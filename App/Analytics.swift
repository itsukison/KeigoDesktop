import Foundation
import PostHog
import TextIO

protocol Analytics: Sendable {
    func rewriteCompleted(
        target: TextTarget,
        promptOrigin: String?,
        isReply: Bool,
        candidateCount: Int,
        latencyMs: Int
    )
    func inserted(target: TextTarget, isReply: Bool, selectedIndex: Int)
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
            // §16. On both events, because the pair is the funnel: reply mode composes
            // text from nothing rather than editing what is there, so its accept rate
            // is the only honest read on whether the composition is any good.
            "is_reply": isReply,
            "latency_ms": latencyMs,
            "candidate_count": candidateCount,
        ])
    }

    func inserted(target: TextTarget, isReply: Bool, selectedIndex: Int) {
        PostHogSDK.shared.capture("desktop_rewrite_inserted", properties: [
            "host_app_bundle_id": target.hostAppBundleId ?? "unknown",
            "capture_mode": target.captureMode.rawValue,
            "io_path": target.path.rawValue,
            "is_reply": isReply,
            "accepted": true,
            "selected_index": selectedIndex,
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
