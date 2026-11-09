#!/usr/bin/env python3
"""Build a small-block Chevy V8 in SolidCraft and export it as a game GLB.

    python3 tools/make_sbc.py

The engine is a 350 small-block as it came in the sixties and seventies, with the user's
3ds Max model (Smallblockchevy.max, exported as Smallblockchevy.3DS) as the reference for
the parts it does well: the block, the heads, the valve covers, the oil pan and the
intake. The rest is drawn from real ones. Dimensions are the real engine's where they are
known (4.400 bore spacing, 9.025 deck height, 90 degree V, the left bank ahead of the
right); the rest are close enough to look right. It has:

  block         one outline across the engine, extruded front to back: the 45 degree
                bank walls down to the crankcase and the pan rail at the crank's height,
                the decks, and the valley under the intake; three freeze plugs in each
                bank wall, the side mount pads, the bellhousing flange at the back
  heads         one casting each, square to its deck: the exhaust face outward, the
                intake face leaning in at 30 degrees from upright, four spark plugs below
                the exhaust ports
  valve covers  stamped, as on the reference: a flange with four bolt tabs, a drafted
                body, a raised panel on top; the oil filler cap on the left one and the
                PCV valve on the right
  intake        the cast-iron dual plane: a valley cover between the heads' flanges, the
                water crossover across the front with the thermostat housing on it, the
                plenum under a square-flange four-barrel pad, eight runners on two
                levels, the distributor boss at the back
  carburetor    a square-flange four-barrel: throttle body, main body, fuel bowls front
                and back, and the 5 1/8 air cleaner ring on top
  air cleaner   14 inches round: the pan, a pleated paper element and a chrome lid with
                a rolled edge and a wing nut
  distributor   points type: the housing, the vacuum advance on its arm, and the cap
                with eight towers round the coil tower
  headers       long tubes (or shorties): a flange on each head, four 1 5/8 primaries
                out of the ports, one bend each, into a merge cone and a 3 inch collector
  front         stamped timing cover, the long water pump with its lower hose inlet, the
                balancer and a two-groove crank pulley, a two-groove pump pulley, the
                fan on a spacer, a Delco alternator high on the right on its bracket, and
                the belt round crank, pump and alternator
  starter       under the right side at the back: the motor, the solenoid on top, the
                nose into the flywheel
  bottom        oil pan with the sump at the back (notched for the starter), the oil
                filter at the back on the left, and the flywheel

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

# The block.
BLOCK_FRONT = -10.6
BLOCK_BACK = 10.6
DECK = 9.025            # crank to deck along the bank's axis
DECK_OUT = 3.3          # bank axis out to the deck's outer edge
DECK_IN = 3.4           # bank axis in to the deck's inner edge
VALLEY_Z = 8.6          # valley floor, under the intake
SKIRT_Y = 5.5           # crankcase sides
RAIL_Y = 5.95           # pan rail lip
RAIL_T = 0.4            # pan rail's thickness, up from the crank's height
BANK_SHIFT = 0.45       # the right bank sits this far back of the middle, the left forward
BORE_X = [-6.6, -2.2, 2.2, 6.6]
# The ports along each bank, before the shift: exhaust valves at the ends of each pair
# (E I I E E I I E), intakes in between.
EXHAUST_PORT_X = [-7.5, -1.3, 1.3, 7.5]
INTAKE_PORT_X = [-5.7, -3.1, 3.1, 5.7]
FREEZE_PLUG_X = [-4.4, 0.0, 4.4]

# The heads, in each deck's own frame: a from the deck's outer edge in, h up off the deck.
HEAD_LEN = 20.2
HEAD_DECK = (-0.25, 6.9)
HEAD_TOP = 4.15
INTAKE_LEAN = math.radians(30)  # the intake face from upright, its top further out
PORT_H = 2.3            # exhaust ports up the exhaust face
PLUG_H = 0.95           # spark plugs up the exhaust face

# Valve covers on the head's top: (a0, a1) across, half length, and heights.
COVER_A = (0.15, 6.05)
COVER_HALF = 9.7
COVER_H = 2.6
COVER_TABS = [(-5.2, 0.0), (5.2, 0.0), (-5.2, 6.2), (5.2, 6.2)]  # (x, a) of the bolt tabs

# Intake.
INTAKE_HALF = 8.2       # the flanges' half length
PLENUM = (3.0, 2.9)     # half length, half width
PAD_Z = 14.7            # carb pad's underside
PAD = (2.85, 2.7, 0.35)
RUNNER_Z = (13.4, 11.8)  # upper and lower plane runners where they leave the plenum
DIST = (9.6, 0.0)       # distributor's axis (x, y)
THERMOSTAT_X = -8.9

# Front of the engine: the belt's plane and what it goes round, (y, z).
COVER_FACE = -11.4
BELT_X = -13.35
CRANK_PULLEY_R = 3.2
PUMP = (0.0, 7.2)
PUMP_PULLEY_R = 3.3
ALTERNATOR = (8.6, 10.6)
ALT_PULLEY_R = 1.45
FAN_X = -16.75
FAN_R = 9.0
FAN_PITCH = math.radians(28)

# Starter, under the right side at the back: its axis (y, z).
STARTER = (5.9, -4.9)
FLYWHEEL = (10.95, 0.5, 7.0)    # front face, thickness, radius

# Oil pan: the tray under the whole rail, the sump at the back.
PAN_TRAY = (10.2, 5.4, 1.8)
SUMP = (0.8, 9.9, -4.6, 3.4, -7.3)  # x0, x1, y0, y1, bottom

# Headers: the collectors' front ends (x before the bank's shift, |y|, z) and their axis.
COLLECTOR = {"long": ((9.0, 9.9, -6.8), (0.72, 0.0, -0.69)),
             "shorty": ((1.5, 10.6, -2.6), (0.8, 0.0, -0.6))}
PRIMARY_D = 1.625

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
    ("valve_bolt", STEEL), ("valve_cover_filler", BLACK), ("valve_cover_pcv", BLACK),
    ("spark_plug_base", STEEL), ("spark_plug_tip", STEEL), ("spark_plug", PORCELAIN),
    ("intake_manifold_bolts", STEEL), ("intake_manifold", CAST_IRON), ("thermostat", CAST_IRON),
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
    return x + s * BANK_SHIFT


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


def offset_poly(pts, d):
    """A closed outline moved d outward (counterclockwise outlines), corners mitred."""
    pts = [np.array(p, float) for p in pts]
    n = len(pts)
    out = []
    for i in range(n):
        a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
        n1 = unit([(b - a)[1], -(b - a)[0]])
        n2 = unit([(c - b)[1], -(c - b)[0]])
        m = unit(n1 + n2)
        out.append(tuple(b + m * d / max(m @ n1, 0.3)))
    return out


def ccw(pts):
    area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]))
    return pts if area > 0 else pts[::-1]


# The block.

def block_outline():
    """The block's outline across the engine (y, z), counterclockwise."""
    edge = deck_edge(1)
    inner = on_head(1, DECK_OUT + DECK_IN, 0.0)
    # The bank's outer wall runs down its axis from the deck's outer edge to the skirt;
    # the inner one down to the valley floor.
    skirt_z = edge[1] - (edge[0] - SKIRT_Y)
    valley_y = inner[0] - (inner[1] - VALLEY_Z)
    right = [(RAIL_Y, 0.0), (RAIL_Y, RAIL_T), (SKIRT_Y, RAIL_T), (SKIRT_Y, skirt_z),
             tuple(edge), tuple(inner), (valley_y, VALLEY_Z)]
    left = [(-y, z) for y, z in reversed(right)]
    return ccw(right + left)


