import Combine
import Foundation

enum MoleCleanupAction: Equatable, Sendable {
    /// `mo clean --dry-run`: shows what would be removed, deletes nothing.
    case preview
    /// `mo clean`: performs Mole's cleanup.
    case clean

    var arguments: [String] {
        switch self {
        case .preview: return ["clean", "--dry-run"]
        case .clean: return ["clean"]
        }
    }

    var displayName: String {
        switch self {
        case .preview: return "Preview"
        case .clean: return "Cleanup"
        }
    }
}

enum MoleCleanupPhase: Equatable {
    case ready
    case unavailable
    case running(MoleCleanupAction)
    case finished(MoleCleanupAction, exitStatus: Int32)
    case cancelled(MoleCleanupAction)
    case failed(MoleCleanupAction, message: String)
}

@MainActor
final class MoleCleanupService: ObservableObject {
    @Published private(set) var phase: MoleCleanupPhase
    @Published private(set) var commandPath: String?
    @Published private(set) var output = ""
    @Published private(set) var lastRunAt: Date?

    /// When true the executable is looked up again whenever it is missing,
    /// so installing Mole while MemWatch is running works without relaunch.
    private let autoResolvesExecutable: Bool
    private var activeHandle: MoleProcessHandle?
    private var outputPollTask: Task<Void, Never>?
    private var resolveTask: Task<Void, Never>?

    convenience init() {
        self.init(
            executablePath: Self.resolveMoleExecutable(allowLoginShell: false),
            autoResolvesExecutable: true
        )
        if commandPath == nil {
            refreshAvailability()
        }
    }

