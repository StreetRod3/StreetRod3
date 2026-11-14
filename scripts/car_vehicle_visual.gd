extends Node3D

## Shared car visuals (STL body, wheels, materials) used by garage and race.
## Defaults match `garage.tscn` / `car_vehicle_visual.tscn`.

@export var wheel_scale: float = 1
## When set (e.g. opponent), applied to the car body after the STL mesh loads.
@export var body_paint: StandardMaterial3D

#@export var body_node_path: NodePath = NodePath("body")

const _CarFile := preload("res://scripts/car_file.gd")
const _PaintShader := preload("res://shaders/car_paint_mask.gdshader")
## Plain white under a solid body's dithered paint; made once.
static var _white_texture: ImageTexture
## Wheel parts are the wheel alone; the tires are drawn on them from this model unless the
## tire part names its own `model`.
const _TIRE_MODEL := "res://assets/parts/tire-225-60r15.glb"

var _waiting_for_stl: bool = false
var _previewing: bool = false
var _preview_spec: Dictionary = {}
var _preview_color: Color = Color.WHITE
## The previewed car's cove paint; alpha 0 leaves the cove the body color.
var _preview_cove: Color = Color(0, 0, 0, 0)
## The previewed car's stripped bumpers, by end ("front", "rear").
var _preview_bumpers_off: Array[String] = []


## Load a catalog car for a viewport that is not the player's garage car.
## Call before the node enters the tree. Returns false when the file fails to load.
## Head position from the car file, in this node's space.
func driver_seat_position() -> Vector3:
	var driver: Variant = _active_spec().get("driver", {})
	if typeof(driver) != TYPE_DICTIONARY:
		return Vector3(-0.35, 1.05, 0.2)
	var pos: Variant = (driver as Dictionary).get("position", null)
	if pos is Vector3:
		return pos
	return Vector3(-0.35, 1.05, 0.2)


## `cove` is the cove's own paint, for a car with one (alpha 0: the cove is the body color).
## `bumpers_off` are the ends whose bumpers are stripped.
func prepare_preview(car_file: String, paint: Color, cove := Color(0, 0, 0, 0), bumpers_off: Array[String] = []) -> bool:
	_preview_cove = cove
	_preview_bumpers_off = bumpers_off.duplicate()
	return _load_preview(car_file, paint)


## Swap the preview to another catalog car after this node is already on screen.
func preview_listing(car_file: String, paint: Color, bumpers_off: Array[String] = []) -> bool:
	_preview_cove = Color(0, 0, 0, 0)
	_preview_bumpers_off = bumpers_off.duplicate()
	if not _load_preview(car_file, paint):
		return false
	if is_inside_tree():
		_apply_car_file()
		_reload_preview_models()
		set_car_body_color(_preview_color)
	return true


func _load_preview(car_file: String, paint: Color) -> bool:
	var spec := _CarFile.load_path(car_file)
	var errors: Variant = spec.get("errors", [])
	if typeof(errors) == TYPE_ARRAY and not (errors as Array).is_empty():
		return false
	_previewing = true
	_preview_spec = spec
	_preview_color = paint
	return true


func reload_player_car() -> void:
	if _previewing:
		return
	_apply_car_file()
	_reload_preview_models()
	apply_equipped_wheels()
	var loaded_body := get_node_or_null("CarBody") as Node
	if loaded_body != null:
		_hide_baked_wheels(loaded_body)
	apply_bumpers()
	set_car_body_color(_active_paint_color())


func _active_spec() -> Dictionary:
	if _previewing:
		return _preview_spec
	return GameState.car_spec


func _active_paint_color() -> Color:
	if _previewing:
		return _preview_color
	return GameState.car_color


func _active_cove_color() -> Color:
	if _previewing:
		return _preview_cove
	return GameState.car_cove_color


func _active_bumpers_off() -> Array[String]:
	if _previewing:
		return _preview_bumpers_off
	return GameState.bumpers_off


