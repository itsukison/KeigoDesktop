import AppKit
import DesktopRewriteKit
import Sparkle
import SwiftUI
import TextIO

@main
struct KeigoButtonMacApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SPUUpdaterDelegate,
    @preconcurrency SPUStandardUserDriverDelegate
{

    private var overlay: OverlayController?
    private var mainWindow: MainWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var mainModel: MainModel?
    private var statusItem: NSStatusItem?
    private var onboardingMenuItem: NSMenuItem?
    private var checkForUpdatesMenuItem: NSMenuItem?
    /// The two time-boxed actions the pill's own right-click menu offers (§17), which
    /// until now could only be reached by right-clicking the pill — and the hide could
    /// only be *undone* from here, because a hidden pill has nothing left to right-click.
    /// One row each, one hour each: the title and the meaning flip with the state, so
    /// there is never a stale 「無効にする」 sitting under an active window. `menuNeedsUpdate`
    /// rewrites the titles; the selectors read the state again at click time, so a window
    /// that expires while the menu is open still does the right thing.
    private var hideOverlayItem: NSMenuItem?
    private var copyTriggerItem: NSMenuItem?
    /// 「アップデート v0.1.3 をインストール」 — hidden until Sparkle has actually found
    /// something. The status item is the one part of this app that is always on screen
    /// and always reachable, so it carries the find whether or not the user ever
    /// dismissed the panel above the bar or opened the window.
    private var updateAvailableItem: NSMenuItem?
    private var updateSeparatorItem: NSMenuItem?
    /// Mirrors `MainModel.availableUpdateVersion`, so the menu and the status-item badge
    /// can be rebuilt from a language change without asking the model again.
    private var pendingUpdateVersion: String?
    private let onboardingProgress = OnboardingProgressStore()
    private let languageStore = AppLanguageStore()
    private var statusMenu: NSMenu?
    private var updaterStarted = false
    private var deferredUpdateCheckTask: Task<Void, Never>?
    /// How recent a check has to be for a wake to leave it alone. Ten minutes against
    /// an hourly floor: often enough that coming back to the machine is a real
    /// opportunity to hear about a release, rare enough that a burst of wake
    /// notifications is still one appcast read.
    private static let wakeUpdateCheckThrottle: TimeInterval = 600

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    private lazy var appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }()

    private lazy var config = SupabaseConfig(appVersion: appVersion)
    private lazy var auth = AuthService(config: config)
    /// Owned here, shared by the overlay (which writes it) and the main window (which
    /// reads it). One actor, so the two cannot race.
    private let history = RewriteHistoryStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // §9: no Dock icon. The pill is the app's real surface; the main window is
        // reached from the menu bar and does not change the activation policy — a
        // policy flip on open would momentarily steal focus, which §4 forbids.
        NSApp.setActivationPolicy(.accessory)
        // Before any window, menu or view is built: `tr` reads a global, and anything
        // constructed ahead of this would be built in the wrong language and never
        // rebuilt (§17).
        languageStore.activate()
        PostHogConfiguration.configure()

        let rewriteService = DesktopRewriteService(config: config, auth: auth)
        let promptStore = UserPromptRemoteStore(config: config, auth: auth)
        let profileStore = ProfileRemoteStore(config: config, auth: auth)
        let billingStore = BillingRemoteStore(config: config, auth: auth)

        let overlay = OverlayController(
            rewriteService: rewriteService,
            promptStore: promptStore,
            analytics: PostHogAnalytics(),
            history: history,
            appVersion: appVersion
        )
        self.overlay = overlay

        mainModel = MainModel(
            auth: auth,
            promptStore: promptStore,
            profileStore: profileStore,
            billingStore: billingStore,
            history: history,
            appVersion: appVersion,
            onPromptsChanged: { [weak overlay] in await overlay?.refreshPrompts() }
        )
        // The menu bar is AppKit, built once, and outside every SwiftUI observation
        // graph — so it is the one surface a language change cannot reach on its own.
        mainModel?.onLanguageChanged = { [weak self] in self?.relabelForLanguage() }
        // A scheduled Sparkle check is intentionally quiet. When one of the three
        // notices is pressed, this brings Sparkle's already-validated update into focus
        // and leaves download, signature verification and installation with Sparkle.
        mainModel?.onUpdateRequested = { [weak self] in self?.checkForUpdates(nil) }
        // Sparkle's find reaches the bar and the menu bar through here. The model owns
        // the record; the two AppKit surfaces are this file's, and neither is something
        // a SwiftUI card can reach.
        mainModel?.onUpdateNoticeChanged = { [weak self] version in
            self?.updateNoticeChanged(to: version)
        }
        overlay.onUpdateRequested = { [weak self] in self?.mainModel?.requestAvailableUpdate() }
        overlay.onUpdateNoticeDismissed = { [weak self] version in
            self?.mainModel?.dismissUpdateNotice(for: version)
        }

        // §9 row 41. A free user who hits the monthly cap pressed a button and got
        // nothing back, so the plan pane is the answer to what just happened — not a
        // second thing to go and find.
        overlay.onQuotaPaywall = { [weak self] in self?.openPlan() }
        overlay.onSignInRequired = { [weak self] in self?.openSignIn() }

        installMainMenu()
        installStatusItem()

        // §5: onboarding gates on Accessibility. Without it there is no product, so the
        // window opens on the permission banner instead of the overlay appearing and
        // doing nothing. A signed-out launch opens it for the same reason: the hover
        // row would have no buttons to show.
        overlay.show()
        if !onboardingProgress.isComplete {
            overlay.setVisible(false)
            openOnboarding()
            return
        }
        // Before the updater, and deliberately after the onboarding return above: an
        // update found in an earlier run is announced again now rather than waiting a
        // day for the next scheduled check to rediscover it.
        mainModel?.restorePendingUpdate()
        observeSystemWake()
        startUpdaterIfConfigured()
        Task { [auth] in
            let signedIn = await auth.isSignedIn
            if !AXPermission.isTrusted || !signedIn { openMainWindow() }
        }
    }

    /// Closing the window is not quitting. The overlay is the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// §5: re-check on every activation — the Accessibility permission is revoked
    /// whenever the binary changes identity, which is every dev rebuild.
    func applicationDidBecomeActive(_ notification: Notification) {
        mainModel?.refresh()
    }

    // MARK: - URL scheme

    /// Two legs arrive here, and they are told apart by host.
    ///
    /// - `keigobutton://auth-callback` — the OAuth return (§6).
    ///   `ASWebAuthenticationSession` normally intercepts this itself; this path is
    ///   what catches the redirect when the sheet has already been dismissed.
    /// - `keigobutton://billing` — the 「アプリに戻る」 button on the Checkout return
    ///   pages. Checkout hands off to the DEFAULT BROWSER (Apple Pay needs Safari's
    ///   payment sheet), so the user finishes the purchase outside the app and has no
    ///   route back except the Dock. This is that route.
    ///
    /// The billing leg re-reads entitlement rather than trusting the redirect. A
    /// `success_url` fires the moment Stripe redirects, which can beat the webhook —
    /// treating it as proof of payment is how an unpaid session gets granted Pro
    /// (§3.3). The webhook remains the only writer; this just asks again.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "keigobutton" {
            if url.host == "billing" {
                NSApp.activate(ignoringOtherApps: true)
                openPlan()
                Task { [mainModel] in await mainModel?.reloadEntitlement() }
            } else {
                Task { [mainModel] in await mainModel?.completeOAuth(url: url) }
            }
        }
    }

    // MARK: - Main menu

    /// An `.accessory` app never *displays* a menu bar — but without a main menu it
    /// also has no key equivalents, and `⌘C`, `⌘V`, `⌘A` and `⌘Z` do nothing in every
    /// text field in the window. Key-equivalent dispatch walks `NSApp.mainMenu`
    /// whether or not it is on screen, so this menu is invisible and load-bearing.
    ///
    /// The selectors are the standard responder-chain ones; they go to whatever field
    /// is first responder, so nothing here needs a target.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(
            withTitle: tr("敬語ボタンを隠す", "Hide KeigoButton", "隐藏敬語ボタン"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        app.addItem(.separator())
        app.addItem(
            withTitle: tr("終了", "Quit", "退出"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = app
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: tr("編集", "Edit", "编辑"))
        edit.addItem(
            withTitle: tr("取り消す", "Undo", "撤销"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        edit.addItem(
            withTitle: tr("やり直す", "Redo", "重做"),
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        edit.addItem(.separator())
        edit.addItem(
            withTitle: tr("カット", "Cut", "剪切"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        edit.addItem(
            withTitle: tr("コピー", "Copy", "复制"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        edit.addItem(
            withTitle: tr("ペースト", "Paste", "粘贴"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        edit.addItem(
            withTitle: tr("すべてを選択", "Select All", "全选"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: tr("ウインドウ", "Window", "窗口"))
        window.addItem(
            withTitle: tr("閉じる", "Close", "关闭"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        window.addItem(
            withTitle: tr("しまう", "Minimize", "最小化"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The outline cut, as a template: the menu bar inverts its own contents for a
        // dark menu bar and for a selected item, which only works on alpha. The colour
        // mark would sit there as a white tile that never inverts.
        item.button?.image = Self.statusImage(
            badged: pendingUpdateVersion != nil,
            description: productName
        )

        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu

        // First row, above 開く: it is the only thing in this menu that is time-sensitive
        // and the only one that is not always true. Hidden — not disabled — when there is
        // no update, so the menu reads exactly as it did before whenever nothing is
        // pending.
        let pendingItem = menu.addItem(
            withTitle: "",
            action: #selector(installAvailableUpdate),
            keyEquivalent: ""
        )
        pendingItem.target = self
        updateAvailableItem = pendingItem
        let pendingSeparator = NSMenuItem.separator()
        menu.addItem(pendingSeparator)
        updateSeparatorItem = pendingSeparator

        menu.addItem(
            withTitle: tr("敬語ボタンを開く", "Open KeigoButton", "打开敬語ボタン"),
            action: #selector(openMainWindow),
            keyEquivalent: ""
        ).target = self
        let onboardingItem = menu.addItem(
            withTitle: onboardingMenuTitle,
            action: #selector(openOnboarding),
            keyEquivalent: ""
        )
        onboardingItem.target = self
        onboardingMenuItem = onboardingItem
        menu.addItem(
            withTitle: tr("環境設定…", "Settings…", "偏好设置…"),
            action: #selector(openPreferences),
            keyEquivalent: ","
        ).target = self
        menu.addItem(
            withTitle: tr("ボタンを再読み込み", "Reload buttons", "重新加载按钮"),
            action: #selector(reloadPrompts),
            keyEquivalent: "r"
        ).target = self
        menu.addItem(.separator())
        // Titles are placeholders; `menuNeedsUpdate` writes the real ones.
        let hideItem = menu.addItem(
            withTitle: "",
            action: #selector(toggleOverlayHidden),
            keyEquivalent: ""
        )
        hideItem.target = self
        hideOverlayItem = hideItem
        let copyItem = menu.addItem(
            withTitle: "",
            action: #selector(toggleCopyTrigger),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyTriggerItem = copyItem
        menu.addItem(.separator())
        let updateItem = menu.addItem(
            withTitle: tr("アップデートを確認…", "Check for Updates…", "检查更新…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        checkForUpdatesMenuItem = updateItem
        menu.addItem(.separator())
        menu.addItem(
            withTitle: tr("終了", "Quit", "退出"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.menu = menu
        statusItem = item
        // The pending row is built with no title and no hidden flag, so it has to be put
        // into whichever of its two states is current — including after a language
        // change, which throws the whole status item away and builds it again.
        updateNoticeChanged(to: pendingUpdateVersion)
    }

    /// The menu-bar glyph, optionally carrying the one-dot "there is something here"
    /// mark that every other menu-bar app uses for the same purpose.
    ///
    /// **Drawn rather than a second asset**, and drawn as a template: the menu bar
    /// inverts its own contents for a dark bar and for a selected item, and it does that
    /// from alpha. A badge composited as colour would sit there as a coloured tile that
    /// never inverts — which is the same mistake the colour mark would have been.
    ///
    /// The dot is knocked out of the mark with `.clear` before it is filled, so it stays
    /// legible where it overlaps the glyph's own strokes instead of merging into them.
    private static func statusImage(badged: Bool, description: String) -> NSImage? {
        guard let mark = NSImage(named: Icon.Name.mark.rawValue) else { return nil }
        mark.size = NSSize(width: 18, height: 18)

        guard badged else {
            mark.isTemplate = true
            mark.accessibilityDescription = description
            return mark
        }

        let size = NSSize(width: 18, height: 18)
        let badged = NSImage(size: size, flipped: false) { _ in
            mark.draw(in: NSRect(origin: .zero, size: size))

            let dot = NSRect(x: 12, y: 12, width: 5, height: 5)
            let gap = dot.insetBy(dx: -1.5, dy: -1.5)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: gap).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        badged.isTemplate = true
        badged.accessibilityDescription = description
        return badged
    }

    /// The product name is the same word in Japanese and Chinese — a 简体中文 user is
    /// writing Japanese and knows the app by its Japanese name (§17). Only English
    /// spells it out.
    private var productName: String { tr("敬語ボタン", "KeigoButton", "敬語ボタン") }

    private var onboardingMenuTitle: String {
        onboardingProgress.isComplete
            ? tr("使い方を見る", "See how it works", "查看使用方法")
            : tr("セットアップを続ける", "Continue setup", "继续设置")
    }

    /// Both menus are AppKit objects built once at launch, so a language chosen on
    /// §15's first page leaves them in the old one. Rebuilding is cheap and happens
    /// at most a handful of times in a session.
    private func relabelForLanguage() {
        installMainMenu()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        installStatusItem()
    }

    /// Runs right before the status menu opens — the same "ask again at click time"
    /// shape `PillRootView`'s right-click menu uses for its own copy-disabled row,
    /// just via AppKit's delegate hook instead of a fresh SwiftUI `ViewBuilder` call.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let overlay else { return }
        let hour = OverlaySnooze.Duration.oneHour.label
        if overlay.isHiddenBySnooze {
            let minutes = overlay.hiddenRemainingMinutes ?? 0
            hideOverlayItem?.title = tr(
                "敬語ボタンを今すぐ再表示する（残り\(minutes)分）",
                "Show the bar now (\(minutes) min left)",
                "立即重新显示敬語ボタン（剩余\(minutes)分钟）"
            )
        } else {
            hideOverlayItem?.title = tr(
                "敬語ボタンを\(hour)非表示にする",
                "Hide the bar for \(hour)",
                "隐藏敬語ボタン\(hour)"
            )
        }
        if overlay.isCopyTriggerDisabled {
            let minutes = overlay.copyDisabledRemainingMinutes ?? 0
            copyTriggerItem?.title = tr(
                "コピー機能を今すぐ有効にする（残り\(minutes)分）",
                "Turn copy detection back on (\(minutes) min left)",
                "立即启用复制功能（剩余\(minutes)分钟）"
            )
        } else {
            copyTriggerItem?.title = tr(
                "コピー機能を\(hour)無効にする",
                "Turn copy detection off for \(hour)",
                "停用复制功能\(hour)"
            )
        }
        checkForUpdatesMenuItem?.isEnabled = updaterStarted
            && updaterController.updater.canCheckForUpdates
            && overlay.allowsUpdateCheck
    }

    // MARK: - The update notice

    /// The one place the three surfaces are kept in step.
    ///
    /// **All three, because no single one of them is enough.** The panel above the bar is
    /// the only surface a user who never opens a window will see, and it is dismissible,
    /// so it cannot be the only record. The status-menu row is permanent but only found
    /// by someone already opening the menu. The ホーム card is the fullest description
    /// and the least likely to be looked at. 0.1.2 shipped the third one alone.
    private func updateNoticeChanged(to version: String?) {
        pendingUpdateVersion = version

        // Dismissing the panel silences *it* and nothing else, so this is the one
        // surface that asks. The row and the badge below deliberately do not.
        let showsPanel = version.map { mainModel?.isUpdateNoticeDismissed($0) == false } ?? false
        overlay?.setPendingUpdate(showsPanel ? version : nil)

        updateAvailableItem?.isHidden = version == nil
        updateSeparatorItem?.isHidden = version == nil
        if let version {
            updateAvailableItem?.title = tr(
                "アップデート v\(version) をインストール",
                "Install update v\(version)",
                "安装更新 v\(version)"
            )
        }
        statusItem?.button?.image = Self.statusImage(
            badged: version != nil,
            description: productName
        )
    }

    @objc private func installAvailableUpdate() {
        mainModel?.requestAvailableUpdate()
    }

    /// The state is read here rather than baked into the item when the menu was built:
    /// a window can expire while the menu sits open, and the row would then do the
    /// opposite of what it says.
    @objc private func toggleOverlayHidden() {
        guard let overlay else { return }
        if overlay.isHiddenBySnooze {
            overlay.cancelHideNow()
        } else {
            overlay.hideOverlay(for: .oneHour)
        }
    }

    @objc private func toggleCopyTrigger() {
        guard let overlay else { return }
        if overlay.isCopyTriggerDisabled {
            overlay.enableCopyTriggerNow()
        } else {
            overlay.disableCopyTrigger(for: .oneHour)
        }
    }

    @objc private func openMainWindow() {
        showMainWindow(activating: true)
    }

    /// `activating: false` is for the one caller the user did not ask anything of — the
    /// update notice opening the dashboard by itself. See
    /// `MainWindowController.presentWithoutActivating`.
    private func showMainWindow(activating: Bool) {
        guard onboardingProgress.isComplete else {
            openOnboarding()
            return
        }
        guard let mainModel else { return }
        if mainWindow == nil {
            mainWindow = MainWindowController(model: mainModel)
        }
        mainModel.refresh()
        if activating {
            mainWindow?.present()
        } else {
            mainWindow?.presentWithoutActivating()
        }
    }

    @objc private func openPreferences() {
        guard onboardingProgress.isComplete else {
            openOnboarding()
            return
        }
        mainModel?.showsPreferences = true
        openMainWindow()
    }

    /// The ⚙︎ modal opened straight onto プラン. Onboarding is not a gate here the way
    /// it is for the two above: hitting the cap means the app has already been used,
    /// so the flow is finished by construction.
    private func openPlan() {
        mainModel?.preferencesSection = .plan
        mainModel?.showsPreferences = true
        openMainWindow()
    }

    /// A missing session found from the overlay is a returning-user recovery path,
    /// not a reason to replay onboarding. Close any stale settings modal and put the
    /// existing account form directly into sign-in mode.
    private func openSignIn() {
        mainModel?.page = .account
        mainModel?.authMode = .signIn
        mainModel?.showsPreferences = false
        openMainWindow()
    }

    @objc private func openOnboarding() {
        guard let mainModel, let overlay else { return }
        if onboardingWindow == nil {
            let coordinator = OnboardingCoordinator(
                mainModel: mainModel,
                overlay: overlay,
                progress: onboardingProgress,
                languageStore: languageStore
            ) { [weak self] in
                guard let self else { return }
                self.onboardingWindow?.close()
                self.onboardingMenuItem?.title = self.onboardingMenuTitle
                self.startUpdaterIfConfigured()
                self.openMainWindow()
            }
            onboardingWindow = OnboardingWindowController(coordinator: coordinator)
        }
        onboardingWindow?.present(replay: onboardingProgress.isComplete)
    }

    @objc private func reloadPrompts() {
        Task { await overlay?.refreshPrompts() }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        guard updaterStarted, overlay?.allowsUpdateCheck == true else { return }
        updaterController.checkForUpdates(sender)
    }

    private func startUpdaterIfConfigured() {
        guard !updaterStarted, onboardingProgress.isComplete else { return }
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        guard let publicKey, !publicKey.isEmpty, !publicKey.contains("$(") else { return }
        updaterController.startUpdater()
        updaterStarted = true
        // `startUpdater` only looks straight away when the scheduled interval has
        // *already* elapsed; inside it, Sparkle just arms its timer. Ask anyway, so
        // every launch reads the appcast once. `requestBackgroundUpdateCheck` stands
        // down when Sparkle is already mid-session, so the overdue case is not checked
        // twice.
        requestBackgroundUpdateCheck()
    }

    /// Look now, or as soon as looking is safe.
    ///
    /// **Why this exists beside the timer.** `SUScheduledCheckInterval` is a ceiling on
    /// how stale a find can be, and Sparkle clamps it to an hour, so the timer alone
    /// cannot answer "the release went out, when will they hear about it?" any better
    /// than that. `checkForUpdatesInBackground` has no rate limit of its own, so the
    /// moments that mean *the user is back and the machine has been away* are cheaper
    /// and better-timed than a tick whose phase is set by whenever the app last
    /// launched.
    ///
    /// `canCheckForUpdates` is false exactly while a Sparkle session is in progress. A
    /// false reading is therefore not a reason to defer — Sparkle is already looking,
    /// or already holding a find this app has announced — so this returns instead of
    /// arming the retry loop and stacking a second check behind the first.
    private func requestBackgroundUpdateCheck() {
        guard updaterStarted, updaterController.updater.canCheckForUpdates else { return }
        guard overlay?.allowsUpdateCheck == true else {
            scheduleDeferredUpdateCheck()
            return
        }
        updaterController.updater.checkForUpdatesInBackground()
    }

    /// `NSWorkspace`'s own centre, not `NotificationCenter.default` — these two names are
    /// only posted on the workspace centre, and observing the wrong one is silent.
    ///
    /// Both names, because they answer different questions: `didWake` is the machine
    /// coming out of sleep, `screensDidWake` is the display coming back while the
    /// machine never slept, which is what a lock-and-return actually looks like. The
    /// throttle in `systemDidWake` is what makes registering for both cheap.
    private func observeSystemWake() {
        let centre = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            centre.addObserver(
                self,
                selector: #selector(systemDidWake),
                name: name,
                object: nil
            )
        }
    }

    /// Waking is the one event that reliably means the user has come back to a machine
    /// that was away, and it is the moment a pending update is most worth mentioning.
    ///
    /// Throttled, because these arrive in bursts — opening a lid fires `didWake` and
    /// `screensDidWake` together, and a display that sleeps on its own at a desk fires
    /// the latter repeatedly through a day. `lastUpdateCheckDate` is Sparkle's own
    /// record, so this also stands down after a check the timer just made.
    @objc private func systemDidWake() {
        guard updaterStarted else { return }
        if let last = updaterController.updater.lastUpdateCheckDate,
           Date().timeIntervalSince(last) < Self.wakeUpdateCheckThrottle {
            return
        }
        requestBackgroundUpdateCheck()
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard onboardingProgress.isComplete, overlay?.allowsUpdateCheck == true else {
            if updateCheck == .updatesInBackground {
                scheduleDeferredUpdateCheck()
            }
            throw NSError(
                domain: "com.core7.keigobutton.mac.updates",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: tr(
                        "現在の操作が終わってからアップデートを確認します。",
                        "Updates will be checked once the current rewrite is finished.",
                        "将在当前操作完成后检查更新。"
                    )
                ]
            )
        }
    }

    // MARK: - Sparkle gentle reminders

    /// This accessory app has no Dock presence and its scheduled Sparkle alert can be
    /// ordered behind the app the user is working in. Claim gentle-reminder support so
    /// background discoveries become a durable dashboard notice instead. User-started
    /// checks still use Sparkle's standard update window.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        let version = update.displayVersionString
        let isFirstSighting = pendingUpdateVersion != version
        mainModel?.offerUpdate(version: version)

        // The dashboard opens **once per version**, on the run that discovers it. Not on
        // every relaunch afterwards: the bar and the menu bar carry the notice from then
        // on, and a window that reopened itself every morning would be the nag this is
        // trying not to be. Nothing opens it if the user already dismissed this version.
        //
        // **Without activating**, which is the whole difference between this and the
        // Sparkle alert two methods up that we declined. Sparkle's find can land within
        // three seconds of the updater starting, and for an app registered with
        // `SMAppService` that means during login — so the one moment this is most likely
        // to fire is the worst possible moment to take someone's keyboard. The window
        // arrives in front and waits to be clicked.
        guard isFirstSighting,
              mainModel?.isUpdateNoticeDismissed(version) == false,
              onboardingProgress.isComplete,
              overlay?.allowsUpdateCheck == true
        else { return }
        mainModel?.page = .home
        mainModel?.showsPreferences = false
        showMainWindow(activating: false)
    }

    /// Once the user has brought Sparkle's real update window forward, the dashboard
    /// has done its job. Sparkle owns the remaining dismiss, skip and install choices.
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        mainModel?.clearUpdateNotice()
    }

    func standardUserDriverWillFinishUpdateSession() {
        mainModel?.clearUpdateNotice()
    }

    /// Sparkle's delegate can decline a scheduled check, but declining alone postpones
    /// it until the next daily interval. Retry as soon as the overlay becomes passive so
    /// an update discovered during a long result/input session is not delayed by a day.
    private func scheduleDeferredUpdateCheck() {
        guard deferredUpdateCheckTask == nil else { return }
        deferredUpdateCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                guard self.updaterStarted else { continue }
                // Both conditions, and the task stays armed until both hold. Declining
                // in `mayPerform` aborts a session that is still being torn down, so
                // `canCheckForUpdates` can be false for a moment after the refusal —
                // and `checkForUpdatesInBackground` logs an error and returns when it
                // is. Clearing the task before that call was how the retry got lost:
                // nothing was left to re-arm it, and the find waited for the next
                // launch or the next interval.
                if self.overlay?.allowsUpdateCheck == true,
                   self.updaterController.updater.canCheckForUpdates {
                    self.deferredUpdateCheckTask = nil
                    self.updaterController.updater.checkForUpdatesInBackground()
                    return
                }
            }
        }
    }
}
