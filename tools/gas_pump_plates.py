#!/usr/bin/env python3
"""Repaints the side plate of the gas pump's texture, once for each pump.

    python3 -I tools/gas_pump_plates.py reference/buildings/PAD_GasPumps OUT_DIR

The pack's plate reads an arrow, "REGULAR" and "LET US KNOW ANYTING NEEDED". This
writes two sets of body maps into OUT_DIR, for tools/gas_pump_to_glb.py and the game:

  pump-regular-color.png, pump-regular-normal.png: the plate reads "REGULAR";
  pump-super-color.png,   pump-super-normal.png:   the plate reads "SUPER".

Both lines of lettering are erased and the word redrawn, so the two pumps match.

Color maps are 2048, normal maps 1024 in glTF's (OpenGL) convention; the pack's
Unreal maps are DirectX style, so green is flipped here.

The lettering is in the color map and stamped into the normal map. The atlas has the
plate twice (on the side panel, and sideways on the plate itself); both are repainted.
Erasing fills the letters from the plate around them. The word is drawn in Routed
Gothic (OFL, the reference folder's font/), a K&E Leroy engraving-template face, at the
original word's capital height and color, halfway between the arrow and the plate's
bottom edge, and stamped into the normal map with a relief fitted to the original
letters. A font path as a third argument overrides the font.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

COLOR_SIZE = 2048
NORMAL_SIZE = 1024
SS = 8  # supersampling for drawn letters
FONT = 'routed-gothic.ttf'  # in the reference folder's font/; a path as a third argument overrides it

# Each copy of the plate: its box in the 4096 atlas, the quarter turns (counterclockwise,
# as np.rot90) that stand it upright, and the plate's own edges in the upright crop.
PLATES = [
    ((3363, 2297, 3648, 2490), 0, (0, 0, 285, 193)),
    ((2380, 420, 2760, 880), 1, (100, 157, 386, 358)),
]


def runs(flags, gap):
    """(start, end) of runs of True, bridging gaps up to `gap` long."""
    out = []
    for i in np.where(flags)[0]:
        if out and i - out[-1][1] <= gap:
            out[-1][1] = i + 1
        else:
            out.append([i, i + 1])
    return out


def bands(mask):
    """Lines of lettering: (y0, y1, x0, x1), wide ones only, specks of grime left out."""
    out = []
    for y0, y1 in runs(mask.sum(1) > 1, 1):
        cols = mask[y0:y1].sum(0)
        groups = [(a, b) for a, b in runs(cols > 0, 10) if cols[a:b].sum() >= 25]
        if not groups or y1 - y0 < 4:
            continue
        x0, x1 = groups[0][0], groups[-1][1]
        if x1 - x0 <= 40:
            continue
        rows = np.where(mask[y0:y1, x0:x1].sum(1) > 1)[0]
        out.append((y0 + int(rows[0]), y0 + int(rows[-1]) + 1, int(x0), int(x1)))
    return out


def fill(img, hole, valid, sigma):
    """Fill hole pixels from valid ones nearby (normalized convolution)."""
    w = valid.astype(np.float64)
    out = img.copy()
    for c in range(img.shape[2]):
        num = ndimage.gaussian_filter(img[..., c] * w, sigma)
        den = ndimage.gaussian_filter(w, sigma)
        out[..., c] = np.where(hole, num / np.maximum(den, 1e-6), img[..., c])
    return out


def relief(cov, sigma):
    h = ndimage.gaussian_filter(cov, sigma)
    gy, gx = np.gradient(h)
    return gx, gy


def fit_relief(cov, normal, region):
    """Least-squares relief that best explains the stamped letters: the blur, and the 2x2
    map from the letters' slope to the normal's red and green (any quarter turn of the
    plate in the atlas comes out of the fit)."""
    dev = normal[..., :2] * 2.0 - 1.0
    best = None
    for sigma in (0.6, 0.9, 1.3, 1.8, 2.5):
        gx, gy = relief(cov, sigma)
        a = np.stack([gx[region], gy[region]], axis=1)
        m, res, _rank, _sv = np.linalg.lstsq(a, dev[region], rcond=None)
        err = ((dev[region] - a @ m) ** 2).sum()
        if best is None or err < best[0]:
            best = (err, sigma, m)
    return best[1:]


def stamp(normal, cov, sigma, m):
    gx, gy = relief(cov, sigma)
    dev = normal * 2.0 - 1.0
    dev[..., :2] += np.stack([gx, gy], axis=-1) @ m
    dev /= np.linalg.norm(dev, axis=2, keepdims=True)
    return (dev + 1.0) * 0.5


def draw_word(font_path, word, cap_px, shape, x_center, y_top):
    """Coverage of `word` with capitals cap_px tall, in the font's own proportions."""
    font = ImageFont.truetype(font_path, 100 * SS)
    ref_cap = font.getbbox('E')
    cap = ref_cap[3] - ref_cap[1]
    scale = cap_px * SS / cap
    box = font.getbbox(word)
    pad = 2 * SS
    big = Image.new('L', (box[2] - box[0] + 2 * pad, cap + 2 * pad), 0)
    ImageDraw.Draw(big).text((pad - box[0], pad - ref_cap[1]), word, font=font, fill=255)
    w = max(1, round(big.width * scale / SS))
    h = max(1, round(big.height * scale / SS))
    small = np.asarray(big.resize((w, h), Image.LANCZOS), dtype=np.float64) / 255.0
    cov = np.zeros(shape)
    x0 = int(round(x_center - w / 2))
    y0 = int(round(y_top - pad * scale / SS))
    cov[y0:y0 + h, x0:x0 + w] = small[:shape[0] - y0, :shape[1] - x0]
    return cov


