import Foundation

struct DeveloperBuildProcess: Equatable, Sendable {
    let pid: Int32
    let executable: String
    let commandLine: String

    init(pid: Int32, executable: String, commandLine: String) {
        self.pid = pid
        self.executable = executable
        self.commandLine = commandLine
    }
}

enum DeveloperBuildActivityState: Equatable, Sendable {
    case inactive
    case active(String)
    case unknown(String)
}

struct DeveloperBuildActivityGuard: @unchecked Sendable {
    typealias ProcessProvider = @Sendable () throws -> [DeveloperBuildProcess]

    private let processProvider: ProcessProvider
    private static let defaultProcessProvider: ProcessProvider = {
        try liveProcesses()
    }

    init(processProvider: @escaping ProcessProvider = DeveloperBuildActivityGuard.defaultProcessProvider) {
        self.processProvider = processProvider
    }

    func state(for verification: CargoTargetVerification) -> DeveloperBuildActivityState {
        let processes: [DeveloperBuildProcess]
        do {
            processes = try processProvider()
        } catch {
            return .unknown(error.localizedDescription)
        }

        for process in processes {
            guard let executable = Self.recognizedExecutableName(process.executable) else { continue }
            if Self.references(process.commandLine, verification: verification) {
                return .active("\(executable) (PID \(process.pid))")
            }
            return .unknown("\(executable) (PID \(process.pid)) could not be associated with this Cargo workspace")
        }
        return .inactive
    }

    private static func recognizedExecutableName(_ executable: String) -> String? {
        let pathName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        let name = pathName.isEmpty ? executable.lowercased() : pathName
        let knownNames = ["cargo", "rustc", "cargo-tauri", "tauri"]
        return knownNames.first(where: { name == $0 })
    }

    private static func references(_ commandLine: String, verification: CargoTargetVerification) -> Bool {
        let paths = [verification.targetDirectory.path] +
            verification.manifestURLs.map(\.path) +
            verification.workspaceRoots.map(\.path)
        return paths.contains { containsPathReference(commandLine, path: $0) }
    }

    private static func containsPathReference(_ text: String, path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var searchStart = text.startIndex
        while let range = text.range(of: path, range: searchStart..<text.endIndex) {
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            let beforeIsPathCharacter = before.map(isPathCharacter) ?? false
            let afterIsPathCharacter = after.map { isPathCharacter($0) && $0 != "/" } ?? false
            if !beforeIsPathCharacter && !afterIsPathCharacter {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isPathCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "-_./".contains(character)
    }

    private static func liveProcesses() throws -> [DeveloperBuildProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm=,args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MemWatch.DeveloperBuildActivityGuard",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ps exited with status \(process.terminationStatus)"]
            )
        }

        guard let output = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "MemWatch.DeveloperBuildActivityGuard",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ps output was not valid UTF-8"]
            )
        }

        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard columns.count == 3, let pid = Int32(columns[0]) else { return nil }
            return DeveloperBuildProcess(
                pid: pid,
                executable: String(columns[1]),
                commandLine: String(columns[2])
            )
        }
    }
}
