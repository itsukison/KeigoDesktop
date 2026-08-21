# Pricing — 敬語ボタン Mac

**Read `AGENTS.md` first.** This file is the pricing and billing authority. Where
it disagrees with `landing/src/data/pricing.js` or `landing/content.md` §10, this
file wins — those numbers were transcribed from a reference site as layout
placeholders and were never commitments.

Status: **prices are final for launch. Nothing is implemented.** No code in
`supabase/` or `App/` enforces any of this yet. The cost model below runs on
GPT-5.6 Terra's list price, so there is no longer an unknown blocking the numbers.

**2026-08-10 — two additions, and §1, §3, §4 and §8 carry them:** the product now
sells in **USD as well as JPY**, chosen by interface language, and there is a
**one-time welcome offer** at the end of first run. The yen plan is unchanged.

---

## 1. The plan — final

| | 無料 | Pro |
|---|---|---|
| 書き換え | **30回 / 月** | **1,000回 / 月**（約33回/日） |
| リセット | 毎月1日（暦月） | 毎月1日（暦月） |
| 価格（JPY） | ¥0 | **¥1,480 / 月** ・ 年払い **¥1,200 / 月相当** |
| 年払い総額（JPY） | — | ¥14,400 / 年（**2ヶ月分以上お得**） |
| 価格（USD） | $0 | **$12 / month** ・ yearly **$10 / month** |
| 年払い総額（USD） | — | $120 / year (**exactly 2 months free**) |
| カード登録 | 不要 | 必要 |
| 無料トライアル | **なし** — 無料プランがその役割 | — |

**iPhone版 (`AIキーボード`) は無料のまま、上限も現状のまま、課金は一切ない。** See §2.

### Which currency a user is charged in

**The interface language decides, and nothing else does.** English → USD; 日本語 and
简体中文 → JPY. `BillingCurrency.forInterface` is the only place that rule lives.

- **简体中文 is billed in yen**, because `AGENTS.md` §17's premise is a Chinese
  speaker working in Japan — their card is a Japanese card. The same fact that keeps
  their buttons writing Japanese keeps their price in yen.
- **The app sends the currency to Checkout explicitly** rather than letting Stripe
  localize by IP. The plan card promises 「表示価格が実際にご請求される金額です」, and IP
  detection would quote an English user sitting in Tokyo in yen after the app had
  shown them dollars. That gap is exactly what the sentence rules out.
- **An existing subscription's currency outranks the language.** Stripe fixes a
  subscription's currency at creation, so a user who bought in yen and later switched
  the app to English is still charged yen — and is still quoted yen everywhere in the
  app. `desktop.subscriptions.currency` is what makes that answerable.
- The arbitrage is real and accepted: $12 ≈ ¥1,800 against ¥1,480, so a determined
  user can pay ~18 % less by reading the app in Japanese. It is a self-service choice
  between two honest prices for one product, and policing it would mean geo-gating a
  language picker.

### Not in the plan

- **No Premium / third tier.** Volume is the only differentiation axis available —
  one model, and `AGENTS.md` §10 defers screen context, streaming, and teams. Add
  a tier when Pro contains something worth segmenting on, not before.
- **No trial.** See §3.
- **No usage-based billing.** A ¥0.66 unit is more accounting than revenue.
- **No third currency.** EUR and CNY are one `currency_options` entry each when
  there is demand to point at; neither has any today.

### Why these numbers

| Decision | Reason |
|---|---|
| 30 free | Cut from 50 on 2026-08-21 (§7 lever 2). Still enough to reach the wall on real work inside a month, and it reaches it sooner |
| 1,000 Pro | ~33/day — beyond any human writing pace, and it holds the margin if someone does reach it (§7) |
| ¥1,480/月 | The monthly anchor |
| ¥14,400/年 | Produces a clean **¥1,200/月相当** that compares directly against ¥1,480, at a ~19% discount |
| ¥1,200 shown first | The annual plan is sold on the monthly-equivalent number; ¥14,400 is secondary |
| $12/month | ≈ ¥1,800 at ¥150/USD — deliberately above the straight conversion (¥1,480 ≈ $9.87). US prosumer willingness-to-pay carries it, and international card fees eat part of the difference |
| $120/year | $12 × 12 = $144, so this is **exactly two months free** — the same 「2ヶ月分お得」 badge the yen plan carries, and here it is literally rather than approximately true (yen saves 2.27 months) |
| $10/month shown first | Same reason as ¥1,200: annual is sold on the monthly-equivalent figure, and $120 was chosen over $96 or $99 **because it divides by twelve into a round number.** $99 gives $8.25 and $96 gives a 33 % discount that makes the monthly plan look mispriced |

