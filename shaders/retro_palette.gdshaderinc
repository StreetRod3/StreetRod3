// The 64 colors an EGA card can show: each of red, green and blue is 0, 1/3, 2/3 or
// full. Street Rod 2 picked sixteen of them at a time; retro_look.gd allows all 64.

// A dark color that would round to black is first brightened, hue kept, until its
// strongest channel reaches the lowest step, so dark asphalt becomes dark gray and a
// dark green stays green. Only near-black stays black.
vec3 retro_snap_srgb(vec3 color) {
	vec3 c = clamp(color, 0.0, 1.0);
	float strongest = max(c.r, max(c.g, c.b));
	if (strongest > 0.03 && strongest < 1.0 / 6.0) {
		c *= (1.0 / 3.0) / strongest;
	}
	return round(c * 3.0) / 3.0;
}

// For colors already in linear light, as ALBEDO is: snapped in sRGB, where the 64 are
// evenly spaced, and turned back.
vec3 retro_snap_linear(vec3 color) {
	vec3 c = clamp(color, 0.0, 1.0);
	vec3 srgb = mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
	srgb = retro_snap_srgb(srgb);
	return mix(srgb / 12.92, pow((srgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), srgb));
}
