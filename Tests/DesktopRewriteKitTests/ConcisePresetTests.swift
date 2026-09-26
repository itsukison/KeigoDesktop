import XCTest
@testable import DesktopRewriteKit

final class ConcisePresetTests: XCTestCase {
    func testEachLanguageOffersThreeSetsOfFourButtons() {
        for language in AppLanguage.allCases {
            let packs = OnboardingPresetPack.available(for: language)
            XCTAssertEqual(packs, [.starter, .work, .social])
            for pack in packs { XCTAssertEqual(pack.drafts(writtenIn: language).count, 4) }
        }
    }

    func testEveryOfferedButtonHasAnExampleInItsWritingLanguage() {
        for language in AppLanguage.allCases {
            for pack in OnboardingPresetPack.available(for: language) {
                for draft in pack.drafts(writtenIn: language) {
                    let example = OnboardingPresetPack.example(for: draft, writtenIn: language)
                    XCTAssertNotNil(example, "\(language) / \(pack) / \(draft.title)")
                    XCTAssertFalse(example?.input.isEmpty ?? true)
                    XCTAssertFalse(example?.output.isEmpty ?? true)
                    XCTAssertNotEqual(example?.input, example?.output)
                }
            }
        }
    }

    func testEditedInstructionDoesNotShowStockResultAsItsPreview() {
        var draft = OnboardingPresetPack.work.drafts(writtenIn: .english)[2]
        draft.prompt = "Translate into French."
        XCTAssertNil(OnboardingPresetPack.example(for: draft, writtenIn: .english))
    }

    func testPriorPresetRemainsRecognizedWithoutChangingItsSavedText() {
        let body = "Rewrite the text as a Slack or Teams message that can be sent as is: short, clear and friendly. Lead with the point, drop email greetings and sign-offs, and stay polite without being formal."
        let saved = UserPrompt(slot: .sub, title: "My work chat", prompt: body, origin: .onboardingPreset)
        XCTAssertTrue(StockButtonLanguage.writesOtherLanguage([saved], whenWriting: .japanese))
        XCTAssertEqual(OnboardingPresetPack.buttonAnalyticsKey(for: saved), "work_chat")
        let replacement = StockButtonLanguage.replacement(choosing: .work, keeping: [saved], whenWriting: .japanese)
        XCTAssertEqual(replacement.count, 4)
        XCTAssertEqual(saved.prompt, body)
    }

    func testEditingAnOldPresetStillMakesItCustom() {
        let body = "次の文章を、上司に失礼なく簡潔に伝わる文章に書き直してください。敬意は保ちつつ過度にへりくだらず、依頼や確認は相手が返答しやすい形にしてください。"
        var saved = UserPrompt(slot: .sub, title: "上司向け", prompt: body, origin: .onboardingPreset)
        XCTAssertEqual(OnboardingPresetPack.buttonAnalyticsKey(for: saved), "manager_message")
        saved.prompt += " 英語にしてください。"
        XCTAssertFalse(StockButtonLanguage.writesOtherLanguage([saved], whenWriting: .english))
        XCTAssertEqual(OnboardingPresetPack.buttonAnalyticsKey(for: saved), "customized_preset")
    }
}
