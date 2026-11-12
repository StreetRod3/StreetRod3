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
  valve cover   tall and rounded, a lip round its foot, two ribs along its top, three
                straps across it with a nut on the outer two, the oil filler cap at the
                front
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

The design is in inches with the crank on the X axis: +X toward the back of the car, +Y
to its right, +Z up, the block's middle on X = 0. The GLB is in the frame of the other
engine models (engine_assembly.gd): engine units of 0.22 m, the crank at Z -0.36. The
game does not use it yet.
"""
import argparse
import json
import math
import os
import re
import shutil
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_wheels import SolidCraft, cmd, write_glb  # noqa: E402
from make_flathead import (Design, hull_outline, outline_commands, read_tris,  # noqa: E402
                           crease_normals, reduce_obj, skp, inch, pt3, BLACK, STEEL,
                           CAST_IRON, CAST_ALUMINUM, PORCELAIN, RUBBER)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEM = "engine-chevy-235"

BORE = 3.5625
STROKE = 3.9375
BORE_X = [-9.6, -5.76, -1.92, 1.92, 5.76, 9.6]   # 3.84 apart, as the reference's plugs

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
COVER = (11.8, 2.6, 1.0)    # half length, half width, corner radius
COVER_TOP = 17.7
STRAP_X = (-6.4, 0.0, 6.4)
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
EXH_OUT_X = 1.75
EXH_FLANGE_Z = 7.2
CARB_X = -1.0
CLEANER = (7.3, 18.9, 23.9)  # diameter, bottom, top

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
PULLEYS = [("crank", (0.0, 0.0), 2.25), ("pump", PUMP, 1.2), ("generator", GENERATOR, 1.0)]

# The right side.
PLUG_Z = 11.4
PLUG_TILT = 25.0        # up from level, leaning out
DIST_BASE = (0.0, 3.7, 0.6)
DIST_TILT = 15.0        # out from upright
COIL = (3.85, 4.9, 9.7, 13.9, 1.75)     # x, y, bottom, top, diameter
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
FINISHES = [
    ("exhaust", CAST_IRON), ("carburetor_neck", STEEL), ("carburetor", CAST_ALUMINUM),
    ("air_cleaner_screen", SCREEN), ("air_cleaner", BLACK), ("plug_wire", WIRE),
    ("distributor_body", STEEL), ("distributor_shank", STEEL), ("distributor_cap", BLACK),
    ("vacuum_advance", STEEL), ("coil", BLACK), ("fuel_pump_bowl", GLASS),
    ("fuel_pump", CAST_ALUMINUM),
    ("oil_filler_cap", BLACK), ("valve_cover_filler_cap", BLACK), ("valve_cover_nut", STEEL),
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
             (UPPER_Y, UPPER_Z), (UPPER_Y, DECK)]
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
    d.cylinder("engine_block_flywheel_housing", (BLOCK_HALF, 0, cz), (1, 0, 0), dia, depth)
    d.cylinder("engine_block_flywheel_flange", (BLOCK_HALF + depth, 0, cz), (1, 0, 0), dia + 0.8, 0.3)
    sy, sz, sd, _, _ = STARTER
    d.cylinder("engine_block_starter_boss", (BLOCK_HALF, sy, sz), (1, 0, 0), sd * 0.75, depth)


def head(d):
    sk = d.sketch("YZ", "Head")
    d.poly([(HEAD_Y, DECK), (HEAD_Y, HEAD_TOP), (-HEAD_Y, HEAD_TOP), (-HEAD_Y, DECK)])
    d.finish()
    d.extrude(sk, "cylinder_head", HEAD_HALF * 2, "symmetric")

    # Bolt bosses down the right side, between the plugs and at the ends.
    xs = [-11.2] + [(a + b) / 2 for a, b in zip(BORE_X, BORE_X[1:])] + [11.2]
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

    # Water outlet on the front end, its neck forward and up to the hose.
    d.box("water_outlet", (-HEAD_HALF - 0.7, -0.9, 11.2), (-HEAD_HALF + 0.05, 0.9, 12.8))
    rod(d, "water_outlet_neck", (-HEAD_HALF - 0.4, 0.0, 12.3), (-0.5, 0.0, 0.866), 1.4, 0.0, 1.8)


def valve_cover(d):
    hl, hw, r = COVER
    sk = d.sketch("XY", "Valve cover lip", offset=HEAD_TOP)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(-hl - 0.2, -hw - 0.2),
                   p1=skp(hl + 0.2, hw + 0.2), radius=inch(r + 0.2)))
    d.finish()
    d.extrude(sk, "valve_cover_lip", 0.25)
    body_h = COVER_TOP - HEAD_TOP - 0.8
    sk = d.sketch("XY", "Valve cover", offset=HEAD_TOP)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(-hl, -hw), p1=skp(hl, hw), radius=inch(r)))
    d.finish()
    d.extrude(sk, "valve_cover", body_h)
    sk = d.sketch("XY", "Valve cover crown", offset=HEAD_TOP + body_h)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(-hl, -hw), p1=skp(hl, hw), radius=inch(r)))
    d.finish()
    d.extrude(sk, "valve_cover_crown", 0.8, taper="-35 deg")
    top_in = 0.8 * math.tan(math.radians(35))

    # Two ribs along the top.
    for s in (1, -1):
        d.box(f"valve_cover_rib_{s}", (-hl + 1.2, s * 1.2 - 0.1, COVER_TOP - 0.05),
              (hl - 1.2, s * 1.2 + 0.1, COVER_TOP + 0.1))

    # Straps across, standing just proud: the ring between two outlines across the cover,
    # its bottom down in the head where it does not show.
    for i, x in enumerate(STRAP_X):
        sk = d.sketch("YZ", f"Strap {i}", offset=x)
        for grow in (0.14, 0.0):
            d.c.append(cmd("sketch.rectangle.rounded", p0=skp(-hw - grow, HEAD_TOP - 1.0 - grow),
                           p1=skp(hw + grow, COVER_TOP - 0.25 + grow), radius=inch(r + grow)))
        d.finish()
        d.extrude(sk, f"valve_cover_strap_{i}", 0.45, "symmetric")
    for i, x in enumerate((STRAP_X[0], STRAP_X[-1])):
        sk = d.sketch("XY", f"Cover nut {i}", offset=COVER_TOP)
        d.c.append(cmd("sketch.polygon.inscribed", center=skp(x, 0.0), radius=0.3 * 25.4, sides=6))
        d.finish()
        d.extrude(sk, f"valve_cover_nut_{i}", 0.35)

    # The oil filler cap at the front of the top.
    assert hw - top_in > 1.3
    d.cylinder("valve_cover_filler", (FILLER_X, 0, COVER_TOP - 0.1), (0, 0, 1), 1.4, 0.5)
    d.cylinder("valve_cover_filler_cap", (FILLER_X, 0, COVER_TOP + 0.4), (0, 0, 1), 2.6, 0.4)


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
        d.cylinder(f"exhaust_port_stub_{half}", (k * EXH_PORT_X, EXH_Y, EXH_LOG_Z), (0, 0, 1), 1.4, 1.3)
        d.cylinder(f"exhaust_port_inner_{half}", (k * EXH_PORT_X, -HEAD_Y, EXH_LOG_Z + 1.3),
                   (0, -1, 0), 1.4, HEAD_Y - (-EXH_Y))
        sphere(d, f"exhaust_port_bend_{half}", (k * EXH_PORT_X, EXH_Y, EXH_LOG_Z + 1.3), 1.4)
        d.box(f"exhaust_flange_{half}", (k * EXH_OUT_X - 1.3, EXH_Y - 0.95, EXH_FLANGE_Z),
              (k * EXH_OUT_X + 1.3, EXH_Y + 0.95, EXH_FLANGE_Z + 0.25))


def front(d):
    # Timing cover round the crank and up round the cam gear on the right.
    sk = d.sketch("YZ", "Timing cover", offset=FRONT)
    d.c += outline_commands(*hull_outline([((0.0, 0.6), 2.0), ((2.6, 2.6), 2.6)]))
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
    d.cylinder("crank_snout", (COVER_FACE, 0, 0), (-1, 0, 0), 2.2, COVER_FACE - BELT_X)
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
    top = np.array(DIST_BASE) + a * 9.0
    e1 = np.array([1.0, 0.0, 0.0])
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


def right_side(d):
    # Distributor leaning out of the block: shank, body, cap; the vacuum advance off it.
    t = math.radians(DIST_TILT)
    a = (0.0, math.sin(t), math.cos(t))
    rod(d, "distributor_shank", DIST_BASE, a, 1.0, 0.0, 4.8)
    rod(d, "distributor_body", DIST_BASE, a, 2.5, 4.8, 2.6)
    rod(d, "distributor_cap", DIST_BASE, a, 2.9, 7.4, 1.6)
    rod(d, "distributor_cap_top", DIST_BASE, a, 1.4, 9.0, 0.5)
    plug_wires(d, a)
    side = np.array(DIST_BASE) + np.array(a) * 5.8
    rod(d, "vacuum_advance", side, (-1, 0, 0), 1.3, 1.2, 0.7)
    rod(d, "vacuum_advance_arm", side, (-1, 0, 0), 0.4, 0.0, 1.3)

    # The coil on a bracket off the head.
    x, y, z0, z1, dia = COIL
    d.cylinder("coil", (x, y, z0), (0, 0, 1), dia, z1 - z0)
    d.cylinder("coil_tower", (x, y, z1), (0, 0, 1), 0.6, 0.5)
    d.box("coil_bracket", (x - 0.4, HEAD_Y - 0.05, 12.4), (x + 0.4, y - dia / 2 + 0.1, 13.0))

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
        reduce_obj(obj, thin, blender)
        bodies = read_tris(thin)

    # Design mm -> engine units (0.22 m), crank down to the models' Z. A sketch of several
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
    parts = []
    for name, (p, nr, i) in merged.items():
        p = p * 0.001 / 0.22 + np.array([0.0, 0.0, -0.36])
        parts.append((name, p, nr, i, finish_for(name)))
    write_glb(glb, parts)
    allp = np.concatenate([p for _, p, *_ in parts])
    print(f"{os.path.relpath(sc, ROOT)}\n{os.path.relpath(glb, ROOT)}: {len(parts)} bodies, "
          f"{sum(len(i) for *_, i, _ in parts) // 3} triangles, extent "
          f"{np.round(allp.min(axis=0), 2).tolist()} to {np.round(allp.max(axis=0), 2).tolist()}")


if __name__ == "__main__":
    main()
