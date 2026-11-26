#!/usr/bin/env python3
"""Build a 426 Hemi V8 in SolidCraft and export it as a game GLB.

    python3 tools/make_hemi.py                             # the Street Hemi
    python3 tools/make_hemi.py headers --headers shorty    # a set of headers alone

The 426 Hemi is an engine of its own, not one of the B or RB wedges: its block is its
own casting, with cross-bolted mains and its own head bolts and engine mounts, but it is
laid out on the raised-block wedge's dimensions, a 10.725 in deck, 4.80 in bore spacing
and 3.75 in stroke, with a 4.25 in bore; its heads are twice as wide as a wedge's, the
plugs down tubes in the middle of the valve covers.
This is the Street Hemi of 1966 to 1971: two four-barrels in tandem on an aluminum intake,
cast-iron exhaust manifolds shaped like headers, crinkle-black valve covers, the rest
Hemi Orange.

The numbers that make it a Hemi are Chrysler's (reference/parts/426/: the Direct
Connection B-RB racing manual, which gives the raised block's dimensions and notes what
the Hemi shares with the wedges, the 1963 Hemi layout drawing and the cross-section for
the heads). The shapes and where the parts are come from a rough sculpt
of a Street Hemi (reference/parts/426/hemi-426.stl, scaled to the 4.80 in bore spacing)
and a photo of a 1966 Street Hemi: the heads' outline across the bank, the valve covers'
section, the intake's height, the carburetors' places, the water pump high on the front,
the alternator on the right, the pan deep at the front. From Chrysler's layout of the time,
not the sculpt: the distributor at the right front, the fuel pump on the right, the oil
filter low on the left, the starter on the right. It has:

  block         one outline across the engine, extruded front to back: each bank's outer
                wall down from the deck's edge to the skirt, the deep skirts down past the
                crank to the pan rail; the valley under a tappet cover; the bellhousing
                flange at the back, the mount pads on the sides, freeze plugs
  heads         the Hemi's outline across the bank: the low outer side up from the deck to
                a boss under the exhaust ports, the exhaust face square to the ground with
                a two-bolt pad round each port, leaning out above them to the valve cover
                rail, the rail falling toward the valley, the intake face high over it
  valve covers  crinkle black on the rail, the outer side tall and the top falling toward
                the valley; bolts round the flange; a well over each plug with its wire's
                boot in it; the oil filler on the left, the breather on the right
  intake        aluminum, painted: a flange on each head's intake face, a floor between
                them, a runner up out of each port into one long plenum, two carb pads on
                it one behind the other
  carburetors   two square-flange four-barrels (make_sbc.py's) under one long oval air
                cleaner
  distributor   at the right front of the valley, the coil on the left head's front
  manifolds     cast iron shaped like headers, as the 1966 photo's: a flange on each port,
                a thick runner out of each, down and back into a cast collector behind the
                back port, the outlet down at the back
  headers       (built alone) long tubes or shorties, as make_sbf.py's
  front         the timing cover, the water pump's big housing high on it with the
                thermostat on top, the balancer and crank pulley, the pump pulley and fan,
                the alternator on the right, the fuel pump on the right, the belt
  bottom        the oil pan, deep at the front, the oil pump and filter on the left, the
                starter on the right, the flywheel

Every part is a body of its own, drawn from numbers in this script; to change the engine,
change the numbers and run it again. The helpers are make_sbf.py's, make_sbc.py's and
make_flathead.py's.

Writes resources/engines/STEM.sc, the SolidCraft design, and assets/parts/STEM.glb, STEM
being engine-hemi-426 for the engine, hemi-426-headers-long and -shorty for the headers.
Needs SolidCraft's command line and Blender, as tools/make_flathead.py does.

The design is in inches with the crank on the X axis: +X toward the back of the car, +Y
to its right, +Z up, the block's middle on X = 0. The GLB is in the frame of the other
engine models (engine_assembly.gd): engine units of 0.22 m, the crank at Z -0.36. Node
names follow make_sbf.py's, +1 the right bank and -1 the left. Chrysler's left bank is the
one ahead, as the Chevy's.
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
from make_flathead import (  # noqa: E402
    BLACK, CAST_ALUMINUM, CAST_IRON, MACHINED, MM, PORCELAIN, RUBBER, S45, STEEL, ZINC,
    crease_normals, hull_outline, inch, outline_commands, read_tris, skp)
from make_sbc import (  # noqa: E402
    BLENDER_REDUCE, CHROME, FILTER, FILTER_CAN, HEADER, SBC, ccw, hose_neck, lerp,
    p3, tube_path, unit, v3)
from make_sbf import grooves, rise_path, shrunk  # noqa: E402
from make_wheels import SolidCraft, cmd, write_glb  # noqa: E402
import engine_meshes as em  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEM = "engine-hemi-426"

# Crank to deck and bore spacing as the raised-block wedge's (the B-RB racing manual);
# bore, stroke, rod.
DECK = 10.725
BORE = 4.25
STROKE = 3.75
ROD = 6.86

# The block. Bores, ports and bolts are along each bank from the bank's middle.
BLOCK_FRONT = -11.35
BLOCK_BACK = 11.35
DECK_OUT = 3.5          # bank axis out to the deck's outer edge
DECK_IN = 4.0           # bank axis in to the deck's inner edge
VALLEY_DROP = 1.4       # the valley floor, this far under the decks' inner edges
WALL_FOOT = (8.0, 1.0)  # where each bank's outer wall comes down to the skirt (|y|, z)
SKIRT_Y = 7.0           # the deep skirts, down past the crank to the pan rail
RAIL_Z = -3.0           # the pan rail
BORE_MID = -0.3         # the bores' middle along the crank, both banks
BANK_SHIFT = 0.47       # the left bank sits this far ahead of that, the right back
BORE_X = [-7.2, -2.4, 2.4, 7.2]     # 4.80 in apart
HEAD_BOLT_X = [-9.6, -4.8, 0.0, 4.8, 9.6]
# The bellhousing flange across the back, (y, z) for the right half, and its bolt bosses.
BELL_FLANGE = [(9.2, RAIL_Z), (9.2, 3.6), (8.4, 6.2), (5.0, 9.6), (1.6, 10.4)]
BELL_BOSSES = [(8.6, -1.8), (8.9, 1.8), (7.4, 5.9), (3.8, 9.3)]
FREEZE_PLUG_X = [-4.8, 0.0, 4.8]    # along the bank, between the cylinders
FREEZE_PLUG_T = 0.45    # how far down the outer wall from the deck's edge
MOUNT_X = -3.8          # the side mounts' pads, along the block
# The tappet cover over the valley, under the intake (half long, |y|, its top).
VALLEY_COVER = (10.9, 4.7, 10.45)

# What shows with the heads off.
THROWS = [0, 90, 270, 180]
DECK_PLATE = 0.012
DECK_BOLTS = (0.75, 6.8, 0.29)      # the bolt rows, in from the deck's outer edge; radius
DECK_WATER = (1.0, 6.15, 0.17)      # the water holes beside each bore, likewise
DOME = (0.78, 0.55)                 # the pistons' domes: across (of the bore), standing up

# The heads, in each deck's own frame: a in from the deck's outer edge, h up off it. From
# the sculpt and the cross-section: the deck, the intake side up to its face high over the
# valley, the rail falling toward the valley, the outer side leaning out above the exhaust
# face, the face square to the ground, the boss under the ports, the low outer side down
# to the deck.
HEAD_HALF = 10.4
HEAD = [(0.0, 0.0), (7.5, 0.0), (10.2, 2.2), (10.2, 5.5), (1.95, 7.5), (1.7, 6.0), (0.3, 4.6),
        (0.95, 3.15), (0.75, 2.5)]
EXHAUST_FACE = ((0.3, 4.6), (1.7, 6.0))     # bottom and top, (a, h)
RAIL = ((1.95, 7.5), (10.2, 5.5))           # the valve cover rail, outer and inner, (a, h)
INTAKE_FACE_A = 10.2
HEAD_END_BEVEL = 0.35
# The exhaust ports, in the middle of the face at each bore: the opening, the pad round it
# with an ear for a bolt each side (x along the face, v up it, r) and how far the pad
# stands out.
PORT_T = 0.5
PORT_OPENING = (1.55, 1.25, 0.35)            # across, up, corner
PORT_PAD = [(-1.5, 0.0, 0.42), (-0.75, -0.72, 0.25), (0.75, -0.72, 0.25), (1.5, 0.0, 0.42),
            (0.75, 0.68, 0.25), (-0.75, 0.68, 0.25)]
PORT_PAD_T = 0.2
PORT_BOLT_X = 1.5
# The lower head bolts on bosses up the outer side, along the bank: a, and the bosses'
# foot and top and the bolts' tops (h).
HEAD_BOLT_LEDGE = (0.55, 0.4, 2.3, 2.7)

# Valve covers, in the rail's frame: x along the bank from its middle, c across from the
# rail's outer edge toward the valley, lift up off it. The section (c, lift), the same all
# along but for the ends, after the sculpt's but deeper: the outer side leaning in up to a
# tall rounded edge, the top falling toward the valley. The flange runs round it, out past the body.
COVER_SECTION = [(8.15, 0.0), (0.1, 0.0), (0.2, 0.6), (1.6, 2.75), (1.95, 3.1), (2.5, 3.25),
                 (3.6, 3.28), (5.6, 2.85), (7.15, 2.15), (7.7, 1.7), (8.0, 1.1), (8.15, 0.4)]
COVER_HALF = 10.0
COVER_END = 1.3         # the body rounds off over this much at each end
COVER_END_SECTIONS = [(0.0, 1.0, 1.0), (0.55, 0.97, 0.88), (1.0, 0.86, 0.5)]   # along, across, up
COVER_FLANGE = (-0.5, 8.6, 10.35, 1.2, 0.12)    # c from, to, half long, corner, thick
# Bolts round the flange: on the outer lip and on the inner (x, c).
COVER_BOLTS = ([(x, -0.22) for x in (-9.3, -4.8, 0.0, 4.8, 9.3)] +
               [(x, 8.38) for x in (-7.2, 0.0, 7.2)])
PLUG_WELL = (3.0, 0.78)     # across, radius: a well over each plug, its boot in it
FILLER = (-8.0, 5.9)        # the oil filler on the left cover (x, c), the breather on the right
BREATHER = (8.0, 5.9)

# Intake, in each head's frame where it sits on it: the flange on each intake face (up the
# face from, to; thick), the runners' ports up it, the bolts' line up it and along each bank
# from its middle.
INTAKE_FLANGE = (2.3, 5.3, 0.6)
INTAKE_PORT_H = 3.8
INTAKE_BOLT_T = 3.8
INTAKE_BOLT_X = [-9.6, -4.8, 0.0, 4.8, 9.6]
INTAKE_FRONT_RIGHT = -8.1   # the right flange and the floor stop here, clear of the distributor
INTAKE_FLOOR_T = 0.55
RUNNER_BENDS = (1.0, 1.0)
RUNNER_CORNER = 0.45
RUNNER_BURY = 0.3
# The runners: (cylinder front to back, bank, top over the ports, across, deep, where each
# ends in the plenum's side (|y|), how steeply it climbs out of its port).
INTAKE_RUNNERS = [(i, s, 2.6, 1.9, 1.7, 2.9, 45) for s in (1, -1) for i in range(4)]
FLOOR_INSET = 0.2
# The plenum along the middle from above (x0, x1, |y|), a lobe at the front left out to the
# left front runner (x0, x1, y up to), its top; the carb pads on it, front and back.
PLENUM = (-8.1, 8.4, 3.1)
PLENUM_LOBE = (-9.1, -6.0, 0.2)
PLENUM_TOP = 18.9
PADS_X = (-4.6, 3.6)
PAD_Z = 20.6            # the pads' underside
PAD = (2.65, 2.6, 0.4)  # half long, half wide, thick
PAD_BOSSES = [(2.75, 2.58), (-2.85, 2.58)]
PAD_BOSS_R = 0.55
PAD_HOLES = [(-0.91, -0.95), (0.91, -0.95)]
PAD_HOLE_R = 0.8
PAD_SLOT = ((-0.99, 0.95), (0.99, 0.95), 0.82)
PLENUM_FLOOR = 1.1
# On each head's intake face, showing with the intake off: a port where each runner meets
# it (half long, half high, corner).
INTAKE_PORT = (0.85, 0.95, 0.35)
# The oval air cleaner over both carburetors: half the straight length, radius.
CLEANER = (4.1, 6.2)

DIST = (-10.3, 2.3)     # the distributor's axis (x, y), at the valley's right front
DIST_BOSS = (9.0, 10.9)  # its boss in the block, from, to (z)
DIST_VACUUM = (-0.5, -0.86, 0.0)
CLAMP_WAY = (-0.3, -1.0)
CLAMP_REACH = 1.6
COIL = (-12.4, -5.6, 12.0)

# The stock exhaust, as the 1966 photo's: cast iron shaped like headers. A flange on each
# port's pad, a thick runner out of each (straight out, then the bend's radius); the front
# two down to MANIFOLD_MID_Z, then back, the back two straight down and back, into a cast
# collector behind the back port (its mouth: x along the bank, |y|, z; its axis, down and
# back to the outlet's flange), flared open toward the runners (radius at the mouth and at
# the outlet, length).
MANIFOLD_FLANGE_T = 0.45
MANIFOLD_RUNNER_D = 1.75
MANIFOLD_OUT = (0.5, 1.2)
MANIFOLD_MID_Z = 4.6
MANIFOLD_LEAN = (-0.15, 0.0, 0.0, 0.25)
MANIFOLD_COLLECTOR = ((9.3, 12.2, 2.6), (0.8, 0.0, -0.6))
MANIFOLD_OUTLET_D = 2.2
MANIFOLD_FLARE = (3.0, 1.15, 3.6)
# Headers, as make_sbf.py's: the collectors' front ends (x along the bank, |y|, z) and axis.
COLLECTOR = {"long": ((10.0, 12.8, -5.5), (0.75, 0.0, -0.66)),
             "shorty": ((3.5, 13.4, -0.5), (0.8, 0.0, -0.6))}
PRIMARY_D = 1.875
PRIMARY_OUT = (1.0, 1.8)
PRIMARY_MID_Z = 4.0
PRIMARY_LEAN = (-0.3, 0.0, 0.0, 0.3)

# Front: the timing cover's outline across (circles ((y, z), r) counterclockwise) out to the
# seal's face, the pump housing's pad on it out to its face, the pump's body on that, high
# up as the sculpt's.
TIMING_COVER = [((5.8, 0.0), 0.6), ((5.4, 4.0), 0.8), ((4.2, 7.5), 1.0), ((0.0, 10.6), 1.0),
                ((-4.2, 7.5), 1.0), ((-5.4, 4.0), 0.8), ((-5.8, 0.0), 0.6), ((-3.5, -3.4), 0.4),
                ((3.5, -3.4), 0.4)]
COVER_SEAL_X = -12.3
PUMP_PAD = [((0.0, 4.2), 1.8), ((4.0, 7.6), 1.4), ((0.0, 11.2), 1.3), ((-4.0, 7.6), 1.4)]
COVER_FACE = -13.0
PUMP = (0.0, 9.2)
PUMP_BODY = [((0.0, 5.8), 1.0), ((4.2, 8.0), 0.8), ((0.0, 9.2), 3.1), ((-4.2, 8.0), 0.8)]
PUMP_FACE = -14.4
THERMOSTAT = (-13.6, -2.0)
BALANCER = (-12.6, -14.6)       # back and front
BALANCER_R = 3.6
BELT_BACK = -14.75
CRANK_PULLEY_R = 3.5
PUMP_PULLEY_R = 4.3
FAN_X = -19.2
FAN_R = 9.0
ALTERNATOR = (7.8, 10.0)
ALT_PULLEY_R = 1.45
FUEL_PUMP = (-11.9, 5.2, 2.0)

# Bottom: the flywheel (front face, thickness, radius), the starter's axis (y, z), the oil
# pan (the flange's ends and half width, the pan's half width, its side profile (x, z) from
# the sculpt: deep at the front, shallower toward the back), the drain, the oil pump and
# filter on the left.
FLYWHEEL = (12.25, 0.9, 7.2)
STARTER = (8.8, -2.4)
PAN_FLANGE = (-12.4, 10.9)
PAN_FLANGE_Y = 7.3
PAN_Y = 6.3
PAN_PROFILE = [(-12.5, -3.15), (10.7, -3.15), (10.7, -4.4), (8.0, -9.5), (3.5, -10.6), (-3.0, -12.3),
               (-11.4, -12.3), (-12.5, -10.8)]
PAN_DRAIN = (-7.0, -12.3)
OIL_FILTER = (-8.5, -7.6, -2.6)
OIL_FILTER_DIR = (0.0, -0.42, -0.91)

HEMI_ORANGE = {"name": "paint", "pbrMetallicRoughness": {
    "baseColorFactor": [0.80, 0.12, 0.015, 1], "metallicFactor": 0.2, "roughnessFactor": 0.45}}
CRINKLE = {"name": "crinkle black", "pbrMetallicRoughness": {
    "baseColorFactor": [0.025, 0.025, 0.025, 1], "metallicFactor": 0.1, "roughnessFactor": 0.85}}


def bank(s):
    """Unit vectors of bank s (+1 right, -1 left) in (y, z): up its axis, out across its
    deck, and in across it toward the valley."""
    return np.array([s * S45, S45]), np.array([s * S45, -S45]), np.array([-s * S45, S45])


def deck_edge(s):
    u, out, _ = bank(s)
    return DECK * u + DECK_OUT * out


def on_head(s, a, h):
    """(y, z) of a point a in from bank s's deck's outer edge and h up off it."""
    u, _, inn = bank(s)
    return deck_edge(s) + a * inn + h * u


def head_dir(s, a, h):
    u, _, inn = bank(s)
    return a * inn + h * u


def bank_x(s, x):
    return x + BORE_MID + s * BANK_SHIFT


def deck_inner(s):
    return on_head(s, DECK_OUT + DECK_IN, 0.0)


def valley_z():
    return deck_inner(1)[1] - VALLEY_DROP


def exhaust_face(s):
    """Bank s's exhaust face: its foot (y, z), the way up it, and its outward normal."""
    f0, f1 = (on_head(s, *p) for p in EXHAUST_FACE)
    up = unit(f1 - f0)
    n = np.array([up[1], -up[0]])
    if n[0] * s < 0:
        n = -n
    return f0, up, n


