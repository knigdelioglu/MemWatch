import CoreGraphics
import Foundation

struct DDCRawBrightnessProbeSummary: Sendable {
    let targetDisplayName: String
    let displayID: CGDirectDisplayID
    let displayIndex: String?
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32?
    let rawCurrentBefore: Int?
    let rawMax: Int?
    let requestedRawMax: Int?
    let writeStatus: M1DDCBrightnessWriteStatus
    let rawAfter: Int?
    let normalizedAfterPercent: Int?
    let matchedMax: Bool
    let diagnosis: [String]
    let notes: [String]

    var rawCurrentBeforeText: String {
        rawCurrentBefore.map(String.init) ?? "unavailable"
    }

    var rawMaxText: String {
        rawMax.map(String.init) ?? "unavailable"
    }

    var requestedRawMaxText: String {
        requestedRawMax.map(String.init) ?? "unavailable"
    }

    var writeResultText: String {
        writeStatus.rawValue
    }

    var rawAfterText: String {
        rawAfter.map(String.init) ?? "unavailable"
    }

    var normalizedAfterPercentText: String {
        normalizedAfterPercent.map { "\($0)%" } ?? "unavailable"
    }

    var matchedMaxText: String {
        matchedMax ? "YES" : "NO"
    }
}
