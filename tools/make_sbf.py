#!/usr/bin/env python3
"""Build a small-block Ford (Windsor) V8 in SolidCraft and export it as a game GLB.

    python3 tools/make_sbf.py                              # the 260/289/302 engine
    python3 tools/make_sbf.py --deck 351                   # the 351 Windsor, its tall deck
    python3 tools/make_sbf.py headers --headers shorty     # a set of headers alone
    python3 tools/make_sbf.py cover                        # the finned aluminum valve covers alone
    python3 tools/make_sbf.py intake                       # the aluminum dual-plane intake alone

The Windsors share one block casting pattern in two deck heights: 8.206 in from the crank
to the deck for the 260, 289 and 302, and 9.480 in for the 351 W, which is taller and wider
across the heads. Everything above the decks is drawn in each deck's own frame and comes
out where the deck puts it, so one script draws both; what sits on the heads (headers,
valve covers, intakes) is built for each deck too.

It is measured from a SolidWorks model of a 351 W (reference/parts/ford-windsor/
351W-Assembly.STEP; its deck is 9.635 in, so only the shapes are taken from it, the deck
heights are Ford's): the block, the heads, the timing cover, the balancer and the oil pan
are where and the size they are on it; the plugs, the exhaust ports and the intake ports
and bolts are on its axes. Its intake is a modern fuel-injected one, so the stock intake is
a sixties cast-iron four-barrel dual plane of the script's own, and the carburetor, air
cleaner, distributor, water pump, alternator, fuel pump, oil filter, starter and exhaust
manifolds are drawn from Ford's layout of the time: the distributor at the front of the
intake, the thermostat beside it on the right, the fuel pump on the timing cover's left,
the oil filter low at the front on the left, the starter on the right. It has:

  block         one outline across the engine, extruded front to back: each bank's outer
                wall straight down from the deck's edge to the skirt, the skirts down past
                the crank to the pan rail; the valley under the intake; the bellhousing
                flange at the back, the mount pads on the sides, freeze plugs
  heads         the reference head's outline across the bank: the low exhaust side rounded
                off below a ledge where the lower head bolts stand, the exhaust face
                sloping in up to the valve cover rail, the rail falling 10 degrees toward
                the valley, the intake face square to the deck; a raised two-bolt pad round
                each exhaust port high on the face, the plugs below them leaning out,
                forward and up
  valve covers  stamped steel on the Windsor's outline, the reference's: long sides, the
                ends slanting in from a big round corner outside to a small one inside,
                the outer side leaning in as it rises, the top rounded over; six bolts,
                three down the outer side, one in the middle of the inner side and one in
                each inner corner, the body notched round those on the sides; the oil
                filler cap at the front of the left one, the breather at the back of the
                right one
  intake        cast iron, in the style of make_sbc.py's: flanges on the heads' intake faces
                with six bolts each, a floor over the valley stepping in by each head, a
                runner up out of each port and round into an end of the plenum (the end
                cylinders' high, over the middle ones' low), the carb pad standing over
                the plenum on its studs' bosses with the left plane's two barrels and the
                right plane's slot, the choke's stove well, the water crossover and
                thermostat at the front, the exhaust heat crossover at the back, the
                distributor boss at the front left of the middle
  carburetor    a square-flange four-barrel under a 14 inch air cleaner (make_sbc.py's)
  distributor   standing at the front of the intake, the vacuum advance off to the left
  manifolds     cast-iron logs under the ports, a runner up into each, the outlet down
  headers       (built alone) long tubes or shorties, as make_sbc.py's
  front         the timing cover over the block's front, the water pump on it with its
                inlet low on the left, the balancer and a two-groove crank pulley, the
                pump pulley and fan, the alternator on the right, the fuel pump on the
                cover's left, the belt
  bottom        the oil pan, shallow in front and deep at the back, the oil filter, the
                starter, the flywheel
  finned covers (built alone) cast aluminum on the same outline, fins along the top, as
                the reference's but plain where its carry a name
  aluminum intake (built alone) a dual plane like the stock one in cast aluminum

Every part is a body of its own, drawn from numbers in this script; to change the engine,
change the numbers and run it again. The helpers are tools/make_sbc.py's and
tools/make_flathead.py's.

Writes resources/engines/STEM.sc, the SolidCraft design, and assets/parts/STEM.glb, STEM
being engine-sbf-302 or engine-sbf-351 for the engines, sbf-302-headers-long and the like
for the rest. Needs SolidCraft's command line and Blender, as tools/make_flathead.py does.

The design is in inches with the crank on the X axis: +X toward the back of the car, +Y
to its right, +Z up, the block's middle on X = 0. The GLB is in the frame of the other
engine models (engine_assembly.gd): engine units of 0.22 m, the crank at Z -0.36. Node
names follow make_sbc.py's, +1 the right bank and -1 the left. Ford's right bank is the
one ahead, the reverse of the Chevy's.
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
    BLACK, CAST_ALUMINUM, CAST_IRON, MACHINED, MM, PORCELAIN, RUBBER, S45, SATIN_ALUMINUM, STEEL, ZINC,
    crease_normals, hull_outline, inch, outline_commands, read_tris, skp)
from make_sbc import (  # noqa: E402
    BLENDER_REDUCE, CHROME, FILTER, FILTER_CAN, HEADER, SBC, ccw, hose_neck, lerp,
    p3, tube_path, unit, v3)
from make_wheels import SolidCraft, cmd, write_glb  # noqa: E402
import engine_meshes as em  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Ford's deck heights, crank to deck (in): the 260, 289 and 302 share the short one.
DECKS = {"302": 8.206, "351": 9.480}
DECK = DECKS["302"]
# What the deck changes besides: bore, stroke and rod (the pistons' depths down the bores).
STROKES = {"302": (4.0, 3.0, 5.09), "351": (4.0, 3.5, 5.956)}

# The block. Bores, ports and bolts are along each bank from the bank's middle.
BLOCK_FRONT = -9.91
BLOCK_BACK = 9.91
DECK_OUT = 2.75         # bank axis out to the deck's outer edge
DECK_IN = 4.55          # bank axis in to the deck's inner edge
VALLEY_DROP = 1.4       # the valley floor, this far under the decks' inner edges
WALL_FOOT = (4.95, 1.35)  # where each bank's outer wall comes down to the skirt (|y|, z)
SKIRT_Y = 4.6           # the skirts, down past the crank to the pan rail
RAIL_Z = -2.62          # the pan rail
BORE_MID = -0.596       # the bores' middle along the crank, both banks
BANK_SHIFT = 0.419      # the right bank sits this far ahead of that, the left back
BORE_X = [-6.57, -2.19, 2.19, 6.57]
HEAD_BOLT_X = [-8.76, -4.38, 0.0, 4.38, 8.76]
# The bellhousing flange across the back, (y, z) for the right half, and its bolt bosses.
BELL_FLANGE = [(8.3, RAIL_Z), (8.3, 3.2), (7.6, 5.4), (4.2, 8.4), (1.5, 9.1)]
BELL_BOSSES = [(7.75, -1.6), (8.0, 1.6), (6.6, 5.3), (3.4, 8.2)]
FREEZE_PLUG_X = [-4.38, 0.0, 4.38]  # along the bank, between the cylinders
FREEZE_PLUG_T = 0.45    # how far down the outer wall from the deck's edge
MOUNT_X = -3.3          # the side mounts' pads, along the block

# What shows with the intake and the heads off, as make_sbc.py's.
THROWS = [0, 90, 270, 180]
DECK_PLATE = 0.012
DECK_BOLTS = (0.75, 6.0, 0.27)      # the bolt rows, in from the deck's outer edge; radius
DECK_WATER = (1.2, 6.4, 0.17)       # the water holes beside each bore, likewise
LIFTER = (0.75, 0.44, 0.55)         # in from the valley's walls on its floor, radius, standing up
LIFTER_X = 0.9
PUSHROD_R = 0.16

# The heads, in each deck's own frame: a in from the deck's outer edge, h up off it.
HEAD_HALF = 9.875
# The low exhaust side is rounded off up to the ledge (1.05, 1.4).
HEAD = ([(0.0, 0.0), (7.3, 0.0), (7.3, 3.72), (2.4, 4.6), (2.3, 3.85)] +
        [(1.05 + 1.05 * math.cos(math.radians(t)), 0.35 + 1.05 * math.sin(math.radians(t)))
         for t in range(90, 181, 15)])
EXHAUST_FACE = ((1.05, 1.4), (2.3, 3.85))    # bottom and top, (a, h)
RAIL = ((2.4, 4.6), (7.3, 3.72))             # the valve cover rail, outer and inner, (a, h)
INTAKE_FACE_A = 7.3
HEAD_END_BEVEL = 0.35
# The exhaust ports, high on the face: how far up it, behind each bore (the left bank's in
# front: the heads are one casting turned round), the opening, the pad round it with an ear
# for a bolt each side (x along the face, v up it, r) and how far the pad stands out.
PORT_T = 0.76
PORT_SHIFT = 0.99
PORT_OPENING = (1.0, 1.2, 0.25)              # across, up, corner
PORT_PAD = [(-1.29, 0.0, 0.4), (-0.6, -0.62, 0.2), (0.6, -0.62, 0.2), (1.29, 0.0, 0.4),
            (0.6, 0.5, 0.2), (-0.6, 0.5, 0.2)]
PORT_PAD_T = 0.18
PORT_BOLT_X = 1.29
# The plugs: their axis passes PLUG (a, h) this far ahead of each bore (behind on the
# left), out, forward and a little up (x, out, up).
PLUG = (1.62, 1.4)
PLUG_SHIFT = -0.21
PLUG_DIR = (-0.293, 0.93, 0.221)
# The lower head bolts on the ledge, along the bank: a, and the bosses' and the bolts' tops.
HEAD_BOLT_LEDGE = (0.62, 0.55, 1.5, 1.9)     # a, foot h, boss top h, bolt top h

# Valve covers, in the rail's frame: x along the bank from its middle toward the back on
# the right bank (toward the front on the left: the heads, and so the covers, are one part
# turned round), c across from the rail's outer edge, lift up off it. The Windsor's outline,
# from the reference: long straight sides, each end a slant from a big round corner on the
# outer side to a small one on the inner side, which is the shorter. Each outline is
# (outer side's c, inner side's c, the tip's x, the big corner's radius, the small corner's
# middle x, its radius); the flange's, then the body's sections up from the flange (lift,
# outline): the outer side leans in all the way up, the ends come in, and over the top it
# rounds off.
COVER_FLANGE = (-0.05, 5.3, 10.1, 1.75, 8.4, 0.7)
COVER_FLANGE_T = 0.1
COVER_SECTIONS = [(0.0, (0.4, 4.9, 9.65, 1.6, 8.0, 0.6)), (1.5, (1.2, 5.15, 9.05, 1.45, 7.2, 0.55)),
                  (2.3, (1.65, 5.2, 8.7, 1.3, 6.95, 0.5)), (2.65, (2.05, 4.95, 8.35, 1.1, 6.75, 0.4))]
# Six bolts: three down the outer side, one in the middle of the inner side, one in each
# inner corner (x, c); the body is notched round those on its sides (radius).
COVER_BOLTS = [(-6.57, 0.5), (0.0, 0.5), (6.57, 0.5), (0.0, 4.72), (-8.95, 4.3), (8.95, 4.3)]
COVER_NOTCH = 0.42
FILLER = (6.0, 3.1)         # the oil filler cap at the left cover's front (x, c), the breather at
BREATHER = (6.0, 3.1)       # the right one's back
# The finned covers: the flange's thickness, the fins along the top (how many across, wide,
# tall) and the plain panel's half length in the middle, where the reference's carries a name.
FIN_FLANGE_T = 0.25
FINS = 6
FIN_W = 0.2
FIN_H = 0.22
FIN_PANEL = 2.3

# Intake, in each head's frame where it sits on it: the flange on each intake face (up the
# face from, to; thick), the runners' ports up it, the bolts' line up it and along each bank
# from its middle (the reference's: six a side, a pair close round the middle).
INTAKE_FLANGE = (0.1, 3.0, 0.6)
INTAKE_PORT_H = 1.6
INTAKE_BOLT_T = 2.45
INTAKE_BOLT_X = [-9.445, -4.375, -0.715, 0.715, 4.375, 9.445]
INTAKE_ENDS = (-10.7, 9.6)      # the floor's front and back
INTAKE_FLOOR_T = 0.55
RUNNER_BENDS = (1.0, 1.0)
RUNNER_CORNER = 0.38
ALUMINUM_RUNNER_CORNER = 0.6    # the aluminum intake's rounder runners
# The runners of the dual plane: (cylinder front to back, bank, top over the ports, across,
# deep, how far out from the middle each turns along into the plenum (None: straight in
# from its side), where it ends: along from the pad's middle, or out from the middle for
# the straight ones). As on make_sbc.py's, every runner turns into an end of the plenum, the
# front two of each bank into its front and the back two into its back: the end cylinders'
# high, over the middle ones' low. The plenum is shorter than the pad, which stands over it
# on its studs' bosses, so the middle cylinders' runners, whose ports are under the pad,
# still turn into its ends.
INTAKE_RUNNERS = [
    (0, 1, 2.7, 1.45, 1.45, 0.85, -1.45), (1, 1, 1.2, 1.3, 1.3, 1.6, -0.6),
    (0, -1, 2.7, 1.45, 1.45, 0.85, -1.45), (1, -1, 1.2, 1.3, 1.3, 1.6, -0.6),
    (2, 1, 1.2, 1.3, 1.3, 1.6, 0.6), (3, 1, 2.7, 1.45, 1.45, 0.85, 1.45),
    (2, -1, 1.2, 1.3, 1.3, 1.6, 0.6), (3, -1, 2.7, 1.45, 1.45, 0.85, 1.45),
]
PLENUM_HALF = 1.45      # the plenum's half length under the pad
WATER_CROSSOVER = (-9.8, 0.9, 1.3)      # x, its axis over the ports, diameter
HEAT_CROSSOVER = (8.0, 0.75, 1.0)       # the exhaust heat crossover at the back, likewise
# The choke's stove well on the right of the plenum: x from the pad's middle, in from the
# flange's face, its top under the pad.
CHOKE_WELL = ((-1.0, 0.1), (1.15, 0.15), 0.75)
FLOOR_INSET = 0.2       # the floor's ends, in from each head's ends
# The carb pad, as make_sbc.py's: the studs' bosses at its corners (x from the pad's middle,
# |y|) round which its outline runs, standing up from the floor; the openings into the
# plenum, the left plane's two barrels round, the right plane's one long slot, all inside
# the plenum's walls (the high runners end in them, the low ones under its floor).
PAD_BOSSES = [(2.75, 2.58), (-2.85, 2.58)]
PAD_BOSS_R = 0.55
PAD_HOLES = [(-0.72, -0.95), (0.72, -0.95)]
PAD_HOLE_R = 0.62
PAD_SLOT = ((-0.72, 0.95), (0.72, 0.95), 0.62)
# On each head's intake face, showing with the intake off: a port where each runner meets it
# (half long, half high, corner), the water passage's hole at the front (x along the bank,
# up the face, radius), the bolts' holes.
INTAKE_PORT = (0.62, 0.85, 0.3)
INTAKE_WATER = (-8.6, 1.9, 0.45)
PAD_X = -0.6            # the carb pad's middle
PAD_RISE = 2.75         # its underside over the ports
PAD = (2.65, 2.6, 0.4)  # half long, half wide, thick
PLENUM_FLOOR = 1.1
DIST = (-9.34, -0.89)   # the distributor's axis (x, y), the reference's
DIST_VACUUM = (-0.5, -0.86, 0.0)
THERMOSTAT = (-10.29, 2.58)
COIL = (-11.6, -5.0, 9.4)

# The stock exhaust: a flange on each port's pad, a log out past them (out from the pads,
# down from the ports' middles, diameter), stubs out into it, the outlet down at one end
# (diameter, length).
MANIFOLD_FLANGE_T = 0.45
MANIFOLD_LOG = (1.5, 0.25, 2.0)
MANIFOLD_RUNNER_D = 1.6
MANIFOLD_OUTLET = (2.3, 2.2)
# Headers, as make_sbc.py's: the collectors' front ends (x along the bank, |y|, z) and axis.
COLLECTOR = {"long": ((9.0, 10.6, -6.8), (0.72, 0.0, -0.69)),
             "shorty": ((1.5, 11.2, -2.6), (0.8, 0.0, -0.6))}
PRIMARY_D = 1.625
PRIMARY_OUT = (1.0, 1.8)
PRIMARY_MID_Z = 3.5
PRIMARY_LEAN = (-0.3, 0.0, 0.0, 0.3)

# Front: the timing cover's outline across (circles ((y, z), r) counterclockwise) out to the
# seal's face, the pump's pad on it out to its face, the pump's body on that.
TIMING_COVER = [((4.9, 0.4), 0.55), ((4.6, 4.2), 0.7), ((3.9, 6.6), 1.0), ((0.0, 9.2), 0.8),
                ((-3.9, 6.6), 1.0), ((-4.6, 4.2), 0.7), ((-4.9, 0.4), 0.55), ((-3.0, -2.3), 0.3),
                ((3.0, -2.3), 0.3)]
COVER_SEAL_X = -11.97
PUMP_PAD = [((0.0, 3.4), 1.6), ((3.6, 6.2), 1.3), ((0.0, 9.0), 0.9), ((-3.6, 6.2), 1.3)]
COVER_FACE = -12.95
PUMP = (0.0, 6.3)
PUMP_BODY = [((0.0, 3.0), 0.9), ((3.6, 5.4), 0.6), ((0.0, 6.3), 2.5), ((-3.6, 5.4), 0.6)]
PUMP_FACE = -14.3
BALANCER = (-13.45, -14.75)     # back and front
BALANCER_R = 3.2
BELT_BACK = -14.9       # the crank pulley's grooves start here, the others in line
CRANK_PULLEY_R = 3.1
PUMP_PULLEY_R = 3.3
FAN_X = -18.6
FAN_R = 8.3
ALTERNATOR = (6.6, 8.2)
ALT_PULLEY_R = 1.45
FUEL_PUMP = (-11.4, -4.6, 2.6)

# Bottom: the flywheel (front face, thickness, radius), the starter's axis (y, z), the oil
# pan (the flange's ends and half width, the pan's half width, its side profile (x, z) from
# the reference: shallow at the front, deep at the back), the drain, the filter.
FLYWHEEL = (11.2, 0.86, 7.0)
STARTER = (7.5, -2.4)
PAN_FLANGE = (-11.75, 9.5)
PAN_FLANGE_Y = 5.1
PAN_Y = 4.55
PAN_PROFILE = [(-11.8, -2.78), (9.3, -2.78), (9.3, -4.0), (6.2, -7.93), (5.5, -7.75), (0.9, -5.57),
               (-6.7, -5.57), (-8.4, -6.55), (-10.5, -6.55), (-11.1, -6.1)]
PAN_DRAIN = (5.8, -7.9)
OIL_FILTER = (-6.9, -5.4, -0.2)
OIL_FILTER_DIR = (0.0, -0.55, -0.83)

FORD_BLUE = {"name": "paint", "pbrMetallicRoughness": {
    "baseColorFactor": [0.03, 0.09, 0.33, 1], "metallicFactor": 0.35, "roughnessFactor": 0.5}}


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
    return x + BORE_MID - s * BANK_SHIFT


def deck_drop():
    """How far the 302's banks sit down and in along their axes from the 351's, which the
    front's numbers are measured on: the front follows them."""
    return (DECKS["351"] - DECK) * S45


