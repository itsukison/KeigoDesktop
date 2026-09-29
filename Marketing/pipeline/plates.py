#!/usr/bin/env python3
"""Background plate preparation for the slideshow pipeline.

Two jobs, both deterministic:

  1. Crop/scale a source photo to the 1080x1350 canvas.
  2. Warp a screenshot into an annotated screen quad (4-point perspective).

Every photo needs a one-time annotation in ANNOTATIONS below: the lid's top edge
(for the icon-fan occlusion on the hook slide) and the screen's four corners (for
the screen composite). Those numbers are in SOURCE pixel coordinates; this module
scales them to the canvas so the annotation survives a change of output size.
"""

import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent
ASSETS = ROOT.parent / "assets"
OUT = ROOT / "plates"

CANVAS = (1080, 1350)

# One-time hand annotations, in each source photo's own pixel space.
#   lid:    two points along the laptop lid's top outer edge
#   screen: display-glass corners, clockwise from top-left
ANNOTATIONS = {
    "_.jpeg": {
        "size": (736, 981),
        # Screen corners were measured by brightness segmentation, not by eye: the
        # display narrows downward and its bottom edge slopes hard right, which is
        # not readable off a dark photo. Nudged ~4px outward so the warp overshoots
        # into the bezel rather than leaving a sliver of the original screen.
        # Verified numerically: this quad leaves 947 uncovered bright screen px
        # (down from 10,692), the residue being the notch and the corner radii.
        # Erring outward is deliberate — covering a rim of bezel is invisible,
        # leaving a rim of the original lock screen is not.
        "lid": [(92, 272), (671, 268)],
        "screen": [(92, 278), (671, 274), (630, 726), (84, 623)],
        "crop": "top",  # keep the top of the frame; the text lives there
    },
    "Macbook Air M4 Sky Blue.jpeg": {
        "size": (736, 981),
        # Measured against a probe overlay, replacing hand-guessed values that were
        # ~20px too high and sloped the wrong way. That single wrong pair was the
        # whole reason post 002's icon fan floated clear of the lid: the mask and the
        # fan are both derived from these two points, so they were faithfully drawing
        # an edge the laptop does not have. The lid also ends at x=573, not 640 —
        # anything wider clips icons against empty wall.
        "lid": [(168, 329), (573, 312)],
        "screen": [(163, 307), (637, 299), (645, 632), (155, 640)],
        "crop": "top",
    },
    "Macbook ios ideas.jpeg": {
        "size": (736, 981),
        # Also re-measured: was ~10px high with the slope inverted.
        "lid": [(60, 362), (690, 359)],
        "screen": [(58, 373), (688, 376), (691, 791), (55, 787)],
        "crop": "center",
    },
    "summer.jpeg": {
        "size": (736, 981),
        # Measured on a 2x probe overlay. The laptop is photographed from below and
        # its right edge leaves the frame, so both the lid and display deliberately
        # continue to x=735 instead of inventing an in-frame corner.
        "lid": [(230, 338), (735, 311)],
        "screen": [(230, 342), (735, 317), (735, 850), (178, 774)],
        "crop": "top",
    },
    "macbook wallpaper.jpeg": {
        "size": (736, 981),
        # Re-measured after the first render exposed a wall-coloured gap between the
        # fan and the bezel. A vertical luminance scan across x=175...735 puts the
        # dark outer edge on y=273...239 with <= 1.1 px residual; the previous left
        # endpoint was 16 px too high. Start at x=175 where the straight top edge
        # begins, rather than treating the rounded corner as usable lid width. The
        # right side of the display continues beyond the photograph.
        "lid": [(175, 273), (735, 239)],
        "screen": [(171, 272), (735, 255), (735, 804), (171, 827)],
        "crop": "top",
    },
}


def _scale_factor(src_size):
    """Cover the canvas by width, which is how all three plates are framed."""
    return CANVAS[0] / src_size[0]


def _crop_box(scaled_h, mode):
    if scaled_h <= CANVAS[1]:
        return (0, 0)
    excess = scaled_h - CANVAS[1]
    top = 0 if mode == "top" else excess // 2
    return (0, top)


