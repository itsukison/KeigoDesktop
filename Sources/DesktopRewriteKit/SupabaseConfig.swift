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

    public let supabaseURL: URL
    public let publishableKey: String
    public let appVersion: String

    public var rewriteEndpoint: URL {
        supabaseURL.appendingPathComponent("functions/v1/desktop-rewrite")
    }
    public var authEndpoint: URL {
        supabaseURL.appendingPathComponent("auth/v1")
    }
    public var restEndpoint: URL {
        supabaseURL.appendingPathComponent("rest/v1")
    }

    public init(
        supabaseURL: URL = SupabaseConfig.defaultURL,
        publishableKey: String = SupabaseConfig.defaultPublishableKey,
        appVersion: String
    ) {
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
        self.appVersion = appVersion
    }
}
