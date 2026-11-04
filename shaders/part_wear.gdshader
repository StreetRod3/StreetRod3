shader_type spatial;
render_mode cull_disabled;

// Wear darkens the metal's own color along the surface. A mesh with UVs is
// stained in that unwrap, so the rust bends with the part. `wear` is 0 when
// clean and 1 at 50% worn.
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform bool use_metallic_tex = false;
uniform sampler2D metallic_texture : hint_default_white;
uniform int metal_channel = 0;
uniform bool use_roughness_tex = false;
uniform sampler2D roughness_texture : hint_default_white;
uniform int rough_channel = 0;
uniform float wear : hint_range(0.0, 1.0) = 0.0;
uniform float use_unwrap = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

float _channel(vec4 texel, int channel) {
	if (channel == 1) {
		return texel.g;
	}
	if (channel == 2) {
		return texel.b;
	}
	if (channel == 3) {
		return texel.a;
	}
	if (channel == 4) {
		return (texel.r + texel.g + texel.b) / 3.0;
	}
	return texel.r;
}

float _hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _noise2(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = _hash2(cell);
	float b = _hash2(cell + vec2(1.0, 0.0));
	float c = _hash2(cell + vec2(0.0, 1.0));
	float d = _hash2(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float _on_surface(vec3 p, vec3 n) {
	vec3 weight = abs(n);
	weight = pow(weight, vec3(4.0));
	weight /= max(weight.x + weight.y + weight.z, 0.001);
	return _noise2(p.yz) * weight.x + _noise2(p.xz) * weight.y + _noise2(p.xy) * weight.z;
}

float _stain(vec3 p, vec3 n, vec2 uv, float scale) {
	float has_uv = use_unwrap * step(0.00001, fwidth(uv.x) + fwidth(uv.y));
	float from_uv = _noise2(uv * scale);
	float from_face = _on_surface(p * 4.0, n);
	return mix(from_face, from_uv, has_uv);
}

void fragment() {
	vec3 base = albedo_color.rgb * texture(albedo_texture, UV).rgb;
	float metal = metallic;
	if (use_metallic_tex) {
		metal *= _channel(texture(metallic_texture, UV), metal_channel);
	}
	float rough = roughness;
	if (use_roughness_tex) {
		rough *= _channel(texture(roughness_texture, UV), rough_channel);
	}
	vec3 n = normalize(world_normal);
	float blotch = _stain(world_pos, n, UV, 7.0);
	float pits = _stain(world_pos + vec3(1.7, 0.4, 2.2), n, UV + vec2(0.37, 0.13), 13.0);
	float grain = _stain(world_pos * 3.0, n, UV, 28.0);
	float dirt = smoothstep(0.42, 0.72, blotch) * wear;
	float rust = dirt * smoothstep(0.48, 0.78, pits) * mix(0.55, 1.0, grain);
	float luma = dot(base, vec3(0.3, 0.59, 0.11));
	float dark = 1.0 - smoothstep(0.02, 0.2, luma);
	vec3 color = base * mix(vec3(1.0), vec3(0.78, 0.72, 0.62), wear * 0.75);
	vec3 grime = mix(base * vec3(0.5, 0.4, 0.28), vec3(0.3, 0.22, 0.14), dark);
	vec3 oxide = mix(base * vec3(0.72, 0.3, 0.12), vec3(0.42, 0.16, 0.05), dark);
	color = mix(color, grime, dirt * 0.9);
	color = mix(color, oxide, rust * 0.9);
	ALBEDO = color;
	float cover = clamp(max(dirt, rust), 0.0, 1.0);
	METALLIC = mix(mix(metal, metal * 0.2, wear), 0.0, cover);
	ROUGHNESS = mix(mix(rough, 0.97, wear * 0.85), 1.0, cover);
	SPECULAR = mix(0.5, 0.0, cover);
}
