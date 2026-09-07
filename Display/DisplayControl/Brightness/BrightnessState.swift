import Foundation

/// Invalidates completions from older brightness requests without trying to
/// terminate a DDC transaction that may already be in progress.
struct LatestValueWriteGate: Equatable, Sendable {
    private(set) var generation: UInt64 = 0

    mutating func invalidate() {
        generation &+= 1
    }

    mutating func startRequest() -> UInt64 {
        generation &+= 1
        return generation
    }

    func accepts(_ requestGeneration: UInt64) -> Bool {
        requestGeneration == generation
    }
}

enum BrightnessSource: String, Codable, Sendable {
    case transition
    case unavailable
    case ambientComputed
    case autoDDCWrite
    case quickPanelSlider
    case ddcReadback
    case manualOverride
    case suppressed
    case writeFailed
}

enum BrightnessReadbackReliability: String, Codable, Sendable, Equatable {
    case reliable
    case uncertainAfterWrite
    case transitionUnverified
    case unavailable
}

/// Describes where a scalar brightness sample came from. A cache fallback is
/// never evidence that the panel returned this value for the current epoch.
enum BrightnessReadbackSource: String, Codable, Sendable, Equatable {
    case hardwareFresh = "freshHardware"
    case cacheFallback
}

enum BrightnessTransitionReapplyStatus: String, Codable, Sendable, Equatable {
    case notNeeded = "not needed"
    case pending
    case awaitingConfirmation = "awaiting confirmation"
    case complete
    case failed
}

enum BrightnessReadbackConfirmationPolicy {
    static let tolerance = 3
    static let normalStableSampleCount = 2
    static let previousEpochStableSampleCount = 4

    static func isWithinTolerance(_ lhs: Int, _ rhs: Int) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    /// A value equal to the previous epoch's readback needs stronger evidence,
    /// but it must still be able to become authoritative after a bounded
    /// number of fresh hardware samples.
    static func requiredStableSampleCount(
        current: Int,
        previousEpochReadback: Int?
    ) -> Int {
        guard let previousEpochReadback,
              isWithinTolerance(current, previousEpochReadback) else {
            return normalStableSampleCount
        }
        return previousEpochStableSampleCount
    }
}

struct BrightnessReadSample: Sendable {
    let percent: Int
    let source: BrightnessReadbackSource
}

enum BrightnessSuppressionReason: String, Codable, Sendable {
    case autoDisabled = "auto disabled"
    case manualOverrideActive = "manual override active"
    case debounceWaiting = "debounce waiting"
    case displayNotResolved = "display not resolved"
    case ddcUnavailable = "DDC unavailable"
    case brightnessWriteSuppressed = "brightness write suppressed"
    case targetEqualsActual = "target equals actual"
    case appInactiveOrSleepWake = "app inactive / sleep-wake suppression"
    case monitorLimiterCooldown = "monitor limiter cooldown"
    case directionChangeSettling = "direction change settling"
}

struct BrightnessState: Sendable {
    var ambientSensorRawValue: Double?
    var ambientNormalizedValue: Double?
    var autoTargetBrightnessPercent: Int?
    var requestedDDCBrightnessPercent: Int?
    var actualDDCBrightnessPercent: Int?
    var lastDDCReadbackPercent: Int?
    var lastDDCRawCurrentBefore: Int?
    var lastDDCRawMax: Int?
    var lastDDCRawTarget: Int?
    var lastDDCRawAfter: Int?
    var lastDDCActualPercentAfter: Int?
    var isAutoBrightnessEnabled: Bool = true
    var isManualOverrideActive: Bool = false
    var lastBrightnessSource: BrightnessSource = .unavailable
    var isDDCReadbackAvailable: Bool = false
    var lastDDCWriteSucceeded: Bool?
    var lastDDCWriteMessage: String?
    var lastDDCWriteStatus: M1DDCBrightnessWriteStatus?
    var lastDDCMatchedTarget: Bool?
    var isBrightnessWriteSuppressed: Bool = false
    var lastSuppressionReason: BrightnessSuppressionReason?
    var lastAutoWriteAttempted: Bool = false
    var lastAutoWriteValue: Int?
    var lastAutoWriteSucceeded: Bool?
    var lastAutoWriteMessage: String?
    var lastAutoWriteActualBefore: Int?
    var lastAutoWriteActualAfter: Int?
    
