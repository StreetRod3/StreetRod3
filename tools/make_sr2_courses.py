#!/usr/bin/env python3
"""Bake Street Rod 2's Mulholland drive (race kind 0x10, lines 370 to 960, ten courses) and its
Aqueduct race (race kind 8, lines 8 to 342 of the strip's table) into .trk files.

Runs the SR2 port's own course_town and course_build from the EXE's starting seed, reads the track
frame, and writes assets/tracks/mulholland_0.trk to mulholland_9.trk and aqueduct.trk. tools/ is
gitignored; the .trk files are what ship.

    python3 tools/make_sr2_courses.py ~/Code/SRDecomp/sr2/src/game assets/tracks
"""
import json
import math
import pathlib
import subprocess
import sys
import tempfile

LINE_M = 5.0            # as the street drag
ROAD_WIDTH_M = 8.0      # SR2's 1800 across
UNIT_M = ROAD_WIDTH_M / 1800.0
HEIGHT_M = 0.4          # height word to meters, as the street drag
# A heading unit in radians, from how SR2 moves a car that points off the road: 2 units across per
# unit of heading per line (race.c 17ed..1813, a distance of 64 to the line).
HEADING_RAD = 2.0 * UNIT_M / LINE_M
MIDDLE = 2400           # across, halfway between the road's 1500 and 3300
VERGE = 200             # ROWS_VERGE_ROAD
START, FINISH, LAST = 370, 960, 985
RUN_IN = 12
ROCKFALL_REACH_M = 2.0  # course_scenery.gd's own numbers
ROAD_BOULDER_M = 1.5
CLUSTER_LINES = 3
MIN_GAP_M = 2.6         # a car's 1.6 m and room to steer it through
NODE_EVERY = 2          # lines. The joins stay under the track's smallest fillet.
STRIP_START, STRIP_FINISH = 8, 342
STRIP_MIDDLE = 2400

DUMP = r'''
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "course.h"
#include "rand.h"
static unsigned short f[COURSE_FRAME_WORDS];
#define AT(b,l) f[((b)+2*(l))/2]
int main(int argc, char **argv){
  game_rng r; game_rng_init(&r,NULL); r.seed=GAME_RNG_SEED;
  course_state cs; memset(&cs,0,sizeof cs); town_pages tp; memset(&tp,0,sizeof tp);
  course_town(f,&cs,0,1,&r,&tp); cs.number=atoi(argv[1]); course_build(f,&cs,0,cs.number,&r);
  for(int l=340;l<990;l++) printf("L %d %d %d %u %u %u %d %d %u\n",l,(short)AT(COURSE_HEADING,l),(short)AT(COURSE_HEIGHT,l),
    AT(COURSE_EDGE,l),AT(COURSE_WALL_LEFT,l),AT(COURSE_WALL_RIGHT,l),(short)AT(COURSE_LEFT_KIND,l),(short)AT(COURSE_RIGHT_KIND,l),AT(COURSE_EXTRA,l));
  for(int l=0;l<COURSE_STRIP_LINES;l++) printf("S %d %u\n",l,AT(COURSE_STRIP,l));
  return 0; }
'''


class Line:
    def __init__(self, row):
        self.number, self.heading, self.height, self.edge, self.wall_l, self.wall_r, self.kind_l, \
            self.kind_r, self.extra = row


def read_frame(game_dir, course):
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "dump.c"
        exe = pathlib.Path(tmp) / "dump"
        src.write_text(DUMP)
        subprocess.run(["gcc", "-std=gnu11", "-w", f"-I{game_dir}", str(src), f"{game_dir}/course.c",
                        f"{game_dir}/rand.c", "-o", str(exe)], check=True)
        out = subprocess.run([str(exe), str(course)], check=True, capture_output=True, text=True).stdout
    lines, strip = {}, {}
    for row in out.splitlines():
        parts = row.split()
        if parts[0] == "L":
            line = Line([int(v) for v in parts[1:]])
            lines[line.number] = line
        else:
            strip[int(parts[1])] = int(parts[2])
    return lines, strip


