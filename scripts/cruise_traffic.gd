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
const _Zones := preload("res://scripts/speed_zones.gd")

const _COUNT := 24
const _COP_COUNT := 5
## The two that are out with no heat. The other three wait at a curb or the station.
const _COP_DRIVING := 2
const _POLICE_CAR := "res://assets/cars/police-fairlane-1957.car"
const _LOOK := 9.0
const _MAX_YAW := 1.15
## A chase can turn only as tight as the tires allow. Stopped wheels do not yaw the car.
const _TURN_RADIUS := 5.6
const _LATERAL := 6.5
## Front wheels stay inside about 30 degrees, so a slow police car cannot pivot or slide sideways.
const _STEER_MAX := 0.5236
const _WHEELBASE := 3.0
## A chase car this slow, facing this far across the street, is blocking the lane.
const _WALK_MPS := 0.8
const _STUCK_S := 1.0
const _CROSS_YAW := 0.87
## Back up, then creep along the road until the nose is in the lane.
const _BACK_S := 1.0
const _UNSTICK_MPS := 2.5
const _CREEP_MPS := 3.2
const _ALIGNED := 0.40
## A car stopped in a jam waits this long, then pulls out and goes around.
const _WAIT_MIN := 10.0
const _WAIT_MAX := 30.0
## Police give the queue much less time. A chase barely waits at all.
const _COP_WAIT_MIN := 2.0
const _COP_WAIT_MAX := 4.0
const _PURSUE_WAIT := 0.5
const _PASS_S := 5.0
const _PASS_M := 3.2
const _JAM_MPS := 1.6
## Once a chase is this close to a car that has stopped, it leaves the loop and parks beside it.
const _PARK_REACH := 48.0
const _PARK_GAP := 3.6
const _PARK_STOP := 1.8
## Another police car this close, while one is already chasing, joins that chase.
const _JOIN_M := 12.0
## Straight at the player only while that line stays on a street. Past this, it is a block.
const _CORRIDOR := 14.0
## Extra meters around a building so the body stops at the wall, not inside it.
const _BLOCK_PAD := 0.45
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
## Building footprints from the city map. x is world X, y is world Z, h is the half size.
var _blocks: Array[Dictionary] = []
## Police cars that have joined a chase already under way. They stay on it until the heat is gone.
var _joined: Dictionary = {}


func setup(track: Dictionary, avoid: Vector3, floor_mesh: MeshInstance3D, car_files: Array[String], with_police := false) -> void:
	_police_on = with_police
	_note_blocks(track)
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
	var player := _player()
	if player == null:
		return _Zones.DEFAULT_MPS
	return limit_at(_player_center(player))


