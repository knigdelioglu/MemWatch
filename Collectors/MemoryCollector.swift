import Darwin
import Foundation

final class MemoryCollector {
    func collect() -> MemorySnapshot {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let vm = readVMStatistics()
        let swap = readSwapUsage()
        let pageSize = UInt64(vm_kernel_page_size)

        let freeBytes = UInt64(vm.free_count) * pageSize
        let inactiveBytes = UInt64(vm.inactive_count) * pageSize
        let speculativeBytes = UInt64(vm.speculative_count) * pageSize
        let purgeableBytes = UInt64(vm.purgeable_count) * pageSize
        let wiredBytes = UInt64(vm.wire_count) * pageSize
        let compressedBytes = UInt64(vm.compressor_page_count) * pageSize
        let swapInBytes = UInt64(vm.swapins) * pageSize
        let swapOutBytes = UInt64(vm.swapouts) * pageSize

        let cachedBytes = inactiveBytes + speculativeBytes + purgeableBytes
        let availableBytes = min(totalBytes, freeBytes + cachedBytes)
        let usedBytes = totalBytes > availableBytes ? totalBytes - availableBytes : 0

        let pressure = classifyPressure(
            totalBytes: totalBytes,
            availableBytes: availableBytes,
            compressedBytes: compressedBytes,
            swapUsedBytes: swap.used
        )

        return MemorySnapshot(
            timestamp: .now,
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            availableBytes: availableBytes,
            freeBytes: freeBytes,
            cachedBytes: cachedBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
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
        compressedBytes: UInt64,
        swapUsedBytes: UInt64
    ) -> MemoryPressure {
        guard totalBytes > 0 else { return .normal }

        let availableRatio = Double(availableBytes) / Double(totalBytes)
        let compressedRatio = Double(compressedBytes) / Double(totalBytes)
        let swapRatio = Double(swapUsedBytes) / Double(totalBytes)

        if availableRatio < 0.08 || (availableRatio < 0.12 && swapRatio > 0.20) {
            return .critical
        }

        if availableRatio < 0.18 || compressedRatio > 0.30 || swapRatio > 0.10 {
            return .warning
        }

        return .normal
    }
}
