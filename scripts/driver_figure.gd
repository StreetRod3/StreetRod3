extends Node3D

## A driver's head and shoulders, built in code from the traits on their license
## (`GameState.driver_traits`). The body and head are lofted from cross sections, so
## weight and sex change their shape rather than stretching a fixed model. Units are
## meters, the origin is between the eyes of a driver of REFERENCE_INCHES, taller and
## shorter drivers stand higher and lower than that, and the driver faces +Z. Call
## apply() again whenever the traits change.

const BALD := "BAL"
const HAIR_COLORS := {
	"BRN": Color(0.27, 0.16, 0.09),
	"BLK": Color(0.07, 0.06, 0.06),
	"BLN": Color(0.8, 0.64, 0.35),
	"RED": Color(0.58, 0.22, 0.09),
	"GRY": Color(0.56, 0.56, 0.56),
	"WHI": Color(0.9, 0.89, 0.86),
}
const EYE_COLORS := {
	"BRN": Color(0.3, 0.17, 0.08),
	"BLU": Color(0.25, 0.48, 0.75),
	"GRN": Color(0.26, 0.52, 0.32),
	"HZL": Color(0.52, 0.4, 0.17),
	"GRY": Color(0.52, 0.58, 0.62),
}
const SKIN := Color(0.8, 0.62, 0.5)
const SHIRT := Color(0.33, 0.42, 0.55)
const COLLAR := Color(0.42, 0.52, 0.66)
const LIPS := Color(0.62, 0.32, 0.3)
const DARK := Color(0.09, 0.07, 0.07)

const REFERENCE_INCHES := 68
## How much of a height difference shows, so short and tall drivers both stay in frame.
const HEIGHT_SHOWN := 0.2
const SLIM_BMI := 18.0
const HEAVY_BMI := 40.0

const _SEGMENTS := 48
const _HEAD_SQUARENESS := 2.25
const _BODY_SQUARENESS := 2.7
## Height against the eyes, half width, depth to the front, depth to the back.
const _HEAD_ROWS: Array[Vector4] = [
	Vector4(0.112, 0.004, 0.004, 0.004),
	Vector4(0.106, 0.036, 0.036, 0.042),
	Vector4(0.09, 0.061, 0.062, 0.076),
	Vector4(0.06, 0.074, 0.08, 0.092),
	Vector4(0.03, 0.078, 0.088, 0.098),
	Vector4(0.015, 0.078, 0.09, 0.098),
	Vector4(0.0, 0.077, 0.083, 0.097),
	Vector4(-0.03, 0.075, 0.087, 0.09),
	Vector4(-0.06, 0.07, 0.086, 0.07),
	Vector4(-0.085, 0.061, 0.083, 0.05),
	Vector4(-0.105, 0.05, 0.08, 0.035),
	Vector4(-0.12, 0.034, 0.072, 0.025),
	Vector4(-0.129, 0.012, 0.058, 0.01),
]
const _TORSO_ROWS: Array[Vector4] = [
	Vector4(-0.142, 0.05, 0.05, 0.05),
	Vector4(-0.165, 0.08, 0.06, 0.06),
	Vector4(-0.195, 0.14, 0.075, 0.075),
	Vector4(-0.225, 0.185, 0.09, 0.085),
	Vector4(-0.275, 0.205, 0.105, 0.095),
	Vector4(-0.4, 0.205, 0.115, 0.1),
	Vector4(-0.7, 0.19, 0.11, 0.1),
]
## How far forward the hair may come at a height against the eyes: the hairline.
const _HAIR_FRONT: Array[Vector2] = [
	Vector2(0.078, 0.2),
	Vector2(0.066, 0.07),
	Vector2(0.05, 0.05),
	Vector2(0.02, 0.03),
	Vector2(-0.02, 0.012),
	Vector2(-0.3, 0.012),
]

const _HAIR_THICKNESS := 0.012
## Short hair stops at the top of the ear, long hair behind the shoulders.
const _SHORT_HAIR_BOTTOM := -0.004
const _LONG_HAIR_BOTTOM := -0.215

## The traits as lofted, for the facial features to sit on the same surfaces.
var _lower_face := 1.0
var _upper_face := 1.0
var _broad := 1.0
var _deep := 1.0
var _neck := 0.05