## Shows each of the car's bumpers unless it is stripped. The garage calls it again after
## a bumper comes off or goes back on; a bumper put back is painted with the rest.
func apply_bumpers() -> void:
	var body := get_node_or_null("CarBody")
	if body == null:
		return
	var off := _active_bumpers_off()
	var bumpers: Dictionary = GameState.spec_bumpers(_active_spec())
	for end: String in bumpers.keys():
		var node := body.find_child(str((bumpers[end] as Dictionary).get("node", "")), true, false) as Node3D
		if node != null:
			node.visible = not off.has(end)


func _enter_tree() -> void:
	_apply_car_file()


func _ready() -> void:
	if not _previewing:
		apply_equipped_wheels()
	_apply_wheel_scale()
	var loaded_body := get_node_or_null("CarBody") as Node
	if loaded_body != null:
		_hide_baked_wheels(loaded_body)
		if loaded_body.has_signal(&"stl_loaded"):
			loaded_body.connect(&"stl_loaded", Callable(self, "_on_body_hide_wheels"))
	apply_bumpers()
	set_car_body_color(_active_paint_color())
	var car_body := get_node_or_null("body") as MeshInstance3D
	if car_body != null and body_paint != null:
		# CarBody `_ready` runs before this node, so the STL may already be loaded.
		if car_body.mesh != null:
			_apply_body_paint(car_body)
		elif car_body.has_signal(&"stl_loaded"):
			_waiting_for_stl = true
			car_body.connect(&"stl_loaded", Callable(self, "_on_car_body_stl_loaded").bind(car_body))

func _on_body_hide_wheels(_mesh: Variant) -> void:
	var loaded_body := get_node_or_null("CarBody") as Node
	if loaded_body != null:
		_hide_baked_wheels(loaded_body)
	apply_bumpers()
	set_car_body_color(_active_paint_color())


func _hide_baked_wheels(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and _is_baked_wheel(child as MeshInstance3D):
			(child as MeshInstance3D).visible = false
		_hide_baked_wheels(child)


func _is_baked_wheel(mesh_instance: MeshInstance3D) -> bool:
	var label := String(mesh_instance.name).to_lower()
	var parent_label := String(mesh_instance.get_parent().name).to_lower() if mesh_instance.get_parent() != null else ""
	if label.contains("driving_wheel") or label.contains("steering") or parent_label.contains("driving_wheel") or parent_label.contains("steering"):
		return false
	if label.contains("wheel") or label.contains("tire"):
		return true
	if mesh_instance.mesh == null:
		return false
	for i in mesh_instance.mesh.get_surface_count():
		var mat := mesh_instance.get_surface_override_material(i)
		if mat == null:
			mat = mesh_instance.mesh.surface_get_material(i)
		if mat == null:
			continue
		var mat_name := String(mat.resource_name).to_lower()
		if mat_name.contains("wheel") or mat_name.contains("tire"):
			return true
	return false


func _on_car_body_stl_loaded(_mesh: Mesh, car_body: MeshInstance3D) -> void:
	_waiting_for_stl = false
	_apply_body_paint(car_body)


func _apply_car_file() -> void:
	var spec: Dictionary = _active_spec()
	if spec.is_empty() or not spec.get("errors", []).is_empty():
		if _previewing:
			return
		spec = _CarFile.load_path(GameState.current_car_file_path())
	var errors: Variant = spec.get("errors", [])
	if typeof(errors) == TYPE_ARRAY and not (errors as Array).is_empty():
		return
	var wheels: Variant = spec.get("wheels", {})
	var overlay := true
	if typeof(wheels) == TYPE_DICTIONARY:
		overlay = bool((wheels as Dictionary).get("overlay", true))
	var model: Variant = spec.get("model", {})
	if typeof(model) == TYPE_DICTIONARY:
		var model_dict: Dictionary = model
		var body := get_node_or_null("CarBody") as Node3D
		_apply_mount(body, str(model_dict.get("path", "")), model_dict, float(model_dict.get("height", 5.0)))
		if body != null:
			body.set("snap_to_ground", not overlay)
	if typeof(wheels) != TYPE_DICTIONARY:
		return
	var wheel_dict: Dictionary = wheels
	_set_overlay_wheels_visible(overlay)
	if not overlay:
		return
	wheel_scale = float(wheel_dict.get("scale", wheel_scale)) * _wheel_size()
	var mounts: Variant = wheel_dict.get("mounts", [])
	if typeof(mounts) != TYPE_ARRAY:
		return
	var wheel_path := str(wheel_dict.get("path", ""))
	var wheel_height := float(wheel_dict.get("height", 0.5))
	var tires := _tire_state(str(wheel_dict.get("part", "")))
	for item: Variant in mounts:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var mount: Dictionary = item
		var wheel := get_node_or_null(str(mount.get("node", ""))) as Node3D
		_apply_mount(wheel, wheel_path, mount, wheel_height)
		_fit_tire(wheel, str(tires["model"]), bool(tires["shown"]))


func _set_overlay_wheels_visible(show: bool) -> void:
	for wname: String in ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]:
		var wheel := get_node_or_null(wname) as Node3D
		if wheel != null:
			wheel.visible = show


