import AppKit
import DesktopRewriteKit

/// Watches for a ⌘C and hands the copied message to the overlay (§16).
///
/// **Polling, and there is no alternative.** `NSPasteboard` posts no notification of
/// any kind; `changeCount` is the only witness there has ever been, and every app on
/// macOS that reacts to a copy samples it. 0.5 s is the interval the bar's own
/// position tracker already runs at, and it is far inside the time it takes to switch
/// apps and reach the bar.
///
/// §16 records why the trigger is ⌘C and not a selection: selected text already means
/// "the thing to rewrite" (`AXTextIO.target(for:)`), so arming on it would give the
/// bar two contradictory readings of the same gesture.
@MainActor
final class ClipboardWatcher {

    /// On by default, because a feature nobody discovers is not shipped. It reads the
    /// clipboard to do that, which is why there is a switch at all — the same reasoning
    /// as 履歴を保存する (§14).
    private static let enabledKey = "reply.clipboardWatchEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// The right-click menu's "コピー機能を無効にする" — a temporary override on top of
    /// `isEnabled`, not a replacement for it. Stored as an absolute deadline rather than
    /// driven by a `Task.sleep`: 10 minutes or 1 hour is long enough to span the Mac
    /// sleeping, and a suspend-clock timer is not guaranteed to keep counting through
    /// that, while a stored `Date` compared against `Date()` on the next poll always
    /// reads correctly regardless of what happened in between. Persisted, so quitting
    /// mid-window does not undo it.
    private static let copyDisabledUntilKey = "reply.clipboardWatchDisabledUntil"

    static var copyDisabledUntil: Date? {
        get { UserDefaults.standard.overlaySnoozeDeadline(forKey: copyDisabledUntilKey) }
        set { UserDefaults.standard.setOverlaySnoozeDeadline(newValue, forKey: copyDisabledUntilKey) }
    }

    /// Self-clearing: there is no separate timer for this window, only this check on
    /// every 0.5 s poll `poll()` already runs. Once the deadline has passed, the stored
    /// value is cleared right here rather than left for the next `disableCopyTrigger`
    /// call to overwrite.
    private static var isCopyTemporarilyDisabled: Bool {
        guard let until = copyDisabledUntil else { return false }
        guard OverlaySnooze.isActive(until: until) else {
            copyDisabledUntil = nil
            return false
        }
        return true
    }

    // MARK: - Our own writes

    /// **The app's own pasteboard traffic is indistinguishable from a ⌘C.** It clears
    /// and restores the clipboard on every fallback capture, writes the rewrite before
    /// every synthesized ⌘V, and writes on 結果 copy and on the insert-failure recovery.
    /// Untracked, the last of those would arm reply mode with the rewrite the user just
    /// produced.
    ///
    /// Static rather than per-instance because there is one pasteboard and one watcher,
    /// and `MainModel.copy` writes to it from the other side of the app.
    private static var suspensionDepth = 0
    /// The `changeCount` our own last bracketed operation left behind. Needed on top of
    /// the depth: `copyToClipboard` suspends, writes and resumes synchronously, so no
    /// poll ever observes a non-zero depth and the bump would surface a tick later
    /// looking exactly like a user copy.
    private static var lastSelfChangeCount = -1

    static func suspend() {
        suspensionDepth += 1
    }

    static func resume() {
        suspensionDepth = max(0, suspensionDepth - 1)
        lastSelfChangeCount = NSPasteboard.general.changeCount
    }

    /// For the synchronous writes — `copyToClipboard`, the insert-failure recovery,
    /// the ホーム list's copy button.
    static func writingOurselves(_ body: () -> Void) {
        suspend()
        body()
        resume()
    }

    // MARK: - Polling

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let onCopy: (ReplySource) -> Void

    init(onCopy: @escaping (ReplySource) -> Void) {
        self.onCopy = onCopy
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        // Absorbed even when the change turns out to be ours, so a bump that happens
        // mid-suspension is not re-examined once the suspension lifts.
        lastChangeCount = count

        guard Self.suspensionDepth == 0, count != Self.lastSelfChangeCount else { return }
        guard Self.isEnabled, !Self.isCopyTemporarilyDisabled else { return }
        guard let string = pasteboard.string(forType: .string),
              let source = ReplySource(copied: string)
        else { return }

        onCopy(source)
    }
}
