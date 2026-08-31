import Foundation
import CoreGraphics

#if DEBUG
let EXPERIMENTAL_PRIVATE_HIDPI = true
#else
let EXPERIMENTAL_PRIVATE_HIDPI = false
#endif

/// Safety guards for the private HiDPI activation experiments.
/// Ensures we only ever run this on the target Samsung monitor.
@MainActor
class HiDPIPrivateActivationSafety {
    static let shared = HiDPIPrivateActivationSafety()
    
    let targetVendorID: UInt32 = 0x4C2D
    let targetProductID: UInt32 = 0x76AB
    let targetSerialNumber: UInt32 = 0x30413332
    
    private init() {}
    
    /// Checks if a given display ID matches the strict fingerprint of the target Samsung monitor.
    func isTargetSamsungMonitor(displayID: CGDirectDisplayID) -> Bool {
        let vendor = CGDisplayVendorNumber(displayID)
        let product = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        
        return vendor == targetVendorID && product == targetProductID && serial == targetSerialNumber
    }
    
    /// Checks if a display is a built-in display.
    func isBuiltInDisplay(displayID: CGDirectDisplayID) -> Bool {
        return CGDisplayIsBuiltin(displayID) != 0
    }
    
    /// Ensures we are targeting the Samsung monitor and it's not the built-in screen.
    func validateTargetDisplay(displayID: CGDirectDisplayID) -> Bool {
        if isBuiltInDisplay(displayID: displayID) {
            print("Safety Guard Failed: Target is a built-in display.")
            return false
        }
        
        if !isTargetSamsungMonitor(displayID: displayID) {
            print("Safety Guard Failed: Fingerprint mismatch (Vendor: \(CGDisplayVendorNumber(displayID)), Product: \(CGDisplayModelNumber(displayID)), Serial: \(CGDisplaySerialNumber(displayID))).")
            return false
        }
        
        return true
    }
    
    /// Validates if the current environment allows running private experiments.
    func isExperimentAllowed() -> Bool {
        return EXPERIMENTAL_PRIVATE_HIDPI
    }
}
