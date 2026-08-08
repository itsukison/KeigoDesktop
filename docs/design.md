# Willow — Style Reference

> Cool neutral SaaS on a white sheet. A grey frame, a white panel floating inside it,
> hairline-bordered cards, and one indigo that is allowed to be the interface.

**Theme:** light

**Source:** measured, not eyeballed, from `reference/Screenshot 2026-08-07 at 19.14.39.png`
(Home), `…19.14.45.png` (Style Matching) and `…19.14.53.png` (Settings) — Willow Voice's
own window at 1058×744. Every value below either has a pixel behind it or is marked
**【推測】**. The window's *interaction* model is documented in `AGENTS.md` §4; this file
is only about how it looks.

Willow runs on a cool near-white system: a `#f2f2f4` window frame, a `#f5f6f7` sidebar,
and the content as a pure-white panel floating inside the frame with a 4 pt margin and a
12 pt radius. Cards are white **on** white and are told apart by a 1 pt `#ececee`
hairline rather than by a deeper fill. Type is a neutral UI sans carried by weight — 600
for stat numbers and page titles, 500 for row labels, 400 for prose — at 12–20 pt, with
`#4e4d51` as the darkest text in the window. A single indigo `#5a57ba` runs the chrome:
filled primary buttons, switches, links, badges and selected states. Green `#46a588`
marks completion. Radii are moderate and varied — 8 pt buttons and rows, 12 pt small
cards, 16 pt cards, 24 pt modal — with the full pill reserved for a handful of prominent
CTAs. The system feels like a well-built Mac productivity app: quiet surfaces, one
confident accent, and no decoration that is not a control.

## Tokens — Colors

