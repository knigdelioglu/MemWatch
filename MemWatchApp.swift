import SwiftUI

@main
struct MemWatchApp: App {
    @StateObject private var monitor = MonitoringService()

    var body: some Scene {
        MenuBarExtra("MemWatch", systemImage: "memorychip") {
            MenuBarView(snapshot: monitor.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}
