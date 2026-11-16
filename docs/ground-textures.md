# Ground textures and sky

The ground, roads and day sky are photographed textures. Their materials are built in code, in `scripts/ground_material.gd` and `scripts/skies.gd`, and Mulholland's ground uses `shaders/vertex_ground.gdshader`. Sources and licenses are in `reference/tracks/`, `reference/skies/` and [CREDITS.md](../CREDITS.md).

## Where each one goes

| Texture | Used on | Material |
| --- | --- | --- |
| Grass (Poliigon GrassPatchyGround 4585) | Ground around the race tracks and the city, Mulholland's flat ground and the foot of its banks | `GroundMaterial.grass()`, and the grass part of `vertex_ground()` |
| Asphalt (Poliigon CityStreetAsphaltGenericClean001) | Race track roads and city streets; Mulholland's road darkened | `asphalt()`, `dark_asphalt()` |
| Concrete (Magnific photo, made to tile by `tools/make_concrete_texture.py`) | The Aqueduct's floor and banks, the street drag's shoulders | `vertex_colored_concrete()`, `shoulder_concrete()` |
| Dirt (Poliigon GroundDirtWeedsPatchy004) | Mulholland's hillsides, and the upper part of its banks | The dirt part of `vertex_ground()` |
| Gravel (Poly Haven Rocky Trail) | Mulholland's verge and its gravel stretches | `gravel()`, and the gravel part of `vertex_ground()` |
| Day sky (Poly Haven Kloofendal 48d Partly Cloudy, Pure Sky) | The city, and every race but Street Rod 2's cruise races unless its track picks another sky | `Skies.use_day()`, `Skies.use()` |

Mulholland's guard rails and far peaks keep their flat colors.

## Settings to tune

All of these are constants in `scripts/ground_material.gd`.

| Constant | Now | What it does |
| --- | --- | --- |
| `DIRT_TINT_AMOUNT` | `0.35` | How much of the old Street Rod 2 hill brown's hue the dirt takes. `0` is the photo's own color; `1` is that brown's hue at the photo's brightness. Higher is redder. |
| `DIRT_DARKEN` | `0.8` | Multiplies the dirt's color after the tint. `1` is as bright as the photo; lower is darker. |
| `DIRT_OLD_COLOR` | `Color(0.56, 0.3, 0.07)` | The brown the tint leans toward: the flat color Mulholland's hills had before. Only its hue is used, not its brightness. |
| `GROUND_SPECULAR` | `0.1` | How much the grass, dirt and gravel reflect. Godot also scales the reflection at shallow angles with it, so raising it toward the default `0.5` makes the ground shine and turns ground in the distance pale with the sky in it. |
| `GRASS_TILE_M`, `ASPHALT_TILE_M`, `CONCRETE_TILE_M`, `DIRT_TILE_M`, `GRAVEL_TILE_M` | `2`, `1`, `2`, `2`, `2` | Meters of ground one tile of each texture covers. |
| `GRAVEL_TINT` | white | Multiplies the gravel's color. Lower is darker; a color tints it. |
| `DARK_ASPHALT_TINT` | `0.3` grey | How dark Mulholland's road is, to keep Street Rod 2's black road. |
| `SHOULDER_TINT` | `0.6` grey | Shade of the street drag's concrete shoulders. |

`DIRT_MEAN` is the dirt photo's average color in linear light, measured from the file. The tint is worked out from it, so measure it again if the dirt texture changes. The dirt is also never smoother than `dirt_min_roughness` (`0.92`) in `shaders/vertex_ground.gdshader`; the photo's own roughness looked damp.

Mulholland's gravel verge has a ragged outside edge, drawn by the same shader; the mesh's edge is straight, and the walls and off-the-road checks still use the straight line. `edge_wobble_m` (`0.3`) is how far the edge wanders in from the full verge width, and `edge_wave_m` (`2.5`) how long its bumps are. The edge only wanders inward: going out past the verge, gravel ran up the face of hills that rise straight from it.

The gravel doesn't fade into the ground beyond it, which looked like a see-through smear. Across a zone `edge_fade_m` (`0.18`) either side of the line, it is broken up by the gravel's height map: the stones last furthest out and the ground between them gives way first, so the verge ends in loose stones on the grass or dirt. `edge_height_pull` (`0.9`) is how far a stone's height carries it out, and `edge_sharpness` (`0.06`) how crisp each stone's outline is.

