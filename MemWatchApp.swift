import AppKit
import Combine
import QuartzCore
import SwiftUI

@main
struct MemWatchApp {
    /// Keep command-line diagnostics independent from AppKit's GUI bootstrap.
    static func main() {
        if runCommandLineDiagnosticsIfRequested() {
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    private static let diagnosticArguments: Set<String> = [
        "--release-bundle-smoke",
        "--display-discovery-diagnostic",
        "--diagnostic",
        "--hidpi-mode-pool-diagnostic",
        "--cgs-mode-enumeration",
        "--cgs-mode74-without-betterdisplay",
        "--cgs-mode74-apply-experiment",
        "--hidpi-system-snapshot",
        "--hidpi-activation-spike",
        "--memory-diagnostics"
    ]

    private static func runCommandLineDiagnosticsIfRequested() -> Bool {
        guard CommandLine.arguments.dropFirst().contains(where: diagnosticArguments.contains) else {
            return false
        }

        if CommandLine.arguments.contains("--memory-diagnostics") {
            MemoryRuntimeDiagnostic.run()
            return true
        }

        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            _ = await DisplayDiagnosticRouter.handleIfRequested()
            semaphore.signal()
        }
        semaphore.wait()
        return true
    }
}

private enum MemoryRuntimeDiagnostic {
    static func run() {
        let snapshot = MemoryCollector().collect()
        let diagnostics = SystemDiagnosticsCollector().collectWithDiagnostics(
            includeProcesses: true,
            processLimit: Int.max
        )
        let processMemory = diagnostics.processMemory

        print("MemWatch memory diagnostics")
        print("Physical Memory: \(bytes(snapshot.totalBytes))")
        print("Memory Used: \(bytes(snapshot.usedBytes))")
        print("App Memory: \(bytes(snapshot.appMemoryBytes))")
        print("Wired: \(bytes(snapshot.wiredBytes))")
        print("Compressed: \(bytes(snapshot.compressedBytes))")
        print("Cached Files: \(bytes(snapshot.cachedFilesBytes))")
        print("True Free: \(bytes(snapshot.freeBytes))")
        print("Available: \(bytes(snapshot.availableBytes))")
        print("Swap Used: \(bytes(snapshot.swapUsedBytes))")
        print("Swap Total: \(bytes(snapshot.swapTotalBytes))")
        print(
            "rawBytes total=\(snapshot.totalBytes) used=\(snapshot.usedBytes) "
                + "app=\(snapshot.appMemoryBytes) wired=\(snapshot.wiredBytes) "
                + "compressed=\(snapshot.compressedBytes) cached=\(snapshot.cachedFilesBytes) "
                + "trueFree=\(snapshot.freeBytes) available=\(snapshot.availableBytes) "
                + "swapUsed=\(snapshot.swapUsedBytes)"
        )

        let componentUsed = clampedSum(
            [snapshot.appMemoryBytes, snapshot.wiredBytes, snapshot.compressedBytes],
            limit: snapshot.totalBytes
        )
        let headroomUsed = subtracting(
            subtracting(snapshot.totalBytes, snapshot.freeBytes),
            snapshot.cachedFilesBytes
        )
        print("componentUsed: \(bytes(componentUsed))")
        print("headroomUsed: \(bytes(headroomUsed))")
        print("usedDifference(component-headroom): \(signedDifference(componentUsed, headroomUsed))")
        print("accountingClamp: per-bucket and total values are clamped to Physical Memory; arithmetic is saturating")
        print("pressureClassification=\(snapshot.pressure.rawValue)")

        guard let processMemory else {
            print("process-groups: unavailable")
            print("totalDiagnosticsDuration: \(duration(diagnostics.totalDuration))")
            return
        }

        print("PID count: \(processMemory.inventoryPIDCount)")
        print("readable PID count: \(processMemory.inventory.count)")
        print("unavailable PID count: \(processMemory.unavailablePIDs.count)")
        print("application root count: \(processMemory.applicationRoots.count)")
        for root in processMemory.applicationRoots {
            print(
                "applicationRootPID=\(root.pid) name=\(root.name) "
                    + "bundleIdentifier=\(root.bundleIdentifier ?? "unavailable") "
                    + "bundlePath=\(root.bundlePath ?? "unavailable")"
            )
        }
        print("inventory duration: \(duration(processMemory.inventoryDuration))")
        print("grouping duration: \(duration(processMemory.groupingDuration))")
        print("total process collection duration: \(duration(processMemory.totalDuration))")
        print("total diagnostics duration: \(duration(diagnostics.totalDuration))")
        print("duplicateAssignedPIDCount: \(processMemory.aggregation.duplicateAssignedPIDCount)")

        if processMemory.unavailablePIDs.isEmpty {
            print("source=unavailable pidCount=0")
        } else {
            let pids = processMemory.unavailablePIDs.map(String.init).joined(separator: ",")
            print("source=unavailable pidCount=\(processMemory.unavailablePIDs.count) pids=\(pids)")
        }

        let entriesByPID = Dictionary(
            uniqueKeysWithValues: processMemory.inventory.map { ($0.pid, $0) }
        )
        print("process-groups:")
        for process in processMemory.aggregation.snapshots {
            let entries = process.processIDs.compactMap { entriesByPID[$0] }
            let rssBytes = saturatingSum(entries.compactMap(\.residentBytes))
            let rssPIDCount = entries.reduce(into: 0) { count, entry in
                if let residentBytes = entry.residentBytes, residentBytes > 0 {
                    count += 1
                }
            }
            let physicalFootprintPIDCount = entries.reduce(into: 0) { count, entry in
                if entry.memoryMetric == .physicalFootprint {
                    count += 1
                }
            }
            let residentFallbackPIDCount = entries.reduce(into: 0) { count, entry in
                if entry.memoryMetric == .residentFallback {
                    count += 1
                }
            }
            let ownedPIDs = process.processIDs.map(String.init).joined(separator: ",")

            print(
                "groupName=\(process.name) "
                    + "groupKind=\(process.groupKind.rawValue) "
                    + "total=\(bytes(process.memoryBytes)) "
                    + "pidCount=\(process.processCount) "
                    + "physicalFootprintPIDCount=\(physicalFootprintPIDCount) "
                    + "residentFallbackPIDCount=\(residentFallbackPIDCount) "
                    + "rssTotal=\(bytes(rssBytes)) "
                    + "rssPIDCount=\(rssPIDCount) "
                    + "ownedPIDs=\(ownedPIDs)"
            )
        }

        print("pid-measurements:")
        for entry in processMemory.inventory.sorted(by: { $0.pid < $1.pid }) {
            let owner = ownerLabel(processMemory.aggregation.ownershipByPID[entry.pid])
            let physical = entry.physicalFootprintBytes.map(String.init) ?? "unavailable"
            let resident = entry.residentBytes.map(String.init) ?? "unavailable"
            print(
                "pid=\(entry.pid) owner=\(owner) selected=\(entry.memoryMetric.rawValue) "
                    + "ri_phys_footprint=\(physical) pti_resident_size=\(resident)"
            )
        }
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private static func duration(_ value: TimeInterval) -> String {
        String(format: "%.4fs", value)
    }

    private static func clampedSum(_ values: [UInt64], limit: UInt64) -> UInt64 {
        min(saturatingSum(values), limit)
    }

    private static func saturatingSum(_ values: [UInt64]) -> UInt64 {
        values.reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? UInt64.max : sum
        }
    }

