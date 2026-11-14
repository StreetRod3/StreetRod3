#!/usr/bin/env python3
"""Make the 1956 Corvette's speedometer a round gauge in the dash's round speedometer.

    python3 tools/c56_round_speedo.py IN.glb OUT.glb

The interior mesh of sr1-c56.glb has a round speedometer modeled in the dash in front of
the driver: a black face with a hub and a fixed needle, an inner chrome ring and an outer
chrome ring. The car dashboard GLBs (efc79f0) put a half-round pod
(dash_speedo_arch_160_pod) in front of it, with the round dial picture squashed onto a
half disc. This replaces that pod with dash_speedo_arch_270_pod:

- The face is a full disc that fills the outer chrome ring, standing just proud of the
  inner ring, so it covers the modeled face, inner ring and fixed needle.
- The dial picture (tex_c56_speedo) is moved up so its middle is the image's middle,
  and the bottom of its ring, which ran off the image, is drawn in from the ring's own
  shading. It is mapped onto the face without stretching.
- The pod's bezel goes: the modeled outer chrome ring is the bezel.
- The dial is spread over 270 degrees: 0 down at the lower left, 160 at the lower
  right, 80 at the top. The ticks are drawn again at their new angles, the numbers are
  moved round to theirs, upright. The pod is arch_270, so the needle sweeps 270 degrees
  (car_body_motion.gd reads the sweep from the pod's name); it rests on 0 and is scaled
  to the smaller dial.
- The modeled gauge was squashed by the car's resize (db4ae25: width x0.801, height
  x0.870), so its chrome rings were ellipses, taller than wide. Its vertices are moved
  back to round, in height, about the gauge's middle; past the outer ring the change
  fades out, and the steering column in front of the gauge is left alone.

GAUGE_CENTER, GAUGE_NORMAL and the radii were measured on the interior mesh, in model
units. The whole binary buffer is rewritten without the old face, bezel and picture.
"""
import io
import json
import math
import struct
import sys

import numpy as np
from PIL import Image

OLD_POD = 'dash_speedo_arch_160_pod'
NEW_POD = 'dash_speedo_arch_270_pod'
INTERIOR = 'vette-1956-interior'
# The modeled gauge: its hub's middle, the way its face looks (toward the driver).
GAUGE_CENTER = np.array([15.6195, 38.4635, 9.5922])
GAUGE_NORMAL = np.array([0.0, 0.06897, -0.99762])
# Inside of the outer chrome ring; the inner ring stands 0.15 proud of the modeled face.
FACE_RADIUS = 2.5
FACE_PROUD = 0.18
FACE_SEGMENTS = 64
# The pod's own layout, kept from efc79f0: face plane and needle below the pod's origin.
FACE_Y = -0.4635
# Needle tip into the long ticks. In the model it rests 10 degrees above the dial's
# horizontal; it is turned down to 0, DIAL_START degrees below the horizontal.
NEEDLE_LENGTH = 2.2
NEEDLE_MODEL_REST_DEG = 10.0
# The resize's squash, undone in height: full inside UNSQUASH_INNER (in the gauge's
# round radius), none past UNSQUASH_OUTER, nothing more than UNSQUASH_FRONT in front.
UNSQUASH = 0.801 / 0.870
UNSQUASH_INNER = 3.25
UNSQUASH_OUTER = 3.6
UNSQUASH_FRONT = -1.0
# The dial picture's ring: middle at pixel (256, 360) of 512, outer radius 236.
PIC_SIZE = 512
PIC_CENTER = (256.0, 360.0)
PIC_RADIUS = 236.0
# The picture's dial: 17 ticks 11.25 degrees apart (0 to 160 by 10), the long ones at
# every number, read once the picture is centered. The hub is inside HUB_RADIUS, the
# ring outside RING_INNER; the numbers lie between the hub and the ticks.
OLD_SWEEP = 180.0
NEW_SWEEP = 270.0
DIAL_START = (NEW_SWEEP - 180.0) / 2
TICKS = 17
LONG_TICK = (174.0, 235.0, 5.0)
SHORT_TICK = (196.0, 235.0, 4.0)
TICK_COLOR = (245, 248, 252)
HUB_RADIUS = 111.0
RING_INNER = 228.0
# The numbers 0 to 160, boxes in the centered picture (left, top, right, bottom). 80
# and 100 share a column of pixels, so their boxes overlap by one.
LABELS = [
    (110, 241, 132, 271), (109, 190, 155, 220), (138, 146, 184, 176),
    (182, 117, 228, 147), (233, 106, 278, 136), (277, 117, 342, 147),
    (320, 146, 386, 176), (349, 190, 415, 220), (360, 241, 426, 271),
]
# The numbers are white; the hub's outline, which some cross, is grey.
LABEL_BRIGHT = 230


