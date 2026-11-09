extends RefCounted

## A photograph of one catalog part: the same model the garage fits, on its own.

const _EngineAssembly := preload("res://scripts/engine_assembly.gd")
const _UnderCar := preload("res://scripts/under_car.gd")
const _Transmission := preload("res://scripts/transmission.gd")
const _WheelMesh := preload("res://scripts/stl_mesh_instance.gd")

const _ENGINE_MODEL := "res://assets/parts/engine-v8-283.glb"
const _WEAR_SHADER := preload("res://shaders/part_wear.gdshader")

static var _white_tex: Texture2D


static func build(part: Dictionary, kind: String) -> Node3D:
	match kind:
		"engine":
			return _engine(part)
		"transmission":
			return _gearbox(part)
		"wheels":
			return _wheel(part)
		_:
			return _part(part)


static func _engine(part: Dictionary) -> Node3D:
	var asm := _EngineAssembly.new()
	asm.show_spec(part, {})
	asm.rebuild(GameState.HOOD_ENGINE)
	return asm


## A hood part on its own, on an engine of its family when it has one: the flathead's
## parts are drawn from the flathead's layout.
static func _hood(part: Dictionary) -> Node3D:
	var slot := str(part.get("slot", ""))
	var engine := {"model": _ENGINE_MODEL, "heads": 2}
	var family := GameState.engine_family(part)
	for listed: Dictionary in GameState.ENGINES:
		if not family.is_empty() and GameState.engine_family(listed) == family:
			engine = listed
			break
	var asm := _EngineAssembly.new()
	asm.show_spec(engine, {slot: part})
	asm.rebuild(slot)
	return asm


static func _gearbox(part: Dictionary) -> Node3D:
	var shop := _Transmission.new()
	var rig := shop.build_preview(part)
	shop.free()
	return rig


static func _under(part: Dictionary) -> Node3D:
	var shop := _UnderCar.new()
	var rig := shop.build_preview(part)
	shop.free()
	return rig


static func _part(part: Dictionary) -> Node3D:
	var slot := str(part.get("slot", ""))
	if slot == GameState.SLOT_TIRES:
		return _tire(part)
	if GameState.is_hood_kind(slot):
		return _hood(part)
	if GameState.UNDER_CAR_SLOTS.has(slot):
		return _under(part)
	return _block()


static func _wheel(part: Dictionary) -> Node3D:
	var path := str(part.get("path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.set_script(_WheelMesh)
	mesh.set("print_debug", false)
	mesh.set("center_model", true)
	mesh.set("apply_rotation", true)
	mesh.set("stl_path", path)
	mesh.set("auto_scale_to_height", float(part.get("height", 0.5)))
	mesh.set("stl_rotation_degrees", Vector3(0.0, 180.0, 90.0))
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.62, 0.66)
	steel.metallic = 0.72
	steel.roughness = 0.32
	mesh.set("car_material", steel)
	root.add_child(mesh)
	mesh.scale = Vector3.ONE * float(part.get("scale", 1.0))
	root.set_meta(&"wear_round_uv", true)
	return root


static func _tire(part: Dictionary) -> Node3D:
	var root := Node3D.new()
	var style := str(part.get("style", "bias"))
	var slick := style == "slick"
	var ring := _torus(0.16 if slick else 0.2, 0.36 if slick else 0.33, Color(0.07, 0.07, 0.07), 0.55 if slick else 0.92)
	root.add_child(ring)
	if style == "radial":
		root.add_child(_torus(0.3, 0.335, Color(0.9, 0.9, 0.86), 0.6))
	return root


static func _torus(inner: float, outer: float, color: Color, roughness: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	ring.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	ring.material_override = mat
	ring.rotation.x = PI * 0.5
	return ring


## Mixes matte dirt and rust into the part's own surface. `worn` is 0 to 50 percent.
static func apply_wear(root: Node3D, worn: int) -> void:
	var amount := clampf(float(worn) / 50.0, 0.0, 1.0)
	if root == null or amount <= 0.001:
		return
	var cache: Dictionary = {}
	_weather(root, amount, cache)


static func _weather(node: Node, amount: float, cache: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		mesh.material_overlay = null
		if mesh.mesh != null:
			_replace_materials(mesh, amount, cache)
	for child: Node in node.get_children():
		_weather(child, amount, cache)


static func _replace_materials(mesh: MeshInstance3D, amount: float, cache: Dictionary) -> void:
	var unwrap := 0.0 if _wants_round_uv(mesh) else 1.0
	if mesh.material_override is BaseMaterial3D:
		mesh.material_override = _worn_material(mesh.material_override as BaseMaterial3D, amount, unwrap, cache)
		return
	for surface: int in mesh.mesh.get_surface_count():
		var mat := mesh.get_active_material(surface)
		if mat is BaseMaterial3D:
			mesh.set_surface_override_material(surface, _worn_material(mat as BaseMaterial3D, amount, unwrap, cache))


static func _worn_material(src: BaseMaterial3D, amount: float, unwrap: float, cache: Dictionary) -> Material:
	var key := "%d:%s" % [src.get_instance_id(), unwrap]
	if cache.has(key):
		return cache[key] as Material
	var mat := ShaderMaterial.new()
	mat.shader = _WEAR_SHADER
	mat.set_shader_parameter(&"albedo_color", src.albedo_color)
	var albedo := src.albedo_texture
	mat.set_shader_parameter(&"albedo_texture", albedo if albedo != null else _white_texture())
	mat.set_shader_parameter(&"metallic", src.metallic)
	mat.set_shader_parameter(&"roughness", src.roughness)
	var metal_tex := src.metallic_texture
	mat.set_shader_parameter(&"use_metallic_tex", metal_tex != null)
	mat.set_shader_parameter(&"metallic_texture", metal_tex if metal_tex != null else _white_texture())
	mat.set_shader_parameter(&"metal_channel", int(src.metallic_texture_channel))
	var rough_tex := src.roughness_texture
	mat.set_shader_parameter(&"use_roughness_tex", rough_tex != null)
	mat.set_shader_parameter(&"roughness_texture", rough_tex if rough_tex != null else _white_texture())
	mat.set_shader_parameter(&"rough_channel", int(src.roughness_texture_channel))
	mat.set_shader_parameter(&"wear", amount)
	mat.set_shader_parameter(&"use_unwrap", unwrap)
	cache[key] = mat
	return mat


static func _wants_round_uv(node: Node) -> bool:
	var here: Node = node
	while here != null:
		if here.has_meta(&"wear_round_uv"):
			return true
		here = here.get_parent()
	return false


static func _white_texture() -> Texture2D:
	if _white_tex != null:
		return _white_tex
	var image := Image.create(1, 1, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	_white_tex = ImageTexture.create_from_image(image)
	return _white_tex


static func _block() -> Node3D:
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.42, 0.26, 0.22)
	block.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.46, 0.48)
	mat.metallic = 0.6
	mat.roughness = 0.4
	block.material_override = mat
	block.position.y = mesh.size.y * 0.5
	return block
