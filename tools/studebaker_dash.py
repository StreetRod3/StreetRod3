"""The 1950 Studebaker Champion's instrument cluster and an add-on tachometer.

Used by tools/studebaker_to_glb.py. Reference: page 5 of "Your 1952 Champion Owner's
Guide" (reference/cars/50studebaker): a wide chrome-framed cluster with a ribbed face, a
half-moon speedometer in the middle with its needle pivoting at the bottom over the
odometer, and four small gauges in the corners (gasoline, ammeter, oil, heat). The look
follows the photos in that folder: slanted white numerals every 20 mph on a black band, a
cream dome with the odometer, the small gauges in black windows with their names printed
outside them, and a round clock in a winged chrome pod over the steering column. The
real dials ran to 100 or 140; this one runs to 160 because the game's needle does.

The car had no tachometer; it gets an accessory one, a 2-5/8 in gauge in a tapered cup
clamped on top of the cluster's hood, as they were added at the time. The windshield
comes down low and close in this car, so the cup sits at the front of the hood, clear of
the glass.

The pods follow the other cars' dashes (the '56 Corvette's): a pod node holds a
`_bezel` mesh, a `_face` mesh and the needle node. In the pod's frame the face lies in
the X-Z plane facing -Y, +X to the driver's right and +Z up; the game turns a needle
about the pod's +Y from where it rests, which is clockwise as the driver sees it. The
speedometer pod's name says `arch_160`, so its needle sweeps 160 degrees for 0-160 mph;
the tachometer's sweeps the default 250 degrees for 0-7000 rpm.
"""
import io
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-BoldOblique.ttf'
FONT_PLAIN = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'

WHITE = (236, 233, 222)
CREAM = (222, 204, 158)
CREAM_DARK = (176, 156, 110)
CHROME = (168, 170, 176)

## Cluster face, meters. The pivot of the speedometer needle is the pod's origin.
CLUSTER_W = 0.38
CLUSTER_H = 0.1133
CLUSTER_PIVOT_UP = 0.0093
## The frame narrows toward the top and has big round top corners, as on the real car.
## Each side leans in about 12 degrees, as in the photos and the owner's guide drawing,
## and the bottom corners come down square onto the rail.
CLUSTER_TAPER = 0.024
CLUSTER_TOP_RADIUS = 0.028
CLUSTER_BOTTOM_RADIUS = 0.002
## The chrome frame round the face: thicker across the top than down the sides.
FRAME_SIDE = 0.007
FRAME_TOP = 0.012
## The chrome rail along the whole bottom of the cluster, which the clock pod sits on.
RAIL_DOWN = 0.009
RAIL_UP = 0.006
RAIL_OUT = 0.016
CLUSTER_TEX = (1716, 512)
SPEEDO_SWEEP = 160.0
SPEEDO_NEEDLE = 0.080

## The small gauges' windows in the cluster texture, pixels: size, the GAS window's top
## left corner, and how far in from each end the E and F marks sit.
GAUGE_SIZE = (200, 72)
GAS_AT = (125, 300)
GAUGE_INSET = 35

## The clock pod: the clock's face radius and how far each chrome wing reaches.
CLOCK_R = 0.024
CLOCK_WING = 0.110
## Where the rail is, measured from the clock's middle (the clock sits a little above it).
CLOCK_RAIL_TOP = -0.0073
CLOCK_RAIL_BOTTOM = -0.0223
CLOCK_TEX = 256

TACH_R = 0.0285
## The tapered cup behind the tachometer, and the clamp from it down onto the hood.
TACH_CUP_DEPTH = 0.034
TACH_CUP_BACK_R = 0.021
TACH_CLAMP_DROP = 0.040
TACH_TEX = 512
TACH_SWEEP = 250.0
TACH_NEEDLE = 0.024

