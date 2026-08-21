import Foundation

enum ThermalHealthState: String, Sendable {
    case nominal
    case fair
    case serious
    case critical

    var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        }
    }

    var severity: Double {
        switch self {
        case .nominal: return 0
        case .fair: return 0.33
        case .serious: return 0.66
        case .critical: return 1
        }
    }
}

struct ProcessMemorySnapshot: Identifiable, Equatable, Sendable {
    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let residentBytes: UInt64

    var id: Int32 { pid }
}

struct SystemDiagnosticsSnapshot: Equatable, Sendable {
    let timestamp: Date
    let cpuUsagePercent: Double?
    let thermalState: ThermalHealthState
    let lowPowerModeEnabled: Bool
    let topProcesses: [ProcessMemorySnapshot]

    static let empty = SystemDiagnosticsSnapshot(
        timestamp: .distantPast,
        cpuUsagePercent: nil,
        thermalState: .nominal,
        lowPowerModeEnabled: false,
        topProcesses: []
    )
}

struct SystemHistoryPoint: Identifiable, Equatable, Sendable {
    let timestamp: Date
    let cpuUsagePercent: Double
    let memoryUsagePercent: Double
    let thermalSeverity: Double

    var id: Date { timestamp }
}

enum LaunchAtLoginState: String, Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case needsSetup
    case unavailable

    var displayName: String {
        switch self {
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        case .requiresApproval: return "Needs approval"
        case .needsSetup: return "Needs setup"
        case .unavailable: return "Unavailable"
        }
    }
}
