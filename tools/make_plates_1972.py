#!/usr/bin/env python3
"""Draw the 1972 California license plate the game prints every car's plate on.

    python3 -I tools/make_plates_1972.py

Writes three images into assets/cars/plates/, each the plate's face long side across, 512
x 256 px (12 x 6 in), drawn to fill the UVs of the cars' `plate` material
(tools/make_blank_plate.py):

  ca-1972-front.png  the front plate with no number: blue, a raised rim, CALIFORNIA in raised
                     yellow, the two sticker wells, and the four bolt holes. Outside the
                     rounded corners it is transparent.
  ca-1972-rear.png   the same with the 1973 year sticker in the well right of CALIFORNIA: red
                     with black characters, as the DMV's table of sticker colors has it
                     (VR manual appendix 1E; 1972's was yellow). The left well stays empty,
                     since month stickers came in 1976.
  ca-1972-glyphs.png the raised yellow characters the game lays over a plate for its number,
                     one cell each, GLYPHS in order along a single row.

The game (scripts/license_plate.gd) copies glyph cells onto a plate in its own code, so
the cell size, the pitch and where the number sits are shared numbers: change them in both.

The plate is laid out from a photo of a pair of 1970-era plates (blue with yellow, 167 FHE,
a 1972 sticker). The characters are Routed Gothic (OFL, reference/buildings/PAD_GasPumps/
font/, as on the gas pumps), squeezed to the plate's tall narrow dies and given an even
stroke. Everything raised is drawn as a height map and lit from the upper left, so the rim,
the lettering and the number stand off the plate.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
FONT = os.path.join(ROOT, 'reference', 'buildings', 'PAD_GasPumps', 'font', 'routed-gothic.ttf')
OUT = os.path.join(ROOT, 'assets', 'cars', 'plates')

W, H = 512, 256
## Drawn this many times larger, then shrunk.
SS = 4
BLUE = np.array([30, 72, 160], np.float64)
YELLOW = np.array([246, 196, 44], np.float64)
STICKER_RED = np.array([196, 38, 36], np.float64)
INK = np.array([18, 16, 16], np.float64)

## The number's characters, one cell each in this order (scripts/license_plate.gd GLYPHS).
GLYPHS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
## A number character's die: its face width and height and the stroke, px on the plate.
GLYPH_W, GLYPH_H, GLYPH_STROKE = 56, 120, 13
## Each cell is the die with this much room round it for the shading and the shadow.
CELL_PAD = 6
CELL_W, CELL_H = GLYPH_W + 2 * CELL_PAD, GLYPH_H + 2 * CELL_PAD

CORNER_R = 16
RIM_INSET, RIM_WIDTH = 7, 4
CALIFORNIA_BOX = (147, 36, 373, 71)
CALIFORNIA_STROKE = 6
WELLS = [(20, 41, 114, 90), (398, 41, 492, 90)]
STICKER = (403, 45, 487, 86)
HOLES = [(110, 19), (402, 19), (106, 237), (406, 237)]
HOLE_R = 5
## Light from the upper left and in front.
LIGHT = np.array([-0.45, -0.55, 0.7])
LIGHT /= np.linalg.norm(LIGHT)


def _font(px):
    return ImageFont.truetype(FONT, px)


def _char_mask(ch, w, h, stroke):
    """A character's coverage at SS scale, w x h px on the plate, with an even stroke."""
    if ch in STROKED:
        return _stroked_mask(STROKED[ch], w, h, stroke)
    font = _font(400)
    box = font.getbbox(ch)
    pad = 40
    img = Image.new('L', (box[2] - box[0] + 2 * pad, box[3] - box[1] + 2 * pad), 0)
    ImageDraw.Draw(img).text((pad - box[0], pad - box[1]), ch, font=font, fill=255)
    img = img.crop(img.getbbox())
    r = stroke * SS / 2
    inner_w, inner_h = max(1, int(round(w * SS - 2 * r))), int(round(h * SS - 2 * r))
    if ch == 'J':
        # The narrow ones keep their own width at the die's height.
        inner_w = max(1, min(inner_w, int(round(img.width * inner_h / img.height * 0.8))))
    # The font's own stroke is thin and differs once squeezed: thin it to a center line and
    # grow it back out evenly. The center line lies in from the outline by half the font's
    # stroke, so it is drawn that much bigger to fill the die.
    ridge = _thin(np.asarray(img.resize((inner_w, inner_h), Image.LANCZOS)) > 100)
    ys, xs = np.nonzero(ridge)
    span_w, span_h = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
    grow_w = inner_w * inner_w / span_w if span_w > inner_w / 2 else inner_w
    grow_h = inner_h * inner_h / span_h if span_h > inner_h / 2 else inner_h
    ridge = _thin(np.asarray(img.resize((int(round(grow_w)), int(round(grow_h))), Image.LANCZOS)) > 100)
    ys, xs = np.nonzero(ridge)
    ridge = ridge[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    rh, rw = ridge.shape
    canvas = np.zeros((int(round(h * SS)), int(round(w * SS))), bool)
    ox = (canvas.shape[1] - rw) // 2
    oy = (canvas.shape[0] - rh) // 2
    canvas[oy:oy + rh, ox:ox + rw] = ridge
    return ndimage.distance_transform_edt(~canvas) <= r


## Characters drawn from strokes instead of the font, as lines through points in the die
## (0-1 across, 0-1 down), and the stroke's share: the plate's 1 is a plain upright with a
## flag and no foot, I a plain upright, and M and W keep their middle strokes apart in a narrow die.
STROKED = {
    '1': ([[(0.6, 0.0), (0.6, 1.0)], [(0.6, 0.0), (0.18, 0.2)]], 1.0),
    'I': ([[(0.5, 0.0), (0.5, 1.0)]], 1.0),
    'M': ([[(0.0, 1.0), (0.0, 0.0), (0.5, 0.62), (1.0, 0.0), (1.0, 1.0)]], 0.85),
    'W': ([[(0.0, 0.0), (0.2, 1.0), (0.5, 0.38), (0.8, 1.0), (1.0, 0.0)]], 0.85),
}


def _stroked_mask(spec, w, h, stroke):
    lines, share = spec
    r = stroke * share * SS / 2
    img = Image.new('L', (int(round(w * SS)), int(round(h * SS))), 0)
    draw = ImageDraw.Draw(img)
    sx, sy = img.width - 2 * r, img.height - 2 * r
    for line in lines:
        draw.line([(r + x * sx, r + y * sy) for x, y in line], fill=255, width=1)
    return ndimage.distance_transform_edt(np.asarray(img) == 0) <= r


def _thin(mask):
    """Zhang-Suen thinning: the shape worn down to a line one pixel wide."""
    m = np.pad(mask, 1).astype(np.uint8)
    while True:
        changed = False
        for step in (0, 1):
            p2, p3, p4 = m[:-2, 1:-1], m[:-2, 2:], m[1:-1, 2:]
            p5, p6, p7 = m[2:, 2:], m[2:, 1:-1], m[2:, :-2]
            p8, p9 = m[1:-1, :-2], m[:-2, :-2]
            ring = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
            neighbors = sum(ring[:8])
            turns = sum(((ring[i] == 0) & (ring[i + 1] == 1)).astype(np.uint8) for i in range(8))
            if step == 0:
                edge = (p2 * p4 * p6 == 0) & (p4 * p6 * p8 == 0)
            else:
                edge = (p2 * p4 * p8 == 0) & (p2 * p6 * p8 == 0)
            drop = (m[1:-1, 1:-1] == 1) & (neighbors >= 2) & (neighbors <= 6) & (turns == 1) & edge
            if drop.any():
                m[1:-1, 1:-1][drop] = 0
                changed = True
        if not changed:
            return m[1:-1, 1:-1].astype(bool)


def _text_mask(text, box, stroke, spacing):
    """Coverage of `text` filling `box` (plate px) at SS scale, letters spaced evenly."""
    x0, y0, x1, y1 = box
    n = len(text)
    gap = spacing
    cw = ((x1 - x0) - gap * (n - 1)) / n
    out = np.zeros((H * SS, W * SS), bool)
    for i, ch in enumerate(text):
        m = _char_mask(ch, cw, y1 - y0, stroke)
        cx = int(round((x0 + i * (cw + gap)) * SS))
        cy = int(round(y0 * SS))
        out[cy:cy + m.shape[0], cx:cx + m.shape[1]] |= m
    return out


def _rounded_rect(box, r):
    img = Image.new('L', (W * SS, H * SS), 0)
    x0, y0, x1, y1 = (v * SS for v in box)
    ImageDraw.Draw(img).rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=r * SS, fill=255)
    return np.asarray(img) > 127


