extends CharacterBody3D

## One car in the city traffic. The cruise picks its road. A hit is the same
## bump the race uses between two cars.

const _CAR_SCENE := preload("res://scenes/car_vehicle_visual.tscn")
const _LicensePlate := preload("res://scripts/license_plate.gd")
const _WHEELS: Array[String] = ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]
const _MASS_KG := 1360.0
const _CENTER_Z := 1.9
const _BODY_Y := 0.35
const _WHEEL_RADIUS := 0.32
## Traffic is not drawn past this many meters from the camera.
const _DRAW_RANGE := 150.0

var edge_i: int = 0
var along: float = 0.0
var next_i: int = -1
## Street node this car is driving to, and the roads left to take to get there.
var destination: int = -1
var route: Array[int] = []
var cruise_mps: float = 11.0
var lane_bias: float = 0.0
## Extra meters toward the curb while a car that cannot be bumped is catching up.
var curb: float = 0.0
var shove: Vector3 = Vector3.ZERO
var spin: float = 0.0
## Seconds left to let a bump show before the lane pulls the car back.
var loose: float = 0.0
var speed: float = 0.0
## A patrol car. `on_duty` is the ones actually out; the rest of the pool drive as traffic
## until the heat calls them. The cruise traffic director sets `duty`. A chase leaves the lane.
## Where this car waits. Traffic drives the streets. The others sit until the heat calls them.
const POST_TRAFFIC := 0
const POST_CURB := 1
const POST_STATION := 2
var cop := false
var on_duty := false
var post := POST_TRAFFIC
## Sitting in its spot. `returning` is on the way back there after a call.
var parked := false
var returning := false
var stall := Vector3.ZERO
var stall_yaw := 0.0
var stall_edge := -1
var stall_along := 0.0
var duty := 0
var aiming := false
var aim_at := Vector3.ZERO
## Seconds left sitting at the curb after a crash.
var held := 0.0
## How long this car has been off the lane or spun across it.
var odd_s := 0.0
## A chase that has stopped across the road. Above zero the car is backing up.
## Below zero it is creeping back onto the street.
var stuck_s := 0.0
var unstick := 0.0
## How long this car has been stopped behind another, and when it gives up waiting.
var wait_s := 0.0
var wait_for := 0.0
## Seconds left swinging out to pass a stopped car. `pass_side` is which way.
var pass_s := 0.0
var pass_side := 1.0
var patrol_i := 0
var retarget := 0.0
## Set on the first frame of a new contact with the player, so a cop beside the car
## does not count as a fresh hit every step.
var struck := false
var _visual: Node3D
var _roll: float = 0.0
## Empty marker the ticket bubble follows.
var _bar: Node3D
var _lightbar: MeshInstance3D
var _red_domes: Array[StandardMaterial3D] = []
var _blue_domes: Array[StandardMaterial3D] = []
var _beacons := false
## One full red-then-blue blink per second. Each color is on for half of that.
const _BLINK_HZ := 2.5
var _blink := 0.0
var _siren: AudioStreamPlayer3D

static var _siren_wav: AudioStreamWAV


func _ready() -> void:
	add_to_group(&"traffic_cars")


func setup(car_file: String, paint: Color, edge: int, distance: float, pace: float, bias: float) -> void:
	add_to_group(&"traffic_cars")
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
		# Each car its own plate, not one for every car of a model.
		_visual.set(&"preview_plate", _LicensePlate.serial(str(get_instance_id())))
		_visual.call(&"prepare_preview", car_file, paint)
	add_child(_visual)
	_draw_near(_visual)


## Past `_DRAW_RANGE` the car is a few pixels tall, and its models cost as much as close up.
func _draw_near(node: Node) -> void:
	var geo := node as GeometryInstance3D
	if geo != null:
		geo.visibility_range_end = _DRAW_RANGE
	for child in node.get_children():
		_draw_near(child)


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


## Swaps the body. Used when a traffic car is taken over as a police Fairlane.
func use_car(car_file: String) -> void:
	if _visual != null and _visual.has_method(&"preview_listing"):
		_visual.call(&"preview_listing", car_file, Color.WHITE)


## The Fairlane keeps its own paint. Its two roof beacons are the chase signal.
## RoofLight is only the point the ticket bubble sits on.
func make_cop() -> void:
	cop = true
	cruise_mps = 11.0
	_bar = Node3D.new()
	_bar.name = "RoofLight"
	_bar.position = Vector3(0.0, 1.7, _CENTER_Z)
	add_child(_bar)
	_arm_beacons()
	_siren = AudioStreamPlayer3D.new()
	_siren.name = "Siren"
	_siren.stream = _siren_stream()
	_siren.max_distance = 70.0
	_siren.unit_size = 14.0
	_siren.volume_db = -8.0
	_siren.position = _bar.position
	add_child(_siren)


