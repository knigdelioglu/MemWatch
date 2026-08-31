import AppKit
import Foundation
enum PowerSourceState {
    case ac
    case battery
    case unknown
}

final class PowerSourceController {
    private let reader = PowerSourceReader()

    func currentState() -> PowerSourceState {
        switch reader.read().source {
        case .ac, .ups:
            return .ac
        case .battery:
            return .battery
        case .unknown:
            return .unknown
        }
    }
}
