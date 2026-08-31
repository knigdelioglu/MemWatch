import AppKit
import CoreGraphics
import Foundation

public struct HiDPIModePoolDiagnosticSummary {
    public let targetDisplay: TargetDisplayInfo?
    public let bundledReferenceExists: Bool
    public let systemOverrideExists: Bool
    public let applicationSupportBackupExists: Bool
    public let bundledReferenceSHA256: String?
    public let systemOverrideSHA256: String?
    public let applicationSupportBackupSHA256: String?
    public let systemMatchesBundledReference: Bool
    public let applicationSupportMatchesBundledReference: Bool
    public let scaleResolutionCount: Int
    public let hasPerfectQHDNormalRecord: Bool
    public let hasPerfectQHDHiDPIRecord: Bool
    public let defaultModes: [PhysicalDisplayMode]
    public let duplicateModes: [PhysicalDisplayMode]
}

public final class HiDPIModePoolDiagnostic {
    public static func reportURL() -> URL {
        HiDPIReportPaths.reportURL("docs/generated/hidpi_mode_pool_dump_after_betterdisplay_removal.md")
    }

    public static func collectSummary() -> HiDPIModePoolDiagnosticSummary {
        let target = (try? HiDPITargetDisplayResolver.resolveSamsungS60UD()) ?? (try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics())

        let referenceRecord = try? HiDPIOverrideReferenceStore.bundledReferenceRecord()
        let systemRecord = try? HiDPIOverrideReferenceStore.systemOverrideRecord()
        let backupRecord = try? HiDPIOverrideReferenceStore.applicationSupportBackupRecord()

        let defaultModes = target.map { NativeDisplayModeReader.getAvailableModes(for: $0.displayID, includeDuplicateLowResolutionModes: false) } ?? []
        let duplicateModes = target.map { NativeDisplayModeReader.getAvailableModes(for: $0.displayID, includeDuplicateLowResolutionModes: true) } ?? []

        return HiDPIModePoolDiagnosticSummary(
            targetDisplay: target,
            bundledReferenceExists: HiDPIOverrideReferenceStore.bundledReferenceExists,
            systemOverrideExists: HiDPIOverrideReferenceStore.systemOverrideExists,
            applicationSupportBackupExists: HiDPIOverrideReferenceStore.applicationSupportBackupExists,
            bundledReferenceSHA256: referenceRecord?.sha256,
            systemOverrideSHA256: systemRecord?.sha256,
            applicationSupportBackupSHA256: backupRecord?.sha256,
            systemMatchesBundledReference: HiDPIOverrideReferenceStore.systemMatchesBundledReference(),
            applicationSupportMatchesBundledReference: HiDPIOverrideReferenceStore.applicationSupportBackupMatchesBundledReference(),
            scaleResolutionCount: referenceRecord?.scaleResolutions.count ?? 0,
            hasPerfectQHDNormalRecord: referenceRecord?.hasPerfectQHDNormalRecord ?? false,
            hasPerfectQHDHiDPIRecord: referenceRecord?.hasPerfectQHDHiDPIRecord ?? false,
            defaultModes: defaultModes,
            duplicateModes: duplicateModes
        )
    }

