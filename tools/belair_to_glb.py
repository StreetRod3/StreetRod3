#!/usr/bin/env python3
"""Convert dagtholander's low-poly 1954 Chevrolet Bel Air into a car body GLB.

    python3 -I tools/belair_to_glb.py assets/cars/chevy-bel-air-1954.glb

Source: "Chevy Bel Air 1954" by dagtholander, CC-BY-4.0,
https://sketchfab.com/3d-models/chevy-bel-air-1954-be7089002f4b4d858a0422d6a374a211

The download is an FBX written by Blender (reference/cars/54-Bel-Air/source), one object
in two materials: the car in one 2048 px image set made in Substance (base color with the
glass's alpha, roughness, metallic, normal; reference/cars/54-Bel-Air/textures) and a
ground plane. In the model's frame the nose points along -Y, Z is up and the driver's
side is +X, as in the Free Vehicle Archive cars, so Blender reads it through
tools/fva_to_glb.py (dump), which hands back every triangle with its loose part.

The parts are told apart by their boxes (the model's frame, its own units): the wheels,
the bumpers, the steering wheel, and the running gear under the floor that is left out.
The glass is the triangles whose texels are see-through.

The GLB is laid out like the other cars' (tools/fva_to_glb.py):

  * Y up, nose along +Z, driver's side +X;
  * centered on X over the body and on Z over the whole car, lowest point at Y = 0;
  * real size: the real car's length (LENGTH) and width (WIDTH) each on its own, and the
    height scaled as the two are on average (no height for the 1954 hardtop was found);
  * the texture with the paint as a mask for car_paint_mask.gdshader: the turquoise
    paint is white with alpha 1 (the shading baked into it left off, the panel seams
    kept), the white roof the same with blue 0, the accent paint (the car file's
    model.accent); everything else has alpha 0 and keeps its colors;
  * an ORM texture (R = AO, G = roughness, B = metallic) and the normal map;
  * the glass as its own see-through material;
  * `bumper_front` and `bumper_rear` nodes so the game can strip them.

The numbers the .car file needs are printed at the end.
"""
import math
import os
import sys
import tempfile

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SOURCE = 'reference/cars/54-Bel-Air/source/chevyBelair1954.fbx'
TEXTURES = 'reference/cars/54-Bel-Air/textures/lowpoly_belair_%s.png'
IN = 0.0254
## 1954 Bel Air: 197.5 in long, 73.0 in wide, 115 in wheelbase (Conceptcarz).
LENGTH = 197.5
WIDTH = 73.0
WHEELBASE = 115.0
## Texels with less alpha than this are glass.
GLASS_ALPHA = 250
## The texture is cut to this many px.
TEXTURE = 2048

## Parts by their boxes (the model's frame and units): two boxes match when every side is
## within BOX_MATCH.
BOX_MATCH = 0.006
## Parts reaching ahead of FRONT_Y and ending ahead of FRONT_END, and parts wholly behind
## REAR_Y: the bumpers, their guards and the front one's wraparound bar.
FRONT_Y = -3.55
FRONT_END = -3.1
REAR_Y = 2.9
## A wheel and tire: this many triangles at least, this tall and long, and narrow.
WHEEL_TRIS = 600
WHEEL_TALL = 0.8
WHEEL_LONG = 1.0
WHEEL_WIDE = 0.4
## The rear bumper's bar is part of the body: its faces behind BAR_Y and below BAR_TOP
## (the guards are a loose part of their own).
BAR_Y = 2.5
BAR_TOP = 0.665
## Under the bar the body is open: the paint's bottom edges there carried straight down
## and tucked in (tools/fva_to_glb.py, rear_skirt), in the model's frame and units.
REAR_SKIRT = {'edges': 'open', 'x': (0.0, 1.25), 'y': 2.45, 'z': (0.62, 0.72),
              'bottom': 0.47, 'profile': 'straight', 'tuck': 0.08, 'radius': 0.04}
