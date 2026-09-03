import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps
import IOKit.pwr_mgt
import Darwin
import SwiftUI

struct M1DDCBrightnessWriteResult: Sendable {
    let success: Bool
    let status: M1DDCBrightnessWriteStatus
    let message: String
    let requestedUIPercent: Int
    let rawMax: Int?
    let computedRawTarget: Int?
    let rawBefore: Int?
    let rawAfter: Int?
    let actualUIPercentAfter: Int?
    let readbackBrightnessPercent: Int?
    let readbackAvailable: Bool
    let matchedTarget: Bool?

    var requestedBrightnessPercent: Int { requestedUIPercent }
}

private struct M1DDCCommandResult {
    var success: Bool
    var output: String
}

private final class ResumeGuard: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()
    func shouldResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}

private final class M1DDCProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func install(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.process = process
        return true
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }
}

struct M1DDCExecutableLocator {
    static let defaultCandidates = [
        "/opt/homebrew/bin/m1ddc",
        "/usr/local/bin/m1ddc"
    ]

    let candidates: [String]
    private let executableCheck: (String) -> Bool

    init(
        candidates: [String] = M1DDCExecutableLocator.defaultCandidates,
        executableCheck: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.candidates = candidates
        self.executableCheck = executableCheck
    }

    func locate() -> URL? {
        candidates.lazy.map(URL.init(fileURLWithPath:)).first { executableCheck($0.path) }
    }
}

struct M1DDCDisplayParseResult: Equatable, Sendable {
    let allDisplays: [ExternalDisplayInfo]
    let externalDisplays: [ExternalDisplayInfo]
    let samsungFilteredDisplays: [ExternalDisplayInfo]
}

private struct M1DDCTargetOperationContext: Sendable {
    let generation: UInt64
    let displayID: CGDirectDisplayID
}

