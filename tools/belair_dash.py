"""The 1954 Chevrolet Bel Air's dash, instrument cluster and steering wheel. Used by
tools/belair_to_glb.py.

The model has no dash inside the windshield (only the cowl outside it) and only the top
half of a steering wheel, so both are made here, after photos of 1953-54 Chevrolet dashes
(reference/cars/54-Bel-Air/notes.md; the user's close-up of a turquoise '54's cluster and
a photo of the whole front of one):

  * the dash (after Joe Mabel's photo of a factory '54, the most faithful of them) rolls
    over from the windshield's foot in a deep curve that bulges out toward the driver, in
    the body color, and tucks under onto a white panel set back below it (the accent
    color) that carries the knobs and the radio; its ends run out to the doors (the
    converter fits them to the body). The cluster sits in a housing of the body color
    that stands out from the dash, its face turned up toward the driver;
  * the cluster in front of the driver, after the user's photo of a restored one (eBay
    listings 227631867062 and 880086601734): a chrome bezel, the speedometer's ring its
    round end on the driver's left, a long band round to the clock at the other end, level
    with it. The speedometer's face is dark grey-green with fine rings, its numbers 0 to
    110 every 10 round 290 degrees turned with the dial, a ring of dots inside them and a
    domed chrome boss in the middle with the odometer, the short pointer coming out from
    under it. The clock has the even hours, dots between and gold hands on a chrome boss.
    The brushed plate between has two long windows, TEMPERATURE (C to H) beside GASOLINE
    (E to F) over BATTERY (D to C) beside OIL PRESSURE (0 to 60), with green dots and pale
    letters, and green turn arrows at its ends;
  * the speaker grille, tall chrome ribs in a chrome frame, runs across the dash from the
    cluster toward the passenger's side, the radio on the white band under its near end;
  * the steering wheel and the column are in the body color, the wheel with two spokes
    down to a chrome hub and a chrome horn ring inside its rim; a chrome gear lever with a
    black knob stands out of the column;
  * the bench seat is dark teal.

The clock stands at ten past ten.

The cluster's pod follows the other cars' dashes (tools/studebaker_dash.py): in its frame
the face lies in the X-Z plane facing -Y, +X to the driver's right and +Z up, with the
speedometer's pivot at the origin; it is named `dash_speedo_arch_270_mph_110_pod` and its
needle turns clockwise from 0. The gas gauge's pointer slides in a pod of its own named
for its travel, `dash_fuel_linear_<travel>_pod`, resting at F and sliding along -X
toward E.

The steering wheel is built in its own frame: +Z down the column into the dash, +X
across to the driver's left, +Y up the wheel; the game turns it about +Z.
"""
import math

import numpy as np
from PIL import Image, ImageDraw

from c10_dash import _dome, _frustum, _spoke, _torus
from studebaker_dash import (MATERIALS, _cap, _circle, _font, _join, _needle, _png, _polar, _rounded_prism,
                             _text, _wall)

## The dash (the car's frame, meters): its profile across, as (y, z) points, the body-colored
## upper part from under the windshield, over its roll and under onto the white lower
## panel, and that panel; how far across they run at most each side of the middle (the
## converter stops them short of the body's sides) and how far short.
DASH_UPPER = [(0.985, 0.95), (0.975, 0.85), (0.962, 0.75), (0.945, 0.68), (0.92, 0.635), (0.88, 0.608),
              (0.83, 0.602), (0.78, 0.612), (0.75, 0.632), (0.735, 0.66), (0.735, 0.72), (0.95, 0.95)]
DASH_BAND = [(0.74, 0.668), (0.70, 0.672), (0.64, 0.675), (0.60, 0.69), (0.585, 0.72), (0.59, 0.78),
             (0.74, 0.78)]
DASH_HALF = 0.95
SIDE_GAP = 0.004

## The cluster (pod frame, meters), after the restored one: a level band with round ends
## from the speedometer (at the origin) to the clock's middle CLOCK_AT, BAND_OUT high each
## side of its middle, its chrome rim a ridge BAND_PEAK high round the brushed plate inside
## BAND_IN; the speedometer's face SPEEDO_R across in a taller ridged ring out to SPEEDO_OUT,
## standing out from the band by SPEEDO_PROUD; the clock's face CLOCK_R in a ring out to
## CLOCK_RING, with its setting knob on the side toward the speedometer. Round it all, the
## housing in the body color, POD_LIP wide, reaching back POD_DEPTH into the dash.
BAND_OUT = 0.077
BAND_IN = 0.058
BAND_PEAK = 0.016
SPEEDO_PEAK = 0.024
CLOCK_PEAK = 0.012
POD_LIP = 0.040
POD_DEPTH = 0.09
## The housing's brow: how far its lip stands out toward the driver at the bottom and at
## the top, over the cluster.
POD_PEAK = (0.008, 0.045)
SPEEDO_R = 0.068
SPEEDO_OUT = 0.087
SPEEDO_PROUD = 0.012
CLOCK_AT = (0.331, 0.0)
CLOCK_R = 0.040
CLOCK_RING = 0.052
CLOCK_KNOB = (-0.050, 0.010, 0.0045)
SEGMENTS = 28
## Where the pod sits (the car's frame): the speedometer's pivot, and the way the face looks
## (toward the driver, flat on the dash's face).
SPEEDO_AT = (0.48, 0.835, 0.585)
FACING = (0.0, 0.35, -1.0)