def dropped(circles, above=None):
    """Outline circles ((y, z), r) moved down with the banks: all of them, or (above given)
    those higher than that, which also move in with their bank."""
    sh = deck_drop()
    out = []
    for (y, z), r in circles:
        if above is None:
            z -= sh
        elif z > above:
            y, z = y - np.sign(y) * sh if abs(y) > 0.1 else y, z - sh
        out.append(((y, z), r))
    return out


def front_point(p, s=0):
    """A point (y, z) on the front, moved down with the banks (and in with bank s's head)."""
    sh = deck_drop()
    return (p[0] - s * sh, p[1] - sh)


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
    return [bank_x(s, x + s * PORT_SHIFT) for x in BORE_X]


class Ford(SBC):
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
    valley_y = inner[0]
    fy, fz = WALL_FOOT
    right = [(SKIRT_Y, RAIL_Z), (SKIRT_Y, 0.0), (fy, 0.0), (fy, fz),
             tuple(deck_edge(1)), tuple(inner), (valley_y, vz)]
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
        d.rounded((m[0] - 1.8, m[1] - 0.55), (m[0] + 1.8, m[1] + 0.55), 0.35)
        d.finish()
        d.extrude(sk, f"engine_block_mount_{s}", 0.25)
        sk, to2d = d.plane(p3(0.0, c), (1, 0, 0), v3(n), f"Mount bosses {s}")
        for dx in (-1.25, 1.25):
            d.circle(to2d(p3(MOUNT_X + dx, c)), 0.38)
        d.finish()
        d.extrude(sk, f"engine_block_mount_bosses_{s}", 0.42)


