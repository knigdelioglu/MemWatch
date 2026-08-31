import CoreGraphics
import Foundation

enum DisplayConnectionPhase: String, Equatable, Sendable {
    case connected
    case softwareDisconnected
    case physicallyDisconnected
    case disconnecting
    case reconnecting
    case unsupported
    case failed
}

struct DisplayConnectionIdentity: Equatable, Sendable {
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let name: String

    static let samsungS60UD = DisplayConnectionIdentity(
        vendorID: 0x4C2D,
        productID: 0x76AB,
        serialNumber: 0x30413332,
        name: "Samsung S60UD"
    )
}

struct DisplayConnectionSnapshot: Equatable, Sendable {
    let phase: DisplayConnectionPhase
    let displayID: CGDirectDisplayID?
    let name: String
    let isOnline: Bool
    let isActive: Bool
    let canToggle: Bool
    let message: String

    static let initial = DisplayConnectionSnapshot(
        phase: .unsupported,
        displayID: nil,
        name: DisplayConnectionIdentity.samsungS60UD.name,
        isOnline: false,
        isActive: false,
        canToggle: false,
        message: "Ekran bağlantı durumu henüz okunmadı."
    )
}

enum DisplayConnectionPolicy {
    static func phase(
        targetFoundInPrivateList: Bool,
        isOnline: Bool,
        isActive: Bool,
        softwareDisconnectRequested: Bool
    ) -> DisplayConnectionPhase {
        guard targetFoundInPrivateList else { return .physicallyDisconnected }
        if isOnline && isActive { return .connected }
        return softwareDisconnectRequested ? .softwareDisconnected : .physicallyDisconnected
    }

    static func canDisable(
        targetDisplayID: CGDirectDisplayID,
        activeDisplayIDs: [CGDirectDisplayID]
    ) -> Bool {
        guard activeDisplayIDs.contains(targetDisplayID) else { return false }
        return activeDisplayIDs.contains { $0 != targetDisplayID }
    }
}
