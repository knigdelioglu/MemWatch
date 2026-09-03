import CoreGraphics
import Foundation
import Darwin

struct CGSDisplayModeCandidate: Identifiable, Equatable {
    let modeID: Int32
    let ioMode: Int32
    let logicalWidth: Int
    let logicalHeight: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let flags: UInt32
    let ioFlags: UInt32
    let isHiDPI: Bool
    let isLowRes: Bool
    let scaleFactor: Double
    let aspectRatio: Double
    let score: Int
    let reason: String

    var id: Int32 { modeID }
}

struct CGSDynamicModeSelectionState: Equatable {
    let currentModeID: Int32?
    let currentModeText: String
    let modeCount: Int
    let publicDuplicateModeCount: Int
    let dynamicHiDPICandidate: CGSDisplayModeCandidate?
    let dynamicNormalCandidate: CGSDisplayModeCandidate?
    let samsungFallbackUsed: Bool
    let samsungFallbackCandidate: CGSDisplayModeCandidate?
}

struct CGSActiveModeFingerprint: Equatable {
    let modeID: Int32?
    let logicalWidth: Int
    let logicalHeight: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRateHz: Double

    var description: String {
        let modeText = modeID.map(String.init) ?? "unavailable"
        return "\(modeText) | \(logicalWidth)x\(logicalHeight) / \(pixelWidth)x\(pixelHeight) / \(String(format: "%.2f", refreshRateHz))Hz"
    }
}

struct CGSModeSwitcherStatus {
    let displayID: CGDirectDisplayID?
    let isSamsungFingerprintMatched: Bool
    let isBuiltin: Bool
    let currentModeID: Int32?
    let cgsModeCount: Int
    let activeFingerprint: CGSActiveModeFingerprint?
    let mode56: CGSModeEnumerationEntry?
    let mode74: CGSModeEnumerationEntry?
    let lastRefreshDate: Date

    var currentModeText: String {
        guard isSamsungFingerprintMatched, !isBuiltin else {
            return "Current CGS Mode: unavailable"
        }

        if let activeFingerprint {
            return "Current CGS Mode: \(activeFingerprint.description)"
        }
        return "Current CGS Mode: unavailable"
    }

    var friendlyCurrentModeText: String {
        guard isSamsungFingerprintMatched, !isBuiltin else {
            return "Mevcut Mod: bilinmiyor"
        }

        guard let activeFingerprint else {
            return "Mevcut Mod: bilinmiyor"
        }

        if activeFingerprint.logicalWidth == 2560 &&
            activeFingerprint.logicalHeight == 1440 &&
            activeFingerprint.pixelWidth == 5120 &&
            activeFingerprint.pixelHeight == 2880 &&
            abs(activeFingerprint.refreshRateHz - 100.0) < 0.1 {
            return "Mevcut Mod: 2560x1440 / 5120x2880 @100Hz"
        }

        if activeFingerprint.logicalWidth == 2560 &&
            activeFingerprint.logicalHeight == 1440 &&
            activeFingerprint.pixelWidth == 2560 &&
            activeFingerprint.pixelHeight == 1440 &&
            abs(activeFingerprint.refreshRateHz - 100.0) < 0.1 {
            return "Mevcut Mod: 2560x1440 / 2560x1440 @100Hz"
        }

        return String(format: "Mevcut Mod: %dx%d / %dx%d @ %.0fHz", activeFingerprint.logicalWidth, activeFingerprint.logicalHeight, activeFingerprint.pixelWidth, activeFingerprint.pixelHeight, activeFingerprint.refreshRateHz)
    }

    var hasMode56: Bool { mode56 != nil }
    var hasMode74: Bool { mode74 != nil }

    var canApplyMode56: Bool {
        isSamsungFingerprintMatched &&
            !isBuiltin &&
            mode56?.width == 2560 &&
            mode56?.height == 1440 &&
            mode56?.pixelWidth == 2560 &&
            mode56?.pixelHeight == 1440 &&
            abs((mode56?.refreshRateHz ?? 0) - 100.0) < 0.1 &&
            mode56?.isHiDPI == false
    }

    var canApplyMode74: Bool {
        isSamsungFingerprintMatched && !isBuiltin && mode74?.isPerfectQHD == true
    }
}

struct CGSManualModeSwitchReport {
    let requestedModeID: Int
    let beforeModeID: Int32?
    let afterModeID: Int32?
    let beforeFingerprint: CGSActiveModeFingerprint?
    let afterFingerprint: CGSActiveModeFingerprint?
    let configureResult: String
    let completeResult: String
    let success: Bool
    let rollbackAttempted: Bool
    let rollbackResult: String?
    let failureReason: String?
    let reportURL: URL
}

