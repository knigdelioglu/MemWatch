import CoreGraphics
import Foundation

public struct PhysicalDisplayMode: Identifiable, Equatable {
    public let id: String
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isHiDPI: Bool
    public let isStrongHiDPI: Bool
    public let isPerfectQHDHiDPI: Bool
    public let pixelEncoding: String
    public let ioFlags: UInt32
    public let modeSource: String
    public let cgMode: CGDisplayMode
    
    public var description: String {
        let hiDpiText = isPerfectQHDHiDPI ? " (Perfect QHD HiDPI)" : (isHiDPI ? " (HiDPI)" : "")
        let refreshText = refreshRate > 0 ? String(format: " @ %.0fHz", refreshRate) : ""
        return "\(width)x\(height)\(hiDpiText)\(refreshText)"
    }
}

public final class NativeDisplayModeReader {
    
    public static func getAvailableModes(
        for displayID: CGDirectDisplayID,
        includeDuplicateLowResolutionModes: Bool = true
    ) -> [PhysicalDisplayMode] {
        // Dahili ekran koruması: Dahili ekrana asla mod analizi yapma
        guard CGDisplayIsBuiltin(displayID) == 0 else {
            return []
        }
        
        let options: CFDictionary? = includeDuplicateLowResolutionModes
            ? [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
            : nil
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return []
        }
        
        let source = includeDuplicateLowResolutionModes ? "duplicateLowResolutionModes" : "default"
        return modes.map { mode in
            let w = mode.width
            let h = mode.height
            let pw = mode.pixelWidth
            let ph = mode.pixelHeight
            let refresh = mode.refreshRate
            
            // Çözünürlük modunun encoding ve flag'lerini alma
            let encoding = (mode.pixelEncoding as String?) ?? "Unknown"
            let flags = mode.ioFlags
            
            // Eğer piksel boyutları mantıksal boyutlardan büyükse bu bir HiDPI modudur.
            let isHiDPI = pw > w || ph > h
            
            // Strong HiDPI: Piksel boyutları mantıksal boyutların tam 2 katı
            let isStrongHiDPI = pw == w * 2 && ph == h * 2
            
            // Perfect QHD HiDPI: 2560x1440 mantıksal çözünürlükte 5120x2880 piksel backing
            let isPerfectQHDHiDPI = w == 2560 && h == 1440 && pw == 5120 && ph == 2880
            
            let id = "\(w)x\(h)@\(Int(refresh))_\(pw)x\(ph)_\(isHiDPI ? "hidpi" : "normal")"
            return PhysicalDisplayMode(
                id: id,
                width: w,
                height: h,
                pixelWidth: pw,
                pixelHeight: ph,
                refreshRate: refresh,
                isHiDPI: isHiDPI,
                isStrongHiDPI: isStrongHiDPI,
                isPerfectQHDHiDPI: isPerfectQHDHiDPI,
                pixelEncoding: encoding,
                ioFlags: flags,
                modeSource: source,
                cgMode: mode
            )
        }.sorted { a, b in
            if a.width != b.width {
                return a.width > b.width
            }
            if a.isPerfectQHDHiDPI != b.isPerfectQHDHiDPI {
                return a.isPerfectQHDHiDPI && !b.isPerfectQHDHiDPI // En başta Perfect QHD HiDPI
            }
            if a.isHiDPI != b.isHiDPI {
                return a.isHiDPI && !b.isHiDPI // Sonra diğer HiDPI modları
            }
            return a.refreshRate > b.refreshRate
        }
    }

    public static func getDefaultModes(for displayID: CGDirectDisplayID) -> [PhysicalDisplayMode] {
        getAvailableModes(for: displayID, includeDuplicateLowResolutionModes: false)
    }

    public static func getHiDPIApplyCandidateModes(for displayID: CGDirectDisplayID) -> [PhysicalDisplayMode] {
        getAvailableModes(for: displayID, includeDuplicateLowResolutionModes: true)
    }

    public static func findPerfectQHDHiDPIMode(for displayID: CGDirectDisplayID) -> PhysicalDisplayMode? {
        getHiDPIApplyCandidateModes(for: displayID).first(where: isPerfectQHDHiDPIMode)
    }

    public static func isPerfectQHDHiDPIMode(_ mode: PhysicalDisplayMode) -> Bool {
        mode.width == HiDPIOverrideReferenceStore.targetLogicalWidth &&
            mode.height == HiDPIOverrideReferenceStore.targetLogicalHeight &&
            mode.pixelWidth == HiDPIOverrideReferenceStore.targetBackingWidth &&
            mode.pixelHeight == HiDPIOverrideReferenceStore.targetBackingHeight &&
            abs(mode.refreshRate - HiDPIOverrideReferenceStore.targetRefreshRate) < 0.1 &&
            mode.isHiDPI &&
            mode.isStrongHiDPI
    }

    public static func isSameModeFingerprint(_ lhs: PhysicalDisplayMode, _ rhs: PhysicalDisplayMode) -> Bool {
        lhs.width == rhs.width &&
            lhs.height == rhs.height &&
            lhs.pixelWidth == rhs.pixelWidth &&
            lhs.pixelHeight == rhs.pixelHeight &&
            abs(lhs.refreshRate - rhs.refreshRate) < 0.1 &&
            lhs.isHiDPI == rhs.isHiDPI &&
            lhs.isStrongHiDPI == rhs.isStrongHiDPI &&
            lhs.ioFlags == rhs.ioFlags
    }

    public static func aspectRatioString(width: Int, height: Int) -> String {
        guard width > 0 && height > 0 else { return "n/a" }
        let ratio = Double(width) / Double(height)
        return String(format: "%.4f", ratio)
    }

    public static func candidateReason(for mode: PhysicalDisplayMode) -> String {
        var reasons: [String] = []
        if mode.width == 2560 && mode.height == 1440 {
            reasons.append("logical-2560x1440")
        }
        if mode.pixelWidth == 5120 && mode.pixelHeight == 2880 {
            reasons.append("pixel-5120x2880")
        }
        if mode.isStrongHiDPI && mode.width * 9 == mode.height * 16 {
            reasons.append("strong-hidpi-16:9")
        }
        if mode.isHiDPI && abs(mode.refreshRate - 100.0) < 0.1 {
            reasons.append("100hz-hidpi")
        }
        if mode.isPerfectQHDHiDPI && abs(mode.refreshRate - 100.0) < 0.1 && mode.isStrongHiDPI {
            reasons.append("strict-perfect-qhd")
        } else if mode.isPerfectQHDHiDPI && mode.isStrongHiDPI {
            reasons.append("loose-perfect-qhd")
        }
        return reasons.isEmpty ? "none" : reasons.joined(separator: ",")
    }
}
