#!/usr/bin/env python3
"""Simplify the L79 327 small-block STEP assembly into a game engine model.

    python3 tools/l79_to_glb.py extract "L79 assembly v411.step"   # once, about 10 minutes
    python3 tools/l79_to_glb.py build                              # seconds

The STEP (an Autodesk export of a complete 1965 L79: block, heads, valvetrain, crank,
pistons, Holley 4160, generator, exhaust manifolds, every fastener) is 400 MB and about
1,500 solids. `extract` reads it with FreeCAD's command line and meshes every solid
coarsely into a cache (index.json, parts.npz; default ~/.cache/sr3/l79); it is not kept
in the repo. `build` takes only what shows from outside, groups the solids into the
nodes the game uses, thins each node to a triangle budget in Blender, and writes
assets/parts/engine-sbc-l79.glb.

Left out: the rotating assembly, cam, valvetrain, timing chain, bearings and main caps,
oil pump, gaskets and seals, clutch, the distributor's insides, the air cleaner (the game
fits its own), the dipstick, the fuel filter and its lines, and most fasteners.

The STEP is in millimetres with Y up, the crank along Z, the front of the engine toward
+Z and the car's right toward -X. The GLB is in the frame of the other engine models
(engine_assembly.gd): engine units of 0.22 m, +X toward the back, +Y right, +Z up, the
crank at Z -0.36 and the block's middle at X 0. Node names follow engine-v8-*.glb where
there is a match (engine_block, cylinder_head_1, valve_cover_-1, valve_bolt_1,
intake_manifold, carburetor, distributor_body, distributor_cap, crank_pulley,
upper_pulley, water_pump_housing, accessory_bracket, oil_pan, timing_cover), +1 the right
bank and -1 the left; exhaust_manifold_1 and the rest are new. One mesh per node, each in
its finish.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_flathead import (  # noqa: E402
    BLACK, CAST_IRON, PAINT, PORCELAIN, RUBBER, STEEL, ZINC, crease_normals, read_tris)
from make_wheels import write_glb  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEM = "engine-sbc-l79"
CACHE = os.path.expanduser("~/.cache/sr3/l79")
ENGINE_UNIT = 0.22      # metres per engine unit
CRANK_Z = -0.36
STEP_CRANK_Y = -32.54   # the crank's height in the STEP, mm (the balancer's middle)

# freecadcmd script: import the STEP and write every solid's assembly path, bounds and a
# coarse mesh.
FREECAD_EXTRACT = r'''
import json, os, time
import FreeCAD, Import, MeshPart
src, out = os.environ["L79_STEP"], os.environ["L79_CACHE"]
t0 = time.time()
def log(*a):
    print("[%5.0fs]" % (time.time() - t0), *a, flush=True)
log("reading", src)
doc = FreeCAD.newDocument("L79")
Import.insert(src, doc.Name)
log("read", len(doc.Objects), "objects")
def path(o):
    names = [o.Label]
    p = o.getParentGeoFeatureGroup()
    while p is not None:
        names.append(p.Label)
        p = p.getParentGeoFeatureGroup()
    return " / ".join(reversed(names))
def mesh(shape):
    try:
        m = MeshPart.meshFromShape(Shape=shape, LinearDeflection=0.4, AngularDeflection=0.5,
                                   Relative=False)
        pts, facets = m.Topology
        return [(p.x, p.y, p.z) for p in pts], [tuple(f) for f in facets]
    except Exception:
        return [], []
index, meshes = [], {}
for o in doc.Objects:
    if o.TypeId != "Part::Feature" or o.Shape.isNull() or not o.Shape.Faces:
        continue
    sh = o.Shape.copy()
    sh.Placement = o.getGlobalPlacement()
    pts, facets = mesh(sh)
    if not facets:
        # A shape the reader's healing broke (the '65 Nova pan) still has most of its
        # faces: mesh them one at a time and leave out the ones that will not mesh.
        for face in sh.Faces:
            fp, ff = mesh(face)
            b = len(pts)
            pts += fp
            facets += [(i + b, j + b, k + b) for i, j, k in ff]
        if facets:
            log("meshed", path(o), "face by face")
    if not pts:
        continue
    n = len(index)
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    index.append({"id": n, "path": path(o), "bbox": lo + hi})
    meshes[n] = (pts, facets)
    if n % 250 == 0:
        log(n, "solids meshed")
json.dump(index, open(os.path.join(out, "index.json"), "w"))
with open(os.path.join(out, "parts.json"), "w") as f:
    json.dump({str(k): v for k, v in meshes.items()}, f)
log("done", len(index), "solids")
'''

# Solids to nodes, by the lower-cased assembly path: the first pattern that matches
# wins, None leaves the solid out. {s} is the side the solid's middle is on, 1 right.
RULES = [
    (r"lower rotating assembly / sbc harmonic balancer", "harmonic_balancer"),
    (r"lower rotating assembly|upper rotating assembly|lifters|pushrod set|rocker assemblies"
     r"|valve assemblies|head hardware", None),
    (r"main cap|main bearing|main bolts|cam bearing|rear main|gasket|seal|oil pump|chitch assembly"
     r"|clutch", None),
    (r"/ slide |/ rl\d|/ rr\d|/ (b09|l07|r20|t09)$", None),     # timing chain
    (r"block plugs and fittings", None),
    (r"l79 block casting", "engine_block"),
    (r"head casting", "cylinder_head_{s}"),
    (r"spark plugs", "spark_plug_{s}"),
    (r"valve cover assembly.*(bolt|washer)", "valve_bolt_{s}"),
    (r"valve cover assembly", "valve_cover_{s}"),
    (r"intake manifold.*thermostat outlet / (sbc|9\d{4}a|thermostat v)", None),
    (r"intake manifold.*thermostat outlet", "thermostat_housing"),
    (r"l79 oem intake manifold", "intake_manifold"),
    (r"intake bolts", "intake_manifold_bolts"),
    (r"holley 4160", "carburetor"),
    (r"air cleaner", None),                  # the game fits its own air cleaners
    (r"distributor.*vacuum advance can", "distributor_vacuum"),
    (r"distributor.*distributor cap", "distributor_cap"),
    (r"distributor.*(distributor body|distributor hold down)", "distributor_body"),
    (r"distributor", None),
    (r"ignition coil", "ignition_coil"),
    (r"spark plug wire shield|heat shield - spark plug", "plug_wire_shield"),
    (r"generator brace|generator tension bolt", "accessory_bracket"),
    (r"generator", "generator"),
    (r"water pump pulley", "upper_pulley"),
    (r"water pump.*(impeller|shaft seal)", None),
    (r"water pump", "water_pump_housing"),
    (r"crank pulley", "crank_pulley"),
    (r"fan blade", "fan_blades"),
    (r"fan bolt", "fan_hub"),
    (r"main fan belt", "belt"),
    (r"bypass hose", "water_hose"),
    (r"exhaust manifold.*compound", "exhaust_manifold_{s}"),
    (r"exhaust manifold|exhaust donut", None),
    (r"starter.*solenoid", "starter_solenoid"),
    (r"starter", "starter"),
    (r"timing cover bolts", None),
    (r"timing cover", "timing_cover"),
    (r"65 nova ss pan / (pan bolt|end bolt|drain plug)", None),
    (r"65 nova ss pan", "oil_pan"),
    (r"oil filter", "oil_filter"),
    (r"road draft", "road_draft_tube"),
    (r"dipstick|dip stick", None),           # stick and both tubes: too fine to see
    (r"oil fill tube", "oil_filler"),
    (r"/ pcv|pvc bolt", "pcv_valve"),
    (r"motor mount", "engine_mount_{s}"),
    (r"fuel pump rod", None),
    (r"fuel pump|5220k292", "fuel_pump"),
    (r"fuel filter|compound271", None),                # the filter and its lines
    (r"flywheel v6 / flywheel", "flywheel"),
    (r"flywheel", None),
    (r"spring-band clamps|spring clamps|pipe fitting|hex head screw|oil pressure sender|coolant temp", None),
]

# Triangle budgets by node name prefix, first match wins.
BUDGETS = [
    ("engine_block", 12000), ("cylinder_head", 4000), ("valve_cover", 1300), ("valve_bolt", 300),
    ("intake_manifold_bolts", 400), ("intake_manifold", 5000), ("thermostat_housing", 300),
    ("carburetor", 4000), ("distributor_body", 700),
    ("distributor_cap", 1000), ("distributor_vacuum", 300), ("ignition_coil", 500),
    ("plug_wire_shield", 900), ("generator", 2200), ("accessory_bracket", 200),
    ("upper_pulley", 700), ("crank_pulley", 700), ("harmonic_balancer", 900),
    ("fan_blades", 900), ("fan_hub", 200), ("belt", 400), ("water_hose", 150),
    ("water_pump_housing", 1500), ("exhaust_manifold", 2500), ("starter_solenoid", 500),
    ("starter", 1500), ("timing_cover", 800), ("oil_pan", 2500), ("oil_filter", 500),
    ("road_draft_tube", 300), ("oil_filler", 300), ("pcv_valve", 150),
    ("engine_mount", 300), ("fuel_pump", 900),
    ("flywheel", 900), ("spark_plug", 600),
]
# Solids smaller than this across (mm) are left out: screws, clips, springs.
MIN_SIZE = 6.0

CHROME = {"name": "chrome", "pbrMetallicRoughness": {
    "baseColorFactor": [0.9, 0.9, 0.92, 1], "metallicFactor": 1.0, "roughnessFactor": 0.12}}
FINISHES = [
    ("valve_cover", CHROME), ("valve_bolt", STEEL),
    ("intake_manifold_bolts", STEEL), ("carburetor", ZINC), ("distributor_cap", BLACK),
    ("distributor", STEEL), ("ignition_coil", BLACK), ("plug_wire_shield", STEEL),
    ("spark_plug", PORCELAIN), ("exhaust_manifold", CAST_IRON), ("generator", BLACK),
    ("accessory_bracket", BLACK), ("upper_pulley", BLACK), ("crank_pulley", BLACK),
    ("harmonic_balancer", STEEL), ("fan", BLACK), ("belt", RUBBER), ("water_hose", RUBBER),
    ("starter_solenoid", ZINC), ("starter", BLACK), ("oil_filter", PAINT),
    ("road_draft_tube", BLACK), ("oil_filler", CHROME),
    ("pcv_valve", BLACK), ("engine_mount", BLACK),
    ("flywheel", STEEL),
]

# Run inside Blender: weld and flatten each solid, cut away what cannot be seen from
# outside (rays at the whole engine from every side; a face no ray reaches first goes,
# unless it touches one that is reached), then thin each solid to its share of its
# node's budget by the area it shows. Writes "node|solid" objects.
BLENDER_REDUCE = r"""
import bmesh, bpy, json, math, sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree
src, dst, params = sys.argv[sys.argv.index("--") + 1:]
params = json.loads(params)
budgets, spacing = params["budgets"], params["spacing"]
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob)
bpy.ops.wm.obj_import(filepath=src)
obs = [ob for ob in bpy.context.scene.objects if ob.type == "MESH"]
for ob in obs:
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()

