#!/usr/bin/env python3
"""Cut the tires out of a car GLB whose wheels are welded into its body shell.

Local tool (tools/ is gitignored), for the one-mesh Tripo models named in CARS:

    python3 tools/strip_baked_wheels.py NAME IN.glb OUT.glb

IN is the model as it was with its tires on (git history has them). Removes the faces
inside each wheel's arch, closes the holes dark, and moves the bottom of the model to
Y=0. Wheels are found per corner by fitting a section through the tread. Prints what
the car file needs.
"""
import io
import json
import struct
import sys

import numpy as np
import scipy.sparse as sp
from PIL import Image
from scipy.sparse.csgraph import connected_components

# Model height in the car file before the cut, which sets the scale. `flip` bakes in the
# half turn that faces the nose to +Z. `min_part` drops loose parts below that many faces.
# Corners: (nose side z, hub y, reach along z, reach above the hub, reach below, y cap, section x).
# "cap" closes each hole with a wall and a flat disc (no real well inboard of the tire),
# "bridge" roofs the gap to the real well, "open" leaves a wheel standing clear of the body.
CARS = {
    "sr1-c56": {"height": 1.5, "flip": False, "min_part": 25000, "inner": 39.0, "section": 47.0, "wheel_x": 0.9, "well": None, "reach": 1.45,
                "front": {"z": 97.7, "y": -19.5, "mode": "cap"},
                "rear": {"z": -87.5, "y": -19.5, "mode": "cap"}},
    "sr1-fairlane-1957": {"height": 1.6, "flip": True, "min_part": 5000, "inner": 49.5, "section": 58.0, "wheel_x": 1.1, "well": 38.0, "reach": 1.3, "behind_lip": (1.12, 62.0),
                          "slats": (-32.0, -17.0, -32.0, -12.0, 63.0),
                          "front": {"z": 107.0, "y": -21.8, "r": 21.4, "top": 20.0, "cap_y": -0.5, "mode": "bridge", "pin": True},
                          "rear": {"z": -90.0, "y": -21.8, "r": 21.4, "top": 20.0, "cap_y": -15.6, "mode": "bridge", "pin": True}},
    "sr1-ford-customized-coupe-1932": {"height": 1.5, "flip": True, "min_part": 5000, "inner": 46.5, "section": 52.0, "wheel_x": 0.8, "well": 36.0, "reach": 1.3,
                                       "front": {"z": 127.2, "y": -25.77, "r": 24.27, "top": 24.27, "cap_y": None, "mode": "open", "pin": True},
                                       "rear": {"z": -107.7, "y": -25.77, "r": 24.27, "top": 18.0, "cap_y": None, "mode": "bridge", "pin": True}},
}
TOP_MARGIN = 0.25  # Cut this far outside the tread.
ARCH_END_X = 47.0  # On the Corvette the slot between tire and fender closes off inside this.


def read_glb(path, flip):
    with open(path, "rb") as f:
        f.read(12)
        n, _ = struct.unpack("<II", f.read(8))
        j = json.loads(f.read(n))
        m, _ = struct.unpack("<II", f.read(8))
        b = f.read(m)

    def acc(i):
        a = j["accessors"][i]
        v = j["bufferViews"][a["bufferView"]]
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        ct = {5126: np.float32, 5125: np.uint32}[a["componentType"]]
        k = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
        arr = np.frombuffer(b, ct, a["count"] * k, off)
        return arr.reshape(-1, k) if k > 1 else arr

    p = j["meshes"][0]["primitives"][0]
    images = []
    for im in j["images"]:
        view = j["bufferViews"][im["bufferView"]]
        start = view.get("byteOffset", 0)
        images.append(b[start:start + view["byteLength"]])
    node = j["nodes"][0]
    scale = node.get("scale", [1.0, 1.0, 1.0])[0]
    P = acc(p["attributes"]["POSITION"]).astype(np.float64) * scale
    N = acc(p["attributes"]["NORMAL"]).astype(np.float32).copy()
    if flip:
        # The half turn in the node (and for the Fairlane, its 0.6 degrees of yaw) go.
        P *= np.array([-1.0, 1.0, -1.0])
        N *= np.array([-1.0, 1.0, -1.0], dtype=np.float32)
    return {
        "json": j,
        "P": P,
        "N": N,
        "T": acc(p["attributes"]["TEXCOORD_0"]).astype(np.float32),
        "F": acc(p["indices"]).reshape(-1, 3).astype(np.int64),
        "images": images,
    }


