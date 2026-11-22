#!/usr/bin/env python3
"""Convert a car from Libau Media's "FREE 1950s Car Variety Pack" into a car body GLB.

    python3 -I tools/variety_pack_to_glb.py hudson-1951 assets/cars/hudson-hornet-1951.glb

Source: "FREE 1950s Car Variety Pack" by Libau Media (robinmikart), CC-BY-4.0,
https://sketchfab.com/3d-models/free-1950s-car-variety-pack-067c3ca92ac0489daadc39ba8b208795

The first argument names a file in reference/cars/varietypack/split/ (written by
tools/split_variety_pack.py) and an entry in CARS. Each car there is one joined mesh:
body, chrome, interior and wheels together, colored mostly by material settings (the
ambientCG images most materials used are not in the download). Blender opens the file
(this script runs itself under `blender -b` for that, so Blender must be on the PATH)
and hands back every triangle with its material and the loose part it belongs to; the
rest is plain Python. In the model's own frame (after the pack scene's 45 degree turn is
taken out) the nose points along -Y, Z is up and the driver's side is +X.

What goes where is found by loose part:

  * the wheels are left out (the game mounts its own): the tires are the parts of the
    tire material that reach the floor, and every part inside a tire's box is a wheel
    part (rim, hubcap, whitewall);
  * the bumpers are every part that lies wholly inside the car's BUMPER boxes, so the
    game can strip them;
  * the steering wheel is the rim part (the biggest part of its material near STEER_AT)
    and every part inside the rim's box; scaled evenly so it stays round, with +Z down
    the column so the game turns it.

The GLB is laid out like the Studebaker's (tools/studebaker_to_glb.py):

  * Y up, nose along +Z, driver's side +X;
  * centered on X and Z, lowest point of the body at Y = 0;
  * real size in meters, each axis on its own: the car's overall length, its width over
    the painted body, and its height from the bottom of the model's tires to the roof;
  * a palette texture, CELL px per color: the body paint is white with alpha 1, which
    car_paint_mask.gdshader multiplies by the car's paint; everything else alpha 0;
  * an ORM palette in the same layout (R = AO, G = roughness, B = metallic);
  * the glass as its own see-through material (GLASS_MATERIAL), so the paint shader
    never touches it, and the plates on their own material with the pack's plate image.

The numbers the .car file needs are printed at the end.
"""
import json
import math
import os
import subprocess
import sys
import tempfile

PACK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'reference', 'cars', 'varietypack')
CELL = 16
IN = 0.0254

## Per car: the real car's size (inches), its paint material, the boxes that hold its
## bumpers (any number of boxes each) and where its steering wheel's rim is, all in the model's frame (meters,
## nose -Y, Z up, driver's side +X).
CARS = {
    # 1951 Hudson Hornet club coupe: 208.5 in long, 77.4 in wide, 60.4 in high on a 124 in
    # wheelbase, 7.10-15 tires (conceptcarz, Series 7A club coupe).
    'hudson-1951': {
        'size_in': (208.5, 77.4, 60.4),
        'paint': {'green_metallic'},
        'bumpers': {
            # The bar with its guards and plate; the two arms that hold it to the frame;
            # the cross bar and the bracket just behind its middle.
            'bumper_front': [((-1.2, -2.9, 0.0), (1.2, -2.30, 0.60)),
                             ((0.38, -2.35, 0.30), (0.6, -1.50, 0.49)),
                             ((-0.6, -2.35, 0.30), (-0.38, -1.50, 0.49)),
                             ((-0.3, -2.35, 0.30), (0.3, -2.10, 0.49))],
            # The bar, then the guards, the plate and its holder between them, which stand
            # taller (between the tail lights, which stay on the body).
            'bumper_rear': [((-1.2, 2.25, 0.0), (1.2, 2.9, 0.60)),
                            ((-0.6, 2.58, 0.0), (0.6, 2.9, 0.72))],
        },
        'steer': ('paint_black', (0.40, -0.455, 1.12)),
    },
    # 1952 Buick Special two-door Deluxe sedan (model 48D): 204 in long, 76.7 in wide,
    # 63.4 in high on a 121.5 in wheelbase (Hometown Buick, model 48D).
    'buick-1952-coupe': {
        'size_in': (204.0, 76.7, 63.4),
        'paint': {'red_paint_metallic'},
        'bumpers': {
            'bumper_front': [((-1.1, -2.6, 0.0), (1.1, -2.05, 0.62)),
                             ((0.35, -2.05, 0.32), (0.6, -1.30, 0.49)),
                             ((-0.6, -2.05, 0.32), (-0.35, -1.30, 0.49)),
                             ((-0.3, -2.05, 0.32), (0.3, -1.80, 0.49))],
            'bumper_rear': [((-1.1, 1.95, 0.0), (1.1, 2.6, 0.62)),
                            ((-0.4, 2.2, 0.0), (0.4, 2.6, 0.66))],
        },
        'steer': ('Metal_painted', (0.36, -0.305, 1.055)),
    },
}

