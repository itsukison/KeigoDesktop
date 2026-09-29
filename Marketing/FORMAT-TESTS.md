# FORMAT-TESTS.md — content format test log

**Read `GTM.md` §3 and §4 first.** This file is the record of every format variant we
have posted and how it did. `GTM.md` decides what we are trying to do; this file is the
evidence about whether it is working.

The whole September gate lives here: **find one format that clears both thresholds.**
Until a row in §3 passes, nothing in `GTM.md` §6 is real.

---

## 1. The gate

A variant passes only by clearing **both** numbers. One without the other is a fail,
and the two failure modes mean different things:

| Threshold | Target | If it fails alone |
|---|---|---|
| **Median views** | **≥ 1,000** per post | The hook is wrong. The product slide never got seen, so it tells us nothing about conversion. **Median, not mean** — see the baseline in §4, where one post carried 42% of an account's views and the mean read 6x the median |
| **Tap-to-install** | **≥ 1%** of views | The hook works and the offer doesn't. Keep the hook, change the product slide, the CTA, or the position |

Sample size before judging: **≥ 5 posts** of a variant, or **≥ 5,000 cumulative
views**, whichever comes first. Anything below that is noise — a single post's reach is
mostly luck.

Installs are attributed per `GTM.md` §7. **Split iOS and Mac installs in every row**:
per §3.2 a Japanese phone viewer is expected to land on the free iOS keyboard, and
judging Japanese creative on Mac installs alone will make a working format look dead.

---

## 1.5 Japan only, for now

**Every TikTok account we have posts in Japanese**, per Buffer. Switching those
audiences to English overnight would test the algorithm's tolerance rather than the
format, so Phase 1 runs Japanese on the existing accounts.

**Amended 2026-08-20 (second revision):** `en-001`…`en-006` are publishable English posts,
not style reference, and they are **scheduled** — to TikTok `keigobutton` in **Buffer**, which
is a different account from the four Zernio ones above. The English track's five-post gate is
counted **separately** from the Japanese one; do not pool the rows.

The `keigobutton` account is being **converted** from Japanese to English rather than created
fresh, and the §1.5 objection above was weighed against its actual numbers before deciding —
see the baseline in §4. Short version: there is almost no engaged Japanese audience to lose.

**Amended 2026-08-22:** the English track now runs on **two** accounts — TikTok
`keigobutton` and Instagram `hannah_keigobutton` (new, Buffer, `en-ig-001`…`en-ig-006`,
scheduled 08-23…08-28). Same hook, same app lists, same captions as the TikTok series, so
they are **one variant row, pooled**, exactly as `ruka` + `yuna` are pooled on the Japanese
side. Keep the **platform** split visible inside the row anyway: Instagram carries the full
caption and TikTok currently carries none (`PUBLISHING.md` §2.1), so a TikTok/Instagram gap
in comments or saves is that bug, not a format signal.

hannah starts at 001 while TikTok is already at 003, so the two accounts are **not** aligned
by post number. Match rows by app list, not by number.

**The `keigobutton` TikTok queue had a batch of 6 Japanese posts on it**, created
2026-08-22 and interleaved between the English roundups at 1.5-hour spacing. Five were
deleted the same day; the sixth had already published (`PUBLISHING.md` §5).

**EN 002 is contaminated and EN 001 is not.** 001 sent 08-21 01:00Z on a quiet account. 002
sent 08-22 02:00Z and was followed the same day by a Japanese slideshow at 03:30Z, an English
Gen-Z video posted by hand in the TikTok app at 08:15Z, and another Japanese slideshow at
08:42Z — four posts, three formats, one account, against `GTM.md` §4.6. Exclude 002 and count
the English gate from 001 plus 003 onward.

**That Gen-Z video is Format E territory on an account mid-sample on Format A.** `GTM.md`
§4.6 sanctions Format E only as its own sample on its own account. If E is being tested,
it needs an account of its own; if it is not, it should not be on this one.

Naming follows from that: posts are numbered in posting order so they can be
scheduled, and `pipeline/out/` mirrors it —
`out/<lang>/<format>/<post>/NN_slide.png`, built with `python3 render.py ja-001`.
The format directory is words (`must-have-apps`) rather than the registry code
(`H5-CB`) so a folder is readable on its own; the two names mean the same thing.

**One consequence for `GTM.md` §6.2:** that ladder assumed the English track supplied
roughly a quarter of the December number. Japanese-only removes it, so either the
Japanese posting volume covers the gap or the December target drops accordingly. Worth
settling before October, not now.

