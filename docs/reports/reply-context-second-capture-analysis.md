# Reply context: second capture and Jev architecture analysis

Analysis date: 2026-09-24. Analysis only; no production code or deployment changes.

## Finding

The new capture finds the focused composer and the correct conversation. It fails later when selecting incoming message content. The principal defect is evidence selection: older history whose AX rectangles collapse to one-pixel strips consumes the text budget before normally sized history text is reached. Fragment-level interpretation and broad abstention rules add a separate reliability problem. Changing the provider or merely rewriting the prompt cannot recover text that was never sent.

The previous change fixed focus traversal but did not establish usable current-message coverage. Its tests covered missing ancestry and sidebar starvation, not edge-collapsed historical text. Passing those tests did not establish live semantic correctness.

## Matched evidence

The replaced local `reply-diagnostics.json` matches the server event at 2026-09-24 22:30:47.723 UTC (18:30:47 EDT):

- Snapshot: `4BA3FB01-08A1-445F-879C-B91FF2FA9279`.
- Attempt: `2C2BBF65-C616-46A8-96C1-3AD3329E5918`.
- Interpreter revision: `capture-v3-focused-2`.
- Result: `needs_choice`, `ambiguous_target`, detail stage.
- Full retained focus ancestry: 26 of 26 nodes, reaches captured window.
- Focused composer: `AXTextArea`, region `c25`, window-relative bounds `[713,747,410,100]`.
- Selected containing pane: `c21`; one distinct candidate from 41 equivalent source-bearing containers. Its header and attachment controls identify the same conversation.
- Conversation margin: 0.92. Audience: raw and effective `direct`, margin 0.74, no forced abstention. These are top-two probability gaps, not accuracy percentages.
- Two successful provider calls, 48,722 and 50,289 request bytes, 61 and 58 questions. Server latency 2,515 ms.
- 500 sampled nodes in 92 ms, 424 child-page reads, zero reported attribute/child failures, zero AX error codes.
- 60 blocks, 59 retained regions; reasons include block, node, and unfinished-child budgets. No region overflow or lost focus anchor.

The analysis evidence equals the captured evidence in this export. This is not a narrowed retry accidentally looking at a different source.

## Where the evidence goes wrong

The first 12 blocks are composer controls and conversation-header labels. Every remaining block, `b12` through `b59`, has window-relative Y=217 and height=1. These include August 24/25 history and the beginning of August 28 history. All 40 source blocks offered as message material have this collapsed geometry; eight more history blocks are supporting links. None of the recent deadline/retry text visible in the earlier supplied screenshot is present.

The retained list `c75` has bounds `[701,217,455,517]`. In the local raw observation tree, its subtree contains 346 visited nodes; 313 have height=1, and none is marked clipped. Later in that same subtree, 16 static-text nodes have height greater than one. They were visited after the source buffer filled, have no recorded source attribute, and contributed no text blocks. For example, `n394` has a normal 338-by-38 rectangle and `n418` a 338-by-78 rectangle. Their text was never requested on the metadata-only path.

This is stronger evidence than merely observing a budget limit: the reader actually reached substantial on-screen text geometry but had already stopped collecting text. The latest screen was not supplied in this turn, so the identities of those unread nodes cannot be established from geometry alone. Their placement is consistent with the recent message area in the earlier screenshot. Missing recent message text and retained August history are directly established by the export.

The implementation explains this behavior:

1. `AXConversationReader.swift:54` reads role, rectangle, editable/selected/expanded state and subrole, but no richer visibility evidence.
2. `ConversationTraversal.swift:169` marks an element clipped only when its rectangle does not intersect the inherited clipping rectangle. One-pixel strips at the viewport edge intersect and survive.
3. At line 185, only window, scroll-area and web-area roles establish clipping. This history is an AXList, and list/container semantics are not analyzed as a viewport. Adding AXList blindly would not by itself fix one-pixel intersections.
4. Children are consumed in their returned order. Focus priority gets to the correct pane, but does not prioritize usable visible history within it.
5. Blocks are retained first-come, first-served. Once 60 are present, later nodes use `metadata`, which intentionally does not request text. Old retained blocks are never displaced by better candidates.
6. Metadata-only traversal cannot repair source coverage. Later empty source groups are compacted away, so the backend does not even receive most of the local evidence that readable-sized text was skipped.

