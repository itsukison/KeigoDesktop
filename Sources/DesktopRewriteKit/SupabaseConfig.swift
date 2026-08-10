import Foundation

/// Shared Supabase project with the iOS app (§6): shared login, shared buttons,
/// shared billing. Separate function, separate schema, separate analytics.
public struct SupabaseConfig: Sendable {
    /// The publishable key is safe to ship — it is RLS-gated, and the iOS binary
    /// already carries the same value. §2's rule is about *provider* keys: no
    /// Gemini/OpenAI key ever reaches this bundle, which is why every AI call goes
    /// through the Edge Function instead of straight to a provider.
    public static let defaultURL = URL(string: "https://eercsucvxnszqletxued.supabase.co")!
    public static let defaultPublishableKey = "sb_publishable_S8rEoVqCOV8iVGfDEErI6w_Slb79nCO"

    /// **Auth is the only host a user ever reads, so it is the only host that is ours.**
    /// macOS composes the `ASWebAuthenticationSession` consent alert —
    /// 「"KeigoButton"がサインインするために"X"を使用しようとしています」— from the host of
    /// the URL the app hands the session, and never from anything configured on
    /// Google's side; Google's own consent screen shows the same host beside the app
    /// name. Both read `eercsucvxnszqletxued.supabase.co`, a random string a user
    /// cannot recognise and a phishing page can imitate for free. Branding the Google
    /// consent screen (done 2026-08-10) fixes the second surface and cannot touch the
    /// first — only the URL can.
    ///
    /// `auth.keigobutton.com` is this project's Supabase custom domain, activated
    /// 2026-08-10. It fronts the same GoTrue instance, so it mints the same tokens for
    /// the same `auth.users` rows, and `<ref>.supabase.co/auth/v1` keeps working —
    /// which is what leaves the iOS app unchanged.
    ///
    /// REST and Functions deliberately stay on `defaultURL`. Nothing about them is
    /// shown to a human, so a custom domain buys them nothing, and pointing them at
    /// our DNS would put the data paths behind a record we maintain instead of
    /// Supabase's. The auth host going down is the milder failure of the two:
    /// `ensureFreshAccessToken` falls back to the stored token, so work in flight
    /// survives until it expires.
    public static let defaultAuthURL = URL(string: "https://auth.keigobutton.com")!

    public let supabaseURL: URL
    public let authURL: URL
    public let publishableKey: String
    public let appVersion: String

    public var rewriteEndpoint: URL {
        supabaseURL.appendingPathComponent("functions/v1/desktop-rewrite")
    }
    public var authEndpoint: URL {
        authURL.appendingPathComponent("auth/v1")
    }
    public var restEndpoint: URL {
        supabaseURL.appendingPathComponent("rest/v1")
    }

    public init(
        supabaseURL: URL = SupabaseConfig.defaultURL,
        authURL: URL = SupabaseConfig.defaultAuthURL,
        publishableKey: String = SupabaseConfig.defaultPublishableKey,
        appVersion: String
    ) {
        self.supabaseURL = supabaseURL
        self.authURL = authURL
        self.publishableKey = publishableKey
        self.appVersion = appVersion
    }
}