func apply(traits: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	var hair := str(traits.get("hair", ""))
	var inches := height_inches(str(traits.get("height", "")))
	var build := build_amount(inches, weight_pounds(str(traits.get("weight", ""))))
	var female := str(traits.get("sex", "")) == "F"

	position.y = (inches - REFERENCE_INCHES) * 0.0254 * HEIGHT_SHOWN
	_upper_face = lerpf(0.95, 1.08, build)
	_lower_face = lerpf(0.9, 1.32, build) * (0.93 if female else 1.0)
	_broad = lerpf(0.82, 1.2, build) * (0.86 if female else 1.0)
	_deep = lerpf(0.8, 1.4, build)
	_neck = lerpf(0.046, 0.082, build)

	_add_body()
	_add_mesh("Head", _loft(_head_rings()), SKIN)
	_add_face(hair, str(traits.get("eyes", "")), female)
	if HAIR_COLORS.has(hair):
		_add_hair(HAIR_COLORS[hair], female)


## 0 for a slim build through 1 for a heavy one, from weight for height.
static func build_amount(inches: int, pounds: int) -> float:
	var bmi := 703.0 * pounds / float(inches * inches)
	return clampf(inverse_lerp(SLIM_BMI, HEAVY_BMI, bmi), 0.0, 1.0)


## "5-08" as printed on the license, in inches.
static func height_inches(height: String) -> int:
	var parts := height.split("-")
	if parts.size() != 2:
		return REFERENCE_INCHES
	return int(parts[0]) * 12 + int(parts[1])


static func weight_pounds(weight: String) -> int:
	return maxi(int(weight), 1)


func _add_body() -> void:
	var neck_rings: Array[PackedVector3Array] = []
	for y: float in [-0.07, -0.11, -0.15, -0.18, -0.21]:
		neck_rings.append(_ring(y, -0.012, _neck, _neck * 1.05, _neck * 1.05, _HEAD_SQUARENESS))
	_add_mesh("Neck", _loft(neck_rings), SKIN.darkened(0.12))

	var rings: Array[PackedVector3Array] = []
	# Close together, for the collar lying on it to follow the same curve.
	var steps := 96
	for i in steps + 1:
		var y := lerpf(_TORSO_ROWS[0].x, _TORSO_ROWS[-1].x, float(i) / steps)
		var row := _torso_row(y)
		rings.append(_ring(y, 0.0, row.y, row.z, row.w, _BODY_SQUARENESS))
	_add_mesh("Shirt", _loft(rings), SHIRT)

	# An open collar: a V of skin with a flap of shirt either side.
	var point := Vector2(0.0, -0.248)
	_add_mesh("Throat", _patch(Vector2(-_neck * 1.1, -0.138), Vector2(_neck * 1.1, -0.138), point, point, 0.004), SKIN.darkened(0.12))
	for side: float in [-1.0, 1.0]:
		var flap := _patch(
			Vector2(side * (_neck + 0.006), -0.15),
			Vector2(side * (_neck + 0.06), -0.178),
			point,
			Vector2(side * 0.056, -0.282),
			0.013,
		)
		_add_mesh("Collar", flap, COLLAR)


## The shirt at a height, with the top kept around the neck however broad the shoulders.
func _torso_row(y: float) -> Vector4:
	var row := _row(_TORSO_ROWS, y)
	return Vector4(y, maxf(row.y * _broad, _neck * 1.12), maxf(row.z * _deep, _neck * 1.15), row.w * _deep)


func _add_face(hair: String, eyes: String, female: bool) -> void:
	var brow: Color = HAIR_COLORS.get(hair, HAIR_COLORS["BRN"]).darkened(0.3)
	var iris: Color = EYE_COLORS.get(eyes, EYE_COLORS["BRN"])
	for side: float in [-1.0, 1.0]:
		var x := side * 0.031
		var z := _face_z(x, 0.0)
		_add_blob("Eye white", Vector3(x, 0.0, z - 0.004), Vector3(0.0148, 0.0082, 0.006), Color(0.93, 0.92, 0.88))
		_add_blob("Iris", Vector3(x, 0.0, z + 0.0005), Vector3(0.0074, 0.0074, 0.0024), iris)
		_add_blob("Pupil", Vector3(x, 0.0, z + 0.0022), Vector3(0.0032, 0.0032, 0.0012), DARK)
		_add_blob("Eyelid", Vector3(x, 0.0066, z - 0.0005), Vector3(0.0165, 0.0029, 0.0052), SKIN.darkened(0.42))
		_add_blob("Eye bag", Vector3(x, -0.0098, z - 0.003), Vector3(0.0135, 0.0026, 0.004), SKIN.darkened(0.14))
		var brow_y := 0.021 if female else 0.0185
		var brow_h := 0.0016 if female else 0.0029
		_add_blob("Eyebrow", Vector3(side * 0.033, brow_y, _face_z(side * 0.033, brow_y) + 0.001), Vector3(0.0175, brow_h, 0.0035), brow, side * -0.12)

		var ear_y := -0.012
		var ear_x := _head_width(ear_y) + 0.002
		_add_blob("Ear", Vector3(side * ear_x, ear_y, -0.006), Vector3(0.0075, 0.03, 0.018), SKIN.darkened(0.05), side * -0.1)
		_add_blob("Ear inner", Vector3(side * (ear_x + 0.003), ear_y, -0.002), Vector3(0.0048, 0.019, 0.01), SKIN.darkened(0.3), side * -0.1)

	var nose_z := _face_z(0.0, -0.035)
	_add_blob("Nose bridge", Vector3(0.0, -0.018, _face_z(0.0, -0.018) + 0.001), Vector3(0.0082, 0.024, 0.0078), SKIN)
	_add_blob("Nose tip", Vector3(0.0, -0.039, nose_z + 0.0075), Vector3(0.0094, 0.0088, 0.0098), SKIN.lightened(0.04))
	for side: float in [-1.0, 1.0]:
		_add_blob("Nose wing", Vector3(side * 0.0098, -0.0425, nose_z + 0.0015), Vector3(0.0056, 0.0056, 0.0066), SKIN.darkened(0.05))
		_add_blob("Nostril", Vector3(side * 0.0056, -0.0472, nose_z + 0.0065), Vector3(0.0028, 0.0013, 0.0028), DARK)

	var lips := SKIN.lerp(LIPS, 0.85 if female else 0.55)
	var mouth_z := _face_z(0.0, -0.072)
	_add_blob("Mouth", Vector3(0.0, -0.0722, mouth_z + 0.0012), Vector3(0.0215, 0.0011, 0.0016), DARK.lerp(lips, 0.25))
	_add_blob("Upper lip", Vector3(0.0, -0.0695, mouth_z - 0.0006), Vector3(0.021, 0.0034, 0.0036), lips.darkened(0.08))
	_add_blob("Lower lip", Vector3(0.0, -0.0762, mouth_z - 0.0006), Vector3(0.0178, 0.0048, 0.0042), lips)


func _add_hair(color: Color, female: bool) -> void:
	_add_mesh("Hair", _loft(_hair_rings(_LONG_HAIR_BOTTOM if female else _SHORT_HAIR_BOTTOM)), color)
	# A sweep over the forehead so the top is not a plain cap.
	var side := -1.0 if female else 1.0
	_add_blob("Hair sweep", Vector3(side * 0.024, 0.079, 0.052), Vector3(0.064 * _upper_face, 0.021, 0.038), color, side * -0.28)
	if not female:
		_add_blob("Hair sweep", Vector3(side * -0.046, 0.067, 0.046), Vector3(0.038 * _upper_face, 0.017, 0.032), color, side * 0.42)


## The head's surface puffed out and drawn back behind the hairline, from the crown down
## to `bottom`. Below the cheeks it hangs straight, and it rounds off at the end.
func _hair_rings(bottom: float) -> Array[PackedVector3Array]:
	var rings: Array[PackedVector3Array] = []
	var steps := 44
	for i in steps + 1:
		var y := lerpf(_HEAD_ROWS[0].x, bottom, float(i) / steps)
		var row := _row(_HEAD_ROWS, maxf(y, _HEAD_ROWS[-1].x))
		var hanging := smoothstep(-0.02, -0.08, y)
		var width := lerpf(row.y * _face_scale(y), 0.08 * _upper_face, hanging) + _HAIR_THICKNESS
		var back := lerpf(row.w, 0.07, hanging) + _HAIR_THICKNESS
		var rounding := sqrt(clampf(inverse_lerp(bottom, bottom + 0.012, y), 0.05, 1.0))
		# Thicker over the crown, so it rises above the top of the head.
		var lift := _HAIR_THICKNESS * smoothstep(0.06, 0.112, y)
		var ring := _ring(y + lift, 0.0, width * rounding, row.z + _HAIR_THICKNESS, back * rounding, _HEAD_SQUARENESS)
		var limit := _hair_front(y)
		for j in ring.size():
			ring[j].z = minf(ring[j].z, limit)
		rings.append(ring)
	return rings


## The head's own surface, from the crown to the chin.
func _head_rings() -> Array[PackedVector3Array]:
	var rings: Array[PackedVector3Array] = []
	var steps := 44
	for i in steps + 1:
		var y := lerpf(_HEAD_ROWS[0].x, _HEAD_ROWS[-1].x, float(i) / steps)
		var row := _row(_HEAD_ROWS, y)
		rings.append(_ring(y, 0.0, row.y * _face_scale(y), row.z, row.w, _HEAD_SQUARENESS))
	return rings


func _hair_front(y: float) -> float:
	for i in range(1, _HAIR_FRONT.size()):
		if y >= _HAIR_FRONT[i].x:
			return lerpf(_HAIR_FRONT[i].y, _HAIR_FRONT[i - 1].y, inverse_lerp(_HAIR_FRONT[i].x, _HAIR_FRONT[i - 1].x, y))
	return _HAIR_FRONT[-1].y


## How wide the build makes the face at a height against the eyes.
func _face_scale(y: float) -> float:
	return lerpf(_upper_face, _lower_face, smoothstep(0.02, -0.08, y))


func _head_width(y: float) -> float:
	return _row(_HEAD_ROWS, y).y * _face_scale(y)


## Where the front of the head is, at a place on the face.
func _face_z(x: float, y: float) -> float:
	var row := _row(_HEAD_ROWS, y)
	var across := clampf(absf(x) / (row.y * _face_scale(y)), 0.0, 1.0)
	return row.z * pow(1.0 - pow(across, _HEAD_SQUARENESS), 1.0 / _HEAD_SQUARENESS)


## A table's row at any height, smoothly between the rows listed. Heights run downward.
func _row(rows: Array[Vector4], y: float) -> Vector4:
	for i in range(1, rows.size()):
		if y >= rows[i].x:
			var t := inverse_lerp(rows[i - 1].x, rows[i].x, y)
			var before := rows[maxi(i - 2, 0)]
			var after := rows[mini(i + 1, rows.size() - 1)]
			return Vector4(
				y,
				cubic_interpolate(rows[i - 1].y, rows[i].y, before.y, after.y, t),
				cubic_interpolate(rows[i - 1].z, rows[i].z, before.z, after.z, t),
				cubic_interpolate(rows[i - 1].w, rows[i].w, before.w, after.w, t),
			)
	return rows[-1]


func _ring(y: float, z: float, width: float, front: float, back: float, squareness: float) -> PackedVector3Array:
	var ring := PackedVector3Array()
	var power := 2.0 / squareness
	for j in _SEGMENTS:
		var angle := TAU * j / _SEGMENTS
		var across := signf(cos(angle)) * pow(absf(cos(angle)), power)
		var along := signf(sin(angle)) * pow(absf(sin(angle)), power)
		ring.append(Vector3(across * width, y, z + along * (front if along > 0.0 else back)))
	return ring


## A closed skin through rings running downward, each with the same number of points.
func _loft(rings: Array[PackedVector3Array]) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings.size() - 1:
		for j in _SEGMENTS:
			var next := (j + 1) % _SEGMENTS
			_add_triangle(tool, rings[i][j], rings[i + 1][j], rings[i][next])
			_add_triangle(tool, rings[i][next], rings[i + 1][j], rings[i + 1][next])
	# Close the bottom.
	var last := rings[-1]
	var middle := Vector3.ZERO
	for point in last:
		middle += point
	middle /= last.size()
	for j in _SEGMENTS:
		_add_triangle(tool, last[j], middle, last[(j + 1) % _SEGMENTS])
	tool.generate_normals()
	return tool.commit()


func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)


