# Supercharger (Roots blower)

| Path | What it is |
| --- | --- |
| `supercharger.blend` | The blower and its drive from "Blown 454 cid V8" by Jorma Rysky (https://sketchfab.com/3d-models/blown-454-cid-v8-b7a63eeaa12d4c1d93324a4c09fc79c7, CC Attribution, the author's own model, published 2024-08-11), cut out of the whole engine that is in `reference/parts/454/`; given on 2026-11-26 as the reference for the blower intakes (`tools/make_blower.py`). Objects: `SM_Littlefield_Blower` (the case with its front gear cover, snout, rear cover and the flat inlet plate on top), `SM_BlowerPuley`, `SM_Blower_Belt_Adjustment_Pulley` (the idler), `SM_Crankshaft_Pulley`, `SM_Blower_Belt`. Textures are linked from `source/Blown454.fbm/`, which is not here (they are in `reference/parts/454/textures/`) |

The model is a reference only: the game's blowers are drawn by `tools/make_blower.py` from numbers, as the engines are.

## Measured from the blend (inches)

| What | Size |
| --- | --- |
| Case with snout, overall | 23.35 long, 11.1 wide over the bosses, 7.7 tall with the inlet plate |
| Case body across the middle | 9.2 wide |
| Rotor case, gear cover to rear cover | about 16.5 long |
| Snout, gear cover to pulley | about 7 |
| Blower pulley | 3.8 across, 2.7 wide |
| Idler | 5.05 across, beside the blower pulley and a little lower |
| Crank pulley | 7.2 across |
| Belt | 2.9 wide, flat (a cog belt) |
| Blower pulley axis | 3.3 above the case's base |

## Decisions

- Two four-barrels in tandem on the blower's top, as on the reference engine (its description: "671 blower, Predator carbs"), so the blower takes the game's carburetor slots like any other two-carburetor intake.
- 6-71 on the V8s; the smaller 4-71 is the period blower for the flathead and the Stovebolt.
- The belt runs down the engine's middle from the crank to the snout, across the water pump's shaft, so a blower takes off the belt-driven fan (period blown cars ran an electric fan or none).

## Fitting each engine

| Engine | Clearance |
| --- | --- |
| Chevy small-block | The distributor's cap stands at the back up to 16.7 in over the crank (x 6.7 to 11.0), so the case ends ahead of it (rotor case from x -10.05) |
| Ford small-block | The distributor is at the front (cap up to 14.97 in on the 302, 15.87 on the 351, back to x -7.32): the case sits back (rotor case from x -4.6), on a box the floor's length behind the cap, and a long snout (about 9 in) reaches forward over the cap, 0.4 in clear, to the belt ahead of the water pump (the user's call, 2026-11-26) |
| Y-block | Still drawn with the old engine-v8-283 model, which has no script to build a manifold from; it gets a blower once the new Y-block is built (the user, 2026-11-26) |
| 426 Hemi | The distributor at the right front clears the box by 3 in; the case sits back on the same long snout as the Ford's (the user's call, 2026-11-26) |
| Flathead | The generator stands on top at the front, where the snout goes. It will get a blower, but first needs references for the 3-71 and 4-71 blowers that were run on flatheads (the user, 2026-11-26) |
| Stovebolt | Its intake is on the left side, not on top |
