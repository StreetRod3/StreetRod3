#!/usr/bin/env python3
"""Build a small-block Chevy V8 in SolidCraft and export it as a game GLB.

    python3 tools/make_sbc.py

The engine is a small-block as it came in the sixties, measured from the CAD assembly of a
1965 L79 327 that tools/l79_to_glb.py reads (the block, the heads, the valve covers, the
intake, the distributor, the plugs, the coil, the oil filter and the starter are where and
the size they are on it), with long-tube headers, a 14 inch air cleaner, a Delco
alternator and a four-blade fan of its own. Only what shows from outside is drawn: no
internals, and nothing under the intake. It has:

  block         one outline across the engine, extruded front to back: the 45 degree
                bank walls down to the crankcase and the pan rail at the crank's height,
                the decks, and the valley under the intake; three freeze plugs in each
                bank wall, the side mount pads, the bellhousing flange at the back
  heads         the L79 head's outline across the bank, square to its deck: the exhaust
                face nearly upright with the ports high on it, the intake face square to
                the deck, the valve cover rail sloping down toward the valley; the spark
                plugs out of the exhaust face below the ports, leaning down and back
  valve covers  the 327's: a flange round the rail with four bolts on spreader bars, a
                plain body with a rounded top
  intake        the L79's dual plane: the flange and valley floor traced from above;
                square runners with rounded corners rising out of the ports, across,
                and turning into the plenum's front and back, the upper plane's
                higher than the lower's; the plenum under a square-flange pad with ears for its
                studs; the bolts on bosses along each side; the water crossover tube
                and thermostat housing at the front, the heat crossover, choke well and
                distributor boss
  carburetor    a square-flange four-barrel: throttle body, main body, fuel bowls front
                and back, and the 5 1/8 air cleaner ring on top
  air cleaner   14 inches round: the pan, a pleated paper element and a chrome lid with
                a rolled edge and a wing nut
  distributor   the housing standing in the intake at the back, right of the middle, the
                vacuum advance off its side, the cap with eight towers on top round the
                coil tower, the hold-down clamp
  coil          standing on the intake behind the carburetor, on the left
  oil filler    the tube out of the intake's front, forward and up, with its breather cap
  headers       long tubes (or shorties): a flange on each head, four 1 5/8 primaries
                out of the ports, one bend each, into a merge cone and a 3 inch collector
  front         stamped timing cover, the long water pump with its open hose necks, the
                balancer and a two-groove crank pulley, a two-groove pump pulley, the
                fan on a spacer, a Delco alternator high on the right on its bracket, and
                the belt round crank, pump and alternator
  starter       on the right below the pan rail: the motor, the solenoid above it on the
                outside, the nose back to the flywheel
  bottom        oil pan with the sump at the back, the oil filter hanging straight down
                at the back on the left, and the flywheel

Every part is a body of its own (SolidCraft's kernel takes minutes to join bodies), drawn
from numbers in this script, so to change the engine change the numbers and run it again.

Writes resources/engines/engine-sbc-350.sc, the SolidCraft design, and
assets/parts/engine-sbc-350.glb. Needs SolidCraft's command line (--solidcraft) and
Blender, as tools/make_flathead.py does.

The design is in inches with the crank on the X axis: +X toward the back of the car, +Y
to its right, +Z up, the block's middle on X = 0. The GLB is in the frame of the other
engine models (engine_assembly.gd): engine units of 0.22 m, the crank at Z -0.36. Node
names follow engine-v8-*.glb where there is a match (engine_block, cylinder_head_1,
valve_cover_-1, valve_bolt_..., intake_manifold, carburetor, carb_throat_..., distributor_cap,
crank_pulley, upper_pulley, alternator_pulley, water_pump_housing, accessory_bracket_right,
exhaust_collector_1, oil_pan, timing_cover), +1 the right bank and -1 the left. The game
does not use it yet.
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
    BLACK, CAST_ALUMINUM, CAST_IRON, MM, PAINT, PORCELAIN, RUBBER, S45, SATIN_ALUMINUM, STEEL, ZINC,
    Design, crease_normals, hull_outline, inch, outline_commands, pt3, read_tris, skp)
from make_wheels import SolidCraft, cmd, write_glb  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEM = "engine-sbc-350"

# The block. Bores, ports and bolts are along each bank from the bank's middle.
BLOCK_FRONT = -10.6
BLOCK_BACK = 10.6
DECK = 9.034            # crank to deck along the bank's axis
DECK_OUT = 3.258        # bank axis out to the deck's outer edge
DECK_IN = 3.4           # bank axis in to the deck's inner edge
VALLEY_Z = 8.6          # valley floor, under the intake
WALL_FOOT = (4.95, 1.0)  # where each bank's outer wall comes down to the skirt (|y|, z)
RAIL_Y = 5.1            # pan rail lip
RAIL_T = 0.25           # pan rail's thickness, up from the crank's height
# The valley's end walls, which the intake's ends sit on: x spans and their top.
CHINA_WALLS = [(-10.6, -9.55), (8.55, 10.6)]
CHINA_TOP = 9.81
HEAD_BOLT_X = [-8.8, -4.4, 0.0, 4.4, 8.8]   # the heads' lower bolts, under each deck's edge
# The bellhousing flange across the back, (y, z) for the right half, and its bolt bosses.
BELL_FLANGE = [(9.0, -0.15), (9.0, 4.35), (8.4, 4.8), (1.2, 9.0)]
BELL_BOSSES = [(7.7, 0.45), (8.3, 2.3), (7.8, 4.2), (4.0, 7.0)]
BORE_MID = -0.49        # the bores' middle along the crank, both banks
BANK_SHIFT = 0.425      # the right bank sits this far back of that, the left forward
BORE_X = [-6.6, -2.2, 2.2, 6.6]
# The exhaust ports along each bank: at the ends, and the middle pair.
EXHAUST_PORT_X = [-7.6, -0.86, 0.86, 7.6]
FREEZE_PLUG_X = [-2.2, 2.2, 6.6]   # under the bores, between the head bolts' bosses
FREEZE_PLUG_T = 0.5     # how far down the outer wall from the deck's edge

# The heads, in each deck's own frame: a in from the deck's outer edge, h up off it.
HEAD_HALF = 9.83
HEAD = [(0.5, 0.0), (8.1, 0.0), (7.7, 3.25), (3.05, 4.4), (2.9, 3.6), (0.5, 1.0)]
EXHAUST_FACE = ((0.5, 1.0), (2.9, 3.6))   # bottom and top, (a, h)
PORT_T = 0.675          # the exhaust ports' middles up that face, a fraction of it
PLUG = (1.22, 0.955)    # where each plug's axis passes, (a, h)
PLUG_DIR = (0.23, 0.96, -0.14)  # out of the head (x, out, up): down a little and back
RAIL = ((3.05, 4.4), (7.7, 3.25))         # the valve cover rail, outer and inner, (a, h)

# Valve covers, in the rail's frame: across from its outer edge, up off it.
COVER_FLANGE = (-0.07, 4.8, 9.81, 0.1)    # across, half length, thickness
COVER_BODY = (0.3, 4.45, 9.47)            # across, half length
COVER_H = 2.25
COVER_BOLTS = [(-4.4, 0.26), (4.4, 0.26), (-4.4, 4.46), (4.4, 4.46)]  # (x, across)

# Intake, after the L79's: a flange lying on each head's intake face along the head, and
# the floor over the valley between them, its outline from above (x, y) with a lobe round
# the distributor's boss, its ends stepping in by each head (the banks are offset: the
# right head starts behind the left and ends behind it too).
INTAKE_FLOOR = [
    (-10.70, -3.00), (-10.70, 2.22), (-10.67, 2.31), (-10.58, 2.38), (-10.12, 2.41),
    (-10.00, 2.48), (-9.94, 2.59), (-9.93, 3.00), (9.75, 3.00), (9.75, 2.53), (10.04, 1.98),
    (10.12, 1.55), (10.04, 1.12), (9.79, 0.70), (9.75, 0.55), (9.75, -2.22), (9.72, -2.31),
    (9.63, -2.38), (9.15, -2.41), (9.03, -2.47), (8.96, -2.59), (8.95, -3.00),
]
# The runners, square tubes with rounded corners, each one piece: up out of its port, a
# bend over level, across toward the middle, then a turn into the plenum's front or back:
# (x, the bank they leave, the height of their top, across, deep, the y they run into
# the plenum along (None: straight on into its side), the x they end at inside it).
INTAKE_RUNNERS = [
    (-5.85, -1, 13.1, 1.5, 1.5, -0.85, -2.3), (-4.6, -1, 12.2, 1.4, 1.4, -1.7, -2.3),
    (-5.1, 1, 12.6, 1.4, 1.4, 0.85, -2.3), (-3.75, 1, 12.0, 1.3, 1.35, 1.7, -2.3),
    (4.2, -1, 13.1, 1.5, 1.5, -0.85, 1.4), (2.8, -1, 12.2, 1.35, 1.4, -1.7, 1.4),
    (5.0, 1, 12.7, 1.4, 1.4, 0.85, 1.4), (3.65, 1, 12.2, 1.35, 1.4, 1.7, 1.4),
    (-1.25, -1, 11.7, 1.15, 1.15, None, -2.4),     # the exhaust heat passage
]
RUNNER_CORNER = 0.38
RUNNER_PORT = (4.15, 10.5, 53.0)   # where each leaves its port: |y|, z, its climb (degrees)
RUNNER_BENDS = (1.0, 1.0)          # radius over level, radius of the turn into the plenum
WATER_CROSSOVER = (-8.35, 11.25, 1.7, 4.15)    # x, z of its axis, diameter, |y| of its ends
HEAT_CROSSOVER = (7.75, 11.05, 1.0, 3.3)       # (the heat crossover's ends inside the bolts)
CHOKE_WELL = ((-0.35, 3.0), (0.75, 4.2), 12.4)  # the stove well's corners and top
INTAKE_BASE = (9.81, 10.65)  # the floor's underside (on the end walls) and top
# Each flange up its head's intake face from the deck, and its thickness, enough that its
# inner face meets the floor's edge at the floor's top; the floor stops short of the faces.
INTAKE_FLANGE = (0.1, 2.55, 0.64)
PAD_X = -0.45           # the carb pad's middle
PAD_Z = 13.15           # the carb pad's underside
PAD = (2.65, 2.6, 0.4)  # half length, half width, thickness
PAD_BOSSES = [(2.3, 2.58), (2.3, -2.58), (-3.3, 2.58), (-3.3, -2.58)]
# The pad's openings down into the plenum, as on the L79: the left plane's two barrels
# round, the right plane's one long slot, a web between; (x, y) from the pad's middle.
PAD_HOLES = [(-0.91, -0.95), (0.91, -0.95)]
PAD_HOLE_R = 0.8
PAD_SLOT = ((-0.99, 0.95), (0.99, 0.95), 0.82)
PLENUM_FLOOR = 1.1      # how far down the openings the plenum's dark floor is
INTAKE_BOLT_X = [-9.42, -7.1, -0.8, 1.52, 7.1, 9.42]   # the right bank's; the left's mirrored
INTAKE_BOLT_T = 1.4     # the bolts' line up each flange
DIST = (8.87, 1.55)     # distributor's axis (x, y)
THERMOSTAT = (-8.9, 0.06)
COIL = (6.7, -1.9)

# Front of the engine: the belt's plane and what it goes round, (y, z).
COVER_FACE = -11.4
BELT_X = -13.35
CRANK_PULLEY_R = 3.2
PUMP = (0.0, 7.03)
PUMP_PULLEY_R = 3.3
ALTERNATOR = (8.6, 10.6)
ALT_PULLEY_R = 1.45
FAN_X = -16.75
FAN_R = 9.0
FAN_PITCH = math.radians(28)

# Starter, on the right below the rail: its axis (y, z).
STARTER = (6.88, -1.77)
FLYWHEEL = (11.85, 0.86, 7.09)    # front face, thickness, radius

# Oil pan: the tray under the rail, the sump at the back. The oil filter hangs straight
# down beside it at the back on the left.
PAN_TRAY = (10.2, 4.3, 1.8)
SUMP = (0.8, 9.9, -4.3, 3.4, -7.3)  # x0, x1, y0, y1, bottom
OIL_FILTER = (8.88, -6.4)

# Headers: the collectors' front ends (x along the bank, |y|, z) and their axis.
COLLECTOR = {"long": ((9.0, 10.4, -6.8), (0.72, 0.0, -0.69)),
             "shorty": ((1.5, 11.4, -2.6), (0.8, 0.0, -0.6))}
PRIMARY_D = 1.625
PRIMARY_OUT = (1.0, 1.8)    # each primary straight out of its port, then its bend's radius
PRIMARY_MID_Z = 3.5         # down to here outside the plugs before bending back
PRIMARY_LEAN = (-0.3, 0.0, 0.0, 0.3)  # front to back: the end tubes lean off their plugs

CHROME = {"name": "chrome", "pbrMetallicRoughness": {
    "baseColorFactor": [0.9, 0.9, 0.92, 1], "metallicFactor": 1.0, "roughnessFactor": 0.12}}
FILTER = {"name": "filter paper", "pbrMetallicRoughness": {
    "baseColorFactor": [0.78, 0.66, 0.42, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}}
HEADER = {"name": "header steel", "pbrMetallicRoughness": {
    "baseColorFactor": [0.32, 0.31, 0.3, 1], "metallicFactor": 0.7, "roughnessFactor": 0.45}}
FILTER_CAN = {"name": "oil filter", "pbrMetallicRoughness": {
    "baseColorFactor": [0.75, 0.75, 0.73, 1], "metallicFactor": 0.1, "roughnessFactor": 0.4}}
# Body name prefixes to finishes, first match wins; anything else is the block's paint.
FINISHES = [
    ("valve_bolt", STEEL), ("valve_cover", CHROME),
    ("spark_plug_base", STEEL), ("spark_plug_tip", STEEL), ("spark_plug", PORCELAIN),
    ("intake_manifold_bolts", STEEL), ("intake_manifold", CAST_IRON),
    ("thermostat_neck_bore", BLACK), ("intake_manifold_plenum_floor", BLACK),
    ("thermostat_bolts", STEEL), ("water_pump_inlet_bore", BLACK),
    ("water_pump_heater_bore", BLACK), ("thermostat", CAST_IRON),
    ("ignition_coil_bracket", STEEL), ("ignition_coil_foot", STEEL), ("ignition_coil", BLACK),
    ("oil_filler", CHROME),
    ("carb_throat", BLACK), ("carburetor", ZINC),
    ("air_cleaner_element", FILTER), ("air_cleaner_wingnut", CHROME), ("air_cleaner", CHROME),
    ("distributor_cap", BLACK), ("distributor", STEEL),
    ("exhaust", HEADER), ("timing_cover", PAINT),
    ("water_pump", PAINT), ("harmonic_balancer_ring", RUBBER), ("harmonic_balancer", STEEL),
    ("crank_pulley", STEEL), ("upper_pulley", STEEL), ("alternator_pulley", STEEL),
    ("fan_spacer", STEEL), ("fan", BLACK), ("belt", RUBBER),
    ("alternator_stator", STEEL), ("alternator_fan", STEEL), ("alternator_vents", BLACK),
    ("alternator", CAST_ALUMINUM), ("accessory_bracket", BLACK),
    ("starter_nose", CAST_ALUMINUM), ("starter_solenoid", ZINC), ("starter", BLACK),
    ("flywheel", STEEL), ("oil_filter", FILTER_CAN), ("freeze_plug", STEEL),
]


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


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


def bank_x(s, x):
    return x + BORE_MID + s * BANK_SHIFT


def head_dir(s, a, h):
    """A direction in bank s's head frame, (a, h), as (y, z)."""
    u, _, inn = bank(s)
    return a * inn + h * u


