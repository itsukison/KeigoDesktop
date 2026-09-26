# Compact desktop introduction

The introductory mascot and copy now form one measured composition, centred at 45%
of screen height. The character's layout slot is 140 pt, followed by a 24 pt gap and
a 460 pt text column. The heading uses regular system type at 32 pt; supporting copy
uses 20 pt, 12 pt below it. The first sentence has an intentional two-line wrap.
Only one supporting sentence is visible at a time in a shared, stable-height slot.
The heading and mascot remain stationary through the swap. Hidden sentences are
excluded from accessibility.

The character remains in the existing never-key pill panel. A SwiftUI anchor connects
its position to the measured composition until departure, then to the real pill's
landing position. The transparent dimmer retains Escape and the pill explanation.
The initial 4% scale settle and proportion-preserving landing replace the large scale
entrance, anticipation stretch, and landing squash. The first sentence holds for four
seconds, fades out over 250 ms, then the second fades in over 350 ms and holds for five
seconds. The nine seconds of fully visible reading time remain; the swap adds 600 ms
to the opening. Both fades belong to the existing cancellable clock, so Escape or an
interruption cannot reveal stale copy. Reduce Motion keeps the opacity-only swap and
has no scale entrance.

The existing AVPlayer movie and portrait are unchanged; no Rive dependency was added.
Their source padding is normalized to the resting outline, with its bottom at source
y = 0.839. The full 145-frame movie was decoded to inspect alpha bounds: its motion
extends at most roughly 16 pt below the resting slot at the new size, inside the
24 pt gap. The renderer permits that movement without clipping it.

First-run persistence, the cancellable timeline, copy wording, three-second pill
explanation, Dock-aware landing, and 700 ms Language reveal are unchanged. Only the
intro uses the new system typography; normal overlay typography stays independent.

## Verification

- Debug Xcode build succeeded with code signing disabled.
- All 11 `OnboardingIntroTests` passed, covering replay/persistence, Reduce Motion,
  display coordinates, Escape replacement (including during the copy swap), interruption,
  and clock failure.
- Native `NSHostingView` renders of the production intro view were generated at
  1280 × 800, 1440 × 900, and 1920 × 1080. Static portrait and copy fit with consistent
  spacing. Both sentence states were checked. The render harness used the bundled asset
  catalog and no account services.
- `git diff --check` passed.

These are native static layout checks and existing lifecycle tests, not a live
end-to-end replay of video playback, cross-window handoff, or drag interaction.
The Debug build in `/private/tmp/keigo-intro-build/Build/Products/Debug/KeigoButton.app`
supports the existing `--replay-onboarding-intro` argument for that review.
