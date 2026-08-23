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
    func rewriteCompleted(
        target: TextTarget,
        promptOrigin: String?,
        isReply: Bool,
        isTutorial: Bool,
        candidateCount: Int,
        latencyMs: Int
    )
    func inserted(
        target: TextTarget,
        isReply: Bool,
        isTutorial: Bool,
        selectedIndex: Int,
        destination: InsertAction
    )
    func copied(target: TextTarget, isReply: Bool, isTutorial: Bool, reason: CopyReason)
    func failed(error: String, isTutorial: Bool)
}

/// Properties every rewrite event carries for a reason that has nothing to do with the
/// rewrite itself. Appended to each event rather than duplicated into four literals.
///
/// - `is_tutorial` closed `docs/analytics.md` §3's third gap. Onboarding practice calls the same
///   three methods as a real press and all three lessons complete *only* on a successful
///   Insert, so every new user used to donate three guaranteed acceptances to the
///   acceptance-rate tile. Measured on 2026-08-22: 38 of 117 completed rewrites were
///   practice, and 14 of the 18 belonging to users who are not the owners.
/// - `accessibility_granted` is read **live**, not taken from the super property of the
///   same name. The super property is stored, so it is only as fresh as the last
///   `MainModel.refresh()` — and the one event where the distinction decides the answer
///   is a `TextIOError.notTrusted` failure, which is precisely the moment the stored
///   value is wrong. Registered *and* sent, deliberately: a gap between the two readings
///   of the same row is a permission that changed without the window ever activating.
private func loopProperties(isTutorial: Bool) -> [String: Any] {
    [
        "is_tutorial": isTutorial,
        "accessibility_granted": AXPermission.isTrusted,
    ]
}

struct PostHogAnalytics: Analytics {

    func rewriteCompleted(
        target: TextTarget,
        promptOrigin: String?,
        isReply: Bool,
        isTutorial: Bool,
        candidateCount: Int,
        latencyMs: Int
    ) {
        PostHogSDK.shared.capture("desktop_rewrite_completed", properties: [
            "host_app_bundle_id": target.hostAppBundleId ?? "unknown",
            "capture_mode": target.captureMode.rawValue,
            // The one to watch: a rising clipboard rate in a specific bundle id is
            // the earliest signal that an app's AX tree changed.
            "io_path": target.path.rawValue,
            "prompt_origin": promptOrigin ?? "custom",
            // §18. `scratch` is a rewrite of nothing — a message composed from an
            // instruction alone — and it is the case that used to be refused outright,
            // so its share of the traffic is the measure of whether that was worth
            // fixing.
            "scope": target.scope.rawValue,
            "has_destination": target.hasDestination,
            // §16. On both events, because the pair is the funnel: reply mode composes
            // text from nothing rather than editing what is there, so its accept rate
            // is the only honest read on whether the composition is any good.
            "is_reply": isReply,
            "latency_ms": latencyMs,
            "candidate_count": candidateCount,
        ].merging(loopProperties(isTutorial: isTutorial)) { own, _ in own })
    }

    func inserted(
        target: TextTarget,
        isReply: Bool,
        isTutorial: Bool,
        selectedIndex: Int,
        destination: InsertAction
    ) {
        PostHogSDK.shared.capture("desktop_rewrite_inserted", properties: [
            "host_app_bundle_id": target.hostAppBundleId ?? "unknown",
            "capture_mode": target.captureMode.rawValue,
            "io_path": target.path.rawValue,
            "scope": target.scope.rawValue,
            "is_reply": isReply,
            "accepted": true,
            "selected_index": selectedIndex,
            // Whether it went back where it came from or into the field the user moved
            // to. A rising `insert_here` rate says people are composing first and
            // choosing the field second, which is the flow §18 opened up.
            "insert_destination": destination == .insertHere ? "insert_here" : "captured_field",
        ].merging(loopProperties(isTutorial: isTutorial)) { own, _ in own })
    }

    /// The other ending. Copy is a completed rewrite, not a failure, so it must not land
    /// in `desktop_rewrite_failed` — and without its own event the destination-less path
    /// §18 introduces would look like a funnel that simply stops.
    func copied(target: TextTarget, isReply: Bool, isTutorial: Bool, reason: CopyReason) {
        PostHogSDK.shared.capture("desktop_rewrite_copied", properties: [
            "host_app_bundle_id": target.hostAppBundleId ?? "unknown",
            "capture_mode": target.captureMode.rawValue,
            "io_path": target.path.rawValue,
            "scope": target.scope.rawValue,
            "is_reply": isReply,
            "reason": reason.rawValue,
        ].merging(loopProperties(isTutorial: isTutorial)) { own, _ in own })
    }

    /// `error` is the toast the user was shown — one of the app's own Japanese strings,
    /// never captured or rewritten text — so it is safe to send and it is the only thing
    /// that makes the failure count diagnosable rather than a bare number.
    /// `isTutorial` here is read from whether a lesson is *armed*, not from a
    /// `PendingRewrite` — a capture failure happens before there is one. So it means
    /// "this failure happened during onboarding practice", which is the question tile 16
    /// needs answered and is a slightly wider claim than the same property on the other
    /// three events.
    func failed(error: String, isTutorial: Bool) {
        PostHogSDK.shared.capture("desktop_rewrite_failed", properties: [
            "message": error,
        ].merging(loopProperties(isTutorial: isTutorial)) { own, _ in own })
    }
}