## Skies

A track picks its sky with its `sky` field, set under Sky in the track maker. The skies are listed in `SKIES` in `scripts/skies.gd`:

| Id | Sky | File | Source |
| --- | --- | --- | --- |
| `day` | Day, partly cloudy | `assets/skies/kloofendal_48d_partly_cloudy_puresky_4k.hdr` | Poly Haven, https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky (CC0) |
| `dusk` | Dusk | `assets/skies/dusk.exr`, not added yet | environment-textures.com, https://www.environment-textures.com/photos/show/id/12k-dusk-skydome-hdri-panorama (paid, one credit; a 12K HDR in the set) |
| `evening-orange` | Cloudy evening, orange | `assets/skies/evening-orange.exr`, from `reference/tracks/cloudyeveninghdri/` | Poliigon HdrSkyEvening006, https://www.poliigon.com/hdri/cloudy-horizon-evening-outdoor-sky-hdri-orange/3522 |
| `sunset-pink` | Hazy sunset, pink and orange | `assets/skies/sunset-pink.exr`, from `reference/tracks/sunsethdri/` | Poliigon HdrSkySunset007, https://www.poliigon.com/hdri/hazy-horizon-sunset-outdoor-sky-hdri-pink-orange/3537 |

The sky is turned so the sun in the photo stands where the scene's light comes from. That needs the sun's place, `sun_u` and `sun_up`. A sky without them (`-1`) is drawn unturned, so its sun can be on the wrong side of the shadows.

In races a sky can also set the light, for a sky that isn't midday. The day sky sets none of these and leaves each scene's own light. The city always has the day sky.

| Key | What it does | `sunset-pink` | `evening-orange` |
| --- | --- | --- | --- |
| `light_height` | The sun light's height in degrees; its heading stays. A little above a sunset sun keeps shadows from running off for hundreds of meters. | `8` | `6` |
| `light_color`, `light_energy` | The sun light's color and strength. | warm orange, `1.1` | orange, `0.8` |
| `ambient_color`, `ambient_energy` | The light everywhere, which lights what the sun doesn't. | dusky lilac, `0.75` | dusky blue, `0.7` |
| `tonemap`, `exposure` | `"filmic"` or `"aces"`. Races otherwise draw without tone mapping, and a low sun's glow then burns out to a white blob. ACES crushed the dark side of the sky to black. | filmic, `1.6` | filmic, `1.6` |
| `sky_energy` | How bright the photo itself is drawn, to tame a glow without darkening the scene. Lower hides the dark side of the sky. | `0.55` | `0.8` |

To add a sky, or the file for one listed above:

1. Download the HDR or EXR, and keep the download and its license under `reference/` (`reference/skies/<id>/`, say) with a `notes.md`. A very large original (the 12K dusk sky, say) can stay out of Git; the notes then say where it came from.
2. Make the game's copy and measure the sun: `godot --headless --path . --script tools/prepare_hdri.gd -- reference/skies/<id>/<file>.hdr assets/skies/<id>.exr`. It scales the panorama down to 4096 across and prints `sun_u` and `sun_up`.
3. Put those two numbers in the sky's entry in `SKIES`. A new sky also needs an entry there, with its name for the track maker and its file. A sky that isn't midday needs the lighting keys above, worked out by looking at a race under it.
4. Import (`godot --headless --import`), then set the new `.import` file to `compress/mode=2` and `detect_3d/compress_to=0`, leave mipmaps off, and import again.
5. Add it to CREDITS.md.

## Adding a texture

These textures are only used by materials built in code, so Godot's editor never marks them as 3D textures. After `godot --headless --import`, set their `.import` files by hand and import again: `compress/mode=2`, `mipmaps/generate=true` and `detect_3d/compress_to=0`, plus `compress/normal_map=1` for normal maps. Without that they load uncompressed with no mipmaps, and the ground shimmers in the distance. Skies take `compress/mode=2` without mipmaps. The image files go in Git LFS (see `.gitattributes`).

Older Poliigon downloads have a gloss map instead of roughness. Godot needs roughness, so invert the gloss map. Check a normal map is OpenGL style (green up) before using it.
