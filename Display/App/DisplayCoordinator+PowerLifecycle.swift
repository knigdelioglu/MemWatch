import AppKit
import CoreGraphics
import Foundation

private enum AmbientLightSensorRecoveryPolicy {
    static let retryDelaysNanoseconds: [UInt64] = [
        0,
        250_000_000,
        500_000_000,
        1_000_000_000,
        2_000_000_000
    ]
}

extension DisplayCoordinator {
    func displayPowerLifecycleSnapshot() -> DisplayPowerLifecycleSnapshot {
        _ = targetDisplayReadiness
        let targetSnapshot = targetDisplayOperationGate.snapshot()
        return runtimeState.powerLifecycle.snapshot(
            isHiDPIAllowed: isRunning &&
                runtimeState.powerLifecycle.allowsDisplayOperations &&
                !isPostWakeRefreshInProgress,
            targetDisplayReadiness: targetSnapshot.readiness,
            targetDisplayGeneration: targetSnapshot.generation
        )
    }

    func handleSystemSleepEvent() {
        guard isRunning else { return }
        runtimeState.powerLifecycle.enterSystemSleep()
        suspendDisplayRuntimeWork()
        keepAwakeCoordinator.handleSystemSleep()
        updateStatus("Display runtime suspended for system sleep")
    }

    func handleScreenSleepEvent() {
        guard isRunning, displayPowerState != .systemSleeping else { return }
        runtimeState.powerLifecycle.enterScreenSleep()
        suspendDisplayRuntimeWork()
        keepAwakeCoordinator.handleDisplaySleep()
        updateStatus("Display runtime suspended for screen sleep")
    }

    func beginDisplayWakeStabilization() {
        guard isRunning else { return }

        suspendDisplayRuntimeWork()
        wakeStabilizationRetryCount = 0
        let now = Date()
        if displayPowerState == .waking {
            runtimeState.powerLifecycle.resetWakeStabilization(now: now)
        } else {
            runtimeState.powerLifecycle.beginWaking(now: now)
        }

        targetDisplayOperationGate.beginStabilizing()
        isPostWakeRefreshInProgress = false
        let generation = displayPowerGeneration
        updateStatus("Display wake stabilization in progress")
        armWakeStabilizationTask(for: generation)
    }

    func notifyDisplayPowerLifecycleChanged() {
        guard externalDisplayReadOperationsAllowed,
              !isPostWakeRefreshInProgress else { return }
        HiDPIReapplyService.shared.notifyPowerStateChanged()
    }

    func refreshHiDPIStateAfterAutomaticReapply() {
        guard externalDisplayReadOperationsAllowed, !isPostWakeRefreshInProgress else { return }
        // The reapply service suppresses its own display-change callback while
        // the CGS transaction is running. Establish the brightness/ALS epoch
        // explicitly here so that a self-generated display-parameter change
        // cannot bypass the transition reset.
        let powerGeneration = displayPowerGeneration
        beginBrightnessControlEpoch(reason: "display parameter transition")
        let brightnessEpoch = brightnessControlEpoch
        let didRebindALS = brightnessCoordinator.rebindAmbientLightSensor()
        traceRuntime(
            "ALS rebind reason=display parameter transition (HiDPI reapply) " +
                "success=\(didRebindALS) displayKey=\(currentDisplayKey ?? "nil") " +
                "clientGeneration=\(brightnessCoordinator.ambientLightSensorClientGeneration) " +
                "rebindCount=\(brightnessCoordinator.ambientLightSensorRebindCount)"
        )
        Task { @MainActor [weak self] in
            guard let self,
                  self.externalDisplayReadOperationsAllowed,
                  self.acceptsDisplayPowerGeneration(powerGeneration),
                  self.acceptsBrightnessControlEpoch(brightnessEpoch) else { return }
            await self.reloadDisplayModes(allowDuringPostWake: true)
            guard self.externalDisplayReadOperationsAllowed,
                  self.acceptsDisplayPowerGeneration(powerGeneration),
                  self.acceptsBrightnessControlEpoch(brightnessEpoch) else { return }
            self.beginAmbientLightSensorRecovery(reason: "display parameter transition")
        }
    }

