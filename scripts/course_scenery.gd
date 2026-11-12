extends RefCounted

## What stands on and beside Street Rod 2's Mulholland drive and Aqueduct race, from the `scenery`
## list of their `.trk` files. Trees, poles, road marks and the finish are street_scenery.gd's. These
## are the rest, built from plain shapes in place of its sprites. Unlike the street drag, some of
## these stop a car, as they do in Street Rod 2: `build` answers with where they are, for the rival.

const _StreetScenery := preload("res://scripts/street_scenery.gd")
const _TrackSides := preload("res://scripts/track_sides.gd")
const _Sawhorse := preload("res://scripts/sawhorse.gd")

const _LEAVES := Color(0.16, 0.5, 0.13, 1)
const _BUSH := Color(0.08, 0.36, 0.08, 1)
const _ROCK := Color(0.52, 0.52, 0.5, 1)
const _POST_WHITE := Color(0.94, 0.94, 0.92, 1)
const _POST_BAND := Color(0.15, 0.2, 0.75, 1)
const _SIGN_YELLOW := Color(0.95, 0.8, 0.1, 1)
const _SIGN_WHITE := Color(0.95, 0.95, 0.93, 1)
const _SIGN_BLACK := Color(0.03, 0.03, 0.03, 1)
const _SIGN_POST := Color(0.6, 0.6, 0.6, 1)
const _GRAVEL := Color(0.36, 0.36, 0.34, 1)
const _JOINT := Color(0.08, 0.08, 0.08, 1)
const _GUTTER := Color(0.2, 0.2, 0.2, 1)
const _DRAIN := Color(0.26, 0.26, 0.26, 1)
const _STAIN := Color(0.04, 0.04, 0.04, 1)
const _OBSTACLE := Color(0.22, 0.22, 0.22, 1)

const _LINE_M := 5.0
const _SIGN_OUT_M := 0.6
const _SIGN_HIGH := 2.3
const _SIGN_SIZE := 1.15
const _ROAD_BOULDER_W := 1.5
const _ROAD_BOULDER_H := 0.95
const _ROCKFALL_REACH := 2.0
const _SLAB_HALF := 613.0 * 8.0 / 1800.0
const _SLAB_H := 340.0 / 7.0 * 8.0 / 1800.0
const _FIN_W := 0.3
const _FIN_H := 340.0 * 8.0 / 1800.0
const _OBSTACLE_HIT_H := 1.6
const _DRAIN_DEEP := 0.25


