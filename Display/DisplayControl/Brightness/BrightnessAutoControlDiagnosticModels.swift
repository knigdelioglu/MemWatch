import Foundation

struct BrightnessAutoControlDiagnosticSummary: Sendable {
    let ambientSensorRawValue: Double?
    let ambientNormalizedValue: Double?
    let isAutoBrightnessEnabled: Bool
    let isManualOverrideActive: Bool
    let computedAutoTargetBrightnessPercent: Int?
    let actualDDCBrightnessBefore: Int?
    let writeAttempted: Bool
    let writeValue: Int?
    let writeSucceeded: Bool?
    let writeMessage: String?
    let actualDDCBrightnessAfter: Int?
    let lastBrightnessSource: BrightnessSource
    let suppressionReason: BrightnessSuppressionReason?
    let mismatchDetected: Bool
}