def lerp(p, q, t):
    return np.asarray(p, float) + t * (np.asarray(q, float) - np.asarray(p, float))


def exhaust_face(s):
    """Bank s's exhaust face: a point on it (y, z), its direction up the face, and its
    outward normal, as (y, z)."""
    f0, f1 = (on_head(s, *p) for p in EXHAUST_FACE)
    up = unit(f1 - f0)
    n = np.array([up[1], -up[0]])
    if n[0] * s < 0:
        n = -n
    return f0, up, n


def port_center(s):
    return on_head(s, *lerp(*EXHAUST_FACE, PORT_T))


def p3(x, yz):
    return np.array([x, yz[0], yz[1]], float)


def v3(yz):
    return np.array([0.0, yz[0], yz[1]], float)


class SBC(Design):
    def plane(self, origin, x_dir, normal, name):
        """A sketch on the plane through origin (inches) square to normal, its x along
        x_dir; extruding positive goes along normal. Returns (name, to2d) where to2d maps
        a point in the design to the sketch's (x, y)."""
        x_dir, normal = unit(x_dir), unit(normal)
        x_dir = unit(x_dir - normal * (x_dir @ normal))
        y_dir = np.cross(normal, x_dir)
        origin = np.asarray(origin, float)
        self.n += 1
        self.c.append(cmd("sketch.create", name=name, plane={
            "origin": [round(float(v) * MM, 4) for v in origin],
            "x_dir": [round(float(v), 6) for v in x_dir], "y_dir": [round(float(v), 6) for v in y_dir]}))
        return name, lambda p: (float((np.asarray(p, float) - origin) @ x_dir),
                                float((np.asarray(p, float) - origin) @ y_dir))

    def body(self, name, kind, **params):
        self.c.append(cmd(kind, operation="new", name=name, body_name=name, **params))

    def revolve(self, name, origin, axis, radial, profile):
        """A body turned about the axis through origin from a closed outline of (along,
        out) points: along the axis and out along radial, square to it."""
        axis, radial = unit(axis), unit(radial)
        sk, _ = self.plane(origin, axis, np.cross(axis, radial), f"{name} profile")
        self.poly(profile)
        self.finish()
        self.body(name, "solid.revolve", sketch=sk, axis={
            "origin": [round(float(v) * MM, 4) for v in origin],
            "dir": [round(float(v), 6) for v in axis]})

    def cone(self, name, base, axis, r0, r1, length):
        self.body(name, "solid.cone", base=pt3(base), axis=[float(a) for a in unit(axis)],
                  radius=inch(r0), top_radius=inch(r1), height=inch(length))

    def sphere(self, name, center, dia):
        self.body(name, "solid.sphere", center=pt3(center), diameter=inch(dia))

    def circle(self, c, r):
        self.c.append(cmd("sketch.circle.center", center=skp(*c), radius=inch(r)))

    def rounded(self, c0, c1, r):
        (x0, y0), (x1, y1) = c0, c1
        self.c.append(cmd("sketch.rectangle.rounded", p0=skp(min(x0, x1), min(y0, y1)),
                          p1=skp(max(x0, x1), max(y0, y1)), radius=inch(r)))

    def hexagon(self, c, across_flats):
        self.c.append(cmd("sketch.polygon.inscribed", center=skp(*c),
                          radius=round(across_flats / math.sqrt(3) * MM, 4), sides=6))

    def loft(self, name, sketches):
        self.body(name, "solid.loft", sections=[{"sketch": s} for s in sketches])