SPEEDO_SWEEP = 290.0
SPEEDO_MAX = 110
SPEEDO_NUMBERS = 0.057
SPEEDO_DOTS = 0.039
SPEEDO_BOSS = 0.032
SPEEDO_NEEDLE = 0.044
## The two long windows (pod frame): their ends across, middles up and height; each holds
## two gauges, (label, letters at its ends, where its pointer stands, 0 to 1, None if it
## works).
WINDOW_X = (0.111, 0.269)
WINDOW_H = 0.0165
WINDOWS = [
    (0.0315, [('TEMPERATURE', ('C', 'H'), 0.15), ('GASOLINE', ('E', 'F'), None)]),
    (-0.030, [('BATTERY', ('D', 'C'), 0.5), ('OIL PRESSURE', ('0', '60'), 0.25)]),
]
## A window's pointer: a thin bar standing across it; how far in from a half's ends its
## scale runs.
POINTER_W = 0.0016
SCALE_IN = 0.007
## The clock's hands at ten past ten (degrees clockwise from up) and lengths.
CLOCK_HANDS = ((300.0, 0.022, 0.0024), (60.0, 0.031, 0.0018))

TEX_W = 2048
FACE = (50, 54, 50)
INK = (206, 216, 196)
PLATE = (176, 178, 182)
GREEN_DOT = (70, 170, 110)
RED = (200, 46, 34)
GREEN = (60, 180, 90)

## The speaker grille on the upper dash's face, across (x) and up (y) it, and the radio's
## plate on the white panel under its near end (the car's frame); each follows the face's
## curve, standing out from it by PANEL_OUT.
GRILLE_X = (0.04, -0.64)
GRILLE_Y = (0.748, 0.905)
GRILLE_RIBS = 64
RADIO_X = (0.05, -0.12)
RADIO_Y = (0.676, 0.722)
PANEL_OUT = 0.004
## Knobs on the white panel (the car's frame, x positions; the last two at the radio's
## ends), their height and size.
KNOBS_X = (0.29, 0.23, 0.15, 0.074, -0.144)
KNOB_Y = 0.699
KNOB_R = 0.011
KNOB_OUT = 0.016

## The steering wheel (meters): 17 in across, its rim, the hub, the spokes down to it and
## the horn ring inside the rim.
WHEEL_R = 8.5 * 0.0254
RIM_R = 0.012
HUB_DISH = 0.055
HUB_R = 0.042
HUB_BACK_R = 0.030
HUB_BACK = 0.10
SPOKE_DOWN = 35.0
HORN_R = 0.80
HORN_THICK = 0.0045
## Swatches: (color, roughness, metallic); the color None is the body's paint (white with
## alpha 1, which the game paints).
WHEEL_SWATCHES = {
    'rim': (None, 0.3, 0.0),
    'spoke': (None, 0.3, 0.0),
    'chrome': ((224, 226, 230), 0.10, 1.0),
    'emblem': ((190, 28, 30), 0.3, 0.2),
    'knob': ((20, 20, 22), 0.3, 0.0),
}
## The gear lever: where it leaves the column (along it from the hub), its way out (the
## wheel's frame) and length, its rod's and its knob's radius.
LEVER_AT = 0.085
LEVER_WAY = (-0.8, 0.28, -0.25)
LEVER_LEN = 0.17
LEVER_R = 0.005
LEVER_KNOB = 0.012

