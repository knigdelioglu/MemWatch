import CoreGraphics
import Foundation

public enum HiDPIModeApplyResult {
    case success(message: String)
    case failure(reason: String)
    case noChangeNeeded
}

@MainActor
public final class HiDPIModeApplier {
    
    private static var lastSavedMode: CGDisplayMode?
    private static var lastSavedDisplayID: CGDirectDisplayID?
    
    public static func applyMode(displayID: CGDirectDisplayID, targetMode: PhysicalDisplayMode) -> HiDPIModeApplyResult {
        // Dahili ekran koruması: Dahili ekrana asla mod uygulanamaz
        guard CGDisplayIsBuiltin(displayID) == 0 else {
            return .failure(reason: "Dahili ekrana HiDPI veya çözünürlük modu uygulanamaz.")
        }
        
        // Ekranın online ve aktif olduğunu doğrulayalım
        guard CGDisplayIsOnline(displayID) != 0 && CGDisplayIsActive(displayID) != 0 else {
            return .failure(reason: "Ekran online veya aktif değil.")
        }
        
        // Perfect QHD HiDPI default listede görünmeyebilir; apply için authoritative havuz duplicate-low-res listesidir.
        let applyCandidateModes = NativeDisplayModeReader.getHiDPIApplyCandidateModes(for: displayID)
        guard let matchedMode = applyCandidateModes.first(where: { NativeDisplayModeReader.isSameModeFingerprint($0, targetMode) }) else {
            return .failure(reason: "Hedef mod duplicateLowResolutionModes=true mod listesinde bulunmuyor (Güvenlik koruması).")
        }
        
        // Aktif modu alıp hedef modla karşılaştıralım
        guard let currentCGMode = CGDisplayCopyDisplayMode(displayID) else {
            return .failure(reason: "Mevcut ekran modu okunamadı.")
        }
        
        if currentCGMode.width == matchedMode.width &&
            currentCGMode.height == matchedMode.height &&
            currentCGMode.pixelWidth == matchedMode.pixelWidth &&
            currentCGMode.pixelHeight == matchedMode.pixelHeight &&
            abs(currentCGMode.refreshRate - matchedMode.refreshRate) < 0.1 {
            return .noChangeNeeded
        }
        
        // Geri yükleme (fallback) için mevcut modu kaydedelim
        lastSavedMode = currentCGMode
        lastSavedDisplayID = displayID
        
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let configRef = config else {
            return .failure(reason: "Ekran konfigürasyon işlemi başlatılamadı.")
        }
        
        let configureError = CGConfigureDisplayWithDisplayMode(configRef, displayID, matchedMode.cgMode, nil)
        guard configureError == .success else {
            CGCancelDisplayConfiguration(configRef)
            return .failure(reason: "Mod yapılandırılamadı: \(configureError.rawValue)")
        }
        
        let completeError = CGCompleteDisplayConfiguration(configRef, .forSession)
        guard completeError == .success else {
            CGCancelDisplayConfiguration(configRef)
            // Rollback tetikleyelim
            _ = restoreLastSavedMode()
            return .failure(reason: "Mod konfigürasyonu tamamlanamadı: \(completeError.rawValue). Geri yükleme yapıldı.")
        }
        
        return .success(message: "Mod başarıyla uygulandı: \(matchedMode.description)")
    }
    
    public static func restoreLastSavedMode() -> Bool {
        guard let displayID = lastSavedDisplayID, let savedMode = lastSavedMode else {
            return false
        }
        
        // Dahili ekran koruması
        guard CGDisplayIsBuiltin(displayID) == 0 else {
            return false
        }
        
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let configRef = config else {
            return false
        }
        
        let configureError = CGConfigureDisplayWithDisplayMode(configRef, displayID, savedMode, nil)
        guard configureError == .success else {
            CGCancelDisplayConfiguration(configRef)
            return false
        }
        
        let completeError = CGCompleteDisplayConfiguration(configRef, .forSession)
        if completeError != .success {
            CGCancelDisplayConfiguration(configRef)
            return false
        }
        
        lastSavedMode = nil
        lastSavedDisplayID = nil
        return true
    }
}
