import XCTest
@testable import DesktopRewriteKit

/// The expiry math behind the right-click menu's snooze actions. `OverlayController`
/// and `ClipboardWatcher` are both untestable here — one needs a window server, the
/// other a real pasteboard — so the boundary check lives in `OverlaySnooze` instead.
final class OverlaySnoozeTests: XCTestCase {

    func testDurationsAreTenMinutesAndOneHour() {
        XCTAssertEqual(OverlaySnooze.Duration.tenMinutes.seconds, 600)
        XCTAssertEqual(OverlaySnooze.Duration.oneHour.seconds, 3600)
    }

    func testUntilAddsTheDurationToTheStartingClock() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        XCTAssertEqual(
            OverlaySnooze.until(.tenMinutes, from: now),
            now.addingTimeInterval(600)
        )
        XCTAssertEqual(
            OverlaySnooze.until(.oneHour, from: now),
            now.addingTimeInterval(3600)
        )
    }

    func testNoDeadlineIsNeverActive() {
        XCTAssertFalse(OverlaySnooze.isActive(until: nil))
    }

    func testFutureDeadlineIsActive() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let deadline = OverlaySnooze.until(.tenMinutes, from: now)
        XCTAssertTrue(OverlaySnooze.isActive(until: deadline, at: now))
        XCTAssertTrue(OverlaySnooze.isActive(until: deadline, at: deadline.addingTimeInterval(-1)))
    }

    /// The boundary is exclusive — the instant `now` reaches the deadline, the snooze
    /// has ended, not one tick later. `checkHiddenExpiry`'s 0.5 s poll relies on this
    /// rather than on an off-by-one grace window.
    func testDeadlineItselfIsNoLongerActive() {
        let deadline = Date(timeIntervalSinceReferenceDate: 1_000_600)
        XCTAssertFalse(OverlaySnooze.isActive(until: deadline, at: deadline))
        XCTAssertFalse(OverlaySnooze.isActive(until: deadline, at: deadline.addingTimeInterval(1)))
    }

    // MARK: - UserDefaults round-trip

    func testUserDefaultsRoundTripsADeadline() {
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        let deadline = Date(timeIntervalSinceReferenceDate: 2_000_000)
        defaults.setOverlaySnoozeDeadline(deadline, forKey: "test.deadline")
        XCTAssertEqual(defaults.overlaySnoozeDeadline(forKey: "test.deadline"), deadline)
    }

    /// Setting `nil` removes the key rather than storing a zero epoch, which is what
    /// makes an absent key and an explicitly-cleared one read back the same way.
    func testSettingNilRemovesTheKey() {
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        defaults.setOverlaySnoozeDeadline(Date(), forKey: "test.deadline")
        defaults.setOverlaySnoozeDeadline(nil, forKey: "test.deadline")
        XCTAssertNil(defaults.overlaySnoozeDeadline(forKey: "test.deadline"))
        XCTAssertNil(defaults.object(forKey: "test.deadline"))
    }

    // MARK: - Remaining-minutes readout

    /// Rounds up: 8 minutes and 1 second left still reads "残り9分", not "残り8分" —
    /// the row would otherwise undercount the time actually remaining.
    func testRemainingMinutesRoundsUp() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let deadline = now.addingTimeInterval(8 * 60 + 1)
        XCTAssertEqual(OverlaySnooze.remainingMinutes(until: deadline, at: now), 9)
    }

    func testRemainingMinutesOnAnExactBoundary() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let deadline = now.addingTimeInterval(10 * 60)
        XCTAssertEqual(OverlaySnooze.remainingMinutes(until: deadline, at: now), 10)
    }

    /// Never negative once the deadline has passed — `isActive` is what callers should
    /// check before displaying this at all, but the arithmetic itself does not go below
    /// zero if they don't.
    func testRemainingMinutesFlooredAtZero() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let deadline = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(OverlaySnooze.remainingMinutes(until: deadline, at: now), 0)
    }

    func testMissingKeyReadsAsNil() {
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        XCTAssertNil(defaults.overlaySnoozeDeadline(forKey: "test.neverSet"))
    }
}
