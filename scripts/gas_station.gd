extends Node3D

## Chris' Gas. The garage fuel can drives the car here. Grab a nozzle, fuel the car, put it back, and the car drives home.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _EngineSound := preload("res://scripts/engine_sound.gd")
const _PumpSound := preload("res://scripts/pump_sound.gd")
const _CAR_SCENE := preload("res://scenes/car_vehicle_visual.tscn")
const _SpeechBubble := preload("res://scenes/speech_bubble.tscn")

const _PARK_X := -0.8
const _APPROACH_X := -20.0
const _EXIT_X := 20.0
const _LANE_Z := 6.45
const _CAR_YAW := PI * 0.5
## How far in front of the camera the held rag floats, in meters.
const _RAG_REACH := 1.8
## Held rag is a small twisted cloth on the pointer, not the full ground rag.
const _RAG_HELD_SCALE := 0.24
## Nozzle on the pointer is half the size of the one on the pump.
const _NOZZLE_HELD_SCALE := 0.5
## After a pour, the lifted nozzle is 30% smaller than the in-hand size.
const _NOZZLE_LIFTED_SCALE := _NOZZLE_HELD_SCALE * 0.7
## Liters flowing into the tank each second the nozzle stays in the filler.
const _POUR_L_PER_S := 4.0
## Full service starts when the player has not begun fueling by this time.
const _SERVICE_WAIT := 60.0
const _RAG_MODEL := "res://assets/locations/gas-station/rag.glb"
## Width of the rag on the ground, in meters.
const _RAG_WIDTH := 0.32
## Car files point the nose along local +Z. The glass is the forward edge of the roof.
const _WHEEL_R := 0.27
## Same roll note as the garage drive-in and drive-out.
const _ROLL_RPM_IDLE := 700.0
const _ROLL_RPM_PULL := 2600.0
const _ROLL_VOL_NEAR := -4.0
const _ROLL_VOL_FAR := -16.0
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
	&"rag": "Rag",
	&"windshield": "Windshield",
	&"sleeper": "Sleeping",
}

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: CanvasLayer = $UI

var _nav = _MenuNav.new()
var _world: Node3D
var _car: Node3D
var _engine: AudioStreamPlayer
var _pump_sound: AudioStreamPlayer
var _cash: Label
var _tooltip: Label
var _back: Button
var _shade: ColorRect
var _open: Label3D
var _filler_local := Vector3(0.7, 0.65, 1.2)
var _held := ""
## Nozzle is in the filler. The next click lifts it back onto the pointer.
var _nozzle_seated := false
## Nozzle is back on the pointer after fueling. The next click holsters it and the car leaves.
var _nozzle_lifted := false
## Fuel is flowing. Liters poured since the last whole-dollar charge.
var _pouring := false
var _pour_banked := 0.0
var _rag: Node3D
var _rag_mats: Array[StandardMaterial3D] = []
var _rag_home := Vector3(-6.45, 0.14, 5.25)
var _rag_held := false
## Set once the sleeper has told the player off. The next click puts the rag down.
var _rag_warned := false
## Set after a wipe. The next click, including the windshield, puts the rag down.
var _rag_wiped := false
## Windshield wipe, in the car's space. Base is the cowl, top is the header.
var _glass_base := Vector3.ZERO
var _glass_top := Vector3.ZERO
var _cursor_mode := ""
var _sleeper: Node3D
var _sleeper_top: Node3D
var _sleeper_head: Node3D
var _sleeper_thighs: Array[Node3D] = []
var _sleeper_shins: Array[Node3D] = []
var _sleeper_feet: Array[Node3D] = []
var _sleeper_bubble: Control
## Clock time when full service takes over. Negative until the car is parked.
var _service_at := -1.0
var _service_done := false
## Dollars charged per liter for the pour that is running.
var _pour_per_liter := 2.0
var _service_pour := false
var _bubble_until := 0.0
var _hit_point := Vector3.ZERO
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
		engine.set(&"play_on_ready", false)
		engine.volume_db = _ROLL_VOL_NEAR
		_engine = engine
		add_child(_engine)
	var pump := _PumpSound.new() as AudioStreamPlayer
	pump.name = "PumpSound"
	_pump_sound = pump
	add_child(pump)
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
	_build_sleeper_bubble()
	_ensure_shade()
	_shade.color = Color(0.0, 0.0, 0.0, 1.0)
	call_deferred(&"_play_arrival")


