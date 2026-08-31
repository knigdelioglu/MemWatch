import AppKit
import CoreGraphics
import Foundation

public struct HiDPISnapshotModeDTO: Codable {
    public let logicalWidth: Int
    public let logicalHeight: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isHiDPI: Bool
    public let isStrongHiDPI: Bool
    public let isPerfectQHDHiDPI: Bool
    public let pixelEncoding: String
    public let ioFlags: UInt32
    public let candidateReason: String
}

public struct HiDPISnapshotDisplayDTO: Codable {
    public let displayID: UInt32
    public let displayName: String
    public let vendorID: UInt32
    public let productID: UInt32
    public let serial: UInt32?
    public let isBuiltIn: Bool
    public let isOnline: Bool
    public let isActive: Bool
    public let currentMode: HiDPISnapshotModeDTO?
    public let defaultModeCount: Int
    public let duplicateLowResolutionModeCount: Int
    public let hiDPIModeCount: Int
    public let has5120x2880BackingMode: Bool
    public let has2560x1440Logical5120x2880PixelMode: Bool
    public let has100HzHiDPICandidate: Bool
}

public struct HiDPISystemSnapshotDTO: Codable {
    public let capturedAt: String
    public let targetVendorID: UInt32
    public let targetProductID: UInt32
    public let targetDisplay: HiDPISnapshotDisplayDTO?
    public let activeDisplays: [HiDPISnapshotDisplayDTO]
    public let defaultModes: [HiDPISnapshotModeDTO]
    public let duplicateLowResolutionModes: [HiDPISnapshotModeDTO]
}

