# AGENTS.md — macOS app

**Read this file first.** Single source of truth for the macOS app that lives in
this folder. `design.md` (Willow style reference, measured from `reference/`) is the
main-window visual authority; `onboarding_reference/` supplies the first-run interaction
reference. This file is the architectural authority. Where they disagree about the
overlay, §8 records the sanctioned deviations.

Status: **MVP implemented, the backend is live, and the app has been run once.**
The first run produced `debug.png` and a round of overlay fixes (§4, §8).

Verified (2026-08-07):

- **2026-08-10 — the shared custom/reply composer no longer asks AppKit to colour its
  placeholder.** In a non-activating panel the native placeholder followed the system
  appearance, ignored the dark overlay palette and rendered black; both ✎ and reply
  guidance became nearly invisible. `InputBar` now gives `TextField` an empty native
  title and draws one explicit `textSecondary` hint layer, matching the result
  refinement field. The reply hint is shortened to 「返信の指示（空欄でおまかせ）」 /
  `Reply instructions (optional)` / 「回复要求（可留空）」 and is unconditionally one
  line, so an empty reply composer stays at its 34 pt floor. The composer also drops its
  separate 返信 / Reply / 回复 capsule: once the placeholder names the mode, that second
  label is redundant, and compression reduced it to an unexplained dark lozenge beside
  the mascot. Only text the user actually types may wrap to `inputBarMaxLines` and grow
  the bar. `swift test` passes all 155
  tests and unsigned `xcodebuild` succeeds with only the existing warnings. **Not
  verified on screen:** all three languages in both composer modes and a real second-line
  typed instruction remain the owner check.
- **2026-08-10 — 保存 was three stacked characters at the shipping window size, and the
  cause was a `Spacer`, not a narrow window.** `SettingsRow` puts `Spacer(minLength: 12)`
  between its title and its trailing content, and the 表示名 row's trailing content was a
  fixed 280 pt field beside an `ActionButton` whose label had no line limit. Two flexible
  children — the greedy `Spacer` and the `Text` — split the leftover, so the Spacer took
  it and 保存 was compressed to its minimum: **measured at the real 714 pt pane, the
  legacy label renders as 3 runs of ink in the button's strip, and at every pane width
  below 680 it renders as 0** — the button vanishes rather than shrinks. A 32 pt plate has
  room for one line, so wrapping there can only ever be clipping. `ActionButton`'s label
  is now `lineLimit(1)` + `fixedSize(horizontal: true)`: measured 1 line at every pane
  from 714 down to 520, and the fix is in the shared component, so all 25 call sites get
  it. The one call site that stretches a button (`PlanView.swift:545`'s
  `.frame(maxWidth: .infinity)`) is unaffected — that frame is outside the label.
  Both states were rendered by a throwaway `ImageRenderer` harness over the real
  `App/Design/` sources and the ink was measured, not eyeballed, because §14 item 1's
  history is that paper gets this wrong.
  **The same pass gave アカウント Google's actual button.** Its 「Google で続ける」 was a
  `.secondary` `ActionButton` with no mark on it while onboarding had a correct one in a
  `private struct` — so the two had already drifted. `GoogleSignInButton` now lives in
  `App/Design/Components.swift` with two sizes: `wide` (42 pt, fills the column, first
  run) and `inline` (32 pt, hugs its content, beside サインイン on アカウント), sharing one
  white plate, one `#747775` border, one `#1f1f1f` label and one G. The artwork is
  200×204, so it is fitted inside its square rather than forced into it — a bare
  `frame(width:height:)` squashed the G by 2%. `assetutil` confirms `GoogleG` is in the
  built `Assets.car`. Components.swift now imports `DesktopRewriteKit` for `tr`, which is
  the first time the design layer needed the kit; the alternative was the same three
  strings in two feature folders again.
  `swift test` passes **155 tests** and `xcodebuild` succeeds with only the two
  pre-existing concurrency/AppIntents warnings. **Not verified: either surface on
  screen.** The row and both button sizes were rendered offline; the G itself cannot draw
  outside the app bundle, so its placement in the inline button is geometry that has been
  measured and artwork that has not been looked at in place.
- **2026-08-10 — sign-in happens on `auth.keigobutton.com`, and only sign-in.**
  The Google flow used to open with macOS quoting `eercsucvxnszqletxued.supabase.co`
  back at the user, because macOS builds that consent alert from the host of the URL
  handed to `ASWebAuthenticationSession` and reads nothing Google is configured with —
  so branding the Google consent screen (done the same day, in the Cloud console) fixes
  the second surface and provably cannot touch the first. `SupabaseConfig` now carries
  `authURL` beside `supabaseURL`; `authEndpoint` derives from the former and
  `restEndpoint` / `rewriteEndpoint` from the latter, so the two hosts are independent
  inputs rather than one derived from the other. REST and Functions stay on
  `<ref>.supabase.co` on purpose: nothing about them is shown to a human, and the auth
  host is the milder of the two to lose — `ensureFreshAccessToken` already falls back to
  the stored token. **The live custom domain was read back rather than assumed:** the
  certificate is `CN=auth.keigobutton.com` from Google Trust Services (valid to
  2026-11-08), `/auth/v1/health` answers GoTrue's own "No API key found" 401, and
  `/auth/v1/authorize?provider=google` 302s to `accounts.google.com` carrying
  `redirect_uri=https://auth.keigobutton.com/auth/v1/callback` — which is the URI that
  must stay on the Google client's allow-list beside the old `.supabase.co` one, and
  **Google accepts it**: following that 302 lands on `accounts.google.com/v3/signin`
  rather than the 400 a `redirect_uri_mismatch` would produce.
  `swift test` passes **155 tests** (5 new, pinning both hosts, the authorize URL's host
  and its unchanged `keigobutton://auth-callback`, and that the two hosts stay distinct),
  and `xcodebuild` succeeds with only the two pre-existing concurrency/AppIntents
  warnings. **Not verified: one real Google sign-in through the new host.** No build
  carrying it has run, so the alert's new wording is reasoned from where macOS gets the
  string, not looked at. iOS was not touched and needs no change.
- **2026-08-10 — regeneration now adds a page instead of erasing the answer it
  replaced.** The first result is `1 / 1`; each completed plain or guided regeneration
  appends its candidates, selects the first new one and advances to `2 / 2`, `3 / 3`,
  and so on. The header arrows traverse that in-memory session, and the echoed prompt
  travels with the selected body because guided pages can have different instructions.
  `ResultPage` keeps the candidate beside the `PendingRewrite`, backend event id,
  response-local candidate index and local history-row id that produced it. That is
  load-bearing: Insert, copy, feedback, another plain reroll and another guided refinement
  all act on the page visibly selected, without reporting an old answer against the
  newest event or marking the wrong history row accepted. Cancel or request failure
  restores the full pre-regeneration result context rather than dropping the comparison.
  No backend or wire change was needed. `swift test` passes all 155 tests and unsigned
  `xcodebuild` succeeds with only the existing warnings. **Not verified on screen:** one
  real three-page sequence, back/forward prompt echo, refining page 1 while page 3 exists,
  and inserting an older page remain the owner check.
- **2026-08-10 — regeneration refinement now morphs in place instead of changing the
  result panel's height.** Hovering ↻ expands that 28 pt control across the same fixed
  footer row, covering copy, feedback and Insert rather than moving them or growing the
  panel. The input reveals left-to-right while ↻ rides its right edge and crossfades
  into an upward Send control at the far right. Its hit target stays 28 pt but the dark
  Send disc is inset to 20 pt so the input mask cannot clip it. The native placeholder
  stays empty; a SwiftUI `textSecondary` layer supplies the hint because AppKit ignored
  the prompt foreground and rendered it black in this non-activating panel. Fill and
  contents are clipped first and the constant hairline is drawn afterward, so the
  animated mask cannot shave the border. Leaving the combined bar restores the untouched
  row after a 140 ms settle; clicking into the field pins it for typing, and
  Escape clears and collapses it. Sending an empty field is the old plain regeneration,
  while a guided run is semantically different:
  the candidate on screen becomes the model's source text and the typed instruction
  becomes its prompt, while `CapturedTarget` remains the original field where Insert
  writes. In reply mode the candidate becomes `<existing_draft>`, so the same UI refines
  a composed reply instead of restarting it from an empty draft. `PendingRewrite` now
  keeps `requestText` separately from the write target so a subsequent plain ↻ rerolls
  the same guided request rather than silently falling back to the first original. The
  result body keeps its full viewport in both states; hover now changes no measured
  dimension at all. No backend or wire-contract change was needed. `swift test` passes
  all 150 tests and unsigned `xcodebuild` succeeds with only the existing warnings.
  **Not verified on screen:** the expansion curve, hover-to-field handoff, focus/Escape
  behavior and one real guided rewrite/Insert still need the owner check.
- **2026-08-10 — the gentle reminder reached no surface, and that is why nobody ever
  saw a toast.** The 2026-08-09 entry below is accurate about everything it built and
  wrong about the one thing that mattered: it declined Sparkle's own scheduled alert
  (`standardUserDriverShouldHandleShowingScheduledUpdate` returns `false`
  unconditionally, `immediateFocus` included) and routed the announcement into a card
  rendered **only** by `HomeView.body` — inside a window an `LSUIElement` app with no
  Dock icon gives nobody a reason to open. `grep` over `App/` and `Sources/` finds zero
  `UNUserNotificationCenter`, `NSUserNotification`, `requestUserAttention` and
  `dockTile`, and nothing called `openMainWindow()` on discovery. Turning Sparkle's UI
  off and replacing it with something invisible is strictly worse than leaving it on,
  which is what 0.1.2 shipped. The plumbing was never the problem and was verified
  against Sparkle 2.9.5's own source (`SPUStandardUserDriver.m:290-311`): returning
  `false` does keep the session alive and does call
  `standardUserDriverWillHandleShowingUpdate` a runloop later, so `offerUpdate` really
  did fire into a `@Published` string nobody could see. It was also in-memory only, so
  quitting erased even the possibility, and `SUScheduledCheckInterval` is a day.
  **Three surfaces now, because no one of them is sufficient**: a constant-height
  `UpdateNoticePanel` stacked 8 pt above the bar (`ReplyContextPanel`'s pattern in every
  respect — never key, never measured-height, stands down in `.generating` / `.result`
  where the bar is *replaced* rather than stacked on, and in the reply states where the
  context pill already owns that space), a hidden-until-pending status-menu row with a
  knocked-out template dot on the menu-bar glyph, and the existing ホーム card. The
  dashboard opens itself **once per version**, on the run that discovers it — not on the
  relaunch replay, and never for a version the user dismissed — and it opens through the
  new `MainWindowController.presentWithoutActivating()`, which is `orderFrontRegardless`
  with no `NSApp.activate`. That last part is not a detail: Sparkle's own launch-time
  alert was declined because `immediateFocus` means the find landed within three seconds
  of the updater starting (`SPUStandardUserDriver.m:198`), and for an app registered with
  `SMAppService` that is *during login* — so a dashboard that activated would have
  committed the same offence, at the same moment, that declining Sparkle avoided. Every
  other caller keeps `present()`: the user asked for that window. Dismissing the panel
  silences that panel for that version only; the row and the card stay, and Sparkle
  keeps ownership of the real skip. `PendingUpdateStore` persists the find so it
  survives a quit, and `pending(for:)` self-clears once the running build has caught up,
  which is also the post-install cleanup. `desktop_update_offered` /
  `desktop_update_accepted` exist because the whole path is otherwise unobservable —
  the ratio is the only evidence the announcement works. `swift test` passes **150
  tests** (13 new, all on `PendingUpdate`: numeric comparison so `0.1.10` beats `0.1.9`,
  the install-clears-the-record case, and dismissal not surviving into the next
  version), and `xcodebuild` succeeds with only the two pre-existing
  concurrency/AppIntents warnings. The row arithmetic was **measured, not eyeballed** —
  a throwaway `ImageRenderer` harness rendered the card at its 300 pt width in all three
  languages and confirmed the sentence, the action pill and the ✕ fit with 145–190 pt to
  spare, so `lineLimit(1)` never eats the version number. **Not verified: any of it in
  the running app, and not one real Sparkle discovery.** A stale instance from 13:08 held
  the bundle id and this environment cannot signal it (the same limitation this file
  records twice already), so the panel, the menu row and the badge have been rendered and
  reasoned, not looked at. Quit from the menu-bar 終了, relaunch, and note that a Debug
  build's `SUPublicEDKey` is empty by design (`startUpdaterIfConfigured` returns early),
  so a real end-to-end discovery needs a signed release — seed
  `defaults write com.core7.keigobutton.mac updates.pendingVersion -string 0.1.3` to
  exercise everything downstream of Sparkle. Delete `SULastCheckTime` before testing the
  real chain or the 86400 s interval, not the UI, is what is under test.
  **One thing this cannot fix, and it bounds the next release.** The announcing code has
  to be in the *installed* build, so 0.1.4 is the first version that can show any of it.
  Everyone on 0.1.0–0.1.3 is unreachable — they will not be prompted for 0.1.4 and will
  not be prompted for anything after it; manual 「アップデートを確認…」 or a fresh DMG is
  their only path, and that is a distribution problem rather than a code one. 0.1.4 →
  0.1.5 is the pair that finally exercises both this and the install chain
  `docs/releasing.md` has listed as outstanding since the first release.
- **2026-08-10 — `v0.1.3` is published, and it is the first release that makes the
  Sparkle chain testable.** Run `31355973591` succeeded in both jobs from commit
  `7b00774`, carrying the welcome-offer/USD pricing work and the two new analytics
  events. Read back rather than assumed: the public
  `/releases/latest/download/KeigoButton.dmg` matches GitHub's SHA-256 digest,
  `stapler validate` passes, Gatekeeper reports `Notarized Developer ID` for team
  `4KS6YS23KT`, and the live Pages appcast has 0.1.3 newest at `sparkle:version` 6
  with an enclosure length equal to the released ZIP. **Not verified: an installed
  0.1.2 updating itself to 0.1.3.** That is the one thing `docs/releasing.md` has
  listed as outstanding since the first release, and it is now the pair to test on —
  install the 0.1.2 DMG on a clean account, then use 「アップデートを確認…」.
- **2026-08-10 — English is priced in dollars, and first run now makes one offer.**
  §17 split interface language from writing language and left a third question
  unasked: what an English user is *charged*. They were quoted ¥1,480 in English
  sentences. English now means **USD — $12/month, $120/year** — while 日本語 and
  简体中文 stay on ¥1,480 / ¥14,400, because §17's premise is that a 简体中文 user is a
  Chinese speaker working in Japan and their card is a Japanese card.
  `BillingCurrency.forInterface` is the only place that rule lives, beside
  `writesJapanese`. $120 was chosen over $96 or $99 for one property: it divides by
  twelve into $10, and $144 − $120 is **exactly two months**, so the existing
  「2ヶ月分お得」 badge is literally rather than approximately true — and it is now
  *computed* from the two list prices rather than written down. **No new Stripe
  product and no new prices**: USD is `currency_options[usd]` on the two prices that
  already exist, which keeps `pro_monthly_jpy` / `pro_yearly_jpy` the only sellable
  keys and keeps the Customer Portal able to move a subscriber between intervals
  without knowing about currency. The `_jpy` suffix now names each price's *default*
  currency; renaming would need `transfer_lookup_key: true`, which strips the key off
  the old price. A **new `.offer` step** (raw value 11) sits between きっかけ and 完了
  — after the three practices that are the argument for paying, before the page that
  hands the app over — offering **33% off the first period** (¥9,600 / $80 a first
  year, ¥980 / $8 a month for three) for **72 hours**. It is two Stripe coupons
  applied server-side, never a third price and never a promotion code; eligibility
  lives entirely in `desktop.welcome_offers`, whose rows are **never deleted**,
  because a primary key that is never removed is the whole enforcement of "once per
  account". Declining is safe — a ホーム card carries the same price and deadline
  until the window closes. `currentVersion` stays **2**, so users who already
  finished first run are never replayed into it. `swift test` passes **137 tests**
  (14 new), `xcodebuild` succeeds with no new warnings, and `deno check` +
  `deno lint` are clean on all four functions.
  **The live Stripe catalog is done and was read back rather than assumed:** both
  prices carry `currency_options[usd]` at 1200 / 12000 with `tax_behavior: inclusive`,
  and `welcome_monthly_33` (¥500 / $4, `repeating` ×3) and `welcome_annual_33`
  (¥4,800 / $40, `once`) exist, restricted by `applies_to` to the Pro product, at
  `times_redeemed: 0`. No product was created, no price was created, nothing was
  archived, and no existing subscription was touched.
  **The backend is deployed and was exercised against the live project.** The
  migration `20260810120000_desktop_usd_pricing_and_welcome_offer.sql` **is applied**,
  and its four drop-and-recreates left exactly one of each function with the grants
  intact — read back from `pg_proc`, not assumed, because a dropped-and-recreated
  function is precisely where a grant goes missing and the failure is silent.
  `desktop_get_entitlement()` and `desktop_start_welcome_offer()` are the only two
  `desktop_*` entry points `authenticated` can reach; `anon` reaches none.
  `desktop-checkout` is **v6** (`verify_jwt` true, 401 without a JWT, 200 on OPTIONS)
  and `desktop-stripe-webhook` is **v3** (`verify_jwt` false, 400 on a missing
  signature, 405 on GET). `DESKTOP_WELCOME_COUPON_MONTHLY` / `_ANNUAL` are set.
  **Six assertions were run against the live database on a throwaway `auth.users` id
  and every row was removed afterwards** (0 left in `welcome_offers`, `subscriptions`
  and `auth.users`): calling `desktop_start_welcome_offer()` twice yields one row and
  the same deadline, the window is 72 hours to within a minute, a never-subscribed
  account reports a **null** currency rather than a guessed yen, `usd` round-trips
  through `desktop.subscriptions.currency` into `billing_currency`, an account that
  has ever held a subscription is refused **while its offer row survives**, and an
  expired deadline reads back as null.
  **Not verified: one payment in either currency, one redeemed coupon, and none of
  the UI on screen.** The Stripe MCP exposes no Checkout Session operation, so no
  session has been created in USD by hand — the deployed function is the only thing
  that creates them, and proving it needs a real signed-in user. One artifact of
  trying: **empty live customer `cus_V2qJQoKQWHhoYB`** (`delete_me: true`, no
  invoices, no payments). §0's rule is that bare customers are left in place, and
  the MCP has no delete operation either way.
  **One thing found while auditing the account, and it is not part of this work:**
  promotion code **`TEST` is live, active, unlimited and 100% off**, on an account
  where every undiscounted session sets `allow_promotion_codes: true`. Anyone who
  types it gets Pro free. **It is still there** — the Stripe MCP exposes no
  promotion-code update operation, so archiving it is a Dashboard action.
- **2026-08-10 — the dashboard measured the loop and not the funnel into it, and
  the two events it needed did not exist.** 549465 has been ingesting since
  2026-08-09 21:21 JST, so the 15 tiles could finally be read against real data
  rather than imagined — and what they could not answer was how many people
  arrived, signed up or finished first run on any given day. `MainModel` now sends
  `desktop_signed_up` and `desktop_signed_in` (§7), closing the gap
  `docs/analytics.md` §3 listed second; `refresh()`'s restored Keychain session
  deliberately sends neither, and Google is separated by the age of the
  `profiles` row rather than by anything in the session, which carries no such
  signal. `Desktop (macOS) Overview` went from 15 tiles to **21 in five bands**,
  the six-tile acquisition band modelled on 465060's own
  `Product KPIs — code-aligned (v2)` — read for structure only; nothing was
  written there and the MCP was switched back to 549465 before any change.
  Two things were **measured on the live project rather than assumed**:
  `Application Installed` carries no `surface` on 0 of 2 rows, because the SDK
  captures it inside `setup()` before `registerSurface()` can run — so tiles 1, 2
  and 5 run unfiltered by necessity, not by omission — and onboarding practice
  emits both rewrite events, so the acceptance rate counts three scripted Inserts
  per new user until an `is_tutorial` property exists. `xcodebuild` succeeds with
  only the two existing concurrency/AppIntents warnings and all 135 tests pass.
  **Not verified: one real `desktop_signed_up`.** No build carrying the two events
  has shipped, and the Google branch's ten-minute window has not met a real new
  account — the release after this is what proves both.
- **2026-08-09 — Sparkle updates now announce themselves on ホーム.** This is
  Sparkle's gentle-reminder path, not a second updater: a scheduled background check
  that selects a valid compatible appcast item no longer opens the standard alert
  behind whatever app an accessory process happens to be under. It publishes only the
  display version into `MainModel`, and ホーム inserts one compact Willow card directly
  below its usage row — white canvas, hairline, tinted product mark, version badge and
  one indigo 「アップデートする」 action. Pressing it asks the existing
  `SPUStandardUpdaterController` to bring that already-selected update into focus, so
  Sparkle still owns release notes, skip/dismiss, EdDSA verification, download and
  installation. Manual 「アップデートを確認…」 checks remain standard Sparkle UI, and
  the dashboard card clears once the update receives the user's attention or its
  session ends. The built debug binary advertises all five expected Objective-C gentle
  reminder selectors, unsigned `xcodebuild` succeeds with no new warnings, and all 105
  tests pass. **Not verified with a newer live release:** the current build needs an
  appcast version above itself to exercise scheduled discovery → card → Sparkle window
  end to end.
- **2026-08-09 — hover expansion is one motion instead of two competing ones.**
  The apparent display-size difference was an animation sequencing bug: changing to
  `.hoverRow` immediately animated the new 34 pt height against the collapsed 44 pt
  width, then SwiftUI reported the row's intrinsic width one layout pass later and a
  second 0.16 s ease-out retargeted the same window. The smaller display made the
  vertical-pop-then-horizontal-stretch discontinuity easier to see; it did not select
  another animation path. Content measurements now carry the identity of the subtree
  they measured, stale outgoing measurements are ignored, and the transition waits for
  one fresh width/height pair before animating the frame once. `PillPanel`'s hosting
  view also has `sizingOptions = []`, so AppKit's controller is the only owner of the
  window frame instead of racing `NSHostingView.standardBounds`. All three mascot
  atlases are decoded and sliced before the panel appears and retained, removing the
  cold engaged-atlas decode from the first 160 ms hover. A reduced real-`NSHostingView`
  harness confirmed that disabling sizing still reports the full intrinsic row width
  from a 44 pt window and that the layout identity produces one fresh callback. An
  isolated unsigned `xcodebuild` succeeds with only the existing concurrency/AppIntents
  warnings, and all 105 tests pass. **Not verified on the MacBook screen:** hover in and
  out repeatedly, including the first hover after launch and a pill parked near an
  edge, to judge the motion itself.
