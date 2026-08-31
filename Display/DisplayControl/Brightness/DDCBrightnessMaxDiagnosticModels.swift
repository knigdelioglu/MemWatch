import CoreGraphics
import Foundation

enum DDCBrightnessLimiterState: String, Sendable {
    case yes
    case no
    case unknown

    var displayText: String {
        switch self {
        case .yes: return "YES"
        case .no: return "NO"
        case .unknown: return "UNKNOWN"
        }
    }
}

struct DDCBrightnessMaxDiagnosticSummary: Sendable {
    let targetDisplayName: String
    let displayID: CGDirectDisplayID
    let displayIndex: String?
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32?
    let currentBrightnessBefore: Int?
    let maxBrightness: Int?
    let setBrightness100Succeeded: Bool?
    let brightnessReadbackAfterSet100: Int?
    let brightnessReadbackAfterSet100UIPercent: Int?
    let requestedRawMax: Int?
    let computedRawTarget: Int?
    let rawBrightnessBefore: Int?
    let rawBrightnessAfter: Int?
    let matchedTarget: Bool?
    let writeStatus: M1DDCBrightnessWriteStatus?
    let currentContrast: Int?
    let maxContrast: Int?
    let mccsCapabilitiesAvailable: Bool
    let mccsCapabilitiesString: String?
    let supportedVCPCodes: [String]
    let possibleBrightnessLimiter: DDCBrightnessLimiterState
    let diagnosis: [String]
    let recommendedManualChecks: [String]
    let notes: [String]

    var ddcBrightnessAvailableText: String {
        currentBrightnessBefore.map(String.init) ?? "unavailable"
    }

    var ddcBrightnessMaxText: String {
        maxBrightness.map(String.init) ?? "unavailable"
    }

    var setBrightness100ResultText: String {
        setBrightness100Succeeded.map { $0 ? "YES" : "NO" } ?? "UNKNOWN"
    }

    var brightnessReadbackAfterSet100Text: String {
        brightnessReadbackAfterSet100.map(String.init) ?? "unavailable"
    }

    var brightnessReadbackAfterSet100UIPercentText: String {
        brightnessReadbackAfterSet100UIPercent.map { "\($0)%" } ?? "unavailable"
    }

    var requestedRawMaxText: String {
        requestedRawMax.map(String.init) ?? "unavailable"
    }

    var computedRawTargetText: String {
        computedRawTarget.map(String.init) ?? "unavailable"
    }

    var rawBrightnessBeforeText: String {
        rawBrightnessBefore.map(String.init) ?? "unavailable"
    }

    var rawBrightnessAfterText: String {
        rawBrightnessAfter.map(String.init) ?? "unavailable"
    }

    var matchedTargetText: String {
        matchedTarget.map { $0 ? "YES" : "NO" } ?? "UNKNOWN"
    }

    var writeStatusText: String {
        writeStatus?.rawValue ?? "unknown"
    }

    var ddcContrastCurrentText: String {
        currentContrast.map(String.init) ?? "unavailable"
    }

    var ddcContrastMaxText: String {
        maxContrast.map(String.init) ?? "unavailable"
    }

    var mccsCapabilitiesAvailableText: String {
        mccsCapabilitiesAvailable ? "YES" : "NO"
    }

    var supportedVCPCodesText: String {
        supportedVCPCodes.isEmpty ? "unavailable" : supportedVCPCodes.joined(separator: ", ")
    }
}
