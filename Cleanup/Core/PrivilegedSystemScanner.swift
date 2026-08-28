import Foundation

struct PrivilegedSystemScanner: CleanupScanner {
    let id: CleanupScannerID = "privileged-system"
    let category: CleanupCategory = .systemCaches

    private let client = PrivilegedHelperClient()
    private let catalog = CleanupRuleCatalog()

    private let scanRuleIDs: [CleanupRuleID] = [
        "system.cache",
        "system.log.old",
        "diagnostic.system.old",
        "launchitem.orphan.system",
        "privatevar.temp.old"
    ]

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        guard context.privilegedHelperAvailable else { return [] }

        let response = try await client.scan(ruleIDs: scanRuleIDs)
        guard response.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion else {
            throw PrivilegedHelperClientError.protocolMismatch
        }

        var results: [CleanupCandidate] = []
        for item in response.items {
            try Task.checkCancellation()
            guard let path = item.path,
                  let rule = catalog.rule(for: CleanupRuleID(rawValue: item.ruleID)) else {
                continue
            }

            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard !context.isIgnored(url) else { continue }

            let identity = item.identity.map {
                FileIdentity(
                    deviceID: $0.deviceID,
                    inode: $0.inode,
                    ownerUID: $0.ownerUID,
                    mode: $0.mode
                )
            }

            results.append(
                CleanupCandidate(
                    scannerID: id,
                    ruleID: rule.id,
                    category: rule.category,
                    url: url,
                    displayName: item.displayName,
                    logicalBytes: item.logicalBytes,
                    allocatedBytes: item.allocatedBytes,
                    createdAt: item.createdAt,
                    modifiedAt: item.modifiedAt,
                    lastAccessedAt: item.lastAccessedAt,
                    safety: rule.defaultSafety,
                    deletionMode: rule.deletionMode,
                    requirements: rule.requirements,
                    reason: item.reason,
                    regenerationHint: privilegedRegenerationHint(for: rule.id),
                    identity: identity,
                    policyNotes: response.issues.isEmpty ? [] : [
                        "Privileged scan also reported: \(response.issues.joined(separator: " | "))"
                    ]
                )
            )
        }
        return results
    }

    private func privilegedRegenerationHint(for ruleID: CleanupRuleID) -> String? {
        switch ruleID.rawValue {
        case "system.cache":
            return "The owning software can normally recreate this cache; Apple-owned system caches are excluded."
        case "system.log.old", "diagnostic.system.old":
            return "Old diagnostics are not required for normal operation, but may be useful for troubleshooting."
        case "launchitem.orphan.system":
            return "The launch item points to a missing executable and should be reviewed before removal."
        case "privatevar.temp.old":
            return "Only old data under explicitly approved temporary/cache roots is returned."
        default:
            return nil
        }
    }
}

struct TimeMachineSnapshotBackend: Sendable {
    private let client = PrivilegedHelperClient()

    func listSnapshots() async throws -> [PrivilegedScannedItem] {
        let response = try await client.scan(ruleIDs: ["timemachine.snapshot"])
        guard response.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion else {
            throw PrivilegedHelperClientError.protocolMismatch
        }
        return response.items.filter { $0.ruleID == "timemachine.snapshot" }
    }

    func thinSnapshots(targetBytes: UInt64) async throws -> PrivilegedOperationResponse {
        try await client.execute(
            PrivilegedOperationRequest(
                operation: .thinTimeMachineSnapshots,
                ruleID: "timemachine.snapshot",
                targetBytes: targetBytes
            )
        )
    }
}
