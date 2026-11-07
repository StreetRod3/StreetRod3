// The car paint shader's uniforms and fragment, shared by car_paint_mask.gdshader and
// car_paint_retro.gdshader. With RETRO defined, the color is snapped to the 64 an EGA
// card can show, and the car is neither metallic nor normal-mapped, so its paint lights in
// flat bands.

uniform vec4 paint_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.42;
uniform float use_orm : hint_range(0.0, 1.0) = 0.0;
uniform float use_normal : hint_range(0.0, 1.0) = 0.0;
uniform float normal_scale = 1.0;

#ifdef RETRO
#include "res://shaders/retro_palette.gdshaderinc"
#endif

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 painted = paint_color.rgb * tex.rgb;
	ALBEDO = mix(tex.rgb, painted, tex.a);
#ifdef RETRO
	// The texture's grain rounds to specks of the next color up or down, which is wanted.
	ALBEDO = retro_snap_linear(ALBEDO);
#endif
	if (use_orm > 0.5) {
		vec3 orm = texture(orm_tex, UV).rgb;
		METALLIC = mix(orm.b, metallic, tex.a);
		ROUGHNESS = mix(orm.g, roughness, tex.a);
		AO = orm.r;
	} else {
		METALLIC = mix(0.05, metallic, tex.a);
		ROUGHNESS = mix(0.82, roughness, tex.a);
	}
#ifdef RETRO
	METALLIC = 0.0;
#endif
	// Not in retro: fine bumps would make the flat lighting flicker between lit and shaded.
#ifndef RETRO
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
#endif
}
