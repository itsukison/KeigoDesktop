# Universal button — implementation verification

The desktop now uses one Polish action and account-scoped local styles. Each context has two ordered three-choice questions, all initialized to the middle choice, plus optional notes. Settings and onboarding share the native SwiftUI editor. Legacy phone prompt types remain for compatibility, but there is no `UserPromptRemoteStore` construction or reference under `App/`.

Current prompt/choice revision: [sendable writing styles](sendable-writing-styles.md), including deployment version 26 and the live-test quota limitation. Earlier evidence below belongs to its original revision.

## Checks completed

- Native Debug build succeeds with signing disabled. Existing shadow-isolation and Dock cache concurrency warnings remain; no new warning was introduced by this feature.
- Swift package suite: 277 tests pass, including default ordering, all 36 wire combinations, persistence/relaunch, account isolation, stale saves, partial documents, write failure, future/corrupt-file preservation, explicit recovery, context resolution, onboarding migration, and response-version checking. Existing TextIO and reply contract suites pass.
- Deno: 57 tests pass across `desktop-rewrite` and `_shared/reply-context`. New cases cover all 36 shared style fixtures, invalid/cross-context enums, version rejection, Unicode notes limits, blank draft/instruction combinations, fragment scope, dynamic-note isolation and reply safeguards. These are contract/prompt tests, not model-quality evaluations.
- `deno check` for the endpoint and `deno lint` for the new style files and modified request/prompt modules pass.
- Native layout harness checks 324 layouts: 36 combinations × 3 interface languages × content widths 606, 682 and 920 pt. Total view height stays 999 pt including the harness's 28 pt outer padding. Card/preview heights are fixed; smaller windows scroll the editor. Native renders were inspected for readability and clipping. The harness uses an isolated model and does not access account storage or the network.
- Static runtime audit finds no desktop references to `UserPromptRemoteStore` or `user_prompts`. No phone rows, database schema, or deployed function was changed.

Preview: [Email in English](universal-button/email-en.png), [Casual messages in Japanese](universal-button/casual-ja.png).

## Behavioral details

- Each captured target carries the resolved profile and composition language. Result pages, regenerate and refine reuse that value snapshot. Settings changes apply to future captures.
- Context resolution is local. URL parsing uses explicit hosts/routes; lookalike domains remain Other. Native mixed-purpose apps require recognized composer labels. Missing evidence falls back to Other. Search, recipient, secure and recognized source-editor controls cannot be assigned prose styling by an override.
- Corrections support one use, a stored native-app/site scope, and removing that mapping. Browsers with no captured hostname cannot receive an app-wide mapping. No full URL is sent in universal style requests.
- The API adds `writingStyle` without changing older-client request meanings or the result body. Validation precedes quota/provider work. The response header confirms the new branch ran; the client rejects missing markers without a paid retry.
- Prompts retain the configured `gpt-5.6-terra` default and existing reasoning configuration. Static modules are separated from dynamic notes/source/instructions. Structural modules are omitted for selections and absent drafts. Preservation is conditional on the requested operation, so explicit summary instructions can omit detail.
- Analytics adds `universal`, style enum metadata joined by attempt ID, and context-correction events. Notes, mapping keys, URLs and text are excluded from these events.

## Backend deployment verified

Follow-up: [platform detection and default politeness](platform-detection-politeness.md) records the Gmail depth failure, native fix, live output checks and backend version 24 deployment.

On 2026-09-24, deployed `desktop-rewrite` version 22 to `eercsucvxnszqletxued`, with `verify_jwt = true`. Version 21 rejected the universal button's intentionally empty prompt. Version 22 adds style validation, prompt compilation and the response-version header.

The package was built from downloaded version 21, replacing only `request.ts` and `prompt.ts`, adding the three style modules and the type-only reply definitions, and adding the style header to `index.ts`. Production logging/retention, provider configuration, billing, authentication and runtime reply validation were preserved. Local consent/retention changes and v3 capture validation were deliberately excluded. Future deployments must review this remaining local/production difference. No iOS function, database schema or phone settings were changed.

- All 57 local backend tests passed; the isolated deployment endpoint passed `deno check`.
- Compared 432 legacy request combinations against version 21: identical serialized parse results/errors and exact system/user prompts. Covered rewrite, compose, legacy reply, selection, language, candidate count and refinement variants.
- All 36 style fixtures with an empty prompt were rejected by version 21 and accepted by the deployment parser with one candidate.
- Downloaded version 22: all 10 runtime/configuration files exactly matched the submitted package (the type-only file is omitted by bundling).
- Live authenticated synthetic requests: universal empty-prompt request returned HTTP 200, one candidate and `X-Desktop-Style-Version: 1`; legacy rewrite returned HTTP 200, one candidate and no style marker.
- Live rejection checks: invalid style version returned HTTP 400 `invalid_writing_style`; unauthenticated request returned HTTP 401.

These checks establish backend compatibility and successful generation, not full model-quality or native capture/insert acceptance.

## Release gates still open

1. Run live GPT-5.6 output evaluations across the authored style matrix, including low/medium reasoning comparisons, factual preservation, tone differences, language and adversarial notes. Native preview text is authored demonstration copy, not generated-output evidence.
2. Run real app capture/insert checks in supported mail/chat/browser versions, including context-menu focus, tab/window changes, secure controls, regeneration, and the release/explicit Reply paths. Resolver unit fixtures are not a claim of verified compatibility with every current app version.
3. Run the startup/auth/onboarding network-spy acceptance check and hands-on keyboard/accessibility review. Static wiring removal and the isolated layout harness cover different parts of this gate.

## Reproduce

```sh
swift test
deno test --allow-read supabase/functions/desktop-rewrite/ supabase/functions/_shared/reply-context/
deno check supabase/functions/desktop-rewrite/index.ts
xcodegen generate
xcodebuild -project KeigoButtonMac.xcodeproj -scheme KeigoButtonMac -configuration Debug -derivedDataPath /private/tmp/keigo-universal-build CODE_SIGNING_ALLOWED=NO build
swiftc -parse-as-library -I .build/arm64-apple-macosx/debug/Modules scripts/verify-writing-style-layout.swift App/Main/WritingStyleView.swift App/Design/DesignTokens.swift .build/arm64-apple-macosx/debug/DesktopRewriteKit.build/*.swift.o -o /private/tmp/style-render
/private/tmp/style-render
```

The rendering command assumes Apple Silicon's standard SPM output directory. It writes PNGs only beneath `/private/tmp/universal-style-renders`.
