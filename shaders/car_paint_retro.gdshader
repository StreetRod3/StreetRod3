shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// car_paint_mask.gdshader for retro_look.gd: retro palette colors, lit in flat bands dithered
// where they meet (retro_light.gdshaderinc).

#define RETRO
#include "res://shaders/car_paint.gdshaderinc"
#include "res://shaders/retro_light.gdshaderinc"
