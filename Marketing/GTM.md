# GTM.md — KeigoButton Desktop

**Read `../AGENTS.md` for what the product does and `../docs/pricing.md` for what it
costs.** This file is the go-to-market authority: positioning, channel, funnel, and
the order in which we do things. Where it disagrees with a slide deck or an ad
account, this file wins.

Convention: unverified claims are tagged **[Estimate]**. Everything untagged is a
fact taken from the product, the schema, or the live site.

Status: **pre-launch.** macOS 0.1.5 is signed, notarized and shipping through
Sparkle. The iOS keyboard is live and free. No paid marketing has run. No content
format has been validated.

---

## 1. What we are selling

**Use AI on your writing without leaving the app you are already in.**

The user selects text — or starts a reply — inside Slack, Gmail, Notion, X, LinkedIn,
anything with a text field. They hover the bar above the Dock, press one of their own
buttons, and the text is rewritten in place. Their buttons are whatever they
repeatedly do: Polish, Shorten, Make casual, Translate, Fix grammar, Make persuasive,
Turn into email, Summarize, or a free-text instruction.

The sentence that actually sells it:

> Your most-used AI prompts become one-click actions available anywhere on your Mac.

### The one mistake that would cost us the category

**Do not market this as "an app that converts text into keigo."** Keigo is one preset
out of a general-purpose product. A product framed as a keigo converter has a ceiling
of about one use case, one country, and one kind of user, and every asset built on
that frame has to be thrown away when we try to leave it.

The correct frame is a **customizable AI writing layer for the Mac**. Keigo is the
door in Japan, not the room.

---

## 2. Two markets, two stories, one product

The Japanese and English go-to-markets share a binary and share nothing else. Treat
them as separate campaigns with separate creative, separate landing routes, and
separate price points. They are already separated in the product: interface language
decides the button packs, the writing language, and the currency.

| | 日本語 | English | 简体中文 |
|---|---|---|---|
| Landing route | `keigobutton.com/` | `/en` | `/zh` |
| Interface | Japanese | English | Chinese |
| Buttons write | Japanese | English | **Japanese** |
| Billed in | ¥1,480 / ¥14,400 | **$12 / $120** | ¥1,480 / ¥14,400 |
| Packs | 定番 / 仕事 / 海外 / 日本語 / SNS | Starter / Work / Outreach / Polish / Social | the Japanese five |

Currency is chosen by **interface language only** — never by IP. The displayed price
is the charged price. English is priced roughly 22% above Japanese at spot
($12 ≈ ¥1,800 vs ¥1,480); that gap is accepted, and it means an English conversion is
worth meaningfully more than a Japanese one.

简体中文 is a Chinese speaker **working in Japan**. Their card is a Japanese card and
their buttons write Japanese. For GTM purposes they are a segment of the Japanese
market who cannot read Japanese ads — a distinct creative need, the same funnel and
the same price.

### 2.1 Japan — keigo is the hook, not the product

Japanese users need no education on the pain. "Turn this into proper business
Japanese" is instantly legible, emotionally charged, and specific enough to stop a
scroll. That is exactly what a hook has to be. Then the product expands underneath
them into a general writing tool, and the expansion is what retains them.

So: **the hook is 敬語, the second beat is everything else.** A slideshow whose first
slide is keigo and whose fourth slide is "and it also shortens, translates, and writes
your replies" does both jobs.

Priority audiences, in the order their content should be produced:

1. **Young professionals / office workers** (largest, cheapest to reach) — polishing
   Slack before sending, making email concise, generating replies from a thread they
   were just sent. Highest volume of daily triggers, so highest retention.
2. **Sales / recruiting / customer-facing** (highest willingness to pay) — warmer or
   more persuasive messages, tone per customer, notes into a follow-up email. They
   already believe writing is revenue, so price resistance is lowest here.
3. **Students / job seekers** (highest content virality, lowest LTV) — mail to
   professors and recruiters, ES and application text. Enormous TikTok presence and
   seasonal spikes; expect free-tier-heavy behavior and treat them as a reach engine
   that converts a thin slice.
4. **Power AI users** (smallest, best evangelists) — they get the real pitch
   immediately: stop retyping your ChatGPT prompts, make them buttons.