## The front compartment, which the model leaves empty under its black lid (the car's
## frame, meters; profiles as (y, z) run across between +-INTERIOR_HALF): the bench seat's
## cushion and back, the toe board under the dash and the carpet on the floor.
INTERIOR_HALF = 0.78
CUSHION = [(0.28, -0.10), (0.28, 0.36), (0.40, 0.385), (0.455, 0.35), (0.465, -0.05), (0.44, -0.10)]
SEAT_BACK = [(0.44, -0.08), (0.94, -0.115), (0.975, -0.15), (0.96, -0.21), (0.44, -0.22)]
REAR_CUSHION = [(0.26, -1.02), (0.26, -0.56), (0.38, -0.535), (0.44, -0.57), (0.45, -0.98), (0.43, -1.02)]
REAR_BACK = [(0.43, -1.0), (0.86, -1.06), (0.895, -1.10), (0.88, -1.15), (0.43, -1.13)]
TOE_BOARD = [(0.585, 0.76), (0.585, 0.785), (0.07, 0.885), (0.07, 0.86)]
CARPET = [(0.08, -1.14), (0.08, 0.88), (0.10, 0.88), (0.10, -1.14)]
INTERIOR_SWATCHES = {
    'seat': ((38, 96, 98), 0.8, 0.0),
    'carpet': ((26, 46, 48), 0.95, 0.0),
}

DASH_MATERIALS = {
    'bezel': MATERIALS['bezel'],
    'chrome': {'name': 'dash_belair_chrome_mat', 'doubleSided': True,
               'pbrMetallicRoughness': {'baseColorFactor': [0.86, 0.87, 0.89, 1.0],
                                        'metallicFactor': 1.0, 'roughnessFactor': 0.12}},
    'needle': MATERIALS['needle'],
    'pointer': MATERIALS['pointer'],
    'gold': {'name': 'dash_belair_gold_mat', 'doubleSided': True,
             'pbrMetallicRoughness': {'baseColorFactor': [0.78, 0.62, 0.30, 1.0],
                                      'metallicFactor': 0.9, 'roughnessFactor': 0.25}},
    'cap': MATERIALS['cap'],
    'knob': {'name': 'dash_belair_knob_mat', 'doubleSided': True,
             'pbrMetallicRoughness': {'baseColorFactor': [0.80, 0.76, 0.66, 1.0],
                                      'metallicFactor': 0.0, 'roughnessFactor': 0.3}},
}


def profile(points):
    """A dash profile turned counterclockwise as tools/studebaker_dash.py's _extrude_x wants it."""
    p = np.array(points, float)
    area = 0.5 * np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1])
    return p if area > 0 else p[::-1]


def stadium(half=BAND_IN, segments=SEGMENTS):
    """The band's outline in the pod's X-Z plane, `half` high each side of its middle, with
    round ends at the speedometer and the clock, counterclockwise as the driver sees it."""
    cx, cz = CLOCK_AT
    pts = []
    for i in range(segments + 1):
        a = math.radians(-90 + 180 * i / segments)
        pts.append((cx + half * math.cos(a), cz + half * math.sin(a)))
    for i in range(segments + 1):
        a = math.radians(90 + 180 * i / segments)
        pts.append((half * math.cos(a), cz + half * math.sin(a)))
    return np.array(pts)


def _bounds():
    return -SPEEDO_R, CLOCK_AT[0] + BAND_IN, -SPEEDO_R, SPEEDO_R


def _px(x, z):
    """Texture pixel of a point on the face (pod frame, meters)."""
    x0, x1, z0, z1 = _bounds()
    s = TEX_W / (x1 - x0)
    return (x - x0) * s, (z1 - z) * s


def face_mesh(outline=None, y=-0.0005):
    """The face (or a part of it inside `outline`) at depth y, facing -Y, with UVs over
    the texture."""
    x0, x1, z0, z1 = _bounds()
    tris, nrm = _cap(stadium() if outline is None else outline, y, -1.0)
    u = (tris[..., 0] - x0) / (x1 - x0)
    v = (z1 - tris[..., 2]) / (z1 - z0)
    return tris, nrm, np.stack([u, v], -1)


def _halves():
    """Each gauge in the windows: (window's middle up, label, letters, pointer, its scale's
    two ends across)."""
    x0, x1 = WINDOW_X
    mid = (x0 + x1) / 2
    out = []
    for wz, gauges in WINDOWS:
        for (label, letters, at), (a, b) in zip(gauges, ((x0, mid), (mid, x1))):
            out.append((wz, label, letters, at, (a + SCALE_IN, b - SCALE_IN)))
    return out


def _turned_text(im, xy, s, font, fill, deg):
    """Text centered on xy, turned `deg` clockwise."""
    size = int(font.size * 3)
    tile = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(tile).text((size / 2, size / 2), s, font=font, fill=(*fill, 255), anchor='mm')
    tile = tile.rotate(-deg, resample=Image.BICUBIC)
    im.paste(tile, (round(xy[0] - size / 2), round(xy[1] - size / 2)), tile)


