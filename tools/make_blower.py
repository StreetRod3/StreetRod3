#!/usr/bin/env python3
"""Build a Roots blower intake for an engine in SolidCraft and export it as a game GLB.

    python3 tools/make_blower.py sbc        # the Chevy small-block's
    python3 tools/make_blower.py sbf-302    # the small-block Ford's, on the 302's deck or the 351's
    python3 tools/make_blower.py hemi-426   # the 426 Hemi's

A blower intake is everything that takes the intake's place: a low manifold bolted to the
heads, a GMC-type Roots blower standing on it with two four-barrel pads in tandem on its
top, and its drive, a cog belt from a pulley on the crank's nose round an idler and the
blower's pulley at the end of its snout. The reference is the blower off "Blown 454 cid
V8" by Jorma Rysky (reference/parts/supercharger/, its notes have the measurements). It
has:

  manifold      the intake's flanges on the heads with their bolts and the floor over
                the valley, as the engine's own intake; a box rising from the floor and
                flaring out to the blower's footprint, its flat top under the case; the
                water outlet on the box's front; the distributor's boss
  case          the rotor case's section along its length: a base flange with bosses
                and nuts down each side, the sides flat and slightly bulged, the top
                corners chamfered in to the inlet flange; five ribs down each side; the
                front gear cover, deeper than the case all round; the rear cover with the
                bearing plate over the rotors' ends (an eight on its side) and its bolts
                round it
  top           the inlet plate across the case's top with a square-flange four-barrel
                pad at each end, open down to a dark floor (the game sets the carbs and
                air cleaners on them)
  drive         the snout out of the gear cover, its pulley flanged each side of the
                belt; the idler beside it on a bracket clamped to the snout; a flanged
                pulley on a hub on the crank's nose ahead of the engine's own pulleys;
                the belt round the three

The case is a 6-71's on the V8s. The belt runs down the engine's middle in front of the
water pump, so the engine's fan comes off with a blower (the game hides it). On the Chevy
the case sits over the middle of the engine, ahead of the distributor at the back; the Ford
and the Hemi have theirs at the front, so their cases sit back on a box the floor's length,
and a long snout reaches forward over the distributor to the belt.

Every part is a body of its own, drawn from numbers in this script and, for what bolts to
the engine, from the engine's own script (make_sbc.py, make_sbf.py, make_hemi.py), in the
engines' design frame: inches, +X toward the back, +Y right, +Z up, the crank on the X
axis. Writes resources/engines/blower-ENGINE.sc and assets/parts/blower-ENGINE.glb, in the engine
models' frame (engine units of 0.22 m, the crank at Z -0.36). Needs SolidCraft's command
line and Blender, as tools/make_flathead.py does.
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
from make_flathead import (  # noqa: E402
    BLACK, CAST_ALUMINUM, RUBBER, SATIN_ALUMINUM, STEEL, crease_normals, hull_outline, inch,
    outline_commands, read_tris)
from make_sbc import BLENDER_REDUCE, SBC, ccw, hose_neck, p3, unit, v3  # noqa: E402
from make_sbf import shrunk  # noqa: E402
from make_wheels import SolidCraft, cmd, write_glb  # noqa: E402
import make_sbc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The case, in its own frame: x back from the rotor case's front face, |y| across, z up
# from the base. The rotor case's length (a 6-71's), the base flange (half wide, thick),
# the section's right half up from the flange to the inlet's edge.
CASE_LEN = 15.4
CASE_FLANGE = (5.3, 0.5)
CASE_SECTION = [(4.55, 0.5), (4.7, 1.2), (4.7, 5.3), (4.05, 6.5), (3.4, 6.9)]
# Ribs down each side (x as a fraction of the length), standing out, thick along x.
RIB_AT = [0.1, 0.3, 0.5, 0.7, 0.9]
RIB = (0.3, 0.35)
# The studs' bosses up the sides between the ribs (x fractions), at |y|, radius, top;
# the nuts on them, across flats and tall.
BOSS_AT = [0.2, 0.4, 0.6, 0.8]
BOSS = (4.85, 0.42, 1.35)
NUT = (0.56, 0.35)
# The inlet flange on the top (half wide, thick, in from the ends), the inlet plate on it
# (half long, half wide, thick), the four-barrel pads on it (x from the case's middle), and
# a pad's throttle bores as make_sbc.py's.
INLET_FLANGE = (3.4, 0.35, 0.2)
TOP_PLATE = (7.3, 3.5, 0.8)
PADS_X = (-4.25, 4.25)    # far enough apart for the game's two 8 in round cleaners
PAD_HOLES = make_sbc.PAD_HOLES
PAD_HOLE_R = make_sbc.PAD_HOLE_R
PAD_SLOT = make_sbc.PAD_SLOT
PAD_FLOOR = (2.3, 2.0)     # the dark floor under each pad's bores (half long, half wide)
# The gear cover ahead of the case (deep, how much bigger than the case all round), the
# rear cover (thick, bigger), the bearing plate on it (the eight's circles' |y|, z, radius;
# thick), its bolts round it.
FRONT_COVER = (2.3, 0.3)
REAR_COVER = (0.7, 0.15)
BEARING_PLATE = (2.05, 3.5, 2.2, 0.25)
BEARING_BOLTS = 10
# The drive: the snout's axis up from the base, its cone (radius at the cover, at its
# nose), the nose's collar (radius, long); the belt (wide, thick); the pulleys' radii
# under the belt (blower, idler, crank) and their flanges (out past the belt, thick);
# the idler's place from the snout's axis (y, z); the idler bracket (thick, round the
# snout, round the idler's axle).
SNOUT_Z = 3.3
SNOUT_R = (2.3, 1.5)
SNOUT_COLLAR = (1.75, 0.4)
BELT = (2.9, 0.3)
BLOWER_PULLEY_R = 1.9
IDLER_R = 2.5
CRANK_DRIVE_R = 3.6
PULLEY_FLANGE = (0.2, 0.2)
IDLER_AT = (5.3, -1.3)
IDLER_BRACKET = (0.4, 2.1, 0.9)
CRANK_HUB_R = 1.4

# Each engine: where the case's front face and base are (x, z), the belt's middle plane,
# the front of the crank pulley the game draws (engine_assembly.gd's belt line less the
# pulley's half width; the drive's hub starts there), and the manifold's
# box (its foot's front and back along x, its head's front; the head's back is the case's).
ENGINES = {
    "sbc": {
        # The case ends ahead of the distributor's cap at the back (from x 6.74, up to z
        # 16.7); the belt clears the water pump's hub (-14.45).
        "case": (-10.05, 13.6),
        "belt_x": -16.1,
        "crank_front": -13.87,
        "manifold": "sbc",
    },
    # The Ford's distributor stands at the front (its cap back to x -7.32, up to z 14.97 on
    # the 302 and 15.87 on the 351), so the case sits back behind it, its front cover clear
    # of the cap, and a long snout reaches forward over the cap to the belt ahead of the
    # water pump's pulley (-16.3). The box starts behind the cap and runs the floor's length.
    "sbf-302": {
        "case": (-4.6, 14.3),
        "belt_x": -18.05,
        "crank_front": -15.82,
        "manifold": "sbf",
        "deck": "302",
        "box": (-7.1, 9.2, -7.1),
    },
    "sbf-351": {
        "case": (-4.6, 15.2),
        "belt_x": -18.05,
        "crank_front": -15.82,
        "manifold": "sbf",
        "deck": "351",
        "box": (-7.1, 9.2, -7.1),
    },
    # The Hemi's distributor at the right front stands lower than the box (cap up to z
    # 15.95, back to x -8.28); the case sits back as the Ford's, on the same long snout.
    "hemi-426": {
        "case": (-4.6, 17.8),
        "belt_x": -17.9,
        "crank_front": -15.67,
        "manifold": "hemi",
        "box": (-8.0, 9.6, -8.0),
    },
}

# Not a mirror: fully metallic, the shop's dark reflections turned it gunmetal on the hood screen.
POLISHED = {"name": "polished aluminum", "pbrMetallicRoughness": {
    "baseColorFactor": [0.88, 0.88, 0.87, 1], "metallicFactor": 0.7, "roughnessFactor": 0.3}}
FINISHES = [
    ("intake_manifold_bolts", STEEL), ("intake_bolts", STEEL), ("intake_manifold", CAST_ALUMINUM), ("thermostat_neck_bore", BLACK),
    ("thermostat", CAST_ALUMINUM), ("blower_top_floor", BLACK), ("blower_nuts", STEEL),
    ("blower_bearing_bolts", STEEL), ("blower_pulley_nut", STEEL), ("blower_belt", RUBBER),
    ("blower_idler_bracket", CAST_ALUMINUM), ("blower_idler", SATIN_ALUMINUM),
    ("blower_pulley", SATIN_ALUMINUM), ("blower_crank", SATIN_ALUMINUM), ("blower", POLISHED),
]

ROUND = "r0.35"
REDUCE_FACTORS = [
    ("intake_manifold_bolt_bosses", 1), ("intake_manifold_distributor", 1),
    ("intake_manifold", 0), ("intake_bolts", 0), ("thermostat", 1), ("blower_bosses", 1), ("blower_nuts", 0),
    ("blower_bearing_bolts", 0), ("blower_top_floor", 0), ("blower_top", 2), ("blower_snout", 1),
    ("blower_pulley", 1), ("blower_idler", 1), ("blower_crank", 1), ("blower_belt", 3), ("blower", 0),
]


class Blower(SBC):
    def __init__(self, engine):
        super().__init__()
        self.x0, self.zb = engine["case"]
        self.belt_x = engine["belt_x"]
        self.crank_front = engine["crank_front"]

    def at(self, x, y, z):
        """The design point of (x, y, z) in the case's frame."""
        return np.array([self.x0 + x, y, self.zb + z], float)

    def snout_yz(self):
        return (0.0, self.zb + SNOUT_Z)

    def idler_yz(self):
        return (IDLER_AT[0], self.zb + SNOUT_Z + IDLER_AT[1])


