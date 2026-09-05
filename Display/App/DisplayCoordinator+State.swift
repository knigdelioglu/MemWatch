import CoreGraphics
import Foundation

/// Compatibility-facing state accessors. Storage and observation live in
/// DisplayRuntimeState; this extension keeps the application feature API
/// stable while making ownership explicit.
extension DisplayCoordinator {
    func traceRuntime(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["MEMWATCH_DISPLAY_RUNTIME_TRACE"] == "1" else { return }
        let line = "[MemWatch DisplayRuntime] \(message())\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    func publishCurrentDisplayInfo(_ display: ExternalDisplayInfo?, reason: String) {
        let previousKey = currentDisplayInfo?.displayKey ?? "nil"
        currentDisplayInfo = display
        let nextKey = display?.displayKey ?? "nil"
        traceRuntime(
            "currentDisplayInfo assigned previous=\(previousKey) next=\(nextKey) reason=\(reason)"
        )
    }

    var ddcAvailable: Bool {
        get { runtimeState.ddcAvailable }
        set { runtimeState.ddcAvailable = newValue }
    }
    var displayPowerState: DisplayPowerState { runtimeState.powerLifecycle.state }
    var displayPowerGeneration: UInt64 { runtimeState.powerLifecycle.generation }
    var targetDisplayReadiness: TargetDisplayReadiness {
        let snapshot = targetDisplayOperationGate.snapshot()
        guard let displayID = snapshot.displayID else { return snapshot.readiness }

        // A ready enum value is not enough to authorize a new external
        // operation. Revalidate the live identity at the coordinator boundary
        // so an offline/inactive display cannot leave a stale ready state.
        guard CGDisplayIsBuiltin(displayID) == 0,
              CGDisplayVendorNumber(displayID) == TargetDisplaySpec.samsungQHD.vendorID,
              CGDisplayModelNumber(displayID) == TargetDisplaySpec.samsungQHD.productID,
              CGDisplayIsOnline(displayID) != 0,
              CGDisplayIsActive(displayID) != 0 else {
            targetDisplayOperationGate.invalidate()
            return .unavailable
        }
        return snapshot.readiness
    }
    var targetDisplayID: CGDirectDisplayID? {
        targetDisplayReadiness.displayID
    }
    var displayReadOperationsAllowed: Bool {
        DisplayOperationPolicy.readOperationsAllowed(
            isRunning: isRunning,
            powerState: displayPowerState
        )
    }
    var displayInteractiveOperationsAllowed: Bool {
        DisplayOperationPolicy.interactiveOperationsAllowed(
            isRunning: isRunning,
            powerState: displayPowerState,
            isPostWakeRefreshInProgress: isPostWakeRefreshInProgress
        )
    }
    var externalDisplayReadOperationsAllowed: Bool {
        DisplayOperationPolicy.externalReadOperationsAllowed(
            isRunning: isRunning,
            powerState: displayPowerState,
            targetReadiness: targetDisplayReadiness
        )
    }
    var externalDisplayInteractiveOperationsAllowed: Bool {
        DisplayOperationPolicy.externalInteractiveOperationsAllowed(
            isRunning: isRunning,
            powerState: displayPowerState,
            isPostWakeRefreshInProgress: isPostWakeRefreshInProgress,
            targetReadiness: targetDisplayReadiness
        )
    }

    // Compatibility alias for internal display/runtime callers. External
    // operations use one of the semantic gates above instead.
    var displayOperationsAllowed: Bool {
        displayReadOperationsAllowed
    }
    func acceptsDisplayPowerGeneration(_ generation: UInt64) -> Bool {
        !Task.isCancelled && isRunning && runtimeState.powerLifecycle.accepts(generation)
    }
    func acceptsTargetDisplayOperation(_ snapshot: TargetDisplayOperationSnapshot) -> Bool {
        guard let displayID = snapshot.displayID else { return false }
        return targetDisplayOperationGate.accepts(snapshot.generation, displayID: displayID)
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
    var manualBrightnessInteractionActive: Bool {
        get { runtimeState.brightness.manualBrightnessInteractionActive }
        set { runtimeState.brightness.manualBrightnessInteractionActive = newValue }
    }
    func invalidateManualBrightnessWrites() {
        runtimeState.brightness.manualBrightnessWriteGate.invalidate()
    }
    @discardableResult
    func startManualBrightnessWrite() -> UInt64 {
        runtimeState.brightness.manualBrightnessWriteGate.startRequest()
    }
    func acceptsManualBrightnessWrite(_ generation: UInt64) -> Bool {
        runtimeState.brightness.manualBrightnessWriteGate.accepts(generation)
    }
    var currentManualBrightnessWriteGeneration: UInt64 {
        runtimeState.brightness.manualBrightnessWriteGate.generation
    }
    var currentManualVolumeWriteGeneration: UInt64 {
        runtimeState.volume.manualVolumeWriteGate.generation
    }
    @discardableResult
    func startManualVolumeWrite() -> UInt64 {
        runtimeState.volume.manualVolumeWriteGate.startRequest()
    }
    func acceptsManualVolumeWrite(_ generation: UInt64) -> Bool {
        runtimeState.volume.manualVolumeWriteGate.accepts(generation)
    }
    func invalidateManualVolumeWrites() {
        runtimeState.volume.manualVolumeWriteGate.invalidate()
    }
    var mismatchIntervalsCount: Int {
        get { runtimeState.mismatchIntervalsCount }
        set { runtimeState.mismatchIntervalsCount = newValue }
    }
    var brightnessControlEpoch: UInt64 {
        get { runtimeState.brightnessControlEpoch }
        set { runtimeState.brightnessControlEpoch = newValue }
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
    var optimisticBrightnessTTL: TimeInterval { runtimeState.optimisticBrightnessTTL }
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
    var pendingVolumeIntent: Int? {
        get { runtimeState.volume.pendingVolumeIntent }
        set { runtimeState.volume.pendingVolumeIntent = newValue }
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
