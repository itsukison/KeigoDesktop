import Foundation

public enum DesktopOnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case access
    case bar
    case practice
    case complete
}

public final class OnboardingProgressStore: @unchecked Sendable {
    public static let currentVersion = 1

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
    }

    private func key(_ suffix: String) -> String {
        "\(prefix).\(suffix)"
    }
}