`visible_history_only` is currently added unconditionally. It is a scope label, not proof that retained text was visibly readable. Likewise `order` is traversal order, not a verified message timeline.

## Why jev-ultrafast has a better-shaped decision

The reference implementation constructs an indexed table of observed controls. It obtains names from DOM labels/ARIA/text, records roles and field state, filters controls using visibility and viewport geometry, and separately collects viewport-intersecting text. It does not use screenshots to make its default decisions. Its DOM access differs materially from our cross-process AX access. These checks are useful design examples, not proof that its visibility logic handles every nested messaging scroller. [snapshot.js](https://github.com/browser-use/jev-ultrafast/blob/main/jev_ultrafast/snapshot.js)

Its model input includes the goal, page text, element table and recent actions. Each operation gets only compatible target options, with descriptive labels and values. After choosing an operation, only the corresponding target answer can execute. It validates those answers but does not impose our universal 0.10 margin veto. [model.py](https://github.com/browser-use/jev-ultrafast/blob/main/jev_ultrafast/model.py)

It observes again after actions and can refresh stale state. Our reply analysis uses one frozen snapshot and at most two calls; Retry reuses that snapshot. The browser project's recovery opportunities therefore differ from ours. [agent.py](https://github.com/browser-use/jev-ultrafast/blob/main/jev_ultrafast/agent.py)

The repository documents small verified demonstrations, including three repeats per version of one flight task, and explicitly does not claim a general reliability benchmark. It has not demonstrated that it solves this exact LinkedIn reply scenario. [README](https://github.com/browser-use/jev-ultrafast)

## Format, questions, and application rules

### Transport is functioning

Our envelope uses structured `state`, typed `questions`, and the pinned `typesafe/jev-1.13` model through OpenRouter Decisions. This is a supported usage pattern. Both responses passed structural validation, conversation selection succeeded, and audience selection succeeded. The reference defaults to `jev-latest` through TypeSafe directly; this is not a controlled model-version comparison. There is no evidence here that a provider switch is the required fix. [OpenRouter's Jev documentation](https://openrouter.ai/blog/insights/what-is-jev/)

### The semantic unit is too small

`buildDetailQuestions` treats each classified AX text block as an independent message/target. In this export, one message is split into a salutation, prose, a section label, individual meeting times, a location and a closing. Date/time/separator nodes also require classification. The questions ask whether each fragment is a current incoming turn, even though many fragments only make sense as part of a complete message.

The state preserves low-level ancestry and coordinates but does not expose a compact message table with body fragment IDs, sender evidence, observed date/time and visibility/coverage status. The model must reconstruct those relationships repeatedly. Supporting link labels cannot become message body content under the present rule; this also excludes legitimate body hyperlinks, a separate limitation to preserve in future regression fixtures.

### Independent questions are not a reasoning chain

Audience, target, author and self-relationship questions run together in the detail call. A target answer cannot consume the author or relationship answer from that same batch. Stage-one kinds select which detail questions exist, but those decisions are not added as an explicit interpreted message structure to the detail state. The target question must independently infer older/self/current status from the raw evidence.

TypeSafe documents that questions are independent and that one answer does not become hidden context for another. Necessary dependencies must be represented in a later state or combined in code. It also recommends focused questions with explicit references to state fields. More questions alone are not evidence of model overload; the concern here is fragmented units and how their answers are combined. [TypeSafe primitives](https://docs.typesafe.ai/primitives)

### Abstention is broader than the product decision

`readDecisions` converts every answer with a top-two margin below 0.10 to `uncertain`. `interpret` lines 490–505 then rejects the whole reply if any possible message block has an uncertain target decision, or if a target has an uncertain kind. Even a clear current target can be vetoed by an unrelated older fragment that remains in the possible-message set. A later branch uses the same error for a target attributed to an explicitly self-marked participant.

The export records raw/effective audience decisions, but not target/kind/author decisions or the exact rejecting branch. Consequently it cannot establish which fragment triggered rejection, whether a target margin caused forced abstention, or whether self-authorship contradiction was the immediate trigger. The evidence-loss finding is conclusive; the precise model-level trigger is not recoverable from this export.

Thresholds are application policy and need domain-specific evaluation. Lowering them now could turn a visible failure into a reply to the wrong month. [TypeSafe confidence guidance](https://docs.typesafe.ai/confidence)

### The UI obscures the stage

`ReplyContextPanel.swift:169` distinguishes audience failures but otherwise uses the generic reply-context failure label. For this attempt, that wording hides successful field/pane detection and unsuccessful message selection. Recovery should distinguish missing current-message evidence from competing recipients or uncertainty about which request to answer.

## Offline checks performed

Two synthetic probes exercised production code without computer use or provider calls:

- Swift traversal: focused composer plus 60 one-pixel older fragments followed by a substantial visible message. Result: composer retained, all 60 older fragments retained, latest node visited through metadata only, no clipped nodes. One temporary XCTest passed. Probe saved at `/tmp/keigo-reply-analysis-probe.swift`; output `/tmp/keigo-reply-analysis-swift.log`. Temporary repository test removed afterward.
- Deno interpreter: an unequivocal current target plus an older fragment. With the older fragment classified as background, result was `ready`; with its target decision uncertain, result was `ambiguous_target`, despite current-target probability 1. This confirms the combination rule, not the unknown actual Jev answers from the user's attempt.

These are diagnostic reproductions, not claims that a fix has passed. No private message text was replayed to a provider.

## Recommended direction

1. **Fix evidence quality before changing prompts.** Collect bounded structural/visibility candidates before committing the text buffer; prefer substantial readable text inside the focused history. Keep window/pane isolation, editable-value exclusion, node/time/byte limits, and exact source provenance. Do not blindly discard every thin container or reverse every child list: thin parents can contain useful descendants, and AX order is not universal chronology.
2. **Make current-message coverage explicit.** Retain counters for edge-collapsed text, skipped readable candidates, and whether visible history was omitted due to text capacity. When the current turn is unavailable, report incomplete capture rather than sending stale history as if it were sufficient and asking the user to choose a recipient.
3. **Build bounded message/turn candidates.** Preserve exact original block IDs and text, but associate body fragments, observed sender labels and date/time evidence. Keep repeated text distinct, quotes separate, self identity evidence-based, and multiple related incoming messages possible. Expose observed order separately from inferred chronology.
4. **Ask directly about candidate turns.** Let Jev choose the current incoming turn or an evidence-backed set of related messages. Include a missing/uncertain option. Use descriptive candidate options and explicit state paths, and only allow material uncertainty about the chosen target or plausible competing targets to block generation. Do not remove genuine self/quote/recipient safeguards.
5. **Add bounded decision diagnostics before another live trial.** Record question/block IDs, raw/effective choices, margins, forced-abstention flags and exact rejection category for material decisions; no message text in server logs. Evaluate capture correctness separately from model decisions and policy outcomes.
6. **Validate against the failure shape, then manually verify.** Fixtures should include hundreds of older edge-collapsed nodes, current visible messages later in AX order, fragmented bodies, body links, nested scroll regions, explicit reply-to messages, self-authored last turns, groups, multiple panes and genuine ambiguity. Use anonymized fixtures for durable tests. Only then evaluate prompt/model variants on identical complete inputs.

No additional manual check is needed to establish the present root cause. A new manual capture will be needed after implementing the capture/representation changes.