def _dot(d, p, r, fill):
    d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def face_texture():
    x0, x1, z0, z1 = _bounds()
    s = TEX_W / (x1 - x0)
    h = round((z1 - z0) * s)
    px = lambda m: m * s
    # Brushed metal across the plate.
    rng = np.random.default_rng(1954)
    rows = np.clip(PLATE[0] + rng.normal(0.0, 5.0, (h, 1)) + rng.normal(0.0, 2.0, (h, TEX_W)), 0, 255)
    im = Image.fromarray(np.repeat(rows[..., None], 3, 2).astype(np.uint8), 'RGB')
    d = ImageDraw.Draw(im)
    # The speedometer: dark, finely ringed; the numbers every 10 round the outside turned
    # with the dial, a ring of dots inside them every 2, the boss and the odometer.
    c = _px(0.0, 0.0)
    for k in range(60):
        r = px(SPEEDO_R * (1 - k / 60))
        shade = 4 if k % 2 else -3
        d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=tuple(v + shade for v in FACE))
    half = SPEEDO_SWEEP / 2
    font = _font(round(px(0.0115)), True)
    for mph in range(0, SPEEDO_MAX + 1, 2):
        deg = -half + SPEEDO_SWEEP * mph / SPEEDO_MAX
        if mph % 10 == 0:
            _turned_text(im, _polar(c, px(SPEEDO_NUMBERS), deg), str(mph), font, INK, deg)
        _dot(d, _polar(c, px(SPEEDO_DOTS), deg), px(0.0013 if mph % 10 == 0 else 0.0009), INK)
    for k in range(14):
        r = px(SPEEDO_BOSS * (1 - k / 14))
        level = 150 + (80 if k % 2 == 0 else 20)
        d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=(level, level, level + 4))
    odo = (c[0] - px(0.012), c[1] + px(0.010), c[0] + px(0.014), c[1] + px(0.019))
    d.rectangle(odo, fill=(30, 30, 30), outline=(235, 235, 235), width=4)
    _text(d, ((odo[0] + odo[2]) / 2, (odo[1] + odo[3]) / 2), '48521', _font(round(px(0.0068)), True), (230, 230, 230))
    # The clock: dark, the even hours, dots between, a chrome boss.
    c = _px(*CLOCK_AT)
    r = px(CLOCK_R)
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=FACE)
    for hour in range(12):
        deg = hour * 30.0
        if hour % 2 == 0:
            _turned_text(im, _polar(c, px(0.030), deg), str(hour or 12), _font(round(px(0.0075)), True), INK, 0.0)
        else:
            _dot(d, _polar(c, px(0.031), deg), px(0.0010), INK)
    for k in range(6):
        r = px(0.011 * (1 - k / 6))
        level = 150 + (80 if k % 2 == 0 else 20)
        d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=(level, level, level + 4))
    # The two windows: dark, green dots between their letters, labels under them; the green
    # arrows at the plate's ends.
    for wz, _ in WINDOWS:
        a, b = _px(WINDOW_X[0], wz + WINDOW_H / 2), _px(WINDOW_X[1], wz - WINDOW_H / 2)
        d.rounded_rectangle([a, b], radius=px(WINDOW_H / 2), fill=(30, 34, 32), outline=(120, 122, 126), width=5)
    for wz, label, (lo, hi), _, (a, b) in _halves():
        font = _font(round(px(0.0066)), True)
        _text(d, _px(a, wz + 0.0015), lo, font, INK)
        _text(d, _px(b, wz + 0.0015), hi, font, INK)
        for k in range(1, 4):
            _dot(d, _px(a + (b - a) * k / 4, wz + 0.0015), px(0.0009), GREEN_DOT)
        _text(d, _px((a + b) / 2, wz - 0.0058), label, _font(round(px(0.0030)), True), INK)
    for x, way in ((0.116, -1), (0.263, 1)):
        cx, cy = _px(x, 0.0)
        w = px(0.004)
        d.polygon([(cx + way * w, cy), (cx, cy - w * 0.8), (cx, cy - w * 0.3), (cx - way * w, cy - w * 0.3),
                   (cx - way * w, cy + w * 0.3), (cx, cy + w * 0.3), (cx, cy + w * 0.8)], fill=(40, 110, 80))
    return im


def face_material(image_index):
    return {'name': 'dash_belair_face_mat', 'doubleSided': True,
            'emissiveFactor': [0.6, 0.6, 0.6], 'emissiveTexture': {'index': image_index},
            'pbrMetallicRoughness': {'baseColorTexture': {'index': image_index},
                                     'metallicFactor': 0.3, 'roughnessFactor': 0.4}}


def face_png():
    return _png(face_texture())


def _moved(part, x, z, y=0.0):
    """A part moved by (x, y, z) in its frame."""
    tris, nrm = part
    return tris + np.array([x, y, z]), nrm


