import Foundation

/// The three languages the app is authored in.
///
/// Chinese is deliberately **interface-only**: a 简体中文 user is assumed to be a
/// Chinese speaker working in Japan, so every label, caption and explanation is
/// translated while the buttons keep writing Japanese. `writesJapanese` is that
/// fact, and it is what `OnboardingPresetCatalog` and `RewriteRequest` read —
/// neither of them should ever branch on the raw language again.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case japanese = "ja"
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    /// The language the user's buttons produce. Only English moves it.
    public var writesJapanese: Bool { self != .english }

    /// Sent to `desktop-rewrite` as `writingLanguage`. Absent on the wire keeps the
    /// function's original Japanese-assistant instructions, so this string existing
    /// is what makes an English user's system prompt different — see §6.
    public var writingLanguageCode: String { writesJapanese ? "ja" : "en" }

    /// Endonyms, never translated: a language picker that renames the language the
    /// reader is looking for is the one control they cannot use.
    public var endonym: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    /// For dates, numbers and any system-drawn text.
    public var locale: Locale { Locale(identifier: rawValue) }

    /// The closest match to what the Mac is already set to, defaulting to Japanese.
    /// Only ever a *preselection* — §15's language page still asks.
    public static func preferred(
        from identifiers: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        for identifier in identifiers {
            let code = identifier.lowercased()
            if code.hasPrefix("ja") { return .japanese }
            if code.hasPrefix("en") { return .english }
            if code.hasPrefix("zh") { return .simplifiedChinese }
        }
        return .japanese
    }
}

/// The current language, readable from anywhere without an actor hop.
///
/// `tr` is called from view bodies, from the overlay's AppKit callbacks and from
/// pure model code in this package, so the read has to be cheap and thread-safe;
/// the write happens once on the language page and once in the ⚙︎ modal.
public enum AppLanguageState {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var value: AppLanguage = .japanese

    public static var current: AppLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

/// One string in three languages, written where it is used.
///
/// **Deliberately not a String Catalog**, and the reason is drift rather than
/// tooling. The Japanese copy in this app is reworded constantly, and both of the
/// standard shapes lose the other two languages when it is: a Japanese-keyed
/// catalog orphans the entry, and a symbolic key leaves `en`/`zh` still holding a
/// translation of a sentence that no longer exists — silently, in a JSON file
/// nobody opens during the edit. Colocating the three makes that impossible to do
/// by accident: rewording the Japanese means looking at the other two.
/// There is no vendor in this loop and no fourth language planned; if either
/// changes, this is the one function to replace.
public func tr(_ ja: String, _ en: String, _ zh: String) -> String {
    switch AppLanguageState.current {
    case .japanese: return ja
    case .english: return en
    case .simplifiedChinese: return zh
    }
}

/// The persisted choice. Local to this Mac by decision: a `language` column on
/// `profiles` would be a migration in a project the iOS app shares (§12).
public final class AppLanguageStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "appLanguage"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Nil until the user answers the language page — which is what lets the page
    /// preselect the system language without claiming the user chose it.
    public var stored: AppLanguage? {
        defaults.string(forKey: key).flatMap(AppLanguage.init(rawValue:))
    }

    public var resolved: AppLanguage {
        stored ?? .preferred()
    }

    public func save(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: key)
        AppLanguageState.current = language
    }

    /// Called once at launch, before any window is built.
    public func activate() {
        AppLanguageState.current = resolved
    }
}
