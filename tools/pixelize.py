#!/usr/bin/env python3
"""Give a car model a pixel-art texture: big square texels, a few colors.

Every textured, opaque surface is laid flat on whichever of the car's six sides
it faces most (side, front, back, top, underneath), the way a PSX-era car
texture is painted. Connected faces that face the same way share one piece of
the new texture, so a whole door or fender is one grid of square texels, and
the grid is at a fixed size in meters across the car, lined up with the
paint's dither squares when the size comes from a .car file's dither_cell.
Each texel is the average of the old texture under it, and the colors are then
cut down to a small palette for the whole car.

The game's paint mask is kept: a texel is paint (alpha 1) or not (alpha 0) by
what most of the old texture under it was, and with an accent (model.accent in
the .car file) a paint texel is grey for the body and has no blue for the
accent. Materials keep their names and settings; their color, metal/roughness,
occlusion, emissive and normal textures are all remade in the new layout. A
normal map is where most of a low-poly model's shape lives (bevels, creases,
panel lines), so it is turned into car-space normals through the old layout's
tangents and back through the new one's, a texel at a time like the colors.
Glass, the dash and gauges,
the license plate and anything else named in --skip are left as they are.

Usage:
  tools/pixelize.py --car assets/cars/chevy-c10-1963.car -o out.glb
  tools/pixelize.py model.glb -o out.glb --ppm 25 --colors 48
"""

import argparse
import copy
import io
import json
import math
import struct
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.cluster.vq import kmeans2
from scipy.spatial import cKDTree

PROJECT = Path(__file__).resolve().parent.parent

COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
COMPONENT_OF = {np.dtype(v): k for k, v in COMPONENT.items()}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
TYPE_OF = {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}
GL_NEAREST = 9728
GL_NEAREST_MIPMAP_LINEAR = 9986
GL_CLAMP_TO_EDGE = 33071

DEFAULT_SKIP = ["dash", "needle", "gauge", "speedo", "tach", "glass", "window", "plate"]
# Gap between pieces of the atlas, in texels on each side.
GUTTER = 2

# The 2D (u, v) axes each of the six sides is laid flat on, as (axis, sign) pairs, chosen
# so every side reads as seen from outside the car.
SIDE_AXES = {
    (0, 1): ((2, -1), (1, 1)),
    (0, -1): ((2, 1), (1, 1)),
    (1, 1): ((0, 1), (2, -1)),
    (1, -1): ((0, -1), (2, -1)),
    (2, 1): ((0, 1), (1, 1)),
    (2, -1): ((0, -1), (1, 1)),
}


# --- glTF binary reading and writing ---------------------------------------------------


