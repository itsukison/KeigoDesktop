-- Adds full attempt/instruction/lineage tracking to desktop.rewrite_events, and
-- removes the consent gate on raw text storage (decided 2026-09-18: no AI-consent
-- screen exists on desktop, the data is not sold or shared, and full capture is
-- needed for product improvement — see docs/private/ analysis from this date).
--
-- ADDITIVE ONLY, same posture as 20260807120000_desktop_schema.sql and
-- 20260819050128_desktop_rewrite_writing_language.sql. Nothing here touches
-- `user_prompts`, `profiles`, `handle_new_user`, or anything the shipped iOS
-- keyboard reads. No backfill: existing rows keep nulls in the new columns.
--
-- Why these six columns:
--
--   `command_key` only ever held the 4 raw builtin ids (natural/polite/email/
--   translateToEnglish) and goes null for everything else — custom instructions,
--   replies, regenerate, refine, and (found this session) some builds that logged
--   null regardless of what was pressed (v0.1.9 and the `smoke` tag: 100% null).
--   That made `command_key IS NULL` an unreliable proxy for "custom" and left no
--   way at all to recover which specific saved-button purpose was used, what a
--   free-typed instruction said, what a reply was responding to, or which prior
--   attempt a regenerate/refine followed.
--
--   `attempt_id` mirrors the UUID `RewriteAttempt.id` already sends to PostHog as
--   `attempt_id` (App/Analytics.swift) — lets a future analysis join this table to
--   PostHog's funnel/latency data without guessing.
--   `rewrite_type` is `RewriteType.rawValue` (saved_button/custom_instruction/
--   reply/regenerate/refine), already computed client-side, just not sent before.
--   `button_key` is the privacy-safe saved-button label already computed for
--   PostHog (e.g. "Shorten", "Client message") — richer than `command_key`.
--   `instruction_text` is `RewriteRequest.prompt` — the actual instruction sent to
--   the model on every path — redacted the same way input_text/output_text are.
--   `reply_source_text` is `RewriteRequest.replyTo` — the original message being
--   replied to, redacted the same way.
--   `previous_event_id` links a regenerate/refine row back to the attempt it
--   followed (populated from the client's already-tracked `page.eventId`), so
--   "what was the version they didn't like" is a one-hop lookup.

alter table desktop.rewrite_events
  add column if not exists attempt_id uuid,
  add column if not exists rewrite_type text,
  add column if not exists button_key text,
  add column if not exists instruction_text text,
  add column if not exists reply_source_text text,
  add column if not exists previous_event_id uuid references desktop.rewrite_events(id);

create index if not exists idx_desktop_rewrite_events_attempt_id
  on desktop.rewrite_events(attempt_id);

create index if not exists idx_desktop_rewrite_events_previous_event_id
  on desktop.rewrite_events(previous_event_id);

-- Rewritten in full rather than patched: `create or replace function` has no
-- partial form, and the insert's column list and value list have to stay
-- aligned. The only change from 20260819050128 is the six new columns.
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
    consent_version, attempt_id, rewrite_type, button_key, instruction_text,
    reply_source_text, previous_event_id
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
    p_event->>'consent_version',
    (p_event->>'attempt_id')::uuid,
    p_event->>'rewrite_type',
    p_event->>'button_key',
    p_event->>'instruction_text',
    p_event->>'reply_source_text',
    (p_event->>'previous_event_id')::uuid
  )
  on conflict (id) do nothing;
$$;

-- `create or replace` preserves the existing grants, but re-revoking is cheap and
-- makes the guarantee local to this file: no desktop entry point is callable by
-- anon or authenticated, only by the service role the Edge Function runs as.
revoke execute on function public.desktop_log_rewrite_event(jsonb)
  from public, anon, authenticated;

-- Applied through the Supabase MCP `apply_migration` on 2026-09-18 and recorded
-- in the shared project's history as version `20260918211225`, which is why
-- this file is named for that number rather than for the hour it was authored
-- — same convention as `20260819050128_desktop_rewrite_writing_language.sql`.