def section(grow=0.0, z_top=None):
    """The case's section in (y, z) from its base, counterclockwise, grown by `grow` all round."""
    right = list(CASE_SECTION)
    if z_top is not None:
        right[-1] = (right[-1][0], z_top)
    pts = right + [(-y, z) for y, z in reversed(right)]
    pts = ccw(pts)
    return shrunk(pts, -grow) if grow else pts


def yz_sketch(d, x, name):
    """A sketch on the plane across the engine at x, its (x, y) the design's (y, z); extruding
    positive goes back."""
    return d.sketch("YZ", name, offset=x)


def case(d):
    x0, zb = d.x0, d.zb
    # The rotor case.
    sk = yz_sketch(d, x0, "Case")
    d.poly([(y, zb + z) for y, z in section()])
    d.finish()
    d.extrude(sk, "blower_case", CASE_LEN)
    hw, ft = CASE_FLANGE
    sk = d.sketch("XY", "Case flange", offset=zb)
    d.rounded((x0, -hw), (x0 + CASE_LEN, hw), 0.35)
    d.finish()
    d.extrude(sk, "blower_case_flange", ft)

    # Ribs down each side, following the section out past it.
    out, thick = RIB
    for k, f in enumerate(RIB_AT):
        x = x0 + f * CASE_LEN - thick / 2
        sk = yz_sketch(d, x, f"Rib {k}")
        # Up the flat side and the chamfer above it, out past them, and back in.
        (ya, _), (yb, zs), (yc, zc) = CASE_SECTION[0], CASE_SECTION[2], CASE_SECTION[3]
        pts = [(ya + 0.05, ft), (yb + out, ft), (yb + out, zs), (yc + out * 0.7, zc + 0.1), (yc - 0.3, zc + 0.1)]
        for s in (1, -1):
            d.poly(ccw([(s * y, zb + z) for y, z in pts]))
        d.finish()
        d.extrude(sk, f"blower_ribs_{k}", thick)

    # Studs' bosses up the sides between the ribs, the nuts on them.
    by, br, btop = BOSS
    sk = d.sketch("XY", "Case bosses", offset=zb + ft - 0.05)
    for f in BOSS_AT:
        for s in (1, -1):
            d.circle((x0 + f * CASE_LEN, s * by), br)
    d.finish()
    d.extrude(sk, "blower_bosses", btop - ft + 0.05)
    af, nh = NUT
    sk = d.sketch("XY", "Case nuts", offset=zb + btop)
    for f in BOSS_AT:
        for s in (1, -1):
            d.hexagon((x0 + f * CASE_LEN, s * by), af)
    d.finish()
    d.extrude(sk, "blower_nuts", nh)

    # The gear cover ahead of the case, a little taller than it.
    deep, grow = FRONT_COVER
    sk = yz_sketch(d, x0, "Gear cover")
    d.poly([(y, zb + z) for y, z in section(grow, CASE_SECTION[-1][1] + 0.1)])
    d.finish()
    d.extrude(sk, "blower_front_cover", deep, "negative")

    # The rear cover, and the bearing plate on it over the rotors' ends.
    thick, grow = REAR_COVER
    rear = x0 + CASE_LEN
    sk = yz_sketch(d, rear, "Rear cover")
    d.poly([(y, zb + z) for y, z in section(grow)])
    d.finish()
    d.extrude(sk, "blower_rear_cover", thick)
    py, pz, pr, pt = BEARING_PLATE
    # An eight on its side: a round plate over each rotor's end, overlapping in the middle.
    for s in (1, -1):
        d.cylinder(f"blower_bearing_plate_{s}", (rear + thick, s * py, zb + pz), (1, 0, 0), 2 * pr, pt)
    # Its bolts round the eight: half on each lobe's outer arc, the rest across the waist.
    sk = yz_sketch(d, rear + thick + pt, "Bearing bolts")
    for k in range(BEARING_BOLTS):
        t = 2 * math.pi * k / BEARING_BOLTS
        y = (py if math.cos(t) >= 0 else -py) + (pr - 0.35) * math.cos(t)
        z = pz + (pr - 0.35) * math.sin(t)
        if abs(y) < py - 0.6:
            continue
        d.hexagon((y, zb + z), 0.4)
    d.finish()
    d.extrude(sk, "blower_bearing_bolts", 0.22)