func _exit_tree() -> void:
	GameState.set_music_dimmed(false)
	Input.set_custom_mouse_cursor(null)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _process(delta: float) -> void:
	_time += delta
	if _open != null:
		var pulse := 0.78 + sin(_time * 6.0) * 0.22
		_open.modulate = Color(2.7 * pulse, 0.1 * pulse, 0.12 * pulse)
	_fly_nozzle()
	_pour_fuel(delta)
	_watch_service()
	_aim_nozzles()
	_aim_hoses()
	_fly_rag()
	_update_tooltip()
	_update_cursor()
	if _sleeper_bubble != null:
		_sleeper_bubble.visible = _bubble_until > _time
	if _status_until > 0.0 and _time >= _status_until:
		_status = ""
		_status_until = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_leave()
		get_viewport().set_input_as_handled()
		return
	if _try_station_shortcut(event):
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
	_service_at = _time + _SERVICE_WAIT


func _watch_service() -> void:
	if _service_done or _service_at < 0.0 or _busy or _pouring:
		return
	if _time < _service_at:
		return
	if GameState.fuel >= GameState.DEFAULT_TANK_L - 0.05:
		_service_done = true
		return
	_full_service()


func _full_service() -> void:
	_service_done = true
	_set_busy(true)
	if not _held.is_empty():
		var put_back := _held
		_held = ""
		_nozzle_seated = false
		_nozzle_lifted = false
		_end_pour("")
		await _move_nozzle(put_back, _home_of(put_back))
		if not is_instance_valid(self):
			return
	await _stand_attendant()
	if not is_instance_valid(self):
		return
	var missing := GameState.DEFAULT_TANK_L - GameState.fuel
	var full_price := int(ceil(maxf(missing, 0.0) * float(GameState.FUEL_PRICE_PER_L) * 2.0))
	if missing <= 0.05:
		_bubble_until = _time + 3.6
		_set_busy(false)
		return
	if GameState.money < full_price:
		_say_broke()
	else:
		_say_service()
	if GameState.money <= 0:
		_show_status("Not enough cash.")
		_bubble_until = _time + 3.6
		_set_busy(false)
		return
	var beside := _filler_global() + Vector3(0.0, 0.0, 1.15)
	beside.y = _sleeper.global_position.y
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_sleeper, "global_position", beside, 1.3)
	await tw.finished
	if not is_instance_valid(self) or _sleeper == null:
		return
	var aim := _filler_global()
	aim.y = _sleeper.global_position.y
	_sleeper.look_at(aim, Vector3.UP)
	_sleeper.rotate_y(PI)
	await _move_nozzle("regular", _filler_global())
	if not is_instance_valid(self):
		return
	_pour_per_liter = float(GameState.FUEL_PRICE_PER_L) * 2.0
	_service_pour = true
	_pouring = true
	_pour_banked = 0.0
	_set_pump_audible(true)
	while _pouring and is_instance_valid(self):
		await get_tree().process_frame
	if not is_instance_valid(self):
		return
	_service_pour = false
	await _move_nozzle("regular", _home_of("regular"))
	if not is_instance_valid(self):
		return
	_bubble_until = _time + 2.0
	_set_busy(false)


func _stand_attendant() -> void:
	if _sleeper_top == null or _sleeper_head == null:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sleeper_head, "rotation:x", 0.0, 0.35)
	tw.tween_property(_sleeper_top, "position:y", 0.22, 0.5)
	for thigh in _sleeper_thighs:
		tw.tween_property(thigh, "rotation:x", -PI * 0.5, 0.5)
		tw.tween_property(thigh, "position:y", 0.62, 0.5)
		tw.tween_property(thigh, "position:z", 0.02, 0.5)
	for shin in _sleeper_shins:
		tw.tween_property(shin, "position:y", 0.32, 0.5)
		tw.tween_property(shin, "position:z", 0.02, 0.5)
	for foot in _sleeper_feet:
		tw.tween_property(foot, "position:y", 0.05, 0.5)
		tw.tween_property(foot, "position:z", 0.06, 0.5)
	await tw.finished


func _say_service() -> void:
	_say_sleeper("Yo, you need\nfull service,\ndummy!", Vector2(280, 110))


func _say_broke() -> void:
	_say_sleeper("Gas ain't free!", Vector2(240, 56))


func _tank_open() -> bool:
	return GameState.fuel < GameState.DEFAULT_TANK_L - 0.05 and GameState.money > 0


func _say_sleeper(text: String, min_size: Vector2) -> void:
	if _sleeper_bubble == null:
		return
	_sleeper_bubble.call("set_line", text, min_size, 26)
	_sleeper_bubble.visible = true
	_bubble_until = _time + 120.0


