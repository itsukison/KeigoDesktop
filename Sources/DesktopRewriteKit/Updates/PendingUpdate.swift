import Foundation

/// What the app remembers about an update Sparkle has already found.
///
/// **Why this exists at all.** Sparkle's scheduled check is deliberately silent here
/// (`AppDelegate` claims `supportsGentleScheduledUpdateReminders`), so the app owns the
/// announcement. The first version of that announcement lived only in `MainModel` as an
/// in-memory `@Published` string rendered by one card inside the main window — a window
/// an `LSUIElement` app gives nobody a reason to open. Discovery therefore produced
/// nothing observable, and quitting the app erased even the possibility of seeing it,
/// because the next scheduled check is `SUScheduledCheckInterval` (a day) away.
///
/// Persisting the find is what makes the announcement survive that. Pure and
/// `UserDefaults`-backed for the same reason `OverlaySnooze` is: the surfaces that show
/// it — an `NSPanel` above the bar, a status-menu row, a SwiftUI card — cannot be
/// exercised without a window server, so the decisions live here where a test can reach
/// them.
public enum PendingUpdate {

    /// The version Sparkle last found, as its **display** version (`0.1.3`), which is
    /// what every surface shows. Deliberately not `sparkle:version`: that is a build
    /// number the user never sees, and comparing it against `CFBundleShortVersionString`
    /// on relaunch would be comparing two different numbering schemes.
    static let versionKey = "updates.pendingVersion"

    /// The version whose *toast* the user waved away. The card and the menu row stay —
    /// dismissing a reminder is not the same as refusing the update, and a user who
    /// closes the toast should still be able to find the update where they'd look for
    /// it. Sparkle owns the real "skip this version" decision.
    static let dismissedKey = "updates.dismissedVersion"

    /// Whether `candidate` is worth announcing to someone running `installed`.
    ///
    /// The load-bearing case is **the launch after a successful update**: the stored
    /// version is now the running version, and without this the app would announce an
    /// update to itself forever. Equal is not newer, so that resolves to `false` and the
    /// record is cleared.
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compare(candidate, installed) == .orderedDescending
    }

    /// Dot-separated integer components, compared numerically and left to right, with a
    /// missing component read as 0 so `0.2` and `0.2.0` are the same version.
    ///
    /// Numeric rather than `String.compare(options: .numeric)` because that treats the
    /// whole string as one number-and-text sequence; this only ever has to understand
    /// the `CFBundleShortVersionString` this project actually ships. Anything
    /// non-numeric in a component reads as 0 rather than throwing — an unparseable
    /// version should fail to nag, not crash the launch path.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}

/// The stored half of `PendingUpdate`, kept as a type so a test can hand it a throwaway
/// `UserDefaults` suite instead of writing into the real domain.
public struct PendingUpdateStore {

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Sparkle found `version`. Recording a version the user had already dismissed
    /// clears that dismissal — this is a *new* find of the same version only if the
    /// record was cleared, and a re-find after an install is handled by `pending(for:)`.
    public func record(_ version: String) {
        if defaults.string(forKey: PendingUpdate.dismissedKey) != version {
            defaults.removeObject(forKey: PendingUpdate.dismissedKey)
        }
        defaults.set(version, forKey: PendingUpdate.versionKey)
    }

    /// The version to announce to someone running `installedVersion`, or `nil`.
    ///
    /// **Self-clearing.** A stored version that is not newer than the running app has
    /// been installed (or the user moved to a newer build some other way), so the record
    /// is removed here rather than left for a separate cleanup pass that could be
    /// forgotten. That makes this safe to call on every launch.
    public func pending(for installedVersion: String) -> String? {
        guard let stored = defaults.string(forKey: PendingUpdate.versionKey),
              !stored.isEmpty else { return nil }
        guard PendingUpdate.isNewer(stored, than: installedVersion) else {
            clear()
            return nil
        }
        return stored
    }

    /// Whether the toast for `version` has been waved away. The card and the menu row
    /// ignore this: see `PendingUpdate.dismissedKey`.
    public func isNoticeDismissed(_ version: String) -> Bool {
        defaults.string(forKey: PendingUpdate.dismissedKey) == version
    }

    public func dismissNotice(for version: String) {
        defaults.set(version, forKey: PendingUpdate.dismissedKey)
    }

    public func clear() {
        defaults.removeObject(forKey: PendingUpdate.versionKey)
        defaults.removeObject(forKey: PendingUpdate.dismissedKey)
    }
}