def block(d):
    outline = block_outline()
    sk = d.sketch("YZ", "Block", offset=BLOCK_FRONT)
    d.poly(outline)
    d.finish()
    d.extrude(sk, "engine_block", BLOCK_BACK - BLOCK_FRONT)

    # The bellhousing flange across the back, wider than the block, down round the crank.
    flange = offset_poly(outline, 0.45)
    sk = d.sketch("YZ", "Bell flange", offset=BLOCK_BACK)
    d.poly(flange)
    d.finish()
    d.extrude(sk, "engine_block_bell_flange", 0.35)

    for s in (1, -1):
        u, _, inn = bank(s)
        # Freeze plugs in the outer bank wall, and the side mount's pad lower down.
        wall = deck_edge(s) - 2.6 * u
        sk, to2d = d.plane(p3(0.0, wall), (1, 0, 0), v3(-inn), f"Freeze plugs {s}")
        for x in FREEZE_PLUG_X:
            d.circle(to2d(p3(bank_x(s, x), wall)), 0.81)
        d.finish()
        d.extrude(sk, f"freeze_plug_{s}", 0.08)
        pad = deck_edge(s) - 4.4 * u
        sk, to2d = d.plane(p3(0.0, pad), (1, 0, 0), v3(-inn), f"Mount pad {s}")
        c = to2d(p3(-6.2, pad))
        d.rounded((c[0] - 1.6, c[1] - 0.7), (c[0] + 1.6, c[1] + 0.7), 0.35)
        d.finish()
        d.extrude(sk, f"engine_block_mount_{s}", 0.3)


