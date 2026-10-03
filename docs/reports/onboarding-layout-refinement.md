# Onboarding layout refinement

Language now has a small static mascot, a semibold heading, native script glyphs,
stronger language labels, secondary captions, and a pale-blue selected row. It keeps
the existing copy, immediate language switching, keyboard buttons, and centered layout.

Account setup groups its existing authentication controls in a white surface with
20 pt insets and 16 pt corners. The introduction sits directly above the form instead
of being separated by a flexible spacer. Email expansion keeps scrolling when needed;
the existing authentication logic and navigation shelf remain intact.

Practice instructions use 28 pt semibold text and 16 pt secondary explanations. The
header's 144 pt fixed reservation is now a 104 pt minimum aligned toward the stage,
followed by a 16 pt gap. Longer translations can grow rather than clip. Mail and reply
practice scenes share 24 pt outer insets, bringing their editors closer to the heading.
Other page headings use medium weight; body text remains regular.

The standalone bar-discovery page is removed from forward/back navigation, skip flow,
and progress (now nine markers). Raw step ID 4 remains reserved and resolves to first
practice. Completion version remains 2. The first practice already teaches hover, and
still requires a ready editor and actual hover before enabling Polish. None of the
rewrite/insert completion rules changed.

## Files changed in this pass

- `App/Onboarding/OnboardingFlowView.swift`: Language, account group, headings,
  practice spacing, and removal of the standalone bar page.
- `App/Onboarding/OnboardingVisuals.swift`: consistent practice-scene insets.
- `App/Onboarding/OnboardingLessonPresentation.swift`: instruction hierarchy/header.
- `App/Onboarding/OnboardingWindowController.swift`: canonical step routing and
  Accessibility → first practice transition.
- `Sources/DesktopRewriteKit/Onboarding/OnboardingProgressStore.swift`: retire bar
  from active flow, retain raw IDs, and migrate saved bar progress.
- `Tests/DesktopRewriteKitTests/OnboardingProgressStoreTests.swift` and
  `OnboardingLessonTests.swift`: migration/navigation/rail and first-practice hover.
- `AGENTS.md` and `design.md`: current layout and nine-step flow guidance.

Pre-existing unrelated working-tree edits were preserved.

## Verification

- Debug `KeigoButtonMac` build passed.
- Focused onboarding/placement suite: 58 tests passed.
- Full `swift test`: 352 tests passed on rerun. The initial full run hit the existing
  native browser relay test's `transport_unavailable`; that test passed in isolation
  and the subsequent full run passed. Browser bridge code was not changed.
- `git diff --check` passed.
- No computer-use automation or live visual inspection performed.

## Manual review

Quit KeigoButton, then run:

```sh
open -n /private/tmp/keigo-intro-build/Build/Products/Debug/KeigoButton.app --args --replay-onboarding-intro
```

Check Language in English, Japanese and Chinese for wrapping, row selection, and overall
balance. On Account, expand email sign-in/sign-up and check the white group's insets and
scrolling with errors visible. Confirm Accessibility leads directly into rewrite practice,
Back returns to Accessibility, and first practice still teaches hover. During each
practice, inspect the title-to-editor gap, longer instructions, editor focus, and the
existing insert/skip behavior. These live layout and interaction checks remain unverified.
