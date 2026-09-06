import Foundation

enum MemoryPressure: String, CaseIterable, Sendable {
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

/// Raw page counters read from `vm_statistics64` plus the host page size.
///
/// Keeping this input separate from the resulting snapshot makes the
/// Activity Monitor-style accounting deterministic to test without invoking
/// Mach APIs.
struct VMAccountingInput: Equatable, Sendable {
    let totalBytes: UInt64
    let pageSize: UInt64
    let freeCount: UInt64
    let activeCount: UInt64
    let inactiveCount: UInt64
    let speculativeCount: UInt64
    let purgeableCount: UInt64
    let wireCount: UInt64
    let compressorPageCount: UInt64
    let externalPageCount: UInt64
    let internalPageCount: UInt64

    init(
        totalBytes: UInt64,
        pageSize: UInt64,
        freeCount: UInt64,
        activeCount: UInt64,
        inactiveCount: UInt64,
        speculativeCount: UInt64,
        purgeableCount: UInt64,
        wireCount: UInt64,
        compressorPageCount: UInt64,
        externalPageCount: UInt64,
        internalPageCount: UInt64
    ) {
        self.totalBytes = totalBytes
        self.pageSize = pageSize
        self.freeCount = freeCount
        self.activeCount = activeCount
        self.inactiveCount = inactiveCount
        self.speculativeCount = speculativeCount
        self.purgeableCount = purgeableCount
        self.wireCount = wireCount
        self.compressorPageCount = compressorPageCount
        self.externalPageCount = externalPageCount
        self.internalPageCount = internalPageCount
    }
}

/// The system memory buckets used by MemWatch.
///
/// `inactiveCount` is retained as telemetry only. It is deliberately not
/// part of `usedBytes` or `cachedFilesBytes`, because inactive pages can be
/// anonymous and are not synonymous with reclaimable file cache.
struct MemoryAccounting: Equatable, Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let appMemoryBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    /// Approximate file-backed/reclaimable memory; not part of Used Memory.
    let cachedFilesBytes: UInt64
    /// Free pages after removing speculative pages already represented by
    /// `free_count`.
    let freeBytes: UInt64

    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let speculativeBytes: UInt64
    let purgeableBytes: UInt64
    let fileBackedBytes: UInt64
    let anonymousBytes: UInt64

    static func calculate(from input: VMAccountingInput) -> MemoryAccounting {
        let rawFreeBytes = pageBytes(input.freeCount, pageSize: input.pageSize)
        let rawSpeculativeBytes = pageBytes(input.speculativeCount, pageSize: input.pageSize)
        let rawPurgeableBytes = pageBytes(input.purgeableCount, pageSize: input.pageSize)
        let rawExternalBytes = pageBytes(input.externalPageCount, pageSize: input.pageSize)
        let rawInternalBytes = pageBytes(input.internalPageCount, pageSize: input.pageSize)

        let appMemoryBytes = bounded(
            subtracting(rawInternalBytes, rawPurgeableBytes),
            by: input.totalBytes
        )
        let wiredBytes = bounded(
            pageBytes(input.wireCount, pageSize: input.pageSize),
            by: input.totalBytes
        )
        let compressedBytes = bounded(
            pageBytes(input.compressorPageCount, pageSize: input.pageSize),
            by: input.totalBytes
        )

        let usedBytes = bounded(
            adding(appMemoryBytes, wiredBytes, compressedBytes),
            by: input.totalBytes
        )

        let cachedFilesBytes = bounded(
            adding(rawExternalBytes, rawPurgeableBytes),
            by: input.totalBytes
        )

        // Speculative pages may already be included in free_count. Subtract
        // them before exposing true free RAM so they cannot be counted twice.
        let freeBytes = bounded(
            subtracting(rawFreeBytes, rawSpeculativeBytes),
            by: input.totalBytes
        )

        return MemoryAccounting(
            totalBytes: input.totalBytes,
            usedBytes: usedBytes,
            availableBytes: input.totalBytes >= usedBytes
                ? input.totalBytes - usedBytes
                : 0,
            appMemoryBytes: appMemoryBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedFilesBytes: cachedFilesBytes,
            freeBytes: freeBytes,
            activeBytes: bounded(
                pageBytes(input.activeCount, pageSize: input.pageSize),
                by: input.totalBytes
            ),
            inactiveBytes: bounded(
                pageBytes(input.inactiveCount, pageSize: input.pageSize),
                by: input.totalBytes
            ),
            speculativeBytes: bounded(rawSpeculativeBytes, by: input.totalBytes),
            purgeableBytes: bounded(rawPurgeableBytes, by: input.totalBytes),
            fileBackedBytes: bounded(rawExternalBytes, by: input.totalBytes),
            anonymousBytes: bounded(rawInternalBytes, by: input.totalBytes)
        )
    }

