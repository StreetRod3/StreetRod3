"""Working gauges for the AC Cobra's instrument panel. Used by tools/cobra_to_glb.py.

The model's panel has seven round dials whose faces, needles included, are painted into
the car's texture; there are no needles of their own. Each dial gets a printed face laid
just over the model's (drawn by tools/impala_dash.py) and a needle made here:

  * the big dial behind the steering wheel, just inboard of its hub, is the speedometer
    (it has the odometer in the texture), 0-160 mph over 250 degrees (the game's needle
    runs to 160; the real one read to 180);
  * the big dial in the middle of the dash is the tachometer, 0-7000 rpm over the same
    250 degrees;
  * the two small dials on the door side of the speedometer are the gas gauge (outer: E
    to F over 90 degrees across the top, its pointer turned back from F as the tank
    empties, a pod named `dash_fuel_arch_90_pod`) and the ammeter;
  * the three small dials over the tachometer are oil pressure, water temperature and
    oil temperature, from the door side in, with pointers that stay put.

The pods follow the Impala's: in a pod's frame the face lies in the X-Z plane facing -Y,
+X to the driver's right and +Z up, and the game turns a needle about the pod's +Y from
where it rests, which is clockwise as the driver sees it.
"""
import numpy as np

import impala_dash
from impala_dash import BIG_TEX, FACE_LIFT, FACE_SHARE, NEEDLE_LIFT, NEEDLES, PODS, SMALL_TEX, pod_basis
from studebaker_dash import _needle, _png

## The Cobra's oil temperature gauge, which the Impala has no face for.
impala_dash.DIALS.setdefault('oiltemp', (120.0, 10.0, [('100', 0.0), ('300', 1.0)], 'OIL °F'))

DOOR_PAIR = ['fuel', 'amp']          # outer first
MIDDLE_ROW = ['oil', 'temp', 'oiltemp']  # from the door side in
## Needle sizes as shares of the face's radius: length, tail, half width.
NEEDLE = (0.82, 0.16, 0.035)
NEEDLE_COLOR = [0.95, 0.93, 0.88, 1.0]


def dial_face(tris):
    """Center, axis (into the dash) and radius of a dial's face from its triangles."""
    cross = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    axis = cross.sum(0)
    axis /= np.linalg.norm(axis)
    if axis[2] < 0:  # into the dash is forward, +Z
        axis = -axis
    pts = tris.reshape(-1, 3)
    center = (pts.min(0) + pts.max(0)) / 2
    center = center + ((pts - center) @ axis).mean() * axis
    flat = (pts - center) - np.outer((pts - center) @ axis, axis)
    return center, axis, float(np.linalg.norm(flat, axis=1).max())


def build(faces):
    """The pods from the dials' face triangles (car space, meters): a list of
    (pod name, origin, basis, face radius, kind, needle node name or None, needle
    corners and normals in the pod frame)."""
    dials = [dial_face(t) for t in faces]
    big = sorted(dials, key=lambda d: -d[2])[:2]
    small = [d for d in dials if not any(d is b for b in big)]
    speedo, tach = sorted(big, key=lambda d: -d[0][0])  # the driver's side is +X
    door = sorted([d for d in small if d[0][0] > speedo[0][0]], key=lambda d: -d[0][0])
    middle = sorted([d for d in small if d[0][0] <= speedo[0][0]], key=lambda d: -d[0][0])
    if len(door) != len(DOOR_PAIR) or len(middle) != len(MIDDLE_ROW):
        raise SystemExit(f'expected 2 small dials by the door and 3 in the middle, '
                         f'found {len(door)} and {len(middle)}')
    pods = [('speedo', speedo), ('tach', tach)] + list(zip(DOOR_PAIR, door)) + list(zip(MIDDLE_ROW, middle))
    out = []
    for kind, (center, axis, radius) in pods:
        radius *= FACE_SHARE
        length, tail, width = (s * radius for s in NEEDLE)
        tris, nrm = _needle(length, tail, width, impala_dash.DIALS[kind][1], -FACE_LIFT - NEEDLE_LIFT)
        out.append((PODS.get(kind, f'dash_{kind}_pod'), center, pod_basis(axis), radius, kind,
                    NEEDLES.get(kind), tris, nrm))
    return out


def face_material(kind, image_index):
    mat = impala_dash.face_material(kind, image_index)
    mat['name'] = f'dash_cobra_{kind}_mat'
    return mat


def needle_material():
    return {'name': 'dash_cobra_needle_mat', 'doubleSided': True,
            'emissiveFactor': [0.5, 0.5, 0.45],
            'pbrMetallicRoughness': {'baseColorFactor': NEEDLE_COLOR, 'metallicFactor': 0.0,
                                     'roughnessFactor': 0.4}}


def face_png(kind):
    return _png(impala_dash.face_texture(kind, BIG_TEX if kind in ('speedo', 'tach') else SMALL_TEX))


face_mesh = impala_dash.face_mesh
