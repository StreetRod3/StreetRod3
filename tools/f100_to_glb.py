#!/usr/bin/env python3
"""Convert the 1970 Ford F100 (f100.3DS, a 3ds Max 3 scene) into a car body GLB.

    python3 tools/f100_to_glb.py F100.3DS assets/cars/ford-f100-1970.glb

The scene's parts sit where its keyframer puts them (read3ds.place); without that the
doors, hood, glass and lights are scattered round the truck. The ground plane, tires
and hubcaps are left out: the game mounts its own wheels. They are found by size and
height, not by name, because 3ds Max renumbers the objects when one is deleted.

The GLB is laid out like the Chevy Styleline's (tools/goxel_to_glb.py):

  * one Y-up mesh, nose along +Z (the scene's -Y), driver's side +X;
  * centered on X and Z, lowest point of the body at Y = 0;
  * real size in meters, scaled evenly so the body is the F100's 79.88 in wide without
    its mirrors (which gives the long-bed truck's wheelbase, about 131 in);
  * a palette texture, 64 px per color; body paint is white with alpha 1, which
    car_paint_mask.gdshader multiplies by the car's paint, everything else alpha 0;
  * an ORM palette in the same layout (R = AO, G = roughness, B = metallic);
  * every face twice, once turned round, because the scene's panels are single skins.

Normals follow the scene's smoothing groups. The numbers the .car file needs (wheel
mounts, ground clearance, height, a driver's head) are printed at the end.
"""
import argparse
import io
import json
import math
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from read3ds import bounds, load, place  # noqa: E402

CELL = 64
WIDTH_M = 79.88 * 0.0254
## The body's sides are inside this; only the mirrors reach past it, and they are not
## counted in the width.
MIRROR_X = 15.0
## Tires touch the scene's floor at Z = 0 and hubcaps reach down near it; the body's
## lowest point is above 5.
WHEEL_BOTTOM_Z = 3.0
## Anything this long is the ground plane.
GROUND_SIZE = 200.0

PLAIN = (255, round(0.82 * 255), round(0.05 * 255))
## (color, paint, (AO, roughness, metallic)) by the scene's material names.
LOOKS = {
    'Material #19': ((255, 255, 255), True, PLAIN),
    'JPEG File': ((59, 59, 59), False, (255, 140, 20)),
    # Fully metallic and nearly mirror smooth, so it reflects like chrome rather than grey paint.
    'Metal_Chrome': ((238, 238, 238), False, (255, 15, 255)),
    'Ground_Water': ((40, 58, 70), False, (255, 13, 60)),
    'LED race Engine ': ((200, 12, 18), False, (255, 60, 10)),
    'LED race Engi1': ((14, 14, 14), False, (255, 230, 0)),
    'LED race Engi2': ((235, 235, 225), False, (255, 40, 30)),
    'LED race Engi3': ((240, 140, 40), False, (255, 60, 10)),
    'Material #411': ((16, 16, 16), False, (255, 200, 10)),
    'Material #401': ((16, 16, 16), False, (255, 160, 10)),
}


