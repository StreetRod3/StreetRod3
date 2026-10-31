extends Node3D

## Night drive-in. Click the man, pick a rival, and their car drives in from the left.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _CAR_SCENE := preload("res://scenes/car_vehicle_visual.tscn")
const _SpeechBubble := preload("res://scenes/speech_bubble.tscn")
## Upright height of the rival's head, in meters.
const _HEAD_HEIGHT := 0.39

## Diner, parked cars, and the man sit this far behind the rival's drive lane.
const _SET_BACK := 4.0
const _HALF_W := 11.0
const _WALL_H := 3.62
const _WALL_T := 0.3
const _WALL := Color(0.84, 0.78, 0.68)
const _RED := Color(0.62, 0.08, 0.09)
const _SKIN := Color(0.76, 0.58, 0.44)
const _HAIR := Color(0.1, 0.07, 0.06)
const _SHOE := Color(0.14, 0.11, 0.09)

const _BULB_COLORS: Array[Color] = [
	Color(1.0, 0.16, 0.18),
	Color(1.0, 0.84, 0.22),
	Color(0.25, 0.95, 1.0),
	Color(0.35, 1.0, 0.42),
	Color(1.0, 0.38, 0.86),
]

const _WINDOWS: Array[Dictionary] = [
	{"x0": -10.15, "x1": -7.45, "kind": "dining"},
	{"x0": -7.0, "x1": -4.3, "kind": "dining"},
	{"x0": -3.85, "x1": -1.15, "kind": "dining"},
	{"x0": -0.7, "x1": 2.0, "kind": "dining"},
	{"x0": 2.45, "x1": 5.15, "kind": "dining"},
	{"x0": 5.6, "x1": 9.05, "kind": "order"},
]

const _RIVAL_CRUISE_MPS := 5.0
const _RIVAL_IDLE_SEC := 6.0
## Seconds with nobody called before a random rival drives in.
const _AUTO_CALL_SEC := 5.0
const _RIVAL_WHEEL_RADIUS := 0.25
const _RIVAL_STILL := 0
const _RIVAL_ARRIVE := 1
const _RIVAL_WAIT := 2
const _RIVAL_LEAVE := 3

const _PARKED: Array[Dictionary] = [
	{"file": "res://assets/cars/sr1-corvette-1956.car", "paint": Color(0.72, 0.08, 0.08), "x": -7.2, "yaw": PI},
	{"file": "res://assets/cars/fairlane-1957.car", "paint": Color(0.93, 0.9, 0.82), "x": -2.4, "yaw": PI},
	{"file": "res://assets/cars/ford-coupe-1932.car", "paint": Color(0.08, 0.22, 0.55), "x": 2.4, "yaw": PI},
	{"file": "res://assets/cars/corvette-1962-1.car", "paint": Color(0.82, 0.68, 0.12), "x": 7.2, "yaw": PI},
]

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: CanvasLayer = $UI

var _nav = _MenuNav.new()
var _cash: Label
var _hover_prompt: Label
var _back: Button
var _opp_root: Control
var _opp_box: VBoxContainer
var _opp_list: VBoxContainer
var _opp_panel: Control
var _opp_back: Button
var _call_btn: Button
var _opp_buttons: Array[Button] = []
var _race_root: Control
var _race_hint: Label
var _drag_btn: Button
var _road_btn: Button
var _race_back: Button
var _stake_root: Control
var _stake_hint: Label
var _stake_kicks: Button
var _stake_low: Button
var _stake_high: Button
var _stake_back: Button
var _road_stake_root: Control
var _road_stake_hint: Label
var _road_stake_low: Button
var _road_stake_high: Button
var _road_stake_pink: Button
var _road_stake_back: Button
var _speech: Control
var _driver_seat: Node3D
var _fuel_root: Control
var _fuel_message: Label
var _fuel_back: Button
var _neon: Label3D
var _rival: StaticBody3D
var _rival_phase: int = _RIVAL_STILL
var _rival_engaged: bool = false
var _rival_from_x: float = 0.0
var _rival_to_x: float = 0.0
var _rival_exit_x: float = 0.0
var _rival_phase_time: float = 0.0
var _rival_phase_dur: float = 1.0
var _rival_wheels: Array[Node3D] = []
var _head_scenes: Dictionary = {}
var _chosen_index: int = 0
var _auto_call_time: float = 0.0
var _time: float = 0.0
var _materials: Dictionary = {}
var _box_meshes: Dictionary = {}
var _sphere_meshes: Dictionary = {}


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_DRIVE_IN
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera.fov = 54.0
	_camera.position = Vector3(0.0, 3.15, 17.6)
	_camera.look_at(Vector3(0.0, 2.35, 0.4), Vector3.UP)
	var world := Node3D.new()
	world.name = "DriveIn"
	add_child(world)
	var lot := Node3D.new()
	lot.name = "Lot"
	lot.position.z = -_SET_BACK
	world.add_child(lot)
	_build_environment()
	_build_lights(lot)
	_build_lot(lot)
	_build_building(lot)
	_build_cars(lot)
	_build_man(lot)
	_build_hud()
	_build_opponent_popup()
	_build_race_popup()
	_build_stake_popup()
	_build_road_stake_popup()
	_build_speech_bubble()
	_build_fuel_monitor()
	_sync_nav()


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _plant_wheels(car: Node3D) -> void:
	var lowest := INF
	var wheels: Array[Node3D] = []
	for wname in ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]:
		var wheel := car.get_node_or_null(wname) as Node3D
		if wheel == null or not wheel.visible:
			continue
		var box := _node_aabb(wheel)
		if box.size.y <= 0.001:
			continue
		lowest = minf(lowest, box.position.y)
		wheels.append(wheel)
	if wheels.is_empty() or lowest <= 0.01:
		return
	for wheel in wheels:
		wheel.position.y -= lowest


func _node_aabb(node: Node) -> AABB:
	var box := AABB()
	var started := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		box = _aabb_corners(mi.global_transform, mi.mesh.get_aabb())
		started = true
	for child in node.get_children():
		var child_box := _node_aabb(child)
		if child_box.size == Vector3.ZERO:
			continue
		if not started:
			box = child_box
			started = true
		else:
			box = box.merge(child_box)
	return box


