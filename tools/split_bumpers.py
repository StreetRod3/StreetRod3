#!/usr/bin/env python3
"""Split a car body GLB's bumpers out into their own nodes, so the game can strip them.

    python3 -I tools/split_bumpers.py CAR IN.glb [OUT.glb]

CAR is one of the cars below. OUT defaults to IN. The bumpers' triangles move out of the
body's mesh into `bumper_front` and `bumper_rear` nodes (car file `bumpers`), beside the
mesh they came from and with its material and transform, so they look as before. Their
mounting brackets go with them: a bumper is unbolted from the frame with its brackets.
Everything else in the file is kept; the binary is repacked, so data only the old body
mesh used is dropped. A file that already has bumper nodes is refused.

These models had parts added after their converters ran (dashes, steering wheels,
interiors), so the split is done on the finished GLB rather than in the converters, and
each car picks its bumpers its own way:

  * corvette-1960: the Sketchfab model's chrome mesh, by connected piece. The front bumper
    is the two wraparound bars with the bolts on them, the two upright guards, the
    license plate between them and the guards' braces; the rear is the two bars, guards
    included. Model space: Z up, nose toward -Y, in model units.
  * ford-f100-1970: the chrome pieces that lie low at each end of the palette mesh. The
    model has no frame, only a flat black underside, which leaves a slot across each end
    behind the bumper, so what the bumpers hid on the real truck is added to the body in
    the underside's black: at the front the lower radiator support set back behind the
    bumper line, with the frame horns the bumper bolted to standing out of it; at the
    rear the crossmember's face under the bed's sill, with the frame rails' ends. The
    rails are a real F-100's 34 inches apart. At the front corners the dark faces that
    stood in front of the fenders' white lower corners are removed, and the underside's
    lip, which ran out under the bumper, is pulled back flush with the radiator support
    and in from beside the fenders, so the fenders show whole.
  * chevy-styleline-1950: a Goxel voxel model, so by voxel: the chrome voxels low at
    each end and the guards that stand up from them, and the grey brackets inside the
    rear bar. Goxel leaves out the faces between
    touching voxels, so the body's faces against the bumper are added back, or the body
    would show holes where the bumper was.
"""
import argparse
import io
import json
import struct
import sys

import numpy as np
from PIL import Image

COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
ENDS = ('front', 'rear')
## The palette's chrome color in the F100's and the Styleline's palette textures.
PALETTE_CHROME = (238, 238, 238)
## The Styleline's light grey: its frame, and the brackets inside its rear bumper.
STYLELINE_FRAME = (223, 223, 223)


