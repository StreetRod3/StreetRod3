#!/usr/bin/env python3
"""Convert a car from Libau Media's "FREE 1950s Car Variety Pack" into a car body GLB.

    python3 -I tools/variety_pack_to_glb.py hudson-1951 assets/cars/hudson-hornet-1951.glb

Source: "FREE 1950s Car Variety Pack" by Libau Media (robinmikart), CC-BY-4.0,
https://sketchfab.com/3d-models/free-1950s-car-variety-pack-067c3ca92ac0489daadc39ba8b208795

The first argument names a file in reference/cars/varietypack/split/ (written by
tools/split_variety_pack.py) and an entry in CARS. Each car there is one joined mesh:
body, chrome, interior and wheels together, colored mostly by material settings (the
ambientCG images most materials used are not in the download). Blender opens the file
(this script runs itself under `blender -b` for that, so Blender must be on the PATH)
and hands back every triangle with its material and the loose part it belongs to; the
rest is plain Python. In the model's own frame (after the pack scene's 45 degree turn is
taken out) the nose points along -Y, Z is up and the driver's side is +X.

What goes where is found by loose part:

  * the wheels are left out (the game mounts its own wheels and suspension): the tires
    are the parts of the tire material that reach the floor, and every part inside a
    tire's box, or inboard of it by up to WELL_IN or centered on the hub and outboard by up to WELL_OUT, is a wheel part (rim, hubcap,
    whitewall, brake backing plate, spring hangers);
  * the tailpipes are left out: long, low parts that run out behind the rear axle;
  * the bumpers are every part that lies wholly inside the car's BUMPER boxes, so the
    game can strip them;
  * the steering wheel is the rim part (the biggest part of its material near STEER_AT)
    and every part inside the rim's box; scaled evenly so it stays round, with +Z down
    the column so the game turns it.

The GLB is laid out like the Studebaker's (tools/studebaker_to_glb.py):

  * Y up, nose along +Z, driver's side +X;
  * centered on X and Z, lowest point of the body at Y = 0;
  * real size in meters: the width over the painted body and the height from the bottom
    of the model's tires to the roof each scaled on their own; along the car, the stretch
    between the axles is scaled to the real wheelbase and the overhangs to what is left
    of the real overall length, easing from one scale to the other around each axle
    (BLEND), so the car is neither too long nor too short in the wheelbase;
  * the front lamps the model gives its tail-light material are clear parking lamps;
  * a palette texture, CELL px per color: the body paint is white with alpha 1, which
    car_paint_mask.gdshader multiplies by the car's paint; everything else alpha 0;
  * an ORM palette in the same layout (R = AO, G = roughness, B = metallic);
  * the glass as its own see-through material (GLASS_MATERIAL), so the paint shader
    never touches it;
  * the dials (`dials` in CARS) as working gauges with printed faces and needles
    (tools/variety_pack_dash.py);
  * the pack's plates (they read "LIBAU") replaced by the blank plate,
    assets/cars/plate-blank.png, laid over each one in its own plane on a material
    named `plate`, so a plate of the player's own can go there later.

The numbers the .car file needs are printed at the end.
"""
import json
import math
import os
import subprocess
import sys
import tempfile

PACK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'reference', 'cars', 'varietypack')
CELL = 16
IN = 0.0254