def load_plate(name):
    """Return (image, meta) with the photo fitted to CANVAS and annotations mapped."""
    ann = ANNOTATIONS[name]
    im = Image.open(ASSETS / name).convert("RGB")
    if im.size != tuple(ann["size"]):
        raise SystemExit(
            f"{name}: expected {ann['size']}, found {im.size} — reannotate before use"
        )

    k = _scale_factor(im.size)
    scaled = im.resize((CANVAS[0], round(im.height * k)), Image.LANCZOS)
    ox, oy = _crop_box(scaled.height, ann["crop"])
    plate = scaled.crop((ox, oy, ox + CANVAS[0], oy + CANVAS[1]))

    def to_canvas(p):
        return (round(p[0] * k - ox), round(p[1] * k - oy))

    meta = {
        "lid": [to_canvas(p) for p in ann["lid"]],
        "screen": [to_canvas(p) for p in ann["screen"]],
    }
    # Extend the lid edge to both canvas margins so it can be used as a clip line.
    (x1, y1), (x2, y2) = meta["lid"]
    slope = (y2 - y1) / (x2 - x1)
    meta["lid_line"] = [
        [0, round(y1 + (0 - x1) * slope)],
        [CANVAS[0], round(y1 + (CANVAS[0] - x1) * slope)],
    ]
    return plate, meta


def _perspective_coeffs(dest_quad, src_quad):
    """Coefficients for PIL's PERSPECTIVE transform (maps dest -> src)."""
    m = []
    for (dx, dy), (sx, sy) in zip(dest_quad, src_quad):
        m.append([dx, dy, 1, 0, 0, 0, -sx * dx, -sx * dy])
        m.append([0, 0, 0, dx, dy, 1, -sy * dx, -sy * dy])
    A = np.array(m, dtype=float)
    b = np.array(src_quad, dtype=float).reshape(8)
    return np.linalg.lstsq(A, b, rcond=None)[0]


def composite_screen(plate, quad, screenshot_path, soften=0.8, grain=2.4,
                     light=0.40, edge=0.20, lift=1.10):
    """Warp a screenshot into `quad` and make it belong to the photograph.

    The warp alone always reads as pasted-on, because the screenshot carries no
    trace of the room the photo was taken in. So rather than invent lighting, we
    transfer the real thing: the original screen's own low-frequency luminance is
    extracted, normalised to a mean of 1.0, and multiplied over the new content.
    Whatever glare, vignette and falloff that display actually had, the composite
    now has — whicih is why this never needs a generative pass.

    Exposure is matched to the display it replaces, so the screen emits about as
    much light as it did in the photo, then nudged up by `lift`. The tuning is
    deliberately conservative: this slide exists so viewers can SEE the button bar,
    and a fully photoreal composite crushed the UI past reading. Legibility wins.

      soften  gaussian blur, matching the plate's own upscaling softness
      grain   luminance noise, matching the photo's sensor noise
      light   how much of the measured lighting field to apply (0 = none)
      edge    extra darkening in the last few px before the bezel
      lift    exposure bias above the measured match, for legibility
    """
    from PIL import ImageDraw

    shot = Image.open(screenshot_path).convert("RGB")
    coeffs = _perspective_coeffs(quad, [(0, 0), (shot.width, 0),
                                        (shot.width, shot.height), (0, shot.height)])
    warped = shot.transform(plate.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)

    mask = Image.new("L", plate.size, 0)
    ImageDraw.Draw(mask).polygon([tuple(p) for p in quad], fill=255)
    inside = np.array(mask) > 128

    a = np.array(warped, dtype=float)

    # Match the replaced display's exposure, then bias upward for legibility.
    ref_mean = np.array(plate.convert("L"), dtype=float)[inside].mean()
    cur_mean = np.array(Image.fromarray(a.astype(np.uint8)).convert("L"),
                        dtype=float)[inside].mean()
    if cur_mean > 1:
        a *= lift * (ref_mean / cur_mean)

    if light > 0:
        # The lighting field: the original screen, blurred until only illumination
        # is left, then flattened to a multiplier around 1.0.
        field = np.array(
            plate.convert("L").filter(ImageFilter.GaussianBlur(60)), dtype=float
        )
        ref = field[inside].mean()
        if ref > 1:
            m = 1.0 + light * (field / ref - 1.0)
            a *= m[:, :, None]

    if edge > 0:
        # Distance-to-bezel falloff, from the mask itself so it follows the quad.
        inner = mask.filter(ImageFilter.GaussianBlur(9))
        f = np.array(inner, dtype=float) / 255.0
        a *= (1.0 - edge * (1.0 - f))[:, :, None]

    if grain > 0:
        rng = np.random.default_rng(7)  # fixed seed: the pipeline stays deterministic
        a += rng.normal(0.0, grain, a.shape[:2])[:, :, None]

    out = plate.copy()
    lit = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if soften > 0:
        lit = lit.filter(ImageFilter.GaussianBlur(soften))
    out.paste(lit, (0, 0), mask.filter(ImageFilter.GaussianBlur(0.8)))
    return out


