extends RefCounted

## Textured ground: grass under the race tracks, the city and Mulholland; Mulholland's dirt and
## gravel; the asphalt of the roads; the Aqueduct's concrete; and the street drag's concrete
## shoulders. Each is mapped from above in world space, so any ground or road mesh takes it without
## UVs of its own, and one tile covers the same ground whatever the mesh's size. Sources and notes
## are in reference/tracks/ (grass, CityStreetAsphalt, dirt, rockytrail, CA_ConcreteRoad,
## concrete.md), and
## docs/ground-textures.md lists them and the settings below.

## Poliigon GrassPatchyGround 4585 at 2K.
const GRASS_TILE_M := 2.0
## How far the grass's normal map tilts the surface; 1 is the map as made, which looked flat.
const GRASS_NORMAL_SCALE := 1.8
## The grass's occlusion map is raised to this power: as made it averages 0.97 and barely shows.
const GRASS_AO_STRENGTH := 4.0
## Large-scale patches on the grass (shaders/ground_common.gdshaderinc), so a field doesn't read as
## one even sheet: their size in meters, how much they brighten and darken, and the dry color the
## second set of patches leans toward (a multiplier, in linear light) and how far.
const GRASS_MACRO_SIZE_M := 18.0
const GRASS_MACRO_BRIGHT := 0.25
const GRASS_MACRO_TINT := Vector3(1.15, 1.05, 0.6)
const GRASS_MACRO_TINT_AMOUNT := 0.6
## Specular of the grass, dirt and gravel. Godot scales the grazing-angle reflection with it too,
## and at the default 0.5 far-off ground turned pale with the sky in it.
const GROUND_SPECULAR := 0.1
## Poliigon CityStreetAsphaltGenericClean001 at 2K. Its roughness map is the download's gloss
## map inverted.
const ASPHALT_TILE_M := 1.0
## As the grass's: normal map strength, occlusion power, and large-scale patches, here lighter
## worn patches and darker fresh ones.
const ASPHALT_NORMAL_SCALE := 1.4
const ASPHALT_AO_STRENGTH := 2.5
const ASPHALT_MACRO_SIZE_M := 12.0
const ASPHALT_MACRO_BRIGHT := 0.2
const ASPHALT_MACRO_TINT := Vector3(1.12, 1.1, 1.06)
const ASPHALT_MACRO_TINT_AMOUNT := 0.5
## How much the grass's and asphalt's occlusion darkens sunlight too, not only ambient light.
const GROUND_AO_LIGHT_AFFECT := 0.5
## Poliigon GroundDirtWeedsPatchy004 at 2K, for Mulholland's hillsides. Its roughness map is the
## download's gloss map inverted.
const DIRT_TILE_M := 2.0
## The dirt takes this much of the hue of Street Rod 2's flat brown hills, `DIRT_OLD_COLOR`, at the
## texture's own brightness (that brown is far lighter), and is then darkened to `DIRT_DARKEN`. The
## texture's mean is `DIRT_MEAN`, in linear light.
const DIRT_TINT_AMOUNT := 0.35
const DIRT_DARKEN := 0.8
const DIRT_OLD_COLOR := Color(0.56, 0.3, 0.07, 1)
const DIRT_MEAN := Vector3(0.1411, 0.0831, 0.0478)
## Mulholland's road is black in Street Rod 2, so its asphalt is darkened this much.
const DARK_ASPHALT_TINT := Color(0.3, 0.3, 0.3, 1)
## A photo from magnific.com made to tile by tools/make_concrete_texture.py. It has no normal or
## roughness map. It is bright, with a mean of 0.651 in linear light, so a tint sets its shade.
const CONCRETE_TILE_M := 2.0
const CONCRETE_LINEAR_MEAN := 0.651
## Leartes Cosmos CA Concrete Road, 2048 square despite the "4096" in its file names, for the
## Aqueduct. Its "R" map, and the green of its ORM map, average 0.1 and drew glassy concrete; its "G"
## map is the same inverted, and that is used as the roughness. One tile at 2 m repeated in bands.
const CA_CONCRETE_TILE_M := 4.0
## The texture's mean color in linear light, measured from the file. It is darker than the old
## photo's `CONCRETE_LINEAR_MEAN`, which the Aqueduct's vertex colors were worked out for
## (track_sides.gd), so the color is multiplied up to that mean.
const CA_CONCRETE_LINEAR_MEAN := 0.257
const CA_CONCRETE_AO_LIGHT_AFFECT := 0.5
## The street drag's shoulders: lighter than the asphalt beside them.
const SHOULDER_TINT := Color(0.6, 0.6, 0.58, 1)
## Gravel: Mulholland's verge and its gravel stretches. Poly Haven Rocky Trail at 2K, whose
## photo covers 2 m; its ARM map holds roughness in green. `GRAVEL_TINT` multiplies its color.
const GRAVEL_TINT := Color(1.0, 1.0, 1.0, 1)
const GRAVEL_TILE_M := 2.0

