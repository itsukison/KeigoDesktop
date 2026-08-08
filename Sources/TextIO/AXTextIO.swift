import ApplicationServices
import DesktopRewriteKit
import Foundation

/// Accessibility read/write — the primary path (§5).
///
/// AX is tried before the clipboard because it is the only path that can serve the
/// `.wholeInput` case: rewriting the field the user is in *without* making them
/// select anything first. A hover pill whose buttons only work after a manual
/// selection is a worse product, so the harder path is the default one.
///
/// Every call runs on `queue`. AX is synchronous cross-process IPC, and §5 forbids
/// touching it from the main thread.
public actor AXTextIO {

    /// Slice of surrounding text sent with a selection, per side. Enough for the
    /// model to make the fragment fit; short enough not to ship the document.
    private static let contextWindow = 600

    /// Electron/Chromium apps do not populate their AX tree until this is set on
    /// the *application* element. Without it Slack, VS Code and Discord look like
    /// they have no focused element at all. Set lazily, once per pid.
    private var manualAccessibilityGranted: Set<pid_t> = []

    private let systemWide: AXUIElement

    public init() {
        systemWide = AXUIElementCreateSystemWide()
        systemWide.applyMessagingTimeout()
    }

    // MARK: - Read

    /// - Parameter frontmostPID: the app to prime before reading. **Required for
    ///   Chromium and Electron apps.**
    ///
    ///   Those apps expose *no focused element at all* until `AXManualAccessibility`
    ///   is set on their application element — verified live against Chrome and
    ///   Windsurf, both of which returned nil. An earlier version derived the pid from
    ///   the focused element and so bailed out with `.noTarget` before it ever got to
    ///   set the flag, meaning the workaround could never fire for the one case it
    ///   exists for. Priming has to come first, off the frontmost app.
    /// - Parameter allowEmpty: accept a field that is readable but blank. Only reply
    ///   mode (§16) sets this — see `target(for:pid:allowEmpty:)`.
    public func capture(frontmostPID: pid_t?, allowEmpty: Bool = false) throws -> TextTarget {
        guard AXPermission.isTrusted else { throw TextIOError.notTrusted }

        if let frontmostPID {
            primeManualAccessibility(pid: frontmostPID)
        }

        guard let focused = systemWide.elementAttribute(kAXFocusedUIElementAttribute) else {
            throw TextIOError.noTarget
        }
        focused.applyMessagingTimeout()

        // The focused element can belong to a different process than the frontmost app
        // (a helper or web-content process), so prime that one too and re-read once.
        let pid = focused.processIdentifier
        if pid != frontmostPID, primeManualAccessibility(pid: pid),
           let refreshed = systemWide.elementAttribute(kAXFocusedUIElementAttribute) {
            refreshed.applyMessagingTimeout()
            return try target(for: refreshed, pid: refreshed.processIdentifier, allowEmpty: allowEmpty)
        }

        return try target(for: focused, pid: pid, allowEmpty: allowEmpty)
    }

    private func target(for element: AXUIElement, pid: pid_t, allowEmpty: Bool) throws -> TextTarget {
        let handle = AXElementHandle(element: element, pid: pid)
        let wholeValue = element.stringAttribute(kAXValueAttribute)
        let selected = element.stringAttribute(kAXSelectedTextAttribute)
        let range = element.rangeAttribute(kAXSelectedTextRangeAttribute)
        let bundleId = BundleIdentity.bundleIdentifier(for: pid)
        let browserURL = browserURL(from: element)

        // Writability decides the *write* strategy only — never whether we captured.
        // Gmail's compose box reads perfectly and reports kAXSelectedText unsettable;
        // gating capture on this threw the read away and left the clipboard, which
        // cannot serve `.wholeInput` at all.
        let strategy: TextWriteStrategy = element.isSettable ? .ax : .clipboard

        // A non-empty selection means the user told us what to operate on.
        if let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let (before, after) = Self.context(around: range, in: wholeValue)
            return TextTarget(
                text: selected,
                captureMode: .selection,
                path: .ax,
                writeStrategy: strategy,
                contextBefore: before,
                contextAfter: after,
                hostAppBundleId: bundleId,
                browserURL: browserURL,
                element: handle,
                selectedRange: range
            )
        }

        // Empty selection but a readable field: the whole field is the target.
        // This is the case the clipboard cannot capture.
        if let wholeValue, !wholeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TextTarget(
                text: wholeValue,
                captureMode: .wholeInput,
                path: .ax,
                writeStrategy: strategy,
                hostAppBundleId: bundleId,
                browserURL: browserURL,
                element: handle,
                selectedRange: range
            )
        }

        // Reply mode targets a field the user has not typed into yet, so a *blank*
        // field has to count. "Copy a message, click into the empty reply box, hover"
        // is the central reply flow (§16), not an edge case, and the check above
        // rejects it — which is why this is a parameter rather than the default.
        //
        // A **nil** `kAXValue` still throws: that is what says this is not a text
        // field at all, and it is the only thing keeping ⌘A + ⌘V out of the Finder.
        if allowEmpty, let wholeValue {
            return TextTarget(
                text: wholeValue,
                captureMode: .wholeInput,
                path: .ax,
                writeStrategy: strategy,
                hostAppBundleId: bundleId,
                browserURL: browserURL,
                element: handle,
                selectedRange: range
            )
        }

        throw TextIOError.noTarget
    }

    /// Slices `contextWindow` characters either side of the selection out of the
    /// full field value. Works in UTF-16 because that is the unit `CFRange` uses;
    /// converting to `String.Index` on a range we did not compute ourselves is how
    /// emoji and kanji get cut in half.
    static func context(around range: CFRange?, in whole: String?) -> (String?, String?) {
        guard let range, let whole, range.location >= 0 else { return (nil, nil) }
        let units = Array(whole.utf16)
        guard range.location <= units.count else { return (nil, nil) }

        let selectionEnd = min(units.count, range.location + max(0, range.length))
        let beforeStart = max(0, range.location - contextWindow)
        let afterEnd = min(units.count, selectionEnd + contextWindow)

        let before = String(decoding: units[beforeStart..<range.location], as: UTF16.self)
        let after = String(decoding: units[selectionEnd..<afterEnd], as: UTF16.self)
        return (before.isEmpty ? nil : before, after.isEmpty ? nil : after)
    }

    // MARK: - Write

    /// `kAXSelectedText` replaces the selected range in place. It preserves the
    /// app's own undo stack and — unlike synthesized paste — does not require the
    /// target app to be frontmost.
    ///
    /// **Verifies the write actually landed.** `AXUIElementSetAttributeValue` returns
    /// `.success` and does nothing in plenty of web and Electron views, which surfaced
    /// as "the rewrite said it worked and the text never changed". Throwing here is
    /// what lets the coordinator fall back to a synthesized paste.
    public func write(_ replacement: String, to target: TextTarget) throws {
        guard AXPermission.isTrusted else { throw TextIOError.notTrusted }
        guard let handle = target.element else { throw TextIOError.writeFailed }

        let element = handle.element
        element.applyMessagingTimeout()

        let before = element.stringAttribute(kAXValueAttribute)

        switch target.captureMode {
        case .selection:
            // Re-assert the range: the app may have moved the insertion point
            // between capture and write (a click elsewhere, an autocomplete).
            if let range = target.selectedRange {
                var mutable = range
                if let value = AXValueCreate(.cfRange, &mutable) {
                    element.setAttribute(kAXSelectedTextRangeAttribute, value)
                }
            }

        case .wholeInput, .fullDocument:
            // Select all, then replace the selection — there is no "set whole
            // value" that preserves undo.
            let length = (before ?? target.text).utf16.count
            var all = CFRange(location: 0, length: length)
            guard let value = AXValueCreate(.cfRange, &all),
                  element.setAttribute(kAXSelectedTextRangeAttribute, value) else {
                throw TextIOError.writeFailed
            }
        }

        guard element.setAttribute(kAXSelectedTextAttribute, replacement as CFString) else {
            throw TextIOError.writeFailed
        }

        guard Self.writeLanded(replacement, in: element, before: before, mode: target.captureMode) else {
            throw TextIOError.writeFailed
        }
    }

    /// Re-reads the field and decides whether the replacement is actually in there.
    ///
    /// Unreadable-after-write is treated as success: some fields stop exposing
    /// `kAXValue` once edited, and pasting a second time over a write that did land
    /// would duplicate the user's text — the worse of the two failures.
    static func writeLanded(
        _ replacement: String,
        in element: AXUIElement,
        before: String?,
        mode: CaptureMode
    ) -> Bool {
        guard let after = element.stringAttribute(kAXValueAttribute) else { return true }

        switch mode {
        case .wholeInput, .fullDocument:
            return after == replacement
        case .selection:
            // The field still holds the surrounding text, so containment is the
            // strongest claim available. A field that did not change at all failed.
            return after.contains(replacement) || after != before
        }
    }

    // MARK: - Electron

    /// Returns true when the flag was newly set, meaning the tree may only now have
    /// become readable and the caller should re-read.
    ///
    /// Cached per pid: setting it is a cross-process AX call, and it only needs to
    /// happen once per app for the lifetime of that process.
    @discardableResult
    private func primeManualAccessibility(pid: pid_t) -> Bool {
        guard !manualAccessibilityGranted.contains(pid) else { return false }
        manualAccessibilityGranted.insert(pid)

        let app = AXUIElementCreateApplication(pid)
        app.applyMessagingTimeout()
        return app.setAttribute("AXManualAccessibility", kCFBooleanTrue)
    }

    // MARK: - Browser URL

    /// Best-effort. Walks up from the focused element looking for an `AXWebArea`
    /// carrying `AXURL`.
    ///
    /// Deliberately not AppleScript, which `prompt/`'s `getBrowserContext` uses:
    /// that would add an Automation permission prompt on top of Accessibility for a
    /// field that only shapes the prompt and feeds analytics. Nil is fine.
    private func browserURL(from element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < 12 {
            node.applyMessagingTimeout()
            if node.stringAttribute(kAXRoleAttribute) == "AXWebArea" {
                if let url = node.copyAttribute(kAXURLAttribute) as? URL {
                    return url.absoluteString
                }
                if let url = node.stringAttribute(kAXURLAttribute) {
                    return url
                }
            }
            current = node.elementAttribute(kAXParentAttribute)
            depth += 1
        }
        return nil
    }
}
