import Foundation

enum PowerSourceKind: String, Sendable {
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

enum BatteryPowerFlow: String, Sendable {
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

enum PowerTelemetryCoverage: String, Sendable {
    case detailed
    case derived
    case batteryOnly
    case unavailable

    var displayName: String {
        switch self {
        case .detailed: return "Detailed sensors"
        case .derived: return "Power balance"
        case .batteryOnly: return "Battery sensors"
        case .unavailable: return "Limited telemetry"
        }
    }
}

struct PowerHistoryPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let systemLoadWatts: Double?
    let adapterInputWatts: Double?
    let batteryFlowWatts: Double?
    let flow: BatteryPowerFlow

    init(
        id: UUID = UUID(),
        timestamp: Date,
        systemLoadWatts: Double?,
        adapterInputWatts: Double?,
        batteryFlowWatts: Double?,
        flow: BatteryPowerFlow
    ) {
        self.id = id
        self.timestamp = timestamp
        self.systemLoadWatts = systemLoadWatts
        self.adapterInputWatts = adapterInputWatts
        self.batteryFlowWatts = batteryFlowWatts
        self.flow = flow
    }
}

struct PowerSnapshot: Equatable, Sendable {
    let timestamp: Date
    let source: PowerSourceKind
    let batteryPercent: Int?
    let isCharging: Bool
    let isCharged: Bool
    let currentMilliAmps: Double?
    let voltageMilliVolts: Double?

    /// Signed battery-side power. Positive means energy is flowing into the
    /// battery, negative means the battery is supplying the Mac.
    let signedBatteryWatts: Double?

    /// Live external input measured by AppleSmartBattery PowerTelemetryData.
    /// This is the power entering the Mac from the attached power source, not
    /// the charger's advertised/rated capacity.
    let systemInputWatts: Double?

    /// Live system load reported directly by PowerTelemetryData when exposed by
    /// the current Mac/macOS combination.
    let measuredSystemLoadWatts: Double?

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
        signedBatteryWatts: nil,
        systemInputWatts: nil,
        measuredSystemLoadWatts: nil,
        adapterRatedWatts: nil,
        adapterCurrentMilliAmps: nil,
        timeToEmptyMinutes: nil,
        timeToFullMinutes: nil
    )

    var flow: BatteryPowerFlow {
        guard batteryPercent != nil else { return .unavailable }

        if let signedBatteryWatts {
            if signedBatteryWatts > 0.15 { return .charging }
            if signedBatteryWatts < -0.15 { return .discharging }
        }

        if source == .battery {
            return .discharging
        }
        if isCharging {
            return .charging
        }
        return .idle
    }

    /// Absolute battery-side power. Direction is available from signedBatteryWatts.
    var batteryFlowWatts: Double? {
        signedBatteryWatts.map(abs)
    }

    var batteryChargeWatts: Double? {
        guard let signedBatteryWatts else { return nil }
        return max(signedBatteryWatts, 0)
    }

    var batteryDischargeWatts: Double? {
        guard let signedBatteryWatts else { return nil }
        return max(-signedBatteryWatts, 0)
    }

    var adapterInputWatts: Double? {
        guard source == .ac || source == .ups else { return nil }
        return nonNegativeFinite(systemInputWatts)
    }

    /// Best available live Mac load.
    /// 1) direct PowerTelemetryData.SystemLoad
    /// 2) external input - signed battery flow
    /// 3) battery discharge power while unplugged
    var systemLoadWatts: Double? {
        if let measured = nonNegativeFinite(measuredSystemLoadWatts) {
            return measured
        }

        if let input = nonNegativeFinite(systemInputWatts) {
            let battery = signedBatteryWatts ?? 0
            let derived = input - battery
            if derived.isFinite, derived >= 0 {
                return derived
            }
        }

        if source == .battery, let discharge = batteryDischargeWatts, discharge.isFinite {
            return discharge
        }

        return nil
    }

    var observableWatts: Double? {
        systemLoadWatts
    }

    var observableMetricName: String {
        "Mac draw"
    }

    var telemetryCoverage: PowerTelemetryCoverage {
        if nonNegativeFinite(systemInputWatts) != nil,
           nonNegativeFinite(measuredSystemLoadWatts) != nil {
            return .detailed
        }
        if nonNegativeFinite(systemInputWatts) != nil {
            return .derived
        }
        if signedBatteryWatts != nil {
            return .batteryOnly
        }
        return .unavailable
    }

    var batteryPercentClamped: Int? {
        batteryPercent.map { min(max($0, 0), 100) }
    }

    static func signedWatts(currentMilliAmps: Double?, voltageMilliVolts: Double?) -> Double? {
        guard let currentMilliAmps, let voltageMilliVolts else { return nil }
        guard currentMilliAmps.isFinite, voltageMilliVolts.isFinite else { return nil }
        guard voltageMilliVolts > 0 else { return nil }

        let watts = currentMilliAmps * voltageMilliVolts / 1_000_000
        guard watts.isFinite else { return nil }
        return watts
    }

    static func watts(currentMilliAmps: Double?, voltageMilliVolts: Double?) -> Double? {
        signedWatts(currentMilliAmps: currentMilliAmps, voltageMilliVolts: voltageMilliVolts).map(abs)
    }

    private func nonNegativeFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