func _apply_mount(node: Node3D, model_path: String, mount: Dictionary, height: float) -> void:
	if node == null or node.get("stl_path") == null:
		return
	if not model_path.is_empty():
		node.set("stl_path", model_path)
	var pos: Variant = mount.get("position", null)
	if pos is Vector3:
		node.position = pos
	var rot: Variant = mount.get("rotation", null)
	if rot is Vector3:
		node.set("stl_rotation_degrees", rot)
	node.set("auto_scale_to_height", height)


func _reload_preview_models() -> void:
	_reload_mount(get_node_or_null("CarBody") as Node3D)
	if not _overlay_wheels_enabled():
		_set_overlay_wheels_visible(false)
		return
	for wname: String in ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]:
		_reload_mount(get_node_or_null(wname) as Node3D)


func _reload_mount(node: Node3D) -> void:
	if node == null or not node.has_method(&"load_model"):
		return
	for child in node.get_children():
		node.remove_child(child)
		child.free()
	if node is MeshInstance3D:
		(node as MeshInstance3D).mesh = null
	node.call(&"load_model")


func apply_equipped_wheels() -> void:
	if not _overlay_wheels_enabled():
		_set_overlay_wheels_visible(false)
		return
	if GameState.equipped_wheel_id == GameState.NO_WHEEL_ID:
		_set_overlay_wheels_visible(false)
		return
	apply_wheel_set(GameState.get_equipped_wheel())


func _overlay_wheels_enabled() -> bool:
	var wheels: Variant = _active_spec().get("wheels", {})
	if typeof(wheels) != TYPE_DICTIONARY:
		return true
	return bool((wheels as Dictionary).get("overlay", true))


func apply_wheel_set(wheel: Dictionary) -> void:
	if wheel.is_empty():
		return
	for wname: String in ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]:
		apply_wheel_to_mount(get_node_or_null(wname) as Node3D, wheel)


func apply_wheel_to_mount(mount: Node3D, wheel: Dictionary) -> void:
	if mount == null or wheel.is_empty():
		return
	var path := str(wheel.get("path", ""))
	if path.is_empty() or mount.get("stl_path") == null:
		return
	wheel_scale = float(wheel.get("scale", wheel_scale)) * _wheel_size()
	var height := float(wheel.get("height", 0.5))
	var changed := str(mount.get("stl_path")) != path
	mount.visible = true
	mount.set("stl_path", path)
	mount.set("auto_scale_to_height", height)
	if changed and mount.has_method(&"load_model"):
		for child in mount.get_children():
			mount.remove_child(child)
			child.free()
		if mount is MeshInstance3D:
			(mount as MeshInstance3D).mesh = null
		mount.call(&"load_model")
	if mount is MeshInstance3D:
		(mount as MeshInstance3D).scale = Vector3.ONE * wheel_scale
	var tires := _tire_state(str(wheel.get("id", "")))
	_fit_tire(mount, str(tires["model"]), bool(tires["shown"]))


