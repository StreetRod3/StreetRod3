#!/usr/bin/env python3
"""Build a Ford flathead V8 in SolidCraft and export it as a game GLB.

    python3 tools/make_flathead.py

The engine is the 1942-48 59A, 239 cubic inches, as in the user's photos of one: a 90
degree V8 with its valves in the block, so the heads are flat castings on decks sloping
at 45 degrees, and the intake manifold lies in the valley between them, covering the
valve chamber. The bell housing is cast with the block. It has:

  block         one outline across the engine, extruded front to back: the crankcase,
                the two banks, the valley floor under the intake; the bell housing behind
                it with the starter's boss
  heads         one casting each, a rounded oblong about 2 1/2 times as long as it is wide
                on a thin flange, its sides drafted in; 24 stud nuts and four spark plugs
                laid out as on the heads' castings, the water outlet's three-bolt flange
                on a pedestal on the front end facing forward, and the plug wires' conduit along
                the inner edge
  intake        the stock single-carburetor manifold: a plate down the valley, a spine,
                a riser under a Ford two-barrel carburetor, the generator's stand at the
                front and the oil filler behind it
  exhaust       a slim cast log on each side under the head's outer edge, a lobe over
                each of its three ports (the middle two cylinders share one), turning down
                at the front to the pipe's flange
  oil pan       shallow, with the sump at the back
  front         the timing cover, the distributor lying forward off the cam's nose, a water
                pump low on each side, the generator on its stand with the fan on its
                pulley, and one belt round the crank, both pumps and the generator

Every part is a body of its own (SolidCraft's kernel takes minutes to join bodies), drawn
from numbers in this script rather than design parameters, so to change the engine change
the numbers here and run it again.

Writes resources/engines/engine-flathead-239.sc, the SolidCraft design, and
assets/parts/engine-flathead-239.glb. Both are LFS files (.gitattributes). Needs
SolidCraft's command line, as tools/make_wheels.py does (--solidcraft).

The design is in inches with the crank on the X axis: +X toward the back of the car, +Y
to its right, +Z up, the block's middle on X = 0.

The GLB is in the frame of the other engine models (engine-v8-*.glb, engine_assembly.gd):
engine units of 0.22 m (the assembly's ENGINE_SCALE), +X back, +Y right, +Z up (the
assembly stands it up), the crank at Z -0.36. Node names follow those models where there
is a match (engine_block, cylinder_head_1, intake_manifold, carburetor, distributor_body,
oil_pan, exhaust_collector_-1...), +1 the right bank and -1 the left. One mesh per body,
each in its finish. The game does not use it yet: engine_assembly.gd places heads,
intakes and plug wires for the small-block Chevy.
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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEM = "engine-flathead-239"
MM = 25.4
S45 = math.sqrt(0.5)

# The block.
BLOCK_LEN = 22.625      # 22 5/8, the block less its bell housing
DECK = 10.45            # crank to deck along the bank's axis (an 8BA measured 10.455)
DECK_OUT = 2.6          # bank axis out to the deck's outer edge
DECK_IN = 6.0           # bank axis in to the deck's inner edge, past the valves
VALLEY_Z = 10.6         # valley floor, under the intake
SKIRT_Y = 6.3           # crankcase sides
RAIL_Y = 6.9            # pan rail lip
RAIL_Z = -3.5           # pan rail, bottom of the block
BANK_SHIFT = 0.5        # the right bank sits this far forward of the middle, the left back
BORE_X = [-6.375, -2.125, 2.125, 6.375]  # cylinders along each bank, before the shift

# The heads, in each deck's own frame: a from the outer edge in, h up off the deck, x
# along the head from its middle.
HEAD_LEN = 22.6
HEAD_A = (-0.3, 8.6)    # 8.9 across, as the heads' outline is about 2 1/2 times as long
# Flange, then the body in from it and drafted in: (inset round the flange's outline,
# base height, thickness, draft, corner radius).
HEAD_STEPS = [(0.0, 0.0, 0.3, None, 1.8), (0.25, 0.3, 1.6, "-8 deg", 1.6)]
HEAD_TOP = 1.9
# The 24 studs and the four plugs as a head (Offenhauser's, whose studs follow the block)
# lays them out: rows across the head by distance in from its inner edge, x along it.
STUD_ROWS = [(1.35, [-8.3, -5.6, -2.75, 2.75, 5.6, 8.3]),
             (2.55, [-10.4, 10.4]), (2.85, [0.0]),
             (4.25, [-5.6, 5.6]),
             (5.45, [-10.25, 10.25]), (5.65, [0.0]),
             (6.9, [-5.6, 5.6]),
             (8.05, [-9.55, -6.9, -4.3, -1.55, 1.55, 4.3, 6.9, 9.55])]
PLUG_IN = 3.15
PLUG_X = [-8.3, -2.8, 2.8, 8.3]
NUT_R = 0.36
# Water outlet on the front end of each head, facing forward to the radiator: a rounded
# three-cornered pedestal standing out of the end, one corner pointing up off the head,
# its corners this far from its middle with this radius; the flange on its face carries
# the water port and a bolt hole in each corner.
OUTLET = (4.6, 1.3)     # middle of the face (a, h)
OUTLET_FORWARD = 0.4    # face this far ahead of the head's end
OUTLET_DEPTH = 0.9      # pedestal from the face back into the head
OUTLET_CORNER = 1.35
OUTLET_CORNER_R = 0.5
OUTLET_PORT_R = 0.75
OUTLET_FLANGE = 0.25
CONDUIT_A = 8.0         # plug wire conduit along the inner edge

# The front: the timing cover's face, and the belt's plane.
COVER_BACK = -11.5
COVER_FACE = -12.5
BELT_X = -13.6
CAM = (0.0, 5.2)
DISTRIBUTOR = (1.8, 5.2)
PUMP = (5.6, 2.4)
GENERATOR = (0.0, 16.0)
GENERATOR_R = 2.4
GENERATOR_BACK = -7.0
FAN_X = -15.0
FAN_R = 8.2

# The bell housing, round the crank behind the block.
BELL_FRONT = 11.0
BELL_BACK = 15.3
BELL_R = (7.0, 8.4)

PAINT = {"name": "paint", "pbrMetallicRoughness": {
    "baseColorFactor": [0.41, 0.44, 0.46, 1], "metallicFactor": 0.5, "roughnessFactor": 0.65}}
BLACK = {"name": "black paint", "pbrMetallicRoughness": {
    "baseColorFactor": [0.03, 0.03, 0.03, 1], "metallicFactor": 0.2, "roughnessFactor": 0.45}}
STEEL = {"name": "steel", "pbrMetallicRoughness": {
    "baseColorFactor": [0.62, 0.62, 0.63, 1], "metallicFactor": 0.6, "roughnessFactor": 0.4}}
CAST_IRON = {"name": "cast iron", "pbrMetallicRoughness": {
    "baseColorFactor": [0.16, 0.14, 0.13, 1], "metallicFactor": 0.4, "roughnessFactor": 0.8}}
ZINC = {"name": "zinc", "pbrMetallicRoughness": {
    "baseColorFactor": [0.66, 0.55, 0.26, 1], "metallicFactor": 0.6, "roughnessFactor": 0.35}}
PORCELAIN = {"name": "porcelain", "pbrMetallicRoughness": {
    "baseColorFactor": [0.85, 0.85, 0.82, 1], "metallicFactor": 0.0, "roughnessFactor": 0.25}}
CAST_ALUMINUM = {"name": "cast aluminum", "pbrMetallicRoughness": {
    "baseColorFactor": [0.58, 0.58, 0.56, 1], "metallicFactor": 0.6, "roughnessFactor": 0.6}}
SATIN_ALUMINUM = {"name": "satin aluminum", "pbrMetallicRoughness": {
    "baseColorFactor": [0.78, 0.78, 0.76, 1], "metallicFactor": 0.8, "roughnessFactor": 0.4}}
RUBBER = {"name": "rubber", "pbrMetallicRoughness": {
    "baseColorFactor": [0.05, 0.05, 0.05, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}}
# Body name prefixes to finishes, first match wins; anything else is the block's paint.
FINISHES = [
    ("cylinder_head_nuts", STEEL), ("cylinder_head_studs", STEEL), ("cylinder_head", CAST_ALUMINUM),
    ("water_outlet_port", BLACK), ("water_outlet", CAST_ALUMINUM), ("plug_conduit", STEEL), ("spark_plug_base", STEEL), ("spark_plug_tip", STEEL),
    ("spark_plug", PORCELAIN), ("exhaust", CAST_IRON), ("carb_throat", BLACK),
    ("carburetor", ZINC), ("distributor_body", STEEL), ("distributor_cap", BLACK),
    ("generator", BLACK), ("fan_blades", BLACK),
    ("fan_hub", BLACK), ("pulley", BLACK), ("belt", RUBBER), ("intake_manifold_oil_filler_cap", BLACK),
]


def inch(v):
    return f"{v:.4f} in"


def skp(x, y):
    """A sketch point: bare sketch coordinates are millimeters whatever the document's units."""
    return [round(float(x) * MM, 4), round(float(y) * MM, 4)]


