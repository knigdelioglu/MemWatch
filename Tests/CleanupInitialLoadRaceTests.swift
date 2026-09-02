import Foundation

private actor SlowCleanupPreferencesStore: CleanupPreferencesPersisting {
    private let loadedPreferences: CleanupPreferences
    private var loadWaiters: [CheckedContinuation<CleanupPreferences, Never>] = []
    private var didStartLoad = false
    private var savedPreferences: [CleanupPreferences] = []

    init(loadedPreferences: CleanupPreferences) {
        self.loadedPreferences = loadedPreferences
    }

    func load() async throws -> CleanupPreferences {
        didStartLoad = true
        return await withCheckedContinuation { continuation in
            loadWaiters.append(continuation)
        }
    }

    func save(_ preferences: CleanupPreferences) throws {
        savedPreferences.append(preferences)
    }

    func releaseLoad() {
        loadWaiters.forEach { $0.resume(returning: loadedPreferences) }
        loadWaiters.removeAll()
    }

    func state() -> (didStartLoad: Bool, saved: [CleanupPreferences]) {
        (didStartLoad, savedPreferences)
    }
}

@main
struct CleanupInitialLoadRaceTests {
    static func main() async throws {
        let diskPreferences = CleanupPreferences(
            requestedRootPaths: ["/disk/old"],
            projectRootPaths: ["/disk/projects"],
            cleanupEnabled: true,
            privilegedOperationsEnabled: false,
            privateBackendEnabled: true
        )
        let store = SlowCleanupPreferencesStore(loadedPreferences: diskPreferences)
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemWatchInitialLoad-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let ignoreStore = CleanupIgnoreStore(
            fileURL: fixtureRoot.appendingPathComponent("ignore-rules.json")
        )
        let historyStore = CleanupHistoryStore(
            fileURL: fixtureRoot.appendingPathComponent("history.json")
        )
        let coordinator = await MainActor.run {
            CleanupCoordinator(
                preferencesStore: store,
                ignoreStore: ignoreStore,
                historyStore: historyStore
            )
        }
        await waitUntil { await store.state().didStartLoad }

        // These mutations happen while the initial load is suspended. The
        // loaded disk snapshot must not replace either user intent.
        await MainActor.run {
            coordinator.setCleanupEnabled(false)
            coordinator.setPrivilegedOperationsEnabled(false)
        }
        await waitUntil { await store.state().saved.count >= 1 }
        await store.releaseLoad()
        await waitUntil { await MainActor.run { coordinator.isPersistentStateLoaded } }

        let appliedPreferences = await MainActor.run { coordinator.preferences }
        precondition(!appliedPreferences.cleanupEnabled, "Slow initial load must preserve the newer cleanup toggle")
        precondition(!appliedPreferences.privilegedOperationsEnabled, "Slow initial load must preserve the newer privilege intent")
        precondition(appliedPreferences.requestedRootPaths != diskPreferences.requestedRootPaths, "The stale disk snapshot must not replace the live preference object")
        print("PASS cleanup coordinator initial-load versus user-intent race")

        // Keep the pure revision invariant close to the integration test so a
        // future refactor cannot remove the state-machine contract unnoticed.
        var revisions = CleanupPreferenceRevisionState()
        let loadRevision = revisions.current
        _ = revisions.recordUserIntent()
        let userIntent = CleanupPreferences(
            requestedRootPaths: ["/user/new"],
            projectRootPaths: ["/user/projects"],
            cleanupEnabled: false,
            privilegedOperationsEnabled: false,
            privateBackendEnabled: false
        )

        var applied = userIntent
        if revisions.acceptsInitialLoad(startedAt: loadRevision) {
            applied = diskPreferences
        }

        precondition(applied == userIntent, "A slow initial load must not overwrite a newer user preference intent")
        precondition(!revisions.acceptsInitialLoad(startedAt: loadRevision), "The stale load revision must be rejected")
    }

    private static func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<10_000 {
            if await condition() { return }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for the slow cleanup initial-load fixture")
    }
}