class Glb:
    def __init__(self, path):
        data = Path(path).read_bytes()
        magic, _version, length = struct.unpack("<4sII", data[:12])
        if magic != b"glTF":
            sys.exit(f"{path} is not a binary glTF file")
        self.json = None
        self.bin = b""
        off = 12
        while off < length:
            chunk_len, chunk_type = struct.unpack("<II", data[off : off + 8])
            chunk = data[off + 8 : off + 8 + chunk_len]
            if chunk_type == 0x4E4F534A:
                self.json = json.loads(chunk)
            elif chunk_type == 0x004E4942:
                self.bin = chunk
            off += 8 + chunk_len

    def view_bytes(self, index):
        view = self.json["bufferViews"][index]
        if view.get("buffer", 0) != 0 or "uri" in self.json["buffers"][view.get("buffer", 0)]:
            sys.exit("only self-contained .glb files are supported")
        start = view.get("byteOffset", 0)
        return self.bin[start : start + view["byteLength"]]

    def accessor(self, index):
        """The accessor's values as stored: an (count, width) array of its component type."""
        acc = self.json["accessors"][index]
        if "sparse" in acc:
            sys.exit(f"accessor {index} is sparse, which is not supported")
        dtype = np.dtype(COMPONENT[acc["componentType"]])
        width = WIDTH[acc["type"]]
        count = acc["count"]
        if "bufferView" not in acc:
            return np.zeros((count, width), dtype)
        view = self.json["bufferViews"][acc["bufferView"]]
        raw = self.view_bytes(acc["bufferView"])
        stride = view.get("byteStride") or dtype.itemsize * width
        return np.ndarray(
            (count, width), dtype=dtype, buffer=raw, offset=acc.get("byteOffset", 0), strides=(stride, dtype.itemsize)
        ).copy()

    def floats(self, index):
        """The accessor's values as float64, normalized integers turned into 0..1 (or -1..1)."""
        acc = self.json["accessors"][index]
        values = self.accessor(index)
        if acc.get("normalized") and values.dtype.kind in "iu":
            return np.maximum(values.astype(np.float64) / np.iinfo(values.dtype).max, -1.0)
        return values.astype(np.float64)

    def image(self, index):
        img = self.json["images"][index]
        if "bufferView" not in img:
            sys.exit(f"image {index} is not embedded in the .glb")
        return Image.open(io.BytesIO(self.view_bytes(img["bufferView"])))

    def add_accessor(self, values, normalized=False):
        """Append an accessor that holds `values` ((count, width) array); returns its index."""
        values = np.ascontiguousarray(values)
        acc = {
            "componentType": COMPONENT_OF[values.dtype],
            "count": int(values.shape[0]),
            "type": TYPE_OF[values.shape[1]],
            "_data": values,
        }
        if normalized:
            acc["normalized"] = True
        self.json["accessors"].append(acc)
        return len(self.json["accessors"]) - 1

    def add_png(self, image, name=None):
        out = io.BytesIO()
        image.save(out, format="PNG", optimize=True)
        img = {"mimeType": "image/png", "_bytes": out.getvalue()}
        if name:
            img["name"] = name
        self.json["images"].append(img)
        return len(self.json["images"]) - 1

    def save(self, path):
        """Write the model, keeping only what is still used and packing its data afresh."""
        g = self.json
        used_mats, used_accs = set(), set()
        for mesh in g.get("meshes", []):
            for prim in mesh["primitives"]:
                used_accs.update(prim["attributes"].values())
                if "indices" in prim:
                    used_accs.add(prim["indices"])
                for target in prim.get("targets", []):
                    used_accs.update(target.values())
                if "material" in prim:
                    used_mats.add(prim["material"])
        for skin in g.get("skins", []):
            if "inverseBindMatrices" in skin:
                used_accs.add(skin["inverseBindMatrices"])
        for anim in g.get("animations", []):
            for sampler in anim["samplers"]:
                used_accs.update((sampler["input"], sampler["output"]))

        mat_map = _keep(g, "materials", used_mats)
        for mesh in g.get("meshes", []):
            for prim in mesh["primitives"]:
                if "material" in prim:
                    prim["material"] = mat_map[prim["material"]]

        used_texs = {info["index"] for mat in g.get("materials", []) for info in _texture_infos(mat)}
        tex_map = _keep(g, "textures", used_texs)
        for mat in g.get("materials", []):
            for info in _texture_infos(mat):
                info["index"] = tex_map[info["index"]]
        used_imgs = {t["source"] for t in g.get("textures", []) if "source" in t}
        used_samplers = {t["sampler"] for t in g.get("textures", []) if "sampler" in t}
        img_map = _keep(g, "images", used_imgs)
        sampler_map = _keep(g, "samplers", used_samplers)
        for tex in g.get("textures", []):
            if "source" in tex:
                tex["source"] = img_map[tex["source"]]
            if "sampler" in tex:
                tex["sampler"] = sampler_map[tex["sampler"]]

        acc_map = _keep(g, "accessors", used_accs)
        for mesh in g.get("meshes", []):
            for prim in mesh["primitives"]:
                prim["attributes"] = {k: acc_map[v] for k, v in prim["attributes"].items()}
                if "indices" in prim:
                    prim["indices"] = acc_map[prim["indices"]]
                prim["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in prim.get("targets", [])]
                if not prim["targets"]:
                    del prim["targets"]
        for skin in g.get("skins", []):
            if "inverseBindMatrices" in skin:
                skin["inverseBindMatrices"] = acc_map[skin["inverseBindMatrices"]]
        for anim in g.get("animations", []):
            for sampler in anim["samplers"]:
                sampler["input"] = acc_map[sampler["input"]]
                sampler["output"] = acc_map[sampler["output"]]

        out = bytearray()
        views = []
        old_views = {}

        def add_view(data, src=None):
            while len(out) % 4:
                out.append(0)
            view = {"buffer": 0, "byteOffset": len(out), "byteLength": len(data)}
            for key in ("byteStride", "target"):
                if src is not None and key in src:
                    view[key] = src[key]
            out.extend(data)
            views.append(view)
            return len(views) - 1

        for acc in g.get("accessors", []):
            if "_data" in acc:
                data = acc.pop("_data")
                acc["bufferView"] = add_view(data.tobytes())
                acc.pop("byteOffset", None)
                if acc["type"] == "VEC3" and data.dtype == np.float32:
                    acc["min"] = data.min(axis=0).tolist() if len(data) else [0, 0, 0]
                    acc["max"] = data.max(axis=0).tolist() if len(data) else [0, 0, 0]
            elif "bufferView" in acc:
                old = acc["bufferView"]
                if old not in old_views:
                    old_views[old] = add_view(self.view_bytes(old), g["bufferViews"][old])
                acc["bufferView"] = old_views[old]
        for img in g.get("images", []):
            if "_bytes" in img:
                img["bufferView"] = add_view(img.pop("_bytes"))
            elif "bufferView" in img:
                img["bufferView"] = add_view(self.view_bytes(img["bufferView"]))
        while len(out) % 4:
            out.append(0)
        g["bufferViews"] = views
        g["buffers"] = [{"byteLength": len(out)}]

        text = json.dumps(g, separators=(",", ":")).encode()
        text += b" " * (-len(text) % 4)
        total = 12 + 8 + len(text) + 8 + len(out)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total))
            f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
            f.write(struct.pack("<II", len(out), 0x004E4942) + bytes(out))