def _ridge(outer, inner, y_back, peak, crest=0.5, steps=8):
    """A rim between two outlines with the same corners (pod's X-Z plane): from the outer
    edge at depth y_back it rises toward the driver (-Y) to a crest `peak` high (or, an
    array, that high at each corner) at `crest` of the way in, and drops back down to the
    inner edge."""
    outer, inner = np.asarray(outer, float), np.asarray(inner, float)
    peak = np.broadcast_to(np.asarray(peak, float), (len(outer),))
    rows = []
    for k in range(steps + 1):
        t = k / steps
        h = math.sin(math.pi * min(t / crest, 1.0) / 2) if t <= crest else math.cos(math.pi * (t - crest) / (1 - crest) / 2)
        xz = outer + (inner - outer) * t
        rows.append(np.stack([xz[:, 0], y_back - peak * h, xz[:, 1]], 1))
    grid = np.array(rows)
    m = len(outer)
    d_along = np.roll(grid, -1, 1) - np.roll(grid, 1, 1)
    d_across = np.gradient(grid, axis=0)
    nrm = np.cross(d_along, d_across)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-12)
    if nrm[steps // 2, :, 1].mean() > 0:
        nrm = -nrm
    tris, nn = [], []
    for k in range(steps):
        for i in range(m):
            j = (i + 1) % m
            q = [grid[k, i], grid[k, j], grid[k + 1, j], grid[k + 1, i]]
            w = [nrm[k, i], nrm[k, j], nrm[k + 1, j], nrm[k + 1, i]]
            tris += [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]
            nn += [[w[0], w[1], w[2]], [w[0], w[2], w[3]]]
    return np.array(tris), np.array(nn)


def pod_parts():
    """The housing round the cluster, in the body color, in the pod's frame: a lip round the
    bezel and its sides back into the dash. [(tris, normals)]."""
    lip_out, lip_in = stadium(BAND_OUT + POD_LIP), stadium(BAND_OUT)
    # Low along the bottom, rising into a brow over the top that hoods the cluster.
    up = np.clip(lip_out[:, 1] / (BAND_OUT + POD_LIP), 0.0, 1.0)
    peak = POD_PEAK[0] + (POD_PEAK[1] - POD_PEAK[0]) * up ** 1.5
    return [_ridge(lip_out, lip_in, POD_DEPTH * 0.1, peak, crest=0.6, steps=10),
            _wall(stadium(BAND_OUT + POD_LIP), POD_DEPTH * 0.1, POD_DEPTH)]


def _frustum_y(r, y0, y1, n=16):
    """A knob: a short cylinder along -Y from y0 out to y1, closed at y1."""
    t, nn = _frustum(r, 0.0, r, y0 - y1, n=n)
    # _frustum runs along +Z from its closed end at z = 0: Y and Z swapped, it runs along +Y
    # from y1, closed there.
    m = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 1.0, 0.0]])
    return t @ m.T + np.array([0.0, y1, 0.0]), nn @ m.T


def _bar(x, z, w, h, y):
    """A flat bar facing -Y centered on (x, z)."""
    q = [(x - w / 2, y, z - h / 2), (x + w / 2, y, z - h / 2), (x + w / 2, y, z + h / 2), (x - w / 2, y, z + h / 2)]
    tris = np.array([[q[0], q[1], q[2]], [q[0], q[2], q[3]]])
    return tris, np.zeros_like(tris) + np.array([0.0, -1.0, 0.0])


def cluster_parts():
    """The cluster pod's meshes in its own frame, {key: [(material, tris, normals, uv)]}: the
    fixed parts, the speedometer's needle, and the gas pointer's pod offset (x, z) with its
    pointer, resting at F."""
    cx, cz = CLOCK_AT
    sy = -SPEEDO_PROUD
    kx, kz, kr = CLOCK_KNOB
    fixed = [
        # The band: its ridged rim, the plate.
        ('chrome', *_ridge(stadium(BAND_OUT), stadium(BAND_IN), 0.0, BAND_PEAK, crest=0.45), None),
        ('face', *face_mesh(stadium(BAND_IN))),
        # The speedometer, standing out over the band's end: its taller ridged ring, steep on
        # the inside, and its face down in it.
        ('chrome', *_ridge(_circle(SPEEDO_OUT, 72), _circle(SPEEDO_R, 72), 0.0, SPEEDO_PEAK, crest=0.6), None),
        ('chrome', *_wall(_circle(SPEEDO_R, 72), sy - 0.006, sy, outward=False), None),
        ('face', *face_mesh(_circle(SPEEDO_R, 72), sy)),
        # Its boss stands in front of its pointer.
        ('face', *face_mesh(_circle(SPEEDO_BOSS, 40), sy - 0.0065)),
        # The clock: its ring, hands, boss and setting knob.
        ('chrome', *_moved(_ridge(_circle(CLOCK_RING, 48), _circle(CLOCK_R, 48), 0.0, CLOCK_PEAK, crest=0.55), cx, cz), None),
        ('gold', *_moved(_needle(CLOCK_HANDS[0][1], 0.004, CLOCK_HANDS[0][2], CLOCK_HANDS[0][0], -0.0025), cx, cz), None),
        ('gold', *_moved(_needle(CLOCK_HANDS[1][1], 0.004, CLOCK_HANDS[1][2], CLOCK_HANDS[1][0], -0.0030), cx, cz), None),
        ('chrome', *_moved(_cap(_circle(0.003, 16), -0.0035, -1.0), cx, cz), None),
        ('chrome', *_moved(_frustum_y(kr, -0.006, -0.012), cx + kx, cz + kz), None),
    ]
    gas_at = None
    for wz, label, _, at, (a, b) in _halves():
        if at is None:
            gas_at = (b, wz)
            travel = b - a
            continue
        fixed.append(('pointer', *_bar(a + (b - a) * at, wz, POINTER_W, WINDOW_H * 0.7, -0.0015), None))
    speedo = [('pointer', *_needle(SPEEDO_NEEDLE, 0.0, 0.0024, -SPEEDO_SWEEP / 2, -SPEEDO_PROUD - 0.0035), None)]
    gas = [('pointer', *_bar(0.0, 0.0, POINTER_W, WINDOW_H * 0.7, -0.0015), None)]
    return {'fixed': fixed, 'speedo': speedo, 'gas': gas, 'gas_at': gas_at, 'gas_travel': travel}


