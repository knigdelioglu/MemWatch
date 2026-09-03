import AppKit
import Foundation

extension DisplayCoordinator {
    func performMonitorVolumeKeyAction(_ action: MonitorVolumeKeyAction) -> Bool {
        guard displayOperationsAllowed else { return false }
        switch action {
        case .increase:
            enqueueVolumeAdjustment(by: 5)
        case .decrease:
            enqueueVolumeAdjustment(by: -5)
        case .mute:
            enqueueMuteToggle()
        }
        return true
    }

    func adjustMonitorVolumeForSettings(by delta: Int) {
        guard displayOperationsAllowed else { return }
        enqueueVolumeAdjustment(by: delta)
    }

    func toggleMuteForSettingsSync() {
        guard displayOperationsAllowed else { return }
        enqueueMuteToggle()
    }

    @discardableResult
    func adjustMonitorVolume(by delta: Int) async -> Bool {
        guard displayOperationsAllowed else { return false }
        let previous = monitorVolumeControlValue
        let target = min(100, max(0, previous + delta))
        let generation = beginVolumeIntent(target: target)
        return await performVolumeAdjustment(
            by: delta,
            target: target,
            previous: previous,
            generation: generation
        )
    }

    @discardableResult
    func setMonitorVolume(_ percent: Int) async -> Bool {
        guard displayOperationsAllowed else { return false }
        let clamped = min(100, max(0, percent))
        let previous = monitorVolumeControlValue
        let generation = beginVolumeIntent(target: clamped)
        return await performVolumeSet(
            clamped,
            previous: previous,
            generation: generation
        )
    }

    @discardableResult
    func toggleMuteForSettings() async -> Bool {
        guard displayOperationsAllowed else { return false }
        let previous = monitorVolumeControlValue
        let isMuted = previous == 0
        let targetVolume = isMuted ? max(1, volumeCoordinator.lastNonZeroVolume) : 0
        let generation = beginVolumeIntent(target: targetVolume)
        return await performMuteToggle(
            isMuted: isMuted,
            target: targetVolume,
            previous: previous,
            generation: generation
        )
    }