# The insides.

def throw_angle(s, i):
    return THROWS[i] - s * 45


def bore_cut(stroke, rod):
    return max(em.piston_depth(throw_angle(s, i), stroke, rod) for s in (1, -1) for i in range(4)) + 1.0


def deck_holes():
    """The deck's small holes (x along the bank, a in from the outer edge, radius)."""
    ob, ib, br = DECK_BOLTS
    ow, iw, wr = DECK_WATER
    return ([(x, a, br) for x in HEAD_BOLT_X for a in (ob, ib)] +
            [(x, a, wr) for x in BORE_X for a in (ow, iw)])


def deck(d, bore, stroke, rod):
    """The bores cut down each bank, and the machined deck plate round them with its holes."""
    for s in (1, -1):
        u = bank(s)[0]
        sk, to2d = d.plane(p3(0.0, deck_edge(s)), (1, 0, 0), v3(u), f"Bores {s}")
        for x in BORE_X:
            c = to2d(p3(bank_x(s, x), on_head(s, DECK_OUT, 0.0)))
            d.c.append(cmd("sketch.polygon.inscribed", center=skp(*c), radius=round(bore / 2 * MM, 4), sides=36))
        d.finish()
        d.c.append(cmd("solid.extrude", sketch=sk, distance=inch(bore_cut(stroke, rod)), direction="negative",
                       operation="cut", targets=["engine_block"], name=f"Bores cut {s}"))
        sk, to2d = d.plane(p3(0.0, deck_edge(s)), (1, 0, 0), v3(u), f"Deck {s}")
        c0 = to2d(p3(bank_x(s, -HEAD_HALF), on_head(s, 0.0, 0.0)))
        c1 = to2d(p3(bank_x(s, HEAD_HALF), on_head(s, DECK_OUT + DECK_IN, 0.0)))
        d.c.append(cmd("sketch.rectangle.two_point", p0=skp(min(c0[0], c1[0]), min(c0[1], c1[1])),
                       p1=skp(max(c0[0], c1[0]), max(c0[1], c1[1]))))
        for x in BORE_X:
            c = to2d(p3(bank_x(s, x), on_head(s, DECK_OUT, 0.0)))
            d.c.append(cmd("sketch.polygon.inscribed", center=skp(*c), radius=round(bore / 2 * MM, 4), sides=36))
        for x, a, r in deck_holes():
            c = to2d(p3(bank_x(s, x), on_head(s, a, 0.0)))
            d.c.append(cmd("sketch.polygon.inscribed", center=skp(*c), radius=round(r * MM, 4), sides=10))
        d.finish()
        d.extrude(sk, f"engine_block_deck_{s}", DECK_PLATE)


def intake_face(s):
    """Bank s's head's intake face: its foot on the deck (y, z), the way up it, and its
    normal toward the valley."""
    f0 = on_head(s, INTAKE_FACE_A, 0.0)
    up = bank(s)[0]
    n = bank(s)[2]
    return f0, up, n


# The heads.

def head_outline(s, outline=HEAD):
    return [tuple(on_head(s, a, h)) for a, h in outline]


def shrunk(outline, by):
    """The outline moved in by `by` all round (each edge along its inward normal)."""
    pts = ccw([tuple(p) for p in outline])
    lines = []
    for k in range(len(pts)):
        p, q = np.array(pts[k], float), np.array(pts[(k + 1) % len(pts)], float)
        e = unit(q - p)
        lines.append((p + by * np.array([-e[1], e[0]]), e))
    out = []
    for k in range(len(lines)):
        (p, e), (q, f) = lines[k - 1], lines[k]
        det = e[0] * -f[1] - e[1] * -f[0]
        if abs(det) < 1e-6:
            out.append(tuple(q))
            continue
        t, _ = np.linalg.solve(np.column_stack([e, -f]), q - p)
        out.append(tuple(p + t * e))
    return out


def plug_exit(s, i):
    """Where plug i of bank s leaves the exhaust face, and its direction out."""
    f0, up, _ = exhaust_face(s)
    dirn = unit([s * PLUG_DIR[0], s * PLUG_DIR[1], PLUG_DIR[2]])
    p_yz = on_head(s, *PLUG)
    m = np.array([[dirn[1], -up[0]], [dirn[2], -up[1]]])
    t, _ = np.linalg.solve(m, f0 - p_yz)
    return p3(bank_x(s, BORE_X[i] + s * PLUG_SHIFT), p_yz) + t * dirn, dirn


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

        # The lower head bolts on their bosses along the ledge.
        u = bank(s)[0]
        a, h0, h1, h2 = HEAD_BOLT_LEDGE
        for k, x in enumerate(HEAD_BOLT_X):
            base = p3(bank_x(s, x), on_head(s, a, h0))
            d.cylinder(f"cylinder_head_{s} ({50 + 10 * k})", base, v3(u), 0.95, h1 - h0)
        sk, to2d = d.plane(p3(0.0, on_head(s, a, h1)), (1, 0, 0), v3(u), f"Head bolts {s}")
        for x in HEAD_BOLT_X:
            d.hexagon(to2d(p3(bank_x(s, x), on_head(s, a, h1))), 0.62)
        d.finish()
        d.extrude(sk, f"head_bolts_{s}", h2 - h1)

        # Spark plugs out of the exhaust face below the ports.
        for i in range(4):
            exit_, dirn = plug_exit(s, i)
            sk, to2d = d.plane(exit_, (1, 0, 0), dirn, f"Spark plug hex {s} {i}")
            d.hexagon(to2d(exit_), 0.63)
            d.finish()
            d.extrude(sk, f"spark_plug_base_{s}_{i}", 0.4, start_offset=inch(-0.1))
            d.cylinder(f"spark_plug_{s}_{i}", exit_ + 0.3 * dirn, dirn, 0.5, 1.0)
            d.cylinder(f"spark_plug_tip_{s}_{i}", exit_ + 1.3 * dirn, dirn, 0.25, 0.32)


def rail_frame(s):
    """Bank s's valve cover rail: its outer edge (y, z), across it toward the valley,
    and up off it, as (y, z)."""
    r0, r1 = (np.array(p, float) for p in RAIL)
    across = unit(r1 - r0)
    upa = np.array([-across[1], across[0]])
    return on_head(s, *r0), head_dir(s, *across), head_dir(s, *upa)


def cover_plane(d, s, lift, name):
    """A sketch on bank s's rail, lift up off it; returns (sketch, at(x along the bank from
    its middle, across))."""
    o, across, up = rail_frame(s)
    origin = p3(bank_x(s, 0.0), o + lift * up)
    sk, to2d = d.plane(origin, (1, 0, 0), v3(up), name)
    return sk, lambda x, c: to2d(origin + np.array([x, 0, 0]) + c * v3(across))


def cover_point(s, x, c, lift):
    o, across, up = rail_frame(s)
    return p3(bank_x(s, s * x), o + c * across + lift * up)


def arc(c, r, a0, a1, n):
    """n points round center c (c, x) from a0 to a1 degrees, both ends included."""
    return [(c[0] + r * math.cos(math.radians(a0 + (a1 - a0) * k / (n - 1))),
             c[1] + r * math.sin(math.radians(a0 + (a1 - a0) * k / (n - 1)))) for k in range(n)]


def tangent(c1, r1, c2, r2):
    """The outer tangent between two circles on the +x side: its touching angles (degrees)."""
    c1, c2 = np.array(c1, float), np.array(c2, float)
    d = np.linalg.norm(c2 - c1)
    e = (c2 - c1) / d
    perp = np.array([-e[1], e[0]])
    if perp[1] < 0:
        perp = -perp
    k = (r1 - r2) / d
    nrm = e * k + perp * math.sqrt(1 - k * k)
    return math.degrees(math.atan2(nrm[1], nrm[0]))


def side(c, x0, x1, notches, inward, n=4):
    """A straight side at c from x0 to x1, notched round each of notches (x) toward inward
    (+1: to larger c); a fixed number of points for each notch, so sections loft."""
    pts = [(c, x0)]
    sign = 1.0 if x1 > x0 else -1.0
    for xn in sorted(notches, key=lambda v: sign * v):
        r = COVER_NOTCH
        pts.append((c, xn - sign * r))
        for k in range(1, n):
            t = math.pi * k / n
            pts.append((c + inward * r * math.sin(t), xn - sign * r * math.cos(t)))
        pts.append((c, xn + sign * r))
    return pts


