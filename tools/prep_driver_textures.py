# Shrinks MakeHuman textures for the web build. Hair goes neutral so the game can tint it.
import sys, numpy as np
from pathlib import Path
from PIL import Image
assets, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
def jpg(src, name, size=1024):
    Image.open(assets / src).convert("RGB").resize((size, size), Image.LANCZOS).save(out / name, quality=90)
def neutral(src, name, size=1024):
    im = Image.open(assets / src).convert("RGBA").resize((size, size), Image.LANCZOS)
    a = np.asarray(im).astype(float) / 255
    lum = (a[..., :3] * [0.2126, 0.7152, 0.0722]).sum(-1)
    mask = a[..., 3] > 0.5
    top = np.percentile(lum[mask], 92) if mask.any() else 1
    lum = 0.4 + 0.6 * np.clip(lum / max(top, 0.02), 0, 1)  # dark roots would stay black under any tint
    rgb = np.dstack([lum] * 3)
    Image.fromarray((np.dstack([rgb, a[..., 3]]) * 255).astype("uint8")).save(out / name, optimize=True)
def skin(sex, word):
    # The skins share one UV layout, so a tone between two of them is a plain blend.
    def diffuse(race):
        folder = assets / f"skins/young_{race}_{word}"
        tex = next(l.split()[1] for l in open(folder / f"young_{race}_{word}.mhmat") if l.startswith("diffuseTexture"))
        return Image.open(folder / tex).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    light, olive, dark = diffuse("caucasian"), diffuse("asian"), diffuse("african")
    tones = {"LGT": light, "OLV": Image.blend(olive, dark, 0.2), "BRN": Image.blend(olive, dark, 0.6), "DRK": dark}
    for code, im in tones.items():
        im.save(out / f"skin_{sex}_{code}.jpg", quality=90)
skin("m", "male")
skin("f", "female")
jpg("clothes/male_casualsuit01/male_casualsuit01_diffuse.png", "shirt_m.jpg")
jpg("clothes/female_elegantsuit01/female_elegantsuit01_diffuse.png", "shirt_f.jpg")
for code, f in {"BRN": "brown", "BLU": "blue", "GRN": "green", "HZL": "brownlight", "GRY": "grey"}.items():
    jpg(f"eyes/materials/{f}_eye.png", f"eye_{code}.jpg", 512)
for h in ["short01", "short02", "short03", "short04", "bob01", "bob02", "long01", "ponytail01", "braid01", "afro01"]:
    tex = next(l.split()[1] for l in open(assets / f"hair/{h}/{h}.mhmat") if l.startswith("diffuseTexture"))
    neutral(f"hair/{h}/{tex}", f"hair_{h}.png")
neutral("eyebrows/eyebrow001/eyebrow001.png", "brows.png", 256)
Image.open(assets / "eyelashes/eyelashes01/eyelashes01.png").convert("RGBA").resize((256, 256), Image.LANCZOS).save(out / "lashes.png", optimize=True)
