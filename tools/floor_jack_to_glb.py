"""Builds the garage's floor jack GLB from the "Tire Repair Shop" pack's hydraulic jack.

    blender -b --factory-startup --python tools/floor_jack_to_glb.py -- \
        reference/buildings/tireshop/Export assets/locations/garage/jack.glb

The source is the pack's Export/Meshes/SM_HydraulicJack.glb (one unwelded mesh in
centimeters, color map only) and Export/Textures/T_Jack_{BC,N,ORM}.png (4096, Unreal's
DirectX normal map). The model is about 1.6 times a real 3-ton floor jack, so it is
scaled by SCALE to real size: a 69 cm body, saddle 29 cm off the floor, 1.1 m with the
handle.

The jack is split into the parts that move when it lifts, each with its origin where it
turns, for scripts/floor_jack.gd to pose:

  * `jack_body`: frame, wheels, casters, ram cylinder, pump and handle; it does not move;
  * `jack_arm`: the lift arm and the pin at the bottom of its lever, origin on the arm's
    pivot pin; it turns about Z;
  * `jack_saddle`: saddle, its post and the post's pins, origin on the pin at the arm's
    tip; it rides the tip and stays level;
  * `jack_links`: the two side links, origin on their front eye (the post's lower pin);
    the front follows the post and the link points at the empty `link_aim` on the frame;
  * `jack_rod`: the ram's rod, origin on its front eye (the arm's lever pin); the eye
    follows the lever and the rod points back at `rod_aim`, the cylinder's mouth.

Empties `arm_tip` (on the arm, the saddle's pin) and `arm_lever` (on the arm, the rod's
pin) tell the script where those points go as the arm turns.

glTF's frame: +Y up, the floor at Y = 0, the saddle along +X and the handle along -X,
the jack centered on Z. Color map at 1024, normal (flipped to OpenGL) and ORM at 512
(R = AO, G = roughness, B = metallic).
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

SCALE = 0.006  # the model's centimeters to meters, and 0.6 to bring it to real size
COLOR_SIZE = 1024
MAP_SIZE = 512


def islands(me):
    """Island index for each face: faces touching, by shared vertices or vertices at the
    same spot (the mesh is unwelded)."""
    n = len(me.vertices)
    parent = np.arange(n)

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    seen = {}
    for v in me.vertices:
        k = tuple(round(c * 1000) for c in v.co)  # 0.01 mm once scaled
        if k in seen:
            union(v.index, seen[k])
        else:
            seen[k] = v.index
    for p in me.polygons:
        vs = p.vertices
        for i in range(1, len(vs)):
            union(vs[0], vs[i])
    return [find(p.vertices[0]) for p in me.polygons]


def box_of(me, faces):
    pts = np.array([me.vertices[i].co for f in faces for i in me.polygons[f].vertices])
    return pts.min(0), pts.max(0)


def center(box):
    return Vector((box[0] + box[1]) / 2)


def classify(lo, hi):
    """Which part an island (bounds in source centimeters) belongs to."""
    def near(a, b, tol=1.0):
        return all(abs(x - y) <= tol for x, y in zip(a, b))
    if near(lo, (-10.16, -7.68, 6.95)) and near(hi, (38.68, 7.68, 33.85)):
        return 'arm'
    if near(lo, (-4.99, -5.48, 10.54)) and near(hi, (-1.15, 5.48, 14.38)):
        return 'lever_pin'
    if lo[0] > 24 and lo[2] > 21:
        return 'saddle'
    if near((lo[0], hi[0], lo[2], hi[2]), (-2.86, 31.25, 21.18, 26.52)):
        return 'links'
    if near(lo, (-42.71, -3.05, 9.32)) and near(hi, (0.06, 3.05, 15.59)):
        return 'rod'
    if near(lo, (-8.34, -11.98, 25.31)) and near(hi, (-4.69, 12.01, 28.95)):
        return 'pivot_pin'
    return 'body'


PART_CODES = {'body': 0, 'arm': 1, 'lever_pin': 1, 'pivot_pin': 0, 'saddle': 2, 'links': 3, 'rod': 4}


def separate(obj, code, name):
    """Split the faces tagged `code` off `obj` into a new object called `name`. (Face
    indices change with each split, so the faces carry their part in an attribute.)"""
    me = obj.data
    tags = [0] * len(me.polygons)
    me.attributes['part'].data.foreach_get('value', tags)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_mode(type='FACE')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    me.polygons.foreach_set('select', [t == code for t in tags])
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    new = [o for o in bpy.context.selected_objects if o is not obj][0]
    new.name = name
    new.data.name = name
    new.data.attributes.remove(new.data.attributes['part'])
    return new


def set_origin(obj, point):
    obj.data.transform(Matrix.Translation(-point))
    obj.matrix_world = Matrix.Translation(point)


def empty(name, point, parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.matrix_world = Matrix.Translation(point)
    if parent is not None:
        e.parent = parent
        e.matrix_parent_inverse = parent.matrix_world.inverted()
    return e


def load_image(path, size, non_color=False, flip_green=False):
    img = bpy.data.images.load(path)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    img.scale(size, size)
    if flip_green:
        px = np.empty(size * size * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px[1::4] = 1.0 - px[1::4]
        img.pixels.foreach_set(px)
    img.pack()
    return img


def occlusion_group():
    """The node group the glTF exporter reads the occlusion map from."""
    group = bpy.data.node_groups.get('glTF Material Output')
    if group is None:
        group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
        group.interface.new_socket('Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
    return group


def make_material(color, normal, orm):
    mat = bpy.data.materials.new('FloorJack')
    mat.use_nodes = True
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


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    src, out = argv[0], argv[1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(src, 'Meshes', 'SM_HydraulicJack.glb'))
    obj = next(o for o in bpy.data.objects if o.type == 'MESH')
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    me = obj.data

    owner = islands(me)
    groups = {}
    for f, root in enumerate(owner):
        groups.setdefault(root, []).append(f)
    parts = {}
    pins = {}
    for faces in groups.values():
        lo, hi = box_of(me, faces)
        kind = classify(lo, hi)
        parts.setdefault(kind, []).extend(faces)
        if kind in ('pivot_pin', 'lever_pin'):
            pins[kind] = center((lo, hi))
        elif kind == 'saddle' and lo[1] < 0 < hi[1] and hi[0] - lo[0] < 5:
            # The post's pins: the one through the arm's tip goes right through the
            # post; the link pins are the pair to each side, lower.
            pins.setdefault('saddle_pins', []).append(center((lo, hi)))
        elif kind == 'saddle' and hi[0] - lo[0] < 5:
            pins.setdefault('link_pins', []).append(center((lo, hi)))
        elif kind == 'links':
            pins.setdefault('links_box', []).append((lo, hi))
    counts = {k: len(v) for k, v in parts.items()}
    print('parts (faces):', counts)
    want = ('arm', 'lever_pin', 'saddle', 'links', 'rod', 'pivot_pin')
    if any(k not in parts for k in want) or len(pins.get('saddle_pins', [])) != 1 \
            or len(pins.get('link_pins', [])) != 2 or len(pins['links_box']) != 2:
        raise SystemExit('split went wrong: %s, pins %s' % (counts, {k: (len(v) if isinstance(v, list) else 1) for k, v in pins.items()}))

    pivot = pins['pivot_pin']
    tip = pins['saddle_pins'][0]
    lever = pins['lever_pin']
    link_front = (pins['link_pins'][0] + pins['link_pins'][1]) / 2
    # The links' back eye: as far in from their back end as their front eye is from the
    # front end, at the eye's height.
    lo = Vector(min(b[0][i] for b in pins['links_box']) for i in range(3))
    hi = Vector(max(b[1][i] for b in pins['links_box']) for i in range(3))
    eye = hi.x - link_front.x
    link_back = Vector((lo.x + eye, 0.0, link_front.z))
    # The rod leaves the ram cylinder at its front end, on the rod's own line.
    rod_mouth = Vector((-16.98, 0.0, lever.z))

    tags = [0] * len(me.polygons)
    for kind, faces in parts.items():
        for f in faces:
            tags[f] = PART_CODES[kind]
    me.attributes.new('part', 'INT', 'FACE').data.foreach_set('value', tags)
    arm = separate(obj, 1, 'jack_arm')
    saddle = separate(obj, 2, 'jack_saddle')
    links = separate(obj, 3, 'jack_links')
    rod = separate(obj, 4, 'jack_rod')
    me.attributes.remove(me.attributes['part'])
    obj.name = obj.data.name = 'jack_body'
    body = obj

    scale = Matrix.Scale(SCALE, 4)
    for o in (body, arm, saddle, links, rod):
        o.data.transform(scale)
    pivot, tip, lever, link_front, link_back, rod_mouth = (
        p * SCALE for p in (pivot, tip, lever, link_front, link_back, rod_mouth))
    pivot.y = tip.y = lever.y = link_front.y = link_back.y = rod_mouth.y = 0.0
    set_origin(arm, pivot)
    set_origin(saddle, tip)
    set_origin(links, link_front)
    set_origin(rod, lever)
    marks = [empty('arm_tip', tip, arm), empty('arm_lever', lever, arm),
             empty('link_aim', link_back), empty('rod_aim', rod_mouth)]

    tex = os.path.join(src, 'Textures')
    mat = make_material(
        load_image(os.path.join(tex, 'T_Jack_BC.png'), COLOR_SIZE),
        load_image(os.path.join(tex, 'T_Jack_N.png'), MAP_SIZE, non_color=True, flip_green=True),
        load_image(os.path.join(tex, 'T_Jack_ORM.png'), MAP_SIZE, non_color=True))
    objs = (body, arm, saddle, links, rod)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs + tuple(marks):
        o.select_set(True)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
                              export_yup=True, export_apply=True)
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    g = lambda p: tuple(round(c, 4) for c in (p.x, p.z, -p.y))
    print('wrote %s: %d triangles' % (out, tris))
    print('pivot %s tip %s lever %s link front %s link aim %s rod aim %s'
          % (g(pivot), g(tip), g(lever), g(link_front), g(link_back), g(rod_mouth)))


main()
