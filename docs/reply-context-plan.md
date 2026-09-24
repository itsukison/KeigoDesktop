# Reply with conversation context

Status: the first backend slice (contracts, validation, request routing, and writer rules) is implemented locally with offline tests. Matching Foundation models and parity tests are authored but uncompiled. Jev interpretation, native capture/UI, semantic evaluation, and enablement remain pending. Nothing from this work has been deployed. This document records source research and the intended complete behavior; see [implementation notes](reply-context-implementation.md) for the current boundary. **Do not compile, test, or run Swift until the Mac mini is available.** Build and validate the backend and fixture-driven logic first; native code can be authored behind a disabled development flag, with compilation and runtime verification explicitly outstanding. Button customization and the possible universal rewrite button remain separate work.

## Recommended interaction

Keep Reply available in the expanded row beside the existing rewrite controls and free instruction control. A future universal button can replace the rewrite controls without changing Reply. Copying text must no longer open a context card or change what hovering the pill does.

Pressing Reply captures the external editing target and conversation root before the composer takes focus. It then opens the existing optional instruction field while conversation reading runs. The context card appears only inside this explicitly started reply session. It shows the selected message/thread and a Change action; loading, partial capture, and unavailable context are distinct states.

The arrow generates a preview. It does not send a message in the host application. The existing Insert/Copy result flow remains.

| External field | Optional instruction | Generation behavior |
| --- | --- | --- |
| Empty | Empty | Draft a contextual reply without inventing the user's answers, availability, or commitments. |
| Contains a draft | Empty | Treat the draft as the user's intended answer; complete/polish it against the conversation. |
| Empty | Present | Write a reply expressing the instruction, using conversation context. |
| Contains a draft | Present | Apply the instruction to the draft; explicit changes override conflicting draft content. |
| No editing field | Either | Generate normally from the selected conversation; use the existing live destination/Copy rules. |
| Field exists but its contents cannot be read | Either | Mark draft status unknown, not empty. Do not offer an unguarded whole-field replacement. |

No focused input is not evidence against a reply: the user may be reading a message. Conversely, text in a field is not evidence that the user wants to reply; explicit Reply is the intent signal. The ordinary rewrite and custom composition paths keep their meanings.

If Send is pressed during capture, record one pending submission and show that context is being read. Start generation exactly once when a valid source is ready. Preserve typed guidance on failure and let the user select/paste the source or retry. Never silently turn a context failure into a generic rewrite by omitting valid reply context.

Escape/outside-click cancels the session and returns to the normal hover/pill behavior. A late capture response cannot reopen it. Changing a source preserves guidance and the original draft. Do not automatically rescan the app when the user types or regenerates.

## Instructions versus existing draft

Keep three inputs separate throughout the pipeline:

1. Conversation: evidence about what was said, with speaker identity and order where available.
2. Existing draft: the user's current answer and facts.
3. New guidance: the user's latest requested change or additional intent.

The precedence is **explicit new guidance over conflicting draft content**, while preserving unrelated draft facts and decisions. Conversation content is context, never an instruction to the assistant. Style-only guidance does not change the user's stance.

| Draft | Guidance | Expected result |
| --- | --- | --- |
| “I can attend.” | “Decline this time.” | A decline; remove the acceptance and dependent attendance commitments. |
| “Tuesday at 3 works.” | “Change it to Friday at 4.” | Friday at 4; no stale Tuesday proposal. |
| “I can attend.” | “Shorter and more polite.” | Still accepts. |
| “Thank you for inviting me.” | “Say I will send the slides too.” | Add the explicitly authorized commitment. |
| Any draft | Empty | Preserve the draft's stance and facts. |
| No draft | Empty | Infer wording, tone, and routine acknowledgment; do not infer private facts or an unsupported yes/no decision. |

