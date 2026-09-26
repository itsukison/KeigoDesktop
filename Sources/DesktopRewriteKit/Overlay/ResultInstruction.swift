import Foundation

/// Local presentation metadata; backend prompts can include instructions the user never typed.
public enum ResultInstruction: Equatable, Sendable {
    case hidden
    case userProvided(String)

    public static func input(_ text: String) -> Self {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .hidden : .userProvided(text)
    }

    public var text: String? {
        if case .userProvided(let text) = self { return text }
        return nil
    }

    public func regenerated(edit: String?) -> Self {
        edit.map(Self.input) ?? self
    }
}
