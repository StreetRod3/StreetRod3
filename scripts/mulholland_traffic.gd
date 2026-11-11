extends Node3D

## Manages dynamic civilian traffic on Mulholland Drive during a race.
## Spawns cars dynamically in a horizon ahead of the racers, despawns them once
## passed, avoids spawning on bridges or near obstacles, and resolves multi-car bumps.

const _RaceTrafficCar := preload("res://scripts/race_traffic_car.gd")
const _CarBump := preload("res://scripts/car_bump.gd")
const _ShopSounds := preload("res://scripts/shop_sounds.gd")
const _TrackFile := preload("res://scripts/track_file.gd")

const _MAX_ACTIVE := 3
const _MIN_SPAWN_AHEAD := 110.0
const _MAX_SPAWN_AHEAD := 190.0
const _DESPAWN_BEHIND := 45.0
const _START_SAFE_ZONE := 90.0
const _FINISH_SAFE_ZONE := 60.0
const _MIN_CAR_GAP := 35.0
const _ONCOMING_CHANCE := 0.75

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

var _track: Node3D
var _player: CharacterBody3D
var _opponent: CharacterBody3D
var _floor_mesh: MeshInstance3D
var _car_files: Array[String] = []
var _active_cars: Array[CharacterBody3D] = []
var _bump: _CarBump = _CarBump.new()
var _car_counter: int = 0
var _spawn_cooldown: float = 0.0


func setup(track: Node3D, player: CharacterBody3D, opponent: CharacterBody3D, floor_mesh: MeshInstance3D, car_files: Array[String]) -> void:
	_track = track
	_player = player
	_opponent = opponent
	_floor_mesh = floor_mesh
	_car_files = car_files


func _exit_tree() -> void:
	if _track != null and _track.has_method(&"clear_dynamic_blocks"):
		_track.clear_dynamic_blocks()


func tick(delta: float) -> void:
	if delta <= 0.0 or _track == null:
		return

	# 1. Step all active traffic cars
	for car_body: CharacterBody3D in _active_cars:
		var car := car_body as _RaceTrafficCar
		if car != null:
			car.step(_track, delta)

	# 2. Despawn cars that have fallen behind or reached track limits
	_check_despawn()

	# 3. Dynamic spawning in the forward horizon
	_update_spawner(delta)

	# 4. Resolve bumps between cars (Traffic-to-Traffic, Traffic-to-Player, Traffic-to-Opponent)
	_resolve_collisions()

	# 5. Update dynamic obstacle blocks on track so rival dodges traffic
	_update_dynamic_blocks()


func _get_player_s() -> float:
	if _player != null and _track != null and _track.has_method(&"closest_sample"):
		return float(_track.closest_sample(_player.global_position).get("s", 0.0))
	return 0.0


func _get_opponent_s() -> float:
	if _opponent != null and _opponent.has_method(&"get_path_s"):
		return _opponent.get_path_s()
	if _opponent != null and _track != null and _track.has_method(&"closest_sample"):
		return float(_track.closest_sample(_opponent.global_position).get("s", 0.0))
	return 0.0


func _check_despawn() -> void:
	var p_s := _get_player_s()
	var o_s := _get_opponent_s()
	var trail_s := minf(p_s, o_s)
	var track_len: float = _track.get_length() if _track.has_method(&"get_length") else 2950.0

	var kept: Array[CharacterBody3D] = []
	for car_body: CharacterBody3D in _active_cars:
		var car := car_body as _RaceTrafficCar
		if car == null:
			continue

		var should_despawn := false
		if car.is_oncoming:
			# Despawn oncoming car if it passed behind trailing racer or reached near start
			if car.s < trail_s - _DESPAWN_BEHIND or car.s <= 10.0:
				should_despawn = true
		else:
			# Despawn same-direction car if trailing racer has passed it or it reached near finish
			if car.s < trail_s - _DESPAWN_BEHIND or car.s >= track_len - 20.0:
				should_despawn = true

		if should_despawn:
			car.queue_free()
		else:
			kept.append(car)

	_active_cars = kept


