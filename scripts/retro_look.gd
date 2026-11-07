extends Node
## Gives the scene it is in a look after Street Rod 2, at full resolution: every material's
## color is snapped to a retro palette (a few steps of lightness and colorfulness, as in
## retro_palette.gdshaderinc), lighting falls in flat bands
## (lit, half lit, shaded) with a checkerboard where they meet (retro_light.gdshaderinc),
## and retro_outline.gdshader draws dark outlines round everything near the camera.
##
## A StandardMaterial3D is replaced by retro_standard.gdshader, which takes its color,
## texture, vertex colors and glow. The original is never changed, so other scenes that
## share it keep their normal look, and while this scene runs, changes that code makes to
## an original (a lamp switched on, a repaint) are copied across. Car paint keeps its own
## shader in a retro build. Materials that use what retro_standard does not (billboards,
## triplanar mapping, front-face culling) keep Godot's toon lighting instead, without
## the dithering. Meshes added later, such as the cars and the track, are converted as
## they arrive, and materials swapped in later are caught by a check twice a second.
##
## A material can choose its own retro color with a "retro_color" meta, for a color that
## would snap to the same palette color as something it must stand apart from (the track's
## terrain against its road). Transparent materials (smoke, glass) are left alone.

const _PAINT_SHADER := preload("res://shaders/car_paint_mask.gdshader")
const _PAINT_RETRO_SHADER := preload("res://shaders/car_paint_retro.gdshader")
const _STANDARD_SHADER := preload("res://shaders/retro_standard.gdshader")
const _STANDARD_DOUBLE_SHADER := preload("res://shaders/retro_standard_double.gdshader")
const _OUTLINE_SHADER := preload("res://shaders/retro_outline.gdshader")
## The palette's steps, as RETRO_LIGHTNESS_STEPS, RETRO_CHROMA_STEPS and RETRO_MAX_CHROMA in
## retro_palette.gdshaderinc.
const LIGHTNESS_STEPS := 10.0
const CHROMA_STEPS := 4.0
const MAX_CHROMA := 0.32
const _FOLLOW_INTERVAL := 0.1
const _RESCAN_INTERVAL := 0.5

## Original material -> its converted version, so each is converted once.
var _converted: Dictionary[Material, Material] = {}
## Every converted material, so one is never converted twice.
var _retro: Dictionary[Material, bool] = {}
## Originals made in code, which that code may go on changing -> their replacements.
var _followed: Dictionary[BaseMaterial3D, ShaderMaterial] = {}
## Instance ids of every geometry seen, to catch materials swapped in later.
var _geometry_ids: Dictionary[int, bool] = {}
var _follow_time := 0.0
var _rescan_time := 0.0


func _ready() -> void:
	_convert_tree(get_parent())
	get_tree().node_added.connect(_on_node_added)
	_add_outlines()


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _process(delta: float) -> void:
	_follow_time += delta
	if _follow_time >= _FOLLOW_INTERVAL:
		_follow_time = 0.0
		for original: BaseMaterial3D in _followed:
			_copy_standard(original, _followed[original])
	_rescan_time += delta
	if _rescan_time >= _RESCAN_INTERVAL:
		_rescan_time = 0.0
		for id: int in _geometry_ids.keys():
			var geometry := instance_from_id(id) as GeometryInstance3D
			if geometry == null:
				_geometry_ids.erase(id)
			elif geometry.is_inside_tree():
				_convert_geometry(geometry)


func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		# Later: materials are often set just after the node enters the tree, and by then
		# the node may also be gone.
		_convert_later.call_deferred(weakref(node))


func _convert_later(ref: WeakRef) -> void:
	var node := ref.get_ref() as Node
	if node != null and node.is_inside_tree():
		_convert_tree(node)


func _convert_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		_convert_geometry(node as GeometryInstance3D)
	for child in node.get_children():
		_convert_tree(child)


func _convert_geometry(geometry: GeometryInstance3D) -> void:
	_geometry_ids[geometry.get_instance_id()] = true
	if geometry.material_override != null:
		var converted := _convert(geometry.material_override)
		if converted != geometry.material_override:
			geometry.material_override = converted
		return
	if geometry is MeshInstance3D:
		var mesh_instance := geometry as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		for i in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.get_surface_override_material(i)
			if mat == null:
				mat = mesh_instance.mesh.surface_get_material(i)
			if mat == null:
				continue
			var retro := _convert(mat)
			if retro != mat:
				mesh_instance.set_surface_override_material(i, retro)
	elif geometry is MultiMeshInstance3D:
		var multi := (geometry as MultiMeshInstance3D).multimesh
		if multi == null or multi.mesh == null or multi.mesh.get_surface_count() != 1:
			return
		var mat := multi.mesh.surface_get_material(0)
		if mat != null:
			var retro := _convert(mat)
			if retro != mat:
				geometry.material_override = retro