- **2026-08-09 — 「使うボタンを確認」 rebuilt around one cause.** Three complaints —
  the left column was not centred like every other page, pressing ✎ animated
  unnaturally, and the preview column moved when the left column did — were one
  structural fact: a `ScrollView` has no natural height, so the column could never be
  centred, and every height change inside it propagated outward. The list is now capped
  at `rowHeight` (74, applied to the closed row rather than assumed of it) × the count
  plus the gaps, and stays flexible below the cap: the column gets a natural height and
  is centred with `.frame(maxHeight: .infinity)` like the others, while a long set is
  still compressed and still scrolls. Because the cap comes from the count and not from
  the content, an opened row grows *inside* a viewport that does not move — the heading,
  the 追加 action and the preview all stay put — and the row is scrolled to the top of it
  under the same curve. The editor's `.move(edge: .top)` is gone (it described the same
  event the row's growth already did) and the preview column's
  `alignment: isEditing ? .topLeading : .leading` is gone with it; the stage now spans
  the full height, which is §15's invariant everywhere else. `xcodebuild` succeeds with
  no new warnings and 105 tests pass. **Not verified: any of it on screen.** The
  geometry was worked out on paper — 542 pt of usable height, a four-row list at 328,
  a block of 474 leaving 34 pt above and below, and an expanded row of 275 inside the
  328 pt viewport — and paper is exactly what got the overlay's panels wrong twice
  (§16). Open the page with four buttons, press ✎ on the last row, and watch whether
  anything outside the list moves.
- **2026-08-09 — first run now asks where the user came from.** A tenth step,
  きっかけ, sits between 返信 and 完了 — the last thing asked, but deliberately *before*
  the page that hands the app over. Eight options; X, YouTube, Instagram and TikTok carry
  their real App Store artwork, pulled through the ASO MCP's `get_app_details` for the
  **jp** storefront (`333903271`, `544007664`, `389801252`, `1235601864`) and bundled at
  1×/2× as `Assets.xcassets/Source*`, while the four non-app answers are Reicon on a
  plate. The page is 用途's composition reused rather than a new layout, and the artwork
  is bundled rather than fetched at runtime because a survey is not a reason to make a
  network call. Answering is optional: 「答えない」 goes straight to 完了 and sends nothing,
  so the series counts answers, not people. `desktop_source_selected` carries
  `source` = `OnboardingSource.rawValue` plus a `$set_once` `attribution_source` person
  property, and a 使い方を見る replay sends nothing at all. `source` is appended at raw
  value 9 so unfinished saved steps still resolve, `currentVersion` stays 2 so users who
  finished before the page existed are not asked, and two new tests pin both the wire
  keys and the question's position before 完了. `xcodebuild` succeeds with no new
  warnings and all 105 tests pass. **Not verified: the page on screen, and not one real
  event.** The grid was sized on paper (297 pt cards in the 642 pt stage, four rows
  inside the available height) rather than looked at, and 549465 has still never received
  an event of any kind — `docs/analytics.md` §5 remains the check to run on the first
  build carrying the token.
- **2026-08-09 — onboarding detail pass: mascot tone, review tracking and practice
  editor geometry.** The welcome mascot was dark because the whole white-field video
  used `.multiply`: it removed the field by also multiplying the keycap's off-white
  body and shadows into lavender. The video now keeps its source colour and feathers
  only its outer edge into the stage. On ボタン, the preview group has a stable 280 pt
  scene and is vertically centred until an editor opens, then top-aligns so the edited
  row and preview are easy to track together. The intermittent edit/delete miss was in
  the shared cursor bridge rather than either callback: its AppKit tracking view still
  participated in hit testing beneath SwiftUI buttons; `CursorRectView.hitTest` is now
  pass-through while its tracking areas remain active. The three practice scenes share
  an explicit `NSTextView` font/inset layout, so the caret and text use the same native
  geometry, and their success badges moved into the heading row instead of covering the
  editable message. `xcodebuild` succeeds with no new warnings and all 103 tests pass.
  **Not verified: the running onboarding window.** The local Computer Use runtime was
  unavailable, so repeated edit/delete clicks, the animated mascot blend and the live
  caret/success transition still need the owner check.
- **2026-08-09 — the two timed switches are reachable from the menu bar, not only
  from the pill.** Hiding the bar and disabling the copy trigger (§16) were
  right-click-only, which left them undiscoverable and left the hide asymmetric: the
  status menu could already *undo* it, because a hidden pill has nothing to right-click.
  The menu now carries one row each — 「敬語ボタンを1時間非表示にする」 and
  「コピー機能を1時間無効にする」 — and each row flips to
  「…を今すぐ再表示する／有効にする（残りN分）」 while its window is in force, so there is
  never a stale 「無効にする」 sitting under an active one. **One hour only from here**; the
  pill's own menu keeps both 10分 and 1時間. `menuNeedsUpdate` writes the titles at open
  time and the selectors re-read the state at *click* time, so a window expiring while
  the menu sits open still does what the row says. `setVisible(true)` now clears the hide
  deadline itself, which is what makes onboarding safe: it puts the real bar on screen for
  its own lesson, and a deadline surviving that would leave the menu offering 再表示 for a
  bar already on screen. `cancelHideNow` and `checkHiddenExpiry` lost their duplicate
  clearing, and `OverlayController` gained `isCopyTriggerDisabled` /
  `copyDisabledRemainingMinutes` / `enableCopyTriggerNow` so both menus ask the same
  object instead of reading `ClipboardWatcher` twice. `xcodebuild` succeeds with no new
  warnings and all 103 tests pass. **Not verified: the menu on screen.** No pure logic was
  added — the durations and the countdown are `OverlaySnooze`, already tested — so what is
  unproven is entirely the AppKit surface: the two rows' titles flipping, and a hide
  started from the menu bar coming back an hour later.
- **2026-08-09 — onboarding now teaches ✎, and reply guidance is intent rather than
  sendable prose.** The visual flow is nine steps: アカウント → 用途 → ボタン →
  アクセス → the real pill → 書き換え → カスタム → 返信 → 完了. The new full-width
  Mail practice keeps a live focused editor, opens the production custom-input path,
  rejects empty guidance, stays out of history/statistics, and completes only after a
  successful Insert; saved buttons cannot complete it. All previous raw step values
  remain fixed (`complete = 6`, `replyPractice = 7`) and `customPractice = 8`, so an
  unfinished reply lesson resumes there and completed v2 users are not replayed.
  `desktop-rewrite` now separates `<received_message>`, `<existing_draft>` and
  `<reply_guidance>`; copied content is escaped and explicitly untrusted, while guidance
  may carry facts, stance, fragments or style. Replies must be complete and sendable,
  preserve supplied facts, never invent decisions or commitments, default to
  context-aware professional language, and let explicit style requests win. The normal
  rewrite prompt is unchanged. `swift test` passes all 103 tests, `xcodebuild` succeeds
  with no new warnings, and six Deno prompt tests plus `deno check` / `deno lint` pass.
  **`desktop-rewrite` v9 is ACTIVE with `verify_jwt = true`;** a request without a JWT
  401s as `unauthorized`, and its downloaded deployed `index.ts`, `prompt.ts` and
  `redact.ts` match the local SHA-256 hashes. Six authenticated
  production reply cases passed: an availability fragment became a complete acceptance,
  a decline kept its supplied reason, empty guidance acknowledged without choosing
  availability, an existing draft was integrated once, Slack stayed concise, and copied
  prompt injection was ignored. Two throwaway Auth accounts were deleted through the
  production deletion function; password login then returned `invalid_credentials`.
  **Not verified: the running nine-step window or either real custom/reply Insert path.**
  The required local UI-control runtime was unavailable in this session, so those remain
  an owner check rather than a claimed visual result.
- **2026-08-09 — the signed-out bar said the wrong thing, and the signed-out account
  page was two pages.** Hovering the pill with no session showed
  「ボタンを読み込めませんでした」 — a network apology for a problem no retry can fix,
  and it was reached because `UserPromptRemoteStore` collapsed *every* failure into
  `RewriteError.backend`, so the row had no way to tell a dropped connection from a
  missing account. `authorize` now wraps a missing session as `notSignedIn` the way
  `DesktopRewriteService.post` already did, and 401/403 maps to it too (a refresh
  failure deliberately falls back to the stored token, so an expired session is
  rejected by PostgREST rather than locally). `OverlayController.signedOut` is that
  state: the stale buttons are dropped, ✎ goes with them, and the row becomes
  「サインインするとボタンが使えます」 plus a filled サインイン pill that collapses the
  row and calls the existing `onSignInRequired` → アカウント in sign-in mode (§4
  Errors). The account page's signed-out half lost its two-column split — a marketing
  panel next to a form pinned at 460 pt inside a pane twice that wide — and is now one
  column of the same row groups the signed-in half uses, with the sync claims as
  captioned rows that survive signing in (§14). `xcodebuild` succeeds with no new
  warnings and all 98 tests pass. **Not verified: either surface on screen.** The row
  needs a real pointer on the bar (§14 item 1) and the page needs the window open with
  no session; both are compiled and reasoned, neither has been looked at.
- **2026-08-09 — 「使うボタンを確認」 always failed on the first attempt, and it was a
  second unique key nobody had read.** `user_prompts` carries
  `user_prompts_user_builtin_unique (user_id, builtin_key) WHERE builtin_key IS NOT NULL`,
  so a `builtin_key` is an *identity*, not a label — an account owns at most one `polite`
  row. `replaceAll` upserts `on_conflict=id` and a preset pack mints fresh ids, so the id
  conflict never fired, the partial index did, and PostgREST answered **409**. This was read
  off the live project rather than theorised: two `POST /rest/v1/user_prompts?on_conflict=id`
  409s in the API log, and `duplicate key value violates unique constraint
  "user_prompts_user_builtin_unique"` in the Postgres log at the same two timestamps.
  It is not intermittent and it is not the network the toast blames: `handle_new_user()`
  seeds **every** account with all four keys at signup, so `starter` (4 keys), `japanese`
  (`polite`) and `international` (`translateToEnglish`) collide 100 % of the time, while
  `work` and `social` carry no keys and always went through — which is exactly why switching
  packs "fixed" it. 「現在のボタンを使う」 was never affected; it sends the owned ids.
  `UserPromptIdentity.reconciled` (pure, 6 tests) now re-points an incoming button at the row
  the account already owns for its key, keeping that row's `created_at`, and `replaceAll`
  reads the current rows first to do it. Reordering the write to delete-then-insert was
  rejected: it fixes the symptom by making a half-failed write able to leave an account with
  no buttons at all. Reproduced and fixed **against the live table** on a throwaway
  `auth.users` id — the pre-fix shape raised the same 23505, the reconciled shape updated all
  four rows in place with no new rows, and the user was deleted afterwards (0 rows left in
  `auth.users`, `user_prompts`, `profiles`). `xcodebuild` succeeds and 98 tests pass.
  **Not verified: the running review page.** The failing and passing shapes are proven at
  the SQL layer and in the client's reconciliation, not by watching the step advance.
- **2026-08-08 — Sparkle updater and GitHub release pipeline are wired.** Sparkle
  2.9.5 is pinned in `project.yml`; the app starts its updater only after onboarding,
  exposes `アップデートを確認…` from the status menu, and defers update presentation
  while the overlay is doing capture, generation, input or result work. Production
  builds take the EdDSA public key from `SPARKLE_PUBLIC_ED_KEY`; a missing key leaves
  local builds usable but deliberately does not start the updater. The manual
  `release-macos.yml` workflow builds a universal Developer ID archive, rejects sandbox
  or debug entitlements, notarizes and staples both the app and DMG, generates a signed
  appcast, publishes a GitHub release, then deploys the appcast to GitHub Pages. A clean
  Debug build, an unsigned universal Release build and all 98 tests pass. **Release
  credentials were completed on 2026-08-09:** Keychain reports the required
  `Developer ID Application` identity for team `4KS6YS23KT`; the App Store Connect Team
  API key authenticated with `notarytool`; the permanent Sparkle Ed25519 key lives in
  Keychain; and the two GitHub environments, Pages, Actions permissions, six production
  secrets and public-key variable are configured. **`v0.1.0` was replaced successfully
  on 2026-08-09 before public announcement:** workflow run `31297160268` exported the
  universal `KeigoButton.app`, verified its
  Developer ID signature and hardened/no-sandbox entitlements, notarized and stapled
  the app and Willow-styled `KeigoButton.dmg`, signed the Sparkle archive/appcast,
  published both release assets and deployed Pages. The stable
  `/releases/latest/download/KeigoButton.dmg` URL resolves; the downloaded public DMG
  matched GitHub's SHA-256 digest, passed `stapler validate`, and Gatekeeper reported
  `Notarized Developer ID`. Its mounted contents carry the saved Finder layout,
  `KeigoButton.app`, and the Applications link. **Not verified: dragging this replacement
  public DMG into Applications and the old-build → new-build Sparkle update chain.** See
  `docs/releasing.md`.
- **2026-08-08 — adaptive rewrite practice and a real reply practice.** Onboarding is
  now eight steps: アカウント → 用途 → ボタン → アクセス → the real pill → 書き換え
  → 返信 → 完了. The first practice's live Mail draft is selected from the reviewed
  main button's builtin key, title and instruction rather than always being a casual
  sentence for 敬語; the real pill exposes every reviewed button, and Insert from any
  one completes the lesson. The new full-width Slack scene
  has one live copy action and one live `TextEditor`: copying arms the production reply
  state, focusing the composer preserves the same-process AX target, and Insert must
  write the generated reply back before the step completes. Both tutorial paths stay
  out of history and statistics. Onboarding prose and progress use the same reusable
  production-shaped `PillPreview` as Home instead of writing 「バー」 as an abstract
  label. Existing raw step values remain unchanged and `replyPractice` is appended at
  7, so an unfinished v2 setup still resumes correctly; `currentVersion` remains 2 so
  this content change does not force completed users through first-run again. `swift
  test` passes all 89 tests and `xcodebuild` succeeds. **The running copy → hover →
  reply → Insert path and the eight-step layout still need an owner check.**
- **2026-08-08 — onboarding visual system rebuilt around realistic desktop scenes.**
  The seven-step state machine, fixed 1080×700 window, shared navigation shelf and real
  tutorial overlay are unchanged. Explanatory steps now use a consistent question-left /
  visual-right composition, with a lavender stage copied from the landing page's own
  desktop scene (`#efecfa → #ddd8f2 → #c8c1e8`, with white and lavender radial light).
  The access illustration is now a detailed System Settings window rather than one
  symbolic row; button review, bar education and completion use the same realistic Mail
  composer and production-shaped overlay preview. Practice is the deliberate full-width
  exception, matching the reference's large app scene while retaining the original live,
  focused `TextEditor` as the same-process AX target. The mock controls are illustrative
  only; permission and navigation actions remain in the bottom shelf. `xcodebuild`
  succeeds and all 87 tests pass. **The owner is doing the running visual check.**
- **2026-08-08 — subscriptions, from the schema up to the cap-hit surface.**
  `docs/billing.md` is the authority and its §11 is the checklist; this is what changed
  here. The billing schema turned out to be **already applied** (`desktop_billing`,
  `desktop_billing_cron`) — the document said otherwise and was wrong. What it did not
  have was an entry point for `desktop.checkout_intents` or `desktop.stripe_events`:
  `desktop` is not an exposed schema (§6), so those two tables were unreachable and the
  Edge Functions were unbuildable. `20260808140000_desktop_billing_entry_points.sql`
  adds the wrappers plus `desktop_process_stripe_event`, which preserves §5's "mark the
  event processed in the same transaction as the write" over a transport that cannot
  hold a lock across an HTTP call. Three new functions — `desktop-checkout` (§3.3's four
  race defences; the price is resolved from a lookup key **server-side**),
  `desktop-portal` (one call, no retention interstitial — §10), and
  `desktop-stripe-webhook` (raw-body HMAC, `v1` scheme only, payload read for the
  customer id and nothing else). `desktop-rewrite`'s bump-then-check guard is replaced
  by reserve/commit/release: a rejected request no longer consumes quota, a failed
  provider call is released, and `requestId` on the wire makes a retry idempotent.
  Client: `PlanView` in the ⚙︎ modal, a quota row on ホーム carrying the **computed**
  reset date (§4.5), and three distinct cap-hit surfaces — free-at-50 opens the paywall,
  Pro-at-1,000 does not, a brake is neither (§9 rows 41–43). `xcodebuild` succeeds with
  no new warnings, 87 tests pass, `deno check` + `deno lint` clean on all four functions.
  `20260808140000` **is applied** — 11 entry points, and §3.3a's "two callers leave with
  one session and one idempotency key" smoke-tested against a throwaway id with the rows
  cleaned up afterwards. The Dashboard was read back rather than assumed: the webhook
  endpoint is live on **`2026-07-29.dahlia`** with all 13 events, and the portal carries
  `shortening_interval` **only**, with no retention offer. All four functions are
  **deployed** — `verify_jwt` true/true/**false**/true, the webhook 400s on a missing or
  forged signature and 405s on GET, both authed functions 401 without a JWT, and
  `desktop-rewrite` v6's source was read back off the platform rather than assumed.
  §6's lifecycle and §4.2's month-end arithmetic were then exercised **against the live
  project on throwaway ids** (rows deleted afterwards): a retry does not double-reserve,
  release returns quota but leaves the day brake ticked, and an anchor on 31 January
  gives Feb 28 → **Mar 31** → Apr 30 with no drift. **Still not proven: a real payment.**
  Tax is deliberately off end to end — **Core7 is a 免税事業者 with no T-number**, so
  there is no Stripe Tax registration and no `jp_trn` by decision rather than by
  omission; `desktop-checkout` sends `automatic_tax[enabled]=false` explicitly rather
  than relying on Stripe's default, because it is a legal position and a default is the
  wrong place to keep one. The plan card no longer says 「税込」 for the same reason.
- **2026-08-08 — onboarding actions anchored and practice insertion crash fixed.** Every
  post-authentication step now uses one shared 58 pt navigation shelf at the bottom of
  the 920 pt grid: Back stays at the left, optional skip actions stay secondary, and the
  single indigo forward action ends at the same lower-right coordinate on every page.
  The practice page no longer tries to visually reach the screen edge; a compact note
  points to the real bar outside the window, and its copy names the actual first
  reviewed button rather than hard-coding 敬語. After a successful tutorial Insert, the
  overlay now finishes dismissing its result panel before firing completion, then the
  onboarding window is restored as key. The reported `EXC_BREAKPOINT` was a real crash,
  not that focus handoff: practice is the one rewrite target owned by this process, and
  its AX setter entered AppKit's `NSTextView` implementation from the `AXTextIO` actor.
  AppKit asserted the main queue in `accessibilitySetSelectedRange` and trapped in
  `_dispatch_assert_queue_fail`. Same-process AX writes now hop to `MainActor`; normal
  cross-process AX writes remain off the main thread. **The running practice insert
  still needs an owner check.**
- **2026-08-08 — practice can no longer resize the onboarding window.** Setting
  `contentMinSize` and `contentMaxSize` was not a fixed-frame guarantee: the
  `NSHostingView` installed afterwards kept its default `.standardBounds`, which
  reflects SwiftUI's min, ideal and max measurements back into its `NSWindow` and
  overwrote those values. Focusing practice's `TextEditor` invalidated the measurement
  and made the window grow toward the screen-edge pill. Onboarding now sets the host's
  `sizingOptions` to `[]`, then applies 1080×700 after installing it. The real pill
  remains a separate screen-edge panel outside the unchanged onboarding frame.
- **2026-08-08 — onboarding rebuilt around use cases and the Willow window system.**
  The window is now fixed at 1080×700 for the full run, and every step sits on the same
  920 pt content grid inside a white 12 pt panel / 4 pt grey shell. The seven-step flow
  is アカウント → 用途 → ボタン → アクセス → バー → 練習 → 完了: Google is the
  primary sign-in, five practical four-button packs replace generic output gimmicks,
  and a mandatory review page supports editing, adding, deleting and reordering before
  anything is written to `user_prompts`. The welcome art is a silent Higgsfield
  Seedance 2.0 mascot loop with no generated text or UI; its white field blends into the
  panel, so the animation has no card, backdrop or decorative pills. `xcodebuild`
  succeeds and all 82 tests pass. **The owner is doing the running visual check.**
- **2026-08-08 — button ordering rewritten after two failed drag interactions.** The
  manual `DragGesture` shook because it moved the row while reordering its list; native
  `.draggable` then produced a detached, opaque preview narrower than the real row and
  made the destination unclear. `ButtonsView` now has a compact vertical pair of up/down
  controls on the left: one click, one adjacent move, no preview and no drop target. The first row is
  always `main`, so moving another button above it replaces it; all rows, including
  builtins, expose delete. `UserPromptRemoteStore.update` persists `slot`, and deleting
  the main normalizes and promotes the next row. Four pure ordering tests cover the
  arrow semantics. `xcodebuild` succeeds and all 79 tests pass. Existing iOS builds may
  re-seed a deleted builtin; permanent cross-client deletion needs the iOS tombstone
  noted in §14.
- `swift build` + `xcodebuild` succeed; 64 unit tests pass, no new warnings.
- **2026-08-08 — one candidate instead of three (§6, §8).** The desktop was sending
  the shared model's default `candidateCount: 3` and showing only the first, so two
  rewrites per press were generated, metered and thrown away. `OverlayController`
  now passes 1 and `candidateInstruction` gained a `count === 1` branch. The result
  panel briefly hid the pager below 2 candidates; that was reverted the same day —
  §8 has why. The footer's hairline went with it, replaced by the body's eased fade.
  `xcodebuild` succeeds with
  no new warnings, 64 tests pass (one new: `testSendsExplicitCandidateCount`), and
  `deno check` + `deno lint` are clean. **`desktop-rewrite` deployed, v2 ACTIVE,
  `verify_jwt` still true** — the deployed source was read back and carries the
  `count === 1` branch. `keyboard-rewrite` was not touched and stays v42.
  **Not verified: a rewrite through the running bar.** The change is confirmed in
  the deployed source and in the client's encoding, not by watching one candidate
  come back on screen.
