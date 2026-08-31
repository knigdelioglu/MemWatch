import Foundation

enum EDIDDiagnosticReporter {
    private static let reportRelativePath = "docs/generated/private_activation/edid_diagnostic_report.md"

    static func writeMarkdownReport(summary: EDIDDiagnosticSummary) throws -> URL {
        try HiDPIReportPaths.write(buildMarkdown(summary: summary), to: reportRelativePath)
    }

    private static func buildMarkdown(summary: EDIDDiagnosticSummary) -> String {
        var lines: [String] = []
        lines.append("# EDID Diagnostic Report")
        lines.append("")
        lines.append("## Target display fingerprint")
        lines.append("- Display name: \(summary.targetDisplayName)")
        lines.append("- Display ID: \(summary.displayID)")
        lines.append(String(format: "- Vendor ID: 0x%04X", summary.targetVendorID))
        lines.append(String(format: "- Product ID: 0x%04X", summary.targetProductID))
        if let serial = summary.targetSerialNumber {
            lines.append(String(format: "- Serial: 0x%08X", serial))
        } else {
            lines.append("- Serial: unreadable")
        }

        lines.append("")
        lines.append("## EDID read status")
        lines.append("- Status: \(summary.status.displayText)")
        lines.append("- EDID available: \(summary.edidAvailable ? "YES" : "NO")")
        lines.append("- Raw byte count: \(summary.rawByteCount.map(String.init) ?? "unavailable")")

        lines.append("")
        lines.append("## EDID match confidence")
        lines.append("- Confidence: \(summary.matchConfidence.displayText)")

        lines.append("")
        lines.append("## EDID hash")
        lines.append("- SHA256: \(summary.sha256 ?? "unavailable")")

        lines.append("")
        lines.append("## Parsed EDID fields")
        lines.append("- Manufacturer: \(summary.manufacturerCode ?? "unavailable")")
        if let productCode = summary.productCode {
            lines.append(String(format: "- Product code: 0x%04X", productCode))
        } else {
            lines.append("- Product code: unavailable")
        }
        if let serial = summary.serialNumber {
            lines.append(String(format: "- EDID serial: 0x%08X", serial))
        } else {
            lines.append("- EDID serial: unavailable")
        }
        if let week = summary.manufactureWeek {
            lines.append("- Manufacture week: \(week)")
        } else {
            lines.append("- Manufacture week: unavailable")
        }
        if let year = summary.manufactureYear {
            lines.append("- Manufacture year: \(year)")
        } else {
            lines.append("- Manufacture year: unavailable")
        }
        lines.append("- Display name: \(summary.edidDisplayName ?? "unavailable")")
        lines.append("- Preferred timing: \(summary.preferredTimingSummary ?? "unavailable")")
        if let hSize = summary.horizontalSizeCm, let vSize = summary.verticalSizeCm {
            lines.append("- Size: \(hSize)cm x \(vSize)cm")
        } else {
            lines.append("- Size: unavailable")
        }

        lines.append("")
        lines.append("## Relation to CGDisplay vendor/product/serial")
        lines.append(String(format: "- CG vendor/product: 0x%04X / 0x%04X", summary.targetVendorID, summary.targetProductID))
        lines.append("- CG serial: \(summary.targetSerialNumber.map { String(format: "0x%08X", $0) } ?? "unreadable")")
        lines.append("- Match confidence: \(summary.matchConfidence.displayText)")

        lines.append("")
        lines.append("## Native resolution hint")
        lines.append("- \(summary.nativeResolutionHint ?? "unavailable")")

        lines.append("")
        lines.append("## Notes")
        if summary.notes.isEmpty {
            lines.append("- none")
        } else {
            summary.notes.forEach { lines.append("- \($0)") }
        }

        lines.append("")
        lines.append("## No EDID write/patch performed")
        lines.append("- Confirmed: read-only EDID collection only.")
        lines.append("- No EDID write, patch, virtual EDID, or /Library/Displays changes were performed.")

        return lines.joined(separator: "\n") + "\n"
    }
}