def pchip(knots, values, at):
    """Monotone cubic through the knots, the curve the track itself uses between its nodes."""
    n = len(knots)
    deltas = [(values[i + 1] - values[i]) / (knots[i + 1] - knots[i]) for i in range(n - 1)]
    slopes = [0.0] * n
    for i in range(1, n - 1):
        if deltas[i - 1] * deltas[i] > 0.0:
            slopes[i] = 2.0 * deltas[i - 1] * deltas[i] / (deltas[i - 1] + deltas[i])
    k = 0
    out = []
    for s in at:
        while k < n - 2 and s >= knots[k + 1]:
            k += 1
        span = knots[k + 1] - knots[k]
        t = (s - knots[k]) / span
        t2, t3 = t * t, t * t * t
        out.append((2 * t3 - 3 * t2 + 1) * values[k] + (t3 - 2 * t2 + t) * span * slopes[k]
                   + (-2 * t3 + 3 * t2) * values[k + 1] + (t3 - t2) * span * slopes[k + 1])
    return out


def rounded_heights(lines, first, last):
    """SR2's heights run straight between block ends, which are sharp points in 3D. Keep the tops,
    the bottoms and where a rise leaves level road at SR2's lines and heights, and round the rest."""
    knots = [first]
    for line in range(first + 1, last):
        before = lines[line].height - lines[line - 1].height
        after = lines[line + 1].height - lines[line].height
        if (before > 0) != (after > 0) or (before < 0) != (after < 0):
            knots.append(line)
    knots.append(last)
    heights = pchip(knots, [lines[k].height * HEIGHT_M for k in knots], range(first, last + 1))
    return {first + i: h for i, h in enumerate(heights)}


class Plan:
    """Where each line is on the ground: the middle of the road and the way it points. Yaw toward
    +X, which is the driver's left, is what SR2's heading going up means."""

    def __init__(self, lines, first, last):
        self.at = {}
        x = y = 0.0
        for line in range(first, last + 1):
            # Past the finish the track holds its last heading, straight on.
            yaw = lines[min(line, FINISH)].heading * HEADING_RAD
            self.at[line] = (x, y, yaw)
            x += math.sin(yaw) * LINE_M
            y += math.cos(yaw) * LINE_M
        yaw = lines[first].heading * HEADING_RAD
        for back in range(1, RUN_IN + 1):
            self.at[first - back] = (-math.sin(yaw) * LINE_M * back, -math.cos(yaw) * LINE_M * back, yaw)

    def point(self, line, across):
        """A point `across` in SR2's units: its road runs 1500 on the driver's left to 3300."""
        x, y, yaw = self.at[line]
        lateral = (MIDDLE - across) * UNIT_M
        return round(x + math.cos(yaw) * lateral, 2), round(y - math.sin(yaw) * lateral, 2)


def mulholland(lines, course):
    plan = Plan(lines, START, LAST)
    heights = rounded_heights(lines, START, FINISH)
    nodes, roads = [], []
    wanted = list(range(START, FINISH, NODE_EVERY)) + [FINISH]
    for index, line in enumerate(wanted):
        info = lines[line]
        x, y, _ = plan.at[line]
        node = {"id": index + 1, "x": round(x, 2), "y": round(y, 2)}
        if abs(heights[line]) > 0.0005:
            node["z"] = round(heights[line], 3)
        if info.kind_l != 0:
            node["left"] = round(info.kind_l * UNIT_M, 2)
        if info.kind_r != 0:
            node["right"] = round(info.kind_r * UNIT_M, 2)
        # A rail on the right only, and not on a bridge, which has its own.
        if info.wall_r & 0x8000 and not info.edge & 0x80:
            node["rail"] = True
        if line == START:
            node["type"] = "start"
        elif line == FINISH:
            node["type"] = "finish"
        nodes.append(node)
    for index, line in enumerate(wanted[:-1]):
        road = {"from": index + 1, "to": index + 2, "width": ROAD_WIDTH_M}
        stretch = range(line, wanted[index + 1])
        if any(lines[l].edge & 0x80 for l in stretch):
            road["width"] = 800 * UNIT_M
            road["type"] = "bridge"
        elif any(lines[l].edge & 0x60 for l in stretch):
            road["type"] = "gravel"
        roads.append(road)
    items, left_out = mulholland_scenery(lines, plan)
    return nodes, roads, items, left_out


