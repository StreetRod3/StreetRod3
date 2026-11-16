shader_type spatial;
render_mode cull_disabled;

// Mulholland's ground beside the road (track_sides.gd). Each vertex says how much of it is grass
// (COLOR.a) and how much is dirt (UV.x); whatever is left is gravel. So the flat ground is grass,
// the hillsides dirt, the banks run from one into the other, and the verge is gravel, the same as
// the course's gravel stretches (ground_material.gd's gravel()). COLOR.rgb is not used. The dirt
// is tinted toward the old flat brown, and none of the three shines. Each texture is mapped from
// above in world space with the same triplanar blend as a StandardMaterial3D's world triplanar
// (see ground_material.gd).

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
// The gravel, tinted by `gravel_color`. Its ARM map holds roughness in green.
uniform vec4 gravel_color : source_color = vec4(1.0);
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_arm : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float gravel_tile_m = 2.0;
// Specular of the grass, dirt and gravel. Low, because Godot scales the grazing-angle reflection
// with it too, and at 0.5 the ground far off turned pale with the sky in it.
uniform float ground_specular = 0.1;
// The dirt is never smoother than this; its own map, about 0.78, read as damp and shiny.
uniform float dirt_min_roughness = 0.92;
// The dirt's color is multiplied by this, in linear light, to bring it toward Street Rod 2's brown
// hills (ground_material.gd works it out).
uniform vec3 dirt_tint = vec3(1.0);

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
	float gravel = 1.0 - grass - dirt;
	// Sampled everywhere, not under an if: the weights change across a triangle, and a texture read
	// in a branch that differs between neighboring pixels gets the wrong mipmap.
	ALBEDO = gravel_color.rgb * triplanar(gravel_albedo, gravel_tile_m).rgb * gravel
		+ triplanar(grass_albedo, grass_tile_m).rgb * grass
		+ clamp(triplanar(dirt_albedo, dirt_tile_m).rgb * dirt_tint, 0.0, 1.0) * dirt;
	ROUGHNESS = triplanar(gravel_arm, gravel_tile_m).g * gravel
		+ triplanar(grass_roughness, grass_tile_m).r * grass
		+ max(triplanar(dirt_roughness, dirt_tile_m).r, dirt_min_roughness) * dirt;
	SPECULAR = ground_specular;
	NORMAL_MAP = triplanar(gravel_normal, gravel_tile_m).rgb * gravel
		+ triplanar(grass_normal, grass_tile_m).rgb * grass
		+ triplanar(dirt_normal, dirt_tile_m).rgb * dirt;
}
