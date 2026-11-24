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
| `buick-1954.blend` | 54buick | 1954 Buick Special four-door sedan | Modeled 250 in long on a 150 in wheelbase, far over the real car; a strip speedometer; a hula girl on the dash |
| `buick-1954-wagon.blend` | 54buickwagon | 1954 Buick station wagon | |
| `ford-1950-police.blend` | 50fordpolice | 1950 Ford Custom Fordor police car | In the game as a civilian car, its police gear left out |
| `ford-1950-wagon.blend` | 50fordwagon | 1950 Ford Custom Deluxe station wagon (Country Squire) | Red steel wheels, spare on the tailgate |
| `ford-1953-panel.blend` | 53fordpanel | Ford F-100 panel van | The wraparound windshield and grille are the 1956 F-100's |
| `hudson-1951.blend` | 51hudson | 1951 Hudson Hornet club coupe | |
| `jeep-1954-usps.blend` | 54 usps jeep | Jeep mail truck | Looks like the later DJ-5; a delivery truck, not a car to buy |
| `packard-1955-caribbean.blend` | 55packard caribbean | 1955 Packard Caribbean convertible | |
| `packard-1955-clipper.blend` | 55packardclipper | 1955 Packard Clipper Custom Constellation hardtop | Red with a cream roof and rear sides |
| `packard-1955-patrician.blend` | 55packard patrician | 1955 Packard Patrician four-door sedan | Maroon and cream |

## Converting a car

`tools/variety_pack_to_glb.py <split name> <out.glb>` builds a game body from one of the split files; each car needs an entry in its `CARS` table (real size and wheelbase, paint material, bumper boxes, steering wheel). Done so far: `hudson-1951` (in the game as `hudson-hornet-1951`), `buick-1952-coupe` (`buick-special-1952`), `ford-1950-police` (`ford-custom-1950`), `packard-1955-clipper` (`packard-clipper-1955`), `packard-1955-patrician` (`packard-patrician-1955`), `ford-1950-wagon` (`ford-country-squire-1950`) and `buick-1954` (`buick-special-1954`). Where a car's tire or gauge-face material has a name of its own, `tire` and `dial_face` give it; `drop` (boxes) and `drop_materials` leave parts out; `steer` can be a box round the whole wheel when the rim is in pieces; `recolor`, `fill` and `badges` give triangles another material's look, add flat panels, and draw decal lettering. The dials become working gauges through `tools/variety_pack_dash.py`, by the `dials` entry in `CARS`.

## Changes from the download

