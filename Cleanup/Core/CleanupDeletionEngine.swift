import AppKit
import Foundation

enum CleanupExecutionMode: String, Codable, Sendable {
    case dryRun
    case apply
}

enum CleanupExecutionStatus: String, Codable, Sendable {
    case wouldRemove
    case removed
    case movedToTrash
    case privilegedRemoved
    case maintenanceCompleted
    case skipped
    case failed
}

struct CleanupExecutionItemResult: Identifiable, Codable, Sendable {
    let id: UUID
    let candidateID: UUID
    let ruleID: String
    let path: String
    let displayName: String
    let status: CleanupExecutionStatus
    let reclaimedBytes: UInt64
    let message: String

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        ruleID: String,
        path: String,
        displayName: String,
        status: CleanupExecutionStatus,
        reclaimedBytes: UInt64 = 0,
        message: String
    ) {
        self.id = id
        self.candidateID = candidateID
        self.ruleID = ruleID
        self.path = path
        self.displayName = displayName
        self.status = status
        self.reclaimedBytes = reclaimedBytes
        self.message = message
    }
}

struct CleanupExecutionReport: Identifiable, Codable, Sendable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let mode: CleanupExecutionMode
    let results: [CleanupExecutionItemResult]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        mode: CleanupExecutionMode,
        results: [CleanupExecutionItemResult]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.mode = mode
        self.results = results
    }

    var reclaimedBytes: UInt64 {
        results.reduce(0) { partial, result in
            let (value, overflow) = partial.addingReportingOverflow(result.reclaimedBytes)
            return overflow ? UInt64.max : value
        }
    }

    var successfulCount: Int {
        results.filter { [.removed, .movedToTrash, .privilegedRemoved, .maintenanceCompleted].contains($0.status) }.count
    }

    var failureCount: Int {
        results.filter { $0.status == .failed }.count
    }
}

enum CleanupDeletionError: LocalizedError {
    case unknownRule(String)
    case protectedItem
    case explicitConfirmationRequired
    case targetMissing
    case identityMissing
    case identityChanged
    case applicationActive(String)
    case applicationStateUnknown(String)
    case unsupportedMode
    case maintenanceTargetRejected
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unknownRule(let rule): return "Unknown cleanup rule: \(rule)"
        case .protectedItem: return "This item is protected from deletion."
        case .explicitConfirmationRequired: return "This item requires explicit confirmation."
        case .targetMissing: return "The cleanup target no longer exists."
        case .identityMissing: return "The cleanup target identity could not be verified."
        case .identityChanged: return "The cleanup target changed after scanning. Rescan before deleting it."
        case .applicationActive(let name): return "\(name) is still running. Close it before cleanup."
        case .applicationStateUnknown(let name): return "MemWatch could not safely verify that \(name) is inactive. Review it manually."
        case .unsupportedMode: return "This cleanup operation has no approved execution backend."
        case .maintenanceTargetRejected: return "The maintenance target is outside MemWatch's strict Xcode maintenance allowlist."
        case .verificationFailed: return "The cleanup operation returned success but the original target still exists."
        }
    }
}

