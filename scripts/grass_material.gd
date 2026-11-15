extends RefCounted

## The grass ground under the race tracks and the cruise. Poliigon GrassPatchyGround 4585 at 2K
## (reference/tracks/grass). It is mapped from above in world space, so any ground mesh takes it
## without UVs of its own, and one tile covers `TILE_M` meters whatever the mesh's size.

const TILE_M := 2.0

const _ALBEDO := "res://assets/textures/grass/Poliigon_GrassPatchyGround_4585_BaseColor.jpg"
const _NORMAL := "res://assets/textures/grass/Poliigon_GrassPatchyGround_4585_Normal.png"
const _ROUGHNESS := "res://assets/textures/grass/Poliigon_GrassPatchyGround_4585_Roughness.jpg"

static var _shared: StandardMaterial3D = null


## One material for every grass ground, made on first use.
static func get_material() -> StandardMaterial3D:
	if _shared != null:
		return _shared
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(_ALBEDO) as Texture2D
	mat.normal_enabled = true
	mat.normal_texture = load(_NORMAL) as Texture2D
	mat.roughness = 1.0
	mat.roughness_texture = load(_ROUGHNESS) as Texture2D
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.metallic = 0.0
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 8.0
	mat.uv1_scale = Vector3.ONE / TILE_M
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_shared = mat
	return mat
