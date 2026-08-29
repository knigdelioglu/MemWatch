import Foundation

struct CargoCommandResult: Sendable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

struct CargoWorkspaceMetadata: Equatable, Sendable {
    let manifestURL: URL
    let workspaceRoot: URL
    let targetDirectory: URL
}

enum CargoMetadataResolutionError: LocalizedError {
    case invalidManifest(String)
    case commandFailed(String)
    case malformedOutput(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest(let path):
            return "Cargo metadata manifest is invalid: \(path)"
        case .commandFailed(let message):
            return "Cargo metadata could not be resolved: \(message)"
        case .malformedOutput(let path):
            return "Cargo metadata output is malformed: \(path)"
        }
    }
}

struct CargoMetadataResolver: Sendable {
    typealias CommandRunner = @Sendable ([String]) throws -> CargoCommandResult

    private let commandRunner: CommandRunner
    private static let defaultCommandRunner: CommandRunner = { arguments in
        try runCargoCommand(arguments)
    }

    init(commandRunner: @escaping CommandRunner = CargoMetadataResolver.defaultCommandRunner) {
        self.commandRunner = commandRunner
    }

    func resolve(manifestURL: URL) throws -> CargoWorkspaceMetadata {
        let manifest = manifestURL.standardizedFileURL
        guard manifest.isFileURL,
              manifest.path.hasPrefix("/"),
              manifest.lastPathComponent == "Cargo.toml" else {
            throw CargoMetadataResolutionError.invalidManifest(manifest.path)
        }

        let result: CargoCommandResult
        do {
            result = try commandRunner([
                "cargo",
                "metadata",
                "--format-version", "1",
                "--no-deps",
                "--manifest-path", manifest.path
            ])
        } catch {
            throw CargoMetadataResolutionError.commandFailed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            let message = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CargoMetadataResolutionError.commandFailed(
                message?.isEmpty == false ? message! : "cargo exited with status \(result.exitCode)"
            )
        }

        struct Payload: Decodable {
            let workspaceRoot: String
            let targetDirectory: String

            enum CodingKeys: String, CodingKey {
                case workspaceRoot = "workspace_root"
                case targetDirectory = "target_directory"
            }
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: result.standardOutput)
        } catch {
            throw CargoMetadataResolutionError.malformedOutput(manifest.path)
        }

        guard let workspaceRoot = Self.absoluteFileURL(payload.workspaceRoot),
              let targetDirectory = Self.absoluteFileURL(payload.targetDirectory) else {
            throw CargoMetadataResolutionError.malformedOutput(manifest.path)
        }

        return CargoWorkspaceMetadata(
            manifestURL: manifest,
            workspaceRoot: workspaceRoot,
            targetDirectory: targetDirectory
        )
    }

    private static func absoluteFileURL(_ path: String) -> URL? {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func runCargoCommand(_ arguments: [String]) throws -> CargoCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        if let manifestArgumentIndex = arguments.firstIndex(of: "--manifest-path"),
           manifestArgumentIndex + 1 < arguments.count {
            let manifestURL = URL(fileURLWithPath: arguments[manifestArgumentIndex + 1])
            process.currentDirectoryURL = manifestURL.deletingLastPathComponent()
        }

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let outputBox = PipeDataBox()
        let errorBox = PipeDataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.data = standardOutput.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBox.data = standardError.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.closeFile()
            standardError.fileHandleForReading.closeFile()
            group.wait()
            throw error
        }
        process.waitUntilExit()
        group.wait()

        return CargoCommandResult(
            exitCode: process.terminationStatus,
            standardOutput: outputBox.data,
            standardError: errorBox.data
        )
    }
}

private final class PipeDataBox: @unchecked Sendable {
    var data = Data()
}
