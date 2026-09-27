import Foundation

@main
struct TrayUXContractTests {
    static func main() throws {
        let source = try String(contentsOfFile: "MemWatchApp.swift", encoding: .utf8)
        let cleanupSource = try String(contentsOfFile: "Views/CleanupView.swift", encoding: .utf8)
        let settingsSource = try String(contentsOfFile: "Views/UnifiedSettingsView.swift", encoding: .utf8)
        let helperSource = try String(contentsOfFile: "Services/PrivilegedHelperService.swift", encoding: .utf8)
        let coordinatorSource = try String(contentsOfFile: "Services/CleanupCoordinator.swift", encoding: .utf8)

        expect(source.contains("button.title = \"\""), "status item should be icon-only")
        expect(!source.contains("monitor.snapshot.usagePercent)%\""), "raw RAM percentage must not return to the tray")
        expect(source.contains("NSImage(named: \"TrayIcon\")"), "tray should use the dedicated MemWatch template glyph")
        expect(source.contains("systemSymbolName: \"memorychip\""), "tray should retain a safe memory-chip fallback")
        expect(!source.contains("systemSymbolName: presentation.symbolName"), "tray glyph should not change with alert state")
        expect(source.contains("accessibilityDisplayShouldReduceMotion"), "tray animation must respect Reduce Motion")
        expect(source.contains("presentation.pulseOnEntry"), "pulse must be state-transition driven")
        expect(source.contains("tintRole: .orange"), "warning states must have an orange presentation")
        expect(source.contains("tintRole: .red"), "critical states must have a red presentation")
        expect(source.contains("SmartMenuBarRootView"), "smart overview must remain the popover root")
        let willShowSection = sourceSection(
            source,
            from: "func popoverWillShow(",
            to: "func popoverDidShow("
        )
        expect(!willShowSection.isEmpty, "popover will-show delegate must remain present")
        expect(!willShowSection.contains("installDashboardRootView()"), "popover presentation must not replace its hosting controller during will-show")
        let didCloseSection = sourceSection(
            source,
            from: "func popoverDidClose(",
            to: "private func updatePopoverHeight("
        )
        expect(!didCloseSection.isEmpty, "popover did-close delegate must remain present")
        expect(!didCloseSection.contains("installDashboardRootView()"), "popover close must not replace its hosting controller")
        expect(source.contains("installDashboardRootView()\n            popover.show("), "dashboard hosting controller must be installed before presentation")
        expect(!source.contains("Mac is doing well"), "health warning card must not be present in the overview")
        expect(source.contains("let openCleanup: () -> Void"), "smart overview must receive a cleanup action")
        expect(source.contains("cleanupCard"), "cleanup must have a visible card in the normal left-click overview")
        expect(source.contains("Text(\"Cleanup & Storage\")"), "cleanup entry must be clearly named in the normal overview")
        expect(source.contains("Button(action: openCleanup)"), "visible cleanup card must open the cleanup window")
        expect(source.contains("displayDashboardCard"), "main overview must expose display and sleep controls")
        expect(source.contains("builtInDisplaySection"), "display card must include built-in display controls")
        expect(source.contains("Yerleşik ekran parlaklığı"), "built-in display brightness slider must be present with accessibility label")
        expect(source.contains("externalDisplaySection"), "display card must include external display controls")
        expect(source.contains("Harici ekran parlaklığı"), "external display brightness slider must be present with accessibility label")
        expect(source.contains("display.toggleExternalDisplayConnection()"), "external display disconnect/reconnect must be accessible from main overview")
        expect(source.contains("sleepTimerSection"), "main overview must expose screen sleep timer controls")
        expect(source.contains("selectKeepAwakeDuration"), "sleep timer must immediately apply and persist duration")
        expect(source.contains("PopoverCardExpansionState"), "overview cards must use explicit expansion state tracking")
        expect(source.contains("cardExpansionState.collapseAll()"), "popover lifecycle must reset all expanded cards to collapsed")
        expect(source.contains("NSWindow.didResignKeyNotification"), "backgrounding popover window must reset cards to collapsed")
        expect(source.contains("accessibilityLabel(\"Memory card,"), "collapsible memory card must provide accessibility state")
        expect(source.contains("accessibilityLabel(\"GPU and System card,"), "collapsible system card must provide accessibility state")
        expect(source.contains("accessibilityLabel(\"Storage card,"), "collapsible storage card must provide accessibility state")
        expect(!source.contains("panelSize = NSSize(width: 390, height: 860)"), "popover must not use fixed 860pt height")
        expect(!source.contains("height: windowLayout ? nil : 860"), "overview must not hardcode 860pt height")
        expect(source.contains("maximumPopoverHeight"), "popover must dynamically calculate maximum height based on screen bounds")
        expect(source.contains("updatePopoverHeight"), "popover must update height from content measurement")
        expect(source.contains("PopoverContentHeightPreferenceKey"), "overview must report content height via preference key")
        expect(settingsSource.contains("KeepAwakeControlsView(display: display)"), "settings should share the main keep-awake controls")
        expect(source.contains("title: \"Cleanup & Storage…\""), "right-click cleanup shortcut must remain available")

        expect(cleanupSource.contains("Text(\"Cleanup\")"), "cleanup window should be present")
        expect(cleanupSource.contains("showAdvancedDetails"), "permissions, storage, and maintenance details should remain collapsed by default")
        expect(cleanupSource.contains("showApplicationDetails"), "application cleanup choices should remain collapsed by default")
        expect(cleanupSource.contains("Text(bytes(coordinator.automaticSafeBytes))"), "safe cleanup amount should be the primary summary")
        expect(cleanupSource.contains("How cleanup safety labels work"), "cleanup must explain deletion scope before actions")
        expect(cleanupSource.contains("title: \"SAFE\""), "safe scope must be explicitly explained")
        expect(cleanupSource.contains("title: \"REVIEW\""), "review scope must be explicitly explained")
        expect(cleanupSource.contains("title: \"PROTECTED\""), "protected scope must be explicitly explained")
        expect(cleanupSource.contains("Button(\"Clean Safe Items\")"), "primary cleanup action must clearly name the safe-only scope")
        expect(cleanupSource.contains("Button(\"Preview Safe Cleanup\")"), "dry run action must be clearly named")
        expect(cleanupSource.contains("friendlyIssueMessage"), "scan problems should be translated into user-facing language")
        expect(!cleanupSource.contains("Text(issue.message)"), "raw scanner messages must not appear in the default user interface")
        expect(cleanupSource.contains("Applications to close during cleanup"), "cleanup should warn about applications that will be closed")
        expect(cleanupSource.contains("setApplicationCleanupEnabled"), "cleanup should offer an application-level opt-out")
        expect(helperSource.contains("func register() async -> Bool"), "helper registration must not block the cleanup window")
        expect(helperSource.contains("Task.detached"), "administrator installation must run off the main actor")
        expect(helperSource.contains("connectionVerified"), "helper availability must be based on a live XPC check")
        expect(helperSource.contains("private func registerWithSMAppService() async -> Bool"), "team-signed helper registration must have an explicit retry path")
        expect(helperSource.contains("recreate the launchd submission"), "stale helper registrations must be recreated on retry")
        expect(coordinatorSource.contains("if currentPreferences.privilegedOperationsEnabled"), "scan should rediscover an installed helper after relaunch")
        expect(coordinatorSource.contains("await helperService.verifyConnection()"), "startup should verify an installed helper before showing it as missing")
        expect(coordinatorSource.contains("helperRefreshTask = Task"), "manual permission refresh should run a live helper check")
        expect(coordinatorSource.contains("await self.helperService.verifyConnection()"), "manual permission refresh should update helper connectivity")
        expect(coordinatorSource.contains("helperService.objectWillChange"), "cleanup should forward helper state changes to its view")
        expect(coordinatorSource.contains("fullDiskAccessService.objectWillChange"), "cleanup should forward disk permission changes to its view")
        expect(cleanupSource.contains("helperService.lastError"), "helper installation failures must remain visible in the cleanup UI")
        expect(cleanupSource.contains("Could not install privileged helper"), "helper installation error details must be visible near the action")
        expect(cleanupSource.contains("state == .requiresApproval"), "helper approval should have a dedicated UI state")
        expect(cleanupSource.contains("openHelperApprovalSettings"), "approval UI should open System Settings directly")

        print("Tray UX contract tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func sourceSection(_ source: String, from startMarker: String, to endMarker: String) -> String {
        guard
            let start = source.range(of: startMarker),
            let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex)
        else {
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
