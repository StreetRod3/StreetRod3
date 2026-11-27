#!/usr/bin/env python3
"""Convert super7's AC Cobra 427 into a car body GLB.

    python3 -I tools/cobra_to_glb.py assets/cars/shelby-cobra-1965.glb

Source: "AC Cobra classic" by super7, CC-BY-4.0,
https://sketchfab.com/3d-models/ac-cobra-classic-e6a38042e6e84189bc158682478e8b24
(reference/cars/cobra/source). A 2018 THREE.GLTFExporter file: four meshes, all on one
2048 px texture set (color and normal map): the interior with the tires, wheels, seats,
dash, side pipes and lamps (INTERIOR), the windscreen, the rest of the glass, and the
body shell (BODY). In the meshes' frame Y is up, the nose points along +X and the
driver sits on -Z.

What the model needs that it doesn't have:

  * a bottom. The body shell has no floor through the wheel arches, and where it has
    one the faces point up into the car, so with back faces culled (as the game draws)
    you look up into the cockpit and the engine bay. A plain dark floor, facing down, is
    added (build_underbody): at the sills' bottom between the wheels, just inside the
    body's underside ahead of and behind them, through each wheel arch out to the
    interior's own wheel tubs and sloping between the heights on either side of the
    arch, and stopping short of the tips of the nose and tail, which are closed
    underneath. Its edges come from cross-sections of the body shell, so it ends on
    the skin.
  * working gauges: the dials are painted into the texture (tools/cobra_dash.py).

The GLB is laid out like the Impala's (tools/impala_to_glb.py):

  * Y up, nose along +Z, driver's side +X;
  * centered on X over the body and on Z over the whole car, lowest point at Y = 0;
  * real size in meters: the 427's 156 in length and 68 in width (over the body, not
    the side pipes), each on its own; the height is scaled as the two are on average.
    The published 47-49 in is from the ground to the top of the windscreen; the model
    stands 44.6 in on its own tires, but only 3.8 in off the ground, so the difference
    is its ride height rather than its body, and the body is not stretched; the
    steering wheel is scaled evenly so it stays round;
  * the texture with the paint as a mask for car_paint_mask.gdshader: the body's blue
    is white with alpha 1, the white stripes the same with blue 0 (the accent, the car
    file's model.accent), the dirt and rust left off; everything else has alpha 0 and
    keeps its colors;
  * an ORM texture (R = AO, G = roughness, B = metallic) and the model's normal map;
  * the glass as its own clear material, so the paint shader never touches it;
  * the rear plate keeps its holder, and the blank plate (assets/cars/plate-blank.png),
    a US plate's 12 x 6 in, is laid over its smaller face on a material named `plate`,
    where the game prints the car's own number (the model's lettering is painted out of the texture as well);
  * no bumpers: the Cobra has none, and the small bars at the corners are jacking
    points, which stay on the body;
  * the steering wheel as its own `driving_wheel` node, its +Z down the column.

The wheels and their spinners are left out: the game mounts its own. The numbers the
.car file needs are printed at the end.
"""
import json
import os
import struct
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SOURCE = 'reference/cars/cobra/source/AC Cobra 1.glb'
IN = 0.0254
## The 1965-67 Cobra 427 (AC Cars / Shelby American): 156 in long, 68 in wide.
LENGTH_M = 156.0 * IN
WIDTH_M = 68.0 * IN

## Meshes of the source (all in the same frame) and their materials.
INTERIOR = 0  # interior, tires, wheels, pipes, lamps
WINDSCREEN = 1
GLASS = 2     # lamp and gauge lenses, wind wings, the windscreen's other side
BODY = 3      # the outer body shell
TEXTURE_IMAGE = 0  # color; image 1 is its normal map

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

## Parts of INTERIOR by their boxes (raw units, the model's frame).
## A part wholly inside a tire's box is that wheel's (tire, rim, spinner): left out.
WHEEL_BOX = 0.2   # past the tire's radius along X and above its top
## The steering wheel: its wood rim and its spokes with the hub, each wholly inside
## this box (the column reaches on into the dash and stays).
STEERING = ((-0.1, 0.6), (0.1, 2.0), (-2.65, -0.7))
## The texture: where the rear plate's face is (px; the part also holds its bracket), and
## where the dials are painted (px, the left edge of the texture), for picking their faces
## out of the dash.
PLATE = (512, 1838, 541, 1911)
DIALS = (0, 1230, 130, 1610)
## A part with at least this share of its area on the plate's face is the plate.
PLATE_SHARE = 0.5
## The paint: texels the body shell covers. Of those, the white stripes are bright and
## grey (ACCENT_LIGHT, ACCENT_GREY); openings and gaps are dark (DARK) and stay as they are.
ACCENT_LIGHT = 150
ACCENT_GREY = 30
DARK = 22
## Roughness of everything that isn't paint (the shader's own paint settings rule there).
ROUGHNESS = 0.6
## The glass: a plain clear.
GLASS_COLOR = [0.9, 0.93, 0.95, 0.18]
UNDERBODY_COLOR = [0.05, 0.05, 0.05, 1.0]
## The blank plate every converted car wears (tools/make_blank_plate.py).
PLATE_IMAGE = os.path.join(ROOT, 'assets', 'cars', 'plate-blank.png')
PLATE_W = 12.0 * IN
PLATE_H = 6.0 * IN


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


