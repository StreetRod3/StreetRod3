# Day sky (`scripts/skies.gd`)

"Kloofendal 48d Partly Cloudy (Pure Sky)" from Poly Haven, https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky, by Greg Zaal (photography) and Jarod Guest (sky edits). CC0. Downloaded 2026-11-15.

The game uses the 4K Radiance file unchanged, `assets/skies/kloofendal_48d_partly_cloudy_puresky_4k.hdr` (4096x2048, 20 MB; imported VRAM-compressed, about 8 MB), so no copy is kept here. Other sizes, up to 16K and as EXR, are on the page.

| Measured | Value |
| --- | --- |
| Sun | 59.47% across the panorama, 48 degrees up; Godot draws it at heading -34.1 degrees (atan2 of x and z) with no sky rotation |
| Sky, upper half | median 0.34, 90th percentile 0.87, 99th 2.07 (linear luminance) |
| Horizon | mean 0.44 |
