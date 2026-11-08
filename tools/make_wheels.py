#!/usr/bin/env python3
"""Build a parametric wheel in SolidCraft and export it as a game GLB.

    python3 tools/make_wheels.py torq                  # 15x7, the stock size
    python3 tools/make_wheels.py torq --size 14x6
    python3 tools/make_wheels.py mag --size 15x8 --backspace 4.5 --set spokes=6 --set lugs=6

Four designs share one rim:

  torq   five spokes, narrow at a small hub and flaring into a wide flat lip
         (American Racing's Torq Thrust, 1965)
  mag    five windows in a dished disc round a flat hub pad (American Racing's
         magnesium drag wheel)
  steel  a stamped steel center with round vents, painted black, under a chrome
         dog-dish hubcap
  c1     the same steel wheel under a full chrome wheel cover, as on the C1 Corvette

The game's tire (make_tires.py) is drawn for a 7 inch rim, so the game's wheels are all
15x7.

Writes resources/wheels/wheel-DESIGN-SIZE.sc, the SolidCraft design (open it in
SolidCraft, change a parameter and it rebuilds), and assets/parts/wheel-DESIGN-SIZE.glb.
Both are LFS files (.gitattributes). Needs SolidCraft's command line: `solidcraft-cli`
on PATH (running the SolidCraft AppImage once puts it there), or --solidcraft with the
path to it or to the AppImage. A wheel takes a minute or two; SolidCraft's kernel is
slow on some sizes (14x6 takes several).

The torq spokes have square front edges for now. Rounding them in SolidCraft 0.30.1
ran over half an hour and then failed on the second window (docs/todo.md).

The design: the wheel axis is SolidCraft's Z, outboard toward +Z, the hub mounting face
on Z = 0. Rim and face are one outline on the YZ plane revolved as a single body
(joining a separate face onto the rim takes SolidCraft minutes), then the lug holes and
the windows are cut along the axis. The windows stop inside the drop well's radius so
the cuts never reach the barrel. Every coordinate is an expression over the design's
parameters, all in inches.

The hubcap or cover of a steel wheel is a second body, "Cap", revolved on its own; the
cuts reach only the wheel.

The GLB: the rim alone (no tire), real size in meters, Y up, the axle along X with the
outboard face toward -X (the cars' wheel mounts turn that side out on both sides of the
car), the origin on the axle midway between the flange tips, which is
where make_tires.py puts the middle of the tire. One mesh per body: the wheel in its
finish (aluminum, or black paint for steel) and a steel wheel's cap in chrome.
"""
import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RIM_PARAMS = [
    # name, expression, comment
    ("rim_dia", "15 in", "bead seat diameter (the tire size)"),
    ("rim_width", "7 in", "width between the flanges (the rim size)"),
    ("backspace", "4 in", "inboard edge to the hub mounting face"),
    ("flange_h", "0.7 in", "flange height above the bead seat"),
    ("flange_t", "0.25 in", "flange thickness"),
    ("flange_curl", "0.3 in", "how far the flange tip leans out past its root"),
    ("wall", "0.22 in", "barrel wall thickness"),
    ("seat_w", "1.0 in", "outboard bead seat width"),
    ("well_d", "0.6 in", "drop well depth"),
    ("well_w", "2.0 in", "drop well floor width"),
    ("center_bore", "3.0 in", "center bore diameter"),
    ("hub_t", "0.9 in", "hub thickness, mounting face to lug seats"),
    ("spokes", "5", "number of spokes"),
    ("lugs", "5", "number of lug holes"),
    ("bolt_circle", "4.5 in", "lug bolt circle diameter"),
    ("lug_hole", "0.6 in", "lug hole diameter"),
    ("lug_angle", "36 deg", "lug pattern rotation from the first spoke"),
]

