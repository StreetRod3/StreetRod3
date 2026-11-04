extends RefCounted

## A photograph of one catalog part: the same model the garage fits, on its own.

const _EngineAssembly := preload("res://scripts/engine_assembly.gd")
const _UnderCar := preload("res://scripts/under_car.gd")
const _Transmission := preload("res://scripts/transmission.gd")
const _WheelMesh := preload("res://scripts/stl_mesh_instance.gd")

const _ENGINE_MODEL := "res://assets/parts/engine-v8-283.glb"


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


static func _hood(part: Dictionary) -> Node3D:
	var slot := str(part.get("slot", ""))
	var asm := _EngineAssembly.new()
	asm.show_spec({"model": _ENGINE_MODEL, "heads": 2}, {slot: part})
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
