import Foundation

enum StorageHealthState: String, Equatable, Sendable {
    case normal
    case warning
    case critical

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Low Space"
        case .critical: return "Critical"
        }
    }
}

struct StorageVolumeSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let mountPath: String
    let totalBytes: UInt64
    let availableBytes: UInt64
    let isInternal: Bool
    let isReadOnly: Bool

    var usedBytes: UInt64 {
        totalBytes >= availableBytes ? totalBytes - availableBytes : 0
    }

    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var usagePercent: Int {
        Int((usageRatio * 100).rounded())
    }

    var availableRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(availableBytes) / Double(totalBytes), 0), 1)
    }

    var health: StorageHealthState {
        let gib: UInt64 = 1_024 * 1_024 * 1_024

        if availableRatio <= 0.03 || (totalBytes >= 64 * gib && availableBytes <= 5 * gib) {
            return .critical
        }

        if availableRatio <= 0.10 || (totalBytes >= 128 * gib && availableBytes <= 20 * gib) {
            return .warning
        }

        return .normal
    }
}

/// APFS/macOS capacity signals for the startup volume.
///
/// `purgeableEstimateBytes` is deliberately kept separate from cleanup scan
/// results. The same bytes may include snapshots, caches or other data that
/// macOS can reclaim on demand, so adding this number to CleanupCandidate
/// totals would double-count storage.
struct StorageSpaceIntelligence: Equatable, Sendable {
    let immediateAvailableBytes: UInt64
    let importantUsageAvailableBytes: UInt64
    let opportunisticUsageAvailableBytes: UInt64

    var purgeableEstimateBytes: UInt64 {
        importantUsageAvailableBytes > immediateAvailableBytes
            ? importantUsageAvailableBytes - immediateAvailableBytes
            : 0
    }

    static func startupVolume() -> StorageSpaceIntelligence? {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey
        ]

        guard let values = try? root.resourceValues(forKeys: keys),
              let immediate = values.volumeAvailableCapacity else {
            return nil
        }

        let immediateBytes = UInt64(max(0, immediate))
        let importantBytes = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? Int64(immediate)))
        let opportunisticBytes = UInt64(max(0, values.volumeAvailableCapacityForOpportunisticUsage ?? Int64(immediate)))

        return StorageSpaceIntelligence(
            immediateAvailableBytes: immediateBytes,
            importantUsageAvailableBytes: importantBytes,
            opportunisticUsageAvailableBytes: opportunisticBytes
        )
    }
}
