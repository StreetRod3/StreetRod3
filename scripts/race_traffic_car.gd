extends CharacterBody3D

## A civilian car driving on Mulholland Drive during a race.
## Follows the track's 3D spline surface (including elevation, pitch, and roll),
## steers around obstacles, rolls wheels, and participates in car bumps with racers.

const _CAR_SCENE := preload("res://scenes/car_vehicle_visual.tscn")
const _WHEELS: Array[String] = ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]
const _MASS_KG := 1360.0
const _CENTER_Z := 1.9
const _WHEEL_RADIUS := 0.32
const _ROAD_BASE_Y := 0.35
const _ROAD_PITCH_SPAN := 8.0

var s: float = 0.0
var lateral: float = 0.0
var target_lane: float = 2.0
var lane_bias: float = 0.0
var speed_mps: float = 12.0
var is_oncoming: bool = true

var shove: Vector3 = Vector3.ZERO
var spin: float = 0.0
var loose: float = 0.0
var speed: float = 0.0
var _visual: Node3D
var _roll: float = 0.0


func _ready() -> void:
	add_to_group(&"traffic_cars")


func setup(car_file: String, paint: Color, track_s: float, start_lane: float, pace: float, oncoming: bool, floor_mesh: MeshInstance3D = null) -> void:
	add_to_group(&"traffic_cars")
	s = track_s
	lateral = start_lane
	target_lane = start_lane
	speed_mps = pace
	is_oncoming = oncoming
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

	_setup_lights(oncoming)

	if floor_mesh != null and _visual.has_method(&"align_wheels_to_floor"):
		_visual.call(&"align_wheels_to_floor", floor_mesh)


func step(track: Node3D, delta: float) -> void:
	if track == null or not track.has_method(&"sample_at"):
		return

	if loose > 0.0:
		loose = maxf(loose - delta, 0.0)
		global_position += shove * delta
		rotation.y += spin * delta
		spin = move_toward(spin, 0.0, 4.0 * delta)
		shove = shove.move_toward(Vector3.ZERO, 6.0 * delta)
		var center_pt := center()
		if track.has_method(&"closest_sample"):
			var cur_sample: Dictionary = track.closest_sample(center_pt)
			s = float(cur_sample.get("s", s))
			lateral = float(cur_sample.get("lateral", lateral))
		var ground_y: float = track.surface_height(global_position)
		global_position.y = ground_y + _ROAD_BASE_Y
		roll_wheels(shove.length() * delta)
		sync_speed()
		return

	# Obstacle avoidance: steer towards clear lane
	var look: float = -18.0 if is_oncoming else 18.0
	var clear_lane := target_lane + lane_bias
	if track.has_method(&"lane_around"):
		clear_lane = track.lane_around(s, target_lane + lane_bias, look)
	lateral = move_toward(lateral, clear_lane, 3.5 * delta)

	# Progress along track distance s
	var dist_step := speed_mps * delta
	if is_oncoming:
		s -= dist_step
	else:
		s += dist_step

	# Align with track spline sample
	var sample: Dictionary = track.sample_at(s)
	var base_pos: Vector3 = sample.get("position", Vector3.ZERO)
	var right_vec: Vector3 = sample.get("right", Vector3.RIGHT)
	var center_pos := base_pos + right_vec * lateral
	var ground_h: float = track.surface_height(center_pos)
	center_pos.y = ground_h + _ROAD_BASE_Y

	var track_yaw: float = float(sample.get("yaw", 0.0))
	var car_yaw := wrapf(track_yaw + PI, -PI, PI) if is_oncoming else track_yaw
	rotation.y = car_yaw

	var forward := Vector3(sin(car_yaw), 0.0, cos(car_yaw))
	global_position = center_pos - forward * _CENTER_Z
	shove = forward * speed_mps
	speed = speed_mps

	# Pitch & Roll
	var ahead_h: float = track.surface_height(global_position + forward * _ROAD_PITCH_SPAN)
	var behind_h: float = track.surface_height(global_position - forward * _ROAD_PITCH_SPAN)
	rotation.x = -atan2(ahead_h - behind_h, _ROAD_PITCH_SPAN * 2.0)
	if track.has_method(&"surface_roll"):
		rotation.z = track.surface_roll(global_position, car_yaw)

	roll_wheels(dist_step)


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
	loose = 0.65


func sync_speed() -> void:
	speed = Vector2(shove.x, shove.z).length()


func _setup_lights(_oncoming: bool) -> void:
	# Front headlights (emissive boxes)
	var head_mat := StandardMaterial3D.new()
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head_mat.albedo_color = Color(1.0, 0.95, 0.8)

	# Rear taillights (emissive red boxes)
	var tail_mat := StandardMaterial3D.new()
	tail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tail_mat.albedo_color = Color(0.95, 0.08, 0.05)

	var lamp_box := BoxMesh.new()
	lamp_box.size = Vector3(0.18, 0.1, 0.06)

	for x_pos: float in [-0.65, 0.65]:
		var hl := MeshInstance3D.new()
		hl.mesh = lamp_box
		hl.material_override = head_mat
		hl.position = Vector3(x_pos, 0.42, 3.88)
		add_child(hl)

	for x_pos: float in [-0.65, 0.65]:
		var tl := MeshInstance3D.new()
		tl.mesh = lamp_box
		tl.material_override = tail_mat
		tl.position = Vector3(x_pos, 0.45, -0.05)
		add_child(tl)

	var spot := SpotLight3D.new()
	spot.position = Vector3(0.0, 0.45, 3.85)
	spot.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	spot.spot_range = 24.0
	spot.spot_angle = 38.0
	spot.spot_attenuation = 1.3
	spot.light_color = Color(1.0, 0.95, 0.8)
	spot.light_energy = 0.9
	spot.shadow_enabled = false
	spot.distance_fade_enabled = true
	spot.distance_fade_begin = 40.0
	spot.distance_fade_length = 25.0
	add_child(spot)


func _silence(node: Node) -> void:
	if node.get("print_debug") != null:
		node.set("print_debug", false)
	for child in node.get_children():
		_silence(child)
