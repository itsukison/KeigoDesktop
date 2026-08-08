import AppKit
import DesktopRewriteKit
import SwiftUI

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var step: DesktopOnboardingStep = .welcome
    @Published private(set) var tutorialCompleted = false

    let mainModel: MainModel
    let overlay: OverlayController

    private let progress: OnboardingProgressStore
    private let onFinish: () -> Void
    private var replaying = false

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
        tutorialCompleted = false
        move(to: replay ? .welcome : progress.savedStep)
    }

    func move(to next: DesktopOnboardingStep) {
        if step == .practice, next != .practice { overlay.endTutorial() }
        step = next
        if !replaying { progress.save(step: next) }

        switch next {
        case .welcome, .access:
            overlay.setVisible(false)
        case .bar, .complete:
            overlay.endTutorial()
            overlay.setVisible(true)
        case .practice:
            overlay.setVisible(true)
            overlay.beginTutorial(prompt: Self.tutorialPrompt) { [weak self] in
                self?.tutorialCompleted = true
            }
        }
    }

    func advance() {
        switch step {
        case .welcome where mainModel.isSignedIn: move(to: .access)
        case .access where mainModel.isTrusted: move(to: .bar)
        case .bar: move(to: .practice)
        case .practice where tutorialCompleted: move(to: .complete)
        case .complete: finish()
        default: break
        }
    }

    func back() {
        guard let previous = DesktopOnboardingStep(rawValue: step.rawValue - 1) else { return }
        move(to: previous)
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

    private static let tutorialPrompt = UserPrompt(
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "敬語ボタンをはじめる"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(Tokens.Window.shell)
        window.contentMinSize = NSSize(width: 960, height: 640)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingFlowView(coordinator: coordinator))
        window.center()
        super.init(window: window)
        window.delegate = self
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