actor CleanupDeletionEngine {
    private let fileManager: FileManager
    private let catalog: CleanupRuleCatalog
    private let safetyEngine: CleanupSafetyEngine
    private let helperClient: PrivilegedHelperClient
    private let activityGuard: CleanupActivityGuard
    private let maintenanceBackend: CleanupMaintenanceBackend

    init(
        fileManager: FileManager = .default,
        catalog: CleanupRuleCatalog = CleanupRuleCatalog(),
        safetyEngine: CleanupSafetyEngine = CleanupSafetyEngine(),
        helperClient: PrivilegedHelperClient = PrivilegedHelperClient(),
        activityGuard: CleanupActivityGuard = CleanupActivityGuard(),
        maintenanceBackend: CleanupMaintenanceBackend = CleanupMaintenanceBackend()
    ) {
        self.fileManager = fileManager
        self.catalog = catalog
        self.safetyEngine = safetyEngine
        self.helperClient = helperClient
        self.activityGuard = activityGuard
        self.maintenanceBackend = maintenanceBackend
    }

    func execute(
        candidates: [CleanupCandidate],
        context: CleanupScanContext,
        mode: CleanupExecutionMode,
        explicitlyConfirmedIDs: Set<UUID> = []
    ) async -> CleanupExecutionReport {
        let startedAt = Date()
        var results: [CleanupExecutionItemResult] = []

        for candidate in candidates {
            if Task.isCancelled { break }
            do {
                let validated = try validate(
                    candidate,
                    context: context,
                    explicitlyConfirmed: explicitlyConfirmedIDs.contains(candidate.id)
                )

                if mode == .dryRun {
                    results.append(
                        result(
                            validated,
                            status: .wouldRemove,
                            message: "Validated. No files were changed."
                        )
                    )
                    continue
                }

                switch validated.deletionMode {
                case .permanent:
                    let expected = validated.allocatedBytes
                    try fileManager.removeItem(at: validated.url)
                    try verifyOriginalPathRemoved(validated.url)
                    results.append(result(validated, status: .removed, reclaimedBytes: expected, message: "Removed and verified."))

                case .trash:
                    let expected = validated.allocatedBytes
                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: validated.url, resultingItemURL: &resultingURL)
                    try verifyOriginalPathRemoved(validated.url)
                    results.append(result(validated, status: .movedToTrash, reclaimedBytes: expected, message: "Moved to Trash and verified."))

                case .privileged:
                    guard let identity = validated.identity else {
                        throw CleanupDeletionError.identityMissing
                    }
                    let response = try await helperClient.execute(
                        PrivilegedOperationRequest(
                            operation: .removeApprovedPath,
                            ruleID: validated.ruleID.rawValue,
                            path: validated.url.path,
                            expectedIdentity: PrivilegedFileIdentity(
                                deviceID: identity.deviceID,
                                inode: identity.inode,
                                ownerUID: identity.ownerUID,
                                mode: identity.mode
                            )
                        )
                    )
                    try verifyOriginalPathRemoved(validated.url)
                    results.append(result(validated, status: .privilegedRemoved, reclaimedBytes: response.reclaimedBytes, message: response.message))

                case .maintenance:
                    let reclaimed = try maintenanceBackend.execute(validated, context: context)
                    try verifyOriginalPathRemoved(validated.url)
                    results.append(result(validated, status: .maintenanceCompleted, reclaimedBytes: reclaimed, message: "Approved Xcode maintenance target removed and verified."))

                case .none:
                    throw CleanupDeletionError.unsupportedMode
                }
            } catch {
                results.append(result(candidate, status: .failed, message: error.localizedDescription))
            }
        }

        return CleanupExecutionReport(
            startedAt: startedAt,
            finishedAt: Date(),
            mode: mode,
            results: results
        )
    }

    private func validate(
        _ candidate: CleanupCandidate,
        context: CleanupScanContext,
        explicitlyConfirmed: Bool
    ) throws -> CleanupCandidate {
        guard let rule = catalog.rule(for: candidate.ruleID) else {
            throw CleanupDeletionError.unknownRule(candidate.ruleID.rawValue)
        }
        guard candidate.safety != .protected,
              candidate.deletionMode != .none else {
            throw CleanupDeletionError.protectedItem
        }

        guard let scannedIdentity = candidate.identity else {
            throw CleanupDeletionError.identityMissing
        }
        guard fileManager.fileExists(atPath: candidate.url.path) else {
            throw CleanupDeletionError.targetMissing
        }
        guard let currentIdentity = CleanupPathValidator.identity(for: candidate.url) else {
            throw CleanupDeletionError.identityMissing
        }
        guard currentIdentity == scannedIdentity else {
            throw CleanupDeletionError.identityChanged
        }

        let reassessment = safetyEngine.assess(candidate: candidate, rule: rule, context: context)
        guard reassessment.canDelete,
              reassessment.candidate.safety != .protected else {
            throw CleanupDeletionError.protectedItem
        }

        let evaluated = reassessment.candidate
        if evaluated.requirements.contains(.explicitConfirmation), !explicitlyConfirmed {
            throw CleanupDeletionError.explicitConfirmationRequired
        }

        if evaluated.requirements.contains(.applicationInactive) {
            switch activityGuard.state(for: evaluated) {
            case .inactive:
                break
            case .active(let name):
                throw CleanupDeletionError.applicationActive(name)
            case .unknown(let name):
                if !explicitlyConfirmed {
                    throw CleanupDeletionError.applicationStateUnknown(name)
                }
            }
        }

        return evaluated
    }

    private func verifyOriginalPathRemoved(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            throw CleanupDeletionError.verificationFailed
        }
    }

    private func result(
        _ candidate: CleanupCandidate,
        status: CleanupExecutionStatus,
        reclaimedBytes: UInt64 = 0,
        message: String
    ) -> CleanupExecutionItemResult {
        CleanupExecutionItemResult(
            candidateID: candidate.id,
            ruleID: candidate.ruleID.rawValue,
            path: candidate.url.path,
            displayName: candidate.displayName,
            status: status,
            reclaimedBytes: reclaimedBytes,
            message: message
        )
    }
}

