# LinkedIn Reply failure: evidence and remaining uncertainty

Investigation of the owner's 2026-09-24 17:31:57 EDT screenshot and subsequent owner-exported retry. No runtime or backend changes were made during this investigation.

## Root cause confirmed by the exported retry

The native reader exhausted its capture budget in LinkedIn's navigation and left conversation list, before reaching the open conversation pane or its focused reply field. Jev received mixed sidebar previews rather than the open thread shown in the screenshot. The audience error is downstream of incomplete source capture.

The export was saved locally as `reply-diagnostics.json` at 17:37:47 EDT. Its attempt is `18D1C985-0A3D-4741-BD29-326616432C4F`, snapshot `BA7565AC-134A-462F-8DE5-5DF9CC5C0811`: this is a later retry, not the original screenshot's request. It reproduces `ambiguous_audience`, two calls, 60 blocks, 120 regions, a 24-node incomplete focus path, and a 28-source/26-support selection. Its routing margin is 0.61; traversal sampled 233 nodes in 47 ms with no reported AX errors.

Inspection of the retained evidence establishes:

- Blocks `b0`–`b28` are page navigation, notifications, search labels, accessibility helper text, and other page UI.
- Blocks `b29`–`b37` are Shoko's **left-sidebar row**, including its name, preview, active-conversation marker, and participant-bearing options label. The name bounds start at x=464, inside the sidebar; this is not the open thread's header. The message preview is available, but the preceding message body visible in the main pane is absent.
- Blocks `b38`–`b59` belong to three other sidebar rows. Capture ends in the fourth row's accessibility navigation hint.
- The only two `composer` observations are the global search combo box and the message-search text field. Neither has focus. The actual focused `AXTextArea` is absent from the captured observations.
- Region `c131` has bounds `[388,172,313,786]` and role `AXList`: the conversation list. After the 120-region limit, later sidebar rows inherit this region, losing their individual boundaries.

An offline replay of the actual `buildCandidates`/`candidateEvidence` functions reproduced all seven exported candidate IDs. Candidate `c31` is the only candidate matching the recorded 28-source/26-support counts. It merges equivalent source sets from the broad page/messaging containers `c31`, `c102`, `c103`, and `c104`. Its 54 blocks include multiple unrelated conversations and navigation. Its only remaining composer observation is **Search messages**. A `containsFocus=true` on these large ancestors does not mean that their captured text includes the focused conversation.

The failure chain is therefore:

1. The 24-node ancestor limit leaves the focused path disconnected from the window.
2. The traversal discards that path for direct-edge priority and walks the surrounding page. Partial focus flags survive only on broad ancestors that it reaches.
3. Navigation and the conversation list consume all 60 block slots before traversal reaches the main thread; region slots are also exhausted.
4. Candidate generation groups the remaining mixed previews under broad focus-bearing ancestors.
5. The detail stage receives this incomplete selection and returns audience uncertainty; the UI displays a generic source-selection failure.

This confirms a capture/scoping defect before any conclusion about Jev's ability to understand a complete LinkedIn thread. It does not recover the exact audience probabilities: those are absent from both the logs and export.

## Confirmed outcome

The matching request returned `needs_choice / ambiguous_audience`, after both Jev calls completed. It passed conversation routing, then failed the direct-versus-group audience check. This does not establish that the selected conversation was correct: logs contain counts, not the selected text or region ID.

The screenshot visibly shows Shoko Handa's open conversation and the adjacent composer. The model receives bounded Accessibility evidence, not the screenshot.

Production function version 5 was active. All six deployed source files exactly matched the local versions inspected, including `interpreter.ts`, `candidates.ts`, `handler.ts` and `jev.ts`.

## Matching attempt

- Native log: 17:31:47.677 EDT, Chrome focused element was `AXTextArea`, `isField=true`; at 17:31:47.678 the overlay entered `explicitReply`.
- Backend event: 21:31:51.504 UTC / 17:31:51.504 EDT.
- Snapshot: `5859036E-E378-416F-8085-57DFB70862A2`.
- Attempt: `C2A2F7C5-0276-4178-AF7E-621F0099A042`.
- HTTP 200; handler latency 2,574 ms; two provider calls.
- Provider payloads: 54,464 and 30,994 bytes, both below the 96,000-byte application limit.
- Question counts: 61 for routing/classification, 17 for detailed interpretation.
- Seven distinct candidates, none omitted. Selected candidate: 28 source blocks and 26 support blocks.
- Conversation decision margin: 0.58. This is the top-two probability gap, not an accuracy measurement or the audience margin.

