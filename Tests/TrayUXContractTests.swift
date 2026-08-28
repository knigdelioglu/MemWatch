import Foundation

@main
struct TrayUXContractTests {
    static func main() throws {
        let source = try String(contentsOfFile: "MemWatchApp.swift", encoding: .utf8)

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

        print("Tray UX contract tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
