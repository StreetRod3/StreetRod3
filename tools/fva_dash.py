"""Working gauges for the Free Vehicle Archive cars. Used by tools/fva_to_glb.py.

Both models' gauge faces are printed in an image and their needles are meshes of their
own. Each working needle comes out of the body into a pod of its own, at its pivot, turned
to rest at 0 (a speedometer) or F (a gas gauge); the needles that don't work (temperature,
oil, battery) stay where the model has them.

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
    straight line, in a pod named `dash_fuel_linear_<travel>_pod`.

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


def build(spec, face, size, needles):
    """The pods for a car's gauges: (pod name, needle node name, origin, basis, needle objects,
    turn) for each needle out of the body, and for a sliding pointer of its own, the pointer
    mesh (positions, normals in its pod's frame) in place of the objects.

    face: the face's triangles and UVs (car space); size: its image's (width, height);
    needles: each needle object's triangles (car space)."""
    pods = []
    speedo = spec['speedo']
    if 'pivot' in speedo:
        pivot = uv_point(*face, size, speedo['pivot'])[0]
    else:
        pivot = circle_center(*[uv_point(*face, size, m)[0] for m in speedo['marks']])
    corners = np.concatenate([needles[o].reshape(-1, 3) for o in speedo['objects']])
    hub = needle_hub(corners, pivot)
    basis, rest, sweep = swinging(face, size, corners, hub, speedo['marks'][0], speedo['marks'][-1])
    pods.append((f'dash_speedo_arch_{sweep:.0f}_mph_{speedo["mph"]}_pod', 'speedo_needle', hub, basis,
                 speedo['objects'], rest))
    fuel = spec.get('fuel')
    if fuel and 'objects' in fuel:
        corners = np.concatenate([needles[o].reshape(-1, 3) for o in fuel['objects']])
        hub = needle_hub(corners, uv_point(*face, size, fuel['pivot'])[0])
        basis, rest, sweep = swinging(face, size, corners, hub, fuel['empty'], fuel['full'])
        pods.append((f'dash_fuel_arch_{sweep:.0f}_pod', 'fuel_needle', hub, basis, fuel['objects'],
                     rest + sweep))
    elif fuel:
        empty, normal = uv_point(*face, size, fuel['slide'][0])
        full, _ = uv_point(*face, size, fuel['slide'][1])
        into = into_dash(normal)
        basis = pod_basis(into, full - empty)
        travel = float(np.linalg.norm(full - empty))
        origin = full - into * POINTER_LIFT
        pods.append((f'dash_fuel_linear_{travel:.4f}_pod', 'fuel_needle', origin, basis,
                     pointer(travel * POINTER_SHARE), 0.0))
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
