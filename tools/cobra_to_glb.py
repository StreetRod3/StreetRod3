#!/usr/bin/env python3
"""Seal the bottom of super7's AC Cobra and fix its materials.

    python3 -I tools/cobra_to_glb.py reference/cars/cobra/cobra-sealed.glb

Source: "AC Cobra classic" by super7, CC-BY-4.0,
https://sketchfab.com/3d-models/ac-cobra-classic-e6a38042e6e84189bc158682478e8b24
(reference/cars/cobra/source). A 2018 THREE.GLTFExporter file: four meshes under a
root node that scales them by 0.25 and lifts them so the tires stand on Y = 0. In the
meshes' own frame Y is up, the nose points along +X and the car is centered on Z.

The bottom of the car is open or single-sided: the body shell has no floor through
the wheel arches, and where it has one the faces point up into the car, so a viewer
that culls back faces (Godot, most glTF viewers) shows the cockpit, the engine bay and
the inside of the hood from below. The interior mesh already holds the wheel tubs and
the cockpit floor. This adds one plain mesh, "underbody", in a dark matte material: a
floor the length of the car, facing down, that

  * sits at the sills' bottom between the wheels and just inside the body's underside
    ahead of the front wheels and behind the rear ones;
  * through each wheel arch runs out to the existing tub walls and slopes between the
    heights on either side of the arch;
  * stops short of the tips of the nose and tail, which are closed underneath.

Its edges are found by cutting the body shell (and through the arches the interior's
tub walls) across at each station, so it ends on the skin and on the tubs.

The materials are also put right: the export made the paint fully metallic and the
interior half metallic with no map, dimmed every color to 80%, and drew a scratch
texture on the glass at half opacity. Here nothing is metallic, colors are full,
the glass is a plain clear, and every material is two-sided.
"""
import json
import os
import struct
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SOURCE = 'reference/cars/cobra/source/AC Cobra 1.glb'

## Meshes of the source (all in the same frame).
INTERIOR = 0  # interior, tires, wheels, pipes, lamps
BODY = 3      # the outer body shell
## The node all four meshes hang under.
PARENT_NODE = 4

## Raw units (0.25 m each). The ground is at the tires' lowest point.
STEP = 0.1          # floor station spacing along X
SILL_INSET = 0.03   # floor this far above the body's lowest point in a station
EDGE_INSET = 0.04   # floor edges this far inside the skin
TIRE_CLEAR = 0.15   # with no tub wall found, the floor stops this far inboard of the tire
ARCH_CLEAR = 0.3    # the floor narrows this far ahead of and behind each tire
## The floor stops where the body's underside rises more than this above the sills:
## the tips of the nose and tail are closed underneath already, and farther forward
## the floor would show through the grille.
END_RISE = 0.6

UNDERBODY_COLOR = [0.05, 0.05, 0.05, 1.0]


def read_glb(path):
    data = open(path, 'rb').read()
    magic, _, _ = struct.unpack_from('<4sII', data, 0)
    assert magic == b'glTF'
    jlen, jtype = struct.unpack_from('<I4s', data, 12)
    assert jtype == b'JSON'
    gltf = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen, btype = struct.unpack_from('<I4s', data, off)
    assert btype == b'BIN\x00'
    return gltf, bytearray(data[off + 8:off + 8 + blen])


def write_glb(path, gltf, binary):
    js = json.dumps(gltf, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    binary = bytes(binary) + b'\x00' * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, total))
        f.write(struct.pack('<I4s', len(js), b'JSON') + js)
        f.write(struct.pack('<I4s', len(binary), b'BIN\x00') + binary)


TYPES = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}
SIZES = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}


def accessor(gltf, binary, index):
    a = gltf['accessors'][index]
    view = gltf['bufferViews'][a['bufferView']]
    n = SIZES[a['type']]
    return np.frombuffer(binary, TYPES[a['componentType']], a['count'] * n,
                         view.get('byteOffset', 0) + a.get('byteOffset', 0)).reshape(-1, n)


def triangles(gltf, binary, mesh):
    prim = gltf['meshes'][mesh]['primitives'][0]
    pos = accessor(gltf, binary, prim['attributes']['POSITION'])
    idx = accessor(gltf, binary, prim['indices']).ravel()
    return pos[idx].reshape(-1, 3, 3).astype(np.float64)


