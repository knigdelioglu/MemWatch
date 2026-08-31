import Foundation

struct HiDPIReapplyLifecycle: Equatable {
    private(set) var isListening = false
    private(set) var hasPendingWork = false

    mutating func start() -> Bool {
        guard !isListening else { return false }
        isListening = true
        return true
    }

    mutating func registrationFailed() {
        isListening = false
        hasPendingWork = false
    }

    mutating func stop() -> Bool {
        let wasListening = isListening
        isListening = false
        hasPendingWork = false
        return wasListening
    }

    mutating func scheduleWork() -> Bool {
        guard isListening else { return false }
        hasPendingWork = true
        return true
    }

    mutating func completeWork() {
        hasPendingWork = false
    }
}
