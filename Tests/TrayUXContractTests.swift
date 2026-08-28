import Foundation

@main
struct TrayUXContractTests {
    static func main() throws {
        let source = try String(contentsOfFile: "MemWatchApp.swift", encoding: .utf8)
        let cleanupSource = try String(contentsOfFile: "Views/CleanupView.swift", encoding: .utf8)

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
        expect(cleanupSource.contains("Güvenli \\(bytes(automaticSafeBytes)) Temizle"), "primary cleanup action must clearly name the safe-only scope")
        expect(cleanupSource.contains("Silmeden Kontrol Et"), "dry run should use understandable Turkish wording")
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
