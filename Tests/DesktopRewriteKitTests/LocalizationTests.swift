import XCTest
@testable import DesktopRewriteKit

/// §17. The three facts worth pinning are the ones a future edit can break
/// silently: which language writes Japanese, what goes on the wire, and that the
/// English packs are actually different buttons rather than translated labels.
final class LocalizationTests: XCTestCase {

    override func tearDown() {
        AppLanguageState.current = .japanese
        super.tearDown()
    }

    // MARK: - What the buttons write

    /// The whole point of the Chinese build: the interface is translated and the
    /// buttons are not. If this ever flips, a 简体中文 user's 敬語 button starts
    /// producing Chinese and the product stops being the one they installed.
    func testOnlyEnglishChangesTheLanguageTheButtonsWriteIn() {
        XCTAssertTrue(AppLanguage.japanese.writesJapanese)
        XCTAssertTrue(AppLanguage.simplifiedChinese.writesJapanese)
        XCTAssertFalse(AppLanguage.english.writesJapanese)
    }

    /// The wire value is a contract with `desktop-rewrite`'s `assistantIdentity`,
    /// which treats anything other than `"en"` as Japanese.
    func testWritingLanguageWireValues() {
        XCTAssertEqual(AppLanguage.japanese.writingLanguageCode, "ja")
        XCTAssertEqual(AppLanguage.simplifiedChinese.writingLanguageCode, "ja")
        XCTAssertEqual(AppLanguage.english.writingLanguageCode, "en")
    }

    func testWritingLanguageSurvivesEncoding() throws {
        let request = RewriteRequest(
            prompt: "Make it polite",
            text: "move the meeting to 3",
            appVersion: "1.0",
            captureMode: .wholeInput,
            writingLanguage: AppLanguage.english.writingLanguageCode
        )
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(request)
        ) as? [String: Any]

