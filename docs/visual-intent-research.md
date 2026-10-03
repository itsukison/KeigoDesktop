# Visual intent A prototype

This is a Debug-only capture-and-replay experiment. Start the app with
`--visual-intent-research`. The normal multiple-button UI and automatic Reply
feature flag are unchanged. There is no field replacement or message sending.

## Run

```sh
cd /Users/itsuki/Desktop/key/laptop
xcodegen generate
xcodebuild -project KeigoButtonMac.xcodeproj -scheme KeigoButtonMac -configuration Debug -derivedDataPath /tmp/keigo-visual-build build
open -n /tmp/keigo-visual-build/Build/Products/Debug/KeigoButton.app --args --visual-intent-research
```

Run these commands from the project folder; `No project spec found at
/Users/itsuki/project.yml` means the terminal is in the home folder. Build only after
code changes, and quit the previous research instance before launching another.
For later testing sessions, launch the existing built app with just the `open`
command above.

The research window reports Accessibility, Screen Recording and the current
KeigoButton account. Sign in through the normal app first. Permission setup is
outside capture; macOS may require a restart. This is the app's own session,
accessed through AuthService; provider credentials stay on the server.

1. Close the research window. The never-key **A · Capture intent** button stays.
2. In Gmail, Slack web/native or LinkedIn, focus a plain message body containing
   rough intent. For this experiment, do not use drafts with signatures or attachments.
3. Press the floating button. Leave the target and window unchanged until the
   preview appears. The checkbox in setup controls whether a capture is immediately
   sent to the model; turn it off for local geometry checks.
   Opening the preview also displays capture errors: read the status below the
   permission/account line. A capture requires rough intent typed into the external
   message body, not into this research window. Wait for the running-model status
   to finish before exporting.
4. Verify the magenta outline exactly encloses the intended composer. Cyan outlines
   are the model's claimed conversation. Inspect excerpts and draft separately.
5. **Export** explicitly saves the image, intent and result to a chosen local folder.
   Nothing is added to normal history/analytics. **Load capture** opens request.json;
   **Run A again** makes a fresh independent request for exactly that saved image.

For the current Luna trial, leave **Send each new capture to model** on. Confirm the
result header says `gpt-6-luna`, reasoning `low`, and `visual-intent-a-4`. Export every
completed attempt before pressing A again or **Run A again**, which replaces the
in-memory result. Each export creates a distinct folder; successes, abstentions and
model failures with a captured request all matter. If acquisition fails before a
request exists, Export is unavailable: record that failure and its displayed error
in your test notes so it remains in the workflow denominator.

Check the magenta composer, selected conversation/evidence, language, material facts
and qualifiers, chronology, invented commitments, and whether the draft is sendable.
Keep a short note next to each export describing what you expected and what needs
editing. Start with fresh conversations across Gmail, Slack web/native and LinkedIn,
including competing panes and deliberately missing context. These are calibration
captures; reserve different conversation families for held-out testing. Export the
first result before re-running the same image to check consistency. Repeats do not
count as new scenes.

The image on the model wire is JPEG quality 0.9 at the captured pixel dimensions,
detail=high. The original and marked PNGs are retained only in memory until an
explicit export. Replay uses the saved JPEG, matching the original model input.
Images cover the entire matched window; surrounding panes are deliberately retained
so association can be tested. There is no OCR, conversation AX traversal, extension,
adapter, rolling history, scrolling, microphone or Apple Events in this path.

## Capture contract

AX freezes the entire field value, element, selected range, write strategy, app PID,
focused/helper PID, window handle, title and geometry. The snapshot precedes account
refresh and any focus-taking UI. ScreenCaptureKit matches by app PID, normal-window
layer, window geometry and composer containment, using title only to disambiguate.
Multiple plausible matches fail. Capture reads one complete SCStream frame and stops;
there is no continuous history. It excludes window shadows, cursor and child windows
(on macOS 14.2+). Child windows can enlarge the backing surface even when SCWindow
and filter dimensions still match AX, as Chrome's toolbar windows demonstrated.

Point-to-pixel mapping uses the frame's screenRect, contentRect, contentScale and
scaleFactor. The frame must agree with the frozen window and its backing extent;
unexplained scaling, clipping or missing metadata fails rather than shifting the
marker. Exported frameMetadata records the transform and geometryVersion. The
macOS 14.0/14.1 fallback cannot explicitly exclude children and must pass the same
extent checks. See the [geometry investigation](reports/visual-intent-geometry-fix.md).

Pre/post AX comparisons reject changed element/window/title/text/geometry. Temporary
AX focus/window observers and app-activation notifications detect additional changes
during acquisition. Unsupported notifications are recorded via focusSubscriptions.
These observations are not atomic and cannot prove that an app did not reuse a
composer for another conversation between reads. Live target-switch tests remain
required. No writeback is enabled in this experiment.

## Server

`desktop-visual-intent` is separate from desktop-rewrite. Gateway JWT validation is
enabled; the handler also validates through Auth and permits only confirmed accounts
listed in `VISUAL_INTENT_TESTER_EMAILS`. With an empty allowlist it is disabled.
This research endpoint does not modify tables, reserve production rewrite quota, or
record content in logs. The allowlist is its research access boundary, not a public
product rate-limiting design.

The research handler explicitly selects `gpt-6-luna`, with reasoning `low`, the
existing server-side OPENAI_API_KEY, and prompt `visual-intent-a-4`. It does not read
the old `VISUAL_INTENT_MODEL` override. Freeze this configuration and the image settings
before held-out evaluation; any future model/effort/prompt change needs a separately
labeled run. Luna is a development candidate, not a proven shipping model. The actual
returned model, reasoning effort, prompt/validation versions, input/output token counts
and model latency are exported. The historical four-condition screening is in
`docs/reports/visual-intent-model-screening/`.