## Per car: the real car's size and wheelbase (inches), its paint materials, the boxes
## that hold its bumpers (any number of boxes each) and where its steering wheel's rim
## is (its material and a point on it, or `box` and a box round the whole wheel), all in
## the model's frame (meters, nose -Y, Z up, driver's side +X). Optional: `tire` and
## `dial_face`, where the car's tire and gauge-face materials have names of their own;
## `drop`, boxes whose parts are left out, and `drop_materials`, materials left out;
## `recolor`, triangles that take another material's look (those of the `from`
## materials in the parts wholly inside `parts_in` (of at least `min_part_tris`
## triangles, given that), or with their middles inside
## `tris_in` and, given `facing`, facing that way); `fill`, flat four-cornered panels
## added in a material's look (material, corners, outward normal); `badges`, decal
## materials drawn as chrome lettering cut out by their image (a mask, white where the
## letters are), by the image's file name in textures/ (or a mask and an image of the
## letters' colors); `height` None scales the height as the width; `dial_order` 'size'
## gives the `dials` kinds from the biggest dial down; `clamp` pulls the parts wholly
## inside `parts_in` in along an axis (0 X, 1 Y, 2 Z) to between `min` and `max`.
CARS = {
    # 1951 Hudson Hornet club coupe: 208.5 in long, 77.4 in wide, 60.4 in high on a 124 in
    # wheelbase, 7.10-15 tires (conceptcarz, Series 7A club coupe).
    'hudson-1951': {
        'size_in': (208.5, 77.4, 60.4),
        'wheelbase_in': 124.0,
        'paint': {'green_metallic'},
        'bumpers': {
            # The bar with its guards and plate; the two arms that hold it to the frame;
            # the cross bar and the bracket just behind its middle.
            'bumper_front': [((-1.2, -2.9, 0.0), (1.2, -2.30, 0.60)),
                             ((0.38, -2.35, 0.30), (0.6, -1.50, 0.49)),
                             ((-0.6, -2.35, 0.30), (-0.38, -1.50, 0.49)),
                             ((-0.3, -2.35, 0.30), (0.3, -2.10, 0.49))],
            # The bar, then the guards, the plate and its holder between them, which stand
            # taller (between the tail lights, which stay on the body).
            'bumper_rear': [((-1.2, 2.25, 0.0), (1.2, 2.9, 0.60)),
                            ((-0.6, 2.58, 0.0), (0.6, 2.9, 0.72))],
        },
        'steer': ('paint_black', (0.40, -0.455, 1.12)),
        # Two dials in front of the driver: from the middle out, the combination gauge
        # and the speedometer (tools/variety_pack_dash.py).
        'dials': ['combo', 'speedo'],
    },
    # 1952 Buick Special two-door Deluxe sedan (model 48D): 204 in long, 76.7 in wide,
    # 63.4 in high on a 121.5 in wheelbase (Hometown Buick, model 48D).
    'buick-1952-coupe': {
        'size_in': (204.0, 76.7, 63.4),
        'wheelbase_in': 121.5,
        'paint': {'red_paint_metallic'},
        'bumpers': {
            'bumper_front': [((-1.1, -2.6, 0.0), (1.1, -1.95, 0.64)),
                             ((0.35, -2.05, 0.32), (0.6, -1.30, 0.49)),
                             ((-0.6, -2.05, 0.32), (-0.35, -1.30, 0.49)),
                             ((-0.3, -2.05, 0.32), (0.3, -1.80, 0.49))],
            'bumper_rear': [((-1.1, 1.95, 0.0), (1.1, 2.6, 0.62)),
                            ((-0.4, 2.2, 0.0), (0.4, 2.6, 0.66))],
        },
        'steer': ('Metal_painted', (0.36, -0.305, 1.055)),
        # One dial in front of the driver: the speedometer with the gas gauge in it.
        'dials': ['speedo_fuel'],
        # Just above the side strip (z 0.75) the rear quarter's front edge reaches 6 mm
        # forward over the door's back edge (y 0.26) and stands 6 mm proud of it, tapering
        # out 14 cm back; it cast a shadow onto the door. It is trimmed in under the door
        # skin there (both sides).
        'trim': [{'panel': 'red_paint_metallic',
                  'region': ((0.85, 0.24, 0.70), (1.05, 0.42, 0.80)),
                  'full': ((0.24, 0.72), (0.30, 0.785)),
                  'ref': ((0.85, 0.245, 0.68), (1.05, 0.268, 0.82))}],
    },
    # 1950 Ford Custom Deluxe Fordor sedan, made from the pack's police car: 196.8 in long,
    # 72.8 in wide, 63.1 in high on a 114 in wheelbase (Wikipedia, 1949 Ford; Ford's 1949
    # specifications for the height).
    'ford-1950-police': {
        'size_in': (196.8, 72.8, 63.1),
        'wheelbase_in': 114.0,
        # Black with white front doors as a police car; all of it is the paint here, and so
        # is the top of the dash in the middle (its image, a ribbed one, is in `bars`).
        'paint': {'paint_black', 'paint_whitee', 'bars'},
        'recolor': [
            # The gravel pan under the grille, part of the grille's mesh in the grilles'
            # dark material, is the body's.
            {'from': {'grooves'}, 'to': 'paint_black', 'parts_in': ((-1.0, -2.7, 0.3), (0.85, -2.1, 0.9))},
            # The headliner along the windshield's top, by the sun visor, is in the paint.
            {'from': {'paint_black'}, 'to': 'seats', 'tris_in': ((-0.75, -0.68, 1.46), (0.6, -0.40, 1.60)),
             'facing': (0.0, 0.0, -1.0)},
        ],
        'tire': 'tyre texture bake',
        'dial_face': 'textureford',
        'bumpers': {
            # The bar with its two small guards and the front plate under it.
            'bumper_front': [((-1.1, -2.75, 0.2), (1.0, -2.15, 0.47))],
            # The bar and its guards; the rear plate is on the trunk panel and stays.
            'bumper_rear': [((-1.1, 2.25, 0.25), (1.0, 2.75, 0.47))],
        },
        'steer': ('bakelite', (0.326, -0.595, 1.024)),
        # One dial in front of the driver, the speedometer with the small gauges in it.
        'dials': ['speedo_fuel'],
        # The police gear: the "POLICE" lettering on roof, hood, doors, fenders and trunk,
        # and the radio under the dash ...
        'drop_materials': {'police_car1', 'motorola'},
        # ... the roof lights with their bases and the siren, the spotlight on its
        # bracket by the driver's windshield pillar, the antennas on the cowl and the rear
        # fenders, the wire screen behind the front seat and the rest of the radio with
        # its microphone's coiled cord.
        'drop': [((0.3, -0.6, 1.53), (0.55, -0.42, 1.76)),
                 ((-0.7, -0.6, 1.53), (-0.5, -0.42, 1.76)),
                 ((-0.2, -0.62, 1.62), (0.05, -0.19, 1.95)),
                 ((0.76, -1.06, 0.98), (1.05, -0.92, 1.38)),
                 ((-0.82, -1.01, 1.11), (-0.79, -0.98, 1.67)),
                 ((-0.82, 2.04, 1.0), (-0.79, 2.28, 1.78)),
                 ((0.67, 2.04, 1.0), (0.70, 2.28, 1.78)),
                 ((-0.87, 0.17, 0.31), (0.73, 0.21, 1.65)),
                 ((-0.57, -0.98, 1.09), (-0.22, -0.69, 1.31))],
    },
    # 1955 Packard Clipper Custom Constellation hardtop: 214.8 in long, 78.0 in wide,
    # 62.0 in high on a 122 in wheelbase (Redbook, via carsales).
    'packard-1955-clipper': {
        'size_in': (214.8, 78.0, 62.0),
        'wheelbase_in': 122.0,
        # The red; the cream roof and rear sides stay cream.
        'paint': {'packard_red'},
        # The bumper hides an opening under the grille, between the fenders' cream lower
        # corners; a cream panel closes it, just behind the grille's bottom bar and the
        # fenders' front edges.
        'fill': [('paint_white_real', ((-0.68, -2.54, 0.34), (0.68, -2.54, 0.34), (0.68, -2.54, 0.56),
                                       (-0.68, -2.54, 0.56)), (0.0, -1.0, 0.0))],
        # "Packard" on the hood's front and the trunk's left, "Clipper" on its right.
        'badges': {'platesandbadges.001': 'packardplatesandAlpha.jpg'},
        'tire': 'tyre tread.002',
        'dial_face': 'gauge.001',
        'bumpers': {
            # The bar with its two bullet guards, the bars between them, the plate under
            # it and the bars behind it (not the strip under the grille, which is the
            # grille's).
            'bumper_front': [((-1.1, -2.9, 0.25), (1.1, -2.296, 0.63))],
            # The bar with the exhaust ports in its ends, the guards with the lamps in
            # them and the plate between them.
            'bumper_rear': [((-1.1, 2.40, 0.3), (1.1, 2.85, 0.70))],
        },
        # The rim is in segments, red and cream.
        'steer': ('box', ((0.23, -0.665, 0.80), (0.70, -0.48, 1.235))),
        # From the middle of the car out: the gauges on the speedometer's inner side (top,
        # bottom), the speedometer, those on its outer side (bottom, top).
        'dials': ['fuel', 'temp', 'speedo', 'amp', 'oil'],
    },
    # 1955 Packard Patrician four-door sedan: 219.7 in long, 78.3 in wide, 62.2 in high
    # on a 127 in wheelbase (Wikipedia, Packard Patrician).
    'packard-1955-patrician': {
        'size_in': (219.7, 78.3, 62.2),
        'wheelbase_in': 127.0,
        # The maroon; the cream roof stays cream.
        'paint': {'bronze_paint'},
        'tire': 'tyre tread.001',
        'dial_face': 'gauge',
        'bumpers': {
            # The bar with its bullet guards, the bars under the grille between them, the
            # plate and the brackets behind.
            'bumper_front': [((-1.1, -2.9, 0.2), (1.1, -2.30, 0.59))],
            # The bar with the exhaust ports in its ends, the guards with their lamps.
            'bumper_rear': [((-1.1, 2.40, 0.3), (1.1, 2.85, 0.65))],
        },
        'steer': ('box', ((0.23, -0.665, 0.77), (0.70, -0.48, 1.22))),
        'dials': ['fuel', 'temp', 'speedo', 'amp', 'oil'],
        # The bumper hides an opening under the grille, above the cream valance; a cream
        # panel closes it, behind the valance's and the fenders' front edges.
        'fill': [('paint_white_real', ((-0.68, -2.56, 0.34), (0.68, -2.56, 0.34), (0.68, -2.56, 0.54),
                                       (-0.68, -2.56, 0.54)), (0.0, -1.0, 0.0))],
        # "Packard" and "Patrician" on the trunk, "The Patrician" in gold on the doors.
        'badges': {'platesandbadges': ('patrician_alpha.png', 'patrician_colors2.png')},
    },
    # 1950 Ford Custom Deluxe station wagon: 208.0 in long on a 114 in wheelbase, the
    # sedan's front end (72.8 in over its fenders; 76.4 in over the wagon's wood); its
    # height is not given, so it scales as the width (Ford's specifications, April 1949).
    'ford-1950-wagon': {
        'size_in': (208.0, 72.8, None),
        'wheelbase_in': 114.0,
        # The red, the top of the dash in the middle as on the sedan, and the spare's wheel
        # on the tailgate, body colored as the pack has it (user, 2026-11-23); the wood
        # stays.
        'paint': {'red_paint_metallic', 'bars', 'v8wheel'},
        'tire': 'tyre black',
        'dial_face': 'textureford',
        'bumpers': {
            'bumper_front': [((-1.0, -2.75, 0.2), (1.0, -2.15, 0.5))],
            # The two halves with their guards, and the plate on its holder between them.
            'bumper_rear': [((-1.0, 2.2, 0.25), (1.0, 2.7, 0.5))],
        },
        'steer': ('bakelite', (0.398, -0.58, 1.049)),
        'dials': ['speedo_fuel'],
        # The gravel pan under the grille, part of the grille's mesh in the frame's black,
        # is the body's (not the small frame pieces behind the grille).
        'recolor': [{'from': {'CHASSIS'}, 'to': 'red_paint_metallic',
                     'parts_in': ((-0.9, -2.65, 0.3), (0.9, -2.05, 0.9)), 'min_part_tris': 200},
                    # The spare's tire on the tailgate is in the body's red; it is the
                    # tires' black (user, 2026-11-23).
                    {'from': {'red_paint_metallic'}, 'to': 'tyre black',
                     'parts_in': ((-0.4, 2.15, 0.55), (0.4, 2.7, 1.3))}],
    },
    # 1954 Buick Special four-door sedan (Series 40): 206.3 in long, 76.8 in wide, 60.5 in
    # high on a 122 in wheelbase (AMA specifications, January 1954). The pack's model is
    # 250 in long on a 150 in wheelbase.
    'buick-1954': {
        'size_in': (206.3, 76.8, 60.5),
        'wheelbase_in': 122.0,
        # The blue; the white roof stays white.
        'paint': {'blue_metallic'},
        'dial_face': 'buick_dash',
        'bumpers': {
            # The bar, the bar under it, the guards and their big bullets, a bracket and
            # the plate.
            'bumper_front': [((-1.1, -3.2, 0.2), (1.1, -2.55, 0.66))],
            # The bar, the guards and their bullets (the plate is on the body).
            'bumper_rear': [((-1.1, 2.55, 0.2), (1.1, 3.2, 0.62))],
        },
        'steer': ('blue_metallic', (0.397, -0.434, 1.094)),
        # The bumper hides an opening under the grille, between the fenders; a body panel
        # closes it, set back to where the fenders' bottom edges curve in.
        'fill': [('blue_metallic', ((-0.78, -2.71, 0.40), (0.78, -2.71, 0.40), (0.78, -2.71, 0.64),
                                    (-0.78, -2.71, 0.64)), (0.0, -1.0, 0.0))],
        # The frame rails run out through the panels behind the bumpers, the ends showing
        # as brackets with the bumpers off; they end inside the body.
        'clamp': [{'parts_in': ((-0.7, -2.9, 0.25), (0.7, 2.85, 0.58)), 'axis': 1, 'min': -2.69, 'max': 2.70}],
        # The long strip speedometer, the small strip under it.
        'dials': ['ribbon_speedo', 'ribbon_fuel'],
        'dial_order': 'size',
    },
}