def pt3(p):
    return [inch(c) for c in p]


def bank(s):
    """Unit vectors of bank s (+1 right, -1 left) in (y, z): up its axis, out across its
    deck, and in across it toward the valley."""
    return np.array([s * S45, S45]), np.array([s * S45, -S45]), np.array([-s * S45, S45])


def deck_edges(s):
    u, out, inn = bank(s)
    return DECK * u + DECK_OUT * out, DECK * u + DECK_IN * inn


def on_head(s, a, h):
    """(y, z) of a point a in from bank s's deck's outer edge and h up off it."""
    u, _, inn = bank(s)
    return deck_edges(s)[0] + a * inn + h * u


def head_point(s, x, a, h):
    y, z = on_head(s, a, h)
    return np.array([x - s * BANK_SHIFT, y, z])


def u3(s):
    u = bank(s)[0]
    return [0.0, float(u[0]), float(u[1])]


class Design:
    def __init__(self):
        self.c = [cmd("document.units", units="in")]
        self.n = 0

    def sketch(self, plane, name=None, offset=None):
        self.n += 1
        name = name or f"Sketch {self.n}"
        p = {"plane": plane, "name": name}
        if offset is not None:
            p["offset"] = inch(offset)
        self.c.append(cmd("sketch.create", **p))
        return name

    def poly(self, pts):
        self.c.append(cmd("sketch.line", infer=False, closed=True,
                          points=[skp(x, y) for x, y in pts]))

    def finish(self):
        self.c.append(cmd("sketch.finish"))

    def extrude(self, sketch, body, distance, direction="positive", **kw):
        self.c.append(cmd("solid.extrude", sketch=sketch, distance=inch(distance),
                          direction=direction, operation="new", name=body, body_name=body, **kw))

    def cylinder(self, body, base, axis, dia, height):
        self.c.append(cmd("solid.cylinder", base=pt3(base), axis=[float(a) for a in axis],
                          diameter=inch(dia), height=inch(height), operation="new",
                          name=body, body_name=body))

    def box(self, body, lo, hi):
        lo, hi = np.array(lo, float), np.array(hi, float)
        size = hi - lo
        self.c.append(cmd("solid.box", corner=pt3(lo), length=inch(size[0]), width=inch(size[1]),
                          height=inch(size[2]), operation="new", name=body, body_name=body))

    def head_plane(self, s, h, name):
        """A sketch on bank s's head parallel to its deck, h up, its normal out of the head;
        sketch (x, y) = (-s * (x - head's middle), a)."""
        origin = head_point(s, 0.0, 0.0, h) * MM
        _, _, inn = bank(s)
        self.n += 1
        self.c.append(cmd("sketch.create", name=name, plane={
            "origin": [round(float(v), 4) for v in origin], "x_dir": [-float(s), 0.0, 0.0],
            "y_dir": [0.0, float(inn[0]), float(inn[1])]}))
        return name


