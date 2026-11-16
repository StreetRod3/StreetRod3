extends RefCounted

## Textured ground: the grass under the race tracks, the city and Mulholland, Mulholland's dirt and gravel, the asphalt of their roads, and
## the concrete of the Aqueduct and the street drag's shoulders.
## Each is mapped from above in world space, so any ground or road mesh takes it without UVs of
## its own, and one tile covers the same ground whatever the mesh's size. Sources and notes are
## in reference/tracks/grass, reference/tracks/CityStreetAsphalt, reference/tracks/dirt and
## reference/tracks/concrete.md.

## Poliigon GrassPatchyGround 4585 at 2K.
const GRASS_TILE_M := 2.0
## Specular of the grass and dirt. Godot scales the grazing-angle reflection with it too, and at
## the default 0.5 far-off ground turned pale with the sky in it.
const GROUND_SPECULAR := 0.1
## Poliigon CityStreetAsphaltGenericClean001 at 2K. Its roughness map is the download's gloss
## map inverted.
const ASPHALT_TILE_M := 1.0
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
## The street drag's shoulders: lighter than the asphalt beside them.
const SHOULDER_TINT := Color(0.6, 0.6, 0.58, 1)
## Gravel: Mulholland's verge and its gravel stretches. Flat for now; a texture goes in
## `_GRAVEL_TEXTURE`, and this color then tints it.
const GRAVEL_COLOR := Color(0.4, 0.4, 0.38, 1)
const GRAVEL_TILE_M := 2.0

const _GRASS := "res://assets/textures/grass/Poliigon_GrassPatchyGround_4585_"
const _ASPHALT := "res://assets/textures/asphalt/CityStreetAsphaltGenericClean001_"
const _CONCRETE := "res://assets/textures/concrete/old-grunge-concrete.jpg"
## Empty until there is a gravel texture.
const _GRAVEL_TEXTURE := ""
const _DIRT := "res://assets/textures/dirt/GroundDirtWeedsPatchy004_"
const _VERTEX_GROUND_SHADER := preload("res://shaders/vertex_ground.gdshader")

static var _grass: StandardMaterial3D = null
static var _asphalt: StandardMaterial3D = null
static var _dark_asphalt: StandardMaterial3D = null
static var _shoulder: StandardMaterial3D = null
static var _vertex_concrete: StandardMaterial3D = null
static var _vertex_ground: ShaderMaterial = null
static var _gravel: StandardMaterial3D = null


## One material for every grass ground, made on first use.
static func grass() -> StandardMaterial3D:
	if _grass == null:
		_grass = _make(_GRASS + "BaseColor.jpg", _GRASS + "Normal.png", _GRASS + "Roughness.jpg", GRASS_TILE_M)
		_grass.metallic_specular = GROUND_SPECULAR
	return _grass


## One material for every road, made on first use.
static func asphalt() -> StandardMaterial3D:
	if _asphalt == null:
		_asphalt = _make(_ASPHALT + "COL_2K.jpg", _ASPHALT + "NRM_2K.jpg", _ASPHALT + "ROUGH_2K.jpg", ASPHALT_TILE_M)
	return _asphalt


## Mulholland's black road.
static func dark_asphalt() -> StandardMaterial3D:
	if _dark_asphalt == null:
		_dark_asphalt = asphalt().duplicate() as StandardMaterial3D
		_dark_asphalt.albedo_color = DARK_ASPHALT_TINT
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
		_vertex_concrete = _make(_CONCRETE, "", "", CONCRETE_TILE_M)
		_vertex_concrete.roughness = 0.95
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
		mat.set_shader_parameter(&"dirt_albedo", load(_DIRT + "COL_2K.jpg") as Texture2D)
		mat.set_shader_parameter(&"dirt_normal", load(_DIRT + "NRM_2K.jpg") as Texture2D)
		mat.set_shader_parameter(&"dirt_roughness", load(_DIRT + "ROUGH_2K.jpg") as Texture2D)
		mat.set_shader_parameter(&"dirt_tile_m", DIRT_TILE_M)
		mat.set_shader_parameter(&"ground_specular", GROUND_SPECULAR)
		mat.set_shader_parameter(&"dirt_tint", dirt_tint())
		mat.set_shader_parameter(&"gravel_color", GRAVEL_COLOR)
		mat.set_shader_parameter(&"gravel_tile_m", GRAVEL_TILE_M)
		if not _GRAVEL_TEXTURE.is_empty():
			mat.set_shader_parameter(&"gravel_albedo", load(_GRAVEL_TEXTURE) as Texture2D)
		_vertex_ground = mat
	return _vertex_ground


## Mulholland's gravel stretches. Its verge is the same gravel, in `vertex_ground()`.
static func gravel() -> StandardMaterial3D:
	if _gravel == null:
		if _GRAVEL_TEXTURE.is_empty():
			_gravel = StandardMaterial3D.new()
		else:
			_gravel = _make(_GRAVEL_TEXTURE, "", "", GRAVEL_TILE_M)
		_gravel.albedo_color = GRAVEL_COLOR
		_gravel.roughness = 0.98
	return _gravel


## What the dirt's color is multiplied by, per channel in linear light.
static func dirt_tint() -> Vector3:
	var lum := Vector3(0.2126, 0.7152, 0.0722)
	var old_c := DIRT_OLD_COLOR.srgb_to_linear()
	var old := Vector3(old_c.r, old_c.g, old_c.b)
	var hue := old * (DIRT_MEAN.dot(lum) / old.dot(lum))
	return Vector3.ONE.lerp(hue / DIRT_MEAN, DIRT_TINT_AMOUNT) * DIRT_DARKEN


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
