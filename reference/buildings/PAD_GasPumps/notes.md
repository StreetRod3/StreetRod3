# PAD Gas Pumps

Source: "PAD Gas Pumps" by Leartes Studios, Leartes Cosmos, https://cosmos.leartesstudios.com/assets/pad-gas-pumps (license: https://cosmos.leartesstudios.com/legal/digital-asset-licensing-contract). Used for both pumps at the gas station (`assets/locations/gas-station/pump.glb`).

| Folder | What it is |
| --- | --- |
| `Meshes/` | The FBX download: body and dial glass, LOD0 (65k triangles), LOD1 (37k), LOD2 (33k). The game uses LOD2. |
| `Textures/` | The FBX download's 4096 maps. Only the glass set is right: every `T_PAD_GasPump_4096_*` file is a copy of the glass set or laid out like it, so the body's color and normal maps are missing. All seven zips downloaded on 2026-11-19 (FBX and OBJ, 2048 and 4096) had the same fault. |
| `Unreal/` | The Unreal download. Its `T_PAD_GasPump_4096_B` and `_N` are the real body maps; its body material uses `T_PAD_GasPump_Glass_4096_ORM` as the body's ORM too. |
| `TexturesFromUnreal/` | The body's color and normal maps decoded from the Unreal `.uasset` files (Oodle-packed PNG source art) with the unreal-assets-to-glb exporter (https://github.com/Prikalel/unreal-assets-to-glb, patched for UE 5.0 to 5.2). That exporter wrote the images with red and blue swapped; these copies are swapped back (the decoded glass ORM matches `Textures/` byte for byte once swapped). The normal map is DirectX style, as Unreal's are. |
| `font/` | Routed Gothic by Darren Embry (https://github.com/dse/routed-gothic), SIL Open Font License 1.1 (`font/LICENSE.md`), a digitization of the K&E Leroy lettering-template style. The side plate's word is drawn in it. |

The side plate originally read an arrow, "REGULAR" and "LET US KNOW ANYTING NEEDED" (misspelled in the pack). `tools/gas_pump_plates.py` erases both lines and draws "REGULAR" or "SUPER" in Routed Gothic, lower on the plate, for the two pumps. `tools/gas_pump_to_glb.py` builds the GLB (commands in its docstring).
