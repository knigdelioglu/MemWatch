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

    private static let excludedTraversalNames: Set<String> = [
        ".git", ".hg", ".svn", "target", ".build", "build", "dist", "node_modules",
        "Pods", "vendor", ".gradle", ".dart_tool", ".next", ".nuxt", ".turbo",
        ".venv", "venv", "__pycache__"
    ]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func discover(in roots: [URL]) throws -> [DeveloperProjectManifest] {
        var discoveredByPath: [String: DeveloperProjectManifest] = [:]

        for root in roots.map({ $0.standardizedFileURL }) {
            try Task.checkCancellation()
            guard !Self.excludedTraversalNames.contains(root.lastPathComponent) else { continue }
            guard isDirectory(root) else {
                if fileManager.fileExists(atPath: root.path) {
                    throw DeveloperProjectDiscoveryError.inaccessibleRoot(root.path)
                }
                continue
            }

            var enumerationError: Error?
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            ) else {
                throw DeveloperProjectDiscoveryError.inaccessibleRoot(root.path)
            }

            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                var skipDescendants = false
                let values: URLResourceValues
                do {
                    values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                } catch {
                    throw DeveloperProjectDiscoveryError.inaccessibleRoot(url.path)
                }

                if values.isSymbolicLink == true {
                    skipDescendants = true
                } else if values.isDirectory == true {
                    skipDescendants = Self.excludedTraversalNames.contains(url.lastPathComponent)
                } else if url.lastPathComponent == "Cargo.toml" {
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

        return discoveredByPath.values.sorted {
            $0.manifestURL.path.localizedStandardCompare($1.manifestURL.path) == .orderedAscending
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
