# Analytics — the desktop PostHog project

Authority for AGENTS.md §7. **The one rule this document exists to enforce: desktop
numbers and iOS keyboard numbers never touch.**

Status (2026-08-10): **live, and the pipe is proven.** Project
`KeigoButton Desktop (macOS)` is **549465**
(`phc_sJZEvNvRET7BEwCwXNnzoRofkbowJ8Ec3TuQTz9hHrG6`, org `Keigo`, timezone
`Asia/Tokyo`), the token and host are set on the repo's `production` environment, and
the dashboard is built and pinned:

- Dashboard — <https://us.posthog.com/project/549465/dashboard/1974822>

**The first real events arrived 2026-08-09 21:21 JST** — §5 has what they proved and
the one thing they falsified. The dashboard was rebuilt on 2026-08-10 from 15 tiles to
21: the original set measured the rewrite loop and nothing before it, so there was no
answer to "how many people arrived today". §4 is the new set.

---

## 1. Why this is a separate project and not a filter

The iOS keyboard, the landing page and the desktop app all authenticate against the
same `auth.users`, and every surface calls `identify()` with the same Supabase UUID.
That UUID is the `distinct_id`. So in a shared project a person is *one* person across
platforms — which is true of the human and false of every number anyone would want:

- **MAU** double-counts nobody, which sounds right and means desktop MAU is
  unobtainable — you cannot subtract a person who was active on both.
- **Retention** counts an iOS-only user as a returning desktop user.
- **Funnels** step across surfaces silently, because the events are the same person's.
- **Event names already collide.** Before 2026-08-09 the desktop sent
  `prompt_created`, `prompt_updated`, `prompt_deleted` and `onboarding_completed` —
  the exact names the iOS container has been sending into project 465060 since
  2026-06-11. Merged, those series are unsplittable after the fact.

None of that is recoverable by filtering, because the damage is to the person store,
not to the event stream.

### The three layers

| Layer | Mechanism | Defends against |
|---|---|---|
| 1. Project | Own PostHog project, own `phc_` token | Person merging; all of the above |
| 2. Event stamp | `surface: macos` super property on **every** event | A misconfigured token — makes a leak visible instead of silent |
| 3. Insight filter | Every dashboard tile filters `surface = macos` | A leaked event inflating a number on the dashboard |

Layers 2 and 3 are redundant *by design*. Layer 1 is a single point of failure — one
wrong CI variable — and the redundancy is what turns that failure from silent into
obvious.

**Layer 2 is registered in `PostHogConfiguration.registerSurface()` and re-registered in
`MainModel.signOut()`.** Super properties are persisted storage and
`PostHogSDK.shared.reset()` clears them along with the identity, so without the second
call every event after a sign-out would lose its surface until the next launch.

---

## 2. The project (done)

Creating a project cannot be scripted from here — the PostHog MCP exposes no
project-creation tool and the connector is OAuth-only. It was done in the UI on
2026-08-09; this is the record, and the recipe if a second one is ever needed.

1. <https://us.posthog.com/organization/projects> → **New project**, in org `Keigo`.
2. Name `KeigoButton Desktop (macOS)`, timezone `Asia/Tokyo` to match 465060.
3. Set the token and host on the repo's `production` environment — **not** as
   repo-wide variables, so they travel with the release workflow's other production
   values:

   ```sh
   gh variable set POSTHOG_PROJECT_TOKEN --env production --body 'phc_…'
   gh variable set POSTHOG_HOST          --env production --body 'https://us.i.posthog.com'
   ```

   `.github/workflows/release-macos.yml` preflights both with `test -n`. Both are set;
   before they were, **a release run failed at the preflight**.
