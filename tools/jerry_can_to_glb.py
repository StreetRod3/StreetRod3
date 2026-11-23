"""Builds the garage's jerry can GLB from reference/buildings/JerryCan.blend: glossy red
paint over the CS1 base metal, chipped and worn through to the metal on its edges.

    blender -b --factory-startup --python tools/jerry_can_to_glb.py -- \
        reference/buildings/JerryCan.blend reference/parts/CS1_BaseMetal/Textures \
        assets/locations/garage/us_jerry_can.glb

A fourth argument, a folder, also saves the maps and the wear mask there as PNGs to
look at. The source is not changed: the blend is read, never saved.

The blend's mesh is an unwelded CAD export: every triangle stands alone, so every edge
is a boundary and no unwrap can make islands bigger than one triangle. It is welded
(two closed parts: body and cap), its seams cleared, and edges over SHARP_DEG made
sharp. The CAD can has wall thickness, so its inside is modeled too: nearly half the
surface, never seen. Faces no outside ray reaches are found, and the big connected
patches of them (the inside walls) are deleted; small hidden patches in crevices stay
so nothing opens a hole. The CAD fillets are cut finer than a garage prop needs, so
the rest is collapsed to DECIMATE of its triangles (13,016 to 1,560; the surface moves
1.5 mm at most) and its normals weighted by face area, or the long collapsed triangles
smear the shading across the flat panels. It is unwrapped with Smart UV Project at one
texel density and packed by island shape.

The paint is baked onto that unwrap with Cycles. The CS1 maps tile, and are sampled
by box projection in object space (TILE_M meters a tile) so their grain runs across
UV seams unbroken:

  * wear: first an edge mask is drawn from the mesh: every texel's distance to the
    nearest convex edge (faces folding outward by over FEATURE_DEG, which takes in the
    facets of rounded fillets), fading out over EDGE_REACH, plus the bottom rim where
    the can scrapes the floor. It is measured, not ray-traced, because ray tests (AO,
    Bevel) see the far side of the thin handles and call a whole handle an edge.
    Noise and the metal's grime break it into chips, each with a faint dark rim; a
    few small chips are scattered on the flat panels too;
  * color: PAINT, shaded a little by the metal's color map; bare metal in the chips;
  * roughness: PAINT_ROUGH, raised a little where the metal's roughness map has grime;
    the metal's own roughness in the chips;
  * metallic: none on the paint, full in the chips;
  * normal: the metal's height map as soft bump under the paint, sharper in the chips,
    and the paint's thickness as a step at each chip's edge; baked to a tangent-space
    map (OpenGL, as glTF and Godot read);
  * occlusion: ambient occlusion baked from the can itself.

glTF's frame: +Y up, the floor at Y = 0, the can centered on X and Z, its long side
along X and the spout toward +X. Color and normal at COLOR_SIZE, ORM at MAP_SIZE.
"""
import math
import os
import sys

import bmesh
import bpy
import mathutils.kdtree
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

SHARP_DEG = 30.0
UV_ANGLE = 66.0
TILE_M = 0.6           # meters one CS1 tile covers on the can
PAINT = (0.42, 0.012, 0.008)   # linear RGB, a deep glossy red
PAINT_ROUGH = 0.16
GRIME_ROUGH = 0.18     # how much the metal's grime raises the paint's roughness
COLOR_VARY = 0.35      # how much the metal's color map shades the paint
BUMP = 0.35
FEATURE_DEG = 8.0      # an edge folding outward by more than this can wear
EDGE_REACH = 0.006     # meters from an edge the wear fades out over
RIM_REACH = 0.012      # meters up from the floor the bottom rim wears
WEAR = 0.55            # chip threshold: lower chips more
EDGE_PULL = 0.55       # how much an edge raises the chip score
NOISE_PULL = 2.0       # how much the noise does: past EDGE_PULL, edges chip in patches
SCATTER_CUT = 0.75     # noise level over which the flat panels chip: higher chips less
RIM = 0.45             # how dark the paint goes at a chip's rim
CHIP_STEP = 0.0004     # paint thickness, meters, at a chip's edge
HIDDEN_RAYS = 256
HIDDEN_MIN_AREA = 0.01  # m^2: hidden patches smaller than this stay
DECIMATE = 0.12        # share of the cleaned mesh's triangles kept
COLOR_SIZE = 1024
MAP_SIZE = 512
MARGIN = 0.003


def cs1(tex, name):
    return os.path.join(tex, 'T_CS1_BaseMetal_01_4096_%s.png' % name)


