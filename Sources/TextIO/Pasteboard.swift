import CoreGraphics
import Foundation

/// The two AppKit-shaped capabilities the clipboard fallback needs, behind
/// protocols so `Sources/` stays AppKit-free (§3) — and so the fallback's
/// *ordering*, which is the part that actually breaks, can be tested with fakes.
public protocol PasteboardBridge: Sendable {
    func readString() -> String?
    func write(_ string: String)
    func clear()
}

public protocol AppActivator: Sendable {
    /// Brings the captured frontmost app back to the front. Returns false when the
    /// app is gone, in which case there is nowhere to paste and the write must fail
    /// rather than dumping the rewrite into whatever is frontmost now.
    func activate(pid: pid_t) -> Bool
}

/// The keystrokes the clipboard path synthesizes.
///
/// Behind a protocol like the pasteboard, because the *sequence* is what broke: a
/// missing ⌘A before ⌘V is why whole-field rewrites appended instead of replacing.
/// That is only testable if it can be recorded.
public protocol KeystrokeSending: Sendable {
    func sendCommandC()
    func sendCommandV()
    /// Needed before pasting over a `.wholeInput` target: ⌘V replaces the *selection*,
    /// so with nothing selected it inserts at the caret instead of replacing.
    func sendCommandA()
}

/// `CGEvent` rather than AppleScript, per §5: no Automation permission prompt, and
/// materially lower latency than spawning `osascript` (which is what `prompt/` did).
public struct KeystrokeSynthesizer: KeystrokeSending {
    private enum KeyCode: CGKeyCode {
        case a = 0
        case c = 8
        case v = 9
    }

    public init() {}

    public func sendCommandC() { send(.c) }
    public func sendCommandV() { send(.v) }
    public func sendCommandA() { send(.a) }

    private func send(_ key: KeyCode) {
        // A private state gets us a clean modifier slate: if the user is still
        // holding a modifier from their last action, the combined flags would turn
        // ⌘C into something else entirely.
        let source = CGEventSource(stateID: .privateState)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