| Name | Value | Token | Role |
|------|-------|-------|------|
| Shell | `#f2f2f4` | `--color-shell` | The window itself. Visible as the margin around the content panel — the panel's separation from the sidebar *is* this colour, not a divider line |
| Sidebar | `#f5f6f7` | `--color-sidebar` | Navigation column. 【推測】in the reference this is an `NSVisualEffectView` sidebar material; `#f5f6f7` is where it lands over a light desktop |
| White | `#ffffff` | `--color-white` | The content panel and every card on it. Pure white — there is no warm off-white anywhere in this system |
| Mist | `#f5f5f5` | `--color-mist` | Search pills, icon plates, hover fills, segmented tracks |
| Fog | `#f7f7f8` | `--color-fog` | Grouped containers that hold cards of their own (the Learning Center block, the settings modal's nav pane) |
| Cloud | `#ededef` | `--color-cloud` | The **active** sidebar row. Selection darkens; it does not lift |
| Hairline | `#ececee` | `--color-hairline` | Card borders and row separators. 【推測】on the value: a 1 pt border downscales to `#f8f8f8`–`#fafafa` in the reference screenshots, so the ratio is measured and the endpoint is inferred |
| Ink | `#4e4d51` | `--color-ink` | Primary text. A soft near-black, never `#000000` |
| Slate | `#8a8a90` | `--color-slate` | Secondary text, row subtitles, stat labels. 【推測】— thin antialiased type does not survive the screenshot's downscale |
| Ash | `#b3b3b8` | `--color-ash` | Captions, timestamps, day labels, placeholder text. 【推測】, same reason |
| Indigo | `#5a57ba` | `--color-indigo` | **UI chrome.** Primary button fills, switches that are on, selected radios, progress marks |
| Indigo Text | `#5856b5` | `--color-indigo-text` | Links and badge labels, where the fill weight of Indigo is too heavy for type |
| Indigo Tint | `#edeefa` | `--color-indigo-tint` | Filled accent surfaces — the plan card, a keycap chip |
| Indigo Track | `#e6e5fd` | `--color-indigo-track` | The lighter track behind a switch that is on |
| Indigo Plate | `#e4e5f0` | `--color-indigo-plate` | Badge plates — a step greyer than the tint |
| Green | `#46a588` | `--color-green` | Completed, granted, connected. The only non-accent colour in the system |
| Control Off | `#d9d9da` | `--color-control-off` | A switch that is off, and any disabled control fill |

## Tokens — Typography

One face, weight-driven. The reference sets a neutral grotesque throughout — Inter is the
closest freely-licensed match and is what this app bundles; the system font is an
acceptable fallback.

### Inter — everything

- **Weights:** 400 (prose), 500 (row labels, buttons, nav), 600 (page titles, stat numbers)
- **Sizes:** 11px, 12px, 13px, 14px, 15px, 17px, 20px, 26px
- **Letter spacing:** −0.01em at 18px and above; normal below
- **Role:** hierarchy comes from weight and colour, not from size. The window's largest
  routine type is a 20 px page title; the only larger figures are stat numbers.

### Geist Mono — technical micro-copy

- **Weights:** 400
- **Sizes:** 12px
- **Role:** timestamps in the history list, card indices, version strings. A monospaced
  timestamp is what keeps a list's left edge straight.

### Type Scale

| Role | Size | Weight | Token |
|------|------|--------|-------|
| caption | 11px | 400 | `--text-caption` |
| meta | 12px | 400–500 | `--text-meta` |
| body-sm | 13px | 400 | `--text-body-sm` |
| body | 14px | 400 | `--text-body` |
| row-label | 14px | 500 | `--text-row-label` |
| section | 15px | 500 | `--text-section` |
| sheet-title | 17px | 600 | `--text-sheet-title` |
| page-title | 20px | 600 | `--text-page-title` |
| stat | 26px | 600 | `--text-stat` |

## Tokens — Spacing & Shapes

**Base unit:** 4px · **Density:** comfortable, but tighter than an editorial system —
cards are padded 20, not 32.

### Spacing Scale

`2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 32`

### Border Radius

| Element | Value |
|---------|-------|
| buttons | 8px |
| inputs | 8px |
| rows / nav items | 8px |
| small cards | 12px |
| content panel | 12px |
| cards | 16px |
| modal sheet | 24px |
| search fields, badges, pills | 9999px |

### Elevation

The system separates with **borders**, and elevates in exactly three places:

| What | Shadow |
|------|--------|
| Content panel | `rgba(0,0,0,0.06) 0 1px 6px` — enough to lift it off the shell |
| Modal sheet | `rgba(0,0,0,0.22) 0 12px 40px` over a 40% black scrim |
| A row being dragged | `rgba(0,0,0,0.12) 0 3px 10px` |

Everything else — cards, groups, rows, buttons — is flat with a hairline.

### Layout

- **Sidebar:** 218px, full height, flush to the window's left and top edges
- **Content panel:** fills the rest, inset 4px from the top, right and bottom
- **Page padding:** 32px horizontal, 32px top (clears the transparent titlebar)
- **Section gap:** 28px · **Card padding:** 20–24px · **Element gap:** 8–16px

## Components

### Primary Button
Indigo `#5a57ba` fill, white text, 8px radius, 14px horizontal padding, 32px tall,
Inter 13/500. Hover drops to 88% opacity. This is the system's only filled button.

### Secondary Button
White fill, `#4e4d51` text, 1px `#ececee` border, 8px radius. Hovers to `#f5f5f5`. Used
for row-level actions — "Change Bindings", "Change Languages", "Reset".

### Pill Button
The same two styles at 9999px radius and 18px padding. Reserved for prominent standalone
CTAs (the reference uses it for "Invite" and the upgrade offer) — not for actions that sit
inside a row.

### Card
White fill, 16px radius, 1px `#ececee` border, 20px padding, no shadow. **The border is
what makes it a card** — it is the same colour as the panel it sits on.

### Row Group
A card with zero padding holding rows separated by full-width `#ececee` hairlines, clipped
to the card's radius. Each row is a title (14/500), an optional subtitle (13/400 slate),
and a trailing control.

### Section Caption
12px/500 in ash, sitting *above* the card it labels. Groups are never titled from inside.

### Section Header
15px/500 title with an optional indigo text link on the far right ("Open Learning
Center").

### Text Input
**A fill, not a box.** `#f7f7f8`, 8px radius, **no border** — the tone separates the
field from the white behind it and a form of three reads as three shapes rather than
three outlines. A border appears only on focus, 1.5px in indigo.

### Search Field
9999px capsule, `#f5f5f5` fill, no border, magnifier glyph, 30px tall.

### Segmented Tabs
A `#f5f5f5` track with 3px padding; the active tab is a white 8px-radius pill with its own
hairline. Inactive tabs are transparent with slate text.

### Switch
Indigo when on, `#d9d9da` when off, `#e6e5fd` track. Every toggle in the window is this
one control.

### Badge / Chip
9999px or 8px plate in `#e4e5f0` / `#edeefa` with `#5856b5` 12–13px medium text. The
reference's keycap chip and "Update" badge are the same object.

### Numbered Task Card
148×148, white, 12px radius, hairline border. Index top-left in mono, a state mark
top-right (indigo filled check when done, `#d9d9da` ring when not), then a glyph and a
2-line title. Laid out in a horizontal scroller inside a `#f7f7f8` group.

### Stat Row
One card, four equal columns. Label 13px slate above, value 26px/600 ink with its unit
13px slate on the same baseline.

### Sidebar Nav Item
Icon (14pt) + label (14/400, 500 when active), 34px tall, 8px radius, full-width inside a
10px gutter. Active fill `#ededef`; hover is the same at half strength.

### Modal Sheet
A centred card over a 40% black scrim — not a titlebar sheet. Two panes: a `#f7f7f8`
navigation column with icon rows, and a white content pane with a 17px/600 title, a round
grey close button top-right, and captioned row groups below. 24px radius.

### Round Icon Button
A 30px `#f5f5f5` disc with a centred glyph; hovers to `#ededef`. Used for close, share and
overflow.

## Iconography

**Reicon Outline** (https://reicon.dev, MIT © Dev Chauhan) — 24×24 grid, one hairline
weight, drawn as filled paths rather than strokes so they hold their shape at any size.
Not SF Symbols: the system set draws at Apple's own weights and optical sizes, which
reads as macOS chrome rather than as the app, and mixing the two is visible immediately
in a sidebar.

- One weight throughout. The Filled variant exists in the library and is not used here.
- Sizes: 20 pt in a task card, 17 pt in a nav row, 15 pt in an icon button, 14 pt inside
  a text button or search pill, and `diameter × 0.46` inside a plate.
- Icons take the surrounding text colour — they are template images, never coloured
  independently.
- The exception is real application icons (the apps a user works in), which are full
  colour and come from the system.

## Do's and Don'ts

### Do
- Put the content on a **white panel floating inside a grey window** — the 4 pt margin is
  the separation, so no divider line between sidebar and content.
- Tell cards apart from the page with a 1 px `#ececee` border, never with a deeper fill.
- Use indigo `#5a57ba` for primary buttons, switches, links, badges and selected states.
  It is the interface, not decoration.
- Carry hierarchy with **weight** — 600 for numbers and titles, 500 for labels, 400 for
  prose — and keep sizes between 11 and 20 px.
- Darken the active sidebar row (`#ededef`). Do not lighten it.
- Caption a group from above it, in 12px ash, outside the box.
- Give inputs a `#f7f7f8` fill and no border; save the outline for focus.
- Draw every glyph from one icon set at one weight (see Iconography).
- Keep `#4e4d51` as the darkest text in the window.
- Vary the radius by role: 8 for controls, 12 for small cards and the panel, 16 for cards,
  24 for the modal.

### Don't
- Don't use pure black `#000000` for text or fills.
- Don't reach for a warm off-white. The whole ramp is cool and the canvas is `#ffffff`.
- Don't put a full pill on an action that lives inside a row — 8 px is the row shape.
- Don't add a second accent colour. Indigo runs the chrome; green marks completion; that
  is the entire palette's colour budget.
- Don't set a page title above 20 px, and don't set body copy in a light weight.
- Don't separate with drop shadows. Three surfaces elevate (panel, modal, dragged row);
  everything else is a hairline.
- Don't outline a field, and don't nest a grey fill inside a grey panel — that is two
  containers doing one container's job.
- Don't mix icon sets, and don't fall back to SF Symbols for "just this one".
- Don't title a card from inside it when a caption above it will do.

## Surfaces

| Level | Name | Value | Purpose |
|-------|------|-------|---------|
| 0 | Shell | `#f2f2f4` | The window, seen only as a margin |
| 1 | Sidebar | `#f5f6f7` | Navigation |
| 2 | Panel / Card | `#ffffff` | Content, and every card on it |
| 3 | Group | `#f7f7f8` | A container that holds cards |
| 3 | Mist | `#f5f5f5` | Quiet fills: search, plates, hovers |
| 4 | Cloud | `#ededef` | Selection |

## Quick Start

```css
:root {
  /* Colours */
  --color-shell: #f2f2f4;
  --color-sidebar: #f5f6f7;
  --color-white: #ffffff;
  --color-mist: #f5f5f5;
  --color-fog: #f7f7f8;
  --color-cloud: #ededef;
  --color-hairline: #ececee;
  --color-ink: #4e4d51;
  --color-slate: #8a8a90;
  --color-ash: #b3b3b8;
  --color-indigo: #5a57ba;
  --color-indigo-text: #5856b5;
  --color-indigo-tint: #edeefa;
  --color-indigo-track: #e6e5fd;
  --color-indigo-plate: #e4e5f0;
  --color-green: #46a588;
  --color-control-off: #d9d9da;

  /* Type */
  --font-ui: 'Inter', ui-sans-serif, system-ui, -apple-system, sans-serif;
  --font-mono: 'Geist Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  --text-caption: 11px;
  --text-meta: 12px;
  --text-body-sm: 13px;
  --text-body: 14px;
  --text-section: 15px;
  --text-sheet-title: 17px;
  --text-page-title: 20px;
  --text-stat: 26px;
  --weight-regular: 400;
  --weight-medium: 500;
  --weight-semibold: 600;

  /* Shape */
  --radius-button: 8px;
  --radius-input: 8px;
  --radius-row: 8px;
  --radius-small-card: 12px;
  --radius-panel: 12px;
  --radius-card: 16px;
  --radius-sheet: 24px;
  --radius-full: 9999px;

  /* Layout */
  --sidebar-width: 218px;
  --panel-inset: 4px;
  --page-padding: 32px;
  --card-padding: 20px;
  --section-gap: 28px;

  /* Elevation */
  --shadow-panel: rgba(0, 0, 0, 0.06) 0 1px 6px;
  --shadow-sheet: rgba(0, 0, 0, 0.22) 0 12px 40px;
  --shadow-drag: rgba(0, 0, 0, 0.12) 0 3px 10px;
  --scrim: rgba(0, 0, 0, 0.4);
}
```

## What this file replaced

Until 2026-08-07 this was an ElevenLabs website reference: a warm eggshell canvas
(`#fdfcfc`), taupe fill-differentiated cards, whisper-weight 300 display type at 32–48 px,
9999 px pills everywhere, and two accents (`#0447ff` / `#ff4704`) that were **forbidden**
on buttons, links, badges and focus rings. Willow contradicts all five of those. **None of
it survives.** The last holdout was the overlay's generating capsule, whose rotating
violet→orange border was grandfathered in `AGENTS.md` §8 until it was checked against
`reference/generating.png` and turned out not to be what that image shows either — it is
now a measured full-spectrum sweep. The dark overlay ramp remains, but it was only ever
*described* as a derivation of the warm palette; it is simply its own ramp.
