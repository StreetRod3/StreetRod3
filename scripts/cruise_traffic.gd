extends Node3D

## Cars on the city streets during a cruise. Each one keeps to the same side of the
## road as the player's own drive. Each one drives the shortest way to a random destination
## and, once there, picks a new one.
## Hitting one is the race's car bump: it shoves both cars, and the player takes damage.
## In a free roam, five of them are police. Two drive the streets. Two sit at the curb
## and one sits at the police station until the heat calls them, and then they drive
## out from that spot. A full meter has all five out. They patrol the same graph, come
## to a crash, and chase once the player's heat is up.

const _TrafficCar := preload("res://scripts/traffic_car.gd")
const _TrackFile := preload("res://scripts/track_file.gd")
const _CarBump := preload("res://scripts/car_bump.gd")
const _ShopSounds := preload("res://scripts/shop_sounds.gd")
const _Police := preload("res://scripts/cruise_police.gd")

const _COUNT := 24
const _COP_COUNT := 5
## The two that are out with no heat. The other three wait at a curb or the station.
const _COP_DRIVING := 2
const _POLICE_CAR := "res://assets/cars/police-fairlane-1957.car"
const _LOOK := 9.0
const _MAX_YAW := 1.15
## Streets this wide, curb to curb, get a lane off the center line.
const _TWO_LANE_HALF := 6.0
const _BODY_Y := 0.35
## A trip is at least this far in a straight line, in meters.
const _MIN_TRIP := 70.0

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
var _stops: Array[int] = []
var _node_pos: Dictionary = {}
var _cars: Array[CharacterBody3D] = []
var _bump: _CarBump = _CarBump.new()
var _prev_player := Vector3.ZERO
var _have_prev := false
var _police_on := false
var _police: _Police
var _pending_harm := 0.0
var _pending_at := Vector3.ZERO
var _any_pursuit := false
## Pulled over. Every police car rolls to a stop and stays there.
var _cops_halted := false
var _station := Vector3.ZERO
var _station_size := Vector2.ZERO
var _have_station := false


func setup(track: Dictionary, avoid: Vector3, floor_mesh: MeshInstance3D, car_files: Array[String], with_police := false) -> void:
	_police_on = with_police
	if _police_on:
		_police = _Police.new()
		_note_station(track)
	_build_graph(track)
	if car_files.is_empty() or _edges.is_empty():
		return
	_spawn(avoid, floor_mesh, car_files)
	if _police_on:
		_fill_cops(avoid)


## The player's last real hit, read by the cruise after the car has taken it.
func note_player_harm(amount: float, at: Vector3) -> void:
	if not _police_on or amount <= _pending_harm:
		return
	_pending_harm = amount
	_pending_at = at


func take_stop(money: int) -> Dictionary:
	if not _police_on:
		return {}
	return _police.take_stop(money)


## Hold every police car, or let them drive again. The ones on a call drop the siren.
func halt_police(on: bool) -> void:
	_cops_halted = on
	if not on:
		return
	_any_pursuit = false
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null or not car.cop:
			continue
		car.aiming = false
		car.duty = _Police.PATROL
		car.show_call(false, false, 0.0)


## The on-duty cop nearest the player, the one who just made the stop.
func nearest_cop() -> Node3D:
	var player := _player()
	if player == null:
		return null
	var at := _player_center(player)
	var flat := Vector2(at.x, at.z)
	var best: _TrafficCar = null
	var best_d := INF
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null or not _working(car):
			continue
		var cop_at := car.center()
		var dist := Vector2(cop_at.x, cop_at.z).distance_to(flat)
		if dist < best_d:
			best_d = dist
			best = car
	return best


func heat_text() -> String:
	if not _police_on:
		return ""
	return _police.hud_text(_any_pursuit)


func heat_amount() -> float:
	if not _police_on:
		return 0.0
	return _police.heat


func pace_limit() -> float:
	return _Police.LIMIT_MPS


func _physics_process(delta: float) -> void:
	tick(delta, _player())


