#!/usr/bin/env python3
"""Convert ROH3D's low-poly 1963 Chevrolet C10 Stepside into a car body GLB.

    python3 -I tools/c10_to_glb.py reference/cars/c10-1963/low-poly-car-chevrolet-c10-pickup-1963.zip \
        assets/cars/chevy-c10-1963.glb

Source: "Low Poly Car - Chevrolet C10 Pickup 1963" by ROH3D, CC-BY-4.0,
https://sketchfab.com/3d-models/low-poly-car-chevrolet-c10-pickup-1963-679354c151984747bb74310ec5af8995

The download is a 3ds Max OBJ (source/FullBody.zip, in centimeters, Y up, nose toward +Z,
driver's side +X) in three objects, LowBody, LowGlass and LowInterior, one material each,
with 4096 px PBR textures. It is read here in plain Python.

The GLB is laid out like the other cars' (tools/impala_to_glb.py):

  * Y up, nose along +Z, driver's side +X;
  * centered on X and Z, lowest point of the body at Y = 0;
  * real size in meters, each axis on its own: the real truck's length (LENGTH_M) and
    width over the bumpers (WIDTH_M), and its height (HEIGHT_M) from the bottom of the
    model's tires to the roof; the steering wheel is scaled evenly so it stays round;
  * the model's textures with the paint as a mask for car_paint_mask.gdshader: the
    teal paint is white with alpha 1 (the shading baked into it left off, the panel
    seams kept), and so are the off-white grille and bumpers, which take the car's
    accent paint; everything else has alpha 0 and keeps its colors;
  * an ORM texture per material (R = AO, G = roughness, B = metallic);
  * the glass as its own see-through material;
  * `bumper_front` and `bumper_rear` nodes so the game can strip them, and `grille`;
    those three are the accent (the car file's model.accent);
  * the model's European plates swapped for the Impala's blank US plate, 12 x 6 in;
  * the model's steering wheel and blank instrument hood swapped for a 1960-63 two-spoke
    wheel (`driving_wheel`) and cluster with working gauges (tools/c10_dash.py).

The model's wheels are left out: the game mounts its own wheels. Their centers set the
wheel positions printed at the end, with the other numbers the .car file needs.
"""
import io
import os
import sys
import zipfile

import numpy as np

LENGTH_M = 186.875 * 0.0254
WIDTH_M = 78.75 * 0.0254
HEIGHT_M = 71.25 * 0.0254
OBJ_ZIP = 'source/FullBody.zip'
OBJ = 'FullBody.obj'
TEXTURE = {'Body': 2048, 'Interior': 1024, 'Glass': 512}
GLASS = 'Glass'

## Islands are picked out by where they lie in the model (centimeters, its own frame).
## The plates are single quads 52 x 11 cm, a European plate's size, beyond the bumpers.
PLATE_Z = 200.0
## The grille (with the headlight rims) and the front bumper are the two islands ahead of
## FRONT_Z; the bumper is the lower one. The rear bumper with its brackets lies behind
## REAR_Z and below REAR_TOP (the tail lights are above it).
FRONT_Z = 195.0
REAR_Z = -228.0
REAR_TOP = 60.0
## The model's steering wheel: its rim and spokes lie inside this box; the column, which
## reaches down and forward out of it, stays.
STEERING_BOX = ((-26.0, 108.0, 22.0), (14.0, 142.0, 46.0))
## The new instrument cluster (tools/c10_dash.py), in the GLB's frame: the middle of its
## face, over the steering column, and how far the face is turned up toward the driver.
CLUSTER_Y = 0.972
CLUSTER_Z = 0.62
CLUSTER_TILT = 27.0
## A wheel and tire: at least this big across (cm), and narrow.
WHEEL_MIN = 60.0
WHEEL_MAX_WIDTH = 25.0

## The paint and the accent in the body texture. Paint is teal (green and blue well above
## red); the accent is near white with little color. The paint's shading is baked into the
## texture (lighter along panel edges, darker in the recesses): on the paint only detail
## finer than SHADE_RADIUS px (at 4096) is kept, and only where it is darker (the seams).
TEAL = 30
ACCENT_LUM = 150
ACCENT_CHROMA = 30
SHADE_RADIUS = 6
SHADE_FLOOR = 0.3