def cut(tris, x):
    """The body cut by the plane X = x: segments as an array (n, 2, [y, z])."""
    d = tris[:, :, 0] - x
    ends = {}
    for a, b in ((0, 1), (1, 2), (2, 0)):
        da, db = d[:, a], d[:, b]
        hit = np.nonzero(da * db < 0)[0]
        t = (da[hit] / (da[hit] - db[hit]))[:, None]
        for i, q in zip(hit, tris[hit, a, 1:] + t * (tris[hit, b, 1:] - tris[hit, a, 1:])):
            ends.setdefault(i, []).append(q)
    segs = [v for v in ends.values() if len(v) == 2]
    return np.array(segs) if segs else np.zeros((0, 2, 2))


def lowest(segs):
    return segs[:, :, 0].min() if len(segs) else None


def skin_width(segs, y):
    """The farthest |z| at which the slice crosses height y (None if it does not)."""
    if not len(segs):
        return None
    y0, y1 = segs[:, 0, 0], segs[:, 1, 0]
    z0, z1 = segs[:, 0, 1], segs[:, 1, 1]
    hit = ((y0 - y) * (y1 - y) <= 0) & (y0 != y1)
    if not hit.any():
        return None
    t = (y - y0[hit]) / (y1[hit] - y0[hit])
    return float(np.abs(z0[hit] + t * (z1[hit] - z0[hit])).max())


def find_tires(interior):
    """Each axle's tire: center x, radius, bottom y and inner face |z|."""
    v = interior.reshape(-1, 3)
    ground = v[:, 1].min()
    low = v[v[:, 1] < ground + 0.45]
    tires = []
    for front in (False, True):
        q = low[(low[:, 0] > 0) == front]
        xc = (q[:, 0].min() + q[:, 0].max()) / 2
        inner = float(np.abs(q[:, 2]).min())
        outer = float(np.abs(q[:, 2]).max())
        # The top of the tire's inner sidewall (farther out the tub's ledge sits lower
        # than the fender trim, but both are above the tire).
        band = v[(np.abs(v[:, 0] - xc) < 1.0) & (np.abs(v[:, 2]) >= inner)
                 & (np.abs(v[:, 2]) < inner + 0.4)]
        top = float(band[:, 1].max())
        tires.append(dict(x=float(xc), r=(top - ground) / 2, bottom=float(ground), top=top,
                          inner=inner))
    return tires


def tub_wall(interior, x, tire):
    """|z| of the interior's wheel tub wall at station x: the outermost near-vertical
    segment inboard of the tire that reaches down to the floor's height."""
    segs = interior_cuts(interior, x)
    if not len(segs):
        return None
    z = np.abs(segs[:, :, 1])
    y = segs[:, :, 0]
    upright = (np.abs(segs[:, 0, 1] - segs[:, 1, 1]) < 0.05) & (np.abs(y[:, 0] - y[:, 1]) > 0.1)
    inboard = (z.max(1) < tire['inner'] + 0.05) & (z.min(1) > tire['inner'] - 0.8)
    low = y.min(1) < tire['bottom'] + 1.2
    hit = upright & inboard & low
    return float(z[hit].max()) if hit.any() else None


_CUTS = {}


def interior_cuts(interior, x):
    key = round(float(x), 4)
    if key not in _CUTS:
        _CUTS[key] = cut(interior, x)
    return _CUTS[key]


def build_underbody(body, interior, tires):
    x_min, x_max = body[:, :, 0].min() + 0.05, body[:, :, 0].max() - 0.05
    # The sills' bottom: the lowest the body gets between the wheels.
    mid = [lowest(cut(body, x)) for x in np.arange(tires[0]['x'] + 2.5, tires[1]['x'] - 2.5, 0.25)]
    sill = min(m for m in mid if m is not None) + SILL_INSET

    arches = [(t['x'] - t['r'] - ARCH_CLEAR, t['x'] + t['r'] + ARCH_CLEAR, t) for t in tires]

    def arch_of(x):
        for a0, a1, t in arches:
            if a0 <= x <= a1:
                return a0, a1, t
        return None

    def outside(x):
        """(y, half width) of the floor at a station outside the arches."""
        segs = cut(body, x)
        low = lowest(segs)
        if low is None or low > sill + END_RISE:
            return None
        y = max(sill, low + SILL_INSET)
        w = skin_width(segs, y)
        return None if w is None else (y, w - EDGE_INSET)

    ends = {}
    for a0, a1, t in arches:
        before, after = outside(a0 - 1e-3), outside(a1 + 1e-3)
        ends[a0] = (before or (sill, 0))[0], (after or (sill, 0))[0]

    def inside(x, a0, a1, t):
        y0, y1 = ends[a0]
        y = y0 + (y1 - y0) * (x - a0) / (a1 - a0)
        w = tub_wall(interior, x, t)
        if w is None:
            w = t['inner'] - TIRE_CLEAR
        skin = skin_width(cut(body, x), y)
        if skin is not None:
            w = min(w, skin - EDGE_INSET)
        return y, w

    xs = sorted(set(np.round(np.arange(x_min, x_max, STEP), 4)) |
                {v for a0, a1, _ in arches for v in (a0, a1)})
    rows = []
    for x in xs:
        arch = arch_of(x)
        f = inside(x, *arch) if arch else outside(x)
        if f is not None and f[1] > 0:
            rows.append((x, f[0], f[1]))

    quads = [[(xa, ya, -wa), (xb, yb, -wb), (xb, yb, wb), (xa, ya, wa)]
             for (xa, ya, wa), (xb, yb, wb) in zip(rows, rows[1:])]
    return np.array(quads, dtype=np.float64), sill


