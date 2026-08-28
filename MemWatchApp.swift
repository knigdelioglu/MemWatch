import AppKit
import Combine
import QuartzCore
import SwiftUI

@main
struct MemWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private lazy var monitor = MonitoringService()
    private lazy var cleanup = CleanupCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(monitor: monitor, cleanup: cleanup)
    }
}

private enum TrayTintRole: Equatable {
    case system
    case orange
    case red

    var color: NSColor? {
        switch self {
        case .system:
            return nil
        case .orange:
            return .systemOrange
        case .red:
            return .systemRed
        }
    }
}

private struct TrayPresentation: Equatable {
    let symbolName: String
    let tintRole: TrayTintRole
    let accessibilityDescription: String
    let toolTip: String
    let pulseOnEntry: Bool
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private static let panelSize = NSSize(width: 430, height: 640)
    private static let cleanupWindowSize = NSSize(width: 680, height: 780)

    private let monitor: MonitoringService
    private let cleanup: CleanupCoordinator
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cleanupWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var pendingSingleClick: DispatchWorkItem?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var previousTrayPresentation: TrayPresentation?

    init(monitor: MonitoringService, cleanup: CleanupCoordinator) {
        self.monitor = monitor
        self.cleanup = cleanup
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        configurePopover()
        observeMonitor()
        updateStatusButton()
    }

    deinit {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = "MemWatch"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        installDashboardRootView()
    }

    private func installDashboardRootView() {
        popover.contentSize = Self.panelSize
        popover.contentViewController = NSHostingController(
            rootView: SmartMenuBarRootView(monitor: monitor)
                .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        )
    }

    private func observeMonitor() {
        Publishers.CombineLatest4(
            monitor.$snapshot,
            monitor.$intelligence,
            monitor.$storageVolumes,
            monitor.$diagnostics
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.updateStatusButton()
        }
        .store(in: &cancellables)
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let presentation = trayPresentation
        let image = NSImage(named: "TrayIcon") ?? NSImage(
            systemSymbolName: "memorychip",
            accessibilityDescription: "MemWatch"
        )
        image?.isTemplate = true

        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.contentTintColor = presentation.tintRole.color
        button.toolTip = presentation.toolTip
        button.setAccessibilityLabel(presentation.accessibilityDescription)

        let shouldPulse = previousTrayPresentation != nil &&
            previousTrayPresentation != presentation &&
            presentation.pulseOnEntry

        previousTrayPresentation = presentation

        if shouldPulse {
            pulseStatusButton(button)
        } else if !presentation.pulseOnEntry {
            stopStatusButtonAnimation(button)
        }
    }

