# Bakes MakeHuman's base mesh and system assets into a head-and-shoulders driver.
# blender -b --python make_driver_model.py -- ASSETS TEXTURES OUT_DIR GLASSES_MHCLO
import sys, os, addon_utils, bpy, numpy as np
addon_utils.enable("bl_ext.blender_org.mpfb", default_set=False, persistent=False)
from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.clothesservice import ClothesService
from bl_ext.blender_org.mpfb.services.targetservice import TargetService
from bl_ext.blender_org.mpfb.entities.clothes.mhclo import Mhclo
from bl_ext.blender_org.mpfb.entities.objectproperties import HumanObjectProperties
from bl_ext.blender_org.mpfb.services.locationservice import LocationService

ASSETS, TEX, OUT, GLASSES = sys.argv[sys.argv.index("--") + 1:]
BODY_VERTS = 13380  # the rest of the base mesh is helper geometry
SINK_CHEST = 0.012  # meters
CROP = 0.5          # below the eyes, under the bottom of the photo at any height
WEIGHTS = {"Basis": 0.5, "slim": 0.1, "heavy": 1.0}
# The weight slider hardly touches the head, so these carry a build into the photo.
BOTH_SIDES = ("l-", "r-")
SHAPE_TARGETS = {
    "Basis": {},
    "slim": {"head/head-fat-decr": 0.7, "cheek/l-cheek-volume-decr": 0.25, "cheek/r-cheek-volume-decr": 0.25,
             "neck/neck-scale-horiz-decr": 0.5, "neck/neck-scale-depth-decr": 0.5},
    "heavy": {"head/head-fat-incr": 1.0, "cheek/l-cheek-volume-incr": 0.45, "cheek/r-cheek-volume-incr": 0.45,
              "neck/neck-double-incr": 1.0, "neck/neck-scale-horiz-incr": 0.8, "neck/neck-scale-depth-incr": 0.8,
              "torso/torso-scale-horiz-incr": 0.5, "torso/torso-scale-depth-incr": 0.5},
}
SEXES = {
    "m": {"gender": 1.0, "shirt": "clothes/male_casualsuit01/male_casualsuit01.mhclo",
          "hair": ["short02"]},
    "f": {"gender": 0.0, "shirt": "clothes/female_elegantsuit01/female_elegantsuit01.mhclo",
          "hair": ["long01"]},
}

def coords(mesh):
    a = np.empty(len(mesh.vertices) * 3, np.float64)
    mesh.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)

def mix_coords(base):
    key = base.shape_key_add(name="read", from_mix=True)
    a = np.empty(len(key.data) * 3, np.float64)
    key.data.foreach_get("co", a)
    base.shape_key_remove(key)
    return a.reshape(-1, 3)

def material(name, image, alpha):
    mat = bpy.data.materials.new(name)
    if image is None:  # the game sets this texture
        return mat
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX, image), check_existing=True)
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6
    if alpha:
        mat.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.blend_method = "BLEND"
    return mat

def is_cornea(uv):
    # The clear shell over the eyeball maps to a transparent dot in the corner of the texture.
    return uv[0] > 0.8 and uv[1] < 0.2

def build(name, src_obj, shapes, mat, keep_vert=None):
    """A cropped copy of src with the given per-variant coordinates as shape keys."""
    src = src_obj.data
    base = shapes["Basis"]
    polys, uvs = [], []
    uv = src.uv_layers.active.data if src.uv_layers.active else None
    for p in src.polygons:
        vs = list(p.vertices)
        if keep_vert is not None and not all(keep_vert[v] for v in vs):
            continue
        if max(base[v][2] for v in vs) < -CROP:
            continue
        if name == "Eyes" and all(is_cornea(uv[i].uv) for i in p.loop_indices):
            continue
        polys.append(vs)
        uvs.extend(uv[i].uv[:] if uv else (0, 0) for i in p.loop_indices)
    used = sorted({v for p in polys for v in p})
    remap = {v: i for i, v in enumerate(used)}
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(base[used].tolist(), [], [[remap[v] for v in p] for p in polys])
    layer = mesh.uv_layers.new(name="UVMap")
    layer.data.foreach_set("uv", np.array(uvs, np.float32).ravel())
    mesh.polygons.foreach_set("use_smooth", [True] * len(polys))
    mesh.update()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.shape_key_add(name="Basis")
    for key, co in shapes.items():
        if key != "Basis":
            obj.shape_key_add(name=key).data.foreach_set("co", co[used].ravel())
    print(f"{name}: {len(used)} verts, {len(polys)} faces")
    return obj

