# Bakes the drive-in's crowd from MakeHuman's base mesh and system assets: a pool of random diners for the
# dining windows, a cook and a waitress for the order window. Clothes are kept to what passes for 1972: the sports
# outfit is left out, and the T-shirts lose MakeHuman's logos and trim for a plain colour of the time.
# Everyone is cut off below the window sills, which hide their legs. One GLB with a node per figure (Diner00...,
# Cook, Waitress), feet at the origin, facing +Z.
# blender -b --python make_drive_in_people.py -- ASSETS OUT_GLB
import sys, os, glob, math, random, bpy, numpy as np
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mh_figure import (texture_of, mhmat_of, plain, tinted, garment, material, flat_material, make_human, add_part,
                       aim_arms, rotate_about, head_of, bake, crop_below, delete_faces_in_groups, export)

ASSETS, OUT = sys.argv[sys.argv.index("--") + 1:]
SEED = 1972
DINERS = 14       # more than the ten places, so the game can pick a different crowd each visit
TEX = 512         # skin and clothes; each figure is a few dozen pixels tall in the game
SMALL = 256       # hair, brows, eyes
CROP_Z = 0.8      # metres above the feet; the sills hide everything lower
PROXIES = {True: "male1591", False: "female1605"}  # MakeHuman's low-poly bodies, on the usual skin textures
# Colours T-shirts and the cook's whites are repainted in.
COLORS_1972 = [(0.80, 0.62, 0.16), (0.78, 0.36, 0.12), (0.42, 0.44, 0.18), (0.45, 0.28, 0.16), (0.55, 0.12, 0.14),
               (0.12, 0.42, 0.42), (0.88, 0.84, 0.70), (0.42, 0.58, 0.76), (0.62, 0.30, 0.42), (0.90, 0.90, 0.88)]
HAIR = {"black": (0.07, 0.06, 0.06), "dark": (0.16, 0.11, 0.08), "brown": (0.32, 0.21, 0.12),
        "auburn": (0.46, 0.21, 0.10), "blonde": (0.78, 0.62, 0.38), "grey": (0.58, 0.57, 0.55)}
EYES = ["brown", "brownlight", "blue", "bluegreen", "green", "grey"]
WHITE = (0.95, 0.95, 0.93)
# Rough texture rectangles (u0, v0, u1, v1) in each logo T-shirt's panels. The mesh pieces mostly inside them are
# the shirt, and their UVs give the exact area to repaint.
TEE_RECTS = {
    "male_casualsuit02": [(0.0, 0.6, 1.0, 1.0), (0.728, 0.0, 1.0, 0.6)],
    "male_casualsuit04": [(0.0, 0.6, 1.0, 1.0)],
    "male_casualsuit06": [(0.0, 0.58, 1.0, 1.0)],
    "female_casualsuit01": [(0.0, 0.58, 1.0, 1.0), (0.715, 0.05, 1.0, 0.4)],
    "female_casualsuit02": [(0.0, 0.58, 1.0, 1.0), (0.725, 0.05, 1.0, 0.4)],
}
TEE = {name: ("mesh", os.path.join(ASSETS, "clothes", name, name + ".obj"), rects) for name, rects in TEE_RECTS.items()}
VARIANTS = {"male_casualsuit01": "toigo_male_casual_suit_01_*", "male_elegantsuit01": "toigo_male_elegant_suit_*"}
OUTFITS = {
    "male": ["male_casualsuit01", "male_casualsuit01", "male_casualsuit02", "male_casualsuit03", "male_casualsuit04",
             "male_casualsuit05", "male_casualsuit06", "male_elegantsuit01", "male_worksuit01"],
    "female": ["female_casualsuit01", "female_casualsuit02", "female_elegantsuit01"],
}
HAIRCUTS = {"male": ["short01", "short02", "short03", "short04"],
            "female": ["bob01", "bob02", "long01", "ponytail01", "braid01"]}
POSES = {  # left arm directions (upper arm, forearm); -Y is the front
    "down": ((0.12, 0.03, -1.0), (0.06, -0.2, -1.0)),
    "forward": ((0.1, -0.25, -1.0), (0.12, -1.0, -0.1)),
}


def clothes_path(name, rng):
    rel = f"clothes/{name}/{name}.mhclo"
    texture = texture_of(mhmat_of(os.path.join(ASSETS, rel)))
    if name in VARIANTS:
        options = sorted(glob.glob(os.path.join(ASSETS, "clothes", name, VARIANTS[name], "*.mhmat")))
        pick = rng.choice([None] + options)
        if pick:
            texture = texture_of(pick)
    return rel, texture