func _update_spawner(delta: float) -> void:
	if _active_cars.size() >= _MAX_ACTIVE or _car_files.is_empty():
		return

	_spawn_cooldown = maxf(_spawn_cooldown - delta, 0.0)
	if _spawn_cooldown > 0.0:
		return

	var p_s := _get_player_s()
	var o_s := _get_opponent_s()
	var lead_s := maxf(p_s, o_s)
	var track_len: float = _track.get_length() if _track.has_method(&"get_length") else 2950.0

	# Don't spawn during start launch safe zone or near finish line
	if lead_s < _START_SAFE_ZONE or lead_s > track_len - _FINISH_SAFE_ZONE - _MIN_SPAWN_AHEAD:
		return

	# Candidate spawn location ahead of leader
	var spawn_s := lead_s + randf_range(_MIN_SPAWN_AHEAD, _MAX_SPAWN_AHEAD)
	if spawn_s > track_len - _FINISH_SAFE_ZONE:
		return

	# Don't spawn on a bridge
	var sample: Dictionary = _track.sample_at(spawn_s)
	if sample.get("road_type") == _TrackFile.ROAD_BRIDGE:
		_spawn_cooldown = 0.4
		return

	# Ensure minimum distance from other active traffic cars
	for car_body: CharacterBody3D in _active_cars:
		var other := car_body as _RaceTrafficCar
		if other != null and absf(other.s - spawn_s) < _MIN_CAR_GAP:
			_spawn_cooldown = 0.5
			return

	# Determine car direction and lane
	var is_oncoming := randf() < _ONCOMING_CHANCE
	var lane := 2.0 if is_oncoming else -2.0
	var pace := randf_range(11.5, 15.5) if is_oncoming else randf_range(9.0, 12.5)
	var bias := randf_range(-0.25, 0.25)
	var paint: Color = _PAINTS[randi() % _PAINTS.size()]
	var car_file: String = _car_files[randi() % _car_files.size()]

	var car := _RaceTrafficCar.new()
	_car_counter += 1
	car.name = "MulhollandTrafficCar%d" % _car_counter
	car.lane_bias = bias
	add_child(car)
	car.setup(car_file, paint, spawn_s, lane, pace, is_oncoming, _floor_mesh)

	# Set initial position
	car.step(_track, 0.001)

	_active_cars.append(car)
	_spawn_cooldown = randf_range(1.2, 2.5)


func _resolve_collisions() -> void:
	# 1. Traffic vs Traffic
	for i in _active_cars.size():
		for j in range(i + 1, _active_cars.size()):
			_bump.resolve(_active_cars[i], _active_cars[j])

	# 2. Traffic vs Player
	if _player != null and _player.has_method(&"apply_car_bump") and not _is_wrecked(_player):
		var hardest_hit := 0.0
		for car_body: CharacterBody3D in _active_cars:
			var hit := _bump.resolve(_player, car_body)
			if hit.x > 0.05:
				hardest_hit = maxf(hardest_hit, hit.x)
				if _player.has_method(&"take_hit"):
					_player.call(&"take_hit", hit.x)
		if hardest_hit > 1.2:
			_crunch(hardest_hit)

	# 3. Traffic vs Opponent Rival
	if _opponent != null and _opponent.has_method(&"apply_car_bump") and not _is_wrecked(_opponent):
		var hardest_hit := 0.0
		for car_body: CharacterBody3D in _active_cars:
			var hit := _bump.resolve(_opponent, car_body)
			if hit.x > 0.05:
				hardest_hit = maxf(hardest_hit, hit.x)
				if _opponent.has_method(&"take_hit"):
					_opponent.call(&"take_hit", hit.x)
		if hardest_hit > 1.2:
			_crunch(hardest_hit)

	for car_body: CharacterBody3D in _active_cars:
		var car := car_body as _RaceTrafficCar
		if car != null:
			car.sync_speed()


func _update_dynamic_blocks() -> void:
	if _track == null or not _track.has_method(&"set_dynamic_blocks"):
		return

	var blocks: Array[Dictionary] = []
	for car_body: CharacterBody3D in _active_cars:
		var car := car_body as _RaceTrafficCar
		if car == null:
			continue
		blocks.append({
			"s": car.s - 3.5,
			"to": car.s + 3.5,
			"low": car.lateral - 1.25,
			"high": car.lateral + 1.25,
		})

	_track.set_dynamic_blocks(blocks)


func _is_wrecked(car: Node) -> bool:
	return car.has_method(&"is_wrecked") and bool(car.call(&"is_wrecked"))


func _crunch(amount: float) -> void:
	var crunch := AudioStreamPlayer.new()
	crunch.stream = _ShopSounds.stream("thud")
	crunch.volume_db = lerpf(-12.0, 4.0, clampf(amount / 10.0, 0.0, 1.0))
	crunch.finished.connect(crunch.queue_free)
	add_child(crunch)
	crunch.play()