def corners(ob):
    """Per face corner: position, normal from the smoothing groups."""
    v = np.array(ob['verts'], np.float64)
    f = np.array(ob['faces'], np.int64)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    smooth = ob['smooth'] or [0] * len(f)
    at = {}
    for i, face in enumerate(f):
        for k in face:
            at.setdefault(int(k), []).append(i)
    normals = np.zeros((len(f), 3, 3))
    for i, face in enumerate(f):
        for c, k in enumerate(face):
            if smooth[i] == 0:
                n = fn[i]
            else:
                n = sum(fn[j] for j in at[int(k)] if smooth[j] & smooth[i])
            length = np.linalg.norm(n)
            normals[i, c] = n / length if length > 1e-12 else (0.0, 0.0, 1.0)
    return v[f], normals


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('dst')
    ap.add_argument('--name', default='ford-f100-1970')
    args = ap.parse_args()

    objects, _ = load(args.src)
    place(args.src, objects)
    kept, tires = [], []
    for ob in objects:
        lo, hi = bounds(ob)
        if hi[0] - lo[0] > GROUND_SIZE:
            continue
        if lo[2] < WHEEL_BOTTOM_Z:
            if 'JPEG File' in ob['groups'] and lo[2] < 0.5:
                tires.append((lo, hi))
            continue
        kept.append(ob)
    # The front tires are one object each; the rear pair is one object.
    front_tires = [t for t in tires if t[1][1] < 0]
    rear_tires = [t for t in tires if t[0][1] > 0]
    front_axle = sum((lo[1] + hi[1]) / 2 for lo, hi in front_tires) / len(front_tires)
    rear_axle = sum((lo[1] + hi[1]) / 2 for lo, hi in rear_tires) / len(rear_tires)

    looks = []
    pos, nrm, look_of, mirror = [], [], [], []
    for ob in kept:
        lo, hi = bounds(ob)
        is_mirror = hi[0] > MIRROR_X or lo[0] < -MIRROR_X
        by_face = [None] * len(ob['faces'])
        for mat, idx in ob['groups'].items():
            for i in idx:
                by_face[i] = mat
        p, n = corners(ob)
        for i, mat in enumerate(by_face):
            if len(set(ob['faces'][i])) < 3:
                continue
            look = LOOKS[mat]
            if look not in looks:
                looks.append(look)
            pos.append(p[i])
            nrm.append(n[i])
            look_of.append(looks.index(look))
            mirror.append(is_mirror)
    # 3ds Max draws both sides of a face and the game culls back faces, so the panels
    # are single skins: without a turned-round copy of each face, the far side of the
    # bed and the inside of the cab show the garage through them.
    pos = np.array(pos)
    nrm = np.array(nrm)
    pos = np.concatenate([pos, pos[:, ::-1]]).reshape(-1, 3)
    nrm = np.concatenate([nrm, -nrm[:, ::-1]]).reshape(-1, 3)
    look_of = look_of + look_of
    mirror = np.repeat(np.array(mirror + mirror), 3)

    # Scene Z-up, nose -Y  ->  game Y-up, nose +Z.  (x, y, z) -> (x, z, -y)
    lo, hi = pos.min(0), pos.max(0)
    body_lo, body_hi = pos[~mirror].min(0), pos[~mirror].max(0)
    scale = WIDTH_M / (body_hi[0] - body_lo[0])
    centre = (body_lo + body_hi) / 2

    def to_game(q):
        q = np.asarray(q, np.float64)
        return np.stack([q[..., 0] - centre[0], q[..., 2] - lo[2], -(q[..., 1] - centre[1])], -1) * scale

    p = to_game(pos).astype(np.float32)
    n = np.stack([nrm[:, 0], nrm[:, 2], -nrm[:, 1]], 1).astype(np.float32)

    grid = math.ceil(math.sqrt(len(looks)))
    size = grid * CELL
    albedo = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    orm = Image.new('RGB', (size, size), PLAIN)
    cells = []
    for i, (color, paint, rough) in enumerate(looks):
        cx, cy = i % grid, i // grid
        box = (cx * CELL, cy * CELL, cx * CELL + CELL, cy * CELL + CELL)
        albedo.paste(color + ((255,) if paint else (0,)), box)
        orm.paste(rough, box)
        cells.append(((cx + 0.5) / grid, (cy + 0.5) / grid))
    uv = np.repeat(np.array([cells[k] for k in look_of], np.float32), 3, 0)

    # Share corners that match exactly.
    keyed = {}
    index = np.empty(len(p), np.uint32)
    for i, key in enumerate(zip(map(tuple, p.round(5)), map(tuple, n.round(4)), map(tuple, uv))):
        index[i] = keyed.setdefault(key, len(keyed))
    order = np.zeros(len(keyed), np.int64)
    order[index] = np.arange(len(p))
    p, n, uv = p[order], n[order], uv[order]

    pngs = []
    for im in (albedo, orm):
        buf = io.BytesIO()
        im.save(buf, 'PNG', optimize=True)
        pngs.append(buf.getvalue())
    write_glb(args.dst, args.name, p, n, uv, index, pngs)

    tris = len(index) // 3
    print(f'{args.dst}: {len(p)} verts, {tris} tris, {len(looks)} colors, size {p.max(0) - p.min(0)} m, '
          f'scale {scale:.6f} m/unit, body {(body_hi[0] - body_lo[0]) * scale / 0.0254:.2f} in wide, '
          f'{(hi[1] - lo[1]) * scale / 0.0254:.1f} in long, wheelbase {(rear_axle - front_axle) * scale / 0.0254:.1f} in')

    # Numbers for the .car file, in game meters with the body's bottom at Y = 0.
    flo, fhi = max(front_tires, key=lambda t: t[1][0])
    rlo, rhi = rear_tires[0]
    radius = (fhi[2] - flo[2]) / 2 * scale
    front = to_game(((flo[0] + fhi[0]) / 2, front_axle, (flo[2] + fhi[2]) / 2))
    rear = to_game((rhi[0] - (fhi[0] - flo[0]) / 2, rear_axle, (rlo[2] + rhi[2]) / 2))
    print('scene wheel radius %.3f m' % radius)
    print('front wheel center', front.round(3), ' rear wheel center', rear.round(3))
    print('body height %.3f m, ground clearance in the scene %.3f m' % ((hi[2] - lo[2]) * scale, (lo[2] - flo[2]) * scale))
    glass = [ob for ob in objects if ob['name'] == 'Driver Gla'][0]
    glo, ghi = bounds(glass)
    print('driver door glass', to_game(glo).round(3), to_game(ghi).round(3))


