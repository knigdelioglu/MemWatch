import Foundation
import CoreGraphics

public struct DisplayModeFingerprint: Codable, Equatable {
    public let logicalWidth: Int
    public let logicalHeight: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isHiDPI: Bool?
    public let isStrongHiDPI: Bool?
    public let isPerfectQHDHiDPI: Bool?
    public let pixelEncoding: String
    public let ioFlags: UInt32
    public let modeSource: String?
    public let displayVendorID: UInt32
    public let displayProductID: UInt32
    public let displaySerial: UInt32
    
    public init(mode: PhysicalDisplayMode, vendorID: UInt32, productID: UInt32, serial: UInt32) {
        self.logicalWidth = mode.width
        self.logicalHeight = mode.height
        self.pixelWidth = mode.pixelWidth
        self.pixelHeight = mode.pixelHeight
        self.refreshRate = mode.refreshRate
        self.isHiDPI = mode.isHiDPI
        self.isStrongHiDPI = mode.isStrongHiDPI
        self.isPerfectQHDHiDPI = NativeDisplayModeReader.isPerfectQHDHiDPIMode(mode)
        self.pixelEncoding = mode.pixelEncoding
        self.ioFlags = mode.ioFlags
        self.modeSource = mode.modeSource
        self.displayVendorID = vendorID
        self.displayProductID = productID
        self.displaySerial = serial
    }
}

public final class HiDPIStateStore {
    
    private static let userDefaultsKey = "com.ambientsync.hidpi.savedmode"
    private static let enabledKey = "com.ambientsync.hidpi.enabled"
    private static let stateTextKey = "com.ambientsync.hidpi.stateText"
    
    public static func savePreferredMode(_ fingerprint: DisplayModeFingerprint) {
        if let data = try? JSONEncoder().encode(fingerprint) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    public static func getPreferredMode() -> DisplayModeFingerprint? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(DisplayModeFingerprint.self, from: data)
    }
    
    public static func clearPreferredMode() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    public static func setHiDPIEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }
    
    public static func isHiDPIEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    public static func setStateText(_ text: String) {
        UserDefaults.standard.set(text, forKey: stateTextKey)
    }

    public static func stateText() -> String? {
        UserDefaults.standard.string(forKey: stateTextKey)
    }
}
