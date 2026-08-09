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

    public static let flow: [DesktopOnboardingStep] = [
        .welcome, .purpose, .review, .access, .bar, .practice, .replyPractice, .complete,
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

    public var savedStep: DesktopOnboardingStep {
        guard defaults.object(forKey: key("step")) != nil else { return .welcome }
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