### The welcome offer — 33% off the first period

Shown once, at the end of first run, on its own page between きっかけ and 完了.

| | list | first period | after |
|---|---|---|---|
| 月払い JPY | ¥1,480 | **¥980 × 3ヶ月** | ¥1,480 |
| 月払い USD | $12 | **$8 × 3 months** | $12 |
| 年払い JPY | ¥14,400 | **¥9,600（初年度）** | ¥14,400 |
| 年払い USD | $120 | **$80 (first year)** | $120 |

- **72 hours**, minted server-side when the user reaches the page and enforced by
  `desktop-checkout` at the moment a session is created. `desktop.welcome_offers` is
  primary-keyed on `user_id` and its rows are **never deleted** — that is what makes
  the deadline real against a reinstall, a replayed onboarding, or a second Mac.
- **Two Stripe coupons, not a third price and not a promotion code.** `amount_off`
  with `currency_options` rather than `percent_off`, because a flat 33 % produces ¥888
  and $7.20 and all four numbers above have to be round. A promotion code would be a
  string, and a string is redeemable by anyone who reads it.
- **Annual is preselected**, for §4's reason.
- Declining costs nothing: the ホーム card carries the same price and the same
  deadline until the window closes. An offer that disappeared with the page it was
  made on would be a deadline of about four seconds.
- 33 % rather than 50 %: the renewal step-up from ¥9,600 to ¥14,400 is survivable,
  and doubling a price at first renewal is the classic churn cliff. Margin is not the
  constraint — at 150 rewrites/month a ¥9,600 first year still nets ~88 %.

**This is the second conversion surface, and §3 was written when there was only one.**

---

## 2. Mobile is free forever, and separate at every layer

The iOS keyboard stays free with no cap change. The Mac app is the only paid
surface. Three consequences, all simplifications:

1. **`keyboard-rewrite` is never touched.** It stays v42 at
   `USER_DAILY_REWRITE_UNITS = 900` (≈300 requests/day at `candidateCount: 3`).
   No downgrade for the 3,279 existing accounts.
2. **No StoreKit, no Apple cut.** iOS sells nothing, so IAP never applies.
   `import StoreKit` in `../Japanese/iOS/Container/RootContainerView.swift:2` is
   there only for `requestReview()` and stays that way. The Mac app ships outside
   the Mac App Store by hard constraint (`AGENTS.md` §2), so Stripe is the whole
   billing story and no platform fee appears anywhere in §6.
3. **Entitlement lives in the `desktop` schema.** §6's split — tables in
   `desktop`, entry points as `SECURITY DEFINER` functions in `public` prefixed
   `desktop_` — already isolates it. Nothing on iOS reads plan state.

`AGENTS.md` §12's open question *"whether desktop and keyboard draw from one quota
or two"* resolves to **two**, and the mobile one is not a quota.

**Mobile is also the acquisition channel**: 3,279 registered accounts, 766
monthly-active (measured 2026-07-08 → 2026-08-08), all with accounts already.
Saying 「iPhone版はこれからも無料です」 on the paywall also kills the strongest
objection to paying for a companion app.