- **Same day, fourth pass — reply mode (§16).** Copy a message, hover the bar, type how
  you want to answer. `supabase/` was **not touched**: `desktop-rewrite` already had the
  reply branch and `RewriteRequest.replyTo` was already in the model, so this is a
  client-only feature. New: `ReplySource` (pure, tested), `ClipboardWatcher`, two
  `OverlayState` cases, `allowEmpty` on the AX capture, a 返信モード switch.
  `xcodegen generate` was re-run for the two new files. **The running bar has not been
  watched** — see §16's "Not verified", which is specific about what that leaves open.
- `user_prompts` carries all four owner-scoped RLS policies
  (`select/insert/update/delete own`) on the live project, so §14's button editor
  needed **no migration**. Its column constraints were read from the same place:
  `user_id` is `NOT NULL` with no default, `builtin_key` is CHECK-limited to the
  four seeded keys, and there is no unique constraint on `(user_id, slot)`.
- The main window builds and launches without crashing. **Screen capture does work
  from this environment** (`screencapture -x` returns a real frame; an earlier note
  here claimed otherwise) and the *pre-restyle* window was captured that way. The
  restyled window has been built and launched but its appearance is being reviewed by
  the owner, not by an agent.
- **2026-08-07, the restyle.** `design.md` was replaced with a Willow style reference
  measured off `reference/`; §8 and §14 were rewritten to match; `App/Design/` and
  `App/Main/` were rebuilt against it. `Tokens.Settings` is now `Tokens.Window`,
  `PillButton` → `ActionButton`, `PageHeader` → `PageTitle`, and
  `GradientMark`/`GradientAvatar`/`BrandSphere`/`ProgressRing` are gone. Nothing under
  `App/Overlay/`, `Sources/` or `supabase/` was touched. `xcodebuild` succeeds and the
  47 tests still pass.
- **Same day, second pass** (from a look at the running window): the titlebar
  safe-area inset removed (§14), inputs changed from bordered boxes to `#f7f7f8` fills,
  and **SF Symbols replaced by Reicon Outline** in an asset catalog — 19 icons, MIT.
  `Icons.xcassets` is a new file, so `xcodegen generate` was re-run; `assetutil` on the
  built `Assets.car` confirms all 19 present with vector representations.
- **Same day, third pass — the product mark.** `wand.and.sparkles` is gone from the
  sidebar, the onboarding, the menu-bar item and the overlay bar; the keycap artwork in
  `public/` replaces it in the two cuts §8 describes, and the landing page's nav, footer,
  favicon, touch icon and mocked overlay bar take the same art. `AppIcon` now exists.
  `xcodebuild` succeeds with no new warnings, `swift test` passes (50 tests — the count
  above is stale), `assetutil` shows `icon-mark` template / `icon-mark-filled` not, and
  `AppIcon.icns` is built into the bundle. `npm run build` in `landing/` succeeds.
  **Not verified: the running app.** A stale instance was already running and this
  sandbox cannot signal it, so the new marks have been confirmed in the catalog and in
  offline renders at 16/20/26/32 px, not on screen. Quit it from the menu-bar 終了 and
  relaunch to look.
- **Same day, fourth pass — a UI/UX round, and it was measured rather than eyeballed.**
  Six fixes: the sidebar's icons were 1.7–2.2 pt below their labels (§14's optical-centre
  item), `icon-buttons` was Reicon's Category tile grid and is now RowVertical, the
  メイン badge and the history label became one `Badge`, the signed-out account page was
  rebuilt as a row group, the overlay had **no working cursors at all** (§14 item 1 —
  cursor rects are key-window-only and the pill can never be key), and the generating
  capsule's colour was re-derived from `generating.png`, which also turned up a border
  that disappeared twice per rotation (§8 deviations 4–6). `xcodebuild` succeeds.
  Everything visual here was checked by compiling `App/Design/` into a throwaway
  `ImageRenderer` harness and measuring ink bounding boxes in the output, because the
  running window cannot be screenshotted from this sandbox while a stale instance holds
  the bundle id. **Not verified on screen**: the cursors, the capsule's animation, and
  the error toast's new lifetime.
- **Same day, sixth pass.** The generating capsule lost its window shadow (§8 deviation 0
  — AppKit was building the shadow silhouette from the *glow's* alpha envelope and drawing
  a black ring standing off the capsule by the glow padding), and the error toast turned
  out never to have been dismissed early at all: it was resizing itself 653 pt below the
  display (§4 Errors). Both were pinned by rendering or sampling the thing in isolation
  rather than by reading the code — the toast's frame was sampled every 500 ms by a
  harness that builds the real `ErrorPanel`, and the fixed toast was then confirmed with
  `screencapture` of the live region.
- **Same day, fifth pass.** The capsule's ring went to 1 pt with a white-cored bloom and
  asymmetric glow padding (§8 deviation 5, all of it measured perpendicular to the ring
  in `generating.png`), the label became 生成中, and `CursorArea` was rewritten again —
  the `.cursorUpdate` tracking area from the fourth pass is as key-window-only as the
  `addCursorRect` it replaced, so it changed nothing. **The cursor work is the one thing
  in this file that cannot be verified without a hand on the mouse**: no synthetic
  pointer motion reaches `NSTrackingArea` at all (§14 item 1 has the three methods that
  were tried and the zero callbacks each produced). Hover the bar and check before
  believing it.
- **2026-08-08 — animated mascot.** Higgsfield's catalog exposed AutoSprite but
  its submission endpoint rejected the job type, so the approved fallback used
  Seedance 2.0 with `public/bgremoved.png` as both first and last frame. The shipped
  generations are idle `610859ac-f8be-493c-8a6a-8bdf63ee042a`, engaged
  `ae88e59b-34fd-4e06-9bf2-ebe671286088`, and thinking
  `a30adc86-8f26-4aad-b67a-b3be79f9bee7`. Each became a transparent 4×4 atlas: 16
  frames, 4 fps, 128 px per frame. `BrandGlyph` runs idle at rest, engaged in hover /
  reply / input states, and `GeneratingCapsule` runs thinking. The first engaged take
  `d1c4b64a-e104-49ca-8898-7bc7086a4d6a` invented a cast shadow and was rejected.
  The first running check exposed that `NSImageView` advertised each 128 px crop as a
  128 pt intrinsic view, so SwiftUI clipped it into the 16 pt slot instead of scaling
  it. The renderer is now a non-intrinsic `NSView` that draws into its actual bounds,
  not a video decoder. Both atlases were inspected at 16 pt on `#141312`; `assetutil`
  sees both names, `xcodebuild` succeeds and 79 tests pass. **The bounds-drawing fix has
  not yet been rechecked in the running overlay.**
- `deno check` + `deno lint` clean on `desktop-rewrite`.
- Migration applied to `eercsucvxnszqletxued`: 3 `desktop` tables, RLS on, zero
  policies; 5 `public.desktop_*` entry points, all confirmed **not** callable by
  `anon` or `authenticated`. Helpers smoke-tested end to end against a throwaway
  id (accumulation, the cross-user annotation guard, and GC), rows cleaned up.
- `desktop-rewrite` deployed, v1 ACTIVE, `verify_jwt = true`. Gateway 401s on
  missing and malformed JWTs; OPTIONS 200 proves the isolate boots.
- `keyboard-rewrite` still v42 with its pre-existing timestamp. `ai_rewrite_events`
  and `user_prompts` untouched.
- First run happened. `debug.png` shows a real candidate in the result panel, so
  capture → JWT → `desktop-rewrite` → response worked end to end at least once.

Measured, not assumed — with the Dock hidden under a full-screen space on the
1920×1080 display: `NSScreen.visibleFrame.minY = 78` while the Dock's AX element
reported its top edge at the screen's bottom. `OverlayPlacement.anchorY` puts the
bar at y = 6 where the old code put it at y = 84. §4 has the detail; it is the
one thing in this file that should not be re-derived from first principles.

Not verified — the overlay fixes are compiled and their inputs measured, but
**the running bar has not been watched crossing into and out of a full-screen
space.** The §5 **write** path is likewise unobserved — `debug.png` is a result
panel, not an insertion — as are the clipboard fallback and the
`AXManualAccessibility` branch for Electron targets.

Known gaps, all deliberate:

- **Analytics is live and the pipe is proven.** Project
  `KeigoButton Desktop (macOS)` is **549465** in org `Keigo`, its token and host
  are set on the repo's `production` environment (so `release-macos.yml`'s
  `test -n` preflight passes — it did not before), and the 21-tile
  `Desktop (macOS) Overview` dashboard is built and pinned. `docs/analytics.md`
  is the authority. The first real events arrived **2026-08-09 21:21 JST**: 135 of
  them from 2 people across 0.1.0/0.1.1/0.1.2, every one carrying `surface: macos`
  **except `Application Installed`**, which is captured inside `PostHogSDK.setup()`
  one line before `registerSurface()` can run. **Still never fired:
  `desktop_onboarding_completed`, `desktop_source_selected`, `desktop_prompt_*` and
  `desktop_checkout_started`** — both testers had already finished first run, so
  four tiles have no data and no proof either way. 465060 receiving nothing new has
  not been re-checked since the token went live.
- Five analytics gaps, each small and each bounding a dashboard tile:
  `Application Installed` carries no surface stamp (so tiles 1, 2 and 5 cannot use
  layer 3's filter), no `desktop_checkout_completed` (the revenue funnel ends at
  intent), **no `is_tutorial` on the rewrite events** — onboarding practice sends
  both and its three lessons complete only on a successful Insert, so every new
  user donates three guaranteed acceptances to the acceptance-rate tile — `io_path`
  exists only on the two rewrite events, and a DMG download is not an event at all:
  `Application Installed` is a first launch. `docs/analytics.md` §3.
- Sparkle and the distribution credentials are wired, and the `v0.1.0` GitHub release
  workflow passed end to end. What remains unproven is the user-side install and an
  installed old-build → new-build Sparkle update. The local Developer ID identity,
  Apple notarization API authentication, permanent Sparkle key, GitHub environments,
  encrypted secrets, Actions permissions, Pages source, public DMG signature/ticket and
  live signed appcast were all verified on 2026-08-09. See §9 and `docs/releasing.md`.
- Inter and Geist Mono are referenced by `DesignTokens` but not yet bundled, so
  type currently falls back to the system font.
- `desktop_delete_old_usage_buckets` is not scheduled. Add it to the pg_cron
  retention jobs beside the other GC functions.

Everything about the iOS app, the `prompt/` Electron app, the Supabase project,
and Willow's shipped binary *has* been verified — sources are cited inline so a
future reader can tell the two apart.

---

## 1. What this is

A macOS menu-bar-less companion to the iOS keyboard (`../Japanese`, internal name
`KeigoButton`, user-facing `AIキーボード`). Same product, same account, different
surface.

The whole app is one interaction: a small pill sits at the bottom of the screen
above the Dock. Hovering it expands a row of the user's own rewrite buttons —
the same `UserPrompt` buttons they configured on their phone — plus a custom
button that turns the row into a free-text input bar. Pressing a button reads
the text the user is currently editing in whatever app they're in, rewrites it,
and writes the result back in place.

There is **no keyboard, no IME, no kana-kanji conversion** in this app. macOS
already has a Japanese IME. `AzooKeyKanaKanjiConverter`, Zenzai, KeyboardKit and
everything in `JapaneseKeyboardCore` / `JapaneseKeyboardUI` are irrelevant here
and must not be pulled in.

### Reference: what we are copying and from where

The interaction model is Willow Voice's. Their Mac binary was inspected directly
(`/Applications/Willow Voice.app`, v2.3.10) — findings that shaped this design:

| Willow does | Evidence | We do |
|---|---|---|
| Native Swift/SwiftUI + AppKit | links `SwiftUI.framework` + `AppKit.framework`, built with Xcode 26.6 / macOS 26.5 SDK | same |
| Reads *and writes* text via Accessibility | `AXUIElementCopyAttributeValue` **and** `AXUIElementSetAttributeValue` in the symbol table | same (§5) |
| Guards against hung apps | `AXUIElementSetMessagingTimeout` | same — non-negotiable, see §5 |
| Synthesizes keystrokes as fallback | `CGEventCreateKeyboardEvent` / `CGEventPost` / `CGEventTapCreate` | fallback only (§5) |
| Ships outside the Mac App Store | no `com.apple.security.app-sandbox` entitlement; Sparkle 2.9.2 with a GitHub Pages appcast | same, and we have no choice (§2) |
| Movable bottom bar taught in onboarding | `Resources/onboarding_move_bar.mp4` | same (§4) |
| Signs in through `ASWebAuthenticationSession`, so sign-in gets its own browser window and the system consent alert rather than a tab | links `AuthenticationServices.framework`; `_OBJC_CLASS_$_ASWebAuthenticationSession` is in its symbol table | same (§6) — the new window and the one alert are the price of the browser handing the callback straight back to the app |
| macOS 14.0 minimum | `LSMinimumSystemVersion = 14.0` | same |
| One account across Mac/Windows/iOS, settings sync, one subscription | [help center](https://help.willowvoice.com/en/articles/13208038-why-isn-t-my-account-or-subscription-syncing-between-devices) | same account, separate data (§6) |

Not copied: their `F1 + F2` chip in `result.png` is a push-to-talk dictation
binding, irrelevant to us. Their `whisper.framework` / STT stack is irrelevant.
Their `ScreenCaptureKit` + `Vision` screen-OCR path is out of scope for v1 (§10).

---

## 2. Hard constraints — read before changing anything

- **App Sandbox is OFF, and the app can never ship on the Mac App Store.**
  `AXUIElementCreateSystemWide()` reading another process's focused element is
  impossible inside the sandbox. Developer ID + notarization + Sparkle is the
  only distribution path. Willow made the same call.
- **No provider API keys in the bundle.** Every AI call goes through a Supabase
  Edge Function authenticated with the user's JWT. `prompt/` ships
  `GEMINI_API_KEY` in a `.env` copied to `process.resourcesPath` — anyone who
  downloads that app can read the key. Do not repeat it here.
- **The pill must never become key window.** If hovering the pill steals focus,
  the user's text field loses its `AXFocused` state and we lose the target we
  are about to write into. Only the input bar and the result panel may become
  key, and only after the target has already been captured. §4 is the full
  ordering; getting it wrong is the single most likely way to break this app.
- **Never write to the iOS app's tables.** `ai_rewrite_events`,
  `ai_rewrite_usage_buckets` and the `keyboard-rewrite` function belong to the
  shipped keyboard. Desktop gets its own function and its own schema (§6). This
  mirrors the precedent already set by `web-rewrite`, whose migration says it
  plainly: *"Nothing here references or alters existing tables, so it cannot
  affect app users or the rest of the schema."*
  (`../Japanese/supabase/migrations/20260728120000_web_rewrite_rate_limit.sql`)
- **`user_prompts` is shared and read-write from both surfaces.** It is the one
  deliberate exception to the rule above — it is what makes a user's buttons
  follow them from phone to laptop. Treat its schema as a contract owned by the
  iOS repo.
- **Analytics never mix.** Desktop reports to its own PostHog project, not the
  existing `Default project` (id 465060, org `Keigo`). See §7.
- **The overlay is dark; the main window is white.** The window is `design.md`'s
  published system; the overlay is its own ramp. See §8.

---

## 3. Repository layout

```
laptop/
├── AGENTS.md                      ← you are here
├── design.md                      ← Willow style reference (visual authority)
├── project.yml                    ← XcodeGen, mirrors ../Japanese's setup
├── Package.swift                  ← local SPM package for the testable core
├── Sources/
│   ├── DesktopRewriteKit/         ← pure Swift, no AppKit: models + service
│   │   ├── Models/                ← UserPrompt, RewriteModels
│   │   ├── Service/               ← AuthService, DesktopRewriteService, KeychainSessionStore
│   │   ├── Prompts/               ← UserPromptRemoteStore (shared user_prompts, read+write)
│   │   ├── Profile/               ← ProfileRemoteStore (shared profiles, read+write)
│   │   ├── History/               ← RewriteHistoryStore + RewriteStats (§14, local only)
│   │   └── SupabaseConfig.swift
│   └── TextIO/                    ← AX + clipboard capture/replace
│       ├── AXTextIO.swift         ← the primary path
│       ├── ClipboardTextIO.swift  ← the fallback, ported from prompt/
│       ├── TextIOCoordinator.swift← picks a path, remembers it for the write
│       ├── Pasteboard.swift       ← PasteboardBridge / AppActivator protocols
│       └── BundleIdentity.swift   ← pid → bundle id without AppKit
├── App/
│   ├── AppDelegate.swift          ← accessory policy, menu-bar item, URL scheme
│   ├── Analytics.swift            ← §7 event shape (transport not yet wired)
│   ├── Overlay/                   ← PillPanel, PillRootView, GeneratingPanel, ResultPanel,
│   │                                OverlayController (the §4 state machine), OverlayPlacement
│   ├── Main/                      ← the white window (§14): MainWindowController,
│   │                                MainModel, MainWindowView, Home/Buttons/Account,
│   │                                PreferencesSheet
│   ├── Design/                    ← DesignTokens.swift, Components.swift,
│   │                                BrandVisuals.swift, Icon.swift (Reicon names)
│   └── Resources/                 ← Info.plist, entitlements,
│                                    Icons.xcassets (Reicon Outline, MIT — README inside)
├── Tests/
│   ├── DesktopRewriteKitTests/    ← the iOS contract (§3) — a failure here is a two-repo change
│   └── TextIOTests/               ← clipboard ordering, UTF-16 context slicing
└── supabase/
    ├── config.toml                ← verify_jwt for desktop-rewrite
    ├── migrations/                ← desktop schema (see §12 on where this should live)
    └── functions/desktop-rewrite/
```

`Sources/` is AppKit-free so capture/replace and the service layer are testable
without a window server. `TextIO` imports `ApplicationServices` (where
`AXUIElement` lives) and `CoreGraphics` (for `CGEvent`), but not AppKit — the two
things it genuinely needs from AppKit, the pasteboard and app activation, are
protocols implemented in `App/Overlay/AppKitBridges.swift`. That boundary is what
makes the clipboard fallback's ordering unit-testable.

`Sources/` stays free of AppKit so the capture/replace logic and the service
layer are unit-testable without a window server. `TextIO` may import
`ApplicationServices` (that's where `AXUIElement` lives) but not AppKit.

### Shared code with the iOS repo

`../Japanese/Package.swift` already declares `.macOS(.v14)`, and both
`JapaneseKeyboardAI` and `KeyboardPreferences` import **only Foundation** — zero
UIKit. So they *could* be linked directly. We are not doing that, because this
is a standalone repo by decision.

Instead, **copy** these four types and keep them contract-compatible:

| Type | Source | Why it must not drift |
|---|---|---|
| `UserPrompt`, `PromptOrigin` | `Sources/KeyboardPreferences/UserPrompts.swift` | decodes rows from the shared `user_prompts` table |
| `RewriteRequest` | `Sources/JapaneseKeyboardAI/Models/RewriteModels.swift` | the desktop function should accept a superset, not a different shape |
| `RewriteCandidate`, `RewriteResult` | same file | `{ candidates, language, eventId }` |
| `CaptureMode` | same file | `.selection` / `.wholeInput` map cleanly onto AX (§5) |

Any change to these on either side is a two-repo change. Note it in the PR.

---

## 4. Windows and the state machine

Five states, three windows. **Which window is key at each moment is the load-
bearing detail.**

```
        hover                press button              done
 PILL ─────────→ HOVER ROW ─────────────→ GENERATING ────────→ RESULT
  ▲               │  │                        │                  │
  │  exit + grace │  │ press ✎                │ cancel           │ insert / esc
  └───────────────┘  ↓                        ↓                  ↓
                  INPUT BAR ──── submit ──────┘            (write + dismiss)
```

| State | Window | Key? | Notes |
|---|---|---|---|
| Pill | `PillPanel` | **never** | ~28 pt tall, fully pilled, always visible |
| Hover row | `PillPanel` (resized) | **never** | user's enabled buttons + custom button |
| Input bar | `PillPanel` (resized) | **yes** | needs typing; capture already done |
| Generating | `GeneratingPanel` | never | separate window, per `generating.png` |
| Result | `ResultPanel` | **yes** | Enter = Insert, Esc = dismiss |

**The generating capsule and the result panel replace the bar, they do not stack
on top of it.** Both anchor their *bottom* to `PillPanel.frame.minY` and the pill
window is ordered out for the duration — `generating.png` and `result.png` both
show one thing on the bottom edge, and a pill sitting under a result panel is a
second control with nothing left to do. The hand-off is ordered so the edge is
never momentarily bare: the bar returns before they leave and leaves after they
arrive. Its frame stays valid while hidden, which is what they anchor to.

### PillPanel

- `NSPanel`, `styleMask: [.borderless, .nonactivatingPanel]`,
  `isFloatingPanel = true`, `hidesOnDeactivate = false`,
  `becomesKeyOnlyIfNeeded = true`, `isMovableByWindowBackground = true`.
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
  so it survives Spaces switches and full-screen apps.
- `level = .statusBar`. High enough to sit over normal windows, below menu-bar
  dropdowns.
- **Position**: bottom-centered, `bottomInset` (6 pt) above
  `OverlayPlacement.workArea(on:).minY`. Not `visibleFrame` — read the next two
  bullets before touching this, they are the whole reason the file exists.
- **`NSScreen.visibleFrame` lies about the Dock, and this is the load-bearing
  fact of §4's placement.** Measured on a 1920×1080 display while a full-screen
  space had the Dock hidden: the Dock's own AX element reported its top edge at
  y = 1080 — the screen's bottom, i.e. gone — while `visibleFrame` still
  reported `minY = 78`. It reserves the Dock's strip whether or not the Dock is
  there. Anchoring to it left the bar floating **84 pt** above the bottom of
  every full-screen app, which is the gap the first round of fixes failed to
  close: re-deriving the Y more often just recomputed the same wrong number.
- **`DockProbe` is the oracle; `visibleFrame` is only the measurement.**
  `DockProbe` asks the Dock process for its own AX geometry and answers one
  question — is a bottom-oriented Dock actually on this screen. If yes,
  `workArea.minY` is `visibleFrame.minY` (which correctly includes the Dock's
  outer margin). If no, it runs to `screen.frame.minY` and the bar sits at the
  very bottom of the display. Willow does the equivalent —
  `NewDockManager`, `lastDockPosition` and `lastDockSize` are in its binary.
- **The Y is re-derived, never carried over.** `OverlayPlacement.anchorY` is the
  only source of the bottom edge and every reposition goes through it.
  Preserving the previous frame's `minY` across a resize is the second half of
  the same bug: the Y computed at launch was the Y forever.
- **The 0.5 s poll is not belt-and-braces, it is the only mechanism that works
  for the Dock.** `didChangeScreenParametersNotification` covers the Dock being
  resized or its auto-hide setting changed; `NSWorkspace.activeSpaceDidChange`
  covers entering and leaving full screen. Neither fires when the Dock slides
  away under a full-screen space, and polling `visibleFrame` cannot see it
  either because the value never moves. The Dock's AX geometry has nothing to
  subscribe to, so it is sampled. Willow ships the same loop
  (`barPositionTrackingTask`).
- **Which screen the bar re-anchors against**: the one containing the bar's own
  centre (`OverlayPlacement.screen(containing:)`), *not* the one under the mouse.
  The position poll compares that screen's work area, so using the cursor's
  screen meant that on a two-display setup merely moving the mouse across
  changed the answer, re-anchored, and clamped the bar onto the other display at
  an X carried over from the one it left. `activeScreen()` is now used only for
  the very first placement, when there is no bar frame to ask about yet.
- **Auxiliary panels clamp.** The generating capsule and the result card go
  through `OverlayPlacement.auxiliaryFrame`, which centres them on the bar and
  then clamps to the work area. They were unclamped, and the bar is draggable
  with a persisted position, so parking it near an edge left a 420 pt card
  hanging off the side. `clampToWorkArea` resolves the screen from the frame
  rather than `NSWindow.screen`, which is nil once a window is fully off-screen —
  exactly when the clamp matters.
- **Which screen (first launch only)**: the one under the mouse cursor
  (`NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }`),
  falling back to `.main`. Same rule `prompt/src/core/window-manager.js`
  `positionOverlay()` uses.
- **Draggable, position remembered.** Store the offset from
  `visibleFrame.origin` (not an absolute point) in `UserDefaults`, so an
  external display being unplugged doesn't strand the pill off-screen. Willow
  ships an onboarding video for exactly this affordance.

### Hover

- `NSTrackingArea` (`.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect`)
  on the panel's content view, with a hit area a few points larger than the
  visible pill.
- **Collapse needs a grace delay (~300 ms).** Without it, a diagonal mouse path
  toward a button on the far end of the expanded row collapses the row
  mid-travel. Cancel the pending collapse on re-entry.
- The Dock sits directly beneath the pill. Any hover hit area that overlaps the
  Dock will fight Dock magnification — keep the tracking rect strictly inside
  `visibleFrame`.
- Expansion animates the **window frame** (`NSAnimationContext`), not just the
  view: a borderless window clips its content.
### Input bar

- **Fixed width (360 pt) — the one state that does not follow its measurement.**
  A text field has no stable intrinsic width: it measures the placeholder while
  empty and the typed string after, so the window snapped narrower on the first
  keystroke and twitched on every one after it. And under
  `fixedSize(horizontal:)` its ideal width is unbounded, so a long prompt grew
  the window off the side of the screen rather than wrapping.
- **The placeholder never wraps and never comes from AppKit.** `TextField` has an empty
  native title; `InputBar` draws an explicit one-line `textSecondary` layer instead.
  This is both a colour invariant — the dark overlay does not inherit a black placeholder
  from the system appearance — and a geometry invariant: the shorter optional-reply hint
  cannot make an untouched composer taller than its 34 pt floor. The reply composer has
  no second mode capsule beside the mascot; the placeholder already names the mode, and
  the duplicate capsule compressed into an unlabeled dark shape. (`ReplyBar` keeps its
  badge in the armed state, where there is no field or placeholder.)
- **Only typed guidance wraps, up to `inputBarMaxLines` (3), and the window height
  follows.** §4's 28/34 pt are a floor, not a fixed height — `currentSize()` takes the
  larger of the measurement and the token.
- **Cancellable, three ways**: Escape, clicking anywhere outside (the panel
  resigning key), or submitting. An input bar you can only leave by generating
  is a trap. Escape is wired through both `onExitCommand` and
  `onKeyPress(.escape)` because a focused `TextField` swallows it often enough
  that neither alone is dependable; `cancelCustomInput` is idempotent.
  Cancelling returns to the hover row when the cursor is still over the bar —
  collapsing under a stationary cursor leaves the row unreachable until the
  pointer leaves and comes back.
- The resign-key cancel is checked one runloop turn late. An accessory app
  taking key on a non-activating panel can bounce once while focus settles, and
  cancelling on that bounce would close the bar the instant it opened.

- **SwiftUI measures the width; the window follows.** `NSHostingView` installs
  constraints from the content's intrinsic size and overrides any frame set behind
  its back, so a hand-computed width is both dead code and a visible jump.
  `PillRootView` reports its measured width up through a preference and
  `OverlayController.contentWidthChanged` is the only thing that resizes.
  Height stays a design decision from `Tokens.Geometry` (28 collapsed / 34 expanded).
  Corollary: the collapsed pill's horizontal padding is load-bearing — without it
  the window measures 16 pt and the pill is a naked icon.

### Hover row layout

**`hovered.png` is Willow's own bar, not ours.** Its `27.3k words` readout and
three icons are dictation affordances; no reference image shows our button row.
The structure below keeps that image's *geometry* and replaces its contents.

```
┌──────────────────────────────────────────────────┐
│  ◈ │  敬語   要約   英訳   丁寧に  │  ✎           │   34 pt tall
└──────────────────────────────────────────────────┘
   ↑     ↑                              ↑
  mark  the user's enabled prompts    custom input
```

- **Left**: the same mark shown on the collapsed pill, 16 pt, then a 1 pt
  `#2e2b28` hairline. No word count, no status text — we have nothing to count.
- **Center**: one pill per enabled `UserPrompt`, in `sort_order`. `UserPrompt.title`
  as a text label, Inter 500 / 12 pt, `#fdfcfc`. 10 pt horizontal padding,
  9999 pt radius, transparent until hover; hover fill `#2e2b28`.
  Labels, not icons — a user's own buttons have arbitrary titles and no icon
  vocabulary can carry them.
- **Right**: hairline, then the custom button `✎`, same metrics as a prompt pill.
- Row width is intrinsic. **No overflow handling.** Measured against live data
  (3,270 users in `user_prompts`): enabled buttons average 3.99, median 4, p99 5,
  max 7. Eight pills including `✎` fit a single row on any supported display.
- Collapsed pill 28 pt → expanded row 34 pt. Animate the window frame (above).
- **The bar is a capsule, at `pillRadius`.** `normal.png` and `hovered.png` show
  Willow's bar as a flat-bottomed tab flush with the work area. That is *their*
  shape; those images are cited here for placement behaviour, not for styling.
  Do not re-derive our shape from them — it has been tried and reverted once.

### Errors

- **`ErrorPanel` is a window, not an overlay.** Errors were an `.overlay` on
  `PillRootView` offset 34 pt above the pill — outside a window sized exactly to
  the pill, so it was clipped and never drew once. Combined with `present(error)`
  only resetting state in the `.generating` branch, pressing a button in an app
  with no editable field did **nothing at all**: no result, no message, no
  change. That is the most likely thing to happen on a first run.
- Every failure path now goes through `present(message:)`, whatever the state.
  The toast sits above whatever currently owns the bottom edge — the bar, the
  capsule, or a result card — auto-dismisses after `errorToastDuration`, and
  dismisses on click or when a rewrite actually starts. Never key: the failure usually
  left the user's own field focused and taking that to show an apology makes it
  worse.
- **The toast was never being dismissed early. It was off the bottom of the screen.**
  This is the actual reason nobody could read it, and it hid behind two plausible
  theories before an isolation harness built the real `ErrorPanel` and sampled its frame:
  created at `(780, 42, 360, 62)` — correct, 8 pt above the bar — and one layout pass
  later `(780, -653, 360, 721)`. `visible`, `alpha 1`, unoccluded, on a screen, and
  653 pt below the display the whole time. What you catch as "a flash" is the frame
  before the resize; when the resize wins the race there is nothing to see at all.
  **`ErrorToast` ended with `.frame(maxHeight: .infinity, alignment: .bottom)`**, copied
  from `ResultView`. Inside an `NSHostingView` that is unbounded in the one direction
  that matters: the card's own `GeometryReader` reported the stretched height, the
  hosting view installed constraints for it, and the window followed. `ResultView`
  survives the same construction only because `ResultPanel.applyContentHeight` clamps to
  `resultPanelMaxHeight` and `ErrorPanel` clamped nothing — **which means the result
  panel is very likely reporting a stretched height too and being silently pinned at
  440; worth checking the next time one is on screen.** The toast now sizes to a fixed
  width and its own content, clamps to `errorToastMin/MaxHeight`, and derives its origin
  from `desiredBottom` rather than reading `frame` back, because `NSHostingView`
  re-satisfies its constraints afterwards and holds the window's **top** — growing by
  6 pt moved the bottom 6 pt down and ate the gap above the bar.
- **It also used to dismiss on *any* transition.**
  A capture failure raises the toast from `.hoverRow`, and the very next transition
  is the row collapsing 300 ms after the pointer leaves the bar — i.e. the instant the
  user's eye moves up to the message. So the failure most likely to happen on a first
  run flashed an explanation and took it away again, and `errorToastDuration` was
  never what anyone was reading against. `transition` now clears the toast only on the
  way into `.generating` or `.result`; the duration is 8 s, the toast is 360 pt wide at
  13 pt, and it says it closes on click.
- **Three empty rows, and only two of them are messages.** A failed `refreshPrompts`
  that leaves nothing to show sets `promptsFailed`, and the row says so instead of
  telling someone to go and make buttons they already have. Hovering retries —
  `refreshPrompts` otherwise runs once at launch, so being offline at that moment left
  the row empty for the session.

  **Signed out is the third, and it is a button.** `refreshPrompts` catches
  `RewriteError.notSignedIn` separately, drops the stale buttons (they belong to an
  account that is no longer attached, so pressing one could only fail) and sets
  `signedOut`. That row is 「サインインするとボタンが使えます」 plus a filled サインイン
  pill, and it drops ✎ as well — every other control on the bar is inert until there is
  an account, so the row holds the one action that changes that. Pressing it collapses
  the row and calls `onSignInRequired`, the same callback a rewrite raises when it
  discovers a missing session, so both routes land on アカウント in sign-in mode. It
  used to report 「ボタンを読み込めませんでした」, which is a network apology for a
  problem no retry can fix.

  **Which needs `notSignedIn` to survive the store.** `UserPromptRemoteStore` used to
  turn every failure into `RewriteError.backend`, so the row could not tell the two
  apart. `authorize` now wraps a missing session the way `DesktopRewriteService.post`
  already did, and 401/403 is mapped as well — `ensureFreshAccessToken` deliberately
  falls back to the stored token when a refresh fails rather than signing the user out,
  so a genuinely expired session reaches PostgREST and comes back rejected rather than
  failing locally.

### Capture ordering — the rule that makes this work

On button press, in this order, synchronously before any UI change:

1. Read the AX target (§5) while the user's app is still frontmost and the pill
   has never been key.
2. Snapshot `NSWorkspace.shared.frontmostApplication` (for the fallback path).
3. *Then* show the generating capsule / take key focus.

For the custom-input path the capture happens when **✎ is pressed**, not when
the user submits the text — by submit time the input bar is key and
`AXFocusedUIElement` points at our own field.

---

## 5. Text I/O — Accessibility first, clipboard fallback

Lives in `Sources/TextIO/`. Two implementations behind one protocol; the AX one
is tried first and the clipboard one is the documented fallback.

### Permission

`AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`. The app is
useless without it, so onboarding gates on it and re-checks on every activation
(the permission is revoked whenever the binary changes identity, which happens
on every dev rebuild — expect to re-grant constantly while developing).

### Read

```
AXUIElementCreateSystemWide()
  → kAXFocusedUIElementAttribute            (the focused control, cross-app)
  → kAXValueAttribute                       (whole field text)
  → kAXSelectedTextAttribute                (current selection)
  → kAXSelectedTextRangeAttribute           (CFRange, for in-place replacement)
```

Mode selection maps onto the existing `CaptureMode`:

- non-empty `kAXSelectedText` → `.selection`; send `selection: true` plus
  `selectionContextBefore/After` sliced from `kAXValue`.
- empty selection but readable `kAXValue` → `.wholeInput`; the whole field is
  the rewrite target. **This is the case the clipboard cannot serve**, and the
  reason AX is first — a hover pill whose buttons only work after you manually
  select text is a worse product.
- neither readable → clipboard fallback.

### Write — read strategy and write strategy are decided SEPARATELY

This is the part that was wrong in the first implementation, and it is why insertion
worked in Notes and nowhere else. `TextTarget` carries both `path` (how it was read)
and `writeStrategy` (how it goes back); **an AX read followed by a clipboard write is
the normal case in Gmail**, not a degradation.

Prefer `AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute, text)` — it
replaces the selected range in place, preserves the app's own undo stack, and does not
require the target app to be frontmost. For `.wholeInput`, select all via
`kAXSelectedTextRangeAttribute` first, then set selected text.

Four rules, each of which was a bug:

1. **Never gate *capture* on writability.** Gmail's compose box reads fine and reports
   `kAXSelectedText` unsettable. Gating capture on it threw the read away and left the
   clipboard, which cannot capture `.wholeInput` at all — ⌘C with nothing selected
   copies nothing. `isSettable` picks the write strategy, nothing else.
2. **Verify the AX write landed** by re-reading `kAXValue`. `SetAttributeValue`
   returns `.success` and does nothing in most web and Electron views. Unreadable
   after write counts as success: pasting again over a write that did land would
   duplicate the user's text, which is the worse failure.
3. **Escalate to a synthesized paste when AX fails**, guarded by the captured pid so
   ⌘V can only ever land in the app we read from. Refusing to escalate is what made
   browsers permanently broken.
4. **A clipboard write of `.wholeInput` must send ⌘A first.** ⌘V replaces the current
   *selection*; with nothing selected it inserts at the caret and the user gets their
   text twice. Pinned by `testWholeInputSelectsAllBeforePasting`.

Write order on insert mirrors `prompt/`'s `insert-text` handler, which is the only
write path that app ever used: **dismiss our panels first**, then clipboard → activate
the captured app → settle 200 ms → (⌘A) → ⌘V → restore clipboard. Our panels must go
first because ⌘V goes to the key window, and the result panel *is* key.

If the write fails anyway, the rewrite is left on the clipboard and the panel comes
back — never silently discarded.

### Mandatory hardening

- **`AXUIElementSetMessagingTimeout(element, 0.5)` on every element we touch.**
  AX calls are synchronous IPC into another process; a hung or beachballing app
  will otherwise block our main thread and freeze the pill. Willow sets this.
- **Electron/Chromium targets need `AXManualAccessibility`** set to `true` on the
  *application* element before their tree is populated. Without it, Slack, VS Code,
  Discord, Chrome and friends look like they have no focused element — verified live:
  both Chrome and Windsurf returned nil for `kAXFocusedUIElement`.

  **Prime it off the frontmost pid, BEFORE the first focused-element read.** The
  original code took the pid from the focused element, so it hit
  `guard let focused = … else { throw .noTarget }` and bailed before ever setting the
  flag — the workaround could never fire for the only case it exists for. The focused
  element may also live in a different process than the frontmost app (web content /
  helper), so prime that one too and re-read once. Cache per pid.

- **`scripts/axdiag.swift` answers "why doesn't app X work?"** It dumps role,
  readability, and settability for the focused element and optionally attempts the real
  write and verifies it landed. Reach for it before theorising — AX reports success
  while doing nothing, so nothing here is falsifiable by reading code.
- Never call AX on the main thread without the timeout above. Prefer a
  dedicated serial queue and hop back for UI.

### Clipboard fallback

Port `prompt/src/services/focus-service.js` almost verbatim — it is correct and
already handles the sharp edges:

1. save `NSPasteboard.general` contents, clear it
2. synthesize ⌘C (`CGEvent`, not AppleScript — no automation prompt, lower
   latency)
3. wait ~100 ms, read, restore the original clipboard
4. to write: put text on the pasteboard, `NSRunningApplication.activate()` the
   captured frontmost app, wait ~200 ms, synthesize ⌘V

Report which path was used as an event property (§7) — if the fallback rate is
high in some app, that's a bug report, not a mystery.

---

## 6. Backend

Shared Supabase project with the iOS app:
`https://eercsucvxnszqletxued.supabase.co`. Shared login, shared buttons, shared
billing. **Separate function, separate schema, separate analytics.**

**Two hosts, deliberately.** Auth alone is reached through the project's Supabase
custom domain `https://auth.keigobutton.com`; REST and Functions stay on
`<ref>.supabase.co`. The split exists because the auth host is the only one a user
ever reads — macOS composes the `ASWebAuthenticationSession` consent alert from the
host of the URL the app hands the session, so it used to quote
`eercsucvxnszqletxued.supabase.co` at people about to type a Google password.
`SupabaseConfig.authURL` is the only place that host lives, and the default
`<ref>.supabase.co/auth/v1` still works, which is what keeps iOS unchanged.

### Shared, read as-is

| Table | Use |
|---|---|
| `auth.users` | one identity across phone and laptop |
| `profiles` | display name, subscription state |
| `user_prompts` | the buttons — read and write (columns: `id, user_id, slot, builtin_key, origin, title, prompt, is_enabled, sort_order, created_at, updated_at`). **`id` is not its only unique key**: `user_prompts_user_builtin_unique (user_id, builtin_key) WHERE builtin_key IS NOT NULL` makes a builtin key an identity, and `handle_new_user()` seeds all four (`polite`, `natural`, `email`, `translateToEnglish`) at signup. Any write that mints a fresh id for an already-owned key is a 409 — see `UserPromptIdentity` |
| `user_ai_consent` | AI-improvement consent, honored by both surfaces |

### Desktop-only `desktop` schema — tables there, entry points in `public`

Applied. Tables live in `desktop`; every callable entry point is a
`SECURITY DEFINER` function in `public` prefixed `desktop_`.

**That split is not cosmetic.** PostgREST only serves schemas in the project's
"Exposed schemas" setting (public/graphql_public/storage by default). Reaching
`desktop` directly would mean changing the shared project's API surface — which the
iOS app also lives behind. Routing through `public` functions avoids that, and has
the better property anyway: **no desktop table is reachable over the API at all.**
It is also what the `web_rewrite_usage` / `public.bump_web_rewrite_usage` precedent
actually did.

| Object | Purpose |
|---|---|
| `desktop.rewrite_events` | mirrors `ai_rewrite_events` in spirit, never in storage. `redact.ts` applies identically; text is opt-in behind the shared `user_ai_consent` |
| `desktop.usage_buckets` | per-user day/hour/minute counters. Shape from `web_rewrite_usage` |
| `desktop.activations` | `(user_id, first_seen_at, last_seen_at, app_version)` — **how desktop counts stay honest.** `profiles` holds both platforms' users; desktop MAU comes from here and PostHog, never from counting `profiles` rows |
| `public.desktop_bump_usage` | atomic increment, returns running `(units, requests)` |
| `public.desktop_log_rewrite_event` | takes the event as one `jsonb` arg |
| `public.desktop_patch_rewrite_event` | feedback. Enforces the `user_id` predicate *inside* the function — the event id comes from the client |
| `public.desktop_record_activation` | upsert `last_seen_at` |
| `public.desktop_delete_old_usage_buckets` | GC on `updated_at`. **Not on `bucket_key`** — keys are prefixed (`day:2026-08-07`), so a string compare against a date literal is false for every row and nothing would ever be deleted |

All five are `REVOKE EXECUTE`d from `public`, `anon`, `authenticated`; only
`service_role` can call them. Verify with `has_function_privilege` after any change
to this migration.

### `desktop-rewrite` Edge Function

New function, same project. Accepts a **superset** of `RewriteRequest` so the
copied model stays compatible:

```
+ surface: "macos"
+ hostAppBundleId: string        // com.apple.mail — for prompt shaping + analytics
+ captureMode: "selection" | "wholeInput"
+ browserURL: string | null      // only when the host app is a browser
+ ioPath: "ax" | "clipboard"     // see below
```

`ioPath` is a fifth field, added during implementation. §7 makes it the earliest
signal that an app's AX tree changed, and **only the client knows which path it
took** — the server cannot infer it. Without it on the wire,
`desktop.rewrite_events.io_path` is permanently null and that signal is silently
lost. Pinned by a test in `Tests/DesktopRewriteKitTests/ContractTests.swift`.

`replyTo`, `refinement`, `stream`, `candidateCount`, `promptOrigin` and the
selection-context fields all keep their existing meanings. Response is
unchanged: `{ candidates, language, eventId }`.

**`candidateCount` is 1 on this surface, in both normal and reply mode.** The
phone shows a picker and needs alternatives to choose between; the desktop writes
back in place, so candidates 2 and 3 were generated, billed and discarded —
`reserveUsage(userId, request.candidateCount)` meters *units by candidate*, so
the count is a 3× multiplier on the `DESKTOP_DAILY_UNITS` budget (900), and
`max_completion_tokens` is `baseTokens * candidateCount` on top of that.

Two things about where that 1 lives:

- **It is set at the call site (`OverlayController`), not on `RewriteRequest`.**
  That type is a copied contract shared with the iOS repo (§3) and its default is
  3 on both sides; moving the desktop's default would be silent drift in a type
  whose whole job is not to drift. `ContractTests` therefore still asserts the
  model default is 3, and a second test asserts an explicit 1 survives encoding.
  That second test is the load-bearing one: `parseRequest` falls back to
  `DEFAULT_CANDIDATES` whenever the key is absent, so a dropped field does not
  fail — it silently restores the phone's count, and the symptom is a usage bill
  rather than a bug report.
- **`candidateInstruction` has a `count === 1` branch.** Without it, 1 fell
  through to the generic string and asked the model for "exactly 1 *distinct*
  candidate rewrite**s** that meaningfully differ in phrasing" — plural, and an
  instruction to differ from a set with nothing else in it.

This is a `desktop-rewrite` change only. Mobile is on `keyboard-rewrite` (v42),
a different function, and was not touched.

Auth is identical to the keyboard: `Authorization: Bearer <user JWT>` +
`apikey: <publishable key>`. The publishable key is safe to ship — it is
RLS-gated. Token refresh mirrors `CloudRewriteService.ensureFreshAccessToken()`
(refresh when within 30 s of expiry).

Session storage is the **macOS Keychain**, not an App Group — App Groups are the
iOS container↔extension mechanism and have no role here.

### Sign-in

`ASWebAuthenticationSession` against Supabase, returning through a custom URL
scheme. Willow registers `willow://` + `willowvoice://` and bounces through a
`/success-open-app` web page; the same pattern works for us.

### Feedback

`result.png`'s 👍/👎 map onto endpoints that already exist on the iOS side —
`submitSelection(eventId:selectedIndex:)` and
`submitAction(eventId:action:selectedIndex:latencyMs:)`. Implement the desktop
equivalents against `desktop.rewrite_events` from day one; the iOS side has had
this listed as an open production item for months precisely because it was
deferred.

---

## 7. Analytics

`docs/analytics.md` is the authority — the dashboard's 21 tiles, the three
isolation layers and the manual project-creation step live there. This is the
short version.

- **The desktop has its own PostHog project: 549465, `KeigoButton Desktop
  (macOS)`.** Do not report into `Default project` (465060) — MAU, retention and
  funnels are computed per project, and person merging across surfaces would
  silently deflate both platforms' counts. 465060 is the iOS keyboard's *and* the
  landing page's; `../Japanese/Config/Local.xcconfig` points at its token, and it
  already ingests `keyboard_enabled`, `$screen` and `app_store_click`. **Reading
  465060 for reference is fine and was done on 2026-08-10** — its
  `Product KPIs — code-aligned (v2)` dashboard is what the desktop's acquisition
  band is modelled on. Writing anything into it from here is not.
- PostHog Swift SDK, `distinct_id` = Supabase user id. **That is the same id iOS
  identifies with**, which is why a shared project could not be salvaged by
  filtering: the merge would be to the person store, not the event stream.
- **Every event carries `surface: macos` as a super property**, registered in
  `PostHogConfiguration.registerSurface()` — so the autocaptured `$exception` and
  `$identify` carry it too, not just the ones we call `capture` for. It is
  re-registered in `MainModel.signOut()`, because `PostHogSDK.shared.reset()`
  clears super properties along with the identity and every event after a
  sign-out would otherwise lose its surface until the next launch. **One event
  escapes it: `Application Installed`.** The SDK captures that inside
  `PostHogSDK.shared.setup(config)`, and `configure()` can only register on the
  line after — measured on the live project, 0 of 2 installs carry a surface.
  Three dashboard tiles therefore run unfiltered; see `docs/analytics.md` §3.
- **`desktop_signed_up` / `desktop_signed_in` (2026-08-10)** are captured in
  `MainModel` for an authentication the user just performed, never for the
  Keychain session `refresh()` restores. Google cannot tell the two apart from the
  session alone, so `completeOAuth` treats a `profiles.created_at` under ten
  minutes old as a signup — the row `handle_new_user()` writes inside the signup
  transaction, and a wide window because the client's clock is not Postgres's.
- **Desktop event names are `desktop_`-prefixed, all of them.** Four of them were
  not until 2026-08-09 — `prompt_created`, `prompt_updated`, `prompt_deleted` and
  `onboarding_completed` are byte-identical to events the iOS container has been
  sending into 465060 since 2026-06-11, so a mistyped token would have merged two
  platforms' series unsplittably. Renaming was free because desktop has no event
  history; it stops being free the moment the token goes live.
- Every rewrite event carries: `host_app_bundle_id`, `capture_mode`,
  `io_path` (`ax` | `clipboard`), `prompt_origin`, `latency_ms`,
  `candidate_count`, `accepted` / `selected_index`.
- `io_path` is the one to watch. A rising clipboard-fallback rate in a specific
  bundle id is the earliest signal that an app's AX tree changed — which is why
  the dashboard breaks it down by `host_app_bundle_id` and not only over time.
- `desktop_rewrite_failed` now carries `message`, the app's own Japanese toast.
  It used to take the string and drop it, so the failure tile could only ever
  have been a count.

---

## 8. Design

`design.md` is the authority, and **as of 2026-08-07 it holds Willow's system, not
ElevenLabs'.** It is measured from the three screenshots in `reference/` rather than
described from a website, so almost all of it maps directly; the parts that do not are
listed at the end of this section.

**This was a replacement, not a re-skin.** The old system and the new one disagree on
six of seven defining choices — warm eggshell vs cool white, taupe fill-differentiated
cards vs white border-differentiated ones, whisper-300 display type vs weight-600 UI
type, pills everywhere vs 8 pt controls, accents banned from all chrome vs one indigo
running the chrome, and a flush content pane vs a floating panel. Anything in this repo
still reasoning from "97% achromatic", "eggshell", "taupe" or "Waldenburg" is stale.

### Two ramps

**Main window — published system verbatim.** Shell `#f2f2f4`, sidebar `#f5f6f7`, a
white content panel floating inside the shell with a 4 pt margin and a 12 pt radius,
white cards bounded by `#ececee` hairlines, text `#4e4d51`, indigo `#5a57ba` on filled
buttons / switches / links / badges / selection, green `#46a588` for completion.
`Tokens.Window` is that table and nothing else.

**Overlay — its own dark ramp.** Unchanged by the restyle:

| Role | Value |
|---|---|
| overlay canvas | `#141312` |
| overlay surface | `#1e1c1a` |
| overlay hairline | `#2e2b28` |
| overlay text primary | `#fdfcfc` |
| overlay text secondary | `#a59f97` |
| overlay text tertiary | `#777169` |

These values used to be justified as a derivation of the light palette's warmth. That
palette is gone; the numbers did not move, and the honest reason they are what they are
is that this is the ramp the bar is drawn from. Restyling the overlay against Willow's
own bar was considered and **deferred by decision** — it is the one path that has run
end to end, and the window was the thing that needed fixing.

### Sanctioned deviations from design.md — and only these

0. **The generating capsule takes no shadow at all** — the one exception to deviation 1
   below, and it is a consequence of the glow. AppKit derives a window shadow from the
   content's alpha, which is right for a hard-edged shape and wrong for a capsule
   wrapped in a soft halo: it thresholds the alpha, takes the *glow's* outer envelope as
   the silhouette, and draws a shadow around that. What you see is a dark ring standing
   off the capsule by exactly the glow padding — a black border with a gap. Rendering
   the identical content over white shows nothing of the kind, which is how it was
   pinned on the window rather than the view. `GeneratingPanel.hasShadow` is therefore
   `false`; the bloom already separates the capsule from the wallpaper, which is the
   whole job deviation 1 exists for. Any future overlay window whose content fades out
   near its own edges needs the same treatment.
1. **Elevation.** The system's near-invisible shadows (`0.04` alpha) assume a
   controlled canvas. The overlay floats over arbitrary wallpapers and needs a
   real shadow to read at all. Overlay only; the main window keeps hairlines.
   **It has to be `NSWindow.hasShadow`, not a SwiftUI `.shadow`.** Every overlay
   window is sized exactly to its content, so a SwiftUI shadow is clipped to the
   frame and the only part that survives is a grey smear in the corners — the
   one place the shape's own fill is not covering it. AppKit derives its shadow
   from the content's alpha and draws it outside the frame. It caches that
   outline, so `invalidateShadow()` is required after every resize or the
   collapsed pill keeps wearing the expanded row's silhouette.
2. **Density.** `card-padding: 20px` on a ~420 pt result panel still leaves the
   overlay too little room. The overlay uses a compact scale: 11/12/13 pt labels,
   14 pt/1.5 result body, 12–16 pt padding. The main window uses the
   published scale unchanged.
3. **Input radius.** The system says `inputs: 8px`; overlay inputs use 10 pt so a
   field inside the 20 pt result card does not read as a chip.
4. **The generating capsule is the overlay's only colour, and it is measured.** The
   border used to be an animated violet→orange (`#0447ff` → `#ff4704`) carried over
   from the ElevenLabs system — but `generating.png` does not show two colours. Sampling
   the ring's peak-chroma pixel every 10° around the capsule gives a hue that sweeps a
   full circle: cyan at 3 o'clock, blue at 6, violet and magenta up the left side, pink
   at 10, coral at 12, then amber and green back to cyan. `Tokens.Overlay.generatingGradient`
   is that sweep, and its saturation is measured too — scaled down to the reference
   capsule's own size the ring there peaks at a chroma of 89, where a full-strength
   spectrum peaks at 154, so the stops are HSL 58 % / 46 %. One rotation takes 2.6 s: it
   is a waiting indicator, and at the 1.6 s it shipped with it read as urgency.
   Nothing of the old palette survives anywhere in the app now.

   **The capsule says 生成中, not the button's name.** It was labelled with
   `buttonTitle`, so pressing 差し替え put 「差し替え」 on a capsule that is not replacing
   anything: nothing has been written back at that point and the rewrite may still fail.
   The one thing true while it is on screen is that a candidate is being generated —
   「返信を生成中」 in reply mode.
5. **The capsule's border is a bloom, and the window is padded to hold it.** Measured
   perpendicular to the ring in `generating.png`, the core is a **single pixel** on a
   capsule the same height as ours, with ~8 pt of falloff either side: almost all of
   what reads as a border there is glow. So the crisp stroke is 1 pt, and behind it sit
   two blurred copies — a 3 pt chromatic halo at radius 9, and a tight white
   `strokeBorder` at radius 2.5 and 30 % — because the reference's ring is white at the
   core and coloured in the spill. The window carries transparent margin for it to fall
   on, and that margin is **asymmetric**: `generatingGlowPadding` (6) at the bottom
   because `bottomInset` is the only slack there is — hanging 6 pt of window below the
   capsule is what keeps the *capsule's* bottom edge, not the window's, on the bar's
   line — and `generatingGlowSpread` (11) above and to the sides, where the halo is
   actually seen. The bottom of a glow sitting on the Dock is not worth a 2 pt jump.
6. **What rotates is a square of gradient, never the shape.** The original spun a
   stroked capsule with `rotationEffect` and masked it back to its own un-rotated
   outline. That only holds while the two overlap, and a 176×36 capsule turned 90° is
   a 36×176 one: the border thinned to a few stray pixels and vanished twice per
   revolution. It went unnoticed because the capsule is on screen for a second at a
   time. The gradient is now a square sized to the capsule's diagonal, rotated behind
   a capsule-shaped mask. It has to be a rotating *view* rather than an
   `AngularGradient(angle:)` rebuilt per frame, because a gradient is not `Animatable`
   and the spin would jump straight to 360°.

### What the window deliberately does not take from the reference

- **Vibrancy.** 【推測】the reference's sidebar is an `NSVisualEffectView` sidebar
  material — `#f5f6f7` against a `#f2f2f4` window edge is what that looks like over a
  light desktop. Ours is a flat fill at the measured value, so it cannot shift with the
  wallpaper behind it. `window.appearance` is pinned to `.aqua` for the same reason:
  the palette is light-only, and the system-drawn halves (switches, carets, the
  titlebar) would otherwise come from a dark appearance on a Mac in dark mode.
- **The plan card and the promo pill** above the sidebar's account row. `profiles` has
  no plan column (§14) and there is no billing surface to put there.
- **The settings modal's search field and its Help Center / Support Community links.**
  Six switches do not need a search box and we have no help centre — a control that
  never finds or opens anything reads as broken.
- **The share button** at the top-right of the home page.

### Icons

**Reicon Outline, not SF Symbols** — `App/Resources/Icons.xcassets`, MIT, extracted from
`reicon-react@1.2.0` (each icon there is a path string; the catalog's README records the
extraction and the whole role → Reicon name table). They are template images, so they
take `foregroundStyle` like a symbol did.

`Icon.Name` is an **enum of roles**, not of pictures: `.buttons`, not `.category`. Two
call sites already want the same glyph for different reasons, and a string-typed
`systemName` is how a window ends up with three subtly different pencils. Adding one
means adding an imageset *and* a case — deliberately, because the alternative is a
`Image("icon-…")` that compiles and draws nothing.

`AppIconView` is the one exception to the single-set rule: real application icons come
from `NSWorkspace` in full colour, because they are the user's apps and not our chrome.

**The product mark is not Reicon.** The artwork in `public/`
(a keycap, off-white with a black keyline and two black eyes) replaced
`wand.and.sparkles` everywhere on 2026-08-07. Three raster assets were cut from it —
`icon-mark` (line art, template), `icon-mark-filled` (the full colour art, the one
non-template static image) and `AppIcon`. Three Higgsfield-derived animation atlases now
carry the overlay states. The catalog's README carries the derivation:

| Surface | Cut | Why |
|---|---|---|
| sidebar, onboarding (`AppMark`) | line art, tinted `#5a57ba` | the full-colour art's black keyline reads as a photograph on a `#f5f6f7` sidebar; §14's rule is that the accent is on the chrome |
| menu-bar status item | line art, `isTemplate = true` | the menu bar inverts its contents for dark mode and for selection, which only works on alpha |
| overlay bar (`BrandGlyph` → `BrandMark`) | idle atlas | 16 transparent frames at 4 fps: a restrained bob and blink, legible at 16 pt |
| expanded/reply/input bar | engaged atlas | a pronounced pop, lean and blink that survives at 16 pt |
| generating capsule | thinking atlas | a pronounced side-to-side rock and directional eye movement; still achromatic, so the capsule ring remains the overlay's only colour |

`MascotIdleSprite`, `MascotEngagedSprite` and `MascotThinkingSprite` are 512×512 PNG atlases in
`Assets.xcassets`, four columns by four rows with 128 px frames. `MascotSprite` slices
them once into `NSImage`s and advances at 250 ms. Its AppKit view deliberately has no
intrinsic size and paints each frame into its SwiftUI-proposed bounds; an `NSImageView`
made the 128 px source behave like a 128 pt view and clip inside the 16 pt pill slot.
This is deliberate instead of shipping the 960 px H.264 sources: the overlay needs
alpha, deterministic loops and no always-on video decoder. Both clips use the original
mark as first **and** last frame, and both were normalized through the same stable crop
so changing state does not change scale.

`AppIcon` did not exist before this — `project.yml` had pointed
`ASSETCATALOG_COMPILER_APPICON_NAME` at an `AppIcon` that was never in the catalog, so
the app wore the generic one. `public/default.png` is full-bleed and macOS does **not**
mask app icons the way iOS does, so it is inset to the 824/1024 grid and squircle-masked
rather than shipped square.

### Type

Inter carries everything, and the hierarchy is **weight**: 600 for page titles and stat
numbers, 500 for row labels and buttons, 400 for prose, at 11–20 pt. Geist Mono 400 at
12 pt for timestamps and version strings. Both OFL. `Tokens.Font.display` is the same
face as `body`, heavier — not a separate display face; the previous system's
whisper-weight 300 display type is gone with the rest of it.

### Result panel, per `result.png`

Header `‹ 1/1 ›` pager + `✕`; the submitted prompt echoed in an editable field
at top; scrollable body with a bottom fade; footer with regenerate / copy / 👍 /
👎 and a primary `Insert ⏎`. (`result.png` also puts a chevron button in the fade;
ours is deliberately gone — see below.)

**Regenerate keeps two meanings inside one morphing control.** At rest the footer is
unchanged. Hovering ↻ expands that control left-to-right across the footer's existing
28 pt slot, visually covering copy, feedback and Insert while their untouched row fades
under it. The panel and result viewport do not change height. The ↻ stays attached to
the growing right edge and becomes an upward Send control at the far right; sending an
empty field performs the same plain regeneration as before. The Send disc is 20 pt
inside a 28 pt hit target. The field has no native placeholder: a separate
`textSecondary` layer supplies it, so AppKit cannot replace its colour with black. The
surface and content are clipped before a constant `hairline` is overlaid; never clip the
stroke itself, and never promote it to a bright focus ring. Pointer departure restores
the normal actions after 140 ms, while field focus pins the bar so moving the pointer
away cannot destroy typed guidance. Escape clears and collapses it. The field is one
line and scrolls horizontally because this is a short correction to an answer already
on screen, not the general-purpose ✎ path.

The model source and the write destination must remain separate for a guided run.
`PendingRewrite.requestText` is the candidate being refined, while
`PendingRewrite.captured` remains the original AX/clipboard target. Conflating them would
make generation look right and Insert write to nowhere useful. Reply mode uses the same
split naturally: the candidate becomes `<existing_draft>` and the typed text remains
`<reply_guidance>`, while `replyTo` is carried unchanged. A plain ↻ after that reruns
the same candidate + guidance pair rather than going back to the first draft.

**The pager is always shown, `1 / 1` included, and regeneration grows it.** Hiding it
below two pages was tried and reverted: `result.png` shows `‹ 1/1 ›`, and the readout is
the promise that another attempt will not destroy this one. Every completed plain or
guided regeneration appends to the current panel session and selects the first new page,
so the sequence becomes `2 / 2`, `3 / 3`, and the arrows revisit every earlier answer.
The echoed prompt changes with the page. Regenerating or refining after navigating back
branches from the answer currently on screen but still appends at the end; it never
truncates the later pages. Cancel and failure restore the session that existed before
the request. `ResultPage` owns its request, event id, response-local candidate index and
history id so Insert and feedback follow the selected answer rather than the latest one.
The desktop still requests one candidate per call (§6), though the pager also accepts
all candidates if the server policy changes later (up to `MAX_CANDIDATES`, 5).

**The panel's height follows its content, the same way the pill's width does.**
SwiftUI measures the assembled card, `ResultPanel.applyContentHeight` resizes the
window, and the bottom edge stays put so it grows upward away from the screen
edge. The body scrolls past `resultBodyMaxHeight` (240 pt) and the panel stops at
`resultPanelMaxHeight` (440 pt). A constant height instead put a one-line rewrite
in the middle of a 440 pt slab of `canvas`, which is what `debug.png` shows.

**The card has to be `clipShape`d, not just given a rounded background.** The
footer paints its own `canvas` fill, and that rectangle is square — it covered the
two bottom corners, leaving a card rounded on top and cut off at the bottom. The
fill is still needed with the hairline gone: it is what the body's fade resolves
*to*.

**There is no divider above the footer.** It had a 1 pt `hairline` across the top;
`result.png` has nothing there — the body text simply dissolves into the footer.
On a card carrying no other rules, one rule under the body read as a table.

The bottom fade renders **only when the body actually overflows**. Unconditional,
it is an affordance pointing at empty canvas — visible in `debug.png` a good 200 pt
above the end of the text. This is also why removing the hairline is safe: when the
body does not overflow, the text ends short of the footer and there is nothing to
separate.

**The chevron is gone, and it should not come back as decoration.** `result.png`
has one sitting in the fade and we copied it, but ours was
`allowsHitTesting(false)` — it looked like a button and clicking it did nothing.
The fade already carries the whole message ("there is more below") and the body
scrolls, so it was a control promising an action that did not exist. Restore it
only with a scroll-to-bottom action behind it, and then it goes **on top of** the
fade, never in the flow with it.

**Which is the other half of the bug the fade shipped with.** The chevron used to
sit in a `VStack` under the gradient, so it laid out *below* the gradient and
pushed it up by its own height (26 + 6 pt). The gradient stopped 32 pt short of the
scroll viewport's bottom edge, and text scrolling through that strip drew at full
opacity: the last line faded out, then reappeared solid underneath its own fade,
above the footer. It was in every overflowing result and survived two passes over
this panel because the fade was only ever reasoned about, never watched — the band
*looks* right in isolation, and nothing in the code reads as wrong until you ask
what sets the gradient's bottom edge. A fade has to be anchored to the same edge as
the thing it is fading and cover it completely.

**The stops are eased, not linear**, which is the difference between the
reference's look and a band. Alpha on a straight clear→canvas ramp does most of its
perceptual work in the first third, so the top of the band has a visible edge and
reads as a scrim laid over the text. Holding it near zero through the first half
(`0 → 0.15 → 0.55 → 1` at `0 / 0.5 / 0.75 / 1`) over 64 pt puts the change where
the text is already thinning out. 64 is safe against the viewport because
`overflows` is only true past `resultBodyMaxHeight` (240), so the band is never
taller than the area it sits in.

---

## 9. Build and distribution

- macOS 14.0 minimum (matches Willow, and `../Japanese/Package.swift`'s
  `.macOS(.v14)`).
- XcodeGen (`project.yml`), mirroring the iOS repo's setup.
- SPM: `supabase-swift`, `PostHog`, `Sparkle`. Nothing else without a reason.
- `NSApp.setActivationPolicy(.accessory)` — no Dock icon; the main window (§14) is
  reachable from the menu-bar item. (Willow keeps a Dock icon; we don't need one
  for a hover-driven app.) **The policy never flips**, not even while the window
  is open: `.regular` would give it a Dock icon and a ⌘Tab entry, and the
  transition activates the app, which is exactly the focus theft §4 forbids.
- Launch at login via `SMAppService.mainApp.register()`.
- Info.plist: `NSAccessibilityUsageDescription` is required and user-visible —
  write it plainly, it is the string that appears in the permission dialog.
- Developer ID signing + notarization + hardened runtime. **No App Sandbox**
  (§2). Sparkle for updates.
- **The Developer ID Application identity is installed and verified.** On 2026-08-09,
  `security find-identity` reported `Developer ID Application: Yihuan Sun
  (4KS6YS23KT)` with its private key available. The password-protected source `.p12`
  stays outside the repository and its encrypted archive/password are separate GitHub
  production secrets. The `v0.1.0` workflow artifact is signed, notarized, stapled and
  public; distribution now needs only the owner install and two-version Sparkle test in
  `docs/releasing.md`.
- **`PRODUCT_NAME` must stay ASCII.** Setting it to `敬語ボタン` makes the
  executable `Contents/MacOS/敬語ボタン`, and Xcode's debug-dylib signing flow then
  signs `*.debug.dylib` and `__preview.dylib` but silently skips the main
  executable — the bundle sign fails with `code object is not signed at all` /
  `Command CodeSign failed with a nonzero exit code`, which names neither the real
  cause nor the file. `PRODUCT_NAME` is `KeigoButton`; `CFBundleDisplayName` and
  `CFBundleName` carry 敬語ボタン, and that is what Finder, the menu bar, and the
  Accessibility dialog display.

---

## 10. Out of scope for v1

Tracked so they don't creep in:

- Screen context. Willow links `ScreenCaptureKit` + `Vision` for on-screen OCR,
  and `prompt/` has a working screenshot→analyze pipeline
  (`context-service.js`). Both are deferred: they add a permission, a vision
  call on the critical path, and a much larger privacy surface.
- Global keyboard shortcut. Hover-only by decision. If it goes in later, it
  changes nothing structural — the capture ordering in §4 already works for it.
- Windows. Willow ships one; ours would be a separate codebase against UI
  Automation. Nothing here should be abstracted in anticipation of it.
- Requesting multiple candidates in one desktop call. The pager can display them, but
  desktop deliberately requests one candidate per generation and accumulates attempts.
- Streaming (`stream: true` exists in the contract; v1 waits for the full
  response).
- **Server-backed usage stats.** §14's four stat numbers still come from a local
  file, and the reasoning below stands for them. **The quota readout is now the
  exception**: `public.desktop_get_entitlement()` is granted to `authenticated` —
  the first and only `desktop_*` entry point that is — because a cap the user
  cannot see is a cap that ambushes them, and it takes no arguments precisely so
  it cannot become the IDOR that a `p_user_id` parameter would be. Reading
  `desktop.usage_buckets` back for the *stat card* would still mean another grant
  on a shared project's API surface. Deferred, not refused; see §12.
- Team / collaboration surfaces. The reference has them; we have no team object.

---

## 11. Identity

Decided. Follows `../Japanese/project.yml` rather than establishing a parallel
convention — `bundleIdPrefix: com.core7.keigobutton`, `DEVELOPMENT_TEAM: 4KS6YS23KT`.

| | |
|---|---|
| User-facing name | **敬語ボタン** — same as iOS. Not renamed; it is the same product on a second surface |
| Bundle id | `com.core7.keigobutton.mac` (the iOS extension is `.keyboard`) |
| URL scheme | `keigobutton://` — one scheme, no alias |
| Team ID | `4KS6YS23KT` |
| Keychain service | `com.core7.keigobutton.mac.session` |

## 12. Open questions

- ~~**Subscription enforcement.**~~ **Answered by `docs/billing.md`.** Two separate
  quotas: the desktop's counters live in `desktop.usage_windows` and the keyboard's in
  `ai_rewrite_usage_buckets`, which follows §2's rule about never writing to the iOS
  app's tables. A free desktop user who hits 50 gets the ⚙︎ プラン paywall with the
  computed reset date; a Pro user who hits 1,000 gets a message and no paywall, because
  there is no tier above (§9 rows 41–42). 「iPhone版はこれからも無料」 is on the plan
  card, so the two quotas are stated rather than merely true.
- **Brand relationship.** The iOS container uses the Bikey design system (purple
  + Liquid Glass); this app uses `design.md`, whose accent is now Willow's indigo
  `#5a57ba` **verbatim** — taken by decision on 2026-08-07 over the alternative of
  keeping Willow's structure with the phone's own hue. Two surfaces of one product
  therefore still do not look like one product, and the desktop's accent is now
  another company's. Worth a decision before launch rather than after; changing it
  later is one constant in `Tokens.Palette`.
- **Migration file ownership.** The project's migration history lives in
  `../Japanese/supabase/migrations/`. If the `desktop` schema is applied from
  this repo, that history diverges. Recommendation: the migration file lands in
  the iOS repo (one project, one history); only the Edge Function lives here.
- **Whether the ホーム numbers should follow the account.** They are per-Mac
  today (§14). Making them cross-device is one read function away, but that
  function has to be granted to `authenticated` on a project the iOS app shares,
  and the migration lands in the iOS repo per the point above. Worth deciding
  before a user has two Macs and two different streaks.
- **Whether the phone should get the same button editor.** §14 writes
  `user_prompts` from the desktop, so the two surfaces now both author buttons.
  Nothing reconciles a simultaneous edit — last write wins, per row.

---

## 13. House rules

Inherited from `../Japanese/CLAUDE.md`, and they apply here unchanged:

- Surgical changes only. Don't refactor adjacent code you didn't touch.
- No speculative abstractions, no flexibility that wasn't requested, no error
  handling for impossible cases.
- Default to no comments. Add one only when the *why* is non-obvious.
- Ask before destructive operations.
- State assumptions before implementing; if something is unclear, stop and ask.

---

## 14. The main window

The light surface. `App/Main/`, one `NSWindow` at 1000×700 (min 920×640), a 218 pt
sidebar on the grey shell with the content as a **white panel floating inside it** —
inset 4 pt on three sides, 12 pt radius, its own soft shadow, and no divider line
anywhere. `design.md`'s published system unchanged; §8's deviations are overlay-only.

The minimum width is set by the preferences modal, not by the pages: it is a 780 pt
card centred *inside* the window (§14's ⚙︎ block), so a narrower window would clip it.

### Reference and what was *not* copied

Three Willow screenshots in `reference/` set the shape: persistent left sidebar,
account pinned bottom-left, a modal sheet for low-level prefs, one stat card row
above a searchable history. What is ours and not theirs:

| Willow has | We have | Why |
|---|---|---|
| "Time saved — 4 hrs 50 min" | nothing | Theirs is dictated words ÷ typing wpm, real arithmetic. A rewrite tool has no ground truth for it; the figure would need an invented seconds-per-rewrite coefficient, and it would be the biggest number on the page and the only made-up one |
| Dictated words, average wpm | 書き換え回数, 書き換えた文字数 | Counted, not modelled |
| Purple Upgrade card, promo pill, plan badge | nothing | The accent itself we now take (see "Where the colour is"); the billing surfaces we do not — `profiles` has no plan column, so there is nothing true to put in that block |
| Dictionary, Style Matching, Collaboration, Team Members | ホーム / ボタン / アカウント | We have no team object, no dictionary, and no per-app tone model. Empty destinations are worse than absent ones |
| Learning Center | compact setup recovery | First-run teaching moved to the dedicated flow in §15; Home only repairs a lost session or Accessibility grant |

### Where the colour is

**This section used to say the opposite, and the reversal is the point.** The old
system forbade its accents on buttons, links, badges and focus rings, so every
coloured pixel in the window had to be artwork and `App/Design/BrandVisuals.swift`
existed to quarantine it. `design.md` puts indigo `#5a57ba` **on the chrome**:

| Where | What |
|---|---|
| Primary buttons | accent fill, white text (`ActionButton(style: .primary)`) |
| Switches | accent when on, `#d9d9da` when off (`View.accentSwitch()`) |
| Links | `#5856b5` (`LinkButton`) |
| Badges and chips | `#e4e5f0` / `#edeefa` plate with `#5856b5` text — the メイン badge, the history label, the バー keycap |
| Selection | onboarding progress, the settings modal's active row |
| Focus rings | accent border on `FieldBackground` — the rule this most directly reverses |
| Sidebar mark, avatar, icon plates | `AppMark`, `Avatar`, `IconPlate` — flat accent, no gradients |
| Overlay generating capsule | §8 deviation 4, the spectrum measured off `generating.png` |

Green `#46a588` is the only other colour and marks one thing: done. Stat numbers,
sidebar selection and body text stay achromatic. `BrandVisuals.swift` still exists but
is no longer load-bearing — it is just the shapes that are not text or a control, and
its gradients are gone.

The Home stat row uses `StatsBackdrop`, a generated 5:1 raster derived from the window's
own white / fog / indigo-tint ramp. It has no motif and is composited at 55% over white;
dark text, hairline border and column rules remain the card's structure. It replaces the
saturated indigo→violet code gradient that made the card look like promotional AI art.

### Reordering is explicit

The button list does not drag. It was tried both ways: the hand-rolled `DragGesture`
moved a row while changing the `ForEach` beneath it and shook; SwiftUI's native
`.draggable` lifted an opaque 340 pt preview out of a much wider row, so the thing being
moved looked unrelated to its destination. For a live list of four to seven items,
up/down arrows are faster to understand and remove every ambiguous intermediate state.

Each row has Reicon AngleUp / AngleDown controls in a 26 pt-wide vertical pair on the
left. One click swaps with one adjacent row, the arrow at either list boundary is
visibly disabled, and the list eases to its new order over 0.16 s. There is no drag
preview, hidden drop target or pointer-following offset.

There is one visible list. Its first row is the `main` slot and every later row is
`sub`; moving another button to the top replaces the phone's main button. The pure
`UserPromptOrder` normalizer owns this invariant and is unit-tested. Writes are serial:
rapid arrow clicks coalesce to the newest pending snapshot instead of racing older
responses against newer ones. Each snapshot PATCHes secondary rows first and the new
main last, so a partial write cannot create two main rows.

Deleting is an `IconButton` on the row behind a confirmation alert — not buried
in the editor, which is where it was and where nobody found it.

No server write happens until an arrow has selected the next complete order.

### Five things that are easy to leave out and obvious when missing

1. **Cursors.** Everything clickable takes `.pointingHand`, the movable overlay bar
   takes `.openHand`, and disabled controls stay `.arrow`. `View.cursor(_:)` wraps an
   `NSView` — **not** `NSCursor.push()` / `pop()` in `.onHover`, which is the usual
   SwiftUI trick and leaks: a hover that ends because the view was *removed* never
   pops, and reordering a list removes hovered views constantly.

   **`addCursorRect` alone is why the overlay never showed a pointer.** Cursor
   rectangles are in effect only in the **key** window, and §2 forbids the pill from
   ever becoming key — so every control on the bar was stuck with an arrow no matter
   what it declared, while the identical code worked in the main window, which *is*
   key. That is documented behaviour and it matches the symptom exactly.

   **The replacement is an active tracking area, and its window must opt into mouse-
   moved delivery.** `CursorArea` uses `.mouseEnteredAndExited` to set the cursor and
   `.mouseMoved` to reassert it after AppKit resets it. `NSWindow` defaults
   `acceptsMouseMovedEvents` to false; leaving that default on `PillPanel` made the
   reassertion dead code and was why the tracking-area replacement still showed an
   arrow. `PillPanel` now sets it to true. `NSTrackingArea` turned out to be unreachable
   by any synthetic pointer:
   moving the window under a stationary pointer, `CGWarpMouseCursorPosition`, and posted
   `.mouseMoved` events at the HID tap each produced **zero** enter/exit callbacks, even
   for a plain `NSView` with no SwiftUI in the way — AppKit only recomputes tracking on
   real HID motion, so nothing here can be tested without a hand on the mouse. (An
   early run that appeared to prove `.cursorUpdate` dead and enter/exit alive did not
   reproduce; it was almost certainly the machine's own pointer crossing the probe.)
   So: the cursor rect stays, for the key window and because it is the only mechanism
   AppKit re-asserts on every mouse-moved; `.mouseEnteredAndExited` + `.activeAlways`
   is added, being the one channel Apple documents as reaching a non-key window in a
   non-active app; and `.mouseMoved` on the same area re-asserts in case something else
   resets the cursor after the enter. `CursorStack` arbitrates, because the pointer is
   inside the bar's area and a pill's area at once and the pill has to win.

   The overlay now declares: `.pointingHand` on the prompt pills, ✎, the submit arrow,
   the result panel's pager, ✕, footer and Insert, and the error toast; `.openHand` on
   the bar's own background, which is what `isMovableByWindowBackground` drags;
   `.arrow` on a disabled pager arrow or an empty input's submit. The input bar
   deliberately installs **nothing** on its background — the field brings its own I-beam
   and a hand across the whole bar would be claiming the one place the pointer means
   something else. `OverlayController.setPillVisible(false)` calls
   `CursorStack.releaseAll()`, because a window that is ordered out sends no exit and
   the bar always disappears under a stationary pointer.
2. **Key equivalents.** An `.accessory` app never displays a menu bar, and
   without `NSApp.mainMenu` it has no key equivalents either — `⌘C`, `⌘V`, `⌘A`
   and `⌘Z` do nothing in every text field. `AppDelegate.installMainMenu` builds
   an invisible, load-bearing Edit menu; dispatch walks the main menu whether or
   not it is on screen.
3. **Focus.** A plain `TextField` draws no focus indication at all, so a stack of
   three of them gave no clue which was taking the typing. `SettingsField` owns a
   `@FocusState` and takes an accent border at 1.5 pt. It used to thicken to ink
   instead — weight rather than colour — because the old system forbade accents on
   focus rings. `design.md` colours them. The **unfocused** field has no border at
   all: it is a `#f7f7f8` fill, which is also why `PromptEditor` sits on the card's
   white rather than on a grey panel of its own — grey fields inside a grey panel is
   one container too many.
4. **The titlebar's safe-area inset.** `NSHostingView` inside a `fullSizeContentView`
   window hands SwiftUI a top safe-area inset the height of the titlebar, and it is
   added to whatever padding the view already has. The panel's 32 pt top read as ~60
   against its 32 pt bottom, and the sidebar's brand row sat that far below the traffic
   lights it was measured against. `MainWindowView` calls `.ignoresSafeArea()` on its
   root so the numbers in the file are the numbers on screen. Anything that reads
   "the top padding looks bigger than the bottom" is this.
5. **Optical centring.** SwiftUI centres a `Text` by its **line box**, and the line box
   a Japanese string gets carries more space under the glyphs than over them —
   measured with `ImageRenderer`, 「ホーム」 at 14 pt inks from 22.5 to 34.5 inside a
   60 pt frame, so its own centre sits 1.5 pt above the box's. A glyph centred in the
   same `HStack` is therefore centred against nothing the eye can see and reads as
   sitting low: the sidebar's icons measured 1.7–2.2 pt below their labels. The gap is
   a constant (1.4–2.1 pt from 11 pt through 15 pt, on katakana, kanji and Latin
   alike), so `View.opticalCentre()` is a flat −1.5 pt applied to the **glyph** —
   nothing about type rendering changes. It is on the sidebar's nav icons and the brand
   mark, which measured 86.33 against 86.33 afterwards.

   `opticalPadding(vertical:horizontal:)` is the other half of it, and the distinction
   matters: `opticalCentre` is for a glyph that is a **sibling** of the label, while a
   plate drawn **around** the label has to bias its own padding instead. Offsetting the
   text inside its plate moves the ink and leaves the plate behind — measured, that
   turned the メイン badge's 3.5/6.5 gaps into 2.0/8.0, i.e. made it worse. Biasing the
   padding gives 5.0/5.0. This was the real content of "the badge needs padding": half
   of the complaint was never the amount.

Page content runs the **full width** of the pane; individual inputs are capped
(`AccountView.fieldWidth`). Clamping a whole page instead left it as a narrow
column hugging the left edge of a 940 pt window. The signed-out form used to be a
deliberate exception, pinned to a 460 pt column beside a marketing panel; it is not
one any more — see "The signed-out form is the same page, not a different one".

**Badges are one object.** `Badge` is `design.md`'s 9999 pt `#e4e5f0` plate with
`#5856b5` 12/500 text and 8/4 `opticalPadding`. The メイン slot marker and the history
list's button label were written separately and had drifted to 11/7/1 and 12/8/2 — two
sizes, two paddings, one role, and neither of them the 12–13 px the system specifies.

### Structure

- **Sidebar** — ホーム / ボタン, then the account block pinned bottom with a ⚙︎
  that opens the preferences modal. Active rows **darken** to `#ededef`; they used to
  lift to the canvas, and `design.md` does the opposite — on a near-white sidebar
  there is no lighter step left to take. The sidebar runs under the transparent
  titlebar and reserves 36 pt for the traffic lights; the panel reserves 32 pt,
  because the titlebar's drag region runs the full width of the window.
- **ホーム** — opens with the **usage row**, not a page title: `design.md`'s home leads
  with the gesture that runs the product ("Hold F1 to dictate on ⟨apps⟩") and so does
  ours, with the icons of the apps this Mac has actually rewritten in beside it. Then
  the four-column stat card, a compact recovery card only when sign-in or Accessibility
  is missing, then history grouped by day under a search pill. Rows expand in place.
- **ボタン** — one ordered list for the hover row. The first row is the main button;
  every row can be enabled/disabled, moved with its compact left-side arrows, retitled,
  reworded, added and deleted.
- **アカウント** — display name (editable), address, join date, sign in, **sign
  up**, Google, sign out. Groups are captioned from above, never titled from inside.
- **⚙︎ modal** — 780×540, two panes (一般 / 履歴 / このアプリ), captioned row groups on
  the right, ✕ in a grey disc. **An overlay inside the window, not an `NSWindow`
  sheet**: `design.md`'s modal is centred behind a 40 % scrim and closes when you click
  away from it, and a real sheet does none of those three things. Escape is wired twice
  — `onExitCommand` plus an invisible `.cancelAction` button — because a focused text
  field elsewhere in the window swallows it often enough that neither alone is
  dependable.

### Closing the window does not close the app

The pill is the product; the window is a place to configure it.
`OverlayController` is owned by `AppDelegate`, never by the window, so the two
have no lifetime relationship at all. `isReleasedWhenClosed = false` keeps the
instance so reopening returns to the same page, and
`applicationShouldTerminateAfterLastWindowClosed` returns `false` explicitly. The
only way out of the app is 終了 — in the menu-bar menu or at the foot of the
sheet.

### Buttons are written, not just read

`UserPromptRemoteStore` gained `create` / `update` / `delete`. §2 already called
`user_prompts` the one shared read-write table; this is the surface that uses it.
Three things about that table are load-bearing and were read off the live project
rather than assumed:

1. **`user_id` is `NOT NULL` with no default.** PostgREST will not fill it from
   the JWT — the insert has to carry it, which is why `create` reads
   `auth.currentSession?.userId` first and fails cleanly if there is none.
2. **`builtin_key` is CHECK-constrained** to `polite | natural | email |
   translateToEnglish`. Desktop-authored rows leave it null and set
   `origin = user_authored`, matching what the phone writes for a hand-made
   button.
3. **Every row is deletable, including a builtin.** The desktop sends a real DELETE;
   deleting the current main immediately promotes and persists the next row. Existing
   phone builds may re-seed a missing `builtin_key`, so permanent cross-client builtin
   deletion still needs an iOS-side tombstone contract rather than another desktop UI
   condition.

Reordering normalizes the whole list: index zero becomes `main` at order zero, and the
remaining `sub` rows are numbered from zero. `UserPromptRemoteStore.update` sends the
slot as well as `sort_order`; without that field a main replacement would look right
locally and revert on the next reload.

Every mutation ends by reloading from the server and re-pushing the hover row, so
a rejected write cannot survive in the list.

### History and stats are local, and hold real text

`Sources/DesktopRewriteKit/History/`. One JSON file at
`~/Library/Application Support/com.core7.keigobutton.mac/history.json`, newest
first, capped at 500.

**Not `desktop.rewrite_events`.** That table exists, but every
`public.desktop_*` entry point is `REVOKE EXECUTE`d from `authenticated` (§6) —
the client cannot read its own rows without a new grant on a project the iOS app
also lives behind. Counting on-device costs no migration and works offline; the
price is per-Mac numbers that start at install, which §12 records as an open
question.

The file holds the user's actual text, captured from arbitrary applications.
Hence the 履歴を保存する switch, the erase button, and the `0o600` mode — the
last of which is pinned by a test, because `.atomic` writes through a temp file
and would otherwise inherit the umask.

`RewriteStats.from` is pure so the streak's edge cases are testable: it anchors
to **yesterday** when today has no rewrites yet, so opening the app in the
morning does not report a streak of 0 for work that is about to happen.

### Sign-up has two successful endings

With "Confirm email" on, `/auth/v1/signup` returns a user row and **no session**.
`SignUpOutcome.confirmationRequired` is that case, and the account page says so
rather than showing a signed-out window over an account that was just created.
`AuthService.signUpError` maps `user_already_exists` and `weak_password` from
both the modern `error_code` and the older `msg` string — dropping either turns
an actionable error into "接続できませんでした".

The account page's email address is read from the JWT's `email` claim, not from
`GET /auth/v1/user`: no round trip, correct offline, and it avoids widening
`AuthSession`, which would invalidate every session already in the Keychain.

### The account page is as big as `profiles` allows

`ProfileRemoteStore` reads and writes the shared `profiles` row (§6). The live
table is **exactly three columns** — `id`, `display_name` (NOT NULL, default
`''`) and `created_at` — with `select/insert/update own` RLS. So the page offers
a name, an address and a join date, and that is the whole honest surface: there
is no plan, avatar or subscription column to render, and inventing one would mean
a migration in the iOS repo.

Saving the name **upserts** rather than PATCHes. `profiles_insert_own` exists
because the row may genuinely not be there — a user who signed up on this Mac has
never been through the phone's onboarding, which is what writes it — and a PATCH
against a missing row succeeds with zero rows affected, which is a save that
silently does nothing.

`PostgRESTCoding` was extracted when this became the second store: snake_case
keys plus the variable-fractional-second timestamp fallback that plain `.iso8601`
rejects. Two copies of that would have been two places to get it wrong.

### The signed-out form is the same page, not a different one

Two shapes have now been rejected here, and they failed for opposite reasons.

The **first** was the shape a sign-in page takes when nobody opens `design.md`: a tinted
icon plate and a bold heading **inside** a card, placeholder-only inputs, a small button,
and a 「または」 rule separating it from a Google button that was sitting right underneath
anyway — all wrapped in a full-width card clamped to a 380 pt column, so half of the card
was empty. `design.md` names four of those in its Don'ts: don't title a card from inside
it when a caption above it will do, don't leave a card's width unused, carry hierarchy
with weight rather than ornament, and don't put a rule where nothing needs separating.

The **second** overcorrected into a two-column split: a marketing panel on the left
(badge, 17 pt heading, three icon-plate benefits) and the form on the right in a fixed
460 pt frame, with `ViewThatFits` stacking them at the minimum width. It read as an
advertisement bolted to a form. The two columns had no shared alignment, only one of them
held a control, the form sat pinned to 460 inside a pane more than twice that wide, and
the page changed shape completely at the instant of signing in — the pane the user was
looking at is the same アカウント page either side of that moment.

It is now **one column of the window's own settings idiom**, structurally identical to
the signed-in half above it: `ModeTabs`, a `RowGroup` of label-plus-field rows at the
page's full width with each field capped at `fieldWidth` (280, the same number 表示名
uses), the two actions, then a 「サインインすると」 group carrying the sync claims as
captioned rows with 同期 / この Mac badges — the same rows `syncSection` shows once
signed in. Nothing on the page is wider or narrower than the rest of the app, and the
claims survive the transition instead of vanishing with the left column.

The tabs are still the group's caption: a `SectionCaption` under them would say
「サインイン」 directly below a tab already reading 「サインイン」. The 240 pt field
width went with the 460 pt column that justified it.

---

## 15. First-run onboarding

`App/Onboarding/` is a dedicated, non-resizable **1080×700** window with no settings
sidebar. Its eleven steps are アカウント → 用途 → ボタン → アクセス → the pill →
書き換え → カスタム → 返信 → きっかけ → **オファー** → 完了 — ten of which the progress
rail counts. The rail deliberately does not count the offer: it counts setting the app
up, and paying for it is not a step of installation. The frame does not follow the intrinsic size of whichever step happens to be
visible: `.resizable` is absent from the style mask, the `NSHostingView` has
`sizingOptions = []`, and both `contentMinSize` and `contentMaxSize` are applied at
1080×700 after the host is installed. The order matters: the hosting view's default
`.standardBounds` reflects SwiftUI's changing measurements into the window and can
overwrite min/max values that were assigned before `contentView`.

The whole flow uses `design.md`'s dashboard system rather than a separate onboarding
theme: a `#f2f2f4` shell, one white panel inset 4 pt, a shared 920 pt content grid with
48 pt outer gutters, white cards separated by hairlines, fog-filled inputs, and indigo
only for progress, selected state and the primary action. Routine page titles stay at
20 pt. Explanatory pages use one consistent question-left / visual-right composition.
The right visual is a reusable lavender stage taken from the landing page's desktop
scene: `#efecfa → #ddd8f2 → #c8c1e8` with white light at the upper-left and `#a99ed4`
at the lower-right. It is an illustration surface, not a new window palette: controls,
cards and the surrounding panel still use `Tokens.Window`. Every glyph is Reicon except
the product mark, traffic-light circles and the official full-colour Google G.

The visual stage contains code-native, shared desktop primitives rather than screenshots:
a Mail composer with window chrome, toolbar, addressing rows and an editable body; the
production-shaped dark overlay bar; and a System Settings accessibility scene with its
sidebar, permission row and current state. Mock controls do not accept input. The custom
and reply practices' live editors, plus the reply practice's copy control, are the
deliberate live exceptions. Real permission, navigation and save actions stay in the
shared bottom shelf, so a switch or toolbar button that looks plausible never becomes a
dead competing action.

Its vertical extent is a layout invariant, not content measurement. On every split page
the stage consumes the full height offered between the progress rail and navigation
shelf, inset 10 pt at the top and bottom. Its width may change for a button editor or
choice grid, but its top and bottom edges do not jump with the mock inside it.
Explanatory columns are vertically centred against that stable stage so the two sides
carry comparable visual weight. **Every left column is centred, including the working
ones** — ボタン used to be the exception on the grounds that a list fills the region
anyway, which was only true at the largest set it allows. A column can only be centred
if it has a natural height, so the one construct that never has one, a `ScrollView`, is
capped rather than left to take everything it is offered (§15's ボタン paragraph).

After authentication, navigation is one shared 58 pt shelf pinned to the bottom of that
grid. Back stays at the left edge, skip actions are text links beside the forward action,
and exactly one filled indigo action ends at the lower-right edge. Individual steps do
not place their own Next button inside their content, so changing from a short page to a
tall one never moves the primary action or changes which control owns the hierarchy.
The signed-out account form is the deliberate exception: Google is the action that
authenticates, so it remains attached to the form rather than masquerading as page
navigation.

アカウント makes Google the primary action and progressively reveals the existing
email/password form. Its right stage keeps `OnboardingMascotLoop.mp4` as the only
generated content; the video is multiply-composited so its white field disappears into
the shared lavender scene instead of becoming a card behind the mark. There are no
generated labels, particles or button chips. The source is Higgsfield
Seedance 2.0 job `101892b2-3fdc-4a81-b054-24a8b5708091`, made from
`public/bgremoved.png` as the matching first and last frame. The prompt deliberately
asks only for a blink, glance and restrained keypress-like bounce because video models
are not trusted with readable text or exact interface geometry.

用途 offers five practical, four-button configurations: the general starter set, work,
international communication, Japanese polishing, and social/chat. The starter remains
敬語 / メール / 英訳 / 自然に and retains the four shared `builtin_key` values. The
other packs use standing context that can genuinely live on a reusable button (for
example 上司向け, 取引先, 仕事英語, 校正, LINE), not one-off message content or
gimmicks such as emoji and hashtag insertion. Existing synced buttons are a sixth choice
when present. The grid is vertically centred when all choices fit and becomes scrollable
without changing that alignment contract when they do not.

ボタン is a required confirmation page. It shows the actual bottom-bar preview and lets
the user rename, rewrite the instruction, reorder, add or delete before proceeding. The
first row is the shared `main` slot. Confirmation upserts the reviewed rows before
deleting obsolete owner rows, then fetches the server result and refreshes the overlay;
a failed second request may leave an extra row but cannot empty the account. Drafts and
the selected pack survive an unfinished close in `OnboardingProgressStore`.

Its layout is three rules, and the first one is what the other two are for. **The list is
capped at the height its rows occupy closed** — `rowHeight` (74, applied to the row rather
than assumed of it) × the count, plus the gaps — and stays flexible below that cap. That
is the only way the column has a natural height, and a natural height is the only way it
can be vertically centred like every other left column; below the cap the parent still
compresses it, so a seven-button set scrolls exactly as before. Because the cap is
computed from the *count* and not measured from the content, **opening a row cannot
resize anything outside the list**: the editor grows inside a viewport whose height did
not change, and the heading, the 追加 action and the preview column stay where they are.
The row is scrolled to the top of that viewport in the same animation, which is what
makes an expanded editor legible in a viewport it can nearly fill. The editor only fades
in; sliding it down from the row's top edge as well described one event twice while the
row was already growing. And the preview column reads nothing about the left one — it
used to flip from centred to top-aligned whenever a row opened, which moved the one thing
on screen the user had not touched.

Sign-in and Accessibility are hard gates. バー and 練習 can be skipped once both
exist. `OnboardingProgressStore.currentVersion` is persisted in `UserDefaults`;
an unfinished close saves the current step, while the menu-bar item changes from
「セットアップを続ける」 to 「使い方を見る」 after completion. A later sign-out or
revoked permission does not reset onboarding; Home's compact recovery card handles it.

The first practice is real, not a simulation. It is the first page that drops the split layout:
the heading runs above a large, full-width Mail composer, matching the interaction
reference and making the target look like a place somebody would actually write. Its
body is still the live `TextEditor`, not text painted into the mock. The real bar remains
outside the onboarding window at the screen edge; no simulated bar competes with it.
The editor carries no artificial focus ring; its content has explicit vertical inset so
the first line clears the Mail body's top edge rather than clipping against it.
`OverlayController.beginTutorial` exposes every reviewed button (with the old 敬語
tutorial prompt only as a defensive fallback when there are none), while
`OnboardingPracticeSample` selects a draft from the main button's builtin key, title and
instruction so 英訳, 校正, 社内チャット and other reviewed main buttons receive a
matching input rather than the old 敬語-only sentence. It then
captures the focused training editor, calls `desktop-rewrite`, presents the production
result card, and completes only after Insert writes successfully. The sample rewrite
never enters local history or statistics. The window does not resize or extend toward
the overlay for this step: a compact instruction points below the window to the real
screen-edge bar and names the actual tutorial button. On a successful Insert, the
result panel is dismissed before the completion callback runs, then the onboarding
window is made key again. Its editor is also the only production AX target owned by this
process: a same-process selected-range setter enters AppKit directly and must run on
`MainActor`, while every ordinary cross-process AX write stays on `AXTextIO`'s actor.

カスタム is a second full-width Mail practice with the focused live editor and the real
screen-edge overlay. Its draft asks to move a 15:00 client meeting because the materials
will not be ready, and the suggested one-off guidance asks for a concise client email
that opens with an apology. The instructions identify the rightmost ✎ as the place for
one-off directions. `beginCustomTutorial` marks only ✎ submissions as tutorial work:
saved buttons may still run but cannot complete the page, blank guidance cannot submit,
generation never reaches local history/statistics, and only a successful Insert clears
the tutorial and restores the onboarding window.

返信 is a third real practice page, not a tour card. Its Slack-style scene has a live
copy action and a live empty composer. The copy is placed on the pasteboard and explicitly
armed through the production reply state so the lesson still works when a replaying user
has disabled clipboard watching; from `.replyArmed` onward it is the same hover, capture,
free-text instruction, generation, result and Insert path as §16. The reply rewrite is
marked as a tutorial, so it neither enters history nor increments local statistics, and
the page completes only after the same-process AX write succeeds. `replyPractice` remains
raw value 7, `complete` remains 6, and `customPractice` is appended at 8;
`DesktopOnboardingStep.flow` owns their visual order and Back navigation without
invalidating unfinished saved steps. `currentVersion` remains 2, so completed users reach
the expanded lesson through 「使い方を見る」 rather than being forced through first run.

きっかけ was the only page that asks for something instead of teaching something, and it
sits **third from last**: 完了 hands the app over, and nothing should be asked after that.
It reuses 用途's composition exactly — question left, choice grid on the lavender stage,
the same card metrics and selection dot — because a survey that invents its own layout
reads as a different product's page. Eight options: X, YouTube, Instagram and TikTok
carry their real App Store artwork, and Web検索 / 知人にすすめられて / 記事・ブログ /
その他 are Reicon on a plate, the same full-colour-beside-Reicon pairing the sign-in
page already makes with the official Google G. The artwork is bundled
(`Assets.xcassets/Source*`), not fetched: this page must draw offline, and a survey is
not a reason to make a network call. It is delivered square, so the superellipse mask is
applied in `SourceMark` rather than baked into an asset that would then be wrong at
another size. **These are third-party trademarks, shown to identify the channel and for
nothing else.**

It is a question, not a gate: 「答えない」 sits beside 「次へ」, moves on without sending
anything, so a skipped run is absent from the series rather than a guess inside it.
`OnboardingSource.rawValue` is the wire key and is pinned by a test — a rename splits an
attribution series with nothing in the data to show it happened — while `label` is free
to be reworded. `desktop_source_selected` carries `source` plus a `$set_once`
`attribution_source` person property (`docs/analytics.md` §3), and a replay sends nothing
at all. `source` is appended at raw value 9, so an unfinished saved step still resolves,
and `currentVersion` stays 2: users who finished before this page existed are not asked.

### オファー — the one page that asks for money

Between きっかけ and 完了, at raw value **11**. The position is the whole design: it comes
**after** the three practices, because the argument for paying is that the user has just
watched their own text rewritten in their own apps, and **before** 完了, because 完了
hands the app over and an ask bolted onto the end of a finished flow is an interruption.

**33 % off the first period, for 72 hours** — ¥9,600 / $80 a first year, ¥980 / $8 a
month for three, then list. `docs/pricing.md` §1 owns the numbers and `docs/billing.md`
§2 owns the mechanics; three things about the page belong here:

- **The deadline is real, and that is what licenses saying it.** It is minted by
  `desktop_start_welcome_offer()` and enforced by `desktop-checkout` against the same
  row, so there is no countdown the client could keep alive. `desktop.welcome_offers` is
  primary-keyed on `user_id` and its rows are **never deleted** — not on expiry, not on
  redemption, and there is deliberately no GC job — because that is the only thing
  making "once per account" survive a reinstall or a second Mac. A deliberately
  unenforced deadline would be a 景表法 有利誤認 claim rather than a design choice, and
  the struck-through list price beside the offer is defensible for the same reason: it
  is the price this same account pays from the second period on.
- **Each card states what it renews at.** 特商法第12条の6 ①分量 and ②対価 — the amount,
  that it covers the first period only, the price afterwards, and that it renews
  automatically. A discounted first period without the second number is half a price.
- **Declining costs nothing.** 「あとで」 moves to 完了 and a ホーム card carries the same
  price and the same remaining time until the window closes. An offer that vanished
  with the page it was made on would be a deadline of about four seconds. Once Checkout
  has been opened the secondary action re-reads 「次へ」 rather than 「あとで」: someone who
  has already gone to pay is not declining, and the payment finishes out of band so
  there is no result to wait for.

The page is skipped entirely — straight to 完了, nothing written — for a user who is
already Pro, for a replaying user, and for any account the server refuses. A network
failure is treated as a refusal for the same reason: the failure mode is a user who
finishes setup without seeing an offer, and the alternative is a page showing a price
checkout will not honour. `currentVersion` stays **2**, so nobody who has already
finished first run is replayed into it.

---

## 16. Reply mode

Copy a message, go to where you are answering it, hover the bar: it opens an input box
for *how* you want to reply, and the rewrite comes back as the reply. Two new
`OverlayState` cases, one clipboard poll, and one flag on the AX capture. Everything
from the generating capsule onward is §4 unchanged.

`desktop-rewrite` selects the reply branch from `replyTo`, as it always has, but reply
prompt construction now lives in the pure, tested `prompt.ts`. The three fields mean:

| Field | Reply mode | Everywhere else |
|---|---|---|
| `replyTo` | the copied message. **The only thing that selects the reply branch** | nil |
| `text` | the user's optional existing draft in `<existing_draft>` — usually `""` | the text being rewritten |
| `prompt` | guidance in `<reply_guidance>`: facts, stance, answers, keywords or style, not necessarily prose to repeat | the button's prompt |

`text` being empty is not a degenerate case, it is the normal one, and it is why
`ContractTests` pins both `replyTo` going over the wire and its default staying nil:
losing the key does not fail loudly, it silently rewrites an empty string.

The copied text is escaped inside `<received_message>` and is untrusted context, never a
source of instructions. A reply must acknowledge and answer it where the user's facts
permit, integrate fragments into coherent prose, and return a complete sendable body.
The host app and sender tone are hints: professional and context-aware is the default,
while an explicit style request wins. Every user-supplied fact, reason, answer, decision
and commitment is preserved; availability, dates, reasons, names, decisions and promises
must never be invented. When both the existing draft and guidance provide no stance, the
fallback acknowledges the message without accepting, declining, promising action or
choosing availability for the user. Normal rewrite prompt construction is unchanged.

### ⌘C is the trigger, and selection is not

`ClipboardWatcher` polls `NSPasteboard.general.changeCount` every 0.5 s. `NSPasteboard`
posts no notification of any kind, so sampling is not a shortcut — it is the only
mechanism, the same way `DockProbe` is sampled in §4.

**Selection was considered and rejected, on a structural ground rather than a cost one.**
`AXTextIO.target(for:)` already treats a non-empty `kAXSelectedText` as `.selection` —
the thing to *rewrite*. Arming reply mode on the same gesture would give one selection
two contradictory readings and leave the bar unable to say which it meant. The cost is
also real (an `AXObserver` per process, re-registered on every app switch, firing on
every caret move, and unreliable in Chromium and Electron web content), but the
ambiguity is what settles it. ⌘C is explicit, works where AX does not, and is one
integer compare.

### Our own pasteboard traffic is indistinguishable from a ⌘C

The app touches the pasteboard in five places, and `changeCount` cannot tell any of them
from a user copy. Untracked, the worst of them — the insert-failure recovery and the
結果 copy button — would arm reply mode with the rewrite the app had just produced and
offer to compose a reply to it.

`ClipboardWatcher.suspend()` / `resume()` bracket all five: the fallback capture in
`press`, `pressCustomInput` and `beginReplyInput` (which clears and restores the
pasteboard around a synthesized ⌘C — three bumps), the write in `insert`, and the two
synchronous writes via `writingOurselves`. **Each is balanced by a `resume()` in its
`catch`.** The depth counter alone is not enough and the `lastSelfChangeCount` snapshot
is not redundant: `copyToClipboard` suspends, writes and resumes synchronously, so no
poll ever observes a non-zero depth and the bump would surface one tick later looking
exactly like a copy.

The suppression is `static`, because `MainModel.copy` writes to the same pasteboard from
the other side of the app.

### An empty compose box is the main path, and it failed capture

`AXTextIO` threw `.noTarget` on a readable-but-blank field. "Copy a message, click into
the empty reply box, hover" is the *central* reply flow, so that was not an edge case —
it was the feature never working. `capture(frontmostPID:allowEmpty:)` accepts
`kAXValue != nil` instead of non-blank, and only reply mode passes `true`.

A **nil** `kAXValue` still throws, and that is load-bearing: it is the only thing
distinguishing "empty text field" from "no text field", and therefore the only thing
keeping a ⌘A + ⌘V out of the Finder.

### Capture happens on hover, because that is the last moment it can

The input box takes key, so by the time anything is typed `AXFocusedUIElement` is our
own field — the same reason `pressCustomInput` captures on the press (§4). Hover is the
last instant the user's app still owns focus.

Two consequences:

- `replyCaptureInFlight` guards it. Hover fires again on re-entry and the capture is a
  cross-process AX call, so a cursor jittering on the bar's edge would otherwise start
  several.
- A capture failure toasts **once per armed copy** (`warnedNoReplyTarget`). Hover is
  passive; a message on every pass of the cursor over the bar would be worse than the
  missing field it reports.

### The rest of the state machine

`.replyArmed` is a **parallel resting state**, not a sixth step: it stands in for
`.pill` while a copy is live, and hovering it goes straight to `.replyInput` where
hovering the pill goes to `.hoverRow`.

- `armReply` only fires from `.pill` or `.replyArmed`. Arming over an open input bar, a
  running rewrite or a result card would replace something the user is in the middle of.
- Escape from `.replyInput` returns to `.replyArmed`, not `.pill` — the copy is still
  live and discarding it means copying again. Deliberately **without** §4's
  cursor-still-over-the-bar courtesy: `.replyArmed` is the state hover opens the input
  box from, so re-opening it under a stationary cursor is a loop Escape cannot break.
- `PendingRewrite.replyTo` is carried rather than read off the state, because ↻
  regenerates from `pending` alone. Dropping it would turn a regenerated reply into a
  rewrite of the user's draft — for the usual empty box, a rewrite of nothing.
- History records `replyTo` as `originalText`. The user's draft is the honest "before"
  for a rewrite and a blank for a reply, and 「返信」 as the button title keeps the row
  out of the ✎ rewrites it is not.
- Expiry (`ReplySource.lifetime`, 180 s) only disarms from `.replyArmed`. Past
  `.replyInput` the copy is in use and the clock stops mattering.
- The watcher stops when the bar is hidden. Watching while hidden would arm a state with
  no window to show it in, then surface a minutes-old copy the moment the bar returned.

### The threshold is set by Japanese, and it is the one filter

`ReplySource.minimumCharacters` is **12**, not the 20 first tried:
「明日の打ち合わせは大丈夫でしょうか。」 is 18 characters and an entirely ordinary message
to reply to. Japanese runs at roughly twice the information density of English per
character, so a threshold eyeballed against ASCII noise silently excludes the real
cases — which is the failure that matters.

The price is known and pinned by `testLongNonMessageCopyStillArms`: a copied URL or
path over 12 characters arms the bar. ✕ is the answer. Filtering it properly means
guessing at the *shape* of the text, and a rule that silently declines is far harder to
explain than a bar that occasionally appears when it need not have.

`ReplySource` is pure and lives in `DesktopRewriteKit` for that reason — `ClipboardWatcher`
needs a real pasteboard and a runloop, so everything that *decides* is tested instead.

### The message is a second window, up the whole time

**Two wrong cuts preceded this, and both are worth knowing because both looked right.**

The first put the copied message *in* the `.replyArmed` bar and nowhere else. The only
way to reach the input box is to hover, and hovering replaces the bar with the input
box — so the message was legible in the one state where there was nothing to do with it
and gone in the state where you were writing against it.

The second added `ReplyContextPanel` but scoped it to `.replyInput`, leaving the armed
bar's preview in place. That was still wrong in the same direction and it shipped two
visible bugs, which had **one cause between them**: `applyMeasuredSize` returns early
when the measurement has not changed, so the hover into the composer frequently never
called `resize` — and `resize` was the only thing that re-derived the card's position.
The card stayed pinned to where the *armed* bar's top edge had been, the taller input
bar grew up through it, and it appeared to "only work once you start typing", because
typing changed the measured width and finally triggered a resize.

Now: **the card is up from the moment a copy arms**, spanning `.replyArmed` and
`.replyInput`, and the bar underneath carries no copy of the message at all — only a
返信 badge saying what hovering will do. One rendering, one owner, and the handover that
used to flicker no longer exists because nothing is handed over.

`OverlayState.replySource` is what makes that one question instead of two.

**A second window rather than more rows inside the bar.** The bar is a capsule sized
exactly to its content (§4), so a four-line message inside it is a 120 pt lozenge, and
the input bar's fixed 360 pt width exists for a reason a message body does not share.
`ErrorPanel` is the exact precedent — the one other thing that stacks above the bar
while the bar is still visible and still key — and `ResultPanel` supplies the
measure-then-clamp-then-scroll contract the body uses.

### The height had to be a constant, and that is the third correction

The card was a measured two-row block, and it overlapped the bar on screen. **The cause
is already written down in this file's own codebase** — `ErrorPanel` carries it:

> *"with an unbounded measurement the window went to 721 pt, and a 721 pt window
> anchored near the bottom of the screen puts its bottom-aligned card 653 pt below the
> display."*

`ErrorPanel` was fixed with `errorToastMinHeight` / `errorToastMaxHeight`. The context
card was written afterwards, against the *pre-fix* version of that file, and inherited
the same unbounded `applyContentHeight`. The mechanism: an inflated measurement makes
the window taller than the space above the bar, `clampToWorkArea` slides that window
**down** to keep it on screen, and because the content is bottom-aligned inside it the
card draws lower than its own anchor — on top of the bar.

It is now **one line at `replyContextHeight` (30 pt)**: icon, the message in italic,
✕. No measurement at all, so the position is a pure function of the bar's frame and a
30 pt window can never trigger the downward clamp. The two-row card, its `ScrollView`,
its overflow fade and both of its preference keys are gone.

Checked by hand rather than by eye, because eye is what got this wrong twice: armed bar
spans `[minY+6, minY+40]`, pill sits at `minY+48`, gap 8 — the same 8 `ErrorPanel` uses.

The cost is that a long message is truncated rather than scrolled. `replyTo` still
carries the full text; only the display is cut. `contextText` also **flattens** newlines
now, because `lineLimit(1)` on its own cuts at the first one — and the messages worth
replying to open with a greeting, so that is the line it would have shown.

Five things about it are load-bearing:

1. **A constant height, per the above.** Anything that reintroduces a measured height
   here reintroduces the overlap.
2. **Never key.** `panelResignedKey` cancels the composer when `PillPanel` loses key, so
   a pill that could take focus would close the input bar the moment anyone clicked the
   message they were reading. `canBecomeKey` returns false, so AppKit leaves key where
   it is and the click is inert. The ✕ is safe for the same reason: `dismissReply` lands
   on `.pill`, so the resign it causes finds a state `cancelInput` ignores.
3. **It follows the bar.** The input bar wraps to `inputBarMaxLines` as the user types,
   so the thing the pill sits on gets taller *during* composition. Every `setFrame` on
   the bar goes through `resize`, which re-anchors first — against the **target** frame,
   not the current one, or the pill would be grown into by the second line for the
   length of the 0.16 s animation. `persistPosition` re-anchors too, and so does
   `applyMeasuredSize`'s **early return** — see the comment there, it is the exact hole
   that produced the first two rounds of this bug. **The one gap left is mid-drag**:
   `isMovableByWindowBackground` moves the window without going through `resize`, so the
   pill catches up on mouseUp rather than following the pointer.
4. **`setVisible(false)` takes it down by hand.** That path assigns `state` directly
   instead of calling `transition`, so the sync that normally owns the pill never runs.
5. **The error toast stacks above it**, not under it — `showErrorToast`'s anchor chain
   gained `replyContextPanel?.frame`.

The card goes away for `.generating` and `.result`: the capsule and the result panel
replace the bar rather than stacking on it (§4), and a 440 pt result card with a message
card above it runs off the top of a short display. Whether the original should be
visible while judging the reply is open.

### One rendering of the message

`ReplySource.contextText` is the only place the copied message is drawn. There used to
be a second — a single-line preview inside the armed bar — and deleting it went with the
pill becoming permanent: two renderings of one string meant truncating it at two
different widths and keeping both in step for no gain.

`contextCharacters` (500) is the only bound on it, and it exists so SwiftUI is never
handed a 10,000-character string to lay out; the visible truncation is the pill's width
and `truncationMode(.tail)`. Neither touches the wire payload — `replyTo` carries the
full text and `desktop-rewrite` has its own limit, which is also why the flattening
happens in `contextText` and not in `text`.

### 返信モード is a switch, on by default

It works by watching what the user copies, which is worth saying out loud rather than
burying — the same reasoning as 履歴を保存する (§14). `ClipboardWatcher.isEnabled` is
consulted on every poll, so `MainModel` needs no wiring to the overlay it does not own.

### Not verified

`swift test` passes 103 tests, `xcodebuild` succeeds, and six Deno prompt tests plus
`deno check` / `deno lint` pass, with no new warnings. `desktop-rewrite` v9 is ACTIVE
with `verify_jwt = true`; the downloaded deployed source matches local hashes, and the
six authenticated quality cases described at the top of this file passed.

**Every correction in this section came from the owner running it, none from reading
code — that is the pattern to expect here, and it is worth taking literally.** The
overlap in particular was diagnosable from a file already in this repo (`ErrorPanel`'s
own comment describes the exact failure) and was instead reasoned about twice from the
creation path, which looked correct and was. The measured height was the problem, two
call sites downstream. When something in the overlay is mispositioned, read what the
other panels had to fix before theorising about this one.

Still unwatched by anyone: the ten-step onboarding window, both real custom/reply Insert
paths, the one-line reply pill, the gap holding as the input bar wraps to a second line,
an empty-field capture in a real Mail or Slack compose box, and the write of a composed
reply. `scripts/axdiag.swift` is the tool for the last.

### Open — the primary flow pays for this

**While a copy is armed, the user's own buttons are unreachable without pressing ✕.**
Hover opens the input box, which is what §16 is for and what was asked for, but for up
to 180 seconds it is also the only thing hover does. The ✕ is on the context card, which
is on screen for both reply states — so it is one click from either, which is as far as
this can be taken without contradicting "hovering just opens the input box". Whether
that is enough is a question for a running build, not for this file.

---

## 17. Three languages

日本語, English and 简体中文, across the overlay, the window, first run and the
landing page. Two questions are kept apart throughout, and almost everything here
follows from the split:

- **The interface language** — what the user reads.
- **The writing language** — what their buttons produce.

They are the same question for Japanese and for English. They are *not* the same
question for Chinese: a 简体中文 user is assumed to be **a Chinese speaker working
in Japan**, so the interface is Chinese and the buttons still write Japanese.
`AppLanguage.writesJapanese` is that fact and it is the only place it is decided;
nothing else in the app branches on the raw language.

| | interface | buttons write | billed in | packs offered |
|---|---|---|---|---|
| 日本語 | Japanese | Japanese | ¥1,480 / ¥14,400 | 定番 / 仕事 / 海外 / 日本語 / SNS |
| English | English | English | **$12 / $120** | Starter / Work / Outreach / Polish / Social |
| 简体中文 | Chinese | **Japanese** | **¥1,480 / ¥14,400** | the Japanese five, unchanged |

The third column was added on 2026-08-10 and it splits the same way the second does,
for the same reason: 简体中文 is a Chinese speaker working in Japan, so their card is
a Japanese card. `BillingCurrency.forInterface` is that fact, and it sits beside
`writesJapanese` as the second — and, so far, last — thing the raw language decides.
**One asymmetry worth knowing:** the writing language is a request field, so it can be
wrong and be corrected on the next rewrite. The currency is fixed at subscription
creation and cannot be changed at all, which is why an existing subscription's
currency outranks the interface language everywhere it is quoted.

### `tr(ja, en, zh)`, and why it is not a String Catalog

Every user-visible string is three literals at its point of use:

```swift
Text(tr("ホーム", "Home", "主页"))
```

**The failure mode this is chosen against is drift, not tooling.** The Japanese
copy in this app is reworded constantly — most entries at the top of this file are
a rewording — and both standard shapes lose the other two languages when it
happens. A Japanese-keyed `.xcstrings` orphans the entry. A symbolic key is worse:
`en` and `zh` keep a translation of a sentence that no longer exists, silently, in
a JSON file nobody opens during the edit. Colocation makes that impossible by
accident: rewording the Japanese means looking at the other two.

The other half is runtime switching. §15's language page has to take effect on
itself, and `String(localized:)` ignores SwiftUI's environment locale — it reads
`Bundle.main` — so a catalog would need a bundle swizzle *plus* a second mechanism
for the SPM package's own strings. `tr` has one mechanism for both targets.

The cost is real and worth stating: no extraction, no translator hand-off, and
three languages is the point at which the argument still holds. A fourth language,
or a vendor in the loop, is when `tr` should be replaced — and it is one function.

- `AppLanguageState.current` is a lock-guarded global, because `tr` is called from
  view bodies, from AppKit callbacks and from pure model code in `DesktopRewriteKit`.
- `AppLanguageStore` persists the choice in `UserDefaults`, **per Mac**. A
  `language` column on `profiles` would be a migration in a project the iOS app
  shares (§12), so this stays local by decision.
- `activate()` runs in `applicationDidFinishLaunching` **before any window, menu or
  view exists**. Anything built ahead of it is built in the wrong language.
- Static `let`s holding a `tr` are a bug: a stored static is evaluated once and
  cached, so it keeps whichever language the app started in.
  `OnboardingCoordinator.fallbackTutorialPrompt` and
  `OverlayController.resetFormatter` are `var`s for that reason.

### What a language change has to reach

Three surfaces cannot observe a global on their own, and each needs its own push:

| Surface | Mechanism |
|---|---|
| Onboarding | `@Published language` on the coordinator + `.id(coordinator.language)` on the panel |
| Overlay (three separate windows) | `OverlayController.languageChanged()` → `objectWillChange.send()`; the bar's width follows on its own, because the row reports its measured width up through a preference (§4) |
| Menu bar and main menu | `AppDelegate.relabelForLanguage()` rebuilds both. They are AppKit objects built once at launch and are outside every SwiftUI observation graph |

`MainModel.languageChanged()` is the one entry point, and it also re-registers the
PostHog super properties — a super property is stored, not computed, so it keeps
its value until it is registered again (the same reason §7 re-registers the surface
after a sign-out).

### The language page

`DesktopOnboardingStep.language` is raw value **10** and sits **first** in `flow`.
Raw values stay append-only so an unfinished saved run still resolves; the array
owns the order. `currentVersion` stays **2**, which means users who finished
onboarding before this page existed are never asked — the ⚙︎ 一般 row is the whole
answer for them, and that is why it exists.

- It is preselected from `Locale.preferredLanguages` and is still a question. A
  preselection is not a choice, which is why `AppLanguageStore.stored` is nil until
  answered and `resolved` falls back separately.
- **`OnboardingProgressStore.savedStep` had to change with it.** With nothing saved
  it answered `.welcome`, which was right only while `.welcome` was also the head of
  `flow` — so a brand-new install, the one user this page exists for, would have
  skipped it. It now returns `flow.first`. A *corrupt* value still falls back to
  `.welcome`: that is a recovery path, and re-asking a language already chosen is
  the wrong repair.
- The choice **applies on click, not on 続ける**. This is the one page where the
  effect of the choice is visible, so applying it late would leave the user no way
  to check they picked the right one.
- Option labels are **endonyms and are never translated**. A picker that renames
  日本語 to "Japanese" in an English interface is unusable by the one person who
  needs it. The captions are written in the language of their own row for the same
  reason.
- It has **no progress-rail segment**. The rail is 10 setting-up steps; the
  language question is asked before setting up starts, and counting it would tell
  someone they are 9 % done for having said which language they read. The rail is
  hidden with `.opacity(0)` rather than removed, because the window cannot resize
  and dropping it would move every page for one step and back again.

### English is a different product surface, not a translated one

敬語 has no English counterpart: the register a Japanese user needs a button for is
grammatical, and the equivalent English problem is tone, length and correctness. So
the starter pack's four axes replace the four honorific levels — **Polite / Email /
Shorten / Proofread**: how it sounds, what shape it takes, how long it is, whether
it is right. The other four packs are Work, Outreach, Polish and Social.

Two things about those packs are load-bearing:

1. **Titles are nine characters or fewer.** The hover row has *no overflow
   handling* (§4) — it is intrinsically sized and simply gets wider. Nine characters
   keeps a four-button English row within a few points of a Japanese one, and
   `testEnglishButtonTitlesStayShortEnoughForTheHoverRow` pins it.
2. **Polite and Email keep their `builtin_key`s.** `handle_new_user()` seeds every
   account with all four keys and `user_prompts_user_builtin_unique` makes a key an
   *identity* (§6), so an English pack claiming none of them would leave the seeded
   Japanese rows to be deleted and re-created rather than reused.

`outreach` and `polish` exist only in English; the Japanese branch resolves them to
the nearest pack that does exist there, so a pack saved before a language change
still yields four buttons rather than an empty list.

**The practice drafts are wrong on purpose.** Each English sample carries the defect
its button fixes — blunt for Polite, padded for Shorten, misspelled for Proofread,
translated-sounding for Natural. A clean sample ends the lesson with a rewrite
indistinguishable from the input.

### `writingLanguage` on the wire

`desktop-rewrite`'s system prompt opened with *"You are a Japanese writing
assistant on macOS."* That is not a claim about the output language — 英訳 has
always returned English — it is a claim about whose writing this is, and for an
English user it biases register, punctuation and sentence length toward Japanese
conventions on text that has none.

`RewriteRequest.writingLanguage` (`"ja"` | `"en"`, optional) now selects it, and
**absent is meaningful**: every installed build older than the field omits it and
those users are Japanese, so `undefined` reproduces the original string exactly
rather than falling into a neutral branch. A 简体中文 user sends `"ja"`.

**iOS cannot be affected by any of this.** The keyboard is on `keyboard-rewrite`
(v42), a different function that was not touched — the isolation is structural, not
a matter of care. The reply branch is language-neutral and is deliberately left
alone; four Deno tests pin the default, both English branches and the reply branch's
independence.

### The landing page — and it is **not** in this repository

**The production site is `../web`**: a Next.js 16 app on Vercel at
`keigobutton.com`. `landing/` here was its *prototype*, and `web/components/mac/`
is a fork of it — `Problem.jsx` and `useReveal.jsx` were byte-identical. A round of
localization was done against the prototype before that was noticed, which is the
whole argument against keeping two copies of one page; the prototype's code is now
deleted and its copy deck lives at `web/components/mac/docs/content.md`, beside the
five files that cite it. Only `landing/landing_reference/` (10 MB of design
screenshots, nothing citing it) is left here.

What follows describes the port, which lives in `../web`.

Three routes rather than three builds. `/` stays Japanese and **unprefixed** — every
indexed URL on that site is unprefixed Japanese, and `/keigo-henkan` and `/reibun/*`
are the pages that rank — so `/en` and `/zh` were added beside it rather than moving
anything. Next's own i18n guide nests every locale including the default, which
would have renamed every ranking URL; that is the one place this deliberately
departs from the framework's documented pattern.

- `hreflang` is emitted **self-referencing and symmetric** on all three, plus
  `x-default` → the Japanese root. Those three properties are what make the set
  valid; drop one and Google ignores the whole thing. `lib/alternates.ts` is the only
  place it is built, so a page cannot be annotated in one direction and forgotten in
  the other — and `SPINE_PATHS`, which feeds the sitemap, holds only paths that exist
  in **all three** languages. A path added there before its routes exist puts a 404
  in the sitemap, which is worse than the page being missing because it is a claim.
- **The scope is the product spine, not the site.** `/keigo-henkan`, `/keigo-check`,
  `/keigo-test`, `/reibun/*` and `/blog/*` exist to rank for Japanese queries —
  「敬語 例文」 has no English search behind it — so they stay Japanese-only, carry no
  `hreflang`, and are dropped from the English and Chinese navigation rather than
  linked with a translated label to a Japanese page.
- **`<html lang>` is the one compromise.** Setting it per route needs multiple root
  layouts, and the docs are explicit that those require *no* top-level `layout.tsx`
  — moving all thirteen route folders in the live repo to change one attribute. The
  localized subtree is wrapped in a server-rendered `<div lang>` instead, which is
  what assistive technology actually reads, with a client effect correcting the root
  element. The route-group move is the upgrade path and nothing blocks it.
- **No automatic redirect by `Accept-Language`.** Google advises against it, and it
  is wrong for real people often enough — a VPN, a work laptop set to English.
  `LocaleBanner` offers the match once, links rather than redirects, and remembers
  being dismissed. The nav's language links are the primary control and are real
  `<a href>`s, so they work before JavaScript does.
- The **zh build loads Noto Sans SC** ahead of JP. 汉字 shared with Japanese have
  different regional glyph forms, and a Japanese font draws the Japanese ones —
  legible to a Chinese reader, but visibly the wrong shapes. JP stays behind it
  because the Chinese page still shows Japanese text inside the product mockups.
- **Amounts change with the language, for English only — and the original reasoning
  is why, not an exception to it.** The rule used to read "amounts never change with
  the language", because a converted figure on the page would not have been the figure
  at the card. Since 2026-08-10 the app charges **$12 / $120** to anyone reading it in
  English, so on `/en` the yen figure is the one that would not match the card. `/` and
  `/zh` are unchanged: 简体中文 is billed in yen for §17's own reason.
  `components/mac/data/pricing.js` holds a `PRICE.jpy` / `PRICE.usd` table and a
  `currencyFor(lang)` that mirrors the app's `BillingCurrency.forInterface` — **the two
  are one rule kept in two repositories, and they have to agree or the page quotes a
  price checkout will not honour.** `app/legal/page.tsx` carries the USD amounts too:
  a 特商法 販売価格 disclosure listing only yen understates what an English buyer pays.
- **The English route is set one weight step lighter than the other two**, and it is
  a typographic fact rather than a preference: latin letterforms at a given numeric
  weight read heavier than the CJK glyphs beside them. `[lang='en'] .mac-landing`
  shifts the whole scale to 300/400/500/600 against 400/500/600/700, with the 48px
  display line and the 40px section headings taking a second step to 300 and their
  negative tracking eased — tight letter-spacing exists to close the gaps a bold face
  opens, and left alone under a light face it reads as cramped. **Inter's 300 has to
  stay in `app/layout.tsx`'s weight list**: an unloaded weight is not rounded down to
  the nearest loaded one, it is synthesised from 400 and looks exactly like 400.
  Japanese and Chinese are deliberately excluded — their glyphs pack far more strokes
  into the same em box, and at 300 a 16px kanji starts losing the strokes that
  distinguish it, which is the same asymmetry `opticalNudge` below records.
- `FeatureGrid`, `Continuity`, `Privacy` and `FinalCta` were cut from the page
  before the port and do not exist in `web/components/mac/`. Their source is in
  `content.md`; bringing one back is now also a translation job.
- **One correction was made that is not localization.** `Pricing.jsx` said
  「価格はすべて税込みです」. `docs/billing.md` §10 records that Core7 is a 免税事業者
  and not an 適格請求書発行事業者, so a 消費税 claim is not ours to make — and
  消費税法第63条's 総額表示義務 excludes 免税事業者 by the text of the article, so
  nothing required the word either. The app's own plan card and this file have said
  so since 2026-08-08; the site was the last place still making the claim, and it now
  carries the same sentence the app does.

**Looking at it locally:** `cd ../web && npm run dev`, then
`http://localhost:3000/`, `/en` and `/zh` — **port 3000, and all three languages
from one server**, because they are routes rather than builds. No trailing slash:
`trailingSlash` is at its Next default, so `/en` is canonical and `/en/` 308s to it.

### `opticalNudge` was checked and deliberately left alone

§14 item 5's −1.5 pt was measured on **Japanese** line boxes, so English was an open
question rather than a known-good. It is now measured — `scripts/opticalprobe.swift`,
which reports ink centre against line-box centre per language, per size, per weight.
Read its *differences*, not its absolutes: it uses the font's ascender+descender box
where §14 used `ImageRenderer` on the real view, and the two are offset by a constant
that cancels between languages at the same size.

At 14 pt / medium, against Japanese: **简体中文 differs by 0.04 pt** — the same
constant, no question. **English differs by 0.47 pt**, which would make its correction
about 1.0 rather than 1.5.

It is still not split, and the reason is in the same output: **the spread between
English words is larger than the correction.** `Home`, `Buttons` and `Account` all
measure −0.43; `History` and `Settings` measure −1.29 and −1.30, because a descender
drops the ink box. So a per-language English constant would be right for half the
labels and wrong by more than the correction for the other half — false precision, and
0.5 pt is at the edge of visible anyway. Japanese and Chinese do not have this problem:
their glyphs fill a consistent em box, which is why one constant works there.

**If an English label does look off against its icon, this is the paragraph to reread**
— the fix is a per-string nudge or an ink-aligned container, not a fourth constant.

### Word order is a layout problem, and it was the real work

Japanese wraps the product's own bar mid-sentence — 「画面下の ⟨bar⟩ が待っています」,
「バーのプレビュー」 — and English cannot. `PillSentence` (onboarding) and
`hoverSentenceBefore` / `After` (ホーム) take a translatable string on **each** side
of the pill, and an empty side is *omitted* rather than laid out: an empty `Text`
still takes the `HStack`'s spacing and leaves a gap beside the pill that nothing in
the copy explains.

### Not verified

`swift test` passes **121 tests** (16 new), `xcodebuild` succeeds with no new
warnings, ten Deno prompt tests plus `deno check` / `deno lint` are clean, and all
three landing builds succeed with correct `hreflang`, `og:locale` and font sets in
the emitted HTML.

**Nothing has been looked at on screen, and this is the change where that matters
most.** English is roughly 1.5–2× wider than Japanese for the same sentence, and
the surfaces it lands on are fixed: the onboarding window is **1080×700 and cannot
resize**, the error toast is 360 pt wide with a clamped height, the input bar is a
fixed 360, and ボタン's list viewport is capped at `rowHeight` (74) × the row count
(§15) — a wrapped English title in a closed row breaks that assumption directly.
`desktop-rewrite` **v10 is ACTIVE with `verify_jwt = true`** and carries the
`writingLanguage` branch. Its ten prompt tests, `deno check` and `deno lint` are clean,
and the deployed gateway still returns 401 without a JWT.

The **Accessibility prompt and the Finder name are the one seam** — macOS draws them
from the bundle, so they follow `InfoPlist.strings` picked by the *system* language,
not by the language chosen on §15's page. An English macOS running the app in
Japanese sees an English permission dialog. That is the correct trade and there is no
mechanism that would do better without forcing `AppleLanguages`, which would drag
every system-drawn control with it.

Open, and a decision rather than a bug: `user_prompts` is shared with the phone
(§2), so an English user's English button titles appear in the iOS keyboard.
