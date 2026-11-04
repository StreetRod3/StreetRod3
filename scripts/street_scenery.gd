extends RefCounted

## What stands beside a `street` track, from the `scenery` list of its `.trk` file. Street Rod 2
## draws these as sprites and never tests a car against them, so nothing here has collision.

const _TRUNK := Color(0.33, 0.2, 0.11, 1)
const _LEAVES := Color(0.2, 0.46, 0.15, 1)
const _GANTRY_STEEL := Color(0.36, 0.24, 0.14, 1)
const _INSULATOR := Color(0.78, 0.78, 0.76, 1)
const _STRIPE := Color(0.92, 0.92, 0.88, 1)
## Street Rod 2 fills its finish line with color 15, which its race palette shows as yellow.
const _FINISH := Color(0.95, 0.85, 0.15, 1)
const _STREAK := Color(0.3, 0.3, 0.29, 1)
const _DARK_STREAK := Color(0.03, 0.03, 0.03, 1)
const _SIGN_BLUE := Color(0.03, 0.05, 0.55, 1)
const _SIGN_WHITE := Color(0.95, 0.95, 0.95, 1)

const _PAINT_RISE := 0.03
const _PAINT_THICK := 0.03
## Longest flat piece of paint. On a rise a longer one would cut through the road.
const _PAINT_PIECE := 2.5
const _DASH_WIDTH := 0.22
const _DASH_LENGTH := 5.0
const _STREAK_WIDTH := 0.3
const _STREAK_LENGTH := 4.0
const _DARK_STREAK_WIDTH := 0.5
const _DARK_STREAK_LENGTH := 2.0
const _FINISH_LENGTH := 5.0

## Trees sit a little into the ground, which is sunk under the road's height.
const _TREE_SINK := 0.15
const _POLE_HEIGHT := 7.5


static func build(track: Node3D, items: Array[Dictionary], road_width: float) -> void:
	var root := Node3D.new()
	root.name = "StreetScenery"
	track.add_child(root)
	var spots: Dictionary = {}
	for item: Dictionary in items:
		var kind := str(item["kind"])
		var list: Array[Vector2] = []
		list.assign(spots.get(kind, list))
		list.append(Vector2(float(item["x"]), float(item["y"])))
		spots[kind] = list
	_build_trees(track, root, _spots_of(spots, "tree"), 5.5, 0.22, 2.4, false)
	_build_trees(track, root, _spots_of(spots, "big_tree"), 7.5, 0.34, 3.3, false)
	_build_trees(track, root, _spots_of(spots, "bare_tree"), 6.5, 0.18, 1.0, true)
	_build_poles(track, root, _spots_of(spots, "pole"))
	_build_paint(track, root, "Dashes", _spots_of(spots, "dash"), _DASH_WIDTH, _DASH_LENGTH, 0.0, _STRIPE)
	_build_paint(track, root, "Finish", _spots_of(spots, "finish"), road_width, _FINISH_LENGTH, 0.0, _FINISH)
	_build_paint(track, root, "Streaks", _spots_of(spots, "streak"), _STREAK_WIDTH, _STREAK_LENGTH, _STREAK_WIDTH * 0.5, _STREAK)
	_build_paint(track, root, "DarkStreaks", _spots_of(spots, "dark_streak"), _DARK_STREAK_WIDTH, _DARK_STREAK_LENGTH, _DARK_STREAK_WIDTH * 0.5, _DARK_STREAK)
	for spot: Vector2 in _spots_of(spots, "gantry"):
		_build_gantry(track, root, spot, road_width)


static func _spots_of(spots: Dictionary, kind: String) -> Array[Vector2]:
	var list: Array[Vector2] = []
	list.assign(spots.get(kind, list))
	return list


static func _ground(track: Node3D, x: float, z: float) -> Vector3:
	return Vector3(x, float(track.surface_height(Vector3(x, 0.0, z))), z)


## The same spot always gives the same number, from 0 to 1, so trees don't all look alike.
static func _spot_random(spot: Vector2, salt: float) -> float:
	return fposmod(sin(spot.x * 12.9898 + spot.y * 78.233 + salt) * 43758.5453, 1.0)