def grille_texture():
    """The speaker grille: chrome ribs, light and dark, inside a bright frame."""
    w, h = 1024, round(1024 * (GRILLE_Y[1] - GRILLE_Y[0]) / abs(GRILLE_X[1] - GRILLE_X[0]))
    im = Image.new('RGB', (w, h), (214, 216, 220))
    d = ImageDraw.Draw(im)
    frame = 10
    rib = (w - 2 * frame) / GRILLE_RIBS
    for k in range(GRILLE_RIBS):
        x = frame + k * rib
        for i in range(int(rib) + 1):
            t = i / rib
            level = int(70 + 170 * math.sin(math.pi * t) ** 0.6)
            d.line([(x + i, frame + 4), (x + i, h - frame - 4)], fill=(level, level, level + 6))
    d.rectangle([0, 0, w - 1, h - 1], outline=(240, 242, 245), width=frame)
    return im


def radio_texture():
    """The radio's plate: chrome with a dark dial window and its numbers."""
    w, h = 512, round(512 * (RADIO_Y[1] - RADIO_Y[0]) / abs(RADIO_X[1] - RADIO_X[0]))
    im = Image.new('RGB', (w, h), (206, 208, 212))
    d = ImageDraw.Draw(im)
    d.rectangle([4, 4, w - 5, h - 5], outline=(240, 242, 245), width=6)
    win = (w * 0.24, h * 0.30, w * 0.76, h * 0.70)
    d.rectangle(win, fill=(30, 28, 24))
    font = _font(18, True)
    for k, n in enumerate(('55', '70', '90', '110', '140', '170')):
        _text(d, (win[0] + (win[2] - win[0]) * (k + 0.5) / 6, (win[1] + win[3]) / 2), n, font, INK)
    return im


def knob(x, y, z):
    """A dash knob (the car's frame): a short cylinder out of the dash toward the driver."""
    tris, nrm = _frustum(KNOB_R, 0.0, KNOB_R * 0.9, KNOB_OUT, n=16)
    # The frustum runs along +Z with its flat end at z = 0 facing -Z (toward the driver):
    # moved so it ends at the dash face.
    return tris + np.array([x, y, z - KNOB_OUT]), nrm


def wheel_texture(swatches=None):
    """(albedo PNG, ORM PNG, {swatch: uv}) for the steering wheel, or other `swatches`
    (alpha 0: never painted)."""
    swatches = swatches or WHEEL_SWATCHES
    n = len(swatches)
    albedo = Image.new('RGBA', (16 * n, 16), (0, 0, 0, 0))
    orm = Image.new('RGB', (16 * n, 16))
    uv = {}
    for i, (key, (rgb, rough, metal)) in enumerate(swatches.items()):
        albedo.paste((255, 255, 255, 255) if rgb is None else (*rgb, 0), (16 * i, 0, 16 * i + 16, 16))
        orm.paste((255, round(rough * 255), round(metal * 255)), (16 * i, 0, 16 * i + 16, 16))
        uv[key] = ((i + 0.5) / n, 0.5)
    return _png(albedo), _png(orm), uv


