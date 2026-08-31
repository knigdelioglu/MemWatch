import Foundation

enum HDRBrightnessDiagnosticReporter {
    private static let reportRelativePath = "docs/generated/brightness_hdr_diagnostic_report.md"

    static func writeMarkdownReport(summary: HDRBrightnessDiagnosticSummary) throws -> URL {
        try HiDPIReportPaths.write(buildMarkdown(summary: summary), to: reportRelativePath)
    }

    private static func buildMarkdown(summary: HDRBrightnessDiagnosticSummary) -> String {
        var lines: [String] = []
        lines.append("# HDR Brightness Diagnostic Report")
        lines.append("")
        lines.append("## Target display")
        lines.append("- Display name: \(summary.targetDisplayName)")
        lines.append("- Display ID: \(summary.displayID)")
        lines.append(String(format: "- Vendor ID: 0x%04X", summary.vendorID))
        lines.append(String(format: "- Product ID: 0x%04X", summary.productID))
        lines.append("- Serial: \(summary.serialNumber.map { String(format: "0x%08X", $0) } ?? "unreadable")")
        lines.append("- DDC display index: \(summary.displayIndex ?? "unavailable")")
        if let w = summary.activeModeLogicalWidth, let h = summary.activeModeLogicalHeight, let pw = summary.activeModePixelWidth, let ph = summary.activeModePixelHeight, let rr = summary.activeModeRefreshRate {
            lines.append(String(format: "- Active mode: %dx%d logical / %dx%d pixel @ %.2fHz", w, h, pw, ph, rr))
        } else {
            lines.append("- Active mode: unavailable")
        }
        lines.append("- Pixel encoding: \(summary.activeModePixelEncoding ?? "unavailable")")

        lines.append("")
        lines.append("## HDR/system_profiler status")
        lines.append("- HDR status: \(summary.hdrSystemProfilerStatus)")
        lines.append("- Color profile: \(summary.systemProfilerColorProfile ?? "unavailable")")
        if summary.systemProfilerEvidence.isEmpty {
            lines.append("- Evidence: none")
        } else {
            summary.systemProfilerEvidence.forEach { lines.append("- \($0)") }
        }

        lines.append("")
        lines.append("## DDC brightness read result")
        lines.append("- DDC brightness available: \(summary.ddcBrightnessAvailable ? "YES" : "NO")")
        lines.append("- Current brightness: \(summary.ddcCurrentBrightness.map(String.init) ?? "unavailable")")
        lines.append("- Max brightness: \(summary.ddcMaxBrightness)%")

        lines.append("")
        lines.append("## DDC brightness set/readback test")
        lines.append("- Set command success: \(summary.ddcSetSucceeded.map { $0 ? "YES" : "NO" } ?? "unknown")")
        lines.append("- Test brightness: \(summary.ddcTestBrightness.map(String.init) ?? "unavailable")")
        lines.append("- Readback brightness: \(summary.ddcReadbackBrightness.map(String.init) ?? "unavailable")")
        lines.append("- Readback changed: \(summary.ddcReadbackChanged.map { $0 ? "YES" : "NO" } ?? "unknown")")
        lines.append("- DDC works in HDR: \(summary.ddcWorksInHDRText)")

        lines.append("")
        lines.append("## NSScreen EDR values")
        lines.append("- maximumExtendedDynamicRangeColorComponentValue: \(formatDouble(summary.edrValues.maximumExtendedDynamicRangeColorComponentValue))")
        lines.append("- maximumPotentialExtendedDynamicRangeColorComponentValue: \(formatDouble(summary.edrValues.maximumPotentialExtendedDynamicRangeColorComponentValue))")
        lines.append("- maximumReferenceExtendedDynamicRangeColorComponentValue: \(formatDouble(summary.edrValues.maximumReferenceExtendedDynamicRangeColorComponentValue))")
        lines.append("- EDR available: \(summary.edrAvailableText)")

        lines.append("")
        lines.append("## Diagnosis")
        lines.append("- \(summary.diagnosis.displayText)")
        lines.append("- No HDR brightness boost was applied.")
        if summary.notes.isEmpty {
            lines.append("- Notes: none")
        } else {
            summary.notes.forEach { lines.append("- \($0)") }
        }

        lines.append("")
        lines.append("## Recommended next step")
        lines.append("- \(summary.recommendedPathText)")

        return lines.joined(separator: "\n") + "\n"
    }

    private static func formatDouble(_ value: Double?) -> String {
        guard let value else { return "unavailable" }
        return String(format: "%.3f", value)
    }
}