static func _build_trees(
	track: Node3D,
	root: Node3D,
	spots: Array[Vector2],
	height: float,
	trunk_radius: float,
	crown_radius: float,
	bare: bool
) -> void:
	if spots.is_empty():
		return
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = trunk_radius * 0.7
	trunk_mesh.bottom_radius = trunk_radius
	trunk_mesh.height = height
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	trunk_mesh.material = _material(_TRUNK)
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.0
	crown_mesh.height = 2.0
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 5
	crown_mesh.material = _material(_LEAVES)
	var crowns := _bare_crowns(height, crown_radius) if bare else _full_crowns(height, crown_radius)
	var trunk_xforms: Array[Transform3D] = []
	var crown_xforms: Array[Transform3D] = []
	for spot: Vector2 in spots:
		var size := lerpf(0.88, 1.15, _spot_random(spot, 1.0))
		var turn := Basis(Vector3.UP, TAU * _spot_random(spot, 2.0)).scaled(Vector3(size, size, size))
		var foot := _ground(track, spot.x, spot.y) + Vector3(0.0, -_TREE_SINK, 0.0)
		var plant := Transform3D(turn, foot)
		trunk_xforms.append(plant * Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, 0.0)))
		for crown: Transform3D in crowns:
			crown_xforms.append(plant * crown)
	_add_multimesh(root, "Trunks", trunk_mesh, trunk_xforms, true)
	_add_multimesh(root, "Crowns", crown_mesh, crown_xforms, true)


## A wide flat crown and a smaller one off to the side, like Street Rod 2's round trees.
static func _full_crowns(height: float, radius: float) -> Array[Transform3D]:
	return [
		_crown(Vector3(0.0, height * 0.95, 0.0), radius, 0.72),
		_crown(Vector3(radius * 0.9, height * 0.72, 0.0), radius * 0.45, 0.7),
	]


## Small tufts spread over thin air, like Street Rod 2's sparse tree.
static func _bare_crowns(height: float, radius: float) -> Array[Transform3D]:
	return [
		_crown(Vector3(0.0, height * 1.02, 0.0), radius, 0.5),
		_crown(Vector3(radius * 1.7, height * 0.82, 0.3), radius * 0.8, 0.45),
		_crown(Vector3(-radius * 1.8, height * 0.76, -0.2), radius * 0.9, 0.42),
		_crown(Vector3(radius * 0.8, height * 0.6, -radius), radius * 0.6, 0.45),
		_crown(Vector3(-radius * 0.7, height * 0.55, radius), radius * 0.55, 0.45),
	]


static func _crown(center: Vector3, radius: float, flat: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3(radius, radius * flat, radius)), center)


static func _build_poles(track: Node3D, root: Node3D, spots: Array[Vector2]) -> void:
	if spots.is_empty():
		return
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.11
	pole_mesh.bottom_radius = 0.15
	pole_mesh.height = _POLE_HEIGHT
	pole_mesh.radial_segments = 6
	pole_mesh.rings = 1
	pole_mesh.material = _material(_TRUNK)
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(2.0, 0.1, 0.1)
	arm_mesh.material = _material(_TRUNK)
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.1, 0.16, 0.1)
	cap_mesh.material = _material(_INSULATOR)
	var pole_xforms: Array[Transform3D] = []
	var arm_xforms: Array[Transform3D] = []
	var cap_xforms: Array[Transform3D] = []
	for spot: Vector2 in spots:
		var foot := _ground(track, spot.x, spot.y) + Vector3(0.0, -_TREE_SINK, 0.0)
		pole_xforms.append(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, _POLE_HEIGHT * 0.5, 0.0)))
		for arm_y: float in [_POLE_HEIGHT - 0.5, _POLE_HEIGHT - 1.2]:
			arm_xforms.append(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, arm_y, 0.0)))
			for cap_x: float in [-0.85, -0.45, 0.45, 0.85]:
				cap_xforms.append(Transform3D(Basis.IDENTITY, foot + Vector3(cap_x, arm_y + 0.13, 0.0)))
	_add_multimesh(root, "Poles", pole_mesh, pole_xforms, true)
	_add_multimesh(root, "PoleArms", arm_mesh, arm_xforms, true)
	_add_multimesh(root, "PoleCaps", cap_mesh, cap_xforms, false)


