import Darwin
import Foundation

struct CleanupPathValidation: Equatable, Sendable {
    let canonicalURL: URL
    let identity: FileIdentity?
    let isAllowed: Bool
    let reason: String?
}

struct CleanupPathValidator: Sendable {
    private static let protectedRoots: [String] = [
        "/System",
        "/bin",
        "/sbin",
        "/usr/bin",
        "/usr/lib",
        "/usr/libexec",
        "/usr/sbin",
        "/dev",
        "/private/etc",
        "/private/var/db",
        "/private/var/root",
        "/private/var/vm"
    ]

    private static let allowedPrivateVarRoots: [String] = [
        "/private/var/folders",
        "/private/var/tmp",
        "/private/var/log"
    ]

    func validate(
        candidate: CleanupCandidate,
        rule: CleanupRule,
        context: CleanupScanContext
    ) -> CleanupPathValidation {
        let standardized = candidate.url.standardizedFileURL
        guard standardized.isFileURL else {
            return denied(standardized, "Only local file URLs are supported")
        }

        let path = standardized.path
        guard path.hasPrefix("/") else {
            return denied(standardized, "Cleanup path is not absolute")
        }

        if Self.isProtectedOperatingSystemPath(path) {
            return denied(standardized, "Path is inside a protected operating-system root")
        }

        if context.isIgnored(standardized) {
            return denied(standardized, "Path is covered by a cleanup ignore rule")
        }

        guard isInsideAllowedRoot(path: path, candidate: candidate, rule: rule, context: context) else {
            return denied(standardized, "Path is outside the roots allowed by cleanup rule \(rule.id.rawValue)")
        }

        let fileIdentity = Self.identity(for: standardized)
        if let fileIdentity, fileIdentity.isSymbolicLink {
            return CleanupPathValidation(
                canonicalURL: standardized,
                identity: fileIdentity,
                isAllowed: false,
                reason: "Symbolic links are not cleanup targets"
            )
        }

        let canonicalURL = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalURL.path == path else {
            return CleanupPathValidation(
                canonicalURL: canonicalURL,
                identity: fileIdentity,
                isAllowed: false,
                reason: "Cleanup target resolves through a symbolic-link path"
            )
        }

        if Self.isProtectedOperatingSystemPath(canonicalURL.path) {
            return CleanupPathValidation(
                canonicalURL: canonicalURL,
                identity: fileIdentity,
                isAllowed: false,
                reason: "Resolved path enters a protected operating-system root"
            )
        }

        return CleanupPathValidation(
            canonicalURL: canonicalURL,
            identity: fileIdentity,
            isAllowed: true,
            reason: nil
        )
    }

    static func path(_ candidate: String, isEqualToOrDescendantOf root: String) -> Bool {
        let normalizedCandidate = normalizedPath(candidate)
        let normalizedRoot = normalizedPath(root)

        guard normalizedRoot != "/" else { return normalizedCandidate.hasPrefix("/") }
        return normalizedCandidate == normalizedRoot || normalizedCandidate.hasPrefix(normalizedRoot + "/")
    }

    static func isProtectedOperatingSystemPath(_ path: String) -> Bool {
        protectedRoots.contains { Self.path(path, isEqualToOrDescendantOf: $0) }
    }

