import Cocoa
import CoreGraphics

@MainActor
public final class HiDPIReapplyService {
    
    public static let shared = HiDPIReapplyService()
    
    private var reapplyWorkItem: DispatchWorkItem?
    private var lifecycleState = HiDPIReapplyLifecycle()
    private var manualSwitchSuppressionDepth = 0
    
    private init() {}

    private static let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = {
        _, flags, _ in
        guard flags.contains(.beginConfigurationFlag) == false else { return }
        DispatchQueue.main.async {
            HiDPIReapplyService.shared.triggerReapplyDebounced()
        }
    }
    
    public func startService() {
        guard lifecycleState.start() else { return }

        let result = CGDisplayRegisterReconfigurationCallback(Self.displayReconfigurationCallback, nil)
        guard result == .success else {
            print("[HiDPIReapplyService] Callback registration failed: \(result.rawValue)")
            lifecycleState.registrationFailed()
            return
        }

        print("[HiDPIReapplyService] Yeniden uygulama servisi başlatıldı.")
    }

    public func stopService() {
        let wasListening = lifecycleState.stop()
        guard wasListening else {
            reapplyWorkItem?.cancel()
            reapplyWorkItem = nil
            return
        }

        let result = CGDisplayRemoveReconfigurationCallback(Self.displayReconfigurationCallback, nil)
        if result != .success {
            print("[HiDPIReapplyService] Callback removal failed: \(result.rawValue)")
        }
        reapplyWorkItem?.cancel()
        reapplyWorkItem = nil
    }
    
    public func triggerReapplyDebounced() {
        guard lifecycleState.isListening else { return }
        guard manualSwitchSuppressionDepth == 0 else {
            print("[HiDPIReapplyService] Manual CGS switch suppression aktif; reapply atlandı.")
            return
        }
        guard lifecycleState.scheduleWork() else { return }

        // Debounce işlemi: Ekranların yerine oturması için 2 saniye bekliyoruz
        reapplyWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.executeReapply()
        }
        
        reapplyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
    
    private func executeReapply() {
        defer { lifecycleState.completeWork() }

        guard lifecycleState.isListening else { return }
        guard manualSwitchSuppressionDepth == 0 else {
            print("[HiDPIReapplyService] Manual CGS switch suppression aktif; reapply iptal edildi.")
            return
        }

        print("[HiDPIReapplyService] Yeniden uygulama işlemi yürütülüyor...")
        
        // 1. Kullanıcı HiDPI özelliğini aktif etti mi?
        guard HiDPIStateStore.isHiDPIEnabled() else {
            print("[HiDPIReapplyService] HiDPI modu kullanıcı tarafından aktif edilmemiş. İşlem iptal edildi.")
            return
        }

        // 2. Hedef Samsung ekran bağlı mı?
        do {
            let resolvedDisplay = try HiDPITargetDisplayResolver.resolveSamsungS60UD()
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

            if decision.shouldApply == false {
                print("[HiDPIReapplyService] \(decision.reason)")
                return
            }

            let report = switcher.applyCGSMode(modeID: Int(selectedCandidate.modeID))
            if report.success {
                HiDPIStateStore.setHiDPIEnabled(true)
                HiDPIStateStore.setStateText("HiDPI enabled")
                print("[HiDPIReapplyService] HiDPI enabled")
            } else {
                print("[HiDPIReapplyService] Mod yeniden uygulanamadı: \(report.failureReason ?? "unknown")")
            }
        } catch {
            print("[HiDPIReapplyService] Ekran sorgulama hatası: \(error.localizedDescription)")
        }
    }

    public func performWithoutReapplyIntervention<T>(_ body: () throws -> T) rethrows -> T {
        manualSwitchSuppressionDepth += 1
        defer { manualSwitchSuppressionDepth = max(0, manualSwitchSuppressionDepth - 1) }
        return try body()
    }

    deinit {
        reapplyWorkItem?.cancel()
        if lifecycleState.isListening {
            _ = CGDisplayRemoveReconfigurationCallback(Self.displayReconfigurationCallback, nil)
        }
    }
}
