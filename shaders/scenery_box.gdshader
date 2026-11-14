shader_type spatial;

// Scenery merged by box_batch.gd. Each vertex carries its own look, so boxes of every
// color, roughness, metal and glow draw together: COLOR is the albedo, already linear;
// UV is roughness and metallic; CUSTOM0 is the glow, color times energy, also linear.
// Lit the same way as a StandardMaterial3D with those values.

varying vec3 v_glow;

void vertex() {
	v_glow = CUSTOM0.rgb;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = UV.x;
	METALLIC = UV.y;
	EMISSION = v_glow;
}