func _aabb_corners(xf: Transform3D, local: AABB) -> AABB:
	var out := AABB(xf * local.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		out = out.expand(xf * local.get_endpoint(i))
	return out


func _process(delta: float) -> void:
	_time += delta
	if _neon != null:
		var pulse := 0.86 + sin(_time * 5.5) * 0.14
		_neon.modulate = Color(2.5 * pulse, 1.55 * pulse, 1.65 * pulse)
	_advance_rival(delta)
	_advance_auto_call(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
		return
	if _nav.handle_event(self, event):
		get_viewport().set_input_as_handled()


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.008, 0.01, 0.035)
	sky_mat.sky_horizon_color = Color(0.18, 0.05, 0.07)
	sky_mat.sky_curve = 0.08
	sky_mat.ground_bottom_color = Color(0.015, 0.015, 0.02)
	sky_mat.ground_horizon_color = Color(0.07, 0.035, 0.04)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.18, 0.28)
	env.ambient_light_energy = 0.28
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.72
	env.glow_strength = 0.95
	env.glow_bloom = 0.14
	env.glow_hdr_threshold = 0.72
	env.glow_hdr_scale = 1.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_lights(parent: Node3D) -> void:
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-52.0, -24.0, 0.0)
	moon.light_color = Color(0.62, 0.7, 0.92)
	moon.light_energy = 0.32
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 45.0
	parent.add_child(moon)
	_omni(parent, Vector3(-4.2, 4.35, 1.15), Color(1.0, 0.28, 0.38), 1.5, 9.0)
	_omni(parent, Vector3(4.4, 4.35, 1.15), Color(0.35, 0.8, 1.0), 1.05, 8.0)
	_omni(parent, Vector3(0.0, 3.15, 1.5), Color(1.0, 0.72, 0.4), 1.1, 7.5)
	_omni(parent, Vector3(-5.5, 2.35, -0.45), Color(1.0, 0.72, 0.42), 1.7, 6.5)
	_omni(parent, Vector3(1.2, 2.35, -0.45), Color(1.0, 0.68, 0.38), 1.5, 6.0)
	_omni(parent, Vector3(7.3, 2.15, -0.35), Color(1.0, 0.78, 0.45), 1.4, 4.5)
	_lot_lamp(parent, Vector3(-11.2, 0.0, 11.4))
	_lot_lamp(parent, Vector3(11.2, 0.0, 11.4))
	var spot := SpotLight3D.new()
	spot.position = Vector3(-0.4, 3.35, 2.2)
	spot.light_color = Color(1.0, 0.88, 0.7)
	spot.light_energy = 3.4
	spot.spot_range = 16.0
	spot.spot_angle = 34.0
	parent.add_child(spot)
	spot.look_at(parent.to_global(Vector3(-0.05, 1.0, 9.45)), Vector3.UP)


func _lot_lamp(parent: Node3D, pos: Vector3) -> void:
	var pole := Color(0.22, 0.22, 0.24)
	_add_box(parent, Vector3(0.12, 4.4, 0.12), pos + Vector3(0.0, 2.2, 0.0), pole, 0.45, 0.6)
	_add_box(parent, Vector3(0.7, 0.08, 0.28), pos + Vector3(0.0, 4.4, 0.1), pole, 0.4, 0.65)
	var bulb := Color(1.0, 0.86, 0.55)
	_add_sphere(parent, 0.1, pos + Vector3(0.0, 4.28, 0.1), bulb, 0.3, 0.0, bulb, 4.0, false)
	_omni(parent, pos + Vector3(0.0, 4.2, 0.2), bulb, 1.6, 12.0)


func _omni(parent: Node3D, pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	parent.add_child(light)


func _build_lot(parent: Node3D) -> void:
	var asphalt := Color(0.07, 0.07, 0.075)
	_add_box(parent, Vector3(48.0, 0.2, 40.0), Vector3(0.0, -0.1, 6.0), asphalt, 0.92)
	_add_box(parent, Vector3(22.6, 0.08, 1.7), Vector3(0.0, 0.04, 0.95), Color(0.4, 0.38, 0.36), 0.8)
	var line := Color(0.72, 0.72, 0.68)
	var edges: Array[float] = [-9.6, -4.8, 0.0, 4.8, 9.6]
	for x in edges:
		_add_box(parent, Vector3(0.08, 0.012, 5.5), Vector3(x, 0.012, 6.45), line, 0.6, 0.0, Color.BLACK, 0.0, Vector3.ZERO, false)
	_add_box(parent, Vector3(21.8, 0.012, 0.08), Vector3(0.0, 0.012, 3.7), line, 0.6, 0.0, Color.BLACK, 0.0, Vector3.ZERO, false)


func _build_building(parent: Node3D) -> void:
	var shell := Node3D.new()
	shell.name = "Diner"
	parent.add_child(shell)
	_add_box(shell, Vector3(0.3, _WALL_H, 8.15), Vector3(-_HALF_W, _WALL_H * 0.5, -4.05), _WALL)
	_add_box(shell, Vector3(0.3, _WALL_H, 8.15), Vector3(_HALF_W, _WALL_H * 0.5, -4.05), _WALL)
	_add_box(shell, Vector3(22.3, _WALL_H, 0.3), Vector3(0.0, _WALL_H * 0.5, -8.15), Color(0.48, 0.24, 0.2))
	_add_floor(shell)
	_add_box(shell, Vector3(21.7, 0.12, 7.9), Vector3(0.0, 3.5, -4.05), Color(0.3, 0.16, 0.14))
	_add_box(shell, Vector3(23.2, 0.16, 8.35), Vector3(0.0, 3.74, -4.0), Color(0.09, 0.08, 0.09), 0.7)
	_build_facade(shell)
	_build_awning(shell)
	_build_sign(shell)
	_build_interior_people(shell)
	var lamp := Color(1.0, 0.82, 0.45)
	_add_sphere(shell, 0.11, Vector3(-5.5, 3.25, -2.4), lamp, 0.3, 0.0, lamp, 3.0, false)
	_add_sphere(shell, 0.11, Vector3(1.0, 3.25, -2.4), lamp, 0.3, 0.0, lamp, 3.0, false)
	_add_box(shell, Vector3(16.5, 0.9, 0.55), Vector3(-1.6, 0.95, -1.55), Color(0.42, 0.2, 0.12), 0.62)


func _add_floor(parent: Node3D) -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.12, 0.12, 0.13))
	img.set_pixel(1, 1, Color(0.12, 0.12, 0.13))
	img.set_pixel(1, 0, Color(0.78, 0.76, 0.72))
	img.set_pixel(0, 1, Color(0.78, 0.76, 0.72))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(14.0, 10.0, 14.0)
	mat.roughness = 0.62
	var mesh := BoxMesh.new()
	mesh.size = Vector3(21.6, 0.08, 7.8)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.04, -4.05)
	parent.add_child(mi)


func _build_facade(parent: Node3D) -> void:
	var cursor := -_HALF_W
	for span in _WINDOWS:
		var x0: float = span["x0"]
		var x1: float = span["x1"]
		_pier(parent, cursor, x0)
		var kind := str(span["kind"])
		var sill := 1.18 if kind == "order" else 0.9
		var head := 2.4 if kind == "order" else 2.64
		_opening(parent, x0, x1, sill, head, kind)
		cursor = x1
	_pier(parent, cursor, _HALF_W)
	_add_box(parent, Vector3(22.3, 0.16, 0.08), Vector3(0.0, 3.22, 0.22), _RED, 0.45, 0.1, Color.BLACK, 0.0, Vector3.ZERO, false)
	_add_box(parent, Vector3(22.3, 0.2, 0.08), Vector3(0.0, 0.1, 0.22), Color(0.38, 0.06, 0.07), 0.5, 0.05, Color.BLACK, 0.0, Vector3.ZERO, false)