func tick(delta: float, player: Node3D) -> void:
	if delta <= 0.0 or _cars.is_empty():
		return
	if _police_on:
		_consume_harm()
		_match_roster(player)
		if _cops_halted:
			_any_pursuit = false
		else:
			_direct_cops(player, delta)
	var blockers := _blockers(delta, player)
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null:
			continue
		_drive(car, delta, blockers)
	for i in _cars.size():
		for j in range(i + 1, _cars.size()):
			var between := _bump.resolve(_cars[i], _cars[j])
			if _police_on:
				_note_pair(_cars[i], _cars[j], between)
	if player != null and player.has_method(&"apply_car_bump") and not _player_wrecked(player):
		var hardest := 0.0
		for body: CharacterBody3D in _cars:
			var hit := _bump.resolve(player, body)
			hardest = maxf(hardest, hit.x)
			if player.has_method(&"take_hit"):
				player.call(&"take_hit", hit.x)
			if _police_on:
				_note_player_bump(player, body, hit)
		if hardest > 1.5:
			_crunch(hardest)
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car != null:
			car.sync_speed()
			if _police_on and car.on_duty:
				var wail := car.duty == _Police.PURSUE or (car.duty == _Police.ATTEND and car.speed > 2.0)
				car.show_call(car.duty != _Police.PATROL, wail, delta)
	if _police_on and player != null and not _player_wrecked(player):
		_note_odd_cars(delta)
		_police.tick_scenes(delta, _sitting())
		_police.tick(delta, _player_speed(player), _cop_within(player, _Police.SIGHT_M), _cop_within(player, _Police.PULL_RANGE_M))


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
	if car.returning and car.stall_edge == car.edge_i and absf(car.along - car.stall_along) < 7.0:
		_park_home(car)
		return
	if car.parked:
		_sit(car, delta)
		return
	if _off_road(car):
		_reacquire(car)
	var sitting := car.held > 0.0
	if sitting:
		car.held = maxf(car.held - delta, 0.0)
	if car.next_i < 0:
		car.next_i = _next_edge(car)
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
	if sitting:
		desired = 0.0
		curb_target = 2.4
	elif _police_on and not _working(car) and car.held <= 0.0 and _near_scene(center, 22.0):
		curb_target = maxf(curb_target, 1.6)
		desired = minf(desired, 7.0)
	car.curb = lerpf(car.curb, curb_target, 1.0 - exp(-2.6 * delta))
	var aim := _ahead(car.edge_i, car.along, car.next_i, _LOOK, car.lane_bias + car.curb)
	if car.aiming:
		aim = car.aim_at
	var flat := Vector2(aim.x - center.x, aim.z - center.z)
	var desired_yaw := car.rotation.y
	if flat.length_squared() > 0.36:
		desired_yaw = atan2(flat.x, flat.y)
	var err := angle_difference(car.rotation.y, desired_yaw)
	if _cops_halted and car.cop:
		desired = 0.0
		car.aiming = false
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
	if sitting and car.held <= 0.0:
		car.route.clear()
		car.next_i = -1
		car.destination = -1
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
	car.route.clear()
	_enter(car, best)


func _enter(car: _TrafficCar, idx: int) -> void:
	if idx < 0 or idx >= _edges.size():
		car.route.clear()
		idx = _choose_next(car.edge_i)
	car.edge_i = idx
	car.next_i = _next_edge(car)
	var edge: Dictionary = _edges[idx]
	var a: Vector3 = edge["a"]
	var dir: Vector3 = edge["dir"]
	var along := (car.center() - a).dot(dir)
	car.along = clampf(along, 0.0, float(edge["length"]))


## The road after the current one. At the end of a trip a new destination is picked.
func _next_edge(car: _TrafficCar) -> int:
	if car.route.is_empty():
		_plan_trip(car)
	if car.route.is_empty():
		return _choose_next(car.edge_i)
	return car.route.pop_front()


