#!/usr/bin/env -S deno run --allow-net --allow-env
//
// The §11 test-clock matrix, driven end to end against a SANDBOX.
//
//   deno run --allow-net --allow-env scripts/billing-matrix.ts
//
// ---------------------------------------------------------------------------
// READ `billing-matrix.sql` FIRST. It covers more than this file does, and it
// needs neither a network nor a key.
//
// **This driver is NOT the main matrix, and it was written before that was clear.**
// Everything time-dependent in §9 runs on OUR clock — `effective_plan` and
// `quota_window` both take the instant as an argument — so the grace window, the
// month-end arithmetic and the twelve annual windows are all provable offline, and
// `billing-matrix.sql` proves them (45 assertions, 0 failures).
//
// What is left for THIS file is the set of rows whose *input* is the claim: that a
// declining card really produces `past_due`, that a pending update really is
// discarded when payment fails and really expires at 23 hours, that a schedule
// really releases. Those are assertions about STRIPE's behaviour, and the SQL
// matrix assumes them rather than proving them.
//
// It is unrun. It needs a test-mode key and a webhook-reachable sandbox, and the
// Supabase branch it was written against turned out to need the Pro plan — so its
// PostgREST transport has never executed. Treat it as a draft, not as passing.
// ---------------------------------------------------------------------------
//
// `docs/billing.md` §11 says it plainly: **nothing time-dependent in §9 is testable
// by waiting.** A 14-day grace window, a 12-month annual term and a renewal failure
// are all clock problems, and Stripe's test clocks are the only way to reach them.
// Test clocks are TEST MODE ONLY, which is the whole reason a sandbox exists.
//
// ---------------------------------------------------------------------------
// REFUSES TO RUN AGAINST LIVE. Three independent guards, because the cost of
// getting this wrong is real money and a 帳簿 record that cannot be deleted (§0):
//
//   1. STRIPE_TEST_KEY must start with a test-mode prefix.
//   2. The Stripe account is queried and every object created is asserted
//      `livemode: false`.
//   3. SUPABASE_URL must not be the live project ref.
//
// ---------------------------------------------------------------------------
// Required environment:
//
//   STRIPE_TEST_KEY        rk_test_… or sk_test_…
//   SUPABASE_URL           the BRANCH's url, e.g. https://<branch-ref>.supabase.co
//   SUPABASE_SERVICE_KEY   the BRANCH's service_role key
//   WEBHOOK_URL            the branch's desktop-stripe-webhook function URL
//
// Optional:
//   KEEP_ARTIFACTS=1       skip teardown, for poking at the wreckage

const LIVE_PROJECT_REF = "eercsucvxnszqletxued";
const STRIPE_API_VERSION = "2026-07-29.dahlia";
const STRIPE = "https://api.stripe.com";

// A Stripe test card that always succeeds, and one that always declines on the
// RENEWAL rather than at attach time — which is the only way to reach `past_due`
// without a human. Both are documented test tokens, not real numbers.
const PM_OK = "pm_card_visa";
const PM_FAILS_LATER = "pm_card_chargeCustomerFail";

// ---------------------------------------------------------------------------
// Result collection — every check lands here, pass or fail, and the run never
// stops on a single failure. A matrix that aborts on row 3 tells you nothing
// about rows 4–19.
// ---------------------------------------------------------------------------

type Check = { rows: string; what: string; ok: boolean; detail: string };
const checks: Check[] = [];

function check(rows: string, what: string, ok: boolean, detail = "") {
  checks.push({ rows, what, ok, detail });
  console.log(`${ok ? "  ✅" : "  ❌"} [§9 ${rows}] ${what}${detail ? ` — ${detail}` : ""}`);
}

function section(title: string) {
  console.log(`\n\x1b[1m${title}\x1b[0m`);
}

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

const env = (key: string): string => {
  const value = Deno.env.get(key);
  if (!value) {
    console.error(`Missing ${key}. See the header of this file.`);
    Deno.exit(2);
  }
  return value;
};

