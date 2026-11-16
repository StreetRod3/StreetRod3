# Night sky, stars (`night-stars` in `scripts/skies.gd`)

"Deep Space Starry Sky HDRI" by Nandu M, from BlendKit: https://www.blendkit.com/asset-gallery-detail/8f312632-1756-4ddc-aac0-c4a8456a2923/ (asset base id 8f312632-1756-4ddc-aac0-c4a8456a2923, asset id 5c682094-0766-4b60-82cf-00d7ac781fbd). Uploaded 2026-08-17. Downloaded 2026-11-15 as BlendKit's free original, without an account.

| File | What it is |
| --- | --- |
| `deep-space-starry-sky-18k.exr` | The original, unchanged: OpenEXR, 18000x9000, DWAA compression, 16 MB. Kept here on disk but out of Git (`.gitignore`); download it again from the page above |
| `preview.jpg` | BlendKit's 512x512 thumbnail: a dark star field over a black lower half, with a faint orange-blue glow on the horizon |
| `assets/skies/deep-space-stars.exr` | The game's copy, 4096x2048 half-float EXR (16 MB), imported VRAM-compressed without mipmaps |

BlendKit also offers 0.5K, 1K, 2K, 4K and 8K copies on the page.

Godot can't read DWAA-compressed EXRs, so the game's copy was made in two steps. Blender re-saved the original as a ZIP-compressed half-float EXR at full size (`bpy.data.images.load`, then `save_render` with `exr_codec = "ZIP"` and `color_depth = "16"`). `tools/prepare_hdri.gd` then scaled that down. The stars survive the scaling as single bright pixels.

The author describes it as a deep-space sky: a dark cosmos with faint distant stars. It has no sun, so its `sun_u` and `sun_up` stay `-1`. `prepare_hdri.gd` found its brightest patch at u 0.7328, 61 degrees up, luminance 7.4 over 98 pixels; that patch is a cluster of stars, not a sun. The street drag uses it, with the same light as the black night sky of Street Rod 2's other cruise races (see docs/ground-textures.md).

## License

BlendKit "Royalty Free" (https://www.blendkit.com/docs/licenses/), marked free. Commercial use is allowed and credit isn't required, though BlendKit asks for it. The asset can't be resold in the same form. BlendKit's FAQ says assets in games "shouldn't be directly extractable in the distribution". The licensing pages don't say whether the raw file may sit in a public repository, so only the scaled-down game copy is in Git.
