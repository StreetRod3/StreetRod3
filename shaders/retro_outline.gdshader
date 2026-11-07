shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

// Dark outlines round everything near the camera, for retro_look.gd. Drawn on a quad that
// covers the screen in every camera, the rear mirror's too, from the depth buffer alone,
// so it works in the Compatibility renderer the web build uses.
//
// Inverse depth (1 / distance) changes evenly across any flat surface on screen, so its
// second difference is zero there. Where it is not, there is an edge: a silhouette, where
// the distance jumps, or a crease, where the surface turns. Far-off lines fade out, so
// distant scenery does not turn into a mass of black.

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Line width in screen pixels at 720 rows; scaled with the screen.
uniform float line_width = 1.0;
// How big the second difference must be, against the depth itself, to draw.
uniform float threshold = 0.05;
uniform float fade_start = 40.0;
uniform float fade_end = 120.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

float distance_at(vec2 uv, mat4 inv_projection) {
	float depth = texture(depth_texture, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 step_uv = line_width * VIEWPORT_SIZE.y / 720.0 / VIEWPORT_SIZE;
	float here = distance_at(SCREEN_UV, INV_PROJECTION_MATRIX);
	float left = distance_at(SCREEN_UV - vec2(step_uv.x, 0.0), INV_PROJECTION_MATRIX);
	float right = distance_at(SCREEN_UV + vec2(step_uv.x, 0.0), INV_PROJECTION_MATRIX);
	float up = distance_at(SCREEN_UV - vec2(0.0, step_uv.y), INV_PROJECTION_MATRIX);
	float down = distance_at(SCREEN_UV + vec2(0.0, step_uv.y), INV_PROJECTION_MATRIX);
	float inv_here = 1.0 / here;
	float bend = abs(1.0 / left + 1.0 / right - 2.0 * inv_here)
			+ abs(1.0 / up + 1.0 / down - 2.0 * inv_here);
	float edge = step(threshold, bend / inv_here);
	float fade = 1.0 - smoothstep(fade_start, fade_end, here);
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a * edge * fade;
}