def top(d):
    """The inlet flange and the plate with the two pads, open down to a dark floor."""
    x0, zb = d.x0, d.zb
    mid = x0 + CASE_LEN / 2
    z = zb + CASE_SECTION[-1][1]
    hw, ft, inset = INLET_FLANGE
    sk = d.sketch("XY", "Inlet flange", offset=z - 0.05)
    d.rounded((x0 + inset, -hw), (x0 + CASE_LEN - inset, hw), 0.4)
    d.finish()
    d.extrude(sk, "blower_inlet_flange", ft + 0.05)
    z += ft
    hl, hw, pt = TOP_PLATE
    corners = [((mid + sx * (hl - 0.6), sy * (hw - 0.6)), 0.6) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))]

    def openings(first):
        # Both slots first, numbered on from the outline's lines and arcs; then the
        # circles, which take arc numbers of their own.
        (sx0, sy0), (sx1, sy1), sr = PAD_SLOT
        for j, px in enumerate(PADS_X):
            d.c += outline_commands(*hull_outline([((mid + px + sx0, sy0), sr), ((mid + px + sx1, sy1), sr)]),
                                    first=first + 2 * j)
        for px in PADS_X:
            for x, y in PAD_HOLES:
                d.circle((mid + px + x, y), PAD_HOLE_R)

    sk = d.sketch("XY", "Inlet plate", offset=z)
    d.c += outline_commands(*hull_outline(corners))
    openings(5)
    d.finish()
    d.extrude(sk, "blower_top", pt)
    fl, fw = PAD_FLOOR
    sk = d.sketch("XY", "Inlet floor", offset=z)
    for px in PADS_X:
        d.rounded((mid + px - fl, -fw), (mid + px + fl, fw), 0.3)
    d.finish()
    d.extrude(sk, "blower_top_floor", 0.02)
    return [(mid + px, 0.0, z + pt) for px in PADS_X]