## 2. The registry

Hook and content are chosen independently, so a post format is a **pair**. Naming:
`H<n>-C<x>` — e.g. `H5-CB` is the must-have photo hook with flat-card content slides.

### Hooks

| ID | Reference | Description | Build cost |
|---|---|---|---|
| **H1** | `sshook/1.png` | "My must have… **MacBook Apps**" — dark room, icon fan behind the lid | Low — same template as H5 |
| **H2** | `sshook/2.png` | "These are the best… **MacBook Settings Tips**" — huge type, no icons | Lowest — no icon layer |
| **H3** | `sshook/3.png` | "Cozy apps for MacBook Neo" — cafe, latte art, figurine, doodles | High — the photograph *is* the format |
| **H4** | `sshook/4.png` | "whimsical macbook neo apps to try" — tatami, matcha, labelled icons on keys | High — same reason, plus a doodle library |
| **H5** | `sshook/5.png` | "my must have **Macbook Apps**" — bright room, icon fan behind the lid | Low — **the chosen first build** |

H1 and H5 are one template at two exposures. Building either yields both.

### Content systems

| ID | Reference | Description | Build cost |
|---|---|---|---|
| **C-A** | `sscontent/s1.png`, `s5.png` | Screen-in-photo — real laptop, app UI composited into the physical screen, icon + copy overlaid above | Medium — needs a perspective transform, and 8 annotated numbers per background |
| **C-B** | `sscontent/s2.png`, `s3.png` | Flat card — no photo at all. Big icon, macOS-window-styled card with name + copy | **Lowest — pure HTML/CSS, needs only an icon** |
| **C-B+** | `sscontent/s4.png` | Flat card with paper texture, doodles and a 3D sticker | Medium — needs a doodle/sticker library |

The reference creators pair them consistently: H1/H5 → C-A, and H3/H4 → C-B / C-B+.
**We are deliberately breaking that pairing** for the first test — H5 (cheap hook) with
C-B (cheap content) — because both halves being cheap is what lets us ship variants
this week. Coherence is carried by the shared type system and by using a blurred crop
of the hook photo as the card background rather than flat cream.

### Video formats (Format E)

The `H<n>-C<x>` pair notation is for slideshows and does not apply here. Format E
(`GTM.md` §4.5) is one video format with two builds:

| ID | Description | Build cost |
|---|---|---|
| **E-1** | Pure rewrite. Phone filming a monitor, native Outlook/Slack/Teams UI, no face, no voice, no cuts. Message appears → deleted → corporate rewrite → button press | Lowest — the copy pair *is* the asset |
| **E-2** | The same post with 2–4 reusable human reaction clips cut in | One shoot, then the same as E-1 |

Each build runs in both languages, and the pair is what a row records: `en-genz-e1`,
`en-genz-e2`, `ja-keigo-e1`, `ja-keigo-e2`. The Japanese joke is **タメ口 → 敬語**, not a
translation of the English one (`GTM.md` §4.5), and per §1.5 the two languages are never
pooled into one sample.

**E-2 is not a new format, it is E-1 with one variable changed** — a human on screen.
That is exactly what §5's one-variable rule wants, and it is the only way to learn what
the clips are worth before paying for more of them.

---

## 3. Test log

Newest last. One row per **variant**, not per post.

| # | Variant | Lang | Posts | Avg views | Taps | Installs (iOS / Mac) | Tap→install | Verdict |
|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | *nothing tested yet* |

**Posts 007–012 add a second variable to the JP TikTok series: sound.** They ship with
`auto_add_music: true` (`PUBLISHING.md` §2.2) and 001–006 shipped silent, because the flag was
not sent. TikTok can only add a track of its own choosing — the API has no track picker — so
this is on/off, not a song test. Read the JP TikTok rows as **004–006 silent vs 007–012 with
music**, and keep Instagram out of that comparison: IG carousels take no audio at all, so
`yuna` is the control that isolates the sound effect on `ruka`.

**The app list is not the variable under test.** It changes every post by construction; the
hook, the card system and the position-3 rule are what stay fixed. A post that underperforms
its neighbours is evidence about its four apps, not about the format.

**JP 001–003 are excluded on purpose.** They published with two confounds — same-evening
spacing and a missing TikTok caption — so they cannot be a variant row. See §4.

Verdicts: `PASS` (both thresholds) · `HOOK FAIL` (views short) · `OFFER FAIL` (views fine, installs short) · `KILL` (both short) · `RUNNING` (below sample size)

---

## 4. Per-test detail