func _leave() -> void:
	if _busy:
		return
	_end_pour("")
	_set_busy(true)
	_nozzle_seated = false
	_nozzle_lifted = false
	if _rag_held and _rag != null:
		_rag_held = false
		_rag.visible = false
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
	if _busy:
		return
	if _nozzle_lifted:
		if _tank_open() and (kind == &"car" or kind == &"windshield"):
			_nozzle_lifted = false
			_set_busy(true)
			await _fuel_with_held()
			if is_instance_valid(self):
				_set_busy(false)
			return
		_nozzle_lifted = false
		_leave()
		return
	if _nozzle_seated:
		_lift_nozzle_from_filler()
		return
	if _rag_held and (_rag_wiped or (_rag_warned and not _wipes_glass(kind))):
		_set_busy(true)
		await _return_rag()
		if is_instance_valid(self):
			_set_busy(false)
		return
	if kind == null:
		return
	if not _held.is_empty() and (kind == &"car" or kind == &"windshield"):
		_set_busy(true)
		await _fuel_with_held()
		if is_instance_valid(self):
			_set_busy(false)
		return
	if kind == &"rag" or kind == &"rag_home" or kind == &"windshield" or kind == &"sleeper":
		await _activate_rag(kind)
		return
	if _rag_held and kind == &"car":
		await _activate_rag(kind)
		return
	if _rag_held:
		return
	if kind == &"car" and _held.is_empty():
		_leave()
		return
	if kind != &"regular" and kind != &"super":
		return
	_set_busy(true)
	await _toggle_nozzle(String(kind))
	if is_instance_valid(self):
		_set_busy(false)


func _activate_rag(kind: Variant) -> void:
	if not _held.is_empty():
		_show_status("Put the nozzle back first.")
		return
	if kind == &"rag_home":
		if _rag_held:
			_set_busy(true)
			await _return_rag()
			if is_instance_valid(self):
				_set_busy(false)
			return
		_grab_rag()
		return
	if kind == &"rag":
		if not _rag_held:
			_grab_rag()
		return
	if kind == &"windshield" or (kind == &"car" and _aiming_at_glass()):
		if not _rag_held and _held.is_empty():
			_leave()
		return
	if not _rag_held:
		return
	if kind == &"sleeper":
		_cover_face()
		return
	if kind == &"car":
		_set_busy(true)
		await _wipe_windshield()
		if is_instance_valid(self):
			_set_busy(false)


func _grab_rag() -> void:
	_rag_held = true
	_rag_warned = false
	_rag_wiped = false
	if _rag != null:
		_rag.visible = true
		_set_rag_solid(false)
	_set_rag_glow(true)
	_fly_rag()


func _return_rag() -> void:
	if _rag == null:
		_rag_held = false
		return
	_attach_rag(_world)
	_rag.visible = true
	_rag.scale = Vector3.ONE
	_rag_held = false
	_rag_warned = false
	_rag_wiped = false
	_set_rag_glow(false)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_rag, "position", _rag_home, 0.32)
	tw.tween_property(_rag, "rotation", Vector3(0.0, 0.45, 0.0), 0.32)
	await tw.finished
	if not is_instance_valid(self):
		return
	_set_rag_solid(true)


func _cover_face() -> void:
	_rag_warned = true
	_bubble_until = _time + 3.6
	if _sleeper_bubble != null:
		_sleeper_bubble.call("set_line", "Get out of\nmy face,\ndummy!", Vector2(240, 96), 26)
		_sleeper_bubble.visible = true


func _wipes_glass(kind: Variant) -> bool:
	return kind == &"car" and not _aiming_at_glass()


func _nozzle_pointer_scale() -> float:
	return _NOZZLE_LIFTED_SCALE if _nozzle_lifted else _NOZZLE_HELD_SCALE


## Held nozzle stays on the pointer until it is clicked into the filler.
func _fly_nozzle() -> void:
	if _held.is_empty() or _nozzle_seated or _busy or _camera == null:
		return
	var nozzle := _nozzle(_held)
	if nozzle == null:
		return
	var from := _camera.project_ray_origin(get_viewport().get_mouse_position())
	var aim := _camera.project_ray_normal(get_viewport().get_mouse_position())
	nozzle.global_position = from + aim * _RAG_REACH
	nozzle.scale = Vector3.ONE * _nozzle_pointer_scale()


## Held rag stays on the pointer, in the world, instead of replacing the cursor.
func _fly_rag() -> void:
	if not _rag_held or _busy or _rag == null or _camera == null:
		return
	_place_rag_at(get_viewport().get_mouse_position())


func _place_rag_at(mouse: Vector2) -> void:
	if _rag == null or _camera == null:
		return
	var from := _camera.project_ray_origin(mouse)
	var aim := _camera.project_ray_normal(mouse)
	var at := from + aim * _RAG_REACH
	var to_cam := -aim
	var x := Vector3.UP.cross(to_cam)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(to_cam).normalized()
	var twist := Basis(x, to_cam, z).rotated(to_cam, 0.85).rotated(x, 0.65)
	_rag.global_transform = Transform3D(twist.scaled(Vector3.ONE * _RAG_HELD_SCALE), at)


