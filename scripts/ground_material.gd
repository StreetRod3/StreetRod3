extends RefCounted

## Textured ground: the grass under the race tracks and the city, the asphalt of their roads, and
## the concrete of the Aqueduct and the street drag's shoulders.
## Each is mapped from above in world space, so any ground or road mesh takes it without UVs of
## its own, and one tile covers the same ground whatever the mesh's size. Sources and notes are
## in reference/tracks/grass, reference/tracks/CityStreetAsphalt and reference/tracks/concrete.md.

## Poliigon GrassPatchyGround 4585 at 2K.
const GRASS_TILE_M := 2.0
## Poliigon CityStreetAsphaltGenericClean001 at 2K. Its roughness map is the download's gloss
## map inverted.
const ASPHALT_TILE_M := 1.0
## Mulholland's road is black in Street Rod 2, so its asphalt is darkened this much.
const DARK_ASPHALT_TINT := Color(0.3, 0.3, 0.3, 1)
## A photo from magnific.com made to tile by tools/make_concrete_texture.py. It has no normal or
## roughness map. It is bright, with a mean of 0.651 in linear light, so a tint sets its shade.
const CONCRETE_TILE_M := 2.0
const CONCRETE_LINEAR_MEAN := 0.651
## The street drag's shoulders: lighter than the asphalt beside them.
const SHOULDER_TINT := Color(0.6, 0.6, 0.58, 1)

const _GRASS := "res://assets/textures/grass/Poliigon_GrassPatchyGround_4585_"
const _ASPHALT := "res://assets/textures/asphalt/CityStreetAsphaltGenericClean001_"
const _CONCRETE := "res://assets/textures/concrete/old-grunge-concrete.jpg"

static var _grass: StandardMaterial3D = null
static var _asphalt: StandardMaterial3D = null
static var _dark_asphalt: StandardMaterial3D = null
static var _shoulder: StandardMaterial3D = null
static var _vertex_concrete: StandardMaterial3D = null


## One material for every grass ground, made on first use.
static func grass() -> StandardMaterial3D:
	if _grass == null:
		_grass = _make(_GRASS + "BaseColor.jpg", _GRASS + "Normal.png", _GRASS + "Roughness.jpg", GRASS_TILE_M)
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
