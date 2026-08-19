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
        candidateCount: Int,
        latencyMs: Int
    )
    func inserted(target: TextTarget, isReply: Bool, selectedIndex: Int, destination: InsertAction)
    func copied(target: TextTarget, isReply: Bool, reason: CopyReason)
    func failed(error: String)
}

struct PostHogAnalytics: Analytics {

    func rewriteCompleted(
        target: TextTarget,
        promptOrigin: String?,
        isReply: Bool,
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
        ])
    }

    func inserted(target: TextTarget, isReply: Bool, selectedIndex: Int, destination: InsertAction) {
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
        ])
    }

    /// The other ending. Copy is a completed rewrite, not a failure, so it must not land
    /// in `desktop_rewrite_failed` — and without its own event the destination-less path
    /// §18 introduces would look like a funnel that simply stops.
    func copied(target: TextTarget, isReply: Bool, reason: CopyReason) {
        PostHogSDK.shared.capture("desktop_rewrite_copied", properties: [
            "host_app_bundle_id": target.hostAppBundleId ?? "unknown",
            "capture_mode": target.captureMode.rawValue,
            "io_path": target.path.rawValue,
            "scope": target.scope.rawValue,
            "is_reply": isReply,
            "reason": reason.rawValue,
        ])
    }

    /// `error` is the toast the user was shown — one of the app's own Japanese strings,
    /// never captured or rewritten text — so it is safe to send and it is the only thing
    /// that makes the failure count diagnosable rather than a bare number.
    func failed(error: String) {
        PostHogSDK.shared.capture("desktop_rewrite_failed", properties: [
            "message": error,
        ])
    }
}
