# Onboarding visual refinements

The animated mascot now uses an exterior-only matte with black edge antialiasing.
The new cyan icon retains the existing keycap character. Lesson hints use compact,
text-sized white callouts with neutral hairlines and a small joined pointer.

## Changed files

- `App/Resources/OnboardingMascotLoop.mov`: regenerated from the preserved opaque
  master. Both the cinematic introduction and gradient stages load this movie.
- `scripts/prepare-onboarding-mascot.swift`: repeatable offline background removal;
  flood fill stops at the black outline and preserves enclosed face/eye pixels.
- `App/Onboarding/OnboardingGuidePanel.swift`: localized text measurement, 16 pt
  system type, quiet border/shadow, attached pointer, no repeating pulse. Retains
  existing non-key behavior, obstacle avoidance, four positions, and lesson copy.
- `public/generated/keigo-icon-cyan-v2.png`: generated full-resolution icon artwork.
- `App/Resources/Icons.xcassets/KeigoAppIcon.appiconset`: all ten macOS icon sizes.
- `App/Resources/Icons.xcassets/KeigoAppMark.imageset`: matching window mark.
- `scripts/prepare-app-icon.swift`: native asset packaging with the existing
  824/1024 macOS superellipse grid and transparent external padding.
- `App/Design/Icon.swift`, `App/Design/BrandVisuals.swift`, `project.yml`: select the
  new icon/brand asset. Earlier purple assets remain available.
- `AGENTS.md` and the icon catalog `README.md`: current matte/callout/icon guidance.

Existing unrelated working-tree edits were preserved.

## Verification

- Debug `KeigoButtonMac` Xcode build: passed.
- `swift test --filter 'Onboarding|BarPlacement'`: 56 tests passed.
- Matte preparation processed all 145 original frames, preserving 960×960, 24 fps,
  and the 6.041667-second duration. Every frame passed the enclosed-center alpha check.
- Decoded the actual HEVC alpha output with AVFoundation and compared frames at
  0, 1, and 3 seconds on cyan and dark backgrounds. The old white fringe is absent
  in these samples; interior face/eye edges remain opaque.
- Inspected the packaged 1024 px icon's artwork, transparent padding and mask.
- `git diff --check`: clean.

Build warnings remain in existing DockProbe/OverlayController concurrency code and
optional AppIntents metadata extraction. No live UI automation was used.

## Manual check

Quit the running app, then launch this Debug build:

```sh
open -n /private/tmp/keigo-intro-build/Build/Products/Debug/KeigoButton.app --args --replay-onboarding-intro
```

Check the account/completion mascot over the gradient through a complete blink/bounce
loop, including at Retina scale. In bar discovery and practice, check that the smaller
hints remain readable and point to the intended control. Try bottom, top and side
placements and a longer Japanese/Chinese instruction. Confirm the new cyan app icon
and matching window mark. Live motion, hint layout and placement remain unverified.

## Reproduce the movie matte

Run from the repository root (requires the existing ffmpeg installation):

```sh
swiftc -O scripts/prepare-onboarding-mascot.swift -o /private/tmp/prepare-onboarding-mascot
set -o pipefail
/private/tmp/prepare-onboarding-mascot App/Resources/OnboardingMascotLoop.mp4 | \
  ffmpeg -hide_banner -loglevel error -f rawvideo -pixel_format bgra \
  -video_size 960x960 -framerate 24 -i - -c:v hevc_videotoolbox \
  -alpha_quality 1 -allow_sw 1 -q:v 65 -tag:v hvc1 -an \
  -y App/Resources/OnboardingMascotLoop.mov
```

## Icon generation

Generated using the built-in imagegen tool, with the existing `MascotPortrait` artwork
as the identity reference. Native packaging: `swift scripts/prepare-app-icon.swift`.
Final prompt:

```text
Use case: logo-brand
Asset type: macOS app icon artwork for KeigoButton.
Input image: reference for the exact existing mascot identity, not an edit target.
Primary request: Create one polished new app icon featuring this same ivory keyboard-key mascot with two black notched oval eyes, heavy black outline, angled face and three-dimensional keycap body. Preserve the character's recognizable proportions and playful quiet personality.
Composition: square full-bleed artwork, mascot centered, occupies about 70% of width, enough comfortable clear space around it. The application will apply its own macOS rounded-square mask and margin, so do NOT draw a rounded-square border, external shadow, mockup, or another nested tile. Fill the entire square canvas.
Backdrop: very restrained pale ice-cyan background with soft blue light, echoing a native macOS app with white surfaces and a calm sky-blue environment. Subtle grounded depth behind the mascot, clean professional finish.
Style: crisp illustration, subtle ivory shading, strong clean silhouette, readable at small sizes. Keep existing black outline and eye design; no added facial features or limbs.
Avoid: white fringe outside black character outline, purple, rainbow AI gradients, glow, glass, particles, text, letters, symbols, extra characters, watermark.
Output one 1024x1024 square image.
```
