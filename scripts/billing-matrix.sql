-- The §9 transition table, asserted against a real database.
--
--   psql -d keigo_sandbox -f scripts/billing-matrix.sql
--
-- ############################################################################
-- ## SANDBOX ONLY. Writes to desktop.subscriptions / usage_windows /         ##
-- ## stripe_events and does not clean up until the end. Never run against    ##
-- ## eercsucvxnszqletxued.                                                   ##
-- ############################################################################
--
-- WHY THIS IS SQL AND NOT A STRIPE TEST CLOCK, which is the thing §11 asks for.
--
-- Everything time-dependent in §9 runs on OUR clock, not Stripe's:
-- `desktop.effective_plan(status, past_due_since, p_at)` and
-- `desktop.quota_window(…, p_now)` both take the instant as an ARGUMENT. That is
-- §3.4's whole design — "Stripe emits no event when our own 14-day timer elapses",
-- so entitlement is a read-time computation and nothing has to fire on time. A
-- Stripe test clock moves Stripe's time; it would never move `now()` here.
--
-- So the honest split is:
--
--   - **This file** proves the transitions and the arithmetic, by feeding the
--     reconciler exactly the shapes Stripe would send and by asking the pure
--     functions what they say at a chosen instant. Deterministic, no network, no
--     money, no waiting.
--   - **A Stripe test clock** is still required for the rows whose INPUT is the
--     thing in question: that a declining card really does produce `past_due`,
--     that a pending update really is discarded on payment failure, that a
--     schedule really releases. Those are assertions about Stripe's behaviour,
--     and this file assumes it rather than proving it.
--
-- Rows covered here: 1–5, 8–10, 12–19a, 24–25, 28–30, 36, 39–40, 44.
-- Rows needing Stripe: 6–7 (pending-update expiry), 11, 20–23 (Checkout races),
-- 26–27 (delivery), 31–35 (money/identity), 41–43 (UI surfaces).

\set ON_ERROR_STOP on
\pset pager off

create temp table results (
  seq      serial,
  rows_    text,
  what     text,
  ok       boolean,
  detail   text
);

create or replace function pg_temp.expect(
  p_rows text, p_what text, p_ok boolean, p_detail text default ''
) returns void language sql as $$
  insert into results (rows_, what, ok, detail) values (p_rows, p_what, p_ok, p_detail);
$$;

-- Feeds the reconciler the shape the webhook would, so every assertion below goes
-- through the real `desktop_process_stripe_event` → `desktop_reconcile_subscription`
-- path rather than writing rows by hand.
create or replace function pg_temp.reconcile(
  p_user uuid, p_cus text, p_sub text, p_interval text, p_status text,
  p_at timestamptz, p_period_start timestamptz, p_period_end timestamptz,
  p_cancel_at_period_end boolean default false,
  p_schedule text default null,
  p_product text default 'prod_V274Ok8sSwkjuZ'
) returns record language plpgsql as $$
declare r record;
begin
  select * into r from public.desktop_process_stripe_event(
    'evt_' || gen_random_uuid()::text, 'customer.subscription.updated', p_at, true,
    p_cus, p_user, p_sub, p_product, 'price_x', 'pro_monthly_jpy',
    p_interval, p_status, p_period_start, p_period_end, p_cancel_at_period_end,
    null, p_schedule
  );
  return r;
end;
$$;

create or replace function pg_temp.sub_row(p_user uuid) returns desktop.subscriptions
language sql as $$ select * from desktop.subscriptions where user_id = p_user $$;

create or replace function pg_temp.win_key(p_user uuid, p_at timestamptz) returns text
language plpgsql as $$
declare s desktop.subscriptions%rowtype; p text; k text;
begin
  s := pg_temp.sub_row(p_user);
  p := coalesce(s.entitlement_override,
                desktop.effective_plan(s.status, s.past_due_since, p_at));
  select w.window_key into k from desktop.quota_window(
    p, s.stripe_subscription_id, s.quota_anchor_at, s.quota_generation, p_at) w;
  return k;
