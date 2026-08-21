import Foundation

enum MemoryPressure: String, CaseIterable, Sendable {
    case normal
    case warning
    case critical

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

struct MemorySnapshot: Sendable {
    let timestamp: Date
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let appMemoryBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let freeBytes: UInt64
    let swapUsedBytes: UInt64
    let swapInBytes: UInt64
    let swapOutBytes: UInt64
    var swapInRateBytesPerSecond: Double
    var swapOutRateBytesPerSecond: Double
    let pressure: MemoryPressure

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var usedPercent: Int {
        Int((usedFraction * 100).rounded())
    }

    var isActivelySwapping: Bool {
        swapInRateBytesPerSecond > 0 || swapOutRateBytesPerSecond > 0
    }

    var isActivelySwappingOut: Bool {
        swapOutRateBytesPerSecond > 0
    }
}

extension MemorySnapshot {
    static let empty = MemorySnapshot(
        timestamp: .distantPast,
        totalBytes: 0,
        usedBytes: 0,
        availableBytes: 0,
        appMemoryBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        cachedBytes: 0,
        freeBytes: 0,
        swapUsedBytes: 0,
        swapInBytes: 0,
        swapOutBytes: 0,
        swapInRateBytesPerSecond: 0,
        swapOutRateBytesPerSecond: 0,
        pressure: .normal
    )
}
