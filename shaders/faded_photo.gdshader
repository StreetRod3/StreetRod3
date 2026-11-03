shader_type canvas_item;

// A color print from the 1970s after years in a wallet: soft focus, washed-out color,
// blacks that have gone milky, whites gone cream, and the magenta cast of a faded dye.
uniform float softness = 1.1;
uniform float color_left = 0.84;
uniform vec3 faded_black = vec3(0.14, 0.11, 0.12);
uniform vec3 faded_white = vec3(0.95, 0.92, 0.87);
uniform vec3 dye_cast = vec3(1.04, 0.97, 0.97);
uniform float grain = 0.022;
uniform float vignette = 0.2;

float noise(vec2 at) {
	return fract(sin(dot(at, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	vec2 step_size = TEXTURE_PIXEL_SIZE * softness;
	vec3 color = texture(TEXTURE, UV).rgb * 0.4;
	color += texture(TEXTURE, UV + step_size * vec2(1.0, 1.0)).rgb * 0.15;
	color += texture(TEXTURE, UV + step_size * vec2(-1.0, 1.0)).rgb * 0.15;
	color += texture(TEXTURE, UV + step_size * vec2(1.0, -1.0)).rgb * 0.15;
	color += texture(TEXTURE, UV + step_size * vec2(-1.0, -1.0)).rgb * 0.15;

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, color_left);
	color = mix(faded_black, faded_white, color) * dye_cast;

	vec2 from_center = UV - vec2(0.5);
	color *= 1.0 - vignette * smoothstep(0.25, 0.75, length(from_center));
	color += noise(floor(UV / TEXTURE_PIXEL_SIZE)) * grain;
	COLOR = vec4(color, 1.0);
}
