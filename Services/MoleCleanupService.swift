import Combine
import Foundation

enum MoleCleanupAction: Equatable, Sendable {
    case clean

    var arguments: [String] {
        ["clean"]
    }
}

enum MoleCleanupPhase: Equatable {
    case ready
    case unavailable
    case running(MoleCleanupAction)
    case finished(MoleCleanupAction, exitStatus: Int32)
    case failed(MoleCleanupAction, message: String)
}

@MainActor
final class MoleCleanupService: ObservableObject {
    @Published private(set) var phase: MoleCleanupPhase
    @Published private(set) var commandPath: String?
    @Published private(set) var output = ""
    @Published private(set) var lastRunAt: Date?

    convenience init() {
        self.init(executablePath: Self.resolveMoleExecutable())
    }

    init(executablePath: String?) {
        commandPath = executablePath
        phase = executablePath == nil ? .unavailable : .ready
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func runCleanup() {
        guard !isRunning else { return }

        output = ""

        guard let resolvedPath = commandPath else {
            phase = .unavailable
            return
        }

        let action = MoleCleanupAction.clean
        phase = .running(action)

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.runMole(at: resolvedPath, action: action)
            await self?.finish(result, action: action)
        }
    }

    private func finish(_ result: MoleCleanupResult, action: MoleCleanupAction) {
        lastRunAt = Date()
        output = result.output

        switch result.outcome {
        case .exit(let status):
            phase = .finished(action, exitStatus: status)
        case .launchFailure(let message):
            phase = .failed(action, message: message)
        }
    }

    private nonisolated static func resolveMoleExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "/opt/homebrew/bin/mo",
            "/usr/local/bin/mo",
            "/opt/local/bin/mo",
            "\(home)/.local/bin/mo",
            "\(home)/bin/mo"
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/mo" })
        }

        var visited = Set<String>()
        return candidates.first { path in
            visited.insert(path).inserted && FileManager.default.isExecutableFile(atPath: path)
        }
    }

    private nonisolated static func runMole(
        at executablePath: String,
        action: MoleCleanupAction
    ) -> MoleCleanupResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = action.arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice

        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        var environment = ProcessInfo.processInfo.environment
        let fixedSearchPaths = [
            URL(fileURLWithPath: executablePath).deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin", isDirectory: true).path
        ]
        let existingSearchPaths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        var seenPaths = Set<String>()
        environment["PATH"] = (fixedSearchPaths + existingSearchPaths)
            .filter { seenPaths.insert($0).inserted }
            .joined(separator: ":")
        process.environment = environment

        do {
            try process.run()

            standardOutputPipe.fileHandleForWriting.closeFile()
            standardErrorPipe.fileHandleForWriting.closeFile()

            let outputCapture = MoleOutputCapture()
            let readers = DispatchGroup()
            for readHandle in [standardOutputPipe.fileHandleForReading, standardErrorPipe.fileHandleForReading] {
                readers.enter()
                DispatchQueue.global(qos: .utility).async {
                    defer { readers.leave() }
                    while true {
                        let chunk = readHandle.availableData
                        guard !chunk.isEmpty else { return }
                        outputCapture.append(chunk)
                    }
                }
            }

            process.waitUntilExit()
            readers.wait()

            let capture = outputCapture.snapshot()
            var text = Self.cleanTerminalOutput(String(decoding: capture.data, as: UTF8.self))
            if capture.omittedEarlierOutput {
                text = "Earlier Mole output was omitted.\n\n" + text
            }
            return MoleCleanupResult(output: text, outcome: .exit(process.terminationStatus))
        } catch {
            return MoleCleanupResult(
                output: "",
                outcome: .launchFailure(error.localizedDescription)
            )
        }
    }

    private nonisolated static func cleanTerminalOutput(_ output: String) -> String {
        let withoutANSI = output.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        return withoutANSI
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private struct MoleCleanupResult: Sendable {
    enum Outcome: Sendable {
        case exit(Int32)
        case launchFailure(String)
    }

    let output: String
    let outcome: Outcome
}

private final class MoleOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumOutputBytes = 96 * 1_024
    private var data = Data()
    private var omittedEarlierOutput = false

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }

        data.append(chunk)
        if data.count > maximumOutputBytes {
            data = Data(data.suffix(maximumOutputBytes))
            omittedEarlierOutput = true
        }
    }

    func snapshot() -> (data: Data, omittedEarlierOutput: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, omittedEarlierOutput)
    }
}