FACE_PARAMS = {
    "torq": [
        ("lip_w", "1.5 in", "flat outboard lip, flange tip in to its inner edge"),
        ("lip_slope", "0.12 in", "how far the lip's inner edge sits back from the outboard edge"),
        ("lip_round", "0.3 in", "radius rolling the lip's inner edge into the spokes"),
        ("lip_back", "1.3 in", "outboard edge back to where the spokes' backs meet the barrel"),
        ("spoke_bow", "0.25 in", "how far the spoke fronts bow out between hub and lip"),
        ("hub_back_dia", "6.8 in", "diameter where the spokes' backs meet the mounting face"),
        ("spoke_root_dia", "5.6 in", "diameter where the spokes' fronts meet the lug seats"),
        ("cap_dia", "3.2 in", "center cap diameter"),
        ("cap_h", "0.6 in", "center cap side height above the lug seats"),
        ("cap_dome", "0.3 in", "center cap dome height"),
        ("spoke_w_in", "1.2 in", "spoke width at the hub end"),
        ("spoke_w_out", "2.2 in", "spoke width at the lip end"),
        ("win_in", "2.95 in", "radius where the windows start"),
        ("win_gap", "0.05 in", "windows' outer edge in from the lip's inner edge"),
        ("win_r_in", "0.45 in", "window corner radius at the hub end"),
        ("win_r_out", "1.0 in", "window corner radius at the lip end (the spoke flare)"),
    ],
    "mag": [
        ("hub_dia", "6.2 in", "flat hub pad diameter"),
        ("face_lip", "0.45 in", "outboard edge back to the disc front at the barrel"),
        ("spoke_t", "0.75 in", "disc thickness along the axis at the barrel"),
        ("dish", "0.35 in", "how far the disc bows in between hub and barrel"),
        ("spoke_w_in", "2.0 in", "spoke width at the hub end"),
        ("spoke_w_out", "1.5 in", "spoke width at the rim end"),
        ("win_in", "3.3 in", "radius where the windows start"),
        ("win_gap", "0.15 in", "band left between the windows and the drop well radius"),
        ("win_r_in", "0.3 in", "window corner radius at the hub end"),
        ("win_r_out", "0.6 in", "window corner radius at the rim end"),
    ],
}
STEEL_PARAMS = [
    ("disc_t", "0.2 in", "steel thickness of the center disc"),
    ("hub_dia", "6.0 in", "flat hub pad diameter"),
    ("seat_in_dia", "7.2 in", "inner diameter of the flat ring the hubcap sits on"),
    ("seat_dia", "9.6 in", "outer diameter of that ring"),
    ("seat_z", "1.6 in", "how far the ring stands out from the mounting face"),
    ("face_lip", "0.7 in", "outboard edge back to the disc front at the barrel"),
    ("dish", "0.25 in", "how far the disc bows in between the ring and the barrel"),
    ("vents", "6", "number of round vents"),
    ("vent_dia", "1.3 in", "vent diameter"),
    ("vent_circle", "11.2 in", "diameter of the circle the vents sit on"),
    ("vent_angle", "0 deg", "vent pattern rotation"),
    ("cap_t", "0.08 in", "hubcap or cover thickness"),
]
FACE_PARAMS["steel"] = STEEL_PARAMS + [
    ("cap_dia", "9.2 in", "dog-dish hubcap diameter"),
    ("cap_h", "1.0 in", "how far the hubcap's middle stands out from its rim"),
]
FACE_PARAMS["c1"] = STEEL_PARAMS + [
    ("cover_in", "0.1 in", "how far the wheel cover's edge sits inside the bead seat"),
    ("cover_back", "0.15 in", "how far the cover's edge sits back from the flange root"),
    ("cover_ridge", "0.35 in", "height of the cover's outer ridge"),
    ("cover_dome", "0.7 in", "height of the cover's middle over its edge"),
]
UNITLESS = ("spokes", "lugs", "vents")

