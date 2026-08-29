import Foundation

@main
struct TrayUXContractTests {
    static func main() throws {
        let source = try String(contentsOfFile: "MemWatchApp.swift", encoding: .utf8)
        let cleanupSource = try String(contentsOfFile: "Views/CleanupView.swift", encoding: .utf8)
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
        expect(source.contains("No action is needed"), "overview should communicate when no action is required")
        expect(source.contains("let openCleanup: () -> Void"), "smart overview must receive a cleanup action")
        expect(source.contains("cleanupCard"), "cleanup must have a visible card in the normal left-click overview")
        expect(source.contains("Text(\"Cleanup & Storage\")"), "cleanup entry must be clearly named in the normal overview")
        expect(source.contains("Button(action: openCleanup)"), "visible cleanup card must open the cleanup window")
        expect(source.contains("title: \"Cleanup & Storage…\""), "right-click cleanup shortcut must remain available")

        expect(cleanupSource.contains("Label(\"Derin Temizleme\""), "cleanup window should use Turkish UI text")
        expect(cleanupSource.contains("Label(\"Ne silinecek?\""), "cleanup must explain deletion scope before actions")
        expect(cleanupSource.contains("title: \"GÜVENLİ\""), "safe scope must be explicitly explained")
        expect(cleanupSource.contains("title: \"İNCELE\""), "review scope must be explicitly explained")
        expect(cleanupSource.contains("title: \"KORUNAN\""), "protected scope must be explicitly explained")
        expect(cleanupSource.contains("Ana düğme bunları silmez"), "review items must be described as opt-in only")
        expect(cleanupSource.contains("Güvenli \\(bytes(coordinator.automaticSafeBytes)) Temizle"), "primary cleanup action must clearly name the safe-only scope")
        expect(cleanupSource.contains("Silmeden Kontrol Et"), "dry run should use understandable Turkish wording")
        expect(cleanupSource.contains("Uygulamayı kapat ve yeniden tara"), "active app cleanup should offer a close-and-rescan action")
        expect(cleanupSource.contains("Çalışan uygulamalar"), "cleanup should warn about applications that will be closed")
        expect(cleanupSource.contains("setApplicationCleanupEnabled"), "cleanup should offer an application-level opt-out")
        expect(helperSource.contains("func register() async -> Bool"), "helper registration must not block the cleanup window")
        expect(helperSource.contains("Task.detached"), "administrator installation must run off the main actor")
        expect(helperSource.contains("connectionVerified"), "helper availability must be based on a live XPC check")
        expect(coordinatorSource.contains("if currentPreferences.privilegedOperationsEnabled"), "scan should rediscover an installed helper after relaunch")
        expect(coordinatorSource.contains("await helperService.verifyConnection()"), "startup should verify an installed helper before showing it as missing")
        expect(coordinatorSource.contains("helperRefreshTask = Task"), "manual permission refresh should run a live helper check")
        expect(coordinatorSource.contains("await self.helperService.verifyConnection()"), "manual permission refresh should update helper connectivity")
        expect(cleanupSource.contains("helperService.lastError"), "helper installation failures must remain visible in the cleanup UI")
        expect(cleanupSource.contains("state == .requiresApproval"), "helper approval should have a dedicated UI state")
        expect(cleanupSource.contains("openHelperApprovalSettings"), "approval UI should open System Settings directly")
        expect(!cleanupSource.contains("Label(\"Dry Run\""), "English dry-run label must not return to cleanup UI")

        print("Tray UX contract tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
