extends Node3D

## One police Fairlane parked on the shoulder near the middle of a road race.
## About one race in seven has it. Once the player drives past, it pulls out
## and chases. A ticket ends the race from `race.gd`.

const _Police := preload("res://scripts/race_police.gd")
const _Traffic := preload("res://scripts/race_traffic_car.gd")
const _CruiseCar := preload("res://scripts/traffic_car.gd")
const _Bump := preload("res://scripts/car_bump.gd")

const _POLICE_CAR := "res://assets/cars/police-fairlane-1957.car"
const _LANE_RATE := 14.0

var _rules: _Police
var _car: _Traffic
var _player: CharacterBody3D
var _track: Node3D
var _bump: _Bump = _Bump.new()
var _pace := 0.0
var _siren: AudioStreamPlayer3D


## Places the car when `police_roll` is inside the chance. A negative roll is a fresh one.
## Returns false when this race has no cop.
func setup(track: Node3D, player: CharacterBody3D, floor_mesh: MeshInstance3D, police_roll: float = -1.0) -> bool:
	_track = track
	_player = player
	_rules = _Police.new()
	var roll := randf() if police_roll < 0.0 else police_roll
	if not _Police.rolled_in(roll):
		return false
	if track == null or not track.has_method(&"sample_at") or not track.has_method(&"get_length"):
		return false
	var length := float(track.call(&"get_length"))
	if length < 40.0:
		return false
	_rules.arm_parked()
	var half := 20.0
	if track.has_method(&"get_half_width"):
		half = float(track.call(&"get_half_width"))
	var shoulder := clampf(half - 3.0, 4.0, maxf(half - 1.5, 4.0))
	_car = _Traffic.new()
	_car.name = "RoadPolice"
	_car.hold_lane = true
	_car.cop = true
	add_child(_car)
	_car.setup(_POLICE_CAR, Color.WHITE, length * 0.5, -shoulder, 0.0, false, floor_mesh)
	_car.step(track, 0.001)
	_mark_block()
	return true


func police_ticketed() -> bool:
	return _rules != null and _rules.ticketed


func police_pursuing() -> bool:
	return _rules != null and _rules.pursuing


func cop_s() -> float:
	if _car == null:
		return 0.0
	return _car.s


func cop_lateral() -> float:
	if _car == null:
		return 0.0
	return _car.lateral


func tick(delta: float) -> void:
	if delta <= 0.0 or _car == null or _rules == null or not _rules.active or _rules.ticketed:
		return
	if _player == null or _track == null:
		return
	var player_s := _player_s()
	var speed := _player_speed()
	var gap := _gap(_car.center(), _body_point(_player))
	var hit := 0.0
	if _player.has_method(&"apply_car_bump") and _player.has_method(&"planar_velocity"):
		hit = _bump.resolve(_player, _car).x
	if not _rules.pursuing:
		if _rules.note_beside(gap, speed, hit):
			_mark_block()
			return
		_rules.note_pass(player_s, _car.s)
	if _rules.pursuing:
		_pace = move_toward(_pace, _Police.pace_for(_car.s, player_s, speed), _Police.PURSUE_ACCEL * delta)
		_car.speed_mps = _pace
		_car.lane_rate = _LANE_RATE
		_car.target_lane = _player_lane()
		_start_siren()
		_car.step(_track, delta)
		_rules.note_chase(gap, speed, _car.s, player_s, delta, hit)
	else:
		_car.step(_track, delta)
	_mark_block()


func _player_s() -> float:
	if _track.has_method(&"closest_sample"):
		return float(_track.closest_sample(_player.global_position).get("s", 0.0))
	return 0.0


func _player_lane() -> float:
	var half := 20.0
	if _track.has_method(&"get_half_width"):
		half = float(_track.call(&"get_half_width"))
	var lat := 0.0
	if _track.has_method(&"closest_sample"):
		lat = float(_track.closest_sample(_player.global_position).get("lateral", 0.0))
	return clampf(lat, -half + 1.5, half - 1.5)


func _player_speed() -> float:
	if _player.has_method(&"get_forward_speed"):
		return absf(float(_player.call(&"get_forward_speed")))
	return 0.0


func _body_point(body: Node3D) -> Vector3:
	if body.has_method(&"center"):
		return body.call(&"center")
	return body.global_position


func _gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _start_siren() -> void:
	if _siren != null or _car == null:
		return
	_siren = AudioStreamPlayer3D.new()
	_siren.name = "Siren"
	_siren.stream = _CruiseCar.siren_stream()
	_siren.max_distance = 70.0
	_siren.unit_size = 14.0
	_siren.volume_db = -8.0
	_car.add_child(_siren)
	_siren.play()


func _mark_block() -> void:
	if _track == null or _car == null or not _track.has_method(&"set_dynamic_blocks"):
		return
	var blocks: Array[Dictionary] = [{
		"s": _car.s - 3.5,
		"to": _car.s + 3.5,
		"low": _car.lateral - 1.25,
		"high": _car.lateral + 1.25,
	}]
	_track.set_dynamic_blocks(blocks)
