#!/usr/bin/env python3
"""Make the police Fairlane from the stock 1957 Fairlane.

Copies the body shell as-is and only changes its paint: black front, roof and
tail, white doors, and a gold shield on each front door, matching the
black-and-white cruiser in backup/1/police-fairlane-1957.avif. A red roof
beacon is added on top of the shell. Chrome, glass, lamps, interior and the
body mesh itself are left alone.

    python3 tools/make_police_fairlane.py
"""
import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/cars/sr1-fairlane-1957.glb"
DST = ROOT / "assets/cars/police-fairlane-1957.glb"
CAR = ROOT / "assets/cars/police-fairlane-1957.car"

# Door skins, in the model's own units (front of the car is +Z).
DOOR_Z = (-58.0, 44.0)
DOOR_Y = (14.0, 44.5)
DOOR_ABS_X = 38.0
DOOR_ABS_NX = 0.34
# Gold shield, centered on the front door below the beltline.
BADGE_Z = 22.0
BADGE_Y = 29.0
BADGE_HALF_Z = 5.4
BADGE_HALF_Y = 6.6
# Single red beacon, centered on the flat roof.
BEACON_X = 0.0
BEACON_Z = 0.0

LUM_LO, LUM_HI = 22.0, 232.0
CHROMA_MAX = 36.0
METAL_MAX = 158.0


