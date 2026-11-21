#!/usr/bin/env python3
"""Convert Artem P's 1970 Dodge Challenger (a two-door hardtop) into a car body GLB.

    python3 -I tools/challenger_to_glb.py reference/cars/1970-Dodge-Challenger \
        assets/cars/dodge-challenger-1970.glb

Source: "Dodge Challenger 1970" by Artem P (temp0.crazy), CC-BY-4.0,
https://sketchfab.com/3d-models/dodge-challenger-1970-915d29c2e6af4ef8a48a93337835f3c8

The download is a Blender 2.79 scene (source/1970 Dodge challenger.blend: Z up, nose
toward -Y, about 2.8 times real size) built from half-panels with mirror and subdivision
modifiers, colored by material settings rather than textures; only the plates and the
vinyl roof's grain use images (textures/). Blender opens the scene (this script runs
itself under `blender -b` for that, so Blender must be on the PATH), applies the
modifiers and hands back every mesh's triangles in world space; the rest is plain Python.

To keep the triangle count down (the scene is about 606k triangles without its wheels):

  * each subdivision modifier runs one level below the model's viewport setting on the
    big panels that show their curves (FINE_PANELS) and two below everywhere else, at
    least 1;
  * the grille's modeled wire lattice (44k triangles) becomes a curved sheet that
    follows the lattice's back face, with the lattice's square holes as a repeating
    texture (GRILLE_*);
  * every badge becomes a decal (DECALS): its colors, finish and the relief of its
    letters baked, seen straight on, into one texture atlas, on a small grid that follows
    the surface behind it DECAL_OUT in front of it, cut out by an alpha mask;
  * the headlights lose their bulbs (DROP) and their lenses' thickness: a 1970 sealed
    beam shows its prism-patterned glass, not a bulb.

The model's wheels are left out: the game mounts its own wheels. Their centers set the
wheel positions printed at the end.

The GLB is laid out like the Studebaker's (tools/studebaker_to_glb.py):

  * Y up, nose along +Z, driver's side +X;
  * centered on X and Z, lowest point of the body at Y = 0;
  * real size in meters, each axis on its own: 191.3 in long, 76.1 in wide and 50.9 in
    from the bottom of the model's tires to the roof;
  * a palette texture, CELL px per color: the red paint is white with alpha 1, which
    car_paint_mask.gdshader multiplies by the car's paint, the vinyl roof and the black
    tail panel yellow with alpha 1, which it paints with the accent (ACCENT_PARTS; the
    car file gives the accent's color and finish), everything else alpha 0;
  * an ORM palette in the same layout (R = AO, G = roughness, B = metallic);
  * the plates on their own material with the download's plate image, its
    registration painted out (PLATE_RECT);
  * the glass and the headlight lenses as their own see-through materials, so the paint
    shader never touches them; the lenses frosted, with the scene's prism pattern (a grid
    of vertical flutes over horizontal bands, LENS_*) as a repeating normal map
    projected from the front;
  * the bumpers as `bumper_front` and `bumper_rear` nodes so the game can strip them,
    with a panel of body paint behind each where the body is open (BACKING_*);
  * an interior (tools/challenger_interior.py) in place of the model's stand-in (the lid
    at the window line, the block seats and the ring of `Inside` are left out, its
    underbody kept): the Rallye dash with working speedometer, tachometer and gas gauge
    under `dash_` nodes, the steering wheel as `driving_wheel`, seats, carpet, trim.

The numbers the .car file needs are printed at the end.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np

LENGTH_M = 191.3 * 0.0254
WIDTH_M = 76.1 * 0.0254
HEIGHT_M = 50.9 * 0.0254
BLEND = 'source/1970 Dodge challenger.blend'
PLATE_IMAGE = 'textures/Lic.jpeg'
CELL = 32
## The panels that keep one more level of subdivision than the rest.
FINE_PANELS = {'Hood', 'Door', 'Roof', 'Trunk', 'FrontBumper', 'BackBumper', 'FrontDown', 'BackDown'}
## The grille lattice (mirrored half, model units): a square grid of GRILLE_PITCH cells
## (across, up) with bars GRILLE_BAR wide. The sheet that replaces it has GRILLE_COLUMNS
## strips across the half, each at the depth of the lattice's back face there.
GRILLE = 'FrontGrill'
GRILLE_PITCH = (0.0241, 0.0229)
GRILLE_BAR = 0.0077
GRILLE_COLUMNS = 24
GRILLE_TILE = 32
GRILLE_BAR_COLOR = (48, 46, 44)
GRILLE_ROUND = 1.6
GRILLE_HOLE_COLOR = (4, 4, 4)
## Badges baked into decals, one each: the grille's script and R/T, the trunk lid's,
## each front fender's, DODGE on the hood lip and on the tail panel, and FUEL on the cap
## ("DogdeLogo" is the scene's own spelling). Each is seen straight on along the normal
## of its best-fit plane, baked at DECAL_RES meters a texel from DECAL_SUPER times as fine
## a raster, and drawn on a grid (about DECAL_GRID meters a cell) that follows the
## surface behind it, DECAL_OUT in front of it. A surface found more than DECAL_DEEP
## behind the badge is past an edge, and the grid stays flat there. The decals share
## one atlas DECAL_ATLAS px wide, DECAL_PAD px apart.
DECALS = ['ChallengerLogo', 'RT', 'ChallengerLogoBack', 'RTBack', 'ChallengerLogoSideL', 'RTL',
          'ChallengerLogoSideR', 'RTR', 'DogdeLogo', 'DogdeLogoBack', 'FuelText']
DECAL_OUT = 0.002
DECAL_RES = 0.0004
DECAL_SUPER = 4
DECAL_MARGIN = 0.002
DECAL_GRID = 0.008
DECAL_DEEP = 0.03
DECAL_ATLAS = 1024
DECAL_PAD = 4
## Middle of the car, for which way a badge faces (away from it), game frame.
CAR_MIDDLE = (0.0, 0.55, 0.0)

## Mesh objects by name. The four wheels (tire, rim, valve) are TireL1 ... TireR2.
WHEEL_PREFIX = 'Tire'
## The headlight bulbs.
DROP = {'FrontLight'}
## The headlight lenses: drawn once, without the solidify modifier's inner skin.
LENS_OBJECT = 'FrontLightLens'
BUMPERS = {
    'bumper_front': {'FrontBumper', 'FrontBumperDetail'},
    'bumper_rear': {'BackBumper', 'BackBumperDetail', 'BackBumperSupp'},
}
BODY = 'Body'
## Behind each bumper the body is open: its panels stop at the bumper's edges. A panel of
## body paint closes the gap, a grid BACKING_CELL (x, y) m that follows the bumper's
## rearmost surface seen from straight ahead (or behind), BACKING_INSET further in, so
## the bumper hides it.
BACKING_CELL = (0.02, 0.01)
BACKING_INSET = 0.004
## The second paint (the car file's model.accent): the vinyl roof and the black tail
## panel round the taillights, by (object, material). Their palette cell is yellow, paint
## (alpha 1) with no blue, which car_paint_mask.gdshader paints with the accent.
ACCENT = 'Accent'
ACCENT_PARTS = {('Roof', 'Leather'), ('BackPlate', 'BlackMetal')}
## The model's stand-in interior: its pieces wholly above INSIDE_DROP_Y (game frame) are
## the lid, the block seats and the ring, and are left out; the underbody stays.
INSIDE = 'Inside'
INSIDE_DROP_Y = 0.6
## The headliner: a grid HEADLINER_GAP under the lowest of these parts' surfaces higher
## than HEADLINER_ABOVE, over the roof between the windshield's and back window's tops
## and the side glass (game frame).
ROOF_PARTS = {'Body', 'Roof'}
HEADLINER_ABOVE = 0.95
HEADLINER_GAP = 0.012
HEADLINER_SPAN = ((-0.70, 0.70), (-1.12, 0.29))
HEADLINER_GRID = (29, 37)
GRILLE_MATERIAL = 'Grille'
GLASS = 'Glass'
LENS = 'Lens'
PLATE = 'License'
## The plate image (1000 x 498): its registration, inside the rim and below the state
## name and the year tabs, clear of the bolt holes.
PLATE_RECT = (45, 182, 955, 428)

## (color, paint, (AO, roughness, metallic)) by the scene's material names; colors are
## the model's (its linear base colors in sRGB), the lamps' set to what they show lit
## from outside (the model gets them through transmission).
PLAIN = (255, round(0.82 * 255), round(0.05 * 255))
CHROME = ((240, 240, 244), False, (255, 15, 255))
LOOKS = {
    'Body': ((255, 255, 255), True, PLAIN),
    'Chrome': CHROME,
    'Mirror': CHROME,
    'GrillMetal': ((32, 27, 22), False, (255, 70, 230)),
    'BlackMetal': ((22, 22, 22), False, (255, 60, 200)),
    'BlackPlastic': ((18, 18, 18), False, (255, 165, 0)),
    'black': ((8, 8, 8), False, (255, 230, 0)),
    'Rubber': ((16, 16, 16), False, (255, 180, 0)),
    'Leather': ((24, 24, 24), False, (255, 140, 0)),
    'RedPlastic': ((160, 4, 12), False, (255, 40, 30)),
    'RearLights': ((185, 18, 16), False, (255, 20, 0)),
    'OrangeGlass': ((225, 110, 30), False, (255, 20, 0)),
    'WhitePlastic': ((240, 232, 232), False, (255, 20, 0)),
    'FrontLight': ((235, 233, 200), False, (255, 30, 0)),
    ACCENT: ((255, 255, 0), True, (255, 140, 0)),
}
GLASS_MATERIAL = {
    'name': 'glass',
    'pbrMetallicRoughness': {'baseColorFactor': [0.62, 0.72, 0.70, 0.22],
                             'metallicFactor': 0.0, 'roughnessFactor': 0.04},
    'alphaMode': 'BLEND',
    'doubleSided': True,
}
## The lens's prism pattern, from the scene's two brick textures on object coordinates
## (model units): flutes LENS_PITCH[0] apart across the lamp, bands LENS_PITCH[1] apart
## up it, each rounded at its edges. Baked as one cell, LENS_TILE px, and repeated.
LENS_PITCH = (0.3 / 15.2, 0.8 / 15.2)
LENS_TILE = (32, 64)
LENS_ROUND = 1.2
## The frosted glass (RGBA) and its color on the seams between cells, which reach
## LENS_SEAM (model units) into each cell.
LENS_GLASS = (232, 234, 228, 110)
LENS_SEAM_COLOR = (120, 122, 118, 200)
LENS_SEAM = 0.006
LENS_MATERIAL = {
    'name': 'lens',
    'pbrMetallicRoughness': {'metallicFactor': 0.0, 'roughnessFactor': 0.08},
    'alphaMode': 'BLEND',
    'doubleSided': True,
}


def dump(blend, out):
    """Under Blender: every mesh's triangle corners in world space after its modifiers,
    with normals and UVs, by object and material, into an .npz."""
    import bpy
    import numpy as np
    bpy.ops.wm.open_mainfile(filepath=blend, load_ui=False, use_scripts=False)
    for o in bpy.data.objects:
        for m in o.modifiers:
            if m.type == 'SUBSURF':
                m.levels = max(m.levels - (1 if o.name in FINE_PANELS else 2), 1)
        if o.name == LENS_OBJECT:
            for m in list(o.modifiers):
                if m.type == 'SOLIDIFY':
                    o.modifiers.remove(m)
    grille_sheet(bpy.data.objects[GRILLE])
    dg = bpy.context.evaluated_depsgraph_get()
    arrays = {}
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
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
        uv = np.zeros((len(me.loops), 2))
        if me.uv_layers.active:
            flat = np.empty(len(me.loops) * 2)
            me.uv_layers.active.data.foreach_get('uv', flat)
            uv = flat.reshape(-1, 2)
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
        ev.to_mesh_clear()
    np.savez(out, **arrays)


def grille_sheet(lattice):
    """Under Blender: swap the grille's wire lattice for a sheet over the same area,
    its strips at the depth of the lattice's back face (the R/T badge's red fill sits
    inside the lattice's depth), with UVs counting cells."""
    import bpy
    import numpy as np
    co = np.array([v.co[:] for v in lattice.data.vertices])
    x0, x1 = co[:, 0].min(), co[:, 0].max()
    z0, z1 = co[:, 2].min(), co[:, 2].max()
    xs = np.linspace(x0, x1, GRILLE_COLUMNS + 1)
    verts, uvs, faces = [], [], []
    for x in xs:
        near = co[np.abs(co[:, 0] - x) <= (x1 - x0) / GRILLE_COLUMNS / 2]
        for z in (z0, z1):
            verts.append((x, near[:, 1].max(), z))
    for i in range(GRILLE_COLUMNS):
        a = 2 * i
        faces.append((a, a + 2, a + 3, a + 1))
    me = bpy.data.meshes.new('grille_sheet')
    me.from_pydata(verts, [], faces)
    me.update()
    uv = me.uv_layers.new()
    for loop in me.loops:
        x, _, z = verts[loop.vertex_index]
        uv.data[loop.index].uv = ((x - x0) / GRILLE_PITCH[0], (z - z0) / GRILLE_PITCH[1])
    me.materials.append(bpy.data.materials.new('Grille'))
    sheet = bpy.data.objects.new('GrilleSheet', me)
    sheet.matrix_world = lattice.matrix_world
    bpy.context.scene.collection.objects.link(sheet)
    sheet.modifiers.new('mirror', 'MIRROR')
    # Faces toward the front (-Y in the scene).
    if me.polygons[0].normal[1] > 0:
        me.flip_normals()
    bpy.data.objects.remove(lattice)


