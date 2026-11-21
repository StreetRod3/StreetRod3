# 1963 Chevrolet C10 half-ton Stepside, 6-1/2 ft box

## Model

| File | What it is |
| --- | --- |
| `low-poly-car-chevrolet-c10-pickup-1963.zip` | The Sketchfab download: `source/FullBody.zip` (a 3ds Max OBJ in centimeters, Y up, nose toward +Z, in three objects: LowBody, LowGlass, LowInterior) and its 4096 px textures in `textures/` (base color, metallic, roughness and OpenGL normal maps for the body and the interior, and the glass's color, opacity, metallic and roughness) |
| `1961-chevrolet-apache-interior.jpg` | Photo of a 1961 Chevrolet Apache's dash, the reference for the instrument cluster and steering wheel (the 1960-63 trucks share the cab). Not in the game |

Source: "Low Poly Car - Chevrolet C10 Pickup 1963" by ROH3D, https://sketchfab.com/3d-models/low-poly-car-chevrolet-c10-pickup-1963-679354c151984747bb74310ec5af8995 (published 2021-09-18). ROH3D's own low-poly car series; the description is about the real truck, with no other source named.

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared:

This work is based on "Low Poly Car - Chevrolet C10 Pickup 1963" (https://sketchfab.com/3d-models/low-poly-car-chevrolet-c10-pickup-1963-679354c151984747bb74310ec5af8995) by ROH3D (https://sketchfab.com/roh3d) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

Photo: "1961 Chevrolet Apache truck interior" by dave_7 from Lethbridge, Canada, 2012-07-21, CC BY 2.0 (https://creativecommons.org/licenses/by/2.0), https://commons.wikimedia.org/wiki/File:1961_Chevrolet_Apache_truck_interior_(7749553176).jpg

The game's body is built from the model by `tools/c10_to_glb.py`, with the dash and steering wheel from `tools/c10_dash.py`. It also takes the blank plate from the 1967 Impala's model (reference/cars/impala-1967).

### Downloads turned down

Before this one, two other "1970 Chevrolet Chevelle SS 454" downloads were looked at and not used (2026-11-20). Both are the same mesh as Ddiaz Design's upload (https://sketchfab.com/3d-models/1970-chevrolet-chevelle-ss-454-a27a86ba9e4b43dcaf9cb5806775dd7e, CC BY-NC-SA 4.0), which says it is "Based on a Forza Motorsport 4 3d model", and its parts carry Forza's names (`che_chevelle_70_*_lod0`). The re-uploads marked CC BY (91e719d1… by tangwang920, 20a3b6d7… by AnswerBlue38) have the same 107,079 vertices and 18 materials, and the second's GLB still names Ddiaz Design and the NC-SA license in its header. A game rip can't be licensed by any of them.

## Changes from the download

| Change | Why |
| --- | --- |
| Wheels left out (the four in LowInterior) | The game mounts its own wheels; the model's set the wheel positions |
| The plates (European, 52 x 11 cm, reading "ROH3D.COM") swapped for the Impala's blank US plate, 12 x 6 in | US plates, and no lettering |
| Teal paint turned into the paint mask, its baked shading left off and the panel seams kept | The game paints the truck any color, clean and shiny |
| Grille (with the headlight rims), the frame round it, the bumpers and the tailgate's CHEVROLET made the accent (`model.accent`), off-white until painted; the texture's white on the body behind the bumpers made body paint | On the real truck they were painted, off-white; the garage paints them with its Accent choice. The white behind the bumpers showed when they were stripped (2026-11-21) |
| The steering wheel swapped for an 18 in two-spoke wheel with a dished hub | The model's was a small four-spoke wheel; the photo shows the real one |
| An instrument cluster in a hooded brow on the dash, and a matching brow over the glovebox | The model's dash is a plain strip with a dark patch painted where the gauges would be; it sits too low for a cluster above the steering column, so the cluster stands on it as the real one stands out of the dash |
| Each axis scaled to the real truck | Scaled evenly, the model is 2 to 3% long for its width and height |

## The cluster

From the photo: a wide window with rounded ends. Left to right: TEMPERATURE (C to H), the GENERATOR light, a half-round speedometer from 0 to 100 mph over 240 degrees with 50 at the top, the OIL light, and GASOLINE (E to F). Black face, white markings, the numbers outside the ticks (as the user asked, 2026-11-20). The speedometer and gas gauge work; the temperature needle stays put.

## Dimensions

| Measure | Real truck | Model as built |
| --- | --- | --- |
| Wheelbase | 115 in | 110.8 in (the model's wheel spacing, kept) |
| Overall length | 186.875 in | 186.9 in |
| Width | 78.75 in | 78.75 in over the bumpers (81.9 in with the mirror) |
| Height | 71.25 in | 71.25 in to the roof on the model's tires |
| Track | 63.1 in front, 61 in rear | 59.4 in (the model's wheel wells) |
| Tires | 6.70 x 15 | Model's tires 28.7 in across; the game's wheels are drawn 1.081 times their size to fill the wells |
| Shipping weight | 3,190 lb (C1404 Step-Side) | 1,500 kg in the game, with fluids |
| Engines | 230 six (140 hp) standard; 292 six (165 hp) and 283 V8 optional | The 235 Stovebolt (the 230 isn't in the game) |

- Wikipedia, Chevrolet C/K (first generation) (wheelbase, length, width, height, engines): https://en.wikipedia.org/wiki/Chevrolet_C/K_(first_generation)
- Old Ride, the 1963 Chevrolet C10 (track, tires, shipping weights): https://www.oldride.com/library/1963_chevrolet_c10.html
