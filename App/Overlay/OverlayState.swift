import DesktopRewriteKit
import Foundation
import TextIO

/// The states of §4, plus the two reply states of §16. `Generating` and `Result`
/// carry the captured target forward, because by the time a result exists the user's
/// selection may be long gone and the target is the only record of where the text has
/// to go back.
///
/// The reply pair is a **parallel** resting state, not a sixth step in the same line:
/// `.replyArmed` stands in for `.pill` while a copy is live, and hovering it goes
/// straight to `.replyInput` where hovering the pill goes to `.hoverRow`. From
/// `.replyInput` on, the flow rejoins §4 unchanged — generating, result, insert.
enum OverlayState: Equatable {
    case pill
    case hoverRow
    case inputBar(target: CapturedTarget)
    case generating(request: PendingRewrite)
    case result(ResultContext)
    /// A copy is live and the bar is showing it. Resting, like `.pill`.
    case replyArmed(ReplySource)
    /// The input bar, in reply mode. The target was captured on hover, before this
    /// window could take key — the same ordering `pressCustomInput` uses (§4).
    case replyInput(reply: ReplySource, target: CapturedTarget)

    var isExpanded: Bool {
        switch self {
        case .pill: return false
        case .hoverRow, .inputBar, .generating, .result, .replyArmed, .replyInput: return true
        }
    }

    /// Whether a copy is still live. `dismissReply` and the expiry timer both need to
    /// leave a rewrite that is already in flight alone.
    var isReply: Bool { replySource != nil }

    /// The live copy, in whichever of the two reply states holds it. `ReplyContextPanel`
    /// is up for both, so the states it spans are one question, not two.
    var replySource: ReplySource? {
        switch self {
        case .replyArmed(let source): return source
        case .replyInput(let source, _): return source
        case .pill, .hoverRow, .inputBar, .generating, .result: return nil
        }
    }

    /// The generating capsule and the result panel take the bar's place rather than
    /// stacking above it — `generating.png` and `result.png` both show the bottom of
    /// the screen occupied by one thing at a time, and leaving the pill underneath a
    /// result panel is just a second control with nothing to do.
    var showsPill: Bool {
        switch self {
        case .pill, .hoverRow, .inputBar, .replyArmed, .replyInput: return true
        case .generating, .result: return false
        }
    }

    /// Only the input bar and the result panel may take key, and only after capture.
    var wantsKeyWindow: Bool {
        switch self {
        case .inputBar, .replyInput: return true
        case .pill, .hoverRow, .generating, .result, .replyArmed: return false
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
        case .replyArmed: return .replyArmed
        case .replyInput: return .replyInput
        }
    }

    /// Height is a design decision (§4 fixes it at 28 pt collapsed, 34 pt expanded).
    /// Width is not specified anywhere, so SwiftUI measures it — see `ContentWidthKey`.
    var contentHeight: CGFloat {
        switch self {
        case .pill, .generating, .result:
            return Tokens.Geometry.pillHeight
        case .hoverRow, .replyArmed:
            return Tokens.Geometry.hoverRowHeight
        case .inputBar, .replyInput:
            return Tokens.Geometry.inputBarHeight
        }
    }
}

enum OverlayContentLayout: Equatable {
    case pill
    case hoverRow
    case inputBar
    case replyArmed
    case replyInput
}

/// A target plus the frontmost app it came from. The pid is needed for the clipboard
/// write path, which has to reactivate the *original* app rather than whatever is
/// frontmost when the rewrite lands.
struct CapturedTarget: Equatable {
    let target: TextTarget
    let frontmostPID: pid_t?

    static func == (lhs: CapturedTarget, rhs: CapturedTarget) -> Bool {
        lhs.target.text == rhs.target.text
            && lhs.target.captureMode == rhs.target.captureMode
            && lhs.frontmostPID == rhs.frontmostPID
    }
}

struct PendingRewrite: Equatable {
    let captured: CapturedTarget
    /// The text sent to the model. This normally matches the captured target, but a
    /// guided regeneration uses the visible candidate while `captured` keeps pointing
    /// at the original field where Insert must write the final result.
    let requestText: String
    /// The prompt text sent to the backend. Echoed in the result panel's top field
    /// per `result.png`, which is why it is held rather than discarded after the call.
    let promptText: String
    /// The copied message being replied to, or nil outside reply mode (§16). Held
    /// rather than read off the state because ↻ regenerates from `pending` alone, and
    /// a regenerate that dropped this would silently rewrite the user's draft instead
    /// of re-composing the reply.
    let replyTo: String?
    /// The button's own title, or nil for the custom-input path.
    let buttonTitle: String?
    /// Tutorial rewrites exercise the real backend and write path, but are not part
    /// of the user's history or statistics.
    let isTutorial: Bool
    let startedAt: Date
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
