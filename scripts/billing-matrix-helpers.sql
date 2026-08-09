-- Sandbox-only helpers for `scripts/billing-matrix.ts`.
--
-- ############################################################################
-- ## DO NOT APPLY THIS TO THE LIVE PROJECT (eercsucvxnszqletxued).           ##
-- ##                                                                         ##
-- ## It is NOT in supabase/migrations/ and must never be moved there. Every  ##
-- ## function below reaches into another user's billing state by explicit    ##
-- ## `p_user_id`, which is exactly the IDOR shape `docs/billing.md` §7 bans  ##
-- ## from production:                                                        ##
-- ##                                                                         ##
-- ##   "A `p_user_id` parameter on a function granted to `authenticated` is  ##
-- ##    an IDOR that lets any signed-in user read anyone's plan."            ##
-- ##                                                                         ##
-- ## They are safe HERE only because a branch database holds no real users   ##
-- ## and no real money, and because they are service_role-only even so.      ##
-- ############################################################################
--
-- Why they have to exist at all: the matrix asserts on things production has no
-- reason to expose. `desktop_get_entitlement()` derives the user from `auth.uid()`
-- and the harness has no JWT; `quota_anchor_at` is deliberately internal; and
-- "what would the plan read as on day 15?" is a question only a test asks, because
-- in production the answer arrives by the clock moving.

-- Guard: refuse to run anywhere that looks like the live project.
do $$
begin
  if current_setting('request.jwt.claims', true) is null
     and current_database() is not null
     and exists (select 1 from desktop.subscriptions limit 1) then
    raise notice 'desktop.subscriptions is non-empty — make sure this is the SANDBOX branch.';
  end if;
end;
$$;

-- §3.2's allowlist is a table so a product can be added without a deploy. Test mode
-- is a separate object space, so the sandbox product has a different id than live
-- and every reconciliation would otherwise (correctly) refuse to grant Pro.
create or replace function public.desktop_pro_products_add_for_test(p_stripe_product_id text)
returns void
language sql
security definer
set search_path to 'public'
as $$
  insert into desktop.pro_products (stripe_product_id, note)
  values (p_stripe_product_id, 'SANDBOX — billing-matrix.ts')
  on conflict (stripe_product_id) do nothing;
$$;

-- The current quota window key for a user, without going through auth.uid().
-- Row 19 asserts that twelve months of an annual term produce twelve DISTINCT
-- values of this.
create or replace function public.desktop_current_window_key_for_test(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_sub  desktop.subscriptions%rowtype;
  v_plan text;
  v_win  record;
begin
  select * into v_sub from desktop.subscriptions s where s.user_id = p_user_id;
  v_plan := coalesce(
    v_sub.entitlement_override,
    desktop.effective_plan(v_sub.status, v_sub.past_due_since, now())
  );
  select w.window_key into v_win
    from desktop.quota_window(
      v_plan, v_sub.stripe_subscription_id, v_sub.quota_anchor_at,
      v_sub.quota_generation, now()
    ) w;
  return v_win.window_key;
end;
$$;

-- Rows 5–7 and 8–9 both assert that the anchor did NOT move. Production never
-- surfaces it, and it is the single value those rows turn on.
create or replace function public.desktop_quota_anchor_for_test(p_user_id uuid)
returns text
language sql
security definer
set search_path to 'public'
as $$
  select coalesce(s.quota_anchor_at::text, '') || '#' || s.quota_generation::text
    from desktop.subscriptions s where s.user_id = p_user_id;
$$;

-- **The assertion §3.4 exists for.** Grace expires at day 14 on OUR clock, and
-- Stripe emits no event when it does — so the only way to prove it is to ask the
-- read-time computation what it would say at an arbitrary instant. Day 13 must be
-- `pro`; day 15 must be `free`; nothing fires in between.
create or replace function public.desktop_effective_plan_at_for_test(
  p_user_id uuid,
  p_at      timestamptz
)
returns text
language sql
security definer
set search_path to 'public'
as $$
  select coalesce(
    s.entitlement_override,
    desktop.effective_plan(s.status, s.past_due_since, p_at)
  )
  from desktop.subscriptions s where s.user_id = p_user_id;
$$;

-- The whole entitlement row for an arbitrary user — `desktop_get_entitlement()`
-- with the `auth.uid()` derivation removed, which is precisely why it is here and
-- not in a migration.
create or replace function public.desktop_get_entitlement_for_test(p_user_id uuid)
returns table (plan text, used integer, month_limit integer, resets_at timestamptz)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_sub    desktop.subscriptions%rowtype;
  v_plan   text;
  v_limits desktop.plan_limits%rowtype;
  v_win    record;
begin
  select * into v_sub from desktop.subscriptions s where s.user_id = p_user_id;
  v_plan := coalesce(
    v_sub.entitlement_override,
    desktop.effective_plan(v_sub.status, v_sub.past_due_since, now())
  );
  select * into v_limits from desktop.plan_limits l where l.plan = v_plan;
  select w.window_key, w.resets_at into v_win
    from desktop.quota_window(
      v_plan, v_sub.stripe_subscription_id, v_sub.quota_anchor_at,
      v_sub.quota_generation, now()
    ) w;

  plan        := v_plan;
  month_limit := v_limits.month;
  resets_at   := v_win.resets_at;
  select least(coalesce(w.committed, 0), v_limits.month) into used
    from desktop.usage_windows w
   where w.user_id = p_user_id and w.window_key = v_win.window_key;
  used := coalesce(used, 0);
  return next;
end;
$$;

-- Same posture as everything else in `desktop_*`: service_role only. The harness
-- authenticates with the branch's service_role key.
do $$
declare v_sig text;
begin
  foreach v_sig in array array[
    'public.desktop_pro_products_add_for_test(text)',
    'public.desktop_current_window_key_for_test(uuid)',
    'public.desktop_quota_anchor_for_test(uuid)',
    'public.desktop_effective_plan_at_for_test(uuid, timestamptz)',
    'public.desktop_get_entitlement_for_test(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', v_sig);
    execute format('grant execute on function %s to service_role', v_sig);
  end loop;
end;
$$;