func _pier(parent: Node3D, x0: float, x1: float) -> void:
	var width := x1 - x0
	if width < 0.04:
		return
	_add_box(parent, Vector3(width, _WALL_H, _WALL_T), Vector3((x0 + x1) * 0.5, _WALL_H * 0.5, 0.0), _WALL)


func _opening(parent: Node3D, x0: float, x1: float, sill: float, head: float, kind: String) -> void:
	var width := x1 - x0
	var mid_x := (x0 + x1) * 0.5
	var hole_h := head - sill
	_add_box(parent, Vector3(width, sill, _WALL_T), Vector3(mid_x, sill * 0.5, 0.0), _WALL)
	_add_box(parent, Vector3(width, _WALL_H - head, _WALL_T), Vector3(mid_x, (head + _WALL_H) * 0.5, 0.0), _WALL)
	var frame := Color(0.74, 0.75, 0.78)
	_add_box(parent, Vector3(0.06, hole_h, 0.08), Vector3(x0, (sill + head) * 0.5, 0.05), frame, 0.32, 0.8, Color.BLACK, 0.0, Vector3.ZERO, false)
	_add_box(parent, Vector3(0.06, hole_h, 0.08), Vector3(x1, (sill + head) * 0.5, 0.05), frame, 0.32, 0.8, Color.BLACK, 0.0, Vector3.ZERO, false)
	_add_box(parent, Vector3(width, 0.06, 0.08), Vector3(mid_x, head, 0.05), frame, 0.32, 0.8, Color.BLACK, 0.0, Vector3.ZERO, false)
	_add_box(parent, Vector3(width, 0.06, 0.08), Vector3(mid_x, sill, 0.05), frame, 0.32, 0.8, Color.BLACK, 0.0, Vector3.ZERO, false)
	_add_box(
		parent,
		Vector3(width - 0.1, hole_h - 0.08, 0.03),
		Vector3(mid_x, (sill + head) * 0.5, 0.02),
		Color(0.95, 0.9, 0.78, 0.08),
		0.04,
		0.05,
		Color(1.0, 0.72, 0.4),
		0.22,
		Vector3.ZERO,
		false,
		0.08
	)
	if kind != "order":
		return
	_add_box(parent, Vector3(width - 0.2, 0.07, 0.62), Vector3(mid_x, sill + 0.02, 0.38), Color(0.5, 0.28, 0.14), 0.5)
	var sign_y := head + 0.46
	_add_box(parent, Vector3(2.7, 0.7, 0.08), Vector3(mid_x, sign_y, 0.32), Color(0.07, 0.04, 0.03), 0.5, 0.05, Color.BLACK, 0.0, Vector3.ZERO, false)
	var amber := Color(1.0, 0.62, 0.12)
	_add_box(parent, Vector3(2.55, 0.045, 0.03), Vector3(mid_x, sign_y + 0.3, 0.38), amber, 0.3, 0.0, amber, 3.2, Vector3.ZERO, false)
	_add_box(parent, Vector3(2.55, 0.045, 0.03), Vector3(mid_x, sign_y - 0.3, 0.38), amber, 0.3, 0.0, amber, 3.2, Vector3.ZERO, false)
	_add_label(parent, "ORDER", Vector3(mid_x, sign_y, 0.42), 86, 0.0064, Color(2.9, 1.9, 0.4), Color(1.1, 0.4, 0.04), 8)


func _build_awning(parent: Node3D) -> void:
	var x_start := -10.2
	var x_end := 5.3
	var stripes := 18
	var stripe_w := (x_end - x_start) / float(stripes)
	for i in stripes:
		var color := _RED if i % 2 == 0 else Color(0.92, 0.9, 0.86)
		var x := x_start + stripe_w * (float(i) + 0.5)
		_add_box(parent, Vector3(stripe_w + 0.015, 0.045, 1.25), Vector3(x, 2.92, 0.72), color, 0.55, 0.0, Color.BLACK, 0.0, Vector3(0.28, 0.0, 0.0), false)
	_bulbs(parent, Vector3(x_start + 0.1, 2.68, 1.32), Vector3(x_end - 0.1, 2.68, 1.32), 0.48)
	_bulbs(parent, Vector3(-10.9, 0.45, 0.35), Vector3(-10.9, 3.35, 0.35), 0.42)
	_bulbs(parent, Vector3(10.9, 0.45, 0.35), Vector3(10.9, 3.35, 0.35), 0.42)


func _build_sign(parent: Node3D) -> void:
	var metal := Color(0.2, 0.2, 0.22)
	_add_box(parent, Vector3(0.1, 1.55, 0.1), Vector3(-6.4, 4.45, 0.12), metal, 0.4, 0.7)
	_add_box(parent, Vector3(0.1, 1.55, 0.1), Vector3(6.4, 4.45, 0.12), metal, 0.4, 0.7)
	_add_box(parent, Vector3(15.4, 1.72, 0.16), Vector3(0.0, 4.32, 0.32), Color(0.04, 0.02, 0.03), 0.55)
	_add_box(parent, Vector3(13.6, 1.2, 0.02), Vector3(0.0, 4.32, 0.41), Color(0.45, 0.03, 0.07), 0.4, 0.0, Color(1.0, 0.12, 0.22), 1.6, Vector3.ZERO, false)
	var tube := Color(1.0, 0.15, 0.28)
	_add_box(parent, Vector3(15.15, 0.06, 0.04), Vector3(0.0, 5.12, 0.43), tube, 0.3, 0.0, tube, 5.0, Vector3.ZERO, false)
	_add_box(parent, Vector3(15.15, 0.06, 0.04), Vector3(0.0, 3.52, 0.43), tube, 0.3, 0.0, tube, 5.0, Vector3.ZERO, false)
	_add_box(parent, Vector3(0.06, 1.66, 0.04), Vector3(-7.55, 4.32, 0.43), tube, 0.3, 0.0, tube, 5.0, Vector3.ZERO, false)
	_add_box(parent, Vector3(0.06, 1.66, 0.04), Vector3(7.55, 4.32, 0.43), tube, 0.3, 0.0, tube, 5.0, Vector3.ZERO, false)
	_neon = _add_label(parent, "CHRIS'S DRIVE-IN", Vector3(0.0, 4.32, 0.48), 110, 0.0115, Color(2.5, 1.55, 1.65), Color(1.8, 0.12, 0.22), 18)
	_bulbs(parent, Vector3(-7.35, 5.22, 0.5), Vector3(7.35, 5.22, 0.5), 0.46)
	_bulbs(parent, Vector3(-7.35, 3.42, 0.5), Vector3(7.35, 3.42, 0.5), 0.46)