## The plate: US size, and the Impala's blank plate cut from its texture, rim and all.
PLATE_W = 12.0 * 0.0254
PLATE_H = 6.0 * 0.0254
PLATE_OUT = 0.003
IMPALA_ZIP = 'reference/cars/impala-1967/chevrolet-impala-1967.zip'
IMPALA_PLATE_TEXTURE = 'textures/FrontChromes_M_Base_Color.png'
IMPALA_PLATE_RECT = (1392, 1545, 1678, 1982)
PLATE_TEX = (512, 256)


def read_obj(text):
    """(positions, uvs, normals, {object: (material, [polygon, ...])}) where a polygon is
    a list of (v, vt, vn) indices from 0."""
    V, T, N = [], [], []
    objs, cur = {}, None
    for line in text.splitlines():
        if line.startswith('v '):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('vt '):
            T.append([float(x) for x in line.split()[1:3]])
        elif line.startswith('vn '):
            N.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('o '):
            cur = line.split()[1]
            objs[cur] = [None, []]
        elif line.startswith('usemtl '):
            objs[cur][0] = line.split()[1]
        elif line.startswith('f '):
            objs[cur][1].append([tuple(int(i) - 1 for i in c.split('/')) for c in line.split()[1:]])
    return np.array(V), np.array(T), np.array(N), objs


def islands(polys):
    """Polygon indices of each connected piece."""
    parent = {}

    def find(a):
        while parent.setdefault(a, a) != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for poly in polys:
        for (a, _, _), (b, _, _) in zip(poly, poly[1:]):
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[ra] = rb
    groups = {}
    for i, poly in enumerate(polys):
        groups.setdefault(find(poly[0][0]), []).append(i)
    return list(groups.values())


def triangles(polys, V, T, N):
    """Fan-triangulated corners: positions, normals, uvs (n, 3, k)."""
    idx = [(p[0], p[i], p[i + 1]) for p in polys for i in range(1, len(p) - 1)]
    corners = np.array(idx)
    return V[corners[..., 0]], N[corners[..., 2]], T[corners[..., 1]]


def classify(V, objs):
    """{group: [(object, polygon indices)]}, the wheels' points and the old steering
    wheel's points (each piece's), by island."""
    groups, wheels, steering = {}, [], []
    lo_s, hi_s = np.array(STEERING_BOX[0]), np.array(STEERING_BOX[1])
    for name, (mat, polys) in objs.items():
        pieces = []
        for isl in islands(polys):
            pts = V[sorted({c[0] for i in isl for c in polys[i]})]
            pieces.append((isl, pts.min(0), pts.max(0)))
        front = sorted([p for p in pieces if p[1][2] > FRONT_Z and len(p[0]) > 1], key=lambda p: p[1][1] + p[2][1])
        for isl, lo, hi in pieces:
            size = hi - lo
            group = 'body'
            if len(isl) == 1 and abs(lo[2]) > PLATE_Z and size[2] < 0.01:
                continue
            if (name == 'LowInterior' and min(size[1], size[2]) > WHEEL_MIN and size[0] < WHEEL_MAX_WIDTH
                    and abs(size[1] - size[2]) < 0.05 * size[1]):
                wheels.append(pts_of(V, polys, isl))
                continue
            if (lo >= lo_s).all() and (hi <= hi_s).all():
                steering.append(pts_of(V, polys, isl))
                continue
            if name == 'LowBody' and len(front) == 2 and any(isl is p[0] for p in front):
                group = 'bumper_front' if isl is front[0][0] else 'grille'
            elif name == 'LowBody' and hi[2] < REAR_Z and hi[1] < REAR_TOP:
                group = 'bumper_rear'
            groups.setdefault(group, []).append((name, isl))
    return groups, wheels, steering


def pts_of(V, polys, isl):
    return V[sorted({c[0] for i in isl for c in polys[i]})]


