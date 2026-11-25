import json
import struct
import trimesh
import numpy as np
from PIL import Image

# --- CONFIGURATION ---
INPUT_GLB = "/home/hellmark/Code/StreetRod3/assets/cars/chevy-c10-1963.glb"
OUTPUT_GLB = "chevy-c10-pixelated.glb"
PIXEL_DENSITY = 24      # Lower = bigger, chunkier pixels (try 16, 24, or 32)
SKIP_KEYWORDS = ["dash", "needle", "glass", "window"]

scene = trimesh.load(INPUT_GLB)

for node_name in scene.graph.nodes_geometry:
    if any(k in node_name.lower() for k in SKIP_KEYWORDS):
        continue

    transform, geom_name = scene.graph[node_name]
    mesh = scene.geometry[geom_name]

    if not hasattr(mesh.visual, "uv") or mesh.visual.uv is None:
        continue

    mat = mesh.visual.material
    orig_img = getattr(mat, "baseColorTexture", None) or getattr(mat, "image", None)
    if orig_img is None:
        continue

    orig_arr = np.array(orig_img.convert("RGB"))
    oh, ow, _ = orig_arr.shape

    verts_world = trimesh.transform_points(mesh.vertices, transform)
    faces = mesh.faces
    v0, v1, v2 = verts_world[faces[:, 0]], verts_world[faces[:, 1]], verts_world[faces[:, 2]]
    face_normals = np.abs(np.cross(v1 - v0, v2 - v0))
    dominant_axis = np.argmax(face_normals, axis=1)

    # Project onto the 2 straight car-aligned axes in world-pixel units
    tri_verts = verts_world[faces]
    world_px = np.zeros((len(faces), 3, 2), dtype=np.float32)

    for axis, cols in [(0, [2, 1]), (1, [0, 2]), (2, [0, 1])]:
        mask = dominant_axis == axis
        world_px[mask] = tri_verts[mask][:, :, cols] * PIXEL_DENSITY

    # Snap each triangle's origin to an INTEGER world-pixel grid cell!
    # This guarantees pixels align seamlessly across adjacent triangles.
    grid_mins = np.floor(world_px.min(axis=1, keepdims=True))
    local_2d = world_px - grid_mins
    spans = np.ceil(local_2d.max(axis=1)).astype(int) + 4  # +4px bleed margin

    # Pack onto atlas
    max_w = max(512, int(np.sqrt(np.sum(spans[:, 0] * spans[:, 1])) * 1.4))
    cursor_x, cursor_y, row_h = 2, 2, 0
    placements = []

    for w, h in spans:
        if cursor_x + w >= max_w - 2:
            cursor_x = 2
            cursor_y += row_h + 2
            row_h = 0
        placements.append((cursor_x, cursor_y))
        cursor_x += w + 2
        row_h = max(row_h, h)

    tex_w = max_w
    tex_h = max(64, cursor_y + row_h + 4)
    new_tex = np.zeros((tex_h, tex_w, 3), dtype=np.uint8)

    new_uvs = np.zeros((len(faces) * 3, 2), dtype=np.float32)
    old_uvs = mesh.visual.uv[faces]

    for f_idx in range(len(faces)):
        ox, oy = placements[f_idx]
        # Shift by +1px inside the padded cell so bleed covers all edges
        p = local_2d[f_idx] + np.array([ox + 1.0, oy + 1.0], dtype=np.float32)

        uv_tri = np.zeros((3, 2), dtype=np.float32)
        uv_tri[:, 0] = p[:, 0] / tex_w
        uv_tri[:, 1] = 1.0 - (p[:, 1] / tex_h)
        new_uvs[f_idx * 3 : f_idx * 3 + 3] = uv_tri

        # Bounding box including 2px outward edge-clamp bleed (prevents dark squiggles)
        min_x = max(0, int(np.floor(p[:, 0].min())) - 2)
        max_x = min(tex_w - 1, int(np.ceil(p[:, 0].max())) + 2)
        min_y = max(0, int(np.floor(p[:, 1].min())) - 2)
        max_y = min(tex_h - 1, int(np.ceil(p[:, 1].max())) + 2)

        denom = (p[1, 1] - p[2, 1]) * (p[0, 0] - p[2, 0]) + (p[2, 0] - p[1, 0]) * (p[0, 1] - p[2, 1])
        ouv = old_uvs[f_idx]

        if abs(denom) < 1e-6:
            uv_c = ouv.mean(axis=0)
            u_i = np.clip(int(uv_c[0] * (ow - 1)), 0, ow - 1)
            v_i = np.clip(int((1.0 - uv_c[1]) * (oh - 1)), 0, oh - 1)
            new_tex[min_y : max_y + 1, min_x : max_x + 1] = orig_arr[v_i, u_i]
            continue

        # Sample pixel centers (x + 0.5, y + 0.5) and clamp outside barycentrics to nearest edge color
        for y in range(min_y, max_y + 1):
            py = y + 0.5
            for x in range(min_x, max_x + 1):
                px = x + 0.5
                w0 = ((p[1, 1] - p[2, 1]) * (px - p[2, 0]) + (p[2, 0] - p[1, 0]) * (py - p[2, 1])) / denom
                w1 = ((p[2, 1] - p[0, 1]) * (px - p[2, 0]) + (p[0, 0] - p[2, 0]) * (py - p[2, 1])) / denom
                w2 = 1.0 - w0 - w1

                # Clamp barycentric weights so outer bleed pixels inherit the triangle's edge color
                w0c, w1c, w2c = np.clip([w0, w1, w2], 0.0, 1.0)
                s = w0c + w1c + w2c
                if s > 0:
                    w0c, w1c, w2c = w0c / s, w1c / s, w2c / s

                uv_sample = w0c * ouv[0] + w1c * ouv[1] + w2c * ouv[2]
                u_i = np.clip(int(uv_sample[0] * (ow - 1)), 0, ow - 1)
                v_i = np.clip(int((1.0 - uv_sample[1]) * (oh - 1)), 0, oh - 1)
                new_tex[y, x] = orig_arr[v_i, u_i]

