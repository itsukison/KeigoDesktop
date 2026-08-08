import Foundation

/// The four numbers the ホーム page shows, plus the most-used host app.
///
/// **There is deliberately no "time saved".** Willow's equivalent is dictated words
/// divided by typing speed — arithmetic on two things it actually measures. A rewrite
/// tool has no such ground truth: any figure would need an invented "how long would
/// you have spent editing this" coefficient. Everything here is counted, not modelled.
public struct RewriteStats: Equatable, Sendable {
    public let totalRewrites: Int
    public let rewritesThisWeek: Int
    public let charactersRewritten: Int
    public let dayStreak: Int
    public let topAppBundleId: String?
    public let topAppCount: Int

    public static let empty = RewriteStats(
        totalRewrites: 0,
        rewritesThisWeek: 0,
        charactersRewritten: 0,
        dayStreak: 0,
        topAppBundleId: nil,
        topAppCount: 0
    )

    public init(
        totalRewrites: Int,
        rewritesThisWeek: Int,
        charactersRewritten: Int,
        dayStreak: Int,
        topAppBundleId: String?,
        topAppCount: Int
    ) {
        self.totalRewrites = totalRewrites
        self.rewritesThisWeek = rewritesThisWeek
        self.charactersRewritten = charactersRewritten
        self.dayStreak = dayStreak
        self.topAppBundleId = topAppBundleId
        self.topAppCount = topAppCount
    }

    /// Pure, so the streak edge cases are testable without a file on disk.
    public static func from(
        entries: [RewriteHistoryEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RewriteStats {
        guard !entries.isEmpty else { return .empty }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        let thisWeek = weekStart.map { start in
            entries.filter { $0.createdAt >= start && $0.createdAt <= now }.count
        } ?? 0

        var counts: [String: Int] = [:]
        for entry in entries {
            guard let bundleId = entry.hostAppBundleId else { continue }
            counts[bundleId, default: 0] += 1
        }
        // Ties break on the bundle id so the caption does not flicker between two
        // equally-used apps every time the list is recomputed.
        let top = counts.max { ($0.value, $1.key) < ($1.value, $0.key) }

        return RewriteStats(
            totalRewrites: entries.count,
            rewritesThisWeek: thisWeek,
            charactersRewritten: entries.reduce(0) { $0 + $1.originalText.count },
            dayStreak: streak(entries: entries, now: now, calendar: calendar),
            topAppBundleId: top?.key,
            topAppCount: top?.value ?? 0
        )
    }

    /// Consecutive days with at least one rewrite, counting back from today.
    ///
    /// A day with no rewrites *yet* must not break the streak — the count is anchored
    /// to yesterday when today is still empty, so opening the app at 9 a.m. does not
    /// report a streak of 0 for work that is about to happen.
    private static func streak(
        entries: [RewriteHistoryEntry],
        now: Date,
        calendar: Calendar
    ) -> Int {
        let days = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
