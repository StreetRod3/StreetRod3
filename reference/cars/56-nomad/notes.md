# 1956 Chevrolet Bel Air Nomad (Free Vehicle Archive)

## Source

"1956 - Chevrolet Bel Air Nomad" by Free Vehicle Archive, https://sketchfab.com/3d-models/1956-chevrolet-bel-air-nomad-efd82e3b0a5e415a921853c88e2a18ab (published 2025-12-19).

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared, with this line:

This work is based on "1956 - Chevrolet Bel Air Nomad" (https://sketchfab.com/3d-models/1956-chevrolet-bel-air-nomad-efd82e3b0a5e415a921853c88e2a18ab) by Free Vehicle Archive (https://sketchfab.com/free-vehicle-archive) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

## Provenance check (2026-11-24)

| Check | Finding |
| --- | --- |
| Uploader | Free Vehicle Archive (https://sketchfab.com/free-vehicle-archive), on Sketchfab since 2024-10-07, 36 models, all classic cars put up free under CC BY; the profile links the artist's Patreon (MahanRasouli) |
| Files | A GLB written by Blender ("Khronos glTF Blender I/O v4.5.47"); one object per part, numbered after the model's name; flat-colored materials with plain names (`Body Paint`, `Chrome`, `Glossy Red`) and small images for the lamps, badges, gauges and interior |
| Naming | No game naming (no LOD levels, no game folder paths, no game material names) |

## Files

| File | What it is |
| --- | --- |
| `source/1956 - Chevrolet Bel Air Nomad.zip` | The Sketchfab download: the GLB |
| `textures/` | The images out of the GLB |
| `nomad.md` | The Sketchfab link |

## Converting it

`tools/fva_to_glb.py nomad-1956 assets/cars/chevy-nomad-1956.glb`; the car's entry in the converter's `CARS` table says what is left out, which parts are the bumpers, the rear valance, the plates and the gauges (`tools/fva_dash.py`).

## Changes from the download

| Change | Why |
| --- | --- |
| Wheels, tires, brake drums, spindles and the rest of the suspension left out | The game mounts its own wheels and draws its own suspension |
| The engine left out | The hood screen draws its own engine |
| The floor, frame and exhaust object cut down to the floor pan, the frame rails, the crossmember under the floor and the gas tank | They are one object in the model, with the suspension and axle |
| The plain black rear plate left out | The game hangs its own blank plate there (and one on the front bumper, which the model leaves bare) |
| Bumpers, with their brackets, as `bumper_front` and `bumper_rear` | So the game can strip them |
| A rear valance under the tailgate and the fins, in the second paint like the rest of the back of the car | The bumper covered the bottom of the body there, which the model leaves open: the valance carries on from the tailgate's and fins' bottom edges along their slope, turns straight down to the bumper's bottom and tucks in under the car (user, 2026-11-25) |
| The body's two paints as the paint and the accent | The garage paints them apart; the accent is the tailgate, rear quarters and spear insert, as on the two-tone cars |
| The speedometer's needle turned into a working needle; a sliding pointer of its own in the gas gauge's window, the printed one painted out | Working gauges, as on the other cars |

## Dimensions

| | Length | Width | Height | Wheelbase | Source |
| --- | --- | --- | --- | --- | --- |
| 1956 Bel Air Nomad | 197.5 in (5016 mm) | 74.0 in (1880 mm) | 60.8 in (1544 mm) | 115 in | Carsales, https://www.carsales.com.au/research/chevrolet/nomad/1956/bel-air/ |
| The model, after conversion | 197.5 in | 74.0 in over the paint | 60.8 in to the top of the paint | 113.9 in between the tires | `tools/fva_to_glb.py` |

The model's tires are 25.2 in across; the game draws its wheels 0.983 times their size to fill the wells. The real car's were 6.70-15.

## Review

The user's marked-up renders from the conversion are in `review/` (review.md).
