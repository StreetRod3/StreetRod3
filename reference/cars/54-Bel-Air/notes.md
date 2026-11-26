# 1954 Chevrolet Bel Air (dagtholander)

## Source

"Chevy Bel Air 1954" by dagtholander, https://sketchfab.com/3d-models/chevy-bel-air-1954-be7089002f4b4d858a0422d6a374a211 (published 2018-06-20).

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared, with this line:

This work is based on "Chevy Bel Air 1954" (https://sketchfab.com/3d-models/chevy-bel-air-1954-be7089002f4b4d858a0422d6a374a211) by dagtholander (https://sketchfab.com/dagtholander) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

## Provenance check (2026-11-25)

| Check | Finding |
| --- | --- |
| Uploader | dagtholander (https://sketchfab.com/dagtholander): about twenty models since 2016, guns, cars and props of their own, a few under CC BY; the description asks for credit |
| Files | An FBX written by Blender 2.74 (2015), one object; textures made in Substance (the model's tags), the image paths in the artist's own folder (`C:\3Dmodels\Cars\old\chevybelair\`) |
| Naming | No game naming (no LOD levels, no game folder paths, no game material names) |

## Files

| File | What it is |
| --- | --- |
| `source/chevyBelair1954.fbx` | The Sketchfab download |
| `textures/` | Its images: base color (the glass's see-through in its alpha), metallic, roughness, normal, and the ground plane's |
| `source.md` | The Sketchfab link |
| `photos/` | Reference photos for the dash (photos.md) |
| `review/` | The user's review screenshots (review.md) |

## Converting it

`tools/belair_to_glb.py assets/cars/chevy-bel-air-1954.glb`; the dash, cluster, steering wheel and seats are `tools/belair_dash.py`.

## Changes from the download

| Change | Why |
| --- | --- |
| Wheels, suspension, the engine's pan, the exhaust and the ground plane left out | The game mounts its own wheels and draws its own suspension; the hood screen draws its own engine |
| Bumpers, with their guards, as `bumper_front` and `bumper_rear`; the rear bumper's bar, part of the body in the model, split out by where it is | So the game can strip them |
| A valance under the rear bumper, carried on from the body's bottom edges straight down and tucked in | The bumper hid the body's open bottom there |
| The paint as a mask: the turquoise is the paint, the white roof the accent, the baked grime and dirt specks on the paint cleaned off, the panel seams kept | The garage paints the car; downloaded cars lose their dirt |
| The headliner, which lay on the roof at the same height, moved down; the black insides of the window frames, posts and seals moved in off their outsides, and those at the windshield's foot left out | They fought with the outside and showed as black patches and points |
| The black lid the model has across the cabin at the sills cut back to the package shelf | It stood in for an interior |
| A '54 dash, cluster, steering wheel, gear lever, bench seats, carpet and toe board (`tools/belair_dash.py`), after the photos in `photos/` | The model has no dash and only half a steering wheel; working speedometer and gas gauge |

## Dimensions

| | Length | Width | Height | Wheelbase | Source |
| --- | --- | --- | --- | --- | --- |
| 1954 Bel Air | 197.5 in | 73.0 in | not found for the hardtop | 115 in | Conceptcarz, https://www.conceptcarz.com/s8943/chevrolet-bel-air.aspx |
| The model, after conversion | 197.5 in | 73.0 in over the body | 63.7 in to the roof, scaled as length and width are | 118.1 in between the tires | `tools/belair_to_glb.py` |

The model's tires are 25.7 in across; the game draws its wheels 1.005 times their size to fill the wells.
