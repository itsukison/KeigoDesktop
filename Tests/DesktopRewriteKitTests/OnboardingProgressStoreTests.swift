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
        OnboardingProgressStore(defaults: defaults).save(step: .practice)
        XCTAssertEqual(OnboardingProgressStore(defaults: defaults).savedStep, .practice)
    }

    func testCompletionClearsResumeStepAndCannotBeMovedBack() {
        let store = OnboardingProgressStore(defaults: defaults)
        store.save(step: .bar)
        store.complete()
        store.save(step: .access)

        XCTAssertTrue(store.isComplete)
        XCTAssertEqual(store.savedStep, .welcome)
    }
}
