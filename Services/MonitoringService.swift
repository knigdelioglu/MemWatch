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

    private let collector = MemoryCollector()
    private let storageCollector = StorageCollector()
    private let powerCollector = PowerCollector()
    private let diagnosticsCollector = SystemDiagnosticsCollector()
    private let launchAtLoginService = LaunchAtLoginService()
    private let pressureMonitor = NativeMemoryPressureMonitor()
    private let swapIntelligence = SwapIntelligenceEngine()
    private let notificationPolicy = NotificationPolicyEngine()
    private let storageNotificationPolicy = StorageNotificationPolicyEngine()
    private let notificationService = NotificationService()
    private let scheduler: PollingScheduler
    private var isRunning = false
    private var lastStorageRefreshDate: Date?
    private var lastProcessRefreshDate: Date?

    private var previousSwapUsedBytes: UInt64?
    private var previousSwapInBytes: UInt64?
    private var previousSwapOutBytes: UInt64?

    init(scheduler: PollingScheduler) {
        self.scheduler = scheduler

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

        notificationService.onAuthorizationChange = { [weak self] state in
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
        notificationService.refreshAuthorizationStatus()
        if notificationsEnabled {
            notificationService.requestAuthorization()
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
            notificationService.requestAuthorization()
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

    func refresh(forceStorage: Bool = false, forceDiagnostics: Bool = false) {
        refreshMemory()
        refreshPower()
        refreshDiagnostics(forceProcesses: forceDiagnostics)
        refreshStorageIfNeeded(force: forceStorage)
        launchAtLoginState = launchAtLoginService.currentState()
    }

    func stop() {
        isRunning = false
        scheduler.unregister(id: "system-health")
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startMonitoring()
    }

    private func refreshMemory() {
        let nextSnapshot = collector.collect()

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

    private func refreshPower() {
        let nextSnapshot = powerCollector.collect()
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

    private func refreshDiagnostics(forceProcesses: Bool) {
        let now = Date()
        let shouldRefreshProcesses: Bool

        if forceProcesses {
            shouldRefreshProcesses = true
        } else if let lastProcessRefreshDate {
            shouldRefreshProcesses = now.timeIntervalSince(lastProcessRefreshDate) >= Self.processRefreshInterval
        } else {
            shouldRefreshProcesses = true
        }

        let collected = diagnosticsCollector.collect(includeProcesses: shouldRefreshProcesses)
        diagnostics = SystemDiagnosticsSnapshot(
            timestamp: collected.timestamp,
            cpuUsagePercent: collected.cpuUsagePercent,
            thermalState: collected.thermalState,
            lowPowerModeEnabled: collected.lowPowerModeEnabled,
            topProcesses: shouldRefreshProcesses ? collected.topProcesses : diagnostics.topProcesses
        )

        if shouldRefreshProcesses {
            lastProcessRefreshDate = now
        }

        if let cpuUsagePercent = collected.cpuUsagePercent {
            systemHistory.append(
                SystemHistoryPoint(
                    timestamp: collected.timestamp,
                    cpuUsagePercent: cpuUsagePercent,
                    memoryUsagePercent: snapshot.usageRatio * 100,
                    thermalSeverity: collected.thermalState.severity
                )
            )

            if systemHistory.count > Self.systemHistoryLimit {
                systemHistory.removeFirst(systemHistory.count - Self.systemHistoryLimit)
            }
        }
    }

    private func refreshStorageIfNeeded(force: Bool) {
        let now = Date()
        if !force,
           let lastStorageRefreshDate,
           now.timeIntervalSince(lastStorageRefreshDate) < Self.storageRefreshInterval {
            return
        }

        storageVolumes = storageCollector.collect()
        lastStorageRefreshDate = now
        evaluateStorageNotifications(now: now)
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

        notificationService.deliver(payload)
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
            notificationService.deliver(payload)
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
