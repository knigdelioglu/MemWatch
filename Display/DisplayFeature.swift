import Foundation

enum DisplayCapabilityStatus: String, Equatable {
    case available
    case degraded
    case unavailable
}

struct DisplayCapability: Equatable {
    let status: DisplayCapabilityStatus
    let reason: String?

    var isAvailable: Bool {
        status != .unavailable
    }

    static let available = DisplayCapability(status: .available, reason: nil)

    static func degraded(_ reason: String) -> DisplayCapability {
        DisplayCapability(status: .degraded, reason: reason)
    }

    static func unavailable(_ reason: String) -> DisplayCapability {
        DisplayCapability(status: .unavailable, reason: reason)
    }
}

struct DisplayCapabilities: Equatable {
    var ambientLightSensor: DisplayCapability
    var internalBrightness: DisplayCapability
    var externalDisplay: DisplayCapability
    var ddc: DisplayCapability
    var volume: DisplayCapability
    var hiDPI: DisplayCapability
    var softwareDisconnect: DisplayCapability
    var keepAwake: DisplayCapability

    static let unavailable = DisplayCapabilities(
        ambientLightSensor: .unavailable("Ambient light sensor is unavailable."),
        internalBrightness: .unavailable("Internal display brightness is unavailable."),
        externalDisplay: .unavailable("No supported external display is connected."),
        ddc: .unavailable("DDC is unavailable. Install m1ddc to control an external display."),
        volume: .unavailable("External monitor volume is unavailable."),
        hiDPI: .unavailable("HiDPI private display APIs are unavailable."),
        softwareDisconnect: .unavailable("Software display connection control is unavailable."),
        keepAwake: .available
    )
}

@MainActor
protocol DisplayFeatureControlling: AnyObject {
    var capabilities: DisplayCapabilities { get }
    var isRunning: Bool { get }

    func start()
    func stop()
    func refresh()
}