TIRE = 'tyre'
GLASS = {'Glass', 'glass.001', 'Glass_Window_Neutral', 'Glass_Window_Neutral.001'}
PLATE = {'number plate diffuse': 'number_plate_diffuse.png', 'numberplate': 'number_plates.png'}
## Clear glass with a faint green tint, as on the Studebaker.
GLASS_MATERIAL = {
    'name': 'glass',
    'pbrMetallicRoughness': {'baseColorFactor': [0.62, 0.72, 0.70, 0.22],
                             'metallicFactor': 0.0, 'roughnessFactor': 0.04},
    'alphaMode': 'BLEND',
    'doubleSided': True,
}
PLAIN = (255, round(0.82 * 255), round(0.05 * 255))
CHROME = ((240, 240, 244), (255, 15, 255))
## (color, (AO, roughness, metallic)) by the pack's material names; any other material
## takes its color, roughness and metallic from its own settings (or the mean of its
## image, where the image is in the download).
LOOKS = {
    'Metallic': CHROME,
    'chrome_shiny': CHROME,
    'mirror': CHROME,
    'mirror.001': CHROME,
    'aloominum': ((200, 204, 208), (255, 60, 255)),
    'headlight glass': ((235, 235, 225), (255, 40, 30)),
    'tail light': ((200, 12, 18), (255, 60, 10)),
    'paint_black': ((14, 14, 14), (255, 110, 10)),
    'blak': ((10, 10, 10), (255, 140, 10)),
    'Metal_painted': ((14, 14, 14), (255, 110, 10)),
    'CHASSIS': ((22, 22, 22), (255, 200, 30)),
    'lorrymetal': ((30, 24, 22), (255, 180, 30)),
    'grooves': ((40, 40, 40), (255, 120, 200)),
    # The gold script on the Hudson's rear fenders.
    'taxi paint': ((232, 196, 96), (255, 40, 255)),
    'tyre': ((16, 16, 16), (255, 200, 10)),
}


def srgb(c):
    c = max(0.0, min(1.0, c))
    return round(255 * (c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055))


