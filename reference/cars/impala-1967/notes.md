# 1967 Chevrolet Impala four-door hardtop (Sport Sedan)

## Model

| File | What it is |
| --- | --- |
| `chevrolet-impala-1967.zip` | The Sketchfab download: `source/Exp1.fbx` (Maya, about 1:100 scale, Z up, nose toward −Y) and its Substance Painter textures in `textures/` (2048 px base color, metallic, roughness, mixed AO, DirectX normal and height maps for six materials, plus the glass opacity) |

Source: "Chevrolet Impala 1967" by Eques_inferno, https://sketchfab.com/3d-models/chevrolet-impala-1967-bce35ef0c10d41fdb3f7d8c4225144d2 (published 2020-02-25; the author's description: "A weekly project of Chevrolet Impala from 67", workflow Maya → Substance Painter).

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared, with this line:

This work is based on "Chevrolet Impala 1967" (https://sketchfab.com/3d-models/chevrolet-impala-1967-bce35ef0c10d41fdb3f7d8c4225144d2) by Eques_inferno (https://sketchfab.com/Eques_inferno) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

The game's body is built from it by `tools/impala_to_glb.py` (it runs Blender to read the FBX).

## Changes from the download

| Change | Why |
| --- | --- |
| Wheels left out (`Wheel_LP`, `CWheel_LP`, `Bolt_LP`) | The game mounts its own wheels; the model's set the wheel positions |
| License plates blanked | The download's plates read "KAZ 2Y5 Kansas", the plate of the car in the TV series *Supernatural*; the game's Impala is a plain '67 |
| Black paint turned into the paint mask | The model is painted gloss black (about 2/255); the game paints the car any color through `car_paint_mask.gdshader` |
| Dirt left off, its grit smoothed out of the normal map | The user wants clean, smooth, shiny paint on every panel, including the ones the bumpers hide (2026-11-20); the panel seams stay |
| Printed faces on the seven blank dials; speedometer, tachometer and gas gauge work (`tools/impala_dash.py`) | The model's dials have needles but no markings |
| Each axis scaled to the real car | Scaled evenly, the model is about 3% too wide and too tall for its length |
| Textures cut to 1024 px | Keeps the GLB about 11 MB |

## Dimensions

| Measure | Real car | Model as built |
| --- | --- | --- |
| Wheelbase | 119.0 in | 120.4 in (the model's wheel spacing, kept) |
| Overall length | 213.2 in | 213.2 in |
| Width | 79.9 in | 79.9 in |
| Height | 55.4 in | 55.4 in to the roof on the model's tires |
| Track | 62.5 in front, 62.4 in rear | |
| Tires | 8.25-14 (7.75-14 on six-cylinder cars) | Model's tires 25.9 in across |

- Wikipedia, Chevrolet Impala (fourth generation): https://en.wikipedia.org/wiki/Chevrolet_Impala_(fourth_generation)
- Ultimate Specs, Impala IV Sedan 1967 (length, width, height, track): https://www.ultimatespecs.com/car-specs/Chevrolet/M15183/Impala-IV-Sedan-1967
- Old Ride, the 1967 Impala (tires): https://www.oldride.com/library/1967_chevrolet_impala.html
- Conceptcarz, Chevrolet Impala series: https://www.conceptcarz.com/w7220/chevrolet-impala-series.aspx