# The heads.

def head_outline(s):
    # The intake face, from the deck's inner end, leans INTAKE_LEAN off upright: in the
    # head's frame it climbs mostly along h and a little inward.
    up = np.array([S45, S45])                       # upright in (a, h)
    out = np.array([-S45, S45])                     # level and outward in (a, h)
    face = math.cos(INTAKE_LEAN) * up + math.sin(INTAKE_LEAN) * out
    top_a = HEAD_DECK[1] + face[0] / face[1] * HEAD_TOP
    pts = [(HEAD_DECK[0], 0.0), (HEAD_DECK[1], 0.0), (top_a, HEAD_TOP),
           (HEAD_DECK[0] + 0.55, HEAD_TOP), (HEAD_DECK[0], HEAD_TOP - 0.55)]
    return [tuple(on_head(s, a, h)) for a, h in pts]


def intake_face(s):
    """Bottom and top of bank s's intake face, (y, z)."""
    o = head_outline(s)
    return np.array(o[1]), np.array(o[2])


def heads(d):
    for s in (1, -1):
        sk = d.sketch("YZ", f"Head {s}", offset=bank_x(s, -HEAD_LEN / 2))
        d.poly(ccw(head_outline(s)))
        d.finish()
        d.extrude(sk, f"cylinder_head_{s}", HEAD_LEN)

        # Spark plugs out of the exhaust face, below the ports, square to it.
        _, _, inn = bank(s)
        face = on_head(s, HEAD_DECK[0], PLUG_H)
        for part, size, start, length in (("spark_plug_base", 0.63, 0.0, 0.4),
                                          ("spark_plug", 0.5, 0.4, 1.25),
                                          ("spark_plug_tip", 0.22, 1.65, 0.35)):
            sk, to2d = d.plane(p3(0.0, face), (1, 0, 0), v3(-inn), f"{part} {s}")
            for x in BORE_X:
                c = to2d(p3(bank_x(s, x), face))
                if part == "spark_plug_base":
                    d.hexagon(c, size)
                else:
                    d.circle(c, size / 2)
            d.finish()
            d.extrude(sk, f"{part}_{s}", length, start_offset=inch(start))


