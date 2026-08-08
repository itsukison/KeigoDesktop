import DesktopRewriteKit
import Foundation

/// The documented fallback for apps whose AX tree we cannot read (§5).
///
/// Ported from `prompt/src/services/focus-service.js`, which already handles the
/// sharp edges — clear before copy so a failed ⌘C reads as empty rather than
/// returning the previous clipboard, and always restore what the user had.
///
/// Two things it cannot do, which is why AX is first:
///   - Serve `.wholeInput`. ⌘C with nothing selected copies nothing, so this path
///     only ever produces `.selection`.
///   - Write without stealing focus. The paste needs the target app frontmost.
public struct ClipboardTextIO: Sendable {

    /// Time for the target app to service the synthesized ⌘C and put text on the
    /// pasteboard. 100 ms is `focus-service.js`'s value, kept as-is.
    static let copySettleNanos: UInt64 = 100_000_000
    /// Longer, because reactivating an app has to finish before the ⌘V lands.
    /// `prompt/`'s `FOCUS_RESTORE_DELAY`, kept as-is.
    static let activateSettleNanos: UInt64 = 200_000_000
    /// Between ⌘A and ⌘V.
    static let selectAllSettleNanos: UInt64 = 60_000_000

    private let pasteboard: PasteboardBridge
    private let activator: AppActivator
    private let keystrokes: KeystrokeSending
    private let sleeper: @Sendable (UInt64) async -> Void

    public init(
        pasteboard: PasteboardBridge,
        activator: AppActivator,
        keystrokes: KeystrokeSending = KeystrokeSynthesizer(),
        sleeper: @escaping @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    ) {
        self.pasteboard = pasteboard
        self.activator = activator
        self.keystrokes = keystrokes
        self.sleeper = sleeper
    }

    // MARK: - Read

    public func capture(hostAppBundleId: String?) async throws -> TextTarget {
        let original = pasteboard.readString()
        pasteboard.clear()

        keystrokes.sendCommandC()
        await sleeper(Self.copySettleNanos)

        let copied = pasteboard.readString()
        // Restore before deciding anything: an early return must not leave the
        // user's clipboard emptied.
        if let original { pasteboard.write(original) } else { pasteboard.clear() }

        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextIOError.noTarget
        }

        return TextTarget(
            text: copied,
            captureMode: .selection,
            path: .clipboard,
            // Nothing was readable via AX, so there is no element to write through.
            writeStrategy: .clipboard,
            hostAppBundleId: hostAppBundleId,
            element: nil,
            selectedRange: nil
        )
    }

    // MARK: - Write

    /// Mirrors `prompt/`'s `insert-text` handler, which is the only write path that
    /// app ever used and works everywhere: clipboard → activate the captured app →
    /// settle → paste.
    ///
    /// - Parameter mode: `.wholeInput` needs a ⌘A first. **This was the bug behind
    ///   "insertion only worked in Notes":** ⌘V replaces the current *selection*, so
    ///   against a whole-field target with nothing selected it inserted at the caret
    ///   and the user got their text twice instead of rewritten.
    public func write(
        _ replacement: String,
        toFrontmost pid: pid_t,
        mode: CaptureMode
    ) async throws {
        let original = pasteboard.readString()
        pasteboard.write(replacement)

        guard activator.activate(pid: pid) else {
            if let original { pasteboard.write(original) }
            throw TextIOError.writeFailed
        }
        await sleeper(Self.activateSettleNanos)

        if mode != .selection {
            keystrokes.sendCommandA()
            // The app needs a beat to apply the selection before ⌘V lands, or the
            // paste races it and inserts instead of replacing.
            await sleeper(Self.selectAllSettleNanos)
        }

        keystrokes.sendCommandV()

        // Give the paste time to consume the pasteboard before restoring. Without
        // this the app can read the *restored* contents and paste the wrong thing.
        await sleeper(Self.copySettleNanos)
        if let original { pasteboard.write(original) }
    }
}
