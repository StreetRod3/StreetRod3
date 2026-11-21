"""Working gauges for the 1967 Impala's instrument panel. Used by tools/impala_to_glb.py.

The model's panel has seven round dials (BaseClock_LP), each with a red needle
(ArrowClock_LP), but the faces are blank. Each dial gets a printed face laid just over the
model's own, and its needle comes out of the body into its own node:

  * the middle pod, behind the steering wheel, is the speedometer, 0-160 mph over 250
    degrees (the game's needle runs to 160);
  * the pod toward the door is the tachometer, 0-7000 rpm over the same 250 degrees;
  * the pod toward the middle of the car is the gas gauge, E to F over 90 degrees across
    the top, its pointer turned back from F as the tank empties (a pod named
    `dash_fuel_arch_90_pod`);
  * the four small dials at the ends are OIL and TEMP toward the middle, AMP and VAC
    toward the door, over 120 degrees, with pointers that stay put.

The pods follow the Studebaker's (tools/studebaker_dash.py): in a pod's frame the face
lies in the X-Z plane facing -Y, +X to the driver's right and +Z up, and the game turns
a needle about the pod's +Y from where it rests, which is clockwise as the driver sees it.
"""
import math

import numpy as np
from PIL import Image, ImageDraw

from studebaker_dash import CHROME, WHITE, _font, _png, _polar, _text, quaternion

## How far the printed face stands off the model's, and the needle off the printed face,
## toward the driver (meters).
FACE_LIFT = 0.0005
NEEDLE_LIFT = 0.0015
## The printed face's radius as a share of the model's face.
FACE_SHARE = 0.985
SEGMENTS = 48
BIG_TEX = 512
SMALL_TEX = 256
RED = (226, 60, 40)
FACE_DARK = (12, 12, 14)

## The big dials by their place from the middle of the car out to the door, and the small
## ones by side (0 = toward the middle) and whether they are the upper of the pair.
BIG = ['fuel', 'speedo', 'tach']
SMALL = {(0, True): 'oil', (0, False): 'temp', (1, True): 'amp', (1, False): 'vac'}
## Each dial: its sweep in degrees, centered on straight up; where its needle rests, in
## degrees clockwise from straight up; its scale (label, share of the sweep); its name.
DIALS = {
    'speedo': (250.0, -125.0, [(str(m), m / 160) for m in range(0, 161, 20)], 'MPH'),
    'tach': (250.0, -125.0, [(str(k), k / 7) for k in range(8)], 'RPM x1000'),
    'fuel': (90.0, 45.0, [('E', 0.0), ('1/2', 0.5), ('F', 1.0)], 'FUEL'),
    'oil': (120.0, 10.0, [('0', 0.0), ('80', 1.0)], 'OIL'),
    'temp': (120.0, 0.0, [('C', 0.0), ('H', 1.0)], 'TEMP'),
    'amp': (120.0, 0.0, [('D', 0.0), ('C', 1.0)], 'AMP'),
    'vac': (120.0, 15.0, [('0', 0.0), ('30', 1.0)], 'VAC'),
}
## The game's node names for the needles that move, and the pods' names.
NEEDLES = {'speedo': 'speedo_needle', 'tach': 'tach_needle', 'fuel': 'fuel_needle'}
PODS = {'speedo': 'dash_speedo_arch_250_pod', 'tach': 'dash_tach_pod', 'fuel': 'dash_fuel_arch_90_pod'}