# Derived values the sketches use, kept as parameters so they show in the
# design's parameter table.
DERIVED = [
    ("R", "rim_dia / 2", "bead seat radius"),
    ("R_tip", "R + flange_h", "flange tip radius"),
    ("zi", "-backspace", "inboard edge"),
    ("zo", "rim_width + 2 * (flange_t + flange_curl) - backspace", "outboard edge"),
    ("z_seat", "zo - flange_t - flange_curl - seat_w", "outboard bead seat, inboard end"),
    ("z_well_out", "z_seat - well_d", "drop well floor, outboard end"),
    ("z_well_in", "z_well_out - well_w", "drop well floor, inboard end"),
    ("R_in", "R - wall", "barrel inside radius"),
    ("spoke_ang", "360 deg / spokes", "angle between spokes"),
]

# The windows' outer radius, always inside the drop well (torq and mag only).
WIN_OUT = {
    "torq": "min(R_tip - lip_w - win_gap, R_in - well_d - 0.05 in)",
    "mag": "R_in - well_d - win_gap",
}


def cmd(_command, **params):
    return {"command": _command, "params": params}


def mid(a, b):
    return f"(({a}) + ({b})) / 2"


class Profile:
    """A closed outline of lines, three-point arcs and splines, chained by reference.

    line(point), arc(through, point) and spline([through...], point) add a segment
    from the point reached so far; a label names the point a segment reaches so a
    corner can be filleted later. close_arc() ends on the start point. After
    commands(), labels maps each label to a curve end.
    """

    def __init__(self, start):
        self.start = start
        self.segs = []
        self.labels = {}

    def line(self, pt, label=None):
        self.segs.append(("line", pt, None, label))

    def arc(self, through, pt, label=None):
        self.segs.append(("arc", pt, through, label))

    def spline(self, through, pt, label=None):
        self.segs.append(("spline", pt, through, label))

    def close_arc(self, through):
        self.segs.append(("arc", None, through, None))

    def close_line(self):
        self.segs.append(("line", None, None, None))

    def commands(self):
        out = []
        nl = na = ns = 0
        first = None
        last = self.start
        chain, chain_labels = [], []

        def flush():
            nonlocal nl, last, first
            if not chain:
                return
            if chain[-1] is None:
                chain[-1] = first
            out.append(cmd("sketch.line", infer=False, points=[last] + chain))
            if first is None:
                first = f"l{nl + 1}.start"
            for i, lab in enumerate(chain_labels):
                if lab:
                    self.labels[lab] = f"l{nl + i + 1}.end"
            nl += len(chain)
            last = f"l{nl}.end"
            chain.clear()
            chain_labels.clear()

        for kind, pt, through, label in self.segs:
            if kind == "line":
                chain.append(pt)
                chain_labels.append(label)
                continue
            flush()
            end = pt if pt is not None else first
            if kind == "spline":
                out.append(cmd("sketch.spline.fit_point", points=[last] + through + [end]))
                ns += 1
                curve = f"s{ns}"
            else:
                out.append(cmd("sketch.arc.three_point", start=last, end=end, through=through))
                na += 1
                curve = f"a{na}"
            if first is None:
                first = f"{curve}.start"
            last = f"{curve}.end"
            if label:
                self.labels[label] = last
        flush()
        return out


def tire_side_and_inside(p):
    """From the outboard flange tip's inner corner round to (R_in, z_seat).

    The flanges are J-shaped: from the bead seat the inner face curls out to a
    rounded tip.
    """
    p.arc([mid("R", "R_tip"), "zo - flange_t - 0.75 * flange_curl"],
          ["R", "zo - flange_t - flange_curl"], label="root_o")
    p.line(["R", "z_seat"])
    p.line(["R - well_d", "z_well_out"])
    p.line(["R - well_d", "z_well_in"])
    p.line(["R", "z_well_in - well_d"])
    p.line(["R", "zi + flange_t + flange_curl"], label="root_i")
    p.arc([mid("R", "R_tip"), "zi + flange_t + 0.75 * flange_curl"], ["R_tip", "zi + flange_t"])
    p.arc(["R_tip + flange_t * 0.45", "zi + flange_t / 2"], ["R_tip", "zi"])
    p.arc([mid("R_in", "R_tip"), "zi + 0.75 * flange_curl"], ["R_in", "zi + flange_curl"])
    p.line(["R_in", "z_well_in - well_d"])
    p.line(["R_in - well_d", "z_well_in"])
    p.line(["R_in - well_d", "z_well_out"])
    p.line(["R_in", "z_seat"])


