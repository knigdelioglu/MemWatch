import CoreGraphics
import Foundation

enum EDIDMatchConfidence: String, Codable, Sendable {
    case unavailable
    case low
    case medium
    case high
    case certain
    case ambiguous

    var displayText: String {
        switch self {
        case .unavailable: return "unavailable"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        case .certain: return "certain"
        case .ambiguous: return "ambiguous"
        }
    }
}

enum EDIDReadStatus: String, Codable, Sendable {
    case unavailable
    case invalid
    case partial
    case available
    case ambiguous

    var displayText: String {
        switch self {
        case .unavailable: return "unavailable"
        case .invalid: return "invalid"
        case .partial: return "partial"
        case .available: return "available"
        case .ambiguous: return "ambiguous"
        }
    }
}

struct EDIDInfo: Codable, Sendable {
    let rawByteCount: Int
    let sha256: String
    let manufacturerCode: String?
    let productCode: UInt16?
    let serialNumber: UInt32?
    let manufactureWeek: UInt8?
    let manufactureYear: UInt16?
    let displayName: String?
    let preferredTimingSummary: String?
    let horizontalSizeCm: UInt8?
    let verticalSizeCm: UInt8?
    let matchConfidence: EDIDMatchConfidence
    let status: EDIDReadStatus
    let notes: [String]
}

struct EDIDParseResult: Sendable {
    let info: EDIDInfo

    var status: EDIDReadStatus { info.status }
    var notes: [String] { info.notes }
}

struct EDIDDiagnosticSummary: Sendable {
    let displayID: CGDirectDisplayID
    let targetDisplayName: String
    let targetVendorID: UInt32
    let targetProductID: UInt32
    let targetSerialNumber: UInt32?
    let edidInfo: EDIDInfo?
    let matchConfidence: EDIDMatchConfidence
    let status: EDIDReadStatus
    let notes: [String]

    var edidAvailable: Bool {
        edidInfo != nil && status != .unavailable && status != .ambiguous
    }

    var rawByteCount: Int? { edidInfo?.rawByteCount }
    var sha256: String? { edidInfo?.sha256 }
    var manufacturerCode: String? { edidInfo?.manufacturerCode }
    var productCode: UInt16? { edidInfo?.productCode }
    var serialNumber: UInt32? { edidInfo?.serialNumber }
    var manufactureWeek: UInt8? { edidInfo?.manufactureWeek }
    var manufactureYear: UInt16? { edidInfo?.manufactureYear }
    var edidDisplayName: String? { edidInfo?.displayName }
    var preferredTimingSummary: String? { edidInfo?.preferredTimingSummary }
    var horizontalSizeCm: UInt8? { edidInfo?.horizontalSizeCm }
    var verticalSizeCm: UInt8? { edidInfo?.verticalSizeCm }
    var nativeResolutionHint: String? { edidInfo?.preferredTimingSummary }
}