func _plan_trip(car: _TrafficCar) -> void:
	if car.returning:
		_retarget(car, car.stall)
		return
	if _working(car):
		_plan_patrol(car)
		return
	car.route.clear()
	car.destination = -1
	if _stops.is_empty():
		return
	var here: Dictionary = _edges[car.edge_i]
	var end: Vector3 = here["b"]
	for attempt in 8:
		var stop: int = _stops[randi() % _stops.size()]
		var target: Vector3 = _node_pos[stop]
		var min_trip := _MIN_TRIP if attempt < 6 else 0.0
		if stop == int(here["to"]) or Vector2(target.x - end.x, target.z - end.z).length() < min_trip:
			continue
		var path := _route(car.edge_i, stop)
		if path.is_empty():
			continue
		car.destination = stop
		car.route = path
		return


## Shortest road list after `start_edge` that ends at node `goal`. A U-turn is only taken at a dead end.
func _route(start_edge: int, goal: int) -> Array[int]:
	var cost := PackedFloat32Array()
	cost.resize(_edges.size())
	cost.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(_edges.size())
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(_edges.size())
	cost[start_edge] = 0.0
	var open: Array[int] = [start_edge]
	var found := -1
	while not open.is_empty():
		var best_at := 0
		for i in open.size():
			if cost[open[i]] < cost[open[best_at]]:
				best_at = i
		var current: int = open[best_at]
		open.remove_at(best_at)
		if done[current] == 1:
			continue
		done[current] = 1
		var edge: Dictionary = _edges[current]
		if current != start_edge and int(edge["to"]) == goal:
			found = current
			break
		var outs: Array = _out.get(int(edge["to"]), [])
		for item: Variant in outs:
			var idx := int(item)
			var nxt: Dictionary = _edges[idx]
			if int(nxt["to"]) == int(edge["from"]) and outs.size() > 1:
				continue
			var total: float = cost[current] + float(nxt["length"])
			if total < cost[idx]:
				cost[idx] = total
				prev[idx] = current
				open.append(idx)
	var path: Array[int] = []
	var step := found
	while step >= 0 and step != start_edge:
		path.push_front(step)
		step = prev[step]
	return path


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
		_node_pos[from_id] = a
		_node_pos[to_id] = b
	for id: int in _out:
		_stops.append(id)


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
	var cops_left := _COP_DRIVING if _police_on else 0
	if _police_on:
		placed = _spawn_parked(avoid_flat, floor_mesh, taken)
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
		var as_cop := cops_left > 0 and flat.distance_to(avoid_flat) >= _Police.SIGHT_M + 8.0 and not _cop_near(flat, 40.0)
		var car := _TrafficCar.new()
		car.name = "TrafficCar%d" % placed
		add_child(car)
		var paint: Color = _PAINTS[randi() % _PAINTS.size()]
		var pace := randf_range(9.0, 14.5)
		var file := car_files[randi() % car_files.size()]
		if as_cop:
			paint = Color.WHITE
			pace = _Police.PATROL_MPS
			file = _POLICE_CAR
		car.setup(file, paint, idx, along, pace, bias)
		if as_cop:
			car.make_cop()
			cops_left -= 1
		var dir: Vector3 = edge["dir"]
		car.place_on(spot, atan2(dir.x, dir.z), floor_mesh)
		_cars.append(car)
		taken.append(spot)
		placed += 1