def cover_outline(sec, notched=True):
    """The outline (x, c) of a cover section, counterclockwise in (c, x)."""
    co, ci, tip, R, kx, r = sec
    big, small = (co + R, tip - R), (ci - r, kx)
    t = tangent(big, R, small, r)
    outer = [x for x, c in COVER_BOLTS if c < 2.5] if notched else []
    inner = [x for x, c in COVER_BOLTS if c > 2.5 and abs(x) < 5] if notched else []
    pts = side(co, -(tip - R), tip - R, outer, 1)[:-1]
    pts += arc(big, R, 180, t, 10)
    pts += arc(small, r, t, 0, 6)
    pts += side(ci, kx, -kx, inner, -1)[1:-1]
    pts += arc((small[0], -small[1]), r, 0, -t, 6)
    pts += arc((big[0], -big[1]), R, -t, -180, 10)[:-1]      # its end is the first point
    return [(x, c) for c, x in pts]


def cover_sketch(d, s, lift, name, outline):
    o, across, up = rail_frame(s)
    origin = p3(bank_x(s, 0.0), o + lift * up)
    sk, to2d = d.plane(origin, (1, 0, 0), v3(up), name)
    d.poly(ccw([to2d(origin + np.array([s * x, 0, 0]) + c * v3(across)) for x, c in outline]))
    d.finish()
    return sk


def cover(d, s, flange_t):
    """A cover's flange, its body lofted up through COVER_SECTIONS, its bolts."""
    sk = cover_sketch(d, s, 0.0, f"Cover flange {s}", cover_outline(COVER_FLANGE, notched=False))
    d.extrude(sk, f"valve_cover_{s}", flange_t)
    sks = [cover_sketch(d, s, flange_t + lift, f"Cover {s} section {k}", cover_outline(sec))
           for k, (lift, sec) in enumerate(COVER_SECTIONS)]
    d.loft(f"valve_cover_body_{s}", sks)
    for i, (x, c) in enumerate(COVER_BOLTS):
        sk, at = cover_plane(d, s, flange_t, f"Cover bolt {s} {i}")
        d.hexagon(at(s * x, c), 0.44)
        d.finish()
        d.extrude(sk, f"valve_bolt_{s}_{i}", 0.25)
    return flange_t + COVER_SECTIONS[-1][0]


def cap_and_breather(d, s, top):
    """The oil filler cap on the left cover, the breather on the right."""
    x, c = FILLER if s == -1 else BREATHER
    p = cover_point(s, x, c, top - 0.05)
    up = v3(rail_frame(s)[2])
    if s == -1:
        d.cylinder("valve_cover_filler_neck", p, up, 1.5, 0.35)
        d.cylinder("oil_filler_cap", p + 0.35 * up, up, 2.3, 0.5)
    else:
        d.cylinder("valve_cover_breather_neck", p, up, 1.3, 0.3)
        d.cylinder("valve_cover_breather", p + 0.3 * up, up, 2.0, 0.7)


def valve_covers(d):
    """Stamped steel covers on the Windsor's outline."""
    for s in (1, -1):
        cap_and_breather(d, s, cover(d, s, COVER_FLANGE_T))


def finned_covers(d):
    """Cast aluminum covers on the same outline, after the reference's: a thick flange,
    fins along the top in a run at each end and a plain panel between where the
    reference's carries a name; the bolts, the filler cap on the left and the breather on
    the right."""
    from shapely.geometry import LineString, Polygon
    for s in (1, -1):
        top = cover(d, s, FIN_FLANGE_T)
        flat = Polygon([(c, x) for x, c in cover_outline(COVER_SECTIONS[-1][1], notched=False)]).buffer(-0.2)
        c0, x0, c1, x1 = flat.bounds
        sk, at = cover_plane(d, s, top - 0.02, f"Fins {s}")
        for k in range(FINS):
            c = c0 + 0.1 + (c1 - c0 - 0.2) * k / (FINS - 1)
            run = flat.intersection(LineString([(c, x0 - 1), (c, x1 + 1)]))
            if run.is_empty:
                continue
            ya, yb = sorted(pt[1] for pt in run.coords)
            for a, b in ((ya, -FIN_PANEL), (FIN_PANEL, yb)):
                if b - a < 0.5:
                    continue
                p, q = at(s * a, c - FIN_W / 2), at(s * b, c + FIN_W / 2)
                d.rounded((min(p[0], q[0]), min(p[1], q[1])), (max(p[0], q[0]), max(p[1], q[1])),
                          FIN_W / 2 - 0.01)
        d.finish()
        d.extrude(sk, f"valve_cover_fins_{s}", FIN_H)
        sk, at = cover_plane(d, s, top - 0.02, f"Panel {s}")
        p, q = at(-FIN_PANEL + 0.2, c0 + 0.05), at(FIN_PANEL - 0.2, c1 - 0.05)
        d.rounded((min(p[0], q[0]), min(p[1], q[1])), (max(p[0], q[0]), max(p[1], q[1])), 0.35)
        d.finish()
        d.extrude(sk, f"valve_cover_panel_{s}", FIN_H * 0.6)
        cap_and_breather(d, s, top + FIN_H)


# The intake.

def port_on_face(s):
    """Where bank s's intake runners leave the flange's face (y, z), and the way out of it."""
    return on_head(s, INTAKE_FACE_A + INTAKE_FLANGE[2], INTAKE_PORT_H), bank(s)[2]


def runner_port():
    p, _ = port_on_face(1)
    return float(p[0]), float(p[1]), 45.0


def runner(d, name, x, s, top, w, h, entry_y, to_x):
    """make_sbc.py's runner: a square runner with rounded corners from bank s's port at x,
    straight up and in out of the port, a bend over level, across, then (entry_y given) a
    turn along X into the plenum at entry_y ending at to_x; else straight on to y = to_x."""
    y0, z0, climb = runner_port()
    th = math.radians(climb)
    zc = top - h / 2
    rise = zc - z0
    r1 = min(RUNNER_BENDS[0], 0.9 * rise / (1 - math.cos(th)))
    lead = max((rise - r1 * (1 - math.cos(th))) / math.sin(th), 0.05)
    r2 = RUNNER_BENDS[1]
    p0 = np.array([x, s * y0, z0])
    y_turn = entry_y + s * r2 if entry_y is not None else to_x
    sk, to2d = d.plane(p0, (0.0, -s, 0.0), (s, 0, 0), f"{name} path")
    u1 = lead * np.array([math.cos(th), math.sin(th)])
    c = u1 + r1 * np.array([math.sin(th), -math.cos(th)])
    u2 = c + np.array([0.0, r1])
    u3 = np.array([abs(y_turn - s * y0), u2[1]])
    flip = np.array([1.0, -1.0])
    d.c.append(cmd("sketch.line", infer=False, points=[skp(0.0, 0.0), skp(*(u1 * flip))]))
    d.c.append(cmd("sketch.arc.center_point", center=skp(*(c * flip)), start="l1.end",
                   end=skp(*(u2 * flip))))
    path = ["l1", "a1"]
    if u3[0] - u2[0] > 0.02:
        d.c.append(cmd("sketch.line", infer=False, points=["a1.end", skp(*(u3 * flip))]))
        path.append("l2")
    d.finish()
    out = np.array([0.0, -s * math.cos(th), math.sin(th)])
    prof, to2d = d.plane(p0, (1, 0, 0), out, f"{name} section")
    cx, cy = to2d(p0)
    d.rounded((cx - w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), RUNNER_CORNER)
    d.finish()
    d.body(name, "solid.sweep", sketch=prof, path_sketch=sk, path=path, orientation=[1.0, 0.0, 0.0])
    if entry_y is None:
        return
    pt = np.array([x, y_turn, zc])
    along = -s
    dx = 1.0 if to_x > x else -1.0
    ysign = -dx * along
    sk, to2d = d.plane(pt, (1, 0, 0), (0, 0, ysign), f"{name} turn")
    centre = pt + np.array([dx * r2, 0.0, 0.0])
    arc_end = pt + np.array([dx * r2, along * r2, 0.0])
    end = np.array([to_x, arc_end[1], zc])
    d.c.append(cmd("sketch.arc.center_point", center=skp(*to2d(centre)), start=skp(*to2d(pt)),
                   end=skp(*to2d(arc_end))))
    d.c.append(cmd("sketch.line", infer=False, points=["a1.end", skp(*to2d(end))]))
    d.finish()
    prof, to2d = d.plane(pt, (1, 0, 0), (0, along, 0), f"{name} turn section")
    cx, cy = to2d(pt)
    d.rounded((cx - w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), RUNNER_CORNER)
    d.finish()
    d.body(f"{name}_turn", "solid.sweep", sketch=prof, path_sketch=sk, path=["a1", "l1"])


def crossover(d, name, x, zc, dia):
    """A round passage across the engine at x between the flanges' faces: up out of each
    as the runners leave their ports, level across at zc."""
    y0, z0, climb = runner_port()
    th = math.radians(climb)
    rise = zc - z0
    r = min(RUNNER_BENDS[0], 0.9 * rise / (1 - math.cos(th)))
    lead = max((rise - r * (1 - math.cos(th))) / math.sin(th), 0.05)
    p0 = np.array([x, -y0, z0])
    sk, _ = d.plane(p0, (0, 1, 0), (-1, 0, 0), f"{name} path")
    u1 = lead * np.array([math.cos(th), math.sin(th)])
    c1 = u1 + r * np.array([math.sin(th), -math.cos(th)])
    u2 = c1 + np.array([0.0, r])
    span = 2 * y0
    u3 = np.array([span - u2[0], u2[1]])
    c2 = np.array([span - c1[0], c1[1]])
    u4 = np.array([span - u1[0], u1[1]])
    flip = np.array([1.0, -1.0])
    f = lambda u: skp(*(u * flip))
    d.c.append(cmd("sketch.line", infer=False, points=[skp(0.0, 0.0), f(u1)]))
    d.c.append(cmd("sketch.arc.center_point", center=f(c1), start="l1.end", end=f(u2)))
    d.c.append(cmd("sketch.line", infer=False, points=["a1.end", f(u3)]))
    d.c.append(cmd("sketch.arc.center_point", center=f(c2), start="l2.end", end=f(u4)))
    d.c.append(cmd("sketch.line", infer=False, points=["a2.end", f(np.array([span, 0.0]))]))
    d.finish()
    d.body(name, "solid.pipe", path_sketch=sk, path=["l1", "a1", "l2", "a2", "l3"],
           diameter=inch(dia))