    /// Starts one bounded ALS recovery chain for the current active display
    /// epoch. Sensor rebinding is target-gated and never continues across a
    /// power or brightness epoch change.
    func beginAmbientLightSensorRecovery(reason: String) {
        guard isRunning,
              displayPowerState == .active,
              externalDisplayReadOperationsAllowed,
              !manualBrightnessInteractionActive,
              brightnessState.pendingManualBrightnessPercent == nil,
              !brightnessState.isManualOverrideActive else { return }

        guard brightnessCoordinator.reader != nil else {
            updateBrightnessState { state in
                state.lastBrightnessSource = .unavailable
                state.suppressionReason = "Ambient light sensor unavailable"
            }
            return
        }

        let powerGeneration = displayPowerGeneration
        let brightnessEpoch = brightnessControlEpoch
        let manualBrightnessWriteGeneration = currentManualBrightnessWriteGeneration
        guard ambientLightSensorRecoveryEpoch != brightnessEpoch else { return }

        ambientLightSensorRecoveryTask?.cancel()
        ambientLightSensorRecoveryTask = nil
        ambientLightSensorRecoveryToken &+= 1
        let token = ambientLightSensorRecoveryToken
        ambientLightSensorRecoveryEpoch = brightnessEpoch
        traceRuntime(
            "ALS recovery begin reason=\(reason) powerGeneration=\(powerGeneration) " +
                "brightnessEpoch=\(brightnessEpoch) token=\(token)"
        )
        updateBrightnessState { state in
            state.suppressionReason = "Ambient light sensor recovery in progress"
        }

        let delays = AmbientLightSensorRecoveryPolicy.retryDelaysNanoseconds
        ambientLightSensorRecoveryTask = Task { @MainActor [weak self] in
            defer {
                guard let self,
                      self.ambientLightSensorRecoveryToken == token,
                      self.ambientLightSensorRecoveryEpoch == brightnessEpoch else {
                    return
                }
                // Manual interaction, a newer slider intent, or a lifecycle
                // boundary can make this chain stale. Always release the
                // epoch marker so a later normal tick may start a fresh,
                // bounded recovery if the sensor is still unavailable.
                self.ambientLightSensorRecoveryTask = nil
                self.ambientLightSensorRecoveryEpoch = nil
            }
            for (attempt, delay) in delays.enumerated() {
                do {
                    if delay > 0 {
                        try await Task.sleep(nanoseconds: delay)
                    }
                    try Task.checkCancellation()
                } catch {
                    return
                }

                guard let self,
                      self.acceptsAmbientLightSensorRecovery(
                          powerGeneration: powerGeneration,
                          brightnessEpoch: brightnessEpoch,
                          manualBrightnessWriteGeneration: manualBrightnessWriteGeneration,
                          token: token
                      ) else {
                    return
                }

                let didRebind = self.brightnessCoordinator.rebindAmbientLightSensor()
                let lux = self.brightnessCoordinator.reader?.readLux()
                guard self.acceptsAmbientLightSensorRecovery(
                    powerGeneration: powerGeneration,
                    brightnessEpoch: brightnessEpoch,
                    manualBrightnessWriteGeneration: manualBrightnessWriteGeneration,
                    token: token
                ) else {
                    return
                }

                self.traceRuntime(
                    "ALS recovery attempt=\(attempt + 1)/\(delays.count) rebind=\(didRebind) " +
                        "lux=\(lux.map { String(format: "%.1f", $0) } ?? "nil")"
                )
                guard let lux else { continue }

                self.luxFilter.reset()
                self.lastSmoothedLux = nil
                self.currentLux = nil
                // Do not use the recovery read as a side door around the
                // interactive gate. The normal tick owns target/reference
                // selection and will simply wait if post-wake work is active.
                if self.externalDisplayInteractiveOperationsAllowed {
                    await self.runRecoveredAmbientTick(
                        lux: lux,
                        powerGeneration: powerGeneration,
                        brightnessEpoch: brightnessEpoch,
                        manualBrightnessWriteGeneration: manualBrightnessWriteGeneration,
                        token: token
                    )
                }
                guard self.ambientLightSensorRecoveryToken == token else { return }
                self.ambientLightSensorRecoveryTask = nil
                self.ambientLightSensorRecoveryEpoch = nil
                return
            }

            guard let self,
                  self.acceptsAmbientLightSensorRecovery(
                      powerGeneration: powerGeneration,
                      brightnessEpoch: brightnessEpoch,
                      manualBrightnessWriteGeneration: manualBrightnessWriteGeneration,
                      token: token
                  ) else {
                return
            }
            self.ambientLightSensorRecoveryTask = nil
            self.updateBrightnessState { state in
                state.lastBrightnessSource = .unavailable
                state.suppressionReason = "Ambient light sensor recovery exhausted"
            }
            self.updateStatus("Sensör kullanılamıyor; ALS kurtarma başarısız")
            self.traceRuntime(
                "ALS recovery exhausted powerGeneration=\(powerGeneration) " +
                    "brightnessEpoch=\(brightnessEpoch) token=\(token)"
            )
        }
    }

