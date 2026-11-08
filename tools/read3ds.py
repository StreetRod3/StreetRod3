"""Reads the meshes and materials out of a 3D Studio (.3DS) file.

    python3 tools/read3ds.py FILE.3DS

lists each object (vertex and face counts, bounds, materials) and each material. As a
module, `load(path)` returns (objects, materials): an object is a dict of `name`,
`verts` (x, y, z tuples in the file's world space), `faces` (index triples), `uvs`,
`groups` (material name to the faces that use it) and `smooth` (each face's smoothing
group bits, empty when the file has none); a material is a dict of `name` and
`diffuse` (and `ambient`, `specular`, `texture` when the file has them).

The vertices are where the mesh was built. 3ds Max also writes a keyframer node per
object, and its pivot can move the object somewhere else: `place(path, objects)` moves
each object's vertices to where the keyframer puts it at frame 0, which is where the
file's author saw it. A model whose parts look scattered needs it.
"""
import math
import struct
import sys


def _cstr(b, o):
    e = b.index(0, o)
    return b[o:e].decode('latin-1'), e + 1


def _chunks(b, o, end):
    while o + 6 <= end:
        cid, ln = struct.unpack_from('<HI', b, o)
        if ln < 6:
            break
        yield cid, o + 6, min(o + ln, end)
        o += ln


def _colour(b, o, end):
    for cid, s, e in _chunks(b, o, end):
        if cid in (0x0010, 0x0013):
            return list(struct.unpack_from('<3f', b, s))
        if cid in (0x0011, 0x0012):
            return [x / 255 for x in b[s:s + 3]]
    return None


def load(path):
    b = open(path, 'rb').read()
    objs, mats = [], {}

    def material(s, e):
        m = {}
        for cid, s2, e2 in _chunks(b, s, e):
            if cid == 0xA000:
                m['name'] = _cstr(b, s2)[0]
            elif cid == 0xA010:
                m['ambient'] = _colour(b, s2, e2)
            elif cid == 0xA020:
                m['diffuse'] = _colour(b, s2, e2)
            elif cid == 0xA030:
                m['specular'] = _colour(b, s2, e2)
            elif cid == 0xA200:
                for c3, s3, e3 in _chunks(b, s2, e2):
                    if c3 == 0xA300:
                        m['texture'] = _cstr(b, s3)[0]
        mats[m.get('name', '?')] = m

    def trimesh(name, s, e):
        ob = {'name': name, 'verts': [], 'faces': [], 'uvs': [], 'groups': {}, 'smooth': []}
        for cid, s2, e2 in _chunks(b, s, e):
            if cid == 0x4110:
                n, = struct.unpack_from('<H', b, s2)
                ob['verts'] = [struct.unpack_from('<3f', b, s2 + 2 + 12 * i) for i in range(n)]
            elif cid == 0x4140:
                n, = struct.unpack_from('<H', b, s2)
                ob['uvs'] = [struct.unpack_from('<2f', b, s2 + 2 + 8 * i) for i in range(n)]
            elif cid == 0x4120:
                n, = struct.unpack_from('<H', b, s2)
                ob['faces'] = [struct.unpack_from('<3H', b, s2 + 2 + 8 * i) for i in range(n)]
                for c3, s3, e3 in _chunks(b, s2 + 2 + 8 * n, e2):
                    if c3 == 0x4130:
                        mn, q = _cstr(b, s3)
                        k, = struct.unpack_from('<H', b, q)
                        ob['groups'].setdefault(mn, []).extend(struct.unpack_from('<%dH' % k, b, q + 2))
                    elif c3 == 0x4150:
                        ob['smooth'] = list(struct.unpack_from('<%dI' % n, b, s3))
        objs.append(ob)

    def walk(o, end):
        for cid, s, e in _chunks(b, o, end):
            if cid in (0x4D4D, 0x3D3D):
                walk(s, e)
            elif cid == 0xAFFF:
                material(s, e)
            elif cid == 0x4000:
                name, p = _cstr(b, s)
                for c2, s2, e2 in _chunks(b, p, e):
                    if c2 == 0x4100:
                        trimesh(name, s2, e2)

    walk(0, len(b))
    return objs, mats


def _first_key(b, s, n):
    """The first key of a keyframer track: `n` floats."""
    q = s + 14
    flags, = struct.unpack_from('<H', b, q + 4)
    q += 6 + 4 * bin(flags & 0x1F).count('1')
    return struct.unpack_from('<%df' % n, b, q)


