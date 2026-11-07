// Lighting for retro_look.gd: flat bands instead of smooth shading, with a checkerboard
// where one band meets the next, the way Street Rod 2's artwork shades between two
// colors. Shadow edges are dithered the same way, because ATTENUATION carries the
// shadow. No highlights: SR2 had none.
//
// The sun (a directional light) gives three bands, lit, half lit and shaded, by how
// squarely a surface faces it. A lamp (omni or spot) gives one: whatever faces it and is
// not in its shadow is lit evenly, at lamp_strength. Banding a lamp by its fade with
// distance, or by its angle across a flat wall, would paint rings round every lamp.

// How lit a surface must be (light facing it, times shadow) to be fully lit, and to be
// half lit. Flat ground under a sun 30 degrees up faces it at 0.5, so band_lit sits well
// below that: otherwise every road is one big checkerboard.
uniform float band_lit = 0.35;
uniform float band_half = 0.12;
// How far either side of a band's edge the checkerboard reaches.
uniform float dither_width = 0.07;
// Size of one checkerboard square, in screen pixels at 720 rows; scaled with the screen.
uniform float dither_pixel = 2.0;
// A lamp's light, as a share of its full strength, on everything it lights.
uniform float lamp_strength = 0.15;
// How faded a lamp's light must be, near the end of its range, to stop lighting.
uniform float lamp_reach = 0.02;

float retro_band(float lit, float edge, float checker) {
	if (lit >= edge + dither_width) {
		return 1.0;
	}
	if (lit <= edge - dither_width) {
		return 0.0;
	}
	return checker;
}

void light() {
	vec2 cell = floor(FRAGCOORD.xy / (dither_pixel * VIEWPORT_SIZE.y / 720.0));
	float checker = mod(cell.x + cell.y, 2.0);
	float facing = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	if (LIGHT_IS_DIRECTIONAL) {
		float lit = facing * ATTENUATION;
		float level = 0.5 * (retro_band(lit, band_half, checker) + retro_band(lit, band_lit, checker));
		DIFFUSE_LIGHT += LIGHT_COLOR * level / PI;
	} else {
		// 0.5 where the light is lamp_reach strong, so the checkerboard sits on the edge.
		float lit = step(0.02, facing) * clamp(ATTENUATION / (2.0 * lamp_reach), 0.0, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * lamp_strength * retro_band(lit, 0.5, checker) / PI;
	}
}