### 2.2 English — the keigo word never appears

The English market has no keigo concept and no interest in one. The product is a
**system-wide AI writing shortcut**:

> Turn any prompt you use repeatedly into a button that works in every app.

Priority audiences:

1. **Heavy ChatGPT / Claude users** — the sharpest pain, the shortest explanation.
   The whole pitch is deleting the copy → tab-switch → prompt → copy → paste loop.
   These people already pay for AI tools, so price is not the objection.
2. **Non-native English speakers** — "make my English sound natural," "fix grammar
   without changing my meaning," tone control. Structurally the same emotional pain
   as keigo in Japan, and the closest thing to a second hook we have.
3. **Founders / sales / marketers** — persuasive copy, rewritten outreach, adapting
   one message for different audiences, custom brand-voice buttons.
4. **Knowledge workers** generally — the broad case, the weakest hook. Do not lead
   here.

The English asset that carries the most weight is a **custom-button demo**, not a
rewrite demo. The rewrite is table stakes now; the button that encodes *your* prompt
is the differentiator.

---

## 3. The channel thesis

**Indie distribution is one game: can we find a high-converting, mass-producible
TikTok slideshow format?** Everything else is downstream of that.

The volume model we are betting on:

- 1 install per 100 views is the target conversion of a working format.
- 1,000 average views per post is a conservative floor for a working format.
- 5 posts/day × 4 accounts = 20 posts/day → **20,000 views/day → 200 installs/day**.

Once a format works, Claude Code can mass-produce it indefinitely. The hard part is
only the first one, and that is precisely why it is the moat: a format that pulls
views but not installs, or installs but not views, or quality that cannot be
replicated, all fail. Expect to research what is already working, copy it closely,
and iterate many times before anything holds. Once it holds, the pipeline can be
driven by cron toward roughly zero hours of operating time.

### 3.1 The revenue math, on our numbers

The 1-in-100 and 5×4 posting shape comes from another founder's app on a ~¥5,000
annual plan. The shape transfers; the arithmetic does not. Ours, from
`../docs/pricing.md`:

| Input | Value | Source |
|---|---|---|
| Blended net revenue per payer | **¥1,333 / month** | `pricing.md` §6 — the JPY/USD, monthly/annual, offer/list blend |
| COGS per rewrite | **¥0.656** | `pricing.md` §5, GPT-5.6 Terra list |
| Free user COGS | **~¥9.8 / month** | 15 rewrites/month average |
| Pro user COGS | **~¥98 / month** | 150 rewrites/month average |
| Break-even conversion | **0.79%** | At assumed usage; **1.57%** if every free user maxes 30 |

At the thesis's full output — 200 installs/day — and 3% install-to-paid:

- 6 new payers/day → **¥8,000/day of new MRR**, or **~¥240,000 of MRR added per month**
- Gross margin at 3% conversion sits between the 56% and 75% rows of `pricing.md` §6

**The number to respect is the break-even row, not the margin row.** 0.79% break-even
looks like enormous headroom, and it is — but only while the 50-rewrite cap stays a
ceiling rather than an expectation. If free users actually use what they are given,
break-even moves to 1.57%. That is the whole point of the 2026-08-21 cut from 50 to 30:
the maxed-out case used to break even at 2.59%, inside the range a 3% target can miss.

**And free-tier COGS is the one cost that scales with installs instead of revenue.**
This is the structural tension in a TikTok strategy specifically: the channel's whole
purpose is mass low-intent installs, and every one of them is a free account
generating cost forever. At the December volumes in §6, free-tier COGS reaches roughly
a quarter of MRR. It is monitored monthly and it has a known fix — routing the free
tier to a model at ¥0.0413/rewrite, **15.9× cheaper**, erases the line entirely.

### 3.2 The problem the model ignores, and the answer

**The volume math comes from App Store apps, where a view converts to an install with
one tap on the same device the view happened on. We are a notarized DMG.** A TikTok
viewer on a phone has to remember us, get to a Mac, visit `keigobutton.com`, download
a DMG, drag to Applications, open past Gatekeeper, and grant Accessibility in System
Settings before the product does anything at all. That is six steps across two
devices, and it will not convert at 1-in-100.