def ccw(pts):
    area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]))
    return pts if area > 0 else pts[::-1]


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
    """The block's outline across the engine (y, z), counterclockwise: the outer walls from
    the decks down to the skirts and the pan rail, the inner walls down to the valley."""
    edge = deck_edge(1)
    inner = on_head(1, DECK_OUT + DECK_IN, 0.0)
    valley_y = inner[0] - (inner[1] - VALLEY_Z)
    fy, fz = WALL_FOOT
    right = [(RAIL_Y, 0.0), (RAIL_Y, RAIL_T), (fy, RAIL_T), (fy, fz),
             tuple(edge), tuple(inner), (valley_y, VALLEY_Z)]
    left = [(-y, z) for y, z in reversed(right)]
    return ccw(right + left)


def block(d):
    outline = block_outline()
    sk = d.sketch("YZ", "Block", offset=BLOCK_FRONT)
    d.poly(outline)
    d.finish()
    d.extrude(sk, "engine_block", BLOCK_BACK - BLOCK_FRONT)

    # The valley's front and back walls, up to where the intake's ends sit.
    for k, (x0, x1) in enumerate(CHINA_WALLS):
        sk = d.sketch("YZ", f"China wall {k}", offset=x0)
        # Up the inner walls and the decks to the heads' inner corners, flat across.
        inner = on_head(1, DECK_OUT + DECK_IN, 0.0)
        corner = on_head(1, HEAD[1][0], 0.0)
        foot = inner - (inner[1] - (VALLEY_Z - 0.2)) * np.array([1.0, 1.0])
        right = [tuple(foot), tuple(inner), (corner[0], CHINA_TOP)]
        d.poly(ccw(right + [(-y, z) for y, z in reversed(right)]))
        d.finish()
        d.extrude(sk, f"engine_block_end_wall_{k}", x1 - x0)

    # The bellhousing flange across the back: tall and square-shouldered, its top
    # rising to the middle, bolt bosses round it on its front.
    half = BELL_FLANGE
    pts = half + [(-y, z) for y, z in reversed(half)]
    sk = d.sketch("YZ", "Bell flange", offset=BLOCK_BACK)
    d.poly(ccw(pts))
    d.finish()
    d.extrude(sk, "engine_block_bell_flange", 0.35)
    sk = d.sketch("YZ", "Bell bosses", offset=BLOCK_BACK)
    for y, z in BELL_BOSSES:
        for side in (1, -1):
            d.circle((side * y, z), 0.45)
    d.finish()
    d.extrude(sk, "engine_block_bell_bosses", 0.4, "negative")

    for s in (1, -1):
        # The heads' lower bolt bosses, half round, down the outer wall from the deck.
        top, n = outer_wall(s, 0.0)
        down = unit(wall_foot(s) - deck_edge(s))
        for k, x in enumerate(HEAD_BOLT_X):
            d.cylinder(f"engine_block_bolt_boss_{s}_{k}", p3(bank_x(s, x), top - 0.05 * down),
                       v3(down), 0.85, 1.1)
        # Freeze plugs set in raised rings in the outer wall.
        c, n = outer_wall(s, FREEZE_PLUG_T)
        sk, to2d = d.plane(p3(0.0, c), (1, 0, 0), v3(n), f"Freeze plug rings {s}")
        for x in FREEZE_PLUG_X:
            d.circle(to2d(p3(bank_x(s, x), c)), 1.05)
            d.circle(to2d(p3(bank_x(s, x), c)), 0.82)
        d.finish()
        d.extrude(sk, f"engine_block_plug_rings_{s}", 0.14)
        sk, to2d = d.plane(p3(0.0, c), (1, 0, 0), v3(n), f"Freeze plugs {s}")
        for x in FREEZE_PLUG_X:
            d.circle(to2d(p3(bank_x(s, x), c)), 0.81)
        d.finish()
        d.extrude(sk, f"freeze_plug_{s}", 0.05)
        # The side mount's pad lower down, with its two bolt bosses.
        c, n = outer_wall(s, 0.82)
        sk, to2d = d.plane(p3(0.0, c), (1, 0, 0), v3(n), f"Mount pad {s}")
        m = to2d(p3(-6.2, c))
        d.rounded((m[0] - 1.6, m[1] - 0.6), (m[0] + 1.6, m[1] + 0.6), 0.35)
        d.finish()
        d.extrude(sk, f"engine_block_mount_{s}", 0.25)
        sk, to2d = d.plane(p3(0.0, c), (1, 0, 0), v3(n), f"Mount bosses {s}")
        for dx in (-1.05, 1.05):
            d.circle(to2d(p3(-6.2 + dx, c)), 0.38)
        d.finish()
        d.extrude(sk, f"engine_block_mount_bosses_{s}", 0.4)


# The heads.

def head_outline(s):
    return [tuple(on_head(s, a, h)) for a, h in HEAD]


def heads(d):
    for s in (1, -1):
        sk = d.sketch("YZ", f"Head {s}", offset=bank_x(s, -HEAD_HALF))
        d.poly(ccw(head_outline(s)))
        d.finish()
        d.extrude(sk, f"cylinder_head_{s}", 2 * HEAD_HALF)

        # Spark plugs out of the exhaust face below the ports, leaning down and back:
        # the hex where the axis leaves the face, the insulator, the terminal.
        f0, up, n = exhaust_face(s)
        dirn = unit([PLUG_DIR[0], s * PLUG_DIR[1], PLUG_DIR[2]])
        p_yz = on_head(s, *PLUG)
        # Where the axis, run outward from p, crosses the face's line.
        m = np.array([[dirn[1], -up[0]], [dirn[2], -up[1]]])
        t, _ = np.linalg.solve(m, f0 - p_yz)
        for k, x in enumerate(BORE_X):
            exit_ = p3(bank_x(s, x), p_yz) + t * dirn
            sk, to2d = d.plane(exit_, (1, 0, 0), dirn, f"Spark plug hex {s} {k}")
            d.hexagon(to2d(exit_), 0.63)
            d.finish()
            d.extrude(sk, f"spark_plug_base_{s}_{k}", 0.4, start_offset=inch(-0.1))
            d.cylinder(f"spark_plug_{s}_{k}", exit_ + 0.3 * dirn, dirn, 0.5, 1.0)
            d.cylinder(f"spark_plug_tip_{s}_{k}", exit_ + 1.3 * dirn, dirn, 0.25, 0.32)


def rail_frame(s):
    """Bank s's valve cover rail: its outer edge (y, z), across it toward the valley,
    and up off it, as (y, z)."""
    r0, r1 = (np.array(p, float) for p in RAIL)
    across = unit(r1 - r0)
    upa = np.array([-across[1], across[0]])
    return on_head(s, *r0), head_dir(s, *across), head_dir(s, *upa)