func limit_at(pos: Vector3) -> float:
	var best := _Zones.DEFAULT_MPS
	var best_gap := INF
	for i in _edges.size():
		var edge: Dictionary = _edges[i]
		var gap := _gap(pos, edge)
		if gap < best_gap:
			best_gap = gap
			best = float(edge.get("limit", _Zones.DEFAULT_MPS))
	return best


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
				var hunt := car.duty == _Police.PURSUE or car.duty == _Police.STOP
				var wail := hunt or (car.duty == _Police.ATTEND and car.speed > 2.0)
				car.show_call(hunt, wail, delta)
	if _police_on and player != null and not _player_wrecked(player):
		_note_odd_cars(delta)
		_police.tick_scenes(delta, _sitting())
		_police.tick(delta, _player_speed(player), _cop_within(player, _Police.SIGHT_M), _cop_within(player, _Police.PULL_RANGE_M), limit_at(_player_center(player)))


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
	if _park_for_stop(car):
		_drive_alongside(car, delta)
		return
	if _pursuing(car) and not _cops_halted:
		_drive_pursuit(car, delta)
		return
	car.stuck_s = 0.0
	car.unstick = 0.0
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
	var jammed := false
	var self_id := car.get_instance_id()
	var passing := car.pass_s > 0.0
	for block: Dictionary in blockers:
		if int(block["id"]) == self_id:
			continue
		var other: Vector3 = block["center"]
		var gap := other - center
		var ahead := gap.dot(forward)
		var lateral := absf(forward.x * gap.z - forward.z * gap.x)
		var other_speed := float(block["speed"])
		if ahead > 0.4 and ahead < 14.0 and lateral < 2.8 and other_speed < _JAM_MPS and car.speed < _JAM_MPS:
			jammed = true
		if passing:
			continue
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
	_queue_pass(car, delta, jammed, sitting, center, forward, blockers)
	if car.pass_s > 0.0:
		desired = maxf(desired, minf(car.cruise_mps, 9.0))
	if sitting:
		desired = 0.0
		curb_target = 2.4
	elif _police_on and not _working(car) and car.held <= 0.0 and _near_scene(center, 22.0):
		curb_target = maxf(curb_target, 1.6)
		desired = minf(desired, 7.0)
	if car.edge_i >= 0 and car.edge_i < _edges.size() and not _hunting(car):
		desired = minf(desired, float(_edges[car.edge_i].get("limit", _Zones.DEFAULT_MPS)))
	car.curb = lerpf(car.curb, curb_target, 1.0 - exp(-2.6 * delta))
	var aim := _ahead(car.edge_i, car.along, car.next_i, _LOOK, car.lane_bias + car.curb)
	if car.aiming:
		aim = car.aim_at
	if car.pass_s > 0.0 and car.edge_i >= 0 and car.edge_i < _edges.size():
		var right: Vector3 = _edges[car.edge_i]["right"]
		aim += right * (_PASS_M * car.pass_side)
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
	if car.cop:
		var yaw_cap := _yaw_limit(Vector2(car.shove.x, car.shove.z).length())
		yaw_rate = clampf(yaw_rate, -yaw_cap, yaw_cap)
	car.spin = move_toward(car.spin, 0.0, 4.0 * delta)
	car.rotation.y += yaw_rate * delta
	forward = Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	var blend := 1.15 if car.loose > 0.0 else 3.4
	car.loose = maxf(car.loose - delta, 0.0)
	car.shove = car.shove.lerp(forward * maxf(desired, 0.0), 1.0 - exp(-blend * delta))
	if car.cop and car.loose <= 0.0:
		car.shove = forward * maxf(car.shove.dot(forward), 0.0)
	var moved := car.shove * delta
	if car.cop:
		_step_cop(car, moved)
	else:
		car.global_position += moved
		car.global_position.y = _BODY_Y
	car.roll_wheels(Vector2(moved.x, moved.z).length())
	if car.pass_s <= 0.0:
		_hold_lane(car, delta)
	if car.cop:
		_keep_solid(car)
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


