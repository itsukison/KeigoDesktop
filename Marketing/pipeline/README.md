# pipeline — slideshow renderer

Renders one variant of the slideshow to 1080×1350 PNGs. **Deterministic by design:**
same inputs give the same output, no generative step anywhere on the critical path.
That is the property that makes the format mass-producible (`../GTM.md` §3).

```bash
python3 plates.py             # prepare background plates + read the annotations
python3 render.py en-cards    # English card-visual reference
python3 render.py ja-001      # Japanese post 001, Ruka handle
python3 render.py ig-001      # same post, Yuna handle
python3 render.py ja-004      # Japanese post 004
python3 render.py ja-005      # Japanese post 005
python3 render.py ja-006      # Japanese post 006
python3 render.py en-001      # English post 001 (en-001 ... en-006)
python3 render.py en-proof-001 # same EN carousel, result-state product proof
python3 render.py ja-proof-001 # same JA carousel, two-state 敬語 proof
```

The `*-proof-NNN` family is non-destructive: it writes to a `proof_...` post folder
and changes only KeigoButton's position-3 card. The other app slides, hook, account
handle, app order, CTA and caption remain the control. Its Slack context is rendered
as a compact composer derived from the existing film-set geometry: the first row pairs
the input with the expanded button bar, and the second replaces that bar with the real
result panel over the same input. The panel follows the shipped dark-ramp geometry
reproduced by the Mac landing page. This is the conversion test, not a replacement for
the control until `FORMAT-TESTS.md` records a pass.

Rendered campaigns are separated by language and variant so experiments cannot
overwrite or get mixed with one another:

```text
out/
  en/must-have-apps/en-ref/style-cards/01_hook.png ...
  en/must-have-apps/keigobutton/001_ice-dockdoor-keigo-dropover/01_hook.png ...
  ja/must-have-apps/
    ruka/
      001_ice-dockdoor-keigo-dropover/01_hook.png ... 05_dropover.png
      004_meetingbar-handmirror-keigo-localsend/01_hook.png ... 05_localsend.png
      005_velja-keka-keigo-coteditor/01_hook.png ... 05_coteditor.png
      006_amphetamine-purepaste-keigo-grandperspective/01_hook.png ... 05_grandperspective.png
    yuna/
      001_ice-dockdoor-keigo-dropover/01_hook.png ... 05_dropover.png
```

## How it works

| Stage | Tool | Why |
|---|---|---|
| Scale/crop photo to canvas | PIL | — |
| Warp a screenshot into the laptop screen | PIL 4-point perspective | CSS can do this, but PIL keeps the sampling under our control |
| Icon fan tucked behind the laptop lid | CSS `clip-path` | Draw bg → icons → **redraw bg clipped below the lid line**. The lid re-occludes the icons with no mask asset |
| All typography and card layout | headless Chrome | Real text rendering, real box model |

## Annotating a new background photo

Two one-time measurements per photo, in `plates.py:ANNOTATIONS`, in the photo's own
pixel coordinates (they are rescaled to the canvas automatically):

- **`lid`** — two points on the laptop lid's top outer edge. Err *high*: a clip line
  above the true edge is invisible, one below it lets icons draw on top of the lid.
- **`screen`** — the four display corners, clockwise from top-left. Err *outward*:
  covering a rim of bezel is invisible, leaving a rim of the original screen is not.

**Never hand-write an annotation.** Two separate bugs came from exactly that:

- On `_.jpeg`, an eyeballed screen quad left 10,692 uncovered bright pixels — the
  display narrows downward and its bottom edge slopes hard, which is unreadable on a
  dark photo. Threshold the luminance, scan per-row runs, then verify by counting
  leaked pixels before and after.
- On `Macbook Air M4 Sky Blue.jpeg`, a guessed `lid` was ~20px too high **and sloped
  the wrong way**, so post 002's icon fan floated clear of the lid. Both the fan and
  its occluding mask are derived from those two points, so they were faithfully
  drawing an edge the laptop does not have. In a bright room thresholding will not
  isolate anything — draw the candidate line onto the photo, crop tight, look at it,
  adjust. Two iterations is normal.

**The lid's horizontal extent matters as much as its height.** Only the lid can
occlude the fan, so the fan has to fit inside it: `render.fan_icon_px()` derives icon
size from the measured lid width, which is why the same format gives 210px icons on
one photo and 146px on another. Widen `lid` past the real laptop and the outer icons
clip against bare wall.

## Inputs

- `../assets/*.jpeg` — background photos (see `../GTM.md` §4 on provenance at volume)
- `icons/*.png` — app icons. Ours comes from the installed bundle:
  `sips -s format png /Applications/KeigoButton.app/Contents/Resources/AppIcon.icns --out icons/keigobutton.png --resampleHeightWidthMax 1024`
- `fonts/` — Poppins ExtraBold (headline), Dancing Script (kicker), Inter (body)
- `../assets/bar.png` and `../assets/bar_jap.png` — real English and Japanese product
  captures used by their respective card variants. The `en-*` posts use `bar.png`, the
  `ja-*`/`ig-*` posts use `bar_jap.png`; they are never crossed.
- **App Store card visuals are storefront-specific.** The `visual` assets were fetched
  for the Japanese campaign, and Amphetamine's and CotEditor's show a Japanese UI, so
  the English cards use `visual_en` (US storefront) instead. Check the language of any
  new App Store asset against the campaign that will use it.
- `source-assets/SOURCES.json` — exact official product pages, download URLs, pinned
  Git commits where available, local filenames, and SHA-256 checksums. Add an entry
  here **before** using any new app or hook asset. The legacy Pinterest hook images
  are explicitly marked incomplete because the earlier download preserved the site
  origin but not the exact pin URL.
