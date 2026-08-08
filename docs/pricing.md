# Pricing — 敬語ボタン Mac

**Read `AGENTS.md` first.** This file is the pricing and billing authority. Where
it disagrees with `landing/src/data/pricing.js` or `landing/content.md` §10, this
file wins — those numbers were transcribed from a reference site as layout
placeholders and were never commitments.

Status: **prices are final for launch. Nothing is implemented.** No code in
`supabase/` or `App/` enforces any of this yet. The cost model below runs on
GPT-5.6 Terra's list price, so there is no longer an unknown blocking the numbers.

---

## 1. The plan — final

| | 無料 | Pro |
|---|---|---|
| 書き換え | **50回 / 月** | **1,000回 / 月**（約33回/日） |
| リセット | 毎月1日（暦月） | 毎月1日（暦月） |
| 価格 | ¥0 | **¥1,480 / 月** ・ 年払い **¥1,200 / 月相当** |
| 年払い総額 | — | ¥14,400 / 年（**2ヶ月分以上お得**） |
| カード登録 | 不要 | 必要 |
| 無料トライアル | **なし** — 無料プランがその役割 | — |

**iPhone版 (`AIキーボード`) は無料のまま、上限も現状のまま、課金は一切ない。** See §2.

### Not in the plan

- **No Premium / third tier.** Volume is the only differentiation axis available —
  one model, and `AGENTS.md` §10 defers screen context, streaming, and teams. Add
  a tier when Pro contains something worth segmenting on, not before.
- **No trial.** See §3.
- **No usage-based billing.** A ¥0.66 unit is more accounting than revenue.

### Why these numbers

| Decision | Reason |
|---|---|
| 50 free | Enough to experience real value; a habitual user reaches the wall naturally within a month |
| 1,000 Pro | ~33/day — beyond any human writing pace, and it holds the margin if someone does reach it (§7) |
| ¥1,480/月 | The monthly anchor |
| ¥14,400/年 | Produces a clean **¥1,200/月相当** that compares directly against ¥1,480, at a ~19% discount |
| ¥1,200 shown first | The annual plan is sold on the monthly-equivalent number; ¥14,400 is secondary |

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

The 50回/月 free tier is the trial, and a better one: it never expires, so it
can't run out while someone is on holiday; it demonstrates value on real work in
real apps; and 50 rewrites is enough for anyone who will love this to know.

A card-required trial would add a second, worse gate — JP consumers are averse to
auto-converting card trials, 特商法 imposes 自動更新 disclosure obligations, and
it is a standing 解約 complaint source. A no-card trial on top of a no-card free
tier is redundant by construction.

**So the cap-hit is the paywall, and that moment is the entire conversion event.**

| When | What the user sees |
|---|---|
| 40 / 50 used | Quiet 残り10回 note in the ホーム usage row |
| 48 / 50 used | 残り2回 — 今月分の書き換えがまもなく上限に達します |
| 50 / 50, on press | Upgrade panel on the overlay, **annual (¥1,200/月相当) preselected** |
| Always | Persistent 今月 34 / 50 readout in the main window's usage row |

That last row is a **requirement**: a quota the user cannot see is a quota that
ambushes them, which is the worst conversion outcome available. It makes the
server-backed usage read that `AGENTS.md` §10 lists as out of scope into required
work — see §8.

---

## 4. Prices

### Annual

| | 表示 | 総額 |
|---|---|---|
| Primary | **¥1,200 / 月相当** | — |
| Secondary | — | ¥14,400 / 年 |

¥1,480 × 12 = ¥17,760. Annual saves **¥3,360**, which is 2.27 months of the
monthly price → **「2ヶ月分以上お得」**, a **18.9% discount**. ¥14,400 ÷ 12 is
exactly ¥1,200, which is the point: the buyer compares ¥1,200 against ¥1,480 in
one step, with no arithmetic.

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
| 50 | **¥32.8** | free cap — the worst a free user can cost |
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
2. Cut the free cap to 30/month.
3. Require a card for the free tier.

Account farming (a fresh account per 50 rewrites) is worth ¥33 of AI and is
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
| 敬語ボタン Pro 月払い | ¥1,480 / month | `pro_monthly_jpy` | `inclusive` |
| 敬語ボタン Pro 年払い | ¥14,400 / year | `pro_yearly_jpy` | `inclusive` |

One product with `statement_descriptor` set and `metadata.plan = "pro"`, so the
webhook maps by lookup key and never by price ID. (`billing-handlers.js` takes
`priceId` **from the client** — do not copy that; validate server-side.) One
webhook at `eercsucvxnszqletxued` with 6 events: the 4 existing plus
`checkout.session.completed` and `invoice.payment_failed`.

### Supabase

- `desktop.subscriptions` — `user_id`, `stripe_customer_id`,
  `stripe_subscription_id`, `plan`, `status`, `current_period_end`,
  `cancel_at_period_end`. Per `AGENTS.md` §12 the migration lands in the iOS repo
  (one project, one history) even though nothing on iOS reads it.
- `month:YYYY-MM` bucket keys in `desktop.usage_buckets`. Extend
  `desktop_delete_old_usage_buckets` to GC them — and note §6's warning that GC
  runs on `updated_at`, never on `bucket_key`.
- `reserveUsage` in `desktop-rewrite/index.ts` reads fixed env limits today. It has
  to look up plan state first and choose the limit set: free 50/month + 20/day,
  Pro 1,000/month + 100/day, both under the existing 120/hour + 12/minute.
- **A read path for the user's own usage**, which `AGENTS.md` §10 lists as out of
  scope. §3 makes it required: the 今月 34 / 50 readout has to be true. One new
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
| `../web/app/legal/page.tsx:58-99` | Tells users subscriptions are billed through the App Store and canceled in iOS Settings. User-facing and legally load-bearing — the Mac app bills through Stripe, and the iOS app sells nothing |

---

## 10. Still open

- **Whether desktop should default to the cheap providers** (§7 lever 1). The only
  question is quality on longer inputs, and the answer changes the cost model by
  16×. Worth testing before launch.
- **USD pricing**, if the LP goes bilingual. ¥1,480 ≈ $10/月, ¥14,400 ≈ $96/年.
- **Whether the ホーム numbers follow the account** (`AGENTS.md` §12). The §8 usage
  read answers half; local history stays per-Mac.
- The 15 and 150 rewrites/month assumptions in §6. Both are 【推測】 and both are
  measurable within a month of launch.

---

Sources for §5's rates: [OpenAI — advancing the price-performance frontier with
GPT-5.6](https://openai.com/index/advancing-the-price-performance-frontier-with-gpt-5-6/),
[OpenRouter — GPT-5.6 Terra](https://openrouter.ai/openai/gpt-5.6-terra).
