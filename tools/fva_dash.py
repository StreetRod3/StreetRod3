"""Working gauges for the Free Vehicle Archive cars. Used by tools/fva_to_glb.py.

The models' gauge faces are printed in images, and their needles are meshes of their own
or printed on the faces. Each working needle comes out of the body into a pod of its own,
at its pivot, turned to rest at 0 (a speedometer or tach) or F (a gas gauge); the needles
that don't work (temperature, oil, battery) stay where the model has them.

Where the marks are is given in the face image's pixels (from the top left), and found on
the dash through the face's UVs, so the sweep is measured on the car, not guessed:

  * `speedo`: the needle's objects, the top of the scale in mph, and three marks along
    the scale (the first at 0, the last at the top): the needle pivots at the middle of
    the circle through them, and its pod is named
    `dash_speedo_arch_<sweep>_mph_<top>_pod`;
  * `fuel` with `objects`: a needle that swings, the marks at E and F and where it
    pivots; its pod is `dash_fuel_arch_<sweep>_pod`, which the game turns back from F as
    the tank empties;
  * `fuel` with `slide`: a pointer of its own (the model's is printed on the face, and is
    painted out over `erase`, a line between two pixels) sliding from F to E along a
    straight line, in a pod named `dash_fuel_linear_<travel>_pod`;
  * `tach`: a needle of its own `color` (the model's is printed on the face and painted
    out by erase_needle over `erase`: its line, width and where the scale's ticks begin),
    turning about `pivot` from `zero` to `full` as the rpm goes from the least to the most
    of `rpm`, reaching out to `tip`; its pod is
    `dash_tach_arch_<sweep>_rpm_<least>_<most>_pod`.

A gauge's face is the spec's `face` (object, material), or the gauge's own.

The pods follow the other cars' dashes (tools/studebaker_dash.py): in a pod's frame +X is
to the driver's right, +Y into the dash and +Z up, and the game turns a needle about the
pod's +Y from where it rests, which is clockwise as the driver sees it.
"""
import math

import numpy as np

## A sliding pointer: its width, how far it stands off the face toward the driver, and its
## length across the slide as a share of the slide's length (meters).
POINTER_WIDTH = 0.0012
POINTER_LIFT = 0.0008
POINTER_SHARE = 0.14
## The pointer's color (sRGB), for the converter's palette.
POINTER_COLOR = (236, 232, 220)


def uv_point(tris, uvs, image_size, pixel):
    """Where a pixel of the face's image (x, y from the top left) is on the face (car space),
    and the face's normal there. UVs repeat, so each triangle's are taken in its own tile."""
    w, h = image_size
    target = np.array([pixel[0] / w, 1.0 - pixel[1] / h])
    tiles = uvs - np.floor(uvs.mean(1, keepdims=True))
    best = None
    for k in range(len(tris)):
        a, b, c = tiles[k]
        v0, v1, v2 = b - a, c - a, target - a
        den = v0[0] * v1[1] - v1[0] * v0[1]
        if abs(den) < 1e-12:
            continue
        l1 = (v2[0] * v1[1] - v1[0] * v2[1]) / den
        l2 = (v0[0] * v2[1] - v2[0] * v0[1]) / den
        miss = max(-l1, -l2, l1 + l2 - 1, 0.0)
        if best is None or miss < best[0]:
            best = (miss, k, l1, l2)
    miss, k, l1, l2 = best
    if miss > 0.02:
        raise ValueError(f'pixel {pixel} is not on the face')
    t = tris[k]
    normal = np.cross(t[1] - t[0], t[2] - t[0])
    return t[0] + l1 * (t[1] - t[0]) + l2 * (t[2] - t[0]), normal / np.linalg.norm(normal)


def pod_basis(into, right=None):
    """Pod axes in car space (columns X, Y, Z): +Y into the dash, +X along `right` (or as
    level as it can be), +Z up."""
    y = into / np.linalg.norm(into)
    if right is None:
        z = np.array([0.0, 1.0, 0.0]) - y[1] * y
        z /= np.linalg.norm(z)
        x = np.cross(y, z)
    else:
        x = right - np.dot(right, y) * y
        x /= np.linalg.norm(x)
        z = np.cross(x, y)
    return np.stack([x, y, z], 1)


