import SwiftUI

@main
struct MemWatchApp: App {
    @StateObject private var monitor = MonitoringService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuBarSymbol)
                Text("\(monitor.snapshot.usagePercent)%")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        if monitor.isActivelySwapping {
            return "arrow.left.arrow.right.circle.fill"
        }

        switch monitor.snapshot.pressure {
        case .normal:
            return "memorychip"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "exclamationmark.octagon.fill"
        }
    }
}
