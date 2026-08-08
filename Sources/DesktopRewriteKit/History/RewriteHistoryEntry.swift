import Foundation

/// One rewrite, as the main window's ホーム page shows it.
///
/// This is a **local** record. `desktop.rewrite_events` exists on the server, but
/// every `public.desktop_*` entry point is `REVOKE EXECUTE`d from `authenticated`
/// (§6) — the client cannot read its own rows back without a new grant on a project
/// the iOS app also lives behind. Counting on-device costs no migration, no privacy
/// surface, and works offline; the price is that the numbers are per-Mac and start
/// at install.
public struct RewriteHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    /// The button's own title, or nil for the ✎ custom-input path.
    public let buttonTitle: String?
    public let promptText: String
    public let originalText: String
    public let rewrittenText: String
    public let hostAppBundleId: String?
    /// Whether the user actually inserted it. Set later, on the write, which is why
    /// this is the one `var` — everything else is fixed at record time.
    public var accepted: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        buttonTitle: String?,
        promptText: String,
        originalText: String,
        rewrittenText: String,
        hostAppBundleId: String?,
        accepted: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.buttonTitle = buttonTitle
        self.promptText = promptText
        self.originalText = originalText
        self.rewrittenText = rewrittenText
        self.hostAppBundleId = hostAppBundleId
        self.accepted = accepted
    }

    /// What the ホーム list labels the row. A custom-input rewrite has no button.
    public var label: String {
        buttonTitle ?? "カスタム"
    }
}