def _keep(g, key, used):
    """Drop the entries of g[key] not in `used`; returns old index -> new index."""
    items = g.get(key, [])
    mapping, kept = {}, []
    for i, item in enumerate(items):
        if i in used:
            mapping[i] = len(kept)
            kept.append(item)
    if key in g:
        g[key] = kept
    return mapping


def _texture_infos(node, slot=None):
    """Every textureInfo in a material, as the dicts themselves (with their slot name set)."""
    if isinstance(node, dict):
        if slot is not None and slot.endswith("Texture") and "index" in node:
            yield node
            return
        for key, value in node.items():
            yield from _texture_infos(value, key)
    elif isinstance(node, list):
        for value in node:
            yield from _texture_infos(value, slot)


def _texture_slots(mat):
    """(slot name, textureInfo) for every texture the material uses."""
    out = []

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key.endswith("Texture") and isinstance(value, dict) and "index" in value:
                    out.append((key, value))
                else:
                    walk(value)

    walk(mat)
    return out


# --- scene ------------------------------------------------------------------------------


def node_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    t = np.array(node.get("translation", [0, 0, 0]), dtype=np.float64)
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    s = np.array(node.get("scale", [1, 1, 1]), dtype=np.float64)
    r = np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )
    m = np.eye(4)
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m


def mesh_placements(g):
    """mesh index -> list of (node name, world matrix) for each node that draws it."""
    out = {}
    scene = g.get("scenes", [{}])[g.get("scene", 0)] if g.get("scenes") else {"nodes": range(len(g["nodes"]))}

    def visit(index, parent):
        node = g["nodes"][index]
        world = parent @ node_matrix(node)
        if "mesh" in node:
            out.setdefault(node["mesh"], []).append((node.get("name", ""), world))
        for child in node.get("children", []):
            visit(child, world)

    for root in scene["nodes"]:
        visit(root, np.eye(4))
    return out


# --- texture sampling -------------------------------------------------------------------


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def sample_nearest(img, uv):
    """Sample an (h, w, c) float image at glTF UVs (origin top left), wrapping around,
    taking the texel each point falls in. Blending neighbors would mix paint and trim
    along the paint mask's edges."""
    h, w = img.shape[:2]
    x = np.floor(uv[:, 0] * w).astype(np.int64) % w
    y = np.floor(uv[:, 1] * h).astype(np.int64) % h
    return img[y, x]


# --- charts -----------------------------------------------------------------------------


class Part:
    """One primitive to be redone: its faces in car space and their old UVs."""

    def __init__(self, glb, mesh_index, prim_index, world):
        g = glb.json
        prim = g["meshes"][mesh_index]["primitives"][prim_index]
        self.mesh_index, self.prim_index, self.prim = mesh_index, prim_index, prim
        local = glb.floats(prim["attributes"]["POSITION"])
        self.n_verts = len(local)
        if "indices" in prim:
            self.faces = glb.accessor(prim["indices"]).reshape(-1, 3).astype(np.int64)
        else:
            self.faces = np.arange(self.n_verts, dtype=np.int64).reshape(-1, 3)
        self.pos = local @ world[:3, :3].T + world[:3, 3]
        self.uv = glb.floats(prim["attributes"]["TEXCOORD_0"])
        corners = self.pos[self.faces]
        normal = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
        axis = np.argmax(np.abs(normal), axis=1)
        sign = np.where(normal[np.arange(len(axis)), axis] >= 0, 1, -1)
        self.side = list(zip(axis.tolist(), sign.tolist()))
        self.chart = np.full(len(self.faces), -1, dtype=np.int64)
        if "NORMAL" in prim["attributes"]:
            normals = glb.floats(prim["attributes"]["NORMAL"]) @ np.linalg.inv(world[:3, :3])
        else:
            normals = np.zeros_like(self.pos)
            np.add.at(normals, self.faces, normal[:, None, :])
        self.normal = _unit(normals)
        # The old layout's tangent (along +u) and bitangent (along +v) at each vertex,
        # summed over its faces like MikkTSpace's.
        t, b = face_frames(corners, self.uv[self.faces])
        self.tangent = np.zeros_like(self.pos)
        self.bitangent = np.zeros_like(self.pos)
        np.add.at(self.tangent, self.faces, t[:, None, :])
        np.add.at(self.bitangent, self.faces, b[:, None, :])


def _unit(v):
    length = np.linalg.norm(v, axis=-1, keepdims=True)
    return np.divide(v, length, out=np.zeros_like(v), where=length > 1e-12)