def repaint(color, normal, font_path, word):
    """Repaint every plate copy in place with `word` in place of the original lettering."""
    for box, turns, plate_box in PLATES:
        x0, y0, x1, y1 = box
        c = np.rot90(color[y0:y1, x0:x1], turns)
        n = np.rot90(normal[y0:y1, x0:x1], turns)
        lum = c @ np.array([0.299, 0.587, 0.114])
        plate = np.zeros(lum.shape, bool)
        px0, py0, px1, py1 = plate_box
        plate[py0:py1, px0:px1] = True
        ground = np.median(lum[plate])
        ink = plate & (lum < ground - 0.11)
        found = bands(ink)
        if len(found) < 3:
            raise SystemExit('plate at %s: found %d lines of lettering, want 3' % (box, len(found)))
        arrow_band, word_band, line_band = found[:3]
        arrow_rows = ink[arrow_band[0]:arrow_band[1], arrow_band[2]:arrow_band[3]].sum(1)
        arrow_bottom = arrow_band[0] + np.where(arrow_rows >= arrow_rows.max() * 0.5)[0][-1] + 1
        line_ink = np.zeros_like(ink)
        line_ink[line_band[0]:line_band[1], line_band[2]:line_band[3]] = \
            ink[line_band[0]:line_band[1], line_band[2]:line_band[3]]
        word_ink = np.zeros_like(ink)
        word_ink[word_band[0]:word_band[1], word_band[2]:word_band[3]] = \
            ink[word_band[0]:word_band[1], word_band[2]:word_band[3]]
        erase = line_ink | word_ink
        hole_c = ndimage.binary_dilation(erase, iterations=2)
        hole_n = ndimage.binary_dilation(erase, iterations=4)
        keep = plate & ~ndimage.binary_dilation(ink, iterations=4)
        c2 = fill(c, hole_c, keep, 4.0)
        n2 = fill(n, hole_n, keep, 4.0)
        word_cov = ndimage.gaussian_filter(word_ink.astype(np.float64), 0.5)
        fit_region = ndimage.binary_dilation(word_ink, iterations=5)
        sigma, m = fit_relief(word_cov, n, fit_region)
        core = ndimage.binary_erosion(word_ink)
        ink_rgb = np.median(c[core if core.any() else word_ink], axis=0)
        wy0, wy1, wx0, wx1 = word_band
        # The new word sits halfway between the arrow and the plate's bottom edge,
        # where the erased line no longer leaves a gap under it.
        top = (arrow_bottom + py1) / 2 - (wy1 - wy0) / 2
        cov = draw_word(font_path, word, wy1 - wy0, lum.shape, (wx0 + wx1) / 2, top)
        c2 = c2 * (1 - cov[..., None]) + ink_rgb * cov[..., None]
        n2 = stamp(n2, cov, sigma, m)
        print('  plate %s: "%s" at row %d (was %d), relief sigma %.1f %s'
              % (box, word, top, wy0, sigma, np.round(m, 2).tolist()))
        color[y0:y1, x0:x1] = np.rot90(c2, -turns)
        normal[y0:y1, x0:x1] = np.rot90(n2, -turns)


def save(arr, path, size, flip_green=False):
    a = arr.copy()
    if flip_green:
        a[..., 1] = 1.0 - a[..., 1]
    img = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)
    print('wrote', path)


def main():
    ref, out = sys.argv[1], sys.argv[2]
    font = sys.argv[3] if len(sys.argv) > 3 else os.path.join(ref, 'font', FONT)
    unreal = os.path.join(ref, 'TexturesFromUnreal')
    base_c = np.asarray(Image.open(os.path.join(unreal, 'T_PAD_GasPump_4096_B.png')).convert('RGB'),
                        dtype=np.float64) / 255.0
    base_n = np.asarray(Image.open(os.path.join(unreal, 'T_PAD_GasPump_4096_N.png')).convert('RGB'),
                        dtype=np.float64) / 255.0
    os.makedirs(out, exist_ok=True)
    for name, word in (('regular', 'REGULAR'), ('super', 'SUPER')):
        c, n = base_c.copy(), base_n.copy()
        repaint(c, n, font, word)
        save(c, os.path.join(out, 'pump-%s-color.png' % name), COLOR_SIZE)
        save(n, os.path.join(out, 'pump-%s-normal.png' % name), NORMAL_SIZE, flip_green=True)


main()
