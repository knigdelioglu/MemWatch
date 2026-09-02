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
            self.ddcAvailable = await self.brightnessCoordinator.isDDCAvailable(refresh: true)
            self.traceRuntime("activateRuntime complete ddcAvailable=\(self.ddcAvailable)")
            guard self.isCurrentStart(generation) else { return }
            self.updateCapabilities()
            // Discover and publish the monitor before the synchronous CGS/HiDPI
            // scan. A slow or unavailable private mode API must not leave the
            // UI showing the initial "no external display" state.
            await self.reloadDisplayInfo(reloadModes: false)
            guard self.isCurrentStart(generation) else { return }
            await self.reloadDisplayModes()
            guard self.isCurrentStart(generation) else { return }
            self.refreshCGSModeSwitcherState()
            if self.keepAwakeState.featureEnabled {
                self.startDefaultAfterWakeSession()
            }
            self.refreshInternalBrightness()
            self.volumeKeyRouter?.setEnabled(self.currentDisplayInfo != nil)
            self.refreshCGSModeSwitcherState()
            await self.tick()
        }
    }

    private func isCurrentStart(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == startGeneration
    }

    private func activateRuntime() {
        traceRuntime("activateRuntime entered isRunning=\(isRunning)")
        guard !isRunning else { return }
        isRunning = true
        HiDPIReapplyService.shared.startService()
        registerWorkspaceObservers()

        volumeKeyRouter = MonitorVolumeKeyRouter(app: self)
        volumeKeyRouter?.setEnabled(currentDisplayInfo != nil)
        volumeKeyRouter?.start()

        scheduler.register(id: "display-feature", interval: 0.8) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.tick()
            }
        }
        traceRuntime("activateRuntime registered display-feature scheduler")
    }

    func stop() {
        startGeneration += 1
        startupTask?.cancel()
        startupTask = nil
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
        isRunning = false
    }

    func refresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isRunning else { return }
            await self.reloadDisplayInfo()
            self.refreshInternalBrightness()
            self.refreshEDIDDiagnosticSummary()
            await self.tick()
        }
    }

    func registerWorkspaceObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeNotifications: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]
        for name in wakeNotifications {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleWakeEvent()
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
        guard currentDisplayInfo != nil else {
            currentVolume = nil
            return
        }

        let now = Date()
        if !force, now.timeIntervalSince(lastVolumeReadDate) < volumeReadInterval {
            return
        }

        lastVolumeReadDate = now
        let readback = await brightnessCoordinator.writer.currentVolume()
        if let readback {
            currentVolume = readback
            volumeCoordinator.record(readback)
        }
    }

    func showVolumeRoutedBanner(message: String = "Ses monitöre yönlendirildi") {
        updateStatus(message)
    }

    func handleWakeEvent() {
        HiDPIReapplyService.shared.triggerReapplyDebounced()
        keepAwakeCoordinator.handleWakeEvent()
    }

    func handleDisplayChangeEvent() {
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