def face_frames(corners, uv):
    """Per face, the directions in space of increasing u and increasing v (unit vectors),
    for (faces, 3, 3) corner positions and (faces, 3, 2) corner UVs."""
    e1 = corners[:, 1] - corners[:, 0]
    e2 = corners[:, 2] - corners[:, 0]
    d1 = uv[:, 1] - uv[:, 0]
    d2 = uv[:, 2] - uv[:, 0]
    det = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r = np.divide(1.0, det, out=np.zeros_like(det), where=np.abs(det) > 1e-14)[:, None]
    t = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) * r
    b = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) * r
    return _unit(t), _unit(b)


def orthonormal(n, t, b):
    """Tangent and bitangent made square to the normal n (Gram-Schmidt), b keeping its side."""
    t = _unit(t - n * np.sum(n * t, axis=-1, keepdims=True))
    b = _unit(b - n * np.sum(n * b, axis=-1, keepdims=True) - t * np.sum(t * b, axis=-1, keepdims=True))
    return t, b


def project(points, side, ppm):
    """Car-space points onto a side's flat plane, in texels (x right, y down)."""
    (ua, us), (va, vs) = SIDE_AXES[side]
    return np.stack([points[..., ua] * us * ppm, -points[..., va] * vs * ppm], axis=-1)


def covered_centers(tri):
    """Integer texel cells whose centers lie strictly inside a 2D triangle."""
    x0, y0 = np.floor(tri.min(axis=0)).astype(int)
    x1, y1 = np.ceil(tri.max(axis=0)).astype(int)
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
    px, py = xs.ravel() + 0.5, ys.ravel() + 0.5
    inside = _barycentric_inside(tri, px, py, -1e-6)
    return set(zip(xs.ravel()[inside].tolist(), ys.ravel()[inside].tolist()))


def _barycentric(tri, px, py):
    (ax, ay), (bx, by), (cx, cy) = tri
    denom = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(denom) < 1e-12:
        return None
    w0 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / denom
    w1 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / denom
    return w0, w1, 1.0 - w0 - w1


def _barycentric_inside(tri, px, py, eps):
    w = _barycentric(tri, px, py)
    if w is None:
        return np.zeros(len(px), dtype=bool)
    return (w[0] > -eps) & (w[1] > -eps) & (w[2] > -eps) if eps < 0 else (w[0] >= -eps) & (w[1] >= -eps) & (w[2] >= -eps)


def build_charts(parts, ppm):
    """Group each part's faces into charts: connected faces facing the same side whose
    flat shapes don't overlap. Returns a list of charts, each a list of (part, face)."""
    # Weld corners by position across all parts, so pieces meet across old UV seams and
    # across primitives.
    all_pos = np.concatenate([p.pos for p in parts])
    keys = np.round(all_pos / 1e-5).astype(np.int64)
    _, weld = np.unique(keys, axis=0, return_inverse=True)
    weld = weld.ravel()
    offsets = np.cumsum([0] + [p.n_verts for p in parts])

    face_ref = []
    edges = []
    for pi, part in enumerate(parts):
        w = weld[part.faces + offsets[pi]]
        base = len(face_ref)
        face_ref.extend((pi, f) for f in range(len(part.faces)))
        for a, b in ((0, 1), (1, 2), (2, 0)):
            e = np.sort(np.stack([w[:, a], w[:, b]], axis=1), axis=1)
            edges.append(np.column_stack([e, np.arange(base, base + len(part.faces))]))
    edges = np.concatenate(edges)
    order = np.lexsort((edges[:, 1], edges[:, 0]))
    edges = edges[order]
    same = np.all(edges[1:, :2] == edges[:-1, :2], axis=1)
    neighbors = [[] for _ in face_ref]
    start = 0
    n = len(edges)
    for i in range(1, n + 1):
        if i == n or not same[i - 1]:
            group = edges[start:i, 2]
            if len(group) > 1:
                for a in group:
                    for b in group:
                        if a != b:
                            neighbors[a].append(b)
            start = i

    side_of = [parts[pi].side[f] for pi, f in face_ref]
    flat = [project(parts[pi].pos[parts[pi].faces[f]], side_of[k], ppm) for k, (pi, f) in enumerate(face_ref)]
    chart_of = np.full(len(face_ref), -1, dtype=np.int64)
    charts = []
    for seed in range(len(face_ref)):
        if chart_of[seed] >= 0:
            continue
        cid = len(charts)
        members = [seed]
        chart_of[seed] = cid
        taken = covered_centers(flat[seed])
        queue = deque([seed])
        while queue:
            k = queue.popleft()
            for nb in neighbors[k]:
                if chart_of[nb] >= 0 or side_of[nb] != side_of[seed]:
                    continue
                cells = covered_centers(flat[nb])
                if cells & taken:
                    continue
                taken |= cells
                chart_of[nb] = cid
                members.append(nb)
                queue.append(nb)
        charts.append([face_ref[k] for k in members])
    for k, (pi, f) in enumerate(face_ref):
        parts[pi].chart[f] = chart_of[k]
    return charts, side_of, face_ref


