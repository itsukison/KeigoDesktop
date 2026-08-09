import Foundation

/// The answers to 「どこで知りましたか？」, the last question of first run (§15).
///
/// The raw value is what reaches PostHog as `source`, so it is a **stable identifier
/// and not a label**: renaming one splits an attribution series in two after the fact,
/// which is the exact failure `docs/analytics.md` §1 exists to prevent. `label` is the
/// visible Japanese and may be reworded freely.
///
/// Lives here rather than beside the view for the same reason `OnboardingPresetCatalog`
/// does: the cases and their keys are the part worth pinning in a test, and the artwork
/// each one draws is a `SwiftUI` decision the App target owns.
public enum OnboardingSource: String, CaseIterable, Sendable {
    case x
    case youtube
    case instagram
    case tiktok
    case webSearch = "web_search"
    case friend
    case article
    case other

    public var label: String {
        switch self {
        case .x: return "X（旧Twitter）"
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .webSearch: return "Web検索"
        case .friend: return "知人にすすめられて"
        case .article: return "記事・ブログ"
        case .other: return "その他"
        }
    }
}
