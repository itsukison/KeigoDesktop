import ApplicationServices
import Foundation

/// §5: the app is useless without Accessibility, so onboarding gates on this and
/// every activation re-checks it.
///
/// The permission is keyed to the binary's code signature, so it is revoked
/// whenever the binary changes identity — which is every unsigned dev rebuild.
/// Expect to re-grant constantly while developing; that is the OS working, not a bug.
public enum AXPermission {

    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt. Returns the state *before* the user answers — the
    /// dialog is asynchronous and there is no completion callback, which is why
    /// callers poll rather than await.
    @discardableResult
    public static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