MATERIALS = {
    # The same looks as the other cars' dashes.
    'bezel': {'name': 'dash_bezel_mat', 'doubleSided': True,
              'pbrMetallicRoughness': {'baseColorFactor': [0.48, 0.51, 0.55, 1.0],
                                       'metallicFactor': 0.88, 'roughnessFactor': 0.24}},
    'needle': {'name': 'dash_needle_mat', 'doubleSided': True,
               'emissiveFactor': [0.665, 0.175, 0.084],
               'pbrMetallicRoughness': {'baseColorFactor': [0.95, 0.25, 0.12, 1.0],
                                        'metallicFactor': 0.0, 'roughnessFactor': 0.35}},
    'pointer': {'name': 'dash_pointer_mat', 'doubleSided': True,
                'emissiveFactor': [0.45, 0.45, 0.45],
                'pbrMetallicRoughness': {'baseColorFactor': [0.94, 0.94, 0.94, 1.0],
                                         'metallicFactor': 0.0, 'roughnessFactor': 0.4}},
    'cap': {'name': 'dash_cap_mat', 'doubleSided': True,
            'pbrMetallicRoughness': {'baseColorFactor': [0.12, 0.12, 0.14, 1.0],
                                     'metallicFactor': 0.7, 'roughnessFactor': 0.3}},
}


def _font(size, plain=False):
    return ImageFont.truetype(FONT_PLAIN if plain else FONT, size)


def _png(im):
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def _polar(center, r, deg):
    """Image point at `deg` clockwise from straight up."""
    a = math.radians(deg)
    return center[0] + r * math.sin(a), center[1] - r * math.cos(a)


def _text(draw, xy, s, font, fill):
    draw.text(xy, s, font=font, fill=fill, anchor='mm')