func _wipe_windshield() -> void:
	if _rag == null or _car == null:
		_show_status("Nothing to wipe.")
		return
	_attach_rag(_world)
	_rag.visible = true
	_rag.scale = Vector3.ONE
	_set_rag_solid(false)
	_set_rag_glow(false)
	var spot := _car.global_transform * _glass_base
	var far := _car.global_transform * _glass_top
	_lay_rag_on_glass(spot, far)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in 2:
		tw.tween_property(_rag, "global_position", far, 0.16)
		tw.tween_property(_rag, "global_position", spot, 0.16)
	await tw.finished
	if not is_instance_valid(self):
		return
	_set_rag_glow(true)
	_rag_wiped = true
	_show_status("Windshield wiped.")


## The mesh nose is local +Z, opposite the way the car travels, so the glass is the
## forward edge of the roof rather than the low end of the body.
func _measure_windshield(car: Node3D) -> void:
	var box := _local_aabb(car)
	var side := _camera_side(car)
	var verts := _body_samples(car)
	if verts.is_empty() or box.size.y < 0.2:
		_glass_base = _face_point(box, side, 0.62, 0.68)
		_glass_top = _face_point(box, side, 0.54, 0.86)
		return
	var bins := 28
	var z0 := box.position.z
	var dz := box.size.z / float(bins)
	var bin_y := PackedFloat32Array()
	bin_y.resize(bins)
	bin_y.fill(-INF)
	var roof := -INF
	for p in verts:
		roof = maxf(roof, p.y)
		var index := clampi(int((p.z - z0) / dz), 0, bins - 1)
		bin_y[index] = maxf(bin_y[index], p.y)
	var hood := -INF
	for index in range(int(bins * 0.72), bins):
		hood = maxf(hood, bin_y[index])
	if hood < 0.0:
		hood = roof * 0.7
	var header_i := 0
	for index in bins:
		if bin_y[index] >= roof - 0.14:
			header_i = index
	var cowl_i := mini(bins - 1, header_i + 2)
	for index in range(header_i, bins):
		if bin_y[index] <= hood + 0.05:
			cowl_i = index
			break
	var header_z := z0 + (float(header_i) + 0.5) * dz
	var cowl_z := z0 + (float(cowl_i) + 0.5) * dz
	var top_z := lerpf(header_z, cowl_z, 0.15)
	var base_z := lerpf(header_z, cowl_z, 0.9)
	_glass_top = _skin_at(verts, side, box, top_z, roof - 0.1)
	_glass_base = _skin_at(verts, side, box, base_z, hood + 0.05)


func _camera_side(car: Node3D) -> Vector3:
	var cam := car.to_local(_camera.global_position)
	cam.y = 0.0
	if cam.length_squared() < 0.001:
		return Vector3.LEFT
	return cam.normalized()


func _body_samples(car: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	car.force_update_transform()
	_collect_body_samples(car, car.global_transform.affine_inverse(), out)
	return out


func _collect_body_samples(node: Node, to_car: Transform3D, out: PackedVector3Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).visible and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var xf := to_car * mi.global_transform
		for surface in mi.mesh.get_surface_count():
			var raw: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, raw.size() / 5000)
			for i in range(0, raw.size(), step):
				out.append(xf * raw[i])
	for child in node.get_children():
		if child is StaticBody3D:
			continue
		_collect_body_samples(child, to_car, out)


func _skin_at(verts: PackedVector3Array, side: Vector3, box: AABB, z: float, y: float) -> Vector3:
	var best := _face_point(box, side, 0.0, 0.0)
	best.y = y
	best.z = z
	var best_score := -INF
	var found := false
	for p in verts:
		if absf(p.z - z) > 0.07 or absf(p.y - y) > 0.08:
			continue
		var score := side.dot(p)
		if score > best_score:
			best_score = score
			best = p
			found = true
	if not found:
		return best + side * 0.05
	return best + side * 0.05


func _face_point(box: AABB, side: Vector3, along: float, height: float) -> Vector3:
	var point := Vector3(
		box.get_center().x,
		box.position.y + box.size.y * height,
		box.position.z + box.size.z * along
	)
	if side.x < 0.0:
		point.x = box.position.x
	else:
		point.x = box.position.x + box.size.x
	return point + side * 0.05


func _lay_rag_on_glass(spot: Vector3, far: Vector3) -> void:
	var up := far - spot
	if up.length_squared() < 0.0001:
		_rag.global_position = spot
		return
	up = up.normalized()
	var to_cam := _camera.global_position - spot
	var axis := up.cross(to_cam)
	if axis.length_squared() < 0.0001:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	var facing := axis.cross(up).normalized()
	if facing.dot(to_cam) < 0.0:
		facing = -facing
		axis = -axis
	_rag.global_transform = Transform3D(Basis(axis, up, facing), spot)


