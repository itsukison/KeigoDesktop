import AppKit
import DesktopRewriteKit
import Foundation
import PostHog
import TextIO

/// Why the rewrite left on the clipboard instead of going into a field. Both values are
/// the user taking the result, and separating them is the only way to see whether §18's
/// copy path is a rescue or a habit.
enum CopyReason: String, Sendable {
    /// There was nowhere to insert, so Copy was the primary action offered.
    case noDestination = "no_destination"
    /// The user pressed the copy button next to a working Insert.
    case userChose = "user_chose"
}

protocol Analytics: Sendable {
    /// The attempt denominator. Emitted once per generation request, before the network
    /// call, so that a failure or an abandonment still has something to be a fraction of.
    func rewriteStarted(_ attempt: RewriteAttempt, target: TextTarget?)
    func rewriteCompleted(
        _ attempt: RewriteAttempt,
        target: TextTarget,
        promptOrigin: String?,
        isReply: Bool,
        candidateCount: Int,
        latencyMs: Int
    )
    func rewriteFailed(
        _ attempt: RewriteAttempt,
        stage: FailureStage,
        message: String,
        target: TextTarget?
    )
    func rewriteAbandoned(
        _ attempt: RewriteAttempt,
        reason: AbandonReason,
        target: TextTarget?
    )
    func inserted(
        _ attempt: RewriteAttempt,
        target: TextTarget,
        isReply: Bool,
        selectedIndex: Int,
        destination: InsertAction
    )
    func copied(
        _ attempt: RewriteAttempt,
        target: TextTarget,
        isReply: Bool,
        reason: CopyReason
    )
}

/// Properties every rewrite event carries for a reason that has nothing to do with the
/// rewrite itself. Appended to each event rather than duplicated into six literals.
///
/// - `attempt_id` ties the six events of one attempt together (see `RewriteAttempt`).
/// - `rewrite_type` is the five-way split `prompt_origin` could not provide.
/// - `button_key` is the privacy-safe saved-button purpose; it never contains a title,
///   prompt, captured text or rewritten text.
/// - `is_tutorial` closed `docs/analytics.md` §3's third gap. Onboarding practice calls the same
///   methods as a real press and all three lessons complete *only* on a successful
///   Insert, so every new user used to donate three guaranteed acceptances to the
///   acceptance-rate tile. Measured on 2026-08-22: 38 of 117 completed rewrites were
///   practice, and 14 of the 18 belonging to users who are not the owners.
/// - `accessibility_granted` is read **live**, not taken from the super property of the
///   same name. The super property is stored, so it is only as fresh as the last
///   `MainModel.refresh()` — and the one event where the distinction decides the answer
///   is a `TextIOError.notTrusted` failure, which is precisely the moment the stored
///   value is wrong. Registered *and* sent, deliberately: a gap between the two readings
///   of the same row is a permission that changed without the window ever activating.
private func attemptProperties(_ attempt: RewriteAttempt) -> [String: Any] {
    [
        "attempt_id": attempt.id.uuidString,
        "rewrite_type": attempt.type.rawValue,
        "button_key": attempt.buttonAnalyticsKey as Any,
        "is_tutorial": attempt.isTutorial,
        "accessibility_granted": AXPermission.isTrusted,
    ]
}

/// The frontmost app, for the events that have no target to read it off.
///
/// `NSWorkspace` rather than AX: the question is "which app was the user in", not
/// "where would a keystroke land", and a capture failure means the AX answer is exactly
/// the thing that was unavailable. `TextIO.BundleIdentity` answers the same question
/// from a pid but is internal to that module by design — §3 keeps AppKit out of
/// `Sources/`, and this file is in `App/`, where asking AppKit directly is the shorter
/// true answer.
private func frontmostBundleId() -> String? {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
}

/// The target-shaped properties, for the events that have a target.
///
/// Optional because a capture failure has none — and that is the whole reason
/// `desktop_rewrite_failed` used to carry no `host_app_bundle_id` at all. Sending them
/// as nulls rather than omitting the keys keeps the property present in the taxonomy, so
/// a breakdown on it renders a "no target" bucket instead of silently dropping the row.
private func targetProperties(_ target: TextTarget?) -> [String: Any] {
    [
        "host_app_bundle_id": target?.hostAppBundleId ?? "unknown",
        // Which app the press happened *in*, asked independently of the capture.
        // `host_app_bundle_id` comes off the target, so a capture failure — the
        // dominant failure in the wild — reported `unknown` and the one question worth
        // asking of it ("is our AX read failing in this app, or was there genuinely
        // nothing focused?") could not be answered at all. Only resolved when there is
        // no target: with one, the two would be the same answer twice.
        //
        // Truthful only because of §4's ordering. Every caller reaching here with a nil
        // target is inside the capture `catch`, before `present(error)` and before any
        // panel takes key, so the frontmost app is still the user's.
        "frontmost_app_bundle_id": (target == nil ? frontmostBundleId() : nil) as Any,
        "capture_mode": target?.captureMode.rawValue as Any,
        // The one to watch: a rising clipboard rate in a specific bundle id is
        // the earliest signal that an app's AX tree changed.
        "io_path": target?.path.rawValue as Any,
        // §18. `scratch` is a rewrite of nothing — a message composed from an
        // instruction alone — and it is the case that used to be refused outright,
        // so its share of the traffic is the measure of whether that was worth
        // fixing.
        "scope": target?.scope.rawValue as Any,
        "has_destination": target?.hasDestination as Any,
    ]
}

