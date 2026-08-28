import Foundation

// Standalone CI fixture shims. Production definitions live in persistence/helper files,
// which are intentionally not needed to exercise scan-engine cancellation behavior.
struct CleanupScanPolicy: Sendable {
    init() {}
    func skips(scanner: any CleanupScanner) -> Bool { false }
    func skips(candidate: CleanupCandidate) -> Bool { false }
}

struct PrivilegedSystemScanner: CleanupScanner {
    let id: CleanupScannerID = "fixture-privileged"
    let category: CleanupCategory = .systemCaches
    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] { [] }
}

private struct SlowCancellationScanner: CleanupScanner {
    let id: CleanupScannerID = "slow-cancellation"
    let category: CleanupCategory = .maintenance

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        for _ in 0..<1_000 {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return []
    }
}

@main
struct CleanupCancellationTests {
    static func main() async throws {
        let engine = CleanupScanEngine(scanners: [SlowCancellationScanner()])
        let context = CleanupScanContext(projectRoots: [])

        let scanTask = Task {
            try await engine.scan(context: context)
        }

        try await Task.sleep(nanoseconds: 15_000_000)
        scanTask.cancel()

        do {
            _ = try await scanTask.value
            preconditionFailure("Cancelled cleanup scan must not complete successfully")
        } catch is CancellationError {
            // Expected: cancellation propagates out of CleanupScanEngine.
        }

        print("PASS Cleanup scan cancellation")
    }
}
