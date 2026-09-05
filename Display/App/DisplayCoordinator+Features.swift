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

    func acceptsBrightnessControlEpoch(_ epoch: UInt64) -> Bool {
        !Task.isCancelled && brightnessControlEpoch == epoch
    }

    /// Starts a fresh brightness-control epoch after a display-parameter or
    /// target transition. Values from the previous mode can remain only as a
    /// presentation fallback. An accepted command may remain as logical user
    /// intent, but its readback confidence and hardware truth are reset.
    func beginBrightnessControlEpoch(reason: String) {
        brightnessControlEpoch &+= 1
        brightnessAutoWriteOutcomePlanner.resetLimiterEvidence()
        manualBrightnessWriteTask?.cancel()
        manualBrightnessWriteTask = nil
        invalidateManualBrightnessWrites()
        let previousCommandedBrightness = brightnessState.commandedBrightnessPercent
        let presentationFallback = previousCommandedBrightness
            ?? brightnessState.persistedBrightnessPercent
            ?? brightnessState.lastConfirmedBrightnessPercent
        let previousEpochReadback = brightnessState.lastDDCReadbackPercent
            ?? brightnessState.lastConfirmedBrightnessPercent
            ?? brightnessState.actualDDCBrightnessPercent
            ?? brightnessState.persistedBrightnessPercent
        let displayKey = currentDisplayInfo?.displayKey
        // A mode transition can temporarily expose a new DDC identity for the
        // same panel, so invalidate every cached brightness sample. The next
        // read must be classified from its transport source, never inferred
        // from an old display-key entry.
        brightnessCoordinator.invalidateDDCBrightnessCache(for: nil)

        updateBrightnessState { state in
            state.pendingManualBrightnessPercent = nil
            // Keep an accepted command as logical intent across a mode epoch;
            // the transition-unverified reliability below prevents it from
            // being mistaken for a fresh hardware observation.
            state.commandedBrightnessPercent = previousCommandedBrightness
            state.optimisticBrightnessPercent = nil
            state.optimisticBrightnessExpiresAt = nil
            state.optimisticReadbackAttempts = 0
            state.persistedBrightnessPercent = presentationFallback
            state.lastConfirmedBrightnessPercent = nil
            state.actualDDCBrightnessPercent = nil
            state.requestedDDCBrightnessPercent = nil
            state.lastDDCReadbackPercent = nil
            state.lastDDCActualPercentAfter = nil
            state.lastReadbackSource = nil
            state.transitionReadbackSampleCount = 0
            state.transitionReadbackStableCount = 0
            state.transitionReadbackCandidatePercent = nil
            state.transitionPreviousReadbackPercent = previousEpochReadback
            state.readbackReliability = .transitionUnverified
            state.lastDDCRawCurrentBefore = nil
            state.lastDDCRawMax = nil
            state.lastDDCRawTarget = nil
            state.lastDDCRawAfter = nil
            state.lastDDCWriteSucceeded = nil
            state.lastDDCWriteMessage = nil
            state.lastDDCWriteStatus = nil
            state.lastDDCMatchedTarget = nil
            state.lastWriteAttemptPercent = nil
            state.lastWriteReadbackPercent = nil
            state.lastAutoWriteAttempted = false
            state.lastAutoWriteValue = nil
            state.lastAutoWriteSucceeded = nil
            state.lastAutoWriteMessage = nil
            state.lastAutoWriteActualBefore = nil
            state.lastAutoWriteActualAfter = nil
            state.smoothedRequestedBrightnessPercent = nil
            state.showMismatchWarning = false
            state.mismatchStreak = 0
            state.limiterDetected = false
            state.isDDCReadbackAvailable = false
            state.isManualOverrideActive = false
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil
            state.lastBrightnessSource = .ambientComputed
            state.isBrightnessWriteSuppressed = false
            state.lastSuppressionReason = nil
            state.suppressionReason = nil
        }

        manualBrightnessInteractionActive = false
        brightnessLimiterCooldownDisplayKey = nil
        brightnessLimiterCooldownUntil = .distantPast
        mismatchIntervalsCount = 0
        pendingTargetCandidate = nil
        manualBrightnessOverrideStartLux = nil
        manualBrightnessOverrideUntil = .distantPast
        lastBrightnessReadDate = .distantPast
        lastSentBrightness = nil
        currentBrightness = nil
        traceRuntime(
            "brightness epoch reset reason=\(reason) displayKey=\(displayKey ?? "nil") " +
                "presentationFallback=\(presentationFallback.map(String.init) ?? "nil") " +
                "ddcCacheReset=true " +
                "readbackReliability=\(BrightnessReadbackReliability.transitionUnverified.rawValue)"
        )
    }

    func expireOptimisticBrightnessIfNeeded(now: Date = Date()) {
        let optimisticExpired = brightnessState.optimisticBrightnessExpiresAt.map {
            now >= $0
        } ?? false
        let cooldownExpired = brightnessLimiterCooldownDisplayKey != nil
            && now >= brightnessLimiterCooldownUntil
        guard optimisticExpired || cooldownExpired else { return }

        brightnessAutoWriteOutcomePlanner.resetLimiterEvidence()
        updateBrightnessState { state in
            if optimisticExpired {
                state.optimisticBrightnessPercent = nil
                state.optimisticBrightnessExpiresAt = nil
                state.optimisticReadbackAttempts = 0
            }
            state.mismatchStreak = 0
            state.limiterDetected = false
        }
        if cooldownExpired {
            brightnessLimiterCooldownDisplayKey = nil
            brightnessLimiterCooldownUntil = .distantPast
        }
        currentBrightness = brightnessState.uiSliderBrightnessPercent
        traceRuntime(
            "brightness confidence reset epoch=\(brightnessControlEpoch) " +
                "optimisticExpired=\(optimisticExpired) cooldownExpired=\(cooldownExpired) " +
                "commanded=\(brightnessState.commandedBrightnessPercent.map(String.init) ?? "nil")"
        )
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

    func applyBrightnessReadback(_ sample: BrightnessReadSample?, requestedFallback: Int? = nil) {
        // A refresh/readback can overlap a manual DDC write. Keep the latest
        // user draft authoritative until that write completes or fails.
        guard brightnessState.pendingManualBrightnessPercent == nil else { return }
        expireOptimisticBrightnessIfNeeded()
        let now = Date()
        let readbackTolerance = 3
        let requiredTransitionSamples = 2
        let limiterCooldownIsActive = brightnessLimiterCooldownDisplayKey != nil
            && now < brightnessLimiterCooldownUntil
        var didConfirmReadback = false

        updateBrightnessState { state in
            if let requestedFallback, state.commandedBrightnessPercent == nil {
                // A persisted/discovery fallback must not overwrite an
                // accepted command while its hardware readback is uncertain.
                state.persistedBrightnessPercent = requestedFallback
            }
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil && !state.isManualOverrideActive
            state.isBrightnessWriteSuppressed = false
            state.lastSuppressionReason = nil
            state.suppressionReason = nil

            guard let sample else {
                state.lastReadbackSource = nil
                state.isDDCReadbackAvailable = false
                if state.commandedBrightnessPercent != nil {
                    state.optimisticReadbackAttempts += 1
                    if state.readbackReliability != .reliable {
                        state.readbackReliability = .unavailable
                    }
                } else if state.readbackReliability != .transitionUnverified,
                          state.lastConfirmedBrightnessPercent == nil {
                    state.readbackReliability = .unavailable
                }
                return
            }

            state.lastReadbackSource = sample.source
            guard sample.source == .hardwareFresh else {
                // Cache fallback is useful for presentation/diagnostics only.
                // It is never a fresh observation and cannot promote state to
                // reliable or replace a commanded value.
                state.isDDCReadbackAvailable = false
                if state.commandedBrightnessPercent != nil,
                   state.readbackReliability != .reliable {
                    state.optimisticReadbackAttempts += 1
                    state.readbackReliability = .uncertainAfterWrite
                } else if state.readbackReliability != .transitionUnverified {
                    state.readbackReliability = .unavailable
                }
                return
            }

            let readback = sample.percent
            state.lastDDCReadbackPercent = readback
            state.lastDDCActualPercentAfter = readback
            state.isDDCReadbackAvailable = true

            if let commanded = state.commandedBrightnessPercent {
                if abs(readback - commanded) <= readbackTolerance {
                    state.actualDDCBrightnessPercent = readback
                    state.lastConfirmedBrightnessPercent = readback
                    state.persistedBrightnessPercent = readback
                    // The accepted command has now graduated to confirmed
                    // hardware truth. Clearing the pending command also
                    // allows a later explicit fresh observation to correct
                    // the confirmed value if the panel is changed outside
                    // MemWatch.
                    state.commandedBrightnessPercent = nil
                    state.optimisticBrightnessPercent = nil
                    state.optimisticBrightnessExpiresAt = nil
                    state.optimisticReadbackAttempts = 0
                    state.readbackReliability = .reliable
                    state.transitionReadbackCandidatePercent = nil
                    state.transitionReadbackStableCount = 0
                    state.transitionPreviousReadbackPercent = nil
                    state.lastBrightnessSource = .ddcReadback
                    didConfirmReadback = true
                } else {
                    // A fresh DDC response that misses the accepted command is
                    // still only diagnostic evidence; changing from the prior
                    // response does not make it authoritative.
                    state.optimisticReadbackAttempts += 1
                    state.readbackReliability = .uncertainAfterWrite
                }
            } else if state.readbackReliability == .transitionUnverified {
                state.transitionReadbackSampleCount += 1
                if let candidate = state.transitionReadbackCandidatePercent,
                   abs(readback - candidate) <= readbackTolerance {
                    state.transitionReadbackStableCount += 1
                } else {
                    state.transitionReadbackCandidatePercent = readback
                    state.transitionReadbackStableCount = 1
                }

                let differsFromPreviousEpoch = state.transitionPreviousReadbackPercent.map {
                    abs(readback - $0) > readbackTolerance
                } ?? true
                if state.transitionReadbackStableCount >= requiredTransitionSamples,
                   differsFromPreviousEpoch {
                    state.actualDDCBrightnessPercent = readback
                    state.lastConfirmedBrightnessPercent = readback
                    state.persistedBrightnessPercent = readback
                    state.readbackReliability = .reliable
                    state.lastBrightnessSource = .ddcReadback
                    state.transitionReadbackCandidatePercent = nil
                    state.transitionReadbackStableCount = 0
                    state.transitionPreviousReadbackPercent = nil
                    didConfirmReadback = true
                }
            } else {
                // Outside a transition and without an accepted command, a
                // fresh hardware sample is explicit observation evidence.
                state.actualDDCBrightnessPercent = readback
                state.lastConfirmedBrightnessPercent = readback
                state.persistedBrightnessPercent = readback
                state.optimisticBrightnessPercent = nil
                state.optimisticBrightnessExpiresAt = nil
                state.optimisticReadbackAttempts = 0
                state.readbackReliability = .reliable
                state.lastBrightnessSource = .ddcReadback
                didConfirmReadback = true
            }
        }

        if didConfirmReadback {
            brightnessAutoWriteOutcomePlanner.resetLimiterEvidence()
            updateBrightnessState { state in
                state.mismatchStreak = 0
                state.limiterDetected = false
            }
            if !limiterCooldownIsActive {
                brightnessLimiterCooldownDisplayKey = nil
                brightnessLimiterCooldownUntil = .distantPast
            }
        }
        currentBrightness = brightnessState.uiSliderBrightnessPercent
    }

    func applyBrightnessWriteResult(
        requested: Int,
        source: BrightnessSource,
        result: M1DDCBrightnessWriteResult
    ) {
        let now = Date()
        let observedBrightness = result.actualUIPercentAfter ?? result.readbackBrightnessPercent
        let previousCommandedBrightness = brightnessState.commandedBrightnessPercent
        let previousOptimisticBrightness = brightnessState.optimisticBrightnessPercent
        let previousOptimisticExpiry = brightnessState.optimisticBrightnessExpiresAt
        let previousOptimisticAttempts = brightnessState.optimisticReadbackAttempts
        let previousPersistedBrightness = brightnessState.persistedBrightnessPercent
        let previousActualBrightness = brightnessState.actualDDCBrightnessPercent
        let previousConfirmedBrightness = brightnessState.lastConfirmedBrightnessPercent
        let previousReadbackReliability = brightnessState.readbackReliability
        let previousTransitionSampleCount = brightnessState.transitionReadbackSampleCount
        let previousTransitionStableCount = brightnessState.transitionReadbackStableCount
        let previousTransitionCandidate = brightnessState.transitionReadbackCandidatePercent
        let previousTransitionReadback = brightnessState.transitionPreviousReadbackPercent
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
            if observedBrightness != nil {
                state.lastReadbackSource = .hardwareFresh
            } else {
                state.lastReadbackSource = nil
            }
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil && !state.isManualOverrideActive
            if source == .autoDDCWrite {
                state.lastAutoWriteAttempted = true
                state.lastAutoWriteValue = requested
                state.lastAutoWriteSucceeded = result.writeAccepted
                state.lastAutoWriteMessage = result.message
                state.lastAutoWriteActualAfter = observedBrightness
            }

            if result.writeAccepted {
                // An accepted command is the canonical logical value even
                // when the monitor returns a stale or otherwise mismatched
                // GET response. The expiry below only controls optimistic
                // confidence; it must never erase this intent.
                state.commandedBrightnessPercent = requested
                state.persistedBrightnessPercent = requested
                state.transitionReadbackSampleCount = 0
                state.transitionReadbackStableCount = 0
                state.transitionReadbackCandidatePercent = nil
                state.transitionPreviousReadbackPercent = nil

                if result.matchedTarget == true, let observedBrightness {
                    state.actualDDCBrightnessPercent = observedBrightness
                    state.lastConfirmedBrightnessPercent = observedBrightness
                    state.commandedBrightnessPercent = nil
                    state.optimisticBrightnessPercent = nil
                    state.optimisticBrightnessExpiresAt = nil
                    state.optimisticReadbackAttempts = 0
                    state.readbackReliability = .reliable
                } else {
                    state.optimisticBrightnessPercent = requested
                    state.optimisticBrightnessExpiresAt = now.addingTimeInterval(optimisticBrightnessTTL)
                    state.optimisticReadbackAttempts = 0
                    state.readbackReliability = result.readbackAvailable
                        ? .uncertainAfterWrite
                        : .unavailable
                }
            } else {
                // A failed command must roll back the logical command and
                // confidence snapshot, not manufacture a new requested value
                // from the failed attempt.
                state.commandedBrightnessPercent = previousCommandedBrightness
                state.optimisticBrightnessPercent = previousOptimisticBrightness
                state.optimisticBrightnessExpiresAt = previousOptimisticExpiry
                state.optimisticReadbackAttempts = previousOptimisticAttempts
                state.persistedBrightnessPercent = previousPersistedBrightness
                state.actualDDCBrightnessPercent = previousActualBrightness
                state.lastConfirmedBrightnessPercent = previousConfirmedBrightness
                state.readbackReliability = previousReadbackReliability
                state.transitionReadbackSampleCount = previousTransitionSampleCount
                state.transitionReadbackStableCount = previousTransitionStableCount
                state.transitionReadbackCandidatePercent = previousTransitionCandidate
                state.transitionPreviousReadbackPercent = previousTransitionReadback
            }
            state.isBrightnessWriteSuppressed = false
            state.lastSuppressionReason = nil
            state.suppressionReason = nil
        }
        currentBrightness = brightnessState.uiSliderBrightnessPercent
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
            displayKey=\(currentDisplayKey ?? "nil")
            source=\(source.rawValue)
            requestedUIPercent=\(requested)
            commandedBrightnessPercent=\(state.commandedBrightnessPercent.map(String.init) ?? "nil")
            uiBrightnessPercent=\(state.uiSliderBrightnessPercent)
            lastConfirmedBrightnessPercent=\(state.lastConfirmedBrightnessPercent.map(String.init) ?? "nil")
            actualDDCBrightnessPercent=\(state.actualDDCBrightnessPercent.map(String.init) ?? "nil")
            readbackPercent=\(state.lastDDCReadbackPercent.map(String.init) ?? "nil")
            readbackSource=\(state.lastReadbackSource?.rawValue ?? "none")
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
        if let commanded = brightnessState.commandedBrightnessPercent {
            return "\(commanded)%"
        }
        if brightnessState.readbackReliability == .reliable {
            if let actual = brightnessState.actualDDCBrightnessPercent {
                return "\(actual)%"
            }
            if let confirmed = brightnessState.lastConfirmedBrightnessPercent {
                return "\(confirmed)%"
            }
        }

        if let persisted = brightnessState.persistedBrightnessPercent {
            return "\(persisted)%"
        }

        if let target = brightnessState.autoTargetBrightnessPercent {
            return "\(target)% (target)"
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
