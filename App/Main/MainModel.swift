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
        displayName.isEmpty ? (signedInEmail ?? "サインインしていません") : displayName
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
        isTrusted = AXPermission.isTrusted
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Task {
            let session = await auth.currentSession
            signedInEmail = await auth.currentEmail
            await identifyIfNeeded(session)
            await reloadHistory()
            guard signedInEmail != nil else {
                entitlement = nil
                return
            }
            await loadProfile()
            await reloadEntitlement()
            if prompts.isEmpty { await reloadPrompts() }
        }
    }

    // MARK: - Plan

    /// Re-read rather than cached, every time. See `entitlement`.
    func reloadEntitlement() async {
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
            entitlementError = "プランを読み込めませんでした。"
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

    func beginCheckout(_ price: BillingRemoteStore.PriceKey) {
        PostHogSDK.shared.capture("desktop_checkout_started", properties: [
            "billing_interval": price == .yearly ? "yearly" : "monthly",
        ])
        openBilling { try await self.billingStore.checkoutURL(for: price) }
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
                entitlementError = "サインインしてください。"
            } catch {
                entitlementError = "接続できませんでした。"
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

    func saveDisplayName() {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != displayName else { return }
        isSavingName = true

        Task {
            defer { isSavingName = false }
            do {
                try await profileStore.setDisplayName(trimmed)
                displayName = trimmed
                profileError = nil
            } catch {
                profileError = "名前を保存できませんでした。"
            }
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

    // MARK: - Account

    func signIn() {
        submitAuth { [auth, email, password] in
            _ = try await auth.signIn(email: email, password: password)
            return nil
        }
    }

    func signUp() {
        guard password == passwordConfirm else {
            authError = "パスワードが一致しません。"
            return
        }
        submitAuth { [auth, email, password] in
            switch try await auth.signUp(email: email, password: password) {
            case .signedIn:
                return nil
            case .confirmationRequired:
                // The account exists but nothing is signed in until the link is
                // clicked. Saying "signed up" and showing a signed-out window would
                // read as a failure.
                return "確認メールを送信しました。メール内のリンクを開いてからサインインしてください。"
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
                            self.authError = "サインインできませんでした。"
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
            await reloadPrompts()
            await onPromptsChanged()
            page = .home
        } catch {
            authError = "サインインできませんでした。"
        }
    }

    private func submitAuth(_ work: @escaping () async throws -> String?) {
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
            return "メールアドレスまたはパスワードが正しくありません。"
        case AuthError.emailAlreadyRegistered:
            return "このメールアドレスは登録済みです。サインインしてください。"
        case AuthError.weakPassword:
            return "パスワードは6文字以上にしてください。"
        default:
            return "接続できませんでした。時間をおいてお試しください。"
        }
    }

    func signOut() {
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
        isLoadingPrompts = true
        defer { isLoadingPrompts = false }
        do {
            prompts = UserPromptOrder.sortedForEditing(try await promptStore.fetch())
            promptsError = nil
        } catch {
            promptsError = "ボタンを読み込めませんでした。"
        }
    }

    func applyOnboardingButtons(_ drafts: [OnboardingButtonDraft]) async throws {
        let replacements = drafts.enumerated().map { index, draft in
            draft.userPrompt(at: index)
        }
        prompts = UserPromptOrder.sortedForEditing(
            try await promptStore.replaceAll(with: replacements)
        )
        promptsError = nil
        await onPromptsChanged()
    }

    func addPrompt() {
        let slot: UserPrompt.Slot = prompts.isEmpty ? .main : .sub
        mutate {
            let created = try await self.promptStore.create(
                title: "新しいボタン",
                prompt: "",
                slot: slot,
                sortOrder: (self.prompts.map(\.sortOrder).max() ?? 0) + 1
            )
            PostHogSDK.shared.capture("desktop_prompt_created", properties: [
                "slot": slot.rawValue,
            ])
            self.editingPromptId = created.id
        }
    }

    func save(_ prompt: UserPrompt) {
        // Applied locally first: the list is the thing the user is looking at, and a
        // round trip's worth of stale text in the row reads as a dropped edit.
        applyLocally(prompt)
        mutate {
            try await self.promptStore.update(prompt)
            PostHogSDK.shared.capture("desktop_prompt_updated", properties: [
                "slot": prompt.slot.rawValue,
                "is_enabled": prompt.isEnabled,
                "origin": prompt.origin.rawValue,
            ])
        }
    }

    func setEnabled(_ prompt: UserPrompt, _ isEnabled: Bool) {
        var next = prompt
        next.isEnabled = isEnabled
        save(next)
    }

    func delete(_ prompt: UserPrompt) {
        prompts.removeAll { $0.id == prompt.id }
        prompts = UserPromptOrder.normalized(prompts)
        editingPromptId = nil
        let remaining = prompts
        mutate {
            try await self.promptStore.delete(id: prompt.id)
            try await self.persistPromptOrder(remaining)
            PostHogSDK.shared.capture("desktop_prompt_deleted", properties: [
                "slot": prompt.slot.rawValue,
                "origin": prompt.origin.rawValue,
            ])
        }
    }

    // MARK: - Reordering

    /// Moves one row by one position. Position zero becomes `main`; every other row
    /// becomes `sub`, so moving a secondary button above the first row replaces the
    /// iPhone's primary toolbar button without a separate "set as main" state.
    @discardableResult
    func movePrompt(id: UUID, by offset: Int) -> Bool {
        guard let next = UserPromptOrder.moving(
            prompts,
            id: id,
            by: offset
        ) else { return false }
        prompts = next
        editingPromptId = nil
        commitOrder()
        return true
    }

    /// Serializes order snapshots. Repeated clicks while a write is active coalesce to
    /// the newest complete order; secondary rows are always written before the main so
    /// a partial network failure cannot leave two main rows.
    func commitOrder() {
        pendingPromptOrder = prompts
        guard promptOrderSaveTask == nil else { return }

        promptOrderSaveTask = Task { [weak self] in
            guard let self else { return }
            while let ordered = self.pendingPromptOrder {
                self.pendingPromptOrder = nil
                do {
                    try await self.persistPromptOrder(ordered)
                    self.promptsError = nil
                } catch {
                    self.promptsError = "保存できませんでした。"
                }
            }
            self.promptOrderSaveTask = nil
            await self.reloadPrompts()
            await self.onPromptsChanged()
        }
    }

    private func persistPromptOrder(_ prompts: [UserPrompt]) async throws {
        let secondary = prompts.filter { $0.slot == .sub }
        let main = prompts.filter { $0.slot == .main }
        for prompt in secondary + main {
            try await promptStore.update(prompt)
        }
    }

    private func applyLocally(_ prompt: UserPrompt) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        prompts[index] = prompt
    }

    /// Every button mutation ends the same way: reload from the server so a rejected
    /// write cannot linger in the list, then re-push the hover row.
    private func mutate(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                promptsError = nil
            } catch {
                promptsError = "保存できませんでした。"
            }
            await reloadPrompts()
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

    func requestAccessibility() {
        AXPermission.requestTrust()
        // The system dialog has no completion callback, so the card is polled rather
        // than left stale until the next activation.
        Task {
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if AXPermission.isTrusted {
                    isTrusted = true
                    return
                }
            }
        }
    }

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