## Two at the curb and one on the station apron. They count toward the traffic total.
func _spawn_parked(avoid: Vector2, floor_mesh: MeshInstance3D, taken: Array[Vector3]) -> int:
	var placed := 0
	if _have_station:
		var front := _closest_on_road(_station)
		if int(front["edge"]) >= 0:
			var edge: Dictionary = _edges[int(front["edge"])]
			var dir: Vector3 = edge["dir"]
			var onto := Vector3(float(front["x"]) - _station.x, 0.0, float(front["z"]) - _station.z)
			if onto.length_squared() > 0.01:
				onto = onto.normalized()
			var reach := absf(onto.x) * _station_size.x * 0.5 + absf(onto.z) * _station_size.y * 0.5
			var stall := _station + onto * (reach + 4.5)
			_place_post(_TrafficCar.POST_STATION, int(front["edge"]), float(front["along"]), stall, atan2(dir.x, dir.z), floor_mesh, taken)
			placed += 1
	var curbs := 0
	for i in _edges.size():
		if curbs >= 2:
			break
		var edge: Dictionary = _edges[i]
		var length := float(edge["length"])
		if length < 48.0:
			continue
		var along := length * (0.42 if curbs == 0 else 0.7)
		var spot := _curb_point(edge, along)
		var flat := Vector2(spot.x, spot.z)
		if flat.distance_to(avoid) < 36.0:
			continue
		if _have_station and flat.distance_to(Vector2(_station.x, _station.z)) < 28.0:
			continue
		var crowded := false
		for prev: Vector3 in taken:
			if Vector2(prev.x, prev.z).distance_to(flat) < 24.0:
				crowded = true
				break
		if crowded:
			continue
		var dir: Vector3 = edge["dir"]
		_place_post(_TrafficCar.POST_CURB, i, along, spot, atan2(dir.x, dir.z), floor_mesh, taken)
		curbs += 1
		placed += 1
	return placed


func _place_post(post: int, edge_i: int, along: float, stall: Vector3, yaw: float, floor_mesh: MeshInstance3D, taken: Array[Vector3]) -> void:
	var car := _TrafficCar.new()
	car.name = "TrafficCar%d" % _cars.size()
	add_child(car)
	car.setup(_POLICE_CAR, Color.WHITE, edge_i, along, 0.0, 0.0)
	car.make_cop()
	car.post = post
	car.parked = true
	car.stall = stall
	car.stall_yaw = yaw
	car.stall_edge = edge_i
	car.stall_along = along
	car.place_on(stall, yaw, floor_mesh)
	car.shove = Vector3.ZERO
	car.speed = 0.0
	_cars.append(car)
	taken.append(stall)


func _note_station(track: Dictionary) -> void:
	for raw: Variant in track.get("buildings", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var block: Dictionary = raw
		if str(block.get("sign", "")) != "POLICE":
			continue
		_station = Vector3(float(block["x"]), 0.0, float(block["y"]))
		_station_size = Vector2(float(block["w"]), float(block["d"]))
		_have_station = true
		return


func _closest_on_road(pos: Vector3) -> Dictionary:
	var best := -1
	var best_along := 0.0
	var best_gap := INF
	var spot := Vector3.ZERO
	for i in _edges.size():
		var edge: Dictionary = _edges[i]
		var a: Vector3 = edge["a"]
		var dir: Vector3 = edge["dir"]
		var along := clampf((pos - a).dot(dir), 0.0, float(edge["length"]))
		var point := a + dir * along
		var gap := Vector2(point.x - pos.x, point.z - pos.z).length()
		if gap < best_gap:
			best_gap = gap
			best = i
			best_along = along
			spot = point
	return {"edge": best, "along": best_along, "x": spot.x, "z": spot.z}


func _curb_point(edge: Dictionary, along: float) -> Vector3:
	var a: Vector3 = edge["a"]
	var dir: Vector3 = edge["dir"]
	var right: Vector3 = edge["right"]
	return a + dir * along + right * (float(edge["half"]) - 1.15)


func _sit(car: _TrafficCar, delta: float) -> void:
	car.shove = car.shove.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))
	var back := car.stall - car.global_position
	back.y = 0.0
	if back.length() > 0.15:
		car.global_position += back * minf(2.2 * delta, 0.4)
	car.global_position.y = _BODY_Y
	car.rotation.y = lerp_angle(car.rotation.y, car.stall_yaw, 1.0 - exp(-3.0 * delta))
	car.speed = 0.0


func _park_home(car: _TrafficCar) -> void:
	car.returning = false
	car.parked = true
	car.cruise_mps = 0.0
	car.route.clear()
	car.next_i = -1
	car.destination = -1
	car.place_on(car.stall, car.stall_yaw, null)
	car.shove = Vector3.ZERO
	car.speed = 0.0


func _dispatch(car: _TrafficCar) -> void:
	car.parked = false
	car.returning = false
	car.serve(true)
	car.cruise_mps = _Police.PATROL_MPS
	car.route.clear()
	car.next_i = -1
	car.destination = -1