def fit_visual(src, out, size=(700, 340), focus="center"):
    """Centre-crop an app visual to one aspect so every card reads the same.

    Card-sized visuals are the reason the public app art is usable at all: these
    are marketing banners at four different aspects (Ice 2.05, DockDoor 1.07,
    Dropover 1.30), and a banner behaves inside a rounded rect the way it never
    could warped onto a laptop screen.
    """
    im = Image.open(src).convert("RGB")
    tw, th = size
    scale = max(tw / im.width, th / im.height)
    r = im.resize((max(tw, round(im.width * scale)), max(th, round(im.height * scale))),
                  Image.LANCZOS)
    left = (r.width - tw) // 2
    if r.height <= th:
        top = 0
    elif focus == "bottom":
        top = r.height - th      # keep the bottom: that is where our button bar is
    elif focus == "top":
        top = 0
    else:
        top = (r.height - th) // 2
    r.crop((left, top, left + tw, top + th)).save(out)
    return out


# Bands measured in assets/bar.png (480x251) by row luminance: wallpaper above the
# overlay pill, the pill itself, a gap, then the real Dock.
BAR_BANDS = {"wallpaper": (0, 141), "pill": (141, 176), "gap": (176, 197),
             "dock": (197, 251)}


def desktop_plate(bar_src, visual=None, include_bar=True, size=(1600, 1000),
                  window_frac=0.66):
    """Build a 16:10 desktop screen out of the real bar screenshot.

    `bar.png` is a bottom-of-screen crop, not a display, so it cannot be warped into
    a laptop screen directly — the aspect is wrong and there is no upper desktop. The
    fix is to rebuild a full screen from its own parts: stretch only the wallpaper
    band to make up the missing height, and keep the pill and Dock at true scale so
    the product never looks distorted.

    Every app gets the same wallpaper and the same Dock, so the four slides read as
    four apps on one Mac rather than four unrelated screenshots. `include_bar` keeps
    our overlay pill; the other apps get their own art as a floating window instead.
    """
    from PIL import ImageDraw, ImageFilter

    W, H = size
    bar = Image.open(bar_src).convert("RGB")
    k = W / bar.width

    def band(name):
        a, b = BAR_BANDS[name]
        return bar.crop((0, a, bar.width, b)).resize(
            (W, max(1, round((b - a) * k))), Image.LANCZOS)

    lower = ["pill", "gap", "dock"] if include_bar else ["gap", "dock"]
    lower_imgs = [band(n) for n in lower]
    lower_h = sum(i.height for i in lower_imgs)

    wall = band("wallpaper").resize((W, max(1, H - lower_h)), Image.LANCZOS)

    out = Image.new("RGB", (W, H))
    out.paste(wall, (0, 0))
    y = wall.height
    for i in lower_imgs:
        out.paste(i, (0, y)); y += i.height

    if visual is not None:
        v = Image.open(visual).convert("RGB")
        tw = round(W * window_frac)
        th = round(v.height * tw / v.width)
        ceiling = round(H * 0.62)
        if th > ceiling:
            th = ceiling; tw = round(v.width * th / v.height)
        v = v.resize((tw, th), Image.LANCZOS)

        card = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
        m = Image.new("L", (tw, th), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, tw - 1, th - 1], 18, fill=255)
        card.paste(v, (0, 0)); card.putalpha(m)

        x = (W - tw) // 2
        yy = max(round(H * 0.06), wall.height - th - round(H * 0.05))

        sh = Image.new("L", (W, H), 0)
        ImageDraw.Draw(sh).rounded_rectangle(
            [x, yy + 12, x + tw, yy + th + 22], 18, fill=150)
        out = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), out,
                              sh.filter(ImageFilter.GaussianBlur(22)))
        out.paste(card, (x, yy), card)

    return out


def blurred_backdrop(name, blur=56, darken=0.68):
    """A heavily blurred, darkened plate — the backdrop for the flat card slides."""
    plate, _ = load_plate(name)
    b = plate.filter(ImageFilter.GaussianBlur(blur))
    return Image.blend(b, Image.new("RGB", b.size, (8, 8, 10)), darken)


def main():
    OUT.mkdir(exist_ok=True)
    manifest = {}
    for name in ANNOTATIONS:
        plate, meta = load_plate(name)
        stem = pathlib.Path(name).stem.replace(" ", "_")
        plate.save(OUT / f"{stem}.png")
        manifest[name] = {"file": f"{stem}.png", **meta}
        print(f"{name:32s} lid_line={meta['lid_line']} screen={meta['screen']}")

    backdrop = blurred_backdrop("_.jpeg")
    backdrop.save(OUT / "backdrop_dark.png")
    print("backdrop_dark.png")

    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    sys.exit(main())
