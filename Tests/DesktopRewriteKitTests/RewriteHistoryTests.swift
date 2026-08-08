import XCTest
@testable import DesktopRewriteKit

/// The ホーム page's numbers are the only thing on it, so the arithmetic behind them
/// is pinned here rather than eyeballed in the window.
final class RewriteStatsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func entry(daysAgo: Int, characters: Int = 10, app: String? = nil) -> RewriteHistoryEntry {
        RewriteHistoryEntry(
            createdAt: calendar.date(byAdding: .day, value: -daysAgo, to: Self.now)!,
            buttonTitle: "敬語",
            promptText: "丁寧に",
            originalText: String(repeating: "あ", count: characters),
            rewrittenText: "書き換え後",
            hostAppBundleId: app
        )
    }

    /// Fixed so a test run at 23:59 does not straddle a day boundary.
    private static let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testEmptyHistoryIsAllZeroes() {
        XCTAssertEqual(RewriteStats.from(entries: [], now: Self.now), .empty)
    }

    func testCharactersCountTheTextThatWentIn() {
        let stats = RewriteStats.from(
            entries: [entry(daysAgo: 0, characters: 12), entry(daysAgo: 1, characters: 8)],
            now: Self.now,
            calendar: calendar
        )
        XCTAssertEqual(stats.totalRewrites, 2)
        XCTAssertEqual(stats.charactersRewritten, 20)
    }

    /// The whole reason the streak is anchored to yesterday: opening the app before
    /// the first rewrite of the day must not report the streak as broken.
    func testStreakSurvivesAnEmptyToday() {
        let stats = RewriteStats.from(
            entries: [entry(daysAgo: 1), entry(daysAgo: 2), entry(daysAgo: 3)],
            now: Self.now,
            calendar: calendar
        )
        XCTAssertEqual(stats.dayStreak, 3)
    }

    func testStreakStopsAtAGap() {
        let stats = RewriteStats.from(
            entries: [entry(daysAgo: 0), entry(daysAgo: 1), entry(daysAgo: 4)],
            now: Self.now,
            calendar: calendar
        )
        XCTAssertEqual(stats.dayStreak, 2)
    }

    func testStreakIsZeroWhenTheLastUseWasTooLongAgo() {
        let stats = RewriteStats.from(
            entries: [entry(daysAgo: 2), entry(daysAgo: 3)],
            now: Self.now,
            calendar: calendar
        )
        XCTAssertEqual(stats.dayStreak, 0)
    }

    func testSeveralRewritesInOneDayAreOneDayOfStreak() {
        let stats = RewriteStats.from(
            entries: [entry(daysAgo: 0), entry(daysAgo: 0), entry(daysAgo: 0)],
            now: Self.now,
            calendar: calendar
        )
        XCTAssertEqual(stats.dayStreak, 1)
        XCTAssertEqual(stats.totalRewrites, 3)
    }

    func testTopAppIgnoresEntriesWithNoHostApp() {
        let stats = RewriteStats.from(
            entries: [
                entry(daysAgo: 0, app: "com.apple.mail"),
                entry(daysAgo: 0, app: "com.apple.mail"),
                entry(daysAgo: 0, app: "com.tinyspeck.slackmacgap"),
                entry(daysAgo: 0, app: nil),
            ],
            now: Self.now,
            calendar: calendar
        )
        XCTAssertEqual(stats.topAppBundleId, "com.apple.mail")
        XCTAssertEqual(stats.topAppCount, 2)
    }
}

final class RewriteHistoryStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func entry(_ text: String) -> RewriteHistoryEntry {
        RewriteHistoryEntry(
            buttonTitle: "敬語",
            promptText: "丁寧に",
            originalText: text,
            rewrittenText: text + "です",
            hostAppBundleId: "com.apple.mail"
        )
    }

    func testRecordsNewestFirstAndSurvivesAReload() async throws {
        let store = RewriteHistoryStore(directory: directory)
        await store.record(entry("1"))
        await store.record(entry("2"))

        let reopened = RewriteHistoryStore(directory: directory)
        let entries = await reopened.entries()
        XCTAssertEqual(entries.map(\.originalText), ["2", "1"])
    }

    /// The cap has to drop the *oldest* rows. Trimming the head would leave a history
    /// list that never changes.
    func testTrimsToCapacityFromTheOldestEnd() async throws {
        let store = RewriteHistoryStore(directory: directory)
        for i in 0...RewriteHistoryStore.capacity {
            await store.record(entry("\(i)"))
        }

        let entries = await store.entries()
        XCTAssertEqual(entries.count, RewriteHistoryStore.capacity)
        XCTAssertEqual(entries.first?.originalText, "\(RewriteHistoryStore.capacity)")
        XCTAssertEqual(entries.last?.originalText, "1")
    }

    func testDisabledHistoryRecordsNothingAndReturnsNoId() async throws {
        let store = RewriteHistoryStore(directory: directory)
        await store.setEnabled(false)

        let id = await store.record(entry("1"))
        let entries = await store.entries()
        XCTAssertNil(id)
        XCTAssertTrue(entries.isEmpty)
    }

    func testTheOffSwitchPersists() async throws {
        let store = RewriteHistoryStore(directory: directory)
        await store.setEnabled(false)

        let reopened = RewriteHistoryStore(directory: directory)
        let enabled = await reopened.isEnabled
        XCTAssertFalse(enabled)
    }

    func testMarkAcceptedFlipsOnlyTheNamedEntry() async throws {
        let store = RewriteHistoryStore(directory: directory)
        await store.record(entry("1"))
        let id = await store.record(entry("2"))

        await store.markAccepted(id: try XCTUnwrap(id))
        let entries = await store.entries()
        XCTAssertEqual(entries.filter(\.accepted).map(\.originalText), ["2"])
    }

    func testClearKeepsTheEnabledFlag() async throws {
        let store = RewriteHistoryStore(directory: directory)
        await store.record(entry("1"))
        await store.clear()

        let entries = await store.entries()
        let enabled = await store.isEnabled
        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(enabled)
    }

    /// The file holds the user's own text, read out of whatever app they were in.
    /// Another account on the same Mac must not be able to page through it.
    func testHistoryFileIsNotWorldReadable() async throws {
        let store = RewriteHistoryStore(directory: directory)
        await store.record(entry("1"))

        let path = directory.appendingPathComponent("history.json").path
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.int16Value, 0o600)
    }
}
