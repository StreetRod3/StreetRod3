shader_type spatial;
render_mode cull_disabled;

// Mulholland's ground beside the road (track_sides.gd). Each vertex says how high it stands over
// the road (UV.x), in meters: ground at the road's level is grass, and from `dirt_from_m` up it
// turns to dirt over `dirt_over_m`, so a hill is dirt nearly from its foot and a low bank gets
// clumps of it. Ground steeper than `steep_from` is dirt at any height: grass ran a foot up near-
// vertical faces before giving way. The dirt's height map breaks the change up, so clumps of dirt show through the
// grass rather than a brown wash. UV.y is how far out it is from the road's edge,
// in meters:
// gravel, the same as the course's gravel stretches (ground_material.gd's gravel()), covers it out
// to a wavy line inside `verge_m`, so the verge has a ragged outside edge where the mesh is
// straight. COLOR is not used. The dirt is tinted toward the old flat brown, and none of the
// three shines. Each texture is mapped from above in world space with the same triplanar blend as
// a StandardMaterial3D's world triplanar (see ground_material.gd).

#include "res://shaders/ground_common.gdshaderinc"

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
// The grass's occlusion, normal strength and large-scale patches, the same as ground.gdshader's
// for `grass()` (ground_material.gd sets both from the same constants).
uniform sampler2D grass_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_ao_strength = 1.0;
uniform float grass_ao_light_affect = 0.0;
uniform float grass_normal_scale = 1.0;
uniform float macro_size_m = 25.0;
uniform float macro_bright = 0.0;
uniform vec3 macro_tint = vec3(1.0);
uniform float macro_tint_amount = 0.0;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
// The dirt's height, stretched to 0 to 1.
uniform sampler2D dirt_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Ground this high over the road starts to turn to dirt, and is all dirt this much higher.
uniform float dirt_from_m = 0.15;
uniform float dirt_over_m = 0.5;
// Ground whose face points up less than this (the cosine of its slope) starts to turn to dirt,
// and is all dirt by `steep_full`: 0.82 is about 35 degrees, 0.7 about 45.
uniform float steep_from = 0.82;
uniform float steep_full = 0.7;
// How much the dirt's height breaks up the change from grass, and how sharp its clumps are.
uniform float dirt_height_pull = 0.9;
uniform float dirt_sharpness = 0.08;
// Meters of ground one tile of each texture covers.
uniform float grass_tile_m = 2.0;
uniform float dirt_tile_m = 2.0;
uniform float sharpness = 8.0;
// The gravel, tinted by `gravel_color`. Its ARM map holds roughness in green.
uniform vec4 gravel_color : source_color = vec4(1.0);
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_arm : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
// The gravel's height, stretched to 0 to 1: the stones are high, the ground between them low.
uniform sampler2D gravel_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float gravel_tile_m = 2.0;
// The verge's width, from the road's edge (track_sides.gd's MOUNTAIN_VERGE).
uniform float verge_m = 0.89;
// How far its outside edge wanders in from `verge_m`, in meters, and how long its bumps are. It
// never goes out past `verge_m`: there a hill can rise straight up, and gravel ran up its face.
uniform float edge_wobble_m = 0.3;
uniform float edge_wave_m = 2.5;
// Half the width of the zone where the gravel thins out, in meters. Across it the gravel is not
// faded but broken up by its height: the stones last furthest out, and the ground between them
// gives way first, so the edge ends in loose stones on the grass or dirt.
uniform float edge_fade_m = 0.18;
// How much a stone's height carries it out past the edge, and how sharp each stone's own edge is.
uniform float edge_height_pull = 0.9;
uniform float edge_sharpness = 0.06;
// Specular of the grass, dirt and gravel. Low, because Godot scales the grazing-angle reflection
// with it too, and at 0.5 the ground far off turned pale with the sky in it.
uniform float ground_specular = 0.1;
// The dirt is never smoother than this; its own map, about 0.78, read as damp and shiny.
uniform float dirt_min_roughness = 0.92;
// The dirt's color is multiplied by this, in linear light, to bring it toward Street Rod 2's brown
// hills (ground_material.gd works it out).
uniform vec3 dirt_tint = vec3(1.0);

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

