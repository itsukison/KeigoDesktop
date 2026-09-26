import DesktopRewriteKit
import Foundation
import TextIO

/// The states of §4, plus the two reply states of §16. `Generating` and `Result`
/// carry the captured target forward, because by the time a result exists the user's
/// selection may be long gone and the target is the only record of where the text has
/// to go back.
enum OverlayState: Equatable {
    case pill
    case hoverRow
    case inputBar(target: CapturedTarget)
    case explicitReply(target: CapturedTarget)
    case generating(request: PendingRewrite)
    case result(ResultContext)
    /// Reply was clicked and the destination captured before taking key.
    case replyInput(reply: ReplySource, target: CapturedTarget)

    var isExpanded: Bool {
        switch self {
        case .pill: return false
        case .explicitReply, .hoverRow, .inputBar, .generating, .result, .replyInput: return true
        }
    }

    var isReply: Bool { if case .explicitReply = self { return true }; return replySource != nil }

    /// A source is active only after the user chooses Reply.
    var replySource: ReplySource? {
        switch self {
        case .replyInput(let source, _): return source
        case .explicitReply, .pill, .hoverRow, .inputBar, .generating, .result: return nil
        }
    }

    /// Just the case, for `destinationLog`. Never `String(describing:)` — the associated
    /// values carry the user's captured and rewritten text.
    var name: String {
        switch self {
        case .pill: return "pill"
        case .hoverRow: return "hoverRow"
        case .inputBar: return "inputBar"
        case .explicitReply: return "explicitReply"
        case .generating: return "generating"
        case .result: return "result"
        case .replyInput: return "replyInput"
        }
    }

    /// The generating capsule and the result panel take the bar's place rather than
    /// stacking above it — `generating.png` and `result.png` both show the bottom of
    /// the screen occupied by one thing at a time, and leaving the pill underneath a
    /// result panel is just a second control with nothing to do.
    var showsPill: Bool {
        switch self {
        case .explicitReply, .pill, .hoverRow, .inputBar, .replyInput: return true
        case .generating, .result: return false
        }
    }

    /// Only the input bar and the result panel may take key, and only after capture.
    var wantsKeyWindow: Bool {
        switch self {
        case .explicitReply, .inputBar, .replyInput: return true
        case .pill, .hoverRow, .generating, .result: return false
        }
    }

    /// Whether Sparkle may run a check right now. A scheduled updater window can take
    /// key, which is safe only while the bar is resting — anywhere else it would
    /// interrupt capture, typing, a rewrite in flight, or a result being judged.
    var allowsUpdateCheck: Bool {
        switch self {
        case .pill: return true
        case .explicitReply, .hoverRow, .inputBar, .generating, .result, .replyInput: return false
        }
    }

    /// The SwiftUI subtree whose intrinsic size drives `PillPanel`.
    ///
    /// This is deliberately separate from the state itself: generating and result both
    /// leave the hidden panel holding the same collapsed mark, while the two input bars
    /// need distinct identities even when they happen to measure to the same size. A
    /// changed identity makes the preference callback deliver a fresh measurement for
    /// the new subtree before AppKit starts its one frame animation.
    var contentLayout: OverlayContentLayout {
        switch self {
        case .pill, .generating, .result: return .pill
        case .hoverRow: return .hoverRow
        case .inputBar: return .inputBar
        case .explicitReply: return .replyInput
        case .replyInput: return .replyInput
        }
    }

    /// Height is a design decision (§4 fixes it at 28 pt collapsed, 34 pt expanded).
    /// Width is not specified anywhere, so SwiftUI measures it — see `ContentWidthKey`.
    var contentHeight: CGFloat {
        switch self {
        case .pill, .generating, .result:
            return Tokens.Geometry.pillHeight
        case .hoverRow:
            return Tokens.Geometry.hoverRowHeight
        case .explicitReply, .inputBar, .replyInput:
            return Tokens.Geometry.inputBarHeight
        }
    }
}

/// What the result panel's primary button will do, decided from a live read of the
/// destination rather than from what was captured (§18).
///
/// The whole point is that this is known *before* the button is pressed. A result that
/// can only be copied used to be presented with 挿入 as its primary action, and the
/// press wrote the text into nothing.
enum InsertAction: Equatable {
    /// The field the rewrite came from is still there.
    case insert
    /// It is not, but the user is in another field that can take text. The rewrite goes
    /// in at the caret there.
    case insertHere
    /// Nowhere to write. The primary action is Copy, and the panel says why.
    case copyOnly
}

/// What the user pressed, as opposed to what the probe thinks. See
/// `OverlayController.insert(intent:)`.
enum InsertIntent: Equatable {
    case write
    case copy
}

