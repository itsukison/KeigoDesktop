# Analytics — the desktop PostHog project

Authority for AGENTS.md §7. **The one rule this document exists to enforce: desktop
numbers and iOS keyboard numbers never touch.**

Status (2026-08-09): **done and live.** Project `KeigoButton Desktop (macOS)` is
**549465** (`phc_sJZEvNvRET7BEwCwXNnzoRofkbowJ8Ec3TuQTz9hHrG6`, org `Keigo`, timezone
`Asia/Tokyo`), the token and host are set on the repo's `production` environment, and
the 15-tile dashboard is built and pinned:

- Dashboard — <https://us.posthog.com/project/549465/dashboard/1974822>

**Not verified: a single real event.** `ingested_event` was `false` at creation and the
tiles have never had data in them. The first desktop build carrying the token is what
proves the pipe, and §5 is the check to run then.

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
| `desktop_onboarding_completed` | `OnboardingWindowController.swift` | — |
| `desktop_source_selected` | `OnboardingWindowController.swift` | `source`, plus person property `attribution_source` (`$set_once`) |
| `desktop_prompt_created` | `MainModel.swift` | `slot` |
| `desktop_prompt_updated` | `MainModel.swift` | `slot`, `is_enabled`, `origin` |
| `desktop_prompt_deleted` | `MainModel.swift` | `slot`, `origin` |
| `desktop_checkout_started` | `MainModel.swift` | `billing_interval` |
| `$exception` | autocapture (`errorTrackingConfig.autoCapture`) | — |
| `$identify` | `MainModel.identifyIfNeeded` | person property `email` |

Plus `surface: macos` on every one of them, including the two the app never calls
`capture` for.

`desktop_source_selected` is the last page of first run (AGENTS.md §15) and is
**self-reported and skippable**: 「答えない」 sends nothing at all, so the event count is
not the number of users who finished onboarding and the shares are of answers, not of
people. `source` is `OnboardingSource.rawValue` — a fixed set pinned by a test, because
renaming one splits a series after the fact. The person property is `$set_once`, so a
replayed 使い方を見る cannot overwrite a first answer (a replay sends nothing either way).

`distinct_id` is the Supabase user id, the same as on iOS. In separate projects that is
a feature rather than a leak: the two platforms can be joined deliberately, in the
warehouse, when someone actually wants a cross-surface number.

### Known instrumentation gaps

These bound what §4 can show, and each is a small change rather than a design problem:

1. **No `desktop_checkout_completed`.** The revenue funnel ends at intent. The Stripe
   webhook (`desktop-stripe-webhook`) knows the answer server-side; nothing forwards it.
2. **No sign-in / sign-up events.** iOS sends `signed_up` / `signed_in`; desktop sends
   neither, so a brand-new desktop user and an existing iOS user installing the Mac app
   are indistinguishable client-side. `desktop.activations` (AGENTS.md §6) is the
   server-side answer and is the one this project should trust for install counts.
3. **`io_path` is only on the two rewrite events.** A capture that fails before a path
   is chosen reports no path at all, so tile 8's denominator is successful captures.

---

## 4. The dashboard — "Desktop (macOS) Overview"

Dashboard **1974822**, 15 tiles, 4 rows. **Every tile carries `surface = macos`** even
though the project is desktop-only; see layer 3.

That filter has a second use beyond defence. Because it is redundant, a *gap* between a
filtered and an unfiltered version of the same tile means events are arriving here
without the surface stamp — which is either a leak from another surface or a capture
running before `registerSurface()`. Either way it is worth chasing, and neither is
visible without the redundancy.

**Ratio tiles use a raw `A/B` formula with `aggregationAxisFormat: percentage_scaled`,
never `A/B*100`.** `percentage_scaled` already multiplies by 100, so a formula that
multiplies too renders 50 % as 5000 %.

### Row 1 — Adoption

