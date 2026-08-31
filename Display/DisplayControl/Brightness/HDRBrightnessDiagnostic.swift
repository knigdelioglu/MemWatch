import AppKit
import CoreGraphics
import Foundation

actor HDRBrightnessDiagnostic {
    private let ddcReader = HDRBrightnessDDCReader()

    func run(preferredDisplayKey: String? = nil) async -> HDRBrightnessDiagnosticSummary {
        guard let target = try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics() else {
            return makeUnknownSummary(
                targetDisplayName: "unavailable",
                displayID: 0,
                displayIndex: nil,
                vendorID: 0,
                productID: 0,
                serialNumber: nil,
                notes: ["Target Samsung display not found"]
            )
        }

        let activeMode = CGDisplayCopyDisplayMode(target.displayID)
        let profiler = runSystemProfiler()
        let edrValues = await MainActor.run { Self.screenEDRValues(for: target.displayID) }
        let ddcResult = await ddcReader.collectResult(preferredDisplayKey: preferredDisplayKey)

        let hdrActive = profiler.hdrDetected == true || edrValues.available
        let diagnosis = Self.classify(
            ddcResult: ddcResult,
            hdrActive: hdrActive,
            edrAvailable: edrValues.available
        )

        var notes = ddcResult.notes
        if profiler.hdrDetected == true {
            notes.append("system_profiler mentions HDR / High Dynamic Range")
        } else if profiler.hdrDetected == false {
            notes.append("system_profiler does not mention HDR")
        } else {
            notes.append("system_profiler HDR state unavailable")
        }
        notes.append("No HDR brightness boost was applied")

        return HDRBrightnessDiagnosticSummary(
            targetDisplayName: target.displayName,
            displayID: target.displayID,
            displayIndex: ddcResult.displayIndex,
            vendorID: target.vendorID,
            productID: target.productID,
            serialNumber: target.serialNumber,
            activeModeLogicalWidth: activeMode?.width,
            activeModeLogicalHeight: activeMode?.height,
            activeModePixelWidth: activeMode?.pixelWidth,
            activeModePixelHeight: activeMode?.pixelHeight,
            activeModeRefreshRate: activeMode?.refreshRate,
            activeModePixelEncoding: activeMode.flatMap { $0.pixelEncoding as String? },
            hdrSystemProfilerStatus: profiler.hdrStatusText,
            systemProfilerColorProfile: profiler.colorProfile,
            systemProfilerEvidence: profiler.evidence,
            ddcReadAvailable: ddcResult.readAvailable,
            ddcCurrentBrightness: ddcResult.currentBrightness,
            ddcMaxBrightness: ddcResult.maxBrightness,
            ddcSetSucceeded: ddcResult.setSucceeded,
            ddcTestBrightness: ddcResult.testBrightness,
            ddcReadbackBrightness: ddcResult.readbackBrightness,
            ddcReadbackChanged: ddcResult.readbackChanged,
            edrValues: edrValues,
            diagnosis: diagnosis,
            notes: notes
        )
    }

    func writeDiagnosticReport(summary: HDRBrightnessDiagnosticSummary) throws -> URL {
        try HDRBrightnessDiagnosticReporter.writeMarkdownReport(summary: summary)
    }

    private static func classify(
        ddcResult: HDRBrightnessDDCResult,
        hdrActive: Bool,
        edrAvailable: Bool
    ) -> HDRBrightnessDiagnosis {
        if !ddcResult.readAvailable {
            return edrAvailable ? .hdrEDRAvailable : .unknown
        }

        if let currentBrightness = ddcResult.currentBrightness,
           let testBrightness = ddcResult.testBrightness,
           let readbackBrightness = ddcResult.readbackBrightness,
           ddcResult.setSucceeded == true,
           abs(readbackBrightness - testBrightness) <= 1,
           currentBrightness != testBrightness {
            return .ddcWorking
        }

        if hdrActive, ddcResult.setSucceeded == true, ddcResult.readbackChanged == false {
            return .ddcIgnoredInHDR
        }

        if edrAvailable {
            return .hdrEDRAvailable
        }

        if hdrActive {
            return .hdrEDRUnavailable
        }

        if ddcResult.setSucceeded == true, ddcResult.readbackChanged == true {
            return .ddcWorking
        }

        return .hdrEDRUnavailable
    }

    private func makeUnknownSummary(
        targetDisplayName: String,
        displayID: CGDirectDisplayID,
        displayIndex: String?,
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32?,
        notes: [String]
    ) -> HDRBrightnessDiagnosticSummary {
        HDRBrightnessDiagnosticSummary(
            targetDisplayName: targetDisplayName,
            displayID: displayID,
            displayIndex: displayIndex,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            activeModeLogicalWidth: nil,
            activeModeLogicalHeight: nil,
            activeModePixelWidth: nil,
            activeModePixelHeight: nil,
            activeModeRefreshRate: nil,
            activeModePixelEncoding: nil,
            hdrSystemProfilerStatus: "unknown",
            systemProfilerColorProfile: nil,
            systemProfilerEvidence: [],
            ddcReadAvailable: false,
            ddcCurrentBrightness: nil,
            ddcMaxBrightness: 100,
            ddcSetSucceeded: nil,
            ddcTestBrightness: nil,
            ddcReadbackBrightness: nil,
            ddcReadbackChanged: nil,
            edrValues: HDRBrightnessEDRValues(
                maximumExtendedDynamicRangeColorComponentValue: nil,
                maximumPotentialExtendedDynamicRangeColorComponentValue: nil,
                maximumReferenceExtendedDynamicRangeColorComponentValue: nil
            ),
            diagnosis: .unknown,
            notes: notes
        )
    }

    private func runSystemProfiler() -> SystemProfilerResult {
        guard let output = runProcess(executable: "/usr/sbin/system_profiler", arguments: ["SPDisplaysDataType", "-detailLevel", "mini"]) else {
            return SystemProfilerResult(hdrDetected: nil, colorProfile: nil, evidence: [], hdrStatusText: "unknown")
        }

        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let evidence = lines.filter {
            let lower = $0.lowercased()
            return lower.contains("hdr") || lower.contains("high dynamic range") || lower.contains("color profile")
        }
        let colorProfile = lines.first(where: { $0.localizedCaseInsensitiveContains("Color Profile") || $0.localizedCaseInsensitiveContains("Display P3") })
        let hdrDetected: Bool?
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hdrDetected = nil
        } else if evidence.contains(where: { $0.localizedCaseInsensitiveContains("hdr") || $0.localizedCaseInsensitiveContains("high dynamic range") }) {
            hdrDetected = true
        } else {
            hdrDetected = false
        }

        let hdrStatusText: String
        switch hdrDetected {
        case .some(true): hdrStatusText = "HDR reported by system_profiler"
        case .some(false): hdrStatusText = "HDR not reported by system_profiler"
        case .none: hdrStatusText = "unknown"
        }
        return SystemProfilerResult(hdrDetected: hdrDetected, colorProfile: colorProfile, evidence: evidence, hdrStatusText: hdrStatusText)
    }

    @MainActor
    private static func screenEDRValues(for displayID: CGDirectDisplayID) -> HDRBrightnessEDRValues {
        let screen = NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == displayID
        }

        guard let screen else {
            return HDRBrightnessEDRValues(
                maximumExtendedDynamicRangeColorComponentValue: nil,
                maximumPotentialExtendedDynamicRangeColorComponentValue: nil,
                maximumReferenceExtendedDynamicRangeColorComponentValue: nil
            )
        }

        return HDRBrightnessEDRValues(
            maximumExtendedDynamicRangeColorComponentValue: screen.maximumExtendedDynamicRangeColorComponentValue,
            maximumPotentialExtendedDynamicRangeColorComponentValue: screen.maximumPotentialExtendedDynamicRangeColorComponentValue,
            maximumReferenceExtendedDynamicRangeColorComponentValue: screen.maximumReferenceExtendedDynamicRangeColorComponentValue
        )
    }

    private func runProcess(executable: String, arguments: [String]) -> String? {
        guard !executable.isEmpty else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private struct SystemProfilerResult {
        let hdrDetected: Bool?
        let colorProfile: String?
        let evidence: [String]
        let hdrStatusText: String
    }
}