def drive(d):
    x0 = d.x0
    sy, sz = d.snout_yz()
    iy, iz = d.idler_yz()
    bw, bt = BELT
    fo, fth = PULLEY_FLANGE
    xb = d.belt_x
    back, front = xb + bw / 2 + fth, xb - bw / 2 - fth    # the pulleys' flanges' outer faces

    # The snout, from the gear cover to the pulley, and the collar at its nose.
    cover_face = x0 - FRONT_COVER[0]
    nose = back + SNOUT_COLLAR[1]
    d.cone("blower_snout", (cover_face, sy, sz), (-1, 0, 0), SNOUT_R[0], SNOUT_R[1], cover_face - nose)
    d.cylinder("blower_snout_collar", (nose, sy, sz), (-1, 0, 0), 2 * SNOUT_COLLAR[0], SNOUT_COLLAR[1])

    def flanged(name, yz, r):
        """A pulley under the belt with a flange each side, turned about its axis."""
        rim = r + bt + fo
        d.revolve(name, p3(0.0, yz), (1, 0, 0), (0, 0, 1),
                  [(back, 0.0), (back, rim), (back - fth, rim), (back - fth, r),
                   (front + fth, r), (front + fth, rim), (front, rim), (front, 0.0)])

    flanged("blower_pulley", (sy, sz), BLOWER_PULLEY_R)
    d.cylinder("blower_pulley_nut", (front, sy, sz), (-1, 0, 0), 1.0, 0.45)

    # The idler, plain under the belt's back, on a bracket clamped round the snout behind it.
    d.revolve("blower_idler", p3(0.0, (iy, iz)), (1, 0, 0), (0, 0, 1),
              [(back - fth, 0.0), (back - fth, IDLER_R + 0.12), (back - fth - 0.12, IDLER_R),
               (front + fth + 0.12, IDLER_R), (front + fth, IDLER_R + 0.12), (front + fth, 0.0)])
    d.cylinder("blower_idler_axle", (front + fth, iy, iz), (-1, 0, 0), 0.9, 0.3)
    th, rs, ri = IDLER_BRACKET
    sk = yz_sketch(d, back + 0.05, "Idler bracket")
    d.c += outline_commands(*hull_outline([((sy, sz), rs), ((iy, iz), ri)]))
    d.finish()
    d.extrude(sk, "blower_idler_bracket", th)

    # The crank's pulley on a hub out from the engine's own pulley's front.
    flanged("blower_crank_pulley", (0.0, 0.0), CRANK_DRIVE_R)
    d.cylinder("blower_crank_hub", (d.crank_front + 0.02, 0.0, 0.0), (-1, 0, 0), 2 * CRANK_HUB_R,
               d.crank_front + 0.02 - back)
    d.cylinder("blower_crank_bolt", (front, 0.0, 0.0), (-1, 0, 0), 1.1, 0.5)

    # The belt, outside all three.
    ring = [((0.0, 0.0), CRANK_DRIVE_R), ((iy, iz), IDLER_R), ((sy, sz), BLOWER_PULLEY_R)]
    sk = yz_sketch(d, xb, "Belt")
    d.c += outline_commands(*hull_outline(ring))
    d.c += outline_commands(*hull_outline([(c, r + bt) for c, r in ring]), first=len(ring) + 1)
    d.finish()
    d.extrude(sk, "blower_belt", bw, "symmetric")


