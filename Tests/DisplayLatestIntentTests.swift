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

        print("PASS display latest-intent volume and brightness completion ordering")
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
