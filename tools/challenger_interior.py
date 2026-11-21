"""The 1970 Dodge Challenger's interior, built for tools/challenger_to_glb.py: the model
it starts from has none (a black lid at the window line, two block seats and an
eight-sided ring stand in for it).

References: reference/cars/1970-Dodge-Challenger/photos/ (the Challenger's dash and
cluster, and a 1970 'Cuda, its E-body twin, for the seats, wheel and shifter). The R/T's
Rallye dash: a padded top that sweeps back over the cluster in a hood in front of the
driver and steps forward over the passenger's side, where the glovebox is; under the
hood a woodgrain panel with four big round pods, from the driver's left: a 150 mph
speedometer, an 8000 rpm tachometer, a four-in-one gauge (fuel at the top, oil left,
temperature right, ammeter at the bottom) and a clock; a woodgrain panel of four knobs
at the driver's end, the heater controls under it and the radio under the clock. A
three-spoke wheel with a woodgrain rim and black spokes on a ribbed column; high-back
buckets with crosswise pleats, no console, a pistol-grip four-speed in a boot on the
tunnel, clutch and brake pedals; door panels with a woodgrain insert and an armrest;
black carpet.

Everything is in the car's frame (meters, Y up, nose +Z, driver's side +X, the body's
bottom at Y = 0). The pods follow the other cars' dashes (tools/studebaker_dash.py): in
a pod's frame the face lies in the X-Z plane facing -Y, +X to the driver's right and +Z
up, and the game turns a needle about the pod's +Y from where it rests, clockwise as
the driver sees it. The dials are drawn to the game's scales: the speedometer's needle
sweeps 270 degrees for 150 mph (`dash_speedo_arch_270_mph_150_pod`), the tachometer's
250 degrees for 7000 rpm (the game's fixed scale; the real dial's 1000 rpm steps are
36 degrees, so it reads true), and the fuel needle turns back from F toward E over 70
degrees (`dash_fuel_arch_70_pod`). The clock and the other three small needles stay put.

The game paints every textured surface whose texture has alpha 1, and every untextured
one, in the car's paint, except under nodes named `dash_...`: so every surface here
outside the cluster has a texture with alpha 0 (the car's palette or the woodgrain),
and the cluster's faces, bezels and needles sit under `dash_` nodes. The seats' pleats
are modeled: an insert laid on each cushion and back, raised into rounded ridges.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from studebaker_dash import MATERIALS, _font, _needle, _png, _polar, _text, facing_basis

## Looks the interior adds to the car's palette: (color, paint, (AO, roughness, metallic)).
LOOKS = {
    'Vinyl': ((22, 22, 24), False, (255, 140, 0)),
    'DashPad': ((19, 19, 21), False, (255, 215, 0)),
    'Headliner': ((24, 24, 27), False, (255, 225, 0)),
    'Carpet': ((14, 14, 15), False, (255, 250, 0)),
    'Rubber': ((16, 16, 16), False, (255, 180, 0)),
    'Chrome': ((240, 240, 244), False, (255, 15, 255)),
    'Brushed': ((168, 170, 176), False, (255, 80, 210)),
    'CupWall': ((30, 26, 24), False, (255, 150, 0)),
    'Knob': ((12, 12, 12), False, (255, 90, 0)),
}

## The cabin (meters): the carpet's height, the inside of the doors, the window line.
FLOOR_Y = 0.12
DOOR_X = 0.80
BELT_Y = 0.69

## The dash: where its top meets the windshield (z by x is the windshield's foot,
## measured from the model), its height, how far back its edge comes over the
## passenger's side and over the driver's cluster (the hood), and the driver's part
## across x (blended over DASH_BLEND).
DASH_TOP_Y = 0.705
DASH_EDGE_Z = 0.40
HOOD_EDGE_Z = 0.27
DASH_BLEND = (0.03, 0.10)
DASH_BOTTOM_Y = 0.42
DASH_END_X = 0.795
DASH_SECTIONS = 48

## The cluster: its panel's middle (on the steering column's line), how far it leans
## back, the pods' spacing, their faces' radius, the chrome bezel round each, how deep
## the cups go into the dash, and the panel's size.
CLUSTER_AT = (0.40, 0.575, 0.36)
CLUSTER_TILT = 12.0
POD_PITCH = 0.136
FACE_R = 0.058
BEZEL_R = 0.066
CUP_DEPTH = 0.026
PANEL_W = 4 * POD_PITCH + 0.03
PANEL_H = 0.150
POD_SEGMENTS = 48
## The knob panel at the driver's end, beside the cluster on the same plane.
KNOBS_W = 0.095

## The steering wheel: its hub, the column's lean (the wheel's top toward the dash), the
## rim's size (15 in across), the spokes, the hub cap. The column runs from behind the
## hub into the dash, ribbed where it shows.
WHEEL_AT = (0.40, 0.605, -0.02)
COLUMN_LEAN = 22.0
WHEEL_R = 7.5 * 0.0254
RIM_R = 0.0125
SPOKE_W = (0.050, 0.030)
SPOKE_T = 0.010
SPOKE_DISH = 0.045
HUB_R = 0.045
COLUMN_R = 0.034
COLUMN_LEN = 0.42
RIBS = (0.11, 0.25, 0.008)

## The seats: the buckets' middles across, the cushions' and backs' sizes and leans,
## the rear bench; the pleats' spacing.
SEAT_X = 0.40
CUSHION = dict(at=(0.0, 0.335, -0.29), half=(0.245, 0.055, 0.255), tilt=6.0)
BACK = dict(base=(0.0, 0.37, -0.53), half=(0.235, 0.33, 0.065), lean=17.0)
REAR_CUSHION = dict(at=(0.0, 0.33, -1.00), half=(0.60, 0.06, 0.24), tilt=6.0)
REAR_BACK = dict(base=(0.0, 0.37, -1.21), half=(0.58, 0.24, 0.07), lean=28.0)
PLEAT = 0.045

## Textures: the woodgrain, the dials (an atlas of four faces and the radio and heater
## panels).
WOOD_TEX = 512
DIAL_TEX = 512

INK = (236, 236, 232)
ORANGE = (236, 120, 40)
YELLOW = (230, 190, 70)
FACE = (14, 14, 16)


# ---------------------------------------------------------------------------- meshes

def smooth_normals(tris, crease=55.0):
    """Corner normals: each corner's the area-weighted sum of the normals of the faces
    that share its position and lie within `crease` degrees of its own face."""
    tris = np.asarray(tris, np.float64)
    fn = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    unit = fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-15)
    keys = np.round(tris.reshape(-1, 3) * 1e5).astype(np.int64)
    _, inverse = np.unique(keys, axis=0, return_inverse=True)
    inverse = inverse.reshape(-1)
    faces_of = {}
    for corner, v in enumerate(inverse):
        faces_of.setdefault(v, []).append(corner // 3)
    limit = math.cos(math.radians(crease))
    out = np.empty((len(tris) * 3, 3))
    for corner, v in enumerate(inverse):
        f = corner // 3
        others = faces_of[v]
        near = [g for g in others if unit[g] @ unit[f] >= limit]
        n = fn[near].sum(0)
        length = np.linalg.norm(n)
        out[corner] = n / length if length > 1e-15 else unit[f]
    return out.reshape(-1, 3, 3)


def grid_tris(points, closed_u=False):
    """Triangles over a grid of points (rows along v, columns along u)."""
    rows, cols = points.shape[:2]
    tris = []
    for j in range(rows - 1):
        for i in range(cols - (0 if closed_u else 1)):
            i1 = (i + 1) % cols
            a, b, c, d = points[j, i], points[j, i1], points[j + 1, i1], points[j + 1, i]
            tris += [[a, b, c], [a, c, d]]
    return np.array(tris)


def drop_degenerate(tris, *more):
    area = np.linalg.norm(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]), axis=1)
    keep = area > 1e-12
    return (tris[keep],) + tuple(m[keep] for m in more)


def superellipsoid(half, e=(0.3, 0.3), nu=32, nv=18):
    """A rounded box: |x/a|^(2/e2) ... a superellipsoid with half sizes `half`; latitude
    along Y. Returns (points grid (nv+1, nu+1, 3))."""
    a, b, c = half
    e1, e2 = e

    def f(w, m):
        return np.sign(w) * np.abs(w) ** m

    eta = np.linspace(-math.pi / 2, math.pi / 2, nv + 1)[:, None]
    om = np.linspace(-math.pi, math.pi, nu + 1)[None, :]
    x = a * f(np.cos(eta), e1) * f(np.cos(om), e2)
    y = b * f(np.sin(eta), e1) * np.ones_like(om)
    z = c * f(np.cos(eta), e1) * f(np.sin(om), e2)
    return np.stack([x, y, z], -1)


def rot_x(deg):
    a = math.radians(deg)
    return np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])


def blob(half, at, rot=None, e=(0.3, 0.3), nu=32, nv=18, shape=None):
    """A rounded box's triangles in the car's frame: built about its middle, reshaped by
    `shape(points)` (local), turned by `rot` and moved to `at`."""
    p = superellipsoid(half, e, nu, nv)
    if shape is not None:
        p = shape(p)
    if rot is not None:
        p = p @ rot.T
    p = p + np.asarray(at, float)
    return drop_degenerate(grid_tris(p))[0]


def prism(outline, axis_lo, axis_hi, frame):
    """A slab from a closed 2D outline (u, v), extruded from axis_lo to axis_hi along the
    frame's third axis; frame = (origin, u axis, v axis, w axis)."""
    o, eu, ev, ew = (np.asarray(f, float) for f in frame)
    pts = np.asarray(outline, float)
    lo = o + pts[:, :1] * eu + pts[:, 1:] * ev + axis_lo * ew
    hi = o + pts[:, :1] * eu + pts[:, 1:] * ev + axis_hi * ew
    n = len(pts)
    tris = []
    for i in range(n):
        j = (i + 1) % n
        tris += [[lo[i], lo[j], hi[j]], [lo[i], hi[j], hi[i]]]
    mid_lo, mid_hi = lo.mean(0), hi.mean(0)
    for i in range(n):
        j = (i + 1) % n
        tris += [[mid_hi, hi[i], hi[j]], [mid_lo, lo[j], lo[i]]]
    return np.array(tris)


