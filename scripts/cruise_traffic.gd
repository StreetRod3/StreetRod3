extends Node3D

## Cars on the city streets during a cruise. Each one keeps to the same side of the
## road as the player's own drive and picks a road at random when the street ends.
## Hitting one is the race's car bump: it shoves both cars, and the player takes damage.

const _TrafficCar := preload("res://scripts/traffic_car.gd")
const _TrackFile := preload("res://scripts/track_file.gd")
const _CarBump := preload("res://scripts/car_bump.gd")
const _ShopSounds := preload("res://scripts/shop_sounds.gd")

const _COUNT := 24
const _LOOK := 9.0
const _MAX_YAW := 1.15
## Streets this wide, curb to curb, get a lane off the center line.
const _TWO_LANE_HALF := 6.0
const _BODY_Y := 0.35

const _PAINTS: Array[Color] = [
	Color(0.74, 0.1, 0.08),
	Color(0.9, 0.87, 0.78),
	Color(0.07, 0.07, 0.08),
	Color(0.14, 0.28, 0.58),
	Color(0.16, 0.36, 0.18),
	Color(0.82, 0.68, 0.16),
	Color(0.42, 0.12, 0.16),
	Color(0.55, 0.58, 0.62),
]

var _edges: Array[Dictionary] = []
var _out: Dictionary = {}
var _cars: Array[CharacterBody3D] = []
var _bump: _CarBump = _CarBump.new()
var _prev_player := Vector3.ZERO
var _have_prev := false


func setup(track: Dictionary, avoid: Vector3, floor_mesh: MeshInstance3D, car_files: Array[String]) -> void:
	_build_graph(track)
	if car_files.is_empty() or _edges.is_empty():
		return
	_spawn(avoid, floor_mesh, car_files)


func _physics_process(delta: float) -> void:
	tick(delta, _player())


func tick(delta: float, player: Node3D) -> void:
	if delta <= 0.0 or _cars.is_empty():
		return
	var blockers := _blockers(delta, player)
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null:
			continue
		_drive(car, delta, blockers)
	for i in _cars.size():
		for j in range(i + 1, _cars.size()):
			_bump.resolve(_cars[i], _cars[j])
	if player != null and player.has_method(&"apply_car_bump") and not _player_wrecked(player):
		var hardest := 0.0
		for body: CharacterBody3D in _cars:
			var hit := _bump.resolve(player, body)
			hardest = maxf(hardest, hit.x)
			if player.has_method(&"take_hit"):
				player.call(&"take_hit", hit.x)
		if hardest > 1.5:
			_crunch(hardest)
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car != null:
			car.sync_speed()


func _player() -> Node3D:
	var parent := get_parent()
	if parent == null:
		return null
	var roam := parent.get_node_or_null("PlayerCar") as Node3D
	if roam != null:
		return roam
	return parent.get_node_or_null("Car") as Node3D


func _player_wrecked(player: Node3D) -> bool:
	return player.has_method(&"is_wrecked") and bool(player.call(&"is_wrecked"))


func _blockers(delta: float, player: Node3D) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null:
			continue
		found.append({
			"id": car.get_instance_id(),
			"center": car.center(),
			"speed": car.speed,
			"ghost": false,
		})
	if player == null:
		return found
	var center := player.global_position + player.global_transform.basis.z * 1.9
	var pace := 0.0
	if _have_prev:
		var step := Vector2(center.x - _prev_player.x, center.z - _prev_player.z)
		pace = minf(step.length() / delta, 80.0)
	_prev_player = center
	_have_prev = true
	found.append({
		"id": player.get_instance_id(),
		"center": center,
		"speed": pace,
		"ghost": not player.has_method(&"apply_car_bump"),
	})
	return found


