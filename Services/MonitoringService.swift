import Foundation

@MainActor
final class MonitoringService: ObservableObject {
    @Published private(set) var snapshot = MemorySnapshot.empty
    @Published private(set) var swapDeltaBytes: Int64 = 0
    @Published private(set) var isActivelySwapping = false

    private let collector = MemoryCollector()
    private var timer: Timer?
    private var previousSwapUsedBytes: UInt64?

    init() {
        refresh()
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let nextSnapshot = collector.collect()

        if let previousSwapUsedBytes {
            swapDeltaBytes = Int64(nextSnapshot.swapUsedBytes) - Int64(previousSwapUsedBytes)
            isActivelySwapping = swapDeltaBytes > 0
        } else {
            swapDeltaBytes = 0
            isActivelySwapping = false
        }

        previousSwapUsedBytes = nextSnapshot.swapUsedBytes
        snapshot = nextSnapshot
    }

    private func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
