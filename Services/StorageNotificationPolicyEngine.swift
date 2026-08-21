import Foundation

enum StorageAlertKind: String, Equatable {
    case lowSpace
    case criticalSpace
}

struct StorageAlertPayload: Equatable {
    let kind: StorageAlertKind
    let volumeID: String
    let title: String
    let body: String
}

struct StorageNotificationPolicyConfiguration {
    var repeatCooldown: TimeInterval = 6 * 60 * 60
}

final class StorageNotificationPolicyEngine {
    private let configuration: StorageNotificationPolicyConfiguration
    private var lastHealthByVolume: [String: StorageHealthState] = [:]
    private var lastAlertDateByVolume: [String: Date] = [:]

    init(configuration: StorageNotificationPolicyConfiguration = .init()) {
        self.configuration = configuration
    }

    func evaluate(
        volumes: [StorageVolumeSnapshot],
        now: Date = .now
    ) -> [StorageAlertPayload] {
        let currentIDs = Set(volumes.map(\.id))
        lastHealthByVolume = lastHealthByVolume.filter { currentIDs.contains($0.key) }
        lastAlertDateByVolume = lastAlertDateByVolume.filter { currentIDs.contains($0.key) }

        var alerts: [StorageAlertPayload] = []

        for volume in volumes {
            let previous = lastHealthByVolume[volume.id] ?? .normal
            let current = volume.health
            defer { lastHealthByVolume[volume.id] = current }

            guard current != .normal else { continue }

            let firstEntry = previous == .normal
            let escalation = severity(current) > severity(previous)
            let cooldownExpired: Bool

            if let lastDate = lastAlertDateByVolume[volume.id] {
                cooldownExpired = now.timeIntervalSince(lastDate) >= max(configuration.repeatCooldown, 0)
            } else {
                cooldownExpired = true
            }

            guard firstEntry || escalation || cooldownExpired else { continue }

            lastAlertDateByVolume[volume.id] = now
            alerts.append(payload(for: volume))
        }

        return alerts
    }

    func reset() {
        lastHealthByVolume.removeAll(keepingCapacity: true)
        lastAlertDateByVolume.removeAll(keepingCapacity: true)
    }

    private func payload(for volume: StorageVolumeSnapshot) -> StorageAlertPayload {
        let free = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: volume.availableBytes),
            countStyle: .file
        )

        switch volume.health {
        case .critical:
            return StorageAlertPayload(
                kind: .criticalSpace,
                volumeID: volume.id,
                title: "Storage critically low",
                body: "\(volume.name) has only \(free) free."
            )
        case .warning:
            return StorageAlertPayload(
                kind: .lowSpace,
                volumeID: volume.id,
                title: "Storage space is low",
                body: "\(volume.name) has \(free) free."
            )
        case .normal:
            preconditionFailure("Normal storage health must not generate an alert")
        }
    }

    private func severity(_ health: StorageHealthState) -> Int {
        switch health {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }
}
