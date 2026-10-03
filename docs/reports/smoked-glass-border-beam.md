# Smoked glass and native BorderBeam test

The `codex/bar-glass-exploration` branch applies the chosen smoked-glass treatment
to the resting bar, expanded actions, instruction composer, answer card, copied-message
and explicit reply context capsules, error toast, snooze menu, update notice, and intro pill. `SmokedGlassSurface`
uses a 78–84% opaque charcoal gradient and thin edge reflection over the desktop.
A native behind-window material at 40% view alpha adds light background softening;
the edge-specific shape masks the material. This blends some blur back into the
previous direct-tint treatment without restoring the full-opacity material. The notch
attachment remains opaque black. Edge-attached answer cards use the shared material
at bottom and side positions, with their existing exposed-edge border drawn separately;
this replaces the opaque canvas introduced by the edge-panel layout. Inset controls and fields retain solid dark fills.
The result footer shares its card’s backdrop, and overflowing answer text fades with
an alpha mask instead of an opaque gradient. Accessibility Reduce Transparency or Increase Contrast
selects an opaque charcoal surface.

Generation uses the official SwiftUI `BorderBeamKit` counterpart of the requested
`border-beam` React package, with the `.md` ocean preset, 3.6-second duration,
18 pt radius, full strength, 1.8 brightness, 1.5 saturation, and no hue cycling.
A 1.5 pt cyan–blue–violet rim at 85% opacity makes generation visible throughout the cycle. The blue–violet
palette replaces the initial rainbow treatment. It draws behind text and Cancel. The native port
supports macOS 14 and requires Xcode's Metal Toolchain. Upstream source is pinned
under `Vendor/BorderBeamKit`, with the exact revision in `UPSTREAM.md` and the MIT
license in both the source tree and resource bundle. No npm dependency or web view
was added to the native app.

The visible generating capsule remains 176 × 36 pt. Transparent space is 24 pt at
the free edge and sides, 6 pt at the attached edge, mirrored by placement. The
outermost 4 pt fade to zero alpha before the native window boundary, preventing
a hard rectangular cutoff. The generating window has no AppKit shadow. Reduce
Motion retains only the static colored rim and still mascot because the upstream
rotating preset does not honor that preference by itself.

The result card’s native backdrop is outside the SwiftUI content clip and entrance
fade; the material view applies its own shape mask. This keeps the backdrop separate
from the compositing applied to text and controls. The reported solid-black appearance
still needs confirmation in the live app after this adjustment.

## Verification

- Debug Xcode build passed with the Metal shaders compiled and linked.
- All 16 `BarPlacementTests` passed.
- Initial material/beam preview inspected against colored, light, and dark backgrounds. No
  rectangular glow cutoff was visible at the sampled animation phases.
- The expanded companion-panel treatment awaits the user's visual check;
  the generating rim is unchanged from the previous iteration.
- Preview Cancel hid the generating panel. Restart recreates it.
- Explicit preview switches exercised the same static-beam and opaque-surface
  branches used by accessibility preferences. System preference changes themselves
  were not toggled during this check.
- SwiftUI/AppKit code retains production capture, focus ownership, hover timing,
  insertion and placement logic. Full signed-in cross-app rewriting, all dock
  positions, multiple displays, and macOS 14 runtime behavior have not been rerun.

## Adjusting the blur blend

Change `Tokens.Overlay.glassBlurBlend` in `App/Design/DesignTokens.swift`, then
rebuild and relaunch the app. The current value is `0.40` (previously `0.25`).
Try increments of `0.05`: lower values reveal sharper desktop detail, higher
values blend in more of the native blurred material. `0` removes that material;
`1` uses it at full opacity. This controls material blending, not a blur radius,
and can also change perceived darkness. The charcoal tint remains 78–84% opaque.
All bar companion panels share this setting. The notch and opaque accessibility
fallback bypass it.

## Running the test

Build with the `KeigoButtonMac` Debug scheme. The tested build is
`/private/tmp/keigo-glass-build/Build/Products/Debug/KeigoButton.app`.

Run its executable with `--preview-smoked-bar` for the isolated native comparison.
This debug-only entry point bypasses normal app startup, auth, analytics, capture,
and rewriting. Closing its window quits that preview process. Without the flag,
the built app uses the new materials in the normal floating-bar flow.

The repository already contained uncommitted work when the exploration branch was
created. The shared workspace was committed during this implementation (`b23ea7c`,
then `f203233`), including the initial bar experiment. Remaining packaging and preview
polish is uncommitted. The original HTML comparison remains a historical material study.