def hull_outline(circles):
    """The outline round circles [(center, r)] in counterclockwise order, every one on the
    outline: (lines [(p, q)], arcs [(center, start, end)] counterclockwise)."""
    n = len(circles)
    touch = []
    for i in range(n):
        (ci, ri), (cj, rj) = circles[i], circles[(i + 1) % n]
        ci, cj = np.array(ci, float), np.array(cj, float)
        d = np.linalg.norm(cj - ci)
        e = (cj - ci) / d
        right = np.array([e[1], -e[0]])
        k = (ri - rj) / d
        nrm = e * k + right * math.sqrt(1 - k * k)
        touch.append((ci + ri * nrm, cj + rj * nrm))
    lines, arcs = [], []
    for i in range(n):
        lines.append(touch[i])
        c = np.array(circles[(i + 1) % n][0], float)
        start, end = touch[i][1], touch[(i + 1) % n][0]
        a0 = math.atan2(*(start - c)[::-1])
        a1 = math.atan2(*(end - c)[::-1])
        sweep = (a1 - a0) % (2 * math.pi)
        if sweep > math.pi * 1.5:
            sys.exit(f"circle {(i + 1) % n} is not on the outline (sweep {math.degrees(sweep):.0f})")
        arcs.append((c, start, end))
    return lines, arcs


def outline_commands(lines, arcs, first=1):
    """Sketch commands for an outline, its lines and arcs numbered from `first` (ids run
    on from the sketch's earlier curves)."""
    out = []
    n = len(lines)
    for i, ((p, q), (c, _, b)) in enumerate(zip(lines, arcs)):
        # Each piece starts on the one before it, and the last arc ends on the first line,
        # so the loop is closed exactly.
        k = first + i
        start = skp(*p) if i == 0 else f"a{k - 1}.end"
        out.append(cmd("sketch.line", infer=False, points=[start, skp(*q)]))
        end = f"l{first}.start" if i == n - 1 else skp(*b)
        out.append(cmd("sketch.arc.center_point", center=skp(*c), start=f"l{k}.end", end=end))
    return out


def block(d):
    out_r, in_r = deck_edges(1)
    wall_z = out_r[1] - (out_r[0] - SKIRT_Y)  # outer bank wall meets the crankcase side
    right = [(RAIL_Y, RAIL_Z), (RAIL_Y, RAIL_Z + 0.6), (SKIRT_Y, RAIL_Z + 0.6), (SKIRT_Y, wall_z),
             tuple(out_r), tuple(in_r), (valley_y(), VALLEY_Z)]
    left = [(-y, z) for y, z in reversed(right)]
    sk = d.sketch("YZ", "Block")
    d.poly(right + left)
    d.finish()
    d.extrude(sk, "engine_block", BLOCK_LEN, "symmetric")


def heads(d, style="stock"):
    if style == "finned":
        return finned_heads(d)
    half = HEAD_LEN / 2
    for s in (1, -1):
        for k, (inset, h, thick, draft, radius) in enumerate(HEAD_STEPS):
            sk = d.head_plane(s, h, f"Head {s} step {k}")
            x0, x1 = sorted((-s * (-half + inset), -s * (half - inset)))
            d.c.append(cmd("sketch.rectangle.rounded", p0=skp(x0, HEAD_A[0] + inset),
                           p1=skp(x1, HEAD_A[1] - inset), radius=inch(radius)))
            d.finish()
            kw = {"taper": draft} if draft else {}
            name = f"cylinder_head_{s}" if k == 0 else f"cylinder_head_body_{s}"
            d.extrude(sk, name, thick, **kw)

        # Nuts, with their studs standing up out of them.
        studs = [(x, HEAD_A[1] - d) for d, xs in STUD_ROWS for x in xs]
        sk = d.head_plane(s, HEAD_TOP, f"Head nuts {s}")
        for x, a in studs:
            d.c.append(cmd("sketch.polygon.inscribed", center=skp(-s * x, a),
                           radius=NUT_R * MM, sides=6))
        d.finish()
        d.extrude(sk, f"cylinder_head_nuts_{s}", 0.5)
        sk = d.head_plane(s, HEAD_TOP, f"Head studs {s}")
        for x, a in studs:
            d.c.append(cmd("sketch.circle.center", center=skp(-s * x, a), radius=inch(0.2)))
        d.finish()
        d.extrude(sk, f"cylinder_head_studs_{s}", 0.35, start_offset=inch(0.5))

        plug_a = HEAD_A[1] - PLUG_IN
        for part, size, start, length in (("spark_plug_base", 0.45, 0.0, 0.35),
                                          ("spark_plug", 0.28, 0.35, 1.2),
                                          ("spark_plug_tip", 0.13, 1.55, 0.35)):
            sk = d.head_plane(s, HEAD_TOP, f"{part} {s}")
            for x in PLUG_X:
                if part == "spark_plug_base":
                    d.c.append(cmd("sketch.polygon.inscribed", center=skp(-s * x, plug_a),
                                   radius=size * MM, sides=6))
                else:
                    d.c.append(cmd("sketch.circle.center", center=skp(-s * x, plug_a),
                                   radius=inch(size)))
            d.finish()
            d.extrude(sk, f"{part}_{s}", length, start_offset=inch(start))

        # Water outlet: the pedestal back from the face, the flange forward of it with its
        # port and bolt holes, and a dark floor in the port. YZ sketches: (y, z).
        _, _, inn = bank(s)
        u = bank(s)[0]
        oc = np.array(on_head(s, *OUTLET))
        corners = [tuple(oc + OUTLET_CORNER * (math.cos(t) * inn + math.sin(t) * u))
                   for t in (math.pi / 2, math.pi * 7 / 6, -math.pi / 6)]
        corners.sort(key=lambda c: math.atan2(c[1] - oc[1], c[0] - oc[0]))
        outline = hull_outline([(c, OUTLET_CORNER_R) for c in corners])
        face = -HEAD_LEN / 2 - OUTLET_FORWARD - s * BANK_SHIFT
        sk = d.sketch("YZ", f"Water outlet {s}", offset=face)
        d.c += outline_commands(*outline)
        d.finish()
        d.extrude(sk, f"water_outlet_{s}", OUTLET_DEPTH)
        sk = d.sketch("YZ", f"Water outlet flange {s}", offset=face)
        d.c += outline_commands(*outline)
        d.c.append(cmd("sketch.circle.center", center=skp(*oc), radius=inch(OUTLET_PORT_R)))
        for c in corners:
            d.c.append(cmd("sketch.circle.center", center=skp(*c), radius=inch(0.17)))
        d.finish()
        d.extrude(sk, f"water_outlet_flange_{s}", OUTLET_FLANGE, "negative")
        sk = d.sketch("YZ", f"Water outlet port {s}", offset=face)
        d.c.append(cmd("sketch.circle.center", center=skp(*oc), radius=inch(OUTLET_PORT_R)))
        d.finish()
        d.extrude(sk, f"water_outlet_port_{s}", 0.05, "negative")

        # Plug wire conduit along the inner edge, dropping at the front to the distributor.
        back = head_point(s, 8.5, CONDUIT_A, HEAD_TOP + 0.4)
        front = head_point(s, -10.6, CONDUIT_A, HEAD_TOP + 0.4)
        d.cylinder(f"plug_conduit_{s}", front, (1, 0, 0), 0.6, back[0] - front[0])
        drop_to = np.array([COVER_FACE - 0.5, DISTRIBUTOR[0] + s * 1.0, DISTRIBUTOR[1] + 1.2])
        leg = drop_to - front
        d.cylinder(f"plug_conduit_drop_{s}", front, leg / np.linalg.norm(leg), 0.6,
                   float(np.linalg.norm(leg)))
        d.c.append(cmd("solid.sphere", center=pt3(front), diameter=inch(0.6), operation="new",
                       name=f"plug_conduit_bend_{s}", body_name=f"plug_conduit_bend_{s}"))