def port_center(s):
    return on_head(s, *lerp(*EXHAUST_FACE, PORT_T))


def port_xs(s):
    return [bank_x(s, x) for x in BORE_X]


class Hemi(SBC):
    pass


# The block.

def wall_foot(s):
    return np.array([s * WALL_FOOT[0], WALL_FOOT[1]])


def outer_wall(s, t):
    """A point t of the way down bank s's outer wall from the deck's edge to its foot, and
    the wall's outward normal, both (y, z)."""
    a, b = deck_edge(s), wall_foot(s)
    along = unit(b - a)
    n = np.array([along[1], -along[0]])
    if n[0] * s < 0:
        n = -n
    return a + t * (b - a), n


def block_outline():
    """The block's outline across the engine (y, z), counterclockwise."""
    inner = deck_inner(1)
    vz = valley_z()
    fy, fz = WALL_FOOT
    right = [(SKIRT_Y, RAIL_Z), (SKIRT_Y, 0.0), (fy, 0.0), (fy, fz),
             tuple(deck_edge(1)), tuple(inner), (inner[0], vz)]
    left = [(-y, z) for y, z in reversed(right)]
    return ccw(right + left)


def block(d):
    sk = d.sketch("YZ", "Block", offset=BLOCK_FRONT)
    d.poly(block_outline())
    d.finish()
    d.extrude(sk, "engine_block", BLOCK_BACK - BLOCK_FRONT)

    # The valley's front and back walls, up to the decks' inner corners.
    inner = deck_inner(1)
    for k, (x0, x1) in enumerate(((BLOCK_FRONT, BLOCK_FRONT + 0.9), (BLOCK_BACK - 0.9, BLOCK_BACK))):
        sk = d.sketch("YZ", f"Valley wall {k}", offset=x0)
        right = [(inner[0], valley_z() - 0.2), tuple(inner)]
        d.poly(ccw(right + [(-y, z) for y, z in reversed(right)]))
        d.finish()
        d.extrude(sk, f"engine_block_end_wall_{k}", x1 - x0)

    # The tappet cover over the valley, a rib down its middle.
    hx, hy, top = VALLEY_COVER
    sk = d.sketch("XY", "Valley cover", offset=top - 0.15)
    d.rounded((-hx, -hy), (hx, hy), 0.5)
    d.finish()
    d.extrude(sk, "valley_cover", 0.15)
    sk = d.sketch("XY", "Valley cover rib", offset=top)
    d.rounded((-hx + 1.0, -0.6), (hx - 1.0, 0.6), 0.5)
    d.finish()
    d.extrude(sk, "valley_cover_rib", 0.25)

    # The bellhousing flange across the back, bolt bosses round it on its front.
    pts = BELL_FLANGE + [(-y, z) for y, z in reversed(BELL_FLANGE)]
    sk = d.sketch("YZ", "Bell flange", offset=BLOCK_BACK - 0.5)
    d.poly(ccw(pts))
    d.finish()
    d.extrude(sk, "engine_block_bell_flange", 0.5)
    sk = d.sketch("YZ", "Bell bosses", offset=BLOCK_BACK - 0.5)
    for y, z in BELL_BOSSES:
        for side in (1, -1):
            d.circle((side * y, z), 0.45)
    d.finish()
    d.extrude(sk, "engine_block_bell_bosses", 0.4, "negative")

    for s in (1, -1):
        # Freeze plugs set in raised rings in the outer wall.
        c, n = outer_wall(s, FREEZE_PLUG_T)
        sk, to2d = d.plane(p3(0.0, c), (1, 0, 0), v3(n), f"Freeze plug rings {s}")
        for x in FREEZE_PLUG_X:
            d.circle(to2d(p3(bank_x(s, x), c)), 0.95)
            d.circle(to2d(p3(bank_x(s, x), c)), 0.74)
        d.finish()
        d.extrude(sk, f"engine_block_plug_rings_{s}", 0.12)
        sk, to2d = d.plane(p3(0.0, c), (1, 0, 0), v3(n), f"Freeze plugs {s}")
        for x in FREEZE_PLUG_X:
            d.circle(to2d(p3(bank_x(s, x), c)), 0.73)
        d.finish()
        d.extrude(sk, f"freeze_plug_{s}", 0.05)
        # The side mount's pad lower down, with its bolt bosses.
        c, n = outer_wall(s, 0.85)
        sk, to2d = d.plane(p3(0.0, c), (1, 0, 0), v3(n), f"Mount pad {s}")
        m = to2d(p3(MOUNT_X, c))
        d.rounded((m[0] - 1.9, m[1] - 0.55), (m[0] + 1.9, m[1] + 0.55), 0.35)
        d.finish()
        d.extrude(sk, f"engine_block_mount_{s}", 0.25)
        sk, to2d = d.plane(p3(0.0, c), (1, 0, 0), v3(n), f"Mount bosses {s}")
        for dx in (-1.3, 1.3):
            d.circle(to2d(p3(MOUNT_X + dx, c)), 0.38)
        d.finish()
        d.extrude(sk, f"engine_block_mount_bosses_{s}", 0.42)


