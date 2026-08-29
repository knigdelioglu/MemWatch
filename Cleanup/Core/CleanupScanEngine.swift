import Foundation

actor CleanupScanEngine {
    typealias ProgressHandler = @Sendable (CleanupScanProgress) async -> Void

    private let scanners: [any CleanupScanner]
    private let ruleCatalog: CleanupRuleCatalog
    private let safetyEngine: CleanupSafetyEngine

    init(
        scanners: [any CleanupScanner] = CleanupScannerRegistry.allScanners + [PrivilegedSystemScanner()],
        ruleCatalog: CleanupRuleCatalog = CleanupRuleCatalog(),
        safetyEngine: CleanupSafetyEngine = CleanupSafetyEngine()
    ) {
        self.scanners = scanners
        self.ruleCatalog = ruleCatalog
        self.safetyEngine = safetyEngine
    }

    func scan(
        context: CleanupScanContext,
        policy: CleanupScanPolicy = CleanupScanPolicy(),
        progress: ProgressHandler? = nil
    ) async throws -> CleanupScanResult {
        let startedAt = Date()
        var items: [CleanupCandidate] = []
        var issues: [CleanupScanIssue] = []
        await progress?(.preparing)

        let activeScanners = scanners.filter { !policy.skips(scanner: $0) }

        for (index, scanner) in activeScanners.enumerated() {
            try Task.checkCancellation()
            await progress?(.scanning(scannerID: scanner.id, completed: index, total: activeScanners.count))
            do {
                let candidates = try await scanner.scan(context: context)
                try Task.checkCancellation()
                await progress?(.evaluating(scannerID: scanner.id, candidateCount: candidates.count))
                for candidate in candidates {
                    try Task.checkCancellation()
                    guard !policy.skips(candidate: candidate) else { continue }
                    guard candidate.scannerID == scanner.id else {
                        issues.append(CleanupScanIssue(scannerID: scanner.id, path: candidate.url.path, message: "Scanner returned a candidate with a mismatched scanner ID"))
                        continue
                    }
                    guard let rule = ruleCatalog.rule(for: candidate.ruleID) else {
                        issues.append(CleanupScanIssue(scannerID: scanner.id, path: candidate.url.path, message: "Unknown cleanup rule: \(candidate.ruleID.rawValue)"))
                        continue
                    }
                    items.append(safetyEngine.assess(candidate: candidate, rule: rule, context: context).candidate)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                issues.append(CleanupScanIssue(scannerID: scanner.id, path: nil, message: error.localizedDescription))
            }
        }

        await progress?(.finishing)
        let (deduplicatedItems, overlapIssues) = coalesce(items)
        issues.append(contentsOf: overlapIssues)
        let sortedItems = deduplicatedItems.sorted { lhs, rhs in
            if lhs.safety != rhs.safety { return lhs.safety.rawValue < rhs.safety.rawValue }
            if lhs.allocatedBytes != rhs.allocatedBytes { return lhs.allocatedBytes > rhs.allocatedBytes }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return CleanupScanResult(startedAt: startedAt, finishedAt: Date(), items: sortedItems, issues: issues)
    }

    private func coalesce(
        _ candidates: [CleanupCandidate]
    ) -> (items: [CleanupCandidate], issues: [CleanupScanIssue]) {
        var byPath: [String: CleanupCandidate] = [:]
        var issues: [CleanupScanIssue] = []

        for candidate in candidates {
            let path = candidate.url.standardizedFileURL.path
            guard let existing = byPath[path] else {
                byPath[path] = candidate
                continue
            }

            let preferred = preferredCandidate(existing, candidate)
            let safety = CleanupSafetyLevel.moreRestrictive(existing.safety, candidate.safety)
            let deletionMode = safety == .protected
                ? CleanupDeletionMode.none
                : (deletionModeRank(existing.deletionMode) >= deletionModeRank(candidate.deletionMode)
                    ? existing.deletionMode
                    : candidate.deletionMode)
            let requirements = existing.requirements.union(candidate.requirements)
            let notes = Array(Set(existing.policyNotes + candidate.policyNotes + [
                "Same cleanup path was returned by more than one scanner; the result was coalesced."
            ])).sorted()
            issues.append(
                CleanupScanIssue(
                    scannerID: candidate.scannerID,
                    path: path,
                    message: "The same cleanup path was returned by more than one scanner; it was coalesced."
                )
            )
            byPath[path] = preferred.applying(
                safety: safety,
                deletionMode: deletionMode,
                requirements: requirements,
                policyNotes: notes
            )
        }

        var retained = Array(byPath.values).sorted {
            $0.url.pathComponents.count < $1.url.pathComponents.count
        }
        var index = 0
        while index < retained.count {
            let ancestor = retained[index]
            let descendants = retained.indices.dropFirst(index + 1).filter { descendantIndex in
                CleanupPathValidator.path(
                    retained[descendantIndex].url.path,
                    isEqualToOrDescendantOf: ancestor.url.path
                ) && retained[descendantIndex].url.standardizedFileURL.path != ancestor.url.standardizedFileURL.path
            }
            guard !descendants.isEmpty else {
                index += 1
                continue
            }

            if ancestor.safety == .protected || ancestor.deletionMode == .none {
                for descendantIndex in descendants.reversed() {
                    let removed = retained.remove(at: descendantIndex)
                    issues.append(
                        CleanupScanIssue(
                            scannerID: removed.scannerID,
                            path: removed.url.path,
                            message: "A protected parent cleanup target suppresses an overlapping descendant."
                        )
                    )
                }
                index += 1
            } else {
                retained.remove(at: index)
                issues.append(
                    CleanupScanIssue(
                        scannerID: ancestor.scannerID,
                        path: ancestor.url.path,
                        message: "An overlapping cleanup target was suppressed; only more-specific targets are retained."
                    )
                )
            }
        }
        return (retained, issues)
    }

    private func preferredCandidate(_ lhs: CleanupCandidate, _ rhs: CleanupCandidate) -> CleanupCandidate {
        if lhs.safety != rhs.safety { return lhs.safety > rhs.safety ? lhs : rhs }
        if deletionModeRank(lhs.deletionMode) != deletionModeRank(rhs.deletionMode) {
            return deletionModeRank(lhs.deletionMode) > deletionModeRank(rhs.deletionMode) ? lhs : rhs
        }
        return lhs.scannerID.rawValue <= rhs.scannerID.rawValue ? lhs : rhs
    }

    private func deletionModeRank(_ mode: CleanupDeletionMode) -> Int {
        switch mode {
        case .none: return 5
        case .privileged: return 4
        case .maintenance: return 3
        case .trash: return 2
        case .permanent: return 1
        }
    }
}
