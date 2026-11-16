// Tree crowns as leaf cards. Adapted from tree_leaves.gdshader in PixelageGames' "Godot 3D
// PixelArt Vegetation Demo" (https://pixelagegames.itch.io/3d-pixelart-vegetation),
// Copyright (c) 2026 Eduardo Schildt, MIT License; see assets/textures/leaves/LICENSE-pixelage.txt.
//
// Each card is four vertices at one point on a crown, with UVs at the four corners. The vertex
// shader spreads them out in view space, so every card faces the camera, turned by the angle in
// UV2.x so the leaves don't all lie the same way. NORMAL is the crown's own, so a crown is lit as
// one round lump, in `light_steps` hard bands with a rim of light on its sunny edge. Changed from
// the original: view-space corners (crowns are scaled unevenly), per-card turn, no wind.
shader_type spatial;
render_mode specular_disabled, cull_back, skip_vertex_transform;

uniform vec4 color : source_color = vec4(0.3647059, 0.65882355, 0.1764706, 1.0);
uniform sampler2D alpha : filter_linear_mipmap, repeat_disable;
// Half the width of a card, in meters.
uniform float card_half_m = 0.45;
uniform float light_steps = 5.0;

void vertex() {
	vec2 corner = UV * 2.0 - 1.0;
	float turn = UV2.x;
	vec2 spread = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * corner;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz + vec3(spread * card_half_m, 0.0);
	NORMAL = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = texture(alpha, UV).r;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	lit = ceil(lit * light_steps) / light_steps;
	DIFFUSE_LIGHT += lit * (LIGHT_COLOR / PI) * ATTENUATION;

	float rim = 1.0 - dot(NORMAL, VIEW);
	rim *= lit;
	rim = round(rim * light_steps) / light_steps;
	rim = rim * rim;
	DIFFUSE_LIGHT += rim * ATTENUATION * LIGHT_COLOR / PI;
}
