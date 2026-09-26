# 0.1.11 release preparation

Draft prepared from `codex/redesign-multiple-buttons` at `9435456` **plus the current
uncommitted product work**, compared with published `v0.1.10`. Version 0.1.11 is a
proposal, not a reserved tag or published release. This document supersedes the old
shared-phone-storage and no-backend-change assumptions in the separation report.

User-facing GitHub/Sparkle copy: [0.1.11 notes](../../releases/0.1.11.md). The same
three language sections are consumed by the existing feed localizer. The notes avoid
claiming measured output improvements from authored examples or promising every user
will see the startup animation after an update.

## Complete product scope

| Area | Include in the candidate | Evidence / source |
|---|---|---|
| First launch | Cinematic mascot introduction, stable two-message composition, landing at the real bar, localized guidance, Escape/interruption handling, static/fade fallbacks | `App/Onboarding/OnboardingIntroController.swift`, `OnboardingIntroPanel.swift`, `IntroCharacterView.swift`; `Sources/DesktopRewriteKit/Onboarding/OnboardingIntroSequence.swift`; intro-composition and installer-and-intro-localization reports |
| Main design | Aside dashboard/settings/onboarding, blue app identity, new installer; bundled artwork including AsidePink/Blue/Orange | `App/Design`, `App/Main`, `App/Resources`, `scripts/release/create-dmg.sh` |
| Placement | Four drag-to-snap destinations, Dock/notch/display anchoring, inward results and errors, smoked glass | `App/Overlay`; edge-attached-panels report |
| Multiple buttons | Enabled saved order, measured content-sized scroll regions, narrow side columns, single-line ellipsis and full-name hover help, independent Reply and pencil | `OverlayController.swift`, `PillRootView.swift`; includes newer measured sizing changes after `7a107f2` |
| Button editor | Shared name/instruction controls, explicit Save/Cancel, draft protection, add/delete/visibility, native drag reordering with autoscroll and accessible move controls | `ButtonsView.swift`, new `SavedButtonReorderList.swift`, `Components.swift`, `UserPromptOrder.swift`; button-editor-refinement and button-drag-reordering reports |
| Setup | Everyday, Work messages, Friends and social; four buttons each; preview examples, review/edit; account-owned drafts, retry, returning-account preservation and read-only tutorial replay | `ButtonSetupSteps.swift`, `OnboardingPresetCatalog.swift`, `OnboardingProgressStore.swift`, new `LegacyOnboardingPrompts.swift`; three-purpose-buttons report |
| Preset instructions | Revised Japanese/English task-specific instructions; Chinese UI uses Japanese writing catalog; legacy definitions retained for recognizing existing configurations | Onboarding preset/stock recognition sources, `ConcisePresetTests.swift`; main-button-output-options report |
| Storage | All Mac CRUD moves to `public.desktop_user_prompts`; no phone fallback or signup seeding; one-time snapshot for previously activated desktop accounts | `UserPromptRemoteStore.swift`, migration `20260926032830_desktop_user_prompts.sql`, `supabase/tests/desktop_user_prompts.sql` |
| Reply and results | Copy availability dot, hover Reply/dismiss, attached source, expiry/cancel; paging, regeneration/refinement, insertion recovery and scratch composition | Reply-availability and release-separation verification reports |
| Update education | Placement-only modal, draggable demonstration, acknowledgement persistence, About replay, localization and accessibility handling | New `ReleaseHighlights.swift`, `WhatsNewView.swift`, `WhatsNewPreview.swift`, `ReleaseIntroductionStore.swift` plus shared-file wiring |
| Update delivery | Legacy feed plus Japanese/English/Chinese feeds selected by app language, same signed archives | `.github/workflows/release-macos.yml`, new localize-appcast script and tests, `AppDelegate.swift` |
| Rewrite backend | New shared saved-button wording rules for whole text, selection and scratch composition; keep existing deployed additive compatibility | `supabase/functions/desktop-rewrite/prompt.ts` and tests; separate deployment dependency below |
| Analytics | Retain attempt/outcome linkage, button purpose, rewrite type and tutorial attribution | `App/Analytics.swift`, saved-button verification fixture; live delivery remains a gate |

Current source is authoritative where reports disagree. In particular,
`OnboardingPresetPack.available` offers three purpose sets; the earlier report saying
only one set of four is available is superseded. Do not replace existing custom
instructions with the new catalog. Completion version remains 2; old writingStyle
progress maps to purpose and old bar progress maps to practice.

The startup cinematic is eligible first-run education, not an every-launch splash.
Completed users do not replay setup. The release modal currently appears on deliberate
dashboard opening when safe, with stable ID `desktop-four-position-bar`; About can
reopen it. It is not guaranteed to be seen by users who only use the floating bar.
Keep this distinction in announcements. Additional modal lessons are not required to
ship the full changes listed in the release notes.

## Backend readiness and preservation

The [three-purpose-buttons report](../three-purpose-buttons.md) records the independent
storage migration as deployed: 229 rows for 57 previously activated accounts, with
all fields preserved, rollback-based owner/cross-owner/anonymous access checks, and
no phone data or trigger changes. These are prior-task deployment records, not a new
live verification in this draft task. Confirm migration history and accessibility of
the table before publishing the exact candidate; do not blindly replay the import.

