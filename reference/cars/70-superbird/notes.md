# 1970 Plymouth Superbird, NASCAR (Free Vehicle Archive)

## Source

"1970 - Plymouth Superbird - Free Vehicle Archive" by Free Vehicle Archive, https://sketchfab.com/3d-models/1970-plymouth-superbird-free-vehicle-archive-3a593f93fc9343ebacc9986714f8b06e (published 2025-10-20).

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared, with this line:

This work is based on "1970 - Plymouth Superbird - Free Vehicle Archive" (https://sketchfab.com/3d-models/1970-plymouth-superbird-free-vehicle-archive-3a593f93fc9343ebacc9986714f8b06e) by Free Vehicle Archive (https://sketchfab.com/free-vehicle-archive) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

## Provenance check (2026-11-25)

| Check | Finding |
| --- | --- |
| Uploader | Free Vehicle Archive (https://sketchfab.com/free-vehicle-archive), the same uploader as the Nomad and the Cadillac (see `../56-nomad/notes.md`) |
| Files | A GLB written by Blender ("Khronos glTF Blender I/O v4.5.47"); one object per part, named `1970 - Plymouth Superbird [NASCAR]` with a number; plain material names (`Vehicle - Body - Paint`, `Chrome`, `RPM`, `Fuel`) |
| Naming | No game naming (no LOD levels, no game folder paths, no game material names) |

The model is the NASCAR race car: roll cage, window net, one race seat, a race gauge panel. The user chose to keep it that way (2026-11-25).

## Files

| File | What it is |
| --- | --- |
| `source/1970 Plymouth Superbird.glb` | The Sketchfab download |
| `textures/` | The images out of the GLB |
| `source.md` | The Sketchfab link |

## Converting it

`tools/fva_to_glb.py superbird-1970 assets/cars/plymouth-superbird-1970.glb`; the car's entry in the converter's `CARS` table says what is left out and where the gauge is (`tools/fva_dash.py`).

## Changes from the download

| Change | Why |
| --- | --- |
| Wheels, the rear axle, the exhaust, and the suspension, transmission and driveshaft in the floor object left out | The game mounts its own wheels and draws its own suspension |
| The rear bumper left on the body, not strippable | Without it the back was ugly and parts stuck through it (user, 2026-11-26); the nose has no bumper |
| The tach's printed needle painted out and a red needle of its own put in, turning 279 degrees from 2,000 to 9,000 rpm; the thin tell-tale and the other gauges stay | A working tach; the race panel has no speedometer and no gas gauge |
| A blank plate on the rear bumper | The game hangs its own plates |

## Dimensions

| | Length | Width | Height | Wheelbase | Source |
| --- | --- | --- | --- | --- | --- |
| 1970 Superbird | 221.0 in | 76.4 in | 61.4 in to the top of the wing | 115.8 in | Aero Warriors, https://aerowarriors.com/sss.html |
| The model, after conversion | 221.0 in | 76.4 in over the paint | 61.4 in to the top of the wing | 115.5 in between the tires | `tools/fva_to_glb.py` |

The model's tires are 28.7 in across; the game draws its wheels 1.121 times their size to fill the wells.