def torq_profile():
    lip_in = "(R_tip - lip_w)"
    lip_z = "(zo - lip_slope)"
    back_out = "(zo - lip_back)"
    hub_back_r = "(hub_back_dia / 2)"
    root_r = "(spoke_root_dia / 2)"
    cap_r = "(cap_dia / 2)"
    cap_top = "(hub_t + cap_h)"
    floor = "(hub_t - 0.3 in)"

    p = Profile([lip_in, lip_z])
    p.line(["R_tip", "zo"])                           # the flat lip
    p.arc(["R_tip + flange_t * 0.45", "zo - flange_t / 2"], ["R_tip", "zo - flange_t"])
    tire_side_and_inside(p)
    p.line(["R_in", back_out])
    # Spoke backs down to the mounting face.
    p.arc([mid("R_in", hub_back_r), f"{back_out} / 2 + spoke_bow"], [hub_back_r, "0"])
    # Mounting face, center bore recess, domed center cap, lug seats.
    p.line(["center_bore / 2", "0"])
    p.line(["center_bore / 2", floor])
    p.line(["0", floor])
    p.line(["0", f"{cap_top} + cap_dome"])
    p.arc([f"{cap_r} * 0.6", f"{cap_top} + cap_dome * 0.64"], [cap_r, cap_top], label="cap_edge")
    p.line([cap_r, "hub_t"], label="cap_foot")
    p.line([root_r, "hub_t"], label="spoke_root")
    # Spoke fronts up to the lip.
    p.close_arc([mid(root_r, lip_in), f"(hub_t + {lip_z}) / 2 + spoke_bow"])
    fillets = [
        (["root_o", "root_i"], "0.15 in"),
        (["cap_edge"], "0.15 in"),
        (["cap_foot", "spoke_root"], "0.2 in"),
    ]
    return p, fillets


def mag_profile():
    hub_r = "(hub_dia / 2)"
    mid_r = "((hub_dia / 2 + R_in) / 2)"
    front_out = "(zo - face_lip)"
    back_out = "(zo - face_lip - spoke_t)"

    p = Profile(["R_in", front_out])
    p.line(["R_in", "zo - flange_curl"])
    p.arc([mid("R_in", "R_tip"), "zo - 0.75 * flange_curl"], ["R_tip", "zo"])
    p.arc(["R_tip + flange_t * 0.45", "zo - flange_t / 2"], ["R_tip", "zo - flange_t"])
    tire_side_and_inside(p)
    p.line(["R_in", back_out])
    p.arc([mid_r, f"{back_out} / 2 - dish"], [hub_r, "0"])
    p.line(["center_bore / 2", "0"])
    p.line(["center_bore / 2", "hub_t"])
    p.line([hub_r, "hub_t"])
    p.close_arc([mid_r, f"(hub_t + {front_out}) / 2 - dish"])
    return p, [(["root_o", "root_i"], "0.15 in")]


