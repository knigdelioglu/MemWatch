import AppKit
import CoreGraphics
import Foundation

extension DisplayCoordinator {
    func displayPowerLifecycleSnapshot() -> DisplayPowerLifecycleSnapshot {
        runtimeState.powerLifecycle.snapshot(
            isHiDPIAllowed: isRunning &&
                runtimeState.powerLifecycle.allowsDisplayOperations &&
                !isPostWakeRefreshInProgress
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
        let now = Date()
        if displayPowerState == .waking {
            runtimeState.powerLifecycle.resetWakeStabilization(now: now)
        } else {
            runtimeState.powerLifecycle.beginWaking(now: now)
        }

        isPostWakeRefreshInProgress = false
        let generation = displayPowerGeneration
        updateStatus("Display wake stabilization in progress")
        armWakeStabilizationTask(for: generation)
    }

    func notifyDisplayPowerLifecycleChanged() {
        guard displayPowerState == .active else { return }
        HiDPIReapplyService.shared.notifyPowerStateChanged()
    }

    func refreshHiDPIStateAfterAutomaticReapply() {
        guard displayOperationsAllowed, !isPostWakeRefreshInProgress else { return }
        Task { @MainActor [weak self] in
            guard let self, self.displayOperationsAllowed else { return }
            await self.reloadDisplayModes()
        }
    }

    private func suspendDisplayRuntimeWork() {
        wakeStabilizationTask?.cancel()
        wakeStabilizationTask = nil
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
            armWakeStabilizationTask(for: generation, retryAfter: 1.0)
            return
        }

        guard runtimeState.powerLifecycle.activateIfReady() else { return }
        let activeGeneration = displayPowerGeneration
        DisplayPowerOperationGate.shared.activate(generation: activeGeneration)
        isPostWakeRefreshInProgress = true
        wakeStabilizationTask = nil

        defer { isPostWakeRefreshInProgress = false }

        await reloadDisplayInfo(reloadModes: false)
        guard acceptsDisplayPowerGeneration(activeGeneration) else { return }
        await reloadDisplayModes()
        guard acceptsDisplayPowerGeneration(activeGeneration) else { return }

        refreshInternalBrightness()
        updateCapabilities()
        volumeKeyRouter?.setEnabled(currentDisplayInfo != nil)
        await tick(allowDuringPostWake: true)
        guard acceptsDisplayPowerGeneration(activeGeneration) else { return }

        // The refresh above is the last private/display read in this wake
        // cycle. Only now may the HiDPI service observe an active lifecycle;
        // publishing the transition earlier would let it apply while the
        // post-wake readback is still in flight.
        isPostWakeRefreshInProgress = false
        keepAwakeCoordinator.refreshKeepAwakeLifecycleIfNeeded()
        notifyDisplayPowerLifecycleChanged()
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