# The insides.

def throw_angle(s, i):
    return THROWS[i] - s * 45


def bore_cut():
    return max(em.piston_depth(throw_angle(s, i), STROKE, ROD) for s in (1, -1) for i in range(4)) + 1.0


def deck_holes():
    """The deck's small holes (x along the bank, a in from the outer edge, radius)."""
    ob, ib, br = DECK_BOLTS
    ow, iw, wr = DECK_WATER
    return ([(x, a, br) for x in HEAD_BOLT_X for a in (ob, ib)] +
            [(x, a, wr) for x in BORE_X for a in (ow, iw)])


def deck(d):
    """The bores cut down each bank, and the machined deck plate round them with its holes."""
    for s in (1, -1):
        u = bank(s)[0]
        # The cut starts a little above the deck: from on it, the kernel fails imprinting.
        lift = 0.05
        sk, to2d = d.plane(p3(0.0, deck_edge(s) + lift * u), (1, 0, 0), v3(u), f"Bores {s}")
        for x in BORE_X:
            c = to2d(p3(bank_x(s, x), on_head(s, DECK_OUT, lift)))
            d.c.append(cmd("sketch.polygon.inscribed", center=skp(*c), radius=round(BORE / 2 * MM, 4), sides=36))
        d.finish()
        d.c.append(cmd("solid.extrude", sketch=sk, distance=inch(bore_cut() + lift), direction="negative",
                       operation="cut", targets=["engine_block"], name=f"Bores cut {s}"))
        sk, to2d = d.plane(p3(0.0, deck_edge(s)), (1, 0, 0), v3(u), f"Deck {s}")
        c0 = to2d(p3(bank_x(s, -HEAD_HALF), on_head(s, 0.0, 0.0)))
        c1 = to2d(p3(bank_x(s, HEAD_HALF), on_head(s, DECK_OUT + DECK_IN, 0.0)))
        d.c.append(cmd("sketch.rectangle.two_point", p0=skp(min(c0[0], c1[0]), min(c0[1], c1[1])),
                       p1=skp(max(c0[0], c1[0]), max(c0[1], c1[1]))))
        for x in BORE_X:
            c = to2d(p3(bank_x(s, x), on_head(s, DECK_OUT, 0.0)))
            d.c.append(cmd("sketch.polygon.inscribed", center=skp(*c), radius=round(BORE / 2 * MM, 4), sides=36))
        for x, a, r in deck_holes():
            c = to2d(p3(bank_x(s, x), on_head(s, a, 0.0)))
            d.c.append(cmd("sketch.polygon.inscribed", center=skp(*c), radius=round(r * MM, 4), sides=10))
        d.finish()
        d.extrude(sk, f"engine_block_deck_{s}", DECK_PLATE)


# The heads.

def head_outline(s, outline=HEAD):
    return [tuple(on_head(s, a, h)) for a, h in outline]


def heads(d):
    bevel = HEAD_END_BEVEL
    for s in (1, -1):
        x0, x1 = bank_x(s, -HEAD_HALF), bank_x(s, HEAD_HALF)
        sk = d.sketch("YZ", f"Head {s}", offset=x0 + bevel)
        d.poly(ccw(head_outline(s)))
        d.finish()
        d.extrude(sk, f"cylinder_head_{s}", x1 - x0 - 2 * bevel)
        # Each end lofted from a smaller outline at the face out to the full one.
        small = shrunk(head_outline(s), bevel * 0.6)
        for k, (xf, xb) in enumerate(((x0, x0 + bevel), (x1, x1 - bevel))):
            sks = []
            for x, outline in ((xf, small), (xb, head_outline(s))):
                sk = d.sketch("YZ", f"Head {s} end {k} at {x:.3f}", offset=x)
                d.poly(ccw(outline))
                d.finish()
                sks.append(sk)
            d.loft(f"cylinder_head_{s} ({10 + 10 * k})", sks)

        # The exhaust ports' pads, their bolts and the dark openings.
        f0, up, n = exhaust_face(s)
        pc = port_center(s)
        sk, to2d = d.plane(p3(0.0, pc), (1, 0, 0), v3(n), f"Port pads {s}")
        first = 1
        for x in port_xs(s):
            pts = [(np.array(to2d(p3(x + dx, pc + v * up))), r) for dx, v, r in PORT_PAD]
            c = sum(p for p, _ in pts) / len(pts)
            pts.sort(key=lambda pr: math.atan2(*(pr[0] - c)[::-1]))
            d.c += outline_commands(*hull_outline([(tuple(p), r) for p, r in pts]), first=first)
            first += len(pts)
        d.finish()
        d.extrude(sk, f"cylinder_head_{s} (40)", PORT_PAD_T, start_offset=inch(-0.1))
        w, h, r = PORT_OPENING
        sk, to2d = d.plane(p3(0.0, pc + (PORT_PAD_T - 0.01) * n), (1, 0, 0), v3(n), f"Port openings {s}")
        for x in port_xs(s):
            c = to2d(p3(x, pc + (PORT_PAD_T - 0.01) * n))
            d.rounded((c[0] - w / 2, c[1] - h / 2), (c[0] + w / 2, c[1] + h / 2), r)
        d.finish()
        d.extrude(sk, f"cylinder_head_{s}_ports", 0.02)
        sk, to2d = d.plane(p3(0.0, pc + PORT_PAD_T * n), (1, 0, 0), v3(n), f"Port bolts {s}")
        for x in port_xs(s):
            for dx in (-PORT_BOLT_X, PORT_BOLT_X):
                d.hexagon(to2d(p3(x + dx, pc + PORT_PAD_T * n)), 0.5)
        d.finish()
        d.extrude(sk, f"exhaust_port_bolts_{s}", 0.3)

        # The lower head bolts on their bosses up the outer side.
        u = bank(s)[0]
        a, h0, h1, h2 = HEAD_BOLT_LEDGE
        for k, x in enumerate(HEAD_BOLT_X):
            base = p3(bank_x(s, x), on_head(s, a, h0))
            d.cylinder(f"cylinder_head_{s}_bosses ({10 + 10 * k})", base, v3(u), 0.95, h1 - h0)
        sk, to2d = d.plane(p3(0.0, on_head(s, a, h1)), (1, 0, 0), v3(u), f"Head bolts {s}")
        for x in HEAD_BOLT_X:
            d.hexagon(to2d(p3(bank_x(s, x), on_head(s, a, h1))), 0.62)
        d.finish()
        d.extrude(sk, f"head_bolts_{s}", h2 - h1)


# Valve covers.

def rail_frame(s):
    """Bank s's valve cover rail: its outer edge (y, z), across it toward the valley, and
    up off it, as (y, z)."""
    r0, r1 = (np.array(p, float) for p in RAIL)
    across = unit(r1 - r0)
    upa = np.array([-across[1], across[0]])
    return on_head(s, *r0), head_dir(s, *across), head_dir(s, *upa)


def rail_point(s, c, lift):
    o, across, up = rail_frame(s)
    return o + c * across + lift * up


def cover_section(s, scale=(1.0, 1.0)):
    """The cover's section across (y, z) on top of the flange, scaled toward the middle of
    its foot (across, up) for the ends."""
    kc, kl = scale
    cm = 4.1
    flange_t = COVER_FLANGE[4]
    return [tuple(rail_point(s, cm + (c - cm) * kc, flange_t + lift * kl)) for c, lift in COVER_SECTION]


def top_lift(c):
    """The cover's top's lift (off the flange) at c, and its slope."""
    top = [(c_, l_) for c_, l_ in COVER_SECTION[2:]]
    for (ca, la), (cb, lb) in zip(top, top[1:]):
        if ca <= c <= cb:
            t = (c - ca) / (cb - ca)
            return la + t * (lb - la), (lb - la) / (cb - ca)
    raise ValueError(c)


def cover_top(s, x, c):
    """A point on bank s's cover's top at x along the bank and c across, and the top's
    outward normal there, both in 3D."""
    lift, slope = top_lift(c)
    _, across, up = rail_frame(s)
    p = p3(bank_x(s, x), rail_point(s, c, COVER_FLANGE[4] + lift))
    n = unit(v3(up) - slope * v3(across))
    return p, n


def valve_covers(d):
    c0, c1, half, corner, thick = COVER_FLANGE
    for s in (1, -1):
        o, across, up = rail_frame(s)
        origin = p3(bank_x(s, 0.0), o)
        sk, to2d = d.plane(origin, (1, 0, 0), v3(up), f"Cover flange {s}")
        a, b = to2d(origin + np.array([-half, 0, 0]) + c0 * v3(across)), \
            to2d(origin + np.array([half, 0, 0]) + c1 * v3(across))
        d.rounded(a, b, corner)
        d.finish()
        d.extrude(sk, f"valve_cover_{s}", thick)

        # The body: the section along the middle, each end lofted down through smaller ones.
        e = COVER_END
        xa, xb = bank_x(s, -(COVER_HALF - e)), bank_x(s, COVER_HALF - e)
        sk = d.sketch("YZ", f"Cover {s}", offset=xa)
        d.poly(ccw(cover_section(s)))
        d.finish()
        d.extrude(sk, f"valve_cover_body_{s}", xb - xa)
        for k, (x_in, way) in enumerate(((xa, -1), (xb, 1))):
            sks = []
            for j, (along, kc, kl) in enumerate(COVER_END_SECTIONS):
                sk = d.sketch("YZ", f"Cover {s} end {k} section {j}", offset=x_in + way * along * e)
                d.poly(ccw(cover_section(s, (kc, kl))))
                d.finish()
                sks.append(sk)
            d.loft(f"valve_cover_body_{s} ({10 + 10 * k})", sks)

        # Bolts round the flange.
        sk, to2d = d.plane(origin + thick * v3(up), (1, 0, 0), v3(up), f"Cover bolts {s}")
        for x, c in COVER_BOLTS:
            d.hexagon(to2d(origin + thick * v3(up) + np.array([x, 0, 0]) + c * v3(across)), 0.44)
        d.finish()
        d.extrude(sk, f"valve_bolt_{s}", 0.25)

        # A well over each plug: a raised ring, the dark hole, the wire's boot in it.
        pc, pr = PLUG_WELL
        for i, x in enumerate(BORE_X):
            p, n = cover_top(s, x, pc)
            d.cylinder(f"valve_cover_well_{s}_{i}", p - 0.1 * n, n, 2 * pr + 0.3, 0.25)
            d.cylinder(f"valve_cover_well_hole_{s}_{i}", p + 0.15 * n, n, 2 * pr - 0.05, 0.02)
            d.cylinder(f"spark_plug_boot_{s}_{i}", p - 0.1 * n, n, 0.8, 1.05)
            d.cone(f"spark_plug_boot_{s}_{i} (10)", p + 0.95 * n, n, 0.4, 0.22, 0.6)

        # The oil filler cap on the left cover, the breather on the right.
        x, c = FILLER if s == -1 else BREATHER
        p, n = cover_top(s, x, c)
        if s == -1:
            d.cylinder("valve_cover_filler_neck", p - 0.1 * n, n, 1.5, 0.45)
            d.cylinder("oil_filler_cap", p + 0.35 * n, n, 2.3, 0.5)
        else:
            d.cylinder("valve_cover_breather_neck", p - 0.1 * n, n, 1.3, 0.4)
            d.cylinder("valve_cover_breather", p + 0.3 * n, n, 2.0, 0.7)


