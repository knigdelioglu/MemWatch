import AppKit
import Darwin
import Foundation

struct CleanupSafetyAssessment: Equatable, Sendable {
    let candidate: CleanupCandidate
    let blockers: [String]

    var canDelete: Bool {
        candidate.isPotentiallyDeletable && blockers.isEmpty
    }
}

enum CleanupApplicationActivityState: Sendable {
    case inactive
    case active(String)
    case unknown(String)
}

enum CleanupApplicationCloseResult: Sendable {
    case noRunningApplication
    case terminationRequested(String)
    case terminationRejected(String)
}

struct CleanupActivityGuard: @unchecked Sendable {
    private let stateProvider: (CleanupCandidate) -> CleanupApplicationActivityState

    init(
        stateProvider: @escaping (CleanupCandidate) -> CleanupApplicationActivityState = CleanupActivityGuard.liveState
    ) {
        self.stateProvider = stateProvider
    }

    func state(for candidate: CleanupCandidate) -> CleanupApplicationActivityState {
        stateProvider(candidate)
    }

    func requestTermination(for candidate: CleanupCandidate) -> CleanupApplicationCloseResult {
        guard let (applications, fallbackName) = Self.applicationCandidates(for: candidate),
              !applications.isEmpty else {
            return .noRunningApplication
        }

        let name = applications.first?.localizedName ?? fallbackName
        let requestAccepted = applications.map { $0.terminate() }.contains(true)
        return requestAccepted
            ? .terminationRequested(name)
            : .terminationRejected(name)
    }

    func activeApplicationName(for candidate: CleanupCandidate) -> String? {
        if case .active(let name) = state(for: candidate) {
            return name
        }
        return nil
    }

    private static func liveState(for candidate: CleanupCandidate) -> CleanupApplicationActivityState {
        guard let (applications, fallbackName) = applicationCandidates(for: candidate) else {
            return .unknown(candidate.displayName)
        }
        return applications.isEmpty
            ? .inactive
            : .active(applications.first?.localizedName ?? fallbackName)
    }

    private static func applicationCandidates(
        for candidate: CleanupCandidate
    ) -> ([NSRunningApplication], String)? {
        if candidate.category == .xcode {
            return (
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode"),
                "Xcode"
            )
        }

        let name = candidate.displayName.lowercased()
        if name.contains("vs code") || candidate.url.path.contains("Application Support/Code") {
            return (
                ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"].flatMap {
                    NSRunningApplication.runningApplications(withBundleIdentifier: $0)
                },
                "Visual Studio Code"
            )
        }
        if name.contains("docker") || candidate.url.path.lowercased().contains("docker") {
            return (
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.docker.docker"),
                "Docker Desktop"
            )
        }
        if name.contains("jetbrains") || candidate.url.path.contains("JetBrains") {
            return (
                NSWorkspace.shared.runningApplications.filter {
                    ($0.bundleIdentifier ?? "").hasPrefix("com.jetbrains.")
                },
                "JetBrains IDE"
            )
        }

        guard let identifier = inferredBundleIdentifier(from: candidate.url) else {
            return nil
        }
        return (
            NSWorkspace.shared.runningApplications.filter { app in
                guard let bundleID = app.bundleIdentifier else { return false }
                return bundleID == identifier ||
                    bundleID.hasPrefix(identifier + ".") ||
                    identifier.hasPrefix(bundleID + ".")
            },
            identifier
        )
    }

    private static func inferredBundleIdentifier(from url: URL) -> String? {
        let components = url.standardizedFileURL.pathComponents
        let markers: [[String]] = [
            ["Library", "Caches"],
            ["Library", "Containers"],
            ["Library", "Group Containers"]
        ]

        for marker in markers {
            guard let start = index(of: marker, in: components) else { continue }
            let candidateIndex = start + marker.count
            guard candidateIndex < components.count else { continue }
            var identifier = components[candidateIndex]
            if identifier.hasPrefix("group.") {
                identifier.removeFirst("group.".count)
            }
            guard identifier.contains("."), !identifier.contains("/") else { continue }
            return identifier
        }
        return nil
    }

    private static func index(of needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return start
            }
        }
        return nil
    }
}

struct CleanupSafetyEngine: Sendable {
    private let pathValidator: CleanupPathValidator
    private let activityGuard: CleanupActivityGuard

