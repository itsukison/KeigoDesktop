import AppKit
import DesktopRewriteKit
import SwiftUI

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var step: DesktopOnboardingStep = .welcome
    @Published private(set) var rewritePracticeCompleted = false
    @Published private(set) var replyPracticeCompleted = false
    @Published private(set) var selectedPack: OnboardingPresetPack?
    @Published var buttonDrafts: [OnboardingButtonDraft] = [] {
        didSet { saveDrafts() }
    }
    @Published private(set) var isPreparingPurpose = false
    @Published private(set) var purposeError: String?
    @Published private(set) var isSavingButtons = false
    @Published private(set) var reviewError: String?

    let mainModel: MainModel
    let overlay: OverlayController

    private let progress: OnboardingProgressStore
    private let onFinish: () -> Void
    private var replaying = false
    var restoreWindowAfterTutorialInsert: (() -> Void)?

    init(
        mainModel: MainModel,
        overlay: OverlayController,
        progress: OnboardingProgressStore,
        onFinish: @escaping () -> Void
    ) {
        self.mainModel = mainModel
        self.overlay = overlay
        self.progress = progress
        self.onFinish = onFinish
    }

    func start(replay: Bool) {
        replaying = replay
        rewritePracticeCompleted = false
        replyPracticeCompleted = false
        selectedPack = progress.savedPack
        buttonDrafts = progress.savedDrafts
        move(to: replay ? .welcome : progress.savedStep)
    }

    func move(to next: DesktopOnboardingStep) {
        if [.practice, .replyPractice].contains(step), next != step { overlay.endTutorial() }
        step = next
        if !replaying { progress.save(step: next) }

        switch next {
        case .welcome, .purpose, .review, .access:
            overlay.setVisible(false)
        case .bar, .complete:
            overlay.endTutorial()
            overlay.setVisible(true)
        case .practice:
            overlay.setVisible(true)
            overlay.beginTutorial(prompts: tutorialPrompts) { [weak self] in
                guard let self else { return }
                self.rewritePracticeCompleted = true
                self.restoreWindowAfterTutorialInsert?()
            }
        case .replyPractice:
            overlay.setVisible(true)
            overlay.beginReplyTutorial { [weak self] in
                guard let self else { return }
                self.replyPracticeCompleted = true
                self.restoreWindowAfterTutorialInsert?()
            }
        }
    }

    func advance() {
        switch step {
        case .welcome where mainModel.isSignedIn: preparePurpose()
        case .purpose: move(to: .review)
        case .review: confirmButtons()
        case .access where mainModel.isTrusted: move(to: .bar)
        case .bar: move(to: .practice)
        case .practice where rewritePracticeCompleted: move(to: .replyPractice)
        case .replyPractice where replyPracticeCompleted: move(to: .complete)
        case .complete: finish()
        default: break
        }
    }

    var usesCurrentButtons: Bool { selectedPack == nil && !buttonDrafts.isEmpty }

    var tutorialSample: String {
        OnboardingPracticeSample.text(for: tutorialPrompt)
    }

    var canConfirmButtons: Bool {
        !buttonDrafts.isEmpty && buttonDrafts.allSatisfy {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func select(pack: OnboardingPresetPack) {
        selectedPack = pack
        buttonDrafts = pack.drafts()
        reviewError = nil
        saveDrafts()
    }

    func selectCurrentButtons() {
        selectedPack = nil
        buttonDrafts = mainModel.prompts.map(OnboardingButtonDraft.init(prompt:))
        reviewError = nil
        saveDrafts()
    }

    func updateDraft(_ draft: OnboardingButtonDraft) {
        guard let index = buttonDrafts.firstIndex(where: { $0.id == draft.id }) else { return }
        buttonDrafts[index] = draft
        reviewError = nil
    }

    func moveDraft(id: UUID, by offset: Int) {
        guard let source = buttonDrafts.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard buttonDrafts.indices.contains(destination) else { return }
        buttonDrafts.swapAt(source, destination)
        reviewError = nil
    }

    func addDraft() {
        guard buttonDrafts.count < 7 else { return }
        buttonDrafts.append(OnboardingButtonDraft(
            title: "新しいボタン",
            prompt: "次の文章を、意図を保ったまま読みやすく書き直してください。",
            origin: .onboardingBuilder
        ))
        reviewError = nil
    }

    func deleteDraft(id: UUID) {
        guard buttonDrafts.count > 1 else { return }
        buttonDrafts.removeAll { $0.id == id }
        reviewError = nil
    }

    func back() {
        guard let index = DesktopOnboardingStep.flow.firstIndex(of: step), index > 0 else { return }
        let previous = DesktopOnboardingStep.flow[index - 1]
        move(to: previous)
    }

    func copyReplyPracticeMessage(_ message: String) {
        overlay.copyReplyTutorialSource(message)
    }

    func skipEducation() {
        guard mainModel.isSignedIn, mainModel.isTrusted else { return }
        finish()
    }

    func close() {
        overlay.endTutorial()
        overlay.setVisible(mainModel.isSignedIn && mainModel.isTrusted)
    }

    private func finish() {
        overlay.endTutorial()
        overlay.setVisible(true)
        if !replaying { progress.complete() }
        onFinish()
    }

    private func preparePurpose() {
        guard !isPreparingPurpose else { return }
        isPreparingPurpose = true
        purposeError = nil
        Task {
            await mainModel.reloadPrompts()
            isPreparingPurpose = false
            if mainModel.promptsError != nil {
                purposeError = "ボタンを読み込めませんでした。接続を確認して、もう一度お試しください。"
                return
            }
            if buttonDrafts.isEmpty {
                if mainModel.prompts.isEmpty {
                    select(pack: .starter)
                } else {
                    selectCurrentButtons()
                }
            }
            move(to: .purpose)
        }
    }

    private func confirmButtons() {
        guard canConfirmButtons, !isSavingButtons else { return }
        isSavingButtons = true
        reviewError = nil
        let drafts = buttonDrafts
        Task {
            defer { isSavingButtons = false }
            do {
                try await mainModel.applyOnboardingButtons(drafts)
                move(to: .access)
            } catch {
                reviewError = "ボタンを保存できませんでした。接続を確認して、もう一度お試しください。"
            }
        }
    }

    private func saveDrafts() {
        guard !replaying else { return }
        progress.save(pack: selectedPack, drafts: buttonDrafts)
    }

    private var tutorialPrompt: UserPrompt {
        tutorialPrompts.first ?? Self.fallbackTutorialPrompt
    }

    private var tutorialPrompts: [UserPrompt] {
        let enabled = mainModel.prompts.filter(\.isEnabled)
        return enabled.isEmpty ? [Self.fallbackTutorialPrompt] : enabled
    }

    private static let fallbackTutorialPrompt = UserPrompt(
        id: UUID(uuidString: "A8D15BB9-5A3F-45A3-B5D7-91B3AC0D8C44")!,
        slot: .main,
        title: "敬語",
        prompt: "次の文章を、日常でそのまま送れる自然でやわらかい丁寧語に変換してください。意味を変えず、命令や指示はやわらかいお願いの形にしてください。出力は変換後の文章だけにしてください。",
        origin: .onboardingPreset
    )
}

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let coordinator: OnboardingCoordinator

    @MainActor
    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "敬語ボタンをはじめる"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(Tokens.Window.shell)
        window.isReleasedWhenClosed = false

        let contentSize = NSSize(width: 1080, height: 700)
        let hostingView = NSHostingView(rootView: OnboardingFlowView(coordinator: coordinator))
        // The default `.standardBounds` reflects SwiftUI's changing min, ideal and
        // max measurements back into the NSWindow. Practice is the only step with a
        // focused TextEditor, so entering it invalidated those measurements and made
        // the window grow despite contentMinSize/contentMaxSize. This window has one
        // fixed frame; its content must consume the AppKit proposal, not resize it.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.setContentSize(contentSize)
        window.center()
        super.init(window: window)
        window.delegate = self
        coordinator.restoreWindowAfterTutorialInsert = { [weak window] in
            guard let window else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @MainActor
    func present(replay: Bool) {
        coordinator.start(replay: replay)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor [coordinator] in coordinator.close() }
    }
}
