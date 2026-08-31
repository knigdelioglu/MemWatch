import Foundation
import IOKit.ps

struct PowerSourceReading {
    let source: PowerSourceKind
    let batteryDescription: NSDictionary?
}

/// Shared low-level power-source snapshot for System Health and Display
/// keep-awake policy. Callers keep their own domain-specific interpretation.
struct PowerSourceReader {
    func read() -> PowerSourceReading {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let providingType = IOPSGetProvidingPowerSourceType(info).takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as NSArray

        var batteryDescription: NSDictionary?
        for item in sources {
            guard let description = IOPSGetPowerSourceDescription(info, item as CFTypeRef)?.takeUnretainedValue() else {
                continue
            }

            let dictionary = description as NSDictionary
            let type = dictionary.object(forKey: kIOPSTypeKey) as? String
            let transport = dictionary.object(forKey: kIOPSTransportTypeKey) as? String

            if type == kIOPSInternalBatteryType || transport == kIOPSInternalType {
                batteryDescription = NSDictionary(dictionary: dictionary)
                break
            }
        }

        let source = sourceKind(from: providingType, batteryDescription: batteryDescription)
        return PowerSourceReading(source: source, batteryDescription: batteryDescription)
    }

    private func sourceKind(
        from providingType: CFTypeRef,
        batteryDescription: NSDictionary?
    ) -> PowerSourceKind {
        if CFGetTypeID(providingType) == CFStringGetTypeID(),
           CFEqual(providingType, kIOPMACPowerKey as CFString) {
            return .ac
        }
        if CFGetTypeID(providingType) == CFStringGetTypeID(),
           CFEqual(providingType, kIOPMBatteryPowerKey as CFString) {
            return .battery
        }

        guard let state = batteryDescription?.object(forKey: kIOPSPowerSourceStateKey) as? String else {
            return .unknown
        }
        if state == kIOPSACPowerValue {
            return .ac
        }
        if state == kIOPSBatteryPowerValue {
            return .battery
        }
        return .unknown
    }
}