class Glb:
    def __init__(self, path):
        data = open(path, 'rb').read()
        n, = struct.unpack('<I', data[12:16])
        self.gltf = json.loads(data[20:20 + n])
        self.binary = data[20 + n + 8:]
        self.arrays = [self._read(i) for i in range(len(self.gltf['accessors']))]

    def _read(self, i):
        a = self.gltf['accessors'][i]
        if 'sparse' in a or 'bufferView' not in a:
            sys.exit('sparse or empty accessors are not handled')
        view = self.gltf['bufferViews'][a['bufferView']]
        kind = COMPONENT[a['componentType']]
        width = WIDTH[a['type']]
        start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        item = np.dtype(kind).itemsize * width
        stride = view.get('byteStride', 0)
        if stride and stride != item:
            raw = np.frombuffer(self.binary, np.uint8, a['count'] * stride, start).reshape(-1, stride)[:, :item]
            arr = raw.copy().view(kind)
        else:
            arr = np.frombuffer(self.binary, kind, a['count'] * width, start).copy()
        return arr.reshape(-1, width) if width > 1 else arr

    def node_index(self, name):
        found = [i for i, n in enumerate(self.gltf['nodes']) if n.get('name') == name]
        if len(found) != 1:
            sys.exit(f'expected one node named {name}, found {len(found)}')
        return found[0]

    def parent_of(self, index):
        for i, n in enumerate(self.gltf['nodes']):
            if index in n.get('children', []):
                return i
        return None

    def triangles(self, prim):
        """Corner positions and the index triples of a primitive."""
        pos = self.arrays[prim['attributes']['POSITION']].astype(np.float64)
        idx = self.arrays[prim['indices']].astype(np.int64).reshape(-1, 3)
        return pos, idx

    def image(self, texture):
        img = self.gltf['images'][self.gltf['textures'][texture]['source']]
        view = self.gltf['bufferViews'][img['bufferView']]
        start = view.get('byteOffset', 0)
        return np.array(Image.open(io.BytesIO(self.binary[start:start + view['byteLength']])).convert('RGBA'))

    def add_accessor(self, arr, like):
        """A new accessor holding `arr`, typed like accessor `like` (indices: uint32)."""
        old = self.gltf['accessors'][like] if like is not None else {'componentType': 5125, 'type': 'SCALAR'}
        acc = {'componentType': old['componentType'], 'type': old['type'], 'count': len(arr)}
        if old.get('normalized'):
            acc['normalized'] = True
        self.gltf['accessors'].append(acc)
        self.arrays.append(np.ascontiguousarray(arr, COMPONENT[old['componentType']]))
        return len(self.arrays) - 1

    def sub_primitive(self, prim, keep, extra=None):
        """`prim` cut down to the triangles in mask `keep`, its corners compacted, with
        `extra` triangles added: {attribute: array of corners, three a triangle}."""
        idx = self.arrays[prim['indices']].astype(np.int64).reshape(-1, 3)[keep]
        used, flat = np.unique(idx.reshape(-1), return_inverse=True)
        out = {k: v for k, v in prim.items() if k not in ('attributes', 'indices')}
        out['attributes'] = {}
        added = 0
        for name, acc in prim['attributes'].items():
            arr = self.arrays[acc][used]
            if extra:
                arr = np.concatenate([arr, extra[name].astype(arr.dtype)])
                added = len(extra[name])
            out['attributes'][name] = self.add_accessor(arr, acc)
        flat = np.concatenate([flat, len(used) + np.arange(added)])
        out['indices'] = self.add_accessor(flat.astype(np.uint32), None)
        return out

    def write(self, path):
        """Writes every accessor in use and every image, tightly packed in one buffer."""
        g = self.gltf
        in_use = set()
        for mesh in g['meshes']:
            for prim in mesh['primitives']:
                in_use.update(prim['attributes'].values())
                in_use.add(prim['indices'])
                for target in prim.get('targets', []):
                    in_use.update(target.values())
        remap = {old: new for new, old in enumerate(sorted(in_use))}
        blob = bytearray()
        views, accessors = [], []

        def view(data, target=None):
            while len(blob) % 4:
                blob.append(0)
            v = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)}
            if target:
                v['target'] = target
            views.append(v)
            blob.extend(data)
            return len(views) - 1

        index_accessors = {p['indices'] for m in g['meshes'] for p in m['primitives']}
        for old in sorted(in_use):
            a = dict(g['accessors'][old])
            arr = self.arrays[old]
            a.pop('byteOffset', None)
            a['count'] = len(arr)
            a['bufferView'] = view(arr.tobytes(), 34963 if old in index_accessors else 34962)
            a.pop('min', None)
            a.pop('max', None)
            if a['componentType'] == 5126 and a['type'] in ('VEC3', 'VEC2', 'SCALAR', 'VEC4'):
                flat = arr.reshape(len(arr), -1)
                a['min'] = flat.min(0).tolist()
                a['max'] = flat.max(0).tolist()
            accessors.append(a)
        for mesh in g['meshes']:
            for prim in mesh['primitives']:
                prim['attributes'] = {k: remap[v] for k, v in prim['attributes'].items()}
                prim['indices'] = remap[prim['indices']]
                if 'targets' in prim:
                    prim['targets'] = [{k: remap[v] for k, v in t.items()} for t in prim['targets']]
        for img in g.get('images', []):
            if 'bufferView' in img:
                old = g['bufferViews'][img['bufferView']]
                start = old.get('byteOffset', 0)
                img['bufferView'] = view(self.binary[start:start + old['byteLength']])
        while len(blob) % 4:
            blob.append(0)
        g['accessors'] = accessors
        g['bufferViews'] = views
        g['buffers'] = [{'byteLength': len(blob)}]
        js = json.dumps(g, separators=(',', ':')).encode()
        while len(js) % 4:
            js += b' '
        with open(path, 'wb') as f:
            f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
            f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
            f.write(struct.pack('<II', len(blob), 0x004E4942) + bytes(blob))


