import AppKit
import Foundation
import IOKit
import IOKit.pwr_mgt

public struct KeepAwakeState: Codable, Hashable {
    public var featureEnabled: Bool
    
    public var defaultIdleTimeoutMode: String // "15", "30", "60", "never", "custom"
    public var defaultIdleTimeoutMinutes: Int
    
    public var temporaryIdleTimeoutMode: String? // "15", "30", "60", "never", "custom"
    public var temporaryIdleTimeoutMinutes: Int?
    public var temporaryOverrideActive: Bool
    
    public var onlyWhilePluggedIn: Bool
    public var keepDisplayAwake: Bool
    
    public var idleSleepAssertionID: UInt32 = 0
    public var displaySleepAssertionID: UInt32 = 0
    public var lastWakeTriggerAt: Date?
    public var lastStopReason: String // "expired", "userStopped", "powerDisconnected", "appTerminated", "none"

    enum CodingKeys: String, CodingKey {
        case featureEnabled
        case defaultIdleTimeoutMode
        case defaultIdleTimeoutMinutes
        case temporaryIdleTimeoutMode
        case temporaryIdleTimeoutMinutes
        case temporaryOverrideActive
        case onlyWhilePluggedIn
        case keepDisplayAwake
        case lastWakeTriggerAt
        case lastStopReason
    }
}

final class KeepAwakeController {
    private(set) var idleSleepAssertionID: IOPMAssertionID = 0
    private(set) var displaySleepAssertionID: IOPMAssertionID = 0
    
    var isActive: Bool {
        idleSleepAssertionID != 0
    }
    
    var isDisplayActive: Bool {
        displaySleepAssertionID != 0
    }

    func syncAssertions(enabled: Bool, keepDisplayAwake: Bool) -> (Bool, String) {
        if enabled {
            var success = true
            var details = ""

            // 1. Idle Sleep Assertion (NoIdleSleep - Her durumda)
            if idleSleepAssertionID == 0 {
                var assertionID = IOPMAssertionID(0)
                let result = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "AmbientSync Keep System Awake" as CFString,
                    &assertionID
                )
                if result == kIOReturnSuccess {
                    idleSleepAssertionID = assertionID
                    details += "idle sleep active; "
                } else {
                    success = false
                    details += "idle sleep failed: \(result); "
                }
            }

            // 2. Display Sleep Assertion (NoDisplaySleep - Sadece keepDisplayAwake true ise)
            if keepDisplayAwake {
                if displaySleepAssertionID == 0 {
                    var assertionID = IOPMAssertionID(0)
                    let result = IOPMAssertionCreateWithName(
                        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                        "AmbientSync Keep Display Awake" as CFString,
                        &assertionID
                    )
                    if result == kIOReturnSuccess {
                        displaySleepAssertionID = assertionID
                        details += "display sleep active; "
                    } else {
                        success = false
                        details += "display sleep failed: \(result); "
                    }
                }
            } else {
                // keepDisplayAwake false ise kaldır
                releaseDisplaySleepAssertion()
                details += "display sleep inactive; "
            }

            return (success, details)
        } else {
            // Pasifse tümünü temizle
            releaseAllAssertions()
            return (true, "keep awake disabled")
        }
    }

    func releaseDisplaySleepAssertion() {
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
    }

    func releaseAllAssertions() {
        if idleSleepAssertionID != 0 {
            IOPMAssertionRelease(idleSleepAssertionID)
            idleSleepAssertionID = 0
        }
        releaseDisplaySleepAssertion()
    }

    func stop() {
        releaseAllAssertions()
    }
}
