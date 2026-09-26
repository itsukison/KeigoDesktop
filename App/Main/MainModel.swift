import AppKit
import AuthenticationServices
import DesktopRewriteKit
import PostHog
import ServiceManagement
import SwiftUI
import TextIO

/// Everything the main window shows and does.
///
/// One model rather than one per page: the pages are not independent — signing in has
/// to repopulate the button list, editing a button has to re-push the hover row, and
/// clearing history has to redraw the stat cards. Splitting them would mean wiring
/// those three edges back together by hand.
@MainActor
final class MainModel: NSObject, ObservableObject {

    enum Page: Hashable {
        case home
        case buttons
        case account
    }

    enum AuthMode: Hashable {
        case signIn
        case signUp
    }

    // MARK: Navigation

    @Published var page: Page = .home
    @Published var showsPreferences = false
    /// Which ⚙︎ pane is open. On the model rather than in `PreferencesSheet` because
    /// the overlay opens it on プラン when a free user hits the monthly cap (§9 row
    /// 41), and a `@State` in the view is unreachable from there.
    @Published var preferencesSection: PreferencesSheet.Section = .general

    // MARK: Account

    @Published var email = ""
    @Published var password = ""
    @Published var passwordConfirm = ""
    @Published var authMode: AuthMode = .signIn
    @Published private(set) var signedInEmail: String?
    @Published private(set) var authError: String?
    @Published private(set) var authNotice: String?
    @Published private(set) var isAuthenticating = false

    var isSignedIn: Bool { signedInEmail != nil }

    // MARK: Profile

    /// `profiles.display_name` is NOT NULL and defaults to `''`, so "no name" is an
    /// empty string rather than a nil — the address stands in for it everywhere.
    @Published private(set) var displayName = ""
    @Published var displayNameDraft = ""
    @Published private(set) var joinedAt: Date?
    @Published private(set) var profileError: String?
    @Published private(set) var isSavingName = false

    /// What the sidebar, the avatar and the account card call this person.
    var accountLabel: String {
        displayName.isEmpty ? (signedInEmail ?? tr("サインインしていません", "Not signed in", "未登录")) : displayName
    }

    var avatarInitial: String {
        let source = displayName.isEmpty ? (signedInEmail ?? "") : displayName
        guard let first = source.first else { return "…" }
        return String(first).uppercased()
    }

    // MARK: Buttons

    @Published private(set) var prompts: [UserPrompt] = []
    @Published private(set) var promptsError: String?
    @Published private(set) var isLoadingPrompts = false
    /// The row currently open for editing. Only ever one — an inline editor per row
    /// would make the list unreadable at seven buttons.
    @Published var editingPromptId: UUID?
    @Published private(set) var isSavingButtons = false
    @Published private(set) var isReorderingButtons = false
    var confirmLeavingButtons: ((@escaping () -> Void) -> Void)?
    func leaveButtons(perform action: @escaping () -> Void) {
        if page == .buttons, let confirmLeavingButtons { confirmLeavingButtons(action) }
        else { action() }
    }
    private var promptAccountID: String?
    private var promptRevision: UInt64 = 0
    private var promptLoadID = UUID()

    /// Arrow clicks may arrive faster than Supabase round trips. Keep only the newest
    /// not-yet-written snapshot and drain it behind the active write, so responses can
    /// never land out of order and snap the visible list backwards.
    private var pendingPromptOrder: [UserPrompt]?
    private var promptOrderSaveTask: Task<Void, Never>?

    // MARK: History

    @Published private(set) var stats: RewriteStats = .empty
    @Published private(set) var history: [RewriteHistoryEntry] = []
    @Published private(set) var historyEnabled = true
    @Published var historySearch = ""

