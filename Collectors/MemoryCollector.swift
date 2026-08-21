import Darwin
import Foundation

final class MemoryCollector {
    func collect() -> MemorySnapshot {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let pressure = readMemoryPressure()
        let swapUsedBytes = readSwapUsage()

        guard let (stats, pageSize) = readVMStatistics() else {
            return MemorySnapshot(
                timestamp: Date(),
                totalBytes: totalBytes,
                usedBytes: 0,
                availableBytes: totalBytes,
                appMemoryBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                freeBytes: totalBytes,
                swapUsedBytes: swapUsedBytes,
                swapInBytes: 0,
                swapOutBytes: 0,
                swapInRateBytesPerSecond: 0,
                swapOutRateBytesPerSecond: 0,
                pressure: pressure
            )
        }

        let appPages = subtractClamped(
            UInt64(stats.internal_page_count),
            UInt64(stats.purgeable_count)
        )
        let freePages = subtractClamped(
            UInt64(stats.free_count),
            UInt64(stats.speculative_count)
        )

        let appMemoryBytes = appPages * pageSize
        let wiredBytes = UInt64(stats.wire_count) * pageSize
        let compressedBytes = UInt64(stats.compressor_page_count) * pageSize
        let cachedBytes = (
            UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)
        ) * pageSize
        let freeBytes = freePages * pageSize

        // Activity Monitor's useful high-level definition is approximately
        // app memory + wired memory + physical pages occupied by the compressor.
        // Clamp to physical RAM because VM accounting can contain small transient
        // overlaps while counters are sampled.
        let measuredUsedBytes = appMemoryBytes + wiredBytes + compressedBytes
        let usedBytes = min(measuredUsedBytes, totalBytes)
        let availableBytes = totalBytes - usedBytes

        return MemorySnapshot(
            timestamp: Date(),
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            availableBytes: availableBytes,
            appMemoryBytes: appMemoryBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedBytes: cachedBytes,
            freeBytes: freeBytes,
            swapUsedBytes: swapUsedBytes,
            swapInBytes: stats.swapins * pageSize,
            swapOutBytes: stats.swapouts * pageSize,
            swapInRateBytesPerSecond: 0,
            swapOutRateBytesPerSecond: 0,
            pressure: pressure
        )
    }

    private func readVMStatistics() -> (vm_statistics64, UInt64)? {
        let host = mach_host_self()
        defer {
            mach_port_deallocate(mach_task_self_, host)
        }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { reboundPointer in
                host_statistics64(
                    host,
                    HOST_VM_INFO64,
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else {
            return nil
        }

        return (stats, UInt64(pageSize))
    }

    private func readSwapUsage() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size

        let result = sysctlbyname(
            "vm.swapusage",
            &usage,
            &size,
            nil,
            0
        )

        return result == 0 ? usage.xsu_used : 0
    }

    private func readMemoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size

        let result = sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &level,
            &size,
            nil,
            0
        )

        guard result == 0 else {
            return .normal
        }

        switch level {
        case 1, 2:
            return .warning
        case 3...:
            return .critical
        default:
            return .normal
        }
    }

    private func subtractClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs > rhs ? lhs - rhs : 0
    }
}
