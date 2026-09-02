import CoreGraphics
import Darwin
import Foundation

enum DisplayDiscoveryPipelineClassification: String, CaseIterable, Equatable, Sendable {
    case m1ddcExecutableNotFound = "A_M1DDC_EXECUTABLE_NOT_FOUND"
    case m1ddcProcessFailed = "B_M1DDC_PROCESS_FAILED"
    case m1ddcOutputEmpty = "C_M1DDC_OUTPUT_EMPTY"
    case m1ddcParserRejectedDisplay = "D_M1DDC_PARSER_REJECTED_DISPLAY"
    case samsungNameFilterRejected = "E_SAMSUNG_NAME_FILTER_REJECTED"
    case coreGraphicsDoesNotSeeExternalDisplay = "F_COREGRAPHICS_DOES_NOT_SEE_EXTERNAL_DISPLAY"
    case coreGraphicsFingerprintMismatch = "G_COREGRAPHICS_FINGERPRINT_MISMATCH"
    case productionWriterReturnedNilDespiteDiscovery = "H_PRODUCTION_WRITER_RETURNED_NIL_DESPITE_DISCOVERY"
    case softwareDisconnectStatePersisted = "I_SOFTWARE_DISCONNECT_STATE_PERSISTED"
    case legacyRuntimeConflict = "J_LEGACY_RUNTIME_CONFLICT"
    case displayDiscoverySucceeded = "K_DISPLAY_DISCOVERY_SUCCEEDED"
    case unknown = "UNKNOWN"
}

struct DisplayDiscoveryClassificationInput: Equatable, Sendable {
    let m1ddcExecutableSelected: Bool
    let m1ddcProcessRan: Bool
    let m1ddcProcessSucceeded: Bool
    let m1ddcTimedOut: Bool
    let m1ddcOutputEmpty: Bool
    let rawDisplayCount: Int
    let allParsedDisplayCount: Int
    let externalParsedDisplayCount: Int
    let samsungFilteredDisplayCount: Int
    let coreGraphicsExternalDisplayCount: Int
    let coreGraphicsFingerprintMatchCount: Int
    let softwareDisconnectStatePersisted: Bool
    let legacyRuntimeConflict: Bool
    let productionWriterReturnedDisplay: Bool
}

enum DisplayDiscoveryPipelineClassifier {
    static func classify(
        _ input: DisplayDiscoveryClassificationInput
    ) -> [DisplayDiscoveryPipelineClassification] {
        var classifications: [DisplayDiscoveryPipelineClassification] = []

        if !input.m1ddcExecutableSelected {
            classifications.append(.m1ddcExecutableNotFound)
        }

        if input.m1ddcProcessRan &&
            (!input.m1ddcProcessSucceeded || input.m1ddcTimedOut)
        {
            classifications.append(.m1ddcProcessFailed)
        }

        if input.m1ddcProcessRan && input.m1ddcOutputEmpty {
            classifications.append(.m1ddcOutputEmpty)
        }

        if input.m1ddcProcessRan && input.m1ddcProcessSucceeded &&
            input.rawDisplayCount > 0 && input.allParsedDisplayCount == 0
        {
            classifications.append(.m1ddcParserRejectedDisplay)
        }

        if input.m1ddcProcessRan && input.m1ddcProcessSucceeded &&
            input.allParsedDisplayCount > 0 &&
            input.externalParsedDisplayCount > 0 &&
            input.samsungFilteredDisplayCount == 0
        {
            classifications.append(.samsungNameFilterRejected)
        }

        if input.coreGraphicsExternalDisplayCount == 0 {
            classifications.append(.coreGraphicsDoesNotSeeExternalDisplay)
        } else if input.coreGraphicsFingerprintMatchCount == 0 {
            classifications.append(.coreGraphicsFingerprintMismatch)
        }

        let discoveryEvidence = input.samsungFilteredDisplayCount > 0 ||
            input.coreGraphicsFingerprintMatchCount > 0
        if discoveryEvidence && !input.productionWriterReturnedDisplay {
            classifications.append(.productionWriterReturnedNilDespiteDiscovery)
        }

        if input.softwareDisconnectStatePersisted {
            classifications.append(.softwareDisconnectStatePersisted)
        }

        if input.legacyRuntimeConflict {
            classifications.append(.legacyRuntimeConflict)
        }

        if input.productionWriterReturnedDisplay {
            classifications.append(.displayDiscoverySucceeded)
        }

        return classifications.isEmpty ? [.unknown] : classifications
    }
}

struct DisplayDiscoveryDiagnostic {
    static let reportRelativePath = "display_discovery_diagnostic.md"

    private static let m1ddcArguments = ["display", "list", "detailed"]
    private static let processTimeout: TimeInterval = 5.0
    private static let legacyAmbientSyncLabel = "fyi.kadir.AmbientSync"
    private static let softwareDisconnectDefaultsKey = DisplayConnectionIntentMigration.memWatchDefaultsKey
    private static let legacySoftwareDisconnectDefaultsKey = DisplayConnectionIntentMigration.legacyDefaultsKey
    private static let displayConnectionIntentMigrationVersionKey = DisplayConnectionIntentMigration.versionKey
    private static let legacyCleanupVersionKey = "MemWatch.LegacyAmbientSyncCleanupVersion"

