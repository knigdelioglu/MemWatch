import Foundation

@main
struct StorageNotificationPolicyTests {
    static let gib: UInt64 = 1_024 * 1_024 * 1_024

    static func main() {
        testNormalDoesNotAlert()
        testWarningAlertsOnce()
        testCriticalEscalationAlertsImmediately()
        testPersistentWarningRespectsCooldown()
        testWarningReentryAlertsAfterRecovery()
        testRemovedVolumeStateIsDiscarded()
        print("MemWatch storage notification policy tests passed")
    }

    static func testNormalDoesNotAlert() {
        let engine = StorageNotificationPolicyEngine()
        let alerts = engine.evaluate(volumes: [volume(id: "disk", free: 100 * gib)], now: Date(timeIntervalSince1970: 0))
        precondition(alerts.isEmpty)
    }

    static func testWarningAlertsOnce() {
        let engine = StorageNotificationPolicyEngine()
        let start = Date(timeIntervalSince1970: 0)
        let warning = volume(id: "disk", free: 40 * gib)

        let first = engine.evaluate(volumes: [warning], now: start)
        let second = engine.evaluate(volumes: [warning], now: start.addingTimeInterval(60))

        precondition(first.count == 1 && first[0].kind == .lowSpace)
        precondition(second.isEmpty)
    }

    static func testCriticalEscalationAlertsImmediately() {
        let engine = StorageNotificationPolicyEngine()
        let start = Date(timeIntervalSince1970: 0)

        _ = engine.evaluate(volumes: [volume(id: "disk", free: 40 * gib)], now: start)
        let critical = engine.evaluate(
            volumes: [volume(id: "disk", free: 10 * gib)],
            now: start.addingTimeInterval(60)
        )

        precondition(critical.count == 1 && critical[0].kind == .criticalSpace)
    }

    static func testPersistentWarningRespectsCooldown() {
        let config = StorageNotificationPolicyConfiguration(repeatCooldown: 300)
        let engine = StorageNotificationPolicyEngine(configuration: config)
        let start = Date(timeIntervalSince1970: 0)
        let warning = volume(id: "disk", free: 40 * gib)

        _ = engine.evaluate(volumes: [warning], now: start)
        let early = engine.evaluate(volumes: [warning], now: start.addingTimeInterval(299))
        let repeatAlert = engine.evaluate(volumes: [warning], now: start.addingTimeInterval(300))

        precondition(early.isEmpty)
        precondition(repeatAlert.count == 1 && repeatAlert[0].kind == .lowSpace)
    }

    static func testWarningReentryAlertsAfterRecovery() {
        let engine = StorageNotificationPolicyEngine()
        let start = Date(timeIntervalSince1970: 0)

        _ = engine.evaluate(volumes: [volume(id: "disk", free: 40 * gib)], now: start)
        _ = engine.evaluate(volumes: [volume(id: "disk", free: 100 * gib)], now: start.addingTimeInterval(60))
        let reentry = engine.evaluate(volumes: [volume(id: "disk", free: 40 * gib)], now: start.addingTimeInterval(120))

        precondition(reentry.count == 1 && reentry[0].kind == .lowSpace)
    }

    static func testRemovedVolumeStateIsDiscarded() {
        let engine = StorageNotificationPolicyEngine()
        let start = Date(timeIntervalSince1970: 0)

        _ = engine.evaluate(volumes: [volume(id: "external", free: 40 * gib)], now: start)
        _ = engine.evaluate(volumes: [], now: start.addingTimeInterval(60))
        let reattached = engine.evaluate(
            volumes: [volume(id: "external", free: 40 * gib)],
            now: start.addingTimeInterval(120)
        )

        precondition(reattached.count == 1)
    }

    static func volume(id: String, free: UInt64) -> StorageVolumeSnapshot {
        StorageVolumeSnapshot(
            id: id,
            name: "Test Disk",
            mountPath: "/Volumes/Test",
            totalBytes: 500 * gib,
            availableBytes: free,
            isInternal: false,
            isReadOnly: false
        )
    }
}