const _GRASS := "res://assets/textures/grass/Poliigon_GrassPatchyGround_4585_"
const _GRASS_AO := _GRASS + "AmbientOcclusion.jpg"
const _ASPHALT := "res://assets/textures/asphalt/CityStreetAsphaltGenericClean001_"
const _ASPHALT_AO := _ASPHALT + "AO_2K.jpg"
const _CONCRETE := "res://assets/textures/concrete/old-grunge-concrete.jpg"
const _CA_CONCRETE := "res://assets/textures/concrete/T_CA_ConcreteRoad_4096_"
const _GRAVEL := "res://assets/textures/gravel/rocky_trail_"
const _DIRT := "res://assets/textures/dirt/GroundDirtWeedsPatchy004_"
const _VERTEX_GROUND_SHADER := preload("res://shaders/vertex_ground.gdshader")
const _GROUND_SHADER := preload("res://shaders/ground.gdshader")
const _GROUND_TWO_SIDED_SHADER := preload("res://shaders/ground_two_sided.gdshader")

static var _grass: ShaderMaterial = null
static var _asphalt: ShaderMaterial = null
static var _two_sided_asphalt: ShaderMaterial = null
static var _dark_asphalt: ShaderMaterial = null
static var _shoulder: StandardMaterial3D = null
static var _vertex_concrete: StandardMaterial3D = null
static var _vertex_ground: ShaderMaterial = null
static var _gravel: StandardMaterial3D = null


## One material for every grass ground, made on first use (shaders/ground.gdshader).
static func grass() -> ShaderMaterial:
	if _grass == null:
		_grass = _make_ground(_GROUND_SHADER, _GRASS + "BaseColor.jpg", _GRASS + "Normal.png",
			_GRASS + "Roughness.jpg", _GRASS_AO, GRASS_TILE_M)
		_grass.set_shader_parameter(&"specular", GROUND_SPECULAR)
		_set_grass_look(_grass, &"normal_scale", &"ao_strength", &"ao_light_affect")
	return _grass


## One material for every road, made on first use (shaders/ground.gdshader).
static func asphalt() -> ShaderMaterial:
	if _asphalt == null:
		_asphalt = _make_asphalt(_GROUND_SHADER)
	return _asphalt


## The asphalt drawn from both sides, for the city's roads.
static func two_sided_asphalt() -> ShaderMaterial:
	if _two_sided_asphalt == null:
		_two_sided_asphalt = _make_asphalt(_GROUND_TWO_SIDED_SHADER)
	return _two_sided_asphalt


## Mulholland's black road.
static func dark_asphalt() -> ShaderMaterial:
	if _dark_asphalt == null:
		_dark_asphalt = asphalt().duplicate() as ShaderMaterial
		_dark_asphalt.set_shader_parameter(&"tint", DARK_ASPHALT_TINT)
	return _dark_asphalt


## The street drag's concrete shoulders.
static func shoulder_concrete() -> StandardMaterial3D:
	if _shoulder == null:
		_shoulder = _make(_CONCRETE, "", "", CONCRETE_TILE_M)
		_shoulder.roughness = 0.9
		_shoulder.albedo_color = SHOULDER_TINT
	return _shoulder