def steel_profile():
    """A pressed steel center: a thin disc from the outboard bead seat down to a flat
    ring the hubcap sits on, then a cone down to the hub pad on the mounting face."""
    hub_r = "(hub_dia / 2)"
    seat_r = "(seat_dia / 2)"
    seat_in = "(seat_in_dia / 2)"
    front_out = "(zo - face_lip)"
    back_out = "(zo - face_lip - disc_t)"

    p = Profile(["R_in", front_out])
    p.line(["R_in", "zo - flange_curl"])
    p.arc([mid("R_in", "R_tip"), "zo - 0.75 * flange_curl"], ["R_tip", "zo"])
    p.arc(["R_tip + flange_t * 0.45", "zo - flange_t / 2"], ["R_tip", "zo - flange_t"])
    tire_side_and_inside(p)
    p.line(["R_in", back_out])
    # Back of the disc, the ring and the cone, to the mounting face.
    p.arc([mid("R_in", seat_r), f"({back_out} + seat_z - disc_t) / 2 - dish"],
          [seat_r, "seat_z - disc_t"])
    p.line([f"{seat_in} + disc_t", "seat_z - disc_t"])
    p.line([hub_r, "0"])
    p.line(["center_bore / 2", "0"])
    p.line(["center_bore / 2", "disc_t"])
    # Front: hub pad, cone, ring, disc out to the barrel.
    p.line([f"{hub_r} - disc_t", "disc_t"])
    p.line([seat_in, "seat_z"])
    p.line([seat_r, "seat_z"])
    p.close_arc([mid("R_in", seat_r), f"({front_out} + seat_z) / 2 - dish"])
    return p, [(["root_o", "root_i"], "0.15 in")]


def dog_dish_profile():
    """A shallow chrome dome sitting on the ring, its edge turned down."""
    r = "(cap_dia / 2)"
    top = "(seat_z + cap_h)"
    p = Profile(["0", top])
    p.arc([f"{r} * 0.6", f"seat_z + cap_h * 0.72"], [r, "seat_z + 0.15 in"])
    p.line([r, "seat_z + 0.02 in"])
    p.line([f"{r} - cap_t", "seat_z + 0.02 in"])
    p.arc([f"{r} * 0.6 - cap_t", f"seat_z + cap_h * 0.72 - cap_t"], ["0", f"{top} - cap_t"])
    p.close_line()
    return p


def wheel_cover_profile():
    """A full wheel cover: its edge clipped in at the outboard bead seat, an outer
    ridge, a dished band and a domed middle."""
    r = "(R - cover_in)"
    edge = "(zo - flange_t - flange_curl - cover_back)"

    def front(dz):
        t = f" - {dz}" if dz else ""
        return [
            ["0", f"{edge} + cover_dome{t}"],
            [f"{r} * 0.22", f"{edge} + cover_dome * 0.75{t}"],
            [f"{r} * 0.55", f"{edge} - 0.2 in{t}"],
            [f"{r} - 0.7 in", f"{edge} + cover_ridge{t}"],
            [r, f"{edge}{t}"],
        ]
    f, b = front(None), front("cap_t")
    p = Profile(f[0])
    p.spline(f[1:-1], f[-1])
    p.line(b[-1])
    p.spline(b[-2:0:-1], b[0])
    p.close_line()
    return p


