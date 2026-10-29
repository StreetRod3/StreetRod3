extends Node3D

## Chris' Gas. The garage fuel can drives the car here. Grab a nozzle, then click the car.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _EngineSound := preload("res://scripts/engine_sound.gd")
const _CAR_SCENE := preload("res://scenes/car_vehicle_visual.tscn")

const _PARK_X := -0.8
const _APPROACH_X := -20.0
const _EXIT_X := 20.0
const _LANE_Z := 6.45
const _CAR_YAW := PI * 0.5
const _WHEEL_R := 0.27
const _WHEEL_NODES: Array[String] = [
	"WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight",
]

const _BRICK := Color(0.55, 0.22, 0.16)
const _BLUE := Color(0.16, 0.32, 0.62)
const _BLUE_DOOR := Color(0.2, 0.4, 0.78)
const _CREAM := Color(0.93, 0.88, 0.76)
const _RED := Color(0.62, 0.1, 0.1)
const _YELLOW := Color(0.9, 0.72, 0.16)
const _WOOD := Color(0.42, 0.26, 0.14)
const _METAL := Color(0.72, 0.7, 0.66)

const _PUMP_REGULAR := Vector3(-5.75, 0.12, 4.85)
const _PUMP_SUPER := Vector3(-4.15, 0.12, 4.85)
const _DOOR_X := -2.4

const _PARKED: Array[Dictionary] = [
	{"file": "res://assets/cars/fairlane-1957.car", "paint": Color(0.62, 0.58, 0.52), "at": Vector3(8.4, 0.0, 8.9), "yaw": PI * 0.5},
]

const _TOOLTIPS := {
	&"regular": "Regular",
	&"super": "Super",
	&"office": "Office",
}

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: CanvasLayer = $UI

var _nav = _MenuNav.new()
var _world: Node3D
var _car: Node3D
var _engine: AudioStreamPlayer
var _cash: Label
var _tooltip: Label
var _back: Button
var _shade: ColorRect
var _open: Label3D
var _filler_local := Vector3(0.7, 0.65, 1.2)
var _held := ""
var _busy := false
var _time := 0.0
var _status := ""
var _status_until := 0.0
var _nozzles: Dictionary = {}
var _homes: Dictionary = {}
var _hoses: Dictionary = {}
var _outlets: Dictionary = {}
var _materials: Dictionary = {}
var _sign_font: Font
var _box_meshes: Dictionary = {}
var _sphere_meshes: Dictionary = {}
var _cylinder_meshes: Dictionary = {}


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GAS_STATION
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera.fov = 50.0
	_camera.position = Vector3(0.7, 3.25, 16.6)
	_camera.look_at(Vector3(1.15, 1.7, 0.6), Vector3.UP)
	if GameState.has_engine():
		var engine := _EngineSound.new() as AudioStreamPlayer
		engine.volume_db = -12.0
		_engine = engine
		add_child(_engine)
		_engine.call(&"set_state", 680.0, 0.0, false, false)
	_world = Node3D.new()
	_world.name = "Station"
	add_child(_world)
	_build_environment()
	_build_lights()
	_build_ground()
	_build_building()
	_build_pumps()
	_build_street()
	_build_background()
	_build_parked_cars()
	_build_player_car()
	_build_hud()
	_ensure_shade()
	_shade.color = Color(0.0, 0.0, 0.0, 1.0)
	call_deferred(&"_play_arrival")


func _exit_tree() -> void:
	GameState.set_music_dimmed(false)


func _process(delta: float) -> void:
	_time += delta
	if _open != null:
		var pulse := 0.78 + sin(_time * 6.0) * 0.22
		_open.modulate = Color(2.7 * pulse, 0.1 * pulse, 0.12 * pulse)
	_aim_hoses()
	_aim_nozzles()
	_update_tooltip()
	if _status_until > 0.0 and _time >= _status_until:
		_status = ""
		_status_until = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_leave()
		get_viewport().set_input_as_handled()
		return
	if _nav.handle_event(self, event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_activate(_kind_at(button.position))


func _play_arrival() -> void:
	_set_busy(true)
	var fade := create_tween()
	fade.tween_property(_shade, "color:a", 0.0, 0.45)
	await _pause(0.16)
	if not is_instance_valid(self):
		return
	if _car != null:
		await _roll(_PARK_X, 2.5, Tween.EASE_OUT)
	if not is_instance_valid(self):
		return
	_set_busy(false)


func _leave() -> void:
	if _busy:
		return
	_set_busy(true)
	if not _held.is_empty():
		var put_back := _held
		_held = ""
		await _move_nozzle(put_back, _home_of(put_back))
		if not is_instance_valid(self):
			return
	if _car != null:
		await _roll(_EXIT_X, 2.15, Tween.EASE_IN)
		if not is_instance_valid(self):
			return
	await _fade_to(1.0, 0.35)
	if not is_instance_valid(self):
		return
	GameState.drive_into_garage = true
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


func _activate(kind: Variant) -> void:
	if _busy or kind == null:
		return
	if kind == &"car" and _held.is_empty():
		_leave()
		return
	if kind != &"regular" and kind != &"super" and kind != &"car":
		return
	_set_busy(true)
	if kind == &"car":
		await _fuel_with_held()
	else:
		await _toggle_nozzle(String(kind))
	if is_instance_valid(self):
		_set_busy(false)


func _toggle_nozzle(id: String) -> void:
	if _held == id:
		var put_back := _held
		_held = ""
		await _move_nozzle(put_back, _home_of(put_back))
		return
	if not _held.is_empty():
		var previous := _held
		_held = ""
		await _move_nozzle(previous, _home_of(previous))
		if not is_instance_valid(self):
			return
	if _car == null:
		_show_status("No car to fuel.")
		return
	await _move_nozzle(id, _hand_point())
	if is_instance_valid(self):
		_held = id


func _fuel_with_held() -> void:
	if _held.is_empty() or _car == null:
		return
	var price := GameState.refuel_price()
	if price <= 0:
		_show_status("The tank is already full.")
		return
	if GameState.money < price:
		_show_status("Not enough cash.")
		return
	var id := _held
	await _move_nozzle(id, _filler_global())
	if not is_instance_valid(self):
		return
	_show_status("Filling up...")
	await _pause(0.65)
	if not is_instance_valid(self):
		return
	var err := GameState.refuel_tank()
	_refresh_cash()
	if err.is_empty():
		_show_status("Tank is full.")
	else:
		_show_status(err)
	await _pause(0.35)
	if not is_instance_valid(self):
		return
	_held = ""
	await _move_nozzle(id, _home_of(id))


func _move_nozzle(id: String, target: Vector3) -> void:
	var nozzle := _nozzle(id)
	if nozzle == null:
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(nozzle, "global_position", target, 0.42)
	await tw.finished


func _roll(to_x: float, duration: float, ease_type: Tween.EaseType) -> void:
	if _car == null:
		return
	var wheels: Array[Node3D] = []
	var bases: Array[Basis] = []
	for wname in _WHEEL_NODES:
		var wheel := _car.get_node_or_null(wname) as Node3D
		if wheel == null or not wheel.visible:
			continue
		wheels.append(wheel)
		bases.append(wheel.basis)
	var start := _car.position
	var end := start
	end.x = to_x
	var forward := -_car.global_transform.basis.z
	var travel := (end - start).dot(forward)
	_set_engine(true)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(ease_type)
	tw.tween_method(_apply_roll.bind(start, end, wheels, bases, travel), 0.0, 1.0, duration)
	await tw.finished
	for i in wheels.size():
		if is_instance_valid(wheels[i]):
			wheels[i].basis = bases[i]
	if is_instance_valid(_car):
		_car.position = end
	_set_engine(false)


func _apply_roll(t: float, start: Vector3, end: Vector3, wheels: Array[Node3D], bases: Array[Basis], travel: float) -> void:
	if _car == null:
		return
	_car.position = start.lerp(end, t)
	var spin := (travel * t) / _WHEEL_R
	for i in wheels.size():
		var wheel := wheels[i]
		if not is_instance_valid(wheel):
			continue
		wheel.basis = bases[i] * Basis(Vector3.UP, spin)


func _set_engine(pulling: bool) -> void:
	if _engine == null or not _engine.has_method(&"set_state") or not GameState.has_engine():
		return
	if pulling:
		GameState.set_music_dimmed(true)
		_engine.volume_db = -5.0
		_engine.call(&"set_state", 2200.0, 0.65, false, false)
		return
	_engine.volume_db = -12.0
	_engine.call(&"set_state", 680.0, 0.0, false, false)
	GameState.set_music_dimmed(false)


func _set_busy(busy: bool) -> void:
	_busy = busy
	if _back != null:
		_back.disabled = busy


func _show_status(text: String) -> void:
	_status = text
	_status_until = _time + 2.4


func _pause(seconds: float) -> void:
	var tw := create_tween()
	tw.tween_interval(seconds)
	await tw.finished


func _fade_to(alpha: float, duration: float) -> void:
	var shade := _ensure_shade()
	var tw := create_tween()
	tw.tween_property(shade, "color:a", alpha, duration)
	await tw.finished


func _ensure_shade() -> ColorRect:
	if _shade != null:
		return _shade
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_shade)
	return _shade