    init(
        pathValidator: CleanupPathValidator = CleanupPathValidator(),
        activityGuard: CleanupActivityGuard = CleanupActivityGuard()
    ) {
        self.pathValidator = pathValidator
        self.activityGuard = activityGuard
    }

    func assess(
        candidate: CleanupCandidate,
        rule: CleanupRule,
        context: CleanupScanContext
    ) -> CleanupSafetyAssessment {
        var blockers: [String] = []
        var notes = candidate.policyNotes
        var safety = CleanupSafetyLevel.moreRestrictive(candidate.safety, rule.defaultSafety)
        var requirements = candidate.requirements.union(rule.requirements)

        guard candidate.category == rule.category else {
            let message = "Scanner category does not match cleanup rule"
            return blocked(candidate, requirements: requirements, identity: candidate.identity, message: message)
        }

        let validation = pathValidator.validate(candidate: candidate, rule: rule, context: context)
        guard validation.isAllowed else {
            let message = validation.reason ?? "Cleanup path was rejected"
            return blocked(candidate, requirements: requirements, identity: validation.identity, message: message)
        }

        guard let identity = validation.identity else {
            return blocked(candidate, requirements: requirements, identity: nil, message: "Cleanup target no longer exists or cannot be identified")
        }

        if rule.deletionMode == .none || rule.defaultSafety == .protected {
            safety = .protected
            blockers.append("Cleanup rule explicitly protects this item")
        }

        if requirements.contains(.fullDiskAccess), !context.fullDiskAccessAvailable {
            safety = .protected
            blockers.append("Full Disk Access is required")
        }

        if requirements.contains(.privilegedHelper), !context.privilegedHelperAvailable {
            safety = .protected
            blockers.append("Privileged helper is required")
        }

        if requirements.contains(.applicationInactive) {
            switch activityGuard.state(for: candidate) {
            case .inactive:
                break
            case .active(let name):
                notes.append("Close \(name) before cleanup; MemWatch will close it before removing its cache")
            case .unknown(let name):
                safety = CleanupSafetyLevel.moreRestrictive(safety, .review)
                requirements.insert(.explicitConfirmation)
                notes.append("The owning application state could not be verified; review this item before cleanup")
                notes.append("Application: \(name)")
            }
        }

        switch rule.rootPolicy {
        case .userHome, .userLibrary, .projectRoots, .requestedRoots, .temporaryDirectory:
            if identity.ownerUID != getuid() {
                safety = .protected
                blockers.append("Target is not owned by the current user")
            }

        case .systemLibrary, .privateVar:
            requirements.insert(.privilegedHelper)
            if !context.privilegedHelperAvailable {
                safety = .protected
                if !blockers.contains("Privileged helper is required") {
                    blockers.append("Privileged helper is required")
                }
            }
        }

        if let minimumAge = rule.minimumAge {
            if let timestamp = candidate.modifiedAt ?? candidate.createdAt {
                if context.now.timeIntervalSince(timestamp) < minimumAge {
                    safety = CleanupSafetyLevel.moreRestrictive(safety, .review)
                    requirements.insert(.explicitConfirmation)
                    notes.append("Item is newer than the automatic-cleanup age threshold")
                }
            } else {
                safety = CleanupSafetyLevel.moreRestrictive(safety, .review)
                requirements.insert(.explicitConfirmation)
                notes.append("Item age could not be verified")
            }
        }

        notes.append(contentsOf: blockers)

        let evaluated = candidate.applying(
            safety: safety,
            deletionMode: safety == .protected ? CleanupDeletionMode.none : rule.deletionMode,
            requirements: requirements,
            identity: identity,
            policyNotes: notes
        )

        return CleanupSafetyAssessment(candidate: evaluated, blockers: blockers)
    }

    private func blocked(
        _ candidate: CleanupCandidate,
        requirements: CleanupRequirements,
        identity: FileIdentity?,
        message: String
    ) -> CleanupSafetyAssessment {
        CleanupSafetyAssessment(
            candidate: candidate.applying(
                safety: .protected,
                deletionMode: CleanupDeletionMode.none,
                requirements: requirements,
                identity: identity,
                policyNotes: candidate.policyNotes + [message]
            ),
            blockers: [message]
        )
    }
}
