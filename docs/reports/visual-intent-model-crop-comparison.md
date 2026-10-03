# Visual intent: model capability versus conversation isolation

## Decision

Continue evaluating A with GPT-5.4 before adding a region-selection pipeline, OCR,
or app adapters. Correct the native capture-to-image geometry first. This comparison
supports a stronger model as the smallest next step; it does not establish real-app
reliability or a production model winner.

Both changes helped: GPT-5.4 succeeded with the full window in every tested repeat,
and giving GPT-4.1 mini a human-selected conversation crop eliminated observed
cross-pane text contamination. Automatic cropping has **not** been solved or tested.

No product implementation or prompt was changed for this experiment. Three offline
preparation/replay/scoring scripts were added. The existing research endpoint's
model setting was temporarily changed, then removed; a final authenticated replay
confirmed restoration to `gpt-4.1-mini-2025-04-14`.

## Directly observed

66 experimental requests: 11 input conditions × 3 independent requests × 2 models.
These are repeated variations of one synthetic conversation family, **not 66
independent scenes**. The browser export is the HTML fixture in Chrome, not Slack,
Gmail or LinkedIn. The user's earlier failed output and the restoration request
are excluded from the 66-request denominator.

“Pass” below means the returned draft and source evidence contain the expected
deadline/reference, contain no facts from the other conversation, do not quote the
rough intent as source evidence, and survive the existing response validator.
It does not certify every aspect of writing quality, exact coordinates or authorship.

| Input condition | GPT-4.1 mini | GPT-5.4 |
|---|---:|---:|
| Clean rendered fixtures, full window; left/right and swapped columns | 5/12 | 12/12 |
| Same fixtures, human-selected target-pane crop | 12/12 | 12/12 |
| User's exact browser export, original marker | 2/3 | 3/3 |
| Browser export, manually corrected marker, full window | 0/3 | 3/3 |
| Browser export, corrected marker and target-pane crop | 3/3 | 3/3 |
| Total | 22/33 | 33/33 |

The five rejected mini responses all failed `evidence_overlaps_composer`. Their
provider content is unavailable through the existing rejection boundary, so their
association correctness is unknown. They count as workflow failures, not proven
wrong-pane selections. Six additional mini responses contained cross-pane facts in
their draft or evidence. A correct draft with contaminated evidence still fails.

For example, two corrected-browser mini runs drafted the correct Cedar reply but
also quoted Indigo evidence; the third drafted the Indigo reply. All three fail
association even though two final texts look acceptable in isolation. Conversely,
three raw-browser replays do not reproduce the original mixed draft every time:
two pass the content check. The behavior is variable, not a deterministic failure.

### The exported marker is misaligned

The export contradicts the initial assumption that composer geometry was correct:

- Request image: 1920 × 958 pixels.
- Exported magenta box: `x=41, y=664, width=888, height=111`.
- Manually measured visible left input: approximately
  `x=37, y=700, width=787, height=96`.
- The magenta box extends above the actual input and across the right pane's edge.

Compare the [exact exported model image](visual-intent-comparison/browser-raw/input.jpg)
with the [manually corrected full image](visual-intent-comparison/browser-corrected-full/input.jpg)
and [correct-pane crop](visual-intent-comparison/browser-corrected-crop/input.jpg).
The correction is an offline diagnostic control. No capture code was fixed.

The mismatched geometry is a native acquisition problem to investigate separately.
It cannot explain every failure: mini still mixes panes with the corrected marker,
and also fails on clean rendered fixtures whose markers align correctly.

### Model boxes are a separate outcome

Every GPT-5.4 run's fact-bearing evidence rectangles intersected the actual source
text, and every claimed conversation region stayed within the target pane's horizontal
boundary. Only 5/33 mini runs passed that coarse fact-box intersection check; all five
were cropped rendered fixtures. Mini could recover the right text while placing its
box far from the actual message.

Intersection is only a necessary condition, not a tight-box accuracy metric. Some
GPT-5.4 boxes are oversized and some responses include UI headings or composer labels
as additional evidence. We do not treat these outputs as verified structural truth.
The scoring script measures fact-bearing excerpts separately from such UI labels.

### Latency

On the clean full-window fixtures, median provider time among returned results was
2.264 seconds for mini and 2.697 seconds for GPT-5.4. This excludes rejected mini
requests because the server does not return their provider timing; per-attempt wall
times, including failures, are retained in the evidence. These small sequential runs
do not establish production latency or cost. Provider usage for rejected requests is
also unavailable, so no complete cost estimate is claimed.