TIRE = 'tyre'
## The dials' faces: one flat piece of this material in each dial (and in a small dial
## across the dash on the passenger's side, which is left as it is).
DIAL_FACE = 'textureford.001'
GLASS = {'Glass', 'glass.001', 'Glass_Window_Neutral', 'Glass_Window_Neutral.001'}
## The pack's plates, which give way to the blank plate (tools/make_blank_plate.py) on a
## material named `plate`, so the game can later put the player's own plate there.
PLATE = {'number plate diffuse', 'numberplate'}
PLATE_IMAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'cars', 'plate-blank.png')
## How far in front of the pack's plate the blank one sits (m, model scale).
PLATE_OUT = 0.002
## The wheel zone reaches this far inboard of each tire (m): the brake backing plates and
## the spring hangers go with the wheels.
WELL_IN = 0.25
## ... and this far outboard: the Hudson's hubcaps stand 2 cm proud of its tires.
WELL_OUT = 0.05
## A part out there is a wheel part only if its middle is this close to the hub (m).
HUB_CENTERED = 0.1
## Tailpipes: parts longer than PIPE_LONG (m) whose top is below PIPE_TOP and whose
## back end is more than PIPE_BEHIND behind the rear axle (the Packard's run out through
## its rear bumper and reach 0.48 m up).
PIPE_LONG = 1.5
PIPE_TOP = 0.5
PIPE_BEHIND = 0.6
## The length scale eases from the wheelbase's to the overhangs' over this far either
## side of each axle (m).
BLEND = 0.35
## A trimmed panel edge ends up this far inside the skin it meets (m), so where the two
## overlap the neighbor is drawn and they don't flicker.
TRIM_UNDER = 0.001
## The badges' image size (px).
BADGE_TEX = 512
## Clear glass with a faint green tint, as on the Studebaker.
GLASS_MATERIAL = {
    'name': 'glass',
    'pbrMetallicRoughness': {'baseColorFactor': [0.62, 0.72, 0.70, 0.22],
                             'metallicFactor': 0.0, 'roughnessFactor': 0.04},
    'alphaMode': 'BLEND',
    'doubleSided': True,
}
PLAIN = (255, round(0.82 * 255), round(0.05 * 255))
CHROME = ((240, 240, 244), (255, 15, 255))
## The model's front lamps in its tail-light material: the real cars' parking lamps were
## clear glass.
PARKING_LAMP = ((240, 232, 210), (255, 40, 30))
## (color, (AO, roughness, metallic)) by the pack's material names; any other material
## takes its color, roughness and metallic from its own settings (or the mean of its
## image, where the image is in the download).
LOOKS = {
    'Metallic': CHROME,
    'chrome_shiny': CHROME,
    'mirror': CHROME,
    'mirror.001': CHROME,
    'aloominum': ((200, 204, 208), (255, 60, 255)),
    'headlight glass': ((235, 235, 225), (255, 40, 30)),
    'tail light': ((200, 12, 18), (255, 60, 10)),
    'paint_black': ((14, 14, 14), (255, 110, 10)),
    'blak': ((10, 10, 10), (255, 140, 10)),
    'Metal_painted': ((14, 14, 14), (255, 110, 10)),
    'CHASSIS': ((22, 22, 22), (255, 200, 30)),
    'lorrymetal': ((30, 24, 22), (255, 180, 30)),
    'grooves': ((40, 40, 40), (255, 120, 200)),
    # The gold script on the Hudson's rear fenders.
    'taxi paint': ((232, 196, 96), (255, 40, 255)),
    'tyre': ((16, 16, 16), (255, 200, 10)),
    # The Packard's chrome and carpet, whose images are not in the download.
    'metal': CHROME,
    'carped_red': ((96, 18, 18), (255, 240, 10)),
}
## A dial's face is at least this big across (m, model scale) and flat to within
## DIAL_FLAT; on the driver's side, at least DIAL_SIDE out from the middle (m, game).
DIAL_MIN = 0.03
DIAL_FLAT = 0.002
DIAL_SIDE = 0.15


