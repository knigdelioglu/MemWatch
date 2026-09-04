import AppKit
import Combine
import Dispatch
import Foundation

@MainActor
final class MonitoringService: ObservableObject {
    @Published private(set) var snapshot = MemorySnapshot.empty
    @Published private(set) var storageVolumes: [StorageVolumeSnapshot] = []
    @Published private(set) var powerSnapshot = PowerSnapshot.empty
    @Published private(set) var powerHistory: [PowerHistoryPoint] = []
    @Published private(set) var diagnostics = SystemDiagnosticsSnapshot.empty
    @Published private(set) var thermalSnapshot = ThermalSnapshot.empty
    @Published private(set) var systemHistory: [SystemHistoryPoint] = []
    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .disabled
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var swapDeltaBytes: Int64 = 0
    @Published private(set) var swapInDeltaBytes: UInt64 = 0
    @Published private(set) var swapOutDeltaBytes: UInt64 = 0
    @Published private(set) var isActivelySwapping = false
    @Published private(set) var systemPressure: MemoryPressure?
    @Published private(set) var notificationsEnabled = true
    @Published private(set) var notificationAuthorization: NotificationAuthorizationState = .unknown
    @Published private(set) var intelligence = SwapIntelligenceResult(
        state: .stable,
        summary: "Memory activity is stable",
        recentSwapInBytes: 0,
        recentSwapOutBytes: 0,
        activeSamples: 0,
        sampleCount: 0
    )

    var pressure: MemoryPressure {
        systemPressure ?? snapshot.pressure
    }

    var memoryPressureEstimate: MemoryPressureEstimate {
        MemoryPressureEstimate.calculate(
            snapshot: snapshot,
            swapOutDeltaBytes: swapOutDeltaBytes
        )
    }

    var isUsingNativePressure: Bool {
        systemPressure != nil
    }

    var hasStorageWarning: Bool {
        storageVolumes.contains { $0.health != .normal }
    }

    var averageObservablePowerWatts: Double? {
        average(powerHistory.compactMap { $0.systemLoadWatts })
    }

    var averageInputPowerWatts: Double? {
        average(powerHistory.compactMap { $0.adapterInputWatts })
    }

    var peakSystemPowerWatts: Double? {
        powerHistory.compactMap { $0.systemLoadWatts }.max()
    }

    private static let notificationsEnabledKey = "MemWatch.notificationsEnabled"
    private static let storageRefreshInterval: TimeInterval = 30
    private static let processRefreshInterval: TimeInterval = 30
    // 5-second samples × 360 = 30 minutes of lightweight in-memory power history.
    private static let powerHistoryLimit = 360
    private static let systemHistoryLimit = 120

    private struct PendingRefresh {
        var forceStorage = false
        var forceDiagnostics = false

        mutating func merge(forceStorage: Bool, forceDiagnostics: Bool) {
            self.forceStorage = self.forceStorage || forceStorage
            self.forceDiagnostics = self.forceDiagnostics || forceDiagnostics
        }
    }

    private let collector: any MonitoringCollecting
    private let launchAtLoginService = LaunchAtLoginService()
    private let pressureMonitor = NativeMemoryPressureMonitor()
    private let swapIntelligence = SwapIntelligenceEngine()
    private let notificationPolicy = NotificationPolicyEngine()
    private let storageNotificationPolicy = StorageNotificationPolicyEngine()
    private let notificationService: NotificationService?
    private let scheduler: PollingScheduler
    private var isRunning = false
    private var lastStorageRefreshDate: Date?
    private var lastProcessRefreshDate: Date?
    private var pendingRefresh: PendingRefresh?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0

    // These counters are interpreted only on MainActor, after the serialized
    // worker has returned an immutable snapshot.
    private var previousSwapUsedBytes: UInt64?
    private var previousSwapInBytes: UInt64?
    private var previousSwapOutBytes: UInt64?

