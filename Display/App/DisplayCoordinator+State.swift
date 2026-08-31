import Foundation

/// Compatibility-facing state accessors. Storage and observation live in
/// DisplayRuntimeState; this extension keeps the application feature API
/// stable while making ownership explicit.
extension DisplayCoordinator {
    var ddcAvailable: Bool {
        get { runtimeState.ddcAvailable }
        set { runtimeState.ddcAvailable = newValue }
    }
    var capabilities: DisplayCapabilities { runtimeState.capabilities }
    var autoBrightnessEnabled: Bool {
        get { runtimeState.autoBrightnessEnabled }
        set { runtimeState.autoBrightnessEnabled = newValue }
    }
    var isTickRunning: Bool {
        get { runtimeState.isTickRunning }
        set { runtimeState.isTickRunning = newValue }
    }
    var lastSmoothedLux: Double? {
        get { runtimeState.lastSmoothedLux }
        set { runtimeState.lastSmoothedLux = newValue }
    }
    var lastSentBrightness: Int? {
        get { runtimeState.lastSentBrightness }
        set { runtimeState.lastSentBrightness = newValue }
    }
    var lastWriteDate: Date {
        get { runtimeState.lastWriteDate }
        set { runtimeState.lastWriteDate = newValue }
    }
    var lastBrightnessReadDate: Date {
        get { runtimeState.lastBrightnessReadDate }
        set { runtimeState.lastBrightnessReadDate = newValue }
    }
    var lastDisplaySearchDate: Date {
        get { runtimeState.lastDisplaySearchDate }
        set { runtimeState.lastDisplaySearchDate = newValue }
    }
    var brightnessReadInterval: TimeInterval { runtimeState.brightnessReadInterval }
    var displaySearchInterval: TimeInterval { runtimeState.displaySearchInterval }
    var manualBrightnessOverrideUntil: Date {
        get { runtimeState.manualBrightnessOverrideUntil }
        set { runtimeState.manualBrightnessOverrideUntil = newValue }
    }
    var autoBrightnessSuppressedUntil: Date {
        get { runtimeState.autoBrightnessSuppressedUntil }
        set { runtimeState.autoBrightnessSuppressedUntil = newValue }
    }
    var manualBrightnessOverrideStartLux: Double? {
        get { runtimeState.manualBrightnessOverrideStartLux }
        set { runtimeState.manualBrightnessOverrideStartLux = newValue }
    }
    var pendingTargetCandidate: Int? {
        get { runtimeState.pendingTargetCandidate }
        set { runtimeState.pendingTargetCandidate = newValue }
    }
    var pendingTargetCandidateSince: Date {
        get { runtimeState.pendingTargetCandidateSince }
        set { runtimeState.pendingTargetCandidateSince = newValue }
    }
    var mismatchIntervalsCount: Int {
        get { runtimeState.mismatchIntervalsCount }
        set { runtimeState.mismatchIntervalsCount = newValue }
    }
    var brightnessLimiterCooldownUntil: Date {
        get { runtimeState.brightnessLimiterCooldownUntil }
        set { runtimeState.brightnessLimiterCooldownUntil = newValue }
    }
    var brightnessLimiterCooldownDisplayKey: String? {
        get { runtimeState.brightnessLimiterCooldownDisplayKey }
        set { runtimeState.brightnessLimiterCooldownDisplayKey = newValue }
    }
    var brightnessLimiterCooldownDuration: TimeInterval { runtimeState.brightnessLimiterCooldownDuration }
    var volumeReadInterval: TimeInterval { runtimeState.volumeReadInterval }
    var lastVolumeReadDate: Date {
        get { runtimeState.lastVolumeReadDate }
        set { runtimeState.lastVolumeReadDate = newValue }
    }

    var keepAwakeState: KeepAwakeState {
        get { runtimeState.keepAwakeState }
        set { runtimeState.keepAwakeState = newValue }
    }
    var currentIdleTimeString: String {
        get { runtimeState.currentIdleTimeString }
        set { runtimeState.currentIdleTimeString = newValue }
    }
    var remainingIdleTimeString: String {
        get { runtimeState.remainingIdleTimeString }
        set { runtimeState.remainingIdleTimeString = newValue }
    }
    var isAwakeAssertionActive: Bool { keepAwakeCoordinator.isActive }

