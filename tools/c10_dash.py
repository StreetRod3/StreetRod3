"""The 1963 Chevrolet C10's instrument cluster, glovebox brow and steering wheel. Used by
tools/c10_to_glb.py.

Reference: reference/cars/c10-1963/1961-chevrolet-apache-interior.jpg (the 1960-63
trucks share the cab). The dash has two raised brows, one over the instrument cluster in
front of the driver and one over the glovebox. The cluster is a wide window with rounded
ends and a black face with white markings, the numbers outside the ticks; from the driver's left: TEMPERATURE (C to H), the
GENERATOR light, a half-round speedometer from 0 to 100 mph over 240 degrees with 50 at
the top and a ribbed fan behind its needle, the OIL light, and GASOLINE (E to F). The
steering wheel is a thin black two-spoke wheel with brushed spokes dished down to a
chrome hub and horn button.

The model's own dash is a plain strip, too low for a cluster above the steering column,
so the cluster sits in a hooded binnacle on top of it, where it is seen through the top
half of the wheel, as in the photo.

The pods follow the other cars' dashes (tools/studebaker_dash.py): in a pod's frame the
face lies in the X-Z plane facing -Y, +X to the driver's right and +Z up; the game turns
a needle about the pod's +Y from where it rests, which is clockwise as the driver sees
it. The speedometer pod is named `dash_speedo_arch_240_mph_100_pod`: its needle sweeps
240 degrees for 0-100 mph. The gas gauge's pointer is in a pod of its own,
`dash_fuel_arch_90_pod`, which turns it back from F toward E with the fuel used.

The steering wheel is built in its own frame: +Z down the column into the dash, +X
across to the driver's left, +Y up the wheel; the game turns it about +Z.
"""
import math

import numpy as np
from PIL import Image, ImageDraw

from studebaker_dash import (MATERIALS, _cap, _circle, _font, _join, _needle, _png, _polar, _ring,
                             _rounded_prism, _rounded_rect, _text, _wall)

## The cluster's face (meters): its width and height, how far its bottom is below the
## speedometer's pivot (the pod's origin), and its round ends.
FACE_W = 0.48
FACE_H = 0.10
PIVOT_UP = 0.04
FACE_R = 0.045
## The chrome frame round the face, and the hood round that: how far the hood stands out
## toward the driver, how far it reaches down past the frame and up over it (the brow),
## and how deep it goes back into the dash.
FRAME = 0.007
HOOD_OUT = 0.035
HOOD_SIDE = 0.016
HOOD_DOWN = 0.012
HOOD_UP = 0.025
HOOD_BACK = 0.11
HOOD_EDGE = 0.012
SEGMENTS = 8

## The dials, in the pod's frame: the speedometer at the origin, the small ones on a row
## through the middle of the face, from the driver's left.
SPEEDO_SWEEP = 240.0
SPEEDO_MAX = 100
SMALL_R = 0.026
SMALL_Z = FACE_H / 2 - PIVOT_UP
SMALL = [('temp', -0.19), ('generator', -0.125), ('oil', 0.125), ('gas', 0.19)]
## Each small gauge's needle: sweep, where it rests (degrees clockwise from up), length.
GAS_SWEEP = 90.0
TEMP_AT = -12.0
SMALL_NEEDLE = 0.0150

TEX_W = 2048
FACE = (16, 16, 18)
INK = (232, 230, 222)
FAN = (62, 63, 68)
LAMP = (96, 26, 22)
## Radii on the dials (meters): the speedometer's ticks (inner, outer) and its numbers
## outside them; the small gauges' ticks and their letters outside them.
SPEEDO_TICKS = (0.029, 0.037)
SPEEDO_NUMBERS = 0.0455
SPEEDO_NEEDLE = 0.036
SMALL_TICKS = (0.0115, 0.0160)
SMALL_LETTERS = 0.0205

