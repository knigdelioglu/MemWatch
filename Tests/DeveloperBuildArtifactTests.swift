import Foundation

@main
struct DeveloperBuildArtifactTests {
    static func main() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("MemWatchCargoFixtures-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let projectRoots = home.appendingPathComponent("Projects", isDirectory: true)
        let app = projectRoots.appendingPathComponent("FixtureApp", isDirectory: true)
        let target = app.appendingPathComponent("target", isDirectory: true)
        let manifest = app.appendingPathComponent("Cargo.toml")
        let tauriManifest = app.appendingPathComponent("src-tauri/Cargo.toml")
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tauriManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFile(manifest, contents: "[workspace]\nmembers = [\"src-tauri\"]\n")
        try writeFile(tauriManifest, contents: "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\n")
        try writeFile(app.appendingPathComponent("src-tauri/tauri.conf.json"), contents: "{}")
        try writeFile(app.appendingPathComponent("src-tauri/src/main.rs"), contents: "fn main() {}\n")
        try writeFile(target.appendingPathComponent("payload.bin"), contents: "generated")

        let skippedCargo = [
            app.appendingPathComponent("target/nested/Cargo.toml"),
            app.appendingPathComponent("node_modules/nested/Cargo.toml"),
            app.appendingPathComponent(".git/nested/Cargo.toml")
        ]
        for path in skippedCargo {
            try writeFile(path, contents: "[package]\nname = \"skipped\"\n")
        }

        defer { try? fileManager.removeItem(at: root) }

        let discovery = DeveloperProjectDiscovery()
        let manifests = try discovery.discover(in: [projectRoots])
        precondition(manifests.count == 2, "Only Cargo manifests outside excluded traversal directories should be discovered")
        precondition(manifests.contains { $0.manifestURL.standardizedFileURL.path == tauriManifest.standardizedFileURL.path && $0.isTauriProject }, "Tauri Cargo manifest should be identified")

        let actualMetadata = try CargoMetadataResolver().resolve(manifestURL: manifest)
        precondition(actualMetadata.workspaceRoot.path == app.path, "Cargo must report the workspace root")
        precondition(actualMetadata.targetDirectory.path == target.path, "Cargo must report the resolved target directory")

        let metadataJSON = try JSONSerialization.data(withJSONObject: [
            "workspace_root": app.path,
            "target_directory": target.path
        ])
        let resolver = CargoMetadataResolver { arguments in
            precondition(
                Array(arguments.prefix(6)) == ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path"] &&
                    [manifest.path, tauriManifest.path].contains(arguments.last ?? ""),
                "Cargo metadata must use the no-deps manifest-first command"
            )
            return CargoCommandResult(exitCode: 0, standardOutput: metadataJSON, standardError: Data())
        }
        let context = CleanupScanContext(homeDirectory: home, projectRoots: [projectRoots])
        let scanner = DeveloperBuildArtifactScanner(metadataResolver: resolver)
        let items = try await scanner.scan(context: context)
        guard let targetItem = items.first else { preconditionFailure("Cargo target should be discovered") }
        let legacyItems = try await ProjectArtifactScanner().scan(context: context)
        precondition(!legacyItems.contains { $0.url.path == target.path }, "Legacy name-based project scanning must not classify an unverified target")
        precondition(targetItem.ruleID.rawValue == "project.rust.target.verified")
        precondition(targetItem.safety == .safe, "A unique target inside its Cargo workspace should be Safe")
        precondition(targetItem.requirements.contains(.explicitConfirmation), "Cargo target cleanup must require explicit confirmation")
        precondition(targetItem.requirements.contains(.buildInactive), "Cargo target cleanup must require an inactive build")
        precondition(targetItem.cargoTargetVerification?.isInsideWorkspace == true)

        let rule = try requireRule("project.rust.target.verified")
        let inactiveEngine = CleanupSafetyEngine(
            activityGuard: CleanupActivityGuard { _ in .inactive },
            buildActivityGuard: DeveloperBuildActivityGuard { [] }
        )
        let inactiveAssessment = inactiveEngine.assess(candidate: targetItem, rule: rule, context: context)
        precondition(inactiveAssessment.canDelete, "A verified inactive Cargo target should pass the safety engine")

        let activeEngine = CleanupSafetyEngine(
            activityGuard: CleanupActivityGuard { _ in .inactive },
            buildActivityGuard: DeveloperBuildActivityGuard {
                [DeveloperBuildProcess(pid: 42, executable: "/usr/bin/cargo", commandLine: "cargo build --manifest-path \(manifest.path)")]
            }
        )
        let activeAssessment = activeEngine.assess(candidate: targetItem, rule: rule, context: context)
        precondition(activeAssessment.candidate.safety == .protected, "An active Cargo build must block target cleanup")
        precondition(!activeAssessment.canDelete, "An active Cargo build must make deletion unavailable")

        let externalProjectRoot = home.appendingPathComponent("ExternalProjects", isDirectory: true)
        let externalApp = externalProjectRoot.appendingPathComponent("FixtureApp", isDirectory: true)
        let externalManifest = externalApp.appendingPathComponent("Cargo.toml")
        let externalTarget = home.appendingPathComponent("rust-target", isDirectory: true)
        try fileManager.createDirectory(at: externalTarget, withIntermediateDirectories: true)
        try writeFile(externalManifest, contents: "[package]\nname = \"external\"\nversion = \"0.1.0\"\n")
        try writeFile(externalTarget.appendingPathComponent("payload.bin"), contents: "external")
        let externalMetadataData = try metadataData(workspaceRoot: externalApp, targetDirectory: externalTarget)
        let externalResolver = CargoMetadataResolver { arguments in
            precondition(arguments.last == externalManifest.path)
            return CargoCommandResult(exitCode: 0, standardOutput: externalMetadataData, standardError: Data())
        }
        let externalItems = try await DeveloperBuildArtifactScanner(metadataResolver: externalResolver).scan(
            context: CleanupScanContext(homeDirectory: home, projectRoots: [externalProjectRoot])
        )
        guard let externalItem = externalItems.first else { preconditionFailure("External Cargo target should be discovered") }
        precondition(externalItem.safety == .review, "A Cargo target outside its workspace must require review")
        precondition(externalItem.cargoTargetVerification?.isInsideWorkspace == false)

        let sharedRoot = home.appendingPathComponent("SharedProjects", isDirectory: true)
        let sharedAppA = sharedRoot.appendingPathComponent("AppA", isDirectory: true)
        let sharedAppB = sharedRoot.appendingPathComponent("AppB", isDirectory: true)
        let sharedManifestA = sharedAppA.appendingPathComponent("Cargo.toml")
        let sharedManifestB = sharedAppB.appendingPathComponent("Cargo.toml")
        let sharedTarget = home.appendingPathComponent("shared-rust-target", isDirectory: true)
        try writeFile(sharedManifestA, contents: "[package]\nname = \"a\"\nversion = \"0.1.0\"\n")
        try writeFile(sharedManifestB, contents: "[package]\nname = \"b\"\nversion = \"0.1.0\"\n")
        try writeFile(sharedTarget.appendingPathComponent("payload.bin"), contents: "shared")
        let sharedResolver = CargoMetadataResolver { arguments in
            let manifestPath = arguments.last ?? ""
            let workspaceRoot = manifestPath == sharedManifestA.path ? sharedAppA : sharedAppB
            let data = try metadataData(workspaceRoot: workspaceRoot, targetDirectory: sharedTarget)
            return CargoCommandResult(exitCode: 0, standardOutput: data, standardError: Data())
        }
        let sharedItems = try await DeveloperBuildArtifactScanner(metadataResolver: sharedResolver).scan(
            context: CleanupScanContext(homeDirectory: home, projectRoots: [sharedRoot])
        )
        guard let sharedItem = sharedItems.first else { preconditionFailure("Shared Cargo target should be discovered") }
        precondition(sharedItem.safety == .review, "A target shared by workspaces must require review")
        precondition(sharedItem.cargoTargetVerification?.isSharedTarget == true)

        let structuralRoot = home.appendingPathComponent("StructuralProjects", isDirectory: true)
        let structuralApp = structuralRoot.appendingPathComponent("FixtureApp", isDirectory: true)
        let structuralManifest = structuralApp.appendingPathComponent("Cargo.toml")
        try writeFile(structuralManifest, contents: "[package]\nname = \"structural\"\nversion = \"0.1.0\"\n")
        let structuralMetadataData = try metadataData(workspaceRoot: structuralApp, targetDirectory: structuralApp)
        let structuralResolver = CargoMetadataResolver { _ in
            CargoCommandResult(exitCode: 0, standardOutput: structuralMetadataData, standardError: Data())
        }
        let structuralItems = try await DeveloperBuildArtifactScanner(metadataResolver: structuralResolver).scan(
            context: CleanupScanContext(homeDirectory: home, projectRoots: [structuralRoot])
        )
        guard let structuralItem = structuralItems.first else { preconditionFailure("Structural Cargo target should be surfaced as protected") }
        precondition(structuralItem.safety == .protected && structuralItem.deletionMode == .none, "Workspace-root target must be protected")

        let unverified = CleanupCandidate(
            scannerID: scanner.id,
            ruleID: rule.id,
            category: .projectArtifacts,
            url: target,
            displayName: "target",
            logicalBytes: 1,
            allocatedBytes: 1,
            safety: .safe,
            deletionMode: .permanent,
            requirements: [.explicitConfirmation, .buildInactive],
            reason: "unverified",
            identity: CleanupPathValidator.identity(for: target)
        )
        let unverifiedAssessment = inactiveEngine.assess(candidate: unverified, rule: rule, context: context)
        precondition(unverifiedAssessment.candidate.safety == .protected, "A target without Cargo metadata proof must remain protected")

        print("PASS Cargo project discovery, metadata verification and build activity guard")
    }

    private static func requireRule(_ id: CleanupRuleID) throws -> CleanupRule {
        guard let rule = CleanupRuleCatalog().rule(for: id) else {
            throw NSError(domain: "MemWatch.DeveloperBuildArtifactTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing rule \(id.rawValue)"])
        }
        return rule
    }

    private static func writeFile(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private static func metadataData(workspaceRoot: URL, targetDirectory: URL) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "workspace_root": workspaceRoot.path,
            "target_directory": targetDirectory.path
        ])
    }
}
