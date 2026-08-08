import AppKit
import AuthenticationServices
import DesktopRewriteKit
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

    let appVersion: String

    private let auth: AuthService
    private let promptStore: UserPromptRemoteStore
    private let profileStore: ProfileRemoteStore
    private let history_: RewriteHistoryStore
    /// Re-reads the hover row. Every button mutation ends here, so the overlay never
    /// disagrees with the list the user is looking at.
    private let onPromptsChanged: () async -> Void
    private var webAuthSession: ASWebAuthenticationSession?

    init(
        auth: AuthService,
        promptStore: UserPromptRemoteStore,
        profileStore: ProfileRemoteStore,
        history: RewriteHistoryStore,
        appVersion: String,
        onPromptsChanged: @escaping () async -> Void
    ) {
        self.auth = auth
        self.promptStore = promptStore
        self.profileStore = profileStore
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
            signedInEmail = await auth.currentEmail
            await reloadHistory()
            guard signedInEmail != nil else { return }
            await loadProfile()
            if prompts.isEmpty { await reloadPrompts() }
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
            _ = try await auth.completeOAuthCallback(url: url)
            signedInEmail = await auth.currentEmail
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
                signedInEmail = await auth.currentEmail
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
            prompts = try await promptStore.fetch().sortedForEditing
            promptsError = nil
        } catch {
            promptsError = "ボタンを読み込めませんでした。"
        }
    }

    func addPrompt() {
        mutate {
            let created = try await self.promptStore.create(
                title: "新しいボタン",
                prompt: "",
                sortOrder: (self.prompts.map(\.sortOrder).max() ?? 0) + 1
            )
            self.editingPromptId = created.id
        }
    }

    func save(_ prompt: UserPrompt) {
        // Applied locally first: the list is the thing the user is looking at, and a
        // round trip's worth of stale text in the row reads as a dropped edit.
        applyLocally(prompt)
        mutate { try await self.promptStore.update(prompt) }
    }

    func setEnabled(_ prompt: UserPrompt, _ isEnabled: Bool) {
        var next = prompt
        next.isEnabled = isEnabled
        save(next)
    }

    /// Builtins can be disabled and reworded but not removed — the phone re-seeds
    /// them from `builtin_key`, so a delete here would come back on the next sync and
    /// look like the button ignored you.
    func canDelete(_ prompt: UserPrompt) -> Bool {
        prompt.builtinKey == nil
    }

    func delete(_ prompt: UserPrompt) {
        guard canDelete(prompt) else { return }
        prompts.removeAll { $0.id == prompt.id }
        editingPromptId = nil
        mutate { try await self.promptStore.delete(id: prompt.id) }
    }

    // MARK: - Reordering
    //
    // Split in two because the grip is dragged, not clicked. `moveLocally` runs many
    // times per gesture and touches only the array; `commitOrder` runs once, on
    // release, and is the only thing that talks to the server. A PATCH per frame would
    // be both slow and a way to leave the table half-reordered if the drag is
    // interrupted.

    /// Moves within a slot only.
    ///
    /// `main` is the phone's single primary toolbar button; dragging a `sub` past it
    /// would either create a second `main` or silently reorder nothing, since the
    /// hover row always renders `main` first (`enabledForHoverRow`).
    func canMove(_ prompt: UserPrompt, by offset: Int) -> Bool {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return false }
        let target = index + offset
        guard prompts.indices.contains(target) else { return false }
        return prompts[target].slot == prompt.slot
    }

    /// - Returns: whether the swap happened, which is what tells the drag gesture
    ///   whether to absorb a row's worth of travel or let the row rubber-band.
    @discardableResult
    func moveLocally(_ prompt: UserPrompt, by offset: Int) -> Bool {
        guard canMove(prompt, by: offset),
              let index = prompts.firstIndex(where: { $0.id == prompt.id })
        else { return false }
        prompts.swapAt(index, index + offset)
        return true
    }

    /// Renumbers each slot from the array's current order and pushes only the rows
    /// that actually changed.
    ///
    /// Renumbering a whole slot rather than swapping two values is deliberate: rows
    /// written before `sort_order` mattered all share a `0`, and swapping two zeroes
    /// is a no-op that the list would happily animate.
    func commitOrder() {
        var changed: [UserPrompt] = []
        for slot in [UserPrompt.Slot.main, .sub] {
            var order = 0
            for i in prompts.indices where prompts[i].slot == slot {
                if prompts[i].sortOrder != order {
                    prompts[i].sortOrder = order
                    changed.append(prompts[i])
                }
                order += 1
            }
        }
        guard !changed.isEmpty else { return }

        mutate {
            for prompt in changed {
                try await self.promptStore.update(prompt)
            }
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

private extension Array where Element == UserPrompt {
    /// The ボタン list's order, which has to match the hover row's: `main` first, then
    /// `sub`, each by `sortOrder`. Unlike `enabledForHoverRow` this keeps the disabled
    /// ones — the whole point of the page is turning them back on.
    var sortedForEditing: [UserPrompt] {
        let main = filter { $0.slot == .main }.sorted { $0.sortOrder < $1.sortOrder }
        let sub = filter { $0.slot == .sub }.sorted { $0.sortOrder < $1.sortOrder }
        return main + sub
    }
}
