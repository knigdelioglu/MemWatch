import Foundation

enum MemoryPressure: String {
    case normal
    case warning
    case critical
}

struct MemorySnapshot {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let swapUsedBytes: UInt64
    let pressure: MemoryPressure
}

extension MemorySnapshot {
    static let empty = MemorySnapshot(
        totalBytes: 0,
        usedBytes: 0,
        availableBytes: 0,
        swapUsedBytes: 0,
        pressure: .normal
    )
}
