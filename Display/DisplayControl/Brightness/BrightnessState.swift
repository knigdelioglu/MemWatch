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
    case ambientComputed
    case autoDDCWrite
    case quickPanelSlider
    case ddcReadback
    case manualOverride
    case suppressed
    case writeFailed
}

enum BrightnessReadbackReliability: String, Codable, Sendable {
    case reliable
    case uncertainAfterWrite
    case unavailable
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
    var lastBrightnessSource: BrightnessSource = .ambientComputed
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
    var optimisticBrightnessPercent: Int?
    var optimisticBrightnessExpiresAt: Date?
    var optimisticReadbackAttempts: Int = 0
    var lastConfirmedBrightnessPercent: Int?
    var readbackReliability: BrightnessReadbackReliability = .unavailable
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
        activeOptimisticBrightnessPercent(now: now)
            ?? (readbackReliability == .reliable
                ? actualDDCBrightnessPercent ?? lastDDCReadbackPercent
                : nil)
            ?? lastConfirmedBrightnessPercent
            ?? requestedDDCBrightnessPercent
            ?? autoTargetBrightnessPercent
    }

    var uiSliderBrightnessPercent: Int {
        return pendingManualBrightnessPercent
            ?? activeOptimisticBrightnessPercent()
            ?? (readbackReliability == .reliable
                ? actualDDCBrightnessPercent ?? lastDDCReadbackPercent
                : nil)
            ?? lastConfirmedBrightnessPercent
            ?? requestedDDCBrightnessPercent
            ?? autoTargetBrightnessPercent
            ?? 50
    }

    var readbackStatusText: String {
        readbackReliability.rawValue
    }
}