def random_diner(rng):
    sex = rng.choice(["male", "female"])
    race = rng.choices(["caucasian", "african", "asian"], [0.6, 0.28, 0.12])[0]
    age = rng.choices(["young", "middleage"], [0.75, 0.25])[0]
    mix = {r: 0.1 for r in ("caucasian", "african", "asian")}
    mix[race] = 0.8
    macro = {"gender": 1.0 if sex == "male" else 0.0, "race": mix,
             "age": rng.uniform(0.44, 0.56) if age == "young" else rng.uniform(0.6, 0.7),
             "weight": rng.uniform(0.3, 0.8), "muscle": rng.uniform(0.3, 0.7), "height": rng.uniform(0.3, 0.7)}
    outfit = rng.choice(OUTFITS[sex])
    rel, texture = clothes_path(outfit, rng)
    repaint = ()
    if outfit in TEE:
        repaint = ((TEE[outfit], rng.choice(COLORS_1972), {"logo_tolerance": 0.15}),)
    cuts = HAIRCUTS[sex] + (["afro01"] if race == "african" else [])
    if race == "caucasian":
        hair = rng.choices(["black", "dark", "brown", "auburn", "blonde"], [1, 3, 3, 1, 2])[0]
        eyes = rng.choice(EYES)
    else:
        hair, eyes = rng.choice(["black", "dark"]), "brown"
    if age == "middleage" and rng.random() < 0.3:
        hair = "grey"
    return {"macro": macro, "skin": f"{age}_{race}_{sex}", "clothes": (rel, texture, repaint),
            "hair": rng.choice(cuts), "hair_color": hair, "eyes": eyes,
            "pose": (rng.choice(list(POSES)), rng.uniform(-14, 14)), "hat": None}


def cook():
    rel = "clothes/male_casualsuit06/male_casualsuit06.mhclo"
    texture = texture_of(mhmat_of(os.path.join(ASSETS, rel)))
    whites = ((TEE["male_casualsuit06"], WHITE, {"logo_tolerance": 0.15}),
              ([(0.0, 0.0, 1.0, 0.58)], WHITE, {"flatten": 8, "brighten": 0.94}))
    return {"macro": {"gender": 1.0, "age": 0.62, "weight": 0.75, "muscle": 0.55,
                      "race": {"caucasian": 0.8, "african": 0.1, "asian": 0.1}},
            "skin": "middleage_caucasian_male", "clothes": (rel, texture, whites),
            "hair": "short01", "hair_color": "dark", "eyes": "brown", "pose": ("forward", 6), "hat": "toque"}


def waitress():
    rel = "clothes/female_elegantsuit01/female_elegantsuit01.mhclo"
    texture = texture_of(mhmat_of(os.path.join(ASSETS, rel)))
    pink = (([(0.0, 0.0, 1.0, 1.0)], (0.93, 0.56, 0.64), {"flatten": 60}),)  # stripes out, one uniform pink
    return {"macro": {"gender": 0.0, "age": 0.47, "weight": 0.45, "muscle": 0.45,
                      "race": {"caucasian": 0.8, "african": 0.1, "asian": 0.1}},
            "skin": "young_caucasian_female", "clothes": (rel, texture, pink),
            "hair": "ponytail01", "hair_color": "auburn", "eyes": "green", "pose": ("one_forward", -8), "hat": "cap"}


def add_hat(kind, name, body):
    """A cook's toque or a waitress's paper cap, white, sat on the scalp (hair meshes reach above it in places
    that are see-through)."""
    zs = [(body.matrix_world @ v.co) for v in body.data.vertices]
    top = max(p.z for p in zs)
    crown = [p for p in zs if p.z > top - 0.08]
    cx = sum(p.x for p in crown) / len(crown)
    cy = sum(p.y for p in crown) / len(crown)
    made = []
    if kind == "toque":
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.1, depth=0.13, location=(cx, cy, top + 0.045))
        made.append(bpy.context.object)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=0.125, location=(cx, cy, top + 0.12))
        puff = bpy.context.object
        puff.scale = (1.0, 1.0, 0.55)
        made.append(puff)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy - 0.04, top - 0.012),
                                        rotation=(math.radians(18), 0.0, 0.0))
        cap = bpy.context.object
        cap.scale = (0.17, 0.03, 0.06)
        made.append(cap)
    for ob in made:
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        bpy.ops.object.shade_smooth()
    if len(made) > 1:
        with bpy.context.temp_override(active_object=made[0], selected_editable_objects=made):
            bpy.ops.object.join()
    hat = made[0]
    hat.name = f"{name}_Hat"
    hat.data.materials.append(flat_material("Hat", WHITE))
    return hat