# The intake.

def intake_face(s):
    """Bank s's head's intake face: its foot on the deck (y, z), the way up it, and its
    normal toward the valley."""
    return on_head(s, INTAKE_FACE_A, 0.0), bank(s)[0], bank(s)[2]


def runner_port():
    p = on_head(1, INTAKE_FACE_A + INTAKE_FLANGE[2], INTAKE_PORT_H)
    return float(p[0]), float(p[1]), 45.0


def flange_face_y():
    """|y| of the flanges' inner faces at their foot."""
    return on_head(1, INTAKE_FACE_A + INTAKE_FLANGE[2], INTAKE_FLANGE[0])[0]


def intake_levels():
    """The intake's heights: the floor's underside and top, the runners' port height, the
    carb pads' underside."""
    z0 = on_head(1, INTAKE_FACE_A + INTAKE_FLANGE[2], INTAKE_FLANGE[0])[1] - 0.45
    _, zp, _ = runner_port()
    return z0, z0 + INTAKE_FLOOR_T, zp, PAD_Z


def web_under(d, name, x, w, path):
    """The casting under a runner's rise, so it never shows an underside: in the upright
    plane at x, w wide, from the centerline path (y, z) down to the floor and back along it
    to the flange's face."""
    zf = intake_levels()[1] - 0.05
    sgn = 1.0 if path[0][0] > 0 else -1.0
    pts = list(path) + [(path[-1][0], zf), (sgn * flange_face_y(), zf)]
    sk = d.sketch("YZ", f"{name} web", offset=x - w / 2)
    d.poly(ccw([(float(y), float(z)) for y, z in pts]))
    d.finish()
    d.extrude(sk, name, w)


def runner(d, name, x, s, top, w, h, to_y, climb):
    """make_sbf.py's runner, straight in: a square runner with rounded corners from bank
    s's port at x, up and in out of the port at climb degrees, a bend over level, and on
    across into the plenum's side at to_y."""
    yp, zp, _ = runner_port()
    th = math.radians(climb)
    y0, z0 = yp + RUNNER_BURY * math.cos(th), zp - RUNNER_BURY * math.sin(th)
    zc = top - h / 2
    rise = zc - z0
    room = abs(to_y - s * y0)
    fit = (room - rise / math.tan(th)) / (math.sin(th) - (1 - math.cos(th)) / math.tan(th))
    r1 = min(RUNNER_BENDS[0], 0.9 * rise / (1 - math.cos(th)), fit)
    if r1 < 0.15:
        sys.exit(f"{name}: no room to bend over ({room:.2f} in across for a {rise:.2f} in rise)")
    lead = max((rise - r1 * (1 - math.cos(th))) / math.sin(th), 0.05)

    def world(u):
        return [round(float(c) * MM, 4) for c in (x, s * (y0 - u[0]), z0 + u[1])]

    u1 = lead * np.array([math.cos(th), math.sin(th)])
    c = u1 + r1 * np.array([math.sin(th), -math.cos(th)])
    u2 = c + np.array([0.0, r1])
    u3 = np.array([room, u2[1]])
    mid = math.pi / 2 + th / 2
    sk = d.sketch("XY", f"{name} path")
    d.c.append(cmd("sketch.options", sketch_3d=True))
    d.c.append(cmd("sketch.line3d", points=[world((0.0, 0.0)), world(u1)]))
    d.c.append(cmd("sketch.arc3d", start=world(u1), through=world(c + r1 * np.array([math.cos(mid), math.sin(mid)])),
                   end=world(u2)))
    path = ["w1", "w2"]
    if u3[0] - u2[0] > 0.05:
        d.c.append(cmd("sketch.line3d", points=[world(u2), world(u3)]))
        path.append("w3")
    d.finish()
    p0 = np.array([x, s * y0, z0])
    out = np.array([0.0, -s * math.cos(th), math.sin(th)])
    prof, to2d = d.plane(p0, (1, 0, 0), out, f"{name} section")
    cx, cy = to2d(p0)
    d.rounded((cx - w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), RUNNER_CORNER)
    d.finish()
    d.body(name, "solid.sweep", sketch=prof, path_sketch=sk, path=path)
    web_under(d, name.replace("_runner_", "_web_"), x, w, rise_path(y0, z0, s, th, r1, lead, u3[0]))


def floor_outline():
    """The intake's floor from above (x, y), counterclockwise: each half as long as its
    head, the right half stopping short at the front for the distributor, rounded off."""
    from shapely.geometry import box
    fy = flange_face_y() + 0.3
    halves = []
    for s in (1, -1):
        x0, x1 = bank_x(s, -HEAD_HALF) + FLOOR_INSET, bank_x(s, HEAD_HALF) - FLOOR_INSET
        if s == 1:
            x0 = INTAKE_FRONT_RIGHT
        y0, y1 = sorted((0.0, s * fy))
        halves.append(box(x0, y0 - 0.4 * (s == 1), x1, y1 + 0.4 * (s == -1)))
    shape = halves[0].union(halves[1]).buffer(0.35, 4).buffer(-0.7, 4).buffer(0.35, 4).simplify(0.01)
    return ccw([tuple(map(float, q)) for q in list(shape.exterior.coords)[:-1]])


def plenum_outline():
    from shapely.geometry import box
    x0, x1, hy = PLENUM
    lx0, lx1, ly = PLENUM_LOBE
    shape = box(x0, -hy, x1, hy).union(box(lx0, -hy, lx1, ly))
    shape = shape.buffer(-0.9, 4).buffer(0.9, 4).buffer(0.4, 4).buffer(-0.4, 4).simplify(0.01)
    return ccw([tuple(map(float, q)) for q in list(shape.exterior.coords)[:-1]])


def intake(d):
    z0, z1, zp, pad_z = intake_levels()
    nm = "intake_manifold"
    sk = d.sketch("XY", "Intake floor", offset=z0)
    d.poly(floor_outline())
    d.finish()
    d.extrude(sk, nm, z1 - z0)

    t0, t1, thick = INTAKE_FLANGE
    for s in (1, -1):
        f0, up, n = intake_face(s)
        xa, xb = bank_x(s, -HEAD_HALF) + 0.1, bank_x(s, HEAD_HALF) - 0.1
        if s == 1:
            xa = INTAKE_FRONT_RIGHT
        sk, to2d = d.plane(p3(0.0, f0), (1, 0, 0), v3(n), f"Intake flange {s}")
        d.rounded(to2d(p3(xa, f0 + t0 * up)), to2d(p3(xb, f0 + t1 * up)), 0.3)
        d.finish()
        d.extrude(sk, f"{nm}_flange_{s}", thick)
        bolt = f0 + INTAKE_BOLT_T * up + thick * n
        xs = [bank_x(s, x) for x in INTAKE_BOLT_X if xa + 0.5 < bank_x(s, x) < xb - 0.5]
        sk, to2d = d.plane(p3(0.0, bolt), (1, 0, 0), v3(n), f"Intake bolt bosses {s}")
        for x in xs:
            d.circle(to2d(p3(x, bolt)), 0.48)
        d.finish()
        d.extrude(sk, f"{nm}_bolt_bosses_{s}", 0.15, start_offset=inch(-0.05))
        sk, to2d = d.plane(p3(0.0, bolt), (1, 0, 0), v3(n), f"Intake bolts {s}")
        for x in xs:
            d.hexagon(to2d(p3(x, bolt)), 0.5)
        d.finish()
        d.extrude(sk, f"intake_bolts_{s}", 0.28, start_offset=inch(0.1))

    for k, (i, s, top, w, h, end, climb) in enumerate(INTAKE_RUNNERS):
        runner(d, f"{nm}_runner_{k}", bank_x(s, BORE_X[i]), s, zp + top, w, h, s * end, climb)

    # The plenum along the middle, from the floor up.
    sk = d.sketch("XY", "Plenum", offset=z1 - 0.1)
    d.poly(plenum_outline())
    d.finish()
    d.extrude(sk, f"{nm}_plenum", PLENUM_TOP - z1 + 0.1)

    # Each carb pad, as make_sbf.py's: a neck up off the plenum, its walls round the pad's
    # openings up to the pad, which runs round its studs' bosses.
    px, py, pt = PAD
    floor = pad_z - PLENUM_FLOOR
    for j, cx in enumerate(PADS_X):
        def openings(first):
            (sx0, sy0), (sx1, sy1), sr = PAD_SLOT
            d.c += outline_commands(*hull_outline([((cx + sx0, sy0), sr), ((cx + sx1, sy1), sr)]),
                                    first=first)
            for x, y in PAD_HOLES:
                d.circle((cx + x, y), PAD_HOLE_R)

        sk = d.sketch("XY", f"Pad neck {j}", offset=PLENUM_TOP - 0.1)
        d.rounded((cx - px - 0.1, -py - 0.1), (cx + px + 0.1, py + 0.1), 0.8)
        d.finish()
        d.extrude(sk, f"{nm}_neck ({10 + j})", floor - PLENUM_TOP + 0.1, taper="3 deg")
        corners = [((cx + sx * (px + 0.1 - 0.8), sy * (py + 0.1 - 0.8)), 0.8)
                   for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))]
        sk = d.sketch("XY", f"Plenum walls {j}", offset=floor)
        d.c += outline_commands(*hull_outline(corners))
        openings(5)
        d.finish()
        d.extrude(sk, f"{nm}_plenum_walls ({10 + j})", pad_z - floor)
        sk = d.sketch("XY", f"Plenum floor {j}", offset=floor)
        openings(1)
        d.finish()
        d.extrude(sk, f"{nm}_plenum_floor ({10 + j})", 0.02)
        bosses = [(cx + x, sy * y) for x, y in PAD_BOSSES for sy in (1, -1)]
        sk = d.sketch("XY", f"Carb pad {j}", offset=pad_z)
        mid = np.mean(bosses, axis=0)
        ring = sorted(bosses, key=lambda q: math.atan2(q[1] - mid[1], q[0] - mid[0]))
        d.c += outline_commands(*hull_outline([(q, PAD_BOSS_R) for q in ring]))
        openings(5)
        d.finish()
        d.extrude(sk, f"{nm}_pad ({10 + j})", pt)
        sk = d.sketch("XY", f"Pad bosses {j}", offset=PLENUM_TOP - 0.1)
        for q in bosses:
            d.circle(q, 0.45)
        d.finish()
        d.extrude(sk, f"{nm}_pad_bosses ({10 + j})", pad_z + pt + 0.12 - (PLENUM_TOP - 0.1))


