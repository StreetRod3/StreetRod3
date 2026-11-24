"""Working gauges for the variety pack's cars. Used by tools/variety_pack_to_glb.py.

The pack's dials are a chrome bezel round a flat face (the `textureford.001` material,
whose gauge image is not in the download) behind a glass cover, with no needles. Each
dial gets a printed face laid just over the model's own and needles of its own:

  * `speedo`: a speedometer, 0-120 mph over 240 degrees, 0 at the lower left (a pod named
    `dash_speedo_arch_240_mph_120_pod`);
  * `combo`: a combination gauge, FUEL across the top (E to F over 90 degrees, its needle
    in a pod named `dash_fuel_arch_90_pod`, which turns it back from F as the tank
    empties) and TEMP across the bottom, whose pointer stays put;
  * `speedo_fuel`: the speedometer with a small gas gauge in the gap at the bottom, its
    own pivot below the middle, F at the lower left and E at the lower right;
  * `fuel`, `temp`, `oil`, `amp`: a small round gauge of its own, its scale across the
    top over 90 degrees and its name below the pivot. The gas gauge works (its needle in
    a pod named `dash_fuel_arch_90_pod`); the others' pointers stay put;
  * `ribbon_speedo`, `ribbon_fuel`: a long flat strip (the 1954 Buick's) with a scale
    along it and a bar of a needle that slides: the speedometer 0-120 mph left to right
    (a pod named `dash_speedo_linear_<travel>_mph_120_pod`, which the game slides along
    its -X, so its X points to the driver's left and its Z down), the gas gauge E to F
    (`dash_fuel_linear_<travel>_pod`, resting at F and sliding back toward E).

The faces are cream with dark printing, as on the cars of the day, and the needles red.
The pods follow the other cars' dashes (tools/studebaker_dash.py): in a pod's frame the
face lies in the X-Z plane facing -Y, +X to the driver's right and +Z up, and the game
turns a needle about the pod's +Y from where it rests, which is clockwise as the driver
sees it.
"""
import math

import numpy as np
from PIL import Image, ImageDraw

from studebaker_dash import CREAM, MATERIALS, _font, _needle, _png, _polar, _text

## How far the printed face stands off the model's, the needles off the face and the hub
## cap off the needles, toward the driver (meters).
FACE_LIFT = 0.0005
NEEDLE_LIFT = 0.0012
HUB_LIFT = 0.0018
## The printed face's radius as a share of the model's face.
FACE_SHARE = 0.99
SEGMENTS = 48
TEX = 512
INK = (34, 30, 26)
RED = (176, 32, 24)
SPEEDO_SWEEP = 240.0
SPEEDO_MAX = 120
FUEL_SWEEP = 90.0
## Where a speedo_fuel face's gas gauge pivots, below the middle, and how long its needle
## is, as shares of the face's radius.
SMALL_FUEL_DOWN = 0.36
SMALL_FUEL_NEEDLE = 0.30
## Where the combination gauge's TEMP pointer rests, clockwise from up (C at 135, H at
## 225: it sits a little past C).
TEMP_AT = 150.0
## The small gauges: the marks at the ends of the scale (left, right; the color of each)
## and where the pointer rests, clockwise from up (the scale runs -45 to 45).
SMALL = {
    'fuel': ('FUEL', (('E', RED), ('F', INK)), FUEL_SWEEP / 2),
    'temp': ('TEMP', (('C', INK), ('H', RED)), -15.0),
    'oil': ('OIL', (('0', INK), ('80', INK)), 5.0),
    'amp': ('AMP', (('-', RED), ('+', INK)), 6.0),
}
NEEDLE_MATERIALS = {
    'needle': MATERIALS['needle'],
    'pointer': {'name': 'dash_ink_pointer_mat', 'doubleSided': True,
                'pbrMetallicRoughness': {'baseColorFactor': [0.06, 0.05, 0.05, 1.0],
                                         'metallicFactor': 0.0, 'roughnessFactor': 0.5}},
    'hub': MATERIALS['bezel'],
}


def dial_frame(tris):
    """Center, axis into the dash (+Z, the way the car faces) and radius of a dial's flat
    face (its triangles, car space)."""
    cross = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    axis = cross.sum(0)
    axis /= np.linalg.norm(axis)
    if axis[2] < 0:
        axis = -axis
    pts = tris.reshape(-1, 3)
    center = (pts.min(0) + pts.max(0)) / 2
    center = center + ((pts - center) @ axis).mean() * axis
    flat = (pts - center) - np.outer((pts - center) @ axis, axis)
    return center, axis, np.linalg.norm(flat, axis=1).max()


