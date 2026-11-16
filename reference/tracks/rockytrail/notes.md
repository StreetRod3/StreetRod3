# Gravel (`GroundMaterial.gravel()`, `shaders/vertex_ground.gdshader`)

Poly Haven "Rocky Trail" by Amal Kumar, https://polyhaven.com/a/rocky_trail, CC0. A 2 m by 2 m patch of ground. Pasted 2026-11-16; `rockytrail.md` is the link as it came.

| File | What it is |
| --- | --- |
| `textures/rocky_trail_diff_4k.jpg` | Color; scaled to 2K as `assets/textures/gravel/rocky_trail_diff_2k.jpg` |
| `textures/rocky_trail_nor_gl_4k.jpg` | Normal map, OpenGL; scaled to 2K as `assets/textures/gravel/rocky_trail_nor_gl_2k.jpg` |
| `textures/rocky_trail_arm_4k.jpg` | Ambient occlusion (red), roughness (green), metal (blue); scaled to 2K as `assets/textures/gravel/rocky_trail_arm_2k.jpg`, and only its green is used |
| `textures/rocky_trail_disp_4k.jpg` | Height. Not in the original download; fetched from Poly Haven on 2026-11-16 (the same CC0 asset). Scaled to 2K as `assets/textures/gravel/rocky_trail_disp_2k.jpg` with its levels stretched (2nd to 98th percentile, 0.498 to 0.773, made 0 to 1), for the verge's edge |
| `rocky_trail_4k.gltf`, `rocky_trail.bin` | Poly Haven's glTF of the material on a plane, not used |

The 2K copies were made with Pillow's Lanczos filter, saved at JPEG quality 92.
