import Foundation

extension DisplayCoordinator {
    func tick(allowDuringPostWake: Bool = false) async {
        guard displayReadOperationsAllowed,
              allowDuringPostWake || !isPostWakeRefreshInProgress else { return }
        guard !isTickRunning else { return }
        isTickRunning = true
        defer { isTickRunning = false }

        let tickPowerGeneration = displayPowerGeneration
        guard acceptsDisplayPowerGeneration(tickPowerGeneration) else { return }

        // Treat the current manual-write generation as the tick's epoch. Any
        // manual interaction that starts while this tick is suspended makes
        // the rest of this auto pass stale, even if the drag ends before the
        // next await resumes.
        let tickBrightnessWriteGeneration = currentManualBrightnessWriteGeneration
        guard !manualBrightnessInteractionActive else { return }

        traceRuntime("tick entered currentDisplay=\(currentDisplayInfo?.displayKey ?? "nil")")

        let isAvailable = await brightnessCoordinator.isDDCAvailable()
        guard acceptsDisplayPowerGeneration(tickPowerGeneration) else { return }
        ddcAvailable = isAvailable
        updateCapabilities()
        refreshSharedRuntimeFeatures()

        guard externalDisplayReadOperationsAllowed else {
            beginTargetDisplayReadinessRecoveryIfNeeded(for: tickPowerGeneration)
            return
        }
        let tickTargetSnapshot = targetDisplayOperationGate.snapshot()
        guard tickTargetSnapshot.isReady else { return }

        if applySoftwareDisconnectedDisplayStateIfNeeded() {
            return
        }

        // Display discovery is independent from the ambient-light sensor. A
        // monitor can be connected while ALS symbols are unavailable or while
        // the sensor is still warming up; in that case we must still publish
        // the external display and its capabilities.
        if currentDisplayInfo == nil, Date().timeIntervalSince(lastDisplaySearchDate) >= displaySearchInterval {
            lastDisplaySearchDate = Date()
            await reloadDisplayInfo(allowDuringPostWake: allowDuringPostWake)
            guard acceptsDisplayPowerGeneration(tickPowerGeneration),
                  acceptsTargetDisplayOperation(tickTargetSnapshot) else { return }
            refreshSharedRuntimeFeatures()
        }

        if manualBrightnessInteractionActive {
            updateBrightnessState { state in
                state.isManualOverrideActive = true
                state.isAutoBrightnessEnabled = false
                state.suppressionReason = "Manual brightness interaction active"
            }
            return
        }

        guard let reader = brightnessCoordinator.reader else {
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

        guard acceptsManualBrightnessWrite(tickBrightnessWriteGeneration), !manualBrightnessInteractionActive else {
            return
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
        expireOptimisticBrightnessIfNeeded(now: now)

        // `brightnessReadInterval` is also the recovery path for monitors
        // whose immediate post-write readback is stale. Do not let the
        // cached value prevent a later read from becoming authoritative.
        let shouldRefreshBrightness = brightnessState.pendingManualBrightnessPercent == nil
            && (currentBrightness == nil
                || now.timeIntervalSince(lastBrightnessReadDate) >= brightnessReadInterval)
        if shouldRefreshBrightness {
            let readback = await brightnessCoordinator.writer.readBrightness(preferredKey: display.displayKey)
            guard acceptsDisplayPowerGeneration(tickPowerGeneration),
                  acceptsTargetDisplayOperation(tickTargetSnapshot),
                  acceptsManualBrightnessWrite(tickBrightnessWriteGeneration),
                  !manualBrightnessInteractionActive,
                  brightnessState.pendingManualBrightnessPercent == nil else {
                return
            }
            applyBrightnessReadback(readback, requestedFallback: store.lastBrightness(for: display.displayKey))
            lastBrightnessReadDate = now
        }

        let ambientNormalizedValue = BrightnessCurve.ambientNormalizedValue(for: smoothedLux, calibration: settings.calibration)
        let autoTargetBrightnessPercent = BrightnessCurve.targetBrightness(
            for: smoothedLux,
            calibration: settings.calibration,
            profile: profile
        )
        let actualBefore = brightnessState.referenceBrightness(now: now)
            ?? currentBrightness
            ?? store.lastBrightness(for: display.displayKey)
            ?? 50
        let requestReferenceBrightness = actualBefore
        let isManualOverrideActive = shouldHoldManualBrightnessOverride(currentLux: smoothedLux, now: now)

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

        await refreshCurrentVolume()
        guard acceptsDisplayPowerGeneration(tickPowerGeneration),
              acceptsTargetDisplayOperation(tickTargetSnapshot) else { return }
        refreshSharedRuntimeFeatures()

        let target = autoTargetBrightnessPercent
        updateStatus(String(format: "%.0f lux -> %%%d", smoothedLux, target))

        let currentActual = brightnessState.referenceBrightness(now: now) ?? actualBefore
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
        let preflightDDCAvailable = await brightnessCoordinator.isDDCAvailable()
        guard acceptsDisplayPowerGeneration(tickPowerGeneration),
              acceptsTargetDisplayOperation(tickTargetSnapshot) else { return }

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
                ddcAvailable: preflightDDCAvailable,
                brightnessLimiterCooldownDisplayKey: brightnessLimiterCooldownDisplayKey,
                brightnessLimiterCooldownUntil: brightnessLimiterCooldownUntil
            )
        )

        guard acceptsDisplayPowerGeneration(tickPowerGeneration),
              acceptsTargetDisplayOperation(tickTargetSnapshot),
              acceptsManualBrightnessWrite(tickBrightnessWriteGeneration),
              !manualBrightnessInteractionActive else {
            return
        }

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

        guard acceptsDisplayPowerGeneration(tickPowerGeneration),
              acceptsTargetDisplayOperation(tickTargetSnapshot),
              acceptsManualBrightnessWrite(tickBrightnessWriteGeneration),
              !manualBrightnessInteractionActive else {
            return
        }
        let result = await brightnessCoordinator.writer.setBrightness(writeCandidate, preferredKey: display.displayKey)
        guard acceptsDisplayPowerGeneration(tickPowerGeneration),
              acceptsTargetDisplayOperation(tickTargetSnapshot),
              acceptsManualBrightnessWrite(tickBrightnessWriteGeneration),
              !manualBrightnessInteractionActive else {
            return
        }

        if result.writeAccepted {
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

    func handleAutoBrightnessWriteSuccess(
        result: M1DDCBrightnessWriteResult,
        candidate: Int,
        currentActual: Int,
        displayKey: String
    ) {
        let outcome = brightnessAutoWriteOutcomePlanner.plan(
            result: result,
            candidate: candidate,
            displayKey: displayKey
        )
        lastWriteDate = Date()

        if let readback = outcome.persistedReadback {
            lastBrightnessReadDate = lastWriteDate
            store.setLastBrightness(readback, for: displayKey)
        }

        applyBrightnessWriteResult(requested: candidate, source: .autoDDCWrite, result: result)

        updateBrightnessState { state in
            state.lastWriteAttemptPercent = candidate
            state.lastWriteReadbackPercent = outcome.actualAfter
            state.mismatchStreak = outcome.mismatchStreak
            state.limiterDetected = outcome.limiterDetected
            state.isAutoBrightnessEnabled = autoBrightnessEnabled
            state.isManualOverrideActive = false
            state.suppressionReason = nil
        }

        pendingTargetCandidate = nil
        currentBrightness = brightnessState.referenceBrightness() ?? outcome.referenceAfter
        lastSentBrightness = candidate
        if outcome.shouldSetCooldown {
            brightnessLimiterCooldownDisplayKey = displayKey
            brightnessLimiterCooldownUntil = Date().addingTimeInterval(brightnessLimiterCooldownDuration)
        } else if brightnessLimiterCooldownDisplayKey == displayKey {
            brightnessLimiterCooldownDisplayKey = nil
            brightnessLimiterCooldownUntil = .distantPast
        }
        logBrightnessWrite(requested: candidate, source: .autoDDCWrite, result: result)
        updateStatus(outcome.statusText)
    }

    func handleAutoBrightnessWriteFailure(
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
            state.mismatchStreak = outcome.mismatchStreak
            state.limiterDetected = outcome.limiterDetected
            state.lastAutoWriteActualAfter = outcome.actualAfter
            state.suppressionReason = "Write error: \(result.message)"
        }
        currentBrightness = brightnessState.referenceBrightness() ?? outcome.referenceAfter
        lastSentBrightness = currentBrightness

        logBrightnessWrite(requested: candidate, source: .autoDDCWrite, result: result)
        updateStatus(outcome.statusText)
    }
}
