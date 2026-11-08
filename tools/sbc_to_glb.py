"""Splits the small block Chevy model (sbc.3DS) into the engine bay's parts.

    blender -b --factory-startup --python tools/sbc_to_glb.py -- SBC.3DS assets/parts

writes four models into the folder given:

- engine-sbc.glb: the long block: block, heads, valve covers, oil pan, timing cover,
  bellhousing plate and flywheel. Pistons, rods, crank, cam, valvetrain and the other
  parts that cannot be seen with the covers on are left out.
- intake-iron4.glb: the cast-iron single four-barrel intake, with its thermostat housing.
- carb-4bbl.glb: the four-barrel carburetor and its spacer, origin at the middle of its
  base.
- distributor-sbc.glb: the distributor, origin at the middle of its base where it sits on
  the intake. The cap is its own node, `distributor_cap`, so the game can color it.

Everything is in the frame the game's engine models use (scripts/engine_assembly.gd): +X toward the
back of the car with the rear face of the block at 1.5 and the front at -1.5, +Z up with
the crank at -0.36, about four and a half times real size. glTF's Z is kept as up.
The points the game builds around (carb pad, distributor base, cap towers, spark plugs)
are printed at the end for the constants in scripts/engine_assembly.gd.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from read3ds import bounds, load  # noqa: E402

## Model units to engine units: the block, 333 long, becomes 3.0.
SCALE = 3.0 / 333.0
## Crank height in the model, and where it goes in engine units.
CRANK_Z = -74.0
CRANK_AT = -0.36

## The model's materials by look.
PAINT = ('paint', (0.62, 0.17, 0.04), 0.15, 0.45)
CHROME = ('chrome', (0.9, 0.9, 0.92), 1.0, 0.12)
STEEL = ('steel', (0.45, 0.45, 0.46), 0.8, 0.4)
BLACK = ('black', (0.03, 0.03, 0.03), 0.0, 0.6)
CAP = ('cap', (0.55, 0.04, 0.03), 0.0, 0.35)
CARB = ('carb', (0.66, 0.55, 0.26), 0.85, 0.35)

## The model's objects for each part. The rest of the outside is the long block.
INTAKE = {'ChamferBo4', 'ChamferBo5', 'ChamferBo6', 'ChamferBo7', 'ChamferBo8', 'ChamferBo9',
          'ChamferB10', 'ChamferB11', 'Box091', 'Box10', 'Box11', 'Circle03', 'Circle06',
          'Tube010', 'NGon010', 'NGon020'}
## The sheet over the lifter valley stays on the block, dull steel.
VALLEY = 'Line020'
## Two copies of the carb spacer sit on the intake's pad; the carb takes them.
CARB_EXTRA = {'Box09', 'Box090'}
## Valve springs, rocker arms and studs, pushrods, valves, pistons, rods, crank, cam.
HIDDEN_PREFIXES = ('Spring', 'Line1222', 'Line1223')
HIDDEN = {'Line11', 'Line12238', 'Line12239', 'Line12240', 'Line12241', 'Line12242',
          'Line12243', 'Line12244', 'Cylinder05', 'Cylinder42'}
HIDDEN_BOXES = {'Box%02d' % i for i in list(range(1, 9)) + list(range(12, 20))}
## A flat plate down the carb's side that is not part of any carburetor.
STRAY = {'Line011'}
## Small parts inside the block: their vertex counts give them away.
HIDDEN_SIZES = {38, 56, 93, 629}


def to_engine(p):
    x, y, z = p
    return (-y * SCALE, x * SCALE, (z - CRANK_Z) * SCALE + CRANK_AT)


def part_of(ob):
    name = ob['name']
    lo, hi = bounds(ob)
    mats = set(ob['groups'])
    if name in STRAY:
        return None
    if name in INTAKE:
        return 'intake'
    if name in CARB_EXTRA or 'Material #11' in mats and lo[2] > 100.0:
        return 'carb'
    if lo[2] >= 133.0 and abs(lo[0]) < 50.0 and abs(hi[0]) < 50.0 and abs(lo[1]) < 90.0 and abs(hi[1]) < 90.0:
        return 'carb'
    if abs(lo[0]) < 30.0 and abs(hi[0]) < 30.0 and lo[1] > -170.0 and hi[1] < -100.0 and lo[2] > -5.0:
        return 'cap' if 'Material #15' in mats or lo[2] > 140.0 else 'distributor'
    if name in HIDDEN or name in HIDDEN_BOXES or name.startswith(HIDDEN_PREFIXES):
        return None
    if name.startswith('Cylinde') and len(ob['verts']) in HIDDEN_SIZES:
        return None
    return 'block'


def look_of(part, material):
    if part == 'cap':
        return CAP
    if part == 'carb':
        return BLACK if material == 'Material #22' else (CHROME if material.startswith('Metal_') else CARB)
    if part == 'distributor':
        return STEEL
    if part == 'valley':
        return STEEL
    if material in ('Material #22', 'Material #81', 'Material #221'):
        return BLACK
    if material in ('Metal_Galvanized', 'Material #80'):
        return CHROME
    if material == 'Metal_Galvani1':
        return STEEL
    return PAINT


_materials = {}


def material(look):
    name, color, metallic, roughness = look
    if name in _materials:
        return _materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    _materials[name] = mat
    return mat


def build(name, obs, part, origin):
    """One mesh object out of `obs`, in engine units less `origin`."""
    verts, faces, face_looks, looks = [], [], [], []
    for ob in obs:
        kind = 'valley' if ob['name'] == VALLEY else part
        base = len(verts)
        verts.extend(tuple(a - b for a, b in zip(to_engine(p), origin)) for p in ob['verts'])
        by_face = ['default'] * len(ob['faces'])
        for mat_name, idx in ob['groups'].items():
            for i in idx:
                if i < len(by_face):
                    by_face[i] = mat_name
        for f, mat_name in zip(ob['faces'], by_face):
            if len(set(f)) < 3:
                continue
            look = look_of(kind, mat_name)
            if look not in looks:
                looks.append(look)
            faces.append(tuple(base + i for i in f))
            face_looks.append(looks.index(look))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    for look in looks:
        mesh.materials.append(material(look))
    for poly, slot in zip(mesh.polygons, face_looks):
        poly.material_index = slot
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35.0))
    return obj


def export(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objs:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_yup=False, export_apply=True)
    print('wrote', path)


def centre(obs):
    lo = [min(bounds(o)[0][i] for o in obs) for i in range(3)]
    hi = [max(bounds(o)[1][i] for o in obs) for i in range(3)]
    return lo, hi


def point(p):
    return 'Vector3(%.3f, %.3f, %.3f)' % to_engine(p)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    src, out = argv[0], argv[1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects, _ = load(src)
    parts = {}
    for ob in objects:
        part = part_of(ob)
        if part is not None:
            parts.setdefault(part, []).append(ob)
    for part, obs in sorted(parts.items()):
        print(part, len(obs), sorted(o['name'] for o in obs))

    zero = (0.0, 0.0, 0.0)
    block = build('engine_block', parts['block'], 'block', zero)
    export([block], os.path.join(out, 'engine-sbc.glb'))
    intake = build('intake_manifold', parts['intake'], 'intake', zero)
    export([intake], os.path.join(out, 'intake-iron4.glb'))

    # The carb sits on the middle of its spacer's underside.
    lo, hi = centre([o for o in parts['carb'] if o['name'] in CARB_EXTRA])
    pad = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2])
    carb = build('carburetor', parts['carb'], 'carb', to_engine(pad))
    export([carb], os.path.join(out, 'carb-4bbl.glb'))

    # The distributor's base: its hold-down flange, under the cap.
    flange = [o for o in parts['distributor'] if o['name'] == 'Cylinder52']
    lo, hi = centre(flange)
    base = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2])
    body = build('distributor_body', parts['distributor'], 'distributor', to_engine(base))
    cap = build('distributor_cap', parts['cap'], 'cap', to_engine(base))
    export([body, cap], os.path.join(out, 'distributor-sbc.glb'))

    print('CARB_PAD', point(pad))
    print('DISTRIBUTOR_BASE', point(base))
    towers = [o for o in parts['cap'] if o['name'].startswith('Line0') or o['name'] == 'Line010']
    for o in sorted(towers, key=lambda o: o['name']):
        lo, hi = bounds(o)
        top = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, hi[2])
        print('TOWER', o['name'], point(top), 'from base', tuple(round(a - b, 3) for a, b in zip(to_engine(top), to_engine(base))))
    for name in ('Line01', 'Box20', 'Box21', 'Object11', 'Object13', 'Circle04', 'Circle05', 'Circle01', 'Star02'):
        for o in objects:
            if o['name'] == name:
                lo, hi = bounds(o)
                print('BOUNDS', name, point(lo), point(hi))


main()