| Change | Why |
| --- | --- |
| Wheels, hubcaps, brake backing plates and spring hangers left out | The game mounts its own wheels and draws its own suspension |
| Tailpipes left out | They stuck out behind the car once the rear bumper came off (user, 2026-11-22; the Packard's, which run out through its bumper, 2026-11-23) |
| Bumpers, with their guards, brackets and plates, as `bumper_front` and `bumper_rear` | So the game can strip them |
| Plates replaced by the blank plate (`assets/cars/plate-blank.png`, from the Impala's, `tools/make_blank_plate.py`) on a material named `plate` | The pack's plates read "LIBAU"; the player is to make their own plates later (user, 2026-11-22) |
| Buick: the rear quarters' front edge trimmed in flush with the doors just above the side strip | The pack's quarter panel reaches 6 mm forward over the door's back edge there and stands 6 mm proud of it, so it cast a shadow onto the door (user, 2026-11-22); `trim` in the converter's `CARS` table |
| Ford: the police gear left out (the "POLICE" lettering, roof lights and siren, the spotlight and its bracket, the three antennas, the radio with its microphone cord, the screen behind the front seat); the white front doors painted with the rest | So it is a civilian 1950 Ford Custom |
| Packard: the knobs in the middle of the dials left out | The new needles have hubs of their own |
| Ford: the top of the dash in the middle and the gravel pan under the grille painted with the body; the headliner along the windshield's top, which the pack has in the paint, made headliner | The dash top's ribbed image came out a grey panel and the pan black (user, 2026-11-23) |
| Packards and the 1954 Buick: a panel added under the grille, behind the bumper (cream on the Packards, body color on the Buick) | With the bumper off there was a hole into the engine bay there (user, 2026-11-23) |
| Ford wagon: the gravel pan under the grille painted with the body | As on the Ford sedan |
| Ford wagon: the spare wheel on the tailgate painted with the body | The pack paints the car's wheels its red; the road wheels are the game's, the spare (a bare wheel, no tire) is the body's (user, 2026-11-23) |
| 1954 Buick: the frame rails' ends pulled in to end inside the body | They ran out through the panels behind the bumpers and showed as brackets with the bumpers off (user, 2026-11-23) |
| 1954 Buick: its strip speedometer and the small strip under it made a sliding speedometer (0-120 mph) and gas gauge | The game slides a needle in a `linear` pod; the speedometer's top is in the pod's name |
| Packard: the "Packard" and "Clipper" scripts drawn as chrome lettering cut out by their image | Their image is a mask, which as one color made a dark box each (user, 2026-11-23) |
| Front lamps in the tail-light material made clear | The pack gives the Buick red parking lamps; the real ones were clear |
| Gauge faces printed and needles added: the Hudson's speedometer and combination gauge (fuel works, temperature stays put), the Buick's and the Ford's speedometer with a small gas gauge, the Packards' speedometer with four small gauges (fuel works; temperature, oil and amps stay put), the 1954 Buick's strip speedometer and gas gauge | The pack's gauge image is not in the download and the dials have no needles; the small dial across the dash (a clock) keeps its plain face |
| Colors from the material settings in one palette, the paint as the mask | Most of the images the materials used are not in the download |
| Length scaled in two parts | The wheelbase to the real one between the axles, the overhangs to the rest of the real length, easing from one to the other around each axle, so the car is neither too long nor short in the wheelbase (user, 2026-11-22) |

## Dimensions

| Car | Real car | Model as built |
| --- | --- | --- |
| 1951 Hudson Hornet club coupe | 208.5 in long, 77.4 in wide, 60.4 in high, 124 in wheelbase, 7.10-15 tires | Real length, width, height and wheelbase; the model's overhangs (95 in together) shortened to the real 84.5 in (scale 0.883), the wheelbase kept (1.000) |
| 1952 Buick Special 48D | 204 in long, 76.7 in wide, 63.4 in high, 121.5 in wheelbase | Real length, width, height and wheelbase; the model's 115 in wheelbase stretched by 1.057, its overhangs by 1.075 |
| 1950 Ford Custom Fordor | 196.8 in long, 72.8 in wide, 63.1 in high, 114 in wheelbase | Real length, width, height and wheelbase; the model's 124.6 in wheelbase shortened by 0.914, its overhangs by 0.948 |
| 1955 Packard Clipper Custom Constellation hardtop | 214.8 in long, 78.0 in wide, 62.0 in high, 122 in wheelbase | Real length, width, height and wheelbase; the model's 125.9 in wheelbase shortened by 0.969, its overhangs by 0.973 |
| 1955 Packard Patrician | 219.7 in long, 78.3 in wide, 62.2 in high, 127 in wheelbase | Real length, width, height and wheelbase; the model's wheelbase kept (1.000), its overhangs shortened by 0.970 |
| 1950 Ford Custom Deluxe station wagon | 208.0 in long, 76.4 in wide over the wood (72.8 over the fenders, as the sedan), 114 in wheelbase; height not given | Real length and wheelbase, the fenders 72.8 in; the height scaled as the width (0.949) |
| 1954 Buick Special four-door (Series 40) | 206.3 in long, 76.8 in wide, 60.5 in high, 122 in wheelbase | Real length, width, height and wheelbase; the model's 150 in wheelbase shortened by 0.813, its overhangs by 0.844 |

- Conceptcarz, Hudson Hornet Series 7A club coupe: https://www.conceptcarz.com/w9330/hudson-hornet-series-7a.aspx
- Wikipedia, Hudson Hornet: https://en.wikipedia.org/wiki/Hudson_Hornet
- Hometown Buick, 1952 Buick Special 2-door Deluxe Sedan (model 48D): https://www.hometownbuick.com/?p=23152
- Team Buick, 1952 production and models: https://teambuick.com/reference/years/52.php
- Wikipedia, 1949 Ford (1950 length and wheelbase): https://en.wikipedia.org/wiki/1949_Ford
- The Henry Ford, 1949 Ford specifications (height): https://ophelia.sdsu.edu:8443/henryford_org/03-25-2015/exhibits/showroom/1949/specs.html
- carsales (Redbook), 1955 Packard Clipper Custom Constellation: https://www.carsales.com.au/research/packard/clipper/1955/custom-constellation
- Wikipedia, Packard Patrician (1955-56): https://en.wikipedia.org/wiki/Packard_Patrician
- AMA specifications, 1954 Buick (January 1954): https://autohistorypreservationsociety.org/wp-content/uploads/1954-BUICK-AMA-Specs-Special-Century-Super-Roadmaster-Pg-1-25.pdf