# Finned heads, after Offenhauser's for the flathead: the stock heads' outline and stud
# pattern, a lower body with fins along it, a round boss standing above the fins round
# every stud, the plugs down in ringed pockets, and the water neck at the middle of the
# inner edge.
FIN_BODY = 1.4          # body top, where the fins and bosses stand
FIN_H = 0.45
FIN_W = 0.24
FIN_PITCH = 0.6
FIN_EDGE = 0.55         # plain band round the fins, in from the body top's edge
STUD_BOSS_R = 0.5
STUD_BOSS_H = 0.6
PLUG_POCKET_R = (0.58, 0.85)
NECK = (0.0, 8.4)       # (x, a) at the middle of the inner edge
NECK_R = (0.7, 1.0)
NECK_H = 2.0
NECK_PAD_R = 1.45


def rounded_span(half_x, a0, a1, r, a):
    """Half-length along x of a rounded rectangle (half_x by a0..a1, corner radius r) at a."""
    dy = max(a0 + r - a, a - (a1 - r), 0.0)
    return half_x - (r - math.sqrt(max(r * r - dy * dy, 0.0)))


def finned_heads(d):
    half = HEAD_LEN / 2
    body = [(0.0, 0.0, 0.3, None, 1.8), (0.25, 0.3, FIN_BODY - 0.3, "-8 deg", 1.6)]
    top_in = 0.25 + (FIN_BODY - 0.3) * math.tan(math.radians(8))
    fin_half = half - top_in - FIN_EDGE
    fin_a = (HEAD_A[0] + top_in + FIN_EDGE, HEAD_A[1] - top_in - FIN_EDGE)
    fin_r = 1.6 - top_in
    studs = [(x, HEAD_A[1] - dd) for dd, xs in STUD_ROWS for x in xs]
    top = FIN_BODY + STUD_BOSS_H
    for s in (1, -1):
        for k, (inset, h, thick, draft, radius) in enumerate(body):
            sk = d.head_plane(s, h, f"Finned head {s} step {k}")
            x0, x1 = sorted((-s * (-half + inset), -s * (half - inset)))
            d.c.append(cmd("sketch.rectangle.rounded", p0=skp(x0, HEAD_A[0] + inset),
                           p1=skp(x1, HEAD_A[1] - inset), radius=inch(radius)))
            d.finish()
            kw = {"taper": draft} if draft else {}
            name = f"cylinder_head_{s}" if k == 0 else f"cylinder_head_body_{s}"
            d.extrude(sk, name, thick, **kw)

        sk = d.head_plane(s, FIN_BODY, f"Fins {s}")
        n = int((fin_a[1] - fin_a[0] - FIN_W) / FIN_PITCH) + 1
        a_first = (fin_a[0] + fin_a[1]) / 2 - (n - 1) * FIN_PITCH / 2
        for i in range(n):
            a = a_first + i * FIN_PITCH
            hx = min(rounded_span(fin_half, fin_a[0], fin_a[1], fin_r, a - FIN_W / 2),
                     rounded_span(fin_half, fin_a[0], fin_a[1], fin_r, a + FIN_W / 2))
            d.c.append(cmd("sketch.rectangle.two_point", p0=skp(-hx, a - FIN_W / 2),
                           p1=skp(hx, a + FIN_W / 2)))
        d.finish()
        d.extrude(sk, f"cylinder_head_fins_{s}", FIN_H)

        sk = d.head_plane(s, FIN_BODY, f"Stud bosses {s}")
        for x, a in studs:
            d.c.append(cmd("sketch.circle.center", center=skp(-s * x, a), radius=inch(STUD_BOSS_R)))
        d.finish()
        d.extrude(sk, f"cylinder_head_bosses_{s}", STUD_BOSS_H)

        plug_a = HEAD_A[1] - PLUG_IN
        sk = d.head_plane(s, FIN_BODY, f"Plug pockets {s}")
        for x in PLUG_X:
            d.c.append(cmd("sketch.circle.center", center=skp(-s * x, plug_a),
                           radius=inch(PLUG_POCKET_R[1])))
            d.c.append(cmd("sketch.circle.center", center=skp(-s * x, plug_a),
                           radius=inch(PLUG_POCKET_R[0])))
        d.finish()
        d.extrude(sk, f"cylinder_head_plug_pockets_{s}", STUD_BOSS_H)

        sk = d.head_plane(s, top, f"Head nuts {s}")
        for x, a in studs:
            d.c.append(cmd("sketch.polygon.inscribed", center=skp(-s * x, a),
                           radius=NUT_R * MM, sides=6))
        d.finish()
        d.extrude(sk, f"cylinder_head_nuts_{s}", 0.5)
        sk = d.head_plane(s, top, f"Head studs {s}")
        for x, a in studs:
            d.c.append(cmd("sketch.circle.center", center=skp(-s * x, a), radius=inch(0.2)))
        d.finish()
        d.extrude(sk, f"cylinder_head_studs_{s}", 0.35, start_offset=inch(0.5))

        # Plugs stand from the pocket floors.
        for part, size, start, length in (("spark_plug_base", 0.45, 0.0, 0.35),
                                          ("spark_plug", 0.28, 0.35, 1.2),
                                          ("spark_plug_tip", 0.13, 1.55, 0.35)):
            sk = d.head_plane(s, FIN_BODY, f"{part} {s}")
            for x in PLUG_X:
                if part == "spark_plug_base":
                    d.c.append(cmd("sketch.polygon.inscribed", center=skp(-s * x, plug_a),
                                   radius=size * MM, sides=6))
                else:
                    d.c.append(cmd("sketch.circle.center", center=skp(-s * x, plug_a),
                                   radius=inch(size)))
            d.finish()
            d.extrude(sk, f"{part}_{s}", length, start_offset=inch(start))

        # Water neck: a pad over the fins, the neck standing up off it, a dark floor.
        nx, na = NECK
        sk = d.head_plane(s, FIN_BODY, f"Neck pad {s}")
        d.c.append(cmd("sketch.circle.center", center=skp(-s * nx, na), radius=inch(NECK_PAD_R)))
        d.finish()
        d.extrude(sk, f"cylinder_head_neck_pad_{s}", FIN_H + 0.1)
        sk = d.head_plane(s, FIN_BODY, f"Neck {s}")
        d.c.append(cmd("sketch.circle.center", center=skp(-s * nx, na), radius=inch(NECK_R[1])))
        d.c.append(cmd("sketch.circle.center", center=skp(-s * nx, na), radius=inch(NECK_R[0])))
        d.finish()
        d.extrude(sk, f"water_outlet_neck_{s}", NECK_H)
        sk = d.head_plane(s, FIN_BODY + FIN_H + 0.1, f"Neck port {s}")
        d.c.append(cmd("sketch.circle.center", center=skp(-s * nx, na), radius=inch(NECK_R[0])))
        d.finish()
        d.extrude(sk, f"water_outlet_port_{s}", 0.05)