    var statusText: String {
        get { runtimeState.statusText }
        set { runtimeState.statusText = newValue }
    }
    var currentLux: Double? {
        get { runtimeState.currentLux }
        set { runtimeState.currentLux = newValue }
    }
    var currentBrightness: Int? {
        get { runtimeState.currentBrightness }
        set { runtimeState.currentBrightness = newValue }
    }
    var currentInternalBrightness: Int? {
        get { runtimeState.currentInternalBrightness }
        set { runtimeState.currentInternalBrightness = newValue }
    }
    var currentVolume: Int? {
        get { runtimeState.currentVolume }
        set { runtimeState.currentVolume = newValue }
    }
    var currentDisplayInfo: ExternalDisplayInfo? {
        get { runtimeState.currentDisplayInfo }
        set { runtimeState.currentDisplayInfo = newValue }
    }
    var hiDPIStatusText: String {
        get { runtimeState.hiDPIStatusText }
        set { runtimeState.hiDPIStatusText = newValue }
    }
    var hiDPIActivationStatusText: String {
        get { runtimeState.hiDPIActivationStatusText }
        set { runtimeState.hiDPIActivationStatusText = newValue }
    }
    var cgsModeEnumerationStatusText: String {
        get { runtimeState.cgsModeEnumerationStatusText }
        set { runtimeState.cgsModeEnumerationStatusText = newValue }
    }
    var cgsModeEnumerationSummary: CGSModeEnumerationSummary? {
        get { runtimeState.cgsModeEnumerationSummary }
        set { runtimeState.cgsModeEnumerationSummary = newValue }
    }
    var cgsModeApplyExperimentStatusText: String {
        get { runtimeState.cgsModeApplyExperimentStatusText }
        set { runtimeState.cgsModeApplyExperimentStatusText = newValue }
    }
    var cgsModeApplyExperimentSummary: CGSModeApplyExperimentSummary? {
        get { runtimeState.cgsModeApplyExperimentSummary }
        set { runtimeState.cgsModeApplyExperimentSummary = newValue }
    }
    var cgsManualModeSwitcherStatusText: String {
        get { runtimeState.cgsManualModeSwitcherStatusText }
        set { runtimeState.cgsManualModeSwitcherStatusText = newValue }
    }
    var cgsManualModeSwitcherSummary: CGSModeSwitcherStatus? {
        get { runtimeState.cgsManualModeSwitcherSummary }
        set { runtimeState.cgsManualModeSwitcherSummary = newValue }
    }
    var cgsDynamicSelectionState: CGSDynamicModeSelectionState? {
        get { runtimeState.cgsDynamicSelectionState }
        set { runtimeState.cgsDynamicSelectionState = newValue }
    }
    var cgsSamsungFallbackUsed: Bool {
        get { runtimeState.cgsSamsungFallbackUsed }
        set { runtimeState.cgsSamsungFallbackUsed = newValue }
    }
    var cgsSelectedHiDPICandidate: CGSDisplayModeCandidate? {
        get { runtimeState.cgsSelectedHiDPICandidate }
        set { runtimeState.cgsSelectedHiDPICandidate = newValue }
    }
    var cgsSelectedNormalCandidate: CGSDisplayModeCandidate? {
        get { runtimeState.cgsSelectedNormalCandidate }
        set { runtimeState.cgsSelectedNormalCandidate = newValue }
    }
    var availableModes: [PhysicalDisplayMode] {
        get { runtimeState.availableModes }
        set { runtimeState.availableModes = newValue }
    }
    var isHiDPIActive: Bool {
        get { runtimeState.isHiDPIActive }
        set { runtimeState.isHiDPIActive = newValue }
    }
    var calibrationSession: CalibrationSession? {
        get { runtimeState.calibrationSession }
        set { runtimeState.calibrationSession = newValue }
    }
    var currentEDIDSummary: EDIDDiagnosticSummary? {
        get { runtimeState.currentEDIDSummary }
        set { runtimeState.currentEDIDSummary = newValue }
    }
    var hdrBrightnessDiagnosticSummary: HDRBrightnessDiagnosticSummary? {
        get { runtimeState.hdrBrightnessDiagnosticSummary }
        set { runtimeState.hdrBrightnessDiagnosticSummary = newValue }
    }
    var ddcBrightnessMaxDiagnosticSummary: DDCBrightnessMaxDiagnosticSummary? {
        get { runtimeState.ddcBrightnessMaxDiagnosticSummary }
        set { runtimeState.ddcBrightnessMaxDiagnosticSummary = newValue }
    }
    var ddcRawBrightnessProbeSummary: DDCRawBrightnessProbeSummary? {
        get { runtimeState.ddcRawBrightnessProbeSummary }
        set { runtimeState.ddcRawBrightnessProbeSummary = newValue }
    }
    var brightnessMappingDiagnosticSummary: BrightnessMappingDiagnosticSummary? {
        get { runtimeState.brightnessMappingDiagnosticSummary }
        set { runtimeState.brightnessMappingDiagnosticSummary = newValue }
    }
    var brightnessState: BrightnessState {
        get { runtimeState.brightnessState }
        set { runtimeState.brightnessState = newValue }
    }
}