#    new_verts = mesh.vertices[faces].reshape(-1, 3)
  #  new_faces = np.arange(len(new_verts)).reshape(-1, 3)
   # new_mesh = trimesh.Trimesh(vertices=new_verts, faces=new_faces, process=False)
# Extract original vertex normals BEFORE unwelding so smooth shading & lighting stay intact
    orig_normals = mesh.vertex_normals
    new_normals = orig_normals[faces].reshape(-1, 3)

    new_verts = mesh.vertices[faces].reshape(-1, 3)
    new_faces = np.arange(len(new_verts)).reshape(-1, 3)
    new_mesh = trimesh.Trimesh(
        vertices=new_verts,
        faces=new_faces,
        vertex_normals=new_normals,
        process=False,
    )

    pil_tex = Image.fromarray(new_tex, "RGB")
    material = trimesh.visual.material.PBRMaterial(
        baseColorTexture=pil_tex,
        roughnessFactor=0.8,
        metallicFactor=0.0,
    )
    new_mesh.visual = trimesh.visual.TextureVisuals(uv=new_uvs, material=material)
    scene.geometry[geom_name] = new_mesh

#    pil_tex = Image.fromarray(new_tex, "RGB")
 #   material = trimesh.visual.material.PBRMaterial(baseColorTexture=pil_tex)
  #  new_mesh.visual = trimesh.visual.TextureVisuals(uv=new_uvs, material=material)
   # scene.geometry[geom_name] = new_mesh

scene.export(OUTPUT_GLB)

# Explicitly attach a GL_NEAREST (9728) sampler to EVERY texture in the GLB
with open(OUTPUT_GLB, "rb") as f:
    data = bytearray(f.read())

json_len = struct.unpack("<I", data[12:16])[0]
gltf = json.loads(data[20 : 20 + json_len].decode("utf-8"))

gltf["samplers"] = [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}]
for tex in gltf.get("textures", []):
    tex["sampler"] = 0

new_json = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
while len(new_json) % 4 != 0:
    new_json += b" "

bin_chunk = data[20 + json_len :]
new_total_len = 12 + 8 + len(new_json) + len(bin_chunk)
patched = (
    data[:8]
    + struct.pack("<I", new_total_len)
    + struct.pack("<I", len(new_json))
    + data[16:20]
    + new_json
    + bin_chunk
)

with open(OUTPUT_GLB, "wb") as f:
    f.write(patched)

print(f"Done! Saved crisp pixelated model to {OUTPUT_GLB}")
