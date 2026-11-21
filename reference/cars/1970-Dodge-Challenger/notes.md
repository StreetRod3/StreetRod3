# 1970 Dodge Challenger R/T two-door hardtop

## Model

| File | What it is |
| --- | --- |
| `source/1970 Dodge challenger.blend` | The Sketchfab download: a Blender 2.79 scene (Z up, nose toward −Y, about 2.8 times real size), half-panels with mirror and subdivision modifiers, colored by material settings |
| `textures/Lic.jpeg` | The plate image both plates use (a real California black plate, "UYF 580") |
| `textures/leather_bumpmap.jpeg` | The vinyl roof's grain (bump only) |
| `textures/NormalMap.png`, `textures/background-image-…-tilea.png` | Lamp lens bump stripes and a normal map the scene doesn't use |

Source: "Dodge Challenger 1970" by Artem P (temp0.crazy), https://sketchfab.com/3d-models/dodge-challenger-1970-915d29c2e6af4ef8a48a93337835f3c8 (published 2017-12-08; the author's description: "All things are made in blender. It's my first car, that I created by myself. Created in Blender 2.79", with an ArtStation link, https://www.artstation.com/artwork/vlR4a).

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared, with this line:

This work is based on "Dodge Challenger 1970" (https://sketchfab.com/3d-models/dodge-challenger-1970-915d29c2e6af4ef8a48a93337835f3c8) by Artem P (https://sketchfab.com/temp0.crazy) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

Provenance checked 2026-11-21: the scene's image paths are under `C:/Users/temp0/`, matching the uploader's name, and the file is Blender 2.79 as the description says. Two later Sketchfab uploads with the same face count, "Dodge Challenger 1970" by kenton.harris (2022-12-02, https://sketchfab.com/3d-models/dodge-challenger-1970-7621ad1f38544c3d893a1b6011243b8f) and by 3001105 (2023-01-04, https://sketchfab.com/3d-models/dodge-challenger-1970-80a05c07c0b544a98b01ee8b49e1dc57), are re-uploads of this model; credit Artem P, not them.

The game's body is built from it by `tools/challenger_to_glb.py` (it runs Blender to open the scene).

In the game it is `assets/cars/dodge-challenger-1970.car`: make GM for parts until there are Chrysler engines (stock 327 V8 standing in for the R/T's 383, four-speed manual), 1,590 kg (the R/T hardtop's curb weight is about 3,500 lb), 56% on the front wheels, wheels drawn 1.026 times their size to fill the wells.

## Changes from the download

| Change | Why |
| --- | --- |
| Wheels left out (`TireL1`, `TireL2`, `TireR1`, `TireR2`) | The game mounts its own wheels; the model's set the wheel positions |
| Plate registration painted out, "CALIFORNIA" and the year tab kept | "UYF 580" is a real car's plate |
| Red paint turned into the paint mask | The game paints the car any color through `car_paint_mask.gdshader` |
| Subdivision one level lower on the hood, doors, roof, trunk lid, bumpers and valances, two lower on the body shell and everything else (at least 1) | Triangle count: the scene is 606k without its wheels, the game's body about 95k; the body shell's reflections break up a little up close in the garage, its shape doesn't change |
| The grille's wire lattice swapped for a curved sheet with the lattice's square holes as a repeating texture, the bars rounded by a normal map | The lattice alone was 44k triangles; the sheet is 96. It sits at the lattice's back face, so the grille badge's red R/T fill stays in front |
| Every badge (the Challenger scripts and R/Ts on the grille, trunk lid and both front fenders, DODGE on the hood lip and tail panel, FUEL on the cap) baked into decals: colors, finish and a normal map of the letters' relief, seen straight on along each badge's plane, in one 1024 px atlas with an alpha mask, on small grids that follow the surface behind each badge 2 mm out | About 23,000 triangles to about 600, one material; from the front, side and below they look like the modeled badges, short of the raised letters' tiny shadows |
| Headlights: bulbs (`FrontLight`) left out; the lenses drawn once (no solidify skin), frosted, with the scene's prism pattern (two brick textures on object coordinates: flutes 0.3/15.2 model units apart, bands 0.8/15.2) baked as a repeating normal map and seam color | The scene gets its sealed-beam look from a lit bulb seen through refracting, bump-patterned glass; with plain clear glass the game showed a bare bulb in a bowl |
| Interior replaced: the scene's `Inside` lid at the window line, block seats and ring wheel left out (its underbody pan kept); a new cabin built by `tools/challenger_interior.py` from the photos below: Rallye dash with woodgrain cluster panel, four pods (working 150 mph speedometer, 8000 rpm tachometer and fuel needle; oil, temperature, ammeter and clock fixed), knob panel, radio and heater faces; three-spoke wood-rim wheel on a ribbed column (`driving_wheel`); high-back buckets and rear bench with modeled pleats, no console; pistol-grip four-speed in a boot; pedals, carpet, door and quarter trim, package shelf, visors, mirror; a headliner shaped from the roof | The scene's interior is a placeholder; about 37k triangles, the car about 131k in all. Not modeled: glovebox and ashtray doors, seat belts, window cranks, the indicator lights between the pods |
| Each axis scaled to the real car | Width 0.3527, height 0.37, length 0.3554 of the model's size: the model is about 4% tall for its length |

## Dimensions

| Measure | Real car | Model as built |
| --- | --- | --- |
| Wheelbase | 110.0 in | 111.5 in (the model's wheel spacing, kept) |
| Overall length | 191.3 in | 191.3 in |
| Width | 76.1 in | 76.1 in |
| Height | 50.9 in | 50.9 in to the roof on the model's tires |
| Track | 59.7 in front, 60.7 in rear | 61.9 in at the model's tire centers |
| Tires | not checked yet | Model's tires 27.2 in across, 10.5 in wide |

- Ultimate Specs, Challenger R/T Hardtop 1970: https://www.ultimatespecs.com/car-specs/Dodge/M12955/Challenger-R-T-Hardtop-(1970-JS-23)
- auto-data.net, Challenger 5.6 V8: https://auto-data.net/en/dodge-challenger-5.6-v8-275hp-42831
- autoevolution, Challenger 1969-70: https://www.autoevolution.com/engine/dodge-challenger-1969-70-v8-4mt-425-hp.html
- Challenger specification page: https://www.dodgechallenger.lotusespritturbo.com/Specification.htm

## Interior references

| File | What it is |
| --- | --- |
| `photos/1970-cuda-interior-6336878902.jpg` | 1970 Plymouth 'Cuda 440 Six Pack interior from the passenger door (the Challenger's E-body twin: same buckets, wheel, shifter and door panels; its dash is the 'Cuda's own), by sv1ambo, CC BY 2.0, https://commons.wikimedia.org/wiki/File:1970_Plymouth_%27Cuda_coupe_(6336878902).jpg |
| `photos/1970-cuda-interior-6336116475.jpg` | The same car from the driver's door, by sv1ambo, CC BY 2.0, https://commons.wikimedia.org/wiki/File:1970_Plymouth_%27Cuda_coupe_(6336116475).jpg |
| `photos/challenger-interior-driver-door.png` | A 1970 Challenger's interior from the driver's door: Rallye dash, three-spoke wood-rim wheel with ribbed column cover, high-back buckets with crosswise pleats, pistol-grip four-speed in a boot, clutch and brake pedals, door panel with a woodgrain insert. The user supplied it on 2026-11-21 with https://www.justdashes.com/blog/instructions-1970-74-mopar-e-body-dash-pad-removal-and-replacement/ |
| `photos/challenger-dash-out-of-car.png` | A Rallye dash out of the car: the padded hood over the cluster, the four pods, the knob panel at the left end, the heater controls below it, the radio, the glovebox. Supplied by the user with the same link |
| `photos/challenger-rallye-cluster.png` | The Rallye cluster straight on, left to right: 150 mph speedometer with odometer, 8000 rpm tachometer, the four-in-one gauge (fuel at the top, oil left, temperature right, ammeter at the bottom), clock. Supplied by the user with the same link |

What the R/T's Rallye dash holds (four large round pods: 150 mph speedometer, 8000 rpm tachometer, clock, and a pod of four small gauges for oil pressure, temperature, fuel and ammeter; standard on the R/T, optional on other Challengers), from web searches on 2026-11-21:

- Classic Industries, Dakota Digital gauges for the 1970-74 E-body Rallye dash: https://news.classicindustries.com/dakota-digital-vhx-gauge-system-for-1970-1974-mopar-e-body-rallye-dash
- JEGS, OER RM4127 in-dash Rallye gauge set for 1970-71 Barracuda, 'Cuda and Challenger (seven gauges): https://jegs.com/i/OER/691/RM4127/10002/-1
- Hagerty, the five best dashboards of the muscle-car era: https://hagerty.com/media/?p=8162
- Bucket seats (C55) and the center console (C16) were options; listings show three-spoke Rim-Blow, Tuff and simulated-wood wheels: https://www.autoevolution.com/news/red-on-red-1970-dodge-challenger-is-a-true-js23-r-t-with-original-sheet-metal-275403.html
