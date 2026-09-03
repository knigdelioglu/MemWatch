import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class DisplayCoordinator: NSObject, ObservableObject, DisplayFeatureControlling {
    let store: AmbientSyncStore
    let brightnessCoordinator = DisplayBrightnessCoordinator()
    let scheduler: PollingScheduler
    let capabilityRegistry: CapabilityRegistry
    let capabilityProvider = DisplayCapabilityProvider()
    var startupTask: Task<Void, Never>?
    var legacyMigrationTask: Task<LegacyAmbientSyncMigrationResult, Never>?
    var observerTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var isRunning = false
    let runtimeState: DisplayRuntimeState
    private var runtimeStateObservation: AnyCancellable?
    private var startGeneration = 0
    var wakeStabilizationTask: Task<Void, Never>?
    var wakeStabilizationRetryCount = 0
    var displayTickTask: Task<Void, Never>?
    var displayTickTaskToken = 0
    var isPostWakeRefreshInProgress = false
    var volumeKeyRouter: MonitorVolumeKeyRouter?
    lazy var keepAwakeCoordinator = KeepAwakeCoordinator(app: self)
    let volumeCoordinator = DisplayVolumeCoordinator()
    let hiDPICoordinator = DisplayHiDPICoordinator()
    let powerSourceController = PowerSourceController()
    let luxFilter = LuxFilter()
    let brightnessAutoController = BrightnessAutoController()
    let brightnessAutoLoopPlanner = BrightnessAutoLoopPlanner()
    let brightnessAutoWriteOutcomePlanner = BrightnessAutoWriteOutcomePlanner()
    let hdrBrightnessDiagnostic = HDRBrightnessDiagnostic()
    let ddcBrightnessMaxDiagnostic = DDCBrightnessMaxDiagnostic()
    let ddcRawBrightnessProbeDiagnostic = DDCRawBrightnessProbeDiagnostic()
    // Coordinator-owned debounce tasks are intentionally shared by every UI
    // surface and input route. A view disappearing must not leave a stale
    // task that can outlive a newer auto/mute/keyboard intent.
    var manualBrightnessWriteTask: Task<Void, Never>?
    var manualVolumeWriteTask: Task<Void, Never>?

    init(scheduler: PollingScheduler, capabilityRegistry: CapabilityRegistry? = nil) {
        DisplayPreferencesMigration.migrateIfNeeded()
        DisplayConnectionIntentMigration.migrateIfNeeded()
        self.store = AmbientSyncStore()
        let initialAutoBrightnessEnabled = UserDefaults.standard.object(forKey: "AmbientSync.AutoBrightnessEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "AmbientSync.AutoBrightnessEnabled")
        self.runtimeState = DisplayRuntimeState(
            autoBrightnessEnabled: initialAutoBrightnessEnabled,
            keepAwakeState: KeepAwakeFeatureController.loadInitialState()
        )
        self.scheduler = scheduler
        self.capabilityRegistry = capabilityRegistry ?? CapabilityRegistry()
        super.init()
        self.runtimeStateObservation = runtimeState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        self.legacyMigrationTask = LegacyAmbientSyncMigration.scheduleIfNeeded()
    }

    func start() {
        traceRuntime("start entered isRunning=\(isRunning) startupTask=\(startupTask != nil)")
        guard !isRunning, startupTask == nil else { return }
        startGeneration += 1
        let generation = startGeneration
        if legacyMigrationTask == nil {
            legacyMigrationTask = LegacyAmbientSyncMigration.scheduleIfNeeded()
        }
        let migrationTask = legacyMigrationTask
        let cleanupVersion = UserDefaults.standard.integer(forKey: "MemWatch.LegacyAmbientSyncCleanupVersion")
        traceRuntime(
            "start prepared generation=\(generation) migrationTask=\(migrationTask != nil) " +
                "cleanupVersion=\(cleanupVersion)"
        )

        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.traceRuntime("startup task entered generation=\(generation)")
            if let migrationTask {
                self.traceRuntime("startup task awaiting legacy migration")
                let migrationResult = await migrationTask.value
                self.traceRuntime("startup task legacy migration result=\(migrationResult)")
                switch migrationResult {
                case .conflict(let reason):
                    guard self.isCurrentStart(generation) else { return }
                    self.updateStatus("Legacy AmbientSync conflict: \(reason); display features are paused")
                    self.updateCapabilities()
                    self.startupTask = nil
                    return
                case .failed(let reason):
                    // Cleanup failures are actionable warnings, not a reason
                    // to suppress display discovery or runtime activation.
                    self.updateStatus("Legacy AmbientSync cleanup warning: \(reason)")
                case .alreadyCompleted, .noLegacyPlist, .completed:
                    break
                }
            }

            guard self.isCurrentStart(generation) else { return }
            self.traceRuntime("startup migration complete; activating runtime generation=\(generation)")
            self.activateRuntime()
            let powerGeneration = self.displayPowerGeneration
            let available = await self.brightnessCoordinator.isDDCAvailable(refresh: true)
            guard self.isCurrentStart(generation),
                  self.acceptsDisplayPowerGeneration(powerGeneration) else { return }
            self.ddcAvailable = available
            self.traceRuntime("activateRuntime complete ddcAvailable=\(self.ddcAvailable)")
            guard self.isCurrentStart(generation) else { return }
            self.updateCapabilities()
            // Discover and publish the monitor before the synchronous CGS/HiDPI
            // scan. A slow or unavailable private mode API must not leave the
            // UI showing the initial "no external display" state.
            await self.reloadDisplayInfo(reloadModes: false)
            guard self.isCurrentStart(generation), self.displayOperationsAllowed else { return }
            await self.reloadDisplayModes()
            guard self.isCurrentStart(generation), self.displayOperationsAllowed else { return }
            self.refreshCGSModeSwitcherState()
            if self.keepAwakeState.featureEnabled {
                self.startDefaultAfterWakeSession()
            }
            self.refreshInternalBrightness()
            self.volumeKeyRouter?.setEnabled(self.currentDisplayInfo != nil)
            self.refreshCGSModeSwitcherState()
            if HiDPIStateStore.isHiDPIEnabled() {
                HiDPIReapplyService.shared.triggerReapplyDebounced()
            }
            await self.tick()
        }
    }

    private func isCurrentStart(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == startGeneration
    }

    private func activateRuntime() {
        traceRuntime("activateRuntime entered isRunning=\(isRunning)")
        guard !isRunning else { return }
        runtimeState.powerLifecycle.prepareForStart()
        DisplayPowerOperationGate.shared.activate(generation: displayPowerGeneration)
        isRunning = true
        HiDPIReapplyService.shared.configurePowerStateProvider { [weak self] in
            guard let self else { return .blocked }
            return self.displayPowerLifecycleSnapshot()
        } powerBoundaryHandler: { [weak self] in
            self?.handleDisplayChangeEvent()
        } reapplyCompletionHandler: { [weak self] in
            self?.refreshHiDPIStateAfterAutomaticReapply()
        }
        HiDPIReapplyService.shared.startService()
        registerWorkspaceObservers()

        volumeKeyRouter = MonitorVolumeKeyRouter(app: self)
        volumeKeyRouter?.setEnabled(currentDisplayInfo != nil)
        volumeKeyRouter?.start()

        scheduler.register(id: "display-feature", interval: 0.8) { [weak self] in
            self?.scheduleDisplayTick()
        }
        traceRuntime("activateRuntime registered display-feature scheduler")
    }

    func stop() {
        startGeneration += 1
        isRunning = false
        startupTask?.cancel()
        startupTask = nil
        displayTickTask?.cancel()
        displayTickTask = nil
        displayTickTaskToken &+= 1
        wakeStabilizationTask?.cancel()
        wakeStabilizationTask = nil
        wakeStabilizationRetryCount = 0
        isPostWakeRefreshInProgress = false
        DisplayPowerOperationGate.shared.suspend()
        Task { await brightnessCoordinator.writer.cancelInFlightOperations() }
        manualBrightnessWriteTask?.cancel()
        manualBrightnessWriteTask = nil
        invalidateManualBrightnessWrites()
        brightnessState.pendingManualBrightnessPercent = nil
        manualVolumeWriteTask?.cancel()
        manualVolumeWriteTask = nil
        invalidateManualVolumeWrites()
        pendingVolumeIntent = nil
        // Migration is shared; cancel only the runtime startup waiter, not
        // the cleanup itself.
        legacyMigrationTask = nil
        scheduler.unregister(id: "display-feature")
        volumeKeyRouter?.stop()
        volumeKeyRouter = nil
        observerTokens.forEach { center, token in center.removeObserver(token) }
        observerTokens.removeAll()
        keepAwakeCoordinator.stop()
        HiDPIReapplyService.shared.stopService()
    }

    private func scheduleDisplayTick() {
        guard displayOperationsAllowed,
              !isPostWakeRefreshInProgress,
              displayTickTask == nil else { return }
        displayTickTaskToken &+= 1
        let taskToken = displayTickTaskToken
        displayTickTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.displayTickTaskToken == taskToken {
                    self.displayTickTask = nil
                }
            }
            await self?.tick()
        }
    }

    func refresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.displayOperationsAllowed else { return }
            let powerGeneration = self.displayPowerGeneration
            await self.reloadDisplayInfo()
            guard self.acceptsDisplayPowerGeneration(powerGeneration) else { return }
            self.refreshInternalBrightness()
            self.refreshEDIDDiagnosticSummary()
            await self.tick()
            guard self.acceptsDisplayPowerGeneration(powerGeneration) else { return }
        }
    }

    func registerWorkspaceObservers() {
        guard observerTokens.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let powerNotifications: [(Notification.Name, () -> Void)] = [
            (NSWorkspace.willSleepNotification, { [weak self] in self?.handleSystemSleepEvent() }),
            (NSWorkspace.screensDidSleepNotification, { [weak self] in self?.handleScreenSleepEvent() }),
            (NSWorkspace.didWakeNotification, { [weak self] in self?.handleWakeEvent() }),
            (NSWorkspace.screensDidWakeNotification, { [weak self] in self?.handleWakeEvent() })
        ]
        for (name, handler) in powerNotifications {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self != nil else { return }
                    handler()
                }
            }
            observerTokens.append((workspaceCenter, token))
        }

        let screenChangeToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDisplayChangeEvent()
            }
        }
        observerTokens.append((NotificationCenter.default, screenChangeToken))
    }


    func updateStatus(_ title: String) {
        statusText = title
    }

    func refreshSharedRuntimeFeatures() {
        keepAwakeCoordinator.refreshKeepAwakeLifecycleIfNeeded()
    }

    func updateCapabilities() {
        let next = capabilityProvider.capabilities(
            for: DisplayCapabilityInputs(
                hasAmbientLightSensor: brightnessCoordinator.reader != nil,
                hasInternalBrightness: brightnessCoordinator.internalDisplayController != nil,
                hasExternalDisplay: currentDisplayInfo != nil,
                hasDDCExecutable: ddcAvailable,
                hasHiDPIPrivateAPI: cgsManualModeSwitcherSummary != nil,
                hasSoftwareDisconnect: displayConnectionController.isAvailable
            )
        )

        guard next != capabilities else { return }
        traceRuntime(
            "capability update external=\(next.externalDisplay.status.rawValue) ddc=\(next.ddc.status.rawValue) " +
                "softwareDisconnect=\(next.softwareDisconnect.status.rawValue) currentDisplay=\(currentDisplayInfo?.displayKey ?? "nil")"
        )
        runtimeState.capabilities = next
        capabilityRegistry.update(display: next)
    }

    func refreshCurrentVolume(force: Bool = false) async {
        guard displayOperationsAllowed else { return }
        guard currentDisplayInfo != nil else {
            invalidateManualVolumeWrites()
            currentVolume = nil
            pendingVolumeIntent = nil
            return
        }

        // A hardware readback that started before a newer user command must
        // not replace the logical latest intent when it returns.
        let writeGeneration = currentManualVolumeWriteGeneration
        guard pendingVolumeIntent == nil else { return }

        let now = Date()
        if !force, now.timeIntervalSince(lastVolumeReadDate) < volumeReadInterval {
            return
        }

        lastVolumeReadDate = now
        let powerGeneration = displayPowerGeneration
        let readback = await brightnessCoordinator.writer.currentVolume()
        guard currentDisplayInfo != nil,
              acceptsDisplayPowerGeneration(powerGeneration),
              acceptsManualVolumeWrite(writeGeneration),
              pendingVolumeIntent == nil else { return }
        if let readback {
            currentVolume = readback
            volumeCoordinator.record(readback)
        }
    }

    func showVolumeRoutedBanner(message: String = "Ses monitöre yönlendirildi") {
        updateStatus(message)
    }

    func handleWakeEvent() {
        beginDisplayWakeStabilization()
        keepAwakeCoordinator.handleWakeEvent()
    }

    func handleDisplayChangeEvent() {
        if displayPowerState != .active || isPostWakeRefreshInProgress {
            beginDisplayWakeStabilization()
            return
        }

        HiDPIReapplyService.shared.triggerReapplyDebounced()
        refresh()
    }
    
    func startDefaultAfterWakeSession() {
        keepAwakeCoordinator.startDefaultAfterWakeSession()
    }

    func setKeepAwakeFeatureEnabled(_ enabled: Bool) {
        keepAwakeCoordinator.setKeepAwakeFeatureEnabled(enabled)
    }

    func toggleKeepAwake() {
        keepAwakeCoordinator.toggleKeepAwake()
    }

    func setKeepAwakePluggedOnly(_ enabled: Bool) {
        keepAwakeCoordinator.setKeepAwakePluggedOnly(enabled)
    }

    func setKeepAwakeDisplayAwake(_ enabled: Bool) {
        keepAwakeCoordinator.setKeepAwakeDisplayAwake(enabled)
    }

    func setKeepDisplayAwakeOnWake(_ enabled: Bool) {
        keepAwakeCoordinator.setKeepDisplayAwakeOnWake(enabled)
    }

    func setKeepAwakeDefaultDurationMode(_ mode: String) {
        keepAwakeCoordinator.setKeepAwakeDefaultDurationMode(mode)
    }

    func setKeepAwakeDefaultCustomMinutes(_ minutes: Int) {
        keepAwakeCoordinator.setKeepAwakeDefaultCustomMinutes(minutes)
    }

    func startSessionWithDefault() {
        keepAwakeCoordinator.startSessionWithDefault()
    }

    func startSessionWithDurationMode(_ mode: String) {
        keepAwakeCoordinator.startSessionWithDurationMode(mode)
    }

    func startSessionWithCustomMinutes(_ minutes: Int) {
        keepAwakeCoordinator.startSessionWithCustomMinutes(minutes)
    }

    func disableKeepAwake() {
        keepAwakeCoordinator.disableKeepAwake()
    }

    func setKeepAwakeDuration(_ duration: TimeInterval) {
        keepAwakeCoordinator.setKeepAwakeDuration(duration)
    }

    func updateAutoBrightnessTitle() {
        updateCapabilities()
    }

    func setKeepAwakeMenuTitle(_ title: String) {
        updateStatus(title)
    }


}