def section(tri, val):
    d = tri[:, :, 0] - val
    s = d > 0
    m = s.any(1) & ~s.all(1)
    t, d = tri[m], d[m]
    out = []
    for a, c in ((0, 1), (1, 2), (2, 0)):
        x = (d[:, a] > 0) != (d[:, c] > 0)
        u = d[x, a] / (d[x, a] - d[x, c])
        out.append(t[x, a] + (t[x, c] - t[x, a]) * u[:, None])
    return np.concatenate(out)


def fit_ellipse(tri, sx, corner, section_x):
    """Corvette: ellipse through the tread, innermost section point per angle, skipping
    the flat contact patch and the fender above the tire."""
    pts = section(tri, sx * section_x)
    zc, yc = corner["z"], corner["y"]
    pts = pts[np.abs(pts[:, 2] - zc) < 30]
    for _ in range(8):
        d = np.hypot(pts[:, 2] - zc, pts[:, 1] - yc)
        th = np.arctan2(pts[:, 1] - yc, pts[:, 2] - zc)
        bins = np.floor((th + np.pi) / (np.pi / 36)).astype(int)
        sel = []
        for bb in np.unique(bins):
            i = np.where(bins == bb)[0]
            ii = i[np.argmin(d[i])]
            if -38 < pts[ii, 1] < -6 and 15 < d[ii] < 25:
                sel.append(ii)
        v = pts[sel]
        A = np.c_[v[:, 2] ** 2, v[:, 1] ** 2, v[:, 2], v[:, 1]]
        s = np.linalg.lstsq(A, np.ones(len(v)), rcond=None)[0]
        zc, yc = -s[2] / (2 * s[0]), -s[3] / (2 * s[1])
    k = 1 + s[2] ** 2 / (4 * s[0]) + s[3] ** 2 / (4 * s[1])
    a, b = np.sqrt(k / s[0]), np.sqrt(k / s[1])
    return zc, yc, a + TOP_MARGIN, b + TOP_MARGIN, b + TOP_MARGIN, None


def fit_circle(tri, sx, corner, section_x, bottom):
    """Circle through the lower half of the tread, above any flat contact patch."""
    pts = section(tri, sx * section_x)
    zc, yc, r = corner["z"], corner["y"], corner["r"]
    if corner.get("pin"):
        # Hub height and size are set; only find the wheel along the car, low down where
        # nothing but tire is in the way.
        for _ in range(4):
            d = np.hypot(pts[:, 2] - zc, pts[:, 1] - yc)
            v = pts[(np.abs(d - r) < 3) & (pts[:, 1] < yc - 0.7 * r) & (pts[:, 1] > bottom + 0.5)]
            zc = (v[:, 2].min() + v[:, 2].max()) / 2
        return zc, yc, r + TOP_MARGIN, corner["top"] + TOP_MARGIN, r + TOP_MARGIN, corner["cap_y"]
    for _ in range(8):
        d = np.hypot(pts[:, 2] - zc, pts[:, 1] - yc)
        v = pts[(np.abs(d - r) < 3) & (pts[:, 1] < yc + 2) & (pts[:, 1] > bottom + 1.2)]
        A = np.c_[2 * v[:, 2], 2 * v[:, 1], np.ones(len(v))]
        s = np.linalg.lstsq(A, v[:, 2] ** 2 + v[:, 1] ** 2, rcond=None)[0]
        zc, yc = s[0], s[1]
        r = np.sqrt(s[2] + zc ** 2 + yc ** 2)
    print(f"   fit from {len(v)} points, spread {np.abs(np.hypot(v[:, 2] - zc, v[:, 1] - yc) - r).std():.2f}")
    top = corner["top"] + r - corner["r"]
    return zc, yc, r + TOP_MARGIN, top + TOP_MARGIN, r + TOP_MARGIN, corner["cap_y"]


