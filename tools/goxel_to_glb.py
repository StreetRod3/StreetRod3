#!/usr/bin/env python3
"""Convert a Goxel glTF export into a car body GLB for Street Rod 3.

Goxel writes Z-up voxels under a root node that turns them Y-up, with one mesh
per layer and a 64x64 palette texture. The game measures a body by its mesh
bounds and ignores node transforms, so this bakes everything into one Y-up mesh:

  * nose along +Z (Goxel's -Y), the game's car space;
  * centred on X and Z, bottom of the body at Y = 0;
  * scaled so the body is --height meters tall;
  * a fresh palette, 64 px per color, so mipmaps never mix neighboring colors;
  * the --paint color becomes white with alpha 1, every other color alpha 0.
    car_paint_mask.gdshader multiplies alpha-1 texels by the car's paint;
  * a metallic-roughness palette in the same layout (R = AO, G = roughness,
    B = metallic, as the shader reads it). --chrome colors are satin chrome (half metal, very smooth: full metal goes dark on flat voxel faces);
    the rest get the shader's own unpainted values, so they look as before.

usage: goxel_to_glb.py IN.gltf OUT.glb --height 1.46 --paint 85,71,221 --chrome 238,238,238
"""
import argparse
import base64
import io
import json
import math
import struct

import numpy as np
from PIL import Image

CELL = 64
# (AO, roughness, metallic) as 0-255. PLAIN matches the shader's unpainted defaults.
PLAIN = (255, round(0.82 * 255), round(0.05 * 255))
CHROME = (255, round(0.1 * 255), round(0.5 * 255))


def load(path):
    g = json.load(open(path))
    bufs = [base64.b64decode(b["uri"].split(",", 1)[1]) for b in g["buffers"]]

    def acc(i):
        a = g["accessors"][i]
        bv = g["bufferViews"][a["bufferView"]]
        buf = bufs[bv["buffer"]]
        if a["componentType"] == 5125:
            off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
            return np.frombuffer(buf, "<u4", a["count"], off).astype(np.int64)
        n = {"VEC3": 3, "VEC2": 2}[a["type"]]
        stride = bv.get("byteStride", 4 * n) // 4
        flat = np.frombuffer(buf, "<f4", offset=bv.get("byteOffset", 0))
        flat = flat[: (len(flat) // stride) * stride].reshape(-1, stride)
        o = a.get("byteOffset", 0) // 4
        return flat[: a["count"], o : o + n].astype(np.float64)

    pos, nrm, uv, idx = [], [], [], []
    base = 0
    for mesh in g["meshes"]:
        for prim in mesh["primitives"]:
            at = prim["attributes"]
            p = acc(at["POSITION"])
            pos.append(p)
            nrm.append(acc(at["NORMAL"]))
            uv.append(acc(at["TEXCOORD_0"]))
            idx.append(acc(prim["indices"]) + base)
            base += len(p)
    tex = g["textures"][g["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
    img_bytes = bufs[g["bufferViews"][g["images"][tex["source"]]["bufferView"]]["buffer"]]
    img = Image.open(io.BytesIO(img_bytes)).convert("RGBA")
    return np.vstack(pos), np.vstack(nrm), np.vstack(uv), np.concatenate(idx), img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--height", type=float, required=True, help="body height in meters")
    ap.add_argument("--paint", required=True, help="R,G,B of the paintable body color")
    ap.add_argument("--chrome", action="append", default=[], help="R,G,B of a chrome color; repeatable")
    ap.add_argument("--name", default="car")
    args = ap.parse_args()
    paint = tuple(int(c) for c in args.paint.split(","))
    chrome = {tuple(int(c) for c in s.split(",")) for s in args.chrome}

    pos, nrm, uv, idx, img = load(args.src)

    # Palette: one cell per color the mesh samples.
    w, h = img.size
    texel = np.stack([np.clip((uv[:, 0] * w).astype(int), 0, w - 1),
                      np.clip((uv[:, 1] * h).astype(int), 0, h - 1)], 1)
    colors = [img.getpixel((int(x), int(y)))[:3] for x, y in texel]
    palette = sorted(set(colors))
    for c in {paint} | chrome:
        if c not in palette:
            raise SystemExit(f"color {c} is not in the model; colors: {palette}")
    grid = math.ceil(math.sqrt(len(palette)))
    size = grid * CELL
    out_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    orm_img = Image.new("RGB", (size, size), PLAIN)
    cell_of = {}
    for i, c in enumerate(palette):
        cx, cy = i % grid, i // grid
        fill = (255, 255, 255, 255) if c == paint else c + (0,)
        box = (cx * CELL, cy * CELL, cx * CELL + CELL, cy * CELL + CELL)
        out_img.paste(fill, box)
        if c in chrome:
            orm_img.paste(CHROME, box)
        cell_of[c] = ((cx + 0.5) / grid, (cy + 0.5) / grid)
    new_uv = np.array([cell_of[c] for c in colors], np.float32)

    # Goxel Z-up, nose -Y  ->  game Y-up, nose +Z.  (x, y, z) -> (x, z, -y)
    lo, hi = pos.min(0), pos.max(0)
    scale = args.height / (hi[2] - lo[2])
    centre = (lo + hi) / 2
    p = np.stack([pos[:, 0] - centre[0], pos[:, 2] - lo[2], -(pos[:, 1] - centre[1])], 1) * scale
    n = np.stack([nrm[:, 0], nrm[:, 2], -nrm[:, 1]], 1)
    p = p.astype(np.float32)
    n = n.astype(np.float32)
    ind = idx.astype(np.uint32)

    pngs = []
    for im in (out_img, orm_img):
        buf = io.BytesIO()
        im.save(buf, "PNG", optimize=True)
        pngs.append(buf.getvalue())

    blobs = [p.tobytes(), n.tobytes(), new_uv.tobytes(), ind.tobytes()] + pngs
    views, bin_ = [], b""
    for i, blob in enumerate(blobs):
        while len(bin_) % 4:
            bin_ += b"\0"
        view = {"buffer": 0, "byteOffset": len(bin_), "byteLength": len(blob)}
        if i < 3:
            view["target"] = 34962
        elif i == 3:
            view["target"] = 34963
        views.append(view)
        bin_ += blob
    while len(bin_) % 4:
        bin_ += b"\0"

    gltf = {
        "asset": {"version": "2.0", "generator": "StreetRod3 tools/goxel_to_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": args.name, "mesh": 0}],
        "meshes": [{"name": args.name, "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
            "indices": 3, "material": 0}]}],
        "materials": [{
            "name": args.name + "_palette",
            "pbrMetallicRoughness": {"baseColorTexture": {"index": 0},
                                     "metallicRoughnessTexture": {"index": 1},
                                     "metallicFactor": 1.0, "roughnessFactor": 1.0},
            "alphaMode": "OPAQUE"}],
        "textures": [{"source": 0, "sampler": 0}, {"source": 1, "sampler": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9987}],
        "images": [{"bufferView": 4, "mimeType": "image/png"},
                   {"bufferView": 5, "mimeType": "image/png"}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(p), "type": "VEC3",
             "min": p.min(0).tolist(), "max": p.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(n), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(new_uv), "type": "VEC2"},
            {"bufferView": 3, "componentType": 5125, "count": len(ind), "type": "SCALAR"},
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(bin_)
    with open(args.dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(bin_), 0x004E4942) + bin_)
    print(f"{args.dst}: {len(p)} verts, {len(ind) // 3} tris, {len(palette)} colors, "
          f"size {p.max(0) - p.min(0)} m, scale {scale:.6f} m/voxel")


if __name__ == "__main__":
    main()