    // Yeni tanı ve izleme alanları
    var smoothedRequestedBrightnessPercent: Int?
    var lastWriteAttemptPercent: Int?
    var lastWriteReadbackPercent: Int?
    var suppressionReason: String?
    var manualOverridePausedUntil: Date?
    var showMismatchWarning: Bool = false
    /// Latest manual slider intent that is waiting for its DDC write or
    /// readback. Backend refreshes must not replace this draft. Once the
    /// command is accepted, `optimisticBrightnessPercent` carries the same
    /// intent beyond this transient phase while the readback is uncertain.
    var pendingManualBrightnessPercent: Int?
    /// Latest DDC command accepted by the monitor. This remains the logical
    /// command/reference until a later explicit failure or authoritative
    /// observation replaces it; it is intentionally not TTL-bound.
    var commandedBrightnessPercent: Int?
    var optimisticBrightnessPercent: Int?
    var optimisticBrightnessExpiresAt: Date?
    var optimisticReadbackAttempts: Int = 0
    /// Presentation-only fallback. It is never treated as hardware truth or
    /// used by the automatic policy reference.
    var persistedBrightnessPercent: Int?
    var lastConfirmedBrightnessPercent: Int?
    var readbackReliability: BrightnessReadbackReliability = .unavailable
    var lastReadbackSource: BrightnessReadbackSource?
    var transitionReadbackSampleCount: Int = 0
    var transitionReadbackStableCount: Int = 0
    var transitionReadbackCandidatePercent: Int?
    /// Non-authoritative diagnostic marker from the preceding display epoch;
    /// used to avoid promoting the same stale value after a transition.
    var transitionPreviousReadbackPercent: Int?
    /// An accepted command remains visible to the UI, but these fields track a
    /// separate, epoch-scoped automatic reapply request. They never promote a
    /// command to hardware truth.
    var transitionReapplyEpoch: UInt64?
    var needsAutoBrightnessReapplyAfterTransition = false
    var transitionReapplyStatus: BrightnessTransitionReapplyStatus = .notNeeded
    var transitionReapplyAttemptCount = 0
    var transitionReapplyTargetPercent: Int?
    var transitionReapplyFailureMessage: String?
    var mismatchStreak: Int = 0
    var limiterDetected: Bool = false

    func activeOptimisticBrightnessPercent(now: Date = Date()) -> Int? {
        guard let optimisticBrightnessPercent,
              let optimisticBrightnessExpiresAt,
              now < optimisticBrightnessExpiresAt else {
            return nil
        }
        return optimisticBrightnessPercent
    }

    func referenceBrightness(now: Date = Date()) -> Int? {
        // This is the logical/UI reference. Accepted commands are intentionally
        // not time-limited so slider continuity survives a display transition.
        // Automatic policy must use authoritativeBrightnessForAutomaticControl
        // instead; a command is not a hardware observation.
        _ = now
        return pendingManualBrightnessPercent
            ?? commandedBrightnessPercent
            ?? authoritativeDDCBrightnessPercent
    }

    /// Only a reliable readback is hardware truth. Persisted values and
    /// unverified samples remain presentation/diagnostic data.
    var authoritativeDDCBrightnessPercent: Int? {
        guard readbackReliability == .reliable else { return nil }
        return actualDDCBrightnessPercent
            ?? lastConfirmedBrightnessPercent
            ?? lastDDCReadbackPercent
    }

    /// The only brightness value the automatic controller may treat as the
    /// current hardware state. Presentation fallbacks, accepted commands,
    /// transition markers and uncertain write results are deliberately absent.
    var authoritativeBrightnessForAutomaticControl: Int? {
        authoritativeDDCBrightnessPercent
    }

    /// Records one fresh hardware sample during a transition and returns
    /// whether the bounded confirmation policy has enough stable evidence to
    /// promote it. Cache samples must never call this method.
    @discardableResult
    mutating func recordTransitionReadbackConfirmation(_ readback: Int) -> Bool {
        transitionReadbackSampleCount += 1
        if let candidate = transitionReadbackCandidatePercent,
           BrightnessReadbackConfirmationPolicy.isWithinTolerance(readback, candidate) {
            transitionReadbackStableCount += 1
        } else {
            transitionReadbackCandidatePercent = readback
            transitionReadbackStableCount = 1
        }

        let requiredSampleCount = BrightnessReadbackConfirmationPolicy.requiredStableSampleCount(
            current: readback,
            previousEpochReadback: transitionPreviousReadbackPercent
        )
        return transitionReadbackStableCount >= requiredSampleCount
    }

    /// UI precedence is intentionally broader than hardware/reference
    /// precedence: it keeps an accepted user intent visible while the panel
    /// is transitioning or a fresh DDC readback is unavailable.
    var uiSliderBrightnessPercent: Int {
        return pendingManualBrightnessPercent
            ?? commandedBrightnessPercent
            ?? authoritativeDDCBrightnessPercent
            ?? persistedBrightnessPercent
            ?? autoTargetBrightnessPercent
            ?? 50
    }

    var readbackStatusText: String {
        readbackReliability.rawValue
    }
}