def valve_covers(d):
    for s in (1, -1):
        o, across, up = rail_frame(s)
        mid = bank_x(s, 0.0)

        def plane(lift, name):
            origin = p3(mid, o + lift * up)
            sk, to2d = d.plane(origin, (1, 0, 0), v3(up), name)
            return sk, lambda x, c: to2d(origin + np.array([x, 0, 0]) + c * v3(across))

        c0, c1, half, t = COVER_FLANGE
        sk, at = plane(0.0, f"Cover flange {s}")
        d.rounded(at(-half, c0), at(half, c1), 0.75)
        d.finish()
        d.extrude(sk, f"valve_cover_{s}", t)

        # The body, a little drafted, and its top rounded over by a steep second draft.
        c0, c1, half = COVER_BODY
        sk, at = plane(t, f"Cover body {s}")
        d.rounded(at(-half, c0), at(half, c1), 0.9)
        d.finish()
        side = COVER_H - t - 0.45
        d.extrude(sk, f"valve_cover_body_{s}", side, taper="-2 deg")
        shrink = side * math.tan(math.radians(2))
        sk, at = plane(t + side, f"Cover top {s}")
        d.rounded(at(-half + shrink, c0 + shrink), at(half - shrink, c1 - shrink), 0.9 - shrink)
        d.finish()
        d.extrude(sk, f"valve_cover_top_{s}", 0.45, taper="-42 deg")

        # Four bolts on spreader bars along the flange's edges.
        for i, (x, c) in enumerate(COVER_BOLTS):
            sk, at = plane(t, f"Cover bar {s} {i}")
            p = at(x, c)
            q = at(x + 1.0, c)
            if abs(q[0] - p[0]) > abs(q[1] - p[1]):
                d.rounded((p[0] - 0.75, p[1] - 0.22), (p[0] + 0.75, p[1] + 0.22), 0.2)
            else:
                d.rounded((p[0] - 0.22, p[1] - 0.75), (p[0] + 0.22, p[1] + 0.75), 0.2)
            d.finish()
            d.extrude(sk, f"valve_bolt_bar_{s}_{i}", 0.06)
            sk, at = plane(t + 0.06, f"Cover bolt {s} {i}")
            d.hexagon(at(x, c), 0.44)
            d.finish()
            d.extrude(sk, f"valve_bolt_{s}_{i}", 0.25)


# The intake.

def runner(d, name, x, s, top, w, h, entry_y, to_x):
    """A square runner with rounded corners from bank s's port at x: straight up and in
    out of the port, a bend over level, across, then (entry_y given) a turn along X into
    the plenum at entry_y, ending at to_x; else straight on to y = to_x."""
    y0, z0, climb = RUNNER_PORT
    th = math.radians(climb)
    zc = top - h / 2
    rise = zc - z0
    r1 = min(RUNNER_BENDS[0], 0.9 * rise / (1 - math.cos(th)))
    lead = max((rise - r1 * (1 - math.cos(th))) / math.sin(th), 0.05)
    r2 = RUNNER_BENDS[1]
    inward = np.array([0.0, -s, 0.0])
    p0 = np.array([x, s * y0, z0])
    y_turn = entry_y + s * r2 if entry_y is not None else to_x
    # Out of the port, in the plane across the engine at x: drawn with the sketch's y
    # down, so the bend over level turns counterclockwise as the sketch's arcs do.
    sk, to2d = d.plane(p0, inward, (s, 0, 0), f"{name} path")
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

    # The turn into the plenum, level: from going along Y round to going along X, drawn
    # on whichever face of the level plane makes it counterclockwise.
    pt = np.array([x, y_turn, zc])
    along = -s                                  # travel along Y
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


def intake_face(s):
    """Bank s's head's intake face: its foot on the deck (y, z), the way up it, and its
    normal toward the valley, all (y, z)."""
    (a0, h0), (a1, h1) = HEAD[1], HEAD[2]
    f0 = on_head(s, a0, h0)
    up = unit(on_head(s, a1, h1) - f0)
    n = np.array([-up[1], up[0]]) if s == 1 else np.array([up[1], -up[0]])
    if n @ (np.array([0.0, 10.0]) - f0) < 0:
        n = -n
    return f0, up, n


def crossover(d, name, x, zc, dia, y0):
    """A round passage across the engine at x between y = -y0 and y0: up out of the flange
    as the runners leave their ports, level across at zc, and back down into it."""
    _, z0, climb = RUNNER_PORT
    th = math.radians(climb)
    rise = zc - z0
    r = min(RUNNER_BENDS[0], 0.9 * rise / (1 - math.cos(th)))
    lead = max((rise - r * (1 - math.cos(th))) / math.sin(th), 0.05)
    p0 = np.array([x, -y0, z0])
    # Drawn with the sketch's y down, so both bends turn counterclockwise.
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


