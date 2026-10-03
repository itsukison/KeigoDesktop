# Polish guidance, shared blur, and four-position error toasts

The shared smoked-glass material now uses `glassBlurBlend = 1.0`. The charcoal
tint, shape masks, borders, black notch surfaces, and opaque accessibility
fallbacks remain intact. This supersedes the 0.40 blend described in the earlier
smoked-glass exploration report.

Polish rejects missing, empty, and whitespace-only targets with localized guidance
before changing focus or starting generation. Nonempty selections remain supported
independently of writability. The pencil still accepts a scratch target. Excluded
controls and missing Accessibility permission keep their specific messages.

Error toasts use the selected zone with an 8 pt inward gap, following the live
anchor during measurement, movement, resizing, and zone/work-area changes. Their
screen is resolved from the anchor, and their size/frame is capped to that screen's
work area. Other auxiliary panels retain their existing placement policy.

## Verification

- Debug Xcode build succeeded using the `KeigoButtonMac` scheme.
- All 363 Swift tests passed. The existing native browser relay test required an
  unsandboxed run to access its local Unix socket.
- The placement subset passed 25 tests, including four new error-toast tests for
  every zone, resizing anchors/toasts, live zone decisions, Dock changes, negative
  and offset display coordinates, and small work areas.
- `--verify-polish-guidance` passed 60 native rejection scenarios: five capture
  outcomes × four positions × three languages. Each kept the bar out of composer
  and generation states, sent no mock rewrite request, retained keyboard focus,
  and kept the toast visible and attached after hover collapse.
- The same native pass verified that an existing toast follows all four zone
  changes, nonempty whole-field and read-only selection fixtures each produce one
  mock rewrite, and the pencil opens a scratch composer without generating.
- Inspected generated English, Japanese, and Chinese toast images for wrapping
  and clipping. The native geometry checks allow at most 0.5 pt of screen rounding.
- `git diff --check` passed.

The native workflow uses injected capture outcomes and an isolated mock URL session,
with preview history/styles under `/private/tmp/keigo-edge-previews`. It does not
verify fresh cross-app Accessibility capture or send production AI requests. The
full native result is `polish-verification.txt` in that directory.

## Visual verification limit

Desktop automation was denied access to the preview app. Generated images are
view renders, not composited desktop captures; they establish message layout, not
the strength of behind-window blur. Live blur over detailed light/dark backgrounds,
system Reduce Transparency/Increase Contrast, and physical multi-display behavior
remain unverified. The opaque accessibility branches are unchanged.

For a live material comparison, run the Debug app with `--preview-smoked-bar`.
That isolated preview now includes detailed background text and stripes, plus
light/dark backgrounds and an opaque-fallback toggle. It bypasses normal account,
analytics, and rewrite startup.