def _small_gauge(draw, box, marks, label, needle_at, label_below):
    """A corner gauge: a black window with a short straight scale and a pointer that stays
    put, its name printed on the face outside the window."""
    x0, y0, x1, y1 = box
    draw.rounded_rectangle(box, (y1 - y0) // 2, fill=(6, 6, 8), outline=CHROME, width=4)
    cy = (y0 + y1) / 2 + 6
    span = (x1 - x0) - 2 * GAUGE_INSET
    for i, m in enumerate(marks):
        x = x0 + GAUGE_INSET + span * i / (len(marks) - 1)
        _text(draw, (x, cy), m, _font(34), WHITE)
    for i in range(len(marks) * 2 - 1):
        x = x0 + GAUGE_INSET + span * i / (2 * (len(marks) - 1))
        draw.line([(x, y0 + 8), (x, y0 + 16)], fill=WHITE, width=3)
    if needle_at is not None:
        x = x0 + GAUGE_INSET + span * needle_at
        draw.line([(x, y0 + 10), (x, y1 - 10)], fill=(240, 240, 240), width=5)
    ly = y1 + 22 if label_below else y0 - 22
    _text(draw, ((x0 + x1) / 2, ly), label, _font(24, True), WHITE)


def cluster_texture():
    w, h = CLUSTER_TEX
    im = Image.new('RGB', (w, h), (20, 20, 24))
    d = ImageDraw.Draw(im)
    # The ribbed face.
    for y in range(0, h, 10):
        d.rectangle([0, y, w, y + 2], fill=(46, 46, 52))
    px = w / CLUSTER_W
    pivot = (w / 2, h - CLUSTER_PIVOT_UP * px)
    # The half-moon: a black band with the numbers round a cream dome.
    r_out, r_band, r_dome = 0.097 * px, 0.062 * px, 0.058 * px
    box = lambda r: [pivot[0] - r, pivot[1] - r, pivot[0] + r, pivot[1] + r]
    half = SPEEDO_SWEEP / 2
    d.pieslice(box(r_out), -90 - half - 8, -90 + half + 8, fill=(4, 4, 6))
    d.arc(box(r_out), -90 - half - 8, -90 + half + 8, fill=CHROME, width=5)
    d.pieslice(box(r_band), -90 - half - 8, -90 + half + 8, fill=CHROME)
    d.pieslice(box(r_dome), -90 - half - 8, -90 + half + 8, fill=CREAM)
    for k in range(0, 181, 6):
        d.line([pivot, _polar(pivot, r_dome, k - 90)], fill=CREAM_DARK, width=2)
    d.pieslice(box(r_dome * 0.55), -180, 0, fill=CREAM)
    for k in range(0, 181, 10):
        p = _polar(pivot, r_dome * 0.86, k - 90)
        d.ellipse([p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5], fill=CREAM_DARK)
    for mph in range(0, 161, 2):
        deg = -half + mph
        if mph % 10 == 0:
            d.line([_polar(pivot, r_band + 2, deg), _polar(pivot, r_band + 0.008 * px, deg)], fill=WHITE, width=5)
            if mph % 20 == 0:
                _text(d, _polar(pivot, r_band + 0.021 * px, deg), str(mph), _font(42), WHITE)
        else:
            d.line([_polar(pivot, r_band + 2, deg), _polar(pivot, r_band + 0.004 * px, deg)], fill=WHITE, width=2)
    # The odometer, just above the clock pod, and the high-beam tell-tale.
    ox, oy = pivot[0], pivot[1] - 0.046 * px
    d.rectangle([ox - 74, oy - 17, ox + 74, oy + 17], fill=(4, 4, 4), outline=CREAM_DARK, width=3)
    for i, c in enumerate('051037'):
        cx = ox - 62 + i * 24.8
        d.rectangle([cx - 10, oy - 13, cx + 10, oy + 13], fill=(232, 230, 222) if i < 5 else (30, 30, 30))
        _text(d, (cx, oy), c, _font(24, True), (20, 20, 20) if i < 5 else (232, 230, 222))
    tx = _polar(pivot, r_dome * 0.86, 0)
    d.ellipse([tx[0] - 8, tx[1] - 8, tx[0] + 8, tx[1] + 8], fill=(150, 18, 18))
    # The small gauges: AMP and OIL across the top, GAS and HEAT under them.
    gw, gh = GAUGE_SIZE
    left, right = 175, w - 175 - gw
    top, bottom = 100, GAS_AT[1]
    bleft, bright = GAS_AT[0], w - GAS_AT[0] - gw
    _small_gauge(d, (left, top, left + gw, top + gh), ['D', '|', 'C'], 'AMP', 0.5, True)
    _small_gauge(d, (bleft, bottom, bleft + gw, bottom + gh), ['E', '1/2', 'F'], 'GAS', None, False)
    _small_gauge(d, (right, top, right + gw, top + gh), ['0', '40', '80'], 'OIL', 0.45, True)
    _small_gauge(d, (bright, bottom, bright + gw, bottom + gh), ['C', '|', 'H'], 'HEAT', 0.4, False)
    return im


def clock_texture():
    s = CLOCK_TEX
    im = Image.new('RGB', (s, s), (8, 8, 10))
    d = ImageDraw.Draw(im)
    c = (s / 2, s / 2)
    r = s / 2 - 10
    for m in range(60):
        major = m % 5 == 0
        d.line([_polar(c, r - (16 if major else 7), m * 6), _polar(c, r, m * 6)], fill=WHITE, width=5 if major else 2)
    for n, deg in (('12', 0), ('3', 90), ('6', 180), ('9', 270)):
        _text(d, _polar(c, r - 40, deg), n, _font(34), WHITE)
    d.line([c, _polar(c, r * 0.5, 10 * 30 + 4)], fill=WHITE, width=7)
    d.line([c, _polar(c, r * 0.78, 8 * 6)], fill=WHITE, width=5)
    d.ellipse([c[0] - 8, c[1] - 8, c[0] + 8, c[1] + 8], fill=CHROME)
    return im


def tach_texture():
    s = TACH_TEX
    im = Image.new('RGB', (s, s), (6, 6, 8))
    d = ImageDraw.Draw(im)
    c = (s / 2, s / 2)
    d.ellipse([6, 6, s - 6, s - 6], outline=(150, 152, 158), width=8)
    half = TACH_SWEEP / 2
    r = s / 2 - 30
    for rpm in range(0, 7001, 250):
        deg = -half + TACH_SWEEP * rpm / 7000
        major = rpm % 1000 == 0
        red = rpm >= 6000
        col = (226, 60, 40) if red else (235, 235, 235)
        d.line([_polar(c, r - (44 if major else 22), deg), _polar(c, r, deg)], fill=col, width=9 if major else 4)
        if major:
            _text(d, _polar(c, r - 86, deg), str(rpm // 1000), _font(62), col)
    _text(d, (c[0], c[1] + 70), 'RPM', _font(42, True), (235, 235, 235))
    _text(d, (c[0], c[1] + 112), 'x1000', _font(28, True), (170, 170, 170))
    return im


def _rounded_rect(w, h, r, segments=6, z0=0.0):
    """Outline of a rounded rectangle in the X-Z plane, counterclockwise as the driver sees it."""
    pts = []
    corners = [(w / 2 - r, z0 + h - r, 0), (-w / 2 + r, z0 + h - r, 90),
               (-w / 2 + r, z0 + r, 180), (w / 2 - r, z0 + r, 270)]
    for cx, cz, start in corners:
        for i in range(segments + 1):
            a = math.radians(start + 90 * i / segments)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return np.array(pts)


def _round_corners(points, radii, segments=8):
    """A convex polygon (counterclockwise, X-Z) with each corner rounded to its radius."""
    pts = np.asarray(points, float)
    out = []
    n = len(pts)
    for i in range(n):
        p, a, b = pts[i], pts[i - 1], pts[(i + 1) % n]
        u1 = (a - p) / np.linalg.norm(a - p)
        u2 = (b - p) / np.linalg.norm(b - p)
        half = math.acos(np.clip(np.dot(u1, u2), -1, 1)) / 2
        r = radii[i]
        t1, t2 = p + u1 * r / math.tan(half), p + u2 * r / math.tan(half)
        bis = (u1 + u2) / np.linalg.norm(u1 + u2)
        c = p + bis * r / math.sin(half)
        a1 = math.atan2(*(t1 - c)[::-1])
        a2 = math.atan2(*(t2 - c)[::-1])
        if a2 < a1:
            a2 += 2 * math.pi
        if a2 - a1 > math.pi:
            a1 += 2 * math.pi
            a1, a2 = a2, a1
            seq = np.linspace(a2, a1, segments + 1)
        else:
            seq = np.linspace(a1, a2, segments + 1)
        for ang in seq:
            out.append(c + r * np.array([math.cos(ang), math.sin(ang)]))
    return np.array(out)


def _grow(outline, d):
    """A convex counterclockwise outline moved out by d."""
    n = len(outline)
    edge_n = []
    for i in range(n):
        e = outline[(i + 1) % n] - outline[i]
        edge_n.append(np.array([e[1], -e[0]]) / max(np.linalg.norm(e), 1e-12))
    out = []
    for i in range(n):
        m = edge_n[i - 1] + edge_n[i]
        m /= np.linalg.norm(m)
        out.append(outline[i] + m * d / max(np.dot(m, edge_n[i]), 0.3))
    return np.array(out)


def _outward_normals(outline):
    """Per-corner outward normals of a convex counterclockwise outline."""
    n = len(outline)
    edge_n = []
    for i in range(n):
        e = outline[(i + 1) % n] - outline[i]
        edge_n.append(np.array([e[1], -e[0]]) / max(np.linalg.norm(e), 1e-12))
    out = []
    for i in range(n):
        m = edge_n[i - 1] + edge_n[i]
        out.append(m / np.linalg.norm(m))
    return np.array(out)


def _rounded_prism(outline, y0, y1, r, steps=4, inner=None):
    """A convex outline from depth y0 (front) to y1 (back) with its front edge rounded
    over by r. With `inner` (an outline inside it, same corner count), the front is a
    ring round that hole instead of a solid face."""
    outline = np.asarray(outline, float)
    normals = _outward_normals(outline)
    core = _grow(outline, -r)
    rings = []
    for k in range(steps + 1):
        a = (math.pi / 2) * k / steps
        pts = core + normals * r * math.sin(a)
        y = y0 + r - r * math.cos(a)
        nn = np.concatenate([normals * math.sin(a), np.full((len(pts), 1), -math.cos(a))], 1)[:, [0, 2, 1]]
        rings.append((pts, y, nn))
    tris, nrm = [], []
    n = len(outline)
    for (pa, ya, na), (pb, yb, nb) in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            q = [(pa[i][0], ya, pa[i][1]), (pa[j][0], ya, pa[j][1]), (pb[j][0], yb, pb[j][1]), (pb[i][0], yb, pb[i][1])]
            m = [tuple(na[i]), tuple(na[j]), tuple(nb[j]), tuple(nb[i])]
            tris += [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]
            nrm += [[m[0], m[1], m[2]], [m[0], m[2], m[3]]]
    side = []
    for i in range(n):
        j = (i + 1) % n
        a, b = outline[i], outline[j]
        q = [(a[0], y0 + r, a[1]), (b[0], y0 + r, b[1]), (b[0], y1, b[1]), (a[0], y1, a[1])]
        m = [(normals[i][0], 0.0, normals[i][1]), (normals[j][0], 0.0, normals[j][1])]
        tris += [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]
        nrm += [[m[0], m[1], m[1]], [m[0], m[1], m[0]]]
    parts = [(np.array(tris), np.array(nrm)), _cap(outline, y1, 1.0)]
    parts.append(_ring(core, inner, y0) if inner is not None else _cap(core, y0, -1.0))
    return _join(*parts)


def _cluster_outline(side=0.0, top=0.0):
    """The face's outline, or with `side` and `top` the frame's, grown out that much down
    the sides and across the top along the same lean."""
    z0, w, h, t = -CLUSTER_PIVOT_UP, CLUSTER_W, CLUSTER_H, CLUSTER_TAPER
    zb, zt = z0, z0 + h + top
    lean = t / h
    xb = w / 2 + side
    xt = xb - lean * (zt - zb)
    corners = [(xb, zb), (xt, zt), (-xt, zt), (-xb, zb)]
    radii = [CLUSTER_BOTTOM_RADIUS, CLUSTER_TOP_RADIUS + top * 0.6, CLUSTER_TOP_RADIUS + top * 0.6, CLUSTER_BOTTOM_RADIUS]
    return _round_corners(corners, radii, 10)


def _extrude_x(profile, x0, x1):
    """A profile in the Y-Z plane (counterclockwise looking along +X) run from x0 to x1,
    smooth along the profile, with flat ends."""
    prof = np.asarray(profile, float)
    n = len(prof)
    center = prof.mean(0)
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
        a0, a1 = (x0, *prof[i]), (x1, *prof[i])
        b0, b1 = (x0, *prof[j]), (x1, *prof[j])
        na, nb = (0.0, *vn[i]), (0.0, *vn[j])
        tris += [[a0, b0, b1], [a0, b1, a1]]
        nrm += [[na, nb, nb], [na, nb, na]]
    for x, sx in ((x0, -1.0), (x1, 1.0)):
        for i in range(n):
            j = (i + 1) % n
            tris.append([(x, *center), (x, *prof[i]), (x, *prof[j])])
            nrm.append([(sx, 0.0, 0.0)] * 3)
    return np.array(tris), np.array(nrm)


def _circle(r, segments=40):
    a = np.linspace(0, 2 * math.pi, segments, endpoint=False)
    return np.stack([r * np.cos(a), r * np.sin(a)], 1)


def _cap(outline, y, normal_y):
    """A flat fan over a convex outline at depth y."""
    center = outline.mean(0)
    tris, nrm = [], []
    for i in range(len(outline)):
        a, b = outline[i], outline[(i + 1) % len(outline)]
        tris.append([(center[0], y, center[1]), (a[0], y, a[1]), (b[0], y, b[1])])
    tris = np.array(tris)
    return tris, np.full_like(tris, 0.0) + np.array([0.0, normal_y, 0.0])


def _ring(outer, inner, y):
    tris = []
    n = len(outer)
    for i in range(n):
        j = (i + 1) % n
        o0, o1, i0, i1 = outer[i], outer[j], inner[i], inner[j]
        tris += [[(o0[0], y, o0[1]), (o1[0], y, o1[1]), (i1[0], y, i1[1])],
                 [(o0[0], y, o0[1]), (i1[0], y, i1[1]), (i0[0], y, i0[1])]]
    tris = np.array(tris)
    return tris, np.full_like(tris, 0.0) + np.array([0.0, -1.0, 0.0])


def _wall(outline, y0, y1, outward=True):
    center = outline.mean(0)
    tris, nrm = [], []
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        a, b = outline[i], outline[j]
        tris += [[(a[0], y0, a[1]), (b[0], y0, b[1]), (b[0], y1, b[1])],
                 [(a[0], y0, a[1]), (b[0], y1, b[1]), (a[0], y1, a[1])]]
        na = (a - center) / np.linalg.norm(a - center)
        nb = (b - center) / np.linalg.norm(b - center)
        if not outward:
            na, nb = -na, -nb
        va, vb = (na[0], 0.0, na[1]), (nb[0], 0.0, nb[1])
        nrm += [[va, vb, vb], [va, vb, va]]
    return np.array(tris), np.array(nrm)


def _join(*parts):
    return np.concatenate([p[0] for p in parts]), np.concatenate([p[1] for p in parts])


def _needle(length, tail, width, rest_deg, y):
    """A tapered needle from the pivot toward `rest_deg` (clockwise from up, as seen)."""
    a = math.radians(rest_deg)
    along = np.array([math.sin(a), math.cos(a)])
    side = np.array([along[1], -along[0]])
    tip = along * length
    back = -along * tail
    pts = [back + side * width, tip + side * width * 0.3, tip - side * width * 0.3, back - side * width]
    q = [(p[0], y, p[1]) for p in pts]
    tris = np.array([[q[0], q[1], q[2]], [q[0], q[2], q[3]]])
    return tris, np.full_like(tris, 0.0) + np.array([0.0, -1.0, 0.0])


def fuel_pointer():
    """The GAS gauge's pointer, which the game slides with the fuel left.

    Returns (where it rests, at F, in the speedometer pod's frame; how far it travels to
    E, meters; its mesh pieces centered on its own origin). The game moves it along its
    -X by the fuel used, as the F100's straight-line speedometer moves."""
    w, h = CLUSTER_TEX
    gw, gh = GAUGE_SIZE
    to_m = CLUSTER_W / w
    full_px = GAS_AT[0] + gw - GAUGE_INSET
    x = full_px * to_m - CLUSTER_W / 2
    z = -CLUSTER_PIVOT_UP + CLUSTER_H - (GAS_AT[1] + gh / 2) * CLUSTER_H / h
    travel = (gw - 2 * GAUGE_INSET) * to_m
    half_w, half_h = 2.5 * to_m, (gh / 2 - 10) * CLUSTER_H / h
    q = [(-half_w, 0.0, -half_h), (half_w, 0.0, -half_h), (half_w, 0.0, half_h), (-half_w, 0.0, half_h)]
    tris = np.array([[q[0], q[1], q[2]], [q[0], q[2], q[3]]])
    nrm = np.full_like(tris, 0.0) + np.array([0.0, -1.0, 0.0])
    return (x, -0.002, z), travel, [('pointer', tris, nrm, None)]


def cluster_parts():
    """Meshes of the speedometer pod in its own frame: {name: (material, tris, normals, uv)}."""
    z0 = -CLUSTER_PIVOT_UP
    face = _cluster_outline()
    lip = _cluster_outline(FRAME_SIDE, FRAME_TOP)
    ftris, fnrm = _cap(face, 0.0, -1.0)
    u = (ftris[..., 0] + CLUSTER_W / 2) / CLUSTER_W
    v = (z0 + CLUSTER_H - ftris[..., 2]) / CLUSTER_H
    rail_w = CLUSTER_W / 2 + 0.010
    # The rail's front is rounded over, top to bottom, so it catches the light.
    zb, zt = z0 - RAIL_DOWN, z0 + RAIL_UP
    zm, rr = (zb + zt) / 2, (zt - zb) / 2
    profile = [(0.045, zb)] + [(-RAIL_OUT + rr - rr * math.cos(a), zm - rr * math.sin(a))
                               for a in np.linspace(-math.pi / 2, math.pi / 2, 9)][::-1] + [(0.045, zt)]
    profile = profile[::-1]
    bezel = _join(_ring(lip, face, -0.010), _wall(lip, -0.010, 0.045), _wall(face, -0.010, 0.0, outward=False),
                  _extrude_x(profile, -rail_w, rail_w))
    needle = _needle(SPEEDO_NEEDLE, 0.012, 0.0022, -SPEEDO_SWEEP / 2, -0.004)
    cap = _cap(_circle(0.0055, 20), -0.0055, -1.0)
    return {
        'bezel': ('bezel', *bezel, None),
        'face': ('cluster_face', ftris, fnrm, np.stack([u, v], -1)),
        'needle': [('needle', *needle, None), ('cap', *cap, None)],
    }


def _taper(r0, y0, r1, y1, segments=40):
    """A cone from radius r0 at depth y0 to r1 at y1, normals out."""
    a0, a1 = _circle(r0, segments), _circle(r1, segments)
    slope = (r0 - r1) / (y1 - y0)
    tris, nrm = [], []
    for i in range(segments):
        j = (i + 1) % segments
        p = [(a0[i][0], y0, a0[i][1]), (a0[j][0], y0, a0[j][1]), (a1[j][0], y1, a1[j][1]), (a1[i][0], y1, a1[i][1])]
        n = []
        for k in (i, j):
            d = a0[k] / r0
            v = np.array([d[0], slope, d[1]])
            n.append(tuple(v / np.linalg.norm(v)))
        tris += [[p[0], p[1], p[2]], [p[0], p[2], p[3]]]
        nrm += [[n[0], n[1], n[1]], [n[0], n[1], n[0]]]
    return np.array(tris), np.array(nrm)


def _box(x0, x1, y0, y1, z0, z1):
    c = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    faces = [((0, 1, 3, 2), (-1, 0, 0)), ((4, 6, 7, 5), (1, 0, 0)), ((0, 4, 5, 1), (0, -1, 0)),
             ((2, 3, 7, 6), (0, 1, 0)), ((0, 2, 6, 4), (0, 0, -1)), ((1, 5, 7, 3), (0, 0, 1))]
    tris, nrm = [], []
    for (a, b, cc, d), n in faces:
        tris += [[c[a], c[b], c[cc]], [c[a], c[cc], c[d]]]
        nrm += [[n] * 3, [n] * 3]
    return np.array(tris, float), np.array(nrm, float)


def tach_parts():
    face = _circle(TACH_R)
    lip = _circle(TACH_R + 0.0045)
    ftris, fnrm = _cap(face, 0.0, -1.0)
    u = 0.5 + ftris[..., 0] / (2 * TACH_R)
    v = 0.5 - ftris[..., 2] / (2 * TACH_R)
    bezel = _join(_ring(lip, face, -0.005), _wall(lip, -0.005, 0.003), _wall(face, -0.005, 0.0, outward=False))
    rim = TACH_R + 0.003
    cup = _join(_taper(rim, 0.003, TACH_CUP_BACK_R, TACH_CUP_DEPTH),
                _cap(_circle(TACH_CUP_BACK_R), TACH_CUP_DEPTH, 1.0),
                # The clamp: a strap from under the cup down onto the cluster's hood.
                _box(-0.006, 0.006, 0.010, 0.026, -TACH_CLAMP_DROP, -rim + 0.004),
                _box(-0.010, 0.010, 0.004, 0.034, -TACH_CLAMP_DROP - 0.003, -TACH_CLAMP_DROP))
    needle = _needle(TACH_NEEDLE, 0.006, 0.0014, -TACH_SWEEP / 2, -0.003)
    cap = _cap(_circle(0.0038, 20), -0.004, -1.0)
    return {
        'bezel': ('bezel', *bezel, None),
        'cup': ('cap', *cup, None),
        'face': ('tach_face', ftris, fnrm, np.stack([u, v], -1)),
        'needle': [('needle', *needle, None), ('cap', *cap, None)],
    }


def _prism(outline, y0, y1):
    """A convex outline in the X-Z plane, from depth y0 (front) to y1 (back)."""
    return _join(_cap(outline[::-1], y0, -1.0), _cap(outline, y1, 1.0), _wall(outline, y0, y1))


def clock_parts():
    """The clock in its winged chrome pod; nothing in it moves."""
    face = _circle(CLOCK_R)
    lip = _circle(CLOCK_R + 0.005)
    ftris, fnrm = _cap(face, 0.0, -1.0)
    u = 0.5 + ftris[..., 0] / (2 * CLOCK_R)
    v = 0.5 - ftris[..., 2] / (2 * CLOCK_R)
    rim = CLOCK_R + 0.005
    # The rim's front edge and the wings' are rounded over a little.
    parts = [_rounded_prism(lip, -0.006, 0.030, 0.0025, inner=face), _wall(face, -0.006, 0.0, outward=False)]
    for side in (-1, 1):
        # Each wing runs out along the rail, its top sloping from the clock's rim down to
        # the rail's top.
        bottom = CLOCK_RAIL_BOTTOM + 0.002
        wing = np.array([(side * rim * 0.7, bottom), (side * CLOCK_WING, bottom),
                         (side * (CLOCK_WING + 0.006), (bottom + CLOCK_RAIL_TOP) / 2),
                         (side * CLOCK_WING, CLOCK_RAIL_TOP + 0.003), (side * rim * 0.7, rim * 0.62)])
        if side < 0:
            wing = wing[::-1]
        parts.append(_rounded_prism(wing, -0.004, 0.030, 0.006, steps=6))
    return {
        'bezel': ('bezel', *_join(*parts), None),
        'face': ('clock_face', ftris, fnrm, np.stack([u, v], -1)),
    }


def face_materials():
    """The face materials (their images are added by the caller): name -> (material, png)."""
    out = {}
    for key, name, im in (('cluster_face', 'dash_studebaker_sp_mat', cluster_texture()),
                          ('tach_face', 'dash_studebaker_ta_mat', tach_texture()),
                          ('clock_face', 'dash_studebaker_clock_mat', clock_texture())):
        out[key] = ({'name': name, 'doubleSided': True, 'emissiveFactor': [0.65, 0.65, 0.65],
                     'pbrMetallicRoughness': {'metallicFactor': 0.0, 'roughnessFactor': 0.45}}, _png(im))
    return out


def facing_basis(toward, up=(0.0, 1.0, 0.0)):
    """Pod axes in car space (columns X, Y, Z) with the face (-Y) turned toward `toward`
    (a direction) and +Z as near `up` as it can be."""
    f = np.asarray(toward, np.float64)
    f /= np.linalg.norm(f)
    y = -f
    z = np.asarray(up, np.float64) - np.dot(up, f) * f
    z /= np.linalg.norm(z)
    x = np.cross(y, z)
    return np.stack([x, y, z], 1)


def quaternion(m):
    """(x, y, z, w) of a rotation matrix."""
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        return [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    i = int(np.argmax(np.diag(m)))
    j, k = (i + 1) % 3, (i + 2) % 3
    s = math.sqrt(1.0 + m[i, i] - m[j, j] - m[k, k]) * 2
    q = [0.0, 0.0, 0.0, 0.0]
    q[i] = 0.25 * s
    q[j] = (m[j, i] + m[i, j]) / s
    q[k] = (m[k, i] + m[i, k]) / s
    q[3] = (m[k, j] - m[j, k]) / s
    return q
