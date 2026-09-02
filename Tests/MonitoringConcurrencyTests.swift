import AppKit
import Combine
import Dispatch
import Foundation

private actor ControlledMonitoringCollector: MonitoringCollecting {
    private var pending: [CheckedContinuation<MonitoringCollectionSnapshot, Never>] = []
    private(set) var requestCount = 0
    private(set) var activeCount = 0
    private(set) var maxActiveCount = 0

    func collect(_ request: MonitoringCollectionRequest) async -> MonitoringCollectionSnapshot {
        _ = request
        requestCount += 1
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        let result = await withCheckedContinuation { continuation in
            pending.append(continuation)
        }
        activeCount -= 1
        return result
    }

    func releaseNext(value: UInt64) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: snapshot(value: value))
    }

    func state() -> (requests: Int, active: Int, maximum: Int) {
        (requestCount, activeCount, maxActiveCount)
    }

    private func snapshot(value: UInt64) -> MonitoringCollectionSnapshot {
        MonitoringCollectionSnapshot(
            memory: MemorySnapshot(
                timestamp: Date(timeIntervalSince1970: TimeInterval(value)),
                totalBytes: 100,
                usedBytes: 50,
                availableBytes: 50,
                freeBytes: 50,
                activeBytes: 50,
                cachedBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                swapTotalBytes: 100,
                swapUsedBytes: value,
                swapFreeBytes: 100 - min(value, 100),
                swapInBytes: value,
                swapOutBytes: value,
                pressure: .normal
            ),
            power: .empty,
            diagnostics: SystemDiagnosticsSnapshot(
                timestamp: Date(timeIntervalSince1970: TimeInterval(value)),
                cpuUsagePercent: Double(value),
                thermalState: .nominal,
                lowPowerModeEnabled: false,
                topProcesses: []
            ),
            storageVolumes: requestStorage(value: value)
        )
    }

    private func requestStorage(value: UInt64) -> [StorageVolumeSnapshot]? {
        [
            StorageVolumeSnapshot(
                id: "fixture",
                name: "Fixture",
                mountPath: "/fixture",
                totalBytes: 100,
                availableBytes: 100 - min(value, 100),
                isInternal: true,
                isReadOnly: false
            )
        ]
    }
}

@main
struct MonitoringConcurrencyTests {
    static func main() async {
        let collector = ControlledMonitoringCollector()
        let service = await MainActor.run {
            MonitoringService(
                scheduler: PollingScheduler(),
                collector: collector,
                notificationService: nil
            )
        }

        await waitUntil { await collector.state().requests == 1 }

        for _ in 0..<100 {
            await MainActor.run { service.refresh() }
        }
        await MainActor.run {
            service.refresh(forceStorage: true, forceDiagnostics: true)
        }

        var heartbeatCount = 0
        let heartbeat = Task { @MainActor in
            for _ in 0..<100 {
                heartbeatCount += 1
                await Task.yield()
            }
        }
        await heartbeat.value
        precondition(heartbeatCount == 100, "MainActor heartbeat must progress while collection is suspended")
        let initialState = await collector.state()
        precondition(initialState.maximum == 1, "Monitoring collection must never overlap")
        precondition(initialState.requests == 1, "Busy refreshes must coalesce instead of creating a task storm")

        await collector.releaseNext(value: 1)
        await waitUntil { await collector.state().requests == 2 }
        await collector.releaseNext(value: 2)
        await waitUntil { await service.snapshot.swapUsedBytes == 2 }

        let finalState = await collector.state()
        let finalDiagnostics = await MainActor.run { service.diagnostics }
        let finalStorageAvailable = await MainActor.run { service.storageVolumes.first?.availableBytes }
        precondition(finalState.maximum == 1, "Follow-up collection must remain serialized")
        precondition(finalDiagnostics.cpuUsagePercent == 2, "The latest snapshot must be applied")
        precondition(finalStorageAvailable == 98, "Latest storage snapshot must be applied")
        await MainActor.run { service.stop() }

        print("PASS monitoring serialization, coalescing and MainActor responsiveness")
    }

    private static func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<10_000 {
            if await condition() { return }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for deterministic monitoring state")
    }
}