static func build(track: Node3D, items: Array[Dictionary]) -> Dictionary:
	var root := Node3D.new()
	root.name = "CourseScenery"
	track.add_child(root)
	var body := StaticBody3D.new()
	body.name = "CourseObstacles"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"track_obstacle", true)
	root.add_child(body)
	var blocks: Array[Dictionary] = []
	var rocks: Array[Vector3] = []
	var boxes := {}
	var rock_boxes: Array[Transform3D] = []
	var signs: Array[Dictionary] = []
	var round_shapes := {"shrub": [], "bush": []}
	var posts: Array[Transform3D] = []
	var bands: Array[Transform3D] = []
	var gutters: Array[Dictionary] = []
	for item: Dictionary in items:
		var kind := str(item["kind"])
		var at := Vector3(float(item["x"]), 0.0, float(item["y"]))
		var here: Dictionary = track.closest_sample(at)
		var yaw := float(here["yaw"])
		var lateral := float(here["lateral"])
		var turn := Basis(Vector3.UP, yaw)
		var along := Vector3(sin(yaw), 0.0, cos(yaw))
		# Measured from the nearest point, so a thing in the run-in sits before the start line.
		# The nearest point alone puts it on the line, where a rival steers round it from the off.
		var off: Vector3 = at - (here["position"] as Vector3)
		var s := float(here["s"]) + Vector2(off.x, off.z).dot(Vector2(along.x, along.z))
		var ground: Vector3 = _StreetScenery._ground(track, at.x, at.z)
		match kind:
			"shrub", "bush":
				var spot := Vector2(at.x, at.z)
				var size := lerpf(0.8, 1.2, _StreetScenery._spot_random(spot, 3.0))
				var shape := Vector3(1.3, 0.6, 1.3) if kind == "shrub" else Vector3(1.8, 1.5, 1.8)
				var list: Array = round_shapes[kind]
				list.append(Transform3D(Basis.IDENTITY.scaled(shape * size), ground + Vector3(0.0, shape.y * size * 0.55, 0.0)))
			"post":
				posts.append(Transform3D(turn.scaled(Vector3(0.14, 1.0, 0.14)), ground + Vector3(0.0, 0.5, 0.0)))
				bands.append(Transform3D(turn.scaled(Vector3(0.15, 0.14, 0.15)), ground + Vector3(0.0, 0.82, 0.0)))
			"rock", "boulder_side":
				var radius := 0.75 if kind == "rock" else 0.5
				rock_boxes.append(_rock_at(ground, radius, Vector2(at.x, at.z)))
			"rockfall_left", "rockfall_right":
				var inward := -1.0 if kind == "rockfall_left" else 1.0
				_add_rockfall(rock_boxes, body, ground, turn, along, inward, yaw, s, lateral, blocks)
			"road_boulder":
				rock_boxes.append(_rock_at(ground, _ROAD_BOULDER_W * 0.5, Vector2(at.x, at.z)))
				_add_hit_box(body, Vector3(_ROAD_BOULDER_W, _OBSTACLE_HIT_H, _ROAD_BOULDER_W), Transform3D(turn, ground + Vector3.UP * _OBSTACLE_HIT_H * 0.5))
				blocks.append({"s": s - _ROAD_BOULDER_W, "to": s + _ROAD_BOULDER_W, "low": lateral - _ROAD_BOULDER_W * 0.5, "high": lateral + _ROAD_BOULDER_W * 0.5})
			"road_rock":
				rock_boxes.append(Transform3D(turn.scaled(Vector3(1.0, 0.18, 0.7)), ground + Vector3.UP * 0.08))
				rocks.append(ground)
			"barricade":
				_add_sawhorse(track, root, ground, yaw, lateral, s, blocks)
			"road_work_sign", "speed_sign", "narrows_sign", "curves_sign", "curves_back_sign", "chevron_left", "chevron_right":
				signs.append({"kind": kind, "foot": ground, "yaw": yaw, "lateral": lateral})
			"joint":
				_add_joint(boxes, ground, yaw)
			"gutter":
				gutters.append({"from": float(item["y"]), "to": float(item.get("to", item["y"]))})
			"drain":
				_add_drain(boxes, body, ground, yaw, at, s, blocks)
			"stain":
				_box_into(boxes, _STAIN, Transform3D(turn.scaled(Vector3(1.6, 0.02, 2.6)), ground + Vector3.UP * 0.02))
			"slab":
				var center := ground + along * (_LINE_M * 0.5) + Vector3.UP * (_SLAB_H * 0.5)
				_box_into(boxes, _OBSTACLE, Transform3D(turn.scaled(Vector3(_SLAB_HALF * 2.0, _SLAB_H, _LINE_M)), center))
				_add_hit_box(body, Vector3(_SLAB_HALF * 2.0, _OBSTACLE_HIT_H, _LINE_M), Transform3D(turn, ground + along * (_LINE_M * 0.5) + Vector3.UP * (_OBSTACLE_HIT_H * 0.5)))
				blocks.append({"s": s, "to": s + _LINE_M, "low": -_SLAB_HALF, "high": _SLAB_HALF})
			"fin":
				var fin_center := ground + along * (_LINE_M * 0.5) + Vector3.UP * (_FIN_H * 0.5)
				var fin_size := Vector3(_FIN_W, _FIN_H, _LINE_M)
				_box_into(boxes, _OBSTACLE, Transform3D(turn.scaled(fin_size), fin_center))
				_add_hit_box(body, fin_size, Transform3D(turn, fin_center))
				blocks.append({"s": s, "to": s + _LINE_M, "low": lateral - _FIN_W * 0.5, "high": lateral + _FIN_W * 0.5})
	_add_round_bushes(root, "Shrubs", _LEAVES, round_shapes["shrub"])
	_add_round_bushes(root, "Bushes", _BUSH, round_shapes["bush"])
	_TrackSides._add_unit_boxes(root, "Posts", posts, _POST_WHITE)
	_TrackSides._add_unit_boxes(root, "PostBands", bands, _POST_BAND)
	_add_rocks(root, rock_boxes)
	for color: Color in boxes:
		var list: Array[Transform3D] = []
		list.assign(boxes[color])
		_TrackSides._add_unit_boxes(root, "Marks", list, color)
	_add_gutters(track, root, gutters)
	for sign: Dictionary in signs:
		_add_sign(root, sign)
	blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))
	return {"blocks": blocks, "rocks": rocks}


