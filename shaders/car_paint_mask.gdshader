shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.42;
uniform float use_orm : hint_range(0.0, 1.0) = 0.0;
// A clear coat over the paint (not over the trim, glass or interior), for cars whose
// .car file gives model.paint.clearcoat: a second, glossier highlight on top.
uniform float clearcoat : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.1;
uniform float use_normal : hint_range(0.0, 1.0) = 0.0;
uniform float normal_scale = 1.0;
// An EGA-style checkerboard dither in the paint, like the 1956 Corvette's texture, for
// cars whose .car file sets model.dither_cell: the size of one square in meters (0
// leaves it off). The paint comes in three flat shades by which way the surface faces:
// its own color on the tops and the shoulders, a solid darker shade down the sides, and
// darker again underneath. Where one shade gives way to the next there is a band of
// squares of the two on a checkerboard rather than a blend.
uniform float dither_cell = 0.0;
// How much darker each shade is than the one above it.
uniform float dither_depth : hint_range(0.0, 0.5) = 0.3;
// Where the shades change, in how far the surface's normal tips up (1) or down (-1).
uniform float dither_upper = 0.25;
uniform float dither_lower = -0.35;
// Half the width of a band of squares, in the same terms.
uniform float dither_band : hint_range(0.0, 0.5) = 0.12;
// The mesh's own coordinates to the car's (meters, Y up), set per mesh by
// car_vehicle_visual.gd, so the squares and shades don't depend on how the model was built.
uniform mat4 car_from_mesh = mat4(1.0);
// A second paint zone, the side coves of the 1956-62 Corvettes, for cars whose .car file
// gives model.cove. A face is in it if it looks out to the side, lies at least
// cove_min_x from the car's middle, and falls inside cove_outline, a side-view outline in
// the car's (z, y), the same on both sides. cove_color's alpha is 0 until the cove is
// painted on its own, and then the cove takes the body's color.
uniform vec4 cove_color = vec4(0.0);
uniform int cove_count = 0;
uniform vec2 cove_outline[24];
uniform float cove_min_x = 0.0;
// A second paint marked in the texture, for cars whose .car file gives model.accent (the
// 1963 C10's grille and its frame, bumpers and tailgate lettering): of the paint's texels
// (alpha 1), the body's are grey (blue as bright as red) and the accent's have no blue.
// The paint's shade is then the texel's red.
uniform float use_accent = 0.0;
uniform vec4 accent_color : source_color = vec4(1.0);
// The finish of the accent or cove, chosen in the garage's paint menu: 0 paint (the
// body's finish), 1 vinyl (satin, no clear coat, a fine leather grain in the light),
// 2 matte (flat, no clear coat).
uniform int accent_finish = 0;
const float VINYL_ROUGHNESS = 0.55;
const float MATTE_ROUGHNESS = 0.78;
// Vinyl grain: cells this many to the meter, tipping the surface by up to this much.
const float GRAIN_SCALE = 450.0;
const float GRAIN_DEPTH = 0.18;
// The body paint's finish, chosen in the garage's paint menu (CarFile.PAINT_FINISHES): 0
// gloss (the car file's own model.paint), 1 matte, 2 primer, 3 metallic, 4 candy, 5 pearl.
// It covers the paint, and an accent or cove whose finish is "paint".
uniform int paint_finish = 0;
// Each finish's metallic, roughness, clear coat and clear coat roughness (gloss's are
// the car file's, from the uniforms above).
const vec4 FINISHES[6] = vec4[6](
	vec4(0.0),
	vec4(0.0, 0.72, 0.0, 0.0),
	vec4(0.0, 0.95, 0.0, 0.0),
	vec4(0.3, 0.38, 1.0, 0.05),
	vec4(0.35, 0.22, 1.0, 0.02),
	vec4(0.25, 0.3, 1.0, 0.04)
);
// Metal flake under the clear coat: cells this many to the meter, of which this share
// hold a flake, tipped its own way by up to FLAKE_DEPTH and a little lighter, so it
// glints (metallic, candy, pearl). It fades out where a flake is smaller than a pixel, so
// from afar the finish is smooth rather than shimmering.
const float FLAKE_SCALE = 650.0;
const float FLAKE_SHARE = 0.14;
const float FLAKE_DEPTH[6] = float[6](0.0, 0.0, 0.0, 0.6, 0.45, 0.25);
// Pearl: how far round the color wheel the paint turns where it is seen edge-on, in radians.
const float PEARL_TURN = 0.9;

