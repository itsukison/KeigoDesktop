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
        self.selectedRange = selectedRange
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum TextIOError: Error, Equatable, Sendable {
    /// The user has not granted Accessibility. The app is useless without it.
    case notTrusted
    /// No focused element, or one that exposes neither value nor selection.
    case noTarget
    /// The focused element is read-only, so a rewrite could never be written back.
    case notEditable
    /// AX reported success but the field did not actually change.
    case writeFailed
    case timedOut
}
