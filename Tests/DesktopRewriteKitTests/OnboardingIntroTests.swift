import DesktopRewriteKit
import Foundation
import XCTest

final class OnboardingIntroTests: XCTestCase {
    func testDebugReplayCannotConsumeFirstLaunchOrOverwriteUnfinishedProgress() {
        let suite = "IntroTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingProgressStore(defaults: defaults)
        let replay = store.replayCopy()
        replay.save(step: .language)
        replay.complete()
        XCTAssertTrue(store.shouldPresentIntro)
        XCTAssertFalse(store.isComplete)
        store.save(step: .access)
        replay.save(step: .language)
        replay.save(pack: .work, drafts: [], accountID: "A")
        replay.complete()
        XCTAssertEqual(store.savedStep, .access)
        XCTAssertNil(store.savedPack(for: "A"))
        XCTAssertFalse(store.isComplete)
    }

    func testIntroEligibilityIsConsumedBySavingLanguageBeforePresentation() {
        let suite = "IntroTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingProgressStore(defaults: defaults)
        XCTAssertTrue(store.shouldPresentIntro)
        store.save(step: .language)
        let resumed = OnboardingProgressStore(defaults: defaults)
        XCTAssertFalse(resumed.shouldPresentIntro)
        XCTAssertEqual(resumed.savedStep, .language)
        XCTAssertFalse(resumed.isComplete)
    }

    func testAllSavedStepsAndCompletedUsersBypassIntro() {
        let suite = "IntroTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingProgressStore(defaults: defaults)
        for step in DesktopOnboardingStep.allCases {
            store.save(step: step)
            XCTAssertFalse(store.shouldPresentIntro)
        }
        store.complete()
        XCTAssertEqual(OnboardingProgressStore.currentVersion, 2)
        XCTAssertFalse(store.shouldPresentIntro)
        XCTAssertTrue(store.isComplete)
    }

    func testCorruptSavedStepDoesNotRestartCinematic() {
        let suite = "IntroTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(999, forKey: "desktopOnboarding.step")
        let store = OnboardingProgressStore(defaults: defaults)
        XCTAssertFalse(store.shouldPresentIntro)
        XCTAssertEqual(store.savedStep, .welcome)
    }

    func testReducedMotionKeepsReadingTimeButRemovesPhysicalMotion() {
        let beats = OnboardingIntroTimeline.beats(reduceMotion: true)
        XCTAssertEqual(beats.first?.cue, .dim)
        XCTAssertEqual(beats.last?.cue, .finish)
        XCTAssertEqual(beats.filter { $0.cue == .read }.reduce(0) { $0 + $1.duration }, 9)
        XCTAssertEqual(beats.first { $0.cue == .pillRead }?.duration, 3)
        for cue: IntroCue in [.anticipate, .travel, .land, .wiggle, .expression] {
            XCTAssertFalse(beats.contains { $0.cue == cue })
        }
        XCTAssertTrue(beats.contains { $0.cue == .reducedArrival })
    }

