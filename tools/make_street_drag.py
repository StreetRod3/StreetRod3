#!/usr/bin/env python3
"""Bake Street Rod 2's cruise drag race (race kind 1, lines 200 to 380) into a .trk file.

Runs the SR2 port's own course_town and course_build from the EXE's starting seed, reads the
track frame, and writes assets/tracks/street_drag.trk. tools/ is gitignored; the .trk is what
ships.

    python3 tools/make_street_drag.py ~/Code/SRDecomp/sr2/src/game assets/tracks/street_drag.trk
"""
import json
import pathlib
import subprocess
import sys
import tempfile

LINE_M = 5.0            # from the speed table and the road frame's pace: 15.5 to 17 ft a line
ROAD_WIDTH_M = 8.0      # SR2's 1800 across; the car ratio says 5.4 to 7 m, 8 leaves room to steer
UNIT_M = ROAD_WIDTH_M / 1800.0
VERGE_M = 400 * UNIT_M  # ROWS_VERGE: how far past the road's edge the verge is
FAR_M = 8.0             # "halfway to the clip's edge", which has no real distance
HEIGHT_M = 0.4          # height word to meters; SR2's only shifts the view, so set by eye
START, FINISH, LAST = 200, 380, 459
RUN_IN = 12             # lines of scenery behind the start, matching _STREET_RUN_IN_M

DUMP = r'''
#include <stdio.h>
#include <string.h>
#include "course.h"
#include "rand.h"
static unsigned short f[COURSE_FRAME_WORDS];
#define AT(b,l) f[((b)+2*(l))/2]
int main(void){
  game_rng r; game_rng_init(&r,NULL); r.seed=GAME_RNG_SEED;
  course_state cs; memset(&cs,0,sizeof cs); town_pages tp; memset(&tp,0,sizeof tp);
  course_town(f,&cs,0,1,&r,&tp); course_build(f,&cs,0,COURSE_RANDOM,&r);
  for(int l=%d;l<=%d;l++) printf("%%d %%d %%u %%u %%u\n",l,(short)AT(COURSE_HEIGHT,l),
    AT(COURSE_EDGE,l),AT(COURSE_WALL_LEFT,l),AT(COURSE_WALL_RIGHT,l));
  return 0; }
''' % (START - RUN_IN, LAST + 3)


def read_frame(game_dir):
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "dump.c"
        exe = pathlib.Path(tmp) / "dump"
        src.write_text(DUMP)
        subprocess.run(["gcc", "-std=gnu11", "-w", f"-I{game_dir}", str(src), f"{game_dir}/course.c",
                        f"{game_dir}/rand.c", "-o", str(exe)], check=True)
        out = subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout
    lines = {}
    for row in out.splitlines():
        line, height, edge, left, right = (int(v) for v in row.split())
        lines[line] = (height, edge, left, right)
    return lines


def road_nodes(lines):
    """A node wherever the height turns: the tops, the bottoms, and where a rise leaves level
    road. SR2's heights run straight between those, which would make sharp points in 3D, so the
    track's curve rounds them instead."""
    wanted = {START, FINISH}
    for line in range(START + 1, FINISH):
        before = lines[line][0] - lines[line - 1][0]
        after = lines[line + 1][0] - lines[line][0]
        if (before > 0) != (after > 0) or (before < 0) != (after < 0):
            wanted.add(line)
    nodes = []
    for index, line in enumerate(sorted(wanted)):
        height = lines[line][0] if line != FINISH else 0
        node = {"id": index + 1, "x": 0, "y": (line - START) * LINE_M}
        if height != 0:
            node["z"] = round(height * HEIGHT_M, 3)
        if line == START:
            node["type"] = "start"
        elif line == FINISH:
            node["type"] = "finish"
        nodes.append(node)
    roads = [{"from": a["id"], "to": b["id"], "width": ROAD_WIDTH_M} for a, b in zip(nodes, nodes[1:])]
    return nodes, roads


def scenery(lines):
    items = []
    taken = set()

    def put(kind, x, line_at):
        y = (line_at - START) * LINE_M
        # SR2 can draw two sprites on one spot. Two trees in one place would just merge.
        if kind.endswith("tree") or kind == "pole":
            while (round(x, 2), y) in taken:
                y += 2.0
            taken.add((round(x, 2), y))
        items.append({"kind": kind, "x": round(x, 2), "y": y})

    edge_x = ROAD_WIDTH_M / 2.0
    for line in range(START - RUN_IN, LAST + 1):
        _, edge, left, right = lines[line]
        racing = line < FINISH
        if edge & 0x8:
            put("dash", 0.0, line)
        if edge & 0x10 and line == FINISH - 1:
            put("finish", 0.0, line)
        if edge & 0x8000 and racing:
            put("gantry", 0.0, line)
        if edge & 0x2:     # driver's right is -X
            put("pole", -(edge_x + VERGE_M - ROAD_WIDTH_M / 8.0), line)
        for side, wall in ((1.0, left), (-1.0, right)):
            is_left = side > 0.0
            # wall & 0x1 is the shoulder, a sprite every fourth line for want of more. A street
            # track draws its shoulder whole, so it isn't listed here.
            if wall & 0x100:
                if wall & 0x200:
                    put("tree", side * (edge_x + 2.0 * VERGE_M), line + (2 if is_left else 3))
                else:
                    put("tree", side * (edge_x + VERGE_M), line)
            if wall & 0x80:
                if wall & 0x2:
                    put("big_tree", side * (edge_x + FAR_M), line + 3)
                elif is_left:
                    put("big_tree", side * (edge_x + VERGE_M), line)
                else:
                    put("big_tree", side * (edge_x + 1.5 * VERGE_M), line)
            if wall & 0x40:
                put("bare_tree", side * (edge_x + VERGE_M), line)
            if wall & 0xc and racing:
                put("dark_streak", side * edge_x, line)
    return items


def main():
    lines = read_frame(sys.argv[1])
    nodes, roads = road_nodes(lines)
    items = scenery(lines)
    out = ['{', '  "name": "Street drag",', '  "style": "street",', '  "nodes": [']
    out.append(",\n".join("    " + json.dumps(n) for n in nodes))
    out += ['  ],', '  "roads": [']
    out.append(",\n".join("    " + json.dumps(r) for r in roads))
    out += ['  ],', '  "scenery": [']
    out.append(",\n".join("    " + json.dumps(i) for i in items))
    out += ['  ]', '}', '']
    pathlib.Path(sys.argv[2]).write_text("\n".join(out))
    kinds = {}
    for item in items:
        kinds[item["kind"]] = kinds.get(item["kind"], 0) + 1
    print(len(nodes), "nodes", kinds)


main()