## The tire model for a set of wheels and whether it has tires on: a catalog car always
## does; the player's fitted set when the tire slot is filled; a set off the car when tires
## are shelved with it.
func _tire_state(wheel_id: String) -> Dictionary:
	if _previewing:
		return {"model": _TIRE_MODEL, "shown": true}
	var tires: Dictionary
	if wheel_id == GameState.equipped_wheel_id:
		tires = GameState.slot_part(GameState.SLOT_TIRES)
	else:
		tires = GameState.listing_by_id(GameState.PARTS, GameState.shelved_wheel_tires_id(wheel_id))
	return {"model": str(tires.get("model", _TIRE_MODEL)), "shown": not tires.is_empty()}


## Puts a tire on a wheel node's model, shown or hidden. A hidden tire stays on, so the car
## sits at the same height and its wheels turn about the same axle with tires or without.
## A wheel model loaded later gets the tire when it arrives.
func _fit_tire(mount: Node3D, model_path: String, shown: bool) -> void:
	if mount == null:
		return
	mount.set_meta(&"tire_model", model_path)
	mount.set_meta(&"tire_shown", shown)
	if not mount.has_meta(&"tire_watch") and mount.has_signal(&"stl_loaded"):
		mount.set_meta(&"tire_watch", true)
		mount.connect(&"stl_loaded", _on_wheel_model_loaded.bind(mount))
	var model := _wheel_model(mount)
	if model != null:
		_place_tire(model, model_path, shown)


func _on_wheel_model_loaded(model: Object, mount: Node3D) -> void:
	if model is Node3D and mount.has_meta(&"tire_model"):
		_place_tire(model as Node3D, str(mount.get_meta(&"tire_model")), bool(mount.get_meta(&"tire_shown", true)))


## The wheel model a wheel node loaded, or null before it has.
func _wheel_model(mount: Node3D) -> Node3D:
	for child in mount.get_children():
		if child is Node3D:
			return child as Node3D
	return null


## The tire goes under the wheel model, so it takes the model's turn onto the axle; both
## are real size and centered on the rim.
func _place_tire(model: Node3D, model_path: String, shown: bool) -> void:
	var tire := model.get_node_or_null(^"Tire") as Node3D
	if tire != null and str(tire.get_meta(&"model", "")) != model_path:
		model.remove_child(tire)
		tire.free()
		tire = null
	if tire == null:
		var scene := load(model_path) as PackedScene
		if scene == null:
			push_warning("[Tire] Failed to load: " + model_path)
			return
		tire = scene.instantiate() as Node3D
		tire.name = "Tire"
		tire.set_meta(&"model", model_path)
		model.add_child(tire)
	tire.visible = shown


## The car file's `wheels.size`: how much bigger than the part this car's wheels are drawn.
func _wheel_size() -> float:
	var wheels: Variant = _active_spec().get("wheels", {})
	if typeof(wheels) != TYPE_DICTIONARY:
		return 1.0
	return float((wheels as Dictionary).get("size", 1.0))


func _apply_wheel_scale() -> void:
	var wheel_names := ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]
	for wname: String in wheel_names:
		var wheel := get_node_or_null(wname) as MeshInstance3D
		if wheel != null:
			wheel.scale = Vector3.ONE * wheel_scale


func _apply_body_paint(car_body: MeshInstance3D) -> void:
	if body_paint == null:
		return
	var m := body_paint.duplicate()
	if m is StandardMaterial3D:
		(m as StandardMaterial3D).albedo_color.a = 1.0
		(m as StandardMaterial3D).transmission = 0.0
	car_body.material_override = m


## Runtime paint updates (e.g. from the garage spray pistol).
#func set_car_body_color(color: Color) -> void:
	#var car_body := get_node_or_null("CarBody") as MeshInstance3D
	#if car_body == null:
		#return
#
	## Build a material based on whatever is currently on the body.
	#var base := car_body.material_override
	#var mat: StandardMaterial3D
	#if base is StandardMaterial3D:
		#mat = (base as StandardMaterial3D).duplicate()
	#elif body_paint != null and body_paint is StandardMaterial3D:
		#mat = (body_paint as StandardMaterial3D).duplicate()
	#else:
		#mat = StandardMaterial3D.new()
		#mat.metallic = 0.4
		#mat.roughness = 0.35