def load(gltf, binary, mesh):
    """A mesh's triangle corners: positions, normals and UVs (raw, the model's frame)."""
    prim = gltf['meshes'][mesh]['primitives'][0]
    idx = accessor(gltf, binary, prim['indices']).ravel()
    a = prim['attributes']
    return {k: accessor(gltf, binary, a[name])[idx].reshape(-1, 3, n).astype(np.float64)
            for k, name, n in (('pos', 'POSITION', 3), ('nrm', 'NORMAL', 3), ('uv', 'TEXCOORD_0', 2))}


def source_image(gltf, binary, material, slot):
    """A material's texture as a PIL image: slot 'base' or 'normal'."""
    import io
    from PIL import Image
    mat = gltf['materials'][material]
    ref = mat['pbrMetallicRoughness']['baseColorTexture'] if slot == 'base' else mat['normalTexture']
    img = gltf['images'][gltf['textures'][ref['index']]['source']]
    view = gltf['bufferViews'][img['bufferView']]
    start = view.get('byteOffset', 0)
    return Image.open(io.BytesIO(bytes(binary[start:start + view['byteLength']]))).convert('RGB')


def pick(mesh, idx):
    return {k: v[idx] for k, v in mesh.items()}


def join(*meshes):
    return {k: np.concatenate([m[k] for m in meshes]) for k in ('pos', 'nrm', 'uv')}


def split_interior(interior, tires, size):
    """INTERIOR's triangle indices by group: body, wheels, driving_wheel, plate (the
    plate with its holder)."""
    from impala_dash import islands
    groups = {g: [] for g in ('body', 'wheels', 'driving_wheel', 'plate')}
    x0, y0, x1, y1 = PLATE
    for idx in islands(interior['pos']):
        q = interior['pos'][idx].reshape(-1, 3)
        lo, hi = q.min(0), q.max(0)
        uv = interior['uv'][idx].mean(1) * size
        t = interior['pos'][idx]
        area = np.linalg.norm(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]), axis=1)
        on = (uv[:, 0] > x0) & (uv[:, 0] < x1) & (uv[:, 1] > y0) & (uv[:, 1] < y1)
        on_plate = area[on].sum() / max(area.sum(), 1e-12)
        if any(lo[0] >= t['x'] - t['r'] - WHEEL_BOX and hi[0] <= t['x'] + t['r'] + WHEEL_BOX
               and lo[2] * hi[2] > 0 and min(abs(lo[2]), abs(hi[2])) >= t['inner'] - 0.05
               and hi[1] <= t['top'] + WHEEL_BOX for t in tires):
            group = 'wheels'
        elif all(a <= l and h <= b for (a, b), l, h in zip(STEERING, lo, hi)):
            group = 'driving_wheel'
        elif on_plate >= PLATE_SHARE:
            group = 'plate'
        else:
            group = 'body'
        groups[group].append(idx)
    return {g: np.concatenate(v) if v else np.zeros(0, np.int64) for g, v in groups.items()}


def dial_faces(interior, body_idx, size):
    """The dials' painted faces in the dash: triangles of the body group drawn from the
    dials' corner of the texture, one array of corners per dial."""
    from impala_dash import islands
    x0, y0, x1, y1 = DIALS
    uv = interior['uv'][body_idx].mean(1) * size
    cen = interior['pos'][body_idx].mean(1)
    sel = body_idx[(uv[:, 0] >= x0) & (uv[:, 0] < x1) & (uv[:, 1] >= y0) & (uv[:, 1] < y1)
                   & (cen[:, 0] > 0.4) & (cen[:, 0] < 0.9) & (cen[:, 1] > 0.6)]
    return [sel[i] for i in islands(interior['pos'][sel])]


