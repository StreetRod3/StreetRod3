"""Exact low-facet meshes for engine parts that SolidCraft would mesh too finely or that
need to stay round: bores, pistons, valves, lifters, holes' dark floors, ports.

Everything is in inches in the engine scripts' design frame (+X back, +Y right, +Z up);
each function returns (positions, normals, indices) with faces turned to their normals.
merge() puts several into one mesh, and to_mm() hands a {name: mesh} over to the scripts'
millimeter bodies.
"""
import math

import numpy as np


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def frame(axis):
    """Two unit vectors square to axis and to each other."""
    a = unit(axis)
    e1 = unit(np.cross(a, [0.0, 0.0, 1.0]) if abs(a[2]) < 0.9 else np.cross(a, [1.0, 0.0, 0.0]))
    return e1, np.cross(a, e1)


def orient(p, nrm, tris):
    """Drop degenerate triangles and turn each to face along its corners' normals."""
    p, nrm = np.asarray(p, float), np.asarray(nrm, float)
    out = []
    for t in tris:
        a, b, c = p[t[0]], p[t[1]], p[t[2]]
        fn = np.cross(b - a, c - a)
        if np.linalg.norm(fn) < 1e-12:
            continue
        out.append(t if fn @ (nrm[t[0]] + nrm[t[1]] + nrm[t[2]]) >= 0 else [t[0], t[2], t[1]])
    return p, nrm, np.array(out, dtype=np.uint32).ravel()


def merge(pieces):
    ps, ns, ix, off = [], [], [], 0
    for p, n, i in pieces:
        ps.append(p)
        ns.append(n)
        ix.append(i + off)
        off += len(p)
    return np.vstack(ps), np.vstack(ns), np.concatenate(ix)


def disc(center, normal, r, n=16):
    """A flat round n-gon facing along normal."""
    nrm = unit(normal)
    e1, e2 = frame(nrm)
    c = np.asarray(center, float)
    rim = [c + r * (math.cos(t) * e1 + math.sin(t) * e2) for t in np.linspace(0, 2 * math.pi, n, endpoint=False)]
    tris = [[0, 1 + k, 1 + (k + 1) % n] for k in range(n)]
    return orient(np.vstack([c] + rim), np.tile(nrm, (n + 1, 1)), tris)


def annulus(center, normal, r0, r1, n=16):
    """A flat ring facing along normal between radii r0 and r1."""
    nrm = unit(normal)
    e1, e2 = frame(nrm)
    c = np.asarray(center, float)
    ts = np.linspace(0, 2 * math.pi, n, endpoint=False)
    p = [c + r * (math.cos(t) * e1 + math.sin(t) * e2) for r in (r0, r1) for t in ts]
    tris = []
    for k in range(n):
        k2 = (k + 1) % n
        tris += [[k, n + k, n + k2], [k, n + k2, k2]]
    return orient(np.array(p), np.tile(nrm, (2 * n, 1)), tris)


def tube_wall(base, axis, r, length, n=24, inward=False):
    """The side of a round prism from base along axis, flat-faced, facing out (a piston, a
    lifter) or in (a bore)."""
    a = unit(axis)
    e1, e2 = frame(a)
    base = np.asarray(base, float)
    p, nrm, tris = [], [], []
    for k in range(n):
        t0, t1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        mid = (t0 + t1) / 2
        out = (math.cos(mid) * e1 + math.sin(mid) * e2) * (-1 if inward else 1)
        b = len(p)
        for t, h in ((t0, 0.0), (t1, 0.0), (t1, length), (t0, length)):
            p.append(base + r * (math.cos(t) * e1 + math.sin(t) * e2) + a * h)
            nrm.append(out)
        tris += [[b, b + 1, b + 2], [b, b + 2, b + 3]]
    return orient(np.array(p), np.array(nrm), tris)


def cylinder(base, axis, r, length, n=24):
    """A round bar from base along axis, its far end capped."""
    a = unit(axis)
    return merge([tube_wall(base, a, r, length, n), disc(np.asarray(base, float) + a * length, a, r, n)])


def rounded_rect(center, normal, along, half_len, half_wid, r, seg=4):
    """A flat rounded rectangle facing along normal, its length along `along`."""
    nrm, u = unit(normal), unit(along)
    u = unit(u - (u @ nrm) * nrm)
    v = np.cross(nrm, u)
    c = np.asarray(center, float)
    r = min(r, half_len, half_wid)
    corners = [(half_len - r, half_wid - r, 0), (-half_len + r, half_wid - r, 90),
               (-half_len + r, -half_wid + r, 180), (half_len - r, -half_wid + r, 270)]
    rim = [c + (cx + r * math.cos(math.radians(a0 + 90 * k / seg))) * u
           + (cy + r * math.sin(math.radians(a0 + 90 * k / seg))) * v
           for cx, cy, a0 in corners for k in range(seg + 1)]
    m = len(rim)
    tris = [[0, 1 + k, 1 + (k + 1) % m] for k in range(m)]
    return orient(np.vstack([c] + rim), np.tile(nrm, (m + 1, 1)), tris)


def piston_depth(angle, stroke, rod, clear=0.03):
    """How far a piston's crown is below the deck with its crank throw angle (degrees)
    from top dead center along its bore."""
    r, t = stroke / 2, math.radians(angle)
    return clear + r * (1 - math.cos(t)) + rod - math.sqrt(rod ** 2 - (r * math.sin(t)) ** 2)


def bore_and_piston(center, axis, bore, depth, cut, n=36):
    """A bore's machined wall from the deck at center down cut along -axis, and the piston
    down it at depth: (wall, piston)."""
    a = unit(axis)
    apothem = bore / 2 * math.cos(math.pi / n)
    c = np.asarray(center, float)
    wall = tube_wall(c - a * cut, a, apothem - 0.004, cut, n, inward=True)
    top = c - a * depth
    r = apothem - 0.03
    piston = merge([disc(top, a, r, n), tube_wall(top - a * 1.0, a, r, 1.0, n)])
    return wall, piston


def to_mm(meshes):
    """{name: mesh in inches} as {name: mesh in millimeters}."""
    return {name: (p * 25.4, nrm, i) for name, (p, nrm, i) in meshes.items()}