The prompt separates target binding, data authority, language/voice, content grounding
and output rules. English rough guidance does not request an English reply to a Japanese
conversation. Summaries must retain material qualifiers and later updates in the final
draft, while distinguishing a reported action from a verified outcome. The rules are
general and contain no names or answers from the calibration captures. Prompt changes
require generated-output review, independently of schema/auth tests; correct evidence
does not by itself establish draft quality.

The [V4 calibration assessment](reports/visual-intent-luna-prompt-v4/assessment.json)
records six real-scene repetitions and eight target/language/missing-context controls.
All three Slack drafts retained the read-only restriction, but two still represented
an earlier setup blocker as current after a later response. This is a recorded chronology
failure, so the trial has not met product advancement gates. Use fresh captures to
evaluate that boundary and natural wording; do not treat replays of these two scenes
as held-out evidence. The A research trigger was opened from the rebuilt Debug app
and verified visible; live capture correctness remains part of the user's trial.

```sh
supabase secrets set VISUAL_INTENT_TESTER_EMAILS=your-confirmed-test-email --project-ref eercsucvxnszqletxued
supabase functions deploy desktop-visual-intent --project-ref eercsucvxnszqletxued --use-api
```

The service permits only inline JPEG input, caps body and image size, and validates
response IDs, geometry, status and evidence/draft invariants. Those validations do
not establish that a quoted excerpt or chosen pane is correct. Under
`visual-intent-validation-2`, evidence/composer overlap produces geometryWarnings
with the overlap fraction; it never discards the entire result by itself. Review
source-text correctness, exact-pane association and draft grounding independently.
Even a large overlap may be inaccurate localization; actual use of composer text
as source evidence remains a semantic failure. Requests set
store=false; that setting is not a claim of zero provider-side retention.

## First acceptance checks

Open `research/visual-intent/fixture.html` in a browser. Both fields contain identical
intent. Capture right then left, without changing the visible message content.
The right answer must use Monday 09:45 / INDIGO-917; the left Thursday 14:20 /
CEDAR-482. Check the marker first, evidence second, draft third. Repeat on a second
display and at different browser zoom levels. This synthetic fixture supplements
the four real communication surfaces; it does not establish real-app support.

During capture, switch field, switch tab, move the window or edit the rough intent.
The result must be the original coherent capture or an explicit stale failure.
Test unavailable AX/Screen Recording. Revoke permissions manually through macOS;
the harness never changes privacy settings automatically.

Then collect the 24 scenes in the architecture decision report (8 calibration,
16 held out, separated by conversation family). Include visible/clipped required
facts with identical intent and source-only facts absent from the intent. A-only
held-out testing has 48 requests (16 scenes × 3 repeats). B remains deferred.

Record native capture correctness, text recovery, exact-composer association,
grounded draft, material unsupported facts, appropriate abstention and latency
separately. Capture failures count in the overall workflow denominator. Repeated
runs are not independent scenes. A response that merely says “I agree” does not
pass a source-recovery trial.

## Verification and remaining evidence

The original prototype passed Debug/Release builds, seven geometry/response tests,
nine server contract/auth tests and the full 387-test Swift suite. The deployed endpoint rejects an
unauthenticated empty request with HTTP 401. The setup window was inspected locally.
These checks do not establish live capture alignment, real-app support, model quality
or latency. Record those separately after permissions and the tester account are ready.

The research endpoint has been deployed and the user-specified tester account is enabled.
The authenticated synthetic right-pane request completed with prompt version 2 in
2,166 ms provider time, recovering Monday 09:45 / INDIGO-917. Version 1 had the
correct draft but incorrectly quoted the intent as evidence; this was a grounding
failure, leading to the explicit composer-overlap validator and prompt revision.
The paired left-pane request then failed the response boundary (HTTP 502). A diagnostic replay identified `evidence_overlaps_composer`: the model still placed purported source evidence inside the marked input. It is not counted as a successful target swap. Synthetic response records are saved under `docs/reports/visual-intent-prototype/`. These are calibration observations, not held-out results. Region boxes remain model
claims; the model can include the composer in its broader conversation region even
though source evidence should exclude the marked composer. The hard overlap rejection
described here was subsequently replaced by diagnostic warnings in validation version 2.

The later user-exported Chrome fixture capture establishes that native capture has
run, but its magenta marker is misaligned with the visible input. A 66-request
[model/crop comparison](reports/visual-intent-model-crop-comparison.md) separates
this geometry problem from model behavior: GPT-5.4 passed all 33 fact/scope checks
on these synthetic controls; mini passed 22/33. Real communication-app acceptance
remains outstanding. The native geometry fix and its verification are tracked in the
[geometry report](reports/visual-intent-geometry-fix.md). The endpoint was restored to
its original mini-model default after the comparison.

## Command-line replay

The Debug app also supports replay without the interactive window. This uses the
app's normal AuthService session, never a copied JWT or provider key:

```sh
/tmp/keigo-visual-build/Build/Products/Debug/KeigoButton.app/Contents/MacOS/KeigoButton --visual-intent-replay /path/to/request.json --output /path/to/results --repeat 3
```

Each run is independent and creates a uniquely named response file. The synthetic
provider fixture can be reproduced with `swift scripts/visual-intent-fixture.swift
/tmp/keigo-visual-fixture` (add `--left` to change only the target marker and IDs).
This rendered image does not exercise live AX or ScreenCaptureKit. The HTML fixture
is for that separate live acquisition test.

The current UI is research tooling in English. It is not a replacement for the
localized shipping overlay. Direct insertion, B's OCR/AX evidence and adapters are
not implemented.
