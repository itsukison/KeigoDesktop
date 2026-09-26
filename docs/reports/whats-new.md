# Native release introduction

Implemented a localized 780 × 540 pt in-window modal with three current highlights:
customizable Buttons, four screen-edge positions, and copy-to-reply. Each uses native
sample UI on a bundled mountain/glow stage. The first and third demonstrate before/
after steps; position controls move a sample bar without changing the real bar.
The catalog follows the Buttons interface now present in the working tree.

The introduction is offered on deliberate main-window opening, gated by onboarding,
settings and idle overlay state. About reopens it. Acknowledgement is independent of
Sparkle's pending version, survives relaunch, and does not repeat for patch builds
sharing an introduction ID. New installations learn through onboarding instead.
The Buttons action navigates to the existing page. No production requests, clipboard
operations or setup progress changes are made by demonstration controls.

The release workflow emits three localized appcasts while preserving the legacy feed
and signed enclosures. Older Japanese-only note sources receive localized fallback
summaries for English/Chinese; authored trilingual sections receive full translations.
Nothing has been published or deployed as part of this implementation.

## Verification

- Debug app build passed using the full current working tree and native dependencies.
- 15 targeted Swift tests passed: release introduction persistence plus existing pending
  update behavior. Four Python feed tests passed, including locale isolation, escaped
  HTML, wrapped bullets, preservation of signed enclosures and the legacy feed.
- Native NSHostingView renders cover three languages, all three lessons, and two demo
  states per lesson at a 920 × 640 pt surround (18 images). Reviewed English pages and
  representative Japanese/Chinese layouts; fixed stable stage height and footer dots.
- Debug `--preview-whats-new` opens an isolated interactive window; `--render-whats-new`
  exports native PNGs without normal app startup or persisted language changes.
- Live mouse/keyboard/focus-return and VoiceOver checks remain manual: the computer-use
  tool could not resolve the temporary preview app. macOS Reduce Motion/Transparency
  preferences are respected in code but were not changed on the user's machine.
- A published two-version Sparkle installation/relaunch cycle was not performed. It
  requires publishing the localized feeds and signed release together.

Build: `/private/tmp/keigo-whats-new-build/Build/Products/Debug/KeigoButton.app`.

## Repositioning release scope

The bundled introduction is now only `placement`, with stable ID `desktop-four-position-bar`.
Buttons and Reply lessons remain available in code for future releases but are not presented.
The local placement demonstration uses drag gestures, a 64% black screen scrim, dotted
white drop zones, destination highlighting, and snap-on-release. Its picker stays visible
as an educational rehearsal; it does not control the real overlay. Single-page introductions
hide pagination. VoiceOver can adjust the miniature bar position without dragging.