## The steering wheel (meters): 18 in across, its rim's thickness, and the hub dished
## toward the column.
WHEEL_R = 9.0 * 0.0254
RIM_R = 0.011
HUB_DISH = 0.06
HUB_R = 0.046
HUB_BACK_R = 0.032
HUB_BACK = 0.11
SPOKE_W = (0.044, 0.024)
SPOKE_T = 0.008
## Swatches in the steering wheel's little texture (it has one, with alpha 0, so the
## game never paints the wheel): (color, roughness, metallic).
WHEEL_SWATCHES = {
    'rim': ((18, 18, 20), 0.45, 0.0),
    'spoke': ((176, 178, 182), 0.32, 0.85),
    'chrome': ((222, 224, 228), 0.12, 1.0),
    'emblem': ((190, 28, 30), 0.3, 0.2),
}

DASH_MATERIALS = {
    'hood': {'name': 'dash_c10_hood_mat', 'doubleSided': True,
             'pbrMetallicRoughness': {'baseColorFactor': [0.03, 0.03, 0.034, 1.0],
                                      'metallicFactor': 0.15, 'roughnessFactor': 0.55}},
    'bezel': MATERIALS['bezel'],
    'needle': MATERIALS['needle'],
    'cap': MATERIALS['cap'],
}


def face_outline(grow=0.0):
    """The face's outline in the pod's X-Z plane, grown by `grow`."""
    return _rounded_rect(FACE_W + 2 * grow, FACE_H + 2 * grow, FACE_R + grow, SEGMENTS, -PIVOT_UP - grow)


def hood_outline():
    w = FACE_W + 2 * (FRAME + HOOD_SIDE)
    z0 = -PIVOT_UP - FRAME - HOOD_DOWN
    h = FACE_H + 2 * FRAME + HOOD_DOWN + HOOD_UP
    return _rounded_rect(w, h, FACE_R + FRAME + HOOD_SIDE, SEGMENTS, z0)


def hood(closed=False):
    """The binnacle: a box rounded over at the front, round the frame (or, `closed`, with
    a flat front, for the glovebox's brow), and the tunnel from its front back to the frame."""
    outer = hood_outline()
    frame = face_outline(FRAME)
    if closed:
        return _rounded_prism(outer, -HOOD_OUT, HOOD_BACK, HOOD_EDGE)
    return _join(_rounded_prism(outer, -HOOD_OUT, HOOD_BACK, HOOD_EDGE, inner=frame),
                 _wall(frame, -HOOD_OUT, -0.006, outward=False))


def bezel():
    """The chrome frame round the face, rounded over at the front."""
    return _rounded_prism(face_outline(FRAME), -0.006, 0.002, 0.003, inner=face_outline())


def face_mesh():
    """The face at y = -0.0005, facing -Y, with UVs over the texture."""
    tris, nrm = _cap(face_outline(), -0.0005, -1.0)
    u = (tris[..., 0] + FACE_W / 2) / FACE_W
    v = (FACE_H - PIVOT_UP - tris[..., 2]) / FACE_H
    return tris, nrm, np.stack([u, v], -1)


def _px(x, z):
    """Texture pixel of a point on the face (pod frame, meters)."""
    s = TEX_W / FACE_W
    return (x + FACE_W / 2) * s, (FACE_H - PIVOT_UP - z) * s


