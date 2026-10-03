# Guided onboarding implementation

Onboarding now uses 28 pt headings, 18 pt instructions/sample text, 16 pt actions,
and 13 pt progress labels. Shared controls and writing-style settings opt in only
inside onboarding. The window remains 1080×700.

Bar discovery requires an actual hover before Continue unlocks; Skip is still
available. Rewrite, Custom, and Reply use a session-scoped lesson state machine,
real control anchors, and a never-key/mouse-transparent callout. Unrelated bar
entry actions are disabled in both the view and controller. Instructions follow
focus, input, generation, result, and completion events. Insertion and Copy
completion have different wording. Editor focus requests are consumed only once
the editor is attached to a key window, rather than repeated during view updates.

Mail and Slack remain recognizable. Important content is enlarged, decorative
controls are quieter, and the source-selection control stays prominent. The
account form can scroll when expanded. Source choices can wrap without shrinking.

## Verification

- `swift test`: **340 tests passed**, including 9 new lesson/placement tests.
- Debug macOS build succeeded with `CODE_SIGNING_ALLOWED=NO`, using
  `/tmp/onboarding-derived` as DerivedData. Existing overlay concurrency warnings
  and the App Intents metadata warning remain; no new onboarding warnings.
- `git diff --check` passed for the affected implementation files.
- An isolated, disposable preview harness rendered the 12 onboarding pages in
  Japanese, English, and Chinese, plus custom-lesson states. It used in-memory auth
  and temporary stores; it did not send sample messages to the production backend.
  Render inspection caught and fixed the coordinator observation hookup, a
  truncated source label, and low-contrast renewal wording. It is not evidence of
  successful live AI generation or insertion.

## Visual handoff

The user will perform the final visual walkthrough. Open the Debug build at
`/tmp/onboarding-derived/Build/Products/Debug/KeigoButton.app` and use the app's
“How to use” / “使い方を見る” menu to replay onboarding.

Check bar discovery first, then Rewrite → Custom → Reply. Also try an empty sample,
Escape/retry, Copy fallback, Back/Skip, and top/side bar placements. Remaining
manual acceptance includes live backend/insertion, multiple-display behavior,
Reduce Motion, and a first-use check without spoken assistance.

The repository had concurrent browser-reply work during implementation. Two small
compile corrections were necessary to verify the combined tree: an exhaustive
`BrowserReplyError.reason` getter and moving an insertion-failure log into its
`catch` block. Other in-progress changes were preserved.
