import Foundation

/// The right-click menu's two time-boxed actions — hide the bar, or disable the
/// copy-triggered reply arm (§16) — each for 10 minutes or 1 hour.
///
/// A namespace, not a stored value: `OverlayController` and `ClipboardWatcher` each
/// keep their own `Date?` deadline in `UserDefaults` (so a quit mid-window does not
/// undo it), and ask this for the label and the boundary check. Pure, so the expiry
/// math is the testable part — neither of those two types can be exercised without a
/// window server or a real pasteboard.
public enum OverlaySnooze {
    public enum Duration: CaseIterable, Hashable, Sendable {
        case tenMinutes
        case oneHour

        public var seconds: TimeInterval {
            switch self {
            case .tenMinutes: return 600
            case .oneHour: return 3600
            }
        }

        /// The menu label's duration phrase — "敬語ボタンを**10分間**非表示にする".
        public var label: String {
            switch self {
            case .tenMinutes: return "10分間"
            case .oneHour: return "1時間"
            }
        }
    }

    public static func until(_ duration: Duration, from now: Date = Date()) -> Date {
        now.addingTimeInterval(duration.seconds)
    }

    /// Whether a stored deadline is still in force. No deadline (`nil`) is never active
    /// — that is the "not snoozed" state both callers start from.
    public static func isActive(until deadline: Date?, at now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        return now < deadline
    }

    /// The countdown a menu row shows — "残り8分". Rounded up so the row does not read
    /// "残り0分" while time is still left on the clock; `isActive` is the boolean this
    /// agrees with at the boundary.
    public static func remainingMinutes(until deadline: Date, at now: Date = Date()) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now) / 60)))
    }
}

extension UserDefaults {
    /// The stored form a snooze deadline takes — `TimeIntervalSinceReferenceDate`, with
    /// an absent key read back as `nil` rather than `Date(timeIntervalSinceReferenceDate: 0)`.
    /// `OverlayController.hiddenUntil` and `ClipboardWatcher.copyDisabledUntil` both go
    /// through this rather than each reimplementing the same conversion.
    public func overlaySnoozeDeadline(forKey key: String) -> Date? {
        let stored = double(forKey: key)
        return stored > 0 ? Date(timeIntervalSinceReferenceDate: stored) : nil
    }

    public func setOverlaySnoozeDeadline(_ deadline: Date?, forKey key: String) {
        if let deadline {
            set(deadline.timeIntervalSinceReferenceDate, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
