#!/usr/bin/env python3
"""Split Libau Media's "FREE 1950s Car Variety Pack" scene into one .blend per vehicle.

    blender -b --factory-startup --disable-autoexec \
        reference/cars/varietypack/tosplit.blend --python tools/split_variety_pack.py

Source: "FREE 1950s Car Variety Pack" by Libau Media (robinmikart), CC-BY-4.0,
https://sketchfab.com/3d-models/free-1950s-car-variety-pack-067c3ca92ac0489daadc39ba8b208795

tosplit.blend is the pack's FBX (source/50scarpackFBX.fbx) opened in Blender, with the
Corvette, the Checker taxi and the Airstream trailer left out. Each vehicle there is one
joined mesh (body, interior and wheels together), scattered over a grid. This writes
reference/cars/varietypack/split/<name>.blend for each of them: only that vehicle, moved
so its footprint is centered on the origin, its mesh data and materials untouched. The
images point at reference/cars/varietypack/textures/ where the pack's file is there; the
others (most of them ambientCG materials, plus a few of the artist's own badge and gauge
images) are not in the download and stay pointing at the artist's own folders.
"""
import os
import re

import bpy
import mathutils

## Scene object name -> file name.
NAMES = {
    '50buick': 'buick-1950',
    '50fordpolice': 'ford-1950-police',
    '50fordwagon': 'ford-1950-wagon',
    '51hudson': 'hudson-1951',
    '52buick_conv': 'buick-1952-convertible',
    '52buick_coupe': 'buick-1952-coupe',
    '53fordpanel': 'ford-1953-panel',
    '54 usps jeep': 'jeep-1954-usps',
    '54buick': 'buick-1954',
    '54buickwagon': 'buick-1954-wagon',
    '55packard caribbean': 'packard-1955-caribbean',
    '55packard patrician': 'packard-1955-patrician',
    '55packardclipper': 'packard-1955-clipper',
}

PACK = os.path.dirname(bpy.data.filepath)
TEXTURES = os.path.join(PACK, 'textures')
OUT = os.path.join(PACK, 'split')


def norm(name):
    return re.sub(r'[ _]', '', name.lower())


def remap_images(have):
    for img in bpy.data.images:
        if not img.filepath:
            continue
        base = os.path.basename(img.filepath.replace('\\', '/'))
        hit = have.get(norm(base))
        if hit:
            img.filepath = os.path.join(TEXTURES, hit)


def main():
    src = bpy.data.filepath
    os.makedirs(OUT, exist_ok=True)
    have = {norm(f): f for f in os.listdir(TEXTURES)}
    for obj_name, file_name in NAMES.items():
        bpy.ops.wm.open_mainfile(filepath=src, load_ui=False)
        keep = bpy.data.objects[obj_name]
        for obj in list(bpy.data.objects):
            if obj is not keep:
                bpy.data.objects.remove(obj, do_unlink=True)
        corners = [keep.matrix_world @ mathutils.Vector(c) for c in keep.bound_box]
        mid_x = (min(c.x for c in corners) + max(c.x for c in corners)) / 2
        mid_y = (min(c.y for c in corners) + max(c.y for c in corners)) / 2
        keep.location.x -= mid_x
        keep.location.y -= mid_y
        keep.name = file_name
        remap_images(have)
        bpy.data.orphans_purge(do_recursive=True)
        path = os.path.join(OUT, file_name + '.blend')
        bpy.ops.file.make_paths_relative()
        bpy.ops.wm.save_as_mainfile(filepath=path, compress=True, relative_remap=True)
        print('wrote', path)


main()
