#!/usr/bin/env python3
"""Build a Chevrolet 235 inline six in SolidCraft and export it as a game GLB.

    python3 tools/make_235.py

The engine is the 235 cubic inch "stovebolt" six of the fifties: bore 3 9/16, stroke
3 15/16, the overhead-valve head under a tall ribbed valve cover. Its proportions and
the layout of its accessories were measured from a SketchUp model of one (a reference
only, nothing of its mesh is used): the manifolds and the generator on the left, the
plugs, distributor, coil, fuel pump, oil filler and starter on the right. It has:

  block         one outline across the engine, extruded front to back: the narrow upper
                block under the head, flaring out to the crankcase and the pan rail at the
                crank's height; the side covers over the pushrods on the right, the oil
                gallery rib on the left, the flywheel housing behind
  head          a plain slab on the block, the bolt bosses down its right side between
                the plugs, the water outlet on its front end
  valve cover   the classic stamped one, as on the reference: tall, rounded over every top
                edge and corner, a lip round its foot, round beads stamped in it (two
                along the top and down the ends, a pair across it at each outer band and
                one at the middle), acorn nuts on washers between the outer pairs, the
                hollow filler cap with its ears at the front
  intake        a round log along the left side, turning in to the head at each end;
                the heat riser box under the carburetor
  carburetor    a one-barrel: base, body and the neck up into the air cleaner
  air cleaner   the tall round oil-bath one: pan, body, the screened band, the lid
  exhaust       in two halves, front and back alike: a port off the head at the end
                dropping to a log under the intake, a second port into the log, and the
                log turning down at the middle to an outlet flange each
  front         the timing cover round the crank and the cam gear, the water pump high
                on the front with the fan on its pulley, the generator low on the left,
                and one belt round crank, pump and generator
  right side    the distributor leaning out of the block, its vacuum advance, the coil
                on the head, the fuel pump at the front, the oil filler tube leaning out,
                the dipstick, and the starter at the back with its solenoid on top
  oil pan       shallow at the front, stepping down to the deep sump at the back

Every part is a body of its own, drawn from numbers in this script, so to change the
engine change the numbers and run it again. The helpers are tools/make_flathead.py's.

Writes resources/engines/engine-chevy-235.sc, the SolidCraft design, and
assets/parts/engine-chevy-235.glb. Both are LFS files (.gitattributes). Needs
SolidCraft's command line and Blender, as tools/make_flathead.py does.

The design is in inches across the block's middle: +X toward the back of the car, +Y to
its right, +Z up, the block's middle on X = 0 and Y = 0, the crank at Z = 0. The crank and
the bores sit CRANK_Y toward the manifolds, as in the 1960 shop manual's cross section:
the cam and pushrod side is the wider. The GLB is in the frame of the other engine models
(engine_assembly.gd): engine units of 0.22 m, the crank on its X axis at Z -0.36. The
game does not use it yet.
"""
import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_wheels import SolidCraft, cmd, write_glb  # noqa: E402
from make_flathead import (Design, hull_outline, outline_commands, read_tris,  # noqa: E402
                           BLENDER_REDUCE,
                           crease_normals, skp, inch, pt3, BLACK, STEEL,
                           CAST_IRON, CAST_ALUMINUM, PORCELAIN, RUBBER)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEM = "engine-chevy-235"

BORE = 3.5625
STROKE = 3.9375
BORE_X = [-9.6, -5.76, -1.92, 1.92, 5.76, 9.6]   # 3.84 apart, as the reference's plugs
GAPS_X = [(a + b) / 2 for a, b in zip(BORE_X, BORE_X[1:])]

# What shows on the deck with the head off: the bores, the pistons in them, the head bolt
# holes (after the manual's tightening diagram, two rows and three between the bores on
# the manifold side, a row along the plug side), the pushrod holes and the water holes.
ROD = 6.0               # connecting rod, center to center
DECK_CLEAR = 0.03       # piston crown below the deck at top dead center
CRANK_ANGLE = [0, 120, 240, 240, 120, 0]  # cylinders 1-6, front to back: 1 and 6 at the top
BOLT_D = 0.5
PUSHROD_D = 0.45
WATER_D = 0.3

CRANK_Y = -0.5          # crank and bores, out from the block's middle toward the manifolds

# The block, across (y, z) from the crank: the pan rail at the crank's height, the
# crankcase flaring in to the upper block, and the head on the deck.
BLOCK_HALF = 11.9
RAIL = (4.5, 0.35)      # pan rail lip: half width, thickness
CASE_Y = 4.2            # crankcase sides
CASE_TOP = 4.0          # where the crankcase starts to narrow
UPPER_Y = 3.15          # upper block sides
UPPER_Z = 6.0           # where the upper block starts
DECK = 9.9
HEAD_TOP = 13.0
HEAD_Y = 3.25
HEAD_HALF = 11.95

# The valve cover on the head.
COVER = (11.84, 2.56, 0.85)  # half length, half width, radius of every edge and corner
COVER_Y = 0.51          # its middle, out from the block's toward the plug side
COVER_TOP = 17.56
STRAP_X = (-6.0, 0.0, 6.0)  # the bands of beads across it, the outer two under the acorn nuts
BAND_BEADS_X = (-6.25, -5.75, 0.0, 5.75, 6.25)
SPINE_HALF = 0.88       # the beads along the top, out from its middle
BEAD_R = 0.13
LIP = 0.1               # the lip round the cover's foot, out from its walls
COVER_BASE = HEAD_TOP + 0.15    # top of the lip, the shell's foot
FILLER_X = -8.9

# Left side: the intake log and the exhaust halves.
INTAKE_Y = -6.85
INTAKE_Z = 11.5
INTAKE_D = 1.7
INTAKE_PORT_X = 8.5
EXH_Y = -4.55
EXH_D = 1.6
EXH_TOP = 12.4
EXH_END_X = 10.0
EXH_PORT_X = 3.7
EXH_LOG_Z = 9.0
EXH_INNER_Z = 10.7      # the inner ports, high enough to sit wholly on the head
EXH_OUT_X = 1.75
EXH_FLANGE_Z = 7.2
CARB_X = -1.0
CLEANER = (7.3, 18.9, 23.9)  # diameter, bottom, top

WATER_OUTLET = (-12.5, 12.0)    # the gooseneck's x, the housing's middle z

# The front, from the block's face back: the timing cover, the belt's plane, the fan.
FRONT = -BLOCK_HALF
COVER_FACE = -12.8
BELT_X = -14.15
FAN_X = -15.5
FAN_R = 6.8
PUMP = (0.0, 8.5)
GENERATOR = (-6.8, 2.7)
GENERATOR_R = 2.5
GENERATOR_BACK = -4.9
PULLEYS = [("crank", (CRANK_Y, 0.0), 2.25), ("pump", PUMP, 1.2), ("generator", GENERATOR, 1.0)]

