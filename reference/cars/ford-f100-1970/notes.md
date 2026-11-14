# 1970 Ford F100

| File | What it is |
| --- | --- |
| `f100.3DS` | The 3ds Max 3 scene the game's body is built from (`tools/f100_to_glb.py`); copied 2026-11-13 from `~/.wine/drive_c/3dsmax3_1/Meshes/f100.3DS`, which stays the working copy edited in Max |
| `f100-render.png` | Render of the truck, pasted 2026-11-06 with its width (79.88 in) |

Original source and license of the scene: not recorded.

Dimensions used: 182.5 in long, 79.88 in wide without the mirrors (the short-bed truck).

## Bumpers

`tools/split_bumpers.py` splits the front and rear bumpers into their own nodes. The model has no frame, only a flat black underside, so with the bumpers off each end showed a slot into the body. The tool adds what the bumpers hid on the real truck, in the underside's black: at the front the lower radiator support, set back behind the bumper line and inside the fenders, with the two frame horns the bumper bolted to; at the rear the crossmember's face under the bed's sill and the frame rails' ends. The rails are 34 in apart outside, as on a 1967-72 F-100 frame (an approximate figure, not from a drawing). At the front corners the dark faces that stood in front of the fenders' white lower corners are taken out, and the underside's lip that ran under the bumper is pulled back, so the fenders show whole. The bumper weights in the car file (25 kg front, 32 kg for the rear step bumper) are estimates, not measured or sourced.