def intake_levels():
    """The intake's heights, which follow the deck: the floor's underside and top (on the
    valley's end walls), the runners' port height, the carb pad's underside."""
    z0 = deck_inner(1)[1] + 0.05
    _, zp, _ = runner_port()
    return z0, z0 + INTAKE_FLOOR_T, zp, zp + PAD_RISE


def intake_runners():
    """(x, bank, top, wide, deep, the y it turns along into the plenum or None, the x it ends
    at, or the y for a straight one), from INTAKE_RUNNERS' (cylinder, bank, ...)."""
    _, _, zp, _ = intake_levels()
    out = []
    for i, s, top, w, h, entry, end in INTAKE_RUNNERS:
        x = bank_x(s, BORE_X[i])
        to = PAD_X + end if entry is not None else s * end
        out.append((x, s, zp + top, w, h, None if entry is None else s * entry, to))
    return out


def flange_face_y():
    """|y| of the flanges' inner faces at the floor."""
    return on_head(1, INTAKE_FACE_A + INTAKE_FLANGE[2], INTAKE_FLANGE[0])[0]


def pad_bosses():
    return [(PAD_X + x, sy * y) for x, y in PAD_BOSSES for sy in (1, -1)]


def floor_outline():
    """The intake's floor from above (x, y), counterclockwise: each half as long as its
    head, the halves stepping across the middle, rounded off, a lobe round the
    distributor's boss."""
    from shapely.geometry import Point, Polygon, box
    fy = flange_face_y()
    halves = []
    for s in (1, -1):
        x0, x1 = bank_x(s, -HEAD_HALF) + FLOOR_INSET, bank_x(s, HEAD_HALF) - FLOOR_INSET
        y0, y1 = sorted((0.0, s * fy))
        halves.append(box(x0, y0 - 0.4 * (s == 1), x1, y1 + 0.4 * (s == -1)))
    shape = halves[0].union(halves[1]).union(Point(DIST).buffer(1.5, 16))
    shape = shape.buffer(0.35, 4).buffer(-0.7, 4).buffer(0.35, 4).simplify(0.01)
    return ccw([tuple(map(float, q)) for q in list(shape.exterior.coords)[:-1]])


def intake(d, stock=True):
    """The dual-plane four-barrel intake: the stock cast-iron one with the thermostat housing
    on it, or (stock False) the aluminum one, its runners rounder, the housing left on the
    engine (its bodies are the engine's)."""
    global RUNNER_CORNER
    z0, z1, zp, pad_z = intake_levels()
    nm = "intake_manifold"
    if not stock:
        RUNNER_CORNER = ALUMINUM_RUNNER_CORNER
    # The floor over the valley between the flanges' inner faces, its ends stepping in by
    # each head (the right one starts and ends ahead of the left), a lobe round the
    # distributor's boss at the front.
    sk = d.sketch("XY", "Intake floor", offset=z0)
    d.poly(floor_outline())
    d.finish()
    d.extrude(sk, nm, z1 - z0)

    t0, t1, thick = INTAKE_FLANGE
    for s in (1, -1):
        f0, up, n = intake_face(s)
        xa, xb = bank_x(s, -HEAD_HALF) + 0.1, bank_x(s, HEAD_HALF) - 0.1
        sk, to2d = d.plane(p3(0.0, f0), (1, 0, 0), v3(n), f"Intake flange {s}")
        d.rounded(to2d(p3(xa, f0 + t0 * up)), to2d(p3(xb, f0 + t1 * up)), 0.3)
        d.finish()
        d.extrude(sk, f"{nm}_flange_{s}", thick)
        bolt = f0 + INTAKE_BOLT_T * up + thick * n
        sk, to2d = d.plane(p3(0.0, bolt), (1, 0, 0), v3(n), f"Intake bolt bosses {s}")
        for x in INTAKE_BOLT_X:
            d.circle(to2d(p3(bank_x(s, s * x), bolt)), 0.48)
        d.finish()
        d.extrude(sk, f"{nm}_bolt_bosses_{s}", 0.15, start_offset=inch(-0.05))
        sk, to2d = d.plane(p3(0.0, bolt), (1, 0, 0), v3(n), f"Intake bolts {s}")
        for x in INTAKE_BOLT_X:
            d.hexagon(to2d(p3(bank_x(s, s * x), bolt)), 0.5)
        d.finish()
        d.extrude(sk, f"intake_bolts_{s}", 0.28, start_offset=inch(0.1))

    for k, r in enumerate(intake_runners()):
        runner(d, f"{nm}_runner_{k}", *r)
    # The water crossover across the front, between the heads' front water ports.
    crossover(d, f"{nm}_crossover", WATER_CROSSOVER[0], zp + WATER_CROSSOVER[1], WATER_CROSSOVER[2])

    # The exhaust heat crossover at the back, the choke's stove well on the right.
    crossover(d, f"{nm}_heat_crossover", HEAT_CROSSOVER[0], zp + HEAT_CROSSOVER[1], HEAT_CROSSOVER[2])
    fy = flange_face_y()
    (cx0, ci0), (cx1, ci1), drop = CHOKE_WELL
    sk = d.sketch("XY", "Choke well", offset=z1 - 0.1)
    d.rounded((PAD_X + cx0, fy - 1.2 + ci0), (PAD_X + cx1, fy - ci1), 0.3)
    d.finish()
    d.extrude(sk, f"{nm}_choke_well", pad_z - drop - z1 + 0.1, taper="-4 deg")

    # The plenum, as make_sbc.py's: solid up to its dark floor, then its walls round the
    # pad's openings up to the pad, which runs round its studs' bosses.
    px, py, pt = PAD
    floor = pad_z - PLENUM_FLOOR
    hx = PLENUM_HALF
    sk = d.sketch("XY", "Plenum", offset=z1 - 0.1)
    d.rounded((PAD_X - hx - 0.1, -py - 0.1), (PAD_X + hx + 0.1, py + 0.1), 0.8)
    d.finish()
    d.extrude(sk, f"{nm}_plenum", floor - z1 + 0.1)

    def openings(first):
        # The slot's lines and arcs are numbered on from the outline's, so it goes before
        # the circles, which take arc numbers of their own.
        (sx0, sy0), (sx1, sy1), sr = PAD_SLOT
        d.c += outline_commands(*hull_outline([((PAD_X + sx0, sy0), sr), ((PAD_X + sx1, sy1), sr)]),
                                first=first)
        for x, y in PAD_HOLES:
            d.circle((PAD_X + x, y), PAD_HOLE_R)

    corners = [((PAD_X + sx * (hx + 0.1 - 0.8), sy * (py + 0.1 - 0.8)), 0.8)
               for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))]
    sk = d.sketch("XY", "Plenum walls", offset=floor)
    d.c += outline_commands(*hull_outline(corners))
    openings(5)
    d.finish()
    d.extrude(sk, f"{nm}_plenum_walls", pad_z - floor)
    sk = d.sketch("XY", "Plenum floor", offset=floor)
    openings(1)
    d.finish()
    d.extrude(sk, f"{nm}_plenum_floor", 0.02)
    bosses = pad_bosses()
    sk = d.sketch("XY", "Carb pad", offset=pad_z)
    mid = np.mean(bosses, axis=0)
    ring = sorted(bosses, key=lambda q: math.atan2(q[1] - mid[1], q[0] - mid[0]))
    d.c += outline_commands(*hull_outline([(q, PAD_BOSS_R) for q in ring]))
    openings(5)
    d.finish()
    d.extrude(sk, f"{nm}_pad", pt)
    sk = d.sketch("XY", "Pad bosses", offset=z1 - 0.1)
    for q in bosses:
        d.circle(q, 0.45)
    d.finish()
    d.extrude(sk, f"{nm}_pad_bosses", pad_z + pt + 0.12 - (z1 - 0.1))

    # The distributor's boss at the front, and the thermostat's seat on the crossover at
    # the front right, the housing bolted down on it, its neck forward and up.
    dx, dy = DIST
    d.cylinder(f"{nm}_distributor_boss", (dx, dy, z0 - 0.3), (0, 0, 1), 2.3, z1 - z0 + 0.6)
    tx, ty = THERMOSTAT
    seat_top = zp + WATER_CROSSOVER[1] + WATER_CROSSOVER[2] / 2 + 0.15
    sk = d.sketch("XY", "Thermostat seat", offset=z1 - 0.05)
    d.c += outline_commands(*hull_outline([((tx, ty - 1.5), 0.5), ((tx + 0.4, ty), 1.25),
                                           ((tx, ty + 1.5), 0.5), ((tx - 0.3, ty), 1.25)]))
    d.finish()
    d.extrude(sk, f"{nm}_thermostat_seat", seat_top - z1 + 0.05)
    if not stock:
        return
    sk = d.sketch("XY", "Thermostat housing", offset=seat_top)
    d.c += outline_commands(*hull_outline([((tx, ty - 1.5), 0.42), ((tx + 0.05, ty), 1.12),
                                           ((tx, ty + 1.5), 0.42), ((tx - 0.05, ty), 1.12)]))
    d.finish()
    d.extrude(sk, "thermostat_housing", 0.25)
    d.revolve("thermostat_dome", (tx, ty, 0.0), (0, 0, 1), (1, 0, 0),
              [(seat_top + 0.2, 0.0), (seat_top + 0.2, 1.15), (seat_top + 0.7, 1.1),
               (seat_top + 1.05, 0.85), (seat_top + 1.2, 0.0)])
    sk = d.sketch("XY", "Thermostat bolts", offset=seat_top + 0.25)
    for y in (ty - 1.5, ty + 1.5):
        d.hexagon((tx, y), 0.5)
    d.finish()
    d.extrude(sk, "thermostat_bolts", 0.3)
    neck = np.array([tx, ty, seat_top + 0.55])
    dirn = unit([-0.75, 0.0, 0.66])
    hose_neck(d, "thermostat_neck", neck, dirn, 0.72, 0.56, 2.1, 1.3)
    d.cylinder("thermostat_bead", neck + 1.6 * dirn, dirn, 1.6, 0.16)