def recenter_picture(png):
    src = np.asarray(Image.open(io.BytesIO(png)).convert('RGB')).astype(np.float64)
    size = PIC_SIZE
    shift = PIC_CENTER[1] - size / 2
    background = src[8, 8]
    # The ring's shading across its width, read along a line below the horizontal,
    # where the dial has no ticks.
    ang = math.radians(200.0)
    radii = np.arange(150.0, 256.0, 0.25)
    profile = []
    for r in radii:
        x = PIC_CENTER[0] + r * math.cos(ang)
        y = PIC_CENTER[1] - r * math.sin(ang)
        x0, y0 = int(math.floor(x)), int(math.floor(y))
        fx, fy = x - x0, y - y0
        if x0 < 0 or y0 + 1 >= src.shape[0]:
            profile.append(background)
            continue
        p = (src[y0, x0] * (1 - fx) * (1 - fy) + src[y0, x0 + 1] * fx * (1 - fy)
             + src[y0 + 1, x0] * (1 - fx) * fy + src[y0 + 1, x0 + 1] * fx * fy)
        profile.append(p)
    profile = np.array(profile)
    out = np.empty((size, size, 3))
    ys, xs = np.mgrid[0:size, 0:size]
    r = np.hypot(xs + 0.5 - size / 2, ys + 0.5 - size / 2)
    drawn = np.empty_like(out)
    for c in range(3):
        drawn[..., c] = np.interp(r, radii, profile[:, c], left=background[c], right=background[c])
    src_y = ys + int(shift)
    inside = src_y < src.shape[0]
    out[inside] = src[src_y[inside], xs[inside]]
    # Below the hub nothing but the ring and the background: draw from the image's old
    # bottom edge down, blending in over a few rows so no seam shows.
    seam = src.shape[0] - int(shift)
    blend = np.clip((ys - (seam - 24)) / 24.0, 0.0, 1.0)[..., None]
    lower = (r > 120)[..., None] & (ys >= seam - 24)[..., None]
    out = np.where(lower, out * (1 - blend) + drawn * blend, out)
    out[~inside] = drawn[~inside]
    buf = io.BytesIO()
    Image.fromarray(np.clip(np.rint(out), 0, 255).astype(np.uint8)).save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def dial_point(r, deg, size):
    """A point r pixels from the middle, deg degrees from the 0 side, over the top."""
    t = math.radians(deg)
    return size / 2 - r * math.cos(t), size / 2 - r * math.sin(t)