def valley_y():
    """Where the valley floor meets the bank's inner wall, out from the middle."""
    _, in_r = deck_edges(1)
    return in_r[0] - (in_r[1] - VALLEY_Z)


def intake_base(d):
    """The plate down the valley, its sides along the heads' inner edges; its top's z."""
    gap = 0.05
    top = VALLEY_Z + 1.4
    y0 = valley_y() - gap
    y1 = y0 + (top - VALLEY_Z)
    sk = d.sketch("YZ", "Intake")
    d.poly([(y0, VALLEY_Z), (y1, top), (-y1, top), (-y0, VALLEY_Z)])
    d.finish()
    d.extrude(sk, "intake_manifold", 19.0, "symmetric")
    return top, y1


def carburetor(d, x, z, suffix="", across=False):
    """A Ford two-barrel on a pad at z: base flange, body, air horn, two throats, side by
    side along the engine, or across it. Across, it sits straight on the intake's own
    shaped pad, without a square base flange of its own."""
    if not across:
        d.box(f"carburetor_base{suffix}", (x - 1.5, -1.4, z), (x + 1.5, 1.4, z + 0.25))
        z += 0.25
    sk = d.sketch("XY", f"Carburetor{suffix}", offset=z)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(x - 1.2, -1.1), p1=skp(x + 1.2, 1.1),
                   radius=inch(0.4)))
    d.finish()
    d.extrude(sk, f"carburetor{suffix}", 1.6)
    d.cylinder(f"carburetor_horn{suffix}", (x, 0, z + 1.6), (0, 0, 1), 2.3, 0.7)
    for end, off in (("front", -0.55), ("back", 0.55)):
        cx, cy = (x, off) if across else (x + off, 0)
        d.cylinder(f"carb_throat{suffix}_{end}", (cx, cy, z + 1.6), (0, 0, 1), 0.85, 0.72)


def generator_stand(d, top):
    gz = GENERATOR[1] - GENERATOR_R + 0.1
    d.box("intake_manifold_generator_stand", (-10.5, -1.6, top), (-7.5, 1.6, gz))


def intake(d, style="stock"):
    if style == "3x2":
        return intake_3x2(d)
    top, _ = intake_base(d)
    sk = d.sketch("XY", "Intake spine", offset=top)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(-8.5, -1.0), p1=skp(8.5, 1.0), radius=inch(0.9)))
    d.finish()
    d.extrude(sk, "intake_manifold_spine", 0.8)
    sk = d.sketch("XY", "Intake riser", offset=top)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(-3.2, -2.6), p1=skp(3.2, 2.6), radius=inch(0.8)))
    d.finish()
    riser_top = top + 1.8
    d.extrude(sk, "intake_manifold_riser", 1.8)
    carburetor(d, 0.0, riser_top)

    # The generator's stand at the front of the intake, the oil filler behind it.
    generator_stand(d, top)
    d.cylinder("intake_manifold_oil_filler", (-5.6, -2.2, top), (0, 0, 1), 1.6, 4.0)
    d.cylinder("intake_manifold_oil_filler_cap", (-5.6, -2.2, top + 4.0), (0, 0, 1), 2.5, 0.8)


