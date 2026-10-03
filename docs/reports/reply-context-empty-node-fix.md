# Reply Context: empty AX node coverage correction

The native capture now distinguishes successfully read empty/whitespace text from unreadable or omitted text. This addresses the false `missing_current_history` rejection reproduced from the LinkedIn timestamp-spacer geometry in snapshot `7503C56C-3A36-4521-804C-4962318F5818`. The original export did not record the spacer's actual read outcome, so a fresh live capture remains necessary to confirm its value and the subsequent semantic result.

## Changes

- The AX value/title reader preserves a successful empty result, tries a meaningful fallback title, and leaves unavailable or failed reads unresolved. A failed attribute read cannot be hidden by a blank fallback.
- Traversal excludes confirmed empty nodes from `skippedCurrentTextNodes`. Missing values, changed role/editability/geometry, and budget omissions remain failures near the composer. Having only blank history still fails.
- Explicit local diagnostic exports now include `textDisposition` on each discovered text candidate. Discarded samples retain failed attribute names and contribute AX error codes/counters, making their omission explainable without exporting additional text.
- Capture limits, backend rejection policy, semantic selection and provider thresholds are unchanged. This is a native AX correction; no backend deployment is needed.

## Verification

- All 326 Swift tests passed, including nine new test methods covering the value-reader distinction, retained message plus blank timestamp spacer, genuine omissions despite retained messages, changed nodes, and blank-only history.
- The regression uses synthetic text and the exported window/composer/header/message geometry. No conversation was sent to a provider.
- Debug Xcode build succeeded with signing disabled at `/tmp/keigo-reply-build`. Warnings remain in unrelated overlay/Dock concurrency code and App Intents metadata extraction.
- `git diff --check` passed.

Run the signed Xcode app and press Reply again from LinkedIn to validate a fresh capture. Existing snapshots retain their original rejection flags; retrying one does not apply the new native capture logic.