#
	#var c := color
	#c.a = 1.0
	#mat.albedo_color = c
	#mat.transmission = 0.0
#
	#body_paint = mat
#
	## If the STL is already loaded, apply immediately; otherwise wait for it.
	#if car_body.mesh != null:
		#_apply_body_paint(car_body)
	#elif car_body.has_signal(&"stl_loaded") and not _waiting_for_stl:
		#_waiting_for_stl = true
		#car_body.connect(&"stl_loaded", Callable(self, "_on_car_body_stl_loaded").bind(car_body))

func set_car_body_color(new_color: Color) -> void:
	var color := new_color
	color.a = 1.0
	var named_body := find_child("body", true, false)
	if named_body is MeshInstance3D and (named_body as MeshInstance3D).mesh != null:
		_paint_solid_mesh(named_body as MeshInstance3D, color)
		return
	var car_body := get_node_or_null("CarBody")
	if car_body != null:
		_paint_masked_meshes(car_body, color)


func _paint_solid_mesh(mesh_instance: MeshInstance3D, color: Color) -> void:
	var surface_count := mesh_instance.mesh.get_surface_count()
	for i in range(surface_count):
		var mat: Material = mesh_instance.get_surface_override_material(i)
		if mat == null:
			mat = mesh_instance.mesh.surface_get_material(i)
		if mat == null:
			mat = StandardMaterial3D.new()
		if mat is StandardMaterial3D and (_dither_cell() > 0.0 or _has_cove()):
			mesh_instance.set_surface_override_material(i, _shaded_solid_paint(mat as StandardMaterial3D, color, mesh_instance))
			continue
		var mat_copy := mat.duplicate()
		mesh_instance.set_surface_override_material(i, mat_copy)
		if mat_copy is StandardMaterial3D:
			(mat_copy as StandardMaterial3D).albedo_texture = null
			(mat_copy as StandardMaterial3D).albedo_color = color
		elif mat_copy is ShaderMaterial:
			if (mat_copy as ShaderMaterial).shader == _PaintShader:
				_set_paint_params(mat_copy as ShaderMaterial, color, mesh_instance)
			elif (mat_copy as ShaderMaterial).shader != null:
				(mat_copy as ShaderMaterial).set_shader_parameter("paint_color", color)
				(mat_copy as ShaderMaterial).set_shader_parameter("albedo_color", color)


## A solid-painted body (a mesh named "body") in a car whose file sets dither_cell or a
## cove: the paint shader over plain white instead of the model's texture, keeping its
## shine and normal map. Painting it again only changes the colors, in the ShaderMaterial
## branch.
func _shaded_solid_paint(std: StandardMaterial3D, color: Color, mesh_instance: MeshInstance3D) -> ShaderMaterial:
	if _white_texture == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_texture = ImageTexture.create_from_image(img)
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = _PaintShader
	shader_mat.set_shader_parameter("albedo_tex", _white_texture)
	_set_paint_params(shader_mat, color, mesh_instance)
	shader_mat.set_shader_parameter("metallic", std.metallic)
	shader_mat.set_shader_parameter("roughness", std.roughness)
	if std.normal_enabled and std.normal_texture != null:
		shader_mat.set_shader_parameter("normal_tex", std.normal_texture)
		shader_mat.set_shader_parameter("use_normal", 1.0)
		shader_mat.set_shader_parameter("normal_scale", std.normal_scale)
	return shader_mat


## Everything car_paint_mask.gdshader takes from the car rather than the material: the
## body and cove colors, the dither, the cove's outline, and where the mesh sits in the car.
func _set_paint_params(shader_mat: ShaderMaterial, color: Color, mesh_instance: MeshInstance3D) -> void:
	shader_mat.set_shader_parameter("paint_color", color)
	shader_mat.set_shader_parameter("dither_cell", _dither_cell())
	shader_mat.set_shader_parameter("car_from_mesh", Projection(_car_from_mesh(mesh_instance)))
	var cove := _cove()
	var outline: PackedVector2Array = cove.get("outline", PackedVector2Array())
	var cove_color := _active_cove_color()
	cove_color.a = 1.0 if cove_color.a > 0.5 else 0.0
	shader_mat.set_shader_parameter("cove_color", cove_color)
	shader_mat.set_shader_parameter("cove_count", outline.size())
	shader_mat.set_shader_parameter("cove_outline", outline)
	shader_mat.set_shader_parameter("cove_min_x", float(cove.get("min_x", 0.0)))