def mulholland_scenery(lines, plan):
    items = []
    taken = set()

    def put(kind, line, across, depth=0):
        at = min(line + depth, LAST)
        x, y = plan.point(at, across)
        # SR2 can draw two sprites on one spot. Two solid things in one place would just merge.
        while (kind, x, y) in taken:
            y += 2.0
        taken.add((kind, x, y))
        item = {"kind": kind, "x": x, "y": y, "_line": line, "_lat": (MIDDLE - across) * UNIT_M}
        items.append(item)
        return item

    left_edge, right_edge = 1500, 3300
    verge_l, verge_r = left_edge - VERGE, right_edge + VERGE
    for line in range(START - RUN_IN, LAST + 1):
        info = lines[line]
        ed, wl, wr = info.edge, info.wall_l, info.wall_r
        flat_l, flat_r = info.kind_l == 0, info.kind_r == 0
        racing = line < FINISH
        if ed & 0x8 and not ed & 0xe0:
            put("dash", line, MIDDLE)
        if ed & 0x10 and line == FINISH - 1:
            put("finish", line, MIDDLE)
        # What stands beside the road, from the driver's left to right, as roadside_ahead.c's
        # objects() has it. The road race's kinds: 0x15 a low shrub and 0x16 a big bush.
        if wl & 0x100 and flat_l:
            if wl & 0x200:
                put("shrub", line, 2 * verge_l - left_edge, 2)
            else:
                put("shrub", line, verge_l)
        if wl & 0x800:
            put("road_work_sign", line, left_edge)
        if wl & 0x1000:
            put("barricade", line, left_edge)
        if wl & 0x1 and flat_l:
            put("post", line, left_edge)
        if wl & 0x10:
            put("rockfall_left", line, left_edge)
        if flat_l:
            if wl & 0x40:
                put("tree", line, verge_l)
            if wl & 0x80:
                if wl & 0x2:
                    put("bush", line, verge_l - 900, 3)
                else:
                    put("bush", line, verge_l)
            if wl & 0x4:
                put("rock", line, left_edge - 2)
            if wl & 0x8:
                put("boulder_side", line, left_edge - 2)
        if flat_r:
            if wr & 0x40:
                put("tree", line, verge_r)
            if wr & 0x80:
                if wr & 0x2:
                    put("bush", line, verge_r + 900, 3)
                else:
                    put("bush", line, verge_r + VERGE // 2 + 900 // 2)
            if wr & 0x4:
                put("rock", line, right_edge + 2)
            if wr & 0x8:
                put("boulder_side", line, right_edge + 2)
            if ed & 0x2:
                put("pole", line, verge_r - 1800 // 8)
            if wr & 0x100:
                if wr & 0x200:
                    put("shrub", line, 2 * verge_r - right_edge, 3)
                else:
                    put("shrub", line, verge_r)
            if wr & 0x1:
                put("post", line, right_edge)
        if wr & 0x2000:
            put("curves_sign", line, right_edge)
        if wr & 0x4000:
            put("curves_back_sign", line, right_edge)
        if wr & 0x800:
            put("road_work_sign", line, right_edge)
        if wr & 0x1000:
            put("barricade", line, right_edge)
        if wr & 0x10:
            put("rockfall_right", line, right_edge)
        lane_across = left_edge + info.extra * 1800 // 16
        if ed & 0x4 and racing:
            put("road_boulder", line, lane_across)
        if ed & 0x1000 and racing:
            put("road_rock", line, lane_across)
        if ed & 0x100:
            put("speed_sign", line, right_edge)
        if ed & 0x800:
            put("narrows_sign", line, right_edge)
        if ed & 0x200:
            put("chevron_left", line, right_edge)
        if ed & 0x400:
            put("chevron_right", line, right_edge)
    return keep_road_open(items)


def keep_road_open(items):
    """SR2 rolls these independently and only some of them stop its car. Here all of them do, so
    where they would close the road between them, the boulder comes off the road. It goes in the
    track's `left_out` list instead, with its line and place. A car can go through a sawhorse, so
    those don't count."""
    def span(item):
        lat = item["_lat"]
        if item["kind"].startswith("rockfall"):
            return (min(lat, lat - math.copysign(ROCKFALL_REACH_M, lat)), max(lat, lat - math.copysign(ROCKFALL_REACH_M, lat)))
        return (lat - ROAD_BOULDER_M / 2, lat + ROAD_BOULDER_M / 2)

    solid = [i for i in items if i["kind"] in ("rockfall_left", "rockfall_right", "road_boulder")]
    left_out = []
    for boulder in [i for i in solid if i["kind"] == "road_boulder"]:
        near = [i for i in solid if abs(i["_line"] - boulder["_line"]) <= CLUSTER_LINES]
        edge, widest = -ROAD_WIDTH_M / 2, 0.0
        for low, high in sorted(span(i) for i in near):
            widest = max(widest, low - edge)
            edge = max(edge, high)
        widest = max(widest, ROAD_WIDTH_M / 2 - edge)
        if widest < MIN_GAP_M:
            items.remove(boulder)
            solid.remove(boulder)
            left_out.append({"kind": "road_boulder", "x": boulder["x"], "y": boulder["y"],
                             "sr2_line": boulder["_line"], "lateral": round(boulder["_lat"], 2),
                             "gap": round(widest, 2), "beside": sorted(i["kind"] for i in near if i is not boulder)})
    for item in items:
        del item["_line"], item["_lat"]
    return items, left_out


def aqueduct(strip):
    last = STRIP_FINISH
    nodes = [{"id": 1, "x": 0, "y": 0, "type": "start"},
             {"id": 2, "x": 0, "y": (STRIP_FINISH - STRIP_START) * LINE_M, "type": "finish"}]
    # The whole channel counts as road, the floor and both banks: 3720 - 1080 across.
    roads = [{"from": 1, "to": 2, "width": round(2640 * UNIT_M, 2)}]
    items = []

    def put(kind, line, across=STRIP_MIDDLE):
        items.append({"kind": kind, "x": round((STRIP_MIDDLE - across) * UNIT_M, 2),
                      "y": round((line - STRIP_START) * LINE_M, 2)})

    gutter_from = None
    for line in range(max(STRIP_START - RUN_IN, 0), COURSE_LINES(strip)):
        bits = strip[line]
        if line > last + 40:
            break
        if bits & 0x2:
            if gutter_from is not None:
                items.append({"kind": "gutter", "x": 0, "y": (gutter_from - STRIP_START) * LINE_M,
                              "to": (line - STRIP_START) * LINE_M})
                gutter_from = None
        elif gutter_from is None:
            gutter_from = line
        if bits & 0x1:
            put("joint", line)
        if bits & 0x400:
            put("finish", line)
        if bits & (0x4 | 0x100):
            put("drain", line, 1080)
        elif bits & (0x8 | 0x200):
            put("drain", line, 3720)
        if bits & 0x20:
            put("stain", line, 1480 + 1840 // 4)
        if bits & 0x40:
            put("stain", line, 3320 - 1840 // 8)
        if bits & 0x10:
            put("slab", line)
        if bits & 0x80:
            # A seventh of the way in from each mark, an eighth of that wide.
            put("fin", line, 1480 + 1840 // 7 + 1840 // 56)
            put("fin", line, 3320 - 1840 // 7 - 1840 // 56)
    if gutter_from is not None:
        items.append({"kind": "gutter", "x": 0, "y": (gutter_from - STRIP_START) * LINE_M,
                      "to": (last + 28 - STRIP_START) * LINE_M})
    return nodes, roads, items


def COURSE_LINES(strip):
    return max(strip) + 1


def write(path, name, style, nodes, roads, items, left_out=()):
    out = ['{', f'  "name": {json.dumps(name)},', f'  "style": {json.dumps(style)},', '  "nodes": [']
    out.append(",\n".join("    " + json.dumps(n) for n in nodes))
    out += ['  ],', '  "roads": [']
    out.append(",\n".join("    " + json.dumps(r) for r in roads))
    out += ['  ],', '  "scenery": [']
    out.append(",\n".join("    " + json.dumps(i) for i in items))
    if left_out:
        out += ['  ],', '  "left_out": [']
        out.append(",\n".join("    " + json.dumps(i) for i in left_out))
    out += ['  ]', '}', '']
    path.write_text("\n".join(out))
    kinds = {}
    for item in items:
        kinds[item["kind"]] = kinds.get(item["kind"], 0) + 1
    print(path.name, len(nodes), "nodes", sum(kinds.values()), "items", kinds, "left out", len(left_out))


def main():
    game_dir, out_dir = sys.argv[1], pathlib.Path(sys.argv[2])
    strip = None
    for course in range(10):
        lines, strip = read_frame(game_dir, course)
        nodes, roads, items, left_out = mulholland(lines, course)
        write(out_dir / f"mulholland_{course}.trk", "Mulholland drive", "mountain", nodes, roads, items, left_out)
    nodes, roads, items = aqueduct(strip)
    write(out_dir / "aqueduct.trk", "Aqueduct race", "aqueduct", nodes, roads, items)


main()
