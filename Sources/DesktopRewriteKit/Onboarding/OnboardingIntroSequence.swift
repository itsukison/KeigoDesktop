import Foundation

public enum IntroPhase: Equatable, Sendable {
    case hidden, characterEntering, introduction, movingToPill
    case pillIntroduction, revealingOnboarding, finished
}

public enum IntroCue: Equatable, Sendable {
    case dim, enter, settle, expression, copy, read, copyOut, nextCopy
    case anticipate, travel, land, formPill, pillReady, wiggle, pillRead
    case reducedDeparture, reducedArrival, quickLanding, reveal, finish

    public var phase: IntroPhase {
        switch self {
        case .dim: return .hidden
        case .enter, .settle, .expression: return .characterEntering
        case .copy, .read, .copyOut, .nextCopy: return .introduction
        case .anticipate, .travel, .land, .formPill, .reducedDeparture,
             .reducedArrival, .quickLanding: return .movingToPill
        case .pillReady, .wiggle, .pillRead: return .pillIntroduction
        case .reveal: return .revealingOnboarding
        case .finish: return .finished
        }
    }
}

public struct IntroBeat: Equatable, Sendable {
    public let cue: IntroCue
    public let duration: TimeInterval

    public init(_ cue: IntroCue, _ duration: TimeInterval) {
        self.cue = cue
        self.duration = duration
    }
}

public enum OnboardingIntroTimeline {
    public static func beats(reduceMotion: Bool) -> [IntroBeat] {
        let entrance: [IntroBeat] = reduceMotion
            ? [.init(.enter, 0.3)]
            : [.init(.enter, 0.35), .init(.settle, 0.35), .init(.expression, 0.5)]
        let landing: [IntroBeat] = reduceMotion
            ? [.init(.reducedDeparture, 0.15), .init(.reducedArrival, 0.2)]
            : [.init(.anticipate, 0.1), .init(.travel, 0.55),
               .init(.land, 0.2), .init(.formPill, 0.15)]
        return [.init(.dim, 0.4)] + entrance
            + [.init(.copy, 0.35), .init(.read, 4), .init(.copyOut, 0.25),
               .init(.nextCopy, 0.35), .init(.read, 5)]
            + landing + [.init(.pillReady, 0.3)]
            + (reduceMotion ? [] : [.init(.wiggle, 0.45)])
            + [.init(.pillRead, reduceMotion ? 3 : 2.55), .init(.reveal, 0.7), .init(.finish, 0)]
    }

    public static let skip: [IntroBeat] = [
        .init(.quickLanding, 0.25), .init(.pillReady, 0),
        .init(.reveal, 0.7), .init(.finish, 0),
    ]
}

/// One cancellable clock owns the sequence. A superseded run cannot deliver a cue.
@MainActor
public final class OnboardingIntroSequence {
    public typealias Sleep = @MainActor (TimeInterval) async throws -> Void
    public typealias Perform = @MainActor (IntroBeat) async throws -> Void
    public private(set) var isRunning = false
    private var hasStarted = false
    private var skipped = false
    private var revision = 0
    private var task: Task<Void, Never>?
    private let sleep: Sleep
    private var perform: Perform?

    public init(sleep: @escaping Sleep = { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }) {
        self.sleep = sleep
    }

    public func start(reduceMotion: Bool, perform: @escaping Perform) {
        guard !hasStarted else { return }
        hasStarted = true
        self.perform = perform
        run(OnboardingIntroTimeline.beats(reduceMotion: reduceMotion))
    }

    public func skipToReveal() {
        guard isRunning, !skipped else { return }
        skipped = true
        run(OnboardingIntroTimeline.skip)
    }

    public func cancel() {
        revision += 1
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func run(_ beats: [IntroBeat]) {
        cancel()
        isRunning = true
        let expected = revision
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for beat in beats {
                    try Task.checkCancellation()
                    guard self.revision == expected else { return }
                    try await self.perform?(beat)
                    try await self.sleep(beat.duration)
                }
            } catch {
                if !Task.isCancelled, self.revision == expected {
                    try? await self.perform?(IntroBeat(.finish, 0))
                }
            }
            guard self.revision == expected else { return }
            self.isRunning = false
            self.task = nil
        }
    }
}

public enum IntroGeometry {
    public static func localPoint(_ point: CGPoint, in screen: CGRect) -> CGPoint {
        CGPoint(x: point.x - screen.minX, y: screen.maxY - point.y)
    }

    public static func landingPoint(pill: CGRect, screen: CGRect) -> CGPoint {
        localPoint(CGPoint(x: pill.midX, y: pill.midY), in: screen)
    }
}