func _filler_global() -> Vector3:
	if _car == null:
		return _PUMP_REGULAR + Vector3(0.0, 0.7, 1.4)
	return _car.global_transform * _filler_local


func _hand_point() -> Vector3:
	return _filler_global() + Vector3(-0.28, 0.08, 0.42)


func _home_of(id: String) -> Vector3:
	return _homes[id] as Vector3


func _nozzle(id: String) -> Node3D:
	return _nozzles.get(id, null) as Node3D


func _aim_hoses() -> void:
	for id in _hoses.keys():
		var hose := _hoses[id] as MeshInstance3D
		var nozzle := _nozzle(String(id))
		if hose == null or nozzle == null or not _outlets.has(id):
			continue
		_aim_segment(hose, _outlets[id] as Vector3, nozzle.global_position)


func _aim_nozzles() -> void:
	if _car == null:
		return
	var aim := _filler_global()
	for id in _nozzles.keys():
		var nozzle := _nozzles[id] as Node3D
		if nozzle == null or not _homes.has(id):
			continue
		var home: Vector3 = _homes[id]
		if nozzle.global_position.distance_to(home) < 0.08:
			nozzle.rotation = Vector3(1.05, 0.25, 0.1)
		elif nozzle.global_position.distance_to(aim) > 0.2:
			nozzle.look_at(aim, Vector3.UP)


func _aim_segment(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 0.04:
		mesh.visible = false
		return
	mesh.visible = true
	mesh.global_position = (a + b) * 0.5
	var up := Vector3.UP
	if absf(delta.normalized().dot(Vector3.UP)) > 0.95:
		up = Vector3.RIGHT
	mesh.look_at(b, up)
	mesh.scale = Vector3(1.0, 1.0, length)


func _kind_at(screen_pos: Vector2) -> Variant:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 80.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node := hit.get("collider") as Node
	while node != null:
		if node.has_meta(&"gas_interact"):
			return node.get_meta(&"gas_interact")
		node = node.get_parent()
	return null


func _update_tooltip() -> void:
	if _tooltip == null:
		return
	if _status_until > _time and not _status.is_empty():
		_tooltip.text = _status
		return
	_tooltip.text = _tooltip_text()


func _tooltip_text() -> String:
	if _busy:
		return ""
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != _ui:
		return ""
	var kind: Variant = _kind_at(get_viewport().get_mouse_position())
	if kind == null:
		return ""
	if kind == &"car":
		if _held.is_empty():
			return "Drive back"
		var price := GameState.refuel_price()
		if price <= 0:
			return "Tank is full"
		return "Fuel the car — $%d" % price
	if kind == &"regular" or kind == &"super":
		return _pump_tip(str(_TOOLTIPS.get(kind, "Fuel")), String(kind))
	return str(_TOOLTIPS.get(kind, ""))


func _pump_tip(title: String, id: String) -> String:
	if _held == id:
		return "%s — put it back" % title
	var price := GameState.refuel_price()
	if price <= 0:
		return "%s — tank is full" % title
	if GameState.money < price:
		return "%s — $%d, not enough cash" % [title, price]
	return "%s — $%d" % [title, price]


func _build_hud() -> void:
	var bar := Control.new()
	bar.name = "HudBottom"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -44.0
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
	_cash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cash.offset_left = 20.0
	_cash.offset_right = -220.0
	_cash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_cash.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78))
	_cash.add_theme_font_size_override(&"font_size", 22)
	_cash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_cash)
	_refresh_cash()
	_tooltip = Label.new()
	_tooltip.name = "TooltipLabel"
	_tooltip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tooltip.offset_left = 400.0
	_tooltip.offset_right = -210.0
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tooltip.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78, 1))
	_tooltip.add_theme_font_size_override(&"font_size", 22)
	bar.add_child(_tooltip)
	_back = Button.new()
	_back.text = "Back to garage"
	_back.custom_minimum_size = Vector2(180, 36)
	_back.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_back.offset_left = -200.0
	_back.offset_right = -16.0
	_back.offset_top = -18.0
	_back.offset_bottom = 18.0
	_back.pressed.connect(_leave)
	_back.disabled = true
	bar.add_child(_back)
	_nav.setup([_back])


