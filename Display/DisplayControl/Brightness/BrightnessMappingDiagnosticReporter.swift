import Foundation

enum BrightnessMappingDiagnosticReporter {
    private static let reportRelativePath = "docs/generated/brightness_mapping_diagnostic.md"

    static func writeMarkdownReport(summary: BrightnessMappingDiagnosticSummary) throws -> URL {
        try HiDPIReportPaths.write(buildMarkdown(summary: summary), to: reportRelativePath)
    }

    private static func buildMarkdown(summary: BrightnessMappingDiagnosticSummary) -> String {
        var lines: [String] = []
        lines.append("# Brightness Mapping Diagnostic Report")
        lines.append("")
        lines.append("## Target display")
        lines.append("- Display name: \(summary.targetDisplayName)")
        lines.append("- Display key: \(summary.displayKey ?? "unavailable")")
        lines.append("")
        lines.append("## ambient raw")
        lines.append("- \(formatDouble(summary.ambientSensorRawValue))")
        lines.append("")
        lines.append("## ambient normalized")
        lines.append("- \(formatDouble(summary.ambientNormalizedValue))")
        lines.append("")
        lines.append("## computed auto target")
        lines.append("- \(summary.computedAutoTargetBrightnessPercent.map { "\($0)%" } ?? "unavailable")")
        lines.append("")
        lines.append("## requested DDC brightness")
        lines.append("- \(summary.requestedDDCBrightnessPercent.map { "\($0)%" } ?? "unavailable")")
        lines.append("")
        lines.append("## actual DDC brightness")
        lines.append("- \(summary.actualDDCBrightnessPercent.map { "\($0)%" } ?? "unavailable")")
        lines.append("- Raw current before: \(summary.rawBefore.map(String.init) ?? "unavailable")")
        lines.append("- Raw max: \(summary.rawMax.map(String.init) ?? "unavailable")")
        lines.append("- Computed raw target: \(summary.computedRawTarget.map(String.init) ?? "unavailable")")
        lines.append("- Raw after: \(summary.rawAfter.map(String.init) ?? "unavailable")")
        lines.append("- Actual UI percent after: \(summary.actualUIPercentAfter.map { "\($0)%" } ?? "unavailable")")
        lines.append("- Matched target: \(summary.matchedTargetText)")
        lines.append("- Write status: \(summary.writeStatusText)")
        lines.append("")
        lines.append("## DDC write result")
        if let succeeded = summary.ddcWriteSucceeded {
            let result = succeeded ? "YES" : "NO"
            if let message = summary.ddcWriteMessage, !message.isEmpty {
                lines.append("- \(result) - \(message)")
            } else {
                lines.append("- \(result)")
            }
        } else {
            lines.append("- unknown")
        }
        lines.append("")
        lines.append("## DDC readback brightness")
        lines.append("- \(summary.lastDDCReadbackPercent.map { "\($0)%" } ?? "unavailable")")
        lines.append("- Readback status: \(summary.readbackAvailable ? "OK" : "Failed")")
        lines.append("")
        lines.append("## UI slider value")
        lines.append("- \(summary.uiSliderValue)%")
        lines.append("")
        lines.append("## source of last update")
        lines.append("- \(summary.lastBrightnessSource.rawValue)")
        lines.append("")
        lines.append("## mismatch detected")
        lines.append("- \(summary.mismatchDetected ? "YES" : "NO")")
        lines.append("")
        lines.append("## mode flags")
        lines.append("- Auto brightness enabled: \(summary.isAutoBrightnessEnabled ? "YES" : "NO")")
        lines.append("- Manual override active: \(summary.isManualOverrideActive ? "YES" : "NO")")

        return lines.joined(separator: "\n") + "\n"
    }

    private static func formatDouble(_ value: Double?) -> String {
        guard let value else { return "unavailable" }
        return String(format: "%.3f", value)
    }
}
