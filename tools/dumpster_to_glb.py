"""Builds the dumpster GLB from Leartes' "PAD Dumpster".

    blender -b --factory-startup --python tools/dumpster_to_glb.py -- \
        reference/buildings/PAD_Dumpster/Export assets/locations/city/dumpster.glb [RATIO]

The source is the pack's Unreal download, exported to reference/buildings/PAD_Dumpster/Export
by the user's unreal-assets-to-glb fork (https://github.com/Hellmark/unreal-assets-to-glb):
Meshes/SM_PAD_Dumpster_Base_c1_LOD0.glb (the bin) and SM_PAD_Dumpster_Lid01/Lid02_c1_LOD0.glb
(the two lids, each with its origin on its hinge), unwelded and in centimeters, and
Textures/T_PAD_Dumpster_4096_{B,N,ORM}.png (Unreal's DirectX normal map). The pack's
blueprint, which places the lids, is not exported; LID_OFFSETS is where each lid's hinge sits on
the bin, found by matching the lids' vertices to the pack's whole dumpster
(SM_PAD_Dumpster_c1_LOD0.glb), which they fit exactly. The pack has only this one detail level,
so each piece is welded and cut down here by RATIO (default 0.15) with Blender's collapse
decimation, which keeps the UV seams: 74k triangles in all become about 11k.

glTF's frame: +Y up, the floor at Y = 0, the bin centered on X and Z, real size in meters
(2.32 m long, 1.27 m deep, 1.6 m tall). The front, the low side the lids slope down to, faces
+Z; the tall flat back with the hinges faces -Z, and the fork pockets are at the ends (+-X).
Nodes: `dumpster` (the bin) and `lid_left` and `lid_right` (at -X and +X, as seen from the
front), each lid's origin on its hinge line, which runs along X; turning a lid by a negative
angle about X opens it. Color map at 1024, normal (flipped to OpenGL) and ORM at 512
(R = AO, G = roughness, B = metallic).
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix

COLOR_SIZE = 1024
MAP_SIZE = 512
WELD_DIST = 0.01  # centimeters, as imported
SMOOTH_ANGLE = math.radians(35.0)
# Each lid's hinge on the bin, in the source glTF's centimeters (x toward the front, y up).
LID_OFFSETS = {
    'Lid01': (-62.341, 155.426, -50.938),
    'Lid02': (-62.341, 155.426, 50.938),
}


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
    mat = bpy.data.materials.new('Dumpster')
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


def import_piece(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    obj = next(o for o in new if o.type == 'MESH')
    for o in new:
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    return obj


def cut_down(obj, ratio):
    """Weld (the faces are all separate), decimate, and shade by angle: welding drops the
    split normals."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=WELD_DIST)
    bm.to_mesh(me)
    bm.free()
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if me.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    mod = obj.modifiers.new('decimate', 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth_by_angle(angle=SMOOTH_ANGLE)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    src, out = argv[0], argv[1]
    ratio = float(argv[2]) if len(argv) > 2 else 0.15
    bpy.ops.wm.read_factory_settings(use_empty=True)
    meshes = os.path.join(src, 'Meshes')
    body = import_piece(os.path.join(meshes, 'SM_PAD_Dumpster_Base_c1_LOD0.glb'))
    lids = {}
    for key in ('Lid01', 'Lid02'):
        lid = import_piece(os.path.join(meshes, 'SM_PAD_Dumpster_%s_c1_LOD0.glb' % key))
        x, y, z = LID_OFFSETS[key]
        lid.location = (x, -z, y)  # glTF to Blender
        lids[key] = lid
    pieces = [body] + list(lids.values())
    before = sum(len(o.data.polygons) for o in pieces)
    for obj in pieces:
        cut_down(obj, ratio)

    # Centimeters to meters, and the front (+X as imported) to glTF's +Z (Blender's -Y). Then
    # the bin's footprint is centered with the floor at 0. Each lid keeps its origin on its
    # hinge, with no turn of its own.
    turn = Matrix.Rotation(-math.pi / 2.0, 4, 'Z') @ Matrix.Scale(0.01, 4)
    body.data.transform(turn)
    pts = np.array([v.co for v in body.data.vertices])
    lo, hi = pts.min(0), pts.max(0)
    shift = Matrix.Translation((-(lo[0] + hi[0]) / 2.0, -(lo[1] + hi[1]) / 2.0, -lo[2]))
    body.data.transform(shift)
    body.name = body.data.name = 'dumpster'
    for lid in lids.values():
        hinge = shift @ turn @ lid.location
        lid.location = (0.0, 0.0, 0.0)
        lid.data.transform(turn)
        lid.location = hinge
        side = 'lid_left' if hinge.x < 0.0 else 'lid_right'
        lid.name = lid.data.name = side

    tex = os.path.join(src, 'Textures')
    mat = make_material(
        load_image(os.path.join(tex, 'T_PAD_Dumpster_4096_B.png'), COLOR_SIZE),
        load_image(os.path.join(tex, 'T_PAD_Dumpster_4096_N.png'), MAP_SIZE, non_color=True, flip_green=True),
        load_image(os.path.join(tex, 'T_PAD_Dumpster_4096_ORM.png'), MAP_SIZE, non_color=True))
    for obj in pieces:
        obj.data.materials.clear()
        obj.data.materials.append(mat)

    bpy.ops.object.select_all(action='DESELECT')
    for obj in pieces:
        obj.select_set(True)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
                              export_yup=True, export_apply=True)
    size = hi - lo
    tris = sum(len(p.vertices) - 2 for o in pieces for p in o.data.polygons)
    print('wrote %s: %d triangles (from %d faces), bin %.2f long, %.2f deep, %.2f tall'
          % (out, tris, before, size[0], size[1], size[2]))
    for lid in lids.values():
        h = lid.location
        print('  %s hinge (glTF) %.3f, %.3f, %.3f' % (lid.name, h.x, h.z, -h.y))


main()