    func cancelAmbientLightSensorRecovery() {
        ambientLightSensorRecoveryTask?.cancel()
        ambientLightSensorRecoveryTask = nil
        ambientLightSensorRecoveryEpoch = nil
        ambientLightSensorRecoveryToken &+= 1
    }

    private func acceptsAmbientLightSensorRecovery(
        powerGeneration: UInt64,
        brightnessEpoch: UInt64,
        manualBrightnessWriteGeneration: UInt64,
        token: UInt64
    ) -> Bool {
        !Task.isCancelled &&
            isRunning &&
            displayPowerState == .active &&
            displayPowerGeneration == powerGeneration &&
            brightnessControlEpoch == brightnessEpoch &&
            acceptsManualBrightnessWrite(manualBrightnessWriteGeneration) &&
            !manualBrightnessInteractionActive &&
            brightnessState.pendingManualBrightnessPercent == nil &&
            !brightnessState.isManualOverrideActive &&
            ambientLightSensorRecoveryToken == token &&
            externalDisplayReadOperationsAllowed
    }

    /// Hands a recovered sample back to the normal tick without racing an
    /// already-running DDC pass. The wait is deliberately bounded; the
    /// scheduler remains the fallback if a competing tick never yields.
    private func runRecoveredAmbientTick(
        lux: Double,
        powerGeneration: UInt64,
        brightnessEpoch: UInt64,
        manualBrightnessWriteGeneration: UInt64,
        token: UInt64
    ) async {
        for _ in 0..<5 {
            guard acceptsAmbientLightSensorRecovery(
                powerGeneration: powerGeneration,
                brightnessEpoch: brightnessEpoch,
                manualBrightnessWriteGeneration: manualBrightnessWriteGeneration,
                token: token
            ),
                  externalDisplayInteractiveOperationsAllowed,
                  !manualBrightnessInteractionActive,
                  brightnessState.pendingManualBrightnessPercent == nil else {
                return
            }
            guard !isTickRunning else {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }
                continue
            }
            await tick(recoveredLux: lux)
            return
        }
    }

    private func suspendDisplayRuntimeWork() {
        wakeStabilizationTask?.cancel()
        wakeStabilizationTask = nil
        wakeStabilizationRetryCount = 0
        targetReadinessTask?.cancel()
        targetReadinessRetryCount = 0
        targetRecoveryToken &+= 1
        targetDisplayOperationGate.invalidate()
        isPostWakeRefreshInProgress = false
        displayTickTask?.cancel()
        displayTickTask = nil
        displayTickTaskToken &+= 1

        // Do not clear `isTickRunning` here. An already-running tick owns
        // that flag until its defer executes; clearing it would allow a
        // post-wake tick to overlap the old DDC operation.

        manualBrightnessWriteTask?.cancel()
        manualBrightnessWriteTask = nil
        invalidateManualBrightnessWrites()
        brightnessState.pendingManualBrightnessPercent = nil
        beginBrightnessControlEpoch(reason: "power transition")

        manualVolumeWriteTask?.cancel()
        manualVolumeWriteTask = nil
        invalidateManualVolumeWrites()
        pendingVolumeIntent = nil

        pendingTargetCandidate = nil
        manualBrightnessInteractionActive = false
        lastDisplaySearchDate = .distantPast
        lastBrightnessReadDate = .distantPast
        lastVolumeReadDate = .distantPast
        volumeKeyRouter?.setEnabled(false)

        // This gate is checked again immediately before DDC Process.run and
        // before private display calls, closing the await-to-side-effect gap.
        DisplayPowerOperationGate.shared.suspend()
        Task { await brightnessCoordinator.writer.cancelInFlightOperations() }
        HiDPIReapplyService.shared.suspendForPowerTransition()
    }

    private func armWakeStabilizationTask(for generation: UInt64, retryAfter delay: TimeInterval? = nil) {
        wakeStabilizationTask?.cancel()

        let wait: TimeInterval
        if let delay {
            wait = max(0.1, delay)
        } else if let deadline = runtimeState.powerLifecycle.wakeStabilizationDeadline {
            wait = max(0.1, deadline.timeIntervalSinceNow)
        } else {
            wait = DisplayPowerLifecycle.defaultWakeStabilization
        }

        let nanoseconds = UInt64((wait * 1_000_000_000).rounded())
        wakeStabilizationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard let self,
                  self.isRunning,
                  self.displayPowerState == .waking,
                  self.displayPowerGeneration == generation else { return }
            await self.finishDisplayWakeStabilization(for: generation)
        }
    }

    private func finishDisplayWakeStabilization(for generation: UInt64) async {
        guard displayPowerState == .waking,
              displayPowerGeneration == generation,
              runtimeState.powerLifecycle.isWakeStabilized() else { return }

        guard displayStackIsOnlineAndActive() else {
            updateStatus("Display stack is still waking")
            wakeStabilizationRetryCount += 1
            armWakeStabilizationTask(for: generation, retryAfter: 1.0)
            return
        }

        let targetExpected = isTargetSamsungExpected()
        var targetReadyDisplayID: CGDirectDisplayID?

        if TargetDisplayWakeStabilizationPolicy.shouldWaitForTarget(
            isTargetExpected: targetExpected,
            retryCount: wakeStabilizationRetryCount
        ), wakeStabilizationRetryCount < TargetDisplayWakeStabilizationPolicy.maxRetries {
            guard let initialCandidate = targetSamsungCandidate(),
                  initialCandidate.isOnline,
                  initialCandidate.isActive else {
                updateStatus("Samsung S60UD is waking…")
                wakeStabilizationRetryCount += 1
                armWakeStabilizationTask(for: generation, retryAfter: 1.0)
                return
            }

            // 500-1000 ms quiet verification window to ensure display ID
            // and mode stack stability.
            do {
                try await Task.sleep(nanoseconds: TargetDisplayWakeStabilizationPolicy.confirmationNanoseconds)
            } catch {
                return
            }

            guard displayPowerState == .waking,
                  displayPowerGeneration == generation else { return }

            let confirmedCandidate = targetSamsungCandidate()
            guard TargetDisplayWakeStabilizationPolicy.isCandidateValid(
                initial: initialCandidate,
                confirmed: confirmedCandidate
            ) else {
                updateStatus("Samsung S60UD is restabilizing…")
                wakeStabilizationRetryCount += 1
                armWakeStabilizationTask(for: generation, retryAfter: 1.0)
                return
            }

            targetReadyDisplayID = initialCandidate.displayID
        }

        if targetExpected, let targetReadyDisplayID {
            _ = targetDisplayOperationGate.markReady(displayID: targetReadyDisplayID)
        } else if targetExpected {
            // The aggressive phase is bounded, but this is deliberately not
            // a success path. Global runtime may activate while the target
            // remains blocked in stabilizing state.
            targetDisplayOperationGate.beginStabilizing()
            targetReadinessRetryCount = max(
                targetReadinessRetryCount,
                wakeStabilizationRetryCount
            )
        } else {
            targetDisplayOperationGate.invalidate()
        }

        guard runtimeState.powerLifecycle.activateIfReady() else { return }
        let activeGeneration = displayPowerGeneration
        DisplayPowerOperationGate.shared.activate(generation: activeGeneration)
        wakeStabilizationTask = nil
        wakeStabilizationRetryCount = 0

        if let targetReadyDisplayID {
            await performControlledTargetRecovery(
                powerGeneration: activeGeneration,
                targetDisplayID: targetReadyDisplayID,
                targetOperationGeneration: targetDisplayOperationGate.currentGeneration()
            )
        } else {
            // Keep the global runtime usable for the built-in display even
            // when Samsung has not become ready yet.
            refreshInternalBrightness()
            updateCapabilities()
            volumeKeyRouter?.setEnabled(false)
            keepAwakeCoordinator.refreshKeepAwakeLifecycleIfNeeded()

            if targetExpected {
                beginTargetDisplayReadinessRecovery(
                    for: activeGeneration,
                    initialDelay: TargetDisplayWakeStabilizationPolicy.retryDelay(
                        afterRetryCount: targetReadinessRetryCount
                    ),
                    preserveRetryCount: true
                )
            }
        }
    }

    func beginTargetDisplayReadinessRecoveryIfNeeded(for powerGeneration: UInt64) {
        guard !targetDisplayReadiness.isReady else { return }
        beginTargetDisplayReadinessRecovery(for: powerGeneration, initialDelay: 0)
    }

    func restartTargetDisplayReadinessRecovery(for powerGeneration: UInt64) {
        guard isRunning else { return }
        beginBrightnessControlEpoch(reason: "display parameter transition")
        let didRebindALS = brightnessCoordinator.rebindAmbientLightSensor()
        traceRuntime(
            "ALS rebind reason=display parameter transition success=\(didRebindALS) " +
                "displayKey=\(currentDisplayKey ?? "nil") " +
                "clientGeneration=\(brightnessCoordinator.ambientLightSensorClientGeneration) " +
                "rebindCount=\(brightnessCoordinator.ambientLightSensorRebindCount)"
        )
        beginTargetDisplayReadinessRecovery(
            for: powerGeneration,
            initialDelay: 0,
            forceRestart: true
        )
    }

    private func beginTargetDisplayReadinessRecovery(
        for powerGeneration: UInt64,
        initialDelay: TimeInterval? = nil,
        preserveRetryCount: Bool = false,
        forceRestart: Bool = false
    ) {
        guard isRunning,
              displayPowerState == .active,
              displayPowerGeneration == powerGeneration else { return }
        guard isTargetSamsungExpected() else {
            targetDisplayOperationGate.invalidate()
            return
        }

        // A single task owns target confirmation and recovery. A display
        // parameter callback may restart that one task to invalidate an
        // in-flight sample window, but it never creates a parallel chain.
        if targetReadinessTask != nil {
            guard forceRestart else { return }
            targetReadinessTask?.cancel()
            targetReadinessTask = nil
        }

        if !preserveRetryCount {
            targetReadinessRetryCount = 0
        }
        targetRecoveryToken &+= 1
        let token = targetRecoveryToken
        targetDisplayOperationGate.beginStabilizing()
        // Any active controlled refresh is stale once the target epoch is
        // restarted. A new refresh will raise this flag again only after the
        // target reaches ready state.
        isPostWakeRefreshInProgress = false
        volumeKeyRouter?.setEnabled(false)
        cancelTargetInteractiveWork()
        HiDPIReapplyService.shared.suspendForTargetTransition()
        armTargetReadinessTask(
            for: powerGeneration,
            token: token,
            retryAfter: initialDelay
        )
    }

    private func armTargetReadinessTask(
        for powerGeneration: UInt64,
        token: Int,
        retryAfter delay: TimeInterval? = nil
    ) {
        targetReadinessTask?.cancel()
        let wait = max(
            0.1,
            delay ?? TargetDisplayWakeStabilizationPolicy.retryDelay(
                afterRetryCount: targetReadinessRetryCount
            )
        )
        let nanoseconds = UInt64((wait * 1_000_000_000).rounded())
        targetReadinessTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard let self,
                  self.isRunning,
                  self.displayPowerState == .active,
                  self.displayPowerGeneration == powerGeneration,
                  self.targetRecoveryToken == token else { return }
            await self.finishTargetDisplayReadinessRecovery(
                for: powerGeneration,
                token: token
            )
        }
    }

    private func finishTargetDisplayReadinessRecovery(
        for powerGeneration: UInt64,
        token: Int
    ) async {
        guard isRunning,
              displayPowerState == .active,
              displayPowerGeneration == powerGeneration,
              targetRecoveryToken == token,
              !targetDisplayReadiness.isReady else {
            return
        }

        guard isTargetSamsungExpected() else {
            targetReadinessTask = nil
            targetDisplayOperationGate.invalidate()
            return
        }

        guard let initialCandidate = targetSamsungCandidate(),
              initialCandidate.isOnline,
              initialCandidate.isActive else {
            retryTargetDisplayReadiness(
                for: powerGeneration,
                token: token,
                status: "Samsung S60UD is unavailable; retrying readiness"
            )
            return
        }

        do {
            try await Task.sleep(
                nanoseconds: TargetDisplayWakeStabilizationPolicy.confirmationNanoseconds
            )
        } catch {
            return
        }

        guard isRunning,
              displayPowerState == .active,
              displayPowerGeneration == powerGeneration,
              targetRecoveryToken == token else { return }

        let confirmedCandidate = targetSamsungCandidate()
        guard TargetDisplayWakeStabilizationPolicy.isCandidateValid(
            initial: initialCandidate,
            confirmed: confirmedCandidate
        ), let targetDisplayID = confirmedCandidate?.displayID else {
            retryTargetDisplayReadiness(
                for: powerGeneration,
                token: token,
                status: "Samsung S60UD is restabilizing"
            )
            return
        }

        let targetOperationGeneration = targetDisplayOperationGate.markReady(
            displayID: targetDisplayID
        )
        targetReadinessRetryCount = 0
        await performControlledTargetRecovery(
            powerGeneration: powerGeneration,
            targetDisplayID: targetDisplayID,
            targetOperationGeneration: targetOperationGeneration
        )
        if targetRecoveryToken == token {
            targetReadinessTask = nil
        }
    }

    private func retryTargetDisplayReadiness(
        for powerGeneration: UInt64,
        token: Int,
        status: String
    ) {
        guard isRunning,
              displayPowerState == .active,
              displayPowerGeneration == powerGeneration,
              targetRecoveryToken == token else { return }
        targetReadinessRetryCount += 1
        targetDisplayOperationGate.beginStabilizing()
        updateStatus(status)
        armTargetReadinessTask(
            for: powerGeneration,
            token: token,
            retryAfter: TargetDisplayWakeStabilizationPolicy.retryDelay(
                afterRetryCount: targetReadinessRetryCount
            )
        )
    }

    private func performControlledTargetRecovery(
        powerGeneration: UInt64,
        targetDisplayID: CGDirectDisplayID,
        targetOperationGeneration: UInt64
    ) async {
        guard acceptsDisplayPowerGeneration(powerGeneration),
              targetDisplayOperationGate.accepts(
                  targetOperationGeneration,
                  displayID: targetDisplayID
              ) else { return }

        let recoveryToken = targetRecoveryToken
        isPostWakeRefreshInProgress = true
        defer {
            if targetRecoveryToken == recoveryToken {
                isPostWakeRefreshInProgress = false
            }
        }

        await reloadDisplayInfo(reloadModes: false, allowDuringPostWake: true)
        guard acceptsDisplayPowerGeneration(powerGeneration),
              targetDisplayOperationGate.accepts(
                  targetOperationGeneration,
                  displayID: targetDisplayID
              ) else { return }

        await reloadDisplayModes(allowDuringPostWake: true)
        guard acceptsDisplayPowerGeneration(powerGeneration),
              targetDisplayOperationGate.accepts(
                  targetOperationGeneration,
                  displayID: targetDisplayID
              ) else { return }

        refreshInternalBrightness()
        updateCapabilities()
        volumeKeyRouter?.setEnabled(currentDisplayInfo?.displayID == targetDisplayID)
        await tick(allowDuringPostWake: true)
        guard acceptsDisplayPowerGeneration(powerGeneration),
              targetDisplayOperationGate.accepts(
                  targetOperationGeneration,
                  displayID: targetDisplayID
              ) else { return }

        guard targetSamsungCandidate()?.displayID == targetDisplayID else {
            targetDisplayOperationGate.beginStabilizing()
            restartTargetDisplayReadinessRecovery(
                for: powerGeneration
            )
            return
        }

        // This is the final controlled readback/mode step for this target
        // epoch. HiDPI can observe it only after the refresh is complete.
        if targetRecoveryToken == recoveryToken {
            isPostWakeRefreshInProgress = false
        }
        keepAwakeCoordinator.refreshKeepAwakeLifecycleIfNeeded()
        notifyDisplayPowerLifecycleChanged()
    }

    private func cancelTargetInteractiveWork() {
        displayTickTask?.cancel()
        displayTickTask = nil
        displayTickTaskToken &+= 1

        manualBrightnessWriteTask?.cancel()
        manualBrightnessWriteTask = nil
        invalidateManualBrightnessWrites()
        brightnessState.pendingManualBrightnessPercent = nil

        manualVolumeWriteTask?.cancel()
        manualVolumeWriteTask = nil
        invalidateManualVolumeWrites()
        pendingVolumeIntent = nil

        // Do not clear isTickRunning here. An already-running tick owns it
        // until its defer executes, while the target gate invalidates its
        // in-flight DDC side effects.
        Task { await brightnessCoordinator.writer.cancelInFlightOperations() }
    }

    private func targetSamsungCandidate() -> TargetDisplayWakeCandidate? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return nil
        }

        for displayID in displayIDs.prefix(Int(count)) {
            guard CGDisplayIsBuiltin(displayID) == 0 else { continue }
            let vendorID = CGDisplayVendorNumber(displayID)
            let productID = CGDisplayModelNumber(displayID)
            if vendorID == TargetDisplaySpec.samsungQHD.vendorID &&
                productID == TargetDisplaySpec.samsungQHD.productID {
                return TargetDisplayWakeCandidate(
                    displayID: displayID,
                    isOnline: CGDisplayIsOnline(displayID) != 0,
                    isActive: CGDisplayIsActive(displayID) != 0
                )
            }
        }
        return nil
    }

    private func isTargetSamsungPhysicallyOnline() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return false
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displayIDs, &count) == .success else {
            return false
        }

        return displayIDs.prefix(Int(count)).contains { displayID in
            CGDisplayIsBuiltin(displayID) == 0 &&
                CGDisplayVendorNumber(displayID) == TargetDisplaySpec.samsungQHD.vendorID &&
                CGDisplayModelNumber(displayID) == TargetDisplaySpec.samsungQHD.productID &&
                CGDisplayIsOnline(displayID) != 0
        }
    }

    private func isTargetSamsungExpected() -> Bool {
        if isTargetSamsungPhysicallyOnline() {
            return true
        }
        if currentDisplayInfo != nil {
            return true
        }
        if store.preferences.selectedDisplayKey != nil {
            return true
        }
        return false
    }

    private func displayStackIsOnlineAndActive() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return false
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return false
        }

        return displayIDs.prefix(Int(count)).contains {
            CGDisplayIsOnline($0) != 0 && CGDisplayIsActive($0) != 0
        }
    }
}
