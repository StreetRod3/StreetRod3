# Bakes the drive-in's race organizer from MakeHuman's base mesh and system assets: a light-skinned man in a
# plain white T-shirt tucked into jeans, boots, dark hair, leaning back against a wall with his legs crossed.
# One static GLB, textures inside, feet on the ground at the origin.
# blender -b --python make_drive_in_organizer.py -- ASSETS OUT_GLB
import sys, os, math, bpy, bmesh, numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mh_figure import (LUMA, texture_of, mhmat_of, load_pixels, store_pixels, blur, plain, tinted, material,
                       make_human, add_part, aim, aim_arms, rotate_about, head_of, bake, export)

ASSETS, OUT = sys.argv[sys.argv.index("--") + 1:]
TEX_SIZE = 1024
SKIN = "skins/young_caucasian_male/young_caucasian_male.mhmat"
PARTS = {  # name: (mhclo, asset type, material)
    "Eyes": ("eyes/low-poly/low-poly.mhclo", "Eyes", "Eye"),
    "Brows": ("eyebrows/eyebrow001/eyebrow001.mhclo", "Eyebrows", "Brows"),
    "Lashes": ("eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes", "Lashes"),
    "Hair": ("hair/short02/short02.mhclo", "Hair", "Hair"),
    "Clothes": ("clothes/male_casualsuit06/male_casualsuit06.mhclo", "Clothes", "Clothes"),
    "Boots": ("clothes/shoes03/shoes03.mhclo", "Clothes", "Boots"),
}
# Pose, in Blender axes: -Y is his front, +X his left. The body tilts back as a whole, weight on the right foot,
# and the left leg crosses in front of the right shin to rest on its toe beside the right foot.
LEAN = 9.0             # degrees back from upright
HEAD_LEVEL = 8.0       # the neck tips forward again so he looks ahead
CROSS_FOOT = (-0.13, -0.07)  # left ankle from the right ankle, across and forward (m)
CROSS_TOE = (-0.05, -0.55, -0.83)  # the crossed foot's ankle-to-toe direction, toe down
KNEE_POLE = (0.15, -1.0, 0.0)  # the crossed knee bends this way
# Arms hang slightly behind him, hands back toward the wall. Left arm directions; the right mirrors them.
UPPER_ARM = (0.14, 0.12, -1.0)
FOREARM = (0.08, 0.16, -1.0)
# The shirt's panels fill the top of the outfit texture; below this UV height it is jeans.
SHIRT_V = 0.58
TUCK = 0.93   # tucked hem sits this fraction of the waistband's radius from the waist's centre
GATHER = 0.05  # metres of shirt above the waistband that taper into it
TUCK_DEPTH = 0.006  # and the hem stays at least this far behind the jeans
HEM_CUT = 0.012  # shirt lower than this below the top of the waistband is cut away
HAIR_TINT = (0.16, 0.11, 0.08)  # near-black brown


def plain_white_shirt(path):
    """The shirt half of the suit texture without MakeHuman's logos, and neutral white, folds kept."""
    a = load_pixels(path, TEX_SIZE)
    rgb = a[..., :3]
    lum = rgb @ LUMA
    shirt = np.zeros(lum.shape, bool)
    shirt[int(TEX_SIZE * SHIRT_V):, :] = True  # the top 42% of the image holds the shirt panels
    cloth = shirt & (lum > 0.35)  # background between the panels is mid grey, the shirt is near white
    base = blur(np.where(cloth, lum, 0.0), 12) / np.maximum(blur(cloth.astype(np.float32), 12), 1e-3)
    sat = rgb.max(-1) - rgb.min(-1)
    logo = shirt & ((sat > 0.06) | ((lum < base - 0.08) & (lum > 0.2)))
    logo = blur(logo.astype(np.float32), 3) > 0.01  # grow the mask over the logos' soft edges
    fill = lum.copy()
    for _ in range(400):  # diffuse the surrounding cloth into the holes
        fill = np.where(logo, blur(fill, 1), lum)
    white = np.clip(fill * 1.04, 0, 1)
    for c in range(3):
        rgb[..., c] = np.where(shirt, white, rgb[..., c])
    a[..., :3] = rgb
    print(f"shirt: {int(logo.sum())} logo pixels painted out")
    return store_pixels("clothes", a)


