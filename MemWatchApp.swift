import AppKit
import SwiftUI

@main
struct MemWatchApp: App {
    @StateObject private var monitor = MonitoringService()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

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
        if monitor.storageVolumes.contains(where: { $0.health == .critical }) {
            return "externaldrive.badge.exclamationmark"
        }

        switch monitor.intelligence.state {
        case .stable, .idleSwap:
            return "memorychip"
        case .readback:
            return "arrow.down.circle"
        case .activeSwap:
            return "arrow.left.arrow.right.circle.fill"
        case .pressure:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "exclamationmark.octagon.fill"
        }
    }
}