### T1 — three consistency treatments, built 2026-08-19, none posted

Same hook, same app list, same copy. **The only variable is how the app slides are
presented**, because a roundup where our slide is built differently from the other
four reads as an ad wearing a roundup's clothes.

Variant keys below use the current naming (`en-flat` was `T1a`, `en-cards` was `T1b`,
`en-screen` was `T1c`, `en-inscreen` was `T1d`).

| Variant | App slides | Our slide | Verdict |
|---|---|---|---|
| `en-flat` | flat cards | flat card — identical to the rest | Consistent, but describes the product without showing it |
| **`en-cards`** | cards **with a visual inside** | same card, same visual slot | **Recommended.** Consistent *and* every app is shown |
| `en-screen` | flat cards | screen composite on the photo | The original build. Most striking, most obviously the odd one out |
| **`en-inscreen`** | **all four on the laptop screen** | same treatment as the rest | Consistent the other way. Strongest showing of each app; most construction per slide |

- **Hook text:** "my must have" / "Macbook Apps" — faithful clone of `sshook/5.png`
- **App list:** Ice / DockDoor / **KeigoButton** / Dropover — us at 3 of 4, indie Mac
  utilities only, no competitor on the list
- **CTA:** 「③はプロフィールのリンクから」, caption only, never on a slide — a roundup stops
  working the moment one entry reads like an ad
- **Scheduled 2026-08-20** (see `PUBLISHING.md`): 001 Thu 19:00 JST, 002 Thu 22:00 JST,
  003 Fri 22:00 JST, each to `ruka_keigobutton` (TikTok) and `yuna_keigobutton` (IG)
- **Result:** pending. **001 and 002 are only 3h apart on one account**, so they compete
  for the same evening audience — if 002 underperforms 001, suspect spacing before
  blaming the apps
- **Our visual is now `assets/bar.png`** — the real overlay pill above a real Dock on a
  real desktop. It replaces the onboarding practice capture, and it is strictly better:
  no mock composer, the Dock is in frame so "sits above your Dock" is shown rather than
  claimed, and the four button labels are legible at card size.

**Japanese Phase 1 build — `T1b-ja`, built 2026-08-20, not posted.** This is the
publishable Japanese campaign variant for `@ruka_keigobutton`; the English T1 outputs
remain preserved separately.

- **Hook text:** `MacBookに入れてよかった` / `神アプリ4選`
- **App list and position:** Ice / DockDoor / **敬語ボタン** / Dropover — unchanged,
  so language is the only campaign-level difference
- **Our visual:** `assets/bar_jap.png`, the real Japanese overlay and Dock capture
- **CTA:** no standalone card. The 敬語ボタン app slide is the format-native CTA;
  adding a sixth sales card breaks the roundup disguise.
- **Output:** `pipeline/out/ja/H5-CB/001_ice-dockdoor-keigo-dropover/`; English renders live under
  `pipeline/out/en/<variant>/`
- **Result:** pending; judge after five posts or 5,000 cumulative views per §1

### T1-proof — two-state product proof — built 2026-08-26

This is the conversion challenger for the roundup, not a new hook. It keeps H5-CB,
position 3, the other three apps, account handle, caption and CTA fixed. Only the
KeigoButton card changes:

- A compact two-row grid shows the same Slack composer twice. `Before` pairs the clear
  input with the expanded KeigoButton bar and its four button options. The selected
  button uses the real muted-gray clicked state and a visible cursor. `After` replaces the bar
  with the horizontally centered dark result panel, overlapping the unchanged composer.
- The proposed rewrite stays inside the result panel, including prompt, pager, feedback
  controls and Insert action. This is the real pre-insert state: the field remains
  unchanged until the user chooses Insert.
- The surrounding Slack chrome and explanatory captions were deliberately removed. The
  only reading order is input → button → result, with localized copy and button labels.
  A short benefit description sits beneath the stacked proof so the slide retains the
  same visual rhythm as the other app cards without shrinking the real controls.
- Build keys are `en-proof-NNN`, `en-ig-proof-NNN`, `ja-proof-NNN` and
  `ig-proof-NNN`. They write under `proof_<post>` and cannot overwrite the controls.
- **Reading:** if median views hold and tap-to-install rises, the wrapper was already
  working and the missing variable was product proof. If taps rise but installs do not,
  stop changing this slide and inspect the landing/install path.
