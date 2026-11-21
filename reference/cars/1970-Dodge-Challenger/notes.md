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
