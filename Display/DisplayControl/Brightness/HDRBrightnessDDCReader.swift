import Foundation

actor HDRBrightnessDDCReader {
    private let maxBrightness = 100
    private let targetMonitorNames = ["S60UD", "LS32D60", "LS32D60xU"]
    private let fallbackMonitorName = "Samsung"
    private let m1ddcCandidates = [
        "/opt/homebrew/bin/m1ddc",
        "/usr/local/bin/m1ddc",
    ]

    private struct DDCDisplayPartial {
        var displayIndex: String = ""
        var productName: String = ""
        var serial: String?
        var systemUUID: String?
        var ioLocation: String?
    }

    private struct DDCDisplayCandidate: Sendable {
        let displayIndex: String
        let productName: String
        let serial: String?
        let systemUUID: String?
        let ioLocation: String?

        var displayKey: String {
            let identity = (serial?.isEmpty == false ? serial : nil)
                ?? (systemUUID?.isEmpty == false ? systemUUID : nil)
                ?? displayIndex
            return "\(productName)|\(identity)"
        }

        var isLikelyInternal: Bool {
            let lowerName = productName.lowercased()
            let lowerLocation = ioLocation?.lowercased() ?? ""
            return lowerName.contains("built-in") || lowerName.contains("color lcd") || lowerLocation.contains("disp0")
        }
    }

    func collectResult(preferredDisplayKey: String? = nil) -> HDRBrightnessDDCResult {
        let candidate = discoverDDCTarget(preferredDisplayKey: preferredDisplayKey)
        guard let candidate else {
            return HDRBrightnessDDCResult(
                displayIndex: nil,
                currentBrightness: nil,
                testBrightness: nil,
                setSucceeded: nil,
                readbackBrightness: nil,
                readbackChanged: nil,
                readAvailable: false,
                maxBrightness: maxBrightness,
                notes: ["DDC target display not found"]
            )
        }

        let currentBrightness = readBrightness(displayIndex: candidate.displayIndex)
        guard let currentBrightness else {
            return HDRBrightnessDDCResult(
                displayIndex: candidate.displayIndex,
                currentBrightness: nil,
                testBrightness: nil,
                setSucceeded: nil,
                readbackBrightness: nil,
                readbackChanged: nil,
                readAvailable: false,
                maxBrightness: maxBrightness,
                notes: ["DDC brightness read unavailable"]
            )
        }

        let testBrightness = Self.pickTestBrightness(from: currentBrightness)
        let setSucceeded = setBrightness(testBrightness, displayIndex: candidate.displayIndex)
        var readbackBrightness: Int?
        var readbackChanged: Bool?
        var notes: [String] = []

        if setSucceeded {
            readbackBrightness = readBrightness(displayIndex: candidate.displayIndex)
            if let readbackBrightness {
                readbackChanged = abs(readbackBrightness - currentBrightness) > 1
            }
            if !setBrightness(currentBrightness, displayIndex: candidate.displayIndex) {
                notes.append("Failed to restore the original brightness after the diagnostic test")
            }
        }

        return HDRBrightnessDDCResult(
            displayIndex: candidate.displayIndex,
            currentBrightness: currentBrightness,
            testBrightness: testBrightness,
            setSucceeded: setSucceeded,
            readbackBrightness: readbackBrightness,
            readbackChanged: readbackChanged,
            readAvailable: true,
            maxBrightness: maxBrightness,
            notes: notes
        )
    }

    private func discoverDDCTarget(preferredDisplayKey: String?) -> DDCDisplayCandidate? {
        let candidates = discoverDDCDisplays()
        if let preferredDisplayKey, let match = candidates.first(where: { $0.displayKey == preferredDisplayKey }) {
            return match
        }

        if let strict = candidates.first(where: { candidate in
            targetMonitorNames.contains { candidate.productName.localizedCaseInsensitiveContains($0) }
        }) {
            return strict
        }

        return candidates.first(where: { $0.productName.localizedCaseInsensitiveContains(fallbackMonitorName) })
    }

    private func discoverDDCDisplays() -> [DDCDisplayCandidate] {
        guard let output = runProcess(executable: m1ddcExecutableURL()?.path ?? "", arguments: ["display", "list", "detailed"]) else {
            return []
        }

        func normalized(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "(null)" else { return nil }
            return trimmed
        }

        var result: [DDCDisplayCandidate] = []
        var current: DDCDisplayPartial?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") {
                appendCurrent(current, into: &result)
                current = DDCDisplayPartial()
                if let endIndex = line.firstIndex(of: "]") {
                    let index = line[line.index(after: line.startIndex)..<endIndex].trimmingCharacters(in: .whitespaces)
                    current?.displayIndex = String(index)
                }
                continue
            }

            guard var partial = current else { continue }
            if line.hasPrefix("- Product name:") {
                partial.productName = line.replacingOccurrences(of: "- Product name:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- Serial:") {
                partial.serial = normalized(line.replacingOccurrences(of: "- Serial:", with: "").trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("- System UUID:") {
                partial.systemUUID = normalized(line.replacingOccurrences(of: "- System UUID:", with: "").trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("- IO Location:") {
                partial.ioLocation = normalized(line.replacingOccurrences(of: "- IO Location:", with: "").trimmingCharacters(in: .whitespaces))
            }
            current = partial
        }

        appendCurrent(current, into: &result)
        return result
    }

    private func appendCurrent(_ partial: DDCDisplayPartial?, into result: inout [DDCDisplayCandidate]) {
        guard let partial else { return }
        guard !partial.displayIndex.isEmpty, !partial.productName.isEmpty else { return }
        let candidate = DDCDisplayCandidate(
            displayIndex: partial.displayIndex,
            productName: partial.productName,
            serial: partial.serial,
            systemUUID: partial.systemUUID,
            ioLocation: partial.ioLocation
        )
        guard !candidate.isLikelyInternal else { return }
        result.append(candidate)
    }

    private func readBrightness(displayIndex: String) -> Int? {
        guard let executable = m1ddcExecutableURL() else { return nil }
        guard let output = runProcess(executable: executable.path, arguments: ["display", displayIndex, "get", "luminance"]) else { return nil }
        return Self.parsePercent(from: output)
    }

    private func setBrightness(_ percent: Int, displayIndex: String) -> Bool {
        guard let executable = m1ddcExecutableURL() else { return false }
        guard let output = runProcess(executable: executable.path, arguments: ["display", displayIndex, "set", "luminance", "\(min(100, max(0, percent)))"]) else { return false }
        return !output.localizedCaseInsensitiveContains("failed")
    }

    private static func pickTestBrightness(from current: Int) -> Int {
        if current >= 90 { return max(1, current - 10) }
        return min(100, current + 10)
    }

    private func m1ddcExecutableURL() -> URL? {
        m1ddcCandidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func runProcess(executable: String, arguments: [String]) -> String? {
        guard !executable.isEmpty else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func parsePercent(from output: String) -> Int? {
        let lines = output.lowercased().split(whereSeparator: \.isNewline)
        for line in lines {
            let lineStr = String(line)
            let patterns = [
                #"\bcurrent\b\s*[:=]?\s*(\d+)"#,
                #"\bluminance\b\s*[:=]?\s*(\d+)"#,
                #"(\d+)%"#
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: lineStr, options: [], range: NSRange(lineStr.startIndex..., in: lineStr)) {
                    let valueRange = match.range(at: match.numberOfRanges > 1 ? 1 : 0)
                    if let range = Range(valueRange, in: lineStr) {
                        let digits = lineStr[range].filter { $0.isNumber }
                        if let value = Int(digits), (0...100).contains(value) {
                            return value
                        }
                    }
                }
            }
        }
        return nil
    }
}