- **Result:** scheduled 2026-08-28 through 2026-09-01 as six posts on each of the four
  accounts. English uses proof cards at 12:00/17:00 ET alongside a 22:00 ET control;
  Japanese uses proof cards at 08:00/12:00/22:00 JST. This simultaneously changes cadence
  from one to three posts per day, so it is not a clean creative-only comparison. Read
  per-post tap-to-install and install conversion, control for account and slot, and treat
  any reach change as cadence-confounded. Full ids and verification are in
  `PUBLISHING.md` §5.

### Japanese posts 001–003 — built 2026-08-20, published 2026-08-20/21

**Read these three as unmeasurable, not as a result.** Two independent defects, both
recorded in `PUBLISHING.md` §5:

- **Timing.** `ruka` 001 and 002 both went out on 2026-08-20, at 19:00 and 22:00 JST —
  three hours apart, competing for one evening. Post 003 landed at 16:51 JST, no slot at
  all. Views on all three are a function of when they posted as much as of the creative.
- **No TikTok caption.** All three published with the title text only — no app list, no
  CTA, and **no hashtags**, because hashtags live in `content` and TikTok strips them from
  the title (`PUBLISHING.md` §2.1). Their TikTok comments, saves and reach are not
  comparable to the Instagram renders of the same posts, and not comparable to 004–006,
  which do carry a caption.

Neither is repairable after publish. Do not enter these in §3 as a variant row.


`ja-001` / `ja-002` / `ja-003`, all on the `en-cards` visual system with Japanese hook,
copy and product capture, one photo each. Hook: 「MacBookに入れてよかった / 神アプリ4選」.
Our slide sits at position 3 of 4 in every post.

Three hook bugs were fixed on these, all from the same root cause — **annotations
written by hand instead of measured**:

- Post 002's fan floated above the lid: the `Sky Blue` lid was ~20px high and sloped
  the wrong way. Post 003's was ~10px high with the slope inverted too.
- The fan was wider than the lid, so the outer icons hung past the laptop where
  nothing could occlude them. Icon size now derives from the measured lid width.
- The title was pinned at a fixed 44px top inset, which is cramped on a plate whose
  lid sits low. It is now centred in the band above the fan, so padding follows the
  measured lid instead of one tuned number.

### Japanese posts 004–006 — built and scheduled 2026-08-20

Three more H5-CB posts add enough creative inventory to carry this first format past
the five-post sample gate. They keep the same Japanese hook, card-with-visual system,
KeigoButton copy and position 3, while introducing **nine new third-party apps**—none
appears in posts 001–003, and each appears exactly once here.

- **004:** MeetingBar / Hand Mirror / **敬語ボタン** / LocalSend — `summer.jpeg`
- **005:** Velja / Keka / **敬語ボタン** / CotEditor — `macbook wallpaper.jpeg`
- **006:** Amphetamine / Pure Paste / **敬語ボタン** / GrandPerspective — the proven
  `_.jpeg` plate

Each new app uses a 512 px icon and a real product visual from its official Mac App
Store record. LocalSend is the one exception on the visual only: Apple's universal-app
record exposes phone screenshots, so its card uses the official 2880×1800 desktop hero
from `localsend.org`. Exact product pages, asset URLs and SHA-256s are recorded in
`source-assets/SOURCES.json`.

The first two hook photos were already in `Marketing/assets/` but unused. Their lid
and display edges were measured on 2× probe overlays before being registered in
`plates.py`; their Pinterest metadata and hashes are recorded in `SOURCES.json` with
the same `legacy-incomplete` provenance status as the original three photos. Both
Ruka (TikTok) and Yuna (Instagram) renders are produced because the handle is burned
into every content slide. They are scheduled one per account per day at 22:00 JST:
004 on Aug 22, 005 on Aug 23, and 006 on Aug 24. The 30 media files live under the
stable public Supabase prefix `marketing-media/mac-roundups/2026-08-20/`; every URL
was checked as `200 image/png` before scheduling. Exact post IDs are recorded in
`PUBLISHING.md`.

**How `en-inscreen` gets every app onto a screen.** `bar.png` is a bottom-of-screen crop, not a
display, so it cannot be warped in directly. `plates.desktop_plate()` rebuilds a full
16:10 screen out of its own parts: **only the wallpaper band is stretched** to make up
the missing height, while the overlay pill and the Dock keep true scale, so the product
is never distorted. Every app then gets that same wallpaper and same Dock — four apps on
one Mac rather than four unrelated screenshots — with the other three placed as a
floating window and the pill omitted.

Known costs of `T1d`, none of them visible to a viewer but worth recording:

