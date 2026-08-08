import Foundation

// COPIED from ../Japanese/Sources/JapaneseKeyboardAI/Models/RewriteModels.swift.
// `RewriteRequest` here is a SUPERSET (§6): the four macOS fields are additive, so
// a payload from this app is still a valid payload for the shared contract, and
// `RewriteResult` is unchanged in both directions.

public enum RefinementIntent: String, Codable, CaseIterable, Sendable {
    case morePolite
    case moreDetailed
    case moreConcise

    public var title: String {
        switch self {
        case .morePolite: return "より丁寧に"
        case .moreDetailed: return "より詳しく"
        case .moreConcise: return "より短く"
        }
    }
}

/// How the target text was captured. Maps onto the AX read in §5.
///
/// `fullDocument` exists on iOS (stitched by `FullDocumentReader`) and has no
/// macOS analogue — `kAXValue` already returns the whole field. It stays in the
/// enum so the two repos decode each other's rows.
public enum CaptureMode: String, Codable, Sendable {
    case wholeInput
    case selection
    case fullDocument
}

public struct RewriteRequest: Codable, Sendable {
    public let prompt: String
    public let text: String
    /// The message being replied to (reply mode). When present the backend
    /// composes a reply to this instead of rewriting `text`.
    public let replyTo: String?
    public let commandKey: String?
    public let title: String?
    public let promptOrigin: String?
    public let locale: String
    public let appVersion: String
    public let candidateCount: Int
    public let refinement: RefinementIntent?
    public let analyticsAppInstanceId: String?
    /// True when `text` is a fragment the user selected inside a larger text.
    public let selection: Bool
    /// Window-truncated host text around the selection, sent for rewrite quality
    /// only — the backend must never store it.
    public let selectionContextBefore: String?
    public let selectionContextAfter: String?
    public let stream: Bool

    // MARK: macOS superset (§6)

    /// Always `"macos"` from this app. Lets one function serve both surfaces
    /// while keeping `desktop.rewrite_events` separable from `ai_rewrite_events`.
    public let surface: String
    /// e.g. `com.apple.mail`. Used for prompt shaping and for the analytics
    /// property that makes a per-app AX regression visible (§7).
    public let hostAppBundleId: String?
    public let captureMode: CaptureMode
    /// Only populated when the host app is a browser.
    public let browserURL: String?
    /// `"ax"` or `"clipboard"`. Only the client knows which path it actually used,
    /// and §7 makes this the earliest signal that an app's AX tree changed — so it
    /// has to go over the wire or `desktop.rewrite_events.io_path` stays null.
    ///
    /// Typed as a plain `String` rather than importing `TextIOPath`: the dependency
    /// runs the other way (`TextIO` depends on this module), and inverting it to
    /// share one enum would be a cycle.
    public let ioPath: String?

    public init(
        prompt: String,
        text: String,
        replyTo: String? = nil,
        commandKey: String? = nil,
        title: String? = nil,
        promptOrigin: String? = nil,
        locale: String = Locale.current.identifier,
        appVersion: String,
        candidateCount: Int = 3,
        refinement: RefinementIntent? = nil,
        analyticsAppInstanceId: String? = nil,
        selection: Bool = false,
        selectionContextBefore: String? = nil,
        selectionContextAfter: String? = nil,
        stream: Bool = false,
        hostAppBundleId: String? = nil,
        captureMode: CaptureMode,
        browserURL: String? = nil,
        ioPath: String? = nil
    ) {
        self.prompt = prompt
        self.text = text
        self.replyTo = replyTo
        self.commandKey = commandKey
        self.title = title
        self.promptOrigin = promptOrigin
        self.locale = locale
        self.appVersion = appVersion
        self.candidateCount = candidateCount
        self.refinement = refinement
        self.analyticsAppInstanceId = analyticsAppInstanceId
        self.selection = selection
        self.selectionContextBefore = selectionContextBefore
        self.selectionContextAfter = selectionContextAfter
        self.stream = stream
        self.surface = "macos"
        self.hostAppBundleId = hostAppBundleId
        self.captureMode = captureMode
        self.browserURL = browserURL
        self.ioPath = ioPath
    }
}

public struct RewriteCandidate: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let replacement: String
    public let changed: Bool

    public init(id: UUID = UUID(), replacement: String, changed: Bool) {
        self.id = id
        self.replacement = replacement
        self.changed = changed
    }

    private enum CodingKeys: String, CodingKey {
        case id, replacement, changed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.replacement = try container.decode(String.self, forKey: .replacement)
        self.changed = try container.decodeIfPresent(Bool.self, forKey: .changed) ?? true
    }
}

public struct RewriteResult: Codable, Equatable, Sendable {
    public let candidates: [RewriteCandidate]
    public let language: String
    /// Server id of the logged rewrite event. Sent back via `submitSelection`
    /// when the user accepts a candidate so the choice can be recorded.
    public let eventId: String?

    public init(candidates: [RewriteCandidate], language: String, eventId: String? = nil) {
        self.candidates = candidates
        self.language = language
        self.eventId = eventId
    }
}
