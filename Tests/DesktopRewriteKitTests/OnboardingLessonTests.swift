import XCTest
@testable import DesktopRewriteKit

final class OnboardingLessonTests: XCTestCase {
    private func send(_ event: OnboardingLesson.Event, to lesson: inout OnboardingLesson) {
        lesson.receive(event, sessionID: lesson.id)
    }

    func testDiscoveryRequiresRealHoverAndDisablesEveryAction() {
        var lesson = OnboardingLesson(kind: .discovery)
        send(.editor(ready: true, empty: false), to: &lesson)
        XCTAssertFalse(lesson.discovered)
        XCTAssertEqual(lesson.phase, .hover)
        for action in [OnboardingLesson.Action.polish, .custom, .reply] { XCTAssertFalse(lesson.allows(action)) }
        send(.hovered, to: &lesson)
        send(.collapsed, to: &lesson)
        XCTAssertTrue(lesson.discovered)
        XCTAssertEqual(lesson.phase, .discovered)
        XCTAssertEqual(OnboardingLesson(kind: .discovery, discovered: true).phase, .discovered)
    }

    func testFirstPracticeTeachesHoverWithoutDiscoveryPage() {
        var lesson = OnboardingLesson(kind: .rewrite)
        send(.editor(ready: true, empty: false), to: &lesson)
        XCTAssertEqual(lesson.phase, .hover)
        XCTAssertFalse(lesson.allows(.polish))
        send(.hovered, to: &lesson)
        XCTAssertEqual(lesson.phase, .action)
        XCTAssertTrue(lesson.allows(.polish))
        XCTAssertTrue(lesson.discovered)
        XCTAssertFalse(lesson.isComplete)
    }

    func testRewriteAllowsOnlyPolishAfterEditorAndHover() {
        var lesson = OnboardingLesson(kind: .rewrite)
        send(.hovered, to: &lesson)
        XCTAssertEqual(lesson.phase, .focus)
        XCTAssertFalse(lesson.allows(.polish))
        send(.editor(ready: true, empty: false), to: &lesson)
        XCTAssertTrue(lesson.allows(.polish))
        XCTAssertFalse(lesson.allows(.custom))
        XCTAssertFalse(lesson.allows(.reply))
        send(.composerOpened, to: &lesson)
        XCTAssertEqual(lesson.phase, .action)
        send(.generating, to: &lesson)
        send(.editor(ready: false, empty: false), to: &lesson)
        XCTAssertEqual(lesson.phase, .generating)
        send(.result, to: &lesson)
        send(.completed(.inserted), to: &lesson)
        XCTAssertEqual(lesson.phase, .complete(.inserted))
        send(.collapsed, to: &lesson)
        XCTAssertTrue(lesson.isComplete)
    }

    func testCustomTextAndComposerFocusDoNotRewindLesson() {
        var lesson = OnboardingLesson(kind: .custom)
        send(.editor(ready: true, empty: false), to: &lesson)
        send(.hovered, to: &lesson)
        XCTAssertTrue(lesson.allows(.custom))
        send(.composerOpened, to: &lesson)
        send(.editor(ready: false, empty: false), to: &lesson)
        XCTAssertEqual(lesson.phase, .instruction)
        send(.guidanceChanged(nonempty: true), to: &lesson)
        XCTAssertEqual(lesson.phase, .submit)
        send(.guidanceChanged(nonempty: false), to: &lesson)
        XCTAssertEqual(lesson.phase, .instruction)
        send(.cancelled, to: &lesson)
        XCTAssertEqual(lesson.phase, .focus)
        send(.editor(ready: true, empty: false), to: &lesson)
        XCTAssertEqual(lesson.phase, .hover)
    }

    func testReplyRequiresSourceButAllowsEmptyDraftAndOptionalGuidance() {
        var lesson = OnboardingLesson(kind: .reply)
        send(.editor(ready: true, empty: true), to: &lesson)
        send(.hovered, to: &lesson)
        XCTAssertEqual(lesson.phase, .source)
        send(.sourceSelected, to: &lesson)
        XCTAssertTrue(lesson.allows(.reply))
        send(.composerOpened, to: &lesson)
        send(.generating, to: &lesson)
        XCTAssertEqual(lesson.phase, .generating)
        send(.result, to: &lesson)
        send(.completed(.copied), to: &lesson)
        XCTAssertEqual(lesson.phase, .complete(.copied))
    }