func _aiming_at_glass() -> bool:
	if _car == null:
		return false
	var box := _local_aabb(_car)
	if box.size.length() < 0.2:
		return false
	var local := _car.to_local(_hit_point)
	var front := box.position.z + box.size.z * 0.4
	var mid_y := box.position.y + box.size.y * 0.5
	return local.z <= front and local.y >= mid_y


func _attach_rag(parent: Node3D) -> void:
	if _rag == null or _rag.get_parent() == parent:
		return
	var at := _rag.global_position
	var rot := _rag.global_rotation
	_rag.reparent(parent)
	_rag.global_position = at
	_rag.global_rotation = rot


func _set_rag_solid(on: bool) -> void:
	if _rag == null:
		return
	var body := _rag.get_node_or_null(^"Pick") as CollisionObject3D
	if body != null:
		body.collision_layer = 1 if on else 0


func _update_cursor() -> void:
	var mode := "arrow"
	if not _busy:
		var kind: Variant = _kind_at(get_viewport().get_mouse_position())
		if _nozzle_seated or _nozzle_lifted:
			mode = "hand"
		elif kind == &"rag" or kind == &"rag_home":
			mode = "hand"
		elif _rag_held and (kind == &"sleeper" or _wipes_glass(kind)):
			mode = "hand"
		elif _rag_held and (_rag_wiped or _rag_warned) and (kind == &"windshield" or kind == &"car"):
			mode = "hand"
		elif _held.is_empty() and (kind == &"regular" or kind == &"super"):
			mode = "hand"
		elif not _held.is_empty() and (kind == &"car" or kind == &"windshield"):
			mode = "hand"
	if mode == _cursor_mode:
		return
	_cursor_mode = mode
	Input.set_custom_mouse_cursor(null)
	var shape := Input.CURSOR_POINTING_HAND if mode == "hand" else Input.CURSOR_ARROW
	Input.set_default_cursor_shape(shape)


func _try_station_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return false
	match key.keycode:
		KEY_P:
			_shortcut_pump()
		KEY_F:
			_shortcut_fuel()
		KEY_D:
			_leave()
		_:
			return false
	return true


## P lifts the nozzle off the pump, or hangs the held nozzle back up.
func _shortcut_pump() -> void:
	if _busy or _rag_held:
		return
	if not _held.is_empty():
		var put_back := _held
		var was_pouring := _pouring
		_end_pour("")
		_status = ""
		_status_until = 0.0
		_held = ""
		_nozzle_seated = false
		_nozzle_lifted = false
		if was_pouring and _tank_open():
			_say_sleeper("It's not full, speedy!", Vector2(300, 56))
			_bubble_until = _time + 3.6
		_set_busy(true)
		await _move_nozzle(put_back, _home_of(put_back))
		if is_instance_valid(self):
			_set_busy(false)
		return
	_set_busy(true)
	await _toggle_nozzle("regular")
	if is_instance_valid(self):
		_set_busy(false)


## F seats the nozzle and pours, or pulls it back onto the pointer.
func _shortcut_fuel() -> void:
	if _busy or _rag_held:
		return
	if _nozzle_seated or _pouring:
		_lift_nozzle_from_filler()
		return
	if _held.is_empty():
		if _car == null:
			_show_status("No car to fuel.")
			return
		if GameState.fuel >= GameState.DEFAULT_TANK_L - 0.05:
			_show_status("The tank is already full.")
			return
		if GameState.money <= 0:
			_show_status("Not enough cash.")
			_say_broke()
			_bubble_until = _time + 3.6
			return
		_held = "regular"
		_nozzle_seated = false
		_nozzle_lifted = false
	_nozzle_lifted = false
	_set_busy(true)
	await _fuel_with_held()
	if is_instance_valid(self):
		_set_busy(false)


func _lift_nozzle_from_filler() -> void:
	_end_pour("")
	_status = ""
	_status_until = 0.0
	_nozzle_seated = false
	_nozzle_lifted = true
	_fly_nozzle()
	if _tank_open():
		_say_sleeper("It's not full, speedy!", Vector2(300, 56))
		_bubble_until = _time + 3.6


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
	_held = id
	_nozzle_seated = false
	_nozzle_lifted = false
	_fly_nozzle()


func _fuel_with_held() -> void:
	if _held.is_empty() or _car == null:
		return
	if GameState.fuel >= GameState.DEFAULT_TANK_L - 0.05:
		_show_status("The tank is already full.")
		return
	if GameState.money <= 0:
		_show_status("Not enough cash.")
		_say_broke()
		_bubble_until = _time + 3.6
		return
	var id := _held
	await _move_nozzle(id, _filler_global())
	if not is_instance_valid(self):
		return
	_nozzle_seated = true
	_pour_per_liter = float(GameState.FUEL_PRICE_PER_L)
	_service_pour = false
	_service_done = true
	_pouring = true
	_pour_banked = 0.0
	_set_pump_audible(true)
	_show_status("Filling up...")


