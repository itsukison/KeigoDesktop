import Foundation

/// The shared toolbar order expressed as one desktop list.
///
/// Position zero owns the iPhone's `main` slot; every later position is `sub`.
/// Keeping this rule pure makes arrow reordering and main-button deletion testable without
/// SwiftUI or a live Supabase project.
public enum UserPromptOrder {
    public static func sortedForEditing(_ prompts: [UserPrompt]) -> [UserPrompt] {
        let main = prompts.filter { $0.slot == .main }
            .sorted { $0.sortOrder < $1.sortOrder }
        let sub = prompts.filter { $0.slot == .sub }
            .sorted { $0.sortOrder < $1.sortOrder }
        return main + sub
    }

    /// Assigns the first row to `main` and gives the remaining `sub` rows a compact,
    /// deterministic order. Empty is valid after deleting the last button.
    public static func normalized(_ prompts: [UserPrompt]) -> [UserPrompt] {
        prompts.enumerated().map { index, prompt in
            var next = prompt
            next.slot = index == 0 ? .main : .sub
            next.sortOrder = index == 0 ? 0 : index - 1
            return next
        }
    }

    /// Moves one row by one position and immediately normalizes the slot contract.
    /// Returning nil means the identifier or offset was invalid, or the row is already
    /// at that edge. The UI intentionally calls this only with -1 or +1.
    public static func moving(
        _ prompts: [UserPrompt],
        id: UUID,
        by offset: Int
    ) -> [UserPrompt]? {
        guard offset == -1 || offset == 1,
              let sourceIndex = prompts.firstIndex(where: { $0.id == id })
        else { return nil }

        let destinationIndex = sourceIndex + offset
        guard prompts.indices.contains(destinationIndex) else { return nil }
        var next = prompts
        next.swapAt(sourceIndex, destinationIndex)
        return normalized(next)
    }
}