func _build_interior_people(parent: Node3D) -> void:
	var shirts: Array[Color] = [
		Color(0.7, 0.12, 0.12),
		Color(0.82, 0.62, 0.18),
		Color(0.12, 0.45, 0.48),
		Color(0.55, 0.18, 0.38),
		Color(0.2, 0.38, 0.18),
		Color(0.45, 0.28, 0.16),
		Color(0.15, 0.2, 0.48),
	]
	var n := 0
	for span in _WINDOWS:
		if str(span["kind"]) == "order":
			continue
		var x0: float = span["x0"]
		var x1: float = span["x1"]
		var mid_x := (x0 + x1) * 0.5
		_add_person(parent, Vector3(mid_x - 0.38, -0.15, -0.7), 0.15, shirts[n % shirts.size()], Color(0.18, 0.16, 0.2))
		n += 1
		if x1 - x0 > 2.4:
			_add_person(parent, Vector3(mid_x + 0.48, -0.15, -0.78), -0.2, shirts[n % shirts.size()], Color(0.28, 0.22, 0.16))
			n += 1
	_add_person(parent, Vector3(6.35, 0.0, -0.72), 0.1, Color(0.92, 0.92, 0.9), Color(0.1, 0.1, 0.12))
	_add_box(parent, Vector3(0.2, 0.05, 0.2), Vector3(6.35, 1.86, -0.72), Color(0.95, 0.95, 0.95))
	_add_person(parent, Vector3(8.05, 0.0, -0.68), -0.35, Color(0.9, 0.9, 0.88), Color(0.12, 0.1, 0.1))
	_add_box(parent, Vector3(0.22, 0.32, 0.04), Vector3(8.05, 1.18, -0.5), _RED, 0.5, 0.0, Color.BLACK, 0.0, Vector3.ZERO, false)
	_add_box(parent, Vector3(0.32, 0.05, 0.22), Vector3(7.15, 1.32, -0.4), Color(0.42, 0.24, 0.12))


func _build_cars(parent: Node3D) -> void:
	for spec in _PARKED:
		var car := _CAR_SCENE.instantiate() as Node3D
		var path := str(spec["file"])
		var paint: Color = spec["paint"]
		if not bool(car.call(&"prepare_preview", path, paint)):
			push_warning("Drive-in car failed to load: %s" % path)
			car.free()
			continue
		car.name = path.get_file().get_basename()
		car.position = Vector3(float(spec["x"]), 0.0, 6.4)
		car.rotation.y = float(spec["yaw"])
		parent.add_child(car)
		var bounds := _node_aabb(car)
		if bounds.size.y > 0.05 and bounds.position.y > 0.02:
			car.position.y -= bounds.position.y
		_plant_wheels(car)


func _build_man(parent: Node3D) -> void:
	var man := StaticBody3D.new()
	man.name = "Challenger"
	man.position = Vector3(-0.05, 0.0, 9.45)
	man.rotation.y = -0.25
	man.collision_mask = 0
	man.input_ray_pickable = true
	parent.add_child(man)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.85, 1.95, 0.6)
	shape.shape = box
	shape.position = Vector3(0.0, 0.98, 0.0)
	man.add_child(shape)
	_add_person(man, Vector3.ZERO, 0.0, Color(0.96, 0.96, 0.98), Color(0.58, 0.76, 0.9), 0.45)
	man.input_event.connect(_on_man_input)
	man.mouse_entered.connect(_on_man_hover.bind(true))
	man.mouse_exited.connect(_on_man_hover.bind(false))


func _add_person(parent: Node3D, pos: Vector3, yaw: float, shirt: Color, pants: Color, shirt_glow: float = 0.0) -> void:
	var body := Node3D.new()
	body.position = pos
	body.rotation.y = yaw
	parent.add_child(body)
	_add_box(body, Vector3(0.16, 0.78, 0.2), Vector3(-0.11, 0.43, 0.0), pants)
	_add_box(body, Vector3(0.16, 0.78, 0.2), Vector3(0.11, 0.43, 0.0), pants)
	_add_box(body, Vector3(0.14, 0.08, 0.26), Vector3(-0.11, 0.04, 0.04), _SHOE)
	_add_box(body, Vector3(0.14, 0.08, 0.26), Vector3(0.11, 0.04, 0.04), _SHOE)
	_add_box(body, Vector3(0.48, 0.5, 0.24), Vector3(0.0, 1.22, 0.0), shirt, 0.55, 0.0, shirt, shirt_glow)
	_add_box(body, Vector3(0.1, 0.46, 0.1), Vector3(-0.3, 1.16, 0.0), _SKIN)
	_add_box(body, Vector3(0.1, 0.46, 0.1), Vector3(0.3, 1.16, 0.0), _SKIN)
	_add_sphere(body, 0.125, Vector3(0.0, 1.64, 0.0), _SKIN)
	_add_sphere(body, 0.11, Vector3(0.0, 1.73, -0.02), _HAIR, 0.8)
	_add_sphere(body, 0.028, Vector3(0.0, 1.62, 0.11), _SKIN)


func _bulbs(parent: Node3D, from: Vector3, to: Vector3, spacing: float) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	_cable(parent, from, to)
	var count := maxi(int(round(length / spacing)), 2)
	for i in count:
		var color: Color = _BULB_COLORS[i % _BULB_COLORS.size()]
		var pos := from.lerp(to, float(i) / float(count - 1))
		_add_sphere(parent, 0.055, pos, color, 0.22, 0.0, color, 6.5, false)


