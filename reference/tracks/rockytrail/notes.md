# Gravel (`GroundMaterial.gravel()`, `shaders/vertex_ground.gdshader`)

Poly Haven "Rocky Trail" by Amal Kumar, https://polyhaven.com/a/rocky_trail, CC0. A 2 m by 2 m patch of ground. Pasted 2026-11-16; `rockytrail.md` is the link as it came.

| File | What it is |
| --- | --- |
| `textures/rocky_trail_diff_4k.jpg` | Color; scaled to 2K as `assets/textures/gravel/rocky_trail_diff_2k.jpg` |
| `textures/rocky_trail_nor_gl_4k.jpg` | Normal map, OpenGL; scaled to 2K as `assets/textures/gravel/rocky_trail_nor_gl_2k.jpg` |
| `textures/rocky_trail_arm_4k.jpg` | Ambient occlusion (red), roughness (green), metal (blue); scaled to 2K as `assets/textures/gravel/rocky_trail_arm_2k.jpg`, and only its green is used |
| `rocky_trail_4k.gltf`, `rocky_trail.bin` | Poly Haven's glTF of the material on a plane, not used |

The 2K copies were made with Pillow's Lanczos filter, saved at JPEG quality 92.