func _recall(car: _TrafficCar) -> void:
	car.serve(false)
	car.returning = true
	car.parked = false
	car.cruise_mps = _Police.PATROL_MPS
	car.route.clear()
	car.next_i = -1
	car.destination = -1


func _plan_patrol(car: _TrafficCar) -> void:
	car.route.clear()
	car.destination = -1
	if _stops.is_empty():
		return
	var here: Dictionary = _edges[car.edge_i]
	var count := _stops.size()
	for step in count:
		var stop: int = _stops[(car.patrol_i + step) % count]
		if stop == int(here["to"]):
			continue
		var path := _route(car.edge_i, stop)
		if path.is_empty():
			continue
		car.patrol_i = (car.patrol_i + step + 1) % count
		car.destination = stop
		car.route = path
		return


func _fill_cops(avoid: Vector3) -> void:
	var have := 0
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car != null and car.cop:
			have += 1
	while have < _COP_COUNT:
		var best: _TrafficCar = null
		var best_d := -1.0
		for body: CharacterBody3D in _cars:
			var car := body as _TrafficCar
			if car == null or car.cop:
				continue
			var flat := Vector2(car.center().x - avoid.x, car.center().z - avoid.z)
			if flat.length() > best_d:
				best_d = flat.length()
				best = car
		if best == null:
			return
		best.use_car(_POLICE_CAR)
		best.make_cop()
		have += 1


func _cop_near(flat: Vector2, reach: float) -> bool:
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null or not car.cop:
			continue
		var at := car.center()
		if Vector2(at.x, at.z).distance_to(flat) < reach:
			return true
	return false


func _consume_harm() -> void:
	var amount := _pending_harm
	var at := _pending_at
	_pending_harm = 0.0
	if amount <= _Police.NOTICE_MPS:
		return
	_police.note_hit(amount, false)
	_police.open_scene(at, amount >= _Police.HARD_MPS, -1)


## The two traffic cars stay out. Extra heat sends the nearest parked car, which
## drives from the curb or the station instead of appearing beside the player.
func _match_roster(player: Node3D) -> void:
	var wanted := _police.cops_for(_police.heat)
	var origin := _player_center(player) if player != null else Vector3.ZERO
	var traffic: Array[_TrafficCar] = []
	var waiting: Array[_TrafficCar] = []
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null or not car.cop:
			continue
		if car.post == _TrafficCar.POST_TRAFFIC:
			traffic.append(car)
		else:
			waiting.append(car)
	for car: _TrafficCar in traffic:
		if car.on_duty:
			continue
		car.parked = false
		car.returning = false
		car.serve(true)
		car.cruise_mps = _Police.PATROL_MPS
	var extra := maxi(wanted - traffic.size(), 0)
	var ranked := _by_distance(waiting, origin)
	for i in ranked.size():
		var car := ranked[i]
		if i < extra:
			if not car.on_duty:
				_dispatch(car)
		elif car.on_duty:
			_recall(car)


func _by_distance(pool: Array[_TrafficCar], origin: Vector3) -> Array[_TrafficCar]:
	var ranked: Array[_TrafficCar] = []
	while not pool.is_empty():
		var best_i := 0
		var best_d := _flat_dist(pool[0].center(), origin)
		for i in range(1, pool.size()):
			var dist := _flat_dist(pool[i].center(), origin)
			if dist < best_d:
				best_d = dist
				best_i = i
		ranked.append(pool[best_i])
		pool.remove_at(best_i)
	return ranked


func _flat_dist(at: Vector3, origin: Vector3) -> float:
	return Vector2(at.x - origin.x, at.z - origin.z).length()


func _working(car: _TrafficCar) -> bool:
	return car.cop and car.on_duty