def dump(blend, out):
    """Under Blender: every triangle of the file's one mesh in the model's frame, with its
    normals, UVs, material index and loose part, into an .npz; material settings into
    out.json."""
    import bpy
    import mathutils
    import numpy as np
    bpy.ops.wm.open_mainfile(filepath=blend, load_ui=False)
    obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    me = obj.data
    me.calc_loop_triangles()
    tris = me.loop_triangles
    n = len(tris)
    loops = np.empty(n * 3, np.int64)
    tris.foreach_get('loops', loops)
    mats = np.empty(n, np.int64)
    tris.foreach_get('material_index', mats)
    tv = np.empty(n * 3, np.int64)
    tris.foreach_get('vertices', tv)
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    nrm = np.empty(len(me.loops) * 3)
    me.corner_normals.foreach_get('vector', nrm)
    nrm = nrm.reshape(-1, 3)
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2)
    ev = np.empty(len(me.edges) * 2, np.int64)
    me.edges.foreach_get('vertices', ev)
    parent = np.arange(len(me.vertices))

    def find(a):
        root = a
        while parent[root] != root:
            root = parent[root]
        while parent[a] != root:
            parent[a], a = root, parent[a]
        return root
    for a, b in ev.reshape(-1, 2):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    roots = np.array([find(v) for v in range(len(me.vertices))])
    _, comp = np.unique(roots, return_inverse=True)
    # The pack scene turns every car 45 degrees about Z; that turn is taken out, the
    # small lean it also carries is kept.
    rz = obj.matrix_world.to_euler().z
    m = np.array(mathutils.Matrix.Rotation(-rz, 4, 'Z') @ obj.matrix_world)
    lin = m[:3, :3]
    pos = co[tv] @ lin.T + m[:3, 3]
    normals = nrm[loops] @ np.linalg.inv(lin)
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
    info = []
    for slot in obj.material_slots:
        mat = slot.material
        d = {'name': mat.name if mat else ''}
        if mat and mat.use_nodes:
            bsdf = [nd for nd in mat.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED']
            if bsdf:
                b = bsdf[0]
                d['color'] = list(b.inputs['Base Color'].default_value)[:3]
                d['metallic'] = b.inputs['Metallic'].default_value
                d['roughness'] = b.inputs['Roughness'].default_value
                if b.inputs['Base Color'].is_linked:
                    imgs = [nd.image for nd in mat.node_tree.nodes if nd.type == 'TEX_IMAGE' and nd.image]
                    paths = [bpy.path.abspath(i.filepath) for i in imgs]
                    d['image'] = next((p for p in paths if os.path.exists(p) and 'ormal' not in p
                                       and 'ough' not in p and 'etal' not in p), None)
        info.append(d)
    np.savez(out, pos=pos.reshape(-1, 3, 3), nrm=normals.reshape(-1, 3, 3), uv=uv[loops].reshape(-1, 3, 2),
             mat=mats, part=comp[tv[0::3]])
    with open(out + '.json', 'w') as f:
        json.dump(info, f)


def look(info):
    """(color, ORM) for a material the LOOKS table doesn't name."""
    import numpy as np
    from PIL import Image
    name = info['name'].split('.')[0] if info['name'] not in LOOKS else info['name']
    if name in LOOKS:
        return LOOKS[name]
    if info.get('image'):
        rgb = np.asarray(Image.open(info['image']).convert('RGB').resize((64, 64)), np.float64)
        color = tuple(int(v) for v in rgb.reshape(-1, 3).mean(0).round())
    else:
        color = tuple(srgb(c) for c in info.get('color', (0.5, 0.5, 0.5)))
    rough = round(255 * info.get('roughness', 0.5))
    metal = round(255 * info.get('metallic', 0.0))
    return color, (255, rough, metal)


def build(car, dst):
    import numpy as np
    from PIL import Image
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from studebaker_to_glb import Gltf, ring_axis, share_corners, png_bytes
    from studebaker_dash import quaternion

    cfg = CARS[car]
    blend = os.path.join(PACK, 'split', car + '.blend')
    with tempfile.TemporaryDirectory() as tmp:
        npz = os.path.join(tmp, 'mesh.npz')
        subprocess.run(['blender', '-b', '--factory-startup', '--disable-autoexec', '--python',
                        os.path.abspath(__file__), '--', 'dump', blend, npz],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        data = dict(np.load(npz))
        info = json.load(open(npz + '.json'))
    pos, nrm, uv, mat, part = data['pos'], data['nrm'], data['uv'], data['mat'], data['part']
    names = [d['name'] for d in info]
    nparts = part.max() + 1
    plo = np.full((nparts, 3), np.inf)
    phi = np.full((nparts, 3), -np.inf)
    flat = pos.reshape(-1, 3)
    np.minimum.at(plo, np.repeat(part, 3), flat)
    np.maximum.at(phi, np.repeat(part, 3), flat)

    def inside(p, lo, hi, margin=0.0):
        return bool(np.all(plo[p] >= np.asarray(lo) - margin) and np.all(phi[p] <= np.asarray(hi) + margin))

    floor = flat[:, 2].min()
    tire_mat = names.index(TIRE)
    tires = [p for p in np.unique(part[mat == tire_mat]) if plo[p][2] < floor + 0.01]
    wheel_parts = {p for p in range(nparts) for t in tires if inside(p, plo[t], phi[t], 0.01)}
    keep = ~np.isin(part, list(wheel_parts))

    steer_mat, steer_at = cfg['steer']
    near = [p for p in np.unique(part[mat == names.index(steer_mat)])
            if np.linalg.norm((plo[p] + phi[p]) / 2 - steer_at) < 0.1]
    rim_part = max(near, key=lambda p: np.sum(part == p))
    steer_parts = {p for p in range(nparts) if inside(p, plo[rim_part], phi[rim_part], 0.005)}
    group_of = np.full(nparts, 'body', object)
    for g, boxes in cfg['bumpers'].items():
        for lo, hi in boxes:
            for p in range(nparts):
                if inside(p, lo, hi) and p not in wheel_parts:
                    group_of[p] = g
    for p in steer_parts:
        group_of[p] = 'driving_wheel'

    # The model's frame (nose -Y, Z up) to the game's (Y up, nose +Z, driver's side +X).
    def to_yup(a):
        return np.stack([a[..., 0], a[..., 2], -a[..., 1]], -1)

    pos, nrm = to_yup(pos), to_yup(nrm)
    kept = pos[keep].reshape(-1, 3)
    paint = np.isin(mat, [names.index(n) for n in cfg['paint']])
    body = pos[keep & paint].reshape(-1, 3)
    tire_pos = pos[np.isin(part, tires)].reshape(-1, 3)
    lo, hi = kept.min(0), kept.max(0)
    length_in, width_in, height_in = cfg['size_in']
    scale = np.array([width_in * IN / (body[:, 0].max() - body[:, 0].min()),
                      height_in * IN / (hi[1] - tire_pos[:, 1].min()),
                      length_in * IN / (hi[2] - lo[2])])
    origin = np.array([(body[:, 0].min() + body[:, 0].max()) / 2, lo[1], (lo[2] + hi[2]) / 2])

    def to_game(q):
        return (q - origin) * scale

    even = scale.mean()
    rim = pos[part == rim_part].reshape(-1, 3)
    rim_mid = to_game((rim.min(0) + rim.max(0)) / 2)

    looks = []
    plates = {}
    groups = {}
    for m in np.unique(mat[keep]):
        name = names[m]
        sel_m = keep & (mat == m)
        for g in np.unique(group_of[part[sel_m]]):
            sel = sel_m & (group_of[part] == g)
            if g == 'driving_wheel':
                p = rim_mid + (pos[sel] - origin - rim_mid / scale) * even
                n = nrm[sel]
            else:
                p = to_game(pos[sel])
                n = nrm[sel] / scale
                n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-12)
            gp = groups.setdefault(g, {'palette': [], 'glass': [], 'plate': {}})
            if name in GLASS:
                gp['glass'].append((p, n))
                continue
            if name in PLATE:
                gp['plate'].setdefault(name, []).append((p, n, uv[sel]))
                plates[name] = PLATE[name]
                continue
            lk = (((255, 255, 255), PLAIN), True) if m in [names.index(x) for x in cfg['paint']] else (look(info[m]), False)
            if lk not in looks:
                looks.append(lk)
            gp['palette'].append((p, n, looks.index(lk)))

    grid = math.ceil(math.sqrt(len(looks)))
    size = grid * CELL
    albedo = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    orm = Image.new('RGB', (size, size), PLAIN)
    cells = []
    for i, ((color, rough), is_paint) in enumerate(looks):
        cx, cy = i % grid, i // grid
        box = (cx * CELL, cy * CELL, cx * CELL + CELL, cy * CELL + CELL)
        albedo.paste(tuple(color) + ((255,) if is_paint else (0,)), box)
        orm.paste(tuple(rough), box)
        cells.append(((cx + 0.5) / grid, (cy + 0.5) / grid))

    out = Gltf()
    out.images = [png_bytes(albedo), png_bytes(orm)]
    out.textures = [0, 1]
    out.materials = [{
        'name': car + '_palette',
        'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                 'metallicRoughnessTexture': {'index': 1},
                                 'metallicFactor': 1.0, 'roughnessFactor': 1.0},
        'alphaMode': 'OPAQUE', 'doubleSided': True}, GLASS_MATERIAL]
    plate_mat = {}
    for name, image in sorted(plates.items()):
        im = Image.open(os.path.join(PACK, 'textures', image)).convert('RGB')
        out.images.append(png_bytes(im))
        out.textures.append(len(out.images) - 1)
        plate_mat[name] = len(out.materials)
        out.materials.append({'name': 'plate', 'pbrMetallicRoughness': {
            'baseColorTexture': {'index': len(out.textures) - 1}, 'metallicFactor': 0.3, 'roughnessFactor': 0.5},
            'alphaMode': 'OPAQUE', 'doubleSided': True})

    def primitives(g, frame=None):
        gp = groups.get(g)
        prims = []
        if not gp:
            return prims

        def place(p, n):
            p, n = p.reshape(-1, 3), n.reshape(-1, 3)
            if frame is not None:
                o, b = frame
                p, n = (p - o) @ b, n @ b
            return p.astype(np.float32), n.astype(np.float32)
        if gp['palette']:
            p, n = place(np.concatenate([a for a, _, _ in gp['palette']]), np.concatenate([b for _, b, _ in gp['palette']]))
            u = np.repeat(np.array([cells[k] for a, _, k in gp['palette'] for _ in range(len(a))], np.float32), 3, 0)
            p, n, u, idx = share_corners(p, n, u)
            prims.append(out.primitive(p, n, idx, 0, u))
        if gp['glass']:
            p, n = place(np.concatenate([a for a, _ in gp['glass']]), np.concatenate([b for _, b in gp['glass']]))
            p, n, u, idx = share_corners(p, n, np.zeros((len(p), 2), np.float32))
            prims.append(out.primitive(p, n, idx, 1))
        for name, parts in gp['plate'].items():
            p, n = place(np.concatenate([a for a, _, _ in parts]), np.concatenate([b for _, b, _ in parts]))
            u = np.concatenate([c for _, _, c in parts]).reshape(-1, 2).astype(np.float32).copy()
            u[:, 1] = 1.0 - u[:, 1]
            p, n, u, idx = share_corners(p, n, u)
            prims.append(out.primitive(p, n, idx, plate_mat[name], u))
        return prims

    steer = np.concatenate([a for a, _, _ in groups['driving_wheel']['palette']]).reshape(-1, 3)
    hub, axis = ring_axis(steer)
    across = np.array([1.0, 0.0, 0.0]) - axis[0] * axis
    across /= np.linalg.norm(across)
    wheel_basis = np.stack([across, np.cross(axis, across), axis], 1)

    roots = [out.node(car, mesh=out.mesh(car, primitives('body')))]
    for g in cfg['bumpers']:
        if g in groups:
            roots.append(out.node(g, mesh=out.mesh(g, primitives(g))))
    wheel_mesh = out.mesh('driving_wheel_mesh', primitives('driving_wheel', (hub, wheel_basis)))
    roots.append(out.node('driving_wheel', translation=hub, rotation=quaternion(wheel_basis),
                          children=[out.node('driving_wheel_mesh', mesh=wheel_mesh)]))
    out.write(dst, roots)

    size_m = (hi - lo) * scale
    print(f'{dst}: {int(keep.sum())} tris, {len(looks)} colors, {os.path.getsize(dst) / 1e6:.1f} MB, '
          f'size {size_m.round(3)} m ({(size_m / IN).round(1)} in), scale {scale.round(3)}')
    print('bumper parts:', {g: int(np.sum(group_of == g)) for g in cfg['bumpers']},
          'steering parts:', len(steer_parts), 'wheel parts:', len(wheel_parts))
    w = to_game(tire_pos)
    front, rear = w[w[:, 2] > 0], w[w[:, 2] <= 0]
    radius = (w[:, 1].max() - w[:, 1].min()) / 2
    fz = (front[:, 2].min() + front[:, 2].max()) / 2
    rz = (rear[:, 2].min() + rear[:, 2].max()) / 2
    right = front[front[:, 0] > 0]
    track = (right[:, 0].min() + right[:, 0].max()) / 2
    wheel_y = (w[:, 1].min() + w[:, 1].max()) / 2
    print('model tire radius %.3f m (%.1f in diameter)' % (radius, radius * 2 / IN))
    print('wheel centers: x ±%.3f, y %.3f (body bottom = 0), front z %.3f, rear z %.3f, wheelbase %.1f in'
          % (track, wheel_y, fz, rz, (fz - rz) / IN))
    print('ground clearance in the model %.3f m' % (-w[:, 1].min()))
    print('steering wheel hub', hub.round(3), 'axis', axis.round(3))


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if argv and argv[0] == 'dump':
        dump(argv[1], argv[2])
    else:
        build(argv[0], argv[1])
