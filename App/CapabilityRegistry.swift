import Foundation
import Combine

@MainActor
final class CapabilityRegistry: ObservableObject {
    @Published private(set) var display = DisplayCapabilities.unavailable

    func update(display capabilities: DisplayCapabilities) {
        display = capabilities
    }
}