def cross_leg(rig):
    """Two-bone solve putting the left ankle across in front of the right one, then the foot on its toe."""
    hip, knee0, ankle0 = (head_of(rig, b) for b in ("upperleg01.L", "lowerleg01.L", "foot.L"))
    thigh, shin = (knee0 - hip).length, (ankle0 - knee0).length
    foot_len = rig.pose.bones["foot.L"].length
    toe = Vector(CROSS_TOE).normalized()
    ground = rig.pose.bones["foot.R"].tail.z
    right = head_of(rig, "foot.R")
    ankle = Vector((right.x + CROSS_FOOT[0], right.y + CROSS_FOOT[1], ground - toe.z * foot_len))
    reach = ankle - hip
    d = min(reach.length, (thigh + shin) * 0.999)
    along = (thigh * thigh - shin * shin + d * d) / (2 * d)
    axis = reach.normalized()
    pole = Vector(KNEE_POLE)
    pole = (pole - axis * pole.dot(axis)).normalized()
    knee = hip + axis * along + pole * math.sqrt(max(thigh * thigh - along * along, 0.0))
    aim(rig, "upperleg01.L", "lowerleg01.L", knee - hip)
    aim(rig, "lowerleg01.L", "foot.L", ankle - knee)
    pb = rig.pose.bones["foot.L"]
    aim_dir = pb.tail - pb.head
    head = pb.head.copy()
    rot = aim_dir.rotation_difference(toe).to_matrix().to_4x4()
    pb.matrix = Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ pb.matrix
    bpy.context.view_layer.update()


def tuck_shirt(ob):
    """Pull the shirt's hem inside the jeans' waistband, gathering it in just above. Runs on the posed mesh, as
    the crossed thigh drags the jeans' waistband away from the shirt, worked upright with the lean undone."""
    mesh = ob.data
    upright = np.array(Matrix.Rotation(math.radians(LEAN), 3, "X"), np.float64)
    co = np.empty(len(mesh.vertices) * 3, np.float64)
    mesh.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3) @ upright.T
    uv = np.empty(len(mesh.loops) * 2, np.float64)
    mesh.uv_layers.active.data.foreach_get("uv", uv)
    loop_vert = np.empty(len(mesh.loops), np.int64)
    mesh.loops.foreach_get("vertex_index", loop_vert)
    shirt = np.zeros(len(co), bool)
    shirt[loop_vert[uv.reshape(-1, 2)[:, 1] > SHIRT_V]] = True
    up = 2  # MakeHuman's mesh is Z-up here, before export
    jeans = co[~shirt]
    top = jeans[:, up].max()
    band = jeans[jeans[:, up] > top - 0.06]
    centre = band[:, :2].mean(0)
    bins = 36
    def angle_bin(p):
        a = np.arctan2(p[:, 1] - centre[1], p[:, 0] - centre[0])
        return ((a + np.pi) / (2 * np.pi) * bins).astype(int) % bins
    band_bin = angle_bin(band)
    waist_z = np.full(bins, top)
    waist_r = np.zeros(bins)
    for b in range(bins):
        ring = band[band_bin == b]
        if len(ring):
            waist_z[b] = ring[:, up].max()
            near = ring[ring[:, up] > waist_z[b] - 0.03]
            waist_r[b] = np.median(np.linalg.norm(near[:, :2] - centre, axis=1))
    waist_r[waist_r == 0] = np.median(waist_r[waist_r > 0])
    idx = np.nonzero(shirt)[0]
    p = co[idx]
    b = angle_bin(p)
    off = p[:, :2] - centre
    r = np.linalg.norm(off, axis=1)
    height = p[:, up] - waist_z[b]
    t = np.clip(height / GATHER, 0.0, 1.0)
    limit = np.where(height < 0.0, waist_r[b] * TUCK, waist_r[b] * TUCK + (r - waist_r[b] * TUCK) * t)
    new_r = np.minimum(r, limit)
    moved = new_r < r - 1e-6
    p[:, :2] = centre + off * (new_r / np.maximum(r, 1e-9))[:, None]
    # The waist isn't round (the small of the back dips in), so then push whatever still lies outside the
    # nearest bit of jeans in behind it.
    normals = np.empty(len(mesh.vertices) * 3, np.float64)
    mesh.vertex_normals.foreach_get("vector", normals)
    normals = normals.reshape(-1, 3) @ upright.T
    jeans_idx = np.nonzero(~shirt & (co[:, up] > top - 0.3))[0]
    tree = KDTree(len(jeans_idx))
    for i in jeans_idx:
        tree.insert(co[i], int(i))
    tree.balance()
    low = np.nonzero(height < 0.02)[0]
    for k in low:
        for _ in range(3):
            _, j, _ = tree.find(p[k])
            depth = np.dot(p[k] - co[j], normals[j])
            if depth <= -TUCK_DEPTH:
                break
            p[k] -= normals[j] * (depth + TUCK_DEPTH)
            moved[k] = True
    co[idx] = p
    mesh.vertices.foreach_set("co", (co @ upright).ravel())
    mesh.update()
    # Shirt that hangs well inside the jeans is never seen, and would only poke through them once posed.
    hidden = set(idx[height < -HEM_CUT].tolist())
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    gone = [f for f in bm.faces if all(v.index in hidden for v in f.verts)]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    print(f"tuck: waistband at {top:.3f}, {int(moved.sum())} shirt vertices pulled in, {len(gone)} hem faces cut")