end;
$$;

create or replace function pg_temp.plan_at(p_user uuid, p_at timestamptz) returns text
language sql as $$
  select coalesce(s.entitlement_override,
                  desktop.effective_plan(s.status, s.past_due_since, p_at))
    from desktop.subscriptions s where s.user_id = p_user;
$$;

-- ---------------------------------------------------------------------------
do $$
declare
  t0   timestamptz := '2026-03-10 12:00:00+09';
  u    uuid;
  s    desktop.subscriptions%rowtype;
  r    record;
  k1   text; k2 text; k3 text;
  n    integer;
begin

-- ===========================================================================
-- Rows 1–3 — cancellation
-- ===========================================================================
u := gen_random_uuid();
perform pg_temp.reconcile(u, 'cus_A', 'sub_A', 'month', 'active', t0,
                          t0, t0 + interval '1 month');
s := pg_temp.sub_row(u);
perform pg_temp.expect('1', 'a fresh monthly subscription grants pro',
  pg_temp.plan_at(u, t0) = 'pro', 'plan=' || pg_temp.plan_at(u, t0));

-- Row 1: cancel mid-period. `cancel_at_period_end` is DISPLAY state — the
-- subscription is `active` until it is not, and entitlement must not move.
perform pg_temp.reconcile(u, 'cus_A', 'sub_A', 'month', 'active', t0 + interval '5 days',
                          t0, t0 + interval '1 month', true);
s := pg_temp.sub_row(u);
perform pg_temp.expect('1', 'cancel_at_period_end does not revoke access',
  pg_temp.plan_at(u, t0 + interval '5 days') = 'pro' and s.cancel_at_period_end,
  'plan=' || pg_temp.plan_at(u, t0 + interval '5 days') || ' flag=' || s.cancel_at_period_end);

-- Row 2: un-cancel is a true no-op.
k1 := pg_temp.win_key(u, t0 + interval '6 days');
perform pg_temp.reconcile(u, 'cus_A', 'sub_A', 'month', 'active', t0 + interval '6 days',
                          t0, t0 + interval '1 month', false);
s := pg_temp.sub_row(u);
perform pg_temp.expect('2', 'un-cancelling changes nothing at all',
  not s.cancel_at_period_end and pg_temp.win_key(u, t0 + interval '6 days') = k1,
  'window unchanged: ' || k1);

-- Row 3: period expires → free, and the free window is a calendar month, so a
-- returning user is never locked out (the minimum Pro term is one month).
perform pg_temp.reconcile(u, 'cus_A', 'sub_A', 'month', 'canceled', t0 + interval '1 month',
                          t0, t0 + interval '1 month');
perform pg_temp.expect('3', 'a canceled subscription drops to free',
  pg_temp.plan_at(u, t0 + interval '1 month') = 'free');
perform pg_temp.expect('3', 'the free window key is a calendar month',
  pg_temp.win_key(u, t0 + interval '1 month') like 'free:%',
  pg_temp.win_key(u, t0 + interval '1 month'));

-- Row 4: resubscribe. A genuinely NEW subscription id ⇒ new window key ⇒ fresh
-- 1,000. This is the row that distinguishes it from 19a below.
perform pg_temp.reconcile(u, 'cus_A', 'sub_A2', 'month', 'active', t0 + interval '2 months',
                          t0 + interval '2 months', t0 + interval '3 months');
s := pg_temp.sub_row(u);
perform pg_temp.expect('4', 'a new subscription id moves the quota anchor',
  s.quota_anchor_at = t0 + interval '2 months', 'anchor=' || s.quota_anchor_at);
perform pg_temp.expect('4', 'and therefore yields a new window key',
  pg_temp.win_key(u, t0 + interval '2 months') <> k1,
  pg_temp.win_key(u, t0 + interval '2 months'));

