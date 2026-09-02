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

actor M1DDCWriter {
    private static let targetMonitorNames = ["S60UD", "LS32D60", "LS32D60xU"]
    private static let fallbackMonitorName = "Samsung"
    private static let targetVendorID: UInt32 = 0x4C2D
    private static let targetProductID: UInt32 = 0x76AB
    private static let processTimeout: TimeInterval = 5.0
    private let workQueue = DispatchQueue(label: "com.ambientsync.m1ddc-worker")

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

    init(executableLocator: M1DDCExecutableLocator = M1DDCExecutableLocator()) {
        self.executableLocator = executableLocator
        executableURL = nil
        currentDisplayInfo = nil 
    }

    func isAvailable(refresh: Bool = false) -> Bool {
        refreshExecutableAvailability(force: refresh)
        return executableURL != nil
    }

    func refreshDisplay(preferredKey: String?) async -> ExternalDisplayInfo? {
        refreshExecutableAvailability(force: true)

        if executableURL != nil {
            if let display = await selectDisplay(preferredKey: preferredKey, forceRefresh: true) {
                currentDisplayInfo = display
                return display
            }
        }

        // m1ddc is the control backend, but it is not the authoritative source
        // for whether a supported monitor is physically connected. On newer
        // macOS/display-driver combinations its list command can be empty while
        // CoreGraphics still exposes the online monitor and its fingerprint.
        let fallbackDisplays = Self.discoverCoreGraphicsDisplays()
        let display = Self.selectDisplay(fallbackDisplays, preferredKey: preferredKey)
        currentDisplayInfo = display
        return display
    }

    func currentBrightness() async -> Int? {
        guard let display = await selectDisplay(preferredKey: nil) else { return nil }
        if let sample = await readBrightnessRaw(displayIndex: Self.ddcSelector(for: display)),
           let rawCurrent = sample.rawCurrent,
           let rawMax = sample.rawMax
        {
            let value = DDCBrightnessScale.uiPercent(fromRawCurrent: rawCurrent, rawMax: rawMax)
            lastKnownBrightnessByDisplay[display.displayKey] = value
            return value
        }
        return lastKnownBrightnessByDisplay[display.displayKey]
    }

    func readBrightness(preferredKey: String? = nil) async -> Int? {
        guard let display = await selectDisplay(preferredKey: preferredKey) else { return nil }
        return await readBrightness(displayIndex: Self.ddcSelector(for: display))
    }

    func readBrightnessRaw(preferredKey: String? = nil) async -> DDCBrightnessRawSample? {
        guard let display = await selectDisplay(preferredKey: preferredKey) else { return nil }
        return await readBrightnessRaw(displayIndex: Self.ddcSelector(for: display))
    }

    func currentVolume() async -> Int? {
        guard let display = await selectDisplay(preferredKey: nil) else { return nil }
        let result = await run(arguments: ["display", Self.ddcSelector(for: display), "get", "volume"])
        if result.success, let value = Self.parsePercent(from: result.output) {
            lastKnownVolumeByDisplay[display.displayKey] = value
            return value
        }
        return lastKnownVolumeByDisplay[display.displayKey]
    }

    func setBrightness(_ percent: Int, preferredKey: String? = nil) async -> M1DDCBrightnessWriteResult {
        let display = await selectDisplay(preferredKey: preferredKey)
        let clamped = min(100, max(0, percent))
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
        let firstResult = await setBrightness(clamped, for: display)
        if firstResult.success {
            return firstResult
        }

        guard let refreshed = await selectDisplay(preferredKey: preferredKey, forceRefresh: true) else {
            return firstResult
        }
        return await setBrightness(clamped, for: refreshed)
    }

    func setVolume(_ percent: Int, preferredKey: String? = nil) async -> (Bool, String) {
        let display = await selectDisplay(preferredKey: preferredKey)
        guard let display else { return (false, "Samsung S60UD display not found") }
        let clamped = min(100, max(0, percent))
        let result = await run(arguments: ["display", Self.ddcSelector(for: display), "set", "volume", "\(clamped)"])
        if result.success {
            lastKnownVolumeByDisplay[display.displayKey] = clamped
        }
        return (result.success, result.output)
    }

    func changeVolume(_ delta: Int, preferredKey: String? = nil) async -> (Bool, String) {
        let display = await selectDisplay(preferredKey: preferredKey)
        guard let display else { return (false, "Samsung S60UD display not found") }
        let result = await run(arguments: ["display", Self.ddcSelector(for: display), "chg", "volume", "\(delta)"])
        if result.success {
            let base = lastKnownVolumeByDisplay[display.displayKey] ?? 50
            lastKnownVolumeByDisplay[display.displayKey] = min(100, max(0, base + delta))
        }
        return (result.success, result.output)
    }

    func setMute(_ enabled: Bool, preferredKey: String? = nil) async -> (Bool, String) {
        let display = await selectDisplay(preferredKey: preferredKey)
        guard let display else { return (false, "Samsung S60UD display not found") }
        let result = await run(arguments: ["display", Self.ddcSelector(for: display), "set", "mute", enabled ? "on" : "off"])
        if result.success {
            lastKnownVolumeByDisplay[display.displayKey] = enabled ? 0 : (lastKnownVolumeByDisplay[display.displayKey] ?? 50)
        }
        return (result.success, result.output)
    }

    private func selectDisplay(preferredKey: String?, forceRefresh: Bool = false) async -> ExternalDisplayInfo? {
        if
            !forceRefresh,
            let currentDisplayInfo,
            preferredKey == nil || preferredKey == currentDisplayInfo.displayKey
        {
            return currentDisplayInfo
        }

        let displays = await discoverDisplays(forceRefresh: forceRefresh || preferredKey != nil)
        guard !displays.isEmpty else {
            currentDisplayInfo = nil
            return nil
        }

        if let preferredKey, let preferred = displays.first(where: { $0.displayKey == preferredKey }) {
            currentDisplayInfo = preferred
            return preferred
        }

        if let currentDisplayInfo, let matched = displays.first(where: { $0.displayKey == currentDisplayInfo.displayKey }) {
            self.currentDisplayInfo = matched
            return matched
        }

        currentDisplayInfo = displays[0]
        return displays[0]
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
        if let systemUUID = display.systemUUID, !systemUUID.isEmpty {
            return "uuid:\(systemUUID)"
        }
        if let displayID = display.displayID {
            return "id:\(displayID)"
        }
        return display.displayIndex
    }

    private func discoverDisplays(forceRefresh: Bool) async -> [ExternalDisplayInfo] {
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

        let result = await run(arguments: ["display", "list", "detailed"])
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

    static func isSupportedTargetDisplay(
        vendorID: UInt32,
        productID: UInt32,
        isBuiltin: Bool
    ) -> Bool {
        !isBuiltin && vendorID == targetVendorID && productID == targetProductID
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
                // m1ddc accepts a stable display-ID selector even when its
                // numeric list index is unavailable or changes between boots.
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

    private func setBrightness(_ clamped: Int, for display: ExternalDisplayInfo) async -> M1DDCBrightnessWriteResult {
        let selector = Self.ddcSelector(for: display)
        let beforeSample = await readBrightnessSample(displayIndex: selector)
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
        let result = await run(arguments: ["display", selector, "set", "luminance", "\(computedRawTarget)"])
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

        try? await Task.sleep(nanoseconds: 500_000_000)
        let afterSample = await readBrightnessSample(displayIndex: selector)
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

    private func run(arguments: [String]) async -> M1DDCCommandResult {
        guard let executableURL = self.executableURL else {
            return M1DDCCommandResult(success: false, output: "m1ddc not found")
        }

        return await withCheckedContinuation { continuation in
            let rGuard = ResumeGuard()
            
            @Sendable func safeResume(with result: M1DDCCommandResult) {
                if rGuard.shouldResume() {
                    continuation.resume(returning: result)
                }
            }

            workQueue.async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

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
                    
                    let success = process.terminationStatus == 0
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
    }

    private func readBrightness(displayIndex: String) async -> Int? {
        guard let sample = await readBrightnessRaw(displayIndex: displayIndex) else { return nil }
        guard let rawCurrent = sample.rawCurrent, let rawMax = sample.rawMax else { return nil }
        return DDCBrightnessScale.uiPercent(fromRawCurrent: rawCurrent, rawMax: rawMax)
    }

    private func readBrightnessSample(displayIndex: String) async -> DDCBrightnessRawSample? {
        await readBrightnessRaw(displayIndex: displayIndex)
    }

    private func readBrightnessRaw(displayIndex: String) async -> DDCBrightnessRawSample? {
        let result = await run(arguments: ["display", displayIndex, "get", "luminance"])
        guard result.success else { return nil }
        let sample = DDCBrightnessParsing.parseRawSample(from: result.output)
        if sample.rawMax != nil {
            return sample
        }

        let maxResult = await run(arguments: ["display", displayIndex, "max", "luminance"])
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
        
        return samsungDisplays.sorted { a, b in
            let aIsS60 = targetMonitorNames.contains { a.productName.localizedCaseInsensitiveContains($0) }
            let bIsS60 = targetMonitorNames.contains { b.productName.localizedCaseInsensitiveContains($0) }
            if aIsS60 != bIsS60 { return aIsS60 } 
            return a.displayIndex < b.displayIndex
        }
    }

}
