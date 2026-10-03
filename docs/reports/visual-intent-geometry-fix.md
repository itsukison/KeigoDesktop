# Composer geometry and overlap evaluation

The misplaced magenta outline came from capturing a different backing extent than
the AX window described. This was an acquisition bug, independent of model quality.

## Direct evidence

The user exported Gmail capture `4985FBAB` and paired Chrome fixture captures
`523D7709` (left) / `F270838A` (right). AX and SCWindow agreed on
`x=0, y=122, width=1920, height=958`. The screenshot nevertheless included Chrome's
tab strip and toolbar, compressed to roughly 1703 pixels wide with black padding
on the right. Both fixture input rectangles were correspondingly misplaced.

A one-frame SCStream probe exposed the discrepancy that the screenshot API's
empty attachment metadata could not diagnose:

| Measurement | Child windows included | Child windows excluded |
|---|---:|---:|
| SCWindow/filter size | 1920 × 958 | 1920 × 958 |
| Frame content size | 1703.111 × 958 | 1920 × 958 |
| contentScale | 0.887037 | 1 |
| scaleFactor | 1 | 1 |
| Toolbar/tab surfaces in image | Present | Absent |

The relevant Chrome auxiliary windows occupy the 122 points above the content
window. Changing only `includeChildWindows` to false yielded the intended content
viewport without black padding. The SDK documents child-window inclusion as the
default on macOS 14.2+. This experiment establishes the cause for this Chrome case;
it does not establish identical behavior for every browser or Electron app.

Probe metadata is preserved in `visual-intent-geometry/before.json` and `after.json`.
The after-image is a synthetic fixture; private mail images remain in the user's
explicit export folders rather than being duplicated into this report.

## Change

The Debug research capture now reads one complete SCStream frame and then stops.
It excludes child windows where supported, shadows and the cursor. AX target
freezing and pre/post focus checks remain in place. The mapping uses actual frame
placement and scale, validates that the source extent agrees with the frozen
window, and exports the metadata as `single-window-frame-v2`.

Unexpected extent changes fail explicitly. This does not hardcode Chrome offsets,
enlarge the composer to include its container, add OCR, or alter the generation
model. The magenta stroke is drawn just inside the frozen editable element bounds.

## Evaluation policy

Both server and client now retain otherwise-valid results when an evidence box
overlaps the composer. The server emits the percentage as a geometry warning with
`validationVersion=visual-intent-validation-2`; the research UI displays it.
Capture correlation, image bounds and response-shape invariants remain enforced.

A replay of the previously rejected Gmail export returned a draft with a 100%
overlap warning instead of losing the result. This verifies retention only: its
English generic-ID reply and promise to provide the ID do not establish a correct
contextual reply to the Japanese message. Box accuracy, recovered source text,
pane association and final reply quality must be scored separately. Slight box
overlap alone is not a contextual failure; treating rough intent as source facts is.

The tester-restricted endpoint was deployed with this validation change. The model
remains `gpt-4.1-mini-2025-04-14`, prompt version `visual-intent-a-2`.

## Verification

- Full Swift suite: 390 tests passed, including 10 visual geometry/response tests.
- Server: 10 contract/auth tests passed, including slight and complete overlap.
- Debug and Release builds passed. Subsequent user-exported Gmail and LinkedIn captures visually confirm tight composer outlines (details below).
- The one-frame native probe confirmed the corrected 1920 × 958 extent at scale 1.
- Real Retina/multiple-display captures, other communication apps and stale-target
  scenarios remain unverified by this geometry experiment. Unit tests cover their
  coordinate arithmetic, which is not a substitute for native acceptance.

## Native Gmail and LinkedIn follow-up

User exports `D7797CE0` (Gmail) and `E3C0F438` (LinkedIn) use
`single-window-frame-v2`. Both have frame content 1920 × 958, contentScale 1,
scaleFactor 1. Visual inspection of both marked PNGs confirms the magenta outlines
wrap only the editable areas. Gmail maps to `(337,777,1478,85)` and LinkedIn to
`(713,747,410,100)` in image pixels. The user also reports the geometry is correct.
This verifies those two captures, not every layout or the paired fixture swap.