func _drive(car: _TrafficCar, delta: float, blockers: Array[Dictionary]) -> void:
	if _off_road(car):
		_reacquire(car)
	if car.next_i < 0:
		car.next_i = _choose_next(car.edge_i)
	var center := car.center()
	var forward := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	var desired := car.cruise_mps
	var curb_target := 0.0
	var self_id := car.get_instance_id()
	for block: Dictionary in blockers:
		if int(block["id"]) == self_id:
			continue
		var other: Vector3 = block["center"]
		var gap := other - center
		var ahead := gap.dot(forward)
		var lateral := absf(forward.x * gap.z - forward.z * gap.x)
		var other_speed := float(block["speed"])
		if ahead > 0.4 and ahead < 16.0 and lateral < 2.6:
			var room := ahead - 5.0
			var cap := other_speed
			if room < 9.0:
				cap = minf(cap, maxf(room, 0.0) * 1.3)
			desired = minf(desired, maxf(cap, 0.0))
		elif ahead > 0.4 and ahead < 9.0 and lateral < 4.6:
			desired = minf(desired, maxf(ahead - 3.2, 0.0) * 1.5)
		elif bool(block["ghost"]) and ahead < -1.0 and ahead > -24.0 and lateral < 2.8:
			curb_target = 2.4
			if other_speed > car.speed - 0.5:
				desired = maxf(desired, minf(other_speed + 1.0, 22.0))
	car.curb = lerpf(car.curb, curb_target, 1.0 - exp(-2.6 * delta))
	var aim := _ahead(car.edge_i, car.along, car.next_i, _LOOK, car.lane_bias + car.curb)
	var flat := Vector2(aim.x - center.x, aim.z - center.z)
	var desired_yaw := car.rotation.y
	if flat.length_squared() > 0.36:
		desired_yaw = atan2(flat.x, flat.y)
	var err := angle_difference(car.rotation.y, desired_yaw)
	if absf(err) > 0.5:
		desired = minf(desired, 6.2)
	var yaw_rate := clampf(err * 2.6, -_MAX_YAW, _MAX_YAW) + car.spin
	car.spin = move_toward(car.spin, 0.0, 4.0 * delta)
	car.rotation.y += yaw_rate * delta
	forward = Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	var blend := 1.15 if car.loose > 0.0 else 3.4
	car.loose = maxf(car.loose - delta, 0.0)
	car.shove = car.shove.lerp(forward * maxf(desired, 0.0), 1.0 - exp(-blend * delta))
	var moved := car.shove * delta
	car.global_position += moved
	car.global_position.y = _BODY_Y
	car.roll_wheels(Vector2(moved.x, moved.z).length())
	_hold_lane(car, delta)
	var edge: Dictionary = _edges[car.edge_i]
	var dir: Vector3 = edge["dir"]
	var a: Vector3 = edge["a"]
	car.along = (car.center() - a).dot(dir)
	if car.along > float(edge["length"]) - 0.8:
		_enter(car, car.next_i)


func _hold_lane(car: _TrafficCar, delta: float) -> void:
	var edge: Dictionary = _edges[car.edge_i]
	var at := clampf(car.along, 0.0, float(edge["length"]))
	var lane_at := _point(edge, at, car.lane_bias + car.curb)
	var center := car.center()
	var pull := Vector3(lane_at.x - center.x, 0.0, lane_at.z - center.z)
	var dir: Vector3 = edge["dir"]
	pull -= dir * pull.dot(dir)
	if pull.length() > 12.0:
		return
	var hold := 0.35 if absf(car.spin) > 0.35 or car.loose > 0.0 else 1.6
	car.global_position += pull * minf(hold * delta, 0.4)
	car.global_position.y = _BODY_Y


func _off_road(car: _TrafficCar) -> bool:
	var edge: Dictionary = _edges[car.edge_i]
	return _gap(car.center(), edge) > float(edge["half"]) + 1.5


func _reacquire(car: _TrafficCar) -> void:
	var center := car.center()
	var forward := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	var best := car.edge_i
	var best_gap := 1000.0
	for i in _edges.size():
		var edge: Dictionary = _edges[i]
		var dir: Vector3 = edge["dir"]
		if dir.dot(forward) < 0.15:
			continue
		var gap := _gap(center, edge)
		if gap < best_gap:
			best_gap = gap
			best = i
	if best_gap > 24.0:
		return
	_enter(car, best)


func _enter(car: _TrafficCar, idx: int) -> void:
	if idx < 0 or idx >= _edges.size():
		idx = _choose_next(car.edge_i)
	car.edge_i = idx
	car.next_i = _choose_next(idx)
	var edge: Dictionary = _edges[idx]
	var a: Vector3 = edge["a"]
	var dir: Vector3 = edge["dir"]
	var along := (car.center() - a).dot(dir)
	car.along = clampf(along, 0.0, float(edge["length"]))


func _choose_next(edge_i: int) -> int:
	var edge: Dictionary = _edges[edge_i]
	var from_id := int(edge["from"])
	var to_id := int(edge["to"])
	var outs: Array = _out.get(to_id, [])
	var pool: Array[int] = []
	var back := -1
	for item: Variant in outs:
		var idx := int(item)
		var nxt: Dictionary = _edges[idx]
		if int(nxt["to"]) == from_id:
			back = idx
		else:
			pool.append(idx)
	if not pool.is_empty():
		return pool[randi() % pool.size()]
	if back >= 0:
		return back
	return edge_i