RASTER_C = r"""
#include <math.h>
#include <stdlib.h>
#include <string.h>

static int edge(float ax, float ay, float bx, float by, float px, float py) {
    return (py - ay) * (bx - ax) - (px - ax) * (by - ay);
}

void raster_uv(
    const float* uv, const float* pos, const float* nrm,
    const int* idx, const float* score, int ntri,
    float* out_pos, float* out_nrm, float* out_score, int S)
{
    memset(out_score, 0, (size_t)S * S * sizeof(float));
    for (int t = 0; t < ntri; t++) {
        float sc = score[t];
        if (sc <= 0.f) continue;
        int i0 = idx[t * 3], i1 = idx[t * 3 + 1], i2 = idx[t * 3 + 2];
        float x0 = uv[i0 * 2], y0 = uv[i0 * 2 + 1];
        float x1 = uv[i1 * 2], y1 = uv[i1 * 2 + 1];
        float x2 = uv[i2 * 2], y2 = uv[i2 * 2 + 1];
        int minx = (int)floorf(fminf(x0, fminf(x1, x2)));
        int maxx = (int)ceilf(fmaxf(x0, fmaxf(x1, x2)));
        int miny = (int)floorf(fminf(y0, fminf(y1, y2)));
        int maxy = (int)ceilf(fmaxf(y0, fmaxf(y1, y2)));
        if (minx < 0) minx = 0;
        if (miny < 0) miny = 0;
        if (maxx >= S) maxx = S - 1;
        if (maxy >= S) maxy = S - 1;
        float area = edge(x0, y0, x1, y1, x2, y2);
        if (fabsf(area) < 1e-6f) continue;
        float inv = 1.f / area;
        const float* p0 = pos + i0 * 3;
        const float* p1 = pos + i1 * 3;
        const float* p2 = pos + i2 * 3;
        const float* n0 = nrm + i0 * 3;
        const float* n1 = nrm + i1 * 3;
        const float* n2 = nrm + i2 * 3;
        for (int y = miny; y <= maxy; y++) {
            for (int x = minx; x <= maxx; x++) {
                float px = (float)x + 0.5f, py = (float)y + 0.5f;
                float w0 = edge(x1, y1, x2, y2, px, py) * inv;
                float w1 = edge(x2, y2, x0, y0, px, py) * inv;
                float w2 = 1.f - w0 - w1;
                if (w0 < -0.002f || w1 < -0.002f || w2 < -0.002f) continue;
                float* dest = out_score + y * S + x;
                if (sc < *dest) continue;
                *dest = sc;
                float* op = out_pos + (y * S + x) * 3;
                float* on = out_nrm + (y * S + x) * 3;
                op[0] = w0 * p0[0] + w1 * p1[0] + w2 * p2[0];
                op[1] = w0 * p0[1] + w1 * p1[1] + w2 * p2[1];
                op[2] = w0 * p0[2] + w1 * p1[2] + w2 * p2[2];
                on[0] = w0 * n0[0] + w1 * n1[0] + w2 * n2[0];
                on[1] = w0 * n0[1] + w1 * n1[1] + w2 * n2[1];
                on[2] = w0 * n0[2] + w1 * n1[2] + w2 * n2[2];
            }
        }
    }
}

void raster_screen(
    const float* sp, const float* nrm, const float* uv, const float* col,
    const int* idx, int ntri,
    float* out_uv, float* out_nrm, float* out_col, float* out_depth,
    int W, int H)
{
    for (int i = 0; i < W * H; i++) out_depth[i] = -1e30f;
    for (int t = 0; t < ntri; t++) {
        int i0 = idx[t * 3], i1 = idx[t * 3 + 1], i2 = idx[t * 3 + 2];
        float x0 = sp[i0 * 3], y0 = sp[i0 * 3 + 1], z0 = sp[i0 * 3 + 2];
        float x1 = sp[i1 * 3], y1 = sp[i1 * 3 + 1], z1 = sp[i1 * 3 + 2];
        float x2 = sp[i2 * 3], y2 = sp[i2 * 3 + 1], z2 = sp[i2 * 3 + 2];
        int minx = (int)floorf(fminf(x0, fminf(x1, x2)));
        int maxx = (int)ceilf(fmaxf(x0, fmaxf(x1, x2)));
        int miny = (int)floorf(fminf(y0, fminf(y1, y2)));
        int maxy = (int)ceilf(fmaxf(y0, fmaxf(y1, y2)));
        if (maxx < 0 || maxy < 0 || minx >= W || miny >= H) continue;
        if (minx < 0) minx = 0;
        if (miny < 0) miny = 0;
        if (maxx >= W) maxx = W - 1;
        if (maxy >= H) maxy = H - 1;
        if (maxx - minx > 400 || maxy - miny > 400) continue;
        float area = edge(x0, y0, x1, y1, x2, y2);
        if (fabsf(area) < 1e-4f) continue;
        float inv = 1.f / area;
        for (int y = miny; y <= maxy; y++) {
            for (int x = minx; x <= maxx; x++) {
                float px = (float)x + 0.5f, py = (float)y + 0.5f;
                float w0 = edge(x1, y1, x2, y2, px, py) * inv;
                float w1 = edge(x2, y2, x0, y0, px, py) * inv;
                float w2 = 1.f - w0 - w1;
                if (w0 < -0.001f || w1 < -0.001f || w2 < -0.001f) continue;
                float depth = w0 * z0 + w1 * z1 + w2 * z2;
                float* dp = out_depth + y * W + x;
                if (depth <= *dp) continue;
                *dp = depth;
                int o = y * W + x;
                out_uv[o * 2] = w0 * uv[i0 * 2] + w1 * uv[i1 * 2] + w2 * uv[i2 * 2];
                out_uv[o * 2 + 1] = w0 * uv[i0 * 2 + 1] + w1 * uv[i1 * 2 + 1] + w2 * uv[i2 * 2 + 1];
                out_nrm[o * 3] = w0 * nrm[i0 * 3] + w1 * nrm[i1 * 3] + w2 * nrm[i2 * 3];
                out_nrm[o * 3 + 1] = w0 * nrm[i0 * 3 + 1] + w1 * nrm[i1 * 3 + 1] + w2 * nrm[i2 * 3 + 1];
                out_nrm[o * 3 + 2] = w0 * nrm[i0 * 3 + 2] + w1 * nrm[i1 * 3 + 2] + w2 * nrm[i2 * 3 + 2];
                out_col[o * 3] = w0 * col[i0 * 3] + w1 * col[i1 * 3] + w2 * col[i2 * 3];
                out_col[o * 3 + 1] = w0 * col[i0 * 3 + 1] + w1 * col[i1 * 3 + 1] + w2 * col[i2 * 3 + 1];
                out_col[o * 3 + 2] = w0 * col[i0 * 3 + 2] + w1 * col[i1 * 3 + 2] + w2 * col[i2 * 3 + 2];
            }
        }
    }
}
"""


def load_raster():
    """Compile the tiny rasterizer once per run."""
    src = Path(tempfile.gettempdir()) / "police_fairlane_raster.c"
    lib = Path(tempfile.gettempdir()) / "police_fairlane_raster.so"
    src.write_text(RASTER_C)
    subprocess.check_call(["cc", "-O3", "-shared", "-fPIC", "-o", str(lib), str(src)])
    import ctypes
    dll = ctypes.CDLL(str(lib))
    dll.raster_uv.argtypes = [
        ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float),
        ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(ctypes.c_float), ctypes.c_int,
        ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float),
        ctypes.POINTER(ctypes.c_float), ctypes.c_int,
    ]
    dll.raster_screen.argtypes = [
        ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float),
        ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float),
        ctypes.POINTER(ctypes.c_int), ctypes.c_int,
        ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float),
        ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float),
        ctypes.c_int, ctypes.c_int,
    ]
    return dll


