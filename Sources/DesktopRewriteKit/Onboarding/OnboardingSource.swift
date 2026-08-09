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
        case .x: return tr("X（旧Twitter）", "X (formerly Twitter)", "X（原Twitter）")
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .webSearch: return tr("Web検索", "Web search", "网络搜索")
        case .friend: return tr("知人にすすめられて", "Someone recommended it", "朋友推荐")
        case .article: return tr("記事・ブログ", "An article or blog", "文章・博客")
        case .other: return tr("その他", "Something else", "其他")
        }
    }
}
