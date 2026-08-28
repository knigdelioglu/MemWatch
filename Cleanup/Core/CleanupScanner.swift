import Foundation

protocol CleanupScanner: Sendable {
    var id: CleanupScannerID { get }
    var category: CleanupCategory { get }
    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate]
}

struct CleanupScanContext: Sendable {
    let homeDirectory: URL
    let requestedRoots: [URL]
    let projectRoots: [URL]
    let ignoredPaths: Set<String>
    let now: Date
    let fullDiskAccessAvailable: Bool
    let privilegedHelperAvailable: Bool

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        requestedRoots: [URL] = [],
        projectRoots: [URL]? = nil,
        ignoredPaths: Set<String> = [],
        now: Date = Date(),
        fullDiskAccessAvailable: Bool = false,
        privilegedHelperAvailable: Bool = false
    ) {
        let standardizedHome = homeDirectory.standardizedFileURL
        self.homeDirectory = standardizedHome
        self.requestedRoots = requestedRoots.map(\.standardizedFileURL)
        self.projectRoots = (projectRoots ?? Self.defaultProjectRoots(homeDirectory: standardizedHome)).map(\.standardizedFileURL)
        self.ignoredPaths = Set(ignoredPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        self.now = now
        self.fullDiskAccessAvailable = fullDiskAccessAvailable
        self.privilegedHelperAvailable = privilegedHelperAvailable
    }

    func isIgnored(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        return ignoredPaths.contains { ignored in
            CleanupPathValidator.path(candidate, isEqualToOrDescendantOf: ignored)
        }
    }

    private static func defaultProjectRoots(homeDirectory: URL) -> [URL] {
        ["Projects", "Code", "dev", "GitHub", "Workspace"].map {
            homeDirectory.appendingPathComponent($0, isDirectory: true)
        }
    }
}

enum CleanupScannerError: LocalizedError {
    case inaccessibleRoot(String)
    case malformedMetadata(String)

    var errorDescription: String? {
        switch self {
        case .inaccessibleRoot(let path): return "Cleanup scan root is not accessible: \(path)"
        case .malformedMetadata(let path): return "Cleanup metadata could not be read: \(path)"
        }
    }
}

struct CleanupScannerSupport: Sendable {
    private let sizer = CleanupFileSizer()

    func candidate(
        url: URL,
        scannerID: CleanupScannerID,
        ruleID: CleanupRuleID,
        category: CleanupCategory,
        displayName: String? = nil,
        safety: CleanupSafetyLevel,
        deletionMode: CleanupDeletionMode,
        requirements: CleanupRequirements = [],
        reason: String,
        regenerationHint: String? = nil
    ) -> CleanupCandidate? {
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else { return nil }
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .contentAccessDateKey, .isSymbolicLinkKey]
        let values = try? standardized.resourceValues(forKeys: keys)
        if values?.isSymbolicLink == true { return nil }
        let size = sizer.measure(standardized)
        return CleanupCandidate(
            scannerID: scannerID,
            ruleID: ruleID,
            category: category,
            url: standardized,
            displayName: displayName ?? standardized.lastPathComponent,
            logicalBytes: size.logicalBytes,
            allocatedBytes: size.allocatedBytes,
            createdAt: values?.creationDate,
            modifiedAt: values?.contentModificationDate,
            lastAccessedAt: values?.contentAccessDate,
            safety: safety,
            deletionMode: deletionMode,
            requirements: requirements,
            reason: reason,
            regenerationHint: regenerationHint,
            identity: CleanupPathValidator.identity(for: standardized)
        )
    }

    func immediateChildren(of root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )) ?? []
    }
}