def valve_covers(d):
    for s in (1, -1):
        u, _, _ = bank(s)
        top = on_head(s, 0.0, HEAD_TOP)

        def plane(lift, name):
            origin = p3(bank_x(s, 0.0), top) + lift * v3(u)
            sk, to2d = d.plane(origin, (1, 0, 0), v3(u), name)
            return sk, lambda x, a: to2d(origin + np.array([x, 0, 0]) + a * v3(bank(s)[2]))

        a0, a1 = COVER_A
        sk, at = plane(0.0, f"Cover flange {s}")
        d.rounded(at(-COVER_HALF, a0), at(COVER_HALF, a1), 0.7)
        for x, a in COVER_TABS:
            d.circle(at(x, a), 0.5)
        d.finish()
        d.extrude(sk, f"valve_cover_{s}", 0.16)

        sk, at = plane(0.16, f"Cover body {s}")
        d.rounded(at(-COVER_HALF + 0.15, a0 + 0.15), at(COVER_HALF - 0.15, a1 - 0.15), 0.6)
        d.finish()
        d.extrude(sk, f"valve_cover_body_{s}", COVER_H, taper="-4 deg")

        # The raised panel on top, as on the reference's covers.
        shrink = 0.15 + COVER_H * math.tan(math.radians(4)) + 0.45
        sk, at = plane(0.16 + COVER_H, f"Cover panel {s}")
        d.rounded(at(-COVER_HALF + shrink, a0 + shrink), at(COVER_HALF - shrink, a1 - shrink), 0.4)
        d.finish()
        d.extrude(sk, f"valve_cover_panel_{s}", 0.14)

        for i, (x, a) in enumerate(COVER_TABS):
            sk, at = plane(0.16, f"Cover bolt {s} {i}")
            d.hexagon(at(x, a), 0.44)
            d.finish()
            d.extrude(sk, f"valve_bolt_{s}_{i}", 0.3)

        # The oil filler's breather cap at the front of the left cover, the PCV valve's
        # grommet at the back of the right one.
        lift = 0.16 + COVER_H + 0.14
        if s == -1:
            sk, at = plane(lift, "Filler")
            d.circle(at(-6.3, 3.1), 1.3)
            d.finish()
            d.extrude(sk, "valve_cover_filler_cap", 1.1, taper="-6 deg")
        else:
            sk, at = plane(lift, "PCV")
            d.circle(at(6.6, 3.1), 0.55)
            d.finish()
            d.extrude(sk, "valve_cover_pcv", 0.9)


# The intake.

def intake(d):
    # The base: each head's flange against its intake face, 0.55 thick, and the valley
    # cover between them.
    pts = {}
    for s in (1, -1):
        f0, f1 = intake_face(s)
        along = unit(f1 - f0)
        n = np.array([-along[1], along[0]]) if s == 1 else np.array([along[1], -along[0]])
        inner_top = f1 + 0.55 * n
        k = (inner_top[1] - (VALLEY_Z + 0.85)) / along[1]
        pts[s] = (f0, f1, inner_top, inner_top - k * along, n, along)
    r, l = pts[1], pts[-1]
    base = [tuple(r[0]), tuple(r[1]), tuple(r[2]), tuple(r[3]), tuple(l[3]), tuple(l[2]),
            tuple(l[1]), tuple(l[0])]
    sk = d.sketch("YZ", "Intake", offset=-INTAKE_HALF)
    d.poly(ccw(base))
    d.finish()
    d.extrude(sk, "intake_manifold", 2 * INTAKE_HALF)

    # The water crossover across the front and the wall across the back, the full width
    # between the faces up to the crossover's top.
    def wedge(top_z):
        out = []
        for f0, f1, *_ in (r, l):
            t = (top_z - f0[1]) / (f1[1] - f0[1])
            out.append((tuple(f0), tuple(f0 + t * (f1 - f0))))
        (r0, rt), (l0, lt) = out
        return ccw([r0, rt, lt, l0])
    sk = d.sketch("YZ", "Crossover", offset=-INTAKE_HALF - 1.1)
    d.poly(wedge(12.2))
    d.finish()
    d.extrude(sk, "intake_manifold_crossover", 1.1)
    sk = d.sketch("YZ", "Back wall", offset=INTAKE_HALF)
    d.poly(wedge(10.6))
    d.finish()
    d.extrude(sk, "intake_manifold_back", 0.7)

    # Thermostat housing on the crossover, its outlet neck up and forward.
    d.cylinder("thermostat_housing", (THERMOSTAT_X, 0, 12.2), (0, 0, 1), 3.0, 0.7)
    neck = np.array([THERMOSTAT_X, 0.0, 12.75])
    dirn = unit([-0.7, 0.0, 0.72])
    d.cylinder("thermostat_neck", neck, dirn, 2.2, 1.4)
    d.cylinder("thermostat_hose_neck", neck + 1.4 * dirn, dirn, 1.55, 1.3)

    # The plenum under the pad, and the pad.
    hx, hy = PLENUM
    sk = d.sketch("XY", "Plenum", offset=VALLEY_Z + 0.85)
    d.rounded((-hx, -hy), (hx, hy), 0.9)
    d.finish()
    d.extrude(sk, "intake_manifold_plenum", PAD_Z - VALLEY_Z - 0.85, taper="-3 deg")
    px, py, pt = PAD
    sk = d.sketch("XY", "Carb pad", offset=PAD_Z)
    d.rounded((-px, -py), (px, py), 0.35)
    d.finish()
    d.extrude(sk, "intake_manifold_pad", pt)

    # Runners, from inside the plenum out to each port, the two planes taking alternate
    # cylinders on each bank.
    for s in (1, -1):
        f0, f1, _, _, n, along = pts[s]
        port = f0 + 0.55 * (f1 - f0) + 0.25 * n
        for i, x in enumerate(INTAKE_PORT_X):
            upper = (i in (0, 3)) == (s == 1)
            z = RUNNER_Z[0] if upper else RUNNER_Z[1]
            px_ = bank_x(s, x)
            x0 = px_ * 0.35
            start = np.array([x0, s * (hy - 0.9), z])
            sk0, to0 = d.plane(start, (1, 0, 0), (0, s, 0), f"Runner {s} {i} start")
            c = to0(start)
            d.rounded((c[0] - 0.6, c[1] - 0.85), (c[0] + 0.6, c[1] + 0.85), 0.4)
            d.finish()
            end = p3(px_, port)
            sk1, to1 = d.plane(end, (1, 0, 0), v3(-n), f"Runner {s} {i} end")
            c = to1(end)
            up = to1(end + v3(along))
            # The port's rectangle stands along the face.
            ax = np.array(up) - np.array(c)
            if abs(ax[1]) >= abs(ax[0]):
                d.rounded((c[0] - 0.62, c[1] - 0.95), (c[0] + 0.62, c[1] + 0.95), 0.4)
            else:
                d.rounded((c[0] - 0.95, c[1] - 0.62), (c[0] + 0.95, c[1] + 0.62), 0.4)
            d.finish()
            d.loft(f"intake_manifold_runner_{s}_{i}", [sk0, sk1])

        # Bolts through the flange's top, square to the face, between the runners.
        bolt = f0 + 0.86 * (f1 - f0) + 0.55 * n
        sk, to2d = d.plane(p3(0.0, bolt), (1, 0, 0), v3(n), f"Intake bolts {s}")
        for x in (-7.3, -4.4, 0.0, 4.4, 7.3):
            d.hexagon(to2d(p3(bank_x(s, x), bolt)), 0.5)
        d.finish()
        d.extrude(sk, f"intake_manifold_bolts_{s}", 0.3)

    # The distributor's boss at the back.
    d.cylinder("intake_manifold_distributor_boss", (DIST[0], DIST[1], VALLEY_Z + 0.4), (0, 0, 1),
               2.7, 11.2 - VALLEY_Z - 0.4)