func _direct_cops(player: Node3D, delta: float) -> void:
	var cops: Array[_TrafficCar] = []
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car != null and _working(car):
			cops.append(car)
	_any_pursuit = false
	if cops.is_empty():
		return
	var player_pos := _player_center(player) if player != null else Vector3.ZERO
	var spots: Array[Vector3] = []
	for car: _TrafficCar in cops:
		spots.append(car.center())
	var plan: Array[int] = []
	if player != null:
		plan = _police.duties(spots, player_pos)
	else:
		plan.resize(cops.size())
	var scene := _police.main_scene()
	var scene_pos := player_pos
	if not scene.is_empty():
		scene_pos = scene["pos"]
	var nearest := INF
	var far_i := -1
	var far_d := -1.0
	for i in cops.size():
		if plan[i] != _Police.ATTEND:
			continue
		var dist := Vector2(spots[i].x - scene_pos.x, spots[i].z - scene_pos.z).length()
		nearest = minf(nearest, dist)
		if dist > far_d:
			far_d = dist
			far_i = i
	if far_i >= 0 and _police.wants_drop(nearest) and player != null:
		if _drop_near(cops[far_i], scene_pos, player_pos):
			_police.mark_dropped()
			spots[far_i] = cops[far_i].center()
	for i in cops.size():
		var car := cops[i]
		car.duty = plan[i]
		if car.duty == _Police.PURSUE:
			_any_pursuit = true
		var pace := _Police.PATROL_MPS
		if car.duty == _Police.PURSUE:
			pace = _Police.PURSUE_MPS
		elif car.duty == _Police.ATTEND and not scene.is_empty():
			var at: Vector3 = scene["pos"]
			var gap := Vector2(at.x - car.center().x, at.z - car.center().z).length()
			pace = 0.0 if gap < 14.0 else _Police.PATROL_MPS
		car.cruise_mps = pace
		# A chase stays on the lane. Steering at the car makes the body slide while the nose hunts it.
		car.aiming = false
		car.retarget -= delta
		if car.duty == _Police.PATROL or car.retarget > 0.0:
			continue
		car.retarget = _Police.RETARGET_S
		var goal := player_pos if car.duty == _Police.PURSUE else scene_pos
		_retarget(car, goal)


func _retarget(car: _TrafficCar, goal_pos: Vector3) -> void:
	var goal := _nearest_node(goal_pos)
	if goal < 0 or car.edge_i < 0 or car.edge_i >= _edges.size():
		return
	var here: Dictionary = _edges[car.edge_i]
	if int(here["to"]) == goal:
		return
	var path := _route(car.edge_i, goal)
	if path.is_empty():
		return
	car.destination = goal
	car.route = path
	car.next_i = car.route.pop_front()


## Parks a cop on the road into the nearest junction, short of the scene.
func _drop_near(car: _TrafficCar, pos: Vector3, player_pos: Vector3, back: float = 0.0) -> bool:
	var node_id := _nearest_node(pos)
	if node_id < 0:
		return false
	var best := -1
	var best_len := -1.0
	for i in _edges.size():
		var edge: Dictionary = _edges[i]
		if int(edge["to"]) != node_id:
			continue
		if float(edge["length"]) > best_len:
			best_len = float(edge["length"])
			best = i
	if best < 0:
		return false
	var edge: Dictionary = _edges[best]
	var along := maxf(float(edge["length"]) - 28.0 - back, 4.0)
	var spot := _point(edge, along, 0.0)
	if Vector2(spot.x - player_pos.x, spot.z - player_pos.z).length() < 22.0:
		return false
	var dir: Vector3 = edge["dir"]
	car.place_on(spot, atan2(dir.x, dir.z), null)
	car.edge_i = best
	car.along = along
	car.route.clear()
	car.destination = node_id
	car.next_i = _choose_next(best)
	car.shove = dir * car.cruise_mps
	car.loose = 0.0
	car.spin = 0.0
	return true


func _nearest_node(pos: Vector3) -> int:
	var best := -1
	var best_d := INF
	for id: Variant in _node_pos:
		var at: Vector3 = _node_pos[id]
		var dist := Vector2(at.x - pos.x, at.z - pos.z).length()
		if dist < best_d:
			best_d = dist
			best = int(id)
	return best