def carburetor(d, x, j):
    """make_sbc.py's square-flange four-barrel on pad j at x; returns its top."""
    z = PAD_Z + PAD[2]
    sfx = f" ({100 + 10 * j})"
    d.box("carburetor_base" + sfx, (x - 2.8, -2.65, z), (x + 2.8, 2.65, z + 0.75))
    z += 0.75
    d.box("carburetor" + sfx, (x - 2.25, -2.5, z), (x + 2.25, 2.5, z + 1.5))
    for end, x0, x1 in (("front", -4.0, -2.25), ("back", 2.25, 4.0)):
        sk = d.sketch("XY", f"Bowl {end} {j}", offset=z - 0.15)
        d.rounded((x + x0, -2.35), (x + x1, 2.35), 0.45)
        d.finish()
        d.extrude(sk, f"carburetor_bowl_{end}" + sfx, 2.55)
        sx = x0 if end == "front" else x1
        d.cylinder(f"carburetor_bowl_screw_{end}" + sfx, (x + sx, 1.6, z + 1.9), (np.sign(sx), 0, 0), 0.4, 0.15)
    z += 1.5
    d.box("carburetor_air_horn" + sfx, (x - 2.25, -2.5, z), (x + 2.25, 2.5, z + 0.35))
    z += 0.35
    sk = d.sketch("XY", f"Air cleaner ring {j}", offset=z)
    d.circle((x, 0), 2.5625)
    d.circle((x, 0), 2.35)
    d.finish()
    d.extrude(sk, "carburetor_ring" + sfx, 0.55)
    for tx in (-0.91, 0.91):
        for ty in (-0.95, 0.95):
            d.cylinder(f"carb_throat_{tx}_{ty}" + sfx, (x + tx, ty, z), (0, 0, 1), 1.56 if tx < 0 else 1.69, 0.04)
    return z + 0.55


def stadium(cx, half, r, n_end=16):
    """An oval (x, y) round the line from cx - half to cx + half, r out, counterclockwise,
    with the outward normals."""
    pts, nrm = [], []
    for k in range(n_end + 1):
        t = -math.pi / 2 + math.pi * k / n_end
        nrm.append((math.cos(t), math.sin(t)))
        pts.append((cx + half + r * math.cos(t), r * math.sin(t)))
    for k in range(n_end + 1):
        t = math.pi / 2 + math.pi * k / n_end
        nrm.append((math.cos(t), math.sin(t)))
        pts.append((cx - half + r * math.cos(t), r * math.sin(t)))
    return pts, nrm


def pleated(cx, half, r, depth, pitch=0.24):
    """The oval at r with pleats depth deep every pitch along it."""
    from shapely.geometry import LineString
    pts, _ = stadium(cx, half, r, 24)
    ring = LineString(pts + [pts[0]])
    n = int(ring.length / pitch) * 2
    out = []
    for k in range(n):
        p = ring.interpolate(ring.length * k / n)
        q = ring.interpolate(ring.length * (k + 0.5) / n)
        tx, ty = q.x - p.x, q.y - p.y
        ln = math.hypot(tx, ty)
        nx, ny = ty / ln, -tx / ln
        dd = 0.0 if k % 2 == 0 else -depth
        out.append((p.x + nx * dd, p.y + ny * dd))
    return out


def air_cleaner(d, zb):
    """One long oval air cleaner over both carburetors: the pan, the pleated element, the
    lid, a stud and wing nut over each carburetor."""
    cx = sum(PADS_X) / 2
    half, r = CLEANER
    pan, _ = stadium(cx, half, r)
    sk = d.sketch("XY", "Air cleaner pan", offset=zb)
    d.poly(ccw(pan))
    d.finish()
    d.extrude(sk, "air_cleaner_base", 0.12)
    sk = d.sketch("XY", "Air cleaner rim", offset=zb + 0.12)
    d.poly(ccw(pan))
    d.poly(ccw(stadium(cx, half, r - 0.15)[0]))
    d.finish()
    d.extrude(sk, "air_cleaner_base (10)", 0.48)
    sk = d.sketch("XY", "Element", offset=zb + 0.12)
    d.poly(ccw(pleated(cx, half, r - 0.3, 0.22)))
    d.poly(ccw(stadium(cx, half, r - 1.1)[0]))
    d.finish()
    d.extrude(sk, "air_cleaner_element", 2.6)
    zl = zb + 2.72
    sk = d.sketch("XY", "Air cleaner lid", offset=zl - 0.45)
    d.poly(ccw(pan))
    d.poly(ccw(stadium(cx, half, r - 0.15)[0]))
    d.finish()
    d.extrude(sk, "air_cleaner_lid", 0.45)
    sk = d.sketch("XY", "Air cleaner lid top", offset=zl)
    d.poly(ccw(pan))
    d.finish()
    d.extrude(sk, "air_cleaner_lid (10)", 0.55, taper="-45 deg")
    for j, x in enumerate(PADS_X):
        d.cylinder(f"air_cleaner_stud ({10 + j})", (x, 0, zl + 0.5), (0, 0, 1), 0.3, 0.6)
        d.cylinder(f"air_cleaner_wingnut ({10 + j})", (x, 0, zl + 0.55), (0, 0, 1), 0.75, 0.5)
        sk = d.sketch("XZ", f"Wing nut {j}", offset=0.0)
        for side in (1, -1):
            d.poly([(x + side * 0.3, -(zl + 0.6)), (x + side * 1.25, -(zl + 0.85)),
                    (x + side * 1.35, -(zl + 1.4)), (x + side * 0.95, -(zl + 1.45)),
                    (x + side * 0.3, -(zl + 1.05))])
        d.finish()
        d.extrude(sk, f"air_cleaner_wingnut_wings ({10 + j})", 0.12, "symmetric")


def clamp_bolt():
    way = unit(CLAMP_WAY)
    return DIST[0] + CLAMP_REACH * way[0], DIST[1] + CLAMP_REACH * way[1]


def distributor(d):
    """Only the outside: its boss up out of the valley's front, the housing, the cap, the
    vacuum advance off to the left, the hold-down clamp."""
    x, y = DIST
    zb0, z = DIST_BOSS
    d.cylinder("engine_block_distributor_boss", (x, y, zb0), (0, 0, 1), 2.3, z - zb0)
    bx, by = clamp_bolt()
    d.cylinder("engine_block_distributor_boss (10)", (bx, by, zb0), (0, 0, 1), 0.95, z - zb0 + 0.25)
    o = np.array([x, y, 0.0])
    d.revolve("distributor_body", o, (0, 0, 1), (1, 0, 0),
              [(z - 0.3, 0.0), (z - 0.3, 0.64), (z + 0.25, 0.64), (z + 0.25, 0.95), (z + 0.45, 0.95),
               (z + 0.45, 0.7), (z + 1.75, 0.7), (z + 1.85, 1.75), (z + 2.15, 1.75), (z + 2.15, 0.0)])
    d.revolve("distributor_cap", o, (0, 0, 1), (1, 0, 0),
              [(z + 2.1, 0.0), (z + 2.1, 1.95), (z + 2.4, 2.02), (z + 2.6, 1.95), (z + 3.7, 1.95),
               (z + 3.95, 1.6), (z + 4.75, 1.62), (z + 4.95, 1.48), (z + 5.05, 1.2), (z + 5.05, 0.0)])
    for k in range(8):
        t = 2 * math.pi * (k + 0.5) / 8
        base = o + np.array([1.15 * math.cos(t), 1.15 * math.sin(t), z + 4.75])
        d.cylinder(f"distributor_cap_tower_{k}", base, (0, 0, 1), 0.62, 0.85)
    d.cylinder("distributor_cap_coil_tower", o + np.array([0, 0, z + 4.85]), (0, 0, 1), 0.72, 1.05)
    arm = unit(DIST_VACUUM)
    za = z + 1.8
    d.cylinder("distributor_vacuum_arm", o + np.array([0, 0, za]) + 0.6 * arm, arm, 0.6, 0.8)
    d.cylinder("distributor_vacuum", o + np.array([0, 0, za]) + 1.35 * arm, arm, 2.2, 1.1)
    d.cone("distributor_vacuum_end", o + np.array([0, 0, za]) + 2.45 * arm, arm, 1.1, 0.6, 0.35)
    d.cylinder("distributor_vacuum_nipple", o + np.array([0, 0, za]) + 2.8 * arm, arm, 0.25, 0.45)
    way = unit(CLAMP_WAY)
    sk = d.sketch("XY", "Distributor clamp", offset=z + 0.45)
    d.c += outline_commands(*hull_outline([((x + 0.55 * way[0], y + 0.55 * way[1]), 0.35), ((bx, by), 0.35)]))
    d.finish()
    d.extrude(sk, "distributor_clamp", 0.2)
    d.cylinder("distributor_clamp_bolt", (bx, by, z + 0.65), (0, 0, 1), 0.55, 0.3)


def coil(d):
    """The coil standing on its bracket off the left head's front."""
    x, y, z = COIL
    d.revolve("ignition_coil", (x, y, 0.0), (0, 0, 1), (1, 0, 0),
              [(z, 0.0), (z, 1.05), (z + 4.9, 1.05), (z + 5.1, 1.15), (z + 5.45, 1.15),
               (z + 5.55, 0.95), (z + 5.55, 0.0)])
    d.revolve("ignition_coil_tower", (x, y, 0.0), (0, 0, 1), (1, 0, 0),
              [(z + 5.5, 0.0), (z + 5.5, 0.42), (z + 6.05, 0.38), (z + 6.15, 0.25), (z + 6.15, 0.0)])
    d.revolve("ignition_coil_bracket", (x, y, 0.0), (0, 0, 1), (1, 0, 0),
              [(z + 1.8, 1.0), (z + 1.8, 1.17), (z + 2.5, 1.17), (z + 2.5, 1.0)])
    head = bank_x(-1, -HEAD_HALF)
    d.box("ignition_coil_strap", (x + 1.0, y - 0.5, z + 1.9), (head + 0.05, y + 0.5, z + 2.3))


# Exhaust manifolds and headers.