- `bar.png` holds only 141px of wallpaper, so stretched to fill a screen the rock reads
  oversized. Passes as a photo wallpaper.
- The Dock is clipped at the right edge and its icons run large, both inherited from the
  source being a crop scaled ~3.3x.
- **Ours is the only genuine capture in the set** — the other three are marketing art
  arranged on a synthetic desktop. That is the inverse of the problem `T1c` had, but
  unlike structural inconsistency it is invisible in the feed.

**Why the app art could not simply be warped in as-is.** The public art exists
and is good, but none of it is a screen capture: Ice's banner is 2.05:1 with
instructional colour-coded callouts, DockDoor's hero is 1.07:1, Dropover's tiles are
646×496. Warping any of them into a 1.6:1 laptop screen distorts them, and a *marketing
banner* on a laptop screen reads as wrong — nobody's display shows labelled callouts.
Compounding it, all three are utilities with no main window: Ice lives in the menu bar,
DockDoor is a hover preview, Dropover is a floating shelf. **That variant needs all
four apps installed and captured full-screen by hand.** Inside a card the same assets
work perfectly, which is what `T1b` uses.

### English posts 001–006 — built 2026-08-20, not scheduled

The English track's first six posts, `en-001`…`en-006`. They are **not** a translation
of the Japanese set — `GTM.md` §9 forbids that, and §2.2 is a different product story.
What carries across is the skeleton: the same six plates, the same six app lists, the
same position 3, the same card-with-visual system. **Language and copy voice are the
only campaign-level differences from `ja-001`…`ja-006`**, which is what makes a JP/EN
comparison worth reading.

- **Hook text:** `no thoughts just` / `MacBook Apps` — Gen-Z lead-in on the same
  character footprint as the `sshook/5.png` clone, so the measured-lid layout is
  unchanged. Identical across all six posts per §5.
- **Handle:** `@keigobutton`. **There is no English account connected** —
  `accounts_list` returns only `yuna` (IG) and `ruka`/`saya`/`yuri` (TikTok), all
  Japanese personas. The neutral brand handle was chosen over reusing an idle persona
  because §1.5 records that flipping a JP-trained audience to English tests the
  algorithm's tolerance rather than the format.
- **Our slide:** `assets/bar.png` — the English overlay pill (Grammar / Email /
  Simplify / Formal) above a real Dock. Never `bar_jap.png`.
- **Our copy, identical on all six cards:** the §2.2 pitch, and **the keigo word never
  appears** — "Stop tabbing out to ChatGPT to fix one sentence. Highlight text
  anywhere — Slack, Gmail, Notion — hit one of your own buttons and it rewrites in
  place. Your prompts, but as buttons."
- **CTA:** 「③ is in my bio」, caption only, never on a slide. Destination is a
  decision still open: §3.2 puts the English ChatGPT-power-user segment on the
  Mac-direct funnel, unlike the Japanese phone-first funnel.
- **Copy voice:** Gen-Z, written for the account rather than translated. Deliberately
  reads as a person's list ("hides the menu bar icons you have never once looked at"),
  because a roundup stops working the moment one entry sounds like marketing.
- **Two card visuals had to be re-sourced.** The Japanese campaign pulled Amphetamine
  and CotEditor art from the **JP** App Store storefront, and both render a Japanese
  UI — wrong on an English card. `visual_en` entries from the US storefront now back
  `amphetamine_en.png` and `coteditor_en.png`; the JA renders are untouched. The other
  six App Store visuals (MeetingBar, Hand Mirror, Velja, Keka, Pure Paste,
  GrandPerspective) were already English and are shared.
- **Output:** `pipeline/out/en/must-have-apps/keigobutton/00N_<slugs>/`, 5 slides plus
  `caption.txt` carrying the TikTok title and the Instagram caption as separate fields.
- **Scheduled 2026-08-21 … 2026-08-26, one per day at 10:00 JST** to TikTok
  `keigobutton` via Buffer. Post IDs are in `PUBLISHING.md`. 10:00 JST is chosen as a
  **US-evening** slot (21:00 EDT / 18:00 PDT the previous day), not a Japanese one.
- **Result:** pending. **This is the English track's own Phase 1, not an extension
  of the Japanese sample** (§8): its five-post gate is counted separately, and rows
  must not be pooled with the `ja-*` posts.

### Baseline — TikTok `keigobutton` before the English switch

Recorded 2026-08-20 because Buffer's free plan exposes **only the last 31 days** of Insights,
and the account's biggest post (2026-07-26) ages out of that window around 2026-08-26. These
numbers cannot be re-derived later.

