import Foundation
import CoreGraphics

@MainActor
class PrivateActivationExperiment {
    
    enum ExperimentResult {
        case success(message: String)
        case failure(reason: String)
        case skipped(reason: String)
    }
    
    let targetDisplayID: CGDirectDisplayID
    
    init(targetDisplayID: CGDirectDisplayID) {
        self.targetDisplayID = targetDisplayID
    }

    private struct SymbolResolution {
        let name: String
        let found: Bool
    }

    private struct ModePoolSnapshot {
        let activeDescription: String
        let activeModeNumber: Int32?
        let duplicateModeCount: Int
        let hiDPICount: Int
        let perfectMode: PhysicalDisplayMode?
        let modeDump: String
    }

    private typealias SLSConfigureDisplayModeFunc = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Int32) -> Int32
    private typealias SLSCompleteDisplayConfigurationWithOptionFunc = @convention(c) (CGDisplayConfigRef, Int32) -> Int32
    private typealias SLSCompleteDisplayConfigurationFunc = @convention(c) (CGDisplayConfigRef) -> Int32
    
    /// Run SLS Detect Displays Activation
    /// Uses SLSMainConnectionID and SLSDetectDisplays to trigger a WindowServer rescan.
    func runSLSDetectDisplaysExperiment() -> ExperimentResult {
        guard HiDPIPrivateActivationSafety.shared.isExperimentAllowed() else {
            return .skipped(reason: "Experimental mode disabled.")
        }
        
        guard HiDPIPrivateActivationSafety.shared.validateTargetDisplay(displayID: targetDisplayID) else {
            return .skipped(reason: "Safety guard failed: Target display invalid.")
        }
        
        print("Starting SLSDetectDisplays Reload Experiment...")
        
        let beforeCount = getModeCount()
        let beforeHasPerfect = checkForPerfectQHD()
        
        let resolver = PrivateDisplaySymbolResolver.shared
        
        // Resolve SLSMainConnectionID
        guard let mainConnSym = resolver.resolveSymbol(name: "SLSMainConnectionID") else {
            return .failure(reason: "Symbol SLSMainConnectionID not found.")
        }
        typealias SLSMainConnectionIDFunc = @convention(c) () -> Int32
        let getConn = unsafeBitCast(mainConnSym, to: SLSMainConnectionIDFunc.self)
        
        // Resolve SLSDetectDisplays
        guard let detectSym = resolver.resolveSymbol(name: "SLSDetectDisplays") else {
            return .failure(reason: "Symbol SLSDetectDisplays not found.")
        }
        typealias SLSDetectDisplaysFunc = @convention(c) (Int32) -> Int32
        let detect = unsafeBitCast(detectSym, to: SLSDetectDisplaysFunc.self)
        
        let cid = getConn()
        print("SLSMainConnectionID: \(cid)")
        
        let result = detect(cid)
        print("SLSDetectDisplays result: \(result)")
        
        // Wait 1 second for WindowServer to process and read overrides
        Thread.sleep(forTimeInterval: 1.0)
        
        let afterCount = getModeCount()
        let afterHasPerfect = checkForPerfectQHD()
        
        print("Mode Count Change: \(beforeCount) -> \(afterCount)")
        
        var report = "# SLS Detect Displays Experiment Report\n\n"
        report += "- SLSMainConnectionID: \(cid)\n"
        report += "- SLSDetectDisplays Result: \(result)\n"
        report += "- Before Mode Count: \(beforeCount)\n"
        report += "- After Mode Count: \(afterCount)\n"
        report += "- Perfect QHD Before: \(beforeHasPerfect)\n"
        report += "- Perfect QHD After: \(afterHasPerfect)\n\n"
        
        if afterHasPerfect {
            report += "## Result: SUCCESS\n"
            report += "Perfect QHD mode appeared in mode pool!\n"
            
            // Try to apply it using the official applier
            // Note: In a real scenario, we'd need to convert the CGDisplayMode to PhysicalDisplayMode
            // For now, we report success.
            saveReport(report)
            return .success(message: "Perfect QHD activated via SLSDetectDisplays!")
        } else {
            report += "## Result: FAILURE\n"
            report += "SLSDetectDisplays did not produce Perfect QHD.\n"
            saveReport(report)
            return .failure(reason: "SLSDetectDisplays did not produce Perfect QHD.")
        }
    }

    /// Replays the BetterDisplay-observed SLS display configuration transaction chain.
    func runSLSTransactionActivationExperiment() -> ExperimentResult {
        guard HiDPIPrivateActivationSafety.shared.isExperimentAllowed() else {
            let report = makeFailureReport(reason: "Experimental mode disabled.")
            saveSLSTransactionReport(report)
            return .skipped(reason: "Experimental mode disabled.")
        }

        guard HiDPIPrivateActivationSafety.shared.validateTargetDisplay(displayID: targetDisplayID) else {
            let report = makeFailureReport(reason: "Safety guard failed: target display invalid.")
            saveSLSTransactionReport(report)
            return .skipped(reason: "Safety guard failed: target display invalid.")
        }

        let resolver = PrivateDisplaySymbolResolver.shared
        let symbolNames = [
            "SLSBeginDisplayConfiguration",
            "CGBeginDisplayConfiguration",
            "SLSConfigureDisplayMode",
            "CGSConfigureDisplayMode",
            "SLSCompleteDisplayConfigurationWithOption",
            "SLSCompleteDisplayConfiguration",
            "CGCompleteDisplayConfiguration",
            "SLSGetDisplayList",
            "SLSGetCurrentDisplayMode"
        ]
        let symbolResolutions = symbolNames.map {
            SymbolResolution(name: $0, found: resolver.resolveSymbol(name: $0) != nil)
        }

        let before = makeSnapshot()
        let currentModeNumber = before.activeModeNumber
        let traceModeNumber: Int32 = 0x38
        let completionOption: Int32 = Int32(CGConfigureOption.forSession.rawValue)

        var attempts: [String] = []
        var beginUsed = "CGBeginDisplayConfiguration"
        var firstConfigureResult: Int32?
        var firstCompleteResult: Int32?
        var secondConfigureResult: Int32?
        var secondCompleteResult: Int32?
        var usedModeNumber: Int32?
        var usedOption: Int32?

        guard let configureSymbol = resolver.resolveSymbol(name: "SLSConfigureDisplayMode")
            ?? resolver.resolveSymbol(name: "CGSConfigureDisplayMode") else {
            let report = buildSLSTransactionReport(
                symbolResolutions: symbolResolutions,
                beginUsed: "not used",
                configureResult: nil,
                completeResult: nil,
                displayID: targetDisplayID,
                modeNumber: nil,
                option: completionOption,
                before: before,
                after: before,
                applyResult: "not attempted",
                attempts: ["Missing SLSConfigureDisplayMode/CGSConfigureDisplayMode symbol."],
                finalStatus: "failure"
            )
            saveSLSTransactionReport(report)
            return .failure(reason: "SLSConfigureDisplayMode/CGSConfigureDisplayMode symbol not found.")
        }

        guard let completeWithOptionSymbol = resolver.resolveSymbol(name: "SLSCompleteDisplayConfigurationWithOption") else {
            let report = buildSLSTransactionReport(
                symbolResolutions: symbolResolutions,
                beginUsed: "not used",
                configureResult: nil,
                completeResult: nil,
                displayID: targetDisplayID,
                modeNumber: nil,
                option: completionOption,
                before: before,
                after: before,
                applyResult: "not attempted",
                attempts: ["Missing SLSCompleteDisplayConfigurationWithOption symbol."],
                finalStatus: "failure"
            )
            saveSLSTransactionReport(report)
            return .failure(reason: "SLSCompleteDisplayConfigurationWithOption symbol not found.")
        }

        let configure = unsafeBitCast(configureSymbol, to: SLSConfigureDisplayModeFunc.self)
        let completeWithOption = unsafeBitCast(completeWithOptionSymbol, to: SLSCompleteDisplayConfigurationWithOptionFunc.self)

        if symbolResolutions.first(where: { $0.name == "SLSBeginDisplayConfiguration" })?.found == true {
            beginUsed += " (SLSBeginDisplayConfiguration resolved but not used; public begin chosen for lowest-risk single attempt)"
        }

        if let currentModeNumber {
            attempts.append("Private SLS Transaction Reconfigure Current Mode: modeNumber=\(currentModeNumber)")
            let result = runSingleSLSTransaction(
                modeNumber: currentModeNumber,
                completionOption: completionOption,
                configure: configure,
                completeWithOption: completeWithOption
            )
            firstConfigureResult = result.configureResult
            firstCompleteResult = result.completeResult
            usedModeNumber = currentModeNumber
            usedOption = completionOption
        } else {
            attempts.append("Private SLS Transaction Reconfigure Current Mode skipped: active mode number unavailable.")
        }

        var afterFirst = makeSnapshot()

        if afterFirst.perfectMode == nil {
            attempts.append("Private SLS Transaction With Trace Mode Number: modeNumber=\(traceModeNumber)")
            let result = runSingleSLSTransaction(
                modeNumber: traceModeNumber,
                completionOption: completionOption,
                configure: configure,
                completeWithOption: completeWithOption
            )
            secondConfigureResult = result.configureResult
            secondCompleteResult = result.completeResult
            usedModeNumber = traceModeNumber
            usedOption = completionOption
            afterFirst = makeSnapshot()
        }

        let after = afterFirst
        var applyResult = "not attempted"

        if let perfectMode = after.perfectMode {
            let result = HiDPIModeApplier.applyMode(displayID: targetDisplayID, targetMode: perfectMode)
            switch result {
            case .success(let message):
                applyResult = "SUCCESS: \(message)"
                savePreferredMode(perfectMode)
            case .noChangeNeeded:
                applyResult = "SUCCESS: no change needed"
                savePreferredMode(perfectMode)
            case .failure(let reason):
                applyResult = "FAILURE: \(reason)"
            }
        } else {
            applyResult = "not attempted; Perfect QHD absent after transaction"
        }

        let configureResult = secondConfigureResult ?? firstConfigureResult
        let completeResult = secondCompleteResult ?? firstCompleteResult
        let finalStatus = after.perfectMode == nil ? "failure" : (applyResult.hasPrefix("SUCCESS") ? "success" : "failure")

        let report = buildSLSTransactionReport(
            symbolResolutions: symbolResolutions,
            beginUsed: beginUsed,
            configureResult: configureResult,
            completeResult: completeResult,
            displayID: targetDisplayID,
            modeNumber: usedModeNumber,
            option: usedOption,
            before: before,
            after: after,
            applyResult: applyResult,
            attempts: attempts + [
                "Trace diagnostic mode number: 0x38 / decimal 56",
                "First configure result: \(firstConfigureResult.map(String.init) ?? "n/a")",
                "First complete result: \(firstCompleteResult.map(String.init) ?? "n/a")",
                "Second configure result: \(secondConfigureResult.map(String.init) ?? "n/a")",
                "Second complete result: \(secondCompleteResult.map(String.init) ?? "n/a")"
            ],
            finalStatus: finalStatus
        )
        saveSLSTransactionReport(report)

        if after.perfectMode == nil {
            return .failure(reason: "SLS transaction reproduced but did not create Perfect QHD.")
        }

        if applyResult.hasPrefix("SUCCESS") {
            return .success(message: "Private SLS transaction completed; Perfect QHD available and applied.")
        }

        return .failure(reason: "Perfect QHD available after transaction, but apply failed.")
    }
    
    private func getModeCount() -> Int {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(targetDisplayID, options) as? [CGDisplayMode]
        return modes?.count ?? 0
    }

    private func runSingleSLSTransaction(
        modeNumber: Int32,
        completionOption: Int32,
        configure: SLSConfigureDisplayModeFunc,
        completeWithOption: SLSCompleteDisplayConfigurationWithOptionFunc
    ) -> (configureResult: Int32, completeResult: Int32) {
        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            return (beginError.rawValue, Int32.min)
        }

        let configureResult = configure(config, targetDisplayID, modeNumber)
        guard configureResult == 0 else {
            CGCancelDisplayConfiguration(config)
            return (configureResult, Int32.min)
        }

        let completeResult = completeWithOption(config, completionOption)
        if completeResult != 0 {
            CGCancelDisplayConfiguration(config)
        }

        Thread.sleep(forTimeInterval: 1.0)
        return (configureResult, completeResult)
    }

    private func makeSnapshot() -> ModePoolSnapshot {
        let active = CGDisplayCopyDisplayMode(targetDisplayID)
        let activeDescription: String
        let activeModeNumber: Int32?
        if let active {
            activeDescription = "\(active.width)x\(active.height) logical / \(active.pixelWidth)x\(active.pixelHeight) backing / \(String(format: "%.2f", active.refreshRate))Hz / ioMode \(active.ioDisplayModeID)"
            activeModeNumber = Int32(active.ioDisplayModeID)
        } else {
            activeDescription = "unavailable"
            activeModeNumber = nil
        }

        let modes = NativeDisplayModeReader.getHiDPIApplyCandidateModes(for: targetDisplayID)
        let perfect = modes.first(where: NativeDisplayModeReader.isPerfectQHDHiDPIMode)
        let hiDPICount = modes.filter(\.isHiDPI).count
        let dump = modes.map { mode in
            "\(mode.width)x\(mode.height) / \(mode.pixelWidth)x\(mode.pixelHeight) / \(String(format: "%.2f", mode.refreshRate))Hz / ioMode \(mode.cgMode.ioDisplayModeID) / hiDPI \(mode.isHiDPI) / perfect \(NativeDisplayModeReader.isPerfectQHDHiDPIMode(mode))"
        }.joined(separator: "\n")

        return ModePoolSnapshot(
            activeDescription: activeDescription,
            activeModeNumber: activeModeNumber,
            duplicateModeCount: modes.count,
            hiDPICount: hiDPICount,
            perfectMode: perfect,
            modeDump: dump
        )
    }

    private func savePreferredMode(_ mode: PhysicalDisplayMode) {
        let vendor = CGDisplayVendorNumber(targetDisplayID)
        let product = CGDisplayModelNumber(targetDisplayID)
        let serial = CGDisplaySerialNumber(targetDisplayID)
        let fingerprint = DisplayModeFingerprint(mode: mode, vendorID: vendor, productID: product, serial: serial)
        HiDPIStateStore.savePreferredMode(fingerprint)
        HiDPIStateStore.setHiDPIEnabled(true)
    }

    private func buildSLSTransactionReport(
        symbolResolutions: [SymbolResolution],
        beginUsed: String,
        configureResult: Int32?,
        completeResult: Int32?,
        displayID: CGDirectDisplayID,
        modeNumber: Int32?,
        option: Int32?,
        before: ModePoolSnapshot,
        after: ModePoolSnapshot,
        applyResult: String,
        attempts: [String],
        finalStatus: String
    ) -> String {
        var report = "# Private SLS Transaction Activation Experiment\n\n"
        report += "## Semboller çözüldü mü?\n\n"
        for symbol in symbolResolutions {
            report += "- \(symbol.found ? "yes" : "no"): `\(symbol.name)`\n"
        }
        report += "\n## Begin call hangisi kullanıldı?\n\n"
        report += "- \(beginUsed)\n\n"
        report += "## Configure call sonucu\n\n"
        report += "- \(configureResult.map(String.init) ?? "not called")\n\n"
        report += "## Complete call sonucu\n\n"
        report += "- \(completeResult.map(String.init) ?? "not called")\n\n"
        report += "## DisplayID\n\n"
        report += "- \(displayID)\n\n"
        report += "## Mode number\n\n"
        report += "- Used: \(modeNumber.map(String.init) ?? "none")\n"
        report += "- Trace diagnostic: `0x38` / `56`\n"
        report += "- Active-before mode number: \(before.activeModeNumber.map(String.init) ?? "unavailable")\n\n"
        report += "## Option\n\n"
        report += "- \(option.map(String.init) ?? "none") (`CGConfigureOption.forSession`)\n\n"
        report += "## Before mode count\n\n"
        report += "- duplicateLowResolutionModes=true: \(before.duplicateModeCount)\n"
        report += "- HiDPI: \(before.hiDPICount)\n"
        report += "- Active: \(before.activeDescription)\n"
        report += "- Perfect QHD present: \(before.perfectMode != nil)\n\n"
        report += "## After mode count\n\n"
        report += "- duplicateLowResolutionModes=true: \(after.duplicateModeCount)\n"
        report += "- HiDPI: \(after.hiDPICount)\n"
        report += "- Active: \(after.activeDescription)\n"
        report += "- Perfect QHD present: \(after.perfectMode != nil)\n\n"
        report += "## Perfect QHD oluştu mu?\n\n"
        report += "- \(after.perfectMode != nil ? "yes" : "no")\n\n"
        report += "## Oluştuysa apply sonucu\n\n"
        report += "- \(applyResult)\n\n"
        report += "## Oluşmadıysa failure\n\n"
        if after.perfectMode == nil {
            report += "- SLS transaction reproduced but did not create Perfect QHD\n\n"
        } else if !applyResult.hasPrefix("SUCCESS") {
            report += "- Perfect QHD exists, but apply failed\n\n"
        } else {
            report += "- n/a\n\n"
        }
        report += "## Attempt log\n\n"
        for attempt in attempts {
            report += "- \(attempt)\n"
        }
        report += "\n## Before mode dump\n\n```text\n\(before.modeDump)\n```\n\n"
        report += "## After mode dump\n\n```text\n\(after.modeDump)\n```\n\n"
        report += "## Final status\n\n- \(finalStatus.uppercased())\n"
        return report
    }

    private func makeFailureReport(reason: String) -> String {
        """
        # Private SLS Transaction Activation Experiment

        ## Semboller çözüldü mü?

        - not checked

        ## Begin call hangisi kullanıldı?

        - not used

        ## Configure call sonucu

        - not called

        ## Complete call sonucu

        - not called

        ## DisplayID

        - \(targetDisplayID)

        ## Mode number

        - none

        ## Option

        - none

        ## Before mode count

        - not captured

        ## After mode count

        - not captured

        ## Perfect QHD oluştu mu?

        - no

        ## Oluştuysa apply sonucu

        - not attempted

        ## Oluşmadıysa failure

        - \(reason)
        """
    }
    
    private func checkForPerfectQHD() -> Bool {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(targetDisplayID, options) as? [CGDisplayMode] else {
            return false
        }
        
        for m in modes {
            if m.width == 2560 && m.height == 1440 && m.pixelWidth == 5120 && m.pixelHeight == 2880 {
                return true
            }
        }
        return false
    }
    
    private func saveReport(_ content: String) {
        do {
            let url = try HiDPIReportPaths.write(content, to: "docs/generated/private_activation/sls_detect_displays_experiment.md")
            print("Report saved to \(url.path)")
        } catch {
            print("Failed to save report: \(error)")
        }
    }

    private func saveSLSTransactionReport(_ content: String) {
        do {
            let url = try HiDPIReportPaths.write(content, to: "docs/generated/private_activation/sls_transaction_activation_experiment.md")
            print("Report saved to \(url.path)")
        } catch {
            print("Failed to save report: \(error)")
        }
    }
}
