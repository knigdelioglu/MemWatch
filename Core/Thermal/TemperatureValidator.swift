import Foundation

enum TemperatureRawOutcome: Sendable, Equatable {
    case value(Double)
    case invalid(code: String?)
}

struct TemperatureValidator: Sendable {
    static let broadPhysicalRange = -40.0...125.0

    /// Common transport/decoder sentinels. Zero is intentionally absent: 0 °C
    /// is a valid physical temperature.
    static let decoderSentinelValues: Set<Double> = [
        -999,
        -128,
        -127,
        255,
        65_535
    ]

    private init() {}

    static func validate(
        _ celsius: Double,
        sentinelValues: Set<Double> = decoderSentinelValues
    ) -> TemperatureSample {
        guard celsius.isFinite else {
            return .invalidSample(reason: "non-finite temperature")
        }

        guard !sentinelValues.contains(celsius) else {
            return .invalidSample(reason: "decoder sentinel temperature")
        }

        guard broadPhysicalRange.contains(celsius) else {
            return .invalidSample(reason: "temperature outside broad physical range")
        }

        return .valid(celsius: celsius)
    }

    static func validate(_ rawOutcome: TemperatureRawOutcome) -> TemperatureSample {
        switch rawOutcome {
        case let .value(celsius):
            return validate(celsius)
        case let .invalid(code):
            return .invalidSample(reason: code ?? "decoder marked temperature invalid")
        }
    }

    static func validate(_ celsius: Double?) -> TemperatureSample {
        guard let celsius else {
            return .invalidSample(reason: "missing temperature")
        }
        return validate(celsius)
    }

    static func isValid(_ celsius: Double) -> Bool {
        guard case .valid = validate(celsius) else { return false }
        return true
    }
}
