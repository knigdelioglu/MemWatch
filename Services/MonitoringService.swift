import Combine
import Foundation

@MainActor
final class MonitoringService: ObservableObject {
    @Published private(set) var snapshot = MemorySnapshot.empty

    private let collector = MemoryCollector()
    private var previousSnapshot: MemorySnapshot?
    private var timer: Timer?

    init() {
        refresh()
        startMonitoring()
    }

    func refresh() {
        var nextSnapshot = collector.collect()
        applySwapRates(to: &nextSnapshot, previous: previousSnapshot)

        previousSnapshot = nextSnapshot
        snapshot = nextSnapshot
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(
            withTimeInterval: 2,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func applySwapRates(
        to current: inout MemorySnapshot,
        previous: MemorySnapshot?
    ) {
        guard let previous else {
            return
        }

        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else {
            return
        }

        if current.swapInBytes >= previous.swapInBytes {
            current.swapInRateBytesPerSecond = Double(
                current.swapInBytes - previous.swapInBytes
            ) / elapsed
        }

        if current.swapOutBytes >= previous.swapOutBytes {
            current.swapOutRateBytesPerSecond = Double(
                current.swapOutBytes - previous.swapOutBytes
            ) / elapsed
        }
    }
}
