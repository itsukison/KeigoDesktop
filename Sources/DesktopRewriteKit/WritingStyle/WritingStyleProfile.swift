import Foundation

public enum WritingContext: String, Codable, CaseIterable, Sendable {
    case email, workChat = "work_chat", personal, other

    public var voiceOptions: [String] {
        switch self {
        case .email: return ["relaxed", "polite", "formal"]
        case .workChat: return ["casual", "neutral", "polite"]
        case .personal: return ["casual", "polite", "formal"]
        case .other: return ["conversational", "neutral", "formal"]
        }
    }
    public var detailKey: String {
        switch self {
        case .email: return "organization"
        case .workChat: return "presentation"
        case .personal: return "rhythm"
        case .other: return "editStrength"
        }
    }
    public var detailOptions: [String] {
        switch self {
        case .email: return ["preserve", "readable", "reorganize"]
        case .workChat: return ["concise", "balanced", "detailed"]
        case .personal: return ["preserve", "moderate", "frequent"]
        case .other: return ["light", "flow", "rework"]
        }
    }
    public var defaultVoice: String {
        switch self {
        case .email, .personal: return "polite"
        case .workChat, .other: return "neutral"
        }
    }
    public var defaultDetail: String {
        switch self {
        case .email: return "readable"
        case .workChat: return "balanced"
        case .personal: return "moderate"
        case .other: return "flow"
        }
    }

    func migratedDetail(_ value: String) -> String {
        guard self == .workChat else { return value }
        switch value {
        case "preserve", "streamline": return "balanced"
        case "structure": return "detailed"
        default: return value
        }
    }
}

public struct WritingStyleProfile: Codable, Equatable, Sendable {
    public let context: WritingContext
    public private(set) var voice: String
    public private(set) var detail: String
    public var notes: String

    public init(context: WritingContext) {
        self.context = context
        voice = context.defaultVoice
        detail = context.defaultDetail
        notes = ""
    }

    public mutating func chooseVoice(_ value: String) {
        guard context.voiceOptions.contains(value) else { return }
        voice = value
    }
    public mutating func chooseDetail(_ value: String) {
        guard context.detailOptions.contains(value) else { return }
        detail = value
    }

    private enum CodingKeys: String, CodingKey { case context, voice, detail, notes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        context = try c.decode(WritingContext.self, forKey: .context)
        voice = try c.decodeIfPresent(String.self, forKey: .voice) ?? context.defaultVoice
        detail = context.migratedDetail(try c.decodeIfPresent(String.self, forKey: .detail) ?? context.defaultDetail)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        guard context.voiceOptions.contains(voice), context.detailOptions.contains(detail),
              notes.unicodeScalars.count <= 500 else {
            throw DecodingError.dataCorruptedError(forKey: .voice, in: c, debugDescription: "Invalid writing style")
        }
    }
}

public enum WritingContextSource: String, Codable, Sendable {
    case userOnce = "user_once", userMapping = "user_mapping", knownSurface = "known_surface"
    case appDefault = "app_default", unknown
}

public struct ResolvedWritingStyle: Codable, Equatable, Sendable {
    public let profile: WritingStyleProfile
    public let source: WritingContextSource
    public init(profile: WritingStyleProfile, source: WritingContextSource) {
        self.profile = profile
        self.source = source
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, context, voice, organization, presentation, rhythm, editStrength, notes, source, resolverVersion
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .version)
        try c.encode(1, forKey: .resolverVersion)
        try c.encode(profile.context, forKey: .context)
        try c.encode(profile.voice, forKey: .voice)
        try c.encode(profile.detail, forKey: CodingKeys(rawValue: profile.context.detailKey)!)
        try c.encode(profile.notes, forKey: .notes)
        try c.encode(source, forKey: .source)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let context = try c.decode(WritingContext.self, forKey: .context)
        let inappropriate = [CodingKeys.organization, .presentation, .rhythm, .editStrength]
            .filter { $0.rawValue != context.detailKey }
        guard inappropriate.allSatisfy({ !c.contains($0) }) else {
            throw DecodingError.dataCorruptedError(forKey: .context, in: c, debugDescription: "Cross-context style field")
        }
        let voice = try c.decode(String.self, forKey: .voice)
        let detail = context.migratedDetail(try c.decode(String.self, forKey: CodingKeys(rawValue: context.detailKey)!))
        let notes = try c.decode(String.self, forKey: .notes)
        guard try c.decode(Int.self, forKey: .version) == 1,
              try c.decode(Int.self, forKey: .resolverVersion) == 1,
              context.voiceOptions.contains(voice), context.detailOptions.contains(detail),
              notes.unicodeScalars.count <= 500 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "Unsupported writing style")
        }
        var p = WritingStyleProfile(context: context)
        p.chooseVoice(voice); p.chooseDetail(detail); p.notes = notes
        profile = p
        source = try c.decode(WritingContextSource.self, forKey: .source)
    }
}