def read_glb(path):
    data = path.read_bytes()
    jlen, = struct.unpack_from("<I", data, 12)
    gltf = json.loads(data[20:20 + jlen])
    blob = data[20 + jlen + 8:]
    return gltf, blob


def accessor(gltf, blob, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    off = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    ctype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[acc["componentType"]]
    comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    count = acc["count"]
    stride = view.get("byteStride", 0)
    if stride and stride != comps * np.dtype(ctype).itemsize:
        raise SystemExit("unexpected stride on %s" % acc)
    arr = np.frombuffer(blob, ctype, count * comps, off).reshape(count, comps).copy()
    return arr


def make_badge():
    """Gold shield with a star, the mark on the reference car's front door."""
    size = 512
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    cx = cy = size / 2

    def to_px(pts):
        out = []
        for x, y in pts:
            out.append((cx + x * size * 0.46, cy - y * size * 0.46))
        return out

    def shield(scale):
        pts = []
        for i in range(17):
            t = i / 16
            x = -0.62 + 1.24 * t
            y = 0.78 + 0.06 * (1 - (2 * t - 1) ** 2)
            pts.append((x * scale, y * scale))
        for i in range(1, 18):
            t = i / 17
            x = 0.62 + (0.0 - 0.62) * t
            y = 0.78 + (-1.0 - 0.78) * (t ** 1.15)
            # Bow the side out through the middle, then in to the point.
            bow = 0.10 * np.sin(t * np.pi)
            pts.append(((x + bow) * scale, y * scale))
        for i in range(1, 18):
            t = i / 17
            x = 0.0 + (-0.62 - 0.0) * t
            y = -1.0 + (0.78 - -1.0) * (t ** 1.15)
            bow = -0.10 * np.sin((1 - t) * np.pi)
            pts.append(((x + bow) * scale, y * scale))
        return pts

    gold = (218, 172, 64, 255)
    gold_deep = (92, 62, 18, 255)
    navy = (12, 22, 48, 255)
    draw.polygon(to_px(shield(1.0)), fill=gold)
    draw.polygon(to_px(shield(0.84)), fill=gold_deep)
    draw.polygon(to_px(shield(0.74)), fill=navy)

    def star(radius, points):
        out = []
        for i in range(points * 2):
            ang = -np.pi / 2 + i * np.pi / points
            r = radius if i % 2 == 0 else radius * 0.46
            out.append((np.cos(ang) * r, np.sin(ang) * r + 0.06))
        return out

    draw.polygon(to_px(star(0.46, 6)), fill=gold)
    draw.polygon(to_px(star(0.16, 6)), fill=navy)

    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 72)
    text = "POLICE"
    box = draw.textbbox((0, 0), text, font=font)
    tw = box[2] - box[0]
    draw.text(((size - tw) / 2, size * 0.68), text, font=font, fill=gold)
    return np.array(im)


