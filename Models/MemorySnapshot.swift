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

/// A transparent 0...100 MemWatch estimate for UI display.
///
/// macOS does not expose Activity Monitor's private memory-pressure percentage,
/// so this score intentionally does not claim to reproduce it. The estimate
/// combines currently available RAM, compression pressure and *active* swap-out
/// traffic. Historical idle swap allocation is deliberately excluded.
struct MemoryPressureEstimate {
    let ratio: Double

    var percent: Int {
        Int((ratio * 100).rounded())
    }

    static func calculate(
        snapshot: MemorySnapshot,
        swapOutDeltaBytes: UInt64,
        effectivePressure: MemoryPressure
    ) -> MemoryPressureEstimate {
        guard snapshot.totalBytes > 0 else {
            return MemoryPressureEstimate(ratio: 0)
        }

        let total = Double(snapshot.totalBytes)
        let availableRatio = Double(snapshot.availableBytes) / total
        let compressedRatio = Double(snapshot.compressedBytes) / total

        // Availability contributes most strongly. There is no availability
        // penalty above 40%, and it reaches full stress at 5% or less.
        let availabilityStress = clamp((0.40 - availableRatio) / 0.35)

        // Compression normally exists on healthy macOS systems. Start counting
        // it only after 5% of physical RAM and saturate at 35%.
        let compressionStress = clamp((compressedRatio - 0.05) / 0.30)

        // Only recent swap-out traffic is a pressure signal. Existing swap data
        // can remain allocated long after a pressure episode, so swapUsedBytes
        // must not raise this percentage by itself.
        let swapOutReferenceBytes = Double(256 * 1024 * 1024)
        let swapOutStress = clamp(Double(swapOutDeltaBytes) / swapOutReferenceBytes)

        var score = (
            availabilityStress * 0.60
            + compressionStress * 0.25
            + swapOutStress * 0.15
        )

        // Keep the numeric estimate consistent with the effective health state,
        // including native DispatchSource memory-pressure events when available.
        switch effectivePressure {
        case .normal:
            break
        case .warning:
            score = max(score, 0.60)
        case .critical:
            score = max(score, 0.90)
        }

        return MemoryPressureEstimate(ratio: clamp(score))
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
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
