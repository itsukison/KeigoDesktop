import AppKit
import Combine
import DesktopRewriteKit
import SwiftUI

@MainActor
final class OnboardingIntroController {
    private(set) var phase: IntroPhase = .hidden
    private let sequence = OnboardingIntroSequence()
    private let overlay: OverlayController
    private let window: NSWindow
    private let screen: NSScreen
    private let presentation: IntroPillPresentation
    private let content: OnboardingIntroContent
    private let dimmer: OnboardingIntroPanel
    private let debugReplay: Bool
    private let onFinish: (Bool) -> Void
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var ended = false
    private var began = false
    private var landingFrame: CGRect

    init(overlay: OverlayController, window: NSWindow, screen: NSScreen,
         debugReplay: Bool, onFinish: @escaping (Bool) -> Void) {
        self.overlay = overlay
        self.window = window
        self.screen = screen
        self.debugReplay = debugReplay
        self.onFinish = onFinish
        presentation = IntroPillPresentation(canvasSize: screen.frame.size,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        content = OnboardingIntroContent(screenFrame: screen.frame)
        dimmer = OnboardingIntroPanel(screen: screen, content: content)
        landingFrame = overlay.introLandingFrame(on: screen)
        content.pillFrame = landingFrame
    }

    func start() {
        guard !began else { return }
        began = true
        // The real onboarding window is laid out before any of its pixels are shown.
        window.alphaValue = 0
        let area = screen.visibleFrame
        window.setFrameOrigin(CGPoint(x: area.midX - window.frame.width / 2,
                                      y: area.midY - window.frame.height / 2))
        window.contentView?.layoutSubtreeIfNeeded()
        dimmer.onSkip = { [weak self] in self?.sequence.skipToReveal() }
        dimmer.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        overlay.beginIntro(presentation, on: screen, debugReplay: debugReplay)
        observeInterruptions()
        sequence.start(reduceMotion: presentation.reduceMotion) { [weak self] beat in
            try await self?.perform(beat)
        }
    }

    func interrupt() { finish(visible: false) }

    private func perform(_ beat: IntroBeat) async throws {
        guard !ended else { return }
        phase = beat.cue.phase
        switch beat.cue {
        case .dim:
            animate(.easeInOut(duration: beat.duration)) { content.dimOpacity = 0.88 }
        case .enter:
            animate(.easeOut(duration: beat.duration)) {
                presentation.opacity = 1
                presentation.scale = CGSize(width: 1, height: 1)
            }
        case .settle:
            animate(.spring(response: 0.35, dampingFraction: 0.85)) {
                presentation.scale = CGSize(width: 1, height: 1)
                presentation.characterState = .bounce
            }
        case .expression:
            animate(.easeInOut(duration: 0.2)) { presentation.characterState = .look }
        case .copy:
            animate(.easeInOut(duration: beat.duration)) {
                presentation.copyOpacity = 1
                presentation.scale = CGSize(width: 1, height: 1)
            }
        case .read, .pillRead: break
        case .copyOut:
            animate(.easeInOut(duration: beat.duration)) { presentation.supportingCopyOpacity = 0 }
        case .nextCopy:
            presentation.showsSecondCopy = true
            animate(.easeInOut(duration: beat.duration)) { presentation.supportingCopyOpacity = 1 }
        case .anticipate:
            landingFrame = overlay.introLandingFrame(on: screen)
            animate(.easeInOut(duration: beat.duration)) {
                presentation.copyOpacity = 0
                presentation.characterState = .fall
            }
        case .travel:
            animate(.timingCurve(0.42, 0, 0.65, 1, duration: beat.duration)) {
                presentation.position = IntroGeometry.landingPoint(pill: landingFrame, screen: screen.frame)
                presentation.travelProgress = 1
                presentation.characterSize = 24
            }
        case .land:
            animate(.easeOut(duration: 0.35)) {
                presentation.pillWidth = landingFrame.width
                presentation.pillOpacity = 1
            }
            animate(.easeOut(duration: beat.duration)) {
                presentation.characterState = .land
                presentation.characterSize = 16
                presentation.spriteMix = 1
            }
        case .formPill:
            animate(.spring(response: 0.22, dampingFraction: 0.88)) {
                presentation.scale = CGSize(width: 1, height: 1)
            }
        case .reducedDeparture:
            animate(.easeOut(duration: beat.duration)) {
                presentation.copyOpacity = 0
                presentation.opacity = 0
            }
        case .reducedArrival:
            placeAtLanding()
            animate(.easeIn(duration: beat.duration)) { presentation.opacity = 1 }
        case .quickLanding:
            if overlay.introPresentation != nil {
                if presentation.reduceMotion {
                    placeAtLanding()
                    presentation.copyOpacity = 0
                    animate(.easeIn(duration: beat.duration)) { presentation.opacity = 1 }
                } else {
                    animate(.easeInOut(duration: beat.duration)) {
                        placeAtLanding()
                        presentation.opacity = 1
                        presentation.copyOpacity = 0
                    }
                }
            }
        case .pillReady:
            overlay.settleIntro(on: screen)
            content.pillFrame = overlay.lessonBarFrame
            if beat.duration > 0 {
                animate(.easeIn(duration: beat.duration)) { content.pillCopyOpacity = 1 }
            }
        case .wiggle:
            overlay.cueIntroDrag()
        case .reveal:
            // Native tracking consumes mouse-up; the existing drag controller owns completion.
            while overlay.introDragInProgress {
                try await Task.sleep(for: .milliseconds(50))
            }
            try Task.checkCancellation()
            animate(.easeInOut(duration: beat.duration)) {
                content.pillCopyOpacity = 0
                content.dimOpacity = 0
            }
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = beat.duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 1
            }, completionHandler: nil)
        case .finish:
            finish(visible: true)
        }
    }

    private func placeAtLanding() {
        landingFrame = overlay.introLandingFrame(on: screen)
        presentation.characterState = .idle
        presentation.position = IntroGeometry.landingPoint(pill: landingFrame, screen: screen.frame)
        presentation.travelProgress = 1
        presentation.characterSize = 16
        presentation.scale = CGSize(width: 1, height: 1)
        presentation.spriteMix = 1
        presentation.pillWidth = landingFrame.width
        presentation.pillOpacity = 1
    }

    private func animate(_ animation: Animation, _ changes: () -> Void) {
        withAnimation(animation, changes)
    }

    private func finish(visible: Bool) {
        guard !ended else { return }
        ended = true
        phase = .finished
        sequence.cancel()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        subscriptions.removeAll()
        let survivingScreen = NSScreen.screens.first { $0 == screen } ?? NSScreen.main
        if let survivingScreen { overlay.settleIntro(on: survivingScreen) }
        overlay.finishIntroPresentation()
        dimmer.orderOut(nil)
        window.alphaValue = 1
        if visible {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
            overlay.setVisible(false)
        }
        onFinish(visible)
    }

    private func observeInterruptions() {
        observe(NotificationCenter.default, NSApplication.didResignActiveNotification)
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
        overlay.$isDraggingBar.combineLatest(overlay.$parkedZone)
            .sink { [weak self] dragging, _ in
                guard let self else { return }
                self.content.pillFrame = self.overlay.lessonBarFrame
                if dragging { self.content.pillCopyOpacity = 0 }
            }.store(in: &subscriptions)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.interrupt() }
        }
        observers.append((center, observer))
    }
}