enum OverlayContentLayout: Equatable {
    case pill
    case hoverRow
    case inputBar
    case replyInput
}

/// A target plus the frontmost app it came from. The pid is needed for the clipboard
/// write path, which has to reactivate the *original* app rather than whatever is
/// frontmost when the rewrite lands.
struct CapturedTarget: Equatable {
    let target: TextTarget
    let frontmostPID: pid_t?
    var browserReplyBinding: BrowserReplyBinding? = nil
    var writingStyle: ResolvedWritingStyle? = nil
    var writingLanguageCode: String = AppLanguageState.current.writingLanguageCode

    static func == (lhs: CapturedTarget, rhs: CapturedTarget) -> Bool {
        lhs.target.text == rhs.target.text
            && lhs.target.captureMode == rhs.target.captureMode
            && lhs.frontmostPID == rhs.frontmostPID
            && lhs.browserReplyBinding == rhs.browserReplyBinding
            && lhs.writingStyle == rhs.writingStyle
            && lhs.writingLanguageCode == rhs.writingLanguageCode
    }
}

struct PendingRewrite: Equatable {
    let captured: CapturedTarget
    /// The text sent to the model. This normally matches the captured target, but a
    /// guided regeneration uses the visible candidate while `captured` keeps pointing
    /// at the original field where Insert must write the final result.
    let requestText: String
    /// The prompt sent to the backend, retained for regeneration.
    let promptText: String
    var instruction: ResultInstruction = .hidden
    /// The copied message being replied to, or nil outside reply mode (§16). Held
    /// rather than read off the state because ↻ regenerates from `pending` alone, and
    /// a regenerate that dropped this would silently rewrite the user's draft instead
    /// of re-composing the reply.
    let replyTo: String?
    let replyContext: ReplyContext?
    let draftReadStatus: ReplyDraftReadStatus?
    var isReply: Bool { replyTo != nil || replyContext != nil }
    /// The button's own title, or nil for the custom-input path.
    let buttonTitle: String?
    /// The attempt this rewrite belongs to. Held on the pending request rather than
    /// only on the controller because Insert and Copy happen long after the generation
    /// finished — often several pages later in the result panel — and they have to
    /// report against the attempt that produced *that* candidate, not the newest one.
    let attempt: RewriteAttempt
    let startedAt: Date
    var lessonID: UUID? = nil

    /// Tutorial rewrites exercise the real backend and write path, but are not part
    /// of the user's history or statistics. Read off the attempt so there is one
    /// source of truth for it rather than two fields that can disagree.
    var isTutorial: Bool { attempt.isTutorial }
}

/// One selectable page in the result panel. Each backend response owns its event id
/// and candidate index, and each history row owns its own id; keeping those beside the
/// text prevents navigating backward from sending feedback or acceptance to the newest
/// response by mistake.
struct ResultPage: Equatable {
    let pending: PendingRewrite
    let candidate: RewriteCandidate
    let eventId: String?
    let responseCandidateIndex: Int
    let historyEntryId: UUID?
}

struct ResultContext: Equatable {
    private(set) var pages: [ResultPage]
    var selectedIndex: Int

    init(pending: PendingRewrite, result: RewriteResult, historyEntryId: UUID?) {
        pages = Self.makePages(
            pending: pending,
            result: result,
            historyEntryId: historyEntryId
        )
        selectedIndex = 0
    }

    var selectedPage: ResultPage? {
        pages.indices.contains(selectedIndex) ? pages[selectedIndex] : pages.first
    }

    var candidate: RewriteCandidate? { selectedPage?.candidate }
    var count: Int { pages.count }

    /// Adds every candidate from a newly completed request and selects the first new
    /// page. Desktop currently requests one, while preserving all candidates keeps the
    /// pager correct if that request policy changes later.
    mutating func append(pending: PendingRewrite, result: RewriteResult, historyEntryId: UUID?) {
        let next = Self.makePages(
            pending: pending,
            result: result,
            historyEntryId: historyEntryId
        )
        guard !next.isEmpty else { return }
        selectedIndex = pages.count
        pages.append(contentsOf: next)
    }

    var pagerLabel: String {
        guard !pages.isEmpty else { return "0 / 0" }
        return "\(min(selectedIndex + 1, pages.count)) / \(pages.count)"
    }

    private static func makePages(
        pending: PendingRewrite,
        result: RewriteResult,
        historyEntryId: UUID?
    ) -> [ResultPage] {
        result.candidates.enumerated().map { index, candidate in
            ResultPage(
                pending: pending,
                candidate: candidate,
                eventId: result.eventId,
                responseCandidateIndex: index,
                // History currently records the first candidate from each response;
                // desktop asks for exactly one, so this is the normal path.
                historyEntryId: index == 0 ? historyEntryId : nil
            )
        }
    }
}