def beacon_mesh(roof_y):
    """Chrome cup and a red dome, sitting on the roof."""
    chrome_p, chrome_n, chrome_uv = [], [], []
    red_p, red_n, red_uv = [], [], []

    def add_cyl(bucket_p, bucket_n, bucket_uv, r, y0, y1, n, v0, v1):
        base = len(bucket_p)
        for i in range(n):
            ang = i / n * np.pi * 2
            c, s = np.cos(ang), np.sin(ang)
            u = i / n
            for y, v in ((y0, v0), (y1, v1)):
                bucket_p.append([r * c, y, r * s])
                bucket_n.append([c, 0.0, s])
                bucket_uv.append([u, v])
        idx = []
        for i in range(n):
            i2 = (i + 1) % n
            a = base + i * 2
            b = base + i2 * 2
            idx += [a, a + 1, b + 1, a, b + 1, b]
        return idx

    def add_annulus(r_out, r_in, y, n):
        base = len(chrome_p)
        idx = []
        for i in range(n):
            ang = i / n * np.pi * 2
            c, s = np.cos(ang), np.sin(ang)
            chrome_p.append([r_out * c, y, r_out * s])
            chrome_n.append([0.0, 1.0, 0.0])
            chrome_uv.append([i / n, 0.5])
            chrome_p.append([r_in * c, y, r_in * s])
            chrome_n.append([0.0, 1.0, 0.0])
            chrome_uv.append([i / n, 0.8])
        for i in range(n):
            i2 = (i + 1) % n
            a = base + i * 2
            b = base + i2 * 2
            idx += [a, b, a + 1, a + 1, b, b + 1]
        return idx

    n = 32
    # Flange, neck, and the lip the dome sits in. Local Y is up from the roof.
    ci = []
    ci += add_cyl(chrome_p, chrome_n, chrome_uv, 6.15, 0.0, 0.85, n, 0.0, 0.25)
    ci += add_annulus(6.15, 4.55, 0.85, n)
    ci += add_cyl(chrome_p, chrome_n, chrome_uv, 4.55, 0.85, 2.15, n, 0.25, 0.7)
    ci += add_annulus(5.15, 4.55, 2.15, n)

    # Red dome: a sphere from the top down past the equator, sunk in the cup.
    center_y = 2.05
    radius = 4.85
    n_lat, n_lon = 12, 32
    base = len(red_p)
    red_p.append([0.0, center_y + radius, 0.0])
    red_n.append([0.0, 1.0, 0.0])
    red_uv.append([0.5, 1.0])
    phis = np.linspace(0, np.radians(108), n_lat + 1)[1:]
    for pi, phi in enumerate(phis):
        for ti in range(n_lon):
            th = ti / n_lon * np.pi * 2
            st, ct = np.sin(phi), np.cos(phi)
            nx, ny, nz = np.cos(th) * st, ct, np.sin(th) * st
            red_p.append([nx * radius, center_y + ny * radius, nz * radius])
            red_n.append([nx, ny, nz])
            red_uv.append([ti / n_lon, 1 - phi / np.radians(108)])
    ri = []
    for ti in range(n_lon):
        ri += [base, base + 1 + (ti + 1) % n_lon, base + 1 + ti]
    for pi in range(n_lat - 1):
        row = base + 1 + pi * n_lon
        nxt = row + n_lon
        for ti in range(n_lon):
            t2 = (ti + 1) % n_lon
            ri += [row + ti, row + t2, nxt + t2, row + ti, nxt + t2, nxt + ti]

    def shift(pts):
        arr = np.array(pts, np.float32)
        arr[:, 0] += BEACON_X
        arr[:, 1] += roof_y - 0.08
        arr[:, 2] += BEACON_Z
        return arr

    chrome = (shift(chrome_p), np.array(chrome_n, np.float32), np.array(chrome_uv, np.float32), np.array(ci, np.uint32))
    red = (shift(red_p), np.array(red_n, np.float32), np.array(red_uv, np.float32), np.array(ri, np.uint32))
    return chrome, red


