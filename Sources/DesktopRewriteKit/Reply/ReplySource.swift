import Foundation

/// A message the user copied, held as the thing a reply gets composed *to* (§16).
///
/// Pure, so the arming rules are the testable part: `ClipboardWatcher` supplies a
/// pasteboard string and a clock, and everything that decides whether a copy is worth
/// widening the bar for lives here.
public struct ReplySource: Equatable, Sendable {

    /// The one filter, and it is deliberately a blunt one.
    ///
    /// **Counted in characters, which is why it is this low.** The first number tried
    /// was 20, and 「明日の打ち合わせは大丈夫でしょうか。」 — an entirely ordinary message
    /// someone would want to reply to — is 18. Japanese runs at roughly twice the
    /// information density of English per character, so a threshold set by eye against
    /// ASCII noise silently excludes real Japanese messages, which is the failure that
    /// matters. 12 admits nearly every real one-line message.
    ///
    /// The price is honest and known: a copied URL or file path longer than this arms
    /// the bar. That is what ✕ is for. Filtering it out properly would mean guessing at
    /// the *shape* of the text, and a rule that silently declines is much harder to
    /// explain than a bar that occasionally appears when it need not have.
    public static let minimumCharacters = 12

    /// The bound on what `ReplyContextPanel` renders. Far more than one line holds —
    /// the pill truncates visually with an ellipsis, and this is only here so SwiftUI is
    /// never handed a 10,000-character string to lay out. The full text still goes over
    /// the wire as `replyTo`; the backend has its own limit (`DESKTOP_MAX_REWRITE_CHARS`).
    public static let contextCharacters = 500

    /// How long a copy stays armed. The flow is copy → switch app → hover, which takes
    /// seconds. Past a few minutes the bar is describing something the user has
    /// forgotten they copied, and a bar that misdescribes itself is worse than the
    /// collapsed pill.
    public static let lifetime: TimeInterval = 180

    /// Trimmed, and what goes over the wire as `replyTo`.
    public let text: String
    public let copiedAt: Date

    /// Nil when the copy is not something to reply to.
    public init?(copied text: String, at copiedAt: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumCharacters else { return nil }
        self.text = trimmed
        self.copiedAt = copiedAt
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(copiedAt) >= Self.lifetime
    }

    /// What `ReplyContextPanel` shows, and the only rendering there is — the armed bar
    /// deliberately carries no copy of it.
    ///
    /// **Flattened**, because the pill is one line at a fixed height. A copied message
    /// arrives with its newlines intact and `lineLimit(1)` would cut it at the first
    /// one, showing a first line that is often just a greeting; joined with spaces, the
    /// same width shows the part that says what the message is about.
    public var contextText: String {
        let flattened = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard flattened.count > Self.contextCharacters else { return flattened }
        return String(flattened.prefix(Self.contextCharacters)) + "…"
    }
}