    static func pageBytes(_ pageCount: UInt64, pageSize: UInt64) -> UInt64 {
        guard pageCount > 0, pageSize > 0 else { return 0 }
        let (bytes, overflow) = pageCount.multipliedReportingOverflow(by: pageSize)
        return overflow ? UInt64.max : bytes
    }

    private static func adding(_ values: UInt64...) -> UInt64 {
        values.reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? UInt64.max : sum
        }
    }

    private static func subtracting(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : 0
    }

    private static func bounded(_ value: UInt64, by totalBytes: UInt64) -> UInt64 {
        min(value, totalBytes)
    }
}

struct MemorySnapshot: Sendable {
    let timestamp: Date

    let totalBytes: UInt64
    let usedBytes: UInt64
    /// User-facing headroom, defined as total physical RAM minus Memory Used.
    let availableBytes: UInt64
    let appMemoryBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedFilesBytes: UInt64
    /// True free pages after removing speculative pages.
    let freeBytes: UInt64

    /// Low-level VM telemetry. These values are not disjoint UI accounting
    /// buckets and are not used to calculate Memory Used.
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let speculativeBytes: UInt64
    let purgeableBytes: UInt64
    let fileBackedBytes: UInt64
    let anonymousBytes: UInt64

    let swapTotalBytes: UInt64
    let swapUsedBytes: UInt64
    let swapFreeBytes: UInt64

    /// Cumulative bytes moved from swap back into RAM since boot.
    let swapInBytes: UInt64

    /// Cumulative bytes moved from RAM into swap since boot.
    let swapOutBytes: UInt64

    let pressure: MemoryPressure

    init(
        timestamp: Date,
        totalBytes: UInt64,
        usedBytes: UInt64,
        availableBytes _: UInt64,
        appMemoryBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        cachedFilesBytes: UInt64,
        freeBytes: UInt64,
        activeBytes: UInt64,
        inactiveBytes: UInt64,
        speculativeBytes: UInt64,
        purgeableBytes: UInt64,
        fileBackedBytes: UInt64,
        anonymousBytes: UInt64,
        swapTotalBytes: UInt64,
        swapUsedBytes: UInt64,
        swapFreeBytes: UInt64,
        swapInBytes: UInt64,
        swapOutBytes: UInt64,
        pressure: MemoryPressure
    ) {
        let normalizedUsedBytes = min(usedBytes, totalBytes)

        self.timestamp = timestamp
        self.totalBytes = totalBytes
        self.usedBytes = normalizedUsedBytes
        // Keep the public snapshot invariant even for hand-built fixtures or
        // future callers. The accounting layer is authoritative; the
        // compatibility parameter is accepted so existing construction sites
        // can migrate without creating a second available-memory semantic.
        self.availableBytes = totalBytes - normalizedUsedBytes
        self.appMemoryBytes = appMemoryBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedFilesBytes = cachedFilesBytes
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.speculativeBytes = speculativeBytes
        self.purgeableBytes = purgeableBytes
        self.fileBackedBytes = fileBackedBytes
        self.anonymousBytes = anonymousBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapFreeBytes = swapFreeBytes
        self.swapInBytes = swapInBytes
        self.swapOutBytes = swapOutBytes
        self.pressure = pressure
    }