def grille_tile():
    """(albedo PNG, ORM PNG, normal PNG) for one cell of the grille: a bar along two
    edges, the hole dark; repeated across the sheet. The normal map rounds the bars, so
    their sides catch the light as the modeled wires' did."""
    from PIL import Image
    from studebaker_to_glb import png_bytes
    n = GRILLE_TILE
    bar = (round(GRILLE_BAR / GRILLE_PITCH[0] * n), round(GRILLE_BAR / GRILLE_PITCH[1] * n))
    albedo = np.zeros((n, n, 4), np.uint8)
    albedo[...] = GRILLE_HOLE_COLOR + (0,)
    orm = np.zeros((n, n, 3), np.uint8)
    orm[...] = (40, 230, 0)
    normal = np.zeros((n, n, 3))
    normal[..., 2] = 1.0
    # Across each bar, -1 at one edge to 1 at the other: the slope of a round wire.
    across_u = (np.arange(bar[0]) + 0.5) / bar[0] * 2.0 - 1.0
    across_v = (np.arange(bar[1]) + 0.5) / bar[1] * 2.0 - 1.0
    for rows, cols in ((slice(None), slice(0, bar[0])), (slice(0, bar[1]), slice(None))):
        albedo[rows, cols] = GRILLE_BAR_COLOR + (0,)
        orm[rows, cols] = (255, 70, 230)
    normal[:, :bar[0], 0] = across_u * GRILLE_ROUND
    normal[:bar[1], :, 1] = across_v[:, None] * GRILLE_ROUND
    normal[:bar[1], :bar[0], :2] *= 0.5
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    normal = np.round((normal * 0.5 + 0.5) * 255).astype(np.uint8)
    return (png_bytes(Image.fromarray(albedo, 'RGBA')), png_bytes(Image.fromarray(orm, 'RGB')),
            png_bytes(Image.fromarray(normal, 'RGB')))


