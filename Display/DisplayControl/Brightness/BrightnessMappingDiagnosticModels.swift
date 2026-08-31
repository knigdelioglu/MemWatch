import Foundation

struct BrightnessMappingDiagnosticSummary: Sendable {
    let targetDisplayName: String
    let displayKey: String?
    let ambientSensorRawValue: Double?
    let ambientNormalizedValue: Double?
    let computedAutoTargetBrightnessPercent: Int?
    let requestedDDCBrightnessPercent: Int?
    let ddcWriteSucceeded: Bool?
    let ddcWriteMessage: String?
    let actualDDCBrightnessPercent: Int?
    let lastDDCReadbackPercent: Int?
    let rawCurrentBefore: Int?
    let rawMax: Int?
    let computedRawTarget: Int?
    let rawBefore: Int?
    let rawAfter: Int?
    let actualUIPercentAfter: Int?
    let matchedTarget: Bool?
    let writeStatus: M1DDCBrightnessWriteStatus?
    let uiSliderValue: Int
    let lastBrightnessSource: BrightnessSource
    let isAutoBrightnessEnabled: Bool
    let isManualOverrideActive: Bool
    let readbackAvailable: Bool

    var mismatchDetected: Bool {
        guard let requestedDDCBrightnessPercent, let actualDDCBrightnessPercent else { return false }
        return abs(requestedDDCBrightnessPercent - actualDDCBrightnessPercent) > 3
    }

    var writeStatusText: String {
        writeStatus?.rawValue ?? "unknown"
    }

    var matchedTargetText: String {
        matchedTarget.map { $0 ? "YES" : "NO" } ?? "UNKNOWN"
    }
}
