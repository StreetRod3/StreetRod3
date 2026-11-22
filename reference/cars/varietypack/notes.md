# FREE 1950s Car Variety Pack (Libau Media)

## Source

"FREE 1950s Car Variety Pack" by Libau Media (robinmikart), https://sketchfab.com/3d-models/free-1950s-car-variety-pack-067c3ca92ac0489daadc39ba8b208795 (published 2024-08-19).

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared, with this line:

This work is based on "FREE 1950s Car Variety Pack" (https://sketchfab.com/3d-models/free-1950s-car-variety-pack-067c3ca92ac0489daadc39ba8b208795) by Libau Media (https://sketchfab.com/robinmikart) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

## Provenance check (2026-11-21)

| Check | Finding |
| --- | --- |
| Uploader | Libau Media (robinmikart), on Sketchfab since 2020-02-24, 95 models, almost all their own "based on" builds of 1910s–1950s American cars and props; bio: "I make 3D vehicles and props for games and animations!" |
| Description | Lists the pack's cars and says the textures were "acquired from ambientcg.com" (CC0) and made in Sketchbook Pro |
| Files | Blender FBX export; object names are the artist's own (`buick_coupe`, `hudson`, `patrician`); texture paths point at the artist's own Blender folders (`C:/Users/roadk/...`); no game naming |
| Textures in the download | ambientCG materials (Carpet012, Metal012, Wood026 …) and the artist's own painted images (plates, decals, wheel bakes) |

## Files

| File | What it is |
| --- | --- |
| `source/50scarpackFBX.fbx` | The pack's FBX: 16 vehicles, each one joined mesh (body, interior and wheels together), on a grid and turned 45 degrees |
| `textures/` | The images that came with the download; most ambientCG images the materials name (Metal004, Metal019, Metal025 …) and a few of the artist's own (gauge decals, Buick and Packard badges, the Jeep texture) are not in it |
| `tosplit.blend` | The FBX opened in Blender with the Corvette, the Checker taxi and the Airstream trailer left out (13 vehicles) |
| `split/*.blend` | One vehicle per file, from `tools/split_variety_pack.py`: centered on the origin, mesh and materials untouched, images pointed at `textures/` where present |
| `source.md` | The Sketchfab link |

## The vehicles in split/

| File | Pack name | What it is | Notes |
| --- | --- | --- | --- |
| `buick-1950.blend` | 50buick | 1950 Buick four-door sedan | |
| `buick-1952-convertible.blend` | 52buick_conv | 1952 Buick convertible | |
| `buick-1952-coupe.blend` | 52buick_coupe | 1952 Buick Special two-door Deluxe sedan (model 48D) | Short for the real car: 192 in long on a 115 in wheelbase in the model |
| `buick-1954.blend` | 54buick | 1954 Buick four-door sedan | |
| `buick-1954-wagon.blend` | 54buickwagon | 1954 Buick station wagon | |
| `ford-1950-police.blend` | 50fordpolice | 1950 Ford police car | Livery, roof lights and antenna would have to come off for a civilian car |
| `ford-1950-wagon.blend` | 50fordwagon | 1950 Ford woody wagon | Red steel wheels, spare on the tailgate |
| `ford-1953-panel.blend` | 53fordpanel | Ford F-100 panel van | The wraparound windshield and grille are the 1956 F-100's |
| `hudson-1951.blend` | 51hudson | 1951 Hudson Hornet club coupe | |
| `jeep-1954-usps.blend` | 54 usps jeep | Jeep mail truck | Looks like the later DJ-5; a delivery truck, not a car to buy |
| `packard-1955-caribbean.blend` | 55packard caribbean | 1955 Packard Caribbean convertible | |
| `packard-1955-clipper.blend` | 55packardclipper | 1955 Packard Clipper | |
| `packard-1955-patrician.blend` | 55packard patrician | 1955 Packard Patrician | |

## Converting a car

`tools/variety_pack_to_glb.py <split name> <out.glb>` builds a game body from one of the split files; each car needs an entry in its `CARS` table (real size, paint material, bumper boxes, steering wheel). Done so far: `hudson-1951` and `buick-1952-coupe`.

## Dimensions

| Car | Real car | Model as built |
| --- | --- | --- |
| 1951 Hudson Hornet club coupe | 208.5 in long, 77.4 in wide, 60.4 in high, 124 in wheelbase, 7.10-15 tires | Scaled per axis to the real length, width and height; the model's overhangs are long, so its wheelbase comes out at 118.3 in |
| 1952 Buick Special 48D | 204 in long, 76.7 in wide, 63.4 in high, 121.5 in wheelbase | Scaled per axis to the real length, width and height; wheelbase 122.2 in |

- Conceptcarz, Hudson Hornet Series 7A club coupe: https://www.conceptcarz.com/w9330/hudson-hornet-series-7a.aspx
- Wikipedia, Hudson Hornet: https://en.wikipedia.org/wiki/Hudson_Hornet
- Hometown Buick, 1952 Buick Special 2-door Deluxe Sedan (model 48D): https://www.hometownbuick.com/?p=23152
- Team Buick, 1952 production and models: https://teambuick.com/reference/years/52.php