func _refresh_cash() -> void:
	if _cash == null:
		return
	_cash.text = "Bankroll: $%d    Tank: %.0f / %.0f L" % [GameState.money, GameState.fuel, GameState.DEFAULT_TANK_L]


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.008, 0.012, 0.04)
	sky_mat.sky_horizon_color = Color(0.05, 0.08, 0.16)
	sky_mat.sky_curve = 0.06
	sky_mat.ground_bottom_color = Color(0.01, 0.012, 0.02)
	sky_mat.ground_horizon_color = Color(0.04, 0.05, 0.08)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.18, 0.28)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.05
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.72
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_stars()


func _stars() -> void:
	var spots: Array[Vector3] = [
		Vector3(-8.0, 11.5, -6.0), Vector3(-3.2, 12.4, -8.0), Vector3(1.4, 11.8, -7.0),
		Vector3(5.5, 12.6, -5.5), Vector3(9.2, 11.2, -4.0), Vector3(-6.4, 10.4, -2.0),
		Vector3(3.2, 10.8, -3.5), Vector3(7.6, 13.0, -9.0), Vector3(-1.0, 13.2, -10.0),
		Vector3(11.0, 12.0, -8.5),
	]
	for spot in spots:
		_sphere(_world, 0.035, spot, Color(0.9, 0.92, 1.0), 0.4, 0.0, Color(0.85, 0.9, 1.0), 3.0, false)


func _build_lights() -> void:
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-38.0, 24.0, 0.0)
	moon.light_color = Color(0.55, 0.64, 0.85)
	moon.light_energy = 0.22
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	_world.add_child(moon)
	_omni(_world, Vector3(-0.4, 2.4, 2.2), Color(1.0, 0.72, 0.38), 2.4, 10.0)
	_omni(_world, Vector3(-4.6, 1.6, 3.2), Color(1.0, 0.78, 0.42), 1.1, 5.0)
	_omni(_world, Vector3(0.4, 2.2, -0.6), Color(1.0, 0.62, 0.32), 1.6, 6.5)


