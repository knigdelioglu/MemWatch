import Foundation

struct DDCBrightnessRawSample: Sendable {
    let rawCurrent: Int?
    let rawMax: Int?
    let available: Bool
    let output: String
}

enum DDCBrightnessParsing {
    static func parseRawSample(from output: String) -> DDCBrightnessRawSample {
        let normalized = output.lowercased()
        let lines = normalized.split(whereSeparator: \.isNewline).map(String.init)

        var rawCurrent: Int?
        var rawMax: Int?

        for line in lines {
            if rawCurrent == nil {
                rawCurrent = firstInt(
                    in: line,
                    patterns: [
                        #"\bcurrent\b\D*(\d+)"#,
                        #"\bluminance\b\D*(\d+)"#,
                        #"\bbrightness\b\D*(\d+)"#,
                        #"\bvalue\b\D*(\d+)"#,
                    ]
                )
            }

            if rawMax == nil {
                rawMax = firstInt(
                    in: line,
                    patterns: [
                        #"\bmax(?:imum)?\b\D*(\d+)"#,
                        #"\bmaximum\b\D*(\d+)"#,
                    ]
                )
            }

            if rawCurrent == nil || rawMax == nil {
                let compactNumbers = line.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                if compactNumbers.count >= 2 {
                    if rawCurrent == nil { rawCurrent = Int(compactNumbers[0]) }
                    if rawMax == nil { rawMax = Int(compactNumbers[1]) }
                } else if compactNumbers.count == 1 {
                    if rawCurrent == nil { rawCurrent = Int(compactNumbers[0]) }
                }
            }

            if rawCurrent != nil && rawMax != nil {
                break
            }
        }

        return DDCBrightnessRawSample(
            rawCurrent: rawCurrent,
            rawMax: rawMax,
            available: rawCurrent != nil || rawMax != nil,
            output: output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func parseSingleRawValue(from output: String) -> Int? {
        let sample = parseRawSample(from: output)
        return sample.rawCurrent ?? sample.rawMax
    }

    private static func firstInt(in line: String, patterns: [String]) -> Int? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range) else { continue }
            let valueRange = match.range(at: match.numberOfRanges > 1 ? 1 : 0)
            if let valueStringRange = Range(valueRange, in: line) {
                let digits = line[valueStringRange].filter(\.isNumber)
                if let value = Int(digits) {
                    return value
                }
            }
        }
        return nil
    }
}