    init(
        timestamp: Date,
        accounting: MemoryAccounting,
        swapTotalBytes: UInt64,
        swapUsedBytes: UInt64,
        swapFreeBytes: UInt64,
        swapInBytes: UInt64,
        swapOutBytes: UInt64,
        pressure: MemoryPressure
    ) {
        self.init(
            timestamp: timestamp,
            totalBytes: accounting.totalBytes,
            usedBytes: accounting.usedBytes,
            availableBytes: accounting.availableBytes,
            appMemoryBytes: accounting.appMemoryBytes,
            wiredBytes: accounting.wiredBytes,
            compressedBytes: accounting.compressedBytes,
            cachedFilesBytes: accounting.cachedFilesBytes,
            freeBytes: accounting.freeBytes,
            activeBytes: accounting.activeBytes,
            inactiveBytes: accounting.inactiveBytes,
            speculativeBytes: accounting.speculativeBytes,
            purgeableBytes: accounting.purgeableBytes,
            fileBackedBytes: accounting.fileBackedBytes,
            anonymousBytes: accounting.anonymousBytes,
            swapTotalBytes: swapTotalBytes,
            swapUsedBytes: swapUsedBytes,
            swapFreeBytes: swapFreeBytes,
            swapInBytes: swapInBytes,
            swapOutBytes: swapOutBytes,
            pressure: pressure
        )
    }

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
///
/// Native macOS warning/critical pressure events are intentionally kept separate
/// from this numeric estimate. They remain authoritative categorical signals in
/// the UI, but they do not impose artificial percentage floors.
struct MemoryPressureEstimate: Sendable {
    let ratio: Double

    var percent: Int {
        Int((ratio * 100).rounded())
    }

    static func calculate(
        snapshot: MemorySnapshot,
        swapOutDeltaBytes: UInt64
    ) -> MemoryPressureEstimate {
        guard snapshot.totalBytes > 0 else {
            return MemoryPressureEstimate(ratio: 0)
        }

        let total = Double(snapshot.totalBytes)
        let availableRatio = Double(snapshot.availableBytes) / total
        let compressedRatio = Double(snapshot.compressedBytes) / total

        // `availableBytes` is now total memory minus App/Wired/Compressed.
        // It includes reclaimable file-backed memory, so the estimate starts
        // rising below 35% headroom and saturates at 5% or less. This is a
        // MemWatch estimate, not Activity Monitor's private percentage.
        let availabilityStress = clamp((0.35 - availableRatio) / 0.30)

        // Compression normally exists on healthy macOS systems. Start counting
        // it only after 8% of physical RAM and saturate at 35%.
        let compressionStress = clamp((compressedRatio - 0.08) / 0.27)

        // Only recent swap-out traffic is a pressure signal. Existing swap data
        // can remain allocated long after a pressure episode, so swapUsedBytes
        // must not raise this percentage by itself.
        let swapOutReferenceBytes = Double(256 * 1024 * 1024)
        let swapOutStress = clamp(Double(swapOutDeltaBytes) / swapOutReferenceBytes)

        let score = (
            availabilityStress * 0.60
            + compressionStress * 0.25
            + swapOutStress * 0.15
        )

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
        appMemoryBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        cachedFilesBytes: 0,
        freeBytes: 0,
        activeBytes: 0,
        inactiveBytes: 0,
        speculativeBytes: 0,
        purgeableBytes: 0,
        fileBackedBytes: 0,
        anonymousBytes: 0,
        swapTotalBytes: 0,
        swapUsedBytes: 0,
        swapFreeBytes: 0,
        swapInBytes: 0,
        swapOutBytes: 0,
        pressure: .normal
    )
}
