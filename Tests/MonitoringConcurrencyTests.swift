import AppKit
import Combine
import Dispatch
import Foundation

private actor ControlledMonitoringCollector: MonitoringCollecting {
    private var pending: [CheckedContinuation<MonitoringCollectionSnapshot, Never>] = []
    private(set) var requestCount = 0
    private(set) var activeCount = 0
    private(set) var maxActiveCount = 0
    private(set) var lifecycleEvents: [ThermalLifecycleEvent] = []

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

    func handleThermalLifecycleEvent(_ event: ThermalLifecycleEvent) async {
        lifecycleEvents.append(event)
    }

    func releaseNext(value: UInt64) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: snapshot(value: value))
    }

    func state() -> (requests: Int, active: Int, maximum: Int, lifecycleEvents: [ThermalLifecycleEvent]) {
        (requestCount, activeCount, maxActiveCount, lifecycleEvents)
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
            storageVolumes: requestStorage(value: value),
            thermal: ThermalSnapshot(
                timestamp: Date(timeIntervalSince1970: TimeInterval(value)),
                hardwareEpoch: value,
                backendStatuses: [:],
                categorySourceSelections: .empty,
                categoryAvailability: .empty,
                aggregates: .empty,
                readings: []
            )
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

private struct LifecycleCollectorState: Sendable {
    let collectionCount: Int
    let activeCount: Int
    let finishedCount: Int
    let lifecycleEvents: [ThermalLifecycleEvent]
    let trace: [String]
}

private actor LifecycleRecordingCollector: MonitoringCollecting {
    private let blocksFirstCollection: Bool
    private var pending: [CheckedContinuation<MonitoringCollectionSnapshot, Never>] = []
    private(set) var collectionCount = 0
    private(set) var activeCount = 0
    private(set) var finishedCount = 0
    private(set) var lifecycleEvents: [ThermalLifecycleEvent] = []
    private(set) var trace: [String] = []

    init(blocksFirstCollection: Bool) {
        self.blocksFirstCollection = blocksFirstCollection
    }

    func collect(_ request: MonitoringCollectionRequest) async -> MonitoringCollectionSnapshot {
        collectionCount += 1
        activeCount += 1
        trace.append("collect")

        let result: MonitoringCollectionSnapshot
        if blocksFirstCollection && collectionCount == 1 {
            result = await withCheckedContinuation { continuation in
                pending.append(continuation)
            }
        } else {
            result = snapshot(value: UInt64(collectionCount), includeStorage: request.includeStorage)
        }

        activeCount -= 1
        finishedCount += 1
        return result
    }

    func handleThermalLifecycleEvent(_ event: ThermalLifecycleEvent) async {
        lifecycleEvents.append(event)
        switch event {
        case .systemWillSleep:
            trace.append("lifecycle.systemWillSleep")
        case .systemDidWake:
            trace.append("lifecycle.systemDidWake")
        }
    }

    func releaseNext(value: UInt64) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: snapshot(value: value, includeStorage: true))
    }

    func clearTrace() {
        trace.removeAll()
        lifecycleEvents.removeAll()
    }

    func state() -> LifecycleCollectorState {
        LifecycleCollectorState(
            collectionCount: collectionCount,
            activeCount: activeCount,
            finishedCount: finishedCount,
            lifecycleEvents: lifecycleEvents,
            trace: trace
        )
    }

    private func snapshot(value: UInt64, includeStorage: Bool) -> MonitoringCollectionSnapshot {
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
            storageVolumes: includeStorage ? [
                StorageVolumeSnapshot(
                    id: "fixture",
                    name: "Fixture",
                    mountPath: "/fixture",
                    totalBytes: 100,
                    availableBytes: 100 - min(value, 100),
                    isInternal: true,
                    isReadOnly: false
                )
            ] : nil,
            thermal: ThermalSnapshot(
                timestamp: Date(timeIntervalSince1970: TimeInterval(value)),
                hardwareEpoch: value,
                backendStatuses: [:],
                categorySourceSelections: .empty,
                categoryAvailability: .empty,
                aggregates: .empty,
                readings: []
            )
        )
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
        let finalThermalEpoch = await MainActor.run { service.thermalSnapshot.hardwareEpoch }
        precondition(finalState.maximum == 1, "Follow-up collection must remain serialized")
        precondition(finalDiagnostics.cpuUsagePercent == 2, "The latest snapshot must be applied")
        precondition(finalStorageAvailable == 98, "Latest storage snapshot must be applied")
        precondition(finalThermalEpoch == 2, "Latest thermal snapshot must be applied")
        await MainActor.run { service.stop() }

        await testThermalLifecycleObserversAndOrdering()
        await testThermalLifecycleStalesInFlightRefresh()

        print("PASS monitoring serialization, coalescing and MainActor responsiveness")
    }

    private static func testThermalLifecycleObserversAndOrdering() async {
        let notificationCenter = NotificationCenter()
        let collector = LifecycleRecordingCollector(blocksFirstCollection: false)
        let service = await MainActor.run {
            MonitoringService(
                scheduler: PollingScheduler(),
                collector: collector,
                notificationService: nil,
                workspaceNotificationCenter: notificationCenter
            )
        }

        await waitUntil { await collector.state().collectionCount == 1 }
        await collector.clearTrace()

        await MainActor.run {
            service.start()
            service.start()
            notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        }
        await Task.yield()
        let afterScreenSleep = await collector.state()
        precondition(afterScreenSleep.lifecycleEvents.isEmpty, "Screen sleep/wake must not drive thermal lifecycle")

        await MainActor.run {
            notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        }
        await waitUntil {
            let state = await collector.state()
            return state.lifecycleEvents == [.systemWillSleep, .systemDidWake]
                && state.collectionCount == 2
        }
        let orderedState = await collector.state()
        precondition(
            orderedState.trace == [
                "lifecycle.systemWillSleep",
                "lifecycle.systemDidWake",
                "collect"
            ],
            "Wake refresh must start only after ordered lifecycle forwarding"
        )

        await MainActor.run {
            service.stop()
            notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        }
        await Task.yield()
        let afterStop = await collector.state()
        precondition(afterStop.lifecycleEvents.count == 2, "stop must remove thermal observers")

        await MainActor.run {
            service.start()
            service.start()
            notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        }
        await waitUntil { await collector.state().lifecycleEvents.count == 3 }
        let afterRestart = await collector.state()
        precondition(
            afterRestart.lifecycleEvents.last == .systemDidWake,
            "start-stop-start must register one fresh observer pair"
        )
        await MainActor.run { service.stop() }
    }

    private static func testThermalLifecycleStalesInFlightRefresh() async {
        let notificationCenter = NotificationCenter()
        let collector = LifecycleRecordingCollector(blocksFirstCollection: true)
        let service = await MainActor.run {
            MonitoringService(
                scheduler: PollingScheduler(),
                collector: collector,
                notificationService: nil,
                workspaceNotificationCenter: notificationCenter
            )
        }

        await MainActor.run { service.start() }
        await waitUntil {
            let state = await collector.state()
            return state.collectionCount == 1 && state.activeCount == 1
        }

        await MainActor.run {
            notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        }
        await waitUntil { await collector.state().lifecycleEvents == [.systemWillSleep] }
        await collector.releaseNext(value: 999)
        await waitUntil {
            let state = await collector.state()
            return state.finishedCount == 1 && state.activeCount == 0
        }
        await Task.yield()

        let applied = await MainActor.run { (service.snapshot.swapUsedBytes, service.thermalSnapshot.hardwareEpoch) }
        precondition(applied.0 == 0 && applied.1 == 0, "Pre-sleep in-flight snapshot must be rejected by refreshGeneration")
        await MainActor.run { service.stop() }
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
