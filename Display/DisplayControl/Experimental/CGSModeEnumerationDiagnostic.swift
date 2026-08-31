import CoreGraphics
import Foundation
import Darwin

struct CGSModeEnumerationEntry: Identifiable, Equatable {
    let id: Int
    let index: Int
    let modeNumber: Int32
    let ioDisplayModeNumber: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRateHz: Double
    let flags: UInt32
    let ioFlags: UInt32
    let isHiDPI: Bool
    let isLowResolution: Bool
    let publicMatchDescription: String?

    var isPerfectQHD: Bool {
        width == HiDPIOverrideReferenceStore.targetLogicalWidth &&
            height == HiDPIOverrideReferenceStore.targetLogicalHeight &&
            pixelWidth == HiDPIOverrideReferenceStore.targetBackingWidth &&
            pixelHeight == HiDPIOverrideReferenceStore.targetBackingHeight &&
            abs(refreshRateHz - HiDPIOverrideReferenceStore.targetRefreshRate) < 0.1 &&
            isHiDPI
    }

    var summaryLine: String {
        let publicMatchText = publicMatchDescription.map { " | public: \($0)" } ?? ""
        return String(
            format: "#%d mode %d / io %d | %dx%d -> %dx%d | %.2fHz | flags 0x%08X | ioFlags 0x%08X | HiDPI:%@ | lowRes:%@%@",
            index,
            modeNumber,
            ioDisplayModeNumber,
            width,
            height,
            pixelWidth,
            pixelHeight,
            refreshRateHz,
            flags,
            ioFlags,
            isHiDPI ? "true" : "false",
            isLowResolution ? "true" : "false",
            publicMatchText
        )
    }
}

struct CGSModeEnumerationSummary {
    let reportPath: String
    let reportTitle: String
    let targetDisplay: TargetDisplayInfo?
    let activeModeDescription: String
    let currentModeID: Int32?
    let cgsModeCount: Int
    let publicDefaultModeCount: Int
    let publicDuplicateModeCount: Int
    let publicDuplicatePerfectQHDExists: Bool
    let descriptionFailureCount: Int
    let entries: [CGSModeEnumerationEntry]
    let mode56: CGSModeEnumerationEntry?
    let mode74: CGSModeEnumerationEntry?

    var reportURL: URL {
        HiDPIReportPaths.reportURL(reportPath)
    }

    var mode74IsPerfectQHD: Bool {
        mode74?.isPerfectQHD == true
    }

    var mode56IsNormalQHD: Bool {
        guard let mode56 else { return false }
        return mode56.width == HiDPIOverrideReferenceStore.targetLogicalWidth &&
            mode56.height == HiDPIOverrideReferenceStore.targetLogicalHeight &&
            mode56.pixelWidth == HiDPIOverrideReferenceStore.targetLogicalWidth &&
            mode56.pixelHeight == HiDPIOverrideReferenceStore.targetLogicalHeight &&
            abs(mode56.refreshRateHz - HiDPIOverrideReferenceStore.targetRefreshRate) < 0.1 &&
            !mode56.isHiDPI
    }

    var canApplyMode74Transaction: Bool {
        targetDisplay != nil && currentModeID != nil && mode74IsPerfectQHD
    }

    var cgsInternalPoolWiderThanPublic: Bool {
        cgsModeCount > publicDuplicateModeCount
    }
}

struct CGSModeEnumerationApplyOutcome {
    let attempted: Bool
    let resultDescription: String
    let finalSummary: CGSModeEnumerationSummary
}

struct CGSModeApplyExperimentStepOutcome {
    let modeLabel: String
    let requestedModeNumber: Int32
    let beforeModeID: Int32?
    let afterModeID: Int32?
    let applyAttempted: Bool
    let alreadyActive: Bool
    let applyResultDescription: String
    let rollbackAttempted: Bool
    let rollbackResultDescription: String?
    let success: Bool
}

struct CGSModeApplyExperimentSummary {
    let reportPath: String
    let reportTitle: String
    let targetDisplay: TargetDisplayInfo?
    let initialModeID: Int32?
    let mode56Verified: Bool
    let mode74Verified: Bool
    let mode56Outcome: CGSModeApplyExperimentStepOutcome?
    let mode74Outcome: CGSModeApplyExperimentStepOutcome?
    let finalSummary: CGSModeEnumerationSummary
    let systemProfilerOutput: String
    let success: Bool
    let failureReason: String?

    var reportURL: URL {
        HiDPIReportPaths.reportURL(reportPath)
    }
}

struct CGSMode56To74RealTestSummary {
    let reportPath: String
    let reportTitle: String
    let targetDisplay: TargetDisplayInfo?
    let initialModeID: Int32?
    let initialModeDescription: String
    let mode56Verified: Bool
    let mode74Attempted: Bool
    let mode74OutcomeDescription: String?
    let finalSummary: CGSModeEnumerationSummary
    let systemProfilerOutput: String
    let success: Bool
    let failureReason: String?

