extends RefCounted

## Pulls a finished race car onto the right side of the road and stops it there.

const _Dynamics := preload("res://scripts/vehicle_dynamics.gd")

## How far the car's center stays inside the right edge.
const _EDGE_INSET := 2.6
## The car behind leaves this much road before it pulls over.
const _FOLLOW_GAP := 9.0
const _BRAKE := 8.0
const _YIELD_BRAKE := 13.0
## Sideways speed while easing over, so the move stays gentle at race pace.
const _LATERAL_RATE := 4.2


static func step(car: CharacterBody3D, dynamics: _Dynamics, delta: float, speed: float, slot: float) -> float:
	var here := _frame(car)
	var road_yaw := float(here.get("yaw", car.rotation.y))
	var lateral := float(here.get("lateral", 0.0))
	var my_s := float(here.get("s", 0.0))
	var lat_err := _target_lateral(here, slot) - lateral
	var steer_err := lat_err
	var yielding := _should_yield(car, my_s, slot)
	if yielding:
		speed = move_toward(speed, 0.0, _YIELD_BRAKE * delta)
		steer_err *= 0.35
	else:
		var rate := _BRAKE
		if absf(lat_err) < 0.45:
			rate = 12.0
		speed = move_toward(speed, 0.0, rate * delta)
		if absf(lat_err) > 1.5 and speed < 4.0:
			speed = move_toward(speed, 4.5, 3.0 * delta)
	speed = maxf(speed, 0.0)
	var heading := car.rotation.y
	if absf(lat_err) < 0.35 and speed < 0.6:
		speed = 0.0
		heading = road_yaw
	else:
		var max_angle := minf(atan(_LATERAL_RATE / maxf(speed, 3.5)), 0.42)
		var look := clampf(steer_err * 0.11, -max_angle, max_angle)
		var desired := road_yaw + look
		heading = lerp_angle(heading, desired, 1.0 - exp(-5.0 * delta))
	var nose := Vector3(sin(heading), 0.0, cos(heading))
	dynamics.yaw = heading
	dynamics.yaw_rate = 0.0
	dynamics.cg_velocity = nose * speed
	dynamics.update_steering(delta, 0.0)
	dynamics.pose_body(car, speed > 0.2)
	car.velocity = nose * speed
	car.move_and_slide()
	return speed


static func _should_yield(car: Node3D, my_s: float, slot: float) -> bool:
	var other := _other(car)
	if other == null:
		return false
	var other_s := float(_frame(other).get("s", my_s))
	var behind := other_s > my_s + 0.4 or (absf(other_s - my_s) <= 0.4 and slot > 0.0)
	return behind and my_s > other_s - _FOLLOW_GAP


static func _target_lateral(here: Dictionary, slot: float) -> float:
	var right_ext := float(here.get("right_ext", 20.0))
	var left_ext := float(here.get("left_ext", 20.0))
	var edge := right_ext - _EDGE_INSET - slot
	return clampf(edge, -left_ext + 1.8, right_ext - 1.5)


static func _frame(car: Node3D) -> Dictionary:
	var race := car.get_parent()
	var track: Node = null
	if race != null and race.has_method(&"get_race_track"):
		track = race.get_race_track()
	if track != null and track.has_method(&"closest_sample"):
		return track.closest_sample(car.global_position)
	return {
		"yaw": 0.0,
		"lateral": car.global_position.x,
		"s": car.global_position.z,
		"left_ext": 20.0,
		"right_ext": 20.0,
	}


static func _other(car: Node) -> Node3D:
	var race := car.get_parent()
	if race == null:
		return null
	for child in race.get_children():
		if child == car or not child is Node3D:
			continue
		if child.has_method(&"begin_park"):
			return child as Node3D
	return null