func _cable(parent: Node3D, from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var length := delta.length()
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, length)
	mi.mesh = mesh
	mi.material_override = _material(Color(0.07, 0.07, 0.08), 0.55, 0.35, Color.BLACK, 0.0, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = (from + to) * 0.5
	var up := Vector3.UP
	if absf(delta.normalized().dot(Vector3.UP)) > 0.92:
		up = Vector3.RIGHT
	mi.look_at(parent.to_global(to), up)


func _add_box(
	parent: Node3D,
	size: Vector3,
	pos: Vector3,
	albedo: Color,
	roughness: float = 0.72,
	metallic: float = 0.0,
	emission: Color = Color.BLACK,
	energy: float = 0.0,
	rotation: Vector3 = Vector3.ZERO,
	shadows: bool = true,
	alpha: float = 1.0
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = _material(albedo, roughness, metallic, emission, energy, alpha)
	mi.position = pos
	mi.rotation = rotation
	if not shadows or alpha < 0.99:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_sphere(
	parent: Node3D,
	radius: float,
	pos: Vector3,
	albedo: Color,
	roughness: float = 0.7,
	metallic: float = 0.0,
	emission: Color = Color.BLACK,
	energy: float = 0.0,
	shadows: bool = true
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(radius)
	mi.material_override = _material(albedo, roughness, metallic, emission, energy, 1.0)
	mi.position = pos
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_label(parent: Node3D, text: String, pos: Vector3, font_size: int, pixel: float, color: Color, outline: Color, outline_px: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_modulate = outline
	label.outline_size = outline_px
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	parent.add_child(label)
	return label


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "%s" % size
	if _box_meshes.has(key):
		return _box_meshes[key] as BoxMesh
	var mesh := BoxMesh.new()
	mesh.size = size
	_box_meshes[key] = mesh
	return mesh


func _sphere_mesh(radius: float) -> SphereMesh:
	var key := "%.3f" % radius
	if _sphere_meshes.has(key):
		return _sphere_meshes[key] as SphereMesh
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	_sphere_meshes[key] = mesh
	return mesh


func _material(albedo: Color, roughness: float, metallic: float, emission: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f|%.2f" % [albedo, roughness, metallic, emission, energy, alpha]
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(albedo.r, albedo.g, albedo.b, alpha)
	mat.roughness = roughness
	mat.metallic = metallic
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
	if alpha < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = mat
	return mat


func _build_hud() -> void:
	var bar := Control.new()
	bar.name = "HudBottom"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -48.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bar)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.09, 0.07, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	var accent := ColorRect.new()
	accent.color = Color(0.55, 0.12, 0.1, 1.0)
	accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	accent.offset_bottom = 3.0
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(accent)
	_cash = Label.new()
	_cash.name = "CashLabel"
	_cash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cash.offset_left = 20.0
	_cash.offset_right = -230.0
	_cash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_cash.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78))
	_cash.add_theme_font_size_override(&"font_size", 22)
	_cash.text = "Bankroll: $%d" % GameState.money
	_cash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_cash)
	_hover_prompt = Label.new()
	_hover_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hover_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hover_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_prompt.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78))
	_hover_prompt.add_theme_font_size_override(&"font_size", 22)
	_hover_prompt.text = "Look for opponent"
	_hover_prompt.visible = false
	_hover_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_hover_prompt)
	_back = Button.new()
	_back.text = "Back to garage"
	_back.custom_minimum_size = Vector2(180, 36)
	_back.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_back.offset_left = -200.0
	_back.offset_right = -16.0
	_back.offset_top = -18.0
	_back.offset_bottom = 18.0
	_back.pressed.connect(_on_back_pressed)
	bar.add_child(_back)


func _build_opponent_popup() -> void:
	var built := _make_overlay("Who do you want to race?")
	_opp_root = built["root"]
	_opp_box = built["box"]
	_opp_panel = built["panel"]
	var hint := _hint_label("He's waiting by the cars.")
	_opp_box.add_child(hint)
	_opp_list = VBoxContainer.new()
	_opp_list.add_theme_constant_override(&"separation", 10)
	_opp_box.add_child(_opp_list)
	_call_btn = _menu_button("Call anybody")
	_call_btn.pressed.connect(_on_call_anybody)
	_opp_box.add_child(_call_btn)
	_opp_back = _menu_button("Back")
	_opp_back.pressed.connect(_hide_popups)
	_opp_box.add_child(_opp_back)
	_rebuild_opponent_list()


func _build_race_popup() -> void:
	var built := _make_overlay("What kind of race?")
	_race_root = built["root"]
	var box: VBoxContainer = built["box"]
	_race_hint = _hint_label("")
	box.add_child(_race_hint)
	_drag_btn = _menu_button("Drag race")
	_drag_btn.pressed.connect(_on_race_type_chosen.bind(GameState.RACE_DRAG))
	box.add_child(_drag_btn)
	_road_btn = _menu_button("Road race")
	_road_btn.pressed.connect(_on_race_type_chosen.bind(GameState.RACE_ROAD))
	box.add_child(_road_btn)
	_race_back = _menu_button("Back")
	_race_back.pressed.connect(_show_opponents)
	box.add_child(_race_back)
	_fit_panel(built["panel"])


func _build_stake_popup() -> void:
	var built := _make_overlay("What's the bet?")
	_stake_root = built["root"]
	var box: VBoxContainer = built["box"]
	_stake_hint = _hint_label("")
	box.add_child(_stake_hint)
	_stake_kicks = _menu_button("Just for kicks")
	_stake_kicks.pressed.connect(_on_stake_chosen.bind(0))
	box.add_child(_stake_kicks)
	_stake_low = _menu_button("$%d" % GameState.DRAG_STAKE_LOW)
	_stake_low.pressed.connect(_on_stake_chosen.bind(GameState.DRAG_STAKE_LOW))
	box.add_child(_stake_low)
	_stake_high = _menu_button("$%d" % GameState.DRAG_STAKE_HIGH)
	_stake_high.pressed.connect(_on_stake_chosen.bind(GameState.DRAG_STAKE_HIGH))
	box.add_child(_stake_high)
	_stake_back = _menu_button("Back")
	_stake_back.pressed.connect(_on_stake_back)
	box.add_child(_stake_back)
	_fit_panel(built["panel"])


func _build_road_stake_popup() -> void:
	var built := _make_overlay("What's the bet?")
	_road_stake_root = built["root"]
	var box: VBoxContainer = built["box"]
	_road_stake_hint = _hint_label("")
	_road_stake_hint.custom_minimum_size = Vector2(400, 96)
	box.add_child(_road_stake_hint)
	_road_stake_low = _menu_button("$%d" % GameState.ROAD_STAKE_LOW)
	_road_stake_low.pressed.connect(_on_road_stake_chosen.bind(GameState.ROAD_STAKE_LOW))
	box.add_child(_road_stake_low)
	_road_stake_high = _menu_button("$%d" % GameState.ROAD_STAKE_HIGH)
	_road_stake_high.pressed.connect(_on_road_stake_chosen.bind(GameState.ROAD_STAKE_HIGH))
	box.add_child(_road_stake_high)
	_road_stake_pink = _menu_button("Pink slips")
	_road_stake_pink.pressed.connect(_on_pink_slips_chosen)
	box.add_child(_road_stake_pink)
	_road_stake_back = _menu_button("Back")
	_road_stake_back.pressed.connect(_on_road_stake_back)
	box.add_child(_road_stake_back)
	_fit_panel(built["panel"])


func _build_speech_bubble() -> void:
	var bubble := _SpeechBubble.instantiate()
	bubble.visible = false
	_ui.add_child(bubble)
	bubble.call("set_line", "You're garage is full, sell some cars first!", Vector2(320, 56), 26)
	bubble.call("grab_screen")
	bubble.call("hold_when_behind", true)
	bubble.connect("pressed", _dismiss_full_garage_line)
	_speech = bubble