func _omni(parent: Node3D, pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	parent.add_child(light)


func _build_ground() -> void:
	_box_mat(_world, Vector3(48.0, 0.24, 11.2), Vector3(1.0, -0.12, 10.7), _tex("asphalt", _asphalt_image(), Vector3(2.4, 2.4, 2.4), 0.94))
	_box_mat(_world, Vector3(16.4, 0.32, 5.6), Vector3(-0.3, -0.06, 2.55), _tex("walk", _slab_image(Color(0.62, 0.6, 0.56), Color(0.46, 0.44, 0.4)), Vector3(0.7, 0.7, 0.7), 0.86))
	_box(_world, Vector3(36.0, 0.012, 0.08), Vector3(2.0, 0.012, 8.6), Color(0.78, 0.64, 0.16), 0.6)
	_bay_lines()


func _bay_lines() -> void:
	var paint := Color(0.82, 0.8, 0.74)
	var y := 0.02
	_box(_world, Vector3(4.8, 0.012, 0.06), Vector3(-0.85, y, 5.35), paint, 0.55)
	_box(_world, Vector3(4.8, 0.012, 0.06), Vector3(-0.85, y, 7.55), paint, 0.55)
	_box(_world, Vector3(0.06, 0.012, 2.2), Vector3(-3.25, y, 6.45), paint, 0.55)
	_box(_world, Vector3(0.06, 0.012, 2.2), Vector3(1.55, y, 6.45), paint, 0.55)


func _build_building() -> void:
	var shell := Node3D.new()
	shell.name = "Building"
	_world.add_child(shell)
	_box_mat(shell, Vector3(0.28, 3.4, 6.4), Vector3(-7.2, 1.7, -3.2), _brick_mat())
	_box_mat(shell, Vector3(0.28, 3.4, 6.4), Vector3(7.2, 1.7, -3.2), _brick_mat())
	_box_mat(shell, Vector3(14.4, 3.4, 0.28), Vector3(0.0, 1.7, -6.4), _brick_mat())
	_box_mat(shell, Vector3(14.2, 0.12, 6.2), Vector3(0.0, 3.28, -3.2), _flat(Color(0.42, 0.3, 0.2), 0.8))
	_box(shell, Vector3(14.0, 0.08, 6.0), Vector3(0.0, 0.04, -3.2), Color(0.55, 0.42, 0.28), 0.75)
	_box(shell, Vector3(14.0, 2.4, 0.08), Vector3(0.0, 2.0, -1.15), Color(0.1, 0.09, 0.13), 0.92)
	_build_facade(shell)
	_build_roof(shell)
	_build_shop_interior(shell)
	_build_office(shell)
	_build_menu(shell)
	_box(shell, Vector3(14.6, 0.14, 0.16), Vector3(-0.2, 3.28, 0.18), _BLUE, 0.5)
	_eave_lights(shell)


func _build_facade(parent: Node3D) -> void:
	_pier(parent, -7.2, -6.45)
	_poster_window(parent, -6.45, -4.7)
	_pier(parent, -4.7, -3.15)
	_pier(parent, -1.65, -1.25)
	_window(parent, -1.25, 2.25)
	_pier(parent, 2.25, 7.2)


func _pier(parent: Node3D, x0: float, x1: float) -> void:
	var width := x1 - x0
	if width < 0.04:
		return
	_box_mat(parent, Vector3(width, 3.4, 0.28), Vector3((x0 + x1) * 0.5, 1.7, 0.0), _brick_mat())


func _window(parent: Node3D, x0: float, x1: float) -> void:
	var width := x1 - x0
	var mid := (x0 + x1) * 0.5
	var sill := 0.82
	var head := 2.72
	_box_mat(parent, Vector3(width, sill, 0.28), Vector3(mid, sill * 0.5, 0.0), _brick_mat())
	_box_mat(parent, Vector3(width, 3.4 - head, 0.28), Vector3(mid, (head + 3.4) * 0.5, 0.0), _brick_mat())
	_frame(parent, x0, x1, sill, head, 0.06, _BLUE)
	_box(parent, Vector3(width - 0.12, head - sill - 0.1, 0.02), Vector3(mid, (sill + head) * 0.5, 0.07), Color(0.62, 0.8, 0.9, 0.07), 0.04, 0.05, Color(0.7, 0.85, 1.0), 0.04, Vector3.ZERO, 0.07)
	for i in 2:
		var bar_x := x0 + (width - 0.12) * (float(i) + 1.0) / 3.0
		_box(parent, Vector3(0.045, head - sill - 0.08, 0.04), Vector3(bar_x, (sill + head) * 0.5, 0.1), _BLUE, 0.4)
	_box(parent, Vector3(width - 0.14, 0.045, 0.04), Vector3(mid, (sill + head) * 0.5, 0.1), _BLUE, 0.4)


func _poster_window(parent: Node3D, x0: float, x1: float) -> void:
	var width := x1 - x0
	var mid := (x0 + x1) * 0.5
	var sill := 0.95
	var head := 2.55
	_box_mat(parent, Vector3(width, sill, 0.28), Vector3(mid, sill * 0.5, 0.0), _brick_mat())
	_box_mat(parent, Vector3(width, 3.4 - head, 0.28), Vector3(mid, (head + 3.4) * 0.5, 0.0), _brick_mat())
	_frame(parent, x0, x1, sill, head, 0.07, _BLUE)
	_box(parent, Vector3(width - 0.16, head - sill - 0.14, 0.04), Vector3(mid, (sill + head) * 0.5 + 0.02, 0.12), Color(0.93, 0.78, 0.18), 0.5)
	_label(parent, "Better Fuel", Vector3(mid, 2.05, 0.18), 26, 0.0036, Color(0.12, 0.18, 0.42), Color(0.93, 0.78, 0.18), 3)
	_label(parent, "Bigger Miles", Vector3(mid, 1.62, 0.18), 26, 0.0036, Color(0.12, 0.18, 0.42), Color(0.93, 0.78, 0.18), 3)


func _frame(parent: Node3D, x0: float, x1: float, sill: float, head: float, depth: float, color: Color) -> void:
	var mid := (x0 + x1) * 0.5
	var height := head - sill
	var z := 0.08
	_box(parent, Vector3(0.07, height, depth), Vector3(x0, (sill + head) * 0.5, z), color, 0.45)
	_box(parent, Vector3(0.07, height, depth), Vector3(x1, (sill + head) * 0.5, z), color, 0.45)
	_box(parent, Vector3(x1 - x0, 0.07, depth), Vector3(mid, head, z), color, 0.45)
	_box(parent, Vector3(x1 - x0, 0.07, depth), Vector3(mid, sill, z), color, 0.45)


func _build_roof(parent: Node3D) -> void:
	var tiles := _tex("roof", _roof_image(), Vector3(1.8, 1.8, 1.8), 0.86)
	_box_mat(parent, Vector3(15.2, 0.14, 4.15), Vector3(0.0, 4.12, -1.35), tiles, Vector3(0.5, 0.0, 0.0))
	_box_mat(parent, Vector3(15.2, 0.14, 4.15), Vector3(0.0, 4.12, -5.05), tiles, Vector3(-0.5, 0.0, 0.0))
	_box(parent, Vector3(15.3, 0.1, 0.22), Vector3(0.0, 4.95, -3.2), Color(0.28, 0.29, 0.31), 0.7)
	_box(parent, Vector3(0.12, 0.7, 3.6), Vector3(-7.45, 4.15, -1.5), _BLUE, 0.5, 0.0, Color.BLACK, 0.0, Vector3(0.5, 0.0, 0.0))
	_box(parent, Vector3(0.12, 0.7, 3.6), Vector3(7.45, 4.15, -1.5), _BLUE, 0.5, 0.0, Color.BLACK, 0.0, Vector3(0.5, 0.0, 0.0))
	_box(parent, Vector3(0.12, 0.7, 3.6), Vector3(-7.45, 4.15, -4.9), _BLUE, 0.5, 0.0, Color.BLACK, 0.0, Vector3(-0.5, 0.0, 0.0))
	_box(parent, Vector3(0.12, 0.7, 3.6), Vector3(7.45, 4.15, -4.9), _BLUE, 0.5, 0.0, Color.BLACK, 0.0, Vector3(-0.5, 0.0, 0.0))


func _build_shop_interior(parent: Node3D) -> void:
	_shelves(parent, Vector3(-0.15, 1.05, -0.38))
	_freezer(parent, Vector3(1.4, 0.0, -0.32))
	_omni(parent, Vector3(0.3, 2.35, -0.2), Color(1.0, 0.72, 0.4), 1.5, 5.0)


func _build_menu(parent: Node3D) -> void:
	var x := 3.25
	_box(parent, Vector3(1.55, 1.7, 0.08), Vector3(x, 1.45, 0.22), Color(0.08, 0.09, 0.1), 0.6)
	var lines: Array[String] = ["Snacks", "Drinks", "Maps", "Supplies"]
	for i in lines.size():
		_label(parent, lines[i], Vector3(x, 1.95 - float(i) * 0.32, 0.28), 32, 0.0042, Color(0.92, 0.9, 0.82), Color(0.08, 0.09, 0.1), 3)
	_open = _label(parent, "OPEN", Vector3(x, 2.55, 0.26), 64, 0.0052, Color(2.5, 0.12, 0.14), Color(0.35, 0.0, 0.02), 8)
	_box(parent, Vector3(0.85, 0.07, 0.04), Vector3(x, 2.78, 0.2), Color(1.0, 0.12, 0.12), 0.3, 0.0, Color(1.0, 0.08, 0.08), 2.2)
	_box(parent, Vector3(0.85, 0.07, 0.04), Vector3(x, 2.32, 0.2), Color(1.0, 0.12, 0.12), 0.3, 0.0, Color(1.0, 0.08, 0.08), 2.2)
	_omni(parent, Vector3(x, 2.55, 0.5), Color(1.0, 0.15, 0.12), 0.7, 2.4)


func _eave_lights(parent: Node3D) -> void:
	for i in 8:
		var x := -5.6 + float(i) * 1.15
		_sconce(parent, Vector3(x, 3.05, 0.28))


func _shelves(parent: Node3D, origin: Vector3) -> void:
	var goods: Array[Color] = [
		Color(0.7, 0.12, 0.12),
		Color(0.86, 0.72, 0.16),
		Color(0.15, 0.42, 0.28),
		Color(0.16, 0.28, 0.62),
		Color(0.82, 0.4, 0.16),
	]
	for row in 3:
		var y := origin.y + float(row) * 0.42
		_box(parent, Vector3(1.55, 0.045, 0.34), Vector3(origin.x, y, origin.z), _WOOD, 0.7)
		for i in 4:
			var color: Color = goods[(row + i) % goods.size()]
			_box(parent, Vector3(0.22, 0.28, 0.16), Vector3(origin.x - 0.52 + float(i) * 0.34, y + 0.18, origin.z + 0.02), color, 0.55)


func _freezer(parent: Node3D, pos: Vector3) -> void:
	_box(parent, Vector3(1.05, 0.85, 0.5), pos + Vector3(0.0, 0.42, 0.0), Color(0.93, 0.94, 0.96), 0.3, 0.1)
	_box(parent, Vector3(0.85, 0.42, 0.04), pos + Vector3(0.0, 0.55, 0.26), Color(0.55, 0.8, 0.95, 0.35), 0.08, 0.0, Color(0.6, 0.85, 1.0), 0.2, Vector3.ZERO, 0.35)
	_box(parent, Vector3(1.08, 0.08, 0.54), pos + Vector3(0.0, 0.88, 0.0), Color(0.16, 0.4, 0.72), 0.3, 0.15)
	_label(parent, "ICE", pos + Vector3(0.0, 0.38, 0.32), 52, 0.005, Color(0.1, 0.35, 0.75), Color(0.93, 0.94, 0.96), 5)


func _build_office(parent: Node3D) -> void:
	var x0 := _DOOR_X - 0.75
	var x1 := _DOOR_X + 0.75
	var sill := 0.02
	var head := 2.48
	_box_mat(parent, Vector3(x1 - x0, 3.4 - head, 0.28), Vector3(_DOOR_X, (head + 3.4) * 0.5, 0.0), _brick_mat())
	_frame(parent, x0, x1, sill, head, 0.1, _BLUE_DOOR)
	_box(parent, Vector3(x1 - x0 - 0.16, head - sill - 0.08, 0.07), Vector3(_DOOR_X, (sill + head) * 0.5, 0.12), _BLUE_DOOR, 0.42)
	_box(parent, Vector3(0.72, 1.15, 0.02), Vector3(_DOOR_X - 0.08, 1.72, 0.17), Color(0.7, 0.84, 0.95, 0.2), 0.05, 0.1, Color(0.75, 0.9, 1.0), 0.08, Vector3.ZERO, 0.18)
	_label(parent, "OFFICE", Vector3(_DOOR_X - 0.08, 1.72, 0.2), 34, 0.0042, Color(0.9, 0.95, 1.0), Color(0.08, 0.18, 0.38), 4, _readable_font())
	_box(parent, Vector3(0.05, 0.32, 0.07), Vector3(_DOOR_X + 0.42, 1.12, 0.2), Color(0.82, 0.66, 0.28), 0.25, 0.9)
	_planter(Vector3(_DOOR_X - 1.35, 0.0, 1.2))
	_planter(Vector3(_DOOR_X + 1.35, 0.0, 1.2))
	_hit_box(parent, Vector3(1.6, 2.55, 0.4), Vector3(_DOOR_X, 1.25, 0.14), &"office")


func _build_pumps() -> void:
	_pump(_PUMP_REGULAR, "REGULAR", "regular")
	_pump(_PUMP_SUPER, "SUPER", "super")
	_box(_world, Vector3(2.45, 0.08, 0.85), Vector3(-4.95, 0.08, 4.85), Color(0.58, 0.56, 0.52), 0.8)


func _pump(pos: Vector3, title: String, id: String) -> void:
	var pump := StaticBody3D.new()
	pump.name = "Pump" + id.capitalize()
	pump.position = pos
	pump.collision_mask = 0
	pump.set_meta(&"gas_interact", StringName(id))
	_world.add_child(pump)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.82, 2.15, 0.7)
	shape.shape = box
	shape.position = Vector3(0.0, 1.05, 0.0)
	pump.add_child(shape)
	_box(pump, Vector3(0.72, 0.1, 0.52), Vector3(0.0, 0.05, 0.0), Color(0.78, 0.76, 0.72), 0.55)
	_box(pump, Vector3(0.58, 1.35, 0.4), Vector3(0.0, 0.76, 0.0), _RED, 0.4)
	var grade_bg := Color(0.16, 0.12, 0.09)
	_box(pump, Vector3(0.5, 0.52, 0.03), Vector3(0.0, 1.05, 0.22), grade_bg, 0.55)
	_box(pump, Vector3(0.52, 0.07, 0.04), Vector3(0.0, 1.32, 0.23), _YELLOW, 0.35, 0.0, _YELLOW, 0.5)
	_label(pump, title, Vector3(0.0, 1.05, 0.26), 32, 0.004, Color(0.96, 0.92, 0.82), grade_bg, 2, _readable_font())
	_label(pump, "Chris' Gas", Vector3(0.0, 0.48, 0.24), 28, 0.0038, Color(1.6, 0.9, 0.18), _RED, 3, _readable_font())
	_sphere(pump, 0.2, Vector3(0.0, 1.62, 0.0), Color(0.75, 0.88, 0.95), 0.15, 0.05, Color(0.8, 0.92, 1.0), 0.35)
	_cylinder(pump, 0.1, 0.12, 0.07, Vector3(0.0, 1.86, 0.0), Color(0.84, 0.8, 0.72), 0.3, 0.55)
	var nozzle := Node3D.new()
	nozzle.name = "Nozzle"
	nozzle.position = Vector3(0.22, 1.05, 0.26)
	pump.add_child(nozzle)
	_box(nozzle, Vector3(0.07, 0.2, 0.06), Vector3(0.0, 0.0, 0.0), Color(0.12, 0.12, 0.13), 0.45, 0.2)
	_box(nozzle, Vector3(0.035, 0.035, 0.22), Vector3(0.0, -0.02, -0.12), _METAL, 0.3, 0.7)
	_nozzles[id] = nozzle
	_homes[id] = nozzle.global_position
	var hose := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.032, 0.032, 1.0)
	hose.mesh = mesh
	hose.material_override = _flat(Color(0.07, 0.07, 0.08), 0.9)
	hose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(hose)
	_hoses[id] = hose
	_outlets[id] = pump.to_global(Vector3(-0.02, 1.28, 0.18))