public final class HiDPISystemSnapshotReporter {
    private static func timestampString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    public static func writeSnapshot(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let snapshot = collectSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(snapshot)
        try jsonData.write(to: directory.appendingPathComponent("cg_mode_pool_summary.json"), options: [.atomic])

        try buildActiveDisplaysMarkdown(snapshot).write(
            to: directory.appendingPathComponent("cg_active_displays.md"),
            atomically: true,
            encoding: .utf8
        )
        try buildModePoolMarkdown(title: "CoreGraphics Mode Pool (default)", modes: snapshot.defaultModes).write(
            to: directory.appendingPathComponent("cg_mode_pool_default.md"),
            atomically: true,
            encoding: .utf8
        )
        try buildModePoolMarkdown(title: "CoreGraphics Mode Pool (duplicateLowResolutionModes=true)", modes: snapshot.duplicateLowResolutionModes).write(
            to: directory.appendingPathComponent("cg_mode_pool_duplicate_low_res.md"),
            atomically: true,
            encoding: .utf8
        )
        try buildSummaryMarkdown(snapshot).write(
            to: directory.appendingPathComponent("hidpi_summary.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    public static func collectSnapshot() -> HiDPISystemSnapshotDTO {
        let activeDisplayIDs = copyActiveDisplayIDs()
        let target = (try? HiDPITargetDisplayResolver.resolveSamsungS60UD()) ?? (try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics())
        let defaultModes = target.map {
            NativeDisplayModeReader.getAvailableModes(for: $0.displayID, includeDuplicateLowResolutionModes: false)
        } ?? []
        let duplicateModes = target.map {
            NativeDisplayModeReader.getAvailableModes(for: $0.displayID, includeDuplicateLowResolutionModes: true)
        } ?? []

        let activeDisplays = activeDisplayIDs.map { displayDTO(for: $0) }
        let targetDTO = target.map {
            displayDTO(
                for: $0.displayID,
                defaultModes: defaultModes,
                duplicateModes: duplicateModes,
                displayNameOverride: $0.displayName
            )
        }

        return HiDPISystemSnapshotDTO(
            capturedAt: timestampString(),
            targetVendorID: HiDPIOverrideReferenceStore.targetVendorID,
            targetProductID: HiDPIOverrideReferenceStore.targetProductID,
            targetDisplay: targetDTO,
            activeDisplays: activeDisplays,
            defaultModes: defaultModes.map(modeDTO),
            duplicateLowResolutionModes: duplicateModes.map(modeDTO)
        )
    }

    private static func copyActiveDisplayIDs() -> [CGDirectDisplayID] {
        let maxDisplays: UInt32 = 32
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(maxDisplays, &displays, &count) == .success else {
            return []
        }
        return Array(displays.prefix(Int(count)))
    }

    private static func displayDTO(
        for displayID: CGDirectDisplayID,
        defaultModes: [PhysicalDisplayMode]? = nil,
        duplicateModes: [PhysicalDisplayMode]? = nil,
        displayNameOverride: String? = nil
    ) -> HiDPISnapshotDisplayDTO {
        let defaultModes = defaultModes ?? NativeDisplayModeReader.getAvailableModes(for: displayID, includeDuplicateLowResolutionModes: false)
        let duplicateModes = duplicateModes ?? NativeDisplayModeReader.getAvailableModes(for: displayID, includeDuplicateLowResolutionModes: true)
        let currentMode = CGDisplayCopyDisplayMode(displayID).map(modeDTO)
        let serialValue = CGDisplaySerialNumber(displayID)
        let serial = serialValue == 0 ? nil : serialValue

        return HiDPISnapshotDisplayDTO(
            displayID: displayID,
            displayName: displayNameOverride ?? displayName(for: displayID),
            vendorID: CGDisplayVendorNumber(displayID),
            productID: CGDisplayModelNumber(displayID),
            serial: serial,
            isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
            isOnline: CGDisplayIsOnline(displayID) != 0,
            isActive: CGDisplayIsActive(displayID) != 0,
            currentMode: currentMode,
            defaultModeCount: defaultModes.count,
            duplicateLowResolutionModeCount: duplicateModes.count,
            hiDPIModeCount: duplicateModes.filter(\.isHiDPI).count,
            has5120x2880BackingMode: duplicateModes.contains { $0.pixelWidth == 5120 && $0.pixelHeight == 2880 },
            has2560x1440Logical5120x2880PixelMode: duplicateModes.contains { $0.width == 2560 && $0.height == 1440 && $0.pixelWidth == 5120 && $0.pixelHeight == 2880 },
            has100HzHiDPICandidate: duplicateModes.contains { $0.isHiDPI && abs($0.refreshRate - 100.0) < 0.1 }
        )
    }

    private static func displayName(for displayID: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("ESDDisplayDeviceID")
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        }
        return screen?.localizedName ?? "Unknown Display"
    }

    private static func modeDTO(_ mode: CGDisplayMode) -> HiDPISnapshotModeDTO {
        let logicalWidth = mode.width
        let logicalHeight = mode.height
        let pixelWidth = mode.pixelWidth
        let pixelHeight = mode.pixelHeight
        let isHiDPI = pixelWidth > logicalWidth || pixelHeight > logicalHeight
        let isStrongHiDPI = pixelWidth == logicalWidth * 2 && pixelHeight == logicalHeight * 2
        let physicalMode = PhysicalDisplayMode(
            id: "\(logicalWidth)x\(logicalHeight)@\(Int(mode.refreshRate))_\(pixelWidth)x\(pixelHeight)_\(isHiDPI ? "hidpi" : "normal")",
            width: logicalWidth,
            height: logicalHeight,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: mode.refreshRate,
            isHiDPI: isHiDPI,
            isStrongHiDPI: isStrongHiDPI,
            isPerfectQHDHiDPI: logicalWidth == 2560 && logicalHeight == 1440 && pixelWidth == 5120 && pixelHeight == 2880,
            pixelEncoding: (mode.pixelEncoding as String?) ?? "Unknown",
            ioFlags: mode.ioFlags,
            modeSource: "current",
            cgMode: mode
        )
        return modeDTO(physicalMode)
    }

    private static func modeDTO(_ mode: PhysicalDisplayMode) -> HiDPISnapshotModeDTO {
        HiDPISnapshotModeDTO(
            logicalWidth: mode.width,
            logicalHeight: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            isHiDPI: mode.isHiDPI,
            isStrongHiDPI: mode.isStrongHiDPI,
            isPerfectQHDHiDPI: mode.isPerfectQHDHiDPI,
            pixelEncoding: mode.pixelEncoding,
            ioFlags: mode.ioFlags,
            candidateReason: NativeDisplayModeReader.candidateReason(for: mode)
        )
    }

    private static func buildActiveDisplaysMarkdown(_ snapshot: HiDPISystemSnapshotDTO) -> String {
        var lines: [String] = ["# Active CoreGraphics Displays", ""]
        if snapshot.activeDisplays.isEmpty {
            lines.append("- No active displays found.")
            return lines.joined(separator: "\n") + "\n"
        }

        for display in snapshot.activeDisplays {
            lines.append("## \(display.displayName)")
            appendDisplay(display, to: &lines)
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func buildSummaryMarkdown(_ snapshot: HiDPISystemSnapshotDTO) -> String {
        var lines: [String] = ["# HiDPI System Snapshot Summary", ""]
        lines.append("- Captured at: \(snapshot.capturedAt)")
        lines.append(String(format: "- Target Vendor ID: 0x%04X", snapshot.targetVendorID))
        lines.append(String(format: "- Target Product ID: 0x%04X", snapshot.targetProductID))
        lines.append("")

        guard let target = snapshot.targetDisplay else {
            lines.append("## Target Samsung Display")
            lines.append("- Not found in the active CoreGraphics display list.")
            return lines.joined(separator: "\n") + "\n"
        }

        lines.append("## Target Samsung Display")
        appendDisplay(target, to: &lines)
        lines.append("")
        lines.append("## Requested Checks")
        lines.append("- 5120x2880 pixel/backing mode present: \(target.has5120x2880BackingMode)")
        lines.append("- 2560x1440 logical / 5120x2880 pixel mode present: \(target.has2560x1440Logical5120x2880PixelMode)")
        lines.append("- 100 Hz HiDPI candidate present: \(target.has100HzHiDPICandidate)")
        lines.append("- Default mode count: \(target.defaultModeCount)")
        lines.append("- duplicateLowResolutionModes=true mode count: \(target.duplicateLowResolutionModeCount)")
        lines.append("- HiDPI mode count: \(target.hiDPIModeCount)")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendDisplay(_ display: HiDPISnapshotDisplayDTO, to lines: inout [String]) {
        lines.append("- DisplayID: \(display.displayID)")
        lines.append(String(format: "- Vendor ID: 0x%04X (%u)", display.vendorID, display.vendorID))
        lines.append(String(format: "- Product ID: 0x%04X (%u)", display.productID, display.productID))
        if let serial = display.serial {
            lines.append(String(format: "- Serial: 0x%08X (%u)", serial, serial))
        } else {
            lines.append("- Serial: unreadable")
        }
        lines.append("- Built-in: \(display.isBuiltIn)")
        lines.append("- Online: \(display.isOnline)")
        lines.append("- Active: \(display.isActive)")
        if let currentMode = display.currentMode {
            lines.append(String(format: "- Current mode: %dx%d logical / %dx%d pixel @ %.2fHz | HiDPI:%@",
                                currentMode.logicalWidth,
                                currentMode.logicalHeight,
                                currentMode.pixelWidth,
                                currentMode.pixelHeight,
                                currentMode.refreshRate,
                                currentMode.isHiDPI ? "true" : "false"))
        } else {
            lines.append("- Current mode: unavailable")
        }
        lines.append("- Default mode count: \(display.defaultModeCount)")
        lines.append("- duplicateLowResolutionModes=true mode count: \(display.duplicateLowResolutionModeCount)")
        lines.append("- HiDPI mode count: \(display.hiDPIModeCount)")
        lines.append("- 5120x2880 pixel/backing mode present: \(display.has5120x2880BackingMode)")
        lines.append("- 2560x1440 logical / 5120x2880 pixel mode present: \(display.has2560x1440Logical5120x2880PixelMode)")
        lines.append("- 100 Hz HiDPI candidate present: \(display.has100HzHiDPICandidate)")
    }

    private static func buildModePoolMarkdown(title: String, modes: [HiDPISnapshotModeDTO]) -> String {
        var lines: [String] = ["# \(title)", ""]
        lines.append("| # | logical | pixel/backing | refresh | encoding | ioFlags | HiDPI | strong HiDPI | candidate reason |")
        lines.append("|---:|---|---|---:|---|---:|---|---|---|")
        for (index, mode) in modes.enumerated() {
            lines.append(String(
                format: "| %d | %dx%d | %dx%d | %.2f | %@ | 0x%08X | %@ | %@ | %@ |",
                index + 1,
                mode.logicalWidth,
                mode.logicalHeight,
                mode.pixelWidth,
                mode.pixelHeight,
                mode.refreshRate,
                mode.pixelEncoding,
                mode.ioFlags,
                mode.isHiDPI ? "true" : "false",
                mode.isStrongHiDPI ? "true" : "false",
                mode.candidateReason
            ))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
