import Foundation

/// Education is tracked independently of Sparkle's available/installed versions.
public struct ReleaseIntroductionStore {
    private let defaults: UserDefaults
    private let key = "updates.seenIntroductions"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func shouldPresent(_ releaseID: String) -> Bool {
        !(defaults.stringArray(forKey: key) ?? []).contains(releaseID)
    }

    public func acknowledge(_ releaseID: String) {
        var seen = defaults.stringArray(forKey: key) ?? []
        guard !seen.contains(releaseID) else { return }
        seen.append(releaseID)
        defaults.set(seen, forKey: key)
    }

    public func prepare(_ releaseID: String, onboardingComplete: Bool) {
        // First-time users learn these features in onboarding instead.
        if !onboardingComplete { acknowledge(releaseID) }
    }
}