## A chase ignores the lane and the right of way. It still rolls: the nose only turns
## as fast as the tires can at this speed, and the car moves along that nose.
## Other cars and buildings stop that move. The bump afterwards is what shoves the cars.
func _drive_pursuit(car: _TrafficCar, delta: float) -> void:
	var reversing := false
	var creeping := false
	if car.pass_s > 0.0:
		car.pass_s = maxf(car.pass_s - delta, 0.0)
	_mark_stuck(car, delta)
	if car.unstick > 0.0:
		car.unstick -= delta
		reversing = true
		if car.unstick <= 0.0:
			car.unstick = -1.0
			reversing = false
			creeping = true
	elif car.unstick < 0.0:
		creeping = true
		if _creep_done(car):
			car.unstick = 0.0
			car.stuck_s = 0.0
			creeping = false
		elif Vector2(car.shove.x, car.shove.z).length() < _WALK_MPS:
			car.stuck_s += delta
			if car.stuck_s >= _STUCK_S:
				car.unstick = _BACK_S
				car.stuck_s = 0.0
				creeping = false
				reversing = true
		else:
			car.stuck_s = 0.0
	var center := car.center()
	var desired_yaw := car.rotation.y
	var desired := 0.0
	if reversing:
		desired = -_UNSTICK_MPS
	elif creeping:
		desired_yaw = _street_yaw(car)
		desired = _CREEP_MPS
	else:
		var aim := center
		var player := _player()
		if player != null:
			var prey := _player_center(player)
			if player.has_method(&"planar_velocity"):
				var lead: Vector3 = player.call(&"planar_velocity")
				lead.y = 0.0
				prey += lead * 0.35
			aim = _pursuit_aim(car, center, prey)
		else:
			aim = _pursuit_road_point(car, 22.0)
		var flat := Vector2(aim.x - center.x, aim.z - center.z)
		if flat.length_squared() > 4.0:
			desired_yaw = atan2(flat.x, flat.y)
		var tight := clampf(absf(angle_difference(car.rotation.y, desired_yaw)) / 1.15, 0.0, 1.0)
		desired = lerpf(_Police.PURSUE_MPS, _CREEP_MPS, tight)
		var nose := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
		_pursue_pass(car, delta, center, nose)
		if car.pass_s > 0.0:
			var aside := Vector3(nose.z, 0.0, -nose.x) * (_PASS_M * car.pass_side)
			aim = center + nose * 8.0 + aside
			if aside.length_squared() > 0.01:
				desired_yaw = atan2(aim.x - center.x, aim.z - center.z)
			desired = maxf(desired, _CREEP_MPS)
	var err := angle_difference(car.rotation.y, desired_yaw)
	var speed := Vector2(car.shove.x, car.shove.z).length()
	var yaw_max := _yaw_limit(speed)
	var yaw_rate := clampf(err * 2.2 + car.spin, -yaw_max, yaw_max)
	car.spin = move_toward(car.spin, 0.0, 4.0 * delta)
	car.rotation.y += yaw_rate * delta
	var forward := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	car.loose = maxf(car.loose - delta, 0.0)
	car.shove = car.shove.lerp(forward * desired, 1.0 - exp(-3.2 * delta))
	if car.loose <= 0.0:
		var along_v := car.shove.dot(forward)
		if desired < 0.0:
			along_v = minf(along_v, 0.0)
		else:
			along_v = maxf(along_v, 0.0)
		car.shove = forward * along_v
	_step_cop(car, car.shove * delta)
	car.roll_wheels(car.shove.dot(forward) * delta)
	_note_nearest_edge(car)


## The chased car has stopped. Leave the road loop and wait beside it for the ticket.
func _park_for_stop(car: _TrafficCar) -> bool:
	if not _hunting(car) or _cops_halted:
		return false
	var player := _player()
	if player == null or _player_wrecked(player):
		return false
	if _player_speed(player) > _Police.CRAWL_MPS:
		return false
	return _flat_dist(car.center(), _player_center(player)) <= _PARK_REACH


func _hunting(car: _TrafficCar) -> bool:
	return car.cop and car.on_duty and (car.duty == _Police.STOP or car.duty == _Police.PURSUE)


