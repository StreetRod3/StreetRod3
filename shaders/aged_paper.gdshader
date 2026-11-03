shader_type canvas_item;

// Everything already drawn on the license, aged by a wear map: the paper yellows and
// stains, the ink fades, and rubbed places lose their print down to bare paper.
// The map's red is staining, green is rubbing, and blue is paper grain around 0.5.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D wear_map : filter_linear;
uniform vec2 card_size = vec2(930.0, 622.0);
uniform float corner_radius = 12.0;
uniform vec3 stain_color = vec3(0.78, 0.68, 0.5);
uniform float stain_amount = 0.7;
uniform vec3 yellowed = vec3(0.985, 0.97, 0.91);
uniform vec3 faded_ink = vec3(0.09, 0.09, 0.1);
uniform vec3 bare_paper = vec3(0.86, 0.82, 0.71);
uniform float rub_amount = 0.75;
uniform float grain_amount = 0.1;

void fragment() {
	vec3 wear = texture(wear_map, UV).rgb;
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	color = mix(faded_ink, vec3(1.0), color) * yellowed;
	color *= mix(vec3(1.0), stain_color, wear.r * stain_amount);
	color = mix(color, bare_paper * mix(vec3(1.0), stain_color, wear.r * 0.5), wear.g * rub_amount);
	color *= 1.0 + (wear.b - 0.5) * grain_amount * 2.0;

	// The card's rounded corners, so nothing beyond them is touched.
	vec2 pixel = UV * card_size;
	vec2 inside = abs(pixel - card_size * 0.5) - (card_size * 0.5 - vec2(corner_radius));
	float outside = length(max(inside, vec2(0.0))) + min(max(inside.x, inside.y), 0.0) - corner_radius;
	COLOR = vec4(color, clamp(0.5 - outside, 0.0, 1.0));
}
