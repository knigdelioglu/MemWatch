import Foundation

enum BrightnessSource: String, Codable, Sendable {
    case ambientComputed
    case autoDDCWrite
    case quickPanelSlider
    case ddcReadback
    case manualOverride
    case suppressed
    case writeFailed
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

    var uiSliderBrightnessPercent: Int {
        return actualDDCBrightnessPercent
            ?? lastDDCReadbackPercent
            ?? requestedDDCBrightnessPercent
            ?? autoTargetBrightnessPercent
            ?? 50
    }

    var readbackStatusText: String {
        isDDCReadbackAvailable ? "OK" : "Failed"
    }
}
