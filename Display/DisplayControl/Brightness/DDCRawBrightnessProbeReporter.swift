import Foundation

enum DDCRawBrightnessProbeReporter {
    private static let reportRelativePath = "docs/generated/ddc_raw_brightness_probe.md"

    static func writeMarkdownReport(summary: DDCRawBrightnessProbeSummary) throws -> URL {
        try HiDPIReportPaths.write(buildMarkdown(summary: summary), to: reportRelativePath)
    }

    private static func buildMarkdown(summary: DDCRawBrightnessProbeSummary) -> String {
        var lines: [String] = []
        lines.append("# DDC Raw Brightness Probe")
        lines.append("")
        lines.append("## Target display")
        lines.append("- Display name: \(summary.targetDisplayName)")
        lines.append("- Display ID: \(summary.displayID)")
        lines.append(String(format: "- Vendor ID: 0x%04X", summary.vendorID))
        lines.append(String(format: "- Product ID: 0x%04X", summary.productID))
        lines.append("- Serial: \(summary.serialNumber.map { String(format: "0x%08X", $0) } ?? "unreadable")")
        lines.append("- DDC display index: \(summary.displayIndex ?? "unavailable")")

        lines.append("")
        lines.append("## raw current before")
        lines.append("- \(summary.rawCurrentBeforeText)")

        lines.append("")
        lines.append("## raw max")
        lines.append("- \(summary.rawMaxText)")

        lines.append("")
        lines.append("## requested raw max")
        lines.append("- \(summary.requestedRawMaxText)")

        lines.append("")
        lines.append("## write result")
        lines.append("- \(summary.writeResultText)")

        lines.append("")
        lines.append("## raw after")
        lines.append("- \(summary.rawAfterText)")

        lines.append("")
        lines.append("## normalized after percent")
        lines.append("- \(summary.normalizedAfterPercentText)")

        lines.append("")
        lines.append("## matched max")
        lines.append("- \(summary.matchedMaxText)")

        lines.append("")
        lines.append("## diagnosis")
        if summary.diagnosis.isEmpty {
            lines.append("- unknown")
        } else {
            summary.diagnosis.forEach { lines.append("- \($0)") }
        }

        lines.append("")
        lines.append("## notes")
        if summary.notes.isEmpty {
            lines.append("- none")
        } else {
            summary.notes.forEach { lines.append("- \($0)") }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