def interior_parts(half_width):
    """The cabin's meshes in the car's frame: [(swatch, tris, normals)]: the seats, the toe
    board and the carpet, each end stopped at `half_width(y, z)`."""
    return [(key, *sweep(points, half_width, INTERIOR_HALF, SIDE_GAP))
            for key, points in (('seat', CUSHION), ('seat', SEAT_BACK), ('seat', REAR_CUSHION), ('seat', REAR_BACK),
                                ('carpet', TOE_BOARD), ('carpet', CARPET))]


def sweep(points, half_width, cap, gap=0.0):
    """A profile across the car ((y, z) points) run out each side to `half_width(y, z)`
    less `gap` at each point, at most `cap`, smooth along the profile, its ends closed (the
    car's frame). Where `half_width` finds no side (None, through glass), the point takes
    the nearest point's that did."""
    prof = profile(points)
    n = len(prof)
    raw = [half_width(y, z) for y, z in prof]
    found = [i for i, w in enumerate(raw) if w is not None]
    if not found:
        raw = [cap + gap] * n
    else:
        raw = [w if w is not None else raw[min(found, key=lambda k: min(abs(k - i), n - abs(k - i)))]
               for i, w in enumerate(raw)]
    ends = np.minimum(np.array(raw) - gap, cap)
    vn = []
    for i in range(n):
        e0 = prof[i] - prof[i - 1]
        e1 = prof[(i + 1) % n] - prof[i]
        n0 = np.array([e0[1], -e0[0]]) / np.linalg.norm(e0)
        n1 = np.array([e1[1], -e1[0]]) / np.linalg.norm(e1)
        m = n0 + n1
        vn.append(m / np.linalg.norm(m))
    tris, nrm = [], []
    for i in range(n):
        j = (i + 1) % n
        a0, a1 = (-ends[i], *prof[i]), (ends[i], *prof[i])
        b0, b1 = (-ends[j], *prof[j]), (ends[j], *prof[j])
        na, nb = (0.0, *vn[i]), (0.0, *vn[j])
        tris += [[a0, b0, b1], [a0, b1, a1]]
        nrm += [[na, nb, nb], [na, nb, na]]
    center = prof.mean(0)
    for sx in (-1.0, 1.0):
        c = (sx * ends.mean(), *center)
        for i in range(n):
            j = (i + 1) % n
            tris.append([c, (sx * ends[i], *prof[i]), (sx * ends[j], *prof[j])])
            nrm.append([(sx, 0.0, 0.0)] * 3)
    return np.array(tris, float), np.array(nrm, float)


def dash_parts(half_width):
    """The dash's two parts in the car's frame, ends stopped at `half_width(y, z)`:
    [(paint, tris, normals)], paint 'paint' or 'accent'."""
    return [(key, *sweep(points, half_width, DASH_HALF, SIDE_GAP))
            for key, points in (('paint', DASH_UPPER), ('accent', DASH_BAND))]


def on_face(points, y0, y1, x0, x1, out, steps=12):
    """A strip lying on a dash profile's face from height y0 to y1 and across from x0 to x1,
    `out` toward the driver, following the face's curve, with UVs across it (u from x0 to
    x1) and up it (v from y1 down to y0): (tris, normals, uvs)."""
    face = _outer_face(points)
    ys = np.linspace(y0, y1, steps)
    zs = np.interp(ys, face[:, 0], face[:, 1])
    dz = np.gradient(zs, ys)
    nrm2 = np.stack([dz, -np.ones_like(dz)], 1)
    nrm2 /= np.linalg.norm(nrm2, axis=1, keepdims=True)
    yy, zz = ys + nrm2[:, 0] * out, zs + nrm2[:, 1] * out
    tris, nn, uv = [], [], []
    for k in range(steps - 1):
        q = [(x0, yy[k], zz[k]), (x1, yy[k], zz[k]), (x1, yy[k + 1], zz[k + 1]), (x0, yy[k + 1], zz[k + 1])]
        w = [(0.0, nrm2[k, 0], nrm2[k, 1])] * 2 + [(0.0, nrm2[k + 1, 0], nrm2[k + 1, 1])] * 2
        t = [(0.0, 1 - k / (steps - 1)), (1.0, 1 - k / (steps - 1)), (1.0, 1 - (k + 1) / (steps - 1)),
             (0.0, 1 - (k + 1) / (steps - 1))]
        tris += [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]
        nn += [[w[0], w[1], w[2]], [w[0], w[2], w[3]]]
        uv += [[t[0], t[1], t[2]], [t[0], t[2], t[3]]]
    return np.array(tris), np.array(nn), np.array(uv)


