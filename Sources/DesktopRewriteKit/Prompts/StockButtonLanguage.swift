import Foundation

/// Whether the user's buttons write the language the app now writes.
///
/// They are two separate pieces of state and nothing kept them in agreement. The
/// interface language lives in `UserDefaults` on this Mac (§17); the buttons live in
/// `user_prompts` on the server, shared with the phone, and no code path rewrote them
/// when the language changed — the ⚙︎ 一般 row said so in as many words. So an English
/// user could be holding four buttons whose instructions are Japanese sentences that
/// explicitly ask for Japanese output, and get exactly that.
///
/// `writingLanguage` on the wire does not save them. It selects an English system
/// prompt, and a one-line persona statement loses to a specific command; the backend's
/// own instructions say "Apply the user-supplied command instruction to it". The model
/// obeys the button. The button has to be right.
///
/// **Detection is exact string matching, never a heuristic.** A body counts as stock
/// only if it equals a preset template or one of the seed rows verbatim. That direction
/// of error is the safe one: a wording change upstream makes the offer stop appearing,
/// where a script or language detector would eventually flag a button the user wrote
/// themselves and propose deleting it.
public enum StockButtonLanguage {

    /// The four rows `public.handle_new_user()` inserts for every new account, in the
    /// trigger's exact wording.
    ///
    /// Not in `OnboardingPresetCatalog`, and they cannot be. The trigger lives in the
    /// database the iOS keyboard shares, it predates this app, and it seeds Japanese
    /// unconditionally — when it was written, Japanese was the only thing either surface
    /// produced. Changing it is a change to the iOS signup path, so this app reconciles
    /// after the fact instead. Anyone who signed up and never picked a preset pack is
    /// still holding precisely these.
    ///
    /// Copied strings rather than a query, because this decides whether to show a
    /// banner and a round trip that can fail is the wrong dependency for that.
    static let seedBodies: Set<String> = [
        "Rewrite into polite, business-appropriate Japanese (敬語) while preserving meaning.",
        "Rewrite into natural, idiomatic Japanese while preserving meaning. Make it sound like a native speaker wrote it.",
        "Rewrite into formal Japanese business email style (件名を要さず、本文のみ). Use 拝啓 only if culturally appropriate, otherwise typical メール本文 register with お世話になっております level politeness when applicable.",
        "Translate into natural English.",
    ]

    /// Stock bodies that write Japanese: the presets plus the seeds.
    ///
    /// 英訳's "Translate into natural English." is in here despite being an English
    /// sentence asking for English output, and that is correct — it is a *Japanese
    /// user's* button, one of the four the trigger seeds, and its presence is part of
    /// what identifies an untouched Japanese set. It is stock text either way, so it is
    /// never mistaken for something the user wrote.
    static func japaneseWritingBodies() -> Set<String> {
        OnboardingPresetPack.stockPromptBodies(writtenIn: .japanese).union(seedBodies)
    }

    static func englishWritingBodies() -> Set<String> {
        OnboardingPresetPack.stockPromptBodies(writtenIn: .english)
    }

    private static func bodies(writtenIn language: AppLanguage) -> Set<String> {
        language.writesJapanese ? japaneseWritingBodies() : englishWritingBodies()
    }

    private static func body(of prompt: UserPrompt) -> String {
        prompt.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Buttons that are stock text for the language the app is *not* writing.
    ///
    /// Only these are ever replaced. Everything else — hand-written buttons, buttons
    /// built by the phone's onboarding, buttons whose preset text the user has since
    /// edited — is the user's work and is kept.
    public static func mismatched(
        in prompts: [UserPrompt],
        whenWriting language: AppLanguage
    ) -> [UserPrompt] {
        let foreign = bodies(writtenIn: language.writesJapanese ? .english : .japanese)
        return prompts.filter { foreign.contains(body(of: $0)) }
    }

    /// Whether to offer the swap at all.
    ///
    /// Disabled buttons count. A button that is off is still one press away from being
    /// on, and a banner that appears the moment someone re-enables a row reads as a
    /// fault rather than an offer.
    public static func writesOtherLanguage(
        _ prompts: [UserPrompt],
        whenWriting language: AppLanguage
    ) -> Bool {
        !mismatched(in: prompts, whenWriting: language).isEmpty
    }

    /// The replacement set for a chosen pack: the pack's buttons, then every button the
    /// user did not get from a preset, in the order they already had.
    ///
    /// The second half is load-bearing. `UserPromptRemoteStore.replaceAll` deletes any
    /// row absent from what it is handed, so returning the pack alone would destroy
    /// hand-made buttons — which is the one outcome a fix for "my buttons are in the
    /// wrong language" must not produce. Stock buttons in the *target* language are
    /// dropped as well as mismatched ones: they are what the pack is replacing, and
    /// keeping them would leave two copies of Polite.
    ///
    /// Capped at seven, the app's own limit (`addDraft`). A user with more hand-made
    /// buttons than fit alongside a pack keeps the first of them; `keptCount` is what
    /// the confirmation copy quotes so the number is never a surprise.
    public static func replacement(
        choosing pack: OnboardingPresetPack,
        keeping prompts: [UserPrompt],
        whenWriting language: AppLanguage
    ) -> [OnboardingButtonDraft] {
        let stock = japaneseWritingBodies().union(englishWritingBodies())
        let kept = prompts
            .filter { !stock.contains(body(of: $0)) }
            .map(OnboardingButtonDraft.init(prompt:))
        return Array((pack.drafts(writtenIn: language) + kept).prefix(maxButtons))
    }

    /// How many of the user's own buttons survive the swap, for the confirmation copy.
    public static func keptCount(
        choosing pack: OnboardingPresetPack,
        keeping prompts: [UserPrompt],
        whenWriting language: AppLanguage
    ) -> Int {
        max(0, replacement(choosing: pack, keeping: prompts, whenWriting: language).count
            - pack.drafts(writtenIn: language).count)
    }

    /// Matches `OnboardingWindowController.addDraft`'s ceiling. Seven is the point at
    /// which the hover row stops fitting a laptop screen (§4).
    static let maxButtons = 7
}