# The right side.
PLUG_Z = 11.4
PLUG_TILT = 25.0        # up from level, leaning out
# The distributor leans 19 degrees out, upright seen from the side; DIST_CAP is the middle
# of its cap, 8.2 up its axis from the shank's foot inside the crankcase.
DIST_AXIS = (0.0, 0.326, 0.946)
DIST_BOSS = (2.4, 4.3)  # its boss on the block, along the axis from the shank's foot
DIST_CAP = (0.0, 5.62, 8.33)
COIL = (3.85, 4.1, 9.68, 13.68, 2.0)    # x, y, bottom, top, diameter
FUEL_PUMP = (-8.9, 5.95)
FILLER_TUBE = ((-5.0, 4.0, 1.5), 20.0, 7.8)   # base, lean out from upright, length
DIPSTICK = (4.4, 4.3, 1.0, 9.0)
STARTER = (6.35, 2.4, 4.5, 5.3, 12.6)   # y, z, diameter, front, back

PAN_WIDTH = 7.2

# The flywheel housing behind the block, round the crank.
FLYWHEEL = (13.8, -0.35, 1.7)   # diameter, center z, depth

PAINT = {"name": "paint", "pbrMetallicRoughness": {
    "baseColorFactor": [0.22, 0.36, 0.48, 1], "metallicFactor": 0.3, "roughnessFactor": 0.55}}
GLASS = {"name": "glass", "pbrMetallicRoughness": {
    "baseColorFactor": [0.55, 0.62, 0.7, 1], "metallicFactor": 0.2, "roughnessFactor": 0.1}}
SCREEN = {"name": "screen", "pbrMetallicRoughness": {
    "baseColorFactor": [0.2, 0.2, 0.21, 1], "metallicFactor": 0.6, "roughnessFactor": 0.6}}
WIRE = {"name": "wire", "pbrMetallicRoughness": {
    "baseColorFactor": [0.06, 0.06, 0.06, 1], "metallicFactor": 0.0, "roughnessFactor": 0.6}}
MACHINED = {"name": "machined iron", "pbrMetallicRoughness": {
    "baseColorFactor": [0.46, 0.46, 0.47, 1], "metallicFactor": 0.7, "roughnessFactor": 0.4}}
FINISHES = [
    ("engine_block_deck_holes", BLACK), ("intake_manifold_carb_bore", BLACK),
    ("carb_throat", BLACK), ("water_outlet_bore", BLACK), ("engine_block_distributor_hole", BLACK), ("cylinder_head_port", BLACK),
    ("flywheel_holes", BLACK), ("flywheel", STEEL), ("engine_block_deck", MACHINED), ("cylinder_bore", MACHINED),
    ("piston", CAST_ALUMINUM),
    ("exhaust", CAST_IRON), ("carburetor_neck", STEEL), ("carburetor", CAST_ALUMINUM),
    ("air_cleaner_screen", SCREEN), ("air_cleaner", BLACK), ("plug_wire", WIRE),
    ("distributor_body", STEEL), ("distributor_shank", STEEL), ("distributor_cap", BLACK),
    ("vacuum_advance", STEEL), ("coil", BLACK), ("fuel_pump_bowl", GLASS),
    ("fuel_pump", CAST_ALUMINUM),
    ("oil_filler_cap", BLACK), ("valve_cover_nut", STEEL), ("valve_cover_washer", STEEL),
    ("dipstick", STEEL), ("spark_plug_base", STEEL), ("spark_plug_tip", STEEL),
    ("spark_plug", PORCELAIN), ("generator", BLACK), ("starter", BLACK),
    ("fan_blades", BLACK), ("fan_hub", BLACK), ("pulley", BLACK), ("belt", RUBBER),
]


def finish_for(name):
    for prefix, mat in FINISHES:
        if name.startswith(prefix):
            return mat
    return PAINT


def unit(v):
    v = np.array(v, float)
    return v / np.linalg.norm(v)


def path_commands(pts, radius):
    """Sketch commands for an open path through pts (sketch coordinates) with every corner
    rounded to radius: (commands, curve ids in order)."""
    pts = [np.array(p, float) for p in pts]
    c, ids = [], []
    start = skp(*pts[0])
    nl = na = 0
    for i in range(1, len(pts) - 1):
        d1, d2 = unit(pts[i] - pts[i - 1]), unit(pts[i + 1] - pts[i])
        turn = math.acos(max(-1.0, min(1.0, float(d1 @ d2))))
        cut = radius * math.tan(turn / 2)
        t1, t2 = pts[i] - d1 * cut, pts[i] + d2 * cut
        nl += 1
        c.append(cmd("sketch.line", infer=False, points=[start, skp(*t1)]))
        ids.append(f"l{nl}")
        left = d1[0] * d2[1] - d1[1] * d2[0] > 0
        n = np.array([-d1[1], d1[0]]) if left else np.array([d1[1], -d1[0]])
        na += 1
        c.append(cmd("sketch.arc.center_point", center=skp(*(t1 + n * radius)), start=f"l{nl}.end",
                     end=skp(*t2), clockwise=not left))
        ids.append(f"a{na}")
        start = f"a{na}.end"
    nl += 1
    c.append(cmd("sketch.line", infer=False, points=[start, skp(*pts[-1])]))
    ids.append(f"l{nl}")
    return c, ids


def pipe(d, name, plane, offset, pts, radius, dia):
    sk = d.sketch(plane, f"{name} path", offset=offset)
    c, ids = path_commands(pts, radius)
    d.c += c
    d.finish()
    d.c.append(cmd("solid.pipe", path_sketch=sk, path=ids, diameter=inch(dia), operation="new",
                   name=name, body_name=name))


def sphere(d, name, center, dia):
    d.c.append(cmd("solid.sphere", center=pt3(center), diameter=inch(dia), operation="new",
                   name=name, body_name=name))


def rod(d, name, base, axis, dia, start, length):
    """A cylinder along axis from start to start + length out of base."""
    a = unit(axis)
    d.cylinder(name, np.array(base, float) + a * start, a, dia, length)


