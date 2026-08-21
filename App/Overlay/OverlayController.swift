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
    /// What Insert would do if it were pressed right now (§18). Re-read on a timer while
    /// the result panel is up, so the button is labelled with the truth rather than with
    /// what was true when the rewrite started.
    @Published private(set) var insertAction: InsertAction = .insert

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
    /// §18. Polled for the same reason `DockProbe` is: AX has nothing to subscribe to,
    /// and a caret moving to another field inside the same app posts no notification of
    /// any kind. Only alive while a result panel is on screen.
    private var destinationTracker: Timer?
    /// The probe is a cross-process AX call with a 0.5 s timeout and the poll runs at
    /// 0.5 s, so a beachballing target app would otherwise queue one behind another.
    private var destinationProbeInFlight = false
    /// Enter is bound to the primary button and the press now waits for a probe before
    /// it writes. Two presses inside that window would paste twice.
    private var insertInFlight = false
    /// A write that was attempted and failed. **The strongest evidence there is**, and
    /// stronger than any probe: the probe reasons about whether a destination is there,
    /// this is the destination refusing the text. It latches so the poll cannot put 挿入
    /// back and invite the user into the same dead end a second time, and it is cleared
    /// only by a new rewrite or a new result.
    private var destinationFailed = false
    /// Where the user's keyboard was, the last time that could honestly be asked (§18).
    ///
    /// **The probe cannot read this for itself, and that is what made the whole feature
    /// a no-op.** `ResultPanel` is key for its entire life — it has to be, Enter is bound
    /// to 挿入 — and §4 already recorded the consequence: while one of our windows holds
    /// key, `AXFocusedUIElement` points at our own field. So every live read the probe
    /// took answered "us", fell open to `.ready`, and 挿入 was offered with nothing
    /// focused anywhere; `.redirect` could not fire at all, so ✎-from-nothing always
    /// ended as コピー and pressing it tore the card down.
    ///
    /// So the reading is taken only from moments when we are *not* holding the keyboard
    /// — at capture, and from any poll that lands while the user is back in their own
    /// window — and kept. A reading that answered about us replaces nothing, which is
    /// exactly what lets 「click where it belongs, then press ここに挿入」 survive the
    /// click that hands key back to the panel.
    private var lastUserFocus: AXTextIO.UserFocus?
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

    // MARK: Update notice

    /// The version Sparkle has quietly found, while it is still worth announcing.
    /// `AppDelegate` sets it; `syncUpdateNoticePanel` decides whether a window for it is
    /// on screen right now. Held here rather than read from `PendingUpdateStore` on
    /// every sync because the bar is asked to re-anchor twice a second.
    private var pendingUpdateVersion: String?
    private var updateNoticePanel: UpdateNoticePanel?

    /// Pressed 「アップデート」 on the notice above the bar. Same destination as the
    /// dashboard card's own action — `AppDelegate` hands the already-selected update
    /// back to Sparkle, which keeps release notes, skip, verification and installation.
    var onUpdateRequested: (() -> Void)?

    /// Pressed ✕. Only this panel goes away, and only for this version.
    var onUpdateNoticeDismissed: ((String) -> Void)?

    // MARK: Reply mode (§16)

    private var clipboardWatcher: ClipboardWatcher?
    private var replyContextPanel: ReplyContextPanel?
    private var replyExpiryTask: Task<Void, Never>?
    /// Hover fires on re-entry and the capture is a cross-process AX call, so a
    /// cursor jittering on the bar's edge could otherwise start several.
    private var replyCaptureInFlight = false

    /// Stands in for the prompt when the user submits an empty reply instruction.
    /// "Just write me a reply" is the strongest case for this feature, and the backend
    /// rejects an empty `prompt` outright (`parseRequest`), so something has to be sent.
    private static var defaultReplyInstruction: String {
        tr(
            "この内容に自然に返信してください。",
            "Write a natural reply to this message.",
            "この内容に自然に返信してください。"
        )
    }

    /// Held while a regeneration replaces the result panel with the generating
    /// capsule. Success appends to it; cancel or failure restores it so trying another
    /// version never destroys the pages the user was comparing.
    private var resultContextBeforeRewrite: ResultContext?
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

    /// Sparkle's gate, decided by the state alone — see `OverlayState.allowsUpdateCheck`
    /// for which states rest and why refusing one is expensive.
    var allowsUpdateCheck: Bool {
        state.allowsUpdateCheck
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
        // Switching app is the loudest way to change where an Insert would land, and it
        // is the one change that *does* post a notification — so it is answered
        // immediately rather than up to half a poll later (§18).
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(focusedAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
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
        // First line of any log capture: which build is talking, and whether the one
        // permission everything depends on is actually granted.
        destinationLog.debug(
            "overlay show version=\(self.appVersion, privacy: .public) trusted=\(AXPermission.isTrusted, privacy: .public)"
        )

        // Decode the three tiny atlases before the panel is visible. Loading the
        // engaged atlas on the first hover used to occupy the main thread during the
        // same 160 ms in which AppKit was animating the window frame.
        MascotSprite.prewarmFrames()

        let hostingView = NSHostingView(rootView: PillRootView(controller: self))
        // The controller below is the sole owner of the window frame. Leaving
        // `.standardBounds` enabled lets NSHostingView reflect its new intrinsic size
        // into NSWindow while `resize` is animating that same frame.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
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
            syncUpdateNoticePanel(for: state)
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
            // The notice is anchored to the bar, so a hidden bar takes it down with it
            // and a returning bar brings it back — including across a relaunch, since
            // `AppDelegate` restores the pending version before `show()`.
            syncUpdateNoticePanel(for: state)
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
            // After `orderOut`, which is what `syncUpdateNoticePanel` reads.
            syncUpdateNoticePanel(for: state)
        }
    }

    /// The bar's own labels — 生成中, the signed-out row, the ✎ placeholder — come
    /// from `tr`, which reads a global that SwiftUI cannot observe. `objectWillChange`
    /// is the whole mechanism: every overlay view is built from this object, so one
    /// send redraws all of them. The window then follows on its own, because the row
    /// reports its measured width up through a preference (§4) and
    /// "Sign in to use your buttons" is not the width of
    /// 「サインインするとボタンが使えます」.
    func languageChanged() {
        objectWillChange.send()
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
                // Reply capture is intentionally not normal rewrite capture. If the
                // user copied by selecting the incoming message and has not clicked a
                // reply field yet, that selection is context — never their draft and
                // never an Insert destination. A selection inside an actual draft uses
                // the whole field because the backend returns a complete reply body.
                let target = try await self.textIO.captureReply(
                    frontmostPID: frontmostPID,
                    copiedMessage: source.text
                )
                await self.snapshotUserFocus()
                // The copy can expire, or be dismissed, while a slow AX call is out.
                guard case .replyArmed(let armed) = self.state, armed == source else { return }
                self.transition(to: .replyInput(
                    reply: source,
                    target: CapturedTarget(target: target, frontmostPID: frontmostPID)
                ))
            } catch {
                // Reply capture returns scratch for missing/non-text focus, leaving only
                // the permission failure here. That is not
                // hover-frequency noise — it is the one thing the user has to act on.
                self.present(error)
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
                // Still the user's keyboard at this point, which is the only moment the
                // question can be asked at all (§18) — the result panel that will need
                // the answer is the thing that makes it unaskable.
                await self.snapshotUserFocus()
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
    ///
    /// **This one never fails for want of a target (§18).** `allowEmpty` accepts the
    /// empty compose box someone has just clicked into, and `allowScratch` accepts
    /// having nothing focused at all — free text is a request in its own right, and the
    /// two rejections it used to end in were the same dead end reply mode had already
    /// been through in §16. What changes with the scope is the placeholder, which is the
    /// one thing the user reads before typing: an instruction like 「もっと丁寧に」 needs
    /// something to apply to, and only the field can say whether there is any.
    func pressCustomInput() {
        let frontmostPID = NSWorkspace.shared.frontmostPID

        Task { [weak self] in
            guard let self else { return }
            do {
                ClipboardWatcher.suspend()
                let target = try await self.textIO.capture(
                    frontmostPID: frontmostPID,
                    allowEmpty: true,
                    allowScratch: true
                )
                ClipboardWatcher.resume()
                // Before the transition: the input bar takes key, and from then on a
                // focus read answers about us (§18).
                await self.snapshotUserFocus()
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
                buttonTitle: tr("返信", "Reply", "回复"),
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
        requestText: String? = nil,
        replyTo: String?,
        buttonTitle: String?,
        commandKey: String?,
        promptOrigin: String?,
        isTutorial: Bool,
        previousResults: ResultContext? = nil
    ) {
        resultContextBeforeRewrite = previousResults
        // A regenerate keeps the result panel's pages, so the latch has to be released
        // explicitly — the new attempt deserves a fresh reading of where it can go.
        destinationFailed = false
        let requestText = requestText ?? captured.target.text
        let pending = PendingRewrite(
            captured: captured,
            requestText: requestText,
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
            text: requestText,
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
            ioPath: captured.target.path.rawValue,
            // The language the buttons write in, which is not the interface language:
            // a 简体中文 user reads Chinese and writes Japanese (§17). Read at send
            // time so a language changed mid-session takes effect on the next press.
            writingLanguage: AppLanguageState.current.writingLanguageCode
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
                let historyEntryId: UUID?
                if pending.isTutorial {
                    historyEntryId = nil
                } else {
                    historyEntryId = await self.record(pending: pending, result: result)
                }
                guard !Task.isCancelled else { return }

                var context = previousResults
                    ?? ResultContext(
                        pending: pending,
                        result: result,
                        historyEntryId: historyEntryId
                    )
                if previousResults != nil {
                    context.append(
                        pending: pending,
                        result: result,
                        historyEntryId: historyEntryId
                    )
                }
                self.resultContextBeforeRewrite = nil
                self.transition(to: .result(context))
            } catch {
                guard !Task.isCancelled else { return }
                if let previousResults {
                    self.resultContextBeforeRewrite = nil
                    self.transition(to: .result(previousResults))
                }
                self.present(error)
            }
        }
    }

    func cancelRewrite() {
        rewriteTask?.cancel()
        rewriteTask = nil
        if let previous = resultContextBeforeRewrite {
            resultContextBeforeRewrite = nil
            transition(to: .result(previous))
        } else {
            transition(to: .pill)
        }
    }

    /// Awaited before the result panel appears rather than fired and forgotten: the
    /// id it returns is what `insert()` marks accepted, and the user can press Insert
    /// the instant the panel lands.
    ///
    /// A nil return means history is switched off, which is also why `insert()` guards
    /// on the id rather than assuming one exists.
    private func record(pending: PendingRewrite, result: RewriteResult) async -> UUID? {
        guard let candidate = result.candidates.first else { return nil }
        return await history.record(
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

    func selectResult(offsetBy delta: Int) {
        guard case .result(var context) = state else { return }
        let next = context.selectedIndex + delta
        guard context.pages.indices.contains(next) else { return }
        context.selectedIndex = next
        transition(to: .result(context))
    }

    // MARK: - Where Insert lands (§18)

    /// Polled while the result panel is up. The whole value of it is that the button is
    /// labelled before it is pressed — a result that can only be copied used to offer
    /// 挿入 and write the text into nothing.
    ///
    /// **Polled rather than subscribed, and the reason given for that was wrong.** §18
    /// claimed a caret moving between fields posts no notification and there was nothing
    /// to subscribe to; `kAXFocusedUIElementChangedNotification` on an `AXObserver`
    /// attached to the frontmost app is exactly that notification. It is not what was
    /// missing, though — an observer would have reported the same thing the live read
    /// did, which is that *we* hold the keyboard. What the poll is actually for now is
    /// catching the moments when we **don't**, so `refreshUserFocus` can take a reading
    /// worth keeping. An observer remains the better instrument for the same job and is
    /// worth doing once this is confirmed on screen.
    ///
    /// Cheap enough to run at the position tracker's cadence: a handful of attribute
    /// reads, no keystrokes, nothing on the main thread.
    private func seedInsertAction(from captured: CapturedTarget?) {
        // This must happen before `ResultPanel` is constructed. A scratch result is the
        // only path that changes the initial layout from Insert to Copy; doing it after
        // the panel was ordered front made its first SwiftUI layout structurally mutate
        // while AppKit was presenting the window.
        insertAction = (captured?.target.hasDestination ?? true) ? .insert : .copyOnly
    }

    private func startDestinationTracking() {
        destinationTracker?.invalidate()
        refreshInsertAction()
        destinationTracker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Ahead of the probe, and outside its guards: after a failed insert
                // `destinationFailed` latches and `refreshInsertAction` returns at once,
                // so the whole timer went quiet — which is precisely the window in which
                // the card was reported vanishing with nothing on record.
                self?.ensureResultSurfaceVisible()
                self?.refreshInsertAction()
            }
        }
    }

    /// A result panel that stopped being on screen without anybody dismissing it.
    ///
    /// `dismissResultPanel` and `transition` both trace, so a card that goes away with
    /// neither line in the log was ordered out by AppKit rather than by us — and that is
    /// a different bug with a different fix. Logged once per disappearance so a 0.5 s
    /// timer cannot fill the stream.
    private var reportedResultPanelGone = false

    private func ensureResultSurfaceVisible() {
        guard case .result = state else { return }
        guard let card = resultPanel else {
            // `.result` without its window is an invalid state, but the recovery must
            // not depend on explaining how it happened. Keep the durable surface up.
            setPillVisible(true)
            return
        }
        guard !card.isVisible else {
            reportedResultPanelGone = false
            // A fallback pill may have been raised while AppKit was restoring the card.
            // Once the result is back, it resumes owning the bottom edge.
            if panel.isVisible { setPillVisible(false) }
            return
        }
        if !reportedResultPanelGone {
            reportedResultPanelGone = true
            destinationLog.debug(
                "result panel vanished unasked state=\(self.state.name, privacy: .public) frame=\(NSStringFromRect(card.frame), privacy: .public) key=\(card.isKeyWindow, privacy: .public) failed=\(self.destinationFailed, privacy: .public)"
            )
        }
        // Never leave the product with no surface. Keep trying on every tick because a
        // transient Space/app transition can outlive one attempt. If AppKit still
        // declines to show the card, the pill is the durable fallback and gives the
        // user a way to recover without quitting.
        card.orderFrontRegardless()
        if card.isVisible {
            setPillVisible(false)
        } else {
            setPillVisible(true)
        }
    }

    private func stopDestinationTracking() {
        destinationTracker?.invalidate()
        destinationTracker = nil
        destinationFailed = false
        insertAction = .insert
    }

    @objc private func focusedAppChanged() {
        // Guarded inside: this fires on every app switch, and only a result on screen
        // has anything to re-read.
        refreshInsertAction()
    }

    private func refreshInsertAction() {
        guard case .result(let context) = state, let page = context.selectedPage else { return }
        guard !destinationFailed, !destinationProbeInFlight, !insertInFlight else { return }
        destinationProbeInFlight = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.destinationProbeInFlight = false }
            let resolved = await self.resolveDestination(for: page.pending.captured)
            // The probe is a cross-process call and the panel can be dismissed while it
            // is out.
            guard case .result = self.state else { return }
            self.insertAction = Self.insertAction(for: resolved.verdict)
        }
    }

    private func resolveDestination(
        for captured: CapturedTarget
    ) async -> (verdict: DestinationVerdict, redirect: TextTarget?) {
        await refreshUserFocus()
        return await textIO.resolveDestination(
            for: captured.target,
            capturedPID: captured.frontmostPID,
            userFocus: lastUserFocus
        )
    }

    /// Takes a live reading, and decides what it is worth (§18).
    ///
    /// - `.user` replaces the remembered reading. The ordinary case.
    /// - `.unaskable` replaces nothing. **Measured: this is what every reading taken at
    ///   the moment of the press looks like** — clicking the card makes us the AX-focused
    ///   application, so the press can never see the field the label was computed from.
    ///   Keeping the reading is the entire reason ここに挿入 can be pressed at all.
    /// - `.silent` is the one that has to be read carefully. The *same* app going quiet
    ///   is an app declining to answer and §18's rule is that silence never downgrades.
    ///   A **different** app owning the keyboard with nothing readable in it is not
    ///   silence about the old field, it is evidence the user has left it — clicking the
    ///   Desktop is the everyday case, and carrying a stale field through it is how
    ///   ここに挿入 would be offered for a window that is no longer there.
    private func refreshUserFocus() async {
        switch await textIO.readUserFocus(frontmostPID: NSWorkspace.shared.frontmostPID) {
        case .user(let focus):
            lastUserFocus = focus

        case .unaskable:
            break

        case .silent(let focusedAppPID):
            guard let cached = lastUserFocus, let focusedAppPID,
                  focusedAppPID != cached.focusedAppPID
            else { break }
            destinationLog.debug(
                "focus dropped movedTo=\(focusedAppPID, privacy: .public) was=\(cached.focusedAppPID.map(String.init) ?? "-", privacy: .public)"
            )
            lastUserFocus = nil
        }
    }

    /// Called at each capture, while the user's app still owns the keyboard and before
    /// any of our windows can take key — §4's ordering, used for a second purpose.
    ///
    /// Cleared first: a reading left over from the previous rewrite is about a field the
    /// user may have closed minutes ago, and `focusReadable: false` (which fails open to
    /// 挿入) is the honest answer when this one cannot be taken.
    private func snapshotUserFocus() async {
        lastUserFocus = nil
        await refreshUserFocus()
    }

    private static func insertAction(for verdict: DestinationVerdict) -> InsertAction {
        switch verdict {
        case .ready: return .insert
        case .redirect: return .insertHere
        case .unavailable: return .copyOnly
        }
    }

    /// Writes the accepted candidate back, then dismisses.
    ///
    /// **The destination is resolved here, not read off the poll.** The label the user
    /// pressed is at most half a second old, which is fine for a label and not fine for
    /// the press that replaces text in someone's document — and it is the same reason §4
    /// re-derives `anchorY` instead of carrying it over.
    /// - Parameter intent: what the button *said* when it was pressed. `.copy` is
    ///   honoured literally and never writes: the label is frozen while the pointer is
    ///   over it, so a probe that changed its mind in the meantime must not turn a press
    ///   on コピー into text appearing in somebody's document. `.write` still re-resolves,
    ///   because there the safe answer is the one the probe gives, not the one on the
    ///   button.
    func insert(intent: InsertIntent = .write) {
        guard case .result(let context) = state, let page = context.selectedPage else { return }
        guard !insertInFlight else { return }
        guard intent == .write else {
            // No probe runs on this branch, so without this line the press leaves no
            // trace at all and the card simply vanishes from the log's point of view.
            destinationLog.debug(
                "insert pressed intent=copy label=\(String(describing: self.insertAction), privacy: .public)"
            )
            copyInstead(page: page, reason: .noDestination)
            return
        }
        insertInFlight = true
        let captured = page.pending.captured
        destinationLog.debug(
            "insert pressed intent=write label=\(String(describing: self.insertAction), privacy: .public)"
        )

        // Deliberately not cleared when this task returns: `writeBack` starts a task of
        // its own and comes back immediately, so a `defer` here would reopen the door
        // while the ⌘V was still in the air.
        Task { [weak self] in
            guard let self else { return }
            let resolved = await self.resolveDestination(for: captured)
            guard case .result = self.state else {
                self.insertInFlight = false
                return
            }
            self.insertAction = Self.insertAction(for: resolved.verdict)

            switch resolved.verdict {
            case .ready:
                self.writeBack(
                    page: page,
                    context: context,
                    to: captured.target,
                    frontmostPID: captured.frontmostPID,
                    destination: .insert
                )

            case .redirect:
                guard let redirect = resolved.redirect else {
                    self.copyInstead(page: page, reason: .noDestination)
                    return
                }
                self.writeBack(
                    page: page,
                    context: context,
                    to: redirect,
                    // The app to reactivate, not the element's process: web content and
                    // helper processes own the focused element in Chromium and Electron,
                    // and `NSRunningApplication` cannot activate one of those.
                    //
                    // Taken from the reading the redirect came from, not read fresh:
                    // pressing the button hands key to the result panel, so "frontmost
                    // now" is a different question than "the app that field is in".
                    frontmostPID: self.lastUserFocus?.frontmostPID ?? NSWorkspace.shared.frontmostPID,
                    destination: .insertHere
                )

            case .unavailable:
                self.copyInstead(page: page, reason: .noDestination)
            }
        }
    }

    /// - Parameter target: where the text goes, which is not always where it came from.
    ///   A redirect writes at the caret in the field the user is in now, and carries
    ///   `.selection` for that reason — see `TextTarget.redirect`.
    private func writeBack(
        page: ResultPage,
        context: ResultContext,
        to target: TextTarget,
        frontmostPID: pid_t?,
        destination: InsertAction
    ) {
        let candidate = page.candidate
        let pending = page.pending

        // Get the *card* out of the way BEFORE touching the target app. The write may
        // escalate to a synthesized ⌘V, and ⌘V goes to whatever window is key — which
        // would be this result panel. `prompt/`'s insert handler calls `hideOverlay`
        // before `activateApp` for exactly this reason.
        dismissResultPanel()
        // **But the bar stays.** `.result` hides the pill (`showsPill`), and this runs
        // without a state change, so dismissing the card used to leave the screen with
        // nothing on it at all until the write finished — 0.5–1 s of clipboard settle and
        // paste verification, and longer behind the feedback POST that used to be awaited
        // below. "I pressed 挿入 and the whole button disappeared" was this, not the write.
        // It cannot intercept the paste: `acceptsKey` is false, so `canBecomeKey` is too.
        setPillVisible(true)
        panel.acceptsKey = false

        Task { [weak self] in
            guard let self else { return }
            do {
                // The write puts the rewrite on the pasteboard and restores the
                // original afterwards whenever it escalates to ⌘V.
                ClipboardWatcher.suspend()
                try await self.textIO.write(
                    candidate.replacement,
                    to: target,
                    frontmostPID: frontmostPID
                )
                ClipboardWatcher.resume()
                // Reported against the target that was *captured*, because that is what
                // `capture_mode` and `io_path` describe. `insert_destination` is the new
                // field and the one that says whether the rewrite went home or somewhere
                // the user pointed it afterwards.
                self.analytics.inserted(
                    target: pending.captured.target,
                    isReply: pending.replyTo != nil,
                    selectedIndex: page.responseCandidateIndex,
                    destination: destination
                )
                // Only marked once the write actually landed — the catch below is a
                // real path, and a history row claiming 挿入済み over text that never
                // arrived would be the list's one unreliable field.
                if !pending.isTutorial, let entryId = page.historyEntryId {
                    await self.history.markAccepted(id: entryId)
                }
                // Detached, like `copyInstead`'s `submitAction`. Awaited here it sat
                // directly in front of `transition(to: .pill)` with a 10 s request
                // timeout, so a bad network kept the whole overlay off screen for as
                // long as it took to fail.
                if let eventId = page.eventId {
                    Task { [rewriteService] in
                        try? await rewriteService.submitSelection(
                            eventId: eventId,
                            selectedIndex: page.responseCandidateIndex
                        )
                    }
                }
                destinationLog.debug(
                    "insert landed destination=\(String(describing: destination), privacy: .public)"
                )
                let tutorialCompletion = pending.isTutorial ? self.tutorialInserted : nil
                if pending.isTutorial {
                    self.tutorialPrompts = []
                    self.tutorialInserted = nil
                    self.tutorialMode = nil
                }
                // The reply has been sent where it was going, so the copy behind it is
                // spent. Cancelling the clock as well keeps a late expiry from firing
                // over whatever the bar is doing minutes from now.
                self.replyExpiryTask?.cancel()
                self.replyExpiryTask = nil
                self.insertInFlight = false
                self.transition(to: .pill)
                tutorialCompletion?()
            } catch {
                ClipboardWatcher.resume()
                destinationLog.debug(
                    "insert failed destination=\(String(describing: destination), privacy: .public) strategy=\(target.writeStrategy.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                self.insertInFlight = false
                // The write is the only witness that cannot be argued with. Whatever the
                // probe believed, this destination just refused the text, so the panel
                // comes back offering the action that will work rather than the one that
                // has now failed once.
                self.destinationFailed = true
                self.insertAction = .copyOnly
                // The panel was already dismissed to get out of ⌘V's way, so a failure
                // here would otherwise throw the rewrite away. Leave it on the
                // clipboard and say so — the same recovery `prompt/` offers when its
                // paste fails — then put the panel back so nothing is lost.
                ClipboardWatcher.writingOurselves {
                    SystemPasteboard().write(candidate.replacement)
                }
                // The card is coming back, and `.result` is a state the bar stands down
                // for — undoing the `setPillVisible(true)` above rather than stacking the
                // two on the same bottom edge.
                self.presentResultPanel(context)
                self.setPillVisible(false)
                self.present(
                    message: tr(
                        "挿入できませんでした。文章をクリップボードにコピーしました。入力欄で ⌘V を押して貼り付けてください。",
                        "Couldn't insert it. The text is on your clipboard — press ⌘V in the field you want it in.",
                        "无法插入。文本已复制到剪贴板，请在输入框中按 ⌘V 粘贴。"
                    )
                )
            }
        }
    }

    /// The Insert that is a Copy, because there is nowhere to insert (§18).
    ///
    /// Reached from the button the user pressed while it said コピー, so this is not a
    /// consolation prize — it is the action they chose, and the toast says what to do
    /// with it rather than apologising. History is deliberately **not** marked accepted:
    /// 挿入済み means the text reached the field, and a copy has not (§14).
    private func copyInstead(page: ResultPage, reason: CopyReason) {
        destinationLog.debug("copyInstead reason=\(String(describing: reason), privacy: .public)")
        let pending = page.pending
        ClipboardWatcher.writingOurselves {
            SystemPasteboard().write(page.candidate.replacement)
        }
        analytics.copied(
            target: pending.captured.target,
            isReply: pending.replyTo != nil,
            reason: reason
        )
        if let eventId = page.eventId {
            Task { [rewriteService] in
                try? await rewriteService.submitAction(
                    eventId: eventId,
                    action: "copy",
                    selectedIndex: page.responseCandidateIndex,
                    latencyMs: nil
                )
            }
        }

        // A tutorial rewrite with nowhere to land still finished. Withholding the step
        // would leave first-run stuck on a screen waiting for an insert that this
        // machine cannot perform.
        let tutorialCompletion = pending.isTutorial ? tutorialInserted : nil
        if pending.isTutorial {
            tutorialPrompts = []
            tutorialInserted = nil
            tutorialMode = nil
        }
        replyExpiryTask?.cancel()
        replyExpiryTask = nil
        insertInFlight = false
        transition(to: .pill)
        present(
            notice: tr(
                "コピーしました。貼り付けたい場所で ⌘V を押してください。",
                "Copied. Press ⌘V where you want it.",
                "已复制。请在要粘贴的位置按 ⌘V。"
            )
        )
        tutorialCompletion?()
    }

    func copyToClipboard() {
        guard case .result(let context) = state, let candidate = context.candidate else { return }
        // Unsuppressed, this is the one that would arm reply mode with the app's own
        // output and offer to write a reply to a rewrite.
        ClipboardWatcher.writingOurselves {
            SystemPasteboard().write(candidate.replacement)
        }
        if let page = context.selectedPage {
            analytics.copied(
                target: page.pending.captured.target,
                isReply: page.pending.replyTo != nil,
                reason: .userChose
            )
        }
        sendAction("copy", context: context)
    }

    /// - Parameter promptText: the possibly-edited prompt from the result panel's echo
    ///   field. Nil re-runs the original — that is the ↻ button. Passing the edited
    ///   text is what makes the field actually editable rather than decorative.
    func regenerate(promptText: String? = nil) {
        guard case .result(let context) = state, let page = context.selectedPage else { return }
        sendAction("regenerate", context: context)
        let pending = page.pending
        startRewrite(
            captured: pending.captured,
            promptText: promptText ?? pending.promptText,
            requestText: pending.requestText,
            // Carried forward. Dropping it would turn ↻ on a reply into a rewrite of
            // the user's draft, which for the usual empty compose box is a rewrite of
            // nothing at all.
            replyTo: pending.replyTo,
            buttonTitle: pending.buttonTitle,
            commandKey: nil,
            promptOrigin: nil,
            isTutorial: pending.isTutorial,
            previousResults: context
        )
    }

    /// Applies a one-off instruction to the candidate currently on screen. The
    /// candidate becomes the model's source text, while `pending.captured` remains the
    /// destination for Insert. In reply mode the same value becomes the existing draft,
    /// which is exactly the backend's refinement path for a composed reply.
    func refine(instruction: String) {
        guard case .result(let context) = state, let page = context.selectedPage else { return }
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        sendAction("regenerate", context: context)
        let pending = page.pending
        startRewrite(
            captured: pending.captured,
            promptText: instruction,
            requestText: page.candidate.replacement,
            replyTo: pending.replyTo,
            buttonTitle: pending.buttonTitle,
            commandKey: nil,
            promptOrigin: nil,
            isTutorial: pending.isTutorial,
            previousResults: context
        )
    }

    func vote(up: Bool) {
        guard case .result(let context) = state else { return }
        sendAction(up ? "thumbs_up" : "thumbs_down", context: context)
    }

    private func sendAction(_ action: String, context: ResultContext) {
        guard let page = context.selectedPage, let eventId = page.eventId else { return }
        Task { [rewriteService] in
            try? await rewriteService.submitAction(
                eventId: eventId,
                action: action,
                selectedIndex: page.responseCandidateIndex,
                latencyMs: nil
            )
        }
    }

    func dismiss() {
        destinationLog.debug("dismiss state=\(self.state.name, privacy: .public)")
        rewriteTask?.cancel()
        resultContextBeforeRewrite = nil
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

        // Every state change, named. "The card vanished and nothing said why" is what
        // two rounds of §18 were spent guessing at, and one line of this settles who
        // tore it down. Case names only — the associated values hold the user's text.
        destinationLog.debug(
            "transition \(self.state.name, privacy: .public) -> \(next.name, privacy: .public)"
        )
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
            stopDestinationTracking()
            if next.wantsKeyWindow { panel.makeKey() }

        case .generating(let pending):
            if wasResult { dismissResultPanel() }
            stopDestinationTracking()
            presentGeneratingPanel(pending)

        case .result(let context):
            // Configure the result's first layout before constructing its window. The
            // scratch path is Copy on first paint; presenting an Insert layout and then
            // adding the Copy notice was the only structural mutation during handoff.
            if !wasResult { seedInsertAction(from: context.selectedPage?.pending.captured) }
            presentResultPanel(context)
            // The new surface is ordered before the thinking capsule leaves, so there is
            // never a frame in which both the old and new owners are absent.
            if wasGenerating { dismissGeneratingPanel() }
            // Not restarted when only the pager moved: every page of one context shares
            // the captured target, so re-probing would blink the button back to 挿入 on
            // the way past a result the poll has already said cannot be inserted.
            if !wasResult { startDestinationTracking() }
        }

        if !next.showsPill {
            if case .result = next, resultPanel?.isVisible != true {
                // A failed window handoff must never strand the app in `.result` with
                // both surfaces ordered out. The tracker will keep trying the card.
                setPillVisible(true)
            } else {
                setPillVisible(false)
            }
        }

        // Stacked above the bar rather than replacing it — the one other thing that
        // does this is the error toast. Ordered after the bar is visible so the card
        // has a valid frame to anchor to, and before `applyMeasuredSize`, which calls
        // `resize` and therefore re-anchors it against the bar's final height.
        syncReplyContextPanel(for: next)
        // After `syncReplyContextPanel`, which owns the same 8 pt above the bar in the
        // reply states — the notice stands down rather than stacking on it.
        syncUpdateNoticePanel(for: next)

        // Do not resize from the outgoing subtree's measurement. `PillRootView` tags
        // its preference with `contentLayout`, so even a height-only state change
        // reports one fresh measurement and starts one complete frame animation.
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
    func contentSizeChanged(_ size: CGSize, for layout: OverlayContentLayout) {
        guard layout == state.contentLayout, size.width > 1 else { return }
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
        updateNoticePanel?.reanchor(to: target)

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
        updateNoticePanel?.reanchor(to: panel.frame)
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

    /// Sparkle found `version` in the background. Shows the notice above the bar if the
    /// bar is in a state that can carry it, and remembers it either way — the bar spends
    /// most of its life resting, but a find can land while a result card is up.
    ///
    /// Passing `nil` withdraws the notice: the update was installed, skipped, or the
    /// user brought Sparkle's own window forward and it now owns the conversation.
    func setPendingUpdate(_ version: String?) {
        guard pendingUpdateVersion != version else { return }
        pendingUpdateVersion = version
        syncUpdateNoticePanel(for: state)
    }

    /// On screen only while the bar itself is, and only in the states that leave the
    /// space above it free. `.generating` and `.result` **replace** the bar rather than
    /// stacking on it (§4), so there is nothing to anchor to; the reply states already
    /// own that space with `ReplyContextPanel`, and two panels 8 pt above the same bar
    /// would be one on top of the other.
    private func syncUpdateNoticePanel(for next: OverlayState) {
        let wanted = next.showsPill && next.replySource == nil && panel.isVisible
            ? pendingUpdateVersion
            : nil

        guard let wanted else {
            updateNoticePanel?.orderOut(nil)
            updateNoticePanel = nil
            return
        }

        // Rebuilt only when the version changes — re-anchoring on every hover keeps the
        // panel from blinking as the row expands beneath it.
        if let existing = updateNoticePanel, existing.version == wanted {
            existing.reanchor(to: panel.frame)
            return
        }

        updateNoticePanel?.orderOut(nil)
        let notice = UpdateNoticePanel(
            anchor: panel.frame,
            version: wanted,
            onUpdate: { [weak self] in self?.onUpdateRequested?() },
            onDismiss: { [weak self] in
                guard let self, let version = self.pendingUpdateVersion else { return }
                self.onUpdateNoticeDismissed?(version)
                self.setPendingUpdate(nil)
            }
        )
        notice.orderFrontRegardless()
        updateNoticePanel = notice
    }

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
            label: pending.replyTo == nil
                ? tr("生成中", "Writing…", "生成中")
                : tr("返信を生成中", "Replying…", "生成回复中"),
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
            existing.orderFrontRegardless()
            return
        }
        let result = ResultPanel(anchor: panel.frame, controller: self, context: context)
        resultPanel = result
        // Accessory apps are not necessarily active. Order independently of activation,
        // then take key for Enter/Escape without asking macOS to activate the app.
        result.orderFrontRegardless()
        result.makeKey()
        reportedResultPanelGone = false
        destinationLog.debug(
            "result panel presented visible=\(result.isVisible, privacy: .public) frame=\(NSStringFromRect(result.frame), privacy: .public)"
        )
    }

    private func dismissResultPanel() {
        if resultPanel != nil {
            destinationLog.debug("result panel dismissed state=\(self.state.name, privacy: .public)")
        }
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
        let reset = denial.resetsAt.map {
            let date = Self.resetFormatter.string(from: $0)
            return tr("\(date)にリセットされます。", " Resets on \(date).", "将于\(date)重置。")
        }

        let message: String
        switch denial.reason {
        case .month where denial.plan == .free:
            message = [
                tr(
                    "今月の無料枠（\(denial.monthLimit ?? PlanPricing.freeMonthlyRewrites)回）を使い切りました。",
                    "You've used this month's free \(denial.monthLimit ?? PlanPricing.freeMonthlyRewrites) rewrites.",
                    "本月的免费额度（\(denial.monthLimit ?? PlanPricing.freeMonthlyRewrites)次）已用完。"
                ),
                reset,
            ].compactMap { $0 }.joined()
        case .month:
            message = [
                tr("今月の上限に達しました。", "You've reached this month's limit.", "已达到本月上限。"),
                reset,
            ].compactMap { $0 }.joined()
        case .day, .hour, .minute:
            message = denial.message
        }

        present(message: message)
        if denial.offersUpgrade { onQuotaPaywall?() }
    }

    /// 「10月20日」 — the date alone. The hour is never the interesting part, and a
    /// timestamp in a toast reads as a system log rather than an answer.
    private static var resetFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageState.current.locale
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = tr("M月d日", "MMMM d", "M月d日")
        return formatter
    }

    /// Every failure path ends here, including the ones that leave the state alone.
    ///
    /// A capture failure arrives while the state is `.hoverRow` or `.pill`, so the old
    /// `if case .generating` was the *only* branch and everything else set a message
    /// that went nowhere — pressing a button in an app with no editable field did
    /// nothing whatsoever.
    /// A toast that is not a failure. Same window and same 8 s, deliberately — the only
    /// difference is that it does not report `desktop_rewrite_failed`, because a copy the
    /// user asked for is an ending, not an error (§18).
    private func present(notice: String) {
        showErrorToast(notice)
    }

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
        // bar — an insert failure happens with a result card in its place, and the reply
        // composer stacks its context card on top of the bar (§16).
        //
        // The **window**, not its frame: the result card is created at 440 pt and shrinks
        // to its measured height a pass later, so a rectangle taken here is a number that
        // was never true for longer than one layout (see `ErrorPanel`).
        let anchor: NSWindow = resultPanel
            ?? generatingPanel
            ?? replyContextPanel
            ?? panel
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
            return tr(
                "アクセシビリティの許可が必要です。設定から許可してください。",
                "KeigoButton needs Accessibility access. Grant it in System Settings.",
                "需要辅助功能权限。请在系统设置中授予。"
            )
        case TextIOError.noTarget:
            // Only a saved button can reach this now: ✎ and reply mode both accept
            // having nothing to work from (§18). So the message can be specific about
            // why — a button applies to text, and there is none — and name the control
            // that does not need any.
            return tr(
                "書き換える文章がありません。文章を選択するか、✎ から新しい文章を書いてください。",
                "There's no text to rewrite. Select some text, or use ✎ to write something new.",
                "没有可改写的文字。请选中文字，或用 ✎ 写一段新文字。"
            )
        case TextIOError.notEditable:
            return tr(
                "この場所には書き戻せません。編集できる入力欄で試してください。",
                "Can't write back here. Try it in an editable text field.",
                "无法在此处写回。请在可编辑的输入框中尝试。"
            )
        case TextIOError.noDestination:
            return tr(
                "書き込める入力欄がありません。コピーして貼り付けてください。",
                "There's no field to write into. Copy it and paste it where you want it.",
                "没有可写入的输入框。请复制后粘贴到需要的位置。"
            )
        case TextIOError.writeFailed:
            return tr(
                "書き戻しに失敗しました。もう一度お試しください。",
                "Writing the result back failed. Please try again.",
                "写回失败。请重试。"
            )
        case RewriteError.notSignedIn:
            return tr(
                "サインインが必要です。アカウント画面からサインインしてください。",
                "You need to sign in. Open the account page to sign in.",
                "需要登录。请在账户页面登录。"
            )
        case RewriteError.rateLimited(let message), RewriteError.contentBlocked(let message),
             RewriteError.backend(let message):
            return message
        default:
            return tr(
                "エラーが発生しました。もう一度お試しください。",
                "Something went wrong. Please try again.",
                "发生错误。请重试。"
            )
        }
    }
}