    init(
        scheduler: PollingScheduler,
        collector: any MonitoringCollecting = MonitoringCollector(),
        notificationService: NotificationService? = NotificationService()
    ) {
        self.scheduler = scheduler
        self.collector = collector
        self.notificationService = notificationService

        if UserDefaults.standard.object(forKey: Self.notificationsEnabledKey) != nil {
            notificationsEnabled = UserDefaults.standard.bool(forKey: Self.notificationsEnabledKey)
        }

        launchAtLoginState = launchAtLoginService.currentState()

        pressureMonitor.onChange = { [weak self] pressure in
            Task { @MainActor [weak self] in
                self?.systemPressure = pressure
            }
        }
        pressureMonitor.start()

        notificationService?.onAuthorizationChange = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let becameDeliverable = !self.notificationAuthorization.canDeliver && state.canDeliver
                self.notificationAuthorization = state

                if becameDeliverable && self.notificationsEnabled {
                    self.notificationPolicy.reset()
                    self.storageNotificationPolicy.reset()
                    self.refresh(forceStorage: true, forceDiagnostics: true)
                }
            }
        }
        notificationService?.refreshAuthorizationStatus()
        if notificationsEnabled {
            notificationService?.requestAuthorization()
        }

        refresh(forceStorage: true, forceDiagnostics: true)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard notificationsEnabled != enabled else { return }

        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.notificationsEnabledKey)
        notificationPolicy.reset()
        storageNotificationPolicy.reset()

        if enabled {
            notificationService?.requestAuthorization()
            refresh(forceStorage: true, forceDiagnostics: true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil

        do {
            try launchAtLoginService.setEnabled(enabled)
            launchAtLoginState = launchAtLoginService.currentState()
        } catch {
            launchAtLoginState = launchAtLoginService.currentState()
            launchAtLoginError = error.localizedDescription
        }
    }

    func openNotificationSettings() {
        openSystemSettings(
            deepLink: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
    }

    func openLoginItemsSettings() {
        openSystemSettings(
            deepLink: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        )
    }

    /// Enqueues one refresh request. Requests arriving while the worker is
    /// busy are merged into one follow-up request, so timer ticks cannot form
    /// an unbounded task backlog.
    func refresh(forceStorage: Bool = false, forceDiagnostics: Bool = false) {
        launchAtLoginState = launchAtLoginService.currentState()

        var request = pendingRefresh ?? PendingRefresh()
        request.merge(forceStorage: forceStorage, forceDiagnostics: forceDiagnostics)
        pendingRefresh = request
        startNextRefreshIfNeeded()
    }

    func stop() {
        isRunning = false
        scheduler.unregister(id: "system-health")
        refreshGeneration &+= 1
        pendingRefresh = nil
        refreshTask?.cancel()
        // Keep the in-flight task registered until its actor call returns. A
        // subsequent start therefore cannot create a second collection while
        // a cancellation-insensitive test/backend is still unwinding.
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startMonitoring()
    }

    private func startNextRefreshIfNeeded() {
        guard refreshTask == nil, let pendingRefresh else { return }
        self.pendingRefresh = nil

        let startedAt = Date()
        let includeProcesses = pendingRefresh.forceDiagnostics || shouldRefreshProcesses(at: startedAt)
        let includeStorage = pendingRefresh.forceStorage || shouldRefreshStorage(at: startedAt)
        let request = MonitoringCollectionRequest(
            includeProcesses: includeProcesses,
            includeStorage: includeStorage
        )

        refreshGeneration &+= 1
        let generation = refreshGeneration
        let collector = self.collector

        refreshTask = Task { @MainActor [weak self] in
            let collected = await collector.collect(request)
            guard let self else { return }

            guard !Task.isCancelled, self.refreshGeneration == generation else {
                self.finishRefresh(generation: generation)
                return
            }

            self.apply(
                collected,
                request: request,
                startedAt: startedAt
            )
            self.finishRefresh(generation: generation)
        }
    }

    private func finishRefresh(generation: UInt64) {
        // A stop can advance the generation while the worker is unwinding. It
        // is still safe to release the in-flight marker here because no newer
        // refresh task can exist while that marker was set.
        guard refreshGeneration == generation || refreshTask != nil else { return }
        refreshTask = nil
        startNextRefreshIfNeeded()
    }

    private func shouldRefreshProcesses(at date: Date) -> Bool {
        guard let lastProcessRefreshDate else { return true }
        return date.timeIntervalSince(lastProcessRefreshDate) >= Self.processRefreshInterval
    }

    private func shouldRefreshStorage(at date: Date) -> Bool {
        guard let lastStorageRefreshDate else { return true }
        return date.timeIntervalSince(lastStorageRefreshDate) >= Self.storageRefreshInterval
    }

    private func apply(
        _ collected: MonitoringCollectionSnapshot,
        request: MonitoringCollectionRequest,
        startedAt: Date
    ) {
        applyMemory(collected.memory)
        applyPower(collected.power)

        let diagnosticsSnapshot = SystemDiagnosticsSnapshot(
            timestamp: collected.diagnostics.timestamp,
            cpuUsagePercent: collected.diagnostics.cpuUsagePercent,
            thermalState: collected.diagnostics.thermalState,
            lowPowerModeEnabled: collected.diagnostics.lowPowerModeEnabled,
            topProcesses: request.includeProcesses
                ? collected.diagnostics.topProcesses
                : diagnostics.topProcesses
        )
        diagnostics = diagnosticsSnapshot
        thermalSnapshot = collected.thermal

        if request.includeProcesses {
            lastProcessRefreshDate = startedAt
        }

        if let cpuUsagePercent = diagnosticsSnapshot.cpuUsagePercent {
            systemHistory.append(
                SystemHistoryPoint(
                    timestamp: diagnosticsSnapshot.timestamp,
                    cpuUsagePercent: cpuUsagePercent,
                    memoryUsagePercent: snapshot.usageRatio * 100,
                    thermalSeverity: diagnosticsSnapshot.thermalState.severity
                )
            )

            if systemHistory.count > Self.systemHistoryLimit {
                systemHistory.removeFirst(systemHistory.count - Self.systemHistoryLimit)
            }
        }

        if request.includeStorage, let volumes = collected.storageVolumes {
            storageVolumes = volumes
            lastStorageRefreshDate = startedAt
            evaluateStorageNotifications(now: diagnosticsSnapshot.timestamp)
        }
    }

    private func applyMemory(_ nextSnapshot: MemorySnapshot) {
        if let previousSwapUsedBytes {
            swapDeltaBytes = signedDelta(current: nextSnapshot.swapUsedBytes, previous: previousSwapUsedBytes)
        } else {
            swapDeltaBytes = 0
        }

        if let previousSwapInBytes {
            swapInDeltaBytes = monotonicDelta(current: nextSnapshot.swapInBytes, previous: previousSwapInBytes)
        } else {
            swapInDeltaBytes = 0
        }

        if let previousSwapOutBytes {
            swapOutDeltaBytes = monotonicDelta(current: nextSnapshot.swapOutBytes, previous: previousSwapOutBytes)
        } else {
            swapOutDeltaBytes = 0
        }

        isActivelySwapping = swapInDeltaBytes > 0 || swapOutDeltaBytes > 0 || swapDeltaBytes > 0

        previousSwapUsedBytes = nextSnapshot.swapUsedBytes
        previousSwapInBytes = nextSnapshot.swapInBytes
        previousSwapOutBytes = nextSnapshot.swapOutBytes
        snapshot = nextSnapshot

        intelligence = swapIntelligence.ingest(
            SwapIntelligenceSample(
                timestamp: nextSnapshot.timestamp,
                pressure: pressure,
                totalBytes: nextSnapshot.totalBytes,
                availableBytes: nextSnapshot.availableBytes,
                compressedBytes: nextSnapshot.compressedBytes,
                swapUsedBytes: nextSnapshot.swapUsedBytes,
                swapInDeltaBytes: swapInDeltaBytes,
                swapOutDeltaBytes: swapOutDeltaBytes
            )
        )

        evaluateMemoryNotification()
    }

    private func applyPower(_ nextSnapshot: PowerSnapshot) {
        powerSnapshot = nextSnapshot

        let systemLoad = nextSnapshot.systemLoadWatts
        let adapterInput = nextSnapshot.adapterInputWatts
        let batteryFlow = nextSnapshot.batteryFlowWatts

        guard systemLoad != nil || adapterInput != nil || batteryFlow != nil else {
            return
        }

        powerHistory.append(
            PowerHistoryPoint(
                timestamp: nextSnapshot.timestamp,
                systemLoadWatts: systemLoad,
                adapterInputWatts: adapterInput,
                batteryFlowWatts: batteryFlow,
                flow: nextSnapshot.flow
            )
        )

        if powerHistory.count > Self.powerHistoryLimit {
            powerHistory.removeFirst(powerHistory.count - Self.powerHistoryLimit)
        }
    }

    private func evaluateMemoryNotification() {
        guard notificationsEnabled else {
            notificationPolicy.reset()
            return
        }

        guard let payload = notificationPolicy.evaluate(
            state: intelligence.state,
            summary: intelligence.summary
        ) else {
            return
        }

        notificationService?.deliver(payload)
    }

    private func evaluateStorageNotifications(now: Date) {
        guard notificationsEnabled else {
            storageNotificationPolicy.reset()
            return
        }

        let payloads = storageNotificationPolicy.evaluate(
            volumes: storageVolumes,
            now: now
        )

        for payload in payloads {
            notificationService?.deliver(payload)
        }
    }

    private func startMonitoring() {
        guard isRunning else { return }
        scheduler.register(id: "system-health", interval: 5) { [weak self] in
            self?.refresh()
        }
    }

    private func openSystemSettings(deepLink: String) {
        if let url = URL(string: deepLink), NSWorkspace.shared.open(url) {
            return
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func monotonicDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private func signedDelta(current: UInt64, previous: UInt64) -> Int64 {
        if current >= previous {
            let delta = current - previous
            return delta > UInt64(Int64.max) ? Int64.max : Int64(delta)
        }

        let delta = previous - current
        return delta > UInt64(Int64.max) ? Int64.min + 1 : -Int64(delta)
    }
}

private final class NativeMemoryPressureMonitor {
    var onChange: ((MemoryPressure) -> Void)?

    private let source: any DispatchSourceMemoryPressure
    private var started = false

    init() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: .all,
            queue: DispatchQueue.main
        )
    }

    func start() {
        guard !started else { return }
        started = true

        source.setEventHandler { [weak self] in
            guard let self else { return }

            let event = self.source.data
            let pressure: MemoryPressure

            if event.contains(.critical) {
                pressure = .critical
            } else if event.contains(.warning) {
                pressure = .warning
            } else {
                pressure = .normal
            }

            self.onChange?(pressure)
        }

        source.activate()
    }

    deinit {
        source.cancel()
    }
}