        XCTAssertEqual(json?["writingLanguage"] as? String, "en")
    }

    /// Absent, not `"ja"`, is what an older client sends, and the server's default
    /// depends on it staying expressible here.
    func testWritingLanguageIsAbsentWhenNotSet() throws {
        let request = RewriteRequest(
            prompt: "敬語に",
            text: "変更しといて",
            appVersion: "1.0",
            captureMode: .wholeInput
        )
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(request)
        ) as? [String: Any]

        XCTAssertNil(json?["writingLanguage"])
    }

    // MARK: - The language itself

    func testPreferredLanguageFollowsTheSystemAndFallsBackToJapanese() {
        XCTAssertEqual(AppLanguage.preferred(from: ["en-US", "ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.preferred(from: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.preferred(from: ["zh-Hant-TW"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.preferred(from: ["ja"]), .japanese)
        XCTAssertEqual(AppLanguage.preferred(from: ["de-DE", "fr-FR"]), .japanese)
        XCTAssertEqual(AppLanguage.preferred(from: []), .japanese)
    }

    /// Nil-until-answered is what lets §15's page preselect the system language
    /// without recording it as the user's choice.
    func testStoreIsEmptyUntilAnswered() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LocalizationTests.store"))
        defaults.removePersistentDomain(forName: "LocalizationTests.store")
        let store = AppLanguageStore(defaults: defaults)

        XCTAssertNil(store.stored)
        store.save(.english)
        XCTAssertEqual(store.stored, .english)
        XCTAssertEqual(AppLanguageStore(defaults: defaults).resolved, .english)
        XCTAssertEqual(AppLanguageState.current, .english)

        defaults.removePersistentDomain(forName: "LocalizationTests.store")
    }

    func testEndonymsAreNeverTranslated() {
        for language in AppLanguage.allCases {
            AppLanguageState.current = language
            XCTAssertEqual(AppLanguage.japanese.endonym, "日本語")
            XCTAssertEqual(AppLanguage.english.endonym, "English")
            XCTAssertEqual(AppLanguage.simplifiedChinese.endonym, "简体中文")
        }
    }

    func testTrFollowsTheCurrentLanguage() {
        AppLanguageState.current = .japanese
        XCTAssertEqual(tr("あ", "a", "啊"), "あ")
        AppLanguageState.current = .english
        XCTAssertEqual(tr("あ", "a", "啊"), "a")
        AppLanguageState.current = .simplifiedChinese
        XCTAssertEqual(tr("あ", "a", "啊"), "啊")
    }

    // MARK: - Packs

    func testChineseIsOfferedTheJapanesePacksAndTheJapaneseButtons() {
        XCTAssertEqual(
            OnboardingPresetPack.available(for: .simplifiedChinese),
            OnboardingPresetPack.available(for: .japanese)
        )

        AppLanguageState.current = .japanese
        let japanese = OnboardingPresetPack.starter.drafts()
        AppLanguageState.current = .simplifiedChinese
        let chinese = OnboardingPresetPack.starter.drafts()

        XCTAssertEqual(japanese.map(\.title), chinese.map(\.title))
        XCTAssertEqual(japanese.map(\.prompt), chinese.map(\.prompt))
    }

    func testEnglishGetsDifferentPacksAndDifferentButtons() {
        XCTAssertEqual(
            OnboardingPresetPack.available(for: .english),
            [.starter, .work, .outreach, .polish, .social]
        )

        AppLanguageState.current = .english
        XCTAssertEqual(
            OnboardingPresetPack.starter.buttonTitles,
            ["Polite", "Email", "Shorten", "Proofread"]
        )
    }

    /// The hover row has no overflow handling (§4) — it just gets wider. Nine
    /// characters keeps a four-button English row close to a Japanese one.
    func testEnglishButtonTitlesStayShortEnoughForTheHoverRow() {
        AppLanguageState.current = .english
        for pack in OnboardingPresetPack.available(for: .english) {
            for title in pack.buttonTitles {
                XCTAssertLessThanOrEqual(
                    title.count, 9,
                    "\(title) is too wide for the bar"
                )
            }
        }
    }

    /// `handle_new_user()` seeds every account with all four builtin keys, and
    /// `user_prompts_user_builtin_unique` makes a key an identity — so an English
    /// pack that claims none of them leaves the seeded Japanese rows to be deleted
    /// and re-created rather than reused (§6).
    func testEnglishStarterStillClaimsTheSharedBuiltinKeys() {
        AppLanguageState.current = .english
        XCTAssertEqual(
            OnboardingPresetPack.starter.drafts().compactMap(\.builtinKey),
            ["polite", "email"]
        )
    }

    /// Two packs exist only in English. A run saved before a language change still
    /// has to resolve to four buttons rather than an empty list.
    func testEnglishOnlyPacksStillResolveInJapanese() {
        AppLanguageState.current = .japanese
        XCTAssertEqual(OnboardingPresetPack.outreach.drafts().count, 4)
        XCTAssertEqual(OnboardingPresetPack.polish.drafts().count, 4)
    }

    /// The practice draft has to carry the defect its button fixes, or the lesson
    /// ends with a rewrite indistinguishable from the input.
    func testEnglishPracticeSamplesAreEnglish() {
        AppLanguageState.current = .english
        let polite = UserPrompt(
            slot: .main,
            builtinKey: "polite",
            title: "Polite",
            prompt: "Rewrite the text so it reads warm, courteous and professional."
        )
        let sample = OnboardingPracticeSample.text(for: polite)

        XCTAssertFalse(
            sample.contains(where: { $0.unicodeScalars.contains { $0.value > 0x2FFF } }),
            "the English practice draft must not be Japanese"
        )
        XCTAssertFalse(sample.isEmpty)
    }

    /// The language page is asked first and is not part of the progress rail.
    func testLanguageIsTheFirstStepAndAppendedLast() {
        XCTAssertEqual(DesktopOnboardingStep.flow.first, .language)
        XCTAssertEqual(DesktopOnboardingStep.language.rawValue, 10)
        XCTAssertEqual(DesktopOnboardingStep(rawValue: 0), .welcome)
    }

    /// A first run has nothing saved, and it is the run the language page exists
    /// for. `savedStep` used to answer `.welcome` here — correct only while
    /// `.welcome` was also the head of the flow.
    func testAFirstRunResumesAtTheHeadOfTheFlow() throws {
        let name = "LocalizationTests.progress"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)

        let store = OnboardingProgressStore(defaults: defaults, prefix: "t")
        XCTAssertEqual(store.savedStep, .language)

        store.save(step: .access)
        XCTAssertEqual(OnboardingProgressStore(defaults: defaults, prefix: "t").savedStep, .access)

        defaults.removePersistentDomain(forName: name)
    }
}