def turn(degrees):
    """A turn about a pod's +Y, clockwise as the driver sees it, for row vectors in the pod."""
    a = math.radians(degrees)
    return np.array([[math.cos(a), 0.0, -math.sin(a)], [0.0, 1.0, 0.0], [math.sin(a), 0.0, math.cos(a)]])


def clock(local):
    """Degrees clockwise from up, as the driver sees it, of a point in a pod's frame."""
    return math.degrees(math.atan2(local[0], local[2]))


def circle_center(a, b, c):
    """The middle of the circle through three points (car space)."""
    ab, ac = b - a, c - a
    n = np.cross(ab, ac)
    return a + (np.cross(n, ab) * np.dot(ac, ac) + np.cross(ac, n) * np.dot(ab, ab)) / (2 * np.dot(n, n))


def into_dash(normal):
    """A face normal turned to point into the dash (the way the car faces, +Z)."""
    return normal if normal[2] > 0 else -normal


def swinging(face, size, needle, pivot, zero, full):
    """A needle that turns about `pivot` (car space): its pod's frame, the turn that rests it
    at `zero` (pixel) and its sweep to `full` (pixel), clockwise."""
    zero_at, normal = uv_point(*face, size, zero)
    full_at, _ = uv_point(*face, size, full)
    basis = pod_basis(into_dash(normal))
    local = (needle - pivot) @ basis
    tip = local[np.argmax(np.hypot(local[:, 0], local[:, 2]))]
    rest, start, end = clock(tip), clock((zero_at - pivot) @ basis), clock((full_at - pivot) @ basis)
    sweep = (end - start) % 360.0
    return basis, start - rest, sweep


def build(spec, faces, needles):
    """The pods for a car's gauges: (pod name, needle node name, origin, basis, needle objects,
    turn) for each needle out of the body, and for a needle or pointer of its own, its mesh
    (positions, normals in its pod's frame, color) in place of the objects.

    faces: the (object, material) of a face to (its triangles and UVs in car space, its
    image's (width, height)); a gauge's face is its own `face` or the spec's; needles: each
    needle object's triangles (car space)."""
    pods = []

    def face_of(part):
        return faces(part.get('face', spec.get('face')))

    speedo = spec.get('speedo')
    if speedo:
        face, size = face_of(speedo)
        if 'pivot' in speedo:
            pivot = uv_point(*face, size, speedo['pivot'])[0]
        else:
            pivot = circle_center(*[uv_point(*face, size, m)[0] for m in speedo['marks']])
        corners = np.concatenate([needles[o].reshape(-1, 3) for o in speedo['objects']])
        hub = needle_hub(corners, pivot)
        basis, rest, sweep = swinging(face, size, corners, hub, speedo['marks'][0], speedo['marks'][-1])
        pods.append((f'dash_speedo_arch_{sweep:.0f}_mph_{speedo["mph"]}_pod', 'speedo_needle', hub, basis,
                     speedo['objects'], rest))
    tach = spec.get('tach')
    if tach:
        face, size = face_of(tach)
        pivot, normal = uv_point(*face, size, tach['pivot'])
        basis = pod_basis(into_dash(normal))
        start, end = (clock((uv_point(*face, size, tach[k])[0] - pivot) @ basis) for k in ('zero', 'full'))
        sweep = (end - start) % 360.0
        length = float(np.linalg.norm(uv_point(*face, size, tach['tip'])[0] - pivot))
        pos, nrm = needle(length)
        low, top = tach['rpm']
        pods.append((f'dash_tach_arch_{sweep:.0f}_rpm_{low}_{top}_pod', 'tach_needle', pivot, basis,
                     (pos @ turn(start), nrm @ turn(start), tach['color']), 0.0))
    fuel = spec.get('fuel')
    if fuel and 'objects' in fuel:
        face, size = face_of(fuel)
        corners = np.concatenate([needles[o].reshape(-1, 3) for o in fuel['objects']])
        hub = needle_hub(corners, uv_point(*face, size, fuel['pivot'])[0])
        basis, rest, sweep = swinging(face, size, corners, hub, fuel['empty'], fuel['full'])
        pods.append((f'dash_fuel_arch_{sweep:.0f}_pod', 'fuel_needle', hub, basis, fuel['objects'],
                     rest + sweep))
    elif fuel:
        face, size = face_of(fuel)
        empty, normal = uv_point(*face, size, fuel['slide'][0])
        full, _ = uv_point(*face, size, fuel['slide'][1])
        into = into_dash(normal)
        basis = pod_basis(into, full - empty)
        travel = float(np.linalg.norm(full - empty))
        origin = full - into * POINTER_LIFT
        pods.append((f'dash_fuel_linear_{travel:.4f}_pod', 'fuel_needle', origin, basis,
                     (*pointer(travel * POINTER_SHARE), POINTER_COLOR), 0.0))
    return pods


