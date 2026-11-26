shader_type canvas_item;
render_mode blend_disabled;

// The 3D view, redrawn as a grid of characters. A cell's brightness picks the glyph
// and the glyph is tinted with that cell's color, so a red car stays red and the sky
// stays blue. Menus and the driving HUD are drawn later, on a higher layer, and are
// left alone.
// source_mode 0 reads the screen (the main view). 1 uses flat_ink, for the settings
// preview. 2 reads this item's own texture, for the garage, whose view is a viewport
// of its own rather than the window.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D glyph_tex : filter_nearest, repeat_disable;
uniform vec2 cell_px = vec2(4.0, 8.0);
uniform float glyph_count = 9.0;
uniform float source_mode = 0.0;
uniform vec4 flat_ink : source_color = vec4(1.0);

void fragment() {
	// One character grid, in screen pixels, for the window and for the garage.
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 pixel = SCREEN_UV * screen_px;
	vec2 origin = floor(pixel / cell_px) * cell_px;
	// Four taps inside the cell, so a thin edge sliding across the grid does not
	// swap the character every frame.
	vec2 p0 = origin + cell_px * vec2(0.35, 0.35);
	vec2 p1 = origin + cell_px * vec2(0.65, 0.35);
	vec2 p2 = origin + cell_px * vec2(0.35, 0.65);
	vec2 p3 = origin + cell_px * vec2(0.65, 0.65);
	vec3 rgb = flat_ink.rgb;
	if (source_mode < 0.5) {
		rgb = texture(screen_tex, clamp(p0 / screen_px, vec2(0.0), vec2(1.0))).rgb;
		rgb += texture(screen_tex, clamp(p1 / screen_px, vec2(0.0), vec2(1.0))).rgb;
		rgb += texture(screen_tex, clamp(p2 / screen_px, vec2(0.0), vec2(1.0))).rgb;
		rgb += texture(screen_tex, clamp(p3 / screen_px, vec2(0.0), vec2(1.0))).rgb;
		rgb *= 0.25;
	} else if (source_mode > 1.5) {
		vec2 uv_dx = dFdx(UV);
		vec2 uv_dy = dFdy(UV);
		vec2 d0 = p0 - pixel;
		vec2 d1 = p1 - pixel;
		vec2 d2 = p2 - pixel;
		vec2 d3 = p3 - pixel;
		rgb = texture(TEXTURE, clamp(UV + uv_dx * d0.x + uv_dy * d0.y, vec2(0.0), vec2(1.0))).rgb;
		rgb += texture(TEXTURE, clamp(UV + uv_dx * d1.x + uv_dy * d1.y, vec2(0.0), vec2(1.0))).rgb;
		rgb += texture(TEXTURE, clamp(UV + uv_dx * d2.x + uv_dy * d2.y, vec2(0.0), vec2(1.0))).rgb;
		rgb += texture(TEXTURE, clamp(UV + uv_dx * d3.x + uv_dy * d3.y, vec2(0.0), vec2(1.0))).rgb;
		rgb *= 0.25;
	}
	float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	// Pull the dark end of the ramp up a little, so asphalt is not all spaces.
	lum = pow(clamp(lum, 0.0, 1.0), 0.8);
	float index = floor(min(lum, 0.999) * glyph_count);
	float peak = max(rgb.r, max(rgb.g, rgb.b));
	vec3 ink = rgb;
	if (peak > 0.03 && peak < 0.5) {
		ink *= 0.5 / peak;
	}
	vec2 atlas_px = vec2(textureSize(glyph_tex, 0));
	float glyph_w = atlas_px.x / glyph_count;
	vec2 in_cell = pixel - origin;
	// Whole pixels inside the cell. The raw coordinate is a pixel center, and
	// stepping the bitmap from that center lined the same mark up in every cell.
	float ix = clamp(floor(in_cell.x), 0.0, cell_px.x - 1.0);
	float iy = clamp(floor(in_cell.y), 0.0, cell_px.y - 1.0);
	// Dot and colon are a single column of marks. On a flat wall those marks
	// sit on the same pixels and the gaps join into lines. Slide those two
	// glyphs around inside the cell. A full-width stroke stays where it is.
	float scatter = step(0.5, index) * step(index, 2.5);
	if (scatter > 0.5) {
		vec2 cell = floor(pixel / cell_px);
		float hx = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
		float hy = fract(sin(dot(cell, vec2(269.5, 183.3))) * 43758.5453);
		ix = mod(ix + floor(hx * cell_px.x), cell_px.x);
		iy = mod(iy + floor(hy * cell_px.y), cell_px.y);
	}
	float tx = ix / max(cell_px.x - 1.0, 1.0);
	float ty = iy / max(cell_px.y - 1.0, 1.0);
	float lx = clamp(floor(mix(1.0, max(glyph_w - 2.0, 1.0), tx)), 0.0, glyph_w - 1.0);
	float ly = clamp(floor(mix(1.0, max(atlas_px.y - 2.0, 1.0), ty)), 0.0, atlas_px.y - 1.0);
	vec2 sample_px = vec2(index * glyph_w + lx + 0.5, ly + 0.5);
	float mask = texture(glyph_tex, sample_px / atlas_px).r;
	COLOR = vec4(ink * mask, 1.0);
}
