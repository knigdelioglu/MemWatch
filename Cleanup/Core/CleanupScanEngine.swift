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

    func scan(context: CleanupScanContext, progress: ProgressHandler? = nil) async throws -> CleanupScanResult {
        let startedAt = Date()
        var items: [CleanupCandidate] = []
        var issues: [CleanupScanIssue] = []
        await progress?(.preparing)

        for (index, scanner) in scanners.enumerated() {
            try Task.checkCancellation()
            await progress?(.scanning(scannerID: scanner.id, completed: index, total: scanners.count))
            do {
                let candidates = try await scanner.scan(context: context)
                try Task.checkCancellation()
                await progress?(.evaluating(scannerID: scanner.id, candidateCount: candidates.count))
                for candidate in candidates {
                    try Task.checkCancellation()
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
        let sortedItems = items.sorted { lhs, rhs in
            if lhs.safety != rhs.safety { return lhs.safety.rawValue < rhs.safety.rawValue }
            if lhs.allocatedBytes != rhs.allocatedBytes { return lhs.allocatedBytes > rhs.allocatedBytes }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return CleanupScanResult(startedAt: startedAt, finishedAt: Date(), items: sortedItems, issues: issues)
    }
}
