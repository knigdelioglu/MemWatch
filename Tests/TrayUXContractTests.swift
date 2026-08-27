import Foundation

@main
struct TrayUXContractTests {
    static func main() throws {
        let source = try String(contentsOfFile: "MemWatchApp.swift", encoding: .utf8)

        expect(source.contains("button.title = \"\""), "status item should be icon-only")
        expect(!source.contains("monitor.snapshot.usagePercent)%\""), "raw RAM percentage must not return to the tray")
        expect(source.contains("systemSymbolName: \"memorychip\""), "tray should keep one stable MemWatch glyph across states")
        expect(!source.contains("systemSymbolName: presentation.symbolName"), "tray glyph should not change with alert state")
        expect(source.contains("accessibilityDisplayShouldReduceMotion"), "tray animation must respect Reduce Motion")
        expect(source.contains("presentation.pulseOnEntry"), "pulse must be state-transition driven")
        expect(source.contains("tintRole: .orange"), "warning states must have an orange presentation")
        expect(source.contains("tintRole: .red"), "critical states must have a red presentation")
        expect(source.contains("SmartMenuBarRootView"), "smart overview must remain the popover root")
        expect(source.contains("No action is needed"), "overview should communicate when no action is required")

        print("Tray UX contract tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