func _build_fuel_monitor() -> void:
	var built := _make_overlay("Low fuel")
	_fuel_root = built["root"]
	var box: VBoxContainer = built["box"]
	_fuel_message = _hint_label("")
	_fuel_message.custom_minimum_size = Vector2(400, 64)
	box.add_child(_fuel_message)
	_fuel_back = _menu_button("Back")
	_fuel_back.pressed.connect(_hide_fuel)
	box.add_child(_fuel_back)
	_fit_panel(built["panel"])


func _make_overlay(title: String) -> Dictionary:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_bottom = -48.0
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 18)
	margin.add_theme_constant_override(&"margin_right", 18)
	margin.add_theme_constant_override(&"margin_top", 14)
	margin.add_theme_constant_override(&"margin_bottom", 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override(&"font_size", 22)
	heading.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78))
	box.add_child(heading)
	return {"root": root, "box": box, "panel": panel}


func _hint_label(text: String) -> Label:
	var hint := Label.new()
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(400, 36)
	hint.add_theme_color_override(&"font_color", Color(0.9, 0.84, 0.72))
	return hint


func _opponent_button(opp: Dictionary) -> Button:
	return _menu_button("%s — %s" % [str(opp.get("name", "Rival")), str(opp.get("car_name", "Car"))])


func _opponent_color(opp: Dictionary) -> Color:
	var paint: Variant = opp.get("color", null)
	if paint is Color:
		return paint
	return Color(0.8, 0.1, 0.1)


func _menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(400, 42)
	return btn


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.96)
	style.border_color = Color(0.55, 0.12, 0.1)
	style.set_border_width_all(2)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _fit_panel(panel: Control) -> void:
	var size := panel.get_combined_minimum_size()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -size.x * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_top = -size.y * 0.5 - 16.0
	panel.offset_bottom = size.y * 0.5 - 16.0


func _on_man_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if _popup_open() or _rival != null:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	_show_opponents()
	get_viewport().set_input_as_handled()


func _on_man_hover(hovering: bool) -> void:
	if _popup_open() or _rival != null:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if _rival == null:
			_hover_prompt.visible = false
		return
	_hover_prompt.visible = hovering
	var shape := Input.CURSOR_POINTING_HAND if hovering else Input.CURSOR_ARROW
	Input.set_default_cursor_shape(shape)


func _show_opponents() -> void:
	_clear_rival()
	_fuel_root.visible = false
	_race_root.visible = false
	_stake_root.visible = false
	_road_stake_root.visible = false
	if _speech != null:
		_speech.visible = false
	_rebuild_opponent_list()
	_opp_root.visible = true
	_hover_prompt.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_sync_nav()


func _rebuild_opponent_list() -> void:
	for child in _opp_list.get_children():
		_opp_list.remove_child(child)
		child.free()
	_opp_buttons.clear()
	for i in range(GameState.opponents.size()):
		var opp: Dictionary = GameState.opponents[i]
		var btn := _opponent_button(opp)
		btn.pressed.connect(_on_opponent_chosen.bind(i))
		_opp_list.add_child(btn)
		_opp_buttons.append(btn)
	_fit_panel(_opp_panel)


func _on_call_anybody() -> void:
	var index := GameState.call_random_opponent()
	if index < 0:
		return
	_on_opponent_chosen(index)


func _hide_popups() -> void:
	_opp_root.visible = false
	_race_root.visible = false
	_stake_root.visible = false
	_road_stake_root.visible = false
	_speech.visible = false
	_fuel_root.visible = false
	_sync_nav()


func _on_opponent_chosen(index: int) -> void:
	_chosen_index = index
	_auto_call_time = 0.0
	_refresh_race_popup()
	_opp_root.visible = false
	_present_rival()
	_sync_nav()


func _advance_auto_call(delta: float) -> void:
	if _rival != null or _popup_open():
		_auto_call_time = 0.0
		return
	_auto_call_time += delta
	if _auto_call_time < _AUTO_CALL_SEC:
		return
	_auto_call_time = 0.0
	var index := GameState.call_random_opponent()
	if index < 0:
		return
	_on_opponent_chosen(index)


func _present_rival() -> void:
	_clear_rival()
	if _chosen_index < 0 or _chosen_index >= GameState.opponents.size():
		return
	var opp: Dictionary = GameState.opponents[_chosen_index]
	var path := str(opp.get("car_file", ""))
	var car := _CAR_SCENE.instantiate() as Node3D
	if not bool(car.call(&"prepare_preview", path, _opponent_color(opp))):
		push_warning("Rival car failed to load: %s" % path)
		car.free()
		_show_opponents()
		return
	var root := StaticBody3D.new()
	root.name = "RivalCar"
	root.collision_mask = 0
	root.input_ray_pickable = true
	root.rotation.y = PI * 0.5
	root.position = Vector3(0.0, 0.0, 15.4)
	get_node("DriveIn").add_child(root)
	root.add_child(car)
	var bounds := _node_aabb(car)
	if bounds.size.y > 0.05 and bounds.position.y > 0.02:
		car.position.y -= bounds.position.y
	_plant_wheels(car)
	bounds = _node_aabb(root)
	root.position.x -= bounds.position.x + bounds.size.x * 0.5
	for _step in 16:
		if _side_fits(_node_aabb(root)):
			break
		root.position.z -= 0.35
	var rival_name := str(opp.get("name", ""))
	_seat_driver(car, GameState.opponent_skin(rival_name), GameState.opponent_head(rival_name))
	_add_rival_hitbox(root)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-3.2, 1.4, 0.0)
	lamp.light_color = Color(1.0, 0.9, 0.75)
	lamp.light_energy = 1.15
	lamp.omni_range = 9.0
	lamp.shadow_enabled = false
	root.add_child(lamp)
	root.input_event.connect(_on_rival_input)
	root.mouse_entered.connect(_on_rival_hover.bind(true))
	root.mouse_exited.connect(_on_rival_hover.bind(false))
	_rival = root
	_collect_rival_wheels(car)
	_start_rival_entrance()
	_hover_prompt.text = "%s — %s" % [str(opp.get("name", "Rival")), str(opp.get("car_name", "Car"))]
	_hover_prompt.visible = true
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _collect_rival_wheels(car: Node) -> void:
	_rival_wheels.clear()
	for wname in ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]:
		var wheel := car.get_node_or_null(wname) as Node3D
		if wheel != null and wheel.visible:
			_rival_wheels.append(wheel)


func _start_rival_entrance() -> void:
	var bounds := _node_aabb(_rival)
	var park_x := _rival.position.x
	_rival_to_x = park_x
	_rival_exit_x = _root_x_past_screen(bounds, 1.0)
	_rival_from_x = _root_x_past_screen(bounds, -1.0)
	_rival.position.x = _rival_from_x
	_rival_engaged = false
	_rival_phase = _RIVAL_ARRIVE
	_rival_phase_time = 0.0
	_rival_phase_dur = maxf(absf(_rival_to_x - _rival_from_x) / _RIVAL_CRUISE_MPS, 0.75)


