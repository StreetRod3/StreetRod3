# Pixel-art car textures (tools/pixelize.py)

`tools/pixelize.py` remakes a car model's texture as pixel art: big square texels at a fixed size on the car, and a few colors. It reads a `.glb` and writes a new one; it does not change the model it reads, and nothing in the game uses its output yet (see [Not done yet](#not-done-yet)).

It was made after two looks: the 1956 Corvette's (`assets/cars/sr1-c56.glb`, from Street Rod 1's art) and the PSX-style low-poly Charger in `reference/cars/lowpoly-charger/`, whose whole body is one 256×256 texture of 76 colors painted on flat side, top and front views.

## Running it

It needs Python 3 with numpy, scipy and Pillow.

```sh
tools/pixelize.py --car assets/cars/chevy-c10-1963.car -o /tmp/c10-pixel.glb
tools/pixelize.py --car assets/cars/studebaker-champion-1950.car -o /tmp/stude-pixel.glb --atlas-dir /tmp/stude-textures
tools/pixelize.py some-model.glb -o /tmp/out.glb --ppm 50 --colors 32
```

With `--car`, the model is the one the car file names, the texel size comes from its `dither_cell` (one texel per paint dither square), and the accent mark is kept if the file has `model.accent`. Without it, give the `.glb` yourself.

It prints which materials it left alone and why, and for each material it redid, how many faces went into how many pieces and how big the new texture is. The C10 takes about 7 seconds and the Studebaker about 30.

## What it does

1. Each opaque, textured surface is laid flat on whichever of the car's six sides it faces most: left, right, front, back, top or underneath. Each side reads as seen from outside the car.
2. Connected faces that face the same side become one piece of the new texture, as long as their flat shapes don't overlap, so a door or a fender is one grid of square texels. The grid is fixed to the car in meters, so texels are the same size everywhere and line up with the paint's dither squares.
3. The pieces are packed into one texture per material, with a 2-texel gap around each.
4. Each texel is the average of the old texture under it (sampled 4×4 per texel). A texel is paint or not paint by what most of the old texture under it was, so paint and trim don't blend into each other at the paint mask's edge.
5. Surfaces with no normal map get shading and panel lines drawn from the shape (see [Drawn shading and panel lines](#drawn-shading-and-panel-lines)).
6. Everything that isn't paint is cut to one palette for the whole car (48 colors). The paint's shades become evenly spaced steps from its darkest to its brightest (6 steps).
7. The metal/roughness, occlusion, emissive and normal maps are remade in the new layout, and the model is written with the new UVs, tangents and textures. Textures use nearest filtering.

## What it keeps

| Kept | How |
| --- | --- |
| The paint mask | A texel's alpha is 1 for paint and 0 for not paint, as `car_paint_mask.gdshader` reads it, so the car can still be repainted. |
| The accent mark | With an accent (the C10's grille, bumpers and lettering), a paint texel is grey for the body and has no blue for the accent. |
| Material names and settings | Each material keeps its name (`plate`, `wheel` and the like are what the game looks for), its metal, roughness and alpha settings, and its other textures. |
| Node and mesh names | Unchanged, so bumpers, wheels and dash parts are still found. |
| Shape in the normal map | A low-poly model's bevels, creases and panel lines are mostly in its normal map. Each texel's normal is turned into car space through the old layout's tangents and back through the new one's, and the new tangents are written into the model so the game reads the map exactly as it was written. |

Glass (see-through materials), the dash and its gauges, the license plate, and anything else whose node, mesh or material name contains a word in `--skip` are left exactly as they were. So are textures on a second UV set or with a texture transform.

## Drawn shading and panel lines

A model whose faces are flat colors with no normal map, like the Studebaker, has nothing in its texture for big texels to show. For those, the shape is drawn into the texture the way a PSX artist painted it:

- **Shading:** each texel is darker the more of the sky around it the car itself hides (ambient occlusion), so grooves, seams, wheel wells, the area behind the bumpers and the underside darken. It's found by marching rays through a 2 cm voxel copy of the car. Rays go out from both sides of the surface and the more open side counts, because some models' normals point inward.
- **Panel lines:** a one-texel line darkens open borders (door gaps, wheel arches), sharp creases, and edges where more than two faces meet. A face repeated with its winding reversed, which is how some models (the Studebaker) are double-sided, counts once.

Both go into the paint's shade, so the car can still be repainted. The darkening is applied to the colors as they look (sRGB), and never goes below `--darkest`, so the deepest shadow is a dark midtone, not black.

With `--detail auto` (the default) this is done for materials with no normal map and skipped for those with one, since their shape is already in it. On the C10 that means only the steering wheel gets it.

## Options

| Option | Default | What it does |
| --- | --- | --- |
| `model` | the `--car` file's model | The `.glb` to read. |
| `-o`, `--output` | required | Where to write the new `.glb`. |
| `--car` | none | A `.car` file, for its model path, `dither_cell` and `accent`. |
| `--ppm` | `1/dither_cell`, or `25` | Texels per meter. `25` is 4 cm texels, close to the Charger; `50` keeps fine trim like the C10's tailgate lettering and grille bars readable. |
| `--colors` | `48` | Palette size for everything that isn't paint. |
| `--shades` | `6` | How many shade steps the paint keeps. |
| `--supersample` | `4` | Samples per texel side when averaging the old texture. Lower is faster and rougher. |
| `--skip` | `dash,needle,gauge,speedo,tach,glass,window,plate` | Words; any node, mesh or material whose name contains one is left alone. |
| `--accent`, `--no-accent` | on if the car file has `model.accent` | Keep the accent mark in paint texels. |
| `--atlas-dir` | none | Also save each new texture as a PNG in this folder, to look at or touch up. |
| `--detail` | `auto` | Draw shading and panel lines from the shape: `auto` for materials with no normal map, `on` for all, `off` for none. |
| `--ao-strength` | `0.75` | How dark a fully hidden texel gets, 0 to 1, before `--darkest`. |
| `--ao-rays` | `24` | Rays per side of the surface for the shading. More is smoother and slower. |
| `--line-strength` | `0.45` | How much a panel line darkens, 0 to 1, before `--darkest`. |
| `--darkest` | `0.45` | The darkest the drawn shading goes, as a share of the color. Raise it toward `0.6` for lighter shadows. |
| `--crease` | `35` | The angle in degrees between two faces that counts as a crease and gets a line. |
| `--voxel` | `0.02` | Voxel size in meters for the shading. Smaller catches thinner gaps and takes more memory. |

## Looking at the result

Godot loading a `.glb` at runtime (`GLTFDocument`) gives placeholder tangents to a model that has none, while the editor's import (`meshes/ensure_tangents`) builds real ones. A runtime render of an original model with a normal map is therefore lit wrong; call `SurfaceTool.generate_tangents()` on its surfaces first. The pixelized models carry their own tangents and are fine either way.

The paint shader smooths its textures (`filter_linear_mipmap`), so to see the pixel look the shader's `albedo_tex`, `orm_tex` and `normal_tex` need `filter_nearest_mipmap`.

## Not done yet

- The game doesn't use the output. A pixelized car needs a paint shader with nearest filtering, switched on per car (for example from the `.car` file), before it looks right in the game.
- A mesh drawn by more than one node is laid out for the first node's position only.
- Morph targets are copied but not checked, and sparse accessors and models with external buffers aren't read.