# The carburetor and air cleaner.

def carburetor(d):
    z = PAD_Z + PAD[2]
    d.box("carburetor_base", (-2.8, -2.65, z), (2.8, 2.65, z + 0.75))
    z += 0.75
    d.box("carburetor", (-2.25, -2.5, z), (2.25, 2.5, z + 1.5))
    for end, x0, x1 in (("front", -4.0, -2.25), ("back", 2.25, 4.0)):
        sk = d.sketch("XY", f"Bowl {end}", offset=z - 0.15)
        d.rounded((x0, -2.35), (x1, 2.35), 0.45)
        d.finish()
        d.extrude(sk, f"carburetor_bowl_{end}", 2.55)
        sx = x0 if end == "front" else x1
        d.cylinder(f"carburetor_bowl_screw_{end}", (sx, 1.6, z + 1.9), (np.sign(sx), 0, 0), 0.4, 0.15)
    z += 1.5
    d.box("carburetor_air_horn", (-2.25, -2.5, z), (2.25, 2.5, z + 0.35))
    z += 0.35
    sk = d.sketch("XY", "Air cleaner ring", offset=z)
    d.circle((0, 0), 2.5625)
    d.circle((0, 0), 2.35)
    d.finish()
    d.extrude(sk, "carburetor_ring", 0.55)
    for x in (-0.85, 0.85):
        for y in (-0.85, 0.85):
            d.cylinder(f"carb_throat_{x}_{y}", (x, y, z), (0, 0, 1), 1.56 if x < 0 else 1.69, 0.04)
    return z + 0.55