def build(design, values):
    """The command script for the design; values overrides parameter expressions by name."""
    c = [cmd("document.units", units="in")]
    derived = DERIVED + ([("win_out", WIN_OUT[design], "radius where the windows end")]
                         if design in WIN_OUT else [])
    for name, expr, comment in RIM_PARAMS + FACE_PARAMS[design] + derived:
        extra = {"unit": ""} if name in UNITLESS else {}
        c.append(cmd("parameters.add", name=name, expression=values.get(name, expr),
                     comment=comment, **extra))

    p, fillets = {"torq": torq_profile, "mag": mag_profile,
                  "steel": steel_profile, "c1": steel_profile}[design]()
    c.append(cmd("sketch.create", plane="YZ", name="Wheel profile"))
    c += p.commands()
    for labels, radius in fillets:
        c.append(cmd("sketch.fillet", points=[p.labels[l] for l in labels], radius=radius))
    if design == "torq":
        # The lip's inner edge, where the closing arc meets the flat lip.
        c.append(cmd("sketch.fillet", point="l1.start", radius="lip_round"))
    c.append(cmd("sketch.finish"))
    c.append(cmd("solid.revolve", sketch="Wheel profile", axis="y", name="Revolve",
                 body_name="Wheel"))

    # Lug holes, cut before the windows while the body is still simple.
    c.append(cmd("sketch.create", plane="XY", name="Lug holes"))
    c.append(cmd("sketch.circle.center",
                 center=["bolt_circle / 2 * cos(lug_angle)", "bolt_circle / 2 * sin(lug_angle)"],
                 diameter="lug_hole"))
    c.append(cmd("sketch.pattern.circular", entities=["c1"], center=[0, 0], count="lugs"))
    c.append(cmd("sketch.finish"))
    c.append(cmd("solid.extrude", sketch="Lug holes", through_all=True, direction="symmetric",
                 operation="cut", targets=["Wheel"], name="Lug cuts"))
    if design not in WIN_OUT:
        return c + steel_extras(design)

    # Windows: one between the first spoke (on +X) and the next, patterned round by
    # the spoke count. Each side runs parallel to its spoke's center line, half the
    # spoke's width off it.
    def side(r, w, rotated):
        x = f"sqrt({r} * {r} - {w} * {w} / 4)"
        if not rotated:
            return [x, f"{w} / 2"]
        return [f"{x} * cos(spoke_ang) + {w} / 2 * sin(spoke_ang)",
                f"{x} * sin(spoke_ang) - {w} / 2 * cos(spoke_ang)"]
    c.append(cmd("sketch.create", plane="XY", name="Windows"))
    c.append(cmd("sketch.line", infer=False, points=[
        side("win_in", "spoke_w_in", False), side("win_out", "spoke_w_out", False)]))
    c.append(cmd("sketch.arc.center_point", center=[0, 0], start="l1.end",
                 end=side("win_out", "spoke_w_out", True)))
    c.append(cmd("sketch.line", infer=False, points=["a1.end", side("win_in", "spoke_w_in", True)]))
    c.append(cmd("sketch.arc.center_point", center=[0, 0], start="l1.start", end="l2.end"))
    c.append(cmd("sketch.fillet", points=["l1.start", "l2.end"], radius="win_r_in"))
    c.append(cmd("sketch.fillet", points=["l1.end", "l2.start"], radius="win_r_out"))
    c.append(cmd("sketch.pattern.circular",
                 entities=["l1", "a1", "l2", "a2", "a3", "a4", "a5", "a6"],
                 center=[0, 0], count="spokes"))
    c.append(cmd("sketch.finish"))
    c.append(cmd("solid.extrude", sketch="Windows", through_all=True, direction="symmetric",
                 operation="cut", targets=["Wheel"], name="Window cuts"))
    return c


def steel_extras(design):
    """A steel wheel's vents and its hubcap or cover."""
    c = [cmd("sketch.create", plane="XY", name="Vents")]
    c.append(cmd("sketch.circle.center",
                 center=["vent_circle / 2 * cos(vent_angle)", "vent_circle / 2 * sin(vent_angle)"],
                 diameter="vent_dia"))
    c.append(cmd("sketch.pattern.circular", entities=["c1"], center=[0, 0], count="vents"))
    c.append(cmd("sketch.finish"))
    c.append(cmd("solid.extrude", sketch="Vents", through_all=True, direction="symmetric",
                 operation="cut", targets=["Wheel"], name="Vent cuts"))
    cap = dog_dish_profile() if design == "steel" else wheel_cover_profile()
    c.append(cmd("sketch.create", plane="YZ", name="Cap profile"))
    c += cap.commands()
    c.append(cmd("sketch.finish"))
    c.append(cmd("solid.revolve", sketch="Cap profile", axis="y", name="Cap", body_name="Cap",
                 operation="new"))
    return c


