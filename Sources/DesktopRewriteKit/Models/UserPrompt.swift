import Foundation

// COPIED from ../Japanese/Sources/KeyboardPreferences/UserPrompts.swift.
// `user_prompts` is the one table both surfaces read and write (AGENTS.md §2), so
// this type is a contract owned by the iOS repo. Any change here is a two-repo
// change — note it in the PR.
//
// Deliberately narrower than the original: the App Group cache (`UserPromptStore`)
// and the built-in seed set are iOS-only. A desktop user with no buttons is a
// user who has not finished onboarding on their phone, and seeding local
// defaults here would write rows the phone never asked for.

/// Where a button came from. Retention differs sharply by origin — a button the
/// user authored predicts sustained use far better than one they merely picked
/// from a preset — so this rides along with the rewrite request and lands in
/// analytics next to `command_key`, which cannot tell the two apart on its own.
public enum PromptOrigin: String, Codable, Sendable {
    case builtin
    case onboardingBuilder = "onboarding_builder"
    case onboardingPreset = "onboarding_preset"
    case userAuthored = "user_authored"
}

public struct UserPrompt: Codable, Equatable, Identifiable, Sendable {
    public enum Slot: String, Codable, Sendable {
        case main
        case sub
    }

    public let id: UUID
    public var slot: Slot
    public let builtinKey: String?
    public var title: String
    public var prompt: String
    public var isEnabled: Bool
    public var sortOrder: Int
    public var origin: PromptOrigin
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        slot: Slot,
        builtinKey: String? = nil,
        title: String,
        prompt: String,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        origin: PromptOrigin? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.slot = slot
        self.builtinKey = builtinKey
        self.title = title
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.origin = origin ?? Self.inferredOrigin(builtinKey: builtinKey)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Rows written before `origin` existed decode without it. Infer rather than
    /// fail: a `builtin_key` means it is seeded, anything else was hand-made.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        slot = try container.decode(Slot.self, forKey: .slot)
        builtinKey = try container.decodeIfPresent(String.self, forKey: .builtinKey)
        title = try container.decode(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        origin = try container.decodeIfPresent(PromptOrigin.self, forKey: .origin)
            ?? Self.inferredOrigin(builtinKey: builtinKey)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    private static func inferredOrigin(builtinKey: String?) -> PromptOrigin {
        builtinKey == nil ? .userAuthored : .builtin
    }
}

public extension Array where Element == UserPrompt {
    /// What the hover row shows, in the order it shows them (§4).
    ///
    /// Both slots are flattened into one row: `main` first, then `sub` by
    /// `sortOrder`. iOS distinguishes the two because its toolbar has one primary
    /// button and a secondary tray; a single horizontal row has no such split, and
    /// hiding the `main` button because it lives in a different slot would drop the
    /// user's most-used button.
    var enabledForHoverRow: [UserPrompt] {
        let main = filter { $0.slot == .main && $0.isEnabled }
            .sorted { $0.sortOrder < $1.sortOrder }
        let sub = filter { $0.slot == .sub && $0.isEnabled }
            .sorted { $0.sortOrder < $1.sortOrder }
        return main + sub
    }
}