def pack(sizes):
    """Shelf-pack (w, h) boxes, each with GUTTER texels around it. Returns positions and
    the atlas size (width a power of two, height a multiple of four)."""
    padded = [(w + 2 * GUTTER, h + 2 * GUTTER) for w, h in sizes]
    area = sum(w * h for w, h in padded)
    width = 1 << max(5, math.ceil(math.log2(max(max(w for w, _ in padded), math.sqrt(area * 1.15)))))
    order = sorted(range(len(sizes)), key=lambda i: (-padded[i][1], -padded[i][0]))
    pos = [None] * len(sizes)
    x = y = shelf = 0
    for i in order:
        w, h = padded[i]
        if x + w > width:
            x, y, shelf = 0, y + shelf, 0
        pos[i] = (x + GUTTER, y + GUTTER)
        x += w
        shelf = max(shelf, h)
    height = y + shelf
    height += -height % 4
    return pos, (width, height)


# --- the bake ---------------------------------------------------------------------------


class Atlas:
    """One material's new texture layout: every texel's samples and where they came from."""

    def __init__(self, parts, ppm, supersample):
        self.parts = parts
        charts, side_of, face_ref = build_charts(parts, ppm)
        self.n_charts = len(charts)
        # Each chart's box on the texel grid, the grid kept at whole texels in car space.
        corners = {}
        boxes = []
        for chart in charts:
            pts = []
            for pi, f in chart:
                part = parts[pi]
                c = project(part.pos[part.faces[f]], part.side[f], ppm)
                corners[(pi, f)] = c
                pts.append(c)
            pts = np.concatenate(pts)
            lo = np.floor(pts.min(axis=0) - 1e-6)
            hi = np.ceil(pts.max(axis=0) + 1e-6)
            boxes.append((lo, np.maximum(hi - lo, 1).astype(int)))
        positions, (self.width, self.height) = pack([tuple(size) for _, size in boxes])

        # Corner positions in the atlas, in texels.
        self.atlas_corners = {}
        for cid, chart in enumerate(charts):
            lo, _ = boxes[cid]
            shift = np.array(positions[cid], dtype=np.float64) - lo
            for key in chart:
                self.atlas_corners[key] = corners[key] + shift

        # The new vertices: each old one once per chart it sits in, with the new UVs and
        # tangents. The tangents go in the model, so the game reads the new normal map
        # through exactly the frame it was written in.
        for pi, part in enumerate(parts):
            key = part.faces * (self.n_charts + 1) + part.chart[:, None]
            uniq, inverse = np.unique(key.ravel(), return_inverse=True)
            part.new_vertex = uniq // (self.n_charts + 1)
            part.new_faces = inverse.reshape(-1, 3)
            flat = np.stack([self.atlas_corners[(pi, f)] for f in range(len(part.faces))])
            uv = np.zeros((len(uniq), 2))
            uv[inverse] = flat.reshape(-1, 2)
            part.new_uv = (uv / (self.width, self.height)).astype(np.float32)
            t_face, b_face = face_frames(part.pos[part.faces], flat)
            t_sum = np.zeros((len(uniq), 3))
            b_sum = np.zeros((len(uniq), 3))
            np.add.at(t_sum, part.new_faces, t_face[:, None, :])
            np.add.at(b_sum, part.new_faces, b_face[:, None, :])
            n = part.normal[part.new_vertex]
            t, b = orthonormal(n, t_sum, b_sum)
            part.new_w = np.where(np.sum(np.cross(n, t) * b, axis=1) < 0, -1.0, 1.0)
            part.new_tangent = t

        # Rasterize every face at `supersample` points per texel side, keeping only the
        # points a face covers (a point on a shared edge may count for both faces).
        s = supersample
        self.face_keys = list(self.atlas_corners)
        sx, sy, sf, sw = [], [], [], []
        for fid, key in enumerate(self.face_keys):
            tri = self.atlas_corners[key] * s
            x0, y0 = np.floor(tri.min(axis=0)).astype(int)
            x1, y1 = np.ceil(tri.max(axis=0)).astype(int)
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
            w = _barycentric(tri, xs.ravel() + 0.5, ys.ravel() + 0.5)
            if w is None:
                continue
            inside = (w[0] >= -1e-4) & (w[1] >= -1e-4) & (w[2] >= -1e-4)
            sx.append(xs.ravel()[inside])
            sy.append(ys.ravel()[inside])
            sf.append(np.full(int(inside.sum()), fid, dtype=np.int32))
            sw.append(np.stack([w[0][inside], w[1][inside], w[2][inside]], axis=1).astype(np.float32))
        hit_x = np.concatenate(sx)
        hit_y = np.concatenate(sy)
        self.fid = np.concatenate(sf)
        self.bary = np.concatenate(sw).astype(np.float64)
        self.src_uv = self.interpolate(lambda part, f: part.uv[part.faces[f]])
        # The texel each sample belongs to.
        self.texel = np.clip(hit_y // s, 0, self.height - 1) * self.width + np.clip(hit_x // s, 0, self.width - 1)

    def per_face(self, corner_values):
        """Stack a per-face (3, c) array over all faces, by face id."""
        return np.stack([corner_values(self.parts[pi], f) for pi, f in self.face_keys])

    def interpolate(self, corner_values):
        """Each sample's value of a per-vertex quantity, blended by its barycentrics."""
        corners = self.per_face(corner_values)[self.fid]
        return np.einsum("nk,nkc->nc", self.bary, corners)

    def average(self, values, weights=None):
        """Average per texel of per-sample values; returns (texels, channels) and the
        mask of texels that had any sample."""
        n = self.width * self.height
        if weights is None:
            weights = np.ones(len(values))
        sums = np.zeros((n, values.shape[1]))
        counts = np.zeros(n)
        np.add.at(sums, self.texel, values * weights[:, None])
        np.add.at(counts, self.texel, weights)
        filled = counts > 0
        sums[filled] /= counts[filled, None]
        return sums, filled

    def fill_empty(self, texels, filled):
        """Give every texel no face touched the value of the nearest one that was."""
        grid = texels.reshape(self.height, self.width, -1)
        empty = ~filled.reshape(self.height, self.width)
        if empty.all():
            return grid
        _, (iy, ix) = ndimage.distance_transform_edt(empty, return_indices=True)
        return grid[iy, ix]



def load_float_image(glb, image_index, cache):
    if image_index not in cache:
        img = glb.image(image_index).convert("RGBA")
        cache[image_index] = np.asarray(img, dtype=np.float32) / 255.0
    return cache[image_index]


def bake_color(atlas, src, alpha_cutoff, accent):
    """The base color: each texel takes the class (not paint, body paint, accent paint)
    most of its samples have, and the average color of those samples."""
    samples = sample_nearest(src, atlas.src_uv)
    paint = samples[:, 3] >= alpha_cutoff
    cls = paint.astype(np.int64)
    if accent:
        cls[paint & (samples[:, 2] < samples[:, 0] * 0.5)] = 2
    n = atlas.width * atlas.height
    votes = np.zeros((n, 3))
    np.add.at(votes, (atlas.texel, cls), 1)
    winner = np.argmax(votes, axis=1)
    agree = (cls == winner[atlas.texel]).astype(np.float64)
    linear = srgb_to_linear(samples[:, :3].astype(np.float64))
    rgb, filled = atlas.average(linear, agree)
    rgb = linear_to_srgb(rgb)
    return rgb, winner, filled


def bake_plain(atlas, src, srgb):
    samples = sample_nearest(src, atlas.src_uv).astype(np.float64)
    if srgb:
        samples[:, :3] = srgb_to_linear(samples[:, :3])
    values, filled = atlas.average(samples)
    if srgb:
        values[:, :3] = linear_to_srgb(values[:, :3])
    return values, filled


def bake_normal(atlas, src):
    """A tangent-space normal map remade in the new layout: each sample's normal turned
    into car space through the old layout's tangents, then back through the new one's,
    and the result averaged per texel. Green points toward decreasing v (OpenGL style, as
    glTF and Godot read it)."""
    tex = sample_nearest(src, atlas.src_uv)[:, :3].astype(np.float64) * 2.0 - 1.0
    n = _unit(atlas.interpolate(lambda part, f: part.normal[part.faces[f]]))
    t_old, b_old = orthonormal(
        n,
        atlas.interpolate(lambda part, f: part.tangent[part.faces[f]]),
        atlas.interpolate(lambda part, f: part.bitangent[part.faces[f]]),
    )
    detail = _unit(t_old * tex[:, :1] - b_old * tex[:, 1:2] + n * tex[:, 2:3])
    # The new frame as the game will build it: the vertex tangents blended, the
    # bitangent from the normal and tangent.
    t_new = _unit(atlas.interpolate(lambda part, f: part.new_tangent[part.new_faces[f]]))
    w = atlas.per_face(lambda part, f: part.new_w[part.new_faces[f]][:, None])[atlas.fid, 0]
    t_new = _unit(t_new - n * np.sum(n * t_new, axis=1, keepdims=True))
    b_new = np.cross(n, t_new) * w
    encoded = np.stack(
        [np.sum(detail * t_new, axis=1), -np.sum(detail * b_new, axis=1), np.sum(detail * n, axis=1)], axis=1
    )
    values, filled = atlas.average(encoded)
    values = _unit(values)
    values[~filled] = (0.0, 0.0, 1.0)
    return values * 0.5 + 0.5, filled


def make_palette(colors, size):
    """A palette of up to `size` colors for (n, 3) colors in 0..1, by median cut refined
    with k-means."""
    unique = np.unique(np.round(colors * 255).astype(np.uint8), axis=0)
    if len(unique) <= size:
        return unique.astype(np.float64) / 255.0
    strip = Image.fromarray(np.round(colors * 255).astype(np.uint8).reshape(-1, 1, 3), "RGB")
    seed = strip.quantize(colors=size, method=Image.Quantize.MEDIANCUT)
    start = np.array(seed.getpalette()[: size * 3], dtype=np.float64).reshape(-1, 3) / 255.0
    rng = np.random.default_rng(0)
    pick = colors if len(colors) <= 200_000 else colors[rng.choice(len(colors), 200_000, replace=False)]
    centers, _ = kmeans2(pick, start, iter=12, minit="matrix")
    return np.clip(centers, 0, 1)


def nearest(palette, colors):
    _, idx = cKDTree(palette).query(colors)
    return palette[idx]


# --- main -------------------------------------------------------------------------------


def res_path(path):
    return PROJECT / path[len("res://") :] if path.startswith("res://") else Path(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model", nargs="?", help="the .glb to redo (default: the --car file's model)")
    ap.add_argument("-o", "--output", required=True, help="where to write the new .glb")
    ap.add_argument("--car", help="the car's .car file, for its model, dither_cell and accent")
    ap.add_argument("--ppm", type=float, help="texels per meter (default 1/dither_cell, or 25)")
    ap.add_argument("--colors", type=int, default=48, help="palette size for everything but paint (default 48)")
    ap.add_argument("--shades", type=int, default=6, help="how many shades the paint keeps (default 6)")
    ap.add_argument("--supersample", type=int, default=4, help="samples per texel side (default 4)")
    ap.add_argument("--skip", default=",".join(DEFAULT_SKIP), help="name parts to leave alone, comma-separated")
    ap.add_argument("--accent", action=argparse.BooleanOptionalAction, help="keep the accent paint mark")
    ap.add_argument("--atlas-dir", help="also save each new texture as a PNG here")
    args = ap.parse_args()

    car = {}
    if args.car:
        car = json.loads(Path(args.car).read_text()).get("model", {})
    model = args.model or (car.get("path") and str(res_path(car["path"])))
    if not model:
        sys.exit("give a model or a --car file")
    ppm = args.ppm
    if ppm is None:
        cell = float(car.get("dither_cell", 0) or 0)
        ppm = 1.0 / cell if cell > 0 else 25.0
    accent = args.accent if args.accent is not None else "accent" in car
    skip = [s.strip().lower() for s in args.skip.split(",") if s.strip()]

    glb = Glb(model)
    g = glb.json
    placements = mesh_placements(g)

    # Which primitives to redo, grouped by material.
    by_material = {}
    skipped = set()
    for mesh_index, places in placements.items():
        mesh = g["meshes"][mesh_index]
        names = [mesh.get("name", "")] + [name for name, _ in places]
        if len(places) > 1:
            print(f"  mesh {mesh.get('name')!r} is drawn {len(places)} times; laid out for the first", file=sys.stderr)
        for prim_index, prim in enumerate(mesh["primitives"]):
            mat_index = prim.get("material")
            if mat_index is None or prim.get("mode", 4) != 4 or "TEXCOORD_0" not in prim["attributes"]:
                continue
            mat = g["materials"][mat_index]
            label = " ".join(names + [mat.get("name", "")]).lower()
            slots = _texture_slots(mat)
            reason = None
            if any(k in label for k in skip):
                reason = "named in --skip"
            elif mat.get("alphaMode") == "BLEND":
                reason = "see-through"
            elif "baseColorTexture" not in mat.get("pbrMetallicRoughness", {}):
                reason = "no texture"
            elif any(info.get("texCoord", 0) != 0 or "extensions" in info for _, info in slots):
                reason = "textures on a second UV set or transformed"
            if reason:
                skipped.add((mat.get("name"), reason))
                continue
            by_material.setdefault(mat_index, []).append((mesh_index, prim_index, places[0][1]))

    for name, reason in sorted(skipped, key=str):
        print(f"  left alone: {name} ({reason})")
    if not by_material:
        sys.exit("nothing to redo")

    g.setdefault("samplers", []).append(
        {"magFilter": GL_NEAREST, "minFilter": GL_NEAREST_MIPMAP_LINEAR, "wrapS": GL_CLAMP_TO_EDGE, "wrapT": GL_CLAMP_TO_EDGE}
    )
    sampler = len(g["samplers"]) - 1
    float_cache = {}

    # Bake every material first, then choose one palette for the whole car.
    baked = []
    for mat_index, prims in by_material.items():
        mat = g["materials"][mat_index]
        parts = [Part(glb, m, p, world) for m, p, world in prims]
        atlas = Atlas(parts, ppm, args.supersample)
        cutoff = mat.get("alphaCutoff", 0.5)
        color_tex = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
        src = load_float_image(glb, g["textures"][color_tex]["source"], float_cache)
        rgb, cls, filled = bake_color(atlas, src, cutoff, accent)
        others = {}
        for slot, info in _texture_slots(mat):
            if slot == "baseColorTexture" or info["index"] in others:
                continue
            img = load_float_image(glb, g["textures"][info["index"]]["source"], float_cache)
            if slot == "normalTexture" or "Normal" in slot:
                others[info["index"]] = bake_normal(atlas, img)
            else:
                others[info["index"]] = bake_plain(atlas, img, srgb=slot == "emissiveTexture")
        baked.append((mat_index, parts, atlas, rgb, cls, filled, others))
        print(
            f"  {mat.get('name')}: {sum(len(p.faces) for p in parts)} faces in {atlas.n_charts} pieces,"
            f" {atlas.width}x{atlas.height} texels"
        )

    plain = np.concatenate([rgb[f & (c == 0)] for _, _, _, rgb, c, f, _ in baked])
    palette = make_palette(plain, args.colors) if len(plain) else np.zeros((1, 3))
    paint = np.concatenate([rgb[f & (c > 0)] for _, _, _, rgb, c, f, _ in baked])
    if accent and len(paint):
        levels = make_palette(np.repeat(paint[:, :1], 3, axis=1), args.shades)[:, :1]
    elif len(paint):
        shades = make_palette(paint, args.shades)

    for mat_index, parts, atlas, rgb, cls, filled, others in baked:
        out = np.zeros((len(rgb), 4))
        none = filled & (cls == 0)
        out[none, :3] = nearest(palette, rgb[none])
        painted = filled & (cls > 0)
        if accent:
            r = nearest(levels, rgb[painted][:, :1])[:, 0]
            body = cls[painted] == 1
            out[painted, 0] = r
            out[painted, 1] = r
            out[painted, 2] = np.where(body, r, 0.0)
        else:
            out[painted, :3] = nearest(shades, rgb[painted])
        out[painted, 3] = 1.0
        grid = atlas.fill_empty(out, filled)
        image = Image.fromarray(np.round(grid * 255).astype(np.uint8), "RGBA")

        mat = copy.deepcopy(g["materials"][mat_index])
        name = mat.get("name", f"material{mat_index}")
        new_textures = {}

        def new_texture(img, suffix):
            image_index = glb.add_png(img, f"{name}_{suffix}")
            g["textures"].append({"source": image_index, "sampler": sampler})
            if args.atlas_dir:
                Path(args.atlas_dir).mkdir(parents=True, exist_ok=True)
                img.save(Path(args.atlas_dir) / f"{name}_{suffix}.png")
            return len(g["textures"]) - 1

        pbr = mat["pbrMetallicRoughness"]
        pbr["baseColorTexture"] = {"index": new_texture(image, "color")}
        for slot, info in _texture_slots(mat):
            if slot == "baseColorTexture":
                continue
            if info["index"] not in new_textures:
                if info["index"] in others:
                    values, f = others[info["index"]]
                    grid = atlas.fill_empty(values, f)
                    mode = "RGBA" if grid.shape[2] == 4 else "RGB"
                    img = Image.fromarray(np.round(np.clip(grid, 0, 1) * 255).astype(np.uint8), mode)
                    new_textures[info["index"]] = new_texture(img, slot.replace("Texture", ""))
            if info["index"] in new_textures:
                info["index"] = new_textures[info["index"]]
        g["materials"].append(mat)
        new_mat = len(g["materials"]) - 1

        has_normal_map = "normalTexture" in mat
        for part in parts:
            prim = part.prim
            old_vertex, faces = part.new_vertex, part.new_faces
            attrs = {}
            if has_normal_map:
                tangent = np.column_stack([part.new_tangent, part.new_w]).astype(np.float32)
                attrs["TANGENT"] = glb.add_accessor(tangent)
            for attr, acc_index in prim["attributes"].items():
                if attr == "TANGENT":
                    continue
                if attr == "TEXCOORD_0":
                    attrs[attr] = glb.add_accessor(part.new_uv)
                    continue
                values = glb.accessor(acc_index)[old_vertex]
                attrs[attr] = glb.add_accessor(values, g["accessors"][acc_index].get("normalized", False))
            prim["attributes"] = attrs
            if "targets" in prim:
                prim["targets"] = [{k: glb.add_accessor(glb.accessor(v)[old_vertex]) for k, v in t.items()} for t in prim["targets"]]
            dtype = np.uint16 if len(old_vertex) < 65536 else np.uint32
            prim["indices"] = glb.add_accessor(faces.reshape(-1, 1).astype(dtype))
            prim["material"] = new_mat

    glb.save(args.output)
    print(f"wrote {args.output}: {ppm:g} texels per meter, {len(palette)} colors plus paint shades")


if __name__ == "__main__":
    main()
