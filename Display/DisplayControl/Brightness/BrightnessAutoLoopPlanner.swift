import Foundation

struct BrightnessAutoLoopPreflightContext {
    let ambientLux: Double
    let target: Int
    let smoothedRequested: Int
    let currentActual: Int
    let hasAuthoritativeActual: Bool
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
    let forceTransitionReapply: Bool
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

enum BrightnessTransitionReapplyPolicy {
    static func isEligible(
        pending: Bool,
        autoBrightnessEnabled: Bool,
        calibrationActive: Bool,
        manualInteractionActive: Bool,
        pendingManualIntent: Bool,
        manualOverrideActive: Bool
    ) -> Bool {
        pending
            && autoBrightnessEnabled
            && !calibrationActive
            && !manualInteractionActive
            && !pendingManualIntent
            && !manualOverrideActive
    }
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
        if !context.forceTransitionReapply,
           context.hasAuthoritativeActual,
           targetDelta < threshold {
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

        guard context.forceTransitionReapply
            || context.now.timeIntervalSince(context.lastWriteDate) >= context.minInterval else {
            let remaining = Int(round(context.minInterval - context.now.timeIntervalSince(context.lastWriteDate)))
            return .suppressed(
                reason: .debounceWaiting,
                source: .ambientComputed,
                statusText: "debounce waiting (\(remaining)s)",
                diagnosis: "Waiting for min interval (\(String(format: "%.1f", context.minInterval))s) to elapse. Remaining: \(remaining)s.",
                reportSuppressionReason: "debounce waiting"
            )
        }

        if context.brightnessLimiterCooldownDisplayKey == context.currentDisplayKey,
            context.now < context.brightnessLimiterCooldownUntil
        {
            let remaining = Int(ceil(context.brightnessLimiterCooldownUntil.timeIntervalSince(context.now)))
            return .suppressed(
                reason: .monitorLimiterCooldown,
                source: .suppressed,
                statusText: "monitor limiter cooldown (\(remaining)s)",
                diagnosis: "Repeated stable DDC mismatches indicate a monitor-side brightness limiter. Auto brightness is paused briefly to avoid visible pulsing.",
                reportSuppressionReason: "monitor limiter cooldown"
            )
        }

        let smoothedDelta = abs(context.smoothedRequested - context.currentActual)
        let candidate = context.forceTransitionReapply
            ? context.target
            : (smoothedDelta < threshold ? context.target : context.smoothedRequested)
        return .proceed(
            candidate: candidate,
            statusText: context.forceTransitionReapply
                ? String(format: "%.0f lux -> %%%d (transition reapply)", context.ambientLux, candidate)
                : String(format: "%.0f lux -> %%%d (Yazılıyor...)", context.ambientLux, candidate)
        )
    }
}