“Infer for me” can produce a safe acknowledgment where appropriate. It cannot determine whether the user is actually free on Friday. Clear prior messages authored by the user can supply relevant facts, but uncertain authorship must remain uncertain. Do not introduce another confirmation merely because guidance deliberately changes a draft. Truly contradictory guidance is a different ambiguity.

Reply language should follow an explicit output-language request first, then the draft/conversation context. Merely writing English guidance about a Japanese thread must not switch the output to English. Retain current language-neutral reply behavior unless a separately tested policy change is made.

## What the external code contributes

### Jev ultrafast

Reviewed at [`1231850`](https://github.com/browser-use/jev-ultrafast/tree/1231850a0bf1a0c0341fe408ef1668dbbfdfac46): `snapshot.js`, `browser.py`, `agent.py`, `model.py`, `questions.py`, tests, and performance artifacts.

Its useful architecture is a compact observation with concrete candidate IDs, one batched decision request, and deterministic validation before acting. The browser snapshot collects visible text and controls; the model chooses among supplied options. Freshness and node identity are checked in code. We should apply the same pattern to selecting conversation context, with no browser-control action loop.

The example controls its own browser tab through CDP. It is not a cross-application macOS screen reader. Its confidence handling validates probability shape and records confidence, but is not a ready-made low-confidence abstention policy for our app. Its recorded fast timings are measurements of that demo, not an end-to-end latency promise for Accessibility capture, our Edge Function, and reply generation. [Source code and measurements](https://github.com/browser-use/jev-ultrafast/tree/1231850a0bf1a0c0341fe408ef1668dbbfdfac46/docs).

Jev currently accepts text, not screenshots. TypeSafe also says English accuracy is strongest and CJK requires workload-specific testing. Therefore “read the screen via Jev” actually means extract structured text first, then use Jev for a narrow decision. [Model documentation](https://docs.typesafe.ai/models).

Use Jev to choose a relevant conversation candidate, distinguish message content from UI chrome, and abstain when uncertain. Do not use it to decide whether an explicitly requested Reply is a reply, generate the actual answer, calculate dates, or select an insertion target. Filter unrelated UI before sending it; maintain an explicit unknown option and validate selected IDs in code. These choices also match the provider's documented limitations around irrelevant state, indirection, adversarial input, and generation. [Known limitations](https://docs.typesafe.ai/model-jaggedness/jev-1.13).

### Native Accessibility implementations

| Source reviewed | Useful pattern | Adaptation required here |
| --- | --- | --- |
| [AXorcist traversal](https://github.com/openclaw/AXorcist/blob/4012a2f04487ed529c5603760cdaff58fb1553eb/Sources/AXorcist/Search/AXTreeTraversal.swift) and text extraction | Identity-aware traversal, cycle handling, pruning, depth/time limits, explicit traversal outcome. | Keep AX work off our main actor. Do not flatten all text into one string or copy raw-text debug logging. Its Swift 6.2/MainActor package is not a drop-in dependency for our Swift 5.9 boundaries. |
| [Screenpipe macOS tree reader](https://github.com/screenpipe/screenpipe/blob/d4f360862fca15cc58666f27c92764f1c77ca1f5/crates/screenpipe-a11y/src/tree/macos.rs) and [batch benchmark](https://github.com/screenpipe/screenpipe/blob/d4f360862fca15cc58666f27c92764f1c77ca1f5/crates/screenpipe-a11y/examples/macos_axbatch_bench.rs) | Batched attribute reads, per-attribute error handling, bounded traversal, truncation reasons; benchmark batching on the same retained nodes. | Window intersection alone does not prove visibility inside a scroll view. Preserve unknown geometry. Scope to a content root so deep Electron wrappers do not consume the entire depth budget. |
| [macOS-use MCP server](https://github.com/mediar-ai/mcp-server-macos-use/tree/b5b9b9d71b9514d87a7f21f070aeca1119a6d0c9) and its [SDK traversal](https://github.com/mediar-ai/MacosUseSDK/blob/a2d7866355bca07faf476c5d180c8664b1992f8c/Sources/MacosUseSDK/AccessibilityTraversal.swift) | Bounded breadth-first traversal and ranged child retrieval rather than fetching arbitrarily large child arrays. | SDK activates the target app, explores application windows, merges text attributes, and uses geometry as visibility. Our reader must not activate apps, mix windows, lose authorship/order, or deduplicate distinct messages by text/geometry. |

The installed Apple SDK confirms `AXUIElementCopyMultipleAttributeValues` supports collecting attributes in one call and can return per-slot errors or nulls. A successful batch is not proof that every attribute was read. Use `AXUIElementCopyAttributeValues` for bounded child ranges. Implement the small required reader against Apple APIs; do not import any of these complete automation frameworks. Check licenses before copying source.

## Proposed capture and model pipeline

```text
Reply press
  -> capture external target, PID, window/content root, selection
  -> open optional instruction composer
  -> bounded AX snapshot from the retained external root
  -> local candidate grouping/filtering
  -> authenticated context endpoint -> one Jev selection call if needed
  -> validate candidate IDs and source completeness
  -> selected conversation preview
  -> submit draft + guidance + selected conversation to existing writer
  -> result preview -> existing destination validation -> Insert/Copy
```

### Capture

- Capture the target/root before taking key focus. Never rediscover the frontmost app after our composer opens. Keep source and insertion destination separate.
- Add a focused-window/content reader under `Sources/TextIO`, using the existing AppKit bridge for app/window metadata. Retain the `AXManualAccessibility` priming policy and 0.5-second per-element timeout. Do not add `AXEnhancedUserInterface`.
- Run traversal serially off the main thread with cancellation/session checks between calls. A traversal deadline cannot interrupt an already-blocked synchronous AX call; stop before issuing more calls once the deadline is exceeded.
- Preserve role, parent/group identity, text source attribute, order, selected status, bounds/visibility evidence, and read errors. Deduplicate repeated attributes from the same element, not identical messages from different elements. Missing text is not an empty draft.
- Exclude secure fields and unrelated chrome. Prefer the conversation region associated with the captured composer or explicit selection. If no field is focused, scope to the active window's conversation candidates. Multiple plausible threads require source choice rather than silently using the last text node.
- Use visible children/ranges and scroll-container clipping when supported. Record partial/unknown capture; offscreen history may be unavailable. Do not scroll, click, expand threads, or switch tabs to obtain more context in this feature.
- Starting experimental bounds: 500 visited nodes, 200 children per retrieval, 12,000 aggregate context characters, and a 1-second traversal scheduling budget. These are tuning parameters, not measured guarantees; profile against real apps before fixing them. Preserve the selected message when pruning supporting history.
- If AX does not expose the message, offer explicit paste/select fallback. Screenshot/OCR would be a separate capture adapter with additional permission and coverage work; Jev itself does not supply OCR.

### Selection

Create a pure `ConversationSnapshot` containing candidate IDs, grouped message blocks, observed speaker labels, ordering, capture quality, and source metadata. Keep AX handles/PIDs local; provider input uses opaque session-local IDs. Candidate construction, text size limits, and IDs are deterministic.

Known, unambiguous sources can bypass Jev. Otherwise ask one narrow choice over available candidate IDs plus `uncertain`/`no_conversation`. If authorship needs classification, batch that narrow question with the same snapshot and permit `unknown`. Reject unknown IDs, invalid probabilities, incompatible groups, and malformed responses. Choose thresholds using labeled Japanese/English/Chinese cases; do not assume a generic probability such as 0.8 proves correctness.

The model selects evidence already captured. It must not create a message, sender, timestamp, or destination. Preserve labels as observations rather than treating a string that says “me” as verified account identity. Keep context-quality status independent of model confidence: high confidence cannot make truncated history complete.

### Backend and request contract

Use a dedicated authenticated `desktop-reply-context` endpoint for the bounded selection request. Keep the provider secret server-side and preserve verified user-JWT authentication. Give this endpoint its own bounded request/rate/cost controls; opening a composer must not inadvertently consume the existing rewrite reservation twice. [Edge Function authentication](https://supabase.com/docs/guides/functions/auth).

The existing writer assumes `replyTo` is a message from another person. Do not put a mixed thread into that field or require one incoming message to represent a group conversation. Introduce a versioned, desktop-only `replyContext` envelope containing participants, messages, reply targets, audience, and uncertainty. Its presence selects the new reply path; legacy `replyTo` continues to select the old path. New clients send one representation, not both. Reject malformed, unsupported-version, or conflicting representations instead of falling through to compose/rewrite. Validate aggregate size and all ID references at the backend. Keep shared iOS field semantics/defaults and response contracts intact.

Update `prompt.ts` to express draft/guidance precedence and speaker provenance. Escape all source content and label it as untrusted evidence. Keep the normal generative model for writing; Jev interprets captured evidence. Absence of a usable reply target must produce a context error, not fall through to ordinary composition. A selected target can include several messages; do not assume that the last speaker, the addressee, and the audience are the same person.

Keep candidate trees ephemeral. Existing rewrite-event logging already captures the selected source under the repo's redaction policy; do not automatically extend that to entire trees or all conversation history. Operational metrics should include timings, capture quality, source changes, unknown outcomes, provider version, and failures without raw screen text. Freeze chosen context in the reply session and result page for regeneration/refinement.

## Local code change map

| Area | Current behavior / required change |
| --- | --- |
| `App/Overlay/PillRootView.swift` | Reply already permits an empty instruction. Add explicit Reply to the hover row; keep the composer stable while context status changes so `@State` text is not lost. |
| `App/Overlay/OverlayController.swift` | Replace `startClipboardWatching`/`armReply` trigger flow with explicit entry. Preserve capture-before-key ordering. Adapt submit, cancel, regeneration, refinement, and late-result guards to a session ID and frozen context. |
| `App/Overlay/OverlayState.swift` | Remove the parallel resting `.replyArmed` state. Represent loading/ready/needs-source inside an explicit reply session. Update layout, key-window policy, reply helpers, pending/page models, and update-check eligibility. |
| `App/Overlay/ReplyContextPanel.swift` | Show only during the explicit session; add source state/Change without reviving unbounded intrinsic-height problems. |
| `Sources/TextIO/AXTextIO.swift` | Current reply policy compares selection with copied text. Replace that heuristic with explicit source identity and draft provenance. Keep whole-draft capture, scratch support, and independent write strategy; distinguish unreadable from genuinely empty. |
| New `Sources/TextIO/AXConversationReader.swift` | Bounded scoped traversal, batched attributes, local element identity, cancellation and completeness. Keep existing focused-field capture lightweight. |
| `Sources/DesktopRewriteKit/Reply/ReplySource.swift` | Current minimum 12 characters and 180-second lifetime belong to unsolicited copy arming. Replace with explicit-source/session models; short messages such as “明日？” are valid. |
| New pure Reply models/service | Snapshot, selected context, draft-read status, provider decision validation, and context service. Reuse authentication narrowly without broadly refactoring the rewrite service. |
| `Sources/DesktopRewriteKit/Models/RewriteModels.swift` | Add optional desktop-only `replyContext` while preserving the copied iOS contract, existing defaults, legacy `replyTo`, and response format. |
| `supabase/functions/desktop-rewrite/prompt.ts`, `index.ts` | Add precedence/role-aware prompting and bounded structured parsing. Existing preservation wording currently makes a changed decision conflict with the old draft. |
| `App/Overlay/ClipboardWatcher.swift` | Remove unsolicited reply watching. Preserve self-write suppression/clipboard restoration still used by other text I/O and copy paths. |
| `App/Main/PreferencesSheet.swift`, `MainModel.swift` | Replace copy-triggered Reply descriptions and settings; migrate stale watcher preferences so upgrades do not retain the old trigger. |
| Onboarding controller/visuals | Replace copy-to-arm teaching with press-Reply/read-context practice. Preserve tutorial identity and completion on actual insertion; use the known training conversation deterministically. |
| `AGENTS.md` §§4, 10, 15, 16, 18 | Update current architectural guidance in place when implemented. Do not rewrite it now as though the proposal shipped. |

The referenced sibling `context-service.js` prototype was not located in the available workspace search, so this plan does not rely on its implementation.

## Build plan while native execution is unavailable

### 1. Define the evidence and writing contracts

Build first: pure TypeScript types, runtime validators, and checked-in JSON fixtures under `supabase/functions/_shared/reply-context/` and `Tests/Fixtures/ReplyContext/`. Author matching Foundation-only models under `Sources/DesktopRewriteKit/Reply/`; their encoding/decoding tests wait for the Mac mini. The same fixtures must eventually be decoded on both sides rather than maintaining two independently invented contracts.

Use two distinct data structures:

| Structure | Required contents |
| --- | --- |
| Captured evidence | Snapshot/session ID; bounded source blocks with opaque IDs, exact text and observed attributes; grouping/order evidence; capture status and truncation reasons. Platform handles remain local. |
| Validated `replyContext` v1 | Snapshot ID; participants; messages referencing source blocks; selected target message IDs; audience; completeness and material uncertainties. |

Each participant has an ID, an optional observed display label, and a `self`/`other`/`unknown` relationship with evidence references. A profile display-name match alone does not prove that a chat participant is the current user. Do not merge two people solely because their display names match.

Each message has an ID, original text, an optional participant ID, source-block references, observed ordering, and any evidenced quote/reply relationship. Missing speaker identity stays unknown. Quoted text does not inherit the containing message's authorship. If a source block mixes a message and a quote without a reliable boundary, retain that uncertainty instead of inventing a split. Jev may select existing blocks or precomputed spans; it must not rewrite the text or invent offsets. Code owns range checks and reassembles exact source text.

Audience is separate from speaker: `direct`, `group`, or `unknown`, with participant IDs only where supported. Reply targets can contain more than one message. A direct @mention does not make the entire group thread a private conversation. Do not infer chronology merely by lexically sorting displayed dates, or infer a recipient merely from the latest speaker.

Draft content remains `text`; guidance remains `prompt`. Add a desktop draft-read status distinguishing `present`, `empty`, `unreadable`, and `no_destination`; an unreadable draft cannot be treated as permission to replace an unknown field. Keep destination handles and write authorization outside model-visible context.

Deliverable: validated example payloads for direct chat, group chat, quoted email, and ambiguous context, plus invalid fixtures for broken references and conflicting request formats. **Done when:** validators pass the positive fixtures, reject invalid/oversized input, preserve exact text, and never convert missing information into a known identity or empty draft.

### 2. Fix writer assumptions and instruction precedence

Update `desktop-rewrite/prompt.ts` and request parsing to consume validated structured context. Keep legacy reply requests working and ordinary rewrite/compose behavior unchanged. Apply the explicit-guidance-over-conflicting-draft rule to both reply paths.

The new prompt must distinguish the authenticated account user from observed conversation identities, authors from recipients, quoted statements from current messages, and selected targets from background history. Supply exact source content with structured labels rather than a free-form Jev summary. Unknown names should normally produce a name-free reply; ambiguity about which conversation is intended should block generation for source selection.

Audit every existing use of `replyTo`, not only prompt generation: reply branching, history display, result refinement/regeneration, event classification, and selected-source logging must recognize the new representation. Use selected target text for any legacy display/logging projection; do not serialize the whole thread into an existing single-message field. Preserve the existing redaction policy and billing request identity.

Deliverable: deterministic parser/prompt tests for both formats, including malformed new context with empty `text`, multiple speakers, mixed-language instructions, and acceptance-to-decline changes. **Done when:** routing cannot silently degrade into generic composition and the prompt carries each role/target explicitly. Passing prompt tests does not claim generated replies are correct; semantic evaluation is step 4.

### 3. Build the Jev interpreter behind an injectable provider

Add `desktop-reply-context` with a small provider interface, a fixture provider for offline tests, and a server-side Jev adapter. Do not require native capture to call it: feed the captured-evidence fixtures through the real validator and decision pipeline.

Separate the judgments: relevant conversation, message versus UI/quote, speaker assignment, current-user relationship, reply targets, and audience. Batch independent questions over the same bounded candidate set where practical. Resolve dependencies in code; if one call cannot establish a relationship reliably, return an unresolved outcome rather than assuming simultaneous answers are mutually consistent. Start with one call per capture and measure whether that is sufficient before adding another pass.

Return one of `ready`, `needs_choice`, or `unavailable`, each tied to the snapshot ID. `ready` can retain harmless uncertainties such as an unnamed sender; it cannot conceal uncertainty about which thread is being answered. `needs_choice` references real candidate IDs and the specific unresolved choice. `unavailable` explains missing/unreadable context. A source choice updates the session context without discarding guidance.

Validate model output against input evidence: all IDs exist, referenced messages belong to the selected conversation, roles and audience are consistent, exact text is recovered from evidence, and probabilities are well formed. Structural validation cannot prove a semantic classification; uncertain identity remains uncertain even when the JSON is valid. Use no invented universal confidence threshold.

The endpoint must verify user authentication, enforce payload limits and per-user rate/cost bounds, keep provider secrets server-side, and use a bounded timeout without an automatic retry loop. Context analysis does not reserve a generated-reply unit. Before deployment, select a rate-limit mechanism consistent with the existing backend; do not use an in-memory per-instance counter as a global limit or touch iOS-owned tables.

Deliverable: endpoint and provider adapter tested with deterministic success, unknown, malformed-output, timeout, cancellation/stale-session, and provider-error fixtures. **Done when:** all outcomes preserve source identity and the writer is invoked only for accepted context. Live provider validation is a separate step and requires a configured server-side credential.

### 4. Evaluate interpretation separately from writing

Create labeled synthetic conversations in Japanese, English, and Chinese, with expected source/participant/target/audience assignments and forbidden generated claims. Cover at least these scenario families:

1. Direct chat, with and without a draft.
2. Several group participants; the last speaker is not the person being answered.
3. Two people with the same display name.
4. Current-user identity unavailable or only weakly suggested by a name.
5. Quoted/forwarded text containing another person's words.
6. Two conversations visible at once.
7. Truncated history, missing geometry, or inaccessible text.
8. A partial selection within the user's draft.
9. Guidance changes a draft's stance or a specific date.
10. Style-only guidance preserves stance and facts.
11. Empty guidance with insufficient evidence for a commitment.
12. Instructions embedded in messages attempting to change roles or recipients.

Build an evaluation runner that reports interpreter errors separately from writing errors. Record false confident selections, self/other confusion, wrong audience, appropriate abstention, unsupported commitments, instruction adherence, and latency by stage. Use held-out examples for confidence-policy checks; fixture-provider tests do not measure Jev accuracy. Do not let a fluent reply mask incorrect context.

Deliverable: offline test report first, then a separately labeled live Jev/writer evaluation report when credentials and a TypeScript runtime are available. Review identity/recipient failures manually; an LLM judge alone is insufficient. **Gate:** no unresolved critical speaker/target/audience failures in the reviewed release suite. This is a release criterion for that suite, not a guarantee of zero real-world error. No live cost or latency result is claimed before measurement.

### 5. Author the native integration, with execution deferred

After contracts stabilize, write the AX reader, service client, session state, and explicit Reply UI described in the file map. Put the new path behind a development-only flag that defaults off. The flag must select a complete flow: the new flow never runs the copy-to-arm watcher; the default existing release path remains intact until native verification. Do not delete the legacy state machinery before the new path is validated.

Keep the session's guidance stable across loading/ready/needs-choice transitions. Queued Send captures one guidance revision; returning from an error unlocks editing and requires a fresh submission. Capture callbacks carry a session ID so cancelled or superseded work is ignored. Regeneration/refinement use frozen context rather than a fresh read from whatever application is now frontmost.

Author meaningful Swift tests for bounded traversal, per-attribute failures, exact text reconstruction, serialization parity, stale sessions, unknown draft contents, and destination behavior, but **do not run Swift, `swift test`, Xcode builds, or native probes** until the Mac mini is available. Static review and TypeScript fixture validation cannot establish that the Swift code compiles or the UI behaves correctly.

Deliverable: reviewable native implementation with an explicit list of uncompiled/untested paths. **Done for this phase means authored and reviewed, not validated or releasable.**

### 6. Resume on the Mac mini and enable only after verification

Compile and run the native tests, verify the shared fixtures from Swift, and test capture-before-focus, multiline composer stability, cancellation, source selection, result insertion, and clipboard restoration in real apps. Tune traversal budgets from measurements and compare Jev interpretation against observed source truth.

Only then enable the new flow, retire automatic copy arming, migrate preferences, update onboarding/localization, and revise `AGENTS.md` in place. Retain a controlled rollback until the release has demonstrated coverage. No production deployment or release is part of the current planning task.

### Execution checkpoints

| Checkpoint | Can author now? | Can validate before the Mac mini? |
| --- | --- | --- |
| Context contracts, validators, JSON fixtures | Yes | TypeScript side; Swift parity deferred. |
| Backend routing, prompts, provider adapter | Yes | Offline tests once a compatible TypeScript/Deno runtime is available. |
| Live Jev and writing evaluations | Yes, runner and cases | With server-side credentials and runtime; never substitute mock results. |
| Foundation models and native AX/UI code | Yes, after contract stabilization | Review only; no compilation or execution. |
| Focus behavior, actual app coverage, insertion | Test cases can be written | No; Mac mini required. |
| Enablement and release | Plan only | No; requires the native and semantic gates above. |

The first implementation slice should contain **steps 1 and 2 plus their offline fixtures/tests**. This corrects the existing assumptions and establishes the interface that both Jev and native capture will use, without making implementation depend on an unavailable machine. Deno was unavailable during the preceding investigation; verifying/provisioning a compatible backend test runtime is an explicit prerequisite, not an assumed completed check.

## Acceptance coverage

Required automated cases: unknown versus empty draft; selected incoming text versus selected draft; duplicate messages; mixed speakers; multiple threads; clipped/deep/cyclic trees; unsupported attribute slots; traversal limits; invalid model IDs; abstention; cancellation; send while loading; text retained after error; late response from an old session; frozen context on regenerate/refine; and source failure never becoming ordinary rewrite. Preserve existing destination and clipboard-order tests.

Prompt string assertions alone do not establish semantic correctness. Add labeled generated-output evaluations for accept-to-decline, date replacement, style-only changes, no invented commitments, mixed languages, quoted prompt injection, and unknown authorship. Evaluate selection separately from writing so a good reply cannot hide a wrong source.

Manual coverage: native Mail, Gmail in Chrome/Safari, Slack, a second Electron messenger, no focused input, an empty composer, a partial draft selection, two open conversations, an AX-poor app, and a hung target. Measure capture, selection round trip, time until source preview, and total generation separately. Copying arbitrary text must produce no overlay change. No automatic external send, tab switching, or unrelated text replacement is allowed.

No live Jev accuracy/latency benchmark or real-app capture validation was performed for this research. The external repositories supply implementation patterns, not verified coverage for this app.
