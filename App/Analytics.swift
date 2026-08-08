import Foundation
import TextIO

/// §7. Event shape is fixed here; the transport is not yet wired.
///
/// **The PostHog project does not exist yet.** §7 requires a *new* project in org
/// `Keigo` — reporting into `Default project` (465060) would merge persons across
/// surfaces and silently deflate both platforms' MAU and retention. Until that
/// project is created and its token set, `NoopAnalytics` is installed and events go
/// nowhere. The property names below are the contract, so swapping the transport in
/// later is a one-file change.
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

struct NoopAnalytics: Analytics {
    func rewriteCompleted(
        target: TextTarget,
        promptOrigin: String?,
        isReply: Bool,
        candidateCount: Int,
        latencyMs: Int
    ) {}
    func inserted(target: TextTarget, isReply: Bool, selectedIndex: Int) {}
    func failed(error: String) {}
}

/// Logs the exact payload §7 specifies, so the shape can be verified before a real
/// project exists behind it.
struct ConsoleAnalytics: Analytics {

    func rewriteCompleted(
        target: TextTarget,
        promptOrigin: String?,
        isReply: Bool,
        candidateCount: Int,
        latencyMs: Int
    ) {
        emit("desktop_rewrite", [
            "surface": "macos",
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
        emit("desktop_rewrite_inserted", [
            "surface": "macos",
            "host_app_bundle_id": target.hostAppBundleId ?? "unknown",
            "capture_mode": target.captureMode.rawValue,
            "io_path": target.path.rawValue,
            "is_reply": isReply,
            "accepted": true,
            "selected_index": selectedIndex,
        ])
    }

    func failed(error: String) {
        emit("desktop_rewrite_failed", ["surface": "macos", "message": error])
    }

    private func emit(_ event: String, _ properties: [String: Any]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["event": event, "properties": properties]
        ), let json = String(data: data, encoding: .utf8) else { return }
        FileHandle.standardError.write(Data("[analytics] \(json)\n".utf8))
    }
}
