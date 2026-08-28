import Darwin
import Foundation

struct CleanupSafetyAssessment: Equatable, Sendable {
    let candidate: CleanupCandidate
    let blockers: [String]

    var canDelete: Bool {
        candidate.isPotentiallyDeletable && blockers.isEmpty
    }
}

struct CleanupSafetyEngine: Sendable {
    private let pathValidator: CleanupPathValidator

    init(pathValidator: CleanupPathValidator = CleanupPathValidator()) {
        self.pathValidator = pathValidator
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
            deletionMode: safety == .protected ? .none : rule.deletionMode,
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
                deletionMode: .none,
                requirements: requirements,
                identity: identity,
                policyNotes: candidate.policyNotes + [message]
            ),
            blockers: [message]
        )
    }
}
