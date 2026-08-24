import XCTest
@testable import DesktopRewriteKit

/// The funnel's one invariant: **every `desktop_rewrite_started` is followed by exactly
/// one of `completed`, `failed` or `abandoned`.**
///
/// Two layers of test, because the risk is in two places:
///
///   1. `RewriteAttemptTracker` — the mechanism. Proven under every ordering, including
///      the overlapping ones that actually happen (a dismiss racing a response, a second
///      press superseding the first).
///   2. `RewriteFunnel.violations` applied to sequences that **encode each real
///      `OverlayController` path**. `OverlayController` needs a window server and cannot
///      be unit-tested, so these sequences are the record of what its paths emit. If a
///      path changes, the corresponding case here is what should change with it.
final class RewriteAttemptTests: XCTestCase {

    private func attempt(_ type: RewriteType = .savedButton, isTutorial: Bool = false) -> RewriteAttempt {
        RewriteAttempt(type: type, isTutorial: isTutorial)
    }

    // MARK: - Wire format

    /// The raw values are the wire format. Renaming one splits a dashboard series after
    /// the fact, with no way to stitch the halves back together — the same hazard
    /// `docs/analytics.md` §1 records for `OnboardingSource`.
    func testRewriteTypeRawValuesArePinned() {
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: RewriteType.allCases.map { ($0, $0.rawValue) }),
            [
                .savedButton: "saved_button",
                .customInstruction: "custom_instruction",
                .reply: "reply",
                .regenerate: "regenerate",
                .refine: "refine",
            ]
        )
    }

    func testFailureStageAndAbandonReasonRawValuesArePinned() {
        XCTAssertEqual(FailureStage.allCases.map(\.rawValue), ["capture", "generation"])
        XCTAssertEqual(AbandonReason.allCases.map(\.rawValue), ["superseded", "dismissed"])
    }

    /// `isTutorial` is a separate boolean, deliberately, and there is no tutorial case in
    /// `RewriteType`. A future edit that adds one would silently make every "attempts by
    /// type" tile stop summing to the total.
    func testTutorialIsNotARewriteType() {
        XCTAssertFalse(RewriteType.allCases.contains { $0.rawValue.contains("tutorial") })
        XCTAssertFalse(RewriteType.allCases.contains { $0.rawValue.contains("onboarding") })
        XCTAssertEqual(RewriteType.allCases.count, 5)
    }

    // MARK: - The tracker

    func testFinishReturnsTheOpenAttemptExactlyOnce() {
        var tracker = RewriteAttemptTracker()
        let a = attempt()
        XCTAssertNil(tracker.begin(a), "nothing was open, so nothing is superseded")
        XCTAssertEqual(tracker.active, a)

        XCTAssertEqual(tracker.finish(), a)
        // The second terminal report is the one that would double-count a single press.
        XCTAssertNil(tracker.finish())
        XCTAssertNil(tracker.finish())
        XCTAssertNil(tracker.active)
    }

    func testFinishWithNothingOpenReportsNothing() {
        var tracker = RewriteAttemptTracker()
        XCTAssertNil(tracker.finish())
    }

    /// The case that was silent before this shipped: a second press while the first is
    /// still generating. The first request has already been sent and metered, so it must
    /// be reported — `begin` returning it is what forces that.
    func testBeginHandsBackTheSupersededAttempt() {
        var tracker = RewriteAttemptTracker()
        let first = attempt(.savedButton)
        let second = attempt(.regenerate)

        tracker.begin(first)
        XCTAssertEqual(tracker.begin(second), first)
        XCTAssertEqual(tracker.active, second)
        XCTAssertEqual(tracker.finish(), second)
    }

    func testEveryBeginYieldsExactlyOneTerminalAcrossALongRun() {
        var tracker = RewriteAttemptTracker()
        var started: [RewriteAttempt] = []
        var terminated: [RewriteAttempt] = []

        // A deliberately awkward interleaving: begins that supersede, finishes with
        // nothing open, and repeated finishes.
        for index in 0 ..< 50 {
            let next = attempt(RewriteType.allCases[index % RewriteType.allCases.count])
            started.append(next)
            if let superseded = tracker.begin(next) { terminated.append(superseded) }
            if index % 3 == 0, let done = tracker.finish() { terminated.append(done) }
            if index % 7 == 0, let extra = tracker.finish() { terminated.append(extra) }
        }
        if let last = tracker.finish() { terminated.append(last) }

        XCTAssertEqual(
            terminated.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }),
            started.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }),
            "every attempt that started must have terminated exactly once"
        )
        XCTAssertEqual(Set(terminated.map(\.id)).count, terminated.count, "no attempt terminated twice")
    }

    // MARK: - The real controller paths

    /// `press()` → capture → generation → the user accepts.
    func testHappyPathSatisfiesTheInvariant() {
        let a = attempt(.savedButton)
        XCTAssertEqual(
            RewriteFunnel.violations(in: [.started(a), .ended(a, .completed), .accepted(a)]),
            []
        )
    }

    /// `press()` → `textIO.capture` throws. The dominant real failure: 17 of 17 failures
    /// external users hit before this shipped. Reported as a started/failed pair so it
    /// sits inside the funnel rather than beside it.
    func testCaptureFailureIsAStartedThenFailedPair() {
        let a = attempt(.savedButton)
        XCTAssertEqual(
            RewriteFunnel.violations(in: [.started(a), .ended(a, .failed(.capture))]),
            []
        )
    }

    /// The backend or network fails after the request went out.
    func testGenerationFailureSatisfiesTheInvariant() {
        let a = attempt(.customInstruction)
        XCTAssertEqual(
            RewriteFunnel.violations(in: [.started(a), .ended(a, .failed(.generation))]),
            []
        )
    }

    /// `cancelRewrite()` / `dismiss()` while `.generating`.
    func testDismissWhileGeneratingSatisfiesTheInvariant() {
        let a = attempt(.reply)
        XCTAssertEqual(
            RewriteFunnel.violations(in: [.started(a), .ended(a, .abandoned(.dismissed))]),
            []
        )
    }

    /// A second press before the first returned. Both attempts must end.
    func testSupersededAttemptStillEnds() {
        let first = attempt(.savedButton)
        let second = attempt(.savedButton)
        XCTAssertEqual(
            RewriteFunnel.violations(in: [
                .started(first),
                .started(second),
                .ended(first, .abandoned(.superseded)),
                .ended(second, .completed),
                .accepted(second),
            ]),
            []
        )
    }

    /// A regenerate chain: each ↻ is its own attempt, separately generated and billed,
    /// and only the last one is accepted.
    func testRegenerateChainSatisfiesTheInvariant() {
        let first = attempt(.savedButton)
        let again = attempt(.regenerate)
        let refined = attempt(.refine)
        XCTAssertEqual(
            RewriteFunnel.violations(in: [
                .started(first), .ended(first, .completed),
                .started(again), .ended(again, .completed),
                .started(refined), .ended(refined, .completed),
                .accepted(refined),
            ]),
            []
        )
    }

    /// Onboarding practice runs the same paths with `isTutorial` set. It must satisfy the
    /// invariant identically — it is counted in the totals now, not filtered out.
    func testTutorialPracticeSatisfiesTheInvariant() {
        let a = attempt(.savedButton, isTutorial: true)
        XCTAssertEqual(
            RewriteFunnel.violations(in: [.started(a), .ended(a, .completed), .accepted(a)]),
            []
        )
    }

    // MARK: - The checker actually catches violations

    func testStartedWithNoEndingIsCaught() {
        let a = attempt()
        XCTAssertEqual(RewriteFunnel.violations(in: [.started(a)]), [.neverEnded(a.id)])
    }

    func testTwoTerminalEventsForOneAttemptAreCaught() {
        let a = attempt()
        XCTAssertEqual(
            RewriteFunnel.violations(in: [
                .started(a),
                .ended(a, .completed),
                .ended(a, .failed(.generation)),
            ]),
            [.endedTwice(a.id)]
        )
    }

    func testTerminalWithoutAStartIsCaught() {
        let a = attempt()
        XCTAssertEqual(
            RewriteFunnel.violations(in: [.ended(a, .completed)]),
            [.endedWithoutStart(a.id)]
        )
    }

    func testDuplicateStartIsCaught() {
        let a = attempt()
        XCTAssertEqual(
            RewriteFunnel.violations(in: [.started(a), .started(a), .ended(a, .completed)]),
            [.startedTwice(a.id)]
        )
    }

    /// An insert can only follow a completion. An accepted-but-failed attempt would mean
    /// the acceptance-rate tile has a denominator that does not contain its numerator.
    func testAcceptanceWithoutCompletionIsCaught() {
        let a = attempt()
        XCTAssertEqual(
            RewriteFunnel.violations(in: [
                .started(a),
                .ended(a, .abandoned(.dismissed)),
                .accepted(a),
            ]),
            [.acceptedWithoutCompletion(a.id)]
        )
    }

    func testMultipleUnendedAttemptsAreAllReported() {
        let a = attempt()
        let b = attempt()
        let violations = RewriteFunnel.violations(in: [.started(a), .started(b)])
        XCTAssertEqual(violations.count, 2)
        XCTAssertEqual(Set(violations), [.neverEnded(a.id), .neverEnded(b.id)])
    }
}
