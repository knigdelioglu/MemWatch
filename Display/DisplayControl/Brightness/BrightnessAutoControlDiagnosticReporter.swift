import Foundation

enum BrightnessAutoControlDiagnosticReporter {
    private static let reportRelativePath = "docs/generated/brightness_auto_control_diagnostic.md"

    static func writeMarkdownReport(summary: BrightnessAutoControlDiagnosticSummary) throws -> URL {
        try HiDPIReportPaths.write(buildMarkdown(summary: summary), to: reportRelativePath)
    }

    private static func buildMarkdown(summary: BrightnessAutoControlDiagnosticSummary) -> String {
        var lines: [String] = []
        lines.append("# Brightness Auto Control Diagnostic Report")
        lines.append("")
        lines.append("## ambient raw")
        lines.append("- \(formatDouble(summary.ambientSensorRawValue))")
        lines.append("")
        lines.append("## ambient normalized")
        lines.append("- \(formatDouble(summary.ambientNormalizedValue))")
        lines.append("")
        lines.append("## auto enabled")
        lines.append("- \(summary.isAutoBrightnessEnabled ? "YES" : "NO")")
        lines.append("")
        lines.append("## manual override")
        lines.append("- \(summary.isManualOverrideActive ? "YES" : "NO")")
        lines.append("")
        lines.append("## computed target")
        lines.append("- \(summary.computedAutoTargetBrightnessPercent.map { "\($0)%" } ?? "unavailable")")
        lines.append("")
        lines.append("## actual DDC before")
        lines.append("- \(summary.actualDDCBrightnessBefore.map { "\($0)%" } ?? "unavailable")")
        lines.append("")
        lines.append("## write attempted")
        lines.append("- \(summary.writeAttempted ? "YES" : "NO")")
        lines.append("")
        lines.append("## write value")
        lines.append("- \(summary.writeValue.map { "\($0)%" } ?? "unavailable")")
        lines.append("")
        lines.append("## write result")
        if let succeeded = summary.writeSucceeded {
            let result = succeeded ? "YES" : "NO"
            if let message = summary.writeMessage, !message.isEmpty {
                lines.append("- \(result) - \(message)")
            } else {
                lines.append("- \(result)")
            }
        } else {
            lines.append("- unknown")
        }
        lines.append("")
        lines.append("## actual DDC after")
        lines.append("- \(summary.actualDDCBrightnessAfter.map { "\($0)%" } ?? "unavailable")")
        lines.append("")
        lines.append("## last source")
        lines.append("- \(summary.lastBrightnessSource.rawValue)")
        lines.append("")
        lines.append("## suppression reason")
        lines.append("- \(summary.suppressionReason?.rawValue ?? "none")")
        lines.append("")
        lines.append("## mismatch status")
        lines.append("- \(summary.mismatchDetected ? "MISMATCH" : "OK")")

        return lines.joined(separator: "\n") + "\n"
    }

    private static func formatDouble(_ value: Double?) -> String {
        guard let value else { return "unavailable" }
        return String(format: "%.3f", value)
    }
}