def gray(data, size):
    """A grey map (8 or 16 bit, or the first channel of a color one) as 8-bit, resized."""
    from PIL import Image
    im = Image.open(io.BytesIO(data))
    a = np.asarray(im)
    if a.ndim == 3:
        a = a[..., 0]
    a = a.astype(np.float32)
    top = 65535.0 if im.mode.startswith('I') else 255.0
    a = np.clip(a / top * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(a, 'L').resize((size, size), Image.LANCZOS)


def blur_masked(values, mask, radius):
    """Gaussian blur of `values` over the texels in `mask` only."""
    from scipy.ndimage import gaussian_filter

    def blur(a):
        return gaussian_filter(a, radius)

    w = blur(mask.astype(np.float32))
    return blur(values * mask) / np.maximum(w, 1e-6)


def uv_mask(shape, uv_tris):
    """Texels covered by the given UV triangles (n, 3, 2), grown a few texels."""
    from PIL import Image, ImageDraw, ImageFilter
    h, w = shape
    im = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(im)
    for tri in uv_tris:
        d.polygon([(u * w, (1.0 - v) * h) for u, v in tri], fill=255)
    return np.asarray(im.filter(ImageFilter.MaxFilter(5))) > 0


def body_albedo(rgb, accent_uv):
    """The body texture as a paint mask: paint and accent white, shaded only by their
    seams, with alpha 1; the rest as it is with alpha 0. (In float32 and a channel at a
    time: the texture is 4096 px.)"""
    r, g, b = (rgb[..., i].astype(np.int16) for i in range(3))
    teal = (g - r > TEAL) & (b - r > TEAL)
    del r, g, b
    lum = rgb.mean(2, dtype=np.float32)
    chroma = rgb.max(2) - rgb.min(2)
    accent = uv_mask(rgb.shape[:2], accent_uv) & (lum > ACCENT_LUM) & (chroma < ACCENT_CHROMA)
    del chroma
    alpha = np.zeros(rgb.shape[:2], np.float32)
    out = rgb.copy()
    for zone in (teal, accent):
        broad = blur_masked(lum, zone, SHADE_RADIUS)
        shade = np.clip(1.0 + np.minimum(lum / np.maximum(broad, 1.0) - 1.0, 0.0), SHADE_FLOOR, 1.0)
        del broad
        out[zone] = np.round(255.0 * shade[zone])[:, None].astype(np.uint8)
        alpha[zone] = 1.0
    return out, alpha


def textures(files, mat, accent_uv):
    """(albedo PNG, ORM PNG, normal PNG or None) for one of the model's materials."""
    from PIL import Image
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from studebaker_to_glb import png_bytes

    size = TEXTURE[mat]
    rgb = np.asarray(Image.open(io.BytesIO(files[f'{mat}_Base_Color.png'])).convert('RGB')).copy()
    alpha = np.zeros(rgb.shape[:2], np.float32)
    if mat == 'Body':
        rgb, alpha = body_albedo(rgb, accent_uv)
    if mat == GLASS:
        alpha = np.asarray(gray(files['Glass_Opacity.png'], rgb.shape[0]), np.float32) / 255.0
    # Color and alpha resized apart: PIL premultiplies an RGBA image when it resizes it,
    # which would turn every texel with alpha 0 black.
    color = Image.fromarray(rgb).resize((size, size), Image.LANCZOS)
    mask = Image.fromarray(np.uint8(np.round(alpha * 255))).resize((size, size), Image.LANCZOS)
    albedo = Image.merge('RGBA', [*color.split(), mask])
    ao = Image.new('L', (size, size), 255)
    orm = Image.merge('RGB', [ao, gray(files[f'{mat}_Roughness.png'], size), gray(files[f'{mat}_Metallic.png'], size)])
    key = f'{mat}_Normal_OpenGL.png'
    normal = None
    if key in files:
        normal = png_bytes(Image.open(io.BytesIO(files[key])).convert('RGB').resize((size, size), Image.LANCZOS))
    return png_bytes(albedo), png_bytes(orm), normal


def plate_png(impala_zip):
    """The Impala's plate, its lettering painted out (tools/impala_to_glb.py), turned to
    lie long side across, with alpha 0 so it is never painted."""
    from PIL import Image
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from impala_to_glb import paint_out_plate
    from studebaker_to_glb import png_bytes
    with zipfile.ZipFile(impala_zip) as z:
        rgb = np.asarray(Image.open(io.BytesIO(z.read(IMPALA_PLATE_TEXTURE))).convert('RGB')).copy()
    paint_out_plate(rgb)
    plate = Image.fromarray(rgb).crop(IMPALA_PLATE_RECT).rotate(90, expand=True).resize(PLATE_TEX, Image.LANCZOS)
    plate.putalpha(0)
    return png_bytes(plate)


def plate_quad(center, facing):
    """A plate's face centered on `center`, facing +Z (facing 1) or -Z (-1), with UVs over
    the plate image (the material is double-sided)."""
    x, y, z = center
    hw, hh = PLATE_W / 2, PLATE_H / 2
    # Seen from in front of it, u runs left to right: toward +X at the front, -X at the rear.
    xs = [x - hw * facing, x + hw * facing]
    q = np.array([[xs[0], y - hh, z], [xs[1], y - hh, z], [xs[1], y + hh, z], [xs[0], y + hh, z]])
    uv = np.array([[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]])
    tris = [(0, 1, 2), (0, 2, 3)]
    pos = np.array([q[list(t)] for t in tris])
    uvs = np.array([uv[list(t)] for t in tris])
    nrm = np.zeros_like(pos) + np.array([0.0, 0.0, float(facing)])
    return pos, nrm, uvs


def orient(tris, nrm):
    """Triangles wound so each faces the way its corners' normals point."""
    tris, nrm = np.array(tris, float), np.array(nrm, float)
    face = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    flip = np.einsum('ij,ij->i', face, nrm.sum(1)) < 0
    tris[flip] = tris[flip][:, ::-1]
    nrm[flip] = nrm[flip][:, ::-1]
    return tris, nrm


def prim(out, share_corners, tris, nrm, uv, material):
    p, n, u, index = share_corners(tris.reshape(-1, 3).astype(np.float32), nrm.reshape(-1, 3).astype(np.float32),
                                   uv.reshape(-1, 2).astype(np.float32))
    return out.primitive(p, n, index, material, u)


def build(src_zip, dst, impala_zip=IMPALA_ZIP):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from studebaker_to_glb import Gltf, ring_axis, share_corners
    from studebaker_dash import facing_basis, quaternion
    import c10_dash as dash

    with zipfile.ZipFile(src_zip) as z:
        files = {os.path.basename(n): z.read(n) for n in z.namelist() if n.startswith('textures/')}
        with zipfile.ZipFile(io.BytesIO(z.read(OBJ_ZIP))) as inner:
            text = inner.read(OBJ).decode('utf-8', 'replace')
    V, T, N, objs = read_obj(text)
    groups, wheels, steering = classify(V, objs)
    wheel = np.concatenate(wheels)

    # The plates' centers, from the model's own plates.
    plates = {}
    for name, (mat, polys) in objs.items():
        for isl in islands(polys):
            pts = pts_of(V, polys, isl)
            if len(isl) == 1 and abs(pts[0, 2]) > PLATE_Z and np.ptp(pts[:, 2]) < 0.01:
                plates['bumper_front' if pts[0, 2] > 0 else 'bumper_rear'] = (pts.min(0) + pts.max(0)) / 2

    kept = np.concatenate([pts_of(V, objs[name][1], isl) for g in groups.values() for name, isl in g])
    lo, hi = kept.min(0), kept.max(0)
    bumpers = np.concatenate([pts_of(V, objs[name][1], isl) for g in ('bumper_front', 'bumper_rear')
                              for name, isl in groups[g]])
    floor = wheel[:, 1].min()
    scale = np.array([WIDTH_M / np.ptp(bumpers[:, 0]), HEIGHT_M / (hi[1] - floor), LENGTH_M / (hi[2] - lo[2])])
    origin = np.array([(bumpers[:, 0].min() + bumpers[:, 0].max()) / 2, lo[1], (lo[2] + hi[2]) / 2])

    def to_game(q):
        return (q - origin) * scale

    accent_uv = []
    meshes = {}
    for group, members in groups.items():
        for name, isl in members:
            mat, polys = objs[name]
            pos, nrm, uv = triangles([polys[i] for i in isl], V, T, N)
            if group in ('grille', 'bumper_front', 'bumper_rear') and mat == 'Body':
                accent_uv.append(uv)
            pos = to_game(pos)
            nrm = nrm / scale
            nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-12)
            meshes.setdefault(group, {}).setdefault(mat, []).append((pos, nrm, uv))

    out = Gltf()
    mat_index = {}
    for mat in TEXTURE:
        albedo, orm, normal = textures(files, mat, np.concatenate(accent_uv) if mat == 'Body' else None)
        base = len(out.images)
        out.images += [albedo, orm] + ([normal] if normal else [])
        out.textures += list(range(base, len(out.images)))
        material = {
            'name': mat,
            'pbrMetallicRoughness': {'baseColorTexture': {'index': base},
                                     'metallicRoughnessTexture': {'index': base + 1},
                                     'metallicFactor': 1.0, 'roughnessFactor': 1.0},
            'occlusionTexture': {'index': base + 1},
            'alphaMode': 'BLEND' if mat == GLASS else 'OPAQUE',
            'doubleSided': True,
        }
        if normal:
            material['normalTexture'] = {'index': base + 2}
        mat_index[mat] = len(out.materials)
        out.materials.append(material)

    image = len(out.images)
    out.images.append(plate_png(impala_zip))
    out.textures.append(image)
    mat_index['plate'] = len(out.materials)
    out.materials.append({'name': 'plate', 'doubleSided': True,
                          'pbrMetallicRoughness': {'baseColorTexture': {'index': len(out.textures) - 1},
                                                   'metallicFactor': 0.3, 'roughnessFactor': 0.5}})
    for group, center in plates.items():
        c = to_game(center)
        facing = 1 if c[2] > 0 else -1
        c[2] += PLATE_OUT * facing
        meshes[group].setdefault('plate', []).append(plate_quad(c, facing))

    def primitives(group):
        prims = []
        for mat, parts in meshes.get(group, {}).items():
            pos = np.concatenate([p for p, _, _ in parts]).reshape(-1, 3)
            nrm = np.concatenate([n for _, n, _ in parts]).reshape(-1, 3)
            uv = np.concatenate([u for _, _, u in parts]).reshape(-1, 2).copy()
            uv[:, 1] = 1.0 - uv[:, 1] if mat != 'plate' else uv[:, 1]
            p, n, u, index = share_corners(pos.astype(np.float32), nrm.astype(np.float32), uv.astype(np.float32))
            prims.append(out.primitive(p, n, index, mat_index[mat], u))
        return prims

    name = os.path.splitext(os.path.basename(dst))[0]
    roots = [out.node(name, mesh=out.mesh(name, primitives('body')))]
    for group in ('grille', 'bumper_front', 'bumper_rear'):
        roots.append(out.node(group, mesh=out.mesh(group, primitives(group))))

    # The steering wheel, where the model's was and on its axis.
    hub, axis = ring_axis(to_game(max(steering, key=lambda p: np.ptp(p, 0).max())))
    across = np.array([1.0, 0.0, 0.0]) - axis[0] * axis
    across /= np.linalg.norm(across)
    wheel_basis = np.stack([across, np.cross(axis, across), axis], 1)
    albedo, orm, swatch_uv = dash.wheel_texture()
    base = len(out.images)
    out.images += [albedo, orm]
    out.textures += [base, base + 1]
    wheel_mat = len(out.materials)
    out.materials.append({'name': 'c10_steering_wheel', 'doubleSided': True,
                          'pbrMetallicRoughness': {'baseColorTexture': {'index': base},
                                                   'metallicRoughnessTexture': {'index': base + 1},
                                                   'metallicFactor': 1.0, 'roughnessFactor': 1.0}})
    parts = dash.wheel_parts()
    tris = np.concatenate([orient(t, n)[0] for _, t, n in parts])
    nrms = np.concatenate([orient(t, n)[1] for _, t, n in parts])
    uvs = np.concatenate([np.tile(swatch_uv[k], (len(t), 3, 1)) for k, t, _ in parts])
    wheel_mesh = out.mesh('driving_wheel_mesh', [prim(out, share_corners, tris, nrms, uvs, wheel_mat)])
    roots.append(out.node('driving_wheel', translation=hub, rotation=quaternion(wheel_basis),
                          children=[out.node('driving_wheel_mesh', mesh=wheel_mesh)]))

    # The cluster over the column, the gas gauge's pointer in a pod of its own, and the
    # glovebox's brow the other side.
    tilt = np.radians(CLUSTER_TILT)
    basis = facing_basis((0.0, np.sin(tilt), -np.cos(tilt)))
    middle_up = dash.FACE_H / 2 - dash.PIVOT_UP
    origin_speedo = np.array([hub[0], CLUSTER_Y, CLUSTER_Z]) - basis[:, 2] * middle_up
    image = len(out.images)
    out.images.append(dash.face_png())
    out.textures.append(image)
    dmat = {}
    for key, material in dash.DASH_MATERIALS.items():
        dmat[key] = len(out.materials)
        out.materials.append(material)
    dmat['face'] = len(out.materials)
    out.materials.append(dash.face_material(len(out.textures) - 1))
    cluster = dash.cluster_parts()

    def dash_mesh(name, parts):
        by_mat = {}
        for mat, t, n, uv in parts:
            t, n = orient(t, n)
            uv = np.zeros(t.shape[:2] + (2,)) if uv is None else uv
            by_mat.setdefault(mat, []).append((t, n, uv))
        prims = [prim(out, share_corners, np.concatenate([a for a, _, _ in v]), np.concatenate([b for _, b, _ in v]),
                      np.concatenate([c for _, _, c in v]), dmat[m]) for m, v in by_mat.items()]
        return out.mesh(name, prims)

    speedo_needle = out.node('speedo_needle', mesh=dash_mesh('speedo_needle', cluster['speedo']))
    face = out.node('dash_c10_cluster', mesh=dash_mesh('dash_c10_cluster', cluster['fixed']))
    roots.append(out.node('dash_speedo_arch_%d_mph_%d_pod' % (dash.SPEEDO_SWEEP, dash.SPEEDO_MAX),
                          translation=origin_speedo, rotation=quaternion(basis), children=[face, speedo_needle]))
    gx, gz = cluster['gas_at']
    gas_at = origin_speedo + basis @ np.array([gx, 0.0, gz])
    fuel_needle = out.node('fuel_needle', mesh=dash_mesh('fuel_needle', cluster['gas']))
    roots.append(out.node('dash_fuel_arch_%d_pod' % dash.GAS_SWEEP, translation=gas_at, rotation=quaternion(basis),
                          children=[fuel_needle]))
    glove_at = np.array([-hub[0], CLUSTER_Y, CLUSTER_Z]) - basis[:, 2] * middle_up
    roots.append(out.node('dash_glovebox', mesh=dash_mesh('dash_glovebox', dash.glovebox_parts()),
                          translation=glove_at, rotation=quaternion(basis)))
    out.write(dst, roots)

    size_m = (hi - lo) * scale
    tris = sum(len(p) for g in meshes.values() for parts in g.values() for p, _, _ in parts)
    print(f'{dst}: {tris} tris, {os.path.getsize(dst) / 1e6:.1f} MB, size {size_m.round(3)} m '
          f'({(size_m / 0.0254).round(1)} in), scale {scale.round(4)}')
    w = to_game(wheel)
    radius = np.ptp(w[:, 1]) / 2
    front, rear = w[w[:, 2] > 0], w[w[:, 2] <= 0]
    right = w[w[:, 0] > 0]
    track = (right[:, 0].min() + right[:, 0].max()) / 2
    fz = (front[:, 2].min() + front[:, 2].max()) / 2
    rz = (rear[:, 2].min() + rear[:, 2].max()) / 2
    print('model tire radius %.3f m (%.1f in diameter)' % (radius, radius * 2 / 0.0254))
    print('wheel centers: x ±%.3f, y %.3f (body bottom = 0), front z %.3f, rear z %.3f, wheelbase %.1f in'
          % (track, (w[:, 1].min() + w[:, 1].max()) / 2, fz, rz, (fz - rz) / 0.0254))
    print('ground clearance in the model %.3f m, full height %.3f m' % (-w[:, 1].min(), size_m[1] - w[:, 1].min()))
    print('steering wheel hub', hub.round(3), 'axis', axis.round(3))
    print('speedometer pivot', origin_speedo.round(3), 'gas pivot', gas_at.round(3), 'facing', (-basis[:, 1]).round(3))


if __name__ == '__main__':
    build(*sys.argv[1:])
