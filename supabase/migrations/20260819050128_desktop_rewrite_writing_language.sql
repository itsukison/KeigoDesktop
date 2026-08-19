-- Records which language a desktop rewrite was asked to write in.
--
-- ADDITIVE ONLY, and confined to the `desktop` schema — same posture as
-- `20260807120000_desktop_schema.sql`. Nothing here touches `user_prompts`,
-- `profiles`, `handle_new_user`, or anything else the shipped iOS keyboard reads.
--
-- Why this column had to exist:
--
--   An English-mode user's rewrite came back in Japanese, and the request field that
--   selects the English system prompt (`RewriteRequest.writingLanguage`, AGENTS.md
--   §17) was not logged anywhere. Diagnosing it meant inferring the writing language
--   from `command_key` — noticing that `translateToEnglish` and `natural` are keys no
--   English preset pack contains — and then reading the account's `user_prompts` rows
--   by hand. The one field that would have answered the question directly was the one
--   field the event did not carry.
--
--   `locale` is not a substitute and never was: it is `Locale.current.identifier`,
--   the user's *system* region, so it says `ja_JP` for an English-mode user on a
--   Japanese Mac and `en_JP` for a Japanese-mode user on an English one.
--
-- Nullable with no default, and null is meaningful three ways: a build older than the
-- field, an explicit Japanese request from a build that collapsed `"ja"` to null, or a
-- blocked attempt logged before the language was read. `app_version` separates the
-- first from the rest.

alter table desktop.rewrite_events
  add column if not exists writing_language text;

-- Rewritten in full rather than patched: `create or replace function` has no partial
-- form, and the insert's column list and value list have to stay aligned. The only
-- change from `20260807120000_desktop_schema.sql` is `writing_language`.
create or replace function public.desktop_log_rewrite_event(p_event jsonb)
returns void
language sql
security definer
set search_path to 'public'
as $$
  insert into desktop.rewrite_events (
    id, user_id, command_key, prompt_origin, capture_mode, host_app_bundle_id,
    io_path, locale, writing_language, app_version, candidate_count, input_length,
    output_length, latency_ms, provider, model, status, input_text, output_text,
    consent_version
  )
  values (
    (p_event->>'id')::uuid,
    (p_event->>'user_id')::uuid,
    p_event->>'command_key',
    p_event->>'prompt_origin',
    p_event->>'capture_mode',
    p_event->>'host_app_bundle_id',
    p_event->>'io_path',
    p_event->>'locale',
    p_event->>'writing_language',
    p_event->>'app_version',
    coalesce((p_event->>'candidate_count')::integer, 0),
    (p_event->>'input_length')::integer,
    (p_event->>'output_length')::integer,
    (p_event->>'latency_ms')::integer,
    p_event->>'provider',
    p_event->>'model',
    coalesce(p_event->>'status', 'ok'),
    p_event->>'input_text',
    p_event->>'output_text',
    p_event->>'consent_version'
  )
  on conflict (id) do nothing;
$$;

-- `create or replace` preserves the existing grants, but re-revoking is cheap and
-- makes the guarantee local to this file: no desktop entry point is callable by
-- anon or authenticated, only by the service role the Edge Function runs as.
revoke execute on function public.desktop_log_rewrite_event(jsonb)
  from public, anon, authenticated;

-- Applied through the Supabase MCP `apply_migration` on 2026-08-19 and recorded in the
-- shared project's history as version `20260819050128`, which is why this file is named
-- for that number rather than for the hour it was written. `20260807120000_desktop_schema.sql`
-- beside it does *not* match its own recorded version (`20260807065039`) — the same
-- mismatch, left as it was found. AGENTS.md §12 still carries the open recommendation
-- that desktop migration files should live in `../Japanese/supabase/migrations/` instead,
-- one project and one history; that has not been adopted for either file.