vec4 triplanar(sampler2D s, float tile_m) {
	vec3 p = v_world / tile_m;
	vec4 c = vec4(0.0);
	c += texture(s, p.xy) * v_tri_weights.z;
	c += texture(s, p.xz) * v_tri_weights.y;
	c += texture(s, p.zy * vec2(-1.0, 1.0)) * v_tri_weights.x;
	return c;
}

// How much of a blend `weight` (0 to 1) shows, broken up by `height`, a height map's 0 to 1: the
// high parts show first. `pull` is how far height carries, `crisp` how soft each part's edge is;
// a weight of 0 or 1 stays all or nothing.
float height_blend(float weight, float height, float pull, float crisp) {
	float s = mix(-0.5 * pull, 1.0 + 0.5 * pull, weight) + (height - 0.5) * pull;
	return smoothstep(0.5 - crisp, 0.5 + crisp, s);
}

void fragment() {
	// Where the gravel ends: a wavy line inside `verge_m`, its bumps set by the ground's place.
	vec2 p = v_world.xz / edge_wave_m;
	float wobble = 0.65 * value_noise(p) + 0.35 * value_noise(p * 2.7 + 17.0);
	float edge = verge_m - edge_fade_m - edge_wobble_m * wobble;
	float toward_road = 1.0 - smoothstep(edge - edge_fade_m, edge + edge_fade_m, UV.y);
	float gravel = height_blend(toward_road, triplanar(gravel_height, gravel_tile_m).r,
		edge_height_pull, edge_sharpness);
	// The face's own slope, from how the position changes across the screen: the mesh's smoothed
	// normals would lean the foot of a cliff toward flat and leave it grass.
	vec3 face = normalize(cross(dFdx(v_position), dFdy(v_position)));
	float steep = 1.0 - smoothstep(steep_full, steep_from, abs(face.y));
	float dirt_weight = max(clamp((UV.x - dirt_from_m) / dirt_over_m, 0.0, 1.0), steep);
	float dirt_part = height_blend(dirt_weight, triplanar(dirt_height, dirt_tile_m).r,
		dirt_height_pull, dirt_sharpness);
	float dirt = dirt_part * (1.0 - gravel);
	float grass = (1.0 - dirt_part) * (1.0 - gravel);
	// Sampled everywhere, not under an if: the weights change across a triangle, and a texture read
	// in a branch that differs between neighboring pixels gets the wrong mipmap.
	vec3 grass_color = ground_macro(triplanar(grass_albedo, grass_tile_m).rgb, v_position.xz,
		macro_size_m, macro_bright, macro_tint, macro_tint_amount);
	ALBEDO = gravel_color.rgb * triplanar(gravel_albedo, gravel_tile_m).rgb * gravel
		+ grass_color * grass
		+ clamp(triplanar(dirt_albedo, dirt_tile_m).rgb * dirt_tint, 0.0, 1.0) * dirt;
	ROUGHNESS = triplanar(gravel_arm, gravel_tile_m).g * gravel
		+ triplanar(grass_roughness, grass_tile_m).r * grass
		+ max(triplanar(dirt_roughness, dirt_tile_m).r, dirt_min_roughness) * dirt;
	SPECULAR = ground_specular;
	NORMAL_MAP = triplanar(gravel_normal, gravel_tile_m).rgb * gravel
		+ triplanar(grass_normal, grass_tile_m).rgb * grass
		+ triplanar(dirt_normal, dirt_tile_m).rgb * dirt;
	// One depth for the blend, so the grass's own strength goes as much as there is grass.
	NORMAL_MAP_DEPTH = mix(1.0, grass_normal_scale, grass);
	AO = mix(1.0, pow(triplanar(grass_ao, grass_tile_m).r, grass_ao_strength), grass);
	AO_LIGHT_AFFECT = grass_ao_light_affect * grass;
}
