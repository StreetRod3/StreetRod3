# Bakes the wear map for the license: python3 make_card_wear.py OUT.jpg
# Red is staining and browned edges, green is where ink and paper have rubbed away,
# blue is the grain of the paper, with 0.5 as no change.
import sys, numpy as np
from PIL import Image
W, H = 1024, 684
rng = np.random.default_rng(1977)

def blotches(cells):
    small = rng.random((max(2, round(cells * H / W)), cells)).astype("float32")
    im = Image.fromarray(small).resize((W, H), Image.BICUBIC)
    return np.asarray(im)

def clouds(first, octaves=4):
    out, amp, total = np.zeros((H, W), "float32"), 1.0, 0.0
    for o in range(octaves):
        out += blotches(first * 2 ** o) * amp
        total += amp
        amp *= 0.5
    return out / total

def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)

y, x = np.mgrid[0:H, 0:W].astype("float32")
edge = np.minimum.reduce([x, W - 1 - x, y, H - 1 - y])
# An uneven distance from the edge, so the browning has no straight border.
wobble = (clouds(10) - 0.5) * 70

stain = 0.22 * smooth(clouds(4), 0.42, 0.72)
stain += 0.5 * (1 - smooth(edge + wobble * 0.6, 0, 42))
# Two soft spots, as from a thumb and whatever else was in the wallet.
for cx, cy, r, amount in ((0.8, 0.82, 0.2, 0.12), (0.3, 0.2, 0.26, 0.08)):
    d = np.hypot((x - cx * W) / (r * W), (y - cy * H) / (r * W))
    stain += amount * (1 - smooth(d + (clouds(8) - 0.5) * 0.7, 0.3, 1.0))

rub = 0.5 * (1 - smooth(edge + wobble * 0.2, 0, 9))
rub += 0.1 * smooth(clouds(90, 2), 0.68, 0.8) * smooth(clouds(5), 0.55, 0.75)  # scuffed patches
rub += 0.35 * (rng.random((H, W)) > 0.9997).astype("float32")  # flecks

# Wallet folds: a pale worn line with a shadow just beside it, wandering a little.
def fold(position, along, across, strength):
    drift = np.interp(along, np.linspace(0, along.max(), 40), np.cumsum(rng.normal(0, 0.55, 40)))
    d = across - position - drift
    fade = 0.55 + 0.45 * clouds(30, 2)
    return strength * np.exp(-(d / 1.3) ** 2) * fade, strength * np.exp(-((d - 2.6) / 2.6) ** 2) * fade

for pos, along, across, strength in ((W * 0.5, y, x, 0.5), (H * 0.47, x, y, 0.26)):
    worn, shade = fold(pos, along, across, strength)
    rub += worn
    stain += shade * 0.6

fibers = rng.normal(0, 1, (H, W)).astype("float32")
fibers = np.asarray(Image.fromarray(fibers).resize((W // 2, H // 2), Image.BILINEAR).resize((W, H), Image.BICUBIC))
grain = 0.5 + 0.1 * fibers + 0.08 * (clouds(180, 2) - 0.5)

rgb = np.dstack([np.clip(stain, 0, 1), np.clip(rub, 0, 1), np.clip(grain, 0, 1)])
Image.fromarray((rgb * 255).astype("uint8")).save(sys.argv[1], quality=88)