def build(name, spec):
    base, rig = make_human(spec["macro"])
    proxy = PROXIES[spec["macro"]["gender"] >= 0.5]
    body = add_part(base, ASSETS, f"proxymeshes/{proxy}/{proxy}.proxy", "Proxymeshes")
    rel, texture, repaint = spec["clothes"]
    parts = {"Clothes": add_part(base, ASSETS, rel, "Clothes"),
             "Eyes": add_part(base, ASSETS, "eyes/low-poly/low-poly.mhclo", "Eyes"),
             "Brows": add_part(base, ASSETS, "eyebrows/eyebrow001/eyebrow001.mhclo", "Eyebrows"),
             "Hair": add_part(base, ASSETS, f"hair/{spec['hair']}/{spec['hair']}.mhclo", "Hair")}
    objects = {"Body": body, **parts}
    # The clothes hide the body under them with a mask, but on the coarse proxy that takes whole faces that show
    # at the neckline. Only faces wholly under the clothes go instead, after baking.
    hidden_groups = [m.vertex_group for m in body.modifiers if m.type == "MASK"]
    for mod in [m for m in body.modifiers if m.type == "MASK"]:
        body.modifiers.remove(mod)

    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    pose, turn = spec["pose"]
    if pose == "one_forward":
        aim_arms(rig, *POSES["forward"], side="R")
        aim_arms(rig, *POSES["down"], side="L")
    else:
        aim_arms(rig, *POSES[pose])
    rotate_about(rig, "neck01", head_of(rig, "neck01"), Vector((0, 0, 1)), turn)
    bpy.ops.object.mode_set(mode="OBJECT")
    bake(objects, rig)
    delete_faces_in_groups(body, hidden_groups)

    low = min((body.matrix_world @ v.co).z for v in body.data.vertices)
    for ob in objects.values():
        ob.matrix_world = Matrix.Translation((0.0, 0.0, -low)) @ ob.matrix_world
    if spec["hat"]:
        objects["Hat"] = add_hat(spec["hat"], name, body)
    for ob in objects.values():
        crop_below(ob, CROP_Z)

    hair_tint = HAIR[spec["hair_color"]]
    brows = texture_of(mhmat_of(os.path.join(ASSETS, "eyebrows/eyebrow001/eyebrow001.mhclo")))
    hair_tex = texture_of(mhmat_of(os.path.join(ASSETS, f"hair/{spec['hair']}/{spec['hair']}.mhclo")))
    skin = texture_of(os.path.join(ASSETS, f"skins/{spec['skin']}/{spec['skin']}.mhmat"))
    mats = {
        "Body": material("Skin", plain(skin, "skin_" + spec["skin"], TEX, True), roughness=0.55),
        "Clothes": material("Clothes", garment(texture, "clothes_" + os.path.basename(texture), TEX, repaint), roughness=0.85),
        "Eyes": material("Eye", plain(os.path.join(ASSETS, f"eyes/materials/{spec['eyes']}_eye.png"), "eye_" + spec["eyes"], SMALL, True), roughness=0.3),
        "Brows": material("Brows", tinted(brows, "brows_" + spec["hair_color"], hair_tint, SMALL), True),
        "Hair": material("Hair", tinted(hair_tex, f"hair_{spec['hair']}_{spec['hair_color']}", hair_tint, SMALL), True, 0.5),
    }
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    root["keep"] = 1
    verts = 0
    for part, ob in objects.items():
        if part in mats:
            ob.data.materials.clear()
            ob.data.materials.append(mats[part])
        for key in list(ob.keys()):  # MPFB's markers, so later figures don't take this one for theirs
            del ob[key]
        ob.name = ob.data.name = f"{name}_{part}"
        ob.parent = root
        ob["keep"] = 1
        verts += len(ob.data.vertices)
    print(f"{name}: {spec['skin']}, {os.path.basename(texture)}, {spec['hair']} {spec['hair_color']}, {pose}, {verts} verts")


for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob)
rng = random.Random(SEED)
for i in range(DINERS):
    build(f"Diner{i:02d}", random_diner(rng))
build("Cook", cook())
build("Waitress", waitress())
for ob in bpy.data.objects:
    if "keep" in ob:
        del ob["keep"]
export(OUT, "JPEG")
