import io
from PIL import Image
from pygltflib import GLTF2

# Load your GLB
gltf = GLTF2().load("/home/hellmark/Code/StreetRod3/assets/cars/chevy-c10-1963.glb")

# 1. Force Nearest-Neighbor filtering on all samplers
for sampler in gltf.samplers:
    sampler.magFilter = 9728  # NEAREST
    sampler.minFilter = 9728  # NEAREST (use 9984 for NEAREST_MIPMAP_NEAREST)

# 2. Downscale and color-quantize embedded PNGs
MAX_SIZE = 128  # 128x128 or 256x256 is the sweet spot for PS1/Saturn
COLORS = 64     # Low color count mimics 15-bit/16-bit VRAM limits

binary_blob = bytearray(gltf.binary_blob())
new_binary_blob = bytearray()

# Rebuild buffer views to keep byte offsets aligned
for i, bv in enumerate(gltf.bufferViews):
    data = binary_blob[bv.byteOffset : bv.byteOffset + bv.byteLength]
    
    # Check if this bufferView belongs to an image (views 76-87 in your file)
    is_image = any(img.bufferView == i for img in gltf.images)
    
    if is_image:
        img = Image.open(io.BytesIO(data)).convert("RGBA")
        # Resize using Nearest Neighbor so it stays crunchy
        img.thumbnail((MAX_SIZE, MAX_SIZE), Image.Resampling.NEAREST)
        
        # Quantize colors with Floyd-Steinberg dithering (classic PS1 look)
        # Keep alpha channel intact
        r, g, b, a = img.split()
        rgb = Image.merge("RGB", (r, g, b)).quantize(colors=COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG).convert("RGB")
        img = Image.merge("RGBA", (*rgb.split(), a))
        
        out = io.BytesIO()
        img.save(out, format="PNG", optimize=True)
        data = out.getvalue()

    # Align to 4-byte boundary as required by glTF spec
    while len(new_binary_blob) % 4 != 0:
        new_binary_blob.append(0)
        
    bv.byteOffset = len(new_binary_blob)
    bv.byteLength = len(data)
    new_binary_blob.extend(data)

gltf.buffers[0].byteLength = len(new_binary_blob)
gltf.set_binary_blob(bytes(new_binary_blob))
gltf.save("chevy-c10-1963-ps1.glb")
