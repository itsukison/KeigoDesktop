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

**2026-08-24 — 32 tiles.** Band 6 rebuilt the rewrite loop around an attempt: six events
instead of four, a five-way `rewrite_type`, and a funnel with a denominator. §3's
"Rebuilt on 2026-08-24" has the why.

**2026-08-22 — 23 tiles, and three instrumentation gaps closed.** The first read of real
user behaviour is what prompted it: 6 external users had produced **4 real rewrites
between them**, and 14 of their 18 completed rewrites were the onboarding tutorial. §3's
"Closed on 2026-08-22" has the three fixes; §6 is why session replay is not one of them.

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
| 1b. Token pin | Surface-specific secret name + expected token pinned in code, write refused on mismatch | Layer 1 failing **on the server**, where the secrets namespace is shared |
| 2. Event stamp | `surface: macos` super property on **every** event | A misconfigured token — makes a leak visible instead of silent |
| 3. Insight filter | Every dashboard tile filters `surface = macos` | A leaked event inflating a number on the dashboard |

**Layer 1b exists because layer 1 was breached on 2026-08-23, exactly as predicted.** The
client gets layer 1 for free — each app is built with its own token by its own release
workflow. The server does not: `keyboard-rewrite` (465060), `web-rewrite` and every
desktop function share the Supabase project `eercsucvxnszqletxued`, and therefore one
secrets namespace. Deploying `desktop-stripe-webhook` at 11:55 JST set the shared
`POSTHOG_PROJECT_TOKEN` to the desktop token; `keyboard-rewrite` read that name in
preference to its own hard-coded default, and from 13:50 JST **198 `ai_rewrite` /
`ai_rewrite_action` / `ai_rewrite_accepted` events from 49 people landed in 549465 while
465060 received none.** A redirect, not a duplicate — the keyboard's rewrite analytics
went dark for ~31 hours and no alarm existed to notice.

Two changes, both required. The secret names are now `DESKTOP_POSTHOG_PROJECT_TOKEN` and
`KEYBOARD_POSTHOG_PROJECT_TOKEN`, so the surfaces cannot collide; and each module pins
its expected `phc_` token and **refuses the write, logging `wrong_project_token`**, if
the resolved value disagrees. The pin is what turns the next collision from silent
pollution into a logged no-op. Losing an event is recoverable; merging two surfaces'
persons is not.

