# PAD Dumpster

Source: "PAD Dumpster" by Leartes Studios, Leartes Cosmos, https://cosmos.leartesstudios.com/assets/pad-dumpster (license: https://cosmos.leartesstudios.com/legal/digital-asset-licensing-contract). Used for the dumpsters in the city and the `dumpster` track scenery (`assets/locations/city/dumpster.glb`).

| Folder | What it is |
| --- | --- |
| `Unreal/` | The Unreal download (UE 5.0): the whole dumpster, the bin without lids, the two lids, their blueprints, and 4096 color, normal, ORM and mask maps. The pack has only the one detail level (74k triangles). |
| `Export/` | `Unreal/` exported by the unreal-assets-to-glb fork (https://github.com/Hellmark/unreal-assets-to-glb, branch `5.5`) on 2026-11-20: `Meshes/` (unwelded, in centimeters) and the dumpster's `Textures/`. The colors come out right (the fork swaps Unreal's BGRA source back), and the normal map is DirectX style, as Unreal's are. The mask map is for the pack's master material and is not used. |

The blueprints, which set the lids on the bin, are not exported. Each lid's origin is its hinge, and it fits the whole dumpster exactly when moved by a pure offset, found by matching vertices; `tools/dumpster_to_glb.py` keeps those offsets. It builds the GLB from `Export/` (command in its docstring): the bin and both lids welded and cut to 15% (11k triangles in all), real size, the front to +Z, textures cut to 1024 and 512.

Export command: `~/Code/unreal-assets-to-glb/.venv/bin/python ~/Code/unreal-assets-to-glb/main.py reference/buildings/PAD_Dumpster/Unreal --export-dir <out>`, then copy `Meshes/` and the `T_PAD_Dumpster_4096_*` textures into `Export/`.
