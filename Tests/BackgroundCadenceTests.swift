import Foundation

@main
struct BackgroundCadenceTests {
    static func main() throws {
        let source = try String(contentsOfFile: "Services/MonitoringService.swift", encoding: .utf8)

        let storageInterval = try captureNumber(
            in: source,
            pattern: #"storageRefreshInterval:\s*TimeInterval\s*=\s*([0-9.]+)"#,
            name: "storageRefreshInterval"
        )
        let processInterval = try captureNumber(
            in: source,
            pattern: #"processRefreshInterval:\s*TimeInterval\s*=\s*([0-9.]+)"#,
            name: "processRefreshInterval"
        )
        let mainInterval = try captureNumber(
            in: source,
            pattern: #"scheduledTimer\(withTimeInterval:\s*([0-9.]+)"#,
            name: "main monitoring timer"
        )

        require(mainInterval >= 5, "Main background polling must not be faster than 5s")
        require(storageInterval >= 30, "Storage polling must not be faster than 30s")
        require(processInterval >= 30, "Process snapshot polling must not be faster than 30s")
        require(source.contains("powerHistoryLimit = 120"), "Power history must remain bounded")
        require(source.contains("systemHistoryLimit = 120"), "System history must remain bounded")

        let wakeupsPerMinute = 60.0 / mainInterval
        require(wakeupsPerMinute <= 12.0, "Background main timer exceeds 12 scheduled polls/minute")

        print("PASS Background cadence budget")
        print("  main: \(mainInterval)s (<= \(String(format: "%.1f", wakeupsPerMinute)) scheduled polls/min)")
        print("  storage: \(storageInterval)s")
        print("  processes: \(processInterval)s")
    }

    private static func captureNumber(in source: String, pattern: String, name: String) throws -> Double {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: source),
              let value = Double(source[captureRange]) else {
            throw NSError(
                domain: "MemWatch.BackgroundCadenceTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not read \(name)"]
            )
        }
        return value
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