def intake(d):
    # The floor over the valley, its ends on the block's end walls.
    z0, z1 = INTAKE_BASE
    sk = d.sketch("XY", "Intake floor", offset=z0)
    d.poly(ccw([tuple(p) for p in INTAKE_FLOOR]))
    d.finish()
    d.extrude(sk, "intake_manifold", z1 - z0)

    # The flange on each head's intake face, the length of the head, the bolts down
    # through it on round bosses.
    t0, t1, thick = INTAKE_FLANGE
    for s in (1, -1):
        f0, up, n = intake_face(s)
        x0, x1 = bank_x(s, -HEAD_HALF) + 0.05, bank_x(s, HEAD_HALF) - 0.05
        sk, to2d = d.plane(p3(0.0, f0), (1, 0, 0), v3(n), f"Intake flange {s}")
        d.rounded(to2d(p3(x0, f0 + t0 * up)), to2d(p3(x1, f0 + t1 * up)), 0.3)
        d.finish()
        d.extrude(sk, f"intake_manifold_flange_{s}", thick)
        bolt = f0 + INTAKE_BOLT_T * up + thick * n
        sk, to2d = d.plane(p3(0.0, bolt), (1, 0, 0), v3(n), f"Intake bolt bosses {s}")
        for x in INTAKE_BOLT_X:
            d.circle(to2d(p3(bank_x(s, s * x), bolt)), 0.48)
        d.finish()
        d.extrude(sk, f"intake_manifold_bolt_bosses_{s}", 0.15, start_offset=inch(-0.05))
        sk, to2d = d.plane(p3(0.0, bolt), (1, 0, 0), v3(n), f"Intake bolts {s}")
        for x in INTAKE_BOLT_X:
            d.hexagon(to2d(p3(bank_x(s, s * x), bolt)), 0.5)
        d.finish()
        d.extrude(sk, f"intake_manifold_bolts_{s}", 0.28, start_offset=inch(0.1))

    # The runners, out of each port and round into the plenum.
    for k, (x, s, top, w, h, entry_y, to_x) in enumerate(INTAKE_RUNNERS):
        runner(d, f"intake_manifold_runner_{k}", x, s, top, w, h, entry_y, to_x)
    # The water crossover across the front, between the heads' front water ports.
    crossover(d, "intake_manifold_crossover", *WATER_CROSSOVER)
    # The exhaust heat crossover at the back, under the distributor, and the choke's
    # stove well on the right.
    crossover(d, "intake_manifold_heat_crossover", *HEAT_CROSSOVER)
    (cx0, cy0), (cx1, cy1), ctop = CHOKE_WELL
    sk = d.sketch("XY", "Choke well", offset=z1 - 0.1)
    d.rounded((cx0, cy0), (cx1, cy1), 0.3)
    d.finish()
    d.extrude(sk, "intake_manifold_choke_well", ctop - z1 + 0.1, taper="-4 deg")

    # The plenum: solid up to its dark floor, then its walls round the pad's openings
    # up to the pad, which has ears for the carb's studs.
    px, py, pt = PAD
    floor = PAD_Z - PLENUM_FLOOR
    sk = d.sketch("XY", "Plenum", offset=z1 - 0.1)
    d.rounded((PAD_X - px - 0.1, -py - 0.1), (PAD_X + px + 0.1, py + 0.1), 0.8)
    d.finish()
    d.extrude(sk, "intake_manifold_plenum", floor - z1 + 0.1)

    def openings(first):
        # The slot's lines and arcs are numbered on from the outline's, so it goes before
        # the circles, which take arc numbers of their own.
        (sx0, sy0), (sx1, sy1), sr = PAD_SLOT
        d.c += outline_commands(*hull_outline([((PAD_X + sx0, sy0), sr), ((PAD_X + sx1, sy1), sr)]),
                                first=first)
        for x, y in PAD_HOLES:
            d.circle((PAD_X + x, y), PAD_HOLE_R)

    corners = [((PAD_X + sx * (px + 0.1 - 0.8), sy * (py + 0.1 - 0.8)), 0.8)
               for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))]
    sk = d.sketch("XY", "Plenum walls", offset=floor)
    d.c += outline_commands(*hull_outline(corners))
    openings(5)
    d.finish()
    d.extrude(sk, "intake_manifold_plenum_walls", PAD_Z - floor)
    sk = d.sketch("XY", "Plenum floor", offset=floor)
    openings(1)
    d.finish()
    d.extrude(sk, "intake_manifold_plenum_floor", 0.02)

    sk = d.sketch("XY", "Carb pad", offset=PAD_Z)
    # The outline round the studs' bosses, taken in turn round the pad.
    mid = np.mean(PAD_BOSSES, axis=0)
    bosses = sorted(PAD_BOSSES, key=lambda p: math.atan2(p[1] - mid[1], p[0] - mid[0]))
    d.c += outline_commands(*hull_outline([((x, y), 0.55) for x, y in bosses]))
    openings(5)
    d.finish()
    d.extrude(sk, "intake_manifold_pad", pt)
    # The pad's bolt bosses stand at the plenum's corners, cast up from the flange
    # and the runners.
    sk = d.sketch("XY", "Pad bosses", offset=z1 - 0.1)
    for x, y in PAD_BOSSES:
        d.circle((x, y), 0.45)
    d.finish()
    d.extrude(sk, "intake_manifold_pad_bosses", PAD_Z + pt + 0.12 - (z1 - 0.1))

    # The distributor's boss at the back, the housing's collar sitting on it.
    d.cylinder("intake_manifold_distributor_boss", (DIST[0], DIST[1], 10.2), (0, 0, 1), 2.1, 0.8)

    # The thermostat's seat, cast up from the flange round the crossover tube to a flat
    # top; the housing bolted down on it by its two ears, its outlet neck forward and up.
    tx, ty = THERMOSTAT
    # Outlines round circles taken in turn counterclockwise: an ear, the right of the
    # housing, the other ear, its left.
    seat = [((tx, ty - 1.9), 0.55), ((tx + 0.3, ty - 0.35), 1.35), ((tx, ty + 1.2), 0.55),
            ((tx - 0.4, ty - 0.35), 1.35)]
    seat_top = WATER_CROSSOVER[1] + WATER_CROSSOVER[2] / 2 + 0.15
    sk = d.sketch("XY", "Thermostat seat", offset=z1 - 0.05)
    d.c += outline_commands(*hull_outline(seat))
    d.finish()
    d.extrude(sk, "intake_manifold_thermostat_seat", seat_top - z1 + 0.05)
    sk = d.sketch("XY", "Thermostat ears", offset=seat_top)
    d.c += outline_commands(*hull_outline([((tx, ty - 1.9), 0.45), ((tx + 0.05, ty - 0.35), 1.2),
                                           ((tx, ty + 1.2), 0.45), ((tx - 0.05, ty - 0.35), 1.2)]))
    d.finish()
    d.extrude(sk, "thermostat_housing", 0.25)
    d.revolve("thermostat_dome", (tx, ty - 0.35, 0.0), (0, 0, 1), (1, 0, 0),
              [(seat_top + 0.2, 0.0), (seat_top + 0.2, 1.25), (seat_top + 0.75, 1.2),
               (seat_top + 1.15, 0.95), (seat_top + 1.3, 0.0)])
    sk = d.sketch("XY", "Thermostat bolts", offset=seat_top + 0.25)
    for y in (ty - 1.9, ty + 1.2):
        d.hexagon((tx, y), 0.5)
    d.finish()
    d.extrude(sk, "thermostat_bolts", 0.3)
    neck = np.array([tx, ty, seat_top + 0.6])
    dirn = unit([-0.6, 0.0, 0.8])
    hose_neck(d, "thermostat_neck", neck, dirn, 0.775, 0.6, 2.25, 1.4)
    d.cylinder("thermostat_bead", neck + 1.75 * dirn, dirn, 1.72, 0.18)


def hose_neck(d, name, base, dirn, r, bore, length, depth):
    """A hose neck from base along dirn, open at its end: a bore depth deep, and a dark
    floor in the bore so the hollow shows."""
    radial = unit(np.cross(dirn, [1.0, 0.0, 0.0]) if abs(dirn[0]) < 0.9 else np.cross(dirn, [0, 1.0, 0]))
    d.revolve(name, base, dirn, radial,
              [(0.0, 0.0), (0.0, r), (length, r), (length, bore), (length - depth, bore),
               (length - depth, 0.0)])
    d.cylinder(f"{name}_bore", base + (length - depth) * dirn, dirn, 2 * bore - 0.02, 0.02)


def coil(d):
    """The ignition coil on its bracket on the intake, behind the carburetor on the left."""
    x, y = COIL
    d.cylinder("ignition_coil_foot", (x, y, INTAKE_BASE[1] - 0.05), (0, 0, 1), 1.4, 0.65)
    d.revolve("ignition_coil", (x, y, 0.0), (0, 0, 1), (1, 0, 0),
              [(11.5, 0.0), (11.5, 1.05), (16.4, 1.05), (16.6, 1.15), (16.95, 1.15),
               (17.05, 0.95), (17.05, 0.0)])
    d.revolve("ignition_coil_tower", (x, y, 0.0), (0, 0, 1), (1, 0, 0),
              [(17.0, 0.0), (17.0, 0.42), (17.55, 0.38), (17.65, 0.25), (17.65, 0.0)])
    d.revolve("ignition_coil_bracket", (x, y, 0.0), (0, 0, 1), (1, 0, 0),
              [(13.3, 1.0), (13.3, 1.17), (14.0, 1.17), (14.0, 1.0)])
    for k, ang in enumerate((90, 270)):
        t = math.radians(ang)
        c = (x + 1.3 * math.cos(t), y + 1.3 * math.sin(t))
        d.cylinder(f"ignition_coil_post_{k}", (c[0], c[1], 16.95), (0, 0, 1), 0.3, 0.3)


def oil_filler(d):
    """The oil filler tube out of the intake's front, forward and up, and its cap."""
    p0 = np.array([-10.0, -0.3, 10.6])
    p1 = np.array([-13.55, -1.65, 16.2])
    dirn = unit(p1 - p0)
    d.cylinder("oil_filler", p0, dirn, 1.2, float(np.linalg.norm(p1 - p0)))
    across = unit(np.cross(dirn, [0, 1, 0]))
    d.revolve("oil_filler_cap", p1, dirn, across,
              [(-0.2, 0.0), (-0.2, 0.75), (0.1, 1.45), (0.55, 1.5), (0.9, 1.35), (1.1, 0.9),
               (1.15, 0.0)])


# The carburetor and air cleaner.

def carburetor(d):
    z = PAD_Z + PAD[2]
    x = PAD_X
    d.box("carburetor_base", (x - 2.8, -2.65, z), (x + 2.8, 2.65, z + 0.75))
    z += 0.75
    d.box("carburetor", (x - 2.25, -2.5, z), (x + 2.25, 2.5, z + 1.5))
    for end, x0, x1 in (("front", -4.0, -2.25), ("back", 2.25, 4.0)):
        sk = d.sketch("XY", f"Bowl {end}", offset=z - 0.15)
        d.rounded((x + x0, -2.35), (x + x1, 2.35), 0.45)
        d.finish()
        d.extrude(sk, f"carburetor_bowl_{end}", 2.55)
        sx = x0 if end == "front" else x1
        d.cylinder(f"carburetor_bowl_screw_{end}", (x + sx, 1.6, z + 1.9), (np.sign(sx), 0, 0), 0.4, 0.15)
    z += 1.5
    d.box("carburetor_air_horn", (x - 2.25, -2.5, z), (x + 2.25, 2.5, z + 0.35))
    z += 0.35
    sk = d.sketch("XY", "Air cleaner ring", offset=z)
    d.circle((x, 0), 2.5625)
    d.circle((x, 0), 2.35)
    d.finish()
    d.extrude(sk, "carburetor_ring", 0.55)
    for tx in (-0.91, 0.91):
        for ty in (-0.95, 0.95):
            d.cylinder(f"carb_throat_{tx}_{ty}", (x + tx, ty, z), (0, 0, 1), 1.56 if tx < 0 else 1.69, 0.04)
    return z + 0.55


