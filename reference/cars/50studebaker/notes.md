# 1950 Studebaker Champion Starlight coupe

First listed as a 1951 by mistake (the folder was `51studebaker`). The dimensions below are the ones the car was built to; some sources are for 1951 cars, which share the 1950 body.

## Model

| File | What it is |
| --- | --- |
| `model/studebaker_-_car_model.glb` | The Sketchfab download the game's body is built from (`tools/studebaker_to_glb.py`) |
| `model/studebaker_-_car_model.zip` | The same model as glTF, with `license.txt` |
| `model/studebaker-car-model.zip` | The author's original FBX and badge texture |
| `model/Studebaker_-_Car_Model.usdz` | The same model as USDZ |
| `model/license.txt` | The license that came with the download |

Source: "Studebaker - Car Model" by Allie2k, https://sketchfab.com/3d-models/studebaker-car-model-c7578ec0f82043e6b392fcdf9b00c743

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared, with this line:

This work is based on "Studebaker - Car Model" (https://sketchfab.com/3d-models/studebaker-car-model-c7578ec0f82043e6b392fcdf9b00c743) by Allie2k (https://sketchfab.com/Allie2k) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

## Dimensions

| Measure | Real car | Source |
| --- | --- | --- |
| Wheelbase | 115 in | The Henry Ford |
| Overall length | 197.5 in | The Henry Ford, ConceptCarz |
| Width | 70.5 in | The Henry Ford (70.688 in another entry; Ataman Museum 70.6 in) |
| Height | 60.25–61.2 in | The Henry Ford 60.5 / 60.25 in, Ataman Museum 61.2 in |
| Tires | 6.40-15 (about 27 in) | |
| Engine | 169.6 ci (170) L-head six | The Henry Ford |

- The Henry Ford, 1951 Studebaker Champion Starlight Coupe: https://www.thehenryford.org/collections/explore/artifact/100434
- Ataman Museum, 1951 Studebaker Champion Custom Starlight Coupe: https://www.atamanmuseum.com/?p=7428
- Wikipedia, Studebaker Starlight: https://en.wikipedia.org/wiki/Studebaker_Starlight

## Paint

Unlike the other cars, the Studebaker's paint is dithered like the 1956 Corvette's pixelated texture: `"dither_cell": 0.04` in the model section of `assets/cars/studebaker-champion-1950.car` has `shaders/car_paint_mask.gdshader` shade the paint in three flat tones by which way the surface faces (the paint's own color on the tops and shoulders, a solid darker shade down the sides, darker again underneath), with bands of 4 cm checkerboard squares where one tone meets the next. The Corvette's look is baked into its model's texture; the Studebaker has no texture of its own to paint it into, so it is done in the shader.

## Instrument panel

`1952-champion-owners-guide-instrument-panel.jpg` is page 5 of "Your 1952 Champion Owner's Guide" (Project Gutenberg #62925, public domain): https://www.gutenberg.org/cache/epub/62925/pg62925-images.html. It is a guide to the style, not a record of the 1950 dash: 1952 had its own differences. Parts dealers list the instrument cluster as "1951/52 Champion".

- A wide cluster with a chrome frame and a ribbed face, in front of the driver.
- A half-moon speedometer, 0–100 mph, its needle pivoting at the bottom over the odometer window; a red high-beam tell-tale lamp in its face.
- Four small gauges in the corners: gasoline (lower left), ammeter (upper left), oil pressure (upper right, 0-40-80), heat (lower right, C-H).
- Turn signal arrows to either side of the top of the speedometer.
- The guide says the instruments are lit by "non-glare black light".
- The car had no tachometer.

Photos pasted 2026-11-13 (no source given): `dash-photo.png` (a 40-140 dial), `dash-photo-2.png` and `dash-photo-3.png` (10-100 dials). They show slanted white numerals every 10 mph on a black band, a cream dome inside the half-moon with the odometer, small black windows for AMP and OIL (top) and GAS and HEAT (bottom) with their names printed outside the windows, a ribbed dark face in a chrome frame, louvers to the right of the cluster, and a round clock in a winged chrome pod on top of the steering column below the speedometer.

## Bumpers

The source model groups each bumper (bar, guards and grey mounting irons) as `Front_Bumper` and `Rear_Bumper`; `tools/studebaker_to_glb.py` makes them the `bumper_front` and `bumper_rear` nodes so the game can strip them. Their weights in the car file (20 kg front, 18 kg rear) are estimates for a chromed steel bar with guards and brackets, not measured or sourced.
