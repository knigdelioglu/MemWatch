import Foundation

struct BrightnessLimiterObservation: Sendable {
    let mismatchStreak: Int
    let limiterDetected: Bool
}

private struct BrightnessLimiterEvidenceTracker {
    private let minimumMismatchPercent: Int = 8
    private let minimumRequestSpan: Int = 10
    private let requiredMismatchStreak: Int = 3
    private let stableRawTolerance: Int = 2

    private(set) var displayKey: String?
    private(set) var lastCandidate: Int?
    private(set) var lastDirection: Int?
    private(set) var lastRawAfter: Int?
    private(set) var lastRawMax: Int?
    private(set) var requestMinimum: Int?
    private(set) var requestMaximum: Int?
    private(set) var distinctCandidates = Set<Int>()
    private(set) var mismatchStreak = 0

    mutating func reset() {
        displayKey = nil
        lastCandidate = nil
        lastDirection = nil
        lastRawAfter = nil
        lastRawMax = nil
        requestMinimum = nil
        requestMaximum = nil
        distinctCandidates.removeAll(keepingCapacity: true)
        mismatchStreak = 0
    }

    mutating func observe(
        result: M1DDCBrightnessWriteResult,
        requested: Int,
        displayKey: String
    ) -> BrightnessLimiterObservation {
        guard result.writeAccepted,
              isReadbackMismatch(result.status),
              result.matchedTarget == false,
              let actualAfter = result.actualUIPercentAfter ?? result.readbackBrightnessPercent,
              let rawAfter = result.rawAfter,
              let rawMax = result.rawMax,
              let computedRawTarget = result.computedRawTarget,
              !DDCBrightnessScale.isMatched(
                  rawAfter: rawAfter,
                  computedRawTarget: computedRawTarget
              ),
              abs(requested - actualAfter) >= minimumMismatchPercent else {
            reset()
            return BrightnessLimiterObservation(mismatchStreak: 0, limiterDetected: false)
        }

        let isSameDisplay = self.displayKey == nil || self.displayKey == displayKey
        let rawAfterIsStable = lastRawAfter.map {
            abs(rawAfter - $0) <= stableRawTolerance
        } ?? true
        let rawMaxIsStable = lastRawMax.map {
            abs(rawMax - $0) <= max(stableRawTolerance, rawMax / 50)
        } ?? true
        let direction = lastCandidate.map {
            directionSign(for: requested - $0)
        } ?? 0
        let directionIsStable = lastDirection == nil || direction == 0 || direction == lastDirection

        let continuesSequence = isSameDisplay
            && rawAfterIsStable
            && rawMaxIsStable
            && directionIsStable

        if continuesSequence {
            mismatchStreak += 1
        } else {
            mismatchStreak = 1
            lastDirection = nil
            requestMinimum = requested
            requestMaximum = requested
            distinctCandidates.removeAll(keepingCapacity: true)
        }

        if direction != 0 {
            lastDirection = lastDirection ?? direction
        }
        self.displayKey = displayKey
        lastCandidate = requested
        lastRawAfter = rawAfter
        lastRawMax = rawMax
        requestMinimum = min(requestMinimum ?? requested, requested)
        requestMaximum = max(requestMaximum ?? requested, requested)
        distinctCandidates.insert(requested)

        let requestSpan = (requestMaximum ?? requested) - (requestMinimum ?? requested)
        let readbackIsStableLimit = actualAfter <= (requestMinimum ?? requested) - minimumMismatchPercent
            || actualAfter >= (requestMaximum ?? requested) + minimumMismatchPercent
        let limiterDetected = mismatchStreak >= requiredMismatchStreak
            && distinctCandidates.count >= requiredMismatchStreak
            && requestSpan >= minimumRequestSpan
            && readbackIsStableLimit

        return BrightnessLimiterObservation(
            mismatchStreak: mismatchStreak,
            limiterDetected: limiterDetected
        )
    }

    private func directionSign(for delta: Int) -> Int {
        if delta == 0 { return 0 }
        return delta > 0 ? 1 : -1
    }

    private func isReadbackMismatch(_ status: M1DDCBrightnessWriteStatus) -> Bool {
        switch status {
        case .writeAcceptedReadbackUncertain, .writeAcceptedButReadbackLimited:
            return true
        case .success, .writeFailed, .readbackUnavailable:
            return false
        }
    }
}