def face_texture():
    s = TEX_W / FACE_W
    h = round(FACE_H * s)
    rng = np.random.default_rng(1963)
    # Black, faintly brushed across.
    streaks = rng.normal(0.0, 1.5, (h, 1)) + rng.normal(0.0, 1.0, (h, TEX_W))
    base = np.clip(np.array(FACE, float)[None, None, :] + streaks[..., None], 0, 255).astype(np.uint8)
    im = Image.fromarray(base, 'RGB')
    d = ImageDraw.Draw(im)
    px = lambda m: m * s
    # The speedometer: a ribbed fan behind the needle, ticks every 5 mph round it, and the
    # numbers every 10 outside the ticks.
    c = _px(0.0, 0.0)
    half = SPEEDO_SWEEP / 2
    for k in range(0, 49):
        deg = -half + SPEEDO_SWEEP * k / 48
        d.line([_polar(c, px(0.009), deg), _polar(c, px(0.025), deg)], fill=FAN, width=3)
    for mph in range(0, SPEEDO_MAX + 1, 5):
        deg = -half + SPEEDO_SWEEP * mph / SPEEDO_MAX
        major = mph % 10 == 0
        d.line([_polar(c, px(SPEEDO_TICKS[0] if major else SPEEDO_TICKS[0] + 0.003), deg),
                _polar(c, px(SPEEDO_TICKS[1]), deg)], fill=INK, width=7 if major else 4)
        if major:
            _text(d, _polar(c, px(SPEEDO_NUMBERS), deg), str(mph), _font(round(px(0.0095)), True), INK)
    _text(d, (c[0], c[1] + px(0.017)), 'MPH', _font(round(px(0.006)), True), INK)
    # The small gauges: a short scale across the top with its letters outside it.
    for kind, x in SMALL:
        cc = _px(x, SMALL_Z)
        r = px(SMALL_R)
        d.ellipse([cc[0] - r, cc[1] - r, cc[0] + r, cc[1] + r], outline=INK, width=6)
        label = {'temp': 'TEMPERATURE', 'generator': 'GENERATOR', 'oil': 'OIL', 'gas': 'GASOLINE'}[kind]
        if kind in ('generator', 'oil'):
            lr = px(0.0095)
            d.ellipse([cc[0] - lr, cc[1] - lr - px(0.003), cc[0] + lr, cc[1] + lr - px(0.003)],
                      fill=LAMP, outline=INK, width=4)
            _text(d, (cc[0], cc[1] + px(0.0135)), label, _font(round(px(0.0042)), True), INK)
            continue
        marks = [('C', -45.0), ('H', 45.0)] if kind == 'temp' else [('E', -45.0), ('F', 45.0)]
        r0 = px(SMALL_TICKS[0])
        d.arc([cc[0] - r0, cc[1] - r0, cc[0] + r0, cc[1] + r0], -135, -45, fill=INK, width=4)
        for k in range(5):
            deg = -45.0 + 90.0 * k / 4
            d.line([_polar(cc, px(SMALL_TICKS[0]), deg),
                    _polar(cc, px(SMALL_TICKS[1] if k % 2 == 0 else SMALL_TICKS[1] - 0.0015), deg)],
                   fill=(220, 40, 32) if kind == 'gas' and k == 0 else INK, width=5)
        for m, deg in marks:
            _text(d, _polar(cc, px(SMALL_LETTERS), deg), m, _font(round(px(0.0062)), True), INK)
        _text(d, (cc[0], cc[1] + px(0.0135)), label, _font(round(px(0.0042)), True), INK)
    return im


def face_material(image_index):
    return {'name': 'dash_c10_face_mat', 'doubleSided': True,
            'emissiveFactor': [0.65, 0.65, 0.65], 'emissiveTexture': {'index': image_index},
            'pbrMetallicRoughness': {'baseColorTexture': {'index': image_index},
                                     'metallicFactor': 0.3, 'roughnessFactor': 0.4}}


def face_png():
    return _png(face_texture())


def _moved(part, x, z):
    tris, nrm = part
    return tris + np.array([x, 0.0, z]), nrm


