import Darwin
import Foundation

struct CleanupScannerID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }
}

struct CleanupRuleID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }
}

enum CleanupCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case userCaches
    case systemCaches
    case logs
    case xcode
    case developer
    case projectArtifacts
    case aiArtifacts
    case applicationLeftovers
    case launchItems
    case iosBackups
    case downloads
    case trash
    case largeOldFiles
    case duplicates
    case similarImages
    case mailAttachments
    case snapshots
    case maintenance

    var id: String { rawValue }
}

enum CleanupSafetyLevel: Int, Codable, Comparable, Sendable {
    case safe = 0
    case review = 1
    case protected = 2

    static func < (lhs: CleanupSafetyLevel, rhs: CleanupSafetyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func moreRestrictive(_ lhs: CleanupSafetyLevel, _ rhs: CleanupSafetyLevel) -> CleanupSafetyLevel {
        max(lhs, rhs)
    }
}

enum CleanupDeletionMode: String, Codable, Sendable {
    case permanent
    case trash
    case privileged
    case maintenance
    case none
}

struct CleanupRequirements: OptionSet, Codable, Sendable {
    let rawValue: Int

    static let fullDiskAccess = CleanupRequirements(rawValue: 1 << 0)
    static let privilegedHelper = CleanupRequirements(rawValue: 1 << 1)
    static let applicationInactive = CleanupRequirements(rawValue: 1 << 2)
    static let explicitConfirmation = CleanupRequirements(rawValue: 1 << 3)
    static let buildInactive = CleanupRequirements(rawValue: 1 << 4)
}

struct CargoTargetVerification: Equatable, Sendable {
    let manifestURLs: [URL]
    let workspaceRoots: [URL]
    let targetDirectory: URL

    init(manifestURLs: [URL], workspaceRoots: [URL], targetDirectory: URL) {
        self.manifestURLs = Self.uniqueStandardizedURLs(manifestURLs)
        self.workspaceRoots = Self.uniqueStandardizedURLs(workspaceRoots)
        self.targetDirectory = targetDirectory.standardizedFileURL
    }

    var isSharedTarget: Bool {
        workspaceRoots.count > 1
    }

    var isInsideWorkspace: Bool {
        workspaceRoots.contains { workspaceRoot in
            let workspacePath = workspaceRoot.path
            let targetPath = targetDirectory.path
            return targetPath != workspacePath && CleanupPathValidator.path(targetPath, isEqualToOrDescendantOf: workspacePath)
        }
    }

    private static func uniqueStandardizedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls
            .map { $0.standardizedFileURL }
            .sorted { $0.path < $1.path }
            .filter { seen.insert($0.path).inserted }
    }
}

struct FileIdentity: Equatable, Codable, Sendable {
    let deviceID: UInt64
    let inode: UInt64
    let ownerUID: UInt32
    let mode: UInt32
    let sizeBytes: UInt64?
    let modificationTimeNanoseconds: Int64?

    init(
        deviceID: UInt64,
        inode: UInt64,
        ownerUID: UInt32,
        mode: UInt32,
        sizeBytes: UInt64? = nil,
        modificationTimeNanoseconds: Int64? = nil
    ) {
        self.deviceID = deviceID
        self.inode = inode
        self.ownerUID = ownerUID
        self.mode = mode
        self.sizeBytes = sizeBytes
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
    }

    var isSymbolicLink: Bool {
        (mode & UInt32(S_IFMT)) == UInt32(S_IFLNK)
    }
}

struct CleanupCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    let scannerID: CleanupScannerID
    let ruleID: CleanupRuleID
    let category: CleanupCategory
    let url: URL
    let displayName: String
    let logicalBytes: UInt64
    let allocatedBytes: UInt64
    let createdAt: Date?
    let modifiedAt: Date?
    let lastAccessedAt: Date?
    let safety: CleanupSafetyLevel
    let deletionMode: CleanupDeletionMode
    let requirements: CleanupRequirements
    let reason: String
    let regenerationHint: String?
    let identity: FileIdentity?
    let policyNotes: [String]
    let cargoTargetVerification: CargoTargetVerification?

    init(
        id: UUID = UUID(),
        scannerID: CleanupScannerID,
        ruleID: CleanupRuleID,
        category: CleanupCategory,
        url: URL,
        displayName: String,
        logicalBytes: UInt64,
        allocatedBytes: UInt64,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        lastAccessedAt: Date? = nil,
        safety: CleanupSafetyLevel,
        deletionMode: CleanupDeletionMode,
        requirements: CleanupRequirements = [],
        reason: String,
        regenerationHint: String? = nil,
        identity: FileIdentity? = nil,
        policyNotes: [String] = [],
        cargoTargetVerification: CargoTargetVerification? = nil
    ) {
        self.id = id
        self.scannerID = scannerID
        self.ruleID = ruleID
        self.category = category
        self.url = url
        self.displayName = displayName
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastAccessedAt = lastAccessedAt
        self.safety = safety
        self.deletionMode = deletionMode
        self.requirements = requirements
        self.reason = reason
        self.regenerationHint = regenerationHint
        self.identity = identity
        self.policyNotes = policyNotes
        self.cargoTargetVerification = cargoTargetVerification
    }

    var isPotentiallyDeletable: Bool {
        safety != .protected && deletionMode != .none
    }

    func applying(
        safety: CleanupSafetyLevel,
        deletionMode: CleanupDeletionMode? = nil,
        requirements: CleanupRequirements? = nil,
        identity: FileIdentity? = nil,
        policyNotes: [String]? = nil,
        cargoTargetVerification: CargoTargetVerification? = nil
    ) -> CleanupCandidate {
        CleanupCandidate(
            id: id,
            scannerID: scannerID,
            ruleID: ruleID,
            category: category,
            url: url,
            displayName: displayName,
            logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            lastAccessedAt: lastAccessedAt,
            safety: safety,
            deletionMode: deletionMode ?? self.deletionMode,
            requirements: requirements ?? self.requirements,
            reason: reason,
            regenerationHint: regenerationHint,
            identity: identity ?? self.identity,
            policyNotes: policyNotes ?? self.policyNotes,
            cargoTargetVerification: cargoTargetVerification ?? self.cargoTargetVerification
        )
    }
}

struct CleanupApplicationCleanupPlan: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let itemIDs: Set<UUID>
    let allocatedBytes: UInt64
}

struct CleanupScanIssue: Identifiable, Equatable, Sendable {
    let id = UUID()
    let scannerID: CleanupScannerID
    let path: String?
    let message: String
}

struct CleanupScanResult: Equatable, Sendable {
    let startedAt: Date
    let finishedAt: Date
    let items: [CleanupCandidate]
    let issues: [CleanupScanIssue]

    var safeBytes: UInt64 {
        items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.allocatedBytes }
    }

    var reviewBytes: UInt64 {
        items.filter { $0.safety == .review }.reduce(0) { $0 + $1.allocatedBytes }
    }

    var protectedBytes: UInt64 {
        items.filter { $0.safety == .protected }.reduce(0) { $0 + $1.allocatedBytes }
    }

    var reclaimableBytes: UInt64 {
        safeBytes + reviewBytes
    }
}

enum CleanupScanProgress: Equatable, Sendable {
    case preparing
    case scanning(scannerID: CleanupScannerID, completed: Int, total: Int)
    case evaluating(scannerID: CleanupScannerID, candidateCount: Int)
    case finishing
}
