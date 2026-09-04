import Foundation

@main
struct TemperatureValidatorTests {
    static func main() {
        testValidBoundaries()
        testInvalidValues()
        testExplicitDecoderOutcome()
        print("PASS Temperature validator")
    }

    private static func testValidBoundaries() {
        require(isValid(43.2), "Normal finite Celsius must be accepted")
        require(isValid(-40), "Lower broad range boundary must be accepted")
        require(isValid(125), "Upper broad range boundary must be accepted")
        require(isValid(0), "Zero Celsius must be accepted")
    }

    private static func testInvalidValues() {
        require(!isValid(.nan), "NaN must be rejected")
        require(!isValid(.infinity), "Positive infinity must be rejected")
        require(!isValid(-.infinity), "Negative infinity must be rejected")
        require(!isValid(180), "Values above the broad range must be rejected without clamping")
        require(!isValid(-127), "Decoder sentinel must be rejected")

        guard case let .invalidSample(reason) = TemperatureValidator.validate(180) else {
            fail("Out-of-range values must preserve an invalid sample outcome")
        }
        require(reason.contains("outside"), "Invalid range reason must remain actionable")
    }

    private static func testExplicitDecoderOutcome() {
        guard case let .invalidSample(reason) = TemperatureValidator.validate(.invalid(code: "sentinel")) else {
            fail("Explicit invalid decoder outcome must remain invalid")
        }
        require(reason == "sentinel", "Explicit decoder failure code must be preserved")

        guard case .invalidSample = TemperatureValidator.validate(Optional<Double>.none) else {
            fail("Missing raw outcome must not become zero")
        }
    }

    private static func isValid(_ value: Double) -> Bool {
        guard case .valid = TemperatureValidator.validate(value) else { return false }
        return true
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }
}