def decal_frame(points):
    """(normal, right, up) for a badge: the normal of its points' best-fit plane, turned
    away from the middle of the car; up is the car's up laid into that plane (toward the
    back for a badge lying flat), right is what a viewer facing the badge sees as right."""
    mid = points.mean(0)
    _, _, vt = np.linalg.svd(points - mid)
    n = vt[2] * (1.0 if vt[2] @ (mid - np.array(CAR_MIDDLE)) > 0 else -1.0)
    up = np.array([0.0, 1.0, 0.0]) - n[1] * n
    if np.linalg.norm(up) < 0.3:
        up = np.array([0.0, 0.0, -1.0]) - n[2] * n
    up /= np.linalg.norm(up)
    return n, np.cross(up, n), up


def surface_depth(tris, frame, a, b, limit):
    """Depth along the frame's normal of the front-most of `tris` (game frame) behind
    each point (a, b) of the frame's plane, no deeper than `limit` in front; NaN where
    nothing is behind."""
    n, r, u = frame
    ta, tb, td = tris @ r, tris @ u, tris @ n
    near = ((ta.max(1) >= a.min()) & (ta.min(1) <= a.max()) & (tb.max(1) >= b.min()) &
            (tb.min(1) <= b.max()) & (td.min(1) <= limit))
    ta, tb, td = ta[near], tb[near], td[near]
    pa, pb = a.reshape(-1, 1), b.reshape(-1, 1)
    det = (tb[:, 1] - tb[:, 2]) * (ta[:, 0] - ta[:, 2]) + (ta[:, 2] - ta[:, 1]) * (tb[:, 0] - tb[:, 2])
    ok = np.abs(det) > 1e-14
    ta, tb, td, det = ta[ok], tb[ok], td[ok], det[ok]
    w0 = ((tb[:, 1] - tb[:, 2]) * (pa - ta[:, 2]) + (ta[:, 2] - ta[:, 1]) * (pb - tb[:, 2])) / det
    w1 = ((tb[:, 2] - tb[:, 0]) * (pa - ta[:, 2]) + (ta[:, 0] - ta[:, 2]) * (pb - tb[:, 2])) / det
    w2 = 1.0 - w0 - w1
    d = w0 * td[:, 0] + w1 * td[:, 1] + w2 * td[:, 2]
    hit = (w0 >= 0) & (w1 >= 0) & (w2 >= 0) & (d <= limit)
    best = np.where(hit, d, -np.inf).max(1) if len(td) else np.full(len(pa), -np.inf)
    return np.where(np.isfinite(best), best, np.nan).reshape(a.shape)


def bilinear(grid, fx, fy):
    """`grid` (rows, cols, ...) sampled at fractional column fx and row fy."""
    x0 = np.clip(np.floor(fx).astype(int), 0, grid.shape[1] - 2)
    y0 = np.clip(np.floor(fy).astype(int), 0, grid.shape[0] - 2)
    tx = np.clip(fx - x0, 0, 1)[..., None]
    ty = np.clip(fy - y0, 0, 1)[..., None]
    top = grid[y0, x0] * (1 - tx) + grid[y0, x0 + 1] * tx
    bot = grid[y0 + 1, x0] * (1 - tx) + grid[y0 + 1, x0 + 1] * tx
    return top * (1 - ty) + bot * ty