func _drive_alongside(car: _TrafficCar, delta: float) -> void:
	car.pass_s = 0.0
	car.wait_s = 0.0
	car.stuck_s = 0.0
	car.unstick = 0.0
	car.aiming = false
	var player := _player()
	var prey := _player_center(player)
	var pyaw := player.rotation.y
	var pforward := Vector3(sin(pyaw), 0.0, cos(pyaw))
	var pright := Vector3(pforward.z, 0.0, -pforward.x)
	var center := car.center()
	var side := _park_side(center, prey, pright)
	var rank := _park_rank(car, prey)
	if rank % 2 == 1:
		side = -side
	var slot := prey + pright * (_PARK_GAP * side) - pforward * (6.0 * float(rank))
	if _slot_blocked(slot):
		side = -side
		slot = prey + pright * (_PARK_GAP * side) - pforward * (6.0 * float(rank))
	var flat := Vector2(slot.x - center.x, slot.z - center.z)
	var dist := flat.length()
	var desired_yaw := pyaw
	if dist > _PARK_STOP:
		desired_yaw = atan2(flat.x, flat.y)
	var err := angle_difference(car.rotation.y, desired_yaw)
	var desired := 0.0
	if dist <= _PARK_STOP:
		desired = 0.0
	elif dist < 14.0 and absf(err) > 0.55:
		desired = minf(_CREEP_MPS, maxf(dist * 0.4, 1.4))
	else:
		desired = minf(_Police.STOP_MPS, dist * 0.55)
		desired = minf(desired, sqrt(maxf(dist, 1.0) * _LATERAL))
		if absf(err) > 0.8:
			desired = minf(desired, _CREEP_MPS)
	var speed := Vector2(car.shove.x, car.shove.z).length()
	var yaw_max := _yaw_limit(speed)
	car.rotation.y += clampf(err * 2.2, -yaw_max, yaw_max) * delta
	var forward := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	car.shove = car.shove.lerp(forward * desired, 1.0 - exp(-3.4 * delta))
	if dist < 22.0:
		var have := Vector2(car.shove.x, car.shove.z).length()
		if have > desired + 0.5:
			car.shove = Vector3.ZERO if desired <= 0.2 else forward * desired
	if dist <= _PARK_STOP:
		car.shove = Vector3.ZERO
	_step_cop(car, car.shove * delta)
	car.roll_wheels(car.shove.dot(forward) * delta)
	_note_nearest_edge(car)


func _park_side(center: Vector3, prey: Vector3, pright: Vector3) -> float:
	var side := (center - prey).dot(pright)
	if absf(side) < 1.2:
		return 1.0
	return 1.0 if side > 0.0 else -1.0


func _park_rank(car: _TrafficCar, prey: Vector3) -> int:
	var mine := _flat_dist(car.center(), prey)
	var rank := 0
	for body: CharacterBody3D in _cars:
		var other := body as _TrafficCar
		if other == null or other == car or not _hunting(other):
			continue
		if _flat_dist(other.center(), prey) < mine - 0.5:
			rank += 1
	return mini(rank, 2)


func _slot_blocked(slot: Vector3) -> bool:
	var flat := Vector2(slot.x, slot.z)
	for block: Dictionary in _blocks:
		var at: Vector2 = block["c"]
		var half: Vector2 = block["h"]
		if absf(flat.x - at.x) < half.x + 1.4 and absf(flat.y - at.y) < half.y + 1.4:
			return true
	return false


## Stopped behind a car. Civilians wait tens of seconds. Police pull out much sooner.
func _queue_pass(car: _TrafficCar, delta: float, jammed: bool, sitting: bool, center: Vector3, forward: Vector3, blockers: Array[Dictionary]) -> void:
	if car.pass_s > 0.0:
		car.pass_s = maxf(car.pass_s - delta, 0.0)
		car.wait_s = 0.0
		return
	var held := sitting or (_cops_halted and car.cop)
	if not jammed or held:
		car.wait_s = 0.0
		car.wait_for = 0.0
		return
	if car.wait_for <= 0.0:
		car.wait_for = _wait_span(car)
	car.wait_s += delta
	if car.wait_s < car.wait_for:
		return
	car.pass_s = _PASS_S
	car.pass_side = _pass_side(car, center, forward, blockers)
	car.wait_s = 0.0
	car.wait_for = 0.0


func _wait_span(car: _TrafficCar) -> float:
	if car.cop:
		return randf_range(_COP_WAIT_MIN, _COP_WAIT_MAX)
	return randf_range(_WAIT_MIN, _WAIT_MAX)