func _build_street() -> void:
	_sign()
	_bench(Vector3(0.35, 0.0, 1.45))
	_bin(Vector3(-4.55, 0.0, 7.85))
	_planter(Vector3(1.85, 0.0, 1.45))
	_fence(Vector3(5.15, 0.0, 1.05))
	_machine(Vector3(5.35, 0.0, 1.55))
	_tree(Vector3(-8.9, 0.0, 1.1))
	for i in 7:
		_bush(Vector3(-2.4 + float(i) * 1.45, 0.0, 9.35), 0.42)
	_bush(Vector3(4.55, 0.0, 1.7), 0.36)
	_pole(Vector3(9.7, 0.0, 2.6))
	_pole(Vector3(-5.5, 0.0, -8.2))
	_wire(Vector3(9.7, 6.55, 2.6), Vector3(14.5, 6.15, 1.4))
	_wire(Vector3(-5.5, 6.2, -8.2), Vector3(9.7, 6.7, 2.6))


func _sign() -> void:
	var root := Node3D.new()
	root.name = "RoadSign"
	root.position = Vector3(7.15, 0.0, 2.15)
	_world.add_child(root)
	_cylinder(root, 0.1, 0.14, 5.6, Vector3(0.0, 2.8, 0.0), Color(0.38, 0.26, 0.16), 0.75)
	var board := Color(0.04, 0.08, 0.06)
	var yellow := Color(0.95, 0.78, 0.16)
	var glow := Color(1.4, 1.05, 0.2)
	_box(root, Vector3(2.55, 1.85, 0.1), Vector3(-0.15, 6.15, 0.0), yellow, 0.35, 0.0, glow, 0.18)
	_box(root, Vector3(2.2, 1.5, 0.08), Vector3(-0.15, 6.15, 0.1), board, 0.5)
	_label(root, "Chris'", Vector3(-0.45, 6.5, 0.18), 70, 0.0062, glow, board, 6)
	_label(root, "Gas", Vector3(-0.45, 5.82, 0.18), 80, 0.0066, glow, board, 6)
	_arrow(root, Vector3(1.15, 6.15, 0.14))
	_sphere(root, 0.09, Vector3(-0.1, 7.2, 0.25), Color(1.0, 0.9, 0.6), 0.3, 0.0, Color(1.0, 0.85, 0.45), 2.2, false)
	_omni(root, Vector3(-0.1, 6.9, 0.7), Color(1.0, 0.82, 0.4), 0.9, 5.5)