Both responses use `gpt-4.1-mini-2025-04-14`, prompt version 2 and validation
version 2. Their drafts were retained despite overlap warnings, as intended.

| Dimension | Gmail | LinkedIn |
|---|---|---|
| Composer geometry | Pass on inspected image | Pass on inspected image |
| Source-only fact in draft | No: generic ID statement could come from intent alone | Yes: Product Manager internship is visible in the associated message and absent from intent |
| Returned source evidence | Fail: quotes rough intent | Fail: quotes rough intent |
| Conversation region | Incorrectly labels the editable draft itself | Region covers only a lower slice, not the message/header |
| Conversation language | English reply to Japanese source | English reply to Japanese source |
| Recipient name | Omitted | Visible Yurino Horiuchi omitted |

The LinkedIn name is present in the captured image's active-conversation header
and message author. Thus name omission in this saved result is not caused by
clipping or missing screenshot pixels. It does not establish that the model could
not read the name: this intent did not explicitly request a salutation. The user's
precise name-related failure description is still being clarified.

Do not turn the overlap warning back into a hard rejection. These examples show
why the excerpt's meaning must be checked independently: the problem is not only
where the model drew a box, but that it selected the user's instruction as source
text. Gmail is not yet evidence of contextual understanding. LinkedIn provides
partial positive evidence through a source-only detail, but not a complete pass.

The next informative comparison is on these identical corrected screenshots:
measure incoming-message evidence, recipient identification, language and draft
facts with the current baseline and the stronger model from the earlier controlled
comparison. Keep model identity explicit and avoid another capture-layer change
unless new geometry evidence warrants it. No model or prompt was changed in this
follow-up review.

## Requested GPT-5.4 test switch

The user subsequently requested GPT-5.4 for live research testing. Set only
`VISUAL_INTENT_MODEL=gpt-5.4-2026-03-05`; prompt, capture and validation remain
unchanged. An authenticated replay of corrected LinkedIn capture `E3C0F438`
returned that exact model in 5,957 ms provider time. Its conversation region
selected the active thread, its evidence identified Yurino Horiuchi, and its draft
used Japanese. The draft still omitted a salutation/name. Some evidence boxes
remain imprecise; one returned excerpt also contains an extra closing bracket.
This single run confirms the switch and improved evidence selection for this
capture, not general reliability. The full result remains alongside the user's
export under `gpt54-verification/`.

## User-run GPT-5.4 LinkedIn and Slack checks

Reviewed exported requests, responses and marked images for `670BDD1B` (LinkedIn)
and `2A2C4BFA` (Slack). Both report `gpt-5.4-2026-03-05`, prompt version 2,
validation version 2, corrected frame geometry and no overlap warnings.

- LinkedIn: the region selects the active conversation; evidence identifies Yurino
  Horiuchi and the Mercari PM internship message, rather than quoting the user's
  intent. The Japanese draft expresses interest and asks where to find application
  information, matching the intent. It does not include a salutation, which was not
  requested. Evidence punctuation/box precision is not perfect.
- Slack: the region selects the right thread associated with the marked composer,
  excluding the channel's other topics. The draft recovers the Rakuten monthly-report
  bot, read-only BigQuery access, the 403 permission problem and the later message
  that it was addressed. These facts are present in the screenshot and absent from
  the rough intent. This is positive evidence for real two-pane association.
- Slack draft caveat: “こちらでも確認を進めます” adds a promise to check that the
  user did not supply and the visible messages do not establish. Correct context
  recovery does not excuse adding a commitment when asked only to summarize.
- Provider latency: LinkedIn 5,100 ms; Slack 7,745 ms (not total interaction time).

These two user-run scenes support continuing with architecture A and GPT-5.4 as
the current research baseline. They are not repeated runs of the same scene, a
held-out benchmark, or proof of general app support. Next test: hold a two-pane
scene fixed and swap the focused composer, using source facts unique to each pane.
No capture, prompt or model settings were changed during this review.