def respace_dial(png):
    """Spread the centered dial's ticks and numbers from OLD_SWEEP over NEW_SWEEP."""
    from PIL import ImageDraw
    src = np.asarray(Image.open(io.BytesIO(png)).convert('RGB'))
    size = src.shape[0]
    background = src[8, 8]
    ys, xs = np.mgrid[0:size, 0:size]
    r = np.hypot(xs + 0.5 - size / 2, ys + 0.5 - size / 2)
    deg = np.degrees(np.arctan2(size / 2 - (ys + 0.5), size / 2 - (xs + 0.5)))
    out = src.copy()
    out[(r > HUB_RADIUS) & (r < RING_INNER)] = background

    def new_deg(old):
        return -DIAL_START + old * NEW_SWEEP / OLD_SWEEP

    # Numbers: the bright pixels in each LABELS box move round the middle together,
    # upright, kept clear of the hub and inside the ticks. Some 1s lie over the hub's
    # outline, which is filled back in from the hub's lower half (it has no numbers, and
    # the hub's stripes are upright, so it mirrors).
    bright = src.astype(int).min(2) > LABEL_BRIGHT
    boxes = []
    for x0, y0, x1, y1 in LABELS:
        box = np.zeros_like(bright)
        box[y0:y1, x0:x1] = True
        boxes.append(bright & box)
    under = np.any(boxes, 0)
    hub = under & (r <= HUB_RADIUS)
    out[hub] = src[size - 1 - ys[hub], xs[hub]]
    for k, (x0, y0, x1, y1) in enumerate(LABELS):
        py, px = np.nonzero(boxes[k])
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        rad = math.hypot(cx - size / 2, cy - size / 2)
        d = new_deg(math.degrees(math.atan2(size / 2 - cy, size / 2 - cx)))
        # The radius that clears the hub, and the one that keeps inside the long ticks.
        # Near the horizontal a wide number fits only over the hub's outline, as in the
        # picture as drawn; otherwise it goes midway.
        def reach(rad):
            nx, ny = dial_point(rad, d, size)
            dx, dy = int(round(nx - cx)), int(round(ny - cy))
            dist = np.hypot(px + dx + 0.5 - size / 2, py + dy + 0.5 - size / 2)
            return dist.min(), dist.max(), dx, dy
        radii = np.arange(100.0, 180.0, 0.5)
        clear = [q for q in radii if reach(q)[0] >= HUB_RADIUS + 3 and reach(q)[1] <= LONG_TICK[0] - 3]
        if clear:
            rad = (clear[0] + clear[-1]) / 2
        else:
            rad = max(q for q in radii if reach(q)[1] <= LONG_TICK[0] - 3)
        _, _, dx, dy = reach(rad)
        out[py + dy, px + dx] = src[py, px]

    # Ticks, drawn four times over size and brought down, for smooth edges.
    scale = 4
    big = Image.new('L', (size * scale, size * scale), 0)
    draw = ImageDraw.Draw(big)
    for k in range(TICKS):
        inner, outer, width = LONG_TICK if k % 2 == 0 else SHORT_TICK
        d = new_deg(k * OLD_SWEEP / (TICKS - 1))
        t = math.radians(d)
        # Across the tick, square to its line out from the middle.
        ox, oy = math.sin(t) * width / 2, -math.cos(t) * width / 2
        a = dial_point(inner, d, size)
        b = dial_point(outer, d, size)
        corners = [(a[0] + ox, a[1] + oy), (b[0] + ox, b[1] + oy), (b[0] - ox, b[1] - oy), (a[0] - ox, a[1] - oy)]
        draw.polygon([(x * scale, y * scale) for x, y in corners], fill=255)
    cover = np.asarray(big.resize((size, size), Image.LANCZOS)).astype(np.float64)[..., None] / 255.0
    cover = np.where((r < RING_INNER)[..., None], cover, 0.0)
    out = out * (1 - cover) + np.array(TICK_COLOR) * cover
    buf = io.BytesIO()
    Image.fromarray(np.clip(np.rint(out), 0, 255).astype(np.uint8)).save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def unsquash_gauge(gltf, binary):
    """Bring the modeled gauge's chrome rings back to round, in the interior mesh."""
    node = next(n for n in gltf['nodes'] if n.get('name') == INTERIOR)
    assert not any(k in node for k in ('translation', 'rotation', 'scale', 'matrix'))
    moved = 0
    for prim in gltf['meshes'][node['mesh']]['primitives']:
        views = {}
        for key in ('POSITION', 'NORMAL'):
            a = gltf['accessors'][prim['attributes'][key]]
            assert a['componentType'] == 5126 and a['type'] == 'VEC3'
            v = gltf['bufferViews'][a['bufferView']]
            start = v.get('byteOffset', 0) + a.get('byteOffset', 0)
            stride = v.get('byteStride', 12)
            views[key] = (a, start, stride)
        a, start, stride = views['POSITION']
        pos = np.array([struct.unpack_from('<3f', binary, start + i * stride) for i in range(a['count'])])
        d = pos - GAUGE_CENTER
        rho = np.hypot(d[:, 0], d[:, 1] * UNSQUASH)
        w = np.clip((UNSQUASH_OUTER - rho) / (UNSQUASH_OUTER - UNSQUASH_INNER), 0.0, 1.0)
        w[d[:, 2] < UNSQUASH_FRONT] = 0.0
        s = 1.0 - (1.0 - UNSQUASH) * w
        hit = np.nonzero(w > 0)[0]
        for i in hit:
            p = pos[i].copy()
            p[1] = GAUGE_CENTER[1] + d[i, 1] * s[i]
            struct.pack_into('<3f', binary, start + i * stride, *p.astype(np.float32))
            pos[i] = p
        a['min'] = pos.min(0).astype(np.float32).tolist()
        a['max'] = pos.max(0).astype(np.float32).tolist()
        na, nstart, nstride = views['NORMAL']
        for i in hit:
            n = np.array(struct.unpack_from('<3f', binary, nstart + i * nstride))
            n[1] /= s[i]
            length = np.linalg.norm(n)
            if length > 0:
                struct.pack_into('<3f', binary, nstart + i * nstride, *(n / length).astype(np.float32))
        moved += len(hit)
    return moved


