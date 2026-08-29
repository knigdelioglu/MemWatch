import Foundation

private extension CleanupSecureNodeIdentity {
    init(_ identity: FileIdentity) {
        self.init(
            deviceID: identity.deviceID,
            inode: identity.inode,
            ownerUID: identity.ownerUID,
            mode: identity.mode,
            sizeBytes: identity.sizeBytes,
            modificationTimeNanoseconds: identity.modificationTimeNanoseconds
        )
    }
}

enum CleanupExecutionMode: String, Codable, Sendable {
    case dryRun
    case apply
}

enum CleanupExecutionOutcome: String, Codable, Sendable {
    case completed
    case cancelled
}

enum CleanupReclaimVerification: String, Codable, Sendable {
    case notMeasured
    case verified
    case noNetIncrease
    case unavailable
    case notApplicable
    case cancelled
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
    let requestedCount: Int
    let outcome: CleanupExecutionOutcome
    let results: [CleanupExecutionItemResult]
    let availableBytesBefore: UInt64?
    let availableBytesAfter: UInt64?
    let volumeAvailableBytesBefore: [String: UInt64]?
    let volumeAvailableBytesAfter: [String: UInt64]?
    let reclaimVerification: CleanupReclaimVerification

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        mode: CleanupExecutionMode,
        results: [CleanupExecutionItemResult],
        requestedCount: Int? = nil,
        outcome: CleanupExecutionOutcome = .completed,
        availableBytesBefore: UInt64? = nil,
        availableBytesAfter: UInt64? = nil,
        volumeAvailableBytesBefore: [String: UInt64]? = nil,
        volumeAvailableBytesAfter: [String: UInt64]? = nil,
        reclaimVerification: CleanupReclaimVerification = .notMeasured
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.mode = mode
        self.requestedCount = requestedCount ?? results.count
        self.outcome = outcome
        self.results = results
        self.availableBytesBefore = availableBytesBefore
        self.availableBytesAfter = availableBytesAfter
        self.volumeAvailableBytesBefore = volumeAvailableBytesBefore
        self.volumeAvailableBytesAfter = volumeAvailableBytesAfter
        self.reclaimVerification = reclaimVerification
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
        guard mode == .apply else { return nil }
        if let before = volumeAvailableBytesBefore,
           let after = volumeAvailableBytesAfter,
           !before.isEmpty || !after.isEmpty {
            return before.reduce(0) { partial, entry in
                guard let afterValue = after[entry.key], afterValue > entry.value else { return partial }
                let delta = afterValue - entry.value
                let (value, overflow) = partial.addingReportingOverflow(delta)
                return overflow ? UInt64.max : value
            }
        }
        guard let before = availableBytesBefore, let after = availableBytesAfter else { return nil }
        return after > before ? after - before : 0
    }

    var isCancelled: Bool {
        outcome == .cancelled
    }

    var verifiedReclaimedBytes: UInt64? {
        reclaimVerification == .verified ? observedFreeSpaceDeltaBytes : nil
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
    case maintenanceUnavailable(String)
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
        case .maintenanceUnavailable(let message): return "Simulator-aware maintenance could not be verified: \(message)"
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
        let measuredVolumes = mode == .apply ? volumeURLs(for: candidates.map(\.url)) : [:]
        let volumeAvailableBefore = mode == .apply ? volumeAvailableBytes(for: measuredVolumes) : nil
        let availableBefore = mode == .apply ? startupVolumeAvailableBytes() : nil
        var results: [CleanupExecutionItemResult] = []
        var outcome: CleanupExecutionOutcome = .completed

        for candidate in candidates {
            if Task.isCancelled {
                outcome = .cancelled
                break
            }
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
                    guard let identity = validated.identity else {
                        throw CleanupDeletionError.identityMissing
                    }
                    try CleanupSecureFileOperations.remove(
                        atPath: validated.url.path,
                        expectedIdentity: CleanupSecureNodeIdentity(identity),
                        cancellationCheck: { try Task.checkCancellation() }
                    )
                    try verifyOriginalPathRemoved(validated.url)
                    results.append(result(validated, status: .removed, affectedBytes: expected, reclaimedBytes: expected, message: "Removed and verified."))

                case .trash:
                    let affected = validated.allocatedBytes
                    guard let identity = validated.identity else {
                        throw CleanupDeletionError.identityMissing
                    }
                    try CleanupSecureFileOperations.moveToTrash(
                        atPath: validated.url.path,
                        expectedIdentity: CleanupSecureNodeIdentity(identity),
                        trashDirectoryPath: try trashDirectory(for: validated.url, context: context).path
                    )
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
                                mode: identity.mode,
                                sizeBytes: identity.sizeBytes,
                                modificationTimeNanoseconds: identity.modificationTimeNanoseconds
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
            } catch is CancellationError {
                outcome = .cancelled
                break
            } catch {
                results.append(result(candidate, status: .failed, affectedBytes: candidate.allocatedBytes, message: error.localizedDescription))
            }
        }

        let volumeAvailableAfter = mode == .apply ? volumeAvailableBytes(for: measuredVolumes) : nil
        let availableAfter = mode == .apply ? startupVolumeAvailableBytes() : nil
        let reclaimVerification = verification(
            mode: mode,
            outcome: outcome,
            results: results,
            before: volumeAvailableBefore,
            after: volumeAvailableAfter
        )
        return CleanupExecutionReport(
            startedAt: startedAt,
            finishedAt: Date(),
            mode: mode,
            results: results,
            requestedCount: candidates.count,
            outcome: outcome,
            availableBytesBefore: availableBefore,
            availableBytesAfter: availableAfter,
            volumeAvailableBytesBefore: volumeAvailableBefore,
            volumeAvailableBytesAfter: volumeAvailableAfter,
            reclaimVerification: reclaimVerification
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
                // Explicit item confirmation cannot prove that an owning
                // application is inactive. Keep the guard fail-closed.
                throw CleanupDeletionError.applicationStateUnknown(name)
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

    private func trashDirectory(for url: URL, context: CleanupScanContext) throws -> URL {
        let targetPath = url.standardizedFileURL.path
        let homePath = context.homeDirectory.standardizedFileURL.path
        if targetPath == homePath || targetPath.hasPrefix(homePath + "/") {
            return context.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        }
        return try fileManager.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
    }

    private func volumeURLs(for urls: [URL]) -> [String: URL] {
        let mountedVolumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: []
        ) ?? [URL(fileURLWithPath: "/", isDirectory: true)]
        var volumes: [String: URL] = [:]
        for url in urls {
            let path = url.standardizedFileURL.path
            guard let volumeURL = mountedVolumes
                .map(\.standardizedFileURL)
                .filter({ CleanupPathValidator.path(path, isEqualToOrDescendantOf: $0.path) })
                .max(by: { $0.path.count < $1.path.count }) else { continue }
            volumes[volumeURL.path] = volumeURL
        }
        return volumes
    }

    private func volumeAvailableBytes(for volumes: [String: URL]) -> [String: UInt64] {
        var result: [String: UInt64] = [:]
        for (path, volumeURL) in volumes {
            if let values = try? volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
               let available = values.volumeAvailableCapacity {
                result[path] = UInt64(max(0, available))
            }
        }
        return result
    }

    private func verification(
        mode: CleanupExecutionMode,
        outcome: CleanupExecutionOutcome,
        results: [CleanupExecutionItemResult],
        before: [String: UInt64]?,
        after: [String: UInt64]?
    ) -> CleanupReclaimVerification {
        guard mode == .apply else { return .notMeasured }
        guard outcome == .completed else { return .cancelled }
        let expected = results.reduce(UInt64(0)) { partial, result in
            let (value, overflow) = partial.addingReportingOverflow(result.reclaimedBytes)
            return overflow ? UInt64.max : value
        }
        guard expected > 0 else { return .notApplicable }
        guard let before, let after, !before.isEmpty, !after.isEmpty else { return .unavailable }
        let observed = before.reduce(UInt64(0)) { partial, entry in
            guard let afterValue = after[entry.key], afterValue > entry.value else { return partial }
            let delta = afterValue - entry.value
            let (value, overflow) = partial.addingReportingOverflow(delta)
            return overflow ? UInt64.max : value
        }
        return observed > 0 ? .verified : .noNetIncrease
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
    private let commandRunner: ([String]) throws -> String

    init(
        fileManager: FileManager = .default,
        commandRunner: @escaping ([String]) throws -> String = CleanupMaintenanceBackend.runSimulatorCommand
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    func execute(_ candidate: CleanupCandidate, context: CleanupScanContext) throws -> UInt64 {
        guard candidate.ruleID.rawValue == "xcode.simulatorcache" else {
            throw CleanupDeletionError.maintenanceTargetRejected
        }

        let developer = context.homeDirectory.appendingPathComponent("Library/Developer", isDirectory: true)
        let coreSimulatorCaches = developer.appendingPathComponent("CoreSimulator/Caches", isDirectory: true).standardizedFileURL.path
        let xctestDevices = developer.appendingPathComponent("XCTestDevices", isDirectory: true).standardizedFileURL.path
        let candidatePath = candidate.url.standardizedFileURL.path

        let isCoreSimulatorCache = candidatePath != coreSimulatorCaches &&
            CleanupPathValidator.path(candidatePath, isEqualToOrDescendantOf: coreSimulatorCaches)
        let isXCTestDeviceChild = candidatePath != xctestDevices && CleanupPathValidator.path(candidatePath, isEqualToOrDescendantOf: xctestDevices)
        guard isCoreSimulatorCache || isXCTestDeviceChild else {
            throw CleanupDeletionError.maintenanceTargetRejected
        }

        try assertSimulatorIdle()

        guard let identity = candidate.identity else {
            throw CleanupDeletionError.identityMissing
        }
        let expected = candidate.allocatedBytes
        try CleanupSecureFileOperations.remove(
            atPath: candidate.url.path,
            expectedIdentity: CleanupSecureNodeIdentity(identity),
            cancellationCheck: { try Task.checkCancellation() }
        )
        return expected
    }

    private func assertSimulatorIdle() throws {
        let output: String
        do {
            output = try commandRunner(["simctl", "list", "devices", "--json"])
        } catch {
            throw CleanupDeletionError.maintenanceUnavailable(error.localizedDescription)
        }

        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let deviceGroups = dictionary["devices"] as? [String: [[String: Any]]] else {
            throw CleanupDeletionError.maintenanceUnavailable("simctl cihaz listesi okunamadı")
        }

        let busyDevice = deviceGroups.values
            .flatMap { $0 }
            .first { device in
                guard let state = device["state"] as? String else { return true }
                return state.caseInsensitiveCompare("Shutdown") != .orderedSame
            }
        guard busyDevice == nil else {
            throw CleanupDeletionError.maintenanceUnavailable("Çalışan veya geçiş durumundaki simülatörler kapatılmadan cache temizlenemez")
        }
    }

    private static func runSimulatorCommand(_ arguments: [String]) throws -> String {
        let executable = "/usr/bin/xcrun"
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "xcrun simctl çıkış kodu \(process.terminationStatus)"
            throw NSError(domain: "CleanupMaintenanceBackend", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