# Three two-barrel intake, after the aftermarket ones for the flathead, in the 59A
# pattern: a plenum log down the middle, three tall drafted risers with a two-bore pad
# on each (the bores across the engine), a bulge over each runner out to the ports,
# bolt bosses along the edges, the generator's stand at the front and the oil filler
# at the back. The carburetors stand back enough to clear the generator.
CARB_X = (-5.0, 0.0, 5.0)
PLENUM = (8.6, 1.5, 1.4)    # half length, half width, height
RISER = (1.7, 1.55, 2.4)    # half length, half width at the base, height
PAD_BORE = (0.72, 1.0)      # bores' offset across the engine, radius
PAD_EAR = (1.35, 0.4)       # ears' offset along the engine, radius
RUNNER = (0.9, 0.8)         # bulges' half length, height


def intake_3x2(d):
    top, edge_y = intake_base(d)
    sk = d.sketch("XY", "Plenum", offset=top)
    hl, hw, ph = PLENUM
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(-hl, -hw), p1=skp(hl, hw),
                   radius=inch(hw * 0.9)))
    d.finish()
    d.extrude(sk, "intake_manifold_plenum", ph, taper="-6 deg")

    # Runner bulges from the plenum out toward each port.
    sk = d.sketch("XY", "Runners", offset=top)
    for x in BORE_X:
        for sy in (1, -1):
            y0, y1 = sorted((sy * (hw - 0.3), sy * (edge_y - 0.5)))
            d.c.append(cmd("sketch.rectangle.rounded", p0=skp(x - RUNNER[0], y0),
                           p1=skp(x + RUNNER[0], y1), radius=inch(RUNNER[0] * 0.9)))
    d.finish()
    d.extrude(sk, "intake_manifold_runners", RUNNER[1], taper="-10 deg")

    rl, rw, rh = RISER
    riser_top = top + rh
    for i, x in enumerate(CARB_X):
        sk = d.sketch("XY", f"Riser {i}", offset=top)
        d.c.append(cmd("sketch.rectangle.rounded", p0=skp(x - rl, -rw), p1=skp(x + rl, rw),
                       radius=inch(0.6)))
        d.finish()
        d.extrude(sk, f"intake_manifold_riser_{i}", rh, taper="-4 deg")

        # The pad: round the two bores and an ear front and back, with the bores and
        # the ears' bolt holes through it.
        by, br = PAD_BORE
        ex, er = PAD_EAR
        circles = [((x + ex, 0.0), er), ((x, by), br), ((x - ex, 0.0), er), ((x, -by), br)]
        sk = d.sketch("XY", f"Carb pad {i}", offset=riser_top)
        d.c += outline_commands(*hull_outline(circles))
        for (cx, cy), _ in circles[::2]:
            d.c.append(cmd("sketch.circle.center", center=skp(cx, cy), radius=inch(0.16)))
        d.finish()
        d.extrude(sk, f"intake_manifold_pad_{i}", 0.3)
        carburetor(d, x, riser_top + 0.3, f"_{i}", across=True)

    # Bolt bosses along both edges, between the runners.
    sk = d.sketch("XY", "Intake bolt bosses", offset=top)
    for x in (-8.5, -4.25, 0.0, 4.25, 8.5):
        for sy in (1, -1):
            d.c.append(cmd("sketch.circle.center", center=skp(x, sy * (edge_y - 0.55)),
                           radius=inch(0.42)))
    d.finish()
    d.extrude(sk, "intake_manifold_bosses", 0.45)

    generator_stand(d, top)
    d.cylinder("intake_manifold_oil_filler", (8.2, 0.0, top), (0, 0, 1), 1.6, 3.6)
    d.cylinder("intake_manifold_oil_filler_cap", (8.2, 0.0, top + 3.6), (0, 0, 1), 2.5, 0.8)


LOG_D = 2.0
LOG_BELOW_DECK = 1.6    # the log's middle below the deck's outer edge
LOG_BACK = 9.8
PORT_X = (-6.375, 0.0, 6.375)   # end cylinders, and the middle two sharing a port
LOBE_D = 2.3
BEND_R = 2.0
PIPE_END_Z = 0.5


def exhaust(d):
    """A slim cast log on each side against the bank's outer wall, right under the head:
    a lobe over each port, the back end closed round, the front end turning down to the
    pipe's flange."""
    out_r, _ = deck_edges(1)
    r = LOG_D / 2
    log_z = out_r[1] - LOG_BELOW_DECK
    # The outer bank wall is the line y - z = out_y - out_z; sit the log r off it.
    log_y = log_z + (out_r[0] - out_r[1]) + r * math.sqrt(2)
    bend_x = PORT_X[0]
    for s in (1, -1):
        y = s * log_y
        # XZ sketch: (x, -z), the plane moved along +y.
        sk = d.sketch("XZ", f"Exhaust {s}", offset=y)
        d.c.append(cmd("sketch.line", infer=False,
                       points=[skp(LOG_BACK, -log_z), skp(bend_x, -log_z)]))
        d.c.append(cmd("sketch.arc.center_point", center=skp(bend_x, -(log_z - BEND_R)),
                       start="l1.end", end=skp(bend_x - BEND_R, -(log_z - BEND_R)),
                       clockwise=True))
        d.c.append(cmd("sketch.line", infer=False,
                       points=["a1.end", skp(bend_x - BEND_R, -PIPE_END_Z)]))
        d.finish()
        d.c.append(cmd("solid.pipe", path_sketch=sk, path=["l1", "a1", "l2"],
                       diameter=inch(LOG_D), operation="new", name=f"exhaust_collector_{s}",
                       body_name=f"exhaust_collector_{s}"))
        d.c.append(cmd("solid.sphere", center=pt3((LOG_BACK, y, log_z)), diameter=inch(LOG_D),
                       operation="new", name=f"exhaust_end_{s}", body_name=f"exhaust_end_{s}"))
        for i, x in enumerate(PORT_X):
            d.c.append(cmd("solid.sphere", center=pt3((x, s * (log_y - 0.2), log_z + 0.15)),
                           diameter=inch(LOBE_D), operation="new",
                           name=f"exhaust_runner_{s}_{i}", body_name=f"exhaust_runner_{s}_{i}"))
        d.cylinder(f"exhaust_flange_{s}", (bend_x - BEND_R, y, PIPE_END_Z + 0.3), (0, 0, -1),
                   2.9, 0.35)


