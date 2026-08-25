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

        let registry = readAppleSmartBatteryTelemetry()
        let currentMilliAmps = registry.currentMilliAmps
            ?? signedNumber(batteryDescription?.object(forKey: kIOPSCurrentKey))
        let voltageMilliVolts = registry.voltageMilliVolts
            ?? number(batteryDescription, key: kIOPSVoltageKey)

        let signedBatteryWatts = PowerSnapshot.signedWatts(
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
            signedBatteryWatts: signedBatteryWatts,
            systemInputWatts: registry.systemInputWatts,
            measuredSystemLoadWatts: registry.systemLoadWatts,
            adapterRatedWatts: adapter.ratedWatts ?? registry.adapterRatedWatts,
            adapterCurrentMilliAmps: adapter.currentMilliAmps ?? registry.adapterCurrentMilliAmps,
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

    /// Reads AppleSmartBattery in one registry pass. Newer Apple Silicon Macs
    /// expose PowerTelemetryData with SystemPowerIn and SystemLoad in mW. Those
    /// values let MemWatch distinguish external input, Mac load, and battery flow
    /// instead of presenting the charger's rated wattage as live consumption.
    private func readAppleSmartBatteryTelemetry() -> RegistryTelemetry {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return .empty
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return .empty
        }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )

        guard result == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any] else {
            return .empty
        }

        let powerTelemetry = properties["PowerTelemetryData"] as? [String: Any]
        let instantCurrent = signedNumber(properties["InstantAmperage"])
        let averageCurrent = signedNumber(properties["Amperage"])
        let voltage = number(properties["Voltage"])

        let rawAdapter = firstAdapterDictionary(in: properties)

        return RegistryTelemetry(
            currentMilliAmps: instantCurrent ?? averageCurrent,
            voltageMilliVolts: voltage,
            systemInputWatts: wattsFromMilliwatts(number(powerTelemetry?["SystemPowerIn"])),
            systemLoadWatts: wattsFromMilliwatts(number(powerTelemetry?["SystemLoad"])),
            adapterRatedWatts: number(rawAdapter?["Watts"]),
            adapterCurrentMilliAmps: number(rawAdapter?["Current"])
        )
    }

    private func firstAdapterDictionary(in properties: [String: Any]) -> [String: Any]? {
        if let adapters = properties["AppleRawAdapterDetails"] as? [[String: Any]],
           let first = adapters.first {
            return first
        }

        if let adapter = properties["AdapterDetails"] as? [String: Any] {
            return adapter
        }

        return nil
    }

    private func wattsFromMilliwatts(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value < 1_000_000 else {
            return nil
        }
        return value / 1_000
    }

    private func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber else { return nil }
        let result = value.doubleValue
        return result.isFinite ? result : nil
    }

    /// AppleSmartBattery may surface negative current through an unsigned-looking
    /// CFNumber. int64Value preserves the two's-complement direction.
    private func signedNumber(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber else { return nil }
        return Double(value.int64Value)
    }

    private func number(_ dictionary: NSDictionary?, key: Any) -> Double? {
        number(dictionary?.object(forKey: key))
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

private struct RegistryTelemetry {
    let currentMilliAmps: Double?
    let voltageMilliVolts: Double?
    let systemInputWatts: Double?
    let systemLoadWatts: Double?
    let adapterRatedWatts: Double?
    let adapterCurrentMilliAmps: Double?

    static let empty = RegistryTelemetry(
        currentMilliAmps: nil,
        voltageMilliVolts: nil,
        systemInputWatts: nil,
        systemLoadWatts: nil,
        adapterRatedWatts: nil,
        adapterCurrentMilliAmps: nil
    )
}
