import DesktopRewriteKit
import Foundation

/// Tries Accessibility, falls back to the clipboard, and remembers which path a
/// target came from so the write goes back the same way.
///
/// `capture` is what §4 calls first on button press, before any UI change and while
/// the user's app is still frontmost.
public actor TextIOCoordinator {

    private let ax: AXTextIO
    private let clipboard: ClipboardTextIO

    /// Reported per rewrite as `io_path` (§7) — how the text was read.
    public private(set) var lastPath: TextIOPath?
    /// How the text was written back. Tracked separately because they genuinely
    /// differ: an AX read followed by a clipboard write is the normal case in Gmail,
    /// and collapsing the two would hide exactly the regression §7 wants to catch.
    public private(set) var lastWritePath: TextIOPath?

    public init(ax: AXTextIO = AXTextIO(), clipboard: ClipboardTextIO) {
        self.ax = ax
        self.clipboard = clipboard
    }

    /// - Parameter frontmostPID: snapshotted by the caller *before* this runs, per
    ///   §4 step 2. It is the write target for the clipboard path, and it must be
    ///   the app that was frontmost at capture time — not whatever is frontmost when
    ///   the rewrite comes back.
    /// - Parameter allowEmpty: accept a readable but blank field. Reply mode only —
    ///   the reply box the user just clicked into is usually empty (§16). The
    ///   clipboard fallback ignores it: ⌘C over an empty field copies nothing, so
    ///   there is no blank target for it to produce.
    public func capture(frontmostPID: pid_t?, allowEmpty: Bool = false) async throws -> TextTarget {
        guard AXPermission.isTrusted else { throw TextIOError.notTrusted }

        do {
            let target = try await ax.capture(frontmostPID: frontmostPID, allowEmpty: allowEmpty)
            lastPath = .ax
            return target
        } catch TextIOError.notTrusted {
            // Not a path problem — nothing downstream can work either.
            throw TextIOError.notTrusted
        } catch {
            let bundleId = frontmostPID.flatMap { BundleIdentity.bundleIdentifier(for: $0) }
            let target = try await clipboard.capture(hostAppBundleId: bundleId)
            lastPath = .clipboard
            return target
        }
    }

    /// Writes the rewrite back, escalating from AX to a synthesized paste.
    ///
    /// The earlier version refused to fall back, reasoning that a stale element made
    /// ⌘V dangerous because it could paste into the wrong place. That was wrong in
    /// the case that actually matters: **AX writes fail silently in most browser and
    /// Electron inputs**, so refusing to escalate meant Gmail and friends just never
    /// worked. The real guard is not "never paste" — it is "only paste into the app
    /// we captured from", which is what `pid` gives us.
    ///
    /// - Parameter frontmostPID: the app that was frontmost at capture time. Required
    ///   for any paste; without it there is no way to know where ⌘V would land.
    public func write(_ replacement: String, to target: TextTarget, frontmostPID: pid_t?) async throws {
        if target.writeStrategy == .ax {
            do {
                try await ax.write(replacement, to: target)
                lastWritePath = .ax
                return
            } catch TextIOError.notTrusted {
                throw TextIOError.notTrusted
            } catch {
                // Fall through. `AXTextIO.write` verifies the field actually changed,
                // so reaching here means the text is genuinely not in place.
            }
        }

        guard let frontmostPID else { throw TextIOError.writeFailed }
        try await clipboard.write(
            replacement,
            toFrontmost: frontmostPID,
            mode: target.captureMode
        )
        lastWritePath = .clipboard
    }
}
