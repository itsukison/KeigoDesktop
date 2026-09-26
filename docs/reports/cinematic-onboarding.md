# Cinematic onboarding implementation

The first-launch introduction uses the existing onboarding coordinator and production
pill. Language and later page content are unchanged. There is no Rive dependency.

## Behavior

- New, incomplete setup with no saved step gets the cinematic. Language is saved before
  it starts; interrupted runs resume there. Completion version remains 2.
- A transparent borderless panel dims the actual desktop to 88% black. The same never-key
  `PillPanel` carries the central mascot, landing, and persistent pill.
- Copy stays fully visible for nine seconds. The pill message lasts three seconds;
  existing Language reveals over 700 ms. Escape advances to landing/reveal.
- Early setup keeps the pill visible and draggable but blocks product actions. Existing
  discovery and practice gates take over at the bar lesson. Normal drags persist.
- Reduce Motion uses a static portrait and fade relocation. Playback failure retains the
  portrait, and clock failure finishes into usable onboarding. Deactivation, sleep, and
  display/Space changes remove the cinematic surfaces without activating the app.
- The debug replay uses read-only onboarding progress and temporary placement. It does
  not reset completion or save its drag destinations. As with existing onboarding replay,
  this is not an isolated user account: language selection and explicit sign-in actions
  still use the existing application services.

## Changed files

- `App/AppDelegate.swift`: hidden startup preparation and debug replay argument.
- `App/Onboarding/OnboardingWindowController.swift`: first-run routing, passive early
  setup, idempotent presentation, intro ownership and cleanup.
- `App/Onboarding/OnboardingIntroController.swift`: native motion and reveal orchestration.
- `App/Onboarding/OnboardingIntroPanel.swift`: transparent scrim and supplied copy.
- `App/Onboarding/IntroCharacterView.swift`: replaceable character renderer and motion pose.
- `App/Overlay/OverlayController.swift`: temporary cinematic ownership, native landing,
  action gating, drag reuse and temporary debug placement.
- `App/Overlay/PillRootView.swift`: intro presentation and subtle drag cue.
- `App/Overlay/SnapOverlayPanel.swift`: optional scrim opacity to avoid double dimming.
- `App/Overlay/OverlayPlacement.swift`: conservative Dock clearance before AX permission.
- `App/Design/BrandVisuals.swift`: optional static sprite rendering for matched handoff.
- `App/Resources/Assets.xcassets/MascotPortrait.imageset/`: unchanged supplied portrait
  copied from `public/bgremoved.png`, plus its catalog manifest.
- `Sources/DesktopRewriteKit/Onboarding/OnboardingProgressStore.swift`: intro eligibility
  and read-only replay progress.
- `Sources/DesktopRewriteKit/Onboarding/OnboardingIntroSequence.swift`: cancellable clock,
  phase/cue timeline, Reduce Motion sequence and logical-coordinate conversion.
- `Tests/DesktopRewriteKitTests/OnboardingIntroTests.swift`: persistence, replay isolation,
  interruption, skip, clock failure, Reduce Motion, idempotence and display-origin cases.
- `AGENTS.md`: current first-run architecture and pre-permission placement guidance.

Existing unrelated working-tree changes were retained. The generated Xcode project is
ignored; no package dependencies or backend changes were added.

## Automated verification

Debug build:

```sh
xcodegen generate
xcodebuild -scheme KeigoButtonMac -configuration Debug \
  -derivedDataPath /private/tmp/keigo-intro-build CODE_SIGNING_ALLOWED=NO build
```

The full Swift test suite passed with 349 tests before the final clock-failure regression
case was added. A concurrent build/test run encountered a transport failure in the
existing browser-native-host integration test; that test and the subsequent full suite
both passed when rerun. No browser bridge files were changed for this task.

The final targeted onboarding/placement run passed all 56 tests, including the additional
clock-failure case. The final Debug build succeeded and `git diff --check` passed.
Build warnings concern existing Dock/overlay concurrency annotations and optional
AppIntents metadata extraction.

## Manual visual review

Computer control was declined, so no live visual validation is claimed. Quit any running
KeigoButton instance, then launch the built Debug app:

```sh
open -n /private/tmp/keigo-intro-build/Build/Products/Debug/KeigoButton.app \
  --args --replay-onboarding-intro
```

1. Let the sequence run for approximately 16 seconds. Check that the desktop remains
   faintly visible, including its menu-bar/Dock region; there should be no normal window,
   white rectangle, or chrome before the Language reveal.
2. Watch the still-to-expression transition, descent, squash, pill growth, and final
   full-display-panel shrink. Report any doubled outline, size jump, clipped mascot,
   blank frame, or pill blink. These are the most important live tuning points.
3. Drag the landed pill to a side or top slot. It should use the existing snap picker,
   remain visible when Language reveals, and avoid a second dim layer. Also let one run
   finish without dragging. Tab and Return must work on Language afterward.
4. Relaunch with the argument and try Escape during the introduction. Try switching
   away once: the dimmer should clear and reopening setup should show Language.
5. Enable macOS Accessibility → Display → Reduce motion, replay, then restore your
   preferred setting. Expect fades without the fall, bounce, squash or wiggle.
6. If available, repeat on an external display and at a different display scaling.
   Ordinary first-run persistence and saved drag placement should be checked in a fresh
   macOS test account without the debug replay argument; replay intentionally preserves
   your current progress and position.

Later setup content and practice remain the existing flow. Signing in or granting
Accessibility is unnecessary just to inspect this introduction.
