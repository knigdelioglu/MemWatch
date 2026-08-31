import Foundation

final class BrightnessAutoController {
    let relativeLuxThreshold: Double
    let absoluteLuxThreshold: Double
    let darkAbsoluteLuxThreshold: Double
    let darkLuxLimit: Double

    init(
        relativeLuxThreshold: Double = 0.25,
        absoluteLuxThreshold: Double = 80.0,
        darkAbsoluteLuxThreshold: Double = 25.0,
        darkLuxLimit: Double = 100.0
    ) {
        self.relativeLuxThreshold = relativeLuxThreshold
        self.absoluteLuxThreshold = absoluteLuxThreshold
        self.darkAbsoluteLuxThreshold = darkAbsoluteLuxThreshold
        self.darkLuxLimit = darkLuxLimit
    }

    func smoothedRequestedPercent(
        target: Int,
        reference: Int,
        smoothing: Double
    ) -> Int {
        let diff = Double(target - reference)
        let step = diff * smoothing
        let smoothedVal = Double(reference) + step
        var result = Int(round(smoothedVal))

        if target != reference && result == reference {
            result += target > reference ? 1 : -1
        }

        return min(100, max(0, result))
    }

    func shouldContinueManualOverride(
        currentLux: Double,
        startLux: Double?,
        overrideUntil: Date,
        now: Date = Date()
    ) -> Bool {
        guard let startLux else {
            return now < overrideUntil
        }

        let absoluteChange = abs(currentLux - startLux)
        let relativeDenominator = max(abs(startLux), 1.0)
        let relativeChange = absoluteChange / relativeDenominator
        let absoluteThreshold = startLux < darkLuxLimit
            ? darkAbsoluteLuxThreshold
            : absoluteLuxThreshold

        return relativeChange < relativeLuxThreshold && absoluteChange < absoluteThreshold
    }
}