## Flat pieces laid along +Z from each spot, pitched to the road. `outward` moves a piece away
## from the road's middle, so a spot on the edge lays it on the shoulder.
static func _build_paint(
	track: Node3D,
	root: Node3D,
	node_name: String,
	spots: Array[Vector2],
	width: float,
	length: float,
	outward: float,
	color: Color
) -> void:
	if spots.is_empty():
		return
	var pieces := maxi(int(ceil(length / _PAINT_PIECE)), 1)
	var piece_length := length / float(pieces)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, _PAINT_THICK, piece_length)
	var mat := _material(color)
	mat.roughness = 0.9
	mesh.material = mat
	var xforms: Array[Transform3D] = []
	for spot: Vector2 in spots:
		var x := spot.x + signf(spot.x) * outward
		for i in pieces:
			var near := _ground(track, x, spot.y + piece_length * float(i))
			var far := _ground(track, x, spot.y + piece_length * float(i + 1))
			var pitch := Basis(Vector3.RIGHT, -atan2(far.y - near.y, piece_length))
			xforms.append(Transform3D(pitch, (near + far) * 0.5 + Vector3(0.0, _PAINT_RISE, 0.0)))
	_add_multimesh(root, node_name, mesh, xforms, false)


## Street Rod 2's overhead highway sign. The driver comes along +Z and so sees its -Z face, with
## their left at +X: the arrow on the left, the route shield on the right.
static func _build_gantry(track: Node3D, root: Node3D, spot: Vector2, road_width: float) -> void:
	const POST_H := 6.2
	const POST_W := 0.26
	const PANEL := Vector3(5.6, 2.3, 0.1)
	var gantry := Node3D.new()
	gantry.name = "Gantry"
	gantry.position = _ground(track, 0.0, spot.y)
	root.add_child(gantry)
	var steel := _material(_GANTRY_STEEL)
	var post_x := road_width * 0.5 + 0.6
	_add_box(gantry, Vector3(POST_W, POST_H, POST_W), steel, Vector3(post_x, POST_H * 0.5 - _TREE_SINK, 0.0))
	_add_box(gantry, Vector3(POST_W, POST_H, POST_W), steel, Vector3(-post_x, POST_H * 0.5 - _TREE_SINK, 0.0))
	_add_box(gantry, Vector3(post_x * 2.0 + POST_W, POST_W, POST_W), steel, Vector3(0.0, POST_H - _TREE_SINK, 0.0))
	var panel_y := POST_H - _TREE_SINK - 0.6
	var face_z := -PANEL.z * 0.5 - POST_W * 0.5
	_add_box(gantry, PANEL, _material(_SIGN_BLUE), Vector3(0.0, panel_y, face_z))
	var white := _material(_SIGN_WHITE)
	var symbol_z := face_z - PANEL.z * 0.5 - 0.02
	var arrow_x := 1.45
	_add_box(gantry, Vector3(0.5, 0.95, 0.03), white, Vector3(arrow_x, panel_y - 0.45, symbol_z))
	_add_prism(gantry, Vector3(1.3, 0.85, 0.03), white, Vector3(arrow_x, panel_y + 0.45, symbol_z), false)
	var shield_x := -1.45
	_add_box(gantry, Vector3(1.2, 1.0, 0.03), white, Vector3(shield_x, panel_y + 0.2, symbol_z))
	_add_prism(gantry, Vector3(1.2, 0.5, 0.03), white, Vector3(shield_x, panel_y - 0.55, symbol_z), true)
	var route := Label3D.new()
	route.text = "69"
	route.font_size = 96
	route.pixel_size = 0.009
	route.outline_size = 0
	route.modulate = Color.BLACK
	route.shaded = false
	route.double_sided = false
	route.rotation.y = PI
	route.position = Vector3(shield_x, panel_y + 0.05, symbol_z - 0.02)
	gantry.add_child(route)


static func _add_box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)


static func _add_prism(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, point_down: bool) -> void:
	var prism := PrismMesh.new()
	prism.size = size
	prism.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = prism
	mi.position = pos
	if point_down:
		mi.rotation.z = PI
	parent.add_child(mi)


static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat


static func _add_multimesh(
	root: Node3D,
	node_name: String,
	mesh: Mesh,
	xforms: Array[Transform3D],
	shadows: bool
) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
