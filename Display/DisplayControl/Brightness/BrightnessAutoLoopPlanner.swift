import Foundation

struct BrightnessAutoLoopPreflightContext {
    let ambientLux: Double
    let target: Int
    let smoothedRequested: Int
    let currentActual: Int
    let now: Date
    let lastWriteDate: Date
    let minInterval: TimeInterval
    let updateThreshold: Int
    let currentDisplayKey: String
    let calibrationActive: Bool
    let appBrightnessSuppressedUntil: Date
    let ddcAvailable: Bool
    let brightnessLimiterCooldownDisplayKey: String?
    let brightnessLimiterCooldownUntil: Date
}

enum BrightnessAutoLoopPreflightDecision {
    case proceed(candidate: Int, statusText: String)
    case suppressed(
        reason: BrightnessSuppressionReason,
        source: BrightnessSource,
        statusText: String,
        diagnosis: String,
        reportSuppressionReason: String
    )
}

final class BrightnessAutoLoopPlanner {
    func preflight(context: BrightnessAutoLoopPreflightContext) -> BrightnessAutoLoopPreflightDecision {
        if context.calibrationActive {
            return .suppressed(
                reason: .autoDisabled,
                source: .suppressed,
                statusText: "auto disabled",
                diagnosis: "Auto brightness is disabled during screen calibration.",
                reportSuppressionReason: "Calibration active"
            )
        }

        if context.now < context.appBrightnessSuppressedUntil {
            return .suppressed(
                reason: .appInactiveOrSleepWake,
                source: .suppressed,
                statusText: "app inactive / sleep-wake suppression",
                diagnosis: "System is in sleep/wake transition or app is inactive.",
                reportSuppressionReason: "App inactive or sleep-wake suppression active"
            )
        }

        let threshold = max(1, context.updateThreshold)
        let targetDelta = abs(context.target - context.currentActual)
        if targetDelta < threshold {
            return .suppressed(
                reason: .targetEqualsActual,
                source: .ambientComputed,
                statusText: "target equals actual",
                diagnosis: "Difference between target and actual brightness is less than \(threshold)%. No adjustment needed.",
                reportSuppressionReason: "target equals actual (difference < \(threshold))"
            )
        }

        guard context.ddcAvailable else {
            return .suppressed(
                reason: .ddcUnavailable,
                source: .suppressed,
                statusText: "DDC unavailable",
                diagnosis: "m1ddc command-line utility could not be found or executed.",
                reportSuppressionReason: "DDC unavailable"
            )
        }

        guard context.now.timeIntervalSince(context.lastWriteDate) >= context.minInterval else {
            let remaining = Int(round(context.minInterval - context.now.timeIntervalSince(context.lastWriteDate)))
            return .suppressed(
                reason: .debounceWaiting,
                source: .ambientComputed,
                statusText: "debounce waiting (\(remaining)s)",
                diagnosis: "Waiting for min interval (\(String(format: "%.1f", context.minInterval))s) to elapse. Remaining: \(remaining)s.",
                reportSuppressionReason: "debounce waiting"
            )
        }

        if
            context.brightnessLimiterCooldownDisplayKey == context.currentDisplayKey,
            context.now < context.brightnessLimiterCooldownUntil
        {
            let remaining = Int(ceil(context.brightnessLimiterCooldownUntil.timeIntervalSince(context.now)))
            return .suppressed(
                reason: .monitorLimiterCooldown,
                source: .suppressed,
                statusText: "monitor limiter cooldown (\(remaining)s)",
                diagnosis: "Previous DDC write was accepted but monitor did not change brightness. Auto brightness is paused briefly to avoid visible pulsing.",
                reportSuppressionReason: "monitor limiter cooldown"
            )
        }

        let smoothedDelta = abs(context.smoothedRequested - context.currentActual)
        let candidate = smoothedDelta < threshold ? context.target : context.smoothedRequested
        return .proceed(
            candidate: candidate,
            statusText: String(format: "%.0f lux -> %%%d (Yazılıyor...)", context.ambientLux, candidate)
        )
    }
}