## The model's steering wheel: only its top half, standing above the dash, so it is left
## out; it gives the column's slope. The new one (tools/belair_dash.py) turns about
## WHEEL_HUB (the GLB's frame), on the column down into the dash, COLUMN_R thick.
WHEEL_HUB = (0.379, 0.79, 0.42)
## The model fakes its interior with a black lid at the window sills (the model's frame:
## black faces facing up between LID_Z, within LID_HALF of the middle); ahead of LID_CUT
## (the GLB's frame, just ahead of the rear window) it is cut away so the dash and the
## seats (tools/belair_dash.py) show; what is left is the package shelf.
LID_Z = (1.45, 1.6)
LID_HALF = 0.9
LID_CUT = -1.0
COLUMN_R = 0.022
## The body's sides are looked for this far out from the middle and beyond (the GLB's frame).
SIDE_FROM = 0.3
STEERING = ((0.254, -1.201, 1.471), (0.829, -1.017, 1.715))
## Left out: the spindles, the engine's pan, the control arms, the exhaust, the rear axle
## and springs (the game draws its own running gear).
DROP = [
    ((-0.824, -2.783, 0.259), (-0.788, -2.604, 0.531)),
    ((0.788, -2.783, 0.259), (0.824, -2.604, 0.531)),
    ((-0.463, -2.778, 0.248), (0.463, -1.895, 0.486)),
    ((-0.838, -2.731, 0.285), (-0.448, -2.675, 0.413)),
    ((0.448, -2.731, 0.285), (0.838, -2.675, 0.413)),
    ((-0.838, -2.731, 0.481), (-0.448, -2.675, 0.609)),
    ((0.448, -2.731, 0.481), (0.838, -2.675, 0.609)),
    ((0.752, 0.89, 0.317), (0.852, 3.105, 0.423)),
    ((-0.224, 1.274, 0.277), (0.224, 1.718, 0.406)),
    ((-0.838, 1.461, 0.409), (-0.448, 1.517, 0.468)),
    ((0.448, 1.461, 0.409), (0.838, 1.517, 0.468)),
]

## The paint in the texture: turquoise (green and blue well above red); the roof's white
## is bright with little color, on the roof (above ROOF_Z, the model's frame). Only
## shading finer than SHADE_RADIUS px and darker than its surroundings (the seams) stays.
## The lower panels carry baked grime, a warm grey (red at least blue less GRIME_COOL, no
## brighter than GRIME_LUM) much like the interior's tan: on a face with at least
## PAINT_SHARE of its texels turquoise (TURQUOISE_FAINT will do here) it is paint, clean;
## the chrome strips, a cool grey, stay.
TURQUOISE = 40
TURQUOISE_FAINT = 15
PAINT_SHARE = 0.15
GRIME_COOL = 4
GRIME_LUM = 170
## Speckles of dark grime: any texel on a paint face no brighter than this.
GRIME_DARK = 130
WHITE_LUM = 205
WHITE_CHROMA = 25
ROOF_Z = 1.5
SHADE_RADIUS = 3
SHADE_FLOOR = 0.3
## Of the darker shading kept, only the seams stay: dark marks (shade under SPECK_SHADE)
## within SEAM_JOIN px of each other are taken together (the seams are dashed), and a
## group stays if it runs at least SEAM_LONG px and is SEAM_THIN times as long as it is
## wide; the rest (specks of baked dirt) go.
SPECK_SHADE = 0.93
SEAM_JOIN = 4
SEAM_LONG = 24
SEAM_THIN = 4.0
BODY, ACCENT = 1, 2
## The headliner lies on the roof, facing down, at the roof's very height, so the two fight
## and the roof shows black patches: the faces facing down above HEADLINER_Z go down by
## HEADLINER_DROP (the model's units).
HEADLINER_Z = 1.9
HEADLINER_NZ = -0.7
HEADLINER_DROP = 0.012
## Elsewhere too (the window frames, the posts, the seals) the inside's black faces lie on
## the outside's, facing the other way, and the two fight: a black face lying within
## TWIN_GAP of a lighter one facing back (TWIN_FACING) goes in by TWIN_PUSH (the model's
## units). Black is no channel above BLACK.
TWIN_GAP = 0.002
TWIN_FACING = -0.95
TWIN_PUSH = 0.006
BLACK = 16
## The black faces round the windows that face sideways, out past SIDE_X between the sills
## and the roof (GREENHOUSE_Z), go in toward the middle by SIDE_PUSH, behind the outside
## (the window frames' insides poke through it at the posts and corners).
SIDE_X = 0.8
GREENHOUSE_Z = (1.4, 2.3)
SIDE_PUSH = 0.01
## At the windshield's foot the cowl's and the pillars' black insides reach out past the
## outside: they are left out (the new dash covers the cabin there). The model's frame:
## out past COWL_X, between COWL_Y and in COWL_Z.
COWL_X = 0.6
COWL_Y = (-1.75, -1.2)
COWL_Z = (1.45, 2.0)


def box_of(tris):
    v = tris.reshape(-1, 3)
    return v.min(0), v.max(0)


def matches(lo, hi, box):
    return np.all(np.abs(lo - np.array(box[0])) <= BOX_MATCH) and np.all(np.abs(hi - np.array(box[1])) <= BOX_MATCH)


