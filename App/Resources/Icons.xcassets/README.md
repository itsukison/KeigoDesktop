# Icons — Reicon

The window's glyphs, replacing SF Symbols.

Source: **Reicon** (https://reicon.dev, https://github.com/dqev/reicon), 24×24 grid,
**Outline** weight, MIT © Dev Chauhan. Extracted from the `reicon-react@1.2.0` package —
each icon there is a path string, so the SVGs here were assembled from the `O` (Outline)
data with `currentColor` resolved to `#000000`; the asset is a **template** image, so the
fill is replaced by the SwiftUI tint at draw time.

Naming: `icon-<role>` — the asset is named for what it does in this app, not for what
Reicon calls it. `Icon.swift` is the only place the mapping lives.

| Asset | Reicon | Used for |
|---|---|---|
| `icon-home` | Home | sidebar ホーム |
| `icon-buttons` | RowVertical | sidebar ボタン, the buttons empty state |
| `icon-settings` | Setting2 | the ⚙︎ that opens preferences |
| `icon-search` | Search | the search pill |
| `icon-add` | Add | ボタンを追加 |
| `icon-edit` | Edit2 | edit a button |
| `icon-trash` | Trash | delete a button |
| `icon-copy` | Copy | copy a history entry |
| `icon-user` | User | the account onboarding step |
| `icon-profile` | ProfileCircle | the signed-out prompt |
| `icon-wand` | WandSparkle | **nothing, currently.** Its last call site was the icon plate at the head of the signed-out account card, and that card is now a row group (§14). Kept because `Icon.Name.wand` is the obvious glyph for a rewrite and the onboarding still reaches for `wand.and.sparkles` in two places it should not |
| `icon-accessibility` | Accessibility | the Accessibility step |
| `icon-history` | History | 履歴, and its disabled empty state |
| `icon-note-add` | NoteAdd | the empty history state |
| `icon-close` | X | close the preferences modal |
| `icon-check` | Check | a completed はじめかた step |
| `icon-sliders` | SliderHorizontal | 一般 in preferences |
| `icon-info` | InfoCircle | このアプリ in preferences |
| `icon-window` | Window | an app whose icon can no longer be resolved |

`icon-buttons` was Reicon's **Category** — the 2×2 tile grid that reads as "apps" or
"categories" and says nothing about a button. **RowVertical** is two stacked rounded
bars: the object the page actually edits (a list of pill-shaped buttons) and the shape
they take on the bar. Rendered at the nav row's 17 pt it is the only candidate that is
unmistakably a pair of controls rather than a layout.

To add one: pull the `O` string out of `reicon-react`'s `icons/<Name>.js`, wrap it in a
24×24 `<svg>`, drop it in a new `icon-<role>.imageset` beside a `Contents.json` copied
from any of these, and add a case to `Icon.Name`.

## The product mark — not Reicon

Three assets here are the app's own artwork, drawn from `public/` at the repo root. They
are raster (32 / 64 px — macOS builds no 3x), not SVG, because that is the form the
artwork arrived in.

| Asset | Cut | Source | Used for |
|---|---|---|---|
| `icon-mark` | line art, **template** | `public/black.png` | `AppMark` (sidebar, onboarding), the menu-bar status item |
| `icon-mark-filled` | filled, two-tone, **not** a template | `public/bgremoved.png` | `BrandGlyph` → `BrandMark`, the overlay bar |
| `AppIcon` | the full tile | `public/default.png` | the Dock, Finder, the Accessibility dialog |

**Why two cuts.** The mark is a two-tone illustration: an off-white keycap with a black
keyline and black eyes. On the window's near-white sidebar the keyline reads as a
photograph rather than as chrome, so the window takes the line art and tints it
`#5a57ba` like every other glyph. On the overlay's `#141312` the reverse is true — the
line art's own double keyline closes into a smudge at 16 pt, while the filled art is a
white shape with two dark counters and stays legible. The menu bar needs alpha (it
inverts its contents), so it takes the template cut.

**How they were derived**, so this is repeatable:

- `icon-mark` — `public/black.png` is white strokes on pure black, so luminance *is* the
  alpha. Ramp 40→200 to drop the faint halo, crop to the content box, pad to square,
  resize. Padding to square matters: `Icon` draws into a square frame and the artwork is
  903×827, so an unpadded mask would be stretched.
- `icon-mark-color` — `public/bgremoved.png` cropped to its alpha box and padded square.
- `AppIcon` — `public/default.png` is full-bleed, and macOS does **not** mask app icons
  the way iOS does. The artwork is scaled to 824/1024 of the canvas, masked with an
  `|x|⁵+|y|⁵ ≤ 1` superellipse (the macOS icon grid's continuous-corner squircle), and
  centred on a transparent 1024. Shipping `default.png` directly would put a hard square
  in the Dock.
