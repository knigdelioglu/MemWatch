import Foundation

@main
struct DisplayFeatureSmoke {
    @MainActor
    static func main() {
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