    public static func buildMarkdownReport() -> String {
        let summary = collectSummary()
        let target = summary.targetDisplay
        let defaultModes = summary.defaultModes
        let duplicateModes = summary.duplicateModes
        let compareDefault = defaultModes.count
        let compareDuplicate = duplicateModes.count
        let compareHiDPI = duplicateModes.filter { $0.isHiDPI }.count
        let strictPerfectDefaultModes = defaultModes.filter(NativeDisplayModeReader.isPerfectQHDHiDPIMode)
        let strictPerfectModes = duplicateModes.filter {
            $0.width == 2560 && $0.height == 1440 &&
            $0.pixelWidth == 5120 && $0.pixelHeight == 2880 &&
            abs($0.refreshRate - 100.0) < 0.1 &&
            $0.isStrongHiDPI
        }
        let loosePerfectModes = duplicateModes.filter {
            $0.width == 2560 && $0.height == 1440 &&
            $0.pixelWidth == 5120 && $0.pixelHeight == 2880 &&
            $0.isStrongHiDPI
        }
        let pixel5120Modes = duplicateModes.filter { $0.pixelWidth == 5120 && $0.pixelHeight == 2880 }
        let logical2560Modes = duplicateModes.filter { $0.width == 2560 && $0.height == 1440 }
        let strong169Modes = duplicateModes.filter { $0.isStrongHiDPI && $0.width * 9 == $0.height * 16 }
        let hidpi100Modes = duplicateModes.filter { $0.isHiDPI && abs($0.refreshRate - 100.0) < 0.1 }
        let currentMode = target.flatMap { CGDisplayCopyDisplayMode($0.displayID) }
        let currentModeIsPerfectQHD = currentMode.map {
            $0.width == HiDPIOverrideReferenceStore.targetLogicalWidth &&
                $0.height == HiDPIOverrideReferenceStore.targetLogicalHeight &&
                $0.pixelWidth == HiDPIOverrideReferenceStore.targetBackingWidth &&
                $0.pixelHeight == HiDPIOverrideReferenceStore.targetBackingHeight &&
                abs($0.refreshRate - HiDPIOverrideReferenceStore.targetRefreshRate) < 0.1
        } ?? false
        let systemProfilerEvidence = systemProfilerPerfectQHDEvidence()
        let windowServerEvidence = windowServerPerfectQHDEvidence()

        var lines: [String] = []
        lines.append("# HiDPI Mode Pool Diagnostic")
        lines.append("")
        lines.append("## Current status")
        lines.append("- Target display: \(target.map { $0.displayName } ?? "unavailable")")
        if let target {
            lines.append("- VendorID: 0x\(String(target.vendorID, radix: 16).uppercased())")
            lines.append("- ProductID: 0x\(String(target.productID, radix: 16).uppercased())")
            if let serial = target.serialNumber {
                lines.append(String(format: "- Serial: 0x%08X", serial))
            } else {
                lines.append("- Serial: unreadable")
            }
            lines.append("- Built-in: \(target.isBuiltin)")
            lines.append("- Online: \(target.isOnline)")
            lines.append("- Active: \(target.isActive)")
        }
        lines.append("- Bundled reference exists: \(summary.bundledReferenceExists)")
        lines.append("- System override exists: \(summary.systemOverrideExists)")
        lines.append("- Application Support backup exists: \(summary.applicationSupportBackupExists)")
        lines.append("- System matches bundled reference: \(summary.systemMatchesBundledReference)")
        lines.append("- Application Support matches bundled reference: \(summary.applicationSupportMatchesBundledReference)")
        lines.append("- Reference SHA256: \(summary.bundledReferenceSHA256 ?? "n/a")")
        lines.append("- System SHA256: \(summary.systemOverrideSHA256 ?? "n/a")")
        lines.append("- Backup SHA256: \(summary.applicationSupportBackupSHA256 ?? "n/a")")
        lines.append("- scale-resolutions count: \(summary.scaleResolutionCount)")
        lines.append("- 5120x2880 normal record: \(summary.hasPerfectQHDNormalRecord)")
        lines.append("- 5120x2880 HiDPI/flexible record: \(summary.hasPerfectQHDHiDPIRecord)")

        lines.append("")
        lines.append("## Mode list comparison")
        lines.append("- Default mode count: \(compareDefault)")
        lines.append("- duplicateLowResolutionModes=true mode count: \(compareDuplicate)")
        lines.append("- HiDPI count in duplicate list: \(compareHiDPI)")
        lines.append("- Perfect QHD in default list: \(!strictPerfectDefaultModes.isEmpty)")
        lines.append("- Perfect QHD in duplicateLowResolutionModes=true list: \(!strictPerfectModes.isEmpty)")
        if let currentMode {
            lines.append(String(format: "- Active mode: %dx%d logical / %dx%d pixel @ %.2fHz | Perfect QHD: %@",
                                currentMode.width,
                                currentMode.height,
                                currentMode.pixelWidth,
                                currentMode.pixelHeight,
                                currentMode.refreshRate,
                                currentModeIsPerfectQHD ? "true" : "false"))
        } else {
            lines.append("- Active mode: unavailable")
        }
        lines.append("- system_profiler 5120x2880 / UI Looks like 2560x1440 evidence: \(systemProfilerEvidence.matches)")
        lines.append("- WindowServer CurrentInfo Scale=2 Wide=2560 High=1440 Hz=100 evidence: \(windowServerEvidence.matches)")
        lines.append("- Strict Perfect QHD count: \(strictPerfectModes.count)")
        lines.append("- Loose Perfect QHD count: \(loosePerfectModes.count)")
        lines.append("- 5120x2880 pixel/backing candidates: \(pixel5120Modes.count)")
        lines.append("- 2560x1440 logical candidates: \(logical2560Modes.count)")
        lines.append("- Strong HiDPI 16:9 candidates: \(strong169Modes.count)")
        lines.append("- 100 Hz HiDPI candidates: \(hidpi100Modes.count)")

        lines.append("")
        lines.append("## Candidate summaries")
        func appendModeList(_ title: String, _ modes: [PhysicalDisplayMode]) {
            lines.append("### \(title)")
            if modes.isEmpty {
                lines.append("- none")
                lines.append("")
                return
            }
            for mode in modes {
                lines.append(String(format: "- %dx%d -> %dx%d @ %.2fHz | HiDPI:%@ | strong:%@ | aspect:%@",
                                    mode.width, mode.height, mode.pixelWidth, mode.pixelHeight, mode.refreshRate,
                                    mode.isHiDPI ? "true" : "false",
                                    mode.isStrongHiDPI ? "true" : "false",
                                    NativeDisplayModeReader.aspectRatioString(width: mode.width, height: mode.height)))
            }
            lines.append("")
        }
        appendModeList("Strict Perfect QHD", strictPerfectModes)
        appendModeList("Strict Perfect QHD in default list", strictPerfectDefaultModes)
        appendModeList("Loose Perfect QHD", loosePerfectModes)
        appendModeList("5120x2880 pixel/backing", pixel5120Modes)
        appendModeList("2560x1440 logical", logical2560Modes)
        appendModeList("Strong HiDPI 16:9", strong169Modes)
        appendModeList("100 Hz HiDPI", hidpi100Modes)

        lines.append("## Full mode dump (duplicateLowResolutionModes=true)")
        lines.append("")
        lines.append("| # | logical | pixel | refresh | encoding | ioFlags | isHiDPI | strongHiDPI | aspect | candidate reason |")
        lines.append("|---:|---|---|---:|---|---:|---|---|---|---|")
        for (index, mode) in duplicateModes.enumerated() {
            lines.append(String(
                format: "| %d | %dx%d | %dx%d | %.2f | %@ | 0x%08X | %@ | %@ | %@ | %@ |",
                index + 1,
                mode.width,
                mode.height,
                mode.pixelWidth,
                mode.pixelHeight,
                mode.refreshRate,
                mode.pixelEncoding,
                mode.ioFlags,
                mode.isHiDPI ? "true" : "false",
                mode.isStrongHiDPI ? "true" : "false",
                NativeDisplayModeReader.aspectRatioString(width: mode.width, height: mode.height),
                NativeDisplayModeReader.candidateReason(for: mode)
            ))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func systemProfilerPerfectQHDEvidence() -> (matches: Bool, snippet: String) {
        let output = shellOutput("/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null")
        let matches = output.contains("Resolution: 5120 x 2880") &&
            output.contains("UI Looks like: 2560 x 1440 @ 100.00Hz")
        return (matches, output)
    }

    private static func windowServerPerfectQHDEvidence() -> (matches: Bool, snippet: String) {
        let command = """
        setopt NULL_GLOB
        for f in /Library/Preferences/com.apple.windowserver.displays.plist /Library/Preferences/com.apple.windowserver.plist /Library/Preferences/ByHost/com.apple.windowserver*.plist "$HOME"/Library/Preferences/com.apple.windowserver*.plist "$HOME"/Library/Preferences/ByHost/com.apple.windowserver*.plist; do
          [ -e "$f" ] || continue
          echo "### $f"
          /usr/bin/plutil -p "$f" 2>/dev/null
        done
        """
        let output = shellOutput(command)
        let matches = output.contains("\"Scale\" => 2") &&
            output.contains("\"Wide\" => 2560") &&
            output.contains("\"High\" => 1440") &&
            (output.contains("\"Hz\" => 100") || output.contains("\"RefreshRate\" => 100"))
        return (matches, output)
    }

    private static func shellOutput(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "command failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    public static func writeMarkdownReport() throws -> URL {
        let url = reportURL()
        let report = buildMarkdownReport()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
