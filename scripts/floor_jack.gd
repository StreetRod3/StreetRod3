extends Node3D

## The garage's floor jack (assets/locations/garage/jack.glb, built by
## tools/floor_jack_to_glb.py). Setting `raise` swings the lift arm up about its pivot.
## The saddle rides the arm's tip and stays level. The side links keep their front eye on
## the saddle's post and point back at their spot on the frame. The ram's rod keeps its eye
## on the arm's lever and points back into the cylinder.

## How far the arm swings up at full lift: the saddle goes from 29 cm off the floor to 46.
const MAX_SWING := deg_to_rad(45.0)

## 0 with the saddle down, 1 at full lift.
var raise := 0.0:
	set(value):
		raise = clampf(value, 0.0, 1.0)
		if _arm != null:
			_pose()

var _arm: Node3D
var _saddle: Node3D
var _links: Node3D
var _rod: Node3D
var _tip_local: Vector3
var _lever_local: Vector3
var _tip_rest: Vector3
var _link_front_rest: Vector3
var _link_aim: Vector3
var _rod_aim: Vector3
var _link_rest_angle: float
var _rod_rest_angle: float


func _ready() -> void:
	_arm = get_node("jack_arm") as Node3D
	_saddle = get_node("jack_saddle") as Node3D
	_links = get_node("jack_links") as Node3D
	_rod = get_node("jack_rod") as Node3D
	_tip_local = (_arm.get_node("arm_tip") as Node3D).position
	_lever_local = (_arm.get_node("arm_lever") as Node3D).position
	_link_aim = (get_node("link_aim") as Node3D).position
	_rod_aim = (get_node("rod_aim") as Node3D).position
	_tip_rest = _saddle.position
	_link_front_rest = _links.position
	_link_rest_angle = _angle(_link_front_rest, _link_aim)
	_rod_rest_angle = _angle(_rod.position, _rod_aim)
	_pose()


func _pose() -> void:
	_arm.rotation.z = raise * MAX_SWING
	var tip := _arm.transform * _tip_local
	_saddle.position = tip
	var link_front := _link_front_rest + (tip - _tip_rest)
	_links.position = link_front
	_links.rotation.z = _angle(link_front, _link_aim) - _link_rest_angle
	var lever := _arm.transform * _lever_local
	_rod.position = lever
	_rod.rotation.z = _angle(lever, _rod_aim) - _rod_rest_angle


## Angle in the jack's side view (X forward, Y up) of the line from `back` to `front`.
static func _angle(front: Vector3, back: Vector3) -> float:
	return atan2(front.y - back.y, front.x - back.x)