    var filteredHistory: [RewriteHistoryEntry] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history }
        return history.filter {
            $0.originalText.localizedCaseInsensitiveContains(query)
                || $0.rewrittenText.localizedCaseInsensitiveContains(query)
                || $0.label.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: Preferences

    @Published private(set) var isTrusted = AXPermission.isTrusted
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var replyModeEnabled = ClipboardWatcher.isEnabled
    /// Published so the window redraws when it changes. §15's first page is where most
    /// users answer this; the ⚙︎ row is the only entry point for everyone who finished
    /// onboarding before the page existed.
    @Published private(set) var language = AppLanguageState.current
    /// The menu bar cannot observe a published property — see `AppDelegate`.
    var onLanguageChanged: (() -> Void)?

    private let languageStore = AppLanguageStore()

    func setLanguage(_ next: AppLanguage) {
        guard next != language else { return }
        languageStore.save(next)
        languageChanged()
    }

    /// Also called from onboarding, which owns its own store instance.
    func languageChanged() {
        language = AppLanguageState.current
        // A super property is stored, not computed, so it keeps whatever it was
        // registered with until it is registered again (§7's same reason for
        // re-registering the surface after a sign-out).
        PostHogConfiguration.registerSurface()
        onLanguageChanged?()
    }

    // MARK: Updates

    /// Set only after Sparkle has selected a newer, compatible, signed appcast item.
    /// The main window deliberately knows only the display version; Sparkle remains
    /// the sole owner of update downloading, verification, skipping and installation.
    @Published private(set) var availableUpdateVersion: String?
    var onUpdateRequested: (() -> Void)?
    /// Raised whenever `availableUpdateVersion` changes, so `AppDelegate` can move the
    /// two surfaces it owns — the panel above the bar and the status-menu row — without
    /// the model knowing either exists.
    var onUpdateNoticeChanged: ((String?) -> Void)?

    private let updateStore = PendingUpdateStore()

    /// A find that outlived the app that made it. Called once at launch, before the bar
    /// is shown: an update discovered yesterday is still an update, and the next
    /// scheduled check is `SUScheduledCheckInterval` — a whole day — away, so a notice
    /// that died with the process would be invisible for most of its life.
    func restorePendingUpdate() {
        guard let version = updateStore.pending(for: appVersion) else {
            // `pending(for:)` clears a record the running build has caught up with, so
            // this is also the post-install cleanup.
            availableUpdateVersion = nil
            onUpdateNoticeChanged?(nil)
            return
        }
        availableUpdateVersion = version
        onUpdateNoticeChanged?(version)
    }

    /// Whether the panel above the bar should stand down for this version because the
    /// user already waved it away. The ホーム card and the status-menu row ignore it.
    func isUpdateNoticeDismissed(_ version: String) -> Bool {
        updateStore.isNoticeDismissed(version)
    }

    func offerUpdate(version: String) {
        let isNewFind = availableUpdateVersion != version
        updateStore.record(version)
        availableUpdateVersion = version
        onUpdateNoticeChanged?(version)
        guard isNewFind else { return }
        // The one event that can tell us this whole path works in the wild. Everything
        // about a background update is invisible from here otherwise: the check, the
        // find and the announcement all happen with nobody watching, which is how a
        // reminder that reached no surface at all shipped in 0.1.2.
        PostHogSDK.shared.capture("desktop_update_offered", properties: [
            "from_version": appVersion,
            "to_version": version
        ])
    }

    /// The user dismissed the panel above the bar. Persisted per version so a re-find on
    /// tomorrow's scheduled check does not put it straight back.
    func dismissUpdateNotice(for version: String) {
        updateStore.dismissNotice(for: version)
    }

    /// Sparkle's own window is now in front of the user, or its session ended. Either
    /// way this app has nothing left to announce **in this run** — but the record
    /// survives, because closing Sparkle's window without acting is not installing the
    /// update, and the next launch should say so again.
    func clearUpdateNotice() {
        availableUpdateVersion = nil
        onUpdateNoticeChanged?(nil)
    }

    func requestAvailableUpdate() {
        if let version = availableUpdateVersion {
            PostHogSDK.shared.capture("desktop_update_accepted", properties: [
                "from_version": appVersion,
                "to_version": version
            ])
        }
        onUpdateRequested?()
    }

    // MARK: Plan

    /// Nil until the first successful read. **Never persisted and never assumed**:
    /// `docs/billing.md` §3.4 makes entitlement a function of `now()`, so a cached
    /// value would keep reporting `pro` for up to 14 days after a grace window ran
    /// out. Re-read on every `refresh()`.
    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var entitlementError: String?
    @Published private(set) var isLoadingEntitlement = false
    /// Guards the two browser hand-offs so a double-click cannot open two tabs. The
    /// server's `checkout_intents` row (§3.3a) is the real defence; this is the
    /// cheap one that stops the user seeing two windows.
    @Published private(set) var isOpeningBilling = false

    let appVersion: String

    private let auth: AuthService
    private let promptStore: UserPromptRemoteStore
    private let profileStore: ProfileRemoteStore
    private let billingStore: BillingRemoteStore
    private let history_: RewriteHistoryStore
    /// Re-reads the hover row. Every button mutation ends here, so the overlay never
    /// disagrees with the list the user is looking at.
    private let onPromptsChanged: () async -> Void
    private var webAuthSession: ASWebAuthenticationSession?
    /// Avoids redundant identify calls during activation-driven refreshes. A fresh app
    /// launch has no value here, so a restored session is identified once per launch.
    private var identifiedUserId: String?

    init(
        auth: AuthService,
        promptStore: UserPromptRemoteStore,
        profileStore: ProfileRemoteStore,
        billingStore: BillingRemoteStore,
        history: RewriteHistoryStore,
        appVersion: String,
        onPromptsChanged: @escaping () async -> Void
    ) {
        self.auth = auth
        self.promptStore = promptStore
        self.profileStore = profileStore
        self.billingStore = billingStore
        self.history_ = history
        self.appVersion = appVersion
        self.onPromptsChanged = onPromptsChanged
        super.init()
        refresh()
    }

    // MARK: - Refresh

    /// §5: the Accessibility permission is tied to the binary's signature, so a
    /// rebuild silently revokes it. Re-checked on every activation, along with
    /// everything else that can change while the window is closed.
    func refresh() {
        #if DEBUG
        if AsideDesignPreview.isRunning { return }
        #endif
        applyTrusted(AXPermission.isTrusted)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Task {
            let session = await auth.currentSession
            signedInEmail = await auth.currentEmail
            if session?.userId != promptAccountID { await reloadPrompts() }
            await identifyIfNeeded(session)
            await reloadHistory()
            guard signedInEmail != nil else {
                entitlement = nil
                return
            }
            await loadProfile()
            await reloadEntitlement()
            if !isSavingButtons { await reloadPrompts() }
        }
    }

    // MARK: - Plan

    /// Re-read rather than cached, every time. See `entitlement`.
    func reloadEntitlement() async {
        #if DEBUG
        if AsideDesignPreview.isRunning { return }
        #endif
        guard signedInEmail != nil else {
            entitlement = nil
            return
        }
        isLoadingEntitlement = true
        defer { isLoadingEntitlement = false }
        do {
            entitlement = try await billingStore.fetchEntitlement()
            entitlementError = nil
        } catch {
            // Keep the last good value on screen. A transient network failure that
            // blanked the plan card would read as "you have been downgraded".
            entitlementError = tr("プランを読み込めませんでした。", "Couldn't load your plan.", "无法加载套餐信息。")
        }
    }

    /// ホーム's アップグレード button. It opens the プラン pane rather than jumping
    /// straight to Stripe: the monthly/annual choice is the decision being made, and
    /// `PlanView` is where the two prices sit side by side with the 特商法 §10 items
    /// (請求総額, 自動更新, 解約) around them.
    func openPlanSettings() {
        preferencesSection = .plan
        showsPreferences = true
    }

    /// The currency every plan surface quotes in.
    ///
    /// A live subscription's own currency wins over the interface language: a user
    /// who bought in yen and later switched the app to English is still charged yen,
    /// and quoting them dollars would misstate their own renewal. With nothing sold
    /// yet there is nothing to preserve, so the language decides.
    var billingCurrency: BillingCurrency {
        entitlement?.currency ?? .forInterface(AppLanguageState.current)
    }

    func beginCheckout(_ price: BillingRemoteStore.PriceKey) {
        let currency = billingCurrency
        PostHogSDK.shared.capture("desktop_checkout_started", properties: [
            "billing_interval": price == .yearly ? "yearly" : "monthly",
            "currency": currency.rawValue,
            // What the client *believes* — the server decides, and the two disagreeing
            // is the signal worth having. See `desktop-checkout`.
            "offer_expected": entitlement?.hasWelcomeOffer ?? false,
        ])
        let language = AppLanguageState.current
        openBilling {
            try await self.billingStore.checkoutURL(
                for: price,
                currency: currency,
                language: language
            )
        }
    }

    /// Opens the 72-hour welcome-offer window and folds the deadline into the
    /// entitlement already on screen, so ホーム and the plan pane can draw the
    /// countdown without waiting for the next full read.
    ///
    /// Failure is silent by design. This is called from the onboarding offer page,
    /// and a network error there must not block a user from finishing setup — the
    /// worst case is that the offer is not shown, which is the same outcome as being
    /// ineligible.
    @discardableResult
    func startWelcomeOffer() async -> Date? {
        guard signedInEmail != nil else { return nil }
        guard let expiry = try? await billingStore.startWelcomeOffer() else { return nil }
        if let current = entitlement {
            entitlement = Entitlement(
                plan: current.plan,
                status: current.status,
                interval: current.interval,
                currency: current.currency,
                used: current.used,
                monthLimit: current.monthLimit,
                resetsAt: current.resetsAt,
                cancelAtPeriodEnd: current.cancelAtPeriodEnd,
                cancelsAt: current.cancelsAt,
                currentPeriodEnd: current.currentPeriodEnd,
                pastDueSince: current.pastDueSince,
                welcomeOfferExpiresAt: expiry
            )
        }
        return expiry
    }

    /// Opens the Billing Portal, optionally on a specific screen.
    ///
    /// The default stays `.overview` so existing call sites are unchanged, and it is
    /// also the right destination for un-cancelling — the overview is where Stripe
    /// puts the renew button.
    func openBillingPortal(_ flow: BillingRemoteStore.PortalFlow = .overview) {
        openBilling { try await self.billingStore.portalURL(flow: flow) }
    }

    /// Both hand-offs go to the default browser rather than an in-app web view:
    /// Stripe Checkout wants Apple Pay, and Apple Pay needs Safari's payment sheet.
    /// §8 calls that the highest-impact single item in the funnel.
    private func openBilling(_ resolve: @escaping () async throws -> URL) {
        guard !isOpeningBilling else { return }
        isOpeningBilling = true
        Task {
            defer { isOpeningBilling = false }
            do {
                NSWorkspace.shared.open(try await resolve())
                entitlementError = nil
            } catch RewriteError.backend(let message) {
                entitlementError = message
            } catch RewriteError.notSignedIn {
                entitlementError = tr("サインインしてください。", "Please sign in.", "请先登录。")
            } catch {
                entitlementError = tr("接続できませんでした。", "Couldn't connect.", "无法连接。")
            }
            // The browser round trip finishes out of band, so the webhook may land
            // before or after the user comes back. Re-reading on the next activation
            // is what `refresh()` already does; this covers the same-window case.
            await reloadEntitlement()
        }
    }

    // MARK: - Profile

    private func loadProfile() async {
        do {
            // Nil means the row does not exist yet — a user created on this Mac has
            // not been through the phone's onboarding. Saving a name upserts it.
            let profile = try await profileStore.fetch()
            displayName = profile?.displayName ?? ""
            joinedAt = profile?.createdAt
            profileError = nil
        } catch {
            profileError = nil
        }
        displayNameDraft = displayName
    }

    var canSaveDisplayName: Bool {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isSavingName && trimmed != displayName
    }

    /// Whether first run has a name to continue on. The **draft**, not `displayName`:
    /// the field saves on Continue anyway, so gating on the stored value would refuse
    /// a name the user has typed and not yet pressed Save on.
    ///
    /// Only first run consults this. The account page can still clear the field —
    /// `handle_new_user()` writes `''` for every signup and `profiles.display_name` is
    /// NOT NULL with that default, so an empty name stays a legal state of the row and
    /// making it illegal would mean a migration in the iOS repo.
    var hasDisplayNameDraft: Bool {
        !displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveDisplayName() {
        Task { _ = await saveDisplayNameForContinuation() }
    }

    /// Saves the current draft and reports whether it is safe for onboarding to
    /// continue. A blank first-run name is optional; an entered one is never silently
    /// left only in the text field when the user presses Continue.
    @discardableResult
    func saveDisplayNameForContinuation() async -> Bool {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != displayName else { return true }
        guard !isSavingName else { return false }
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await profileStore.setDisplayName(trimmed)
            displayName = trimmed
            profileError = nil
            return true
        } catch {
            profileError = tr("名前を保存できませんでした。", "Couldn't save your name.", "无法保存名称。")
            return false
        }
    }

    private func reloadHistory() async {
        historyEnabled = await history_.isEnabled
        history = await history_.entries()
        stats = await history_.stats()
    }

    /// Establishes the authenticated Supabase user as the SDK identity exactly once.
    /// The UUID is stable; the email remains a person property rather than event data.
    private func identifyIfNeeded(_ session: AuthSession?) async {
        guard let session, !session.userId.isEmpty, session.userId != identifiedUserId else {
            return
        }

        let email = await auth.currentEmail
        var userProperties: [String: Any] = [:]
        if let email { userProperties["email"] = email }
        PostHogSDK.shared.identify(session.userId, userProperties: userProperties)
        identifiedUserId = session.userId
    }

    /// `desktop_signed_up` / `desktop_signed_in` — the gap `docs/analytics.md` §3 listed
    /// as "a brand-new desktop user and an existing iOS user installing the Mac app are
    /// indistinguishable client-side". They are the desktop's own names for the events
    /// 465060 has had since June; the `desktop_` prefix is what keeps the two series
    /// separable if a token is ever mistyped.
    ///
    /// **Only an authentication the user just performed reaches here.** `refresh()`
    /// restores a Keychain session on every activation and deliberately does not call
    /// this: counting that would turn a signup series into a launch count.
    private func captureAuth(signedUp: Bool, method: String, extra: [String: Any] = [:]) {
        var properties: [String: Any] = ["method": method]
        properties.merge(extra) { _, new in new }
        PostHogSDK.shared.capture(
            signedUp ? "desktop_signed_up" : "desktop_signed_in",
            properties: properties
        )
    }

    // MARK: - Account

    func signIn() {
        submitAuth(.signIn) { [auth, email, password] in
            _ = try await auth.signIn(email: email, password: password)
            return nil
        }
    }

    func signUp() {
        guard password == passwordConfirm else {
            authError = tr("パスワードが一致しません。", "The passwords don't match.", "两次输入的密码不一致。")
            return
        }
        submitAuth(.signUp) { [auth, email, password] in
            switch try await auth.signUp(email: email, password: password) {
            case .signedIn:
                return nil
            case .confirmationRequired:
                // The account exists but nothing is signed in until the link is
                // clicked. Saying "signed up" and showing a signed-out window would
                // read as a failure.
                return tr("確認メールを送信しました。メール内のリンクを開いてからサインインしてください。", "We sent a confirmation email. Open the link in it, then sign in.", "确认邮件已发送。请打开邮件中的链接后再登录。")
            }
        }
    }

    /// Google through `ASWebAuthenticationSession` (§6). The callback scheme is the
    /// same `keigobutton://` the app registers, so `AppDelegate`'s URL handler is the
    /// fallback if the sheet is dismissed after the redirect has already fired.
    func signInWithGoogle() {
        authError = nil
        authNotice = nil
        isAuthenticating = true

        Task {
            let url = await auth.authorizeURL(provider: "google")
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "keigobutton"
            ) { [weak self] callback, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isAuthenticating = false
                    guard let callback else {
                        // Cancelling is a decision, not a failure — no error badge.
                        if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                            self.authError = tr("サインインできませんでした。", "Couldn't sign in.", "无法登录。")
                        }
                        return
                    }
                    await self.completeOAuth(url: callback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webAuthSession = session
            session.start()
        }
    }

    /// Also reached from `AppDelegate` when the redirect arrives as a plain URL open.
    func completeOAuth(url: URL) async {
        do {
            let session = try await auth.completeOAuthCallback(url: url)
            signedInEmail = await auth.currentEmail
            await identifyIfNeeded(session)
            await loadProfile()
            // Google is the only path where the client cannot be told which of the two
            // happened: Supabase answers a first authorization and a returning one with
            // the same session shape. `profiles.created_at` is the discriminator —
            // `handle_new_user()` writes that row inside the signup transaction, so a
            // returning user's is hours or months old whatever surface they made it on.
            // The window is deliberately wide: it absorbs clock skew between this Mac
            // and Postgres, and the only thing it can misread is an account created on
            // the phone within the last ten minutes.
            captureAuth(
                signedUp: joinedAt.map { Date().timeIntervalSince($0) < 600 } ?? false,
                method: "google"
            )
            await reloadPrompts()
            await onPromptsChanged()
            page = .home
        } catch {
            authError = tr("サインインできませんでした。", "Couldn't sign in.", "无法登录。")
        }
    }

    private enum AuthAttempt {
        case signIn
        case signUp
    }

    private func submitAuth(_ attempt: AuthAttempt, _ work: @escaping () async throws -> String?) {
        authError = nil
        authNotice = nil
        isAuthenticating = true

        Task {
            defer { isAuthenticating = false }
            do {
                let notice = try await work()
                password = ""
                passwordConfirm = ""
                authNotice = notice
                let session = await auth.currentSession
                signedInEmail = await auth.currentEmail
                await identifyIfNeeded(session)
                switch attempt {
                case .signUp:
                    // Both endings of `SignUpOutcome` are a signup. The confirmation
                    // branch has no session yet, so this one rides the anonymous
                    // distinct_id and follows the person through the later `identify`.
                    captureAuth(
                        signedUp: true,
                        method: "password",
                        extra: ["confirmation_required": notice != nil]
                    )
                case .signIn:
                    if session != nil { captureAuth(signedUp: false, method: "password") }
                }
                guard signedInEmail != nil else { return }
                await loadProfile()
                await reloadPrompts()
                await onPromptsChanged()
                page = .home
            } catch {
                authError = Self.message(for: error)
            }
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case AuthError.invalidCredentials:
            return tr("メールアドレスまたはパスワードが正しくありません。", "That email address or password is incorrect.", "邮箱地址或密码不正确。")
        case AuthError.emailAlreadyRegistered:
            return tr("このメールアドレスは登録済みです。サインインしてください。", "That email address already has an account. Sign in instead.", "该邮箱已注册，请直接登录。")
        case AuthError.weakPassword:
            return tr("パスワードは6文字以上にしてください。", "Passwords need at least 6 characters.", "密码需要至少6个字符。")
        default:
            return tr("接続できませんでした。時間をおいてお試しください。", "Couldn't connect. Try again in a moment.", "无法连接。请稍后重试。")
        }
    }

    func signOut() {
        promptRevision &+= 1
        promptAccountID = nil
        prompts = []
        pendingPromptOrder = nil
        Task {
            await auth.signOut()
            PostHogSDK.shared.reset()
            // `reset` clears super properties along with the identity, so the surface
            // has to go back on or every post-sign-out event loses it.
            PostHogConfiguration.registerSurface()
            identifiedUserId = nil
            signedInEmail = nil
            email = ""
            password = ""
            passwordConfirm = ""
            displayName = ""
            displayNameDraft = ""
            joinedAt = nil
            prompts = []
            await onPromptsChanged()
        }
    }

    // MARK: - Buttons

    func reloadPrompts() async {
        #if DEBUG
        if AsideDesignPreview.isRunning { return }
        #endif
        let account = await auth.currentSession?.userId
        if promptAccountID != account {
            promptRevision &+= 1
            promptAccountID = account
            prompts = []
            editingPromptId = nil
            pendingPromptOrder = nil
        }
        guard let account else { isLoadingPrompts = false; return }
        let loadID = UUID()
        promptLoadID = loadID
        isLoadingPrompts = true
        do {
            let loaded = try await promptStore.scoped(to: account).fetch()
            guard await auth.currentSession?.userId == account,
                  promptAccountID == account, promptLoadID == loadID else { return }
            if pendingPromptOrder == nil && promptOrderSaveTask == nil {
                prompts = UserPromptOrder.sortedForEditing(loaded)
            }
            promptsError = nil
        } catch {
            guard promptAccountID == account, promptLoadID == loadID else { return }
            promptsError = tr("ボタンを読み込めませんでした。", "Couldn't load your buttons.", "无法加载按钮。")
        }
        if promptLoadID == loadID { isLoadingPrompts = false }
    }

    /// Whether the buttons on this account write a language the app is not writing.
    ///
    /// Computed rather than stored: `prompts` and `language` are both `@Published`, so a
    /// swap or a language change re-evaluates it without a second thing to keep in sync
    /// — which is the exact failure this whole surface exists to correct.
    var buttonsWriteOtherLanguage: Bool {
        isSignedIn && StockButtonLanguage.writesOtherLanguage(prompts, whenWriting: language)
    }

    /// Replaces the stock buttons with one preset pack in the current writing language,
    /// keeping everything the user made themselves (`StockButtonLanguage.replacement`).
    ///
    /// Routed through `applyOnboardingButtons` deliberately — that is already the one
    /// path that reconciles `builtin_key` identities before upserting (§6,
    /// `UserPromptIdentity`), and a second whole-set writer would be a second place for
    /// the 409 that note describes to come back.
    func applyPresetPack(_ pack: OnboardingPresetPack) {
        let drafts = StockButtonLanguage.replacement(
            choosing: pack,
            keeping: prompts,
            whenWriting: language
        )
        mutate { _ in
            try await self.applyOnboardingButtons(drafts)
            PostHogSDK.shared.capture("desktop_button_language_realigned", properties: [
                "pack": pack.rawValue,
                "writing_language": self.language.writingLanguageCode,
                "buttons": drafts.count,
            ])
            PostHogSDK.shared.capture("desktop_preset_selected", properties: [
                "pack": pack.rawValue,
                "source": "language_realign",
                "writing_language": self.language.writingLanguageCode,
                "button_count": drafts.count,
                "customized": false,
            ])
        }
    }

    func applyOnboardingButtons(_ drafts: [OnboardingButtonDraft]) async throws {
        guard let account = await auth.currentSession?.userId else { throw RewriteError.notSignedIn }
        let store = promptStore.scoped(to: account)
        let replacements = drafts.enumerated().map { $0.element.userPrompt(at: $0.offset) }
        let loaded = try await store.replaceAll(with: replacements)
        guard await auth.currentSession?.userId == account else { throw RewriteError.notSignedIn }
        prompts = UserPromptOrder.sortedForEditing(loaded)
        promptsError = nil
        await onPromptsChanged()
    }

    func saveButton(_ existing: UserPrompt?, title: String, instruction: String) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !instruction.isEmpty, !isSavingButtons,
              promptOrderSaveTask == nil, let account = promptAccountID else { return false }
        guard await auth.currentSession?.userId == account, !isSavingButtons, promptOrderSaveTask == nil else { return false }
        isSavingButtons = true
        defer { isSavingButtons = false }
        let store = promptStore.scoped(to: account)
        do {
            let saved: UserPrompt
            if let existing {
                guard var prompt = prompts.first(where: { $0.id == existing.id }) else { return false }
                prompt.title = title
                prompt.prompt = instruction
                try await store.update(prompt)
                saved = prompt
            } else {
                saved = try await store.create(title: title, prompt: instruction,
                    slot: prompts.isEmpty ? .main : .sub, sortOrder: (prompts.map(\.sortOrder).max() ?? -1) + 1)
            }
            guard await auth.currentSession?.userId == account else { return false }
            if let index = prompts.firstIndex(where: { $0.id == saved.id }) { prompts[index] = saved }
            else { prompts.append(saved) }
            editingPromptId = saved.id
            PostHogSDK.shared.capture(existing == nil ? "desktop_prompt_created" : "desktop_prompt_updated",
                properties: ["slot": saved.slot.rawValue, "origin": saved.origin.rawValue, "is_enabled": saved.isEnabled])
            await reloadPrompts()
            await onPromptsChanged()
            return true
        } catch {
            guard await auth.currentSession?.userId == account else { return false }
            promptsError = tr("保存できませんでした。もう一度お試しください。", "Couldn't save. Your edits are still here; try again.", "无法保存。编辑内容已保留，请重试。")
            return false
        }
    }

    func setEnabled(_ prompt: UserPrompt, _ isEnabled: Bool) {
        guard !isSavingButtons, promptOrderSaveTask == nil else { return }
        var next = prompt
        next.isEnabled = isEnabled
        mutate { store in try await store.update(next) }
    }

    func delete(_ prompt: UserPrompt) {
        guard !isSavingButtons, promptOrderSaveTask == nil else { return }
        let remaining = UserPromptOrder.normalized(prompts.filter { $0.id != prompt.id })
        mutate { store in
            try await store.delete(id: prompt.id)
            for row in remaining.filter({ $0.slot == .sub }) + remaining.filter({ $0.slot == .main }) {
                try await store.update(row)
            }
            PostHogSDK.shared.capture("desktop_prompt_deleted", properties: ["slot": prompt.slot.rawValue, "origin": prompt.origin.rawValue])
        }
    }

    @discardableResult
    func movePrompt(id: UUID, by offset: Int) -> Bool {
        guard !isSavingButtons, let next = UserPromptOrder.moving(prompts, id: id, by: offset) else { return false }
        prompts = next
        commitOrder()
        return true
    }

    func movePrompt(id: UUID, before destination: UUID) {
        guard !isSavingButtons, let next = UserPromptOrder.moving(prompts, id: id, before: destination) else { return }
        prompts = next
        commitOrder()
    }

    func commitOrder() {
        pendingPromptOrder = prompts
        guard promptOrderSaveTask == nil else { return }
        guard let account = promptAccountID else { pendingPromptOrder = nil; return }
        let revision = promptRevision
        isReorderingButtons = true
        promptOrderSaveTask = Task {
            defer { isReorderingButtons = false }
            guard await auth.currentSession?.userId == account else { pendingPromptOrder = nil; promptOrderSaveTask = nil; return }
            let store = promptStore.scoped(to: account)
            var failed = false
            while revision == promptRevision, let ordered = pendingPromptOrder {
                pendingPromptOrder = nil
                do {
                    for prompt in ordered.filter({ $0.slot == .sub }) + ordered.filter({ $0.slot == .main }) {
                        try await store.update(prompt)
                    }
                } catch { failed = true; pendingPromptOrder = nil; break }
            }
            promptOrderSaveTask = nil
            guard revision == promptRevision, await auth.currentSession?.userId == account else { return }
            await reloadPrompts()
            if failed { promptsError = tr("並べ替えを保存できませんでした。再度お試しください。", "Couldn't save the order. Please try again.", "无法保存排序，请重试。") }
            await onPromptsChanged()
        }
    }

    private func mutate(_ work: @escaping (UserPromptRemoteStore) async throws -> Void) {
        guard !isSavingButtons, promptOrderSaveTask == nil, let account = promptAccountID else { return }
        isSavingButtons = true
        Task {
            defer { isSavingButtons = false }
            guard await auth.currentSession?.userId == account else { return }
            var failed = false
            do { try await work(promptStore.scoped(to: account)) }
            catch { failed = true }
            guard await auth.currentSession?.userId == account else { return }
            await reloadPrompts()
            if failed { promptsError = tr("保存できませんでした。", "Couldn't save. Please try again.", "无法保存，请重试。") }
            await onPromptsChanged()
        }
    }

    // MARK: - History

    func setHistoryEnabled(_ enabled: Bool) {
        historyEnabled = enabled
        Task {
            await history_.setEnabled(enabled)
            await reloadHistory()
        }
    }

    func clearHistory() {
        Task {
            await history_.clear()
            await reloadHistory()
        }
    }

    func copy(_ entry: RewriteHistoryEntry) {
        // Suppressed like the overlay's own writes (§16). Unbracketed, copying a row
        // out of the history list would arm reply mode with a rewrite this app
        // produced and offer to compose a reply to it.
        ClipboardWatcher.writingOurselves {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.rewrittenText, forType: .string)
        }
    }

    // MARK: - Preferences

    /// Where the user was standing when they were asked. `docs/analytics.md` §4's
    /// activation funnel used to step from install straight to onboarding completion,
    /// so a user who gave up on the permission page and one who never reached it were
    /// indistinguishable; `source` is what separates them.
    enum AccessibilityPromptSource: String {
        /// §15's permission page — the gate almost everyone meets first.
        case onboarding
        /// The ⚙︎ sheet's Accessibility row, i.e. someone repairing a revoked grant.
        case preferences
        /// The home card, which only appears once the permission is already missing.
        case home
    }

    /// Which of the two buttons on the permission page they pressed. Both are a prompt;
    /// only one of them can be answered without leaving the app, and the ratio is the
    /// read on whether 「システム設定を開く」 is doing any work.
    enum AccessibilityPromptMethod: String {
        /// `AXIsProcessTrustedWithOptions` — the system's own dialog.
        case systemPrompt = "system_prompt"
        /// `x-apple.systempreferences:` — we opened System Settings for them.
        case settingsLink = "settings_link"
    }

    func requestAccessibility(source: AccessibilityPromptSource) {
        recordAccessibilityPrompt(source: source, method: .systemPrompt)
        AXPermission.requestTrust()
        // The system dialog has no completion callback, so the card is polled rather
        // than left stale until the next activation.
        Task {
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if AXPermission.isTrusted {
                    applyTrusted(true)
                    return
                }
            }
        }
    }

    /// Captured for the 「システム設定を開く」 leg too, which asks just as much as the
    /// system dialog does but leaves no trace anywhere else.
    func recordAccessibilityPrompt(
        source: AccessibilityPromptSource,
        method: AccessibilityPromptMethod
    ) {
        let defaults = UserDefaults.standard
        defaults.set(source.rawValue, forKey: Self.promptSourceKey)
        defaults.set(Date().timeIntervalSince1970, forKey: Self.promptedAtKey)
        PostHogSDK.shared.capture("desktop_accessibility_prompted", properties: [
            "source": source.rawValue,
            "method": method.rawValue,
        ])
    }

    /// The single writer of `isTrusted`, so the grant cannot be observed without being
    /// reported and the super property cannot go stale.
    ///
    /// Fires `desktop_accessibility_granted` the first time the app ever sees the
    /// permission, and **once only** — the flag is persisted, because `refresh()` runs on
    /// every window activation and this would otherwise be a launch count. A revocation
    /// (every unsigned dev rebuild, per `AXPermission`) does not re-arm it: what the
    /// funnel needs is the first crossing, and a second event on the same person would
    /// make the tile a rebuild counter.
    private func applyTrusted(_ trusted: Bool) {
        let changed = isTrusted != trusted
        isTrusted = trusted
        // Stored, not computed. Without this the property keeps whatever it held at
        // launch and every event after a grant still says the user has no permission.
        if changed { PostHogConfiguration.registerSurface() }

        let defaults = UserDefaults.standard
        guard trusted, !defaults.bool(forKey: Self.grantReportedKey) else { return }
        defaults.set(true, forKey: Self.grantReportedKey)

        // `outside_app` is the honest answer when nobody pressed anything — a user who
        // granted it from System Settings on their own, or on a launch that inherited a
        // grant made before this build shipped. Keeping it as a value rather than
        // omitting the property is what stops it reading as a missing measurement.
        let source = defaults.string(forKey: Self.promptSourceKey) ?? "outside_app"
        var properties: [String: Any] = ["source": source]
        if let promptedAt = defaults.object(forKey: Self.promptedAtKey) as? Double {
            properties["seconds_since_prompt"] = Int(
                max(0, Date().timeIntervalSince1970 - promptedAt)
            )
        }
        PostHogSDK.shared.capture("desktop_accessibility_granted", properties: properties)
    }

    private static let grantReportedKey = "analytics.accessibilityGrantReported"
    private static let promptSourceKey = "analytics.accessibilityPromptSource"
    private static let promptedAtKey = "analytics.accessibilityPromptedAt"

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail while the app runs from a location the service
            // manager will not accept (a DerivedData build). Fall through to the real
            // status rather than reporting a toggle that did not take.
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func resetPosition() {
        OverlayPlacement.resetPosition()
    }

    /// §16. Read straight off `ClipboardWatcher` rather than mirrored here: the watcher
    /// consults the same value on every poll, so there is nothing to keep in sync and
    /// no wiring between this model and the overlay it does not own.
    func setReplyModeEnabled(_ enabled: Bool) {
        ClipboardWatcher.isEnabled = enabled
        replyModeEnabled = enabled
    }

    // MARK: - App names

    private static var appNameCache: [String: String] = [:]

    /// `com.apple.mail` → `Mail`. The stat caption is about where the user works, and
    /// a reverse-DNS id is not a place anyone recognises.
    static func appName(for bundleId: String) -> String {
        if let cached = appNameCache[bundleId] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        let name = url.map { FileManager.default.displayName(atPath: $0.path) }
            // An app that has since been uninstalled leaves only its id; the last
            // component is closer to its name than the whole string.
            ?? bundleId.split(separator: ".").last.map(String.init)
            ?? bundleId
        appNameCache[bundleId] = name
        return name
    }
}

extension MainModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
        }
    }
}

#if DEBUG
extension MainModel {
    /// Inert design fixtures; never restore a session, load files, or call a service.
    func configureDesignPreview(signedIn: Bool = true, state: String = "ready") {
        language = AppLanguageState.current
        signedInEmail = signedIn ? "alex@example.com" : nil
        displayName = signedIn ? "Alex" : ""
        displayNameDraft = displayName
        isTrusted = state != "permission"
        authMode = state == "signup" ? .signUp : .signIn
        isAuthenticating = state == "loading"
        authError = state == "error" ? tr("接続できませんでした。ネットワークを確認して、もう一度お試しください。", "We couldn’t connect. Check your connection and try again. Your information has not been lost.", "无法连接。请检查网络连接，然后重试。你的信息没有丢失。") : nil
        profileError = state == "error" ? authError : nil
        email = state == "signup" ? "alex@example.com" : ""
        prompts = OnboardingPresetPack.starter.drafts().enumerated().map { $0.element.userPrompt(at: $0.offset) }
        history = []
    }
}
#endif