func _advance_rival(delta: float) -> void:
	if _rival == null or not is_instance_valid(_rival) or _rival_phase == _RIVAL_STILL:
		return
	_rival_phase_time += delta
	var t := clampf(_rival_phase_time / maxf(_rival_phase_dur, 0.001), 0.0, 1.0)
	var prev_x := _rival.position.x
	if _rival_phase == _RIVAL_ARRIVE:
		var eased := 1.0 - pow(1.0 - t, 2.0)
		_rival.position.x = lerpf(_rival_from_x, _rival_to_x, eased)
		_spin_rival_wheels(_rival.position.x - prev_x)
		if t >= 1.0:
			_rival.position.x = _rival_to_x
			_begin_rival_wait()
		return
	if _rival_phase == _RIVAL_WAIT:
		if _rival_engaged or _popup_open():
			return
		if _rival_phase_time >= _rival_phase_dur:
			_begin_rival_leave()
		return
	if _rival_phase != _RIVAL_LEAVE:
		return
	var eased_out := t * t
	_rival.position.x = lerpf(_rival_from_x, _rival_to_x, eased_out)
	_spin_rival_wheels(_rival.position.x - prev_x)
	if t >= 1.0:
		_clear_rival()


func _begin_rival_wait() -> void:
	_rival_phase = _RIVAL_WAIT
	_rival_phase_time = 0.0
	_rival_phase_dur = _RIVAL_IDLE_SEC


func _begin_rival_leave() -> void:
	if _rival == null or not is_instance_valid(_rival):
		return
	_rival_phase = _RIVAL_LEAVE
	_rival_phase_time = 0.0
	_rival_from_x = _rival.position.x
	_rival_to_x = _rival_exit_x
	_rival_phase_dur = maxf(absf(_rival_to_x - _rival_from_x) / _RIVAL_CRUISE_MPS, 0.75)
	_rival.input_ray_pickable = false
	if _hover_prompt != null:
		_hover_prompt.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _spin_rival_wheels(distance: float) -> void:
	if absf(distance) < 0.0001:
		return
	var angle := -distance / _RIVAL_WHEEL_RADIUS
	for wheel in _rival_wheels:
		if is_instance_valid(wheel):
			wheel.rotate_object_local(Vector3.UP, angle)


## Root X that puts every corner past the left (sign -1) or right (sign +1) screen edge.
func _root_x_past_screen(box: AABB, sign: float) -> float:
	var vp := get_viewport().get_visible_rect().size
	var margin := maxf(48.0, vp.x * 0.04)
	var edge := -margin if sign < 0.0 else vp.x + margin
	var shift := 0.4
	for i in 8:
		var corner: Vector3 = box.get_endpoint(i)
		if _camera.is_position_behind(corner):
			shift = maxf(shift, 8.0)
			continue
		var screen := _camera.unproject_position(corner)
		var per_meter := _screen_dx_per_world_x(corner)
		if absf(per_meter) < 0.01:
			shift = maxf(shift, 8.0)
			continue
		var outward := (edge - screen.x) / per_meter * sign
		if outward > shift:
			shift = outward
	return _rival.position.x + sign * shift


func _screen_dx_per_world_x(world: Vector3) -> float:
	var ahead := world + Vector3(0.5, 0.0, 0.0)
	if _camera.is_position_behind(world) or _camera.is_position_behind(ahead):
		return 0.0
	var a := _camera.unproject_position(world)
	var b := _camera.unproject_position(ahead)
	return (b.x - a.x) / 0.5


func _clear_rival() -> void:
	if _rival != null and is_instance_valid(_rival):
		_rival.input_ray_pickable = false
		_rival.queue_free()
	_rival = null
	_driver_seat = null
	_rival_phase = _RIVAL_STILL
	_rival_engaged = false
	_rival_wheels.clear()
	if _speech != null:
		_speech.visible = false
	if _hover_prompt != null:
		_hover_prompt.text = "Look for opponent"
		_hover_prompt.visible = false


func _seat_driver(car: Node3D, skin: Color, head_path: String) -> void:
	var head_pos := Vector3(-0.35, 1.05, 0.2)
	if car.has_method(&"driver_seat_position"):
		var seated: Variant = car.call(&"driver_seat_position")
		if seated is Vector3:
			head_pos = seated
	var seat := Node3D.new()
	seat.name = "Driver"
	seat.position = head_pos
	car.add_child(seat)
	_driver_seat = seat
	var packed := _head_scene(head_path)
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	if model == null:
		push_warning("Opponent head failed to load: %s" % head_path)
		return
	model.name = "Head"
	# The file is Z-up, with the face toward -Y. Stand it up facing the car's nose.
	model.rotation_degrees.x = -90.0
	seat.add_child(model)
	_paint_driver_skin(model, skin)
	var bounds := _node_aabb(model)
	if bounds.size.y > 0.001:
		model.scale = Vector3.ONE * (_HEAD_HEIGHT / bounds.size.y)
		model.force_update_transform()
		bounds = _node_aabb(model)
	if bounds.size != Vector3.ZERO:
		model.position -= seat.to_local(bounds.get_center())


func _head_scene(path: String) -> PackedScene:
	if _head_scenes.has(path):
		var cached: Variant = _head_scenes[path]
		if cached is PackedScene:
			return cached
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Opponent head failed to load: %s" % path)
		return null
	_head_scenes[path] = packed
	return packed


func _paint_driver_skin(model: Node, skin_color: Color) -> void:
	var skin := _material(skin_color, 0.72, 0.0, Color.BLACK, 0.0, 1.0)
	_paint_driver_skin_on(model, skin)


func _paint_driver_skin_on(node: Node, skin: Material) -> void:
	if node is MeshInstance3D and _is_skin_mesh(node.name):
		(node as MeshInstance3D).material_override = skin
	for child in node.get_children():
		_paint_driver_skin_on(child, skin)


func _is_skin_mesh(node_name: String) -> bool:
	var base := node_name
	if base.length() > 2 and base.substr(base.length() - 2, 1) == "_" and base.substr(base.length() - 1).is_valid_int():
		base = base.substr(0, base.length() - 2)
	match base:
		"Head", "Jaw", "Chin", "Neck", "Ear", "Ear inner", "Nose bridge", "Nose tip", "Nostril", "Cheek":
			return true
	return false


func _add_rival_hitbox(root: Node3D) -> void:
	var bounds := _node_aabb(root)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size
	shape.shape = box
	root.add_child(shape)
	shape.global_position = bounds.get_center()