func _cove() -> Dictionary:
	var model: Variant = _active_spec().get("model", {})
	if typeof(model) != TYPE_DICTIONARY:
		return {}
	var cove: Variant = (model as Dictionary).get("cove", {})
	return cove if typeof(cove) == TYPE_DICTIONARY else {}


func _has_cove() -> bool:
	return not _cove().is_empty()


func _is_dash_gauge(node: Node) -> bool:
	var n := String(node.name).to_lower()
	return n.begins_with("dash_") or n == "speedo_needle" or n == "tach_needle"


func _paint_masked_meshes(node: Node, color: Color) -> void:
	if _is_dash_gauge(node):
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.visible and not _is_baked_wheel(mesh_instance):
			_paint_masked_mesh(mesh_instance, color)
	for child in node.get_children():
		_paint_masked_meshes(child, color)


func _paint_masked_mesh(mesh_instance: MeshInstance3D, color: Color) -> void:
	for i in range(mesh_instance.mesh.get_surface_count()):
		var mat: Material = mesh_instance.get_surface_override_material(i)
		if mat == null:
			mat = mesh_instance.mesh.surface_get_material(i)
		var tex: Texture2D = null
		if mat is ShaderMaterial:
			var existing := mat as ShaderMaterial
			var tagged: Variant = existing.get_shader_parameter("albedo_tex")
			if tagged is Texture2D:
				tex = tagged
			_set_paint_params(existing, color, mesh_instance)
			if tex != null:
				continue
		var orm: Texture2D = null
		var normal: Texture2D = null
		var normal_scale := 1.0
		if mat is StandardMaterial3D:
			var std := mat as StandardMaterial3D
			if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			tex = std.albedo_texture
			orm = std.metallic_texture
			if orm == null:
				orm = std.roughness_texture
			normal = std.normal_texture
			normal_scale = std.normal_scale
		if tex == null:
			if mat is StandardMaterial3D:
				var solid := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				solid.albedo_color = color
				mesh_instance.set_surface_override_material(i, solid)
			continue
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = _PaintShader
		shader_mat.set_shader_parameter("albedo_tex", tex)
		_set_paint_params(shader_mat, color, mesh_instance)
		if orm != null:
			shader_mat.set_shader_parameter("orm_tex", orm)
			shader_mat.set_shader_parameter("use_orm", 1.0)
		if normal != null:
			shader_mat.set_shader_parameter("normal_tex", normal)
			shader_mat.set_shader_parameter("use_normal", 1.0)
			shader_mat.set_shader_parameter("normal_scale", normal_scale)
		mesh_instance.set_surface_override_material(i, shader_mat)

## Sit wheel bottoms and the car body on the top of a horizontal floor mesh.
func align_wheels_to_floor(floor_mesh_instance: MeshInstance3D) -> void:
	if floor_mesh_instance == null or floor_mesh_instance.mesh == null:
		fit_parent_collision()
		return

	var faabb := floor_mesh_instance.get_aabb()
	var minp := faabb.position
	var maxp := faabb.position + faabb.size
	var floor_top_y := -INF
	for x: float in [minp.x, maxp.x]:
		for y: float in [minp.y, maxp.y]:
			for z: float in [minp.z, maxp.z]:
				var corner := Vector3(x, y, z)
				var world := floor_mesh_instance.global_transform * corner
				floor_top_y = maxf(floor_top_y, world.y)

	var wheel_names := ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]
	for wname: String in wheel_names:
		_snap_node_bottom_to_y(get_node_or_null(wname) as Node3D, floor_top_y)
	_snap_node_bottom_to_y(get_node_or_null("CarBody") as Node3D, floor_top_y + _ground_clearance())
	fit_parent_collision()


