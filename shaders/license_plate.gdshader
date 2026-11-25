shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// A license plate (scripts/license_plate.gd): the front plate's image on a plate at the
// car's nose, the rear one's (with the year sticker) on one at its tail. A single surface
// can hold both plates, so the choice is made here, by which end of the car the point is.
uniform sampler2D front_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D rear_tex : source_color, filter_linear_mipmap, repeat_disable;
// The mesh's own coordinates to the car's, whose nose is +Z.
uniform mat4 car_from_mesh = mat4(1.0);

varying float car_z;

void vertex() {
	car_z = (car_from_mesh * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec4 tex = car_z >= 0.0 ? texture(front_tex, UV) : texture(rear_tex, UV);
	// Past the plate's rounded corners.
	if (tex.a < 0.5) {
		discard;
	}
	ALBEDO = tex.rgb;
	// Painted steel; the sticker is no shinier.
	METALLIC = 0.2;
	ROUGHNESS = 0.42;
}
