extends RefCounted

## The gas pump model (assets/locations/gas-station/pump.glb, built by tools/gas_pump_to_glb.py),
## ready to stand: the gas station scene's two pumps and the city's both use it. Its front, the
## dial and the GASOLINE plate, faces +Z, and it stands on Y = 0.

## Both pumps are this model; its side plate reads REGULAR.
const MODEL := "res://assets/locations/gas-station/pump.glb"
## The super pump's body maps: the same atlas with the plate reading SUPER.
const _SUPER_COLOR := "res://assets/locations/gas-station/pump-super-color.png"
const _SUPER_NORMAL := "res://assets/locations/gas-station/pump-super-normal.png"

static var _glass_mat: BaseMaterial3D = null
static var _super_mat: BaseMaterial3D = null


## A pump, its plate reading SUPER when `id` is "super" and REGULAR otherwise. Null if the
## model fails to load.
static func make(id: String) -> Node3D:
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_error("Pump model failed to load: %s" % MODEL)
		return null
	var model := packed.instantiate() as Node3D
	model.name = "Model"
	if id == "super":
		_paint_super_plate(model.get_node_or_null("pump") as MeshInstance3D)
	_clear_glass(model.get_node_or_null("pump_glass") as MeshInstance3D)
	return model


## The glTF import gives the dial glass a depth pre-pass, which hides the dial behind
## it; a plain alpha blend shows the dial through the grimy glass.
static func _clear_glass(glass: MeshInstance3D) -> void:
	if glass == null:
		return
	if _glass_mat == null:
		var base := glass.get_active_material(0) as BaseMaterial3D
		if base == null:
			return
		_glass_mat = base.duplicate() as BaseMaterial3D
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.set_surface_override_material(0, _glass_mat)


## The super pump wears the same atlas with its side plate repainted to read SUPER.
static func _paint_super_plate(body: MeshInstance3D) -> void:
	if body == null:
		return
	if _super_mat == null:
		var base := body.get_active_material(0) as BaseMaterial3D
		var color := load(_SUPER_COLOR) as Texture2D
		var normal := load(_SUPER_NORMAL) as Texture2D
		if base == null or color == null or normal == null:
			push_error("Super pump maps failed to load")
			return
		_super_mat = base.duplicate() as BaseMaterial3D
		_super_mat.albedo_texture = color
		_super_mat.normal_texture = normal
	body.set_surface_override_material(0, _super_mat)