## Fuel runs in while the nozzle stays seated. Pulling it out stops the pour.
func _pour_fuel(delta: float) -> void:
	if not _pouring:
		return
	var room := GameState.DEFAULT_TANK_L - GameState.fuel
	if room <= 0.05:
		_end_pour("Tank is full.")
		return
	var step := minf(_POUR_L_PER_S * delta, room)
	var price := _pour_per_liter
	if price <= 0.0:
		_end_pour("")
		return
	# Unpaid liters already in the tank still have to be covered by the cash left.
	var affordable := float(GameState.money) / price - _pour_banked
	step = minf(step, maxf(affordable, 0.0))
	if step <= 0.0001:
		_end_pour("Not enough cash.")
		return
	_pour_banked += step
	GameState.set_fuel(GameState.fuel + step)
	var owed := int(floor(_pour_banked * price))
	if owed > 0:
		var pay := mini(owed, GameState.money)
		GameState.money -= pay
		_pour_banked -= float(pay) / price
	if _cash != null:
		_cash.text = "Bankroll: $%d    Tank: %.1f / %.0f L" % [GameState.money, GameState.fuel, GameState.DEFAULT_TANK_L]
	var filling := "Full service... %.1f L" if _service_pour else "Filling up... %.1f L"
	_status = filling % GameState.fuel
	_status_until = _time + 0.35
	if GameState.fuel >= GameState.DEFAULT_TANK_L - 0.05:
		_end_pour("Tank is full.")
	elif GameState.money <= 0 and _pour_banked * price < 0.01:
		_end_pour("Not enough cash.")


func _end_pour(message: String) -> void:
	var was_pouring := _pouring
	_pouring = false
	if was_pouring:
		_set_pump_audible(false)
	if was_pouring or _pour_banked > 0.0:
		var price := _pour_per_liter
		var owed := int(ceil(_pour_banked * price - 0.001))
		if owed > 0 and GameState.money >= owed:
			GameState.money -= owed
		elif _pour_banked > 0.0:
			GameState.set_fuel(GameState.fuel - _pour_banked)
		_pour_banked = 0.0
		GameState.commit_fuel()
		_refresh_cash()
	if was_pouring and not message.is_empty():
		_show_status(message)
		if message == "Not enough cash.":
			_say_broke()
			_bubble_until = _time + 3.6


func _set_pump_audible(on: bool) -> void:
	if _pump_sound == null:
		return
	if on == _pump_sound.playing:
		return
	if on:
		_pump_sound.play()
	else:
		_pump_sound.stop()


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
	var pulling_away := absf(end.x - _PARK_X) > absf(start.x - _PARK_X)
	_start_roll_engine()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(ease_type)
	tw.tween_method(_apply_roll.bind(start, end, wheels, bases, travel, pulling_away), 0.0, 1.0, duration)
	await tw.finished
	for i in wheels.size():
		if is_instance_valid(wheels[i]):
			wheels[i].basis = bases[i]
	if is_instance_valid(_car):
		_car.position = end
	_stop_roll_engine()


func _apply_roll(
	t: float,
	start: Vector3,
	end: Vector3,
	wheels: Array[Node3D],
	bases: Array[Basis],
	travel: float,
	pulling_away: bool
) -> void:
	if _car == null:
		return
	_car.position = start.lerp(end, t)
	var spin := (travel * t) / _WHEEL_R
	for i in wheels.size():
		var wheel := wheels[i]
		if not is_instance_valid(wheel):
			continue
		wheel.basis = bases[i] * Basis(Vector3.UP, spin)
	var span := maxf(absf(end.x - start.x), 0.001)
	var away := clampf(absf(_car.position.x - _PARK_X) / span, 0.0, 1.0)
	_update_roll_engine(t, pulling_away, away)


func _start_roll_engine() -> void:
	if _engine == null or not _engine.has_method(&"set_state") or not GameState.has_engine():
		return
	GameState.set_music_dimmed(true)
	_engine.volume_db = _ROLL_VOL_NEAR
	_engine.call(&"set_state", _ROLL_RPM_IDLE, 0.15, false)


func _update_roll_engine(t: float, pulling_away: bool, away: float) -> void:
	if _engine == null or not _engine.playing:
		return
	var rpm := lerpf(_ROLL_RPM_IDLE, _ROLL_RPM_PULL, t)
	var throttle := lerpf(0.3, 0.9, t)
	if not pulling_away:
		rpm = lerpf(_ROLL_RPM_PULL, _ROLL_RPM_IDLE, t)
		throttle = lerpf(0.55, 0.0, t)
	_engine.volume_db = lerpf(_ROLL_VOL_NEAR, _ROLL_VOL_FAR, away)
	_engine.call(&"set_state", rpm, throttle, false)