## Interpretation and limits

**Strongly supported:** model choice materially affects this task. The same prompt,
schema, output budget and marked images work substantially better with GPT-5.4.
The current mini model's failure is insufficient grounds for abandoning A.

**Strongly supported:** isolating the intended conversation helps mini recover
uncontaminated text. Crops also change image dimensions, model preprocessing and
available detail; the experiment does not isolate distraction removal from those
other effects. Cropping does not make mini's evidence coordinates dependable.

**Unresolved:** how reliably either model handles real Slack two-pane layouts,
multiple Gmail drafts, Japanese text, quoted history, clipped messages, floating
LinkedIn panels or stale focus. These cases require held-out real-app captures.

**Unresolved:** the exact native geometry defect. The exported raster and AX-derived
marker disagree; the cause could involve capture content placement/scaling or geometry
inputs. The export alone cannot distinguish those causes. Do not install a fixed
offset/scale from this one example.

**Speculative:** a small structural association layer may still be needed on harder
layouts. This experiment provides no evidence that it is necessary yet. Similarly,
the perfect GPT-5.4 count here must not be extrapolated into a universal reliability
claim. It is one easy, English, synthetic conversation family.

## Method and evidence

- Models: `gpt-4.1-mini-2025-04-14` and `gpt-5.4-2026-03-05`.
- Unchanged prompt: `visual-intent-a-2`; Chat Completions; strict response schema;
  image `detail=high`; `max_completion_tokens=2400`; no explicit reasoning effort.
  GPT-5.4's documented default is `none`. Models may preprocess images differently.
- Same tester-restricted endpoint and normal KeigoButton AuthService session.
  No credentials were extracted; no provider keys were moved to the client.
- The two existing 1200 × 800 rendered JPEG fixtures were reused. Four full-window
  conditions combine both target sides with original/swapped column placement.
  Swaps move entire columns and their marker; metadata follows that marker. Opaque
  IDs prevent left/right text in synthetic IDs from contradicting the image.
- Each rendered crop is the known 600 × 800 target column. Browser crop:
  `x=18, y=177, width=826, height=638`, including the source and target composer.
- Crops and swaps do not rescale or generate content, but derived JPEGs are lossily
  re-encoded at quality 0.9. Corrected browser images derive from exported original.png.
  The raw browser replay preserves the original request and exact wire JPEG.
- Browser full images contain an answer-key footer; this is a confound. The clean
  rendered fixtures have no such footer. The browser crop excludes the footer and
  browser chrome. These are calibration controls, not held-out acceptance evidence.
- Models ran sequentially, mini first; request order was not randomized. Repeats use
  fresh stateless requests, without previous model responses in context. No automatic
  retry silently replaces a failed attempt.

The [manifest](visual-intent-comparison/manifest.json) records all inputs and hashes.
[Summary](visual-intent-comparison/summary.json), [scored records](visual-intent-comparison/scored.json)
and the `results/` subtree preserve all 66 attempts and returned responses. Fact/scope
grading is a fixture-specific deterministic check; all returned drafts were also
reviewed. There is no independent general-purpose semantic judge.

Preparation: `scripts/visual-intent-prepare-comparison.swift`.
Replay: `scripts/visual-intent-run-comparison.py`.
Scoring: `scripts/visual-intent-score-comparison.py`.
The runner asserts the returned model matches the experiment label. Run it only after
selecting the intended server model; restore the original setting afterward. Stored
paths refer to this workspace and must be adjusted if the archive is moved.

Official documentation confirms GPT-5.4 supports image input, Chat Completions and
structured outputs; it does not establish performance on our fixtures. See
[GPT-5.4 model documentation](https://developers.openai.com/api/docs/models/gpt-5.4)
and [vision limitations](https://developers.openai.com/api/docs/guides/images-vision).

## Smallest next step

1. Diagnose and correct the AX-to-captured-raster mapping, with visual checks across
   window sizes, zoom, Retina scaling and displays. Preserve frozen-target checks.
2. Use GPT-5.4 as the next research baseline and collect the planned held-out real-app
   scenes. Score target association independently from text, draft and region accuracy.
3. Add explicit region selection/isolation only for demonstrated residual association
   failures. Add OCR when exact text recovery/coordinates need it, and adapters only
   for recurring app-specific failures. This experiment does not authorize or implement
   those larger changes.
