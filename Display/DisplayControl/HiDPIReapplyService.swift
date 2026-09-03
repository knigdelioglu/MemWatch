import Cocoa
import CoreGraphics

@MainActor
public final class HiDPIReapplyService {
    public static let shared = HiDPIReapplyService()

    private static let debounceNanoseconds: UInt64 = 2_000_000_000
    private static let selfGeneratedCallbackSuppression: TimeInterval = 2.0

    private var reapplyTask: Task<Void, Never>?
    private var lifecycleState = HiDPIReapplyLifecycle()
    private var manualSwitchSuppressionDepth = 0
    private var powerStateProvider: (@MainActor () -> DisplayPowerLifecycleSnapshot)?
    private var powerBoundaryHandler: (@MainActor () -> Void)?
    private var reapplyCompletionHandler: (@MainActor () -> Void)?
    private var pendingTriggerWhilePowerBlocked = false
    private var selfGeneratedCallbackSuppressionUntil = Date.distantPast

    private init() {}

    private static let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = {
        _, flags, _ in
        guard flags.contains(.beginConfigurationFlag) == false else { return }
        Task { @MainActor in
            HiDPIReapplyService.shared.handleDisplayReconfigurationCallback()
        }
    }

    func configurePowerStateProvider(
        _ provider: @escaping @MainActor () -> DisplayPowerLifecycleSnapshot,
        powerBoundaryHandler: (@MainActor () -> Void)? = nil,
        reapplyCompletionHandler: (@MainActor () -> Void)? = nil
    ) {
        powerStateProvider = provider
        self.powerBoundaryHandler = powerBoundaryHandler
        self.reapplyCompletionHandler = reapplyCompletionHandler
    }

    public func startService() {
        guard lifecycleState.start() else { return }

        let result = CGDisplayRegisterReconfigurationCallback(Self.displayReconfigurationCallback, nil)
        guard result == .success else {
            print("[HiDPIReapplyService] Callback registration failed: \(result.rawValue)")
            lifecycleState.registrationFailed()
            return
        }

        lifecycleState.registrationSucceeded()
        print("[HiDPIReapplyService] Yeniden uygulama servisi başlatıldı.")
    }

    public func stopService() {
        reapplyTask?.cancel()
        reapplyTask = nil
        pendingTriggerWhilePowerBlocked = false
        lifecycleState.cancelWork()
        lifecycleState.endApplyingMode()

        let wasListening = lifecycleState.stop()
        guard wasListening else { return }

        let result = CGDisplayRemoveReconfigurationCallback(Self.displayReconfigurationCallback, nil)
        if result == .success {
            lifecycleState.removalSucceeded()
        } else {
            lifecycleState.removalFailed()
            print("[HiDPIReapplyService] Callback removal failed: \(result.rawValue)")
        }
    }

    /// Cancels scheduled/executing reapply work at a power boundary. A
    /// persisted HiDPI preference remains intact and requests one controlled
    /// retry after the coordinator reports that wake stabilization is done.
    public func suspendForPowerTransition() {
        if HiDPIStateStore.isHiDPIEnabled() {
            pendingTriggerWhilePowerBlocked = true
        }

        reapplyTask?.cancel()
        reapplyTask = nil
        lifecycleState.cancelWork(for: lifecycleState.operationGeneration)
    }

    /// Called only after the coordinator has completed post-wake discovery and
    /// readback. This keeps a callback observed during wake from applying a
    /// private mode too early.
    public func notifyPowerStateChanged() {
        guard canRunHiDPIOperations else { return }
        guard pendingTriggerWhilePowerBlocked else { return }
        pendingTriggerWhilePowerBlocked = false
        triggerReapplyDebounced()
    }

    public func triggerReapplyDebounced() {
        guard lifecycleState.isListening else { return }
        guard manualSwitchSuppressionDepth == 0,
              !lifecycleState.isApplyingMode,
              Date() >= selfGeneratedCallbackSuppressionUntil else {
            return
        }

        guard canRunHiDPIOperations else {
            pendingTriggerWhilePowerBlocked = true
            return
        }

        guard lifecycleState.scheduleWork() else { return }
        let operationGeneration = lifecycleState.operationGeneration
        reapplyTask?.cancel()
        reapplyTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            } catch {
                self?.cancelScheduledWork(for: operationGeneration)
                return
            }

