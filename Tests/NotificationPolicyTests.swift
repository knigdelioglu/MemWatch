import Foundation

@main
struct NotificationPolicyTests {
    static func main() {
        testIdleStatesDoNotNotify()
        testActiveSwapNotifies()
        testDuplicateIsSuppressedWithinCooldown()
        testEscalationNotifiesImmediately()
        testCriticalEscalationNotifiesImmediately()
        testRecoveryNotifiesOnce()
        testRepeatAfterCooldown()
        testResetRearmsPolicy()

        print("MemWatch notification policy tests passed")
    }

    private static func testIdleStatesDoNotNotify() {
        let engine = NotificationPolicyEngine()
        let now = Date(timeIntervalSince1970: 1_000)

        precondition(engine.evaluate(state: .stable, summary: "stable", now: now) == nil)
        precondition(engine.evaluate(state: .idleSwap, summary: "idle", now: now.addingTimeInterval(5)) == nil)
        precondition(engine.evaluate(state: .readback, summary: "readback", now: now.addingTimeInterval(10)) == nil)
    }

    private static func testActiveSwapNotifies() {
        let engine = NotificationPolicyEngine()
        let alert = engine.evaluate(
            state: .activeSwap,
            summary: "RAM pressure is causing sustained swap writes",
            now: Date(timeIntervalSince1970: 2_000)
        )

        precondition(alert?.kind == .activeSwap)
    }

    private static func testDuplicateIsSuppressedWithinCooldown() {
        let engine = NotificationPolicyEngine(
            configuration: NotificationPolicyConfiguration(repeatCooldown: 900)
        )
        let start = Date(timeIntervalSince1970: 3_000)

        precondition(engine.evaluate(state: .activeSwap, summary: "active", now: start) != nil)
        precondition(engine.evaluate(state: .activeSwap, summary: "active", now: start.addingTimeInterval(60)) == nil)
    }

    private static func testEscalationNotifiesImmediately() {
        let engine = NotificationPolicyEngine()
        let start = Date(timeIntervalSince1970: 4_000)

        precondition(engine.evaluate(state: .activeSwap, summary: "active", now: start)?.kind == .activeSwap)
        precondition(
            engine.evaluate(
                state: .pressure,
                summary: "pressure",
                now: start.addingTimeInterval(5)
            )?.kind == .memoryPressure
        )
    }

    private static func testCriticalEscalationNotifiesImmediately() {
        let engine = NotificationPolicyEngine()
        let start = Date(timeIntervalSince1970: 5_000)

        precondition(engine.evaluate(state: .pressure, summary: "pressure", now: start)?.kind == .memoryPressure)
        precondition(
            engine.evaluate(
                state: .critical,
                summary: "critical",
                now: start.addingTimeInterval(5)
            )?.kind == .critical
        )
    }

    private static func testRecoveryNotifiesOnce() {
        let engine = NotificationPolicyEngine()
        let start = Date(timeIntervalSince1970: 6_000)

        precondition(engine.evaluate(state: .activeSwap, summary: "active", now: start) != nil)
        precondition(
            engine.evaluate(
                state: .idleSwap,
                summary: "idle",
                now: start.addingTimeInterval(5)
            )?.kind == .recovered
        )
        precondition(
            engine.evaluate(
                state: .stable,
                summary: "stable",
                now: start.addingTimeInterval(10)
            ) == nil
        )
    }

    private static func testRepeatAfterCooldown() {
        let engine = NotificationPolicyEngine(
            configuration: NotificationPolicyConfiguration(repeatCooldown: 60)
        )
        let start = Date(timeIntervalSince1970: 7_000)

        precondition(engine.evaluate(state: .pressure, summary: "pressure", now: start) != nil)
        precondition(engine.evaluate(state: .pressure, summary: "pressure", now: start.addingTimeInterval(30)) == nil)
        precondition(engine.evaluate(state: .pressure, summary: "pressure", now: start.addingTimeInterval(61)) != nil)
    }

    private static func testResetRearmsPolicy() {
        let engine = NotificationPolicyEngine()
        let start = Date(timeIntervalSince1970: 8_000)

        precondition(engine.evaluate(state: .activeSwap, summary: "active", now: start) != nil)
        engine.reset()
        precondition(engine.evaluate(state: .activeSwap, summary: "active", now: start.addingTimeInterval(5)) != nil)
    }
}