    private func pulseStatusButton(_ button: NSStatusBarButton) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopStatusButtonAnimation(button)
            return
        }

        button.wantsLayer = true
        button.layer?.removeAnimation(forKey: "memwatch-status-pulse")

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1.0, 0.35, 1.0, 0.35, 1.0, 0.35, 1.0]
        animation.keyTimes = [0.0, 0.12, 0.28, 0.40, 0.56, 0.68, 1.0]
        animation.duration = 1.35
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = true
        button.layer?.add(animation, forKey: "memwatch-status-pulse")
    }

    private func stopStatusButtonAnimation(_ button: NSStatusBarButton) {
        button.layer?.removeAnimation(forKey: "memwatch-status-pulse")
        button.layer?.opacity = 1.0
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(relativeTo: sender)
            return
        }

        if event.type == .rightMouseUp || event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            closePopover()
            showContextMenu(relativeTo: sender)
            return
        }

        pendingSingleClick?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak sender] in
            guard let self, let sender else { return }
            self.togglePopover(relativeTo: sender)
        }
        pendingSingleClick = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            monitor.refresh(forceStorage: true, forceDiagnostics: true)
            installDashboardRootView()
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            startOutsideClickMonitoring()
        }
    }

    private func closePopover() {
        stopOutsideClickMonitoring()
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }

            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem.button?.window

            if event.window !== popoverWindow && event.window !== statusWindow {
                self.closePopover()
            }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover()
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()

        let cleanupItem = NSMenuItem(
            title: "Deep Cleanup…",
            action: #selector(openCleanupWindow),
            keyEquivalent: ""
        )
        cleanupItem.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Deep Cleanup"
        )
        cleanupItem.target = self
        menu.addItem(cleanupItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MemWatch",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: cleanupItem,
            at: NSPoint(x: 0, y: button.bounds.minY),
            in: button
        )
    }

    @objc
    private func openCleanupWindow() {
        closePopover()

        if let window = cleanupWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if cleanup.scanResult == nil, !cleanup.isBusy {
                cleanup.startScan()
            }
            return
        }

        let hostingController = NSHostingController(
            rootView: CleanupView(coordinator: cleanup)
                .frame(
                    minWidth: Self.cleanupWindowSize.width,
                    minHeight: Self.cleanupWindowSize.height
                )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MemWatch Deep Cleanup"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.cleanupWindowSize)
        window.minSize = NSSize(width: 560, height: 620)
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        cleanupWindowController = controller

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        if cleanup.scanResult == nil, !cleanup.isBusy {
            cleanup.startScan()
        }
    }

    @objc
    private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    private var trayPresentation: TrayPresentation {
        if monitor.diagnostics.thermalState == .critical {
            return TrayPresentation(
                symbolName: "thermometer.high",
                tintRole: .red,
                accessibilityDescription: "MemWatch critical alert, Mac thermal state is critical",
                toolTip: "MemWatch — Critical thermal state",
                pulseOnEntry: true
            )
        }

        if monitor.storageVolumes.contains(where: { $0.health == .critical }) {
            return TrayPresentation(
                symbolName: "externaldrive.badge.exclamationmark",
                tintRole: .red,
                accessibilityDescription: "MemWatch critical alert, storage space is critically low",
                toolTip: "MemWatch — Critical storage space",
                pulseOnEntry: true
            )
        }

        switch monitor.intelligence.state {
        case .stable:
            return TrayPresentation(
                symbolName: "memorychip",
                tintRole: .system,
                accessibilityDescription: "MemWatch, Mac memory is healthy",
                toolTip: "MemWatch — Memory healthy",
                pulseOnEntry: false
            )
        case .idleSwap:
            return TrayPresentation(
                symbolName: "memorychip",
                tintRole: .system,
                accessibilityDescription: "MemWatch, swap contains idle data but memory is healthy",
                toolTip: "MemWatch — Idle swap, no current pressure",
                pulseOnEntry: false
            )
        case .readback:
            return TrayPresentation(
                symbolName: "arrow.down.circle",
                tintRole: .system,
                accessibilityDescription: "MemWatch, previously swapped memory is being read back",
                toolTip: "MemWatch — Swap readback",
                pulseOnEntry: false
            )
        case .activeSwap:
            return TrayPresentation(
                symbolName: "arrow.left.arrow.right.circle.fill",
                tintRole: .orange,
                accessibilityDescription: "MemWatch warning, active swap writes detected",
                toolTip: "MemWatch — Active swap",
                pulseOnEntry: true
            )
        case .pressure:
            return TrayPresentation(
                symbolName: "exclamationmark.triangle.fill",
                tintRole: .orange,
                accessibilityDescription: "MemWatch warning, memory pressure is elevated",
                toolTip: "MemWatch — Memory pressure",
                pulseOnEntry: true
            )
        case .critical:
            return TrayPresentation(
                symbolName: "exclamationmark.octagon.fill",
                tintRole: .red,
                accessibilityDescription: "MemWatch critical alert, memory pressure and swap activity are critical",
                toolTip: "MemWatch — Critical memory pressure",
                pulseOnEntry: true
            )
        }
    }
}

private struct SmartMenuBarRootView: View {
    @ObservedObject var monitor: MonitoringService
    @State private var showingTechnicalDetails = false

