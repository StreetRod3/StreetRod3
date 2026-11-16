# Cloudy evening sky, `evening-orange` (`scripts/skies.gd`)

Poliigon HdrSkyEvening006, "Cloudy Horizon Evening, orange", https://www.poliigon.com/hdri/cloudy-horizon-evening-outdoor-sky-hdri-orange/3522 (the source confirmed 2026-11-16). Pasted 2026-11-16. Sky only: the lower half is black.

| File | What it is |
| --- | --- |
| `HdrSkyEvening006_HDR_8K.exr` | 8192x4096 HDR. `tools/prepare_hdri.gd` scales it to `assets/skies/evening-orange.exr`, 4096x2048 |
| `HdrSkyEvening006_JPG_8K.jpg` | 16384x8192 JPG for display, not used |
| `HdrSkyEvening006_preview1.jpg` | Poliigon's preview |

The sun measured by `tools/prepare_hdri.gd`: `sun_u` 0.4999, `sun_up` 0.4 degrees, a point of luminance 24,407 over 8 pixels right on the horizon.