def block(d):
    right = [(RAIL[0], 0.0), (RAIL[0], RAIL[1]), (CASE_Y, RAIL[1]), (CASE_Y, CASE_TOP),
             (UPPER_Y, UPPER_Z), (UPPER_Y, DECK - DECK_SLAB)]
    left = [(-y, z) for y, z in reversed(right)]
    sk = d.sketch("YZ", "Block")
    d.poly(right + left)
    d.finish()
    d.extrude(sk, "engine_block", BLOCK_HALF * 2, "symmetric")

    # Side covers over the pushrods on the right, front and back.
    sk = d.sketch("XZ", "Side covers", offset=UPPER_Y)
    for x0, x1 in ((-11.5, -0.3), (0.3, 11.5)):
        d.c.append(cmd("sketch.rectangle.rounded", p0=skp(x0, -9.7), p1=skp(x1, -6.1),
                       radius=inch(0.5)))
    d.finish()
    d.extrude(sk, "engine_block_side_cover", 0.3)

    # Oil gallery rib along the left of the crankcase.
    d.cylinder("engine_block_rib", (GENERATOR_BACK, -CASE_Y, 2.6), (1, 0, 0), 0.8,
               BLOCK_HALF - GENERATOR_BACK)

    # Flywheel housing behind, with the starter's boss.
    dia, cz, depth = FLYWHEEL
    d.cylinder("engine_block_flywheel_plate", (BLOCK_HALF, CRANK_Y, cz), (1, 0, 0), dia, 0.3)
    sk = d.sketch("YZ", "Flywheel housing", offset=BLOCK_HALF + 0.3)
    for r in (dia / 2, dia / 2 - 0.4):
        d.c.append(cmd("sketch.circle.center", center=skp(CRANK_Y, cz), radius=inch(r)))
    d.finish()
    d.extrude(sk, "engine_block_flywheel_housing", depth - 0.3)
    # The flywheel in it, on the crank, its ring gear round the edge.
    d.cylinder("flywheel", (BLOCK_HALF + 0.45, CRANK_Y, 0.0), (1, 0, 0), 11.6, 0.8)
    d.cylinder("flywheel_ring_gear", (BLOCK_HALF + 0.55, CRANK_Y, 0.0), (1, 0, 0), 12.2, 0.6)
    d.cylinder("flywheel_hub", (BLOCK_HALF + 1.25, CRANK_Y, 0.0), (1, 0, 0), 3.0, 0.25)
    sk = d.sketch("YZ", "Flywheel bolts", offset=BLOCK_HALF + 1.5)
    for k in range(6):
        t = math.radians(60 * k)
        d.c.append(cmd("sketch.polygon.inscribed", center=skp(CRANK_Y + 1.05 * math.cos(t), 1.05 * math.sin(t)),
                       radius=0.26 * 25.4, sides=6))
    d.finish()
    d.extrude(sk, "flywheel_bolts", 0.22)
    sk = d.sketch("YZ", "Flywheel housing flange", offset=BLOCK_HALF + depth)
    for r in (dia / 2 + 0.4, dia / 2 - 0.4):
        d.c.append(cmd("sketch.circle.center", center=skp(CRANK_Y, cz), radius=inch(r)))
    d.finish()
    d.extrude(sk, "engine_block_flywheel_flange", 0.3)
    sy, sz, sd, _, _ = STARTER
    d.cylinder("engine_block_starter_boss", (BLOCK_HALF, sy, sz), (1, 0, 0), sd * 0.75, depth)


def piston_depth(angle):
    """How far the crown is below the deck with the crank at angle from top dead center."""
    r, t = STROKE / 2, math.radians(angle)
    return DECK_CLEAR + r * (1 - math.cos(t)) + ROD - math.sqrt(ROD ** 2 - (r * math.sin(t)) ** 2)


def deck_holes():
    """The deck's small holes: [(x, y, diameter)] for bolts, pushrods and water."""
    holes = []
    holes += [(x, -2.35, BOLT_D) for x in [-11.1] + GAPS_X + [11.3]]        # manifold side
    holes += [(x, CRANK_Y - 0.85, BOLT_D) for x in GAPS_X[1::2]]             # between bores
    holes += [(x, 2.9, BOLT_D) for x in [-11.2] + GAPS_X + [11.2]]           # plug side
    holes += [(x + dx, 1.9, PUSHROD_D) for x in BORE_X for dx in (-0.7, 0.7)]
    holes += [(x, 1.45, WATER_D) for x in GAPS_X[1::2]]
    holes += [(x, -2.65, WATER_D) for x in BORE_X]
    return holes


BORE_SIDES = 36         # the bores' and pistons' facets
HOLE_SIDES = 8          # the small holes' facets
DECK_SLAB = 0.12        # the machined deck: the block's top this thick, bare iron, as thin as a gasket from outside
HOLE_DEPTH = 0.1        # small holes, down into the deck to their dark floors


def deck(d):
    """The machined slab on top of the block, the bores cut down through it and the block,
    and the small holes cut into it. The bores' walls, the pistons and the holes' floors
    are drawn as meshes of their own (deck_meshes), exact and with few facets."""
    sk = d.sketch("XY", "Deck", offset=DECK - DECK_SLAB)
    d.c.append(cmd("sketch.rectangle.two_point", p0=skp(-BLOCK_HALF, -UPPER_Y), p1=skp(BLOCK_HALF, UPPER_Y)))
    d.finish()
    d.extrude(sk, "engine_block_deck", DECK_SLAB)
    sk = d.sketch("XY", "Bores", offset=DECK)
    for x in BORE_X:
        d.c.append(cmd("sketch.polygon.inscribed", center=skp(x, CRANK_Y),
                       radius=round(BORE / 2 * 25.4, 4), sides=BORE_SIDES))
    d.finish()
    d.c.append(cmd("solid.extrude", sketch=sk, distance=inch(bore_cut()), direction="negative",
                   operation="cut", targets=["engine_block", "engine_block_deck"], name="Bores cut"))
    sk = d.sketch("XY", "Deck holes", offset=DECK)
    for x, y, dia in deck_holes():
        d.c.append(cmd("sketch.polygon.inscribed", center=skp(x, y), radius=round(dia / 2 * 25.4, 4),
                       sides=HOLE_SIDES))
    d.finish()
    d.c.append(cmd("solid.extrude", sketch=sk, distance=inch(HOLE_DEPTH), direction="negative",
                   operation="cut", targets=["engine_block_deck"], name="Holes cut"))


def bore_cut():
    return max(piston_depth(a) for a in CRANK_ANGLE) + 1.0


def ring(n, r, phase=0.0):
    t = np.linspace(0, 2 * math.pi, n, endpoint=False) + phase
    return np.stack([np.cos(t) * r, np.sin(t) * r], axis=1)


def disc(cx, cy, z, r, n, up=True):
    """A flat n-gon facing up (or down): positions, normals, indices, in inches."""
    rim = ring(n, r) + [cx, cy]
    p = np.vstack([[cx, cy, z]] + [[x, y, z] for x, y in rim])
    nrm = np.tile([0.0, 0.0, 1.0 if up else -1.0], (n + 1, 1))
    i = [[0, 1 + k, 1 + (k + 1) % n] if up else [0, 1 + (k + 1) % n, 1 + k] for k in range(n)]
    return p, nrm, np.array(i, dtype=np.uint32).ravel()


def wall(cx, cy, z0, z1, r, n, inward):
    """The side of an n-gon prism, its faces flat, facing in (a bore) or out (a piston)."""
    rim = ring(n, r)
    p, nrm, idx = [], [], []
    for k in range(n):
        a, b = rim[k], rim[(k + 1) % n]
        mid = (a + b) / 2
        out = mid / np.linalg.norm(mid) * (-1 if inward else 1)
        base = len(p)
        for (x, y), z in ((a, z0), (b, z0), (b, z1), (a, z1)):
            p.append([cx + x, cy + y, z])
            nrm.append([out[0], out[1], 0.0])
        idx += ([base, base + 2, base + 1, base, base + 3, base + 2] if inward else
                [base, base + 1, base + 2, base, base + 2, base + 3])
    return np.array(p), np.array(nrm), np.array(idx, dtype=np.uint32)