def bake_decal(tris, normals, looks, frame, box, slope):
    """Bake badge triangles (game frame) seen straight on along the frame's normal into
    (RGBA, ORM, normal) arrays. Columns run along the frame's right from box[0], rows
    down from box[3]; the front-most triangle wins each texel. Normals are turned into
    the frame of the surface under the badge: `slope` (rows, cols, 2) is the surface's
    depth gradient along right and up on the decal's grid, which spans the box."""
    n, r, u = frame
    a0, b0, a1, b1 = box
    res = DECAL_RES / DECAL_SUPER
    w = int(round((a1 - a0) / DECAL_RES)) * DECAL_SUPER
    h = int(round((b1 - b0) / DECAL_RES)) * DECAL_SUPER
    depth = np.full((h, w), -np.inf)
    color = np.zeros((h, w, 3))
    orm = np.zeros((h, w, 3))
    nrm = np.zeros((h, w, 3))
    for tri, tn, look in zip(tris, normals, looks):
        px = (tri @ r - a0) / res
        py = (b1 - tri @ u) / res
        pz = tri @ n
        c0, c1 = max(int(px.min()), 0), min(int(np.ceil(px.max())) + 1, w)
        r0, r1 = max(int(py.min()), 0), min(int(np.ceil(py.max())) + 1, h)
        if c0 >= c1 or r0 >= r1:
            continue
        gx, gy = np.meshgrid(np.arange(c0, c1) + 0.5, np.arange(r0, r1) + 0.5)
        d = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
        if abs(d) < 1e-12:
            continue
        a = ((py[1] - py[2]) * (gx - px[2]) + (px[2] - px[1]) * (gy - py[2])) / d
        b = ((py[2] - py[0]) * (gx - px[2]) + (px[0] - px[2]) * (gy - py[2])) / d
        c = 1.0 - a - b
        inside = (a >= 0) & (b >= 0) & (c >= 0)
        z = a * pz[0] + b * pz[1] + c * pz[2]
        win = inside & (z > depth[r0:r1, c0:c1])
        if not win.any():
            continue
        depth[r0:r1, c0:c1][win] = z[win]
        nn = a[..., None] * tn[0] + b[..., None] * tn[1] + c[..., None] * tn[2]
        nrm[r0:r1, c0:c1][win] = nn[win]
        color[r0:r1, c0:c1][win] = look[0]
        orm[r0:r1, c0:c1][win] = look[2]
    covered = np.isfinite(depth)
    # The surface's slope at each texel; its tangent frame in (right, up, normal).
    rows, cols = slope.shape[0] - 1, slope.shape[1] - 1
    fx = (np.arange(w) + 0.5) / w * cols
    fy = (1.0 - (np.arange(h) + 0.5) / h) * rows
    g = bilinear(slope, np.broadcast_to(fx[None, :], (h, w)), np.broadcast_to(fy[:, None], (h, w)))
    ga, gb = g[..., 0], g[..., 1]
    one, zero = np.ones_like(ga), np.zeros_like(ga)
    face = np.stack([-ga, -gb, one], -1)
    face /= np.linalg.norm(face, axis=-1, keepdims=True)
    tangent = np.stack([one, zero, ga], -1)
    tangent /= np.linalg.norm(tangent, axis=-1, keepdims=True)
    bitangent = np.cross(face, tangent)
    local = np.stack([nrm @ r, nrm @ u, nrm @ n], -1)
    local /= np.maximum(np.linalg.norm(local, axis=-1, keepdims=True), 1e-12)
    ts = np.stack([(local * tangent).sum(-1), (local * bitangent).sum(-1), (local * face).sum(-1)], -1)
    ts[~covered] = (0.0, 0.0, 1.0)
    ts[..., 2] = np.maximum(ts[..., 2], 0.05)
    ts /= np.linalg.norm(ts, axis=-1, keepdims=True)

    def shrink(arr):
        return arr.reshape(h // DECAL_SUPER, DECAL_SUPER, w // DECAL_SUPER, DECAL_SUPER, -1).mean((1, 3))

    cover = shrink(covered[..., None].astype(np.float64))
    weight = np.maximum(cover, 1e-6)
    albedo = shrink(color * covered[..., None]) / weight
    finish = shrink(orm * covered[..., None]) / weight
    finish[cover[..., 0] == 0] = (255, 128, 0)
    normal = shrink(ts)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    return (np.round(np.concatenate([albedo, cover * 255], -1)).astype(np.uint8),
            np.round(finish).astype(np.uint8), np.round((normal * 0.5 + 0.5) * 255).astype(np.uint8))


def decal(tris, normals, looks, others):
    """One badge's decal: (images, positions, normals, UVs in the decal's own image)."""
    frame = decal_frame(tris.reshape(-1, 3))
    n, r, u = frame
    pts = tris.reshape(-1, 3)
    a0, a1 = (pts @ r).min() - DECAL_MARGIN, (pts @ r).max() + DECAL_MARGIN
    b0, b1 = (pts @ u).min() - DECAL_MARGIN, (pts @ u).max() + DECAL_MARGIN
    a1 = a0 + np.ceil((a1 - a0) / DECAL_RES) * DECAL_RES
    b0 = b1 - np.ceil((b1 - b0) / DECAL_RES) * DECAL_RES
    cols = max(2, int(np.ceil((a1 - a0) / DECAL_GRID)))
    rows = max(2, int(np.ceil((b1 - b0) / DECAL_GRID)))
    ga, gb = np.meshgrid(np.linspace(a0, a1, cols + 1), np.linspace(b0, b1, rows + 1))
    back, front = (pts @ n).min(), (pts @ n).max()
    depth = surface_depth(others, frame, ga, gb, front + 0.005)
    depth = np.where(np.isnan(depth) | (depth < back - DECAL_DEEP), back, depth)
    da = np.gradient(depth, ga[0], axis=1)
    db = np.gradient(depth, gb[:, 0], axis=0)
    images = bake_decal(tris, normals, looks, frame, (a0, b0, a1, b1), np.stack([da, db], -1))
    lift = depth + DECAL_OUT
    vpos = ga[..., None] * r + gb[..., None] * u + lift[..., None] * n
    vnrm = n - da[..., None] * r - db[..., None] * u
    vnrm /= np.linalg.norm(vnrm, axis=-1, keepdims=True)
    vuv = np.stack([(ga - a0) / (a1 - a0), (b1 - gb) / (b1 - b0)], -1)
    pos, nrm, uv = [], [], []
    for j in range(rows):
        for i in range(cols):
            for (y, x) in ((j, i), (j, i + 1), (j + 1, i + 1), (j, i), (j + 1, i + 1), (j + 1, i)):
                pos.append(vpos[y, x])
                nrm.append(vnrm[y, x])
                uv.append(vuv[y, x])
    return images, np.array(pos), np.array(nrm), np.array(uv)


def pack_atlas(images):
    """Shelf-pack (RGBA, ORM, normal) image sets into one atlas each; returns the three
    atlases and each image's (x, y, w, h) in it."""
    order = sorted(range(len(images)), key=lambda k: -images[k][0].shape[0])
    places = [None] * len(images)
    x = y = shelf = 0
    for k in order:
        h, w = images[k][0].shape[:2]
        if x + w + DECAL_PAD > DECAL_ATLAS:
            x, y, shelf = 0, y + shelf + DECAL_PAD, 0
        places[k] = (x + DECAL_PAD, y + DECAL_PAD, w, h)
        x += w + DECAL_PAD
        shelf = max(shelf, h)
    height = int(np.ceil((y + shelf + 2 * DECAL_PAD) / 4.0) * 4)
    rgba = np.zeros((height, DECAL_ATLAS, 4), np.uint8)
    orm = np.zeros((height, DECAL_ATLAS, 3), np.uint8)
    orm[...] = (255, 128, 0)
    nrm = np.zeros((height, DECAL_ATLAS, 3), np.uint8)
    nrm[...] = (128, 128, 255)
    for (c, o, nm), (px, py, w, h) in zip(images, places):
        rgba[py:py + h, px:px + w] = c
        orm[py:py + h, px:px + w] = o
        nrm[py:py + h, px:px + w] = nm
    return (rgba, orm, nrm), places


def lens_tile():
    """(color PNG, normal PNG) for one cell of the headlight lens's prism pattern: a
    flute across and a band up, each a rounded rise, added together. The color is the
    frosted glass, darker and less clear where the cells meet, so the grid shows in any
    light (the normal map alone only shows in reflections)."""
    from PIL import Image
    from studebaker_to_glb import png_bytes
    w, h = LENS_TILE
    fu = (np.arange(w) + 0.5) / w
    fv = (np.arange(h) + 0.5) / h
    # Slope of sin(pi f) over the cell: steepest at the edges, flat on top.
    du = np.cos(np.pi * fu) * LENS_ROUND
    dv = np.cos(np.pi * fv) * LENS_ROUND * LENS_PITCH[0] / LENS_PITCH[1]
    n = np.zeros((h, w, 3))
    n[..., 0] = -du[None, :]
    n[..., 1] = -dv[:, None]
    n[..., 2] = 1.0
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    # How near a cell edge each texel is: 1 on the seam, 0 a third of the way in.
    edge = np.maximum(np.clip(1.0 - np.minimum(fu, 1.0 - fu)[None, :] * 3.0 * LENS_PITCH[0] / LENS_SEAM, 0, 1),
                      np.clip(1.0 - np.minimum(fv, 1.0 - fv)[:, None] * 3.0 * LENS_PITCH[1] / LENS_SEAM, 0, 1))
    edge = np.broadcast_to(edge, (h, w))
    glass, seam = np.array(LENS_GLASS, np.float64), np.array(LENS_SEAM_COLOR, np.float64)
    color = glass[None, None] * (1.0 - edge[..., None]) + seam[None, None] * edge[..., None]
    return (png_bytes(Image.fromarray(np.round(color).astype(np.uint8), 'RGBA')),
            png_bytes(Image.fromarray(np.round((n * 0.5 + 0.5) * 255).astype(np.uint8), 'RGB')))


def roof_underside(roof_tris):
    """The headliner's height at points (x, z), game frame: HEADLINER_GAP under the
    lowest roof surface above HEADLINER_ABOVE straight over each; NaN under no roof."""
    tris = np.concatenate(roof_tris)
    tris = tris[tris[:, :, 1].min(1) > HEADLINER_ABOVE]
    # Looking up: depth along -Y is -y, so the front-most is the lowest.
    frame = (np.array([0.0, -1.0, 0.0]), np.array([1.0, 0.0, 0.0]), np.array([0.0, 0.0, 1.0]))

    def under(x, z):
        x, z = np.asarray(x, float), np.asarray(z, float)
        return -surface_depth(tris, frame, x, z, 0.0) - HEADLINER_GAP
    return under


def headliner(under, interior):
    """The headliner under the model's roof: a grid over HEADLINER_SPAN at `under`'s
    height; cells with a corner under no roof are left out."""
    xs = np.linspace(*HEADLINER_SPAN[0], HEADLINER_GRID[0])
    zs = np.linspace(*HEADLINER_SPAN[1], HEADLINER_GRID[1])
    X, Z = np.meshgrid(xs, zs)
    pts = np.stack([X, under(X, Z), Z], -1)
    cells = interior.grid_tris(pts)
    ok = np.isfinite(cells).all(axis=(1, 2))
    cells = cells[ok]
    fn = np.cross(cells[:, 1] - cells[:, 0], cells[:, 2] - cells[:, 0])
    down = fn[:, 1] > 0
    cells[down] = cells[down][:, ::-1]
    return interior._part('Headliner', cells, crease=60.0, closed=False)


def above(tris, y):
    """Which triangles belong to connected pieces lying wholly above height y."""
    keys = np.round(tris.reshape(-1, 3) * 1e5).astype(np.int64)
    _, inverse = np.unique(keys, axis=0, return_inverse=True)
    inverse = inverse.reshape(-1, 3)
    parent = list(range(len(tris)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    owner = {}
    for t, corners in enumerate(inverse):
        for v in corners:
            if v in owner:
                parent[find(t)] = find(owner[v])
            else:
                owner[v] = t
    roots = np.array([find(t) for t in range(len(tris))])
    low = {}
    for t, r in enumerate(roots):
        low[r] = min(low.get(r, np.inf), tris[t, :, 1].min())
    return np.array([low[r] > y for r in roots])


def bumper_backing(tris, sign):
    """A panel behind a bumper (triangles, game frame; sign +1 at the front, -1 at the
    rear): over the cells the bumper covers seen along Z, at its rearmost surface there,
    BACKING_INSET further into the car. Returns positions and normals, by corner."""
    cx, cy = BACKING_CELL
    x0, y0 = tris[..., 0].min() - cx, tris[..., 1].min() - cy
    nx = int(np.ceil((tris[..., 0].max() - x0) / cx)) + 2
    ny = int(np.ceil((tris[..., 1].max() - y0) / cy)) + 2
    deep = np.full((ny, nx), np.inf)
    for t in tris:
        a, b, c = t[:, :2]
        det = (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])
        if abs(det) < 1e-12:
            continue
        i0, i1 = int((t[:, 0].min() - x0) / cx), int((t[:, 0].max() - x0) / cx) + 1
        j0, j1 = int((t[:, 1].min() - y0) / cy), int((t[:, 1].max() - y0) / cy) + 1
        px, py = np.meshgrid(x0 + (np.arange(i0, i1 + 1) + 0.5) * cx, y0 + (np.arange(j0, j1 + 1) + 0.5) * cy)
        u = ((b[0] - px) * (c[1] - py) - (c[0] - px) * (b[1] - py)) / det
        v = ((c[0] - px) * (a[1] - py) - (a[0] - px) * (c[1] - py)) / det
        w = 1 - u - v
        inside = (u >= -1e-9) & (v >= -1e-9) & (w >= -1e-9)
        if not inside.any():
            continue
        d = sign * (u * t[0, 2] + v * t[1, 2] + w * t[2, 2])
        block = deep[j0:j1 + 1, i0:i1 + 1]
        block[inside] = np.minimum(block[inside], d[inside])
    covered = np.isfinite(deep)
    # Each grid corner at the rearmost of the covered cells round it.
    padded = np.pad(deep, 1, constant_values=np.inf)
    corner = np.minimum(np.minimum(padded[:-1, :-1], padded[:-1, 1:]), np.minimum(padded[1:, :-1], padded[1:, 1:]))
    z = sign * (corner - BACKING_INSET)
    gx = x0 + np.arange(nx + 1) * cx
    gy = y0 + np.arange(ny + 1) * cy
    pos = []
    for j, i in zip(*np.nonzero(covered)):
        q = [np.array([gx[ii], gy[jj], z[jj, ii]]) for jj, ii in ((j, i), (j, i + 1), (j + 1, i + 1), (j + 1, i))]
        pos += [q[0], q[1], q[2], q[0], q[2], q[3]] if sign > 0 else [q[0], q[2], q[1], q[0], q[3], q[2]]
    pos = np.array(pos)
    t = pos.reshape(-1, 3, 3)
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    return pos, np.repeat(n, 3, axis=0)


def load_pieces(path):
    data = np.load(path)
    pieces = {}
    for key in data.files:
        name, mat, kind = key.split('|')
        pieces.setdefault((name, mat), {})[kind] = data[key]
    return pieces


def plate_png(path):
    """The download's plate with its registration painted out: the plate's own black
    with a fine grain, so it carries no registration."""
    from PIL import Image
    from studebaker_to_glb import png_bytes
    rgb = np.asarray(Image.open(path).convert('RGB')).copy()
    x0, y0, x1, y1 = PLATE_RECT
    face = rgb[y0:y1, x0:x1].astype(np.float64)
    bare = face[face.mean(2) < 60]
    grain = np.random.default_rng(1970).normal(0.0, 2.5, face.shape[:2])[..., None]
    rgb[y0:y1, x0:x1] = np.clip(np.median(bare, 0) + grain, 0, 255).astype(np.uint8)
    im = Image.fromarray(rgb).resize((512, 256), Image.LANCZOS)
    return png_bytes(Image.merge('RGBA', [*im.split(), Image.new('L', im.size, 0)]))


def build(src, dst):
    import math
    from PIL import Image
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from studebaker_to_glb import Gltf, png_bytes, share_corners
    from studebaker_dash import MATERIALS, quaternion
    import challenger_interior as interior
    looks_all = dict(LOOKS, **{k: v for k, v in interior.LOOKS.items() if k not in LOOKS})

    with tempfile.TemporaryDirectory() as tmp:
        npz = os.path.join(tmp, 'pieces.npz')
        subprocess.run(['blender', '-b', '--factory-startup', '--disable-autoexec', '--python',
                        os.path.abspath(__file__), '--', 'dump', os.path.join(src, BLEND), npz],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        pieces = load_pieces(npz)

    # Blender's frame (Z up, nose -Y) to the game's (Y up, nose +Z, driver's side +X).
    def to_yup(a):
        return np.stack([a[..., 0], a[..., 2], -a[..., 1]], -1)

    for p in pieces.values():
        p['pos'] = to_yup(p['pos'])
        p['nrm'] = to_yup(p['nrm'])
    wheel = np.concatenate([p['pos'] for k, p in pieces.items() if k[0].startswith(WHEEL_PREFIX)])
    kept = {k: p for k, p in pieces.items() if not k[0].startswith(WHEEL_PREFIX) and k[0] not in DROP}
    for name, mat in [k for k in kept if k in ACCENT_PARTS]:
        kept[(name, ACCENT)] = kept.pop((name, mat))
    unknown = {mat for _, mat in kept} - set(LOOKS) - {GLASS, LENS, PLATE, GRILLE_MATERIAL}
    if unknown:
        raise SystemExit(f'no look for materials {sorted(unknown)}')
    allp = np.concatenate([p['pos'] for p in kept.values()])
    body = np.concatenate([p['pos'] for k, p in kept.items() if k[0] == BODY])
    lo, hi = allp.min(0), allp.max(0)
    floor = wheel[:, 1].min()
    scale = np.array([WIDTH_M / (body[:, 0].max() - body[:, 0].min()),
                      HEIGHT_M / (hi[1] - floor),
                      LENGTH_M / (hi[2] - lo[2])])
    origin = np.array([(body[:, 0].min() + body[:, 0].max()) / 2, lo[1], (lo[2] + hi[2]) / 2])

    def to_game(q):
        return (q - origin) * scale

    # The stand-in interior's lid, block seats and ring.
    for key in [k for k in kept if k[0] == INSIDE]:
        p = kept[key]
        keep = ~above(to_game(p['pos']).reshape(-1, 3, 3), INSIDE_DROP_Y)
        for k in ('pos', 'nrm', 'uv'):
            p[k] = p[k].reshape(len(keep), 3, -1)[keep].reshape(-1, p[k].shape[-1])

    under = roof_underside([to_game(p['pos']).reshape(-1, 3, 3) for (nm, _), p in kept.items()
                            if nm in ROOF_PARTS])
    inside_parts = interior.interior_parts(under)
    inside_parts.append(headliner(under, interior))
    looks = sorted({mat for _, mat in kept if mat in LOOKS} | {m for m, *_ in inside_parts if m in looks_all})
    grid = math.ceil(math.sqrt(len(looks)))
    size = grid * CELL
    albedo = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    orm = Image.new('RGB', (size, size), PLAIN)
    cells = {}
    for i, mat in enumerate(looks):
        color, paint, finish = looks_all[mat]
        cx, cy = i % grid, i // grid
        box = (cx * CELL, cy * CELL, cx * CELL + CELL, cy * CELL + CELL)
        albedo.paste(color + ((255,) if paint else (0,)), box)
        orm.paste(finish, box)
        cells[mat] = ((cx + 0.5) / grid, (cy + 0.5) / grid)

    out = Gltf()
    out.images = [png_bytes(albedo), png_bytes(orm), plate_png(os.path.join(src, PLATE_IMAGE)), *grille_tile(),
                  *lens_tile()]
    out.textures = [0, 1, 2, 3, 4, 5, 6, 7]
    lens_material = dict(LENS_MATERIAL, normalTexture={'index': 7})
    lens_material['pbrMetallicRoughness'] = dict(LENS_MATERIAL['pbrMetallicRoughness'],
                                                 baseColorTexture={'index': 6})
    out.materials = [{
        'name': 'challenger_palette',
        'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                 'metallicRoughnessTexture': {'index': 1},
                                 'metallicFactor': 1.0, 'roughnessFactor': 1.0},
        'alphaMode': 'OPAQUE', 'doubleSided': True,
    }, GLASS_MATERIAL, lens_material, {
        'name': 'plate',
        'pbrMetallicRoughness': {'baseColorTexture': {'index': 2},
                                 'metallicFactor': 0.3, 'roughnessFactor': 0.45},
        'alphaMode': 'OPAQUE', 'doubleSided': True,
    }, {
        'name': 'grille',
        'pbrMetallicRoughness': {'baseColorTexture': {'index': 3},
                                 'metallicRoughnessTexture': {'index': 4},
                                 'metallicFactor': 1.0, 'roughnessFactor': 1.0},
        'occlusionTexture': {'index': 4},
        'normalTexture': {'index': 5},
        'alphaMode': 'OPAQUE', 'doubleSided': True,
    }]
    slot = {GLASS: 1, LENS: 2, PLATE: 3, GRILLE_MATERIAL: 4}

    # Decals: baked from the badges' triangles, which then leave the model; the surface
    # behind each is found among everything else.
    from PIL import Image
    others = np.concatenate([to_game(p['pos']) for (nm, mat), p in kept.items()
                             if nm not in DECALS and mat not in (GLASS, LENS)]).reshape(-1, 3, 3)
    baked = []
    for badge in DECALS:
        parts = [(to_game(p['pos']), p['nrm'] / scale, mat) for (nm, mat), p in kept.items() if nm == badge]
        tris = np.concatenate([q for q, _, _ in parts]).reshape(-1, 3, 3)
        tnrm = np.concatenate([nn for _, nn, _ in parts]).reshape(-1, 3, 3)
        tnrm /= np.linalg.norm(tnrm, axis=-1, keepdims=True)
        looks_of = [LOOKS[m] for q, _, m in parts for _ in range(len(q) // 3)]
        baked.append(decal(tris, tnrm, looks_of, others))
    atlas, places = pack_atlas([b[0] for b in baked])
    first = len(out.images)
    out.images += [png_bytes(Image.fromarray(atlas[0], 'RGBA')), png_bytes(Image.fromarray(atlas[1], 'RGB')),
                   png_bytes(Image.fromarray(atlas[2], 'RGB'))]
    out.textures += [first, first + 1, first + 2]
    slot['decals'] = len(out.materials)
    out.materials.append({
        'name': 'badges',
        'pbrMetallicRoughness': {'baseColorTexture': {'index': first},
                                 'metallicRoughnessTexture': {'index': first + 1},
                                 'metallicFactor': 1.0, 'roughnessFactor': 1.0},
        'normalTexture': {'index': first + 2},
        'alphaMode': 'MASK', 'alphaCutoff': 0.5,
    })
    atlas_h = atlas[0].shape[0]
    decal_meshes = []
    for (_, pos, nrm, uv), (px, py, w, h) in zip(baked, places):
        uv = np.stack([(px + uv[:, 0] * w) / DECAL_ATLAS, (py + uv[:, 1] * h) / atlas_h], -1)
        decal_meshes.append((pos, nrm, uv))
    kept = {k: p for k, p in kept.items() if k[0] not in DECALS}

    groups = {}
    for (name, mat), p in kept.items():
        pos = to_game(p['pos'])
        nrm = p['nrm'] / scale
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
        if mat in LOOKS:
            uv = np.tile(np.array(cells[mat]), (len(pos), 1))
        elif mat == LENS:
            # Projected from the front, in model units, one tile per cell of the pattern.
            uv = np.stack([p['pos'][:, 0] / LENS_PITCH[0], -p['pos'][:, 1] / LENS_PITCH[1]], -1)
        else:
            uv = p['uv'].copy()
            uv[:, 1] = 1.0 - uv[:, 1]
        group = next((g for g, names in BUMPERS.items() if name in names), 'body')
        groups.setdefault(group, {}).setdefault(slot.get(mat, 0), []).append((pos, nrm, uv))
    for pos, nrm, uv in decal_meshes:
        groups['body'].setdefault(slot['decals'], []).append((pos, nrm, uv))
    for group, sign in (('bumper_front', 1), ('bumper_rear', -1)):
        tris = np.concatenate([q for parts in groups[group].values() for q, _, _ in parts]).reshape(-1, 3, 3)
        pos, nrm = bumper_backing(tris, sign)
        groups['body'][0].append((pos, nrm, np.tile(np.array(cells[BODY]), (len(pos), 1))))

    # The interior: its plain parts on the palette, the woodgrain on its own texture
    # (alpha 0, so the game leaves it unpainted).
    wood_albedo, wood_orm = interior.wood_texture()
    first = len(out.images)
    out.images += [wood_albedo, wood_orm]
    out.textures += [first, first + 1]
    slot['wood'] = len(out.materials)
    out.materials.append({'name': 'woodgrain', 'doubleSided': True,
                          'pbrMetallicRoughness': {'baseColorTexture': {'index': first},
                                                   'metallicRoughnessTexture': {'index': first + 1},
                                                   'metallicFactor': 1.0, 'roughnessFactor': 1.0}})

    def interior_entry(mat, tris, nrm, uv):
        if mat in looks_all:
            return 0, (tris.reshape(-1, 3), nrm.reshape(-1, 3), np.tile(np.array(cells[mat]), (tris.size // 3, 1)))
        return slot[mat], (tris.reshape(-1, 3), nrm.reshape(-1, 3), np.asarray(uv).reshape(-1, 2))

    for mat, tris, nrm, uv in inside_parts:
        material, entry = interior_entry(mat, tris, nrm, uv)
        groups['body'].setdefault(material, []).append(entry)
    wheel_groups = {}
    for mat, tris, nrm, uv in interior.wheel_parts():
        material, entry = interior_entry(mat, tris, nrm, uv)
        wheel_groups.setdefault(material, []).append(entry)
    groups['wheel'] = wheel_groups

    # The cluster, under `dash_` nodes: its dial faces lit, its own bezel, cup and needle
    # materials.
    dial_png, _ = interior.dial_texture()
    dial_tex = len(out.textures)
    out.images.append(dial_png)
    out.textures.append(len(out.images) - 1)
    dmat = {'face': len(out.materials)}
    out.materials.append({'name': 'challenger_dials', 'doubleSided': True,
                          'emissiveFactor': [0.55, 0.55, 0.55], 'emissiveTexture': {'index': dial_tex},
                          'pbrMetallicRoughness': {'baseColorTexture': {'index': dial_tex},
                                                   'metallicFactor': 0.0, 'roughnessFactor': 0.45}})
    dmat['cup'] = len(out.materials)
    out.materials.append({'name': 'challenger_cups', 'doubleSided': True,
                          'pbrMetallicRoughness': {'baseColorFactor': [0.035, 0.03, 0.028, 1.0],
                                                   'metallicFactor': 0.1, 'roughnessFactor': 0.6}})
    for key in ('bezel', 'needle', 'pointer', 'cap'):
        dmat[key] = len(out.materials)
        out.materials.append(MATERIALS[key])

    def primitives(group):
        prims = []
        for material, parts in sorted(groups[group].items()):
            pos = np.concatenate([q for q, _, _ in parts]).astype(np.float32)
            nrm = np.concatenate([n for _, n, _ in parts]).astype(np.float32)
            uv = np.concatenate([u for _, _, u in parts]).astype(np.float32)
            p, n, u, index = share_corners(pos, nrm, uv)
            prims.append(out.primitive(p, n, index, material, u))
        return prims

    name = os.path.splitext(os.path.basename(dst))[0]
    roots = [out.node(name, mesh=out.mesh(name, primitives('body')))]
    for group in BUMPERS:
        roots.append(out.node(group, mesh=out.mesh(group, primitives(group))))

    # The steering wheel, turned by the game about its +Z (down the column).
    hub, wheel_basis = interior.wheel_frame()
    wheel_mesh = out.mesh('driving_wheel_mesh', primitives('wheel'))
    roots.append(out.node('driving_wheel', translation=hub, rotation=quaternion(wheel_basis),
                          children=[out.node('driving_wheel_mesh', mesh=wheel_mesh)]))

    def dash_mesh(mesh_name, parts):
        by_mat = {}
        for mat, tris, nrm, uv in parts:
            uv = np.zeros(tris.shape[:2] + (2,)) if uv is None else np.asarray(uv)
            by_mat.setdefault(dmat[mat], []).append((tris.reshape(-1, 3), np.asarray(nrm).reshape(-1, 3),
                                                     uv.reshape(-1, 2)))
        prims = []
        for material, entries in sorted(by_mat.items()):
            p, n, u, index = share_corners(np.concatenate([e[0] for e in entries]).astype(np.float32),
                                           np.concatenate([e[1] for e in entries]).astype(np.float32),
                                           np.concatenate([e[2] for e in entries]).astype(np.float32))
            prims.append(out.primitive(p, n, index, material, u))
        return out.mesh(mesh_name, prims)

    cl = interior.cluster_parts()
    c_origin, c_basis = np.asarray(interior.CLUSTER_AT, float), interior.cluster_basis()
    roots.append(out.node('dash_rallye_cluster', translation=c_origin, rotation=quaternion(c_basis),
                          mesh=dash_mesh('dash_rallye_cluster', cl['fixed'])))
    faces = [('face', tris, np.zeros_like(tris) + 0.0, uv) for _, tris, uv in interior.lower_face_quads()]
    faces = [(m, t, np.repeat(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])[:, None], 3, 1), uv)
             for m, t, _, uv in faces]
    roots.append(out.node('dash_radio_heater', mesh=dash_mesh('dash_radio_heater', faces)))
    pods = (('dash_speedo_arch_270_mph_150_pod', 'speedo_needle', cl['speedo'], 0),
            ('dash_tach_pod', 'tach_needle', cl['tach'], 1),
            ('dash_fuel_arch_70_pod', 'fuel_needle', cl['fuel'], 2))
    for pod, needle_name, (tris, nrm), k in pods:
        cx, cz = cl['centers'][k]
        at = c_origin + c_basis @ np.array([cx, 0.0, cz])
        needle = out.node(needle_name, mesh=dash_mesh(needle_name, [('needle', tris, nrm, None)]))
        roots.append(out.node(pod, translation=at, rotation=quaternion(c_basis), children=[needle]))
    out.write(dst, roots)

    size_m = (hi - lo) * scale
    tris = sum(len(p) for g in groups.values() for parts in g.values() for p, _, _ in parts) // 3
    print(f'{dst}: {tris} tris, {os.path.getsize(dst) / 1e6:.1f} MB, '
          f'size {size_m.round(3)} m ({(size_m / 0.0254).round(1)} in), scale {scale.round(4)}')
    for g, names in BUMPERS.items():
        b = np.concatenate([to_game(kept[k]['pos']) for k in kept if k[0] in names])
        print(f'{g}: {b.min(0).round(3)} .. {b.max(0).round(3)}')
    w = to_game(wheel)
    front, rear = w[w[:, 2] > 0], w[w[:, 2] <= 0]
    radius = (w[:, 1].max() - w[:, 1].min()) / 2
    right = front[front[:, 0] > 0]
    track = (right[:, 0].min() + right[:, 0].max()) / 2
    rright = rear[rear[:, 0] > 0]
    rtrack = (rright[:, 0].min() + rright[:, 0].max()) / 2
    fz = (front[:, 2].min() + front[:, 2].max()) / 2
    rz = (rear[:, 2].min() + rear[:, 2].max()) / 2
    wheel_y = (w[:, 1].min() + w[:, 1].max()) / 2
    print('model tire radius %.3f m (%.1f in diameter), width %.1f in'
          % (radius, radius * 2 / 0.0254, (right[:, 0].max() - right[:, 0].min()) / 0.0254))
    print('wheel centers: x front ±%.3f rear ±%.3f (track %.1f / %.1f in), y %.3f (body bottom = 0), '
          'front z %.3f, rear z %.3f, wheelbase %.1f in'
          % (track, rtrack, track * 2 / 0.0254, rtrack * 2 / 0.0254, wheel_y, fz, rz, (fz - rz) / 0.0254))
    print('ground clearance in the model %.3f m' % (-w[:, 1].min()))


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if argv and argv[0] == 'dump':
        dump(argv[1], argv[2])
    else:
        build(argv[0], argv[1])
