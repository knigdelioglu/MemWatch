import Foundation

@main
struct DisplayFeatureSmoke {
    @MainActor
    static func main() async {
        testBrightnessCurve()
        testDDCBrightnessParsing()
        testDDCBrightnessScale()
        testLuxFilter()
        testCapabilityModel()
        testAutomaticBrightnessPlanning()
        testDisplayConnectionPolicy()
        testDisplayIdentity()
        testKeepAwakeStatePersistence()
        testPollingSchedulerOwnership()
        testPreferencesMigration()
        testCapabilityProvider()
        testPrivateDisplayBackendResolutionCache()
        testM1DDCExecutableLocator()
        await testM1DDCRuntimeAvailabilityRefresh()
        testHiDPIReapplyLifecycle()
        await testLegacyMigration()
        print("Display feature smoke tests passed")
    }

    private static func testBrightnessCurve() {
        let profile = AmbientSyncProfile.defaultProfiles[2]
        let calibration = DisplayCalibration.default
        let dark = BrightnessCurve.targetBrightness(for: 0, calibration: calibration, profile: profile)
        let medium = BrightnessCurve.targetBrightness(for: 350, calibration: calibration, profile: profile)
        let bright = BrightnessCurve.targetBrightness(for: 1_500, calibration: calibration, profile: profile)

        precondition(dark == 0)
        precondition(dark <= medium && medium <= bright)
        precondition((0...100).contains(bright))
    }

    private static func testDDCBrightnessScale() {
        precondition(DDCBrightnessScale.rawTarget(forUIPercent: 50, rawMax: 255) == 128)
        precondition(DDCBrightnessScale.uiPercent(fromRawCurrent: 128, rawMax: 255) == 50)
        precondition(DDCBrightnessScale.rawTarget(forUIPercent: -20, rawMax: 255) == 0)
        precondition(DDCBrightnessScale.rawTarget(forUIPercent: 120, rawMax: 255) == 255)
        precondition(DDCBrightnessScale.isMatched(rawAfter: 128, computedRawTarget: 130, tolerance: 2))
        precondition(!DDCBrightnessScale.isMatched(rawAfter: nil, computedRawTarget: 130))
    }

    private static func testDDCBrightnessParsing() {
        let labeled = DDCBrightnessParsing.parseRawSample(
            from: "Current luminance: 128\nMaximum luminance: 255"
        )
        precondition(labeled.rawCurrent == 128)
        precondition(labeled.rawMax == 255)
        precondition(labeled.available)

        let compact = DDCBrightnessParsing.parseRawSample(from: "128 255")
        precondition(compact.rawCurrent == 128)
        precondition(compact.rawMax == 255)
        precondition(DDCBrightnessParsing.parseSingleRawValue(from: "No value") == nil)
    }

    private static func testLuxFilter() {
        let filter = LuxFilter()
        _ = filter.push(10, baseSmoothing: 0.2)
        _ = filter.push(10_000, baseSmoothing: 0.2)
        let value = filter.push(10_000, baseSmoothing: 0.2)
        precondition(value >= 0 && value <= 120_000)
        filter.reset()
        precondition(filter.push(-5, baseSmoothing: 0.2) == 0)
    }

    private static func testCapabilityModel() {
        precondition(DisplayCapability.degraded("limited").isAvailable)
        precondition(!DisplayCapabilities.unavailable.ddc.isAvailable)
        precondition(DisplayCapabilities.unavailable.keepAwake.isAvailable)
    }

    private static func testCapabilityProvider() {
        let provider = DisplayCapabilityProvider()
        let unavailable = provider.capabilities(
            for: DisplayCapabilityInputs(
                hasAmbientLightSensor: true,
                hasInternalBrightness: false,
                hasExternalDisplay: false,
                hasDDCExecutable: false,
                hasHiDPIPrivateAPI: false,
                hasSoftwareDisconnect: false
            )
        )
        precondition(unavailable.ddc.status == .unavailable)
        precondition(unavailable.externalDisplay.reason?.isEmpty == false)
        precondition(unavailable.keepAwake.status == .available)

        let connected = provider.capabilities(
            for: DisplayCapabilityInputs(
                hasAmbientLightSensor: true,
                hasInternalBrightness: true,
                hasExternalDisplay: true,
                hasDDCExecutable: true,
                hasHiDPIPrivateAPI: true,
                hasSoftwareDisconnect: true
            )
        )
        precondition(connected.ddc.status == .available)
        precondition(connected.hiDPI.status == .available)
    }