def carb_and_cleaner(d):
    """make_sbc.py's square-flange four-barrel and 14 inch air cleaner, set on this pad."""
    import make_sbc
    _, _, _, pad_z = intake_levels()
    make_sbc.PAD_X, make_sbc.PAD_Z, make_sbc.PAD = PAD_X, pad_z, PAD
    make_sbc.air_cleaner(d, make_sbc.carburetor(d))


def distributor(d):
    """Only the outside: the housing out of the intake's boss, the cap, the vacuum advance
    off to the left, the hold-down clamp."""
    x, y = DIST
    _, z1, _, _ = intake_levels()
    z = z1 + 0.3     # the boss's top
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
    za = z + 1.2
    d.cylinder("distributor_vacuum_arm", o + np.array([0, 0, za]) + 0.6 * arm, arm, 0.6, 0.8)
    d.cylinder("distributor_vacuum", o + np.array([0, 0, za]) + 1.35 * arm, arm, 2.2, 1.1)
    d.cone("distributor_vacuum_end", o + np.array([0, 0, za]) + 2.45 * arm, arm, 1.1, 0.6, 0.35)
    d.cylinder("distributor_vacuum_nipple", o + np.array([0, 0, za]) + 2.8 * arm, arm, 0.25, 0.45)
    d.box("distributor_clamp", (x + 0.55, y - 0.35, z + 0.45), (x + 2.0, y + 0.35, z + 0.65))
    d.cylinder("distributor_clamp_bolt", (x + 1.55, y, z + 0.65), (0, 0, 1), 0.55, 0.3)


def coil(d):
    """The coil standing on its bracket off the left head's front, beside the distributor."""
    x, y, z = COIL
    y, z = front_point((y, z), -1)
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

def iron_manifolds(d):
    """Cast-iron logs: a short runner out of each port down into a log along the bank below
    the ports, the outlet down out of it at one end to a round two-bolt flange."""
    for s in (1, -1):
        _, up, n = exhaust_face(s)
        pc = port_center(s)
        xs = port_xs(s)
        sk, to2d = d.plane(p3(0.0, pc), (1, 0, 0), v3(n), f"Manifold flanges {s}")
        first = 1
        for x in xs:
            pts = [(np.array(to2d(p3(x + dx, pc + v * up))), r) for dx, v, r in PORT_PAD]
            c = sum(p for p, _ in pts) / len(pts)
            pts.sort(key=lambda pr: math.atan2(*(pr[0] - c)[::-1]))
            d.c += outline_commands(*hull_outline([(tuple(p), r) for p, r in pts]), first=first)
            first += len(pts)
        d.finish()
        d.extrude(sk, f"exhaust_manifold_{s}", MANIFOLD_FLANGE_T, start_offset=inch(PORT_PAD_T))
        out, drop, dia = MANIFOLD_LOG
        log_yz = pc + (PORT_PAD_T + out) * n + np.array([0.0, -drop])
        lo, hi = min(xs) - 0.9, max(xs) + 0.9
        d.cylinder(f"exhaust_manifold_log_{s}", p3(lo, log_yz), (1, 0, 0), dia, hi - lo)
        for k, x in enumerate(xs):
            start = p3(x, pc + PORT_PAD_T * n)
            end = p3(x, log_yz)
            dirn = unit(end - start)
            d.cylinder(f"exhaust_manifold_{s} ({10 + 10 * k})", start, dirn, MANIFOLD_RUNNER_D,
                       float(np.linalg.norm(end - start)))
        for k, x in enumerate((lo, hi)):
            d.sphere(f"exhaust_manifold_{s} ({60 + 10 * k})", p3(x, log_yz), dia)
        # The outlet down at the back on the right, at the front on the left.
        ox = hi - 0.6 if s == 1 else lo + 0.6
        top = p3(ox, log_yz)
        d.cylinder(f"exhaust_manifold_outlet_{s}", top, (0, 0, -1), MANIFOLD_OUTLET[0], MANIFOLD_OUTLET[1])
        fz = log_yz[1] - MANIFOLD_OUTLET[1]
        sk = d.sketch("XY", f"Manifold outlet flange {s}", offset=fz)
        oy = log_yz[0]
        d.c += outline_commands(*hull_outline([((ox, oy - 0.35), 1.15), ((ox + 1.9, oy), 0.42),
                                               ((ox, oy + 0.35), 1.15), ((ox - 1.9, oy), 0.42)]))
        d.circle((ox, oy), MANIFOLD_OUTLET[0] / 2 - 0.25)
        d.finish()
        d.extrude(sk, f"exhaust_manifold_outlet_flange_{s}", 0.4)
        d.cylinder(f"exhaust_manifold_bore_{s}", (ox, oy, fz + 0.6), (0, 0, 1),
                   MANIFOLD_OUTLET[0] - 0.55, 0.02)


def headers(d, style):
    """make_sbc.py's headers on these heads: a flange over the four ports, four primaries out
    of them, each down outside the plugs and one bend back into a merge cone and collector."""
    (cx, cy, cz), axis = COLLECTOR[style]
    axis = unit(axis)
    for s in (1, -1):
        n = v3(exhaust_face(s)[2])
        pc = port_center(s)
        xs = port_xs(s)
        sk, to2d = d.plane(p3(0.0, pc), (1, 0, 0), n, f"Header flange {s}")
        a, b = to2d(p3(min(xs) - 1.75, pc)), to2d(p3(max(xs) + 1.75, pc))
        d.rounded((min(a[0], b[0]), a[1] - 0.75), (max(a[0], b[0]), a[1] + 0.75), 0.3)
        d.finish()
        d.extrude(sk, f"exhaust_flange_{s}", 0.375)

        front = np.array([bank_x(s, cx), s * cy, cz])
        across = unit(np.cross(axis, [0, 0, 1])) if abs(axis[2]) < 0.99 else np.array([0, 1, 0])
        upv = np.cross(across, axis)
        mouths = [front + 0.62 * (i * across + j * upv) for i, j in ((-1, 1), (1, 1), (-1, -1), (1, -1))]
        ports = [p3(x, pc) + 0.375 * n for x in xs]
        order = sorted(range(4), key=lambda k: ports[k][0])
        mouth_order = sorted(range(4), key=lambda k: (mouths[k][0], -s * mouths[k][1]))
        for k_port, k_mouth in zip(order, mouth_order):
            p0, target = ports[k_port] - 0.375 * n, mouths[k_mouth]
            lean = PRIMARY_LEAN[order.index(k_port)]
            dropv = unit([lean, 0.0, -1.0])
            corner = p0 + (PRIMARY_OUT[0] + PRIMARY_OUT[1]) * n
            mid = corner + (corner[2] - PRIMARY_MID_Z) * dropv / -dropv[2]
            name = f"exhaust_runner_{s}_{k_port}"
            down = None
            for part, (start, out_dir, end, lead, radius) in enumerate((
                    (p0, n, mid, PRIMARY_OUT[0], PRIMARY_OUT[1]),
                    (mid, None, target, 0.05, 3.0))):
                if out_dir is None:
                    out_dir = down
                e1, e2, (a0, a1, c, q, t) = tube_path(start, out_dir, end, lead, radius)
                down = unit(end - (start + q[0] * e1 + q[1] * e2))
                sk, _ = d.plane(start, e1, np.cross(e1, e2), f"{name} path {part}")
                d.c.append(cmd("sketch.line", infer=False, points=[skp(*a0), skp(*a1)]))
                d.c.append(cmd("sketch.arc.center_point", center=skp(*c), start="l1.end", end=skp(*q)))
                d.c.append(cmd("sketch.line", infer=False, points=["a1.end", skp(*t)]))
                d.finish()
                d.body(f"{name}_{part}", "solid.pipe", path_sketch=sk, path=["l1", "a1", "l2"],
                       diameter=inch(PRIMARY_D))
        d.cone(f"exhaust_collector_{s}", front - 0.4 * axis, axis, 2.05, 1.5, 3.4)
        d.cylinder(f"exhaust_collector_pipe_{s}", front + 3.0 * axis, axis, 3.0, 3.0)
        d.cylinder(f"exhaust_collector_flange_{s}", front + 6.0 * axis, axis, 4.6, 0.375)


# The front of the engine.

def grooves(x_back, n, r, root):
    """A pulley's rim outline from x_back forward: n V grooves, out to r, root deep."""
    pts = [(x_back, r)]
    x = x_back
    for _ in range(n):
        pts += [(x - 0.1, r), (x - 0.35, root), (x - 0.45, root), (x - 0.7, r)]
        x -= 0.7
    return pts, x