    static func run() async {
        let reportURL = HiDPIReportPaths.reportURL(reportRelativePath)
        let measurement = await collectMeasurement()
        let report = buildReport(measurement: measurement, reportURL: reportURL)

        print(report, terminator: "")

        do {
            try FileManager.default.createDirectory(
                at: reportURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
        } catch {
            fputs(
                "Display discovery diagnostic report write failed: \(error)\n",
                stderr
            )
            exit(1)
        }
    }

    private struct ExecutableObservation {
        let path: String
        let exists: Bool
        let isExecutableFile: Bool
    }

    private struct ProcessResult: Sendable {
        let didRun: Bool
        let terminationStatus: Int32?
        let launchError: String?
        let stdout: String
        let stderr: String
        let timedOut: Bool

        var succeeded: Bool {
            didRun && terminationStatus == 0 && launchError == nil && !timedOut
        }

        var productionParserInput: String {
            (stdout + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedData = Data()

        func store(_ data: Data) {
            lock.lock()
            storedData = data
            lock.unlock()
        }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return storedData
        }
    }

    private struct CoreGraphicsDisplayList {
        let countResult: Int32
        let listResult: Int32?
        let displayIDs: [CGDirectDisplayID]
    }

    private struct CoreGraphicsDisplayMeasurement {
        let displayID: CGDirectDisplayID
        let vendorID: UInt32
        let productID: UInt32
        let serialNumber: UInt32
        let isBuiltin: Bool
        let isOnline: Bool
        let isActive: Bool
        let bounds: String
        let currentModeWidth: String
        let currentModeHeight: String
        let pixelWidth: String
        let pixelHeight: String
        let refreshRate: String

        var fingerprintMatches: Bool {
            M1DDCWriter.isSupportedTargetDisplay(
                vendorID: vendorID,
                productID: productID,
                isBuiltin: isBuiltin
            )
        }
    }

    private struct CoreGraphicsMeasurement {
        let online: CoreGraphicsDisplayList
        let active: CoreGraphicsDisplayList
        let detailsByID: [CGDirectDisplayID: CoreGraphicsDisplayMeasurement]

        var externalDisplayCount: Int {
            detailsByID.values.filter { !$0.isBuiltin }.count
        }

        var fingerprintMatchCount: Int {
            detailsByID.values.filter(\.fingerprintMatches).count
        }
    }

    private struct PrivateBackendMeasurement {
        let available: Bool
        let displayIDs: [CGDirectDisplayID]
        let enumerationError: String?
    }

    private struct PersistedStateMeasurement {
        let softwareDisconnectRawValue: String
        let softwareDisconnectRequested: Bool
        let legacySoftwareDisconnectRawValue: String
        let legacySoftwareDisconnectRequested: Bool
        let displayConnectionIntentMigrationVersionRawValue: String
        let displayConnectionIntentMigrationVersion: Int
        let legacyCleanupVersionRawValue: String
        let legacyCleanupVersion: Int
        let currentPreferencesDataByteCount: Int?
        let currentPreferences: AppPreferences?
        let currentPreferencesDecodeError: String?
        let legacyPreferencesDataByteCount: Int?
        let legacyPreferences: AppPreferences?
        let legacyPreferencesDecodeError: String?
        let currentDisplayRelatedDefaults: [(String, String)]
        let legacyDisplayRelatedDefaults: [(String, String)]
    }

    private struct DiagnosticMeasurement {
        let bundleIdentifier: String
        let executableURL: String
        let processUID: UInt32
        let home: String
        let path: String
        let executableObservations: [ExecutableObservation]
        let selectedExecutableURL: URL?
        let rawM1DDC: ProcessResult?
        let rawParserInput: String
        let rawDisplayCount: Int
        let parsedDisplays: M1DDCDisplayParseResult
        let rawSelectedDisplay: ExternalDisplayInfo?
        let coreGraphics: CoreGraphicsMeasurement
        let privateBackend: PrivateBackendMeasurement
        let persistedState: PersistedStateMeasurement
        let legacyLaunchAgentURL: String
        let legacyLaunchAgentExists: Bool
        let legacyServiceTarget: String
        let legacyRuntimeProbe: ProcessResult?
        let productionM1DDCAvailable: Bool
        let preferredKey: String?
        let productionDisplay: ExternalDisplayInfo?
        let productionCurrentDisplayInfo: ExternalDisplayInfo?
        let classifications: [DisplayDiscoveryPipelineClassification]
        let reportGeneratedAt: Date
    }

    private static func collectMeasurement() async -> DiagnosticMeasurement {
        let environment = ProcessInfo.processInfo.environment
        let fileManager = FileManager.default
        let executableObservations = M1DDCExecutableLocator.defaultCandidates.map { path in
            ExecutableObservation(
                path: path,
                exists: fileManager.fileExists(atPath: path),
                isExecutableFile: fileManager.isExecutableFile(atPath: path)
            )
        }
        let selectedExecutableURL = M1DDCExecutableLocator().locate()

        let rawM1DDC: ProcessResult?
        if let selectedExecutableURL {
            rawM1DDC = await runProcess(
                executableURL: selectedExecutableURL,
                arguments: m1ddcArguments,
                timeout: processTimeout
            )
        } else {
            rawM1DDC = nil
        }

        let rawParserInput = rawM1DDC?.productionParserInput ?? ""
        let parsedDisplays = M1DDCWriter.parseDisplaysForDiagnostics(rawParserInput)
        let rawDisplayCount = countRawDisplays(in: rawParserInput)
        let persistedState = readPersistedState()
        let coreGraphics = captureCoreGraphics()
        let privateBackend = capturePrivateBackend()

        let legacyLaunchAgentURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(legacyAmbientSyncLabel).plist")
        let legacyLaunchAgentExists = fileManager.fileExists(atPath: legacyLaunchAgentURL.path)
        let legacyServiceTarget = "gui/\(getuid())/\(legacyAmbientSyncLabel)"
        let legacyRuntimeProbe: ProcessResult?
        let launchctlURL = URL(fileURLWithPath: "/bin/launchctl")
        if fileManager.isExecutableFile(atPath: launchctlURL.path) {
            legacyRuntimeProbe = await runProcess(
                executableURL: launchctlURL,
                arguments: ["print", legacyServiceTarget],
                timeout: processTimeout
            )
        } else {
            legacyRuntimeProbe = nil
        }

        let writer = M1DDCWriter()
        let productionM1DDCAvailable = await writer.isAvailable(refresh: true)
        let preferredKey = persistedState.currentPreferences?.selectedDisplayKey
        let productionDisplay = await writer.refreshDisplay(preferredKey: preferredKey)
        let productionCurrentDisplayInfo = await writer.currentDisplayInfo
        let rawSelectedDisplay = selectDisplay(
            from: parsedDisplays.samsungFilteredDisplays,
            preferredKey: preferredKey
        )

        let classifications = DisplayDiscoveryPipelineClassifier.classify(
            DisplayDiscoveryClassificationInput(
                m1ddcExecutableSelected: selectedExecutableURL != nil,
                m1ddcProcessRan: rawM1DDC?.didRun == true,
                m1ddcProcessSucceeded: rawM1DDC?.succeeded == true,
                m1ddcTimedOut: rawM1DDC?.timedOut == true,
                m1ddcOutputEmpty: rawM1DDC?.productionParserInput.isEmpty == true,
                rawDisplayCount: rawDisplayCount,
                allParsedDisplayCount: parsedDisplays.allDisplays.count,
                externalParsedDisplayCount: parsedDisplays.externalDisplays.count,
                samsungFilteredDisplayCount: parsedDisplays.samsungFilteredDisplays.count,
                coreGraphicsExternalDisplayCount: coreGraphics.externalDisplayCount,
                coreGraphicsFingerprintMatchCount: coreGraphics.fingerprintMatchCount,
                softwareDisconnectStatePersisted: persistedState.softwareDisconnectRequested,
                legacyRuntimeConflict: legacyRuntimeProbe?.succeeded == true,
                productionWriterReturnedDisplay: productionDisplay != nil
            )
        )

        return DiagnosticMeasurement(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "nil",
            executableURL: Bundle.main.executableURL?.path ?? "nil",
            processUID: getuid(),
            home: environment["HOME"] ?? "nil",
            path: environment["PATH"] ?? "nil",
            executableObservations: executableObservations,
            selectedExecutableURL: selectedExecutableURL,
            rawM1DDC: rawM1DDC,
            rawParserInput: rawParserInput,
            rawDisplayCount: rawDisplayCount,
            parsedDisplays: parsedDisplays,
            rawSelectedDisplay: rawSelectedDisplay,
            coreGraphics: coreGraphics,
            privateBackend: privateBackend,
            persistedState: persistedState,
            legacyLaunchAgentURL: legacyLaunchAgentURL.path,
            legacyLaunchAgentExists: legacyLaunchAgentExists,
            legacyServiceTarget: legacyServiceTarget,
            legacyRuntimeProbe: legacyRuntimeProbe,
            productionM1DDCAvailable: productionM1DDCAvailable,
            preferredKey: preferredKey,
            productionDisplay: productionDisplay,
            productionCurrentDisplayInfo: productionCurrentDisplayInfo,
            classifications: classifications,
            reportGeneratedAt: Date()
        )
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(
                    returning: runProcessSynchronously(
                        executableURL: executableURL,
                        arguments: arguments,
                        timeout: timeout
                    )
                )
            }
        }
    }