def quat_x(angle):
    return [math.sin(angle / 2), 0.0, 0.0, math.cos(angle / 2)]


def quat_y(angle):
    return [0.0, math.sin(angle / 2), 0.0, math.cos(angle / 2)]


def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, 'rb').read()
    jlen, = struct.unpack('<I', data[12:16])
    gltf = json.loads(data[20:20 + jlen])
    bin_start = 20 + jlen + 8
    blen, = struct.unpack('<I', data[20 + jlen:24 + jlen])
    binary = bytearray(data[bin_start:bin_start + blen])
    assert len(gltf['buffers']) == 1

    def view_bytes(index):
        v = gltf['bufferViews'][index]
        return binary[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]

    nodes = gltf['nodes']
    by_name = {n.get('name'): i for i, n in enumerate(nodes)}
    pod_i = by_name[OLD_POD]
    pod = nodes[pod_i]
    face_i = by_name[OLD_POD + '_face']
    bezel_i = by_name[OLD_POD + '_bezel']
    needle_i = by_name['speedo_needle']
    assert sorted(pod['children']) == sorted([bezel_i, face_i, needle_i]), pod['children']

    # Pod: turned so its face looks the way the modeled gauge does, face centered on it.
    n = GAUGE_NORMAL / np.linalg.norm(GAUGE_NORMAL)
    # Turning the pod by a about X takes its face's normal (0, -1, 0) to (0, -cos a, -sin a).
    a = math.atan2(-n[2], -n[1])
    face_center = GAUGE_CENTER + FACE_PROUD * n
    pod['name'] = NEW_POD
    pod['rotation'] = quat_x(a)
    pod['translation'] = (face_center + FACE_Y * n).tolist()
    pod['children'] = [face_i, needle_i]

    needle = nodes[needle_i]
    needle_mesh = gltf['meshes'][needle['mesh']]
    tip = 0.0
    for prim in needle_mesh['primitives']:
        a_pos = gltf['accessors'][prim['attributes']['POSITION']]
        tip = max(tip, a_pos['max'][0])
    s = NEEDLE_LENGTH / tip
    needle['scale'] = [s, s, s]
    needle['rotation'] = quat_y(math.radians(-(NEEDLE_MODEL_REST_DEG + DIAL_START)))

    # New face: a fan of FACE_SEGMENTS triangles about the middle, +X toward 0, -Z up.
    face = nodes[face_i]
    face['name'] = NEW_POD + '_face'
    old_prim = gltf['meshes'][face['mesh']]['primitives'][0]
    normal_acc = gltf['accessors'][old_prim['attributes']['NORMAL']]
    old_normal = struct.unpack_from('<3f', view_bytes(normal_acc['bufferView']), normal_acc.get('byteOffset', 0))
    pos = [(0.0, FACE_Y, 0.0)]
    for k in range(FACE_SEGMENTS):
        t = 2 * math.pi * k / FACE_SEGMENTS
        pos.append((FACE_RADIUS * math.cos(t), FACE_Y, -FACE_RADIUS * math.sin(t)))
    pos = np.array(pos, np.float32)
    k_uv = PIC_RADIUS / PIC_SIZE / FACE_RADIUS
    uv = np.stack([0.5 - pos[:, 0] * k_uv, 0.5 + pos[:, 2] * k_uv], 1).astype(np.float32)
    nrm = np.tile(np.array(old_normal, np.float32), (len(pos), 1))
    idx = []
    for k in range(FACE_SEGMENTS):
        idx += [0, 1 + k, 1 + (k + 1) % FACE_SEGMENTS]
    idx = np.array(idx, np.uint16)

    # Rebuild the binary: every view still referenced, then the new face and picture.
    pic_image_i = next(i for i, im in enumerate(gltf['images']) if im.get('name') == 'tex_c56_speedo')
    pic_png = respace_dial(recenter_picture(view_bytes(gltf['images'][pic_image_i]['bufferView'])))
    moved = unsquash_gauge(gltf, binary)
    for key in ('POSITION', 'NORMAL', 'TEXCOORD_0'):
        gltf['accessors'][old_prim['attributes'][key]]['_drop'] = True
    gltf['accessors'][old_prim['indices']]['_drop'] = True
    bezel_mesh = gltf['meshes'][nodes[bezel_i]['mesh']]
    for prim in bezel_mesh['primitives']:
        for acc in list(prim['attributes'].values()) + [prim.get('indices')]:
            if acc is not None:
                gltf['accessors'][acc]['_drop'] = True

    new_bin = bytearray()
    new_views = []

    def add_view(raw, target=None):
        while len(new_bin) % 4:
            new_bin.append(0)
        view = {'buffer': 0, 'byteOffset': len(new_bin), 'byteLength': len(raw)}
        if target is not None:
            view['target'] = target
        new_bin.extend(raw)
        new_views.append(view)
        return len(new_views) - 1

    view_map = {}
    for i, v in enumerate(gltf['bufferViews']):
        users = [a for a in gltf['accessors'] if a.get('bufferView') == i and not a.get('_drop')]
        used_by_image = any(im.get('bufferView') == i for j, im in enumerate(gltf['images']) if j != pic_image_i)
        if users or used_by_image:
            view_map[i] = add_view(view_bytes(i), v.get('target'))
            if 'byteStride' in v:
                new_views[-1]['byteStride'] = v['byteStride']

    # Drop the old accessors; keep every other accessor's index by remapping.
    acc_map = {}
    accessors = []
    for i, a in enumerate(gltf['accessors']):
        if a.get('_drop'):
            continue
        a = dict(a)
        a['bufferView'] = view_map[a['bufferView']]
        acc_map[i] = len(accessors)
        accessors.append(a)

    def add_accessor(arr, ctype, atype, target):
        v = add_view(arr.tobytes(), target)
        a = {'bufferView': v, 'componentType': ctype, 'count': len(arr), 'type': atype}
        if atype != 'SCALAR':
            a['min'] = arr.min(0).tolist()
            a['max'] = arr.max(0).tolist()
        accessors.append(a)
        return len(accessors) - 1

    for mesh in gltf['meshes']:
        for prim in mesh['primitives']:
            if prim is old_prim or mesh is bezel_mesh:
                continue
            prim['attributes'] = {k: acc_map[v] for k, v in prim['attributes'].items()}
            if 'indices' in prim:
                prim['indices'] = acc_map[prim['indices']]
    old_prim['attributes'] = {
        'POSITION': add_accessor(pos, 5126, 'VEC3', 34962),
        'NORMAL': add_accessor(nrm, 5126, 'VEC3', 34962),
        'TEXCOORD_0': add_accessor(uv, 5126, 'VEC2', 34962),
    }
    old_prim['indices'] = add_accessor(idx, 5123, 'SCALAR', 34963)
    gltf['meshes'][face['mesh']]['name'] = NEW_POD + '_face'

    for j, im in enumerate(gltf['images']):
        if j == pic_image_i:
            im['bufferView'] = add_view(pic_png)
        elif 'bufferView' in im:
            im['bufferView'] = view_map[im['bufferView']]
    gltf['accessors'] = accessors
    gltf['bufferViews'] = new_views

    # Remove the bezel node and its mesh, renumbering what points past them.
    bezel_mesh_i = nodes[bezel_i]['mesh']
    del gltf['meshes'][bezel_mesh_i]
    for node in nodes:
        if node.get('mesh', -1) > bezel_mesh_i:
            node['mesh'] -= 1
    del nodes[bezel_i]
    for node in nodes:
        if 'children' in node:
            node['children'] = [c - (c > bezel_i) for c in node['children'] if c != bezel_i]
    for scene in gltf['scenes']:
        scene['nodes'] = [c - (c > bezel_i) for c in scene['nodes'] if c != bezel_i]
    assert 'skins' not in gltf and 'animations' not in gltf

    while len(new_bin) % 4:
        new_bin.append(0)
    gltf['buffers'][0]['byteLength'] = len(new_bin)
    js = json.dumps(gltf, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    total = 12 + 8 + len(js) + 8 + len(new_bin)
    out = (struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(js), 0x4E4F534A) + js
           + struct.pack('<II', len(new_bin), 0x004E4942) + bytes(new_bin))
    open(dst, 'wb').write(out)
    print(f'{dst}: {NEW_POD}, face radius {FACE_RADIUS}, needle x{s:.3f}, {moved} gauge vertices rounded, {len(binary)} -> {len(new_bin)} bytes of data')


if __name__ == '__main__':
    main()
