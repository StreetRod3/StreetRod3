extends CharacterBody3D

## One car in the city traffic. The cruise picks its road. A hit is the same
## bump the race uses between two cars.

const _CAR_SCENE := preload("res://scenes/car_vehicle_visual.tscn")
const _WHEELS: Array[String] = ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]
const _MASS_KG := 1360.0
const _CENTER_Z := 1.9
const _BODY_Y := 0.35
const _WHEEL_RADIUS := 0.32

var edge_i: int = 0
var along: float = 0.0
var next_i: int = -1
var cruise_mps: float = 11.0
var lane_bias: float = 0.0
## Extra meters toward the curb while a car that cannot be bumped is catching up.
var curb: float = 0.0
var shove: Vector3 = Vector3.ZERO
var spin: float = 0.0
## Seconds left to let a bump show before the lane pulls the car back.
var loose: float = 0.0
var speed: float = 0.0
var _visual: Node3D
var _roll: float = 0.0


func setup(car_file: String, paint: Color, edge: int, distance: float, pace: float, bias: float) -> void:
	edge_i = edge
	along = distance
	cruise_mps = pace
	lane_bias = bias
	speed = pace
	collision_layer = 2
	collision_mask = 0
	motion_mode = MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 0.5, 4.0)
	shape.shape = box
	shape.position = Vector3(0.0, 0.2, _CENTER_Z)
	add_child(shape)
	_visual = _CAR_SCENE.instantiate() as Node3D
	_visual.name = "CarPivot"
	_visual.position = Vector3(0.0, 0.0, _CENTER_Z)
	_silence(_visual)
	if _visual.has_method(&"prepare_preview"):
		_visual.call(&"prepare_preview", car_file, paint)
	add_child(_visual)


## `center` is the middle of the car on the lane. `floor_mesh` sits the tires on the road.
func place_on(center: Vector3, yaw: float, floor_mesh: MeshInstance3D) -> void:
	rotation.y = yaw
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	global_position = Vector3(center.x, _BODY_Y, center.z) - forward * _CENTER_Z
	shove = forward * cruise_mps
	speed = cruise_mps
	if floor_mesh != null and _visual != null and _visual.has_method(&"align_wheels_to_floor"):
		_visual.call(&"align_wheels_to_floor", floor_mesh)


func center() -> Vector3:
	return global_position + global_transform.basis.z * _CENTER_Z


func roll_wheels(distance: float) -> void:
	if _visual == null:
		return
	_roll = wrapf(_roll + distance / _WHEEL_RADIUS, -TAU, TAU)
	for wname: String in _WHEELS:
		var wheel := _visual.get_node_or_null(wname) as Node3D
		if wheel == null:
			continue
		if not wheel.has_meta(&"rest"):
			wheel.set_meta(&"rest", wheel.transform)
		var rest: Transform3D = wheel.get_meta(&"rest")
		var hub := rest.origin
		var turn := Basis(Vector3.RIGHT, _roll)
		wheel.transform = Transform3D(turn, hub) * Transform3D(Basis.IDENTITY, -hub) * rest


func planar_velocity() -> Vector3:
	return shove


func get_mass_kg() -> float:
	return _MASS_KG


func apply_car_bump(offset: Vector3, new_velocity: Vector3, yaw_kick: float) -> void:
	global_position += offset
	shove = Vector3(new_velocity.x, 0.0, new_velocity.z)
	spin += yaw_kick
	loose = 0.55


func sync_speed() -> void:
	speed = Vector2(shove.x, shove.z).length()


func _silence(node: Node) -> void:
	if node.get("print_debug") != null:
		node.set("print_debug", false)
	for child in node.get_children():
		_silence(child)