def paint_mask(base, body_uv):
    """The car's texture with the paint as a mask (see the module's notes): RGBA."""
    from PIL import Image, ImageDraw, ImageFilter
    size = base.size[0]
    cover = Image.new('L', base.size, 0)
    draw = ImageDraw.Draw(cover)
    for tri in body_uv * size:
        draw.polygon([tuple(p) for p in tri], fill=255)
    cover = np.asarray(cover.filter(ImageFilter.MaxFilter(5))) > 0
    rgb = np.asarray(base).copy()
    f = rgb.astype(np.int64)
    light = f.mean(2)
    grey = f.max(2) - f.min(2)
    accent = cover & (light >= ACCENT_LIGHT) & (grey <= ACCENT_GREY)
    paint = cover & ~accent & (light > DARK)
    rgb[paint] = 255
    rgb[accent] = (255, 255, 0)
    # The plate's face: its own median color with a fine grain, so it carries no
    # registration (the part is left out, but the texture ships with the car).
    x0, y0, x1, y1 = PLATE
    face = rgb[y0:y1, x0:x1].astype(np.float64)
    grain = np.random.default_rng(427).normal(0.0, 3.0, face.shape[:2])[..., None]
    rgb[y0:y1, x0:x1] = np.clip(np.median(face.reshape(-1, 3), 0) + grain, 0, 255).astype(np.uint8)
    alpha = np.uint8((paint | accent) * 255)
    return Image.merge('RGBA', [*Image.fromarray(rgb).split(), Image.fromarray(alpha)])


