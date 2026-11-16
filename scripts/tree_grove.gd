extends Node3D

## Every tree of one kind in a scene, drawn together, each with a solid trunk. A car that hits a
## trunk slower than the tree's snap speed is stopped by it like any barrier (wall_scrape.gd). At
## the snap speed or more the trunk breaks: the car goes on with some speed and harm taken off,
## the tree leaves the shared drawing, a stump stays, and the rest falls the way the car was going
## and lies as a log that stops a car. Rivals on a race track steer round a log on the road. A
## broken tree stays broken until the scene is built again.

const _Sounds := preload("res://scripts/shop_sounds.gd")

## Speed into the trunk that snaps it, in m/s, by kind. Bare trees go easily, big ones only fast.
const SNAP_MPS := {"bare_tree": 5.0, "tree": 9.0, "big_tree": 16.0}
## What going through costs the car, as speed lost and as the change of speed charged as damage
## (car_damage.gd: 1.5 is free, 14 totals). Less than a hit just under the snap speed costs, as
## the tree gives way.
const SNAP_COST_MPS := {"bare_tree": 3.0, "tree": 5.5, "big_tree": 9.5}
## Height of the stump above the ground.
const STUMP_M := 0.5
## How fast a broken tree starts to tip, per m/s of the hit, and the least and most, in rad/s.
const _TIP_PER_MPS := 0.06
const _TIP_MIN := 0.25
const _TIP_MAX := 1.2
## Share of the fall's turning speed that bounces back when the crown lands.
const _BOUNCE := 0.2
const _GRAVITY := 9.8
## How far street_scenery.gd sets a tree's foot into the ground.
const _SINK_M := 0.15
## A log is a block for rivals where it lies this low, and this near the middle of the road.
const _LOG_BLOCK_UNDER_M := 1.3
const _LOG_BLOCK_ROAD_M := 8.0

var kind := "tree"
## The race track, to tell rivals about logs, or null.
var track: Node3D = null

var _height := 5.5
var _trunk_radius := 0.22
var _trunk_mesh: Mesh
var _crown_mesh: Mesh
var _leaf_mesh: Mesh
var _crowns: Array[Transform3D] = []
var _plants: Array[Transform3D] = []
var _seeds := PackedFloat32Array()
var _greens: Array[Color] = []
var _trunks: MultiMesh
var _crown_shadows: MultiMesh
var _leaves: MultiMesh
var _bodies: Array[StaticBody3D] = []
var _broken := PackedByteArray()
var _falls: Array[Dictionary] = []


## `plants` is where each tree stands and how it is turned and sized; `seeds` picks its bark and
## `greens` its leaves' color, in linear light. `crowns` are the crown shapes in a tree's own
## space, and `crown_mesh` casts their shadows.
func setup(
	tree_kind: String,
	height: float,
	trunk_radius: float,
	trunk_mesh: Mesh,
	crown_mesh: Mesh,
	leaf_mesh: Mesh,
	crowns: Array[Transform3D],
	plants: Array[Transform3D],
	seeds: PackedFloat32Array,
	greens: Array[Color]
) -> void:
	kind = tree_kind
	_height = height
	_trunk_radius = trunk_radius
	_trunk_mesh = trunk_mesh
	_crown_mesh = crown_mesh
	_leaf_mesh = leaf_mesh
	_crowns = crowns
	_plants = plants
	_seeds = seeds
	_greens = greens
	_broken.resize(plants.size())
	_broken.fill(0)
	_trunks = _multimesh("Trunks", trunk_mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, true)
	_crown_shadows = _multimesh("Crowns", crown_mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, false)
	_leaves = _multimesh("Leaves", leaf_mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, false)
	_leaves.use_colors = true
	_trunks.instance_count = plants.size()
	_crown_shadows.instance_count = plants.size() * crowns.size()
	_leaves.instance_count = plants.size()
	for i in plants.size():
		var plant := plants[i]
		_trunks.set_instance_transform(i, plant * _trunk_center())
		_trunks.set_instance_custom_data(i, Color(seeds[i], second_seed(seeds[i]), 0.0, 0.0))
		_leaves.set_instance_transform(i, plant)
		_leaves.set_instance_color(i, greens[i])
		for c in crowns.size():
			_crown_shadows.set_instance_transform(i * crowns.size() + c, plant * crowns[c])
		_bodies.append(_trunk_body(i))
	set_physics_process(false)


