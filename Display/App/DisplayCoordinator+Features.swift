import AppKit
import Foundation

extension DisplayCoordinator {
    func persistHiDPIState(enabled: Bool) {
        HiDPIStateStore.setHiDPIEnabled(enabled)
        HiDPIStateStore.setStateText(enabled ? "HiDPI enabled" : "HiDPI disabled")
        hiDPIActivationStatusText = enabled ? "HiDPI enabled" : "HiDPI disabled"
    }

    func reloadDisplayModes(allowDuringPostWake: Bool = false) async {
        let operationsAllowed = allowDuringPostWake
            ? externalDisplayReadOperationsAllowed
            : externalDisplayInteractiveOperationsAllowed
        guard operationsAllowed else { return }
        let powerGeneration = displayPowerGeneration
        let targetSnapshot = targetDisplayOperationGate.snapshot()
        guard let targetDisplayID = targetSnapshot.displayID else { return }
        let snapshot = await hiDPICoordinator.refreshService.reloadDisplayModes(currentActivationStatusText: hiDPIActivationStatusText)
        guard acceptsDisplayPowerGeneration(powerGeneration),
              targetDisplayOperationGate.accepts(
                  targetSnapshot.generation,
                  displayID: targetDisplayID
              ) else { return }
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
        guard externalDisplayReadOperationsAllowed else { return }
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

    /// Starts a fresh brightness-control epoch after a display-parameter or
    /// target transition. A last confirmed value is safe as a temporary
    /// fallback, but write confidence, optimistic values, and limiter
    /// evidence belong to the previous display mode and must not cross it.
    func beginBrightnessControlEpoch(reason: String) {
        brightnessControlEpoch &+= 1
        brightnessAutoWriteOutcomePlanner.resetLimiterEvidence()
        let fallback = brightnessState.lastConfirmedBrightnessPercent

        updateBrightnessState { state in
            state.pendingManualBrightnessPercent = nil
            state.optimisticBrightnessPercent = nil
            state.optimisticBrightnessExpiresAt = nil
            state.optimisticReadbackAttempts = 0
            state.readbackReliability = .unavailable
            state.actualDDCBrightnessPercent = fallback
            state.requestedDDCBrightnessPercent = fallback
            state.lastDDCReadbackPercent = nil
            state.lastDDCActualPercentAfter = nil
            state.lastDDCRawCurrentBefore = nil
            state.lastDDCRawMax = nil
            state.lastDDCRawTarget = nil
            state.lastDDCRawAfter = nil
            state.lastDDCWriteSucceeded = nil
            state.lastDDCWriteMessage = nil
            state.lastDDCWriteStatus = nil
            state.lastDDCMatchedTarget = nil
            state.lastWriteReadbackPercent = nil
            state.mismatchStreak = 0
            state.limiterDetected = false
            state.isDDCReadbackAvailable = false
            state.isManualOverrideActive = false
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil
        }

        brightnessLimiterCooldownDisplayKey = nil
        brightnessLimiterCooldownUntil = .distantPast
        mismatchIntervalsCount = 0
        pendingTargetCandidate = nil
        manualBrightnessOverrideStartLux = nil
        manualBrightnessOverrideUntil = .distantPast
        lastBrightnessReadDate = .distantPast
        lastSentBrightness = fallback
        currentBrightness = nil
        traceRuntime(
            "brightness control epoch=\(brightnessControlEpoch) reset reason=\(reason) fallback=\(fallback.map(String.init) ?? "nil")"
        )
    }

    func expireOptimisticBrightnessIfNeeded(now: Date = Date()) {
        guard let expiresAt = brightnessState.optimisticBrightnessExpiresAt,
              now >= expiresAt else { return }

        brightnessAutoWriteOutcomePlanner.resetLimiterEvidence()
        updateBrightnessState { state in
            state.optimisticBrightnessPercent = nil
            state.optimisticBrightnessExpiresAt = nil
            state.optimisticReadbackAttempts = 0
            state.readbackReliability = .unavailable
            state.actualDDCBrightnessPercent = state.lastConfirmedBrightnessPercent
            state.isDDCReadbackAvailable = false
            state.mismatchStreak = 0
            state.limiterDetected = false
        }
        brightnessLimiterCooldownDisplayKey = nil
        brightnessLimiterCooldownUntil = .distantPast
        currentBrightness = brightnessState.referenceBrightness(now: now) ?? currentBrightness
        traceRuntime("brightness optimistic state expired epoch=\(brightnessControlEpoch)")
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
            if let actual, state.readbackReliability == .reliable {
                state.actualDDCBrightnessPercent = actual
            }
        }
    }