def primaries(d, s, front, axis, name, dia, out, mid_z, spread, lean=PRIMARY_LEAN, direct=()):
    """Four tubes from bank s's ports, each out of its port, bent down to mid_z and then
    one bend back into a mouth at front, the four mouths two by two, spread apart, round
    the collector's axis. Those in direct (counted front to back) bend once out of their
    port and run straight to their mouth instead."""
    n = v3(exhaust_face(s)[2])
    pc = port_center(s)
    xs = port_xs(s)
    across = unit(np.cross(axis, [0, 0, 1])) if abs(axis[2]) < 0.99 else np.array([0, 1, 0])
    upv = np.cross(across, axis)
    mouths = [front + spread * (i * across + j * upv) for i, j in ((-1, 1), (1, 1), (-1, -1), (1, -1))]
    ports = [p3(x, pc) for x in xs]
    order = sorted(range(4), key=lambda k: ports[k][0])
    mouth_order = sorted(range(4), key=lambda k: (mouths[k][0], -s * mouths[k][1]))
    for k_port, k_mouth in zip(order, mouth_order):
        p0, target = ports[k_port], mouths[k_mouth]
        if order.index(k_port) in direct:
            e1, e2, (a0, a1, c, q, t) = tube_path(p0, n, target, out[0], out[1])
            nm = f"{name}_{s}_{k_port}_0"
            sk, _ = d.plane(p0, e1, np.cross(e1, e2), f"{nm} path")
            d.c.append(cmd("sketch.line", infer=False, points=[skp(*a0), skp(*a1)]))
            d.c.append(cmd("sketch.arc.center_point", center=skp(*c), start="l1.end", end=skp(*q)))
            d.c.append(cmd("sketch.line", infer=False, points=["a1.end", skp(*t)]))
            d.finish()
            d.body(nm, "solid.pipe", path_sketch=sk, path=["l1", "a1", "l2"], diameter=inch(dia))
            continue
        dropv = unit([lean[order.index(k_port)], 0.0, -1.0])
        corner = p0 + (out[0] + out[1]) * n
        mid = corner + (corner[2] - mid_z) * dropv / -dropv[2]
        down = None
        # The bend back into the mouth is kept inside the room there is: a back port's drop
        # ends close to its mouth, and a bend wider than that makes no tube at all.
        back = min(3.0, 0.4 * float(np.linalg.norm(target - mid)))
        for part, (start, out_dir, end, lead, radius) in enumerate((
                (p0, n, mid, out[0], out[1]), (mid, None, target, 0.05, back))):
            if out_dir is None:
                out_dir = down
            e1, e2, (a0, a1, c, q, t) = tube_path(start, out_dir, end, lead, radius)
            down = unit(end - (start + q[0] * e1 + q[1] * e2))
            nm = f"{name}_{s}_{k_port}_{part}"
            sk, _ = d.plane(start, e1, np.cross(e1, e2), f"{nm} path")
            d.c.append(cmd("sketch.line", infer=False, points=[skp(*a0), skp(*a1)]))
            d.c.append(cmd("sketch.arc.center_point", center=skp(*c), start="l1.end", end=skp(*q)))
            d.c.append(cmd("sketch.line", infer=False, points=["a1.end", skp(*t)]))
            d.finish()
            d.body(nm, "solid.pipe", path_sketch=sk, path=["l1", "a1", "l2"], diameter=inch(dia))


def iron_manifolds(d):
    """Cast iron, shaped like headers as the 1966 photo's: a flange on each port's pad, a
    thick runner out of each, down and back into a cast collector behind the back port,
    its outlet down and back to a round two-bolt flange."""
    (cx, cy, cz), axis = MANIFOLD_COLLECTOR
    axis = unit(axis)
    for s in (1, -1):
        _, up, n = exhaust_face(s)
        pc = port_center(s)
        sk, to2d = d.plane(p3(0.0, pc), (1, 0, 0), v3(n), f"Manifold flanges {s}")
        first = 1
        for x in port_xs(s):
            pts = [(np.array(to2d(p3(x + dx, pc + v * up))), rr) for dx, v, rr in PORT_PAD]
            c = sum(p for p, _ in pts) / len(pts)
            pts.sort(key=lambda pr: math.atan2(*(pr[0] - c)[::-1]))
            d.c += outline_commands(*hull_outline([(tuple(p), rr) for p, rr in pts]), first=first)
            first += len(pts)
        d.finish()
        d.extrude(sk, f"exhaust_manifold_{s}", MANIFOLD_FLANGE_T, start_offset=inch(PORT_PAD_T))

        front = np.array([bank_x(s, cx), s * cy, cz])
        primaries(d, s, front, axis, "exhaust_manifold_runner", MANIFOLD_RUNNER_D, MANIFOLD_OUT,
                  MANIFOLD_MID_Z, 0.75, MANIFOLD_LEAN, direct=(2, 3))
        r0, r1, length = MANIFOLD_FLARE
        d.cone(f"exhaust_manifold_collector_{s}", front - (length - 1.6) * axis, axis, r0, r1, length)
        d.cylinder(f"exhaust_manifold_outlet_{s}", front + 2.0 * axis, axis, 2.2, 1.2)
        end = front + 3.2 * axis
        across = unit(np.cross(axis, [0, 0, 1]))
        sk, to2d = d.plane(end, across, axis, f"Manifold outlet flange {s}")
        o = to2d(end)
        d.c += outline_commands(*hull_outline([((o[0], o[1] - 0.35), 1.15), ((o[0] + 1.85, o[1]), 0.42),
                                               ((o[0], o[1] + 0.35), 1.15), ((o[0] - 1.85, o[1]), 0.42)]))
        d.circle(o, MANIFOLD_OUTLET_D / 2 - 0.2)
        d.finish()
        d.extrude(sk, f"exhaust_manifold_outlet_flange_{s}", 0.4)
        d.cylinder(f"exhaust_manifold_bore_{s}", end - 0.6 * axis, axis, MANIFOLD_OUTLET_D - 0.45, 0.02)


def headers(d, style):
    """make_sbf.py's headers on these heads: a flange over the four ports, four primaries
    out of them, each down and one bend back into a merge cone and collector."""
    (cx, cy, cz), axis = COLLECTOR[style]
    axis = unit(axis)
    for s in (1, -1):
        n = v3(exhaust_face(s)[2])
        pc = port_center(s)
        xs = port_xs(s)
        sk, to2d = d.plane(p3(0.0, pc), (1, 0, 0), n, f"Header flange {s}")
        a, b = to2d(p3(min(xs) - 1.9, pc)), to2d(p3(max(xs) + 1.9, pc))
        d.rounded((min(a[0], b[0]), a[1] - 0.85), (max(a[0], b[0]), a[1] + 0.85), 0.3)
        d.finish()
        d.extrude(sk, f"exhaust_flange_{s}", 0.375)
        front = np.array([bank_x(s, cx), s * cy, cz])
        primaries(d, s, front, axis, "exhaust_runner", PRIMARY_D, PRIMARY_OUT, PRIMARY_MID_Z, 0.7)
        d.cone(f"exhaust_collector_{s}", front - 0.4 * axis, axis, 2.3, 1.6, 3.6)
        d.cylinder(f"exhaust_collector_pipe_{s}", front + 3.2 * axis, axis, 3.2, 3.0)
        d.cylinder(f"exhaust_collector_flange_{s}", front + 6.2 * axis, axis, 4.8, 0.375)


# The front of the engine.

def front(d):
    def turned(name, yz, profile):
        d.revolve(name, p3(0.0, yz), (1, 0, 0), (0, 0, 1), profile)

    # Timing cover over the block's front, round the crank and up to the pump housing's pad.
    sk = d.sketch("YZ", "Timing cover", offset=BLOCK_FRONT)
    d.c += outline_commands(*hull_outline(TIMING_COVER))
    d.finish()
    d.extrude(sk, "timing_cover", BLOCK_FRONT - COVER_SEAL_X, "negative")
    sk = d.sketch("YZ", "Timing cover pump pad", offset=COVER_SEAL_X)
    d.c += outline_commands(*hull_outline(PUMP_PAD))
    d.finish()
    d.extrude(sk, "timing_cover_pad", COVER_SEAL_X - COVER_FACE, "negative")

    # The water pump: the body on the pad, the snout, the hub; its inlet low on the left,
    # the heater fitting on the right; the thermostat housing on top, its neck forward.
    py, pz = PUMP
    sk = d.sketch("YZ", "Water pump", offset=COVER_FACE)
    d.c += outline_commands(*hull_outline(PUMP_BODY))
    d.finish()
    d.extrude(sk, "water_pump_housing", COVER_FACE - PUMP_FACE, "negative")
    d.cone("water_pump_snout", (PUMP_FACE, py, pz), (-1, 0, 0), 2.3, 1.1, PUMP_FACE - BELT_BACK + 1.2)
    hose_neck(d, "water_pump_inlet", np.array([PUMP_FACE + 0.6, -2.6, 6.6]), unit([-0.3, -0.7, -0.65]),
              0.85, 0.68, 3.0, 1.5)
    hose_neck(d, "water_pump_heater", np.array([PUMP_FACE + 0.3, 2.4, 11.2]), unit([-0.6, 0.35, 0.72]),
              0.4, 0.27, 1.3, 0.8)
    tx, ty = THERMOSTAT
    seat = pz + math.sqrt(PUMP_BODY[2][1] ** 2 - ty ** 2) - 0.3
    d.cylinder("thermostat_housing", (tx, ty, seat), (0, 0, 1), 2.2, 0.5)
    d.revolve("thermostat_dome", (tx, ty, 0.0), (0, 0, 1), (1, 0, 0),
              [(seat + 0.45, 0.0), (seat + 0.45, 1.0), (seat + 0.95, 0.95), (seat + 1.3, 0.75), (seat + 1.45, 0.0)])
    neck = np.array([tx, ty, seat + 0.8])
    dirn = unit([-0.75, 0.0, 0.66])
    hose_neck(d, "thermostat_neck", neck, dirn, 0.72, 0.56, 2.1, 1.3)
    d.cylinder("thermostat_bead", neck + 1.6 * dirn, dirn, 1.6, 0.16)

    # The balancer and the crank pulley, turned about the crank.
    b0, b1 = BALANCER
    turned("harmonic_balancer", (0.0, 0.0),
           [(COVER_SEAL_X, 0.0), (COVER_SEAL_X, 1.3), (b0, 1.3), (b0, BALANCER_R), (b1, BALANCER_R), (b1, 0.0)])
    turned("harmonic_balancer_ring", (0.0, 0.0),
           [(b0 - 0.35, BALANCER_R - 0.75), (b0 - 0.35, BALANCER_R + 0.01), (b0 - 0.5, BALANCER_R + 0.01),
            (b0 - 0.5, BALANCER_R - 0.75)])
    rim, x_front = grooves(BELT_BACK, 2, CRANK_PULLEY_R, CRANK_PULLEY_R - 0.42)
    turned("crank_pulley", (0.0, 0.0), [(b1, 0.0), (b1, CRANK_PULLEY_R)] + rim + [(x_front, 0.0)])
    turned("crank_bolt", (0.0, 0.0), [(x_front, 0.0), (x_front, 0.55), (x_front - 0.5, 0.55),
                                       (x_front - 0.5, 0.0)])

    # The pump's pulley, dished forward to its web on the hub, the fan on a spacer.
    rim, x_front = grooves(BELT_BACK, 2, PUMP_PULLEY_R, PUMP_PULLEY_R - 0.42)
    turned("upper_pulley", PUMP, [(BELT_BACK, PUMP_PULLEY_R - 0.55)] + rim
           + [(x_front, 0.6), (x_front + 0.2, 0.6), (x_front + 0.2, PUMP_PULLEY_R - 0.55)])
    d.cylinder("fan_spacer", (x_front, py, pz), (-1, 0, 0), 2.5, x_front - FAN_X - 0.1)
    d.cylinder("fan_hub", (FAN_X + 0.08, py, pz), (-1, 0, 0), 5.0, 0.16)
    center = np.array([FAN_X, py, pz])
    sections = [(2.1, 0.95, 38), (5.5, 1.8, 30), (8.0, 2.05, 23), (FAN_R, 1.35, 20)]
    for k in range(4):
        t = math.radians(45 + 90 * k)
        radial = np.array([0.0, math.cos(t), math.sin(t)])
        tangent = np.array([0.0, -math.sin(t), math.cos(t)])
        sketches = []
        for j, (r, half, pitch) in enumerate(sections):
            p = math.radians(pitch)
            chord = math.cos(p) * tangent + math.sin(p) * np.array([-1.0, 0, 0])
            across = np.cross(radial, chord)
            mid = center + r * radial
            sk, to2d = d.plane(mid, tangent, radial, f"Fan blade {k} section {j}")
            pts = [mid + half * chord, mid + 0.4 * half * chord + 0.09 * across,
                   mid - 0.4 * half * chord + 0.09 * across, mid - half * chord,
                   mid - 0.4 * half * chord - 0.04 * across, mid + 0.4 * half * chord - 0.04 * across]
            d.poly([to2d(q) for q in pts])
            d.finish()
            sketches.append(sk)
        d.loft(f"fan_blades_{k}", sketches)

    alternator(d)
    fuel_pump(d)

    # The belt round crank, alternator and pump, in the back grooves.
    belt_x = BELT_BACK - 0.1 - 0.3
    ring = [((0.0, 0.0), CRANK_PULLEY_R - 0.2), (ALTERNATOR, ALT_PULLEY_R - 0.2), (PUMP, PUMP_PULLEY_R - 0.2)]
    sk = d.sketch("YZ", "Belt", offset=belt_x)
    d.c += outline_commands(*hull_outline(ring))
    d.c += outline_commands(*hull_outline([(c, r + 0.33) for c, r in ring]), first=len(ring) + 1)
    d.finish()
    d.extrude(sk, "belt", 0.5, "symmetric")


