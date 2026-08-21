import Foundation
import IOKit
import IOKit.ps

struct PowerCollector {
    func collect() -> PowerSnapshot {
        let now = Date()
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
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
                batteryDescription = dictionary
                break
            }
        }

        let source = powerSource(from: batteryDescription)
        let isCharging = bool(batteryDescription, key: kIOPSIsChargingKey) ?? false
        let isCharged = bool(batteryDescription, key: kIOPSIsChargedKey) ?? false

        let currentCapacity = number(batteryDescription, key: kIOPSCurrentCapacityKey)
        let maxCapacity = number(batteryDescription, key: kIOPSMaxCapacityKey)
        let batteryPercent = percent(current: currentCapacity, max: maxCapacity)

        let registryTelemetry = readAppleSmartBatteryTelemetry()
        let currentMilliAmps = number(batteryDescription, key: kIOPSCurrentKey) ?? registryTelemetry.currentMilliAmps
        let voltageMilliVolts = number(batteryDescription, key: kIOPSVoltageKey) ?? registryTelemetry.voltageMilliVolts
        let flowWatts = PowerSnapshot.watts(
            currentMilliAmps: currentMilliAmps,
            voltageMilliVolts: voltageMilliVolts
        )

        let adapter = readAdapterDetails()

        return PowerSnapshot(
            timestamp: now,
            source: source,
            batteryPercent: batteryPercent,
            isCharging: isCharging,
            isCharged: isCharged,
            currentMilliAmps: currentMilliAmps,
            voltageMilliVolts: voltageMilliVolts,
            batteryFlowWatts: flowWatts,
            adapterRatedWatts: adapter.ratedWatts,
            adapterCurrentMilliAmps: adapter.currentMilliAmps,
            timeToEmptyMinutes: positiveMinutes(batteryDescription, key: kIOPSTimeToEmptyKey),
            timeToFullMinutes: positiveMinutes(batteryDescription, key: kIOPSTimeToFullChargeKey)
        )
    }

    private func powerSource(from battery: NSDictionary?) -> PowerSourceKind {
        guard let state = battery?.object(forKey: kIOPSPowerSourceStateKey) as? String else {
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

    private func readAdapterDetails() -> (ratedWatts: Double?, currentMilliAmps: Double?) {
        guard let unmanaged = IOPSCopyExternalPowerAdapterDetails() else {
            return (nil, nil)
        }

        let details = unmanaged.takeRetainedValue() as NSDictionary
        return (
            number(details, key: kIOPSPowerAdapterWattsKey),
            number(details, key: kIOPSPowerAdapterCurrentKey)
        )
    }

    /// IOPowerSources does not expose current/voltage on every Mac/OS build.
    /// AppleSmartBattery is used only as a telemetry fallback; all access still
    /// goes through public IORegistry APIs and failure simply yields nil values.
    private func readAppleSmartBatteryTelemetry() -> (currentMilliAmps: Double?, voltageMilliVolts: Double?) {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return (nil, nil)
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return (nil, nil)
        }
        defer { IOObjectRelease(service) }

        let instantCurrent = registryNumber(service, key: "InstantAmperage")
        let current = instantCurrent ?? registryNumber(service, key: "Amperage")
        let voltage = registryNumber(service, key: "Voltage")
        return (current, voltage)
    }

    private func registryNumber(_ service: io_service_t, key: String) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else {
            return nil
        }

        return value.doubleValue
    }

    private func number(_ dictionary: NSDictionary?, key: Any) -> Double? {
        (dictionary?.object(forKey: key) as? NSNumber)?.doubleValue
    }

    private func bool(_ dictionary: NSDictionary?, key: Any) -> Bool? {
        (dictionary?.object(forKey: key) as? NSNumber)?.boolValue
    }

    private func positiveMinutes(_ dictionary: NSDictionary?, key: Any) -> Int? {
        guard let value = dictionary?.object(forKey: key) as? NSNumber else { return nil }
        let minutes = value.intValue
        return minutes > 0 ? minutes : nil
    }

    private func percent(current: Double?, max: Double?) -> Int? {
        guard let current, let max, max > 0 else { return nil }
        let value = Int((current / max * 100).rounded())
        return min(maximum(value, 0), 100)
    }

    private func maximum(_ lhs: Int, _ rhs: Int) -> Int {
        lhs > rhs ? lhs : rhs
    }
}
