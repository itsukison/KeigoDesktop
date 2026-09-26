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
    @Published private(set) var introPresentation: IntroPillPresentation?
    @Published private(set) var onboardingPassive = false
    @Published private(set) var introDragCue = 0
    private(set) var introDimmerVisible = false
    private var visibilityRequested = false
    private var introPlacementOverride: SnapZone?
    private var debugIntroPlacement = false
    var introDragInProgress: Bool { isDraggingBar || isAnimatingSnapLanding }

    @Published private(set) var lesson: OnboardingLesson?
    weak var onboardingWindow: NSWindow?
    private var lessonGuide: OnboardingGuidePanel?
    var lessonAnchors: [LessonAnchor: WeakLessonAnchor] = [:]

    func beginLesson(_ kind: OnboardingLesson.Kind, discovered: Bool = false) {
        lesson = OnboardingLesson(kind: kind, discovered: discovered)
        lessonGuide = OnboardingGuidePanel(controller: self)
        if let window = onboardingWindow, window.screen != panel.screen {
            let screen = OverlayPlacement.screen(containing: panel.frame)
            let area = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2,
                                          y: area.midY - window.frame.height / 2))
        }
        syncLessonGuide()
    }

    func lessonEvent(_ event: OnboardingLesson.Event, sessionID: UUID) {
        guard var current = lesson, current.id == sessionID else { return }
        current.receive(event, sessionID: sessionID)
        if current != lesson { lesson = current }
        syncLessonGuide()
    }

    private func lessonEvent(_ event: OnboardingLesson.Event) {
        guard let id = lesson?.id else { return }
        lessonEvent(event, sessionID: id)
    }

    func allowsLessonAction(_ action: OnboardingLesson.Action) -> Bool {
        !onboardingPassive && introPresentation == nil && (lesson?.allows(action) ?? true)
    }

    func guidanceChanged(_ text: String, sessionID: UUID?) {
        guard let sessionID else { return }
        lessonEvent(.guidanceChanged(nonempty: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), sessionID: sessionID)
    }

    func syncLessonGuide() { lessonGuide?.refresh() }

    var lessonGuideCanShow: Bool {
        lesson != nil && NSApp.isActive && onboardingWindow?.isVisible == true
            && onboardingWindow?.isOnActiveSpace == true
            && onboardingWindow?.isMiniaturized == false && !isDraggingBar
            && !isAnimatingSnapLanding && errorPanel == nil && !insertInFlight
    }

    var lessonBarFrame: NSRect { panel.frame }
    var lessonGuideObstacles: [NSRect] {
        [replyContextPanel, resultPanel, generatingPanel, errorPanel].compactMap {
            guard let window = $0, window.isVisible else { return nil }
            return window.frame
        }
    }

    func lessonAnchorFrame(_ anchor: LessonAnchor) -> NSRect? {
        if anchor == .bar { return panel.isVisible ? panel.frame : nil }
        guard let view = lessonAnchors[anchor]?.view, let window = view.window,
              window.isVisible else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
    private var activeAccount: String?
    private var accountRevision: UInt64 = 0
    @Published private(set) var prompts: [UserPrompt] = []
    @Published private(set) var promptsFailed = false
    private var promptRefreshID = UUID()
    private let promptStore: UserPromptRemoteStore
    private let auth: AuthService

    @Published private(set) var tutorialPrompts: [UserPrompt] = []
    /// Set when there is no usable session at all. The hover row answers this with a
    /// sign-in button rather than an apology.
    @Published private(set) var signedOut = false
    /// What Insert would do if it were pressed right now (§18). Re-read on a timer while
    /// the result panel is up, so the button is labelled with the truth rather than with
    /// what was true when the rewrite started.
    @Published private(set) var insertAction: InsertAction = .insert

    @Published private(set) var replySession: ReplySession?
    private var replyContextTask: Task<Void, Never>?
    private lazy var replyCapture = ReplyCaptureCoordinator()
    private var replyCaptureSource = "ax"
    private var replyFallbackReason: String?
    private var replyCaptureID: UUID?
    private var replyDiagnosticData: Data?
    private var replyLocalObservations: [ReplyNodeObservation] = []
    private var exportingReplyDiagnostics = false
    private var replyAppCategory = "other"
    private var tutorialReplySource: String?

    private let panel: PillPanel
    private var generatingPanel: GeneratingPanel?
    private var resultPanel: ResultPanel?

    private let textIO: TextIOCoordinator
    private let rewriteService: DesktopRewriteService
    private let analytics: Analytics
    private let history: RewriteHistoryStore
    private let appVersion: String

    private var collapseTask: Task<Void, Never>?
    private var rewriteTask: Task<Void, Never>?
    /// The generation currently in flight, or nil when none is.
    ///
    /// **This field is what enforces the funnel's one invariant: a `desktop_rewrite_started`
    /// is followed by exactly one of `completed`, `failed` or `abandoned`.** Every
    /// terminal report goes through `finishAttempt`, which reads this once and clears it,
    /// so a double report is a no-op and a dropped one is impossible as long as every
    /// exit from `.generating` calls it. `beginAttempt` abandons whatever was still here,
    /// which is how a second press while the first is generating gets recorded rather
    /// than silently overwriting an attempt that was already billed by the server.
    ///
    /// Post-generation events (`inserted`, `copied`) deliberately do NOT read this: they
    /// happen after the attempt is finished and report against `PendingRewrite.attempt`.
    ///
    /// The rule itself lives in `RewriteAttemptTracker` (and is tested there) rather than
    /// in this file, because `OverlayController` needs a window server and cannot be
    /// unit-tested at all.
    private var attempts = RewriteAttemptTracker()
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

    // MARK: Bar dragging (§4, docs/bar-positioning.md)

    private var barDragObserver: NSObjectProtocol?
    /// True from the first observed move with the button down until the drag ends.
    /// Everything else that moves the panel — resize animations, the snap landing —
    /// posts `didMove` too, and must not be read as the user's hand.
    @Published private(set) var isDraggingBar = false
    @Published private(set) var parkedZone = OverlayPlacement.savedZone() {
        didSet { errorPanel?.reanchor(zone: parkedZone) }
    }
    @Published private(set) var notchWidth: CGFloat = 0
    private var dragOriginScreen: NSScreen?
    private var dragEndTimer: Timer?
    /// The snap landing's own animation moves the panel; those moves are ours.
    private var isAnimatingSnapLanding = false
    private var activeSnapZone: SnapZone?
    private var snapOverlay: SnapOverlayPanel?

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
    /// Invalidates a late AX response after dismissal or a different action.
    private var clipboardReplyCaptureID: UUID?
    @Published private(set) var availableReplySource: ReplySource?

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
    private var tutorialInserted: ((OnboardingLesson.Completion) -> Void)?
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

    /// Fit ordinary names, cap unusually long ones, and avoid an empty gutter around
    /// the actual hit targets. Reply keeps room for its separate dismiss control.
    var sidebarButtonWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: Tokens.Overlay.labelMedium, weight: .medium)
        let longest = displayedPrompts.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 44
        let replyWidth = availableReplySource == nil ? CGFloat(0)
            : (tr("返信", "Reply", "回复") as NSString).size(withAttributes: [.font: font]).width + 42
        return max(replyWidth, min(108, max(56, ceil(longest) + 12)))
    }

    var buttonViewportSize: NSSize {
        let area = OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: panel.frame))
        if usesSidebarLayout {
            return NSSize(width: sidebarButtonWidth, height: min(max(32, CGFloat(displayedPrompts.count) * 40 - 8), max(32, area.height - 180)))
        }
        let width = displayedPrompts.reduce(CGFloat(0)) { value, prompt in
            value + (prompt.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: Tokens.Overlay.labelMedium)]).width + 32
        }
        return NSSize(width: min(max(100, width), max(100, area.width - 240)), height: 34)
    }

    var displayedPrompts: [UserPrompt] {
        tutorialPrompts.isEmpty ? prompts.enabledForHoverRow : tutorialPrompts.enabledForHoverRow
    }

    /// Sparkle's gate, decided by the state alone — see `OverlayState.allowsUpdateCheck`
    /// for which states rest and why refusing one is expensive.
    var allowsUpdateCheck: Bool {
        state.allowsUpdateCheck
    }

    init(
        rewriteService: DesktopRewriteService,
        auth: AuthService,
        promptStore: UserPromptRemoteStore,
        analytics: Analytics,
        history: RewriteHistoryStore,
        appVersion: String
    ) {
        self.rewriteService = rewriteService
        self.auth = auth
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
        notchWidth = OverlayPlacement.notchFrame(on: screen)?.width ?? 0
        panel.onDragEnded = { [weak self] in self?.endBarDrag() }

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
        // A drag is the one move of the panel that is not ours. `isMovableByWindowBackground`
        // does the moving and posts `didMove` for every step of it — the live signal the
        // snap overlay and the mid-drag re-anchoring both ride on. The mouse-up itself
        // lands on the bar's own background (`HoverTracker`), which is what ends it.
        barDragObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] note in
            guard let self, note.object as? NSWindow === self.panel else { return }
            MainActor.assumeIsolated { self.barDidMove() }
        }
    }

    deinit {
        if let barDragObserver {
            NotificationCenter.default.removeObserver(barDragObserver)
        }
    }

    /// `transition` sets `state` before it touches `acceptsKey`, so the resign it
    /// triggers on the way *out* of the input bar finds a state that is already
    /// something else and stops here.
    @objc private func panelResignedKey() {
        // Checked a turn later rather than inline: an accessory app taking key on a
        // non-activating panel can bounce once as focus settles, and cancelling on
        // that would make the input bar close the instant it opened.
        Task { @MainActor [weak self] in
            guard let self, !self.panel.isKeyWindow, !self.exportingReplyDiagnostics else { return }
            self.cancelInput()
        }
    }

    // MARK: - Lifecycle

    func show(initiallyVisible: Bool = true) {
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
            setVisible(initiallyVisible)
        }
        Task { await refreshAccount() }
    }

    // MARK: - Onboarding presentation

    func setOnboardingPassive(_ passive: Bool) {
        onboardingPassive = passive
        collapseTask?.cancel()
        collapseTask = nil
        if passive {
            clearAvailableReply()
            clipboardWatcher?.stop()
            clipboardWatcher = nil
            dismissSnoozeMenu()
            if introPresentation == nil { dismiss() }
        } else if visibilityRequested {
            startClipboardWatching()
        }
    }

    func beginIntro(_ presentation: IntroPillPresentation, on screen: NSScreen, debugReplay: Bool) {
        setOnboardingPassive(true)
        debugIntroPlacement = debugReplay
        introPlacementOverride = .bottomCenter
        parkedZone = .bottomCenter
        introDimmerVisible = true
        introPresentation = presentation
        visibilityRequested = true
        panel.acceptsKey = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.setFrame(screen.frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
    }

    func introLandingFrame(on screen: NSScreen) -> NSRect {
        OverlayPlacement.zoneFrame(.bottomCenter,
            barSize: NSSize(width: Tokens.Geometry.pillCollapsedWidth, height: Tokens.Geometry.pillHeight),
            on: screen)
    }

    func settleIntro(on screen: NSScreen) {
        guard introPresentation != nil else { return }
        let target = introLandingFrame(on: screen)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            introPresentation = nil
            panel.setFrame(target, display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        }
        panel.hasShadow = true
        panel.invalidateShadow()
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        lastAppliedSize = target.size
        lastWorkArea = OverlayPlacement.workArea(on: screen)
    }

    func cueIntroDrag() {
        guard !introDragInProgress else { return }
        introDragCue += 1
    }

    func finishIntroPresentation() {
        introDimmerVisible = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
    }

    func endOnboardingPresentation() {
        finishIntroPresentation()
        introPlacementOverride = nil
        debugIntroPlacement = false
        setOnboardingPassive(false)
        reanchor()
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

    /// Snoozing the copy trigger also dismisses unused reply availability.
    func disableCopyTrigger(for duration: OverlaySnooze.Duration) {
        ClipboardWatcher.copyDisabledUntil = OverlaySnooze.until(duration)
        clearAvailableReply()
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
        guard !onboardingPassive, introPresentation == nil else { return }
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
        visibilityRequested = visible
        if !visible { cancelReplySession(); clearAvailableReply() }
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

    func refreshAccount(reloadButtons: Bool = true) async {
        let account = await auth.currentSession?.userId
        if activeAccount != account {
            accountRevision &+= 1
            activeAccount = account
            prompts = []
            clearAvailableReply()
            replyDiagnosticData = nil
            replyLocalObservations = []
            dismiss()
        }
        signedOut = account == nil
        guard let account, reloadButtons else { return }
        let requestID = UUID()
        promptRefreshID = requestID
        do {
            let loaded = try await promptStore.scoped(to: account).fetch()
            guard await auth.currentSession?.userId == account,
                  activeAccount == account, promptRefreshID == requestID else { return }
            prompts = UserPromptOrder.sortedForEditing(loaded)
            promptsFailed = false
        } catch {
            guard activeAccount == account, promptRefreshID == requestID else { return }
            promptsFailed = true
        }
    }

    private func capturedTarget(_ target: TextTarget, pid: pid_t?) -> CapturedTarget {
        CapturedTarget(target: target, frontmostPID: pid)
    }

    func press(_ prompt: UserPrompt) {
        guard allowsLessonAction(.polish) else { return }
        let buttonKey = OnboardingPresetPack.buttonAnalyticsKey(for: prompt)
        clipboardReplyCaptureID = nil
        let lessonID = lesson?.id
        let frontmostPID = NSWorkspace.shared.frontmostPID
        Task { [weak self] in
            guard let self, self.lesson?.id == lessonID else { return }
            await self.refreshAccount(reloadButtons: false)
            guard self.lesson?.id == lessonID else { return }
            guard !self.signedOut else { self.pressSignIn(); return }
            let revision = self.accountRevision
            do {
                ClipboardWatcher.suspend()
                let target = try await self.captureWritingTarget(frontmostPID: frontmostPID)
                ClipboardWatcher.resume()
                guard self.accountRevision == revision else { return }
                guard self.lesson?.id == lessonID else { return }
                guard self.acceptsButtonTarget(target, buttonKey: buttonKey) else { return }
                await self.snapshotUserFocus()
                guard self.lesson?.id == lessonID else { return }
                let captured = self.capturedTarget(target, pid: frontmostPID)
                self.startRewrite(captured: captured, promptText: prompt.prompt, replyTo: nil,
                    buttonTitle: prompt.title, commandKey: prompt.builtinKey, promptOrigin: prompt.origin.rawValue,
                    rewriteType: .savedButton, buttonAnalyticsKey: buttonKey, isTutorial: self.lesson?.kind == .rewrite)
            } catch {
                guard self.lesson?.id == lessonID else { return }
                ClipboardWatcher.resume()
                self.reportCaptureFailure(.savedButton, isTutorial: self.lesson?.kind == .rewrite, buttonAnalyticsKey: buttonKey, message: Self.message(for: error))
                self.present(error)
            }
        }
    }

    private func captureWritingTarget(frontmostPID: pid_t?) async throws -> TextTarget {
        #if DEBUG
        if let previewWritingCapture { return try previewWritingCapture.get() }
        #endif
        return try await textIO.capture(frontmostPID: frontmostPID, allowEmpty: true, allowScratch: true)
    }

    private func acceptsButtonTarget(_ target: TextTarget, buttonKey: String?) -> Bool {
        let message: String
        if target.writingSurfaceHint == .excluded {
            message = tr("文章の入力欄でお使いください。", "Use a button in a writing field.", "请在正文输入框中使用润色。")
        } else if target.isEmpty {
            message = target.hasDestination ? tr(
                "ボタンを使う前に文章を入力してください。新しい文章を書くには、鉛筆ボタンをお使いください。",
                "Type some text before using a button, or use the pencil to write something new.",
                "请先输入文字再使用润色，或点击铅笔按钮撰写新内容。"
            ) : tr(
                "入力欄をクリックするか文章を選択してから、もう一度ボタンを押してください。",
                "Click into a writing field or select some text, then try the button again.",
                "请点击输入框或选中文字，然后再次点击润色。"
            )
        } else {
            return true
        }
        reportCaptureFailure(.savedButton, isTutorial: lesson?.kind == .rewrite, buttonAnalyticsKey: buttonKey, message: message)
        present(message: message)
        return false
    }

    func beginTutorial(prompts: [UserPrompt], onInserted: @escaping (OnboardingLesson.Completion) -> Void) {
        tutorialMode = .savedButtons(Set(prompts.map(\.id)))
        tutorialPrompts = prompts
        tutorialInserted = onInserted
        transition(to: .pill)
    }

    func beginCustomTutorial(onInserted: @escaping (OnboardingLesson.Completion) -> Void) {
        tutorialMode = .custom
        tutorialPrompts = []
        tutorialInserted = onInserted
        transition(to: .pill)
    }

    func beginReplyTutorial(onInserted: @escaping (OnboardingLesson.Completion) -> Void) {
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
        lessonEvent(.sourceSelected)
        if ReplyContextFeature.isEnabled {
            tutorialReplySource = text
        } else {
            armReply(source)
        }
    }

    func endTutorial() {
        lessonGuide?.close()
        lessonGuide = nil
        lesson = nil
        cancelReplySession()
        clearAvailableReply()
        insertInFlight = false
        finishAttempt(.abandoned(.dismissed), target: currentGeneratingTarget)
        rewriteTask?.cancel()
        rewriteTask = nil
        resultContextBeforeRewrite = nil
        tutorialPrompts = []
        tutorialInserted = nil
        tutorialMode = nil
        tutorialReplySource = nil
        if case .pill = state { return }
        transition(to: .pill)
    }

    @objc private func reanchor() {
        guard introPresentation == nil, !isDraggingBar, !isAnimatingSnapLanding else { return }
        parkedZone = introPlacementOverride ?? OverlayPlacement.savedZone()
        notchWidth = OverlayPlacement.notchFrame(on: OverlayPlacement.screen(containing: panel.frame))?.width ?? 0
        lastWorkArea = OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: panel.frame))
        resize(to: currentSize(), animated: false)
        generatingPanel?.reanchor(companionGeometry)
        resultPanel?.reanchor(companionGeometry)
        errorPanel?.reanchor(zone: parkedZone)
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
                if self.isDraggingBar {
                    if NSEvent.pressedMouseButtons & 1 == 0 { self.endBarDrag() }
                    return
                }
                guard self.introPresentation == nil, !self.isAnimatingSnapLanding else { return }
                let area = OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: self.panel.frame))
                guard area != self.lastWorkArea || self.parkedZone != (self.introPlacementOverride ?? OverlayPlacement.savedZone()) else { return }
                self.reanchor()
            }
        }
    }

    // MARK: - Reply mode (§16)

    private func startClipboardWatching() {
        guard !onboardingPassive, introPresentation == nil, visibilityRequested else { return }
        guard !ReplyContextFeature.isEnabled else { return }
        guard clipboardWatcher == nil else { return }
        let watcher = ClipboardWatcher { [weak self] source in self?.armReply(source) }
        watcher.start()
        clipboardWatcher = watcher
    }

    private func armReply(_ source: ReplySource?) {
        guard !onboardingPassive, introPresentation == nil else { return }
        guard lesson == nil || lesson?.kind == .reply else { return }
        guard clipboardReplyCaptureID == nil else { return }
        if source == nil {
            clearAvailableReply()
            lessonEvent(.sourceCleared)
            return
        }
        guard state == .pill || state == .hoverRow else { return }
        clearAvailableReply()
        guard let source, !source.isExpired() else { return }
        availableReplySource = source
        scheduleReplyExpiry(source)
    }

    private func clearAvailableReply() {
        availableReplySource = nil
        clipboardReplyCaptureID = nil
        replyExpiryTask?.cancel()
        replyExpiryTask = nil
    }

    func dismissReply() {
        clearAvailableReply()
        cancelReplySession()
        if state.isReply {
            transition(to: panel.frame.contains(NSEvent.mouseLocation) ? .hoverRow : .pill)
        }
        lessonEvent(.sourceCleared)
    }

    private func scheduleReplyExpiry(_ source: ReplySource) {
        replyExpiryTask?.cancel()
        let remaining = max(0, ReplySource.lifetime - Date().timeIntervalSince(source.copiedAt))
        replyExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self, self.availableReplySource == source else { return }
            self.clearAvailableReply()
            self.lessonEvent(.sourceCleared)
        }
    }

    func pressCopiedReply() {
        guard allowsLessonAction(.reply), state == .hoverRow,
              clipboardReplyCaptureID == nil, let source = availableReplySource else { return }
        guard !source.isExpired() else { dismissReply(); return }
        guard !signedOut else { pressSignIn(); return }
        let captureID = UUID()
        clipboardReplyCaptureID = captureID
        replyExpiryTask?.cancel()
        collapseTask?.cancel()
        let lessonID = lesson?.id
        let revision = accountRevision
        let frontmostPID = NSWorkspace.shared.frontmostPID

        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.clipboardReplyCaptureID == captureID { self.clipboardReplyCaptureID = nil }
                if self.availableReplySource == source { self.scheduleReplyExpiry(source) }
                if self.state == .hoverRow, !self.panel.frame.contains(NSEvent.mouseLocation) {
                    self.mouseExited()
                }
            }
            do {
                let target = try await self.textIO.captureReply(
                    frontmostPID: frontmostPID, copiedMessage: source.text
                )
                guard self.clipboardReplyCaptureID == captureID,
                      self.accountRevision == revision,
                      self.lesson?.id == lessonID, self.state == .hoverRow,
                      NSWorkspace.shared.frontmostPID == frontmostPID else { return }
                await self.snapshotUserFocus()
                guard self.clipboardReplyCaptureID == captureID,
                      self.accountRevision == revision,
                      self.lesson?.id == lessonID, self.state == .hoverRow,
                      NSWorkspace.shared.frontmostPID == frontmostPID else { return }
                self.clearAvailableReply()
                self.transition(to: .replyInput(
                    reply: source, target: self.capturedTarget(target, pid: frontmostPID)
                ))
            } catch {
                guard self.clipboardReplyCaptureID == captureID else { return }
                self.present(error)
            }
        }
    }

    func pressReply() {
        guard allowsLessonAction(.reply) else { return }
        let lessonID = lesson?.id
        guard ReplyContextFeature.isEnabled, replyCaptureID == nil else { return }
        let captureID = UUID()
        replyCaptureID = captureID
        collapseTask?.cancel()
        let pid = NSWorkspace.shared.frontmostPID
        replyContextTask = Task { [weak self] in
            guard let self, self.lesson?.id == lessonID else { return }
            do {
                let anchor = try await self.textIO.captureReplyAnchor(frontmostPID: pid)
                guard self.lesson?.id == lessonID else { return }
                await self.snapshotUserFocus()
                guard self.lesson?.id == lessonID else { return }
                guard !Task.isCancelled, self.replyCaptureID == captureID, NSWorkspace.shared.frontmostPID == pid else {
                    self.replyCaptureID = nil
                    return
                }
                let session = ReplySession(draftStatus: anchor.draftStatus)
                let bundle = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } ?? ""
                // Freeze DOM and native destination together before any overlay can take key.
                let capture = try await self.replyCapture.capture(anchor, snapshotId: session.id, bundle: bundle, pid: pid)
                guard !Task.isCancelled, self.replyCaptureID == captureID, NSWorkspace.shared.frontmostPID == pid else {
                    self.replyCaptureID = nil
                    return
                }
                if capture.binding != nil, anchor.target.hasDestination,
                   !(await self.textIO.replyTargetStillFocused(anchor.target, frontmostPID: pid)) {
                    throw BrowserReplyError.failure("target_changed")
                }
                self.replyCaptureID = nil
                self.replySession = session
                self.replyDiagnosticData = nil
                self.replyCaptureSource = capture.source
                self.replyFallbackReason = capture.fallbackReason
                self.replyLocalObservations = capture.observations
                self.replyAppCategory = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "org.mozilla.firefox"].contains(bundle) ? "browser" : "other"
                var captured = self.capturedTarget(anchor.target, pid: pid)
                captured.browserReplyBinding = capture.binding
                self.transition(to: .explicitReply(target: captured))
                if self.tutorialMode?.marksReply == true, let source = self.tutorialReplySource {
                    self.chooseReplySource([ReplySourceBlock(id: "tutorial", conversationId: "tutorial", text: source, order: 0)], audience: .group)
                    return
                }
                let evidence = capture.evidence
                self.replySession?.captured(evidence)
                self.updateReplyDiagnostics()
                guard !evidence.blocks.isEmpty, capture.failureReason == nil else {
                    self.replySession?.fail(unavailable: true, reason: capture.failureReason ?? "no_readable_context")
                    self.updateReplyDiagnostics()
                    return
                }
                let outcome = try await self.rewriteService.replyContext(evidence, attemptId: session.attemptId, appCategory: self.replyAppCategory, appVersion: self.appVersion)
                guard !Task.isCancelled, self.replySession?.id == session.id else { return }
                let queued = self.replySession?.accept(outcome)
                self.updateReplyDiagnostics()
                self.recordReplyWorkflow(self.replySession?.context, stage: "context_ready")
                if let queued { self.submitInput(queued) }
            } catch {
                guard self.lesson?.id == lessonID else { return }
                guard !Task.isCancelled else { return }
                self.replyCaptureID = nil
                if self.replySession != nil { self.replySession?.fail(error); self.updateReplyDiagnostics() }
                else { self.present(error) }
            }
        }
    }

    func retryReplyContext() {
        guard let session = replySession, let evidence = session.analysisEvidence, session.canRetryAnalysis else { return }
        replyContextTask?.cancel()
        replySession?.retry()
        let attemptId = replySession?.attemptId ?? UUID().uuidString
        replyContextTask = Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.rewriteService.replyContext(evidence, attemptId: attemptId, appCategory: self.replyAppCategory, appVersion: self.appVersion)
                guard !Task.isCancelled, self.replySession?.id == session.id else { return }
                let queued = self.replySession?.accept(outcome)
                self.updateReplyDiagnostics()
                self.recordReplyWorkflow(self.replySession?.context, stage: "context_ready")
                if let queued { self.submitInput(queued) }
            } catch {
                guard !Task.isCancelled, self.replySession?.id == session.id else { return }
                self.replySession?.fail(error)
                self.updateReplyDiagnostics()
            }
        }
    }

    private func updateReplyDiagnostics() {
        #if DEBUG
        guard let session = replySession, let evidence = session.evidence else { return }
        struct Export: Encodable {
            let format = "keigo-reply-diagnostics-v2"
            let captureSource: String
            let fallbackReason: String?
            let appVersion: String
            let appCategory: String
            let attemptId: String
            let evidence: CapturedReplyEvidence
            let analysisEvidence: CapturedReplyEvidence?
            let observations: [ReplyNodeObservation]
            let diagnostics: ReplyInterpretationDiagnostics?
            let candidates: [ReplyCandidate]
            let context: ReplyContext?
            let phase: String
            let failureReason: String?
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        replyDiagnosticData = try? encoder.encode(Export(captureSource: replyCaptureSource, fallbackReason: replyFallbackReason, appVersion: appVersion, appCategory: replyAppCategory,
            attemptId: session.attemptId, evidence: evidence, analysisEvidence: session.analysisEvidence,
            observations: replyLocalObservations, diagnostics: session.diagnostics, candidates: session.candidates,
            context: session.context, phase: String(describing: session.phase), failureReason: session.failureReason))
        #endif
    }

    /// Survives ReplySession dismissal during generation; tied to the original snapshot.
    private func recordReplyWorkflow(_ context: ReplyContext?, stage: String, reason: String? = nil) {
        #if DEBUG
        guard let context, let data = replyDiagnosticData,
              var export = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let evidence = export["evidence"] as? [String: Any], evidence["snapshotId"] as? String == context.snapshotId else { return }
        var stages = export["workflow"] as? [[String: String]] ?? []
        var event = ["stage": stage]
        if let reason { event["reason"] = reason }
        stages.append(event)
        export["workflow"] = stages
        replyDiagnosticData = try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
        #endif
    }

    func exportReplyDiagnostics() {
        #if DEBUG
        guard let data = replyDiagnosticData else {
            present(message: tr("返信の会話を確認してから書き出してください", "Analyze a Reply conversation before exporting", "请先分析回复对话再导出"))
            return
        }
        exportingReplyDiagnostics = true
        let save = NSSavePanel()
        save.title = "Export Reply Diagnostics"
        save.message = tr("会話の本文を含みます。共有前に個人情報を削除してください。", "Includes conversation source text. Review and redact personal information before sharing.", "包含对话原文。分享前请检查并删除个人信息。")
        save.nameFieldStringValue = "reply-diagnostics.json"
        save.begin { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = save.url {
                do { try data.write(to: url, options: .atomic) }
                catch { self.present(message: tr("書き出しに失敗しました", "Could not export diagnostics", "导出失败")) }
            }
            if case .explicitReply = self.state { self.panel.makeKeyAndOrderFront(nil) }
            self.exportingReplyDiagnostics = false
        }
        #endif
    }

    func chooseReplyRegion(_ id: String) {
        replySession?.scope(to: id)
        retryReplyContext()
    }

    private func cancelReplySession() {
        replyContextTask?.cancel()
        replyContextTask = nil
        replyCaptureID = nil
        replySession = nil
    }

    func chooseReplySource(_ blocks: [ReplySourceBlock], audience: ReplyAudienceKind) {
        guard case .explicitReply = state else { return }
        replyContextTask?.cancel()
        replySession?.choose(blocks: blocks, audience: audience)
    }

    func pasteReplySource(audience: ReplyAudienceKind) {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf16.count <= 12000 else { return }
        chooseReplySource([ReplySourceBlock(id: "pasted", conversationId: "pasted", text: text, order: 0)], audience: audience)
    }

    // MARK: - Hover

    func mouseEntered() {
        guard !onboardingPassive, introPresentation == nil else { return }
        guard introPresentation == nil, !isDraggingBar, !isAnimatingSnapLanding else { return }
        collapseTask?.cancel()
        collapseTask = nil
        lessonEvent(.hovered)
        guard case .pill = state else { return }
        Task { await refreshAccount() }
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
        guard !onboardingPassive, introPresentation == nil else { return }
        guard introPresentation == nil, !isDraggingBar, !isAnimatingSnapLanding else { return }
        guard case .hoverRow = state, clipboardReplyCaptureID == nil else { return }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Tokens.Geometry.collapseGrace * 1_000_000_000))
            guard !Task.isCancelled, let self, case .hoverRow = self.state,
                  self.snoozeMenuPanel == nil, !self.isDraggingBar, !self.isAnimatingSnapLanding
            else { return }
            self.transition(to: .pill)
        }
    }

    // MARK: - The capture ordering (§4)

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
        guard allowsLessonAction(.custom) else { return }
        clipboardReplyCaptureID = nil
        let lessonID = lesson?.id
        let frontmostPID = NSWorkspace.shared.frontmostPID

        Task { [weak self] in
            guard let self, self.lesson?.id == lessonID else { return }
            await self.refreshAccount(reloadButtons: false)
            guard self.lesson?.id == lessonID else { return }
            guard !self.signedOut else { self.pressSignIn(); return }
            let revision = self.accountRevision
            do {
                ClipboardWatcher.suspend()
                let target = try await self.captureWritingTarget(frontmostPID: frontmostPID)
                ClipboardWatcher.resume()
                guard self.accountRevision == revision else { return }
                // Before the transition: the input bar takes key, and from then on a
                // focus read answers about us (§18).
                guard self.lesson?.id == lessonID else { return }
                await self.snapshotUserFocus()
                guard self.lesson?.id == lessonID else { return }
                self.transition(to: .inputBar(
                    target: self.capturedTarget(target, pid: frontmostPID)
                ))
            } catch {
                guard self.lesson?.id == lessonID else { return }
                ClipboardWatcher.resume()
                // Rare by construction — `allowEmpty` and `allowScratch` mean this path
                // does not fail for want of a target — but a `notTrusted` still lands
                // here, and that is exactly the failure worth seeing by type.
                self.reportCaptureFailure(
                    .customInstruction,
                    isTutorial: self.tutorialMode != nil,
                    message: Self.message(for: error)
                )
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
        guard !onboardingPassive, introPresentation == nil else { return }
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
        case .explicitReply:
            cancelReplySession()
            transition(to: .pill)

        case .inputBar:
            transition(to: panel.frame.contains(NSEvent.mouseLocation) ? .hoverRow : .pill)

        case .replyInput(let source, _):
            transition(to: panel.frame.contains(NSEvent.mouseLocation) ? .hoverRow : .pill)
            armReply(ReplySource(copied: source.text))

        case .pill, .hoverRow, .generating, .result:
            return
        }
    }

    func submitInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch state {
        case .explicitReply(let captured):
            guard var session = replySession else { return }
            if session.phase == .loading {
                session.queue(trimmed)
                replySession = session
                return
            }
            guard let context = session.context, session.phase == .ready else { return }
            startRewrite(captured: captured, promptText: trimmed, instruction: .input(trimmed), replyTo: nil,
                buttonTitle: tr("返信", "Reply", "回复"), commandKey: nil, promptOrigin: nil,
                rewriteType: .reply, isTutorial: tutorialMode?.marksReply == true,
                replyContext: context, draftReadStatus: session.draftStatus)
        case .inputBar(let captured):
            guard !trimmed.isEmpty else { return }
            startRewrite(
                captured: captured,
                promptText: trimmed,
                instruction: .input(trimmed),
                replyTo: nil,
                buttonTitle: nil,
                commandKey: nil,
                promptOrigin: nil,
                rewriteType: .customInstruction,
                isTutorial: tutorialMode?.marksCustomGuidance(trimmed) == true
            )

        case .replyInput(let source, let captured):
            // Empty is allowed here and blocked above. "Just write me a reply" is the
            // strongest case for reply mode, and the backend requires a non-empty
            // `prompt`, so the default instruction stands in for one.
            startRewrite(
                captured: captured,
                promptText: trimmed.isEmpty ? Self.defaultReplyInstruction : trimmed,
                instruction: .input(trimmed),
                replyTo: source.text,
                // Labels the ホーム history row. A reply has no button behind it and
                // 「カスタム」 would file it with the ✎ rewrites it is not.
                buttonTitle: tr("返信", "Reply", "回复"),
                commandKey: nil,
                promptOrigin: nil,
                rewriteType: .reply,
                isTutorial: tutorialMode?.marksReply == true
            )

        case .pill, .hoverRow, .generating, .result:
            return
        }
    }

    // MARK: - Attempt lifecycle

    /// Opens an attempt and reports `desktop_rewrite_started`.
    ///
    /// Any attempt still open is abandoned as `superseded` first. That is not a tidy-up:
    /// `startRewrite` cancels `rewriteTask`, and the cancelled request has already been
    /// sent, metered and billed by `desktop-rewrite`. Before this, that request reported
    /// nothing at all — the `guard !Task.isCancelled` sits in front of the analytics call
    /// — so `completed + failed` silently failed to add up to the number of presses.
    private func beginAttempt(
        _ type: RewriteType,
        isTutorial: Bool,
        buttonAnalyticsKey: String? = nil,
        target: TextTarget?
    ) -> RewriteAttempt {
        let attempt = RewriteAttempt(
            type: type,
            isTutorial: isTutorial,
            buttonAnalyticsKey: buttonAnalyticsKey
        )
        if let superseded = attempts.begin(attempt) {
            // The *outgoing* attempt's target, not the incoming one — the abandoned event
            // describes the request being thrown away, and attributing it to the new
            // press's host app would misfile it. `begin` hands the value back precisely
            // so this cannot be forgotten.
            analytics.rewriteAbandoned(
                superseded,
                reason: .superseded,
                target: currentGeneratingTarget
            )
        }
        analytics.rewriteStarted(attempt, target: target)
        return attempt
    }

    /// How an attempt ended. Exactly one of these is reported per `beginAttempt`.
    private enum AttemptOutcome {
        case completed(target: TextTarget, promptOrigin: String?, isReply: Bool, candidateCount: Int, latencyMs: Int)
        case failed(stage: FailureStage, message: String)
        case abandoned(AbandonReason)
    }

    /// Reports the one terminal event for the open attempt and closes it.
    ///
    /// A no-op when no attempt is open, which is what makes it safe to call from every
    /// exit path — including the ones that overlap, like a dismiss that races the
    /// response, or `present(message:)` being reached from a state that never started
    /// a generation at all.
    private func finishAttempt(_ outcome: AttemptOutcome, target: TextTarget?) {
        guard let attempt = attempts.finish() else { return }
        switch outcome {
        case let .completed(target, promptOrigin, isReply, candidateCount, latencyMs):
            analytics.rewriteCompleted(
                attempt,
                target: target,
                promptOrigin: promptOrigin,
                isReply: isReply,
                candidateCount: candidateCount,
                latencyMs: latencyMs
            )
        case let .failed(stage, message):
            analytics.rewriteFailed(attempt, stage: stage, message: message, target: target)
        case let .abandoned(reason):
            analytics.rewriteAbandoned(attempt, reason: reason, target: target)
        }
    }

    /// The target of the generation in flight, for the terminal events that are raised
    /// from outside the rewrite task and so do not have it in hand. Nil whenever the
    /// state is not `.generating`, which is also every case where there is no attempt to
    /// report against.
    private var currentGeneratingTarget: TextTarget? {
        guard case .generating(let request) = state else { return nil }
        return request.captured.target
    }

    /// A press that never became a generation because there was nothing to read.
    ///
    /// Reported as a started-then-failed pair so it lands inside the funnel rather than
    /// beside it. This is the dominant failure in the wild — every one of the 17 failures
    /// external users hit before this shipped was a capture failure — and until now it
    /// carried no type, no host app and no stage, only a translated toast string.
    private func reportCaptureFailure(
        _ type: RewriteType,
        isTutorial: Bool,
        buttonAnalyticsKey: String? = nil,
        message: String
    ) {
        _ = beginAttempt(
            type,
            isTutorial: isTutorial,
            buttonAnalyticsKey: buttonAnalyticsKey,
            target: nil
        )
        finishAttempt(.failed(stage: .capture, message: message), target: nil)
    }

    // MARK: - Rewrite

    private func startRewrite(
        captured: CapturedTarget,
        promptText: String,
        instruction: ResultInstruction = .hidden,
        requestText: String? = nil,
        replyTo: String?,
        buttonTitle: String?,
        commandKey: String?,
        promptOrigin: String?,
        rewriteType: RewriteType,
        buttonAnalyticsKey: String? = nil,
        isTutorial: Bool,
        previousResults: ResultContext? = nil,
        previousEventId: String? = nil,
        replyContext: ReplyContext? = nil,
        draftReadStatus: ReplyDraftReadStatus? = nil
    ) {
        let attempt = beginAttempt(
            rewriteType,
            isTutorial: isTutorial,
            buttonAnalyticsKey: buttonAnalyticsKey,
            target: captured.target
        )
        if let style = captured.writingStyle {
            analytics.styleApplied(style, attemptID: attempt.id, isTutorial: isTutorial)
        }
        resultContextBeforeRewrite = previousResults
        // A regenerate keeps the result panel's pages, so the latch has to be released
        // explicitly — the new attempt deserves a fresh reading of where it can go.
        destinationFailed = false
        let requestText = requestText ?? captured.target.text
        let pending = PendingRewrite(
            captured: captured,
            requestText: requestText,
            promptText: promptText,
            instruction: instruction,
            replyTo: replyTo,
            replyContext: replyContext,
            draftReadStatus: draftReadStatus,
            buttonTitle: buttonTitle,
            attempt: attempt,
            startedAt: Date(),
            lessonID: lesson?.id
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
            browserURL: captured.writingStyle == nil ? captured.target.browserURL : nil,
            ioPath: captured.target.path.rawValue,
            // Keep composition language with the captured profile through regeneration.
            writingLanguage: captured.writingLanguageCode,
            attemptId: attempt.id.uuidString,
            rewriteType: rewriteType.rawValue,
            buttonAnalyticsKey: buttonAnalyticsKey,
            previousEventId: previousEventId,
            replyContext: replyContext,
            draftReadStatus: draftReadStatus,
            writingStyle: captured.writingStyle
        )

        rewriteTask?.cancel()
        rewriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.rewriteService.rewrite(request)
                // A cancelled task reports nothing here on purpose: whoever cancelled it
                // already closed the attempt — `beginAttempt` as `superseded`, or
                // `cancelRewrite`/`dismiss` as `dismissed`. Reporting again would be the
                // second terminal event for one `started`.
                guard !Task.isCancelled, self.lesson?.id == pending.lessonID else { return }
                self.recordReplyWorkflow(pending.replyContext, stage: "generation_complete")
                let latencyMs = Int(Date().timeIntervalSince(pending.startedAt) * 1000)
                self.finishAttempt(
                    .completed(
                        target: captured.target,
                        promptOrigin: promptOrigin,
                        isReply: pending.isReply,
                        candidateCount: result.candidates.count,
                        latencyMs: latencyMs
                    ),
                    target: captured.target
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
                self.recordReplyWorkflow(pending.replyContext, stage: "generation_failed")
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
        // Before the cancel, so the target is still readable off `.generating`.
        finishAttempt(.abandoned(.dismissed), target: currentGeneratingTarget)
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
                originalText: pending.replyContext?.selectedTargetText ?? pending.replyTo ?? pending.captured.target.text,
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
            guard let self, self.lesson?.id == pending.lessonID else { return }
            do {
                // The write puts the rewrite on the pasteboard and restores the
                // original afterwards whenever it escalates to ⌘V.
                ClipboardWatcher.suspend()
                let binding = destination == .insert ? pending.captured.browserReplyBinding : nil
                if let binding {
                    let browser = self.replyCapture.browser
                    _ = try await browser.validate(binding)
                    self.recordReplyWorkflow(pending.replyContext, stage: "destination_validated")
                    try await self.textIO.write(
                        candidate.replacement,
                        to: target,
                        frontmostPID: frontmostPID,
                        beforePaste: { @Sendable in _ = try await browser.validate(binding, focused: true) }
                    )
                    let result: String
                    do { result = try await browser.validate(binding, expectedText: candidate.replacement) }
                    catch {
                        self.recordReplyWorkflow(pending.replyContext, stage: "insertion_unverified", reason: (error as? BrowserReplyError)?.reason ?? "verification_failed")
                        throw error
                    }
                    self.recordReplyWorkflow(pending.replyContext, stage: result == "verified" ? "insertion_verified" : "insertion_failed", reason: result)
                    if result != "verified" { throw TextIOError.writeFailed }
                } else {
                    try await self.textIO.write(candidate.replacement, to: target, frontmostPID: frontmostPID)
                    self.recordReplyWorkflow(pending.replyContext, stage: destination == .insertHere ? "insertion_redirected" : "insertion_unverified")
                }
                ClipboardWatcher.resume()
                guard self.lesson?.id == pending.lessonID else { return }
                // Reported against the target that was *captured*, because that is what
                // `capture_mode` and `io_path` describe. `insert_destination` is the new
                // field and the one that says whether the rewrite went home or somewhere
                // the user pointed it afterwards.
                self.analytics.inserted(
                    pending.attempt,
                    target: pending.captured.target,
                    isReply: pending.isReply,
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
                let tutorialCompletion = pending.isTutorial && self.lesson?.id == pending.lessonID ? self.tutorialInserted : nil
                if tutorialCompletion != nil { self.lessonEvent(.completed(.inserted)) }
                if pending.isTutorial {
                    self.tutorialPrompts = []
                    self.tutorialInserted = nil
                    self.tutorialMode = nil
                }
                // The reply has been sent where it was going, so the copy behind it is
                // spent. Cancelling the clock as well keeps a late expiry from firing
                // over whatever the bar is doing minutes from now.
                if pending.isReply { self.clearAvailableReply() }
                self.insertInFlight = false
                self.transition(to: .pill)
                tutorialCompletion?(.inserted)
            } catch {
                ClipboardWatcher.resume()
                guard self.lesson?.id == pending.lessonID else { return }
                self.recordReplyWorkflow(pending.replyContext, stage: "insertion_failed", reason: (error as? BrowserReplyError)?.reason ?? "write_failed")
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
            pending.attempt,
            target: pending.captured.target,
            isReply: pending.isReply,
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
        let tutorialCompletion = pending.isTutorial && lesson?.id == pending.lessonID ? tutorialInserted : nil
        if tutorialCompletion != nil { lessonEvent(.completed(.copied)) }
        if pending.isTutorial {
            tutorialPrompts = []
            tutorialInserted = nil
            tutorialMode = nil
            tutorialReplySource = nil
        }
        if pending.isReply { clearAvailableReply() }
        insertInFlight = false
        transition(to: .pill)
        present(
            notice: tr(
                "コピーしました。貼り付けたい場所で ⌘V を押してください。",
                "Copied. Press ⌘V where you want it.",
                "已复制。请在要粘贴的位置按 ⌘V。"
            )
        )
        tutorialCompletion?(.copied)
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
                page.pending.attempt,
                target: page.pending.captured.target,
                isReply: page.pending.isReply,
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
            instruction: pending.instruction.regenerated(edit: promptText),
            requestText: pending.requestText,
            // Carried forward. Dropping it would turn ↻ on a reply into a rewrite of
            // the user's draft, which for the usual empty compose box is a rewrite of
            // nothing at all.
            replyTo: pending.replyTo,
            buttonTitle: pending.buttonTitle,
            commandKey: nil,
            promptOrigin: nil,
            // A ↻ is its own attempt, not a continuation of the one that produced the
            // page it was pressed on: it is separately generated, separately billed, and
            // separately acceptable. It reported as `prompt_origin: custom` until now,
            // indistinguishable from a first-time ✎ press.
            rewriteType: .regenerate,
            isTutorial: pending.isTutorial,
            previousResults: context,
            previousEventId: page.eventId,
            replyContext: pending.replyContext,
            draftReadStatus: pending.draftReadStatus
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
            instruction: .input(instruction),
            requestText: page.candidate.replacement,
            replyTo: pending.replyTo,
            buttonTitle: pending.buttonTitle,
            commandKey: nil,
            promptOrigin: nil,
            rewriteType: .refine,
            isTutorial: pending.isTutorial,
            previousResults: context,
            previousEventId: page.eventId,
            replyContext: pending.replyContext,
            draftReadStatus: pending.replyContext == nil ? pending.draftReadStatus : .present
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
        // Dismissing while a generation is in flight is an abandonment. A no-op in every
        // other state, which is the common case — dismiss is also how a result panel and
        // an idle bar are closed.
        finishAttempt(.abandoned(.dismissed), target: currentGeneratingTarget)
        rewriteTask?.cancel()
        resultContextBeforeRewrite = nil
        transition(to: .pill)
    }

    // MARK: - Transitions

    private func transition(to next: OverlayState) {
        guard introPresentation == nil else { return }
        clipboardReplyCaptureID = nil
        if replyCaptureID != nil { cancelReplySession() }
        if case .explicitReply = state {
            if case .explicitReply = next {} else { cancelReplySession() }
        }

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
        switch next {
        case .inputBar, .replyInput, .explicitReply: lessonEvent(.composerOpened)
        case .generating: lessonEvent(.generating)
        case .result: lessonEvent(.result)
        case .pill:
            if let phase = lesson?.phase, [.instruction, .submit, .generating, .result].contains(phase) {
                lessonEvent(.cancelled)
            } else { lessonEvent(.collapsed) }
        case .hoverRow:
            if let phase = lesson?.phase, [.instruction, .submit, .generating, .result].contains(phase) {
                lessonEvent(.cancelled)
                lessonEvent(.hovered)
            }
        }

        // **Only work in progress clears the message.** This used to dismiss on every
        // transition, and the transition that follows a capture failure is the hover
        // row collapsing 300 ms after the pointer leaves the bar — which is the moment
        // the user's eye moves *to* the toast. So pressing a button in an app with no
        // editable field flashed an explanation and took it away again; the timeout was
        // never what anyone was reading against. A toast now stands until it times out,
        // is clicked, or is replaced by a rewrite actually starting.
        switch next {
        case .generating, .result: dismissErrorToast()
        case .explicitReply, .pill, .hoverRow, .inputBar, .replyInput: break
        }

        // Key-ness is opened before the window is asked to take key, and closed
        // before anything else happens, so there is never a moment where a
        // non-input state could accept focus.
        panel.acceptsKey = next.wantsKeyWindow

        // The capsule and the result panel stand in for the bar rather than sitting
        // above it, so the hand-off is ordered to keep something on the bottom edge at
        // every instant: the bar returns *before* they leave, and leaves *after* they
        // arrive. Its frame stays valid while hidden — that is what they anchor to.
        if next.showsPill && visibilityRequested { setPillVisible(true) }

        switch next {
        case .explicitReply, .pill, .hoverRow, .inputBar, .replyInput:
            if wasGenerating { dismissGeneratingPanel() }
            if wasResult { dismissResultPanel() }
            stopDestinationTracking()
            if next.wantsKeyWindow { panel.makeKey() }

        case .generating(let pending):
            stopDestinationTracking()
            presentGeneratingPanel(pending)
            if wasResult { dismissResultPanel() }

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
        syncLessonGuide()

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
        guard introPresentation == nil, !isDraggingBar, !isAnimatingSnapLanding else { return }
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
    var usesSidebarLayout: Bool { parkedZone == .left || parkedZone == .right }

    var barMinimumSize: NSSize {
        if case .pill = state {
            switch parkedZone {
            case .left, .right:
                return NSSize(width: Tokens.Geometry.sideTabWidth, height: Tokens.Geometry.sideTabHeight)
            case .topCenter:
                return NSSize(width: max(64, notchWidth), height: Tokens.Geometry.pillHeight)
            case .bottomCenter:
                return NSSize(width: Tokens.Geometry.pillCollapsedWidth, height: Tokens.Geometry.pillHeight)
            }
        }
        return NSSize(width: parkedZone == .topCenter ? notchWidth : 0, height: state.contentHeight)
    }

    private func currentSize() -> NSSize {
        if case .pill = state { return barMinimumSize }
        return NSSize(width: max(measuredSize?.width ?? Tokens.Geometry.pillCollapsedWidth, barMinimumSize.width),
                      height: max(measuredSize?.height ?? 0, barMinimumSize.height))
    }

    /// §4: expansion animates the **window frame**. Animating only the view clips it,
    /// because a borderless window does not draw outside its bounds.
    private func resize(to size: NSSize, animated: Bool) {
        guard introPresentation == nil, !isDraggingBar, !isAnimatingSnapLanding else { return }
        let screen = OverlayPlacement.screen(containing: panel.frame)
        let target = OverlayPlacement.zoneFrame(parkedZone, barSize: size, on: screen)

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
            Task { @MainActor in panel.invalidateShadow() }
        }
    }

    // MARK: - Bar dragging (§4, docs/bar-positioning.md)

    private func barDidMove() {
        guard introPresentation == nil, !isAnimatingSnapLanding else { return }
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            if isDraggingBar { endBarDrag() }
            return
        }
        if !isDraggingBar {
            // Resize animations also post didMove while a button can be held.
            guard let start = panel.dragStartLocation,
                  hypot(NSEvent.mouseLocation.x - start.x, NSEvent.mouseLocation.y - start.y) > 3
            else { return }
            dragOriginScreen = OverlayPlacement.screen(containing: panel.dragStartFrame ?? panel.frame)
            collapseTask?.cancel()
            isDraggingBar = true
            syncLessonGuide()
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    if NSEvent.pressedMouseButtons & 1 == 0 { self?.endBarDrag() }
                }
            }
            dragEndTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        let frame = panel.frame
        let screen = OverlayPlacement.screen(containing: frame)
        activeSnapZone = OverlayPlacement.activeSnapZone(near: frame, on: screen)
        if snapOverlay == nil || snapOverlay?.displayID != SnapOverlayPanel.displayID(of: screen) {
            snapOverlay?.orderOut(nil)
            let overlay = SnapOverlayPanel(screen: screen, scrimOpacity: introDimmerVisible ? 0 : 0.64)
            if introDimmerVisible { overlay.level = panel.level }
            overlay.model.slots = OverlayPlacement.slotFrames(on: screen)
            overlay.orderFrontRegardless()
            panel.orderFrontRegardless()
            snapOverlay = overlay
        }
        snapOverlay?.model.active = activeSnapZone
        snapOverlay?.model.slots = OverlayPlacement.slotFrames(on: screen, active: activeSnapZone)
        replyContextPanel?.reanchor(to: frame)
        updateNoticePanel?.reanchor(to: frame)
    }

    func endBarDrag() {
        guard isDraggingBar else { return }
        dragEndTimer?.invalidate()
        dragEndTimer = nil
        isAnimatingSnapLanding = true
        isDraggingBar = false

        let destinationScreen = OverlayPlacement.screen(containing: panel.frame)
        let screen = activeSnapZone == nil
            ? dragOriginScreen.flatMap { original in NSScreen.screens.first { $0 == original } } ?? destinationScreen
            : destinationScreen
        parkedZone = activeSnapZone ?? parkedZone
        notchWidth = OverlayPlacement.notchFrame(on: screen)?.width ?? 0
        if debugIntroPlacement {
            introPlacementOverride = parkedZone
        } else {
            introPlacementOverride = nil
            OverlayPlacement.persist(zone: parkedZone)
        }
        activeSnapZone = nil
        dragOriginScreen = nil
        let slot = OverlayPlacement.zoneFrame(parkedZone, barSize: currentSize(), on: screen)
        replyContextPanel?.reanchor(to: slot)
        updateNoticePanel?.reanchor(to: slot)
        let overlay = snapOverlay
        snapOverlay = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(slot, display: true)
            overlay?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                overlay?.orderOut(nil)
                guard let self else { return }
                self.isAnimatingSnapLanding = false
                self.syncLessonGuide()
                self.panel.invalidateShadow()
                self.lastAppliedSize = nil
                self.applyMeasuredSize()
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.mouseExited() }
            }
        }
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

    #if DEBUG
    var replyPreviewPanel: PillPanel { panel }
    var replyPreviewHasDetachedContext: Bool { replyContextPanel != nil }

    func prepareReplyPreview(zone: SnapZone) {
        clearAvailableReply()
        transition(to: .pill)
        visibilityRequested = true
        parkedZone = zone
        let screen = NSScreen.main ?? OverlayPlacement.activeScreen()
        notchWidth = OverlayPlacement.notchFrame(on: screen)?.width ?? 0
        measuredSize = nil
        lastAppliedSize = nil
        if !(panel.contentView is NSHostingView<PillRootView>) {
            let host = NSHostingView(rootView: PillRootView(controller: self))
            host.sizingOptions = []
            panel.contentView = host
        }
        panel.setFrame(OverlayPlacement.zoneFrame(zone, barSize: barMinimumSize, on: screen), display: true)
        panel.orderFrontRegardless()
    }

    func previewCopy(_ source: ReplySource?) { armReply(source) }

    func previewReplyComposer() {
        guard let source = availableReplySource else { return }
        clearAvailableReply()
        transition(to: .replyInput(reply: source, target: CapturedTarget(
            target: TextTarget(text: "", captureMode: .wholeInput, path: .ax, writeStrategy: .none),
            frontmostPID: nil)))
    }

    var previewWritingCapture: Result<TextTarget, TextIOError>?
    var previewError: ErrorPanel? { errorPanel }
    var edgePreviewResult: ResultPanel? { resultPanel }

    func configureEdgePreview(context: ResultContext, zone: SnapZone) {
        dismiss()
        parkedZone = zone
        let screen = NSScreen.main ?? OverlayPlacement.activeScreen()
        panel.setFrame(OverlayPlacement.zoneFrame(zone, barSize: NSSize(width: 44, height: 28), on: screen), display: false)
        transition(to: .result(context))
        stopDestinationTracking()
    }
    #endif

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

    private func syncReplyContextPanel(for next: OverlayState) {
        if case .explicitReply = next {
            if replyContextPanel?.source == nil, replyContextPanel != nil {
                replyContextPanel?.reanchor(to: panel.frame)
            } else {
                replyContextPanel?.orderOut(nil)
                let card = ReplyContextPanel(anchor: panel.frame, source: nil, controller: self, onDismiss: { [weak self] in self?.dismissReply() })
                card.orderFrontRegardless()
                replyContextPanel = card
            }
            return
        }
        replyContextPanel?.orderOut(nil)
        replyContextPanel = nil
    }

    private var companionGeometry: CompanionGeometry {
        CompanionGeometry(zone: parkedZone, anchor: panel.frame,
                          screen: OverlayPlacement.screen(containing: panel.frame))
    }

    private func presentGeneratingPanel(_ pending: PendingRewrite) {
        dismissGeneratingPanel()
        let generating = GeneratingPanel(
            geometry: companionGeometry,
            // **A progress word, not the button's name.** The capsule used to be
            // labelled with `buttonTitle`, so pressing 差し替え put 「差し替え」 on a
            // capsule that is not replacing anything yet — nothing has been written
            // back at this point and the rewrite may still fail. The one thing that is
            // true while it is on screen is that a candidate is being generated.
            label: !pending.isReply
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
            existing.reanchor(companionGeometry)
            existing.update(context: context)
            existing.orderFrontRegardless()
            return
        }
        let result = ResultPanel(geometry: companionGeometry, controller: self, context: context)
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
        lessonEvent(.failed)
        // Closes the attempt as a generation failure. A capture failure has already
        // closed its own attempt via `reportCaptureFailure` before reaching here, so
        // this is a no-op for those — which is the point of routing every terminal
        // report through one idempotent call rather than emitting at each site.
        //
        // A message with no attempt open at all (an insert failure on an old result, a
        // sign-in prompt) reports nothing, which is correct: those are not attempts.
        finishAttempt(
            .failed(stage: .generation, message: message),
            target: currentGeneratingTarget
        )

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
        // Stack inward from whichever surface currently owns the selected edge.
        // An insert failure can anchor to a result card that is still measuring.
        //
        // The **window**, not its frame: the result card is created at 440 pt and shrinks
        // to its measured height a pass later, so a rectangle taken here is a number that
        // was never true for longer than one layout (see `ErrorPanel`).
        let anchor: NSWindow = resultPanel
            ?? generatingPanel
            ?? replyContextPanel
            ?? panel
        let toast = ErrorPanel(anchor: anchor, zone: parkedZone, message: message) { [weak self] in
            self?.dismissErrorToast()
        }
        toast.orderFrontRegardless()
        errorPanel = toast
        syncLessonGuide()

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
        syncLessonGuide()
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
            //
            // **It leads with clicking into the field, and that ordering is the fix.**
            // The message used to offer selecting and ✎ only, which describes two of the
            // three ways out and omits the one the product is actually built around:
            // `.wholeInput` rewrites the focused field with nothing selected (§5), and it
            // is the case the clipboard cannot serve. Telling someone to select text when
            // clicking into their draft would have worked teaches them the slower half of
            // the product, and reads as a refusal when the field is right there.
            return tr(
                "書き換える文章がありません。書きかけの入力欄をクリックするか、文章を選択してから、もう一度お試しください。✎ なら新しい文章を書けます。",
                "There's no text to rewrite. Click into the field you're writing in, or select some text, then try again — or use ✎ to write something new.",
                "没有可改写的文字。请点击你正在输入的输入框，或选中文字后重试；用 ✎ 可以写一段新文字。"
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
