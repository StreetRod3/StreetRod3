#!/usr/bin/env python3
"""Build a parametric tire in SolidCraft and export it as a game GLB.

    python3 tools/make_tires.py                           # 225/60R15, the game's size
    python3 tools/make_tires.py 205/70R14 --rim-width 6 --set grooves=5

The size is the P-metric one on the sidewall: section width in mm / aspect ratio
(sidewall height as a percentage of the width) R rim diameter in inches. The tire's
beads sit on the rim's bead seats rim-width apart and its lower sidewalls follow
make_wheels.py's J flanges (same flange_h and flange_curl), so it fits those wheels.
Above the flanges the sidewall bulges out to the section width, rounds over a
shoulder and crosses a crowned tread with circumferential grooves (a rib tread, as
on 1960s tires).

Writes resources/tires/tire-WIDTH-ASPECTrDIA.sc, the SolidCraft design (change a
parameter and it rebuilds), and assets/parts/tire-WIDTH-ASPECTrDIA.glb, both LFS
files. Needs SolidCraft's command line, as make_wheels.py does.

The GLB: one rubber mesh, real size in meters, Y up, the axle along X, the origin on
the axle midway between the beads. A make_wheels.py wheel's GLB has its origin at the
hub mounting face, so on that wheel the tire's origin goes at
x = rim_width / 2 + flange_t + flange_curl - backspace (0.05 in, 1.27 mm, for the
stock 15x7 with 4 in backspacing).
"""
import argparse
import json
import os
import re
import shutil
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_wheels import ROOT, Profile, SolidCraft, cmd, mid, read_obj, write_glb  # noqa: E402

PARAMS = [
    # name, expression, comment
    ("section_w", "225 mm", "section width, sidewall to sidewall"),
    ("aspect", "60", "sidewall height as a percentage of the section width"),
    ("rim_dia", "15 in", "rim diameter"),
    ("rim_width", "7 in", "rim width between the flanges, where the beads sit"),
    ("flange_h", "0.7 in", "the wheel's flange height above the bead seat"),
    ("flange_curl", "0.3 in", "how far the wheel's flange tip leans out past its root"),
    ("bulge", "0.5", "where the sidewall is widest, as a fraction of its height"),
    ("tread_w", "section_w * 0.72", "tread width across the shoulders"),
    ("crown_drop", "0.3 in", "how far the tread's edges sit below its center"),
    ("shoulder_r", "0.45 in", "shoulder radius between sidewall and tread"),
    ("grooves", "4", "number of circumferential tread grooves"),
    ("groove_w", "0.3 in", "groove width"),
    ("groove_d", "0.3 in", "groove depth"),
]
UNITLESS = ("aspect", "bulge", "grooves")

DERIVED = [
    ("h", "section_w * aspect / 100", "sidewall height"),
    ("R", "rim_dia / 2", "bead seat radius"),
    ("Ro", "R + h", "outside radius"),
    ("W2", "rim_width / 2", "bead heel, either side of the middle"),
]