func _pass_side(car: _TrafficCar, center: Vector3, forward: Vector3, blockers: Array[Dictionary]) -> float:
	var right := Vector3(forward.z, 0.0, -forward.x)
	var left_n := 0
	var right_n := 0
	var self_id := car.get_instance_id()
	for block: Dictionary in blockers:
		if int(block["id"]) == self_id:
			continue
		var other: Vector3 = block["center"]
		var gap := other - center
		var ahead := gap.dot(forward)
		if ahead < -2.0 or ahead > 16.0:
			continue
		var side := gap.dot(right)
		if side > 0.5:
			right_n += 1
		elif side < -0.5:
			left_n += 1
	if left_n != right_n:
		return -1.0 if left_n < right_n else 1.0
	return -1.0 if randf() < 0.5 else 1.0


## A chase does not queue. A car stopped in front of it is a reason to swing out.
func _pursue_pass(car: _TrafficCar, delta: float, center: Vector3, forward: Vector3) -> void:
	if car.pass_s > 0.0 or car.unstick != 0.0:
		return
	if not _jam_ahead(car, center, forward):
		car.wait_s = 0.0
		return
	car.wait_s += delta
	if car.wait_s < _PURSUE_WAIT:
		return
	var blockers: Array[Dictionary] = []
	for body: CharacterBody3D in _cars:
		var other := body as _TrafficCar
		if other == null or other == car:
			continue
		blockers.append({"id": other.get_instance_id(), "center": other.center()})
	car.pass_s = _PASS_S
	car.pass_side = _pass_side(car, center, forward, blockers)
	car.wait_s = 0.0


func _jam_ahead(car: _TrafficCar, center: Vector3, forward: Vector3) -> bool:
	if Vector2(car.shove.x, car.shove.z).length() >= _JAM_MPS:
		return false
	for body: CharacterBody3D in _cars:
		var other := body as _TrafficCar
		if other == null or other == car:
			continue
		var gap := other.center() - center
		var ahead := gap.dot(forward)
		var lateral := absf(forward.x * gap.z - forward.z * gap.x)
		if ahead > 0.5 and ahead < 12.0 and lateral < 2.6 and other.speed < _JAM_MPS:
			return true
	return false


## Nearly stopped and sideways to the street. The next second is spent backing out.
func _mark_stuck(car: _TrafficCar, delta: float) -> void:
	if car.unstick != 0.0 or car.pass_s > 0.0:
		return
	var slow := Vector2(car.shove.x, car.shove.z).length() < _WALK_MPS
	if slow and _off_street(car) > _CROSS_YAW:
		car.stuck_s += delta
		if car.stuck_s >= _STUCK_S:
			car.unstick = _BACK_S
			car.stuck_s = 0.0
	else:
		car.stuck_s = 0.0


## The creep has the nose along the street and the car rolling that way.
func _creep_done(car: _TrafficCar) -> bool:
	if absf(angle_difference(car.rotation.y, _street_yaw(car))) > _ALIGNED:
		return false
	var forward := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	return car.shove.dot(forward) > 1.0


## Street direction nearest the nose, so the car takes the shorter turn back into the lane.
func _street_yaw(car: _TrafficCar) -> float:
	if car.edge_i < 0 or car.edge_i >= _edges.size():
		return car.rotation.y
	var dir: Vector3 = _edges[car.edge_i]["dir"]
	var yaw := atan2(dir.x, dir.z)
	var ahead := absf(angle_difference(car.rotation.y, yaw))
	var back := absf(angle_difference(car.rotation.y, yaw + PI))
	return yaw if ahead <= back else yaw + PI


func _off_street(car: _TrafficCar) -> float:
	return absf(angle_difference(car.rotation.y, _street_yaw(car)))


## Short steps, so a fast chase cannot skip through a car or a wall in one frame.
func _step_cop(car: _TrafficCar, move: Vector3) -> void:
	var dist := Vector2(move.x, move.z).length()
	var steps := maxi(int(ceil(dist / 0.45)), 1)
	var slice := move / float(steps)
	for _i in steps:
		car.global_position += slice
		car.global_position.y = _BODY_Y
		_keep_solid(car)