def inside_arch(c, zc, yc, a, top, under, cap_y):
    span = np.where(c[:, 1] > yc, top, under)
    rr = np.hypot((c[:, 2] - zc) / a, (c[:, 1] - yc) / span)
    return rr, cap_y


def dark_uv(data, floor_mask):
    """UV in the middle of an evenly dark patch of the floor's texture, unpainted if the
    texture has a paint mask."""
    j = data["json"]
    base = j["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    im = np.array(Image.open(io.BytesIO(data["images"][j["textures"][base]["source"]])).convert("RGBA"))
    uv = data["T"][data["F"][floor_mask, 0]]
    h, w = im.shape[:2]
    half = max(w // 64, 8)
    rng = np.random.default_rng(1)
    for limit, painted_ok in ((40, False), (40, True), (70, True), (110, True)):
        for k in rng.permutation(len(uv))[:4000]:
            x, y = int(uv[k, 0] * w), int(uv[k, 1] * h)
            if not (half <= x < w - half and half <= y < h - half):
                continue
            patch = im[y - half:y + half, x - half:x + half]
            if (painted_ok or patch[..., 3].max() == 0) and patch[..., :3].max() < limit:
                return uv[k].copy(), patch[..., :3].mean()
    raise SystemExit("no dark patch found")


def boundary_loops(F, weld):
    """Loops of open edges, as welded ids, each edge running as in its kept face."""
    e = weld[np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])]
    key = np.minimum(e[:, 0], e[:, 1]) * (weld.max() + 1) + np.maximum(e[:, 0], e[:, 1])
    _, inv, cnt = np.unique(key, return_inverse=True, return_counts=True)
    open_e = e[cnt[inv] == 1]
    nxt = {}
    for a, b in open_e:
        nxt.setdefault(int(a), []).append(int(b))
    loops = []
    while nxt:
        start = next(iter(nxt))
        loop = [start]
        cur = start
        while True:
            options = nxt.get(cur)
            if not options:
                break
            n = options.pop()
            if not options:
                del nxt[cur]
            if n == start:
                loops.append(loop)
                break
            loop.append(n)
            cur = n
    return loops