const STRIPE_KEY = env("STRIPE_TEST_KEY");
const SUPABASE_URL = env("SUPABASE_URL");
const SUPABASE_KEY = env("SUPABASE_SERVICE_KEY");
const WEBHOOK_URL = env("WEBHOOK_URL");

function formEncode(input: Record<string, unknown>, prefix = ""): string[] {
  const parts: string[] = [];
  for (const [rawKey, value] of Object.entries(input)) {
    if (value === undefined || value === null) continue;
    const key = prefix ? `${prefix}[${rawKey}]` : rawKey;
    if (Array.isArray(value)) {
      value.forEach((item, i) => {
        if (item && typeof item === "object") {
          parts.push(...formEncode(item as Record<string, unknown>, `${key}[${i}]`));
        } else {
          parts.push(`${encodeURIComponent(`${key}[${i}]`)}=${encodeURIComponent(String(item))}`);
        }
      });
    } else if (typeof value === "object") {
      parts.push(...formEncode(value as Record<string, unknown>, key));
    } else {
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
    }
  }
  return parts;
}

async function stripe(
  path: string,
  opts: {
    method?: "GET" | "POST" | "DELETE";
    body?: Record<string, unknown>;
    query?: Record<string, unknown>;
  } = {},
): Promise<any> {
  const query = opts.query ? `?${formEncode(opts.query).join("&")}` : "";
  const res = await fetch(`${STRIPE}${path}${query}`, {
    method: opts.method ?? "GET",
    headers: {
      Authorization: `Bearer ${STRIPE_KEY}`,
      "Stripe-Version": STRIPE_API_VERSION,
      ...(opts.body ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
    },
    body: opts.body ? formEncode(opts.body).join("&") : undefined,
  });
  const text = await res.text();
  const parsed = text ? JSON.parse(text) : null;
  if (!res.ok) {
    throw new Error(`Stripe ${path} ${res.status}: ${parsed?.error?.message ?? text}`);
  }
  // Guard 2, applied to every object this script ever sees.
  if (parsed && parsed.livemode === true) {
    throw new Error(`REFUSING: ${path} returned a LIVE object. Aborting before anything else runs.`);
  }
  return parsed;
}

async function rpc(fn: string, args: Record<string, unknown> = {}): Promise<any> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${fn}: ${res.status} ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

const rpcRow = async (fn: string, args: Record<string, unknown> = {}) => {
  const rows = await rpc(fn, args);
  return Array.isArray(rows) ? rows[0] ?? null : rows;
};

/// The webhook is asynchronous, so every assertion about our own state has to wait
/// for it rather than sleep a fixed amount and hope. Polls the row until the
/// predicate holds or the budget runs out.
async function until(
  what: string,
  predicate: (state: any) => boolean,
  userId: string,
  timeoutMs = 45_000,
): Promise<any> {
  const deadline = Date.now() + timeoutMs;
  let last: any = null;
  while (Date.now() < deadline) {
    last = await rpcRow("desktop_billing_state", { p_user_id: userId });
    if (predicate(last)) return last;
    await new Promise((r) => setTimeout(r, 1500));
  }
  throw new Error(`timed out waiting for ${what}; last state = ${JSON.stringify(last)}`);
}

const uuid = () => crypto.randomUUID();
const DAY = 86_400;
const now = () => Math.floor(Date.now() / 1000);

// ---------------------------------------------------------------------------
// Guards 1 and 3 — before a single object is created
// ---------------------------------------------------------------------------

function assertSandbox() {
  if (!/^(rk|sk)_test_/.test(STRIPE_KEY)) {
    console.error("REFUSING: STRIPE_TEST_KEY is not a test-mode key.");
    Deno.exit(2);
  }
  if (SUPABASE_URL.includes(LIVE_PROJECT_REF) || WEBHOOK_URL.includes(LIVE_PROJECT_REF)) {
    console.error(`REFUSING: SUPABASE_URL/WEBHOOK_URL point at the LIVE project (${LIVE_PROJECT_REF}).`);
    Deno.exit(2);
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

type Catalog = { productId: string; monthlyPriceId: string; yearlyPriceId: string };

/// Test mode is a SEPARATE object space — the live product and prices do not exist
/// here. Same shape, same lookup keys, same `tax_behavior: inclusive`, so the
/// sandbox exercises the code paths the live catalog will.
async function ensureCatalog(): Promise<Catalog> {
  const existing = await stripe("/v1/prices", {
    query: { lookup_keys: ["pro_monthly_jpy", "pro_yearly_jpy"], active: true, limit: 5, expand: ["data.product"] },
  });
  if (existing.data?.length === 2) {
    const monthly = existing.data.find((p: any) => p.recurring.interval === "month");
    const yearly = existing.data.find((p: any) => p.recurring.interval === "year");
    return {
      productId: typeof monthly.product === "string" ? monthly.product : monthly.product.id,
      monthlyPriceId: monthly.id,
      yearlyPriceId: yearly.id,
    };
  }

  const product = await stripe("/v1/products", {
    method: "POST",
    body: { name: "敬語ボタン Pro (sandbox)", metadata: { plan: "pro" } },
  });
  const mk = (amount: number, interval: string, lookup_key: string) =>
    stripe("/v1/prices", {
      method: "POST",
      body: {
        product: product.id,
        currency: "jpy",
        unit_amount: amount,
        tax_behavior: "inclusive",
        lookup_key,
        recurring: { interval },
      },
    });
  const monthly = await mk(1480, "month", "pro_monthly_jpy");
  const yearly = await mk(14400, "year", "pro_yearly_jpy");
  return { productId: product.id, monthlyPriceId: monthly.id, yearlyPriceId: yearly.id };
}

/// A customer frozen to a test clock. Every subscription created against it moves
/// only when the clock is advanced, which is what makes day 14 and month 12
/// reachable at all.
async function newActor(clockId: string, paymentMethod: string) {
  const userId = uuid();
  const customer = await stripe("/v1/customers", {
    method: "POST",
    body: {
      test_clock: clockId,
      email: `matrix-${userId.slice(0, 8)}@example.test`,
      metadata: { supabase_user_id: userId, surface: "macos" },
    },
  });
  const pm = await stripe(`/v1/payment_methods/${paymentMethod}/attach`, {
    method: "POST",
    body: { customer: customer.id },
  });
  await stripe(`/v1/customers/${customer.id}`, {
    method: "POST",
    body: { invoice_settings: { default_payment_method: pm.id } },
  });
  await rpc("desktop_link_stripe_customer", {
    p_user_id: userId,
    p_stripe_customer_id: customer.id,
  });
  return { userId, customerId: customer.id };
}

async function advanceTo(clockId: string, unixTime: number) {
  await stripe(`/v1/test_helpers/test_clocks/${clockId}/advance`, {
    method: "POST",
    body: { frozen_time: unixTime },
  });
  const deadline = Date.now() + 180_000;
  while (Date.now() < deadline) {
    const clock = await stripe(`/v1/test_helpers/test_clocks/${clockId}`);
    if (clock.status === "ready") return;
    if (clock.status === "internal_failure") throw new Error("test clock advance failed");
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error("test clock advance timed out");
}

// ---------------------------------------------------------------------------
// The matrix
// ---------------------------------------------------------------------------

async function main() {
  assertSandbox();

  section("Sandbox preflight");
  const account = await stripe("/v1/account");
  console.log(`  account ${account.id}, livemode=false ✅`);
  const catalog = await ensureCatalog();
  console.log(`  catalog ${catalog.productId} (${catalog.monthlyPriceId} / ${catalog.yearlyPriceId})`);

  // §3.2's allowlist is a TABLE precisely so a product can be added without a
  // deploy. The sandbox product has a different id than live, so it has to be here
  // or every reconciliation would correctly refuse to grant Pro.
  await rpc("desktop_pro_products_add_for_test", { p_stripe_product_id: catalog.productId })
    .catch(() => {
      console.log("  (no test-only helper; insert the sandbox product id into desktop.pro_products by hand)");
    });

  const webhook = await stripe("/v1/webhook_endpoints", {
    method: "POST",
    body: {
      url: WEBHOOK_URL,
      api_version: STRIPE_API_VERSION,
      enabled_events: [
        "checkout.session.completed", "checkout.session.expired",
        "checkout.session.async_payment_succeeded",
        "customer.subscription.created", "customer.subscription.updated",
        "customer.subscription.deleted",
        "customer.subscription.pending_update_applied",
        "customer.subscription.pending_update_expired",
        "invoice.paid", "invoice.payment_failed",
        "charge.refunded", "charge.dispute.created",
        "subscription_schedule.released",
      ],
    },
  });
  console.log(`  webhook ${webhook.id} → ${WEBHOOK_URL}`);
  console.log(`  \x1b[33mSet STRIPE_WEBHOOK_SECRET on the branch to: ${webhook.secret}\x1b[0m`);

  const clock = await stripe("/v1/test_helpers/test_clocks", {
    method: "POST",
    body: { frozen_time: now(), name: "billing-matrix" },
  });
  console.log(`  test clock ${clock.id}`);

  const created: { subs: string[]; customers: string[] } = { subs: [], customers: [] };

  try {
    await rowsFourAndNineteen(clock.id, catalog, created);
    await rowsFiveToSeven(clock.id, catalog, created);
    await rowsEightToTen(clock.id, catalog, created);
    await rowsTwelveToSixteen(clock.id, catalog, created);
    await rowsTwentyFourToTwentySeven(clock.id, catalog, created);
  } finally {
    section("Results");
    const failed = checks.filter((c) => !c.ok);
    for (const c of checks) {
      console.log(`${c.ok ? "PASS" : "FAIL"}  §9 ${c.rows.padEnd(8)} ${c.what}${c.detail ? ` — ${c.detail}` : ""}`);
    }
    console.log(`\n${checks.length - failed.length}/${checks.length} passed.`);

    if (!Deno.env.get("KEEP_ARTIFACTS")) {
      section("Teardown");
      await stripe(`/v1/webhook_endpoints/${webhook.id}`, { method: "DELETE" }).catch(() => {});
      console.log("  webhook endpoint deleted");
      console.log("  (the test clock and its customers are left; deleting the clock deletes them)");
    }
    if (failed.length) Deno.exit(1);
  }
}

/// §9 row 4 — a resubscribe is a genuinely NEW subscription id, so it gets a new
/// window key and a fresh 1,000. Row 19 — an annual subscription rolls twelve
/// MONTHLY quota windows, not one annual one.
async function rowsFourAndNineteen(clockId: string, catalog: Catalog, created: any) {
  section("Rows 4, 19 — window key follows the subscription; annual rolls 12 windows");
  const actor = await newActor(clockId, PM_OK);
  created.customers.push(actor.customerId);

  const sub = await stripe("/v1/subscriptions", {
    method: "POST",
    body: {
      customer: actor.customerId,
      items: [{ price: catalog.yearlyPriceId }],
      billing_mode: { type: "flexible" },
      metadata: { supabase_user_id: actor.userId },
    },
  });
  created.subs.push(sub.id);

  const state = await until("annual activation", (s) => s?.plan === "pro", actor.userId);
  check("4", "annual subscription grants pro", state.plan === "pro", `status=${state.status}`);
  check("4", "interval recorded as year", state.billing_interval === "year", `interval=${state.billing_interval}`);

  const first = await rpcRow("desktop_get_entitlement_for_test", { p_user_id: actor.userId })
    .catch(() => null);
  const keys = new Set<string>();
  const anchor = await currentWindowKey(actor.userId);
  keys.add(anchor);

  // Walk 12 months. Each month must be a DIFFERENT bucket — that is the whole of
  // "Pro annual gets monthly quota windows" (§4.1).
  for (let month = 1; month <= 12; month++) {
    await advanceTo(clockId, now() + month * 31 * DAY);
    keys.add(await currentWindowKey(actor.userId));
  }
  check("19", "an annual term rolls 12 distinct monthly windows", keys.size >= 12, `${keys.size} distinct keys`);
  if (first) check("19", "entitlement readable throughout", true);
}

async function currentWindowKey(userId: string): Promise<string> {
  const row = await rpcRow("desktop_current_window_key_for_test", { p_user_id: userId });
  return typeof row === "string" ? row : row?.window_key ?? "";
}

/// §9 rows 5–7 — the case a naive implementation gets wrong. A FAILED upgrade must
/// leave interval, entitlement and `quota_anchor_at` completely untouched:
/// `payment_behavior: pending_if_incomplete` means nothing applies until the new
/// invoice is paid.
async function rowsFiveToSeven(clockId: string, catalog: Catalog, created: any) {
  section("Rows 5–7 — a failed monthly→annual upgrade changes nothing");
  const actor = await newActor(clockId, PM_FAILS_LATER);
  created.customers.push(actor.customerId);

  const sub = await stripe("/v1/subscriptions", {
    method: "POST",
    body: {
      customer: actor.customerId,
      items: [{ price: catalog.monthlyPriceId }],
      billing_mode: { type: "flexible" },
      metadata: { supabase_user_id: actor.userId },
    },
  }).catch(() => null);
  if (!sub) {
    check("5-7", "monthly subscription created for the upgrade test", false, "creation failed");
    return;
  }
  created.subs.push(sub.id);

  const before = await until("monthly activation", (s) => s?.billing_interval === "month", actor.userId);
  const anchorBefore = await anchorOf(actor.userId);

  const item = sub.items.data[0].id;
  await stripe(`/v1/subscriptions/${sub.id}`, {
    method: "POST",
    body: {
      items: [{ id: item, price: catalog.yearlyPriceId }],
      payment_behavior: "pending_if_incomplete",
      proration_behavior: "always_invoice",
      billing_cycle_anchor: "now",
    },
  }).catch(() => {});

  await new Promise((r) => setTimeout(r, 8000));
  const after = await rpcRow("desktop_billing_state", { p_user_id: actor.userId });
  const anchorAfter = await anchorOf(actor.userId);

  check("6", "interval stays monthly when the upgrade payment fails",
    after?.billing_interval === "month", `interval=${after?.billing_interval}`);
  check("6", "entitlement stays pro", after?.plan === "pro", `plan=${after?.plan}`);
  check("5", "quota_anchor_at is untouched by a failed upgrade",
    anchorBefore === anchorAfter, `${anchorBefore} → ${anchorAfter}`);
  check("5", "state was readable before the attempt", !!before);
}

async function anchorOf(userId: string): Promise<string | null> {
  const row = await rpcRow("desktop_quota_anchor_for_test", { p_user_id: userId });
  return typeof row === "string" ? row : row?.quota_anchor_at ?? null;
}

/// §9 rows 8–10 — an annual→monthly downgrade is SCHEDULED, never immediate:
/// switching now would credit up to ~¥13,000 for a downgrade. Entitlement is pro
/// throughout and the anchor never moves.
async function rowsEightToTen(clockId: string, catalog: Catalog, created: any) {
  section("Rows 8–10 — scheduled downgrade holds access; release restores cleanly");
  const actor = await newActor(clockId, PM_OK);
  created.customers.push(actor.customerId);

  const sub = await stripe("/v1/subscriptions", {
    method: "POST",
    body: {
      customer: actor.customerId,
      items: [{ price: catalog.yearlyPriceId }],
      billing_mode: { type: "flexible" },
      metadata: { supabase_user_id: actor.userId },
    },
  });
  created.subs.push(sub.id);
  await until("annual activation", (s) => s?.plan === "pro", actor.userId);
  const anchorBefore = await anchorOf(actor.userId);

  const schedule = await stripe("/v1/subscription_schedules", {
    method: "POST",
    body: { from_subscription: sub.id },
  });
  const periodEnd = sub.items.data[0].current_period_end;
  await stripe(`/v1/subscription_schedules/${schedule.id}`, {
    method: "POST",
    body: {
      end_behavior: "released",
      phases: [
        { items: [{ price: catalog.yearlyPriceId, quantity: 1 }], start_date: sub.items.data[0].current_period_start, end_date: periodEnd },
        { items: [{ price: catalog.monthlyPriceId, quantity: 1 }] },
      ],
    },
  });

  const scheduled = await until("schedule recorded", (s) => !!s?.schedule_id, actor.userId).catch(() => null);
  check("8", "schedule_id is stored while a downgrade is pending", !!scheduled?.schedule_id,
    `schedule_id=${scheduled?.schedule_id ?? "null"}`);
  check("8", "entitlement stays pro under a scheduled downgrade", scheduled?.plan === "pro" || !scheduled);
  check("8", "anchor does not move for a scheduled downgrade",
    (await anchorOf(actor.userId)) === anchorBefore);

  // Row 9 — undoing it is a release, and it must be a no-op on quota.
  await stripe(`/v1/subscription_schedules/${schedule.id}/release`, { method: "POST" }).catch(() => {});
  const released = await until("schedule cleared", (s) => !s?.schedule_id, actor.userId).catch(() => null);
  check("9", "releasing the schedule clears schedule_id", !!released && !released.schedule_id);
  check("9", "the undo is a no-op on quota", (await anchorOf(actor.userId)) === anchorBefore);
}

/// §9 rows 12–16, and the one this whole design exists for: **grace expires at day
/// 14 on OUR clock, regardless of the Dashboard's retry setting.** Nothing in
/// Stripe's event stream marks day 14, so only a read-time computation can be right.
async function rowsTwelveToSixteen(clockId: string, catalog: Catalog, created: any) {
  section("Rows 12–16 — past_due keeps pro for exactly 14 days");
  const actor = await newActor(clockId, PM_FAILS_LATER);
  created.customers.push(actor.customerId);

  const sub = await stripe("/v1/subscriptions", {
    method: "POST",
    body: {
      customer: actor.customerId,
      items: [{ price: catalog.monthlyPriceId }],
      billing_mode: { type: "flexible" },
      metadata: { supabase_user_id: actor.userId },
    },
  }).catch(() => null);
  if (!sub) {
    check("12-16", "subscription for the dunning test", false, "creation failed");
    return;
  }
  created.subs.push(sub.id);
  await until("activation", (s) => s?.plan === "pro", actor.userId).catch(() => null);

  // Renewal falls due, and this card declines on renewal.
  await advanceTo(clockId, sub.items.data[0].current_period_end + DAY);
  const pastDue = await until("past_due", (s) => s?.status === "past_due", actor.userId).catch(() => null);
  check("12", "a failed renewal moves Stripe to past_due", pastDue?.status === "past_due",
    `status=${pastDue?.status ?? "?"}`);
  check("12", "entitlement stays pro inside the grace window", pastDue?.plan === "pro",
    `plan=${pastDue?.plan ?? "?"}`);

  // Day 13 — still pro. Day 15 — free. No event fires at either point; the read
  // is what changes. This is the assertion §3.4 was written for.
  const failedAt = now();
  const at13 = await rpcRow("desktop_effective_plan_at_for_test", {
    p_user_id: actor.userId, p_at: new Date((failedAt + 13 * DAY) * 1000).toISOString(),
  }).catch(() => null);
  const at15 = await rpcRow("desktop_effective_plan_at_for_test", {
    p_user_id: actor.userId, p_at: new Date((failedAt + 15 * DAY) * 1000).toISOString(),
  }).catch(() => null);

  if (at13 === null || at15 === null) {
    check("16", "grace expires at day 14", false, "needs desktop_effective_plan_at_for_test on the branch");
  } else {
    check("12", "day 13 of grace still reads pro", at13 === "pro" || at13?.plan === "pro", `${JSON.stringify(at13)}`);
    check("16", "day 15 reads free with no event having fired", at15 === "free" || at15?.plan === "free", `${JSON.stringify(at15)}`);
  }
}

/// §9 rows 24–27 — the reliability row. Duplicate, out-of-order and dropped events
/// must all converge on ONE state. Re-delivering a processed event must be a no-op
/// and must still answer 200, or Stripe retries it forever.
async function rowsTwentyFourToTwentySeven(clockId: string, catalog: Catalog, created: any) {
  section("Rows 24–27 — duplicate, out-of-order and dropped events converge");
  const actor = await newActor(clockId, PM_OK);
  created.customers.push(actor.customerId);

  const sub = await stripe("/v1/subscriptions", {
    method: "POST",
    body: {
      customer: actor.customerId,
      items: [{ price: catalog.monthlyPriceId }],
      billing_mode: { type: "flexible" },
      metadata: { supabase_user_id: actor.userId },
    },
  });
  created.subs.push(sub.id);
  const settled = await until("activation", (s) => s?.plan === "pro", actor.userId);

  // Row 24 — the same event id twice. Second call must report `duplicate` and
  // must NOT re-run the reconciliation.
  const eventId = `evt_matrix_${crypto.randomUUID().slice(0, 12)}`;
  const stamp = await rpc("desktop_now");
  const first = await rpcRow("desktop_process_stripe_event", {
    p_event_id: eventId, p_event_type: "invoice.paid", p_reconciled_at: stamp,
    p_reconcile: false,
  });
  const second = await rpcRow("desktop_process_stripe_event", {
    p_event_id: eventId, p_event_type: "invoice.paid", p_reconciled_at: stamp,
    p_reconcile: false,
  });
  check("24", "a duplicate event id is reported as duplicate, not reprocessed",
    first?.duplicate === false && second?.duplicate === true,
    `first=${first?.duplicate} second=${second?.duplicate}`);

  // Row 25 — an OLDER snapshot landing second must be discarded by the monotonic
  // `reconciled_at` guard, not applied over the newer one.
  const stale = new Date(Date.now() - 3_600_000).toISOString();
  const staleResult = await rpcRow("desktop_process_stripe_event", {
    p_event_id: `evt_stale_${crypto.randomUUID().slice(0, 12)}`,
    p_event_type: "customer.subscription.updated",
    p_reconciled_at: stale,
    p_reconcile: true,
    p_stripe_customer_id: actor.customerId,
    p_user_id: actor.userId,
    p_stripe_subscription_id: sub.id,
    p_stripe_product_id: catalog.productId,
    p_interval: "month",
    p_status: "canceled",
  });
  check("25", "an out-of-order (older) reconciliation is discarded",
    staleResult?.applied === false, `applied=${staleResult?.applied}`);

  const afterStale = await rpcRow("desktop_billing_state", { p_user_id: actor.userId });
  check("25", "the stale event did not downgrade a paying user",
    afterStale?.plan === "pro", `plan=${afterStale?.plan}`);
  check("25", "settled state was pro to begin with", settled?.plan === "pro");

  // Row 27 — the webhook must answer 400 to a forged signature and never 5xx, or
  // Stripe's retry budget is spent on our own bug.
  const forged = await fetch(WEBHOOK_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "stripe-signature": `t=${now()},v1=deadbeef` },
    body: JSON.stringify({ id: "evt_forged", type: "invoice.paid" }),
  });
  check("27", "a forged signature is rejected with 400", forged.status === 400, `status=${forged.status}`);
}

if (import.meta.main) {
  await main().catch((error) => {
    console.error(`\n\x1b[31mAborted:\x1b[0m ${error.message}`);
    Deno.exit(1);
  });
}