actor M1DDCWriter {
    private static let targetMonitorNames = ["S60UD", "LS32D60", "LS32D60xU"]
    private static let fallbackMonitorName = "Samsung"
    private static let targetVendorID: UInt32 = 0x4C2D
    private static let targetProductID: UInt32 = 0x76AB
    private static let processTimeout: TimeInterval = 5.0
    private let workQueue = DispatchQueue(label: "com.ambientsync.m1ddc-worker")
    private let operationGate: DisplayPowerOperationGate
    private let targetOperationGate: TargetDisplayOperationGate
    private var inFlightProcessHandles: [ObjectIdentifier: M1DDCProcessHandle] = [:]

    private let executableLocator: M1DDCExecutableLocator
    private var executableURL: URL?
    private var lastExecutableCheckDate = Date.distantPast
    private(set) var currentDisplayInfo: ExternalDisplayInfo?
    private var cachedDisplays: [ExternalDisplayInfo] = []
    private var lastDiscoveryDate: Date = .distantPast
    private var lastKnownBrightnessByDisplay: [String: Int] = [:]
    private var lastKnownVolumeByDisplay: [String: Int] = [:]
    private let discoveryCacheInterval: TimeInterval = 6.0
    private let executableCacheInterval: TimeInterval = 5.0

    init(
        executableLocator: M1DDCExecutableLocator = M1DDCExecutableLocator(),
        operationGate: DisplayPowerOperationGate = .shared,
        targetOperationGate: TargetDisplayOperationGate = .shared
    ) {
        self.executableLocator = executableLocator
        self.operationGate = operationGate
        self.targetOperationGate = targetOperationGate
        executableURL = nil
        currentDisplayInfo = nil 
    }

    func isAvailable(refresh: Bool = false) -> Bool {
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration) else { return false }
        refreshExecutableAvailability(force: refresh)
        return operationGate.accepts(operationGeneration) && executableURL != nil
    }

    /// Terminates every DDC subprocess owned by this writer at a power
    /// boundary. This complements cancellation of coordinator-owned tasks and
    /// prevents a diagnostic or refresh task from leaving m1ddc running into
    /// sleep.
    func cancelInFlightOperations() {
        inFlightProcessHandles.values.forEach { $0.cancel() }
    }

    func refreshDisplay(preferredKey: String?) async -> ExternalDisplayInfo? {
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration),
              let targetContext = currentTargetOperationContext() else { return nil }
        refreshExecutableAvailability(force: true)

        if executableURL != nil {
            if let display = await selectDisplay(
                preferredKey: preferredKey,
                forceRefresh: true,
                expectedGeneration: operationGeneration,
                targetContext: targetContext
            ) {
                guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return nil }
                currentDisplayInfo = display
                return display
            }
        }

        // m1ddc is the control backend, but it is not the authoritative source
        // for whether a supported monitor is physically connected. On newer
        // macOS/display-driver combinations its list command can be empty while
        // CoreGraphics still exposes the online monitor and its fingerprint.
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return nil }
        let fallbackDisplays = Self.discoverCoreGraphicsDisplays()
        let display = Self.selectDisplay(fallbackDisplays, preferredKey: preferredKey)
        guard display?.displayID == targetContext.displayID,
              acceptsOperation(operationGeneration, targetContext: targetContext) else { return nil }
        currentDisplayInfo = display
        return display
    }

    func currentBrightness() async -> Int? {
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration),
              let targetContext = currentTargetOperationContext() else { return nil }
        guard let display = await selectDisplay(
            preferredKey: nil,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        ) else { return nil }
        if let sample = await readBrightnessRaw(
            displayIndex: Self.ddcSelector(for: display),
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        ),
           acceptsOperation(operationGeneration, targetContext: targetContext),
           let rawCurrent = sample.rawCurrent,
           let rawMax = sample.rawMax
        {
            let value = DDCBrightnessScale.uiPercent(fromRawCurrent: rawCurrent, rawMax: rawMax)
            lastKnownBrightnessByDisplay[display.displayKey] = value
            return value
        }
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return nil }
        return lastKnownBrightnessByDisplay[display.displayKey]
    }

    func readBrightness(preferredKey: String? = nil) async -> Int? {
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration),
              let targetContext = currentTargetOperationContext() else { return nil }
        guard let display = await selectDisplay(
            preferredKey: preferredKey,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        ) else { return nil }
        return await readBrightness(
            displayIndex: Self.ddcSelector(for: display),
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
    }

    func readBrightnessRaw(preferredKey: String? = nil) async -> DDCBrightnessRawSample? {
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration),
              let targetContext = currentTargetOperationContext() else { return nil }
        guard let display = await selectDisplay(
            preferredKey: preferredKey,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        ) else { return nil }
        return await readBrightnessRaw(
            displayIndex: Self.ddcSelector(for: display),
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
    }

    func currentVolume() async -> Int? {
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration),
              let targetContext = currentTargetOperationContext() else { return nil }
        guard let display = await selectDisplay(
            preferredKey: nil,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        ) else { return nil }
        let selector = Self.ddcSelector(for: display)
        guard !selector.isEmpty else { return nil }
        let result = await run(
            arguments: ["display", selector, "get", "volume"],
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return nil }
        if result.success, let value = Self.parsePercent(from: result.output) {
            lastKnownVolumeByDisplay[display.displayKey] = value
            return value
        }
        return lastKnownVolumeByDisplay[display.displayKey]
    }

    func setBrightness(_ percent: Int, preferredKey: String? = nil) async -> M1DDCBrightnessWriteResult {
        let clamped = min(100, max(0, percent))
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration),
              let targetContext = currentTargetOperationContext() else {
            return Self.suspendedBrightnessWriteResult(for: clamped)
        }
        let display = await selectDisplay(
            preferredKey: preferredKey,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else {
            return Self.suspendedBrightnessWriteResult(for: clamped)
        }
        guard let display else {
            return M1DDCBrightnessWriteResult(
                success: false,
                status: .writeFailed,
                message: "Samsung S60UD display not found",
                requestedUIPercent: clamped,
                rawMax: nil,
                computedRawTarget: nil,
                rawBefore: nil,
                rawAfter: nil,
                actualUIPercentAfter: nil,
                readbackBrightnessPercent: nil,
                readbackAvailable: false,
                matchedTarget: nil
            )
        }
        let firstResult = await setBrightness(
            clamped,
            for: display,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
        if firstResult.success {
            return firstResult
        }

        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return firstResult }

        guard let refreshed = await selectDisplay(
            preferredKey: preferredKey,
            forceRefresh: true,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        ) else {
            return firstResult
        }
        return await setBrightness(
            clamped,
            for: refreshed,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
    }

    private static func suspendedBrightnessWriteResult(for percent: Int) -> M1DDCBrightnessWriteResult {
        M1DDCBrightnessWriteResult(
            success: false,
            status: .writeFailed,
            message: "Display runtime suspended",
            requestedUIPercent: percent,
            rawMax: nil,
            computedRawTarget: nil,
            rawBefore: nil,
            rawAfter: nil,
            actualUIPercentAfter: nil,
            readbackBrightnessPercent: nil,
            readbackAvailable: false,
            matchedTarget: nil
        )
    }

    func setVolume(_ percent: Int, preferredKey: String? = nil) async -> (Bool, String) {
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration),
              let targetContext = currentTargetOperationContext() else { return (false, "Samsung target display not ready") }
        let display = await selectDisplay(
            preferredKey: preferredKey,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return (false, "Display runtime suspended") }
        guard let display else { return (false, "Samsung S60UD display not found") }
        let clamped = min(100, max(0, percent))
        let selector = Self.ddcSelector(for: display)
        guard !selector.isEmpty else { return (false, "DDC selector unavailable") }
        let result = await run(
            arguments: ["display", selector, "set", "volume", "\(clamped)"],
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return (false, "Display runtime suspended") }
        if result.success {
            lastKnownVolumeByDisplay[display.displayKey] = clamped
        }
        return (result.success, result.output)
    }

    func changeVolume(_ delta: Int, preferredKey: String? = nil) async -> (Bool, String) {
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration),
              let targetContext = currentTargetOperationContext() else { return (false, "Samsung target display not ready") }
        let display = await selectDisplay(
            preferredKey: preferredKey,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return (false, "Display runtime suspended") }
        guard let display else { return (false, "Samsung S60UD display not found") }
        let selector = Self.ddcSelector(for: display)
        guard !selector.isEmpty else { return (false, "DDC selector unavailable") }
        let result = await run(
            arguments: ["display", selector, "chg", "volume", "\(delta)"],
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return (false, "Display runtime suspended") }
        if result.success {
            let base = lastKnownVolumeByDisplay[display.displayKey] ?? 50
            lastKnownVolumeByDisplay[display.displayKey] = min(100, max(0, base + delta))
        }
        return (result.success, result.output)
    }

    func setMute(_ enabled: Bool, preferredKey: String? = nil) async -> (Bool, String) {
        let operationGeneration = operationGate.currentGeneration()
        guard operationGate.accepts(operationGeneration),
              let targetContext = currentTargetOperationContext() else { return (false, "Samsung target display not ready") }
        let display = await selectDisplay(
            preferredKey: preferredKey,
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return (false, "Display runtime suspended") }
        guard let display else { return (false, "Samsung S60UD display not found") }
        let selector = Self.ddcSelector(for: display)
        guard !selector.isEmpty else { return (false, "DDC selector unavailable") }
        let result = await run(
            arguments: ["display", selector, "set", "mute", enabled ? "on" : "off"],
            expectedGeneration: operationGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else { return (false, "Display runtime suspended") }
        if result.success {
            lastKnownVolumeByDisplay[display.displayKey] = enabled ? 0 : (lastKnownVolumeByDisplay[display.displayKey] ?? 50)
        }
        return (result.success, result.output)
    }

    private func selectDisplay(
        preferredKey: String?,
        forceRefresh: Bool = false,
        expectedGeneration: UInt64,
        targetContext: M1DDCTargetOperationContext
    ) async -> ExternalDisplayInfo? {
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else { return nil }
        if
            !forceRefresh,
            let currentDisplayInfo,
            preferredKey == nil || preferredKey == currentDisplayInfo.displayKey
        {
            guard currentDisplayInfo.displayID == targetContext.displayID else { return nil }
            return currentDisplayInfo
        }

        let displays = await discoverDisplays(
            forceRefresh: forceRefresh || preferredKey != nil,
            expectedGeneration: expectedGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else { return nil }
        let targetDisplays = displays.filter { $0.displayID == targetContext.displayID }
        guard !targetDisplays.isEmpty else {
            currentDisplayInfo = nil
            return nil
        }

        if let preferredKey, let preferred = targetDisplays.first(where: { $0.displayKey == preferredKey }) {
            currentDisplayInfo = preferred
            return preferred
        }

        if let currentDisplayInfo, let matched = targetDisplays.first(where: { $0.displayKey == currentDisplayInfo.displayKey }) {
            self.currentDisplayInfo = matched
            return matched
        }

        currentDisplayInfo = targetDisplays[0]
        return targetDisplays[0]
    }

    private static func selectDisplay(
        _ displays: [ExternalDisplayInfo],
        preferredKey: String?
    ) -> ExternalDisplayInfo? {
        if let preferredKey, let preferred = displays.first(where: { $0.displayKey == preferredKey }) {
            return preferred
        }
        return displays.first
    }

    private static func ddcSelector(for display: ExternalDisplayInfo) -> String {
        if !display.displayIndex.isEmpty, !display.displayIndex.hasPrefix("id:") {
            // This is the selector used by the original AmbientSync
            // implementation and is the index emitted by `display list
            // detailed`. Keep the operational selector separate from the
            // stable display identity stored in displayKey.
            return display.displayIndex
        }

        if let systemUUID = display.systemUUID, !systemUUID.isEmpty {
            // m1ddc also accepts the UUID itself as a fallback; the `uuid:`
            // prefix is not part of its selector grammar.
            return systemUUID
        }

        // A CoreGraphics-only fallback has a display ID but no m1ddc list
        // index. The CG ID is an identity value, not a valid m1ddc selector;
        // leave DDC unavailable rather than addressing an unrelated display.
        return ""
    }

    static func ddcSelectorForDiagnostics(_ display: ExternalDisplayInfo) -> String {
        ddcSelector(for: display)
    }

    private func discoverDisplays(
        forceRefresh: Bool,
        expectedGeneration: UInt64,
        targetContext: M1DDCTargetOperationContext
    ) async -> [ExternalDisplayInfo] {
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else { return [] }
        refreshExecutableAvailability(force: forceRefresh)
        guard executableURL != nil else {
            cachedDisplays = []
            return []
        }

        let now = Date()
        if
            !forceRefresh,
            now.timeIntervalSince(lastDiscoveryDate) < discoveryCacheInterval,
            !cachedDisplays.isEmpty
        {
            return cachedDisplays
        }

        let result = await run(
            arguments: ["display", "list", "detailed"],
            expectedGeneration: expectedGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else { return [] }
        lastDiscoveryDate = now
        guard result.success else { return cachedDisplays }
        let parsed = Self.parseDisplays(result.output)
        if !parsed.isEmpty {
            cachedDisplays = parsed
        } else {
            cachedDisplays = []
        }
        return cachedDisplays
    }

    private func acceptsOperation(
        _ expectedGeneration: UInt64,
        targetContext: M1DDCTargetOperationContext
    ) -> Bool {
        operationGate.accepts(expectedGeneration) &&
            targetOperationGate.accepts(
                targetContext.generation,
                displayID: targetContext.displayID
            ) &&
            isCurrentTargetIdentity(targetContext.displayID)
    }

    private func currentTargetOperationContext() -> M1DDCTargetOperationContext? {
        let snapshot = targetOperationGate.snapshot()
        guard let displayID = snapshot.displayID,
              acceptsTargetOperation(snapshot.generation, displayID: displayID) else {
            return nil
        }
        return M1DDCTargetOperationContext(
            generation: snapshot.generation,
            displayID: displayID
        )
    }

    private func acceptsTargetOperation(
        _ generation: UInt64,
        displayID: CGDirectDisplayID
    ) -> Bool {
        targetOperationGate.accepts(generation, displayID: displayID) &&
            isCurrentTargetIdentity(displayID)
    }

    private func isCurrentTargetIdentity(_ displayID: CGDirectDisplayID) -> Bool {
        displayID != 0 &&
            CGDisplayIsBuiltin(displayID) == 0 &&
            CGDisplayVendorNumber(displayID) == Self.targetVendorID &&
            CGDisplayModelNumber(displayID) == Self.targetProductID &&
            CGDisplayIsOnline(displayID) != 0 &&
            CGDisplayIsActive(displayID) != 0
    }

    static func isSupportedTargetDisplay(
        vendorID: UInt32,
        productID: UInt32,
        isBuiltin: Bool
    ) -> Bool {
        !isBuiltin && vendorID == targetVendorID && productID == targetProductID
    }

    static var targetVendorIDForDiagnostics: UInt32 { targetVendorID }
    static var targetProductIDForDiagnostics: UInt32 { targetProductID }

    static func parseDisplaysForDiagnostics(_ output: String) -> M1DDCDisplayParseResult {
        parseDisplayStages(output)
    }

    static func selectDisplayForDiagnostics(
        _ displays: [ExternalDisplayInfo],
        preferredKey: String?
    ) -> ExternalDisplayInfo? {
        selectDisplay(displays, preferredKey: preferredKey)
    }

    private static func discoverCoreGraphicsDisplays() -> [ExternalDisplayInfo] {
        let displayIDs = copyOnlineDisplayIDs()

        return displayIDs.compactMap { displayID in
            guard isSupportedTargetDisplay(
                vendorID: CGDisplayVendorNumber(displayID),
                productID: CGDisplayModelNumber(displayID),
                isBuiltin: CGDisplayIsBuiltin(displayID) != 0
            ) else {
                return nil
            }

            let serialValue = CGDisplaySerialNumber(displayID)
            return ExternalDisplayInfo(
                // Keep the CG ID in a visibly non-DDC selector-shaped field so
                // the identity remains diagnosable without mistaking it for
                // an m1ddc list index.
                displayIndex: "id:\(displayID)",
                displayID: displayID,
                productName: "Samsung S60UD",
                serial: serialValue == 0 ? nil : String(serialValue),
                systemUUID: nil,
                ioLocation: nil
            )
        }
    }

    private static func copyOnlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        if CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 {
            var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
            if CGGetOnlineDisplayList(count, &displayIDs, &count) == .success {
                return Array(displayIDs.prefix(Int(count)))
            }
        }

        // Some display-driver/session combinations report no online list to a
        // fresh process while the active display list is already populated.
        // Use the active list as a discovery fallback; the fingerprint filter
        // below still prevents unrelated displays from being selected.
        let maxDisplays: UInt32 = 32
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        guard CGGetActiveDisplayList(maxDisplays, &displayIDs, &count) == .success else {
            return []
        }
        return Array(displayIDs.prefix(Int(count)))
    }

    private func refreshExecutableAvailability(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastExecutableCheckDate) >= executableCacheInterval else { return }

        lastExecutableCheckDate = now
        let nextURL = executableLocator.locate()
        if nextURL?.path != executableURL?.path {
            executableURL = nextURL
            cachedDisplays = []
            currentDisplayInfo = nil
            lastDiscoveryDate = .distantPast
        } else {
            executableURL = nextURL
        }
    }

    private func setBrightness(
        _ clamped: Int,
        for display: ExternalDisplayInfo,
        expectedGeneration: UInt64,
        targetContext: M1DDCTargetOperationContext
    ) async -> M1DDCBrightnessWriteResult {
        let selector = Self.ddcSelector(for: display)
        guard acceptsOperation(expectedGeneration, targetContext: targetContext),
              display.displayID == targetContext.displayID,
              !selector.isEmpty else {
            return Self.suspendedBrightnessWriteResult(for: clamped)
        }
        let beforeSample = await readBrightnessSample(
            displayIndex: selector,
            expectedGeneration: expectedGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else {
            return Self.suspendedBrightnessWriteResult(for: clamped)
        }
        guard let rawMax = beforeSample?.rawMax else {
            return M1DDCBrightnessWriteResult(
                success: false,
                status: .readbackUnavailable,
                message: "Unable to read raw brightness max",
                requestedUIPercent: clamped,
                rawMax: nil,
                computedRawTarget: nil,
                rawBefore: beforeSample?.rawCurrent,
                rawAfter: nil,
                actualUIPercentAfter: nil,
                readbackBrightnessPercent: nil,
                readbackAvailable: false,
                matchedTarget: nil
            )
        }

        let rawBefore = beforeSample?.rawCurrent
        let computedRawTarget = DDCBrightnessScale.rawTarget(forUIPercent: clamped, rawMax: rawMax)
        let result = await run(
            arguments: ["display", selector, "set", "luminance", "\(computedRawTarget)"],
            expectedGeneration: expectedGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else {
            return Self.suspendedBrightnessWriteResult(for: clamped)
        }
        guard result.success else {
            return M1DDCBrightnessWriteResult(
                success: false,
                status: .writeFailed,
                message: result.output,
                requestedUIPercent: clamped,
                rawMax: rawMax,
                computedRawTarget: computedRawTarget,
                rawBefore: rawBefore,
                rawAfter: nil,
                actualUIPercentAfter: nil,
                readbackBrightnessPercent: nil,
                readbackAvailable: false,
                matchedTarget: nil
            )
        }
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            return Self.suspendedBrightnessWriteResult(for: clamped)
        }
        guard !Task.isCancelled, acceptsOperation(expectedGeneration, targetContext: targetContext) else {
            return Self.suspendedBrightnessWriteResult(for: clamped)
        }
        let afterSample = await readBrightnessSample(
            displayIndex: selector,
            expectedGeneration: expectedGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else {
            return Self.suspendedBrightnessWriteResult(for: clamped)
        }
        guard let rawAfter = afterSample?.rawCurrent else {
            return M1DDCBrightnessWriteResult(
                success: false,
                status: .readbackUnavailable,
                message: "DDC write accepted but readback unavailable",
                requestedUIPercent: clamped,
                rawMax: rawMax,
                computedRawTarget: computedRawTarget,
                rawBefore: rawBefore,
                rawAfter: nil,
                actualUIPercentAfter: nil,
                readbackBrightnessPercent: nil,
                readbackAvailable: false,
                matchedTarget: nil
            )
        }

        let actualUIPercentAfter = DDCBrightnessScale.uiPercent(fromRawCurrent: rawAfter, rawMax: rawMax)
        let matchedTarget = DDCBrightnessScale.isMatched(rawAfter: rawAfter, computedRawTarget: computedRawTarget)
        lastKnownBrightnessByDisplay[display.displayKey] = actualUIPercentAfter

        if matchedTarget {
            return M1DDCBrightnessWriteResult(
                success: true,
                status: .success,
                message: "ok",
                requestedUIPercent: clamped,
                rawMax: rawMax,
                computedRawTarget: computedRawTarget,
                rawBefore: rawBefore,
                rawAfter: rawAfter,
                actualUIPercentAfter: actualUIPercentAfter,
                readbackBrightnessPercent: actualUIPercentAfter,
                readbackAvailable: true,
                matchedTarget: true
            )
        }

        return M1DDCBrightnessWriteResult(
            success: false,
            status: .writeAcceptedButReadbackLimited,
            message: "DDC write accepted but monitor did not change brightness. Possible monitor-side limiter.",
            requestedUIPercent: clamped,
            rawMax: rawMax,
            computedRawTarget: computedRawTarget,
            rawBefore: rawBefore,
            rawAfter: rawAfter,
            actualUIPercentAfter: actualUIPercentAfter,
            readbackBrightnessPercent: actualUIPercentAfter,
            readbackAvailable: true,
            matchedTarget: false
        )
    }

    private func run(
        arguments: [String],
        expectedGeneration: UInt64,
        targetContext: M1DDCTargetOperationContext
    ) async -> M1DDCCommandResult {
        let operationGeneration = expectedGeneration
        guard acceptsOperation(operationGeneration, targetContext: targetContext) else {
            return M1DDCCommandResult(success: false, output: "Display runtime suspended")
        }
        guard let executableURL = self.executableURL else {
            return M1DDCCommandResult(success: false, output: "m1ddc not found")
        }

        let processHandle = M1DDCProcessHandle()
        let processHandleID = ObjectIdentifier(processHandle)
        inFlightProcessHandles[processHandleID] = processHandle
        defer { inFlightProcessHandles.removeValue(forKey: processHandleID) }
        let workQueue = self.workQueue
        let operationGate = self.operationGate
        let targetOperationGate = self.targetOperationGate
        let targetDisplayID = targetContext.displayID
        let targetGeneration = targetContext.generation

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let rGuard = ResumeGuard()

                @Sendable func safeResume(with result: M1DDCCommandResult) {
                    if rGuard.shouldResume() {
                        continuation.resume(returning: result)
                    }
                }

                workQueue.async {
                    guard operationGate.accepts(operationGeneration),
                          targetOperationGate.accepts(targetGeneration, displayID: targetDisplayID),
                          CGDisplayIsBuiltin(targetDisplayID) == 0,
                          CGDisplayVendorNumber(targetDisplayID) == Self.targetVendorID,
                          CGDisplayModelNumber(targetDisplayID) == Self.targetProductID,
                          CGDisplayIsOnline(targetDisplayID) != 0,
                          CGDisplayIsActive(targetDisplayID) != 0,
                          !processHandle.isCancelled() else {
                        safeResume(with: M1DDCCommandResult(success: false, output: "Display runtime suspended"))
                        return
                    }

                    let process = Process()
                    process.executableURL = executableURL
                    process.arguments = arguments
                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr

                    guard processHandle.install(process),
                          operationGate.accepts(operationGeneration),
                          targetOperationGate.accepts(targetGeneration, displayID: targetDisplayID),
                          CGDisplayIsBuiltin(targetDisplayID) == 0,
                          CGDisplayVendorNumber(targetDisplayID) == Self.targetVendorID,
                          CGDisplayModelNumber(targetDisplayID) == Self.targetProductID,
                          CGDisplayIsOnline(targetDisplayID) != 0,
                          CGDisplayIsActive(targetDisplayID) != 0 else {
                        safeResume(with: M1DDCCommandResult(success: false, output: "Display runtime suspended"))
                        return
                    }
                    defer { processHandle.clear() }

                    do {
                        try process.run()

                        let timer = DispatchSource.makeTimerSource(queue: .global())
                        timer.schedule(deadline: .now() + Self.processTimeout)
                        timer.setEventHandler {
                            if process.isRunning {
                                process.terminate()
                            }
                        }
                        timer.resume()

                        process.waitUntilExit()
                        timer.cancel()

                        let outputData = stdout.fileHandleForReading.readDataToEndOfFile() + stderr.fileHandleForReading.readDataToEndOfFile()
                        let output = (String(data: outputData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                        let success = process.terminationStatus == 0 &&
                            operationGate.accepts(operationGeneration) &&
                            targetOperationGate.accepts(targetGeneration, displayID: targetDisplayID) &&
                            CGDisplayIsBuiltin(targetDisplayID) == 0 &&
                            CGDisplayVendorNumber(targetDisplayID) == Self.targetVendorID &&
                            CGDisplayModelNumber(targetDisplayID) == Self.targetProductID &&
                            CGDisplayIsOnline(targetDisplayID) != 0 &&
                            CGDisplayIsActive(targetDisplayID) != 0 &&
                            !processHandle.isCancelled()
                        let result = M1DDCCommandResult(
                            success: success,
                            output: output.isEmpty ? (success ? "ok" : "m1ddc command failed") : output
                        )
                        safeResume(with: result)
                    } catch {
                        safeResume(with: M1DDCCommandResult(success: false, output: error.localizedDescription))
                    }
                }
            }
        }, onCancel: {
            processHandle.cancel()
        })
    }

    private func readBrightness(
        displayIndex: String,
        expectedGeneration: UInt64,
        targetContext: M1DDCTargetOperationContext
    ) async -> Int? {
        guard let sample = await readBrightnessRaw(
            displayIndex: displayIndex,
            expectedGeneration: expectedGeneration,
            targetContext: targetContext
        ) else { return nil }
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else { return nil }
        guard let rawCurrent = sample.rawCurrent, let rawMax = sample.rawMax else { return nil }
        return DDCBrightnessScale.uiPercent(fromRawCurrent: rawCurrent, rawMax: rawMax)
    }

    private func readBrightnessSample(
        displayIndex: String,
        expectedGeneration: UInt64,
        targetContext: M1DDCTargetOperationContext
    ) async -> DDCBrightnessRawSample? {
        await readBrightnessRaw(
            displayIndex: displayIndex,
            expectedGeneration: expectedGeneration,
            targetContext: targetContext
        )
    }

    private func readBrightnessRaw(
        displayIndex: String,
        expectedGeneration: UInt64,
        targetContext: M1DDCTargetOperationContext
    ) async -> DDCBrightnessRawSample? {
        guard acceptsOperation(expectedGeneration, targetContext: targetContext),
              !displayIndex.isEmpty else { return nil }
        let result = await run(
            arguments: ["display", displayIndex, "get", "luminance"],
            expectedGeneration: expectedGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else { return nil }
        guard result.success else { return nil }
        let sample = DDCBrightnessParsing.parseRawSample(from: result.output)
        if sample.rawMax != nil {
            return sample
        }

        let maxResult = await run(
            arguments: ["display", displayIndex, "max", "luminance"],
            expectedGeneration: expectedGeneration,
            targetContext: targetContext
        )
        guard acceptsOperation(expectedGeneration, targetContext: targetContext) else { return nil }
        guard maxResult.success, let rawMax = DDCBrightnessParsing.parseSingleRawValue(from: maxResult.output) else {
            return sample
        }

        return DDCBrightnessRawSample(
            rawCurrent: sample.rawCurrent,
            rawMax: rawMax,
            available: sample.available,
            output: [sample.output, "max: \(maxResult.output)"]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        )
    }

    private static func parsePercent(from output: String) -> Int? {
        let lines = output.lowercased().split(whereSeparator: \.isNewline)

        for line in lines {
            let lineStr = String(line)

            let patterns = [
                #"\bcurrent\b\s*[:=]?\s*(\d+)"#,
                #"\bvalue\b\s*[:=]?\s*(\d+)"#,
                #"\bluminance\b\s*[:=]?\s*(\d+)"#,
                #"\bbrightness\b\s*[:=]?\s*(\d+)"#,
                #"\bvolume\b\s*[:=]?\s*(\d+)"#,
                #"(\d+)%"#
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: lineStr, options: [], range: NSRange(lineStr.startIndex..., in: lineStr)) {
                    let groupIndex = match.numberOfRanges > 1 ? 1 : 0
                    let valueRange = match.range(at: groupIndex)
                    if let range = Range(valueRange, in: lineStr) {
                        let matchStr = lineStr[range].filter { $0.isNumber }
                        if let val = Int(matchStr), (0...100).contains(val) { return val }
                    }
                }
            }
        }

        for line in lines {
            let tokens = String(line).components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if let lastToken = tokens.last, let val = Int(lastToken), (0...100).contains(val) {
                return val
            }
        }

        return nil
    }

    private static func parseDisplays(_ output: String) -> [ExternalDisplayInfo] {
        parseDisplayStages(output).samsungFilteredDisplays
    }

    private static func parseDisplayStages(_ output: String) -> M1DDCDisplayParseResult {
        struct Partial {
            var displayIndex: String = ""
            var displayID: UInt32?
            var productName: String = ""
            var serial: String?
            var systemUUID: String?
            var ioLocation: String?
        }

        func normalizedValue(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "(null)" else { return nil }
            return trimmed
        }

        func flush(_ partial: Partial?, into external: inout [ExternalDisplayInfo], all: inout [ExternalDisplayInfo]) {
            guard let partial else { return }
            guard !partial.displayIndex.isEmpty else { return }
            guard let productName = normalizedValue(partial.productName) else { return }
            let display = ExternalDisplayInfo(
                displayIndex: partial.displayIndex,
                displayID: partial.displayID,
                productName: productName,
                serial: partial.serial,
                systemUUID: partial.systemUUID,
                ioLocation: partial.ioLocation
            )
            all.append(display)

            let lowerName = productName.lowercased()
            let lowerLocation = partial.ioLocation?.lowercased() ?? ""
            let looksInternal = lowerName.contains("built-in") || lowerName.contains("color lcd") || lowerLocation.contains("disp0")
            if !looksInternal {
                external.append(display)
            }
        }

        var externalDisplays: [ExternalDisplayInfo] = []
        var allDisplays: [ExternalDisplayInfo] = []
        var current: Partial?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") {
                flush(current, into: &externalDisplays, all: &allDisplays)
                current = Partial()
                if let endIndex = line.firstIndex(of: "]") {
                    let bracketValue = line[line.index(after: line.startIndex)..<endIndex].trimmingCharacters(in: .whitespaces)
                    current?.displayIndex = String(bracketValue)
                }
                continue
            }

            guard var partial = current else { continue }
            if line.hasPrefix("- Product name:") {
                partial.productName = line.replacingOccurrences(of: "- Product name:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- Display ID:") {
                let value = line.replacingOccurrences(of: "- Display ID:", with: "").trimmingCharacters(in: .whitespaces)
                partial.displayID = UInt32(value)
            } else if line.hasPrefix("- Serial:") {
                let value = line.replacingOccurrences(of: "- Serial:", with: "").trimmingCharacters(in: .whitespaces)
                partial.serial = value.isEmpty || value == "(null)" ? nil : value
            } else if line.hasPrefix("- System UUID:") {
                let value = line.replacingOccurrences(of: "- System UUID:", with: "").trimmingCharacters(in: .whitespaces)
                partial.systemUUID = value.isEmpty || value == "(null)" ? nil : value
            } else if line.hasPrefix("- IO Location:") {
                partial.ioLocation = line.replacingOccurrences(of: "- IO Location:", with: "").trimmingCharacters(in: .whitespaces)
            }
            current = partial
        }

        flush(current, into: &externalDisplays, all: &allDisplays)
        
        let samsungDisplays = externalDisplays.filter { display in
            targetMonitorNames.contains { display.productName.localizedCaseInsensitiveContains($0) } ||
                display.productName.localizedCaseInsensitiveContains(fallbackMonitorName)
        }
        
        let sortedSamsungDisplays = samsungDisplays.sorted { a, b in
            let aIsS60 = targetMonitorNames.contains { a.productName.localizedCaseInsensitiveContains($0) }
            let bIsS60 = targetMonitorNames.contains { b.productName.localizedCaseInsensitiveContains($0) }
            if aIsS60 != bIsS60 { return aIsS60 } 
            return a.displayIndex < b.displayIndex
        }

        return M1DDCDisplayParseResult(
            allDisplays: allDisplays,
            externalDisplays: externalDisplays,
            samsungFilteredDisplays: sortedSamsungDisplays
        )
    }

}