    private static func runProcessSynchronously(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(
                didRun: false,
                terminationStatus: nil,
                launchError: String(describing: error),
                stdout: "",
                stderr: "",
                timedOut: false
            )
        }

        let stdoutData = DataBox()
        let stderrData = DataBox()
        let stdoutReader = DispatchWorkItem {
            stdoutData.store(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        }
        let stderrReader = DispatchWorkItem {
            stderrData.store(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        }
        DispatchQueue.global(qos: .utility).async(execute: stdoutReader)
        DispatchQueue.global(qos: .utility).async(execute: stderrReader)

        var timedOut = false
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if timedOut {
            let terminationDeadline = Date().addingTimeInterval(1.0)
            while process.isRunning && Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        stdoutReader.wait()
        stderrReader.wait()

        return ProcessResult(
            didRun: true,
            terminationStatus: process.terminationStatus,
            launchError: nil,
            stdout: String(decoding: stdoutData.data, as: UTF8.self),
            stderr: String(decoding: stderrData.data, as: UTF8.self),
            timedOut: timedOut
        )
    }

    private static func countRawDisplays(in output: String) -> Int {
        output.split(whereSeparator: \.isNewline).reduce(into: 0) { count, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") {
                count += 1
            }
        }
    }

    private static func selectDisplay(
        from displays: [ExternalDisplayInfo],
        preferredKey: String?
    ) -> ExternalDisplayInfo? {
        if let preferredKey, let preferred = displays.first(where: { $0.displayKey == preferredKey }) {
            return preferred
        }
        return displays.first
    }

    private typealias DisplayListGetter = @convention(c) (
        UInt32,
        UnsafeMutablePointer<CGDirectDisplayID>?,
        UnsafeMutablePointer<UInt32>?
    ) -> CGError

    private static func captureCoreGraphics() -> CoreGraphicsMeasurement {
        let online = captureDisplayList(using: CGGetOnlineDisplayList)
        let active = captureDisplayList(using: CGGetActiveDisplayList)
        let allIDs = Set(online.displayIDs + active.displayIDs)
        var detailsByID: [CGDirectDisplayID: CoreGraphicsDisplayMeasurement] = [:]
        for displayID in allIDs {
            detailsByID[displayID] = captureDisplayMeasurement(displayID: displayID)
        }
        return CoreGraphicsMeasurement(
            online: online,
            active: active,
            detailsByID: detailsByID
        )
    }

    private static func captureDisplayList(
        using getter: DisplayListGetter
    ) -> CoreGraphicsDisplayList {
        var count: UInt32 = 0
        let countResult = getter(0, nil, &count)
        guard countResult == .success else {
            return CoreGraphicsDisplayList(
                countResult: countResult.rawValue,
                listResult: nil,
                displayIDs: []
            )
        }
        guard count > 0 else {
            return CoreGraphicsDisplayList(
                countResult: countResult.rawValue,
                listResult: nil,
                displayIDs: []
            )
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let listResult = displayIDs.withUnsafeMutableBufferPointer { buffer in
            getter(count, buffer.baseAddress, &count)
        }
        guard listResult == .success else {
            return CoreGraphicsDisplayList(
                countResult: countResult.rawValue,
                listResult: listResult.rawValue,
                displayIDs: []
            )
        }
        return CoreGraphicsDisplayList(
            countResult: countResult.rawValue,
            listResult: listResult.rawValue,
            displayIDs: Array(displayIDs.prefix(Int(count)))
        )
    }

    private static func captureDisplayMeasurement(
        displayID: CGDirectDisplayID
    ) -> CoreGraphicsDisplayMeasurement {
        let bounds = CGDisplayBounds(displayID)
        let mode = CGDisplayCopyDisplayMode(displayID)
        return CoreGraphicsDisplayMeasurement(
            displayID: displayID,
            vendorID: CGDisplayVendorNumber(displayID),
            productID: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID),
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
            isOnline: CGDisplayIsOnline(displayID) != 0,
            isActive: CGDisplayIsActive(displayID) != 0,
            bounds: "origin=(\(bounds.origin.x), \(bounds.origin.y)) size=(\(bounds.size.width), \(bounds.size.height))",
            currentModeWidth: mode.map { String($0.width) } ?? "nil",
            currentModeHeight: mode.map { String($0.height) } ?? "nil",
            pixelWidth: mode.map { String($0.pixelWidth) } ?? "nil",
            pixelHeight: mode.map { String($0.pixelHeight) } ?? "nil",
            refreshRate: mode.map { String(format: "%.3f Hz", $0.refreshRate) } ?? "nil"
        )
    }

    private static func capturePrivateBackend() -> PrivateBackendMeasurement {
        let backend = PrivateDisplayConnectionBackend()
        guard backend.isAvailable else {
            return PrivateBackendMeasurement(
                available: false,
                displayIDs: [],
                enumerationError: nil
            )
        }

        do {
            return PrivateBackendMeasurement(
                available: true,
                displayIDs: try backend.allDisplayIDs(),
                enumerationError: nil
            )
        } catch {
            return PrivateBackendMeasurement(
                available: true,
                displayIDs: [],
                enumerationError: String(describing: error)
            )
        }
    }

    private static func readPersistedState() -> PersistedStateMeasurement {
        let defaults = UserDefaults.standard
        let legacyDefaults = UserDefaults(suiteName: DisplayPreferencesMigration.legacySuiteName)
        let softwareDisconnectValue = defaults.object(forKey: softwareDisconnectDefaultsKey)
        let legacySoftwareDisconnectValue = legacyDefaults?.object(forKey: legacySoftwareDisconnectDefaultsKey)
        let displayConnectionIntentMigrationVersionValue = defaults.object(
            forKey: displayConnectionIntentMigrationVersionKey
        )
        let legacyCleanupVersionValue = defaults.object(forKey: legacyCleanupVersionKey)

        let currentPreferencesData = defaults.data(forKey: AppPreferences.storageKey)
        let currentPreferencesDecoded = decodePreferences(currentPreferencesData)

        let legacyPreferencesData = legacyDefaults?.data(forKey: AppPreferences.storageKey)
        let legacyPreferencesDecoded = decodePreferences(legacyPreferencesData)

        let currentDomain = Bundle.main.bundleIdentifier
            .flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        let legacyDomain = legacyDefaults?.persistentDomain(
            forName: DisplayPreferencesMigration.legacySuiteName
        ) ?? [:]

        return PersistedStateMeasurement(
            softwareDisconnectRawValue: persistedValueDescription(softwareDisconnectValue),
            softwareDisconnectRequested: defaults.bool(forKey: softwareDisconnectDefaultsKey),
            legacySoftwareDisconnectRawValue: persistedValueDescription(legacySoftwareDisconnectValue),
            legacySoftwareDisconnectRequested: legacyDefaults?.bool(forKey: legacySoftwareDisconnectDefaultsKey) == true,
            displayConnectionIntentMigrationVersionRawValue: persistedValueDescription(
                displayConnectionIntentMigrationVersionValue
            ),
            displayConnectionIntentMigrationVersion: defaults.integer(forKey: displayConnectionIntentMigrationVersionKey),
            legacyCleanupVersionRawValue: persistedValueDescription(legacyCleanupVersionValue),
            legacyCleanupVersion: defaults.integer(forKey: legacyCleanupVersionKey),
            currentPreferencesDataByteCount: currentPreferencesData?.count,
            currentPreferences: currentPreferencesDecoded.preferences,
            currentPreferencesDecodeError: currentPreferencesDecoded.error,
            legacyPreferencesDataByteCount: legacyPreferencesData?.count,
            legacyPreferences: legacyPreferencesDecoded.preferences,
            legacyPreferencesDecodeError: legacyPreferencesDecoded.error,
            currentDisplayRelatedDefaults: displayRelatedDefaults(from: currentDomain),
            legacyDisplayRelatedDefaults: displayRelatedDefaults(from: legacyDomain)
        )
    }

    private static func decodePreferences(
        _ data: Data?
    ) -> (preferences: AppPreferences?, error: String?) {
        guard let data else { return (nil, nil) }
        do {
            return (try JSONDecoder().decode(AppPreferences.self, from: data), nil)
        } catch {
            return (nil, String(describing: error))
        }
    }

    private static func persistedValueDescription(_ value: Any?) -> String {
        guard let value else { return "nil" }
        if let data = value as? Data {
            return "Data(\(data.count) bytes)"
        }
        return String(describing: value)
    }

    private static func displayRelatedDefaults(
        from domain: [String: Any]
    ) -> [(String, String)] {
        domain.keys
            .filter { key in
                let lower = key.lowercased()
                return lower.contains("display") ||
                    lower.contains("ambient") ||
                    lower.contains("hidpi")
            }
            .sorted()
            .map { key in
                (key, persistedValueDescription(domain[key]))
            }
    }

    private struct ReportBuilder {
        var content = ""

        mutating func line(_ value: String = "") {
            content.append(value)
            content.append("\n")
        }

        mutating func rawSection(
            _ label: String,
            value: String?,
            byteCount: Int? = nil
        ) {
            if let byteCount {
                line("\(label)_BYTE_COUNT = \(byteCount)")
            }
            line("\(label)_BEGIN")
            if let value {
                if value.isEmpty {
                    line("(empty)")
                } else {
                    content.append(value)
                    if !value.hasSuffix("\n") {
                        content.append("\n")
                    }
                }
            } else {
                line("(not run)")
            }
            line("\(label)_END")
        }
    }

    private static func buildReport(
        measurement: DiagnosticMeasurement,
        reportURL: URL
    ) -> String {
        var report = ReportBuilder()
        report.line("# MemWatch Display Discovery Diagnostic")
        report.line("REPORT_PATH = \(reportURL.path)")
        report.line(
            "GENERATED_AT_UTC = \(ISO8601DateFormatter().string(from: measurement.reportGeneratedAt))"
        )
        report.line()

        report.line("## PROCESS / EXECUTABLE")
        report.line("Bundle.main.bundleIdentifier = \(measurement.bundleIdentifier)")
        report.line("Bundle.main.executableURL = \(measurement.executableURL)")
        report.line("PROCESS_UID = \(measurement.processUID)")
        report.line("HOME = \(measurement.home)")
        report.line("PATH = \(measurement.path)")
        report.line()
        report.line("M1DDC_CANDIDATE_COUNT = \(measurement.executableObservations.count)")
        for (index, observation) in measurement.executableObservations.enumerated() {
            report.line("M1DDC_CANDIDATE[\(index)].PATH = \(observation.path)")
            report.line("M1DDC_CANDIDATE[\(index)].EXISTS = \(bool(observation.exists))")
            report.line(
                "M1DDC_CANDIDATE[\(index)].IS_EXECUTABLE_FILE = \(bool(observation.isExecutableFile))"
            )
            report.line(
                "M1DDC_CANDIDATE[\(index)].SELECTED = \(bool(measurement.selectedExecutableURL?.path == observation.path))"
            )
        }
        report.line(
            "M1DDC_SELECTED_EXECUTABLE_URL = \(measurement.selectedExecutableURL?.path ?? "nil")"
        )
        report.line()

        report.line("## RAW M1DDC")
        report.line("M1DDC_COMMAND = m1ddc display list detailed")
        report.line("M1DDC_PROCESS_RAN = \(bool(measurement.rawM1DDC?.didRun == true))")
        if let rawM1DDC = measurement.rawM1DDC {
            report.line(
                "M1DDC_TERMINATION_STATUS = \(rawM1DDC.terminationStatus.map(String.init) ?? "nil")"
            )
            report.line("M1DDC_LAUNCH_ERROR = \(rawM1DDC.launchError ?? "nil")")
            report.line("M1DDC_TIMEOUT = \(bool(rawM1DDC.timedOut))")
            report.rawSection(
                "M1DDC_STDOUT_RAW",
                value: rawM1DDC.stdout,
                byteCount: rawM1DDC.stdout.utf8.count
            )
            report.rawSection(
                "M1DDC_STDERR_RAW",
                value: rawM1DDC.stderr,
                byteCount: rawM1DDC.stderr.utf8.count
            )
        } else {
            report.line("M1DDC_TERMINATION_STATUS = not-run")
            report.line("M1DDC_LAUNCH_ERROR = not-run (no selected executable)")
            report.line("M1DDC_TIMEOUT = not-run")
            report.rawSection("M1DDC_STDOUT_RAW", value: nil)
            report.rawSection("M1DDC_STDERR_RAW", value: nil)
        }
        report.line("M1DDC_PARSER_INPUT = stdout + stderr, production trim semantics")
        report.rawSection(
            "M1DDC_PARSER_INPUT_RAW",
            value: measurement.rawParserInput,
            byteCount: measurement.rawParserInput.utf8.count
        )
        report.line("RAW_DISPLAY_COUNT = \(measurement.rawDisplayCount)")
        report.line()

        report.line("### ALL_PARSED_DISPLAYS = \(measurement.parsedDisplays.allDisplays.count)")
        appendDisplays(
            measurement.parsedDisplays.allDisplays,
            label: "ALL_PARSED_DISPLAY",
            to: &report
        )
        report.line()
        report.line(
            "### EXTERNAL_PARSED_DISPLAYS = \(measurement.parsedDisplays.externalDisplays.count)"
        )
        appendDisplays(
            measurement.parsedDisplays.externalDisplays,
            label: "EXTERNAL_PARSED_DISPLAY",
            to: &report
        )
        report.line()
        report.line(
            "### SAMSUNG_FILTERED_DISPLAYS = \(measurement.parsedDisplays.samsungFilteredDisplays.count)"
        )
        appendDisplays(
            measurement.parsedDisplays.samsungFilteredDisplays,
            label: "SAMSUNG_FILTERED_DISPLAY",
            to: &report
        )
        report.line()
        if let rawSelectedDisplay = measurement.rawSelectedDisplay {
            report.line("SELECTED_DISPLAY = non-nil")
            appendDisplay(rawSelectedDisplay, label: "SELECTED_DISPLAY", index: nil, to: &report)
        } else {
            report.line("SELECTED_DISPLAY = nil")
        }
        report.line()

        report.line("## COREGRAPHICS")
        report.line(
            "TARGET_VENDOR_DECIMAL = \(M1DDCWriter.targetVendorIDForDiagnostics)"
        )
        report.line(
            "TARGET_VENDOR_HEX = \(hex(M1DDCWriter.targetVendorIDForDiagnostics))"
        )
        report.line(
            "TARGET_PRODUCT_DECIMAL = \(M1DDCWriter.targetProductIDForDiagnostics)"
        )
        report.line(
            "TARGET_PRODUCT_HEX = \(hex(M1DDCWriter.targetProductIDForDiagnostics))"
        )
        appendCoreGraphicsList(
            measurement.coreGraphics.online,
            label: "CGGetOnlineDisplayList",
            detailsByID: measurement.coreGraphics.detailsByID,
            to: &report
        )
        report.line()
        appendCoreGraphicsList(
            measurement.coreGraphics.active,
            label: "CGGetActiveDisplayList",
            detailsByID: measurement.coreGraphics.detailsByID,
            to: &report
        )
        report.line()
        report.line(
            "COREGRAPHICS_EXTERNAL_DISPLAY_COUNT = \(measurement.coreGraphics.externalDisplayCount)"
        )
        report.line(
            "COREGRAPHICS_FINGERPRINT_MATCH_COUNT = \(measurement.coreGraphics.fingerprintMatchCount)"
        )
        report.line()

        report.line("## PRIVATE DISPLAY BACKEND")
        report.line("PRIVATE_BACKEND_AVAILABLE = \(bool(measurement.privateBackend.available))")
        if let enumerationError = measurement.privateBackend.enumerationError {
            report.line("PRIVATE_BACKEND_ENUMERATION_ERROR = \(enumerationError)")
        }
        report.line(
            "PRIVATE_BACKEND_DISPLAY_ID_COUNT = \(measurement.privateBackend.displayIDs.count)"
        )
        for (index, displayID) in measurement.privateBackend.displayIDs.enumerated() {
            appendPrivateDisplay(displayID, index: index, to: &report)
        }
        report.line()

        report.line("## USERDEFAULTS / PERSISTED STATE")
        report.line(
            "SOFTWARE_DISCONNECT_DEFAULTS_KEY = \(softwareDisconnectDefaultsKey)"
        )
        report.line(
            "SOFTWARE_DISCONNECT_DEFAULTS_VALUE = \(measurement.persistedState.softwareDisconnectRawValue)"
        )
        report.line(
            "SOFTWARE_DISCONNECT_STATE_PERSISTED = \(bool(measurement.persistedState.softwareDisconnectRequested))"
        )
        report.line(
            "LEGACY_SOFTWARE_DISCONNECT_DEFAULTS_KEY = \(legacySoftwareDisconnectDefaultsKey)"
        )
        report.line(
            "LEGACY_SOFTWARE_DISCONNECT_DEFAULTS_VALUE = \(measurement.persistedState.legacySoftwareDisconnectRawValue)"
        )
        report.line(
            "LEGACY_SOFTWARE_DISCONNECT_STATE_PERSISTED = \(bool(measurement.persistedState.legacySoftwareDisconnectRequested))"
        )
        report.line(
            "DISPLAY_CONNECTION_INTENT_MIGRATION_VERSION_KEY = \(displayConnectionIntentMigrationVersionKey)"
        )
        report.line(
            "DISPLAY_CONNECTION_INTENT_MIGRATION_VERSION_VALUE = \(measurement.persistedState.displayConnectionIntentMigrationVersionRawValue)"
        )
        report.line(
            "DISPLAY_CONNECTION_INTENT_MIGRATION_VERSION_INTEGER = \(measurement.persistedState.displayConnectionIntentMigrationVersion)"
        )
        report.line("LEGACY_CLEANUP_VERSION_KEY = \(legacyCleanupVersionKey)")
        report.line(
            "LEGACY_CLEANUP_VERSION_VALUE = \(measurement.persistedState.legacyCleanupVersionRawValue)"
        )
        report.line(
            "LEGACY_CLEANUP_VERSION_INTEGER = \(measurement.persistedState.legacyCleanupVersion)"
        )
        appendPreferences(
            label: "AMBIENTSYNC_STORE",
            storageKey: AppPreferences.storageKey,
            dataByteCount: measurement.persistedState.currentPreferencesDataByteCount,
            preferences: measurement.persistedState.currentPreferences,
            decodeError: measurement.persistedState.currentPreferencesDecodeError,
            to: &report
        )
        appendPreferences(
            label: "LEGACY_AMBIENTSYNC_STORE",
            storageKey: AppPreferences.storageKey,
            dataByteCount: measurement.persistedState.legacyPreferencesDataByteCount,
            preferences: measurement.persistedState.legacyPreferences,
            decodeError: measurement.persistedState.legacyPreferencesDecodeError,
            to: &report
        )
        appendDefaults(
            measurement.persistedState.currentDisplayRelatedDefaults,
            label: "CURRENT_DISPLAY_RELATED_DEFAULT",
            to: &report
        )
        appendDefaults(
            measurement.persistedState.legacyDisplayRelatedDefaults,
            label: "LEGACY_DISPLAY_RELATED_DEFAULT",
            to: &report
        )
        report.line()

        report.line("## LEGACY RUNTIME PROBE (READ-ONLY)")
        report.line("LEGACY_LAUNCH_AGENT_PATH = \(measurement.legacyLaunchAgentURL)")
        report.line("LEGACY_LAUNCH_AGENT_EXISTS = \(bool(measurement.legacyLaunchAgentExists))")
        report.line("LEGACY_RUNTIME_SERVICE_TARGET = \(measurement.legacyServiceTarget)")
        if let legacyRuntimeProbe = measurement.legacyRuntimeProbe {
            report.line("LEGACY_RUNTIME_PROBE_RAN = \(bool(legacyRuntimeProbe.didRun))")
            report.line(
                "LEGACY_RUNTIME_PROBE_TERMINATION_STATUS = \(legacyRuntimeProbe.terminationStatus.map(String.init) ?? "nil")"
            )
            report.line(
                "LEGACY_RUNTIME_PROBE_LAUNCH_ERROR = \(legacyRuntimeProbe.launchError ?? "nil")"
            )
            report.line("LEGACY_RUNTIME_PROBE_TIMEOUT = \(bool(legacyRuntimeProbe.timedOut))")
            report.line(
                "LEGACY_RUNTIME_SERVICE_LOADED = \(bool(legacyRuntimeProbe.succeeded))"
            )
            report.rawSection(
                "LEGACY_RUNTIME_PROBE_STDOUT_RAW",
                value: legacyRuntimeProbe.stdout,
                byteCount: legacyRuntimeProbe.stdout.utf8.count
            )
            report.rawSection(
                "LEGACY_RUNTIME_PROBE_STDERR_RAW",
                value: legacyRuntimeProbe.stderr,
                byteCount: legacyRuntimeProbe.stderr.utf8.count
            )
        } else {
            report.line("LEGACY_RUNTIME_PROBE_RAN = false")
            report.line("LEGACY_RUNTIME_PROBE_TERMINATION_STATUS = not-run")
            report.line("LEGACY_RUNTIME_PROBE_LAUNCH_ERROR = not-run (/bin/launchctl unavailable)")
            report.line("LEGACY_RUNTIME_PROBE_TIMEOUT = not-run")
            report.line("LEGACY_RUNTIME_SERVICE_LOADED = false")
        }
        report.line()

        report.line("## PRODUCTION DISCOVERY RESULT")
        report.line("M1DDC_AVAILABLE = \(bool(measurement.productionM1DDCAvailable))")
        report.line("PREFERRED_KEY = \(measurement.preferredKey ?? "nil")")
        report.line(
            "REFRESH_DISPLAY_RESULT = \(measurement.productionDisplay == nil ? "nil" : "non-nil")"
        )
        if let productionCurrentDisplayInfo = measurement.productionCurrentDisplayInfo {
            report.line("CURRENT_DISPLAY_INFO = non-nil")
            appendDisplay(
                productionCurrentDisplayInfo,
                label: "CURRENT_DISPLAY_INFO",
                index: nil,
                to: &report
            )
        } else {
            report.line("CURRENT_DISPLAY_INFO = nil")
        }
        report.line()

        report.line("## PIPELINE CLASSIFICATION")
        report.line("CLASSIFICATION_COUNT = \(measurement.classifications.count)")
        for classification in measurement.classifications {
            report.line(classification.rawValue)
        }
        report.line()

        report.line("## SAFETY")
        report.line("DIAGNOSTIC_READ_ONLY = true")
        report.line("BRIGHTNESS_WRITE_PERFORMED = false")
        report.line("VOLUME_WRITE_PERFORMED = false")
        report.line("DISPLAY_MODE_CHANGED = false")
        report.line("HIDPI_ACTIVATION_PERFORMED = false")
        report.line("DISPLAY_DISCONNECT_RECONNECT_PERFORMED = false")
        report.line("USERDEFAULTS_WRITE_PERFORMED = false")
        report.line("MIGRATION_PERFORMED = false")

        return report.content
    }

    private static func appendDisplays(
        _ displays: [ExternalDisplayInfo],
        label: String,
        to report: inout ReportBuilder
    ) {
        if displays.isEmpty {
            report.line("\(label) = none")
            return
        }
        for (index, display) in displays.enumerated() {
            appendDisplay(display, label: label, index: index, to: &report)
        }
    }

    private static func appendDisplay(
        _ display: ExternalDisplayInfo,
        label: String,
        index: Int?,
        to report: inout ReportBuilder
    ) {
        let prefix = index.map { "\(label)[\($0)]" } ?? label
        report.line("\(prefix).displayIndex = \(display.displayIndex)")
        report.line("\(prefix).displayID = \(display.displayID.map(String.init) ?? "nil")")
        report.line("\(prefix).productName = \(display.productName)")
        report.line("\(prefix).serial = \(display.serial ?? "nil")")
        report.line("\(prefix).systemUUID = \(display.systemUUID ?? "nil")")
        report.line("\(prefix).ioLocation = \(display.ioLocation ?? "nil")")
        report.line("\(prefix).displayKey = \(display.displayKey)")
    }

    private static func appendCoreGraphicsList(
        _ list: CoreGraphicsDisplayList,
        label: String,
        detailsByID: [CGDirectDisplayID: CoreGraphicsDisplayMeasurement],
        to report: inout ReportBuilder
    ) {
        report.line("### \(label)")
        report.line("\(label).COUNT_QUERY_RESULT = \(list.countResult)")
        report.line("\(label).LIST_QUERY_RESULT = \(list.listResult.map(String.init) ?? "nil")")
        report.line("\(label).DISPLAY_COUNT = \(list.displayIDs.count)")
        if list.displayIDs.isEmpty {
            report.line("\(label).DISPLAY_IDS = none")
            return
        }
        for (index, displayID) in list.displayIDs.enumerated() {
            guard let details = detailsByID[displayID] else { continue }
            appendCoreGraphicsDisplay(details, label: label, index: index, to: &report)
        }
    }

    private static func appendCoreGraphicsDisplay(
        _ display: CoreGraphicsDisplayMeasurement,
        label: String,
        index: Int,
        to report: inout ReportBuilder
    ) {
        let prefix = "\(label)[\(index)]"
        report.line("\(prefix).numeric_displayID = \(display.displayID)")
        report.line("\(prefix).CGDisplayVendorNumber_DECIMAL = \(display.vendorID)")
        report.line("\(prefix).CGDisplayVendorNumber_HEX = \(hex(display.vendorID))")
        report.line("\(prefix).CGDisplayModelNumber_DECIMAL = \(display.productID)")
        report.line("\(prefix).CGDisplayModelNumber_HEX = \(hex(display.productID))")
        report.line("\(prefix).CGDisplaySerialNumber_DECIMAL = \(display.serialNumber)")
        report.line("\(prefix).CGDisplaySerialNumber_HEX = \(hex(display.serialNumber))")
        report.line("\(prefix).CGDisplayIsBuiltin = \(bool(display.isBuiltin))")
        report.line("\(prefix).CGDisplayIsOnline = \(bool(display.isOnline))")
        report.line("\(prefix).CGDisplayIsActive = \(bool(display.isActive))")
        report.line("\(prefix).bounds = \(display.bounds)")
        report.line("\(prefix).current_mode_width = \(display.currentModeWidth)")
        report.line("\(prefix).current_mode_height = \(display.currentModeHeight)")
        report.line("\(prefix).pixelWidth = \(display.pixelWidth)")
        report.line("\(prefix).pixelHeight = \(display.pixelHeight)")
        report.line("\(prefix).refreshRate = \(display.refreshRate)")
        report.line("\(prefix).FINGERPRINT_MATCH = \(bool(display.fingerprintMatches))")
    }

    private static func appendPrivateDisplay(
        _ displayID: CGDirectDisplayID,
        index: Int,
        to report: inout ReportBuilder
    ) {
        let display = captureDisplayMeasurement(displayID: displayID)
        let prefix = "PRIVATE_DISPLAY[\(index)]"
        report.line("\(prefix).numeric_displayID = \(display.displayID)")
        report.line("\(prefix).CGDisplayVendorNumber_DECIMAL = \(display.vendorID)")
        report.line("\(prefix).CGDisplayVendorNumber_HEX = \(hex(display.vendorID))")
        report.line("\(prefix).CGDisplayModelNumber_DECIMAL = \(display.productID)")
        report.line("\(prefix).CGDisplayModelNumber_HEX = \(hex(display.productID))")
        report.line("\(prefix).CGDisplaySerialNumber_DECIMAL = \(display.serialNumber)")
        report.line("\(prefix).CGDisplaySerialNumber_HEX = \(hex(display.serialNumber))")
        report.line("\(prefix).CGDisplayIsBuiltin = \(bool(display.isBuiltin))")
        report.line("\(prefix).CGDisplayIsOnline = \(bool(display.isOnline))")
        report.line("\(prefix).CGDisplayIsActive = \(bool(display.isActive))")
        report.line("\(prefix).FINGERPRINT_MATCH = \(bool(display.fingerprintMatches))")
    }

    private static func appendPreferences(
        label: String,
        storageKey: String,
        dataByteCount: Int?,
        preferences: AppPreferences?,
        decodeError: String?,
        to report: inout ReportBuilder
    ) {
        report.line("\(label)_STORAGE_KEY = \(storageKey)")
        report.line("\(label)_DATA_PRESENT = \(bool(dataByteCount != nil))")
        report.line("\(label)_DATA_BYTE_COUNT = \(dataByteCount.map(String.init) ?? "nil")")
        if let decodeError {
            report.line("\(label)_DECODE_ERROR = \(decodeError)")
        }
        report.line("\(label)_SELECTED_DISPLAY_KEY = \(preferences?.selectedDisplayKey ?? "nil")")
        report.line("\(label)_DISPLAY_SETTINGS_COUNT = \(preferences?.displaySettingsByKey.count ?? 0)")
        guard let preferences else {
            report.line("\(label)_DISPLAY_SETTINGS = none")
            return
        }
        for (index, entry) in preferences.displaySettingsByKey.sorted(by: { $0.key < $1.key }).enumerated() {
            let displayKey = entry.key
            let settings = entry.value
            report.line("\(label)_DISPLAY_SETTINGS[\(index)].displayKey = \(displayKey)")
            report.line("\(label)_DISPLAY_SETTINGS[\(index)].selectedProfileID = \(settings.selectedProfileID)")
            report.line("\(label)_DISPLAY_SETTINGS[\(index)].calibration.lowLux = \(settings.calibration.lowLux)")
            report.line("\(label)_DISPLAY_SETTINGS[\(index)].calibration.midLux = \(settings.calibration.midLux)")
            report.line("\(label)_DISPLAY_SETTINGS[\(index)].calibration.highLux = \(settings.calibration.highLux)")
            report.line("\(label)_DISPLAY_SETTINGS[\(index)].lastBrightness = \(settings.lastBrightness.map(String.init) ?? "nil")")
        }
    }

    private static func appendDefaults(
        _ defaults: [(String, String)],
        label: String,
        to report: inout ReportBuilder
    ) {
        if defaults.isEmpty {
            report.line("\(label) = none")
            return
        }
        for (index, entry) in defaults.enumerated() {
            report.line("\(label)[\(index)].KEY = \(entry.0)")
            report.line("\(label)[\(index)].VALUE = \(entry.1)")
        }
    }

    private static func bool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "0x%08X", value)
    }
}
