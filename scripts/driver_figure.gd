extends Node3D

## A driver's head and shoulders, from a MakeHuman character baked to a model for each
## sex (assets/driver) and set from the traits on their license
## (`GameState.driver_traits`). Weight drives the models' slim and heavy shape keys,
## which leave the eyes where they are. Units are meters, the origin is between the
## eyes of a driver of REFERENCE_INCHES, taller and shorter drivers stand higher and
## lower than that, and the driver faces +Z. Call apply() again whenever the traits
## change.

const BALD := "BAL"
## Hair textures are neutral grey, so these are multiplied onto them.
const HAIR_COLORS := {
	"BRN": Color(0.34, 0.2, 0.11),
	"BLK": Color(0.09, 0.08, 0.08),
	"BLN": Color(0.95, 0.76, 0.42),
	"RED": Color(0.7, 0.27, 0.11),
	"GRY": Color(0.66, 0.66, 0.66),
	"WHI": Color(1.0, 0.99, 0.95),
}
## The brows of a driver with no hair.
const BALD_BROWS := "BRN"
const EYE_TEXTURES := {
	"BRN": preload("res://assets/driver/eye_BRN.jpg"),
	"BLU": preload("res://assets/driver/eye_BLU.jpg"),
	"GRN": preload("res://assets/driver/eye_GRN.jpg"),
	"HZL": preload("res://assets/driver/eye_HZL.jpg"),
	"GRY": preload("res://assets/driver/eye_GRY.jpg"),
}
## In the order a click on the photo steps through them.
const SKIN_TONES: Array[String] = ["LGT", "OLV", "BRN", "DRK"]
const MODELS := {"M": "res://assets/driver/driver_m.glb", "F": "res://assets/driver/driver_f.glb"}
const HAIR_STYLES := {"M": "Hair_short02", "F": "Hair_long01"}

const REFERENCE_INCHES := 68
## How much of a height difference shows, so short and tall drivers both stay in frame.
const HEIGHT_SHOWN := 0.2
const AVERAGE_BMI := 24.0
const SLIM_BMI := 16.0
const HEAVY_BMI := 45.0

var _sex := ""
var _model: Node3D
var _meshes: Dictionary[String, MeshInstance3D] = {}


func apply(traits: Dictionary) -> void:
	var sex := "F" if str(traits.get("sex", "")) == "F" else "M"
	if sex != _sex:
		_load_model(sex)
	var inches := height_inches(str(traits.get("height", "")))
	var build := build_amount(inches, weight_pounds(str(traits.get("weight", ""))))
	position.y = (inches - REFERENCE_INCHES) * 0.0254 * HEIGHT_SHOWN
	for mesh: MeshInstance3D in _meshes.values():
		mesh.set_blend_shape_value(mesh.find_blend_shape_by_name(&"slim"), maxf(-build, 0.0))
		mesh.set_blend_shape_value(mesh.find_blend_shape_by_name(&"heavy"), maxf(build, 0.0))

	var hair := str(traits.get("hair", ""))
	var style: String = HAIR_STYLES[sex]
	for part: String in _meshes:
		if part.begins_with("Hair_"):
			_meshes[part].visible = part == style and HAIR_COLORS.has(hair)
	if HAIR_COLORS.has(hair):
		_material(style).albedo_color = HAIR_COLORS[hair]
	_material("Brows").albedo_color = HAIR_COLORS.get(hair, HAIR_COLORS[BALD_BROWS])
	_meshes["Glasses"].visible = bool(traits.get("glasses", false))
	var tone := str(traits.get("skin", ""))
	if not SKIN_TONES.has(tone):
		tone = SKIN_TONES[0]
	_material("Body").albedo_texture = load("res://assets/driver/skin_%s_%s.jpg" % [sex.to_lower(), tone])
	_material("Eyes").albedo_texture = EYE_TEXTURES.get(str(traits.get("eyes", "")), EYE_TEXTURES["BRN"])


## -1 for the slimmest build through 1 for the heaviest, from weight for height.
static func build_amount(inches: int, pounds: int) -> float:
	var bmi := 703.0 * pounds / float(inches * inches)
	if bmi < AVERAGE_BMI:
		return -clampf(inverse_lerp(AVERAGE_BMI, SLIM_BMI, bmi), 0.0, 1.0)
	return clampf(inverse_lerp(AVERAGE_BMI, HEAVY_BMI, bmi), 0.0, 1.0)


static func height_inches(height: String) -> int:
	var parts := height.split("-")
	if parts.size() != 2:
		return REFERENCE_INCHES
	return int(parts[0]) * 12 + int(parts[1])


static func weight_pounds(weight: String) -> int:
	return maxi(int(weight), 1)


func _load_model(sex: String) -> void:
	if _model:
		remove_child(_model)
		_model.free()
	_sex = sex
	_model = (load(MODELS[sex]) as PackedScene).instantiate()
	add_child(_model)
	_meshes.clear()
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var material := (mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		material.cull_mode = BaseMaterial3D.CULL_BACK
		if mesh.name.begins_with("Hair_"):
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		elif mesh.name == "Brows" or mesh.name == "Lashes":
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		elif mesh.name == "Eyes":
			material.roughness = 0.2
		mesh.set_surface_override_material(0, material)
		_meshes[str(mesh.name)] = mesh


func _material(part: String) -> StandardMaterial3D:
	return _meshes[part].get_surface_override_material(0)
