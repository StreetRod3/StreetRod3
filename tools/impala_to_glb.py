#!/usr/bin/env python3
"""Convert the Sketchfab 1967 Chevrolet Impala (a four-door hardtop) into a car body GLB.

    python3 -I tools/impala_to_glb.py reference/cars/impala-1967/chevrolet-impala-1967.zip \
        assets/cars/impala-1967.glb

Source: "Chevrolet Impala 1967" by Eques_inferno, CC-BY-4.0,
https://sketchfab.com/3d-models/chevrolet-impala-1967-bce35ef0c10d41fdb3f7d8c4225144d2

The download is an FBX (source/Exp1.fbx) with Substance Painter textures. Blender reads
the FBX (this script runs itself under `blender -b` for that, so Blender must be on the
PATH) and hands back every mesh's triangles in world space; the rest is plain Python.

The model's wheels are left out: the game mounts its own wheels. Their centers set the
wheel positions printed at the end.

The GLB is laid out like the Studebaker's (tools/studebaker_to_glb.py):

  * Y up, nose along +Z, driver's side +X;
  * centered on X and Z, lowest point of the body at Y = 0;
  * real size in meters, each axis on its own: 213.2 in long, 79.9 in wide and 55.4 in
    from the bottom of the model's tires to the roof (the model is about 3% wide and
    tall for its length); the steering wheel is scaled evenly so it stays round;
  * the model's own textures, at TEXTURE px: the body's black paint, and the dirt
    over it, is plain white with alpha 1, which car_paint_mask.gdshader multiplies by
    the car's paint, so the paint is clean; the tan inside faces and every other
    material have alpha 0 and keep their colors;
  * an ORM texture per material (R = AO, G = roughness, B = metallic), which is what
    the paint shader reads, and the normal maps turned from DirectX to OpenGL;
  * the glass as its own see-through material, so the paint shader never touches it;
  * the bumpers as `bumper_front` and `bumper_rear` nodes so the game can strip them;
  * the steering wheel as its own `driving_wheel` node, its +Z down the column;
  * the panel's blank dials as working gauges with printed faces (tools/impala_dash.py).

The plates in the download carry a real car's registration; their lettering is
painted out (PLATE) and the plate keeps its worn finish.

The numbers the .car file needs are printed at the end.
"""
import io
import os
import subprocess
import sys
import tempfile
import zipfile

LENGTH_M = 213.2 * 0.0254
WIDTH_M = 79.9 * 0.0254
HEIGHT_M = 55.4 * 0.0254
TEXTURE = 1024
FBX = 'source/Exp1.fbx'

## Mesh objects by FBX name. The wheels (all four in Wheel_LP) are dropped.
WHEEL = 'Wheel_LP'
DROP = {'Wheel_LP', 'CWheel_LP', 'Bolt_LP'}
## The front bumper with its guards, parking lamps and plate; the rear with its plate.
BUMPERS = {
    'bumper_front': {'FrontBump_LP', 'frontBumpTooth_LP', 'ColorLamp_LP', 'ID_LP'},
    'bumper_rear': {'Backbump_LP', 'IDBack_LP'},
}
## The rim and the spokes with the horn button; the column and the turn-signal lever
## stay with the body.
STEERING = {'DonutDrive_LP', 'BracketDrive_LP'}
STEERING_RIM = 'DonutDrive_LP'
## The panel's dials and their needles, which become the working gauges (tools/impala_dash.py).
DIALS = 'BaseClock_LP'
NEEDLES = 'ArrowClock_LP'
BODY = 'UpCar_M1'
GLASS = 'Window_M'
## The body texture is gloss black paint (about 2/255) with dirt and panel seams over it
## up to about 50; the inside faces of the panels are tan (50-100, plainly brown).
## Everything that isn't tan is clean paint: the dirt is left off. The normal map has the
## dirt's grit sculpted in as well (in the wheel wells and along the rockers); where at
## least GRIT_SHARE of the texels around (GRIT_RADIUS px) were dirtier than DIRTY, it is
## smoothed out, which leaves the thin panel seams alone.
DIRTY = 8.0
GRIT_RADIUS = 10
GRIT_SHARE = 0.3
## Detail in the body's normal map wider than this (px at 2048) is dropped on the paint.
SEAM_RADIUS = 12
## The plate in FrontChromes_M (2048 px texture): its flat face inside the rim.
PLATE = (1408, 1558, 1662, 1958)
PLATE_TEXTURE = 'FrontChromes_M'