def alternator(d):
    """make_sbc.py's alternator, high on the right as the sculpt's."""
    ay, az = ALTERNATOR
    sh = BELT_BACK + 13.0       # make_sbc.py's pulley stands at -13.0

    def turned(name, profile):
        d.revolve(name, p3(0.0, (ay, az)), (1, 0, 0), (0, 0, 1), [(x + sh, r) for x, r in profile])

    turned("alternator_pulley", [(-13.0, 0.0), (-13.0, ALT_PULLEY_R), (-13.12, ALT_PULLEY_R),
                                 (-13.32, ALT_PULLEY_R - 0.4), (-13.42, ALT_PULLEY_R - 0.4),
                                 (-13.62, ALT_PULLEY_R), (-13.72, ALT_PULLEY_R), (-13.72, 0.0)])
    turned("alternator_nut", [(-13.72, 0.0), (-13.72, 0.42), (-14.05, 0.42), (-14.05, 0.0)])
    d.cylinder("alternator_fan", (-12.62 + sh, ay, az), (-1, 0, 0), 4.7, 0.07)
    sk = d.sketch("YZ", "Alternator fan vanes", offset=-12.69 + sh)
    for i in range(10):
        t0 = 2 * math.pi * i / 10
        pts = []
        for r, dt, w in ((1.15, 0.0, -0.08), (2.3, 0.42, -0.08), (2.3, 0.42, 0.08), (1.15, 0.0, 0.08)):
            t = t0 + dt
            pts.append((ay + r * math.cos(t) - w * math.sin(t), az + r * math.sin(t) + w * math.cos(t)))
        d.poly(ccw(pts))
    d.finish()
    d.extrude(sk, "alternator_fan_vanes", 0.3, "negative")
    turned("alternator", [(-12.62, 0.0), (-12.62, 2.75), (-12.35, 3.15), (-11.2, 3.15), (-11.2, 0.0)])
    turned("alternator_stator", [(-11.2, 0.0), (-11.2, 3.35), (-10.6, 3.35), (-10.6, 0.0)])
    turned("alternator_back", [(-10.6, 0.0), (-10.6, 3.1), (-10.1, 3.0), (-9.9, 2.55),
                               (-9.9, 1.0), (-9.8, 1.0), (-9.8, 0.0)])
    sk = d.sketch("YZ", "Alternator vents", offset=-12.64 + sh)
    for k in range(8):
        t = 2 * math.pi * (k + 0.5) / 8
        c, s_ = math.cos(t), math.sin(t)
        pts = []
        for r, w in ((1.2, -0.28), (2.45, -0.4), (2.45, 0.4), (1.2, 0.28)):
            pts.append((ay + r * c - w * s_, az + r * s_ + w * c))
        d.poly(ccw(pts))
    d.finish()
    d.extrude(sk, "alternator_vents", 0.04, "negative")
    for name, ang, x0, x1 in (("alternator_ear_pivot", -125, -12.5, -11.7),
                              ("alternator_ear_adjust", 20, -12.3, -11.9)):
        t = math.radians(ang)
        c, s_ = math.cos(t), math.sin(t)
        sk = d.sketch("YZ", name, offset=x1 + sh)
        d.c += outline_commands(*hull_outline([((ay + 2.2 * c, az + 2.2 * s_), 0.75),
                                                ((ay + 3.65 * c, az + 3.65 * s_), 0.48)]))
        d.finish()
        d.extrude(sk, name, x1 - x0, "negative")
    t = math.radians(-125)
    ear = (ay + 3.65 * math.cos(t), az + 3.65 * math.sin(t))
    sk = d.sketch("YZ", "Alternator bracket", offset=COVER_FACE)
    d.c += outline_commands(*hull_outline([(ear, 0.6), (PUMP_PAD[1][0], 0.7)]))
    d.finish()
    d.extrude(sk, "accessory_bracket_right", 0.3, "negative")


def fuel_pump(d):
    """The mechanical fuel pump on the right front of the block, its body out to the
    right, the domed bowl, a line fitting front and back."""
    x, y, z = FUEL_PUMP
    d.cylinder("fuel_pump_mount", (x, y - 0.3, z), (0, 1, 0), 2.4, 0.9)
    d.cylinder("fuel_pump", (x, y + 0.6, z), (0, 1, 0), 2.9, 0.9)
    d.revolve("fuel_pump_bowl", (x, y + 1.5, z), (0, 1, 0), (0, 0, 1),
              [(0.0, 0.0), (0.0, 1.45), (0.4, 1.4), (0.75, 1.05), (0.85, 0.0)])
    for k, dx in enumerate((-1.0, 1.0)):
        d.cylinder(f"fuel_pump_fitting_{k}", (x, y + 1.0, z), (dx, 0, 0), 0.35, 1.9)


# The bottom.

def bottom(d):
    fx, ft, fr = FLYWHEEL
    d.cylinder("flywheel", (fx, 0, 0), (1, 0, 0), 2 * fr, ft)
    d.cylinder("flywheel_crank_flange", (BLOCK_BACK, 0, 0), (1, 0, 0), 3.6, fx - BLOCK_BACK)
    d.cylinder("flywheel_hub", (fx + ft, 0, 0), (1, 0, 0), 3.2, 0.3)

    # The starter on the right, low: the motor, its end cap, the nose back to the
    # bellhousing, the solenoid on top.
    sy, sz = STARTER
    d.cylinder("starter", (3.2, sy, sz), (1, 0, 0), 4.5, 5.9)
    d.cylinder("starter_end", (2.9, sy, sz), (1, 0, 0), 3.7, 0.3)
    d.cone("starter_nose", (9.1, sy, sz), (1, 0, 0), 1.8, 1.4, fx - 9.1)
    d.box("starter_nose_mount", (fx - 1.6, sy - 1.7, sz - 1.5), (fx - 0.2, sy + 0.3, sz + 1.7))
    d.cylinder("starter_solenoid", (4.6, sy + 0.4, sz + 2.2), (1, 0, 0), 2.0, 3.4)

    # Oil pan: the flange on the rail, the pan below in its side profile, the drain plug.
    x0, x1 = PAN_FLANGE
    sk = d.sketch("XY", "Pan flange", offset=RAIL_Z)
    d.rounded((x0, -PAN_FLANGE_Y), (x1, PAN_FLANGE_Y), 0.6)
    d.finish()
    d.extrude(sk, "oil_pan", 0.16, "negative")
    sk = d.sketch("XZ", "Pan", offset=0.0)
    d.poly(ccw([(x, -z) for x, z in PAN_PROFILE]))
    d.finish()
    d.extrude(sk, "oil_pan_body", 2 * PAN_Y, "symmetric")
    bx, bz = PAN_DRAIN
    d.cylinder("oil_pan_drain", (bx, 0.0, bz), (0, 0, -1), 0.9, 0.3)

    # The oil pump low on the block's left front, the filter on its cover pointing down
    # and out.
    ox, oy, oz = OIL_FILTER
    dirn = unit(OIL_FILTER_DIR)
    d.cylinder("engine_block_oil_pump", (ox, oy, oz) - 1.3 * dirn, dirn, 3.2, 1.35)
    d.cylinder("oil_filter_adapter", (ox, oy, oz), dirn, 2.9, 0.4)
    across = unit(np.cross(dirn, [1.0, 0, 0]))
    d.revolve("oil_filter", np.array([ox, oy, oz]) + 0.4 * dirn, dirn, across,
              [(0.0, 0.0), (0.0, 1.68), (0.15, 1.83), (4.9, 1.83), (5.13, 1.62), (5.2, 0.0)])


