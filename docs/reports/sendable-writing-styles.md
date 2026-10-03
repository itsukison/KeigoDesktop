# Sendable writing styles

The middle choices now aim for a message that can be used after one pass: natural grammar and phrasing, consistent politeness, enough detail to convey the supplied information, and the author's intended social meaning. Preservation applies to meaning, not accidental rough wording. This is the intended behavior; live model quality remains unverified for this revision.

Email formatting has since been revised: [complete email formatting](email-formatting.md) permits missing-name placeholders and adds the full frame. Its deployment and verification supersede the email-specific statements below.

## Product and prompt changes

- All 36 context/voice/detail combinations share a quality floor. Even a light edit must fix errors, unnatural wording and accidental mixed register. A punctuation-only change is insufficient when the original remains inappropriate for the selected voice.
- Acknowledgment, thanks, requests, refusals and apologies remain distinct. Preserve actors, uncertainty, negation, deadlines, conditions and commitment strength. Courtesy must not introduce an excuse, promise, weakened deadline or unsolicited offer.
- Japanese messages use coherent register throughout the author's prose; quotations, names, code and deliberate fragments are protected. Correct honorific direction and prefer ordinary request forms to stacked cushioning. English uses its own conversational conventions.
- Work chat now asks **メッセージの詳しさは？** with **簡潔に / 標準 / 詳しく**. Standard does not intentionally shorten or expand. Concise retains distinct information and social intent. Detailed unpacks supplied information without inventing background, reasons or commitments.
- Local work choices migrate `preserve` and old-default `streamline` to `balanced`; `structure` maps to `detailed`, the closest new preference for fuller explanation. Voice, notes and mappings survive. The backend accepts both old and new IDs; old `streamline` also receives the corrected normal-length baseline. The old structure setting remains available to installed clients through its legacy wire ID.
- Email stays an email body without invented greeting/signature. Personal messages stay conversational, with their supplied emotion. Other identifies messages versus reports/notes, so an unknown app neither preserves rough message keigo nor turns a report into a letter.
- Detail modules now apply to new composition and replies without a draft. Source-preservation instructions do not invent nonexistent structure. Selections continue to omit body-formatting modules and return only the selected replacement.
- Current instructions and saved notes retain precedence. Translation, explicit summary and reply intent keep their existing boundaries.

The design drew on [natural-japanese's readability principles](https://github.com/coji/natural-japanese/blob/main/skills/natural-japanese/references/readability-principles.md), including the distinction between clear writing and short writing. Report-specific conventions and its full document-authoring workflow are not runtime dependencies.

## Verification

- 298 Swift tests pass. Added coverage for work-detail migration, round trips and preservation of voice, notes and mappings. All eight defaults remain the middle option.
- 59 backend tests pass. All 36 shared fixtures validate; every selected voice/detail module reaches polish, composition and reply; fragment scope and legacy work IDs are covered.
- All 48 synthetic evaluation request payloads validate locally. This is validation of requests, not generation quality.
- Backend type check and style-file lint pass.
- 432 unstyled/legacy request combinations preserve exact parsing and system/user prompts versus deployed version 24.
- Native Debug build succeeds with signing disabled at `/private/tmp/keigo-sendable-build/Build/Products/Debug/KeigoButton.app`. Existing overlay concurrency warnings remain outside this change. The installed running app has not been replaced.
- 324 layout combinations pass (36 styles × 3 languages × 3 widths). Japanese and English work-chat renders were visually inspected at the narrow width. Cards remain readable and the total layout height remains 999 pt in the harness. The standalone render does not load bundled app-logo assets; that is not a missing asset in the app.

## Deployment and live-test limitation

`desktop-rewrite` version **26** is active with JWT verification enabled. Downloaded files exactly match the submitted package. Only `style_prompt.ts` and `style_modules.ts` differ from the version 24 baseline. Deployed authentication, billing, model configuration, retention/logging and reply validation were preserved. No database, iOS function or phone prompt was modified.

The deployment was composed from downloaded production files, not the entire local function directory: the unrelated local retention and v3 reply changes still differ from production and must not accidentally ship in a future style-only deployment.

The authenticated synthetic evaluation was rejected before generation:

```json
{"reason":"quota_month","plan":"free","used":30,"monthLimit":30,"resetsAt":"2026-09-30T15:00:00+00:00"}
```

No output was generated, no quality pass is claimed, and quota/billing was not changed to bypass the limit. The configured provider default remains unchanged; no actual model identifier was observed on this blocked run. The 48-case live evaluation and semantic review remain pending an account with available quota.

## Reproduce the quality evaluation

The checked-in `scripts/evaluate-writing-styles.py` uses synthetic text only. It covers all 36 styles and 12 additional cases: report/notes, firm refusal, honorific direction, already-good short text, English, explicit and saved casual preferences, a selected fragment, new detailed composition, no-stance reply, and a protected quotation.

```sh
python3 scripts/evaluate-writing-styles.py --output /private/tmp/sendable-cases.json
```

For live use, configure `STYLE_EVAL_ENDPOINT`, `STYLE_EVAL_USER_JWT` and `STYLE_EVAL_PUBLISHABLE_KEY` through the environment, without passing secrets on the command line. Use an authorized account with enough test quota; this invokes the normal metered endpoint. The script spaces requests below the 12/minute burst ceiling and stops on errors rather than retrying paid generations.

```sh
python3 scripts/evaluate-writing-styles.py --live --output /private/tmp/sendable-results.json
```

A single case can be selected with `--case work_chat-neutral-balanced`. Each saved result includes the input, chosen style, output, event ID, latency, factual anchor checks and a semantic review checklist. Anchor checks alone cannot pass the case. Review consistency of register, naturalness, preserved factual/social meaning, scope and lack of invented content. Compare the three settings without requiring a mechanical character-count progression or visible changes to already-good short text.