# One tree over every face, remembering whose face it is.
verts, polys, owner = [], [], []
for k, ob in enumerate(obs):
    base = len(verts)
    verts += [v.co.copy() for v in ob.data.vertices]
    for p in ob.data.polygons:
        polys.append([base + i for i in p.vertices])
        owner.append((k, p.index))
tree = BVHTree.FromPolygons(verts, polys)
lo = Vector([min(v[i] for v in verts) for i in range(3)])
hi = Vector([max(v[i] for v in verts) for i in range(3)])
mid, radius = (lo + hi) / 2, (hi - lo).length / 2 + 0.01
# Directions: an icosphere's vertices.
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=params["subdivisions"], radius=1.0)
dirs = [v.co.normalized() for v in bm.verts]
bm.free()
seen = set()
n = int(2 * radius / spacing)
for d in dirs:
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(up).normalized()
    w = d.cross(u)
    start = mid - d * (radius + 0.1)
    for i in range(n):
        a = -radius + (i + 0.5) * spacing
        for j in range(n):
            b = -radius + (j + 0.5) * spacing
            hit = tree.ray_cast(start + u * a + w * b, d)
            if hit[2] is not None:
                seen.add(hit[2])
print("visible faces", len(seen), "of", len(polys), flush=True)

keep = {}
for f in seen:
    k, i = owner[f]
    keep.setdefault(k, set()).add(i)