def paint_body(color, orm, pos, nrm, score):
    """Recolor exterior body paint. Chrome, lamps and dark gaps stay put."""
    lum = color[:, :, :3].astype(np.float32).mean(2)
    chroma = color[:, :, :3].max(2) - color[:, :, :3].min(2)
    metal = orm[:, :, 2].astype(np.float32)
    covered = score > 0
    paint = (
        covered
        & (lum >= LUM_LO) & (lum <= LUM_HI)
        & (chroma <= CHROMA_MAX)
        & (metal <= METAL_MAX)
        & (pos[:, :, 1] > 11.0)
    )
    # Headlight and tail-light lenses sit in the same gray range as the paint.
    x, y, z = pos[:, :, 0], pos[:, :, 1], pos[:, :, 2]
    lamp = ((z > 128.0) & (y > 27.0) & (y < 39.0) & (np.abs(x) > 18.0) & (np.abs(x) < 46.0)) | (
        (z < -128.0) & (y > 26.0) & (y < 40.0) & (np.abs(x) > 22.0)
    )
    paint &= ~lamp

    rel = np.clip((lum - 188.0) / 70.0, -1.2, 1.0)
    black = np.clip(20.0 + rel * 12.0, 5.0, 36.0)
    white = np.clip(236.0 + rel * 22.0, 198.0, 248.0)
    side = (
        (np.abs(nrm[:, :, 0]) >= DOOR_ABS_NX)
        & (np.abs(x) >= DOOR_ABS_X)
        & (y >= DOOR_Y[0]) & (y <= DOOR_Y[1])
        & (z >= DOOR_Z[0]) & (z <= DOOR_Z[1])
        & (nrm[:, :, 1] < 0.62)
    )
    shade = np.where(side, white, black)
    out = color.copy()
    rgb = out[:, :, :3]
    rgb[paint] = np.clip(shade[paint], 0, 255).astype(np.uint8)[:, None]

    badge = make_badge()
    bh, bw = badge.shape[:2]
    # +X is the car's right when facing forward. Flip each side so the word reads
    # from outside the door.
    on_door = paint & (np.abs(x) > 42.0) & (np.abs(nrm[:, :, 0]) > 0.4)
    bz = (z - BADGE_Z) / BADGE_HALF_Z
    by = (y - BADGE_Y) / BADGE_HALF_Y
    bu = np.where(x >= 0.0, -bz, bz)
    inside = on_door & (np.abs(bu) <= 1.0) & (np.abs(by) <= 1.0)
    ys, xs = np.where(inside)
    if len(xs):
        px = np.clip(((bu[ys, xs] * 0.5 + 0.5) * (bw - 1)).astype(np.int32), 0, bw - 1)
        py = np.clip(((0.5 - by[ys, xs] * 0.5) * (bh - 1)).astype(np.int32), 0, bh - 1)
        sample = badge[py, px]
        keep = sample[:, 3] > 160
        rgb[ys[keep], xs[keep]] = sample[keep, :3]
        badge_px = int(keep.sum())
    else:
        badge_px = 0

    # Pull the new paint a couple of texels into the island gutter, which is the
    # same light gray just outside the rasterized triangles. Stop at chrome and black.
    gutter = (
        (lum >= LUM_LO - 8) & (lum <= LUM_HI + 6)
        & (chroma <= CHROMA_MAX + 4)
        & (metal <= METAL_MAX)
        & ~lamp
    )
    mask = paint.copy()
    # The badge counts as painted too, so its edge pads the same way.
    mask[ys, xs] = True

    def shift(arr, dy, dx):
        out = np.zeros_like(arr)
        ys_ = slice(max(dy, 0), arr.shape[0] + min(dy, 0))
        xs_ = slice(max(dx, 0), arr.shape[1] + min(dx, 0))
        y2 = slice(max(-dy, 0), arr.shape[0] + min(-dy, 0))
        x2 = slice(max(-dx, 0), arr.shape[1] + min(-dx, 0))
        out[ys_, xs_] = arr[y2, x2]
        return out

    for _ in range(3):
        acc = np.zeros(rgb.shape, np.float32)
        cnt = np.zeros(mask.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sm = shift(mask, dy, dx).astype(np.float32)
            sc = shift(rgb, dy, dx).astype(np.float32)
            acc += sc * sm[:, :, None]
            cnt += sm
        grow = (~mask) & (cnt > 0) & gutter
        rgb[grow] = (acc[grow] / cnt[grow, None]).astype(np.uint8)
        mask[grow] = True
    out[:, :, :3] = rgb
    return out, int(paint.sum()), badge_px


def append_view(gltf, blobs, raw, target=None):
    blobs.append(np.ascontiguousarray(raw).tobytes())
    view = {"buffer": 0, "byteLength": len(blobs[-1]), "byteOffset": 0}
    if target is not None:
        view["target"] = target
    gltf["bufferViews"].append(view)
    return len(gltf["bufferViews"]) - 1


def append_accessor(gltf, view, comp_type, typ, count, mins=None, maxs=None):
    acc = {"bufferView": view, "componentType": comp_type, "count": count, "type": typ}
    if mins is not None:
        acc["min"] = mins
        acc["max"] = maxs
    gltf["accessors"].append(acc)
    return len(gltf["accessors"]) - 1


def add_beacon(gltf, blobs, roof_y):
    chrome, red = beacon_mesh(roof_y)
    prims = []
    for (pos, nrm, uv, idx), mat_name, mat in (
        (chrome, "police_beacon_chrome", {
            "name": "police_beacon_chrome",
            "pbrMetallicRoughness": {
                "baseColorFactor": [0.74, 0.75, 0.77, 1.0],
                "metallicFactor": 1.0,
                "roughnessFactor": 0.18,
            },
        }),
        (red, "police_beacon_red", {
            "name": "police_beacon_red",
            "pbrMetallicRoughness": {
                "baseColorFactor": [0.62, 0.01, 0.012, 1.0],
                "metallicFactor": 0.04,
                "roughnessFactor": 0.16,
            },
            "emissiveFactor": [0.85, 0.02, 0.015],
        }),
    ):
        gltf["materials"].append(mat)
        mat_i = len(gltf["materials"]) - 1
        pv = append_view(gltf, blobs, pos.astype(np.float32), 34962)
        nv = append_view(gltf, blobs, nrm.astype(np.float32), 34962)
        tv = append_view(gltf, blobs, uv.astype(np.float32), 34962)
        iv = append_view(gltf, blobs, idx.astype(np.uint32), 34963)
        pa = append_accessor(gltf, pv, 5126, "VEC3", len(pos), pos.min(0).tolist(), pos.max(0).tolist())
        na = append_accessor(gltf, nv, 5126, "VEC3", len(nrm), nrm.min(0).tolist(), nrm.max(0).tolist())
        ta = append_accessor(gltf, tv, 5126, "VEC2", len(uv), [0.0, 0.0], [1.0, 1.0])
        ia = append_accessor(gltf, iv, 5125, "SCALAR", len(idx))
        prims.append({
            "attributes": {"POSITION": pa, "NORMAL": na, "TEXCOORD_0": ta},
            "indices": ia,
            "material": mat_i,
        })
    gltf["meshes"].append({"name": "police_beacon", "primitives": prims})
    gltf["nodes"].append({"name": "police_beacon", "mesh": len(gltf["meshes"]) - 1})
    gltf["scenes"][gltf.get("scene", 0)]["nodes"].append(len(gltf["nodes"]) - 1)
    top = max(chrome[0][:, 1].max(), red[0][:, 1].max())
    return float(top)


def pack(gltf, blobs):
    out = bytearray()
    for i, part in enumerate(blobs):
        pad = (-len(out)) % 4
        out += b"\x00" * pad
        gltf["bufferViews"][i]["byteOffset"] = len(out)
        gltf["bufferViews"][i]["byteLength"] = len(part)
        out += part
    pad = (-len(out)) % 4
    out += b"\x00" * pad
    gltf["buffers"][0]["byteLength"] = len(out)
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(out)
    header = struct.pack("<4sII", b"glTF", 2, total)
    return header + struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(out), b"BIN\x00") + bytes(out)


