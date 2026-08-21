import Foundation

enum SwapHealthState: String, CaseIterable {
    case stable
    case idleSwap
    case readback
    case activeSwap
    case pressure
    case critical

    var displayName: String {
        switch self {
        case .stable: return "Stable"
        case .idleSwap: return "Idle Swap"
        case .readback: return "Swap Readback"
        case .activeSwap: return "Active Swap"
        case .pressure: return "Memory Pressure"
        case .critical: return "Critical"
        }
    }
}

struct SwapIntelligenceResult: Equatable {
    let state: SwapHealthState
    let summary: String
    let recentSwapInBytes: UInt64
    let recentSwapOutBytes: UInt64
    let activeSamples: Int
    let sampleCount: Int
}

struct SwapIntelligenceSample {
    let timestamp: Date
    let pressure: MemoryPressure
    let totalBytes: UInt64
    let availableBytes: UInt64
    let compressedBytes: UInt64
    let swapUsedBytes: UInt64
    let swapInDeltaBytes: UInt64
    let swapOutDeltaBytes: UInt64
}

struct SwapIntelligenceConfiguration {
    var historyLimit = 12
    var activityThresholdBytes: UInt64 = 1 * 1_024 * 1_024
    var heavySwapOutBytes: UInt64 = 64 * 1_024 * 1_024
    var criticalSwapOutBytes: UInt64 = 256 * 1_024 * 1_024
    var warningEnterSamples = 2
    var criticalEnterSamples = 2
    var recoverySamples = 3
}

final class SwapIntelligenceEngine {
    private let configuration: SwapIntelligenceConfiguration
    private(set) var history: [SwapIntelligenceSample] = []
    private(set) var result = SwapIntelligenceResult(
        state: .stable,
        summary: "Memory activity is stable",
        recentSwapInBytes: 0,
        recentSwapOutBytes: 0,
        activeSamples: 0,
        sampleCount: 0
    )

    private var pendingState: SwapHealthState?
    private var pendingCount = 0
    private var recoveryCount = 0

    init(configuration: SwapIntelligenceConfiguration = .init()) {
        self.configuration = configuration
    }

    @discardableResult
    func ingest(_ sample: SwapIntelligenceSample) -> SwapIntelligenceResult {
        history.append(sample)
        if history.count > configuration.historyLimit {
            history.removeFirst(history.count - configuration.historyLimit)
        }

        let candidate = classifyCurrentWindow()
        let stableState = applyHysteresis(candidate)
        let metrics = windowMetrics()

        result = SwapIntelligenceResult(
            state: stableState,
            summary: summary(for: stableState),
            recentSwapInBytes: metrics.swapIn,
            recentSwapOutBytes: metrics.swapOut,
            activeSamples: metrics.activeSamples,
            sampleCount: history.count
        )
        return result
    }

    func reset() {
        history.removeAll(keepingCapacity: true)
        pendingState = nil
        pendingCount = 0
        recoveryCount = 0
        result = SwapIntelligenceResult(
            state: .stable,
            summary: "Memory activity is stable",
            recentSwapInBytes: 0,
            recentSwapOutBytes: 0,
            activeSamples: 0,
            sampleCount: 0
        )
    }

    private func classifyCurrentWindow() -> SwapHealthState {
        guard let latest = history.last else { return .stable }
        let metrics = windowMetrics()
        let availableRatio = ratio(latest.availableBytes, latest.totalBytes)
        let compressedRatio = ratio(latest.compressedBytes, latest.totalBytes)

        if latest.pressure == .critical {
            return .critical
        }

        let recentWindow = Array(history.suffix(6))
        let recentSwapOut = recentWindow.reduce(UInt64(0)) { saturatingAdd($0, $1.swapOutDeltaBytes) }
        let recentActiveSamples = recentWindow.filter {
            $0.swapOutDeltaBytes >= configuration.activityThresholdBytes
        }.count

        if recentSwapOut >= configuration.criticalSwapOutBytes && availableRatio < 0.10 {
            return .critical
        }

        if latest.pressure == .warning {
            return .pressure
        }

        if recentActiveSamples >= 2 ||
            (recentSwapOut >= configuration.heavySwapOutBytes && availableRatio < 0.18) ||
            (recentSwapOut > 0 && compressedRatio > 0.30) {
            return .activeSwap
        }

        if latest.swapInDeltaBytes >= configuration.activityThresholdBytes &&
            latest.swapOutDeltaBytes < configuration.activityThresholdBytes {
            return .readback
        }

        if latest.swapUsedBytes > 0 && metrics.activeSamples == 0 {
            return .idleSwap
        }

        return .stable
    }

    private func applyHysteresis(_ candidate: SwapHealthState) -> SwapHealthState {
        let current = result.state

        if candidate == current {
            pendingState = nil
            pendingCount = 0
            recoveryCount = 0
            return current
        }

        if severity(candidate) < severity(current) {
            recoveryCount += 1
            guard recoveryCount >= configuration.recoverySamples else {
                return current
            }
            recoveryCount = 0
            pendingState = nil
            pendingCount = 0
            return candidate
        }

        recoveryCount = 0

        if candidate == .critical && current != .critical {
            if pendingState == candidate {
                pendingCount += 1
            } else {
                pendingState = candidate
                pendingCount = 1
            }

            if pendingCount >= configuration.criticalEnterSamples {
                pendingState = nil
                pendingCount = 0
                return candidate
            }
            return current
        }

        if severity(candidate) >= severity(.activeSwap) {
            if pendingState == candidate {
                pendingCount += 1
            } else {
                pendingState = candidate
                pendingCount = 1
            }

            if pendingCount >= configuration.warningEnterSamples {
                pendingState = nil
                pendingCount = 0
                return candidate
            }
            return current
        }

        pendingState = nil
        pendingCount = 0
        return candidate
    }

    private func windowMetrics() -> (swapIn: UInt64, swapOut: UInt64, activeSamples: Int) {
        var swapIn: UInt64 = 0
        var swapOut: UInt64 = 0
        var activeSamples = 0

        for sample in history {
            swapIn = saturatingAdd(swapIn, sample.swapInDeltaBytes)
            swapOut = saturatingAdd(swapOut, sample.swapOutDeltaBytes)
            if sample.swapInDeltaBytes >= configuration.activityThresholdBytes ||
                sample.swapOutDeltaBytes >= configuration.activityThresholdBytes {
                activeSamples += 1
            }
        }

        return (swapIn, swapOut, activeSamples)
    }

    private func summary(for state: SwapHealthState) -> String {
        switch state {
        case .stable:
            return "Memory activity is stable"
        case .idleSwap:
            return "Swap contains data, but there is no sustained disk activity"
        case .readback:
            return "Previously swapped data is being read back into memory"
        case .activeSwap:
            return "RAM pressure is causing sustained swap writes"
        case .pressure:
            return "macOS reports elevated memory pressure"
        case .critical:
            return "Memory pressure and swap activity are critical"
        }
    }

    private func severity(_ state: SwapHealthState) -> Int {
        switch state {
        case .stable: return 0
        case .idleSwap: return 1
        case .readback: return 1
        case .activeSwap: return 2
        case .pressure: return 3
        case .critical: return 4
        }
    }

    private func ratio(_ numerator: UInt64, _ denominator: UInt64) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : value
    }
}