def front(d):
    def turned(name, yz, profile):
        d.revolve(name, p3(0.0, yz), (1, 0, 0), (0, 0, 1), profile)

    # Timing cover over the block's front, round the crank and up to the pump's pad.
    sk = d.sketch("YZ", "Timing cover", offset=BLOCK_FRONT)
    d.c += outline_commands(*hull_outline(dropped(TIMING_COVER, 5.0)))
    d.finish()
    d.extrude(sk, "timing_cover", BLOCK_FRONT - COVER_SEAL_X, "negative")
    sk = d.sketch("YZ", "Timing cover pump pad", offset=COVER_SEAL_X)
    d.c += outline_commands(*hull_outline(dropped(PUMP_PAD)))
    d.finish()
    d.extrude(sk, "timing_cover_pad", COVER_SEAL_X - COVER_FACE, "negative")

    # The water pump: the body on the cover's pad, the snout, the hub; its inlet low on
    # the left, the heater fitting up on its right.
    py, pz = pump = front_point(PUMP)
    sh = deck_drop()
    sk = d.sketch("YZ", "Water pump", offset=COVER_FACE)
    d.c += outline_commands(*hull_outline(dropped(PUMP_BODY)))
    d.finish()
    d.extrude(sk, "water_pump_housing", COVER_FACE - PUMP_FACE, "negative")
    d.cone("water_pump_snout", (PUMP_FACE, py, pz), (-1, 0, 0), 2.3, 1.1, PUMP_FACE - BELT_BACK + 1.2)
    hose_neck(d, "water_pump_inlet", np.array([PUMP_FACE + 0.6, -2.2, 3.6 - sh]), unit([-0.3, -0.7, -0.65]),
              0.85, 0.68, 3.0, 1.5)
    hose_neck(d, "water_pump_heater", np.array([PUMP_FACE + 0.3, 1.5, 8.1 - sh]), unit([-0.6, 0.35, 0.72]),
              0.4, 0.27, 1.3, 0.8)

    # The balancer and the crank pulley, turned about the crank.
    b0, b1 = BALANCER
    turned("harmonic_balancer", (0.0, 0.0),
           [(COVER_SEAL_X, 0.0), (COVER_SEAL_X, 1.3), (b0, 1.3), (b0, BALANCER_R), (b1, BALANCER_R), (b1, 0.0)])
    turned("harmonic_balancer_ring", (0.0, 0.0),
           [(b0 + 0.35, BALANCER_R - 0.75), (b0 + 0.35, BALANCER_R + 0.01), (b0 + 0.47, BALANCER_R + 0.01),
            (b0 + 0.47, BALANCER_R - 0.75)])
    rim, x_front = grooves(BELT_BACK, 2, CRANK_PULLEY_R, CRANK_PULLEY_R - 0.42)
    turned("crank_pulley", (0.0, 0.0), [(b1, 0.0), (b1, CRANK_PULLEY_R)] + rim + [(x_front, 0.0)])
    turned("crank_bolt", (0.0, 0.0), [(x_front, 0.0), (x_front, 0.55), (x_front - 0.5, 0.55),
                                       (x_front - 0.5, 0.0)])

    # The pump's pulley, dished forward to its web on the hub, the fan on a spacer.
    rim, x_front = grooves(BELT_BACK, 2, PUMP_PULLEY_R, PUMP_PULLEY_R - 0.42)
    turned("upper_pulley", pump, [(BELT_BACK, PUMP_PULLEY_R - 0.55)] + rim
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
    ring = [((0.0, 0.0), CRANK_PULLEY_R - 0.2), (front_point(ALTERNATOR, 1), ALT_PULLEY_R - 0.2),
            (pump, PUMP_PULLEY_R - 0.2)]
    sk = d.sketch("YZ", "Belt", offset=belt_x)
    d.c += outline_commands(*hull_outline(ring))
    d.c += outline_commands(*hull_outline([(c, r + 0.33) for c, r in ring]), first=len(ring) + 1)
    d.finish()
    d.extrude(sk, "belt", 0.5, "symmetric")


def alternator(d):
    """make_sbc.py's alternator, moved to this belt and up on the right head's front."""
    ay, az = front_point(ALTERNATOR, 1)
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
    # The pivot ear down toward the cover, its bracket down to the pump pad's bolt; the
    # adjusting ear up and out.
    for name, ang, x0, x1 in (("alternator_ear_pivot", -110, -12.5, -11.7),
                              ("alternator_ear_adjust", 30, -12.3, -11.9)):
        t = math.radians(ang)
        c, s_ = math.cos(t), math.sin(t)
        sk = d.sketch("YZ", name, offset=x1 + sh)
        d.c += outline_commands(*hull_outline([((ay + 2.2 * c, az + 2.2 * s_), 0.75),
                                                ((ay + 3.65 * c, az + 3.65 * s_), 0.48)]))
        d.finish()
        d.extrude(sk, name, x1 - x0, "negative")
    t = math.radians(-110)
    ear = (ay + 3.65 * math.cos(t), az + 3.65 * math.sin(t))
    sk = d.sketch("YZ", "Alternator bracket", offset=COVER_FACE)
    d.c += outline_commands(*hull_outline([(ear, 0.6), (dropped(PUMP_PAD)[1][0], 0.7)]))
    d.finish()
    d.extrude(sk, "accessory_bracket_right", 0.3, "negative")


def fuel_pump(d):
    """The mechanical fuel pump on the timing cover's left, its body out to the left, the
    domed bowl, a line fitting front and back."""
    x, y, z = FUEL_PUMP
    d.cylinder("fuel_pump_mount", (x, y + 0.3, z), (0, -1, 0), 2.4, 0.9)
    d.cylinder("fuel_pump", (x, y - 0.6, z), (0, -1, 0), 2.9, 0.9)
    d.revolve("fuel_pump_bowl", (x, y - 1.5, z), (0, -1, 0), (0, 0, 1),
              [(0.0, 0.0), (0.0, 1.45), (0.4, 1.4), (0.75, 1.05), (0.85, 0.0)])
    for k, dx in enumerate((-1.0, 1.0)):
        d.cylinder(f"fuel_pump_fitting_{k}", (x, y - 1.0, z), (dx, 0, 0), 0.35, 1.9)


# The bottom.

def bottom(d):
    fx, ft, fr = FLYWHEEL
    d.cylinder("flywheel", (fx, 0, 0), (1, 0, 0), 2 * fr, ft)
    d.cylinder("flywheel_crank_flange", (BLOCK_BACK, 0, 0), (1, 0, 0), 3.6, fx - BLOCK_BACK)
    d.cylinder("flywheel_hub", (fx + ft, 0, 0), (1, 0, 0), 3.2, 0.3)

    # The starter on the right, low: the motor, its end cap, the nose back to the
    # bellhousing, the positive-engagement hump on top.
    sy, sz = STARTER
    d.cylinder("starter", (2.6, sy, sz), (1, 0, 0), 4.5, 5.9)
    d.cylinder("starter_end", (2.3, sy, sz), (1, 0, 0), 3.7, 0.3)
    d.cone("starter_nose", (8.5, sy, sz), (1, 0, 0), 1.8, 1.4, fx - 8.5)
    d.box("starter_nose_mount", (fx - 1.6, sy - 1.7, sz - 1.5), (fx - 0.2, sy + 0.3, sz + 1.7))
    sk = d.sketch("YZ", "Starter hump", offset=4.6)
    d.c += outline_commands(*hull_outline([((sy - 1.3, sz + 0.6), 0.6), ((sy + 1.3, sz + 0.6), 0.6),
                                           ((sy + 0.5, sz + 1.9), 0.75), ((sy - 0.5, sz + 1.9), 0.75)]))
    d.finish()
    d.extrude(sk, "starter_hump", 3.4)
    d.cylinder("starter_post", (5.2, sy + 1.5, sz + 1.1), (0.0, 0.7, 0.7), 0.45, 0.6)

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

    # The oil filter at the front on the left, low, pointing down and out.
    ox, oy, oz = OIL_FILTER
    dirn = unit(OIL_FILTER_DIR)
    d.cylinder("engine_block_filter_boss", (ox, oy, oz) - 0.9 * dirn, dirn, 3.0, 0.95)
    d.cylinder("oil_filter_adapter", (ox, oy, oz), dirn, 2.9, 0.4)
    across = unit(np.cross(dirn, [1.0, 0, 0]))
    d.revolve("oil_filter", np.array([ox, oy, oz]) + 0.4 * dirn, dirn, across,
              [(0.0, 0.0), (0.0, 1.68), (0.15, 1.83), (4.9, 1.83), (5.13, 1.62), (5.2, 0.0)])


# Run inside Blender: thin each body to a budget by its size, as make_sbc.py does.
ROUND = "r0.35"
REDUCE_FACTORS = [
    ("engine_block_deck", 0), ("engine_block_filter", ROUND), ("engine_block_", 1), ("engine_block", 0),
    ("cylinder_head", 0), ("valve_cover_body", 0), ("valve_cover_fins", 0), ("spark_plug", ROUND), ("head_bolts", 0), ("exhaust_port_bolts", 0),
    ("valve_cover_breather", ROUND), ("valve_cover_filler", ROUND), ("oil_filler", ROUND),
    ("air_cleaner_element", 0), ("alternator_fan_vanes", 0), ("air_cleaner", ROUND),
    ("crank_pulley", ROUND), ("upper_pulley", ROUND), ("alternator", ROUND), ("harmonic_balancer", ROUND),
    ("crank_bolt", ROUND), ("distributor_clamp", 1), ("distributor", ROUND), ("ignition_coil_strap", 1),
    ("ignition_coil", ROUND), ("oil_filter", ROUND), ("thermostat_bolts", 0), ("thermostat_housing", 0),
    ("thermostat", ROUND), ("starter_nose_mount", 1), ("starter_hump", 1), ("starter", ROUND),
    ("flywheel", ROUND), ("fan_spacer", ROUND), ("fan_hub", ROUND), ("water_pump_snout", ROUND),
    ("water_pump_inlet", ROUND), ("water_pump_heater", ROUND), ("fuel_pump", ROUND),
    ("carburetor_ring", ROUND), ("carb_throat", ROUND), ("carburetor_bowl_screw", ROUND),
    ("exhaust_collector", ROUND), ("exhaust_runner", "r0.08"), ("exhaust_manifold_outlet_flange", 0),
    ("exhaust_manifold_bore", ROUND), ("exhaust_manifold", "r0.2"),
    ("intake_manifold_runner", "r0.12"),
    ("intake_manifold_crossover", "r0.2"), ("intake_manifold_heat", "r0.2"), ("intake_manifold_choke", 0),
    ("intake_manifold_bolt_bosses", ROUND),
    ("intake_manifold_pad_bosses", ROUND), ("intake_manifold_pad", 0), ("intake_manifold_plenum", 0), ("intake_manifold_thermostat_seat", 0),
    ("intake_manifold_distributor", ROUND),
    ("fan_blades", 2), ("belt", 3), ("oil_pan_body", 0), ("oil_pan_drain", ROUND),
]

FINISHES = [
    ("engine_block_deck_holes", BLACK), ("engine_block_deck", MACHINED), ("cylinder_bores", MACHINED),
    ("piston", CAST_ALUMINUM), ("engine_block_lifters", STEEL),
    ("cylinder_head_1_pushrods", STEEL), ("cylinder_head_-1_pushrods", STEEL),
    ("cylinder_head_1_ports", BLACK), ("cylinder_head_-1_ports", BLACK),
    ("exhaust_port_bolts", STEEL), ("head_bolts", STEEL),
    ("valve_bolt", STEEL), ("valve_cover_breather", BLACK), ("oil_filler", BLACK),
    ("spark_plug_base", STEEL), ("spark_plug_tip", STEEL), ("spark_plug", PORCELAIN),
    ("freeze_plug", STEEL),
    ("intake_bolts", STEEL), ("intake_manifold_plenum_floor", BLACK), ("intake_manifold", CAST_IRON),
    ("thermostat_neck_bore", BLACK), ("thermostat_bolts", STEEL), ("thermostat", CAST_IRON),
    ("water_pump_inlet_bore", BLACK), ("water_pump_heater_bore", BLACK),
    ("exhaust_manifold_bore", BLACK), ("exhaust_manifold", CAST_IRON), ("exhaust", HEADER),
    ("ignition_coil_strap", STEEL), ("ignition_coil", BLACK),
    ("carb_throat", BLACK), ("carburetor", ZINC),
    ("air_cleaner_element", FILTER), ("air_cleaner_wingnut", CHROME), ("air_cleaner", BLACK),
    ("distributor_cap", BLACK), ("distributor", STEEL),
    ("harmonic_balancer_ring", RUBBER), ("harmonic_balancer", STEEL), ("crank_pulley", STEEL),
    ("crank_bolt", STEEL), ("upper_pulley", STEEL), ("alternator_pulley", STEEL),
    ("fan_spacer", STEEL), ("fan", BLACK), ("belt", RUBBER),
    ("alternator_stator", STEEL), ("alternator_fan", STEEL), ("alternator_vents", BLACK),
    ("alternator", CAST_ALUMINUM), ("accessory_bracket", BLACK),
    ("fuel_pump_bowl", STEEL), ("fuel_pump_fitting", STEEL), ("fuel_pump", CAST_IRON),
    ("starter_nose", CAST_ALUMINUM), ("starter", BLACK),
    ("flywheel", STEEL), ("oil_filter", FILTER_CAN), ("oil_pan_drain", STEEL),
]


def internals_meshes(bore, stroke, rod):
    """{name: mesh} in inches for what shows with the intake and heads off."""
    out, walls, floors, lifters = {}, [], [], []
    cut = bore_cut(stroke, rod)
    vz = valley_z()
    for s in (1, -1):
        u = v3(bank(s)[0])
        for i, x in enumerate(BORE_X):
            depth = em.piston_depth(throw_angle(s, i), stroke, rod)
            wall, piston = em.bore_and_piston(p3(bank_x(s, x), on_head(s, DECK_OUT, 0.0)), u, bore, depth, cut)
            walls.append(wall)
            out[f"piston_{s}_{i + 1}"] = piston
        for x, a, r in deck_holes():
            floors.append(em.disc(p3(bank_x(s, x), on_head(s, a, 0.004)), u, r * 0.95, 10))
        lin, lr, lh = LIFTER
        ly = deck_inner(1)[0] - lin
        rods = []
        for x in BORE_X:
            for k in (-1, 1):
                base = np.array([bank_x(s, x + k * LIFTER_X), s * ly, vz]) - u * 0.2
                lifters.append(em.cylinder(base, u, lr, lh + 0.2, 12))
                top = base + u * (lh + 0.2)
                h = (top[1:] - deck_edge(s)) @ bank(s)[0]
                rods.append(em.cylinder(top, u, PUSHROD_R, 0.6 - h, 6))
        out[f"cylinder_head_{s}_pushrods"] = em.merge(rods)

        # The head's intake face: a port where each runner meets it, the water passage's
        # hole at the front, the intake bolts' holes.
        inn = v3(bank(s)[2])
        ports = []
        hl, hh, cr = INTAKE_PORT
        for x in BORE_X:
            ports.append(em.rounded_rect(p3(bank_x(s, x), on_head(s, INTAKE_FACE_A + 0.004, INTAKE_PORT_H)),
                                         inn, (1, 0, 0), hl, hh, cr))
        wx, wh, wr = INTAKE_WATER
        ports.append(em.disc(p3(bank_x(s, wx), on_head(s, INTAKE_FACE_A + 0.004, wh)), inn, wr, 12))
        for x in INTAKE_BOLT_X:
            ports.append(em.disc(p3(bank_x(s, x), on_head(s, INTAKE_FACE_A + 0.004, INTAKE_BOLT_T)), inn, 0.2, 8))
        out[f"cylinder_head_{s}_ports"] = em.merge(ports)
    out.update({"cylinder_bores": em.merge(walls), "engine_block_deck_holes": em.merge(floors),
                "engine_block_lifters": em.merge(lifters)})
    return out


def reduce_obj(src, dst, blender):
    r = subprocess.run([blender, "-b", "--factory-startup", "--python-expr", BLENDER_REDUCE,
                        "--", src, dst, json.dumps(REDUCE_FACTORS)], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(dst):
        sys.exit(f"blender: {r.stderr.strip() or r.stdout.strip()}")


def finish_for(name, what="engine"):
    if what == "cover" and name.startswith("valve_cover") and not name.startswith("valve_cover_breather"):
        return SATIN_ALUMINUM
    if what == "intake" and name.startswith("intake_manifold") and not name.startswith("intake_manifold_plenum_floor"):
        return SATIN_ALUMINUM
    for prefix, mat in FINISHES:
        if name.startswith(prefix):
            return mat
    return FORD_BLUE


def main():
    global DECK
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("what", nargs="?", default="engine", choices=("engine", "headers", "cover", "intake"),
                    help="the whole engine with its cast-iron manifolds (default); or alone: a set of "
                         "headers, the finned aluminum valve covers, the aluminum dual-plane intake")
    ap.add_argument("--headers", default="long", choices=sorted(COLLECTOR),
                    help="which headers: long tubes (default) or shorties")
    ap.add_argument("--deck", default="302", choices=sorted(DECKS),
                    help="302: the 260, 289 and 302's deck (default); 351: the 351 W's")
    ap.add_argument("--sc", help="design file (default resources/engines/STEM.sc)")
    ap.add_argument("--glb", help="mesh (default assets/parts/STEM.glb)")
    ap.add_argument("--solidcraft", default="solidcraft-cli",
                    help="solidcraft-cli, or the SolidCraft AppImage")
    ap.add_argument("--blender", default="blender", help="Blender, which thins the mesh")
    args = ap.parse_args()
    DECK = DECKS[args.deck]
    bore, stroke, rod = STROKES[args.deck]
    stem = {"engine": f"engine-sbf-{args.deck}", "headers": f"sbf-{args.deck}-headers-{args.headers}",
            "cover": f"sbf-{args.deck}-valve-covers-finned", "intake": f"sbf-{args.deck}-intake-aluminum"}[args.what]
    sc = os.path.abspath(args.sc or os.path.join(ROOT, "resources", "engines", stem + ".sc"))
    glb = os.path.abspath(args.glb or os.path.join(ROOT, "assets", "parts", stem + ".glb"))
    tool = shutil.which(args.solidcraft) or args.solidcraft
    if not os.path.exists(tool):
        sys.exit(f"no SolidCraft command line at {args.solidcraft}")
    blender = shutil.which(args.blender) or args.blender
    if not os.path.exists(blender):
        sys.exit(f"no Blender at {args.blender}")

    d = Ford()
    if args.what == "headers":
        headers(d, args.headers)
    elif args.what == "cover":
        finned_covers(d)
    elif args.what == "intake":
        intake(d, stock=False)
    else:
        block(d)
        deck(d, bore, stroke, rod)
        heads(d)
        valve_covers(d)
        intake(d)
        carb_and_cleaner(d)
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
        print("thinning the mesh")
        thin = os.path.join(tmp, "thin.obj")
        reduce_obj(obj, thin, blender)
        bodies = read_tris(thin)

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
        merged.update(em.to_mm(internals_meshes(bore, stroke, rod)))
    parts = []
    for name, (p, nr, i) in merged.items():
        p = p * 0.001 / 0.22 + np.array([0.0, 0.0, -0.36])
        parts.append((name, p, nr, i, finish_for(name, args.what)))
    write_glb(glb, parts)
    allp = np.concatenate([p for _, p, *_ in parts])
    print(f"{os.path.relpath(sc, ROOT)}\n{os.path.relpath(glb, ROOT)}: {len(parts)} bodies, "
          f"{sum(len(i) for *_, i, _ in parts) // 3} triangles, extent "
          f"{np.round(allp.min(axis=0), 2).tolist()} to {np.round(allp.max(axis=0), 2).tolist()}")


if __name__ == "__main__":
    main()
