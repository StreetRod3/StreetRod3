// Tree trunks, lit to go with the leaf cards (tree_leaves.gdshader): the photo bark is lit in
// `light_steps` hard bands, warm where the sun is full on it and cooler in the part-lit bands.
// The trunk darkens toward the crown and at its foot, and each tree gets its own place on the
// bark and a slight shift of color, so a row of trees doesn't repeat. Made for CylinderMesh
// trunks: its side takes V from 0 at the top to 0.5 at the foot.
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float light_steps = 3.0;
// Multiplies the sun on the fully lit band, and on the least lit; bands between are mixed.
uniform vec4 warm : source_color = vec4(1.0, 0.8, 0.55, 1.0);
uniform vec4 cool : source_color = vec4(0.6, 0.55, 0.9, 1.0);
// Darkening: `crown_shade` at the very top, from `crown_from` of the way up; `foot_shade` at the
// ground, gone by `foot_to` of the way up.
uniform float crown_shade = 0.6;
uniform float crown_from = 0.45;
uniform float foot_shade = 0.3;
uniform float foot_to = 0.08;
// How far a tree's color can stray: brightness either way, and toward red or toward grey.
uniform float tree_value_jitter = 0.18;
uniform float tree_warmth_jitter = 0.12;

varying float tree_rand;
varying float tree_rand2;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec2 at = MODEL_MATRIX[3].xz;
	tree_rand = hash(at);
	tree_rand2 = hash(at + vec2(17.31, -4.7));
}

void fragment() {
	float up = clamp(1.0 - UV.y * 2.0, 0.0, 1.0);
	vec2 uv = UV * uv_scale + vec2(tree_rand, tree_rand2 * 3.0);
	vec3 bark = texture(albedo_texture, uv).rgb * tint.rgb;
	float value = 1.0 + (tree_rand2 * 2.0 - 1.0) * tree_value_jitter;
	float warmth = (tree_rand * 2.0 - 1.0) * tree_warmth_jitter;
	bark *= value * vec3(1.0 + warmth, 1.0, 1.0 - warmth);
	float shade = 1.0 - crown_shade * smoothstep(crown_from, 1.0, up);
	shade *= 1.0 - foot_shade * (1.0 - smoothstep(0.0, foot_to, up));
	ALBEDO = bark * shade;
	NORMAL_MAP = texture(normal_texture, uv).rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	lit = ceil(lit * light_steps) / light_steps;
	vec3 hue = mix(cool.rgb, warm.rgb, lit);
	DIFFUSE_LIGHT += lit * hue * ATTENUATION * LIGHT_COLOR / PI;
}