def weld(obj):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-7)
    for e in bm.edges:
        e.seam = False
    bm.to_mesh(me)
    bm.free()


def place(obj):
    """Bake the parent's transform in, then stand the can on Z = 0, centered."""
    obj.data.transform(obj.matrix_world)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    lo, hi = co.min(0), co.max(0)
    shift = Vector(((lo[0] + hi[0]) / -2, (lo[1] + hi[1]) / -2, -lo[2]))
    obj.data.transform(Matrix.Translation(shift))
    return hi - lo


def remove_hidden(obj):
    """Delete the big connected patches of faces no ray from outside reaches."""
    me = obj.data
    bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [p.vertices for p in me.polygons])
    rng = np.random.default_rng(1)
    dirs = rng.normal(size=(HIDDEN_RAYS, 3))
    dirs = [Vector(d) for d in dirs / np.linalg.norm(dirs, axis=1)[:, None]]
    hidden = set()
    for p in me.polygons:
        start = p.center + p.normal * 1e-4
        if not any(d.dot(p.normal) > 0 and bvh.ray_cast(start, d, 2.0)[0] is None
                   for d in dirs):
            hidden.add(p.index)

    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    doomed, seen = [], set()
    for i in hidden:
        if i in seen:
            continue
        patch, stack = [], [bm.faces[i]]
        seen.add(i)
        while stack:
            f = stack.pop()
            patch.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index in hidden and g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        if sum(f.calc_area() for f in patch) >= HIDDEN_MIN_AREA:
            doomed += patch
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(me)
    bm.free()
    return len(hidden), len(doomed)


def decimate(obj):
    """Collapse the mesh to DECIMATE of its triangles, then shade it smooth with
    edges over SHARP_DEG sharp and normals weighted by face area."""
    mod = obj.modifiers.new('decimate', 'DECIMATE')
    mod.ratio = DECIMATE
    mod.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    obj.modifiers.clear()
    old, obj.data = obj.data, me
    bpy.data.meshes.remove(old)
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(SHARP_DEG))
    # plain smooth normals bend across the long collapsed triangles and smear the flat
    # panels; weighting by face area keeps big flat faces flat and curves the fillets
    mod = obj.modifiers.new('weighted', 'WEIGHTED_NORMAL')
    mod.mode = 'FACE_AREA'
    mod.weight = 100
    mod.keep_sharp = True
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    obj.modifiers.clear()
    old, obj.data = obj.data, me
    bpy.data.meshes.remove(old)


def unwrap(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name='UVMap')
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(UV_ANGLE), island_margin=MARGIN,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.pack_islands(rotate=True, rotate_method='ANY', shape_method='CONCAVE',
                            margin_method='FRACTION', margin=MARGIN)
    bpy.ops.object.mode_set(mode='OBJECT')
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get('uv', uv)
    t = uv.reshape(-1, 3, 2)
    e1, e2 = t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]
    used = (np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]) / 2).sum()
    area = sum(p.area for p in me.polygons)
    return used, math.sqrt(used / area)


def image(name, size, non_color):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=non_color)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    return img


class Graph:
    """Shorthand for building a material's node tree."""

    def __init__(self, mat):
        self.nodes, self.links = mat.node_tree.nodes, mat.node_tree.links

    def node(self, kind, inputs=(), **props):
        n = self.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        for k, v in inputs:
            if isinstance(v, bpy.types.NodeSocket):
                self.links.new(v, n.inputs[k])
            else:
                n.inputs[k].default_value = v
        return n

    def math(self, op, a, b=0.0, clamp=False):
        return self.node('ShaderNodeMath', ((0, a), (1, b)), operation=op,
                         use_clamp=clamp).outputs[0]

    def ramp(self, value, lo, hi, to_lo=0.0, to_hi=1.0, smooth=False):
        n = self.node('ShaderNodeMapRange', (('Value', value), ('From Min', lo),
                                             ('From Max', hi), ('To Min', to_lo),
                                             ('To Max', to_hi)))
        n.interpolation_type = 'SMOOTHSTEP' if smooth else 'LINEAR'
        return n.outputs['Result']

    def mix(self, fac, a, b, data_type='FLOAT'):
        n = self.nodes.new('ShaderNodeMix')
        n.data_type = data_type
        sockets = {'FLOAT': (0, 2, 3, 0), 'RGBA': (0, 6, 7, 2)}[data_type]
        for idx, v in zip(sockets[:3], (fac, a, b)):
            if isinstance(v, bpy.types.NodeSocket):
                self.links.new(v, n.inputs[idx])
            else:
                n.inputs[idx].default_value = v
        return n.outputs[sockets[3]]

    def box(self, coord, path, non_color):
        t = self.node('ShaderNodeTexImage', (('Vector', coord),), projection='BOX',
                      projection_blend=0.3)
        t.image = bpy.data.images.load(path, check_existing=True)
        if non_color:
            t.image.colorspace_settings.name = 'Non-Color'
        return t.outputs['Color']