for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob)
base, rig = make_human({"gender": 1.0, "muscle": 0.6, "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}})
base.name = "Body"
objects = {"Body": base}
for name, (rel, kind, _) in PARTS.items():
    ob = add_part(base, ASSETS, rel, kind)
    ob.name = name
    objects[name] = ob

bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
X = Vector((1, 0, 0))
foot_rest = rig.pose.bones["foot.R"].tail - rig.pose.bones["foot.R"].head
rotate_about(rig, "root", head_of(rig, "root"), X, -LEAN)  # turning about -X tips the top toward +Y, his back
# The standing leg runs straight down the leaning body rather than out to the side as MakeHuman stands.
down = Vector((0.0, -math.sin(math.radians(LEAN)), -math.cos(math.radians(LEAN))))
aim(rig, "upperleg01.R", "lowerleg01.R", down)
aim(rig, "lowerleg01.R", "foot.R", down)
pb = rig.pose.bones["foot.R"]
rotate_about(rig, "foot.R", pb.head.copy(), (pb.tail - pb.head).cross(foot_rest).normalized(),
             math.degrees((pb.tail - pb.head).angle(foot_rest)))  # flat on the ground again
rotate_about(rig, "neck01", head_of(rig, "neck01"), X, HEAD_LEVEL)
cross_leg(rig)
aim_arms(rig, UPPER_ARM, FOREARM)
bpy.ops.object.mode_set(mode="OBJECT")

bake(objects, rig)
tuck_shirt(objects["Clothes"])
# Feet on the ground, centred between the boots.
low = min((ob.matrix_world @ v.co).z for ob in objects.values() for v in ob.data.vertices)
boots = objects["Boots"]
xs = [(boots.matrix_world @ v.co).x for v in boots.data.vertices]
foot_x = (min(xs) + max(xs)) * 0.5
for ob in objects.values():
    ob.matrix_world = Matrix.Translation((-foot_x, 0.0, -low)) @ ob.matrix_world

clothes_mhmat = mhmat_of(os.path.join(ASSETS, PARTS["Clothes"][0]))
mats = {
    "Body": material("Skin", plain(texture_of(os.path.join(ASSETS, SKIN)), "skin", TEX_SIZE), roughness=0.55),
    "Eye": material("Eye", plain(os.path.join(ASSETS, "eyes/materials/brown_eye.png"), "eye", TEX_SIZE), roughness=0.3),
    "Brows": material("Brows", tinted(texture_of(mhmat_of(os.path.join(ASSETS, PARTS["Brows"][0]))), "brows", HAIR_TINT, TEX_SIZE), True),
    "Lashes": material("Lashes", plain(texture_of(mhmat_of(os.path.join(ASSETS, PARTS["Lashes"][0]))), "lashes", TEX_SIZE), True),
    "Hair": material("Hair", tinted(texture_of(mhmat_of(os.path.join(ASSETS, PARTS["Hair"][0]))), "hair", HAIR_TINT, TEX_SIZE), True, 0.5),
    "Clothes": material("Clothes", plain_white_shirt(texture_of(clothes_mhmat)), roughness=0.85),
    "Boots": material("Boots", plain(texture_of(mhmat_of(os.path.join(ASSETS, PARTS["Boots"][0]))), "boots", TEX_SIZE), roughness=0.45),
}
for name, ob in objects.items():
    ob.data.materials.clear()
    ob.data.materials.append(mats[PARTS[name][2] if name in PARTS else name])
    print(f"{name}: {len(ob.data.vertices)} verts, {len(ob.data.polygons)} faces")

export(OUT)
