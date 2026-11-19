https://cosmos.leartesstudios.com/materials/ca-concrete-road

"CA Concrete Road" by Leartes Studios, Leartes Cosmos; license: https://cosmos.leartesstudios.com/legal/digital-asset-licensing-contract

| File | What it is |
| --- | --- |
| `T_CA_ConcreteRoad_4096_B.png` | Color, 2048 square despite the name; in `assets/textures/concrete/` for the Aqueduct |
| `T_CA_ConcreteRoad_4096_OpenGL_N.png` | Normal map, OpenGL (Godot's) convention; in `assets/textures/concrete/` |
| `T_CA_ConcreteRoad_4096_G.png` | Used as the roughness, in `assets/textures/concrete/`: it averages 0.9. It is `R` inverted |
| `T_CA_ConcreteRoad_4096_AO.png` | Ambient occlusion; in `assets/textures/concrete/` |
| `T_CA_ConcreteRoad_4096_R.png`, `_ORM.png` (green) | Roughness as shipped, averaging 0.1, which drew glassy concrete; not used |
| `T_CA_ConcreteRoad_4096_N.png` | DirectX normal map; not used |
| `T_CA_ConcreteRoad_4096_H.png`, `_M.png`, `_MM.png`, `_MS.png` | Height, metal and mask maps; not used |

The color's mean is 0.257 in linear light, measured from the file (`CA_CONCRETE_LINEAR_MEAN` in `scripts/ground_material.gd`).
