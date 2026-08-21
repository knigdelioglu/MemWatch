import Combine
import Foundation

@MainActor
final class MonitoringService: ObservableObject {
    @Published private(set) var snapshot = MemorySnapshot.empty
    @Published private(set) var swapDeltaBytes: Int64 = 0
    @Published private(set) var swapInDeltaBytes: UInt64 = 0
    @Published private(set) var swapOutDeltaBytes: UInt64 = 0
    @Published private(set) var isActivelySwapping = false

    private let collector = MemoryCollector()
    private var timer: Timer?

    private var previousSwapUsedBytes: UInt64?
    private var previousSwapInBytes: UInt64?
    private var previousSwapOutBytes: UInt64?

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
            swapDeltaBytes = signedDelta(current: nextSnapshot.swapUsedBytes, previous: previousSwapUsedBytes)
        } else {
            swapDeltaBytes = 0
        }

        if let previousSwapInBytes {
            swapInDeltaBytes = monotonicDelta(current: nextSnapshot.swapInBytes, previous: previousSwapInBytes)
        } else {
            swapInDeltaBytes = 0
        }

        if let previousSwapOutBytes {
            swapOutDeltaBytes = monotonicDelta(current: nextSnapshot.swapOutBytes, previous: previousSwapOutBytes)
        } else {
            swapOutDeltaBytes = 0
        }

        isActivelySwapping = swapInDeltaBytes > 0 || swapOutDeltaBytes > 0 || swapDeltaBytes > 0

        previousSwapUsedBytes = nextSnapshot.swapUsedBytes
        previousSwapInBytes = nextSnapshot.swapInBytes
        previousSwapOutBytes = nextSnapshot.swapOutBytes
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

    private func monotonicDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private func signedDelta(current: UInt64, previous: UInt64) -> Int64 {
        if current >= previous {
            let delta = current - previous
            return delta > UInt64(Int64.max) ? Int64.max : Int64(delta)
        }

        let delta = previous - current
        return delta > UInt64(Int64.max) ? Int64.min + 1 : -Int64(delta)
    }
}
