# Edge-attached generation and results

The implementation gives generation/results explicit snap-zone geometry, with stable
attachment during content resizing and screen/work-area changes. The result goes directly
from header to answer; regeneration and guidance use the existing footer control.
Local instruction metadata remains independent of backend prompts and attempt analytics.
The existing page history, write destination, failure recovery and refinement flow remain.

## Verification

- Debug Xcode build passed, including the native Metal generation dependency.
- `swift test`: 358 tests passed. New tests cover four-way attachment across content
  sizes and offset displays, notch anchoring, Dock geometry changes, constrained work
  areas, and instruction inheritance through regeneration/editing.
- The isolated native renderer exercised Polish/custom/long results in Japanese,
  English and Chinese at all four positions; measured result frames stayed within
  the then-current 440 pt cap. Generation remained never-key and shadow-free.
- Local fixture responses exercised successful regeneration appending pages,
  instruction inheritance, refinement, earlier-page selection, generation failure
  restoring the selected session, and cancellation restoring that session.
- Before removal of the separate instruction editor, native UI checks confirmed Edit opens the complete instruction; Escape cancels
  editing without closing the answer; Return regenerates the edited instruction
  instead of accepting the answer; pager navigation restores the earlier instruction.
- Final visual review is assigned to the user. Animated Metal effects are not reliably
  represented by `NSView.cacheDisplay`; the automated generation PNGs are not visual
  evidence of the live effect. Use the interactive preview or actual overlay.
- Live cross-application Copy/Insert, physical multi-display/notch hardware, and system
  accessibility display settings were not rerun end to end for this change.

## Native review

Build the Debug `KeigoButtonMac` scheme and launch its executable with
`--preview-edge-panels`. The local preview offers all four positions, Polish/custom/long
answers, a held generation state, and three interface languages. It uses isolated
in-memory authentication, local response fixtures, temporary data, and no-op analytics.
It does not send requests to production. Cancel exits the held generation state.

`--render-edge-panels` renders fixtures and runs the local regeneration/recovery checks
into `/private/tmp/keigo-edge-previews`. Neither flag runs normal app startup. Normal
launch uses the same production panels with the real capture and insertion flow.

The verified Debug build is at
`/private/tmp/keigo-edge-build/Build/Products/Debug/KeigoButton.app`.

## Feedback revision

Removed the above-answer prompt summary/editor. Restored the colorful rainbow beam
and static accessibility rim. Side generation is 176 × 60 pt; side results are 320 pt
wide, with a 320 pt answer viewport and 520 pt overall cap. Bottom/top sizes are
unchanged. Shared smoked-glass material is preserved. Visual review remains with the
user; the earlier editor checks above describe the superseded UI.

Revision validation: Debug build passed; all five `CompanionPanelTests` passed,
including resizing to the taller side limit across offset displays. Visual and live
Copy/Insert checks were not rerun for this revision.
