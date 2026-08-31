import Cocoa
import CoreGraphics

@MainActor
public final class HiDPIReapplyService {
    
    public static let shared = HiDPIReapplyService()
    
    private var reapplyWorkItem: DispatchWorkItem?
    private var isListening = false
    private var manualSwitchSuppressionDepth = 0
    
    private init() {}
    
    public func startService() {
        guard !isListening else { return }
        
        // Workspace/application notifications are owned by DisplayCoordinator.
        // Keep only the low-level callback here so one lifecycle owns refresh events.
        CGDisplayRegisterReconfigurationCallback({ (displayID, flags, userInfo) in
            // Ekran konfigürasyon değişikliklerinde servise haber ver
            if flags.contains(.beginConfigurationFlag) == false {
                // Konfigürasyon bittiğinde reapply tetikleyelim
                DispatchQueue.main.async {
                    HiDPIReapplyService.shared.triggerReapplyDebounced()
                }
            }
        }, nil)
        
        isListening = true
        print("[HiDPIReapplyService] Yeniden uygulama servisi başlatıldı.")
    }
    
    public func triggerReapplyDebounced() {
        guard manualSwitchSuppressionDepth == 0 else {
            print("[HiDPIReapplyService] Manual CGS switch suppression aktif; reapply atlandı.")
            return
        }

        // Debounce işlemi: Ekranların yerine oturması için 2 saniye bekliyoruz
        reapplyWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.executeReapply()
        }
        
        reapplyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
    
    private func executeReapply() {
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
}