def bake(sex, cfg):
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    macro = TargetService.get_default_macro_info_dict()
    macro["gender"] = cfg["gender"]
    # An even mix, so that skin tone alone never changes the shape of the face.
    macro["race"] = {"asian": 1 / 3, "caucasian": 1 / 3, "african": 1 / 3}
    base = HumanService.create_human(mask_helpers=False, macro_detail_dict=macro)
    parts = {"Eyes": "eyes/high-poly/high-poly.mhclo", "Brows": "eyebrows/eyebrow001/eyebrow001.mhclo",
             "Lashes": "eyelashes/eyelashes01/eyelashes01.mhclo", "Shirt": cfg["shirt"], "Glasses": GLASSES}
    for h in cfg["hair"]:
        parts["Hair_" + h] = f"hair/{h}/{h}.mhclo"
    loaded = {}
    for name, rel in parts.items():
        m = Mhclo()
        m.load(os.path.join(ASSETS, rel))
        m.load_mesh(bpy.context)
        loaded[name] = m
    body = {}
    fitted = {name: {} for name in parts}
    targets = LocationService.get_mpfb_data("targets")
    for key, weight in WEIGHTS.items():
        HumanObjectProperties.set_value("weight", weight, entity_reference=base)
        TargetService.reapply_macro_details(base)
        for others in SHAPE_TARGETS.values():
            for rel in others:
                name = rel.split("/")[1]
                if not TargetService.has_target(base, name):
                    TargetService.load_target(base, os.path.join(targets, rel + ".target.gz"), weight=0.0, name=name)
                TargetService.set_target_value(base, name, SHAPE_TARGETS[key].get(rel, 0.0))
        co = mix_coords(base)
        for name, m in loaded.items():
            ClothesService.fit_clothes_to_human(m.clothes, base, mhclo=m, set_parent=False)
            fitted[name][key] = coords(m.clothes.data)
        # The eyes stay put so the photo never needs reframing.
        eye = fitted["Eyes"][key]
        centre = (eye.min(0) + eye.max(0)) / 2
        body[key] = co - centre
        for name in parts:
            fitted[name][key] = fitted[name][key] - centre
    # Chest skin sinks behind the shirt, which would otherwise show it on a slim driver.
    ramp = np.clip((-0.16 - body["Basis"][:, 2]) / 0.06, 0.0, 1.0) * SINK_CHEST
    for key in body:
        body[key][:, 1] += ramp
    hidden = set(int(v) for v in loaded["Shirt"].delverts)
    keep = [i < BODY_VERTS and i not in hidden for i in range(len(base.data.vertices))]
    mats = {"Body": material("Skin", None, False), "Eyes": material("Eye", None, False),
            "Brows": material("Brows", "brows.png", True), "Lashes": material("Lashes", "lashes.png", True),
            "Shirt": material("Shirt", f"shirt_{sex}.jpg", False), "Glasses": material("Glasses", "glasses.png", False)}
    sources = {name: loaded[name].clothes for name in parts}
    made = [build("Body", base, body, mats["Body"], keep)]
    for name, src in sources.items():
        mat = mats.get(name) or material(name, name.replace("Hair_", "hair_") + ".png", True)
        made.append(build(name, src, fitted[name], mat))
    for ob in list(bpy.context.scene.collection.all_objects):
        if ob not in made:
            bpy.data.objects.remove(ob)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"driver_{sex}.glb"), export_format="GLB", export_yup=True,
                              export_morph=True, export_morph_normal=True, export_animations=False,
                              export_skins=False, export_cameras=False, export_lights=False)

for sex, cfg in SEXES.items():
    bake(sex, cfg)