def air_cleaner(d, zb):
    x = PAD_X
    o = np.array([x, 0.0, zb])
    d.revolve("air_cleaner_base", o, (0, 0, 1), (1, 0, 0),
              [(0.0, 2.6), (0.0, 7.3), (0.6, 7.3), (0.6, 7.15), (0.12, 7.15), (0.12, 2.6)])
    # The pleated paper element, round a solid inner ring.
    n = 120
    pleats = []
    for i in range(2 * n):
        t = math.pi * i / n
        r = 7.0 if i % 2 == 0 else 6.78
        pleats.append((x + r * math.cos(t), r * math.sin(t)))
    sk = d.sketch("XY", "Element", offset=zb + 0.12)
    d.poly(pleats)
    d.circle((x, 0), 6.2)
    d.finish()
    d.extrude(sk, "air_cleaner_element", 3.0)
    zl = zb + 3.12
    d.revolve("air_cleaner_lid", o, (0, 0, 1), (1, 0, 0),
              [(3.12 - 0.5, 7.3), (3.12 + 0.05, 7.3), (3.12 + 0.35, 6.7), (3.12 + 0.78, 0.45),
               (3.12 + 0.64, 0.45), (3.12 + 0.22, 6.65), (3.12 - 0.05, 7.15), (3.12 - 0.5, 7.15)])
    d.cylinder("air_cleaner_stud", (x, 0, zl + 0.5), (0, 0, 1), 0.3, 1.2)
    d.cylinder("air_cleaner_wingnut", (x, 0, zl + 0.78), (0, 0, 1), 0.75, 0.5)
    sk = d.sketch("XZ", "Wing nut", offset=0.0)
    for side in (1, -1):
        d.poly([(x + side * 0.3, -(zl + 0.8)), (x + side * 1.25, -(zl + 1.05)),
                (x + side * 1.35, -(zl + 1.6)), (x + side * 0.95, -(zl + 1.65)),
                (x + side * 0.3, -(zl + 1.25))])
    d.finish()
    d.extrude(sk, "air_cleaner_wingnut_wings", 0.12, "symmetric")


def distributor(d):
    """Only the outside: the housing out of the intake's boss, the cap, the vacuum advance
    and the hold-down clamp."""
    x, y = DIST
    o = np.array([x, y, 0.0])
    d.revolve("distributor_body", o, (0, 0, 1), (1, 0, 0),
              [(10.4, 0.0), (10.4, 0.64), (11.0, 0.64), (11.0, 0.9), (11.25, 0.9), (11.25, 0.64),
               (12.6, 0.64), (12.7, 1.86), (13.05, 1.86), (13.05, 0.0)])
    d.revolve("distributor_cap", o, (0, 0, 1), (1, 0, 0),
              [(13.0, 0.0), (13.0, 2.05), (13.3, 2.13), (13.5, 2.05), (14.95, 2.05), (15.2, 1.68),
               (16.35, 1.72), (16.6, 1.58), (16.72, 1.3), (16.72, 0.0)])
    # Eight towers standing up round the top, and the coil tower in the middle.
    for k in range(8):
        t = 2 * math.pi * (k + 0.5) / 8
        base = o + np.array([1.2 * math.cos(t), 1.2 * math.sin(t), 16.4])
        d.cylinder(f"distributor_cap_tower_{k}", base, (0, 0, 1), 0.64, 0.9)
    d.cylinder("distributor_cap_coil_tower", o + np.array([0, 0, 16.5]), (0, 0, 1), 0.74, 1.1)
    # The vacuum advance off the housing toward the front on the right, by the cap.
    arm = unit([-0.72, 0.68, 0.0])
    z = 13.5
    d.cylinder("distributor_vacuum_arm", o + np.array([0, 0, z]) + 1.7 * arm, arm, 0.6, 0.7)
    d.cylinder("distributor_vacuum", o + np.array([0, 0, z]) + 2.25 * arm, arm, 2.2, 1.2)
    d.cone("distributor_vacuum_end", o + np.array([0, 0, z]) + 3.45 * arm, arm, 1.1, 0.6, 0.35)
    d.cylinder("distributor_vacuum_nipple", o + np.array([0, 0, z]) + 3.8 * arm, arm, 0.25, 0.45)
    # The hold-down clamp over the collar, its bolt in front.
    d.box("distributor_clamp", (x - 2.0, y - 0.35, 11.25), (x - 0.55, y + 0.35, 11.45))
    d.cylinder("distributor_clamp_bolt", (x - 1.55, y, 11.45), (0, 0, 1), 0.55, 0.3)


# The headers.

def tube_path(p0, n, target, lead=1.0, radius=2.2):
    """A primary's path in its own plane: out of the port along n, one bend, straight to
    target. Returns (plane x, plane y, points (start, bend start, bend centre, bend end,
    end) in plane coordinates)."""
    p1 = p0 + lead * n
    w = target - p1
    e2 = unit(w - n * (w @ n))
    tx, ty = (target - p0) @ n, (target - p0) @ e2
    c = np.array([lead, radius])
    dvec = np.array([tx, ty]) - c
    dist = np.linalg.norm(dvec)
    phi = math.atan2(dvec[1], dvec[0]) - math.acos(min(radius / dist, 1.0))
    q = c + radius * np.array([math.cos(phi), math.sin(phi)])
    return n, e2, [(0.0, 0.0), (lead, 0.0), tuple(c), tuple(q), (tx, ty)]


def headers(d, style):
    (cx, cy, cz), axis = COLLECTOR[style]
    axis = unit(axis)
    for s in (1, -1):
        n = v3(exhaust_face(s)[2])         # out of the exhaust face
        port_yz = port_center(s)
        # The flange over all four ports.
        sk, to2d = d.plane(p3(0.0, port_yz), (1, 0, 0), n, f"Header flange {s}")
        x0, x1 = bank_x(s, EXHAUST_PORT_X[0] - 1.05), bank_x(s, EXHAUST_PORT_X[-1] + 1.05)
        a, b = to2d(p3(x0, port_yz)), to2d(p3(x1, port_yz))
        d.rounded((a[0], a[1] - 0.82), (b[0], b[1] + 0.82), 0.3)
        d.finish()
        d.extrude(sk, f"exhaust_flange_{s}", 0.375)

        front = np.array([bank_x(s, cx), s * cy, cz])
        # Two pairs side by side across the collector's mouth.
        across = unit(np.cross(axis, [0, 0, 1])) if abs(axis[2]) < 0.99 else np.array([0, 1, 0])
        up = np.cross(across, axis)
        mouths = [front + 0.62 * (i * across + j * up) for i, j in ((-1, 1), (1, 1), (-1, -1), (1, -1))]
        ports = [p3(bank_x(s, x), port_yz) + 0.375 * n for x in EXHAUST_PORT_X]
        # The front ports to the mouths nearest them.
        order = sorted(range(4), key=lambda k: ports[k][0])
        mouth_order = sorted(range(4), key=lambda k: (mouths[k] @ np.array([1.0, 0, 0]),
                                                      -s * mouths[k][1]))
        for k_port, k_mouth in zip(order, mouth_order):
            # Out of the port and down outside the plugs to below them, the end tubes
            # leaning away from their plugs; then one bend back into the collector.
            p0, target = ports[k_port] - 0.375 * n, mouths[k_mouth]
            lean = PRIMARY_LEAN[order.index(k_port)]
            drop = unit([lean, 0.0, -1.0])
            corner = p0 + (PRIMARY_OUT[0] + PRIMARY_OUT[1]) * n
            mid = corner + (corner[2] - PRIMARY_MID_Z) * drop / -drop[2]
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
        # The merge cone over the tubes' ends, the collector, its flange.
        d.cone(f"exhaust_collector_{s}", front - 0.4 * axis, axis, 2.05, 1.5, 3.4)
        d.cylinder(f"exhaust_collector_pipe_{s}", front + 3.0 * axis, axis, 3.0, 3.0)
        d.cylinder(f"exhaust_collector_flange_{s}", front + 6.0 * axis, axis, 4.6, 0.375)


# The front of the engine.

