import Foundation

@main
struct MergeArchitectureContractTests {
    static func main() throws {
        let root = FileManager.default.currentDirectoryPath
        let appShell = try read("MemWatchApp.swift", root: root)
        let services = try read("App/AppServices.swift", root: root)
        let displayCoordinator = try read("Display/App/DisplayCoordinator.swift", root: root)
        let displayRuntime = try read("Display/App/DisplayCoordinator+DisplayRuntime.swift", root: root)
        let displayRuntimeState = try read("Display/App/DisplayRuntimeState.swift", root: root)
        let displayCoordinatorState = try read("Display/App/DisplayCoordinator+State.swift", root: root)
        let displayConnection = try read("Display/DisplayControl/DisplayConnectionController.swift", root: root)
        let displayComposition = try read("Display/App/DisplayFeatureComposition.swift", root: root)
        let displayFeatures = try read("Display/App/DisplayCoordinator+Features.swift", root: root)
        let displayBrightnessRuntime = try read("Display/App/DisplayCoordinator+BrightnessRuntime.swift", root: root)
        let privateBackend = try read("Display/DisplayControl/PrivateDisplayConnectionBackend.swift", root: root)
        let migrationRuntime = try read("Display/App/LegacyAmbientSyncMigration.swift", root: root)
        let hiDPIReapply = try read("Display/DisplayControl/HiDPIReapplyService.swift", root: root)
        let hiDPILifecycle = try read("Display/DisplayControl/HiDPIReapplyLifecycle.swift", root: root)
        let m1DDC = try read("Display/DisplayControl/M1DDCDisplayController.swift", root: root)
        let keepAwake = try read("Display/App/KeepAwakeCoordinator.swift", root: root)
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
        expect(displayCoordinator.split(whereSeparator: \.isNewline).count < 400,
               "DisplayCoordinator must remain a thin lifecycle/facade type")
        expect(displayCoordinator.contains("DisplayBrightnessCoordinator")
            && displayCoordinator.contains("DisplayHiDPICoordinator")
            && displayCoordinator.contains("DisplayVolumeCoordinator")
            && displayCoordinator.contains("DisplayCapabilityProvider"),
               "DisplayCoordinator must compose focused display feature owners")
        expect(!displayCoordinator.contains("@Published")
            && displayRuntimeState.contains("final class DisplayBrightnessRuntimeState")
            && displayRuntimeState.contains("final class DisplayHiDPIRuntimeState")
            && displayRuntimeState.contains("final class DisplayDiagnosticsRuntimeState")
            && displayRuntimeState.contains("final class DisplayVolumeRuntimeState")
            && displayRuntimeState.contains("lastSmoothedLux")
            && displayRuntimeState.contains("brightnessState")
            && displayRuntimeState.contains("currentEDIDSummary")
            && displayCoordinatorState.contains("extension DisplayCoordinator"),
               "Mutable display state must be owned outside the lifecycle coordinator")
        expect(!displayCoordinator.contains("private let writer")
            && !displayCoordinator.contains("private let internalBrightnessController")
            && !displayCoordinator.contains("private let cgsModeSwitcher")
            && !displayCoordinator.contains("dlopen")
            && !displayCoordinator.contains("dlsym"),
               "DisplayCoordinator must not carry low-level hardware/private API ownership")
        expect(displayFeatures.contains("extension DisplayCoordinator")
            && displayBrightnessRuntime.contains("extension DisplayCoordinator"),
               "Display feature implementation must be separated from lifecycle composition")
        expect(displayCoordinator.contains("await self.reloadDisplayInfo(reloadModes: false)")
            && displayCoordinator.firstRange(of: "await self.reloadDisplayInfo(reloadModes: false)")!.lowerBound
                < displayCoordinator.firstRange(of: "await self.reloadDisplayModes()")!.lowerBound
            && displayRuntime.contains("func reloadDisplayInfo(reloadModes: Bool = true)")
            && displayRuntime.contains("updateCapabilities()"),
               "External display discovery must publish before the synchronous HiDPI scan")
        expect(displayComposition.contains("final class DisplayBrightnessCoordinator")
            && displayComposition.contains("final class DisplayVolumeCoordinator")
            && displayComposition.contains("final class DisplayHiDPICoordinator"),
               "Focused display coordinators must own hardware/controller composition")
        expect(appShell.contains("let services = AppServices()"),
               "The app shell must create the shared service container")
        expect(appShell.contains("static func main()")
            && !appShell.contains("static func main() async")
            && appShell.contains("application.run()")
            && appShell.contains("await DisplayDiagnosticRouter.handleIfRequested()"),
               "AppKit must run from a synchronous main while CLI diagnostics remain pre-bootstrap")
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
        expect(migration.contains("enum DisplayConnectionIntentMigration")
            && migration.contains("removeObject(forKey: legacyDefaultsKey)")
            && migration.contains("memWatchDefaultsKey"),
               "Display disconnect intent migration must remove stale copied state")
        expect(displayConnection.contains("DisplayConnectionIntentMigration.memWatchDefaultsKey"),
               "Display connection must read only the canonical MemWatch intent")
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
        expect(privateBackend.contains("init(symbolLookup:")
            && privateBackend.contains("var isAvailable: Bool")
            && !privateBackend.contains("func isAvailable"),
               "Private display symbols must be resolved once, outside the availability hot path")
        expect(migrationRuntime.contains("Task.detached")
            && migrationRuntime.contains("[\"print\", serviceTarget]")
            && migrationRuntime.contains("[\"bootout\", serviceTarget]")
            && migrationRuntime.contains("case .conflict")
            && !migrationRuntime.contains("guard processResult.succeeded"),
               "Legacy migration must distinguish stale plist cleanup from an active conflict")
        expect(displayCoordinator.contains("let migrationTask = legacyMigrationTask")
            && displayCoordinator.contains("case .conflict(let reason)")
            && !displayCoordinator.contains("guard migrationResult.completedSuccessfully")
            && displayCoordinator.contains("self.activateRuntime()")
            && displayCoordinator.firstRange(of: "let migrationTask = legacyMigrationTask")!.lowerBound
                < displayCoordinator.firstRange(of: "self.activateRuntime()")!.lowerBound
            && displayCoordinator.firstRange(of: "self.activateRuntime()")!.lowerBound
                < displayCoordinator.firstRange(of: "HiDPIReapplyService.shared.startService()")!.lowerBound,
               "Display runtime activation must not be gated by non-conflict migration failures")
        expect(project.components(separatedBy: "SWIFT_STRICT_CONCURRENCY = complete;").count - 1 >= 6,
               "All Swift targets must enable complete strict concurrency checking")
        expect(hiDPIReapply.contains("CGDisplayRemoveReconfigurationCallback")
            && hiDPIReapply.contains("stopService()")
            && hiDPILifecycle.contains("mutating func stop()")
            && hiDPILifecycle.contains("mutating func removalFailed()")
            && hiDPILifecycle.contains("isRegistrationInFlight"),
               "HiDPI callback lifecycle must support idempotent stop/unregister")
        expect(m1DDC.contains("M1DDCExecutableLocator")
            && m1DDC.contains("executableCacheInterval")
            && m1DDC.contains("run(arguments: [\"display\", \"list\", \"detailed\"])")
            && m1DDC.contains("stdout.fileHandleForReading.readDataToEndOfFile() + stderr.fileHandleForReading.readDataToEndOfFile()")
            && !m1DDC.contains("return \"uuid:\\(systemUUID)\""),
               "m1ddc discovery and DDC selectors must retain the working command contract")
        expect(displayRuntime.contains("guard connection.phase == .softwareDisconnected else { return false }")
            && displayRuntime.contains("await brightnessCoordinator.writer.refreshDisplay")
            && displayRuntime.contains("publishCurrentDisplayInfo(display, reason: \"writer.refreshDisplay non-nil\")")
            && displayRuntime.contains("publishCurrentDisplayInfo(nil, reason: \"writer.refreshDisplay returned nil\")")
            && !displayRuntime.contains("currentDisplayInfo = nil"),
               "Connection capability degradation must not erase independently discovered display state")
        expect(displayCoordinatorState.contains("currentDisplayInfo assigned")
            && displayCoordinator.contains("traceRuntime(\"start entered")
            && displayCoordinator.contains("traceRuntime(\"activateRuntime entered"),
               "Display runtime lifecycle must expose startup and state-transition instrumentation")
        expect(keepAwake.contains("func disableKeepAwake()")
            && keepAwake.contains("setKeepAwakeFeatureEnabled(false)"),
               "Keep Awake disable must disable the feature instead of starting a session")

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
