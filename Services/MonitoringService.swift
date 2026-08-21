import Foundation

@MainActor
final class MonitoringService: ObservableObject {
    @Published var snapshot = MemorySnapshot.empty

    private let collector = MemoryCollector()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        snapshot = collector.collect()
    }
}
