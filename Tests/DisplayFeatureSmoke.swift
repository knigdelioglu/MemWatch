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
        testExternalSliderInteractionPolicy()
        testLatestValueWriteGate()
        testDisplayPowerLifecycle()
        testTargetDisplayWakeStabilizationPolicy()
        testTargetDisplayReadinessFailClosed()
        testDisplayOperationGates()
        testKeepAwakeStatePersistence()
        testPollingSchedulerOwnership()
        testPreferencesMigration()
        testDisplayConnectionIntentMigration()
        testCapabilityProvider()
        testPrivateDisplayBackendResolutionCache()
        testM1DDCExecutableLocator()
        await testM1DDCRuntimeAvailabilityRefresh()
        testCoreGraphicsDisplayFingerprint()
        testDisplayDiscoveryParserAndClassification()
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

    private static func testLatestValueWriteGate() {
        var gate = LatestValueWriteGate()
        let autoGeneration = gate.startRequest()
        precondition(gate.accepts(autoGeneration))

        // Beginning a manual interaction invalidates an already-running auto
        // completion before the first manual DDC write is issued.
        gate.invalidate()
        precondition(!gate.accepts(autoGeneration))

        let firstManualGeneration = gate.startRequest()
        let latestManualGeneration = gate.startRequest()
        precondition(!gate.accepts(firstManualGeneration))
        precondition(gate.accepts(latestManualGeneration))
    }

    private static func testDisplayPowerLifecycle() {
        var lifecycle = DisplayPowerLifecycle()
        let gate = DisplayPowerOperationGate()
        let activeGeneration = lifecycle.generation
        gate.activate(generation: activeGeneration)
        precondition(lifecycle.state == .active)
        precondition(lifecycle.accepts(activeGeneration))
        precondition(gate.isAllowed())
        let activeOperationGeneration = gate.currentGeneration()

        // A screen/system sleep suspends display work without erasing the
        // cached display identity and invalidates every older completion.
        lifecycle.enterScreenSleep()
        gate.suspend()
        precondition(lifecycle.state == .screenSleeping)
        precondition(!lifecycle.accepts(activeGeneration))
        precondition(!gate.isAllowed())

        lifecycle.enterSystemSleep()
        lifecycle.enterScreenSleep()
        precondition(lifecycle.state == .systemSleeping)

        // A rapid sleep -> wake must not make a completion from the previous
        // operation epoch valid merely because the gate is active again.
        gate.activate(generation: activeOperationGeneration + 1)
        precondition(!gate.accepts(activeOperationGeneration))

        // Wake callbacks restart the complete stabilization window rather
        // than allowing the first callback to arm display work immediately.
        let wakeStart = Date(timeIntervalSince1970: 10_000)
        lifecycle.beginWaking(now: wakeStart, stabilizationDuration: 5)
        let firstWakeGeneration = lifecycle.generation
        let firstDeadline = lifecycle.wakeStabilizationDeadline
        lifecycle.resetWakeStabilization(now: wakeStart.addingTimeInterval(1), stabilizationDuration: 5)
        precondition(lifecycle.state == .waking)
        precondition(lifecycle.generation != firstWakeGeneration)
        precondition(lifecycle.wakeStabilizationDeadline == wakeStart.addingTimeInterval(6))
        precondition(firstDeadline != lifecycle.wakeStabilizationDeadline)
        precondition(!lifecycle.isWakeStabilized(at: wakeStart.addingTimeInterval(5.9)))
        precondition(!lifecycle.activateIfReady(now: wakeStart.addingTimeInterval(5.9)))

        let wakingSnapshot = lifecycle.snapshot(isHiDPIAllowed: true)
        precondition(wakingSnapshot.state == .waking)
        precondition(!wakingSnapshot.isHiDPIAllowed)
        precondition(!wakingSnapshot.targetDisplayReadiness.isReady)

        precondition(lifecycle.activateIfReady(now: wakeStart.addingTimeInterval(6)))

        gate.activate(generation: lifecycle.generation)
        precondition(gate.isAllowed())
        precondition(lifecycle.accepts(lifecycle.generation))
    }

    private static func testTargetDisplayWakeStabilizationPolicy() {
        precondition(TargetDisplayWakeStabilizationPolicy.confirmationNanoseconds == 750_000_000)
        precondition(TargetDisplayWakeStabilizationPolicy.maxRetries == 5)

        let initial = TargetDisplayWakeCandidate(displayID: 42, isOnline: true, isActive: true)
        let confirmed = TargetDisplayWakeCandidate(displayID: 42, isOnline: true, isActive: true)
        precondition(TargetDisplayWakeStabilizationPolicy.isCandidateValid(initial: initial, confirmed: confirmed))

        // Display ID changed during the 750ms verification window -> invalid
        let changedID = TargetDisplayWakeCandidate(displayID: 43, isOnline: true, isActive: true)
        precondition(!TargetDisplayWakeStabilizationPolicy.isCandidateValid(initial: initial, confirmed: changedID))

        // Display dropped offline or inactive during the window -> invalid
        let offline = TargetDisplayWakeCandidate(displayID: 42, isOnline: false, isActive: true)
        precondition(!TargetDisplayWakeStabilizationPolicy.isCandidateValid(initial: initial, confirmed: offline))
        let inactive = TargetDisplayWakeCandidate(displayID: 42, isOnline: true, isActive: false)
        precondition(!TargetDisplayWakeStabilizationPolicy.isCandidateValid(initial: initial, confirmed: inactive))
        precondition(!TargetDisplayWakeStabilizationPolicy.isCandidateValid(initial: nil, confirmed: confirmed))
        precondition(!TargetDisplayWakeStabilizationPolicy.isCandidateValid(initial: initial, confirmed: nil))

        // Retry limit policy
        precondition(TargetDisplayWakeStabilizationPolicy.shouldWaitForTarget(isTargetExpected: true, retryCount: 0))
        precondition(TargetDisplayWakeStabilizationPolicy.shouldWaitForTarget(isTargetExpected: true, retryCount: 4))
        precondition(TargetDisplayWakeStabilizationPolicy.shouldWaitForTarget(isTargetExpected: true, retryCount: 5))
        precondition(TargetDisplayWakeStabilizationPolicy.shouldWaitForTarget(isTargetExpected: true, retryCount: 20))
        precondition(!TargetDisplayWakeStabilizationPolicy.shouldWaitForTarget(isTargetExpected: false, retryCount: 0))
        precondition(TargetDisplayWakeStabilizationPolicy.retryDelay(afterRetryCount: 0) == 1)
        precondition(TargetDisplayWakeStabilizationPolicy.retryDelay(afterRetryCount: 4) == 1)
        precondition(TargetDisplayWakeStabilizationPolicy.retryDelay(afterRetryCount: 5) == 3)
        precondition(TargetDisplayWakeStabilizationPolicy.retryDelay(afterRetryCount: 20) == 3)
    }

    private static func testTargetDisplayReadinessFailClosed() {
        let gate = TargetDisplayOperationGate()
        let initial = TargetDisplayWakeCandidate(displayID: 42, isOnline: true, isActive: true)
        let sameID = TargetDisplayWakeCandidate(displayID: 42, isOnline: true, isActive: true)
        let changedID = TargetDisplayWakeCandidate(displayID: 43, isOnline: true, isActive: true)

        // A. Missing target and B/C. Five or twenty failed retries never
        // become an external-operation success.
        gate.beginStabilizing()
        for retryCount in [0, 5, 20] {
            precondition(TargetDisplayWakeStabilizationPolicy.shouldWaitForTarget(
                isTargetExpected: true,
                retryCount: retryCount
            ))
            precondition(!gate.snapshot().isReady)
        }
        var ddcWrites = 0
        var cgsApplies = 0
        if gate.snapshot().isReady {
            ddcWrites += 1
            cgsApplies += 1
        }
        precondition(ddcWrites == 0)
        precondition(cgsApplies == 0)

        // D. Two matching samples make one readiness/recovery epoch.
        precondition(TargetDisplayWakeStabilizationPolicy.isCandidateValid(
            initial: initial,
            confirmed: sameID
        ))
        let firstReadyGeneration = gate.markReady(displayID: sameID.displayID)
        precondition(gate.accepts(firstReadyGeneration, displayID: sameID.displayID))
        var recoveryChains = 1
        let duplicateGeneration = gate.markReady(displayID: sameID.displayID)
        if duplicateGeneration != firstReadyGeneration {
            recoveryChains += 1
        }
        precondition(recoveryChains == 1)

        // E. A display ID change in the confirmation window is not ready.
        gate.beginStabilizing()
        precondition(!TargetDisplayWakeStabilizationPolicy.isCandidateValid(
            initial: initial,
            confirmed: changedID
        ))
        precondition(!gate.snapshot().isReady)

        // F/G. Offline/invalidation blocks the old epoch; the same stable
        // target can later reappear and produce exactly one new chain.
        gate.invalidate()
        gate.beginStabilizing()
        precondition(!gate.snapshot().isReady)
        let reappearedGeneration = gate.markReady(displayID: sameID.displayID)
        precondition(gate.accepts(reappearedGeneration, displayID: sameID.displayID))
        precondition(!gate.accepts(firstReadyGeneration, displayID: sameID.displayID))
        precondition(gate.markReady(displayID: sameID.displayID) == reappearedGeneration)
        precondition(TargetDisplayWakeStabilizationPolicy.isCandidateValid(
            initial: initial,
            confirmed: sameID
        ))
    }

    private static func testDisplayOperationGates() {
        let ready = TargetDisplayReadiness.ready(displayID: 42)
        let unavailable = TargetDisplayReadiness.unavailable

        // H/J. Slider, volume-key, and mute-style interactive writes are all
        // blocked during controlled post-wake refresh.
        precondition(DisplayOperationPolicy.readOperationsAllowed(
            isRunning: true,
            powerState: .active
        ))
        precondition(!DisplayOperationPolicy.interactiveOperationsAllowed(
            isRunning: true,
            powerState: .active,
            isPostWakeRefreshInProgress: true
        ))
        precondition(!DisplayOperationPolicy.externalInteractiveOperationsAllowed(
            isRunning: true,
            powerState: .active,
            isPostWakeRefreshInProgress: true,
            targetReadiness: ready
        ))

        // L/M. Controlled reads and the internal scheduler's read-side work
        // remain allowed while the interactive side is closed.
        precondition(DisplayOperationPolicy.externalReadOperationsAllowed(
            isRunning: true,
            powerState: .active,
            targetReadiness: ready
        ))
        precondition(DisplayOperationPolicy.readOperationsAllowed(
            isRunning: true,
            powerState: .active
        ))

        // A. Target readiness independently blocks external DDC/CGS work,
        // while the global runtime can remain active for built-in features.
        precondition(DisplayOperationPolicy.readOperationsAllowed(
            isRunning: true,
            powerState: .active
        ))
        precondition(!DisplayOperationPolicy.externalReadOperationsAllowed(
            isRunning: true,
            powerState: .active,
            targetReadiness: unavailable
        ))
        precondition(!DisplayOperationPolicy.externalInteractiveOperationsAllowed(
            isRunning: true,
            powerState: .active,
            isPostWakeRefreshInProgress: false,
            targetReadiness: unavailable
        ))
        for powerState in [DisplayPowerState.screenSleeping, .systemSleeping, .waking] {
            precondition(!DisplayOperationPolicy.interactiveOperationsAllowed(
                isRunning: true,
                powerState: powerState,
                isPostWakeRefreshInProgress: false
            ))
        }

        // K/N. Once refresh completes, user intent is eligible again; a
        // stale queued command is still rejected by the latest-intent gate.
        precondition(DisplayOperationPolicy.externalInteractiveOperationsAllowed(
            isRunning: true,
            powerState: .active,
            isPostWakeRefreshInProgress: false,
            targetReadiness: ready
        ))
        var latestIntent = LatestValueWriteGate()
        let queuedGeneration = latestIntent.startRequest()
        latestIntent.invalidate()
        precondition(!latestIntent.accepts(queuedGeneration))
    }

    private static func testExternalSliderInteractionPolicy() {
        precondition(ExternalSliderInteractionPolicy.brightnessDebounceNanoseconds == 150_000_000)
        precondition(ExternalSliderInteractionPolicy.volumeDebounceNanoseconds == 120_000_000)

        var draft = 20.0
        var pendingWrite: Int?
        for value in [20.0, 19.0, 18.0, 17.0, 16.0, 15.0] {
            if ExternalSliderInteractionPolicy.shouldSchedule(newValue: value, previousDraft: draft) {
                pendingWrite = ExternalSliderInteractionPolicy.roundedValue(value)
            }
            draft = value
        }
        // Each new setter cancels the prior debounce task, so only the final
        // value remains eligible to reach DDC.
        precondition(pendingWrite == 15)

        var localDraft = 15.0
        if ExternalSliderInteractionPolicy.shouldSynchronizeFromBackend(isAdjusting: true) {
            localDraft = 20
        }
        precondition(localDraft == 15)
        precondition(ExternalSliderInteractionPolicy.shouldSynchronizeFromBackend(isAdjusting: false))
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

    private static func testCoreGraphicsDisplayFingerprint() {
        precondition(M1DDCWriter.isSupportedTargetDisplay(
            vendorID: 0x4C2D,
            productID: 0x76AB,
            isBuiltin: false
        ))
        precondition(!M1DDCWriter.isSupportedTargetDisplay(
            vendorID: 0x4C2D,
            productID: 0x76AB,
            isBuiltin: true
        ))
        precondition(!M1DDCWriter.isSupportedTargetDisplay(
            vendorID: 0x4C2D,
            productID: 0x0001,
            isBuiltin: false
        ))
    }

    private static func testDisplayDiscoveryParserAndClassification() {
        let rawOutput = """
        [0]
        - Product name: Color LCD
        - Display ID: 1
        - Serial: INTERNAL
        - System UUID: internal-uuid
        - IO Location: IOService:/AppleACPIPlatformExpert/Disp0

        [1]
        - Product name: Samsung S60UD
        - Display ID: 42
        - Serial: S60UD-serial
        - System UUID: s60ud-uuid
        - IO Location: IOService:/AppleACPIPlatformExpert/Disp1
        """
        let parsed = M1DDCWriter.parseDisplaysForDiagnostics(rawOutput)
        precondition(parsed.allDisplays.count == 2)
        precondition(parsed.externalDisplays.count == 1)
        precondition(parsed.samsungFilteredDisplays.count == 1)
        precondition(parsed.samsungFilteredDisplays[0].displayKey == "Samsung S60UD|S60UD-serial")
        precondition(parsed.samsungFilteredDisplays[0].displayID == 42)
        precondition(
            M1DDCWriter.selectDisplayForDiagnostics(
                parsed.samsungFilteredDisplays,
                preferredKey: "stale-preferred-key"
            )?.displayKey == parsed.samsungFilteredDisplays[0].displayKey
        )
        precondition(
            M1DDCWriter.ddcSelectorForDiagnostics(parsed.samsungFilteredDisplays[0]) == "1"
        )
        let coreGraphicsOnlyFallback = ExternalDisplayInfo(
            displayIndex: "id:42",
            displayID: 42,
            productName: "Samsung S60UD",
            serial: "CG-serial",
            systemUUID: nil,
            ioLocation: nil
        )
        precondition(M1DDCWriter.ddcSelectorForDiagnostics(coreGraphicsOnlyFallback).isEmpty)

        func input(
            executableSelected: Bool = true,
            processRan: Bool = true,
            processSucceeded: Bool = true,
            timedOut: Bool = false,
            outputEmpty: Bool = false,
            rawCount: Int = 1,
            allParsed: Int = 1,
            externalParsed: Int = 1,
            samsungFiltered: Int = 1,
            coreGraphicsExternal: Int = 1,
            coreGraphicsFingerprint: Int = 1,
            softwareDisconnect: Bool = false,
            legacyConflict: Bool = false,
            productionDisplay: Bool = true
        ) -> DisplayDiscoveryClassificationInput {
            DisplayDiscoveryClassificationInput(
                m1ddcExecutableSelected: executableSelected,
                m1ddcProcessRan: processRan,
                m1ddcProcessSucceeded: processSucceeded,
                m1ddcTimedOut: timedOut,
                m1ddcOutputEmpty: outputEmpty,
                rawDisplayCount: rawCount,
                allParsedDisplayCount: allParsed,
                externalParsedDisplayCount: externalParsed,
                samsungFilteredDisplayCount: samsungFiltered,
                coreGraphicsExternalDisplayCount: coreGraphicsExternal,
                coreGraphicsFingerprintMatchCount: coreGraphicsFingerprint,
                softwareDisconnectStatePersisted: softwareDisconnect,
                legacyRuntimeConflict: legacyConflict,
                productionWriterReturnedDisplay: productionDisplay
            )
        }

        precondition(
            DisplayDiscoveryPipelineClassifier.classify(input()) ==
                [.displayDiscoverySucceeded]
        )
        precondition(
            DisplayDiscoveryPipelineClassifier.classify(
                input(
                    outputEmpty: true,
                    rawCount: 0,
                    allParsed: 0,
                    externalParsed: 0,
                    samsungFiltered: 0
                )
            ) == [.m1ddcOutputEmpty, .displayDiscoverySucceeded]
        )
        precondition(
            DisplayDiscoveryPipelineClassifier.classify(
                input(
                    rawCount: 1,
                    allParsed: 1,
                    externalParsed: 0,
                    samsungFiltered: 0,
                    coreGraphicsFingerprint: 0,
                    productionDisplay: false
                )
            ) == [.coreGraphicsFingerprintMismatch]
        )
        precondition(
            DisplayDiscoveryPipelineClassifier.classify(
                input(productionDisplay: false)
            ) == [.productionWriterReturnedNilDespiteDiscovery]
        )
    }

    private static func testHiDPIReapplyLifecycle() {
        var lifecycle = HiDPIReapplyLifecycle()
        precondition(lifecycle.start())
        precondition(!lifecycle.start())
        lifecycle.registrationSucceeded()
        precondition(lifecycle.scheduleWork())
        let scheduledGeneration = lifecycle.operationGeneration
        precondition(lifecycle.scheduleWork())
        precondition(lifecycle.operationGeneration != scheduledGeneration)
        let executingGeneration = lifecycle.operationGeneration
        precondition(lifecycle.beginExecution(for: executingGeneration))
        precondition(lifecycle.workState == .executing)
        precondition(!lifecycle.scheduleWork())
        precondition(!lifecycle.shouldScheduleFromReconfigurationCallback())
        precondition(lifecycle.beginApplyingMode())
        precondition(lifecycle.isApplyingMode)
        precondition(!lifecycle.beginApplyingMode())
        lifecycle.endApplyingMode()
        precondition(!lifecycle.isApplyingMode)
        lifecycle.completeWork(for: executingGeneration)
        precondition(lifecycle.workState == .idle)
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

    @MainActor
    private static func testLegacyMigration() async {
        final class SequencedRunner: @unchecked Sendable, LegacyAmbientSyncProcessRunning {
            var results: [LegacyAmbientSyncProcessResult]
            private(set) var calls: [[String]] = []

            init(results: [LegacyAmbientSyncProcessResult]) {
                self.results = results
            }

            func run(executableURL: URL, arguments: [String]) async -> LegacyAmbientSyncProcessResult {
                calls.append(arguments)
                precondition(!results.isEmpty, "Unexpected launchctl invocation")
                return results.removeFirst()
            }
        }

        func makeFixture(_ name: String) throws -> (root: URL, plist: URL, defaults: UserDefaults, defaultsName: String) {
            let root = URL(fileURLWithPath: "/private/tmp/memwatch-migration-smoke-\(name)-\(ProcessInfo.processInfo.processIdentifier)")
            let launchAgents = root.appendingPathComponent("Library/LaunchAgents")
            let plist = launchAgents.appendingPathComponent("fyi.kadir.AmbientSync.plist")
            let defaultsName = "MemWatch.LegacyMigration.\(name).\(ProcessInfo.processInfo.processIdentifier)"
            let defaults = UserDefaults(suiteName: defaultsName)!
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
            try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
            try Data("legacy".utf8).write(to: plist)
            return (root, plist, defaults, defaultsName)
        }

        let stale = try! makeFixture("stale")
        let staleRunner = SequencedRunner(results: [
            LegacyAmbientSyncProcessResult(terminationStatus: 1, launchError: nil)
        ])
        let staleResult = await LegacyAmbientSyncMigration.runIfNeeded(
            defaults: stale.defaults,
            homeDirectory: stale.root,
            runner: staleRunner
        )
        precondition(staleResult == .completed)
        precondition(!FileManager.default.fileExists(atPath: stale.plist.path))
        precondition(stale.defaults.integer(forKey: "MemWatch.LegacyAmbientSyncCleanupVersion") == 1)
        precondition(staleRunner.calls.count == 1 && staleRunner.calls[0].first == "print")

        let unloadedAfterBootout = try! makeFixture("unloaded-after-bootout")
        let unloadRunner = SequencedRunner(results: [
            LegacyAmbientSyncProcessResult(terminationStatus: 0, launchError: nil),
            LegacyAmbientSyncProcessResult(terminationStatus: 1, launchError: nil),
            LegacyAmbientSyncProcessResult(terminationStatus: 1, launchError: nil)
        ])
        let unloadResult = await LegacyAmbientSyncMigration.runIfNeeded(
            defaults: unloadedAfterBootout.defaults,
            homeDirectory: unloadedAfterBootout.root,
            runner: unloadRunner
        )
        precondition(unloadResult == .completed)
        precondition(!FileManager.default.fileExists(atPath: unloadedAfterBootout.plist.path))
        precondition(unloadRunner.calls.map(\.first) == ["print", "bootout", "print"])

        let conflict = try! makeFixture("conflict")
        let conflictRunner = SequencedRunner(results: [
            LegacyAmbientSyncProcessResult(terminationStatus: 0, launchError: nil),
            LegacyAmbientSyncProcessResult(terminationStatus: 1, launchError: nil),
            LegacyAmbientSyncProcessResult(terminationStatus: 0, launchError: nil)
        ])
        let conflictResult = await LegacyAmbientSyncMigration.runIfNeeded(
            defaults: conflict.defaults,
            homeDirectory: conflict.root,
            runner: conflictRunner
        )
        guard case .conflict = conflictResult else {
            preconditionFailure("A service that remains loaded must be reported as a conflict")
        }
        precondition(!conflictResult.completedSuccessfully)
        precondition(FileManager.default.fileExists(atPath: conflict.plist.path))
        precondition(conflict.defaults.integer(forKey: "MemWatch.LegacyAmbientSyncCleanupVersion") == 0)

        let completed = try! makeFixture("completed")
        let completedRunner = SequencedRunner(results: [
            LegacyAmbientSyncProcessResult(terminationStatus: 0, launchError: nil),
            LegacyAmbientSyncProcessResult(terminationStatus: 0, launchError: nil)
        ])
        let completedResult = await LegacyAmbientSyncMigration.runIfNeeded(
            defaults: completed.defaults,
            homeDirectory: completed.root,
            runner: completedRunner
        )
        precondition(completedResult == .completed)
        precondition(!FileManager.default.fileExists(atPath: completed.plist.path))
        let repeated = await LegacyAmbientSyncMigration.runIfNeeded(defaults: completed.defaults, homeDirectory: completed.root)
        precondition(repeated == .alreadyCompleted)

        let absentRoot = URL(fileURLWithPath: "/private/tmp/memwatch-migration-smoke-absent-\(ProcessInfo.processInfo.processIdentifier)")
        let absentDefaultsName = "MemWatch.LegacyMigration.absent.\(ProcessInfo.processInfo.processIdentifier)"
        let absentDefaults = UserDefaults(suiteName: absentDefaultsName)!
        absentDefaults.removePersistentDomain(forName: absentDefaultsName)
        try? FileManager.default.removeItem(at: absentRoot)
        let absent = await LegacyAmbientSyncMigration.runIfNeeded(defaults: absentDefaults, homeDirectory: absentRoot)
        precondition(absent == .noLegacyPlist)
        precondition(absentDefaults.integer(forKey: "MemWatch.LegacyAmbientSyncCleanupVersion") == 1)

        let scheduledDefaultsName = "MemWatch.LegacyMigration.schedule.\(ProcessInfo.processInfo.processIdentifier)"
        let scheduledDefaults = UserDefaults(suiteName: scheduledDefaultsName)!
        scheduledDefaults.removePersistentDomain(forName: scheduledDefaultsName)
        let scheduled = LegacyAmbientSyncMigration.scheduleIfNeeded(
            defaults: scheduledDefaults,
            homeDirectory: absentRoot
        )
        precondition(scheduled == nil)
        precondition(scheduledDefaults.integer(forKey: "MemWatch.LegacyAmbientSyncCleanupVersion") == 1)

        let fixtureRoots = [stale.root, unloadedAfterBootout.root, conflict.root, completed.root, absentRoot]
        fixtureRoots.forEach { try? FileManager.default.removeItem(at: $0) }
        [
            (stale.defaults, stale.defaultsName),
            (unloadedAfterBootout.defaults, unloadedAfterBootout.defaultsName),
            (conflict.defaults, conflict.defaultsName),
            (completed.defaults, completed.defaultsName),
            (absentDefaults, absentDefaultsName),
            (scheduledDefaults, scheduledDefaultsName)
        ].forEach { defaults, name in
            defaults.removePersistentDomain(forName: name)
        }
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

    private static func testDisplayConnectionIntentMigration() {
        let suffix = "MemWatch.DisplayFeatureSmoke.DisplayConnectionIntent.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suffix)!
        let legacy = UserDefaults(suiteName: suffix + ".legacy")!
        defaults.removePersistentDomain(forName: suffix)
        legacy.removePersistentDomain(forName: suffix + ".legacy")

        // A legacy AmbientSync request is not copied into the new MemWatch
        // intent key during the first preferences migration.
        legacy.set(true, forKey: DisplayConnectionIntentMigration.legacyDefaultsKey)
        precondition(
            DisplayPreferencesMigration.migrateIfNeeded(
                defaults: defaults,
                legacyDefaults: legacy
            )
        )
        precondition(defaults.object(forKey: DisplayConnectionIntentMigration.legacyDefaultsKey) == nil)
        precondition(!defaults.bool(forKey: DisplayConnectionIntentMigration.memWatchDefaultsKey))
        precondition(legacy.bool(forKey: DisplayConnectionIntentMigration.legacyDefaultsKey))

        precondition(DisplayConnectionIntentMigration.migrateIfNeeded(defaults: defaults))
        precondition(defaults.integer(forKey: DisplayConnectionIntentMigration.versionKey) == 1)
        precondition(!DisplayConnectionIntentMigration.migrateIfNeeded(defaults: defaults))

        // A machine that already ran DisplayPreferencesMigration v1 may have
        // the stale copied value; the corrective migration removes only that
        // deprecated key.
        defaults.removePersistentDomain(forName: suffix)
        defaults.set(1, forKey: DisplayPreferencesMigration.versionKey)
        defaults.set(true, forKey: DisplayConnectionIntentMigration.legacyDefaultsKey)
        precondition(DisplayConnectionIntentMigration.migrateIfNeeded(defaults: defaults))
        precondition(defaults.object(forKey: DisplayConnectionIntentMigration.legacyDefaultsKey) == nil)
        precondition(!defaults.bool(forKey: DisplayConnectionIntentMigration.memWatchDefaultsKey))

        // A deliberate MemWatch request uses the canonical key and survives
        // cleanup even if the deprecated copied key is still present.
        defaults.removePersistentDomain(forName: suffix)
        defaults.set(true, forKey: DisplayConnectionIntentMigration.memWatchDefaultsKey)
        defaults.set(true, forKey: DisplayConnectionIntentMigration.legacyDefaultsKey)
        precondition(DisplayConnectionIntentMigration.migrateIfNeeded(defaults: defaults))
        precondition(defaults.bool(forKey: DisplayConnectionIntentMigration.memWatchDefaultsKey))
        precondition(defaults.object(forKey: DisplayConnectionIntentMigration.legacyDefaultsKey) == nil)

        defaults.removePersistentDomain(forName: suffix)
        legacy.removePersistentDomain(forName: suffix + ".legacy")
    }
}