    private static func testPrivateDisplayBackendResolutionCache() {
        final class CountingLookup: PrivateDisplaySymbolLookup {
            var calls = 0

            func symbol(named: String) -> UnsafeMutableRawPointer? {
                calls += 1
                return nil
            }
        }

        let lookup = CountingLookup()
        let backend = PrivateDisplayConnectionBackend(symbolLookup: lookup)
        let callsAfterInit = lookup.calls
        precondition(callsAfterInit > 0)
        precondition(!backend.isAvailable)
        precondition(!backend.isAvailable)
        precondition(lookup.calls == callsAfterInit)
    }

    private static func testM1DDCExecutableLocator() {
        var available = Set<String>()
        let locator = M1DDCExecutableLocator(
            candidates: ["/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc"],
            executableCheck: { available.contains($0) }
        )
        precondition(locator.locate() == nil)
        available.insert("/usr/local/bin/m1ddc")
        precondition(locator.locate()?.path == "/usr/local/bin/m1ddc")
        available.remove("/usr/local/bin/m1ddc")
        precondition(locator.locate() == nil)
    }

    private static func testM1DDCRuntimeAvailabilityRefresh() async {
        final class AvailabilityBox: @unchecked Sendable {
            var available = false
            var checks = 0
        }

        let box = AvailabilityBox()
        let writer = M1DDCWriter(
            executableLocator: M1DDCExecutableLocator(
                candidates: ["/tmp/m1ddc"],
                executableCheck: { _ in
                    box.checks += 1
                    return box.available
                }
            )
        )
        let initiallyAvailable = await writer.isAvailable(refresh: true)
        precondition(!initiallyAvailable)
        let checksAfterFirstRefresh = box.checks
        let cachedAvailability = await writer.isAvailable()
        precondition(!cachedAvailability)
        precondition(box.checks == checksAfterFirstRefresh)
        box.available = true
        let becameAvailable = await writer.isAvailable(refresh: true)
        precondition(becameAvailable)
        box.available = false
        let becameUnavailable = await writer.isAvailable(refresh: true)
        precondition(!becameUnavailable)
    }

    private static func testHiDPIReapplyLifecycle() {
        var lifecycle = HiDPIReapplyLifecycle()
        precondition(lifecycle.start())
        precondition(!lifecycle.start())
        lifecycle.registrationSucceeded()
        precondition(lifecycle.scheduleWork())
        precondition(lifecycle.hasPendingWork)
        precondition(lifecycle.stop())
        precondition(!lifecycle.hasPendingWork)
        // A stop request does not lie about the OS callback. The service
        // clears this only after CGDisplayRemoveReconfigurationCallback
        // reports success.
        precondition(lifecycle.isListening)
        precondition(!lifecycle.start())
        lifecycle.removalSucceeded()
        precondition(!lifecycle.isListening)
        precondition(!lifecycle.stop())
        precondition(lifecycle.start())
        lifecycle.registrationSucceeded()
        precondition(lifecycle.scheduleWork())
        precondition(lifecycle.stop())
        lifecycle.removalFailed()
        precondition(lifecycle.isListening)
        precondition(!lifecycle.start())
        lifecycle.removalSucceeded()
        precondition(!lifecycle.isListening)
        precondition(lifecycle.start())
        lifecycle.registrationSucceeded()
        lifecycle.completeWork()
        precondition(!lifecycle.hasPendingWork)
    }