def flanges(d, M, bolts, bolt_xs, inset=0.1, front_right=None):
    """The intake's flange on each head's intake face as the engine's own intake has it
    (module M's numbers), the bolts down through it on round bosses; bolt_xs(s) are the
    bolts' places along bank s, `bolts` the bolt bodies' name."""
    t0, t1, thick = M.INTAKE_FLANGE
    for s in (1, -1):
        f0, up, n = M.intake_face(s)
        xa, xb = M.bank_x(s, -M.HEAD_HALF) + inset, M.bank_x(s, M.HEAD_HALF) - inset
        if s == 1 and front_right is not None:
            xa = front_right
        sk, to2d = d.plane(p3(0.0, f0), (1, 0, 0), v3(n), f"Intake flange {s}")
        d.rounded(to2d(p3(xa, f0 + t0 * up)), to2d(p3(xb, f0 + t1 * up)), 0.3)
        d.finish()
        d.extrude(sk, f"intake_manifold_flange_{s}", thick)
        bolt = f0 + M.INTAKE_BOLT_T * up + thick * n
        xs = [x for x in bolt_xs(s) if xa + 0.5 < x < xb - 0.5]
        sk, to2d = d.plane(p3(0.0, bolt), (1, 0, 0), v3(n), f"Intake bolt bosses {s}")
        for x in xs:
            d.circle(to2d(p3(x, bolt)), 0.48)
        d.finish()
        d.extrude(sk, f"intake_manifold_bolt_bosses_{s}", 0.15, start_offset=inch(-0.05))
        sk, to2d = d.plane(p3(0.0, bolt), (1, 0, 0), v3(n), f"Intake bolts {s}")
        for x in xs:
            d.hexagon(to2d(p3(x, bolt)), 0.5)
        d.finish()
        d.extrude(sk, f"{bolts}_{s}", 0.28, start_offset=inch(0.1))