func _side_fits(box: AABB) -> bool:
	if box.size == Vector3.ZERO:
		return false
	var vp := get_viewport().get_visible_rect().size
	var margin_x := vp.x * 0.05
	var margin_top := vp.y * 0.06
	var margin_bottom := vp.y * 0.1
	for i in 8:
		var corner: Vector3 = box.get_endpoint(i)
		if _camera.is_position_behind(corner):
			return false
		var screen := _camera.unproject_position(corner)
		if screen.x < margin_x or screen.x > vp.x - margin_x:
			return false
		if screen.y < margin_top or screen.y > vp.y - margin_bottom:
			return false
	return true


func _on_rival_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if _popup_open() or _rival_phase == _RIVAL_LEAVE:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	_rival_engaged = true
	_race_root.visible = true
	_hover_prompt.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_sync_nav()
	get_viewport().set_input_as_handled()


func _on_rival_hover(hovering: bool) -> void:
	if _popup_open() or _rival_phase == _RIVAL_LEAVE:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	var shape := Input.CURSOR_POINTING_HAND if hovering else Input.CURSOR_ARROW
	Input.set_default_cursor_shape(shape)


func _refresh_race_popup() -> void:
	var opp: Dictionary = {}
	if _chosen_index >= 0 and _chosen_index < GameState.opponents.size():
		opp = GameState.opponents[_chosen_index]
	var rival := str(opp.get("name", "Rival"))
	var car_name := str(opp.get("car_name", "car"))
	_race_hint.text = "Racing %s in a %s.\nTank %.0f L." % [rival, car_name, GameState.fuel]
	_drag_btn.text = "Drag race\nQuarter mile · %.0f L" % GameState.race_fuel_liters(GameState.RACE_DRAG)
	_road_btn.text = "Road race\n2.4 km with turns · %.0f L" % GameState.race_fuel_liters(GameState.RACE_ROAD)


func _on_race_type_chosen(race_type: String) -> void:
	if not GameState.has_fuel_for_race(race_type):
		_show_fuel_monitor(race_type)
		return
	if race_type == GameState.RACE_DRAG:
		_show_stake_menu()
		return
	_show_road_stake_menu()


func _show_stake_menu() -> void:
	_stake_hint.text = "Side bet on the quarter mile.\nBankroll: $%d" % GameState.money
	_stake_low.disabled = GameState.money < GameState.DRAG_STAKE_LOW
	_stake_high.disabled = GameState.money < GameState.DRAG_STAKE_HIGH
	_race_root.visible = false
	_stake_root.visible = true
	_sync_nav()


func _on_stake_chosen(amount: int) -> void:
	if amount > GameState.money:
		return
	_start_race(GameState.RACE_DRAG, amount)


func _on_stake_back() -> void:
	_stake_root.visible = false
	_race_root.visible = true
	_sync_nav()


func _show_road_stake_menu() -> void:
	var opp: Dictionary = {}
	if _chosen_index >= 0 and _chosen_index < GameState.opponents.size():
		opp = GameState.opponents[_chosen_index]
	var car_name := str(opp.get("car_name", "their car"))
	_road_stake_hint.text = "Side bet on the road course.\nTheir car: %s\nBankroll: $%d" % [car_name, GameState.money]
	_road_stake_low.disabled = GameState.money < GameState.ROAD_STAKE_LOW
	_road_stake_high.disabled = GameState.money < GameState.ROAD_STAKE_HIGH
	_road_stake_pink.disabled = false
	_race_root.visible = false
	_road_stake_root.visible = true
	_sync_nav()


func _on_road_stake_chosen(amount: int) -> void:
	if amount > GameState.money:
		return
	_start_race(GameState.RACE_ROAD, amount, false)


func _on_pink_slips_chosen() -> void:
	if GameState.owned_car_ids.size() >= GameState.MAX_OWNED_CARS:
		_show_full_garage_line()
		return
	_start_race(GameState.RACE_ROAD, 0, true)


func _show_full_garage_line() -> void:
	_road_stake_root.visible = false
	if _driver_seat != null and is_instance_valid(_driver_seat):
		_speech.call("follow_node", _camera, _driver_seat, Vector3(0.0, 0.42, 0.0))
	else:
		_speech.call("show_centered")
	_speech.visible = true
	_speech.call("place")
	_sync_nav()


func _dismiss_full_garage_line() -> void:
	_speech.visible = false
	_road_stake_root.visible = true
	_sync_nav()


func _on_road_stake_back() -> void:
	_road_stake_root.visible = false
	_race_root.visible = true
	_sync_nav()


func _start_race(race_type: String, stake: int, pink_slips: bool = false) -> void:
	GameState.selected_opponent_id = _chosen_index
	GameState.selected_race_type = race_type
	GameState.race_stake = stake
	GameState.race_pink_slips = pink_slips
	GameState.current_scene_path = GameState.SCENE_RACE
	get_tree().change_scene_to_file(GameState.SCENE_RACE)


func _show_fuel_monitor(race_type: String) -> void:
	var need := GameState.race_fuel_liters(race_type)
	_fuel_message.text = "The tank has %.0f L. This race needs %.0f L.\nFill it up at the gas station first." % [GameState.fuel, need]
	_fuel_root.visible = true
	_sync_nav()


func _hide_fuel() -> void:
	_fuel_root.visible = false
	_sync_nav()


func _popup_open() -> bool:
	if _opp_root != null and _opp_root.visible:
		return true
	if _race_root != null and _race_root.visible:
		return true
	if _stake_root != null and _stake_root.visible:
		return true
	if _road_stake_root != null and _road_stake_root.visible:
		return true
	if _speech != null and _speech.visible:
		return true
	if _fuel_root != null and _fuel_root.visible:
		return true
	return false


func _on_cancel() -> void:
	if _fuel_root.visible:
		_hide_fuel()
		return
	if _stake_root.visible:
		_on_stake_back()
		return
	if _speech.visible:
		_dismiss_full_garage_line()
		return
	if _road_stake_root.visible:
		_on_road_stake_back()
		return
	if _race_root.visible:
		_show_opponents()
		return
	if _opp_root.visible:
		_hide_popups()
		return
	if _rival != null:
		_clear_rival()
		return
	_on_back_pressed()


func _sync_nav() -> void:
	if _fuel_root.visible:
		_nav.setup([_fuel_back])
		return
	if _stake_root.visible:
		_nav.setup([_stake_kicks, _stake_low, _stake_high, _stake_back])
		return
	if _speech.visible:
		_nav.clear()
		return
	if _road_stake_root.visible:
		_nav.setup([_road_stake_low, _road_stake_high, _road_stake_pink, _road_stake_back])
		return
	if _race_root.visible:
		_nav.setup([_drag_btn, _road_btn, _race_back])
		return
	if _opp_root.visible:
		var items: Array = []
		for btn in _opp_buttons:
			items.append(btn)
		items.append(_call_btn)
		items.append(_opp_back)
		_nav.setup(items)
		return
	_nav.setup([_back])


func _on_back_pressed() -> void:
	GameState.drive_into_garage = true
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)