def cluster_parts():
    """The speedometer pod's meshes in its own frame, {key: [(material, tris, normals, uv)]}:
    the fixed parts and the speedometer needle; and the gas pointer's pod offset (x, z)
    with its needle."""
    temp_x = dict(SMALL)['temp']
    gas_x = dict(SMALL)['gas']
    fixed = [
        ('hood', *hood(), None),
        ('bezel', *bezel(), None),
        ('face', *face_mesh()),
        ('needle', *_moved(_needle(SMALL_NEEDLE, 0.004, 0.0013, TEMP_AT, -0.003), temp_x, SMALL_Z), None),
        ('cap', *_moved(_cap(_circle(0.0035, 16), -0.0035, -1.0), temp_x, SMALL_Z), None),
        ('cap', *_moved(_cap(_circle(0.0035, 16), -0.0035, -1.0), gas_x, SMALL_Z), None),
    ]
    speedo = [('needle', *_needle(SPEEDO_NEEDLE, 0.009, 0.0021, -SPEEDO_SWEEP / 2, -0.004), None),
              ('cap', *_cap(_circle(0.0065, 20), -0.0055, -1.0), None)]
    gas = [('needle', *_needle(SMALL_NEEDLE, 0.004, 0.0013, GAS_SWEEP / 2, -0.003), None)]
    return {'fixed': fixed, 'speedo': speedo, 'gas': gas, 'gas_at': (gas_x, SMALL_Z)}


def glovebox_parts():
    """The glovebox's brow: the same hood, closed, with a chrome strip along its foot."""
    outer = hood_outline()
    z0 = outer[:, 1].min()
    strip = _rounded_prism(_rounded_rect(FACE_W * 0.8, 0.008, 0.0035, 4, z0 + 0.012), -HOOD_OUT - 0.003,
                           -HOOD_OUT + 0.004, 0.002)
    return [('hood', *hood(closed=True), None), ('bezel', *strip, None)]


def wheel_texture():
    """(albedo PNG, ORM PNG, {swatch: uv}) for the steering wheel."""
    n = len(WHEEL_SWATCHES)
    albedo = Image.new('RGBA', (16 * n, 16), (0, 0, 0, 0))
    orm = Image.new('RGB', (16 * n, 16))
    uv = {}
    for i, (key, (rgb, rough, metal)) in enumerate(WHEEL_SWATCHES.items()):
        albedo.paste((*rgb, 0), (16 * i, 0, 16 * i + 16, 16))
        orm.paste((255, round(rough * 255), round(metal * 255)), (16 * i, 0, 16 * i + 16, 16))
        uv[key] = ((i + 0.5) / n, 0.5)
    return _png(albedo), _png(orm), uv


def _torus(R, r, n=64, m=12):
    tris, nrm = [], []
    for i in range(n):
        for j in range(m):
            quad = []
            for di, dj in ((0, 0), (1, 0), (1, 1), (0, 1)):
                a = 2 * math.pi * (i + di) / n
                b = 2 * math.pi * (j + dj) / m
                ring = np.array([math.cos(a), math.sin(a), 0.0])
                normal = ring * math.cos(b) + np.array([0.0, 0.0, math.sin(b)])
                quad.append((ring * R + normal * r, normal))
            p = [q[0] for q in quad]
            nn = [q[1] for q in quad]
            tris += [[p[0], p[1], p[2]], [p[0], p[2], p[3]]]
            nrm += [[nn[0], nn[1], nn[2]], [nn[0], nn[2], nn[3]]]
    return np.array(tris), np.array(nrm)


def _frustum(r0, z0, r1, z1, n=32, cap0=True):
    """A cone from radius r0 at z0 to r1 at z1 about the Z axis, normals out, and a flat
    end at z0 facing -Z."""
    tris, nrm = [], []
    slope = (r0 - r1) / (z1 - z0)
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        d0, d1 = np.array([math.cos(a0), math.sin(a0), 0.0]), np.array([math.cos(a1), math.sin(a1), 0.0])
        p = [d0 * r0 + [0, 0, z0], d1 * r0 + [0, 0, z0], d1 * r1 + [0, 0, z1], d0 * r1 + [0, 0, z1]]
        n0 = d0 + [0, 0, slope]
        n1 = d1 + [0, 0, slope]
        n0, n1 = n0 / np.linalg.norm(n0), n1 / np.linalg.norm(n1)
        tris += [[p[0], p[2], p[1]], [p[0], p[3], p[2]]]
        nrm += [[n0, n1, n1], [n0, n0, n1]]
        if cap0:
            tris.append([[0, 0, z0], d0 * r0 + [0, 0, z0], d1 * r0 + [0, 0, z0]])
            nrm.append([[0, 0, -1]] * 3)
    return np.array(tris, float), np.array(nrm, float)


