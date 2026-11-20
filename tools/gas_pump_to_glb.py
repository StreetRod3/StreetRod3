"""Builds the gas station's pump GLB from Leartes' "PAD Gas Pumps".

    python3 -I tools/gas_pump_plates.py reference/buildings/PAD_GasPumps MAPS_DIR
    blender -b --factory-startup --python tools/gas_pump_to_glb.py -- \
        reference/buildings/PAD_GasPumps MAPS_DIR assets/locations/gas-station/pump.glb [VARIANT]

Source: https://cosmos.leartesstudios.com/assets/pad-gas-pumps (notes in the reference
folder's notes.md).

The pack's FBX/OBJ downloads are missing the pump body's color and normal maps: the
files named T_PAD_GasPump_4096_* are copies of the glass set. The Unreal download has
the real ones; they were decoded from its .uasset files into TexturesFromUnreal/, and
tools/gas_pump_plates.py repaints the side plate from them into MAPS_DIR, one set per
pump. The GLB carries VARIANT's set (default regular); the game swaps in the super set
for the other pump. The body's ORM is the one the Unreal material uses, T_PAD_GasPump_Glass_4096_ORM (it
covers both atlases).

The GLB holds:

  * `pump`: the body from LOD2 (the pack's lightest, ~33k triangles), color map at
    2048, normal and ORM maps at 1024 (R = AO, G = roughness, B = metallic);
  * `pump_glass`: the dial glass from its own LOD2, placed on the pack's socket, with
    a see-through material and 512 maps;
  * `nozzle`: the nozzle, hung spout up in its holder on the pump's left side (-X).
    Its origin is the spout's tip and its -Z points out of the spout, so the game can
    lift it off, aim it with look_at and seat the tip in a filler neck. Its child
    `hose_end` marks where the hose goes into the handle;
  * `hose`: the hose as it hangs with the nozzle home, from the nozzle down in a loop
    and up into its fitting at the back of the pump (which stays on `pump`, as does the
    nozzle's holder). The game hides it while the nozzle is off and draws its own from
    `hose_outlet`, an empty at that fitting, to `nozzle/hose_end`.

The loose parts of the pack's single mesh are sorted by where they sit: the hose is
the side part that reaches the ground; the nozzle is the side parts out past the
holder, above the hose's fitting.

glTF's frame: +Y up, base at Y = 0, the front (the dial and the GASOLINE plate) along
+Z, real size in meters (1.8 m tall). Unreal's collision hulls (UCX_) are left out.
"""
import os
import sys

import bpy

BODY_COLOR_SIZE = 2048
BODY_MAP_SIZE = 1024
GLASS_MAP_SIZE = 512


def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def load_image(path, size, non_color=False):
    img = bpy.data.images.load(path)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    if img.size[0] != size:
        img.scale(size, size)
    img.pack()
    return img


def occlusion_group():
    """The node group the glTF exporter reads the occlusion map from."""
    group = bpy.data.node_groups.get('glTF Material Output')
    if group is None:
        group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
        group.interface.new_socket('Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
    return group


def bounds(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return ([min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)])


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def split_body(body):
    """Pull the nozzle and the hose off the body; returns (pump, nozzle, hose)."""
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='LOOSE')
    bpy.ops.object.mode_set(mode='OBJECT')
    parts = [o for o in bpy.context.selected_objects]
    pump, nozzle, hose = [], [], []
    for o in parts:
        lo, hi = bounds(o)
        if lo[0] < -0.34 and lo[2] < 0.05:
            hose.append(o)
        elif lo[0] < -0.40 and lo[2] > 1.1:
            nozzle.append(o)
        else:
            pump.append(o)
    if len(hose) != 1 or len(nozzle) < 3:
        raise SystemExit('split: %d hose parts, %d nozzle parts' % (len(hose), len(nozzle)))
    return join(pump, 'pump'), join(nozzle, 'nozzle'), join(hose, 'hose')


def set_frame(obj, point, forward):
    """Give obj its origin at `point` and its local +Y (glTF's -Z) along `forward`,
    without moving its mesh."""
    from mathutils import Matrix
    frame = Matrix.Translation(point) @ forward.to_track_quat('Y', 'Z').to_matrix().to_4x4()
    obj.data.transform(frame.inverted() @ obj.matrix_world)
    obj.matrix_world = frame


def empty(name, point, parent=None):
    from mathutils import Matrix
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
        e.matrix_parent_inverse = parent.matrix_world.inverted()
    e.matrix_world = Matrix.Translation(point)
    return e


def gltf_point(p):
    return (round(p[0], 4), round(p[2], 4), round(-p[1], 4))