## Concrete shaded by the mesh's vertex colors, for the Aqueduct's channel. A vertex color in
## linear light times `CONCRETE_LINEAR_MEAN` is the shade it comes out.
static func vertex_colored_concrete() -> StandardMaterial3D:
	if _vertex_concrete == null:
		_vertex_concrete = _make(_CA_CONCRETE + "B.png", _CA_CONCRETE + "OpenGL_N.png",
			_CA_CONCRETE + "G.png", CA_CONCRETE_TILE_M)
		_vertex_concrete.ao_enabled = true
		_vertex_concrete.ao_texture = load(_CA_CONCRETE + "AO.png") as Texture2D
		_vertex_concrete.ao_light_affect = CA_CONCRETE_AO_LIGHT_AFFECT
		var gain := CONCRETE_LINEAR_MEAN / CA_CONCRETE_LINEAR_MEAN
		_vertex_concrete.albedo_color = Color(gain, gain, gain).linear_to_srgb()
		_vertex_concrete.vertex_color_use_as_albedo = true
		_vertex_concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _vertex_concrete


## Mulholland's ground beside the road (shaders/vertex_ground.gdshader): grass as much as a
## vertex's alpha, dirt as much as its UV.x, and its flat color for the rest. The grass is the same
## as `grass()`.
static func vertex_ground() -> ShaderMaterial:
	if _vertex_ground == null:
		var mat := ShaderMaterial.new()
		mat.shader = _VERTEX_GROUND_SHADER
		mat.set_shader_parameter(&"grass_albedo", load(_GRASS + "BaseColor.jpg") as Texture2D)
		mat.set_shader_parameter(&"grass_normal", load(_GRASS + "Normal.png") as Texture2D)
		mat.set_shader_parameter(&"grass_roughness", load(_GRASS + "Roughness.jpg") as Texture2D)
		mat.set_shader_parameter(&"grass_tile_m", GRASS_TILE_M)
		mat.set_shader_parameter(&"grass_ao", load(_GRASS_AO) as Texture2D)
		_set_grass_look(mat, &"grass_normal_scale", &"grass_ao_strength", &"grass_ao_light_affect")
		mat.set_shader_parameter(&"dirt_albedo", load(_DIRT + "COL_2K.jpg") as Texture2D)
		mat.set_shader_parameter(&"dirt_normal", load(_DIRT + "NRM_2K.jpg") as Texture2D)
		mat.set_shader_parameter(&"dirt_roughness", load(_DIRT + "ROUGH_2K.jpg") as Texture2D)
		mat.set_shader_parameter(&"dirt_tile_m", DIRT_TILE_M)
		mat.set_shader_parameter(&"dirt_height", load(_DIRT + "HEIGHT_2K.jpg") as Texture2D)
		mat.set_shader_parameter(&"ground_specular", GROUND_SPECULAR)
		mat.set_shader_parameter(&"dirt_tint", dirt_tint())
		mat.set_shader_parameter(&"gravel_color", GRAVEL_TINT)
		mat.set_shader_parameter(&"gravel_tile_m", GRAVEL_TILE_M)
		mat.set_shader_parameter(&"gravel_albedo", load(_GRAVEL + "diff_2k.jpg") as Texture2D)
		mat.set_shader_parameter(&"gravel_normal", load(_GRAVEL + "nor_gl_2k.jpg") as Texture2D)
		mat.set_shader_parameter(&"gravel_arm", load(_GRAVEL + "arm_2k.jpg") as Texture2D)
		mat.set_shader_parameter(&"gravel_height", load(_GRAVEL + "disp_2k.jpg") as Texture2D)
		_vertex_ground = mat
	return _vertex_ground


