import Foundation
import DesktopRewriteKit

/// Which path produced or consumed a target. Reported as the `io_path` analytics
/// property (§7) — a rising `clipboard` rate for one bundle id is the earliest
/// signal that an app's AX tree changed.
public enum TextIOPath: String, Sendable {
    case ax
    case clipboard
}

/// How the rewrite gets written back.
///
/// **Reading and writing are decided separately, and that is the whole point.**
/// Gmail, Slack and most browser/Electron inputs let AX *read* `kAXValue` fine but
/// report `kAXSelectedText` as not settable — or accept the set and silently do
/// nothing. Gating capture on writability threw those away and fell back to
/// clipboard capture, which cannot serve `.wholeInput` at all (⌘C with no selection
/// copies nothing). So: read via AX wherever possible, write via whatever actually
/// works. That combination is what makes "rewrite the field I'm in" work in Gmail.
public enum TextWriteStrategy: String, Sendable {
    /// `AXUIElementSetAttributeValue` on `kAXSelectedText`. Preserves the app's undo
    /// stack and does not need the app frontmost.
    case ax
    /// Pasteboard + synthesized ⌘V, preceded by ⌘A when the whole field is the
    /// target. This is the only path `prompt/` ever used, and it works everywhere.
    case clipboard
    /// **There is nowhere to write.** Nothing was focused when this was captured, so
    /// the rewrite can only ever be copied — and no ⌘A or ⌘V may be synthesized for
    /// it. §16's rule that a nil `kAXValue` is the only thing keeping ⌘A out of the
    /// Finder used to be enforced by refusing to capture at all; a scratch compose
    /// captures instead, and this case is what enforces it now.
    case none
}

/// What the rewrite is actually operating on, which is the thing the user has to be
/// told before they type an instruction. It is derived, never stored: a user who reads
/// 「どう書き換えますか？」 over an empty compose box has been told there is text to
/// rewrite, types 「もっと丁寧に」, and gets a rewrite of nothing.
///
/// Deliberately *not* a new `CaptureMode` case. That type is a copied contract shared
/// with the iOS repo (§3) and the backend validates its three values, so a fourth would
/// be a three-place change to say something only the desktop UI needs to know.
public enum RewriteScope: String, Sendable {
    /// The user's selection is the source text.
    case selection
    /// The whole focused field is the source text.
    case inputField
    /// There is no source text — the instruction is all there is. Either the focused
    /// field is empty (and can still be written back into) or nothing was focused at
    /// all (and the result can only be copied). `hasDestination` is what separates
    /// those two, and they are one scope because the *instruction* is the same job.
    case scratch
}

/// A captured rewrite target. Produced while the user's app is still frontmost and
/// before any of our windows can take key (§4), then held until the rewrite comes
/// back and is written into the same place.
public struct TextTarget: Sendable {
    /// The text to rewrite.
    public let text: String
    public let captureMode: CaptureMode
    /// How the text was *read*. Reported as `io_path`.
    public let path: TextIOPath
    /// How it should be written *back* — decided independently of `path`.
    public let writeStrategy: TextWriteStrategy

    /// Host text around a selection, for rewrite quality only. Never persisted.
    public let contextBefore: String?
    public let contextAfter: String?

    public let hostAppBundleId: String?
    /// Best-effort, and only when the host app is a browser.
    public let browserURL: String?

    /// The AX handle to write back into. Nil on the clipboard path, where the
    /// write goes through pasteboard + synthesized ⌘V instead.
    public let element: AXElementHandle?

    /// An element that must not be offered as a live redirect destination.
    ///
    /// Reply capture sets this when the focused selection is the copied incoming
    /// message itself. That selection is useful as context but is never a place the
    /// composed reply may replace. Keeping the exclusion beside the target lets the
    /// result panel accept a later click into a real reply field without ever
    /// rediscovering the source selection as 「ここに挿入」.
    public let excludedRedirectElement: AXElementHandle?

    /// The selected range at capture time. `.wholeInput` writes need to restore a
    /// select-all before setting text; a selection write replaces in place.
    public let selectedRange: CFRange?

    public init(
        text: String,
        captureMode: CaptureMode,
        path: TextIOPath,
        writeStrategy: TextWriteStrategy,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        hostAppBundleId: String? = nil,
        browserURL: String? = nil,
        element: AXElementHandle? = nil,
        excludedRedirectElement: AXElementHandle? = nil,
        selectedRange: CFRange? = nil
    ) {
        self.text = text
        self.captureMode = captureMode
        self.path = path
        self.writeStrategy = writeStrategy
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.hostAppBundleId = hostAppBundleId
        self.browserURL = browserURL
        self.element = element
        self.excludedRedirectElement = excludedRedirectElement
        self.selectedRange = selectedRange
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// See `RewriteScope`. Derived from what was captured rather than recorded at
    /// capture time, so it cannot drift out of step with `text`.
    public var scope: RewriteScope {
        if isEmpty { return .scratch }
        return captureMode == .selection ? .selection : .inputField
    }

    /// Whether there is anywhere to write the result back to. False means Insert is
    /// not an action we can offer, and the result panel says so before it is pressed.
    public var hasDestination: Bool { writeStrategy != .none }

    /// Nothing was focused: no field to read, and none to write into. The rewrite is
    /// whatever the user asks for and it comes back to the clipboard.
    static func scratch(
        hostAppBundleId: String?,
        excluding excludedRedirectElement: AXElementHandle? = nil
    ) -> TextTarget {
        TextTarget(
            text: "",
            // `.wholeInput` because `CaptureMode` has no fourth value (see
            // `RewriteScope`) and an empty selection would send `selection: true` to a
            // backend that would then look for a fragment. The ⌘A that `.wholeInput`
            // normally implies cannot fire: `writeStrategy` is `.none`.
            captureMode: .wholeInput,
            path: .ax,
            writeStrategy: .none,
            hostAppBundleId: hostAppBundleId,
            excludedRedirectElement: excludedRedirectElement
        )
    }

    /// The destination re-resolved at Insert time — the field the user is in *now*,
    /// when the one they started from is gone (§18).
    ///
    /// Always `.selection`: the text goes in at the caret, replacing whatever is
    /// selected. A re-resolved `.wholeInput` would send ⌘A to a field this rewrite was
    /// never read from and replace someone else's draft with it.
    ///
    /// **No `selectedRange`, deliberately.** `AXTextIO.performWrite` re-asserts a range
    /// when it has one, and a range read a moment ago from a field the user is actively
    /// typing in can only place the text worse than the app's own live caret does.
    static func redirect(
        element: AXElementHandle,
        writeStrategy: TextWriteStrategy,
        hostAppBundleId: String?
    ) -> TextTarget {
        TextTarget(
            text: "",
            captureMode: .selection,
            path: .ax,
            writeStrategy: writeStrategy,
            hostAppBundleId: hostAppBundleId,
            element: element
        )
    }
}

public enum TextIOError: Error, Equatable, Sendable {
    /// The user has not granted Accessibility. The app is useless without it.
    case notTrusted
    /// No focused element, or one that exposes neither value nor selection.
    case noTarget
    /// The focused element is read-only, so a rewrite could never be written back.
    case notEditable
    /// There is nowhere to write this — a scratch compose, or a destination that went
    /// away. Copy is the answer, and §18's Insert button says so before it is pressed.
    case noDestination
    /// AX reported success but the field did not actually change.
    case writeFailed
    case timedOut
}
