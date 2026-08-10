import Foundation

public enum DesktopOnboardingStep: Int, CaseIterable, Sendable {
    case welcome = 0
    case purpose = 1
    case review = 2
    case access = 3
    case bar = 4
    case practice = 5
    case complete = 6
    case replyPractice = 7
    case customPractice = 8
    case source = 9
    case language = 10
    case offer = 11

    /// Raw values are append-only — a saved step from an unfinished run is read back by
    /// number — while this array owns the order the user actually sees. `source` is
    /// third from last: 完了 stays the page the run ends on, and a question asked after
    /// the closing card would be asked after the app was already handed over.
    ///
    /// `offer` sits between them for the same reason, and it is the harder call. The
    /// offer is the one page in the run that asks for money, so it has to come *after*
    /// the three practices — the user has watched their own text get rewritten in their
    /// own apps, which is the entire argument for paying — and *before* 完了, which
    /// hands the app over. Putting it after 完了 would be an ask bolted onto the end of
    /// a finished flow; putting it earlier would be an ask made before the value.
    ///
    /// `language` is first for the opposite reason: it is the only page whose answer
    /// changes every page after it, so it has to be asked before there is anything to
    /// re-render. It is also the one page with no Back button — there is nowhere behind
    /// it — and the only one that does not require a session.
    public static let flow: [DesktopOnboardingStep] = [
        .language, .welcome, .purpose, .review, .access, .bar, .practice, .customPractice,
        .replyPractice, .source, .offer, .complete,
    ]

    /// The steps the progress rail counts, in order.
    ///
    /// Two pages are deliberately not on it. `language` is asked before setting up
    /// starts, and counting it would tell someone they are 9 % done for having said
    /// which language they read. `offer` is not setting the app up at all — it is a
    /// purchase — and a rail segment would frame paying as a step of installation,
    /// which is both untrue and the kind of pressure this page is written to avoid.
    public static let railSteps: [DesktopOnboardingStep] = flow.filter {
        $0 != .language && $0 != .offer
    }

    /// Which rail segment to light for a step that has none: the last counted step at
    /// or before it. Without this the rail reads `firstIndex(of:) ?? 0` and jumps back
    /// to segment one for the length of the offer page.
    public var railAnchor: DesktopOnboardingStep? {
        guard let position = Self.flow.firstIndex(of: self) else { return nil }
        return Self.railSteps.last { step in
            (Self.flow.firstIndex(of: step) ?? .max) <= position
        }
    }
}

public final class OnboardingProgressStore: @unchecked Sendable {
    public static let currentVersion = 2

    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "desktopOnboarding") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public var isComplete: Bool {
        defaults.integer(forKey: key("completedVersion")) >= Self.currentVersion
    }

    /// **Nothing saved means a first run, so it starts at the head of `flow`, not at
    /// `.welcome`.** This returned `.welcome` while that was the first page, and the
    /// two stopped being the same thing when §17 put the language question in front of
    /// it — leaving a brand-new install, the one user the page exists for, skipping it.
    /// A corrupt value still falls back to `.welcome`: that is a recovery path, and
    /// re-asking a language already chosen is the wrong repair.
    public var savedStep: DesktopOnboardingStep {
        guard defaults.object(forKey: key("step")) != nil else {
            return DesktopOnboardingStep.flow.first ?? .welcome
        }
        return DesktopOnboardingStep(rawValue: defaults.integer(forKey: key("step"))) ?? .welcome
    }

    public func save(step: DesktopOnboardingStep) {
        guard !isComplete else { return }
        defaults.set(step.rawValue, forKey: key("step"))
    }

    public func complete() {
        defaults.set(Self.currentVersion, forKey: key("completedVersion"))
        defaults.removeObject(forKey: key("step"))
        defaults.removeObject(forKey: key("pack"))
        defaults.removeObject(forKey: key("drafts"))
    }

    public func save(pack: OnboardingPresetPack?, drafts: [OnboardingButtonDraft]) {
        if let pack {
            defaults.set(pack.rawValue, forKey: key("pack"))
        } else {
            defaults.removeObject(forKey: key("pack"))
        }
        defaults.set(try? JSONEncoder().encode(drafts), forKey: key("drafts"))
    }

    public var savedPack: OnboardingPresetPack? {
        defaults.string(forKey: key("pack")).flatMap(OnboardingPresetPack.init(rawValue:))
    }

    public var savedDrafts: [OnboardingButtonDraft] {
        guard let data = defaults.data(forKey: key("drafts")) else { return [] }
        return (try? JSONDecoder().decode([OnboardingButtonDraft].self, from: data)) ?? []
    }

    private func key(_ suffix: String) -> String {
        "\(prefix).\(suffix)"
    }
}
