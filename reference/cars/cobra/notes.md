# 1965 Shelby Cobra (super7's AC Cobra 427)

## Source

"AC Cobra classic" by super7, https://sketchfab.com/3d-models/ac-cobra-classic-e6a38042e6e84189bc158682478e8b24 (published 2018-07-22). The description reads only "AC Cobra for Oculus Home format glb scale 1:1".

License: CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Commercial use is allowed; the author must be credited wherever the game is shared, with this line:

This work is based on "AC Cobra classic" (https://sketchfab.com/3d-models/ac-cobra-classic-e6a38042e6e84189bc158682478e8b24) by super7 (https://sketchfab.com/super7) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

## Provenance check (2026-11-27)

| Check | Finding |
| --- | --- |
| Uploader | super7 (https://sketchfab.com/super7), a basic account |
| Files | A GLB written by THREE.GLTFExporter: four meshes (`mesh0`), four materials (`NewMat02`, `NewMat04`), the whole car on one 2048 px color and normal texture set |
| Naming | The root node is `1966_Shelby_Cobra_427_Mesh.glb`, a file name other than the upload's; no game folder paths, LOD levels or game material names |
| Other uploads | A search found no earlier copy of the model |

The single texture set is a game-ready layout: the user's judgment (2026-11-27) is that the model was made for use in a game, not taken from one.

## Files

| File | What it is |
| --- | --- |
| `source/AC Cobra 1.glb` | The Sketchfab download |
| `textures/` | The images out of the GLB (each is stored twice in it) |
| `source.md` | The Sketchfab link |

## Converting it

`tools/cobra_to_glb.py` (with `tools/cobra_dash.py` for the gauges) writes `assets/cars/shelby-cobra-1965.glb`. What it had to fix:

- **No bottom.** The shell is open through the wheel arches and faces up into the car elsewhere, so with back faces culled you looked up into the cockpit and the engine bay. The converter adds a down-facing floor that meets the model's own wheel tubs.
- **Materials.** The 2018 export made the paint fully metallic and the interior half metallic with no map (nearly black in real-time viewers), multiplied every color by 0.8, and drew a scratch texture on the windscreen at half opacity.
- **Gauges.** The seven dials are painted into the texture with their needles; they get printed faces and needles of their own.
- **Steering wheel.** The wood rim and the spokes with the hub are separate parts; both go into `driving_wheel`.
- **Plate.** The model's rear plate is 7.9 x 3.8 in and reads "JVH 802", which looks like a real registration. Its lettering is painted out of the texture, and a 12 x 6 in blank plate is laid over it on a `plate` material.

## Decisions (the user, 2026-11-27)

- It is a Shelby, but counts as Ford for the parts rules (`"make": "Ford"`).
- The 289 and 427 Cobras are treated as the same car, despite the real differences. It comes with the 289; some will come with a 427 later.
- It has no bumpers. The bars at the corners are jacking points and stay on the body.
- It uses the game's customizable plates.

## Dimensions

| | Real | Used |
| --- | --- | --- |
| Length | 156 in (3,962 mm) | 156 in |
| Width | 68 in (1,727 mm), over the body | 68 in over the body (75.9 in over the side pipes) |
| Wheelbase | 90 in (2,286 mm) | 91.6 in, the model's |
| Height | 47-49 in, ground to windscreen top | 44.6 in on the model's own tires; the model rides 3.8 in off the ground, so the body is not stretched |

Height sources disagree: Wikipedia gives 49 in for the Mk I and 48 in (1,219 mm) for the Mk III; dimensions.com and ultimatespecs give about 49 in for the 427; Hillbank lists 47 in to the top of the screen for its 427 S/C; classic.com and Top Gear give 48 in (1,219 mm) for Superformance replicas.

## Links

- https://en.wikipedia.com/wiki/AC_Cobra
- https://www.dimensions.com/element/shelby-cobra-427-mkiii
- https://www.ultimatespecs.com/car-specs/Shelby/M1627/Cobra
- https://www.motormatchup.com/catalog/Shelby/Cobra/1965/427
- https://hillbankusa.com/models/shelby/csx6000
- https://www.classic.com/veh/1965-shelby-cobra-replica-superformance-spo3770-pd3ZGZW/?tab=comps
- https://www.topgear.com/car-reviews/superformance/2dr-5spd-manual/spec
