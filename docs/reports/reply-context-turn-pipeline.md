# Reply Context: visible history and normalized turns

## Problem and implementation

The second LinkedIn export retained the correct composer and pane, but spent all 60 text slots before reading current history. Forty-eight retained history fragments had one-pixel rectangles. Sixteen later static-text nodes had substantial rectangles but only metadata was collected. An offline synthetic reproduction demonstrated the same loss. The old per-fragment target rule could also reject a clear incoming message solely because an unrelated fragment remained uncertain.

The implementation changes the data pipeline rather than the model provider or the 0.10 margin:

1. **Discover, rank, then read.** The existing retained-window/focus traversal gathers bounded metadata first. It reserves 35% of the one-second scheduling allowance for text reads. Text needs at least 6 pt visible height and 4 pt visible width when geometry is available. Thin group wrappers are not pruned: visible children remain discoverable. Selection uses focus ancestry priority, known geometry, horizontal overlap above the composer, proximity, and visible area. Retained blocks are restored to observed traversal order for exact provenance; that order is never represented as chronology.
2. **Detect missing coverage.** Near-composer text that was discovered but could not be retained, or absence of readable nearby history with a known focused composer, reports `missing_current_history`. The UI asks to show recent messages and press Reply again. Retrying the frozen capture is disabled. Counters distinguish clipped candidates, text candidates, value reads and skipped current text. Existing old-v3 captures with only collapsed history are also rejected before Jev/quota work.
3. **Normalize before Jev.** `turns.ts` creates a capture-independent `ConversationTurn` model with source IDs, exact joined text, observed order, bounds, visibility, boundary reliability and composer-relative position. AX groups under list/outline/scroll history containers provide item boundaries; inline links join their message. Adjacent history items and duplicate messages remain separate. Missing structural boundaries remain `unresolved`; proximity alone does not merge speakers. Sender/timestamp/self fields begin unknown. The provider sees exact ID-bearing fragments inside each candidate, once, plus separate supporting labels.
4. **Compose semantic decisions.** The first batch chooses the conversation, classifies whole turns and associates explicit sender evidence. The second receives these interpretations as state, then chooses one anchor and separately includes relevant background turns. Self turns may be background. Independent heads do not pretend to see other answers from their own batch. An uncertain unused turn is excluded rather than vetoing the anchor. A close anchor competition, uncertain/quoted anchor, self-authored anchor or uncertain audience still blocks generation.
5. **Preserve the writer contract.** The existing v2 writer context already separates `targetMessageIds` from other `messages`. The selected anchor is the sole target; selected supporting turns remain messages, including self-authored turns. Group threads retain group audience. A separate thread subtype and parsed timestamp field are not required by the current writer and are not inferred. Legacy v1/v2 captures retain compatibility with their existing interpreter.
6. **Explain the result.** Explicit exports carry message candidate IDs and source membership (exact text remains in evidence), boundary/visibility, anchor ID, context IDs, raw/effective choices, margin and forced abstention, and the precise rejecting head. Backend logs omit arbitrary source IDs and decision details that could contain private content. No private saved capture was sent to a provider during verification.

## Future DOM adapter

**Superseded direction:** DOM-first browser capture is now the agreed next implementation
priority. See [planning handoff](../reply-context-dom-planning-handoff.md) and AGENTS.md §16.
The following paragraph records the earlier deferral, not current guidance.

A browser adapter is useful but not necessary to fix this failure. `ConversationTurn` and `TurnInterpretation` separate capture structure from semantic selection. A future DOM adapter should provide the same source provenance and exact text, real message boundaries, sender/timestamp evidence, visibility and composer association. It should replace the AX normalization input for that snapshot, not fork the Jev policy.

Proposed transport: an opt-in extension content script reads the active conversation; its service worker communicates with a registered native-messaging helper; the helper returns a bounded snapshot to KeigoButton. Chrome requires a native host manifest and extension `nativeMessaging` permission; content scripts relay through the service worker. See [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).

Pair every response with the captured browser window/tab/navigation identity and Reply attempt. A stale response must not replace the current target. Exclude drafts/editable and secure values, validate the payload at the native boundary, and keep capture read-only. When the extension is absent, unavailable or unsupported, use AX. DOM visibility still requires nested-scroll and virtualization checks; DOM is not automatically correct. Vision would be a separately scoped fallback with its own permission/provenance limitations, not an automatic addition here.

The staged interpretation follows TypeSafe's documented [independent questions](https://docs.typesafe.ai/primitives): previous answers must be explicitly passed into a later state. Tests use deterministic providers to verify policy and contracts, consistent with [Supabase function testing guidance](https://supabase.com/docs/guides/functions/unit-test); this does not establish live Jev accuracy.

## Limits and owner checkpoint

The 500-node cap and time cap remain. Extremely deep/large or changing trees can still omit content. Unknown geometry stays lower-priority evidence; structurally unclear fragments remain unresolved. The 300 pt near-composer coverage band is an operational heuristic, not a universal chronology detector. Automatic sender parsing is intentionally conservative and preserves unknown identity. Real app semantics still need the owner's manual check.

Stop and Run the Debug app, open the same LinkedIn conversation, focus its reply field, press Reply, and export a fresh JSON even if it succeeds. Verify that the visible current message is present, the selected anchor belongs to it, and relevant prior/self turns are context. Test a Slack-style multi-turn conversation as well. An in-session Retry reuses the old snapshot and cannot verify capture changes.

## Verification

- Clean Swift suite: **317 passed**, including four new capture regressions and two new session/diagnostic tests. The first full run identified missing backward-compatible decoding defaults; the new counters are optional. An incremental binary subsequently crashed while copying the changed capture model. A fresh `/tmp/keigo-reply-turns-clean` build passed the full suite; a clean Xcode build was also required and completed.
- Deno interpreter/handler/contracts: **63 passed**, including nine new turn/anchor/context/coverage regressions. The maximum CJK/region fixture fits both actual provider envelopes. `deno check`, `deno lint`, formatting and `git diff --check` passed.
- **Clean Debug Xcode build succeeded.** The app was not launched or driven by automation.
- Deployed only **desktop-reply-context v7**, `ACTIVE`, `verify_jwt=true`, revision `capture-v3-turns-1`. All seven deployed runtime files match tested local source. Type-only dependencies are removed by the deployment bundler. Prior v6 bundle retained at `/tmp/keigo-reply-context-v6-rollback.json`.
- Live unauthenticated POST returned **401**. No private capture was replayed to Jev; authenticated live semantics remain the owner checkpoint.
- Existing unrelated working-tree changes and `reply-diagnostics.json` were preserved. No commits were made.

Logs: `/tmp/keigo-turns-clean-swift.log`, `/tmp/keigo-turns-deno.log`, `/tmp/keigo-turns-clean-build.log`.