    private static func subtracting(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : 0
    }

    private static func signedDifference(_ lhs: UInt64, _ rhs: UInt64) -> String {
        if lhs >= rhs {
            return "+\(bytes(lhs - rhs))"
        }
        return "-\(bytes(rhs - lhs))"
    }

    private static func ownerLabel(_ owner: ProcessMemoryGroupOwner?) -> String {
        guard let owner else { return "unavailable" }
        switch owner {
        case let .application(rootPID):
            return "application:\(rootPID)"
        case let .standalone(pid):
            return "standalone:\(pid)"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let services = AppServices()
        self.services = services
        services.start()
        statusBarController = StatusBarController(
            monitor: services.monitoring,
            cleanup: services.cleanup,
            display: services.display
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        services?.stop()
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
    private static let panelSize = NSSize(width: 390, height: 860)
    private static let mainWindowSize = NSSize(width: 1120, height: 760)
    private static let mainWindowMinimumSize = NSSize(width: 900, height: 680)

    private let monitor: MonitoringService
    private let cleanup: CleanupCoordinator
    private let display: DisplayCoordinator
    private let mainWindowNavigation = MainWindowNavigation()
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var mainWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var previousTrayPresentation: TrayPresentation?

    init(monitor: MonitoringService, cleanup: CleanupCoordinator, display: DisplayCoordinator) {
        self.monitor = monitor
        self.cleanup = cleanup
        self.display = display
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        configurePopover()
        observeMonitor()
        updateStatusButton()
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
            rootView: SmartMenuBarRootView(
                monitor: monitor,
                openDisplays: { [weak self] in
                    self?.openDisplayWindow()
                },
                openCleanup: { [weak self] in
                    self?.openCleanupWindow()
                },
                openSettings: { [weak self] in
                    self?.openSettings()
                }
            )
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

        display.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
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

        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            closePopover()
            showContextMenu(relativeTo: sender)
            return
        }

        togglePopover(relativeTo: sender)
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            monitor.refresh(forceStorage: true, forceDiagnostics: true)
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()

        let cleanupItem = NSMenuItem(
            title: "Cleanup & Storage…",
            action: #selector(openCleanupWindow),
            keyEquivalent: ""
        )
        cleanupItem.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Cleanup & Storage"
        )
        cleanupItem.target = self
        menu.addItem(cleanupItem)

        let displayItem = NSMenuItem(
            title: "Displays & Awake…",
            action: #selector(openDisplayWindow),
            keyEquivalent: ""
        )
        displayItem.image = NSImage(
            systemSymbolName: "display",
            accessibilityDescription: "Displays & Awake"
        )
        displayItem.target = self
        menu.addItem(displayItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Settings"
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
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
    private func openSettings() {
        showMainWindow(selection: .settings)
    }

    @objc
    private func openCleanupWindow() {
        showMainWindow(selection: .cleanup)
        if cleanup.scanResult == nil, !cleanup.isBusy {
            cleanup.startScan()
        }
    }

    @objc
    private func openDisplayWindow() {
        showMainWindow(selection: .displays)
    }

    private func showMainWindow(selection: WindowNavigationSelection) {
        closePopover()
        mainWindowNavigation.selection = selection

        if let window = mainWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: MainWindowRootView(
            monitor: monitor,
            cleanup: cleanup,
            display: display,
            navigation: mainWindowNavigation
        ))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MemWatch"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.mainWindowSize)
        window.minSize = Self.mainWindowMinimumSize
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        mainWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { return }
        monitor.refresh(forceStorage: true, forceDiagnostics: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
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
            if let displayPresentation = displayTrayPresentation {
                return displayPresentation
            }
            return TrayPresentation(
                symbolName: "memorychip",
                tintRole: .system,
                accessibilityDescription: "MemWatch, Mac memory is healthy",
                toolTip: "MemWatch — Memory healthy",
                pulseOnEntry: false
            )
        case .idleSwap:
            if let displayPresentation = displayTrayPresentation {
                return displayPresentation
            }
            return TrayPresentation(
                symbolName: "memorychip",
                tintRole: .system,
                accessibilityDescription: "MemWatch, swap contains idle data but memory is healthy",
                toolTip: "MemWatch — Idle swap, no current pressure",
                pulseOnEntry: false
            )
        case .readback:
            if let displayPresentation = displayTrayPresentation {
                return displayPresentation
            }
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

    private var displayTrayPresentation: TrayPresentation? {
        if display.keepAwakeState.featureEnabled && display.isAwakeAssertionActive {
            return TrayPresentation(
                symbolName: "moon.zzz.fill",
                tintRole: .system,
                accessibilityDescription: "MemWatch, display keep-awake session is active",
                toolTip: "MemWatch — Display keep-awake active",
                pulseOnEntry: false
            )
        }

        guard display.currentDisplayInfo != nil else { return nil }
        let mode = display.autoBrightnessEnabled ? "automatic brightness" : "manual brightness"
        return TrayPresentation(
            symbolName: "sun.max.fill",
            tintRole: .system,
            accessibilityDescription: "MemWatch, external display connected with \(mode)",
            toolTip: "MemWatch — External display connected",
            pulseOnEntry: false
        )
    }
}

@MainActor
private final class MainWindowNavigation: ObservableObject {
    @Published var selection: WindowNavigationSelection = .displays
}

@MainActor
private struct MainWindowRootView: View {
    @ObservedObject var monitor: MonitoringService
    @ObservedObject var cleanup: CleanupCoordinator
    @ObservedObject var display: DisplayCoordinator
    @ObservedObject var navigation: MainWindowNavigation

    var body: some View {
        HStack(spacing: 0) {
            WindowSidebar(
                selection: navigation.selection,
                onOpenOverview: { navigation.selection = .overview },
                onOpenCleanup: { navigation.selection = .cleanup },
                onOpenDisplays: { navigation.selection = .displays },
                onOpenSettings: { navigation.selection = .settings }
            )
            content
        }
        .frame(minWidth: 900, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.selection {
        case .overview:
            SmartMenuBarRootView(
                monitor: monitor,
                openDisplays: { navigation.selection = .displays },
                openCleanup: { navigation.selection = .cleanup },
                openSettings: { navigation.selection = .settings },
                windowLayout: true
            )
            .frame(maxWidth: 620, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .cleanup:
            CleanupView(coordinator: cleanup, showsNavigation: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .displays:
            DisplayFeatureView(display: display, usesWindowLayout: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .settings:
            UnifiedSettingsView(monitor: monitor, display: display)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SmartMenuBarRootView: View {
    @ObservedObject var monitor: MonitoringService
    let openDisplays: () -> Void
    let openCleanup: () -> Void
    let openSettings: () -> Void
    var windowLayout = false
    @State private var showingTechnicalDetails = false

    private var snapshot: MemorySnapshot { monitor.snapshot }
    private var intelligence: SwapIntelligenceResult { monitor.intelligence }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if showingTechnicalDetails {
                MenuBarView(monitor: monitor, windowLayout: windowLayout)
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
        .frame(width: windowLayout ? nil : 390, height: windowLayout ? nil : 860)
        .frame(maxWidth: windowLayout ? .infinity : nil, maxHeight: windowLayout ? .infinity : nil)
        .animation(.easeInOut(duration: 0.16), value: showingTechnicalDetails)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                dashboardHeader
                memoryFocusCard
                systemDashboardCard
                storageDashboardCard
                powerDashboardCard
                smartAlertsCard
                controlsRow
            }
            .padding(12)
        }
    }

    private var dashboardHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 31, height: 31)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("MemWatch").font(.headline)
                Text("A cleaner, healthier Mac").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Label(healthName == "Good" ? "All Systems Good" : healthName, systemImage: healthSymbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(healthColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(healthColor.opacity(0.1), in: Capsule())
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 27, height: 27)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
    }

    private var memoryFocusCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label("Memory", systemImage: "memorychip")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(memoryBytes(snapshot.usedBytes)) of \(memoryBytes(snapshot.totalBytes))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text("\(snapshot.usagePercent)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(snapshot.usagePercent) / 100)
                .tint(memoryStateColor)
                .controlSize(.small)
            HStack {
                Text("Memory Pressure · \(monitor.pressure.displayName)")
                Spacer()
                Text("Swap Used · \(memoryBytes(snapshot.swapUsedBytes))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if monitor.systemHistory.count > 1 {
                DashboardSparkline(
                    values: monitor.systemHistory.map(\.memoryUsagePercent),
                    tint: memoryStateColor
                )
                .accessibilityLabel("Recent memory usage trend")
            }
        }
        .padding(11)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var systemDashboardCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label("CPU & System", systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(monitor.diagnostics.cpuUsagePercent.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            HStack(spacing: 9) {
                Text("Load")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let cpu = monitor.diagnostics.cpuUsagePercent {
                    ProgressView(value: min(max(cpu / 100, 0), 1))
                        .tint(.blue)
                        .controlSize(.small)
                } else {
                    Text("Unavailable")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(cpuTemperatureText)
                        .font(.caption2.monospacedDigit().weight(.medium))
                    Text(monitor.diagnostics.thermalState.displayName)
                        .font(.system(size: 9))
                        .foregroundStyle(thermalColor)
                }
            }
            if monitor.systemHistory.count > 1 {
                DashboardSparkline(
                    values: monitor.systemHistory.map(\.cpuUsagePercent),
                    tint: .blue
                )
                .accessibilityLabel("Recent CPU load trend")
            }
            HStack {
                Text("Low Power Mode")
                Spacer()
                Text(monitor.diagnostics.lowPowerModeEnabled ? "On" : "Off")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            Text("Top Memory Usage")
                .font(.caption.weight(.semibold))
            if monitor.diagnostics.topProcesses.isEmpty {
                Text("No process snapshot available yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.diagnostics.topProcesses.prefix(5)) { process in
                    HStack(spacing: 7) {
                        Image(systemName: process.groupKind.symbolName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 13)
                        Text(process.name)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(memoryBytes(process.memoryBytes))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(11)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var storageDashboardCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Storage", systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))
            if monitor.storageVolumes.isEmpty {
                Text("Storage information unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dashboardStorageVolumes) { volume in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(volume.name).font(.caption)
                                Text("\(fileBytes(volume.usedBytes)) used of \(fileBytes(volume.totalBytes))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(volume.usagePercent)%")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(storageHealthColor(volume.health))
                        }
                        ProgressView(value: min(max(Double(volume.usagePercent) / 100, 0), 1))
                            .tint(storageHealthColor(volume.health))
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(11)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var powerDashboardCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: powerSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(powerColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Power").font(.subheadline.weight(.semibold))
                    Text(powerSummary).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let watts = monitor.powerSnapshot.systemLoadWatts {
                    Text(String(format: "%.1f W", watts))
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
            }
            if monitor.powerHistory.compactMap(\.systemLoadWatts).count > 1 {
                DashboardSparkline(
                    values: monitor.powerHistory.compactMap(\.systemLoadWatts),
                    tint: .green
                )
                .frame(height: 24)
                .accessibilityLabel("Recent power usage trend")
            }
        }
        .padding(11)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var smartAlertsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Smart Alerts", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                if !activeSystemAlerts.isEmpty {
                    Text("\(activeSystemAlerts.count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.red, in: Circle())
                        .accessibilityLabel("\(activeSystemAlerts.count) active alerts")
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { monitor.notificationsEnabled },
                    set: { monitor.setNotificationsEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            if activeSystemAlerts.isEmpty {
                Label("No current system alerts", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeSystemAlerts, id: \.self) { alert in
                    Label(alert, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            HStack {
                Text("Notification permission")
                Spacer()
                Text(monitor.notificationAuthorization.displayName)
                    .foregroundStyle(notificationAuthorizationColor)
            }
            .font(.caption2)
            if monitor.notificationAuthorization == .denied {
                Button("Open Notification Settings") { monitor.openNotificationSettings() }
                    .buttonStyle(.link)
                    .font(.caption2)
            }
        }
        .padding(11)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var activeSystemAlerts: [String] {
        var alerts: [String] = []
        if monitor.pressure != .normal { alerts.append("Memory pressure is \(monitor.pressure.displayName.lowercased())") }
        if intelligence.state == .activeSwap || intelligence.state == .pressure || intelligence.state == .critical {
            alerts.append("Active swap usage (\(memoryBytes(snapshot.swapUsedBytes)))")
        }
        if let volume = monitor.storageVolumes.first(where: { $0.health == .warning || $0.health == .critical }) {
            alerts.append("\(volume.name) storage is almost full")
        }
        if monitor.diagnostics.thermalState == .serious || monitor.diagnostics.thermalState == .critical {
            alerts.append("System is running hot")
        }
        return alerts
    }

    private var healthName: String {
        if monitor.diagnostics.thermalState == .critical || intelligence.state == .critical ||
            monitor.pressure == .critical ||
            monitor.storageVolumes.contains(where: { $0.health == .critical }) { return "Critical" }
        if monitor.diagnostics.thermalState == .serious || intelligence.state == .pressure ||
            intelligence.state == .activeSwap || monitor.pressure == .warning ||
            monitor.storageVolumes.contains(where: { $0.health == .warning }) {
            return "Attention"
        }
        return "Good"
    }

    private var healthColor: Color {
        switch healthName {
        case "Critical": return .red
        case "Attention": return .orange
        default: return .green
        }
    }

    private var healthSymbol: String {
        switch healthName {
        case "Critical": return "exclamationmark.octagon.fill"
        case "Attention": return "exclamationmark.triangle.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var notificationAuthorizationColor: Color {
        monitor.notificationAuthorization.canDeliver ? .green : .secondary
    }

    private func storageHealthColor(_ health: StorageHealthState) -> Color {
        switch health {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Button(action: openDisplays) {
                Label("Displays", systemImage: "display")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: openCleanup) {
                Label("Cleanup", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

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

    private var dashboardStorageVolumes: [StorageVolumeSnapshot] {
        let internalVolume = monitor.storageVolumes.first(where: \.isInternal)
        let externalVolume = monitor.storageVolumes.first(where: { !$0.isInternal })
        return [internalVolume, externalVolume].compactMap { $0 }
    }

    private var powerSummary: String {
        let power = monitor.powerSnapshot
        var parts: [String] = []
        if let percent = power.batteryPercentClamped {
            parts.append("Battery \(percent)%")
        } else {
            parts.append(power.source.displayName)
        }
        parts.append(power.flow.displayName)

        let remainingMinutes: Int?
        switch power.flow {
        case .discharging: remainingMinutes = power.timeToEmptyMinutes
        case .charging: remainingMinutes = power.timeToFullMinutes
        case .idle, .unavailable: remainingMinutes = nil
        }
        if let remainingMinutes {
            let hours = remainingMinutes / 60
            let minutes = remainingMinutes % 60
            parts.append(hours > 0 ? "\(hours)h \(minutes)m remaining" : "\(minutes)m remaining")
        }
        return parts.joined(separator: " · ")
    }

    private var cpuTemperatureText: String {
        guard let temperature = monitor.thermalSnapshot.aggregates[.cpu]?.currentCelsius else {
            return "Temperature unavailable"
        }
        return String(format: "%.0f°C", temperature)
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

private struct DashboardSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let samples = values.filter(\.isFinite)
            guard samples.count > 1, size.width > 1, size.height > 1,
                  let minimum = samples.min(), let maximum = samples.max() else { return }

            let range = maximum - minimum
            let step = size.width / CGFloat(samples.count - 1)
            var line = Path()
            for (index, value) in samples.enumerated() {
                let x = CGFloat(index) * step
                let normalized = range < 0.001 ? 0.5 : CGFloat((value - minimum) / range)
                let y = size.height - normalized * (size.height - 2) - 1
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    line.move(to: point)
                } else {
                    line.addLine(to: point)
                }
            }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(tint.opacity(0.1)))
            context.stroke(
                line,
                with: .color(tint),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 26)
    }
}