def pieces(pos, idx, decimals=4):
    """Each triangle's connected piece, corners joined where their positions match."""
    _, weld = np.unique(pos.round(decimals), axis=0, return_inverse=True)
    corners = weld.reshape(-1)[idx]
    parent = np.arange(corners.max() + 1)

    def find(a):
        root = a
        while parent[root] != root:
            root = parent[root]
        while parent[a] != root:
            parent[a], a = root, parent[a]
        return root

    for a, b, c in corners:
        ra = find(a)
        parent[find(b)] = ra
        parent[find(c)] = ra
    roots = np.array([find(a) for a in corners[:, 0]])
    return np.unique(roots, return_inverse=True)[1].reshape(-1)


def piece_boxes(tris, label):
    return [(tris[label == p].reshape(-1, 3).min(0), tris[label == p].reshape(-1, 3).max(0))
            for p in range(label.max() + 1)]


def palette_colors(glb, prim):
    """Each triangle's palette color (RGB) from its first corner's texture coordinate."""
    tex = glb.gltf['materials'][prim['material']]['pbrMetallicRoughness']['baseColorTexture']['index']
    albedo = glb.image(tex)
    h, w = albedo.shape[:2]
    uv = glb.arrays[prim['attributes']['TEXCOORD_0']]
    first = glb.arrays[prim['indices']].astype(np.int64).reshape(-1, 3)[:, 0]
    x = np.clip((uv[first, 0] * w).astype(int), 0, w - 1)
    y = np.clip((uv[first, 1] * h).astype(int), 0, h - 1)
    return albedo[y, x, :3]


def corvette(glb, prim):
    pos, idx = glb.triangles(prim)
    tris = pos[idx]
    label = pieces(pos, idx)
    boxes = piece_boxes(tris, label)
    bars = [p for p, (lo, hi) in enumerate(boxes) if lo[1] < -110 and lo[2] > 18 and hi[2] < 24]
    mid_x = np.mean([(boxes[p][0][0] + boxes[p][1][0]) / 2 for p in bars])
    # The guards, the plate between them and their braces, round the middle of the nose.
    middle = [p for p, (lo, hi) in enumerate(boxes)
              if lo[1] < -110 and hi[2] < 24 and abs((lo[0] + hi[0]) / 2 - mid_x) < 14]
    rear = [p for p, (lo, hi) in enumerate(boxes) if lo[1] > 70 and hi[2] < 29]
    front = sorted(set(bars + middle))
    for name, chosen in (('front', front), ('rear', rear)):
        print(f'  {name}: {len(chosen)} pieces, {int(np.isin(label, chosen).sum())} triangles')
    return {'front': np.isin(label, front), 'rear': np.isin(label, rear)}, None


