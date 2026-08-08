-- Desktop (macOS) schema for 敬語ボタン's laptop surface.
--
-- ADDITIVE ONLY. Nothing here references or alters `ai_rewrite_events`,
-- `ai_rewrite_usage_buckets`, `user_prompts`, `profiles`, `user_ai_consent`, or
-- any existing function, so it cannot affect the shipped iOS keyboard or its
-- users. Same posture as `20260728120000_web_rewrite_rate_limit.sql`.
--
-- Why the tables live in a `desktop` schema but every entry point lives in
-- `public`:
--
--   The data wants isolation — `ai_rewrite_events` is the keyboard's event log
--   and mixing a second surface into it makes every existing query on it
--   silently wrong. A separate schema gets that.
--
--   But PostgREST only serves schemas listed in the project's "Exposed schemas"
--   setting, which defaults to public/graphql_public/storage. Adding `desktop`
--   there would change the shared project's API surface — a change the iOS app
--   also lives behind. So instead the four callable entry points are
--   SECURITY DEFINER functions in `public`, prefixed `desktop_`, exactly the way
--   `public.bump_web_rewrite_usage` reaches `public.web_rewrite_usage`.
--
--   Net effect: no desktop table is reachable over the API at all. The Edge
--   Function calls functions; nothing else can reach the data.

create schema if not exists desktop;

revoke all on schema desktop from public, anon, authenticated;
grant usage on schema desktop to service_role;

-- ---------------------------------------------------------------------------
-- Tables. RLS enabled with no policies, so only the service role — which
-- bypasses RLS — reaches them, and only through the functions below.
-- ---------------------------------------------------------------------------

create table if not exists desktop.rewrite_events (
  id uuid primary key,
  user_id uuid not null,
  created_at timestamptz not null default now(),

  -- Request shape
  command_key text,
  prompt_origin text,
  capture_mode text not null,
  host_app_bundle_id text,
  -- 'ax' | 'clipboard'. The most useful column here: a rising clipboard rate for
  -- one bundle id means that app's AX tree changed (§7).
  io_path text,
  locale text,
  app_version text,

  -- Metadata, always stored
  candidate_count integer not null default 0,
  input_length integer,
  output_length integer,
  latency_ms integer,
  provider text,
  model text,
  status text not null default 'ok',

  -- Feedback, filled in by desktop_patch_rewrite_event
  selected_index integer,
  action text,
  accepted boolean,

  -- Opt-in only. Null unless the user has an explicit consent record; redacted
  -- through redact.ts before it ever gets here.
  input_text text,
  output_text text,
  consent_version text
);

create index if not exists rewrite_events_user_created_idx
  on desktop.rewrite_events (user_id, created_at desc);
create index if not exists rewrite_events_created_idx
  on desktop.rewrite_events (created_at desc);
-- Supports the io_path regression query without a full scan.
create index if not exists rewrite_events_bundle_io_idx
  on desktop.rewrite_events (host_app_bundle_id, io_path, created_at desc);

alter table desktop.rewrite_events enable row level security;

-- Usage buckets. Shape copied from web_rewrite_usage. The limits themselves live
-- in the Edge Function so caps can be retuned by redeploying it, no migration.
create table if not exists desktop.usage_buckets (
  user_id uuid not null,
  bucket_key text not null,
  units integer not null default 0,
  requests integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, bucket_key)
);

alter table desktop.usage_buckets enable row level security;

-- How desktop user counts stay honest. `profiles` holds both platforms' users, so
-- desktop MAU is counted from here (and from PostHog), never by counting profiles.
create table if not exists desktop.activations (
  user_id uuid primary key,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  app_version text
);

alter table desktop.activations enable row level security;

-- ---------------------------------------------------------------------------
-- Entry points, all in `public` so PostgREST can reach them without the shared
-- project's exposed-schema list changing.
-- ---------------------------------------------------------------------------

-- Atomically increments one bucket and returns its running totals. Plain SQL
-- rather than plpgsql on purpose: with `RETURNS TABLE (units, requests)` the
-- output names would collide with the table's own column names inside plpgsql.
create or replace function public.desktop_bump_usage(
  p_user_id uuid,
  p_bucket_key text,
  p_units integer
)
returns table (units integer, requests integer)
language sql
security definer
set search_path to 'public'
as $$
  insert into desktop.usage_buckets as b (user_id, bucket_key, units, requests, updated_at)
  values (p_user_id, p_bucket_key, p_units, 1, now())
  on conflict (user_id, bucket_key)
  do update set
    units = b.units + p_units,
    requests = b.requests + 1,
    updated_at = now()
  returning b.units, b.requests;
$$;

revoke execute on function public.desktop_bump_usage(uuid, text, integer)
  from public, anon, authenticated;

create or replace function public.desktop_log_rewrite_event(p_event jsonb)
returns void
language sql
security definer
set search_path to 'public'
as $$
  insert into desktop.rewrite_events (
    id, user_id, command_key, prompt_origin, capture_mode, host_app_bundle_id,
    io_path, locale, app_version, candidate_count, input_length, output_length,
    latency_ms, provider, model, status, input_text, output_text, consent_version
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

revoke execute on function public.desktop_log_rewrite_event(jsonb)
  from public, anon, authenticated;

-- Feedback. Scoped by user_id as well as id: the event id comes from the client,
-- so without that predicate one user could annotate another's event.
create or replace function public.desktop_patch_rewrite_event(
  p_event_id uuid,
  p_user_id uuid,
  p_action text default null,
  p_selected_index integer default null,
  p_latency_ms integer default null,
  p_accepted boolean default null
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  touched integer;
begin
  update desktop.rewrite_events e
  set
    action = coalesce(p_action, e.action),
    selected_index = coalesce(p_selected_index, e.selected_index),
    latency_ms = coalesce(p_latency_ms, e.latency_ms),
    accepted = coalesce(p_accepted, e.accepted)
  where e.id = p_event_id and e.user_id = p_user_id;

  get diagnostics touched = row_count;
  return touched > 0;
end;
$$;

revoke execute on function public.desktop_patch_rewrite_event(uuid, uuid, text, integer, integer, boolean)
  from public, anon, authenticated;

create or replace function public.desktop_record_activation(
  p_user_id uuid,
  p_app_version text
)
returns void
language sql
security definer
set search_path to 'public'
as $$
  insert into desktop.activations (user_id, app_version)
  values (p_user_id, p_app_version)
  on conflict (user_id)
  do update set last_seen_at = now(), app_version = excluded.app_version;
$$;

revoke execute on function public.desktop_record_activation(uuid, text)
  from public, anon, authenticated;

-- Best-effort GC; schedule via pg_cron alongside the other retention jobs.
--
-- Keyed on `updated_at`, NOT on `bucket_key`. Comparing the key as a string does
-- not work: keys are prefixed ('day:2026-08-07'), so 'd' sorts above any date
-- literal and the predicate is false for every row.
create or replace function public.desktop_delete_old_usage_buckets(retain_days integer default 7)
returns void
language sql
security definer
set search_path to 'public'
as $$
  delete from desktop.usage_buckets
  where updated_at < now() - make_interval(days => retain_days);
$$;

revoke execute on function public.desktop_delete_old_usage_buckets(integer)
  from public, anon, authenticated;
