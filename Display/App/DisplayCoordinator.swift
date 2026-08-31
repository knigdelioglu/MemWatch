import AppKit
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps
import IOKit.pwr_mgt
import Darwin
import SwiftUI

@MainActor
final class DisplayCoordinator: NSObject, ObservableObject, DisplayFeatureControlling {
    let store: AmbientSyncStore
    private let reader = AmbientLightReader()
    private let writer = M1DDCWriter()
    private let internalBrightnessController = InternalDisplayBrightnessController()
    private let scheduler: PollingScheduler
    private let capabilityRegistry: CapabilityRegistry
    private var startupTask: Task<Void, Never>?
    private var observerTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var isRunning = false
    private var ddcAvailable = false
    @Published private(set) var capabilities = DisplayCapabilities.unavailable
    @Published private(set) var autoBrightnessEnabled = true
    private var volumeKeyRouter: MonitorVolumeKeyRouter?
    private lazy var keepAwakeCoordinator = KeepAwakeCoordinator(app: self)
    private let volumeFeatureController = VolumeFeatureController()
    private let hiDPIFeatureController = HiDPIFeatureController()
    private let hiDPIRefreshService: HiDPIRefreshService
    let powerSourceController = PowerSourceController()
    private let luxFilter = LuxFilter()
    private let brightnessAutoController = BrightnessAutoController()
    private let brightnessAutoLoopPlanner = BrightnessAutoLoopPlanner()
    private let brightnessAutoWriteOutcomePlanner = BrightnessAutoWriteOutcomePlanner()
    private var isTickRunning = false
    private var lastSmoothedLux: Double?
    private var lastSentBrightness: Int?
    private var lastWriteDate = Date.distantPast
    private var lastBrightnessReadDate = Date.distantPast
    private var lastDisplaySearchDate = Date.distantPast
    private let brightnessReadInterval: TimeInterval = 8.0
    private let displaySearchInterval: TimeInterval = 3.0
    private var manualBrightnessOverrideUntil = Date.distantPast
    private var autoBrightnessSuppressedUntil = Date.distantPast
    private var manualBrightnessOverrideStartLux: Double?
    private var pendingTargetCandidate: Int?
    private var pendingTargetCandidateSince: Date = .distantPast
    private var mismatchIntervalsCount: Int = 0
    private var brightnessLimiterCooldownUntil = Date.distantPast
    private var brightnessLimiterCooldownDisplayKey: String?
    private let brightnessLimiterCooldownDuration: TimeInterval = 120.0
    private var lastNonZeroVolume: Int = VolumeFeatureController.loadLastVolume()
    private let volumeReadInterval: TimeInterval = 5.0
    private var lastVolumeReadDate = Date.distantPast

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
    private let cgsModeSwitcher = CGSModeSwitcher()
    private let hdrBrightnessDiagnostic = HDRBrightnessDiagnostic()
    private let ddcBrightnessMaxDiagnostic = DDCBrightnessMaxDiagnostic()
    private let ddcRawBrightnessProbeDiagnostic = DDCRawBrightnessProbeDiagnostic()
    init(scheduler: PollingScheduler, capabilityRegistry: CapabilityRegistry? = nil) {
        DisplayPreferencesMigration.migrateIfNeeded()
        LegacyAmbientSyncMigration.runIfNeeded()
        self.store = AmbientSyncStore()
        self.keepAwakeState = KeepAwakeFeatureController.loadInitialState()
        self.autoBrightnessEnabled = UserDefaults.standard.object(forKey: "AmbientSync.AutoBrightnessEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "AmbientSync.AutoBrightnessEnabled")
        self.scheduler = scheduler
        self.capabilityRegistry = capabilityRegistry ?? CapabilityRegistry()
        self.hiDPIRefreshService = HiDPIRefreshService(modeSwitcher: cgsModeSwitcher, featureController: hiDPIFeatureController)
        super.init()
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
            self.ddcAvailable = await self.writer.isAvailable()
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
        scheduler.unregister(id: "display-feature")
        volumeKeyRouter?.stop()
        volumeKeyRouter = nil
        observerTokens.forEach { center, token in center.removeObserver(token) }
        observerTokens.removeAll()
        keepAwakeCoordinator.stop()
        isRunning = false
    }

    func refresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.reloadDisplayInfo()
            self.refreshInternalBrightness()
            self.refreshEDIDDiagnosticSummary()
            await self.tick()
        }
    }

    private func registerWorkspaceObservers() {
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

    private func tick() async {
        guard !isTickRunning else { return }
        isTickRunning = true
        defer { isTickRunning = false }

        updateCapabilities()
        refreshSharedRuntimeFeatures()

        if applySoftwareDisconnectedDisplayStateIfNeeded() {
            return
        }

        guard let reader else {
            updateStatus("Işık sensörü bulunamadı")
            updateBrightnessState { state in
                state.suppressionReason = "Işık sensörü bulunamadı"
            }
            return
        }

        guard let lux = reader.readLux() else {
            updateStatus("Sensör bekleniyor")
            updateBrightnessState { state in
                state.suppressionReason = "Sensör bekleniyor"
            }
            return
        }

        if currentDisplayInfo == nil, Date().timeIntervalSince(lastDisplaySearchDate) >= displaySearchInterval {
            lastDisplaySearchDate = Date()
            await reloadDisplayInfo()
            refreshSharedRuntimeFeatures()
        }

        guard let display = currentDisplayInfo else {
            updateStatus("Samsung S60UD ekranı bulunamadı")
            updateBrightnessState { state in
                state.suppressionReason = "Samsung S60UD ekranı bulunamadı"
            }
            return
        }

        store.setSelectedDisplayKey(display.displayKey)

        let settings = store.ensureSettings(for: display.displayKey)
        let profile = store.profile(id: settings.selectedProfileID)

        let smoothedLux = luxFilter.push(lux, baseSmoothing: profile.smoothing)
        lastSmoothedLux = smoothedLux
        currentLux = smoothedLux

        let now = Date()
        let ambientNormalizedValue = BrightnessCurve.ambientNormalizedValue(for: smoothedLux, calibration: settings.calibration)
        let autoTargetBrightnessPercent = BrightnessCurve.targetBrightness(
            for: smoothedLux,
            calibration: settings.calibration,
            profile: profile
        )
        let isManualOverrideActive = shouldHoldManualBrightnessOverride(currentLux: smoothedLux, now: now)
        let actualBefore = brightnessState.actualDDCBrightnessPercent
            ?? brightnessState.lastDDCReadbackPercent
            ?? currentBrightness
            ?? store.lastBrightness(for: display.displayKey)
            ?? 50
        let requestReferenceBrightness = actualBefore

        let smoothedRequestedPercent = brightnessAutoController.smoothedRequestedPercent(
            target: autoTargetBrightnessPercent,
            reference: requestReferenceBrightness,
            smoothing: profile.smoothing
        )

        updateBrightnessState { state in
            state.ambientSensorRawValue = lux
            state.ambientNormalizedValue = ambientNormalizedValue
            state.autoTargetBrightnessPercent = autoTargetBrightnessPercent
            state.smoothedRequestedBrightnessPercent = smoothedRequestedPercent
            state.actualDDCBrightnessPercent = actualBefore
            state.isManualOverrideActive = isManualOverrideActive
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && !isManualOverrideActive && calibrationSession == nil
            state.manualOverridePausedUntil = manualBrightnessOverrideUntil != .distantPast ? manualBrightnessOverrideUntil : nil
            state.lastAutoWriteAttempted = false
        }

        if !autoBrightnessEnabled {
            recordAutoSuppression(
                reason: .autoDisabled,
                source: .manualOverride,
                target: autoTargetBrightnessPercent,
                actual: actualBefore
            )
            updateBrightnessState { state in
                state.suppressionReason = "Automatic brightness is disabled"
            }
            updateStatus("Otomatik parlaklık kapalı")
            return
        }

        if isManualOverrideActive {
            recordAutoSuppression(
                reason: .manualOverrideActive,
                source: .manualOverride,
                target: autoTargetBrightnessPercent,
                actual: actualBefore
            )
            updateBrightnessState { state in
                state.suppressionReason = "Manual override active"
            }
            updateStatus("Parlaklık %\(currentBrightness ?? lastSentBrightness ?? 50) (manuel)")
            return
        }

        if currentBrightness == nil {
            let readback = await writer.readBrightness(preferredKey: display.displayKey)
            applyBrightnessReadback(readback, requestedFallback: store.lastBrightness(for: display.displayKey))
            lastBrightnessReadDate = now
        }
        await refreshCurrentVolume()
        refreshSharedRuntimeFeatures()

        let target = autoTargetBrightnessPercent
        updateStatus(String(format: "%.0f lux -> %%%d", smoothedLux, target))

        let currentActual = brightnessState.actualDDCBrightnessPercent ?? brightnessState.lastDDCReadbackPercent ?? actualBefore
        let minInterval: TimeInterval = profile.minInterval

        if abs(target - currentActual) > 10 {
            mismatchIntervalsCount += 1
        } else {
            mismatchIntervalsCount = 0
        }
        
        updateBrightnessState { state in
            state.showMismatchWarning = mismatchIntervalsCount >= 2
        }

        let smoothedCandidate = smoothedRequestedPercent
        let preflight = brightnessAutoLoopPlanner.preflight(
            context: BrightnessAutoLoopPreflightContext(
                ambientLux: smoothedLux,
                target: target,
                smoothedRequested: smoothedCandidate,
                currentActual: currentActual,
                now: now,
                lastWriteDate: lastWriteDate,
                minInterval: minInterval,
                updateThreshold: profile.updateThreshold,
                currentDisplayKey: display.displayKey,
                calibrationActive: calibrationSession != nil,
                appBrightnessSuppressedUntil: autoBrightnessSuppressedUntil,
                ddcAvailable: await writer.isAvailable(),
                brightnessLimiterCooldownDisplayKey: brightnessLimiterCooldownDisplayKey,
                brightnessLimiterCooldownUntil: brightnessLimiterCooldownUntil
            )
        )

        let writeCandidate: Int
        switch preflight {
        case .suppressed(let reason, let source, let statusText, _, _):
            recordAutoSuppression(
                reason: reason,
                source: source,
                target: target,
                actual: currentActual
            )
            updateBrightnessState { state in
                state.suppressionReason = statusText
            }
            if reason == .autoDisabled {
                updateCalibrationStatus()
            }
            if reason == .monitorLimiterCooldown {
                updateStatus("Monitör parlaklık komutunu sınırlıyor; otomatik yazma bekletiliyor")
            }
            return
        case .proceed(let candidate, let statusText):
            writeCandidate = candidate
            updateStatus(statusText)
            updateBrightnessState { state in
                state.lastAutoWriteAttempted = true
                state.lastWriteAttemptPercent = candidate
                state.lastAutoWriteValue = candidate
                state.lastAutoWriteActualBefore = currentActual
                state.lastAutoWriteActualAfter = currentActual
                state.lastSuppressionReason = nil
                state.suppressionReason = "Writing..."
                state.isBrightnessWriteSuppressed = false
            }
        }

        if writeCandidate > requestReferenceBrightness && manualBrightnessOverrideUntil > now && manualBrightnessOverrideStartLux == nil {
            manualBrightnessOverrideUntil = .distantPast
        }

        let result = await writer.setBrightness(writeCandidate, preferredKey: display.displayKey)

        if result.status == .success || result.status == .writeAcceptedButReadbackLimited {
            handleAutoBrightnessWriteSuccess(
                result: result,
                candidate: writeCandidate,
                currentActual: currentActual,
                displayKey: display.displayKey
            )
        } else {
            handleAutoBrightnessWriteFailure(
                result: result,
                candidate: writeCandidate,
                currentActual: currentActual
            )
        }
    }

    private func handleAutoBrightnessWriteSuccess(
        result: M1DDCBrightnessWriteResult,
        candidate: Int,
        currentActual: Int,
        displayKey: String
    ) {
        let outcome = brightnessAutoWriteOutcomePlanner.plan(result: result, candidate: candidate)
        lastWriteDate = Date()

        if let readback = outcome.persistedReadback {
            lastBrightnessReadDate = lastWriteDate
            store.setLastBrightness(readback, for: displayKey)
        }

        applyBrightnessWriteResult(requested: candidate, source: .autoDDCWrite, result: result)

        updateBrightnessState { state in
            state.lastWriteAttemptPercent = candidate
            state.lastWriteReadbackPercent = outcome.actualAfter
            state.actualDDCBrightnessPercent = outcome.actualAfter
            state.lastDDCReadbackPercent = outcome.actualAfter
            state.isAutoBrightnessEnabled = autoBrightnessEnabled
            state.isManualOverrideActive = false
            state.suppressionReason = nil
        }

        pendingTargetCandidate = nil
        currentBrightness = outcome.actualAfter
        lastSentBrightness = outcome.actualAfter
        if outcome.shouldSetCooldown {
            brightnessLimiterCooldownDisplayKey = displayKey
            brightnessLimiterCooldownUntil = Date().addingTimeInterval(brightnessLimiterCooldownDuration)
        } else {
            brightnessLimiterCooldownDisplayKey = nil
            brightnessLimiterCooldownUntil = .distantPast
        }
        updateStatus(outcome.statusText)
    }

    private func handleAutoBrightnessWriteFailure(
        result: M1DDCBrightnessWriteResult,
        candidate: Int,
        currentActual: Int
    ) {
        let outcome = brightnessAutoWriteOutcomePlanner.planFailure(
            result: result,
            currentActual: currentActual
        )
        applyBrightnessWriteResult(
            requested: candidate,
            source: .autoDDCWrite,
            result: result
        )
        updateBrightnessState { state in
            state.lastWriteAttemptPercent = candidate
            state.lastWriteReadbackPercent = nil
            state.lastAutoWriteActualAfter = outcome.actualAfter
            state.suppressionReason = "Write error: \(result.message)"
        }
        currentBrightness = outcome.actualAfter
        lastSentBrightness = outcome.actualAfter

        updateStatus(outcome.statusText)
    }

    private func updateStatus(_ title: String) {
        statusText = title
    }

    private func refreshSharedRuntimeFeatures() {
        keepAwakeCoordinator.refreshKeepAwakeLifecycleIfNeeded()
    }

    private func updateCapabilities() {
        let hasExternalDisplay = currentDisplayInfo != nil
        let ddcCapability: DisplayCapability
        if !ddcAvailable {
            ddcCapability = .unavailable("DDC is unavailable. Install m1ddc at /opt/homebrew/bin/m1ddc or /usr/local/bin/m1ddc.")
        } else if hasExternalDisplay {
            ddcCapability = .available
        } else {
            ddcCapability = .degraded("m1ddc is installed, but no supported external display is connected.")
        }

        let connectionController = displayConnectionController
        let hiDPICapability: DisplayCapability
        if !hasExternalDisplay {
            hiDPICapability = .unavailable("HiDPI requires a supported external display.")
        } else if cgsManualModeSwitcherSummary != nil {
            hiDPICapability = .available
        } else {
            hiDPICapability = .unavailable("HiDPI private display APIs are unavailable on this macOS configuration.")
        }

        let next = DisplayCapabilities(
            ambientLightSensor: reader == nil
                ? .unavailable("Ambient light sensor symbols are unavailable on this Mac.")
                : .available,
            internalBrightness: internalBrightnessController == nil
                ? .unavailable("Internal display brightness is unavailable.")
                : .available,
            externalDisplay: hasExternalDisplay
                ? .available
                : .unavailable("No supported external display is connected."),
            ddc: ddcCapability,
            volume: ddcCapability,
            hiDPI: hiDPICapability,
            softwareDisconnect: connectionController.isAvailable
                ? (hasExternalDisplay ? .available : .degraded("No supported external display is connected."))
                : .unavailable("Software display connection control is unavailable on this macOS configuration."),
            keepAwake: .available
        )

        guard next != capabilities else { return }
        capabilities = next
        capabilityRegistry.update(display: next)
    }

    private func refreshCurrentVolume(force: Bool = false) async {
        guard currentDisplayInfo != nil else {
            currentVolume = nil
            return
        }

        let now = Date()
        if !force, now.timeIntervalSince(lastVolumeReadDate) < volumeReadInterval {
            return
        }

        lastVolumeReadDate = now
        let readback = await writer.currentVolume()
        if let readback {
            currentVolume = readback
            if readback > 0 {
                lastNonZeroVolume = readback
            }
            volumeFeatureController.persistLastVolume(readback)
        }
    }

    func showVolumeRoutedBanner(message: String = "Ses monitöre yönlendirildi") {
        updateStatus(message)
    }

    func handleWakeEvent() {
        HiDPIReapplyService.shared.triggerReapplyDebounced()
        keepAwakeCoordinator.handleWakeEvent()
    }

    private func handleDisplayChangeEvent() {
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

    private func updateAutoBrightnessTitle() {
        updateCapabilities()
    }

    func setKeepAwakeMenuTitle(_ title: String) {
        updateStatus(title)
    }

    private func persistHiDPIState(enabled: Bool) {
        HiDPIStateStore.setHiDPIEnabled(enabled)
        HiDPIStateStore.setStateText(enabled ? "HiDPI enabled" : "HiDPI disabled")
        hiDPIActivationStatusText = enabled ? "HiDPI enabled" : "HiDPI disabled"
    }

    private func reloadDisplayModes() async {
        let snapshot = hiDPIRefreshService.reloadDisplayModes(currentActivationStatusText: hiDPIActivationStatusText)
        availableModes = snapshot.availableModes
        cgsManualModeSwitcherSummary = snapshot.manualModeSwitcherSummary
        cgsManualModeSwitcherStatusText = snapshot.manualModeSwitcherStatusText
        cgsDynamicSelectionState = snapshot.dynamicSelectionState
        cgsSelectedHiDPICandidate = snapshot.selectedHiDPICandidate
        cgsSelectedNormalCandidate = snapshot.selectedNormalCandidate
        cgsSamsungFallbackUsed = snapshot.samsungFallbackUsed
        isHiDPIActive = snapshot.isHiDPIActive
        hiDPIStatusText = snapshot.hiDPIStatusText
        hiDPIActivationStatusText = snapshot.hiDPIActivationStatusText
        if let statusMessage = snapshot.statusMessage {
            updateStatus(statusMessage)
        }
        if snapshot.succeeded {
            refreshEDIDDiagnosticSummary()
        } else {
            currentEDIDSummary = nil
        }
    }

    private func refreshCGSModeSwitcherState() {
        let summary = hiDPIRefreshService.refreshCGSModeSwitcherState()
        cgsManualModeSwitcherSummary = summary
        cgsManualModeSwitcherStatusText = summary?.currentModeText ?? "Current CGS Mode: unavailable"
    }

    var activeDisplayKey: String {
        currentDisplayInfo?.displayKey ?? store.preferences.selectedDisplayKey ?? "default"
    }

    var currentDisplayKey: String? {
        currentDisplayInfo?.displayKey
    }

    private func updateBrightnessState(_ mutate: (inout BrightnessState) -> Void) {
        var next = brightnessState
        mutate(&next)
        brightnessState = next
    }

    private func recordAutoSuppression(
        reason: BrightnessSuppressionReason,
        source: BrightnessSource,
        target: Int?,
        actual: Int?
    ) {
        updateBrightnessState { state in
            state.isBrightnessWriteSuppressed = true
            state.lastSuppressionReason = reason
            state.suppressionReason = reason.rawValue
            state.lastBrightnessSource = source
            if let target {
                state.autoTargetBrightnessPercent = target
            }
            if let actual {
                state.actualDDCBrightnessPercent = actual
            }
        }
    }

    private func applyBrightnessReadback(_ readback: Int?, requestedFallback: Int? = nil) {
        updateBrightnessState { state in
            if let requestedFallback {
                state.requestedDDCBrightnessPercent = requestedFallback
            }
            state.actualDDCBrightnessPercent = readback
            if let readback {
                state.lastDDCReadbackPercent = readback
                state.lastDDCActualPercentAfter = readback
                if state.lastAutoWriteActualBefore == nil {
                    state.lastAutoWriteActualBefore = readback
                }
                state.lastAutoWriteActualAfter = readback
            }
            state.isDDCReadbackAvailable = readback != nil
            state.lastBrightnessSource = .ddcReadback
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil && !state.isManualOverrideActive
            state.isBrightnessWriteSuppressed = false
            state.lastSuppressionReason = nil
            state.suppressionReason = nil
        }
        currentBrightness = readback ?? requestedFallback ?? currentBrightness
    }

    private func applyBrightnessWriteResult(
        requested: Int,
        source: BrightnessSource,
        result: M1DDCBrightnessWriteResult
    ) {
        updateBrightnessState { state in
            state.requestedDDCBrightnessPercent = requested
            state.actualDDCBrightnessPercent = result.actualUIPercentAfter ?? result.readbackBrightnessPercent
            if let readback = result.actualUIPercentAfter ?? result.readbackBrightnessPercent {
                state.lastDDCReadbackPercent = readback
                state.lastDDCActualPercentAfter = readback
            }
            state.lastDDCRawCurrentBefore = result.rawBefore
            state.lastDDCRawMax = result.rawMax
            state.lastDDCRawTarget = result.computedRawTarget
            state.lastDDCRawAfter = result.rawAfter
            state.isDDCReadbackAvailable = result.readbackAvailable
            state.lastBrightnessSource = result.success ? source : .writeFailed
            state.lastDDCWriteSucceeded = result.success
            state.lastDDCWriteMessage = result.message
            state.lastDDCWriteStatus = result.status
            state.lastDDCMatchedTarget = result.matchedTarget
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil && !state.isManualOverrideActive
            if source == .autoDDCWrite {
                state.lastAutoWriteAttempted = true
                state.lastAutoWriteValue = requested
                state.lastAutoWriteSucceeded = result.success
                state.lastAutoWriteMessage = result.message
                state.lastAutoWriteActualAfter = result.actualUIPercentAfter ?? result.readbackBrightnessPercent ?? state.lastAutoWriteActualAfter
            }
            state.isBrightnessWriteSuppressed = false
            state.lastSuppressionReason = nil
            state.suppressionReason = nil
        }
        if let observedBrightness = result.actualUIPercentAfter ?? result.readbackBrightnessPercent {
            currentBrightness = observedBrightness
        }
    }

    private func brightnessMappingDiagnosticSummarySnapshot() -> BrightnessMappingDiagnosticSummary {
        BrightnessMappingDiagnosticSummary(
            targetDisplayName: currentDisplayInfo?.displayLabel ?? "unavailable",
            displayKey: currentDisplayKey,
            ambientSensorRawValue: brightnessState.ambientSensorRawValue,
            ambientNormalizedValue: brightnessState.ambientNormalizedValue,
            computedAutoTargetBrightnessPercent: brightnessState.autoTargetBrightnessPercent,
            requestedDDCBrightnessPercent: brightnessState.requestedDDCBrightnessPercent,
            ddcWriteSucceeded: brightnessState.lastDDCWriteSucceeded,
            ddcWriteMessage: brightnessState.lastDDCWriteMessage,
            actualDDCBrightnessPercent: brightnessState.actualDDCBrightnessPercent,
            lastDDCReadbackPercent: brightnessState.lastDDCReadbackPercent,
            rawCurrentBefore: brightnessState.lastDDCRawCurrentBefore,
            rawMax: brightnessState.lastDDCRawMax,
            computedRawTarget: brightnessState.lastDDCRawTarget,
            rawBefore: brightnessState.lastDDCRawCurrentBefore,
            rawAfter: brightnessState.lastDDCRawAfter,
            actualUIPercentAfter: brightnessState.lastDDCActualPercentAfter,
            matchedTarget: brightnessState.lastDDCMatchedTarget,
            writeStatus: brightnessState.lastDDCWriteStatus,
            uiSliderValue: brightnessState.uiSliderBrightnessPercent,
            lastBrightnessSource: brightnessState.lastBrightnessSource,
            isAutoBrightnessEnabled: brightnessState.isAutoBrightnessEnabled,
            isManualOverrideActive: brightnessState.isManualOverrideActive,
            readbackAvailable: brightnessState.isDDCReadbackAvailable
        )
    }

    var canApplyCGSMode74Transaction: Bool {
        cgsManualModeSwitcherSummary?.canApplyMode74 == true
    }

    var canApplyCGSMode56NormalQHDTransaction: Bool {
        cgsManualModeSwitcherSummary?.canApplyMode56 == true
    }

    var currentCGSModeStatusText: String {
        cgsManualModeSwitcherStatusText
    }

    var currentDisplayLabel: String {
        currentDisplayInfo?.displayLabel ?? "Ekran bekleniyor"
    }

    var monitorVolumeControlValue: Int {
        currentVolume ?? lastNonZeroVolume
    }

    var monitorBrightnessControlValue: Int {
        brightnessState.uiSliderBrightnessPercent
    }

    var brightnessSensorTargetText: String {
        brightnessState.autoTargetBrightnessPercent.map { "\($0)%" } ?? "—"
    }

    var brightnessActualText: String {
        if brightnessState.isDDCReadbackAvailable {
            if let actual = brightnessState.actualDDCBrightnessPercent {
                return "\(actual)%"
            }
            if let readback = brightnessState.lastDDCReadbackPercent {
                return "\(readback)%"
            }
        }

        if let requested = brightnessState.requestedDDCBrightnessPercent {
            return "\(requested)% (requested)"
        }

        return "—"
    }

    var brightnessLastSourceText: String {
        brightnessState.lastBrightnessSource.rawValue
    }

    var brightnessReadbackText: String {
        brightnessState.readbackStatusText
    }

    var brightnessDiagnosticInlineText: String {
        "Sensor target: \(brightnessSensorTargetText) · DDC actual: \(brightnessActualText) · Last source: \(brightnessLastSourceText) · Readback: \(brightnessReadbackText)"
    }

    var keepAwakeSummaryText: String {
        keepAwakeCoordinator.keepAwakeSummaryText
    }

    var keepAwakePluggedOnlySummaryText: String {
        keepAwakeCoordinator.keepAwakePluggedOnlySummaryText
    }

    var keepAwakeUntilText: String? {
        keepAwakeCoordinator.keepAwakeUntilText
    }

    func applySoftwareDisconnectedDisplayStateIfNeeded() -> Bool {
        let connection = displayConnectionController.reconcileDesiredState()
        guard connection.phase == .softwareDisconnected else { return false }

        currentDisplayInfo = nil
        currentBrightness = nil
        currentVolume = nil
        volumeKeyRouter?.setEnabled(false)
        availableModes = []
        isHiDPIActive = false
        hiDPIStatusText = "Samsung S60UD yazılımsal olarak ayrıldı"
        currentEDIDSummary = nil
        hdrBrightnessDiagnosticSummary = nil
        ddcBrightnessMaxDiagnosticSummary = nil
        ddcRawBrightnessProbeSummary = nil
        brightnessMappingDiagnosticSummary = nil
        clearManualBrightnessOverride()
        updateBrightnessState { state in
            state.isAutoBrightnessEnabled = false
            state.isBrightnessWriteSuppressed = true
            state.suppressionReason = "Harici ekran yazılımsal olarak ayrıldı"
        }
        updateStatus(connection.message)
        return true
    }

    private func reloadDisplayInfo() async {
        if applySoftwareDisconnectedDisplayStateIfNeeded() {
            return
        }
        let previousDisplayKey = currentDisplayInfo?.displayKey
        if let display = await writer.refreshDisplay(preferredKey: store.preferences.selectedDisplayKey) {
            currentDisplayInfo = display
            store.setSelectedDisplayKey(display.displayKey)
            if display.displayKey != previousDisplayKey {
                luxFilter.reset()
                lastSentBrightness = store.lastBrightness(for: display.displayKey)
                lastWriteDate = .distantPast
                lastBrightnessReadDate = .distantPast
                lastDisplaySearchDate = Date()
                clearManualBrightnessOverride()
                brightnessLimiterCooldownDisplayKey = nil
                brightnessLimiterCooldownUntil = .distantPast
                currentVolume = nil
                lastVolumeReadDate = .distantPast
                hdrBrightnessDiagnosticSummary = nil
                ddcBrightnessMaxDiagnosticSummary = nil
                ddcRawBrightnessProbeSummary = nil
                brightnessMappingDiagnosticSummary = nil
                brightnessState = BrightnessState()
                currentBrightness = nil
            }
            if currentBrightness == nil || display.displayKey != previousDisplayKey {
                let readback = await writer.readBrightness(preferredKey: display.displayKey)
                let fallback = readback ?? store.lastBrightness(for: display.displayKey)
                applyBrightnessReadback(readback, requestedFallback: fallback)
                lastBrightnessReadDate = Date()
            }
            updateAutoBrightnessTitle()
            await refreshCurrentVolume(force: true)
            volumeKeyRouter?.setEnabled(true)
            await reloadDisplayModes()
        } else {
            currentDisplayInfo = nil
            currentBrightness = nil
            clearManualBrightnessOverride()
            currentVolume = nil
            volumeKeyRouter?.setEnabled(false)
            self.availableModes = []
            self.isHiDPIActive = false
            hiDPIStatusText = "Samsung S60UD ekranı bulunamadı"
            hdrBrightnessDiagnosticSummary = nil
            ddcBrightnessMaxDiagnosticSummary = nil
            ddcRawBrightnessProbeSummary = nil
            brightnessMappingDiagnosticSummary = nil
            brightnessState = BrightnessState()
        }
    }

    private func refreshInternalBrightness() {
        currentInternalBrightness = internalBrightnessController?.currentBrightness()
    }

    func refreshDisplay() {
        Task {
            await reloadDisplayInfo()
            refreshInternalBrightness()
            refreshEDIDDiagnosticSummary()
            await tick()
        }
    }

    func refreshRuntimeState() {
        updateAutoBrightnessTitle()
        refreshInternalBrightness()
        Task {
            await tick()
        }
    }

    private func updateCalibrationStatus() {
        guard let session = calibrationSession, let lux = lastSmoothedLux else { return }
        updateStatus("\(session.step.rawValue.capitalized) step: \(String(format: "%.0f", lux)) lux")
    }

    private func refreshEDIDDiagnosticSummary() {
        guard let target = try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics() else {
            currentEDIDSummary = nil
            return
        }
        currentEDIDSummary = DisplayEDIDReader.shared.readEDID(for: target.displayID)
    }

    func readEDIDDiagnostic() {
        guard let target = try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics() else {
            currentEDIDSummary = nil
            updateStatus("EDID diagnostic: target display unavailable")
            return
        }

        let summary = DisplayEDIDReader.shared.readEDID(for: target.displayID)
        currentEDIDSummary = summary
        if let url = DisplayEDIDReader.shared.writeDiagnosticReport(summary: summary) {
            print("EDID diagnostic report written: \(url.path)")
            updateStatus("EDID diagnostic written")
        } else {
            print("EDID diagnostic report write failed")
            updateStatus("EDID diagnostic write failed")
        }
    }

    func readHDRBrightnessDiagnostic() {
        Task { @MainActor in
            let summary = await hdrBrightnessDiagnostic.run(preferredDisplayKey: currentDisplayInfo?.displayKey)
            hdrBrightnessDiagnosticSummary = summary
            do {
                let url = try await hdrBrightnessDiagnostic.writeDiagnosticReport(summary: summary)
                print("HDR brightness diagnostic report written: \(url.path)")
                updateStatus("HDR brightness diagnostic written")
            } catch {
                print("HDR brightness diagnostic report write failed: \(error.localizedDescription)")
                updateStatus("HDR brightness diagnostic write failed")
            }
        }
    }

    func readDDCBrightnessMaxDiagnostic() {
        Task { @MainActor in
            let summary = await ddcBrightnessMaxDiagnostic.run(preferredDisplayKey: currentDisplayInfo?.displayKey)
            ddcBrightnessMaxDiagnosticSummary = summary
            do {
                let url = try await ddcBrightnessMaxDiagnostic.writeDiagnosticReport(summary: summary)
                print("DDC brightness max diagnostic report written: \(url.path)")
                updateStatus("DDC brightness max diagnostic written")
            } catch {
                print("DDC brightness max diagnostic report write failed: \(error.localizedDescription)")
                updateStatus("DDC brightness max diagnostic write failed")
            }
        }
    }

    func readDDCRawBrightnessProbeDiagnostic() {
        Task { @MainActor in
            let summary = await ddcRawBrightnessProbeDiagnostic.run(preferredDisplayKey: currentDisplayInfo?.displayKey)
            ddcRawBrightnessProbeSummary = summary
            do {
                let url = try await ddcRawBrightnessProbeDiagnostic.writeDiagnosticReport(summary: summary)
                print("DDC raw brightness probe report written: \(url.path)")
                updateStatus("DDC raw brightness probe written")
            } catch {
                print("DDC raw brightness probe report write failed: \(error.localizedDescription)")
                updateStatus("DDC raw brightness probe write failed")
            }
        }
    }

    func readBrightnessMappingDiagnostic() {
        Task { @MainActor in
            if let display = currentDisplayInfo {
                let readback = await writer.readBrightness(preferredKey: display.displayKey)
                let rawSample = await writer.readBrightnessRaw(preferredKey: display.displayKey)
                if let rawSample {
                    updateBrightnessState { state in
                        state.lastDDCRawCurrentBefore = rawSample.rawCurrent
                        state.lastDDCRawMax = rawSample.rawMax
                        state.lastDDCRawAfter = rawSample.rawCurrent
                        if let rawCurrent = rawSample.rawCurrent, let rawMax = rawSample.rawMax {
                            state.lastDDCActualPercentAfter = DDCBrightnessScale.uiPercent(fromRawCurrent: rawCurrent, rawMax: rawMax)
                        }
                    }
                }
                applyBrightnessReadback(readback, requestedFallback: store.lastBrightness(for: display.displayKey))
            }

            let summary = brightnessMappingDiagnosticSummarySnapshot()
            brightnessMappingDiagnosticSummary = summary
            do {
                let url = try BrightnessMappingDiagnosticReporter.writeMarkdownReport(summary: summary)
                print("Brightness mapping diagnostic report written: \(url.path)")
                updateStatus("Brightness mapping diagnostic written")
            } catch {
                print("Brightness mapping diagnostic report write failed: \(error.localizedDescription)")
                updateStatus("Brightness mapping diagnostic write failed")
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleKeepAwakeAction() {
        toggleKeepAwake()
    }

    @objc private func refreshDisplayAction() {
        refreshDisplay()
    }

    @objc private func readEDIDDiagnosticAction() {
        readEDIDDiagnostic()
    }

    @objc private func readHDRBrightnessDiagnosticAction() {
        readHDRBrightnessDiagnostic()
    }

    @objc private func readDDCBrightnessMaxDiagnosticAction() {
        readDDCBrightnessMaxDiagnostic()
    }

    @objc private func readDDCRawBrightnessProbeDiagnosticAction() {
        readDDCRawBrightnessProbeDiagnostic()
    }

    @objc private func decreaseVolumeAction() {
        Task { await adjustMonitorVolume(by: -5) }
    }

    @objc private func increaseVolumeAction() {
        Task { await adjustMonitorVolume(by: 5) }
    }

    @objc private func setVolumeFiftyAction() {
        Task { await setMonitorVolume(50) }
    }

    @objc private func toggleMuteAction() {
        Task { await toggleMuteForSettings() }
    }

    func performMonitorVolumeKeyAction(_ action: MonitorVolumeKeyAction) -> Bool {
        Task {
            switch action {
            case .increase:
                await adjustMonitorVolume(by: 5)
            case .decrease:
                await adjustMonitorVolume(by: -5)
            case .mute:
                await toggleMuteForSettings()
            }
        }
        return true
    }

    func adjustMonitorVolumeForSettings(by delta: Int) {
        Task { await adjustMonitorVolume(by: delta) }
    }

    func toggleMuteForSettingsSync() {
        Task { await toggleMuteForSettings() }
    }

    @discardableResult
    func adjustMonitorVolume(by delta: Int) async -> Bool {
        let (success, _) = await writer.changeVolume(delta, preferredKey: activeDisplayKey)
        if success {
            let fallbackBase = monitorVolumeControlValue
            currentVolume = min(100, max(0, fallbackBase + delta))
            volumeFeatureController.persistLastVolume(currentVolume)
            if let currentVolume, currentVolume > 0 {
                lastNonZeroVolume = currentVolume
            }
            if let currentVolume {
                updateStatus("Volume \(currentVolume)%")
            } else {
                updateStatus("Volume changed")
            }
        } else {
            updateStatus("Volume change failed")
        }
        return success
    }

    @discardableResult
    func setMonitorVolume(_ percent: Int) async -> Bool {
        let clamped = min(100, max(0, percent))
        let (success, _) = await writer.setVolume(clamped, preferredKey: activeDisplayKey)
        if success {
            currentVolume = clamped
            volumeFeatureController.persistLastVolume(clamped)
            if clamped > 0 {
                lastNonZeroVolume = clamped
            }
            updateStatus("Volume \(clamped)%")
        } else {
            updateStatus("Volume set failed")
        }
        return success
    }

    @discardableResult
    func toggleMuteForSettings() async -> Bool {
        let volume = monitorVolumeControlValue
        let isMuted = volume == 0
        let targetVolume = isMuted ? max(1, lastNonZeroVolume) : 0
        let (success, _) = await writer.setMute(!isMuted, preferredKey: activeDisplayKey)
        if success {
            currentVolume = targetVolume
            volumeFeatureController.persistLastVolume(targetVolume)
            if targetVolume > 0 {
                lastNonZeroVolume = targetVolume
            }
            updateStatus(!isMuted ? "Muted" : "Unmuted")
        } else {
            updateStatus("Mute failed")
        }
        return success
    }

    func setMonitorVolumeForSettings(_ percent: Int) {
        Task { await setMonitorVolume(percent) }
    }

    func setMonitorBrightness(_ percent: Int) {
        let clamped = min(100, max(0, percent))
        pauseAutoBrightnessTemporarily()
        Task {
            let result = await writer.setBrightness(clamped, preferredKey: activeDisplayKey)
            let actualAfter = result.actualUIPercentAfter ?? result.readbackBrightnessPercent ?? clamped
            let matchedTarget = result.matchedTarget == true
            print(
                """
                requestedUIPercent=\(clamped)
                rawMax=\(result.rawMax.map(String.init) ?? "unavailable")
                computedRawTarget=\(result.computedRawTarget.map(String.init) ?? "unavailable")
                rawBefore=\(result.rawBefore.map(String.init) ?? "unavailable")
                writeResult=\(result.status.rawValue)
                rawAfter=\(result.rawAfter.map(String.init) ?? "unavailable")
                actualUIPercentAfter=\(actualAfter)
                matchedTarget=\(matchedTarget ? "YES" : "NO")
                """
            )
            if result.status == .success || result.status == .writeAcceptedButReadbackLimited {
                lastSentBrightness = clamped
                lastWriteDate = Date()
                beginManualBrightnessOverride()
                if let readback = result.actualUIPercentAfter ?? result.readbackBrightnessPercent {
                    lastBrightnessReadDate = lastWriteDate
                    store.setLastBrightness(readback, for: activeDisplayKey)
                } else {
                    store.setLastBrightness(clamped, for: activeDisplayKey)
                }
                applyBrightnessWriteResult(requested: clamped, source: .quickPanelSlider, result: result)
                if result.status == .writeAcceptedButReadbackLimited {
                    updateStatus(result.message)
                } else {
                    updateStatus(result.actualUIPercentAfter.map { "Brightness \($0)%" } ?? "Brightness \(clamped)%")
                }
            } else {
                applyBrightnessWriteResult(requested: clamped, source: .quickPanelSlider, result: result)
                updateStatus(result.message.isEmpty ? "Parlaklık yazılamadı" : "Parlaklık yazılamadı: \(result.message)")
            }
        }
    }

    @discardableResult
    func setInternalBrightness(_ percent: Int) -> Bool {
        guard let controller = internalBrightnessController else {
            updateStatus("Dahili parlaklık kontrolü kullanılamıyor")
            return false
        }

        let (success, message) = controller.setBrightness(percent)
        if success {
            currentInternalBrightness = controller.currentBrightness() ?? min(100, max(0, percent))
            updateStatus("Dahili parlaklık %\(currentInternalBrightness ?? percent)")
        } else {
            currentInternalBrightness = controller.currentBrightness()
            updateStatus("Dahili parlaklık ayarlanamadı: \(message)")
        }
        return success
    }

    func pauseAutoBrightnessTemporarily(for duration: TimeInterval = 20) {
        beginManualBrightnessOverride(fallbackDuration: duration)
    }

    func setAutoBrightnessEnabled(_ enabled: Bool) {
        guard autoBrightnessEnabled != enabled else { return }
        autoBrightnessEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "AmbientSync.AutoBrightnessEnabled")

        if enabled {
            clearManualBrightnessOverride()
            updateStatus("Otomatik parlaklık açıldı")
        } else {
            pendingTargetCandidate = nil
            updateBrightnessState { state in
                state.isAutoBrightnessEnabled = false
                state.isManualOverrideActive = false
                state.isBrightnessWriteSuppressed = true
                state.suppressionReason = "Automatic brightness is disabled"
            }
            updateStatus("Otomatik parlaklık kapalı")
        }
    }

    private func beginManualBrightnessOverride(fallbackDuration: TimeInterval = 20) {
        if manualBrightnessOverrideStartLux == nil {
            manualBrightnessOverrideStartLux = lastSmoothedLux ?? currentLux
        }
        if manualBrightnessOverrideStartLux == nil {
            manualBrightnessOverrideUntil = max(manualBrightnessOverrideUntil, Date().addingTimeInterval(fallbackDuration))
        } else {
            manualBrightnessOverrideUntil = .distantPast
        }
        pendingTargetCandidate = nil
        updateBrightnessState { state in
            state.isManualOverrideActive = true
            state.isAutoBrightnessEnabled = false
        }
    }

    private func clearManualBrightnessOverride() {
        manualBrightnessOverrideStartLux = nil
        manualBrightnessOverrideUntil = .distantPast
        pendingTargetCandidate = nil
        updateBrightnessState { state in
            state.isManualOverrideActive = false
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil
        }
    }

    private func shouldHoldManualBrightnessOverride(currentLux: Double, now: Date) -> Bool {
        let shouldContinue = brightnessAutoController.shouldContinueManualOverride(
            currentLux: currentLux,
            startLux: manualBrightnessOverrideStartLux,
            overrideUntil: manualBrightnessOverrideUntil,
            now: now
        )

        guard shouldContinue else {
            clearManualBrightnessOverride()
            return false
        }

        if manualBrightnessOverrideStartLux == nil && now < manualBrightnessOverrideUntil {
            manualBrightnessOverrideStartLux = currentLux
            manualBrightnessOverrideUntil = .distantPast
        }

        return true
    }

    @discardableResult
    private func setHiDPIEnabled(_ enabled: Bool) async -> Bool {
        do {
            let target = try HiDPITargetDisplayResolver.resolveSamsungS60UD()
            let _ = cgsModeSwitcher.scanCGSModes(displayID: target.displayID)
            let status = cgsModeSwitcher.refreshCGSModes(displayID: target.displayID)
            cgsManualModeSwitcherSummary = status
            cgsManualModeSwitcherStatusText = status.currentModeText

            guard status.isSamsungFingerprintMatched, !status.isBuiltin else {
                hiDPIStatusText = "Mevcut Mod: bilinmiyor"
                hiDPIActivationStatusText = "Samsung fingerprint doğrulanamadı."
                return false
            }

            let dynamicHiDPI = cgsModeSwitcher.findBestHiDPIMode(
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                targetPixelWidth: 5120,
                targetPixelHeight: 2880,
                preferredRefreshRate: 100.0
            )
            let fallbackHiDPI = dynamicHiDPI == nil ? cgsModeSwitcher.verifiedSamsungFallbackCandidate(
                modeID: 74,
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                targetPixelWidth: 5120,
                targetPixelHeight: 2880,
                preferredRefreshRate: 100.0,
                expectedHiDPI: true
            ) : nil

            let dynamicNormal = cgsModeSwitcher.findBestNormalMode(
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                preferredRefreshRate: 100.0
            )
            let fallbackNormal = dynamicNormal == nil ? cgsModeSwitcher.verifiedSamsungFallbackCandidate(
                modeID: 56,
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                targetPixelWidth: 2560,
                targetPixelHeight: 1440,
                preferredRefreshRate: 100.0,
                expectedHiDPI: false
            ) : nil

            let selection = hiDPIFeatureController.chooseActivationCandidate(
                enabled: enabled,
                dynamicHiDPI: dynamicHiDPI,
                fallbackHiDPI: fallbackHiDPI,
                dynamicNormal: dynamicNormal,
                fallbackNormal: fallbackNormal
            )

            guard let selectedCandidate = selection.selectedCandidate else {
                hiDPIActivationStatusText = selection.statusMessage
                updateStatus(selection.updateMessage)
                return false
            }

            let report = cgsModeSwitcher.applyCGSMode(modeID: Int(selectedCandidate.modeID))
            if report.success {
                persistHiDPIState(enabled: enabled)
                hiDPIStatusText = "Mevcut Mod: \(selectedCandidate.logicalWidth)x\(selectedCandidate.logicalHeight) / \(selectedCandidate.pixelWidth)x\(selectedCandidate.pixelHeight) @\(Int(selectedCandidate.refreshRate.rounded()))Hz"
                isHiDPIActive = enabled
                updateStatus(selection.updateMessage)
                await reloadDisplayModes()
                return true
            }

            hiDPIActivationStatusText = report.failureReason ?? selection.statusMessage
            updateStatus(enabled ? "HiDPI açma başarısız" : "HiDPI kapatma başarısız")
            return false
        } catch {
            hiDPIStatusText = "Mevcut Mod: bilinmiyor"
            hiDPIActivationStatusText = "Samsung ekran bulunamadı."
            updateStatus("HiDPI işlemi başarısız")
            return false
        }
    }

    @objc func applyRetinaMode() {
        Task {
            await setHiDPIEnabled(true)
        }
    }

    @objc func disableRetinaModeAction() {
        disableRetinaMode()
    }

    func disableRetinaMode() {
        Task {
            await setHiDPIEnabled(false)
        }
    }

    @objc func emergencyResetRetinaModeAction() {
        emergencyResetRetinaMode()
    }

    func emergencyResetRetinaMode() {
        disableRetinaMode()
    }

    @objc func runHiDPIModePoolDiagnosticAction() {
        Task {
            HiDPIDiagnostic.runModePoolDiagnostic()
            updateStatus("HiDPI mode pool diagnostic completed")
        }
    }

    @objc func runExperimentalHiDPIActivationAction() {
        Task {
            hiDPIActivationStatusText = "Private SLS transaction activation çalışıyor..."
            updateStatus("Private SLS transaction running")
            let result = PrivateHiDPIActivationEngine.shared.runSLSTransactionActivationExperiment()
            hiDPIActivationStatusText = "\(result). Report: docs/generated/private_activation/sls_transaction_activation_experiment.md"
            await reloadDisplayModes()
        }
    }

    @objc func runCGSModeEnumerationAction() {
        Task {
            do {
                let summary = try CGSModeEnumerationDiagnostic.runEnumeration()
                cgsModeEnumerationSummary = summary
                let reportPath = summary.reportURL.path
                let current = summary.currentModeID.map(String.init) ?? "unavailable"
                cgsModeEnumerationStatusText = "CGS current mode: \(current) | CGS count: \(summary.cgsModeCount) | public dup: \(summary.publicDuplicateModeCount) | Report: \(reportPath)"
                updateStatus("CGS mode enumeration completed")
            } catch {
                cgsModeEnumerationStatusText = "CGS mode enumeration failed: \(error.localizedDescription)"
                updateStatus("CGS mode enumeration failed")
            }
        }
    }

    @objc func runCGSMode74WithoutBetterDisplayCheckAction() {
        Task {
            do {
                let summary = try CGSModeEnumerationDiagnostic.runWithoutBetterDisplayVerification()
                cgsModeEnumerationSummary = summary
                let reportPath = summary.reportURL.path
                let current = summary.currentModeID.map(String.init) ?? "unavailable"
                cgsModeEnumerationStatusText = "CGS current mode: \(current) | CGS count: \(summary.cgsModeCount) | public dup: \(summary.publicDuplicateModeCount) | mode74: \(summary.mode74 != nil ? "present" : "missing") | Report: \(reportPath)"
                updateStatus("CGS mode 74 check completed")
            } catch {
                cgsModeEnumerationStatusText = "CGS mode 74 check failed: \(error.localizedDescription)"
                updateStatus("CGS mode 74 check failed")
            }
        }
    }

    @objc func applyCGSMode56Action() {
        Task {
            guard let summary = cgsManualModeSwitcherSummary, summary.canApplyMode56 else {
                cgsManualModeSwitcherStatusText = "Current CGS Mode: unavailable"
                updateStatus("CGS mode 56 apply blocked")
                return
            }

            let report = cgsModeSwitcher.applyCGSMode(modeID: 56)
            refreshCGSModeSwitcherState()
            if report.success {
                updateStatus("CGS mode 56 applied")
            } else {
                updateStatus("CGS mode 56 apply failed")
            }
        }
    }

    @objc func applyCGSMode74Action() {
        Task {
            guard let summary = cgsManualModeSwitcherSummary, summary.canApplyMode74 else {
                cgsManualModeSwitcherStatusText = "Current CGS Mode: unavailable"
                updateStatus("CGS mode 74 apply blocked")
                return
            }

            let report = cgsModeSwitcher.applyCGSMode(modeID: 74)
            refreshCGSModeSwitcherState()
            if report.success {
                updateStatus("CGS mode 74 applied")
            } else {
                updateStatus("CGS mode 74 apply failed")
            }
        }
    }

    @objc func applyCGSMode56NormalQHDTransactionAction() {
        Task {
            guard let summary = cgsModeEnumerationSummary else {
                cgsModeApplyExperimentStatusText = "CGS enumeration önce çalıştırılmalı."
                updateStatus("CGS mode 56 apply blocked")
                return
            }

            guard summary.mode56IsNormalQHD else {
                cgsModeApplyExperimentStatusText = "Mode 56 doğrulanmadı; apply pasif."
                updateStatus("CGS mode 56 apply blocked")
                return
            }

            do {
                let experiment = try CGSModeEnumerationDiagnostic.runMode56NormalQHDApplyExperiment(using: cgsModeApplyExperimentSummary)
                cgsModeApplyExperimentSummary = experiment
                cgsModeEnumerationSummary = experiment.finalSummary
                let reportPath = experiment.reportURL.path
                cgsModeApplyExperimentStatusText = "Mode 56: \(experiment.mode56Outcome?.applyResultDescription ?? "not attempted") | Final: \(experiment.finalSummary.activeModeDescription) | Report: \(reportPath)"
                updateStatus("CGS mode 56 apply completed")
                await reloadDisplayModes()
            } catch {
                cgsModeApplyExperimentStatusText = "CGS mode 56 apply failed: \(error.localizedDescription)"
                updateStatus("CGS mode 56 apply failed")
            }
        }
    }

    @objc func applyCGSMode74TransactionAction() {
        Task {
            guard let summary = cgsModeEnumerationSummary else {
                cgsModeApplyExperimentStatusText = "CGS enumeration önce çalıştırılmalı."
                updateStatus("CGS mode 74 apply blocked")
                return
            }

            guard summary.canApplyMode74Transaction else {
                cgsModeApplyExperimentStatusText = "Mode 74 doğrulanmadı; apply pasif."
                updateStatus("CGS mode 74 apply blocked")
                return
            }

            do {
                let experiment = try CGSModeEnumerationDiagnostic.runMode74ApplyExperiment(using: cgsModeApplyExperimentSummary)
                cgsModeApplyExperimentSummary = experiment
                cgsModeEnumerationSummary = experiment.finalSummary
                let reportPath = experiment.reportURL.path
                cgsModeApplyExperimentStatusText = "Mode 74: \(experiment.mode74Outcome?.applyResultDescription ?? "not attempted") | Final: \(experiment.finalSummary.activeModeDescription) | Report: \(reportPath)"
                updateStatus("CGS mode 74 apply completed")
                await reloadDisplayModes()
            } catch {
                cgsModeApplyExperimentStatusText = "CGS mode 74 apply failed: \(error.localizedDescription)"
                updateStatus("CGS mode 74 apply failed")
            }
        }
    }

    func startCalibration() {
        let key = activeDisplayKey
        let settings = store.ensureSettings(for: key)
        calibrationSession = CalibrationSession(
            displayKey: key,
            profileID: settings.selectedProfileID,
            step: .low,
            lowLux: nil,
            midLux: nil,
            highLux: nil
        )
        updateAutoBrightnessTitle()
        updateCalibrationStatus()
    }

    func captureCalibrationStep() {
        guard var session = calibrationSession, let lux = lastSmoothedLux else { return }
        switch session.step {
        case .low:
            session.lowLux = lux
            session.step = .mid
        case .mid:
            session.midLux = lux
            session.step = .high
        case .high:
            session.highLux = lux
            finalizeCalibration(session)
            return
        }
        calibrationSession = session
        updateCalibrationStatus()
    }

    func cancelCalibration() {
        guard calibrationSession != nil else { return }
        calibrationSession = nil
        updateAutoBrightnessTitle()
        updateStatus("Calibration cancelled")
    }

    private func finalizeCalibration(_ session: CalibrationSession) {
        guard
            let lowLux = session.lowLux,
            let midLux = session.midLux,
            let highLux = session.highLux
        else {
            cancelCalibration()
            return
        }

        let calibration = DisplayCalibration(lowLux: lowLux, midLux: midLux, highLux: highLux)
        store.setCalibration(calibration, for: session.displayKey)
        calibrationSession = nil
        updateAutoBrightnessTitle()
        updateStatus("Calibration saved")
        Task {
            await tick()
        }
    }

}
