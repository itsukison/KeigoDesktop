# Billing — 敬語ボタン Mac

**Read `AGENTS.md` and `docs/pricing.md` first.** `pricing.md` is the pricing
authority: what the plans cost and why. This file is the *mechanics* authority.

Its goal, stated as a test the design must pass:

> **For every combination of payment state, cancellation state, billing interval,
> quota state, retry, refund and resubscription, there is exactly one deterministic
> entitlement and quota outcome.** §9 is the table that has to stay true.

Status: **Everything is deployed and configured. The only thing left is a real
payment — no money has moved through this path yet.** 特商法 (§10) is still
launch-blocking and lives outside this repo.

| | State as of 2026-08-08 |
|---|---|
| Product `prod_V274Ok8sSwkjuZ` 敬語ボタン Pro | **live**, `metadata.plan=pro`, `statement_descriptor=KEIGO BUTTON` |
| `pro_monthly_jpy` `price_1U22r6CZmA6ItMhqL2dvxwui` | **live**, ¥1,480/month, `tax_behavior: inclusive` — re-read from the API 2026-08-08 |
| `pro_yearly_jpy` `price_1U22qkCZmA6ItMhqG9BcunGs` | **live**, ¥14,400/year, `tax_behavior: inclusive` — same |
| API version | **`2026-07-29.dahlia`** — pin this everywhere (§2) |
| Migration `20260808120000` + `…130000_desktop_billing_cron.sql` | **applied** (`desktop_billing`, `desktop_billing_cron`). The line above used to say otherwise |
| Migration `20260808140000_desktop_billing_entry_points.sql` | **applied.** 11 new entry points; §3.3a's intent race smoke-tested against a throwaway id and the rows cleaned up |
| Webhook endpoint `we_1U23a8CZmA6ItMhq4o5heJGB` | **live**, on **`2026-07-29.dahlia`**, all 13 events, pointed at `desktop-stripe-webhook` |
| Portal config `bpc_1T2o0tCZmA6ItMhqqxMAc8cY` | **done and correct**: `schedule_at_period_end.conditions` is **`shortening_interval` only** (§11's trap), cancel is `at_period_end` with `proration_behavior: none`, update is `always_invoice`, **no retention offer** |
| `desktop-checkout` **v2**, `desktop-portal` v1, `desktop-stripe-webhook` v1 | **deployed.** `verify_jwt` is `true`/`true`/**`false`** as intended; both authed functions 401 without a JWT and 200 on OPTIONS. v2's source was read back and carries `automatic_tax[enabled]=false` explicitly (§10) |
| `desktop-rewrite` **v6** reserve/commit/release (§6) | **deployed**, and the deployed source was read back — it carries `requestId`, the three-phase lifecycle and the attributable 429 |
| Client: plan pane, ホーム quota row, cap-hit surfaces, `requestId` | **written**; `xcodebuild` succeeds, 87 tests pass |
| Stripe Tax registration, `jp_trn` | **Deliberately absent.** Core7 is a 免税事業者 — see §10 |
| Function secrets | **set** 2026-08-08 |

**One portal setting worth a decision rather than a fix.**
`subscription_update.billing_cycle_anchor` is `unchanged`. §8's own E-UP recipe uses
`billing_cycle_anchor: 'now'`, because under `billing_mode: flexible` the anchor is
*never* automatically reset on an interval change (§2). `always_invoice` is set, so a
monthly → annual upgrade through the portal still invoices the proration
immediately — the user is not double-charged and nothing is broken. What differs is
that the annual term is measured from the old monthly anchor rather than from the day
they upgraded. Quota is unaffected either way: §4.2 keys the anchor move on the
`interval` diff, not on how Stripe set its own.

**Why there is a fourth migration.** `20260808120000` created
`desktop.checkout_intents`, `desktop.stripe_events` and `desktop.billing_alerts` and
then gave two of them no entry point. `desktop` is deliberately not an exposed
schema (§6 of `AGENTS.md`), so a table with no `public.desktop_*` wrapper is a table
an Edge Function cannot reach at all — `desktop-checkout` and the webhook were
unbuildable as the schema stood. `…140000` adds the wrappers, plus
`desktop_process_stripe_event`, which is the one place §5's design had to bend: see
the note in §5.

Three corrections were made to this document on the way: the Pro window key gained a
`quota_generation` (§4.4), entitlement became a read-time computation rather than a
stored column (§3.4), and the quota anchor now keys on the subscription id rather than
on a `free → pro` plan transition (§4.2, §9 row 19a). The first two were raised in
review; the third fell out of fixing them.

Where this file disagrees with `pricing.md` §7 (calendar-month quota for both
tiers) or §8, this file wins — both were written before the state machine existed.
§10 lists what that obligates.

Stripe behaviour and Japanese law are sourced inline. Unsourced claims carry
**【推測】**.

---

## 0. What has already happened

Live account `acct_1T2WK5CZmA6ItMhq` (PromptOS), audited and cleared 2026-08-08.

| | Before | Action | After |
|---|---|---|---|
| Products | 2 (`Pro`, `Power`) | `active: false` | 0 active |
| Prices | 16, no `lookup_key`, `tax_behavior: unspecified` | `active: false` ×16 | 0 active |
| Webhook | 1 → `fedzebrojuvixsiajjef` (wrong project) | `disabled` | none live |

**Not deleted, deliberately:** customer `cus_U0oRVlmuSmnwrY`, invoice
`HSDYUSLF-0001`, charge `ch_3T2mpbCZmA6ItMhq0c8O54Sj` — **¥980, captured, paid, not
refunded**, to `itsukison00@gmail.com`. Commercially it is the owner's own
self-test; legally it is a settled live payment and a 帳簿 record. Deleting the
customer is irreversible and buys nothing. If it should be reversed, refund it.

Prices are **never deletable**, only deactivated — hence §2's `lookup_key` rule.
Archiving a price leaves existing subscriptions running but **an archived price
cannot start a new subscription**
([manage-prices](https://docs.stripe.com/products-prices/manage-prices)), which is
the failure behind §9's resubscribe path.

---

## 1. The model

Four things are tracked, and conflating any two of them is how this goes wrong.

| | What it is | Moved by | Lives in |
|---|---|---|---|
| **Entitlement** | `free` or `pro` | Stripe state + our own clock | **computed** — `desktop.effective_plan(status, past_due_since, now())` |
| **Quota window** | which counter is current, and when it rolls | arithmetic from a stored anchor | derived — `desktop.usage_windows.window_key` |
| **Consumption** | rewrites *successfully delivered* in that window | the user | `usage_windows.committed` |
| **In-flight** | rewrites reserved but not yet delivered | the request lifecycle | `usage_windows.pending` |

Three rules follow, and everything else in this document is a consequence:

1. **The counter is plan-agnostic.** It counts rewrites. The plan only decides what
   number it is compared against.
2. **The quota window is computed, not stored.** Given an anchor and `now()`, the
   current window key is arithmetic. Nothing has to fire on time for a window to
   roll — see §4.3, which is why this survives a webhook outage.
3. **Only delivered rewrites consume quota.** Reserved ≠ consumed. §6.

---

## 2. Stripe catalog

**One product, two prices, resolved by `lookup_key`, validated by product ID.**

```
Product: "敬語ボタン Pro"
  metadata.plan = "pro"
  statement_descriptor = "KEIGO BUTTON"      ← ASCII; what JP cards show
```

| lookup_key | Amount | Interval | tax_behavior |
|---|---|---|---|
| `pro_monthly_jpy` | ¥1,480 | `month` | `inclusive` |
| `pro_yearly_jpy` | ¥14,400 | `year` | `inclusive` |

**Both prices on the same Product.** Not stylistic: the Customer Portal *"can only
downgrade at the end of the billing period between prices with the same product"*
([configure-portal](https://docs.stripe.com/customer-management/configure-portal)).
Two products makes E-DOWN unbuildable.

**`lookup_key` finds the price to *sell*. It must never be the entitlement check.**
`transfer_lookup_key: true` **removes the key from the old price**, so a
grandfathered subscriber's price has no lookup key at all and a lookup-key-based
entitlement check would silently demote every legacy customer on the day of a price
change. Entitlement validates **product ID** (§3.2).

Prices are immutable — a price change is a new price object, and existing
subscribers are grandfathered by construction. `tax_behavior` is **immutable after
creation** (*"Once specified as either `inclusive` or `exclusive`, it cannot be
changed"* — [prices/object](https://docs.stripe.com/api/prices/object)); §8 has why
`inclusive` is legally required.

The 「最初の100名は初年度 ¥9,800」 cohort discount is a **promotion code** with
`duration: once` against `pro_yearly_jpy`, never a third price.

### API version — pinned, not inherited

**Pin an explicit API version** in the SDK/fetch layer *and* on the webhook
endpoint, and record the exact string in `supabase/config.toml`. Three reasons this
is not optional here:

- `billing_mode: flexible` in Checkout requires **≥ `2025-06-30.basil`**.
- `current_period_start/end` moved off the subscription object in
  **`2025-03-31.basil`** (§7).
- A webhook endpoint keeps the version it was created with, indefinitely. The dead
  PromptOS endpoint was on `2026-01-28.clover`. An endpoint and an API client on
  different versions disagree about where the period lives — which is exactly the
  bug §5 avoids by never reading the period off a webhook payload.

【推測】 The current version at implementation time is not knowable from here.
Read it off the Dashboard, pin it, write it down.

### `billing_mode: flexible`, and the trap

Use it: Stripe recommends it, and it computes credit prorations from the amount
**originally debited**. **The migration is one-way**
([billing-mode](https://docs.stripe.com/billing/subscriptions/billing-mode)).

It **reverses** the anchor behaviour on an interval change:

| | Classic | Flexible |
|---|---|---|
| Switching monthly ↔ annual | anchor *"is automatically reset"* | anchor ***"is never automatically reset"*** |

([compare](https://docs.stripe.com/billing/subscriptions/billing-mode/compare)) —
and *"if your subscription uses `billing_mode[type]=flexible`, resetting the billing
cycle anchor to `now` doesn't automatically generate a new invoice. To trigger an
invoice on a BCA reset, you must also set `proration_behavior` to `always_invoice`"*
([billing-cycle](https://docs.stripe.com/billing/subscriptions/billing-cycle)).

So E-UP must pass **both** `billing_cycle_anchor: 'now'` and
`proration_behavior: 'always_invoice'` explicitly. Choosing flexible without knowing
this produces an annual subscription still billing on the old monthly anchor.

### Webhook events — nine

| Event | Role |
|---|---|
| `checkout.session.completed` | first activation; Stripe holds the redirect on it |
| `checkout.session.expired` | release the pending-checkout guard (§3.3) |
| `checkout.session.async_payment_succeeded` | required by Stripe's fulfillment guide |
| `customer.subscription.created` / `.updated` / `.deleted` | lifecycle |
| `invoice.paid` | **the canonical successful-payment signal** |
| `invoice.payment_failed` | dunning messaging only, never gating |
| `charge.refunded` | §8 — including refunds issued by hand in the Dashboard |

Plus `charge.dispute.created`, `customer.subscription.pending_update_applied` /
`_expired`, and `subscription_schedule.released` as operational signals.

**`invoice.paid`, not `invoice.payment_succeeded`** — it is the event Stripe's own
subscription guides use to provision (*"Continue to provision each month as you
receive `invoice.paid` events"*,
[build-subscriptions](https://docs.stripe.com/billing/subscriptions/build-subscriptions)).

**All of them run the same handler** (§5).

---

## 3. Entitlement

### 3.1 Status → plan

| Stripe `status` | `plan` | Note |
|---|---|---|
| *(no qualifying subscription)* | `free` | Absence is a valid state, never an error |
| `incomplete` | `free` | **Never grant on `incomplete`** — payment unconfirmed. Expires in 23 h |
| `incomplete_expired` | `free` | |
| `trialing` | `pro` | We ship no trial; map it rather than crash |
| `active` | `pro` | |
| `past_due` | `pro` **if within our own grace window** | §3.4 |
| `unpaid` | `free` | |
| `canceled` | `free` | Terminal, immutable |
| `paused` | `free` | Only reachable from a trial ending with no payment method |

Two traps:

**`cancel_at_period_end` never appears here.** It is display state. A subscription
scheduled to cancel is `active` until it is not.

**Never gate on `canceled_at`.** *"If the subscription was canceled with
`cancel_at_period_end`, `canceled_at` will reflect **the time of the most recent
update request**, not the end of the subscription period"*
([subscriptions/object](https://docs.stripe.com/api/subscriptions/object)).
`if (sub.canceled_at) revoke()` revokes a paying customer the instant they click
cancel — and in Japan that is a 特商法第14条①一 exposure, not only a bug.

### 3.2 Status alone is not sufficient — the subscription must be *ours*

A customer can hold more than one subscription. Granting Pro because *any*
subscription is `active` means an unrelated product grants access to this one.

**A subscription qualifies only if all three hold:**

1. `status` maps to `pro` in §3.1, **and**
2. it has exactly one item whose `price.product` is in `desktop.pro_products`, **and**
3. its `price.recurring.interval` is `month` or `year`

`desktop.pro_products(stripe_product_id)` is a one-row allowlist today. It is a
table rather than a constant so that a future product replacement is an `INSERT`
that grandfathers the old one, rather than a deploy that demotes everybody.

If more than one qualifying subscription exists — which §3.3 is designed to prevent
but cannot make impossible — take the one with the latest `created`, and **log a
duplicate-subscription alert**. Never sum them, never pick arbitrarily.

We persist `stripe_subscription_id`, `stripe_product_id`, `stripe_price_id`,
`price_lookup_key` (nullable, informational only) and `interval` so that a
grandfathered price stays identifiable after its lookup key is transferred away.

### 3.3 One subscription lifecycle per user

The naive "is there an active subscription?" check loses every race that matters.
Four defences, in order of how early they fire:

**a. A checkout intent row, taken before Stripe is called.**

```sql
create table desktop.checkout_intents (
  user_id            uuid primary key,          -- ← at most one open intent per user
  idempotency_key    text not null,
  stripe_session_id  text,
  price_lookup_key   text not null,
  created_at         timestamptz not null default now(),
  expires_at         timestamptz not null
);
```

`primary key (user_id)` is the lock. `desktop-checkout` does
`insert … on conflict (user_id) do nothing`; zero rows means an intent is already
open, in which case it **returns the existing session's URL** rather than creating a
second session. Double-click and two-tabs both resolve to one session.

**b. A Stripe idempotency key on the session creation itself**, derived from
`(user_id, price_lookup_key, intent.created_at)`. Two concurrent server requests
that both somehow get past (a) still create one session. Note Stripe idempotency
keys *"prune after 24 hours"* and error if the same key is reused with different
parameters — which is why the key includes the intent timestamp.

**c. Session expiry, short and explicit.** Checkout Sessions *"expire after 24
hours"* by default and `expires_at` accepts **30 minutes to 24 hours**
([how-checkout-works](https://docs.stripe.com/payments/checkout/how-checkout-works)).
Set **30 minutes**. An abandoned checkout then clears itself quickly instead of
blocking a retry for a day. On `checkout.session.expired`, delete the intent row.
On retry before expiry, reuse; on explicit user retry we may also call
[`/expire`](https://docs.stripe.com/api/checkout/sessions/expire) and open a fresh
one.

**d. A pre-flight state check.** Before creating any session: if a qualifying
subscription already exists in `active`/`trialing`/`past_due`, return the **Billing
Portal** URL instead. If one exists in `incomplete`, return that subscription's
existing payment URL — do not start a parallel one.

The intent row is deleted on `checkout.session.completed`, `.expired`, and by a GC
sweep for anything past `expires_at` (covering a dropped `.expired` event).

### 3.4 Payment failure — our policy, not a Dashboard setting

The Dashboard's retries-exhausted behaviour is a setting someone can change without
touching code, and Stripe does not document its default. **Define the grace window
in our own data so entitlement is deterministic regardless:**

```
plan = 'pro'  if status ∈ {active, trialing}
            or (status = 'past_due' and now() < past_due_since + grace_days)
     = 'free' otherwise
```

**That formula is evaluated on every read, not written into a column.** This is the
correction that makes §9 row 16 true. Entitlement was described above as living in
`desktop.subscriptions.plan`, reconciled by webhook — but **Stripe emits no event
when our own 14-day timer elapses.** Nothing in the Smart Retry stream marks day 14,
and the terminal `unpaid` transition fires on a *Dashboard* schedule that §3.4 exists
precisely to be independent of. A stored `plan` would therefore read `pro` at day 14,
day 20 and day 30, and only the nightly reconciliation would ever correct it — within
24 hours, not "exactly at day 14" as the transition table promises.

So `desktop_reserve_usage` and `desktop_get_entitlement` both call
`desktop.effective_plan(status, past_due_since, now())`. The `plan` column survives as
a reconciled convenience copy for analytics and is explicitly **not** the gate; it is
correct only as of `reconciled_at`.

`past_due_since` is stamped on the first reconciliation that sees `past_due` and
cleared on any reconciliation that sees `active`. `grace_days` = **14**, matching
Stripe's recommended Smart Retry policy of *"8 retries within 2 weeks"*
([smart-retries](https://docs.stripe.com/billing/revenue-recovery/smart-retries)).

Why grace at all, in one line: the dominant cause of a failed renewal is an expired
card, involuntary churn is **20–40% of total churn**
([Baremetrics](https://baremetrics.com/blog/dunning-management)), and 14 days of Pro
at the cap is ~¥300 of COGS.

Set the Dashboard's terminal action to **`unpaid`**, not `cancel`. Entitlement logic
is identical for both, so `cancel` buys nothing, while `unpaid` keeps the
subscription updatable — recovery is a payment rather than a re-signup, which also
sidesteps §0's archived-price hazard. Our 14-day rule revokes on schedule either
way, so a Dashboard change cannot alter user-visible behaviour.

**Authentication-required is not a decline.** A JP card hitting 3-D Secure surfaces
as an invoice needing customer action. It is handled like `past_due` — keep Pro,
show a banner, deep-link to the Billing Portal / hosted invoice page — and it is
listed separately in §9 because the *recovery* action differs: the user must
complete authentication, not replace a card.

**A recovered payment does not touch the quota window.** The anchor is unchanged
(§4), so there is nothing to reset. This falls out of the model rather than needing
a rule.

---

## 4. Quota windows

This reverses `pricing.md` §7. Its stated reason for calendar month —
「毎月1日にリセット」 is what users expect — was real; its cost was not priced in.
§4.4 has what changed.

### 4.1 The two window shapes

| Plan | Window | Key | Resets |
|---|---|---|---|
| **Free** | calendar month, **Asia/Tokyo** | `free:2026-09` | 1st, 00:00 JST |
| **Pro** (monthly *and* annual) | subscription month from the anchor | `pro:<sub_id>:<generation>:<n>` | anchor + n months |

**Pro annual gets monthly quota windows, not one annual window.** Subscribing on 20
August:

```
Aug 20 → Sep 20   1,000
Sep 20 → Oct 20   1,000
Oct 20 → Nov 20   1,000   … for all twelve months of the annual term
```

Free stays calendar-anchored because a free user **has no Stripe subscription** —
there is no anchor to hang a window on. The two tiers therefore genuinely reset on
different schedules, which is why:

> **The UI shows the computed next reset date. It never claims a fixed date.**
> 「10月20日にリセット」 for that user, 「10月1日にリセット」 for a free user.

`pricing.md` §1's 「毎月1日（暦月）」 row is wrong for Pro and must be corrected (§10).

### 4.2 The anchor, and month arithmetic

`desktop.subscriptions.quota_anchor_at timestamptz` is set at exactly two moments
and never otherwise:

| Moment | Set to |
|---|---|
| `stripe_subscription_id` **changes** (including null → value) | that subscription's `current_period_start` |
| `interval` **changes** (E-UP, E-DOWN) | the new `current_period_start`, **and `quota_generation += 1`** |

**Both conditions are diffs against stored state, not reactions to events**, and that
is load-bearing three times over:

- **It is what keeps §5 idempotent.** Reconciling twice must not bump the generation
  twice. `current_period_start` is stable within a period, so recomputing the anchor
  from it yields the same value and the `is distinct from` guard does nothing the
  second time. An event-triggered `generation += 1` would hand out a second fresh
  1,000 on every webhook retry.
- **It catches a portal-initiated interval change**, which never passes through our
  own E-UP call at all.
- **It fixes the case the table above got wrong.** The old first row said "Pro
  activation (`free → pro`)". A payment recovering *after* the 14-day grace expired is
  exactly a `free → pro` transition of the effective plan — same subscription, same
  billing period, quota already partly consumed. Anchoring on that hands the user a
  fresh 1,000 they did not buy. Keying on the *subscription id* instead makes
  resubscription (§9 row 4, genuinely new id) reset and recovery (§9 rows 14–16, same
  id) not, which is what both rows already say they want.

Corollary: the anchor, the generation and `stripe_subscription_id` are **retained
while the effective plan is `free`**. Clearing them on downgrade would make a later
recovery on the same Stripe subscription look like a brand-new one.

It is **stored, not derived from Stripe's `billing_cycle_anchor`.** Stripe documents
that field as sometimes resetting to the current period start, and that the reset
behaviour *"is only guaranteed for subscriptions created after June 2024"*
([cancel](https://docs.stripe.com/billing/subscriptions/cancel)). Quota must not
depend on a field with that much documented drift.

**The window index and its bounds:**

```
n            = the largest integer where anchor + n months <= now()
window_start = anchor + n months
resets_at    = anchor + (n+1) months
```

**Always computed from the anchor, never iteratively.** This is the whole of the
month-end correctness argument. Anchor 31 January:

| From anchor | Postgres | Correct? |
|---|---|---|
| `anchor + 1 month` | 2026-02-28 | ✅ clamped |
| `anchor + 2 months` | 2026-03-31 | ✅ **returns to the 31st** |

Iterating (`Feb 28 + 1 month` → `Mar 28`) drifts a day earlier every short month and
silently shortens the user's year. Postgres `+ interval` clamps and does not
accumulate — but only if every computation starts from the anchor. Stripe applies
the same logic to billing (`billing_cycle_anchor_config` *"automatically accounts
for short months and leap years"*), so billing and quota stay aligned.

**Anchor arithmetic runs in `Asia/Tokyo`**, as do the free/day/hour/minute keys.

### 4.3 Two live bugs this replaces

The current code builds keys from `new Date().toISOString()`
(`desktop-rewrite/index.ts:306`) — **UTC**:

1. **The daily brake already resets at 09:00 JST.** Live today. A calendar-month key
   would have made 「毎月1日にリセット」 happen at 09:00 on the 1st.
2. **The GC would have eaten a month bucket.** `desktop_delete_old_usage_buckets`
   defaults to `retain_days = 7` on `updated_at`; a monthly counter untouched for 8
   days would silently return to zero. `pricing.md` §8 says to extend the GC to
   collect month buckets — **the hazard is the reverse.** Retention must be ≥ 40
   days for `free:%` and `pro:%` keys. Matching a key *prefix* is safe; the existing
   comment warns only against comparing the key to a date literal.

**Why this model cannot be broken by a webhook outage** — the objection that kept
the old design: the window rolls by arithmetic on a stored anchor. If every webhook
stopped for a week, a paying user's window still rolls on time. Only the *anchor*
depends on Stripe, and it is written once at activation.

### 4.4 What the reversal buys

The calendar-month-for-Pro design had three costs, all now gone:

| | Calendar month for Pro | Subscription-anchored |
|---|---|---|
| **Straddle** — one monthly payment touching two windows (28 Aug → 28 Sep = ~2,000 rewrites) | `pricing.md` §6's 54.0% cap margin was really ~8% | **Exactly 1,000 per paid month.** §6's table becomes true |
| **Downgrade lockout** — Pro→Free mid-month at 800 used vs a 50 cap | median ~2 weeks of dead app for a churning user | **Structurally impossible.** The minimum Pro term is one month, so by the time a user returns to free the calendar month has always rolled and the `free:` window is fresh |
| **Reset date** | one claimed date, wrong for Pro | computed per user, always true |

The downgrade case deserves the emphasis: it needed a `quota_epoch` column and a
bespoke "increment iff plan changes" rule in the previous draft. **The bespoke rule is
deleted; the column is not, and claiming otherwise was this section's one real
error.** Anchoring the window to the subscription makes fresh-allowance-on-*downgrade*
fall out of the key derivation — the plan changes, so the key prefix changes from
`pro:` to `free:`. It does **not** do the same for fresh-window-on-*upgrade*, and the
difference is that E-UP keeps the same subscription id:

```
monthly, month 2 of the subscription      pro:sub_123:1     ← 800 rewrites in here
upgrade to annual: anchor := now(), n := 0
first window after the upgrade            pro:sub_123:0
first window of the FIRST month           pro:sub_123:0     ← the same bucket
```

The "fresh window" §9 row 5 promises resolves to a key the subscription's own first
month already filled, and §4.3's ≥ 40-day retention guarantees that bucket is still
there to be hit. `quota_generation` (§4.2) is what separates them:
`pro:sub_123:0:0` before, `pro:sub_123:1:0` after. It survives as an explicit integer
rather than as the anchor timestamp because two anchors *can* coincide — an upgrade
landing exactly on an old window boundary would collide again.

### 4.5 Showing the date is not decoration

The clearest finding in the research behind this document: the driver of billing
support tickets is **an invisible reset date**, not the lock itself. GitHub Copilot
runs calendar-month quotas over arbitrary billing anchors, documents it plainly, and
still carries a continuous stream of confused threads —
[#164643](https://github.com/orgs/community/discussions/164643),
[#164613](https://github.com/orgs/community/discussions/164613) and others, none
with a staff answer. Grammarly, which surfaces 「次回リフィルまであと N 日」 at the
block point, does not.

**`resets_at` is required on every cap-hit surface and on the ホーム usage row.**

---

## 5. Webhook processing

The previous draft claimed "re-fetch from Stripe makes ordering irrelevant." **That
is false**, and the correction is the sharpest one in this revision: two handlers
can each re-fetch and still write out of order — A fetches at t₁, B fetches at
t₂ > t₁, B's write lands first, A's older snapshot overwrites it. Re-fetching fixes
*staleness*, not *ordering*.

### The handler

```
1. verify signature
2. upsert desktop.stripe_events(event_id) → if already `processed`, return 200
                                            (row exists but unprocessed → continue)
3. resolve the customer id from the payload — the ONLY thing the payload is used for
4. BEGIN
5.   pg_advisory_xact_lock(hashtext(stripe_customer_id))    ← serialize per customer
6.   t := now()                                             ← Postgres clock, not ours
7.   fetch the customer's subscriptions from the Stripe API
8.   if t <= subscriptions.reconciled_at → COMMIT and return 200 (a newer
                                            reconciliation already won)
9.   compute entitlement (§3.1 + §3.2); read the period from items.data[0]
10.  upsert desktop.subscriptions, set reconciled_at = t
11.  mark the event processed
12. COMMIT
13. 200 — any failure above rolls back and returns 5xx so Stripe retries
```

Six properties, each answering a specific failure:

- **The event is marked processed only after the state is persisted, in the same
  transaction.** A handler that dies at step 9 leaves the event unprocessed and the
  row untouched; Stripe retries and it succeeds. Marking first — the previous
  draft's dedupe-then-work order — turns any mid-handler failure into permanent
  entitlement drift.
- **The advisory lock serializes per customer**, so steps 7–10 cannot interleave
  for one user. Different customers never contend.
- **`reconciled_at` is the belt-and-braces monotonic guard** (step 8), stamped from
  **Postgres `now()`** rather than the Edge Function's clock, which may be skewed.
  The lock alone would suffice within one database; the guard also covers a manual
  reconciliation or a backfill running concurrently.
- **The payload is a notification, not a source of truth**, which is Stripe's own
  advice — *"This data might already be stale by the time you process it, so we
  recommend retrieving the latest version of the resource from the API"*
  ([event-destinations](https://docs.stripe.com/event-destinations)). It also makes
  endpoint version pinning harmless (§2): we never read a field off the payload.
- **All nine events share this path**, so there are not nine chances to write a
  stale state.
- **Idempotent by construction** — recomputing from live Stripe state twice yields
  the same row.

**The lock is held across an HTTP call**, which is normally poor practice. It is
correct here because webhook volume is single-digit events per day and the fetch is
one round trip. **What would change it:** if per-customer event volume ever makes
lock hold time visible, move to fetch-then-lock and rely on `reconciled_at` alone.
Written down so the tradeoff is a decision rather than an accident.

### What was actually built — fetch-then-lock, for a transport reason

The implementation takes that alternative, and not for the reason above: **the shape
in the box is not expressible over PostgREST.** Each RPC is its own transaction and
the Stripe fetch happens in the Edge Function *between* them, so there is no
transaction for the lock to span. The steps run as:

```
1. verify signature
2. desktop_stripe_event_processed(id) → 200 if already done   (cheap early-out only)
3. resolve the customer id from the payload
4. fetch the customer's subscriptions from the Stripe API
5. t := desktop_now()                       ← Postgres clock, AFTER the fetch
6. desktop_process_stripe_event(…)          ← ONE transaction:
     insert the event row, re-check processed_at,
     desktop_reconcile_subscription (advisory lock + reconciled_at guard),
     set processed_at = now()
7. 200 — any failure rolls back and returns 5xx so Stripe retries
```

Two of §5's six properties are unchanged and they are the two that matter:

- **`reconciled_at` still discards the older snapshot.** It was always the thing
  doing the real work here; the lock only narrowed the window it had to cover.
  Stamping `t` *after* the fetch is what keeps it honest — taken before, a handler
  with a slow fetch would carry a timestamp older than the data it is guarding and
  could discard a fresher write.
- **The event is marked processed only after the state is persisted, in the same
  transaction.** `desktop_process_stripe_event` is one plpgsql function precisely so
  this survives. Marking first is the failure mode §5 named: any mid-handler death
  becomes permanent entitlement drift.

What is lost is the guarantee that two handlers for one customer cannot have
overlapping *fetches*. The consequence is bounded to a wasted fetch, because the
loser's write is rejected by the guard.

### Reconciliation, as a backstop and not an afterthought

A nightly job that, for every row: re-runs steps 5–11. Plus a targeted sweep of
`GET /v1/events?delivery_success=false` (Stripe retries for **up to 3 days** with
exponential backoff; Dashboard resend ≤ 15 days, CLI ≤ 30). Rows whose
`current_period_end` is in the past are reconciled first — that is the signature of
a dropped renewal event.

【推測】 Nightly is a starting cadence, not a derived one; there are zero
observations of webhook reliability on this account.

---

## 6. Quota consumption — reserve → execute → commit

The current code (`reserveUsage`, `index.ts:294`) **bumps then checks**, so a
rejected request consumes quota, and a request whose model call then fails consumes
a rewrite the user never saw. Both are wrong. Replace with a three-phase,
idempotent lifecycle.

### The contract

```
reserve(request_id, units)  →  allowed | denied(reason)     pending += units
    ↓ generation succeeds                                   pending -= units
commit(request_id)                                          committed += units
    ↓ generation fails / times out / provider error
release(request_id, reason)                                 pending -= units
```

**`request_id` is a client-generated UUID, unique per user intent**, sent on the
rewrite request and carried through all three calls. It is the idempotency key:

- `reserve` with a known `request_id` returns the **existing** reservation. A client
  retry of the same rewrite cannot consume twice.
- `commit` / `release` are idempotent and terminal — whichever lands first wins, and
  the second is a no-op.

### Admission

A request is admitted only if, for the quota window:

```
committed + pending + units <= limit
```

Counting `pending` in the admission test is what stops two concurrent requests both
passing at 999. Combined with the whole check running in one transaction, the race
is closed rather than narrowed.

### Quota counts successes. Brakes count attempts.

This distinction is load-bearing and easy to lose:

| Counter | Increments on | Released on failure? | Why |
|---|---|---|---|
| **Monthly quota** (50 / 1,000) | **commit** | **yes** | The user is paying for delivered rewrites. A provider outage must not bill them for it |
| **Daily brake** (20 / 100) | **reserve** | no | It is an abuse brake. If failures released it, a script that induces failures would never be braked |
| **Hour / minute brakes** (120 / 12) | **reserve** | no | Same |

So a failed rewrite costs the user nothing against the marketed allowance and still
costs them one tick against the anti-abuse ceiling. That is the correct asymmetry:
the marketed number is a promise, the brakes are a defence.

### Orphaned reservations

If the Edge Function dies between `reserve` and `commit`, `pending` is stranded.
Reservations carry `expires_at = created_at + 5 minutes` (a rewrite takes seconds),
and `desktop_expire_stale_reservations()` releases anything past it. The failure
mode is **fail-open in the user's favour and bounded**: a crash after generation but
before commit gives the user one free rewrite.

### Where the calls go

`reserve` is the existing pre-flight. **`commit` folds into the
`desktop_log_rewrite_event` call that already happens on success**, so the happy
path adds no round trip — reserve, generate, log-and-commit. `release` is a new call
on every failure branch, which is cheap because those branches already return early.

**Fail closed on the reserve.** The comment at `index.ts:290` is right and nothing
here changes it: an unmeasurable request is one we decline.

### Analytics

Blocked and failed attempts are recorded separately in `desktop.rewrite_events` with
the `reason` from `reserve` (`quota_month` / `brake_day` / `brake_hour` /
`brake_minute`) or the release reason (`provider_error` / `timeout` / `cancelled`).
`pricing.md` §8 instrumentation item 4 asks for exactly this — a 429 does not
distinguish a quota cap from an abuse brake today.

---

## 7. Schema

```sql
create table desktop.subscriptions (
  user_id                 uuid primary key,
  stripe_customer_id      text not null unique,
  stripe_subscription_id  text,
  stripe_product_id       text,          -- §3.2 — the entitlement check
  stripe_price_id         text,          -- survives a lookup_key transfer
  price_lookup_key        text,          -- informational only, may go null
  interval                text,          -- 'month' | 'year'
  plan                    text not null default 'free',
  status                  text,
  current_period_start    timestamptz,   -- from items.data[0], see below
  current_period_end      timestamptz,   -- from items.data[0], see below
  cancel_at_period_end    boolean not null default false,
  cancel_at               timestamptz,
  quota_anchor_at         timestamptz,   -- §4.2
  quota_generation        integer not null default 0,  -- §4.4, the E-UP collision
  past_due_since          timestamptz,   -- §3.4
  entitlement_override    text,          -- §8's deliberate support exception
  entitlement_override_note text,
  schedule_id             text,          -- set while a downgrade is scheduled
  reconciled_at           timestamptz,   -- §5 monotonic guard
  updated_at              timestamptz not null default now()
);

create table desktop.pro_products (stripe_product_id text primary key);

create table desktop.plan_limits (
  plan text primary key, month int, day int, hour int, minute int
);
-- free: 50 / 20 / 120 / 12      pro: 1000 / 100 / 120 / 12

create table desktop.usage_windows (
  user_id uuid, window_key text, committed int not null default 0,
  pending int not null default 0, updated_at timestamptz not null default now(),
  primary key (user_id, window_key)
);

create table desktop.usage_reservations (
  request_id text primary key, user_id uuid not null, units int not null,
  window_keys text[] not null, state text not null,   -- held | committed | released
  reason text, created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table desktop.checkout_intents (…);   -- §3.3
create table desktop.stripe_events (event_id text primary key, type text,
  received_at timestamptz, processed_at timestamptz);   -- §5
```

**`current_period_start/end` are not on the subscription object.** As of
`2025-03-31.basil`:

> *"The `current_period_start` and `current_period_end` fields are no longer
> available on the subscription resource. Instead, access the subscription item's
> billing periods directly using `items.data.current_period_end` and
> `items.data.current_period_start`."*
> — [changelog](https://docs.stripe.com/changelog/basil/2025-03-31/deprecate-subscription-current-period-start-and-end)

They moved because a subscription can hold mixed intervals. Ours never will — one
item, one price — so `items.data[0]` is unambiguous, but reading
`sub.current_period_end` returns `undefined` and writes a null period, which
silently breaks the 解約予定 display and §5's reconciliation priority.

Both dates are stored, not just the end, because §4.2's anchor arithmetic and §9's
transitions need to place `now()` within a period, not just know when it ends.

`plan_limits` is data rather than env vars so `pricing.md` §7's lever 2 (cut the
free cap to 30) is an `UPDATE`, and — more importantly — so the limit can
participate in §6's atomic admission test.

Per `AGENTS.md` §12 the migration lands in the **iOS repo** (one project, one
history).

### Entry points

| Function | Grant | Does |
|---|---|---|
| `desktop_reserve_usage(user_id, request_id, units)` | `service_role` | §6 admission, all four windows, one transaction. Returns `(allowed, reason, plan, used, limit, resets_at)` |
| `desktop_commit_usage(request_id)` | `service_role` | idempotent |
| `desktop_release_usage(request_id, reason)` | `service_role` | idempotent |
| `desktop_expire_stale_reservations()` | `service_role` | pg_cron |
| `desktop_reconcile_subscription(customer_id, …)` | `service_role` | §5 steps 5–11 |
| **`desktop_get_entitlement()`** | **`authenticated`** | plan, used, limit, **`resets_at`**, `cancel_at_period_end`, `current_period_end`, `status`, `interval` |

**`desktop_get_entitlement()` takes no arguments** and derives the user from
`auth.uid()`. A `p_user_id` parameter on a function granted to `authenticated` is an
IDOR that lets any signed-in user read anyone's plan. It is the first `desktop_*`
entry point that is not `service_role`-only, so the migration's
`has_function_privilege` assertions must be re-verified, not copied.

### Edge Functions

`desktop-checkout` (§3.3's four defences; price resolved by `lookup_key`
**server-side** — `prompt/src/ipc/billing-handlers.js` takes `priceId` from the
client and must not be copied), `desktop-portal`, `desktop-stripe-webhook`.

Signature verification: HMAC-SHA256 over `"{timestamp}.{raw_body}"`, **raw body**,
constant-time compare, **ignore all schemes but `v1`** (*"to prevent downgrade
attacks"*), never tolerance 0. Return 2xx *"prior to any complex logic that could
cause a timeout"*; 3xx counts as failure, so point the endpoint at the resolved URL.

---

## 8. Plan changes, refunds, and account deletion

### E-UP — Monthly → Annual, payment-safe

```
subscriptions.update(sub_id, {
  items: [{ id: item_id, price: annual_price_id }],
  payment_behavior:   'pending_if_incomplete',   ← nothing applies until payment succeeds
  proration_behavior: 'always_invoice',
  billing_cycle_anchor: 'now',                   ← required under flexible (§2)
})
```

*"With the pending updates feature, you can make changes to subscriptions only if
payment succeeds on the new invoice"*
([pending-updates](https://docs.stripe.com/billing/subscriptions/pending-updates)).
All four parameters are on the supported-attributes list for pending updates, and
`charge_automatically` + card/Apple Pay/Link satisfies its preconditions.

**Never grant the annual state, and never move `quota_anchor_at`, before
`customer.subscription.pending_update_applied` (or the reconciliation that sees the
new price).** On failure the subscription is unchanged and a `pending_update` hash
is populated; the user is unchanged Pro-monthly, which is the correct outcome.

Expiry: `expired_at` is the earlier of the trial end or the earliest
`items.current_period_end` **if within 23 hours**, otherwise **23 hours** from the
request. To cancel a pending update, void the invoice.

**Never `proration_behavior: 'none'` on an interval change** — Stripe still resets
the billing date and bills immediately but issues no credit for unused time, which
is double-charging from the customer's side.

### E-DOWN — Annual → Monthly, scheduled

Annual is prepaid; switching immediately would issue up to ~¥13,000 of credit for a
*downgrade*. Use a schedule:

```
schedules.create({ from_subscription: sub_id })
schedules.update(sched_id, { phases: [
  { …current annual…, end_date: current_period_end },
  { items: [{ price: monthly_price_id }] },
], end_behavior: 'released' })
```

Store `schedule_id` on the row. `end_behavior: 'released'` — `cancel` would
terminate the subscription at the end of phase 2. Two rules that bite: *"you must
pass all current and future phases, including any previously set parameters you want
to keep"*, and *"if a subscription has a subscription schedule attached, use the
Subscription Schedule API to modify the subscription, instead of the Subscriptions
API."* Clear `schedule_id` on `subscription_schedule.released`.

**Undoing a scheduled downgrade** = release the schedule
([`/release`](https://docs.stripe.com/api/subscription_schedules/release)), which
keeps the subscription and drops the schedule. Entitlement is `pro` throughout, and
`quota_anchor_at` never moves, so the undo is a no-op on quota — as it should be.

Entitlement and quota are **unchanged in both directions**: both intervals are `pro`
and the anchor only moves on E-UP's deliberate reset. Interval changes are invisible
to the quota layer.

### Refunds

| Case | Entitlement | Mechanism |
|---|---|---|
| **Full refund of the current period** | **cancel immediately, revoke** | `charge.refunded` where `amount_refunded == amount` on the invoice covering the current period → `subscriptions.cancel`, then reconcile |
| **Partial refund** | **unchanged** | goodwill/proration adjustments are not a statement about access |
| **Refund issued by hand in the Dashboard** | same as above | which is why `charge.refunded` is a subscribed event and not merely an accounting concern — a manual refund must reconcile, not diverge |
| **Deliberate support exception** | as decided | record it; the reconciler must not silently undo a manual decision, so an exception sets a flag the reconciler respects |

**Quota is not clawed back on refund.** Rewrites already delivered were delivered.
The window simply ends with the entitlement.

### Money arrives after the subscription is gone

`invoice.paid` for a subscription that is already `canceled` — a customer paying an
old dunning invoice weeks later. The reconciler recomputes from Stripe, finds no
qualifying subscription, and correctly leaves the user `free`. **That is the right
entitlement and the wrong outcome**, because money was received.

**Policy: never silently.** The handler raises a `billing_needs_review` alert
carrying the invoice, amount and customer. A human then either restores entitlement
(by creating a new subscription) or refunds. Both are fine; silence is not.

### Account deletion

**An account must never disappear while Stripe keeps charging an orphaned
customer.** Deleting the Supabase user first leaves a live subscription whose
`user_id` resolves to nothing — it bills forever, the webhook cannot place it, and
the customer has no surface on which to cancel.

Ordered flow, and the order is the whole point:

1. Block deletion if a qualifying subscription is `active` / `trialing` / `past_due`
   / `incomplete`. Show what it is and what will happen.
2. On confirmation, `subscriptions.cancel` **immediately** (not at period end — the
   account is going away), and decide refund per the policy above. Japanese
   consumer expectation for a mid-period 解約 with immediate deletion is a
   prorated refund; make it a deliberate choice, not an accident.
3. Wait for `customer.subscription.deleted` and a reconciliation showing `free`.
4. Only then delete the user, and **retain the Stripe customer** — invoices are 帳簿
   records (§0). Set `metadata.deleted_user_id` on the customer so a later
   accounting question is answerable.

---

## 9. The transition table

This is the test in the header made concrete. Every row has exactly one entitlement
and one quota outcome.

### Cancellation

| # | Scenario | Entitlement | Quota | Notes |
|---|---|---|---|---|
| 1 | Cancel mid-period | `pro` to `current_period_end` | untouched | `cancel_at_period_end: true`; status stays `active` |
| 2 | Cancel → un-cancel before period end | `pro`, never changed | untouched | **True no-op.** Clear `cancellation_details.feedback` explicitly — whether Stripe clears it is undocumented |
| 3 | Cancel → period expires | → `free` at period end | new `free:YYYY-MM` window, fresh 50 | The calendar month has always rolled (min Pro term = 1 month), so no lockout |
| 4 | Expired → resubscribe | → `pro` on `invoice.paid` | **new `sub_id` ⇒ new window key**, fresh 1,000 | Reuse the existing customer; resolve price by `lookup_key` so an archived price is never used |

**Always `cancel_at_period_end: true`, never `cancel_at: <period_end>.`** They look
equivalent and are not: *"When you schedule a cancel date that occurs before the
billing period ends, the subscription's items' `current_period_end` updates to match
the `cancel_at` date. **This creates prorations**"*, and the billing cycle anchor
moves with it ([cancel](https://docs.stripe.com/billing/subscriptions/cancel)).
`cancel_at_period_end` is on Stripe's explicit list of updates that generate no
prorations and no charge — which is precisely why row 2 is clean.

### Interval changes, including combinations

| # | Scenario | Entitlement | Quota |
|---|---|---|---|
| 5 | Monthly → annual, payment succeeds | `pro` throughout | `quota_anchor_at := new period start`, **`quota_generation += 1`**, fresh window. The generation is what makes it fresh — see §4.4 |
| 6 | Monthly → annual, **payment fails** | **`pro` monthly, unchanged** | **untouched** — nothing applied |
| 7 | Monthly → annual, pending update expires (23 h) | unchanged monthly | untouched |
| 8 | Annual → monthly, scheduled | `pro` throughout | untouched — anchor does not move |
| 9 | Annual → monthly scheduled, then **undone** | `pro` throughout | untouched |
| 10 | Annual → monthly scheduled, then **cancel entirely** | `pro` to period end, then `free` | as row 3 |
| 11 | **Cancellation scheduled + monthly → annual** | see below | see below |

Row 10: cancelling a subscription that has a schedule releases it from the schedule
first, *"which means the rest of the scheduled changes won't take effect."* Clear
`schedule_id`.

**Row 11 is the one that needs a stated rule.** A pending update and a schedule
phase change interact: *"A schedule phase change discards a pending update and voids
the associated invoice"*, and Stripe voids a pending update when *"a subscription
schedule linked to the subscription transitions to a new phase."*
**Policy: refuse the second operation while the first is outstanding.** If
`cancel_at_period_end` is true, un-cancel before offering an interval change; if a
`schedule_id` or a `pending_update` exists, the upgrade path returns a "finish or
undo the pending change first" error. Serialising these in our own UI is far cheaper
than reasoning about Stripe's interaction matrix, and neither combination is a
sequence a real user is deprived of.

### Payment failure

| # | Scenario | Entitlement | Quota |
|---|---|---|---|
| 12 | Renewal fails → `past_due` | **`pro`** while `now() < past_due_since + 14d` | untouched |
| 13 | Payment requires authentication (3-D Secure) | `pro`, same grace | untouched |
| 14 | Retry succeeds | `pro`; `past_due_since` cleared | **untouched — no reset** |
| 15 | Retries exhausted → `unpaid` | → `free` | new `free:` window |
| 16 | Grace expires while still `past_due` | → `free` at day 14 | new `free:` window |
| 17 | **`past_due` + user cancels** | `pro` per grace, then `free` at period end or day 14, whichever is first | as row 3 |
| 18 | **`past_due` + payment recovered + cancellation pending** | `pro` to period end | untouched |
| 19 | Annual renewal fails, then recovers | rows 12 → 14 | untouched — a 12-month anchor keeps ticking monthly windows |
| 19a | **Payment recovers *after* day 14, same Stripe subscription** | `free` → `pro` again on `invoice.paid` | **untouched — no fresh 1,000.** Same `sub_id`, same `interval`, so §4.2's diff moves nothing |

Row 14 needs no rule: the anchor did not move, so there is nothing to reset.

**Row 19a is the row this table was missing, and it is the one a naive
implementation gets wrong.** `unpaid` and `past_due`-past-grace both read as `free`,
so a recovery from either is a `free → pro` transition — and §4.2's *old* first row
("Pro activation (`free → pro`)") would have fired on it and reset the anchor. The
user would be handed a fresh 1,000 on a billing period they had already spent, having
paid for one month. Keying the anchor on `stripe_subscription_id` rather than on the
plan transition is what distinguishes this from row 4, where the id genuinely is new.

The bounded imperfection worth naming: if a subscription sits `unpaid` for two months
and then recovers, the anchor has kept ticking and `n` has advanced two windows, so
the user does land in an empty bucket. Stripe has billed one period, we have rolled
three. It is bounded by however long Stripe leaves a subscription recoverable and it
falls out of the same arithmetic row 19 depends on, so it is accepted rather than
fixed.

### Races, retries, and reliability

| # | Scenario | Outcome |
|---|---|---|
| 20 | Two simultaneous Checkouts | One session. `checkout_intents` PK → second request reuses the first session's URL (§3.3a) |
| 21 | Double-click Upgrade | Same as 20; plus a Stripe idempotency key (§3.3b) |
| 22 | Abandoned Checkout → retry | 30-minute `expires_at`; `checkout.session.expired` clears the intent; retry opens a fresh session |
| 23 | `incomplete` subscription lingering | **`free`.** Never granted on `incomplete`. Pre-flight returns the existing payment URL, not a new session |
| 24 | Webhook duplicated | `stripe_events` PK; already-`processed` → 200 |
| 25 | Webhook out of order | Advisory lock + `reconciled_at` guard (§5) — the older reconciliation is discarded |
| 26 | Webhook dropped | Nightly reconciliation + `delivery_success=false` sweep |
| 27 | Handler crashes mid-way | Event **not** marked processed; transaction rolls back; Stripe retries within its 3-day envelope |
| 28 | Reservation then model failure | `release` → **no quota consumed**; brakes still ticked (§6) |
| 29 | Client retries the same rewrite | Same `request_id` → same reservation. **Cannot consume twice** |
| 30 | Handler dies between generate and commit | Reservation expires after 5 min and releases. User gets one free rewrite. Bounded, fail-open |

### Money and identity

| # | Scenario | Outcome |
|---|---|---|
| 31 | Full refund of the current period | Cancel immediately, revoke (§8) |
| 32 | Partial refund | Entitlement unchanged |
| 33 | **Refund while cancellation pending** | Full → immediate cancel supersedes the scheduled one; partial → schedule stands |
| 34 | Old unpaid invoice paid after termination | Stays `free` **and raises `billing_needs_review`** — never silent (§8) |
| 35 | Account deletion with an active subscription | Blocked → cancel → confirm `deleted` → then delete user; Stripe customer retained (§8) |
| 36 | Grandfathered price after a price change | Still `pro` — entitlement validates **product ID**, and `transfer_lookup_key` having stripped the old price's lookup key is irrelevant (§3.2) |
| 37 | User switches Macs | Entitlement and quota are server-side and follow `auth.uid()`. Local `history.json` stays per-Mac (`AGENTS.md` §14) |
| 38 | Sign out → sign in as a different account | Keyed on `auth.uid()`. The app must clear cached plan state on sign-out |
| 39 | Same customer holds an unrelated subscription | **Not** granted Pro — §3.2's product check |
| 40 | Two qualifying subscriptions somehow exist | Latest `created` wins **and** a duplicate alert is raised. Never summed |

### Cap-hit surfaces

| # | Scenario | Message |
|---|---|---|
| 41 | Free user hits 50 | Paywall (`pricing.md` §3), annual preselected, **with `resets_at`** |
| 42 | Pro user hits 1,000 | **Not a paywall** — there is no tier above. 「今月の上限に達しました。◯月◯日にリセットされます」 |
| 43 | Daily/hour/minute brake fires | Distinct message and a distinct `reason` in analytics (§6) |
| 44 | Counter display near the cap | `committed` only, clamped at the limit. `pending` is never shown |

---

## 10. Japan — required, not optional

Sources: [e-Gov 特商法](https://laws.e-gov.go.jp/law/351AC0000000057),
[消費者庁 最終確認画面ガイドライン (2024-11-19)](https://www.no-trouble.caa.go.jp/pdf/20241119la02_09.pdf),
[消費税法第63条](https://laws.e-gov.go.jp/law/363AC0000000108),
[国税庁 No.6902](https://www.nta.go.jp/taxes/shiraberu/taxanswer/shohi/6902.htm),
[国税庁 インボイス Q&A](https://www.nta.go.jp/taxes/shiraberu/zeimokubetsu/shohi/keigenzeiritsu/invoice.htm).

The product is **通信販売** and a **役務提供契約**. 特定継続的役務提供 (法第41条) does
not apply — it covers 7 designated services, none of them software.

### クーリング・オフは適用されない — but every disclosure duty does

通信販売にクーリング・オフ制度はありません。More decisively, 法第15条の3's 8-day
法定返品権 is written for **商品又は特定権利**; 「役務」「役務提供契約」 appear nowhere
in it. **A subscription has neither.** 法第11条 and 法第12条の6 both explicitly cover
役務提供契約, so no return right ≠ no disclosure duty.

### 法第12条の6 — the 最終確認画面 (in force 2022-06-01)

> 広告において法第11条に従い表示を行ったとしても、それにより法第12条の6第1項の
> 表示義務を果たしたことにはならない

**A 特商法に基づく表記 page does not discharge this.** Six items must be on the
screen where the user commits: ①分量 ②販売価格 ③支払時期・方法 ④提供時期 ⑤申込期間
⑥撤回・解除に関する事項.

Two land directly on this design:

**①分量 — the 1,000回 cap is 分量:**
> サブスクリプションの場合についても…期間内に利用可能な回数が定められている場合には
> その内容を表示しなければならない…**自動更新のある契約である場合には、その旨も加えて
> 表示する必要がある。**

**②販売価格 — this governs Free → Pro:**
> 無償又は割引価格で利用できる期間を経て…有償又は通常価格の契約内容に自動的に移行する
> ような場合には、**有償契約又は通常価格への移行時期及びその支払うこととなる金額が明確に
> 把握できるようにあらかじめ表示する必要がある。**

**And the one that constrains copy `pricing.md` §8 already specifies:**
> **「いつでも解約可能」などと強調する表示は**…実際には解約条件等が付いているにもかかわらず…
> **「人を誤認させるような表示」に該当するおそれがある。**

「いつでもワンクリックで解約」 is defensible **only while it is literally true** —
Billing Portal, one click, no phone call, no conditions. This design satisfies that,
so the claim and the mechanism are now coupled: if cancellation ever acquires a
condition, this string becomes a 特商法 problem before it becomes a copy problem.
Pair it with 「解約後も現在の請求期間の終了日までご利用いただけます」, which is both
accurate and reassuring.

Penalties: 第1項違反は **3年以下の拘禁刑又は300万円以下の罰金** (法第70条第2号)、
**法人重科1億円以下** (法第74条①二). Hence §11's sequencing.

**Do not enable Stripe's retention offer.** The 消費者庁
デジタル取引・特定商取引法等検討会 (第1回 2026-01-22 → 第7回 2026-07-17;
**no とりまとめ as of 2026-08-08**) names
「解約前に他のプラン等の選択肢を紹介し、消費者を引き留めようとする」 as a candidate
prohibited practice in its
[第4回 material](https://www.caa.go.jp/policies/policy/consumer_transaction/meeting_materials/assets/consumer_transaction_cms101_260416_02.pdf),
alongside 電話限定解約 and multi-screen cancellation flows.「キャンセル困難」 was the
most frequent dark pattern in its survey — **38 of 102 cases**.

### 消費税 — Core7 is a 免税事業者, and that settles three of these questions

**Business decision, taken 2026-08-08: Core7 is treated as a 免税事業者, is not
registered as an 適格請求書発行事業者, and has no T-number.** This section previously
assumed the opposite and specified work that must now *not* be done:

| | Do |
|---|---|
| Stripe Tax JP registration | **Do not add.** `/v1/tax/registrations` stays empty |
| `account_tax_ids` / `jp_trn` | **Do not set** |
| `DESKTOP_STRIPE_AUTOMATIC_TAX` | **`false`**, and `desktop-checkout` sends `automatic_tax[enabled]=false` explicitly |
| Prices | Unchanged — ¥1,480/month, ¥14,400/year |
| Empty tax registration as a launch blocker | **It is not one.** It is the correct state |

Three consequences, and each *removes* an obligation rather than deferring it:

**総額表示義務 does not apply to us.** 消費税法第63条 opens
「事業者（第九条第一項本文の規定により消費税を納める義務が免除される事業者を除く。）は…」
— 免税事業者 are excluded by the text of the article itself. The tax-inclusive
display requirement is therefore not binding here. `tax_behavior: inclusive` stays
anyway: it is immutable, it is what makes ¥1,480 the amount actually charged, and
with `automatic_tax` off no tax is computed against it at all, so the flag is inert.
景表法's 有利誤認 still applies to everyone — which is why the plan card now says
「表示価格が実際にご請求される金額です。」 rather than 「税込」.

**A 免税事業者 may not issue a 適格請求書, so the invoice PDF carrying neither 適用税率
nor 消費税額等 is correct, not broken.** The paragraph this replaces called that "the
silent invalidity" and treated it as a defect to fix. Under the new position it is
the required output: showing a 消費税額 or a 登録番号 we do not have would
misrepresent the business. **The commercial cost named there is real and unchanged**
— a corporate buyer cannot claim 仕入税額控除 in full against our invoice, so a
¥1,480 tool is marginally harder to expense. That is now a pricing/positioning
consequence of the 免税 decision, not a bug.

**【推測】** The 経過措置 (invoice-transition relief) still lets a buyer deduct a
proportion of tax on purchases from a 免税事業者 for a period, on a declining
schedule. The exact proportion and end date are not verified here and nothing in
this design depends on them; check with the accountant before making any claim to a
corporate buyer.

**What would reverse all of this: the 1,000万円 threshold.** Exceeding ¥10M of
taxable sales in a 基準期間 makes the business a 課税事業者 automatically, and
総額表示義務 and the invoice question both come back. The switch is
`DESKTOP_STRIPE_AUTOMATIC_TAX`, but flipping it alone is not enough — the JP
registration under Tax → Locations and `account_tax_ids` have to exist first, or
Stripe computes ¥0 and produces a silently non-compliant invoice. That trap is why
the flag is read at session creation rather than baked in.

For our own books: **ストライプジャパン株式会社 `T8010601046367`**. Visa/Mastercard
processing fees became JCT-taxable **2026-04-01**, FX fees **2025-10-31** — both
inside the current fiscal year. 【推測】 Whether a 免税事業者 gains anything from
tracking these is an accounting question, not a technical one.

---

## 11. Sequencing

| | Step | Blocked by |
|---|---|---|
| 1a | ~~Product, 2 prices (`inclusive`, `lookup_key`)~~ — **done 2026-08-08**, ids in the status table above. API version read off the docs: **`2026-07-29.dahlia`** | — |
| 1b | ~~Webhook endpoint **on `2026-07-29.dahlia`**, portal config (`shortening_interval` only, **retention offer off**), the three function secrets~~ — **done**. Stripe Tax and `jp_trn` are **deliberately not done** (§10, 免税事業者). Still outstanding: **dunning → `unpaid`** | **manual** — Dashboard access |
| 2 | ~~Schema (§7) + all entry points, GC retention fix (§4.3)~~ — **applied.** `…120000_desktop_billing.sql` and `…130000_desktop_billing_cron.sql` | — |
| 2b | ~~`20260808140000_desktop_billing_entry_points.sql` — the wrappers for `checkout_intents` / `stripe_events` / `pro_products` and `desktop_process_stripe_event`~~ — **applied 2026-08-08** | — |
| 3 | `desktop-checkout` (§3.3), `desktop-portal`, `desktop-stripe-webhook` (§5) — **written**, in `supabase/functions/`, sharing `_shared/billing.ts`. **Not deployed.** `supabase functions deploy` is the only correct route: the three functions import `../_shared/billing.ts`, and hand-uploading a reconstructed file set is how deployed source silently diverges from the repo | 1b, 2b |
| 4 | ~~Rewrite `reserveUsage` as reserve/commit/release (§6)~~ — **written**, plus `requestId` on the wire and a `reason` on every 429. **Not deployed** | 2 |
| 5 | ~~Paywall, usage readout **with the computed reset date**, portal button, `past_due` banner~~ — **written**: `PlanView` (⚙︎ プラン), ホーム's quota row, `OverlayController.presentQuotaDenial`. **Account deletion is NOT done** — see below | 3 |
| 6 | 特商法 最終確認画面 items, 表記 page, `../web/app/legal/page.tsx` correction | independent, **launch-blocking** (§10) |
| 7 | `landing/src/data/pricing.js`, `landing/content.md` §10 | independent |

**Account deletion (§8) is deliberately not in step 5's tick.** The Mac app has no
delete-account surface at all — the flow lives in the iOS repo's `delete-account`
Edge Function, and §8's ordering (block → cancel → confirm `deleted` → then delete
the user, retaining the Stripe customer) is a change to *that* function. Building a
second deletion path on the desktop would be the wrong shape: one account, one
deletion. It is still launch-blocking, because a deletion that leaves Stripe billing
an orphaned customer is the failure §8 exists to prevent.

**Portal trap:** `subscription_update.schedule_at_period_end.conditions` must be
**`shortening_interval` only**. `decreasing_item_amount` fires when a subscription
moves *"from a shorter billing period to a longer one and the resulting price is
cheaper in the long term"* — at ¥1,480/mo vs ¥14,400/yr that describes our
**upgrade**, and enabling it silently defers every upgrade to period end.

### Test clocks — the required matrix

Nothing time-dependent in §9 is testable by waiting. Confirm at minimum:

### What has actually been run — 55 assertions, 0 failures

**A Stripe test clock turned out not to be the precondition this section assumed.**
Everything time-dependent in §9 runs on *our* clock, not Stripe's:
`desktop.effective_plan(status, past_due_since, p_at)` and
`desktop.quota_window(…, p_now)` both take the instant as an **argument**. That is
§3.4's design restated — "Stripe emits no event when our own 14-day timer elapses",
so entitlement is a read-time computation and nothing has to fire on time. A test
clock moves *Stripe's* time and would never move `now()` in Postgres.

So the split is:

- **`scripts/billing-matrix.sql` — 45 assertions, all passing.** Feeds the real
  `desktop_process_stripe_event` → `desktop_reconcile_subscription` path exactly the
  shapes Stripe sends, then asks the pure functions what they say at a chosen
  instant. Deterministic, offline, no money, no waiting.
- **`scripts/select-subscription_test.ts` — 10 assertions, all passing.** §3.2's
  selection is TypeScript, not SQL, and the test imports the **real module the
  webhook uses** rather than a copy.
- **A Stripe test clock is still needed** for the rows whose *input* is the claim:
  that a declining card really produces `past_due`, that a pending update really is
  discarded on payment failure, that a schedule really releases. Those assert
  Stripe's behaviour; the matrix assumes it.

The sandbox is a **disposable local PostgreSQL 16 cluster**, not a Supabase branch —
branching needs the Pro plan and the org is on Free. The three migrations apply to
it unmodified; the only Supabase-isms in the whole schema are three role names and
`auth.uid()`, which is stubbed to read a session GUC so `desktop_get_entitlement()`
is testable without minting JWTs. Live is untouched by construction: nothing in this
path has a network route to it.

**Rows proven** — 1, 2, 3, 4, 5, 8, 9, 12, 14, 15, 16, 19, 19a, 24, 25, 28, 29, 30,
36, 39, 40, 44, plus §4.2's month-end arithmetic and §7's `auth.uid()` derivation.

**Rows still unproven, and why** — 6, 7 (pending-update failure and its 23-hour
expiry), 10, 11, 13 (3-D Secure), 17, 18, 20–23 (Checkout races), 26, 27 (delivery
and retry), 31–35 (refunds, disputes, deletion), 41–43 (UI surfaces). These need
either a Stripe test clock, a browser through Checkout, or a running app.

### Earlier, against the live project

**Four of these were run on 2026-08-08 without a test clock, against the live
project on throwaway ids, and the rows were deleted afterwards.** They are the ones
that are pure arithmetic or pure lifecycle:

| Checked | Result |
|---|---|
| §3.3a's intent lock | Two calls → one intent, `created=false` on the second, **same `idempotency_key`**, and the loser is handed the winner's session URL |
| §6's three phases | Retry of one `request_id` does **not** double-reserve (`pending` stays 1); commit moves pending → committed and is idempotent; release returns the quota but **leaves the day brake at 2** — the asymmetry §6 asks for |
| The attributable 429 | A request over the cap denies with `reason = 'quota_month'`, not a bare refusal |
| **Anchor on 31 January** | `Jan 31 → Feb 28 → **Mar 31** → Apr 30`, and 12 months out lands on `n=11`, `Dec 31 → Jan 31`. No drift, which is the whole month-end argument |
| Free window, JST | `free:2026-08`, resetting **2026-09-01 00:00 JST** — not 09:00. §4.3's live bug is gone |

Everything below still needs a Stripe test clock and a real subscription — **and
therefore needs TEST MODE, which does not exist for this integration yet.** Test
clocks are test-mode only, so rows 5–19 cannot be exercised at all until a test-mode
webhook endpoint (same 13 events, same `2026-07-29.dahlia`) and a test-mode
`STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` pair exist. That is the real
precondition for this table, and it is not on §11's list because the list was
written before there was anything to test.

**The harness is written and waiting**: `scripts/billing-matrix.ts` (driver) and
`scripts/billing-matrix-helpers.sql` (five read-only RPCs the assertions need,
**sandbox-only and deliberately never in `supabase/migrations/`** — every one of
them takes a `p_user_id`, which is the IDOR shape §7 bans from production).

The sandbox is a **Supabase branch**, chosen so live is untouched: its own database
with all migrations applied, its own project ref, its own function URLs. Two
structural facts forced that choice rather than a cheaper one — Edge Function
secrets are **project-wide**, so one `STRIPE_SECRET_KEY` cannot be both live and
test; and `desktop.pro_products` would have to carry the test-mode product id,
because test mode is a separate object space and the sandbox product has a different
id than live.

The driver refuses to run against live three separate ways: the key must match
`^(rk|sk)_test_`, every Stripe object it touches is asserted `livemode: false`, and
the Supabase URL must not contain the live project ref. All three were exercised
before the harness was ever pointed at anything.

**The account is LIVE.** `acct_1T2WK5CZmA6ItMhq` has `livemode: true` on the
product, both prices and the webhook endpoint, so any end-to-end purchase made today
moves real money and creates a real 帳簿 record — §0 exists because exactly that
already happened once, and the ¥980 charge it describes cannot be deleted. Refunding
a live test charge is not merely tidy-up either: a **full** refund is §8's revoke
trigger, so it exercises §9 row 31 on the way out.

| Rows | What must be true |
|---|---|
| 3, 4 | A Pro window key changes with the subscription id; free window is fresh on downgrade |
| 5–7 | A **failed** upgrade leaves interval, entitlement and `quota_anchor_at` untouched |
| 8–10 | Scheduled downgrade holds annual access; release restores cleanly |
| 12–16 | Grace expires at day 14 regardless of the Dashboard setting |
| 14 | **A recovered payment does not reset quota** |
| 19 | An annual subscription rolls 12 monthly quota windows |
| — | **Anchor on 31 January produces Feb 28, then Mar 31** (§4.2) |
| 24–27 | Duplicate, out-of-order and dropped events all converge on one state |
| 28–30 | Reservation lifecycle: failure releases, retry does not double-consume, orphan expires |

One thing to measure rather than assume: the current retries-exhausted Dashboard
value (§3.4). Stripe's tax rounding on ¥1,480 used to be the second — it is moot now
that no tax is computed at all (§10).

---

## 12. Documents this obligates

| File | What changes |
|---|---|
| `pricing.md` §1 | 「リセット: 毎月1日（暦月）」 is **wrong for Pro** — Pro resets on the subscription anchor. Free keeps the 1st |
| `pricing.md` §6 | The margin table's cap column is now **correct**, because §4.4 removed the straddle that made it optimistic |
| `pricing.md` §7 | "Calendar month, not billing period" is reversed for Pro, with §4.4's reasoning. Bucket keys and the GC-retention hazard both change |
| `pricing.md` §8 | 6 webhook events → 9; the schema sketch is superseded by §7; 「いつでもワンクリックで解約」 needs §10's qualifier |
| `AGENTS.md` §12 | "Subscription enforcement… what a free-tier desktop user sees when they hit the cap, or whether desktop and keyboard draw from one quota or two" — both answered |
| `AGENTS.md` §10 | "Server-backed usage stats" moves from out-of-scope to required |

## 13. Still open

- **Degrading over-cap users to `gpt-oss-120b` instead of blocking.** GitHub
  Copilot's answer (*"you can still use Copilot with one of the included models for
  the rest of the month"*), and `pricing.md` §7 lever 1 already has the model wired
  at ¥0.0413/rewrite — **15.9× cheaper**. Blocked only on `pricing.md` §10's
  unresolved quality question. Resolving that one question improves the cost model
  16× *and* removes the worst UX moment in the product. **Highest-value open item in
  either document.**
- ~~**Stripe's tax rounding** on ¥1,480 — ¥134 vs ¥135.~~ **Closed by the 免税事業者
  decision** (§10): `automatic_tax` is off, so there is no tax line to round.
- **The retries-exhausted setting's current value** — documented options,
  undocumented default.
- **Reconciliation cadence.** Nightly is a starting guess; zero observations exist.
- **Refund policy on account deletion mid-period** (§8 step 2) — prorated refund is
  the JP consumer expectation, but it is a business decision, not a technical one.
- ~~**【推測】 適格簡易請求書** applicability to subscriptions~~ — **moot.** A
  免税事業者 issues neither form (§10).
- **【推測】 The 経過措置 proportion and end date** for a corporate buyer's partial
  仕入税額控除 on purchases from a 免税事業者. Nothing here depends on it, but it is
  the number to have before answering a corporate buyer who asks (§10).
- **When the 1,000万円 threshold is crossed**, §10 reverses: 総額表示義務 returns and
  the invoice-registration question reopens. Worth a calendar reminder against the
  基準期間 rather than a discovery at filing time.