def floor(d, outline, z0, z1):
    sk = d.sketch("XY", "Intake floor", offset=z0)
    d.poly(outline)
    d.finish()
    d.extrude(sk, "intake_manifold", z1 - z0)


def water_outlet(d, x, y, z):
    """The water outlet out of the box's front at (x, y, z), its neck forward and a little up."""
    d.cylinder("thermostat_housing", (x, y, z), (-1, 0, 0), 2.3, 1.3)
    d.cylinder("thermostat_flange", (x - 1.3, y, z), (-1, 0, 0), 2.6, 0.25)
    hose_neck(d, "thermostat_neck", np.array([x - 1.55, y, z]), unit([-1.0, 0.0, 0.25]), 0.775, 0.6, 1.8, 1.2)


def sbc_manifold(d, engine):
    """The small-block's: the L79 intake's floor, flanges and bolts (make_sbc.py), a box up
    from them flaring out under the case, the water outlet on its front, the distributor's
    boss."""
    S = make_sbc
    z0, z1 = S.INTAKE_BASE
    floor(d, ccw([tuple(p) for p in S.INTAKE_FLOOR]), z0, z1)
    flanges(d, S, "intake_manifold_bolts", lambda s: [S.bank_x(s, s * x) for x in S.INTAKE_BOLT_X], inset=0.05)
    x0 = d.x0
    box(d, z1 - 0.1, (x0 + 0.4, x0 + CASE_LEN - 0.4, 3.6), x0)
    d.cylinder("intake_manifold_distributor_boss", (S.DIST[0], S.DIST[1], 10.2), (0, 0, 1), 2.1, 0.8)
    water_outlet(d, x0 + 0.5, S.THERMOSTAT[1], 11.5)


def sbf_manifold(d, engine):
    """The small-block Ford's, on either deck: the dual-plane intake's floor (with its lobe
    round the distributor's boss and the clamp's ear), flanges and bolts (make_sbf.py); a
    box the floor's length behind the distributor, flaring out under the case, which sits
    back on its top; the water outlet on the box's front at the right, where the intake's
    thermostat was; the distributor's boss and the clamp's ear."""
    import make_sbf as F
    F.DECK = F.DECKS[engine["deck"]]
    z0, z1, _, _ = F.intake_levels()
    floor(d, F.floor_outline(), z0, z1)
    flanges(d, F, "intake_bolts", lambda s: [F.bank_x(s, s * x) for x in F.INTAKE_BOLT_X])
    fx0, fx1, hx0 = engine["box"]
    box(d, z1 - 0.1, (fx0, fx1, F.flange_face_y() + 1.0), hx0)
    dx, dy = F.DIST
    d.cylinder("intake_manifold_distributor_boss", (dx, dy, z0 - 0.3), (0, 0, 1), 2.3, z1 - z0 + 0.6)
    bx, by = F.clamp_bolt()
    d.cylinder("intake_manifold_distributor_ear", (bx, by, z0), (0, 0, 1), 0.95, z1 - z0 + 0.75)
    water_outlet(d, fx0 + 0.5, F.THERMOSTAT[1], z1 + 1.3)


def hemi_manifold(d, engine):
    """The Hemi's: the intake's floor (stopping short at the right front for the
    distributor), flanges and bolts (make_hemi.py), and the box the floor's length behind
    the distributor, flaring out under the case, which sits back on its top. The Hemi's
    thermostat is on its water pump."""
    import make_hemi as H
    z0, z1, _, _ = H.intake_levels()
    floor(d, H.floor_outline(), z0, z1)
    flanges(d, H, "intake_bolts", lambda s: [H.bank_x(s, x) for x in H.INTAKE_BOLT_X],
            front_right=H.INTAKE_FRONT_RIGHT)
    fx0, fx1, hx0 = engine["box"]
    box(d, z1 - 0.1, (fx0, fx1, H.flange_face_y() + 1.0), hx0)