def f100(glb, prim):
    pos, idx = glb.triangles(prim)
    tris = pos[idx]
    chrome = np.all(palette_colors(glb, prim) == PALETTE_CHROME, axis=1)
    label = np.full(len(idx), -1)
    label[chrome] = pieces(pos, idx[chrome])
    lo_z, hi_z = pos[:, 2].min(), pos[:, 2].max()
    masks = {end: np.zeros(len(idx), bool) for end in ENDS}
    for p in range(label.max() + 1):
        box = tris[label == p].reshape(-1, 3)
        lo, hi = box.min(0), box.max(0)
        if hi[1] < 0.25 and lo[2] > hi_z - 0.3:
            masks['front'] |= label == p
        elif hi[1] < 0.25 and hi[2] < lo_z + 0.3:
            masks['rear'] |= label == p
    for end in ENDS:
        print(f'  {end}: {int(masks[end].sum())} triangles')
    # The dark faces at the front corners stand in front of the fenders' white lower
    # corners, which the bumper's ends wrapped round; they go, so the fenders show.
    colors = palette_colors(glb, prim)
    c = tris.mean(1)
    masks['drop'] = (np.all(colors == F100_CORNER_DARK, axis=1) & (np.abs(c[:, 0]) > F100_PANEL_X - 0.03)
                     & (c[:, 1] < 0.205) & (c[:, 2] > 2.4))
    # The underside's front lip ran out under the bumper: back flush with the radiator
    # support, and its corners in from beside the fenders' lower edges.
    under = np.all(colors == F100_FRONT_UNDERSIDE, axis=1) & (c[:, 2] > 2.3)
    p = glb.arrays[prim['attributes']['POSITION']]
    corners = np.unique(glb.arrays[prim['indices']].astype(np.int64).reshape(-1, 3)[under].reshape(-1))
    corners = corners[p[corners, 2] > 2.45]
    p[corners, 2] = np.minimum(p[corners, 2], F100_PANEL_FRONT)
    p[corners, 0] = np.clip(p[corners, 0], -F100_PANEL_X, F100_PANEL_X)
    print(f'  dark corner faces: {int(masks["drop"].sum())}; underside lip: {len(corners)} corners moved')
    return masks, f100_frame(glb, prim)


## The F100's frame ends, in meters in the body's space (nose +Z), as boxes (low corner,
## high corner). The rails are 2.5 in wide and their centers 31.5 in apart, 34 in outside.
F100_RAIL_X = 0.40
F100_RAIL_HALF = 0.032
## How far out the radiator support reaches: inside the fenders' skins (0.76 m out at the
## bottom), so the fenders' white lower corners show whole beside it.
F100_PANEL_X = 0.75
## The radiator support's front face.
F100_PANEL_FRONT = 2.565
F100_FRAME = [
    # Lower radiator support: across between the fenders and inside them, back from the
    # old bumper line, from the underside up behind the valance.
    ((-F100_PANEL_X, 0.03, F100_PANEL_FRONT - 0.02), (F100_PANEL_X, 0.215, F100_PANEL_FRONT)),
    # Front frame horns, out to where the bumper's brackets bolted on.
    ((-F100_RAIL_X - F100_RAIL_HALF, 0.05, 2.40), (-F100_RAIL_X + F100_RAIL_HALF, 0.20, 2.635)),
    ((F100_RAIL_X - F100_RAIL_HALF, 0.05, 2.40), (F100_RAIL_X + F100_RAIL_HALF, 0.20, 2.635)),
    # Rear crossmember's face under the sill, inside the bed's lower edge (0.89 m out at
    # its height), and the rails' ends.
    ((-0.86, 0.125, -2.48), (0.86, 0.225, -2.46)),
    ((-F100_RAIL_X - F100_RAIL_HALF, 0.09, -2.505), (-F100_RAIL_X + F100_RAIL_HALF, 0.235, -2.25)),
    ((F100_RAIL_X - F100_RAIL_HALF, 0.09, -2.505), (F100_RAIL_X + F100_RAIL_HALF, 0.235, -2.25)),
]
## The underside's black in the F100's palette, the front's own black, and the dark grey
## of the faces at the front corners.
F100_UNDERSIDE = (16, 16, 16)
F100_FRONT_UNDERSIDE = (14, 14, 14)
F100_CORNER_DARK = (59, 59, 59)


