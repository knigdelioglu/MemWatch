import AppKit
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
    var ddcAvailable = false
    @Published private(set) var capabilities = DisplayCapabilities.unavailable
    @Published var autoBrightnessEnabled = true
    var volumeKeyRouter: MonitorVolumeKeyRouter?
    lazy var keepAwakeCoordinator = KeepAwakeCoordinator(app: self)
    let volumeCoordinator = DisplayVolumeCoordinator()
    let hiDPICoordinator = DisplayHiDPICoordinator()
    let powerSourceController = PowerSourceController()
    let luxFilter = LuxFilter()
    let brightnessAutoController = BrightnessAutoController()
    let brightnessAutoLoopPlanner = BrightnessAutoLoopPlanner()
    let brightnessAutoWriteOutcomePlanner = BrightnessAutoWriteOutcomePlanner()
    var isTickRunning = false
    var lastSmoothedLux: Double?
    var lastSentBrightness: Int?
    var lastWriteDate = Date.distantPast
    var lastBrightnessReadDate = Date.distantPast
    var lastDisplaySearchDate = Date.distantPast
    let brightnessReadInterval: TimeInterval = 8.0
    let displaySearchInterval: TimeInterval = 3.0
    var manualBrightnessOverrideUntil = Date.distantPast
    var autoBrightnessSuppressedUntil = Date.distantPast
    var manualBrightnessOverrideStartLux: Double?
    var pendingTargetCandidate: Int?
    var pendingTargetCandidateSince: Date = .distantPast
    var mismatchIntervalsCount: Int = 0
    var brightnessLimiterCooldownUntil = Date.distantPast
    var brightnessLimiterCooldownDisplayKey: String?
    let brightnessLimiterCooldownDuration: TimeInterval = 120.0
    let volumeReadInterval: TimeInterval = 5.0
    var lastVolumeReadDate = Date.distantPast

    @Published var keepAwakeState: KeepAwakeState

    @Published var currentIdleTimeString: String = "00:00"
    @Published var remainingIdleTimeString: String = "--:--"
    var isAwakeAssertionActive: Bool { keepAwakeCoordinator.isActive }
    
    @Published var statusText: String = "Başlatılıyor..."
    @Published var currentLux: Double?
    @Published var currentBrightness: Int?
    @Published var currentInternalBrightness: Int?
    @Published var currentVolume: Int? = nil
    @Published var currentDisplayInfo: ExternalDisplayInfo?
    @Published var hiDPIStatusText: String = "Mevcut Mod: bilinmiyor"
    @Published var hiDPIActivationStatusText: String = "HiDPI disabled"
    @Published var cgsModeEnumerationStatusText: String = "CGS mode enumeration henüz çalıştırılmadı."
    @Published var cgsModeEnumerationSummary: CGSModeEnumerationSummary?
    @Published var cgsModeApplyExperimentStatusText: String = "CGS apply experiment henüz çalıştırılmadı."
    @Published var cgsModeApplyExperimentSummary: CGSModeApplyExperimentSummary?
    @Published var cgsManualModeSwitcherStatusText: String = "Current CGS Mode: unavailable"
    @Published var cgsManualModeSwitcherSummary: CGSModeSwitcherStatus?
    @Published var cgsDynamicSelectionState: CGSDynamicModeSelectionState?
    @Published var cgsSamsungFallbackUsed: Bool = false
    @Published var cgsSelectedHiDPICandidate: CGSDisplayModeCandidate?
    @Published var cgsSelectedNormalCandidate: CGSDisplayModeCandidate?
    @Published var availableModes: [PhysicalDisplayMode] = []
    @Published var isHiDPIActive: Bool = false
    @Published var calibrationSession: CalibrationSession?
    @Published var currentEDIDSummary: EDIDDiagnosticSummary?
    @Published var hdrBrightnessDiagnosticSummary: HDRBrightnessDiagnosticSummary?
    @Published var ddcBrightnessMaxDiagnosticSummary: DDCBrightnessMaxDiagnosticSummary?
    @Published var ddcRawBrightnessProbeSummary: DDCRawBrightnessProbeSummary?
    @Published var brightnessMappingDiagnosticSummary: BrightnessMappingDiagnosticSummary?
    @Published var brightnessState = BrightnessState()
    let hdrBrightnessDiagnostic = HDRBrightnessDiagnostic()
    let ddcBrightnessMaxDiagnostic = DDCBrightnessMaxDiagnostic()
    let ddcRawBrightnessProbeDiagnostic = DDCRawBrightnessProbeDiagnostic()
    init(scheduler: PollingScheduler, capabilityRegistry: CapabilityRegistry? = nil) {
        DisplayPreferencesMigration.migrateIfNeeded()
        self.store = AmbientSyncStore()
        self.keepAwakeState = KeepAwakeFeatureController.loadInitialState()
        self.autoBrightnessEnabled = UserDefaults.standard.object(forKey: "AmbientSync.AutoBrightnessEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "AmbientSync.AutoBrightnessEnabled")
        self.scheduler = scheduler
        self.capabilityRegistry = capabilityRegistry ?? CapabilityRegistry()
        super.init()
        self.legacyMigrationTask = LegacyAmbientSyncMigration.scheduleIfNeeded()
    }

    func start() {
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

        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let migrationResult = await self.legacyMigrationTask?.value,
               !migrationResult.completedSuccessfully {
                self.updateStatus("Legacy AmbientSync cleanup failed; display features are paused")
                self.updateCapabilities()
                return
            }
            self.ddcAvailable = await self.brightnessCoordinator.isDDCAvailable(refresh: true)
            self.updateCapabilities()
            await self.reloadDisplayModes()
            self.refreshCGSModeSwitcherState()
            if self.keepAwakeState.featureEnabled {
                self.startDefaultAfterWakeSession()
            }
            await self.reloadDisplayInfo()
            self.refreshInternalBrightness()
            self.volumeKeyRouter?.setEnabled(self.currentDisplayInfo != nil)
            self.refreshCGSModeSwitcherState()
            await self.tick()
        }
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        legacyMigrationTask?.cancel()
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
        capabilities = next
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