def _facing(pos, faces, cull):
    """Triangles whose face points toward the camera."""
    v0, v1, v2 = pos[faces[:, 0]], pos[faces[:, 1]], pos[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    return (fn * np.array(cull, np.float32)).sum(1) > 0.0


def render_views(dll, pos, nrm, uv, faces, tex, extra, out_dir):
    """Orthographic shots of the repainted shell, beacon included."""
    light = np.array([0.25, 0.85, 0.45], np.float32)
    light /= np.linalg.norm(light)
    rgb = tex[:, :, :3]
    th, tw = rgb.shape[:2]

    blocks = [(pos, nrm, uv, np.zeros((len(pos), 3), np.float32), faces, True)]
    for mesh in extra:
        blocks.append((*mesh, False))

    # project(pos) -> screen x, screen y, depth. cull is the direction a visible
    # face points. crop limits the framed region in those screen axes.
    views = [
        ("side", lambda p: (p[:, 2], p[:, 1], p[:, 0]), (1, 0, 0), None),
        ("door", lambda p: (p[:, 2], p[:, 1], p[:, 0]), (1, 0, 0), (2, 48, 14, 50)),
        ("door-left", lambda p: (p[:, 2], p[:, 1], -p[:, 0]), (-1, 0, 0), (2, 48, 14, 50)),
        ("front", lambda p: (p[:, 0], p[:, 1], p[:, 2]), (0, 0, 1), None),
        ("rear", lambda p: (-p[:, 0], p[:, 1], -p[:, 2]), (0, 0, -1), None),
        ("top", lambda p: (p[:, 2], -p[:, 0], p[:, 1]), (0, 1, 0), None),
        ("three-quarter", lambda p: (
            p[:, 0] * 0.62 + p[:, 2] * 0.78,
            p[:, 1],
            -p[:, 0] * 0.78 + p[:, 2] * 0.62,
        ), (-0.78, 0, 0.62), None),
    ]
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, project, cull, crop in views:
        chunks = []
        for bp, bn, bu, bc, bf, cull_it in blocks:
            use = bf[_facing(bp, bf, cull)] if cull_it else bf
            if crop is not None and len(use):
                mid = bp[use].mean(1)
                sx, sy, _sd = project(mid)
                use = use[(sx > crop[0]) & (sx < crop[1]) & (sy > crop[2]) & (sy < crop[3])]
            if len(use) == 0:
                continue
            sx, sy, sd = project(bp)
            chunks.append((sx, sy, sd, bn, bu, bc, use, len(bp)))
        if not chunks:
            continue
        if crop is None:
            all_x = np.concatenate([c[0][c[6].reshape(-1)] for c in chunks])
            all_y = np.concatenate([c[1][c[6].reshape(-1)] for c in chunks])
            x0, x1 = float(all_x.min()), float(all_x.max())
            y0, y1 = float(all_y.min()), float(all_y.max())
        else:
            x0, x1, y0, y1 = crop
        span_x = (x1 - x0) or 1
        span_y = (y1 - y0) or 1
        W = 1100 if crop is None else 900
        H = int(W * span_y / span_x) + 8
        H = min(max(H, 240), 1000)
        screens, norms, uvs, cols, indices = [], [], [], [], []
        base = 0
        for sx, sy, sd, bn, bu, bc, bf, n in chunks:
            scr = np.zeros((n, 3), np.float32)
            scr[:, 0] = (sx - x0) / span_x * (W - 1)
            scr[:, 1] = (y1 - sy) / span_y * (H - 1)
            scr[:, 2] = sd
            screens.append(scr)
            norms.append(bn.astype(np.float32))
            uvs.append(bu.astype(np.float32))
            cols.append(bc.astype(np.float32))
            indices.append(bf.astype(np.int32) + base)
            base += n
        sp = np.ascontiguousarray(np.concatenate(screens))
        nn = np.ascontiguousarray(np.concatenate(norms))
        uu = np.ascontiguousarray(np.concatenate(uvs))
        cc = np.ascontiguousarray(np.concatenate(cols))
        ii = np.ascontiguousarray(np.concatenate([a.reshape(-1) for a in indices]))
        out_uv = np.zeros((H, W, 2), np.float32)
        out_n = np.zeros((H, W, 3), np.float32)
        out_c = np.zeros((H, W, 3), np.float32)
        depth = np.zeros((H, W), np.float32)
        dll.raster_screen(
            sp.ctypes.data_as(ctypes_float()), nn.ctypes.data_as(ctypes_float()),
            uu.ctypes.data_as(ctypes_float()), cc.ctypes.data_as(ctypes_float()),
            ii.ctypes.data_as(ctypes_int()), ii.size // 3,
            out_uv.ctypes.data_as(ctypes_float()), out_n.ctypes.data_as(ctypes_float()),
            out_c.ctypes.data_as(ctypes_float()), depth.ctypes.data_as(ctypes_float()),
            W, H,
        )
        hit = depth > -1e20
        img = np.zeros((H, W, 3), np.uint8)
        uu_i = np.clip((out_uv[:, :, 0] * (tw - 1)).astype(np.int32), 0, tw - 1)
        vv_i = np.clip(((1 - out_uv[:, :, 1]) * (th - 1)).astype(np.int32), 0, th - 1)
        albedo = rgb[vv_i, uu_i].astype(np.float32)
        # Beacon verts carry their color in the vertex color and a UV of -1.
        solid = out_uv[:, :, 0] < -0.5
        albedo[solid] = np.clip(out_c[solid] * 255.0, 0, 255)
        nrm_s = out_n
        ln = np.linalg.norm(nrm_s, axis=2)
        ln[ln < 1e-6] = 1
        nrm_s = nrm_s / ln[:, :, None]
        ndot = np.clip((nrm_s * light).sum(2), 0, 1)
        shade = 0.38 + 0.62 * ndot
        img[hit] = np.clip(albedo[hit] * shade[hit, None], 0, 255).astype(np.uint8)
        Image.fromarray(img).save(out_dir / f"{name}.png")
        print("preview", name, img.shape)


def ctypes_float():
    import ctypes
    return ctypes.POINTER(ctypes.c_float)


def ctypes_int():
    import ctypes
    return ctypes.POINTER(ctypes.c_int)


def main():
    dll = load_raster()
    gltf, blob = read_glb(SRC)
    prim = gltf["meshes"][0]["primitives"][0]
    pos = accessor(gltf, blob, prim["attributes"]["POSITION"]).astype(np.float32)
    nrm = accessor(gltf, blob, prim["attributes"]["NORMAL"]).astype(np.float32)
    uv = accessor(gltf, blob, prim["attributes"]["TEXCOORD_0"]).astype(np.float32)
    faces = accessor(gltf, blob, prim["indices"]).reshape(-1, 3).astype(np.int32)

    images = {}
    bin_start_views = []
    for im in gltf["images"]:
        view = gltf["bufferViews"][im["bufferView"]]
        start = view.get("byteOffset", 0)
        raw = blob[start:start + view["byteLength"]]
        images[im["name"]] = (im["bufferView"], raw)

    color = np.array(Image.open(__import__("io").BytesIO(images["Image_1"][1])).convert("RGBA"))
    orm = np.array(Image.open(__import__("io").BytesIO(images["Image_2"][1])).convert("RGB"))
    S = color.shape[0]
    if color.shape[1] != S:
        raise SystemExit("expected a square body texture")

    v0, v1, v2 = pos[faces[:, 0]], pos[faces[:, 1]], pos[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    length = np.linalg.norm(fn, axis=1)
    length[length < 1e-8] = 1
    fn /= length[:, None]
    center = (v0 + v1 + v2) / 3
    score = fn[:, 0] * center[:, 0] + fn[:, 2] * center[:, 2] + fn[:, 1] * np.maximum(center[:, 1], 0)

    H, W = color.shape[:2]
    ui = np.clip((uv[:, 0] * (W - 1)).astype(np.int32), 0, W - 1)
    vi = np.clip(((1 - uv[:, 1]) * (H - 1)).astype(np.int32), 0, H - 1)
    rgb = color[vi, ui].astype(np.float32)
    lum = rgb[:, :3].mean(1)
    chroma = rgb[:, :3].max(1) - rgb[:, :3].min(1)
    metal = orm[vi, ui, 2].astype(np.float32)
    paintish = (lum >= LUM_LO - 15) & (lum <= LUM_HI + 10) & (chroma <= CHROMA_MAX + 10) & (metal <= METAL_MAX + 20)
    keep = (score > 10) & (center[:, 1] > 10) & paintish[faces].any(1)
    use = np.where(keep)[0]
    print("triangles rasterized", len(use), "of", len(faces))

    pix_uv = np.zeros_like(uv)
    pix_uv[:, 0] = np.clip(uv[:, 0], 0, 1) * (S - 1)
    pix_uv[:, 1] = (1 - np.clip(uv[:, 1], 0, 1)) * (S - 1)
    out_pos = np.zeros((S, S, 3), np.float32)
    out_nrm = np.zeros((S, S, 3), np.float32)
    out_score = np.zeros((S, S), np.float32)
    idx = np.ascontiguousarray(faces[use])
    sc = np.ascontiguousarray(score[use].astype(np.float32))
    dll.raster_uv(
        np.ascontiguousarray(pix_uv).ctypes.data_as(ctypes_float()),
        np.ascontiguousarray(pos).ctypes.data_as(ctypes_float()),
        np.ascontiguousarray(nrm).ctypes.data_as(ctypes_float()),
        idx.ctypes.data_as(ctypes_int()),
        sc.ctypes.data_as(ctypes_float()),
        int(len(use)),
        out_pos.ctypes.data_as(ctypes_float()),
        out_nrm.ctypes.data_as(ctypes_float()),
        out_score.ctypes.data_as(ctypes_float()),
        S,
    )
    painted, n_paint, badge_px = paint_body(color, orm, out_pos, out_nrm, out_score)
    print("paint texels", n_paint, "changed", painted_stats(color, painted), "badge", badge_px)

    import io
    buf = io.BytesIO()
    Image.fromarray(painted).save(buf, format="PNG", optimize=True)
    png = buf.getvalue()

    blobs = []
    for view in gltf["bufferViews"]:
        start = view.get("byteOffset", 0)
        blobs.append(blob[start:start + view["byteLength"]])
    color_view = images["Image_1"][0]
    blobs[color_view] = png

    roof = pos[(np.abs(pos[:, 0]) < 4) & (np.abs(pos[:, 2] - BEACON_Z) < 4) & (nrm[:, 1] > 0.75) & (pos[:, 1] > 60)]
    roof_y = float(np.median(roof[:, 1])) if len(roof) else 65.30
    print("roof Y", roof_y)
    top = add_beacon(gltf, blobs, roof_y)
    old_top = float(pos[:, 1].max())
    # The game scales the whole file to the car file's height. Grow that height
    # by the beacon so the body stays the size it was.
    scale_h = 1.226 * (top / old_top)
    print("beacon top", top, "model height", round(scale_h, 3))

    DST.write_bytes(pack(gltf, blobs))
    text = CAR.read_text()
    CAR.write_text(text.replace('"height": 1.226', '"height": %.3f' % scale_h, 1))
    print("wrote", DST, "bytes", DST.stat().st_size)

    if "--preview" in sys.argv:
        chrome, red = beacon_mesh(roof_y)
        extra = []
        for mesh, rgb_v in ((chrome, (0.78, 0.79, 0.82)), (red, (0.85, 0.02, 0.02))):
            p, n, u, f = mesh
            u = np.full((len(p), 2), -1.0, np.float32)
            c = np.tile(np.array(rgb_v, np.float32), (len(p), 1))
            extra.append((p, n, u, c, f.reshape(-1, 3).astype(np.int32)))
        render_views(dll, pos, nrm, uv, faces, painted, extra, ROOT / ".tmp-police-preview")


def painted_stats(before, after):
    changed = np.any(before[:, :, :3] != after[:, :, :3], axis=2).sum()
    return int(changed)


if __name__ == "__main__":
    main()
