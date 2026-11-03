extends RefCounted

## What the driver sees of the springs and shocks. The tires stay on the road and the wheels
## roll and steer, while the body moves over them: it dives, squats, leans, and bounces.
## Only the visuals move. The car's collision box and its place on the road do not.

const _Dynamics := preload("res://scripts/vehicle_dynamics.gd")

const WHEEL_NAMES: Array[String] = ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]
## Below this the front wheels still show a full steering input, so that a car at speed,
## whose rack hardly moves, looks like it is being steered.
const _SHOWN_STEER_RAD := 0.2
const _MIN_WHEEL_RADIUS_M := 0.1
## How quickly measured acceleration reaches the body, in 1/seconds.
const _ACCEL_RESPONSE := 14.0

var _visual: Node3D
var _dynamics: _Dynamics
var _body: Node3D
var _body_rest := Transform3D.IDENTITY
var _lean_center := Vector3.ZERO
## One entry per wheel: its node, resting transform, hub, radius, and how far it has rolled.
var _wheels: Array[Dictionary] = []
var _captured := false
var _last_velocity := Vector3.ZERO
var _long_accel := 0.0
var _lat_accel := 0.0


func setup(visual: Node3D, dynamics: _Dynamics) -> void:
	_visual = visual
	_dynamics = dynamics


## Takes the car as it stands as the resting pose. Call once the visuals have been fitted to
## the ground, before the first pose.
func capture() -> void:
	if _captured or _visual == null:
		return
	_captured = true
	_body = _visual.get_node_or_null("CarBody") as Node3D
	if _body != null:
		_body_rest = _body.transform
	var to_visual := _visual.global_transform.affine_inverse()
	for wheel_name in WHEEL_NAMES:
		var wheel := _visual.get_node_or_null(wheel_name) as Node3D
		if wheel == null or not wheel.is_visible_in_tree():
			_wheels.append({})
			continue
		var bounds := _mesh_bounds(wheel, to_visual)
		if bounds.size.length_squared() < 0.0001:
			_wheels.append({})
			continue
		_wheels.append({
			"node": wheel,
			"rest": wheel.transform,
			"hub": bounds.get_center(),
			"radius": maxf(bounds.size.y * 0.5, _MIN_WHEEL_RADIUS_M),
			"front": wheel_name.contains("Front"),
			"rolled": 0.0,
		})
	if _dynamics != null:
		var cg := _dynamics.cg_local - _visual.position
		_lean_center = Vector3(cg.x, _dynamics.config.cg_height_m, cg.z)


## Runs the springs and shocks for a car whose tires are not doing so, from how its velocity
## is changing. `velocity` is its planar velocity and `yaw` its heading.
func ride_from_motion(dt: float, velocity: Vector3, yaw: float) -> void:
	if dt <= 0.0 or _dynamics == null:
		return
	var accel := (velocity - _last_velocity) / dt
	_last_velocity = velocity
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var blend := 1.0 - exp(-_ACCEL_RESPONSE * dt)
	_long_accel = lerpf(_long_accel, accel.dot(forward), blend)
	_lat_accel = lerpf(_lat_accel, accel.dot(right), blend)
	_dynamics.ride(dt, _long_accel, _lat_accel)


## Keeps the measured velocity current while the tires run the springs instead.
func note_velocity(velocity: Vector3) -> void:
	_last_velocity = velocity


## How the body sits, in the space of the car node rather than of the visuals.
func lean_in_car_space() -> Transform3D:
	if _visual == null:
		return Transform3D.IDENTITY
	return _visual.transform * _lean_transform() * _visual.transform.affine_inverse()


func _lean_transform() -> Transform3D:
	if _dynamics == null:
		return Transform3D.IDENTITY
	var turn := Basis(Vector3.RIGHT, -_dynamics.body_pitch()) * Basis(Vector3.BACK, _dynamics.body_roll())
	var lift := Vector3(0.0, _dynamics.body_heave(), 0.0)
	return Transform3D(Basis.IDENTITY, _lean_center + lift) * Transform3D(turn, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -_lean_center)


## Moves the body and wheels to match. `steer` is the road-wheel angle in radians, and
## `steer_input` the driver's input, -1 to 1.
func pose(dt: float, speed: float, steer: float, steer_input: float) -> void:
	if not _captured:
		return
	if _body != null:
		_body.transform = _lean_transform() * _body_rest
	var sim_wheels: Array = _dynamics.wheels() if _dynamics != null else []
	var shown := _shown_steer(steer, steer_input)
	for i in _wheels.size():
		var wheel: Dictionary = _wheels[i]
		if wheel.is_empty():
			continue
		wheel["rolled"] = wrapf(float(wheel["rolled"]) + speed / float(wheel["radius"]) * dt, -TAU, TAU)
		var turn := Basis(Vector3.RIGHT, float(wheel["rolled"]))
		if bool(wheel["front"]):
			turn = Basis(Vector3.UP, shown) * turn
		var hub: Vector3 = wheel["hub"]
		if i < sim_wheels.size():
			hub += Vector3(0.0, (sim_wheels[i] as _Dynamics.Wheel).hub_lift, 0.0)
		var mesh := Transform3D(turn, hub) * Transform3D(Basis.IDENTITY, -(wheel["hub"] as Vector3))
		(wheel["node"] as Node3D).transform = mesh * (wheel["rest"] as Transform3D)


func _shown_steer(steer: float, steer_input: float) -> float:
	var floor_angle := absf(steer_input) * _SHOWN_STEER_RAD
	if absf(steer) >= floor_angle:
		return steer
	return signf(steer_input) * floor_angle


func _mesh_bounds(node: Node, to_space: Transform3D) -> AABB:
	var merged := AABB()
	var started := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var local := mi.mesh.get_aabb()
		merged = AABB(to_space * mi.global_transform * local.get_endpoint(0), Vector3.ZERO)
		for i in range(1, 8):
			merged = merged.expand(to_space * mi.global_transform * local.get_endpoint(i))
		started = true
	for child in node.get_children():
		var bounds := _mesh_bounds(child, to_space)
		if bounds.size == Vector3.ZERO:
			continue
		merged = merged.merge(bounds) if started else bounds
		started = true
	return merged
