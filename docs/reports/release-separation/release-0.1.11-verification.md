# 0.1.11 release verification

Product candidate: `0315d28` on `codex/redesign-multiple-buttons`. A clean Git archive
was built at `/private/tmp/keigo-release-0.1.11`; only the existing ignored local build
configuration was supplied separately. All latest product sources, first-launch
animation, bundled artwork, button editor, setup, independent storage and release
education are included. Unrelated marketing, diagnostics and browser experiment files
remain outside the release commit.

## Candidate checks

- Clean native Debug and Release builds pass, with version override 0.1.11.
  Logs: `/private/tmp/keigo-release-0.1.11-debug.log` and
  `/private/tmp/keigo-release-0.1.11-release.log`.
- Clean Swift suite: 380 tests pass on rerun. The first run encountered the existing
  native bridge integration transport failure (four assertions in one test); rerunning
  the full suite passed without changing source. Evidence:
  `/private/tmp/keigo-release-final-swift-rerun.log`.
- Offline native saved-button harness passes with `KEIGO_REPLY_CONTEXT=1`: CRUD,
  validation, order/visibility/identity preservation, failed writes, account changes,
  onboarding defaults/drafts/retry/replay. Automatic Reply remains hard-off.
- No development native host was found in the Release app bundle.
- Localized appcast tests: four pass. All three 0.1.11 note sections previously
  rendered as valid localized HTML with ten bullets each and no fallback.
- Ordinary clean Debug launch succeeded. Native cross-app insertion and browser
  acceptance have not been completed by this task; UI automation reached a scratch
  TextEdit draft and the bar, but did not complete a generation/insertion cycle.

## Live backend and telemetry inspection

Read-only production storage check confirms migration `20260926032830` is recorded,
229 desktop rows across 57 accounts exist, and RLS is enabled. Two overlapping rows
differ between phone and Mac; neither has a newer phone timestamp. No data was copied,
overwritten or deleted during this release check. The one-time snapshot remains intact.

PostHog discovery via `learn` still fails, but direct tool/schema discovery and queries
work. The active project was explicitly set to **KeigoButton Desktop (macOS), 549465**.
In the queried trailing seven-day sample, 132 starts, 115 completions, 71 insertions
and 17 failures all have attempt IDs, rewrite types and tutorial flags. These are
delivery diagnostics including internal/tutorial traffic, not adoption metrics.

Of 75 saved-button starts, 69 have purpose keys. All six missing keys are from 0.1.9;
observed 0.1.10 saved-button starts have purpose keys, including `user_authored`.
Eight sampled 0.1.10 saved-button attempts each have start/completion/insertion events
with one consistent type, purpose and tutorial status. Copy events exist in the schema
but none occurred in this seven-day result. This verifies existing live delivery,
not yet events from the newly published 0.1.11 binary or a per-custom-button metric.

Deployed desktop-rewrite version 28 was downloaded and preserved. The deployment
candidate retains every deployed file and changes only `desktop-rewrite/prompt.ts`
with the approved saved-button rules. JWT verification remains enabled. Its 24 prompt
tests pass when checked against compatible v2 reply types retained in the experiment;
the local release's older v1 type-only file is incompatible with deployed validation
and is not substituted into the deployment. Universal/backend compatibility is retained.
Deployment completion will be recorded below when performed.

## Recovery and remaining acceptance

A new private snapshot is at `.local-recovery/20260926-release-0.1.11/`: 2,393
nonignored files, SHA-256 manifest, working diff, refs, stash inventory, full Git bundle,
deployed backend source and deployment candidate. The previous recovery tags and stash
remain intact. Local experiment branches retain their separate earlier baseline.

The user has authorized publication. Confirmation of the previously required manual
native/browser rewrite/Reply acceptance, or an explicit decision to release with those
checks outstanding, is pending. Physical multi-display/notch/Dock transitions and
OS accessibility settings have not been newly verified here. Signed installer and
Sparkle update-chain checks follow publication; successful builds do not establish them.