def _dome(r, z, depth, n=32, rings=4):
    """A shallow dome of radius r at z bulging toward -Z by `depth`."""
    tris, nrm = [], []
    big = (r * r + depth * depth) / (2 * depth)
    center = np.array([0.0, 0.0, z - depth + big])

    def point(t, a):
        rad = r * t
        h = math.sqrt(max(big * big - rad * rad, 0.0))
        p = np.array([rad * math.cos(a), rad * math.sin(a), center[2] - h])
        return p, (p - center) / big

    for k in range(rings):
        for i in range(n):
            a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            q = [point(k / rings, a0), point(k / rings, a1), point((k + 1) / rings, a1), point((k + 1) / rings, a0)]
            tris += [[q[0][0], q[2][0], q[1][0]], [q[0][0], q[3][0], q[2][0]]]
            nrm += [[q[0][1], q[2][1], q[1][1]], [q[0][1], q[3][1], q[2][1]]]
    return np.array(tris), np.array(nrm)


def _spoke(side):
    """A flat brushed spoke from the hub out to the rim along +X (side 1) or -X (-1),
    dished: it starts HUB_DISH toward the column and meets the rim's middle."""
    r0, r1 = HUB_R - 0.004, WHEEL_R - RIM_R
    z0, z1 = HUB_DISH * 0.75, 0.0
    w0, w1 = SPOKE_W
    pts = []
    for r, z, w in ((r0, z0, w0), (r1, z1, w1)):
        for dy in (-w / 2, w / 2):
            for dz in (-SPOKE_T / 2, SPOKE_T / 2):
                pts.append(np.array([side * r, dy, z + dz]))
    # The corners: at the hub end then the rim end, each -Y/+Y by back/front; the box's
    # four long faces (its ends are inside the hub and the rim).
    a = pts[:4]
    b = pts[4:]
    faces = [(a[0], a[2], b[2], b[0]), (a[1], b[1], b[3], a[3]),   # front (-Z) and back (+Z)
             (a[0], b[0], b[1], a[1]), (a[2], a[3], b[3], b[2])]   # the two edges
    middle = np.mean(pts, 0)
    tris, nrm = [], []
    for q in faces:
        nn = np.cross(q[1] - q[0], q[2] - q[0])
        nn /= np.linalg.norm(nn)
        if np.dot(nn, np.mean(q, 0) - middle) < 0:
            q, nn = q[::-1], -nn
        tris += [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]
        nrm += [[nn] * 3, [nn] * 3]
    return np.array(tris), np.array(nrm)


def _emblem(z):
    """The horn button's red bar, flat on its face at z, facing -Z."""
    pts = np.array([[-0.017, -0.0035], [0.012, -0.0035], [0.017, 0.0035], [-0.012, 0.0035]])
    q = [np.array([p[0], p[1], z]) for p in pts]
    tris = np.array([[q[0], q[2], q[1]], [q[0], q[3], q[2]]])
    return tris, np.zeros_like(tris) + np.array([0.0, 0.0, -1.0])


def wheel_parts():
    """The steering wheel's meshes in its own frame: [(swatch, tris, normals)]."""
    hub_face = HUB_DISH - 0.004
    return [
        ('rim', *_torus(WHEEL_R - RIM_R, RIM_R)),
        ('spoke', *_join(_spoke(1), _spoke(-1))),
        ('spoke', *_frustum(HUB_R, HUB_DISH, HUB_BACK_R, HUB_BACK)),
        ('chrome', *_dome(HUB_R * 0.82, hub_face, 0.012)),
        ('emblem', *_emblem(hub_face - 0.0125)),
    ]