RUBBER = {"name": "rubber", "pbrMetallicRoughness": {
    "baseColorFactor": [0.03, 0.03, 0.03, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}}


def tire_profile():
    """Half a cross section each side of the middle, on the YZ plane (r, z)."""
    def side(sign):
        s = "" if sign > 0 else "-"
        flange_mid = ["R + flange_h / 2", f"{s}(W2 + 0.25 * flange_curl)"]
        flange_tip = ["R + flange_h", f"{s}(W2 + flange_curl)"]
        widest = ["R + bulge * h", f"{s}(section_w / 2)"]
        upper = ["R + (bulge + 1) / 2 * h", f"{s}(section_w / 2 - (section_w - tread_w) / 6)"]
        # The shoulder: a quarter round from the sidewall's top to the tread's edge.
        side_top = ["Ro - crown_drop - shoulder_r", f"{s}(tread_w / 2)"]
        round_mid = ["Ro - crown_drop - shoulder_r * (1 - 0.7071)",
                     f"{s}(tread_w / 2 - shoulder_r * (1 - 0.7071))"]
        tread_edge = ["Ro - crown_drop", f"{s}(tread_w / 2 - shoulder_r)"]
        return flange_mid, flange_tip, widest, upper, side_top, round_mid, tread_edge

    fm, ft, wd, up, st, rm, te = side(+1)
    fm_, ft_, wd_, up_, st_, rm_, te_ = side(-1)
    p = Profile(["R", "-W2"])
    p.line(["R", "W2"])                       # on the bead seats
    p.arc(fm, ft)                             # up the flange's inner face
    p.spline([wd, up], st)                    # the sidewall
    p.arc(rm, te)
    p.arc(["Ro", "0"], te_)                   # the crowned tread
    p.arc(rm_, st_)
    p.spline([up_, wd_], ft_)
    p.close_arc(fm_)
    return p


def build(values):
    c = [cmd("document.units", units="in")]
    for name, expr, comment in PARAMS + DERIVED:
        extra = {"unit": ""} if name in UNITLESS else {}
        c.append(cmd("parameters.add", name=name, expression=values.get(name, expr),
                     comment=comment, **extra))

    p = tire_profile()
    c.append(cmd("sketch.create", plane="YZ", name="Tire profile"))
    c += p.commands()
    c.append(cmd("sketch.finish"))
    c.append(cmd("solid.revolve", sketch="Tire profile", axis="y", name="Revolve",
                 body_name="Tire"))

    # Grooves: the first one tread_w / (grooves + 1) in from one edge, repeated across.
    pitch = "tread_w / (grooves + 1)"
    z0 = f"-tread_w / 2 + {pitch}"
    c.append(cmd("sketch.create", plane="YZ", name="Grooves"))
    c.append(cmd("sketch.rectangle.two_point",
                 p0=["Ro - groove_d", f"{z0} - groove_w / 2"],
                 p1=["Ro + 0.5 in", f"{z0} + groove_w / 2"]))
    c.append(cmd("sketch.pattern.rectangular", entities=["l1", "l2", "l3", "l4"],
                 count="grooves", spacing=pitch, dir=[0, 1]))
    c.append(cmd("sketch.finish"))
    c.append(cmd("solid.revolve", sketch="Grooves", axis="y", operation="cut",
                 targets=["Tire"], name="Groove cuts"))
    return c


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("size", nargs="?", default="225/60R15",
                    help="P-metric size (default 225/60R15)")
    ap.add_argument("--rim-width", type=float, default=7.0,
                    help="inches between the rim's flanges (default 7)")
    ap.add_argument("--set", action="append", default=[], metavar="NAME=EXPR",
                    help="any other parameter, e.g. grooves=5 or crown_drop='0.2 in'")
    ap.add_argument("--sc", help="design file (default resources/tires/tire-SIZE.sc)")
    ap.add_argument("--glb", help="mesh (default assets/parts/tire-SIZE.glb)")
    ap.add_argument("--solidcraft", default="solidcraft-cli",
                    help="solidcraft-cli, or the SolidCraft AppImage")
    args = ap.parse_args()

    m = re.fullmatch(r"(\d+)/(\d+)R(\d+(?:\.\d+)?)", args.size.upper())
    if not m:
        sys.exit(f"{args.size}: expected a size like 235/75R15")
    width, aspect, dia = m.groups()
    values = {"section_w": f"{width} mm", "aspect": aspect, "rim_dia": f"{dia} in",
              "rim_width": f"{args.rim_width:g} in"}
    known = {n for n, _, _ in PARAMS}
    for s in args.set:
        name, _, expr = s.partition("=")
        if name not in known:
            sys.exit(f"the tire has no parameter {name}")
        values[name] = expr
    stem = f"tire-{width}-{aspect}r{dia}"
    sc = os.path.abspath(args.sc or os.path.join(ROOT, "resources", "tires", stem + ".sc"))
    glb = os.path.abspath(args.glb or os.path.join(ROOT, "assets", "parts", stem + ".glb"))
    tool = shutil.which(args.solidcraft) or args.solidcraft
    if not os.path.exists(tool):
        sys.exit(f"no SolidCraft command line at {args.solidcraft}")
    scraft = SolidCraft(tool)

    with tempfile.TemporaryDirectory() as tmp:
        commands = build(values)
        obj = os.path.join(tmp, "tire.obj")
        commands.append(cmd("file.export_obj", path=obj))
        script = os.path.join(tmp, "tire.json")
        json.dump({"commands": commands}, open(script, "w"))
        os.makedirs(os.path.dirname(sc), exist_ok=True)
        print(f"building {stem}")
        scraft.run(script, "--save", sc)
        pos, nrm, index = read_obj(obj)
    # SolidCraft (x, y, z) in mm, axle along z  ->  glTF (z, y, -x) in m, axle along x.
    swap = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], dtype=float)
    pos = pos @ swap * 0.001
    nrm = nrm @ swap
    write_glb(glb, stem, pos, nrm, index, RUBBER)
    print(f"{os.path.relpath(sc, ROOT)}\n{os.path.relpath(glb, ROOT)}: {len(index) // 3} triangles, "
          f"{(pos[:, 1].max() - pos[:, 1].min()) * 1000:.1f} mm across, "
          f"{(pos[:, 0].max() - pos[:, 0].min()) * 1000:.1f} mm wide")


if __name__ == "__main__":
    main()
