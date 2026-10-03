# Focused conversation capture correction

Implementation completed on `reply-context-v1`; live native capture verification remains pending with the owner. No computer-use checks were performed.

## Changes and effects

- Retained ancestry now walks up to 64 nodes within the existing 250 ms scheduling budget, with explicit root/depth/time/cycle/unavailable-parent outcomes. Full chains take priority. Partial chains supply direct edges only after their top node is encountered from the retained window.
- Focus-path work outranks generic pane rotation, and neighboring branches are read from inner ancestors outward. This preserves main-pane messages and headers before unrelated sidebar text fills the buffer.
- A full text buffer switches to metadata-only sampling instead of ending all discovery. The shared 500-node/one-second scheduling limits remain. Editable and secure values remain excluded; individual AX calls still have their 0.5-second timeout.
- Temporary structural regions share the node budget. Empty group leaves and single-child group wrappers without owned evidence are compacted before the existing 120-region wire cap. Unretained branches are discarded with their blocks/observations instead of being merged into a parent.
- Search controls/subroles and generic single-line fields are structural observations. Multiline editing fields are composer observations. Neither designation is a claim about the audience or authorization to insert.
- Equivalent v3 candidates favor a specific pane retaining an editing anchor. Candidate projection and manual scope retain text-free field metadata; broader equivalent wrappers no longer accumulate unrelated supporting controls.
- Missing/unreadable anchors and region overflow return `capture_incomplete` before any provider call/reservation. The UI requests a fresh Reply press. Audience ambiguity has separate wording, and optional response diagnostics record raw/effective audience choice, margin and forced abstention. The 0.10 threshold is unchanged.

Capture v3 and the writer contract are unchanged. No database, iOS, provider, insertion authorization, account isolation or draft policy changes were made. Debug stays enabled by default; Release stays disabled. Existing unrelated working-tree edits and the owner's private diagnostics file remain untouched.

## Verification

- Before the native fix, five added regressions produced eight assertion failures: long focus path/sidebar ordering, partial-path reconnection, metadata after text exhaustion, neutral-wrapper compaction, and search-input classification.
- Full Swift suite: **310 tests passed**. After the final search-subrole correction, **40 focused traversal/session tests passed**, including the added subrole case (311 total tests now exist).
- Deno interpreter/contract tests: **54 passed**, including v1/v2/v3 compatibility, exact source binding, bounded two-call provider envelopes, separate conversations, nested field/header projection and audience abstention diagnostics.
- `deno check`, `deno lint`, and `git diff --check` passed.
- Signed Debug Xcode build succeeded; final incremental build includes the search-subrole correction.
- Deployed only `desktop-reply-context` as **v6**, `ACTIVE`, `verify_jwt=true`, revision `capture-v3-focused-2`. Downloaded deployed runtime files match local source exactly. The previous v5 bundle is saved at `/tmp/keigo-reply-context-v5-rollback.json` for rollback.
- Live unauthenticated endpoint probe returned **401** (`Missing authorization header`), confirming the deployment still enforces authentication. Authenticated interpretation remains part of the owner checkpoint.
- No private capture was replayed to a provider. Local synthetic tests establish scheduling and contract behavior, not live Jev accuracy.

Logs: `/tmp/keigo-focused-baseline.log`, `/tmp/keigo-focused-swift.log`, `/tmp/keigo-focused-final-swift.log`, `/tmp/keigo-focused-deno.log`, `/tmp/keigo-focused-build.log`.

## Required owner checkpoint

1. Stop and Run the Debug app in Xcode. Open the same LinkedIn conversation, click its reply field, then press Reply on the bar.
2. Export a **new** Reply Diagnostics file, even if the reply succeeds. Retrying analysis inside the previous composer reuses the old capture and cannot test this fix.
3. Verify the capture includes the actual main-thread header/history, focused textarea metadata, and a selected candidate excluding unrelated sidebar rows. Verify the generated response answers the intended incoming turn.
4. Check unfocused LinkedIn, Gmail, a native messenger and an Electron messenger, including group chat, two plausible panes and a focused search field. Insertion still needs owner confirmation on real apps.

Do not call the LinkedIn issue resolved until that fresh native capture and interpretation have been inspected. No LinkedIn-specific names, coordinates or selectors were added. Large or inaccessible trees can still exhaust the bounded capture; they should now fail explicitly rather than supplying flattened evidence.
