import CoreGraphics
import Foundation

protocol DisplayConnectionBackend: Sendable {
    var isAvailable: Bool { get }

    func allDisplayIDs() throws -> [CGDirectDisplayID]
    func setDisplayEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws
}

enum DisplayConnectionBackendError: LocalizedError, Equatable {
    case missingPrivateSymbol(String)
    case displayEnumerationFailed(Int32)
    case beginConfigurationFailed(Int32)
    case mirrorDetachFailed(Int32)
    case configureEnabledFailed(Int32)
    case completeConfigurationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingPrivateSymbol(let name):
            return "Gerekli private ekran sembolü bulunamadı: \(name)"
        case .displayEnumerationFailed(let code):
            return "Private ekran listesi alınamadı (\(code))."
        case .beginConfigurationFailed(let code):
            return "Ekran yapılandırma transaction'ı başlatılamadı (\(code))."
        case .mirrorDetachFailed(let code):
            return "Mirror bağlantısı ayrılamadı (\(code))."
        case .configureEnabledFailed(let code):
            return "Ekran bağlantı durumu değiştirilemedi (\(code))."
        case .completeConfigurationFailed(let code):
            return "Ekran yapılandırması tamamlanamadı (\(code))."
        }
    }
}