def merge(pieces):
    ps, ns, ix, off = [], [], [], 0
    for p, n, i in pieces:
        ps.append(p)
        ns.append(n)
        ix.append(i + off)
        off += len(p)
    return np.vstack(ps), np.vstack(ns), np.concatenate(ix)


def disc_facing(center, normal, r, n):
    """A flat n-gon round center, facing along normal: positions, normals, indices."""
    nrm = unit(normal)
    e1 = unit(np.cross(nrm, [0.0, 0.0, 1.0]) if abs(nrm[2]) < 0.9 else np.cross(nrm, [1.0, 0.0, 0.0]))
    e2 = np.cross(nrm, e1)
    rim = [np.array(center) + r * (math.cos(t) * e1 + math.sin(t) * e2)
           for t in np.linspace(0, 2 * math.pi, n, endpoint=False)]
    p = np.vstack([center] + rim)
    i = [[0, 1 + k, 1 + (k + 1) % n] for k in range(n)]
    return p, np.tile(nrm, (n + 1, 1)), np.array(i, dtype=np.uint32).ravel()


def openings():
    """{name: mesh} for what shows where a part comes off: the head's ports under the
    manifolds, the carburetor's bore in the intake's pad, the throat under the air
    cleaner, and the distributor's hole in its boss."""
    left = (0.0, -1.0, 0.0)
    face = -HEAD_Y - 0.004
    ports = [disc_facing((k * INTAKE_PORT_X, face, INTAKE_Z), left, 0.6, 12) for k in (-1, 1)]
    exhaust = [disc_facing((k * EXH_END_X, face, EXH_TOP - 0.5), left, 0.6, 12) for k in (-1, 1)]
    exhaust += [disc_facing((k * EXH_PORT_X, face, EXH_INNER_Z), left, 0.6, 12) for k in (-1, 1)]
    a = unit(DIST_AXIS)
    return {
        "cylinder_head_ports": merge(ports + exhaust),
        "intake_manifold_carb_bore": disc_facing((CARB_X, INTAKE_Y, INTAKE_Z + 0.904), (0, 0, 1), 0.65, 16),
        "water_outlet_bore": disc_facing((WATER_OUTLET[0] - 1.404, 0.0, WATER_OUTLET[1] + 0.9), (-1, 0, 0),
                                         0.5, 12),
        "carb_throat": disc_facing((CARB_X, INTAKE_Y, CLEANER[1] + 0.004), (0, 0, 1), 0.85, 16),
        "engine_block_distributor_hole": disc_facing(dist_base() + a * (DIST_BOSS[1] + 0.004), a, 0.55, 12),
        # The clutch's bolt holes round the flywheel's face.
        "flywheel_holes": merge([disc_facing((BLOCK_HALF + 1.254, CRANK_Y + 5.0 * math.cos(t), 5.0 * math.sin(t)),
                                             (1, 0, 0), 0.2, 8)
                                 for t in np.radians(np.arange(30, 360, 60))]),
    }


def deck_meshes():
    """{name: (positions, normals, indices)} in inches: the bores' machined walls just inside
    the cut, a piston down each, and a dark floor in each small hole."""
    apothem = BORE / 2 * math.cos(math.pi / BORE_SIDES)
    cut = bore_cut()
    out = {"cylinder_bores": merge([wall(x, CRANK_Y, DECK - cut, DECK, apothem - 0.004, BORE_SIDES, True)
                                    for x in BORE_X])}
    for i, (x, a) in enumerate(zip(BORE_X, CRANK_ANGLE)):
        top = DECK - piston_depth(a)
        r = apothem - 0.03
        out[f"piston_{i + 1}"] = merge([disc(x, CRANK_Y, top, r, BORE_SIDES),
                                        wall(x, CRANK_Y, top - 1.0, top, r, BORE_SIDES, False)])
    floors = []
    for x, y, dia in deck_holes():
        r = dia / 2 * math.cos(math.pi / HOLE_SIDES)
        floors.append(disc(x, y, DECK - HOLE_DEPTH + 0.003, r, HOLE_SIDES))
    out["engine_block_deck_holes"] = merge(floors)
    out.update(openings())
    out.update(cover_meshes())
    out.update(water_outlet_meshes())
    return out


# Bodies left exact, not thinned: flat-faced, and their holes must stay round.
KEEP_EXACT = ("engine_block", "engine_block_deck")


def reduce_exact(src, dst, blender):
    """tools/make_flathead.py's thinning, leaving KEEP_EXACT's bodies as they are."""
    script = BLENDER_REDUCE.replace("import bmesh, bpy, math, sys", "import bmesh, bpy, math, re, sys")
    script = script.replace("    if tris > budget * 1.5:",
                            "    if tris > budget * 1.5 and re.sub(r'[ _]\\(\\d+\\)$', '', ob.name) "
                            f"not in {KEEP_EXACT!r}:")
    assert script.count("re.sub") == 1 and "math, re, sys" in script
    r = subprocess.run([blender, "-b", "--factory-startup", "--python-expr", script, "--", src, dst],
                       capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(dst):
        sys.exit(f"blender: {r.stderr.strip() or r.stdout.strip()}")


def head(d):
    sk = d.sketch("YZ", "Head")
    d.poly([(HEAD_Y, DECK), (HEAD_Y, HEAD_TOP), (-HEAD_Y, HEAD_TOP), (-HEAD_Y, DECK)])
    d.finish()
    d.extrude(sk, "cylinder_head", HEAD_HALF * 2, "symmetric")

    # Bolt bosses down the right side, between the plugs and at the ends.
    xs = [-11.2] + GAPS_X + [11.2]
    sk = d.sketch("XY", "Head bosses", offset=DECK + 0.1)
    for x in xs:
        d.c.append(cmd("sketch.circle.center", center=skp(x, HEAD_Y), radius=inch(0.4)))
    d.finish()
    d.extrude(sk, "cylinder_head_bosses", HEAD_TOP - DECK - 0.2)

    # Spark plugs out of the right side, leaning up.
    t = math.radians(PLUG_TILT)
    a = (0.0, math.cos(t), math.sin(t))
    for i, x in enumerate(BORE_X):
        base = (x, HEAD_Y, PLUG_Z)
        rod(d, f"spark_plug_base_{i}", base, a, 0.85, -0.1, 0.45)
        rod(d, f"spark_plug_{i}", base, a, 0.55, 0.35, 1.2)
        rod(d, f"spark_plug_tip_{i}", base, a, 0.25, 1.55, 0.35)

    # Thermostat housing on the front end: round, on the head's face, with a gooseneck
    # rising out of it and turning forward to the hose (an XZ path: (x, -z)).
    # Drawn as exact meshes: water_outlet_meshes.


def valve_cover(d):
    """The cover's lip, its acorn nuts and its filler cap; its stamped shell and beads are
    drawn as exact meshes (cover_meshes)."""
    hl, hw, r = COVER
    sk = d.sketch("XY", "Valve cover lip", offset=HEAD_TOP)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(-hl - LIP, COVER_Y - hw - LIP),
                   p1=skp(hl + LIP, COVER_Y + hw + LIP), radius=inch(r + LIP)))
    d.finish()
    d.extrude(sk, "valve_cover_lip", COVER_BASE - HEAD_TOP)

    # Acorn nuts on washers, sitting on the outer bands' pairs of beads.
    seat = COVER_TOP + BEAD_R
    for i, x in enumerate((STRAP_X[0], STRAP_X[-1])):
        d.cylinder(f"valve_cover_washer_{i}", (x, COVER_Y, seat), (0, 0, 1), 0.6, 0.04)
        sk = d.sketch("XY", f"Cover nut {i}", offset=seat + 0.04)
        d.c.append(cmd("sketch.polygon.inscribed", center=skp(x, COVER_Y), radius=0.25 * 25.4, sides=6))
        d.finish()
        d.extrude(sk, f"valve_cover_nut_{i}", 0.25)
        sphere(d, f"valve_cover_nut_dome_{i}", (x, COVER_Y, seat + 0.29), 0.42)

    # The filler cap at the front: a neck, a hollow ring with its floor down inside, and
    # two little ears to turn it by.
    fx, z = FILLER_X, COVER_TOP - 0.06
    d.cylinder("valve_cover_filler", (fx, COVER_Y, z), (0, 0, 1), 1.5, 0.25)
    d.cylinder("valve_cover_filler_cap_floor", (fx, COVER_Y, z + 0.25), (0, 0, 1), 1.5, 0.13)
    for k in (-1, 1):
        d.cylinder(f"valve_cover_filler_cap_ear_{k}", (fx + k * 1.16, COVER_Y, z + 0.25), (0, 0, 1), 0.56, 0.22)
        d.box(f"valve_cover_filler_cap_lug_{k}", (fx + k * 0.8 - 0.25, COVER_Y - 0.2, z + 0.25),
              (fx + k * 0.8 + 0.25, COVER_Y + 0.2, z + 0.38))