struct PostHogAnalytics: Analytics {

    func rewriteStarted(_ attempt: RewriteAttempt, target: TextTarget?) {
        PostHogSDK.shared.capture("desktop_rewrite_started", properties:
            targetProperties(target)
                .merging(attemptProperties(attempt)) { own, _ in own })
    }

    func rewriteCompleted(
        _ attempt: RewriteAttempt,
        target: TextTarget,
        promptOrigin: String?,
        isReply: Bool,
        candidateCount: Int,
        latencyMs: Int
    ) {
        PostHogSDK.shared.capture("desktop_rewrite_completed", properties: [
            // Now only ever set for `savedButton`; nil elsewhere rather than defaulted
            // to "custom", which is what made four interactions indistinguishable.
            "prompt_origin": promptOrigin as Any,
            // §16. On both events, because the pair is the funnel: reply mode composes
            // text from nothing rather than editing what is there, so its accept rate
            // is the only honest read on whether the composition is any good.
            "is_reply": isReply,
            "latency_ms": latencyMs,
            "candidate_count": candidateCount,
        ]
        .merging(targetProperties(target)) { own, _ in own }
        .merging(attemptProperties(attempt)) { own, _ in own })
    }

    /// `message` is the toast the user was shown — one of the app's own Japanese strings,
    /// never captured or rewritten text — so it is safe to send and it is the only thing
    /// that makes the failure count diagnosable rather than a bare number. `stage` is
    /// what makes it actionable without parsing that string.
    func rewriteFailed(
        _ attempt: RewriteAttempt,
        stage: FailureStage,
        message: String,
        target: TextTarget?
    ) {
        PostHogSDK.shared.capture("desktop_rewrite_failed", properties: [
            "failure_stage": stage.rawValue,
            "message": message,
        ]
        .merging(targetProperties(target)) { own, _ in own }
        .merging(attemptProperties(attempt)) { own, _ in own })
    }

    /// The third ending, and until now the silent one. A rewrite superseded by a second
    /// press, or dismissed while the panel was generating, was billed by the server and
    /// reported to nobody — so `completed + failed` did not add up to `started` and there
    /// was no way to tell that from the data.
    func rewriteAbandoned(
        _ attempt: RewriteAttempt,
        reason: AbandonReason,
        target: TextTarget?
    ) {
        PostHogSDK.shared.capture("desktop_rewrite_abandoned", properties: [
            "reason": reason.rawValue,
        ]
        .merging(targetProperties(target)) { own, _ in own }
        .merging(attemptProperties(attempt)) { own, _ in own })
    }

    func inserted(
        _ attempt: RewriteAttempt,
        target: TextTarget,
        isReply: Bool,
        selectedIndex: Int,
        destination: InsertAction
    ) {
        PostHogSDK.shared.capture("desktop_rewrite_inserted", properties: [
            "is_reply": isReply,
            "accepted": true,
            "selected_index": selectedIndex,
            // Whether it went back where it came from or into the field the user moved
            // to. A rising `insert_here` rate says people are composing first and
            // choosing the field second, which is the flow §18 opened up.
            "insert_destination": destination == .insertHere ? "insert_here" : "captured_field",
        ]
        .merging(targetProperties(target)) { own, _ in own }
        .merging(attemptProperties(attempt)) { own, _ in own })
    }

    /// The other ending. Copy is a completed rewrite, not a failure, so it must not land
    /// in `desktop_rewrite_failed` — and without its own event the destination-less path
    /// §18 introduces would look like a funnel that simply stops.
    func copied(
        _ attempt: RewriteAttempt,
        target: TextTarget,
        isReply: Bool,
        reason: CopyReason
    ) {
        PostHogSDK.shared.capture("desktop_rewrite_copied", properties: [
            "is_reply": isReply,
            "reason": reason.rawValue,
        ]
        .merging(targetProperties(target)) { own, _ in own }
        .merging(attemptProperties(attempt)) { own, _ in own })
    }
}
