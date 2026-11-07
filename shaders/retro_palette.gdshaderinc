// The retro palette, applied to each material's base color before lighting. Colors are
// posterized in OKLab, a color space that follows how people see color: lightness in
// RETRO_LIGHTNESS_STEPS steps, colorfulness (chroma) in RETRO_CHROMA_STEPS steps spaced
// finer near gray, and hue kept as it is. Anything with almost no color comes out an
// exact gray, so near-grays never split into tints.
//
// Rounding red, green and blue each to a few levels (EGA's 64 colors, then a 216-color
// cube) did not work: SR3's muted floors, walls and doors all rounded to the same gray,
// and a near-gray with channels either side of a step turned pink or teal.

const float RETRO_LIGHTNESS_STEPS = 10.0;
const float RETRO_CHROMA_STEPS = 4.0;
// Chroma of the most colorful step; sRGB's strongest colors are about this.
const float RETRO_MAX_CHROMA = 0.32;

vec3 retro_linear_to_oklab(vec3 c) {
	vec3 lms = vec3(
		0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
		0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
		0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	return vec3(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}

vec3 retro_oklab_to_linear(vec3 lab) {
	vec3 lms = vec3(
		lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z,
		lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z,
		lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z);
	lms = lms * lms * lms;
	return vec3(
		4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
		-1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
		-0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z);
}

// For colors in linear light, as ALBEDO is. A dark color that would round to black is
// kept at the lowest step, so dark asphalt stays dark gray; only near-black goes black.
vec3 retro_snap_linear(vec3 color) {
	vec3 lab = retro_linear_to_oklab(clamp(color, 0.0, 1.0));
	float lightness = round(lab.x * RETRO_LIGHTNESS_STEPS) / RETRO_LIGHTNESS_STEPS;
	if (lightness == 0.0 && lab.x > 0.04) {
		lightness = 1.0 / RETRO_LIGHTNESS_STEPS;
	}
	float chroma = length(lab.yz);
	float step_index = round(sqrt(chroma / RETRO_MAX_CHROMA) * RETRO_CHROMA_STEPS) / RETRO_CHROMA_STEPS;
	vec2 hue = chroma > 0.0 ? lab.yz / chroma : vec2(0.0);
	vec3 snapped = vec3(lightness, hue * step_index * step_index * RETRO_MAX_CHROMA);
	return clamp(retro_oklab_to_linear(snapped), 0.0, 1.0);
}