func _arrow(parent: Node3D, pos: Vector3) -> void:
	var green := Color(0.15, 0.72, 0.22)
	var glow := Color(0.2, 1.0, 0.35)
	_box(parent, Vector3(0.55, 0.7, 0.08), pos + Vector3(-0.15, 0.0, 0.0), green, 0.4, 0.0, glow, 0.7)
	_box(parent, Vector3(0.85, 0.22, 0.07), pos + Vector3(0.42, 0.32, 0.0), green, 0.4, 0.0, glow, 0.7, Vector3(0.0, 0.0, -0.62))
	_box(parent, Vector3(0.85, 0.22, 0.07), pos + Vector3(0.42, -0.32, 0.0), green, 0.4, 0.0, glow, 0.7, Vector3(0.0, 0.0, 0.62))


func _fence(pos: Vector3) -> void:
	var metal := Color(0.7, 0.72, 0.74)
	for i in 8:
		_box(_world, Vector3(0.035, 1.45, 0.035), pos + Vector3(-0.62 + float(i) * 0.18, 0.9, 0.0), metal, 0.3, 0.75)
	for i in 5:
		_box(_world, Vector3(1.3, 0.02, 0.02), pos + Vector3(0.0, 0.32 + float(i) * 0.28, 0.0), metal, 0.3, 0.75)
	for i in 4:
		_box(_world, Vector3(0.02, 0.55, 0.02), pos + Vector3(-0.4 + float(i) * 0.28, 0.85, 0.02), metal, 0.3, 0.75, Color.BLACK, 0.0, Vector3(0.0, 0.0, 0.7))
		_box(_world, Vector3(0.02, 0.55, 0.02), pos + Vector3(-0.4 + float(i) * 0.28, 0.85, 0.02), metal, 0.3, 0.75, Color.BLACK, 0.0, Vector3(0.0, 0.0, -0.7))


func _machine(pos: Vector3) -> void:
	_box(_world, Vector3(0.62, 1.45, 0.4), pos + Vector3(0.0, 0.75, 0.0), Color(0.9, 0.91, 0.92), 0.4, 0.15)
	var oval := _cylinder(_world, 0.16, 0.16, 0.04, pos + Vector3(0.0, 0.95, 0.22), Color(0.15, 0.4, 0.75), 0.3, 0.1, Color(0.2, 0.5, 1.0), 0.4)
	oval.rotation.x = PI * 0.5
	_box(_world, Vector3(0.28, 0.35, 0.03), pos + Vector3(0.0, 0.45, 0.22), Color(0.15, 0.16, 0.18), 0.5)


func _bench(pos: Vector3) -> void:
	var bench := Node3D.new()
	bench.position = pos
	_world.add_child(bench)
	_box(bench, Vector3(0.08, 0.42, 0.08), Vector3(-0.62, 0.21, 0.16), _METAL, 0.4, 0.5)
	_box(bench, Vector3(0.08, 0.42, 0.08), Vector3(0.62, 0.21, 0.16), _METAL, 0.4, 0.5)
	_box(bench, Vector3(0.08, 0.42, 0.08), Vector3(-0.62, 0.21, -0.16), _METAL, 0.4, 0.5)
	_box(bench, Vector3(0.08, 0.42, 0.08), Vector3(0.62, 0.21, -0.16), _METAL, 0.4, 0.5)
	for i in 4:
		_box(bench, Vector3(1.45, 0.045, 0.1), Vector3(0.0, 0.44, -0.18 + float(i) * 0.12), _WOOD, 0.72)
	for i in 3:
		_box(bench, Vector3(1.45, 0.08, 0.045), Vector3(0.0, 0.62 + float(i) * 0.12, -0.24), _WOOD, 0.72)


func _bin(pos: Vector3) -> void:
	_cylinder(_world, 0.28, 0.24, 0.62, pos + Vector3(0.0, 0.32, 0.0), Color(0.1, 0.22, 0.55), 0.45, 0.15)
	_cylinder(_world, 0.3, 0.3, 0.06, pos + Vector3(0.0, 0.64, 0.0), Color(0.08, 0.16, 0.4), 0.4, 0.2)


func _planter(pos: Vector3) -> void:
	_box(_world, Vector3(0.7, 0.46, 0.48), pos + Vector3(0.0, 0.23, 0.0), Color(0.55, 0.28, 0.18), 0.82)
	_box(_world, Vector3(0.56, 0.06, 0.34), pos + Vector3(0.0, 0.48, 0.0), Color(0.28, 0.18, 0.1), 0.9)
	_sphere(_world, 0.22, pos + Vector3(0.0, 0.68, 0.0), Color(0.18, 0.42, 0.16), 0.8)
	_sphere(_world, 0.08, pos + Vector3(-0.1, 0.84, 0.06), Color(0.75, 0.14, 0.16), 0.5)
	_sphere(_world, 0.07, pos + Vector3(0.12, 0.82, -0.04), _YELLOW, 0.5)
	_sphere(_world, 0.065, pos + Vector3(0.0, 0.78, 0.1), Color(0.85, 0.45, 0.55), 0.5)


func _bush(pos: Vector3, radius: float) -> void:
	_sphere(_world, radius, pos + Vector3(0.0, radius * 0.7, 0.0), Color(0.14, 0.36, 0.12), 0.85)
	_sphere(_world, radius * 0.72, pos + Vector3(radius * 0.45, radius * 0.9, radius * 0.15), Color(0.22, 0.48, 0.16), 0.85)
	_sphere(_world, radius * 0.16, pos + Vector3(-radius * 0.2, radius * 1.15, radius * 0.35), Color(0.85, 0.25, 0.3), 0.5)
	_sphere(_world, radius * 0.14, pos + Vector3(radius * 0.35, radius * 1.05, radius * 0.4), Color(0.95, 0.82, 0.2), 0.5)