    func applyBrightnessReadback(_ readback: Int?, requestedFallback: Int? = nil) {
        // A refresh/readback can overlap a manual DDC write. Keep the latest
        // user draft authoritative until that write completes or fails.
        guard brightnessState.pendingManualBrightnessPercent == nil else { return }
        expireOptimisticBrightnessIfNeeded()
        let now = Date()
        var didConfirmReadback = false

        updateBrightnessState { state in
            if let requestedFallback {
                state.requestedDDCBrightnessPercent = requestedFallback
            }

            let previousReadback = state.lastDDCReadbackPercent
            let optimistic = state.activeOptimisticBrightnessPercent(now: now)
            if let readback {
                state.lastDDCReadbackPercent = readback
                state.lastDDCActualPercentAfter = readback
                let matchesOptimistic = optimistic.map {
                    abs(readback - $0) <= 3
                } ?? false
                let changedAfterWrite = optimistic != nil && previousReadback.map {
                    abs(readback - $0) > 3
                } == true
                let isReliable = optimistic == nil || matchesOptimistic || changedAfterWrite

                if isReliable {
                    state.actualDDCBrightnessPercent = readback
                    state.lastConfirmedBrightnessPercent = readback
                    state.optimisticBrightnessPercent = nil
                    state.optimisticBrightnessExpiresAt = nil
                    state.optimisticReadbackAttempts = 0
                    state.readbackReliability = .reliable
                    state.lastBrightnessSource = .ddcReadback
                    didConfirmReadback = true
                } else {
                    // A stale value after an accepted write is diagnostic data,
                    // not a new authoritative brightness value.
                    state.optimisticReadbackAttempts += 1
                    state.readbackReliability = .uncertainAfterWrite
                }
                state.isDDCReadbackAvailable = true
            } else {
                state.isDDCReadbackAvailable = false
                if optimistic != nil {
                    state.optimisticReadbackAttempts += 1
                    state.readbackReliability = .unavailable
                } else if state.lastConfirmedBrightnessPercent == nil {
                    state.readbackReliability = .unavailable
                }
            }
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil && !state.isManualOverrideActive
            state.isBrightnessWriteSuppressed = false
            state.lastSuppressionReason = nil
            state.suppressionReason = nil
        }

        if didConfirmReadback {
            brightnessAutoWriteOutcomePlanner.resetLimiterEvidence()
            updateBrightnessState { state in
                state.mismatchStreak = 0
                state.limiterDetected = false
            }
            brightnessLimiterCooldownDisplayKey = nil
            brightnessLimiterCooldownUntil = .distantPast
        }
        currentBrightness = brightnessState.referenceBrightness(now: now)
            ?? requestedFallback
            ?? currentBrightness
    }