## Buildings push the body back out. Another car only stops the speed going into it,
## and the bump that follows is what shoves the two apart.
func _keep_solid(car: _TrafficCar) -> void:
	for _i in 4:
		var hit := _building_hit(car)
		if hit.is_empty():
			break
		var normal: Vector2 = hit["normal"]
		var depth := float(hit["depth"])
		car.global_position += Vector3(normal.x, 0.0, normal.y) * (depth + 0.08)
		car.global_position.y = _BODY_Y
		_strip_into(car, normal)
	var crowd := _crowd_hit(car)
	if crowd.is_empty():
		return
	_strip_into(car, crowd["normal"])


func _strip_into(car: _TrafficCar, normal: Vector2) -> void:
	var flat := Vector2(car.shove.x, car.shove.z)
	var into := flat.dot(normal)
	if into >= 0.0:
		return
	flat -= normal * into
	car.shove = Vector3(flat.x, 0.0, flat.y)


func _building_hit(car: _TrafficCar) -> Dictionary:
	var box := _body_box(car)
	if box.is_empty():
		return {}
	var best := 0.0
	var normal := Vector2.ZERO
	var found := false
	for block: Dictionary in _blocks:
		var center: Vector2 = block["c"]
		var half: Vector2 = block["h"]
		var hit := _separate(
			box["center"], box["axis_x"], box["axis_z"], float(box["half_x"]), float(box["half_z"]),
			center, Vector2.RIGHT, Vector2(0.0, 1.0), half.x, half.y
		)
		if hit.is_empty():
			continue
		var depth := float(hit["depth"])
		if not found or depth > best:
			found = true
			best = depth
			normal = hit["normal"]
	if not found:
		return {}
	return {"depth": best, "normal": normal}


func _crowd_hit(car: _TrafficCar) -> Dictionary:
	var box := _body_box(car)
	if box.is_empty():
		return {}
	var best := 0.0
	var normal := Vector2.ZERO
	var found := false
	for body: CharacterBody3D in _cars:
		if body == car:
			continue
		var other := _body_box(body)
		if other.is_empty():
			continue
		var hit := _separate(
			box["center"], box["axis_x"], box["axis_z"], float(box["half_x"]), float(box["half_z"]),
			other["center"], other["axis_x"], other["axis_z"], float(other["half_x"]), float(other["half_z"])
		)
		if hit.is_empty():
			continue
		var depth := float(hit["depth"])
		if not found or depth > best:
			found = true
			best = depth
			normal = hit["normal"]
	var player := _player()
	if player is CharacterBody3D:
		var theirs := _body_box(player as CharacterBody3D)
		if not theirs.is_empty():
			var hit := _separate(
				box["center"], box["axis_x"], box["axis_z"], float(box["half_x"]), float(box["half_z"]),
				theirs["center"], theirs["axis_x"], theirs["axis_z"], float(theirs["half_x"]), float(theirs["half_z"])
			)
			if not hit.is_empty() and float(hit["depth"]) > best:
				found = true
				normal = hit["normal"]
	if not found:
		return {}
	return {"depth": best, "normal": normal}


func _body_box(body: CharacterBody3D) -> Dictionary:
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not shape_node.shape is BoxShape3D:
		return {}
	var shape := shape_node.shape as BoxShape3D
	var xf := shape_node.global_transform
	var scale := xf.basis.get_scale()
	var axis_x := Vector2(xf.basis.x.x, xf.basis.x.z)
	var axis_z := Vector2(xf.basis.z.x, xf.basis.z.z)
	if axis_x.length_squared() < 0.0001 or axis_z.length_squared() < 0.0001:
		return {}
	return {
		"center": Vector2(xf.origin.x, xf.origin.z),
		"axis_x": axis_x.normalized(),
		"axis_z": axis_z.normalized(),
		"half_x": shape.size.x * absf(scale.x) * 0.5,
		"half_z": shape.size.z * absf(scale.z) * 0.5,
	}


