import CoreGraphics
import Foundation

public struct TargetDisplaySpec: Equatable, Sendable {
    public let vendorID: UInt32
    public let productID: UInt32
    public let name: String
    
    public static let samsungQHD = TargetDisplaySpec(
        vendorID: 0x4C2D,
        productID: 0x76AB,
        name: "Samsung S60UD QHD"
    )
}

public struct TargetDisplayInfo: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let vendorID: UInt32
    public let productID: UInt32
    public let serialNumber: UInt32?
    public let displayName: String
    public let isBuiltin: Bool
    public let isOnline: Bool
    public let isActive: Bool
    public let nativeWidth: Int
    public let nativeHeight: Int
    public var hasReadableSerialNumber: Bool { serialNumber != nil }
}

public final class HiDPITargetDisplayResolver {
    
    public static func resolveSamsungS60UD() throws -> TargetDisplayInfo {
        let targets = try resolveTargets(spec: .samsungQHD, allowUnreadableSerial: false)
        guard let firstTarget = targets.first else {
            throw NSError(domain: "HiDPITargetDisplayResolver", code: 404, userInfo: [NSLocalizedDescriptionKey: "Hedef Samsung S60UD ekranı bulunamadı."])
        }
        return firstTarget
    }
    
    public static func resolveSamsungS60UDForDiagnostics() throws -> TargetDisplayInfo {
        let targets = try resolveTargets(spec: .samsungQHD, allowUnreadableSerial: true)
        guard let firstTarget = targets.first else {
            throw NSError(domain: "HiDPITargetDisplayResolver", code: 404, userInfo: [NSLocalizedDescriptionKey: "Hedef Samsung S60UD ekranı bulunamadı."])
        }
        return firstTarget
    }
    
    public static func resolveTargets(spec: TargetDisplaySpec, allowUnreadableSerial: Bool = false) throws -> [TargetDisplayInfo] {
        let maxDisplays: UInt32 = 16
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        
        guard CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount) == .success else {
            throw NSError(domain: "HiDPITargetDisplayResolver", code: 500, userInfo: [NSLocalizedDescriptionKey: "Aktif ekran listesi alınamadı."])
        }
        
        var matchedTargets: [TargetDisplayInfo] = []
        
        for i in 0..<Int(displayCount) {
            let displayID = activeDisplays[i]
            
            // Dahili ekran koruması: Asla işlem yapma ve listeleme
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            guard !isBuiltin else { continue }
            
            let vendorID = CGDisplayVendorNumber(displayID)
            let productID = CGDisplayModelNumber(displayID)
            
            if vendorID == spec.vendorID && productID == spec.productID {
                let serialValue = CGDisplaySerialNumber(displayID)
                let serial = serialValue == 0 ? nil : serialValue
                guard allowUnreadableSerial || serial != nil else {
                    continue
                }
                let isOnline = CGDisplayIsOnline(displayID) != 0
                let isActive = CGDisplayIsActive(displayID) != 0
                
                // Ekranın en yüksek native modunun boyutlarını bulalım
                let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] ?? []
                let maxMode = modes.max { a, b in
                    a.width < b.width
                }
                
                let nativeW = maxMode?.width ?? 0
                let nativeH = maxMode?.height ?? 0
                
                matchedTargets.append(TargetDisplayInfo(
                    displayID: displayID,
                    vendorID: vendorID,
                    productID: productID,
                    serialNumber: serial,
                    displayName: spec.name,
                    isBuiltin: false,
                    isOnline: isOnline,
                    isActive: isActive,
                    nativeWidth: nativeW,
                    nativeHeight: nativeH
                ))
            }
        }
        
        return matchedTargets
    }
}