struct BrightnessAutoWriteOutcome {
    let statusText: String
    let writeDiagnosis: String
    /// The raw readback-derived value, when one exists. It is retained for
    /// diagnostics and is not necessarily the value used as the next policy
    /// reference when readback reliability is uncertain.
    let actualAfter: Int
    /// The logical value used by the auto loop after an accepted command.
    let referenceAfter: Int
    /// For an uncertain accepted write this is the requested value, not the
    /// stale raw readback, so persistence remains a useful fallback.
    let persistedReadback: Int?
    let readbackReliability: BrightnessReadbackReliability
    let mismatchStreak: Int
    let limiterDetected: Bool
    let shouldSetCooldown: Bool
}

final class BrightnessAutoWriteOutcomePlanner {
    private var limiterEvidence = BrightnessLimiterEvidenceTracker()

    func resetLimiterEvidence() {
        limiterEvidence.reset()
    }

    func observeLimiterEvidence(
        result: M1DDCBrightnessWriteResult,
        requested: Int,
        displayKey: String
    ) -> BrightnessLimiterObservation {
        limiterEvidence.observe(
            result: result,
            requested: requested,
            displayKey: displayKey
        )
    }

    func plan(
        result: M1DDCBrightnessWriteResult,
        candidate: Int,
        displayKey: String = "unknown"
    ) -> BrightnessAutoWriteOutcome {
        guard result.writeAccepted else {
            return planFailure(result: result, currentActual: candidate)
        }
        let observedAfter = result.actualUIPercentAfter ?? result.readbackBrightnessPercent ?? candidate
        let matchedTarget = result.matchedTarget == true
        let reliability = result.readbackReliability

        let evidence = observeLimiterEvidence(
            result: result,
            requested: candidate,
            displayKey: displayKey
        )

        switch result.status {
        case .success:
            if matchedTarget {
                return BrightnessAutoWriteOutcome(
                    statusText: "Brightness \(observedAfter)%",
                    writeDiagnosis: "DDC write succeeded and the readback matched the requested target.",
                    actualAfter: observedAfter,
                    referenceAfter: observedAfter,
                    persistedReadback: observedAfter,
                    readbackReliability: reliability,
                    mismatchStreak: evidence.mismatchStreak,
                    limiterDetected: evidence.limiterDetected,
                    shouldSetCooldown: evidence.limiterDetected
                )
            }
            return BrightnessAutoWriteOutcome(
                statusText: "Brightness \(candidate)% (readback uncertain)",
                writeDiagnosis: "DDC write was accepted but the success status lacked a matching target; readback remains uncertain.",
                actualAfter: observedAfter,
                referenceAfter: candidate,
                persistedReadback: candidate,
                readbackReliability: reliability,
                mismatchStreak: evidence.mismatchStreak,
                limiterDetected: evidence.limiterDetected,
                shouldSetCooldown: evidence.limiterDetected
            )
        case .writeAcceptedReadbackUncertain, .writeAcceptedButReadbackLimited:
            return BrightnessAutoWriteOutcome(
                statusText: evidence.limiterDetected
                    ? "Brightness \(candidate)% (limiter evidence detected)"
                    : "Brightness \(candidate)% (readback uncertain)",
                writeDiagnosis: "DDC write accepted, but the readback did not match the target. Limiter evidence is inconclusive until repeated stable mismatches are observed.",
                actualAfter: observedAfter,
                referenceAfter: candidate,
                persistedReadback: candidate,
                readbackReliability: reliability,
                mismatchStreak: evidence.mismatchStreak,
                limiterDetected: evidence.limiterDetected,
                shouldSetCooldown: evidence.limiterDetected
            )
        case .readbackUnavailable:
            return BrightnessAutoWriteOutcome(
                statusText: "Brightness \(candidate)% (readback unavailable)",
                writeDiagnosis: "DDC write was accepted, but no readback was available to confirm the target.",
                actualAfter: observedAfter,
                referenceAfter: candidate,
                persistedReadback: candidate,
                readbackReliability: reliability,
                mismatchStreak: evidence.mismatchStreak,
                limiterDetected: evidence.limiterDetected,
                shouldSetCooldown: evidence.limiterDetected
            )
        case .writeFailed:
            return planFailure(result: result, currentActual: candidate)
        }
    }

    func planFailure(
        result: M1DDCBrightnessWriteResult,
        currentActual: Int
    ) -> BrightnessAutoWriteOutcome {
        resetLimiterEvidence()
        return BrightnessAutoWriteOutcome(
            statusText: result.message.isEmpty ? "Yazma hatası" : "Yazma hatası: \(result.message)",
            writeDiagnosis: "DDC write failed. Error details: \(result.message)",
            actualAfter: currentActual,
            referenceAfter: currentActual,
            persistedReadback: nil,
            readbackReliability: .unavailable,
            mismatchStreak: 0,
            limiterDetected: false,
            shouldSetCooldown: false
        )
    }
}