This is the single largest GTM risk and it cannot be fixed by better creative. There
is no Mac App Store option — the App Sandbox makes cross-process Accessibility
impossible, so Developer ID plus notarization is the only path that will ever exist
for this app.

**The answer is already built: the iPhone keyboard is the top of funnel.**

- `AIキーボード` is on the App Store, is free, stays free, and has no billing.
- It is a one-tap install on the device the view happened on.
- **The account and the `user_prompts` buttons are shared.** A user who set up
  buttons on their phone opens the Mac app and their buttons are already there.

So the canonical loop is:

```
TikTok (phone) → free iOS keyboard install → account + buttons configured
   → "this also works on your Mac" → DMG → Mac app is the paid surface
```

Mac-direct acquisition still runs — it is the right funnel for the English
ChatGPT-power-user segment, who are at a laptop when they watch — but **the Japanese
consumer funnel should be measured as install-to-iOS, not install-to-Mac.** Judging
Japanese TikTok creative on Mac installs will make every working format look broken.

### 3.3 The organic asset we already have

`keigobutton.com` ranks in Japanese. `/keigo-henkan`, `/keigo-check`, `/keigo-test`
and `/reibun/*` exist to win Japanese keigo queries and are deliberately Japanese-only
— there is no English search behind 「敬語 例文」. This is compounding, already-paid-for
demand from exactly the user our keigo hook targets, and it is the one channel that
does not depend on finding a format.

Two consequences:

- **Never break those URLs.** They are unprefixed Japanese for a reason; `/en` and
  `/zh` were added beside them rather than moving them.
- **Those pages need a Mac-app path**, not just a keigo answer. A user who came for
  a keigo example is one step from the product that produces them.

---

## 4. The format library

The reference set in `reference/sshook/` and `reference/sscontent/` points at one
proven shape, and it is the right first bet.

### 4.1 Format A — the Mac app roundup (primary)

What the references are: a photographed MacBook, a large two-line hook in white sans
("My must have… **MacBook Apps**"), then one slide per app — big icon, app name, two
or three sentences of plain-language benefit, a screenshot of it running.

Why it is the right first format:

- **It is identity content, not an ad.** The viewer watches because they own a
  MacBook, and roundups of any kind reliably pull views.
- **We are one slide.** The post does not have to sell us; it has to get to slide 4.
- **It is trivially mass-producible.** Swap the photo, reorder the apps, change the
  hook, keep our slide. Claude Code can generate hundreds of variants.
- **The audience is pre-qualified as Mac owners**, which is the entire reason our
  install friction exists. This format is the friction's natural counter.

Variants visible in the reference set, all worth testing: `must-have MacBook apps`,
`MacBook settings tips` (tips format with our app as the payoff), and an
aesthetic/cozy treatment (`Cozy apps for MacBook Neo`, warm photo, script type,
"productivity focused" chip) which targets a different, younger, largely female
audience with the same skeleton.

### 4.2 Format B — the in-app rewrite proof (Japan)

Screen recording, no face, no voice: rough Japanese in a Slack box → hover → 敬語 →
the sentence becomes proper business Japanese in place. The whole value proposition is
legible in under three seconds with sound off.

Hook lines to test: 上司に送る前のこれ, 敬語が合ってるか毎回不安な人, this-took-me-10-minutes-now-it-takes-1.

### 4.3 Format C — the custom button (English)

"I turned my most-used ChatGPT prompt into a button." Show the button being created,
then used in three different apps in a row. The three-apps-in-a-row beat is what
communicates *system-wide*, and nothing else does.

### 4.4 Format D — reply mode

Copy the message you received, hover, describe how you want to answer, get the reply.
This is the most impressive single feature we have and the least self-explanatory, so
it needs the longest setup and belongs in slideshows rather than 5-second clips.

### 4.5 Format E — the tone-gap rewrite (video)

Not a slideshow. A short video: POV title → an unhinged message meant for a close
friend, typed into Outlook or Slack → one beat of regret → an absurdly corporate
rewrite. The joke is the gap between what a 22-year-old wants to type and what they
send, and **the product is the thing that closes the gap**, which is why the demo and
the punchline are the same three seconds.

Two production variants. **E-2 is a variant of E-1, not a second format** — the only
difference between them is whether a human is on screen:

