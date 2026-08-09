import Foundation

public enum OnboardingTutorialMode: Equatable, Sendable {
    case savedButtons(Set<UUID>)
    case custom
    case reply

    public func marksSavedButton(id: UUID) -> Bool {
        guard case .savedButtons(let promptIDs) = self else { return false }
        return promptIDs.contains(id)
    }

    public func marksCustomGuidance(_ guidance: String) -> Bool {
        guard case .custom = self else { return false }
        return !guidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var marksReply: Bool {
        guard case .reply = self else { return false }
        return true
    }
}
