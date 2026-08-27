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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(monitor: monitor)
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

    private let monitor: MonitoringService
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var pendingSingleClick: DispatchWorkItem?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var previousTrayPresentation: TrayPresentation?

    init(monitor: MonitoringService) {
        self.monitor = monitor
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

    /// Rebuild the SwiftUI root before every presentation. MenuBarView starts at
    /// `.dashboard`, so reopening MemWatch never restores a previously selected
    /// detail route. Keeping the AppKit popover and SwiftUI root at the same
    /// 430-point width also prevents dashboard and memory cards from clipping.
    private func installDashboardRootView() {
        popover.contentSize = Self.panelSize
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(monitor: monitor)
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
        let image = NSImage(
            systemSymbolName: presentation.symbolName,
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
            showQuitMenu(relativeTo: sender)
            return
        }

        pendingSingleClick?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak sender] in
            guard let self, let sender else { return }
            self.togglePopover(relativeTo: sender)
        }
        pendingSingleClick = workItem

        // Small delay lets a second click turn into the requested Quit menu
        // instead of opening and immediately closing the details popover.
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

    private func showQuitMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit MemWatch",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: quitItem,
            at: NSPoint(x: 0, y: button.bounds.minY),
            in: button
        )
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