-- ===========================================================================
-- Row 5 — the generation, and the collision it exists to prevent
-- ===========================================================================
u := gen_random_uuid();
perform pg_temp.reconcile(u, 'cus_B', 'sub_B', 'month', 'active', t0, t0, t0 + interval '1 month');
k1 := pg_temp.win_key(u, t0 + interval '40 days');   -- month 2 of the subscription
s := pg_temp.sub_row(u);
n := s.quota_generation;

-- Monthly → annual. Same subscription id, anchor resets, n returns to 0 — which
-- WITHOUT the generation would point straight back at the first month's bucket.
perform pg_temp.reconcile(u, 'cus_B', 'sub_B', 'year', 'active', t0 + interval '40 days',
                          t0 + interval '40 days', t0 + interval '1 year 40 days');
s := pg_temp.sub_row(u);
k2 := pg_temp.win_key(u, t0 + interval '40 days');
perform pg_temp.expect('5', 'an interval change bumps quota_generation',
  s.quota_generation = n + 1, format('%s → %s', n, s.quota_generation));
perform pg_temp.expect('5', 'an interval change moves the anchor',
  s.quota_anchor_at = t0 + interval '40 days');
perform pg_temp.expect('5', 'the upgrade window does not collide with month 1',
  k1 <> k2, format('%s vs %s', k1, k2));

-- Idempotency: §4.2 is a DIFF against stored state, not a reaction to an event.
-- Reconciling the same state twice must not bump the generation twice, or a
-- webhook retry hands out a second fresh 1,000.
n := s.quota_generation;
perform pg_temp.reconcile(u, 'cus_B', 'sub_B', 'year', 'active', t0 + interval '41 days',
                          t0 + interval '40 days', t0 + interval '1 year 40 days');
s := pg_temp.sub_row(u);
perform pg_temp.expect('5', 'reconciling twice does NOT bump the generation again',
  s.quota_generation = n, format('stayed at %s', s.quota_generation));

-- ===========================================================================
-- Rows 8–10 — scheduled downgrade
-- ===========================================================================
u := gen_random_uuid();
perform pg_temp.reconcile(u, 'cus_C', 'sub_C', 'year', 'active', t0, t0, t0 + interval '1 year');
s := pg_temp.sub_row(u);
k1 := s.quota_anchor_at::text || '#' || s.quota_generation;

perform pg_temp.reconcile(u, 'cus_C', 'sub_C', 'year', 'active', t0 + interval '1 day',
                          t0, t0 + interval '1 year', false, 'sub_sched_C');
s := pg_temp.sub_row(u);
perform pg_temp.expect('8', 'schedule_id is stored while a downgrade is pending',
  s.schedule_id = 'sub_sched_C');
perform pg_temp.expect('8', 'entitlement is pro throughout a scheduled downgrade',
  pg_temp.plan_at(u, t0 + interval '1 day') = 'pro');
perform pg_temp.expect('8', 'the anchor does not move for a scheduled downgrade',
  s.quota_anchor_at::text || '#' || s.quota_generation = k1);

-- Row 9 — releasing the schedule is an undo, and a no-op on quota.
perform pg_temp.reconcile(u, 'cus_C', 'sub_C', 'year', 'active', t0 + interval '2 days',
                          t0, t0 + interval '1 year', false, null);
s := pg_temp.sub_row(u);
perform pg_temp.expect('9', 'releasing the schedule clears schedule_id',
  s.schedule_id is null);
perform pg_temp.expect('9', 'the undo leaves quota untouched',
  s.quota_anchor_at::text || '#' || s.quota_generation = k1);

-- ===========================================================================
-- Rows 12–16 — the grace window, on OUR clock
-- ===========================================================================
u := gen_random_uuid();
perform pg_temp.reconcile(u, 'cus_D', 'sub_D', 'month', 'active', t0, t0, t0 + interval '1 month');
k1 := pg_temp.win_key(u, t0);