func _ahead(edge_i: int, along: float, next_i: int, dist: float, extra: float) -> Vector3:
	var edge: Dictionary = _edges[edge_i]
	var remain := float(edge["length"]) - along
	if dist <= remain or next_i < 0:
		return _point(edge, along + dist, extra)
	var nxt: Dictionary = _edges[next_i]
	return _point(nxt, dist - remain, extra)


func _point(edge: Dictionary, distance: float, extra: float) -> Vector3:
	var length := float(edge["length"])
	var at := clampf(distance, 0.0, length)
	var dir: Vector3 = edge["dir"]
	var right: Vector3 = edge["right"]
	var a: Vector3 = edge["a"]
	var half := float(edge["half"])
	var lane := clampf(float(edge["lane"]) + extra, 0.0, maxf(half - 1.35, 0.0))
	return a + dir * at + right * lane


func _gap(center: Vector3, edge: Dictionary) -> float:
	var a3: Vector3 = edge["a"]
	var b3: Vector3 = edge["b"]
	var a := Vector2(a3.x, a3.z)
	var b := Vector2(b3.x, b3.z)
	var p := Vector2(center.x, center.z)
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _build_graph(track: Dictionary) -> void:
	var nodes: Dictionary = track.get("nodes", {})
	var roads: Array = track.get("roads", [])
	for raw: Variant in roads:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var road: Dictionary = raw
		var from_id := int(road.get("from", -1))
		var to_id := int(road.get("to", -1))
		if not nodes.has(from_id) or not nodes.has(to_id):
			continue
		var a := _TrackFile.world_position(nodes[from_id])
		var b := _TrackFile.world_position(nodes[to_id])
		var span := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var length := span.length()
		if length < 1.0:
			continue
		var dir := span / length
		var half := maxf(float(road.get("width", 16.0)) * 0.5, 1.0)
		var lane := half * 0.46 if half >= _TWO_LANE_HALF else 0.0
		var idx := _edges.size()
		_edges.append({
			"from": from_id,
			"to": to_id,
			"a": a,
			"b": b,
			"dir": dir,
			"right": Vector3(-dir.z, 0.0, dir.x),
			"length": length,
			"half": half,
			"lane": lane,
		})
		if not _out.has(from_id):
			var fresh: Array[int] = []
			_out[from_id] = fresh
		(_out[from_id] as Array).append(idx)


func _spawn(avoid: Vector3, floor_mesh: MeshInstance3D, car_files: Array[String]) -> void:
	var long: Array[int] = []
	for i in _edges.size():
		if float((_edges[i] as Dictionary).get("length", 0.0)) >= 22.0:
			long.append(i)
	if long.is_empty():
		return
	var avoid_flat := Vector2(avoid.x, avoid.z)
	var taken: Array[Vector3] = []
	var placed := 0
	var tries := 0
	while placed < _COUNT and tries < 600:
		tries += 1
		var idx: int = long[randi() % long.size()]
		var edge: Dictionary = _edges[idx]
		var length := float(edge["length"])
		var along := randf_range(8.0, maxf(length - 8.0, 8.0))
		var bias := randf_range(-0.35, 0.35)
		var spot := _point(edge, along, bias)
		var flat := Vector2(spot.x, spot.z)
		if flat.distance_to(avoid_flat) < 18.0:
			continue
		var crowded := false
		for prev: Vector3 in taken:
			if Vector2(prev.x, prev.z).distance_to(flat) < 14.0:
				crowded = true
				break
		if crowded:
			continue
		var car := _TrafficCar.new()
		car.name = "TrafficCar%d" % placed
		add_child(car)
		var paint: Color = _PAINTS[randi() % _PAINTS.size()]
		var pace := randf_range(9.0, 14.5)
		car.setup(car_files[randi() % car_files.size()], paint, idx, along, pace, bias)
		var dir: Vector3 = edge["dir"]
		car.place_on(spot, atan2(dir.x, dir.z), floor_mesh)
		_cars.append(car)
		taken.append(spot)
		placed += 1


func _crunch(amount: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = _ShopSounds.stream("thud")
	player.volume_db = lerpf(-14.0, 2.0, clampf(amount / 10.0, 0.0, 1.0))
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
