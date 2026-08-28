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
    let affectedBytes: UInt64
    let reclaimedBytes: UInt64
    let message: String

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        ruleID: String,
        path: String,
        displayName: String,
        status: CleanupExecutionStatus,
        affectedBytes: UInt64 = 0,
        reclaimedBytes: UInt64 = 0,
        message: String
    ) {
        self.id = id
        self.candidateID = candidateID
        self.ruleID = ruleID
        self.path = path
        self.displayName = displayName
        self.status = status
        self.affectedBytes = affectedBytes
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
    let availableBytesBefore: UInt64?
    let availableBytesAfter: UInt64?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        mode: CleanupExecutionMode,
        results: [CleanupExecutionItemResult],
        availableBytesBefore: UInt64? = nil,
        availableBytesAfter: UInt64? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.mode = mode
        self.results = results
        self.availableBytesBefore = availableBytesBefore
        self.availableBytesAfter = availableBytesAfter
    }

    var reclaimedBytes: UInt64 {
        results.reduce(0) { partial, result in
            let (value, overflow) = partial.addingReportingOverflow(result.reclaimedBytes)
            return overflow ? UInt64.max : value
        }
    }

    var movedToTrashBytes: UInt64 {
        results.filter { $0.status == .movedToTrash }.reduce(0) { partial, result in
            let (value, overflow) = partial.addingReportingOverflow(result.affectedBytes)
            return overflow ? UInt64.max : value
        }
    }

    var observedFreeSpaceDeltaBytes: UInt64? {
        guard mode == .apply, let before = availableBytesBefore, let after = availableBytesAfter else { return nil }
        return after > before ? after - before : 0
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
        let availableBefore = mode == .apply ? startupVolumeAvailableBytes() : nil
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
                            affectedBytes: validated.allocatedBytes,
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
                    results.append(result(validated, status: .removed, affectedBytes: expected, reclaimedBytes: expected, message: "Removed and verified."))

                case .trash:
                    let affected = validated.allocatedBytes
                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: validated.url, resultingItemURL: &resultingURL)
                    try verifyOriginalPathRemoved(validated.url)
                    results.append(result(validated, status: .movedToTrash, affectedBytes: affected, reclaimedBytes: 0, message: "Moved to Trash and verified. Disk space is reclaimed only after Trash is emptied."))

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
                    results.append(result(validated, status: .privilegedRemoved, affectedBytes: validated.allocatedBytes, reclaimedBytes: response.reclaimedBytes, message: response.message))

                case .maintenance:
                    let reclaimed = try maintenanceBackend.execute(validated, context: context)
                    try verifyOriginalPathRemoved(validated.url)
                    results.append(result(validated, status: .maintenanceCompleted, affectedBytes: validated.allocatedBytes, reclaimedBytes: reclaimed, message: "Approved Xcode maintenance target removed and verified."))

                case .none:
                    throw CleanupDeletionError.unsupportedMode
                }
            } catch {
                results.append(result(candidate, status: .failed, affectedBytes: candidate.allocatedBytes, message: error.localizedDescription))
            }
        }

        let availableAfter = mode == .apply ? startupVolumeAvailableBytes() : nil
        return CleanupExecutionReport(
            startedAt: startedAt,
            finishedAt: Date(),
            mode: mode,
            results: results,
            availableBytesBefore: availableBefore,
            availableBytesAfter: availableAfter
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

        if evaluated.requirements.contains(.explicitConfirmation), !explicitlyConfirmed {
            throw CleanupDeletionError.explicitConfirmationRequired
        }

        return evaluated
    }

    private func startupVolumeAvailableBytes() -> UInt64? {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        guard let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let available = values.volumeAvailableCapacity else { return nil }
        return UInt64(max(0, available))
    }

    private func verifyOriginalPathRemoved(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            throw CleanupDeletionError.verificationFailed
        }
    }

    private func result(
        _ candidate: CleanupCandidate,
        status: CleanupExecutionStatus,
        affectedBytes: UInt64 = 0,
        reclaimedBytes: UInt64 = 0,
        message: String
    ) -> CleanupExecutionItemResult {
        CleanupExecutionItemResult(
            candidateID: candidate.id,
            ruleID: candidate.ruleID.rawValue,
            path: candidate.url.path,
            displayName: candidate.displayName,
            status: status,
            affectedBytes: affectedBytes,
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
