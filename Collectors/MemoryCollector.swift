import Darwin
import Foundation

final class MemoryCollector {
    func collect() -> MemorySnapshot {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let vm = readVMStatistics()
        let swap = readSwapUsage()
        let pageSize = UInt64(vm_kernel_page_size)

        let accounting = MemoryAccounting.calculate(
            from: VMAccountingInput(
                totalBytes: totalBytes,
                pageSize: pageSize,
                freeCount: UInt64(vm.free_count),
                activeCount: UInt64(vm.active_count),
                inactiveCount: UInt64(vm.inactive_count),
                speculativeCount: UInt64(vm.speculative_count),
                purgeableCount: UInt64(vm.purgeable_count),
                wireCount: UInt64(vm.wire_count),
                compressorPageCount: UInt64(vm.compressor_page_count),
                externalPageCount: UInt64(vm.external_page_count),
                internalPageCount: UInt64(vm.internal_page_count)
            )
        )

        let swapInBytes = MemoryAccounting.pageBytes(UInt64(vm.swapins), pageSize: pageSize)
        let swapOutBytes = MemoryAccounting.pageBytes(UInt64(vm.swapouts), pageSize: pageSize)

        // Prefer the kernel's *current* pressure level. It is polled on every
        // sample, so it returns to Normal as soon as macOS does. The heuristic
        // is only a fallback when the sysctl is unavailable.
        let pressure = readKernelPressureLevel() ?? classifyPressure(
            totalBytes: totalBytes,
            availableBytes: accounting.availableBytes,
            compressedBytes: accounting.compressedBytes
        )

        return MemorySnapshot(
            timestamp: .now,
            accounting: accounting,
            swapTotalBytes: swap.total,
            swapUsedBytes: swap.used,
            swapFreeBytes: swap.free,
            swapInBytes: swapInBytes,
            swapOutBytes: swapOutBytes,
            pressure: pressure
        )
    }

    private func readVMStatistics() -> vm_statistics64 {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return vm_statistics64()
        }

        return statistics
    }

    private func readSwapUsage() -> (total: UInt64, used: UInt64, free: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size

        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else {
            return (0, 0, 0)
        }

        return (
            total: usage.xsu_total,
            used: usage.xsu_used,
            free: usage.xsu_avail
        )
    }

    /// MemWatch health classification. This intentionally does not claim
    /// to reproduce Apple's private Activity Monitor pressure algorithm.
    private func classifyPressure(
        totalBytes: UInt64,
        availableBytes: UInt64,
        compressedBytes: UInt64
    ) -> MemoryPressure {
        guard totalBytes > 0 else { return .normal }

        let availableRatio = ratio(availableBytes, totalBytes)
        let compressedRatio = ratio(compressedBytes, totalBytes)

        // These are MemWatch health thresholds, not Apple's private pressure
        // algorithm. The availability thresholds are calibrated for the new
        // `total - (App + Wired + Compressed)` headroom metric, which already
        // includes reclaimable file-backed memory.
        // Swap size is intentionally NOT used here: macOS keeps already
        // swapped pages on disk until they are touched, so the swap file can
        // stay large for hours after RAM pressure is gone. Using it made the
        // pressure state "stick" at Warning long after memory was freed.
        if availableRatio < 0.08 {
            return .critical
        }

        if availableRatio < 0.16 || compressedRatio > 0.30 {
            return .warning
        }

        return .normal
    }

    /// Reads `kern.memorystatus_vm_pressure_level`
    /// (1 = normal, 2 = warning, 4 = critical). This is the same live level
    /// the kernel uses for memory-pressure notifications.
    private func readKernelPressureLevel() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }

        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return nil
        }
    }

    private func ratio(_ numerator: UInt64, _ denominator: UInt64) -> Double {
        guard denominator > 0 else { return 0 }
        return min(max(Double(numerator) / Double(denominator), 0), 1)
    }
}
