# Bar positioning: growing away from the edge

Status: **decided, not implemented.** Written on a laptop with no Xcode; needs to be
built and watched on screen on the machine that can run it, per AGENTS.md's own
"Not verified" convention. Nothing in this file should be treated as shipped
behavior until it has been.

## The problem

AGENTS.md §4 documents the pill as bottom-center, draggable, and told never to
resize in a way that carries the previous frame's position over (`OverlayPlacement.
reframe`, `anchorY`). That's correct for where the bar lives today, but it was never
tested off that one spot. Two things assume "the bar is near the bottom, and nothing
is to its immediate left or right":

1. The hover row grows *wider* — 4 buttons + ✎ can go past 400 pt (§4, "Hover row
   layout").
2. The generating capsule, the result panel, the error toast, and the reply-context
   card all grow *taller* above the bar — up to 440 pt for the result panel.

If the bar can end up anywhere the user drags it — a corner, an edge, the top of the
screen — both of those assumptions can put a window off-screen or visually detached
from the bar.

## Decision

Free dragging, not a Willow-style snap-to-slot picker (the 8-zone drag overlay in
`willow positioning.png`). The picker is a real feature on its own — a whole new
drag-overlay UI — and isn't needed to fix the actual problem, which is that
*expansion direction* doesn't yet know where the bar is. Revisit the picker later if
we want it purely for discoverability; it changes nothing about the rule below.

## The rule

**Grow away from whichever edge you're touching. If you're not touching an edge on
that axis, grow from the center, same as today.**

That's the whole rule, on both axes independently:

| Bar position | Horizontal growth | Vertical growth |
|---|---|---|
| Bottom-center (today) | left + right, from center | upward |
| Top-center | left + right, from center | downward |
| Left edge, mid-height | rightward only | from center |
| Right edge, mid-height | leftward only | from center |
| Top-left corner | rightward only | downward |
| Top-right corner | leftward only | downward |
| Bottom-left corner | rightward only | upward |
| Bottom-right corner | leftward only | upward |

## What already works, for free

The horizontal case is already handled. `OverlayPlacement.reframe` computes the
resized frame by keeping the *center* fixed, then calls `clamp(_:to:)`, which is a
plain `min`/`max` on each axis. Traced by hand for a bar sitting flush against the
left edge (`origin.x == workArea.minX`): the centered target frame's `origin.x` goes
negative, `clamp` pulls it back to exactly `workArea.minX`, and the result is a
window whose left edge is unchanged and whose right edge extends outward. Flush
against the right edge, the same clamp pins the *right* edge and extends left. This
is `min`/`max` doing the "grow away from the edge" rule by accident, not by design,
but it already does it correctly — no code change needed there.

The same reasoning applies to `anchorY` / `reframe`'s vertical component for the
small hover-row height change (28 → 34 pt): if the bar is flush against the top of
the work area, the clamp on `origin.y` pins the top and pushes the bottom edge down;
flush against the bottom, it pins the bottom and pushes the top edge up. Also already
correct, and the height delta here is small enough (6 pt) that even a floating
mid-screen position wouldn't look wrong if it leaned one way.

## What actually needs to change

Three places hardcode "I sit above the bar" and do not go through `clamp` in a way
that saves them the way the horizontal case is saved — clamping a 440 pt panel that's
been placed 440 pt above a bar near the top of the screen just slides it back onto
the screen, landing it far from the bar rather than beside it:

- `OverlayPlacement.auxiliaryFrame(size:anchoredTo:)` — used by the generating
  capsule and the result panel. Currently always `y: bar.minY`, i.e. always grows
  upward from the bar's bottom edge.
- `ErrorPanel` — `desiredBottom = anchor.frame.maxY + 8`, always above.
- `ReplyContextPanel.frame(anchoredTo:)` — `y: anchor.maxY + replyContextGap`,
  always above.

All three need the same new decision instead of the hardcoded "above": compare the
room above the bar (`workArea.maxY - bar.maxY`) against the room below it
(`bar.minY - workArea.minY`), and anchor to whichever side has more room. That
computation belongs in one place — most naturally a new `OverlayPlacement` helper
(e.g. `verticalSide(for bar: NSRect, on screen: NSScreen) -> Edge` returning `.above`
or `.below`) — so the three call sites ask the same question the same way instead of
three separately-reasoned answers drifting apart, the way the "above the bar" answer
already exists in three different files today.

Horizontal placement of these panels (`x: bar.midX - size.width / 2`, then
`clampToWorkArea`) does not need this treatment — it already gets the same
center-then-clamp trick the hover row does, for the same reason.

## Left open

- **The notch.** On a MacBook with the camera cutout, a bar dragged to top-center
  should sit just below the notch, not behind it. Not designed yet — needs a way to
  read the notch's safe-area geometry (`NSScreen.safeAreaInsets`, macOS 12+) and treat
  it as extra top inset only on displays that report one.
- **Whether "touching an edge" needs a tolerance.** The clamp-based trick above only
  engages once the naive centered/growing target would actually overflow the work
  area — there's no separate margin or threshold to tune, which is simpler than it
  sounded going in. Worth confirming on screen that a bar dragged *near but not
  flush against* an edge doesn't end up half-clipped before the clamp kicks in.
- Reordering these panels' z-order / show-hide handoff (§4's "the bar returns before
  they leave and leaves after they arrive") is unaffected by any of this — that's
  about *when* a panel is on screen, this file is only about *where*.
