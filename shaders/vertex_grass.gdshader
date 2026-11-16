shader_type spatial;
render_mode cull_disabled;

// Mulholland's ground beside the road (track_sides.gd). Each vertex carries its flat color in
// COLOR.rgb and how much of it is grass in COLOR.a: 1 is the grass texture, 0 the flat color, so
// the banks run from grass up into the brown of a hillside. The grass is the same as
// ground_material.gd's: mapped from above in world space, color, normal and roughness, with the
// same triplanar blend as a StandardMaterial3D's world triplanar.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
// Meters of ground one tile of the texture covers.
uniform float tile_m = 2.0;
uniform float sharpness = 8.0;
// Roughness of the flat-colored ground.
uniform float flat_roughness = 0.95;

varying vec3 v_tri_pos;
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
	v_tri_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz / tile_m * vec3(1.0, -1.0, 1.0);
}

vec4 triplanar(sampler2D s) {
	vec4 c = vec4(0.0);
	c += texture(s, v_tri_pos.xy) * v_tri_weights.z;
	c += texture(s, v_tri_pos.xz) * v_tri_weights.y;
	c += texture(s, v_tri_pos.zy * vec2(-1.0, 1.0)) * v_tri_weights.x;
	return c;
}

void fragment() {
	float grass = clamp(COLOR.a, 0.0, 1.0);
	ALBEDO = mix(COLOR.rgb, triplanar(grass_albedo).rgb, grass);
	ROUGHNESS = mix(flat_roughness, triplanar(grass_roughness).r, grass);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), triplanar(grass_normal).rgb, grass);
}
