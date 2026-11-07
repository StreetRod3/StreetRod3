shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

// car_paint_mask.gdshader for retro_look.gd: EGA colors, lit in flat bands.

#define RETRO
#include "res://shaders/car_paint.gdshaderinc"