func _tree(pos: Vector3) -> void:
	_cylinder(_world, 0.18, 0.34, 2.6, pos + Vector3(0.15, 1.3, 0.0), Color(0.3, 0.18, 0.1), 0.85)
	var leaves: Array[Vector3] = [
		Vector3(0.2, 3.3, 0.4), Vector3(1.15, 3.7, 0.7), Vector3(-0.4, 3.9, 0.2),
		Vector3(0.7, 4.5, 0.1), Vector3(1.7, 4.2, 0.9), Vector3(-0.7, 4.6, -0.1),
		Vector3(0.4, 5.1, 0.3), Vector3(1.2, 4.9, 0.5),
	]
	var greens: Array[Color] = [Color(0.1, 0.34, 0.12), Color(0.18, 0.46, 0.16), Color(0.12, 0.3, 0.1), Color(0.22, 0.48, 0.18)]
	for i in leaves.size():
		_sphere(_world, 0.85 if i < 3 else 0.62, pos + leaves[i], greens[i % greens.size()], 0.88)


func _pole(pos: Vector3) -> void:
	_box(_world, Vector3(0.14, 6.6, 0.14), pos + Vector3(0.0, 3.3, 0.0), Color(0.25, 0.25, 0.27), 0.45, 0.35)
	_box(_world, Vector3(1.3, 0.08, 0.08), pos + Vector3(0.0, 6.35, 0.0), Color(0.25, 0.25, 0.27), 0.45, 0.35)
	_sphere(_world, 0.06, pos + Vector3(-0.5, 6.35, 0.0), Color(0.45, 0.42, 0.38), 0.4, 0.0, Color.BLACK, 0.0, false)
	_sphere(_world, 0.06, pos + Vector3(0.5, 6.35, 0.0), Color(0.45, 0.42, 0.38), 0.4, 0.0, Color.BLACK, 0.0, false)


func _wire(a: Vector3, b: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.015, 0.015, 1.0)
	mesh.mesh = box
	mesh.material_override = _flat(Color(0.12, 0.12, 0.13), 0.4, 0.6)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mesh)
	_aim_segment(mesh, a, b)


func _sconce(parent: Node3D, pos: Vector3) -> void:
	_box(parent, Vector3(0.08, 0.1, 0.1), pos, Color(0.2, 0.2, 0.22), 0.4, 0.5)
	_sphere(parent, 0.07, pos + Vector3(0.0, -0.02, 0.08), Color(1.0, 0.86, 0.55), 0.3, 0.0, Color(1.0, 0.8, 0.45), 1.6, false)
	_omni(parent, pos + Vector3(0.0, -0.05, 0.15), Color(1.0, 0.78, 0.45), 0.55, 3.2)


func _build_background() -> void:
	for i in 7:
		var x := -10.0 + float(i) * 3.2
		_sphere(_world, 1.1, Vector3(x, 4.6, -10.5), Color(0.02, 0.05, 0.03), 0.95)
		_sphere(_world, 0.7, Vector3(x + 0.4, 5.6, -10.8), Color(0.015, 0.04, 0.025), 0.95)
	_house(Vector3(11.4, 0.0, 3.2), 3.4, 3.2, 3.2, Color(0.5, 0.42, 0.34), Color(0.26, 0.2, 0.16))
	_house(Vector3(14.2, 0.0, 1.2), 3.0, 3.6, 3.0, Color(0.36, 0.32, 0.42), Color(0.18, 0.16, 0.16))
	var shop := Vector3(10.2, 2.45, 4.4)
	_box(_world, Vector3(1.6, 0.7, 0.08), shop, Color(0.1, 0.18, 0.42), 0.5, 0.0, Color(0.15, 0.3, 0.8), 0.4)
	_label(_world, "FOOD", shop + Vector3(0.0, 0.18, 0.06), 22, 0.004, Color(0.9, 0.92, 1.0), Color(0.1, 0.18, 0.42), 2)
	_label(_world, "DRINKS MAPS", shop + Vector3(0.0, -0.12, 0.06), 18, 0.0035, Color(0.9, 0.92, 1.0), Color(0.1, 0.18, 0.42), 2)
	_omni(_world, Vector3(10.2, 2.1, 5.2), Color(1.0, 0.75, 0.4), 0.8, 5.0)


func _house(pos: Vector3, width: float, height: float, depth: float, wall: Color, roof: Color) -> void:
	_box(_world, Vector3(width, height, depth), pos + Vector3(0.0, height * 0.5, 0.0), wall, 0.85)
	_box(_world, Vector3(width + 0.35, 0.22, depth + 0.35), pos + Vector3(0.0, height + 0.08, 0.0), roof, 0.8)
	for row in 2:
		for col in 3:
			var x := pos.x - width * 0.28 + float(col) * width * 0.28
			var y := pos.y + height * 0.4 + float(row) * height * 0.26
			_box(_world, Vector3(width * 0.14, height * 0.14, 0.06), Vector3(x, y, pos.z + depth * 0.5 + 0.02), Color(0.55, 0.72, 0.8), 0.2, 0.05, Color(1.0, 0.85, 0.55), 0.05)
	_box(_world, Vector3(width * 0.14, height * 0.28, 0.06), Vector3(pos.x, pos.y + height * 0.16, pos.z + depth * 0.5 + 0.02), Color(0.28, 0.16, 0.1), 0.7)


func _build_parked_cars() -> void:
	for spec in _PARKED:
		var car := _CAR_SCENE.instantiate() as Node3D
		var path := str(spec["file"])
		var paint: Color = spec["paint"]
		if not car.has_method(&"prepare_preview") or not bool(car.call(&"prepare_preview", path, paint)):
			push_warning("Gas station car failed to load: %s" % path)
			car.free()
			continue
		car.position = spec["at"]
		car.rotation.y = float(spec["yaw"])
		_world.add_child(car)
		_seat_car(car)


func _build_player_car() -> void:
	if not GameState.has_active_car():
		return
	var car := _CAR_SCENE.instantiate() as Node3D
	var path := GameState.current_car_file_path()
	if not car.has_method(&"prepare_preview") or not bool(car.call(&"prepare_preview", path, GameState.car_color)):
		push_warning("Gas station car failed to load: %s" % path)
		car.free()
		return
	car.name = "PlayerCar"
	car.position = Vector3(_PARK_X, 0.0, _LANE_Z)
	car.rotation.y = _CAR_YAW
	_world.add_child(car)
	_seat_car(car)
	_measure_filler(car)
	_add_car_hit(car)
	car.position.x = _APPROACH_X
	_car = car


func _add_car_hit(car: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "CarHit"
	body.collision_mask = 0
	body.set_meta(&"gas_interact", &"car")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.85, 1.4, 4.5)
	shape.shape = box
	shape.position = Vector3(0.0, 0.7, 0.15)
	body.add_child(shape)
	car.add_child(body)


