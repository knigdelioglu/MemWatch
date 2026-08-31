import Combine
import Foundation

/// Owns the mutable state for the brightness policy and its sensor/DDC
/// readback. The other runtime state owners below follow the same boundary.
@MainActor
final class DisplayBrightnessRuntimeState: ObservableObject {
    @Published var ddcAvailable = false
    @Published var autoBrightnessEnabled: Bool
    @Published var currentLux: Double?
    @Published var currentBrightness: Int?
    @Published var brightnessState = BrightnessState()

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
    var mismatchIntervalsCount = 0
    var brightnessLimiterCooldownUntil = Date.distantPast
    var brightnessLimiterCooldownDisplayKey: String?
    let brightnessLimiterCooldownDuration: TimeInterval = 120.0

    init(autoBrightnessEnabled: Bool) {
        self.autoBrightnessEnabled = autoBrightnessEnabled
    }
}

@MainActor
final class DisplayVolumeRuntimeState: ObservableObject {
    @Published var currentVolume: Int?
    var lastVolumeReadDate = Date.distantPast
    let volumeReadInterval: TimeInterval = 5.0
}

@MainActor
final class DisplayDiagnosticsRuntimeState: ObservableObject {
    @Published var capabilities = DisplayCapabilities.unavailable
    @Published var currentInternalBrightness: Int?
    @Published var currentDisplayInfo: ExternalDisplayInfo?
    @Published var currentEDIDSummary: EDIDDiagnosticSummary?
    @Published var hdrBrightnessDiagnosticSummary: HDRBrightnessDiagnosticSummary?
    @Published var ddcBrightnessMaxDiagnosticSummary: DDCBrightnessMaxDiagnosticSummary?
    @Published var ddcRawBrightnessProbeSummary: DDCRawBrightnessProbeSummary?
    @Published var brightnessMappingDiagnosticSummary: BrightnessMappingDiagnosticSummary?
}

/// HiDPI/CGS values are kept together because they are produced by the same
/// mode discovery and activation pipeline.
@MainActor
final class DisplayHiDPIRuntimeState: ObservableObject {
    @Published var hiDPIStatusText = "Mevcut Mod: bilinmiyor"
    @Published var hiDPIActivationStatusText = "HiDPI disabled"
    @Published var cgsModeEnumerationStatusText = "CGS mode enumeration henüz çalıştırılmadı."
    @Published var cgsModeEnumerationSummary: CGSModeEnumerationSummary?
    @Published var cgsModeApplyExperimentStatusText = "CGS apply experiment henüz çalıştırılmadı."
    @Published var cgsModeApplyExperimentSummary: CGSModeApplyExperimentSummary?
    @Published var cgsManualModeSwitcherStatusText = "Current CGS Mode: unavailable"
    @Published var cgsManualModeSwitcherSummary: CGSModeSwitcherStatus?
    @Published var cgsDynamicSelectionState: CGSDynamicModeSelectionState?
    @Published var cgsSamsungFallbackUsed = false
    @Published var cgsSelectedHiDPICandidate: CGSDisplayModeCandidate?
    @Published var cgsSelectedNormalCandidate: CGSDisplayModeCandidate?
    @Published var availableModes: [PhysicalDisplayMode] = []
    @Published var isHiDPIActive = false
    @Published var calibrationSession: CalibrationSession?
}

/// Aggregates domain owners and forwards their change notifications so the
/// application-level ObservableObject remains the single UI observation point.
@MainActor
final class DisplayRuntimeState: ObservableObject {
    let brightness: DisplayBrightnessRuntimeState
    let volume: DisplayVolumeRuntimeState
    let diagnostics: DisplayDiagnosticsRuntimeState
    let hiDPI: DisplayHiDPIRuntimeState

    @Published var keepAwakeState: KeepAwakeState
    @Published var currentIdleTimeString = "00:00"
    @Published var remainingIdleTimeString = "--:--"
    @Published var statusText = "Başlatılıyor..."

    private var childObservations = Set<AnyCancellable>()

