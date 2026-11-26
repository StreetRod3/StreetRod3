# 1949 Cadillac Series 62 convertible (Free Vehicle Archive)

## Source

"1949 - Cadillac Series 62" by Free Vehicle Archive, https://sketchfab.com/3d-models/1949-cadillac-series-62-9a480a4c86ab435188897915759e8aab (published 2025-10-18).

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared, with this line:

This work is based on "1949 - Cadillac Series 62" (https://sketchfab.com/3d-models/1949-cadillac-series-62-9a480a4c86ab435188897915759e8aab) by Free Vehicle Archive (https://sketchfab.com/free-vehicle-archive) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

## Provenance check (2026-11-24)

| Check | Finding |
| --- | --- |
| Uploader | Free Vehicle Archive (https://sketchfab.com/free-vehicle-archive), on Sketchfab since 2024-10-07, 36 models, all classic cars put up free under CC BY; the profile links the artist's Patreon (MahanRasouli) |
| Files | A Blender file; one object per part, numbered after the model's name, some with French names; image paths in the artist's own Blender folder (`//Temp/1949 - Cadillac Series 62/texture/`) |
| Naming | No game naming (no LOD levels, no game folder paths, no game material names) |

## Files

| File | What it is |
| --- | --- |
| `source/1949 - Cadillac Series 62.blend` | The Sketchfab download |
| `source/1949 - Cadillac Series 62 - Stripped.blend` | The user's copy with the wheels, suspension, engine, exhaust and the rest of the running gear taken out, the X-frame kept; the converter builds the body from this one and measures the wheels in the full file |
| `textures/` | The images out of the Blender file |
| `source.md` | The Sketchfab link |

## Converting it

`tools/fva_to_glb.py cadillac-1949 assets/cars/cadillac-series-62-1949.glb`; the car's entry in the converter's `CARS` table says what is left out, which parts are the bumpers, the rear valance, the plates and the gauges (`tools/fva_dash.py`).

## Changes from the download

| Change | Why |
| --- | --- |
| Wheels, suspension, engine and exhaust left out (the stripped copy), and the tailpipe's tip left hanging under the rear bumper | The game mounts its own wheels and draws its own suspension; the hood screen draws its own engine |
| Bumpers, with their guards, brackets, black inner faces, the plate's housing, its lamp lens and the gravel pan, as `bumper_front` and `bumper_rear` | So the game can strip them |
| The fins' ends closed below the taillights | The bumper's wrapped ends covered them, which the model leaves open: each end follows the fender ahead of it, cut off where it ends, down and round under to a short spine, scaled to the fin's outline and shaded as the fender is, so the two meet without a seam (user, 2026-11-25). The trunk's rear panel and the fenders' end panels beside it are as the model has them |
| A blank plate on the black face of the rear bumper's plate housing and one on the front bumper | The model has no plates; the game hangs its own |
| The speedometer and gas gauge needles turned into working needles | Working gauges, as on the other cars; the temperature, battery and oil needles stay put |

## Dimensions

| | Length | Width | Height | Wheelbase | Source |
| --- | --- | --- | --- | --- | --- |
| 1949 Series 62 | 215.1 in | 80.1 in | 62.0 in | 126 in | Length and wheelbase: Over Drive's 1949 Cadillac fact sheet, https://over-drive-magazine.com/2025/04/15/1949-cadillac-fact-sheet/; height: a convertible for sale, https://classiccars.com/listings/view/1474339/1949-cadillac-series-62-for-sale-in-stratford-wisconsin-54484; width: a 1949 Series 62 coupe (80.13 in), https://www.conceptcarz.com/s10146/news.aspx, as no convertible's was found |
| The model, after conversion | 215.1 in | 80.1 in over the paint | 62.0 in to the top of the top | 126.6 in between the tires | `tools/fva_to_glb.py` |

The model's tires are 28.3 in across; the game draws its wheels 1.104 times their size to fill the wells. The real car's were 8.00-15.