## A strip's scale spans this share of its width.
RIBBON_SCALE = 0.88
RIBBON_TEX = 1024
## A strip needle's width (m) and its height as a share of the strip's.
RIBBON_NEEDLE = 0.0025
RIBBON_NEEDLE_SHARE = 0.8


def face_extent(tris, center, basis):
    """Half the width and half the height of a face (car space) in its pod's X and Z."""
    q = (tris.reshape(-1, 3) - center) @ basis
    return float(np.abs(q[:, 0]).max()), float(np.abs(q[:, 2]).max())


def pod_basis(axis):
    """Pod axes in car space (columns X, Y, Z): +Y into the dash, +Z as near up as it can be."""
    y = axis / np.linalg.norm(axis)
    z = np.array([0.0, 1.0, 0.0]) - y[1] * y
    z /= np.linalg.norm(z)
    return np.stack([np.cross(y, z), y, z], 1)


def _ticks(d, c, r, start, sweep, count, major_every, long_len, short_len, width):
    for k in range(count + 1):
        deg = start + sweep * k / count
        major = k % major_every == 0
        d.line([_polar(c, r - (long_len if major else short_len), deg), _polar(c, r, deg)],
               fill=INK, width=width if major else max(1, width // 2))


def face_texture(kind):
    im = Image.new('RGB', (TEX, TEX), CREAM)
    d = ImageDraw.Draw(im)
    c = (TEX / 2, TEX / 2)
    r = TEX / 2 - TEX * 0.06
    d.ellipse([4, 4, TEX - 4, TEX - 4], outline=INK, width=6)
    if kind in ('speedo', 'speedo_fuel'):
        start = -SPEEDO_SWEEP / 2
        _ticks(d, c, r, start, SPEEDO_SWEEP, SPEEDO_MAX // 5, 2, TEX * 0.075, TEX * 0.04, 6)
        for mph in range(0, SPEEDO_MAX + 1, 20):
            _text(d, _polar(c, r - TEX * 0.16, start + SPEEDO_SWEEP * mph / SPEEDO_MAX), str(mph),
                  _font(int(TEX * 0.085)), INK)
        _text(d, (c[0], c[1] - TEX * 0.14), 'MPH', _font(int(TEX * 0.06), True), INK)
        if kind == 'speedo_fuel':
            fc = (c[0], c[1] + SMALL_FUEL_DOWN * TEX / 2)
            fr = SMALL_FUEL_NEEDLE * TEX / 2
            _ticks(d, fc, fr, 135.0, FUEL_SWEEP, 4, 2, TEX * 0.035, TEX * 0.02, 4)
            _text(d, _polar(fc, fr + TEX * 0.035, 225.0), 'F', _font(int(TEX * 0.05)), INK)
            _text(d, _polar(fc, fr + TEX * 0.035, 135.0), 'E', _font(int(TEX * 0.05)), RED)
            _text(d, (fc[0], fc[1] - TEX * 0.05), 'GAS', _font(int(TEX * 0.04), True), INK)
    elif kind == 'combo':
        _ticks(d, c, r, -FUEL_SWEEP / 2, FUEL_SWEEP, 4, 2, TEX * 0.08, TEX * 0.045, 6)
        _text(d, _polar(c, r - TEX * 0.15, -FUEL_SWEEP / 2), 'E', _font(int(TEX * 0.09)), RED)
        _text(d, _polar(c, r - TEX * 0.15, 0.0), '1/2', _font(int(TEX * 0.07)), INK)
        _text(d, _polar(c, r - TEX * 0.15, FUEL_SWEEP / 2), 'F', _font(int(TEX * 0.09)), INK)
        _text(d, (c[0], c[1] - TEX * 0.12), 'FUEL', _font(int(TEX * 0.065), True), INK)
        _ticks(d, c, r, 135.0, 90.0, 4, 2, TEX * 0.08, TEX * 0.045, 6)
        _text(d, _polar(c, r - TEX * 0.15, 135.0), 'C', _font(int(TEX * 0.09)), INK)
        _text(d, _polar(c, r - TEX * 0.15, 225.0), 'H', _font(int(TEX * 0.09)), RED)
        _text(d, (c[0], c[1] + TEX * 0.12), 'TEMP', _font(int(TEX * 0.065), True), INK)
    elif kind in SMALL:
        title, ends, _ = SMALL[kind]
        _ticks(d, c, r, -FUEL_SWEEP / 2, FUEL_SWEEP, 4, 2, TEX * 0.12, TEX * 0.07, 10)
        for (mark, color), deg in zip(ends, (-FUEL_SWEEP / 2 - 22, FUEL_SWEEP / 2 + 22)):
            _text(d, _polar(c, r - TEX * 0.11, deg), mark, _font(int(TEX * 0.14), True), color)
        _text(d, (c[0], c[1] + TEX * 0.2), title, _font(int(TEX * 0.13), True), INK)
    return im


def ribbon_texture(kind, half_w, half_h):
    w = RIBBON_TEX
    h = max(48, round(w * half_h / half_w))
    im = Image.new('RGB', (w, h), CREAM)
    d = ImageDraw.Draw(im)
    d.rectangle([2, 2, w - 3, h - 3], outline=INK, width=4)
    x0, x1 = w * (1 - RIBBON_SCALE) / 2, w * (1 + RIBBON_SCALE) / 2
    if kind == 'ribbon_speedo':
        for mph in range(0, SPEEDO_MAX + 1, 5):
            x = x0 + (x1 - x0) * mph / SPEEDO_MAX
            major = mph % 20 == 0
            d.line([(x, h * 0.08), (x, h * (0.45 if major else 0.3))], fill=INK, width=5 if major else 3)
            if major:
                _text(d, (x, h * 0.66), str(mph), _font(int(h * 0.33), True), INK)
        _text(d, (x0 * 0.5, h * 0.5), 'MPH', _font(int(h * 0.22), True), INK)
    else:
        for k in range(5):
            x = x0 + (x1 - x0) * k / 4
            d.line([(x, h * 0.08), (x, h * (0.5 if k % 2 == 0 else 0.32))], fill=INK, width=6)
        _text(d, (x0 + (x1 - x0) * 0.08, h * 0.75), 'E', _font(int(h * 0.42), True), RED)
        _text(d, (x1 - (x1 - x0) * 0.08, h * 0.75), 'F', _font(int(h * 0.42), True), INK)
        _text(d, ((x0 + x1) / 2, h * 0.75), 'GAS', _font(int(h * 0.3), True), INK)
    return im


def rect(half_w, half_h, lift):
    """A rectangle in the pod's X-Z plane at -lift, facing -Y, with UVs over its image."""
    c = [(-half_w, half_h), (half_w, half_h), (half_w, -half_h), (-half_w, -half_h)]
    q = [np.array([x, -lift, z]) for x, z in c]
    uv = [(0.5 + x / (2 * half_w), 0.5 - z / (2 * half_h)) for x, z in c]
    tris = np.array([[q[0], q[2], q[1]], [q[0], q[3], q[2]]])
    uvs = np.array([[uv[0], uv[2], uv[1]], [uv[0], uv[3], uv[2]]])
    return tris, np.tile([0.0, -1.0, 0.0], (2, 3, 1)), uvs


def bar(x, half_w, half_h, lift):
    """A strip's needle: an upright bar at x."""
    t, n, _ = rect(half_w, half_h, lift)
    return t + np.array([x, 0.0, 0.0]), n


FLIP = np.diag([-1.0, 1.0, -1.0])


def disk(radius, lift, segments=SEGMENTS):
    """A disk in the pod's X-Z plane at -lift, facing -Y, with UVs over a square texture."""
    a = np.linspace(0.0, 2 * math.pi, segments, endpoint=False)
    ring = np.stack([np.sin(a), np.zeros_like(a), np.cos(a)], 1) * radius
    tris, uvs = [], []
    for i in range(segments):
        p = [np.zeros(3), ring[(i + 1) % segments], ring[i]]
        tris.append(p)
        uvs.append([(0.5 + q[0] / (2 * radius), 0.5 - q[2] / (2 * radius)) for q in p])
    tris = np.array(tris) + np.array([0.0, -lift, 0.0])
    nrm = np.tile([0.0, -1.0, 0.0], (len(tris), 3, 1))
    return tris, nrm, np.array(uvs)


def build(dials, kinds, by_size=False):
    """The pods for a car's dials (each a (center, axis, radius, half width, half height)
    in car space), given their kinds from the middle of the car out to the door (or, with
    by_size, from the biggest down). Returns a list of pods, each (node name, origin,
    basis, face kind or None, face size (a radius, or a strip's half width and height),
    [(node name, material key, triangles, normals)]); a pod with a face kind also
    carries the face."""
    order = sorted(dials, key=lambda dial: -dial[2] if by_size else abs(dial[0][0]))
    pods = []
    for kind, (center, axis, radius, half_w, half_h) in zip(kinds, order):
        basis = pod_basis(axis)
        if kind in ('ribbon_speedo', 'ribbon_fuel'):
            hw, hh = half_w * FACE_SHARE, half_h * FACE_SHARE
            span = 2 * hw * RIBBON_SCALE
            needle = bar(0.0, RIBBON_NEEDLE / 2, hh * RIBBON_NEEDLE_SHARE, NEEDLE_LIFT)
            if kind == 'ribbon_speedo':
                # Built with X to the right and Z up, then turned about Y so the game's
                # slide along -X runs left to right.
                t, n = needle[0] + np.array([-span / 2, 0.0, 0.0]), needle[1]
                pods.append((f'dash_speedo_linear_{span:.4f}_mph_{SPEEDO_MAX}_pod', center, basis @ FLIP, kind,
                             (hw, hh), [('speedo_needle', 'needle', t @ FLIP, n @ FLIP)]))
            else:
                t, n = needle[0] + np.array([span / 2, 0.0, 0.0]), needle[1]
                pods.append((f'dash_fuel_linear_{span:.4f}_pod', center, basis, kind, (hw, hh),
                             [('fuel_needle', 'needle', t, n)]))
            continue
        r = radius * FACE_SHARE
        hub = [('hub', *disk(r * 0.07, HUB_LIFT, 16)[:2])]
        if kind in ('speedo', 'speedo_fuel'):
            needle = _needle(r * 0.86, r * 0.16, r * 0.035, -SPEEDO_SWEEP / 2, -NEEDLE_LIFT)
            pods.append((f'dash_speedo_arch_{SPEEDO_SWEEP:.0f}_mph_{SPEEDO_MAX}_pod', center, basis, kind, r,
                         [('speedo_needle', 'needle', *needle), ('speedo_hub', *hub[0])]))
            if kind == 'speedo_fuel':
                at = center + basis @ np.array([0.0, 0.0, -SMALL_FUEL_DOWN * r])
                needle = _needle(r * SMALL_FUEL_NEEDLE, r * 0.05, r * 0.025, 225.0, -NEEDLE_LIFT)
                small_hub = disk(r * 0.04, HUB_LIFT, 12)[:2]
                pods.append((f'dash_fuel_arch_{FUEL_SWEEP:.0f}_pod', at, basis, None, r,
                             [('fuel_needle', 'needle', *needle), ('fuel_hub', 'hub', *small_hub)]))
        elif kind == 'combo':
            fuel = _needle(r * 0.8, r * 0.12, r * 0.035, FUEL_SWEEP / 2, -NEEDLE_LIFT)
            temp = _needle(r * 0.8, r * 0.12, r * 0.035, TEMP_AT, -NEEDLE_LIFT * 0.8)
            pods.append(('dash_combo_pod', center, basis, kind, r,
                         [('temp_needle', 'pointer', *temp), ('combo_hub', *hub[0])]))
            pods.append((f'dash_fuel_arch_{FUEL_SWEEP:.0f}_pod', center, basis, None, r,
                         [('fuel_needle', 'needle', *fuel)]))
        elif kind in SMALL:
            needle = _needle(r * 0.82, r * 0.15, r * 0.06, SMALL[kind][2], -NEEDLE_LIFT)
            small_hub = ('hub', *disk(r * 0.12, HUB_LIFT, 12)[:2])
            if kind == 'fuel':
                pods.append((f'dash_fuel_arch_{FUEL_SWEEP:.0f}_pod', center, basis, kind, r,
                             [('fuel_needle', 'needle', *needle), ('fuel_hub', *small_hub)]))
            else:
                pods.append((f'dash_{kind}_pod', center, basis, kind, r,
                             [(f'{kind}_needle', 'pointer', *needle), (f'{kind}_hub', *small_hub)]))
        else:
            raise ValueError(f'no such dial kind: {kind}')
    return pods


def face_material(kind, image_index):
    return {'name': f'dash_pack_{kind}_mat', 'doubleSided': True,
            'emissiveFactor': [0.5, 0.5, 0.5], 'emissiveTexture': {'index': image_index},
            'pbrMetallicRoughness': {'baseColorTexture': {'index': image_index},
                                     'metallicFactor': 0.0, 'roughnessFactor': 0.5}}


def face_png(kind, size):
    if kind.startswith('ribbon_'):
        return _png(ribbon_texture(kind, *size))
    return _png(face_texture(kind))


def face_mesh(kind, size):
    """The face's triangles, normals and UVs in its pod's frame."""
    if kind.startswith('ribbon_'):
        t, n, u = rect(*size, FACE_LIFT)
        return (t @ FLIP, n @ FLIP, u) if kind == 'ribbon_speedo' else (t, n, u)
    return disk(size, FACE_LIFT)
