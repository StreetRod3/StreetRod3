shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.42;
uniform float use_orm : hint_range(0.0, 1.0) = 0.0;
uniform float use_normal : hint_range(0.0, 1.0) = 0.0;
uniform float normal_scale = 1.0;
// An EGA-style checkerboard dither in the paint, like the 1956 Corvette's texture, for
// cars whose .car file sets model.dither_cell: the size of one square in model units
// (0 leaves it off). The paint comes in three flat shades by which way the surface faces:
// its own color on the tops and the shoulders, a solid darker shade down the sides, and
// darker again underneath. Where one shade gives way to the next there is a band of
// squares of the two on a checkerboard rather than a blend.
uniform float dither_cell = 0.0;
// How much darker each shade is than the one above it.
uniform float dither_depth : hint_range(0.0, 0.5) = 0.3;
// Where the shades change, in how far the surface's normal tips up (1) or down (-1).
uniform float dither_upper = 0.25;
uniform float dither_lower = -0.35;
// Half the width of a band of squares, in the same terms.
uniform float dither_band : hint_range(0.0, 0.5) = 0.12;

varying vec3 model_pos;
varying vec3 model_normal;

void vertex() {
	model_pos = VERTEX;
	model_normal = NORMAL;
}

float paint_tone() {
	vec3 n = normalize(model_normal);
	vec3 a = abs(n);
	// The squares lie on whichever model plane the surface faces most.
	vec2 p = a.x > a.y && a.x > a.z ? model_pos.zy : (a.y > a.z ? model_pos.xz : model_pos.xy);
	p /= dither_cell;
	ivec2 c = ivec2(floor(p));
	// 0 on the tops, 1 down the sides, 2 underneath; a band sits on each change.
	float level = step(n.y, dither_upper) + step(n.y, dither_lower);
	float near_upper = step(abs(n.y - dither_upper), dither_band);
	float near_lower = step(abs(n.y - dither_lower), dither_band);
	float band_top = near_upper > 0.0 ? 0.0 : 1.0;
	bool odd = ((c.x + c.y) & 1) == 1;
	float dithered = band_top + (odd ? 1.0 : 0.0);
	// Far off, where a square is smaller than a pixel, blend instead of shimmering.
	float fine = smoothstep(0.35, 0.7, length(fwidth(p)));
	dithered = mix(dithered, band_top + 0.5, fine);
	if (near_upper + near_lower > 0.0) {
		level = dithered;
	}
	return 1.0 - dither_depth * level;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 painted = paint_color.rgb * tex.rgb;
	if (dither_cell > 0.0) {
		painted *= paint_tone();
	}
	ALBEDO = mix(tex.rgb, painted, tex.a);
	if (use_orm > 0.5) {
		vec3 orm = texture(orm_tex, UV).rgb;
		METALLIC = mix(orm.b, metallic, tex.a);
		ROUGHNESS = mix(orm.g, roughness, tex.a);
		AO = orm.r;
	} else {
		METALLIC = mix(0.05, metallic, tex.a);
		ROUGHNESS = mix(0.82, roughness, tex.a);
	}
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
