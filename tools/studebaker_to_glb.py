#!/usr/bin/env python3
"""Convert the Sketchfab Studebaker (a 1951 Champion Starlight coupe) into a car body GLB.

    python3 -I tools/studebaker_to_glb.py reference/cars/51studebaker/model/studebaker_-_car_model.glb \
        assets/cars/studebaker-champion-1951.glb

Source: "Studebaker - Car Model" by Allie2k, CC-BY-4.0,
https://sketchfab.com/3d-models/studebaker-car-model-c7578ec0f82043e6b392fcdf9b00c743

The download is a Maya scene on a display turntable. The turntable (floor, ring
light, bulbs, posts), the wheels and the front axle beam are left out: the game mounts
its own wheels and draws its own suspension. The wheels are found by geometry: the tires are the Rubber1 meshes that reach the
lowest point of the car, and every mesh that fits inside a tire's box is a wheel part.

The GLB is laid out like the F100's (tools/f100_to_glb.py):

  * one Y-up mesh, nose along +Z, driver's side +X;
  * centered on X and Z, lowest point of the body at Y = 0;
  * real size in meters: scaled evenly to the Champion's 197.5 in length, then the
    width alone stretched to its 70.5 in (the model is narrow for its length); the
    side mirror moves out with the door and keeps its shape;
  * a palette texture, 64 px per color; body paint is white with alpha 1, which
    car_paint_mask.gdshader multiplies by the car's paint, everything else alpha 0;
  * an ORM palette in the same layout (R = AO, G = roughness, B = metallic);
  * every face of an open skin twice, once turned round, because every material is
    double-sided; closed parts whose faces point out (seats, steering wheel, grille
    rings, bumper ends) are drawn once;
  * the glass as a second surface with its own see-through material (GLASS_MATERIAL),
    drawn from both sides, so the paint shader never touches it;
  * the steering wheel as its own `driving_wheel` node, its +Z down the column, so the
    game turns it;
  * the dash from tools/studebaker_dash.py: the Champion's cluster as the speedometer
    pod and an add-on tachometer, as on the other cars' dashes.

The numbers the .car file needs are printed at the end.
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
import studebaker_dash as dash  # noqa: E402

CELL = 64
LENGTH_M = 197.5 * 0.0254
WIDTH_M = 70.5 * 0.0254
BODY = 'aiStandardSurface17'
DROP_MATERIALS = {'Floor', 'Bulb', 'pasted__Light'}
GLASS = 'Glass'
## Clear glass with a faint green tint, as plate glass of the day had; drawn from both
## sides, smooth so it picks up reflections, and left alone by the game's paint code
## because it is see-through.
GLASS_MATERIAL = {
    'name': 'glass',
    'pbrMetallicRoughness': {'baseColorFactor': [0.62, 0.72, 0.70, 0.22],
                             'metallicFactor': 0.0, 'roughnessFactor': 0.04},
    'alphaMode': 'BLEND',
    'doubleSided': True,
}
MIRROR_NODES = {'Side_Mirror_Chrome_0', 'Side_Mirror_Mirror1_0'}
## The steering wheel (rim, spokes and hub): its own node, so the game can turn it. The
## grey column behind it (pCylinder24) stays with the body: it is not on the wheel's axis,
## so it would swing round if it turned.
STEERING_NODES = {'Steering_Wheel_Rubber1_0'}
## The wheel itself (rim and spokes), whose rim sets the axis it turns about.
STEERING_RIM = 'Steering_Wheel_Rubber1_0'
## The driver's eye, in the GLB's frame (body bottom at Y = 0), for aiming the gauges.
EYE = (0.377, 0.95, 0.30)
## The cluster's needle pivot, standing out from the upright dash face (Z 0.86) ahead of
## the driver, and how far its face leans back.
CLUSTER_AT = (0.377, 0.779, 0.835)
CLUSTER_LEAN = 0.0
## The accessory tachometer, clamped on top of the cluster's hood at its right end, in
## front of the windshield (which comes down to the dash at Z 0.9).
TACH_AT = (0.245, 0.933, 0.808)
## The clock pod on the cluster's bottom rail, over the steering column, facing the same
## way as the cluster; the column runs into the back of it, as the pod sat on the real
## car's column. Its middle is 0.0073 above the rail (studebaker_dash.CLOCK_RAIL_TOP).
CLOCK_AT = (0.377, 0.783, 0.811)
## The front axle beam: its ends sit in the wheel wells, where the game's own wheels
## and suspension go.
DROP_NODES = {'polySurface28_Chrome_0'}

PLAIN = (255, round(0.82 * 255), round(0.05 * 255))
## Chrome: fully metallic and nearly mirror smooth, so it reflects the sky instead of
## reading as flat grey paint (metallic 0.5 left half of it diffuse grey).
CHROME = ((240, 240, 244), False, (255, 15, 255))
## (color, paint, (AO, roughness, metallic)) by the scene's material names.
LOOKS = {
    BODY: ((255, 255, 255), True, PLAIN),
    'Chrome': CHROME,
    'Mirror1': CHROME,
    'Sticker': CHROME,
    'Upholstry': ((92, 52, 30), False, (255, 220, 0)),
    'Rubber1': ((16, 16, 16), False, (255, 200, 10)),
    'lambert1': ((150, 150, 150), False, (255, 160, 10)),
    'Headlights1': ((235, 235, 225), False, (255, 40, 30)),
    'RearLights': ((200, 12, 18), False, (255, 60, 10)),
}


def read_glb(path):
    data = open(path, 'rb').read()
    n, = struct.unpack('<I', data[12:16])
    gltf = json.loads(data[20:20 + n])
    binary = data[20 + n + 8:]

    def accessor(i):
        a = gltf['accessors'][i]
        view = gltf['bufferViews'][a['bufferView']]
        kind = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a['componentType']]
        width = {'VEC3': 3, 'VEC2': 2, 'SCALAR': 1}[a['type']]
        start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = view.get('byteStride', 0)
        item = np.dtype(kind).itemsize * width
        if stride and stride != item:
            raw = np.frombuffer(binary, np.uint8, a['count'] * stride, start).reshape(-1, stride)[:, :item]
            arr = raw.copy().view(kind)
        else:
            arr = np.frombuffer(binary, kind, a['count'] * width, start)
        return arr.reshape(-1, width) if width > 1 else arr

    return gltf, accessor


def node_matrix(node):
    if 'matrix' in node:
        return np.array(node['matrix'], np.float64).reshape(4, 4).T
    m = np.eye(4)
    t = node.get('translation', [0, 0, 0])
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    s = node.get('scale', [1, 1, 1])
    r = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m[:3, :3] = r * np.array(s)
    m[:3, 3] = t
    return m


def pieces(gltf, accessor):
    """(node name, material name, triangle corners, corner normals) in world space."""
    out = []

    def walk(i, parent):
        node = gltf['nodes'][i]
        world = parent @ node_matrix(node)
        if 'mesh' in node:
            lin = world[:3, :3]
            flip = np.linalg.det(lin) < 0
            nlin = np.linalg.inv(lin).T
            for prim in gltf['meshes'][node['mesh']]['primitives']:
                pos = accessor(prim['attributes']['POSITION']).astype(np.float64)
                nrm = accessor(prim['attributes']['NORMAL']).astype(np.float64)
                idx = accessor(prim['indices']).astype(np.int64).reshape(-1, 3)
                if flip:
                    idx = idx[:, ::-1]
                pos = pos @ lin.T + world[:3, 3]
                nrm = nrm @ nlin.T
                nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
                mat = gltf['materials'][prim['material']]['name']
                out.append((node['name'], mat, pos[idx], nrm[idx]))
        for c in node.get('children', []):
            walk(c, world)

    for root in gltf['scenes'][gltf.get('scene', 0)]['nodes']:
        walk(root, np.eye(4))
    return out


def box(tris):
    flat = tris.reshape(-1, 3)
    return flat.min(0), flat.max(0)


def inside(lo, hi, outer_lo, outer_hi, margin=0.03):
    return bool(np.all(lo >= outer_lo - margin) and np.all(hi <= outer_hi + margin))


def ring_axis(points):
    """The center and axis of a steering wheel's rim: a circle fitted to the rim's outer
    edge (the farthest point in each 10 degree slice, so the spokes and hub don't pull
    it), refined a few times. The axis points away from the driver (+Z)."""
    center = (points.min(0) + points.max(0)) / 2
    _, _, vt = np.linalg.svd(points - points.mean(0))
    axis = vt[2]
    for _ in range(8):
        u = np.cross(axis, [0.0, 1.0, 0.0])
        u /= np.linalg.norm(u)
        v = np.cross(axis, u)
        q = points - center
        x, y = q @ u, q @ v
        ang = np.degrees(np.arctan2(y, x))
        r = np.hypot(x, y)
        edge = []
        for a0 in range(-180, 180, 10):
            m = np.nonzero((ang >= a0) & (ang < a0 + 10))[0]
            if len(m):
                edge.append(m[np.argmax(r[m])])
        ring = points[edge]
        _, _, vt = np.linalg.svd(ring - ring.mean(0))
        axis = vt[2]
        q = ring - center
        x, y = q @ u, q @ v
        a = np.stack([x, y, np.ones_like(x)], 1)
        (ca, cb, _), *_ = np.linalg.lstsq(a, -(x * x + y * y), rcond=None)
        center = center + (-ca / 2) * u + (-cb / 2) * v
    return center, (axis if axis[2] > 0 else -axis)


def drawn_once(tris, normals):
    """True for a closed part whose faces all wind to match their normals: its inside is
    never seen, so it needs no turned-round copy."""
    _, welded = np.unique(tris.reshape(-1, 3).round(5), axis=0, return_inverse=True)
    f = welded.reshape(-1, 3)
    edges = np.sort(np.stack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]], 1).reshape(-1, 2), 1)
    _, counts = np.unique(edges, axis=0, return_counts=True)
    if np.any(counts != 2):
        return False
    facing = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    agree = np.einsum('ij,ij->i', facing, normals.mean(1)) > 0
    return agree.mean() > 0.98


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('dst')
    ap.add_argument('--name', default='studebaker-champion-1951')
    args = ap.parse_args()

    gltf, accessor = read_glb(args.src)
    parts = [p for p in pieces(gltf, accessor) if p[1] not in DROP_MATERIALS and p[0] not in DROP_NODES]
    floor = min(box(p[2])[0][1] for p in parts)
    tires = [box(p[2]) for p in parts if p[1] == 'Rubber1' and box(p[2])[0][1] < floor + 0.01]
    kept = [p for p in parts if not any(inside(*box(p[2]), *t) for t in tires)]

    body = np.concatenate([p[2].reshape(-1, 3) for p in kept if p[1] == BODY])
    body_lo, body_hi = body.min(0), body.max(0)
    allp = np.concatenate([p[2].reshape(-1, 3) for p in kept])
    lo, hi = allp.min(0), allp.max(0)
    center = (body_lo + body_hi) / 2
    scale = LENGTH_M / (hi[2] - lo[2])
    stretch = WIDTH_M / ((body_hi[0] - body_lo[0]) * scale)

    def to_game(q):
        q = np.asarray(q, np.float64)
        return np.stack([(q[..., 0] - center[0]) * stretch, q[..., 1] - lo[1], q[..., 2] - (lo[2] + hi[2]) / 2], -1) * scale

    rim_src = [t for nm, _, t, _ in kept if nm == STEERING_RIM][0].reshape(-1, 3)
    wheel_x = (rim_src[:, 0].min() + rim_src[:, 0].max()) / 2
    looks = []
    rim_points = None
    groups = {'body': ([], [], []), 'wheel': ([], [], [])}
    glass_pos, glass_nrm = [], []
    once = 0
    for name, mat, tris, normals in kept:
        p = to_game(tris)
        if name in MIRROR_NODES:
            # Moved as a whole by as much as its inner edge moved, so it keeps its shape.
            inner = tris[..., 0].min() - center[0]
            p[..., 0] = (tris[..., 0] - center[0] + inner * (stretch - 1)) * scale
            n = normals
        elif name in STEERING_NODES:
            # Moved out with the stretch by its middle but not stretched itself, so the
            # wheel stays round and turns true.
            p[..., 0] = (tris[..., 0] - center[0] + (wheel_x - center[0]) * (stretch - 1)) * scale
            n = normals
        else:
            n = normals / np.array([stretch, 1.0, 1.0])
            n /= np.linalg.norm(n, axis=-1, keepdims=True)
        if mat == GLASS:
            glass_pos.append(p)
            glass_nrm.append(n)
            continue
        look = LOOKS[mat]
        if look not in looks:
            looks.append(look)
        if drawn_once(tris, normals):
            once += len(p)
        else:
            p = np.concatenate([p, p[:, ::-1]])
            n = np.concatenate([n, -n[:, ::-1]])
        if name == STEERING_RIM:
            rim_points = p.reshape(-1, 3)
        gpos, gnrm, glook = groups['wheel' if name in STEERING_NODES else 'body']
        gpos.append(p)
        gnrm.append(n)
        glook += [looks.index(look)] * len(p)

    grid = math.ceil(math.sqrt(len(looks)))
    size = grid * CELL
    albedo = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    orm = Image.new('RGB', (size, size), PLAIN)
    cells = []
    for i, (color, paint, rough) in enumerate(looks):
        cx, cy = i % grid, i // grid
        cell = (cx * CELL, cy * CELL, cx * CELL + CELL, cy * CELL + CELL)
        albedo.paste(color + ((255,) if paint else (0,)), cell)
        orm.paste(rough, cell)
        cells.append(((cx + 0.5) / grid, (cy + 0.5) / grid))

    def palette_mesh(group, frame=None):
        gpos, gnrm, glook = groups[group]
        pos = np.concatenate(gpos).reshape(-1, 3)
        nrm = np.concatenate(gnrm).reshape(-1, 3)
        if frame is not None:
            origin, basis = frame
            pos = (pos - origin) @ basis
            nrm = nrm @ basis
        uv = np.repeat(np.array([cells[k] for k in glook], np.float32), 3, 0)
        return share_corners(pos.astype(np.float32), nrm.astype(np.float32), uv)

    # The steering wheel's frame: the middle of its rim, +Z along the column toward the dash.
    hub, axis = ring_axis(rim_points)
    across = np.array([1.0, 0.0, 0.0]) - axis[0] * axis
    across /= np.linalg.norm(across)
    wheel_basis = np.stack([across, np.cross(axis, across), axis], 1)

    p, n, uv, index = palette_mesh('body')
    wp, wn, wuv, windex = palette_mesh('wheel', (hub, wheel_basis))
    gp = np.concatenate(glass_pos).reshape(-1, 3).astype(np.float32)
    gn = np.concatenate(glass_nrm).reshape(-1, 3).astype(np.float32)
    gp, gn, _, gindex = share_corners(gp, gn, np.zeros((len(gp), 2), np.float32))

    out = Gltf()
    out.images = [png_bytes(albedo), png_bytes(orm)]
    out.textures = [0, 1]
    out.materials = [{
        'name': args.name + '_palette',
        'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                 'metallicRoughnessTexture': {'index': 1},
                                 'metallicFactor': 1.0, 'roughnessFactor': 1.0},
        'alphaMode': 'OPAQUE'}, GLASS_MATERIAL]
    body_mesh = out.mesh(args.name, [out.primitive(p, n, index, 0, uv), out.primitive(gp, gn, gindex, 1)])
    roots = [out.node(args.name, mesh=body_mesh)]
    wheel_mesh = out.mesh('driving_wheel_mesh', [out.primitive(wp, wn, windex, 0, wuv)])
    roots.append(out.node('driving_wheel', translation=hub, rotation=dash.quaternion(wheel_basis),
                          children=[out.node('driving_wheel_mesh', mesh=wheel_mesh)]))
    roots += add_dash(out)
    out.write(args.dst, roots)

    size_m = p.max(0) - p.min(0)
    print(f'{args.dst}: {len(p) + len(gp)} verts, {len(index) // 3} tris + {len(gindex) // 3} glass '
          f'+ {len(windex) // 3} steering wheel, '
          f'{once} tris drawn once, {len(looks)} colors, '
          f'size {size_m.round(3)} m ({(size_m / 0.0254).round(1)} in), scale {scale:.5f}, width stretch {stretch:.4f}')

    front = [t for t in tires if (t[0][2] + t[1][2]) / 2 > center[2]]
    rear = [t for t in tires if (t[0][2] + t[1][2]) / 2 <= center[2]]
    fz = np.mean([(t[0][2] + t[1][2]) / 2 for t in front])
    rz = np.mean([(t[0][2] + t[1][2]) / 2 for t in rear])
    radius = np.mean([(t[1][1] - t[0][1]) / 2 for t in tires]) * scale
    wheel_y = np.mean([(t[0][1] + t[1][1]) / 2 for t in tires])
    right = max(front, key=lambda t: t[1][0])
    track_half = to_game([(right[0][0] + right[1][0]) / 2, wheel_y, fz])
    print('model tire radius %.3f m (%.1f in diameter)' % (radius, radius * 2 / 0.0254))
    print('wheel centers: x ±%.3f, y %.3f (body bottom = 0), front z %.3f, rear z %.3f, wheelbase %.1f in'
          % (abs(track_half[0]), track_half[1], to_game([0, 0, fz])[2], to_game([0, 0, rz])[2], (fz - rz) * scale / 0.0254))
    print('ground clearance in the model %.3f m' % ((lo[1] - floor) * scale))
    wheel = [pp for pp in kept if pp[0].startswith('Steering_Wheel')][0]
    swl, swh = box(to_game(wheel[2]))
    print('steering wheel', swl.round(3), swh.round(3))


def share_corners(pos, nrm, uv):
    """Index the corners, sharing the ones that match exactly."""
    keyed = {}
    index = np.empty(len(pos), np.uint32)
    for i, key in enumerate(zip(map(tuple, pos.round(5)), map(tuple, nrm.round(4)), map(tuple, uv))):
        index[i] = keyed.setdefault(key, len(keyed))
    order = np.zeros(len(keyed), np.int64)
    order[index] = np.arange(len(pos))
    return pos[order], nrm[order], uv[order], index


def png_bytes(im):
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def add_dash(out):
    """The speedometer and tachometer pods; returns their root nodes."""
    mats = {}
    for key, material in dash.MATERIALS.items():
        mats[key] = len(out.materials)
        out.materials.append(material)
    for key, (material, png) in dash.face_materials().items():
        out.images.append(png)
        out.textures.append(len(out.images) - 1)
        tex = len(out.textures) - 1
        material = dict(material)
        material['pbrMetallicRoughness'] = dict(material['pbrMetallicRoughness'], baseColorTexture={'index': tex})
        material['emissiveTexture'] = {'index': tex}
        mats[key] = len(out.materials)
        out.materials.append(material)

    def part(name, pieces):
        prims = []
        for mat, tris, nrm, uv in pieces:
            pos = tris.reshape(-1, 3).astype(np.float32)
            nn = nrm.reshape(-1, 3).astype(np.float32)
            tex = uv.reshape(-1, 2).astype(np.float32) if uv is not None else np.zeros((len(pos), 2), np.float32)
            pp, nn, tt, idx = share_corners(pos, nn, tex)
            prims.append(out.primitive(pp, nn, idx, mats[mat], tt if uv is not None else None))
        return out.mesh(name, prims)

    def pod(name, parts, needle_name, at, basis, extra=()):
        if needle_name is None:
            children = [out.node(f'{name}_{key}', mesh=part(f'{name}_{key}', [piece])) for key, piece in parts.items()]
            return out.node(name, translation=at, rotation=dash.quaternion(basis), children=children)
        children = []
        for key, piece in parts.items():
            if key == 'needle':
                continue
            children.append(out.node(f'{name}_{key}', mesh=part(f'{name}_{key}', [piece])))
        children.append(out.node(needle_name, mesh=part(needle_name, parts['needle'])))
        children += list(extra)
        return out.node(name, translation=at, rotation=dash.quaternion(basis), children=children)

    lean = math.radians(CLUSTER_LEAN)
    # The GAS pointer: a pod named for its travel (Godot turns the point into "_"), resting
    # at F, its `fuel_needle` slid toward E by the game.
    full_at, travel, pointer = dash.fuel_pointer()
    fuel = out.node(f'dash_fuel_linear_{travel:.4f}_pod', translation=full_at,
                    children=[out.node('fuel_needle', mesh=part('fuel_needle', pointer))])
    cluster = pod('dash_speedo_arch_160_pod', dash.cluster_parts(), 'speedo_needle', CLUSTER_AT,
                  dash.facing_basis((0.0, math.sin(lean), -math.cos(lean))), extra=[fuel])
    toward = np.array(EYE) - np.array(TACH_AT)
    tach = pod('dash_tach_pod', dash.tach_parts(), 'tach_needle', TACH_AT, dash.facing_basis(toward))
    clock = pod('dash_clock_pod', dash.clock_parts(), None, CLOCK_AT,
                dash.facing_basis((0.0, math.sin(lean), -math.cos(lean))))
    return [cluster, tach, clock]


class Gltf:
    """Collects meshes, nodes, materials and images, and writes them as one GLB."""

    def __init__(self):
        self.bin = bytearray()
        self.views, self.accessors, self.meshes, self.nodes = [], [], [], []
        self.materials, self.images, self.textures = [], [], []

    def view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        v = {'buffer': 0, 'byteOffset': len(self.bin), 'byteLength': len(data)}
        if target:
            v['target'] = target
        self.views.append(v)
        self.bin += data
        return len(self.views) - 1

    def accessor(self, arr, kind, bounds=False):
        if kind == 'SCALAR':
            acc = {'bufferView': self.view(arr.astype(np.uint32).tobytes(), 34963), 'componentType': 5125,
                   'count': len(arr), 'type': 'SCALAR'}
        else:
            arr = arr.astype(np.float32)
            acc = {'bufferView': self.view(arr.tobytes(), 34962), 'componentType': 5126,
                   'count': len(arr), 'type': kind}
            if bounds:
                acc['min'] = arr.min(0).tolist()
                acc['max'] = arr.max(0).tolist()
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def primitive(self, pos, nrm, index, material, uv=None):
        attributes = {'POSITION': self.accessor(pos, 'VEC3', True), 'NORMAL': self.accessor(nrm, 'VEC3')}
        if uv is not None:
            attributes['TEXCOORD_0'] = self.accessor(uv, 'VEC2')
        return {'attributes': attributes, 'indices': self.accessor(index, 'SCALAR'), 'material': material}

    def mesh(self, name, primitives):
        self.meshes.append({'name': name, 'primitives': primitives})
        return len(self.meshes) - 1

    def node(self, name, mesh=None, translation=None, rotation=None, children=None):
        nd = {'name': name}
        if mesh is not None:
            nd['mesh'] = mesh
        if translation is not None:
            nd['translation'] = [float(x) for x in translation]
        if rotation is not None:
            nd['rotation'] = [float(x) for x in rotation]
        if children:
            nd['children'] = children
        self.nodes.append(nd)
        return len(self.nodes) - 1

    def write(self, dst, roots):
        images = [{'bufferView': self.view(png), 'mimeType': 'image/png'} for png in self.images]
        while len(self.bin) % 4:
            self.bin.append(0)
        gltf = {
            'asset': {'version': '2.0', 'generator': 'StreetRod3 tools/studebaker_to_glb.py'},
            'scene': 0,
            'scenes': [{'nodes': roots}],
            'nodes': self.nodes,
            'meshes': self.meshes,
            'materials': self.materials,
            'textures': [{'source': i, 'sampler': 0} for i in self.textures],
            'samplers': [{'magFilter': 9729, 'minFilter': 9987}],
            'images': images,
            'accessors': self.accessors,
            'bufferViews': self.views,
            'buffers': [{'byteLength': len(self.bin)}],
        }
        js = json.dumps(gltf, separators=(',', ':')).encode()
        while len(js) % 4:
            js += b' '
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(dst, 'wb') as f:
            f.write(struct.pack('<III', 0x46546C67, 2, total))
            f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
            f.write(struct.pack('<II', len(self.bin), 0x004E4942) + bytes(self.bin))


if __name__ == '__main__':
    main()