def islands(tris):
    """Triangle indices of each connected piece of a triangle soup."""
    _, inv = np.unique(tris.reshape(-1, 3).round(6), axis=0, return_inverse=True)
    f = inv.reshape(-1, 3)
    parent = np.arange(f.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a, b, c in f:
        for x, y in ((a, b), (b, c)):
            rx, ry = find(x), find(y)
            if rx != ry:
                parent[rx] = ry
    roots = np.array([find(v) for v in f[:, 0]])
    return [np.nonzero(roots == r)[0] for r in np.unique(roots)]


def dial_face(tris, needle):
    """Center, axis (into the dash) and radius of a dial's face: of the big flat pieces of
    the dial (the bezel's front ring, the face, the plate at the back of the cup), the one
    in the plane its needle lies on."""
    cross = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    area = np.linalg.norm(cross, axis=1)
    n = cross / np.maximum(area, 1e-15)[:, None]
    n *= np.where(n[:, 2] < 0, -1.0, 1.0)[:, None]
    depth = np.einsum('ij,ij->i', tris[:, 0], n)
    planes = []
    for i in np.argsort(-area)[:60]:
        same = (np.abs(n @ n[i]) > 0.999) & (np.abs(tris[:, 0] @ n[i] - depth[i]) < 0.0005)
        if not any(np.array_equal(same, p) for p, _ in planes):
            planes.append((same, area[same].sum()))
    biggest = max(a for _, a in planes)
    tip = needle.reshape(-1, 3).mean(0)
    best = min((p for p, a in planes if a > 0.3 * biggest),
               key=lambda p: abs((tip - tris[p][0, 0]) @ n[np.nonzero(p)[0][0]]))
    pts = tris[best].reshape(-1, 3)
    axis = (n[best] * area[best, None]).sum(0)
    axis /= np.linalg.norm(axis)
    center = (pts.min(0) + pts.max(0)) / 2
    center = center + ((pts - center) @ axis).mean() * axis
    flat = (pts - center) - np.outer((pts - center) @ axis, axis)
    return center, axis, np.linalg.norm(flat, axis=1).max()


def pod_basis(axis):
    """Pod axes in car space (columns X, Y, Z): +Y into the dash, +Z as near up as it can be."""
    y = axis / np.linalg.norm(axis)
    z = np.array([0.0, 1.0, 0.0]) - y[1] * y
    z /= np.linalg.norm(z)
    return np.stack([np.cross(y, z), y, z], 1)


def face_texture(kind, size):
    sweep, _, scale, name = DIALS[kind]
    im = Image.new('RGB', (size, size), FACE_DARK)
    d = ImageDraw.Draw(im)
    c = (size / 2, size / 2)
    r = size / 2 - size * 0.05
    big = size == BIG_TEX
    d.ellipse([3, 3, size - 3, size - 3], outline=CHROME, width=max(3, size // 80))
    half = sweep / 2
    if kind == 'speedo':
        ticks = [(m / 160, m % 10 == 0) for m in range(0, 161, 5)]
    elif kind == 'tach':
        ticks = [(k / 28, k % 4 == 0) for k in range(29)]
    else:
        ticks = [(k / 8, k % 4 == 0) for k in range(9)]
    for share, major in ticks:
        deg = -half + sweep * share
        col = RED if kind == 'tach' and share >= 6 / 7 or kind == 'fuel' and share == 0 else WHITE
        d.line([_polar(c, r - size * (0.09 if major else 0.045), deg), _polar(c, r, deg)],
               fill=col, width=max(2, size // (60 if major else 130)))
    for label, share in scale:
        deg = -half + sweep * share
        col = RED if kind == 'tach' and share >= 6 / 7 else WHITE
        _text(d, _polar(c, r - size * (0.19 if big else 0.25), deg), label, _font(int(size * (0.105 if big else 0.14))), col)
    _text(d, (c[0], c[1] + size * (0.2 if sweep > 180 else 0.08)), name, _font(int(size * (0.07 if big else 0.13)), True), WHITE)
    return im


def face_mesh(radius):
    """A disk in the pod's X-Z plane at -FACE_LIFT, facing -Y, with UVs over the texture."""
    a = np.linspace(0.0, 2 * math.pi, SEGMENTS, endpoint=False)
    ring = np.stack([np.sin(a), np.zeros_like(a), np.cos(a)], 1) * radius
    tris, uvs = [], []
    for i in range(SEGMENTS):
        p = [np.zeros(3), ring[(i + 1) % SEGMENTS], ring[i]]
        tris.append(p)
        uvs.append([(0.5 + q[0] / (2 * radius), 0.5 - q[2] / (2 * radius)) for q in p])
    tris = np.array(tris) + np.array([0.0, -FACE_LIFT, 0.0])
    nrm = np.tile([0.0, -1.0, 0.0], (len(tris), 3, 1))
    return tris, nrm, np.array(uvs)


def needle_at_rest(pos, rest_deg):
    """A needle's corners (pod frame) turned about the pod's Y so its tip points to rest_deg,
    clockwise from straight up as the driver sees it, and lifted off the face."""
    flat = pos.reshape(-1, 3)
    tip = flat[np.argmax(flat[:, 0] ** 2 + flat[:, 2] ** 2)]
    turn = math.radians(rest_deg) - math.atan2(tip[0], tip[2])
    c, s = math.cos(turn), math.sin(turn)
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    return np.stack([x * c + z * s, y - NEEDLE_LIFT, -x * s + z * c], -1)


def build(dial_tris, needle_tris):
    """The pods from the model's dials and needles (car space, meters): a list of
    (pod name, origin, basis, face radius, kind, needle node name or None, needle corners
    in the pod frame, needle index into needle_tris)."""
    needles = [(needle_tris[i], i) for i in islands(needle_tris)]
    dials = []
    for i in islands(dial_tris):
        mid = dial_tris[i].reshape(-1, 3).mean(0)
        near = min(needles, key=lambda nd: np.linalg.norm(nd[0].reshape(-1, 3).mean(0) - mid))
        dials.append(dial_face(dial_tris[i], near[0]))
    big = sorted([d for d in dials if d[2] > 0.04], key=lambda d: d[0][0])
    small = [d for d in dials if d[2] <= 0.04]
    middle = np.mean([d[0][0] for d in small])
    pods = []
    for kind, dial in zip(BIG, big):
        pods.append((kind, dial))
    for dial in small:
        side = int(dial[0][0] > middle)
        pair = [d for d in small if int(d[0][0] > middle) == side]
        upper = dial[0][1] == max(d[0][1] for d in pair)
        pods.append((SMALL[(side, upper)], dial))
    out = []
    for kind, (center, axis, radius) in pods:
        basis = pod_basis(axis)
        tris, idx = min(needles, key=lambda nd: np.linalg.norm(nd[0].reshape(-1, 3).mean(0) - center))
        local = (tris - center) @ basis
        name = PODS.get(kind, f'dash_{kind}_pod')
        out.append((name, center, basis, radius * FACE_SHARE, kind, NEEDLES.get(kind),
                    needle_at_rest(local, DIALS[kind][1]), idx))
    return out


def face_material(kind, image_index):
    return {'name': f'dash_impala_{kind}_mat', 'doubleSided': True,
            'emissiveFactor': [0.65, 0.65, 0.65], 'emissiveTexture': {'index': image_index},
            'pbrMetallicRoughness': {'baseColorTexture': {'index': image_index},
                                     'metallicFactor': 0.0, 'roughnessFactor': 0.45}}


def face_png(kind):
    return _png(face_texture(kind, BIG_TEX if kind in BIG else SMALL_TEX))


__all__ = ['build', 'face_mesh', 'face_material', 'face_png', 'quaternion']