def rounded_rect(w, h, r, seg=6):
    pts = []
    for cx, cy, start in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                          (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(seg + 1):
            a = math.radians(start + 90 * i / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return np.array(pts)


def tube(path, radius, n=12, cap=True):
    """A round tube along a polyline."""
    path = np.asarray(path, float)
    rings = []
    for k, p in enumerate(path):
        t = path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]
        t /= np.linalg.norm(t)
        a = np.cross(t, [0.0, 1.0, 0.0] if abs(t[1]) < 0.9 else [1.0, 0.0, 0.0])
        a /= np.linalg.norm(a)
        b = np.cross(t, a)
        ang = np.linspace(0, 2 * math.pi, n, endpoint=False)
        rings.append(p + radius * (np.cos(ang)[:, None] * a + np.sin(ang)[:, None] * b))
    tris = list(grid_tris(np.array(rings), closed_u=True))
    if cap:
        for ring, p in ((rings[0], path[0]), (rings[-1], path[-1])):
            for i in range(n):
                tris.append([p, ring[i], ring[(i + 1) % n]])
    return np.array(tris)


def revolve(profile, axis_frame, n=32):
    """A surface of revolution: profile [(r, h)] about the frame's axis;
    axis_frame = (origin, axis, across)."""
    o, ax, ac = (np.asarray(f, float) for f in axis_frame)
    ac = ac - (ac @ ax) * ax
    ac /= np.linalg.norm(ac)
    up = np.cross(ax, ac)
    ang = np.linspace(0, 2 * math.pi, n, endpoint=False)
    rows = []
    for r, h in profile:
        rows.append(o + h * ax + r * (np.cos(ang)[:, None] * ac + np.sin(ang)[:, None] * up))
    return grid_tris(np.array(rows), closed_u=True)


def planar_uv(tris, origin, eu, ev, scale_u, scale_v):
    p = tris.reshape(-1, 3) - np.asarray(origin, float)
    return np.stack([p @ np.asarray(eu, float) / scale_u, p @ np.asarray(ev, float) / scale_v], -1).reshape(-1, 3, 2)


# --------------------------------------------------------------------------- textures

def wood_texture():
    """Woodgrain: warm brown with darker streaks running along U, tiling."""
    n = WOOD_TEX
    rng = np.random.default_rng(1970)
    v = np.arange(n)[:, None] / n
    u = np.arange(n)[None, :] / n
    # Grain lines: across V, wavering slowly along U; tiled by using whole periods.
    waver = sum(rng.uniform(0.002, 0.012) * np.sin(2 * math.pi * (k * u + rng.uniform())) for k in (1, 2, 3))
    lines = sum(rng.uniform(0.3, 1.0) * np.sin(2 * math.pi * (k * (v + waver) + rng.uniform()))
                for k in (7, 13, 23, 41))
    fibre = rng.normal(0, 1, (n, 8))
    fibre = np.repeat(fibre, n // 8, axis=1)
    fibre = np.roll(np.asarray(Image.fromarray(np.uint8(np.clip(fibre * 40 + 128, 0, 255)))
                               .filter(ImageFilter.GaussianBlur(3)), float), 0, 1) / 128.0 - 1.0
    shade = 0.5 + 0.18 * np.tanh(lines) + 0.06 * fibre
    dark, light = np.array([70, 42, 24], float), np.array([168, 112, 66], float)
    rgb = dark + (light - dark) * np.clip(shade, 0, 1)[..., None]
    albedo = np.concatenate([rgb, np.zeros((n, n, 1))], -1)
    orm = np.zeros((n, n, 3))
    orm[...] = (255, 70, 0)
    return (_png(Image.fromarray(np.round(albedo).astype(np.uint8), 'RGBA')),
            _png(Image.fromarray(np.round(orm).astype(np.uint8), 'RGB')))


def _dial_base(d, c, r):
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=FACE)


def _ticks(d, c, r0, r1, start, sweep, count, width, color=INK, every=1):
    for k in range(count + 1):
        if k % every:
            continue
        deg = start + sweep * k / count
        d.line([_polar(c, r0, deg), _polar(c, r1, deg)], fill=color, width=width)


def speedo_face(d, c, r):
    _dial_base(d, c, r)
    _ticks(d, c, r * 0.80, r * 0.92, -135, 270, 75, 3)
    _ticks(d, c, r * 0.74, r * 0.92, -135, 270, 15, 6)
    for k in range(16):
        deg = -135 + 270 * k / 15
        _text(d, _polar(c, r * 0.60, deg), str(k * 10), _font(round(r * 0.13), True), INK)
    for y, label in ((-0.22, '00000'), (0.30, '000')):
        bw = r * (0.42 if len(label) == 5 else 0.26)
        box = [c[0] - bw / 2, c[1] + y * r - r * 0.07, c[0] + bw / 2, c[1] + y * r + r * 0.07]
        d.rectangle(box, fill=(4, 4, 4), outline=(90, 90, 90), width=2)
        _text(d, (c[0], c[1] + y * r), label, _font(round(r * 0.11), True), INK)
    _text(d, (c[0], c[1] + r * 0.66), 'M.P.H.', _font(round(r * 0.09), True), INK)


def tach_face(d, c, r):
    _dial_base(d, c, r)
    start = 114.0
    step = 250.0 / 7.0
    for k in range(0, 41):
        deg = start + step * k / 5
        major = k % 5 == 0
        rpm = k * 200
        color = ORANGE if rpm >= 6000 else (YELLOW if rpm >= 5000 else INK)
        d.line([_polar(c, r * (0.74 if major else 0.82), deg), _polar(c, r * 0.92, deg)], fill=color,
               width=6 if major else 3)
        if major and k:
            _text(d, _polar(c, r * 0.60, deg), str(k // 5), _font(round(r * 0.17), True), color)
    _text(d, (c[0] + r * 0.36, c[1] + r * 0.02), 'R.P.M.', _font(round(r * 0.085), True), INK)
    _text(d, (c[0] + r * 0.36, c[1] + r * 0.14), 'X 1000', _font(round(r * 0.075), True), INK)
    rr = r * 0.30
    d.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=(150, 150, 150), width=2)


def four_face(d, c, r):
    _dial_base(d, c, r)
    rr = r * 0.46
    d.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=INK, width=4)
    for mid, (lo, hi) in ((0, ('E', 'F')), (90, ('C', 'H')), (180, ('D', 'C')), (270, ('L', 'H'))):
        _ticks(d, c, r * 0.80, r * 0.92, mid - 35, 70, 4, 4)
        d.line([_polar(c, r * 0.80, mid - 35), _polar(c, r * 0.92, mid - 35)], fill=ORANGE, width=6)
        _text(d, _polar(c, r * 0.68, mid - 30), lo, _font(round(r * 0.11), True), INK)
        _text(d, _polar(c, r * 0.68, mid + 30), hi, _font(round(r * 0.11), True), INK)
    for (dx, dy), label in (((0, -0.24), 'FUEL'), ((-0.28, 0.0), 'OIL'), ((0.28, 0.0), 'TEMP'), ((0, 0.24), 'ALT')):
        _text(d, (c[0] + dx * r, c[1] + dy * r), label, _font(round(r * 0.10), True), INK)


def clock_face(d, c, r):
    _dial_base(d, c, r)
    _ticks(d, c, r * 0.84, r * 0.92, 0, 360, 60, 3)
    _ticks(d, c, r * 0.76, r * 0.92, 0, 360, 12, 6)
    for k in range(12):
        label = '△' if k == 0 else str(k * 5)
        _text(d, _polar(c, r * 0.64, k * 30), label, _font(round(r * 0.13), True), INK)
    rr = r * 0.36
    d.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=(130, 130, 130), width=2)
    for k in range(12):
        _text(d, _polar(c, r * 0.27, k * 30), str(12 if k == 0 else k), _font(round(r * 0.07), True), INK)