## A needle's hub: its corners within this much of the one nearest the marked pivot (m).
HUB_REACH = 0.006


def needle_hub(corners, pivot):
    """Where a needle turns: the middle of its end nearest the marked pivot (car space)."""
    d = np.linalg.norm(corners - pivot, axis=1)
    return corners[d <= d.min() + HUB_REACH].mean(0)


def pointer(length):
    """A sliding gas gauge's pointer: a thin bar across the slide, facing the driver (-Y),
    in its pod's frame; (positions, normals) as a triangle list."""
    w, h = POINTER_WIDTH / 2, length / 2
    quad = np.array([[-w, 0, -h], [w, 0, -h], [w, 0, h], [-w, 0, -h], [w, 0, h], [-w, 0, h]])
    return quad, np.tile([0.0, -1.0, 0.0], (6, 1))


## A needle of its own: its width at the hub and at the tip, and how far its tail reaches
## back past the hub, as a share of its length (meters).
NEEDLE_ROOT = 0.0018
NEEDLE_TIP = 0.0007
NEEDLE_TAIL = 0.18


def needle(length):
    """A round gauge's needle of its own, pointing up (+Z) from its hub at the pod's origin,
    standing off the face toward the driver (-Y), with a round hub; (positions, normals)
    as a triangle list."""
    tail = length * NEEDLE_TAIL
    r, t = NEEDLE_ROOT / 2, NEEDLE_TIP / 2
    y = -POINTER_LIFT
    quad = [[-r, y, -tail], [r, y, -tail], [t, y, length], [-r, y, -tail], [t, y, length], [-t, y, length]]
    hub = []
    for k in range(12):
        a0, a1 = 2 * math.pi * k / 12, 2 * math.pi * (k + 1) / 12
        hub += [[0, y * 1.5, 0], [NEEDLE_ROOT * math.sin(a0), y * 1.5, NEEDLE_ROOT * math.cos(a0)],
                [NEEDLE_ROOT * math.sin(a1), y * 1.5, NEEDLE_ROOT * math.cos(a1)]]
    pos = np.array(quad + hub, float)
    return pos, np.tile([0.0, -1.0, 0.0], (len(pos), 1))


def erase(pixels, line, width=1.8):
    """Paint out a printed pointer: the pixels within `width` of the line between two pixels
    take the middle color of those a little farther out (pixels: rows top down, RGBA)."""
    (x0, y0), (x1, y1) = line
    h, w = pixels.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w]
    d = np.array([x1 - x0, y1 - y0], float)
    t = np.clip(((xs - x0) * d[0] + (ys - y0) * d[1]) / np.dot(d, d), 0, 1)
    dist = np.hypot(xs - (x0 + t * d[0]), ys - (y0 + t * d[1]))
    out = pixels.copy()
    out[dist <= width] = np.median(pixels[(dist > width + 1) & (dist <= width + 3)], axis=0).astype(pixels.dtype)
    return out


def _line_distance(shape, line):
    """Each pixel's distance from the segment between two pixels."""
    (x0, y0), (x1, y1) = line
    h, w = shape
    ys, xs = np.mgrid[0:h, 0:w]
    d = np.array([x1 - x0, y1 - y0], float)
    t = np.clip(((xs - x0) * d[0] + (ys - y0) * d[1]) / np.dot(d, d), 0, 1)
    return np.hypot(xs - (x0 + t * d[0]), ys - (y0 + t * d[1]))


