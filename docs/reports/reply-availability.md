# Quiet copied-reply availability

Copying now leaves the collapsed pill at its normal size, with a static neutral dot.
Hover reveals Polish, an optional Reply/× group, and the pencil. Reply captures the
current destination before opening the guidance editor. The source excerpt appears
inside that editor's window, above a divider; no copied-source panel is created.

The × clears the offered source without modifying the clipboard. Escape/outside-click
retains the source for another three minutes. Unused sources expire, nonqualifying
copies clear old availability, and an active reply keeps its chosen source. Onboarding
teaches the Reply click and returns to the copy step after dismissal or expiry.

Bottom grows up; top/notch grows down; both side positions grow inward and remain
vertically centered. Side actions are 80 pt wide while Reply is available, retaining
separate 28 pt dismiss targets. The side reply composer is 208 × 287 pt. Native samples
measured the horizontal reply composer at 360 × 70 pt with empty guidance.

## Verification

- Debug Xcode build succeeded, with signing disabled for the isolated preview.
- `swift test`: 359 tests passed. The existing native-host socket test transiently
  failed during one run; its focused retry and the subsequent full suite passed.
- `--render-reply-availability` exercises the real controller and SwiftUI views with
  isolated account/service fixtures. It renders 36 images across three languages and
  four positions to `/private/tmp/keigo-reply-availability`.
- Native assertions passed for unchanged collapsed geometry, non-key hover, dismissal
  without leaving the action row, hover grace collapse, attached source ownership,
  fixed source during composition, cancellation, expiry, invalid-copy clearing,
  position anchoring, and unchanged system clipboard.
- Visual inspection caught and corrected a wrapping Japanese Reply label. Final
  samples checked horizontal and side actions, both attachment directions, source
  truncation, placeholders and the collapsed dot.
- Cross-app AX capture/insertion, live generation, multiple physical displays and a
  physical notch were not exercised in this run. Composer fixtures use a scratch
  destination; native layout success does not establish end-to-end insertion success.

## Reproduce

```sh
xcodegen generate
xcodebuild -project KeigoButtonMac.xcodeproj -scheme KeigoButtonMac \
  -configuration Debug -derivedDataPath /tmp/keigo-reply-build \
  build CODE_SIGNING_ALLOWED=NO
/tmp/keigo-reply-build/Build/Products/Debug/KeigoButton.app/Contents/MacOS/KeigoButton \
  --render-reply-availability
swift test
```