    var reportURL: URL {
        HiDPIReportPaths.reportURL(reportPath)
    }
}

final class CGSModeEnumerationDiagnostic {
    private typealias CGSGetCurrentDisplayModeFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias CGSGetNumberOfDisplayModesFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias CGSGetDisplayModeDescriptionOfLengthFunc = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> CGError
    private typealias CGSConfigureDisplayModeFunc = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Int32) -> Int32

    private enum DescriptionLayout {
        static let size = 212
        static let modeNumber = 0
        static let flags = 4
        static let width = 8
        static let height = 12
        static let refreshRate = 36
        static let fixPtRefreshRate = 188
        static let ioModeInfoFlags = 192
        static let ioDisplayModeNumber = 196
        static let pixelsWide = 200
        static let pixelsHigh = 204
    }

    private static let defaultReportPath = "docs/generated/private_activation/cgs_mode_enumeration.md"
    private static let withoutBetterDisplayReportPath = "docs/generated/private_activation/cgs_mode74_without_betterdisplay.md"
    private static let applyExperimentReportPath = "docs/generated/private_activation/cgs_mode74_apply_experiment.md"
    private static let realTestReportPath = "docs/generated/private_activation/cgs_mode56_to_74_real_test.md"

    static func reportURL(reportPath: String = defaultReportPath) -> URL {
        HiDPIReportPaths.reportURL(reportPath)
    }

    static func runEnumeration() throws -> CGSModeEnumerationSummary {
        let summary = collectSummary(reportPath: defaultReportPath, reportTitle: "CGS Mode Enumeration")
        _ = try writeReport(summary: summary, applyOutcome: nil)
        return summary
    }

    static func runWithoutBetterDisplayVerification() throws -> CGSModeEnumerationSummary {
        let summary = collectSummary(
            reportPath: withoutBetterDisplayReportPath,
            reportTitle: "CGS Mode 74 Check (Without BetterDisplay)"
        )
        _ = try writeReport(summary: summary, applyOutcome: nil)
        return summary
    }

    static func runMode56NormalQHDApplyExperiment(using existingState: CGSModeApplyExperimentSummary? = nil) throws -> CGSModeApplyExperimentSummary {
        try runModeApplyExperiment(
            requestedModeLabel: "Mode 56 Normal QHD",
            requestedModeNumber: 56,
            existingState: existingState
        )
    }

    static func runMode74ApplyExperiment(using existingState: CGSModeApplyExperimentSummary? = nil) throws -> CGSModeApplyExperimentSummary {
        try runModeApplyExperiment(
            requestedModeLabel: "Mode 74 Perfect QHD",
            requestedModeNumber: 74,
            existingState: existingState
        )
    }

    static func runMode56Then74ApplyExperiment() throws -> CGSModeApplyExperimentSummary {
        let mode56State = try runMode56NormalQHDApplyExperiment()
        return try runMode74ApplyExperiment(using: mode56State)
    }

    static func runMode56To74RealTest() throws -> CGSMode56To74RealTestSummary {
        let initialSummary = collectSummary(reportPath: realTestReportPath, reportTitle: "CGS Mode 56 -> 74 Real Test")
        let systemProfilerOutput = systemProfilerDisplayOutput()
        let initialModeID = initialSummary.currentModeID
        let mode56Verified = initialSummary.mode56IsNormalQHD && initialModeID == 56

        func makeSummary(
            mode74Attempted: Bool,
            mode74OutcomeDescription: String?,
            finalSummary: CGSModeEnumerationSummary,
            success: Bool,
            failureReason: String?
        ) -> CGSMode56To74RealTestSummary {
            CGSMode56To74RealTestSummary(
                reportPath: realTestReportPath,
                reportTitle: "CGS Mode 56 -> 74 Real Test",
                targetDisplay: initialSummary.targetDisplay,
                initialModeID: initialModeID,
                initialModeDescription: initialSummary.activeModeDescription,
                mode56Verified: mode56Verified,
                mode74Attempted: mode74Attempted,
                mode74OutcomeDescription: mode74OutcomeDescription,
                finalSummary: finalSummary,
                systemProfilerOutput: systemProfilerOutput,
                success: success,
                failureReason: failureReason
            )
        }

        if initialModeID == 74 {
            let summary = makeSummary(
                mode74Attempted: false,
                mode74OutcomeDescription: "Invalid test: Mode 74 already active",
                finalSummary: initialSummary,
                success: false,
                failureReason: "Invalid test: Mode 74 already active"
            )
            _ = try writeRealTestReport(summary: summary)
            return summary
        }

        guard initialModeID == 56 else {
            let summary = makeSummary(
                mode74Attempted: false,
                mode74OutcomeDescription: "Invalid test: Mode 56 not active",
                finalSummary: initialSummary,
                success: false,
                failureReason: "Invalid test: Mode 56 not active"
            )
            _ = try writeRealTestReport(summary: summary)
            return summary
        }

        guard mode56Verified else {
            let summary = makeSummary(
                mode74Attempted: false,
                mode74OutcomeDescription: "Invalid test: Mode 56 not verified as normal QHD",
                finalSummary: initialSummary,
                success: false,
                failureReason: "Invalid test: Mode 56 not verified as normal QHD"
            )
            _ = try writeRealTestReport(summary: summary)
            return summary
        }

        guard initialSummary.mode74IsPerfectQHD, let target = initialSummary.targetDisplay else {
            let summary = makeSummary(
                mode74Attempted: false,
                mode74OutcomeDescription: "Mode 74 Perfect QHD not verified",
                finalSummary: initialSummary,
                success: false,
                failureReason: "Mode 74 Perfect QHD not verified"
            )
            _ = try writeRealTestReport(summary: summary)
            return summary
        }

        let mode74OutcomeDescription = configureCGSMode(displayID: target.displayID, modeNumber: 74) ?? "CGS mode 74 apply attempted"
        Thread.sleep(forTimeInterval: 1.0)
        var finalSummary = collectSummary(reportPath: realTestReportPath, reportTitle: "CGS Mode 56 -> 74 Real Test")
        let mode74Attempted = true
        var success = finalSummary.currentModeID == 74 && finalSummary.mode74IsPerfectQHD
        var failureReason: String? = success ? nil : "Mode 74 did not become active"

        if !success {
            _ = configureCGSMode(displayID: target.displayID, modeNumber: 56)
            Thread.sleep(forTimeInterval: 1.0)
            finalSummary = collectSummary(reportPath: realTestReportPath, reportTitle: "CGS Mode 56 -> 74 Real Test")
            success = finalSummary.currentModeID == 74 && finalSummary.mode74IsPerfectQHD
            failureReason = success ? nil : "Mode 74 did not become active"
        }

        let summary = makeSummary(
            mode74Attempted: mode74Attempted,
            mode74OutcomeDescription: mode74OutcomeDescription,
            finalSummary: finalSummary,
            success: success,
            failureReason: failureReason
        )
        _ = try writeRealTestReport(summary: summary)
        return summary
    }

    static func applyMode74Transaction(using summary: CGSModeEnumerationSummary) throws -> CGSModeEnumerationApplyOutcome {
        guard summary.canApplyMode74Transaction else {
            throw NSError(
                domain: "CGSModeEnumerationDiagnostic",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Mode 74 doğrulanmadı; apply denenemez."]
            )
        }

        guard let target = summary.targetDisplay, let mode74 = summary.mode74 else {
            throw NSError(
                domain: "CGSModeEnumerationDiagnostic",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Target display veya mode 74 bilgisi eksik."]
            )
        }

        guard let configureSymbol = resolveFirstSymbol(["CGSConfigureDisplayMode", "SLSConfigureDisplayMode"]) else {
            throw NSError(
                domain: "CGSModeEnumerationDiagnostic",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "CGSConfigureDisplayMode / SLSConfigureDisplayMode sembolü bulunamadı."]
            )
        }

        let configure = unsafeBitCast(configureSymbol.pointer, to: CGSConfigureDisplayModeFunc.self)

        var config: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&config)
        guard beginResult == .success, let config else {
            let message = "CGBeginDisplayConfiguration failed: \(beginResult.rawValue)"
            let finalSummary = collectSummary(reportPath: summary.reportPath, reportTitle: summary.reportTitle)
            _ = try writeReport(summary: summary, applyOutcome: CGSModeEnumerationApplyOutcome(attempted: true, resultDescription: message, finalSummary: finalSummary))
            return CGSModeEnumerationApplyOutcome(attempted: true, resultDescription: message, finalSummary: finalSummary)
        }

        let configureResult = configure(config, target.displayID, mode74.modeNumber)
        guard configureResult == 0 else {
            CGCancelDisplayConfiguration(config)
            let message = "CGSConfigureDisplayMode returned \(configureResult)"
            let finalSummary = collectSummary(reportPath: summary.reportPath, reportTitle: summary.reportTitle)
            _ = try writeReport(summary: summary, applyOutcome: CGSModeEnumerationApplyOutcome(attempted: true, resultDescription: message, finalSummary: finalSummary))
            return CGSModeEnumerationApplyOutcome(attempted: true, resultDescription: message, finalSummary: finalSummary)
        }

        let completeResult = CGCompleteDisplayConfiguration(config, .forSession)
        if completeResult != .success {
            CGCancelDisplayConfiguration(config)
        }

        Thread.sleep(forTimeInterval: 1.0)

        let finalSummary = collectSummary(reportPath: summary.reportPath, reportTitle: summary.reportTitle)
        let message = completeResult == .success
            ? "CGSConfigureDisplayMode(\(mode74.modeNumber)) + CGCompleteDisplayConfiguration(option: 2) succeeded."
            : "CGCompleteDisplayConfiguration failed: \(completeResult.rawValue)"

        _ = try writeReport(
            summary: summary,
            applyOutcome: CGSModeEnumerationApplyOutcome(
                attempted: true,
                resultDescription: message,
                finalSummary: finalSummary
            )
        )
        return CGSModeEnumerationApplyOutcome(
            attempted: true,
            resultDescription: message,
            finalSummary: finalSummary
        )
    }

    static func runModeApplyExperiment(
        requestedModeLabel: String,
        requestedModeNumber: Int32,
        existingState: CGSModeApplyExperimentSummary? = nil
    ) throws -> CGSModeApplyExperimentSummary {
        let strictTarget = try HiDPITargetDisplayResolver.resolveSamsungS60UD()
        let summary = collectSummary(reportPath: applyExperimentReportPath, reportTitle: "CGS Mode 74 Apply Experiment")

        guard let currentModeID = summary.currentModeID else {
            throw NSError(
                domain: "CGSModeEnumerationDiagnostic",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Mevcut CGS mode id okunamadı."]
            )
        }

        let initialModeID = existingState?.initialModeID ?? currentModeID
        let mode56Outcome = existingState?.mode56Outcome
        let mode74Outcome = existingState?.mode74Outcome

        let requestedMode = requestedModeNumber == 56 ? summary.mode56 : summary.mode74
        guard let requestedMode else {
            throw NSError(
                domain: "CGSModeEnumerationDiagnostic",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "\(requestedModeLabel) CGS listesinde doğrulanamadı."]
            )
        }

        if requestedModeNumber == 56, !summary.mode56IsNormalQHD {
            throw NSError(
                domain: "CGSModeEnumerationDiagnostic",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Mode 56 normal QHD olarak doğrulanmadı."]
            )
        }

        if requestedModeNumber == 74, !summary.mode74IsPerfectQHD {
            throw NSError(
                domain: "CGSModeEnumerationDiagnostic",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Mode 74 Perfect QHD olarak doğrulanmadı."]
            )
        }

        let beforeModeID = currentModeID
        let configureResultDescription: String
        var rollbackAttempted = false
        var rollbackResultDescription: String?
        var finalSummary = summary

        if beforeModeID == requestedModeNumber {
            configureResultDescription = "\(requestedModeLabel) zaten aktif; apply atlandı."
        } else {
            let configureError = configureCGSMode(displayID: strictTarget.displayID, modeNumber: requestedMode.modeNumber)
            if let configureError {
                configureResultDescription = configureError
            } else {
                Thread.sleep(forTimeInterval: 1.0)
                finalSummary = collectSummary(reportPath: applyExperimentReportPath, reportTitle: "CGS Mode 74 Apply Experiment")
                if finalSummary.currentModeID == requestedModeNumber {
                    configureResultDescription = "\(requestedModeLabel) başarıyla uygulandı."
                } else {
                    configureResultDescription = "Mode \(requestedModeNumber) apply sonrası aktif olmadı; current: \(finalSummary.currentModeID.map(String.init) ?? "unavailable")."
                    if beforeModeID != requestedModeNumber {
                        rollbackAttempted = true
                        rollbackResultDescription = configureCGSMode(displayID: strictTarget.displayID, modeNumber: beforeModeID)
                        Thread.sleep(forTimeInterval: 1.0)
                        finalSummary = collectSummary(reportPath: applyExperimentReportPath, reportTitle: "CGS Mode 74 Apply Experiment")
                    }
                }
            }
        }

        if finalSummary.currentModeID != requestedModeNumber, beforeModeID != requestedModeNumber, rollbackResultDescription == nil {
            rollbackAttempted = true
            rollbackResultDescription = configureCGSMode(displayID: strictTarget.displayID, modeNumber: beforeModeID)
            Thread.sleep(forTimeInterval: 1.0)
            finalSummary = collectSummary(reportPath: applyExperimentReportPath, reportTitle: "CGS Mode 74 Apply Experiment")
        }

        let systemProfilerOutput = systemProfilerDisplayOutput()
        let stepOutcome = CGSModeApplyExperimentStepOutcome(
            modeLabel: requestedModeLabel,
            requestedModeNumber: requestedModeNumber,
            beforeModeID: beforeModeID,
            afterModeID: finalSummary.currentModeID,
            applyAttempted: beforeModeID != requestedModeNumber,
            alreadyActive: beforeModeID == requestedModeNumber,
            applyResultDescription: configureResultDescription,
            rollbackAttempted: rollbackAttempted,
            rollbackResultDescription: rollbackResultDescription,
            success: finalSummary.currentModeID == requestedModeNumber
        )

        let updatedState = CGSModeApplyExperimentSummary(
            reportPath: applyExperimentReportPath,
            reportTitle: "CGS Mode 74 Apply Experiment",
            targetDisplay: strictTarget,
            initialModeID: initialModeID,
            mode56Verified: finalSummary.mode56IsNormalQHD,
            mode74Verified: finalSummary.mode74IsPerfectQHD,
            mode56Outcome: requestedModeNumber == 56 ? stepOutcome : mode56Outcome,
            mode74Outcome: requestedModeNumber == 74 ? stepOutcome : mode74Outcome,
            finalSummary: finalSummary,
            systemProfilerOutput: systemProfilerOutput,
            success: stepOutcome.success,
            failureReason: stepOutcome.success
                ? nil
                : ([stepOutcome.applyResultDescription, stepOutcome.rollbackResultDescription]
                    .compactMap { $0 }
                    .joined(separator: " | "))
        )

        _ = try writeApplyExperimentReport(summary: updatedState)
        return updatedState
    }

    private static func configureCGSMode(displayID: CGDirectDisplayID, modeNumber: Int32) -> String? {
        guard let configureSymbol = resolveFirstSymbol(["CGSConfigureDisplayMode", "SLSConfigureDisplayMode"]) else {
            return "CGSConfigureDisplayMode / SLSConfigureDisplayMode sembolü bulunamadı."
        }

        let configure = unsafeBitCast(configureSymbol.pointer, to: CGSConfigureDisplayModeFunc.self)

        var config: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&config)
        guard beginResult == .success, let config else {
            return "CGBeginDisplayConfiguration failed: \(beginResult.rawValue)"
        }

        let configureResult = configure(config, displayID, modeNumber)
        guard configureResult == 0 else {
            CGCancelDisplayConfiguration(config)
            return "CGSConfigureDisplayMode returned \(configureResult)"
        }

        let completeResult = CGCompleteDisplayConfiguration(config, .forSession)
        if completeResult != .success {
            CGCancelDisplayConfiguration(config)
            return "CGCompleteDisplayConfiguration failed: \(completeResult.rawValue)"
        }

        return "CGSConfigureDisplayMode(\(modeNumber)) + CGCompleteDisplayConfiguration(option: 2) succeeded."
    }

    private static func systemProfilerDisplayOutput() -> String {
        let output = shellOutput("/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null")
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let filtered = lines.filter {
            $0.contains("Resolution:") ||
                $0.contains("UI Looks like:") ||
                $0.contains("Refresh Rate:") ||
                $0.contains("Vendor:") ||
                $0.contains("Product ID:") ||
                $0.contains("Serial Number:") ||
                $0.contains("Samsung")
        }
        return filtered.isEmpty ? String(output.prefix(6000)) : filtered.joined(separator: "\n")
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

    static func writeApplyExperimentReport(summary: CGSModeApplyExperimentSummary) throws -> URL {
        let url = summary.reportURL
        let report = buildApplyExperimentReport(summary: summary)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func writeRealTestReport(summary: CGSMode56To74RealTestSummary) throws -> URL {
        let url = summary.reportURL
        let report = buildRealTestReport(summary: summary)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func buildRealTestReport(summary: CGSMode56To74RealTestSummary) -> String {
        var lines: [String] = []
        lines.append("# \(summary.reportTitle)")
        lines.append("")
        lines.append("Generated at: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append("## Başlangıç mode")
        lines.append("- \(summary.initialModeDescription)")
        lines.append("")
        lines.append("## Mode 56 gerçekten aktif mi?")
        lines.append("- \(summary.mode56Verified ? "Evet" : "Hayır")")
        lines.append("")
        lines.append("## Mode 74 denendi mi?")
        lines.append("- \(summary.mode74Attempted ? "Evet" : "Hayır")")
        if let outcome = summary.mode74OutcomeDescription {
            lines.append("- \(outcome)")
        }
        lines.append("")
        lines.append("## Final mode")
        lines.append("- \(summary.finalSummary.activeModeDescription)")
        lines.append("")
        lines.append("## system_profiler sonucu")
        lines.append("```")
        lines.append(summary.systemProfilerOutput)
        lines.append("```")
        lines.append("")
        lines.append("## Başarılı mı?")
        lines.append("- \(summary.success ? "Evet" : "Hayır")")
        if let failureReason = summary.failureReason {
            lines.append("- \(failureReason)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func buildApplyExperimentReport(summary: CGSModeApplyExperimentSummary) -> String {
        var lines: [String] = []
        lines.append("# \(summary.reportTitle)")
        lines.append("")
        lines.append("Generated at: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append("## Before mode id")
        lines.append("- \(summary.initialModeID.map(String.init) ?? "unavailable")")
        lines.append("")
        lines.append("## Mode 56 doğrulandı mı?")
        lines.append("- \(summary.mode56Verified ? "Evet" : "Hayır")")
        lines.append("")
        lines.append("## Mode 74 doğrulandı mı?")
        lines.append("- \(summary.mode74Verified ? "Evet" : "Hayır")")
        lines.append("")
        lines.append("## Mode 56 apply sonucu")
        lines.append("- \(renderStepOutcome(summary.mode56Outcome))")
        lines.append("")
        lines.append("## Mode 74 apply sonucu")
        lines.append("- \(renderStepOutcome(summary.mode74Outcome))")
        lines.append("")
        lines.append("## Final active mode")
        lines.append("- \(summary.finalSummary.activeModeDescription)")
        lines.append("")
        lines.append("## system_profiler sonucu")
        lines.append("```")
        lines.append(summary.systemProfilerOutput)
        lines.append("```")
        lines.append("")
        lines.append("## Başarı/başarısızlık")
        lines.append("- \(summary.success ? "Başarılı" : "Başarısız")")
        if let failureReason = summary.failureReason {
            lines.append("- \(failureReason)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderStepOutcome(_ outcome: CGSModeApplyExperimentStepOutcome?) -> String {
        guard let outcome else { return "not attempted" }
        var parts: [String] = []
        parts.append("requested \(outcome.requestedModeNumber)")
        parts.append("before \(outcome.beforeModeID.map(String.init) ?? "unavailable")")
        parts.append("after \(outcome.afterModeID.map(String.init) ?? "unavailable")")
        parts.append(outcome.alreadyActive ? "already active" : "apply attempted")
        parts.append(outcome.applyResultDescription)
        if outcome.rollbackAttempted {
            parts.append("rollback: \(outcome.rollbackResultDescription ?? "attempted")")
        }
        parts.append(outcome.success ? "success" : "failure")
        return parts.joined(separator: " | ")
    }

    static func collectSummary(
        reportPath: String = defaultReportPath,
        reportTitle: String = "CGS Mode Enumeration"
    ) -> CGSModeEnumerationSummary {
        let target = (try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics()) ?? (try? HiDPITargetDisplayResolver.resolveSamsungS60UD())
        let publicDefaultModes = target.map { NativeDisplayModeReader.getDefaultModes(for: $0.displayID) } ?? []
        let publicDuplicateModes = target.map { NativeDisplayModeReader.getHiDPIApplyCandidateModes(for: $0.displayID) } ?? []
        let publicDuplicatePerfectQHDExists = publicDuplicateModes.contains { NativeDisplayModeReader.isPerfectQHDHiDPIMode($0) }

        let activeModeDescription = target.flatMap { target -> String? in
            guard let current = CGDisplayCopyDisplayMode(target.displayID) else { return nil }
            return String(
                format: "%dx%d logical / %dx%d pixel @ %.2fHz / ioMode %u",
                current.width,
                current.height,
                current.pixelWidth,
                current.pixelHeight,
                current.refreshRate,
                current.ioDisplayModeID
            )
        } ?? "unavailable"

        let currentModeID = resolveCurrentModeID(displayID: target?.displayID ?? 0)
        let cgsModeCount = resolveModeCount(displayID: target?.displayID ?? 0)
        let cgsModes = collectCGSModes(displayID: target?.displayID ?? 0, publicModes: publicDuplicateModes)
        let mode56 = cgsModes.first { $0.modeNumber == 56 || $0.ioDisplayModeNumber == 56 }
        let mode74 = cgsModes.first { $0.modeNumber == 74 || $0.ioDisplayModeNumber == 74 }
        let descriptionFailureCount = max(0, cgsModeCount - cgsModes.count)

        return CGSModeEnumerationSummary(
            reportPath: reportPath,
            reportTitle: reportTitle,
            targetDisplay: target,
            activeModeDescription: activeModeDescription,
            currentModeID: currentModeID,
            cgsModeCount: cgsModeCount,
            publicDefaultModeCount: publicDefaultModes.count,
            publicDuplicateModeCount: publicDuplicateModes.count,
            publicDuplicatePerfectQHDExists: publicDuplicatePerfectQHDExists,
            descriptionFailureCount: descriptionFailureCount,
            entries: cgsModes,
            mode56: mode56,
            mode74: mode74
        )
    }

    static func writeReport(summary: CGSModeEnumerationSummary, applyOutcome: CGSModeEnumerationApplyOutcome?) throws -> URL {
        let url = summary.reportURL
        let report = buildReport(summary: summary, applyOutcome: applyOutcome)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func buildReport(summary: CGSModeEnumerationSummary, applyOutcome: CGSModeEnumerationApplyOutcome?) -> String {
        var lines: [String] = []
        lines.append("# \(summary.reportTitle)")
        lines.append("")
        lines.append("Generated at: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        lines.append("## CGS current mode id")
        lines.append("- \(summary.currentModeID.map(String.init) ?? "unavailable")")
        lines.append("")

        lines.append("## Başlangıç active mode")
        lines.append("- \(summary.activeModeDescription)")
        lines.append("")

        lines.append("## Public mode count")
        lines.append("- default: \(summary.publicDefaultModeCount)")
        lines.append("- duplicateLowResolutionModes=true: \(summary.publicDuplicateModeCount)")
        lines.append("- public duplicate listte Perfect QHD var mı?: \(summary.publicDuplicatePerfectQHDExists ? "Evet" : "Hayır")")
        lines.append("")

        lines.append("## CGS mode count")
        lines.append("- \(summary.cgsModeCount)")
        lines.append("- CGS internal mode pool public CoreGraphics listesinden geniş: \(summary.cgsInternalPoolWiderThanPublic ? "Evet" : "Hayır")")
        lines.append("")

        lines.append("## Mode 56 var mı?")
        if let mode56 = summary.mode56 {
            lines.append("- var")
            lines.append("- \(mode56.summaryLine)")
        } else {
            lines.append("- yok")
        }
        lines.append("")

        lines.append("## Mode 74 var mı?")
        if let mode74 = summary.mode74 {
            lines.append("- var")
            lines.append("- \(mode74.summaryLine)")
            lines.append("- Mode 74 description okunabiliyor mu?: Evet")
        } else {
            lines.append("- yok")
            lines.append("- Mode 74 description okunabiliyor mu?: Hayır")
        }
        lines.append("")

        lines.append("## Mode 74 Perfect QHD mi?")
        lines.append("- \(summary.mode74IsPerfectQHD ? "Evet" : "Hayır")")
        lines.append("")

        lines.append("## Apply denendi mi?")
        lines.append("- \(applyOutcome?.attempted == true ? "Evet" : "Hayır")")
        lines.append("")

        lines.append("## Apply sonucu")
        lines.append("- \(applyOutcome?.resultDescription ?? "not attempted")")
        lines.append("")

        lines.append("## Son active mode")
        lines.append("- \(applyOutcome?.finalSummary.activeModeDescription ?? summary.activeModeDescription)")
        lines.append("")

        lines.append("## Son karar")
        if summary.mode74 == nil {
            lines.append("- Mode 74 yalnızca BetterDisplay activation sonrası CGS listesine giriyor. Hâlâ activation problemi var.")
        } else if summary.publicDuplicatePerfectQHDExists {
            lines.append("- Mode 74 CGS listede ve public duplicate listte de Perfect QHD var.")
        } else {
            lines.append("- Mode 74 CGS internal listte var; public duplicate listte Perfect QHD yok. Apply CGS Mode 74 denenebilir.")
        }
        lines.append("")

        lines.append("## Description failures")
        lines.append("- \(summary.descriptionFailureCount)")
        lines.append("")

        lines.append("## CGS mode dump")
        lines.append("")
        lines.append("| # | mode id | io mode | logical | pixel | refresh | flags | ioFlags | HiDPI | lowRes | public match |")
        lines.append("|---:|---:|---:|---|---|---:|---:|---:|---|---|---|")
        for entry in summary.entries {
            lines.append(String(
                format: "| %d | %d | %d | %dx%d | %dx%d | %.2f | 0x%08X | 0x%08X | %@ | %@ | %@ |",
                entry.index,
                entry.modeNumber,
                entry.ioDisplayModeNumber,
                entry.width,
                entry.height,
                entry.pixelWidth,
                entry.pixelHeight,
                entry.refreshRateHz,
                entry.flags,
                entry.ioFlags,
                entry.isHiDPI ? "true" : "false",
                entry.isLowResolution ? "true" : "false",
                entry.publicMatchDescription ?? "n/a"
            ))
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func collectCGSModes(displayID: CGDirectDisplayID, publicModes: [PhysicalDisplayMode]) -> [CGSModeEnumerationEntry] {
        guard displayID != 0 else { return [] }
        guard resolveModeCount(displayID: displayID) > 0 else { return [] }
        guard let descriptionSymbol = resolveFirstSymbol(["CGSGetDisplayModeDescriptionOfLength", "SLSGetDisplayModeDescriptionOfLength"]) else {
            return []
        }

        let description = unsafeBitCast(descriptionSymbol.pointer, to: CGSGetDisplayModeDescriptionOfLengthFunc.self)
        let modeCount = resolveModeCount(displayID: displayID)
        guard modeCount > 0 else { return [] }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: DescriptionLayout.size, alignment: MemoryLayout<Int32>.alignment)
        defer { buffer.deallocate() }

        var entries: [CGSModeEnumerationEntry] = []
        entries.reserveCapacity(modeCount)

        for index in 0..<modeCount {
            memset(buffer, 0, DescriptionLayout.size)
            let result = description(displayID, Int32(index), buffer, Int32(DescriptionLayout.size))
            guard result == .success else { continue }

            let modeNumber = readInt32(buffer, DescriptionLayout.modeNumber)
            let flags = readUInt32(buffer, DescriptionLayout.flags)
            let width = Int(readInt32(buffer, DescriptionLayout.width))
            let height = Int(readInt32(buffer, DescriptionLayout.height))
            let refreshRaw = readInt32(buffer, DescriptionLayout.fixPtRefreshRate)
            let fallbackRefreshRaw = readInt32(buffer, DescriptionLayout.refreshRate)
            let refreshHz = decodeRefreshHz(rawRefresh: refreshRaw, fallbackRaw: fallbackRefreshRaw)
            let ioFlags = readUInt32(buffer, DescriptionLayout.ioModeInfoFlags)
            let ioDisplayModeNumber = readInt32(buffer, DescriptionLayout.ioDisplayModeNumber)
            let pixelWidth = Int(readInt32(buffer, DescriptionLayout.pixelsWide))
            let pixelHeight = Int(readInt32(buffer, DescriptionLayout.pixelsHigh))
            let isHiDPI = pixelWidth > width || pixelHeight > height
            let isLowResolution = !isHiDPI
            let publicMatch = matchPublicMode(
                publicModes: publicModes,
                modeNumber: modeNumber,
                ioDisplayModeNumber: ioDisplayModeNumber,
                width: width,
                height: height,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                refreshHz: refreshHz
            )

            entries.append(
                CGSModeEnumerationEntry(
                    id: index,
                    index: index,
                    modeNumber: modeNumber,
                    ioDisplayModeNumber: ioDisplayModeNumber,
                    width: width,
                    height: height,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    refreshRateHz: refreshHz,
                    flags: flags,
                    ioFlags: ioFlags,
                    isHiDPI: isHiDPI,
                    isLowResolution: isLowResolution,
                    publicMatchDescription: publicMatch
                )
            )
        }

        return entries
    }

    private static func matchPublicMode(
        publicModes: [PhysicalDisplayMode],
        modeNumber: Int32,
        ioDisplayModeNumber: Int32,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshHz: Double
    ) -> String? {
        let exactMatches = publicModes.filter {
            Int32($0.cgMode.ioDisplayModeID) == modeNumber || Int32($0.cgMode.ioDisplayModeID) == ioDisplayModeNumber
        }

        let dimensionMatches = publicModes.filter {
            $0.width == width &&
                $0.height == height &&
                $0.pixelWidth == pixelWidth &&
                $0.pixelHeight == pixelHeight &&
                abs($0.refreshRate - refreshHz) < 0.1
        }

        let candidate = exactMatches.first ?? dimensionMatches.first
        guard let candidate else { return nil }
        return String(
            format: "%dx%d/%dx%d @ %.2fHz | ioMode %u",
            candidate.width,
            candidate.height,
            candidate.pixelWidth,
            candidate.pixelHeight,
            candidate.refreshRate,
            candidate.cgMode.ioDisplayModeID
        )
    }

    private static func resolveCurrentModeID(displayID: CGDirectDisplayID) -> Int32? {
        guard displayID != 0 else { return nil }
        guard let symbol = resolveFirstSymbol(["CGSGetCurrentDisplayMode", "SLSGetCurrentDisplayMode"]) else {
            return nil
        }
        let function = unsafeBitCast(symbol.pointer, to: CGSGetCurrentDisplayModeFunc.self)
        var modeID: Int32 = 0
        let result = function(displayID, &modeID)
        return result == .success ? modeID : nil
    }

    private static func resolveModeCount(displayID: CGDirectDisplayID) -> Int {
        guard displayID != 0 else { return 0 }
        guard let symbol = resolveFirstSymbol(["CGSGetNumberOfDisplayModes", "SLSGetNumberOfDisplayModes"]) else {
            return 0
        }
        let function = unsafeBitCast(symbol.pointer, to: CGSGetNumberOfDisplayModesFunc.self)
        var count: Int32 = 0
        let result = function(displayID, &count)
        return result == .success ? Int(count) : 0
    }

    private static func resolveFirstSymbol(_ names: [String]) -> (name: String, pointer: UnsafeMutableRawPointer)? {
        let resolver = PrivateDisplaySymbolResolver.shared
        for name in names {
            if let pointer = resolver.resolveSymbol(name: name) {
                return (name, pointer)
            }
        }
        return nil
    }

    private static func readInt32(_ pointer: UnsafeMutableRawPointer, _ offset: Int) -> Int32 {
        pointer.load(fromByteOffset: offset, as: Int32.self)
    }

    private static func readUInt32(_ pointer: UnsafeMutableRawPointer, _ offset: Int) -> UInt32 {
        pointer.load(fromByteOffset: offset, as: UInt32.self)
    }

    private static func decodeRefreshHz(rawRefresh: Int32, fallbackRaw: Int32) -> Double {
        let candidate = rawRefresh != 0 ? rawRefresh : fallbackRaw
        guard candidate != 0 else { return 0 }
        return candidate > 1000 ? Double(candidate) / 65536.0 : Double(candidate)
    }
}
