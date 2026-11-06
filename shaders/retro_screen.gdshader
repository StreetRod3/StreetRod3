shader_type canvas_item;

// Redraws what is already on screen (the 3D view) as Street Rod 2 would have shown it.
// Goes on a full-screen ColorRect in a CanvasLayer under the HUD (scenes/retro_screen.tscn).

#include "res://shaders/retro_ega.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

void fragment() {
	vec2 pixel_size = retro_pixel_size(SCREEN_PIXEL_SIZE);
	vec2 cell = retro_cell(FRAGCOORD.xy, pixel_size);
	vec2 center = (cell + 0.5) * pixel_size;
	// Four taps inside the retro pixel, so thin lines and far-off detail crawl less.
	vec2 tap = pixel_size * 0.25;
	vec3 color = texture(screen_texture, (center + vec2(-tap.x, -tap.y)) * SCREEN_PIXEL_SIZE).rgb;
	color += texture(screen_texture, (center + vec2(tap.x, -tap.y)) * SCREEN_PIXEL_SIZE).rgb;
	color += texture(screen_texture, (center + vec2(-tap.x, tap.y)) * SCREEN_PIXEL_SIZE).rgb;
	color += texture(screen_texture, (center + vec2(tap.x, tap.y)) * SCREEN_PIXEL_SIZE).rgb;
	COLOR = vec4(retro_quantize(color * 0.25, cell), 1.0);
}