## The bark shader's second number for a tree, from its first.
static func second_seed(seed_value: float) -> float:
	return fposmod(seed_value * 7.13 + 0.31, 1.0)


## Called by wall_scrape.gd when a car presses `into` m/s against tree `index`'s trunk, going
## along `travel`. Breaks the tree if that's fast enough, and answers what going through costs the
## car; -1 if the tree stands.
func try_break(index: int, into: float, travel: Vector3, car: PhysicsBody3D) -> float:
	if index < 0 or index >= _plants.size() or _broken[index] == 1:
		return -1.0
	if into < float(SNAP_MPS[kind]):
		return -1.0
	_break(index, into, travel, car)
	return float(SNAP_COST_MPS[kind])


func _break(index: int, into: float, travel: Vector3, car: PhysicsBody3D) -> void:
	_broken[index] = 1
	var body := _bodies[index]
	body.collision_layer = 0
	body.queue_free()
	var plant := _plants[index]
	var gone := Transform3D(Basis.from_scale(Vector3.ZERO), plant.origin)
	_trunks.set_instance_transform(index, gone)
	_leaves.set_instance_transform(index, gone)
	for c in _crowns.size():
		_crown_shadows.set_instance_transform(index * _crowns.size() + c, gone)
	var size := plant.basis.get_scale().x
	var stump_h := STUMP_M + _SINK_M
	# The cut, in the tree's own units from its foot.
	var cut := stump_h / size
	var stump := MeshInstance3D.new()
	stump.name = "Stump%d" % index
	stump.mesh = _trunk_piece(0.0, cut)
	stump.transform = plant * Transform3D(Basis.IDENTITY, Vector3(0.0, cut * 0.5, 0.0))
	stump.set_instance_shader_parameter(&"tree_seed", _seeds[index])
	add_child(stump)
	var pivot := plant.origin + Vector3.UP * stump_h
	var fall := Node3D.new()
	fall.name = "Falling%d" % index
	fall.position = pivot
	add_child(fall)
	var tree := Node3D.new()
	tree.transform = Transform3D(plant.basis, plant.origin - pivot)
	fall.add_child(tree)
	var upper := MeshInstance3D.new()
	upper.mesh = _trunk_piece(cut, _height)
	upper.position = Vector3(0.0, (cut + _height) * 0.5, 0.0)
	upper.set_instance_shader_parameter(&"tree_seed", _seeds[index])
	tree.add_child(upper)
	var leaves := MeshInstance3D.new()
	leaves.mesh = _leaf_mesh
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# On its own the tree has no instance color, so its green goes in a copy of the material.
	var green := ((_leaf_mesh as ArrayMesh).surface_get_material(0) as ShaderMaterial).duplicate() as ShaderMaterial
	green.set_shader_parameter(&"color", _greens[index].linear_to_srgb())
	leaves.material_override = green
	tree.add_child(leaves)
	for crown: Transform3D in _crowns:
		var shadow := MeshInstance3D.new()
		shadow.mesh = _crown_mesh
		shadow.transform = crown
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		tree.add_child(shadow)
	var flat := Vector3(travel.x, 0.0, travel.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	_falls.append({
		"node": fall,
		"axis": Vector3.UP.cross(flat).normalized(),
		"angle": 0.0,
		"rate": clampf(into * _TIP_PER_MPS, _TIP_MIN, _TIP_MAX),
		"end": _rest_angle(size, stump_h),
		"length": (_height - cut) * size,
		"radius": _trunk_radius * 0.85 * size,
		"bounced": false,
		"car": weakref(car) if car != null else null,
	})
	_play(fall, 1.0)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	var k := _falls.size() - 1
	while k >= 0:
		var fall: Dictionary = _falls[k]
		var angle := float(fall["angle"])
		var rate := float(fall["rate"])
		var length := float(fall["length"])
		rate += 1.5 * _GRAVITY / maxf(length, 0.5) * sin(angle) * delta
		angle += rate * delta
		var end := float(fall["end"])
		if angle >= end:
			angle = end
			if not bool(fall["bounced"]) and rate > 0.3:
				fall["bounced"] = true
				_play(fall["node"] as Node3D, 0.7)
				rate = -rate * _BOUNCE
			else:
				rate = 0.0
		fall["angle"] = angle
		fall["rate"] = rate
		var node := fall["node"] as Node3D
		node.basis = Basis(fall["axis"] as Vector3, angle)
		if rate == 0.0 and angle >= end:
			_lie_down(fall)
			_falls.remove_at(k)
		k -= 1
	if _falls.is_empty():
		set_physics_process(false)


## The fallen trunk becomes solid. The car that broke it can go through its own log, as it is
## already where the log lands; rivals on a race track are told to steer round it.
func _lie_down(fall: Dictionary) -> void:
	var node := fall["node"] as Node3D
	var length := float(fall["length"])
	var radius := float(fall["radius"])
	var along := node.basis * Vector3.UP
	var body := StaticBody3D.new()
	body.name = "Log"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"track_obstacle", true)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = maxf(radius, 0.12)
	cylinder.height = length
	shape.shape = cylinder
	body.add_child(shape)
	body.transform = Transform3D(node.basis, node.position + along * length * 0.5)
	add_child(body)
	var ref := fall["car"] as WeakRef
	var car := ref.get_ref() as PhysicsBody3D if ref != null else null
	if car != null:
		car.add_collision_exception_with(body)
	_block_rivals(node.position, along, length, radius)


