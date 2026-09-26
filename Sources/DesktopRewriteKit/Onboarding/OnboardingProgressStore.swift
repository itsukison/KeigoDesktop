import Foundation

public enum DesktopOnboardingStep: Int, CaseIterable, Sendable {
    case welcome = 0
    case purpose = 1
    case review = 2
    case access = 3
    case bar = 4 // Reserved for older installs; resumes at practice.
    case practice = 5
    case complete = 6
    case replyPractice = 7
    case customPractice = 8
    case source = 9
    case language = 10
    case offer = 11
    case name = 12
    case writingStyle = 13

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
    ///
    /// `name` follows `welcome` because it is the one question about the *user* rather
    /// than about the app, and it belongs beside the account it is stored on. It used
    /// to be a second card on that page, stacked under the sign-in — where it read as
    /// one more field of the signup form rather than as the name every rewrite will be
    /// signed with, which is the only thing it is for.
    public static let flow: [DesktopOnboardingStep] = [
        .language, .welcome, .name, .purpose, .review, .access, .practice,
        .customPractice, .replyPractice, .source, .offer, .complete,
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

    /// The three practice pages carry 「あとで始める」. They teach interaction rather
    /// than setup, and so the only ones a user can decline without leaving the app in
    /// a half-configured state.
    public static let educationSteps: [DesktopOnboardingStep] = [
        .practice, .customPractice, .replyPractice,
    ]

    /// Retire pages without reusing persisted identifiers or restarting setup.
    public var activeStep: DesktopOnboardingStep {
        switch self {
        case .writingStyle: return .purpose
        case .bar: return .practice
        default: return self
        }
    }

    /// Where 「あとで始める」 goes: **the next page in `flow`, never the end of the run.**
    ///
    /// It used to call `finish()`, which fired `desktop_onboarding_completed` and shut
    /// the window from whichever practice the user was on. That skipped `source` and
    /// `offer` along with the exercise — so declining one tutorial silently cancelled
    /// the only time the run ever asks for money, and did it on the four pages that
    /// come *before* the ask. Two of the first four completions took that exit and
    /// were never shown a price; `desktop.welcome_offers` has no row for either,
    /// because `desktop_start_welcome_offer` is called from `.offer` and `.offer` was
    /// never reached.
    ///
    /// Skipping is per page, so the link and the primary button differ only in whether
    /// the current exercise had to be finished first. That is deliberate: the run's
    /// last three pages are not optional, and the way out of the tutorial is forward
    /// through it rather than around it.
    ///
    /// `nil` for every other page — nothing else offers the link, and a caller asking
    /// on `.offer` or `.complete` is asking the wrong question.
    public var skippingEducation: DesktopOnboardingStep? {
        guard Self.educationSteps.contains(self),
              let position = Self.flow.firstIndex(of: self),
              position + 1 < Self.flow.count
        else { return nil }
        return Self.flow[position + 1]
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
    private let persistsChanges: Bool

    public init(defaults: UserDefaults = .standard, prefix: String = "desktopOnboarding", persistsChanges: Bool = true) {
        self.defaults = defaults
        self.prefix = prefix
        self.persistsChanges = persistsChanges
    }

    public func replayCopy() -> OnboardingProgressStore {
        OnboardingProgressStore(defaults: defaults, prefix: prefix, persistsChanges: false)
    }

    public var isComplete: Bool {
        defaults.integer(forKey: key("completedVersion")) >= Self.currentVersion
    }

    public var shouldPresentIntro: Bool {
        !isComplete && defaults.object(forKey: key("step")) == nil
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
        let step = DesktopOnboardingStep(rawValue: defaults.integer(forKey: key("step"))) ?? .welcome
        return step.activeStep
    }

    public func save(step: DesktopOnboardingStep) {
        guard persistsChanges, !isComplete else { return }
        defaults.set(step.rawValue, forKey: key("step"))
    }

    public func complete(accountID: String? = nil) {
        guard persistsChanges else { return }
        defaults.set(Self.currentVersion, forKey: key("completedVersion"))
        defaults.removeObject(forKey: key("step"))
        if let accountID {
            defaults.removeObject(forKey: draftKey("pack", accountID: accountID))
            defaults.removeObject(forKey: draftKey("drafts", accountID: accountID))
        }
    }

    public func save(pack: OnboardingPresetPack?, drafts: [OnboardingButtonDraft], accountID: String) {
        guard persistsChanges, !accountID.isEmpty else { return }
        if let pack {
            defaults.set(pack.rawValue, forKey: draftKey("pack", accountID: accountID))
        } else {
            defaults.removeObject(forKey: draftKey("pack", accountID: accountID))
        }
        defaults.set(try? JSONEncoder().encode(drafts), forKey: draftKey("drafts", accountID: accountID))
    }

    public func savedPack(for accountID: String) -> OnboardingPresetPack? {
        defaults.string(forKey: draftKey("pack", accountID: accountID)).flatMap(OnboardingPresetPack.init(rawValue:))
    }

    public func savedDrafts(for accountID: String) -> [OnboardingButtonDraft] {
        guard let data = defaults.data(forKey: draftKey("drafts", accountID: accountID)) else { return [] }
        return (try? JSONDecoder().decode([OnboardingButtonDraft].self, from: data)) ?? []
    }

    private func draftKey(_ suffix: String, accountID: String) -> String {
        key("account.\(accountID).\(suffix)")
    }

    private func key(_ suffix: String) -> String {
        "\(prefix).\(suffix)"
    }
}