func _ground_clearance() -> float:
	var model: Variant = _active_spec().get("model", {})
	if typeof(model) != TYPE_DICTIONARY:
		return 0.0
	return float((model as Dictionary).get("ground_clearance", 0.0))


## Takes a body mesh's own coordinates to the car's: meters, Y up, as CarBody holds the model.
## The paint's dither squares and shades are laid out in these, so a model's units and
## up axis (Z in Sketchfab exports) don't change them.
func _car_from_mesh(mesh_instance: MeshInstance3D) -> Transform3D:
	var body := get_node_or_null("CarBody")
	var xf := Transform3D.IDENTITY
	var node: Node = mesh_instance
	while node != null and node != body and node != self:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	return xf


## The size of the paint's dither squares in meters (car_paint_mask.gdshader), 0 for none.
func _dither_cell() -> float:
	var model: Variant = _active_spec().get("model", {})
	if typeof(model) != TYPE_DICTIONARY:
		return 0.0
	return float((model as Dictionary).get("dither_cell", 0.0))


func _snap_node_bottom_to_y(node: Node3D, floor_top_y: float) -> void:
	if node == null:
		return
	var bottom_y := _mesh_bottom_y(node)
	if bottom_y == INF:
		return
	var delta := floor_top_y - bottom_y
	if absf(delta) > 0.0001:
		var gp := node.global_position
		gp.y += delta
		node.global_position = gp


## Size the parent car's box to the visible body. The bottom stays clear of the road.
func fit_parent_collision() -> void:
	var body := get_parent() as Node3D
	if body == null or not is_inside_tree():
		return
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	force_update_transform()
	var bounds := _collect_mesh_bounds(self, body.global_transform.affine_inverse())
	if bounds.size.length_squared() < 0.01:
		return
	const BOTTOM_LIFT_M := 0.08
	if bounds.size.y > BOTTOM_LIFT_M + 0.4:
		bounds.position.y += BOTTOM_LIFT_M
		bounds.size.y -= BOTTOM_LIFT_M
	var box := BoxShape3D.new()
	box.size = bounds.size
	shape_node.shape = box
	shape_node.position = bounds.get_center()
	shape_node.rotation = Vector3.ZERO


func _collect_mesh_bounds(node: Node, to_space: Transform3D) -> AABB:
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		return AABB()
	var merged := AABB()
	var started := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			merged = _aabb_in_space(to_space * mi.global_transform, mi.mesh.get_aabb())
			started = true
	for child in node.get_children():
		var child_bounds := _collect_mesh_bounds(child, to_space)
		if child_bounds.size == Vector3.ZERO:
			continue
		if not started:
			merged = child_bounds
			started = true
		else:
			merged = merged.merge(child_bounds)
	return merged


func _aabb_in_space(xf: Transform3D, local: AABB) -> AABB:
	var mins := Vector3(INF, INF, INF)
	var maxs := Vector3(-INF, -INF, -INF)
	var origin := local.position
	var extent := local.size
	for i in 8:
		var corner := origin
		if (i & 1) != 0:
			corner.x += extent.x
		if (i & 2) != 0:
			corner.y += extent.y
		if (i & 4) != 0:
			corner.z += extent.z
		var point := xf * corner
		mins = mins.min(point)
		maxs = maxs.max(point)
	return AABB(mins, maxs - mins)


func _mesh_bottom_y(node: Node3D) -> float:
	var bottom_y := INF
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var aabb := (node as MeshInstance3D).get_aabb()
		var wmin := aabb.position
		var wmax := wmin + aabb.size
		for wx: float in [wmin.x, wmax.x]:
			for wy: float in [wmin.y, wmax.y]:
				for wz: float in [wmin.z, wmax.z]:
					var world := node.global_transform * Vector3(wx, wy, wz)
					bottom_y = minf(bottom_y, world.y)
	for child in node.get_children():
		if child is Node3D:
			bottom_y = minf(bottom_y, _mesh_bottom_y(child as Node3D))
	return bottom_y