func _stop_roll_engine() -> void:
	if _engine != null:
		_engine.volume_db = -6.0
		if _engine.playing:
			_engine.stop()
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
		var in_hand := String(id) == _held and not _nozzle_seated and not _busy
		nozzle.scale = Vector3.ONE * (_nozzle_pointer_scale() if in_hand else 1.0)


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
	_hit_point = hit.get("position", Vector3.ZERO)
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
	if _nozzle_seated:
		return "Take the nozzle"
	if _nozzle_lifted:
		if _tank_open() and (kind == &"car" or kind == &"windshield"):
			return _fuel_tip()
		return "Put the nozzle back"
	if _rag_held and _rag_wiped:
		return "Put the rag down"
	if _rag_held and _rag_warned:
		if _wipes_glass(kind):
			return "Wipe the windshield"
		return "Put the rag down"
	if kind == null:
		return ""
	if kind == &"car":
		if _rag_held and _aiming_at_glass():
			return ""
		if _rag_held:
			return "Wipe the windshield"
		if _held.is_empty():
			return "Drive back"
		return _fuel_tip()
	if kind == &"windshield" and not _held.is_empty() and not _rag_held:
		return _fuel_tip()
	if kind == &"rag_home" and _rag_held:
		return "Put the rag back"
	if kind == &"rag" or kind == &"rag_home":
		return "Rag"
	if kind == &"windshield" and _held.is_empty() and not _rag_held:
		return "Drive back"
	if kind == &"sleeper" and _rag_held:
		return "Wave it in his face"
	if kind == &"regular" or kind == &"super":
		return _pump_tip(str(_TOOLTIPS.get(kind, "Fuel")), String(kind))
	return str(_TOOLTIPS.get(kind, ""))


func _fuel_tip() -> String:
	var price := GameState.refuel_price()
	if price <= 0:
		return "Tank is full"
	return "Fuel the car — $%d" % price


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
	_build_rag()


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


func _build_rag() -> void:
	var spot := _rag_home
	_box(_world, Vector3(0.38, 0.012, 0.26), spot + Vector3(0.0, -0.02, 0.0), Color(0.28, 0.34, 0.36), 0.92)
	_hit_box(_world, Vector3(0.46, 0.16, 0.34), spot, &"rag_home")
	var rag := Node3D.new()
	rag.name = "Rag"
	rag.position = spot
	rag.rotation = Vector3(0.0, 0.45, 0.0)
	_world.add_child(rag)
	var packed := load(_RAG_MODEL) as PackedScene
	if packed == null:
		push_error("Rag model failed to load: %s" % _RAG_MODEL)
		_rag = rag
		return
	var model := packed.instantiate() as Node3D
	model.name = "Cloth"
	rag.add_child(model)
	var bounds := _local_aabb(model)
	var span := maxf(bounds.size.x, bounds.size.z)
	if span > 0.001:
		var fit := _RAG_WIDTH / span
		model.scale = Vector3.ONE * fit
		model.position = -bounds.get_center() * fit
		model.force_update_transform()
	_keep_rag_materials(model)
	var fitted := _local_aabb(rag)
	if fitted.size != Vector3.ZERO:
		rag.position.y += -fitted.position.y
		_rag_home = rag.position
	var pick := StaticBody3D.new()
	pick.name = "Pick"
	pick.collision_mask = 0
	pick.set_meta(&"gas_interact", &"rag")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var pick_size := fitted.size
	if pick_size == Vector3.ZERO:
		pick_size = Vector3(0.38, 0.12, 0.28)
	box.size = pick_size
	shape.shape = box
	shape.position = fitted.get_center()
	pick.add_child(shape)
	rag.add_child(pick)
	_rag = rag


func _keep_rag_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var active := mi.get_active_material(0) as StandardMaterial3D
		if active != null:
			var lit := active.duplicate() as StandardMaterial3D
			lit.emission_enabled = false
			lit.emission = active.albedo_color
			lit.emission_energy_multiplier = 0.0
			mi.material_override = lit
			_rag_mats.append(lit)
	for child in node.get_children():
		_keep_rag_materials(child)


## The cloth leaves the pump lights while it flies, so it keeps its own color.
func _set_rag_glow(on: bool) -> void:
	for mat in _rag_mats:
		mat.emission_enabled = on
		mat.emission_energy_multiplier = 0.55 if on else 0.0