def f100_frame(glb, prim):
    """F100_FRAME's boxes as extra triangles, in the underside's palette color."""
    black = np.nonzero(np.all(palette_colors(glb, prim) == F100_UNDERSIDE, axis=1))[0]
    if not len(black):
        sys.exit('no underside color in the palette')
    corner = glb.arrays[prim['indices']][black[0] * 3]
    uv = glb.arrays[prim['attributes']['TEXCOORD_0']][corner]
    pos, nrm = [], []
    for lo, hi in F100_FRAME:
        p, n = box_triangles(np.array(lo), np.array(hi))
        pos.append(p)
        nrm.append(n)
    pos = np.concatenate(pos)
    print(f'  frame: {len(F100_FRAME)} boxes, {len(pos) // 3} triangles')
    return {'POSITION': pos, 'NORMAL': np.concatenate(nrm), 'TEXCOORD_0': np.tile(uv, (len(pos), 1))}


def box_triangles(lo, hi):
    """A box's 12 triangles, wound to face out, and their corners' normals."""
    pos, nrm = [], []
    for axis in range(3):
        for sign in (-1, 1):
            quad = face_quad(np.zeros(3, int), axis, sign, np.zeros(3), 1.0) * (hi - lo) + lo
            n = np.zeros(3)
            n[axis] = sign
            for k in (0, 1, 2, 0, 2, 3):
                pos.append(quad[k])
                nrm.append(n)
    return np.array(pos), np.array(nrm)


## The six directions out of a voxel, as (axis, sign).
DIRECTIONS = [(a, s) for a in range(3) for s in (-1, 1)]


def styleline(glb, prim):
    pos, idx = glb.triangles(prim)
    tris = pos[idx]
    normal = glb.arrays[prim['attributes']['NORMAL']].astype(np.float64)[idx].mean(1)
    xs = np.unique(pos[:, 0].round(5))
    step = np.diff(xs)
    size = float(np.median(step[step > 1e-4]))
    origin = pos.min(0)
    cell = np.floor((tris.mean(1) - normal * size * 0.5 - origin) / size + 1e-6).astype(int)
    colors = palette_colors(glb, prim)
    chrome = np.all(colors == PALETTE_CHROME, axis=1)
    frame = np.all(colors == STYLELINE_FRAME, axis=1)
    top = cell.max(0)
    mid_x = top[0] / 2
    x, y, z = cell[:, 0], cell[:, 1], cell[:, 2]
    # The bars low at each end, and the guards that stand up from them: in front of the
    # grille at the nose (which is two voxels further back), at the very back at the tail,
    # where the one-sided chrome strip up the fender's edge is kept. The rear bar has its
    # brackets inside it in the frame's grey; the frame's crossmember behind it stays, as
    # do the frame horns behind the front bar.
    front = chrome & (z >= top[2] - 20) & ((y <= 11) | ((y <= 17) & (z >= top[2] - 2)))
    rear = (chrome & (z <= 10) & ((y <= 8) | ((y <= 17) & (z <= 4) & (np.abs(x - mid_x) < 30)))) \
        | (frame & (z <= 7) & (y <= 8))
    masks = {'front': front, 'rear': rear}

    # Fill the body's faces against the bumper. A voxel's faces are the triangles facing
    # out of it; a side with none is against another voxel.
    faces = {}
    for t, (c, n) in enumerate(zip(map(tuple, cell), np.rint(normal).astype(int))):
        axis = int(np.argmax(np.abs(n)))
        faces.setdefault(c, set()).add((axis, int(np.sign(n[axis]))))
    owner = {}
    for t, c in enumerate(map(tuple, cell)):
        owner.setdefault(c, t)
    gone = set()
    for end in ENDS:
        gone.update(map(tuple, cell[masks[end]]))
    # Voxels with no faces at all, inside the bumper, are gone with it: a bumper voxel's
    # side with no face is against another solid voxel, a bumper one if it is not drawn
    # and lies where the bumpers do.
    def bumper_place(c):
        return c[1] <= 17 and (c[2] >= top[2] - 20 or c[2] <= 10)

    frontier = list(gone)
    while frontier:
        c = frontier.pop()
        for axis, sign in DIRECTIONS:
            if (axis, sign) in faces.get(c, ()):
                continue
            n = list(c)
            n[axis] += sign
            n = tuple(n)
            if n not in faces and n not in gone and bumper_place(n):
                gone.add(n)
                frontier.append(n)
    attrs = {name: [] for name in prim['attributes']}
    uv_of = glb.arrays[prim['attributes']['TEXCOORD_0']]
    corners_of = idx
    added = 0
    for c, sides in faces.items():
        if c in gone:
            continue
        for axis, sign in DIRECTIONS:
            n = list(c)
            n[axis] += sign
            if (axis, sign) in sides or tuple(n) not in gone:
                continue
            quad = face_quad(np.array(c), axis, sign, origin, size)
            nrm = np.zeros(3)
            nrm[axis] = sign
            uv = uv_of[corners_of[owner[c], 0]]
            for tri in ((0, 1, 2), (0, 2, 3)):
                for k in tri:
                    for name in attrs:
                        if name == 'POSITION':
                            attrs[name].append(quad[k])
                        elif name == 'NORMAL':
                            attrs[name].append(nrm)
                        elif name.startswith('TEXCOORD'):
                            attrs[name].append(uv)
                        else:
                            sys.exit(f'cannot fill attribute {name}')
            added += 1
    print(f'  voxel {size:.5f} m; front {int(front.sum())}, rear {int(rear.sum())} triangles; '
          f'{len(gone)} voxels go, {added} body faces filled in')
    extra = {name: np.array(v, np.float64).reshape(-1, len(v[0]) if v else 3) for name, v in attrs.items()}
    return masks, extra


