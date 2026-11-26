#!/usr/bin/env python3
"""Convert a car from Sketchfab's "Free Vehicle Archive" into a car body GLB.

    python3 -I tools/fva_to_glb.py nomad-1956 assets/cars/chevy-nomad-1956.glb
    python3 -I tools/fva_to_glb.py cadillac-1949 assets/cars/cadillac-series-62-1949.glb
    python3 -I tools/fva_to_glb.py superbird-1970 assets/cars/plymouth-superbird-1970.glb

Sources (all CC-BY-4.0, by Free Vehicle Archive, https://sketchfab.com/free-vehicle-archive):
  * "1956 - Chevrolet Bel Air Nomad",
    https://sketchfab.com/3d-models/1956-chevrolet-bel-air-nomad-efd82e3b0a5e415a921853c88e2a18ab
  * "1949 - Cadillac Series 62",
    https://sketchfab.com/3d-models/1949-cadillac-series-62-9a480a4c86ab435188897915759e8aab
  * "1970 - Plymouth Superbird - Free Vehicle Archive" (the NASCAR car),
    https://sketchfab.com/3d-models/1970-plymouth-superbird-free-vehicle-archive-3a593f93fc9343ebacc9986714f8b06e

The first argument names an entry in CARS. The models are made in Blender the same way:
one object per part, flat-colored materials for most of the car and small images for
the lamps, badges, gauges and interior. Blender opens the source (this script runs
itself under `blender -b` for that, so Blender must be on the PATH) and hands back every
triangle with its object, material and UVs, the materials' settings and the images'
pixels; the rest is plain Python. In all of them the nose points along -Y, Z is up and the
driver's side is +X. Objects are named after the model (`base`, or the file's name).

What goes where is set per car in CARS, by object (the number Blender put after the
model's name, '' for the one without):

  * `drop`: objects left out: the wheels, brakes and suspension (the game mounts its own),
    the engine (the hood view draws its own), the exhaust;
  * `split`: objects that hold many loose parts (the Nomad's floor, frame, suspension and
    exhaust are one object), of which only the parts whose boxes match `keep` stay;
  * `bumpers`: the objects of `bumper_front` and `bumper_rear`, with their brackets, so
    the game can strip them;
  * `clamp`: objects whose corners are pulled in along an axis (0 X, 1 Y, 2 Z) to
    between a least and a most, so frame rails that ran out past the body under the
    bumper end inside it;
  * `rear_skirt`: the body's rear end under the bumper, which the model leaves open (the
    bumper wraps round the fins' ends and covers the gap under the trunk): the paint's
    open bottom edges there carried down and tucked in under the car, straight down or
    flowing on from the panel (see rear_skirt);
  * `plates`: where the game's plates go (model space), printed in the game's space for
    the car file;
  * `gauges`: the working gauges (tools/fva_dash.py);
  * `steering`: the steering wheel, as its own `driving_wheel` node with +Z down the
    column, scaled evenly so it stays round;
  * `tires`: the tire objects that set the wheel positions printed at the end (from
    `wheel_source` where the source file has had its wheels taken out).

The GLB is laid out like the Studebaker's (tools/studebaker_to_glb.py):

  * Y up, nose along +Z, driver's side +X;
  * centered on X over the paint and on Z over the whole car, lowest point at Y = 0;
  * real size in meters, each axis on its own: the length overall, the width over the
    paint, the height from the bottom of the model's tires to the top of `roof` (the
    paint, or everything);
  * flat colors in a palette texture, CELL px per color: the body paint is white with
    alpha 1, which car_paint_mask.gdshader multiplies by the car's paint, a second paint
    (`accent`) has no blue, so the garage's Accent choice paints it; everything else has
    alpha 0 and keeps its color;
  * an ORM texture per material (R = AO, G = roughness, B = metallic), which is what
    the paint shader reads;
  * each image of the model as its own material, alpha 0 where it is opaque; images
    with see-through texels (lamp lenses, badges, gauge faces) cut out (MASK) where
    their alpha is all but on or off, or blended (BLEND);
  * the glass as its own see-through material, so the paint shader never touches it.

The numbers the .car file needs are printed at the end.
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
IN = 0.0254
CELL = 16
## Images are cut to at most this many px on a side.
TEXTURE = 1024
## Two boxes are the same part's when every side is within this (m, model).
BOX_MATCH = 0.006
## Corners of a split object closer than this (m) are one, for finding its loose parts.
WELD = 0.0005

NOMAD = 'reference/cars/56-nomad'
CADILLAC = 'reference/cars/49-Cadillac'
SUPERBIRD = 'reference/cars/70-superbird'

CARS = {
    'nomad-1956': {
        'source': (NOMAD + '/source/1956 - Chevrolet Bel Air Nomad.zip', '1956 - Chevrolet Bel Air Nomad.glb'),
        # Carsales (Redbook), 1956 Chevrolet Nomad: 5016 x 1880 x 1544 mm, 115 in wheelbase.
        'length': 197.5, 'width': 74.0, 'height': 60.8, 'wheelbase': 115.0,
        'roof': 'paint',
        'paint': {'Body Paint'},
        # The rear quarters, the tailgate and the insert between the side spears: the
        # second color of a two-tone 1956 Bel Air.
        'accent': {'Body Paint-2'},
        'tires': ['150', '151', '152', '153'],
        'drop': [
            # Tires, rims, hubcaps, wheel centers, brake drums, front spindles and
            # brakes, the valve stems.
            '150', '151', '152', '153', '154', '155', '156', '157',
            '159', '160', '161', '162', '163', '164', '165', '166', '167', '168', '169', '170',
            '171', '172', '173', '174', '175', '176', '177', '178',
            '', '001', '002', '003', '047', '048', '049', '050', '113', '114', '032', '033',
            # The engine.
            '129',
            # The rear plate (plain black): the game hangs a blank plate there.
            '122',
        ],
        # The floor, frame, suspension, axle, exhaust and gas tank are one object; the
        # floor pan, the frame rails, the crossmember under the floor and the tank stay.
        'split': {
            '051': [
                ((-0.903, -1.004, 0.260), (0.906, 2.412, 0.798)),
                ((-0.490, -2.332, 0.240), (0.007, 2.166, 0.592)),
                ((-0.007, -2.332, 0.240), (0.493, 2.166, 0.592)),
                ((-0.838, -0.157, 0.282), (0.840, -0.079, 0.408)),
                ((-0.265, 1.566, 0.440), (0.272, 2.104, 0.560)),
            ],
        },
        'clamp': {},
        # Under the tailgate and the fins' ends: open to the floor and the gas tank behind
        # the bumper. Straight down to the quarter panels' bottom and tucked in.
        # Down to the bumper's bottom, under the fins as under the tailgate, so the
        # quarter panels' bottoms don't show below the fins from behind.
        'rear_skirt': {'edges': 'open', 'x': (0.0, 0.95), 'y': 2.1, 'z': (0.45, 0.62),
                       'bottom': 0.40, 'profile': 'straight',
                       'tuck': 0.06, 'radius': 0.03},
        'bumpers': {
            'bumper_front': ['073', '030'],
            'bumper_rear': ['074', '031'],
        },
        # Rim and spokes (in the body paint), the horn ring, the horn button.
        'steering': ['041', '043', '042', '040'],
        # Where the plates go (model space, the middle of the plate's face): the rear on
        # the bumper where the model's plain black plate was, the front on the middle of
        # the front bumper's bar, which the model leaves bare.
        'plates': {'front': (0.0, -2.512, 0.40), 'rear': (0.0, 2.326, 0.451)},
        # The fan-shaped speedometer (its face printed in the Gauge image; the pixels are
        # the image as the model holds it, the reference copy upside down) with its red
        # needle; the gas gauge's pointer is printed in its window, under GASOLINE at the
        # top right of the fan, so it gets one of its own.
        'gauges': {
            'face': ('112', 'Gauge'),
            'speedo': {'objects': ['044'], 'mph': 110, 'marks': [(290, 257), (397, 226), (465, 254)]},
            'fuel': {'slide': [(409, 189), (459, 201)], 'erase': [(443, 202), (448, 194)]},
        },
    },
    'cadillac-1949': {
        # The user's copy with the wheels, suspension, engine, exhaust and the rest of the
        # running gear taken out; the wheels are measured in the full file.
        'source': (CADILLAC + '/source/1949 - Cadillac Series 62 - Stripped.blend', None),
        'wheel_source': CADILLAC + '/source/1949 - Cadillac Series 62.blend',
        # 1949 Series 61/62: 215.1 in long on a 126 in wheelbase (Over Drive fact sheet);
        # 62 in high (the convertible); 80.1 in wide (a 1949 Series 62, Conceptcarz).
        'length': 215.1, 'width': 80.1, 'height': 62.0, 'wheelbase': 126.0,
        'roof': 'all',
        'paint': {'Office Green - Metallic'},
        'accent': set(),
        'tires': ['065', '066', '067', '068'],
        'drop': [
            # The tailpipe's tip, left hanging under the rear bumper.
            '105',
        ],
        'split': {},
        'clamp': {},
        # The fins' ends, open from the taillights down to the fenders' bottoms behind
        # the bumper's wrapped ends: carried on from the fins' line down to the fenders'
        # bottoms. The trunk's rear panel comes down to the trunk floor on its own.
        'rear_skirt': {'edges': 'rim', 'center': (0.865, 2.65), 'x': (0.70, 1.0), 'y': 2.62,
                       'z': (0.6, 0.78), 'profile': 'section', 'section': 2.6493,
                       'spine': 0.085},
        'bumpers': {
            # The bumper with its guards, and its brackets.
            'bumper_front': ['014', '072'],
            # The bumper with its guards, its black inner face, the plate's housing, its
            # lamp's lens and the gravel pan under it.
            'bumper_rear': ['017', '104', '018', '106', '041'],
        },
        'steering': ['111'],
        # The rear plate on the black face of the bumper's plate housing, the front on the
        # middle of the front bumper's bar between its guards.
        'plates': {'front': (0.0, -2.52, 0.405), 'rear': (0.0, 2.744, 0.6055)},
        # The arched speedometer over the white plate, its needle turning from the
        # plate's middle (where its 0 and 110 ticks point); the gas gauge at the far
        # left, E to F across the top of its window. The temperature, battery and oil
        # needles stay put.
        'gauges': {
            'face': ('124', 'Dials'),
            'speedo': {'objects': ['125'], 'mph': 110, 'marks': [(281, 171), (476, 110), (752, 186)],
                       'pivot': (519, 240)},
            'fuel': {'objects': ['128'], 'pivot': (97, 283), 'empty': (78, 262), 'full': (116, 262)},
        },
    },
}

CARS['superbird-1970'] = {
    'source': (SUPERBIRD + '/source/1970 Plymouth Superbird.glb', None),
    # The objects are named after the model, not the file.
    'base': '1970 - Plymouth Superbird [NASCAR]',
    # 221.0 in long, 76.4 in wide, 61.4 in to the top of the wing, 115.8 in wheelbase
    # (Aero Warriors, Superbird specifications).
    'length': 221.0, 'width': 76.4, 'height': 61.4, 'wheelbase': 115.8,
    'roof': 'paint',
    'paint': {'Vehicle - Body - Paint'},
    'accent': set(),
    'tires': ['019', '023', '028', '031'],
    'drop': [
        # Tires, rims, hub caps.
        '019', '023', '028', '031', '020', '024', '027', '030', '021', '025', '029', '032',
        # The rear axle and the exhaust.
        '076', '069',
    ],
    # The floor, suspension, transmission, driveshaft and exhaust pipe are one object; the
    # floor pan and the trunk's pan stay.
    'split': {
        '022': [
            ((-0.742, -2.068, 0.177), (0.742, 0.855, 0.402)),
            ((-0.762, 1.727, 0.289), (0.763, 2.402, 0.378)),
        ],
    },
    'clamp': {},
    # The rear bumper stays on: the nose has none, and under the tail panel the body is
    # open behind it.
    'bumpers': {},
    'steering': ['074', '075'],
    # The rear plate on the middle of the bumper, between the exhaust holes; the nose has
    # no place for one.
    'plates': {'rear': (0.0, 2.596, 0.48)},
    # The race panel: a tach (2,000 to 9,000 rpm round from the bottom), fuel pressure, oil
    # temperature, water temperature and oil pressure, their needles printed on their faces.
    # The tach's red needle is painted out for one that works; the thin tell-tale beside
    # it stays, as do the other gauges.
    'gauges': {
        'tach': {'face': ('066', 'RPM'), 'pivot': (257, 258), 'zero': (259, 480), 'full': (480, 291),
                 'tip': (259, 463), 'rpm': (2000, 9000), 'color': (176, 26, 30),
                 'erase': {'line': [(257, 258), (341, 29)], 'width': 6, 'ring': 199}},
    },
}

## Clear glass with a faint green tint, as on the Studebaker.
GLASS_MATERIAL = {
    'name': 'glass',
    'pbrMetallicRoughness': {'baseColorFactor': [0.62, 0.72, 0.70, 0.22],
                             'metallicFactor': 0.0, 'roughnessFactor': 0.04},
    'alphaMode': 'BLEND',
    'doubleSided': True,
}
CHROME = ((236, 236, 240), 0.06, 1.0)
## (sRGB color, roughness, metallic) by material name, over the model's own settings,
## which give most materials full metallic.
LOOKS = {
    'Chrome': CHROME,
    'Mirror': CHROME,
    'Aluminum': ((200, 204, 208), 0.25, 1.0),
    'Aluminum-Dark': ((150, 152, 156), 0.25, 1.0),
    'Rim': ((200, 204, 208), 0.2, 1.0),
    'Headlight-Base': (None, 0.15, 1.0),
}


def needle_cell(color):
    """The palette cell of a needle or pointer of its own (tools/fva_dash.py), by its color."""
    return '__needle_%d_%d_%d__' % tuple(color)


## A flat material's metallic when LOOKS doesn't give it.
METALLIC = 0.0


def srgb(c):
    c = max(0.0, min(1.0, c))
    return round(255 * (c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055))


def short(name, base):
    return name[len(base) + 1:] if name.startswith(base + '.') else ''


def dump(src, out, base, tires_only):
    """Under Blender: every triangle by object and material, in the model's frame, with
    normals and UVs (through the material's Mapping node, if any), and for every object
    the loose part each triangle is in; the materials' settings and the images' pixels.
    With tires_only, the tire objects' corners only."""
    import bpy
    import numpy as np
    if src.endswith('.glb'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=src)
    elif src.lower().endswith('.fbx'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=src)
    else:
        bpy.ops.wm.open_mainfile(filepath=src, load_ui=False)
    want = set(tires_only.split(',')) if tires_only else None

    def principled(mat):
        for n in mat.node_tree.nodes:
            if n.type == 'BSDF_PRINCIPLED':
                return n
        return None

    def linked_image(sock):
        for link in sock.links:
            node = link.from_node
            if node.type == 'TEX_IMAGE':
                return node
            if node.type == 'NORMAL_MAP':
                return linked_image(node.inputs['Color'])
        return None

    def mapping(img_node):
        if img_node is None or not img_node.inputs['Vector'].links:
            return None
        node = img_node.inputs['Vector'].links[0].from_node
        if node.type != 'MAPPING':
            return None
        return [list(node.inputs['Location'].default_value)[:2], list(node.inputs['Scale'].default_value)[:2]]

    materials, images = {}, {}
    for mat in bpy.data.materials:
        info = {'color': [1.0, 1.0, 1.0], 'roughness': 0.5, 'metallic': 0.0, 'image': None,
                'alpha_image': False, 'normal': None, 'mapping': None, 'blend': mat.blend_method}
        if mat.use_nodes:
            p = principled(mat)
            group = next((n for n in mat.node_tree.nodes if n.type == 'GROUP'), None)
            if p is not None:
                info['color'] = list(p.inputs['Base Color'].default_value)[:3]
                info['roughness'] = p.inputs['Roughness'].default_value
                info['metallic'] = p.inputs['Metallic'].default_value
                tex = linked_image(p.inputs['Base Color'])
                if tex is not None and tex.image is not None:
                    info['image'] = tex.image.name
                    info['alpha_image'] = bool(p.inputs['Alpha'].links)
                    info['mapping'] = mapping(tex)
                nrm = linked_image(p.inputs['Normal'])
                if nrm is not None and nrm.image is not None:
                    info['normal'] = nrm.image.name
                    info['normal_mapping'] = mapping(nrm)
            elif group is not None and 'Color' in group.inputs:
                info['color'] = list(group.inputs['Color'].default_value)[:3]
        materials[mat.name] = info
        for key in ('image', 'normal'):
            name = info[key]
            if name and name not in images:
                im = bpy.data.images[name]
                w, h = im.size
                px = np.empty(w * h * im.channels, np.float32)
                im.pixels.foreach_get(px)
                px = px.reshape(h, w, im.channels)[::-1]
                if im.channels == 3:
                    px = np.concatenate([px, np.ones((h, w, 1), np.float32)], 2)
                images[name] = np.clip(np.round(px * 255), 0, 255).astype(np.uint8)

    arrays = {}
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        key_name = short(o.name, base)
        if want is not None and key_name not in want:
            continue
        me = o.data
        me.calc_loop_triangles()
        tris = me.loop_triangles
        n = len(tris)
        if n == 0:
            continue
        loops = np.empty(n * 3, np.int64)
        tris.foreach_get('loops', loops)
        mats = np.empty(n, np.int64)
        tris.foreach_get('material_index', mats)
        polys = np.empty(n, np.int64)
        tris.foreach_get('polygon_index', polys)
        verts = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get('vertex_index', verts)
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get('co', co)
        co = co.reshape(-1, 3)
        m = np.array(o.matrix_world)
        lin = m[:3, :3]
        world = co @ lin.T + m[:3, 3]
        pos = world[verts[loops]]
        if want is not None:
            arrays[key_name + '|pos'] = pos
            continue
        nrm = np.empty(len(me.loops) * 3)
        me.corner_normals.foreach_get('vector', nrm)
        nrm = nrm.reshape(-1, 3)[loops] @ np.linalg.inv(lin)
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
        if me.uv_layers.active is not None:
            uv = np.empty(len(me.loops) * 2)
            me.uv_layers.active.data.foreach_get('uv', uv)
            uv = uv.reshape(-1, 2)[loops]
        else:
            uv = np.zeros((n * 3, 2))
        # Loose parts: corners at the same place (to WELD) join their polygons.
        keys = np.round(world / WELD).astype(np.int64)
        _, vid = np.unique(keys, axis=0, return_inverse=True)
        vid = vid.reshape(-1)
        parent = list(range(int(vid.max()) + 1))

        def find(a):
            while parent[a] != a:
                parent[a] = parent[parent[a]]
                a = parent[a]
            return a
        for poly in me.polygons:
            vs = [int(vid[v]) for v in poly.vertices]
            r0 = find(vs[0])
            for v in vs[1:]:
                r = find(v)
                if r != r0:
                    parent[r] = r0
        part = np.array([find(int(vid[me.polygons[p].vertices[0]])) for p in polys])
        order = np.arange(n * 3).reshape(-1, 3)
        if np.linalg.det(lin) < 0:
            order = order[:, ::-1]
        names = [s.material.name if s.material else '' for s in o.material_slots] or ['']
        for k, mat in enumerate(names):
            sel_t = np.nonzero(mats == k)[0]
            if len(sel_t) == 0:
                continue
            sel = order[sel_t].reshape(-1)
            uvk = uv[sel].copy()
            mp = materials.get(mat, {}).get('mapping')
            if mp:
                uvk = uvk * np.array(mp[1]) + np.array(mp[0])
            key = f'{key_name}|{mat}'
            arrays[key + '|pos'] = pos[sel]
            arrays[key + '|nrm'] = nrm[sel]
            arrays[key + '|uv'] = uvk
            arrays[key + '|part'] = part[sel_t]
    np.savez(out, **arrays)
    if want is None:
        np.savez(out + '.images.npz', **images)
        with open(out + '.json', 'w') as f:
            json.dump(materials, f)


def run_dump(src, npz, base, tires_only=''):
    subprocess.run(['blender', '-b', '--factory-startup', '--python', os.path.abspath(__file__),
                    '--', 'dump', src, npz, base, tires_only],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def load_pieces(path):
    import numpy as np
    data = np.load(path)
    pieces = {}
    for key in data.files:
        obj, mat, kind = key.split('|')
        pieces.setdefault((obj, mat), {})[kind] = data[key]
    return pieces


def look(name, info):
    """(sRGB color, roughness, metallic) of a flat material."""
    color, rough, metal = LOOKS.get(name, (None, None, None))
    if color is None:
        color = tuple(srgb(c) for c in info['color'])
    if rough is None:
        rough = info['roughness']
    if metal is None:
        metal = METALLIC
    return color, rough, metal


def image_png(px, alpha, size):
    """An image's PNG at most `size` px on a side; alpha 0 unless the material is see-through."""
    import numpy as np
    from PIL import Image
    from studebaker_to_glb import png_bytes
    h, w = px.shape[:2]
    scale = min(1.0, size / max(w, h))
    dims = (max(1, round(w * scale)), max(1, round(h * scale)))
    # Color and alpha resized apart: PIL premultiplies an RGBA image when it resizes it.
    color = Image.fromarray(np.ascontiguousarray(px[..., :3])).resize(dims, Image.LANCZOS)
    a = px[..., 3] if alpha else np.zeros((h, w), np.uint8)
    mask = Image.fromarray(np.ascontiguousarray(a)).resize(dims, Image.LANCZOS)
    return png_bytes(Image.merge('RGBA', [*color.split(), mask]))


def normal_png(px, size):
    import numpy as np
    from PIL import Image
    from studebaker_to_glb import png_bytes
    h, w = px.shape[:2]
    scale = min(1.0, size / max(w, h))
    dims = (max(1, round(w * scale)), max(1, round(h * scale)))
    return png_bytes(Image.fromarray(np.ascontiguousarray(px[..., :3])).resize(dims, Image.LANCZOS))


def flat_png(color):
    from PIL import Image
    from studebaker_to_glb import png_bytes
    return png_bytes(Image.new('RGB', (4, 4), color))


def box_match(lo, hi, boxes):
    import numpy as np
    return any(np.all(np.abs(lo - np.array(b[0])) <= BOX_MATCH) and np.all(np.abs(hi - np.array(b[1])) <= BOX_MATCH)
               for b in boxes)


## The rear valance's top edges are found by welding the paint's corners this close (m).
SKIRT_WELD = 0.0005
## Points along a valance's profile, top to bottom.
SKIRT_STEPS = 12
## How far back from the panel ahead, and down from the top, a 'section' end blends out
## to that panel's side (m).
SKIRT_MEET = 0.08
## How far a valance carries on along its panel's slope before it turns (m): enough to
## leave no crease, little enough to stay inside the bumper.
SKIRT_LEAD = 0.02


def rear_skirt(kept, car, spec):
    """The rear valance: where the bumper covered the bottom of the body, the bottom
    edges of the paint (in spec's band of heights 'z', behind spec's 'y', at spec's |x|)
    carried down and in under the car, each edge in its own panel's paint, leaving the
    panel along its own slope and shaded as it is at the edge. Returns {material: piece}.

    The edges are, by spec's 'edges': 'open', the paint's open edges under a standing
    panel (the Nomad's single-skin panels); or 'rim', the outside edge of the flat rim
    where a two-skin panel ends (the Cadillac's fins), outside being away from spec's
    'center' (x, y; mirrored for the other side).

    By spec's 'profile': 'straight' turns straight down to 'bottom' (a height, or
    (|x|, height) points to go between) and rounds in over 'radius' to a 'tuck' in from
    the edge; 'section' follows the panel ahead, cut across at y = 'section', down and
    round under to its bottom, scaled about a spine 'spine' long running back from
    'center', so the end flows on from the panel's side and closes underneath along the
    spine."""
    import numpy as np
    paints = car['paint'] | car['accent']
    bumpers = set(car['bumpers']['bumper_rear'])
    pos, nrm, mats = [], [], []
    for (obj, mat), p in kept.items():
        if mat in paints and obj not in bumpers:
            pos.append(p['pos'].reshape(-1, 3, 3))
            nrm.append(p['nrm'].reshape(-1, 3, 3))
            mats += [mat] * (len(p['pos']) // 3)
    tris, corner_n, mats = np.concatenate(pos), np.concatenate(nrm), np.array(mats)
    fn = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    _, key = np.unique(np.round(tris.reshape(-1, 3) / SKIRT_WELD).astype(np.int64), axis=0,
                       return_inverse=True)
    key = key.reshape(-1, 3)
    zlo, zhi = spec['z']
    xlo, xhi = spec['x']
    mid = tris.mean(1)
    near = ((mid[:, 2] >= zlo - 0.15) & (mid[:, 2] <= zhi + 0.15) & (mid[:, 1] >= spec['y'] - 0.15)
            & (np.abs(mid[:, 0]) >= xlo - 0.15) & (np.abs(mid[:, 0]) <= xhi + 0.15))
    flat = np.abs(fn[:, 2]) > 0.7
    edges = {}
    for t in np.nonzero(near)[0]:
        for i, j in ((0, 1), (1, 2), (2, 0)):
            e = (min(key[t, i], key[t, j]), max(key[t, i], key[t, j]))
            edges.setdefault(e, []).append((t, i, j))

    def center(q):
        """The point a 'section' end is scaled about: on the spine, beside q."""
        c = np.array([np.sign(q[0]) * spec['center'][0], spec['center'][1], 0.0])
        c[1] = np.clip(q[1], c[1], c[1] + spec.get('spine', 0.0))
        return c

    picked = []
    for e, uses in edges.items():
        t, i, j = uses[0]
        a, b = tris[t, i], tris[t, j]
        m = (a + b) / 2
        run = np.linalg.norm(b - a)
        if not (zlo <= a[2] <= zhi and zlo <= b[2] <= zhi and min(a[1], b[1]) >= spec['y']
                and xlo <= abs(a[0]) <= xhi and xlo <= abs(b[0]) <= xhi):
            continue
        if run < 1e-6 or abs(b[2] - a[2]) > 0.5 * run:
            continue
        if spec['edges'] == 'open':
            # A bottom edge of a standing panel: the one triangle is above it.
            if len(uses) != 1 or flat[t] or mid[t][2] <= m[2]:
                continue
            stand = t
        else:
            rims = [u for u in uses if flat[u[0]] and fn[u[0]][2] < 0]
            stands = [u for u in uses if not flat[u[0]] and mid[u[0]][2] > m[2]]
            if len(rims) != 1 or len(stands) != 1:
                continue
            # The outside edge has the rim on its inner side (toward the center).
            out = np.array([a[1] - b[1], b[0] - a[0], 0.0])
            if np.dot(out, m - center(m)) < 0:
                out = -out
            if np.dot(mid[rims[0][0]] - m, out) >= 0:
                continue
            stand = stands[0][0]
        picked.append(((key[t, i], key[t, j]), stand, a, b))
    # Each corner: where it is, its panel's shading there, the edge's way along, and the
    # way in (flat, away from the panel's outside).
    where, shade, along, inward = {}, {}, {}, {}
    for (ka, kb), t, a, b in picked:
        n = fn[t].copy()
        n[2] = 0
        n /= max(np.linalg.norm(n), 1e-12)
        if spec['edges'] == 'rim' and np.dot(n, (a + b) / 2 - center((a + b) / 2)) < 0:
            n = -n
        for k, q in ((ka, a), (kb, b)):
            where[k] = q
            c = list(key[t]).index(k)
            shade[k] = shade.get(k, 0) + corner_n[t, c]
            run = b - a
            if k in along and np.dot(along[k], run) < 0:
                run = -run
            along[k] = along.get(k, 0) + run
            inward[k] = inward.get(k, 0) - n
    if spec['profile'] == 'section':
        # The panel ahead's outer skin where it is cut off: its corners on the cut that
        # face out, or down in the curl (the inner skin's face in), bottom to top, curling in under
        # itself to the spine at the bottom; and its shading there, as (out, up).
        cx = spec['center'][0]
        flat_tris = tris.reshape(-1, 3)
        flat_n = corner_n.reshape(-1, 3)
        side = np.sign(flat_tris[:, 0])
        on = ((np.abs(flat_tris[:, 1] - spec['section']) < 0.002) & (np.abs(flat_tris[:, 0]) > cx - 0.005)
              & (flat_n[:, 1] < 0.5) & (flat_n[:, 0] * side - flat_n[:, 2] > 0.2))
        # Facing down only in the curl at the bottom, not the flat rim at the top.
        on &= ~((flat_n[:, 2] < -0.7) & (flat_tris[:, 2] > flat_tris[on, 2].min() + 0.1))
        skin = {}
        for q, n in zip(flat_tris[on], flat_n[on]):
            row = skin.setdefault(round(q[2], 4), [])
            row.append((abs(q[0]), n[0] * np.sign(q[0]), n[2], n[1]))
        heights = np.array(sorted(skin))
        cut = np.array([np.mean(skin[z], axis=0) for z in heights])

        def reach(z):
            return max(np.interp(z, heights, cut[:, 0]) - cx, 0.0)


        def skin_normal(z, u):
            n = u * np.interp(z, heights, cut[:, 1]) + np.array([0, 0, np.interp(z, heights, cut[:, 2])])
            return n / max(np.linalg.norm(n), 1e-12)

    profile = {}
    for k, q in where.items():
        nb = shade[k] / max(np.linalg.norm(shade[k]), 1e-12)
        # Down the panel from the edge, square to the edge.
        slope = np.cross(nb, along[k])
        slope /= max(np.linalg.norm(slope), 1e-12)
        if slope[2] > 0:
            slope = -slope
        if spec['profile'] == 'straight':
            w = inward[k] / max(np.linalg.norm(inward[k]), 1e-12)
            bottom = (np.interp(abs(q[0]), *zip(*spec['bottom'])) if isinstance(spec['bottom'], list)
                      else spec['bottom'])
            r = min(spec['radius'], (q[2] - bottom) / 2)
            # On along the panel's slope, round to straight down, down, round in, in.
            lead = q + slope * SKIRT_LEAD
            turn = lead - np.array([0, 0, SKIRT_LEAD])
            pts = []
            for s in np.linspace(0, 1, 5)[:-1]:
                pts.append((1 - s) ** 2 * q + 2 * (1 - s) * s * lead + s ** 2 * turn)
            foot = np.array([turn[0], turn[1], bottom])
            for s in np.linspace(0, 1, SKIRT_STEPS // 2)[:-1]:
                pts.append(turn + (foot + np.array([0, 0, r]) - turn) * s)
            for s in np.linspace(0, np.pi / 2, SKIRT_STEPS // 2 + 1):
                pts.append(foot + np.array([0, 0, r]) + w * r * (1 - np.cos(s)) - np.array([0, 0, r * np.sin(s)]))
            pts.append(foot + w * spec['tuck'])
        else:
            # Scaled about the spine as the panel ahead is at each height, leaving the
            # edge along the panel's slope.
            c = center(q)
            u = q - c
            u[2] = 0
            r_top = np.linalg.norm(u)
            u /= max(r_top, 1e-12)
            out_slope = np.dot(slope, u) / max(-slope[2], 0.2)
            # Up against the panel ahead, the side comes out to it (the fin above can be a
            # little narrower than the panel's end): fully at the front from a little way
            # down, none a little way back or on the side away from it.
            meet = (np.clip(1 - (q[1] - spec['section']) / SKIRT_MEET, 0, 1)
                    * np.clip(abs(u[0]) * 2 - 1, 0, 1)) if u[0] * np.sign(q[0]) > 0 else 0.0
            pts, shades = [q], [nb]
            rows = np.union1d(heights, np.arange(heights[0], q[2], 0.005))
            for z in rows[rows < q[2] - 0.002][::-1]:
                fall = reach(z) / reach(q[2])
                r = r_top * fall + out_slope * SKIRT_LEAD * (1 - np.exp(-(q[2] - z) / SKIRT_LEAD)) * fall
                r += (reach(z) - r) * meet * np.clip((q[2] - z) / SKIRT_MEET, 0, 1)
                pts.append(np.array([c[0] + u[0] * r, c[1] + u[1] * r, z]))
                # Shaded as the panel ahead is at this height, turned to face this way;
                # near the top, as the edge's own panel is.
                top = np.exp(-(q[2] - z) / SKIRT_LEAD)
                n = skin_normal(z, u) * (1 - top) + nb * top
                shades.append(n / max(np.linalg.norm(n), 1e-12))
            w = -u
            profile[k] = (np.array(pts), w, nb, np.array(shades))
            continue
        profile[k] = (np.array(pts), w, nb, None)
    out = {}

    def add(mat, tri, outside, shades=None):
        tri = np.array(tri)
        face = np.cross(tri[1] - tri[0], tri[2] - tri[0])
        if np.linalg.norm(face) < 1e-12:
            return
        if np.dot(face, outside) < 0:
            tri = tri[[0, 2, 1]]
            face = -face
            if shades is not None:
                shades = shades[[0, 2, 1]]
        o = out.setdefault(mat, {'pos': [], 'face': [], 'shade': []})
        o['pos'].append(tri)
        o['face'].append(face / np.linalg.norm(face))
        o['shade'].append(shades if shades is not None else np.full((3, 3), np.nan))

    tops = {}
    for (ka, kb), t, a, b in picked:
        (pa, wa, na, sa), (pb, wb, nb, sb) = profile[ka], profile[kb]
        tops[tuple(np.round(pa[0], 6))] = na
        tops[tuple(np.round(pb[0], 6))] = nb
        # Outside is away from the way in, and down.
        outside = -(wa + wb) / 2 - np.array([0, 0, 1.0])
        if sa is not None:
            # Rows by height, so the two sides of a step stay level with each other.
            za, zb = pa[:, 2], pb[:, 2]
            rows = np.union1d(za, zb)[::-1]
            rows = rows[rows <= min(za[0], zb[0]) + 1e-9]
            if za[0] > zb[0] + 1e-9 or zb[0] > za[0] + 1e-9:
                rows = np.concatenate([[max(za[0], zb[0])], rows])

            def at(p, sh, z):
                i = np.clip(np.searchsorted(-p[:, 2], -z), 1, len(p) - 1)
                f = np.clip((p[i - 1, 2] - z) / max(p[i - 1, 2] - p[i, 2], 1e-12), 0, 1)
                n = sh[i - 1] * (1 - f) + sh[i] * f
                return p[i - 1] * (1 - f) + p[i] * f, n / max(np.linalg.norm(n), 1e-12)

            ring = [(at(pa, sa, z), at(pb, sb, z)) for z in rows]
            for ((p0, n0), (p1, n1)), ((p2, n2), (p3, n3)) in zip(ring[:-1], ring[1:]):
                add(mats[t], (p0, p1, p3), outside, np.array([n0, n1, n3]))
                add(mats[t], (p0, p3, p2), outside, np.array([n0, n3, n2]))
            continue
        for s in range(min(len(pa), len(pb)) - 1):
            add(mats[t], (pa[s], pb[s], pb[s + 1]), outside)
            add(mats[t], (pa[s], pb[s + 1], pa[s + 1]), outside)
    result = {}
    for mat, o in out.items():
        pos = np.concatenate(o['pos'])
        face = np.repeat(np.array(o['face']), 3, 0)
        _, at = np.unique(np.round(pos / 1e-5).astype(np.int64), axis=0, return_inverse=True)
        at = at.reshape(-1)
        vn = np.zeros((at.max() + 1, 3))
        np.add.at(vn, at, face)
        vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
        vn = vn[at]
        # A 'section' end is shaded as the panel ahead is at each height (how far it
        # faces up or down), facing round the way its own shape does.
        shade = np.concatenate(o['shade'])
        given = ~np.isnan(shade[:, 0])
        if given.any():
            flat_way = vn[given] * np.array([1, 1, 0])
            flat_way /= np.maximum(np.linalg.norm(flat_way, axis=1, keepdims=True), 1e-12)
            # Up against the panel ahead, on its side, facing as that panel's side does.
            at_side = pos[given]
            ahead = np.stack([np.sign(at_side[:, 0]) * np.interp(at_side[:, 2], heights, cut[:, 1]),
                              np.interp(at_side[:, 2], heights, cut[:, 3]), np.zeros(len(at_side))], 1)
            ahead /= np.maximum(np.linalg.norm(ahead, axis=1, keepdims=True), 1e-12)
            near_it = (np.clip(1 - (at_side[:, 1] - spec['section']) / SKIRT_MEET, 0, 1)
                       * (np.abs(at_side[:, 0]) > spec['center'][0]))[:, None]
            flat_way = flat_way * (1 - near_it) + ahead * near_it
            flat_way /= np.maximum(np.linalg.norm(flat_way, axis=1, keepdims=True), 1e-12)
            vn[given] = (flat_way * np.linalg.norm(shade[given][:, :2], axis=1, keepdims=True)
                         + shade[given] * np.array([0, 0, 1]))
        # Where the valance meets its panel, it is shaded as the panel is there.
        for i, q in enumerate(pos):
            n = tops.get(tuple(np.round(q, 6)))
            if n is not None:
                vn[i] = n / max(np.linalg.norm(n), 1e-12)
        result[mat] = {'pos': pos, 'nrm': vn, 'uv': np.zeros((len(pos), 2))}
    return result


def build(car_name, dst):
    import numpy as np
    from PIL import Image
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from studebaker_to_glb import Gltf, ring_axis, share_corners, png_bytes
    from studebaker_dash import quaternion
    import fva_dash
    import zipfile

    car = CARS[car_name]
    path, inner = car['source']
    path = os.path.join(ROOT, path)
    with tempfile.TemporaryDirectory() as tmp:
        if inner:
            with zipfile.ZipFile(path) as z:
                z.extract(inner, tmp)
            src = os.path.join(tmp, inner)
        else:
            src = path
        base = car.get('base') or os.path.splitext(os.path.basename(inner or path))[0].replace(' - Stripped', '')
        npz = os.path.join(tmp, 'pieces.npz')
        run_dump(src, npz, base)
        pieces = load_pieces(npz)
        with open(npz + '.json') as f:
            materials = json.load(f)
        images = dict(np.load(npz + '.images.npz'))
        if 'wheel_source' in car:
            wnpz = os.path.join(tmp, 'wheels.npz')
            run_dump(os.path.join(ROOT, car['wheel_source']), wnpz, base, ','.join(car['tires']))
            tire_pos = np.concatenate([v for v in np.load(wnpz).values()])
        else:
            tire_pos = np.concatenate([p['pos'] for (obj, _), p in pieces.items() if obj in car['tires']])

    # Printed pointers and needles that get working ones of their own are painted out.
    gauges = car.get('gauges') or {}
    for part in ('speedo', 'tach', 'fuel'):
        spec = gauges.get(part, {})
        if 'erase' in spec:
            image = materials[spec.get('face', gauges.get('face'))[1]]['image']
            if isinstance(spec['erase'], dict):
                e = spec['erase']
                images[image] = fva_dash.erase_needle(images[image], e['line'], e['width'], spec['pivot'], e['ring'])
            else:
                images[image] = fva_dash.erase(images[image], spec['erase'])

    # Leave out the dropped objects and the loose parts of split objects not kept.
    kept = {}
    for (obj, mat), p in pieces.items():
        if obj in car['drop']:
            continue
        if obj in car['split']:
            keep = np.zeros(len(p['part']), bool)
            corners = p['pos'].reshape(-1, 3, 3)
            for part in np.unique(p['part']):
                sel = p['part'] == part
                # The part's box over all of its triangles, in any material.
                every = np.concatenate([q['pos'].reshape(-1, 3, 3)[q['part'] == part]
                                        for (o2, _), q in pieces.items() if o2 == obj])
                lo, hi = every.reshape(-1, 3).min(0), every.reshape(-1, 3).max(0)
                keep[sel] = box_match(lo, hi, car['split'][obj])
            if not keep.any():
                continue
            idx = np.repeat(keep, 3)
            p = {'pos': p['pos'][idx], 'nrm': p['nrm'][idx], 'uv': p['uv'][idx]}
            del corners
        for axis, least, most in car['clamp'].get(obj, []):
            p['pos'] = p['pos'].copy()
            p['pos'][:, axis] = np.clip(p['pos'][:, axis], least, most)
        kept[(obj, mat)] = p
    if car.get('rear_skirt'):
        for mat, p in rear_skirt(kept, car, car['rear_skirt']).items():
            kept[('rear_skirt', mat)] = p

    # The model's frame (Z up, nose -Y) to the game's (Y up, nose +Z, driver's side +X).
    def to_yup(a):
        return np.stack([a[..., 0], a[..., 2], -a[..., 1]], -1)

    for p in kept.values():
        p['pos'] = to_yup(p['pos'])
        p['nrm'] = to_yup(p['nrm'])
    tire_pos = to_yup(tire_pos)
    allp = np.concatenate([p['pos'] for p in kept.values()])
    paint = np.concatenate([p['pos'] for (o, m), p in kept.items() if m in car['paint']])
    lo, hi = allp.min(0), allp.max(0)
    floor = tire_pos[:, 1].min()
    top = paint[:, 1].max() if car['roof'] == 'paint' else hi[1]
    scale = np.array([car['width'] * IN / (paint[:, 0].max() - paint[:, 0].min()),
                      car['height'] * IN / (top - floor),
                      car['length'] * IN / (hi[2] - lo[2])])
    origin = np.array([(paint[:, 0].min() + paint[:, 0].max()) / 2, lo[1], (lo[2] + hi[2]) / 2])

    def to_game(q):
        return (q - origin) * scale

    # The working gauges' pods: (name, needle's name, origin, basis, objects or a mesh of
    # its own, the turn that rests the needle), and which group each needle object is in.
    pods, pod_of = [], {}
    if gauges:
        def faces(key):
            fp = pieces[tuple(key)]
            px = images[materials[key[1]]['image']]
            return (to_game(fp['pos']).reshape(-1, 3, 3), fp['uv'].reshape(-1, 3, 2)), (px.shape[1], px.shape[0])
        objects = [o for part in ('speedo', 'fuel') for o in gauges.get(part, {}).get('objects', [])]
        needles = {o: to_game(np.concatenate([p['pos'] for (o2, _), p in kept.items() if o2 == o]))
                   for o in objects}
        pods = fva_dash.build(gauges, faces, needles)
        for i, pod in enumerate(pods):
            if isinstance(pod[4], list):
                pod_of.update({o: f'pod{i}' for o in pod[4]})
            print(f'gauge {pod[0]}: {pod[1]} at {pod[2].round(3)}, turned {pod[5]:.1f} degrees to rest')

    steer_all = np.concatenate([p['pos'] for (o, m), p in kept.items() if o in car['steering']])
    rim = to_game(steer_all)
    rim_mid = (rim.min(0) + rim.max(0)) / 2
    even = scale.mean()

    # Materials: the palette (flat colors, the paint and the accent), one per image, glass.
    flat, imaged = [], []
    for (o, m) in kept:
        info = materials.get(m, {})
        if 'Glass' in m or m in car['paint'] or m in car['accent']:
            continue
        if info.get('image'):
            if m not in imaged:
                imaged.append(m)
        elif m not in flat:
            flat.append(m)
    # A cell for each color of the needles and pointers of their own.
    own = {needle_cell(pod[4][2]): pod[4][2] for pod in pods if not isinstance(pod[4], list)}
    flat += sorted(own)
    cells = ['__paint__', '__accent__'] + sorted(flat)
    side = 1
    while side * side < len(cells):
        side *= 2
    pal = np.zeros((side * CELL, side * CELL, 4), np.uint8)
    orm = np.zeros((side * CELL, side * CELL, 3), np.uint8)
    cell_uv = {}
    for i, name in enumerate(cells):
        cx, cy = i % side, i // side
        if name == '__paint__':
            color, rough, metal, alpha = (255, 255, 255), 0.3, 0.0, 255
        elif name == '__accent__':
            color, rough, metal, alpha = (255, 255, 0), 0.3, 0.0, 255
        elif name in own:
            color, rough, metal, alpha = own[name], 0.4, 0.0, 0
        else:
            color, rough, metal = look(name, materials[name])
            alpha = 0
        pal[cy * CELL:(cy + 1) * CELL, cx * CELL:(cx + 1) * CELL] = (*color, alpha)
        orm[cy * CELL:(cy + 1) * CELL, cx * CELL:(cx + 1) * CELL] = (255, round(rough * 255), round(metal * 255))
        cell_uv[name] = ((cx + 0.5) / side, (cy + 0.5) / side)

    out = Gltf()
    mat_index = {}

    def add_material(name, albedo, orm_png, normal=None, mode='OPAQUE'):
        base_i = len(out.images)
        out.images += [albedo, orm_png] + ([normal] if normal else [])
        tex0 = len(out.textures)
        out.textures += list(range(base_i, len(out.images)))
        material = {
            'name': name,
            'pbrMetallicRoughness': {'baseColorTexture': {'index': tex0},
                                     'metallicRoughnessTexture': {'index': tex0 + 1},
                                     'metallicFactor': 1.0, 'roughnessFactor': 1.0},
            'occlusionTexture': {'index': tex0 + 1},
            'alphaMode': mode,
            'doubleSided': True,
        }
        if normal:
            material['normalTexture'] = {'index': tex0 + 2}
        if mode == 'MASK':
            material['alphaCutoff'] = 0.5
        mat_index[name] = len(out.materials)
        out.materials.append(material)

    add_material('palette', png_bytes(Image.fromarray(pal, 'RGBA')), png_bytes(Image.fromarray(orm, 'RGB')))
    for m in imaged:
        info = materials[m]
        px = images[info['image']]
        mode = 'OPAQUE'
        if info['alpha_image']:
            a = px[..., 3]
            if (a < 250).mean() > 0.002:
                soft = ((a > 16) & (a < 240)).mean() / max((a < 250).mean(), 1e-9)
                mode = 'MASK' if soft < 0.25 else 'BLEND'
        color, rough, metal = LOOKS.get(m, (None, None, None))
        rough = info['roughness'] if rough is None else rough
        metal = METALLIC if metal is None else metal
        normal = normal_png(images[info['normal']], TEXTURE) if info.get('normal') and \
            info.get('normal_mapping') == info.get('mapping') else None
        add_material(m, image_png(px, mode != 'OPAQUE', TEXTURE),
                     flat_png((255, round(rough * 255), round(metal * 255))), normal, mode)
    mat_index['glass'] = len(out.materials)
    out.materials.append(GLASS_MATERIAL)

    groups = {}
    for (obj, m), p in kept.items():
        if obj in car['steering']:
            # Scaled evenly about the rim's middle, so the wheel stays round.
            pos = rim_mid + (p['pos'] - origin - rim_mid / scale) * even
            nrm = p['nrm']
        else:
            pos = to_game(p['pos'])
            nrm = p['nrm'] / scale
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
        group = 'driving_wheel' if obj in car['steering'] else pod_of.get(obj) or next(
            (g for g, objs in car['bumpers'].items() if obj in objs), 'body')
        uv = p['uv'].copy()
        if 'Glass' in m:
            target = 'glass'
        elif m in car['paint'] or m in car['accent'] or m in flat:
            target = 'palette'
            uv[:] = cell_uv['__paint__' if m in car['paint'] else '__accent__' if m in car['accent'] else m]
        else:
            target = m
            uv[:, 1] = 1.0 - uv[:, 1]
        groups.setdefault(group, {}).setdefault(target, []).append((pos, nrm, uv))

    steer = np.concatenate([pos for parts in groups['driving_wheel'].values() for pos, _, _ in parts])
    hub, axis = ring_axis(steer)
    across = np.array([1.0, 0.0, 0.0]) - axis[0] * axis
    across /= np.linalg.norm(across)
    wheel_basis = np.stack([across, np.cross(axis, across), axis], 1)

    def primitives(group, frame=None):
        prims = []
        for target, parts in groups.get(group, {}).items():
            pos = np.concatenate([q for q, _, _ in parts])
            nrm = np.concatenate([n for _, n, _ in parts])
            uv = np.concatenate([u for _, _, u in parts])
            if frame is not None:
                o, b = frame
                pos = (pos - o) @ b
                nrm = nrm @ b
            pp, nn, uu, index = share_corners(pos.astype(np.float32), nrm.astype(np.float32), uv.astype(np.float32))
            prims.append(out.primitive(pp, nn, index, mat_index[target], uu))
        return prims

    name = os.path.splitext(os.path.basename(dst))[0]
    roots = [out.node(name, mesh=out.mesh(name, primitives('body')))]
    for group in car['bumpers']:
        roots.append(out.node(group, mesh=out.mesh(group, primitives(group))))
    wheel_mesh = out.mesh('driving_wheel_mesh', primitives('driving_wheel', (hub, wheel_basis)))
    roots.append(out.node('driving_wheel', translation=hub, rotation=quaternion(wheel_basis),
                          children=[out.node('driving_wheel_mesh', mesh=wheel_mesh)]))
    for i, (pod_name, needle_name, at, basis, made, rest) in enumerate(pods):
        if isinstance(made, list):
            prims = primitives(f'pod{i}', (at, basis @ fva_dash.turn(rest)))
        else:
            pp, nn, uu, index = share_corners(made[0].astype(np.float32), made[1].astype(np.float32),
                                              np.tile(cell_uv[needle_cell(made[2])], (len(made[0]), 1)).astype(np.float32))
            prims = [out.primitive(pp, nn, index, mat_index['palette'], uu)]
        needle = out.node(needle_name, mesh=out.mesh(needle_name, prims))
        roots.append(out.node(pod_name, translation=at, rotation=quaternion(basis), children=[needle]))
    out.write(dst, roots)

    size_m = (hi - lo) * scale
    tris = sum(len(p['pos']) // 3 for p in kept.values())
    print(f'{dst}: {tris} tris, {len(out.materials)} materials, {os.path.getsize(dst) / 1e6:.1f} MB, '
          f'size {size_m.round(3)} m ({(size_m / IN).round(1)} in), scale {scale.round(3)}')
    w = to_game(tire_pos)
    radius = (w[:, 1].max() - w[:, 1].min()) / 2
    centers = []
    for sx in (1, -1):
        for sz in (1, -1):
            q = w[(np.sign(w[:, 0]) == sx) & (np.sign(w[:, 2]) == sz)]
            centers.append((q.min(0) + q.max(0)) / 2)
    centers = np.array(centers)
    print('model tire radius %.3f m (%.1f in diameter)' % (radius, radius * 2 / IN))
    for label, c in zip(('front left', 'rear left', 'front right', 'rear right'), centers):
        print('  wheel %-11s %s' % (label, c.round(3)))
    wb = (centers[0, 2] - centers[1, 2]) / IN
    print('wheelbase %.1f in (real %.1f), track %.1f in' % (wb, car['wheelbase'], (centers[0, 0] - centers[2, 0]) / IN))
    print('ground clearance in the model %.3f m' % (-w[:, 1].min()))
    print('steering wheel hub', hub.round(3), 'axis', axis.round(3))
    print('model height %.4f m' % (size_m[1]))
    for end, at in car.get('plates', {}).items():
        print(f'{end} plate at {to_game(np.array(to_yup(np.array(at)))).round(3)}')


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if argv and argv[0] == 'dump':
        dump(argv[1], argv[2], argv[3], argv[4] if len(argv) > 4 else '')
    else:
        build(argv[0], argv[1])