## A four-cornered piece laid over the front of the shirt, following its curve. The corners
## are in x and y, going top left, top right, bottom left, bottom right.
func _patch(a: Vector2, b: Vector2, c: Vector2, d: Vector2, lift: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 8
	for i in cells:
		for j in cells:
			var top_left := _on_shirt(a, b, c, d, float(j) / cells, float(i) / cells, lift)
			var top_right := _on_shirt(a, b, c, d, float(j + 1) / cells, float(i) / cells, lift)
			var low_left := _on_shirt(a, b, c, d, float(j) / cells, float(i + 1) / cells, lift)
			var low_right := _on_shirt(a, b, c, d, float(j + 1) / cells, float(i + 1) / cells, lift)
			_add_triangle(tool, top_left, top_right, low_left)
			_add_triangle(tool, top_right, low_right, low_left)
	tool.generate_normals()
	return tool.commit()


func _on_shirt(a: Vector2, b: Vector2, c: Vector2, d: Vector2, across: float, down: float, lift: float) -> Vector3:
	var at := a.lerp(b, across).lerp(c.lerp(d, across), down)
	var row := _torso_row(at.y)
	var out := clampf(absf(at.x) / row.y, 0.0, 1.0)
	return Vector3(at.x, at.y, row.z * pow(1.0 - pow(out, _BODY_SQUARENESS), 1.0 / _BODY_SQUARENESS) + lift)


func _add_mesh(part: String, mesh: Mesh, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	add_child(instance)
	return instance


## A squashed sphere for a facial feature, tilted in the plane of the face.
func _add_blob(part: String, at: Vector3, radii: Vector3, color: Color, tilt: float = 0.0) -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 20
	sphere.rings = 10
	var instance := _add_mesh(part, sphere, color)
	instance.position = at
	instance.rotation.z = tilt
	instance.scale = radii * 2.0