| # | Tile | Query |
|---|---|---|
| 1 | [Desktop DAU / WAU / MAU](https://us.posthog.com/project/549465/insights/qKSsc7XX) | Trends, `All events` — `dau` / `weekly_active` / `monthly_active` |
| 2 | [Activation funnel](https://us.posthog.com/project/549465/insights/9cbmwXvI) | Funnel: `desktop_onboarding_completed` → `desktop_rewrite_inserted`, ordered, 7-day window |
| 3 | [Lifecycle](https://us.posthog.com/project/549465/insights/QLMv4ESa) | Lifecycle on `desktop_rewrite_completed`, weekly — new / returning / resurrecting / dormant |

Tile 2 is deliberately `ordered` rather than `strict`: many events fall between finishing
onboarding and the first accepted rewrite, and `strict` would require them to be adjacent.

### Row 2 — The core loop

| # | Tile | Query |
|---|---|---|
| 4 | [Rewrites per day](https://us.posthog.com/project/549465/insights/Rl35xXid) | Trends, `desktop_rewrite_completed`, count + unique users |
| 5 | **[Acceptance rate](https://us.posthog.com/project/549465/insights/bTQAoCs7)** | Formula `B/A` over `desktop_rewrite_completed` (A) and `desktop_rewrite_inserted` (B) |
| 6 | [Acceptance rate by `is_reply`](https://us.posthog.com/project/549465/insights/8nPuiflZ) | Tile 5 broken down by `is_reply`, weekly |
| 7 | [Rewrites per active user](https://us.posthog.com/project/549465/insights/bb5UPyEK) | Formula, `desktop_rewrite_completed` count ÷ unique users |

Tile 5 is the one number to keep. A rewrite that is generated, metered and never
inserted is a cost with no product in it. Tile 6 is §16's stated reason for putting
`is_reply` on both events: reply mode composes from nothing rather than editing what is
there, so its acceptance rate is the only honest read on whether the composition works.

### Row 3 — Health

| # | Tile | Query |
|---|---|---|
| 8 | **[Clipboard fallback rate](https://us.posthog.com/project/549465/insights/AJBcohZ4)** | Trends, `desktop_rewrite_completed` broken down by `io_path`, percent-stacked area |
| 9 | **[Fallback rate by host app](https://us.posthog.com/project/549465/insights/GlRwsGfW)** | Table, `desktop_rewrite_completed` broken down by `host_app_bundle_id` × `io_path`, top 20 |
| 10 | [Failure rate](https://us.posthog.com/project/549465/insights/nWnT70o2) | Formula, `desktop_rewrite_failed` ÷ `desktop_rewrite_completed` |
| 11 | [Failures by message](https://us.posthog.com/project/549465/insights/lWbz9z9i) | Bar, `desktop_rewrite_failed` broken down by `message`, top 15 |
| 12 | [Latency median / p95](https://us.posthog.com/project/549465/insights/wMYLjz07) | Trends, `latency_ms` percentiles on `desktop_rewrite_completed` |
| 13 | [Crashes](https://us.posthog.com/project/549465/insights/uCriz4tu) | Trends, `$exception` volume + users affected |

Rate and diagnosis are two tiles rather than one: a formula and a breakdown cannot share
an insight, and 10 is the number you watch while 11 is the one you act on.

§7 calls `io_path` "the one to watch" and tile 9 is why: a rising clipboard rate *in a
specific bundle id* is the earliest signal that an app's AX tree changed. Tile 8 alone
would average that signal away across every app the user types in. Whatever surfaces in
9 is what `scripts/axdiag.swift` exists for.

Tile 12's budget comes from §5's `AXUIElementSetMessagingTimeout(element, 0.5)` — the
capture side is bounded at 500 ms per element by construction, so p95 growth is the
model or the network, not the AX path.

### Row 4 — Retention & revenue

| # | Tile | Query |
|---|---|---|
| 14 | **[Weekly retention](https://us.posthog.com/project/549465/insights/8QhCncOr)** | Retention: acquisition `desktop_onboarding_completed`, return `desktop_rewrite_inserted`, weekly, 9 periods |
| 15 | [Checkout intent](https://us.posthog.com/project/549465/insights/rWOWxmDc) | Trends, `desktop_checkout_started` broken down by `billing_interval` |

Tile 14 is the number this whole document exists to protect. In project 465060 it would
count an iOS-only user as a returning desktop user, every week, forever. Return is an
accepted rewrite rather than a launch, because an app that sits on the screen edge is
"opened" by doing nothing.

### Supporting breakdowns

Worth adding to tile 4 rather than as their own tiles: `capture_mode`
(`selection` vs `wholeInput` — how people actually invoke the bar) and `prompt_origin`
(which buttons earn their place on the row).

---

## 5. Proving the pipe on the first build

None of the tiles have ever had data in them. When the first build carrying
`POSTHOG_PROJECT_TOKEN` runs:

1. Press a button in any app and check `desktop_rewrite_completed` arrives in 549465's
   live event feed — **and that it carries `surface: macos`**. A missing surface means
   `registerSurface()` is not running where it should.
2. Sign out and press again. This is the `reset()` path: the surface must still be there.
3. Confirm 465060 receives **nothing new** from the desktop over the same window. The
   `desktop_` prefix means a leak shows up as a new event name there rather than as
   silent extra volume on an existing one.
