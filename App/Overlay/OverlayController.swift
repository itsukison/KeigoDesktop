import AppKit
import DesktopRewriteKit
import SwiftUI
import TextIO

/// Owns the three windows and drives the §4 state machine.
///
/// Everything here is `@MainActor`. The AX work happens inside `TextIOCoordinator`,
/// which is its own actor, so the main thread never makes a synchronous AX call.
@MainActor
final class OverlayController: ObservableObject {

    @Published private(set) var state: OverlayState = .pill
    @Published private(set) var prompts: [UserPrompt] = []
    @Published private(set) var tutorialPrompts: [UserPrompt] = []
    /// Set only when the fetch failed **and** left nothing to show — see `refreshPrompts`.
    @Published private(set) var promptsFailed = false
    /// Set when there is no usable session at all. The hover row answers this with a
    /// sign-in button rather than an apology — see `refreshPrompts`.
    @Published private(set) var signedOut = false

    private let panel: PillPanel
    private var generatingPanel: GeneratingPanel?
    private var resultPanel: ResultPanel?

    private let textIO: TextIOCoordinator
    private let rewriteService: DesktopRewriteService
    private let promptStore: UserPromptRemoteStore
    private let analytics: Analytics
    private let history: RewriteHistoryStore
    private let appVersion: String

    private var collapseTask: Task<Void, Never>?
    private var rewriteTask: Task<Void, Never>?
    private var positionTracker: Timer?
    private var errorPanel: ErrorPanel?
    private var errorDismissTask: Task<Void, Never>?
    private var lastWorkArea: NSRect = .zero

    // MARK: Right-click snooze

    /// The right-click menu's "非表示にする" — stored as an absolute deadline, not driven
    /// by a `Task.sleep`, for the same reason `ClipboardWatcher.copyDisabledUntil` is:
    /// a 10-minute or 1-hour window has to survive the Mac sleeping, and only a stored
    /// `Date` compared against `Date()` does that reliably. Persisted, so quitting
    /// mid-window does not undo it — `show()` re-applies it on the next launch.
    private static let hiddenUntilKey = "overlay.pill.hiddenUntil"

    private static var hiddenUntil: Date? {
        get { UserDefaults.standard.overlaySnoozeDeadline(forKey: hiddenUntilKey) }
        set { UserDefaults.standard.setOverlaySnoozeDeadline(newValue, forKey: hiddenUntilKey) }
    }

    /// Set only while the pill is hidden *because of* the snooze — as opposed to
    /// onboarding, which also calls `setVisible(false)` for a lifecycle reason of its
    /// own. `checkHiddenExpiry` only acts while this is true, so an expiring deadline
    /// never pops the bar back up over a state the snooze did not create.
    private var hiddenBySnooze = false

    private var snoozeMenuPanel: SnoozeMenuPanel?

    // MARK: Reply mode (§16)

    private var clipboardWatcher: ClipboardWatcher?
    private var replyContextPanel: ReplyContextPanel?
    private var replyExpiryTask: Task<Void, Never>?
    /// Hover is passive, so the "no field to reply into" toast fires once per armed
    /// copy. Unbounded, every pass of the cursor over the bar would raise it again.
    private var warnedNoReplyTarget = false
    /// Hover fires on re-entry and the capture is a cross-process AX call, so a
    /// cursor jittering on the bar's edge could otherwise start several.
    private var replyCaptureInFlight = false

    /// Stands in for the prompt when the user submits an empty reply instruction.
    /// "Just write me a reply" is the strongest case for this feature, and the backend
    /// rejects an empty `prompt` outright (`parseRequest`), so something has to be sent.
    private static let defaultReplyInstruction = "この内容に自然に返信してください。"

    /// The row to flip to `accepted` if the user goes on to insert. Only one rewrite
    /// is ever in flight, and a regenerate deliberately replaces it — the entry that
    /// gets inserted is the last one produced.
    private var lastHistoryEntryId: UUID?
    private var tutorialInserted: (() -> Void)?
    private var tutorialMode: OnboardingTutorialMode?

    /// Opens the paywall when a **free** user hits the monthly cap (§9 row 41).
    ///
    /// A closure rather than a reference to the window: `AppDelegate` owns both this
    /// controller and `MainWindowController`, and §14's rule is that the overlay and
    /// the window have no lifetime relationship at all. Giving the bar a handle on the
    /// window would be the first one.
    var onQuotaPaywall: (() -> Void)?

    /// Opens the returning-user sign-in surface when a rewrite discovers that the
    /// saved session is missing. Kept as a callback for the same ownership reason as
    /// `onQuotaPaywall`: the overlay must not own or retain the main window.
    var onSignInRequired: (() -> Void)?

    var displayedPrompts: [UserPrompt] {
        tutorialPrompts.isEmpty ? prompts : tutorialPrompts
    }

    /// A scheduled updater window may take key, which is safe only while the bar is
    /// fully at rest. In every other state that would interrupt capture, typing, a
    /// rewrite in flight, or a result the user is still judging.
    var allowsUpdateCheck: Bool {
        state == .pill
    }