func _measure_filler(car: Node3D) -> void:
	var box := _local_aabb(car)
	if box.size.length() < 0.2:
		return
	_filler_local = Vector3(
		box.position.x + box.size.x * 0.08,
		box.position.y + box.size.y * 0.5,
		box.position.z + box.size.z * 0.2
	)


func _seat_car(car: Node3D) -> void:
	var bounds := _world_aabb(car)
	if bounds.size.y > 0.05 and bounds.position.y > 0.02:
		car.position.y -= bounds.position.y
	_plant_wheels(car)


func _plant_wheels(car: Node3D) -> void:
	var lowest := INF
	var wheels: Array[Node3D] = []
	for wname in _WHEEL_NODES:
		var wheel := car.get_node_or_null(wname) as Node3D
		if wheel == null or not wheel.visible:
			continue
		var box := _world_aabb(wheel)
		if box.size.y <= 0.001:
			continue
		lowest = minf(lowest, box.position.y)
		wheels.append(wheel)
	if wheels.is_empty() or lowest <= 0.01:
		return
	for wheel in wheels:
		wheel.position.y -= lowest


func _world_aabb(node: Node) -> AABB:
	var box := AABB()
	var started := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		box = _aabb_corners(mi.global_transform, mi.mesh.get_aabb())
		started = true
	for child in node.get_children():
		var child_box := _world_aabb(child)
		if child_box.size == Vector3.ZERO:
			continue
		if not started:
			box = child_box
			started = true
		else:
			box = box.merge(child_box)
	return box


func _local_aabb(root: Node3D) -> AABB:
	return _local_aabb_from(root, root)


func _local_aabb_from(root: Node3D, node: Node) -> AABB:
	var box := AABB()
	var started := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var xf := root.global_transform.affine_inverse() * mi.global_transform
		box = _aabb_corners(xf, mi.mesh.get_aabb())
		started = true
	for child in node.get_children():
		var child_box := _local_aabb_from(root, child)
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


func _hit_box(parent: Node3D, size: Vector3, pos: Vector3, kind: StringName) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_mask = 0
	body.set_meta(&"gas_interact", kind)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


func _readable_font() -> Font:
	if _sign_font != null:
		return _sign_font
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Narrow", "Helvetica Neue", "Helvetica", "Arial"])
	font.font_weight = 700
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_sign_font = font
	return font


func _label(parent: Node3D, text: String, pos: Vector3, font_size: int, pixel: float, color: Color, outline: Color, outline_px: int, font: Font = null) -> Label3D:
	var label := Label3D.new()
	label.text = text
	if font != null:
		label.font = font
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_modulate = outline
	label.outline_size = outline_px
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	parent.add_child(label)
	return label


func _box(parent: Node3D, size: Vector3, pos: Vector3, albedo: Color, rough: float = 0.72, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 0.0, rot: Vector3 = Vector3.ZERO, alpha: float = 1.0) -> MeshInstance3D:
	return _box_mat(parent, size, pos, _flat(albedo, rough, metal, emission, energy, alpha), rot, alpha >= 0.99)


func _box_mat(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, radius: float, pos: Vector3, albedo: Color, rough: float = 0.7, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 0.0, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(radius)
	mi.material_override = _flat(albedo, rough, metal, emission, energy, 1.0)
	mi.position = pos
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cylinder(parent: Node3D, radius_top: float, radius_bottom: float, height: float, pos: Vector3, albedo: Color, rough: float = 0.7, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 0.0, alpha: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _cylinder_mesh(radius_top, radius_bottom, height)
	mi.material_override = _flat(albedo, rough, metal, emission, energy, alpha)
	mi.position = pos
	if alpha < 0.99:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


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


func _cylinder_mesh(radius_top: float, radius_bottom: float, height: float) -> CylinderMesh:
	var key := "%.3f|%.3f|%.3f" % [radius_top, radius_bottom, height]
	if _cylinder_meshes.has(key):
		return _cylinder_meshes[key] as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_top
	mesh.bottom_radius = radius_bottom
	mesh.height = height
	mesh.radial_segments = 12
	_cylinder_meshes[key] = mesh
	return mesh


func _flat(albedo: Color, rough: float, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "flat|%s|%.2f|%.2f|%s|%.2f|%.2f" % [albedo, rough, metal, emission, energy, alpha]
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(albedo.r, albedo.g, albedo.b, alpha)
	mat.roughness = rough
	mat.metallic = metal
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
	if alpha < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = mat
	return mat


func _tex(key: String, image: Image, tile: Vector3, rough: float) -> StandardMaterial3D:
	var cache := "tex|" + key
	if _materials.has(cache):
		return _materials[cache] as StandardMaterial3D
	var tex := ImageTexture.create_from_image(image)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_triplanar = true
	mat.uv1_scale = tile
	mat.roughness = rough
	_materials[cache] = mat
	return mat


func _brick_mat() -> StandardMaterial3D:
	return _tex("brick", _brick_image(), Vector3(1.35, 1.35, 1.35), 0.9)


func _brick_image() -> Image:
	var w := 16
	var h := 8
	var image := Image.create(w, h, false, Image.FORMAT_RGB8)
	var mortar := Color(0.76, 0.7, 0.62)
	var a := Color(0.62, 0.24, 0.16)
	var b := Color(0.48, 0.18, 0.13)
	for y in h:
		for x in w:
			var row := int(y / 4)
			var shifted := (x + (8 if row % 2 == 1 else 0)) % 16
			var in_brick := (y % 4) < 3 and shifted < 15
			var color := mortar
			if in_brick:
				color = a if (int(x / 4) + row) % 2 == 0 else b
			image.set_pixel(x, y, color)
	return image


func _roof_image() -> Image:
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	var a := Color(0.48, 0.49, 0.52)
	var b := Color(0.32, 0.33, 0.36)
	var mortar := Color(0.22, 0.22, 0.24)
	for y in 8:
		for x in 8:
			if y % 4 == 3:
				image.set_pixel(x, y, mortar)
			else:
				var shift := 4 if int(y / 4) % 2 == 1 else 0
				var on := (x + shift) % 8 < 7
				image.set_pixel(x, y, a if on and (x + y) % 2 == 0 else b)
	return image


func _asphalt_image() -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	var base := Color(0.16, 0.16, 0.17)
	for y in 16:
		for x in 16:
			var speck := (x * 7 + y * 13) % 11 == 0
			image.set_pixel(x, y, Color(0.28, 0.27, 0.26) if speck else base)
	return image


func _slab_image(base: Color, line: Color) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var edge := x == 0 or y == 0 or x == 15 or y == 15
			image.set_pixel(x, y, line if edge else base)
	return image