## Smallest overlap. The normal pushes the first box out of the second. Empty when they are apart.
func _separate(
	a_center: Vector2, a_x: Vector2, a_z: Vector2, a_hx: float, a_hz: float,
	b_center: Vector2, b_x: Vector2, b_z: Vector2, b_hx: float, b_hz: float
) -> Dictionary:
	var best := INF
	var normal := Vector2.ZERO
	var delta := a_center - b_center
	var axes: Array[Vector2] = [a_x, a_z, b_x, b_z]
	for axis: Vector2 in axes:
		if axis.length_squared() < 0.0001:
			continue
		var n := axis.normalized()
		var dist := delta.dot(n)
		var reach_a := a_hx * absf(a_x.dot(n)) + a_hz * absf(a_z.dot(n))
		var reach_b := b_hx * absf(b_x.dot(n)) + b_hz * absf(b_z.dot(n))
		var overlap := reach_a + reach_b - absf(dist)
		if overlap <= 0.0:
			return {}
		if overlap < best:
			best = overlap
			normal = n if dist >= 0.0 else -n
	if best == INF:
		return {}
	return {"depth": best, "normal": normal}


## How fast the nose may yaw at this speed. Thirty degrees of steer, and no tighter than the tires.
func _yaw_limit(speed: float) -> float:
	var v := absf(speed)
	if v < 0.05:
		return 0.0
	var radius := maxf(_TURN_RADIUS, v * v / _LATERAL)
	return minf(v / radius, v * tan(_STEER_MAX) / _WHEELBASE)


func _pursuing(car: _TrafficCar) -> bool:
	return car.cop and car.on_duty and car.duty == _Police.PURSUE


## Coming to pull the car over. Still on the lane, with the lights on.
func _stopping(car: _TrafficCar) -> bool:
	return car.cop and car.on_duty and car.duty == _Police.STOP


## Across an open street, aim at the car. Through a block, take the road instead.
func _pursuit_aim(car: _TrafficCar, from: Vector3, prey: Vector3) -> Vector3:
	var gap := Vector2(prey.x - from.x, prey.z - from.z).length()
	if gap < 22.0 or _line_on_roads(from, prey):
		return prey
	return _pursuit_road_point(car, 24.0)


func _line_on_roads(a: Vector3, b: Vector3) -> bool:
	for t: float in [0.35, 0.65]:
		var at := a.lerp(b, t)
		if _road_gap(at) > _CORRIDOR:
			return false
	return true


func _road_gap(pos: Vector3) -> float:
	var best := INF
	for i in _edges.size():
		best = minf(best, _gap(pos, _edges[i]))
	return best


## A point ahead on the street center, so a chase can cut the corner without a lane.
func _pursuit_road_point(car: _TrafficCar, dist: float) -> Vector3:
	if car.edge_i < 0 or car.edge_i >= _edges.size():
		return car.center()
	if car.route.is_empty() or car.next_i < 0:
		var player := _player()
		if player != null:
			_retarget(car, _player_center(player))
	if car.next_i < 0:
		car.next_i = _next_edge(car)
	var edge: Dictionary = _edges[car.edge_i]
	var remain := float(edge["length"]) - car.along
	if dist <= remain or car.next_i < 0 or car.next_i >= _edges.size():
		var at := clampf(car.along + dist, 0.0, float(edge["length"]))
		var dir: Vector3 = edge["dir"]
		var a: Vector3 = edge["a"]
		return a + dir * at
	var nxt: Dictionary = _edges[car.next_i]
	var into := clampf(dist - remain, 0.0, float(nxt["length"]))
	var dir_n: Vector3 = nxt["dir"]
	var origin: Vector3 = nxt["a"]
	return origin + dir_n * into


