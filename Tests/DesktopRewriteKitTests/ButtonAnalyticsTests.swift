import XCTest
@testable import DesktopRewriteKit

final class ButtonAnalyticsTests: XCTestCase {
    func testStockButtonsResolveToStablePurposeKeysWithoutTitlesOrPrompts() {
        let prompts = OnboardingPresetPack.starter
            .drafts(writtenIn: .japanese)
            .enumerated()
            .map { $0.element.userPrompt(at: $0.offset) }

        XCTAssertEqual(
            prompts.map(OnboardingPresetPack.buttonAnalyticsKey(for:)),
            ["polite", "email", "translate_english", "natural_japanese"]
        )
    }

    func testSamePurposeUsesSameKeyAcrossPacks() {
        let starter = OnboardingPresetPack.starter.drafts(writtenIn: .japanese)[2]
        let international = OnboardingPresetPack.international.drafts(writtenIn: .japanese)[0]

        XCTAssertEqual(
            OnboardingPresetPack.buttonAnalyticsKey(for: starter.userPrompt(at: 0)),
            "translate_english"
        )
        XCTAssertEqual(
            OnboardingPresetPack.buttonAnalyticsKey(for: international.userPrompt(at: 0)),
            "translate_english"
        )
    }

    func testEditedNonBuiltinPresetDoesNotClaimTheStockPurpose() {
        var prompt = OnboardingPresetPack.work
            .drafts(writtenIn: .english)[0]
            .userPrompt(at: 0)
        prompt.prompt += " Keep it especially concise."

        XCTAssertEqual(
            OnboardingPresetPack.buttonAnalyticsKey(for: prompt),
            "customized_preset"
        )
    }

    func testUserAuthoredAndBuilderButtonsShareThePrivacySafeBucket() {
        for origin in [PromptOrigin.userAuthored, .onboardingBuilder] {
            let prompt = UserPrompt(
                slot: .main,
                title: "Private title",
                prompt: "Private instruction",
                origin: origin
            )
            XCTAssertEqual(
                OnboardingPresetPack.buttonAnalyticsKey(for: prompt),
                "user_authored"
            )
        }
    }

    func testAuthoredCopyOfAStockPromptStillReportsAsUserAuthored() {
        let stock = OnboardingPresetPack.starter.drafts(writtenIn: .english)[0]
        let prompt = UserPrompt(
            slot: .main,
            title: stock.title,
            prompt: stock.prompt,
            origin: .userAuthored
        )

        XCTAssertEqual(
            OnboardingPresetPack.buttonAnalyticsKey(for: prompt),
            "user_authored"
        )
    }

    func testLegacyBuiltinFallsBackToBuiltinKey() {
        let prompt = UserPrompt(
            slot: .main,
            builtinKey: "polite",
            title: "Edited title",
            prompt: "Edited legacy prompt",
            origin: .builtin
        )

        XCTAssertEqual(OnboardingPresetPack.buttonAnalyticsKey(for: prompt), "polite")
    }

    func testPresetCustomizationIgnoresIdentityButDetectsContentAndOrder() {
        let pack = OnboardingPresetPack.work
        let untouched = pack.drafts(writtenIn: .english)
        XCTAssertFalse(pack.isCustomized(drafts: untouched, writtenIn: .english))

        var edited = untouched
        edited[0].title = "Edited"
        XCTAssertTrue(pack.isCustomized(drafts: edited, writtenIn: .english))

        var reordered = untouched
        reordered.swapAt(0, 1)
        XCTAssertTrue(pack.isCustomized(drafts: reordered, writtenIn: .english))
    }

    func testAttemptCarriesButtonKeyThroughTheFunnelIdentity() {
        let attempt = RewriteAttempt(
            type: .savedButton,
            isTutorial: true,
            buttonAnalyticsKey: "work_chat"
        )

        XCTAssertEqual(attempt.buttonAnalyticsKey, "work_chat")
        XCTAssertEqual(
            RewriteFunnel.violations(in: [
                .started(attempt),
                .ended(attempt, .completed),
                .accepted(attempt),
            ]),
            []
        )
    }
}
