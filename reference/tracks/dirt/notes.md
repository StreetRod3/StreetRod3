# Mulholland's dirt (`shaders/vertex_ground.gdshader`)

Poliigon "Soil With Weeds" (GroundDirtWeedsPatchy004), the 2K set, https://www.poliigon.com/texture/soil-with-weeds-texture/6987, pasted 2026-11-15. A free asset under Poliigon's royalty-free license, like the grass and asphalt.

| File | What it is |
| --- | --- |
| `GroundDirtWeedsPatchy004_Preview1.png` | Poliigon's preview render |
| `GroundDirtWeedsPatchy004_COL_2K.jpg` | Color, copied to `assets/textures/dirt/` |
| `GroundDirtWeedsPatchy004_NRM_2K.jpg` | Normal map, copied to `assets/textures/dirt/`; OpenGL, as Godot wants (checked against the height map) |
| `GroundDirtWeedsPatchy004_GLOSS_2K.jpg` | Gloss; inverted into `assets/textures/dirt/GroundDirtWeedsPatchy004_ROUGH_2K.jpg`, since Godot takes roughness |
| `GroundDirtWeedsPatchy004_AO_2K.jpg` | Ambient occlusion, not used |
| `GroundDirtWeedsPatchy004_BUMP_2K.jpg`, `..._BUMP16_2K.tiff` | Bump, not used (the normal map covers it) |
| `GroundDirtWeedsPatchy004_DISP_2K.jpg` | Height; its levels stretched (2nd to 98th percentile, 0.369 to 0.545, made 0 to 1) into `assets/textures/dirt/GroundDirtWeedsPatchy004_HEIGHT_2K.jpg`, to break up the change from grass to dirt |
| `GroundDirtWeedsPatchy004_DISP16_2K.tiff` | 16-bit height, not used |
| `GroundDirtWeedsPatchy004_REFL_2K.jpg` | Specular reflection, not used |
