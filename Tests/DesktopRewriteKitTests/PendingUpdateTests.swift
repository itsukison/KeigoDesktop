import XCTest
@testable import DesktopRewriteKit

/// The decisions behind the update announcement. Every surface that shows it — the
/// panel above the bar, the status-menu row, the ホーム card — needs a window server,
/// so what a test can hold is this: which version is worth announcing, and when the
/// record stops being true.
final class PendingUpdateTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PendingUpdateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private var store: PendingUpdateStore { PendingUpdateStore(defaults: defaults) }

    // MARK: - Version comparison

    func testANewerPatchIsNewer() {
        XCTAssertTrue(PendingUpdate.isNewer("0.1.3", than: "0.1.2"))
        XCTAssertFalse(PendingUpdate.isNewer("0.1.2", than: "0.1.3"))
    }

    /// The one comparison a string sort gets wrong, and the one this project reaches
    /// within a handful of releases.
    func testTenIsNewerThanNine() {
        XCTAssertTrue(PendingUpdate.isNewer("0.1.10", than: "0.1.9"))
        XCTAssertFalse(PendingUpdate.isNewer("0.1.9", than: "0.1.10"))
    }

    func testTheSameVersionIsNotNewer() {
        XCTAssertFalse(PendingUpdate.isNewer("0.1.3", than: "0.1.3"))
    }

    /// A missing component is zero, so these name the same release.
    func testMissingComponentsReadAsZero() {
        XCTAssertFalse(PendingUpdate.isNewer("0.2", than: "0.2.0"))
        XCTAssertFalse(PendingUpdate.isNewer("0.2.0", than: "0.2"))
        XCTAssertTrue(PendingUpdate.isNewer("0.2.1", than: "0.2"))
    }

    func testAMajorBumpOutranksAHigherMinor() {
        XCTAssertTrue(PendingUpdate.isNewer("1.0.0", than: "0.9.9"))
    }

    // MARK: - The record

    func testNothingIsPendingByDefault() {
        XCTAssertNil(store.pending(for: "0.1.2"))
    }

    func testARecordedNewerVersionIsPending() {
        store.record("0.1.3")
        XCTAssertEqual(store.pending(for: "0.1.2"), "0.1.3")
    }

    /// The launch after a successful update. Without this the app announces an update
    /// to itself for as long as the record survives.
    func testInstallingTheUpdateClearsTheRecord() {
        store.record("0.1.3")
        XCTAssertNil(store.pending(for: "0.1.3"))
        // Cleared, not merely hidden — a later launch of an older build must not
        // resurrect it from the same key.
        XCTAssertNil(defaults.string(forKey: PendingUpdate.versionKey))
    }

    func testARecordOlderThanTheRunningBuildIsCleared() {
        store.record("0.1.1")
        XCTAssertNil(store.pending(for: "0.1.2"))
    }

    // MARK: - Dismissal

    func testDismissingTheToastLeavesTheUpdatePending() {
        store.record("0.1.3")
        store.dismissNotice(for: "0.1.3")
        XCTAssertTrue(store.isNoticeDismissed("0.1.3"))
        // The card and the menu row are driven by this, and they stay.
        XCTAssertEqual(store.pending(for: "0.1.2"), "0.1.3")
    }

    func testDismissalDoesNotCarryToTheNextVersion() {
        store.record("0.1.3")
        store.dismissNotice(for: "0.1.3")
        store.record("0.1.4")
        XCTAssertFalse(store.isNoticeDismissed("0.1.4"))
    }

    /// Re-recording the version the user already dismissed must not un-dismiss it:
    /// Sparkle re-finds the same update on every scheduled check, and a toast that came
    /// back once a day would be the nagging this design is trying not to be.
    func testRerecordingTheSameVersionKeepsItDismissed() {
        store.record("0.1.3")
        store.dismissNotice(for: "0.1.3")
        store.record("0.1.3")
        XCTAssertTrue(store.isNoticeDismissed("0.1.3"))
    }

    func testClearingRemovesBothKeys() {
        store.record("0.1.3")
        store.dismissNotice(for: "0.1.3")
        store.clear()
        XCTAssertNil(store.pending(for: "0.1.2"))
        XCTAssertFalse(store.isNoticeDismissed("0.1.3"))
    }
}
