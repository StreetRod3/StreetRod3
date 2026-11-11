# Shared helpers for baking MakeHuman figures in Blender with MPFB: making a human, posing its default rig,
# baking it to static meshes, and the plain textured materials the game reads from glTF.
import os, math, addon_utils, bpy, bmesh, numpy as np
from mathutils import Matrix, Vector
addon_utils.enable("bl_ext.blender_org.mpfb", default_set=False, persistent=False)
from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.targetservice import TargetService

LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)
_images = {}
_materials = {}


def texture_of(mhmat, key="diffuseTexture"):
    for line in open(mhmat):
        if line.startswith(key):
            return os.path.join(os.path.dirname(mhmat), line.split()[1])
    raise KeyError(f"{key} not in {mhmat}")


def mhmat_of(mhclo):
    for line in open(mhclo):
        if line.startswith("material "):
            return os.path.join(os.path.dirname(mhclo), line.split()[1])
    raise KeyError(f"no material in {mhclo}")


def load_pixels(path, size):
    img = bpy.data.images.load(path, check_existing=False)
    img.scale(size, size)
    a = np.empty(size * size * 4, np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(size, size, 4)  # rows run bottom to top


def store_pixels(name, a, opaque=False):
    """opaque drops the alpha channel, so the image goes out as JPEG."""
    size = a.shape[0]
    if opaque:
        a[..., 3] = 1.0
    out = bpy.data.images.new(name, size, size, alpha=True)
    out.pixels.foreach_set(a.ravel())
    out.file_format = "PNG" if a[..., 3].min() < 0.999 else "JPEG"
    out.pack()
    return out


def blur(a, passes):
    for _ in range(passes):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5
    return a


def cached_image(key, make):
    """One image per key, so figures sharing a texture share it in the GLB."""
    if key not in _images:
        _images[key] = make()
    return _images[key]


def plain(path, name, size, opaque=False):
    return cached_image(("plain", path, size, opaque), lambda: store_pixels(name, load_pixels(path, size), opaque))


def tinted(path, name, tint, size):
    """Hair-style texture greyed and then tinted, keeping its alpha."""
    def make():
        a = load_pixels(path, size)
        lum = a[..., :3] @ LUMA
        lum = 0.55 + 0.45 * lum / max(float(np.percentile(lum[a[..., 3] > 0.5], 92)), 0.02)
        for c in range(3):
            a[..., c] = np.clip(lum * tint[c], 0, 1)
        return store_pixels(name, a)
    return cached_image(("tinted", path, tuple(tint), size), make)


def mesh_region(size, obj_path, rects):
    """The texture under every piece of a garment's mesh that lies mostly within rects (say every piece of the
    T-shirt and none of the jeans), traced from the pieces' UVs and grown a little over the seams."""
    uvs, faces = [], []
    parent = []
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for line in open(obj_path):
        p = line.split()
        if not p:
            continue
        if p[0] == "v":
            parent.append(len(parent))
        elif p[0] == "vt":
            uvs.append((float(p[1]), float(p[2])))
        elif p[0] == "f":
            corners = [c.split("/") for c in p[1:]]
            faces.append(([int(c[0]) - 1 for c in corners], [uvs[int(c[1]) - 1] for c in corners]))
    for verts, _ in faces:
        for v in verts[1:]:
            parent[find(v)] = find(verts[0])
    def inside(u, v):
        return any(r[0] <= u <= r[2] and r[1] <= v <= r[3] for r in rects)
    votes = {}
    for verts, corners in faces:
        c = find(verts[0])
        u = sum(x for x, _ in corners) / len(corners)
        v = sum(y for _, y in corners) / len(corners)
        n, k = votes.get(c, (0, 0))
        votes[c] = (n + 1, k + inside(u, v))
    mask = np.zeros((size, size), bool)
    for verts, corners in faces:
        n, k = votes[find(verts[0])]
        if k * 2 <= n:
            continue
        pts = np.array(corners) * size
        for i in range(1, len(pts) - 1):
            a, b, c = pts[0], pts[i], pts[i + 1]
            x0, y0 = np.floor(np.minimum(np.minimum(a, b), c)).astype(int)
            x1, y1 = np.ceil(np.maximum(np.maximum(a, b), c)).astype(int)
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, size - 1), min(y1, size - 1)
            if x1 < x0 or y1 < y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(d) < 1e-12:
                continue
            l1 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / d
            l2 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / d
            hit = (l1 >= -0.02) & (l2 >= -0.02) & (l1 + l2 <= 1.02)
            mask[y0:y1 + 1, x0:x1 + 1] |= hit
    return blur(mask.astype(np.float32), 3) > 0.01