def arc_points(c, r, a0, a1, n):
    return [(c[0] + r * math.cos(t), c[1] + r * math.sin(t))
            for t in np.linspace(math.radians(a0), math.radians(a1), n + 1)]


def cover_section(n=8):
    """The cover's cross-section (y, z), left foot up over the top to the right foot."""
    hl, hw, r = COVER
    cz = COVER_TOP - r
    y0, y1 = COVER_Y - hw + r, COVER_Y + hw - r
    return ([(COVER_Y - hw, COVER_BASE)] + arc_points((y0, cz), r, 180, 90, n)
            + arc_points((y1, cz), r, 90, 0, n) + [(COVER_Y + hw, COVER_BASE)])


def cover_length_section(n=8):
    """The cover along its length (x, z) where it is not rounded across: down the front
    end, over the top, down the back end."""
    hl, hw, r = COVER
    cz = COVER_TOP - r
    return ([(-hl, COVER_BASE)] + arc_points((-hl + r, cz), r, 180, 90, n)
            + arc_points((hl - r, cz), r, 90, 0, n) + [(hl, COVER_BASE)])


def annulus(cx, cy, z, r0, r1, n):
    """A flat ring facing up between radii r0 and r1."""
    inner, outer = ring(n, r0) + [cx, cy], ring(n, r1) + [cx, cy]
    p = np.array([[x, y, z] for x, y in inner] + [[x, y, z] for x, y in outer])
    tris = []
    for k in range(n):
        k2 = (k + 1) % n
        tris += [[k, n + k, n + k2], [k, n + k2, k2]]
    return orient(p, np.tile([0.0, 0.0, 1.0], (2 * n, 1)), tris)


def tube(path, normal, radius, sides=8):
    """A round bead along a path in a plane (normal), its middle on the path: positions,
    normals, indices."""
    path = np.array(path, float)
    b = unit(normal)
    p, nrm = [], []
    for k in range(len(path)):
        t = unit(path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)])
        n = np.cross(b, t)
        for j in range(sides):
            a = 2 * math.pi * j / sides
            d = math.cos(a) * n + math.sin(a) * b
            p.append(path[k] + radius * d)
            nrm.append(d)
    tris = []
    for k in range(len(path) - 1):
        for j in range(sides):
            a, c = k * sides + j, k * sides + (j + 1) % sides
            tris += [[a, c, c + sides], [a, c + sides, a + sides]]
    return orient(np.array(p), np.array(nrm), tris)


def cover_shell(seg=8):
    """The stamped shell: a box with every top edge and corner rounded to COVER's radius,
    the corners up its sides too, its walls down to the lip. Columns run round the plan, a
    quarter turn to each corner; rows from the foot up to the top."""
    hl, hw, r = COVER
    cx, cy, cz = hl - r, hw - r, COVER_TOP - r
    cols = []
    for q, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        for k in range(seg + 1):
            cols.append((math.radians(90 * q + 90 * k / seg), sx, sy))
    rows = [None] + [math.radians(90 * k / seg) for k in range(seg + 1)]
    p, nrm = [], []
    for t, sx, sy in cols:
        for f in rows:
            if f is None:
                p.append([sx * cx + r * math.cos(t), COVER_Y + sy * cy + r * math.sin(t), COVER_BASE])
                nrm.append([math.cos(t), math.sin(t), 0.0])
            else:
                n = [math.cos(f) * math.cos(t), math.cos(f) * math.sin(t), math.sin(f)]
                p.append([sx * cx + r * n[0], COVER_Y + sy * cy + r * n[1], cz + r * n[2]])
                nrm.append(n)
    nr, nc = len(rows), len(cols)
    tris = []
    for c in range(nc):
        c2 = (c + 1) % nc
        for k in range(nr - 1):
            a, b, e, f = c * nr + k, c2 * nr + k, c2 * nr + k + 1, c * nr + k + 1
            tris += [[a, b, e], [a, e, f]]
    tops = [q * (seg + 1) * nr + nr - 1 for q in range(4)]
    tris += [[tops[0], tops[1], tops[2]], [tops[0], tops[2], tops[3]]]
    return orient(np.array(p), np.array(nrm), tris)


def orient(p, nrm, tris):
    """Drop degenerate triangles and turn each to face along its corners' normals."""
    out = []
    for t in tris:
        a, b, c = p[t[0]], p[t[1]], p[t[2]]
        fn = np.cross(b - a, c - a)
        if np.linalg.norm(fn) < 1e-9:
            continue
        out.append(t if fn @ (nrm[t[0]] + nrm[t[1]] + nrm[t[2]]) >= 0 else [t[0], t[2], t[1]])
    return p, nrm, np.array(out, dtype=np.uint32).ravel()


