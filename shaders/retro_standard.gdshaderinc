// What retro_look.gd turns a StandardMaterial3D into: its color, texture, vertex colors
// and glow, snapped to the retro palette, lit by retro_light.gdshaderinc. The parameters
// are named as on the StandardMaterial3D, so code that sets albedo_color still works.
// retro_standard.gdshader draws one side, retro_standard_double.gdshader both.

#include "res://shaders/retro_palette.gdshaderinc"
#include "res://shaders/retro_light.gdshaderinc"

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform bool use_vertex_color = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec3 albedo = albedo_color.rgb * texture(albedo_texture, UV).rgb;
	if (use_vertex_color) {
		albedo *= COLOR.rgb;
	}
	ALBEDO = retro_snap_linear(albedo);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = retro_snap_linear(emission.rgb) * emission_energy;
}