def texel(img, uv):
    """The texels under UVs (n, 2), the image's rows top down."""
    h, w = img.shape[:2]
    x = np.clip((uv[:, 0] % 1.0) * w, 0, w - 1).astype(int)
    y = np.clip((1.0 - uv[:, 1] % 1.0) * h, 0, h - 1).astype(int)
    return img[y, x]


def push_twins(tris, black, live):
    """Move each black face lying on a lighter one that faces the other way in along its own
    normal by TWIN_PUSH (tris changed in place); how many moved."""
    fn = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    mid = tris.mean(1)
    light = np.nonzero(~black & live)[0]
    lo, hi = tris[light].min(1), tris[light].max(1)
    moved = 0
    for i in np.nonzero(black & live)[0]:
        c = mid[i]
        near = light[np.all((lo - TWIN_GAP <= c) & (c <= hi + TWIN_GAP), axis=1)]
        near = near[fn[near] @ fn[i] < TWIN_FACING]
        if not len(near):
            continue
        a = tris[near, 0]
        near = near[np.abs(np.einsum('ij,ij->i', fn[near], c - a)) < TWIN_GAP]
        for j in near:
            a, b, cc = tris[j]
            v0, v1, v2 = b - a, cc - a, c - a
            d00, d01, d11 = v0 @ v0, v0 @ v1, v1 @ v1
            d20, d21 = v2 @ v0, v2 @ v1
            den = d00 * d11 - d01 * d01
            if abs(den) < 1e-18:
                continue
            u = (d11 * d20 - d01 * d21) / den
            v = (d00 * d21 - d01 * d20) / den
            if u >= -1e-3 and v >= -1e-3 and u + v <= 1 + 1e-3:
                tris[i] += fn[i] * TWIN_PUSH
                moved += 1
                break
    return moved


def clip_behind(tri, plane):
    """The part of a triangle (corners (3, 3)) with z below `plane`, as triangles."""
    d = tri[:, 2] - plane
    inside = [i for i in range(3) if d[i] <= 0]
    if len(inside) == 3:
        return [tri]
    if not inside:
        return []
    poly = []
    for i in range(3):
        a, b = tri[i], tri[(i + 1) % 3]
        if d[i] <= 0:
            poly.append(a)
        if (d[i] <= 0) != (d[(i + 1) % 3] <= 0):
            poly.append(a + (b - a) * d[i] / (d[i] - d[(i + 1) % 3]))
    return [np.array([poly[0], poly[k], poly[k + 1]]) for k in range(1, len(poly) - 1)]


def zone_map(shape, zoned):
    """Each texel's zone from the UV triangles that cover it, grown a few texels so
    filtering at the edges finds it."""
    from PIL import Image, ImageDraw, ImageFilter
    h, w = shape
    im = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(im)
    for tri, zone in zoned:
        if zone:
            d.polygon([(u * w, (1.0 - v) * h) for u, v in tri], fill=int(zone))
    return np.asarray(im.filter(ImageFilter.MaxFilter(5)))


def turquoise(rgb, least):
    r, g, b = (rgb[..., i].astype(np.int16) for i in range(3))
    return (g - r > least) & (b - r > least)


def paint_zone(rgb, uv, roof, rng):
    """A body face's zone: BODY where enough of its texels (sampled) are turquoise, at any
    height (the hood and the trunk lid reach up past ROOF_Z); else ACCENT up on the roof;
    else 0."""
    samples = rng.dirichlet([1.0, 1.0, 1.0], 24) @ uv
    if turquoise(texel(rgb, samples), TURQUOISE_FAINT).mean() >= PAINT_SHARE:
        return BODY
    return ACCENT if roof else 0


def seams_only(shade, zone):
    """The shade with its dark specks lifted out: only long thin dark lines (the seams)
    stay darker than 1."""
    from scipy import ndimage
    dark = zone & (shade < SPECK_SHADE)
    joined = ndimage.binary_dilation(dark, iterations=SEAM_JOIN)
    labels, count = ndimage.label(joined, structure=np.ones((3, 3)))
    out = shade.copy()
    for k, box in enumerate(ndimage.find_objects(labels), 1):
        if box is None:
            continue
        h, w = box[0].stop - box[0].start, box[1].stop - box[1].start
        # A diagonal line's box is square: measure its width across from its area instead.
        mine = labels[box] == k
        length = math.hypot(h, w)
        width = max(mine.sum() / max(length, 1.0), 1.0)
        if max(h, w) >= SEAM_LONG and length / width >= SEAM_THIN:
            continue
        out[box][mine & dark[box]] = 1.0
    return out


