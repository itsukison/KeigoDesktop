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

    func testFreshInstallStartsAtWelcome() {
        let store = OnboardingProgressStore(defaults: defaults)
        XCTAssertFalse(store.isComplete)
        XCTAssertEqual(store.savedStep, .welcome)
    }

    func testUnfinishedStepSurvivesAStoreReload() {
        OnboardingProgressStore(defaults: defaults).save(step: .replyPractice)
        XCTAssertEqual(OnboardingProgressStore(defaults: defaults).savedStep, .replyPractice)
    }

    func testCompletionClearsResumeStepAndCannotBeMovedBack() {
        let store = OnboardingProgressStore(defaults: defaults)
        store.save(step: .bar)
        store.complete()
        store.save(step: .access)

        XCTAssertTrue(store.isComplete)
        XCTAssertEqual(store.savedStep, .welcome)
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

    func testEveryPackProducesFourCompleteOrderedButtons() {
        for pack in OnboardingPresetPack.allCases {
            let drafts = pack.drafts()
            XCTAssertEqual(drafts.count, 4, pack.rawValue)
            XCTAssertEqual(Set(drafts.map(\.title)).count, 4, pack.rawValue)
            XCTAssertTrue(drafts.allSatisfy { !$0.title.isEmpty && !$0.prompt.isEmpty })

            let prompts = drafts.enumerated().map { $0.element.userPrompt(at: $0.offset) }
            XCTAssertEqual(prompts[0].slot, .main)
            XCTAssertEqual(prompts[0].sortOrder, 0)
            XCTAssertTrue(prompts.dropFirst().allSatisfy { $0.slot == .sub })
            XCTAssertEqual(prompts.dropFirst().map(\.sortOrder), [0, 1, 2])
        }
    }

    func testStarterPackKeepsTheSharedBuiltinKeys() {
        XCTAssertEqual(
            OnboardingPresetPack.starter.drafts().compactMap(\.builtinKey),
            ["polite", "email", "translateToEnglish", "natural"]
        )
    }

    func testReplyPracticeWasAppendedWithoutChangingExistingStoredSteps() {
        XCTAssertEqual(DesktopOnboardingStep.complete.rawValue, 6)
        XCTAssertEqual(DesktopOnboardingStep.replyPractice.rawValue, 7)
        XCTAssertEqual(
            DesktopOnboardingStep.flow,
            [.welcome, .purpose, .review, .access, .bar, .practice, .replyPractice, .complete]
        )
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
