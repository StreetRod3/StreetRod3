# Ground textures and sky

The ground, roads and day sky are photographed textures. Their materials are built in code, in `scripts/ground_material.gd` and `scripts/skies.gd`, and Mulholland's ground uses `shaders/vertex_ground.gdshader`. Sources and licenses are in `reference/tracks/`, `reference/skies/` and [CREDITS.md](../CREDITS.md).

## Where each one goes

| Texture | Used on | Material |
| --- | --- | --- |
| Grass (Poliigon GrassPatchyGround 4585) | Ground around the race tracks and the city, Mulholland's flat ground and the foot of its banks | `GroundMaterial.grass()`, and the grass part of `vertex_ground()` |
| Asphalt (Poliigon CityStreetAsphaltGenericClean001) | Race track roads and city streets; Mulholland's road darkened | `asphalt()`, `dark_asphalt()` |
| Concrete (Magnific photo, made to tile by `tools/make_concrete_texture.py`) | The Aqueduct's floor and banks, the street drag's shoulders | `vertex_colored_concrete()`, `shoulder_concrete()` |
| Dirt (Poliigon GroundDirtWeedsPatchy004) | Mulholland's hillsides, and the upper part of its banks | The dirt part of `vertex_ground()` |
| Day sky (Poly Haven Kloofendal 48d Partly Cloudy, Pure Sky) | Every race but Street Rod 2's cruise races, and the city | `Skies.use_day()` |

Mulholland's verge and gravel stretches, the guard rails and the far peaks keep their flat colors.

## Settings to tune

All of these are constants in `scripts/ground_material.gd`.

| Constant | Now | What it does |
| --- | --- | --- |
| `DIRT_TINT_AMOUNT` | `0.35` | How much of the old Street Rod 2 hill brown's hue the dirt takes. `0` is the photo's own color; `1` is that brown's hue at the photo's brightness. Higher is redder. |
| `DIRT_DARKEN` | `0.8` | Multiplies the dirt's color after the tint. `1` is as bright as the photo; lower is darker. |
| `DIRT_OLD_COLOR` | `Color(0.56, 0.3, 0.07)` | The brown the tint leans toward: the flat color Mulholland's hills had before. Only its hue is used, not its brightness. |
| `GROUND_SPECULAR` | `0.1` | How much the grass and dirt reflect. Godot also scales the reflection at shallow angles with it, so raising it toward the default `0.5` makes the ground shine and turns ground in the distance pale with the sky in it. |
| `GRASS_TILE_M`, `ASPHALT_TILE_M`, `CONCRETE_TILE_M`, `DIRT_TILE_M` | `2`, `1`, `2`, `2` | Meters of ground one tile of each texture covers. |
| `DARK_ASPHALT_TINT` | `0.3` grey | How dark Mulholland's road is, to keep Street Rod 2's black road. |
| `SHOULDER_TINT` | `0.6` grey | Shade of the street drag's concrete shoulders. |

`DIRT_MEAN` is the dirt photo's average color in linear light, measured from the file. The tint is worked out from it, so measure it again if the dirt texture changes. The dirt is also never smoother than `dirt_min_roughness` (`0.92`) in `shaders/vertex_ground.gdshader`; the photo's own roughness looked damp.

## Adding a texture

These textures are only used by materials built in code, so Godot's editor never marks them as 3D textures. After `godot --headless --import`, set their `.import` files by hand and import again: `compress/mode=2`, `mipmaps/generate=true` and `detect_3d/compress_to=0`, plus `compress/normal_map=1` for normal maps. Without that they load uncompressed with no mipmaps, and the ground shimmers in the distance. Skies take `compress/mode=2` without mipmaps. The image files go in Git LFS (see `.gitattributes`).

Older Poliigon downloads have a gloss map instead of roughness. Godot needs roughness, so invert the gloss map. Check a normal map is OpenGL style (green up) before using it.
