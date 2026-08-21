import Foundation

enum StorageHealthState: String, Equatable {
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

struct StorageVolumeSnapshot: Identifiable, Equatable {
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
