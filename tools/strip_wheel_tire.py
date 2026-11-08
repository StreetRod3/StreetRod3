#!/usr/bin/env python3
"""Take the tire out of a wheel GLB and put the wheel at real size.

    python3 tools/strip_wheel_tire.py assets/parts/wheel-premium.glb --tire tire --rim-dia 15

The game draws tires separately (tools/make_tires.py), so a wheel part is the wheel alone.
This keeps the GLB's meshes, materials and textures and edits only its scene: the node
named by --tire, its mesh and its material go, and the wheel's node gets a scale and an
offset so that the wheel is real size in meters (the tire's inner radius, where its beads
sat, becomes the bead seat of a --rim-dia wheel) and centered on its rim along the axle
(X), as make_wheels.py's wheels are. The game's wheels face -X, outboard; with --flip a
wheel that faces +X is turned round. The file is rewritten in place unless --out is given.
"""
import argparse
import json
import struct
import sys

import numpy as np


def read_glb(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    gltf = json.loads(b[20:20 + n])
    off = 20 + n
    bl = struct.unpack("<I", b[off:off + 4])[0]
    return gltf, b[off + 8:off + 8 + bl]


def positions(gltf, bin_, mesh):
    out = []
    for prim in gltf["meshes"][mesh]["primitives"]:
        acc = gltf["accessors"][prim["attributes"]["POSITION"]]
        view = gltf["bufferViews"][acc["bufferView"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", 12)
        raw = np.frombuffer(bin_, dtype=np.uint8, count=stride * acc["count"], offset=start)
        out.append(np.frombuffer(raw.reshape(-1, stride)[:, :12].tobytes(), dtype=np.float32)
                   .reshape(-1, 3))
    return np.concatenate(out)


def write_glb(path, gltf, bin_):
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    bin_ += b"\0" * (-len(bin_) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(bin_), 0x004E4942) + bin_)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("glb")
    ap.add_argument("--tire", required=True, help="name of the tire's node")
    ap.add_argument("--rim-dia", type=float, default=15.0, help="inches (default 15)")
    ap.add_argument("--flip", action="store_true", help="turn a wheel that faces +X round")
    ap.add_argument("--out", help="write here instead of over the input")
    args = ap.parse_args()

    gltf, bin_ = read_glb(args.glb)
    nodes = gltf["nodes"]
    tire = next((i for i, n in enumerate(nodes) if n.get("name") == args.tire), None)
    if tire is None:
        sys.exit(f"no node named {args.tire}")
    if any(k in nodes[tire] for k in ("translation", "rotation", "scale", "matrix", "children")):
        sys.exit("the tire node is transformed or has children; this only handles flat scenes")
    tire_pos = positions(gltf, bin_, nodes[tire]["mesh"])
    bead_r = np.hypot(tire_pos[:, 1], tire_pos[:, 2]).min()
    k = float(args.rim_dia * 0.0254 / 2 / bead_r)

    wheels = [i for i in gltf["scenes"][gltf.get("scene", 0)]["nodes"] if i != tire]
    if any(k_ in nodes[i] for i in wheels for k_ in ("translation", "rotation", "scale", "matrix")):
        sys.exit("a wheel node is already transformed; this only handles flat scenes")
    xs = np.concatenate([positions(gltf, bin_, nodes[i]["mesh"])[:, 0] for i in wheels])
    center = float(xs.min() + xs.max()) / 2

    # Drop the tire's node, and its mesh and material when nothing else uses them.
    tire_mesh = nodes[tire]["mesh"]
    tire_mats = {p.get("material") for p in gltf["meshes"][tire_mesh]["primitives"]}
    del nodes[tire]
    for n in nodes:
        n["children"] = [c - (c > tire) for c in n.get("children", []) if c != tire] or None
        if n["children"] is None:
            del n["children"]
    for s in gltf["scenes"]:
        s["nodes"] = [i - (i > tire) for i in s["nodes"] if i != tire]
    if not any(n.get("mesh") == tire_mesh for n in nodes):
        del gltf["meshes"][tire_mesh]
        for n in nodes:
            if n.get("mesh", -1) > tire_mesh:
                n["mesh"] -= 1
    used = {p.get("material") for m in gltf["meshes"] for p in m["primitives"]}
    for mat in sorted((m for m in tire_mats if m is not None and m not in used), reverse=True):
        del gltf["materials"][mat]
        for m in gltf["meshes"]:
            for p in m["primitives"]:
                if p.get("material", -1) > mat:
                    p["material"] -= 1

    # Scale about the rim's center and, flipped, turn half round about Y (X -> -X).
    sign = -1.0 if args.flip else 1.0
    for i in [i - (i > tire) for i in wheels]:
        nodes[i]["scale"] = [k, k, k]
        nodes[i]["translation"] = [-center * k * sign, 0.0, 0.0]
        if args.flip:
            nodes[i]["rotation"] = [0.0, 1.0, 0.0, 0.0]
    write_glb(args.out or args.glb, gltf, bin_)
    print(f"bead radius {bead_r:.3f} units -> {k:.5f} m per unit; "
          f"{(xs.max() - xs.min()) * k / 0.0254:.2f} in wide")


if __name__ == "__main__":
    main()