    init(autoBrightnessEnabled: Bool, keepAwakeState: KeepAwakeState) {
        self.brightness = DisplayBrightnessRuntimeState(autoBrightnessEnabled: autoBrightnessEnabled)
        self.volume = DisplayVolumeRuntimeState()
        self.diagnostics = DisplayDiagnosticsRuntimeState()
        self.hiDPI = DisplayHiDPIRuntimeState()
        self.keepAwakeState = keepAwakeState

        brightness.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childObservations)
        volume.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childObservations)
        diagnostics.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childObservations)
        hiDPI.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childObservations)
    }

    var ddcAvailable: Bool {
        get { brightness.ddcAvailable }
        set { brightness.ddcAvailable = newValue }
    }
    var capabilities: DisplayCapabilities {
        get { diagnostics.capabilities }
        set { diagnostics.capabilities = newValue }
    }
    var autoBrightnessEnabled: Bool {
        get { brightness.autoBrightnessEnabled }
        set { brightness.autoBrightnessEnabled = newValue }
    }
    var isTickRunning: Bool {
        get { brightness.isTickRunning }
        set { brightness.isTickRunning = newValue }
    }
    var lastSmoothedLux: Double? {
        get { brightness.lastSmoothedLux }
        set { brightness.lastSmoothedLux = newValue }
    }
    var lastSentBrightness: Int? {
        get { brightness.lastSentBrightness }
        set { brightness.lastSentBrightness = newValue }
    }
    var lastWriteDate: Date {
        get { brightness.lastWriteDate }
        set { brightness.lastWriteDate = newValue }
    }
    var lastBrightnessReadDate: Date {
        get { brightness.lastBrightnessReadDate }
        set { brightness.lastBrightnessReadDate = newValue }
    }
    var lastDisplaySearchDate: Date {
        get { brightness.lastDisplaySearchDate }
        set { brightness.lastDisplaySearchDate = newValue }
    }
    var brightnessReadInterval: TimeInterval { brightness.brightnessReadInterval }
    var displaySearchInterval: TimeInterval { brightness.displaySearchInterval }
    var manualBrightnessOverrideUntil: Date {
        get { brightness.manualBrightnessOverrideUntil }
        set { brightness.manualBrightnessOverrideUntil = newValue }
    }
    var autoBrightnessSuppressedUntil: Date {
        get { brightness.autoBrightnessSuppressedUntil }
        set { brightness.autoBrightnessSuppressedUntil = newValue }
    }
    var manualBrightnessOverrideStartLux: Double? {
        get { brightness.manualBrightnessOverrideStartLux }
        set { brightness.manualBrightnessOverrideStartLux = newValue }
    }
    var pendingTargetCandidate: Int? {
        get { brightness.pendingTargetCandidate }
        set { brightness.pendingTargetCandidate = newValue }
    }
    var pendingTargetCandidateSince: Date {
        get { brightness.pendingTargetCandidateSince }
        set { brightness.pendingTargetCandidateSince = newValue }
    }
    var mismatchIntervalsCount: Int {
        get { brightness.mismatchIntervalsCount }
        set { brightness.mismatchIntervalsCount = newValue }
    }
    var brightnessLimiterCooldownUntil: Date {
        get { brightness.brightnessLimiterCooldownUntil }
        set { brightness.brightnessLimiterCooldownUntil = newValue }
    }
    var brightnessLimiterCooldownDisplayKey: String? {
        get { brightness.brightnessLimiterCooldownDisplayKey }
        set { brightness.brightnessLimiterCooldownDisplayKey = newValue }
    }
    var brightnessLimiterCooldownDuration: TimeInterval { brightness.brightnessLimiterCooldownDuration }
    var volumeReadInterval: TimeInterval { volume.volumeReadInterval }
    var lastVolumeReadDate: Date {
        get { volume.lastVolumeReadDate }
        set { volume.lastVolumeReadDate = newValue }
    }
    var currentLux: Double? {
        get { brightness.currentLux }
        set { brightness.currentLux = newValue }
    }
    var currentBrightness: Int? {
        get { brightness.currentBrightness }
        set { brightness.currentBrightness = newValue }
    }
    var currentInternalBrightness: Int? {
        get { diagnostics.currentInternalBrightness }
        set { diagnostics.currentInternalBrightness = newValue }
    }
    var currentVolume: Int? {
        get { volume.currentVolume }
        set { volume.currentVolume = newValue }
    }
    var currentDisplayInfo: ExternalDisplayInfo? {
        get { diagnostics.currentDisplayInfo }
        set { diagnostics.currentDisplayInfo = newValue }
    }
    var hiDPIStatusText: String {
        get { hiDPI.hiDPIStatusText }
        set { hiDPI.hiDPIStatusText = newValue }
    }
    var hiDPIActivationStatusText: String {
        get { hiDPI.hiDPIActivationStatusText }
        set { hiDPI.hiDPIActivationStatusText = newValue }
    }
    var cgsModeEnumerationStatusText: String {
        get { hiDPI.cgsModeEnumerationStatusText }
        set { hiDPI.cgsModeEnumerationStatusText = newValue }
    }
    var cgsModeEnumerationSummary: CGSModeEnumerationSummary? {
        get { hiDPI.cgsModeEnumerationSummary }
        set { hiDPI.cgsModeEnumerationSummary = newValue }
    }
    var cgsModeApplyExperimentStatusText: String {
        get { hiDPI.cgsModeApplyExperimentStatusText }
        set { hiDPI.cgsModeApplyExperimentStatusText = newValue }
    }
    var cgsModeApplyExperimentSummary: CGSModeApplyExperimentSummary? {
        get { hiDPI.cgsModeApplyExperimentSummary }
        set { hiDPI.cgsModeApplyExperimentSummary = newValue }
    }
    var cgsManualModeSwitcherStatusText: String {
        get { hiDPI.cgsManualModeSwitcherStatusText }
        set { hiDPI.cgsManualModeSwitcherStatusText = newValue }
    }
    var cgsManualModeSwitcherSummary: CGSModeSwitcherStatus? {
        get { hiDPI.cgsManualModeSwitcherSummary }
        set { hiDPI.cgsManualModeSwitcherSummary = newValue }
    }
    var cgsDynamicSelectionState: CGSDynamicModeSelectionState? {
        get { hiDPI.cgsDynamicSelectionState }
        set { hiDPI.cgsDynamicSelectionState = newValue }
    }
    var cgsSamsungFallbackUsed: Bool {
        get { hiDPI.cgsSamsungFallbackUsed }
        set { hiDPI.cgsSamsungFallbackUsed = newValue }
    }
    var cgsSelectedHiDPICandidate: CGSDisplayModeCandidate? {
        get { hiDPI.cgsSelectedHiDPICandidate }
        set { hiDPI.cgsSelectedHiDPICandidate = newValue }
    }
    var cgsSelectedNormalCandidate: CGSDisplayModeCandidate? {
        get { hiDPI.cgsSelectedNormalCandidate }
        set { hiDPI.cgsSelectedNormalCandidate = newValue }
    }
    var availableModes: [PhysicalDisplayMode] {
        get { hiDPI.availableModes }
        set { hiDPI.availableModes = newValue }
    }
    var isHiDPIActive: Bool {
        get { hiDPI.isHiDPIActive }
        set { hiDPI.isHiDPIActive = newValue }
    }
    var calibrationSession: CalibrationSession? {
        get { hiDPI.calibrationSession }
        set { hiDPI.calibrationSession = newValue }
    }
    var currentEDIDSummary: EDIDDiagnosticSummary? {
        get { diagnostics.currentEDIDSummary }
        set { diagnostics.currentEDIDSummary = newValue }
    }
    var hdrBrightnessDiagnosticSummary: HDRBrightnessDiagnosticSummary? {
        get { diagnostics.hdrBrightnessDiagnosticSummary }
        set { diagnostics.hdrBrightnessDiagnosticSummary = newValue }
    }
    var ddcBrightnessMaxDiagnosticSummary: DDCBrightnessMaxDiagnosticSummary? {
        get { diagnostics.ddcBrightnessMaxDiagnosticSummary }
        set { diagnostics.ddcBrightnessMaxDiagnosticSummary = newValue }
    }
    var ddcRawBrightnessProbeSummary: DDCRawBrightnessProbeSummary? {
        get { diagnostics.ddcRawBrightnessProbeSummary }
        set { diagnostics.ddcRawBrightnessProbeSummary = newValue }
    }
    var brightnessMappingDiagnosticSummary: BrightnessMappingDiagnosticSummary? {
        get { diagnostics.brightnessMappingDiagnosticSummary }
        set { diagnostics.brightnessMappingDiagnosticSummary = newValue }
    }
    var brightnessState: BrightnessState {
        get { brightness.brightnessState }
        set { brightness.brightnessState = newValue }
    }
}