def air_cleaner(d, zb):
    o = np.array([0.0, 0.0, zb])
    d.revolve("air_cleaner_base", o, (0, 0, 1), (1, 0, 0),
              [(0.0, 2.6), (0.0, 7.3), (0.6, 7.3), (0.6, 7.15), (0.12, 7.15), (0.12, 2.6)])
    # The pleated paper element, round a solid inner ring.
    n = 120
    pleats = []
    for i in range(2 * n):
        t = math.pi * i / n
        r = 7.0 if i % 2 == 0 else 6.78
        pleats.append((r * math.cos(t), r * math.sin(t)))
    sk = d.sketch("XY", "Element", offset=zb + 0.12)
    d.poly(pleats)
    d.circle((0, 0), 6.2)
    d.finish()
    d.extrude(sk, "air_cleaner_element", 3.0)
    zl = zb + 3.12
    d.revolve("air_cleaner_lid", o, (0, 0, 1), (1, 0, 0),
              [(3.12 - 0.5, 7.3), (3.12 + 0.05, 7.3), (3.12 + 0.35, 6.7), (3.12 + 0.78, 0.45),
               (3.12 + 0.64, 0.45), (3.12 + 0.22, 6.65), (3.12 - 0.05, 7.15), (3.12 - 0.5, 7.15)])
    d.cylinder("air_cleaner_stud", (0, 0, zl + 0.5), (0, 0, 1), 0.3, 1.2)
    d.cylinder("air_cleaner_wingnut", (0, 0, zl + 0.78), (0, 0, 1), 0.75, 0.5)
    sk = d.sketch("XZ", "Wing nut", offset=0.0)
    for side in (1, -1):
        d.poly([(side * 0.3, -(zl + 0.8)), (side * 1.25, -(zl + 1.05)), (side * 1.35, -(zl + 1.6)),
                (side * 0.95, -(zl + 1.65)), (side * 0.3, -(zl + 1.25))])
    d.finish()
    d.extrude(sk, "air_cleaner_wingnut_wings", 0.12, "symmetric")