4. For local runs, `cp Config/Local.example.xcconfig Config/Local.xcconfig` and fill in
   the token. `project.yml` wires that file in as the target's `configFiles` for both
   Debug and Release, and it is gitignored.

   **Without it the app builds and then traps on launch** —
   `Thread 1: Fatal error: POSTHOG_PROJECT_TOKEN variable required by PostHog is
   missing or un-configured`. `Info.plist` carries `$(POSTHOG_PROJECT_TOKEN)`, an
   undefined setting substitutes to nothing, and `PostHogConfiguration.configure()`
   trips its DEBUG `assertionFailure`. CI never hit this because the release workflow
   passes both values to `xcodebuild` on the command line, which outranks an xcconfig —
   so the file being absent on CI is a warning, not a failure.

   **The `//` in the host URL must be escaped as `https:/$()/us.i.posthog.com`.** An
   xcconfig parses `//` as a comment, so the unescaped form silently yields `https:`.
   Verify a build with
   `/usr/libexec/PlistBuddy -c "Print :POSTHOG_HOST" <built app>/Contents/Info.plist`.

**Do not reuse `phc_rkuAvbqxdVqqG5jZuySrJq8CH4NrYG97Z2B7vv7GXhJw`.** That is project
465060, the iOS keyboard and the landing page.

**PostHog auto-created "Your starter dashboard" (1974810) in 549465** with eight
web-shaped insights — `$pageview`, sessions, top referrers, a visit-to-interaction
funnel. None of those events can ever fire in a macOS accessory app, so that dashboard
will read zero forever. It is left in place rather than deleted; delete it when it
starts being mistaken for a real one.

---

## 3. What the desktop sends

All names are `desktop_`-prefixed. The prefix is not decoration — it is layer 2's
partner: an event without it, in the desktop project, came from somewhere it shouldn't.

