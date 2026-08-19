import XCTest
@testable import DesktopRewriteKit

/// §17's two questions — what the user reads, what their buttons write — drifting
/// apart, and the detection that notices.
///
/// The bug these pin: an English-mode user pressed 敬語 and got Japanese back. The
/// interface was English, `writingLanguage: "en"` was on the wire, and the system
/// prompt said "You are an English writing assistant on macOS." — but the button's own
/// instruction was 「…自然でやわらかい丁寧語に変換してください」, and the command is what
/// the model follows. Nothing had ever rewritten the buttons when the language changed.
final class StockButtonLanguageTests: XCTestCase {

    override func tearDown() {
        AppLanguageState.current = .japanese
        super.tearDown()
    }

    private func prompt(
        _ body: String,
        title: String = "ボタン",
        builtinKey: String? = nil,
        isEnabled: Bool = true
    ) -> UserPrompt {
        UserPrompt(
            slot: .main,
            builtinKey: builtinKey,
            title: title,
            prompt: body,
            isEnabled: isEnabled
        )
    }

    /// The four rows `handle_new_user()` writes at signup. Every account starts here,
    /// whatever language it is going to be used in, because the trigger is in the
    /// database the iOS keyboard shares and predates this app entirely.
    private var seededButtons: [UserPrompt] {
        [
            prompt(
                "Rewrite into polite, business-appropriate Japanese (敬語) while preserving meaning.",
                title: "敬語",
                builtinKey: "polite"
            ),
            prompt(
                "Rewrite into natural, idiomatic Japanese while preserving meaning. Make it sound like a native speaker wrote it.",
                title: "自然に書き直し",
                builtinKey: "natural"
            ),
            prompt("Translate into natural English.", title: "英訳", builtinKey: "translateToEnglish"),
        ]
    }

    // MARK: - Detection

    /// The reported failure, reduced to one assertion. This account's buttons are the
    /// Japanese 「まずは定番」 pack; the app is in English.
    func testJapanesePresetButtonsAreFlaggedForAnEnglishUser() {
        let japanesePack = OnboardingPresetPack.starter.drafts(writtenIn: .japanese)
        let buttons = japanesePack.enumerated().map { $1.userPrompt(at: $0) }

        XCTAssertTrue(StockButtonLanguage.writesOtherLanguage(buttons, whenWriting: .english))
        XCTAssertEqual(
            StockButtonLanguage.mismatched(in: buttons, whenWriting: .english).count,
            japanesePack.count
        )
    }

    /// The signup seeds are not in `OnboardingPresetCatalog` and have to be recognised
    /// separately, or the one group of users who never picked a pack — the whole reason
    /// the ⚙︎ language row exists — would see no offer at all.
    func testSignupSeedsAreRecognisedAsJapaneseWriting() {
        XCTAssertTrue(StockButtonLanguage.writesOtherLanguage(seededButtons, whenWriting: .english))
    }

    func testEnglishPresetButtonsAreNotFlaggedForAnEnglishUser() {
        let buttons = OnboardingPresetPack.starter.drafts(writtenIn: .english)
            .enumerated().map { $1.userPrompt(at: $0) }
        XCTAssertFalse(StockButtonLanguage.writesOtherLanguage(buttons, whenWriting: .english))
    }

    /// The other direction, which is not symmetrical in the UI but is in the logic: a
    /// user who tries English and goes back to 日本語 must be offered the way back.
    func testEnglishPresetButtonsAreFlaggedForAJapaneseUser() {
        let buttons = OnboardingPresetPack.starter.drafts(writtenIn: .english)
            .enumerated().map { $1.userPrompt(at: $0) }
        XCTAssertTrue(StockButtonLanguage.writesOtherLanguage(buttons, whenWriting: .japanese))
    }

    /// 简体中文 writes Japanese (§17), so a Japanese button set is correct for it and
    /// must not be flagged. Getting this wrong would tell every Chinese user that their
    /// buttons are broken.
    func testChineseInterfaceIsSatisfiedByJapaneseButtons() {
        XCTAssertFalse(
            StockButtonLanguage.writesOtherLanguage(seededButtons, whenWriting: .simplifiedChinese)
        )
    }

    /// Detection is exact matching, and this is the reason: a user's own Japanese
    /// button in an English app is a deliberate choice — an English speaker in Japan
    /// with one 敬語 button — and proposing to delete it would be worse than the bug.
    func testHandWrittenButtonsAreNeverFlagged() {
        let authored = [
            prompt("この文章を関西弁にしてください。", title: "関西弁"),
            prompt("Rewrite this as a haiku.", title: "Haiku"),
        ]
        XCTAssertFalse(StockButtonLanguage.writesOtherLanguage(authored, whenWriting: .english))
        XCTAssertFalse(StockButtonLanguage.writesOtherLanguage(authored, whenWriting: .japanese))
    }