    func testLandingPointUsesLogicalCoordinatesAndDisplayOrigin() {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: 260, width: 1920, height: 1080),
                       CGRect(x: 1440, y: -900, width: 1280, height: 800)] {
            let pill = CGRect(x: screen.midX - 22, y: screen.minY + 84, width: 44, height: 28)
            let point = IntroGeometry.landingPoint(pill: pill, screen: screen)
            XCTAssertEqual(point.x, screen.width / 2)
            XCTAssertEqual(point.y, screen.height - 98)
            XCTAssertEqual(CGPoint(x: point.x + screen.minX, y: screen.maxY - point.y),
                           CGPoint(x: pill.midX, y: pill.midY))
        }
    }

    @MainActor
    func testClockFailureStillReachesUsableOnboarding() async {
        struct ClockFailure: Error { }
        let finished = expectation(description: "fallback finished")
        var cues: [IntroCue] = []
        let sequence = OnboardingIntroSequence(sleep: { _ in throw ClockFailure() })
        sequence.start(reduceMotion: false) { beat in
            cues.append(beat.cue)
            if beat.cue == .finish { finished.fulfill() }
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(cues, [.dim, .finish])
    }

    @MainActor
    func testRepeatedPresentationCannotRestartOrDuplicateFinishedSequence() async {
        var cues: [IntroCue] = []
        let finished = expectation(description: "finished")
        let sequence = OnboardingIntroSequence(sleep: { _ in })
        let perform: OnboardingIntroSequence.Perform = { beat in
            cues.append(beat.cue)
            if beat.cue == .finish { finished.fulfill() }
        }
        sequence.start(reduceMotion: false, perform: perform)
        sequence.start(reduceMotion: false, perform: perform)
        await fulfillment(of: [finished], timeout: 2)
        sequence.start(reduceMotion: false, perform: perform)
        await Task.yield()
        XCTAssertEqual(cues, OnboardingIntroTimeline.beats(reduceMotion: false).map(\.cue))
    }

    @MainActor
    func testEscapeReplacesWaitingRunAndStaleClockCannotAdvanceIt() async {
        var continuation: CheckedContinuation<Void, Error>?
        var cues: [IntroCue] = []
        let waiting = expectation(description: "waiting")
        let finished = expectation(description: "finished")
        let sequence = OnboardingIntroSequence(sleep: { duration in
            if duration == 0.4 {
                try await withCheckedThrowingContinuation { pending in
                    continuation = pending
                    waiting.fulfill()
                }
            }
        })
        sequence.start(reduceMotion: false) { beat in
            cues.append(beat.cue)
            if beat.cue == .finish { finished.fulfill() }
        }
        await fulfillment(of: [waiting], timeout: 2)
        sequence.skipToReveal()
        sequence.skipToReveal()
        await fulfillment(of: [finished], timeout: 2)
        continuation?.resume()
        await Task.yield()
        XCTAssertEqual(cues, [.dim] + OnboardingIntroTimeline.skip.map(\.cue))
    }

    @MainActor
    func testEscapeDuringCopyFadeCannotRevealSecondSentenceLater() async {
        var continuation: CheckedContinuation<Void, Error>?
        var cues: [IntroCue] = []
        let fading = expectation(description: "first sentence fading")
        let finished = expectation(description: "finished")
        let sequence = OnboardingIntroSequence(sleep: { _ in
            if cues.last == .copyOut {
                try await withCheckedThrowingContinuation { pending in
                    continuation = pending
                    fading.fulfill()
                }
            }
        })
        sequence.start(reduceMotion: false) { beat in
            cues.append(beat.cue)
            if beat.cue == .finish { finished.fulfill() }
        }
        await fulfillment(of: [fading], timeout: 2)
        sequence.skipToReveal()
        await fulfillment(of: [finished], timeout: 2)
        continuation?.resume()
        await Task.yield()
        XCTAssertFalse(cues.contains(.nextCopy))
        XCTAssertEqual(Array(cues.suffix(OnboardingIntroTimeline.skip.count)),
                       OnboardingIntroTimeline.skip.map(\.cue))
        XCTAssertFalse(sequence.isRunning)
    }

    @MainActor
    func testInterruptionStopsBeforeLanguageReveal() async {
        var continuation: CheckedContinuation<Void, Error>?
        let waiting = expectation(description: "waiting")
        var cues: [IntroCue] = []
        let sequence = OnboardingIntroSequence(sleep: { _ in
            try await withCheckedThrowingContinuation { pending in
                continuation = pending
                waiting.fulfill()
            }
        })
        sequence.start(reduceMotion: true) { cues.append($0.cue) }
        await fulfillment(of: [waiting], timeout: 2)
        sequence.cancel()
        continuation?.resume()
        await Task.yield()
        XCTAssertFalse(sequence.isRunning)
        XCTAssertEqual(cues, [.dim])
    }
}