def main():
    name = sys.argv[1]
    car = CARS[name]
    data = read_glb(sys.argv[2], car["flip"])
    P, N, T, F = data["P"].copy(), data["N"], data["T"], data["F"]
    tri = P[F]
    scale = car["height"] / (P[:, 1].max() - P[:, 1].min())
    bottom_all = P[:, 1].min()

    u, weld = np.unique(np.round(P * 1000).astype(np.int64), axis=0, return_inverse=True)
    weld = weld.ravel()
    floor = (np.abs(tri[:, :, 0]).max(1) < 30) & (np.abs(tri[:, :, 2]).max(1) < 50) & (tri[:, :, 1].max(1) < bottom_all + 22)
    liner_uv, liner_rgb = dark_uv(data, floor)
    print("liner uv", liner_uv, "mean rgb", liner_rgb)

    wheels = []
    centroid = tri.mean(1)
    remove = np.zeros(len(F), bool)
    for sx in (1, -1):
        for key in ("front", "rear"):
            corner = car[key]
            if "r" in corner:
                zc, yc, a, top, under, cap_y = fit_circle(tri, sx, corner, car["section"], bottom_all)
            else:
                zc, yc, a, top, under, cap_y = fit_ellipse(tri, sx, corner, car["section"])
            print(f"corner x{sx:+d} {key}: zc {zc:.2f} yc {yc:.2f} a {a:.2f} top {top:.2f} under {under:.2f}")
            wheels.append({"sx": sx, "key": key, "zc": zc, "yc": yc, "a": a, "top": top, "under": under, "mode": corner["mode"]})
            rr, _ = inside_arch(centroid, zc, yc, a, top, under, cap_y)
            inside = (rr < 1) & (sx * centroid[:, 0] > car["inner"])
            if cap_y is not None:
                inside &= centroid[:, 1] < cap_y
            print("   faces cut", inside.sum())
            remove |= inside
    F = F[~remove]

    # Scraps the cut left hanging, and any loose part too small to be the car.
    e = weld[np.vstack([F[:, [0, 1]], F[:, [1, 2]]])]
    n = weld.max() + 1
    _, labels = connected_components(sp.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)), directed=False)
    fl = labels[weld[F[:, 0]]]
    cnt = np.bincount(fl)
    small = (cnt > 0) & (cnt <= car["min_part"])
    print("parts", (cnt > 0).sum(), "dropping", small.sum(), "with", cnt[small].sum(), "faces; kept sizes", sorted(cnt[(cnt > 0) & ~small].tolist()))
    F = F[np.isin(fl, np.where(~small)[0])]

    first_of = np.full(n, -1, np.int64)
    first_of[weld[::-1]] = np.arange(len(P))[::-1]
    new_p, new_n, new_f = [], [], []
    base = len(P)

    def add(p, nrm):
        new_p.append(p)
        new_n.append(nrm)
        return base + len(new_p) - 1

    for loop in boundary_loops(F, weld):
        pts = P[first_of[np.array(loop)]]
        mid = pts.mean(0)
        best = None
        for w in wheels:
            if w["sx"] * mid[0] > 25 and np.hypot(mid[2] - w["zc"], mid[1] - w["yc"]) < 32:
                best = w
        if best is None or len(loop) < 8:
            print(f"loop of {len(loop)} around {np.round(mid, 1)}: left open")
            continue
        sx, zc, yc, a, top = best["sx"], best["zc"], best["yc"], best["a"], best["top"]
        small_hole = np.ptp(pts[:, 1]) < 14 and np.ptp(pts[:, 2]) < 14
        kind = "disc" if small_hole or best["mode"] != "bridge" and best["mode"] != "cap" else best["mode"]
        print(f"loop of {len(loop)} around {np.round(mid, 1)}: {kind} ({sx:+d} {best['key']})")
        m = len(loop)
        if kind == "disc":
            hub = add(np.array([np.median(pts[:, 0]), pts[:, 1].mean(), pts[:, 2].mean()]), [sx, 0, 0])
            ring = [add(pts[i], [sx, 0, 0]) for i in range(m)]
            for i in range(m):
                new_f.append(face_toward(P_of(new_p, base, hub, P), P_of(new_p, base, ring[i], P), P_of(new_p, base, ring[(i + 1) % m], P), (hub, ring[i], ring[(i + 1) % m]), np.array([sx, 0, 0])))
        elif kind == "cap":
            # Wall in along X from the hole's edge, then a flat inner wall.
            x_in = sx * min((sx * pts[:, 0]).min(), car["inner"])
            hub = add(np.array([x_in, yc, zc]), [sx, 0, 0])
            radial = np.c_[np.zeros(m), (pts[:, 1] - yc) / top ** 2, (pts[:, 2] - zc) / a ** 2]
            radial /= np.linalg.norm(radial, axis=1, keepdims=True)
            outer = [add(pts[i], -radial[i]) for i in range(m)]
            inner = [add([x_in, pts[i, 1], pts[i, 2]], -radial[i]) for i in range(m)]
            cap = [add([x_in, pts[i, 1], pts[i, 2]], [sx, 0, 0]) for i in range(m)]
            for i in range(m):
                j = (i + 1) % m
                # Kept face runs loop[i] -> loop[j], so the well runs the other way.
                new_f.append((outer[j], outer[i], inner[i]))
                new_f.append((outer[j], inner[i], inner[j]))
                new_f.append((hub, cap[j], cap[i]))
        else:
            # Roof from the fender's edge across to the top of the real well: the loop is
            # those two edges, split where it turns round at each end of the arch.
            phi = np.arctan2(pts[:, 2] - zc, pts[:, 1] - yc)
            i0, i1 = int(np.argmin(phi)), int(np.argmax(phi))
            chain_a = [(i0 + k) % m for k in range((i1 - i0) % m + 1)]
            chain_b = [(i0 - k) % m for k in range((i0 - i1) % m + 1)]
            radial = np.c_[np.zeros(m), (pts[:, 1] - yc) / top ** 2, (pts[:, 2] - zc) / a ** 2]
            radial /= np.linalg.norm(radial, axis=1, keepdims=True)
            ids = [add(pts[i], -radial[i]) for i in range(m)]
            ia, ib = 0, 0
            while ia < len(chain_a) - 1 or ib < len(chain_b) - 1:
                na = phi[chain_a[ia + 1]] if ia < len(chain_a) - 1 else np.inf
                nb = phi[chain_b[ib + 1]] if ib < len(chain_b) - 1 else np.inf
                if na <= nb:
                    t = (chain_a[ia], chain_b[ib], chain_a[ia + 1])
                    ia += 1
                else:
                    t = (chain_a[ia], chain_b[ib], chain_b[ib + 1])
                    ib += 1
                center = pts[list(t)].mean(0)
                toward = np.array([0.0, yc - center[1], zc - center[2]])
                new_f.append(face_toward(pts[t[0]], pts[t[1]], pts[t[2]], (ids[t[0]], ids[t[1]], ids[t[2]]), toward))

    # The arches' inner faces carry baked tire tread, which would show behind the real
    # wheels. Those facing the axle go dark too, on their own vertices for a clean edge.
    tri_k = P[F]
    c = tri_k.mean(1)
    fn = np.cross(tri_k[:, 1] - tri_k[:, 0], tri_k[:, 2] - tri_k[:, 0])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    dark = np.zeros(len(F), bool)
    for w in wheels:
        if w["mode"] == "open":
            continue
        sx, zc, yc, a, top, under = w["sx"], w["zc"], w["yc"], w["a"], w["top"], w["under"]
        rr, _ = inside_arch(c, zc, yc, a, top, under, None)
        rr_round = np.hypot((c[:, 2] - zc) / a, (c[:, 1] - yc) / a)
        inner = car["well"] if car["well"] is not None else car["inner"]
        near = (np.minimum(rr, rr_round) < car["reach"]) & (sx * c[:, 0] > inner)
        rad = np.c_[(c[:, 1] - yc) / under, (c[:, 2] - zc) / a]
        rad /= np.maximum(np.linalg.norm(rad, axis=1, keepdims=True), 1e-9)
        toward_axle = -(fn[:, 1] * rad[:, 0] + fn[:, 2] * rad[:, 1])
        if car["well"] is None:
            end_wall = (sx * fn[:, 0] > 0.7) & (sx * c[:, 0] < ARCH_END_X)
        else:
            end_wall = (sx * fn[:, 0] > 0.7) & (sx * c[:, 0] < car["inner"] + 1)
        dark |= near & ((toward_axle > 0.45) | end_wall)
        if "behind_lip" in car:
            # Slivers left between the tire and the fender's edge.
            reach, x_max = car["behind_lip"]
            dark |= (rr < reach) & (sx * c[:, 0] > inner) & (sx * c[:, 0] < x_max)
        if "slats" in car and w["key"] == "front":
            # The Fairlane's chrome slats behind the front tire.
            z0, z1, y0, y1, x_max = car["slats"]
            dark |= (c[:, 2] > zc + z0) & (c[:, 2] < zc + z1) & (c[:, 1] > y0) & (c[:, 1] < y1) & (sx * c[:, 0] > inner) & (sx * c[:, 0] < x_max)
    print("arch faces darkened", dark.sum())
    copies = {}
    F = F.copy()
    for fi in np.where(dark)[0]:
        for k in range(3):
            v = int(F[fi, k])
            if v not in copies:
                copies[v] = add(P[v], N[v])
            F[fi, k] = copies[v]

    P2 = np.vstack([P, np.array(new_p)])
    N2 = np.vstack([N, np.array(new_n, dtype=np.float32)])
    T2 = np.vstack([T, np.tile(liner_uv, (len(new_p), 1))])
    F2 = np.vstack([F, np.array(new_f, dtype=np.int64)])

    # Drop vertices nothing uses, bottom of the model to Y=0.
    used = np.zeros(len(P2), bool)
    used[F2.ravel()] = True
    remap = np.cumsum(used) - 1
    P2, N2, T2, F2 = P2[used], N2[used], T2[used], remap[F2]
    bottom = P2[:, 1].min()
    P2[:, 1] -= bottom
    height = P2[:, 1].max()

    write_glb(sys.argv[3], data, P2.astype(np.float32), N2.astype(np.float32), T2.astype(np.float32), F2.astype(np.uint32))

    print(f"\nverts {len(P2)} tris {len(F2)}")
    hubs = {}
    for w in wheels:
        hubs.setdefault(w["key"], []).append(w["yc"])
    hub_y = np.mean([np.mean(v) for v in hubs.values()])
    clearance = 0.34 - (hub_y - bottom) * scale
    # Where the old model's bottom sat on the ground, for moving the driver with the body.
    driver_shift = (bottom_all - bottom) * scale + clearance
    print(f"model height {height * scale:.3f} ground_clearance {clearance:.3f} driver y {driver_shift:+.3f}")
    for w in wheels:
        side = "Left" if w["sx"] < 0 else "Right"
        where = "Front" if w["key"] == "front" else "Back"
        print(f"Wheel{where}{side} [{w['sx'] * car['wheel_x']:.3f}, 0.34, {w['zc'] * scale:.3f}]  hub rise {(w['yc'] - hub_y) * scale:+.3f}")


