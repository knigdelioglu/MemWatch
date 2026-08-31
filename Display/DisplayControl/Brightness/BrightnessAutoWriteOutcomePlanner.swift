import Foundation

struct BrightnessAutoWriteOutcome {
    let statusText: String
    let writeDiagnosis: String
    let actualAfter: Int
    let persistedReadback: Int?
    let shouldSetCooldown: Bool
}

final class BrightnessAutoWriteOutcomePlanner {
    func plan(
        result: M1DDCBrightnessWriteResult,
        candidate: Int
    ) -> BrightnessAutoWriteOutcome {
        let actualAfter = result.actualUIPercentAfter ?? result.readbackBrightnessPercent ?? candidate

        if result.status == .writeAcceptedButReadbackLimited {
            return BrightnessAutoWriteOutcome(
                statusText: result.message,
                writeDiagnosis: "DDC write accepted but monitor did not change brightness. Possible monitor-side limiter.",
                actualAfter: actualAfter,
                persistedReadback: result.actualUIPercentAfter ?? result.readbackBrightnessPercent ?? candidate,
                shouldSetCooldown: true
            )
        }

        return BrightnessAutoWriteOutcome(
            statusText: result.actualUIPercentAfter.map { "Brightness \($0)%" } ?? "Brightness \(candidate)%",
            writeDiagnosis: "DDC write succeeded. Brightness successfully updated towards target.",
            actualAfter: actualAfter,
            persistedReadback: result.actualUIPercentAfter ?? result.readbackBrightnessPercent ?? candidate,
            shouldSetCooldown: false
        )
    }

    func planFailure(
        result: M1DDCBrightnessWriteResult,
        currentActual: Int
    ) -> BrightnessAutoWriteOutcome {
        BrightnessAutoWriteOutcome(
            statusText: result.message.isEmpty ? "Yazma hatası" : "Yazma hatası: \(result.message)",
            writeDiagnosis: "DDC write failed. Error details: \(result.message)",
            actualAfter: currentActual,
            persistedReadback: nil,
            shouldSetCooldown: false
        )
    }
}
