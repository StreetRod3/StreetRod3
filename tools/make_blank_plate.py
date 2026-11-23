#!/usr/bin/env python3
"""Write the blank license plate every converted car wears: assets/cars/plate-blank.png.

    python3 -I tools/make_blank_plate.py reference/cars/impala-1967/chevrolet-impala-1967.zip

It is the Impala download's plate, rim and all, with its registration painted out
(tools/impala_to_glb.py, paint_out_plate), turned to lie long side across, 512 x 256 px
(the C10's plate, tools/c10_to_glb.py). It is kept as a file of its own so the car
converters share it and the game can later put a plate of the player's own in its place:
the converters put it on a material named `plate`.
"""
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'cars', 'plate-blank.png')


def blank_plate(impala_zip):
    """The blank plate as a PIL RGB image."""
    import io
    import zipfile

    import numpy as np
    from PIL import Image
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from c10_to_glb import IMPALA_PLATE_RECT, IMPALA_PLATE_TEXTURE, PLATE_TEX
    from impala_to_glb import paint_out_plate
    with zipfile.ZipFile(impala_zip) as z:
        rgb = np.asarray(Image.open(io.BytesIO(z.read(IMPALA_PLATE_TEXTURE))).convert('RGB')).copy()
    paint_out_plate(rgb)
    return Image.fromarray(rgb).crop(IMPALA_PLATE_RECT).rotate(90, expand=True).resize(PLATE_TEX, Image.LANCZOS)


if __name__ == '__main__':
    blank_plate(sys.argv[1]).save(OUT, optimize=True)
    print('wrote', os.path.normpath(OUT))