def distributor(d):
    x, y = DIST
    o = np.array([x, y, 0.0])
    d.revolve("distributor_body", o, (0, 0, 1), (1, 0, 0),
              [(8.6, 0.0), (8.6, 0.72), (11.2, 0.72), (11.2, 1.25), (11.7, 1.6), (12.9, 1.6),
               (12.9, 0.0)])
    # Vacuum advance off the housing's side, toward the front on the right.
    arm = unit([-0.55, 0.84, 0.0])
    d.cylinder("distributor_vacuum_arm", o + np.array([0, 0, 12.25]) + 1.3 * arm, arm, 0.75, 1.2)
    d.cylinder("distributor_vacuum", o + np.array([0, 0, 12.25]) + 2.5 * arm, arm, 2.1, 1.0)
    d.revolve("distributor_cap", o, (0, 0, 1), (1, 0, 0),
              [(12.9, 0.0), (12.9, 2.15), (13.9, 2.15), (14.3, 1.95), (14.95, 1.2), (14.95, 0.0)])
    # Eight towers on the shoulder, leaning out, and the coil tower in the middle.
    for k in range(8):
        t = 2 * math.pi * (k + 0.5) / 8
        radial = np.array([math.cos(t), math.sin(t), 0.0])
        lean = unit(np.array([0, 0, 1.0]) + 0.45 * radial)
        base = o + np.array([0, 0, 14.35]) + 1.55 * radial
        d.cylinder(f"distributor_cap_tower_{k}", base, lean, 0.62, 0.85)
    d.cylinder("distributor_cap_coil_tower", o + np.array([0, 0, 14.9]), (0, 0, 1), 0.72, 0.85)
    # Hold-down clamp at the base.
    d.box("distributor_clamp", (x - 2.2, -0.35, 11.2), (x - 0.6, 0.35, 11.45))


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
        _, _, inn = bank(s)
        n = v3(-inn)                       # out of the exhaust face
        port_yz = on_head(s, HEAD_DECK[0], PORT_H)
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
            p0, target = ports[k_port] - 0.375 * n, mouths[k_mouth]
            e1, e2, (a0, a1, c, q, t) = tube_path(p0, n, target)
            name = f"exhaust_runner_{s}_{k_port}"
            sk, _ = d.plane(p0, e1, np.cross(e1, e2), f"{name} path")
            d.c.append(cmd("sketch.line", infer=False, points=[skp(*a0), skp(*a1)]))
            d.c.append(cmd("sketch.arc.center_point", center=skp(*c), start="l1.end", end=skp(*q)))
            d.c.append(cmd("sketch.line", infer=False, points=["a1.end", skp(*t)]))
            d.finish()
            d.body(name, "solid.pipe", path_sketch=sk, path=["l1", "a1", "l2"],
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
    d.cylinder("water_pump_inlet", inlet, dirn, 1.75, 3.2)
    d.cylinder("water_pump_heater", (snout0 - 0.4, -1.6, 8.6), (-1, 0, 0), 0.8, 1.4)

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
    d.cylinder("flywheel_hub", (fx + ft, 0, 0), (1, 0, 0), 3.2, 0.3)

    sy, sz = STARTER
    d.cylinder("starter", (2.6, sy, sz), (1, 0, 0), 4.4, 5.6)
    d.cylinder("starter_end", (2.3, sy, sz), (1, 0, 0), 3.4, 0.3)
    d.cone("starter_nose", (8.2, sy, sz), (1, 0, 0), 2.0, 1.55, 2.6)
    d.box("starter_nose_mount", (8.4, sy - 1.3, sz + 1.2), (10.2, sy + 0.9, 0.0))
    sol = (sy + 1.25, sz + 2.35)
    d.cylinder("starter_solenoid", (3.3, sol[0], sol[1]), (1, 0, 0), 2.3, 4.5)
    for k, dy in enumerate((-0.5, 0.5)):
        d.cylinder(f"starter_solenoid_post_{k}", (3.3, sol[0] + dy, sol[1]), (-1, 0, 0), 0.45, 0.55)

    # Oil pan: the flange on the rail, the tray, the sump at the back with a notch for
    # the starter, the drain plug.
    sk = d.sketch("XY", "Pan flange", offset=0.0)
    d.rounded((BLOCK_FRONT + 0.05, -RAIL_Y), (BLOCK_BACK - 0.05, RAIL_Y), 0.8)
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

    # Oil filter on its adapter at the back of the block on the left, pointing down and out.
    base = np.array([7.6, -6.5, 0.9])
    dirn = unit([0.0, -0.62, -0.78])
    d.cylinder("oil_filter_adapter", base, dirn, 2.6, 0.6)
    d.cylinder("oil_filter", base + 0.6 * dirn, dirn, 3.7, 4.9)


# Run inside Blender: as make_flathead.py's, weld, dissolve the coplanar triangles and
# collapse each body to a triangle budget by its size, but a body turned about its axis
# (pulleys, the air cleaner's lid) keeps a budget per ring of its outline, so it stays
# round, and the pleated element is left whole.
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
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=bm.verts, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    tris = len(bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    factor = next((f for p, f in factors if ob.name.startswith(p)), 1)
    if factor == 0:
        continue
    size = sorted(ob.dimensions)[1] / 25.4
    budget = 4 * min(36, max(10, int(5 * size))) * factor
    if tris > budget * 1.5:
        mod = ob.modifiers.new("reduce", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = budget * 1.5 / tris
bpy.ops.wm.obj_export(filepath=dst, apply_modifiers=True, export_normals=False, export_uv=False,
                      export_materials=False, export_triangulated_mesh=True)
"""
# Budget multipliers by body name prefix, first match wins; 0 leaves the body whole.
REDUCE_FACTORS = [
    ("air_cleaner_element", 0), ("air_cleaner_lid", 5), ("air_cleaner_base", 3),
    ("crank_pulley", 5), ("upper_pulley", 5), ("alternator_pulley", 4), ("harmonic_balancer", 2),
    ("alternator_fan_vanes", 0), ("alternator", 2), ("distributor_cap", 3), ("distributor_body", 3),
    ("fan_blades", 3), ("exhaust_runner", 2), ("carburetor_ring", 2),
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
