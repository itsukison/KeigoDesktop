import DesktopRewriteKit
import Foundation
import XCTest

final class OnboardingProgressStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingProgressStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// The head of `flow`, which §17 made `.language` rather than `.welcome`. A
    /// fresh install is exactly the run the language page exists for, so this is the
    /// assertion that stops it being skipped.
    func testFreshInstallStartsAtTheHeadOfTheFlow() {
        let store = OnboardingProgressStore(defaults: defaults)
        XCTAssertFalse(store.isComplete)
        XCTAssertEqual(store.savedStep, .language)
        XCTAssertEqual(store.savedStep, DesktopOnboardingStep.flow.first)
    }

    func testUnfinishedStepSurvivesAStoreReload() {
        OnboardingProgressStore(defaults: defaults).save(step: .replyPractice)
        XCTAssertEqual(OnboardingProgressStore(defaults: defaults).savedStep, .replyPractice)

        OnboardingProgressStore(defaults: defaults).save(step: .customPractice)
        XCTAssertEqual(OnboardingProgressStore(defaults: defaults).savedStep, .customPractice)
    }

    func testCompletionClearsResumeStepAndCannotBeMovedBack() {
        let store = OnboardingProgressStore(defaults: defaults)
        store.save(step: .bar)
        store.complete()
        store.save(step: .access)

        XCTAssertTrue(store.isComplete)
        // Completion clears the key, so this is the no-saved-value answer again.
        XCTAssertEqual(store.savedStep, .language)
    }

    func testSelectedPackAndEditedDraftsSurviveAStoreReload() {
        let store = OnboardingProgressStore(defaults: defaults)
        var drafts = OnboardingPresetPack.work.drafts()
        drafts[0].title = "社内"
        store.save(pack: .work, drafts: drafts)

        let reloaded = OnboardingProgressStore(defaults: defaults)
        XCTAssertEqual(reloaded.savedPack, .work)
        XCTAssertEqual(reloaded.savedDrafts, drafts)
    }

    /// Every pack in every language — §17 gives English its own four-button sets and
    /// resolves the two English-only packs differently in the Japanese branch, so
    /// "four unique, complete, correctly ordered buttons" has to hold six ways.
    func testEveryPackProducesFourCompleteOrderedButtons() {
        defer { AppLanguageState.current = .japanese }

        for language in AppLanguage.allCases {
            AppLanguageState.current = language
            for pack in OnboardingPresetPack.allCases {
                let where_ = "\(language.rawValue)/\(pack.rawValue)"
                let drafts = pack.drafts()
                XCTAssertEqual(drafts.count, 4, where_)
                XCTAssertEqual(Set(drafts.map(\.title)).count, 4, where_)
                XCTAssertTrue(drafts.allSatisfy { !$0.title.isEmpty && !$0.prompt.isEmpty }, where_)

                let prompts = drafts.enumerated().map { $0.element.userPrompt(at: $0.offset) }
                XCTAssertEqual(prompts[0].slot, .main, where_)
                XCTAssertEqual(prompts[0].sortOrder, 0, where_)
                XCTAssertTrue(prompts.dropFirst().allSatisfy { $0.slot == .sub }, where_)
                XCTAssertEqual(prompts.dropFirst().map(\.sortOrder), [0, 1, 2], where_)
            }
        }
    }

    func testStarterPackKeepsTheSharedBuiltinKeys() {
        XCTAssertEqual(
            OnboardingPresetPack.starter.drafts().compactMap(\.builtinKey),
            ["polite", "email", "translateToEnglish", "natural"]
        )
    }

    func testPracticeStepsWereAppendedWithoutChangingExistingStoredSteps() {
        XCTAssertEqual(DesktopOnboardingStep.welcome.rawValue, 0)
        XCTAssertEqual(DesktopOnboardingStep.purpose.rawValue, 1)
        XCTAssertEqual(DesktopOnboardingStep.review.rawValue, 2)
        XCTAssertEqual(DesktopOnboardingStep.access.rawValue, 3)
        XCTAssertEqual(DesktopOnboardingStep.bar.rawValue, 4)
        XCTAssertEqual(DesktopOnboardingStep.practice.rawValue, 5)
        XCTAssertEqual(DesktopOnboardingStep.complete.rawValue, 6)
        XCTAssertEqual(DesktopOnboardingStep.replyPractice.rawValue, 7)
        XCTAssertEqual(DesktopOnboardingStep.customPractice.rawValue, 8)
        XCTAssertEqual(DesktopOnboardingStep.source.rawValue, 9)
        XCTAssertEqual(DesktopOnboardingStep.language.rawValue, 10)
        XCTAssertEqual(DesktopOnboardingStep.offer.rawValue, 11)
        XCTAssertEqual(
            DesktopOnboardingStep.flow,
            [
                .language, .welcome, .purpose, .review, .access, .bar, .practice,
                .customPractice, .replyPractice, .source, .offer, .complete,
            ]
        )
    }

    func testVisualFlowHasMatchingForwardAndBackNavigation() {
        let flow = DesktopOnboardingStep.flow
        XCTAssertEqual(Array(flow.dropFirst()), [
            .welcome, .purpose, .review, .access, .bar, .practice, .customPractice,
            .replyPractice, .source, .offer, .complete,
        ])
        XCTAssertEqual(Array(flow.dropLast().reversed()), [
            .offer, .source, .replyPractice, .customPractice, .practice, .bar, .access,
            .review, .purpose, .welcome, .language,
        ])
    }

    /// Both questions are asked before the closing card, not after it — 完了 hands the
    /// app over, and nothing should be asked once it has. The offer sits last of the
    /// two because it is the only one that costs money, and it has to come after the
    /// three practices that are the argument for paying.
    func testTheSourceQuestionAndTheOfferAreBothAskedBeforeCompletion() {
        XCTAssertEqual(DesktopOnboardingStep.flow.last, .complete)
        XCTAssertEqual(DesktopOnboardingStep.flow.dropLast().last, .offer)
        XCTAssertEqual(DesktopOnboardingStep.flow.dropLast(2).last, .source)
    }

    /// The rail counts setting-up steps. Neither the language question nor the offer
    /// is one, and the offer being counted would frame paying as part of installing.
    func testTheRailCountsNeitherTheLanguagePageNorTheOffer() {
        XCTAssertFalse(DesktopOnboardingStep.railSteps.contains(.language))
        XCTAssertFalse(DesktopOnboardingStep.railSteps.contains(.offer))
        XCTAssertEqual(DesktopOnboardingStep.railSteps.count, 10)
    }

    /// A step with no segment lights the last one at or before it. Without this the
    /// rail resets to segment one for the length of the offer page.
    func testAStepWithNoRailSegmentAnchorsToTheOneBeforeIt() {
        XCTAssertEqual(DesktopOnboardingStep.offer.railAnchor, .source)
        XCTAssertEqual(DesktopOnboardingStep.source.railAnchor, .source)
        XCTAssertEqual(DesktopOnboardingStep.complete.railAnchor, .complete)
        // Nothing precedes the language page, so there is nothing to light — and the
        // rail is hidden there anyway.
        XCTAssertNil(DesktopOnboardingStep.language.railAnchor)
    }

    /// The raw values reach PostHog as `source`. Renaming one splits an attribution
    /// series in two with nothing in the data to say it happened.
    func testSourceKeysAreStable() {
        XCTAssertEqual(
            OnboardingSource.allCases.map(\.rawValue),
            ["x", "youtube", "instagram", "tiktok", "web_search", "friend", "article", "other"]
        )
        XCTAssertTrue(OnboardingSource.allCases.allSatisfy { !$0.label.isEmpty })
    }

    func testCompletedVersionTwoUsersRemainComplete() {
        let store = OnboardingProgressStore(defaults: defaults)
        XCTAssertEqual(OnboardingProgressStore.currentVersion, 2)
        store.complete()
        XCTAssertTrue(OnboardingProgressStore(defaults: defaults).isComplete)
    }

    func testPracticeSamplesFollowTheReviewedMainButton() {
        let english = OnboardingPresetPack.international.drafts()[0].userPrompt(at: 0)
        let proofreading = OnboardingPresetPack.japanese.drafts()[0].userPrompt(at: 0)
        let chat = OnboardingPresetPack.work.drafts()[0].userPrompt(at: 0)

        XCTAssertTrue(OnboardingPracticeSample.text(for: english).contains("打ち合わせ"))
        XCTAssertTrue(OnboardingPracticeSample.text(for: proofreading).contains("でしょか"))
        XCTAssertTrue(OnboardingPracticeSample.text(for: chat).contains("リリース"))
        XCTAssertEqual(
            OnboardingPracticeSample.text(for: english),
            "来週の打ち合わせを火曜日の午後に変更できますか？"
        )
    }
}