func _build_street() -> void:
	_sign()
	_bench(Vector3(0.35, 0.0, 1.45))
	_bin(Vector3(-4.55, 0.0, 7.85))
	_planter(Vector3(1.85, 0.0, 1.45))
	_fence(Vector3(5.15, 0.0, 1.05))
	_machine(Vector3(5.35, 0.0, 1.55))
	_tree(Vector3(-8.9, 0.0, 1.1))
	_sitter(Vector3(6.35, 0.1, 2.45))
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


func _sitter(pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Sitter"
	root.position = pos
	_world.add_child(root)
	var wood := Color(0.4, 0.24, 0.13)
	var skin := Color(0.72, 0.52, 0.38)
	var shirt := Color(0.16, 0.32, 0.55)
	var pants := Color(0.2, 0.18, 0.16)
	var shoes := Color(0.1, 0.08, 0.07)
	for side in [-0.2, 0.2]:
		for depth in [-0.16, 0.16]:
			_box(root, Vector3(0.04, 0.46, 0.04), Vector3(side, 0.23, depth), wood, 0.72)
	_box(root, Vector3(0.48, 0.045, 0.4), Vector3(0.0, 0.46, 0.0), wood, 0.68)
	_box(root, Vector3(0.48, 0.42, 0.04), Vector3(0.0, 0.68, -0.18), wood, 0.68)
	var person := Node3D.new()
	person.name = "Person"
	root.add_child(person)
	_sleeper = person
	var top := Node3D.new()
	top.name = "Top"
	person.add_child(top)
	_sleeper_top = top
	_box(top, Vector3(0.34, 0.14, 0.22), Vector3(0.0, 0.58, 0.0), pants, 0.75)
	for side in [-0.09, 0.09]:
		var thigh := _box(person, Vector3(0.12, 0.1, 0.28), Vector3(side, 0.56, 0.22), pants, 0.75)
		var shin := _box(person, Vector3(0.1, 0.32, 0.1), Vector3(side, 0.28, 0.34), pants, 0.75)
		var foot := _box(person, Vector3(0.11, 0.05, 0.16), Vector3(side, 0.08, 0.38), shoes, 0.6)
		_sleeper_thighs.append(thigh)
		_sleeper_shins.append(shin)
		_sleeper_feet.append(foot)
	_box(top, Vector3(0.34, 0.36, 0.18), Vector3(0.0, 0.84, -0.02), shirt, 0.65)
	_box(top, Vector3(0.09, 0.26, 0.09), Vector3(-0.22, 0.78, 0.08), shirt, 0.65)
	_box(top, Vector3(0.09, 0.26, 0.09), Vector3(0.22, 0.78, 0.08), shirt, 0.65)
	_sphere(top, 0.045, Vector3(-0.22, 0.64, 0.12), skin, 0.55)
	_sphere(top, 0.045, Vector3(0.22, 0.64, 0.12), skin, 0.55)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 1.14, 0.0)
	head.rotation.x = 0.55
	top.add_child(head)
	_sleeper_head = head
	_sphere(head, 0.12, Vector3.ZERO, skin, 0.5)
	_sphere(head, 0.11, Vector3(0.0, 0.08, -0.02), Color(0.14, 0.09, 0.07), 0.7)
	_box(head, Vector3(0.2, 0.035, 0.18), Vector3(0.0, 0.1, 0.02), shirt, 0.5)
	_box(head, Vector3(0.14, 0.03, 0.08), Vector3(0.0, 0.08, 0.14), shirt, 0.5)
	_box(head, Vector3(0.055, 0.012, 0.012), Vector3(-0.04, 0.02, 0.11), Color(0.15, 0.1, 0.08), 0.4)
	_box(head, Vector3(0.055, 0.012, 0.012), Vector3(0.04, 0.02, 0.11), Color(0.15, 0.1, 0.08), 0.4)
	_hit_box(head, Vector3(0.32, 0.32, 0.32), Vector3(0.0, 0.02, 0.06), &"sleeper")


func _build_sleeper_bubble() -> void:
	if _sleeper_head == null:
		return
	var bubble := _SpeechBubble.instantiate()
	bubble.visible = false
	_ui.add_child(bubble)
	bubble.call("set_line", "Get out of\nmy face,\ndummy!", Vector2(240, 96), 26)
	bubble.call("follow_node", _camera, _sleeper_head, Vector3(0.0, 0.28, 0.12))
	_sleeper_bubble = bubble


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
	_add_windshield(car)
	_measure_windshield(car)
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


func _add_windshield(car: Node3D) -> void:
	var box := _local_aabb(car)
	if box.size.length() < 0.2:
		return
	var pos := Vector3(
		box.position.x + box.size.x * 0.06,
		box.position.y + box.size.y * 0.7,
		box.position.z + box.size.z * 0.14
	)
	_hit_box(car, Vector3(0.5, 0.42, 0.72), pos, &"windshield")


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