def build(dst):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from PIL import Image
    from studebaker_to_glb import Gltf, png_bytes, ring_axis, share_corners
    from studebaker_dash import quaternion
    from variety_pack_to_glb import plate_quad
    import cobra_dash as dash

    gltf, binary = read_glb(os.path.join(ROOT, SOURCE))
    interior = load(gltf, binary, INTERIOR)
    body_shell = load(gltf, binary, BODY)
    glass = join(load(gltf, binary, WINDSCREEN), load(gltf, binary, GLASS))
    base = source_image(gltf, binary, INTERIOR, 'base')
    normal = source_image(gltf, binary, INTERIOR, 'normal')
    size = base.size[0]

    tires = find_tires(interior['pos'])
    quads, _ = build_underbody(body_shell['pos'], interior['pos'], tires)
    floor = np.concatenate([quads[:, [0, 1, 2]], quads[:, [0, 2, 3]]])
    fn = np.cross(floor[:, 1] - floor[:, 0], floor[:, 2] - floor[:, 0])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True)
    underbody = {'pos': floor, 'nrm': np.repeat(fn[:, None], 3, 1), 'uv': np.zeros(floor.shape[:2] + (2,))}

    parts = split_interior(interior, tires, size)
    faces = dial_faces(interior, parts['body'], size)
    groups = {
        'body': join(body_shell, pick(interior, parts['body']), pick(interior, parts['plate'])),
        'driving_wheel': pick(interior, parts['driving_wheel']),
    }
    plate_face = plate_face_tris(interior, parts['plate'], size)

    # The model's frame (Y up, nose +X, driver -Z) to the game's (Y up, nose +Z,
    # driver +X): a quarter turn about Y.
    def axes(a):
        return np.stack([-a[..., 2], a[..., 1], a[..., 0]], -1)

    kept = np.concatenate([axes(m['pos']).reshape(-1, 3) for m in (*groups.values(), glass, underbody)])
    shell = axes(body_shell['pos']).reshape(-1, 3)
    lo, hi = kept.min(0), kept.max(0)
    scale = np.array([WIDTH_M / np.ptp(shell[:, 0]), 0.0, LENGTH_M / (hi[2] - lo[2])])
    scale[1] = (scale[0] + scale[2]) / 2
    origin = np.array([(shell[:, 0].min() + shell[:, 0].max()) / 2, lo[1], (lo[2] + hi[2]) / 2])

    def to_game(q):
        return (axes(q) - origin) * scale

    def normals_to_game(n):
        n = axes(n) / scale
        return n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-12)

    out = Gltf()

    def add_image(im):
        out.images.append(png_bytes(im))
        out.textures.append(len(out.images) - 1)
        return len(out.textures) - 1

    albedo = add_image(paint_mask(base, body_shell['uv'].reshape(-1, 3, 2)))
    orm = add_image(Image.merge('RGB', [Image.new('L', base.size, 255),
                                        Image.new('L', base.size, int(ROUGHNESS * 255)),
                                        Image.new('L', base.size, 0)]))
    nrm_tex = add_image(normal)
    blank = Image.open(PLATE_IMAGE).convert('RGB')
    blank.putalpha(0)
    plate_tex = add_image(blank)
    out.materials += [
        {'name': 'cobra', 'doubleSided': True,
         'pbrMetallicRoughness': {'baseColorTexture': {'index': albedo},
                                  'metallicRoughnessTexture': {'index': orm},
                                  'metallicFactor': 1.0, 'roughnessFactor': 1.0},
         'occlusionTexture': {'index': orm}, 'normalTexture': {'index': nrm_tex}},
        {'name': 'cobra_glass', 'doubleSided': True, 'alphaMode': 'BLEND',
         'pbrMetallicRoughness': {'baseColorFactor': GLASS_COLOR, 'metallicFactor': 0.0,
                                  'roughnessFactor': 0.05}},
        {'name': 'underbody', 'doubleSided': True,
         'pbrMetallicRoughness': {'baseColorFactor': UNDERBODY_COLOR, 'metallicFactor': 0.0,
                                  'roughnessFactor': 0.9}},
        {'name': 'plate', 'doubleSided': True,
         'pbrMetallicRoughness': {'baseColorTexture': {'index': plate_tex}, 'metallicFactor': 0.3,
                                  'roughnessFactor': 0.5}},
    ]
    PAINTED, CLEAR, FLOOR, PLATE_MAT = 0, 1, 2, 3

    def primitive(m, material, frame=None, even=None):
        pos = to_game(m['pos']).reshape(-1, 3)
        nrm = normals_to_game(m['nrm']).reshape(-1, 3)
        if even is not None:
            mid, k = even
            pos = mid + (pos - mid) * k
            nrm = axes(m['nrm']).reshape(-1, 3)
        if frame is not None:
            o, b = frame
            pos = (pos - o) @ b
            nrm = nrm @ b
        p, n, u, index = share_corners(pos.astype(np.float32), nrm.astype(np.float32),
                                       m['uv'].reshape(-1, 2).astype(np.float32))
        return out.primitive(p, n, index, material, u)

    # The blank plate over the model's: in the plate's plane, PLATE_OUT in front of it.
    qp, qn, qu, plate_size = plate_quad(to_game(plate_face), -1)
    # The model's plate is small (7.9 x 3.8 in): the US plate is laid over it at its own
    # size, about the same middle.
    c0, c1, c2, c3 = qp[0, 0], qp[0, 1], qp[0, 2], qp[1, 2]
    right = (c1 - c0) / np.linalg.norm(c1 - c0)
    up = (c3 - c0) / np.linalg.norm(c3 - c0)
    mid = (c0 + c2) / 2
    corners = [mid + (sx * PLATE_W * right + sy * PLATE_H * up) / 2
               for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    qp = np.array([[corners[0], corners[1], corners[2]], [corners[0], corners[2], corners[3]]])
    plate_size = (PLATE_W, PLATE_H)
    p, n, u, index = share_corners(qp.reshape(-1, 3).astype(np.float32), qn.reshape(-1, 3).astype(np.float32),
                                   qu.reshape(-1, 2).astype(np.float32))
    plate_prim = out.primitive(p, n, index, PLATE_MAT, u)

    name = os.path.splitext(os.path.basename(dst))[0]
    roots = [out.node(name, mesh=out.mesh(name, [primitive(groups['body'], PAINTED),
                                                 primitive(glass, CLEAR),
                                                 primitive(underbody, FLOOR),
                                                 plate_prim]))]

    # The steering wheel, scaled evenly about the rim's middle so it stays round.
    wheel = to_game(groups['driving_wheel']['pos']).reshape(-1, 3)
    mid = (wheel.min(0) + wheel.max(0)) / 2
    even = (mid, scale.mean() / scale)
    hub, axis = ring_axis(mid + (wheel - mid) * even[1])
    across = np.array([1.0, 0.0, 0.0]) - axis[0] * axis
    across /= np.linalg.norm(across)
    basis = np.stack([across, np.cross(axis, across), axis], 1)
    steer = out.mesh('driving_wheel_mesh', [primitive(groups['driving_wheel'], PAINTED, (hub, basis), even)])
    roots.append(out.node('driving_wheel', translation=hub, rotation=quaternion(basis),
                          children=[out.node('driving_wheel_mesh', mesh=steer)]))

    # The gauges.
    pods = dash.build([to_game(interior['pos'][i]) for i in faces])
    out.materials.append(dash.needle_material())
    needle_mat = len(out.materials) - 1
    for pod, center, pbasis, radius, kind, needle_name, ntris, nnrm in pods:
        out.materials.append(dash.face_material(kind, add_image_png(out, dash.face_png(kind))))
        ft, fnrm, fuv = dash.face_mesh(radius)
        fp, fnn, fu, fidx = share_corners(ft.reshape(-1, 3).astype(np.float32),
                                          fnrm.reshape(-1, 3).astype(np.float32),
                                          fuv.reshape(-1, 2).astype(np.float32))
        face = out.node(f'{pod}_face', mesh=out.mesh(f'{pod}_face', [out.primitive(fp, fnn, fidx, len(out.materials) - 1, fu)]))
        np_, nn, _, nidx = share_corners(ntris.reshape(-1, 3).astype(np.float32),
                                         nnrm.reshape(-1, 3).astype(np.float32),
                                         np.zeros((ntris.size // 3, 2), np.float32))
        hand_name = needle_name or f'{pod}_needle'
        hand = out.node(hand_name, mesh=out.mesh(hand_name, [out.primitive(np_, nn, nidx, needle_mat)]))
        roots.append(out.node(pod, translation=center, rotation=quaternion(pbasis), children=[face, hand]))
    out.write(dst, roots)

    report(dst, kept, scale, origin, to_game, interior, parts, tires, pods, hub, axis, plate_size, qp)


def add_image_png(out, png):
    out.images.append(png)
    out.textures.append(len(out.images) - 1)
    return len(out.textures) - 1


def plate_face_tris(interior, plate_idx, size):
    """The plate's face: the triangles of the plate part drawn from the plate's face in
    the texture."""
    x0, y0, x1, y1 = PLATE
    uv = interior['uv'][plate_idx].mean(1) * size
    on = (uv[:, 0] > x0) & (uv[:, 0] < x1) & (uv[:, 1] > y0) & (uv[:, 1] < y1)
    return interior['pos'][plate_idx[on]]


def report(dst, kept, scale, origin, to_game, interior, parts, tires, pods, hub, axis, plate_size, plate):
    size_m = (kept.max(0) - kept.min(0)) * scale
    print(f'{dst}: {os.path.getsize(dst) / 1e6:.1f} MB, size {size_m.round(3)} m '
          f'({(size_m / IN).round(1)} in), scale {scale.round(4)} m per model unit')
    print('parts:', {g: len(i) for g, i in parts.items()}, 'triangles')
    w = to_game(interior['pos'][parts['wheels']]).reshape(-1, 3)
    ground = w[:, 1].min()
    for t, name in zip(tires, ('rear', 'front')):
        z = (t['x'] - origin[2]) * scale[2]
        q = w[np.abs(w[:, 2] - z) < t['r'] * scale[2] * 1.2]
        right = q[q[:, 0] > 0]
        y_mid = (q[:, 1].min() + q[:, 1].max()) / 2
        r = (q[:, 1].max() - q[:, 1].min()) / 2
        tread = right[np.hypot(right[:, 1] - y_mid, right[:, 2] - z) > 0.85 * r]
        print(f'{name} wheels: z {z:.3f}, center y {y_mid:.3f}, track x ±{(tread[:, 0].min() + tread[:, 0].max()) / 2:.3f}, '
              f'tire radius {r:.3f} m ({2 * r / IN:.1f} in)')
    zs = [(t['x'] - origin[2]) * scale[2] for t in tires]
    print(f'wheelbase {(zs[1] - zs[0]):.3f} m ({(zs[1] - zs[0]) / IN:.1f} in); ground clearance {-ground:.3f} m')
    plate = plate.reshape(-1, 3)
    print(f'rear plate at {((plate.min(0) + plate.max(0)) / 2).round(3)}, '
          f'{plate_size[0] / IN:.1f} x {plate_size[1] / IN:.1f} in')
    print(f'model height {(kept[:, 1].max() - kept[:, 1].min()) * scale[1]:.4f} m; front end z {(kept[:, 2].max() - origin[2]) * scale[2]:.3f}, '
          f'rear end z {(kept[:, 2].min() - origin[2]) * scale[2]:.3f}')
    seats = to_game(interior['pos'][parts['body']]).reshape(-1, 3)
    near = seats[(np.abs(seats[:, 0] - hub[0]) < 0.15) & (seats[:, 2] < hub[2] - 0.2) & (seats[:, 2] > hub[2] - 1.2)]
    print('driver\'s seat (near the wheel\'s line): y', near[:, 1].min().round(3), '..', near[:, 1].max().round(3),
          'z', near[:, 2].min().round(3), '..', near[:, 2].max().round(3))
    for pod, center, basis, radius, kind, *_ in pods:
        print(f'{pod}: {kind} at {center.round(3)}, face radius {radius:.4f}, facing {(-basis[:, 1]).round(3)}')
    print('steering wheel hub', hub.round(3), 'axis', axis.round(3))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    build(sys.argv[1])