def bell_housing(d):
    d.c.append(cmd("solid.cone", base=pt3((BELL_FRONT, 0, 0)), axis="X",
                   radius=inch(BELL_R[0]), top_radius=inch(BELL_R[1]),
                   height=inch(BELL_BACK - BELL_FRONT), operation="new",
                   name="engine_block_bell", body_name="engine_block_bell"))
    d.cylinder("engine_block_bell_flange", (BELL_BACK - 0.45, 0, 0), (1, 0, 0),
               BELL_R[1] * 2 + 0.8, 0.45)
    d.cylinder("engine_block_starter_boss", (BELL_FRONT - 1.0, 6.6, -4.2), (1, 0, 0), 3.8,
               BELL_BACK - BELL_FRONT + 0.6)


def oil_pan(d):
    sk = d.sketch("XY", "Oil pan", offset=RAIL_Z)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(-11.3, -RAIL_Y + 0.2), p1=skp(11.3, RAIL_Y - 0.2),
                   radius=inch(1.0)))
    d.finish()
    d.extrude(sk, "oil_pan", 1.8, "negative")
    sk = d.sketch("XY", "Sump", offset=RAIL_Z - 1.8)
    d.c.append(cmd("sketch.rectangle.rounded", p0=skp(0.5, -5.4), p1=skp(10.8, 5.4), radius=inch(1.2)))
    d.finish()
    d.extrude(sk, "oil_pan_sump_detail", 2.8, "negative")
    d.cylinder("oil_pan_drain", (8.0, 0, RAIL_Z - 4.6), (0, 0, -1), 0.9, 0.3)


def front(d):
    # Timing cover: round the crank and up round the cam.
    sk = d.sketch("YZ", "Timing cover", offset=COVER_BACK)
    d.c += outline_commands(*hull_outline([((0.0, 0.0), 3.8), (CAM, 3.0)]))
    d.finish()
    d.extrude(sk, "timing_cover", COVER_BACK - COVER_FACE, "negative")

    # Distributor lying forward off the cam's nose, cap to the front.
    dx, dz = DISTRIBUTOR
    d.cylinder("distributor_body", (COVER_FACE, dx, dz), (-1, 0, 0), 2.6, 1.0)
    d.cylinder("distributor_cap", (COVER_FACE - 1.0, dx, dz), (-1, 0, 0), 3.6, 1.1)

    # Generator on its stand, the fan on its pulley.
    gy, gz = GENERATOR
    d.cylinder("generator", (BELT_X + 0.6, gy, gz), (1, 0, 0), GENERATOR_R * 2,
               GENERATOR_BACK - BELT_X - 0.6)

    # Water pumps low on the front, one each side of the timing cover.
    for s in (1, -1):
        d.cylinder(f"water_pump_housing_{s}", (COVER_BACK, s * PUMP[0], PUMP[1]), (-1, 0, 0),
                   3.6, 1.5)
    d.cylinder("fan_shaft", (BELT_X - 0.45, gy, gz), (-1, 0, 0), 1.4, -FAN_X + BELT_X + 0.45)
    d.cylinder("fan_hub", (FAN_X + 0.3, gy, gz), (-1, 0, 0), 3.2, 0.5)
    sk = d.sketch("YZ", "Fan", offset=FAN_X)
    blade = [(1.2, -1.0), (FAN_R - 1.2, -1.5), (FAN_R, -0.9), (FAN_R, 0.9), (FAN_R - 1.2, 1.5),
             (1.2, 1.0)]
    for k in range(4):
        t = math.radians(45 + 90 * k)
        c, sn = math.cos(t), math.sin(t)
        d.poly([(gy + r * c - w * sn, gz + r * sn + w * c) for r, w in blade])
    d.finish()
    d.extrude(sk, "fan_blades", 0.12, "symmetric")

    # Pulleys in the belt's plane, and the belt round them.
    pulleys = [("crank", (0.0, 0.0), 3.2), ("pump_1", PUMP, 2.2),
               ("generator", GENERATOR, 1.8), ("pump_-1", (-PUMP[0], PUMP[1]), 2.2)]
    for name, (py, pz), r in pulleys:
        d.cylinder(f"pulley_{name}", (BELT_X + 0.45, py, pz), (-1, 0, 0), r * 2, 0.9)
    d.cylinder("crank_snout", (COVER_FACE, 0, 0), (-1, 0, 0), 2.0, COVER_FACE - BELT_X)
    sk = d.sketch("YZ", "Belt", offset=BELT_X)
    # The belt is the ring between the outline round the pulleys and one its thickness out.
    d.c += outline_commands(*hull_outline([(c, r) for _, c, r in pulleys]))
    d.c += outline_commands(*hull_outline([(c, r + 0.3) for _, c, r in pulleys]),
                            first=len(pulleys) + 1)
    d.finish()
    d.extrude(sk, "belt", 0.55, "symmetric")


# Run inside Blender: weld, dissolve the coplanar triangles SolidCraft's tessellation
# leaves (a cylinder comes out in fifteen rows of 128 facets), then collapse each body to
# a triangle budget by its size, and write the result as an OBJ.
BLENDER_REDUCE = r"""
import bmesh, bpy, math, sys
src, dst = sys.argv[sys.argv.index("--") + 1:]
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
    # Budget: about four triangles per facet round a cylinder, the facets by the body's
    # middle extent (millimeters) from 10 up to 36.
    size = sorted(ob.dimensions)[1] / 25.4
    budget = 4 * min(36, max(10, int(5 * size)))
    if tris > budget * 1.5:
        mod = ob.modifiers.new("reduce", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = budget * 1.5 / tris
bpy.ops.wm.obj_export(filepath=dst, apply_modifiers=True, export_normals=False, export_uv=False,
                      export_materials=False, export_triangulated_mesh=True)
"""


