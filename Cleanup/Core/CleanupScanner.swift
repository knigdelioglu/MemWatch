import Foundation

protocol CleanupScanner: Sendable {
    var id: CleanupScannerID { get }
    var category: CleanupCategory { get }

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate]
}

struct CleanupScanContext: Sendable {
    let homeDirectory: URL
    let requestedRoots: [URL]
    let ignoredPaths: Set<String>
    let now: Date
    let fullDiskAccessAvailable: Bool
    let privilegedHelperAvailable: Bool

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        requestedRoots: [URL] = [],
        ignoredPaths: Set<String> = [],
        now: Date = Date(),
        fullDiskAccessAvailable: Bool = false,
        privilegedHelperAvailable: Bool = false
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.requestedRoots = requestedRoots.map(\.standardizedFileURL)
        self.ignoredPaths = ignoredPaths
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
}

enum CleanupScannerError: LocalizedError {
    case inaccessibleRoot(String)
    case malformedMetadata(String)

    var errorDescription: String? {
        switch self {
        case .inaccessibleRoot(let path):
            return "Cleanup scan root is not accessible: \(path)"
        case .malformedMetadata(let path):
            return "Cleanup metadata could not be read: \(path)"
        }
    }
}
