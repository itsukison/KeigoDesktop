# Reply Context: latest LinkedIn capture rejected by coverage check

Analysis of the replacement `reply-diagnostics.json` on September 24, 2026. Investigation only; no production code or deployment changes.

## Finding

This attempt used Accessibility (AX), not DOM. The visible-history selection fix recovered the recent messages. A new native coverage check then rejected the capture because one small nearby text candidate was not retained. The backend honored that flag before building conversation candidates, normalizing turns, or calling Jev.

The defect is that the coverage check equates **any non-retained nearby text-shaped node** with **missing current message content**. It does not distinguish empty/whitespace layout text from a meaningful message lost to a budget or read failure. The skipped node sits between a bullet and timestamp and is consistent with a whitespace spacer; its exact value was not exported, so that final characterization remains an inference.

## Matched artifact

- Snapshot: `50BAAF26-A570-41FE-A808-B63D15872B07`.
- Attempt: `3B929AEF-848D-4CA1-8D57-758AF2FFB667`.
- Interpreter revision: `capture-v3-turns-1`; app version `0.1.2`.
- Export phase: `unavailable`; failure: `missing_current_history`.
- Rejecting decision: `capture.missing_current_history`; stage: `capture`.
- Provider calls: **0**. Conversation candidates: **0**, because their construction was never reached.
- `analysisEvidence` equals `evidence`; this is not a narrowed source selection.
- SHA-256: `67320c5de9ffaae212bd13abe8e577fb6b8290aa1f8daebf9b81d48ef18e81a3`.

`OverlayController.swift:30,763` instantiates and invokes `AXConversationReader`. The export contains AX roles, AX attribute provenance, AX traversal counters, and the focused AX composer. The referenced implementation report and AGENTS.md explicitly leave DOM/native-messaging integration as future work.

## What improved

The focused composer remains in `c25`, bounds `[713,747,410,100]` relative to the captured window. All 26 focus-path nodes were read and the path reaches the window.

Unlike the preceding export, this capture includes:

- `b13`–`b24`: the recent message with retry/access troubleshooting instructions, including its inline contact link.
- `b30`: the subsequent message specifying the September 28 and September 29 deadlines. Its rectangle is `[757,613,338,78]`, not a one-pixel strip.

The reader excluded **187 clipped text nodes**, discovered **52 text candidates**, attempted **52 text reads**, and retained **51 blocks / 1,494 UTF-16 units**. It did not exhaust the 60-block or 12,000-unit text limits. Reported traversal time is **94 ms**, with no time-budget or geometry-change reason. Reported metadata/child failures and AX error codes are zero; this is not proof that every later value read succeeded, because discarded value reads lack equivalent diagnostics.

The 500-node limit and unfinished-child work still appear in the export, but neither directly produces this rejection. All discovered eligible text candidates were attempted, and the recent message bodies survived.

## Exact trigger

The only eligible, unclipped text candidate without retained source provenance is `n414`:

- Role: `AXStaticText`; parent: `n412`.
- Screen rectangle: `[933,708,4,16]`.
- Window-relative rectangle: `[933,586,4,16]` (window origin is `[0,122]`).
- Its siblings are `n413`, the bullet retained as `b28`, and `n415`, `1:53 PM`, retained as `b29`.
- It belongs to the header of the same history item whose message body is `n418` / `b30`.

The 4 pt width passes the new filter, which excludes widths **less than** 4. It overlaps the composer horizontally and is 145 pt above its top after accounting for its height, so it falls inside the 300 pt coverage band.

The source path is:

1. `ConversationTraversal.swift:171–206` admits the node as a text candidate based on role and geometry.
2. `ConversationTraversal.swift:247–250` attempts its value read but retains only a matching, noneditable sample with nonblank text. Nil samples, changed roles, editable samples, nil values, empty strings and whitespace all fail this same guard.
3. `ConversationTraversal.swift:275–283` counts every nearby candidate absent from the retained set. It does not preserve or inspect the reason for omission. Thus `skippedCurrentTextNodes = 1` forces `missing_current_history`, despite other retained nearby message text.
4. `interpreter.ts:429–435` immediately returns `unavailable`. Candidate construction begins at line 443 and normalization at line 452, after the return. No anchor, sender, audience, confidence-margin, or generation decision was made.

Absence of text/block-budget and geometry-change reasons narrows this node's omission to the value/sample guard. The export cannot distinguish its individual cases. Its 4 pt rectangle between a bullet and time strongly suggests a whitespace spacer, but a failed or changed sample cannot be conclusively excluded.

## Offline verification

A temporary Swift package copied the current production sources and exercised `ConversationTraversal.read` with synthetic message text, the exported composer/message geometry, and the small timestamp-spacer geometry. No app or browser was driven.

One XCTest covered four cases. With the actual message retained in every case:

| Spacer value | Retained blocks | Skipped current nodes | Missing-history rejection |
|---|---:|---:|---|
| nil | 1 | 1 | yes |
| empty string | 1 | 1 | yes |
| one space | 1 | 1 | yes |
| nonblank text | 2 | 0 | no |

The test passed, confirming the false-rejection mechanism independently of LinkedIn or Jev. It is a reproduction, not a fix test. Probe output: `/tmp/keigo-reply-coverage-probe.log`; the temporary package location is recorded in `/tmp/keigo-reply-coverage-package-path`.

Separately, running the existing pure TypeScript normalization locally on the unchanged export yields two visible history-item turns containing the recent conversation messages: `t0` from `b12`–`b24`, and `t1` from `b25`–`b30`. Candidate construction includes the focused pane `c21`, plus wider/sidebar alternatives. This establishes that the captured recent text can reach the new representation; it does not establish what Jev would select. No capture was sent to a provider.

The existing regression `testMissingOrUnreadCurrentTextHasSpecificCaptureFailure` covers a missing sole message and an oversized sole message. It does not cover a successfully retained message accompanied by an empty nearby metadata/spacer node.

## Correction indicated

Keep the missing-history protection, but track why each candidate was omitted. Successfully read blank/whitespace nodes should not count as lost message content. Preserve conservative handling for actual unreadable message evidence, changed geometry, exhausted budgets, and absence of usable history; those cases need distinct diagnostics rather than one undifferentiated count. Coverage should account for the focused history and message structure, not geometry alone.

Add the retained-message-plus-blank-spacer regression, alongside genuine missing-message cases. Include omission reason and node identity in explicit local exports so a subsequent failure can be attributed without inferring value-read outcomes from geometry. Then a fresh app capture is needed to assess live semantic selection; this attempt never reached that stage.