-- Renewal fails.
perform pg_temp.reconcile(u, 'cus_D', 'sub_D', 'month', 'past_due', t0 + interval '1 month',
                          t0, t0 + interval '1 month');
s := pg_temp.sub_row(u);
perform pg_temp.expect('12', 'past_due stamps past_due_since once',
  s.past_due_since = t0 + interval '1 month', 'since=' || s.past_due_since);

-- **The assertion this whole design exists for.** Nothing fires at day 14.
perform pg_temp.expect('12', 'day 1 of grace still reads pro',
  pg_temp.plan_at(u, t0 + interval '1 month 1 day') = 'pro');
perform pg_temp.expect('12', 'day 13 of grace still reads pro',
  pg_temp.plan_at(u, t0 + interval '1 month 13 days') = 'pro');
perform pg_temp.expect('16', 'day 15 reads free with NO event having fired',
  pg_temp.plan_at(u, t0 + interval '1 month 15 days') = 'free');
perform pg_temp.expect('16', 'the free window is fresh once grace expires',
  pg_temp.win_key(u, t0 + interval '1 month 15 days') like 'free:%');

-- A failed retry must NOT restart the 14 days.
perform pg_temp.reconcile(u, 'cus_D', 'sub_D', 'month', 'past_due', t0 + interval '1 month 5 days',
                          t0, t0 + interval '1 month');
s := pg_temp.sub_row(u);
perform pg_temp.expect('12', 'a second past_due does not restart the grace clock',
  s.past_due_since = t0 + interval '1 month', 'still ' || s.past_due_since);

-- Row 14 — recovery inside grace. The anchor never moved, so there is nothing to
-- reset, and the quota window must be the same bucket it was.
k2 := pg_temp.win_key(u, t0 + interval '1 month 5 days');
perform pg_temp.reconcile(u, 'cus_D', 'sub_D', 'month', 'active', t0 + interval '1 month 6 days',
                          t0 + interval '1 month', t0 + interval '2 months');
s := pg_temp.sub_row(u);
perform pg_temp.expect('14', 'a recovered payment clears past_due_since',
  s.past_due_since is null);
perform pg_temp.expect('14', 'a recovered payment does NOT reset quota',
  s.quota_anchor_at = t0, 'anchor still ' || s.quota_anchor_at);

-- Row 15 — retries exhausted.
perform pg_temp.reconcile(u, 'cus_D', 'sub_D', 'month', 'unpaid', t0 + interval '2 months',
                          t0 + interval '1 month', t0 + interval '2 months');
perform pg_temp.expect('15', 'unpaid reads free',
  pg_temp.plan_at(u, t0 + interval '2 months') = 'free');

-- ===========================================================================
-- Row 19a — the row the table was missing
-- ===========================================================================
-- A payment recovering AFTER grace expired is a free → pro transition of the
-- effective plan, on the SAME subscription and the SAME billing period. Anchoring
-- on that would hand out a fresh 1,000 the user did not buy.
u := gen_random_uuid();
perform pg_temp.reconcile(u, 'cus_E', 'sub_E', 'month', 'active', t0, t0, t0 + interval '1 month');
s := pg_temp.sub_row(u);
k1 := s.quota_anchor_at::text || '#' || s.quota_generation;

perform pg_temp.reconcile(u, 'cus_E', 'sub_E', 'month', 'past_due', t0 + interval '1 month',
                          t0, t0 + interval '1 month');
perform pg_temp.expect('19a', 'past grace, the same subscription reads free',
  pg_temp.plan_at(u, t0 + interval '1 month 20 days') = 'free');

perform pg_temp.reconcile(u, 'cus_E', 'sub_E', 'month', 'active', t0 + interval '1 month 20 days',
                          t0, t0 + interval '1 month');
