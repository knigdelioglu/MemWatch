import CoreGraphics
import Foundation

@main
struct DisplayLatestIntentTests {
    static func main() {
        var volumeGate = LatestValueWriteGate()
        var logicalVolume = 50
        var pendingVolume: [(generation: UInt64, value: Int)] = []

        for value in 1...20 {
            let generation = volumeGate.startRequest()
            pendingVolume.append((generation, value))
        }

        let latestSlider = pendingVolume.removeLast()
        apply(
            generation: latestSlider.generation,
            value: latestSlider.value,
            gate: volumeGate,
            logicalValue: &logicalVolume
        )
        for request in pendingVolume.reversed() {
            apply(
                generation: request.generation,
                value: request.value,
                gate: volumeGate,
                logicalValue: &logicalVolume
            )
        }
        precondition(logicalVolume == 20, "Reordered slider completions must leave the latest volume intent applied")

        let muteGeneration = volumeGate.startRequest()
        let staleSliderGeneration = latestSlider.generation
        apply(
            generation: staleSliderGeneration,
            value: 70,
            gate: volumeGate,
            logicalValue: &logicalVolume
        )
        precondition(logicalVolume == 20, "A stale slider completion must not undo a newer mute intent")
        apply(
            generation: muteGeneration,
            value: 0,
            gate: volumeGate,
            logicalValue: &logicalVolume
        )
        precondition(logicalVolume == 0, "Mute must win over an older in-flight slider write")

        var brightnessGate = LatestValueWriteGate()
        let manualGeneration = brightnessGate.startRequest()
        let autoGeneration = brightnessGate.startRequest()
        precondition(!brightnessGate.accepts(manualGeneration), "Auto mode intent must invalidate an older manual write")
        precondition(brightnessGate.accepts(autoGeneration), "The latest brightness intent must remain eligible")

        let secondManualGeneration = brightnessGate.startRequest()
        precondition(!brightnessGate.accepts(autoGeneration), "A manual slider interaction must invalidate an older auto write")
        precondition(brightnessGate.accepts(secondManualGeneration), "The latest manual brightness intent must remain eligible")

        testDisplayOperationGatesAndTargetEpoch()

        print("PASS display latest-intent ordering and target-operation gates")
    }

    private static func testDisplayOperationGatesAndTargetEpoch() {
        let targetGate = TargetDisplayOperationGate()
        let targetID: CGDirectDisplayID = 4242
        let unavailable = targetGate.snapshot()

        precondition(!DisplayOperationPolicy.externalReadOperationsAllowed(
            isRunning: true,
            powerState: .active,
            targetReadiness: unavailable.readiness
        ), "External reads must fail closed before target readiness")
        precondition(!DisplayOperationPolicy.externalInteractiveOperationsAllowed(
            isRunning: true,
            powerState: .active,
            isPostWakeRefreshInProgress: true,
            targetReadiness: unavailable.readiness
        ), "Post-wake user input must remain blocked before target readiness")

        let targetGeneration = targetGate.markReady(displayID: targetID)
        let ready = targetGate.snapshot()
        precondition(ready.generation == targetGeneration && ready.displayID == targetID)
        precondition(DisplayOperationPolicy.externalReadOperationsAllowed(
            isRunning: true,
            powerState: .active,
            targetReadiness: ready.readiness
        ), "Controlled reads may run after target readiness")
        precondition(!DisplayOperationPolicy.externalInteractiveOperationsAllowed(
            isRunning: true,
            powerState: .active,
            isPostWakeRefreshInProgress: true,
            targetReadiness: ready.readiness
        ), "Interactive DDC must remain blocked during controlled refresh")
        precondition(DisplayOperationPolicy.externalInteractiveOperationsAllowed(
            isRunning: true,
            powerState: .active,
            isPostWakeRefreshInProgress: false,
            targetReadiness: ready.readiness
        ), "Interactive DDC may resume after controlled refresh")

        targetGate.invalidate()
        precondition(!targetGate.accepts(targetGeneration, displayID: targetID),
                     "A target transition must invalidate a queued external intent")
        precondition(!targetGate.snapshot().isReady, "Target invalidation must close external operations")
    }

    private static func apply(
        generation: UInt64,
        value: Int,
        gate: LatestValueWriteGate,
        logicalValue: inout Int
    ) {
        guard gate.accepts(generation) else { return }
        logicalValue = value
    }
}