| Event | Where | Properties |
|---|---|---|
| `desktop_rewrite_completed` | `Analytics.swift` | `host_app_bundle_id`, `capture_mode`, `io_path`, `prompt_origin`, `is_reply`, `latency_ms`, `candidate_count` |
| `desktop_rewrite_inserted` | `Analytics.swift` | `host_app_bundle_id`, `capture_mode`, `io_path`, `is_reply`, `accepted`, `selected_index` |
| `desktop_rewrite_failed` | `Analytics.swift` | `message` (the app's own Japanese toast — never captured or rewritten text) |
| `desktop_signed_up` | `MainModel.swift` | `method` (`password` \| `google`), `confirmation_required` (password only) |
| `desktop_signed_in` | `MainModel.swift` | `method` (`password` \| `google`) |
| `desktop_onboarding_completed` | `OnboardingWindowController.swift` | — |
| `desktop_source_selected` | `OnboardingWindowController.swift` | `source`, plus person property `attribution_source` (`$set_once`) |
| `desktop_prompt_created` | `MainModel.swift` | `slot` |
| `desktop_prompt_updated` | `MainModel.swift` | `slot`, `is_enabled`, `origin` |
| `desktop_prompt_deleted` | `MainModel.swift` | `slot`, `origin` |
| `desktop_checkout_started` | `MainModel.swift` | `billing_interval`, `currency`, `offer_expected` |
| `desktop_welcome_offer_shown` | `OnboardingWindowController.swift` | `currency` |
| `desktop_welcome_offer_accepted` | `OnboardingWindowController.swift` | `billing_interval`, `currency` |
| `$exception` | autocapture (`errorTrackingConfig.autoCapture`) | — |
| `$identify` | `MainModel.identifyIfNeeded` | person property `email` |

Plus `surface: macos` on every one of them, including the two the app never calls
`capture` for.

**And `app_language`** (`ja` | `en` | `zh-Hans`), registered beside it in
`PostHogConfiguration.registerSurface()`. A super property rather than a per-event
one, because the question it answers is always "split this series" and never "what
happened on this row". Two things to know when reading it:

- It is the **interface** language, not the language the user's buttons write in.
  A `zh-Hans` user writes Japanese (AGENTS.md §17), so a rewrite-volume comparison
  between `ja` and `zh-Hans` is comparing two groups doing the same thing.
- Super properties are stored, not computed, so a language change has to
  re-register them. `MainModel.languageChanged()` does — the same hazard as the
  surface being cleared by `reset()` on sign-out.

Events captured before the first build carrying this property have no
`app_language` at all; they are Japanese by construction, since the language page
did not exist.

**`desktop_signed_up` / `desktop_signed_in` are new on 2026-08-10** and they close the
gap this document used to list second: a brand-new desktop user and an existing iOS
user installing the Mac app were indistinguishable client-side. Three things about them:

- **Only an authentication the user just performed is captured.** `MainModel.refresh()`
  restores a Keychain session on every window activation and deliberately sends
  nothing — counting that would turn a signup series into a launch count.
- **Google needs a discriminator and `profiles.created_at` is it.** Supabase answers a
  first authorization and a returning one with the same session shape, so
  `completeOAuth` reads the profile row `handle_new_user()` wrote inside the signup
  transaction and calls it a signup if it is under ten minutes old. The window is wide
  on purpose — it absorbs clock skew between the Mac and Postgres, and the only thing it
  can misread is an account created on the phone in the last ten minutes.
- **Both endings of `SignUpOutcome` are a signup.** The confirmation branch has no
  session yet, so that event rides the anonymous `distinct_id` and follows the person
  through the later `identify`; `confirmation_required` separates the two on the wire.

`desktop_source_selected` is the last page of first run (AGENTS.md §15) and is
**self-reported and skippable**: 「答えない」 sends nothing at all, so the event count is
not the number of users who finished onboarding and the shares are of answers, not of
people. `source` is `OnboardingSource.rawValue` — a fixed set pinned by a test, because
renaming one splits a series after the fact. The person property is `$set_once`, so a
replayed 使い方を見る cannot overwrite a first answer (a replay sends nothing either way).

**The three billing properties added on 2026-08-10** answer the two questions the
pricing change created, and one of them is deliberately a client *belief* rather than a
fact:

- **`currency`** (`jpy` | `usd`) is on both the offer events and the checkout event.
  It follows the interface language for a new buyer and the existing subscription for
  everyone else, so it is not derivable from `app_language` and has to be sent.
- **`offer_expected`** is what the app thought when the button was pressed. The server
  decides whether a discount is actually applied and logs `offerApplied` on
  `desktop_checkout` in the function logs. **The two disagreeing is the signal** — it
  means a window closed between the card being drawn and the session being created —
  and neither value can be recovered from the other after the fact.
- `desktop_welcome_offer_shown` is emitted once per eligible first run, so
  `_accepted` ÷ `_shown` is the offer's conversion rate. Neither fires for a user who
  is skipped (already Pro, replaying, or refused by the server), which is what keeps the
  denominator to people who were actually offered something.

**Not verified: one real event of any of the three.** No build carrying them has
shipped, and the Stripe catalog they describe has not been applied.

`distinct_id` is the Supabase user id, the same as on iOS. In separate projects that is
a feature rather than a leak: the two platforms can be joined deliberately, in the
warehouse, when someone actually wants a cross-surface number.

### Known instrumentation gaps

These bound what §4 can show, and each is a small change rather than a design problem:

1. **`Application Installed` carries no `surface`, and this was read off the live
   project rather than reasoned about** — 2 of 2 installs have it null while every other
   event has it set. It is not a bug in `registerSurface()`: the PostHog Swift SDK
   captures the install inside `PostHogSDK.shared.setup(config)`, and
   `PostHogConfiguration.configure()` can only register super properties on the line
   after. So layer 3 has one hole, and it is exactly the event the acquisition tiles are
   built on — **tiles 1, 2 and 5 therefore carry no surface filter**, which is recorded
   in their own descriptions so nobody "fixes" them later. The real fix is to hand the
   properties to `setup` rather than register them after it.
2. **No `desktop_checkout_completed`.** The revenue funnel ends at intent. The Stripe
   webhook (`desktop-stripe-webhook`) knows the answer server-side; nothing forwards it.
3. **The rewrite events have no `is_tutorial`,** and onboarding practice sends them.
   `OverlayController` skips history for a tutorial rewrite but calls
   `analytics.rewriteCompleted` and `analytics.inserted` either way, and all three
   practice lessons complete *only* on a successful Insert. So every new user donates
   three guaranteed acceptances to tile 11 and three rewrites to tile 10. At today's
   volume that is most of the numerator. One property on both events fixes it.
4. **`io_path` is only on the two rewrite events.** A capture that fails before a path
   is chosen reports no path at all, so tile 14's denominator is successful captures.
5. **A DMG download is not an event and never will be.** Distribution is a GitHub
   release, so PostHog's earliest sighting of anyone is `Application Installed` — the
   first launch. Downloads that never launch are only visible as the GitHub release
   asset's `download_count`, which is cumulative and lives outside this project.

---

## 4. The dashboard — "Desktop (macOS) Overview"

Dashboard **1974822**, **21 tiles in five bands**, rebuilt 2026-08-10. The first
fifteen measured the rewrite loop and everything downstream of it; what they could not
answer was how many people arrived, signed up or finished first run on a given day —
which is the first question anyone asks of a product that has just started shipping.
Band 1 is that question and the shape of it is taken from 465060's
`Product KPIs — code-aligned (v2)`, deliberately: two surfaces of one product should be
readable side by side even though their numbers must never be added together.

**Every tile carries `surface = macos` except 1, 2 and 5.** Those three touch
`Application Installed`, which has no surface stamp (§3 gap 1), and filtering would
make them read zero forever. Everywhere else the filter is redundant on purpose — a
*gap* between a filtered and an unfiltered version of the same tile means events are
arriving here without the stamp, which is either a leak from another surface or a
capture running before `registerSurface()`. Neither is visible without the redundancy.

**Ratio tiles use a raw `A/B` formula with `aggregationAxisFormat: percentage_scaled`,
never `A/B*100`.** `percentage_scaled` already multiplies by 100, so a formula that
multiplies too renders 50 % as 5000 %.

### Band 1 — Acquisition

| # | Tile | Query |
|---|---|---|
| 1 | **[Installs & sign-ups per day](https://us.posthog.com/project/549465/insights/XIZ1sNHS)** | Trends, daily bars — `Application Installed`, `desktop_signed_up`, `desktop_signed_in`. No surface filter |
| 2 | [Cumulative installs & sign-ups](https://us.posthog.com/project/549465/insights/SwT8ymDK) | Same three series, cumulative line, 90 d. No surface filter |
| 3 | [New accounts vs existing accounts](https://us.posthog.com/project/549465/insights/U9iz5kZc) | Trends, weekly — `desktop_signed_up` against `desktop_signed_in` |
| 4 | **[Onboarding completions per day](https://us.posthog.com/project/549465/insights/S7qSDuke)** | Trends, daily — `desktop_onboarding_completed`, count + unique users |
| 5 | [Activation funnel](https://us.posthog.com/project/549465/insights/9cbmwXvI) | Funnel: `Application Installed` → `desktop_onboarding_completed` → `desktop_rewrite_inserted`, ordered, 14-day window. No surface filter |
| 6 | [Where users came from](https://us.posthog.com/project/549465/insights/Ep2l1MSd) | Bar, `desktop_source_selected` broken down by `source`, 90 d |

Tile 3 is the one that only exists because the projects are split. Both people on it
are the same `auth.users` id, so in 465060 the question "is the Mac app acquiring users
or serving the keyboard's existing ones" has no answer at all.

Tile 5 is `ordered` rather than `strict`: a great many events fall between installing
and the first accepted rewrite, and `strict` would require them to be adjacent. Ordering
is also what keeps step 3 honest while §3 gap 3 stands — onboarding practice sends
`desktop_rewrite_inserted` too, but it does so *before* completion, so it cannot satisfy
a step that has to follow one.

Tile 6 counts answers, not people: 「答えない」 sends nothing at all.

### Band 2 — Adoption

| # | Tile | Query |
|---|---|---|
| 7 | [Desktop DAU / WAU / MAU](https://us.posthog.com/project/549465/insights/qKSsc7XX) | Trends, `All events` — `dau` / `weekly_active` / `monthly_active` |
| 8 | [Lifecycle](https://us.posthog.com/project/549465/insights/QLMv4ESa) | Lifecycle on `desktop_rewrite_completed`, weekly — new / returning / resurrecting / dormant |
| 9 | **[Version adoption](https://us.posthog.com/project/549465/insights/IZ1MTpBy)** | Trends, `Application Opened` unique users broken down by `$app_version`, percent-stacked |

Tile 9 is the only read on whether a Sparkle update actually lands. `release-macos.yml`
proves an appcast was published and stapled; it says nothing about installation, and
AGENTS.md §9 still lists the old-build → new-build update chain as unverified. A version
whose share stops shrinking is a stuck update; one that never appears is an appcast or
signature problem.

### Band 3 — The core loop

| # | Tile | Query |
|---|---|---|
| 10 | [Rewrites per day](https://us.posthog.com/project/549465/insights/Rl35xXid) | Trends, `desktop_rewrite_completed`, count + unique users |
| 11 | **[Acceptance rate](https://us.posthog.com/project/549465/insights/bTQAoCs7)** | Formula `B/A` over `desktop_rewrite_completed` (A) and `desktop_rewrite_inserted` (B) |
| 12 | [Acceptance rate by `is_reply`](https://us.posthog.com/project/549465/insights/8nPuiflZ) | Tile 11 broken down by `is_reply`, weekly |
| 13 | [Rewrites per active user](https://us.posthog.com/project/549465/insights/bb5UPyEK) | Formula, `desktop_rewrite_completed` count ÷ unique users |

Tile 11 is the one number to keep. A rewrite that is generated, metered and never
inserted is a cost with no product in it. **Read it against §3 gap 3 until that is
fixed** — three of every new user's acceptances are the onboarding lessons, which only
complete on a successful Insert. Tile 12 is §16's stated reason for putting `is_reply`
on both events: reply mode composes from nothing rather than editing what is there, so
its acceptance rate is the only honest read on whether the composition works.

### Band 4 — Health

| # | Tile | Query |
|---|---|---|
| 14 | **[Clipboard fallback rate](https://us.posthog.com/project/549465/insights/AJBcohZ4)** | Trends, `desktop_rewrite_completed` broken down by `io_path`, percent-stacked area |
| 15 | **[Fallback rate by host app](https://us.posthog.com/project/549465/insights/GlRwsGfW)** | Table, `desktop_rewrite_completed` broken down by `host_app_bundle_id` × `io_path`, top 20 |
| 16 | [Failure rate](https://us.posthog.com/project/549465/insights/nWnT70o2) | Formula, `desktop_rewrite_failed` ÷ `desktop_rewrite_completed` |
| 17 | [Failures by message](https://us.posthog.com/project/549465/insights/lWbz9z9i) | Bar, `desktop_rewrite_failed` broken down by `message`, top 15 |
| 18 | [Latency median / p95](https://us.posthog.com/project/549465/insights/wMYLjz07) | Trends, `latency_ms` percentiles on `desktop_rewrite_completed` |
| 19 | [Crashes](https://us.posthog.com/project/549465/insights/uCriz4tu) | Trends, `$exception` volume + users affected |

Rate and diagnosis are two tiles rather than one: a formula and a breakdown cannot share
an insight, and 16 is the number you watch while 17 is the one you act on.

§7 calls `io_path` "the one to watch" and tile 15 is why: a rising clipboard rate *in a
specific bundle id* is the earliest signal that an app's AX tree changed. Tile 14 alone
would average that signal away across every app the user types in. Whatever surfaces in
15 is what `scripts/axdiag.swift` exists for.

Tile 18's budget comes from §5's `AXUIElementSetMessagingTimeout(element, 0.5)` — the
capture side is bounded at 500 ms per element by construction, so p95 growth is the
model or the network, not the AX path.

### Band 5 — Retention & revenue

| # | Tile | Query |
|---|---|---|
| 20 | **[Weekly retention](https://us.posthog.com/project/549465/insights/8QhCncOr)** | Retention: acquisition `desktop_onboarding_completed`, return `desktop_rewrite_inserted`, weekly, 9 periods |
| 21 | [Checkout intent](https://us.posthog.com/project/549465/insights/rWOWxmDc) | Trends, `desktop_checkout_started` broken down by `billing_interval` |

Tile 20 is the number this whole document exists to protect. In project 465060 it would
count an iOS-only user as a returning desktop user, every week, forever. Return is an
accepted rewrite rather than a launch, because an app that sits on the screen edge is
"opened" by doing nothing.

### Supporting breakdowns

Worth adding to tile 10 rather than as their own tiles: `capture_mode`
(`selection` vs `wholeInput` — how people actually invoke the bar) and `prompt_origin`
(which buttons earn their place on the row). Worth adding to tiles 1 and 3: `method`,
once there is enough volume to tell whether Google is carrying sign-up the way
onboarding assumes.

### What is deliberately not here

- **A downloads tile.** See §3 gap 5 — the number does not exist inside PostHog.
- **A permission-granted tile.** 465060 has "Keyboard enabled — first-time
  activations", and the desktop's equivalent is the Accessibility grant in §5. Nothing
  captures it, so the funnel steps straight from install to onboarding completion and
  cannot tell a user who gave up at the permission page from one who never opened it.
- **Test-account filtering.** Every tile is `filterTestAccounts: false` and the project
  has no test-account rule configured, so the owner's own machines are in every number.
  At two people and forty-seven launches that is most of the data; it stops being
  harmless the moment real users arrive.

---

## 5. The pipe, proven — and the one thing it falsified

The first build carrying `POSTHOG_PROJECT_TOKEN` ran on **2026-08-09 at 21:21 JST**.
Over the following fifteen hours 549465 received 135 events from 2 people across app
versions 0.1.0, 0.1.1 and 0.1.2: 47 `Application Opened`, 46 `Application Backgrounded`,
10 `desktop_rewrite_completed`, 10 `desktop_rewrite_inserted`, 3 `desktop_rewrite_failed`,
5 `$identify`, 11 `$set`, 2 `Application Installed` and 1 `Application Updated`.
Capture → JWT → `desktop-rewrite` → response → write-back is therefore proven end to
end by real events and not only by `debug.png`.

What that run established:

1. **The surface stamp arrives.** Every event carries `surface: macos` — **except
   `Application Installed`, 0 of 2.** That is §3 gap 1 and it was found here rather than
   reasoned about; the install is captured inside `setup()`, one line before
   `registerSurface()` can run.
2. **`app_language` behaves.** Null on the earliest events, then `en`, then `ja`, then
   `en` again as the language was switched — so `languageChanged()`'s re-registration
   works and pre-language-page events are correctly absent rather than wrong.
3. **`$identify` did not strand anyone.** Anonymous `019fe6…` ids appear at launch and
   the Supabase UUID takes over from the identify onward, which is the merge working.

Still unobserved, and each blocks a tile rather than the pipe:

- **`desktop_onboarding_completed` has never fired** (tiles 4, 5, 20). Both people had
  already finished first run, so an empty tile is not yet evidence of a broken step —
  but it also means the ten-step flow's analytics have not been exercised even once.
- **`desktop_source_selected`, `desktop_prompt_*` and `desktop_checkout_started` have
  never fired** (tiles 6, 21).
- **`desktop_signed_up` / `desktop_signed_in` cannot have fired**: they were added on
  2026-08-10 and no build carrying them has shipped. Tiles 1, 2 and 3 stay at zero on
  those series until the next release.
- **465060 receiving nothing new has not been re-checked since the pipe went live.** The
  `desktop_` prefix means a leak would show up there as a new event name rather than as
  silent extra volume on an existing one, so it is a cheap check and still worth running.