def quads_to_mesh(quads):
    tris = np.concatenate([quads[:, [0, 1, 2]], quads[:, [0, 2, 3]]])
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    length = np.linalg.norm(n, axis=1)
    keep = length > 1e-9
    tris, n = tris[keep], n[keep] / length[keep, None]
    pos = tris.reshape(-1, 3).astype(np.float32)
    nor = np.repeat(n, 3, axis=0).astype(np.float32)
    return pos, nor


def add_view(gltf, binary, data, target=None):
    while len(binary) % 4:
        binary.append(0)
    view = {'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(data)}
    if target:
        view['target'] = target
    binary.extend(data)
    gltf['bufferViews'].append(view)
    return len(gltf['bufferViews']) - 1


def fix_materials(gltf):
    for m in gltf['materials']:
        pbr = m['pbrMetallicRoughness']
        pbr['metallicFactor'] = 0.0
        if m.get('alphaMode') == 'BLEND':
            pbr['baseColorFactor'] = [1.0, 1.0, 1.0, 0.25]
            pbr['roughnessFactor'] = 0.05
        else:
            pbr['baseColorFactor'] = [1.0, 1.0, 1.0, 1.0]
        m['doubleSided'] = True


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    gltf, binary = read_glb(os.path.join(ROOT, SOURCE))
    body = triangles(gltf, binary, BODY)
    interior = triangles(gltf, binary, INTERIOR)
    tires = find_tires(interior)
    quads, sill = build_underbody(body, interior, tires)
    pos, nor = quads_to_mesh(quads)

    fix_materials(gltf)
    gltf['materials'].append({
        'name': 'underbody',
        'pbrMetallicRoughness': {'baseColorFactor': UNDERBODY_COLOR,
                                 'metallicFactor': 0.0, 'roughnessFactor': 0.9},
        'doubleSided': True,
    })
    pv = add_view(gltf, binary, pos.tobytes(), 34962)
    nv = add_view(gltf, binary, nor.tobytes(), 34962)
    gltf['accessors'] += [
        {'bufferView': pv, 'componentType': 5126, 'count': len(pos), 'type': 'VEC3',
         'min': pos.min(0).tolist(), 'max': pos.max(0).tolist()},
        {'bufferView': nv, 'componentType': 5126, 'count': len(nor), 'type': 'VEC3'},
    ]
    gltf['meshes'].append({'name': 'underbody', 'primitives': [{
        'attributes': {'POSITION': len(gltf['accessors']) - 2,
                       'NORMAL': len(gltf['accessors']) - 1},
        'material': len(gltf['materials']) - 1}]})
    gltf['nodes'].append({'name': 'underbody', 'mesh': len(gltf['meshes']) - 1})
    gltf['nodes'][PARENT_NODE]['children'].append(len(gltf['nodes']) - 1)
    gltf['buffers'][0]['byteLength'] = len(binary) + (-len(binary) % 4)

    write_glb(sys.argv[1], gltf, binary)
    for t, name in zip(tires, ('rear', 'front')):
        print(f"{name} tire: x {t['x']:.2f} radius {t['r']:.2f} top {t['top']:.2f} "
              f"inner face {t['inner']:.2f}")
    print(f'floor at y {sill:.2f}; underbody {len(pos) // 3} triangles -> {sys.argv[1]}')


if __name__ == '__main__':
    main()
