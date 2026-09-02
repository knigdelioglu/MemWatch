import Foundation

struct PrivilegedHelperClient: Sendable {
    init() {}

    func execute(_ request: PrivilegedOperationRequest) async throws -> PrivilegedOperationResponse {
        throw NSError(
            domain: "CleanupCancellationStressTests",
            code: 999,
            userInfo: [NSLocalizedDescriptionKey: "Privileged helper must not be reached by the cancellation fixture"]
        )
    }
}

@main
struct CleanupCancellationStressTests {
    static func main() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MemWatchDeletionStress-" + UUID().uuidString, isDirectory: true)
        let candidateRoot = root.appendingPathComponent("candidate", isDirectory: true)
        try fileManager.createDirectory(at: candidateRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        for index in 0..<2_000 {
            let directory = candidateRoot.appendingPathComponent("directory-" + String(index / 100), isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([UInt8(index & 0xFF)]).write(to: directory.appendingPathComponent("payload-" + String(index)))
        }

        guard let identity = CleanupSecureFileOperations.identity(atPath: candidateRoot.path) else {
            preconditionFailure("The deletion fixture identity must be readable")
        }
        var cancellationChecks = 0
        do {
            try CleanupSecureFileOperations.remove(
                atPath: candidateRoot.path,
                expectedIdentity: identity,
                cancellationCheck: {
                    cancellationChecks += 1
                    if cancellationChecks >= 128 {
                        throw CancellationError()
                    }
                }
            )
            preconditionFailure("Preflight cancellation must stop before a destructive mutation")
        } catch is CancellationError {
            // Expected: cancellation happened during read-only preflight.
        }

        let remaining = try fileManager.subpathsOfDirectory(atPath: candidateRoot.path)
        precondition(remaining.count == 2_020, "Cancellation during preflight must not partially delete the candidate")

        let cancelledTask = Task {
            await CleanupDeletionEngine().execute(
                candidates: [
                    candidate(url: candidateRoot),
                    candidate(url: root.appendingPathComponent("not-started", isDirectory: true))
                ],
                context: CleanupScanContext(homeDirectory: root, projectRoots: [root]),
                mode: .apply,
                explicitlyConfirmedIDs: []
            )
        }
        cancelledTask.cancel()
        let report = await cancelledTask.value
        precondition(report.outcome == .cancelled, "A cancelled deletion must report a cancelled outcome")
        precondition(report.requestedCount == 2, "Cancellation reports must retain the original requested count")
        precondition(report.results.isEmpty, "No result may be fabricated for a candidate that never started")
        precondition(report.reclaimVerification == .cancelled, "Cancelled deletion must not claim reclaim verification")
        precondition(fileManager.fileExists(atPath: candidateRoot.path), "Cancelled deletion must preserve the target")

        print("PASS cleanup cancellation boundary and partial-delete protection")
    }

    private static func candidate(url: URL) -> CleanupCandidate {
        CleanupCandidate(
            scannerID: "stress",
            ruleID: "project.artifact",
            category: .projectArtifacts,
            url: url,
            displayName: url.lastPathComponent,
            logicalBytes: 1,
            allocatedBytes: 1,
            safety: .safe,
            deletionMode: .permanent,
            requirements: [],
            reason: "stress fixture",
            identity: CleanupPathValidator.identity(for: url)
        )
    }
}
