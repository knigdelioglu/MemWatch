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

        if Self.protectedRoots.contains(where: { Self.path(path, isEqualToOrDescendantOf: $0) }) {
            return denied(standardized, "Path is inside a protected operating-system root")
        }

        if context.isIgnored(standardized) {
            return denied(standardized, "Path is covered by a cleanup ignore rule")
        }

        guard isInsideAllowedRoot(path: path, rule: rule, context: context) else {
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

        if Self.protectedRoots.contains(where: { Self.path(canonicalURL.path, isEqualToOrDescendantOf: $0) }) {
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

    static func identity(for url: URL) -> FileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }

        return FileIdentity(
            deviceID: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            ownerUID: UInt32(info.st_uid),
            mode: UInt32(info.st_mode)
        )
    }

    private func isInsideAllowedRoot(
        path: String,
        rule: CleanupRule,
        context: CleanupScanContext
    ) -> Bool {
        switch rule.rootPolicy {
        case .userHome:
            return Self.path(path, isEqualToOrDescendantOf: context.homeDirectory.path)

        case .userLibrary:
            return Self.path(
                path,
                isEqualToOrDescendantOf: context.homeDirectory.appendingPathComponent("Library", isDirectory: true).path
            )

        case .temporaryDirectory:
            let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
            return Self.path(path, isEqualToOrDescendantOf: temporary) || Self.path(path, isEqualToOrDescendantOf: "/private/tmp")

        case .systemLibrary:
            return Self.path(path, isEqualToOrDescendantOf: "/Library")

        case .privateVar:
            return Self.allowedPrivateVarRoots.contains { Self.path(path, isEqualToOrDescendantOf: $0) }

        case .projectRoots:
            return context.projectRoots.contains { Self.path(path, isEqualToOrDescendantOf: $0.path) }

        case .requestedRoots:
            return context.requestedRoots.contains { Self.path(path, isEqualToOrDescendantOf: $0.path) }
        }
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
}
