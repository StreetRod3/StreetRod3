extends RefCounted

## A camera that hangs back from a car: it swings round after the car in a turn and drifts
## with its acceleration, so the car moves in the frame.

## How quickly the camera swings round after the car, in 1/seconds. Lower lags more.
const _YAW_FOLLOW := 3.2
## The camera never falls further than this behind the car's heading, in radians.
const _YAW_LAG_MAX := 0.42
## How quickly the camera's drift follows acceleration, in 1/seconds.
const _SWAY_RESPONSE := 2.6
## Meters of drift per m/s² of acceleration, along the car and across it.
const _SURGE_PER_ACCEL := 0.07
const _SWAY_PER_ACCEL := 0.09
const _SURGE_MAX := 1.1
const _SWAY_MAX := 0.7
## Meters the camera jumps per m/s a hit changes the car's speed, and how fast that dies away.
const _JOLT_PER_HIT := 0.035
const _JOLT_MAX := 0.6
const _JOLT_DECAY := 7.0

var _yaw: float = 0.0
var _drift := Vector2.ZERO
var _last_velocity := Vector3.ZERO
var _jolt: float = 0.0


## Puts the camera straight behind a car that is not moving.
func settle(yaw: float) -> void:
	_yaw = yaw
	_drift = Vector2.ZERO
	_last_velocity = Vector3.ZERO


func jolt(speed_change: float) -> void:
	_jolt = minf(_jolt + speed_change * _JOLT_PER_HIT, _JOLT_MAX)


## `center` is where the car turns about, and `rest` where the camera sits with the car
## still, both in the car's space. `velocity` is the car's planar velocity.
func place(camera: Camera3D, car: Node3D, center: Vector3, rest: Transform3D, velocity: Vector3, delta: float) -> void:
	var yaw := car.rotation.y
	if delta > 0.0:
		var accel := (velocity - _last_velocity) / delta
		var surge := accel.dot(Vector3(sin(yaw), 0.0, cos(yaw))) * _SURGE_PER_ACCEL
		var sway := accel.dot(Vector3(cos(yaw), 0.0, -sin(yaw))) * _SWAY_PER_ACCEL
		var target := Vector2(clampf(sway, -_SWAY_MAX, _SWAY_MAX), clampf(surge, -_SURGE_MAX, _SURGE_MAX))
		_drift = _drift.lerp(target, 1.0 - exp(-_SWAY_RESPONSE * delta))
		_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-_YAW_FOLLOW * delta))
		_yaw = yaw - clampf(wrapf(yaw - _yaw, -PI, PI), -_YAW_LAG_MAX, _YAW_LAG_MAX)
	_last_velocity = velocity
	# Around the car's center, keeping the road's slope but none of the car's heading.
	var hang := Transform3D(Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, car.rotation.x), car.global_transform * center)
	var pos := rest.origin - center + Vector3(-_drift.x, 0.0, -_drift.y)
	if _jolt > 0.001:
		pos += Vector3(randf_range(-_jolt, _jolt), randf_range(-_jolt, _jolt), 0.0)
		_jolt *= exp(-_JOLT_DECAY * delta)
	camera.global_transform = hang * Transform3D(rest.basis, pos)
