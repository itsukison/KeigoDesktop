import Foundation

/// Which row on the server an incoming button is actually *about*.
///
/// `user_prompts` carries a second unique key besides its primary one, and it is not
/// visible from the Swift model:
///
/// ```
/// CREATE UNIQUE INDEX user_prompts_user_builtin_unique
///   ON public.user_prompts (user_id, builtin_key) WHERE builtin_key IS NOT NULL;
/// ```
///
/// So a `builtin_key` is an identity, not a label — an account owns at most one `polite`
/// row, whatever its id. The onboarding write upserts `on_conflict=id`, and a preset pack
/// mints fresh ids, so 「まずは定番」 on an account whose phone already seeded `polite`
/// sent a *new* row carrying an already-owned key: the id conflict never fired, the partial
/// unique index did, and PostgREST answered 409. Reordering the write (delete first, then
/// insert) would fix the symptom by making a failure able to leave the account with no
/// buttons at all — so the id is reconciled instead, which turns that insert into the update
/// it was always meant to be.
///
/// This is why the review step failed on the first attempt and passed after switching packs:
/// `starter`, `japanese` and `international` carry builtin keys and collided; `work` and
/// `social` carry none and went straight through.
public enum UserPromptIdentity {

    /// Re-points each incoming button at the row the account already owns for its
    /// `builtinKey`, keeping that row's `createdAt` — the button has existed since the phone
    /// made it, and only its text is being replaced. Everything else is passed through
    /// untouched, including `origin`: the content now in the row did come from the preset.
    public static func reconciled(
        _ incoming: [UserPrompt],
        existing: [UserPrompt]
    ) -> [UserPrompt] {
        var ownerByBuiltinKey: [String: UserPrompt] = [:]
        for row in existing {
            guard let key = row.builtinKey, ownerByBuiltinKey[key] == nil else { continue }
            ownerByBuiltinKey[key] = row
        }

        var claimed = Set<UUID>()
        return incoming.map { prompt in
            var id = prompt.id
            var builtinKey = prompt.builtinKey
            var createdAt = prompt.createdAt

            if let key = builtinKey, let owner = ownerByBuiltinKey[key] {
                id = owner.id
                createdAt = owner.createdAt
            }

            // One upsert may not carry the same id twice — Postgres refuses to let
            // ON CONFLICT DO UPDATE touch a row a second time. The only way to get here is
            // two incoming buttons claiming one builtin key, which the account could not
            // store either. Drop the later one's claim rather than the button: it keeps its
            // own identity and lands as an ordinary row.
            if claimed.contains(id) {
                id = claimed.contains(prompt.id) ? UUID() : prompt.id
                builtinKey = nil
                createdAt = prompt.createdAt
            }
            claimed.insert(id)

            return UserPrompt(
                id: id,
                slot: prompt.slot,
                builtinKey: builtinKey,
                title: prompt.title,
                prompt: prompt.prompt,
                isEnabled: prompt.isEnabled,
                sortOrder: prompt.sortOrder,
                origin: prompt.origin,
                createdAt: createdAt,
                updatedAt: prompt.updatedAt
            )
        }
    }
}