varying vec3 model_pos;
varying vec3 model_normal;

void vertex() {
	model_pos = (car_from_mesh * vec4(VERTEX, 1.0)).xyz;
	model_normal = mat3(car_from_mesh) * NORMAL;
}

float paint_tone() {
	vec3 n = normalize(model_normal);
	vec3 a = abs(n);
	// The squares lie on whichever model plane the surface faces most.
	vec2 p = a.x > a.y && a.x > a.z ? model_pos.zy : (a.y > a.z ? model_pos.xz : model_pos.xy);
	p /= dither_cell;
	ivec2 c = ivec2(floor(p));
	// 0 on the tops, 1 down the sides, 2 underneath; a band sits on each change.
	float level = step(n.y, dither_upper) + step(n.y, dither_lower);
	float near_upper = step(abs(n.y - dither_upper), dither_band);
	float near_lower = step(abs(n.y - dither_lower), dither_band);
	float band_top = near_upper > 0.0 ? 0.0 : 1.0;
	bool odd = ((c.x + c.y) & 1) == 1;
	float dithered = band_top + (odd ? 1.0 : 0.0);
	// Far off, where a square is smaller than a pixel, blend instead of shimmering.
	float fine = smoothstep(0.35, 0.7, length(fwidth(p)));
	dithered = mix(dithered, band_top + 0.5, fine);
	if (near_upper + near_lower > 0.0) {
		level = dithered;
	}
	return 1.0 - dither_depth * level;
}

bool in_cove() {
	if (cove_count < 3 || cove_color.a < 0.5 || abs(model_pos.x) < cove_min_x) {
		return false;
	}
	vec3 n = normalize(model_normal);
	if (n.x * sign(model_pos.x) < 0.3) {
		return false;
	}
	vec2 p = model_pos.zy;
	bool inside = false;
	int j = cove_count - 1;
	for (int i = 0; i < cove_count; i++) {
		vec2 a = cove_outline[i];
		vec2 b = cove_outline[j];
		if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
			inside = !inside;
		}
		j = i;
	}
	return inside;
}