| ID | Build | Cost |
|---|---|---|
| **E-1** | Pure rewrite. No face, no voice, no cuts. Phone filming a monitor, native Outlook/Teams/Slack UI, imperfect office light, trending audio. Message appears → deleted → corporate version | ~¥0, unlimited variants |
| **E-2** | Same post with 2–4 reusable human clips cut in — confident typing → pause → the realisation → back to work | One shoot, then ~¥0 |

Why it earns a test slot while Format A is still unresolved:

- **The product is inside the joke.** Select the text, press the button, the sentence
  changes in place. Format A has to survive four unrelated slides before we appear at
  position 3; here the proof is the payoff.
- **It gives English the emotional hook §2.2 does not have.** "Knowledge workers who
  write a lot" is a category, not a hook. "Fear of sounding wrong to someone senior" is
  the same emotional shape keigo has in Japan, and it is the first English angle with
  that property.
- **E-1 is as mass-producible as a slideshow** — the copy pair is the whole asset, and
  copy pairs can be generated indefinitely.

Three things it must not be allowed to become:

1. **A format with no product in it.** The organic cut — type, delete, retype polished
   — will pull views and convert nobody. That is a structural `OFFER FAIL` by
   construction, not a result. The button press is the CTA; it stays in every post, and
   the caption CTA and link stay constant per §4.6.
2. **A format sold to an audience that cannot buy.** The joke is set in a corporate
   office, much of that audience works on a Windows laptop we will never ship (§9), and
   all of them are watching on a phone. **Film on a MacBook** so the frame pre-qualifies
   the viewer the way §4.1 does, and judge this format on **iOS-keyboard installs** per
   §3.2 — scoring it on Mac installs will read as dead when it is working.
3. **An unwritten amendment to §3.** The channel thesis bets on a *slideshow* format.
   E-1 fits that bet; **E-2 does not scale the same way** — its variant supply is bounded
   by clip inventory, so it cannot run 5 posts/day × 4 accounts without reading as
   repetition. If both clear the gate, E-1 is the volume engine and E-2 is what gives an
   account a face worth following.

**日本語 runs the same format on a different joke, not a translation.** English is
slang in Outlook. Japanese is **タメ口 → 敬語**: a 部長 addressed with no 敬語 at all, which
is a sharper social taboo and needs no slang to carry it. That is §2.1's keigo hook doing
exactly its job — instantly legible, emotionally charged, and the product is the thing
that closes the gap. §9 still holds: the two tracks share a skeleton, never a script, and
per `FORMAT-TESTS.md` §1.5 their samples are counted separately.

**For filmed E-2, shoot the reaction clips with a real person, once.** Not image-to-video: the joke
depends on the viewer believing someone nearly sent that message, and an AI face on an
account selling an AI writing tool spends credibility at exactly the point the format
needs it. If no person is available, frame hands and the monitor instead.

**AI avatar reaction + demo template — audio rule.** This separately used template
must have all original audio removed before upload, including generated speech,
room sound, sound effects and any existing music. Replace it with the audio track
from one file in `Marketing/assets/audio/` (the library contains screen recordings;
use their audio only). Fit the replacement to the full video length: trim a longer
track or loop a shorter one, with a brief fade at the end. Preserve the visuals,
cuts, on-screen text and timing. Upload the same corrected export for its TikTok
and Instagram pair. This rule applies to every future upload and to queued media
replacements; the six pending posts were corrected on 2026-10-02, recorded in
`PUBLISHING.md` §5.

The production spec — POV bank, the four-ingredient line recipe, the corporate phrase
bank, the clip inventory, and the E-1/E-2 paired test design — lives in
`FORMAT-TESTS.md`.

### 4.6 Production rules

- **One format, many variants, before a second format.** Four half-tested formats
  teach nothing. Format E (§4.5) is the sanctioned exception, on one condition: it runs
  as its own sample on its own account, never interleaved into an account that is
  mid-sample on Format A. Two formats sharing an account produce one unreadable result,
  not two.
- **Every post ends on the same CTA and the same link.** Attribution is worthless
  otherwise.
- **AI avatar reaction + demo uploads use library audio only.** Apply §4.5's audio
  rule before handing the MP4 to the scheduler; never upload the original soundtrack.
