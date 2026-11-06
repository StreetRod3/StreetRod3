shader_type canvas_item;

// The rear mirror (a SubViewportContainer), flipped left to right and drawn on the same
// retro pixel grid as the screen behind it.

#include "res://shaders/retro_ega.gdshaderinc"

uniform bool retro = true;

void fragment() {
	vec2 uv = UV;
	vec2 cell = vec2(0.0);
	if (retro) {
		vec2 pixel_size = retro_pixel_size(SCREEN_PIXEL_SIZE);
		cell = retro_cell(FRAGCOORD.xy, pixel_size);
		vec2 to_center = (cell + 0.5) * pixel_size - FRAGCOORD.xy;
		uv += dFdx(UV) * to_center.x + dFdy(UV) * to_center.y;
	}
	vec4 color = texture(TEXTURE, vec2(1.0 - uv.x, uv.y));
	COLOR = retro ? vec4(retro_quantize(color.rgb, cell), color.a) : color;
}
