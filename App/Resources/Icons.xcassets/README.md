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
| `icon-arrow-up` | AngleUp | move a button one position up |
| `icon-arrow-down` | AngleDown | move a button one position down |
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

Four assets here are the app's own artwork, drawn from `public/` at the repo root. They
are raster (32 / 64 px — macOS builds no 3x), not SVG, because that is the form the
artwork arrived in.

| Asset | Cut | Source | Used for |
|---|---|---|---|
| `KeigoAppMark` | the full-bleed blue tile | `public/generated/keigo-icon-cyan-v2.png` | `AppMark` (sidebar, onboarding) |
| `icon-mark` | line art, **template** | `public/black.png` | the menu-bar status item, `IconPlate(icon: .mark)` |
| `icon-mark-filled` | filled, two-tone, **not** a template | `public/bgremoved.png` | static source/fallback for the overlay animation |
| `KeigoAppIcon` | the full tile | `public/generated/keigo-icon-cyan-v2.png` | the Dock, Finder, the Accessibility dialog |

**Why the cuts.** The mark is a two-tone illustration: an off-white keycap with a black
keyline and black eyes. The window's brand row shows the full-bleed cyan artwork
(the same cut `KeigoAppIcon` ships) clipped to a rounded
tile in `AppMark`. On the overlay's `#141312` the line art's own double keyline closes
into a smudge at 16 pt, while the filled art is a white shape with two dark counters
and stays legible. The menu bar needs alpha (it inverts its contents), so it takes the
template cut.

**How they were derived**, so this is repeatable:

- `KeigoAppMark` — generated blue artwork resized to 64 / 128, full bleed. Corners
  are rounded at draw time by `AppMark` (22.5 %, continuous).
- `icon-mark` — `public/black.png` is white strokes on pure black, so luminance *is* the
  alpha. Ramp 40→200 to drop the faint halo, crop to the content box, pad to square,
  resize. Padding to square matters: `Icon` draws into a square frame and the artwork is
  903×827, so an unpadded mask would be stretched.
- `icon-mark-color` — `public/bgremoved.png` cropped to its alpha box and padded square.
- `KeigoAppIcon` — generated blue artwork inset to 824/1024, masked with a
  superellipse, and centered on a transparent canvas for macOS.

The overlay's live mark is now three 4×4 transparent atlases in `Assets.xcassets`:
`MascotIdleSprite`, `MascotEngagedSprite` and `MascotThinkingSprite`. Higgsfield
Seedance 2.0 generated them from `public/bgremoved.png` as first and last frame; the
4-second clips were sampled at 4 fps, chroma-keyed, normalized to one stable crop and
tiled into 16-frame PNGs. The generation ids are recorded in `AGENTS.md` §8 so the
sources are reproducible.

### Current cyan app icon

`KeigoAppIcon` is the selected app icon; `KeigoAppMark` is the matching full-bleed
window mark. The generated source is `public/generated/keigo-icon-cyan-v2.png`.
`swift scripts/prepare-app-icon.swift` emits the ten macOS icon sizes with the
existing 824/1024 superellipse grid and the 64/128 px window mark. Legacy
`AppIcon` / `icon-brand` names are regenerated as identical blue aliases, so older
references cannot reintroduce a purple tile.
The menu template, overlay sprites, and onboarding character are unchanged by this icon.