- **Post the Japanese and English accounts separately.** Different formats, different
  audiences; a mixed account trains the algorithm on nobody.
- 4 accounts per language once a format holds, 5 posts/day each. Not before.

---

## 5. The conversion architecture

We are not starting from zero here — the product's paid path is built and deliberate.

- **Free tier is the trial.** 30 rewrites/month (cut from 50 on 2026-08-21), no card, resets the 1st of each
  calendar month. There is deliberately no time-limited trial: the free plan does that
  job. Marketing should say "free to start," never "free trial."
- **Pro is 1,000 rewrites/month** (~33/day). Volume is the only axis; there is no
  third tier and should not be one until Pro contains something worth segmenting on.
- **First run is 11 steps**, and the money ask is step 11 — after the user has
  watched their own text rewritten in their own apps, before the flow hands the app
  over. That ordering is the argument for paying, and it should not be moved.
- **The welcome offer: 33% off the first period, for 72 hours.** ¥9,600 / $80 for a
  first year, or ¥980 / $8 a month for three, then list. Once per account, minted and
  enforced server-side, surviving reinstalls and second Macs.
- **The deadline is real and must stay real** in every asset that mentions it. An
  unenforced countdown is a 景表法 有利誤認 exposure, not a growth tactic. Same reason
  the struck-through list price is defensible: it is what this account pays from the
  second period on.
- **Every offer surface states the renewal price and that it renews** (特商法第12条の6
  ①分量 / ②対価). A discounted first period quoted without the second number is half a
  price. This applies to ads and landing copy exactly as it applies to the app.
- **Declining costs nothing** — a home-screen card carries the same price and the same
  remaining time. Marketing can safely point at the offer without the page being a
  wall.

One copy constraint worth knowing: we are a 免税事業者 and not an 適格請求書発行事業者,
so **no asset may claim 税込**. The app and the site both stopped saying it.

---

## 6. The goal, and the KPIs that ladder into it

### 6.1 The number we are chasing

> **By 2026-12-31: 450 paying subscribers, ¥600,000 MRR, ¥7.2M ARR run-rate.**

One number, three ways of saying it, because at a fixed price they are the same
number: 450 payers × ¥1,333 blended ≈ ¥600,000 MRR, and MRR × 12 is the ARR run-rate
we exit the year on. **Paying subscribers is the north star** — ARPU is set by the
pricing page and is not something we move week to week, so subscribers is the only
term in the equation the work actually touches.

This is deliberately more aggressive than `pricing.md` §6's base case (¥26,700 MRR /
¥320,000 ARR), and the difference is the entire reason this file exists: that model
converts **only the existing mobile base** over six months. This goal adds the content
engine on top of it.

**It is contingent on one gate.** The whole number rests on a working slideshow format
existing by 2026-09-30. If Phase 1 has not produced one by then, the December target
is not missed by 20% — it resets to the floor scenario below, and the honest move is
to reset it openly rather than carry a number nobody believes.

| Scenario | Condition | Dec MRR | Dec ARR run-rate | Payers |
|---|---|---|---|---|
| **Floor** | Format lands in November | ~¥150,000 | ¥1.8M | ~110 |
| **Base — committed** | Format lands in September, 3% conversion, 10% churn | **¥600,000** | **¥7.2M** | **450** |
| **Stretch** | Above, plus the English track lands independently at 4% | ~¥950,000 | ¥11.4M | ~710 |

### 6.2 The month-by-month ladder

Installs are the input we control through posting volume; everything right of that
column is arithmetic on 3% conversion, ¥1,333 blended ARPU, and 10% monthly logo
churn. **[Estimate]** — every row is a model until §7's funnel is instrumented.

| Month | Phase | Installs | New payers | Net payers | MRR | Exit ARR run-rate |
|---|---|---|---|---|---|---|
| **Aug** (12 days left) | 0 — instrument | ~50 | 1 | 1 | ¥1,300 | ¥16,000 |
| **Sep** | 1 — find the format | 800 | 24 | 24 | ¥32,000 | ¥384,000 |
| **Oct** | 2 — scale to 2 JP accounts | 2,500 | 75 | 97 | ¥129,000 | ¥1.55M |
| **Nov** | 2 — 4 JP accounts, EN starts | 5,000 | 150 | 237 | ¥316,000 | ¥3.79M |
| **Dec** | 2 — 4 JP + 4 EN | 7,500 | 225 | 438 | ¥584,000 | **¥7.0M** |