# Run inside Blender: thin each body to a budget by its size, as make_sbc.py does.
# Small round parts: SolidCraft meshes a cylinder in rows of 128 facets however small it is.
ROUND = "r0.35"
SMALL = "r0.08"
REDUCE_FACTORS = [
    ("cylinder_head_1_bosses", SMALL), ("cylinder_head_-1_bosses", SMALL), ("spark_plug_boot", SMALL),
    ("valve_cover_well", SMALL), ("air_cleaner_stud", SMALL), ("air_cleaner_wingnut", SMALL),
    ("engine_block_distributor", SMALL), ("intake_manifold_pad_bosses", SMALL),
    ("intake_manifold_bolt_bosses", SMALL), ("intake_manifold_plenum_walls", ROUND), ("fuel_pump_fitting", SMALL),
    ("thermostat_neck", SMALL), ("thermostat_bead", SMALL), ("water_pump_heater", SMALL), ("water_pump_inlet", SMALL),
    ("distributor_cap_tower", SMALL), ("distributor_cap_coil", SMALL), ("distributor_vacuum", SMALL),
    ("carb_throat", SMALL), ("carburetor_bowl_screw", SMALL), ("oil_filter", "r0.15"), ("ignition_coil", "r0.15"),
    ("exhaust_manifold_runner", "r0.08"), ("exhaust_manifold_collector", "r0.15"),
    ("exhaust_manifold_outlet_flange", 0), ("exhaust_manifold_outlet", "r0.15"),
    ("engine_block_deck", 0), ("engine_block_oil_pump", ROUND), ("engine_block_distributor", ROUND),
    ("engine_block_", 1), ("engine_block", 0), ("valley_cover", 0),
    ("cylinder_head", 0), ("valve_cover_body", 0), ("valve_cover_well", ROUND), ("spark_plug_boot", ROUND),
    ("head_bolts", 0), ("exhaust_port_bolts", 0),
    ("valve_cover_breather", ROUND), ("valve_cover_filler", ROUND), ("oil_filler", ROUND),
    ("air_cleaner_element", 0), ("alternator_fan_vanes", 0), ("air_cleaner_stud", ROUND),
    ("air_cleaner_wingnut", ROUND), ("air_cleaner", 0),
    ("crank_pulley", ROUND), ("upper_pulley", ROUND), ("alternator", ROUND), ("harmonic_balancer", ROUND),
    ("crank_bolt", ROUND), ("distributor_clamp", 1), ("distributor", ROUND), ("ignition_coil_strap", 1),
    ("ignition_coil", ROUND), ("oil_filter", ROUND), ("thermostat", ROUND),
    ("starter_nose_mount", 1), ("starter", ROUND),
    ("flywheel", ROUND), ("fan_spacer", ROUND), ("fan_hub", ROUND), ("water_pump_snout", ROUND),
    ("water_pump_inlet", ROUND), ("water_pump_heater", ROUND), ("fuel_pump", ROUND),
    ("carburetor_ring", ROUND), ("carb_throat", ROUND), ("carburetor_bowl_screw", ROUND),
    ("exhaust_collector", ROUND), ("exhaust_runner", "r0.08"), ("exhaust_manifold_outlet_flange", 0),
    ("exhaust_manifold_bore", ROUND), ("exhaust_manifold", "r0.2"),
    ("intake_manifold_runner", "r0.12"), ("intake_manifold_web", 0),
    ("intake_manifold_bolt_bosses", ROUND), ("intake_manifold_pad_bosses", ROUND),
    ("intake_manifold_pad", 0), ("intake_manifold_plenum", 0), ("intake_manifold_neck", 0),
    ("fan_blades", 2), ("belt", 3), ("oil_pan_body", 0), ("oil_pan_drain", ROUND),
]

FINISHES = [
    ("engine_block_deck_holes", BLACK), ("engine_block_deck", MACHINED), ("cylinder_bores", MACHINED),
    ("piston", CAST_ALUMINUM),
    ("cylinder_head_1_ports", BLACK), ("cylinder_head_-1_ports", BLACK),
    ("exhaust_port_bolts", STEEL), ("head_bolts", STEEL),
    ("valve_bolt", STEEL), ("valve_cover_well_hole", BLACK), ("valve_cover_breather", BLACK),
    ("oil_filler", BLACK), ("valve_cover", CRINKLE), ("spark_plug_boot", RUBBER),
    ("freeze_plug", STEEL),
    ("intake_bolts", STEEL), ("intake_manifold_plenum_floor", BLACK),
    ("thermostat_neck_bore", BLACK), ("water_pump_inlet_bore", BLACK), ("water_pump_heater_bore", BLACK),
    ("exhaust_manifold_bore", BLACK), ("exhaust_manifold", CAST_IRON), ("exhaust", HEADER),
    ("ignition_coil_strap", STEEL), ("ignition_coil", BLACK),
    ("carb_throat", BLACK), ("carburetor", ZINC),
    ("air_cleaner_element", FILTER), ("air_cleaner_wingnut", CHROME), ("air_cleaner", BLACK),
    ("distributor_cap", BLACK), ("distributor", STEEL),
    ("harmonic_balancer_ring", RUBBER), ("harmonic_balancer", BLACK), ("crank_pulley", BLACK),
    ("crank_bolt", STEEL), ("upper_pulley", BLACK), ("alternator_pulley", STEEL),
    ("fan_spacer", STEEL), ("fan", BLACK), ("belt", RUBBER),
    ("alternator_stator", STEEL), ("alternator_fan", STEEL), ("alternator_vents", BLACK),
    ("alternator", CAST_ALUMINUM), ("accessory_bracket", BLACK),
    ("fuel_pump_bowl", STEEL), ("fuel_pump_fitting", STEEL), ("fuel_pump", CAST_IRON),
    ("starter_nose", CAST_ALUMINUM), ("starter", BLACK),
    ("flywheel", STEEL), ("oil_filter", FILTER_CAN), ("oil_pan_drain", STEEL),
]


def dome(center, axis, r, h, rings=4, n=36):
    """A piston's dome: a low cap r across standing h up off center along axis."""
    a = unit(axis)
    e1, e2 = em.frame(a)
    c = np.asarray(center, float)
    pts, nrm = [c + h * a], [a]
    for k in range(1, rings + 1):
        f = k / rings
        rr, hh = r * f, h * (1 - f * f)
        slope = 2 * h * f / r
        for t in np.linspace(0, 2 * math.pi, n, endpoint=False):
            radial = math.cos(t) * e1 + math.sin(t) * e2
            pts.append(c + rr * radial + hh * a)
            nrm.append(unit(a + slope * radial))
    tris = [[0, 1 + j, 1 + (j + 1) % n] for j in range(n)]
    for k in range(rings - 1):
        b0, b1 = 1 + k * n, 1 + (k + 1) * n
        for j in range(n):
            j2 = (j + 1) % n
            tris += [[b0 + j, b1 + j, b1 + j2], [b0 + j, b1 + j2, b0 + j2]]
    return em.orient(np.array(pts), np.array(nrm), tris)


def internals_meshes():
    """{name: mesh} in inches for what shows with the heads off: the bores, the domed
    pistons, the deck's holes; on the heads' intake faces, the ports and bolt holes."""
    out, walls, floors = {}, [], []
    cut = bore_cut()
    for s in (1, -1):
        u = v3(bank(s)[0])
        for i, x in enumerate(BORE_X):
            depth = em.piston_depth(throw_angle(s, i), STROKE, ROD)
            c = p3(bank_x(s, x), on_head(s, DECK_OUT, 0.0))
            wall, piston = em.bore_and_piston(c, u, BORE, depth, cut)
            walls.append(wall)
            out[f"piston_{s}_{i + 1}"] = em.merge([piston, dome(c - u * depth, u, BORE / 2 * DOME[0], DOME[1])])
        for x, a, r in deck_holes():
            floors.append(em.disc(p3(bank_x(s, x), on_head(s, a, 0.004)), u, r * 0.95, 10))

        inn = v3(bank(s)[2])
        ports = []
        hl, hh, cr = INTAKE_PORT
        for x in BORE_X:
            ports.append(em.rounded_rect(p3(bank_x(s, x), on_head(s, INTAKE_FACE_A + 0.004, INTAKE_PORT_H)),
                                         inn, (1, 0, 0), hl, hh, cr))
        for x in INTAKE_BOLT_X:
            ports.append(em.disc(p3(bank_x(s, x), on_head(s, INTAKE_FACE_A + 0.004, INTAKE_BOLT_T)), inn, 0.2, 8))
        out[f"cylinder_head_{s}_ports"] = em.merge(ports)
    out.update({"cylinder_bores": em.merge(walls), "engine_block_deck_holes": em.merge(floors)})
    return out


def reduce_obj(src, dst, blender):
    r = subprocess.run([blender, "-b", "--factory-startup", "--python-expr", BLENDER_REDUCE,
                        "--", src, dst, json.dumps(REDUCE_FACTORS)], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(dst):
        sys.exit(f"blender: {r.stderr.strip() or r.stdout.strip()}")


def finish_for(name):
    for prefix, mat in FINISHES:
        if name.startswith(prefix):
            return mat
    return HEMI_ORANGE


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("what", nargs="?", default="engine", choices=("engine", "headers"),
                    help="the whole engine with its cast-iron manifolds (default), or a set of headers alone")
    ap.add_argument("--headers", default="long", choices=sorted(COLLECTOR),
                    help="which headers: long tubes (default) or shorties")
    ap.add_argument("--sc", help="design file (default resources/engines/STEM.sc)")
    ap.add_argument("--glb", help="mesh (default assets/parts/STEM.glb)")
    ap.add_argument("--obj", help="also keep SolidCraft's unthinned OBJ here (for comparing to the reference)")
    ap.add_argument("--solidcraft", default="solidcraft-cli",
                    help="solidcraft-cli, or the SolidCraft AppImage")
    ap.add_argument("--blender", default="blender", help="Blender, which thins the mesh")
    args = ap.parse_args()
    stem = STEM if args.what == "engine" else f"hemi-426-headers-{args.headers}"
    sc = os.path.abspath(args.sc or os.path.join(ROOT, "resources", "engines", stem + ".sc"))
    glb = os.path.abspath(args.glb or os.path.join(ROOT, "assets", "parts", stem + ".glb"))
    tool = shutil.which(args.solidcraft) or args.solidcraft
    if not os.path.exists(tool):
        sys.exit(f"no SolidCraft command line at {args.solidcraft}")
    blender = shutil.which(args.blender) or args.blender
    if not os.path.exists(blender):
        sys.exit(f"no Blender at {args.blender}")

    d = Hemi()
    if args.what == "headers":
        headers(d, args.headers)
    else:
        block(d)
        deck(d)
        heads(d)
        valve_covers(d)
        intake(d)
        air_cleaner(d, max(carburetor(d, x, j) for j, x in enumerate(PADS_X)))
        distributor(d)
        coil(d)
        iron_manifolds(d)
        front(d)
        bottom(d)

    with tempfile.TemporaryDirectory() as tmp:
        obj = os.path.join(tmp, "engine.obj")
        d.c.append(cmd("file.export_obj", path=obj))
        script = os.path.join(tmp, "engine.json")
        with open(script, "w") as f:
            json.dump({"commands": d.c}, f)
        os.makedirs(os.path.dirname(sc), exist_ok=True)
        print(f"building {stem}")
        SolidCraft(tool).run(script, "--save", sc)
        if args.obj:
            shutil.copy(obj, args.obj)
        print("thinning the mesh")
        thin = os.path.join(tmp, "thin.obj")
        reduce_obj(obj, thin, blender)
        bodies = read_tris(thin)
    # SolidCraft can skip a body it cannot make without failing the run: name any missing.
    made = {n.replace(" ", "_") for n in bodies}
    wanted = {c["params"]["body_name"] for c in d.c if "body_name" in c.get("params", {})}
    missing = sorted(w for w in wanted if w.replace(" ", "_") not in made)
    if missing:
        print("missing bodies: " + ", ".join(missing))

    merged = {}
    for name, (p, t) in bodies.items():
        p, nr, i = crease_normals(p, t)
        base = re.sub(r"([ _]\(\d+\))+$", "", name)
        if base in merged:
            mp, mn, mi = merged[base]
            merged[base] = (np.vstack([mp, p]), np.vstack([mn, nr]), np.concatenate([mi, i + len(mp)]))
        else:
            merged[base] = (p, nr, i)
    if args.what == "engine":
        merged.update(em.to_mm(internals_meshes()))
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
