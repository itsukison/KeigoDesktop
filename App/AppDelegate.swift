import AppKit
import DesktopRewriteKit
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
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var overlay: OverlayController?
    private var mainWindow: MainWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var mainModel: MainModel?
    private var statusItem: NSStatusItem?
    private var onboardingMenuItem: NSMenuItem?
    private let onboardingProgress = OnboardingProgressStore()

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
            history: history,
            appVersion: appVersion,
            onPromptsChanged: { [weak overlay] in await overlay?.refreshPrompts() }
        )

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

    /// The `keigobutton://auth-callback` leg of an OAuth sign-in (§6).
    ///
    /// `ASWebAuthenticationSession` normally intercepts this itself; this path is what
    /// catches the redirect when the sheet has already been dismissed.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "keigobutton" {
            Task { [mainModel] in await mainModel?.completeOAuth(url: url) }
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
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.menu = menu
        statusItem = item
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
                self.openMainWindow()
            }
            onboardingWindow = OnboardingWindowController(coordinator: coordinator)
        }
        onboardingWindow?.present(replay: onboardingProgress.isComplete)
    }

    @objc private func reloadPrompts() {
        Task { await overlay?.refreshPrompts() }
    }
}