def dump(fbx, out):
    """Under Blender: every mesh's triangle corners in world space, with normals and
    UVs, by object, into an .npz."""
    import bpy
    import numpy as np
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fbx)
    arrays = {}
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        me = o.data
        me.calc_loop_triangles()
        tris = me.loop_triangles
        n = len(tris)
        loops = np.empty(n * 3, np.int64)
        tris.foreach_get('loops', loops)
        mats = np.empty(n, np.int64)
        tris.foreach_get('material_index', mats)
        verts = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get('vertex_index', verts)
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get('co', co)
        co = co.reshape(-1, 3)
        nrm = np.empty(len(me.loops) * 3)
        me.corner_normals.foreach_get('vector', nrm)
        nrm = nrm.reshape(-1, 3)
        uv = np.empty(len(me.loops) * 2)
        me.uv_layers.active.data.foreach_get('uv', uv)
        uv = uv.reshape(-1, 2)
        m = np.array(o.matrix_world)
        lin = m[:3, :3]
        pos = co[verts[loops]] @ lin.T + m[:3, 3]
        normals = nrm[loops] @ np.linalg.inv(lin)
        normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
        order = np.arange(n * 3).reshape(-1, 3)
        if np.linalg.det(lin) < 0:
            order = order[:, ::-1]
        names = [s.material.name if s.material else '' for s in o.material_slots] or ['']
        for k, mat in enumerate(names):
            sel = order[mats == k].reshape(-1)
            if len(sel) == 0:
                continue
            key = f'{o.name}|{mat}'
            arrays[key + '|pos'] = pos[sel]
            arrays[key + '|nrm'] = normals[sel]
            arrays[key + '|uv'] = uv[loops][sel]
    np.savez(out, **arrays)


def load_pieces(path):
    import numpy as np
    data = np.load(path)
    pieces = {}
    for key in data.files:
        name, mat, kind = key.split('|')
        pieces.setdefault((name, mat), {})[kind] = data[key]
    return pieces


