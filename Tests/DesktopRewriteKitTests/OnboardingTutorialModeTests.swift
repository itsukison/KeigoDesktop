import DesktopRewriteKit
import XCTest

final class OnboardingTutorialModeTests: XCTestCase {
    func testCustomPracticeRejectsSavedButtonsAndBlankGuidance() {
        let mode = OnboardingTutorialMode.custom

        XCTAssertFalse(mode.marksSavedButton(id: UUID()))
        XCTAssertFalse(mode.marksCustomGuidance(""))
        XCTAssertFalse(mode.marksCustomGuidance("  \n"))
        XCTAssertTrue(mode.marksCustomGuidance("取引先向けに簡潔なメールにしてください。"))
        XCTAssertFalse(mode.marksReply)
    }

    func testSavedButtonPracticeMarksOnlyReviewedPromptIDs() {
        let reviewed = UUID()
        let mode = OnboardingTutorialMode.savedButtons(Set([reviewed]))

        XCTAssertTrue(mode.marksSavedButton(id: reviewed))
        XCTAssertFalse(mode.marksSavedButton(id: UUID()))
        XCTAssertFalse(mode.marksCustomGuidance("丁寧に"))
    }

    func testReplyPracticeMarksOnlyReplyRequests() {
        let mode = OnboardingTutorialMode.reply

        XCTAssertTrue(mode.marksReply)
        XCTAssertFalse(mode.marksSavedButton(id: UUID()))
        XCTAssertFalse(mode.marksCustomGuidance("短く"))
    }
}
