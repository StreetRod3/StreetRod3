extends Node
## Gives the scene it is in a look after Street Rod 2, at full resolution: every material's
## color is snapped to the 64 colors an EGA card can show, lighting falls in flat bands
## (lit and shaded) instead of smooth gradients, and retro_outline.gdshader draws dark
## outlines round everything near the camera.
##
## Materials loaded from files (car models, the scene's own sub-resources) are copied
## before they are changed, so other scenes that share them keep their normal look.
## Materials made in code belong to this scene and are changed in place, so the code
## that made them can go on changing them, as car repainting does. Meshes added later,
## such as the cars and the track, are converted as they arrive.
##
## A material can choose its own retro color with a "retro_color" meta, for a color that
## would snap to the same EGA color as something it must stand apart from (the track's
## terrain against its road). Transparent materials (smoke, glass) are left alone. Track sides colored per vertex
## get the flat lighting but keep their vertex colors.

const _PAINT_SHADER := preload("res://shaders/car_paint_mask.gdshader")
const _PAINT_RETRO_SHADER := preload("res://shaders/car_paint_retro.gdshader")
const _OUTLINE_SHADER := preload("res://shaders/retro_outline.gdshader")

## Original material -> its converted version, so each is converted once.
var _converted: Dictionary[Material, Material] = {}
## Every converted material, so one is never converted twice.
var _retro: Dictionary[Material, bool] = {}


func _ready() -> void:
	var root := get_parent()
	_convert_tree(root)
	get_tree().node_added.connect(_on_node_added)
	_add_outlines()


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


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
	if geometry.material_override != null:
		geometry.material_override = _convert(geometry.material_override)
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
		if base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			retro = _own(mat)
			_make_retro_base(retro as BaseMaterial3D)
	elif mat is ShaderMaterial and (mat as ShaderMaterial).shader == _PAINT_SHADER:
		retro = _own(mat)
		(retro as ShaderMaterial).shader = _PAINT_RETRO_SHADER
	_converted[mat] = retro
	_retro[retro] = true
	return retro


## The material itself if code made it for this scene; a copy if it came from a file.
func _own(mat: Material) -> Material:
	if mat.resource_path.is_empty():
		return mat
	return mat.duplicate()


func _make_retro_base(mat: BaseMaterial3D) -> void:
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


## The nearest of the 64 EGA colors; alpha is kept. As in retro_palette.gdshaderinc, a
## dark color that would round to black is brightened first, hue kept, so dark asphalt
## becomes dark gray and only near-black stays black.
static func snap_color(color: Color) -> Color:
	var c := Color(clampf(color.r, 0.0, 1.0), clampf(color.g, 0.0, 1.0), clampf(color.b, 0.0, 1.0))
	var strongest := maxf(c.r, maxf(c.g, c.b))
	if strongest > 0.03 and strongest < 1.0 / 6.0:
		c *= (1.0 / 3.0) / strongest
	return Color(roundf(c.r * 3.0) / 3.0, roundf(c.g * 3.0) / 3.0, roundf(c.b * 3.0) / 3.0, color.a)


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