    func setMonitorVolumeForSettings(_ percent: Int) {
        guard displayOperationsAllowed else { return }
        let clamped = min(100, max(0, percent))
        let previous = monitorVolumeControlValue
        let generation = beginVolumeIntent(target: clamped)
        manualVolumeWriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.performVolumeSet(clamped, previous: previous, generation: generation)
        }
    }

    func setMonitorBrightness(_ percent: Int) {
        guard displayOperationsAllowed else { return }
        let clamped = min(100, max(0, percent))
        pauseAutoBrightnessTemporarily()
        let writeGeneration = startManualBrightnessWrite()
        brightnessState.pendingManualBrightnessPercent = clamped
        manualBrightnessWriteTask?.cancel()
        manualBrightnessWriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performManualBrightnessWrite(clamped, generation: writeGeneration)
        }
    }

    /// Owns the slider debounce so auto/mute/keyboard intents can cancel it
    /// from the same coordinator that owns the latest-intent gate.
    func scheduleMonitorBrightnessWrite(_ percent: Int) {
        guard displayOperationsAllowed else { return }
        let clamped = min(100, max(0, percent))
        pauseAutoBrightnessTemporarily()
        let writeGeneration = startManualBrightnessWrite()
        brightnessState.pendingManualBrightnessPercent = clamped
        manualBrightnessWriteTask?.cancel()
        manualBrightnessWriteTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: ExternalSliderInteractionPolicy.brightnessDebounceNanoseconds)
            } catch {
                return
            }
            guard let self, self.acceptsManualBrightnessWrite(writeGeneration) else { return }
            await self.performManualBrightnessWrite(clamped, generation: writeGeneration)
        }
    }

    func scheduleMonitorVolumeWrite(_ percent: Int) {
        guard displayOperationsAllowed else { return }
        let clamped = min(100, max(0, percent))
        let previous = monitorVolumeControlValue
        let generation = beginVolumeIntent(target: clamped)
        manualVolumeWriteTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: ExternalSliderInteractionPolicy.volumeDebounceNanoseconds)
            } catch {
                return
            }
            guard let self, self.acceptsManualVolumeWrite(generation) else { return }
            _ = await self.performVolumeSet(clamped, previous: previous, generation: generation)
        }
    }

    func cancelPendingManualBrightnessWrite() {
        manualBrightnessWriteTask?.cancel()
        manualBrightnessWriteTask = nil
        guard brightnessState.pendingManualBrightnessPercent != nil else { return }
        invalidateManualBrightnessWrites()
        brightnessState.pendingManualBrightnessPercent = nil
    }

    func cancelPendingManualVolumeWrite() {
        manualVolumeWriteTask?.cancel()
        manualVolumeWriteTask = nil
        guard pendingVolumeIntent != nil else { return }
        invalidateManualVolumeWrites()
        pendingVolumeIntent = nil
    }

    private func beginVolumeIntent(target: Int?) -> UInt64 {
        manualVolumeWriteTask?.cancel()
        manualVolumeWriteTask = nil
        let generation = startManualVolumeWrite()
        pendingVolumeIntent = target
        return generation
    }

    private func enqueueVolumeAdjustment(by delta: Int) {
        let previous = monitorVolumeControlValue
        let target = min(100, max(0, previous + delta))
        let generation = beginVolumeIntent(target: target)
        manualVolumeWriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.performVolumeAdjustment(
                by: delta,
                target: target,
                previous: previous,
                generation: generation
            )
        }
    }

    private func enqueueMuteToggle() {
        let previous = monitorVolumeControlValue
        let isMuted = previous == 0
        let target = isMuted ? max(1, volumeCoordinator.lastNonZeroVolume) : 0
        let generation = beginVolumeIntent(target: target)
        manualVolumeWriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.performMuteToggle(
                isMuted: isMuted,
                target: target,
                previous: previous,
                generation: generation
            )
        }
    }

    private func performVolumeSet(
        _ clamped: Int,
        previous: Int,
        generation: UInt64
    ) async -> Bool {
        guard displayOperationsAllowed, acceptsManualVolumeWrite(generation) else { return false }
        let powerGeneration = displayPowerGeneration
        let (success, _) = await brightnessCoordinator.writer.setVolume(clamped, preferredKey: activeDisplayKey)
        guard acceptsDisplayPowerGeneration(powerGeneration),
              acceptsManualVolumeWrite(generation) else { return false }

        pendingVolumeIntent = nil
        if success {
            currentVolume = clamped
            volumeCoordinator.record(clamped)
            updateStatus("Volume \(clamped)%")
        } else {
            currentVolume = previous
            updateStatus("Volume set failed")
        }
        return success
    }

    private func performVolumeAdjustment(
        by delta: Int,
        target: Int,
        previous: Int,
        generation: UInt64
    ) async -> Bool {
        guard displayOperationsAllowed, acceptsManualVolumeWrite(generation) else { return false }
        let powerGeneration = displayPowerGeneration
        let (success, _) = await brightnessCoordinator.writer.changeVolume(delta, preferredKey: activeDisplayKey)
        guard acceptsDisplayPowerGeneration(powerGeneration),
              acceptsManualVolumeWrite(generation) else { return false }

        pendingVolumeIntent = nil
        if success {
            currentVolume = target
            volumeCoordinator.record(target)
            updateStatus("Volume \(target)%")
        } else {
            currentVolume = previous
            updateStatus("Volume change failed")
        }
        return success
    }

    private func performMuteToggle(
        isMuted: Bool,
        target: Int,
        previous: Int,
        generation: UInt64
    ) async -> Bool {
        guard displayOperationsAllowed, acceptsManualVolumeWrite(generation) else { return false }
        let powerGeneration = displayPowerGeneration
        let (success, _) = await brightnessCoordinator.writer.setMute(!isMuted, preferredKey: activeDisplayKey)
        guard acceptsDisplayPowerGeneration(powerGeneration),
              acceptsManualVolumeWrite(generation) else { return false }

        pendingVolumeIntent = nil
        if success {
            currentVolume = target
            volumeCoordinator.record(target)
            updateStatus(isMuted ? "Unmuted" : "Muted")
        } else {
            currentVolume = previous
            updateStatus("Mute failed")
        }
        return success
    }

    private func performManualBrightnessWrite(_ clamped: Int, generation: UInt64) async {
        guard displayOperationsAllowed, acceptsManualBrightnessWrite(generation) else { return }
        let powerGeneration = displayPowerGeneration
        let result = await brightnessCoordinator.writer.setBrightness(clamped, preferredKey: activeDisplayKey)
        guard acceptsDisplayPowerGeneration(powerGeneration),
              acceptsManualBrightnessWrite(generation) else { return }
        brightnessState.pendingManualBrightnessPercent = nil
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

    @discardableResult
    func setInternalBrightness(_ percent: Int) -> Bool {
        guard displayOperationsAllowed else { return false }
        guard let controller = brightnessCoordinator.internalDisplayController else {
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
        guard displayOperationsAllowed else { return }
        invalidateManualBrightnessWrites()
        beginManualBrightnessOverride(fallbackDuration: duration)
    }

    /// Marks the beginning of a real slider interaction. The override is
    /// established before the debounced DDC write can be scheduled, and any
    /// auto write already in flight becomes a stale completion.
    func beginManualBrightnessInteraction() {
        guard displayOperationsAllowed else { return }
        pauseAutoBrightnessTemporarily()
        manualBrightnessInteractionActive = true
        pendingTargetCandidate = nil
        pendingTargetCandidateSince = .distantPast
    }

    func endManualBrightnessInteraction() {
        manualBrightnessInteractionActive = false
    }

    func setAutoBrightnessEnabled(_ enabled: Bool) {
        // The mode toggle is itself a newer intent. Invalidate both pending
        // manual debounce and auto completions before changing presentation
        // state, so an older slider task cannot re-enable manual override.
        manualBrightnessWriteTask?.cancel()
        manualBrightnessWriteTask = nil
        invalidateManualBrightnessWrites()
        brightnessState.pendingManualBrightnessPercent = nil
        manualBrightnessInteractionActive = false
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

    func beginManualBrightnessOverride(fallbackDuration: TimeInterval = 20) {
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

    func clearManualBrightnessOverride() {
        manualBrightnessOverrideStartLux = nil
        manualBrightnessOverrideUntil = .distantPast
        pendingTargetCandidate = nil
        updateBrightnessState { state in
            state.isManualOverrideActive = false
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil
        }
    }

    func shouldHoldManualBrightnessOverride(currentLux: Double, now: Date) -> Bool {
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

}