            guard let self else { return }
            await self.executeReapply(operationGeneration: operationGeneration)
        }
    }

    private func handleDisplayReconfigurationCallback() {
        guard lifecycleState.isListening else { return }
        guard !lifecycleState.isApplyingMode else { return }

        let powerSnapshot = currentPowerSnapshot
        guard powerSnapshot.isActive, powerSnapshot.isHiDPIAllowed else {
            // A CG callback can arrive between didWake/screensDidWake and the
            // coordinator's stabilization deadline. Feed it back into the
            // coordinator so the single wake debounce window restarts.
            pendingTriggerWhilePowerBlocked = true
            powerBoundaryHandler?()
            return
        }

        guard lifecycleState.shouldScheduleFromReconfigurationCallback(),
              Date() >= selfGeneratedCallbackSuppressionUntil else {
            return
        }

        triggerReapplyDebounced()
    }

    private var currentPowerSnapshot: DisplayPowerLifecycleSnapshot {
        powerStateProvider?() ?? .blocked
    }

    private var canRunHiDPIOperations: Bool {
        let snapshot = currentPowerSnapshot
        return snapshot.isActive && snapshot.isHiDPIAllowed
    }

    private func cancelScheduledWork(for operationGeneration: UInt64) {
        guard lifecycleState.operationGeneration == operationGeneration else { return }
        lifecycleState.cancelWork(for: operationGeneration)
    }

    private func executeReapply(operationGeneration: UInt64) async {
        guard lifecycleState.beginExecution(for: operationGeneration) else { return }
        defer {
            lifecycleState.completeWork(for: operationGeneration)
            if lifecycleState.operationGeneration == operationGeneration {
                reapplyTask = nil
            }
        }

        guard !Task.isCancelled,
              canRunHiDPIOperations,
              manualSwitchSuppressionDepth == 0 else { return }

        print("[HiDPIReapplyService] Yeniden uygulama işlemi yürütülüyor...")

        guard HiDPIStateStore.isHiDPIEnabled() else {
            print("[HiDPIReapplyService] HiDPI modu kullanıcı tarafından aktif edilmemiş. İşlem iptal edildi.")
            return
        }

        do {
            let resolvedDisplay = try HiDPITargetDisplayResolver.resolveSamsungS60UD()
            guard resolvedDisplay.isOnline,
                  resolvedDisplay.isActive,
                  canRunHiDPIOperations else {
                print("[HiDPIReapplyService] Hedef ekran online/active değil; otomatik reapply iptal edildi.")
                return
            }

            let switcher = CGSModeSwitcher()
            let status = switcher.refreshCGSModes(displayID: resolvedDisplay.displayID)

            guard status.isSamsungFingerprintMatched, !status.isBuiltin else {
                print("[HiDPIReapplyService] Hedef Samsung doğrulanamadı; otomatik reapply iptal edildi.")
                return
            }

            _ = switcher.scanCGSModes(displayID: resolvedDisplay.displayID)
            let dynamicCandidate = switcher.findBestHiDPIMode(
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                targetPixelWidth: 5120,
                targetPixelHeight: 2880,
                preferredRefreshRate: 100.0
            )
            let fallbackCandidate = dynamicCandidate == nil ? switcher.verifiedSamsungFallbackCandidate(
                modeID: 74,
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                targetPixelWidth: 5120,
                targetPixelHeight: 2880,
                preferredRefreshRate: 100.0,
                expectedHiDPI: true
            ) : nil

            guard let selectedCandidate = dynamicCandidate ?? fallbackCandidate else {
                print("[HiDPIReapplyService] HiDPI modu sistem listesinde bulunamadı. Override/configuration kontrolü gerekiyor.")
                return
            }

            let decision = HiDPIFeatureController().shouldReapplyHiDPI(
                activeFingerprint: status.activeFingerprint,
                selectedCandidate: selectedCandidate
            )
            guard decision.shouldApply else {
                print("[HiDPIReapplyService] \(decision.reason)")
                return
            }

            guard canRunHiDPIOperations else { return }
            let report = await switcher.applyCGSMode(modeID: Int(selectedCandidate.modeID))
            guard !Task.isCancelled,
                  lifecycleState.operationGeneration == operationGeneration,
                  canRunHiDPIOperations else { return }

            if report.success {
                HiDPIStateStore.setHiDPIEnabled(true)
                HiDPIStateStore.setStateText("HiDPI enabled")
                print("[HiDPIReapplyService] HiDPI enabled")
                reapplyCompletionHandler?()
            } else {
                print("[HiDPIReapplyService] Mod yeniden uygulanamadı: \(report.failureReason ?? "unknown")")
            }
        } catch {
            print("[HiDPIReapplyService] Ekran sorgulama hatası: \(error.localizedDescription)")
        }
    }

    public func performWithoutReapplyIntervention<T>(_ body: () throws -> T) rethrows -> T {
        let startedApplying = manualSwitchSuppressionDepth == 0 && lifecycleState.beginApplyingMode()
        manualSwitchSuppressionDepth += 1
        defer {
            manualSwitchSuppressionDepth = max(0, manualSwitchSuppressionDepth - 1)
            if startedApplying {
                lifecycleState.endApplyingMode()
                selfGeneratedCallbackSuppressionUntil = Date().addingTimeInterval(Self.selfGeneratedCallbackSuppression)
            }
        }
        return try body()
    }

    public func performWithoutReapplyInterventionAsync<T>(
        _ body: () async throws -> T
    ) async rethrows -> T {
        let startedApplying = manualSwitchSuppressionDepth == 0 && lifecycleState.beginApplyingMode()
        manualSwitchSuppressionDepth += 1
        defer {
            manualSwitchSuppressionDepth = max(0, manualSwitchSuppressionDepth - 1)
            if startedApplying {
                lifecycleState.endApplyingMode()
                selfGeneratedCallbackSuppressionUntil = Date().addingTimeInterval(Self.selfGeneratedCallbackSuppression)
            }
        }
        return try await body()
    }
}
