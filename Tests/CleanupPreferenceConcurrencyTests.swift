import Foundation

struct PrivilegedHelperClient: Sendable {
    init() {}

    func execute(_ request: PrivilegedOperationRequest) async throws -> PrivilegedOperationResponse {
        throw NSError(domain: "CleanupPreferenceConcurrencyTests", code: 999)
    }
}

private actor ControlledPreferencesWriter {
    private var pending: [CheckedContinuation<Void, Error>] = []
    private(set) var startedValues: [CleanupPreferences] = []
    private(set) var durableValue: CleanupPreferences?

    func save(_ value: CleanupPreferences) async throws {
        startedValues.append(value)
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
        }
        durableValue = value
    }

    func releaseNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume()
    }

    func startedCount() -> Int { startedValues.count }
    func durable() -> CleanupPreferences? { durableValue }
}

private actor SubmissionBarrier {
    private let expected: Int
    private var entered = 0
    private var isOpen = false
    private var allEnteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(expected: Int) {
        self.expected = expected
    }

    func arriveAndWait() async {
        entered += 1
        if entered >= expected {
            allEnteredWaiters.forEach { $0.resume() }
            allEnteredWaiters.removeAll()
        }
        if isOpen { return }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilAllEntered() async {
        if entered >= expected { return }
        await withCheckedContinuation { continuation in
            allEnteredWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

@main
struct CleanupPreferenceConcurrencyTests {
    static func main() async throws {
        let writer = ControlledPreferencesWriter()
        let pipeline = LatestIntentWritePipeline<CleanupPreferences> { value in
            try await writer.save(value)
        }

        let first = Task {
            try await pipeline.submit(preferences(value: 1), revision: 1)
        }
        await waitUntil { await writer.startedCount() == 1 }

        let barrier = SubmissionBarrier(expected: 99)
        var submissions: [Task<LatestIntentWriteOutcome, Error>] = []
        for value in 2...100 {
            submissions.append(Task {
                await barrier.arriveAndWait()
                return try await pipeline.submit(preferences(value: value), revision: UInt64(value))
            })
        }

        await barrier.waitUntilAllEntered()
        await barrier.open()
        await waitUntil { await pipeline.latestSubmittedRevision == 100 }

        // The first I/O is intentionally delayed until every rapid intent has
        // entered the pipeline. Only revision 100 may be written next.
        await writer.releaseNext()
        await waitUntil { await writer.startedCount() == 2 }
        await writer.releaseNext()

        let firstOutcome = try await first.value
        precondition(firstOutcome == .superseded, "An old preference write must not report durable success")

        var persistedOutcomes = 0
        for submission in submissions {
            if try await submission.value == .persisted {
                persistedOutcomes += 1
            }
        }
        precondition(persistedOutcomes == 1, "Exactly the latest preference revision may be persisted")
        let durable = await writer.durable()
        let startedCount = await writer.startedCount()
        precondition(
            durable?.requestedRootPaths == ["/fixture/100"],
            "The durable preference must equal the latest rapid user intent"
        )
        precondition(
            startedCount == 2,
            "A 99-event burst must coalesce to the in-flight write plus one latest write"
        )

        print("PASS cleanup latest-intent preference persistence")
    }

    private static func preferences(value: Int) -> CleanupPreferences {
        CleanupPreferences(
            requestedRootPaths: ["/fixture/" + String(value)],
            projectRootPaths: ["/projects/" + String(value)],
            cleanupEnabled: value.isMultiple(of: 2),
            privilegedOperationsEnabled: true,
            privateBackendEnabled: true
        )
    }

    private static func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<10_000 {
            if await condition() { return }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for deterministic preference pipeline state")
    }
}
