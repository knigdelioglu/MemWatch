import Dispatch
import Foundation

@main
struct CleanupFileSizerStressTests {
    static func main() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MemWatchSizerStress-" + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        for index in 0..<20_000 {
            let file = root.appendingPathComponent("entry-" + String(index))
            try Data([UInt8(index & 0xFF)]).write(to: file)
        }

        let reachedCheckpoint = DispatchSemaphore(value: 0)
        let measurement = Task.detached {
            try CleanupFileSizer().measureStrict(root, entryObserver: { count in
                if count == 256 {
                    reachedCheckpoint.signal()
                }
            })
        }

        precondition(
            reachedCheckpoint.wait(timeout: .now() + 5) == .success,
            "The large-directory measurement did not reach its deterministic cancellation checkpoint"
        )
        let cancelledAt = Date()
        measurement.cancel()

        do {
            _ = try await measurement.value
            preconditionFailure("A cancelled strict size measurement must not complete successfully")
        } catch is CancellationError {
            // Expected: the sizer checks cancellation at a bounded entry batch.
        }

        precondition(
            Date().timeIntervalSince(cancelledAt) < 2,
            "Large-directory cancellation latency exceeded the bounded budget"
        )
        print("PASS cleanup file-sizer large-directory cancellation")
    }
}
