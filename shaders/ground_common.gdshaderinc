// Shared by the ground shaders (ground_surface.gdshaderinc, vertex_ground.gdshader): a hash and
// value noise, and the large-scale variation that keeps a field of one tiling texture from
// reading as one even sheet.

// A hash with no sine, so it holds up a few kilometers from the origin.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Three octaves of value noise, 0 to 1 around 0.5.
float ground_fbm(vec2 p) {
	return 0.5 * value_noise(p) + 0.3 * value_noise(p * 2.3 + 11.0)
		+ 0.2 * value_noise(p * 5.1 + 29.0);
}

// `albedo` brightened and darkened in patches about `patch_size_m` across by up to `patch_bright`
// (0.2 is 20 percent either way), and multiplied toward `patch_tint` by up to `patch_tint_amount`
// in a second, unrelated set of patches. `xz` is the ground's place in the world, in meters. The
// parameters have their own names because a parameter named like a uniform of the including
// shader is read as that uniform.
vec3 ground_macro(vec3 albedo, vec2 xz, float patch_size_m, float patch_bright, vec3 patch_tint,
		float patch_tint_amount) {
	vec2 p = xz / patch_size_m;
	// The sum of octaves stays near 0.5 (about 0.12 either way is usual), so it is stretched to
	// span -1 to 1 by twice that.
	float b = clamp((ground_fbm(p) - 0.5) / 0.24, -1.0, 1.0);
	float t = ground_fbm(p * 0.71 + vec2(37.0, 91.0));
	albedo *= 1.0 + patch_bright * b;
	albedo *= mix(vec3(1.0), patch_tint, patch_tint_amount * smoothstep(0.5, 0.65, t));
	return clamp(albedo, 0.0, 1.0);
}