@MainActor
final class CGSModeSwitcher {
    private typealias CGSGetCurrentDisplayModeFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias CGSGetNumberOfDisplayModesFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias CGSGetDisplayModeDescriptionOfLengthFunc = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> CGError
    private typealias CGSConfigureDisplayModeFunc = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Int32) -> Int32

    private static let reportPath = "docs/generated/private_activation/cgs_manual_mode_switch.md"
    private static let dynamicReportPath = "docs/generated/private_activation/cgs_dynamic_mode_selection.md"
    private static let expectedVendorID: UInt32 = 0x4C2D
    private static let expectedProductID: UInt32 = 0x76AB
    private static let expectedSerial: UInt32 = 0x30413332
    private static let targetLogicalWidth = 2560
    private static let targetLogicalHeight = 1440
    private static let targetBackingWidth = 5120
    private static let targetBackingHeight = 2880
    private static let targetRefreshRate = 100.0

    private var cachedStatus: CGSModeSwitcherStatus?
    private var cachedDisplayID: CGDirectDisplayID?
    private var cachedCandidates: [CGSDisplayModeCandidate] = []
    private var cachedSelectionState: CGSDynamicModeSelectionState?
    private let operationGate: DisplayPowerOperationGate
    private let targetOperationGate: TargetDisplayOperationGate

    init(
        operationGate: DisplayPowerOperationGate = .shared,
        targetOperationGate: TargetDisplayOperationGate = .shared
    ) {
        self.operationGate = operationGate
        self.targetOperationGate = targetOperationGate
    }

    func refreshCGSModes(displayID: CGDirectDisplayID) -> CGSModeSwitcherStatus {
        let targetSnapshot = targetOperationGate.snapshot()
        guard operationGate.isAllowed(),
              targetOperationGate.accepts(targetSnapshot.generation, displayID: displayID),
              isSamsungTargetIdentity(displayID) else {
            return unavailableStatus(displayID: displayID)
        }
        cachedDisplayID = displayID

        let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
        let vendorID = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        let isSamsungFingerprintMatched = !isBuiltin &&
            vendorID == Self.expectedVendorID &&
            productID == Self.expectedProductID &&
            serial == Self.expectedSerial

        guard isSamsungFingerprintMatched else {
            let status = CGSModeSwitcherStatus(
                displayID: displayID,
                isSamsungFingerprintMatched: false,
                isBuiltin: isBuiltin,
                currentModeID: nil,
                cgsModeCount: 0,
                activeFingerprint: nil,
                mode56: nil,
                mode74: nil,
                lastRefreshDate: Date()
            )
            cachedStatus = status
            return status
        }

        let summary = CGSModeEnumerationDiagnostic.collectSummary(
            reportPath: Self.reportPath,
            reportTitle: "CGS Manual Mode Switch"
        )

        guard targetOperationGate.accepts(targetSnapshot.generation, displayID: displayID),
              isDisplayOnlineAndActive(displayID) else {
            return unavailableStatus(displayID: displayID)
        }

        guard summary.targetDisplay?.displayID == displayID else {
            let status = CGSModeSwitcherStatus(
                displayID: displayID,
                isSamsungFingerprintMatched: true,
                isBuiltin: false,
                currentModeID: readCurrentCGSMode(displayID: displayID),
                cgsModeCount: summary.cgsModeCount,
                activeFingerprint: readActiveModeFingerprint(displayID: displayID),
                mode56: nil,
                mode74: nil,
                lastRefreshDate: Date()
            )
            cachedStatus = status
            return status
        }

        let status = CGSModeSwitcherStatus(
            displayID: displayID,
            isSamsungFingerprintMatched: true,
            isBuiltin: false,
            currentModeID: summary.currentModeID,
            cgsModeCount: summary.cgsModeCount,
            activeFingerprint: readActiveModeFingerprint(displayID: displayID),
            mode56: summary.mode56,
            mode74: summary.mode74,
            lastRefreshDate: Date()
        )
        cachedStatus = status
        return status
    }

    func scanCGSModes(displayID: CGDirectDisplayID) -> [CGSDisplayModeCandidate] {
        let targetSnapshot = targetOperationGate.snapshot()
        guard operationGate.isAllowed(),
              targetOperationGate.accepts(targetSnapshot.generation, displayID: displayID),
              isSamsungTargetIdentity(displayID) else {
            cachedCandidates = []
            cachedSelectionState = nil
            return []
        }
        cachedDisplayID = displayID
        let modeCount = resolveModeCount(displayID: displayID)
        guard modeCount > 0, let descriptionSymbol = resolveFirstSymbol(["CGSGetDisplayModeDescriptionOfLength", "SLSGetDisplayModeDescriptionOfLength"]) else {
            cachedCandidates = []
            cachedSelectionState = buildSelectionState(
                displayID: displayID,
                modeCount: 0,
                candidates: [],
                publicDuplicateModeCount: 0
            )
            return []
        }

        let description = unsafeBitCast(descriptionSymbol.pointer, to: CGSGetDisplayModeDescriptionOfLengthFunc.self)
        let publicModes = NativeDisplayModeReader.getHiDPIApplyCandidateModes(for: displayID)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 212, alignment: MemoryLayout<Int32>.alignment)
        defer { buffer.deallocate() }

        var candidates: [CGSDisplayModeCandidate] = []
        candidates.reserveCapacity(modeCount)

        for index in 0..<modeCount {
            memset(buffer, 0, 212)
            let result = description(displayID, Int32(index), buffer, 212)
            guard result == .success else { continue }

            let modeID = readInt32(buffer, 0)
            let flags = readUInt32(buffer, 4)
            let logicalWidth = Int(readInt32(buffer, 8))
            let logicalHeight = Int(readInt32(buffer, 12))
            let refreshRaw = readInt32(buffer, 188)
            let fallbackRefreshRaw = readInt32(buffer, 36)
            let refreshRate = decodeRefreshHz(rawRefresh: refreshRaw, fallbackRaw: fallbackRefreshRaw)
            let ioFlags = readUInt32(buffer, 192)
            let ioMode = readInt32(buffer, 196)
            let pixelWidth = Int(readInt32(buffer, 200))
            let pixelHeight = Int(readInt32(buffer, 204))
            let isHiDPI = pixelWidth > logicalWidth || pixelHeight > logicalHeight
            let isLowRes = !isHiDPI
            let scaleFactor = logicalWidth > 0 ? Double(pixelWidth) / Double(logicalWidth) : 0
            let aspectRatio = logicalHeight > 0 ? Double(logicalWidth) / Double(logicalHeight) : 0
            let reason = dynamicReason(
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                refreshRate: refreshRate,
                isHiDPI: isHiDPI,
                isLowRes: isLowRes,
                scaleFactor: scaleFactor,
                aspectRatio: aspectRatio
            ) + publicMatchSuffix(
                modeID: modeID,
                ioMode: ioMode,
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                refreshRate: refreshRate,
                publicModes: publicModes
            )
            let score = dynamicScore(
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                refreshRate: refreshRate,
                isHiDPI: isHiDPI,
                isLowRes: isLowRes,
                scaleFactor: scaleFactor,
                aspectRatio: aspectRatio
            )
            candidates.append(
                CGSDisplayModeCandidate(
                    modeID: modeID,
                    ioMode: ioMode,
                    logicalWidth: logicalWidth,
                    logicalHeight: logicalHeight,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    refreshRate: refreshRate,
                    flags: flags,
                    ioFlags: ioFlags,
                    isHiDPI: isHiDPI,
                    isLowRes: isLowRes,
                    scaleFactor: scaleFactor,
                    aspectRatio: aspectRatio,
                    score: score,
                    reason: reason
                )
            )
        }
        cachedCandidates = candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI && !rhs.isHiDPI }
            if lhs.pixelWidth != rhs.pixelWidth { return lhs.pixelWidth > rhs.pixelWidth }
            return lhs.modeID < rhs.modeID
        }
        cachedSelectionState = buildSelectionState(
            displayID: displayID,
            modeCount: modeCount,
            candidates: cachedCandidates,
            publicDuplicateModeCount: publicModes.count
        )
        return cachedCandidates
    }

    func findBestHiDPIMode(
        targetLogicalWidth: Int,
        targetLogicalHeight: Int,
        targetPixelWidth: Int,
        targetPixelHeight: Int,
        preferredRefreshRate: Double
    ) -> CGSDisplayModeCandidate? {
        let candidates = cachedCandidates.isEmpty ? scanCGSModes(displayID: cachedDisplayID ?? 0) : cachedCandidates
        let hiCandidates = candidates.filter { $0.isHiDPI }
        let exactMatches = hiCandidates.filter {
            $0.logicalWidth == targetLogicalWidth &&
            $0.logicalHeight == targetLogicalHeight &&
            $0.pixelWidth == targetPixelWidth &&
            $0.pixelHeight == targetPixelHeight &&
            abs($0.refreshRate - preferredRefreshRate) < 0.1
        }
        let best = exactMatches.max(by: { $0.score < $1.score }) ?? hiCandidates.max(by: { $0.score < $1.score })
        guard let best else { return nil }
        guard best.score >= 1700 else { return nil }
        return best
    }

    func findBestNormalMode(
        targetLogicalWidth: Int,
        targetLogicalHeight: Int,
        preferredRefreshRate: Double
    ) -> CGSDisplayModeCandidate? {
        let candidates = cachedCandidates.isEmpty ? scanCGSModes(displayID: cachedDisplayID ?? 0) : cachedCandidates
        let normalCandidates = candidates.filter { !$0.isHiDPI }
        let exactMatches = normalCandidates.filter {
            $0.logicalWidth == targetLogicalWidth &&
            $0.logicalHeight == targetLogicalHeight &&
            $0.pixelWidth == targetLogicalWidth &&
            $0.pixelHeight == targetLogicalHeight &&
            abs($0.refreshRate - preferredRefreshRate) < 0.1
        }
        let best = exactMatches.max(by: { $0.score < $1.score }) ?? normalCandidates.max(by: { $0.score < $1.score })
        guard let best else { return nil }
        guard best.score >= 1100 else { return nil }
        return best
    }

    func verifiedSamsungFallbackCandidate(
        modeID: Int,
        targetLogicalWidth: Int,
        targetLogicalHeight: Int,
        targetPixelWidth: Int,
        targetPixelHeight: Int,
        preferredRefreshRate: Double,
        expectedHiDPI: Bool
    ) -> CGSDisplayModeCandidate? {
        let candidates = cachedCandidates.isEmpty ? scanCGSModes(displayID: cachedDisplayID ?? 0) : cachedCandidates
        guard let candidate = candidates.first(where: { Int($0.modeID) == modeID || Int($0.ioMode) == modeID }) else {
            return nil
        }
        guard candidate.logicalWidth == targetLogicalWidth,
              candidate.logicalHeight == targetLogicalHeight,
              candidate.pixelWidth == targetPixelWidth,
              candidate.pixelHeight == targetPixelHeight,
              abs(candidate.refreshRate - preferredRefreshRate) < 0.1,
              candidate.isHiDPI == expectedHiDPI else {
            return nil
        }
        return candidate
    }

    func currentDynamicSelectionState() -> CGSDynamicModeSelectionState? {
        cachedSelectionState
    }

    func writeDynamicModeSelectionReport(
        displayID: CGDirectDisplayID,
        selectedHiDPI: CGSDisplayModeCandidate?,
        selectedNormal: CGSDisplayModeCandidate?,
        samsungFallbackUsed: Bool
    ) -> URL? {
        let candidates = scanCGSModes(displayID: displayID)
        let selectedHiDPIText = selectedHiDPI.map(candidateText) ?? "unavailable"
        let selectedNormalText = selectedNormal.map(candidateText) ?? "unavailable"
        let dynamicHiDPIText = candidates.first(where: { $0.isHiDPI }).map(candidateText) ?? "unavailable"
        let dynamicNormalText = candidates.first(where: { !$0.isHiDPI }).map(candidateText) ?? "unavailable"
        let fallbackText = samsungFallbackUsed ? "YES" : "NO"

        var lines: [String] = []
        lines.append("# CGS Dynamic Mode Selection")
        lines.append("")
        lines.append("## Display fingerprint")
        lines.append(displayFingerprintText(displayID: displayID))
        lines.append("")
        lines.append("## CGS mode count")
        lines.append("- \(cachedSelectionState?.modeCount ?? candidates.count)")
        lines.append("")
        lines.append("## Dynamic normal candidate")
        lines.append("- \(dynamicNormalText)")
        lines.append("")
        lines.append("## Dynamic HiDPI candidate")
        lines.append("- \(dynamicHiDPIText)")
        lines.append("")
        lines.append("## Samsung fallback candidate")
        lines.append("- \(fallbackText)")
        lines.append("")
        lines.append("## Selected HiDPI mode")
        lines.append("- \(selectedHiDPIText)")
        lines.append("")
        lines.append("## Selected normal mode")
        lines.append("- \(selectedNormalText)")
        lines.append("")
        lines.append("## Final decision")
        lines.append("- \(selectedHiDPI != nil || selectedNormal != nil ? "mode available" : "no suitable mode")")
        lines.append("")
        lines.append("## Candidate dump")
        for candidate in candidates {
            lines.append("- \(candidateText(candidate)) | score=\(candidate.score) | reason=\(candidate.reason)")
        }
        do {
            let url = HiDPIReportPaths.reportURL(Self.dynamicReportPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    func findMode56() -> CGSModeEnumerationEntry? {
        cachedStatus?.mode56
    }

    func findMode74() -> CGSModeEnumerationEntry? {
        cachedStatus?.mode74
    }

    func readCurrentCGSMode() -> Int32? {
        guard operationGate.isAllowed(),
              let targetDisplayID = targetOperationGate.snapshot().displayID,
              cachedDisplayID == nil || cachedDisplayID == targetDisplayID,
              isSamsungTargetIdentity(targetDisplayID) else { return nil }
        let displayID = targetDisplayID
        return readCurrentCGSMode(displayID: displayID)
    }

    func readActiveModeFingerprint() -> CGSActiveModeFingerprint? {
        guard operationGate.isAllowed(),
              let targetDisplayID = targetOperationGate.snapshot().displayID,
              cachedDisplayID == nil || cachedDisplayID == targetDisplayID,
              isSamsungTargetIdentity(targetDisplayID) else { return nil }
        let displayID = targetDisplayID
        return readActiveModeFingerprint(displayID: displayID)
    }

    func applyCGSMode(modeID: Int) async -> CGSManualModeSwitchReport {
        let reportURL = HiDPIReportPaths.reportURL(Self.reportPath)
        let operationGeneration = operationGate.currentGeneration()
        let targetSnapshot = targetOperationGate.snapshot()
        let targetOperationGeneration = targetSnapshot.generation

        guard operationGate.accepts(operationGeneration),
              let targetDisplayID = targetSnapshot.displayID,
              targetOperationGate.accepts(targetOperationGeneration, displayID: targetDisplayID),
              isSamsungTargetIdentity(targetDisplayID) else {
            let report = unavailableApplyReport(
                modeID: modeID,
                reportURL: reportURL,
                reason: "Display runtime suspended; CGS mode apply not attempted."
            )
            _ = try? writeReport(report)
            return report
        }

        let target = resolveExactSamsungDisplay()

        guard let target,
              target.displayID == targetDisplayID,
              target.isOnline,
              target.isActive,
              targetOperationGate.accepts(targetOperationGeneration, displayID: targetDisplayID) else {
            let report = CGSManualModeSwitchReport(
                requestedModeID: modeID,
                beforeModeID: nil,
                afterModeID: nil,
                beforeFingerprint: nil,
                afterFingerprint: nil,
                configureResult: "Samsung fingerprint mismatch, built-in, offline, or inactive display detected.",
                completeResult: "not attempted",
                success: false,
                rollbackAttempted: false,
                rollbackResult: nil,
                failureReason: "Samsung fingerprint mismatch, built-in, offline, or inactive display detected.",
                reportURL: reportURL
            )
            _ = try? writeReport(report)
            return report
        }

        let status = refreshCGSModes(displayID: target.displayID)
        guard operationGate.accepts(operationGeneration),
              targetOperationGate.accepts(targetOperationGeneration, displayID: targetDisplayID),
              status.isSamsungFingerprintMatched,
              !status.isBuiltin else {
            let report = CGSManualModeSwitchReport(
                requestedModeID: modeID,
                beforeModeID: nil,
                afterModeID: nil,
                beforeFingerprint: nil,
                afterFingerprint: nil,
                configureResult: "Samsung fingerprint mismatch or built-in display detected.",
                completeResult: "not attempted",
                success: false,
                rollbackAttempted: false,
                rollbackResult: nil,
                failureReason: "Samsung fingerprint mismatch or built-in display detected.",
                reportURL: reportURL
            )
            _ = try? writeReport(report)
            return report
        }

        guard let requestedMode = modeEntry(for: modeID) else {
            let report = CGSManualModeSwitchReport(
                requestedModeID: modeID,
                beforeModeID: status.currentModeID,
                afterModeID: status.currentModeID,
                beforeFingerprint: status.activeFingerprint,
                afterFingerprint: status.activeFingerprint,
                configureResult: "Requested mode \(modeID) not present in CGS list.",
                completeResult: "not attempted",
                success: false,
                rollbackAttempted: false,
                rollbackResult: nil,
                failureReason: "Requested mode \(modeID) not present in CGS list.",
                reportURL: reportURL
            )
            _ = try? writeReport(report)
            return report
        }

        let beforeModeID = readCurrentCGSMode(displayID: target.displayID)
        let beforeFingerprint = readActiveModeFingerprint(displayID: target.displayID)

        guard operationGate.accepts(operationGeneration),
              targetOperationGate.accepts(targetOperationGeneration, displayID: targetDisplayID),
              let beforeModeID else {
            let report = CGSManualModeSwitchReport(
                requestedModeID: modeID,
                beforeModeID: nil,
                afterModeID: nil,
                beforeFingerprint: beforeFingerprint,
                afterFingerprint: beforeFingerprint,
                configureResult: "Current CGS mode id could not be read.",
                completeResult: "not attempted",
                success: false,
                rollbackAttempted: false,
                rollbackResult: nil,
                failureReason: "Current CGS mode id could not be read.",
                reportURL: reportURL
            )
            _ = try? writeReport(report)
            return report
        }

        var configureResult = "not attempted"
        var completeResult = "not attempted"
        var rollbackAttempted = false
        var rollbackResult: String?
        var afterModeID: Int32? = beforeModeID
        var afterFingerprint: CGSActiveModeFingerprint? = beforeFingerprint
        var success = false
        var failureReason: String?

        await HiDPIReapplyService.shared.performWithoutReapplyInterventionAsync { [weak self] in
            guard let self else { return }
            configureResult = "not attempted"
            completeResult = "not attempted"

            guard self.operationGate.accepts(operationGeneration),
                  self.targetOperationGate.accepts(
                      targetOperationGeneration,
                      displayID: targetDisplayID
                  ),
                  self.isSamsungTargetIdentity(targetDisplayID) else {
                failureReason = "Display runtime generation changed before CGS mode apply."
                return
            }

            if beforeModeID == requestedMode.modeNumber || matches(requestedMode, fingerprint: beforeFingerprint) {
                configureResult = "Requested mode already active."
                completeResult = "skipped"
                afterModeID = readCurrentCGSMode(displayID: target.displayID)
                afterFingerprint = readActiveModeFingerprint(displayID: target.displayID)
                success = true
                return
            }

            guard self.operationGate.accepts(operationGeneration),
                  self.targetOperationGate.accepts(
                      targetOperationGeneration,
                      displayID: targetDisplayID
                  ),
                  self.isSamsungTargetIdentity(targetDisplayID) else {
                failureReason = "Samsung target changed before CGS configuration."
                return
            }

            var config: CGDisplayConfigRef?
            let beginResult = CGBeginDisplayConfiguration(&config)
            guard beginResult == .success, let config else {
                configureResult = "CGBeginDisplayConfiguration failed: \(beginResult.rawValue)"
                failureReason = configureResult
                return
            }

            let configure = resolveConfigureSymbol()
            guard let configure else {
                CGCancelDisplayConfiguration(config)
                configureResult = "CGSConfigureDisplayMode / SLSConfigureDisplayMode symbol not found."
                failureReason = configureResult
                return
            }

            guard self.operationGate.accepts(operationGeneration),
                  self.targetOperationGate.accepts(
                      targetOperationGeneration,
                      displayID: targetDisplayID
                  ),
                  self.isSamsungTargetIdentity(targetDisplayID) else {
                CGCancelDisplayConfiguration(config)
                failureReason = "Samsung target changed before CGS configure."
                return
            }

            let configureValue = configure(config, target.displayID, requestedMode.modeNumber)
            if configureValue != 0 {
                CGCancelDisplayConfiguration(config)
                configureResult = "CGSConfigureDisplayMode returned \(configureValue)"
                failureReason = configureResult
                return
            }

            configureResult = "CGSConfigureDisplayMode(\(requestedMode.modeNumber)) succeeded."

            guard self.operationGate.accepts(operationGeneration),
                  self.targetOperationGate.accepts(
                      targetOperationGeneration,
                      displayID: targetDisplayID
                  ),
                  self.isSamsungTargetIdentity(targetDisplayID) else {
                CGCancelDisplayConfiguration(config)
                failureReason = "Samsung target changed before CGS completion."
                return
            }

            let completeValue = CGCompleteDisplayConfiguration(config, .forSession)
            completeResult = "CGCompleteDisplayConfiguration(option: 2) returned \(completeValue.rawValue)"
            if completeValue != .success {
                CGCancelDisplayConfiguration(config)
                failureReason = completeResult
                rollbackAttempted = true
                rollbackResult = rollback(
                    to: beforeModeID,
                    displayID: target.displayID,
                    targetOperationGeneration: targetOperationGeneration
                )
                afterModeID = readCurrentCGSMode(displayID: target.displayID)
                afterFingerprint = readActiveModeFingerprint(displayID: target.displayID)
                return
            }

            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                failureReason = "CGS mode verification cancelled."
                return
            }
            guard !Task.isCancelled,
                  self.operationGate.accepts(operationGeneration),
                  self.targetOperationGate.accepts(
                      targetOperationGeneration,
                      displayID: targetDisplayID
                  ),
                  self.isSamsungTargetIdentity(targetDisplayID) else {
                failureReason = "Display runtime suspended during CGS mode verification."
                return
            }
            afterModeID = readCurrentCGSMode(displayID: target.displayID)
            afterFingerprint = readActiveModeFingerprint(displayID: target.displayID)

            if isSuccessfulSwitch(requestedModeID: modeID, afterModeID: afterModeID, afterFingerprint: afterFingerprint) {
                success = true
                return
            }

            failureReason = "Active CGS mode could not be verified after switch."
            rollbackAttempted = true
            rollbackResult = rollback(
                to: beforeModeID,
                displayID: target.displayID,
                targetOperationGeneration: targetOperationGeneration
            )
            afterModeID = readCurrentCGSMode(displayID: target.displayID)
            afterFingerprint = readActiveModeFingerprint(displayID: target.displayID)
        }

        let report = CGSManualModeSwitchReport(
            requestedModeID: modeID,
            beforeModeID: beforeModeID,
            afterModeID: afterModeID,
            beforeFingerprint: beforeFingerprint,
            afterFingerprint: afterFingerprint,
            configureResult: configureResult,
            completeResult: completeResult,
            success: success,
            rollbackAttempted: rollbackAttempted,
            rollbackResult: rollbackResult,
            failureReason: success ? nil : failureReason,
            reportURL: reportURL
        )
        _ = try? writeReport(report)
        if operationGate.accepts(operationGeneration),
           targetOperationGate.accepts(targetOperationGeneration, displayID: targetDisplayID) {
            cachedStatus = refreshCGSModes(displayID: target.displayID)
        }
        return report
    }

    private func resolveExactSamsungDisplay() -> TargetDisplayInfo? {
        guard let targetDisplayID = targetOperationGate.snapshot().displayID else {
            return nil
        }
        guard let display = try? HiDPITargetDisplayResolver.resolveTargets(spec: .samsungQHD, allowUnreadableSerial: false).first(where: {
            !$0.isBuiltin &&
                $0.vendorID == Self.expectedVendorID &&
                $0.productID == Self.expectedProductID &&
                $0.serialNumber == Self.expectedSerial &&
                $0.displayID == targetDisplayID
        }) else {
            return nil
        }
        return display
    }

    private func unavailableStatus(displayID: CGDirectDisplayID) -> CGSModeSwitcherStatus {
        CGSModeSwitcherStatus(
            displayID: displayID,
            isSamsungFingerprintMatched: false,
            isBuiltin: false,
            currentModeID: nil,
            cgsModeCount: 0,
            activeFingerprint: nil,
            mode56: nil,
            mode74: nil,
            lastRefreshDate: Date()
        )
    }

    private func isDisplayOnlineAndActive(_ displayID: CGDirectDisplayID) -> Bool {
        displayID != 0 &&
            CGDisplayIsOnline(displayID) != 0 &&
            CGDisplayIsActive(displayID) != 0
    }

    private func isSamsungTargetIdentity(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(displayID) == 0 &&
            CGDisplayVendorNumber(displayID) == Self.expectedVendorID &&
            CGDisplayModelNumber(displayID) == Self.expectedProductID &&
            CGDisplaySerialNumber(displayID) == Self.expectedSerial &&
            isDisplayOnlineAndActive(displayID)
    }

    private func unavailableApplyReport(
        modeID: Int,
        reportURL: URL,
        reason: String
    ) -> CGSManualModeSwitchReport {
        CGSManualModeSwitchReport(
            requestedModeID: modeID,
            beforeModeID: nil,
            afterModeID: nil,
            beforeFingerprint: nil,
            afterFingerprint: nil,
            configureResult: reason,
            completeResult: "not attempted",
            success: false,
            rollbackAttempted: false,
            rollbackResult: nil,
            failureReason: reason,
            reportURL: reportURL
        )
    }

    private func buildSelectionState(
        displayID: CGDirectDisplayID,
        modeCount: Int,
        candidates: [CGSDisplayModeCandidate],
        publicDuplicateModeCount: Int
    ) -> CGSDynamicModeSelectionState {
        let currentModeID = readCurrentCGSMode(displayID: displayID)
        let currentFingerprint = readActiveModeFingerprint(displayID: displayID)
        let currentText = currentFingerprint.map { "Current CGS Mode: \($0.description)" } ?? "Current CGS Mode: unavailable"
        let hiDPI = candidates.first(where: { $0.isHiDPI })
        let normal = candidates.first(where: { !$0.isHiDPI })
        return CGSDynamicModeSelectionState(
            currentModeID: currentModeID,
            currentModeText: currentText,
            modeCount: modeCount,
            publicDuplicateModeCount: publicDuplicateModeCount,
            dynamicHiDPICandidate: hiDPI,
            dynamicNormalCandidate: normal,
            samsungFallbackUsed: false,
            samsungFallbackCandidate: nil
        )
    }

    private func dynamicReason(
        logicalWidth: Int,
        logicalHeight: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        isHiDPI: Bool,
        isLowRes: Bool,
        scaleFactor: Double,
        aspectRatio: Double
    ) -> String {
        var reasons: [String] = []
        if logicalWidth == Self.targetLogicalWidth && logicalHeight == Self.targetLogicalHeight {
            reasons.append("logical-match")
        }
        if pixelWidth == Self.targetBackingWidth && pixelHeight == Self.targetBackingHeight {
            reasons.append("backing-match")
        }
        if isHiDPI { reasons.append("hidpi") }
        if abs(refreshRate - Self.targetRefreshRate) < 0.1 { reasons.append("100hz") }
        if abs(scaleFactor - 2.0) < 0.05 { reasons.append("scale-2x") }
        if abs(aspectRatio - (16.0 / 9.0)) < 0.01 { reasons.append("16:9") }
        if isLowRes { reasons.append("lowres") }
        if pixelWidth == logicalWidth && pixelHeight == logicalHeight { reasons.append("pixel-equals-logical") }
        return reasons.joined(separator: ",")
    }

    private func dynamicScore(
        logicalWidth: Int,
        logicalHeight: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        isHiDPI: Bool,
        isLowRes: Bool,
        scaleFactor: Double,
        aspectRatio: Double
    ) -> Int {
        var score = 0
        if logicalWidth == Self.targetLogicalWidth && logicalHeight == Self.targetLogicalHeight {
            score += 1000
        }
        if pixelWidth == Self.targetBackingWidth && pixelHeight == Self.targetBackingHeight {
            score += 1000
        }
        if isHiDPI {
            score += 500
        }
        if abs(refreshRate - Self.targetRefreshRate) < 0.1 {
            score += 300
        }
        if abs(scaleFactor - 2.0) < 0.05 {
            score += 200
        }
        if abs(aspectRatio - (16.0 / 9.0)) < 0.01 {
            score += 100
        }
        if isLowRes {
            score -= 1000
        }
        if pixelWidth == logicalWidth && pixelHeight == logicalHeight {
            score -= 500
        }
        return score
    }

    private func publicMatchSuffix(
        modeID: Int32,
        ioMode: Int32,
        logicalWidth: Int,
        logicalHeight: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        publicModes: [PhysicalDisplayMode]
    ) -> String {
        guard let match = publicModes.first(where: {
            Int32($0.cgMode.ioDisplayModeID) == modeID || Int32($0.cgMode.ioDisplayModeID) == ioMode ||
            ($0.width == logicalWidth && $0.height == logicalHeight && $0.pixelWidth == pixelWidth && $0.pixelHeight == pixelHeight && abs($0.refreshRate - refreshRate) < 0.1)
        }) else {
            return ""
        }
        return " | public:\(match.modeSource)"
    }

    private func candidateText(_ candidate: CGSDisplayModeCandidate) -> String {
        "\(candidate.modeID) | \(candidate.logicalWidth)x\(candidate.logicalHeight) / \(candidate.pixelWidth)x\(candidate.pixelHeight) / \(String(format: "%.0f", candidate.refreshRate))Hz"
    }

    private func displayFingerprintText(displayID: CGDirectDisplayID) -> String {
        let vendor = CGDisplayVendorNumber(displayID)
        let product = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        return String(format: "- Vendor 0x%04X | Product 0x%04X | Serial 0x%08X", vendor, product, serial)
    }

    private func resolveModeCount(displayID: CGDirectDisplayID) -> Int {
        guard displayID != 0, let symbol = resolveFirstSymbol(["CGSGetNumberOfDisplayModes", "SLSGetNumberOfDisplayModes"]) else {
            return 0
        }
        let function = unsafeBitCast(symbol.pointer, to: CGSGetNumberOfDisplayModesFunc.self)
        var count: Int32 = 0
        let result = function(displayID, &count)
        return result == .success ? Int(count) : 0
    }

    private func readInt32(_ pointer: UnsafeMutableRawPointer, _ offset: Int) -> Int32 {
        pointer.load(fromByteOffset: offset, as: Int32.self)
    }

    private func readUInt32(_ pointer: UnsafeMutableRawPointer, _ offset: Int) -> UInt32 {
        pointer.load(fromByteOffset: offset, as: UInt32.self)
    }

    private func decodeRefreshHz(rawRefresh: Int32, fallbackRaw: Int32) -> Double {
        let candidate = rawRefresh != 0 ? rawRefresh : fallbackRaw
        guard candidate != 0 else { return 0 }
        return candidate > 1000 ? Double(candidate) / 65536.0 : Double(candidate)
    }

    private func modeEntry(for modeID: Int) -> CGSModeEnumerationEntry? {
        if modeID == 56 {
            return cachedStatus?.mode56
        }
        if modeID == 74 {
            return cachedStatus?.mode74
        }
        return nil
    }

    private func readCurrentCGSMode(displayID: CGDirectDisplayID) -> Int32? {
        guard displayID != 0, let symbol = resolveFirstSymbol(["CGSGetCurrentDisplayMode", "SLSGetCurrentDisplayMode"]) else {
            return nil
        }
        let function = unsafeBitCast(symbol.pointer, to: CGSGetCurrentDisplayModeFunc.self)
        var modeID: Int32 = 0
        let result = function(displayID, &modeID)
        return result == .success ? modeID : nil
    }

    private func readActiveModeFingerprint(displayID: CGDirectDisplayID) -> CGSActiveModeFingerprint? {
        guard displayID != 0, let mode = CGDisplayCopyDisplayMode(displayID) else {
            return nil
        }
        return CGSActiveModeFingerprint(
            modeID: Int32(mode.ioDisplayModeID),
            logicalWidth: mode.width,
            logicalHeight: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRateHz: mode.refreshRate
        )
    }

    private func resolveConfigureSymbol() -> CGSConfigureDisplayModeFunc? {
        guard let symbol = resolveFirstSymbol(["CGSConfigureDisplayMode", "SLSConfigureDisplayMode"]) else {
            return nil
        }
        return unsafeBitCast(symbol.pointer, to: CGSConfigureDisplayModeFunc.self)
    }

    private func rollback(
        to modeID: Int32,
        displayID: CGDirectDisplayID,
        targetOperationGeneration: UInt64
    ) -> String {
        guard modeID >= 0 else {
            return "Rollback skipped: previous mode unavailable."
        }

        guard operationGate.isAllowed(),
              targetOperationGate.accepts(targetOperationGeneration, displayID: displayID),
              isSamsungTargetIdentity(displayID) else {
            return "Rollback skipped: Samsung target changed."
        }

        guard let configure = resolveConfigureSymbol() else {
            return "Rollback failed: CGSConfigureDisplayMode symbol not found."
        }

        var config: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&config)
        guard beginResult == .success, let config else {
            return "Rollback failed: CGBeginDisplayConfiguration returned \(beginResult.rawValue)"
        }

        let configureResult = configure(config, displayID, modeID)
        guard configureResult == 0 else {
            CGCancelDisplayConfiguration(config)
            return "Rollback failed: CGSConfigureDisplayMode returned \(configureResult)"
        }

        let completeResult = CGCompleteDisplayConfiguration(config, .forSession)
        if completeResult != .success {
            CGCancelDisplayConfiguration(config)
            return "Rollback failed: CGCompleteDisplayConfiguration returned \(completeResult.rawValue)"
        }

        return "Rollback to mode \(modeID) succeeded."
    }

    private func matches(_ mode: CGSModeEnumerationEntry, fingerprint: CGSActiveModeFingerprint?) -> Bool {
        guard let fingerprint else { return false }
        return mode.width == fingerprint.logicalWidth &&
            mode.height == fingerprint.logicalHeight &&
            mode.pixelWidth == fingerprint.pixelWidth &&
            mode.pixelHeight == fingerprint.pixelHeight &&
            abs(mode.refreshRateHz - fingerprint.refreshRateHz) < 0.1
    }

    private func isSuccessfulSwitch(
        requestedModeID: Int,
        afterModeID: Int32?,
        afterFingerprint: CGSActiveModeFingerprint?
    ) -> Bool {
        switch requestedModeID {
        case 56:
            if afterModeID == 56 { return true }
            guard let afterFingerprint else { return false }
            return
                (afterFingerprint.logicalWidth == 2560 &&
                 afterFingerprint.logicalHeight == 1440 &&
                 afterFingerprint.pixelWidth == 2560 &&
                 afterFingerprint.pixelHeight == 1440 &&
                 abs(afterFingerprint.refreshRateHz - 100.0) < 0.1)
        case 74:
            if afterModeID == 74 { return true }
            guard let afterFingerprint else { return false }
            return
                (afterFingerprint.logicalWidth == 2560 &&
                 afterFingerprint.logicalHeight == 1440 &&
                 afterFingerprint.pixelWidth == 5120 &&
                 afterFingerprint.pixelHeight == 2880 &&
                 abs(afterFingerprint.refreshRateHz - 100.0) < 0.1)
        default:
            return false
        }
    }

    private func writeReport(_ report: CGSManualModeSwitchReport) throws {
        let beforeModeText = report.beforeModeID.map(String.init) ?? "unavailable"
        let afterModeText = report.afterModeID.map(String.init) ?? "unavailable"
        let beforeFingerprintText = report.beforeFingerprint?.description ?? "unavailable"
        let afterFingerprintText = report.afterFingerprint?.description ?? "unavailable"

        var lines: [String] = []
        lines.append("# CGS Manual Mode Switch")
        lines.append("")
        lines.append("Generated at: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append("## requested mode")
        lines.append("- \(report.requestedModeID)")
        lines.append("")
        lines.append("## before mode id")
        lines.append("- \(beforeModeText)")
        lines.append("")
        lines.append("## after mode id")
        lines.append("- \(afterModeText)")
        lines.append("")
        lines.append("## before active fingerprint")
        lines.append("- \(beforeFingerprintText)")
        lines.append("")
        lines.append("## after active fingerprint")
        lines.append("- \(afterFingerprintText)")
        lines.append("")
        lines.append("## configure result")
        lines.append("- \(report.configureResult)")
        lines.append("")
        lines.append("## complete result")
        lines.append("- \(report.completeResult)")
        lines.append("")
        lines.append("## success/failure")
        lines.append("- \(report.success ? "success" : "failure")")
        if let failureReason = report.failureReason {
            lines.append("- \(failureReason)")
        }
        lines.append("")
        lines.append("## rollback yapıldı mı?")
        lines.append("- \(report.rollbackAttempted ? "Evet" : "Hayır")")
        if let rollbackResult = report.rollbackResult {
            lines.append("- \(rollbackResult)")
        }
        lines.append("")

        try FileManager.default.createDirectory(at: report.reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: report.reportURL, atomically: true, encoding: .utf8)
    }

    private func resolveFirstSymbol(_ names: [String]) -> (name: String, pointer: UnsafeMutableRawPointer)? {
        let resolver = PrivateDisplaySymbolResolver.shared
        for name in names {
            if let pointer = resolver.resolveSymbol(name: name) {
                return (name, pointer)
            }
        }
        return nil
    }
}