Note what did **not** save us: layer 2. The leaked events carried no `surface` at all,
which is precisely the signal layer 2 promises — but a signal nobody queries is not a
control. Surface-filtered tiles were unaffected; **tile 7 (DAU/WAU/MAU) aggregates
`All events` and was inflated by the 49 keyboard persons for the duration.**

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
| `desktop_rewrite_started` | `Analytics.swift` (0.1.9) | `attempt_id`, `rewrite_type`, `is_tutorial`, `accessibility_granted`, plus the target properties |
| `desktop_rewrite_completed` | `Analytics.swift` | `attempt_id`, `rewrite_type`, `host_app_bundle_id`, `capture_mode`, `io_path`, `prompt_origin`, `is_reply`, `latency_ms`, `candidate_count`, `scope`, `has_destination`, `is_tutorial`, `accessibility_granted` |
| `desktop_rewrite_inserted` | `Analytics.swift` | `attempt_id`, `rewrite_type`, `host_app_bundle_id`, `capture_mode`, `io_path`, `is_reply`, `accepted`, `selected_index`, `scope`, `insert_destination`, `is_tutorial`, `accessibility_granted` |
| `desktop_rewrite_copied` | `Analytics.swift` | `attempt_id`, `rewrite_type`, `host_app_bundle_id`, `capture_mode`, `io_path`, `is_reply`, `scope`, `reason`, `is_tutorial`, `accessibility_granted` |
| `desktop_rewrite_failed` | `Analytics.swift` | `attempt_id`, `rewrite_type`, **`failure_stage`** (`capture` \| `generation`), `message` (the app's own Japanese toast — never captured or rewritten text), the target properties where a target exists, `is_tutorial`, `accessibility_granted` |
| `desktop_rewrite_abandoned` | `Analytics.swift` (0.1.9) | `attempt_id`, `rewrite_type`, `reason` (`superseded` \| `dismissed`), the target properties, `is_tutorial`, `accessibility_granted` |
| `desktop_signed_up` | `MainModel.swift` | `method` (`password` \| `google`), `confirmation_required` (password only) |
| `desktop_signed_in` | `MainModel.swift` | `method` (`password` \| `google`) |
| `desktop_accessibility_prompted` | `MainModel.swift` | `source` (`onboarding` \| `preferences` \| `home`), `method` (`system_prompt` \| `settings_link`) |
| `desktop_accessibility_granted` | `MainModel.swift` | `source` (the prompt that preceded it, or `outside_app`), `seconds_since_prompt` |
| `desktop_checkout_completed` | `desktop-stripe-webhook` (**server**) | `billing_interval`, `currency`, `welcome_offer_redeemed`, `stripe_status`, `payment_deferred`, `captured_by: server` |
| `desktop_onboarding_completed` | `OnboardingWindowController.swift` | — |
| `desktop_source_selected` | `OnboardingWindowController.swift` | `source`, plus person property `attribution_source` (`$set_once`) |
| `desktop_prompt_created` | `MainModel.swift` | `slot` |
| `desktop_prompt_updated` | `MainModel.swift` | `slot`, `is_enabled`, `origin` |
| `desktop_prompt_deleted` | `MainModel.swift` | `slot`, `origin` |
| `desktop_button_language_realigned` | `MainModel.swift` | `pack`, `writing_language`, `buttons` |
| `desktop_checkout_started` | `MainModel.swift` | `billing_interval`, `currency`, `offer_expected` |
| `desktop_welcome_offer_shown` | `OnboardingWindowController.swift` | `currency` |
| `desktop_welcome_offer_accepted` | `OnboardingWindowController.swift` | `billing_interval`, `currency` |
| `desktop_update_offered` | `MainModel.swift` | `from_version`, `to_version` |
| `desktop_update_accepted` | `MainModel.swift` | `from_version`, `to_version` |
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

**And `accessibility_granted` (2026-08-22)**, registered in the same call. §5 says the
app is useless without the Accessibility permission and until this date nothing measured
it, so the activation funnel stepped straight over the one gate that can silently end the
product: a user who never granted it and a user who granted it and hit a broken AX tree
were the same row. It is a super property for `app_language`'s reason — the question is
always "split this series", never "what happened on this row" — and:

- **`MainModel.applyTrusted` is the single writer of `isTrusted` and re-registers on
  every flip.** Super properties are stored, so without that the value keeps whatever it
  held at launch and every event after a grant still reports no permission.
- **The four rewrite events also send it as a per-event property, read live from
  `AXPermission.isTrusted` at capture time.** Deliberate redundancy, and not the same
  reading: the stored one is only as fresh as the last `refresh()`, and a
  `TextIOError.notTrusted` failure is exactly the moment it is stale. A row where the
  two disagree is a permission that changed without the window ever activating.

**`desktop_update_offered` / `desktop_update_accepted` are new on 2026-08-10**, and they
exist because the update path is otherwise entirely unobservable. A scheduled Sparkle
check, the find, and the announcement all happen with nobody watching — which is exactly
how 0.1.2 shipped a "gentle reminder" that reached no surface a user could see and nobody
could tell. `offered` fires once per newly-discovered version (not on the daily re-find of
a version already known, and not on the relaunch replay); `accepted` fires when the user
presses one of the three notices and hands the update back to Sparkle. The ratio between
them is the only measurement of whether the announcement works. Neither says the update
**installed** — that is `Application Installed` at the new `$app_version`, which is the
join to make when reading them.

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

### The 2026-08-18 destination properties (AGENTS.md §18)

Three additions, and the reason for each is that the core loop grew a second ending.

- **`desktop_rewrite_copied`** with `reason` (`no_destination` | `user_chose`). A rewrite
  the user copied because there was nowhere to insert it is *completed*, not failed, so it
  must not go into `desktop_rewrite_failed` — and without an event of its own that whole
  path reads as a funnel that stops after `completed`. **Tile 11's acceptance rate is now
  an undercount** by exactly the `no_destination` volume; the honest formula is
  `(inserted + copied[no_destination]) / completed`, and tile 11 has not been changed.
- **`scope`** (`selection` | `input_field` | `scratch`) on completed, inserted and copied.
  `scratch` is a rewrite composed from an instruction alone — the press that used to be
  refused outright — so its share is the measure of whether opening it up was worth it.
- **`insert_destination`** (`captured_field` | `insert_here`) on inserted. A rising
  `insert_here` rate means people compose first and choose the field afterwards, which is
  the flow §18 made possible; it is also the only signal that the live destination probe
  is firing at all in the wild.

None of these have a tile yet, and none has been seen in the live project.

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
2. **`io_path` is only on the rewrite events.** A capture that fails before a path is
   chosen reports no path at all, so tile 14's denominator is successful captures.
3. **A DMG download is not an event and never will be.** Distribution is a GitHub
   release, so PostHog's earliest sighting of anyone is `Application Installed` — the
   first launch. Downloads that never launch are only visible as the GitHub release
   asset's `download_count`, which is cumulative and lives outside this project.

### Closed on 2026-08-22

Three of the gaps this section used to list were closed together, because the read that
prompted them was the same one: **6 external users had produced 4 real rewrites between
them, and 14 of their 18 completed rewrites were the onboarding tutorial.** The numbers
were not visible until the tutorial could be subtracted.

- **~~No `desktop_checkout_completed`~~.** Now sent by `desktop-stripe-webhook` through
  `supabase/functions/_shared/posthog.ts`. It could never have come from the client:
  Checkout hands off to the DEFAULT BROWSER, so the app is not running when payment
  lands, and a `success_url` redirect is not proof of payment (§3.3). Fires only for the
  two paid Checkout types and only when `desktop_process_stripe_event` reports
  `applied` and `plan: pro`, so a duplicate delivery cannot report a second purchase.
  `captured_by: server` names the writer. Tile 23 is the funnel.
- **~~The rewrite events have no `is_tutorial`~~.** All four now carry it. Measured
  before the fix: **38 of 117 completed rewrites (32%) were practice**, and every new
  user donated three guaranteed acceptances to tile 11, because all three lessons
  complete *only* on a successful Insert. On `desktop_rewrite_failed` the flag reads
  from whether a lesson is *armed* rather than from a `PendingRewrite`, because a capture
  failure happens before one exists — a slightly wider claim, recorded in
  `PostHogAnalytics.failed`.
- **~~No permission-granted event~~.** `desktop_accessibility_prompted` and
  `desktop_accessibility_granted`, plus the `accessibility_granted` super property above.
  `granted` fires **once per person ever** — the flag is persisted, because `refresh()`
  runs on every window activation and this would otherwise be a launch count, and a
  revocation (every unsigned dev rebuild, per `AXPermission`) does not re-arm it. Two
  consequences to read it with: existing users granted the permission before this
  shipped, so their first launch on the new build sends `source: outside_app`; and
  tile 5's 14-day window means those backfills do not join their original install.

**The tiles still filter on `host_app_bundle_id`, not `is_tutorial`.** The bundle id works
on data captured before the property existed and the property does not, and the two agree
by construction — onboarding practice rewrites the app's OWN field, so
`com.core7.keigobutton.mac` *is* the practice. Switch the tiles to `is_tutorial` once
there are 30 days of it, not before.

---

## 4. The dashboard — "Desktop (macOS) Overview"

Dashboard **1974822**, **32 tiles in six bands** (21 as of 2026-08-10, 22–23 on 2026-08-22, 24–32 on 2026-08-24). The first
fifteen measured the rewrite loop and everything downstream of it; what they could not
answer was how many people arrived, signed up or finished first run on a given day —
which is the first question anyone asks of a product that has just started shipping.
Band 1 is that question and the shape of it is taken from 465060's
`Product KPIs — code-aligned (v2)`, deliberately: two surfaces of one product should be
readable side by side even though their numbers must never be added together.

**The tile links in this section were all wrong until 2026-08-22, and the way they were
wrong is worth knowing.** The dashboard's insights were **recreated on 2026-08-21** — 19
of the 21 got new `short_id`s and the originals were left saved but detached from any
dashboard. Editing a tile by the short_id written here therefore changed nothing anyone
could see. The links below are the ones dashboard 1974822 actually renders; **read them
off the dashboard, not from here, before editing a tile.** The orphaned originals
(`Rl35xXid`, `bTQAoCs7`, `bb5UPyEK`, `9cbmwXvI`, …) are still in the project and should
be deleted once someone has confirmed nothing else points at them.

The recreated set also differs in three ways the originals did not: `filterTestAccounts`
is **`true`**, the surface filter sits on each *series* rather than at the top level, and
`dateRange` is a fixed `2026-08-01` rather than `-30d`. Match that shape when adding a
tile.

**`filterTestAccounts: true` currently filters nothing, and this is the trap.** The rule
on the project is a `not_in` exclusion of cohort 467436, *Internal / Test users*, which
matches on the person property `$internal_or_test_user` — and that property is **null on
all 10 people in the project**. So the dashboard says it excludes internal traffic and
does not. Setting the property on the three owner accounts is all it would take; **not
doing so is a decision** (asked and answered 2026-08-22), so every tile is "us plus them".
For scale: the owners are 758 of 892 events (**85%**) and 75 of the 79 real rewrites.

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
| 1 | **[Installs & sign-ups per day](https://us.posthog.com/project/549465/insights/nGaGKMBk)** | Trends, daily bars — `Application Installed`, `desktop_signed_up`, `desktop_signed_in`. No surface filter |
| 2 | [Cumulative installs & sign-ups](https://us.posthog.com/project/549465/insights/VpFxoQKN) | Same three series, cumulative line, 90 d. No surface filter |
| 3 | [New accounts vs existing accounts](https://us.posthog.com/project/549465/insights/GM3VfbYx) | Trends, weekly — `desktop_signed_up` against `desktop_signed_in` |
| 4 | **[Onboarding completions per day](https://us.posthog.com/project/549465/insights/LvyG0Nja)** | Trends, daily — `desktop_onboarding_completed`, count + unique users |
| 5 | [Activation funnel](https://us.posthog.com/project/549465/insights/P1JOql50) | Funnel: `Application Installed` → `desktop_onboarding_completed` → `desktop_rewrite_inserted`, ordered, 14-day window. No surface filter |
| 6 | [Where users came from](https://us.posthog.com/project/549465/insights/2I3OFtCS) | Bar, `desktop_source_selected` broken down by `source`, 90 d |

Tile 3 is the one that only exists because the projects are split. Both people on it
are the same `auth.users` id, so in 465060 the question "is the Mac app acquiring users
or serving the keyboard's existing ones" has no answer at all.

Tile 5 is `ordered` rather than `strict`: a great many events fall between installing
and the first accepted rewrite, and `strict` would require them to be adjacent.

**It grew a second step and a filtered last step on 2026-08-22.** `desktop_accessibility_granted`
sits between install and onboarding because that is the gate the funnel used to step
straight over, and the final step now excludes `com.core7.keigobutton.mac` so it means a
*real* rewrite. Ordering used to be the only thing keeping that step honest — practice
sends `desktop_rewrite_inserted` too, just before completion rather than after — and the
filter now does it directly, which is the stronger guarantee.

Tile 6 counts answers, not people: 「答えない」 sends nothing at all.

### Band 2 — Adoption

| # | Tile | Query |
|---|---|---|
| 7 | [Desktop DAU / WAU / MAU](https://us.posthog.com/project/549465/insights/QuMQQ8rD) | Trends, `All events` — `dau` / `weekly_active` / `monthly_active` |
| 8 | [Lifecycle](https://us.posthog.com/project/549465/insights/QLMv4ESa) | Lifecycle on `desktop_rewrite_completed`, weekly — new / returning / resurrecting / dormant |
| 9 | **[Version adoption](https://us.posthog.com/project/549465/insights/0Q1HO4op)** | Trends, `Application Opened` unique users broken down by `$app_version`, percent-stacked |

Tile 9 is the only read on whether a Sparkle update actually lands. `release-macos.yml`
proves an appcast was published and stapled; it says nothing about installation, and
AGENTS.md §9 still lists the old-build → new-build update chain as unverified. A version
whose share stops shrinking is a stuck update; one that never appears is an appcast or
signature problem.

### Band 3 — The core loop

| # | Tile | Query |
|---|---|---|
| 10 | [Rewrites per day](https://us.posthog.com/project/549465/insights/ePhDpBQ6) | Trends, `desktop_rewrite_completed`, count + unique users. Excludes practice |
| 11 | **[Acceptance rate](https://us.posthog.com/project/549465/insights/P5f7IeMz)** | Formula `B/A` over `desktop_rewrite_completed` (A) and `desktop_rewrite_inserted` (B). Excludes practice |
| 12 | [Acceptance rate by `is_reply`](https://us.posthog.com/project/549465/insights/JjSYGG4L) | Tile 11 broken down by `is_reply`, weekly |
| 13 | [Rewrites per active user](https://us.posthog.com/project/549465/insights/6UA3H9NQ) | Formula, `desktop_rewrite_completed` count ÷ unique users. Excludes practice |

Tile 11 is the one number to keep. A rewrite that is generated, metered and never
inserted is a cost with no product in it. **Tiles 10, 11 and 13 exclude onboarding
practice as of 2026-08-22** — see §3's closed gaps for why the filter is on
`host_app_bundle_id` rather than `is_tutorial`. It is still an undercount by the
`copied[no_destination]` volume; the honest formula is
`(inserted + copied[no_destination]) / completed`. Tile 12 is §16's stated reason for putting `is_reply`
on both events: reply mode composes from nothing rather than editing what is there, so
its acceptance rate is the only honest read on whether the composition works.

### Band 4 — Health

| # | Tile | Query |
|---|---|---|
| 14 | **[Clipboard fallback rate](https://us.posthog.com/project/549465/insights/8A6jCNhU)** | Trends, `desktop_rewrite_completed` broken down by `io_path`, percent-stacked area |
| 15 | **[Fallback rate by host app](https://us.posthog.com/project/549465/insights/YuKR0kmb)** | Table, `desktop_rewrite_completed` broken down by `host_app_bundle_id` × `io_path`, top 20 |
| 16 | [Failure rate](https://us.posthog.com/project/549465/insights/mdXo7Pyz) | Formula, `desktop_rewrite_failed` ÷ `desktop_rewrite_completed` |
| 17 | [Failures by message](https://us.posthog.com/project/549465/insights/KpJihDLt) | Bar, `desktop_rewrite_failed` broken down by `message`, top 15 |
| 18 | [Latency median / p95](https://us.posthog.com/project/549465/insights/eWp7pSbp) | Trends, `latency_ms` percentiles on `desktop_rewrite_completed` |
| 19 | [Crashes](https://us.posthog.com/project/549465/insights/sFEF7FG8) | Trends, `$exception` volume + users affected |

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
| 21 | [Checkout intent](https://us.posthog.com/project/549465/insights/wtBft2H9) | Trends, `desktop_checkout_started` broken down by `billing_interval` |
| 22 | **[Accessibility — prompted vs granted](https://us.posthog.com/project/549465/insights/IU5GESXP)** | Trends, daily bars — `desktop_accessibility_prompted` vs `desktop_accessibility_granted` |
| 23 | **[Checkout funnel — intent to paid](https://us.posthog.com/project/549465/insights/NibQ8aa9)** | Funnel: `desktop_checkout_started` → `desktop_checkout_completed`, ordered, 3-day window |

Tiles 22 and 23 are new on 2026-08-22 and both read zero until a build carrying their
events ships. 22 is the gate tile 5's new step 2 measures, broken out so `source` and
`method` can be read off it — the ratio between the two series says whether the
permission page persuades anyone, and 「システム設定を開く」 vs the system dialog says which
of its two buttons does the work. 23's window is 3 days rather than 14 because Konbini and
bank transfer settle late and arrive as `payment_deferred`; a shorter window would read
those as non-conversions.

Tile 20 is the number this whole document exists to protect. In project 465060 it would
count an iOS-only user as a returning desktop user, every week, forever. Return is an
accepted rewrite rather than a launch, because an app that sits on the screen edge is
"opened" by doing nothing.

### Band 6 — Rewrite attempts & types (0.1.9)

Nine tiles, added 2026-08-24. **Every one of them reads zero until 0.1.9 ships** —
`desktop_rewrite_started`, `desktop_rewrite_abandoned`, `rewrite_type`, `attempt_id` and
`failure_stage` all arrive with that build. Keep the band anyway: an empty tile whose
event has not shipped is a different thing from an empty tile whose event is broken, and
the descriptions say which.

| # | Tile | Query |
|---|---|---|
| 24 | **[Rewrite attempts per day (incl. onboarding)](https://us.posthog.com/project/549465/insights/DtjYwMCL)** | Trends, `desktop_rewrite_started`, count + unique users. **No tutorial filter** |
| 25 | [Onboarding vs real usage](https://us.posthog.com/project/549465/insights/TNqOHEh7) | Tile 24 broken down by `is_tutorial` |
| 26 | **[Attempts by rewrite type](https://us.posthog.com/project/549465/insights/YsTp4rZs)** | `desktop_rewrite_started` × `rewrite_type` × `is_tutorial`, weekly bars |
| 27 | [Success rate by type](https://us.posthog.com/project/549465/insights/wJ5BVQKA) | Formula `B/A` — completed ÷ started, broken down by `rewrite_type` |
| 28 | [Acceptance rate by type](https://us.posthog.com/project/549465/insights/Vsc37M1u) | Formula `(B+C)/A` — (inserted + copied) ÷ completed, by `rewrite_type` |
| 29 | [Attempt outcomes](https://us.posthog.com/project/549465/insights/P5yVs1NT) | completed / failed / abandoned, percent-stacked area |
| 30 | **[Failure stage by type](https://us.posthog.com/project/549465/insights/iJYfHJZF)** | `desktop_rewrite_failed` × `failure_stage` × `rewrite_type` |
| 31 | [Funnel — started → completed → inserted](https://us.posthog.com/project/549465/insights/IGuOzWHW) | Funnel, ordered, 1-hour window, by `rewrite_type` |
| 32 | **[Attempt funnel by type (exact)](https://us.posthog.com/project/549465/insights/uqsAVMt0)** | HogQL table correlated on `attempt_id`. Carries the `unresolved` invariant monitor |

**Tile 24 is deliberately the only unfiltered total on the dashboard.** Onboarding
practice is a real product interaction — a user may retry a lesson many times, and
counting one `desktop_onboarding_completed` per person would miss all of it. Tile 10
remains the real-usage-only view; the pair is the answer, not either alone.

**Tile 32 exists because 31 cannot be exact.** PostHog aggregates funnels per *person*,
and the MCP's `funnelAggregateByHogQL` accepts only `properties.$session_id` — so a user
who presses twice inside the conversion window has their steps interleaved. 32 groups by
`attempt_id` in HogQL instead, which cannot blur. **Read rates off 32 and shape off 31.**

**Tile 32's `unresolved` column is the live invariant monitor and must read 0.** It counts
attempts with a `started` and no ending. `RewriteAttemptTracker` makes that structurally
impossible and `RewriteAttemptTests` proves it under every ordering, so a non-zero value
means a new exit path in `OverlayController` forgot to call `finishAttempt` — the one
failure mode the type cannot prevent, since the controller needs a window server and
cannot be unit-tested.

**Tiles 10, 11 and 13 changed on 2026-08-24, and the way they changed is worth knowing.**
Their tutorial exclusion moved off `host_app_bundle_id` — but *not* to a plain
`is_tutorial = false`, which would have been much worse than the proxy it replaced:
**128 of 144 completed rewrites predate the property**, so an exact-false filter reads
those as excluded and collapses tile 10 from 96 to 9. The filter is a HogQL coalesce —
trust the flag where present, fall back to the bundle id where it is absent:

```sql
JSONExtractRaw(properties, 'is_tutorial') != 'true'
AND (JSONExtractRaw(properties, 'is_tutorial') != ''
     OR properties.host_app_bundle_id != 'com.core7.keigobutton.mac')
```

The proxy was wrong in *both* directions, which only became visible once the flag had
real data: it also excluded **3 real rewrites made with the app window frontmost**
(`prompt_origin: onboarding_preset`, `is_tutorial: false` — an onboarding preset button
pressed after onboarding ended). AGENTS.md used to claim the two "agree by construction";
they do not. Total over 2026-08-01…24 goes **96 → 99**. Tile 11 also gained its missing
`copied` term, so it is now the honest `(inserted + copied) / completed`.

### Supporting breakdowns

Worth adding to tile 10 rather than as their own tiles: `capture_mode`
(`selection` vs `wholeInput` — how people actually invoke the bar) and `prompt_origin`
(which buttons earn their place on the row). Worth adding to tiles 1 and 3: `method`,
once there is enough volume to tell whether Google is carrying sign-up the way
onboarding assumes.

### What is deliberately not here

- **A downloads tile.** See §3 gap 3 — the number does not exist inside PostHog.
- **Working test-account filtering.** Every tile sets `filterTestAccounts: true` and it
  filters nothing, because cohort 467436 keys on `$internal_or_test_user` and no person
  has it. See §4's opening — **keeping the owners in is a decision**, taken 2026-08-22, so
  every tile is "us plus them". The fix, when external volume makes the owners noise
  rather than signal, is one person property on three accounts.

Session replay is a third entry and it is not a choice: see §6.

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

---

## 6. Session replay is not available on this surface

Asked on 2026-08-22, and the answer is structural rather than a configuration to fix.

**0 recordings in the project, all time, and that will not change.** Session replay in
`posthog-ios` (pinned at **3.69.3** in `Package.resolved`) is iOS-only at the source
level, not merely unsupported:

- `PostHogConfig.sessionReplay` and `sessionReplayConfig` are declared **inside
  `#if os(iOS)`** — compiling for macOS, the symbols do not exist. There is no line to
  add.
- Every file under `PostHog/Replay/` is `#if os(iOS)`-guarded, and
  `PostHogReplayIntegration` is only appended to `integrations` inside an `#if os(iOS)`
  block. The capture path is built on UIKit view-tree snapshots.

**The project has the Session Replay product enabled** (`session_recording_opt_in:
true`), which is why PostHog reports replay as an active product for 549465. That is a
server-side switch with no client able to feed it. Leave it; it costs nothing and turning
it off would only make the next person re-derive this.

The consequence worth stating: **there is no qualitative channel on this surface.** No
replay, no heatmaps, no `$pageview`, and the app is an accessory process with no screens
to instrument. Everything anyone will ever know about desktop behaviour arrives as the
events in §3 — which is the whole reason the three gaps closed on 2026-08-22 were worth
closing, and the reason a missing property here costs more than it would on the web.

## 7. Error tracking

**`autocapture_exceptions_opt_in` was `null` until 2026-08-22 and tile 19 was reading
zero for that reason, not because nothing had crashed.** `$exception` had never appeared
in the project taxonomy across 892 events and 13 days.

`PostHogErrorTrackingAutoCaptureIntegration.install` returns
`.skipped(.disabledByRemoteConfig)` when `remoteConfig.isAutocaptureExceptionsEnabled()`
is false, so `config.errorTrackingConfig.autoCapture = true` in
`PostHogConfiguration.configure()` was being overruled server-side. The flag is now on.

Two things to know when reading tile 19:

- **It is a crash tile, not an error tile.** The integration captures Mach exceptions,
  POSIX signals and uncaught `NSException`s — not handled Swift errors. Those reach
  PostHog only as `desktop_rewrite_failed`.
- **A crash is reported on the NEXT launch**, persisted to disk in between, and crash
  reporting is disabled entirely while a debugger is attached. So a crash seen in Xcode
  will never appear here.