def face_quad(c, axis, sign, origin, size):
    """The four corners of voxel `c`'s side facing (axis, sign), wound to face out."""
    u, v = [a for a in range(3) if a != axis]
    base = c.astype(np.float64).copy()
    if sign > 0:
        base[axis] += 1
    corners = []
    for du, dv in ((0, 0), (1, 0), (1, 1), (0, 1)):
        p = base.copy()
        p[u] += du
        p[v] += dv
        corners.append(origin + p * size)
    corners = np.array(corners)
    out = np.cross(corners[1] - corners[0], corners[2] - corners[0])
    if out[axis] * sign < 0:
        corners = corners[::-1]
    return corners


CARS = {
    'corvette-1960': ('Object_2', corvette),
    'ford-f100-1970': ('ford-f100-1970', f100),
    'chevy-styleline-1950': ('styleline-1950', styleline),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('car', choices=sorted(CARS))
    ap.add_argument('src')
    ap.add_argument('dst', nargs='?')
    args = ap.parse_args()
    glb = Glb(args.src)
    g = glb.gltf
    if any(n.get('name', '').startswith('bumper_') for n in g['nodes']):
        sys.exit(f'{args.src} already has bumper nodes')
    node_name, choose = CARS[args.car]
    body = glb.node_index(node_name)
    mesh = g['meshes'][g['nodes'][body]['mesh']]
    if len(mesh['primitives']) != 1:
        sys.exit(f'{node_name} has {len(mesh["primitives"])} primitives, expected one')
    prim = mesh['primitives'][0]
    print(f'{args.src}: {node_name}')
    masks, extra = choose(glb, prim)
    keep = ~(masks['front'] | masks['rear'] | masks.get('drop', False))
    new_nodes = []
    for end in ENDS:
        if not masks[end].any():
            sys.exit(f'no {end} bumper found')
        g['meshes'].append({'name': f'bumper_{end}', 'primitives': [glb.sub_primitive(prim, masks[end])]})
        node = {k: v for k, v in g['nodes'][body].items() if k in ('translation', 'rotation', 'scale', 'matrix')}
        node['name'] = f'bumper_{end}'
        node['mesh'] = len(g['meshes']) - 1
        g['nodes'].append(node)
        new_nodes.append(len(g['nodes']) - 1)
    mesh['primitives'] = [glb.sub_primitive(prim, keep, extra)]
    parent = glb.parent_of(body)
    if parent is None:
        g['scenes'][g.get('scene', 0)]['nodes'] += new_nodes
    else:
        g['nodes'][parent]['children'] += new_nodes
    glb.write(args.dst or args.src)
    print(f'wrote {args.dst or args.src}')


if __name__ == '__main__':
    main()