class SolidCraft:
    def __init__(self, path):
        self.path = path
        self.env = dict(os.environ)
        if path.endswith(".AppImage"):
            # The AppImage runs its command line with this set; the other keeps it
            # from installing a desktop entry.
            self.env["SOLIDCRAFT_APPIMAGE_CLI"] = "1"
            self.env["SOLIDCRAFT_NO_DESKTOP_INTEGRATION"] = "1"

    def run(self, script, *args):
        r = subprocess.run([self.path, "run", script, *args], env=self.env,
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"solidcraft-cli run {os.path.basename(script)}: {r.stderr.strip()}")


def read_obj(path):
    """The bodies of an OBJ whose faces are triangles v//vn: {name: (positions, normals,
    indices)}, in the order they come."""
    v, vn, groups = [], [], {}
    corners = None
    with open(path) as f:
        for line in f:
            if line.startswith("v "):
                v.append([float(t) for t in line.split()[1:4]])
            elif line.startswith("vn "):
                vn.append([float(t) for t in line.split()[1:4]])
            elif line.startswith("o "):
                corners = groups.setdefault(line[2:].strip(), [])
            elif line.startswith("f "):
                if corners is None:
                    corners = groups.setdefault("mesh", [])
                for t in line.split()[1:4]:
                    a, _, b = t.split("/")
                    corners.append((int(a) - 1, int(b) - 1))
    v, vn = np.array(v), np.array(vn)
    bodies = {}
    for name, cs in groups.items():
        unique, index = {}, []
        for c in cs:
            index.append(unique.setdefault(c, len(unique)))
        pairs = np.array(list(unique), dtype=np.int64)
        bodies[name] = (v[pairs[:, 0]], vn[pairs[:, 1]], np.array(index, dtype=np.uint32))
    return bodies


# SolidCraft (x, y, z) in mm, axle along z, outboard +z  ->  glTF (-z, y, x) in m, axle
# along x, outboard -x.
TO_GAME = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], dtype=float)


def to_game(bodies):
    return {n: (p @ TO_GAME * 0.001, nr @ TO_GAME, i) for n, (p, nr, i) in bodies.items()}


ALUMINUM = {"name": "aluminum", "pbrMetallicRoughness": {
    "baseColorFactor": [0.8, 0.8, 0.8, 1], "metallicFactor": 1.0, "roughnessFactor": 0.3}}
BLACK_PAINT = {"name": "black paint", "pbrMetallicRoughness": {
    "baseColorFactor": [0.03, 0.03, 0.03, 1], "metallicFactor": 0.2, "roughnessFactor": 0.4}}
CHROME = {"name": "chrome", "pbrMetallicRoughness": {
    "baseColorFactor": [0.9, 0.9, 0.9, 1], "metallicFactor": 1.0, "roughnessFactor": 0.08}}
FINISH = {"torq": ALUMINUM, "mag": ALUMINUM, "steel": BLACK_PAINT, "c1": BLACK_PAINT}


