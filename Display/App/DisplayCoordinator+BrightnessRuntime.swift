import Foundation

extension DisplayCoordinator {
    func tick() async {
        guard isRunning else { return }
        guard !isTickRunning else { return }
        isTickRunning = true
        defer { isTickRunning = false }

        ddcAvailable = await brightnessCoordinator.isDDCAvailable()
        updateCapabilities()
        refreshSharedRuntimeFeatures()

        if applySoftwareDisconnectedDisplayStateIfNeeded() {
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
            let readback = await brightnessCoordinator.writer.readBrightness(preferredKey: display.displayKey)
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
                ddcAvailable: await brightnessCoordinator.isDDCAvailable(),
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

        let result = await brightnessCoordinator.writer.setBrightness(writeCandidate, preferredKey: display.displayKey)

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

    func handleAutoBrightnessWriteSuccess(
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
            state.lastAutoWriteActualAfter = outcome.actualAfter
            state.suppressionReason = "Write error: \(result.message)"
        }
        currentBrightness = outcome.actualAfter
        lastSentBrightness = outcome.actualAfter

        updateStatus(outcome.statusText)
    }
}
