import Darwin
import Foundation

struct DeveloperBuildArtifactScanner: CleanupScanner {
    let id: CleanupScannerID = "developer-build-artifact"
    let category: CleanupCategory = .projectArtifacts

    private let discovery: DeveloperProjectDiscovery
    private let metadataResolver: CargoMetadataResolver
    private let support = CleanupScannerSupport()

    init(
        discovery: DeveloperProjectDiscovery = DeveloperProjectDiscovery(),
        metadataResolver: CargoMetadataResolver = CargoMetadataResolver()
    ) {
        self.discovery = discovery
        self.metadataResolver = metadataResolver
    }

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let manifests = try discovery.discover(in: context.projectRoots)
        guard !manifests.isEmpty else { return [] }

        var metadata: [CargoWorkspaceMetadata] = []
        var firstResolutionError: Error?
        for manifest in manifests {
            try Task.checkCancellation()
            guard !context.isIgnored(manifest.manifestURL) else { continue }
            do {
                metadata.append(try metadataResolver.resolve(manifestURL: manifest.manifestURL))
            } catch {
                firstResolutionError = firstResolutionError ?? error
            }
        }

        if metadata.isEmpty, let firstResolutionError {
            throw firstResolutionError
        }

        var groupedByTarget: [String: [CargoWorkspaceMetadata]] = [:]
        for entry in metadata {
            groupedByTarget[entry.targetDirectory.standardizedFileURL.path, default: []].append(entry)
        }

        var results: [CleanupCandidate] = []
        for targetPath in groupedByTarget.keys.sorted() {
            try Task.checkCancellation()
            guard let group = groupedByTarget[targetPath], let representative = group.first else { continue }
            let target = representative.targetDirectory.standardizedFileURL
            guard !context.isIgnored(target), let identity = CleanupPathValidator.identity(for: target), !identity.isSymbolicLink,
                  (identity.mode & UInt32(S_IFMT)) == UInt32(S_IFDIR) else { continue }

            let verification = CargoTargetVerification(
                manifestURLs: group.map(\.manifestURL),
                workspaceRoots: group.map(\.workspaceRoot),
                targetDirectory: target
            )
            let structuralReason = protectedTargetReason(
                target: target,
                identity: identity,
                verification: verification,
                context: context
            )
            let isProtected = structuralReason != nil
            let safety: CleanupSafetyLevel
            let reason: String
            if let structuralReason {
                safety = .protected
                reason = structuralReason
            } else if verification.isSharedTarget {
                safety = .review
                reason = "Cargo-verified target shared by multiple workspaces"
            } else if verification.isInsideWorkspace {
                safety = .safe
                reason = "Cargo-verified workspace build target"
            } else {
                safety = .review
                reason = "Cargo-verified target configured outside its workspace"
            }

            let displayName = "Cargo target · \(target.lastPathComponent)"
            if let item = support.candidate(
                url: target,
                scannerID: id,
                ruleID: "project.rust.target.verified",
                category: category,
                displayName: displayName,
                safety: safety,
                deletionMode: isProtected ? .none : .permanent,
                requirements: [.explicitConfirmation, .buildInactive],
                reason: reason,
                regenerationHint: "Cargo can regenerate this target directory on the next build.",
                measureSize: !isProtected,
                cargoTargetVerification: verification
            ), isProtected || item.allocatedBytes > 0 {
                results.append(item)
            }
        }
        return results
    }

    private func protectedTargetReason(
        target: URL,
        identity: FileIdentity,
        verification: CargoTargetVerification,
        context: CleanupScanContext
    ) -> String? {
        let path = target.standardizedFileURL.path
        if CleanupPathValidator.isProtectedOperatingSystemPath(path) {
            return "Cargo metadata points to a protected operating-system root"
        }
        if identity.ownerUID != getuid() {
            return "Cargo target is not owned by the current user"
        }

        let normalized = target.standardizedFileURL.path
        if normalized == context.homeDirectory.standardizedFileURL.path || normalized == "/" {
            return "Cargo target resolves to a structural filesystem root"
        }
        if (context.projectRoots + verification.workspaceRoots).contains(where: {
            $0.standardizedFileURL.path == normalized
        }) {
            return "Cargo target resolves to a project or workspace root"
        }

        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: []
        ) ?? []
        if mountedVolumes.contains(where: { $0.standardizedFileURL.path == normalized }) {
            return "Cargo target resolves to a mounted volume root"
        }
        return nil
    }
}