| Metric | Value |
|---|---|
| Sent posts (2026-07-19 → 08-13) | 51 |
| Total views / reach | 192,450 / 183,224 |
| **Mean views** | **3,849** |
| **Median views** | **639** |
| Best post | 81,382 — **42.3% of all views on its own** |
| Top 3 posts | 76.5% of all views |
| Posts clearing 1,000 views | 12 / 50 |
| Likes / comments / shares | 366 / 28 / 12 |
| Like rate | 0.19% (engagement rate 0.21%) |

**The conclusion that mattered for the switch: "the Japanese content was going well" is three
viral posts, not a working format.** Strip the top 3 and the remaining 47 posts average 962
views. Engagement is effectively nil — the last 12 posts (Aug 11-13) drew 0-3 likes and zero
comments each — so converting this account to English forfeits almost no audience value. That
is why §1.5's objection was overridden here rather than answered with a new account. The queue
had also been empty since 2026-08-13, giving a clean seven-day break between languages.

**This baseline invalidates §1's "average views" threshold as written.** On real data from our
own account, mean is a lottery artifact: 3,849 mean against a 639 median. A variant judged on
mean would pass on one lucky post while 38 of 50 posts failed to reach 1,000 views.
**Judge the gate on median views, and record the max separately** so a viral outlier is visible
as an outlier rather than laundered into the average.

**[Estimate]** Expect the first 3-5 English posts to be suppressed: the residual Japanese
follower base will not engage with English content, which depresses the early engagement-rate
signal. Treat those posts as conversion cost and exclude them from the format evaluation.

Template for the next one:

```
### T<n> — <variant id> — <date range>

- **Hook text:** the exact string
- **App list and our position:** e.g. Notchnook / DropOver / **KeigoButton** / DockDoor
- **Our slide:** which content system, what it showed
- **CTA:** exact wording and destination
- **Result:** posts, avg views, best/worst post, taps, installs split by platform
- **Verdict:** and the one thing we change next
```

The last line is the point of the whole file. A test that does not produce a single
next change was not a test.

### T2 — Format E, `en-genz-e1` vs `en-genz-e2` — building 2026-08-21

The Gen Z → corporate rewrite. Strategy and the three constraints on it are in
`GTM.md` §4.5; this is the production spec and the test design.

**The design is a pair, and the pair is the point.** Every E-2 post has an E-1 twin
with **identical POV, identical Gen Z line, identical rewrite, identical app UI,
identical audio, identical caption and CTA**. The only difference is the reaction clips.
A post whose copy differs from its twin is not a pair and cannot be read as one — it
just adds a third unmeasured format.

- **Gate:** §1 unchanged — median ≥ 1,000 views **and** ≥ 1% tap-to-install, ≥ 5 posts
  per variant. So the pair costs **10 posts minimum**, and the two variants are separate
  rows in §3.
- **Counted separately from `en-001`…`en-006`.** Those are H5-CB roundups on the
  `keigobutton` account and still mid-sample; pooling them with Format E rows destroys
  both samples.
- **Account — open.** `GTM.md` §4.6 forbids interleaving Format E into an account that
  is mid-sample on Format A. The roundup schedule on `keigobutton` runs to 2026-08-26,
  so either Format E starts after that date on `keigobutton`, or it gets its own English
  account. **Recommendation: its own account** — the two formats want different
  audiences (Mac-utility hobbyist vs young office worker) and a mixed account trains the
  algorithm on nobody.
- **Install attribution:** iOS-keyboard installs are the primary number for this format
  per `GTM.md` §3.2, with Mac installs recorded beside them. This audience is watching
  on a phone, at work, from an office where the laptop may well be Windows.
- **Product beat, mandatory:** select the text → press the button → it rewrites in
  place. The organic cut (delete and retype) is allowed as **at most one control post**,
  never as the format.
- **Track per post:** 1–3 s retention, completion rate, rewatches, shares, comments,
  profile visits, product clicks. Retention at 1–3 s is the number that decides whether
  a reaction clip in front of the message helps or costs — if the clip delays the
  ridiculous message past ~1 s, expect it to cost.