def front(d):
    # Timing cover: round the crank and up round the cam sprocket.
    sk = d.sketch("YZ", "Timing cover", offset=BLOCK_FRONT)
    d.c += outline_commands(*hull_outline([((0.0, 0.0), 3.7), ((0.0, 4.7), 2.6)]))
    d.finish()
    d.extrude(sk, "timing_cover", BLOCK_FRONT - COVER_FACE, "negative")

    # Water pump: the body bolted to the block's front over the cover, the snout, the
    # hub flange, the lower hose inlet on the right and the heater fitting on the left.
    sk = d.sketch("YZ", "Water pump", offset=BLOCK_FRONT)
    d.c += outline_commands(*hull_outline([((4.2, 4.6), 0.9), (PUMP, 2.7), ((-4.2, 4.6), 0.9)]))
    d.finish()
    d.extrude(sk, "water_pump_housing", 1.5, "negative")
    py, pz = PUMP
    snout0 = BLOCK_FRONT - 1.5
    d.cone("water_pump_snout", (snout0, py, pz), (-1, 0, 0), 2.1, 1.05, snout0 + 14.3)
    d.cylinder("water_pump_hub", (-14.3, py, pz), (-1, 0, 0), 3.4, 0.15)
    inlet = np.array([snout0 + 0.6, 2.4, 5.0])
    dirn = unit([-0.55, 0.62, -0.56])
    hose_neck(d, "water_pump_inlet", inlet, dirn, 0.875, 0.7, 3.2, 1.6)
    hose_neck(d, "water_pump_heater", np.array([snout0 - 0.4, -1.6, 8.6]), np.array([-1.0, 0, 0]),
              0.4, 0.27, 1.4, 0.8)

    # Balancer and the pulleys, turned about the X axis: (x, r) outlines.
    def turned(name, yz, profile):
        d.revolve(name, p3(0.0, yz), (1, 0, 0), (0, 0, 1), profile)

    turned("harmonic_balancer", (0.0, 0.0),
           [(COVER_FACE, 0.0), (COVER_FACE, 3.37), (-13.0, 3.37), (-13.0, 0.0)])
    turned("harmonic_balancer_ring", (0.0, 0.0),
           [(-12.0, 2.55), (-12.0, 3.38), (-12.12, 3.38), (-12.12, 2.55)])

    def grooves(x_back, n, r, root):
        """A pulley's rim outline from x_back forward: n V grooves, out to r, root deep."""
        pts = [(x_back, r)]
        x = x_back
        for _ in range(n):
            pts += [(x - 0.1, r), (x - 0.35, root), (x - 0.45, root), (x - 0.7, r)]
            x -= 0.7
        return pts, x

    rim, x_front = grooves(-13.0, 2, CRANK_PULLEY_R, CRANK_PULLEY_R - 0.42)
    turned("crank_pulley", (0.0, 0.0), [(-13.0, 0.0)] + rim + [(x_front, 0.0)])
    turned("crank_bolt", (0.0, 0.0), [(x_front, 0.0), (x_front, 0.55), (x_front - 0.5, 0.55),
                                       (x_front - 0.5, 0.0)])

    # The pump's pulley: the same rim, dished back to a web at its front on the hub.
    rim, x_front = grooves(-13.0, 2, PUMP_PULLEY_R, PUMP_PULLEY_R - 0.42)
    turned("upper_pulley", PUMP, [(-13.0, PUMP_PULLEY_R - 0.55)] + rim
           + [(x_front, 0.6), (x_front + 0.2, 0.6), (x_front + 0.2, PUMP_PULLEY_R - 0.55)])

    # The fan on its spacer: a hub plate and four pitched blades.
    spacer0 = x_front
    d.cylinder("fan_spacer", (spacer0, py, pz), (-1, 0, 0), 2.5, spacer0 - FAN_X - 0.1)
    d.cylinder("fan_hub", (FAN_X + 0.08, py, pz), (-1, 0, 0), 5.0, 0.16)
    # Each blade lofted through sections across it, twisted from steep at the root to
    # flatter at the tip, the last section narrower to round the tip off: (radius, half
    # chord, pitch in degrees).
    center = np.array([FAN_X, py, pz])
    sections = [(2.1, 0.95, 38), (5.5, 1.8, 30), (8.3, 2.05, 23), (FAN_R, 1.35, 20)]
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
            # A thin section, a little cambered.
            pts = [mid + half * chord, mid + 0.4 * half * chord + 0.09 * across,
                   mid - 0.4 * half * chord + 0.09 * across, mid - half * chord,
                   mid - 0.4 * half * chord - 0.04 * across, mid + 0.4 * half * chord - 0.04 * across]
            d.poly([to2d(q) for q in pts])
            d.finish()
            sketches.append(sk)
        d.loft(f"fan_blades_{k}", sketches)

    alternator(d)

    # The belt round crank, alternator and pump, in the back grooves.
    belt_x = -13.0 - 0.1 - 0.3
    ring = [((0.0, 0.0), CRANK_PULLEY_R - 0.2), (ALTERNATOR, ALT_PULLEY_R - 0.2),
            (PUMP, PUMP_PULLEY_R - 0.2)]
    sk = d.sketch("YZ", "Belt", offset=belt_x)
    d.c += outline_commands(*hull_outline(ring))
    d.c += outline_commands(*hull_outline([(c, r + 0.33) for c, r in ring]), first=len(ring) + 1)
    d.finish()
    d.extrude(sk, "belt", 0.5, "symmetric")


def alternator(d):
    ay, az = ALTERNATOR
    yz = (ay, az)

    def turned(name, profile):
        d.revolve(name, p3(0.0, yz), (1, 0, 0), (0, 0, 1), profile)

    turned("alternator_pulley", [(-13.0, 0.0), (-13.0, ALT_PULLEY_R), (-13.12, ALT_PULLEY_R),
                                 (-13.32, ALT_PULLEY_R - 0.4), (-13.42, ALT_PULLEY_R - 0.4),
                                 (-13.62, ALT_PULLEY_R), (-13.72, ALT_PULLEY_R), (-13.72, 0.0)])
    turned("alternator_nut", [(-13.72, 0.0), (-13.72, 0.42), (-14.05, 0.42), (-14.05, 0.0)])
    # The cooling fan behind the pulley: a disc with vanes round its edge.
    # The cooling fan behind the pulley: a thin disc, and vanes standing off it, swept
    # back from the radial.
    d.cylinder("alternator_fan", (-12.62, ay, az), (-1, 0, 0), 4.7, 0.07)
    sk = d.sketch("YZ", "Alternator fan vanes", offset=-12.69)
    for i in range(10):
        t0 = 2 * math.pi * i / 10
        pts = []
        for r, dt, w in ((1.15, 0.0, -0.08), (2.3, 0.42, -0.08), (2.3, 0.42, 0.08), (1.15, 0.0, 0.08)):
            t = t0 + dt
            pts.append((ay + r * math.cos(t) - w * math.sin(t), az + r * math.sin(t) + w * math.cos(t)))
        d.poly(ccw(pts))
    d.finish()
    d.extrude(sk, "alternator_fan_vanes", 0.3, "negative")
    turned("alternator", [(-12.62, 0.0), (-12.62, 2.75), (-12.35, 3.15), (-11.2, 3.15),
                          (-11.2, 0.0)])
    turned("alternator_stator", [(-11.2, 0.0), (-11.2, 3.35), (-10.6, 3.35), (-10.6, 0.0)])
    turned("alternator_back", [(-10.6, 0.0), (-10.6, 3.1), (-10.1, 3.0), (-9.85, 2.55),
                               (-9.85, 1.0), (-9.6, 1.0), (-9.6, 0.0)])
    # Dark vent slots round the front housing's face.
    sk = d.sketch("YZ", "Alternator vents", offset=-12.64)
    for k in range(8):
        t = 2 * math.pi * (k + 0.5) / 8
        c, s_ = math.cos(t), math.sin(t)
        pts = []
        for r, w in ((1.2, -0.28), (2.45, -0.4), (2.45, 0.4), (1.2, 0.28)):
            pts.append((ay + r * c - w * s_, az + r * s_ + w * c))
        d.poly(ccw(pts))
    d.finish()
    d.extrude(sk, "alternator_vents", 0.04, "negative")
    # Mounting ears: the pivot ear down toward the pump, the adjusting ear up and in.
    for name, ang, x0, x1 in (("alternator_ear_pivot", -125, -12.5, -11.7),
                              ("alternator_ear_adjust", 160, -12.3, -11.9)):
        t = math.radians(ang)
        c, s_ = math.cos(t), math.sin(t)
        sk = d.sketch("YZ", name, offset=x1)
        d.c += outline_commands(*hull_outline([((ay + 2.2 * c, az + 2.2 * s_), 0.75),
                                                ((ay + 3.65 * c, az + 3.65 * s_), 0.48)]))
        d.finish()
        d.extrude(sk, name, x1 - x0, "negative")
    # The bracket from the pivot ear down to the pump's right-hand bolt.
    t = math.radians(-125)
    ear = (ay + 3.65 * math.cos(t), az + 3.65 * math.sin(t))
    sk = d.sketch("YZ", "Alternator bracket", offset=BLOCK_FRONT - 1.5)
    d.c += outline_commands(*hull_outline([(ear, 0.6), ((4.2, 4.6), 0.8)]))
    d.finish()
    d.extrude(sk, "accessory_bracket_right", 0.3, "negative")


# The starter, flywheel, oil pan and oil filter.