The December row lands at 438 payers and ¥584,000. **The committed goal is rounded up
to 450 and ¥600,000 deliberately** — a target should sit slightly above the model that
produced it, and the gap is one good week of posting.

Net payers compound as `prior × 0.9 + new`, which is why the curve steepens: churn
takes 10% of a small base while acquisition adds to it. It also means **a slipped
month is not recoverable by working harder in December** — the compounding it was
supposed to seed never happens. September is worth more than its own row.

Two structural notes about this table:

- **Dec's 7,500 installs assumes 8 accounts across 2 languages**, above the thesis's
  4-account / 6,000-per-month output. The English track is not optional decoration in
  this plan; it is roughly a quarter of the December number.
- **Growth is 100% new-logo growth.** There is no tier above Pro, so there is no
  expansion revenue and **NRR can never exceed 100%** by construction. Gross retention
  is a hard ceiling, not a baseline to expand from. Every SaaS instinct about
  net-negative churn saving a weak acquisition month is unavailable to us.

### 6.3 KPI tiers

**Tier 1 — the goal.** Reviewed monthly.

| KPI | Definition | Dec target |
|---|---|---|
| Paying subscribers | Active `desktop.subscriptions` | **450** |
| MRR | Annual counted as ÷12; offer periods at their actual amount | **¥600,000** |
| ARR run-rate | Exit-month MRR × 12 | **¥7.2M** |
| Blended ARPU | MRR ÷ payers | **≥ ¥1,300** |
| Gross margin | (MRR − free COGS − Pro COGS) ÷ MRR | **≥ 65%** |

**Tier 2 — retention and churn.** The half of the goal that acquisition cannot fix.

| KPI | Definition | Target |
|---|---|---|
| Monthly logo churn | Paid cancels ÷ starting payers | **≤ 10%** |
| Revenue churn | Same, weighted by MRR | ≤ 10% |
| M3 paid retention | Payers still active 3 months after first charge | **≥ 75%** |
| Welcome-offer renewal | Monthly-offer users who survive the ×3 → ¥1,480 step | **≥ 70%** — the classic churn cliff, and the one to watch first |
| Annual mix | Annual as a share of new payers | ≥ 30% — annual cannot churn monthly, so mix is a churn lever |
| W4 install retention | Installs doing ≥1 rewrite in days 22–28 | **≥ 30%** |

**Tier 3 — funnel conversion.** The leading indicators; §7 is how they get measured.

| KPI | Target | Why it matters |
|---|---|---|
| Link tap → install | **≥ 1%** of views | The thesis's core assumption. Split by device — phone taps go to iOS |
| Launch → Accessibility granted | **≥ 60%** | The step most likely to silently kill the funnel; the app does nothing without it |
| Install → first rewrite in 24h | **≥ 40%** | Time-to-value. Below this, no offer will convert |
| First rewrite → offer seen | **≥ 70%** | Anyone who drops out of first run before step 11 is never asked to pay |
| Offer seen → paid | **≥ 8%** | High-intent moment, 72h deadline, 33% off |
| Install → paid (blended) | **≥ 3%** | The number the whole model rests on. Break-even is 0.79–1.57% |

**Tier 4 — engagement and cost health.** Early warning, not scoreboard.

| KPI | Target | Reading |
|---|---|---|
| Rewrites / weekly active user | **≥ 8** | The best churn predictor we have — daily-workflow usage is the retention story |
| Free users hitting the 30 cap | **10–30%** | Below 10%, the free tier is absorbing users who will never feel a reason to pay. Above 30%, break-even moves toward 1.57%. **[Estimate]** — the band was set against a 50 cap and more people will hit 30, so expect this to read high until it is re-baselined |
| Pro users near 1,000 | **< 2%** | The cap must stay a ceiling, not an expectation |
| Free COGS as a share of MRR | **≤ 25%** | Breaching it triggers the cheap-model routing in §3.1, not a price change |
| CAC | **~¥0** | Content is the channel. If paid starts, cap CAC at ¥4,000 — 3.0-month payback on revenue, 4.5 on contribution |
| LTV : CAC | **> 3** | At 10% churn, LTV ≈ ¥13,330 gross / ~¥8,900 contribution at 67% GM |

