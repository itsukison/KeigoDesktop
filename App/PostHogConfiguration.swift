import DesktopRewriteKit
import Foundation
import PostHog
import TextIO

enum PostHogConfiguration {
    static func configure() {
        guard let projectToken = configuredValue(for: "POSTHOG_PROJECT_TOKEN") else {
#if DEBUG
            assertionFailure("POSTHOG_PROJECT_TOKEN variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once POSTHOG_PROJECT_TOKEN is configured")
#endif
            return
        }
        guard let host = configuredValue(for: "POSTHOG_HOST") else {
#if DEBUG
            assertionFailure("POSTHOG_HOST variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once POSTHOG_HOST is configured")
#endif
            return
        }

        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.errorTrackingConfig.autoCapture = true
        PostHogSDK.shared.setup(config)
        registerSurface()
    }

    /// Stamps every event — including the ones we never call `capture` for, such as
    /// `$exception`, `$identify` and the application lifecycle events — with
    /// `surface: macos`, the interface language, and whether Accessibility is granted.
    ///
    /// §7 makes the separate project the boundary, and this is the second layer behind
    /// it: the desktop and the iOS keyboard share one `auth.users` id and therefore one
    /// `distinct_id`, so a mistyped `POSTHOG_PROJECT_TOKEN` would merge two platforms'
    /// people and events with no error anywhere. A surface on every row makes that
    /// visible instead of silent, and it is what the dashboard's insights filter on.
    ///
    /// **Must be re-registered after `PostHogSDK.shared.reset()`.** Super properties are
    /// persisted storage and `reset` clears them, so signing out would otherwise strip
    /// the surface off every event until the next launch — see `MainModel.signOut`.
    static func registerSurface() {
        PostHogSDK.shared.register([
            "surface": "macos",
            // §17. Read at registration time and re-registered whenever the language
            // changes, so a series can be split by it without a per-event property —
            // and so the English and 简体中文 funnels are separable from day one
            // rather than after the fact.
            "app_language": AppLanguageState.current.rawValue,
            // §5 says the app is useless without this permission, and until 2026-08-22
            // nothing measured it. The install → onboarding → first-real-rewrite funnel
            // stepped straight over the one gate that can silently end the product, so a
            // user who never granted it and one who granted it and hit a broken AX tree
            // were the same row.
            //
            // A super property rather than a per-event one for the same reason as
            // `app_language`: the question is always "split this series" — did the users
            // who never completed a real rewrite have permission? — and never "what
            // happened on this row". The rewrite events *also* send it live, because
            // stored state is only as fresh as the last `refresh()` and a
            // `TextIOError.notTrusted` failure is exactly when it is stale.
            //
            // Re-registered by `MainModel.applyTrusted` whenever the state flips — the
            // same hazard as the surface being cleared by `reset()` on sign-out.
            "accessibility_granted": AXPermission.isTrusted,
        ])
    }

    private static func configuredValue(for key: String) -> String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty,
            !value.contains("$(")
        else {
            return nil
        }
        return value
    }
}
