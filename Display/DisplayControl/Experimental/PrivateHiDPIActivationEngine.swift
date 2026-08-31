import Foundation
import CoreGraphics

/// Main coordinator for private HiDPI activation experiments.
@MainActor
class PrivateHiDPIActivationEngine {
    static let shared = PrivateHiDPIActivationEngine()
    
    private init() {}
    
    /// Finds the target Samsung monitor.
    private func getTargetDisplay() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 10)
        
        let error = CGGetActiveDisplayList(10, &activeDisplays, &displayCount)
        if error != .success {
            return nil
        }
        
        for i in 0..<Int(displayCount) {
            let displayID = activeDisplays[i]
            if HiDPIPrivateActivationSafety.shared.isTargetSamsungMonitor(displayID: displayID) {
                return displayID
            }
        }
        
        return nil
    }
    
    /// Runs the symbol discovery and saves it to a report.
    func scanPrivateDisplaySymbols() {
        print("Starting private symbol scan...")
        let report = PrivateDisplaySymbolResolver.shared.runDiscovery()
        
        do {
            let url = try HiDPIReportPaths.write(report, to: "docs/generated/private_activation/symbol_scan_report.md")
            print("Report saved to \(url.path)")
        } catch {
            print("Failed to save report: \(error)")
        }
    }
    
    /// Runs a specific experiment.
    func runExperiment(id: String) {
        guard getTargetDisplay() != nil else {
            print("Target display not found. Aborting experiment.")
            return
        }
        
        print("\n--- Starting Experiment \(id) ---")
        
        let result: PrivateActivationExperiment.ExperimentResult
        
        switch id {
        case "SLS_DETECT":
            result = .skipped(reason: "SLSDetectDisplays is marked failed and is disabled as an activation candidate.")
        default:
            print("Unknown experiment ID.")
            return
        }
        
        switch result {
        case .success(let message):
            print("✅ Success: \(message)")
        case .failure(let reason):
            print("❌ Failure: \(reason)")
        case .skipped(let reason):
            print("⚠️ Skipped: \(reason)")
        }
        
        print("--- Experiment \(id) Complete ---\n")
    }

    func runSLSTransactionActivationExperiment() -> String {
        guard let targetDisplayID = getTargetDisplay() else {
            let message = "Target display not found. Aborting SLS transaction experiment."
            print(message)
            return message
        }

        let experiment = PrivateActivationExperiment(targetDisplayID: targetDisplayID)
        let result = experiment.runSLSTransactionActivationExperiment()

        switch result {
        case .success(let message):
            print("✅ Success: \(message)")
            return "SUCCESS: \(message)"
        case .failure(let reason):
            print("❌ Failure: \(reason)")
            return "FAILURE: \(reason)"
        case .skipped(let reason):
            print("⚠️ Skipped: \(reason)")
            return "SKIPPED: \(reason)"
        }
    }
}
