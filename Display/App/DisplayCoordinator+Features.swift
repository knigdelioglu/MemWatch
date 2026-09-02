import AppKit
import Foundation

extension DisplayCoordinator {
    func persistHiDPIState(enabled: Bool) {
        HiDPIStateStore.setHiDPIEnabled(enabled)
        HiDPIStateStore.setStateText(enabled ? "HiDPI enabled" : "HiDPI disabled")
        hiDPIActivationStatusText = enabled ? "HiDPI enabled" : "HiDPI disabled"
    }

    func reloadDisplayModes() async {
        let snapshot = hiDPICoordinator.refreshService.reloadDisplayModes(currentActivationStatusText: hiDPIActivationStatusText)
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

    func refreshCGSModeSwitcherState() {
        let summary = hiDPICoordinator.refreshService.refreshCGSModeSwitcherState()
        cgsManualModeSwitcherSummary = summary
        cgsManualModeSwitcherStatusText = summary?.currentModeText ?? "Current CGS Mode: unavailable"
    }

    var activeDisplayKey: String {
        currentDisplayInfo?.displayKey ?? store.preferences.selectedDisplayKey ?? "default"
    }

    var currentDisplayKey: String? {
        currentDisplayInfo?.displayKey
    }

    func updateBrightnessState(_ mutate: (inout BrightnessState) -> Void) {
        var next = brightnessState
        mutate(&next)
        brightnessState = next
    }

    func recordAutoSuppression(
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

    func applyBrightnessReadback(_ readback: Int?, requestedFallback: Int? = nil) {
        // A refresh/readback can overlap a manual DDC write. Keep the latest
        // user draft authoritative until that write completes or fails.
        guard brightnessState.pendingManualBrightnessPercent == nil else { return }
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

    func applyBrightnessWriteResult(
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

    func brightnessMappingDiagnosticSummarySnapshot() -> BrightnessMappingDiagnosticSummary {
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
        pendingVolumeIntent ?? currentVolume ?? volumeCoordinator.lastNonZeroVolume
    }

    var monitorBrightnessControlValue: Int {
        brightnessState.uiSliderBrightnessPercent
    }

    var brightnessSensorTargetText: String {
        brightnessState.autoTargetBrightnessPercent.map { "\($0)%" } ?? "—"
    }

    var brightnessActualText: String {
        if let pending = brightnessState.pendingManualBrightnessPercent {
            return String(pending) + "%"
        }
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
}