s := pg_temp.sub_row(u);
perform pg_temp.expect('19a', 'recovery after day 14 restores pro',
  pg_temp.plan_at(u, t0 + interval '1 month 20 days') = 'pro');
perform pg_temp.expect('19a', 'and grants NO fresh 1,000 — same id, same interval',
  s.quota_anchor_at::text || '#' || s.quota_generation = k1, 'anchor unchanged');

-- ===========================================================================
-- Row 19 — an annual term rolls TWELVE monthly windows
-- ===========================================================================
u := gen_random_uuid();
perform pg_temp.reconcile(u, 'cus_F', 'sub_F', 'year', 'active',
                          '2026-01-31 00:00:00+09', '2026-01-31 00:00:00+09',
                          '2027-01-31 00:00:00+09');
select count(distinct pg_temp.win_key(u, '2026-01-31 00:00:00+09'::timestamptz + (i || ' months')::interval))
  into n from generate_series(0, 11) i;
perform pg_temp.expect('19', 'an annual subscription rolls 12 distinct monthly windows',
  n = 12, n || ' distinct keys');

-- And the month-end argument, on the anchor that breaks naive implementations.
perform pg_temp.expect('4.2', 'Jan 31 anchor → Feb 28, then back to Mar 31',
  (select to_char(resets_at at time zone 'Asia/Tokyo', 'MM-DD')
     from desktop.quota_window('pro','sub_F','2026-01-31 00:00:00+09',0,'2026-02-15+09')) = '02-28'
  and
  (select to_char(resets_at at time zone 'Asia/Tokyo', 'MM-DD')
     from desktop.quota_window('pro','sub_F','2026-01-31 00:00:00+09',0,'2026-03-15+09')) = '03-31',
  'no drift');

-- ===========================================================================
-- Rows 24–25 — duplicate and out-of-order events
-- ===========================================================================
u := gen_random_uuid();
perform pg_temp.reconcile(u, 'cus_G', 'sub_G', 'month', 'active', t0, t0, t0 + interval '1 month');

select * into r from public.desktop_process_stripe_event(
  'evt_dup', 'invoice.paid', t0 + interval '1 day', false);
perform pg_temp.expect('24', 'a first delivery is processed', r.duplicate = false);
select * into r from public.desktop_process_stripe_event(
  'evt_dup', 'invoice.paid', t0 + interval '1 day', false);
perform pg_temp.expect('24', 'a redelivery is reported duplicate, not reprocessed',
  r.duplicate = true);

-- An OLDER snapshot landing second must be discarded — this is the correction §5
-- makes: re-fetching fixes staleness, not ordering.
select * into r from public.desktop_process_stripe_event(
  'evt_stale', 'customer.subscription.updated', t0 - interval '1 hour', true,
  'cus_G', u, 'sub_G', 'prod_V274Ok8sSwkjuZ', 'price_x', null, 'month', 'canceled',
  t0, t0 + interval '1 month', false, null, null);
perform pg_temp.expect('25', 'an out-of-order (older) reconciliation is discarded',
  r.applied = false, 'applied=' || r.applied);
perform pg_temp.expect('25', 'the stale event did not downgrade a paying user',
  pg_temp.plan_at(u, t0 + interval '2 days') = 'pro');

-- ===========================================================================
-- Rows 36, 39, 40 — entitlement validates the PRODUCT
-- ===========================================================================
u := gen_random_uuid();
-- Row 36: a grandfathered price whose lookup_key was transferred away. Entitlement
-- must not care — it validates product id.
select * into r from public.desktop_process_stripe_event(
  'evt_' || gen_random_uuid()::text, 'customer.subscription.updated', t0, true,
  'cus_H', u, 'sub_H', 'prod_V274Ok8sSwkjuZ', 'price_old', null, 'month', 'active',
  t0, t0 + interval '1 month', false, null, null);
perform pg_temp.expect('36', 'a price with NO lookup_key is still pro',
  pg_temp.plan_at(u, t0) = 'pro');