    init(executablePath: String?, autoResolvesExecutable: Bool = false) {
        self.autoResolvesExecutable = autoResolvesExecutable
        commandPath = executablePath
        phase = executablePath == nil ? .unavailable : .ready
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// Re-checks whether Mole is installed. Cheap; safe to call on appear.
    func refreshAvailability() {
        guard autoResolvesExecutable, !isRunning else { return }

        if let commandPath, FileManager.default.isExecutableFile(atPath: commandPath) {
            if case .unavailable = phase { phase = .ready }
            return
        }

        if let resolved = Self.resolveMoleExecutable(allowLoginShell: false) {
            apply(resolvedPath: resolved)
            return
        }

        // The login-shell lookup can take a moment; keep it off the main
        // thread.
        guard resolveTask == nil else { return }
        resolveTask = Task { @MainActor [weak self] in
            let resolved = await Task.detached(priority: .utility) {
                Self.resolveMoleExecutable(allowLoginShell: true)
            }.value
            guard let self else { return }
            self.resolveTask = nil
            guard !self.isRunning else { return }
            self.apply(resolvedPath: resolved)
        }
    }

    private func apply(resolvedPath: String?) {
        commandPath = resolvedPath
        if resolvedPath == nil {
            phase = .unavailable
        } else if case .unavailable = phase {
            phase = .ready
        }
    }

    func runCleanup() {
        run(.clean)
    }

    func runPreview() {
        run(.preview)
    }

    func cancel() {
        activeHandle?.terminate()
    }

    func run(_ action: MoleCleanupAction) {
        guard !isRunning else { return }

        output = ""

        guard let resolvedPath = commandPath else {
            phase = .unavailable
            return
        }

        phase = .running(action)

        let handle = MoleProcessHandle()
        let capture = MoleOutputCapture()
        activeHandle = handle

        // Stream Mole's output while it runs so a long cleanup does not look
        // frozen.
        outputPollTask?.cancel()
        outputPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self, self.isRunning, self.activeHandle === handle else { return }
                let snapshot = capture.snapshot()
                let text = Self.cleanTerminalOutput(String(decoding: snapshot.data, as: UTF8.self))
                if text != self.output {
                    self.output = text
                }
            }
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.runMole(at: resolvedPath, action: action, handle: handle, capture: capture)
            await self?.finish(result, action: action, handle: handle)
        }
    }

    private func finish(_ result: MoleCleanupResult, action: MoleCleanupAction, handle: MoleProcessHandle) {
        guard activeHandle === handle else { return }
        activeHandle = nil
        outputPollTask?.cancel()
        outputPollTask = nil

        lastRunAt = Date()
        output = result.output

        switch result.outcome {
        case .exit(let status):
            phase = .finished(action, exitStatus: status)
        case .cancelled:
            phase = .cancelled(action)
        case .launchFailure(let message):
            phase = .failed(action, message: message)
        }
    }

    // MARK: - Executable discovery

    nonisolated static func resolveMoleExecutable(allowLoginShell: Bool = true) -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let names = ["mo", "mole"]
        var directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "\(home)/.homebrew/bin",
            "\(home)/homebrew/bin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "/opt/homebrew/opt/mole/bin",
            "/usr/local/opt/mole/bin"
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        var visited = Set<String>()
        for directory in directories {
            for name in names {
                let candidate = "\(directory)/\(name)"
                guard visited.insert(candidate).inserted else { continue }
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        // Apps launched from Finder/login items get a minimal PATH. Ask the
        // user's login shell, which knows custom Homebrew prefixes.
        return allowLoginShell ? resolveWithLoginShell() : nil
    }

    private nonisolated static func resolveWithLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v mo 2>/dev/null || command -v mole 2>/dev/null"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Never block for long on a misbehaving shell profile.
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
        guard let path, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    // MARK: - Process execution

    private nonisolated static func runMole(
        at executablePath: String,
        action: MoleCleanupAction,
        handle: MoleProcessHandle,
        capture: MoleOutputCapture
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fixedSearchPaths = [
            URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().deletingLastPathComponent().path,
            URL(fileURLWithPath: executablePath).deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/opt/local/bin",
            home.appendingPathComponent(".homebrew/bin", isDirectory: true).path,
            home.appendingPathComponent(".local/bin", isDirectory: true).path,
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingSearchPaths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        var seenPaths = Set<String>()
        environment["PATH"] = (fixedSearchPaths + existingSearchPaths)
            .filter { seenPaths.insert($0).inserted }
            .joined(separator: ":")
        // GUI apps have no TERM; Mole's shell helpers call tput/printf with
        // colours and can fail under `set -e` without one. ANSI codes are
        // stripped from the captured output below.
        if environment["TERM"] == nil || environment["TERM"] == "dumb" {
            environment["TERM"] = "xterm-256color"
        }
        environment["HOME"] = environment["HOME"] ?? home.path
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        process.environment = environment

        do {
            try process.run()
        } catch {
            return MoleCleanupResult(
                output: "",
                outcome: .launchFailure(error.localizedDescription)
            )
        }

        handle.attach(process)

        standardOutputPipe.fileHandleForWriting.closeFile()
        standardErrorPipe.fileHandleForWriting.closeFile()

        let readers = DispatchGroup()
        for readHandle in [standardOutputPipe.fileHandleForReading, standardErrorPipe.fileHandleForReading] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave() }
                while true {
                    let chunk = readHandle.availableData
                    guard !chunk.isEmpty else { return }
                    capture.append(chunk)
                }
            }
        }

        process.waitUntilExit()
        readers.wait()

        let snapshot = capture.snapshot()
        var text = Self.cleanTerminalOutput(String(decoding: snapshot.data, as: UTF8.self))
        if snapshot.omittedEarlierOutput {
            text = "Earlier Mole output was omitted.\n\n" + text
        }

        if handle.wasCancelled {
            return MoleCleanupResult(output: text, outcome: .cancelled)
        }
        return MoleCleanupResult(output: text, outcome: .exit(process.terminationStatus))
    }

    nonisolated static func cleanTerminalOutput(_ output: String) -> String {
        let withoutANSI = output.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        // Spinners redraw a line with carriage returns; keep only the final
        // state of each such line.
        return withoutANSI
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                line.split(separator: "\r", omittingEmptySubsequences: true).last ?? ""
            }
            .joined(separator: "\n")
    }
}

private struct MoleCleanupResult: Sendable {
    enum Outcome: Sendable {
        case exit(Int32)
        case cancelled
        case launchFailure(String)
    }

    let output: String
    let outcome: Outcome
}

/// Lets the main actor cancel a Mole process owned by a background task.
private final class MoleProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelRequested = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancelRequested
        lock.unlock()
        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func terminate() {
        lock.lock()
        cancelRequested = true
        let process = self.process
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
        }
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested
    }
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