def cylinder_mesh(base, axis, r, length, n=24):
    """A round bar from base along axis, its far end capped."""
    a = unit(axis)
    e1 = unit(np.cross(a, [0.0, 0.0, 1.0]) if abs(a[2]) < 0.9 else np.cross(a, [1.0, 0.0, 0.0]))
    e2 = np.cross(a, e1)
    base = np.array(base, float)
    p, nrm, tris = [], [], []
    for j in range(n):
        t = 2 * math.pi * j / n
        d = math.cos(t) * e1 + math.sin(t) * e2
        p += [base + r * d, base + a * length + r * d]
        nrm += [d, d]
    for j in range(n):
        k, k2 = 2 * j, 2 * ((j + 1) % n)
        tris += [[k, k2, k2 + 1], [k, k2 + 1, k + 1]]
    side = orient(np.array(p), np.array(nrm), tris)
    return merge([side, disc_facing(base + a * length, a, r, n)])


def water_outlet_meshes():
    """The thermostat housing, round on the head's front, and its gooseneck rising out of
    it and turning forward to the hose."""
    hx, hz = WATER_OUTLET
    path = ([(hx, 0.0, hz - 0.4)] + [(hx - 0.6 + 0.6 * math.cos(t), 0.0, hz + 0.3 + 0.6 * math.sin(t))
                                      for t in np.linspace(0, math.pi / 2, 9)] + [(hx - 1.4, 0.0, hz + 0.9)])
    return {
        "water_outlet": cylinder_mesh((-HEAD_HALF + 0.05, 0.0, hz), (-1, 0, 0), 0.95, 0.75),
        "water_outlet_neck": tube(path, (0, 1, 0), 0.65, 16),
    }


def cover_meshes():
    """{name: mesh} in inches: the cover's shell and its stamped beads, as on the
    reference: two along the top either side of the middle, over the end shoulders and down
    the ends to the lip, and across it a pair at each outer band and one at the middle,
    over the top and down both sides."""
    across = [[(x, y, z) for y, z in cover_section()] for x in BAND_BEADS_X]
    along = [[(x, COVER_Y + s * SPINE_HALF, z) for x, z in cover_length_section()] for s in (-1, 1)]
    fx, z = FILLER_X, COVER_TOP + 0.19
    cap = [wall(fx, COVER_Y, z, z + 0.38, 0.94, 32, False), wall(fx, COVER_Y, z, z + 0.38, 0.75, 32, True),
           annulus(fx, COVER_Y, z + 0.38, 0.75, 0.94, 32)]
    return {
        "valve_cover_filler_cap": merge(cap),
        "valve_cover": cover_shell(),
        "valve_cover_beads": merge([tube(pth, (1, 0, 0), BEAD_R) for pth in across]
                                   + [tube(pth, (0, 1, 0), BEAD_R) for pth in along]),
    }


def intake(d):
    # The log along the left, turning in to the head at each end (an XY path at its height).
    p = INTAKE_PORT_X
    pipe(d, "intake_manifold", "XY", INTAKE_Z,
         [(-p, -HEAD_Y + 0.3), (-p, INTAKE_Y), (p, INTAKE_Y), (p, -HEAD_Y + 0.3)], 1.6, INTAKE_D)
    # Port flanges on the head.
    for i, x in enumerate((-p, p)):
        d.cylinder(f"intake_manifold_flange_{i}", (x, -HEAD_Y, INTAKE_Z), (0, -1, 0), 2.2, 0.3)
    # Heat riser box under the carburetor, against the log.
    d.box("intake_manifold_riser", (CARB_X - 1.9, INTAKE_Y - 1.05, 9.6),
          (CARB_X + 1.9, INTAKE_Y + 0.85, INTAKE_Z + 0.9))


def carburetor(d):
    z = INTAKE_Z + 0.9
    d.box("carburetor_base", (CARB_X - 1.6, INTAKE_Y - 1.5, z), (CARB_X + 1.6, INTAKE_Y + 1.5, z + 0.3))
    sk = d.sketch("XY", "Carburetor", offset=z + 0.3)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(CARB_X - 1.4, INTAKE_Y - 1.5),
                   p1=skp(CARB_X + 1.4, INTAKE_Y + 1.5), radius=inch(0.5)))
    d.finish()
    d.extrude(sk, "carburetor", 2.5)
    top = z + 2.8
    d.cylinder("carburetor_neck", (CARB_X, INTAKE_Y, top), (0, 0, 1), 2.4, CLEANER[1] - top)


def air_cleaner(d):
    dia, z0, z1 = CLEANER
    c = (CARB_X, INTAKE_Y)
    d.cylinder("air_cleaner_pan", (*c, z0), (0, 0, 1), dia - 0.8, 0.5)
    d.cylinder("air_cleaner", (*c, z0 + 0.5), (0, 0, 1), dia, 2.4)
    d.cylinder("air_cleaner_screen", (*c, z0 + 2.9), (0, 0, 1), dia - 0.3, 0.8)
    d.cylinder("air_cleaner_lid", (*c, z0 + 3.7), (0, 0, 1), dia + 0.1, 0.6)
    d.c.append(cmd("solid.cone", base=pt3((*c, z0 + 4.3)), axis="Z", radius=inch(dia / 2 - 0.2),
                   top_radius=inch(1.8), height=inch(z1 - z0 - 4.3), operation="new",
                   name="air_cleaner_top", body_name="air_cleaner_top"))


def exhaust(d):
    for k, half in ((-1, "front"), (1, "back")):
        name = f"exhaust_collector_{half}"
        # XZ sketch: (x, -z), the plane moved along +y.
        pts = [(k * EXH_END_X, -EXH_TOP), (k * EXH_END_X, -EXH_LOG_Z), (k * EXH_OUT_X, -EXH_LOG_Z),
               (k * EXH_OUT_X, -(EXH_FLANGE_Z + 0.25))]
        pipe(d, name, "XZ", EXH_Y, pts, 0.9, EXH_D)
        sphere(d, f"exhaust_end_{half}", (k * EXH_END_X, EXH_Y, EXH_TOP), EXH_D)
        # Ports off the head: one into the top of the end, one into the log.
        d.cylinder(f"exhaust_port_{half}", (k * EXH_END_X, -HEAD_Y, EXH_TOP - 0.5), (0, -1, 0),
                   1.4, HEAD_Y - (-EXH_Y))
        d.cylinder(f"exhaust_port_stub_{half}", (k * EXH_PORT_X, EXH_Y, EXH_LOG_Z), (0, 0, 1), 1.4,
                   EXH_INNER_Z - EXH_LOG_Z)
        d.cylinder(f"exhaust_port_inner_{half}", (k * EXH_PORT_X, -HEAD_Y, EXH_INNER_Z),
                   (0, -1, 0), 1.4, HEAD_Y - (-EXH_Y))
        sphere(d, f"exhaust_port_bend_{half}", (k * EXH_PORT_X, EXH_Y, EXH_INNER_Z), 1.4)
        d.box(f"exhaust_flange_{half}", (k * EXH_OUT_X - 1.3, EXH_Y - 0.95, EXH_FLANGE_Z),
              (k * EXH_OUT_X + 1.3, EXH_Y + 0.95, EXH_FLANGE_Z + 0.25))