def write_glb(path, parts):
    """parts: [(name, positions, normals, indices, material)], one node and mesh each."""
    blobs, accessors, views, nodes, meshes, materials = [], [], [], [], [], []
    offset = 0

    def add(data, target, acc):
        nonlocal offset
        b = data.tobytes()
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(b), "target": target})
        blobs.append(b)
        offset += len(b)
        acc["bufferView"] = len(views) - 1
        accessors.append(acc)
        return len(accessors) - 1

    for name, pos, nrm, index, material in parts:
        pos = pos.astype(np.float32)
        nrm = (nrm / np.linalg.norm(nrm, axis=1, keepdims=True)).astype(np.float32)
        a_pos = add(pos, 34962, {"componentType": 5126, "count": len(pos), "type": "VEC3",
                                 "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()})
        a_nrm = add(nrm, 34962, {"componentType": 5126, "count": len(nrm), "type": "VEC3"})
        a_idx = add(index.astype(np.uint32), 34963,
                    {"componentType": 5125, "count": len(index), "type": "SCALAR"})
        if material not in materials:
            materials.append(material)
        meshes.append({"name": name, "primitives": [{
            "attributes": {"POSITION": a_pos, "NORMAL": a_nrm}, "indices": a_idx,
            "material": materials.index(material)}]})
        nodes.append({"mesh": len(meshes) - 1, "name": name})
    gltf = {
        "asset": {"version": "2.0", "generator": "tools/" + os.path.basename(sys.argv[0])},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "materials": materials,
        "meshes": meshes,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": offset}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    bin_ = b"".join(blobs)
    bin_ += b"\0" * (-len(bin_) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(bin_), 0x004E4942) + bin_)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("design", choices=sorted(FACE_PARAMS))
    ap.add_argument("--size", default="15x7", help="diameter x width in inches (default 15x7)")
    ap.add_argument("--backspace", type=float,
                    help="inches (default: half the width plus half an inch, 4 for a 7)")
    ap.add_argument("--set", action="append", default=[], metavar="NAME=EXPR",
                    help="any other parameter, e.g. spokes=6 or lip_w='1.2 in'")
    ap.add_argument("--sc", help="design file (default resources/wheels/wheel-DESIGN-SIZE.sc)")
    ap.add_argument("--glb", help="mesh (default assets/parts/wheel-DESIGN-SIZE.glb)")
    ap.add_argument("--solidcraft", default="solidcraft-cli",
                    help="solidcraft-cli, or the SolidCraft AppImage")
    args = ap.parse_args()

    dia, width = (float(t) for t in args.size.lower().split("x"))
    backspace = args.backspace if args.backspace is not None else width / 2 + 0.5
    values = {"rim_dia": f"{dia:g} in", "rim_width": f"{width:g} in",
              "backspace": f"{backspace:g} in"}
    known = {n for n, _, _ in RIM_PARAMS + FACE_PARAMS[args.design]}
    for s in args.set:
        name, _, expr = s.partition("=")
        if name not in known:
            sys.exit(f"{args.design} has no parameter {name}")
        values[name] = expr
    stem = f"wheel-{args.design}-{args.size.lower()}"
    sc = os.path.abspath(args.sc or os.path.join(ROOT, "resources", "wheels", stem + ".sc"))
    glb = os.path.abspath(args.glb or os.path.join(ROOT, "assets", "parts", stem + ".glb"))
    tool = shutil.which(args.solidcraft) or args.solidcraft
    if not os.path.exists(tool):
        sys.exit(f"no SolidCraft command line at {args.solidcraft}")
    scraft = SolidCraft(tool)

    with tempfile.TemporaryDirectory() as tmp:
        commands = build(args.design, values)
        obj = os.path.join(tmp, "wheel.obj")
        commands.append(cmd("file.export_obj", path=obj))
        script = os.path.join(tmp, "wheel.json")
        json.dump({"commands": commands}, open(script, "w"))
        os.makedirs(os.path.dirname(sc), exist_ok=True)
        print(f"building {stem}")
        scraft.run(script, "--save", sc)
        bodies = to_game(read_obj(obj))
    # Center on the rim: midway between the flange tips, the wheel's axial extremes.
    wheel = bodies["Wheel"][0]
    shift = np.array([(wheel[:, 0].min() + wheel[:, 0].max()) / 2, 0.0, 0.0])
    parts = [(f"{stem}-{n.lower()}", p - shift, nr, i,
              FINISH[args.design] if n == "Wheel" else CHROME) for n, (p, nr, i) in bodies.items()]
    write_glb(glb, parts)
    print(f"{os.path.relpath(sc, ROOT)}\n{os.path.relpath(glb, ROOT)}: "
          f"{sum(len(i) for *_, i, _ in parts) // 3} triangles, "
          f"{(wheel[:, 1].max() - wheel[:, 1].min()) / 0.0254:.2f} in across, "
          f"{(wheel[:, 0].max() - wheel[:, 0].min()) / 0.0254:.2f} in wide")


if __name__ == "__main__":
    main()
