shader_type spatial;
render_mode cull_disabled;

// Mulholland's ground beside the road (track_sides.gd). Each vertex says how much of it is grass
// (COLOR.a) and how much is dirt (UV.x); its flat COLOR.rgb shows through whatever is left. So the
// flat ground is grass, the hillsides dirt, the banks run from one into the other, and the verge
// keeps its flat gray. Both textures are mapped from above in world space with the same
// triplanar blend as a StandardMaterial3D's world triplanar (see ground_material.gd).

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
// Meters of ground one tile of each texture covers.
uniform float grass_tile_m = 2.0;
uniform float dirt_tile_m = 2.0;
uniform float sharpness = 8.0;
// Roughness of the flat-colored ground.
uniform float flat_roughness = 0.95;

varying vec3 v_world;
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
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * vec3(1.0, -1.0, 1.0);
}

vec4 triplanar(sampler2D s, float tile_m) {
	vec3 p = v_world / tile_m;
	vec4 c = vec4(0.0);
	c += texture(s, p.xy) * v_tri_weights.z;
	c += texture(s, p.xz) * v_tri_weights.y;
	c += texture(s, p.zy * vec2(-1.0, 1.0)) * v_tri_weights.x;
	return c;
}

void fragment() {
	float grass = clamp(COLOR.a, 0.0, 1.0);
	float dirt = clamp(UV.x, 0.0, 1.0 - grass);
	float flat_part = 1.0 - grass - dirt;
	// Sampled everywhere, not under an if: the weights change across a triangle, and a texture read
	// in a branch that differs between neighboring pixels gets the wrong mipmap.
	ALBEDO = COLOR.rgb * flat_part
		+ triplanar(grass_albedo, grass_tile_m).rgb * grass
		+ triplanar(dirt_albedo, dirt_tile_m).rgb * dirt;
	ROUGHNESS = flat_roughness * flat_part
		+ triplanar(grass_roughness, grass_tile_m).r * grass
		+ triplanar(dirt_roughness, dirt_tile_m).r * dirt;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0) * flat_part
		+ triplanar(grass_normal, grass_tile_m).rgb * grass
		+ triplanar(dirt_normal, dirt_tile_m).rgb * dirt;
}