The current failure is therefore not the old pre-provider request-size rejection, an authentication failure, a rate limit, or a provider timeout.

## The exact rejection and misleading UI

`interpreter.ts:133` asks whether the selected region is a one-to-one or group conversation. `readDecisions`, at line 291, changes *any* choice to `uncertain` when the top-two probability gap is below 0.10. This applies to audience as well as routing. At line 438, an uncertain audience immediately returns `ambiguous_audience`, before message-target validation.

Two different situations produce this outcome: Jev explicitly chose uncertain, or it chose direct/group with a gap below 0.10. Current diagnostics record only the conversation margin, so the logs cannot distinguish them. A synthetic check against the actual parser confirmed that direct=0.54/group=0.46 becomes uncertain, whereas direct=0.90/group=0.07/uncertain=0.03 stays direct. These synthetic values are not the real request's probabilities.

`ReplySession.accept` preserves the reason but maps `needs_choice` to `needsSource`. `ReplyContextPanel.swift:167` displays the same generic Japanese message for every such reason. Consequently, an audience-classification failure appears to be a failure to find anyone to reply to.

## Capture weaknesses observed in this request

1. **The focused path was incomplete.** Diagnostics report `focusPathLength=24`, `focusReachesRoot=false`, and `focusPathRead=16`. `AXConversationReader.swift:38` limits the upward walk to 24 nodes. The retained chain did not reach the captured window within that limit. `ConversationTraversal.swift:62` then uses an empty verified path, disabling direct traversal along known focused edges. Partial focus flags remain available; all focus information is not lost.
2. **Capture exhausted representation limits quickly.** It sampled 221 nodes in 29 ms, recorded no child/attribute failures or AX error codes, and reached exactly 60 blocks and 120 regions. Reported reasons were `block_budget`, `child_budget`, `region_budget`, `unknown_geometry`, and `visible_history_only`. It did not hit the time or 500-node limit. The traversal stops completely at the block limit, including later composer metadata. Every qualifying `AXGroup` spends a region slot; after 120, further structure inherits its enclosing region instead of recording a new boundary. `child_budget` here means pending child work remained, not proof that an individual 200-child page was too large.
3. **Routing retained almost all captured text.** Detailed interpretation received 54 of the 60 blocks. This warrants checking whether the chosen region mixes navigation, sidebar previews, and the conversation. Counts alone cannot establish contamination or which exact header/message was missing.

These are concrete weaknesses in this capture. Whether they caused the audience uncertainty, rather than an interpretation/calibration problem with sufficient evidence, requires the retained snapshot.

## Correction direction

The owner-exported retry supplies the missing capture evidence described above. Its private source text was inspected locally and was not sent to another provider or copied into a test fixture. The report records structural findings rather than the conversation bodies.

The export does not contain raw Jev answers, so it cannot retrospectively recover the exact audience choice/probabilities. Add bounded audience-choice/margin and selected-region diagnostics to distinguish model abstention from our threshold, without storing conversation text.

The first implementation work is to preserve a verified focused-composer path through deep web trees, reserve useful header/history/composer evidence before generic page chrome consumes capture limits, and retain those relationships in candidate scoping. Keep the captured-window boundary and bounded IPC; do not solve this by following arbitrary foreign-window focus edges. Generic search inputs must not be presented as reply-composer evidence. Compact structural wrappers without merging independent conversations or deduplicating genuinely repeated messages. Audience policy should then be evaluated against complete relevant evidence; forcing `direct` or simply lowering the threshold could conceal a wrong-conversation selection. The UI should expose the actual recoverable uncertainty rather than conflating it with missing context.

Existing automated fixtures verify routing and abstention using mocked decisions. They do not prove that Jev can classify this real LinkedIn capture. No live provider replay or UI automation was performed in this investigation.