def _diffuse(out, known):
    """Fill the unknown pixels from their known neighbors, from the edges in."""
    h, w = known.shape
    while not known.all():
        acc = np.zeros(out.shape)
        n = np.zeros((h, w))
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx or dy:
                    k = np.roll(np.roll(known, dy, 0), dx, 1)
                    acc += np.roll(np.roll(out, dy, 0), dx, 1) * k[..., None]
                    n += k
        new = ~known & (n >= 3)
        if not new.any():
            new = ~known & (n > 0)
        out[new] = acc[new] / n[new][:, None]
        known |= new
    return out


## A printed needle's pixels: those within its width of its line whose color is within this
## much (0-255, per channel at most) of the needle's, and one more pixel round them.
NEEDLE_MATCH = 80


def erase_needle(pixels, line, width, pivot, ring):
    """Paint out a round gauge's printed needle (pixels: rows top down, RGBA): its pixels near
    the line between two pixels, in the color the line's middle has. Out on the scale (past
    `ring` px from `pivot`) every pixel near the line takes the one a turn of the ticks'
    pattern round (tick_step), so the ticks it covered come back; inside, the face round
    the needle is carried in."""
    h, w = pixels.shape[:2]
    dist = _line_distance((h, w), line)
    rgb = pixels[..., :3].astype(int)
    color = np.median(rgb[dist <= 1.0], axis=0)
    mask = (dist <= width) & (np.abs(rgb - color).max(-1) <= NEEDLE_MATCH)
    grown = mask.copy()
    grown[1:] |= mask[:-1]
    grown[:-1] |= mask[1:]
    grown[:, 1:] |= mask[:, :-1]
    grown[:, :-1] |= mask[:, 1:]
    ys, xs = np.mgrid[0:h, 0:w]
    r = np.hypot(xs - pivot[0], ys - pivot[1])
    # Out on the scale every pixel near the line goes, edges and all: the ticks come back.
    mask = grown & (dist <= width + 1) | (r > ring) & (dist <= width + 1)
    out = pixels.astype(float)
    a = np.arctan2(ys - pivot[1], xs - pivot[0])
    step = tick_step(pixels, pivot, ring)
    outer = mask & (r > ring)
    for turn in (step, -step):
        sx = np.round(pivot[0] + r * np.cos(a + turn)).astype(int).clip(0, w - 1)
        sy = np.round(pivot[1] + r * np.sin(a + turn)).astype(int).clip(0, h - 1)
        take = outer & ~mask[sy, sx]
        out[take] = pixels[sy[take], sx[take]]
        outer &= ~take
    known = ~mask | (r > ring) & ~outer
    out = _diffuse(out, known)
    return np.round(out).clip(0, 255).astype(pixels.dtype)


## How far out past a scale's inner edge its ticks are looked for (px), and the turns
## (degrees) tried for the one that best repeats them.
TICK_BAND = 16
TICK_TURNS = (2.0, 30.0)


def tick_step(pixels, pivot, ring):
    """The turn (radians) that best repeats a scale's ticks, long and short alike: the lag
    at which the brightness round the circles from `ring` px out from `pivot` (to
    TICK_BAND px past it) best matches itself."""
    h, w = pixels.shape[:2]
    lum = pixels[..., :3].astype(float).mean(-1)
    n = 3600
    angles = np.linspace(0, 2 * np.pi, n, endpoint=False)
    rows = []
    for rr in np.linspace(ring, ring + TICK_BAND, 8):
        x = np.round(pivot[0] + rr * np.cos(angles)).astype(int).clip(0, w - 1)
        y = np.round(pivot[1] + rr * np.sin(angles)).astype(int).clip(0, h - 1)
        rows.append(lum[y, x])
    sig = np.mean(rows, 0)
    sig = sig - sig.mean()
    lags = np.arange(int(TICK_TURNS[0] * n / 360), int(TICK_TURNS[1] * n / 360) + 1)
    match = [np.dot(sig, np.roll(sig, k)) for k in lags]
    return 2 * np.pi * lags[int(np.argmax(match))] / n
