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
            pattern: #"register\(id:\s*\"system-health\",\s*interval:\s*([0-9.]+)"#,
            name: "main monitoring timer"
        )
        let powerHistoryLimit = try captureNumber(
            in: source,
            pattern: #"powerHistoryLimit\s*=\s*([0-9.]+)"#,
            name: "powerHistoryLimit"
        )
        let systemHistoryLimit = try captureNumber(
            in: source,
            pattern: #"systemHistoryLimit\s*=\s*([0-9.]+)"#,
            name: "systemHistoryLimit"
        )

        require(source.contains("private let scheduler: PollingScheduler"), "Monitoring must use the shared polling scheduler")
        require(!source.contains("register(id: \"thermal-health\"")
            && !source.contains("register(id: \"thermal-refresh\"")
            && !source.contains("register(id: \"thermal-wake\"")
            && !source.contains("register(id: \"temperature\""),
                "Thermal collection must reuse the existing system-health scheduler")

        require(mainInterval >= 5, "Main background polling must not be faster than 5s")
        require(storageInterval >= 30, "Storage polling must not be faster than 30s")
        require(processInterval >= 30, "Process snapshot polling must not be faster than 30s")

        // Power history stores only a handful of Doubles plus timestamp/UUID per sample.
        // 360 samples is 30 minutes at the existing 5-second cadence and stays a small,
        // strictly bounded in-memory buffer without increasing wake-up frequency.
        require(powerHistoryLimit > 0 && powerHistoryLimit <= 360, "Power history must remain bounded to at most 360 samples")
        require(systemHistoryLimit > 0 && systemHistoryLimit <= 120, "System history must remain bounded to at most 120 samples")

        let wakeupsPerMinute = 60.0 / mainInterval
        require(wakeupsPerMinute <= 12.0, "Background main timer exceeds 12 scheduled polls/minute")

        print("PASS Background cadence budget")
        print("  main: \(mainInterval)s (<= \(String(format: "%.1f", wakeupsPerMinute)) scheduled polls/min)")
        print("  storage: \(storageInterval)s")
        print("  processes: \(processInterval)s")
        print("  power history: \(Int(powerHistoryLimit)) samples")
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
