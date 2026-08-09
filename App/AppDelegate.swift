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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SPUUpdaterDelegate {

    private var overlay: OverlayController?
    private var mainWindow: MainWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var mainModel: MainModel?
    private var statusItem: NSStatusItem?
    private var onboardingMenuItem: NSMenuItem?
    private var checkForUpdatesMenuItem: NSMenuItem?
    /// The status menu's only escape hatch once a right-click hide has taken the pill
    /// off screen (§17) — there is nothing left to right-click at that point. Hidden
    /// whenever `overlay.isHiddenBySnooze` is false, rather than removed and re-added,
    /// so `menuNeedsUpdate` only ever toggles one item instead of rebuilding the menu.
    private var reshowOverlayItem: NSMenuItem?
    private var reshowOverlaySeparator: NSMenuItem?
    private let onboardingProgress = OnboardingProgressStore()
    private var updaterStarted = false
    private var deferredUpdateCheckTask: Task<Void, Never>?

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
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

        let rewriteService = DesktopRewriteService(config: config, auth: auth)
        let promptStore = UserPromptRemoteStore(config: config, auth: auth)
        let profileStore = ProfileRemoteStore(config: config, auth: auth)
        let billingStore = BillingRemoteStore(config: config, auth: auth)

        let overlay = OverlayController(
            rewriteService: rewriteService,
            promptStore: promptStore,
            analytics: NoopAnalytics(),
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
            withTitle: "敬語ボタンを隠す",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        app.addItem(.separator())
        app.addItem(
            withTitle: "終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = app
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "編集")
        edit.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: "すべてを選択",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "ウインドウ")
        window.addItem(
            withTitle: "閉じる",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        window.addItem(
            withTitle: "しまう",
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
        let markImage = NSImage(named: Icon.Name.mark.rawValue)
        markImage?.isTemplate = true
        markImage?.size = NSSize(width: 18, height: 18)
        markImage?.accessibilityDescription = "敬語ボタン"
        item.button?.image = markImage

        let menu = NSMenu()
        menu.delegate = self

        // Starts hidden — `menuNeedsUpdate` is what shows it, and only while
        // `overlay.isHiddenBySnooze`.
        let reshowItem = menu.addItem(
            withTitle: "",
            action: #selector(reshowOverlay),
            keyEquivalent: ""
        )
        reshowItem.target = self
        reshowItem.isHidden = true
        reshowOverlayItem = reshowItem
        let reshowSeparator = NSMenuItem.separator()
        reshowSeparator.isHidden = true
        menu.addItem(reshowSeparator)
        reshowOverlaySeparator = reshowSeparator

        menu.addItem(
            withTitle: "敬語ボタンを開く",
            action: #selector(openMainWindow),
            keyEquivalent: ""
        ).target = self
        let onboardingItem = menu.addItem(
            withTitle: onboardingProgress.isComplete ? "使い方を見る" : "セットアップを続ける",
            action: #selector(openOnboarding),
            keyEquivalent: ""
        )
        onboardingItem.target = self
        onboardingMenuItem = onboardingItem
        menu.addItem(
            withTitle: "環境設定…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        ).target = self
        menu.addItem(
            withTitle: "ボタンを再読み込み",
            action: #selector(reloadPrompts),
            keyEquivalent: "r"
        ).target = self
        let updateItem = menu.addItem(
            withTitle: "アップデートを確認…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        checkForUpdatesMenuItem = updateItem
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.menu = menu
        statusItem = item
    }

    /// Runs right before the status menu opens — the same "ask again at click time"
    /// shape `PillRootView`'s right-click menu uses for its own copy-disabled row,
    /// just via AppKit's delegate hook instead of a fresh SwiftUI `ViewBuilder` call.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let overlay, let reshowItem = reshowOverlayItem, let separator = reshowOverlaySeparator else {
            return
        }
        let hidden = overlay.isHiddenBySnooze
        reshowItem.isHidden = !hidden
        separator.isHidden = !hidden
        if hidden {
            let minutes = overlay.hiddenRemainingMinutes ?? 0
            reshowItem.title = "敬語ボタンを今すぐ再表示する（残り\(minutes)分）"
        }
        checkForUpdatesMenuItem?.isEnabled = updaterStarted
            && updaterController.updater.canCheckForUpdates
            && overlay.allowsUpdateCheck
    }

    @objc private func reshowOverlay() {
        overlay?.cancelHideNow()
    }

    @objc private func openMainWindow() {
        guard onboardingProgress.isComplete else {
            openOnboarding()
            return
        }
        guard let mainModel else { return }
        if mainWindow == nil {
            mainWindow = MainWindowController(model: mainModel)
        }
        mainModel.refresh()
        mainWindow?.present()
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
                progress: onboardingProgress
            ) { [weak self] in
                guard let self else { return }
                self.onboardingWindow?.close()
                self.onboardingMenuItem?.title = "使い方を見る"
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
                    NSLocalizedDescriptionKey: "現在の操作が終わってからアップデートを確認します。"
                ]
            )
        }
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
                if self.overlay?.allowsUpdateCheck == true {
                    self.deferredUpdateCheckTask = nil
                    self.updaterController.updater.checkForUpdatesInBackground()
                    return
                }
            }
        }
    }
}