The snapshot has a cutoff. Older desktop binaries continue editing phone storage;
changes made there after the snapshot do not automatically reach the Mac table.
Assess any intervening edits before release. Do not overwrite current desktop edits,
repeat the import, or promise continuous phone sync. Rollback to an older client also
returns to phone storage, so it is not a transparent rollback of button data.

The newer `prompt.ts` rules are recorded as **not deployed**. Deploy the reviewed
desktop-rewrite change separately before claiming it in production, preserving the
additive compatibility already deployed. Do not deploy an older local function tree
over newer production style support. Compare the deployed function and apply only the
approved prompt delta. The macOS GitHub workflow performs no Supabase deployment.
No backend mutation or deployment is performed by preparing these drafts.

## Verification status

Fresh checks on the combined working tree during draft preparation:

- 380 Swift tests passed (`/private/tmp/keigo-release-draft-swift.log`).
- 24 desktop-rewrite prompt tests passed (`/private/tmp/keigo-release-draft-prompt.log`).
- Four localized-feed Python tests passed.

Prior task records cover native Debug builds of the newer setup/editor work and
offline CRUD/order/account fixtures. The earlier isolated Debug/Release builds apply
to `7a107f2`, before these newer changes. They do not establish a native Release build
of the final combined candidate. Rendered previews and model fixtures do not prove
live capture, video playback, insertion, telemetry delivery, or Sparkle installation.

Before publishing:

- [ ] Freeze and audit an exact candidate commit containing all product sources,
  bundled resources, tests, localizer scripts and release workflow changes above.
  Recheck edits made after this inventory; avoid blanket staging.
- [ ] Build native Debug and Release from that clean commit with the required build
  configuration. Confirm startup succeeds and automatic Reply stays hard-off, with
  no native host bundled. Repeat relevant tests if the candidate changes.
- [ ] Confirm deployed Mac storage state and review the snapshot cutoff. Verify
  existing button identities/edits/order/visibility survive upgrade and reload; a new
  account begins with no rows, then saves its explicitly selected set.
- [ ] Verify the reviewed backend prompt delta in production through real generation;
  check Japanese/English task outputs, name handling and preservation of intent.
- [ ] Run native editor and browser capture → generation → insertion with the actual
  candidate: selection, whole field, empty input, missing destination, copy-only and
  copy-to-reply. Confirm Accessibility on that app identity.
- [ ] User visual acceptance: final narrow sidebar/overflow, native drag handles and
  autoscroll, editor keyboard flow, first-launch animation and handoff, repositioning
  modal dismissal/replay; multi-display/notch/Dock transitions where hardware permits.
  Record unavailable hardware explicitly. Check Reduce Motion/Transparency and VoiceOver.
- [ ] Confirm live desktop PostHog project 549465 delivery: `button_key`, `rewrite_type`,
  `attempt_id`, `is_tutorial`, and outcome joins. Exclude tutorials and separate internal
  users in decision readouts. `button_key` aggregates purpose, not individual custom
  button IDs. Do not claim per-custom-button popularity from these events.
- [ ] Reconcile recovery/branch references before local merge and retirement. The
  experiment branches preserve the earlier release baseline; newer product work has
  not automatically been propagated into them. Rebuild if rebased or otherwise changed.
- [ ] Finalize the version and release notes, then merge/push the reviewed candidate
  to `main` and use the existing Release macOS workflow when publishing is authorized.

During the authorized release, the workflow tests, archives, signs, notarizes/staples,
packages the installer/update archive, signs the Sparkle enclosure, creates the GitHub
release, then deploys Pages. Confirm both workflow jobs succeed and all four feeds
exist; localized-feed clients depend on the new feed URLs. Verify downloaded artifact
identity, signatures, notarization, version/build and enclosure URLs. Complete an
installed 0.1.10 → candidate Sparkle download/replacement/relaunch smoke test, preserving
account state, buttons, placement, history and Accessibility. Check localized notes
and that education acknowledgement survives relaunch. Do not advertise before these
post-publish checks pass.

## Assembly boundaries

Suggested integration title: **Prepare 0.1.11: redesigned Mac buttons, first-launch
introduction and four-position bar**.

Suggested integration description: This release refreshes the Mac workspace and
first-run experience while retaining multiple saved buttons. Users can move the bar
to four screen edges, manage independently stored Mac buttons, choose a purpose-based
starter set, and use the revised copy-to-reply flow. It also adds placement education
and localized Sparkle notes. Universal-button and automatic-Reply experiments remain
disabled. Independent storage deployment is recorded separately; the new backend
writing rules and final live acceptance checks remain release prerequisites. Attach
the final clean-commit build and acceptance results before merging.

Include the untracked product sources and asset catalogs named above, not just tracked
diffs. Keep new migration and its verification script in the reviewed change even
though deployment is separately recorded. Include only relevant public-safe reports.
Preserve diagnostics, private query output, `log/`, the existing stash, unrelated
`Marketing/`, loose source artwork and experimental `BrowserExtension/` separately.
Check the untracked `aside` item before deciding its purpose; it is not implicitly a
release input. Never stage local config or credential values.

Universal action/styles and automatic AX/DOM Reply remain separate experiments.
Keep recovery tags and original mixed implementations. No broad experimental merge,
remote branch deletion, release-tag changes, backend rollback, or production publishing
is part of drafting this package. The original recovery snapshot predates the latest
uncommitted work; preserve a fresh checkpoint of that work when assembling the candidate.