def front(d):
    # Timing cover round the crank and up round the cam gear on the right.
    sk = d.sketch("YZ", "Timing cover", offset=FRONT)
    d.c += outline_commands(*hull_outline([((CRANK_Y + 0.7, 0.5), 2.0), ((2.6, 2.6), 2.6)]))
    d.finish()
    d.extrude(sk, "timing_cover", FRONT - COVER_FACE, "negative")

    # Water pump high on the front, the fan on its pulley.
    py, pz = PUMP
    d.cylinder("water_pump_housing", (FRONT, py, pz), (-1, 0, 0), 3.6, 1.0)
    d.cylinder("water_pump_snout", (FRONT - 1.0, py, pz), (-1, 0, 0), 1.4, BELT_X - 0.35 - FRONT + 1.0)
    d.cylinder("fan_shaft", (BELT_X, py, pz), (-1, 0, 0), 1.0, BELT_X - FAN_X)
    d.cylinder("fan_hub", (FAN_X + 0.6, py, pz), (-1, 0, 0), 2.6, 0.6)
    sk = d.sketch("YZ", "Fan", offset=FAN_X)
    blade = [(1.1, -0.9), (FAN_R - 1.2, -1.4), (FAN_R, -0.8), (FAN_R, 0.8), (FAN_R - 1.2, 1.4),
             (1.1, 0.9)]
    for k in range(4):
        t = math.radians(45 + 90 * k)
        c, sn = math.cos(t), math.sin(t)
        d.poly([(py + r * c - w * sn, pz + r * sn + w * c) for r, w in blade])
    d.finish()
    d.extrude(sk, "fan_blades", 0.12, "symmetric")

    # Generator low on the left, its shaft forward to its pulley.
    gy, gz = GENERATOR
    d.cylinder("generator", (-12.4, gy, gz), (1, 0, 0), GENERATOR_R * 2, GENERATOR_BACK + 12.4)
    d.cylinder("generator_shaft", (-12.4, gy, gz), (-1, 0, 0), 0.7, 12.4 + BELT_X)
    d.box("generator_bracket", (-9.0, -CASE_Y - 0.4, 2.2), (-8.2, -CASE_Y + 0.05, 3.2))

    # Crank snout through the cover, the pulleys in the belt's plane and the belt round them.
    d.cylinder("crank_snout", (COVER_FACE, CRANK_Y, 0), (-1, 0, 0), 2.2, COVER_FACE - BELT_X)
    for name, (y, z), r in PULLEYS:
        d.cylinder(f"pulley_{name}", (BELT_X + 0.45, y, z), (-1, 0, 0), r * 2, 0.9)
    sk = d.sketch("YZ", "Belt", offset=BELT_X)
    d.c += outline_commands(*hull_outline([(c, r) for _, c, r in PULLEYS]))
    d.c += outline_commands(*hull_outline([(c, r + 0.3) for _, c, r in PULLEYS]),
                            first=len(PULLEYS) + 1)
    d.finish()
    d.extrude(sk, "belt", 0.55, "symmetric")


def plane_sketch(d, name, origin, xdir, ydir):
    """A sketch on the plane through origin (inches) spanned by xdir and ydir: sketch (u, v)
    is origin + u xdir + v ydir."""
    d.n += 1
    d.c.append(cmd("sketch.create", name=name, plane={
        "origin": [round(float(v) * 25.4, 4) for v in origin],
        "x_dir": [float(v) for v in unit(xdir)], "y_dir": [float(v) for v in unit(ydir)]}))
    return name


def wire(d, name, p0, p1, rise):
    """A plug wire from p0 to p1, arching rise above the higher end, in the upright plane
    through both."""
    p0, p1 = np.array(p0, float), np.array(p1, float)
    h = p1 - p0
    h[2] = 0.0
    length = float(np.linalg.norm(h))
    dz = float(p1[2] - p0[2])
    top = max(0.0, dz) + rise
    pts = [np.array([0.0, 0.0]), np.array([length * 0.5, top]), np.array([length, dz])]
    l1, l2 = np.linalg.norm(pts[1] - pts[0]), np.linalg.norm(pts[2] - pts[1])
    d1, d2 = unit(pts[1] - pts[0]), unit(pts[2] - pts[1])
    turn = math.acos(max(-1.0, min(1.0, float(d1 @ d2))))
    r = 0.45 * min(l1, l2) / math.tan(turn / 2)
    sk = plane_sketch(d, f"{name} path", p0, h, (0, 0, 1))
    c, ids = path_commands(pts, r)
    d.c += c
    d.finish()
    d.c.append(cmd("solid.pipe", path_sketch=sk, path=ids, diameter=inch(0.3), operation="new",
                   name=name, body_name=name))


def plug_wires(d, a):
    """Towers round the distributor cap's top, a wire from each to a plug in the order the
    towers lie along the engine, and the coil's wire to the middle."""
    a = np.array(a, float)
    top = dist_base() + a * 9.0
    e1 = unit(np.array([1.0, 0.0, 0.0]) - a[0] * a)
    e2 = np.cross(a, e1)
    towers = [top + 1.0 * (math.cos(t) * e1 + math.sin(t) * e2)
              for t in (math.radians(30 + 60 * k) for k in range(6))]
    for k, q in enumerate(towers):
        d.cylinder(f"distributor_cap_tower_{k}", q, a, 0.42, 0.5)
    towers.sort(key=lambda q: (q[0], q[1]))
    t = math.radians(PLUG_TILT)
    pa = np.array([0.0, math.cos(t), math.sin(t)])
    for i, x in enumerate(BORE_X):
        tip = np.array([x, HEAD_Y, PLUG_Z]) + pa * 1.9
        wire(d, f"plug_wire_{i}", tip, towers[i] + a * 0.5, 0.9)
    x, y, _, z1, _ = COIL
    wire(d, "plug_wire_coil", (x, y, z1 + 0.5), top + a * 0.5, 1.2)


def dist_base():
    """The foot of the distributor's shank."""
    return np.array(DIST_CAP) - unit(DIST_AXIS) * 8.2