area = {}
for k, ob in enumerate(obs):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    hit = keep.get(k, set())
    # Grow the seen faces by one ring, so thin seen faces between unseen ones stay whole.
    near = set(hit)
    for i in hit:
        for v in bm.faces[i].verts:
            near.update(f.index for f in v.link_faces)
    gone = [f for f in bm.faces if f.index not in near]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    area[ob.name] = sum(f.calc_area() for f in bm.faces)
    bm.to_mesh(ob.data)
    bm.free()

# Each node's budget shared out by area shown; a solid whose share is tiny is dropped.
node_area = {}
for name, a in area.items():
    node_area[name.split("|")[0]] = node_area.get(name.split("|")[0], 0.0) + a
for ob in obs:
    node = ob.name.split("|")[0]
    tris = len(ob.data.polygons)
    share = budgets.get(node, 1000) * area[ob.name] / max(node_area[node], 1e-12)
    if tris == 0 or share < params["min_tris"]:
        bpy.data.objects.remove(ob)
        continue
    if tris > share:
        mod = ob.modifiers.new("reduce", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = share / tris
bpy.ops.wm.obj_export(filepath=dst, apply_modifiers=True, export_normals=False, export_uv=False,
                      export_materials=False, export_triangulated_mesh=True)
"""


def classify(path):
    p = path.lower()
    for pat, node in RULES:
        if re.search(pat, p):
            return node
    return "?"


def lookup(table, name, default):
    return next((v for prefix, v in table if name.startswith(prefix)), default)


def extract(args):
    os.makedirs(args.cache, exist_ok=True)
    freecad = shutil.which(args.freecad) or args.freecad
    with tempfile.TemporaryDirectory() as tmp:
        script = os.path.join(tmp, "extract.py")
        with open(script, "w") as f:
            f.write(FREECAD_EXTRACT)
        env = dict(os.environ, L79_STEP=os.path.abspath(args.step), L79_CACHE=args.cache)
        r = subprocess.run([freecad, script], env=env, cwd=tmp)
    if r.returncode != 0 or not os.path.exists(os.path.join(args.cache, "parts.json")):
        sys.exit("FreeCAD did not finish")
    # The meshes as numpy arrays, one pair per solid.
    meshes = json.load(open(os.path.join(args.cache, "parts.json")))
    np.savez(os.path.join(args.cache, "parts.npz"),
             **{f"p{k}_v": np.array(v, np.float32).reshape(-1, 3) for k, (v, _) in meshes.items()},
             **{f"p{k}_f": np.array(f, np.int32).reshape(-1, 3) for k, (_, f) in meshes.items()})
    os.remove(os.path.join(args.cache, "parts.json"))
    print(f"cache in {args.cache}")


def to_engine(v, z_mid):
    """STEP millimetres to engine units: (x, y, z) -> (back, right, up)."""
    out = np.stack([-(v[:, 2] - z_mid), -v[:, 0], v[:, 1] - STEP_CRANK_Y], axis=1) * 0.001 / ENGINE_UNIT
    out[:, 2] += CRANK_Z
    return out


def build(args):
    index = json.load(open(os.path.join(args.cache, "index.json")))
    data = np.load(os.path.join(args.cache, "parts.npz"))
    nodes, unsorted = {}, []
    for e in index:
        b = e["bbox"]
        node = classify(e["path"])
        if node == "?":
            unsorted.append(e["path"])
        if node is None or node == "?" or f"p{e['id']}_v" not in data:
            continue
        if b[0] > b[3] or np.linalg.norm(np.subtract(b[3:], b[:3])) < MIN_SIZE:
            continue
        side = 1 if (b[0] + b[3]) / 2 < 0 else -1
        nodes.setdefault(node.format(s=side), []).append(e["id"])
    if unsorted:
        print(f"{len(unsorted)} solids match no rule, left out:")
        for p in unsorted:
            print("  " + p)

    # The block's middle front to back, from its own solids.
    block = np.concatenate([data[f"p{i}_v"] for i in nodes["engine_block"]])
    z_mid = (block[:, 2].min() + block[:, 2].max()) / 2

    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "nodes.obj")
        budgets = {}
        with open(src, "w") as f:
            base = 1
            for name, ids in sorted(nodes.items()):
                for i in ids:
                    f.write(f"o {name}|{i}\n")
                    v, t = to_engine(data[f"p{i}_v"], z_mid), data[f"p{i}_f"]
                    f.write("".join(f"v {x:.5f} {y:.5f} {z:.5f}\n" for x, y, z in v))
                    f.write("".join(f"f {a + base} {b + base} {c + base}\n" for a, b, c in t))
                    base += len(v)
                budgets[name] = int(lookup(BUDGETS, name, 500) * args.detail)
        dst = os.path.join(tmp, "thin.obj")
        blender = shutil.which(args.blender) or args.blender
        r = subprocess.run([blender, "-b", "--factory-startup", "--python-expr", BLENDER_REDUCE,
                            "--", src, dst, json.dumps({
                                "budgets": budgets, "spacing": args.spacing, "subdivisions": 2,
                                "min_tris": 12})], capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(dst):
            sys.exit(f"blender: {r.stderr.strip() or r.stdout.strip()}")
        print(next((ln for ln in r.stdout.splitlines() if ln.startswith("visible")), ""))
        bodies = read_tris(dst)

    # The solids back into their nodes.
    merged = {}
    for name, (p, t) in bodies.items():
        node = name.split("|")[0]
        if node in merged:
            mp, mt = merged[node]
            merged[node] = (np.vstack([mp, p]), np.vstack([mt, t + len(mp)]))
        else:
            merged[node] = (p, t)
    parts = []
    for name, (p, t) in sorted(merged.items()):
        p, n, i = crease_normals(p, t)
        parts.append((name, p, n, i, lookup(FINISHES, name, PAINT)))
    glb = os.path.abspath(args.glb or os.path.join(ROOT, "assets", "parts", STEM + ".glb"))
    write_glb(glb, parts)
    allp = np.concatenate([p for _, p, *_ in parts])
    print(f"{os.path.relpath(glb, ROOT)}: {len(parts)} nodes, "
          f"{sum(len(i) for *_, i, _ in parts) // 3} triangles, extent "
          f"{np.round(allp.min(axis=0), 2).tolist()} to {np.round(allp.max(axis=0), 2).tolist()}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="stage", required=True)
    ex = sub.add_parser("extract", help="mesh the STEP into the cache (FreeCAD, slow)")
    ex.add_argument("step", help="the L79 assembly STEP file")
    ex.add_argument("--freecad", default="freecadcmd", help="FreeCAD's command line")
    bu = sub.add_parser("build", help="write the game model from the cache")
    bu.add_argument("--glb", help=f"mesh (default assets/parts/{STEM}.glb)")
    bu.add_argument("--detail", type=float, default=1.0, help="scale every triangle budget")
    bu.add_argument("--spacing", type=float, default=0.012,
                    help="ray spacing for finding hidden faces, engine units (0.012 is 2.6 mm)")
    bu.add_argument("--blender", default="blender", help="Blender, which thins the mesh")
    for p in (ex, bu):
        p.add_argument("--cache", default=CACHE, help=f"mesh cache (default {CACHE})")
    args = ap.parse_args()
    args.cache = os.path.abspath(os.path.expanduser(args.cache))
    extract(args) if args.stage == "extract" else build(args)


if __name__ == "__main__":
    main()