    func testDismissingOrExpiringCopiedSourceReturnsReplyLessonToCopyStep() {
        var lesson = OnboardingLesson(kind: .reply)
        send(.editor(ready: true, empty: true), to: &lesson)
        send(.sourceSelected, to: &lesson)
        send(.hovered, to: &lesson)
        XCTAssertTrue(lesson.allows(.reply))
        send(.sourceCleared, to: &lesson)
        XCTAssertEqual(lesson.phase, .source)
        XCTAssertFalse(lesson.allows(.reply))
        send(.sourceSelected, to: &lesson)
        XCTAssertTrue(lesson.allows(.reply))
        send(.composerOpened, to: &lesson)
        send(.sourceCleared, to: &lesson)
        XCTAssertEqual(lesson.phase, .instruction)
        XCTAssertTrue(lesson.sourceSelected)
        send(.cancelled, to: &lesson)
        send(.sourceCleared, to: &lesson)
        XCTAssertEqual(lesson.phase, .source)
    }

    func testEmptiedSampleAndLostFocusRecoverWithoutLosingDiscovery() {
        var lesson = OnboardingLesson(kind: .rewrite)
        send(.editor(ready: true, empty: false), to: &lesson)
        send(.hovered, to: &lesson)
        send(.editor(ready: true, empty: true), to: &lesson)
        XCTAssertEqual(lesson.phase, .restore)
        XCTAssertFalse(lesson.allows(.polish))
        send(.editor(ready: false, empty: false), to: &lesson)
        XCTAssertEqual(lesson.phase, .focus)
        send(.editor(ready: true, empty: false), to: &lesson)
        XCTAssertEqual(lesson.phase, .action)
        XCTAssertTrue(lesson.discovered)
    }

    func testFailureOffersRetryAndInsertFailureKeepsResult() {
        var lesson = OnboardingLesson(kind: .rewrite)
        send(.editor(ready: true, empty: false), to: &lesson)
        send(.hovered, to: &lesson)
        send(.generating, to: &lesson)
        send(.failed, to: &lesson)
        XCTAssertEqual(lesson.phase, .hover)
        XCTAssertTrue(lesson.needsRetry)
        send(.hovered, to: &lesson)
        send(.generating, to: &lesson)
        XCTAssertFalse(lesson.needsRetry)
        send(.result, to: &lesson)
        send(.failed, to: &lesson)
        XCTAssertEqual(lesson.phase, .result)
        send(.completed(.copied), to: &lesson)
        XCTAssertTrue(lesson.isComplete)
    }

    func testLateEventsCannotAffectNewLessonOrFinishEarly() {
        let old = OnboardingLesson(kind: .rewrite)
        var next = OnboardingLesson(kind: .custom)
        for event in [OnboardingLesson.Event.hovered, .generating, .result, .completed(.inserted), .failed] {
            next.receive(event, sessionID: old.id)
        }
        XCTAssertEqual(next, OnboardingLesson(kind: .custom, id: next.id))
        send(.completed(.inserted), to: &next)
        send(.result, to: &next)
        XCTAssertFalse(next.isComplete)
        XCTAssertEqual(next.phase, .focus)
    }

    func testCalloutFitsAllFourEdgesAndNeverCoversTarget() throws {
        let area = CGRect(x: 100, y: 80, width: 1440, height: 900)
        let cases: [(CGRect, OnboardingGuidePlacement.Edge)] = [
            (CGRect(x: 800, y: 86, width: 44, height: 28), .above),
            (CGRect(x: 800, y: 940, width: 180, height: 28), .below),
            (CGRect(x: 106, y: 510, width: 28, height: 44), .right),
            (CGRect(x: 1506, y: 510, width: 28, height: 44), .left)
        ]
        for (bar, edge) in cases {
            let placement = try XCTUnwrap(OnboardingGuidePlacement.place(target: bar, owner: bar,
                size: CGSize(width: 344, height: 116), workArea: area, preferred: edge, obstacles: []))
            XCTAssertEqual(placement.edge, edge)
            XCTAssertTrue(area.contains(placement.frame))
            XCTAssertFalse(placement.frame.intersects(bar))
        }
    }

    func testCalloutAvoidsReplyCardAndHidesIfThereIsNoSpace() throws {
        let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let bar = CGRect(x: 540, y: 86, width: 360, height: 40)
        let card = CGRect(x: 540, y: 134, width: 360, height: 260)
        let placement = try XCTUnwrap(OnboardingGuidePlacement.place(target: bar, owner: bar,
            size: CGSize(width: 344, height: 116), workArea: area, preferred: .above, obstacles: [card]))
        XCTAssertFalse(placement.frame.intersects(card))
        XCTAssertNil(OnboardingGuidePlacement.place(target: bar, owner: bar,
            size: CGSize(width: 344, height: 116), workArea: area, preferred: .above, obstacles: [area]))
    }
}
