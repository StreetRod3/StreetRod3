// One photographed ground texture (ground_material.gd's grass and asphalt), mapped from above in
// world space with the same triplanar blend as a StandardMaterial3D's world triplanar, so it
// looks the same as the StandardMaterial3D it replaced. On top of that: a stronger normal map,
// the texture's ambient occlusion, and large-scale patches (ground_common.gdshaderinc) that
// break up the tiling in the distance, where the normal map's small bumps average out to flat.
// ground.gdshader and ground_two_sided.gdshader include this; they differ only in culling.

#include "res://shaders/ground_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Multiplies the color, like a StandardMaterial3D's albedo_color.
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// How far the normal map tilts the surface; 1 is the map as made.
uniform float normal_scale = 1.0;
uniform sampler2D roughness_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// The occlusion map is raised to this power: the maps are faint, 1 barely shows.
uniform float ao_strength = 1.0;
// How much the occlusion darkens sunlight as well as ambient light.
uniform float ao_light_affect = 0.0;
uniform float specular = 0.5;
// Meters of ground one tile of the texture covers.
uniform float tile_m = 1.0;
uniform float sharpness = 8.0;
// The large-scale patches: their size in meters, how much they brighten and darken, and the
// color the second set of patches leans toward and how far.
uniform float macro_size_m = 25.0;
uniform float macro_bright = 0.0;
uniform vec3 macro_tint = vec3(1.0);
uniform float macro_tint_amount = 0.0;

varying vec3 v_world;
varying vec3 v_position;
varying vec3 v_tri_weights;

void vertex() {
	TANGENT = vec3(0.0, 0.0, -1.0) * abs(NORMAL.x);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.y);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.z);
	TANGENT = normalize(TANGENT);
	BINORMAL = vec3(0.0, 1.0, 0.0) * abs(NORMAL.x);
	BINORMAL += vec3(0.0, 0.0, -1.0) * abs(NORMAL.y);
	BINORMAL += vec3(0.0, 1.0, 0.0) * abs(NORMAL.z);
	BINORMAL = normalize(BINORMAL);
	v_tri_weights = pow(abs(mat3(MODEL_MATRIX) * NORMAL), vec3(sharpness));
	v_tri_weights /= dot(v_tri_weights, vec3(1.0));
	v_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world = v_position * vec3(1.0, -1.0, 1.0);
}

vec4 triplanar(sampler2D s) {
	vec3 p = v_world / tile_m;
	vec4 c = vec4(0.0);
	c += texture(s, p.xy) * v_tri_weights.z;
	c += texture(s, p.xz) * v_tri_weights.y;
	c += texture(s, p.zy * vec2(-1.0, 1.0)) * v_tri_weights.x;
	return c;
}

void fragment() {
	vec3 albedo = triplanar(albedo_tex).rgb * tint.rgb;
	ALBEDO = ground_macro(albedo, v_position.xz, macro_size_m, macro_bright, macro_tint,
		macro_tint_amount);
	ROUGHNESS = triplanar(roughness_tex).r;
	METALLIC = 0.0;
	SPECULAR = specular;
	NORMAL_MAP = triplanar(normal_tex).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	AO = pow(triplanar(ao_tex).r, ao_strength);
	AO_LIGHT_AFFECT = ao_light_affect;
}