def body_albedo(rgb, zones):
    """The texture as a paint mask: the turquoise white, shaded only by its seams, and the
    grime on the paint white and clean, with alpha 1; the roof's white the same with blue 0;
    the rest as it is with alpha 0."""
    from c10_to_glb import blur_masked
    r, b = rgb[..., 0].astype(np.int16), rgb[..., 2].astype(np.int16)
    lum = rgb.mean(2, dtype=np.float32)
    chroma = rgb.max(2).astype(np.int16) - rgb.min(2)
    on_body = zones == BODY
    shaded = turquoise(rgb, TURQUOISE) & on_body
    grime = on_body & ~turquoise(rgb, TURQUOISE_FAINT) & ((r >= b - GRIME_COOL) & (lum <= GRIME_LUM)
                                                         | (lum <= GRIME_DARK))
    faint = on_body & turquoise(rgb, TURQUOISE_FAINT) & ~shaded
    white = (lum > WHITE_LUM) & (chroma < WHITE_CHROMA) & (zones == ACCENT)
    alpha = np.zeros(rgb.shape[:2], np.float32)
    out = rgb.copy()
    for zone, accent in ((shaded, False), (white, True)):
        broad = blur_masked(lum, zone, SHADE_RADIUS)
        shade = np.clip(1.0 + np.minimum(lum / np.maximum(broad, 1.0) - 1.0, 0.0), SHADE_FLOOR, 1.0)
        shade = seams_only(shade, zone)
        level = np.round(255.0 * shade[zone]).astype(np.uint8)
        out[zone] = np.stack([level, level, np.zeros_like(level) if accent else level], -1)
        alpha[zone] = 1.0
    out[grime | faint] = 255
    alpha[grime | faint] = 1.0
    return out, alpha