    private var snapshot: MemorySnapshot { monitor.snapshot }
    private var intelligence: SwapIntelligenceResult { monitor.intelligence }
    private var pressureEstimate: MemoryPressureEstimate { monitor.memoryPressureEstimate }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if showingTechnicalDetails {
                MenuBarView(monitor: monitor)
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                Button {
                    showingTechnicalDetails = false
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.primary.opacity(0.12), lineWidth: 1)
                }
                .padding(14)
                .help("Back to smart overview")
            } else {
                overview
                    .transition(.opacity)
            }
        }
        .frame(width: 430, height: 640)
        .animation(.easeInOut(duration: 0.16), value: showingTechnicalDetails)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                healthCard
                memoryFocusCard
                quickFactsCard
                topConsumersCard
                controlsRow
            }
            .padding(16)
        }
    }

    private var healthCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: healthSymbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(healthColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(healthTitle)
                    .font(.title3.weight(.semibold))

                Text(healthMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(healthColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(healthColor.opacity(0.28), lineWidth: 1)
        }
    }

    private var memoryFocusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Memory", systemImage: "memorychip")
                    .font(.headline)
                Spacer()
                Text(memoryStateLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(memoryStateColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(memoryStateColor.opacity(0.10), in: Capsule())
            }

            Text(memoryInterpretation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 0) {
                smartMetric(title: "Available", value: memoryBytes(snapshot.availableBytes))
                smartMetric(title: "Pressure", value: "\(pressureEstimate.percent)%")
                smartMetric(title: "Swap", value: swapMetricValue)
            }
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func smartMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickFactsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("At a glance")
                .font(.subheadline.weight(.semibold))

            quickFactRow(
                symbol: "internaldrive",
                title: "Storage",
                value: storageFact,
                color: storageColor
            )

            quickFactRow(
                symbol: powerSymbol,
                title: "Power",
                value: powerFact,
                color: powerColor
            )

            quickFactRow(
                symbol: "cpu",
                title: "System",
                value: systemFact,
                color: thermalColor
            )
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func quickFactRow(symbol: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var topConsumersCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Top memory users")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if intelligence.state == .activeSwap || intelligence.state == .pressure || intelligence.state == .critical {
                    Text("Check first")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(memoryStateColor)
                }
            }

            if monitor.diagnostics.topProcesses.isEmpty {
                Text("No application snapshot yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.diagnostics.topProcesses.prefix(3)) { process in
                    HStack(spacing: 8) {
                        Image(systemName: "app.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(process.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(memoryBytes(process.residentBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Button {
                showingTechnicalDetails = true
            } label: {
                Label("All details", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                monitor.refresh(forceStorage: true, forceDiagnostics: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24)
            }
            .buttonStyle(.bordered)
            .help("Refresh")
        }
    }

    private var healthTitle: String {
        if isCritical { return "Mac needs attention" }
        if needsAttention { return "Keep an eye on this" }
        return "Mac is doing well"
    }

    private var healthMessage: String {
        if monitor.diagnostics.thermalState == .critical {
            return "The system thermal state is critical. Reduce sustained load and let the Mac cool down."
        }
        if let volume = monitor.storageVolumes.first(where: { $0.health == .critical }) {
            return "\(volume.name) is critically low on free space. Freeing storage should be the next action."
        }

        switch intelligence.state {
        case .critical:
            return "Memory pressure and swap activity are critical. If the Mac is slowing down, close one heavy app first."
        case .pressure:
            return "Memory pressure is elevated. The heaviest apps below are the first place to look if responsiveness drops."
        case .activeSwap:
            return "macOS is actively moving memory to disk. No action is needed unless this persists or the Mac starts to feel slow."
        case .readback:
            return "macOS is bringing previously swapped data back into RAM. This is informational, not an alert."
        case .idleSwap:
            return "Swap contains older data, but there is no current memory pressure. No action is needed."
        case .stable:
            if monitor.diagnostics.thermalState == .serious {
                return "Memory is healthy, but the Mac is running hot."
            }
            if let volume = monitor.storageVolumes.first(where: { $0.health == .warning }) {
                return "Memory is healthy. \(volume.name) is starting to run low on free space."
            }
            return "No action is needed. MemWatch will become noticeable only when something deserves attention."
        }
    }

    private var healthSymbol: String {
        if monitor.diagnostics.thermalState == .critical { return "thermometer.high" }
        if monitor.storageVolumes.contains(where: { $0.health == .critical }) {
            return "externaldrive.badge.exclamationmark"
        }
        switch intelligence.state {
        case .stable, .idleSwap: return "checkmark.circle.fill"
        case .readback: return "arrow.down.circle.fill"
        case .activeSwap: return "arrow.left.arrow.right.circle.fill"
        case .pressure: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private var healthColor: Color {
        if isCritical { return .red }
        if needsAttention { return .orange }
        return .green
    }

    private var isCritical: Bool {
        monitor.diagnostics.thermalState == .critical ||
            intelligence.state == .critical ||
            monitor.storageVolumes.contains(where: { $0.health == .critical })
    }

    private var needsAttention: Bool {
        monitor.diagnostics.thermalState == .serious ||
            intelligence.state == .activeSwap ||
            intelligence.state == .pressure ||
            monitor.storageVolumes.contains(where: { $0.health == .warning })
    }

    private var memoryStateLabel: String {
        switch intelligence.state {
        case .stable: return "Normal"
        case .idleSwap: return "Idle swap"
        case .readback: return "Readback"
        case .activeSwap: return "Swap active"
        case .pressure: return "Pressure"
        case .critical: return "Critical"
        }
    }

    private var memoryStateColor: Color {
        switch intelligence.state {
        case .stable: return .green
        case .idleSwap: return .secondary
        case .readback: return .blue
        case .activeSwap, .pressure: return .orange
        case .critical: return .red
        }
    }

    private var memoryInterpretation: String {
        switch intelligence.state {
        case .stable: return "Memory activity is stable."
        case .idleSwap: return "Swap exists, but it is not currently creating disk pressure."
        case .readback: return "Previously swapped data is being read back into memory."
        case .activeSwap: return "RAM pressure is causing sustained swap activity."
        case .pressure: return "macOS reports elevated memory pressure."
        case .critical: return "Memory pressure and swap activity are both critical."
        }
    }

    private var swapMetricValue: String {
        if snapshot.swapUsedBytes == 0 { return "None" }
        switch intelligence.state {
        case .activeSwap, .pressure, .critical:
            return "Active"
        case .readback:
            return "Readback"
        case .idleSwap, .stable:
            return memoryBytes(snapshot.swapUsedBytes)
        }
    }

    private var internalVolume: StorageVolumeSnapshot? {
        monitor.storageVolumes.first(where: { $0.isInternal })
    }

    private var storageFact: String {
        guard let internalVolume else { return "Unavailable" }
        return "\(fileBytes(internalVolume.availableBytes)) free"
    }

    private var storageColor: Color {
        guard let internalVolume else { return .secondary }
        switch internalVolume.health {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var powerFact: String {
        if let percent = monitor.powerSnapshot.batteryPercentClamped {
            return "\(percent)% · \(monitor.powerSnapshot.flow.displayName)"
        }
        return monitor.powerSnapshot.source.displayName
    }

    private var powerSymbol: String {
        switch monitor.powerSnapshot.source {
        case .ac: return "powerplug.fill"
        case .battery: return "battery.75percent"
        case .ups: return "bolt.horizontal.fill"
        case .unknown: return "bolt"
        }
    }

    private var powerColor: Color {
        switch monitor.powerSnapshot.flow {
        case .charging: return .green
        case .discharging: return .orange
        case .idle: return .blue
        case .unavailable: return .secondary
        }
    }

    private var systemFact: String {
        let thermal = monitor.diagnostics.thermalState.displayName
        if let cpu = monitor.diagnostics.cpuUsagePercent {
            return "CPU \(Int(cpu.rounded()))% · \(thermal)"
        }
        return thermal
    }

    private var thermalColor: Color {
        switch monitor.diagnostics.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }

    private func memoryBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private func fileBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
}