struct UserCacheScanner: CleanupScanner {
    let id: CleanupScannerID = "user-cache"
    let category: CleanupCategory = .userCaches
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        var results: [CleanupCandidate] = []
        let library = context.homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let primaryCache = library.appendingPathComponent("Caches", isDirectory: true)
        for url in support.immediateChildren(of: primaryCache) where !context.isIgnored(url) {
            try Task.checkCancellation()
            if let item = support.candidate(url: url, scannerID: id, ruleID: "user.cache", category: category, safety: .safe, deletionMode: .permanent, requirements: [.applicationInactive], reason: "Application cache under ~/Library/Caches", regenerationHint: "The owning application can recreate this cache.") {
                results.append(item)
            }
        }
        let containers = library.appendingPathComponent("Containers", isDirectory: true)
        for container in support.immediateChildren(of: containers) {
            try Task.checkCancellation()
            let cache = container.appendingPathComponent("Data/Library/Caches", isDirectory: true)
            guard !context.isIgnored(cache) else { continue }
            if let item = support.candidate(url: cache, scannerID: id, ruleID: "user.cache", category: category, displayName: "\(container.lastPathComponent) cache", safety: .safe, deletionMode: .permanent, requirements: [.applicationInactive], reason: "Sandbox application cache", regenerationHint: "The sandboxed application can recreate this cache."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        let groupContainers = library.appendingPathComponent("Group Containers", isDirectory: true)
        for group in support.immediateChildren(of: groupContainers) {
            try Task.checkCancellation()
            let cache = group.appendingPathComponent("Library/Caches", isDirectory: true)
            guard !context.isIgnored(cache) else { continue }
            if let item = support.candidate(url: cache, scannerID: id, ruleID: "user.cache", category: category, displayName: "\(group.lastPathComponent) shared cache", safety: .safe, deletionMode: .permanent, requirements: [.applicationInactive], reason: "Application-group cache", regenerationHint: "Applications in the group can recreate this cache."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        return results
    }
}

struct UserLogScanner: CleanupScanner {
    let id: CleanupScannerID = "user-log"
    let category: CleanupCategory = .logs
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        var results: [CleanupCandidate] = []
        let library = context.homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let primaryLogs = library.appendingPathComponent("Logs", isDirectory: true)
        for url in support.immediateChildren(of: primaryLogs) where !context.isIgnored(url) {
            try Task.checkCancellation()
            if let item = support.candidate(url: url, scannerID: id, ruleID: "user.log.old", category: category, safety: .safe, deletionMode: .permanent, reason: "User application log", regenerationHint: "Logs are diagnostic output and may be recreated.") {
                results.append(item)
            }
        }
        let containers = library.appendingPathComponent("Containers", isDirectory: true)
        for container in support.immediateChildren(of: containers) {
            try Task.checkCancellation()
            let logs = container.appendingPathComponent("Data/Library/Logs", isDirectory: true)
            guard !context.isIgnored(logs) else { continue }
            if let item = support.candidate(url: logs, scannerID: id, ruleID: "user.log.old", category: category, displayName: "\(container.lastPathComponent) logs", safety: .safe, deletionMode: .permanent, reason: "Sandbox application logs", regenerationHint: "The application can create new logs when needed."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        return results
    }
}

struct XcodeCleanupScanner: CleanupScanner {
    let id: CleanupScannerID = "xcode-cleanup"
    let category: CleanupCategory = .xcode
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let library = context.homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let developer = library.appendingPathComponent("Developer", isDirectory: true)
        let xcode = developer.appendingPathComponent("Xcode", isDirectory: true)
        var results: [CleanupCandidate] = []
        results.append(contentsOf: children(root: xcode.appendingPathComponent("DerivedData", isDirectory: true), ruleID: "xcode.deriveddata", safety: .safe, deletionMode: .permanent, reason: "Generated Xcode build/index data", context: context))
        let simpleTargets: [(URL, CleanupRuleID, CleanupSafetyLevel, CleanupDeletionMode, String)] = [
            (xcode.appendingPathComponent("ModuleCache.noindex", isDirectory: true), "xcode.modulecache", .safe, .permanent, "Generated Xcode module cache"),
            (xcode.appendingPathComponent("DocumentationCache", isDirectory: true), "xcode.documentationcache", .safe, .permanent, "Downloaded/generated Xcode documentation cache"),
            (library.appendingPathComponent("Caches/org.swift.swiftpm", isDirectory: true), "xcode.swiftpmcache", .safe, .permanent, "Swift Package Manager cache"),
            (xcode.appendingPathComponent("UserData/Previews", isDirectory: true), "xcode.previews", .safe, .permanent, "Generated SwiftUI/Xcode preview artifacts"),
            (developer.appendingPathComponent("CoreSimulator/Caches", isDirectory: true), "xcode.simulatorcache", .review, .maintenance, "CoreSimulator cache; cleanup should use simulator-aware maintenance")
        ]
        for (url, ruleID, safety, deletionMode, reason) in simpleTargets {
            try Task.checkCancellation()
            guard !context.isIgnored(url) else { continue }
            if let item = support.candidate(url: url, scannerID: id, ruleID: ruleID, category: category, safety: safety, deletionMode: deletionMode, requirements: deletionMode == .maintenance ? [.explicitConfirmation, .applicationInactive] : [.applicationInactive], reason: reason, regenerationHint: "Xcode or its command-line tools can recreate this data."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        for folderName in ["iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport"] {
            try Task.checkCancellation()
            results.append(contentsOf: children(root: xcode.appendingPathComponent(folderName, isDirectory: true), ruleID: "xcode.devicesupport", safety: .review, deletionMode: .permanent, reason: "\(folderName) version support files", context: context))
        }
        results.append(contentsOf: children(root: developer.appendingPathComponent("XCTestDevices", isDirectory: true), ruleID: "xcode.simulatorcache", safety: .review, deletionMode: .maintenance, reason: "Generated XCTest device data", context: context))
        return results
    }

    private func children(root: URL, ruleID: CleanupRuleID, safety: CleanupSafetyLevel, deletionMode: CleanupDeletionMode, reason: String, context: CleanupScanContext) -> [CleanupCandidate] {
        support.immediateChildren(of: root).compactMap { child in
            guard !context.isIgnored(child) else { return nil }
            return support.candidate(url: child, scannerID: id, ruleID: ruleID, category: category, safety: safety, deletionMode: deletionMode, requirements: deletionMode == .maintenance ? [.explicitConfirmation, .applicationInactive] : [.applicationInactive], reason: reason, regenerationHint: "Xcode can recreate or redownload this data when it is needed again.")
        }
    }
}

struct DeveloperCacheScanner: CleanupScanner {
    let id: CleanupScannerID = "developer-cache"
    let category: CleanupCategory = .developer
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let home = context.homeDirectory
        var results: [CleanupCandidate] = []
        let cacheTargets: [(String, URL, CleanupSafetyLevel, CleanupRequirements)] = [
            ("Homebrew cache", home.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true), .safe, []),
            ("npm cache", home.appendingPathComponent(".npm/_cacache", isDirectory: true), .safe, []),
            ("npm logs", home.appendingPathComponent(".npm/_logs", isDirectory: true), .safe, []),
            ("Yarn cache", home.appendingPathComponent("Library/Caches/Yarn", isDirectory: true), .safe, []),
            ("Yarn cache", home.appendingPathComponent(".cache/yarn", isDirectory: true), .safe, []),
            ("pnpm cache", home.appendingPathComponent("Library/Caches/pnpm", isDirectory: true), .safe, []),
            ("pip cache", home.appendingPathComponent("Library/Caches/pip", isDirectory: true), .safe, []),
            ("pip cache", home.appendingPathComponent(".cache/pip", isDirectory: true), .safe, []),
            ("Poetry cache", home.appendingPathComponent("Library/Caches/pypoetry", isDirectory: true), .safe, []),
            ("Poetry cache", home.appendingPathComponent(".cache/pypoetry", isDirectory: true), .safe, []),
            ("uv cache", home.appendingPathComponent(".cache/uv", isDirectory: true), .safe, []),
            ("Cargo registry cache", home.appendingPathComponent(".cargo/registry/cache", isDirectory: true), .safe, []),
            ("Go build cache", home.appendingPathComponent("Library/Caches/go-build", isDirectory: true), .safe, []),
            ("Go build cache", home.appendingPathComponent(".cache/go-build", isDirectory: true), .safe, []),
            ("Go module download cache", home.appendingPathComponent("go/pkg/mod/cache", isDirectory: true), .safe, []),
            ("CocoaPods cache", home.appendingPathComponent("Library/Caches/CocoaPods", isDirectory: true), .safe, []),
            ("Bun install cache", home.appendingPathComponent(".bun/install/cache", isDirectory: true), .safe, []),
            ("Deno cache", home.appendingPathComponent("Library/Caches/deno", isDirectory: true), .safe, []),
            ("Deno cache", home.appendingPathComponent(".cache/deno", isDirectory: true), .safe, []),
            ("mise cache", home.appendingPathComponent(".cache/mise", isDirectory: true), .safe, []),
            ("JetBrains cache", home.appendingPathComponent("Library/Caches/JetBrains", isDirectory: true), .review, [.applicationInactive, .explicitConfirmation]),
            ("Docker Desktop cache", home.appendingPathComponent("Library/Caches/com.docker.docker", isDirectory: true), .review, [.applicationInactive, .explicitConfirmation])
        ]
        for (name, url, safety, requirements) in cacheTargets {
            try Task.checkCancellation()
            guard !context.isIgnored(url) else { continue }
            if let item = support.candidate(url: url, scannerID: id, ruleID: "developer.cache", category: category, displayName: name, safety: safety, deletionMode: .permanent, requirements: requirements, reason: "Regenerable developer-tool cache", regenerationHint: "The developer tool can rebuild or redownload this cache."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        let vscodeRoot = home.appendingPathComponent("Library/Application Support/Code", isDirectory: true)
        for component in ["Cache", "CachedData", "CachedExtensionVSIXs", "GPUCache", "Service Worker/CacheStorage"] {
            try Task.checkCancellation()
            let url = vscodeRoot.appendingPathComponent(component, isDirectory: true)
            guard !context.isIgnored(url) else { continue }
            if let item = support.candidate(url: url, scannerID: id, ruleID: "developer.cache", category: category, displayName: "VS Code \(component)", safety: .review, deletionMode: .permanent, requirements: [.applicationInactive, .explicitConfirmation], reason: "VS Code generated cache", regenerationHint: "VS Code can recreate this cache after restart."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        let storeTargets: [(String, URL)] = [
            ("pnpm store", home.appendingPathComponent("Library/pnpm/store", isDirectory: true)),
            ("pnpm store", home.appendingPathComponent(".pnpm-store", isDirectory: true)),
            ("Cargo git database", home.appendingPathComponent(".cargo/git/db", isDirectory: true)),
            ("Maven local repository", home.appendingPathComponent(".m2/repository", isDirectory: true)),
            ("Gradle caches", home.appendingPathComponent(".gradle/caches", isDirectory: true))
        ]
        for (name, url) in storeTargets {
            try Task.checkCancellation()
            guard !context.isIgnored(url) else { continue }
            if let item = support.candidate(url: url, scannerID: id, ruleID: "developer.store", category: category, displayName: name, safety: .review, deletionMode: .permanent, requirements: [.explicitConfirmation], reason: "Regenerable dependency/package store", regenerationHint: "Deleting this can reclaim substantial space but may require a large re-download."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        return results
    }
}

struct ProjectArtifactScanner: CleanupScanner {
    let id: CleanupScannerID = "project-artifact"
    let category: CleanupCategory = .projectArtifacts
    private let support = CleanupScannerSupport()
    private let exactArtifactNames: Set<String> = ["node_modules", ".next", ".nuxt", ".turbo", "dist", "build", "target", ".build", ".venv", "venv", "__pycache__", "Pods", "vendor", ".gradle", ".dart_tool"]
    private let excludedTraversalNames: Set<String> = [".git", ".hg", ".svn"]

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        var results: [CleanupCandidate] = []
        for root in context.projectRoots {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: root.path), !context.isIgnored(root) else { continue }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { continue }
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isDirectory == true else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                let name = url.lastPathComponent
                if excludedTraversalNames.contains(name) { enumerator.skipDescendants(); continue }
                guard exactArtifactNames.contains(name) || name.hasPrefix("cmake-build-") else { continue }
                enumerator.skipDescendants()
                guard !context.isIgnored(url) else { continue }
                if let item = support.candidate(url: url, scannerID: id, ruleID: "project.artifact", category: category, displayName: url.path.replacingOccurrences(of: root.path + "/", with: ""), safety: .review, deletionMode: .permanent, requirements: [.explicitConfirmation], reason: artifactReason(name), regenerationHint: regenerationHint(name)), item.allocatedBytes > 0 {
                    results.append(item)
                }
            }
        }
        return results
    }

    private func artifactReason(_ name: String) -> String {
        switch name {
        case "node_modules", "Pods", "vendor", ".venv", "venv": return "Project dependency artifact"
        case "__pycache__": return "Generated Python bytecode cache"
        default: return "Generated project build artifact"
        }
    }

    private func regenerationHint(_ name: String) -> String {
        switch name {
        case "node_modules": return "Restore with the project's npm/Yarn/pnpm install command."
        case "Pods": return "Restore with CocoaPods."
        case ".venv", "venv": return "Recreate the Python virtual environment and dependencies."
        case "target": return "Rust/Cargo or another build system can regenerate this directory."
        case ".build": return "SwiftPM or the project's build system can regenerate this directory."
        default: return "The project's build/dependency tool can regenerate this directory."
        }
    }
}

struct AIArtifactScanner: CleanupScanner {
    let id: CleanupScannerID = "ai-artifact"
    let category: CleanupCategory = .aiArtifacts
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let home = context.homeDirectory
        var results: [CleanupCandidate] = []
        let protectedModelRoots: [(String, URL)] = [
            ("Ollama models", home.appendingPathComponent(".ollama/models", isDirectory: true)),
            ("LM Studio models", home.appendingPathComponent(".cache/lm-studio/models", isDirectory: true)),
            ("LM Studio models", home.appendingPathComponent(".lmstudio/models", isDirectory: true)),
            ("Whisper models", home.appendingPathComponent(".cache/whisper", isDirectory: true)),
            ("PyTorch hub/checkpoints", home.appendingPathComponent(".cache/torch/hub", isDirectory: true)),
            ("MLX cache/models", home.appendingPathComponent(".cache/mlx", isDirectory: true)),
            ("Jan models", home.appendingPathComponent("Library/Application Support/Jan/models", isDirectory: true))
        ]
        for (name, url) in protectedModelRoots {
            try Task.checkCancellation()
            guard !context.isIgnored(url) else { continue }
            if let item = support.candidate(url: url, scannerID: id, ruleID: "ai.model", category: category, displayName: name, safety: .protected, deletionMode: .none, reason: "Downloaded local AI model data", regenerationHint: "Models are user-managed downloads and are never part of automatic cleanup."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        let hub = home.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
        for child in support.immediateChildren(of: hub) {
            try Task.checkCancellation()
            guard !context.isIgnored(child) else { continue }
            let metadata = child.lastPathComponent == ".locks"
            if let item = support.candidate(url: child, scannerID: id, ruleID: metadata ? "ai.cache" : "ai.model", category: category, displayName: metadata ? "Hugging Face locks/cache metadata" : "Hugging Face: \(child.lastPathComponent)", safety: metadata ? .safe : .protected, deletionMode: metadata ? .permanent : .none, reason: metadata ? "Regenerable Hugging Face cache metadata" : "Hugging Face downloaded model/dataset repository", regenerationHint: metadata ? nil : "This content is intentionally protected from automatic cleanup."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        let reviewCaches: [(String, URL)] = [
            ("Hugging Face Xet cache", home.appendingPathComponent(".cache/huggingface/xet", isDirectory: true)),
            ("Hugging Face assets cache", home.appendingPathComponent(".cache/huggingface/assets", isDirectory: true))
        ]
        for (name, url) in reviewCaches {
            try Task.checkCancellation()
            guard !context.isIgnored(url) else { continue }
            if let item = support.candidate(url: url, scannerID: id, ruleID: "ai.temp", category: category, displayName: name, safety: .review, deletionMode: .permanent, requirements: [.explicitConfirmation], reason: "AI download/cache transport data", regenerationHint: "The tool can recreate this cache, but doing so may cause network activity."), item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        return results
    }
}

struct DownloadsScanner: CleanupScanner {
    let id: CleanupScannerID = "downloads"
    let category: CleanupCategory = .downloads
    private let support = CleanupScannerSupport()
    private let reviewExtensions: Set<String> = ["dmg", "pkg", "mpkg", "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso", "crdownload", "part", "partial", "download"]

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let downloads = context.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        var results: [CleanupCandidate] = []
        for url in support.immediateChildren(of: downloads) {
            try Task.checkCancellation()
            guard !context.isIgnored(url) else { continue }
            let ext = url.pathExtension.lowercased()
            guard reviewExtensions.contains(ext) else { continue }
            let reason: String
            if ["crdownload", "part", "partial", "download"].contains(ext) { reason = "Partial or incomplete download" }
            else if ["dmg", "pkg", "mpkg", "iso"].contains(ext) { reason = "Downloaded installer or disk image" }
            else { reason = "Downloaded archive" }
            if let item = support.candidate(url: url, scannerID: id, ruleID: "downloads.review", category: category, safety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], reason: reason, regenerationHint: "Personal downloads are never included in automatic safe cleanup.") {
                results.append(item)
            }
        }
        return results
    }
}

struct TrashScanner: CleanupScanner {
    let id: CleanupScannerID = "trash"
    let category: CleanupCategory = .trash
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let trash = context.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        var results: [CleanupCandidate] = []
        for url in support.immediateChildren(of: trash) {
            try Task.checkCancellation()
            guard !context.isIgnored(url) else { continue }
            if let item = support.candidate(url: url, scannerID: id, ruleID: "trash.user", category: category, safety: .review, deletionMode: .permanent, requirements: [.explicitConfirmation], reason: "Item is already in the user's Trash", regenerationHint: "Emptying Trash is permanent.") {
                results.append(item)
            }
        }
        return results
    }
}

struct IOSBackupScanner: CleanupScanner {
    let id: CleanupScannerID = "ios-backup"
    let category: CleanupCategory = .iosBackups
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let backupRoot = context.homeDirectory.appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true)
        var results: [CleanupCandidate] = []
        for backup in support.immediateChildren(of: backupRoot) {
            try Task.checkCancellation()
            guard !context.isIgnored(backup) else { continue }
            let metadata = readMetadata(from: backup.appendingPathComponent("Info.plist"))
            let deviceName = metadata["Device Name"] as? String
            let productVersion = metadata["Product Version"] as? String
            let lastBackupDate = metadata["Last Backup Date"] as? Date
            var display = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if display?.isEmpty != false { display = "Apple device backup \(backup.lastPathComponent.prefix(8))…" }
            if let productVersion, !productVersion.isEmpty { display = "\(display ?? "Apple device backup") · iOS \(productVersion)" }
            var reason = "Local iPhone/iPad backup"
            if let lastBackupDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                reason += " · last backup \(formatter.string(from: lastBackupDate))"
            }
            if let item = support.candidate(url: backup, scannerID: id, ruleID: "ios.backup", category: category, displayName: display, safety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], reason: reason, regenerationHint: "Deleting this removes the local backup; it is never part of automatic safe cleanup.") {
                results.append(item)
            }
        }
        return results
    }

    private func readMetadata(from url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url), let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil), let dictionary = plist as? [String: Any] else { return [:] }
        return dictionary
    }
}

enum CleanupScannerRegistry {
    static var userSpaceScanners: [any CleanupScanner] {
        [UserCacheScanner(), UserLogScanner(), XcodeCleanupScanner(), DeveloperCacheScanner(), ProjectArtifactScanner(), AIArtifactScanner(), DownloadsScanner(), TrashScanner(), IOSBackupScanner()]
    }
}
