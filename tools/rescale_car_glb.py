#!/usr/bin/env python3
"""Scale a car body GLB by different amounts in length, width and height.

    python3 tools/rescale_car_glb.py IN.glb OUT.glb SX SY SZ

SX, SY and SZ multiply the model's width (X), height (Y) and length (Z) about its
origin, which in the car GLBs is the middle of the car at the bottom of the body, so the
body stays on the ground and centered. This is for the cars converted from Street Rod 1
(sr1-c56.glb, sr1-fairlane-1957.glb, sr1-ford-customized-coupe-1932.glb), whose bodies
came out too long and too wide for their real wheelbase and width, and not by the same
amount in each direction.

The body, interior and glass meshes (every top-level node with a mesh) are stretched.
The steering wheel and the dash pods (top-level nodes named driving_wheel* or dash_*,
and everything under them) only move to their stretched positions; their own shapes are
left alone, so the wheel's rim and the dials stay round and the needles still turn in
their plane.

The vertex data is rewritten in place (positions, and normals turned to match), so
everything else in the file (materials, textures, node names) is kept byte for byte.
The model's units are unchanged: to keep the car's parts the same size in the game, the
car file's model height is multiplied by SY as well, since the game scales the model to
that height.
"""
import json
import struct
import sys

import numpy as np

RIGID = ('driving_wheel', 'dash_')


def main():
    src, dst = sys.argv[1], sys.argv[2]
    s = np.array([float(v) for v in sys.argv[3:6]], np.float64)
    data = bytearray(open(src, 'rb').read())
    jlen, = struct.unpack('<I', data[12:16])
    gltf = json.loads(data[20:20 + jlen])
    bin_start = 20 + jlen + 8

    def accessor_view(index):
        a = gltf['accessors'][index]
        assert a['componentType'] == 5126 and a['type'] == 'VEC3' and 'sparse' not in a, a
        view = gltf['bufferViews'][a['bufferView']]
        start = bin_start + view.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = view.get('byteStride', 12)
        return a, start, stride

    def read(index):
        a, start, stride = accessor_view(index)
        rows = [struct.unpack_from('<3f', data, start + i * stride) for i in range(a['count'])]
        return np.array(rows, np.float64)

    def write(index, values):
        a, start, stride = accessor_view(index)
        for i, row in enumerate(values.astype(np.float32)):
            struct.pack_into('<3f', data, start + i * stride, *row)

    scene = gltf['scenes'][gltf.get('scene', 0)]
    done = set()
    for n in scene['nodes']:
        node = gltf['nodes'][n]
        name = node.get('name', '')
        assert 'matrix' not in node, name
        if name.startswith(RIGID):
            if 'translation' in node:
                node['translation'] = (np.array(node['translation']) * s).tolist()
            continue
        assert not node.get('children'), name
        assert not any(k in node for k in ('translation', 'rotation', 'scale')), name
        if 'mesh' not in node:
            continue
        for prim in gltf['meshes'][node['mesh']]['primitives']:
            attrs = prim['attributes']
            assert 'TANGENT' not in attrs, name
            pos_index = attrs['POSITION']
            assert pos_index not in done, 'shared vertex data ' + name
            done.add(pos_index)
            pos = read(pos_index) * s
            write(pos_index, pos)
            a = gltf['accessors'][pos_index]
            a['min'] = pos.min(0).astype(np.float32).tolist()
            a['max'] = pos.max(0).astype(np.float32).tolist()
            if 'NORMAL' in attrs:
                nrm = read(attrs['NORMAL']) / s
                length = np.linalg.norm(nrm, axis=1, keepdims=True)
                write(attrs['NORMAL'], nrm / np.where(length > 0, length, 1))

    js = json.dumps(gltf, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    binary = bytes(data[bin_start - 8:])
    total = 12 + 8 + len(js) + len(binary)
    out = struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(js), 0x4E4F534A) + js + binary
    open(dst, 'wb').write(out)
    print(f'{dst}: scaled {s.tolist()}, {len(done)} vertex sets')


if __name__ == '__main__':
    main()