def make_material(name, color, normal, orm, glass=False):
    old = bpy.data.materials.get(name)
    if old is not None:
        old.name = name + '_fbx'
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = not glass
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes['Principled BSDF']
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = color
    links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    if glass:
        links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
        mat.surface_render_method = 'BLENDED'
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
    ref, maps, out = argv[0], argv[1], argv[2]
    variant = argv[3] if len(argv) > 3 else 'regular'
    meshes = os.path.join(ref, 'Meshes')
    tex = os.path.join(ref, 'Textures')

    bpy.ops.wm.read_factory_settings(use_empty=True)
    body_objs = import_fbx(os.path.join(meshes, 'SM_PAD_GasPump_c1_LOD2.fbx'))
    socket = next(o for o in body_objs if o.name.startswith('SOCKET_'))
    socket_matrix = socket.matrix_world.copy()
    glass_objs = import_fbx(os.path.join(meshes, 'SM_PAD_GasPump_Glass_c1_LOD2.fbx'))

    body = next(o for o in body_objs if o.type == 'MESH' and not o.name.startswith('UCX_'))
    glass = next(o for o in glass_objs if o.type == 'MESH' and not o.name.startswith('UCX_'))
    for o in body_objs + glass_objs:
        if o not in (body, glass):
            bpy.data.objects.remove(o, do_unlink=True)
    glass.matrix_world = socket_matrix @ glass.matrix_world
    glass.name = 'pump_glass'
    body, nozzle, hose = split_body(body)

    from mathutils import Vector
    # The hose's ends: where it goes into the nozzle (the nozzle's lowest point) and
    # where it leaves the pump (its end nearest the back fitting, at the top of the loop).
    n_lo, n_hi = bounds(nozzle)
    hose_verts = [hose.matrix_world @ v.co for v in hose.data.vertices]
    nozzle_end = min(hose_verts, key=lambda p: (p - Vector(((n_lo[0] + n_hi[0]) / 2, (n_lo[1] + n_hi[1]) / 2, n_lo[2]))).length)
    back = [p for p in hose_verts if p.y > 0.05]
    outlet_top = max(back, key=lambda p: p.z)
    ring = [p for p in back if p.z > outlet_top.z - 0.004]
    outlet = sum(ring, Vector()) / len(ring)
    ring = [p for p in hose_verts if (p - nozzle_end).length < 0.03 and abs(p.z - nozzle_end.z) < 0.004]
    nozzle_end = sum(ring, Vector()) / len(ring)
    # The spout's tip is the nozzle's point farthest from the hose.
    nozzle_verts = [nozzle.matrix_world @ v.co for v in nozzle.data.vertices]
    far = max(nozzle_verts, key=lambda p: (p - nozzle_end).length)
    tip_ring = [p for p in nozzle_verts if (p - far).length < 0.012]
    tip = sum(tip_ring, Vector()) / len(tip_ring)
    set_frame(nozzle, tip, (tip - nozzle_end).normalized())
    hose_end = empty('hose_end', nozzle_end, nozzle)
    hose_outlet = empty('hose_outlet', outlet)

    orm = load_image(os.path.join(tex, 'T_PAD_GasPump_Glass_4096_ORM.png'), BODY_MAP_SIZE, non_color=True)
    body_mat = make_material(
        'GasPump',
        load_image(os.path.join(maps, 'pump-%s-color.png' % variant), BODY_COLOR_SIZE),
        load_image(os.path.join(maps, 'pump-%s-normal.png' % variant), BODY_MAP_SIZE,
                   non_color=True),
        orm)
    glass_mat = make_material(
        'GasPumpGlass',
        load_image(os.path.join(tex, 'T_PAD_GasPump_Glass_4096_B.png'), GLASS_MAP_SIZE),
        load_image(os.path.join(tex, 'T_PAD_GasPump_Glass_4096_OpenGL_N.png'), GLASS_MAP_SIZE,
                   non_color=True),
        load_image(os.path.join(tex, 'T_PAD_GasPump_Glass_4096_ORM.png'), GLASS_MAP_SIZE,
                   non_color=True),
        glass=True)
    for obj, mat in ((body, body_mat), (nozzle, body_mat), (hose, body_mat), (glass, glass_mat)):
        obj.data.materials.clear()
        obj.data.materials.append(mat)

    objs = (body, glass, nozzle, hose)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs + (hose_end, hose_outlet):
        o.select_set(True)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
                              export_yup=True, export_apply=True)
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    print('wrote %s: %d triangles' % (out, tris))
    print('nozzle tip %s, hose end %s, %.2f m apart; hose outlet %s'
          % (gltf_point(tip), gltf_point(nozzle_end), (tip - nozzle_end).length, gltf_point(outlet)))


main()
