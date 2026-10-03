# Platform detection and default politeness

## Failure confirmed

The 2026-09-24 rewrite attempt `7daa36aa-9d74-42a1-af2b-dd39bf871374` captured the complete draft through AX in Chrome. PostHog recorded `other / unknown / neutral / flow`. Its output preserved the casual wording and changed punctuation only.

A live, read-only inspection of the owner's Gmail inline reply found an `AXTextArea` labeled Message Body. The `AXWebArea` with `mail.google.com` was at ancestor depth 30; the old reader stopped before depth 12. The same field's window also exposed the Gmail URL through `AXDocument`. This establishes the capture-metadata failure rather than inferring it from the generated text.

## Changes

- URL discovery follows up to 64 ancestors, skips non-HTTP(S) frame URLs, detects cycles, and stops scheduling reads after 200 ms. Individual probe calls use 50 ms messaging timeouts, restored to the normal 500 ms afterward. The total can exceed the traversal budget by an in-flight bounded node read. Fallback uses only the captured element's window document, never another window or tab. No conversation traversal or address-bar keystrokes.
- A recognized browser mail-body hint can resolve Email when URL evidence is missing. Unknown browser fields and known non-mail routes continue to resolve Other. No cross-capture URL cache.
- URL probe diagnostics report source, depth and availability, without URLs or text.
- Other/neutral now makes message-like drafts politely sendable, preserving urgency, facts, conditions and commitments. Reports and notes retain their genre. Explicit casual instructions/preferences continue to win.
- Email/polite now explicitly transforms casual acknowledgments and request endings, retaining acknowledgment and gratitude as distinct content. An initial live Email evaluation still retained casual wording; this additional correction was evaluated before handoff.
- Added the missing `DesktopRewriteKit` import required by the workspace's existing `VerticalAnchorSide` usage in `GeneratingPanel` to unblock the native build.

## Verification

- 297 Swift tests pass, including regressions for deep frames, blank inner frames, parent cycles, limits, non-web documents, capture-to-capture URL changes, missing URL with mail hints, calendar/chat routes and excluded fields.
- Native Debug build succeeds with signing disabled. The build is at `/private/tmp/keigo-platform-build/Build/Products/Debug/KeigoButton.app`; the running installed app was not replaced.
- A harness invoking the updated native URL reader directly on Chrome's focused Gmail element returned `host=mail.google.com context=email source=known_surface elapsedMs=2`. A separate system-focus harness could not read Chrome while the diagnostic process lacked the intended focus; it was not treated as validation.
- Backend contract/prompt suite: 57 tests pass.
- `desktop-rewrite` version 24 is live with JWT verification enabled. Downloaded runtime files match the submitted package. Only `style_modules.ts` differs from version 22; existing legacy prompts, auth, provider configuration, billing, logging and runtime reply validation were preserved. The unrelated local retention and v3 capture changes remain excluded.

## Live generated examples

Input: `おっけい\nありがとうございます、返信があったらすぐ教えてね`

Other/neutral/flow:

> わかりました。  
> ありがとうございます。返信がありましたら、すぐにご連絡いただけますと助かります。

Email/polite/readable:

> 承知しました。  
> ありがとうございます。返信がありましたら、すぐにご連絡いただけますと助かります。

Both default profiles preserved the deadline and fallback condition in `明日17時までに確認して。難しいなら今日中に教えて。`:

> 明日17時までにご確認ください。難しい場合は、本日中にご連絡いただけますと助かります。

Other preserved the 5% figure and unconfirmed profit-margin caveat in an expository report. An explicit casual instruction retained casual language. An English message became `Okay, thank you. Please let me know as soon as they reply.` These are small live acceptance samples, not a comprehensive model-quality evaluation or a guarantee of identical stochastic output.