    func applyBrightnessWriteResult(
        requested: Int,
        source: BrightnessSource,
        result: M1DDCBrightnessWriteResult
    ) {
        let now = Date()
        let observedBrightness = result.actualUIPercentAfter ?? result.readbackBrightnessPercent
        updateBrightnessState { state in
            state.requestedDDCBrightnessPercent = requested
            if let observedBrightness {
                state.lastDDCReadbackPercent = observedBrightness
                state.lastDDCActualPercentAfter = observedBrightness
            }
            state.lastDDCRawCurrentBefore = result.rawBefore
            state.lastDDCRawMax = result.rawMax
            state.lastDDCRawTarget = result.computedRawTarget
            state.lastDDCRawAfter = result.rawAfter
            state.isDDCReadbackAvailable = result.readbackAvailable
            state.lastBrightnessSource = result.writeAccepted ? source : .writeFailed
            state.lastDDCWriteSucceeded = result.writeAccepted
            state.lastDDCWriteMessage = result.message
            state.lastDDCWriteStatus = result.status
            state.lastDDCMatchedTarget = result.matchedTarget
            state.lastWriteReadbackPercent = observedBrightness
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil && !state.isManualOverrideActive
            if source == .autoDDCWrite {
                state.lastAutoWriteAttempted = true
                state.lastAutoWriteValue = requested
                state.lastAutoWriteSucceeded = result.writeAccepted
                state.lastAutoWriteMessage = result.message
                state.lastAutoWriteActualAfter = observedBrightness ?? state.lastAutoWriteActualAfter
            }

            switch result.status {
            case .success:
                if let observedBrightness {
                    state.actualDDCBrightnessPercent = observedBrightness
                    state.lastConfirmedBrightnessPercent = observedBrightness
                    state.optimisticBrightnessPercent = nil
                    state.optimisticBrightnessExpiresAt = nil
                    state.optimisticReadbackAttempts = 0
                    state.readbackReliability = .reliable
                } else if result.writeAccepted {
                    state.optimisticBrightnessPercent = requested
                    state.optimisticBrightnessExpiresAt = now.addingTimeInterval(optimisticBrightnessTTL)
                    state.optimisticReadbackAttempts = 0
                    state.readbackReliability = .unavailable
                }
            case .writeAcceptedReadbackUncertain, .writeAcceptedButReadbackLimited:
                state.optimisticBrightnessPercent = requested
                state.optimisticBrightnessExpiresAt = now.addingTimeInterval(optimisticBrightnessTTL)
                state.optimisticReadbackAttempts = 0
                state.readbackReliability = .uncertainAfterWrite
                // Keep actualDDCBrightnessPercent and lastConfirmedBrightnessPercent
                // unchanged; the observed value may be stale.
            case .readbackUnavailable:
                if result.writeAccepted {
                    state.optimisticBrightnessPercent = requested
                    state.optimisticBrightnessExpiresAt = now.addingTimeInterval(optimisticBrightnessTTL)
                    state.optimisticReadbackAttempts = 0
                    state.readbackReliability = .unavailable
                } else {
                    state.optimisticBrightnessPercent = nil
                    state.optimisticBrightnessExpiresAt = nil
                    state.optimisticReadbackAttempts = 0
                    state.readbackReliability = .unavailable
                }
            case .writeFailed:
                state.optimisticBrightnessPercent = nil
                state.optimisticBrightnessExpiresAt = nil
                state.optimisticReadbackAttempts = 0
                state.readbackReliability = .unavailable
                state.actualDDCBrightnessPercent = state.lastConfirmedBrightnessPercent
            }
            state.isBrightnessWriteSuppressed = false
            state.lastSuppressionReason = nil
            state.suppressionReason = nil
        }
        currentBrightness = brightnessState.referenceBrightness(now: now) ?? currentBrightness
    }

    func logBrightnessWrite(
        requested: Int,
        source: BrightnessSource,
        result: M1DDCBrightnessWriteResult
    ) {
        let state = brightnessState
        let matchedTarget = result.matchedTarget.map { $0 ? "YES" : "NO" } ?? "UNKNOWN"
        print(
            """
            [MemWatch Brightness Write]
            brightnessControlEpoch=\(brightnessControlEpoch)
            source=\(source.rawValue)
            requestedUIPercent=\(requested)
            optimisticBrightness=\(state.activeOptimisticBrightnessPercent()?.description ?? "none")
            rawMax=\(result.rawMax.map(String.init) ?? "unavailable")
            computedRawTarget=\(result.computedRawTarget.map(String.init) ?? "unavailable")
            rawBefore=\(result.rawBefore.map(String.init) ?? "unavailable")
            rawAfter=\(result.rawAfter.map(String.init) ?? "unavailable")
            actualUIPercentAfter=\((result.actualUIPercentAfter ?? result.readbackBrightnessPercent).map(String.init) ?? "unavailable")
            matchedTarget=\(matchedTarget)
            readbackReliability=\(state.readbackReliability.rawValue)
            mismatchStreak=\(state.mismatchStreak)
            limiterDetected=\(state.limiterDetected ? "YES" : "NO")
            status=\(result.status.rawValue)
            writeAccepted=\(result.writeAccepted ? "YES" : "NO")
            """
        )
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
        if let optimistic = brightnessState.activeOptimisticBrightnessPercent() {
            return "\(optimistic)%"
        }
        if brightnessState.readbackReliability == .reliable {
            if let actual = brightnessState.actualDDCBrightnessPercent {
                return "\(actual)%"
            }
            if let readback = brightnessState.lastDDCReadbackPercent {
                return "\(readback)%"
            }
        }

        if let confirmed = brightnessState.lastConfirmedBrightnessPercent {
            return "\(confirmed)%"
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