def _height(mask, soft):
    """A raised shape's height: 1 on its face, falling off over `soft` px at its edges."""
    return ndimage.gaussian_filter(mask.astype(np.float64), soft * SS)


def _light(height, depth):
    """How lit each point is, 1 on the flat, from the height map's slope."""
    gy, gx = np.gradient(height * depth * SS)
    n = np.dstack([-gx, -gy, np.ones_like(gx)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    flat = LIGHT[2]
    return np.clip(0.55 + 0.45 * (n @ LIGHT) / flat, 0.25, 1.6)


def _shrink(rgba):
    """SS-scale straight RGBA (floats 0-255) to plate size, averaging premultiplied."""
    a = rgba[..., 3:4] / 255.0
    pre = np.concatenate([rgba[..., :3] * a, a], axis=2)
    h, w = pre.shape[0] // SS, pre.shape[1] // SS
    pre = pre.reshape(h, SS, w, SS, 4).mean(axis=(1, 3))
    alpha = pre[..., 3:4]
    rgb = np.where(alpha > 1e-4, pre[..., :3] / np.maximum(alpha, 1e-4), 0.0)
    out = np.concatenate([rgb, alpha * 255.0], axis=2)
    return Image.fromarray(np.clip(np.round(out), 0, 255).astype(np.uint8), 'RGBA')


def plate(sticker):
    """The plate with no number, as a PIL RGBA image; with `sticker` the 1973 sticker on."""
    outline = _rounded_rect((0, 0, W, H), CORNER_R)
    rim_outer = _rounded_rect((RIM_INSET, RIM_INSET, W - RIM_INSET, H - RIM_INSET), CORNER_R - RIM_INSET)
    rim_inner = _rounded_rect((RIM_INSET + RIM_WIDTH, RIM_INSET + RIM_WIDTH, W - RIM_INSET - RIM_WIDTH,
                               H - RIM_INSET - RIM_WIDTH), CORNER_R - RIM_INSET - RIM_WIDTH)
    rim = rim_outer & ~rim_inner
    # The plate's edge rolls back away from the face.
    edge = ndimage.distance_transform_edt(outline) / SS
    height = _height(rim, 1.2) * 1.0 - np.clip(1.0 - edge / 4.0, 0.0, 1.0) * 0.8
    wells = np.zeros_like(rim)
    for box in WELLS:
        outer = _rounded_rect(box, 4)
        inner = _rounded_rect((box[0] + 2, box[1] + 2, box[2] - 2, box[3] - 2), 3)
        wells |= outer & ~inner
    height += _height(wells, 0.8) * 0.5
    letters = _text_mask('CALIFORNIA', CALIFORNIA_BOX, CALIFORNIA_STROKE, 5)
    letters_h = _height(letters, 1.0)
    height += letters_h * 0.8
    lit = _light(height, 2.2)

    rng = np.random.default_rng(1972)
    grain = ndimage.gaussian_filter(rng.normal(0.0, 1.0, height.shape), SS * 0.6) * 6.0
    face = np.clip(letters_h * 1.6 - 0.3, 0.0, 1.0)[..., None]
    rgb = (BLUE * (1 - face) + YELLOW * face) * lit[..., None] + grain[..., None]
    if sticker:
        rgb = _sticker(rgb)
    holes = np.zeros_like(rim)
    yy, xx = np.mgrid[0:H * SS, 0:W * SS]
    for hx, hy in HOLES:
        holes |= (xx - hx * SS) ** 2 + (yy - hy * SS) ** 2 <= (HOLE_R * SS) ** 2
    # A bolt hole shows the dark behind the plate, its far edge lit where the steel turns in.
    rgb[holes] = INK + 10
    alpha = outline.astype(np.float64) * 255.0
    return _shrink(np.dstack([np.clip(rgb, 0, 255), alpha]))


def _sticker(rgb):
    """Lays the 1973 year sticker into the right well: flat, red, with black printing."""
    x0, y0, x1, y1 = STICKER
    w, h = (x1 - x0) * SS, (y1 - y0) * SS
    img = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=2 * SS, outline=255, width=int(1.2 * SS))
    small = _font(int(8.5 * SS))
    draw.text((w / 2, 2.0 * SS), 'CALIFORNIA', font=small, fill=255, anchor='mt')
    big = _font(int(17 * SS))
    mid = h * 0.56
    draw.text((w * 0.27, mid), '19', font=big, fill=255, anchor='mm')
    draw.text((w * 0.73, mid), '73', font=big, fill=255, anchor='mm')
    # A made-up seal between the halves of the year, not the state's.
    r = 6.0 * SS
    draw.ellipse((w / 2 - r, mid - r, w / 2 + r, mid + r), outline=255, width=int(1.1 * SS))
    draw.ellipse((w / 2 - r * 0.45, mid - r * 0.45, w / 2 + r * 0.45, mid + r * 0.45), fill=255)
    draw.text((w / 2, h - 2.0 * SS), '6058213', font=_font(int(6 * SS)), fill=255, anchor='mb')
    ink = (np.asarray(img) / 255.0)[..., None]
    paper = STICKER_RED * 1.02
    region = paper * (1 - ink) + INK * ink
    # A little gloss toward the top.
    region *= np.linspace(1.08, 0.94, h)[:, None, None]
    sy, sx = y0 * SS, x0 * SS
    rgb[sy:sy + h, sx:sx + w] = region
    return rgb


def glyphs():
    """The number's raised characters, a cell each along one row, as a PIL RGBA image."""
    cells = []
    for ch in GLYPHS:
        m = np.zeros((CELL_H * SS, CELL_W * SS), bool)
        face = _char_mask(ch, GLYPH_W, GLYPH_H, GLYPH_STROKE)
        p = CELL_PAD * SS
        m[p:p + face.shape[0], p:p + face.shape[1]] = face
        height = _height(m, 1.4)
        lit = _light(height, 3.0)
        top = np.clip(height * 1.8 - 0.4, 0.0, 1.0)[..., None]
        rgb = (BLUE * (1 - top) + YELLOW * top) * lit[..., None]
        # Where the die pushed the steel up: the raised part and its sides.
        raised = np.clip(height * 6.0, 0.0, 1.0)
        # A soft shadow down and right of it, on the flat.
        shadow = ndimage.shift(ndimage.gaussian_filter(m.astype(np.float64), 1.6 * SS), (1.5 * SS, 1.2 * SS), order=1)
        shadow_a = np.clip(shadow * 0.45, 0.0, 1.0) * (1 - raised)
        alpha = raised + shadow_a
        color = np.where(alpha[..., None] > 1e-6,
                         (rgb * raised[..., None] + BLUE * 0.35 * shadow_a[..., None]) / np.maximum(alpha, 1e-6)[..., None],
                         0.0)
        cells.append(np.dstack([np.clip(color, 0, 255), np.clip(alpha, 0, 1) * 255.0]))
    return _shrink(np.concatenate(cells, axis=1))


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, image in (('ca-1972-front.png', plate(False)), ('ca-1972-rear.png', plate(True)),
                        ('ca-1972-glyphs.png', glyphs())):
        path = os.path.join(OUT, name)
        image.save(path, optimize=True)
        print('wrote', os.path.normpath(path))
    sys.exit(0)