def srgb(c):
    c = max(0.0, min(1.0, c))
    return round(255 * (c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055))


def dump(blend, out):
    """Under Blender: every triangle of the file's one mesh in the model's frame, with its
    normals, UVs, material index and loose part, into an .npz; material settings into
    out.json."""
    import bpy
    import mathutils
    import numpy as np
    bpy.ops.wm.open_mainfile(filepath=blend, load_ui=False)
    obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    me = obj.data
    me.calc_loop_triangles()
    tris = me.loop_triangles
    n = len(tris)
    loops = np.empty(n * 3, np.int64)
    tris.foreach_get('loops', loops)
    mats = np.empty(n, np.int64)
    tris.foreach_get('material_index', mats)
    tv = np.empty(n * 3, np.int64)
    tris.foreach_get('vertices', tv)
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    nrm = np.empty(len(me.loops) * 3)
    me.corner_normals.foreach_get('vector', nrm)
    nrm = nrm.reshape(-1, 3)
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2)
    ev = np.empty(len(me.edges) * 2, np.int64)
    me.edges.foreach_get('vertices', ev)
    parent = np.arange(len(me.vertices))

    def find(a):
        root = a
        while parent[root] != root:
            root = parent[root]
        while parent[a] != root:
            parent[a], a = root, parent[a]
        return root
    for a, b in ev.reshape(-1, 2):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    roots = np.array([find(v) for v in range(len(me.vertices))])
    _, comp = np.unique(roots, return_inverse=True)
    # The pack scene turns every car 45 degrees about Z; that turn is taken out, the
    # small lean it also carries is kept.
    rz = obj.matrix_world.to_euler().z
    m = np.array(mathutils.Matrix.Rotation(-rz, 4, 'Z') @ obj.matrix_world)
    lin = m[:3, :3]
    pos = co[tv] @ lin.T + m[:3, 3]
    normals = nrm[loops] @ np.linalg.inv(lin)
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
    info = []
    for slot in obj.material_slots:
        mat = slot.material
        d = {'name': mat.name if mat else ''}
        if mat and mat.use_nodes:
            bsdf = [nd for nd in mat.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED']
            if bsdf:
                b = bsdf[0]
                d['color'] = list(b.inputs['Base Color'].default_value)[:3]
                d['metallic'] = b.inputs['Metallic'].default_value
                d['roughness'] = b.inputs['Roughness'].default_value
                if b.inputs['Base Color'].is_linked:
                    imgs = [nd.image for nd in mat.node_tree.nodes if nd.type == 'TEX_IMAGE' and nd.image]
                    paths = [bpy.path.abspath(i.filepath) for i in imgs]
                    d['image'] = next((p for p in paths if os.path.exists(p) and 'ormal' not in p
                                       and 'ough' not in p and 'etal' not in p), None)
        info.append(d)
    np.savez(out, pos=pos.reshape(-1, 3, 3), nrm=normals.reshape(-1, 3, 3), uv=uv[loops].reshape(-1, 3, 2),
             mat=mats, part=comp[tv[0::3]])
    with open(out + '.json', 'w') as f:
        json.dump(info, f)


def look(info):
    """(color, ORM) for a material the LOOKS table doesn't name."""
    import numpy as np
    from PIL import Image
    name = info['name'].split('.')[0] if info['name'] not in LOOKS else info['name']
    if name in LOOKS:
        return LOOKS[name]
    if info.get('image'):
        rgb = np.asarray(Image.open(info['image']).convert('RGB').resize((64, 64)), np.float64)
        color = tuple(int(v) for v in rgb.reshape(-1, 3).mean(0).round())
    else:
        color = tuple(srgb(c) for c in info.get('color', (0.5, 0.5, 0.5)))
    rough = round(255 * info.get('roughness', 0.5))
    metal = round(255 * info.get('metallic', 0.0))
    return color, (255, rough, metal)


def length_map(z, front, rear, length, wheelbase, lo, hi):
    """The game's Z for each model Z: the stretch between the axles scales the model's
    wheelbase to the real one, the overhangs beyond them take what is left of the real
    length, and the scale eases from one to the other over BLEND either side of each
    axle, so no panel gets a crease. Returns (mapped z, the local scale at each z)."""
    import numpy as np
    grid = np.linspace(lo - 0.05, hi + 0.05, 8001)

    def ease(t):
        t = np.clip(t, 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    over = np.maximum(ease((grid - front + BLEND) / (2 * BLEND)), ease((rear + BLEND - grid) / (2 * BLEND)))
    step = grid[1] - grid[0]
    inner = np.concatenate([[0.0], np.cumsum((1.0 - over[1:] + 1.0 - over[:-1]) / 2 * step)])
    outer = np.concatenate([[0.0], np.cumsum((over[1:] + over[:-1]) / 2 * step)])

    def at(a, v):
        return np.interp(v, grid, a)
    rows = np.array([[at(inner, front) - at(inner, rear), at(outer, front) - at(outer, rear)],
                     [at(inner, hi) - at(inner, lo), at(outer, hi) - at(outer, lo)]])
    s_mid, s_over = np.linalg.solve(rows, [wheelbase, length])
    mapped = s_mid * inner + s_over * outer
    mapped -= (at(mapped, lo) + at(mapped, hi)) / 2
    local = s_mid * (1.0 - over) + s_over * over
    return np.interp(z, grid, mapped), np.interp(z, grid, local), (s_mid, s_over)


def trim_lip(pos, nrm, panel, part, trim):
    """Bring a panel's edge in flush with the panel it meets at a seam, on both sides of
    the car (model frame, |x| outward). The panel being trimmed is the part with the
    most of `panel`'s outward faces in the `region` box; the `ref` box holds the
    neighbor's edge, and the neighbor's outermost |x| there at each height, on each side,
    is its skin.
    Every point of the trimmed panel's outward skin in the region that stands out past
    that skin comes in to TRIM_UNDER below it, fully inside the `full` (y, z) span and
    easing to nothing at the region's edges. Each corner's normal turns by as much as
    the surface around it turned, so nothing outside the change shades differently.
    Changes pos and nrm."""
    import numpy as np
    (rx0, ry0, rz0), (rx1, ry1, rz1) = trim['region']
    (fy0, fz0), (fy1, fz1) = trim['full']
    (ax0, ay0, az0), (ax1, ay1, az1) = trim['ref']
    flat = pos.reshape(-1, 3)
    ax = np.abs(flat[:, 0])

    def in_box(lo, hi):
        return (ax >= lo[0]) & (ax <= hi[0]) & (flat[:, 1] >= lo[1]) & (flat[:, 1] <= hi[1]) \
            & (flat[:, 2] >= lo[2]) & (flat[:, 2] <= hi[2])
    # Outward by the model's own normals: the mirrored side's faces are wound the other
    # way round.
    outward = panel & (np.sign(pos.mean(1)[:, 0]) * nrm.mean(1)[:, 0] > 0.2)
    region = in_box((rx0, ry0, rz0), (rx1, ry1, rz1))
    hits = outward & region.reshape(-1, 3).all(1)
    trimmed = np.bincount(part[hits]).argmax()
    corner_part = np.repeat(part, 3)
    ref = in_box((ax0, ay0, az0), (ax1, ay1, az1)) & (corner_part != trimmed) & np.repeat(panel, 3)
    # Each side its own level: the model is not quite centered on X.
    bins = np.arange(az0, az1 + 0.005, 0.005)
    target = np.zeros(len(flat))
    for side in (1.0, -1.0):
        here = np.sign(flat[:, 0]) == side
        level = np.array([ax[ref & here & (np.abs(flat[:, 2] - z) < 0.006)].max(initial=-1.0) for z in bins])
        ok = level > 0
        target[here] = np.interp(flat[here, 2], bins[ok], level[ok]) - TRIM_UNDER
    skin = region & np.repeat(outward & (part == trimmed), 3)

    def ease(v, a0, a1, b0, b1):
        up = np.clip((v - a0) / max(a1 - a0, 1e-9), 0, 1)
        down = np.clip((b1 - v) / max(b1 - b0, 1e-9), 0, 1)
        t = np.minimum(up, down)
        return t * t * (3 - 2 * t)
    weight = ease(flat[:, 1], ry0 - 1.0, ry0, fy1, ry1) * ease(flat[:, 2], rz0, fz0, fz1, rz1)
    cut = np.where(skin, np.minimum(target - ax, 0.0) * weight, 0.0)
    # Every corner at a point that moves moves with it, whatever part it belongs to.
    _, vid = np.unique(np.round(flat, 5), axis=0, return_inverse=True)
    vid = vid.reshape(-1)
    nv = vid.max() + 1
    vcut = np.zeros(nv)
    np.minimum.at(vcut, vid, cut)

    def vertex_normals(points):
        tri = points.reshape(-1, 3, 3)
        f = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        g = np.zeros((nv, 3))
        for c in range(3):
            np.add.at(g, vid[c::3], f)
        return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)
    before = vertex_normals(flat)
    flat[:, 0] += np.sign(flat[:, 0]) * vcut[vid]
    pos[:] = flat.reshape(pos.shape)
    after = vertex_normals(flat)
    turned = np.linalg.norm(after - before, axis=1) > 1e-6
    corners = turned[vid]
    n = nrm.reshape(-1, 3)
    n[corners] += (after - before)[vid[corners]]
    n[corners] /= np.maximum(np.linalg.norm(n[corners], axis=1, keepdims=True), 1e-12)
    nrm[:] = n.reshape(nrm.shape)
    return float(-vcut.min())


def plate_quad(tris, facing):
    """A plate face over the pack's plate (its triangles, game frame): in the plane of the
    plate, its long side level, covering the plate's extent, PLATE_OUT in front of it,
    with UVs over the whole plate image seen from in front."""
    import numpy as np
    pts = tris.reshape(-1, 3)
    mid = (pts.min(0) + pts.max(0)) / 2
    _, _, vt = np.linalg.svd(pts - pts.mean(0))
    normal = vt[2] * (1.0 if vt[2][2] * facing > 0 else -1.0)
    up = np.array([0.0, 1.0, 0.0]) - normal[1] * normal
    up /= np.linalg.norm(up)
    right = np.cross(up, normal)
    q = pts - mid
    half_w = np.abs(q @ right).max()
    half_h = np.abs(q @ up).max()
    front_face = (q @ normal).max()
    c = mid + normal * (front_face + PLATE_OUT)
    corners = [c - right * half_w - up * half_h, c + right * half_w - up * half_h,
               c + right * half_w + up * half_h, c - right * half_w + up * half_h]
    uv = np.array([[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]])
    order = [(0, 1, 2), (0, 2, 3)]
    pos = np.array([[corners[i] for i in t] for t in order])
    uvs = np.array([[uv[i] for i in t] for t in order])
    nrm = np.zeros_like(pos) + normal
    return pos, nrm, uvs, (half_w * 2, half_h * 2)


def dial_faces(tris):
    """The gauge-face triangles in pieces that hang together by their corners, as lists
    of their indices: one piece per face (a mesh part can hold several faces, and a
    face's center knob is a part of its own)."""
    import numpy as np
    keys = np.round(tris.reshape(-1, 3), 5)
    _, corner = np.unique(keys, axis=0, return_inverse=True)
    corner = corner.reshape(-1, 3)
    parent = np.arange(corner.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for a, b, c in corner:
        for x, y in ((a, b), (b, c)):
            rx, ry = find(x), find(y)
            if rx != ry:
                parent[rx] = ry
    piece = np.array([find(a) for a in corner[:, 0]])
    return [np.nonzero(piece == k)[0] for k in np.unique(piece)]


def build(car, dst):
    import numpy as np
    from PIL import Image
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from studebaker_to_glb import Gltf, ring_axis, share_corners, png_bytes
    from studebaker_dash import quaternion

    cfg = CARS[car]
    blend = os.path.join(PACK, 'split', car + '.blend')
    with tempfile.TemporaryDirectory() as tmp:
        npz = os.path.join(tmp, 'mesh.npz')
        subprocess.run(['blender', '-b', '--factory-startup', '--disable-autoexec', '--python',
                        os.path.abspath(__file__), '--', 'dump', blend, npz],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        data = dict(np.load(npz))
        info = json.load(open(npz + '.json'))
    pos, nrm, mat, part, uv = data['pos'], data['nrm'], data['mat'].copy(), data['part'], data['uv']
    names = [d['name'] for d in info]
    nparts = part.max() + 1
    plo = np.full((nparts, 3), np.inf)
    phi = np.full((nparts, 3), -np.inf)
    flat = pos.reshape(-1, 3)
    np.minimum.at(plo, np.repeat(part, 3), flat)
    np.maximum.at(phi, np.repeat(part, 3), flat)

    # Loose vertices with no faces make empty parts; they hold nothing.
    has_faces = np.bincount(part, minlength=nparts) > 0

    def inside(p, lo, hi, margin=0.0):
        return bool(has_faces[p] and np.all(plo[p] >= np.asarray(lo) - margin)
                    and np.all(phi[p] <= np.asarray(hi) + margin))

    # The wheels: everything in a tire's box, widened inboard by WELL_IN (the brake
    # backing plates and the spring hangers, which the game's own wheels and suspension
    # replace) and, for parts centered on the hub, outboard by WELL_OUT (hubcaps that
    # stand proud of the tire).
    floor = flat[:, 2].min()
    tire_mat = names.index(cfg.get('tire', TIRE))
    tires = [p for p in np.unique(part[mat == tire_mat]) if plo[p][2] < floor + 0.01]
    wheel_parts = set()
    for t in tires:
        lo, hi = plo[t].copy(), phi[t].copy()
        hub = (plo[t][1:] + phi[t][1:]) / 2
        out_lo, out_hi = lo.copy(), hi.copy()
        if lo[0] > 0:
            lo[0] -= WELL_IN
            out_hi[0] += WELL_OUT
        else:
            hi[0] += WELL_IN
            out_lo[0] -= WELL_OUT
        wheel_parts |= {p for p in range(nparts) if inside(p, lo, hi, 0.01)}
        # Outboard only what is centered on the hub: the hubcaps, not the script on a
        # fender skirt beside the tire.
        wheel_parts |= {p for p in range(nparts) if inside(p, out_lo, out_hi, 0.01)
                        and np.linalg.norm((plo[p][1:] + phi[p][1:]) / 2 - hub) < HUB_CENTERED}
    # The tailpipes: long, low parts that run out behind the rear axle.
    rear_axle = max((plo[t][1] + phi[t][1]) / 2 for t in tires)
    pipes = {p for p in range(nparts) if phi[p][1] - plo[p][1] > PIPE_LONG and phi[p][2] < PIPE_TOP
             and phi[p][1] > rear_axle + PIPE_BEHIND}
    gear = {p for lo, hi in cfg.get('drop', []) for p in range(nparts) if inside(p, lo, hi)}
    dropped = wheel_parts | pipes | gear
    keep = ~np.isin(part, list(dropped)) & ~np.isin(mat, [names.index(m) for m in cfg.get('drop_materials', ())])
    for rc in cfg.get('recolor', []):
        sel = np.isin(mat, [names.index(m) for m in rc['from']])
        if 'parts_in' in rc:
            big = np.bincount(part, minlength=nparts) >= rc.get('min_part_tris', 0)
            sel &= np.isin(part, [p for p in range(nparts) if inside(p, *rc['parts_in']) and big[p]])
        if 'tris_in' in rc:
            mid = pos.mean(1)
            sel &= np.all((mid >= rc['tris_in'][0]) & (mid <= rc['tris_in'][1]), 1)
        if 'facing' in rc:
            sel &= nrm.mean(1) @ np.asarray(rc['facing'], np.float64) > 0.3
        mat[sel] = names.index(rc['to'])

    for cl in cfg.get('clamp', []):
        sel = np.isin(part, [p for p in range(nparts) if inside(p, *cl['parts_in'])])
        pos[sel, :, cl['axis']] = np.clip(pos[sel, :, cl['axis']], cl.get('min', -np.inf), cl.get('max', np.inf))

    for trim in cfg.get('trim', []):
        trim_lip(pos, nrm, mat == names.index(trim['panel']), part, trim)

    steer_mat, steer_at = cfg['steer']
    if steer_mat == 'box':
        steer_box = steer_at
        steer_parts = {p for p in range(nparts) if inside(p, *steer_box)}
    else:
        near = [p for p in np.unique(part[mat == names.index(steer_mat)])
                if np.linalg.norm((plo[p] + phi[p]) / 2 - steer_at) < 0.1]
        rim_part = max(near, key=lambda p: np.sum(part == p))
        steer_box = (plo[rim_part], phi[rim_part])
        steer_parts = {p for p in range(nparts) if inside(p, plo[rim_part], phi[rim_part], 0.005)}
    group_of = np.full(nparts, 'body', object)
    for g, boxes in cfg['bumpers'].items():
        for lo, hi in boxes:
            for p in range(nparts):
                if inside(p, lo, hi) and p not in dropped:
                    group_of[p] = g
    for p in steer_parts:
        group_of[p] = 'driving_wheel'
    for fill_mat, corners, normal in cfg.get('fill', []):
        q = np.asarray(corners, np.float64)
        pos = np.concatenate([pos, np.array([[q[0], q[1], q[2]], [q[0], q[2], q[3]]])])
        nrm = np.concatenate([nrm, np.tile(np.asarray(normal, np.float64), (2, 3, 1))])
        uv = np.concatenate([uv, np.zeros((2, 3, 2))])
        mat = np.append(mat, [names.index(fill_mat)] * 2)
        part = np.append(part, [nparts] * 2)
        keep = np.append(keep, [True, True])
        group_of = np.append(group_of, np.array(['body'], object))
        nparts += 1

    # The model's frame (nose -Y, Z up) to the game's (Y up, nose +Z, driver's side +X).
    def to_yup(a):
        return np.stack([a[..., 0], a[..., 2], -a[..., 1]], -1)

    pos, nrm = to_yup(pos), to_yup(nrm)
    kept = pos[keep].reshape(-1, 3)
    paint_ids = [names.index(n) for n in cfg['paint']]
    body = pos[keep & np.isin(mat, paint_ids)].reshape(-1, 3)
    tire_pos = pos[np.isin(part, tires)].reshape(-1, 3)
    lo, hi = kept.min(0), kept.max(0)
    length_in, width_in, height_in = cfg['size_in']
    front_z = np.mean([(-(plo[t][1] + phi[t][1]) / 2) for t in tires if (plo[t][1] + phi[t][1]) / 2 < 0])
    rear_z = np.mean([(-(plo[t][1] + phi[t][1]) / 2) for t in tires if (plo[t][1] + phi[t][1]) / 2 >= 0])
    scale_x = width_in * IN / (body[:, 0].max() - body[:, 0].min())
    # With no height known, the height scales as the width does.
    scale_y = scale_x if height_in is None else height_in * IN / (hi[1] - tire_pos[:, 1].min())
    origin_xy = np.array([(body[:, 0].min() + body[:, 0].max()) / 2, lo[1]])

    def to_game(q):
        q = np.asarray(q, np.float64)
        z, _, _ = length_map(q[..., 2], front_z, rear_z, length_in * IN, cfg['wheelbase_in'] * IN, lo[2], hi[2])
        return np.stack([(q[..., 0] - origin_xy[0]) * scale_x, (q[..., 1] - origin_xy[1]) * scale_y, z], -1)

    def normals_to_game(q, n):
        _, local, _ = length_map(q[..., 2], front_z, rear_z, length_in * IN, cfg['wheelbase_in'] * IN, lo[2], hi[2])
        n = np.stack([n[..., 0] / scale_x, n[..., 1] / scale_y, n[..., 2] / local], -1)
        return n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-12)

    _, _, (s_mid, s_over) = length_map(np.zeros(1), front_z, rear_z, length_in * IN, cfg['wheelbase_in'] * IN, lo[2], hi[2])
    rim_mid_src = to_yup((np.asarray(steer_box[0]) + np.asarray(steer_box[1])) / 2)
    rim_mid = to_game(rim_mid_src)
    even = (scale_x + scale_y + s_mid) / 3

    # The dials: the flat pieces of the gauge-face material, big enough, on the driver's
    # side (the same face is on a clock, and on the Packard the radio, across the dash).
    # A knob of that material in the middle of one (the Packard's) gives way to the
    # needles' own hubs.
    if cfg.get('dials'):
        import variety_pack_dash as dash
        face_idx = np.nonzero(keep & (mat == names.index(cfg.get('dial_face', DIAL_FACE))))[0]
        pieces = []
        for idx in dial_faces(pos[face_idx]):
            tris = pos[face_idx[idx]]
            center, axis, radius = dash.dial_frame(tris)
            depth = np.ptp((tris.reshape(-1, 3) - center) @ axis)
            pieces.append((face_idx[idx], center, radius, 2 * radius >= DIAL_MIN and depth <= DIAL_FLAT))
        faces = [(c, r) for _, c, r, flat_face in pieces if flat_face]
        for idx, c, r, flat_face in pieces:
            if not flat_face and any(np.linalg.norm(c - fc) + r < fr for fc, fr in faces):
                keep[idx] = False
        dials = []
        for idx, _, _, flat_face in pieces:
            if flat_face:
                tris = to_game(pos[idx])
                center, axis, radius = dash.dial_frame(tris)
                dials.append((center, axis, radius, *dash.face_extent(tris, center, dash.pod_basis(axis))))
        dials = [d for d in dials if d[0][0] > DIAL_SIDE]
        if len(dials) != len(cfg['dials']):
            raise SystemExit(f'{len(dials)} dials found for {len(cfg["dials"])} kinds')

    # Each kept triangle's look: the paint, glass, the plate, or a palette color; the
    # front lamps in the tail-light material are parking lamps.
    tri_z = pos[..., 2].mean(1)
    looks = []
    groups = {}
    plate_parts = []
    for m in np.unique(mat[keep]):
        name = names[m]
        base = name.split('.')[0]
        for g in np.unique(group_of[part[keep & (mat == m)]]):
            sel_g = keep & (mat == m) & (group_of[part] == g)
            if name in PLATE:
                plate_parts += [(g, p) for p in np.unique(part[sel_g])]
                continue
            if name in cfg.get('badges', {}):
                badge_uv = uv[sel_g].copy()
                badge_uv[..., 1] = 1.0 - badge_uv[..., 1]
                gp = groups.setdefault(g, {'palette': [], 'glass': [], 'plate': [], 'badge': []})
                gp['badge'].append((to_game(pos[sel_g]), normals_to_game(pos[sel_g], nrm[sel_g]), badge_uv, name))
                continue
            for front_lamp in (False, True):
                sel = sel_g & ((tri_z > 0) == front_lamp) if base == 'tail light' else (sel_g if not front_lamp else None)
                if sel is None or not sel.any():
                    continue
                if g == 'driving_wheel':
                    p = rim_mid + (pos[sel] - rim_mid_src) * even
                    n = nrm[sel]
                else:
                    p = to_game(pos[sel])
                    n = normals_to_game(pos[sel], nrm[sel])
                gp = groups.setdefault(g, {'palette': [], 'glass': [], 'plate': [], 'badge': []})
                if name in GLASS:
                    gp['glass'].append((p, n))
                    continue
                if m in paint_ids:
                    lk = (((255, 255, 255), PLAIN), True)
                elif front_lamp:
                    lk = (PARKING_LAMP, False)
                else:
                    lk = (look(info[m]), False)
                if lk not in looks:
                    looks.append(lk)
                gp['palette'].append((p, n, looks.index(lk)))
    plate_sizes = []
    for g, p in plate_parts:
        t = to_game(pos[part == p])
        facing = 1 if t[..., 2].mean() > 0 else -1
        qp, qn, qu, size_m = plate_quad(t, facing)
        groups.setdefault(g, {'palette': [], 'glass': [], 'plate': [], 'badge': []})['plate'].append((qp, qn, qu))
        plate_sizes.append(size_m)

    grid = math.ceil(math.sqrt(len(looks)))
    size = grid * CELL
    albedo = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    orm = Image.new('RGB', (size, size), PLAIN)
    cells = []
    for i, ((color, rough), is_paint) in enumerate(looks):
        cx, cy = i % grid, i // grid
        box = (cx * CELL, cy * CELL, cx * CELL + CELL, cy * CELL + CELL)
        albedo.paste(tuple(color) + ((255,) if is_paint else (0,)), box)
        orm.paste(tuple(rough), box)
        cells.append(((cx + 0.5) / grid, (cy + 0.5) / grid))

    out = Gltf()
    plate_im = Image.open(PLATE_IMAGE).convert('RGB')
    plate_im.putalpha(0)
    out.images = [png_bytes(albedo), png_bytes(orm), png_bytes(plate_im)]
    out.textures = [0, 1, 2]
    out.materials = [{
        'name': car + '_palette',
        'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                 'metallicRoughnessTexture': {'index': 1},
                                 'metallicFactor': 1.0, 'roughnessFactor': 1.0},
        'alphaMode': 'OPAQUE', 'doubleSided': True}, GLASS_MATERIAL,
        {'name': 'plate', 'doubleSided': True,
         'pbrMetallicRoughness': {'baseColorTexture': {'index': 2}, 'metallicFactor': 0.3, 'roughnessFactor': 0.5}}]
    # The badges: chrome where their image is white, cut out elsewhere (the game's paint
    # leaves see-through materials alone).
    badge_material = {}
    for badge_name, image_name in cfg.get('badges', {}).items():
        image_name, color_name = (image_name, None) if isinstance(image_name, str) else image_name
        mask = Image.open(os.path.join(PACK, 'textures', image_name)).convert('L').resize((BADGE_TEX, BADGE_TEX), Image.LANCZOS)
        if color_name:
            badge_im = Image.open(os.path.join(PACK, 'textures', color_name)).convert('RGBA').resize(mask.size, Image.LANCZOS)
        else:
            badge_im = Image.new('RGBA', mask.size, CHROME[0] + (255,))
        badge_im.putalpha(mask)
        out.images.append(png_bytes(badge_im))
        out.textures.append(len(out.images) - 1)
        badge_material[badge_name] = len(out.materials)
        out.materials.append({'name': 'badge', 'doubleSided': True, 'alphaMode': 'MASK', 'alphaCutoff': 0.5,
                              'pbrMetallicRoughness': {'baseColorTexture': {'index': len(out.textures) - 1},
                                                       'metallicFactor': 1.0, 'roughnessFactor': 0.15}})

    def primitives(g, frame=None):
        gp = groups.get(g)
        prims = []
        if not gp:
            return prims

        def place(p, n):
            p, n = p.reshape(-1, 3), n.reshape(-1, 3)
            if frame is not None:
                o, b = frame
                p, n = (p - o) @ b, n @ b
            return p.astype(np.float32), n.astype(np.float32)
        if gp['palette']:
            p, n = place(np.concatenate([a for a, _, _ in gp['palette']]), np.concatenate([b for _, b, _ in gp['palette']]))
            u = np.repeat(np.array([cells[k] for a, _, k in gp['palette'] for _ in range(len(a))], np.float32), 3, 0)
            p, n, u, idx = share_corners(p, n, u)
            prims.append(out.primitive(p, n, idx, 0, u))
        if gp['glass']:
            p, n = place(np.concatenate([a for a, _ in gp['glass']]), np.concatenate([b for _, b in gp['glass']]))
            p, n, u, idx = share_corners(p, n, np.zeros((len(p), 2), np.float32))
            prims.append(out.primitive(p, n, idx, 1))
        if gp['plate']:
            p, n = place(np.concatenate([a for a, _, _ in gp['plate']]), np.concatenate([b for _, b, _ in gp['plate']]))
            u = np.concatenate([c for _, _, c in gp['plate']]).reshape(-1, 2).astype(np.float32)
            p, n, u, idx = share_corners(p, n, u)
            prims.append(out.primitive(p, n, idx, 2, u))
        for badge_name in sorted({k for _, _, _, k in gp['badge']}):
            these = [(a, b, c) for a, b, c, k in gp['badge'] if k == badge_name]
            p, n = place(np.concatenate([a for a, _, _ in these]), np.concatenate([b for _, b, _ in these]))
            u = np.concatenate([c for _, _, c in these]).reshape(-1, 2).astype(np.float32)
            p, n, u, idx = share_corners(p, n, u)
            prims.append(out.primitive(p, n, idx, badge_material[badge_name], u))
        return prims

    steer = np.concatenate([a for a, _, _ in groups['driving_wheel']['palette']]).reshape(-1, 3)
    hub, axis = ring_axis(steer)
    across = np.array([1.0, 0.0, 0.0]) - axis[0] * axis
    across /= np.linalg.norm(across)
    wheel_basis = np.stack([across, np.cross(axis, across), axis], 1)

    roots = [out.node(car, mesh=out.mesh(car, primitives('body')))]
    for g in cfg['bumpers']:
        if g in groups:
            roots.append(out.node(g, mesh=out.mesh(g, primitives(g))))
    wheel_mesh = out.mesh('driving_wheel_mesh', primitives('driving_wheel', (hub, wheel_basis)))
    roots.append(out.node('driving_wheel', translation=hub, rotation=quaternion(wheel_basis),
                          children=[out.node('driving_wheel_mesh', mesh=wheel_mesh)]))
    pods = []
    if cfg.get('dials'):
        pods = dash.build(dials, cfg['dials'], cfg.get('dial_order') == 'size')
        looks_mat = {}
        for key, material in dash.NEEDLE_MATERIALS.items():
            looks_mat[key] = len(out.materials)
            out.materials.append(material)
        for name, center, basis, kind, radius, parts in pods:
            children = []
            if kind:
                out.images.append(dash.face_png(kind, radius))
                out.textures.append(len(out.images) - 1)
                face_index = len(out.materials)
                out.materials.append(dash.face_material(kind, len(out.textures) - 1))
                ft, fn, fu = dash.face_mesh(kind, radius)
                p, n, u, idx = share_corners(ft.reshape(-1, 3).astype(np.float32), fn.reshape(-1, 3).astype(np.float32),
                                             fu.reshape(-1, 2).astype(np.float32))
                children.append(out.node(f'{name}_face', mesh=out.mesh(f'{name}_face', [out.primitive(p, n, idx, face_index, u)])))
            for node_name, key, tris, nrms in parts:
                p, n, u, idx = share_corners(tris.reshape(-1, 3).astype(np.float32), nrms.reshape(-1, 3).astype(np.float32),
                                             np.zeros((tris.size // 3, 2), np.float32))
                children.append(out.node(node_name, mesh=out.mesh(node_name, [out.primitive(p, n, idx, looks_mat[key])])))
            roots.append(out.node(name, translation=center, rotation=quaternion(basis), children=children))
    out.write(dst, roots)

    game = to_game(kept)
    size_m = game.max(0) - game.min(0)
    print(f'{dst}: {int(keep.sum())} tris, {len(looks)} colors, {os.path.getsize(dst) / 1e6:.1f} MB, '
          f'size {size_m.round(3)} m ({(size_m / IN).round(1)} in), scale x {scale_x:.3f} y {scale_y:.3f} '
          f'z {s_mid:.3f} between the axles, {s_over:.3f} on the overhangs')
    print('bumper parts:', {g: int(np.sum(group_of == g)) for g in cfg['bumpers']},
          'steering parts:', len(steer_parts), 'wheel parts:', len(wheel_parts), 'tailpipes:', len(pipes),
          'plates (in):', [tuple(round(float(v) / IN, 1) for v in s) for s in plate_sizes])
    w = to_game(tire_pos)
    front, rear = w[w[:, 2] > 0], w[w[:, 2] <= 0]
    radius = (w[:, 1].max() - w[:, 1].min()) / 2
    # The axles where the length map put them (the tires' own outlines lean toward the
    # overhangs, whose scale differs).
    fz = to_game(np.array([0.0, 0.0, front_z]))[2]
    rz = to_game(np.array([0.0, 0.0, rear_z]))[2]
    right = front[front[:, 0] > 0]
    track = (right[:, 0].min() + right[:, 0].max()) / 2
    wheel_y = (w[:, 1].min() + w[:, 1].max()) / 2
    print('model tire radius %.3f m (%.1f in diameter)' % (radius, radius * 2 / IN))
    print('wheel centers: x ±%.3f, y %.3f (body bottom = 0), front z %.3f, rear z %.3f, wheelbase %.1f in'
          % (track, wheel_y, fz, rz, (fz - rz) / IN))
    print('ground clearance in the model %.3f m' % (-w[:, 1].min()))
    print('steering wheel hub', hub.round(3), 'axis', axis.round(3))
    for name, center, basis, kind, radius, _ in pods:
        print(f'{name}: {kind or "needle"} at {center.round(3)}, face size {np.round(radius, 4)}')

if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if argv and argv[0] == 'dump':
        dump(argv[1], argv[2])
    else:
        build(argv[0], argv[1])