- **The film set is built:** `filmset/` — a live Slack mockup with a real editable
  composer, `./run.sh` for a chromeless fullscreen window, scenarios in
  `filmset/scenarios.js`, keys and the pre-shoot checklist in `filmset/README.md`. It is
  a copy of `Raylight/mockups-en/slack.html`'s chrome rebuilt to fill a display and be
  typed in; the Raylight plates are fixed at 1468×1080 for that project's transforms and
  were left untouched. **The message is typed and deleted by hand on camera** — the page
  drives nothing, and set-up commands sit behind `⌥` so they cannot land in a take.
  Keeping an E-1 take and its E-2 twin identical is therefore a performance constraint,
  not a mechanical one: same line, same pace, reshoot rather than improvise. It draws a
  **small window bottom-centre** rather than filling the display — the filming machine is
  a Mac mini on a large display, and a full-screen Slack is far wider than a portrait
  phone frame keeps. `--fill` rescales the whole mockup at once.
- **Scenario `ja-001` is written:** POV 「pov: 入社1年目、上司に送信する直前」, a DM from a
  マーケティング部 部長 asking to 「スコープをフィックスする前に…ステークホルダーと目線合わせを
  して、Q3のナラティブをリバイスした上でドラフトを共有」, answered in full タメ口 with
  「え、まって ガチで何言ってるか分からんのだけどw とりあえず日本語で頼むw」. Set is
  `filmset/slack-ja.html` + `scenarios-ja.js`, run with `./run.sh ja`.
- **Ten English scenarios are written — `e-001`…`e-010`, the whole E-1 sample.** POV is
  held constant at `pov: you're a 22 year old working in corporate` across all ten per §5,
  so the Gen Z line is the only variable; the rest of the POV bank is the next sample.
  Situations: jargon soup · a 9:47 PM ping · messaged on PTO · "do you have 15 minutes" ·
  new work at 5:41 PM Friday · work already delivered · blamed for someone else's miss ·
  a 60-minute meeting with no agenda · a vague ownership grab · blunt feedback. Four are
  the §4 buckets; six are new, and the new ones are deliberately the *grievance* cases,
  where the underlying meaning is mildly rude and the rewrite therefore has more work to
  do. Filming target is a Mac mini on a large display.
- **The Gen Z line must be translatable, and it is the binding constraint on this
  format.** The product changes register, not content — it makes a message polite, it does
  not infer a message that was never there. A pure-reaction line therefore cannot be
  filmed: `unc it's 10pm 💀 be so fr rn` says nothing the rewrite could turn into "I'll
  prioritise it in the morning", so the demo would show the app producing text it cannot
  produce. Every line is now **slang reaction + the actual thing being said**, and passes
  one test before it is shot: *delete every slang word and every emoji; what is left must
  still be a complete message.* The same rule binds the `corporate` fallback — an early
  draft of it promised the deck "ahead of the 9am" and cited a summary sent "last
  Thursday", both details only the boss's message contains.
- **The character is powerless, not defiant — and the first ten got this wrong.** The
  reference lines (`shiiii twin ngl i have no idea what this means 💀`,
  `lmaooo fam stop with the aura farming`) are funny because the speaker addresses a
  director exactly as they address their best friend: misjudged intimacy, not rebellion.
  Several of `e-001`…`e-010` drifted into refusing, blaming and scorekeeping — negotiating
  positions, which are neither funny nor powerless, and which change what the product
  appears to be for. The three engines that work (over-honest confession, misjudged
  intimacy, absurd oversharing), the three-question test, and the next ten lines are in
  `filmset/LINEBANK.md`. **Recorded after `e-001`…`e-010` were filmed**, so the batch-one
  rows in §3 carry the mixed register as a known confound.
- **Batch two is built: `e-011`…`e-020`, 2026-08-23.** Ten new situations on three new
  bosses (Tobias Renner / Cecilia Vance / Nadia Okonjo), written in the corrected
  powerless register, with the line *shape* varied as deliberately as the words: two carry
  no emoji, one opens on one, four end on one, 😭 appears once, and punctuation and caps
  differ line to line. Batch one had every line as `slang 😭 clause`, which reads as a
  template by the third post a viewer sees. `scenarios.js` now loads one batch at a time —
  `./run.sh dark-b1` for batch one, unchanged, because its E-2 twins must reuse those exact
  lines.
- **Lines run eight to twelve words**, which is what carrying an actual clause costs.
  `shiiii twin ngl i have no idea what this means 💀` was the original `e-001` and failed
  on length; the three-to-six-word replacements that followed failed on translatability.
  Each scenario carries three `alts` at the same length and under the same rule.
- **Three bosses, rotated.** Diane Whitaker / Greg Halvorsen / Priya Raman, no more than
  four posts each, each with its own scrollback. At the film set's default `--fill` the
  sidebar falls outside the 9:16 crop, so the boss's name, avatar and last message are
  the only frame elements a repeat viewer sees — those rotate, the chrome does not.
  Mechanically this is a `CASTS` + `SCENES` split at the top of `scenarios.js`; there is
  still no build step.
