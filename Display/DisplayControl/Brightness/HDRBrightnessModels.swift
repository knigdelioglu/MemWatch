import CoreGraphics
import Foundation

enum HDRBrightnessDiagnosis: String, Sendable {
    case ddcWorking
    case ddcIgnoredInHDR
    case hdrEDRAvailable
    case hdrEDRUnavailable
    case unknown

    var displayText: String {
        switch self {
        case .ddcWorking: return "ddcWorking"
        case .ddcIgnoredInHDR: return "ddcIgnoredInHDR"
        case .hdrEDRAvailable: return "hdrEDRAvailable"
        case .hdrEDRUnavailable: return "hdrEDRUnavailable"
        case .unknown: return "unknown"
        }
    }

    var recommendedPath: String {
        switch self {
        case .ddcWorking: return "Use DDC brightness"
        case .ddcIgnoredInHDR: return "HDR locks DDC brightness"
        case .hdrEDRAvailable: return "HDR/EDR brightness boost requires separate implementation"
        case .hdrEDRUnavailable: return "Use DDC brightness"
        case .unknown: return "HDR/EDR brightness boost requires separate implementation"
        }
    }
}

struct HDRBrightnessEDRValues: Sendable {
    let maximumExtendedDynamicRangeColorComponentValue: Double?
    let maximumPotentialExtendedDynamicRangeColorComponentValue: Double?
    let maximumReferenceExtendedDynamicRangeColorComponentValue: Double?

    var available: Bool {
        [maximumExtendedDynamicRangeColorComponentValue, maximumPotentialExtendedDynamicRangeColorComponentValue, maximumReferenceExtendedDynamicRangeColorComponentValue]
            .compactMap { $0 }
            .contains { $0 > 1.0 }
    }
}

struct HDRBrightnessDiagnosticSummary: Sendable {
    let targetDisplayName: String
    let displayID: CGDirectDisplayID
    let displayIndex: String?
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32?
    let activeModeLogicalWidth: Int?
    let activeModeLogicalHeight: Int?
    let activeModePixelWidth: Int?
    let activeModePixelHeight: Int?
    let activeModeRefreshRate: Double?
    let activeModePixelEncoding: String?
    let hdrSystemProfilerStatus: String
    let systemProfilerColorProfile: String?
    let systemProfilerEvidence: [String]
    let ddcReadAvailable: Bool
    let ddcCurrentBrightness: Int?
    let ddcMaxBrightness: Int
    let ddcSetSucceeded: Bool?
    let ddcTestBrightness: Int?
    let ddcReadbackBrightness: Int?
    let ddcReadbackChanged: Bool?
    let edrValues: HDRBrightnessEDRValues
    let diagnosis: HDRBrightnessDiagnosis
    let notes: [String]

    var ddcBrightnessAvailable: Bool { ddcCurrentBrightness != nil }
    var ddcWorksInHDRText: String {
        switch diagnosis {
        case .ddcWorking: return "YES"
        case .ddcIgnoredInHDR: return "NO"
        case .hdrEDRAvailable, .hdrEDRUnavailable, .unknown: return "UNKNOWN"
        }
    }

    var edrAvailableText: String {
        edrValues.available ? "YES" : "NO"
    }

    var recommendedPathText: String {
        diagnosis.recommendedPath
    }
}

struct HDRBrightnessDDCResult: Sendable {
    let displayIndex: String?
    let currentBrightness: Int?
    let testBrightness: Int?
    let setSucceeded: Bool?
    let readbackBrightness: Int?
    let readbackChanged: Bool?
    let readAvailable: Bool
    let maxBrightness: Int
    let notes: [String]
}
