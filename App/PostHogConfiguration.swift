import Foundation
import PostHog

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
    /// `surface: macos`.
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
        PostHogSDK.shared.register(["surface": "macos"])
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