def P_of(new_p, base, idx, P):
    return new_p[idx - base] if idx >= base else P[idx]


def face_toward(a, b, c, ids, toward):
    """The triangle `ids`, wound so that its front faces along `toward`."""
    n = np.cross(np.asarray(b) - np.asarray(a), np.asarray(c) - np.asarray(a))
    return ids if np.dot(n, toward) >= 0 else (ids[0], ids[2], ids[1])


def write_glb(path, data, P, N, T, F):
    j = data["json"]
    chunks = [F.tobytes(), P.tobytes(), N.tobytes(), T.tobytes()] + data["images"]
    views, off = [], 0
    targets = [34963, 34962, 34962, 34962] + [None] * len(data["images"])
    for c, t in zip(chunks, targets):
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(c)}
        if t:
            v["target"] = t
        views.append(v)
        off += len(c)
        off += (4 - off % 4) % 4
    blob = bytearray(off)
    for c, v in zip(chunks, views):
        blob[v["byteOffset"]:v["byteOffset"] + v["byteLength"]] = c
    j = json.loads(json.dumps(j))
    j["bufferViews"] = views
    j["buffers"] = [{"byteLength": len(blob)}]
    j["accessors"] = [
        {"bufferView": 0, "componentType": 5125, "count": int(F.size), "type": "SCALAR"},
        {"bufferView": 1, "componentType": 5126, "count": len(P), "type": "VEC3", "min": P.min(0).tolist(), "max": P.max(0).tolist()},
        {"bufferView": 2, "componentType": 5126, "count": len(N), "type": "VEC3"},
        {"bufferView": 3, "componentType": 5126, "count": len(T), "type": "VEC2"},
    ]
    j["meshes"][0]["primitives"][0].update({"indices": 0, "attributes": {"POSITION": 1, "NORMAL": 2, "TEXCOORD_0": 3}})
    for i, im in enumerate(j["images"]):
        im["bufferView"] = 4 + i
    # Scale and any half turn are in the vertices now.
    for key in ("scale", "rotation", "translation"):
        j["nodes"][0].pop(key, None)
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


if __name__ == "__main__":
    main()
