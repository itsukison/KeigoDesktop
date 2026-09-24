# Reply context: first implementation slice

The backend now accepts structured context and corrects the existing legacy reply writer rules. This is steps 1–2 of the build plan, with native parity validation deferred. It does not yet read a screen, invoke Jev, add a Reply button, or disable copy arming. No deployment was performed.

## Contract

`supabase/functions/_shared/reply-context/types.ts` defines captured evidence separately from `ReplyContext` v1. Matching Foundation types live in `Sources/DesktopRewriteKit/Reply/ReplyContext.swift`; these are transport models, not a Swift validation implementation.

The structured request sends `replyContext`, `draftReadStatus`, optional guidance in `prompt` (an empty string is valid), and draft content in `text`. Omit `replyTo`. Old clients keep sending `replyTo`; rewrite/compose retain their default candidate count and existing response format. Explicit null or malformed `replyContext` is an error, never a compose request.

Source blocks carry opaque IDs, conversation IDs, observed traversal order, exact text and optional role/parent attributes. Order is observed order, not a timestamp-derived chronology. V1 uses whole presegmented blocks; message text must equal its source blocks joined with one newline in source order. Span extraction is not implemented. Capture must retain uncertainty when it cannot separate a quoted region safely; it must not invent a boundary. Parent IDs, when supplied, must reference included blocks; a bounded capture may omit a parent attribute rather than retain a dangling reference.

Participants retain separate IDs even when labels match. Self identity requires `self_marker` or `account_identifier` evidence; a profile-name match alone is rejected. These evidence kinds are interpreter assertions grounded in source IDs, not independently verified identity credentials. Before a future interpreter returns context, it must validate all output against the original captured snapshot, not a model-authored copy of the source blocks. Runtime validation here proves structural consistency and exact source reconstruction, not semantic correctness or authenticity.

Messages distinguish their author from a quoted author and the quote's containing message. Targets are separate from audience. Targeting an earlier or self-authored message is permitted. A direct audience can have an unnamed recipient; a group need not enumerate everyone. Unknown audience or material uncertainty blocks generation with `reply_context_needs_choice`. Uncertainty about conversation, target or audience cannot be labeled non-material. Harmless unknown speaker labels can proceed without guessing a name.

Draft status distinguishes `present`, `empty`, `unreadable`, and `no_destination`. The last three require blank `text`, but retain their distinct status. This field does not authorize insertion; native destination guards still must prevent replacing an unreadable field.

Limits: 96,000 UTF-8 bytes of serialized context, 12,000 aggregate UTF-16 source units, 200 source blocks, 100 messages, 30 participants, bounded evidence references and labels. Both the raw source and reconstructed messages count toward serialized size. Draft/guidance retain existing endpoint limits. Unknown contract fields and unsupported versions are rejected. These are provisional cost bounds, not measured capture performance targets.

## Routing and retention audit

| Consumer | Current status |
| --- | --- |
| Parser | Pure `desktop-rewrite/request.ts`; validates new context before provider/quota execution. Preserves trusted profile boundary and billing request ID. |
| Writer | Both reply forms share corrected precedence. Structured messages, targets, audience and uncertainties are serialized as escaped data; raw source blocks are not duplicated in writer input. |
| Identity fetch and operational reply flag | Recognize either reply representation. |
| Event classification | Reply fallback when the client omits the type; explicit regenerate/refine type is retained. |
| Reply source log | Selected target text only, in observed order, through existing PII redaction. Background messages/source trees are not added to stored event text. |
| Foundation request | Additive optional fields, nil by default; existing shared fields/defaults/results unchanged. |
| Overlay pending request, history, result labels, regenerate/refine | Still legacy-only. During native integration, carry the frozen `ReplyContext` and draft status through `PendingRewrite` and every `startRewrite` call; use `selectedTargetText` for history/preview and either representation for reply classification. Do not enable structured capture before this is complete. |

## Verification

Backend tests cover JA/EN/ZH fixtures, duplicate display names, unknown authors, quote ownership, earlier and multiple targets, malformed/oversized input, broken references, altered text, conflicting formats, empty guidance, distinct draft statuses, prompt injection escaping and both reply formats' precedence. These tests verify contracts and instructions; they do not measure model accuracy or prove generated answers obey them.

Run from the repository root with Deno 2:

```sh
deno test --allow-read=Tests/Fixtures/ReplyContext supabase/functions/_shared/reply-context/validate_test.ts supabase/functions/desktop-rewrite/prompt_test.ts supabase/functions/desktop-rewrite/request_test.ts
deno check supabase/functions/desktop-rewrite/index.ts
```

An isolated Deno 2.5.6 runtime was provisioned under `/tmp/keigo-reply-tools` for local verification; it is not a project dependency. Swift parity tests consume the same JSON fixtures but have not been run. Do not run Swift, Xcode or native probes until the Mac mini is available.

Local result: 50 backend tests passed; `deno check` passed for the complete rewrite endpoint; lint passed for the context modules, extracted parser, request tests and writer prompt. No live provider calls or database changes were made.

Next: implement the injectable interpreter and Jev adapter, auth/rate limits for its endpoint, snapshot-bound output verification, and independent semantic evaluations. Then author the native session/capture/UI integration behind the default-off development flag. Capture provenance will need per-attribute read errors, visibility/clipping and geometry in the capture layer before app coverage can be assessed; v1 text blocks alone cannot establish visibility.
