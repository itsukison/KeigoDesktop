# Sidebar layout verification

The supplied draft was used for the vertical state arrangement. The implementation
uses the existing overlay palette, mascot, typography, action labels, capture-aware
instruction text, and generate behavior.

- Native Debug app build succeeds with the existing concurrency warnings.
- Rendered 324 layouts using the actual `PillRootView`, `InputBar`, `HoverRow`,
  tokens, and bundled mascot assets, with an isolated controller model and no
  account, text capture, or backend operations.
- Covered all four destinations, Japanese/English/Simplified Chinese, empty-field /
  whole-draft / selection scopes, idle / hover / composer / explicit reply states,
  signed-out hover, and empty / long instructions.
- Asserted the side composer remains exactly 208 pt wide and the same height when
  long instructions replace an empty field. Observed 208 × 252 pt for both sides.
- Inspected rendered left/right hover and composer states for text clipping,
  placeholder wrapping, mascot rendering, and mirrored attachment.
- Rebuilt and rerendered all 324 cases after tightening the hover stack from
  88 to 72 pt, reducing top-tab bottom corners to 8 pt, and replacing the wide
  composer submit strip with a 28 pt circular-arrow control aligned right.
  Inspected the narrower English action labels and a simulated 180 pt notch
  layout; actual notch hardware remains untested.

Preview: `build/verification/sidebar-layout.png` (generated, not a shipped resource).
The isolated render harness lives under `/tmp/keigo-sidebar-preview` for this session.
These checks validate rendering and geometry; live mouse interaction, focus transfer,
and typing during a cross-destination drag have not been exercised in a running app.
