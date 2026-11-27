shader_type sky;

// The hood screen's shop, seen only in reflections: lighter overhead, dark floor, a row of
// fluorescent tubes across the ceiling and the open bay door, so chrome and polished metal
// have bright things to catch as they do in a real shop.
uniform vec3 top_color = vec3(0.55, 0.52, 0.48);
uniform vec3 horizon_color = vec3(0.3, 0.28, 0.25);
uniform vec3 ground_horizon = vec3(0.2, 0.19, 0.17);
uniform vec3 ground_bottom = vec3(0.08, 0.075, 0.07);
uniform vec3 tube_color = vec3(3.2, 3.15, 3.0);
uniform vec3 door_color = vec3(1.6, 1.55, 1.45);

void sky() {
	vec3 d = EYEDIR;
	vec3 c;
	if (d.y >= 0.0) {
		c = mix(horizon_color, top_color, smoothstep(0.0, 1.0, d.y));
		if (d.y > 0.12) {
			// The ceiling one unit up: tubes two units apart, each 0.12 wide, three units long.
			vec2 p = d.xz / d.y;
			float across = abs(fract(p.x * 0.5) - 0.5) * 2.0;
			float tube = (1.0 - smoothstep(0.08, 0.12, across)) * (1.0 - smoothstep(2.6, 3.0, abs(p.y)));
			c = mix(c, tube_color, tube);
		}
		float door = (1.0 - smoothstep(0.55, 0.65, abs(atan(d.z, d.x) - 1.9)))
				* (1.0 - smoothstep(0.22, 0.28, d.y));
		c = mix(c, door_color, door);
	} else {
		c = mix(ground_horizon, ground_bottom, smoothstep(0.0, 0.6, -d.y));
	}
	COLOR = c;
}