⚠️ Promoting a paid Mac subscription from inside the free iOS app touches Apple's
anti-steering rules. Post-2025 relaxations (US, Japan's Smartphone Act) permit
external links, but the zero-risk route at launch is to acquire via the LP and
email and keep purchase mechanics out of the iOS binary.

---

## 3. Why there is no trial

The 30回/月 free tier is the trial, and a better one: it never expires, so it
can't run out while someone is on holiday; it demonstrates value on real work in
real apps; and 30 rewrites is enough for anyone who will love this to know.

A card-required trial would add a second, worse gate — JP consumers are averse to
auto-converting card trials, 特商法 imposes 自動更新 disclosure obligations, and
it is a standing 解約 complaint source. A no-card trial on top of a no-card free
tier is redundant by construction.

**The cap-hit is still the paywall.** It stopped being the *only* conversion event on
2026-08-10, when the welcome offer gave first run one — but the two are different
moments and neither replaces the other. The offer is made to someone who has just
watched the product work and has spent nothing; the cap-hit is made to someone who has
just been stopped. A user who declines the first is not a user who has said no.

| When | What the user sees |
|---|---|
| End of first run | The welcome offer page — 33% off the first period, 72 hours, **annual preselected** (§1) |
| While that window is open | A ホーム card carrying the same price and the remaining time |
| 20 / 30 used | Quiet 残り10回 note in the ホーム usage row |
| 28 / 30 used | 残り2回 — 今月分の書き換えがまもなく上限に達します |
| 30 / 30, on press | Upgrade panel on the overlay, **annual (¥1,200/月相当 · $10/month) preselected** |
| Always | Persistent 今月 21 / 30 readout in the main window's usage row |

The offer also does not undermine §3's argument against a trial: it asks for a card
**once, optionally, at a lower price**, and refusing it leaves the free tier exactly as
it was. A card-required trial removes the free path; this adds a cheaper paid one.

That last row is a **requirement**: a quota the user cannot see is a quota that
ambushes them, which is the worst conversion outcome available. It makes the
server-backed usage read that `AGENTS.md` §10 lists as out of scope into required
work — see §8.

---

## 4. Prices

### Annual

| | 表示 | 総額 |
|---|---|---|
| Primary (JPY) | **¥1,200 / 月相当** | ¥14,400 / 年 |
| Primary (USD) | **$10 / month, billed yearly** | $120 / year |

¥1,480 × 12 = ¥17,760. Annual saves **¥3,360**, which is 2.27 months of the
monthly price → **「2ヶ月分以上お得」**, a **18.9% discount**. ¥14,400 ÷ 12 is
exactly ¥1,200, which is the point: the buyer compares ¥1,200 against ¥1,480 in
one step, with no arithmetic.

$12 × 12 = $144. Annual saves **$24**, which is **exactly two months** — a **16.7%
discount**, deliberately close to the yen plan's so the two read as one product priced
twice rather than two different offers. $120 ÷ 12 = $10, and the divisibility is the
whole reason for the number.

**The badge is computed, never written.** `PlanPricing.monthsFree` derives it from the
two list prices, so a price change cannot leave a stale 「2ヶ月分お得」 beside a discount
that is no longer two months. A hard-coded 2 was the failure mode worth engineering
against here.

Annual prepay is the highest-leverage lever on this product — it converts cash
flow forward and removes eleven monthly churn decisions. Target **30–40% annual
mix**. Toggle defaults to annual; offer annual again at the first monthly renewal,
never earlier. Launch discounts go on a **cohort**
(「最初の100名は初年度 ¥9,800」), never on the list price.

### Net of Stripe (JP domestic card, 3.6%, no fixed fee)

| | 表示価格 | 手数料 | 手取り | 月あたり手取り |
|---|---|---|---|---|
| 月払い | ¥1,480 | ¥53 | ¥1,427 | **¥1,427** |
| 年払い | ¥14,400 | ¥518 | ¥13,882 | **¥1,157** |
| 混合（年払い35%） | — | — | — | **¥1,333** |

¥1,333/payer/month is the blended figure used in §6.

---

## 5. Cost model — GPT-5.6 Terra

### Rates (OpenAI list, standard processing)

| | per 1M tokens |
|---|---|
| Input | **$2.50** |
| Cached input | $0.25 |
| Output | **$15.00** |

Output is 6× input, so **output is 69% of the cost of a rewrite** — the only lever
that matters. `candidateCount: 1` (`AGENTS.md` §6) already takes the 3× multiplier
off, and `OPENAI_REASONING_EFFORT=low` keeps reasoning near zero (measured: 4
tokens average). 【推測】The cached-input rate probably never applies: at 550 input
tokens a request sits below OpenAI's automatic prompt-caching minimum. Do not model
cache savings — input is only 31% of the bill regardless.

### Tokens per rewrite — 【推測】

**550 input / 200 output** at `candidateCount: 1`. Derived from measured mobile
data (`public.ai_rewrite_events`, n=2,390 on `gpt-5.6-terra`): 421 input tokens on
~30 chars of user text implies ~390 tokens of fixed system-prompt overhead; a
mail-length desktop draft adds ~150 input and lands near 200 output.

### Cost per rewrite

```
input   550 × $2.50 / 1M  = $0.001375
output  200 × $15.00 / 1M = $0.003000
                            ─────────
                            $0.004375   × ¥150/USD = ¥0.656
```

**¥0.656 per rewrite** is the planning cost throughout this document.

### Per-user monthly COGS

| Usage / month | COGS | Note |
|---|---|---|
| 15 | **¥9.8** | assumed free-tier average 【推測】 |
| 30 | **¥19.7** | free cap — the worst a free user can cost |
| 150 | **¥98.4** | assumed Pro average 【推測】 |
| 500 | ¥328 | |
| 1,000 | **¥656** | Pro cap — the worst a payer can cost |

### Margin per payer

| | 平均利用（150回） | 上限利用（1,000回） |
|---|---|---|
| 月払い（手取り ¥1,427） | **93.1%** | **54.0%** |
| 年払い（手取り ¥1,157/月） | **91.5%** | **43.3%** |

The bottom-right cell is the tightest in the model and it is still comfortably
positive. **This is what the 1,500 → 1,000 change bought.** At a 1,500 cap a
maxing annual subscriber would cost ¥984 against ¥1,157 net — **15% margin**. At
1,000 it is 43%. The Pro cap is what makes the annual plan safe at Terra pricing.

### Fixed costs

| Item | Monthly |
|---|---|
| Supabase Pro | ~¥3,750 ($25) |
| Apple Developer Program | ~¥1,250 ($99/yr) |
| Domain + LP hosting | ~¥1,000 |
| **Total** | **~¥6,000** |

Contribution per payer at average usage is ¥1,235, so **5 paying users** cover all
fixed cost. Fixed cost is not a factor here; free-tier COGS is (§7).

---

## 6. Profit model

Per **1,000 Mac installs**, blended net ¥1,333/payer/month, free users averaging
15 rewrites/month and Pro users 150 【推測】:

| 転換率 | 課金者 | 売上 / 月 | 原価（無料） | 原価（Pro） | 原価計 | 粗利 | 粗利率 |
|---|---|---|---|---|---|---|---|
| 2% | 20 | ¥26,660 | ¥9,643 | ¥1,968 | ¥11,611 | ¥15,049 | **56.4%** |
| 4% | 40 | ¥53,320 | ¥9,446 | ¥3,936 | ¥13,382 | ¥39,938 | **74.9%** |
| 6% | 60 | ¥79,980 | ¥9,250 | ¥5,904 | ¥15,154 | ¥64,826 | **81.1%** |

### Break-even conversion rate (COGS only)

| Assumption | Break-even |
|---|---|
| Free avg 15/mo, Pro avg 150/mo | **0.79%** |
| **Every free user maxes 50/mo**, Pro avg | **2.59%** |
| Both tiers max out | **4.62%** |

Freemium conversion for a prosumer utility runs 1–4%, so the middle row is the one
to respect: **the model depends on caps being ceilings, not expectations.** The
bottom row is not a forecast — a population where every free user burns exactly 50
and every payer burns exactly 1,000 does not exist — but it is the boundary.

### How many free users one payer supports

- At assumed usage: **135 free users** per payer (¥1,329 contribution ÷ ¥9.8).
- If both max out: **23 free users** per payer (¥771 ÷ ¥32.8).

### Funnel, for scale — 【推測】

The install column is a model. Nothing about desktop demand is measured;
`desktop.activations` holds one row.

| | Pessimistic | Base | Optimistic |
|---|---|---|---|
| Mobile accounts → Mac install (6 mo) | 10% (328) | 15% (492) | 20% (656) |
| Free → paid | 2% | 4% | 6% |
| Payers | 7 | 20 | 39 |
| MRR | ¥9,300 | **¥26,700** | ¥52,000 |
| ARR | ¥112,000 | **¥320,000** | ¥624,000 |

Plus organic LP acquisition. The base case says the existing mobile base alone is
worth ~¥320,000 ARR, which is why the phone → Mac path deserves more engineering
attention than the pricing page does.

---

## 7. Usage limits — three layers

Only the first layer is marketed. The others are abuse brakes and must never
appear in pricing copy.

| Layer | 無料 | Pro | Purpose |
|---|---|---|---|
| **Monthly quota** (marketed) | 50 | 1,000 | The product boundary |
| **Daily brake** | 20 | 100 | Stops a scripted run draining the month in one sitting |
| **Hour / minute brake** | 120 / 12 | 120 / 12 | Already implemented (§6 `reserveUsage`) |

Copy for Pro reads 「月1,000回まで（通常のご利用では到達しません）」. Not 「無制限」 —
saying unlimited while enforcing 1,000 is a 景表法 problem.

**Calendar month, not billing period.** Bucket keys become `month:YYYY-MM`
alongside the existing `day:` / `hour:` / `minute:` in `desktop.usage_buckets`.
Anchoring Pro's window to Stripe's `current_period_start` is more correct and needs
the period stored in the entitlement row; at a 1,000 ceiling nobody reaches, the
difference never binds, and calendar month is the reset users expect
(「毎月1日にリセット」). Revisit only if the Pro cap starts binding.

**Free-tier COGS is the one line item that scales with registered users rather
than revenue**, and at Terra pricing it is the dominant cost at low conversion:
36% of revenue at 2% conversion, 18% at 4%, 12% at 6%. Watch it and act if it
holds above **25% of MRR**. Levers, in order:

1. **Route desktop traffic to `gpt-oss-120b`** (cerebras/groq, already wired per
   §6, and 51% of mobile traffic today). ¥0.0413/rewrite — **15.9× cheaper than
   Terra**, which erases the free tier as a cost line entirely (¥607/month per
   1,000 free users, 2.3% of revenue at 2% conversion) and takes a maxing Pro user
   from ¥656 to ¥41. Costs nothing to test; the only question is quality on longer
   desktop inputs. **Try this before touching the free cap.**
2. ~~Cut the free cap to 30/month.~~ **Taken 2026-08-21**, ahead of lever 1 — `desktop.plan_limits.free.month` is 30 and `PlanPricing.freeMonthlyRewrites` matches it. Lever 1 is still untried and still the cheaper move.
3. Require a card for the free tier.

Account farming (a fresh account per 30 rewrites) is worth ¥20 of AI and is
already slowed by the email-confirmation signup flow (`AGENTS.md` §14). Not worth
engineering against.

---

## 8. What this requires in the codebase

Nothing below exists yet.

### Stripe — rebuild the catalog, keep the account

Live account `acct_1T2WK5CZmA6ItMhq` is named **PromptOS** and belongs to the
`prompt/` Electron app. Audited 2026-08-08:

- 2 products (Pro "1,000 generations/month, memory enabled", Power "10,000
  generations/month") — a different product's metering model.
- **16 active prices for 2 products**, two generations created 6 hours apart. Pro
  JPY ¥980/mo exists twice (`price_…m6vpCIMq`, `price_…wuzBUMqg`); ¥9,800 vs
  ¥9,600 yearly; Power ¥2,500 vs ¥2,480.
- No `default_price`, `lookup_key`, `nickname`, or `metadata` anywhere.
- `tax_behavior: "unspecified"` on all 16 — a defect for a JP consumer product
  (総額表示義務).
- One webhook → `https://fedzebrojuvixsiajjef.supabase.co/functions/v1/stripe-webhook`,
  i.e. **a different Supabase project**, not `eercsucvxnszqletxued` where
  `auth.users` lives. 4 events; missing `checkout.session.completed` and
  `invoice.payment_failed`.
- Lifetime revenue: **1 subscription, canceled 81 minutes after creation
  (`feedback: switched_service`), 0 active.** Nothing to preserve.
- `stripe-webhook`, `create-checkout-session`, `create-portal-session` are
  **deployed-only** on the PromptOS project — no source in any local repo. Only
  `prompt/src/ipc/billing-handlers.js` (100 lines, client side) survives, useful as
  a reference for the Swift equivalent.

Keep the account — KYC is done and redoing 事業者確認 costs days. Deactivate the 2
products and 16 prices, then create:

| | Amount | lookup_key | tax_behavior |
|---|---|---|---|
| 敬語ボタン Pro 月払い | ¥1,480 / month · **$12 / month** | `pro_monthly_jpy` | `inclusive` |
| 敬語ボタン Pro 年払い | ¥14,400 / year · **$120 / year** | `pro_yearly_jpy` | `inclusive` |

One product with `statement_descriptor` set and `metadata.plan = "pro"`, so the
webhook maps by lookup key and never by price ID. (`billing-handlers.js` takes
`priceId` **from the client** — do not copy that; validate server-side.) One
webhook at `eercsucvxnszqletxued` with 6 events: the 4 existing plus
`checkout.session.completed` and `invoice.payment_failed`.

**USD is `currency_options[usd]` on those same two prices — not a second pair, and
not a second product.** Three reasons, and the first is the one that decides it:

1. **The Customer Portal.** §2 of `docs/billing.md` already records that both
   intervals must sit on one Product or E-DOWN is unbuildable. Four prices across two
   currencies reintroduces the same class of problem one level down — the portal would
   have to be told which two of the four a given subscriber may switch between.
2. `pro_monthly_jpy` / `pro_yearly_jpy` stay the only sellable keys, so the checkout
   function's allowlist does not grow and §2's "the lookup key finds the price to
   *sell*, the product id is the entitlement check" is untouched.
3. Nothing has to be migrated. Existing subscriptions keep their price object.

The `_jpy` suffix now names each price's **default** currency rather than the charged
one. Renaming would need `transfer_lookup_key: true`, which §2 records as the thing
that strips the key off the old price — so it is documented rather than renamed.

**Two coupons for the welcome offer (§1), and no promotion codes:**

| coupon | amount_off (jpy) | currency_options[usd].amount_off | duration |
|---|---|---|---|
| `welcome_monthly_33` | ¥500 | $4 | `repeating`, 3 months |
| `welcome_annual_33` | ¥4,800 | $40 | `once` |

Applied by `desktop-checkout` via `discounts: [{coupon}]`, from a server-side row the
client cannot influence. **`discounts` and `allow_promotion_codes` are mutually
exclusive** — a Checkout Session takes at most one coupon or code — so a discounted
session deliberately has no promotion-code box, and an undiscounted one keeps it for
cohort codes like 「最初の100名は初年度 ¥9,800」.

### Supabase

- `desktop.subscriptions` — `user_id`, `stripe_customer_id`,
  `stripe_subscription_id`, `plan`, `status`, `current_period_end`,
  `cancel_at_period_end`. Per `AGENTS.md` §12 the migration lands in the iOS repo
  (one project, one history) even though nothing on iOS reads it.
- `month:YYYY-MM` bucket keys in `desktop.usage_buckets`. Extend
  `desktop_delete_old_usage_buckets` to GC them — and note §6's warning that GC
  runs on `updated_at`, never on `bucket_key`.
- `reserveUsage` in `desktop-rewrite/index.ts` reads fixed env limits today. It has
  to look up plan state first and choose the limit set: free 30/month, Pro
  1,000/month, both under the existing 120/hour + 12/minute. **There is no daily
  cap.** `desktop.plan_limits.day` is null on every plan as of 2026-08-21 and
  `desktop_reserve_usage` skips the check when it is — a second, differently-shaped
  wall that no copy mentioned and the usage row could not show. The day bucket is
  still written, so per-day usage stays observable; a number in that column
  re-enables the brake.
- **A read path for the user's own usage**, which `AGENTS.md` §10 lists as out of
  scope. §3 makes it required: the 今月 21 / 30 readout has to be true. One new
  `SECURITY DEFINER` function granted to `authenticated` — the first `desktop_*`
  entry point that is not `service_role`-only, so re-verify the
  `has_function_privilege` assertions in the migration.
- Three new Edge Functions: `desktop-checkout`, `desktop-portal`,
  `desktop-stripe-webhook`.

### Mac app

- Paywall panel on the overlay for the cap-hit, **¥1,200/月相当 preselected**.
- Plan state + 今月の残り回数 in the ホーム usage row (§14), which today reads
  `history.json` and will need the server read above.
- **Apple Pay in Stripe Checkout.** Highest-impact single item here: on a Mac,
  Touch ID checkout removes card entry entirely, and card entry is the largest
  drop-off in a JP subscription funnel.
- 「いつでもワンクリックで解約」 on the paywall, wired to the Stripe Billing
  Portal. Raises conversion in Japan and is what 特商法 expects.
- 適格請求書 (インボイス) on receipts if the company is 登録済み — a ¥1,480 tool
  gets expensed.

### Instrumentation

`desktop.rewrite_events` already carries enough for the first two:

1. rewrites/month per user, free vs Pro — validates the 15 and 150 assumptions
   that §6 rests on
2. day-2 / 7 / 30 retention
3. free → paid conversion, and the rewrite count at which it happens
4. cap-hit events tagged **quota** vs **abuse brake** — a 429 does not distinguish
   them today, so cap-hits are invisible
5. free-tier COGS as a share of MRR (the §7 trigger)

---

## 9. Documents this contradicts

Fix before implementation; all of these currently assert the opposite:

| File | What it says |
|---|---|
| `AGENTS.md` §2 | "Shared login, shared buttons, shared billing" |
| `AGENTS.md` §6 | same, in the backend section header |
| `AGENTS.md` §12 | "Shared billing was decided, but not … whether desktop and keyboard draw from one quota or two" — now: two, and mobile has none |
| `AGENTS.md` §14 | "`profiles` has no plan column … nothing true to put in that block" — still true of `profiles`, but plan state now exists in `desktop.subscriptions`, so a sidebar plan card becomes possible |
| `landing/content.md` §10, `landing/src/data/pricing.js` | ¥1,180 / ¥11,800, 1日10回, 「上限なし」, 「iPhone版の上限も解除」, 「iPhone版とMac版で、ひとつの契約」 — **all placeholder, all wrong.** The last two are actively misleading: mobile is free and separate |
| `AGENTS.md` §17 | "Amounts never change with the language" — reversed for English on 2026-08-10; the sentence now describes 日本語 and 简体中文 only. **Corrected** |
| `../web` `/en` | Quoted ¥1,480 / ¥14,400 to a visitor the app charges $12 / $120. **Fixed 2026-08-10** — see §10 |
| `../web/app/legal/page.tsx` | Said 「税込」 and 「価格はすべて消費税を含む総額です」, which a 免税事業者 may not claim, and listed no USD. **Both fixed 2026-08-10.** Its App Store billing claim (rows 58-99) is a separate defect and is **still there** |
| `../web/app/legal/page.tsx:58-99` | Tells users subscriptions are billed through the App Store and canceled in iOS Settings. User-facing and legally load-bearing — the Mac app bills through Stripe, and the iOS app sells nothing |

---

## 10. Still open

- **Whether desktop should default to the cheap providers** (§7 lever 1). The only
  question is quality on longer inputs, and the answer changes the cost model by
  16×. Worth testing before launch.
- ~~The landing page still quotes yen in every language.~~ **Done 2026-08-10.**
  `../web`'s `/en` renders `$0` / `$12` (and `$10` · `$120` on the yearly toggle) while
  `/` and `/zh` are unchanged at ¥0 / ¥1,480 — verified against the built pages, not
  the source. `components/mac/data/pricing.js` now carries a `PRICE.jpy` / `PRICE.usd`
  table and a `currencyFor(lang)` that is the site's copy of the app's
  `BillingCurrency.forInterface`; **the two have to agree or the page quotes a price
  checkout will not honour.** The English 「2ヶ月分以上お得」 also lost its "over":
  $144 − $120 is exactly two months, and only the yen plan needs the 以上.
  `app/legal/page.tsx` gained the USD amounts as well — a 特商法 販売価格 disclosure
  listing only yen understates what an English buyer is charged — and lost its
  「税込」/「価格はすべて消費税を含む総額です」, which §9's table had flagged and which
  `docs/billing.md` §10 says is not a claim a 免税事業者 may make. That page was the
  last place still making it.
- **Whether the welcome offer's 72 hours and 33% are the right numbers.** Both were
  chosen rather than measured. `desktop_welcome_offer_shown` / `_accepted` and the
  `offer_applied` property on the checkout event are what will answer it, and neither
  has carried an event yet.
- **Whether the ホーム numbers follow the account** (`AGENTS.md` §12). The §8 usage
  read answers half; local history stays per-Mac.
- The 15 and 150 rewrites/month assumptions in §6. Both are 【推測】 and both are
  measurable within a month of launch.

---

Sources for §5's rates: [OpenAI — advancing the price-performance frontier with
GPT-5.6](https://openai.com/index/advancing-the-price-performance-frontier-with-gpt-5-6/),
[OpenRouter — GPT-5.6 Terra](https://openrouter.ai/openai/gpt-5.6-terra).