def _outer_face(points):
    """A dash profile's face toward the driver: for each of its heights the least z, as
    (y, z) rows by height."""
    prof = np.array(points, float)
    rows = {}
    for y, z in prof:
        rows[round(y, 4)] = min(rows.get(round(y, 4), 9.0), z)
    # Points on the closing edges (back into the dash) are not on the face: keep only those
    # that are the least z for their height among the profile's segments.
    ys = np.array(sorted(rows))
    zs = np.array([rows[round(y, 4)] for y in ys])
    keep = [i for i, (y, z) in enumerate(zip(ys, zs)) if z <= _least_z(prof, y) + 1e-6]
    return np.stack([ys[keep], zs[keep]], 1)


def _least_z(prof, y):
    """The least z where a closed profile crosses height y."""
    best = 9.0
    for i in range(len(prof)):
        (y0, z0), (y1, z1) = prof[i], prof[(i + 1) % len(prof)]
        if min(y0, y1) - 1e-9 <= y <= max(y0, y1) + 1e-9:
            z = z0 if abs(y1 - y0) < 1e-12 else z0 + (z1 - z0) * (y - y0) / (y1 - y0)
            best = min(best, z)
    return best


def face_z(points, y):
    """How far forward a dash profile's face is at height y."""
    return _least_z(np.array(points, float), y)


def _turn_z(part, deg):
    tris, nrm = part
    a = math.radians(deg)
    m = np.array([[math.cos(a), -math.sin(a), 0.0], [math.sin(a), math.cos(a), 0.0], [0.0, 0.0, 1.0]])
    return tris @ m.T, nrm @ m.T


def wheel_parts():
    """The steering wheel's meshes in its own frame: [(swatch, tris, normals)]."""
    import c10_dash
    saved = (c10_dash.WHEEL_R, c10_dash.RIM_R, c10_dash.HUB_R, c10_dash.HUB_DISH, c10_dash.SPOKE_W)
    c10_dash.WHEEL_R, c10_dash.RIM_R, c10_dash.HUB_R, c10_dash.HUB_DISH = WHEEL_R, RIM_R, HUB_R, HUB_DISH
    c10_dash.SPOKE_W = (0.040, 0.022)
    try:
        # Two spokes from the hub down and out to the rim, each SPOKE_DOWN below across.
        spokes = _join(_turn_z(_spoke(1), -SPOKE_DOWN), _turn_z(_spoke(-1), SPOKE_DOWN))
    finally:
        c10_dash.WHEEL_R, c10_dash.RIM_R, c10_dash.HUB_R, c10_dash.HUB_DISH, c10_dash.SPOKE_W = saved
    hub_face = HUB_DISH - 0.004
    ring = WHEEL_R * HORN_R
    return [
        ('rim', *_torus(WHEEL_R - RIM_R, RIM_R)),
        ('spoke', *spokes),
        ('spoke', *_frustum(HUB_R, HUB_DISH, HUB_BACK_R, HUB_BACK)),
        ('chrome', *_dome(HUB_R * 0.85, hub_face, 0.012)),
        ('chrome', *_moved(_torus(ring, HORN_THICK, 64, 8), 0.0, HUB_DISH * 0.3)),
        ('emblem', *_emblem(hub_face - 0.0125)),
    ]


def lever_parts():
    """The gear lever in the steering wheel's frame (it stays with the column, not the wheel):
    [(swatch, tris, normals)]."""
    way = np.array(LEVER_WAY, float)
    way /= np.linalg.norm(way)
    start = np.array([0.0, 0.0, HUB_BACK + LEVER_AT]) + way * HUB_BACK_R
    rod = _frustum(LEVER_R, 0.0, LEVER_R * 0.8, LEVER_LEN, n=12, cap0=False)
    knob = _frustum(LEVER_KNOB, LEVER_LEN, LEVER_KNOB * 0.8, LEVER_LEN + 0.03, n=16)
    # Along +Z from the origin, turned to run along `way` from `start`.
    z = way
    x = np.cross([0.0, 1.0, 0.0], z)
    x /= np.linalg.norm(x)
    m = np.stack([x, np.cross(z, x), z], 1)
    return [(key, t @ m.T + start, n @ m.T) for key, (t, n) in (('chrome', rod), ('knob', knob))]


def _emblem(z):
    """The horn button's red bow tie, flat on its face at z, facing -Z."""
    pts = np.array([[-0.016, -0.004], [-0.004, -0.002], [0.004, -0.002], [0.016, -0.004],
                    [0.016, 0.004], [0.004, 0.002], [-0.004, 0.002], [-0.016, 0.004]])
    q = [np.array([p[0], p[1], z]) for p in pts]
    tris = np.array([[q[0], q[1], q[6]], [q[0], q[6], q[7]], [q[1], q[2], q[5]], [q[1], q[5], q[6]],
                     [q[2], q[3], q[4]], [q[2], q[4], q[5]]])
    return tris, np.zeros_like(tris) + np.array([0.0, 0.0, -1.0])