def build(dst):
    from PIL import Image
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import fva_to_glb as fva
    from studebaker_to_glb import Gltf, ring_axis, share_corners, png_bytes
    from studebaker_dash import facing_basis, quaternion
    from c10_dash import _frustum
    from c10_to_glb import orient
    import belair_dash as dash

    with tempfile.TemporaryDirectory() as tmp:
        npz = os.path.join(tmp, 'pieces.npz')
        fva.run_dump(os.path.join(ROOT, SOURCE), npz, 'Cube.003')
        car = fva.load_pieces(npz)[('', 'belair')]
    rgba = np.asarray(Image.open(os.path.join(ROOT, TEXTURES % 'BaseColor')).convert('RGBA')).copy()
    tris = car['pos'].reshape(-1, 3, 3)
    nrms = car['nrm'].reshape(-1, 3, 3)
    uvs = car['uv'].reshape(-1, 3, 2)

    # Each triangle's group, by its loose part's box; glass by its texels.
    group = np.full(len(tris), 'body', object)
    wheels = []
    for part in np.unique(car['part']):
        sel = car['part'] == part
        lo, hi = box_of(tris[sel])
        size = hi - lo
        if sel.sum() >= WHEEL_TRIS and size[2] > WHEEL_TALL and size[1] < WHEEL_LONG and size[0] < WHEEL_WIDE:
            wheels.append(tris[sel].reshape(-1, 3))
            group[sel] = None
        elif any(matches(lo, hi, b) for b in DROP):
            group[sel] = None
        elif matches(lo, hi, STEERING):
            group[sel] = 'driving_wheel'
        elif lo[1] < FRONT_Y and hi[1] < FRONT_END:
            group[sel] = 'bumper_front'
        elif lo[1] > REAR_Y:
            group[sel] = 'bumper_rear'
    mid = tris.mean(1)
    group[(group == 'body') & (mid[:, 1] > BAR_Y) & (mid[:, 2] < BAR_TOP)] = 'bumper_rear'
    lining = (nrms.mean(1)[:, 2] < HEADLINER_NZ) & (mid[:, 2] > HEADLINER_Z)
    tris = tris.copy()
    tris[lining, :, 2] -= HEADLINER_DROP
    alpha = texel(rgba[..., 3], uvs.mean(1))
    glass = (alpha < GLASS_ALPHA) & (group == 'body')
    pushed = push_twins(tris, texel(rgba[..., :3], uvs.mean(1)).max(1) <= BLACK, group != None)  # noqa: E711
    fn = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    mid = tris.mean(1)
    side = ((texel(rgba[..., :3], uvs.mean(1)).max(1) <= BLACK) & (group != None)  # noqa: E711
            & (np.abs(mid[:, 0]) > SIDE_X) & (np.abs(fn[:, 0]) > 0.7)
            & (mid[:, 2] > GREENHOUSE_Z[0]) & (mid[:, 2] < GREENHOUSE_Z[1]))
    tris[side, :, 0] -= np.sign(mid[side, 0])[:, None] * SIDE_PUSH
    cowl = ((texel(rgba[..., :3], uvs.mean(1)).max(1) <= BLACK) & (group == 'body')
            & (np.abs(mid[:, 0]) > COWL_X) & (mid[:, 1] > COWL_Y[0]) & (mid[:, 1] < COWL_Y[1])
            & (mid[:, 2] > COWL_Z[0]) & (mid[:, 2] < COWL_Z[1]))
    group[cowl] = None
    print(f'inner black faces pushed off the outside: {pushed}, round the windows: {int(side.sum())}, '
          f'left out at the cowl: {int(cowl.sum())}')

    # Each body face's paint zone (the model's frame).
    rng = np.random.default_rng(1)
    zone = np.array([paint_zone(rgba[..., :3], uv, m[2] >= ROOF_Z, rng)
                     if g in ('body', 'bumper_front', 'bumper_rear') and not gl else 0
                     for uv, m, g, gl in zip(uvs, mid, group, glass)])
    # The valance under the rear bumper, in the paint: its UVs on the middle of the face
    # with the most turquoise.
    paint = (zone == BODY) & (group == 'body')
    skirt = fva.rear_skirt({('body', 'paint'): {'pos': tris[paint].reshape(-1, 3), 'nrm': nrms[paint].reshape(-1, 3)}},
                           {'paint': {'paint'}, 'accent': set(), 'bumpers': {'bumper_rear': []}}, REAR_SKIRT)
    if skirt:
        piece = skirt['paint']
        n = len(piece['pos']) // 3
        share = [turquoise(texel(rgba[..., :3], np.random.default_rng(2).dirichlet([1, 1, 1], 24) @ uv),
                           TURQUOISE).mean() for uv in uvs[paint]]
        swatch = uvs[paint][int(np.argmax(share))].mean(0)
        tris = np.concatenate([tris, piece['pos'].reshape(-1, 3, 3)])
        nrms = np.concatenate([nrms, piece['nrm'].reshape(-1, 3, 3)])
        uvs = np.concatenate([uvs, np.tile(swatch, (n, 3, 1))])
        group = np.concatenate([group, np.full(n, 'body', object)])
        glass = np.concatenate([glass, np.zeros(n, bool)])
        zone = np.concatenate([zone, np.zeros(n, int)])
        print(f'rear valance: {n} tris')
    # Swatches for the dash: the paint (the face with the most turquoise) and the accent
    # (the roof's face with the most white).
    samples = np.random.default_rng(3).dirichlet([1, 1, 1], 24)

    def best(sel, test):
        share = [test(texel(rgba[..., :3], samples @ uv)).mean() for uv in uvs[sel]]
        return uvs[sel][int(np.argmax(share))].mean(0)

    paint_uv = best(zone == BODY, lambda px: turquoise(px, TURQUOISE))
    accent_uv = best(zone == ACCENT, lambda px: px.mean(1) > WHITE_LUM)
    mid = tris.mean(1)
    lid = ((mid[:, 2] > LID_Z[0]) & (mid[:, 2] < LID_Z[1]) & (np.abs(mid[:, 0]) < LID_HALF)
           & (nrms.mean(1)[:, 2] > 0.5) & (group == 'body')
           & (texel(rgba[..., :3], uvs.mean(1)).max(1) < 16))
    keep = group != None  # noqa: E711 (an object array)

    def to_yup(a):
        return np.stack([a[..., 0], a[..., 2], -a[..., 1]], -1)

    tris, nrms = to_yup(tris), to_yup(nrms)
    tire = to_yup(np.concatenate(wheels))
    body = tris[keep & ~glass & (group == 'body')].reshape(-1, 3)
    every = tris[keep].reshape(-1, 3)
    lo, hi = every.min(0), every.max(0)
    sx = WIDTH * IN / (body[:, 0].max() - body[:, 0].min())
    sz = LENGTH * IN / (hi[2] - lo[2])
    scale = np.array([sx, (sx + sz) / 2, sz])
    origin = np.array([(body[:, 0].min() + body[:, 0].max()) / 2, lo[1], (lo[2] + hi[2]) / 2])

    def to_game(q):
        return (q - origin) * scale

    # The lid clipped at LID_CUT: what lies behind it stays.
    plane = LID_CUT / scale[2] + origin[2]
    kept_t, kept_n, kept_uv = [], [], []
    for t, n, uv in zip(tris[lid], nrms[lid], uvs[lid]):
        for piece in clip_behind(t, plane):
            kept_t.append(piece)
            kept_n.append(n)
            kept_uv.append(np.tile(uv.mean(0), (3, 1)))
    group[lid] = None
    keep &= ~lid
    m = len(kept_t)
    tris = np.concatenate([tris, np.array(kept_t).reshape(-1, 3, 3)])
    nrms = np.concatenate([nrms, np.array(kept_n).reshape(-1, 3, 3)])
    uvs = np.concatenate([uvs, np.array(kept_uv).reshape(-1, 3, 2)])
    group = np.concatenate([group, np.full(m, 'body', object)])
    glass = np.concatenate([glass, np.zeros(m, bool)])
    keep = np.concatenate([keep, np.ones(m, bool)])
    print(f'interior lid: {int(lid.sum())} tris, clipped to {m} behind the driver')

    zones = zone_map(rgba.shape[:2], zip(uvs, zone))
    rgb, paint_alpha = body_albedo(rgba[..., :3].copy(), zones)
    albedo = Image.merge('RGBA', [*Image.fromarray(rgb).split(),
                                  Image.fromarray(np.uint8(np.round(paint_alpha * 255)))])
    rough = Image.open(os.path.join(ROOT, TEXTURES % 'Roughness')).convert('L')
    metal = Image.open(os.path.join(ROOT, TEXTURES % 'Metallic')).convert('L')
    orm = Image.merge('RGB', [Image.new('L', rough.size, 255), rough, metal])
    normal = Image.open(os.path.join(ROOT, TEXTURES % 'Normal')).convert('RGB')

    out = Gltf()
    out.images += [png_bytes(albedo), png_bytes(orm), png_bytes(normal)]
    out.textures += [0, 1, 2]
    out.materials.append({
        'name': 'belair',
        'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicRoughnessTexture': {'index': 1},
                                 'metallicFactor': 1.0, 'roughnessFactor': 1.0},
        'occlusionTexture': {'index': 1},
        'normalTexture': {'index': 2},
        'alphaMode': 'OPAQUE',
        'doubleSided': True,
    })
    out.materials.append(fva.GLASS_MATERIAL)

    def primitives(sel, frame=None):
        prims = []
        for mat, which in ((0, sel & ~glass), (1, sel & glass)):
            if not which.any():
                continue
            pos = to_game(tris[which]).reshape(-1, 3)
            nrm = (nrms[which] / scale).reshape(-1, 3)
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
            uv = uvs[which].reshape(-1, 2).copy()
            uv[:, 1] = 1.0 - uv[:, 1]
            if frame is not None:
                o, b = frame
                pos, nrm = (pos - o) @ b, nrm @ b
            p, n, u, index = share_corners(pos.astype(np.float32), nrm.astype(np.float32), uv.astype(np.float32))
            prims.append(out.primitive(p, n, index, mat, u))
        return prims

    # The steering column's slope from the model's half wheel; the new wheel's frame.
    _, axis = ring_axis(to_game(tris[group == 'driving_wheel']).reshape(-1, 3))
    hub = np.array(WHEEL_HUB)
    across = np.array([1.0, 0.0, 0.0]) - axis[0] * axis
    across /= np.linalg.norm(across)
    wheel_basis = np.stack([across, np.cross(axis, across), axis], 1)

    # How far out the cabin reaches at a height and a place along the car: the body's sides
    # (doors, pillars, wheel housings) found across from the middle.
    # The glass counts: where a window is nearest, the dash stops at it.
    side = to_game(tris[keep & (group == 'body')])
    side = side[side[:, :, 0].max(1) > SIDE_FROM]

    def skin(y, z):
        a, b, c = side[:, 0], side[:, 1], side[:, 2]
        v0, v1 = (b - a)[:, 1:], (c - a)[:, 1:]
        v2 = np.array([y, z]) - a[:, 1:]
        den = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
        ok = np.abs(den) > 1e-12
        den = np.where(ok, den, 1.0)
        l1 = (v2[:, 0] * v1[:, 1] - v1[:, 0] * v2[:, 1]) / den
        l2 = (v0[:, 0] * v2[:, 1] - v2[:, 0] * v0[:, 1]) / den
        hit = ok & (l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)
        x = a[:, 0] + l1 * (b - a)[:, 0] + l2 * (c - a)[:, 0]
        x = x[hit & (x > SIDE_FROM)]
        return float(x.min()) if len(x) else None

    # The dash, its housing round the cluster and the column, painted: in the body's
    # texture, on the paint's and the accent's swatches.
    basis = facing_basis(dash.FACING)
    speedo_at = np.array(dash.SPEEDO_AT)
    dash_parts = []
    for key, t, n in dash.dash_parts(skin):
        dash_parts.append((t, n, paint_uv if key == 'paint' else accent_uv))
    for t, n in dash.pod_parts():
        dash_parts.append((t @ basis.T + speedo_at, n @ basis.T, paint_uv))
    reach = (dash.DASH_BAND[0][1] - hub[2]) / axis[2] + 0.01
    t, n = _frustum(COLUMN_R, dash.HUB_BACK, COLUMN_R, reach, n=20, cap0=False)
    dash_parts.append((t @ wheel_basis.T + hub, n @ wheel_basis.T, paint_uv))

    def painted():
        pos = np.concatenate([t.reshape(-1, 3) for t, _, _ in dash_parts])
        nrm = np.concatenate([n.reshape(-1, 3) for _, n, _ in dash_parts])
        uv = np.concatenate([np.tile(s_, (t.size // 3, 1)) for t, _, s_ in dash_parts]).copy()
        uv[:, 1] = 1.0 - uv[:, 1]
        p, n, u, index = share_corners(pos.astype(np.float32), nrm.astype(np.float32), uv.astype(np.float32))
        return out.primitive(p, n, index, 0, u)

    name = os.path.splitext(os.path.basename(dst))[0]
    roots = [out.node(name, mesh=out.mesh(name, primitives(group == 'body') + [painted()]))]
    for g in ('bumper_front', 'bumper_rear'):
        roots.append(out.node(g, mesh=out.mesh(g, primitives(group == g))))

    # The steering wheel.
    albedo, orm_png, swatch_uv = dash.wheel_texture()
    base = len(out.images)
    out.images += [albedo, orm_png]
    out.textures += [base, base + 1]
    wheel_mat = len(out.materials)
    out.materials.append({'name': 'belair_steering_wheel', 'doubleSided': True,
                          'pbrMetallicRoughness': {'baseColorTexture': {'index': base},
                                                   'metallicRoughnessTexture': {'index': base + 1},
                                                   'metallicFactor': 1.0, 'roughnessFactor': 1.0}})

    def prim(t, n, uv, material):
        p, nn, u, index = share_corners(t.reshape(-1, 3).astype(np.float32), n.reshape(-1, 3).astype(np.float32),
                                        uv.reshape(-1, 2).astype(np.float32))
        return out.primitive(p, nn, index, material, u)

    parts = dash.wheel_parts()
    wt = np.concatenate([orient(t, n)[0] for _, t, n in parts])
    wn = np.concatenate([orient(t, n)[1] for _, t, n in parts])
    wu = np.concatenate([np.tile(swatch_uv[k], (len(t), 3, 1)) for k, t, _ in parts])
    wheel_mesh = out.mesh('driving_wheel_mesh', [prim(wt, wn, wu, wheel_mat)])
    roots.append(out.node('driving_wheel', translation=hub, rotation=quaternion(wheel_basis),
                          children=[out.node('driving_wheel_mesh', mesh=wheel_mesh)]))
    # The gear lever out of the column, which stays put as the wheel turns.
    parts = dash.lever_parts()
    lt = np.concatenate([orient(t, n)[0] for _, t, n in parts])
    ln = np.concatenate([orient(t, n)[1] for _, t, n in parts])
    lu = np.concatenate([np.tile(swatch_uv[k], (len(t), 3, 1)) for k, t, _ in parts])
    roots.append(out.node('gear_lever', translation=hub, rotation=quaternion(wheel_basis),
                          mesh=out.mesh('gear_lever', [prim(lt, ln, lu, wheel_mat)])))

    # The front seat, the toe board and the carpet.
    albedo, orm_png, seat_uv = dash.wheel_texture(dash.INTERIOR_SWATCHES)
    base = len(out.images)
    out.images += [albedo, orm_png]
    out.textures += [base, base + 1]
    seat_mat = len(out.materials)
    out.materials.append({'name': 'belair_interior', 'doubleSided': True,
                          'pbrMetallicRoughness': {'baseColorTexture': {'index': base},
                                                   'metallicRoughnessTexture': {'index': base + 1},
                                                   'metallicFactor': 1.0, 'roughnessFactor': 1.0}})
    parts = dash.interior_parts(skin)
    it = np.concatenate([t for _, t, _ in parts])
    inn = np.concatenate([n for _, _, n in parts])
    iu = np.concatenate([np.tile(seat_uv[k], (len(t), 3, 1)) for k, t, _ in parts])
    roots.append(out.node('interior', mesh=out.mesh('interior', [prim(it, inn, iu, seat_mat)])))

    # The cluster with the speedometer's needle, the gas gauge's pointer in its own pod, the
    # grille, the radio and the knobs.
    dmat = {}
    for key, material in dash.DASH_MATERIALS.items():
        dmat[key] = len(out.materials)
        out.materials.append(material)
    for key, image, extra in (('face', dash.face_png(), dash.face_material),
                              ('grille', png_bytes(dash.grille_texture()), None),
                              ('radio', png_bytes(dash.radio_texture()), None)):
        out.images.append(image)
        out.textures.append(len(out.images) - 1)
        tex = len(out.textures) - 1
        dmat[key] = len(out.materials)
        out.materials.append(extra(tex) if extra else
                             {'name': f'dash_belair_{key}_mat', 'doubleSided': True,
                              'pbrMetallicRoughness': {'baseColorTexture': {'index': tex},
                                                       'metallicFactor': 0.9, 'roughnessFactor': 0.2}})

    def dash_mesh(mesh_name, parts):
        by_mat = {}
        for mat, t, n, uv in parts:
            t, n = orient(t, n)
            uv = np.zeros(t.shape[:2] + (2,)) if uv is None else uv
            by_mat.setdefault(mat, []).append((t, n, uv))
        return out.mesh(mesh_name, [prim(np.concatenate([a for a, _, _ in v]), np.concatenate([b for _, b, _ in v]),
                                         np.concatenate([c for _, _, c in v]), dmat[m]) for m, v in by_mat.items()])

    cluster = dash.cluster_parts()
    face = out.node('dash_belair_cluster', mesh=dash_mesh('dash_belair_cluster', cluster['fixed']))
    needle = out.node('speedo_needle', mesh=dash_mesh('speedo_needle', cluster['speedo']))
    roots.append(out.node('dash_speedo_arch_%d_mph_%d_pod' % (dash.SPEEDO_SWEEP, dash.SPEEDO_MAX),
                          translation=speedo_at, rotation=quaternion(basis), children=[face, needle]))
    gx, gz = cluster['gas_at']
    gas_at = speedo_at + basis @ np.array([gx, 0.0, gz])
    pointer = out.node('fuel_needle', mesh=dash_mesh('fuel_needle', cluster['gas']))
    roots.append(out.node('dash_fuel_linear_%.4f_pod' % cluster['gas_travel'], translation=gas_at,
                          rotation=quaternion(basis), children=[pointer]))
    panels = [('grille', *dash.on_face(dash.DASH_UPPER, *dash.GRILLE_Y, *dash.GRILLE_X, dash.PANEL_OUT)),
              ('radio', *dash.on_face(dash.DASH_BAND, *dash.RADIO_Y, *dash.RADIO_X, dash.PANEL_OUT))]
    knob_z = dash.face_z(dash.DASH_BAND, dash.KNOB_Y)
    panels += [('knob', *dash.knob(x, dash.KNOB_Y, knob_z), None) for x in dash.KNOBS_X]
    roots.append(out.node('dash_belair_panel', mesh=dash_mesh('dash_belair_panel', panels)))
    out.write(dst, roots)

    size_m = (hi - lo) * scale
    print(f'{dst}: {int(keep.sum())} tris ({int((keep & glass).sum())} glass), '
          f'{os.path.getsize(dst) / 1e6:.1f} MB, size {size_m.round(3)} m ({(size_m / IN).round(1)} in), '
          f'scale {scale.round(4)}')
    w = to_game(tire)
    radius = (w[:, 1].max() - w[:, 1].min()) / 2
    centers = []
    for sx_ in (1, -1):
        for sz_ in (1, -1):
            q = w[(np.sign(w[:, 0]) == sx_) & (np.sign(w[:, 2]) == sz_)]
            centers.append((q.min(0) + q.max(0)) / 2)
    centers = np.array(centers)
    print('model tire radius %.3f m (%.1f in diameter)' % (radius, radius * 2 / IN))
    for label, c in zip(('front left', 'rear left', 'front right', 'rear right'), centers):
        print('  wheel %-11s %s' % (label, c.round(3)))
    print('wheelbase %.1f in (real %.1f), track %.1f in' % ((centers[0, 2] - centers[1, 2]) / IN, WHEELBASE,
                                                            (centers[0, 0] - centers[2, 0]) / IN))
    print('ground clearance in the model %.3f m' % (-w[:, 1].min()))
    print('steering wheel hub', hub.round(3), 'axis', axis.round(3))
    print('speedometer pivot', speedo_at.round(3), 'gas pointer at F', gas_at.round(3))
    print('model height %.4f m' % size_m[1])


if __name__ == '__main__':
    build(sys.argv[1])
