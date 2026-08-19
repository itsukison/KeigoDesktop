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
    /// - Parameter allowEmpty: accept a readable but blank field. The reply box the
    ///   user just clicked into is usually empty (§16), and so is the compose box they
    ///   press ✎ in to write something from nothing (§18). The clipboard fallback
    ///   ignores it: ⌘C over an empty field copies nothing, so there is no blank target
    ///   for it to produce.
    /// - Parameter allowScratch: when nothing at all is focused, return an empty target
    ///   with no destination rather than throwing (§18). This is what turns "no input
    ///   box detected" from a dead end into writing a message from scratch, and it is
    ///   the *last* resort — AX and then the clipboard are both tried first, because a
    ///   selection the user made is a better answer than an empty page.
    public func capture(
        frontmostPID: pid_t?,
        allowEmpty: Bool = false,
        allowScratch: Bool = false
    ) async throws -> TextTarget {
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
            do {
                let target = try await clipboard.capture(hostAppBundleId: bundleId)
                lastPath = .clipboard
                return target
            } catch {
                guard allowScratch else { throw error }
                lastPath = .ax
                return TextTarget.scratch(hostAppBundleId: bundleId)
            }
        }
    }

    /// Reply mode has different source semantics from rewrite mode: a selection that
    /// equals the copied message is the other person's message, while a selection
    /// inside a reply field is only part of the user's draft. AX owns that distinction;
    /// the clipboard fallback is intentionally skipped because it can only copy the
    /// already-known source message again.
    public func captureReply(frontmostPID: pid_t?, copiedMessage: String) async throws -> TextTarget {
        let target = try await ax.captureReply(
            frontmostPID: frontmostPID,
            copiedMessage: copiedMessage
        )
        lastPath = .ax
        return target
    }

    /// Where the user's keyboard is, when that can honestly be asked (§18).
    ///
    /// Kept separate from `resolveDestination` because the two have different *validity
    /// windows*: this one is only truthful while none of our own windows holds key, and
    /// the caller is the only thing that knows when that is. See `AXTextIO.UserFocus`.
    public func readUserFocus(frontmostPID: pid_t?) async -> AXTextIO.UserFocusReading {
        await ax.readUserFocus(frontmostPID: frontmostPID)
    }

    /// Where an Insert would land right now — asked while the result panel is on screen
    /// and again the moment the button is pressed (§18).
    ///
    /// Read-only and keystroke-free by construction: it goes straight to `AXTextIO` and
    /// never touches `clipboard`, because this runs on a timer.
    ///
    /// - Parameter userFocus: the remembered reading from `readUserFocus`. Passed in
    ///   rather than read here: by the time this is called the result panel is key, and
    ///   a live read would answer about us.
    public func resolveDestination(
        for target: TextTarget,
        capturedPID: pid_t?,
        userFocus: AXTextIO.UserFocus?
    ) async -> (verdict: DestinationVerdict, redirect: TextTarget?) {
        await ax.resolveDestination(
            for: target,
            capturedPID: capturedPID,
            userFocus: userFocus
        )
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
        // A scratch compose has nowhere to go and the caller is expected to have offered
        // Copy instead (§18). Reaching here would mean synthesizing ⌘A into whatever
        // happens to be focused, which is the one thing `.none` exists to prevent.
        guard target.hasDestination else { throw TextIOError.noDestination }

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
        // Read before, so the paste can be checked afterwards. Nil either way for a
        // target with no element, which is the case this cannot verify at all.
        let before = await ax.currentValue(of: target)
        try await clipboard.write(
            replacement,
            toFrontmost: frontmostPID,
            mode: target.captureMode
        )

        // The keystroke is posted, not acknowledged, so "sent" is not "landed". Settle,
        // then look — and treat unreadable as landed (`pasteLanded`).
        try? await Task.sleep(nanoseconds: Self.pasteVerifyNanos)
        guard await ax.pasteLanded(replacement, in: target, before: before) else {
            throw TextIOError.writeFailed
        }
        lastWritePath = .clipboard
    }

    /// Time for the target app to apply the paste before its value is re-read. Longer
    /// than `selectAllSettleNanos` because a web view can take a beat to reflect it, and
    /// a read that is too early reports a failure that did not happen.
    static let pasteVerifyNanos: UInt64 = 150_000_000
}
