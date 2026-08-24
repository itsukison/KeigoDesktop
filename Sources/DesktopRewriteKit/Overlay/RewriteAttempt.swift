import Foundation

/// Which of the five ways into a generation an attempt came from.
///
/// **This replaces `prompt_origin` as the answer to "what did the user do".** Until
/// 2026-08-24 four distinct interactions all reported `prompt_origin: custom` — the ✎
/// bar, reply mode, ↻ regenerate and a follow-up refinement — because that property is
/// nil for all four and the analytics layer defaulted nil to `"custom"`. Measured on the
/// live project the day this shipped: 45 of 96 real completed rewrites were in that
/// bucket, and only the 16 carrying `is_reply` could be separated out. The remaining 29
/// were unattributable, which made "which buttons earn their place on the row"
/// — `prompt_origin`'s stated purpose — unanswerable.
///
/// `prompt_origin` survives and now means only what its name says: *which* saved or
/// builtin button, for the one type where that question exists.
///
/// **Deliberately orthogonal to `isTutorial`.** Onboarding practice is a context, not a
/// sixth kind of interaction — the tutorial teaches three of these five types, so
/// folding it in here would make "what did they practise" unmeasurable and would force
/// every dashboard tile to remember a magic enum value instead of setting one boolean
/// filter.
///
/// The raw values are the wire format and a renaming splits a series after the fact, so
/// they are pinned by `RewriteAttemptTests`.
public enum RewriteType: String, Sendable, CaseIterable, Equatable {
    /// A saved or builtin button on the hover row.
    case savedButton = "saved_button"
    /// The ✎ bar — a free-text instruction the user typed.
    case customInstruction = "custom_instruction"
    /// Reply mode: composing an answer to a copied message (§16).
    case reply
    /// ↻ — the same request run again, with or without an edited prompt.
    case regenerate
    /// A follow-up instruction applied to the candidate already on screen.
    case refine
}

/// How far an attempt got before it failed.
///
/// The distinction is not cosmetic: of the 17 failures external users hit before this
/// shipped, **all 17 were capture failures** — 「書き換える文章がありません」 and its two
/// translations — and none was a model or network error. Those are opposite problems
/// (one is a UI affordance, the other is a backend incident) and the only thing that
/// separated them was reading the Japanese toast string.
public enum FailureStage: String, Sendable, CaseIterable, Equatable {
    /// Nothing could be read to rewrite. Happens before there is a target at all.
    case capture
    /// The request was sent and the backend or network did not return a result.
    case generation
}

/// Why an attempt ended without a result the user could see.
public enum AbandonReason: String, Sendable, CaseIterable, Equatable {
    /// A newer attempt replaced this one before it returned.
    case superseded
    /// The user dismissed the panel or pressed Escape while it was generating.
    case dismissed
}

/// The identity of one generation attempt, carried by every event that attempt emits.
///
/// `id` is what makes the funnel exact. Without it `started → completed → inserted` can
/// only be correlated by per-person event ordering, which is wrong the moment someone
/// presses a second button while the first is still generating — precisely the case
/// `AbandonReason.superseded` exists to describe.
public struct RewriteAttempt: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let type: RewriteType
    public let isTutorial: Bool

    public init(type: RewriteType, isTutorial: Bool, id: UUID = UUID()) {
        self.id = id
        self.type = type
        self.isTutorial = isTutorial
    }
}

/// The three ways a generation can end. Exactly one is reported per attempt.
public enum RewriteOutcome: Sendable, Equatable {
    case completed
    case failed(FailureStage)
    case abandoned(AbandonReason)
}

