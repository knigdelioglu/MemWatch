import Foundation

enum DDCBrightnessMaxDiagnosticReporter {
    private static let reportRelativePath = "docs/generated/brightness_max_diagnostic.md"

    static func writeMarkdownReport(summary: DDCBrightnessMaxDiagnosticSummary) throws -> URL {
        try HiDPIReportPaths.write(buildMarkdown(summary: summary), to: reportRelativePath)
    }

    private static func buildMarkdown(summary: DDCBrightnessMaxDiagnosticSummary) -> String {
        var lines: [String] = []
        lines.append("# Real Maximum Brightness Diagnostic")
        lines.append("")
        lines.append("## Target display")
        lines.append("- Display name: \(summary.targetDisplayName)")
        lines.append("- Display ID: \(summary.displayID)")
        lines.append(String(format: "- Vendor ID: 0x%04X", summary.vendorID))
        lines.append(String(format: "- Product ID: 0x%04X", summary.productID))
        lines.append("- Serial: \(summary.serialNumber.map { String(format: "0x%08X", $0) } ?? "unreadable")")
        lines.append("- DDC display index: \(summary.displayIndex ?? "unavailable")")

        lines.append("")
        lines.append("## DDC brightness current/max before")
        lines.append("- Current brightness: \(summary.ddcBrightnessAvailableText)")
        lines.append("- Max brightness: \(summary.ddcBrightnessMaxText)")
        lines.append("- Raw current before: \(summary.rawBrightnessBeforeText)")
        lines.append("- Requested raw max: \(summary.requestedRawMaxText)")
        lines.append("- Computed raw target: \(summary.computedRawTargetText)")

        lines.append("")
        lines.append("## Set brightness 100 result")
        lines.append("- Write status: \(summary.writeStatusText)")
        lines.append("- Write success: \(summary.setBrightness100ResultText)")

        lines.append("")
        lines.append("## DDC brightness readback after")
        lines.append("- Readback brightness: \(summary.brightnessReadbackAfterSet100Text)")
        lines.append("- Readback UI percent: \(summary.brightnessReadbackAfterSet100UIPercentText)")
        lines.append("- Raw after: \(summary.rawBrightnessAfterText)")
        lines.append("- Matched target: \(summary.matchedTargetText)")

        lines.append("")
        lines.append("## DDC contrast current/max")
        lines.append("- Current contrast: \(summary.ddcContrastCurrentText)")
        lines.append("- Max contrast: \(summary.ddcContrastMaxText)")

        lines.append("")
        lines.append("## Supported VCP codes")
        lines.append("- MCCS capabilities available: \(summary.mccsCapabilitiesAvailableText)")
        lines.append("- MCCS capabilities string: \(summary.mccsCapabilitiesString ?? "unavailable")")
        lines.append("- Supported VCP codes: \(summary.supportedVCPCodesText)")

        lines.append("")
        lines.append("## HDR/Eco/Eye Saver suspicion notes")
        if summary.notes.isEmpty {
            lines.append("- none")
        } else {
            summary.notes.forEach { lines.append("- \($0)") }
        }

        lines.append("")
        lines.append("## Diagnosis")
        if summary.diagnosis.isEmpty {
            lines.append("- unknown")
        } else {
            summary.diagnosis.forEach { lines.append("- \($0)") }
        }
        lines.append("- Possible brightness limiter: \(summary.possibleBrightnessLimiter.displayText)")

        lines.append("")
        lines.append("## Recommended manual checks")
        if summary.recommendedManualChecks.isEmpty {
            lines.append("- none")
        } else {
            summary.recommendedManualChecks.forEach { lines.append("- \($0)") }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