static func _box_into(boxes: Dictionary, color: Color, xform: Transform3D) -> void:
	if not boxes.has(color):
		boxes[color] = []
	var list: Array = boxes[color]
	list.append(xform)


static func _add_hit_box(body: StaticBody3D, size: Vector3, xform: Transform3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var hit := CollisionShape3D.new()
	hit.shape = shape
	hit.transform = xform
	body.add_child(hit)


static func _rock_at(ground: Vector3, radius: float, spot: Vector2) -> Transform3D:
	var turn := Basis(Vector3.UP, TAU * _StreetScenery._spot_random(spot, 5.0))
	var size := Vector3(radius * 2.0, radius * 1.3, radius * 1.7)
	return Transform3D(turn.scaled(size), ground + Vector3.UP * (radius * 0.5))


static func _add_rocks(root: Node3D, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _StreetScenery._material(_ROCK)
	_StreetScenery._add_multimesh(root, "Rocks", mesh, xforms, true)


static func _add_round_bushes(root: Node3D, node_name: String, color: Color, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = _StreetScenery._material(color)
	var typed: Array[Transform3D] = []
	typed.assign(xforms)
	_StreetScenery._add_multimesh(root, node_name, mesh, typed, true)


## Street Rod 2's rocks fallen from a hillside, reaching about 2 m into the road from its edge.
static func _add_rockfall(
	rock_boxes: Array[Transform3D],
	body: StaticBody3D,
	ground: Vector3,
	turn: Basis,
	along: Vector3,
	inward: float,
	yaw: float,
	s: float,
	lateral: float,
	blocks: Array[Dictionary]
) -> void:
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var spots: Array[Vector3] = [
		Vector3(0.3, 0.0, 0.0), Vector3(1.0, 0.0, 1.6), Vector3(1.7, 0.0, 0.2),
		Vector3(0.6, 0.0, 3.2), Vector3(1.4, 0.0, 3.8),
	]
	for k in spots.size():
		var spot := spots[k]
		var radius := 0.85 if k % 2 == 1 else 0.6
		var foot := ground + across * (inward * spot.x) + along * spot.z
		rock_boxes.append(_rock_at(foot, radius, Vector2(foot.x, foot.z)))
	var center := ground + across * (inward * _ROCKFALL_REACH * 0.5) + along * (_LINE_M * 0.5) + Vector3.UP * (_OBSTACLE_HIT_H * 0.5)
	_add_hit_box(body, Vector3(_ROCKFALL_REACH, _OBSTACLE_HIT_H, _LINE_M), Transform3D(turn, center))
	var inner := lateral + inward * _ROCKFALL_REACH
	blocks.append({"s": s, "to": s + _LINE_M, "low": minf(lateral, inner), "high": maxf(lateral, inner)})


## A sawhorse can be driven through, at a price, so a rival goes around it only if it can.
static func _add_sawhorse(track: Node3D, root: Node3D, ground: Vector3, yaw: float, lateral: float, s: float, blocks: Array[Dictionary]) -> void:
	var inward := -signf(lateral)
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var horse: Node3D = _Sawhorse.new()
	root.add_child(horse)
	horse.setup(track, ground + across * (inward * _Sawhorse.REACH * 0.5), yaw)
	var inner := lateral + inward * _Sawhorse.REACH
	blocks.append({"s": s - 1.0, "to": s + 1.0, "low": minf(lateral, inner), "high": maxf(lateral, inner), "soft": true})


## A seam across the floor and up both banks.
static func _add_joint(boxes: Dictionary, ground: Vector3, yaw: float) -> void:
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var floor_half: float = _TrackSides.AQUEDUCT_FLOOR_HALF
	var top_lat: float = floor_half + _TrackSides.AQUEDUCT_BANK_RUN
	var center := Vector3(ground.x, 0.0, ground.z)
	var lift := Vector3.UP * 0.02
	var a := center + across * floor_half + lift
	var b := center - across * floor_half + lift
	_box_into(boxes, _JOINT, _thin_beam(a, b))
	var bank_top := Vector3.UP * _TrackSides.AQUEDUCT_BANK_HIGH
	_box_into(boxes, _JOINT, _thin_beam(a, center + across * top_lat + bank_top + lift))
	_box_into(boxes, _JOINT, _thin_beam(b, center - across * top_lat + bank_top + lift))


static func _thin_beam(a: Vector3, b: Vector3) -> Transform3D:
	var beam: Transform3D = _TrackSides._beam(a, b)
	var scale_down := 0.06 / _TrackSides._TRUSS_BEAM
	var flat := Basis(beam.basis.x * scale_down, beam.basis.y * (0.02 / _TrackSides._TRUSS_BEAM), beam.basis.z)
	return Transform3D(flat, beam.origin)


## Street Rod 2's dark mark on a bank, a line long, which ends the race if the car touches it.
static func _add_drain(boxes: Dictionary, body: StaticBody3D, ground: Vector3, yaw: float, at: Vector3, s: float, blocks: Array[Dictionary]) -> void:
	var side := signf(at.x)
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var along := Vector3(sin(yaw), 0.0, cos(yaw))
	var run: float = _TrackSides.AQUEDUCT_BANK_RUN
	var high: float = _TrackSides.AQUEDUCT_BANK_HIGH
	var floor_half: float = _TrackSides.AQUEDUCT_FLOOR_HALF
	var center_lat := floor_half + run * 0.5
	var center := Vector3(ground.x - at.x, 0.0, ground.z) + across * (side * center_lat) + along * (_LINE_M * 0.5) + Vector3.UP * (high * 0.5)
	var slope := atan2(high, run)
	var lean := Basis(along, -side * slope)
	var basis := lean * Basis(Vector3.UP, yaw)
	var size := Vector3(sqrt(run * run + high * high) * 0.72, _DRAIN_DEEP, _LINE_M)
	_box_into(boxes, _DRAIN, Transform3D(basis.scaled(size), center))
	_add_hit_box(body, size, Transform3D(basis, center))
	var low := minf(side * floor_half, side * (floor_half + run))
	var high_lat := maxf(side * floor_half, side * (floor_half + run))
	blocks.append({"s": s, "to": s + _LINE_M, "low": low, "high": high_lat})


## The channel's dark middle. A gap in it is where Street Rod 2's table has a line with bit 1.
static func _add_gutters(track: Node3D, root: Node3D, gutters: Array[Dictionary]) -> void:
	const WIDTH := 80.0 * 8.0 / 1800.0
	const PIECE := 2.5
	var xforms: Array[Transform3D] = []
	for gutter: Dictionary in gutters:
		var z := float(gutter["from"])
		var finish := float(gutter["to"])
		while z < finish:
			var length := minf(PIECE, finish - z)
			var center: Vector3 = _StreetScenery._ground(track, 0.0, z + length * 0.5)
			xforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(WIDTH, 0.02, length)), center + Vector3.UP * 0.015))
			z += length
	_TrackSides._add_unit_boxes(root, "Gutter", xforms, _GUTTER)