def box(d, z_floor, foot, head_front):
    """The manifold's box from the floor (its foot: front and back along x, half wide) up,
    flaring out to its head under the case, from head_front back to the case's back end,
    and the flat top there that the case sits on."""
    x0, zb = d.x0, d.zb
    fx0, fx1, fw = foot
    hx0, hx1 = min(head_front, x0), x0 + CASE_LEN
    hw, ft = CASE_FLANGE
    lower = d.sketch("XY", "Box foot", offset=z_floor)
    d.rounded((fx0, -fw), (fx1, fw), 0.8)
    d.finish()
    upper = d.sketch("XY", "Box head", offset=zb - 0.5)
    d.rounded((hx0, -(hw - 0.3)), (hx1, hw - 0.3), 0.6)
    d.finish()
    d.loft("intake_manifold_box", [lower, upper])
    sk = d.sketch("XY", "Manifold top", offset=zb - 0.5)
    d.rounded((hx0, -hw), (hx1, hw), 0.35)
    d.finish()
    d.extrude(sk, "intake_manifold_top", 0.5)


MANIFOLDS = {"sbc": sbc_manifold, "sbf": sbf_manifold, "hemi": hemi_manifold}


def reduce_obj(src, dst, blender):
    import subprocess
    r = subprocess.run([blender, "-b", "--factory-startup", "--python-expr", BLENDER_REDUCE,
                        "--", src, dst, json.dumps(REDUCE_FACTORS)], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(dst):
        sys.exit(f"blender: {r.stderr.strip() or r.stdout.strip()}")


def finish_for(name):
    for prefix, mat in FINISHES:
        if name.startswith(prefix):
            return mat
    return POLISHED


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("engine", choices=sorted(ENGINES), help="which engine's blower intake")
    ap.add_argument("--sc", help="design file (default resources/engines/blower-ENGINE.sc)")
    ap.add_argument("--glb", help="mesh (default assets/parts/blower-ENGINE.glb)")
    ap.add_argument("--obj", help="also keep SolidCraft's unthinned OBJ here")
    ap.add_argument("--obj-in", help="thin this OBJ, kept with --obj from an earlier run, instead of building again")
    ap.add_argument("--solidcraft", default="solidcraft-cli", help="solidcraft-cli, or the SolidCraft AppImage")
    ap.add_argument("--blender", default="blender", help="Blender, which thins the mesh")
    args = ap.parse_args()
    stem = f"blower-{args.engine}"
    sc = os.path.abspath(args.sc or os.path.join(ROOT, "resources", "engines", stem + ".sc"))
    glb = os.path.abspath(args.glb or os.path.join(ROOT, "assets", "parts", stem + ".glb"))
    tool = shutil.which(args.solidcraft) or args.solidcraft
    if not os.path.exists(tool):
        sys.exit(f"no SolidCraft command line at {args.solidcraft}")
    blender = shutil.which(args.blender) or args.blender
    if not os.path.exists(blender):
        sys.exit(f"no Blender at {args.blender}")

    engine = ENGINES[args.engine]
    d = Blower(engine)
    MANIFOLDS[engine["manifold"]](d, engine)
    case(d)
    pads = top(d)
    drive(d)
    print("pads (in): " + ", ".join(f"({x:.2f}, {y:.2f}, {z:.2f})" for x, y, z in pads))

    with tempfile.TemporaryDirectory() as tmp:
        obj = os.path.join(tmp, "blower.obj")
        d.c.append(cmd("file.export_obj", path=obj))
        script = os.path.join(tmp, "blower.json")
        with open(script, "w") as f:
            json.dump({"commands": d.c}, f)
        os.makedirs(os.path.dirname(sc), exist_ok=True)
        if args.obj_in:
            obj = args.obj_in
        else:
            print(f"building {stem}")
            SolidCraft(tool).run(script, "--save", sc)
        if args.obj and not args.obj_in:
            shutil.copy(obj, args.obj)
        print("thinning the mesh")
        thin = os.path.join(tmp, "thin.obj")
        reduce_obj(obj, thin, blender)
        bodies = read_tris(thin)
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
