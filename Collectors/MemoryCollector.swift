import Foundation
import Darwin

final class MemoryCollector {
    func collect() -> MemorySnapshot {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()

        host_statistics64(host, HOST_VM_INFO64, &stats, &count)

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let available = free + UInt64(stats.purgeable_count) * pageSize
        let used = total > available ? total - available : 0

        return MemorySnapshot(
            totalBytes: total,
            usedBytes: used,
            availableBytes: available,
            swapUsedBytes: readSwapUsage(),
            pressure: .normal
        )
    }

    private func readSwapUsage() -> UInt64 {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &xsw, &size, nil, 0)
        return result == 0 ? xsw.xsu_used : 0
    }
}
