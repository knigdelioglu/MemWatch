import Darwin
import Foundation

struct DeveloperProjectManifest: Equatable, Sendable {
    let manifestURL: URL
    let configuredRoot: URL
    let isTauriProject: Bool

    init(manifestURL: URL, configuredRoot: URL, isTauriProject: Bool) {
        self.manifestURL = manifestURL.standardizedFileURL
        self.configuredRoot = configuredRoot.standardizedFileURL
        self.isTauriProject = isTauriProject
    }
}

struct DeveloperProjectDiscoveryIssue: Equatable, Sendable {
    let path: String
    let message: String
}

struct DeveloperProjectDiscoveryResult: Equatable, Sendable {
    let manifests: [DeveloperProjectManifest]
    let issues: [DeveloperProjectDiscoveryIssue]
}

enum DeveloperProjectDiscoveryError: LocalizedError {
    case inaccessibleRoot(String)

    var errorDescription: String? {
        switch self {
        case .inaccessibleRoot(let path):
            return "Developer project root is not accessible: \(path)"
        }
    }
}

struct DeveloperProjectDiscovery: @unchecked Sendable {
    private let fileManager: FileManager
    private let isKnownInaccessible: @Sendable (URL) -> Bool

    private static let excludedTraversalNames: Set<String> = [
        ".git", ".hg", ".svn", "target", ".build", "build", "dist", "node_modules",
        "Pods", "vendor", ".gradle", ".dart_tool", ".next", ".nuxt", ".turbo",
        ".venv", "venv", "__pycache__"
    ]

    init(
        fileManager: FileManager = .default,
        isKnownInaccessible: @escaping @Sendable (URL) -> Bool = { _ in false }
    ) {
        self.fileManager = fileManager
        self.isKnownInaccessible = isKnownInaccessible
    }

    func discover(in roots: [URL]) throws -> [DeveloperProjectManifest] {
        try discoverWithDiagnostics(in: roots).manifests
    }

    func discoverWithDiagnostics(in roots: [URL]) throws -> DeveloperProjectDiscoveryResult {
        var discoveredByPath: [String: DeveloperProjectManifest] = [:]
        var issues: [DeveloperProjectDiscoveryIssue] = []

        for root in roots.map({ $0.standardizedFileURL }) {
            try Task.checkCancellation()
            guard !Self.excludedTraversalNames.contains(root.lastPathComponent) else { continue }

            switch directoryState(of: root) {
            case .missing:
                continue
            case .inaccessible:
                throw DeveloperProjectDiscoveryError.inaccessibleRoot(root.path)
            case .directory:
                break
            }

            if isKnownInaccessible(root) {
                throw DeveloperProjectDiscoveryError.inaccessibleRoot(root.path)
            }

            var enumerationError: Error?
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [],
                errorHandler: { url, error in
                    if url.standardizedFileURL.path == root.path {
                        enumerationError = error
                        return false
                    }

                    issues.append(
                        DeveloperProjectDiscoveryIssue(
                            path: url.standardizedFileURL.path,
                            message: "Skipped inaccessible developer-project subtree: " + error.localizedDescription
                        )
                    )
                    return true
                }
            ) else {
                throw DeveloperProjectDiscoveryError.inaccessibleRoot(root.path)
            }

            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                var skipDescendants = false

                if isKnownInaccessible(url) {
                    issues.append(
                        DeveloperProjectDiscoveryIssue(
                            path: url.standardizedFileURL.path,
                            message: "Skipped inaccessible developer-project subtree"
                        )
                    )
                    enumerator.skipDescendants()
                    continue
                }

                let values: URLResourceValues
                do {
                    values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                } catch {
                    issues.append(
                        DeveloperProjectDiscoveryIssue(
                            path: url.standardizedFileURL.path,
                            message: "Skipped inaccessible developer-project subtree: " + error.localizedDescription
                        )
                    )
                    enumerator.skipDescendants()
                    continue
                }

                guard let isSymbolicLink = values.isSymbolicLink,
                      let isDirectory = values.isDirectory else {
                    issues.append(
                        DeveloperProjectDiscoveryIssue(
                            path: url.standardizedFileURL.path,
                            message: "Skipped developer-project entry with ambiguous filesystem metadata"
                        )
                    )
                    enumerator.skipDescendants()
                    continue
                }

                if isSymbolicLink {
                    skipDescendants = true
                } else if isDirectory {
                    skipDescendants = Self.excludedTraversalNames.contains(url.lastPathComponent)
                } else if values.isRegularFile == true, url.lastPathComponent == "Cargo.toml" {
                    let parent = url.deletingLastPathComponent().standardizedFileURL
                    let isTauri = parent.lastPathComponent == "src-tauri" ||
                        fileManager.fileExists(atPath: parent.appendingPathComponent("tauri.conf.json").path) ||
                        fileManager.fileExists(atPath: parent.appendingPathComponent("tauri.conf.json5").path)
                    let manifest = DeveloperProjectManifest(
                        manifestURL: url,
                        configuredRoot: root,
                        isTauriProject: isTauri
                    )
                    discoveredByPath[manifest.manifestURL.path] = manifest
                }

                if skipDescendants {
                    enumerator.skipDescendants()
                }
            }

            if enumerationError != nil {
                throw DeveloperProjectDiscoveryError.inaccessibleRoot(root.path)
            }
        }

        let manifests = discoveredByPath.values.sorted {
            $0.manifestURL.path.localizedStandardCompare($1.manifestURL.path) == .orderedAscending
        }
        return DeveloperProjectDiscoveryResult(manifests: manifests, issues: issues)
    }

    private enum DirectoryState {
        case missing
        case directory
        case inaccessible
    }

    private func directoryState(of url: URL) -> DirectoryState {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            switch errno {
            case ENOENT, ENOTDIR:
                return .missing
            default:
                return .inaccessible
            }
        }

        let mode = UInt32(info.st_mode) & UInt32(S_IFMT)
        guard mode == UInt32(S_IFDIR) else {
            return .inaccessible
        }
        return .directory
    }
}