def region_mask(size, regions):
    """Rectangles (u0, v0, u1, v1) of the texture, v up as in the UVs; or ("mesh", obj, rects) for mesh_region."""
    if regions and regions[0] == "mesh":
        return mesh_region(size, regions[1], regions[2])
    mask = np.zeros((size, size), bool)
    for u0, v0, u1, v1 in regions:
        mask[int(v0 * size):int(v1 * size), int(u0 * size):int(u1 * size)] = True
    return mask


def recolor(a, regions, color, flatten=0, logo_tolerance=None, brighten=1.0):
    """Repaint rectangles of a garment texture in one colour, keeping the cloth's shading. With logo_tolerance,
    pixels that stray that far from the region's usual colour (logos, trim) are painted out first. flatten blurs
    the shading, which takes out a pattern such as stripes and keeps only the folds."""
    size = a.shape[0]
    region = region_mask(size, regions)
    rgb = a[..., :3]
    lum = rgb @ LUMA
    painted = np.zeros(region.shape, bool)
    if logo_tolerance is not None:
        typical = np.median(rgb[region], axis=0)
        logo = region & (np.abs(rgb - typical).max(-1) > logo_tolerance)
        painted = blur(logo.astype(np.float32), 3) > 0.01  # over the logos' soft edges too
        fill = lum.copy()
        for _ in range(int(size * 0.4)):  # diffuse the surrounding cloth into the holes
            fill = np.where(painted, blur(fill, 1), lum)
        lum = fill
    if flatten:
        lum = blur(lum, flatten)
    shade = np.clip(lum / max(float(np.median(lum[region])), 1e-3), 0.55, 1.25) * brighten
    for c in range(3):
        rgb[..., c] = np.where(region, np.clip(shade * color[c], 0, 1), rgb[..., c])
    a[..., :3] = rgb
    return int(painted.sum())


def garment(path, name, size, repaints=(), opaque=True):
    """A garment texture with a list of recolor() calls, as (regions, colour, keyword args)."""
    key = ("garment", path, size, repr(repaints), opaque)
    def make():
        a = load_pixels(path, size)
        for regions, color, kwargs in repaints:
            recolor(a, regions, color, **kwargs)
        return store_pixels(name, a, opaque)
    return cached_image(key, make)