func _block_rivals(base: Vector3, along: Vector3, length: float, radius: float) -> void:
	if track == null or not track.has_method(&"add_block") or not track.has_method(&"closest_sample"):
		return
	var min_s := INF
	var max_s := -INF
	var low := INF
	var high := -INF
	var step := 0.5
	var t := 0.0
	while t <= length:
		var point := base + along * t
		t += step
		if point.y - base.y + STUMP_M > _LOG_BLOCK_UNDER_M:
			continue
		var here: Dictionary = track.closest_sample(point)
		var lateral := float(here["lateral"])
		if absf(lateral) > _LOG_BLOCK_ROAD_M:
			continue
		var s := float(here["s"])
		min_s = minf(min_s, s)
		max_s = maxf(max_s, s)
		low = minf(low, lateral)
		high = maxf(high, lateral)
	if is_inf(min_s):
		return
	track.call(&"add_block", {"s": min_s - radius - 1.0, "to": max_s + radius + 1.0, "low": low - radius, "high": high + radius})


## How far a tree tips before its crown is on the ground: the first crown, taken as round, to
## touch the ground the trunk stands on. The pivot is the top of the stump.
func _rest_angle(size: float, stump_h: float) -> float:
	var best := PI * 0.5
	for crown: Transform3D in _crowns:
		var reach := crown.origin.y * size - stump_h
		var round_r := crown.basis.get_scale().x * 0.85 * size
		if reach <= 0.0:
			continue
		var c := clampf((round_r - STUMP_M) / reach, 0.0, 1.0)
		best = minf(best, acos(c))
	return clampf(best, 0.6, PI * 0.5)


## A piece of the trunk from `from` to `to` up it, in the tree's own units. Its bark lines up with
## the whole trunk's, and it darkens toward the crown as the whole trunk does.
func _trunk_piece(from: float, to: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = lerpf(_trunk_radius, _trunk_radius * 0.7, from / _height)
	mesh.top_radius = lerpf(_trunk_radius, _trunk_radius * 0.7, to / _height)
	mesh.height = to - from
	mesh.radial_segments = 6
	mesh.rings = 1
	var mat := ((_trunk_mesh as CylinderMesh).material as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"piece_from", from / _height)
	mat.set_shader_parameter(&"piece_to", to / _height)
	mesh.material = mat
	return mesh


func _trunk_center() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, _height * 0.5, 0.0))


func _trunk_body(index: int) -> StaticBody3D:
	var plant := _plants[index]
	var size := plant.basis.get_scale().x
	var body := StaticBody3D.new()
	body.name = "Trunk%d" % index
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"track_obstacle", true)
	body.set_meta(&"tree_index", index)
	body.position = plant.origin + Vector3.UP * _height * size * 0.5
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = _trunk_radius * size
	cylinder.height = _height * size
	shape.shape = cylinder
	body.add_child(shape)
	add_child(body)
	return body


func _multimesh(node_name: String, mesh: Mesh, shadows: GeometryInstance3D.ShadowCastingSetting, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = shadows
	add_child(mmi)
	return mm


func _play(at: Node3D, pitch: float) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _Sounds.stream("thud")
	sound.pitch_scale = pitch
	sound.finished.connect(sound.queue_free)
	at.add_child(sound)
	sound.play()