## Mulholland's gravel stretches. Its verge is the same gravel, in `vertex_ground()`.
static func gravel() -> StandardMaterial3D:
	if _gravel == null:
		_gravel = _make(_GRAVEL + "diff_2k.jpg", _GRAVEL + "nor_gl_2k.jpg", _GRAVEL + "arm_2k.jpg", GRAVEL_TILE_M)
		_gravel.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		_gravel.albedo_color = GRAVEL_TINT
		_gravel.metallic_specular = GROUND_SPECULAR
	return _gravel


## What the dirt's color is multiplied by, per channel in linear light.
static func dirt_tint() -> Vector3:
	var lum := Vector3(0.2126, 0.7152, 0.0722)
	var old_c := DIRT_OLD_COLOR.srgb_to_linear()
	var old := Vector3(old_c.r, old_c.g, old_c.b)
	var hue := old * (DIRT_MEAN.dot(lum) / old.dot(lum))
	return Vector3.ONE.lerp(hue / DIRT_MEAN, DIRT_TINT_AMOUNT) * DIRT_DARKEN


static func _make_asphalt(shader: Shader) -> ShaderMaterial:
	var mat := _make_ground(shader, _ASPHALT + "COL_2K.jpg", _ASPHALT + "NRM_2K.jpg",
		_ASPHALT + "ROUGH_2K.jpg", _ASPHALT_AO, ASPHALT_TILE_M)
	mat.set_shader_parameter(&"normal_scale", ASPHALT_NORMAL_SCALE)
	mat.set_shader_parameter(&"ao_strength", ASPHALT_AO_STRENGTH)
	mat.set_shader_parameter(&"ao_light_affect", GROUND_AO_LIGHT_AFFECT)
	mat.set_shader_parameter(&"macro_size_m", ASPHALT_MACRO_SIZE_M)
	mat.set_shader_parameter(&"macro_bright", ASPHALT_MACRO_BRIGHT)
	mat.set_shader_parameter(&"macro_tint", ASPHALT_MACRO_TINT)
	mat.set_shader_parameter(&"macro_tint_amount", ASPHALT_MACRO_TINT_AMOUNT)
	return mat


## The grass's normal strength, occlusion and large-scale patches, for `grass()` and the grass part
## of `vertex_ground()`, which name the first three parameters differently.
static func _set_grass_look(mat: ShaderMaterial, normal_scale: StringName, ao_strength: StringName,
		ao_light_affect: StringName) -> void:
	mat.set_shader_parameter(normal_scale, GRASS_NORMAL_SCALE)
	mat.set_shader_parameter(ao_strength, GRASS_AO_STRENGTH)
	mat.set_shader_parameter(ao_light_affect, GROUND_AO_LIGHT_AFFECT)
	mat.set_shader_parameter(&"macro_size_m", GRASS_MACRO_SIZE_M)
	mat.set_shader_parameter(&"macro_bright", GRASS_MACRO_BRIGHT)
	mat.set_shader_parameter(&"macro_tint", GRASS_MACRO_TINT)
	mat.set_shader_parameter(&"macro_tint_amount", GRASS_MACRO_TINT_AMOUNT)


## A material on shaders/ground_surface.gdshaderinc: color, normal, roughness (red channel) and
## occlusion maps.
static func _make_ground(shader: Shader, albedo: String, normal: String, roughness: String, ao: String,
		tile_m: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"albedo_tex", load(albedo) as Texture2D)
	mat.set_shader_parameter(&"normal_tex", load(normal) as Texture2D)
	mat.set_shader_parameter(&"roughness_tex", load(roughness) as Texture2D)
	mat.set_shader_parameter(&"ao_tex", load(ao) as Texture2D)
	mat.set_shader_parameter(&"tile_m", tile_m)
	return mat


## `normal` and `roughness` may be empty for a texture without those maps.
static func _make(albedo: String, normal: String, roughness: String, tile_m: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(albedo) as Texture2D
	if not normal.is_empty():
		mat.normal_enabled = true
		mat.normal_texture = load(normal) as Texture2D
	mat.roughness = 1.0
	if not roughness.is_empty():
		mat.roughness_texture = load(roughness) as Texture2D
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.metallic = 0.0
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 8.0
	mat.uv1_scale = Vector3.ONE / tile_m
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat
