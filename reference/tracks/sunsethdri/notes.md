# Hazy sunset sky, `sunset-pink` (`scripts/skies.gd`)

Poliigon HdrSkySunset007, taken to be "Hazy Horizon Sunset, pink orange", https://www.poliigon.com/hdri/hazy-horizon-sunset-outdoor-sky-hdri-pink-orange/3537 (the page could not be read to check the asset number). Pasted 2026-11-16. Sky only: the lower half is black.

| File | What it is |
| --- | --- |
| `HdrSkySunset007_HDR_8K.exr` | 8192x4096 HDR. `tools/prepare_hdri.gd` scales it to `assets/skies/sunset-pink.exr`, 4096x2048 |
| `HdrSkySunset007_JPG_8K.jpg` | 16384x8192 JPG for display, not used |
| `HdrSkySunset007_preview1.jpg` | Poliigon's preview |

The sun measured by `tools/prepare_hdri.gd`: `sun_u` 0.4856, `sun_up` 4.9 degrees, brightest luminance 49.5.