- **Result:** not built yet. E-2 clips are in production as of 2026-08-21.

**POV hooks.** Simple, slightly stupid, culturally recognisable. The POV sets the frame;
the message delivers the joke. Reject any hook that reads as a written premise —
"POV: your manager asks for an update 3 minutes after assigning the task" is a
marketer's skit, `pov: you're 23 with a corporate email address` is not.

Bank, in rough testing order: `pov: you're a 22 year old working in corporate` ·
`pov: you're 23 with a corporate email address` ·
`pov: you're a 23 year old teenager working in the corporate world` ·
`pov: texting your boss as a gen z in a corporate big girl job` ·
`pov: gen z trying to write a professional email` ·
`pov: you're gen z but you have a big girl job` ·
`pov: gen z in their first corporate job` ·
`pov: trying to remember outlook is not the groupchat` ·
`pov: gen z attempting corporate communication`

**The Gen Z line is the most important asset in the post.** It has to clear one bar:
*there is no way they're actually sending that.* Four ingredients, in order — reaction
word (`LMAOOOO` / `shiiii` / `waitttt` / `nahhhh` / `broooo`), friend-address word
(`twin` / `fam` / `bro` / `girl`), filler (`ngl` / `lowkey` / `no bc` / `i fear` /
`be so fr` / `rn`), and **an extremely basic underlying meaning** — I don't understand,
what are you saying, no, not today, that's not what I said, what do you want me to do.
The simpler the thought, the funnier the corporate translation.

Lines to test, by situation:

| Situation | Line |
|---|---|
| Confused | `waitttt twin what am i even looking at rn 😭` · `LMFAOOOO no bc what does this mean` · `shiiii i fear i have no idea what ur asking me 💀` · `girl what are u even saying rn 😭` |
| Disagreeing | `nahhhh be so fr 😭` · `twin i don't think thats gonna work ngl` · `wait why are we doing all that tho` · `bro there's literally no way 😭` |
| Asked to do something | `damn can i finish the first thing first 😭` · `shiiii u need this TODAY??` · `waittt so what exactly do u want me to do 😭` · `girl i fear thats not happening today` |
| They got it wrong | `bro did u even look at what i sent 😭` · `waitttt thats literally not what i said` · `twin where did u even get that from 💀` · `LMAOOOOO we are not looking at the same spreadsheet` |

**The rewrite has to be comically corporate**, not merely correct. Phrase bank:
"I appreciate the additional context" · "I want to make sure I fully understand" ·
"Would you mind clarifying" · "It may be helpful to revisit" · "Could we align on" ·
"Given the current timeline" · "Would you be open to" · "I wanted to follow up" ·
"To make sure we're on the same page" · "Please let me know your thoughts". The target
is **unreasonably Gen Z → unreasonably corporate**; a merely polite rewrite kills the
post.

**Clip inventory for E-2** — 4 clips, shot once with a real person, reused across posts:
smug/cocky typing · the sudden pause · the mild "oh shit" realisation · satisfied
back-to-work. Aesthetic: normal office, phone camera, imperfect framing, slightly
awkward lighting, believable young employee. **No cinematic AI visuals and no AI face**
(`GTM.md` §4.5). Shoot 8–12 micro-variants rather than 4 if the shoot allows — identical
segments across dozens of posts are recognisable to a viewer who sees three of them.

**Content engine.** Generate 50+ scenarios up front, one row each: POV · situation ·
Gen Z text · corporate rewrite · variant (E-1 / E-2). The generation rule is the one
creative constraint that matters: *write what a 21-year-old would text their closest
friend in this situation, not what a marketer thinks Gen Z would say.* If the line reads
as deliberately written to be funny, it gets rewritten.

---

## 5. Decision rules

- **One variable per variant.** Changing the hook and the app list together teaches
  nothing about either.
- **A `HOOK FAIL` keeps the content, changes the hook.** An `OFFER FAIL` keeps the
  hook, changes our slide, our position in the list, or the CTA. This is the reason the
  two thresholds are tracked separately.
- **Three consecutive `KILL` verdicts on one hook family retires that family** and we
  move to the next ID in §2.
- **A `PASS` freezes the variant.** No further creative changes; it becomes the
  template and the work shifts to volume (`GTM.md` §8 Phase 2).
- **No scaling before a `PASS`.** Volume applied to an unvalidated format is the most
  expensive way to learn nothing.
