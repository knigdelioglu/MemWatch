import Foundation

enum MemoryPressure: String, CaseIterable {
    case normal
    case warning
    case critical

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

struct MemorySnapshot {
    let timestamp: Date

    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let freeBytes: UInt64
    let cachedBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64

    let swapTotalBytes: UInt64
    let swapUsedBytes: UInt64
    let swapFreeBytes: UInt64

    /// Cumulative bytes moved from swap back into RAM since boot.
    let swapInBytes: UInt64

    /// Cumulative bytes moved from RAM into swap since boot.
    let swapOutBytes: UInt64

    let pressure: MemoryPressure

    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var usagePercent: Int {
        Int((usageRatio * 100).rounded())
    }

    var swapRatio: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return min(max(Double(swapUsedBytes) / Double(swapTotalBytes), 0), 1)
    }
}

extension MemorySnapshot {
    static let empty = MemorySnapshot(
        timestamp: .now,
        totalBytes: 0,
        usedBytes: 0,
        availableBytes: 0,
        freeBytes: 0,
        cachedBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        swapTotalBytes: 0,
        swapUsedBytes: 0,
        swapFreeBytes: 0,
        swapInBytes: 0,
        swapOutBytes: 0,
        pressure: .normal
    )
}