def gray16(path, size):
    """A 16-bit or 8-bit grey map as 8-bit, resized."""
    import numpy as np
    from PIL import Image
    im = Image.open(path)
    a = np.asarray(im).astype(np.float64)
    if a.ndim == 3:
        a = a[..., 0]
    top = 65535.0 if im.mode.startswith('I') else 255.0
    a = np.clip(a / top * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(a, 'L').resize((size, size), Image.LANCZOS)


def paint_out_plate(rgb):
    """A blank plate: its face inside the rim in the plate's own median color with a
    fine grain, so it carries no registration (the lettering covers too much of the
    face to fill in from around it)."""
    import numpy as np
    x0, y0, x1, y1 = PLATE
    face = rgb[y0:y1, x0:x1].astype(np.float64)
    bare = face[face.mean(2) > 120]
    grain = np.random.default_rng(1967).normal(0.0, 3.0, face.shape[:2])[..., None]
    rgb[y0:y1, x0:x1] = np.clip(np.median(bare, 0) + grain, 0, 255).astype(np.uint8)


def smooth_grit(nrm, grit):
    """Blur the normal map where the dirt was dense, so the paint there is smooth."""
    import numpy as np
    from PIL import Image, ImageFilter
    share = np.asarray(Image.fromarray(np.uint8(grit * 255)).filter(ImageFilter.GaussianBlur(GRIT_RADIUS)),
                       np.float64) / 255.0
    weight = np.clip((share - GRIT_SHARE * 0.5) / (GRIT_SHARE * 0.5), 0.0, 1.0)[..., None]
    blurred = np.asarray(Image.fromarray(nrm).filter(ImageFilter.GaussianBlur(GRIT_RADIUS)), np.float64)
    nrm[:] = np.round(nrm * (1.0 - weight) + blurred * weight).astype(np.uint8)


def keep_seams(nrm, paint):
    """On the paint, keep only the normal map's fine detail (the panel seams and edges):
    the broad shading baked into it from the high-poly model evened out the light across
    every panel in the game, so the paint looked flat."""
    import numpy as np
    from PIL import Image, ImageFilter
    broad = np.asarray(Image.fromarray(nrm).filter(ImageFilter.GaussianBlur(SEAM_RADIUS)), np.float64)
    fine = np.clip(nrm.astype(np.float64) - broad + np.array([128.0, 128.0, 255.0]), 0, 255)
    nrm[paint] = np.round(fine[paint]).astype(np.uint8)


def textures(texdir, mat, size):
    """(albedo PNG, ORM PNG, normal PNG) for one of the model's materials."""
    import numpy as np
    from PIL import Image
    from studebaker_to_glb import png_bytes

    def path(kind):
        return os.path.join(texdir, f'{mat}_{kind}.png')

    rgb = np.asarray(Image.open(path('Base_Color')).convert('RGB')).copy()
    if mat == PLATE_TEXTURE:
        paint_out_plate(rgb)
    alpha = np.zeros(rgb.shape[:2], np.float64)
    if mat == BODY:
        tan = rgb[..., 0].astype(int) - rgb[..., 2] > 25
        grit = (rgb.astype(np.float64).mean(2) >= DIRTY) & ~tan
        alpha = (~tan).astype(np.float64)
        rgb[~tan] = 255
    if mat == GLASS:
        alpha = np.asarray(gray16(path('Opacity'), rgb.shape[0]), np.float64) / 255.0
    # Color and alpha resized apart: PIL premultiplies an RGBA image when it resizes it,
    # which would turn every texel with alpha 0 (everything but the paint) black.
    color = Image.fromarray(rgb).resize((size, size), Image.LANCZOS)
    mask = Image.fromarray(np.uint8(alpha * 255)).resize((size, size), Image.LANCZOS)
    albedo = Image.merge('RGBA', [*color.split(), mask])
    orm = Image.merge('RGB', [gray16(path('Mixed_AO'), size), gray16(path('Roughness'), size),
                              gray16(path('Metallic'), size)])
    nrm = np.asarray(Image.open(path('Normal_DirectX')).convert('RGB')).copy()
    nrm[..., 1] = 255 - nrm[..., 1]
    if mat == BODY:
        smooth_grit(nrm, grit)
        keep_seams(nrm, ~tan)
    normal = Image.fromarray(nrm).resize((size, size), Image.LANCZOS)
    return png_bytes(albedo), png_bytes(orm), png_bytes(normal)


def build(src_zip, dst):
    import numpy as np
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from studebaker_to_glb import Gltf, ring_axis, share_corners
    from studebaker_dash import quaternion
    import impala_dash as dash

    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(src_zip) as z:
            z.extractall(tmp)
        npz = os.path.join(tmp, 'pieces.npz')
        subprocess.run(['blender', '-b', '--factory-startup', '--python', os.path.abspath(__file__),
                        '--', 'dump', os.path.join(tmp, FBX), npz],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        pieces = load_pieces(npz)
        mats = sorted({mat for (name, mat) in pieces if name not in DROP})
        tex = {mat: textures(os.path.join(tmp, 'textures'), mat, TEXTURE) for mat in mats}

    # Blender's frame (Z up, nose -Y) to the game's (Y up, nose +Z, driver's side +X).
    def to_yup(a):
        return np.stack([a[..., 0], a[..., 2], -a[..., 1]], -1)

    for p in pieces.values():
        p['pos'] = to_yup(p['pos'])
        p['nrm'] = to_yup(p['nrm'])
    wheel = pieces[next(k for k in pieces if k[0] == WHEEL)]['pos']
    kept = {k: p for k, p in pieces.items() if k[0] not in DROP}
    allp = np.concatenate([p['pos'] for p in kept.values()])
    body = pieces[next(k for k in pieces if k[1] == BODY)]['pos']
    lo, hi = allp.min(0), allp.max(0)
    floor = wheel[:, 1].min()
    scale = np.array([WIDTH_M / (body[:, 0].max() - body[:, 0].min()),
                      HEIGHT_M / (body[:, 1].max() - floor),
                      LENGTH_M / (hi[2] - lo[2])])
    origin = np.array([(body[:, 0].min() + body[:, 0].max()) / 2, lo[1], (lo[2] + hi[2]) / 2])

    def to_game(q):
        return (q - origin) * scale

    rim = to_game(kept[next(k for k in kept if k[0] == STEERING_RIM)]['pos'])
    rim_mid = (rim.min(0) + rim.max(0)) / 2
    even = scale.mean()

    dial_key = next(k for k in kept if k[0] == DIALS)
    needle_key = next(k for k in kept if k[0] == NEEDLES)
    pods = dash.build(to_game(kept[dial_key]['pos']).reshape(-1, 3, 3),
                      to_game(kept[needle_key]['pos']).reshape(-1, 3, 3))
    needle_uv = kept[needle_key]['uv'].reshape(-1, 3, 2)

    groups = {}
    for (name, mat), p in kept.items():
        if name == NEEDLES:
            continue
        if name in STEERING:
            # Scaled evenly about the rim's middle, so the wheel stays round.
            pos = rim_mid + (p['pos'] - origin - rim_mid / scale) * even
            nrm = p['nrm']
        else:
            pos = to_game(p['pos'])
            nrm = p['nrm'] / scale
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
        group = 'driving_wheel' if name in STEERING else next(
            (g for g, names in BUMPERS.items() if name in names), 'body')
        if mat == GLASS:
            group += '+glass'
        gp = groups.setdefault(group, {})
        gp.setdefault(mat, []).append((pos, nrm, p['uv']))

    steer = np.concatenate([pos for pos, _, _ in groups['driving_wheel'][next(iter(groups['driving_wheel']))]])
    rim_pos = np.concatenate([pos for m in groups['driving_wheel'].values() for pos, _, _ in m])
    hub, axis = ring_axis(rim_pos)
    across = np.array([1.0, 0.0, 0.0]) - axis[0] * axis
    across /= np.linalg.norm(across)
    wheel_basis = np.stack([across, np.cross(axis, across), axis], 1)

    out = Gltf()
    mat_index = {}
    for mat in mats:
        albedo, orm, normal = tex[mat]
        base = len(out.images)
        out.images += [albedo, orm, normal]
        out.textures += [base, base + 1, base + 2]
        material = {
            'name': mat,
            'pbrMetallicRoughness': {'baseColorTexture': {'index': base},
                                     'metallicRoughnessTexture': {'index': base + 1},
                                     'metallicFactor': 1.0, 'roughnessFactor': 1.0},
            'occlusionTexture': {'index': base + 1},
            'normalTexture': {'index': base + 2},
            'alphaMode': 'BLEND' if mat == GLASS else 'OPAQUE',
            'doubleSided': True,
        }
        mat_index[mat] = len(out.materials)
        out.materials.append(material)

    def primitives(group, frame=None):
        prims = []
        for name in (group, group + '+glass'):
            for mat, parts in groups.get(name, {}).items():
                pos = np.concatenate([p for p, _, _ in parts])
                nrm = np.concatenate([n for _, n, _ in parts])
                uv = np.concatenate([u for _, _, u in parts]).copy()
                uv[:, 1] = 1.0 - uv[:, 1]
                if frame is not None:
                    o, b = frame
                    pos = (pos - o) @ b
                    nrm = nrm @ b
                p, n, u, index = share_corners(pos.astype(np.float32), nrm.astype(np.float32), uv.astype(np.float32))
                prims.append(out.primitive(p, n, index, mat_index[mat], u))
        return prims

    name = os.path.splitext(os.path.basename(dst))[0]
    roots = [out.node(name, mesh=out.mesh(name, primitives('body')))]
    for group in BUMPERS:
        roots.append(out.node(group, mesh=out.mesh(group, primitives(group))))
    wheel_mesh = out.mesh('driving_wheel_mesh', primitives('driving_wheel', (hub, wheel_basis)))
    roots.append(out.node('driving_wheel', translation=hub, rotation=quaternion(wheel_basis),
                          children=[out.node('driving_wheel_mesh', mesh=wheel_mesh)]))
    for pod, center, basis, radius, kind, needle_name, needle, idx in pods:
        image = len(out.images)
        out.images.append(dash.face_png(kind))
        out.textures.append(image)
        face_mat = len(out.materials)
        out.materials.append(dash.face_material(kind, len(out.textures) - 1))
        ft, fn, fu = dash.face_mesh(radius)
        fp, fnn, fuu, fidx = share_corners(ft.reshape(-1, 3).astype(np.float32), fn.reshape(-1, 3).astype(np.float32),
                                           fu.reshape(-1, 2).astype(np.float32))
        face = out.node(f'{pod}_face', mesh=out.mesh(f'{pod}_face', [out.primitive(fp, fnn, fidx, face_mat, fuu)]))
        flat = np.cross(needle[:, 1] - needle[:, 0], needle[:, 2] - needle[:, 0])
        flat /= np.maximum(np.linalg.norm(flat, axis=1, keepdims=True), 1e-12)
        uv = needle_uv[idx].reshape(-1, 2).copy()
        uv[:, 1] = 1.0 - uv[:, 1]
        np_, nn, nu, nidx = share_corners(needle.reshape(-1, 3).astype(np.float32),
                                          np.repeat(flat, 3, 0).astype(np.float32), uv.astype(np.float32))
        needle_node = needle_name or f'{pod}_needle'
        hand = out.node(needle_node, mesh=out.mesh(needle_node, [out.primitive(np_, nn, nidx, mat_index['Indoor_M'], nu)]))
        roots.append(out.node(pod, translation=center, rotation=quaternion(basis), children=[face, hand]))
    out.write(dst, roots)

    size_m = (hi - lo) * scale
    tris = sum(len(p['pos']) // 3 for p in kept.values())
    print(f'{dst}: {tris} tris, {len(mats)} materials, {os.path.getsize(dst) / 1e6:.1f} MB, '
          f'size {size_m.round(3)} m ({(size_m / 0.0254).round(1)} in), scale {scale.round(3)}')
    w = to_game(wheel)
    front, rear = w[w[:, 2] > 0], w[w[:, 2] <= 0]
    radius = (w[:, 1].max() - w[:, 1].min()) / 2
    # The track from the tire and rim alone: the axle stubs reach in toward the middle.
    right = w[w[:, 0] > 0]
    axle_y = (w[:, 1].min() + w[:, 1].max()) / 2
    rf = right[right[:, 2] > 0]
    out_r = np.hypot(rf[:, 1] - axle_y, rf[:, 2] - (rf[:, 2].min() + rf[:, 2].max()) / 2) > 0.6 * radius
    track = (rf[out_r, 0].min() + rf[out_r, 0].max()) / 2
    fz = (front[:, 2].min() + front[:, 2].max()) / 2
    rz = (rear[:, 2].min() + rear[:, 2].max()) / 2
    wheel_y = (w[:, 1].min() + w[:, 1].max()) / 2
    print('model tire radius %.3f m (%.1f in diameter)' % (radius, radius * 2 / 0.0254))
    print('wheel centers: x ±%.3f, y %.3f (body bottom = 0), front z %.3f, rear z %.3f, wheelbase %.1f in'
          % (track, wheel_y, fz, rz, (fz - rz) / 0.0254))
    print('ground clearance in the model %.3f m' % (-w[:, 1].min()))
    for pod, center, basis, radius, kind, *_ in pods:
        print(f'{pod}: {kind} at {center.round(3)}, face radius {radius:.4f}, facing {(-basis[:, 1]).round(3)}')
    print('steering wheel hub', hub.round(3), 'axis', axis.round(3), 'rim', steer.min(0).round(3), steer.max(0).round(3))


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if argv and argv[0] == 'dump':
        dump(argv[1], argv[2])
    else:
        build(argv[0], argv[1])