struct CleanupMaintenanceBackend: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func execute(_ candidate: CleanupCandidate, context: CleanupScanContext) throws -> UInt64 {
        guard candidate.ruleID.rawValue == "xcode.simulatorcache" else {
            throw CleanupDeletionError.maintenanceTargetRejected
        }

        let developer = context.homeDirectory.appendingPathComponent("Library/Developer", isDirectory: true)
        let coreSimulatorCaches = developer.appendingPathComponent("CoreSimulator/Caches", isDirectory: true).standardizedFileURL.path
        let xctestDevices = developer.appendingPathComponent("XCTestDevices", isDirectory: true).standardizedFileURL.path
        let candidatePath = candidate.url.standardizedFileURL.path

        let isCoreSimulatorCache = CleanupPathValidator.path(candidatePath, isEqualToOrDescendantOf: coreSimulatorCaches)
        let isXCTestDeviceChild = candidatePath != xctestDevices && CleanupPathValidator.path(candidatePath, isEqualToOrDescendantOf: xctestDevices)
        guard isCoreSimulatorCache || isXCTestDeviceChild else {
            throw CleanupDeletionError.maintenanceTargetRejected
        }

        let expected = candidate.allocatedBytes
        try fileManager.removeItem(at: candidate.url)
        return expected
    }
}

enum CleanupApplicationActivityState: Sendable {
    case inactive
    case active(String)
    case unknown(String)
}

struct CleanupActivityGuard: Sendable {
    func state(for candidate: CleanupCandidate) -> CleanupApplicationActivityState {
        if candidate.category == .xcode {
            return running(bundleIdentifiers: ["com.apple.dt.Xcode"], displayName: "Xcode")
        }

        let name = candidate.displayName.lowercased()
        if name.contains("vs code") || candidate.url.path.contains("Application Support/Code") {
            return running(bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], displayName: "Visual Studio Code")
        }
        if name.contains("docker") || candidate.url.path.lowercased().contains("docker") {
            return running(bundleIdentifiers: ["com.docker.docker"], displayName: "Docker Desktop")
        }
        if name.contains("jetbrains") || candidate.url.path.contains("JetBrains") {
            let matches = NSWorkspace.shared.runningApplications.filter {
                ($0.bundleIdentifier ?? "").hasPrefix("com.jetbrains.")
            }
            return matches.isEmpty ? .inactive : .active(matches.first?.localizedName ?? "JetBrains IDE")
        }

        if let identifier = inferredBundleIdentifier(from: candidate.url) {
            let matches = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            if !matches.isEmpty {
                return .active(matches.first?.localizedName ?? identifier)
            }

            let related = NSWorkspace.shared.runningApplications.filter { app in
                guard let bundleID = app.bundleIdentifier else { return false }
                return bundleID == identifier ||
                    bundleID.hasPrefix(identifier + ".") ||
                    identifier.hasPrefix(bundleID + ".")
            }
            return related.isEmpty ? .inactive : .active(related.first?.localizedName ?? identifier)
        }

        return .unknown(candidate.displayName)
    }

    private func running(
        bundleIdentifiers: [String],
        displayName: String
    ) -> CleanupApplicationActivityState {
        let apps = bundleIdentifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
        return apps.isEmpty ? .inactive : .active(apps.first?.localizedName ?? displayName)
    }

    private func inferredBundleIdentifier(from url: URL) -> String? {
        let components = url.standardizedFileURL.pathComponents
        let markers: [[String]] = [
            ["Library", "Caches"],
            ["Library", "Containers"],
            ["Library", "Group Containers"]
        ]

        for marker in markers {
            guard let start = index(of: marker, in: components) else { continue }
            let candidateIndex = start + marker.count
            guard candidateIndex < components.count else { continue }
            var identifier = components[candidateIndex]
            if identifier.hasPrefix("group.") {
                identifier.removeFirst("group.".count)
            }
            guard identifier.contains("."), !identifier.contains("/") else { continue }
            return identifier
        }
        return nil
    }

    private func index(of needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return start
            }
        }
        return nil
    }
}