def write_glb(dst, name, p, n, uv, index, pngs):
    blobs = [p.tobytes(), n.tobytes(), uv.astype(np.float32).tobytes(), index.tobytes()] + pngs
    views, bin_ = [], b''
    for i, blob in enumerate(blobs):
        while len(bin_) % 4:
            bin_ += b'\0'
        view = {'buffer': 0, 'byteOffset': len(bin_), 'byteLength': len(blob)}
        if i < 3:
            view['target'] = 34962
        elif i == 3:
            view['target'] = 34963
        views.append(view)
        bin_ += blob
    while len(bin_) % 4:
        bin_ += b'\0'
    gltf = {
        'asset': {'version': '2.0', 'generator': 'StreetRod3 tools/f100_to_glb.py'},
        'scene': 0,
        'scenes': [{'nodes': [0]}],
        'nodes': [{'name': name, 'mesh': 0}],
        'meshes': [{'name': name, 'primitives': [{
            'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2},
            'indices': 3, 'material': 0}]}],
        'materials': [{
            'name': name + '_palette',
            'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                     'metallicRoughnessTexture': {'index': 1},
                                     'metallicFactor': 1.0, 'roughnessFactor': 1.0},
            'alphaMode': 'OPAQUE'}],
        'textures': [{'source': 0, 'sampler': 0}, {'source': 1, 'sampler': 0}],
        'samplers': [{'magFilter': 9728, 'minFilter': 9987}],
        'images': [{'bufferView': 4, 'mimeType': 'image/png'},
                   {'bufferView': 5, 'mimeType': 'image/png'}],
        'accessors': [
            {'bufferView': 0, 'componentType': 5126, 'count': len(p), 'type': 'VEC3',
             'min': p.min(0).tolist(), 'max': p.max(0).tolist()},
            {'bufferView': 1, 'componentType': 5126, 'count': len(n), 'type': 'VEC3'},
            {'bufferView': 2, 'componentType': 5126, 'count': len(uv), 'type': 'VEC2'},
            {'bufferView': 3, 'componentType': 5125, 'count': len(index), 'type': 'SCALAR'},
        ],
        'bufferViews': views,
        'buffers': [{'byteLength': len(bin_)}],
    }
    js = json.dumps(gltf, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    total = 12 + 8 + len(js) + 8 + len(bin_)
    with open(dst, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        f.write(struct.pack('<II', len(bin_), 0x004E4942) + bin_)


if __name__ == '__main__':
    main()