    init(
        rewriteService: DesktopRewriteService,
        promptStore: UserPromptRemoteStore,
        analytics: Analytics,
        history: RewriteHistoryStore,
        appVersion: String
    ) {
        self.rewriteService = rewriteService
        self.promptStore = promptStore
        self.analytics = analytics
        self.history = history
        self.appVersion = appVersion
        self.textIO = TextIOCoordinator(
            clipboard: ClipboardTextIO(
                pasteboard: SystemPasteboard(),
                activator: RunningAppActivator()
            )
        )

        let screen = OverlayPlacement.activeScreen()
        let size = NSSize(
            width: Tokens.Geometry.pillCollapsedWidth,
            height: Tokens.Geometry.pillHeight
        )
        panel = PillPanel(contentRect: OverlayPlacement.frame(for: size, on: screen))

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reanchor),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // Entering or leaving a full-screen app is a space change, not a screen-
        // parameters change: the work area loses the Dock and the menu bar without
        // `didChangeScreenParameters` ever firing.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(reanchor),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        // Clicking into another app is a cancel. Scoped to `panel`, so the user's own
        // window resigning key when we take it does not come back through here.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
    }

    /// `transition` sets `state` before it touches `acceptsKey`, so the resign it
    /// triggers on the way *out* of the input bar finds a state that is already
    /// something else and stops here.
    @objc private func panelResignedKey() {
        // Checked a turn later rather than inline: an accessory app taking key on a
        // non-activating panel can bounce once as focus settles, and cancelling on
        // that would make the input bar close the instant it opened.
        Task { @MainActor [weak self] in
            guard let self, !self.panel.isKeyWindow else { return }
            self.cancelInput()
        }
    }

    // MARK: - Lifecycle

    func show() {
        panel.contentView = NSHostingView(rootView: PillRootView(controller: self))
        startPositionTracking()

        // A snooze started before the last quit is still checked against the wall
        // clock here, not against how long the app was closed — see `hiddenUntilKey`.
        if OverlaySnooze.isActive(until: Self.hiddenUntil) {
            hiddenBySnooze = true
            setVisible(false)
        } else {
            Self.hiddenUntil = nil // clears a deadline that had already passed
            panel.orderFrontRegardless()
            startClipboardWatching()
        }
        Task { await refreshPrompts() }
    }

    // MARK: - Right-click snooze

    /// Whether the bar is currently down because of a right-click hide — as opposed to
    /// hidden, say, during onboarding. `AppDelegate`'s status-bar menu reads this to
    /// decide whether "再表示する" belongs on screen at all.
    var isHiddenBySnooze: Bool { hiddenBySnooze }

    /// `nil` unless `isHiddenBySnooze` — there is no deadline to read a countdown off
    /// of otherwise.
    var hiddenRemainingMinutes: Int? {
        guard hiddenBySnooze, let until = Self.hiddenUntil else { return nil }
        return OverlaySnooze.remainingMinutes(until: until)
    }

    /// The right-click menu's "非表示にする" rows. Reuses `setVisible(false)` wholesale —
    /// it already dismisses the auxiliary panels and stops the clipboard watcher, and
    /// none of that needs a second implementation just because this hide is timed.
    func hideOverlay(for duration: OverlaySnooze.Duration) {
        Self.hiddenUntil = OverlaySnooze.until(duration)
        hiddenBySnooze = true
        setVisible(false) // also dismisses the menu this was very likely called from
    }

    /// The status-bar menu's "今すぐ再表示する" — the only way back once the pill itself
    /// is gone and there is nothing left to right-click. The deadline is cleared by
    /// `setVisible(true)`, which every other route back goes through as well.
    func cancelHideNow() {
        guard hiddenBySnooze else { return }
        setVisible(true)
    }

    /// Whether the copy-triggered reply arm (§16) is inside a timed disable, and how
    /// long is left on it. Both menus that offer the toggle are built fresh on every
    /// open, so this is asked at that moment rather than published.
    var isCopyTriggerDisabled: Bool {
        OverlaySnooze.isActive(until: ClipboardWatcher.copyDisabledUntil)
    }

    var copyDisabledRemainingMinutes: Int? {
        guard let until = ClipboardWatcher.copyDisabledUntil, OverlaySnooze.isActive(until: until) else {
            return nil
        }
        return OverlaySnooze.remainingMinutes(until: until)
    }

    /// The right-click menu's "コピー機能を無効にする" rows. This does not touch the bar at
    /// all — `ClipboardWatcher` keeps polling, it just stops arming reply mode — so there
    /// is nothing here for `OverlayController` to own beyond forwarding the call.
    func disableCopyTrigger(for duration: OverlaySnooze.Duration) {
        ClipboardWatcher.copyDisabledUntil = OverlaySnooze.until(duration)
    }

    /// Its counterpart, "コピー機能を有効にする", in both menus.
    func enableCopyTriggerNow() {
        ClipboardWatcher.copyDisabledUntil = nil
    }

    /// Checked from the position-tracking timer below, which is already polling at the
    /// interval this needs and would otherwise be the only other timer in the app.
    private func checkHiddenExpiry() {
        guard hiddenBySnooze, !OverlaySnooze.isActive(until: Self.hiddenUntil) else { return }
        setVisible(true)
    }

    /// The pill's own right-click menu (§17) — not `.contextMenu`, see
    /// `SnoozeMenuPanel`'s doc comment for why. A second right-click while it is open
    /// closes it, the same as clicking any other control twice would toggle it.
    func toggleSnoozeMenu() {
        if snoozeMenuPanel != nil {
            dismissSnoozeMenu()
        } else {
            presentSnoozeMenu()
        }
    }

    private func presentSnoozeMenu() {
        // A menu opened mid-grace-period should not have its own open-ness raced by a
        // collapse timer that was scheduled before it existed — `mouseExited` re-checks
        // `snoozeMenuPanel` at fire time so this is belt-and-suspenders, but there is no
        // reason to leave a stale task sitting around either.
        collapseTask?.cancel()
        collapseTask = nil

        let menu = SnoozeMenuPanel(
            anchor: panel.frame,
            isCopyDisabled: isCopyTriggerDisabled,
            copyDisabledRemainingMinutes: copyDisabledRemainingMinutes,
            onHide: { [weak self] duration in self?.hideOverlay(for: duration) },
            onDisableCopy: { [weak self] duration in
                self?.disableCopyTrigger(for: duration)
                self?.dismissSnoozeMenu()
            },
            onCancelCopyDisable: { [weak self] in
                self?.enableCopyTriggerNow()
                self?.dismissSnoozeMenu()
            },
            onDismiss: { [weak self] in self?.dismissSnoozeMenu() }
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(snoozeMenuResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: menu
        )
        menu.makeKeyAndOrderFront(nil)
        snoozeMenuPanel = menu
    }

    /// Same bounce guard as `panelResignedKey`: an accessory app taking key on a
    /// non-activating panel can resign once as focus settles before it actually holds
    /// key, and dismissing on that would close the menu the instant it opened.
    @objc private func snoozeMenuResignedKey() {
        Task { @MainActor [weak self] in
            guard let self, self.snoozeMenuPanel?.isKeyWindow != true else { return }
            self.dismissSnoozeMenu()
        }
    }

    private func dismissSnoozeMenu() {
        guard let menu = snoozeMenuPanel else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: menu)
        menu.orderOut(nil)
        snoozeMenuPanel = nil

        // `mouseExited` asked this question and got told to stand down while the menu
        // was up (it re-checks `snoozeMenuPanel`, which is why nothing collapsed while
        // the cursor moved off the bar to read this). Now that it is gone, ask again:
        // if the cursor is not sitting back over the bar, the row should still collapse
        // — just on its own grace delay, the same as any other exit.
        if case .hoverRow = state, !panel.frame.contains(NSEvent.mouseLocation) {
            mouseExited()
        }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            // Any deliberate show outranks a timed hide, and onboarding is the caller
            // that makes this load-bearing: it puts the real bar on screen for its own
            // lesson, and a deadline left in force behind that would leave the status
            // menu offering 再表示 for a bar the user is already looking at.
            hiddenBySnooze = false
            Self.hiddenUntil = nil
            panel.orderFrontRegardless()
            startClipboardWatching()
        } else {
            rewriteTask?.cancel()
            dismissGeneratingPanel()
            dismissResultPanel()
            dismissErrorToast()
            // The right-click menu is only ever reachable while the pill is on screen
            // — once it is gone, so is whatever this was anchored to.
            dismissSnoozeMenu()
            // Watching the clipboard while the bar is hidden would arm a state with no
            // window to show it in, and re-arm it the moment the bar came back with a
            // copy from minutes ago.
            clipboardWatcher?.stop()
            clipboardWatcher = nil
            replyExpiryTask?.cancel()
            replyExpiryTask = nil
            // Assigned directly rather than through `transition`, so the context card
            // has to be taken down by hand — the sync that normally does it never runs.
            replyContextPanel?.orderOut(nil)
            replyContextPanel = nil
            state = .pill
            panel.acceptsKey = false
            panel.orderOut(nil)
        }
    }

    func refreshPrompts() async {
        do {
            prompts = try await promptStore.fetch().enabledForHoverRow
            promptsFailed = false
            signedOut = false
        } catch RewriteError.notSignedIn {
            // **Not the stale-data case below.** These buttons belong to an account
            // that is no longer attached, so keeping them would leave a row of pills
            // whose only possible outcome is a failed rewrite. The row shows the way
            // back in instead, which is the one thing the user can act on.
            prompts = []
            signedOut = true
            promptsFailed = false
        } catch {
            // A stale button list is better than an empty row, so whatever we had
            // stays. But an empty row after a *failure* is not the same as an empty
            // row because the user has no buttons — telling someone to go and make
            // buttons they already have is worse than saying nothing, so the row
            // needs to be able to tell the two apart.
            signedOut = false
            promptsFailed = prompts.isEmpty
        }
    }

    func beginTutorial(prompts: [UserPrompt], onInserted: @escaping () -> Void) {
        tutorialMode = .savedButtons(Set(prompts.map(\.id)))
        tutorialPrompts = prompts
        tutorialInserted = onInserted
        transition(to: .pill)
    }

    func beginCustomTutorial(onInserted: @escaping () -> Void) {
        tutorialMode = .custom
        tutorialPrompts = []
        tutorialInserted = onInserted
        transition(to: .pill)
    }

    func beginReplyTutorial(onInserted: @escaping () -> Void) {
        tutorialPrompts = []
        tutorialMode = .reply
        tutorialInserted = onInserted
        transition(to: .pill)
    }

    func copyReplyTutorialSource(_ text: String) {
        guard tutorialMode?.marksReply == true, let source = ReplySource(copied: text) else { return }
        ClipboardWatcher.writingOurselves {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        armReply(source)
    }

    func endTutorial() {
        tutorialPrompts = []
        tutorialInserted = nil
        tutorialMode = nil
        if case .pill = state { return }
        transition(to: .pill)
    }

    @objc private func reanchor() {
        lastWorkArea = OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: panel.frame))
        resize(to: currentSize(), animated: false)
    }

    /// The poll is not a belt-and-braces addition to the notifications above — for
    /// the Dock it is the only thing that works.
    ///
    /// The Dock sliding away under a full-screen space posts nothing, and it does not
    /// move `visibleFrame` either (see `OverlayPlacement.workArea`). The only witness
    /// is the Dock's own AX geometry, and there is nothing to subscribe to, so it has
    /// to be sampled. Willow ships the same loop — `barPositionTrackingTask`,
    /// `lastDockPosition` and `lastDockSize` are all in its binary.
    private func startPositionTracking() {
        lastWorkArea = OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: panel.frame))
        positionTracker?.invalidate()
        positionTracker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.checkHiddenExpiry()
                let area = OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: self.panel.frame))
                guard area != self.lastWorkArea else { return }
                self.reanchor()
            }
        }
    }

    // MARK: - Reply mode (§16)

    private func startClipboardWatching() {
        guard clipboardWatcher == nil else { return }
        let watcher = ClipboardWatcher { [weak self] source in self?.armReply(source) }
        watcher.start()
        clipboardWatcher = watcher
    }

    /// A copy arrived. The bar widens to show it and hovering now opens the input box
    /// rather than the button row.
    private func armReply(_ source: ReplySource) {
        // Only from a resting bar. Arming over an open input bar, a running rewrite or
        // a result card would replace something the user is in the middle of — and a
        // copy during a result is very often our own 結果 copy button, which is why
        // `copyToClipboard` also suspends the watcher.
        switch state {
        case .pill, .replyArmed:
            break
        case .hoverRow, .inputBar, .generating, .result, .replyInput:
            return
        }

        warnedNoReplyTarget = false
        transition(to: .replyArmed(source))
        scheduleReplyExpiry(source)
    }

    /// The ✕ on the armed bar.
    func dismissReply() {
        replyExpiryTask?.cancel()
        replyExpiryTask = nil
        guard state.isReply else { return }
        transition(to: .pill)
    }

    /// Only ever disarms from `.replyArmed`. If the user has since opened the input box
    /// or started a rewrite, the copy is in use and the clock stops mattering.
    private func scheduleReplyExpiry(_ source: ReplySource) {
        replyExpiryTask?.cancel()
        replyExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ReplySource.lifetime * 1_000_000_000))
            guard !Task.isCancelled, let self,
                  case .replyArmed(let armed) = self.state, armed == source
            else { return }
            self.transition(to: .pill)
        }
    }

    /// §4's capture ordering, moved to hover.
    ///
    /// The input bar takes key, so by the time the user has typed anything
    /// `AXFocusedUIElement` is our own field — the same reason `pressCustomInput`
    /// captures on the press rather than on submit. Hover is the last moment the
    /// user's own app still owns focus, so the read has to happen here.
    private func beginReplyInput(_ source: ReplySource) {
        guard !replyCaptureInFlight else { return }
        replyCaptureInFlight = true
        let frontmostPID = NSWorkspace.shared.frontmostPID

        Task { [weak self] in
            guard let self else { return }
            defer { self.replyCaptureInFlight = false }
            do {
                // `allowEmpty`: the reply box the user just clicked into is usually
                // blank, and a blank field is exactly what the normal capture rejects.
                ClipboardWatcher.suspend()
                let target = try await self.textIO.capture(
                    frontmostPID: frontmostPID,
                    allowEmpty: true
                )
                ClipboardWatcher.resume()
                // The copy can expire, or be dismissed, while a slow AX call is out.
                guard case .replyArmed(let armed) = self.state, armed == source else { return }
                self.transition(to: .replyInput(
                    reply: source,
                    target: CapturedTarget(target: target, frontmostPID: frontmostPID)
                ))
            } catch {
                ClipboardWatcher.resume()
                // Once per armed copy. Hover is passive: a toast on every pass of the
                // cursor over the bar would be worse than the missing field it reports.
                guard !self.warnedNoReplyTarget else { return }
                self.warnedNoReplyTarget = true
                self.present(
                    message: "返信を書き込む入力欄が見つかりません。返信したい場所をクリックしてから、バーにカーソルを合わせてください。"
                )
            }
        }
    }

    // MARK: - Hover

    func mouseEntered() {
        collapseTask?.cancel()
        collapseTask = nil
        // A live copy replaces the button row with the input box — the whole point of
        // reply mode is that the instruction is free text, not one of the saved buttons.
        if case .replyArmed(let source) = state {
            beginReplyInput(source)
            return
        }
        guard case .pill = state else { return }
        // The only retry there is. `refreshPrompts` otherwise runs once at launch, so
        // being offline at that moment left the row permanently empty. `signedOut` is
        // retried for the same reason: signing in elsewhere pushes a refresh through
        // `MainModel.onPromptsChanged`, but a session restored any other way would
        // otherwise leave the sign-in button up for the rest of the session.
        if promptsFailed || signedOut { Task { await refreshPrompts() } }
        transition(to: .hoverRow)
    }

    /// §4: collapse needs a grace delay. Without it a diagonal path toward a button
    /// on the far end of the row collapses it mid-travel.
    ///
    /// **Re-checked at fire time, not just at schedule time.** `mouseExited` fires the
    /// instant the cursor leaves the pill for `SnoozeMenuPanel` sitting above it (§17)
    /// — a different window, so the bar sees exactly what it would see for any other
    /// exit. Collapsing out from under an open menu would take the menu with it
    /// (`transition` dismisses it unconditionally), so the guard below reads
    /// `snoozeMenuPanel` at the moment the timer actually fires rather than trusting
    /// whatever was true when it was scheduled — the same reason §4 re-derives
    /// `anchorY` instead of carrying it over. `dismissSnoozeMenu` is what asks this
    /// question again once the menu is gone.
    func mouseExited() {
        guard case .hoverRow = state else { return }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Tokens.Geometry.collapseGrace * 1_000_000_000))
            guard !Task.isCancelled, let self, case .hoverRow = self.state,
                  self.snoozeMenuPanel == nil
            else { return }
            self.transition(to: .pill)
        }
    }

    // MARK: - The capture ordering (§4)

    /// Pressing one of the user's buttons.
    ///
    /// The read happens while the user's app is still frontmost and before any UI
    /// change — that ordering is the whole reason this works. The pid snapshot comes
    /// first only because it is a local read that cannot disturb focus; the AX call,
    /// which can block, still runs before anything is shown.
    func press(_ prompt: UserPrompt) {
        let frontmostPID = NSWorkspace.shared.frontmostPID

        Task { [weak self] in
            guard let self else { return }
            do {
                // The fallback capture clears and restores the pasteboard around a
                // synthesized ⌘C — three `changeCount` bumps that are ours, not a copy.
                ClipboardWatcher.suspend()
                let target = try await self.textIO.capture(frontmostPID: frontmostPID)
                ClipboardWatcher.resume()
                let captured = CapturedTarget(target: target, frontmostPID: frontmostPID)
                self.startRewrite(
                    captured: captured,
                    promptText: prompt.prompt,
                    replyTo: nil,
                    buttonTitle: prompt.title,
                    commandKey: prompt.builtinKey,
                    promptOrigin: prompt.origin.rawValue,
                    isTutorial: self.tutorialMode?.marksSavedButton(id: prompt.id) == true
                )
            } catch {
                ClipboardWatcher.resume()
                self.present(error)
            }
        }
    }

    /// Pressing ✎.
    ///
    /// §4: capture happens **now**, not on submit. By submit time the input bar is key
    /// and `AXFocusedUIElement` points at our own field.
    func pressCustomInput() {
        let frontmostPID = NSWorkspace.shared.frontmostPID

        Task { [weak self] in
            guard let self else { return }
            do {
                ClipboardWatcher.suspend()
                let target = try await self.textIO.capture(frontmostPID: frontmostPID)
                ClipboardWatcher.resume()
                self.transition(to: .inputBar(
                    target: CapturedTarget(target: target, frontmostPID: frontmostPID)
                ))
            } catch {
                ClipboardWatcher.resume()
                self.present(error)
            }
        }
    }

    /// The signed-out hover row's only action — the bar's way into the window.
    ///
    /// No capture and no AX call: there is nothing to rewrite until there is an
    /// account. The row collapses first so the bar is not left expanded behind the
    /// window that is about to take focus, and `onSignInRequired` is the same callback
    /// a rewrite raises when it discovers a missing session, so both routes land on
    /// アカウント in sign-in mode.
    func pressSignIn() {
        transition(to: .pill)
        onSignInRequired?()
    }

    /// Backing out of the input bar without sending anything.
    ///
    /// Reached from Escape and from the panel losing key — clicking anywhere else is
    /// how people leave a spotlight-style field, and an input bar you can only escape
    /// by submitting is a trap. The captured target is simply dropped; it is re-read
    /// on the next press anyway.
    ///
    /// Returning to the hover row rather than the collapsed pill when the cursor is
    /// still over the bar: collapsing under a stationary cursor leaves the row
    /// unreachable until the pointer leaves and comes back.
    func cancelInput() {
        switch state {
        case .inputBar:
            transition(to: panel.frame.contains(NSEvent.mouseLocation) ? .hoverRow : .pill)

        case .replyInput(let source, _):
            // Back to the armed bar, not the pill: the copy is still live and throwing
            // it away because someone pressed Escape means copying it again.
            //
            // Unlike the custom-input case above this deliberately does *not* care
            // whether the cursor is still over the bar. `.replyArmed` is the state
            // hovering opens the input box from, so re-opening it under a stationary
            // cursor is not a courtesy — it is a loop that Escape cannot break.
            transition(to: .replyArmed(source))

        case .pill, .hoverRow, .generating, .result, .replyArmed:
            return
        }
    }

    func submitInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch state {
        case .inputBar(let captured):
            guard !trimmed.isEmpty else { return }
            startRewrite(
                captured: captured,
                promptText: trimmed,
                replyTo: nil,
                buttonTitle: nil,
                commandKey: nil,
                promptOrigin: nil,
                isTutorial: tutorialMode?.marksCustomGuidance(trimmed) == true
            )

        case .replyInput(let source, let captured):
            // Empty is allowed here and blocked above. "Just write me a reply" is the
            // strongest case for reply mode, and the backend requires a non-empty
            // `prompt`, so the default instruction stands in for one.
            startRewrite(
                captured: captured,
                promptText: trimmed.isEmpty ? Self.defaultReplyInstruction : trimmed,
                replyTo: source.text,
                // Labels the ホーム history row. A reply has no button behind it and
                // 「カスタム」 would file it with the ✎ rewrites it is not.
                buttonTitle: "返信",
                commandKey: nil,
                promptOrigin: nil,
                isTutorial: tutorialMode?.marksReply == true
            )

        case .pill, .hoverRow, .generating, .result, .replyArmed:
            return
        }
    }

    // MARK: - Rewrite

    private func startRewrite(
        captured: CapturedTarget,
        promptText: String,
        replyTo: String?,
        buttonTitle: String?,
        commandKey: String?,
        promptOrigin: String?,
        isTutorial: Bool
    ) {
        if isTutorial { lastHistoryEntryId = nil }
        let pending = PendingRewrite(
            captured: captured,
            promptText: promptText,
            replyTo: replyTo,
            buttonTitle: buttonTitle,
            isTutorial: isTutorial,
            startedAt: Date()
        )
        transition(to: .generating(request: pending))

        // In reply mode the three text fields mean something different, and the
        // backend's own branch (`systemInstructions`, `isReply`) is what defines it:
        // `replyTo` is the message received, `text` is the user's own draft in the
        // field they are about to write into — usually empty, which the backend
        // handles explicitly — and `prompt` is the instruction they typed.
        let request = RewriteRequest(
            prompt: promptText,
            text: captured.target.text,
            replyTo: replyTo,
            commandKey: commandKey,
            title: buttonTitle,
            promptOrigin: promptOrigin,
            appVersion: appVersion,
            // One candidate, not the model's default 3. The phone shows a picker
            // and needs alternatives to pick between; the desktop writes back in
            // place, so the other two are generated, billed (`reserveUsage` counts
            // units by candidate) and thrown away. Overridden here rather than in
            // `RewriteRequest` because that type is a copied contract shared with
            // the iOS repo (§3) and its default must not drift.
            candidateCount: 1,
            selection: captured.target.captureMode == .selection,
            selectionContextBefore: captured.target.contextBefore,
            selectionContextAfter: captured.target.contextAfter,
            hostAppBundleId: captured.target.hostAppBundleId,
            captureMode: captured.target.captureMode,
            browserURL: captured.target.browserURL,
            ioPath: captured.target.path.rawValue
        )

        rewriteTask?.cancel()
        rewriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.rewriteService.rewrite(request)
                guard !Task.isCancelled else { return }
                let latencyMs = Int(Date().timeIntervalSince(pending.startedAt) * 1000)
                self.analytics.rewriteCompleted(
                    target: captured.target,
                    promptOrigin: promptOrigin,
                    isReply: replyTo != nil,
                    candidateCount: result.candidates.count,
                    latencyMs: latencyMs
                )
                if !pending.isTutorial {
                    await self.record(pending: pending, result: result)
                }
                self.transition(to: .result(
                    ResultContext(pending: pending, result: result, selectedIndex: 0)
                ))
            } catch {
                guard !Task.isCancelled else { return }
                self.present(error)
            }
        }
    }

    func cancelRewrite() {
        rewriteTask?.cancel()
        rewriteTask = nil
        transition(to: .pill)
    }

    /// Awaited before the result panel appears rather than fired and forgotten: the
    /// id it returns is what `insert()` marks accepted, and the user can press Insert
    /// the instant the panel lands.
    ///
    /// A nil return means history is switched off, which is also why `insert()` guards
    /// on the id rather than assuming one exists.
    private func record(pending: PendingRewrite, result: RewriteResult) async {
        guard let candidate = result.candidates.first else { return }
        lastHistoryEntryId = await history.record(
            RewriteHistoryEntry(
                buttonTitle: pending.buttonTitle,
                promptText: pending.promptText,
                // For a reply the interesting "before" is the message being replied
                // to, not the user's draft — which is usually the empty compose box
                // and would file the row under a blank original.
                originalText: pending.replyTo ?? pending.captured.target.text,
                rewrittenText: candidate.replacement,
                hostAppBundleId: pending.captured.target.hostAppBundleId
            )
        )
    }

    // MARK: - Result actions

    func selectCandidate(offsetBy delta: Int) {
        guard case .result(var context) = state else { return }
        let next = context.selectedIndex + delta
        guard context.result.candidates.indices.contains(next) else { return }
        context.selectedIndex = next
        transition(to: .result(context))
    }

    /// Writes the accepted candidate back, then dismisses.
    func insert() {
        guard case .result(let context) = state, let candidate = context.candidate else { return }
        let captured = context.pending.captured

        // Get our windows out of the way BEFORE touching the target app. The write may
        // escalate to a synthesized ⌘V, and ⌘V goes to whatever window is key — which
        // would be this result panel. `prompt/`'s insert handler calls `hideOverlay`
        // before `activateApp` for exactly this reason.
        dismissResultPanel()
        panel.acceptsKey = false

        Task { [weak self] in
            guard let self else { return }
            do {
                // The write puts the rewrite on the pasteboard and restores the
                // original afterwards whenever it escalates to ⌘V.
                ClipboardWatcher.suspend()
                try await self.textIO.write(
                    candidate.replacement,
                    to: captured.target,
                    frontmostPID: captured.frontmostPID
                )
                ClipboardWatcher.resume()
                self.analytics.inserted(
                    target: captured.target,
                    isReply: context.pending.replyTo != nil,
                    selectedIndex: context.selectedIndex
                )
                // Only marked once the write actually landed — the catch below is a
                // real path, and a history row claiming 挿入済み over text that never
                // arrived would be the list's one unreliable field.
                if !context.pending.isTutorial, let entryId = self.lastHistoryEntryId {
                    await self.history.markAccepted(id: entryId)
                }
                if let eventId = context.result.eventId {
                    try? await self.rewriteService.submitSelection(
                        eventId: eventId,
                        selectedIndex: context.selectedIndex
                    )
                }
                let tutorialCompletion = context.pending.isTutorial ? self.tutorialInserted : nil
                if context.pending.isTutorial {
                    self.tutorialPrompts = []
                    self.tutorialInserted = nil
                    self.tutorialMode = nil
                }
                // The reply has been sent where it was going, so the copy behind it is
                // spent. Cancelling the clock as well keeps a late expiry from firing
                // over whatever the bar is doing minutes from now.
                self.replyExpiryTask?.cancel()
                self.replyExpiryTask = nil
                self.transition(to: .pill)
                tutorialCompletion?()
            } catch {
                ClipboardWatcher.resume()
                // The panel was already dismissed to get out of ⌘V's way, so a failure
                // here would otherwise throw the rewrite away. Leave it on the
                // clipboard and say so — the same recovery `prompt/` offers when its
                // paste fails — then put the panel back so nothing is lost.
                ClipboardWatcher.writingOurselves {
                    SystemPasteboard().write(candidate.replacement)
                }
                self.presentResultPanel(context)
                self.present(
                    message: "挿入できませんでした。文章をクリップボードにコピーしました。元の入力欄で ⌘V を押して貼り付けてください。"
                )
            }
        }
    }

    func copyToClipboard() {
        guard case .result(let context) = state, let candidate = context.candidate else { return }
        // Unsuppressed, this is the one that would arm reply mode with the app's own
        // output and offer to write a reply to a rewrite.
        ClipboardWatcher.writingOurselves {
            SystemPasteboard().write(candidate.replacement)
        }
        sendAction("copy", context: context)
    }

    /// - Parameter promptText: the possibly-edited prompt from the result panel's echo
    ///   field. Nil re-runs the original — that is the ↻ button. Passing the edited
    ///   text is what makes the field actually editable rather than decorative.
    func regenerate(promptText: String? = nil) {
        guard case .result(let context) = state else { return }
        sendAction("regenerate", context: context)
        let pending = context.pending
        startRewrite(
            captured: pending.captured,
            promptText: promptText ?? pending.promptText,
            // Carried forward. Dropping it would turn ↻ on a reply into a rewrite of
            // the user's draft, which for the usual empty compose box is a rewrite of
            // nothing at all.
            replyTo: pending.replyTo,
            buttonTitle: pending.buttonTitle,
            commandKey: nil,
            promptOrigin: nil,
            isTutorial: pending.isTutorial
        )
    }

    func vote(up: Bool) {
        guard case .result(let context) = state else { return }
        sendAction(up ? "thumbs_up" : "thumbs_down", context: context)
    }

    private func sendAction(_ action: String, context: ResultContext) {
        guard let eventId = context.result.eventId else { return }
        Task { [rewriteService] in
            try? await rewriteService.submitAction(
                eventId: eventId,
                action: action,
                selectedIndex: context.selectedIndex,
                latencyMs: nil
            )
        }
    }

    func dismiss() {
        rewriteTask?.cancel()
        transition(to: .pill)
    }

    // MARK: - Transitions

    private func transition(to next: OverlayState) {
        let wasResult = { if case .result = state { return true } else { return false } }()
        let wasGenerating = { if case .generating = state { return true } else { return false } }()

        // The menu is anchored to `.pill` / `.hoverRow`, and every other state either
        // hides the bar outright or takes key away from it — either way, a state
        // change means the menu's own anchor is no longer the state it was opened
        // against.
        dismissSnoozeMenu()

        state = next

        // **Only work in progress clears the message.** This used to dismiss on every
        // transition, and the transition that follows a capture failure is the hover
        // row collapsing 300 ms after the pointer leaves the bar — which is the moment
        // the user's eye moves *to* the toast. So pressing a button in an app with no
        // editable field flashed an explanation and took it away again; the timeout was
        // never what anyone was reading against. A toast now stands until it times out,
        // is clicked, or is replaced by a rewrite actually starting.
        switch next {
        case .generating, .result: dismissErrorToast()
        case .pill, .hoverRow, .inputBar, .replyArmed, .replyInput: break
        }

        // Key-ness is opened before the window is asked to take key, and closed
        // before anything else happens, so there is never a moment where a
        // non-input state could accept focus.
        panel.acceptsKey = next.wantsKeyWindow

        // The capsule and the result panel stand in for the bar rather than sitting
        // above it, so the hand-off is ordered to keep something on the bottom edge at
        // every instant: the bar returns *before* they leave, and leaves *after* they
        // arrive. Its frame stays valid while hidden — that is what they anchor to.
        if next.showsPill { setPillVisible(true) }

        switch next {
        case .pill, .hoverRow, .inputBar, .replyArmed, .replyInput:
            if wasGenerating { dismissGeneratingPanel() }
            if wasResult { dismissResultPanel() }
            if next.wantsKeyWindow { panel.makeKey() }

        case .generating(let pending):
            if wasResult { dismissResultPanel() }
            presentGeneratingPanel(pending)

        case .result(let context):
            if wasGenerating { dismissGeneratingPanel() }
            presentResultPanel(context)
        }

        if !next.showsPill { setPillVisible(false) }

        // Stacked above the bar rather than replacing it — the one other thing that
        // does this is the error toast. Ordered after the bar is visible so the card
        // has a valid frame to anchor to, and before `applyMeasuredSize`, which calls
        // `resize` and therefore re-anchors it against the bar's final height.
        syncReplyContextPanel(for: next)

        // Height comes from the new state, width from the last measurement. If the
        // content's width also changed, `contentWidthChanged` supersedes this within
        // the same layout pass; this call is what makes a height-only change (hover
        // row → input bar, same width) still apply.
        applyMeasuredSize()
    }

    /// SwiftUI's measured content size, reported up from `PillRootView`.
    private var measuredSize: CGSize?
    /// What the window frame was last set to, so a measurement that changes nothing
    /// does not restart the animation.
    private var lastAppliedSize: NSSize?

    /// The single source of truth for the window's size.
    ///
    /// `NSHostingView` installs constraints from SwiftUI's intrinsic size and
    /// overrides any frame set behind its back, so the window has to follow the
    /// measurement rather than the reverse. `transition` deliberately does **not**
    /// resize: doing both meant one frame at the outgoing state's width — a 44 pt
    /// window holding a 267 pt row — before this corrected it.
    func contentSizeChanged(_ size: CGSize) {
        guard size.width > 1 else { return }
        measuredSize = size
        applyMeasuredSize()
    }

    private func applyMeasuredSize() {
        let size = currentSize()
        guard lastAppliedSize != size else {
            // **This early return is what broke the context pill twice.** `resize` is
            // the only thing that re-derives the pill's position from the bar, and a
            // transition that does not change the bar's measured size never reaches it
            // — so a pill created during that transition kept whatever frame the bar
            // had *before* the last resize. The bar is genuinely not moving here, but
            // the pill may still be anchored to a stale one (§16).
            replyContextPanel?.reanchor(to: panel.frame)
            return
        }
        lastAppliedSize = size
        resize(to: size, animated: true)
    }

    /// §4's 28/34 pt are a floor, not a fixed value — the input bar wraps and the
    /// window has to grow with it.
    private func currentSize() -> NSSize {
        NSSize(
            width: measuredSize?.width ?? Tokens.Geometry.pillCollapsedWidth,
            height: max(measuredSize?.height ?? 0, state.contentHeight)
        )
    }

    /// §4: expansion animates the **window frame**. Animating only the view clips it,
    /// because a borderless window does not draw outside its bounds.
    private func resize(to size: NSSize, animated: Bool) {
        let screen = OverlayPlacement.screen(containing: panel.frame)
        let target = OverlayPlacement.reframe(panel.frame, to: size, on: screen)

        // Against `target`, not `panel.frame`: the animated branch below has not moved
        // the bar yet, and a card that waited for the animation to finish would be
        // overlapped by the input bar's second line for the length of it.
        replyContextPanel?.reanchor(to: target)

        guard animated else {
            panel.setFrame(target, display: true)
            panel.invalidateShadow()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [panel] in
            // The window shadow is cached from the content's alpha channel; without
            // this the collapsed pill keeps wearing the expanded row's outline.
            panel.invalidateShadow()
        }
    }

    func persistPosition() {
        OverlayPlacement.persist(frame: panel.frame, on: OverlayPlacement.screen(containing: panel.frame))
        // The bar is draggable while the composer is open, and dragging moves the
        // window without going through `resize`.
        replyContextPanel?.reanchor(to: panel.frame)
    }

    private func setPillVisible(_ visible: Bool) {
        guard panel.isVisible != visible else { return }
        if visible {
            panel.orderFrontRegardless()
        } else {
            // A window that is ordered out sends no `mouseExited`, and the bar always
            // goes away under a stationary pointer — pressing a prompt pill is what
            // hides it. Without this the pointing hand stays on over the generating
            // capsule that takes its place.
            CursorStack.shared.releaseAll()
            panel.orderOut(nil)
        }
    }

    // MARK: - Auxiliary windows

    /// The card is up for **both** reply states, from the moment a copy arms.
    ///
    /// It used to appear only with the composer, which put the message on screen at the
    /// same instant the user started writing against it and not one moment earlier —
    /// so the armed bar still had to carry a truncated preview, and the handover
    /// between the two was the thing that flickered. Spanning both states means the
    /// card is created once, survives the hover, and the bar below it never has to
    /// describe its own contents.
    private func syncReplyContextPanel(for next: OverlayState) {
        guard let source = next.replySource else {
            replyContextPanel?.orderOut(nil)
            replyContextPanel = nil
            return
        }
        // Rebuilt only when the copy itself changes — the armed → composing transition
        // must not tear it down and put it back, which is exactly the flash it exists
        // to avoid.
        if let existing = replyContextPanel, existing.source == source {
            existing.reanchor(to: panel.frame)
            return
        }

        replyContextPanel?.orderOut(nil)
        let card = ReplyContextPanel(
            anchor: panel.frame,
            source: source,
            onDismiss: { [weak self] in self?.dismissReply() }
        )
        card.orderFrontRegardless()
        replyContextPanel = card
    }

    private func presentGeneratingPanel(_ pending: PendingRewrite) {
        dismissGeneratingPanel()
        let generating = GeneratingPanel(
            anchor: panel.frame,
            // **A progress word, not the button's name.** The capsule used to be
            // labelled with `buttonTitle`, so pressing 差し替え put 「差し替え」 on a
            // capsule that is not replacing anything yet — nothing has been written
            // back at this point and the rewrite may still fail. The one thing that is
            // true while it is on screen is that a candidate is being generated.
            label: pending.replyTo == nil ? "生成中" : "返信を生成中",
            onCancel: { [weak self] in self?.cancelRewrite() }
        )
        generating.orderFrontRegardless()
        generatingPanel = generating
    }

    private func dismissGeneratingPanel() {
        generatingPanel?.orderOut(nil)
        generatingPanel = nil
    }

    private func presentResultPanel(_ context: ResultContext) {
        if let existing = resultPanel {
            existing.update(context: context)
            return
        }
        let result = ResultPanel(anchor: panel.frame, controller: self, context: context)
        result.makeKeyAndOrderFront(nil)
        resultPanel = result
    }

    private func dismissResultPanel() {
        resultPanel?.orderOut(nil)
        resultPanel = nil
    }

    // MARK: - Errors

    private func present(_ error: Error) {
        if case RewriteError.notSignedIn = error {
            present(message: Self.message(for: error))
            onSignInRequired?()
            return
        }
        if case RewriteError.quotaExceeded(let denial) = error {
            presentQuotaDenial(denial)
            return
        }
        present(message: Self.message(for: error))
    }

    /// `docs/billing.md` §9 rows 41–43 — three cap-hit surfaces, and the whole point
    /// is that they are not one.
    ///
    /// - **Free user at 50** → the paywall. The user pressed a button and got nothing,
    ///   so the upgrade surface *is* the answer, and it opens on the プラン pane with
    ///   annual already selected (`PlanView`'s default, per pricing §4).
    /// - **Pro user at 1,000** → *not* a paywall. There is no tier above, so offering
    ///   one would be selling them what they already own.
    /// - **A brake** → its own message, because upgrading does not lift it. §6 keeps
    ///   the reason distinct in analytics for the same reason.
    ///
    /// Every branch carries the reset date. §4.5's finding is that the driver of
    /// billing support tickets is an invisible reset date rather than the lock, and
    /// the date is per-user — a Pro window resets on the subscription anchor, a free
    /// one on the 1st — so it can only come from the server.
    private func presentQuotaDenial(_ denial: QuotaDenial) {
        let reset = denial.resetsAt.map { "\(Self.resetFormatter.string(from: $0))にリセットされます。" }

        let message: String
        switch denial.reason {
        case .month where denial.plan == .free:
            message = [
                "今月の無料枠（\(denial.monthLimit ?? 50)回）を使い切りました。",
                reset,
            ].compactMap { $0 }.joined()
        case .month:
            message = ["今月の上限に達しました。", reset].compactMap { $0 }.joined()
        case .day, .hour, .minute:
            message = denial.message
        }

        present(message: message)
        if denial.offersUpgrade { onQuotaPaywall?() }
    }

    /// 「10月20日」 — the date alone. The hour is never the interesting part, and a
    /// timestamp in a toast reads as a system log rather than an answer.
    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    /// Every failure path ends here, including the ones that leave the state alone.
    ///
    /// A capture failure arrives while the state is `.hoverRow` or `.pill`, so the old
    /// `if case .generating` was the *only* branch and everything else set a message
    /// that went nowhere — pressing a button in an app with no editable field did
    /// nothing whatsoever.
    private func present(message: String) {
        analytics.failed(error: message)

        // Deliberately not `transition(to:)`: leaving `.generating` through it would
        // dismiss the toast this call is about to raise (see the switch there). The two
        // things it would otherwise do still have to happen.
        if case .generating = state {
            dismissGeneratingPanel()
            state = .pill
            setPillVisible(true)
            applyMeasuredSize()
        }
        showErrorToast(message)
    }

    private func showErrorToast(_ message: String) {
        dismissErrorToast()
        // Sits above whatever currently owns the bottom edge, which is not always the
        // bar — an insert failure happens with a 440 pt result card in its place, and
        // the reply composer stacks its context card on top of the bar (§16).
        let anchor = resultPanel?.frame
            ?? generatingPanel?.frame
            ?? replyContextPanel?.frame
            ?? panel.frame
        let toast = ErrorPanel(anchor: anchor, message: message) { [weak self] in
            self?.dismissErrorToast()
        }
        toast.orderFrontRegardless()
        errorPanel = toast

        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Tokens.Geometry.errorToastDuration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.dismissErrorToast()
        }
    }

    private func dismissErrorToast() {
        errorDismissTask?.cancel()
        errorDismissTask = nil
        errorPanel?.orderOut(nil)
        errorPanel = nil
    }

    private static func message(for error: Error) -> String {
        switch error {
        case TextIOError.notTrusted:
            return "アクセシビリティの許可が必要です。設定から許可してください。"
        case TextIOError.noTarget:
            return "書き換える文章が見つかりませんでした。文章を選択してもう一度お試しください。"
        case TextIOError.notEditable:
            return "この場所には書き戻せません。編集できる入力欄で試してください。"
        case TextIOError.writeFailed:
            return "書き戻しに失敗しました。もう一度お試しください。"
        case RewriteError.notSignedIn:
            return "サインインが必要です。アカウント画面からサインインしてください。"
        case RewriteError.rateLimited(let message), RewriteError.contentBlocked(let message),
             RewriteError.backend(let message):
            return message
        default:
            return "エラーが発生しました。もう一度お試しください。"
        }
    }
}