static func _add_sign(root: Node3D, sign: Dictionary) -> void:
	var kind := str(sign["kind"])
	var yaw := float(sign["yaw"])
	var lateral := float(sign["lateral"])
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var foot: Vector3 = sign["foot"]
	var holder := Node3D.new()
	holder.name = kind
	holder.position = foot + across * (signf(lateral) * _SIGN_OUT_M)
	holder.rotation.y = yaw
	root.add_child(holder)
	var post := _StreetScenery._material(_SIGN_POST)
	_StreetScenery._add_box(holder, Vector3(0.07, _SIGN_HIGH, 0.07), post, Vector3(0.0, _SIGN_HIGH * 0.5, 0.0))
	var white_panel := kind == "speed_sign" or kind == "narrows_sign"
	var panel := _StreetScenery._material(_SIGN_WHITE if white_panel else _SIGN_YELLOW)
	var black := _StreetScenery._material(_SIGN_BLACK)
	var face := Vector3(0.0, _SIGN_HIGH, 0.0)
	var front := -0.05
	match kind:
		"chevron_left", "chevron_right":
			_StreetScenery._add_box(holder, Vector3(_SIGN_SIZE, _SIGN_SIZE * 0.85, 0.04), panel, face)
			# The driver looks along +Z, with their left at +X.
			var pointing := 1.0 if kind == "chevron_left" else -1.0
			for rise: float in [-1.0, 1.0]:
				var arm := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = Vector3(0.62, 0.2, 0.02)
				mesh.material = black
				arm.mesh = mesh
				arm.position = face + Vector3(pointing * 0.02, rise * 0.17, front)
				arm.rotation.z = rise * pointing * deg_to_rad(-40.0)
				holder.add_child(arm)
		"curves_sign", "curves_back_sign":
			_add_diamond(holder, panel, face)
			var flip := 1.0 if kind == "curves_sign" else -1.0
			for k in 3:
				var bend := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = Vector3(0.14, 0.34, 0.02)
				mesh.material = black
				bend.mesh = mesh
				bend.position = face + Vector3(flip * (float(k) - 1.0) * 0.1 * (1.0 if k != 1 else 0.0), (float(k) - 1.0) * 0.26, front)
				bend.rotation.z = flip * deg_to_rad(35.0 if k == 1 else -25.0)
				holder.add_child(bend)
		"road_work_sign":
			_add_diamond(holder, panel, face)
			_add_words(holder, "ROAD\nWORK\nAHEAD", face + Vector3(0.0, 0.0, front), 0.0046)
		"speed_sign":
			_StreetScenery._add_box(holder, Vector3(_SIGN_SIZE * 0.82, _SIGN_SIZE * 1.05, 0.04), panel, face)
			_add_words(holder, "SPEED\n35\nLIMIT", face + Vector3(0.0, 0.0, front), 0.0052)
		"narrows_sign":
			_StreetScenery._add_box(holder, Vector3(_SIGN_SIZE * 0.82, _SIGN_SIZE, 0.04), panel, face)
			for end: float in [-1.0, 1.0]:
				_StreetScenery._add_box(holder, Vector3(0.1, 0.84, 0.02), black, face + Vector3(end * 0.17, 0.0, front))


static func _add_diamond(holder: Node3D, panel: Material, center: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_SIGN_SIZE * 0.82, _SIGN_SIZE * 0.82, 0.04)
	mesh.material = panel
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	mi.rotation.z = PI * 0.25
	holder.add_child(mi)


static func _add_words(holder: Node3D, words: String, at: Vector3, pixel: float) -> void:
	var label := Label3D.new()
	label.text = words
	label.font_size = 48
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = Color.BLACK
	label.shaded = false
	label.double_sided = false
	label.rotation.y = PI
	label.position = at
	holder.add_child(label)
