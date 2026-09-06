import Foundation

@main
struct MemoryCollectorSmoke {
    static func main() {
        accountingUsesActivityMonitorBuckets()
        speculativePagesAreSubtractedOnce()
        inactivePagesDoNotBecomeCache()
        accountingHandlesUnderflowOverflowAndZeros()

        let snapshot = MemoryCollector().collect()

        precondition(snapshot.totalBytes > 0, "Total RAM must be greater than zero")
        precondition(snapshot.usedBytes <= snapshot.totalBytes, "Used RAM cannot exceed total RAM")
        precondition(snapshot.availableBytes <= snapshot.totalBytes, "Available RAM cannot exceed total RAM")
        precondition(
            snapshot.usedBytes + snapshot.availableBytes == snapshot.totalBytes,
            "Used plus available headroom must cover physical RAM"
        )
        precondition(snapshot.appMemoryBytes <= snapshot.totalBytes, "App memory cannot exceed total RAM")
        precondition(snapshot.activeBytes <= snapshot.totalBytes, "Active RAM cannot exceed total RAM")
        precondition(snapshot.wiredBytes <= snapshot.totalBytes, "Wired RAM cannot exceed total RAM")
        precondition(snapshot.compressedBytes <= snapshot.totalBytes, "Compressed RAM cannot exceed total RAM")
        precondition(snapshot.cachedFilesBytes <= snapshot.totalBytes, "Cached files cannot exceed total RAM")
        precondition(snapshot.freeBytes <= snapshot.totalBytes, "True free RAM cannot exceed total RAM")
        precondition(snapshot.swapUsedBytes <= snapshot.swapTotalBytes || snapshot.swapTotalBytes == 0, "Swap used cannot exceed swap total")

        print("MemWatch collector smoke test passed")
        print("RAM: \(snapshot.usedBytes)/\(snapshot.totalBytes)")
        print("App: \(snapshot.appMemoryBytes)")
        print("Compressed: \(snapshot.compressedBytes)")
        print("Wired: \(snapshot.wiredBytes)")
        print("Cached files: \(snapshot.cachedFilesBytes)")
        print("True free: \(snapshot.freeBytes)")
        print("Swap: \(snapshot.swapUsedBytes)/\(snapshot.swapTotalBytes)")
        print("Swap-in cumulative: \(snapshot.swapInBytes)")
        print("Swap-out cumulative: \(snapshot.swapOutBytes)")
    }

    private static func accountingUsesActivityMonitorBuckets() {
        let pageSize: UInt64 = 4096
        let input = makeInput(
            free: 40,
            active: 12,
            inactive: 90,
            speculative: 8,
            purgeable: 10,
            wired: 20,
            compressed: 5,
            external: 30,
            internalPageCount: 100,
            totalBytes: 1_000 * pageSize,
            pageSize: pageSize
        )

        let result = MemoryAccounting.calculate(from: input)

        expect(result.appMemoryBytes == 90 * pageSize, "App memory must subtract purgeable pages")
        expect(result.wiredBytes == 20 * pageSize, "Wired memory must use wire_count")
        expect(result.compressedBytes == 5 * pageSize, "Compressed memory must use compressor_page_count")
        expect(result.usedBytes == (90 + 20 + 5) * pageSize, "Used memory must sum App, Wired and Compressed")
        expect(result.cachedFilesBytes == (30 + 10) * pageSize, "Cached files must use external plus purgeable pages")
        expect(result.freeBytes == (40 - 8) * pageSize, "True free must subtract speculative pages")
        expect(result.availableBytes == result.totalBytes - result.usedBytes, "Available must be total minus used")
    }

    private static func speculativePagesAreSubtractedOnce() {
        let input = makeInput(
            free: 100,
            active: 0,
            inactive: 0,
            speculative: 25,
            purgeable: 0,
            wired: 0,
            compressed: 0,
            external: 0,
            internalPageCount: 0,
            totalBytes: 1_000 * 4096,
            pageSize: 4096
        )

        let result = MemoryAccounting.calculate(from: input)
        expect(result.freeBytes == 75 * 4096, "Speculative pages must not be counted twice")
        expect(result.cachedFilesBytes == 0, "Speculative pages are not cached files")
    }

    private static func inactivePagesDoNotBecomeCache() {
        let withoutInactive = MemoryAccounting.calculate(from: makeInput(inactive: 0))
        let withInactive = MemoryAccounting.calculate(from: makeInput(inactive: 800))

        expect(
            withoutInactive.usedBytes == withInactive.usedBytes,
            "Inactive pages must not directly change Memory Used"
        )
        expect(
            withoutInactive.cachedFilesBytes == withInactive.cachedFilesBytes,
            "Inactive pages must not directly become Cached Files"
        )
    }

    private static func accountingHandlesUnderflowOverflowAndZeros() {
        let underflow = MemoryAccounting.calculate(
            from: makeInput(
                free: 1,
                active: 0,
                inactive: 0,
                speculative: 2,
                purgeable: 4,
                wired: 0,
                compressed: 0,
                external: 0,
                internalPageCount: 1,
                totalBytes: 4096,
                pageSize: 4096
            )
        )
        expect(underflow.appMemoryBytes == 0, "App memory subtraction must not underflow")
        expect(underflow.freeBytes == 0, "Free minus speculative must not underflow")

        let overflow = MemoryAccounting.calculate(
            from: makeInput(
                free: UInt64.max,
                active: UInt64.max,
                inactive: UInt64.max,
                speculative: UInt64.max,
                purgeable: UInt64.max,
                wired: UInt64.max,
                compressed: UInt64.max,
                external: UInt64.max,
                internalPageCount: UInt64.max,
                totalBytes: 4096,
                pageSize: UInt64.max
            )
        )
        expect(overflow.usedBytes <= overflow.totalBytes, "Overflow must clamp Used memory")
        expect(overflow.availableBytes <= overflow.totalBytes, "Overflow must clamp Available memory")
        expect(overflow.cachedFilesBytes <= overflow.totalBytes, "Overflow must clamp Cached Files")

        let zero = MemoryAccounting.calculate(
            from: makeInput(
                free: UInt64.max,
                active: UInt64.max,
                inactive: UInt64.max,
                speculative: UInt64.max,
                purgeable: UInt64.max,
                wired: UInt64.max,
                compressed: UInt64.max,
                external: UInt64.max,
                internalPageCount: UInt64.max,
                totalBytes: 0,
                pageSize: 0
            )
        )
        expect(zero.usedBytes == 0 && zero.availableBytes == 0, "Zero-sized memory must remain zero")
    }

    private static func makeInput(
        free: UInt64 = 40,
        active: UInt64 = 12,
        inactive: UInt64 = 90,
        speculative: UInt64 = 8,
        purgeable: UInt64 = 10,
        wired: UInt64 = 20,
        compressed: UInt64 = 5,
        external: UInt64 = 30,
        internalPageCount: UInt64 = 100,
        totalBytes: UInt64 = 1_000 * 4096,
        pageSize: UInt64 = 4096
    ) -> VMAccountingInput {
        VMAccountingInput(
            totalBytes: totalBytes,
            pageSize: pageSize,
            freeCount: free,
            activeCount: active,
            inactiveCount: inactive,
            speculativeCount: speculative,
            purgeableCount: purgeable,
            wireCount: wired,
            compressorPageCount: compressed,
            externalPageCount: external,
            internalPageCount: internalPageCount
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
