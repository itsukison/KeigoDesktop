import ApplicationServices
import DesktopRewriteKit
import Foundation
import os

/// **Not behind `#if DEBUG`, deliberately.** `Logger.debug` is compiled in but not
/// recorded unless someone is streaming the subsystem, so it costs a release build
/// nothing — and a release build is exactly where AX misbehaves and no debugger is
/// attached. It carries roles, verdicts and booleans; never captured or rewritten text.
///
///     log stream --predicate 'subsystem == "com.core7.keigobutton.mac"'
public let destinationLog = Logger(
    subsystem: "com.core7.keigobutton.mac",
    category: "destination"
)

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
        guard let focused = focusedElement(frontmostPID: frontmostPID) else {
            throw TextIOError.noTarget
        }
        return try target(for: focused, pid: focused.processIdentifier, allowEmpty: allowEmpty)
    }

    /// Captures the user's side of a reply without confusing the copied source with
    /// the draft it is answering.
    ///
    /// This deliberately has no clipboard fallback. Reply mode already owns the
    /// clipboard text as `copiedMessage`; copying again can only rediscover that same
    /// incoming message, never a blank reply box. A missing/non-text focus therefore
    /// becomes a scratch target that can be copied or redirected after the user clicks
    /// a real reply field.
    public func captureReply(frontmostPID: pid_t?, copiedMessage: String) throws -> TextTarget {
        guard AXPermission.isTrusted else { throw TextIOError.notTrusted }
        let fallbackBundleId = frontmostPID.flatMap { BundleIdentity.bundleIdentifier(for: $0) }
        guard let focused = focusedElement(frontmostPID: frontmostPID) else {
            return TextTarget.scratch(hostAppBundleId: fallbackBundleId)
        }

        let pid = focused.processIdentifier
        let handle = AXElementHandle(element: focused, pid: pid)
        let bundleId = BundleIdentity.bundleIdentifier(for: pid) ?? fallbackBundleId
        let wholeValue = focused.stringAttribute(kAXValueAttribute)
        let selected = focused.stringAttribute(kAXSelectedTextAttribute)

        switch Self.replyCaptureDisposition(
            copiedMessage: copiedMessage,
            selectedText: selected,
            wholeValue: wholeValue,
            canTakeText: Self.canTakeText(focused)
        ) {
        case .copiedSource:
            return TextTarget.scratch(hostAppBundleId: bundleId, excluding: handle)
        case .scratch:
            return TextTarget.scratch(hostAppBundleId: bundleId)
        case .wholeDraft(let draft):
            return TextTarget(
                text: draft,
                captureMode: .wholeInput,
                path: .ax,
                writeStrategy: focused.isSettable ? .ax : .clipboard,
                hostAppBundleId: bundleId,
                browserURL: browserURL(from: focused),
                element: handle,
                selectedRange: focused.rangeAttribute(kAXSelectedTextRangeAttribute)
            )
        }
    }

    enum ReplyCaptureDisposition: Equatable {
        /// The incoming message is still selected. It is context, not a draft or a
        /// destination, even when the selected element happens to be editable.
        case copiedSource
        /// A focused reply field. The whole value is the draft even when the user has
        /// selected only one phrase inside it; a reply result is a complete body.
        case wholeDraft(String)
        /// No usable reply field is focused.
        case scratch
    }

    static func replyCaptureDisposition(
        copiedMessage: String,
        selectedText: String?,
        wholeValue: String?,
        canTakeText: Bool
    ) -> ReplyCaptureDisposition {
        let normalize: (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\r\n", with: "\n")
        }
        let copied = normalize(copiedMessage)
        if let selectedText, !copied.isEmpty, normalize(selectedText) == copied {
            return .copiedSource
        }
        guard canTakeText else { return .scratch }
        return .wholeDraft(wholeValue ?? "")
    }

    /// **The one focus reading in this file, and it used to be two.**
    ///
    /// `capture` read the system-wide focused element with the priming §5 requires;
    /// the destination probe read it off the frontmost *application* element instead.
    /// Those are not the same question. An application element answers nil for exactly
    /// the web-content and helper processes the priming exists for, so the probe could
    /// not see fields the capture had just successfully read from — the user clicked
    /// into a text box and the panel went on offering コピー. Anything asking "where is
    /// the keyboard right now" goes through here.
    ///
    /// `AXUIElementCreateSystemWide` is the documented instrument for this: its whole
    /// purpose is finding the focused object regardless of which application is active.
    ///
    /// - Parameter frontmostPID: primed first, and **required for Chromium and Electron**
    ///   — they expose no focused element at all until `AXManualAccessibility` is set on
    ///   the application element. The focused element may then turn out to live in a
    ///   different process (a renderer or helper), so that one is primed too and the
    ///   read is repeated once.
    func focusedElement(frontmostPID: pid_t?) -> AXUIElement? {
        if let frontmostPID {
            primeManualAccessibility(pid: frontmostPID)
        }

        guard let focused = systemWide.elementAttribute(kAXFocusedUIElementAttribute) else {
            return nil
        }
        focused.applyMessagingTimeout()

        let pid = focused.processIdentifier
        if pid != frontmostPID, primeManualAccessibility(pid: pid),
           let refreshed = systemWide.elementAttribute(kAXFocusedUIElementAttribute) {
            refreshed.applyMessagingTimeout()
            return refreshed
        }
        return focused
    }

    /// The application that owns keyboard focus, as **AX** understands it.
    ///
    /// Not `NSWorkspace.frontmostApplication`: the question being asked is where a
    /// synthesized ⌘V would land, and that follows keyboard focus. It is also the honest
    /// way to ask whether our own key panel has taken focus away from the user's app —
    /// a thing reasoned about twice in this file and never measured.
    func focusedApplicationPID() -> pid_t? {
        systemWide.elementAttribute(kAXFocusedApplicationAttribute)?.processIdentifier
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
        // **`canTakeText`, not "kAXValue is non-nil".** §16 claimed a nil `kAXValue` was
        // what says this is not a text field, and that it was the only thing keeping ⌘A +
        // ⌘V out of the Finder. It is neither. Plenty of things that are not text controls
        // answer `kAXValue` with a string — static text, a table row, a web area — so with
        // nothing focused at all this branch handed back a target carrying a real write
        // strategy, the panel offered 挿入 over it, and the press synthesized ⌘A + ⌘V into
        // whatever was frontmost. Reported on screen 2026-08-19, from ✎ with no field
        // anywhere; the scratch path that exists for exactly that case never got a chance
        // to run, because this branch answered first.
        //
        // It only guards the *blank* branch. A field with text in it was asked for by
        // name — the user selected it or it is the field they are typing in — and §5's
        // rule that reading is decided separately from writing still governs there; the
        // destination probe re-asks `canTakeText` of those at verdict time instead.
        if allowEmpty, let wholeValue, Self.canTakeText(element) {
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

        destinationLog.debug("""
            capture rejected role=\(element.stringAttribute(kAXRoleAttribute) ?? "-", privacy: .public) \
            subrole=\(element.stringAttribute(kAXSubroleAttribute) ?? "-", privacy: .public) \
            hasValue=\(wholeValue != nil, privacy: .public) \
            isField=\(Self.canTakeText(element), privacy: .public) \
            allowEmpty=\(allowEmpty, privacy: .public)
            """)
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
    public func write(_ replacement: String, to target: TextTarget) async throws {
        guard AXPermission.isTrusted else { throw TextIOError.notTrusted }
        guard let handle = target.element else { throw TextIOError.writeFailed }

        // Cross-process AX is synchronous IPC and belongs on this actor. The practice
        // editor is the one exception: its AX element belongs to this process, so the
        // setter enters AppKit's NSTextView implementation directly. AppKit requires
        // that path on the main queue and traps in `_dispatch_assert_queue_fail` when
        // it arrives from a cooperative executor.
        if Self.writeRequiresMainActor(
            targetPID: handle.pid,
            currentPID: ProcessInfo.processInfo.processIdentifier
        ) {
            try await MainActor.run {
                try Self.performWrite(replacement, to: target, handle: handle)
            }
            return
        }

        try Self.performWrite(replacement, to: target, handle: handle)
    }

    static func writeRequiresMainActor(targetPID: pid_t, currentPID: pid_t) -> Bool {
        targetPID == currentPID
    }

    private static func performWrite(
        _ replacement: String,
        to target: TextTarget,
        handle: AXElementHandle
    ) throws {
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

        guard writeLanded(replacement, in: element, before: before, mode: target.captureMode) else {
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

    // MARK: - Destination (§18)

    /// Where the user's keyboard was the last time the question could honestly be asked.
    ///
    /// **This type exists because of *when* the probe runs, not what it reads.** The
    /// result panel is key for its whole life — it has to be, Enter is bound to 挿入 —
    /// and §4 already recorded what that does to Accessibility: "by submit time the input
    /// bar is key and `AXFocusedUIElement` points at our own field". So a probe that asks
    /// live, from inside that panel, can only ever be told about us. It fell open to
    /// `.ready` on that answer and 挿入 was offered with nothing focused anywhere;
    /// `.redirect` could never fire at all, so every scratch compose ended as コピー.
    ///
    /// The reading is therefore taken from moments when we are *not* holding the
    /// keyboard — at capture, and from any poll that lands while the user is back in
    /// their own window — and remembered. A reading that answered about us replaces
    /// nothing, which is what makes 「click where it belongs, then press ここに挿入」
    /// survive the click that hands us key back.
    public struct UserFocus: Sendable {
        public let element: AXElementHandle
        /// The app to reactivate for a redirect write, snapshotted alongside the element.
        /// Never the element's own pid: Chromium and Electron put the focused element in
        /// a helper process `NSRunningApplication` cannot activate.
        public let frontmostPID: pid_t?
        public let bundleId: String?
        /// `kAXFocusedApplication` when this was read. What lets a later `.silent`
        /// reading be told apart: the same app going quiet is an app declining to
        /// answer, a *different* app owning the keyboard is the reading going stale.
        public let focusedAppPID: pid_t?
        /// `canTakeText` at the time of reading. Re-asked before it is offered as a
        /// redirect — this one is for the trace and for nothing else.
        public let canTakeText: Bool
    }

    /// What a live focus read produced. The three cases are not interchangeable and
    /// collapsing them is the bug this file was rewritten around twice.
    public enum UserFocusReading: Sendable {
        /// Somebody else's element. The only case that may replace a remembered reading.
        case user(UserFocus)
        /// AX answered about **us** — our own key panel. A question that could not be
        /// asked, never "the user is nowhere".
        case unaskable
        /// AX would not say. Ordinary in exactly the apps the priming exists for.
        ///
        /// Carries `kAXFocusedApplication` because silence alone cannot be acted on and
        /// this is what makes it legible: the same app that the remembered reading came
        /// from is one that has gone quiet, and a different one is the user having moved
        /// on — clicking the Desktop is the everyday case, and it is exactly the
        /// "挿入 offered with nothing focused" report.
        case silent(focusedAppPID: pid_t?)
    }

    /// Reads where the keyboard is right now, and says plainly when it could not.
    ///
    /// - Parameter frontmostPID: primed first, per `focusedElement(frontmostPID:)`.
    public func readUserFocus(frontmostPID: pid_t?) -> UserFocusReading {
        guard AXPermission.isTrusted else {
            Self.traceFocus("silent", why: "untrusted", pid: nil, role: nil, isField: nil)
            return .silent(focusedAppPID: nil)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Asked before the element read: `kAXFocusedApplication` being us is the cheapest
        // and most direct form of "you are holding the keyboard, do not trust what comes
        // back next".
        let focusedApp = focusedApplicationPID()
        if focusedApp == ownPID {
            Self.traceFocus("unaskable", why: "focusedApp==self", pid: focusedApp, role: nil, isField: nil)
            return .unaskable
        }

        guard let focused = focusedElement(frontmostPID: frontmostPID) else {
            // **The one distinction the whole diagnosis rests on.** `focusedApp` is what
            // separates "our panel took the keyboard" from "the user really is nowhere":
            // nil here with a *foreign* focused app is an app declining to answer, and
            // nil with no focused app at all is a desktop with nothing on it.
            Self.traceFocus("silent", why: "noFocusedElement", pid: focusedApp, role: nil, isField: nil)
            return .silent(focusedAppPID: focusedApp)
        }
        let pid = focused.processIdentifier
        guard pid != ownPID else {
            Self.traceFocus("unaskable", why: "element==self", pid: pid, role: nil, isField: nil)
            return .unaskable
        }

        let isField = Self.canTakeText(focused)
        Self.traceFocus(
            "user",
            why: BundleIdentity.bundleIdentifier(for: pid) ?? "-",
            pid: pid,
            role: focused.stringAttribute(kAXRoleAttribute),
            isField: isField
        )
        return .user(
            UserFocus(
                element: AXElementHandle(element: focused, pid: pid),
                frontmostPID: frontmostPID,
                bundleId: BundleIdentity.bundleIdentifier(for: pid),
                focusedAppPID: focusedApp,
                canTakeText: isField
            )
        )
    }

    /// Why a focus reading came out the way it did. Paired with the `verdict=` line: that
    /// one reports `focusReadable`, this one reports *which* of the three reasons is
    /// behind it, and `focusReadable=false` means nothing without it.
    private static func traceFocus(
        _ reading: String,
        why: String,
        pid: pid_t?,
        role: String?,
        isField: Bool?
    ) {
        destinationLog.debug("""
            focus=\(reading, privacy: .public) \
            why=\(why, privacy: .public) \
            pid=\(pid.map(String.init) ?? "-", privacy: .public) \
            self=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) \
            role=\(role ?? "-", privacy: .public) \
            isField=\(isField.map(String.init) ?? "-", privacy: .public)
            """)
    }

    /// Is the place this rewrite came from still there, and if not, is the user in a
    /// field that could take it instead?
    ///
    /// **Reads only.** This runs on a timer while a result panel is up, so it must
    /// never synthesize a keystroke — a probe that reached for the clipboard fallback
    /// would fire ⌘C into the user's app twice a second.
    ///
    /// Everything about the *captured* element is re-asked live, because those questions
    /// are answerable no matter who holds the keyboard: an AX read is addressed to an
    /// element, not to the front window. Only "where is the user now" comes in from
    /// outside, as `userFocus`, for the reason `UserFocus` documents.
    ///
    /// - Parameter capturedPID: the app the target was read from. Only used when there
    ///   is no captured element to ask — the clipboard path stores no element.
    /// - Parameter userFocus: the remembered reading, or nil when no reading has ever
    ///   been obtainable. Nil means `focusReadable: false`, which fails open.
    public func resolveDestination(
        for target: TextTarget,
        capturedPID: pid_t?,
        userFocus: UserFocus?
    ) -> (verdict: DestinationVerdict, redirect: TextTarget?) {
        // Nothing works without the permission, and answering `.unavailable` here would
        // replace the one message that tells the user what to do with a copy hint.
        guard AXPermission.isTrusted else { return (.ready, nil) }

        let focused = userFocus?.element.element
        focused?.applyMessagingTimeout()
        let redirect = userFocus.flatMap { focus -> TextTarget? in
            if let excluded = target.excludedRedirectElement,
               CFEqual(excluded.element, focus.element.element) {
                return nil
            }
            return Self.redirectTarget(focus)
        }

        let facts = DestinationFacts(
            capturedHasDestination: target.hasDestination,
            capturedStrategy: target.writeStrategy,
            capturedAppRunning: (target.element?.pid ?? capturedPID).map(Self.isRunning) ?? false,
            capturedElementStillWritable: target.element?.element.isSettable ?? false,
            capturedElementIsField: target.element.map { Self.canTakeText($0.element) },
            capturedElementFocused: capturedElementIsFocused(target, focused: focused),
            focusedHoldsCapturedText: focused.map {
                !target.text.isEmpty && Self.reads(target.text, from: $0, mode: target.captureMode)
            } ?? false,
            focusReadable: userFocus != nil,
            redirectAvailable: redirect != nil
        )

        let verdict = DestinationVerdict.decide(facts)
        Self.trace(facts: facts, verdict: verdict, focused: focused)
        return (verdict, verdict == .redirect ? redirect : nil)
    }

    private func capturedElementIsFocused(_ target: TextTarget, focused: AXUIElement?) -> Bool {
        guard let handle = target.element, let focused else { return false }
        handle.element.applyMessagingTimeout()
        return CFEqual(handle.element, focused)
    }

    /// The field the user was last in, when it can still take text.
    ///
    /// **`canTakeText` is re-asked rather than taken from the reading**, for the same
    /// reason settability is re-asked of the captured element: the reading may be from
    /// before the panel opened, and a window closed since answers nothing at all — which
    /// is exactly the false `.redirect` that would write into a dead element and report
    /// success. Never our own process: `readUserFocus` refuses to produce one, and the
    /// result panel's prompt-echo field is a text field, so offering to insert the rewrite
    /// into the box that shows the instruction would otherwise be a live option.
    private static func redirectTarget(_ focus: UserFocus) -> TextTarget? {
        let element = focus.element.element
        element.applyMessagingTimeout()
        guard canTakeText(element) else { return nil }

        return TextTarget.redirect(
            element: focus.element,
            writeStrategy: element.isSettable ? .ax : .clipboard,
            hostAppBundleId: focus.bundleId
        )
    }

    /// AX reports success while doing nothing and answers a different question in every
    /// app, so a reading nobody can see is a reading nobody can correct — the same reason
    /// `scripts/axdiag.swift` exists. Debug builds only:
    /// `log stream --predicate 'subsystem == "com.core7.keigobutton.mac"'`.
    private static func trace(
        facts: DestinationFacts,
        verdict: DestinationVerdict,
        focused: AXUIElement?
    ) {
        let role = focused?.stringAttribute(kAXRoleAttribute) ?? "-"
        let subrole = focused?.stringAttribute(kAXSubroleAttribute) ?? "-"
        destinationLog.debug("""
            verdict=\(verdict.rawValue, privacy: .public)             role=\(role, privacy: .public)/\(subrole, privacy: .public)             strategy=\(facts.capturedStrategy.rawValue, privacy: .public)             hasDest=\(facts.capturedHasDestination, privacy: .public)             writable=\(facts.capturedElementStillWritable, privacy: .public)             capturedIsField=\(facts.capturedElementIsField.map(String.init) ?? "unasked", privacy: .public)             capturedFocused=\(facts.capturedElementFocused, privacy: .public)             textMatch=\(facts.focusedHoldsCapturedText, privacy: .public)             focusReadable=\(facts.focusReadable, privacy: .public)             redirect=\(facts.redirectAvailable, privacy: .public)
            """)
    }

    /// Whether an element is a text control that would accept text being put into it.
    ///
    /// Four signals in order of how much they can be trusted, because the role is the
    /// least reliable of them in exactly the apps that matter:
    ///
    ///   1. `kAXSelectedText` settable — decisive when true, and the same test §5 uses to
    ///      choose the AX write strategy.
    ///   2. A selected-text **range**, a character count, or an insertion-point line.
    ///      Only text objects expose these, and Gmail's compose box — unsettable,
    ///      pasteable, and the case §5 was rewritten around — has them.
    ///   3. A known text role, last.
    ///
    /// And one veto: a **secure** field. Putting a rewrite into a password box is not a
    /// service, and macOS's secure input mode would swallow the ⌘V anyway. The global
    /// `IsSecureEventInputEnabled()` was considered and rejected — it is famously left
    /// stuck on by other applications, and one of those would have degraded every insert
    /// on the machine to a copy.
    static func canTakeText(_ element: AXUIElement) -> Bool {
        if element.stringAttribute(kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
            return false
        }
        // **A container is never the text entry, however many text questions it answers.**
        // Measured 2026-08-19: ✎ pressed in a browser with no input focused captured the
        // page's `AXWebArea`, which passes signal 2 below — web areas expose a selected
        // range and a character count for the document. `capturedIsField=true`,
        // `capturedFocused=true`, verdict `.ready`, 挿入 offered, and the ⌘V went into a
        // page that cannot be typed in. Signal 2 exists for Gmail's compose box, which is
        // a *child* of a web area and not one, so vetoing the containers costs it nothing.
        //
        // Ahead of settability deliberately: the veto is about what the element *is*, and
        // a container that also answers yes to a write question is the case being ruled
        // out, not an exception to it.
        if let role = element.stringAttribute(kAXRoleAttribute), containerRoles.contains(role) {
            return false
        }
        if element.isSettable { return true }
        if element.rangeAttribute(kAXSelectedTextRangeAttribute) != nil { return true }
        if element.copyAttribute(kAXNumberOfCharactersAttribute) != nil { return true }
        if element.copyAttribute(kAXInsertionPointLineNumberAttribute) != nil { return true }
        guard let role = element.stringAttribute(kAXRoleAttribute) else { return false }
        return textRoles.contains(role)
    }

    private static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    /// Things that *hold* text controls rather than being one. They answer range and
    /// character-count queries on behalf of their contents, which is exactly what made
    /// them false positives.
    static func isContainerRole(_ role: String) -> Bool { containerRoles.contains(role) }

    private static let containerRoles: Set<String> = [
        "AXWebArea", kAXGroupRole, kAXScrollAreaRole, kAXStaticTextRole,
        kAXListRole, kAXOutlineRole, kAXTableRole, kAXRowRole,
    ]

    /// Does this element still hold the text we captured? Electron and web views rebuild
    /// elements around a field that never changed, so element identity alone reports the
    /// user's own compose box as gone.
    static func reads(_ text: String, from element: AXUIElement, mode: CaptureMode) -> Bool {
        switch mode {
        case .selection:
            return element.stringAttribute(kAXSelectedTextAttribute) == text
        case .wholeInput, .fullDocument:
            return element.stringAttribute(kAXValueAttribute) == text
        }
    }

    /// `kill(pid, 0)` rather than `NSRunningApplication`: this module stays AppKit-free
    /// (§3) and the question is only whether the process is still there.
    static func isRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Verifying a synthesized paste

    /// Whether a ⌘V actually changed the field, for the targets where AX can see it.
    ///
    /// A clipboard write reports success as soon as the keystroke is posted, so a paste
    /// into a place that does not accept one — selected text on a web page is the common
    /// case — used to be indistinguishable from a paste that landed. Everything about
    /// the outcome was invisible: the panel closed, history said 挿入済み, and the field
    /// never changed.
    ///
    /// **Unreadable counts as landed**, the same call `writeLanded` makes and for the
    /// same reason: a second paste over a write that did land duplicates the user's
    /// text, which is the worse failure.
    public func pasteLanded(_ replacement: String, in target: TextTarget, before: String?) -> Bool {
        guard let handle = target.element else { return true }
        handle.element.applyMessagingTimeout()
        guard let after = handle.element.stringAttribute(kAXValueAttribute) else { return true }
        return Self.pasteLanded(replacement, after: after, before: before)
    }

    /// Deliberately looser than `writeLanded`: any change at all counts. A field that
    /// normalises what it was given — smart quotes, a trimmed newline, an autocomplete —
    /// did accept the paste, and only "nothing happened whatsoever" is the failure this
    /// is looking for.
    static func pasteLanded(_ replacement: String, after: String, before: String?) -> Bool {
        after.contains(replacement) || after != before
    }

    /// The field's value right before a paste, so `pasteLanded` has something to
    /// compare against.
    public func currentValue(of target: TextTarget) -> String? {
        guard let handle = target.element else { return nil }
        handle.element.applyMessagingTimeout()
        return handle.element.stringAttribute(kAXValueAttribute)
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
