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

    /// Raw values are append-only — a saved step from an unfinished run is read back by
    /// number — while this array owns the order the user actually sees. `source` is
    /// second to last: 完了 stays the page the run ends on, and a question asked after
    /// the closing card would be asked after the app was already handed over.
    ///
    /// `language` is first for the opposite reason: it is the only page whose answer
    /// changes every page after it, so it has to be asked before there is anything to
    /// re-render. It is also the one page with no Back button — there is nowhere behind
    /// it — and the only one that does not require a session.
    public static let flow: [DesktopOnboardingStep] = [
        .language, .welcome, .purpose, .review, .access, .bar, .practice, .customPractice,
        .replyPractice, .source, .complete,
    ]
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