def dial_texture():
    """The dial atlas: four faces (2 x 2) on the left, the radio and the heater panel on the
    right. Returns (PNG, {name: (u0, v0, u1, v1)})."""
    s = DIAL_TEX
    im = Image.new('RGBA', (4 * s, 2 * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    boxes = {}
    for k, (name, draw) in enumerate((('speedo', speedo_face), ('tach', tach_face), ('four', four_face),
                                      ('clock', clock_face))):
        x0, y0 = (k % 2) * s, (k // 2) * s
        draw(d, (x0 + s / 2, y0 + s / 2), s / 2 - 2)
        boxes[name] = (x0 / (4 * s), y0 / (2 * s), (x0 + s) / (4 * s), (y0 + s) / (2 * s))
    # Radio: a chrome face, the dial window with its numbers, the push buttons.
    x0, y0, w, h = 2 * s, 0, 2 * s, s // 2
    d.rectangle([x0, y0, x0 + w, y0 + h], fill=(150, 152, 156))
    d.rectangle([x0 + w * 0.22, y0 + h * 0.18, x0 + w * 0.78, y0 + h * 0.52], fill=(20, 20, 22))
    for k, f in enumerate(('54', '6', '8', '10', '12', '14', '16')):
        _text(d, (x0 + w * (0.26 + 0.08 * k), y0 + h * 0.30), f, _font(round(h * 0.10), True), INK)
    d.line([(x0 + w * 0.47, y0 + h * 0.20), (x0 + w * 0.47, y0 + h * 0.50)], fill=ORANGE, width=4)
    _text(d, (x0 + w * 0.5, y0 + h * 0.44), 'CHRYSLER SOLID STATE', _font(round(h * 0.06), True), INK)
    for k in range(5):
        bx = x0 + w * (0.30 + 0.09 * k)
        d.rectangle([bx, y0 + h * 0.62, bx + w * 0.07, y0 + h * 0.80], fill=(200, 200, 204), outline=(60, 60, 60))
    boxes['radio'] = (x0 / (4 * s), y0 / (2 * s), (x0 + w) / (4 * s), (y0 + h) / (2 * s))
    # Heater: black with white lettering.
    x0, y0, w, h = 2 * s, s // 2, 2 * s, s // 2
    d.rectangle([x0, y0, x0 + w, y0 + h], fill=(16, 16, 18))
    for k, label in enumerate(('OFF', 'HEAT', 'DEF')):
        _text(d, (x0 + w * 0.2, y0 + h * (0.25 + 0.25 * k)), label, _font(round(h * 0.12), True), INK)
    for k, label in enumerate(('LO', 'TEMP', 'HIGH')):
        _text(d, (x0 + w * 0.6, y0 + h * (0.25 + 0.25 * k)), label, _font(round(h * 0.12), True), INK)
    d.line([(x0 + w * 0.38, y0 + h * 0.15), (x0 + w * 0.38, y0 + h * 0.85)], fill=(120, 120, 120), width=6)
    d.line([(x0 + w * 0.82, y0 + h * 0.15), (x0 + w * 0.82, y0 + h * 0.85)], fill=(120, 120, 120), width=6)
    boxes['heater'] = (x0 / (4 * s), y0 / (2 * s), (x0 + w) / (4 * s), (y0 + h) / (2 * s))
    return _png(im), boxes


# ------------------------------------------------------------------------------ parts

def outward(tris):
    """A closed (or nearly closed) mesh wound so its faces point out, by the sign of the
    volume it encloses about its middle."""
    tris = np.asarray(tris, float)
    c = tris.reshape(-1, 3).mean(0)
    vol = np.einsum('ij,ij->i', tris[:, 0] - c, np.cross(tris[:, 1] - c, tris[:, 2] - c)).sum()
    return tris[:, ::-1].copy() if vol < 0 else tris


def _part(mat, tris, uv=None, crease=55.0, closed=True):
    tris = np.asarray(tris, float)
    if closed:
        flipped = outward(tris)
        if uv is not None and flipped is not tris and not np.shares_memory(flipped, tris):
            if not np.allclose(flipped, tris):
                uv = np.asarray(uv)[:, ::-1]
        tris = flipped
    return (mat, tris, smooth_normals(tris, crease), uv)


def _smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def windshield_z(x):
    """The windshield's foot along the car (z) by x, from the model."""
    xs = [0.0, 0.45, 0.60, 0.75, 0.80]
    zs = [0.711, 0.687, 0.665, 0.597, 0.57]
    return np.interp(abs(x), xs, zs)


def dash_profile(x):
    """The dash's cross-section at x as a closed loop of (z, y), the same number of points
    everywhere: from the windshield's foot back along the top, round the edge and down
    the face (over the driver: the hood, its underside back in to the cluster panel, the
    panel's backing and the face under it), along the bottom and up the front."""
    drv = _smoothstep(DASH_BLEND[0], DASH_BLEND[1], x)
    zf = windshield_z(x) - 0.01
    tilt = math.tan(math.radians(CLUSTER_TILT))
    cz, cy = CLUSTER_AT[2], CLUSTER_AT[1]
    panel_top = cy + PANEL_H / 2
    panel_bot = cy - PANEL_H / 2
    # The panel's backing sits CUP_DEPTH + 1 cm behind its face.
    back = CUP_DEPTH + 0.012

    def backing_z(y):
        return cz + back + (y - cy) * tilt

    edge = DASH_EDGE_Z + (HOOD_EDGE_Z - DASH_EDGE_Z) * drv
    pas = [(zf, DASH_TOP_Y), (0.55, DASH_TOP_Y), (DASH_EDGE_Z + 0.03, DASH_TOP_Y - 0.002),
           (DASH_EDGE_Z + 0.006, DASH_TOP_Y - 0.010), (DASH_EDGE_Z - 0.004, DASH_TOP_Y - 0.030),
           (DASH_EDGE_Z, DASH_TOP_Y - 0.050), (DASH_EDGE_Z + 0.004, 0.62), (DASH_EDGE_Z + 0.008, 0.56),
           (DASH_EDGE_Z + 0.012, 0.50), (DASH_EDGE_Z + 0.016, 0.45), (DASH_EDGE_Z + 0.03, DASH_BOTTOM_Y),
           (0.60, DASH_BOTTOM_Y), (zf - 0.02, 0.60)]
    drv_pts = [(zf, DASH_TOP_Y), (0.55, DASH_TOP_Y + 0.004), (edge + 0.03, DASH_TOP_Y + 0.010),
               (edge + 0.004, DASH_TOP_Y + 0.002), (edge - 0.006, DASH_TOP_Y - 0.022),
               (edge + 0.002, panel_top + 0.010), (backing_z(panel_top) - 0.01, panel_top + 0.004),
               (backing_z(panel_top), panel_top - 0.004), (backing_z(cy), cy),
               (backing_z(panel_bot), panel_bot), (backing_z(panel_bot) - 0.02, DASH_BOTTOM_Y),
               (0.60, DASH_BOTTOM_Y), (zf - 0.02, 0.60)]
    return np.array([np.array(p) * (1 - drv) + np.array(q) * drv for p, q in zip(pas, drv_pts)])


def dash_parts():
    """The padded dash, the full width of the car, with its ends closed against the doors."""
    xs = np.concatenate([np.linspace(-DASH_END_X, DASH_BLEND[0], DASH_SECTIONS // 2, endpoint=False),
                         np.linspace(DASH_BLEND[0], DASH_BLEND[1], 10, endpoint=False),
                         np.linspace(DASH_BLEND[1], DASH_END_X, DASH_SECTIONS // 2)])
    rings = []
    for x in xs:
        prof = dash_profile(x)
        rings.append(np.stack([np.full(len(prof), x), prof[:, 1], prof[:, 0]], -1))
    rings = np.array(rings)
    tris = list(grid_tris(rings, closed_u=True))
    for ring in (rings[0], rings[-1]):
        mid = ring.mean(0)
        for i in range(len(ring)):
            tris.append([mid, ring[i], ring[(i + 1) % len(ring)]])
    return [_part('DashPad', np.array(tris), crease=40.0)]


def cluster_basis():
    t = math.radians(CLUSTER_TILT)
    return facing_basis((0.0, math.sin(t), -math.cos(t)))


def to_car(points, origin, basis):
    return np.asarray(points, float) @ basis.T + np.asarray(origin, float)


def pod_centers():
    """The four pods' middles in the cluster's frame (X to the driver's right), from the
    driver's left."""
    return [((k - 1.5) * POD_PITCH, 0.0) for k in range(4)]


def _ring_xz(r, y, n=POD_SEGMENTS):
    a = np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.stack([r * np.cos(a), np.full(n, y), r * np.sin(a)], -1)


def panel_with_holes(width, height, centers, hole_r, n=POD_SEGMENTS):
    """The cluster's woodgrain panel (X-Z plane at y = 0, facing -Y) with a round hole
    at each center: each pod's cell is a ring from its hole out to the cell's edges; the
    margins at the ends are plain strips."""
    tris = []
    half_h = height / 2
    xs = [c[0] for c in centers]
    for k, (cx, cz) in enumerate(centers):
        x0 = cx - POD_PITCH / 2 if k else -width / 2
        x1 = cx + POD_PITCH / 2 if k < len(centers) - 1 else width / 2
        a = np.linspace(0, 2 * math.pi, n, endpoint=False)
        hole = np.stack([cx + hole_r * np.cos(a), cz + hole_r * np.sin(a)], -1)
        outer = []
        for ang in a:
            dx, dz = math.cos(ang), math.sin(ang)
            tx = ((x1 - cx) / dx if dx > 1e-9 else (x0 - cx) / dx if dx < -1e-9 else 1e9)
            tz = ((half_h - cz) / dz if dz > 1e-9 else (-half_h - cz) / dz if dz < -1e-9 else 1e9)
            t = min(tx, tz)
            outer.append((cx + dx * t, cz + dz * t))
        outer = np.array(outer)
        # The cell's corners, so the ring reaches them.
        corners = [(x1, half_h), (x0, half_h), (x0, -half_h), (x1, -half_h)]
        for i in range(n):
            j = (i + 1) % n
            p = [(hole[i][0], 0.0, hole[i][1]), (hole[j][0], 0.0, hole[j][1]),
                 (outer[j][0], 0.0, outer[j][1]), (outer[i][0], 0.0, outer[i][1])]
            tris += [[p[0], p[2], p[1]], [p[0], p[3], p[2]]]
        for (qx, qz) in corners:
            ang = math.atan2(qz - cz, qx - cx) % (2 * math.pi)
            i = int(ang / (2 * math.pi) * n) % n
            j = (i + 1) % n
            tris.append([(outer[i][0], 0.0, outer[i][1]), (qx, 0.0, qz), (outer[j][0], 0.0, outer[j][1])])
    del xs
    tris = np.array(tris, float)
    # Facing -Y: wind them so.
    fn = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    flip = fn[:, 1] > 0
    tris[flip] = tris[flip][:, ::-1]
    return tris


def cluster_parts():
    """The cluster in its own frame: [(material, tris, normals, uv)] fixed under the
    `dash_` node; the pods' needles; and the panel (woodgrain, in the body)."""
    centers = pod_centers()
    _, boxes = dial_texture()
    fixed = []
    for (cx, cz), name in zip(centers, ('speedo', 'tach', 'four', 'clock')):
        off = np.array([cx, 0.0, cz])
        # The cup: a wall from the bezel back to the face.
        wall = []
        a0 = _ring_xz(FACE_R + 0.002, -0.001) + off
        a1 = _ring_xz(FACE_R, CUP_DEPTH) + off
        for i in range(POD_SEGMENTS):
            j = (i + 1) % POD_SEGMENTS
            wall += [[a0[i], a1[i], a1[j]], [a0[i], a1[j], a0[j]]]
        wall = np.array(wall)
        radial = wall - off
        radial[..., 1] = 0.0
        fixed.append(('cup', wall, -radial / np.linalg.norm(radial, axis=-1, keepdims=True), None))
        # The face at the cup's bottom, facing -Y, with its UVs in the atlas.
        ring = _ring_xz(FACE_R, CUP_DEPTH) + off
        face = np.array([[off + [0, CUP_DEPTH, 0], ring[(i + 1) % POD_SEGMENTS], ring[i]] for i in range(POD_SEGMENTS)])
        u0, v0, u1, v1 = boxes[name]
        uv = np.stack([u0 + (face[..., 0] - cx + FACE_R) / (2 * FACE_R) * (u1 - u0),
                       v0 + (cz + FACE_R - face[..., 2]) / (2 * FACE_R) * (v1 - v0)], -1)
        fixed.append(('face', face, np.full_like(face, 0.0) + [0, -1, 0], uv))
        # The chrome bezel: a rounded ring standing out from the panel.
        prof = [(BEZEL_R, 0.0), (BEZEL_R - 0.001, -0.0035), (BEZEL_R - 0.004, -0.0045),
                (FACE_R + 0.002, -0.002), (FACE_R + 0.002, 0.001)]
        bez = revolve([(r, h) for r, h in prof], (off, (0, -1, 0), (1, 0, 0)), POD_SEGMENTS)
        fixed.append(('bezel', bez, smooth_normals(bez, 70.0), None))
    # The four-in-one's raised middle, over the small needles' pivots.
    cx, cz = centers[2]
    inner = 0.46 * FACE_R
    disc_y = CUP_DEPTH - 0.004
    ring = _ring_xz(inner, disc_y) + [cx, 0, cz]
    disc = np.array([[[cx, disc_y, cz], ring[(i + 1) % POD_SEGMENTS], ring[i]] for i in range(POD_SEGMENTS)])
    u0, v0, u1, v1 = boxes['four']
    uv = np.stack([u0 + (disc[..., 0] - cx + FACE_R) / (2 * FACE_R) * (u1 - u0),
                   v0 + (cz + FACE_R - disc[..., 2]) / (2 * FACE_R) * (v1 - v0)], -1)
    fixed.append(('face', disc, np.full_like(disc, 0.0) + [0, -1, 0], uv))
    side = []
    r0 = _ring_xz(inner, disc_y) + [cx, 0, cz]
    r1 = _ring_xz(inner, CUP_DEPTH) + [cx, 0, cz]
    for i in range(POD_SEGMENTS):
        j = (i + 1) % POD_SEGMENTS
        side += [[r0[i], r1[j], r1[i]], [r0[i], r0[j], r1[j]]]
    side = np.array(side)
    radial = side - [cx, 0, cz]
    radial[..., 1] = 0.0
    fixed.append(('cup', side, radial / np.linalg.norm(radial, axis=-1, keepdims=True), None))
    # The small needles that stay put (oil, temperature, ammeter), from the middle out.
    for rest in (-90.0 + 10, 90.0 - 15, 180.0):
        t, n = _needle(FACE_R * 0.88, 0.0, 0.0024, rest, CUP_DEPTH - 0.002)
        fixed.append(('needle', t + [cx, 0, cz], n, None))
    # The clock's hands, ten past ten, and its second hand.
    cx, cz = centers[3]
    for length, width, rest, y in ((FACE_R * 0.55, 0.0032, -60.0, CUP_DEPTH - 0.003),
                                   (FACE_R * 0.80, 0.0026, 60.0, CUP_DEPTH - 0.0035),
                                   (FACE_R * 0.86, 0.0010, 160.0, CUP_DEPTH - 0.004)):
        t, n = _needle(length, length * 0.15, width, rest, y)
        fixed.append(('needle' if width < 0.002 else 'pointer', t + [cx, 0, cz], n, None))
    caps = []
    for (cx, cz), r in zip(centers, (0.007, 0.007, 0.0, 0.005)):
        if r:
            ring = _ring_xz(r, CUP_DEPTH - 0.005, 16) + [cx, 0, cz]
            caps += [[[cx, CUP_DEPTH - 0.0055, cz], ring[(i + 1) % 16], ring[i]] for i in range(16)]
    caps = np.array(caps)
    fixed.append(('cap', caps, np.full_like(caps, 0.0) + [0, -1, 0], None))
    # The moving needles, each in its pod's frame.
    speedo = _needle(FACE_R * 0.90, FACE_R * 0.15, 0.0034, -135.0, CUP_DEPTH - 0.003)
    tach = _needle(FACE_R * 0.90, FACE_R * 0.15, 0.0034, 114.0, CUP_DEPTH - 0.003)
    fuel = _needle(FACE_R * 0.88, 0.0, 0.0024, 35.0, CUP_DEPTH - 0.002)
    panel = panel_with_holes(PANEL_W, PANEL_H, centers, BEZEL_R - 0.002)
    return {'fixed': fixed, 'speedo': speedo, 'tach': tach, 'fuel': fuel, 'panel': panel, 'centers': centers}


def knob_panel():
    """The woodgrain strip of four knobs at the driver's end of the cluster, in the
    cluster's frame, and its knobs: (panel tris, knob parts)."""
    x0 = -PANEL_W / 2 - KNOBS_W
    x1 = -PANEL_W / 2
    h = PANEL_H / 2
    panel = np.array([[(x0, 0, -h), (x1, 0, h), (x1, 0, -h)], [(x0, 0, -h), (x0, 0, h), (x1, 0, h)]], float)
    knobs = []
    for kx, kz in ((x0 + 0.03, 0.035), (x0 + 0.068, 0.035), (x0 + 0.03, -0.03), (x0 + 0.068, -0.03)):
        knobs.append(revolve([(0.0, -0.022), (0.011, -0.022), (0.012, -0.018), (0.012, 0.0)],
                             ((kx, 0.0, kz), (0, -1, 0), (1, 0, 0)), 16))
    return panel, np.concatenate(knobs)


def wheel_parts():
    """The steering wheel in its own frame (+Z down the column into the dash, +X to the
    driver's left, +Y up): [(material, tris, normals, uv)]: the woodgrain rim, three black spokes
    (at 3, 9 and 6 o'clock) with a brushed inlay, the black hub."""
    parts = []
    # Rim: a torus, its UV along the rim so the grain runs round it.
    n, m = 72, 14
    R = WHEEL_R - RIM_R
    pts = np.zeros((m + 1, n + 1, 3))
    uv = np.zeros((m + 1, n + 1, 2))
    for i in range(n + 1):
        a = 2 * math.pi * i / n
        ring = np.array([math.cos(a), math.sin(a), 0.0])
        for j in range(m + 1):
            b = 2 * math.pi * j / m
            pts[j, i] = ring * (R + RIM_R * math.cos(b)) + np.array([0, 0, RIM_R * math.sin(b) * 1.15])
            uv[j, i] = (i / n * 6.0, j / m * 0.25)
    rim = grid_tris(pts)
    rim_uv = grid_tris(np.concatenate([uv, np.zeros((m + 1, n + 1, 1))], -1))[..., :2]
    parts.append(_part('wood', rim, rim_uv, crease=80.0))
    # Spokes: flat tapered bars from the hub to the rim, dished toward the column.
    spokes, inlays = [], []
    for ang in (0.0, 180.0, 270.0):
        a = math.radians(ang)
        along = np.array([math.cos(a), math.sin(a), 0.0])
        side = np.array([-math.sin(a), math.cos(a), 0.0])
        r0, r1 = HUB_R * 0.8, R - RIM_R * 0.4
        z0, z1 = SPOKE_DISH, 0.0
        w0, w1 = SPOKE_W
        outline = []
        for r, z, w in ((r0, z0, w0), (r1, z1, w1)):
            outline.append((r, z, w))
        corners = []
        for (r, z, w) in outline:
            for s in (-1, 1):
                for t in (-1, 1):
                    corners.append(along * r + side * s * w / 2 + np.array([0, 0, z + t * SPOKE_T / 2]))
        c = corners
        quads = [(c[0], c[2], c[6], c[4]), (c[1], c[5], c[7], c[3]), (c[0], c[4], c[5], c[1]), (c[2], c[3], c[7], c[6])]
        mid = np.mean(c, 0)
        for q in quads:
            q = [np.asarray(p) for p in q]
            nn = np.cross(q[1] - q[0], q[2] - q[0])
            if nn @ (np.mean(q, 0) - mid) < 0:
                q = q[::-1]
            spokes += [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]
        # The inlay: a brushed strip down the spoke's face (toward the driver, -Z).
        inl = []
        for (r, z, w) in outline:
            for s in (-1, 1):
                inl.append(along * r + side * s * w * 0.32 + np.array([0, 0, z - SPOKE_T / 2 - 0.0008]))
        inlays += [[inl[0], inl[2], inl[3]], [inl[0], inl[3], inl[1]]]
    parts.append(_part('Knob', np.array(spokes), crease=40.0, closed=False))
    parts.append(_part('Brushed', np.array(inlays), closed=False))
    # Hub: a short cone back to the column and a black cap toward the driver.
    hub = revolve([(0.0, SPOKE_DISH - 0.018), (HUB_R * 0.7, SPOKE_DISH - 0.016), (HUB_R, SPOKE_DISH - 0.006),
                   (HUB_R, SPOKE_DISH + 0.01), (HUB_R * 0.8, SPOKE_DISH + 0.05), (COLUMN_R * 0.9, SPOKE_DISH + 0.06)],
                  ((0, 0, 0), (0, 0, 1), (1, 0, 0)), 32)
    parts.append(_part('Knob', hub, crease=60.0))
    return parts


def wheel_frame():
    """The steering wheel's hub and its frame's axes in the car (columns X, Y, Z)."""
    lean = math.radians(COLUMN_LEAN)
    axis = np.array([0.0, -math.sin(lean), math.cos(lean)])
    across = np.array([1.0, 0.0, 0.0])
    up = np.cross(axis, across)
    return np.asarray(WHEEL_AT, float), np.stack([across, up, axis], 1)


def column_parts():
    """The steering column from behind the hub into the dash: ribbed (the collapsible
    column's cover) near the wheel, plain further in."""
    hub, basis = wheel_frame()
    axis = basis[:, 2]
    rib0, rib1, pitch = RIBS
    prof = [(COLUMN_R * 0.9, SPOKE_DISH + 0.055)]
    h = rib0
    while h < rib1:
        prof += [(COLUMN_R, h), (COLUMN_R * 0.88, h + pitch / 2)]
        h += pitch
    prof += [(COLUMN_R * 0.9, rib1 + 0.01), (COLUMN_R * 0.9, COLUMN_LEN)]
    tris = revolve(prof, (hub, axis, (1, 0, 0)), 24)
    return [_part('Brushed', tris, crease=80.0)]


def surface_height(u, w, half_u, half_w, half_t, e=(0.3, 0.3)):
    """How far a superellipsoid's surface stands out along its thin axis at in-plane point
    (u, w): half sizes half_u, half_w in the plane, half_t along the thin axis. The
    latitude axis of superellipsoid() is the w axis here when the thin axis is not Y, so
    e is (across the latitude, along it)."""
    e1, e2 = e
    q = np.abs(u / half_u) ** (2 / e2) + np.abs(w / half_w) ** (2 / e2)
    return half_t * np.clip(1.0 - q ** (e2 / e1), 0.0, 1.0) ** (e1 / 2)


def pleated_insert(cols, span_u, span_w, height):
    """A grid of points over (u, w) in the insert's span with `height(u, w)` the surface
    under it, raised into rounded pleats running along u, one every PLEAT along w.
    Returns points (rows, cols, 3) as (u, w, height)."""
    u = np.linspace(span_u[0], span_u[1], cols)
    n_pleats = max(1, int(round((span_w[1] - span_w[0]) / PLEAT)))
    w = np.linspace(span_w[0], span_w[1], n_pleats * 4 + 1)
    U, W = np.meshgrid(u, w)
    frac = (W - span_w[0]) / (span_w[1] - span_w[0]) * n_pleats
    rise = 0.0025 + 0.0065 * np.sin(math.pi * (frac % 1.0)) ** 0.6
    # The insert's edges tuck into the surface.
    edge = np.minimum(_smoothstep(0, 0.012, U - span_u[0]), _smoothstep(0, 0.012, span_u[1] - U))
    return np.stack([U, W, height(U, W) + rise * edge], -1)


def seat_parts(x):
    """A high-back bucket at x: the cushion with its bolsters raised at the sides, on a
    black base; the back, its top narrowing into the headrest; each with a pleated insert
    (pleats across) laid on it."""
    parts = []
    c = CUSHION
    hx, hy, hz = c['half']
    e = (0.35, 0.3)

    def raise_top(xx, yy, zz):
        top = _smoothstep(-0.2 * hy, 0.8 * hy, yy)
        bol = _smoothstep(hx * 0.62, hx * 0.92, np.abs(xx))
        return top * (0.028 * bol + 0.010 * (zz / hz))

    def cushion_shape(p):
        p = p.copy()
        p[..., 1] += raise_top(p[..., 0], p[..., 1], p[..., 2])
        return p

    tilt = rot_x(-c['tilt'])
    at = np.array(c['at']) + [x, 0, 0]
    parts.append(_part('Vinyl', blob(c['half'], at, tilt, e, 36, 16, cushion_shape), crease=70.0))
    parts.append(_part('Vinyl', blob((hx * 0.85, 0.08, hz * 0.8), at + [0, -0.11, -0.02], None, (0.3, 0.3), 20, 10)))

    def cushion_top(u, w):
        y = surface_height(u, w, hx, hz, hy, (e[0], e[1]))
        return y + raise_top(u, y, w)

    g = pleated_insert(14, (-hx * 0.6, hx * 0.6), (-hz * 0.85, hz * 0.82), cushion_top)
    local = np.stack([g[..., 0], g[..., 2], g[..., 1]], -1)
    parts.append(_part('Vinyl', grid_tris(local @ tilt.T + at)[:, ::-1], crease=50.0, closed=False))

    b = BACK
    bx, by, bz = b['half']

    def narrow(yy):
        return 1.0 - 0.20 * _smoothstep(0.62, 1.0, (yy + by) / (2 * by))

    def bolster(xx, yy, zz):
        front = _smoothstep(-0.2 * bz, 0.8 * bz, zz)
        bol = _smoothstep(bx * 0.6, bx * 0.92, np.abs(xx))
        return front * 0.03 * bol * (1 - _smoothstep(0.65, 0.85, (yy + by) / (2 * by)))

    def back_shape(p):
        p = p.copy()
        p[..., 0] *= narrow(p[..., 1])
        p[..., 2] += bolster(p[..., 0], p[..., 1], p[..., 2])
        return p

    lean = rot_x(-b['lean'])
    base = np.array(b['base']) + [x, 0, 0]
    center = base + lean @ np.array([0, by, 0])
    parts.append(_part('Vinyl', blob(b['half'], center, lean, (0.3, 0.3), 36, 24, back_shape), crease=70.0))

    def back_front(u, w):
        # u across (already narrowed), w up the back.
        k = narrow(w)
        return surface_height(u / k, w, bx, by, bz, (0.3, 0.3))

    g = pleated_insert(14, (-bx * 0.58, bx * 0.58), (-by * 0.80, by * 0.86), back_front)
    g[..., 0] *= narrow(g[..., 1])
    local = np.stack([g[..., 0], g[..., 1], g[..., 2]], -1)
    parts.append(_part('Vinyl', grid_tris(local @ lean.T + center), crease=50.0, closed=False))
    return parts


def rear_seat_parts():
    parts = []
    c = REAR_CUSHION
    hx, hy, hz = c['half']
    e = (0.35, 0.3)
    tilt = rot_x(-c['tilt'])
    at = np.array(c['at'])
    parts.append(_part('Vinyl', blob(c['half'], at, tilt, e, 48, 16), crease=70.0))
    g = pleated_insert(24, (-hx * 0.78, hx * 0.78), (-hz * 0.85, hz * 0.82),
                       lambda u, w: surface_height(u, w, hx, hz, hy, e))
    local = np.stack([g[..., 0], g[..., 2], g[..., 1]], -1)
    parts.append(_part('Vinyl', grid_tris(local @ tilt.T + at)[:, ::-1], crease=50.0, closed=False))
    b = REAR_BACK
    bx, by, bz = b['half']
    lean = rot_x(-b['lean'])
    center = np.array(b['base']) + lean @ np.array([0, by, 0])
    parts.append(_part('Vinyl', blob(b['half'], center, lean, (0.3, 0.3), 48, 18), crease=70.0))
    g = pleated_insert(24, (-bx * 0.78, bx * 0.78), (-by * 0.80, by * 0.82),
                       lambda u, w: surface_height(u, w, bx, by, bz, (0.3, 0.3)))
    parts.append(_part('Vinyl', grid_tris(g @ lean.T + center), crease=50.0, closed=False))
    # The package shelf under the back window, and the wheel housings beside the seat.
    shelf = prism(rounded_rect(1.32, 0.14, 0.01), -0.012, 0.012,
                  ((0, 0.815, -1.405), (1, 0, 0), (0, 0, 1), (0, 1, 0)))
    parts.append(_part('Vinyl', shelf, crease=40.0))
    for s in (-1, 1):
        parts.append(_part('Vinyl', blob((0.075, 0.20, 0.30), (s * 0.69, 0.30, -1.22), None, (0.4, 0.4), 16, 10)))
    return parts


def floor_y(x, z):
    """The carpet's height: the floor, the tunnel down the middle (taller in front), the
    toe boards rising to the firewall, the sills."""
    ax = np.abs(x)
    tunnel_h = np.interp(z, [-1.3, -0.6, 0.0, 0.6], [0.06, 0.12, 0.17, 0.20])
    tunnel = tunnel_h * (1 - _smoothstep(0.12, 0.24, ax))
    toe = np.clip(z - 0.52, 0, None) * 1.2
    sill = 0.04 * _smoothstep(0.74, 0.79, ax)
    rear = 0.06 * _smoothstep(-0.70, -0.80, z)
    return FLOOR_Y + np.maximum(tunnel, 0) + toe + sill + rear


def floor_parts():
    xs = np.linspace(-DOOR_X, DOOR_X, 49)
    zs = np.linspace(-1.36, 0.78, 61)
    X, Z = np.meshgrid(xs, zs)
    pts = np.stack([X, floor_y(X, Z), Z], -1)
    tris = grid_tris(pts)
    fn = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    tris[fn[:, 1] < 0] = tris[fn[:, 1] < 0][:, ::-1]
    parts = [_part('Carpet', tris, crease=80.0, closed=False)]
    # The firewall above the toe boards, up to the dash, and the kick panels at the sides.
    fw_y = floor_y(0.0, 0.78)
    wall = prism(rounded_rect(2 * DOOR_X, 0.10, 0.0, 1), -0.005, 0.005,
                 ((0, (fw_y + DASH_BOTTOM_Y) / 2 + 0.02, 0.79), (1, 0, 0), (0, 1, 0), (0, 0, 1)))
    parts.append(_part('Carpet', wall, crease=40.0))
    for s in (-1, 1):
        kick = np.array([[(s * DOOR_X, FLOOR_Y, 0.70), (s * DOOR_X, FLOOR_Y, 0.80), (s * DOOR_X, 0.48, 0.80)],
                         [(s * DOOR_X, FLOOR_Y, 0.70), (s * DOOR_X, 0.48, 0.80), (s * DOOR_X, 0.48, 0.70)]])
        parts.append(_part('Vinyl', kick, closed=False))
    return parts


def door_parts(s):
    """The door's inside on side s (+1 the driver's): the trim panel, its window sill,
    the armrest, the woodgrain insert, the handle; and the quarter trim behind the door."""
    parts = []
    x = s * DOOR_X
    frame = ((x, 0.0, 0.0), (0, 0, 1), (0, 1, 0), (-s, 0, 0))
    panel = rounded_rect(1.36, BELT_Y - 0.14, 0.03)
    panel = panel + [0.02, (BELT_Y + 0.14) / 2]
    parts.append(_part('Vinyl', prism(panel, 0.0, 0.025, frame), crease=40.0))
    sill = rounded_rect(1.36, 0.06, 0.02) + [0.02, BELT_Y - 0.01]
    parts.append(_part('DashPad', prism(sill, 0.0, 0.05, frame), crease=40.0))
    arm = blob((0.03, 0.028, 0.23), (x - s * 0.055, 0.40, -0.05), None, (0.4, 0.4), 16, 10)
    parts.append(_part('Vinyl', arm))
    insert = rounded_rect(0.80, 0.11, 0.012) + [-0.05, 0.545]
    wood = prism(insert, 0.025, 0.031, frame)
    parts.append(_part('wood', wood, planar_uv(wood, (x, 0.49, -0.45), (0, 0, 1), (0, 1, 0), 0.8, 0.8), crease=40.0))
    handle = prism(rounded_rect(0.09, 0.022, 0.008), 0.025, 0.045,
                   ((x, 0.47, 0.43), (0, 0, 1), (0, 1, 0), (-s, 0, 0)))
    parts.append(_part('Chrome', handle, crease=40.0))
    quarter = rounded_rect(0.66, BELT_Y - 0.14, 0.03) + [-1.02, (BELT_Y + 0.14) / 2]
    qframe = ((s * 0.77, 0.0, 0.0), (0, 0, 1), (0, 1, 0), (-s, 0, 0))
    parts.append(_part('Vinyl', prism(quarter, 0.0, 0.02, qframe), crease=40.0))
    qsill = rounded_rect(0.66, 0.05, 0.02) + [-1.02, BELT_Y - 0.005]
    parts.append(_part('DashPad', prism(qsill, -0.02, 0.04, qframe), crease=40.0))
    return parts


def pedal_parts():
    parts = []
    for px, w, h, top in ((0.52, 0.085, 0.065, 0.27), (0.35, 0.085, 0.065, 0.27), (0.20, 0.050, 0.11, 0.25)):
        pad = blob((w / 2, h / 2, 0.012), (px, top, 0.53), rot_x(30.0), (0.4, 0.4), 12, 8)
        parts.append(_part('Rubber', pad))
        if top > 0.26:
            parts.append(_part('Brushed', tube([(px, top + 0.02, 0.545), (px, 0.36, 0.58), (px, DASH_BOTTOM_Y + 0.01, 0.56)],
                                               0.006, 8)))
        else:
            parts.append(_part('Brushed', tube([(px, top + 0.05, 0.55), (px, DASH_BOTTOM_Y + 0.01, 0.58)], 0.005, 8)))
    return parts


def shifter_parts():
    """The four-speed's pistol grip on a chrome stick, out of a rubber boot on the tunnel."""
    at = np.array([0.03, floor_y(0.03, -0.02), -0.02])
    prof = [(0.075, 0.0)]
    for k in range(8):
        prof += [(0.068 - 0.005 * k, 0.012 + 0.012 * k), (0.060 - 0.005 * k, 0.018 + 0.012 * k)]
    prof += [(0.016, 0.11), (0.0, 0.112)]
    boot = revolve(prof, (at, (0, 1, 0), (1, 0, 0)), 24)
    parts = [_part('Rubber', boot, crease=80.0)]
    top = at + [0.0, 0.24, -0.04]
    parts.append(_part('Chrome', tube([at + [0, 0.10, 0], at + [0, 0.18, -0.01], top], 0.008, 10)))
    grip = blob((0.016, 0.055, 0.028), top + [0, 0.035, -0.012], rot_x(-28.0), (0.5, 0.5), 14, 10)
    parts.append(_part('wood', grip, planar_uv(grip, top, (0, 1, 0), (0, 0, 1), 0.3, 0.3)))
    return parts


def extras_parts():
    """The rear-view mirror at the top of the windshield and the sun visors."""
    parts = []
    parts.append(_part('Chrome', tube([(0.0, 1.03, 0.30), (0.0, 0.985, 0.285)], 0.006, 8)))
    mirror = blob((0.11, 0.032, 0.014), (0.0, 0.965, 0.27), rot_x(8.0), (0.3, 0.3), 16, 8)
    parts.append(_part('Knob', mirror))
    glass = np.array([[(-0.10, 0.94, 0.255), (0.10, 0.99, 0.262), (0.10, 0.94, 0.255)],
                      [(-0.10, 0.94, 0.255), (-0.10, 0.99, 0.262), (0.10, 0.99, 0.262)]])
    parts.append(_part('Chrome', glass, closed=False))
    for s in (-1, 1):
        visor = blob((0.17, 0.008, 0.075), (s * 0.36, 1.035, 0.20), rot_x(-12.0), (0.3, 0.3), 16, 6)
        parts.append(_part('Vinyl', visor))
    return parts


def interior_parts():
    """Everything fixed in the body: [(material, tris, normals, uv or None)], car frame."""
    parts = []
    parts += dash_parts()
    parts += floor_parts()
    for s in (-1, 1):
        parts += seat_parts(s * SEAT_X)
        parts += door_parts(s)
    parts += rear_seat_parts()
    parts += pedal_parts()
    parts += shifter_parts()
    parts += column_parts()
    parts += extras_parts()
    # The cluster's woodgrain panel and the knob strip, in the body.
    origin, basis = np.asarray(CLUSTER_AT, float), cluster_basis()
    cl = cluster_parts()
    panel = to_car(cl['panel'], origin, basis)
    kp, knobs = knob_panel()
    for tris in (panel, to_car(kp, origin, basis)):
        uv = planar_uv(tris, origin, basis[:, 0], basis[:, 2], 0.5, 0.5)
        parts.append(_part('wood', tris, uv, crease=30.0))
    parts.append(_part('Knob', to_car(knobs, origin, basis), crease=70.0))
    # The radio under the clock and the heater controls under the speedometer, on the dash's
    # face under the cluster.
    return parts


def lower_face_quads():
    """The radio and heater faces under the cluster: [(atlas box name, tris (2,3,3), uv)]."""
    out = []
    origin, basis = np.asarray(CLUSTER_AT, float), cluster_basis()
    tilt = math.tan(math.radians(CLUSTER_TILT))
    for name, cx, w, h, y in (('radio', 0.17, 0.17, 0.045, -0.115), ('heater', -0.24, 0.14, 0.05, -0.115)):
        x0, x1, z0, z1 = cx - w / 2, cx + w / 2, y - h / 2, y + h / 2
        depth = CUP_DEPTH + 0.012 - 0.002 + (y) * 0.0 * tilt
        q = np.array([[(x0, depth, z0), (x1, depth, z1), (x1, depth, z0)],
                      [(x0, depth, z0), (x0, depth, z1), (x1, depth, z1)]])
        uv = np.stack([(q[..., 0] - x0) / w, (z1 - q[..., 2]) / h], -1)
        out.append((name, to_car(q, origin, basis), uv))
    return out
