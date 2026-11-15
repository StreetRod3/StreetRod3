# Makes the Aqueduct's tiling concrete from a flat photo:
#   python3 make_concrete_texture.py IN.jpg OUT.jpg
# The photo (reference/tracks/old-grunge-concrete.jpg) is lit unevenly and does not tile. This
# takes the middle square, divides out the shading at large scale so the corners are as bright as
# the middle, blends it with a copy shifted half a tile so the edges meet, and scales it to 2048.
# The mean is set bright, so the vertex colors in track_sides.gd can set the shade; the script
# prints the mean in linear light for them.
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

SIZE = 2048
# Mean brightness of the result, 0-255 sRGB.
TARGET_MEAN = 210.0
# Shading broader than this many pixels of the source is divided out.
SHADING_SIGMA = 250.0

src = np.asarray(Image.open(sys.argv[1]).convert("RGB"), dtype="float32")
h, w, _ = src.shape
n = min(h, w)
top, left = (h - n) // 2, (w - n) // 2
img = src[top:top + n, left:left + n]

lum = img.mean(axis=2)
shade = gaussian_filter(lum, SHADING_SIGMA, mode="reflect")
img = img / shade[..., None] * lum.mean()

# Blend with the half-shifted copy: the original in the middle, the shifted copy at the edges,
# whose edges are neighbors in the original. Dividing by the window's length keeps the contrast.
mean = img.mean(axis=(0, 1))
shifted = np.roll(img, (n // 2, n // 2), axis=(0, 1))
ramp = np.sin(np.pi * (np.arange(n, dtype="float32") + 0.5) / n)
wgt = (ramp[:, None] * ramp[None, :])[..., None]
mixed = (img - mean) * wgt + (shifted - mean) * (1.0 - wgt)
img = mean + mixed / np.sqrt(wgt * wgt + (1.0 - wgt) ** 2)

img = img * (TARGET_MEAN / img.mean())
out = Image.fromarray(np.clip(img, 0, 255).astype("uint8")).resize((SIZE, SIZE), Image.LANCZOS)
out.save(sys.argv[2], quality=92)

s = np.asarray(out, dtype="float32") / 255.0
linear = np.where(s <= 0.04045, s / 12.92, ((s + 0.055) / 1.055) ** 2.4)
print("linear mean %.3f" % linear.mean())
