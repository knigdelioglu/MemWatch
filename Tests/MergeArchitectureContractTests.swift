import Foundation

@main
struct MergeArchitectureContractTests {
    static func main() throws {
        let root = FileManager.default.currentDirectoryPath
        let appShell = try read("MemWatchApp.swift", root: root)
        let services = try read("App/AppServices.swift", root: root)
        let displayCoordinator = try read("Display/App/DisplayCoordinator.swift", root: root)
        let displayFeature = try read("Display/DisplayFeature.swift", root: root)
        let scheduler = try read("Core/Polling/PollingScheduler.swift", root: root)
        let migration = try read("Display/App/DisplayPreferencesMigration.swift", root: root)
        let project = try read("MemWatch.xcodeproj/project.pbxproj", root: root)
        let workflow = try read(".github/workflows/ci.yml", root: root)

        expect(count(of: "NSStatusBar.system.statusItem", in: appShell) == 1,
               "MemWatch must create exactly one status item")
        expect(!displayCoordinator.contains("NSStatusBar.system.statusItem"),
               "DisplayCoordinator must not own the status item")
        expect(!displayCoordinator.contains("NSApplicationDelegate"),
               "DisplayCoordinator must not own the application lifecycle")
        expect(appShell.contains("let services = AppServices()"),
               "The app shell must create the shared service container")
        expect(appShell.contains("await DisplayDiagnosticRouter.handleIfRequested()"),
               "CLI diagnostics must run before AppKit bootstrap")
        expect(services.contains("PollingScheduler"),
               "AppServices must own the shared polling scheduler")
        expect(services.contains("MonitoringService(scheduler: scheduler)"),
               "MonitoringService must receive the shared scheduler")
        expect(services.contains("display = DisplayCoordinator(\n"),
               "DisplayCoordinator must receive the shared scheduler")
        expect(displayFeature.contains("protocol DisplayFeatureControlling"),
               "Display must expose a feature boundary")
        expect(scheduler.contains("func register(\n"),
               "PollingScheduler must provide named job ownership")
        expect(migration.contains("fyi.kadir.AmbientSync"),
               "Preference migration must retain the legacy suite")
        expect(project.contains("Samsung_4C2D_76AB_reference.plist")
            && project.contains("Samsung HiDPI reference in Resources"),
               "The HiDPI reference resource must be in the app bundle")
        expect(!FileManager.default.fileExists(
            atPath: (root as NSString).appendingPathComponent("Display/DisplayControl/DisplayRecoveryController.swift")
        ), "The unused duplicate display recovery controller must not ship")
        expect(!FileManager.default.fileExists(
            atPath: (root as NSString).appendingPathComponent("Display/DisplayControl/Experimental/HiDPIRuntimeTraceAnalyzer.swift")
        ), "The unused runtime trace analyzer must not ship")
        expect(!FileManager.default.fileExists(
            atPath: (root as NSString).appendingPathComponent("Display/DisplayControl/DisplayTargetResolver.swift")
        ), "The unused display target resolver must not ship")
        expect(!FileManager.default.fileExists(
            atPath: (root as NSString).appendingPathComponent("Display/DisplayControl/ExternalDisplayBrightnessController.swift")
        ), "The unused external brightness adapter must not ship")
        expect(workflow.contains("Scripts/run_display_feature_tests.sh"),
               "The merged display smoke suite must run in CI")

        print("Merge architecture contract tests passed")
    }

    private static func read(_ relativePath: String, root: String) throws -> String {
        let path = (root as NSString).appendingPathComponent(relativePath)
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func count(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError(message)
        }
    }
}