def bottom(d):
    fx, ft, fr = FLYWHEEL
    d.cylinder("flywheel", (fx, 0, 0), (1, 0, 0), 2 * fr, ft)
    # The crank's flange out of the block's back, the flywheel bolted to it.
    d.cylinder("flywheel_crank_flange", (BLOCK_BACK, 0, 0), (1, 0, 0), 3.6, fx - BLOCK_BACK)
    d.cylinder("flywheel_hub", (fx + ft, 0, 0), (1, 0, 0), 3.2, 0.3)

    # The starter: the motor, its end cap, the nose back to the flywheel bolted up to the
    # block, the solenoid above the motor on the outside with its posts forward.
    sy, sz = STARTER
    d.cylinder("starter", (1.9, sy, sz), (1, 0, 0), 4.0, 5.7)
    d.cylinder("starter_end", (1.6, sy, sz), (1, 0, 0), 3.4, 0.3)
    d.cone("starter_nose", (7.6, sy, sz), (1, 0, 0), 1.7, 1.3, 4.2)
    d.box("starter_nose_mount", (9.2, sy - 1.6, sz + 0.9), (10.9, sy + 1.6, 0.0))
    sol = (sy + 1.64, sz + 2.64)
    d.cylinder("starter_solenoid", (4.4, sol[0], sol[1]), (1, 0, 0), 2.3, 4.55)
    for k, dy in enumerate((-0.5, 0.5)):
        d.cylinder(f"starter_solenoid_post_{k}", (4.4, sol[0] + dy, sol[1]), (-1, 0, 0), 0.45, 0.55)

    # Oil pan: the flange on the rail, notched at the back on the left for the filter;
    # the tray, the sump at the back, the drain plug.
    fx0, fx1 = BLOCK_FRONT + 0.05, BLOCK_BACK - 0.05
    sk = d.sketch("XY", "Pan flange", offset=0.0)
    d.poly(ccw([(fx0, -RAIL_Y), (6.6, -RAIL_Y), (6.6, -4.5), (fx1, -4.5), (fx1, RAIL_Y),
                (fx0, RAIL_Y)]))
    d.finish()
    d.extrude(sk, "oil_pan", 0.16, "negative")
    tx, ty, th = PAN_TRAY
    sk = d.sketch("XY", "Pan tray", offset=-0.16)
    d.rounded((-tx, -ty), (tx, ty), 1.1)
    d.finish()
    d.extrude(sk, "oil_pan_tray", th, "negative", taper="-4 deg")
    x0, x1, y0, y1, zb = SUMP
    top = -0.16 - th + 0.05
    sk = d.sketch("XY", "Sump", offset=top)
    d.rounded((x0, y0), (x1, y1), 1.0)
    d.finish()
    d.extrude(sk, "oil_pan_sump_detail", top - zb, "negative", taper="-3 deg")
    d.cylinder("oil_pan_drain", ((x0 + x1) / 2 + 2.0, (y0 + y1) / 2, zb), (0, 0, -1), 0.9, 0.3)

    # The oil filter hanging straight down from its boss on the block, at the back on
    # the left, beside the pan.
    ox, oy = OIL_FILTER
    sk = d.sketch("XY", "Filter boss", offset=0.85)
    d.rounded((ox - 1.6, oy - 1.6), (ox + 1.6, -WALL_FOOT[0] + 0.15), 0.6)
    d.finish()
    d.extrude(sk, "engine_block_filter_boss", 1.3)
    d.cylinder("oil_filter_adapter", (ox, oy, 0.9), (0, 0, -1), 2.9, 0.45)
    d.revolve("oil_filter", (ox, oy, 0.0), (0, 0, 1), (1, 0, 0),
              [(0.45, 0.0), (0.45, 1.68), (0.3, 1.83), (-4.45, 1.83), (-4.68, 1.62),
               (-4.75, 0.0)])


# Run inside Blender: as make_flathead.py's, weld, dissolve the coplanar triangles and
# collapse each body to a triangle budget by its size. SolidCraft meshes a circle with
# over a hundred segments; round bodies (a factor given as "r0.35") are thinned by that
# ratio instead, which leaves forty-odd evenly round them, where a budget by size would
# leave them jagged.
BLENDER_REDUCE = r"""
import bmesh, bpy, json, math, sys
src, dst, factors = sys.argv[sys.argv.index("--") + 1:]
factors = json.loads(factors)
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob)
bpy.ops.wm.obj_import(filepath=src)
for ob in list(bpy.context.scene.objects):
    if ob.type != "MESH":
        continue
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-3)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=bm.verts, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    tris = len(bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    factor = next((f for p, f in factors if ob.name.startswith(p)), 1)
    if isinstance(factor, str):
        mod = ob.modifiers.new("reduce", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = float(factor[1:])
        continue
    if factor == 0:
        continue
    size = sorted(ob.dimensions)[1] / 25.4
    budget = 6 * min(96, max(16, int(8 * size))) * factor
    if tris > budget * 1.5:
        mod = ob.modifiers.new("reduce", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = budget * 1.5 / tris
bpy.ops.wm.obj_export(filepath=dst, apply_modifiers=True, export_normals=False, export_uv=False,
                      export_materials=False, export_triangulated_mesh=True)
"""
# Budget multipliers by body name prefix, first match wins; 0 leaves the body whole.
ROUND = "r0.35"
REDUCE_FACTORS = [
    ("air_cleaner_element", 0), ("alternator_fan_vanes", 0),
    ("air_cleaner", ROUND), ("crank_pulley", ROUND), ("upper_pulley", ROUND),
    ("alternator", ROUND), ("harmonic_balancer", ROUND), ("crank_bolt", ROUND),
    ("distributor_clamp", 1), ("distributor", ROUND), ("spark_plug", ROUND),
    ("ignition_coil", ROUND), ("oil_filler", ROUND), ("oil_filter", ROUND),
    ("thermostat_bolts", 0), ("thermostat_housing", 0), ("thermostat", ROUND),
    ("starter_nose_mount", 1), ("starter", ROUND), ("flywheel", ROUND), ("fan_spacer", ROUND),
    ("fan_hub", ROUND), ("water_pump_snout", ROUND), ("water_pump_hub", ROUND),
    ("water_pump_inlet", ROUND), ("water_pump_heater", ROUND), ("carburetor_ring", ROUND),
    ("carb_throat", ROUND), ("carburetor_bowl_screw", ROUND), ("exhaust_collector", ROUND),
    ("exhaust_runner", "r0.08"), ("intake_manifold_runner", "r0.12"),
    ("intake_manifold_crossover", "r0.2"),
    ("intake_manifold_heat", "r0.2"), ("intake_manifold_bolt_bosses", ROUND),
    ("intake_manifold_pad_bosses", ROUND), ("intake_manifold_pad", 0), ("intake_manifold_choke", 0),
    ("intake_manifold_plenum", 0), ("intake_manifold_thermostat_seat", 0),
    ("intake_manifold_distributor", ROUND), ("fan_blades", 2), ("belt", 3),
]


def reduce_obj(src, dst, blender):
    r = subprocess.run([blender, "-b", "--factory-startup", "--python-expr", BLENDER_REDUCE,
                        "--", src, dst, json.dumps(REDUCE_FACTORS)], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(dst):
        sys.exit(f"blender: {r.stderr.strip() or r.stdout.strip()}")


def finish_for(name):
    for prefix, mat in FINISHES:
        if name.startswith(prefix):
            return mat
    return PAINT


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--headers", default="long", choices=sorted(COLLECTOR),
                    help="long tubes (default) or shorties")
    ap.add_argument("--sc", help="design file (default resources/engines/STEM.sc)")
    ap.add_argument("--glb", help="mesh (default assets/parts/STEM.glb)")
    ap.add_argument("--solidcraft", default="solidcraft-cli",
                    help="solidcraft-cli, or the SolidCraft AppImage")
    ap.add_argument("--blender", default="blender", help="Blender, which thins the mesh")
    args = ap.parse_args()
    stem = STEM if args.headers == "long" else f"{STEM}-{args.headers}"
    sc = os.path.abspath(args.sc or os.path.join(ROOT, "resources", "engines", stem + ".sc"))
    glb = os.path.abspath(args.glb or os.path.join(ROOT, "assets", "parts", stem + ".glb"))
    tool = shutil.which(args.solidcraft) or args.solidcraft
    if not os.path.exists(tool):
        sys.exit(f"no SolidCraft command line at {args.solidcraft}")
    blender = shutil.which(args.blender) or args.blender
    if not os.path.exists(blender):
        sys.exit(f"no Blender at {args.blender}")

    d = SBC()
    block(d)
    heads(d)
    valve_covers(d)
    intake(d)
    air_cleaner(d, carburetor(d))
    distributor(d)
    coil(d)
    oil_filler(d)
    headers(d, args.headers)
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

    # Design mm -> engine units (0.22 m), crank down to the models' Z. A sketch of several
    # separate shapes extrudes into a body each, "name (2)" and on: put them back in one.
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
