import Foundation

enum DDCBrightnessScale {
    static func rawTarget(forUIPercent uiPercent: Int, rawMax: Int) -> Int {
        guard rawMax > 0 else { return 0 }
        let clamped = min(100, max(0, uiPercent))
        let target = Double(clamped) / 100.0 * Double(rawMax)
        return min(rawMax, max(0, Int(target.rounded())))
    }

    static func uiPercent(fromRawCurrent rawCurrent: Int, rawMax: Int) -> Int {
        guard rawMax > 0 else { return 0 }
        let percent = Double(rawCurrent) / Double(rawMax) * 100.0
        return min(100, max(0, Int(percent.rounded())))
    }

    static func isMatched(rawAfter: Int?, computedRawTarget: Int?, tolerance: Int = 2) -> Bool {
        guard let rawAfter, let computedRawTarget else { return false }
        return abs(rawAfter - computedRawTarget) <= tolerance
    }
}