func _convert(mat: Material) -> Material:
	if _retro.has(mat):
		return mat
	if _converted.has(mat):
		return _converted[mat]
	var retro: Material = mat
	if mat is BaseMaterial3D:
		var base := mat as BaseMaterial3D
		if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			pass
		elif _fits_retro_standard(base):
			var standard := ShaderMaterial.new()
			standard.shader = _STANDARD_DOUBLE_SHADER if base.cull_mode == BaseMaterial3D.CULL_DISABLED else _STANDARD_SHADER
			_copy_standard(base, standard)
			if base.resource_path.is_empty():
				_followed[base] = standard
			retro = standard
		else:
			retro = _own(mat)
			_make_retro_toon(retro as BaseMaterial3D)
	elif mat is ShaderMaterial and (mat as ShaderMaterial).shader == _PAINT_SHADER:
		retro = _own(mat)
		(retro as ShaderMaterial).shader = _PAINT_RETRO_SHADER
	_converted[mat] = retro
	_retro[retro] = true
	return retro


func _fits_retro_standard(mat: BaseMaterial3D) -> bool:
	return (mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED
		and mat.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED
		and not mat.uv1_triplanar
		and mat.cull_mode != BaseMaterial3D.CULL_FRONT
		and not mat.vertex_color_is_srgb)


## Copies what retro_standard.gdshaderinc draws from a StandardMaterial3D. Only what has
## changed is set, as this runs again and again for materials that code may change.
func _copy_standard(from: BaseMaterial3D, to: ShaderMaterial) -> void:
	var color := from.albedo_color
	if from.has_meta(&"retro_color"):
		color = from.get_meta(&"retro_color") as Color
	_set_param(to, &"albedo_color", color)
	_set_param(to, &"albedo_texture", from.albedo_texture)
	_set_param(to, &"use_vertex_color", from.vertex_color_use_as_albedo)
	_set_param(to, &"uv1_scale", from.uv1_scale)
	_set_param(to, &"uv1_offset", from.uv1_offset)
	var glow := from.emission if from.emission_enabled else Color.BLACK
	_set_param(to, &"emission", glow)
	_set_param(to, &"emission_energy", from.emission_energy_multiplier if from.emission_enabled else 0.0)


func _set_param(mat: ShaderMaterial, param: StringName, value: Variant) -> void:
	if mat.get_shader_parameter(param) != value:
		mat.set_shader_parameter(param, value)


## The material itself if code made it for this scene; a copy if it came from a file.
func _own(mat: Material) -> Material:
	if mat.resource_path.is_empty():
		return mat
	return mat.duplicate()


## For materials retro_standard cannot draw: snapped color and Godot's toon lighting.
func _make_retro_toon(mat: BaseMaterial3D) -> void:
	if mat.has_meta(&"retro_color"):
		mat.albedo_color = mat.get_meta(&"retro_color") as Color
	else:
		mat.albedo_color = snap_color(mat.albedo_color)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.metallic = 0.0


## The retro palette's version of a color; alpha is kept. The same posterizing as
## retro_snap_linear in retro_palette.gdshaderinc: lightness and chroma in OKLab snapped
## to a few steps, hue kept.
static func snap_color(color: Color) -> Color:
	var lab := _linear_to_oklab(color.srgb_to_linear())
	var lightness := roundf(lab.x * LIGHTNESS_STEPS) / LIGHTNESS_STEPS
	if lightness == 0.0 and lab.x > 0.04:
		lightness = 1.0 / LIGHTNESS_STEPS
	var chroma := Vector2(lab.y, lab.z).length()
	var step_index := roundf(sqrt(chroma / MAX_CHROMA) * CHROMA_STEPS) / CHROMA_STEPS
	var hue := Vector2(lab.y, lab.z) / chroma if chroma > 0.0 else Vector2.ZERO
	hue *= step_index * step_index * MAX_CHROMA
	var snapped := _oklab_to_linear(Vector3(lightness, hue.x, hue.y)).linear_to_srgb()
	return Color(clampf(snapped.r, 0.0, 1.0), clampf(snapped.g, 0.0, 1.0), clampf(snapped.b, 0.0, 1.0), color.a)


static func _linear_to_oklab(c: Color) -> Vector3:
	var l := pow(maxf(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b, 0.0), 1.0 / 3.0)
	var m := pow(maxf(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b, 0.0), 1.0 / 3.0)
	var s := pow(maxf(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b, 0.0), 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


static func _oklab_to_linear(lab: Vector3) -> Color:
	var l := pow(lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z, 3.0)
	var m := pow(lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z, 3.0)
	var s := pow(lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z, 3.0)
	return Color(
		clampf(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, 0.0, 1.0),
		clampf(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s, 0.0, 1.0),
		clampf(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s, 0.0, 1.0))


func _add_outlines() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = _OUTLINE_SHADER
	_retro[mat] = true
	var outlines := MeshInstance3D.new()
	outlines.name = "Outlines"
	outlines.mesh = quad
	outlines.material_override = mat
	outlines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad is placed in clip space by its shader, so it must never be culled.
	outlines.extra_cull_margin = 16384.0
	add_child(outlines)