    private static func testLegacyMigration() async {
        struct FakeRunner: LegacyAmbientSyncProcessRunning {
            let result: LegacyAmbientSyncProcessResult

            func run(executableURL: URL, arguments: [String]) async -> LegacyAmbientSyncProcessResult {
                result
            }
        }

        let root = URL(fileURLWithPath: "/private/tmp/memwatch-migration-smoke-\(ProcessInfo.processInfo.processIdentifier)")
        let launchAgents = root.appendingPathComponent("Library/LaunchAgents")
        let plist = launchAgents.appendingPathComponent("fyi.kadir.AmbientSync.plist")
        let defaults = UserDefaults(suiteName: "MemWatch.LegacyMigration.\(ProcessInfo.processInfo.processIdentifier)")!
        defaults.removePersistentDomain(forName: "MemWatch.LegacyMigration.\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: root)
        try! FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)

        try! Data("legacy".utf8).write(to: plist)
        let failed = await LegacyAmbientSyncMigration.runIfNeeded(
            defaults: defaults,
            homeDirectory: root,
            runner: FakeRunner(result: LegacyAmbientSyncProcessResult(terminationStatus: 1, launchError: nil))
        )
        guard case .failed = failed else { preconditionFailure("bootout failure must remain incomplete") }
        precondition(FileManager.default.fileExists(atPath: plist.path))
        precondition(defaults.integer(forKey: "MemWatch.LegacyAmbientSyncCleanupVersion") == 0)

        let completed = await LegacyAmbientSyncMigration.runIfNeeded(
            defaults: defaults,
            homeDirectory: root,
            runner: FakeRunner(result: LegacyAmbientSyncProcessResult(terminationStatus: 0, launchError: nil))
        )
        precondition(completed == .completed)
        precondition(!FileManager.default.fileExists(atPath: plist.path))
        precondition(defaults.integer(forKey: "MemWatch.LegacyAmbientSyncCleanupVersion") == 1)
        let repeated = await LegacyAmbientSyncMigration.runIfNeeded(defaults: defaults, homeDirectory: root)
        precondition(repeated == .alreadyCompleted)

        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: "MemWatch.LegacyMigration.\(ProcessInfo.processInfo.processIdentifier)")
        let absent = await LegacyAmbientSyncMigration.runIfNeeded(defaults: defaults, homeDirectory: root)
        precondition(absent == .noLegacyPlist)
        precondition(defaults.integer(forKey: "MemWatch.LegacyAmbientSyncCleanupVersion") == 1)
        defaults.removePersistentDomain(forName: "MemWatch.LegacyMigration.\(ProcessInfo.processInfo.processIdentifier)")
    }

    private static func testAutomaticBrightnessPlanning() {
        let controller = BrightnessAutoController()
        precondition(controller.smoothedRequestedPercent(target: 80, reference: 40, smoothing: 0.25) == 50)
        precondition(!controller.shouldContinueManualOverride(
            currentLux: 400,
            startLux: 100,
            overrideUntil: Date().addingTimeInterval(60)
        ))

        let now = Date()
        let planner = BrightnessAutoLoopPlanner()
        let context = BrightnessAutoLoopPreflightContext(
            ambientLux: 400,
            target: 80,
            smoothedRequested: 70,
            currentActual: 40,
            now: now,
            lastWriteDate: now.addingTimeInterval(-5),
            minInterval: 1,
            updateThreshold: 2,
            currentDisplayKey: "display-1",
            calibrationActive: false,
            appBrightnessSuppressedUntil: now.addingTimeInterval(-1),
            ddcAvailable: true,
            brightnessLimiterCooldownDisplayKey: nil,
            brightnessLimiterCooldownUntil: now.addingTimeInterval(-1)
        )

        guard case let .proceed(candidate, _) = planner.preflight(context: context) else {
            preconditionFailure("Expected automatic brightness write to proceed")
        }
        precondition(candidate == 70)

        let unavailableContext = BrightnessAutoLoopPreflightContext(
            ambientLux: context.ambientLux,
            target: context.target,
            smoothedRequested: context.smoothedRequested,
            currentActual: context.currentActual,
            now: context.now,
            lastWriteDate: context.lastWriteDate,
            minInterval: context.minInterval,
            updateThreshold: context.updateThreshold,
            currentDisplayKey: context.currentDisplayKey,
            calibrationActive: context.calibrationActive,
            appBrightnessSuppressedUntil: context.appBrightnessSuppressedUntil,
            ddcAvailable: false,
            brightnessLimiterCooldownDisplayKey: context.brightnessLimiterCooldownDisplayKey,
            brightnessLimiterCooldownUntil: context.brightnessLimiterCooldownUntil
        )
        guard case let .suppressed(reason, _, _, _, _) = planner.preflight(context: unavailableContext) else {
            preconditionFailure("Expected DDC-unavailable suppression")
        }
        guard case .ddcUnavailable = reason else {
            preconditionFailure("Expected DDC-unavailable suppression reason")
        }
    }

    private static func testDisplayConnectionPolicy() {
        precondition(
            DisplayConnectionPolicy.phase(
                targetFoundInPrivateList: true,
                isOnline: true,
                isActive: true,
                softwareDisconnectRequested: false
            ) == .connected
        )
        precondition(
            DisplayConnectionPolicy.phase(
                targetFoundInPrivateList: true,
                isOnline: false,
                isActive: false,
                softwareDisconnectRequested: true
            ) == .softwareDisconnected
        )
        precondition(
            DisplayConnectionPolicy.phase(
                targetFoundInPrivateList: false,
                isOnline: true,
                isActive: true,
                softwareDisconnectRequested: false
            ) == .physicallyDisconnected
        )
        precondition(DisplayConnectionPolicy.canDisable(targetDisplayID: 1, activeDisplayIDs: [1, 2]))
        precondition(!DisplayConnectionPolicy.canDisable(targetDisplayID: 1, activeDisplayIDs: [1]))
    }

    private static func testDisplayIdentity() {
        let serialIdentity = ExternalDisplayInfo(
            displayIndex: "1",
            displayID: 1,
            productName: "Samsung S60UD",
            serial: "SN-42",
            systemUUID: "uuid-42",
            ioLocation: nil
        )
        precondition(serialIdentity.displayKey == "Samsung S60UD|SN-42")

        let fallbackIdentity = ExternalDisplayInfo(
            displayIndex: "2",
            displayID: 2,
            productName: "Samsung S60UD",
            serial: "",
            systemUUID: "uuid-43",
            ioLocation: nil
        )
        precondition(fallbackIdentity.displayKey == "Samsung S60UD|uuid-43")
        precondition(DisplayConnectionIdentity.samsungS60UD.vendorID == 0x4C2D)
        precondition(DisplayConnectionIdentity.samsungS60UD.productID == 0x76AB)
    }

    private static func testKeepAwakeStatePersistence() {
        let suiteName = "MemWatch.DisplayFeatureSmoke.KeepAwake.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let controller = KeepAwakeFeatureController(defaults: defaults)
        var state = KeepAwakeFeatureController.loadInitialState(defaults: defaults)
        controller.setFeatureEnabled(false, state: &state)
        controller.setPluggedOnly(true, state: &state)
        controller.setDisplayAwake(false, state: &state)

        let restored = KeepAwakeFeatureController.loadInitialState(defaults: defaults)
        precondition(!restored.featureEnabled)
        precondition(restored.onlyWhilePluggedIn)
        precondition(!restored.keepDisplayAwake)

        controller.startDurationMode("60", state: &state)
        precondition(state.temporaryOverrideActive)
        precondition(state.temporaryIdleTimeoutMode == "60")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    private static func testPollingSchedulerOwnership() {
        let scheduler = PollingScheduler()
        scheduler.register(id: "smoke", interval: 1) {}
        scheduler.register(id: "smoke", interval: 1) {}
        precondition(scheduler.registeredJobIDs == ["smoke"])
        scheduler.unregister(id: "smoke")
        precondition(scheduler.registeredJobIDs.isEmpty)
        scheduler.register(id: "smoke", interval: 1) {}
        scheduler.stop()
        precondition(scheduler.registeredJobIDs.isEmpty)
    }

    private static func testPreferencesMigration() {
        let suffix = "MemWatch.DisplayFeatureSmoke.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suffix + ".current")!
        let legacy = UserDefaults(suiteName: suffix + ".legacy")!
        defaults.removePersistentDomain(forName: suffix + ".current")
        legacy.removePersistentDomain(forName: suffix + ".legacy")
        legacy.set(Data("legacy".utf8), forKey: "AmbientSync.LastVolume")

        precondition(
            DisplayPreferencesMigration.migrateIfNeeded(
                defaults: defaults,
                legacyDefaults: legacy
            )
        )
        precondition(defaults.data(forKey: "AmbientSync.LastVolume") == Data("legacy".utf8))
        precondition(!DisplayPreferencesMigration.migrateIfNeeded(defaults: defaults, legacyDefaults: legacy))

        defaults.removePersistentDomain(forName: suffix + ".current")
        legacy.removePersistentDomain(forName: suffix + ".legacy")
    }
}