def edge_mask(obj, size):
    """The wear mask, 0 to 1, drawn texel by texel over the unwrap: near convex edges
    (more for sharper ones) and near the floor."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    lo_deg, hi_deg = math.radians(FEATURE_DEG), math.radians(FEATURE_DEG * 1.5)
    step = EDGE_REACH / 4
    pts, weights = [], []
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        ang = e.calc_face_angle_signed()
        if ang <= lo_deg:
            continue
        w = min(1.0, (ang - lo_deg) / (hi_deg - lo_deg))
        a, b = e.verts[0].co, e.verts[1].co
        n = max(1, int((b - a).length / step))
        for k in range(n + 1):
            pts.append(a.lerp(b, k / n))
            weights.append(w)
    bm.free()
    tree = mathutils.kdtree.KDTree(len(pts))
    for i, co in enumerate(pts):
        tree.insert(co, i)
    tree.balance()

    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2) * size - 0.5          # texel centers at integers
    vi = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get('vertex_index', vi)
    mask = np.zeros((size, size), dtype=np.float32)
    hit = np.zeros((size, size), dtype=bool)
    for p in me.polygons:
        loops = range(p.loop_start, p.loop_start + p.loop_total)
        t, P = uv[list(loops)], co[vi[list(loops)]]
        x0, y0 = np.maximum(np.floor(t.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(t.max(0)).astype(int), size - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        g = np.stack((gx.ravel(), gy.ravel()), 1).astype(float)
        m = np.array(((t[1] - t[0]), (t[2] - t[0]))).T
        if abs(np.linalg.det(m)) < 1e-12:
            continue
        bc = np.linalg.solve(m, (g - t[0]).T).T
        w = np.column_stack((1 - bc.sum(1), bc))
        inside = (w >= -1e-4).all(1)
        for (x, y), ww in zip(g[inside].astype(int), w[inside]):
            pos = Vector(ww @ P)
            _, i, d = tree.find(pos)
            edge = weights[i] * max(0.0, 1 - d / EDGE_REACH)
            rim = max(0.0, 1 - pos.z / RIM_REACH)
            mask[y, x] = max(edge, rim * rim)
            hit[y, x] = True
    for _ in range(4):                          # bleed past the island edges
        grown = mask.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            shifted = np.roll(np.roll(mask, dy, 0), dx, 1)
            sh_hit = np.roll(np.roll(hit, dy, 0), dx, 1)
            take = ~hit & sh_hit
            grown[take] = np.maximum(grown[take], shifted[take])
        hit = hit | np.roll(hit, 1, 0) | np.roll(hit, -1, 0) | np.roll(hit, 1, 1) | np.roll(hit, -1, 1)
        mask = grown
    img = image('edges', size, True)
    px = np.ones((size * size, 4), dtype=np.float32)
    px[:, :3] = mask.reshape(-1, 1)
    img.pixels.foreach_set(px.ravel())
    return img


def paint_material(tex, edges):
    """The material the maps are baked from: chipped paint over the CS1 metal."""
    mat = bpy.data.materials.new('JerryCanPaint')
    g = Graph(mat)
    bsdf = g.nodes['Principled BSDF']
    obj_co = g.node('ShaderNodeTexCoord').outputs['Object']
    coord = g.node('ShaderNodeMapping', (('Vector', obj_co), ('Scale', (1 / TILE_M,) * 3))
                   ).outputs['Vector']

    base = g.box(coord, cs1(tex, 'B'), False)
    grime = g.box(coord, cs1(tex, 'R'), True)
    grime = g.node('ShaderNodeSeparateColor', (('Color', grime),)).outputs['Red']
    height = g.box(coord, cs1(tex, 'H'), True)
    height = g.node('ShaderNodeSeparateColor', (('Color', height),)).outputs['Red']

    # chips: the edge mask, broken up by two noises and the grime
    wear = g.node('ShaderNodeTexImage', (), interpolation='Linear')
    wear.image = edges
    wear = g.node('ShaderNodeSeparateColor', (('Color', wear.outputs['Color']),)
                  ).outputs['Red']
    big = g.node('ShaderNodeTexNoise', (('Vector', obj_co), ('Scale', 18.0),
                                        ('Detail', 8.0), ('Roughness', 0.65))).outputs['Fac']
    fine = g.node('ShaderNodeTexNoise', (('Vector', obj_co), ('Scale', 90.0),
                                         ('Detail', 6.0), ('Roughness', 0.6))).outputs['Fac']
    rough_edge = g.math('ADD', g.math('MULTIPLY', big, 0.7), g.math('MULTIPLY', fine, 0.3))
    score = g.math('ADD', g.math('MULTIPLY', wear, EDGE_PULL),
                   g.math('MULTIPLY', g.math('SUBTRACT', rough_edge, 0.5), NOISE_PULL))
    score = g.math('ADD', score, g.math('MULTIPLY', g.math('SUBTRACT', grime, 0.37), 0.5))
    edge_chips = g.ramp(score, WEAR, WEAR + 0.06)
    spots = g.node('ShaderNodeTexNoise', (('Vector', obj_co), ('Scale', 45.0),
                                          ('Detail', 4.0), ('Roughness', 0.5))).outputs['Fac']
    spot_score = g.math('ADD', spots, g.math('MULTIPLY', g.math('SUBTRACT', fine, 0.5), 0.15))
    spot_chips = g.ramp(spot_score, SCATTER_CUT, SCATTER_CUT + 0.015)
    chip = g.math('MAXIMUM', edge_chips, spot_chips, clamp=True)
    near = g.math('MAXIMUM', g.ramp(score, WEAR - 0.1, WEAR, smooth=True),
                  g.ramp(spot_score, SCATTER_CUT - 0.025, SCATTER_CUT, smooth=True))
    rim = g.math('MULTIPLY', near, g.math('SUBTRACT', 1.0, chip), clamp=True)

    # paint
    shade = g.ramp(g.node('ShaderNodeRGBToBW', (('Color', base),)).outputs['Val'],
                   0.0, 0.28, 1 - COLOR_VARY, 1.0)
    shade.node.clamp = False
    paint = g.node('ShaderNodeMix', (('Factor', 1.0), (6, PAINT + (1.0,)), (7, shade)),
                   data_type='RGBA', blend_type='MULTIPLY').outputs[2]
    paint = g.mix(g.math('MULTIPLY', rim, RIM), paint, (0.05, 0.03, 0.025, 1.0), 'RGBA')
    paint_rough = g.ramp(grime, 0.32, 1.0, PAINT_ROUGH, PAINT_ROUGH + GRIME_ROUGH)
    paint_rough = g.math('ADD', paint_rough, g.math('MULTIPLY', rim, 0.2))

    # bare metal in the chips, a little darker than the clean sheet
    metal = g.node('ShaderNodeMix', (('Factor', 1.0), (6, base), (7, (0.75, 0.75, 0.75, 1))),
                   data_type='RGBA', blend_type='MULTIPLY').outputs[2]

    color = g.mix(chip, paint, metal, 'RGBA')
    roughness = g.mix(chip, paint_rough, grime)
    metallic = chip
    surface = g.math('ADD', g.math('MULTIPLY', height, BUMP),
                     g.math('MULTIPLY', g.math('SUBTRACT', 1.0, chip), CHIP_STEP / 0.001))
    surface = g.math('ADD', surface, g.math('MULTIPLY', g.math('MULTIPLY', height, chip),
                                            1 - BUMP))
    bump = g.node('ShaderNodeBump', (('Strength', 1.0), ('Distance', 0.001),
                                     ('Height', surface)))

    g.links.new(color, bsdf.inputs['Base Color'])
    g.links.new(roughness, bsdf.inputs['Roughness'])
    g.links.new(metallic, bsdf.inputs['Metallic'])
    g.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    return mat, bsdf, color, roughness, metallic


def bake(mat, kind, img, samples=1):
    nodes = mat.node_tree.nodes
    target = nodes.get('bake_target') or nodes.new('ShaderNodeTexImage')
    target.name = 'bake_target'
    target.image = img
    for n in nodes:
        n.select = False
    target.select = True
    nodes.active = target
    sc = bpy.context.scene
    sc.cycles.samples = samples
    sc.render.bake.margin = 4
    sc.render.bake.use_clear = True
    bpy.ops.object.bake(type=kind, normal_space='TANGENT', use_selected_to_active=False)


def bake_emit(mat, bsdf, socket, img, samples=1):
    """Bake one socket by routing it through the material output as emission."""
    links = mat.node_tree.links
    out = mat.node_tree.nodes['Material Output']
    em = mat.node_tree.nodes.new('ShaderNodeEmission')
    links.new(socket, em.inputs['Color'])
    links.new(em.outputs['Emission'], out.inputs['Surface'])
    bake(mat, 'EMIT', img, samples)
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    mat.node_tree.nodes.remove(em)


def pixels(img):
    px = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    return px.reshape(-1, 4)


def occlusion_group():
    """The node group the glTF exporter reads the occlusion map from."""
    group = bpy.data.node_groups.get('glTF Material Output')
    if group is None:
        group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
        group.interface.new_socket('Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
    return group


def game_material(color, normal, orm):
    mat = bpy.data.materials.new('JerryCan')
    mat.use_backface_culling = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes['Principled BSDF']
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = color
    links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    ntex = nodes.new('ShaderNodeTexImage')
    ntex.image = normal
    nmap = nodes.new('ShaderNodeNormalMap')
    links.new(ntex.outputs['Color'], nmap.inputs['Color'])
    links.new(nmap.outputs['Normal'], bsdf.inputs['Normal'])
    otex = nodes.new('ShaderNodeTexImage')
    otex.image = orm
    sep = nodes.new('ShaderNodeSeparateColor')
    links.new(otex.outputs['Color'], sep.inputs['Color'])
    links.new(sep.outputs['Green'], bsdf.inputs['Roughness'])
    links.new(sep.outputs['Blue'], bsdf.inputs['Metallic'])
    occ = nodes.new('ShaderNodeGroup')
    occ.node_tree = occlusion_group()
    links.new(sep.outputs['Red'], occ.inputs['Occlusion'])
    return mat


def to_png(img, name, size, non_color):
    """A packed 8-bit PNG copy of a baked image, at size."""
    out = bpy.data.images.new(name, img.size[0], img.size[1], alpha=False)
    if non_color:
        out.colorspace_settings.name = 'Non-Color'
    out.pixels.foreach_set(pixels(img).ravel())
    if size != img.size[0]:
        out.scale(size, size)
    out.file_format = 'PNG'
    out.pack()
    return out


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    src, tex, out = argv[0], argv[1], argv[2]
    dump = argv[3] if len(argv) > 3 else None
    bpy.ops.wm.open_mainfile(filepath=src)
    obj = next(o for o in bpy.data.objects if o.type == 'MESH')
    for o in list(bpy.data.objects):
        if o is not obj:
            bpy.data.objects.remove(o)
    weld(obj)
    size = place(obj)
    hidden, removed = remove_hidden(obj)
    decimate(obj)
    used, density = unwrap(obj)

    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    edges = edge_mask(obj, COLOR_SIZE)

    mat, bsdf, color, roughness, metallic = paint_material(tex, edges)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    col_img = image('color', COLOR_SIZE, False)
    bake_emit(mat, bsdf, color, col_img)
    rough_img = image('rough', COLOR_SIZE, True)
    bake_emit(mat, bsdf, roughness, rough_img)
    metal_img = image('metal', COLOR_SIZE, True)
    bake_emit(mat, bsdf, metallic, metal_img)
    nrm_img = image('normal', COLOR_SIZE, True)
    bake(mat, 'NORMAL', nrm_img)
    ao_img = image('ao', COLOR_SIZE, True)
    bake(mat, 'AO', ao_img, samples=128)

    orm = pixels(ao_img).copy()
    orm[:, 1] = pixels(rough_img)[:, 0]
    orm[:, 2] = pixels(metal_img)[:, 0]
    orm_img = image('orm', COLOR_SIZE, True)
    orm_img.pixels.foreach_set(orm.ravel())

    color_png = to_png(col_img, 'JerryCan_BC', COLOR_SIZE, False)
    normal_png = to_png(nrm_img, 'JerryCan_N', COLOR_SIZE, True)
    orm_png = to_png(orm_img, 'JerryCan_ORM', MAP_SIZE, True)
    if dump:
        for img in (color_png, normal_png, orm_png, to_png(edges, 'JerryCan_edges', COLOR_SIZE, True)):
            img.filepath_raw = os.path.join(dump, img.name + '.png')
            img.save()

    game = game_material(color_png, normal_png, orm_png)
    obj.data.materials.clear()
    obj.data.materials.append(game)
    obj.name = obj.data.name = 'jerry_can'

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
                              export_yup=True, export_apply=True)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print('wrote %s: %d triangles, %d vertices, %.3f x %.3f x %.3f m'
          % (out, tris, len(obj.data.vertices), size[0], size[1], size[2]))
    print('hidden faces %d, removed %d; UV space used %.0f%%, %.2f texels/mm'
          % (hidden, removed, used * 100, density * COLOR_SIZE / 1000))


main()