def right_side(d):
    # Distributor leaning out of the block: shank, body, cap; the vacuum advance off it.
    a = unit(DIST_AXIS)
    base = dist_base()
    rod(d, "distributor_shank", base, a, 1.0, 0.0, 4.8)
    # Its boss on the block, the shank going down into it.
    rod(d, "engine_block_distributor_boss", base, a, 1.7, DIST_BOSS[0], DIST_BOSS[1] - DIST_BOSS[0])
    rod(d, "distributor_body", base, a, 2.5, 4.8, 2.6)
    rod(d, "distributor_cap", base, a, 2.9, 7.4, 1.6)
    rod(d, "distributor_cap_top", base, a, 1.4, 9.0, 0.5)
    plug_wires(d, a)
    side = base + a * 5.8
    rod(d, "vacuum_advance", side, (-1, 0, 0), 1.3, 1.2, 0.7)
    rod(d, "vacuum_advance_arm", side, (-1, 0, 0), 0.4, 0.0, 1.3)

    # The coil on a bracket off the head.
    x, y, z0, z1, dia = COIL
    d.cylinder("coil", (x, y, z0), (0, 0, 1), dia, z1 - z0)
    d.cylinder("coil_tower", (x, y, z1), (0, 0, 1), 0.6, 0.5)
    # Its bracket: a strap off the head's top edge, round the coil.
    d.box("coil_bracket", (x - 0.5, HEAD_Y - 0.5, HEAD_TOP - 0.25), (x + 0.5, y + dia / 2 + 0.05, HEAD_TOP + 0.05))

    # Fuel pump at the front: the pad, the body and the glass bowl on top.
    fx, fy = FUEL_PUMP
    d.box("fuel_pump_pad", (fx - 1.0, CASE_Y - 0.05, 1.4), (fx + 1.0, fy - 0.6, 3.4))
    d.cylinder("fuel_pump", (fx, fy, 1.6), (0, 0, 1), 2.2, 2.2)
    d.cylinder("fuel_pump_bowl", (fx, fy, 3.8), (0, 0, 1), 2.6, 1.6)

    # Oil filler tube leaning out, its cap; the dipstick.
    base, lean, length = FILLER_TUBE
    t = math.radians(lean)
    a = (0.0, math.sin(t), math.cos(t))
    rod(d, "oil_filler", base, a, 1.3, -0.6, length + 0.6)
    rod(d, "oil_filler_cap", base, a, 2.0, length, 0.45)
    x, y, z0, z1 = DIPSTICK
    d.cylinder("dipstick", (x, y, z0), (0, 0, 1), 0.25, z1 - z0)
    sphere(d, "dipstick_knob", (x, y, z1), 0.6)

    # Starter at the back, nose into the flywheel housing, the solenoid on top.
    sy, sz, sd, s0, s1 = STARTER
    d.cylinder("starter", (s0, sy, sz), (1, 0, 0), sd, s1 - s0)
    d.cylinder("starter_nose", (s1, sy, sz), (1, 0, 0), sd * 0.5, BLOCK_HALF + FLYWHEEL[2] - s1)
    d.cylinder("starter_solenoid", (s0 + 1.8, sy - 0.35, sz + sd / 2 + 0.9), (1, 0, 0), 2.0, 4.5)


def oil_pan(d):
    d.box("oil_pan_flange", (-BLOCK_HALF, -RAIL[0], -0.25), (BLOCK_HALF - 0.5, RAIL[0], 0.0))
    # XZ sketch: (x, -z). Shallow at the front, stepping down to the sump at the back.
    prof = [(-BLOCK_HALF, 0.0), (BLOCK_HALF - 0.5, 0.0), (BLOCK_HALF - 0.5, -6.2), (11.0, -6.6),
            (-2.5, -6.6), (-4.9, -4.6), (-9.3, -4.6), (-11.4, -2.6), (-BLOCK_HALF, -2.1)]
    sk = d.sketch("XZ", "Oil pan", offset=0.0)
    d.poly([(x, -z) for x, z in prof])
    d.finish()
    d.extrude(sk, "oil_pan", PAN_WIDTH, "symmetric")
    d.cylinder("oil_pan_drain", (8.5, 0, -6.6), (0, 0, -1), 0.9, 0.3)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sc", help="design file (default resources/engines/STEM.sc)")
    ap.add_argument("--glb", help="mesh (default assets/parts/STEM.glb)")
    ap.add_argument("--solidcraft", default="solidcraft-cli",
                    help="solidcraft-cli, or the SolidCraft AppImage")
    ap.add_argument("--blender", default="blender", help="Blender, which thins the mesh")
    args = ap.parse_args()
    sc = os.path.abspath(args.sc or os.path.join(ROOT, "resources", "engines", STEM + ".sc"))
    glb = os.path.abspath(args.glb or os.path.join(ROOT, "assets", "parts", STEM + ".glb"))
    tool = shutil.which(args.solidcraft) or args.solidcraft
    if not os.path.exists(tool):
        sys.exit(f"no SolidCraft command line at {args.solidcraft}")
    blender = shutil.which(args.blender) or args.blender
    if not os.path.exists(blender):
        sys.exit(f"no Blender at {args.blender}")

    d = Design()
    block(d)
    deck(d)
    head(d)
    valve_cover(d)
    intake(d)
    carburetor(d)
    air_cleaner(d)
    exhaust(d)
    front(d)
    right_side(d)
    oil_pan(d)

    with tempfile.TemporaryDirectory() as tmp:
        obj = os.path.join(tmp, "engine.obj")
        d.c.append(cmd("file.export_obj", path=obj))
        script = os.path.join(tmp, "engine.json")
        with open(script, "w") as f:
            json.dump({"commands": d.c}, f)
        os.makedirs(os.path.dirname(sc), exist_ok=True)
        print(f"building {STEM}")
        SolidCraft(tool).run(script, "--save", sc)
        print("thinning the mesh")
        thin = os.path.join(tmp, "thin.obj")
        reduce_exact(obj, thin, blender)
        bodies = read_tris(thin)

    # Design mm -> engine units (0.22 m), the crank onto the models' axis. A sketch of several
    # separate shapes extrudes into a body each, "name (2)" and on: one mesh again.
    merged = {}
    for name, (p, t) in bodies.items():
        p, nr, i = crease_normals(p, t)
        base = re.sub(r"[ _]\(\d+\)$", "", name)
        if base in merged:
            mp, mn, mi = merged[base]
            merged[base] = (np.vstack([mp, p]), np.vstack([mn, nr]), np.concatenate([mi, i + len(mp)]))
        else:
            merged[base] = (p, nr, i)
    for name, (p, nr, i) in deck_meshes().items():
        merged[name] = (p * 25.4, nr, i)
    parts = []
    for name, (p, nr, i) in merged.items():
        p = (p * 0.001 - np.array([0.0, CRANK_Y * 0.0254, 0.0])) / 0.22 + np.array([0.0, 0.0, -0.36])
        parts.append((name, p, nr, i, finish_for(name)))
    write_glb(glb, parts)
    allp = np.concatenate([p for _, p, *_ in parts])
    print(f"{os.path.relpath(sc, ROOT)}\n{os.path.relpath(glb, ROOT)}: {len(parts)} bodies, "
          f"{sum(len(i) for *_, i, _ in parts) // 3} triangles, extent "
          f"{np.round(allp.min(axis=0), 2).tolist()} to {np.round(allp.max(axis=0), 2).tolist()}")


if __name__ == "__main__":
    main()