## Puts the car on the job, or back into ordinary traffic. Off duty, the beacons go dark.
func serve(on: bool) -> void:
	on_duty = on
	if on:
		return
	duty = 0
	aiming = false
	struck = false
	_set_beacons(false, 0.0)
	if _siren != null and _siren.playing:
		_siren.stop()


## `lights` blinks the red and blue roof domes. `wail` is the siren.
func show_call(lights: bool, wail: bool, delta: float) -> void:
	if not on_duty:
		_set_beacons(false, 0.0)
		if _siren != null and _siren.playing:
			_siren.stop()
		return
	_set_beacons(lights, delta)
	if _siren == null:
		return
	if wail and not _siren.playing:
		_siren.play()
	elif not wail and _siren.playing:
		_siren.stop()


## The model is one light bar: a red dome, a blue dome, and a white tube between them.
## The tube stays hidden. A chase blinks the two domes, and nothing on the bar spins.
func _arm_beacons() -> void:
	if _lightbar != null and not is_instance_valid(_lightbar):
		_lightbar = null
		_red_domes.clear()
		_blue_domes.clear()
		_beacons = false
	if _beacons or _visual == null:
		return
	var bar := _find_named(_visual, "police_lightbar") as MeshInstance3D
	if bar == null or bar.mesh == null:
		return
	var mesh := bar.mesh
	var red_i := -1
	var blue_i := -1
	for i in mesh.get_surface_count():
		var name := _surface_name(mesh, i)
		if name.contains("dome_red"):
			red_i = i
			_red_domes.append(_dome_lamp(bar, i, Color(1.0, 0.04, 0.02)))
		elif name.contains("dome_blue"):
			blue_i = i
			_blue_domes.append(_dome_lamp(bar, i, Color(0.08, 0.25, 1.0)))
		elif name.contains("bulb"):
			_hide_surface(bar, i)
	if red_i < 0 and mesh.get_surface_count() >= 5:
		_red_domes.append(_dome_lamp(bar, 2, Color(1.0, 0.04, 0.02)))
		_blue_domes.append(_dome_lamp(bar, 3, Color(0.08, 0.25, 1.0)))
		_hide_surface(bar, 4)
	if _red_domes.is_empty() or _blue_domes.is_empty():
		return
	_lightbar = bar
	_beacons = true
	_glow(_red_domes, false)
	_glow(_blue_domes, false)


func _set_beacons(on: bool, delta: float) -> void:
	_arm_beacons()
	var period := 1.0 / _BLINK_HZ
	if on:
		_blink = fmod(_blink + delta, period)
	var red_on := on and _blink < period * 0.5
	_glow(_red_domes, red_on)
	_glow(_blue_domes, on and not red_on)


func _glow(domes: Array[StandardMaterial3D], on: bool) -> void:
	for mat: StandardMaterial3D in domes:
		var tint := Color(mat.emission.r, mat.emission.g, mat.emission.b)
		mat.emission_energy_multiplier = 5.0 if on else 0.0
		mat.albedo_color = tint if on else Color(tint.r * 0.12, tint.g * 0.12, tint.b * 0.12)


## Flat color, so the dome reads as on or off without a scene light.
func _dome_lamp(bar: MeshInstance3D, index: int, tint: Color) -> StandardMaterial3D:
	var lamp := StandardMaterial3D.new()
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.emission_enabled = true
	lamp.emission = tint
	lamp.emission_energy_multiplier = 0.0
	lamp.albedo_color = Color(tint.r * 0.12, tint.g * 0.12, tint.b * 0.12)
	bar.set_surface_override_material(index, lamp)
	return lamp


func _hide_surface(bar: MeshInstance3D, index: int) -> void:
	if index < 0:
		return
	var hide := StandardMaterial3D.new()
	hide.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hide.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	hide.emission_enabled = false
	bar.set_surface_override_material(index, hide)


func _surface_name(mesh: Mesh, index: int) -> String:
	var mat := mesh.surface_get_material(index)
	if mat == null:
		return ""
	return mat.resource_name.to_lower()


func _find_named(node: Node, want: String) -> Node:
	if str(node.name).begins_with(want):
		return node
	for child in node.get_children():
		var found := _find_named(child, want)
		if found != null:
			return found
	return null


static func siren_stream() -> AudioStreamWAV:
	return _siren_stream()


static func _siren_stream() -> AudioStreamWAV:
	if _siren_wav != null:
		return _siren_wav
	const rate := 22050
	var seconds := 1.1
	var samples := PackedFloat32Array()
	samples.resize(int(seconds * rate))
	for i in samples.size():
		var t := float(i) / float(rate)
		var freq := 920.0 if t >= 0.55 else 680.0
		samples[i] = sin(TAU * freq * t) * 0.32
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	_siren_wav = wav
	return wav


func _silence(node: Node) -> void:
	if node.get("print_debug") != null:
		node.set("print_debug", false)
	for child in node.get_children():
		_silence(child)