def _mul(a, c):
    return [[sum(a[i][k] * c[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def _move(v):
    return [[1, 0, 0, v[0]], [0, 1, 0, v[1]], [0, 0, 1, v[2]], [0, 0, 0, 1]]


def _scale(v):
    return [[v[0], 0, 0, 0], [0, v[1], 0, 0], [0, 0, v[2], 0], [0, 0, 0, 1]]


def _turn(angle, axis):
    n = math.sqrt(sum(a * a for a in axis))
    if n < 1e-9 or abs(angle) < 1e-9:
        return _scale((1, 1, 1))
    x, y, z = (a / n for a in axis)
    c, s = math.cos(angle), math.sin(angle)
    t = 1 - c
    return [[t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0],
            [t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0],
            [t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0], [0, 0, 0, 1]]


def _invert(m):
    a = [row[:3] for row in m[:3]]
    det = (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
           + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]))
    inv = [[(a[(j + 1) % 3][(i + 1) % 3] * a[(j + 2) % 3][(i + 2) % 3]
             - a[(j + 1) % 3][(i + 2) % 3] * a[(j + 2) % 3][(i + 1) % 3]) / det for j in range(3)] for i in range(3)]
    t = [-sum(inv[i][k] * m[k][3] for k in range(3)) for i in range(3)]
    return [inv[0] + [t[0]], inv[1] + [t[1]], inv[2] + [t[2]], [0, 0, 0, 1]]


def place(path, objects):
    """Moves each object in `objects` (from `load`) to its keyframer place at frame 0."""
    b = open(path, 'rb').read()
    frames, nodes = {}, {}

    def walk(o, end):
        for cid, s, e in _chunks(b, o, end):
            if cid in (0x4D4D, 0x3D3D, 0xB000):
                walk(s, e)
            elif cid == 0x4000:
                name, p = _cstr(b, s)
                for c2, s2, e2 in _chunks(b, p, e):
                    if c2 == 0x4100:
                        for c3, s3, e3 in _chunks(b, s2, e2):
                            if c3 == 0x4160:
                                f = struct.unpack_from('<12f', b, s3)
                                frames[name] = [[f[0], f[3], f[6], f[9]], [f[1], f[4], f[7], f[10]],
                                                [f[2], f[5], f[8], f[11]], [0, 0, 0, 1]]
            elif cid == 0xB002:
                n = {'pivot': (0, 0, 0), 'pos': (0, 0, 0), 'rot': (0, 0, 0, 0), 'scl': (1, 1, 1), 'parent': -1}
                for c2, s2, e2 in _chunks(b, s, e):
                    if c2 == 0xB010:
                        n['name'], q = _cstr(b, s2)
                        n['parent'], = struct.unpack_from('<h', b, q + 4)
                    elif c2 == 0xB030:
                        n['id'], = struct.unpack_from('<h', b, s2)
                    elif c2 == 0xB013:
                        n['pivot'] = struct.unpack_from('<3f', b, s2)
                    elif c2 == 0xB020:
                        n['pos'] = _first_key(b, s2, 3)
                    elif c2 == 0xB021:
                        n['rot'] = _first_key(b, s2, 4)
                    elif c2 == 0xB022:
                        n['scl'] = _first_key(b, s2, 3)
                nodes[n.get('id', len(nodes))] = n

    walk(0, len(b))
    done = {}

    def matrix(i):
        if i not in done:
            n = nodes[i]
            m = _mul(_mul(_move(n['pos']), _turn(n['rot'][0], n['rot'][1:])), _scale(n['scl']))
            done[i] = _mul(matrix(n['parent']), m) if n['parent'] in nodes else m
        return done[i]

    by_name = {n['name']: i for i, n in nodes.items()}
    for ob in objects:
        i = by_name.get(ob['name'])
        if i is None or ob['name'] not in frames:
            continue
        m = _mul(_mul(matrix(i), _move([-x for x in nodes[i]['pivot']])), _invert(frames[ob['name']]))
        ob['verts'] = [tuple(m[r][0] * x + m[r][1] * y + m[r][2] * z + m[r][3] for r in range(3))
                       for x, y, z in ob['verts']]
    return objects


def bounds(ob):
    v = ob['verts']
    if not v:
        return (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)
    return tuple(min(p[i] for p in v) for i in range(3)), tuple(max(p[i] for p in v) for i in range(3))


if __name__ == '__main__':
    objects, materials = load(sys.argv[1])
    for ob in objects:
        lo, hi = bounds(ob)
        print('%-14s v=%6d f=%6d %s %s %s' % (ob['name'], len(ob['verts']), len(ob['faces']),
              [round(x, 1) for x in lo], [round(x, 1) for x in hi], list(ob['groups'])))
    for name, m in materials.items():
        print('material', name, m.get('diffuse'), m.get('texture', ''))