/// Owns the "exactly one terminal event per `desktop_rewrite_started`" invariant.
///
/// The rule this type exists to make unbreakable: **for every attempt that `begin`
/// opens, exactly one of `completed` / `failed` / `abandoned` is reported.** Without it
/// the funnel has no denominator anyone can trust — a `started` with no ending is an
/// attempt that was generated and billed and then vanished, and two endings double-count
/// a single press.
///
/// It is enforced structurally rather than by convention, in two moves:
///
///   - `finish()` returns the open attempt and clears it, so a **second** terminal report
///     for the same attempt gets nil and emits nothing. Every exit path can therefore
///     call it unconditionally, including the paths that overlap — a dismiss racing the
///     response, or an error presenter reached from a state that never started a
///     generation.
///   - `begin()` hands back whatever was still open, so a caller **cannot** silently
///     drop a superseded attempt: the value has to be dealt with to open the new one.
///     Before this existed, a second press while the first was generating cancelled the
///     first request — already sent and metered by `desktop-rewrite` — and reported
///     nothing at all, because the cancellation check sat in front of the analytics call.
///
/// Deliberately *not* responsible for `inserted` / `copied`. Those happen after the
/// generation is finished, often several result-panel pages later, and they report
/// against `PendingRewrite.attempt` rather than against whatever is open now.
public struct RewriteAttemptTracker: Sendable, Equatable {
    /// The generation currently in flight, or nil when none is.
    public private(set) var active: RewriteAttempt?

    public init() {}

    /// Opens `attempt`.
    ///
    /// - Returns: the attempt that was still open and must now be reported as
    ///   `abandoned(.superseded)`, or nil in the normal case.
    @discardableResult
    public mutating func begin(_ attempt: RewriteAttempt) -> RewriteAttempt? {
        let superseded = active
        active = attempt
        return superseded
    }

    /// Closes the open attempt.
    ///
    /// - Returns: the attempt to report a terminal event for, or nil when there is
    ///   nothing open — which is what makes a duplicate terminal report a no-op rather
    ///   than a second event.
    @discardableResult
    public mutating func finish() -> RewriteAttempt? {
        defer { active = nil }
        return active
    }
}

/// One reported analytics event, reduced to the parts the invariant is about.
///
/// Exists so the invariant can be *checked* rather than only asserted about a tracker in
/// isolation: `RewriteFunnel.violations` runs over a recorded sequence, so a test can
/// encode each real controller path (press → success, press → capture failure, press →
/// press → success, …) and fail if that path stops satisfying the rule. The same checker
/// can be pointed at a day of exported events to audit the live stream.
public enum RewriteFunnelEvent: Sendable, Equatable {
    case started(RewriteAttempt)
    case ended(RewriteAttempt, RewriteOutcome)
    /// `inserted` / `copied`. Must follow a `completed` for the same attempt.
    case accepted(RewriteAttempt)
}

/// A violation of the funnel's shape, named precisely enough to act on.
public enum RewriteFunnelViolation: Sendable, Equatable, Hashable {
    /// A `started` that never ended. The attempt was generated and reported nothing.
    case neverEnded(UUID)
    /// A second terminal event for one attempt.
    case endedTwice(UUID)
    /// A terminal event for an attempt that never started.
    case endedWithoutStart(UUID)
    /// Two `started` events sharing one id.
    case startedTwice(UUID)
    /// An `inserted` / `copied` for an attempt that did not complete.
    case acceptedWithoutCompletion(UUID)
}

public enum RewriteFunnel {
    /// Checks a recorded event sequence against the invariant.
    ///
    /// An empty result is the whole contract: every `started` has exactly one ending,
    /// nothing ends twice or without starting, and nothing is accepted that did not
    /// complete.
    public static func violations(in events: [RewriteFunnelEvent]) -> [RewriteFunnelViolation] {
        var started: Set<UUID> = []
        var ended: [UUID: RewriteOutcome] = [:]
        var violations: [RewriteFunnelViolation] = []

        for event in events {
            switch event {
            case .started(let attempt):
                guard started.insert(attempt.id).inserted else {
                    violations.append(.startedTwice(attempt.id))
                    continue
                }

            case .ended(let attempt, let outcome):
                if !started.contains(attempt.id) {
                    violations.append(.endedWithoutStart(attempt.id))
                    continue
                }
                if ended[attempt.id] != nil {
                    violations.append(.endedTwice(attempt.id))
                    continue
                }
                ended[attempt.id] = outcome

            case .accepted(let attempt):
                if ended[attempt.id] != .completed {
                    violations.append(.acceptedWithoutCompletion(attempt.id))
                }
            }
        }

        // Order the unended ids so the failure message is stable rather than
        // set-iteration order.
        for id in started.subtracting(ended.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
            violations.append(.neverEnded(id))
        }
        return violations
    }
}
