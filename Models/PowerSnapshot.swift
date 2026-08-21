import Foundation

enum PowerSourceKind: String {
    case ac
    case battery
    case ups
    case unknown

    var displayName: String {
        switch self {
        case .ac: return "Power Adapter"
        case .battery: return "Battery"
        case .ups: return "UPS"
        case .unknown: return "Unknown"
        }
    }
}

enum BatteryPowerFlow: String {
    case charging
    case discharging
    case idle
    case unavailable

    var displayName: String {
        switch self {
        case .charging: return "Charging"
        case .discharging: return "Discharging"
        case .idle: return "Battery Idle"
        case .unavailable: return "Unavailable"
        }
    }
}

struct PowerHistoryPoint: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let watts: Double
    let flow: BatteryPowerFlow

    init(
        id: UUID = UUID(),
        timestamp: Date,
        watts: Double,
        flow: BatteryPowerFlow
    ) {
        self.id = id
        self.timestamp = timestamp
        self.watts = watts
        self.flow = flow
    }
}

struct PowerSnapshot: Equatable {
    let timestamp: Date
    let source: PowerSourceKind
    let batteryPercent: Int?
    let isCharging: Bool
    let isCharged: Bool
    let currentMilliAmps: Double?
    let voltageMilliVolts: Double?
    let batteryFlowWatts: Double?
    let adapterRatedWatts: Double?
    let adapterCurrentMilliAmps: Double?
    let timeToEmptyMinutes: Int?
    let timeToFullMinutes: Int?

    static let empty = PowerSnapshot(
        timestamp: .distantPast,
        source: .unknown,
        batteryPercent: nil,
        isCharging: false,
        isCharged: false,
        currentMilliAmps: nil,
        voltageMilliVolts: nil,
        batteryFlowWatts: nil,
        adapterRatedWatts: nil,
        adapterCurrentMilliAmps: nil,
        timeToEmptyMinutes: nil,
        timeToFullMinutes: nil
    )

    var flow: BatteryPowerFlow {
        guard batteryPercent != nil else { return .unavailable }

        if source == .battery {
            return .discharging
        }

        if isCharging {
            return .charging
        }

        return .idle
    }

    /// A public-API-backed live power number that MemWatch can state without
    /// pretending the adapter's rated wattage is instantaneous wall draw.
    /// On battery this approximates total Mac draw from the battery. On AC it
    /// represents battery charging power only when the battery is charging.
    var observableWatts: Double? {
        switch flow {
        case .charging, .discharging:
            return batteryFlowWatts
        case .idle:
            return 0
        case .unavailable:
            return nil
        }
    }

    var observableMetricName: String {
        switch flow {
        case .charging: return "Battery charge"
        case .discharging: return "Mac draw"
        case .idle: return "Battery flow"
        case .unavailable: return "Power"
        }
    }

    var batteryPercentClamped: Int? {
        batteryPercent.map { min(max($0, 0), 100) }
    }

    static func watts(currentMilliAmps: Double?, voltageMilliVolts: Double?) -> Double? {
        guard let currentMilliAmps, let voltageMilliVolts else { return nil }
        guard currentMilliAmps.isFinite, voltageMilliVolts.isFinite else { return nil }
        guard voltageMilliVolts > 0 else { return nil }

        let watts = abs(currentMilliAmps) * voltageMilliVolts / 1_000_000
        guard watts.isFinite else { return nil }
        return watts
    }
}
