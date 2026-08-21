import AppKit
import Combine
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

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: MonitoringService
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var pendingSingleClick: DispatchWorkItem?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

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
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .medium
        )
        button.toolTip = "MemWatch — single-click for details, double-click for Quit"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(monitor: monitor)
                .frame(width: 380, height: 640)
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

        let image = NSImage(
            systemSymbolName: menuBarSymbol,
            accessibilityDescription: "MemWatch"
        )
        image?.isTemplate = true

        button.image = image
        button.title = " \(monitor.snapshot.usagePercent)%"
        button.setAccessibilityLabel(
            "MemWatch, memory usage \(monitor.snapshot.usagePercent) percent"
        )
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

    private var menuBarSymbol: String {
        if monitor.diagnostics.thermalState == .critical {
            return "thermometer.high"
        }
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