### 6.4 Monthly gates

Each month passes or fails on one thing. A failed gate stops the next phase rather
than being carried forward.

| Month | Gate |
|---|---|
| **Aug** | Every Tier 3 KPI is *measurable* end-to-end. Revenue is explicitly not a goal |
| **Sep** | One format clears **both** thresholds — ≥1,000 average views **and** ≥1% tap-to-install. This is the year's real gate |
| **Oct** | 3% blended install-to-paid confirmed on ≥2,000 real installs, and Accessibility grant rate ≥60% |
| **Nov** | Monthly logo churn measured at ≤10% on a base of ≥90 payers, and the English track has a candidate format |
| **Dec** | 450 payers. Free COGS ≤25% of MRR |

---

## 7. Instrumentation — the numbers we do not have yet

Desktop reports to its own PostHog project, never the keyboard's. Every number below
is currently unknown, and the entire strategy in §3 is unfalsifiable until they exist.
Standing up this funnel is prerequisite work, not follow-up work.

| Step | What we need to know |
|---|---|
| Views → profile/link tap | Which hook, per format variant |
| Link tap → device | How much Japanese traffic is on a phone (decides §3.2) |
| Tap → iOS install | The real top-of-funnel rate for JP consumer |
| Tap → DMG download | The Mac-direct rate, by language |
| Download → launch | Gatekeeper and drag-to-Applications loss |
| Launch → Accessibility granted | **The step most likely to silently kill the funnel** |
| Granted → account created | Sign-in friction |
| Account → first rewrite | Time-to-value |
| First rewrite → offer seen | How many finish first run at all |
| Offer seen → paid, by currency and by term | The only revenue number that matters |

Two of these decide whether §3's math survives contact: **link-tap-to-install** and
**launch-to-Accessibility-granted**. Measure them before scaling posting volume.

---

## 8. Sequencing

**Phase 0 — make the funnel measurable (before volume).** One tracked link per
format. Confirm the iOS install path and the Mac download path both attribute. Get
the Accessibility grant rate. Nothing below is worth doing until a post's outcome is
observable.

**Phase 1 — find one format that holds.** Format A (§4.1) on one Japanese account,
one variant per day, until a variant clears the two thresholds: views **and**
installs. Research and closely copy what is already working in the Mac-app roundup
niche; do not invent. Expect this phase to be long, and expect most variants to fail
on one threshold while passing the other.

**Phase 2 — mass-produce the winner.** Only after Phase 1. Variant generation via
Claude Code, 4 accounts × 5 posts/day per language, posting driven on a schedule.
Start the English track here with Format C, treated as its own Phase 1 rather than a
translation of the Japanese winner.

**Phase 3 — compound the organic.** Route the existing Japanese SEO spine into the
Mac funnel, and add the English pages that the `/en` route is currently missing.

Do not run paid acquisition before Phase 2. We do not know our conversion rate or our
LTV, and buying traffic against unknown unit economics on a ¥1,480 product is how the
budget disappears.

---

## 9. What we do not do

- **Do not market keigo conversion as the product.** §1.
- **Do not translate Japanese creative into English.** §2.2 is a different product
  story, not a localization of §2.1.
- **Do not promise a free trial.** The free plan is the trial; saying "trial" invites
  the card-required expectation we deliberately avoided.
- **Do not show a countdown the server will not honor**, and do not quote a
  discounted first period without the renewal price. §5.
- **Do not claim 税込** anywhere. §5.
- **Do not promise Windows, a global hotkey, screen context, streaming, or team
  features.** All are explicitly out of scope; a Windows build would be a separate
  codebase. Selling them creates refund exposure, not demand.
- **Do not imply the iPhone app will ever be paid.** 「iPhone版はこれからも無料」 is a
  standing commitment and it is what makes the §3.2 funnel honest.
- **Do not scale posting before a format clears both thresholds.** Volume applied to
  a format that does not convert is the most expensive way to learn nothing.