func _note_nearest_edge(car: _TrafficCar) -> void:
	var center := car.center()
	var best := car.edge_i
	var best_gap := INF
	var best_along := car.along
	for i in _edges.size():
		var edge: Dictionary = _edges[i]
		var a: Vector3 = edge["a"]
		var dir: Vector3 = edge["dir"]
		var along := clampf((center - a).dot(dir), 0.0, float(edge["length"]))
		var point := a + dir * along
		var gap := Vector2(point.x - center.x, point.z - center.z).length()
		if gap < best_gap:
			best_gap = gap
			best = i
			best_along = along
	if best < 0:
		return
	if best != car.edge_i:
		car.next_i = -1
	car.edge_i = best
	car.along = best_along


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
	var step := pull * minf(hold * delta, 0.4)
	if car.cop:
		var cap := _yaw_limit(Vector2(car.shove.x, car.shove.z).length()) * _WHEELBASE * delta
		if step.length() > cap:
			step = step.normalized() * cap if cap > 0.0 else Vector3.ZERO
	car.global_position += step
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
	if _pursuing(car) or _stopping(car):
		var player := _player()
		if player != null:
			_retarget(car, _player_center(player))
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
			"limit": _Zones.mps_of(road),
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


func _note_blocks(track: Dictionary) -> void:
	_blocks.clear()
	for raw: Variant in track.get("buildings", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var block: Dictionary = raw
		var half := Vector2(float(block.get("w", 0.0)), float(block.get("d", 0.0))) * 0.5
		if half.x < 0.5 or half.y < 0.5:
			continue
		half += Vector2(_BLOCK_PAD, _BLOCK_PAD)
		_blocks.append({
			"c": Vector2(float(block.get("x", 0.0)), float(block.get("y", 0.0))),
			"h": half,
		})


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
	if _police.heat <= 0.0:
		_joined.clear()
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
		elif car.on_duty and not bool(_joined.get(car.get_instance_id(), false)):
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
	if player != null:
		_join_passed(cops, plan, spots, player_pos)
	for i in cops.size():
		var car := cops[i]
		car.duty = plan[i]
		if car.duty == _Police.PURSUE or car.duty == _Police.STOP:
			_any_pursuit = true
		var pace := _Police.PATROL_MPS
		if car.duty == _Police.PURSUE:
			pace = _Police.PURSUE_MPS
		elif car.duty == _Police.STOP:
			pace = _Police.STOP_MPS
		elif car.duty == _Police.ATTEND and not scene.is_empty():
			var at: Vector3 = scene["pos"]
			var gap := Vector2(at.x - car.center().x, at.z - car.center().z).length()
			pace = 0.0 if gap < 14.0 else _Police.PATROL_MPS
		car.cruise_mps = pace
		# The chase itself steers. Aiming here would fight the lane hold and slide the body.
		car.aiming = false
		car.retarget -= delta
		if car.duty == _Police.PATROL or car.retarget > 0.0:
			continue
		car.retarget = _Police.RETARGET_S
		var hunting := car.duty == _Police.PURSUE or car.duty == _Police.STOP
		var goal := player_pos if hunting else scene_pos
		_retarget(car, goal)


## A chase is already going. A police car the player drives past joins it, and stays on it.
func _join_passed(cops: Array[_TrafficCar], plan: Array[int], spots: Array[Vector3], player_pos: Vector3) -> void:
	if _police.heat <= 0.0:
		_joined.clear()
		return
	var chase := -1
	for duty: int in plan:
		if duty == _Police.PURSUE or duty == _Police.STOP:
			chase = duty
			break
	if chase < 0:
		return
	for i in cops.size():
		var id := cops[i].get_instance_id()
		if plan[i] == chase or _flat_dist(spots[i], player_pos) <= _JOIN_M:
			_joined[id] = true
		if bool(_joined.get(id, false)):
			plan[i] = chase
	var extra: Array[_TrafficCar] = []
	for body: CharacterBody3D in _cars:
		var car := body as _TrafficCar
		if car == null or not car.cop or car.on_duty:
			continue
		if _flat_dist(car.center(), player_pos) > _JOIN_M:
			continue
		_dispatch(car)
		_joined[car.get_instance_id()] = true
		extra.append(car)
	for car: _TrafficCar in extra:
		cops.append(car)
		plan.append(chase)
		spots.append(car.center())


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