func _on_edge(pos: Vector3, edge_i: int) -> bool:
	if edge_i < 0 or edge_i >= _edges.size():
		return false
	var edge: Dictionary = _edges[edge_i]
	return _gap(pos, edge) <= float(edge["half"]) + 1.0


func _note_pair(a_body: CharacterBody3D, b_body: CharacterBody3D, hit: Vector2) -> void:
	var a := a_body as _TrafficCar
	var b := b_body as _TrafficCar
	if a == null or b == null:
		return
	var amount := maxf(hit.x, hit.y)
	if amount <= _Police.NOTICE_MPS or (_working(a) and _working(b)):
		return
	var mid := (a.center() + b.center()) * 0.5
	var hard := amount >= _Police.HARD_MPS or _off_road(a) or _off_road(b)
	_police.open_scene(mid, hard, -1)
	if not _working(a):
		_hold(a)
		_police.open_scene(mid, hard, a.get_instance_id())
	if not _working(b):
		_hold(b)
		_police.open_scene(mid, hard, b.get_instance_id())


func _note_player_bump(player: Node3D, body: CharacterBody3D, hit: Vector2) -> void:
	var car := body as _TrafficCar
	if car == null:
		return
	if _working(car):
		if _bump.touched:
			if not car.struck:
				car.struck = true
				_police.note_hit(0.0, true)
		else:
			car.struck = false
		return
	var amount := maxf(hit.x, hit.y)
	if amount <= _Police.NOTICE_MPS:
		return
	var mid := (_player_center(player) + car.center()) * 0.5
	var hard := amount >= _Police.HARD_MPS or _off_road(car)
	_hold(car)
	_police.open_scene(mid, hard, car.get_instance_id())


func _hold(car: _TrafficCar) -> void:
	if _working(car) or car.held > 0.0:
		return
	car.held = randf_range(_Police.HOLD_MIN_S, _Police.HOLD_MAX_S)


func _note_odd_cars(delta: float) -> void:
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null:
			continue
		if _working(car) or car.parked or car.held > 0.0 or car.loose > 0.0:
			car.odd_s = 0.0
			continue
		if car.edge_i < 0 or car.edge_i >= _edges.size():
			continue
		var edge: Dictionary = _edges[car.edge_i]
		var dir: Vector3 = edge["dir"]
		var road_yaw := atan2(dir.x, dir.z)
		var spun := absf(angle_difference(car.rotation.y, road_yaw)) > 1.1 and car.speed < 1.6
		if _off_road(car) or spun:
			car.odd_s += delta
		else:
			car.odd_s = 0.0
		if car.odd_s < 1.0:
			continue
		car.odd_s = 0.0
		var off := _off_road(car)
		_hold(car)
		_police.open_scene(car.center(), off, car.get_instance_id())


func _sitting() -> Dictionary:
	var sitting := {}
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car != null:
			sitting[car.get_instance_id()] = car.held > 0.0
	return sitting


func _near_scene(center: Vector3, reach: float) -> bool:
	if not _police_on:
		return false
	var flat := Vector2(center.x, center.z)
	for scene: Dictionary in _police.scenes:
		var at: Vector3 = scene["pos"]
		if Vector2(at.x, at.z).distance_to(flat) <= reach:
			return true
	return false


func _cop_within(player: Node3D, reach: float) -> bool:
	var at := _player_center(player)
	var flat := Vector2(at.x, at.z)
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null or not _working(car):
			continue
		var cop_at := car.center()
		if Vector2(cop_at.x, cop_at.z).distance_to(flat) <= reach:
			return true
	return false


func _player_center(player: Node3D) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.has_method(&"center"):
		return player.call(&"center")
	return player.global_position + player.global_transform.basis.z * 1.9


func _player_speed(player: Node3D) -> float:
	if player != null and player.has_method(&"get_forward_speed"):
		return absf(float(player.call(&"get_forward_speed")))
	return 0.0


func _crunch(amount: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = _ShopSounds.stream("thud")
	player.volume_db = lerpf(-14.0, 2.0, clampf(amount / 10.0, 0.0, 1.0))
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
