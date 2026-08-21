import SwiftUI

@main
struct MemWatchApp: App {
    @StateObject private var monitor = MonitoringService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                snapshot: monitor.snapshot,
                refreshAction: monitor.refresh
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: statusSymbol)
                Text("\(monitor.snapshot.usedPercent)%")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var statusSymbol: String {
        switch monitor.snapshot.pressure {
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.triangle"
        case .normal:
            return monitor.snapshot.isActivelySwappingOut
                ? "arrow.up.circle.fill"
                : "memorychip"
        }
    }
}