def reduce_obj(src, dst, blender):
    r = subprocess.run([blender, "-b", "--factory-startup", "--python-expr", BLENDER_REDUCE,
                        "--", src, dst], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(dst):
        sys.exit(f"blender: {r.stderr.strip() or r.stdout.strip()}")


def read_tris(path):
    """{object name: (positions, triangle indices)} of an OBJ of triangles."""
    v, objs, cur = [], {}, None
    with open(path) as f:
        for line in f:
            if line.startswith("v "):
                v.append([float(t) for t in line.split()[1:4]])
            elif line.startswith("o "):
                cur = objs.setdefault(line[2:].strip(), [])
            elif line.startswith("f "):
                cur.append([int(t.split("/")[0]) - 1 for t in line.split()[1:4]])
    v = np.array(v)
    out = {}
    for name, faces in objs.items():
        faces = np.array(faces)
        used, inv = np.unique(faces, return_inverse=True)
        out[name] = (v[used], inv.reshape(-1, 3))
    return out


def crease_normals(pos, tri, crease_deg=40.0):
    """Per-corner positions, normals and indices: a corner takes the area-weighted normals
    of the triangles round its vertex that are within the crease angle of its own, so flat
    faces stay flat and round ones shade smooth."""
    fn = np.cross(pos[tri[:, 1]] - pos[tri[:, 0]], pos[tri[:, 2]] - pos[tri[:, 0]])
    keep = np.linalg.norm(fn, axis=1) > 1e-12
    tri, fn = tri[keep], fn[keep]
    unit = fn / np.linalg.norm(fn, axis=1, keepdims=True)
    around = [[] for _ in range(len(pos))]
    for f, t in enumerate(tri):
        for vtx in t:
            around[vtx].append(f)
    cos_crease = math.cos(math.radians(crease_deg))
    out_p, out_n, index, seen = [], [], [], {}
    for f, t in enumerate(tri):
        for vtx in t:
            near = [g for g in around[vtx] if unit[g] @ unit[f] >= cos_crease]
            n = fn[near].sum(axis=0)
            n /= np.linalg.norm(n)
            key = (vtx, tuple(np.round(n, 4)))
            if key not in seen:
                seen[key] = len(out_p)
                out_p.append(pos[vtx])
                out_n.append(n)
            index.append(seen[key])
    return np.array(out_p), np.array(out_n), np.array(index, dtype=np.uint32)


def finish_for(name, styles=None):
    styles = styles or {}
    if styles.get("heads") == "finned" and name.startswith(("cylinder_head", "water_outlet_neck")) \
            and not name.startswith(("cylinder_head_nuts", "cylinder_head_studs")):
        return SATIN_ALUMINUM
    if styles.get("intake") == "3x2" and name.startswith("intake_manifold") and not name.endswith("_cap"):
        return SATIN_ALUMINUM
    for prefix, mat in FINISHES:
        if name.startswith(prefix):
            return mat
    return PAINT


HEAD_STYLES = ("stock", "finned")
INTAKE_STYLES = ("stock", "3x2")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("what", nargs="?", default="engine", choices=("engine", "heads", "intake"),
                    help="the whole engine (default), or only its heads or its intake")
    ap.add_argument("--heads", default="stock", choices=HEAD_STYLES)
    ap.add_argument("--intake", default="stock", choices=INTAKE_STYLES)
    ap.add_argument("--sc", help="design file (default resources/engines/STEM.sc)")
    ap.add_argument("--glb", help="mesh (default assets/parts/STEM.glb)")
    ap.add_argument("--solidcraft", default="solidcraft-cli",
                    help="solidcraft-cli, or the SolidCraft AppImage")
    ap.add_argument("--blender", default="blender", help="Blender, which thins the mesh")
    args = ap.parse_args()
    if args.what == "heads":
        stem = f"flathead-heads-{args.heads}"
    elif args.what == "intake":
        stem = f"flathead-intake-{args.intake}"
    else:
        stem = "-".join([STEM] + [v for v in (args.heads, args.intake) if v != "stock"])
    sc = os.path.abspath(args.sc or os.path.join(ROOT, "resources", "engines", stem + ".sc"))
    glb = os.path.abspath(args.glb or os.path.join(ROOT, "assets", "parts", stem + ".glb"))
    tool = shutil.which(args.solidcraft) or args.solidcraft
    if not os.path.exists(tool):
        sys.exit(f"no SolidCraft command line at {args.solidcraft}")
    blender = shutil.which(args.blender) or args.blender
    if not os.path.exists(blender):
        sys.exit(f"no Blender at {args.blender}")

    d = Design()
    if args.what == "heads":
        heads(d, args.heads)
    elif args.what == "intake":
        intake(d, args.intake)
    else:
        block(d)
        heads(d, args.heads)
        intake(d, args.intake)
        exhaust(d)
        bell_housing(d)
        oil_pan(d)
        front(d)

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

    # Design mm -> engine units (ENGINE_SCALE m), crank down to the models' Z.
    # A sketch of several separate shapes extrudes into a body each, "name (2)" and on:
    # put them back in one mesh.
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
        parts.append((name, p, nr, i, finish_for(name, {"heads": args.heads, "intake": args.intake})))
    write_glb(glb, parts)
    allp = np.concatenate([p for _, p, *_ in parts])
    print(f"{os.path.relpath(sc, ROOT)}\n{os.path.relpath(glb, ROOT)}: {len(parts)} bodies, "
          f"{sum(len(i) for *_, i, _ in parts) // 3} triangles, extent "
          f"{np.round(allp.min(axis=0), 2).tolist()} to {np.round(allp.max(axis=0), 2).tolist()}")


if __name__ == "__main__":
    main()