float grain_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// Smooth value noise, 0 to 1.
float grain_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(grain_hash(i), grain_hash(i + vec3(1, 0, 0)), f.x), mix(grain_hash(i + vec3(0, 1, 0)), grain_hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(grain_hash(i + vec3(0, 0, 1)), grain_hash(i + vec3(1, 0, 1)), f.x), mix(grain_hash(i + vec3(0, 1, 1)), grain_hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

// Turns a color round the color wheel (about the grey axis).
vec3 hue_turn(vec3 c, float a) {
	vec3 k = vec3(0.57735);
	float co = cos(a);
	return c * co + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - co);
}

// The paint's color in the body's finish; facing is 1 where the surface faces the eye, 0
// edge-on.
vec3 finish_color(vec3 c, float facing) {
	if (paint_finish == 2) {
		// Primer: chalky, a little greyed and lightened, and blotchy where it was sanded.
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		c = mix(mix(vec3(lum), c, 0.7), vec3(0.6), 0.12);
		return c * (0.92 + 0.16 * grain_noise(model_pos * 5.0));
	}
	if (paint_finish == 3) {
		// Metallic: the flakes throw light back where the paint faces the eye, so it is
		// lighter there and darker edge-on (the "flop").
		vec3 face = min(c * 1.7 + vec3(0.07), vec3(1.0));
		return mix(c * 0.45, face, facing);
	}
	if (paint_finish == 4) {
		// Candy: a richer, brighter color where it faces the eye, deepening toward the
		// edges as through a thicker tinted coat.
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		vec3 rich = clamp(vec3(lum) + (c - vec3(lum)) * 1.5, vec3(0.0), vec3(1.0));
		vec3 face = min(rich * 1.3, vec3(1.0));
		return mix(rich * rich * 0.45, face, pow(facing, 1.2));
	}
	if (paint_finish == 5) {
		// Pearl: a paler, turned color sheens over it edge-on.
		vec3 sheen = mix(max(hue_turn(c, PEARL_TURN), vec3(0.0)), vec3(1.0), 0.3);
		return mix(c, sheen, pow(1.0 - facing, 2.0) * 0.85);
	}
	return c;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	bool cove = in_cove();
	vec3 paint = cove ? cove_color.rgb : paint_color.rgb;
	vec3 painted = paint * tex.rgb;
	// How much of this texel is the accent (or cove), for its finish.
	float zone = cove ? 1.0 : 0.0;
	if (use_accent > 0.5) {
		float accent = clamp(1.0 - tex.b / max(tex.r, 0.004), 0.0, 1.0);
		painted = mix(paint, accent_color.rgb, accent) * tex.r;
		zone = max(zone, accent);
	}
	// The accent's or cove's share of the texel where it has a finish of its own; the
	// rest of the paint takes the body's.
	float own = accent_finish > 0 ? zone : 0.0;
	zone = own * tex.a;
	float body = paint_finish > 0 ? tex.a * (1.0 - own) : 0.0;
	if (dither_cell > 0.0) {
		painted *= paint_tone();
	}
	vec4 finish = FINISHES[paint_finish];
	// This texel's flake, if it has one: 1 in a flake, faded out with distance.
	float flake = 0.0;
	vec3 flake_cell = vec3(0.0);
	if (FLAKE_DEPTH[paint_finish] > 0.0 && body > 0.0) {
		vec3 p = model_pos * FLAKE_SCALE;
		flake_cell = floor(p);
		float fade = 1.0 - smoothstep(0.5, 1.0, length(fwidth(p)));
		// A round speck in its cell, off center by the cell's own amount.
		vec3 off = vec3(grain_hash(flake_cell + 5.9), grain_hash(flake_cell + 9.4), grain_hash(flake_cell + 2.6)) * 0.4 - 0.2;
		float speck = step(length(fract(p) - 0.5 - off), 0.3);
		flake = step(1.0 - FLAKE_SHARE, grain_hash(flake_cell + 3.3)) * speck * fade * body;
	}
	if (paint_finish > 0) {
		float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
		painted = mix(painted, finish_color(painted, facing), 1.0 - own);
		painted = mix(painted, min(painted * 1.6 + vec3(0.05), vec3(1.0)), flake);
	}
	ALBEDO = mix(tex.rgb, painted, tex.a);
	float metal;
	float rough;
	if (use_orm > 0.5) {
		vec3 orm = texture(orm_tex, UV).rgb;
		metal = mix(orm.b, metallic, tex.a);
		rough = mix(orm.g, roughness, tex.a);
		AO = orm.r;
	} else {
		metal = mix(0.05, metallic, tex.a);
		rough = mix(0.82, roughness, tex.a);
	}
	metal = mix(metal, finish.x, body);
	rough = mix(rough, finish.y, body);
	METALLIC = mix(metal, 0.0, zone);
	ROUGHNESS = mix(rough, accent_finish == 1 ? VINYL_ROUGHNESS : MATTE_ROUGHNESS, zone);
	CLEARCOAT = (paint_finish > 0 ? finish.z : clearcoat) * tex.a * (1.0 - zone);
	CLEARCOAT_ROUGHNESS = paint_finish > 0 ? finish.w : clearcoat_roughness;
	// Primer has hardly any shine at all.
	SPECULAR = mix(0.5, 0.2, paint_finish == 2 ? body : 0.0);
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (flake > 0.0) {
		// Each flake is a cell fixed to the car, tipped its own way.
		vec3 g = vec3(grain_hash(flake_cell), grain_hash(flake_cell + 7.1), grain_hash(flake_cell + 13.7)) - 0.5;
		g = mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * (inverse(mat3(car_from_mesh)) * g));
		g -= dot(g, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL + g * (2.0 * FLAKE_DEPTH[paint_finish] * flake));
	}
	if (accent_finish == 1 && zone > 0.0 && use_normal < 0.5) {
		// Vinyl's grain, fixed to the car, fading out where a cell is smaller than a pixel;
		// a material with its own normal map (the Challenger's vinyl top) has its own grain.
		vec3 p = model_pos * GRAIN_SCALE;
		float fade = 1.0 - smoothstep(0.4, 1.0, length(fwidth(p)));
		vec3 g = vec3(grain_noise(p), grain_noise(p + 17.3), grain_noise(p + 41.9)) - 0.5;
		g = mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * (inverse(mat3(car_from_mesh)) * g));
		g -= dot(g, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL + g * (2.0 * GRAIN_DEPTH * zone * fade));
	}
}