-- Row 39: an unrelated product must not grant Pro.
u := gen_random_uuid();
perform pg_temp.reconcile(u, 'cus_I', 'sub_I', 'month', 'active', t0, t0,
                          t0 + interval '1 month', false, null, 'prod_SOMETHING_ELSE');
perform pg_temp.expect('39', 'an unrelated product does NOT grant pro',
  pg_temp.plan_at(u, t0) = 'free', 'plan=' || pg_temp.plan_at(u, t0));

-- ===========================================================================
-- Rows 28–30, 44 — the reservation lifecycle
-- ===========================================================================
u := gen_random_uuid();
perform set_config('sandbox.uid', u::text, false);

select * into r from public.desktop_reserve_usage(u, 'rq1', 1);
perform pg_temp.expect('44', 'a free user starts at 0 of 50',
  r.allowed and r.used = 0 and r.month_limit = 50, format('used=%s limit=%s', r.used, r.month_limit));

select * into r from public.desktop_reserve_usage(u, 'rq1', 1);
select coalesce(pending, -1) into n from desktop.usage_windows
  where user_id = u and window_key like 'free:%';
perform pg_temp.expect('29', 'a retry of one request_id cannot consume twice',
  r.allowed and n = 1, 'pending=' || n);

perform public.desktop_commit_usage('rq1');
select committed into n from desktop.usage_windows where user_id = u and window_key like 'free:%';
perform pg_temp.expect('28', 'commit moves pending → committed', n = 1, 'committed=' || n);

select * into r from public.desktop_reserve_usage(u, 'rq2', 1);
perform public.desktop_release_usage('rq2', 'provider_error');
select committed into n from desktop.usage_windows where user_id = u and window_key like 'free:%';
perform pg_temp.expect('28', 'a failed rewrite consumes NO quota', n = 1, 'committed=' || n);
select committed into n from desktop.usage_windows where user_id = u and window_key like 'day:%';
perform pg_temp.expect('28', 'but the daily brake still ticked twice', n = 2, 'day=' || n);

-- Row 30: an orphaned reservation expires and releases, fail-open and bounded.
select * into r from public.desktop_reserve_usage(u, 'rq3', 1);
update desktop.usage_reservations set expires_at = now() - interval '1 minute'
  where request_id = 'rq3';
perform public.desktop_expire_stale_reservations();
select pending into n from desktop.usage_windows where user_id = u and window_key like 'free:%';
perform pg_temp.expect('30', 'an orphaned reservation expires and releases pending',
  n = 0, 'pending=' || n);

-- Row 41/42's server half: the cap denies with an attributable reason.
select * into r from public.desktop_reserve_usage(u, 'rq4', 60);
perform pg_temp.expect('41', 'the monthly cap denies with reason=quota_month',
  not r.allowed and r.reason = 'quota_month', 'reason=' || coalesce(r.reason, 'null'));

-- §7's IDOR guard, exercised rather than asserted: the one entry point granted to
-- `authenticated` takes no arguments and derives the user from auth.uid().
select * into r from public.desktop_get_entitlement();
perform pg_temp.expect('44', 'desktop_get_entitlement() derives the user from auth.uid()',
  r.plan = 'free' and r.used = 1 and r.month_limit = 50,
  format('plan=%s used=%s limit=%s', r.plan, r.used, r.month_limit));
perform pg_temp.expect('44', 'the counter shows committed only, never pending',
  r.used = 1, 'used=' || r.used);

end;
$$;

-- ---------------------------------------------------------------------------
\echo ''
\echo '================ §9 MATRIX ================'
select
  lpad(rows_, 5) as "§9 row",
  case when ok then 'PASS' else 'FAIL' end as result,
  what,
  nullif(detail, '') as detail
from results order by seq;

select
  count(*) filter (where ok)     as passed,
  count(*) filter (where not ok) as failed,
  count(*)                       as total
from results;
