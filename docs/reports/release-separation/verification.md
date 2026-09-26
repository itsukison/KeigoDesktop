# Multiple-button release verification

The release implementation is on `codex/redesign-multiple-buttons`. It has **not**
been merged or published. See [the branch and recovery map](branch-map.md).

## Implemented behavior

- Restored shared account-backed `user_prompts` loading, editing, enabled states,
  ordering and saved-button capture/generation. Loading never seeds/replaces rows.
- Buttons page rebuilt under the Aside design: list left, name/instructions right,
  drag plus up/down controls, toggles, local Add draft, explicit valid Save/Cancel,
  deletion confirmation naming phone sync, dirty selection/navigation/settings/close
  guards, loading/empty/signed-out/error states and explicit language realignment.
- Reads and multi-request writes are account-scoped. Rapid reorders coalesce;
  failures reload server state. Saving text retains the current row's slot/toggle.
- Restored purpose/preset and button-review onboarding; returning configurations are
  the default, replay does not replace buttons, disabled states and identities survive
  draft round trips. Raw IDs and completion version 2 remain stable. `writingStyle`
  resumes at purpose; old bar resumes at practice.
- Retained redesigned workspace/settings, cinematic mascot introduction, blue identity
  and installer, four-position placement, smoked-glass bar, attached generation/results,
  inward errors, result paging/regeneration/refinement and copy-to-reply workflow.
- Enabled buttons remain in saved order in a bounded scroll region, with separate
  pencil and Reply. Side-column correction: matching viewport/button widths,
  6 pt outer insets, 56–108 pt button widths fitted to ordinary labels, one line with
  tail ellipsis for long labels and full-name hover help. Reply reserves dismiss space.
- Automatic Reply is hard-off in Debug and Release. Old environment/preferences cannot
  enable it. No development native host is embedded in the release app. Universal
  style files remain untouched and saved-button requests omit the style payload.
- Existing backend files on the release branch are unchanged from main; no schema,
  function deployment, API migration or rollback occurred. Shared wire types remain
  compatible. Universal backend additions live in its experiment.

## Passed checks

| Check | Evidence |
|---|---|
| Isolated release Swift suite | 369 tests, zero failures; `/private/tmp/keigo-clean-tests.log` |
| Isolated release native Debug and Release | Both pass, including `7a107f2`; `/private/tmp/keigo-clean-debug.log`, `keigo-clean-release.log` |
| Native model mutation fixtures | Save/reload, blank creation rejection, ID/builtin preservation, toggle, rapid order persistence/main slot, Add/Delete, failed Save, failed reorder reconciliation, stale account response |
| Disabled automatic Reply override | `--verify-saved-buttons` passes with `KEIGO_REPLY_CONTEXT=1` on the release build |
| Actual saved-button request/attribution | Controller-generated mock requests retain saved instructions, `saved_button`, button purpose and attempt ID; no style payload. Started/completed events carry equal attempts and tutorial status |
| Blank/missing target guidance | 60 language × position × rejection cases, never-key errors, no generation/focus change, error survives collapse; toast follows live zone changes |
| Generation fixtures | Nonempty whole-input and selection each produce one mock rewrite; pencil opens scratch without a request |
| Copy-to-reply native fixtures | 12 language/position layouts; unchanged idle geometry, never-key hover, dismissal, grace collapse, attached source, frozen source, cancellation, expiry and invalid-copy clearing; clipboard preserved |
| Edge/result fixtures | JA/EN/ZH × four positions × short/long/instruction results; regeneration append, instruction inheritance, refinement, earlier-page choice, failure and cancellation restoration |
| Light UI render fixtures | 87 fixtures in `/private/tmp/aside-previews`; Buttons at 920/1000 widths and setup screens in JA/EN/ZH. Inspected smaller English Buttons and JA/ZH review images; Save remains visible |
| Live Buttons UI | Existing customized long instruction loaded intact; unsaved navigation warning, Keep editing, Cancel restore and Tab focus into multiline editor verified; no production button mutation |
| Universal experiment | Native Debug/Release builds; 369 Swift tests; 13 backend style tests |
| Reply experiment | Native Debug/Release builds; 369 Swift tests; 67 backend capture/validation tests; 14 browser-extension tests |
| Recovery | 679 archived file hashes match; complete Git bundle verifies; original stash object ID unchanged |

Native fixture commands run the Debug executable with `--verify-saved-buttons`,
`--verify-polish-guidance` (historical name; now checks saved buttons),
`--render-reply-availability`, `--render-edge-panels`, or `--render-aside-previews`.
They use isolated service fixtures, not production generation. The core test total
excludes the concurrent task's two release-introduction tests.

The original live development build showed revoked Accessibility access. An isolated
fixture process reported trusted access, so that alone was not treated as proof of
live cross-app capability. A subsequent ordinary isolated launch initially failed
because its ignored `Local.xcconfig` had not been copied: the existing PostHog startup
assertion rejected an empty project token. Copying that existing local build config
and rebuilding fixed launch. No credential values were printed or committed.

The user took ownership of visual acceptance and reported the UI mostly fine, with
the side-column spacing/wrapping correction above. The updated build was opened for
that review. Earlier render evidence predates this final compact-column correction;
its Debug and Release builds pass.

## Outstanding acceptance gates

1. Real capture → generation → insertion in a native editor and browser composer,
   including selection, empty/missing destination, copy-only results and copy-to-reply.
   No end-to-end production generation/insertion success is claimed here. Reconfirm
   Accessibility on the actual signed build used for this acceptance.
2. Live PostHog delivery and attribution. The installed connector repeatedly returned
   `The learn command is not available for this client`; its required skill discovery
   was unavailable (earlier skill calls also reported missing `llm_skill:read`). No live
   query was completed, and telemetry is **not described as verified**.
3. User visual acceptance of the final narrow side column, long names/overflow and
   accessibility settings. Physical multi-display/notch/Dock-transition checks were
   not performed; pure placement and native single-display fixture coverage is not a
   substitute for those hardware checks.

## Telemetry decision readout

The code retains `button_key`, `rewrite_type`, `attempt_id` and `is_tutorial` across
attempt/outcome reporting, and the saved-button backend request retains corresponding
metadata. `button_key` is a privacy-safe purpose, not a saved row ID or arbitrary label;
customized/user-authored buttons aggregate rather than sending their instructions.
This supports a purpose-level usage comparison, not per-custom-button popularity.

Before deciding on universal-button shipping, verify delivery in the **desktop**
PostHog project `549465`, exclude tutorial attempts, and separate internal/test accounts
from everyday users. Compare attempts with completion/insertion/copy/failure outcomes
using attempt IDs. Do not infer real adoption from preview fixtures, internal model
experiments or guaranteed onboarding actions. No product-direction decision was made.

After these gates pass: merge locally, retire redundant local branch names per the
branch map, then perform the normal signed/notarized release and version/feed steps
as separately authorized work. No publish, remote deletion or deployment was done.
