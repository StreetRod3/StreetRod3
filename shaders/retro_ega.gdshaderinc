// Street Rod 2's screen: 320x200 in EGA's sixteen colors, shown at 4:3, so each pixel
// is 1.2 times as tall as it is wide. Shades between the sixteen are drawn as a
// checkerboard of two, the way SR2's artwork does it. ega_lut.png (made by
// tools/make_ega_lut.py) says which color or pair to use for every color.
//
// The pixel grid is laid on the screen, not on what is drawn, so the race view and
// the rear mirror line up. SR3's colors are muted next to EGA's, so they are made more
// saturated first: otherwise the slate sky and most of the world come out gray.

uniform sampler2D ega_lut : filter_nearest, repeat_disable;
uniform float rows = 200.0;
uniform float pixel_aspect = 1.2;
uniform float saturation = 1.7;

const vec3 EGA[16] = vec3[16](
	vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.667), vec3(0.0, 0.667, 0.0), vec3(0.0, 0.667, 0.667),
	vec3(0.667, 0.0, 0.0), vec3(0.667, 0.0, 0.667), vec3(0.667, 0.333, 0.0), vec3(0.667, 0.667, 0.667),
	vec3(0.333, 0.333, 0.333), vec3(0.333, 0.333, 1.0), vec3(0.333, 1.0, 0.333), vec3(0.333, 1.0, 1.0),
	vec3(1.0, 0.333, 0.333), vec3(1.0, 0.333, 1.0), vec3(1.0, 1.0, 0.333), vec3(1.0, 1.0, 1.0)
);

// One retro pixel's size in screen pixels.
vec2 retro_pixel_size(vec2 screen_pixel_size) {
	float tall = 1.0 / (screen_pixel_size.y * rows);
	return vec2(tall / pixel_aspect, tall);
}

// Which retro pixel a screen position is in.
vec2 retro_cell(vec2 frag_coord, vec2 pixel_size) {
	return floor(frag_coord / pixel_size);
}

vec3 retro_quantize(vec3 color, vec2 cell) {
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = clamp(mix(vec3(luma), color, saturation), 0.0, 1.0);
	vec3 level = clamp(floor(color * 31.0 + 0.5), 0.0, 31.0);
	vec2 at = (vec2(level.r + 32.0 * level.b, level.g) + 0.5) / vec2(1024.0, 32.0);
	vec3 way = texture(ega_lut, at).rgb;
	bool odd = mod(cell.x + cell.y, 2.0) >= 1.0;
	float pick = (way.b > 0.5 && odd) ? way.g : way.r;
	return EGA[int(round(pick * 15.0))];
}
