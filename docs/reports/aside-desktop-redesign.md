# Aside desktop redesign — implementation handoff

The desktop light UI now uses the Aside palette, native system typography, semantic
primary/selection colors, and bundled mountain/glow artwork. Onboarding uses the new
1016 pt composition width, shared split/choice layouts, fixed bottom navigation and
quiet progress markers. Dashboard organization and dimensions remain intact.

The floating overlay's source files, color ramp, font helpers, geometry and timings
are unchanged relative to the start of this implementation. The desktop cinematic
also retains its existing typography and lifecycle. No backend, iOS, landing-page,
saved-step, completion-version or account-contract changes were made.

## Engineering verification

- Native Debug app builds with Xcode 26.6, code signing disabled for this local build.
- All 350 existing Swift tests pass, including onboarding progress, lessons, intro,
  placement, style persistence and text I/O tests.
- Both catalog images match the supplied originals byte for byte.
- `git diff --check` passes.
- Debug-only `--render-aside-previews` renders 87 native 2× fixtures covering all 12
  onboarding screens in Japanese, English and Simplified Chinese, authentication
  sign-up/error/loading states, and dashboard/preferences at default/minimum sizes.
  The renderer returns before production startup, uses an empty session store,
  isolated file paths, inert view state, and disabled interaction. It does not start
  sign-in, billing, analytics or onboarding transitions. Native rendering is evidence
  that these views can render; it is not a completed visual or interaction audit.

## Review handoff

The user will perform the visual review. Review every onboarding step, the expanded
email form, localized labels, style scrolling, bottom navigation, scene sizes and
asset crops. Test Reduce Motion/Transparency and keyboard navigation in the live app.

The real permission/sign-in/insertion walkthrough has not been repeated during this
redesign. Existing behavior is retained and its unit tests pass; those tests do not
establish that the full cross-app workflow succeeds on this machine.

Build: `/private/tmp/aside-build/Build/Products/Debug/KeigoButton.app`

Native fixtures: `/private/tmp/aside-previews/` (manifest lists every capture).

Run the app normally for the live walkthrough. The existing “View tutorial” menu
entry opens replay without resetting completed onboarding or real style preferences.
The debug `--replay-onboarding-intro` flag also replays the desktop introduction.