def material(name, image, alpha_clip=False, roughness=0.7):
    key = (image.name, alpha_clip, roughness)
    if key in _materials:
        return _materials[key]
    mat = bpy.data.materials.new(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha_clip:  # exports as glTF alpha MASK, which Godot draws without sorting trouble
        cut = nodes.new("ShaderNodeMath")
        cut.operation = "GREATER_THAN"
        cut.inputs[1].default_value = 0.4
        links.new(tex.outputs["Alpha"], cut.inputs[0])
        links.new(cut.outputs[0], bsdf.inputs["Alpha"])
    _materials[key] = mat
    return mat


def flat_material(name, color, roughness=0.8):
    key = (name, tuple(color), roughness)
    if key not in _materials:
        mat = bpy.data.materials.new(name)
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        _materials[key] = mat
    return _materials[key]


def make_human(macro):
    """A basemesh with MPFB's default rig. macro holds any of the MakeHuman macro sliders to change."""
    details = TargetService.get_default_macro_info_dict()
    details.update(macro)
    base = HumanService.create_human(mask_helpers=True, macro_detail_dict=details)
    rig = HumanService.add_builtin_rig(base, "default")
    return base, rig


def add_part(base, assets, rel, kind):
    return HumanService.add_mhclo_asset(os.path.join(assets, rel), base, asset_type=kind, subdiv_levels=0,
                                        material_type="NONE")


def aim(rig, bone, end, direction):
    """Turn a pose bone about its head until the segment from its head to bone end's head points along direction."""
    pb = rig.pose.bones[bone]
    head = pb.matrix.to_translation()
    now = rig.pose.bones[end].matrix.to_translation() - head
    rot = now.rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4()
    pb.matrix = Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ pb.matrix
    bpy.context.view_layer.update()


def rotate_about(rig, bone, pivot, axis, degrees):
    pb = rig.pose.bones[bone]
    rot = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(degrees), 4, axis) @ Matrix.Translation(-pivot)
    pb.matrix = rot @ pb.matrix
    bpy.context.view_layer.update()


def head_of(rig, bone):
    return rig.pose.bones[bone].matrix.to_translation()


def aim_arms(rig, upper, fore, side="both"):
    """Arm directions for the left arm (+X); the right arm mirrors them. -Y is the figure's front."""
    for s, sign in (("L", 1.0), ("R", -1.0)):
        if side in ("both", s):
            aim(rig, f"upperarm01.{s}", f"lowerarm01.{s}", (sign * upper[0], upper[1], upper[2]))
            aim(rig, f"lowerarm01.{s}", f"wrist.{s}", (sign * fore[0], fore[1], fore[2]))


def apply_all(ob):
    """Bake shape keys and modifiers (the pose among them) into the mesh. Subdivision is dropped."""
    bpy.context.view_layer.objects.active = ob
    if ob.data.shape_keys:
        ob.shape_key_add(name="mix", from_mix=True)
        mix = ob.data.shape_keys.key_blocks["mix"]
        co = np.empty(len(mix.data) * 3, np.float32)
        mix.data.foreach_get("co", co)
        ob.shape_key_clear()
        ob.data.vertices.foreach_set("co", co)
    for mod in list(ob.modifiers):
        if mod.type == "SUBSURF":
            ob.modifiers.remove(mod)
            continue
        with bpy.context.temp_override(object=ob, active_object=ob):
            bpy.ops.object.modifier_apply(modifier=mod.name)


def bake(objects, rig):
    """Apply every modifier, unparent from the rig keeping the pose, and delete the rig and anything else MPFB
    left about the figure."""
    for ob in objects.values():
        apply_all(ob)
    for ob in objects.values():
        ob.parent = None
        ob.matrix_world = rig.matrix_world @ ob.matrix_world
    keep = set(objects.values())
    for ob in list(bpy.data.objects):
        if ob not in keep and ob.get("keep") is None:
            bpy.data.objects.remove(ob)


def crop_below(ob, z):
    """Drop faces lying wholly below world height z, and the vertices left without faces."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    world = ob.matrix_world
    gone = [f for f in bm.faces if all((world @ v.co).z < z for v in f.verts)]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def delete_faces_in_groups(ob, groups):
    """Drop faces whose every vertex is weighted into one of the vertex groups."""
    index = {ob.vertex_groups[g].index for g in groups if g in ob.vertex_groups}
    if not index:
        return
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    deform = bm.verts.layers.deform.active
    def hidden(v):
        return any(v[deform].get(i, 0.0) >= 0.5 for i in index)
    gone = [f for f in bm.faces if all(hidden(v) for v in f.verts)]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def export(path, image_format="AUTO"):
    """image_format JPEG still writes PNG for textures whose alpha is used."""
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_image_format=image_format,
                              export_animations=False, export_skins=False, export_morph=False,
                              export_cameras=False, export_lights=False)