    static func identity(for url: URL) -> FileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }

        return FileIdentity(
            deviceID: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            ownerUID: UInt32(info.st_uid),
            mode: UInt32(info.st_mode),
            sizeBytes: UInt64(max(0, info.st_size)),
            modificationTimeNanoseconds: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        )
    }

    private func isInsideAllowedRoot(
        path: String,
        candidate: CleanupCandidate,
        rule: CleanupRule,
        context: CleanupScanContext
    ) -> Bool {
        let broadlyAllowed: Bool
        switch rule.rootPolicy {
        case .userHome:
            broadlyAllowed = Self.strictlyInside(path, root: context.homeDirectory.path)

        case .userLibrary:
            broadlyAllowed = Self.strictlyInside(
                path,
                root: context.homeDirectory.appendingPathComponent("Library", isDirectory: true).path
            )

        case .temporaryDirectory:
            let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
            broadlyAllowed = Self.strictlyInside(path, root: temporary) || Self.strictlyInside(path, root: "/private/tmp")

        case .systemLibrary:
            broadlyAllowed = Self.strictlyInside(path, root: "/Library")

        case .privateVar:
            broadlyAllowed = Self.allowedPrivateVarRoots.contains { Self.strictlyInside(path, root: $0) }

        case .projectRoots:
            if rule.id.rawValue == "project.rust.target.verified" {
                broadlyAllowed = Self.isVerifiedCargoTargetAllowed(path: path, candidate: candidate, context: context)
            } else {
                broadlyAllowed = context.projectRoots.contains { Self.strictlyInside(path, root: $0.path) }
            }

        case .requestedRoots:
            broadlyAllowed = context.requestedRoots.contains { Self.strictlyInside(path, root: $0.path) }
        }
        return broadlyAllowed && Self.isApprovedRuleTarget(path: path, candidate: candidate, rule: rule, context: context)
    }

    private static func isApprovedRuleTarget(
        path: String,
        candidate: CleanupCandidate,
        rule: CleanupRule,
        context: CleanupScanContext
    ) -> Bool {
        switch rule.id.rawValue {
        case "user.cache":
            let primary = context.homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true).path
            let containers = context.homeDirectory.appendingPathComponent("Library/Containers", isDirectory: true).path
            let groupContainers = context.homeDirectory.appendingPathComponent("Library/Group Containers", isDirectory: true).path
            return Self.isDirectChild(path, of: primary) ||
                Self.isNamedContainerTarget(path, parent: containers, suffix: ["Data", "Library", "Caches"]) ||
                Self.isNamedContainerTarget(path, parent: groupContainers, suffix: ["Library", "Caches"])

        case "user.log.old":
            let primary = context.homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true).path
            let containers = context.homeDirectory.appendingPathComponent("Library/Containers", isDirectory: true).path
            return Self.isDirectChild(path, of: primary) ||
                Self.isNamedContainerTarget(path, parent: containers, suffix: ["Data", "Library", "Logs"])

        case "system.cache":
            return Self.isDirectChild(path, of: "/Library/Caches") && !Self.isAppleNamed(URL(fileURLWithPath: path).lastPathComponent)
        case "system.log.old":
            return Self.isDirectChild(path, of: "/Library/Logs") && URL(fileURLWithPath: path).lastPathComponent != "DiagnosticReports"
        case "diagnostic.system.old":
            return Self.isDirectChild(path, of: "/Library/Logs/DiagnosticReports")

        case "xcode.deriveddata":
            return Self.strictlyInside(path, root: context.homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true).path)
        case "xcode.modulecache":
            return Self.isExact(path, context.homeDirectory.appendingPathComponent("Library/Developer/Xcode/ModuleCache.noindex", isDirectory: true).path)
        case "xcode.documentationcache":
            return Self.isExact(path, context.homeDirectory.appendingPathComponent("Library/Developer/Xcode/DocumentationCache", isDirectory: true).path)
        case "xcode.swiftpmcache":
            return Self.isExact(path, context.homeDirectory.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true).path)
        case "xcode.previews":
            return Self.isExact(path, context.homeDirectory.appendingPathComponent("Library/Developer/Xcode/UserData/Previews", isDirectory: true).path)
        case "xcode.devicesupport":
            return ["iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport"].contains { name in
                Self.isDirectChild(path, of: context.homeDirectory.appendingPathComponent("Library/Developer/Xcode/\(name)", isDirectory: true).path)
            }
        case "xcode.simulatorcache":
            let simulatorCaches = context.homeDirectory.appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true).path
            let xctestDevices = context.homeDirectory.appendingPathComponent("Library/Developer/XCTestDevices", isDirectory: true).path
            return Self.isDirectChild(path, of: simulatorCaches) ||
                Self.isDirectChild(path, of: xctestDevices)

        case "developer.cache":
            let home = context.homeDirectory
            let roots = [
                home.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true).path,
                home.appendingPathComponent(".npm/_cacache", isDirectory: true).path,
                home.appendingPathComponent(".npm/_logs", isDirectory: true).path,
                home.appendingPathComponent("Library/Caches/Yarn", isDirectory: true).path,
                home.appendingPathComponent(".cache/yarn", isDirectory: true).path,
                home.appendingPathComponent("Library/Caches/pnpm", isDirectory: true).path,
                home.appendingPathComponent("Library/Caches/pip", isDirectory: true).path,
                home.appendingPathComponent(".cache/pip", isDirectory: true).path,
                home.appendingPathComponent("Library/Caches/pypoetry", isDirectory: true).path,
                home.appendingPathComponent(".cache/pypoetry", isDirectory: true).path,
                home.appendingPathComponent(".cache/uv", isDirectory: true).path,
                home.appendingPathComponent(".cargo/registry/cache", isDirectory: true).path,
                home.appendingPathComponent("Library/Caches/go-build", isDirectory: true).path,
                home.appendingPathComponent(".cache/go-build", isDirectory: true).path,
                home.appendingPathComponent("go/pkg/mod/cache", isDirectory: true).path,
                home.appendingPathComponent("Library/Caches/CocoaPods", isDirectory: true).path,
                home.appendingPathComponent(".bun/install/cache", isDirectory: true).path,
                home.appendingPathComponent("Library/Caches/deno", isDirectory: true).path,
                home.appendingPathComponent(".cache/deno", isDirectory: true).path,
                home.appendingPathComponent(".cache/mise", isDirectory: true).path,
                home.appendingPathComponent("Library/Caches/JetBrains", isDirectory: true).path,
                home.appendingPathComponent("Library/Caches/com.docker.docker", isDirectory: true).path,
                home.appendingPathComponent("Library/Application Support/Code/Cache", isDirectory: true).path,
                home.appendingPathComponent("Library/Application Support/Code/CachedData", isDirectory: true).path,
                home.appendingPathComponent("Library/Application Support/Code/CachedExtensionVSIXs", isDirectory: true).path,
                home.appendingPathComponent("Library/Application Support/Code/GPUCache", isDirectory: true).path,
                home.appendingPathComponent("Library/Application Support/Code/Service Worker/CacheStorage", isDirectory: true).path
            ]
            return roots.contains { Self.isExact(path, $0) }

        case "developer.store":
            let home = context.homeDirectory
            let roots = [
                home.appendingPathComponent("Library/pnpm/store", isDirectory: true).path,
                home.appendingPathComponent(".pnpm-store", isDirectory: true).path,
                home.appendingPathComponent(".cargo/git/db", isDirectory: true).path,
                home.appendingPathComponent(".m2/repository", isDirectory: true).path,
                home.appendingPathComponent(".gradle/caches", isDirectory: true).path
            ]
            return roots.contains { Self.isExact(path, $0) }

        case "project.artifact":
            let names: Set<String> = ["node_modules", ".next", ".nuxt", ".turbo", "dist", "build", ".build", ".venv", "venv", "__pycache__", "Pods", "vendor", ".gradle", ".dart_tool"]
            let name = URL(fileURLWithPath: path).lastPathComponent
            return names.contains(name) || name.hasPrefix("cmake-build-")

        case "project.rust.target.verified":
            return Self.isVerifiedCargoTargetAllowed(path: path, candidate: candidate, context: context)

        case "ai.cache":
            return Self.isExact(path, context.homeDirectory.appendingPathComponent(".cache/huggingface/hub/.locks", isDirectory: true).path)
        case "ai.temp":
            return [
                context.homeDirectory.appendingPathComponent(".cache/huggingface/xet", isDirectory: true).path,
                context.homeDirectory.appendingPathComponent(".cache/huggingface/assets", isDirectory: true).path
            ].contains { Self.isExact(path, $0) }

        case "application.leftover.user":
            let library = context.homeDirectory.appendingPathComponent("Library", isDirectory: true)
            return ["Preferences", "Containers", "HTTPStorages", "WebKit", "Saved Application State"].contains {
                Self.isBundleIdentifierChild(path, of: library.appendingPathComponent($0, isDirectory: true).path)
            }
        case "application.leftover.system":
            return ["/Library/Preferences", "/Library/Caches", "/Library/Application Support"].contains {
                Self.isBundleIdentifierChild(path, of: $0)
            }
        case "launchitem.orphan.user":
            return Self.isDirectPlistChild(path, of: context.homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true).path)
        case "diagnostic.user.old":
            return Self.isDirectChild(path, of: context.homeDirectory.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true).path)
        case "launchitem.orphan.system":
            return Self.isDirectPlistChild(path, of: "/Library/LaunchAgents") ||
                Self.isDirectPlistChild(path, of: "/Library/LaunchDaemons")
        case "ios.backup":
            return Self.isDirectChild(path, of: context.homeDirectory.appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true).path)
        case "downloads.review":
            return Self.isDirectChild(path, of: context.homeDirectory.appendingPathComponent("Downloads", isDirectory: true).path)
        case "trash.user":
            return Self.isDirectChild(path, of: context.homeDirectory.appendingPathComponent(".Trash", isDirectory: true).path)
        case "mail.attachment.cache":
            return Self.isDirectChild(path, of: context.homeDirectory.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", isDirectory: true).path)
        default:
            return true
        }
    }

    private static func isVerifiedCargoTargetAllowed(
        path: String,
        candidate: CleanupCandidate,
        context: CleanupScanContext
    ) -> Bool {
        guard let verification = candidate.cargoTargetVerification,
              normalizedPath(path) == normalizedPath(verification.targetDirectory.path),
              !verification.manifestURLs.isEmpty,
              !verification.workspaceRoots.isEmpty else {
            return false
        }

        let discoveredUnderConfiguredRoot = verification.manifestURLs.allSatisfy { manifest in
            guard manifest.lastPathComponent == "Cargo.toml" else { return false }
            let manifestDirectory = manifest.deletingLastPathComponent().path
            return context.projectRoots.contains { projectRoot in
                Self.path(manifestDirectory, isEqualToOrDescendantOf: projectRoot.path)
            }
        }
        guard discoveredUnderConfiguredRoot else { return false }

        let manifestsBelongToWorkspace = verification.manifestURLs.allSatisfy { manifest in
            let manifestDirectory = manifest.deletingLastPathComponent().path
            return verification.workspaceRoots.contains { workspaceRoot in
                Self.path(manifestDirectory, isEqualToOrDescendantOf: workspaceRoot.path)
            }
        }
        guard manifestsBelongToWorkspace else { return false }
        guard !isStructuralCargoTarget(path, verification: verification, context: context) else { return false }

        return true
    }

    private static func isStructuralCargoTarget(
        _ path: String,
        verification: CargoTargetVerification,
        context: CleanupScanContext
    ) -> Bool {
        let normalized = normalizedPath(path)
        if normalized == "/" || normalized == normalizedPath(context.homeDirectory.path) {
            return true
        }

        let configuredRoots = context.projectRoots.map { $0.path }
        let workspaceRoots = verification.workspaceRoots.map { $0.path }
        if (configuredRoots + workspaceRoots).contains(where: { normalized == normalizedPath($0) }) {
            return true
        }

        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: []
        ) ?? []
        return mountedVolumes.contains { normalized == normalizedPath($0.path) }
    }

    private static func isNamedContainerTarget(
        _ path: String,
        parent: String,
        suffix: [String]
    ) -> Bool {
        let pathComponents = URL(fileURLWithPath: normalizedPath(path)).pathComponents
        let parentComponents = URL(fileURLWithPath: normalizedPath(parent)).pathComponents
        guard pathComponents.count == parentComponents.count + 1 + suffix.count,
              Array(pathComponents.prefix(parentComponents.count)) == parentComponents else {
            return false
        }

        let relative = Array(pathComponents.dropFirst(parentComponents.count))
        return isBundleIdentifier(relative[0]) && Array(relative.dropFirst().prefix(suffix.count)) == suffix
    }

    private static func isExact(_ path: String, _ root: String) -> Bool {
        normalizedPath(path) == normalizedPath(root)
    }

    private static func isDirectChild(_ path: String, of root: String) -> Bool {
        let candidateComponents = URL(fileURLWithPath: normalizedPath(path)).pathComponents
        let rootComponents = URL(fileURLWithPath: normalizedPath(root)).pathComponents
        return candidateComponents.count == rootComponents.count + 1 &&
            Array(candidateComponents.dropLast()) == rootComponents
    }

    private static func isDirectPlistChild(_ path: String, of root: String) -> Bool {
        isDirectChild(path, of: root) && URL(fileURLWithPath: path).pathExtension.lowercased() == "plist"
    }

    private static func isBundleIdentifierChild(_ path: String, of root: String) -> Bool {
        isDirectChild(path, of: root) && isBundleIdentifier(URL(fileURLWithPath: path).lastPathComponent)
    }

    private static func isBundleIdentifier(_ value: String) -> Bool {
        var identifier = value
        for suffix in [".savedState", ".plist"] where identifier.hasSuffix(suffix) {
            identifier.removeLast(suffix.count)
        }
        let components = identifier.split(separator: ".")
        return identifier.count >= 5 &&
            components.count >= 2 &&
            !isAppleNamed(identifier) &&
            components.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }

    private static func isAppleNamed(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("com.apple.") ||
            lower.hasPrefix("group.com.apple.") ||
            lower == "apple" ||
            lower.hasPrefix("apple.")
    }

    private func denied(_ url: URL, _ reason: String) -> CleanupPathValidation {
        CleanupPathValidation(
            canonicalURL: url,
            identity: Self.identity(for: url),
            isAllowed: false,
            reason: reason
        )
    }

    private static func normalizedPath(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized.count > 1, standardized.hasSuffix("/") else { return standardized }
        return String(standardized.dropLast())
    }

    private static func strictlyInside(_ candidate: String, root: String) -> Bool {
        let candidate = normalizedPath(candidate)
        let root = normalizedPath(root)
        return candidate != root && Self.path(candidate, isEqualToOrDescendantOf: root)
    }
}