    /// An edited preset stops being stock text the moment it is edited, which is the
    /// intended behaviour: the wording is now the user's.
    func testAnEditedPresetIsTreatedAsTheUsersOwn() {
        var edited = seededButtons[0]
        edited.prompt += " Keep it short."
        XCTAssertFalse(StockButtonLanguage.writesOtherLanguage([edited], whenWriting: .english))
    }

    /// A disabled button is one click from being live, so it counts. A banner that
    /// appeared only after someone re-enabled a row would read as a new fault.
    func testDisabledButtonsStillCount() {
        let off = seededButtons.map {
            prompt($0.prompt, title: $0.title, builtinKey: $0.builtinKey, isEnabled: false)
        }
        XCTAssertTrue(StockButtonLanguage.writesOtherLanguage(off, whenWriting: .english))
    }

    func testNoButtonsIsNotAMismatch() {
        XCTAssertFalse(StockButtonLanguage.writesOtherLanguage([], whenWriting: .english))
    }

    // MARK: - The replacement set

    /// `replaceAll` deletes every row absent from what it is handed, so the replacement
    /// has to carry the user's own buttons forward. This is the assertion that stands
    /// between a language fix and someone losing work they typed.
    func testReplacementKeepsHandWrittenButtonsAndDropsStockOnes() {
        let authored = prompt("この文章を関西弁にしてください。", title: "関西弁")
        let existing = seededButtons + [authored]

        let replacement = StockButtonLanguage.replacement(
            choosing: .starter,
            keeping: existing,
            whenWriting: .english
        )

        let englishStarter = OnboardingPresetPack.starter.drafts(writtenIn: .english)
        XCTAssertEqual(replacement.count, englishStarter.count + 1)
        XCTAssertEqual(replacement.prefix(englishStarter.count).map(\.title), englishStarter.map(\.title))
        XCTAssertEqual(replacement.last?.title, authored.title)
        XCTAssertEqual(replacement.last?.prompt, authored.prompt)
        XCTAssertEqual(
            StockButtonLanguage.keptCount(choosing: .starter, keeping: existing, whenWriting: .english),
            1
        )
    }

    /// The pack the user is switching *to* is stock text as well, so its own rows are
    /// replaced rather than kept — otherwise picking Starter twice would leave two
    /// Polite buttons.
    func testReplacingAnEnglishPackDoesNotDuplicateIt() {
        let existing = OnboardingPresetPack.starter.drafts(writtenIn: .english)
            .enumerated().map { $1.userPrompt(at: $0) }
        let replacement = StockButtonLanguage.replacement(
            choosing: .work,
            keeping: existing,
            whenWriting: .english
        )
        XCTAssertEqual(replacement.count, OnboardingPresetPack.work.drafts(writtenIn: .english).count)
    }

    /// The builtin keys are an identity on the server (§6). The English pack keeps
    /// `polite` and `email` for exactly that reason, and the replacement has to carry
    /// them or `UserPromptIdentity` cannot reconcile the upsert into an update.
    func testReplacementCarriesTheBuiltinKeysForward() {
        let replacement = StockButtonLanguage.replacement(
            choosing: .starter,
            keeping: seededButtons,
            whenWriting: .english
        )
        XCTAssertEqual(
            Set(replacement.compactMap(\.builtinKey)),
            ["polite", "email"]
        )
    }

    /// Seven is the app's own ceiling (`addDraft`), and the hover row has no overflow
    /// handling (§4), so the replacement cannot hand `replaceAll` more than that.
    func testReplacementRespectsTheSevenButtonCeiling() {
        let authored = (1...6).map { prompt("Rewrite this \($0) different ways.", title: "A\($0)") }
        let replacement = StockButtonLanguage.replacement(
            choosing: .starter,
            keeping: seededButtons + authored,
            whenWriting: .english
        )
        XCTAssertEqual(replacement.count, 7)
    }

    /// `drafts(writtenIn:)` exists so the audit never depends on the global, and this
    /// pins it: the answer must not move when the app's language does.
    func testDraftsForALanguageIgnoreTheGlobalState() {
        AppLanguageState.current = .japanese
        let english = OnboardingPresetPack.starter.drafts(writtenIn: .english)
        AppLanguageState.current = .english
        XCTAssertEqual(english.map(\.prompt), OnboardingPresetPack.starter.drafts(writtenIn: .english).map(\.prompt))
        XCTAssertEqual(english.first?.title, "Polite")
    }
}
