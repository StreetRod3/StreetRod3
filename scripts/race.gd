extends Node3D

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _CarBump := preload("res://scripts/car_bump.gd")
const _SpeechBubble := preload("res://scenes/speech_bubble.tscn")

const QUARTER_MILE_M := 402.336

const COUNTDOWN_RED_S := 1.2
const COUNTDOWN_RED_ORANGE_S := 1.0
const COUNTDOWN_GREEN_VISIBLE_S := 0.55

## 0 = red only, 1 = red + orange, 2 = green (race running), 3 = lights hidden
var _countdown_phase: int = 0
var _phase_time: float = 0.0
var _race_started: bool = false

@onready var _player: CharacterBody3D = $PlayerCar
@onready var _opponent: CharacterBody3D = $OpponentCar
@onready var _hud_speed: Label = $RaceUI/Panel/Margin/VBox/SpeedLabel
@onready var _hud_gear: Label = $RaceUI/Panel/Margin/VBox/GearLabel
@onready var _hud_hint: Label = $RaceUI/Panel/Margin/VBox/HintLabel
@onready var _hud_dist: Label = $RaceUI/Panel/Margin/VBox/DistLabel
@onready var _hud_time: Label = $RaceUI/Panel/Margin/VBox/TimeLabel
@onready var _hud_opp: Label = $RaceUI/Panel/Margin/VBox/OppLabel
@onready var _rpm_meter: Control = $RaceUI/RpmMeter
@onready var _mobile: Control = $RaceUI/MobileControls
@onready var _result: Control = $RaceUI/ResultPanel
@onready var _traffic: Control = $RaceUI/TrafficLights
@onready var _light_red: ColorRect = $RaceUI/TrafficLights/Center/HBox/LightRed
@onready var _light_orange: ColorRect = $RaceUI/TrafficLights/Center/HBox/LightOrange
@onready var _light_green: ColorRect = $RaceUI/TrafficLights/Center/HBox/LightGreen
@onready var _track: Node3D = $RaceTrack
@onready var _ground: StaticBody3D = $Ground
@onready var _finish: Area3D = $FinishLine

@onready var _pause_menu: Control = $RaceUI/PauseMenu
@onready var _pause_main: Control = $RaceUI/PauseMenu/Panel
@onready var _pause_settings: Control = $RaceUI/PauseMenu/SettingsPanel
@onready var _pause_confirm: Control = $RaceUI/PauseMenu/ConfirmPanel
@onready var _pause_fullscreen: CheckBox = $RaceUI/PauseMenu/SettingsPanel/Margin/VBox/FullscreenCheck
@onready var _pause_master: HSlider = $RaceUI/PauseMenu/SettingsPanel/Margin/VBox/MasterSlider
@onready var _pause_music: CheckBox = $RaceUI/PauseMenu/SettingsPanel/Margin/VBox/MusicCheck
@onready var _pause_arcade: CheckBox = $RaceUI/PauseMenu/SettingsPanel/Margin/VBox/ArcadeCheck

var _race_over: bool = false
var _car_bump: _CarBump = _CarBump.new()
var _fuel_used: bool = false
var _opponent_finished: bool = false
var _is_road: bool = false
var _elapsed: float = 0.0
var _nav = _MenuNav.new()
var _result_bubble: Control
## Scene the result bubble leads to when clicked. Empty until the race ends.
var _result_scene: String = ""

## Closing speed between the two cars that wrecks the player's car. Ordinary bumps stay below it.
const WRECK_BUMP_MPS := 9.0

## Dim “off” lamp colors (same hue, low value).
const _DIM_RED := Color(0.12, 0.05, 0.05, 1)
const _DIM_ORANGE := Color(0.12, 0.08, 0.03, 1)
const _DIM_GREEN := Color(0.04, 0.1, 0.05, 1)
const _ON_RED := Color(1.0, 0.12, 0.12, 1)
const _ON_ORANGE := Color(1.0, 0.58, 0.08, 1)
const _ON_GREEN := Color(0.2, 0.95, 0.28, 1)


func _ready() -> void:
	# After both cars have moved, so a bump sees this frame's positions.
	process_priority = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	_opponent.process_mode = Node.PROCESS_MODE_PAUSABLE
	$RaceUI.process_mode = Node.PROCESS_MODE_PAUSABLE
	_pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	GameState.current_scene_path = GameState.SCENE_RACE
	GameState.update_music()
	_is_road = GameState.selected_race_type == GameState.RACE_ROAD
	_setup_race_layout()
	_result.visible = false
	_build_result_bubble()
	_reset_pause_pages()
	_pause_menu.visible = false
	var opp := GameState.selected_opponent()
	var rival := str(opp.get("name", "Rival"))
	var car_name := str(opp.get("car_name", ""))
	if car_name.is_empty():
		_hud_opp.text = "Opponent: %s" % rival
	else:
		_hud_opp.text = "Opponent: %s (%s)" % [rival, car_name]
	if _player.has_method(&"is_automatic_gearbox") and _player.is_automatic_gearbox():
		_hud_hint.text = "W / Up: throttle · S / Down: brake · A/D or arrows: steer · C: camera"
	else:
		_hud_hint.text = "W / Up: throttle · S / Down: brake · A/D or arrows: steer · Q/E: shift · C: camera"
	_traffic.visible = true
	_refresh_traffic_lights()

	# Apply the player's selected paint color to the shared car visuals.
	var player_pivot := _player.get_node_or_null("CarPivot")
	if player_pivot != null and player_pivot.has_method(&"set_car_body_color"):
		player_pivot.set_car_body_color(GameState.car_color)
	# Defer so the MeshInstance child scripts have a chance
	# to populate `MeshInstance3D.mesh` before we inspect it.
	call_deferred(&"_debug_car_mesh_resource_load")
	call_deferred(&"_debug_car_mesh_instances")
	call_deferred(&"_align_race_cars_to_ground")


func is_race_started() -> bool:
	return _race_started


func get_race_track() -> Node:
	if _is_road and _track != null and _track.has_method(&"is_road_course") and _track.is_road_course():
		return _track
	return null


func _setup_race_layout() -> void:
	if not _is_road:
		return
	_ground.visible = false
	_ground.collision_layer = 0
	_ground.collision_mask = 0
	if _track.has_method(&"finish_basis"):
		_finish.global_transform = _track.finish_basis()
	var col := _finish.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		var box := BoxShape3D.new()
		box.size = Vector3(42, 8, 5)
		col.shape = box


func _debug_car_mesh_instances() -> void:
	# Prints bounds and surface counts for each MeshInstance3D under player/opponent.
	# Wheels will also show up; the car body node is usually the one named `MeshInstance3D`.
	_debug_body_mesh_instances(_player, "player")
	_debug_body_mesh_instances(_opponent, "opponent")


func _debug_car_mesh_resource_load() -> void:
	# One-time check: whether Godot can actually load the STL import resource.
	var stl_path := "res://assets/vette-c1.stl"
	var exists_array_mesh := ResourceLoader.exists(stl_path, &"ArrayMesh")
	var loaded := ResourceLoader.load(stl_path)
	var loaded_type := "<null>"
	if loaded != null:
		loaded_type = loaded.get_class()

	print("[DEBUG CAR][race] ResourceLoader stl_path=", stl_path,
		" exists(ArrayMesh)=", exists_array_mesh,
		" loaded=", loaded != null,
		" loaded_type=", loaded_type)


func _align_race_cars_to_ground() -> void:
	var floor_mi: MeshInstance3D = $Ground/MeshInstance3D
	if _is_road and _track.has_method(&"get_road_mesh_instance"):
		var road_mi: MeshInstance3D = _track.get_road_mesh_instance()
		if road_mi != null:
			floor_mi = road_mi
	for car in [_player, _opponent]:
		var pivot: Node = car.get_node_or_null("CarPivot")
		if pivot != null and pivot.has_method(&"align_wheels_to_floor"):
			pivot.align_wheels_to_floor(floor_mi)


func _debug_body_mesh_instances(body: Node, label: String) -> void:
	if body == null:
		print("[DEBUG CAR][race] Missing body for ", label)
		return

	_debug_mesh_instances_recursive(body, label)


func _debug_mesh_instances_recursive(node: Node, label: String) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mesh := mi.mesh
			var surfaces := 0
			var resource_path := "<null>"
			if mesh != null:
				resource_path = mesh.resource_path
				if mesh.has_method(&"get_surface_count"):
					surfaces = mesh.get_surface_count()

			var aabb := mi.get_aabb() # local-space bounds
			var center_local := aabb.position + aabb.size * 0.5
			var center_world := mi.global_transform * center_local

			print("[DEBUG CAR][race] ", label, " node=", mi.get_path(), " visible=", mi.visible,
				" mesh_null=", mesh == null,
				" mesh_resource=", resource_path,
				" surface_count=", surfaces,
				" local_aabb_size=", aabb.size,
				" center_world=", center_world)
		_debug_mesh_instances_recursive(child, label)


func _physics_process(_delta: float) -> void:
	if get_tree().paused or _race_over or not _race_started:
		return
	if _car_bump.resolve(_player, _opponent) >= WRECK_BUMP_MPS:
		_show_wreck()


func _process(delta: float) -> void:
	if get_tree().paused or _race_over:
		return
	if _player.has_method(&"get_gear_label"):
		_hud_gear.text = "Gear: %s" % _player.get_gear_label()
	_update_rpm_meter()
	if _race_started and not _race_over and _player.has_method(&"is_engine_blown") and _player.is_engine_blown():
		_show_engine_blown()
		return
	if _race_started and _player.has_method(&"is_wrecked") and _player.is_wrecked():
		_show_wreck()
		return
	if not _race_started:
		_advance_countdown(delta)
		return
	if _countdown_phase == 2:
		_phase_time += delta
		if _phase_time >= COUNTDOWN_GREEN_VISIBLE_S:
			_countdown_phase = 3
			_traffic.visible = false

	_elapsed += delta
	_hud_time.text = "Time: %.2f s" % _elapsed
	_hud_dist.text = "To finish: %.1f m" % _distance_to_finish()
	var spd: float = _player.get_forward_speed()
	_hud_speed.text = "Speed: %.0f km/h" % (spd * 3.6)
	_maybe_finish_by_progress()


func _advance_countdown(delta: float) -> void:
	_phase_time += delta
	if _countdown_phase == 0:
		if _phase_time >= COUNTDOWN_RED_S:
			_countdown_phase = 1
			_phase_time = 0.0
			_refresh_traffic_lights()
	elif _countdown_phase == 1:
		if _phase_time >= COUNTDOWN_RED_ORANGE_S:
			_countdown_phase = 2
			_phase_time = 0.0
			_race_started = true
			if not _fuel_used:
				_fuel_used = true
				GameState.consume_race_fuel()
			_refresh_traffic_lights()


func _refresh_traffic_lights() -> void:
	match _countdown_phase:
		0:
			_light_red.color = _ON_RED
			_light_orange.color = _DIM_ORANGE
			_light_green.color = _DIM_GREEN
		1:
			_light_red.color = _ON_RED
			_light_orange.color = _ON_ORANGE
			_light_green.color = _DIM_GREEN
		2, 3:
			_light_red.color = _DIM_RED
			_light_orange.color = _DIM_ORANGE
			_light_green.color = _ON_GREEN


func _on_finish_area_body_entered(body: Node3D) -> void:
	if _race_over or not _race_started:
		return
	if body == _player:
		_finish_player()
	elif body == _opponent:
		_opponent_finished = true


func _distance_to_finish() -> float:
	if _is_road and _track.has_method(&"remaining_distance"):
		return _track.remaining_distance(_player.global_position)
	return maxf(0.0, QUARTER_MILE_M - _player.global_position.z)


func _maybe_finish_by_progress() -> void:
	if not _is_road or _race_over or _track == null:
		return
	var p_rem: float = _track.remaining_distance(_player.global_position)
	var o_rem := INF
	if _opponent.has_method(&"get_path_s"):
		o_rem = maxf(0.0, _track.get_length() - _opponent.get_path_s())
	if o_rem <= 1.0:
		_opponent_finished = true
	if p_rem <= 1.0:
		_finish_player()


func _update_rpm_meter() -> void:
	if _rpm_meter == null or not _rpm_meter.has_method(&"set_reading"):
		return
	if not _player.has_method(&"get_rpm"):
		return
	_rpm_meter.set_reading(
		_player.get_rpm(),
		_player.get_rpm_shift_start(),
		_player.get_rpm_redline(),
		_player.get_rpm_critical(),
		_player.is_engine_blown()
	)


func _finish_player() -> void:
	if _race_over:
		return
	_race_over = true
	GameState.drift_engine_tune_after_race()
	_show_result(not _opponent_finished)


func _show_engine_blown() -> void:
	_race_over = true
	_end_race_ui()
	GameState.remove_engine()
	var payout := GameState.apply_race_stake(false)
	var text := "You blew the engine!"
	if GameState.apply_pink_slips(false) == GameState.PINK_LOST:
		text += "\nThey took your car!"
	text += _lost_bucks_line(payout)
	_show_bubble(text, GameState.SCENE_GARAGE)


func _show_wreck() -> void:
	if _race_over:
		return
	_race_over = true
	_end_race_ui()
	# A wrecked car can't be handed over, so pink slips are void.
	GameState.race_pink_slips = false
	var payout := GameState.apply_race_stake(false)
	GameState.wreck_active_car()
	_show_bubble("You wrecked the car!" + _lost_bucks_line(payout), GameState.SCENE_GARAGE)


func _show_result(player_won: bool) -> void:
	_end_race_ui()
	var payout := GameState.apply_race_stake(player_won)
	var pink := GameState.apply_pink_slips(player_won)
	if player_won:
		if pink == GameState.PINK_WON:
			_show_bubble("You just won a helluva car!", GameState.SCENE_GARAGE)
		elif payout > 0:
			_show_bubble("You just won %d bucks!" % payout, GameState.SCENE_DRIVE_IN)
		else:
			_show_bubble("You just won the race!", GameState.SCENE_DRIVE_IN)
		return
	if pink == GameState.PINK_LOST:
		_show_bubble("They took your car!" + _lost_bucks_line(payout), GameState.SCENE_GARAGE)
	elif payout < 0:
		_show_bubble("You lost %d bucks!" % -payout, GameState.SCENE_DRIVE_IN)
	else:
		_show_bubble("You lost the race!", GameState.SCENE_DRIVE_IN)


func _lost_bucks_line(payout: int) -> String:
	if payout >= 0:
		return ""
	return "\nYou lost %d bucks!" % -payout


func _end_race_ui() -> void:
	_resume_race()
	if _mobile != null:
		_mobile.visible = false
	if _rpm_meter != null:
		_rpm_meter.visible = false


func _build_result_bubble() -> void:
	var bubble := _SpeechBubble.instantiate()
	_result.add_child(bubble)
	bubble.call("show_centered")
	_result_bubble = bubble
	_result.gui_input.connect(_on_result_input)


func _show_bubble(text: String, next_scene: String) -> void:
	_result_bubble.call("set_line", text, Vector2(320, 56), 26)
	_result_scene = next_scene
	_result.visible = true
	_result_bubble.call("place")


func _on_result_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		get_viewport().set_input_as_handled()
		_leave_result()


func _leave_result() -> void:
	if _result_scene.is_empty():
		return
	var next_scene := _result_scene
	_result_scene = ""
	get_tree().paused = false
	GameState.current_scene_path = next_scene
	get_tree().change_scene_to_file(next_scene)


func _unhandled_input(event: InputEvent) -> void:
	if _result.visible:
		if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			_leave_result()
		return
	if event.is_action_pressed(&"ui_cancel"):
		_handle_escape()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return
	if _pause_menu.visible:
		if _nav.handle_event(self, event):
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()


func _handle_escape() -> void:
	if _pause_confirm.visible:
		_hide_pause_confirm()
		return
	if _pause_settings.visible:
		_close_pause_settings()
		return
	if _pause_menu.visible:
		_resume_race()
		return
	_open_pause_menu()


func _open_pause_menu() -> void:
	_reset_pause_pages()
	_pause_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_sync_pause_nav()


func _resume_race() -> void:
	get_tree().paused = false
	_reset_pause_pages()
	_pause_menu.visible = false
	_nav.clear()


func _reset_pause_pages() -> void:
	_pause_main.visible = true
	_pause_settings.visible = false
	_pause_confirm.visible = false


func _sync_pause_nav() -> void:
	if _pause_confirm.visible:
		_nav.setup([
			$RaceUI/PauseMenu/ConfirmPanel/Margin/VBox/CancelBtn,
			$RaceUI/PauseMenu/ConfirmPanel/Margin/VBox/LeaveBtn,
		])
	elif _pause_settings.visible:
		_nav.setup([
			_pause_fullscreen,
			_pause_master,
			_pause_music,
			_pause_arcade,
			$RaceUI/PauseMenu/SettingsPanel/Margin/VBox/BackBtn,
		])
	elif _pause_menu.visible:
		_nav.setup([
			$RaceUI/PauseMenu/Panel/Margin/VBox/ResumeBtn,
			$RaceUI/PauseMenu/Panel/Margin/VBox/SettingsBtn,
			$RaceUI/PauseMenu/Panel/Margin/VBox/ExitBtn,
		])
	else:
		_nav.clear()


func _on_pause_resume_pressed() -> void:
	_resume_race()


func _on_pause_settings_pressed() -> void:
	_pause_main.visible = false
	_pause_confirm.visible = false
	_pause_settings.visible = true
	_refresh_pause_settings()
	_sync_pause_nav()


func _on_pause_settings_back_pressed() -> void:
	_close_pause_settings()


func _close_pause_settings() -> void:
	GameState.save_settings()
	_pause_settings.visible = false
	_pause_main.visible = true
	_sync_pause_nav()


func _refresh_pause_settings() -> void:
	_pause_fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	_pause_master.set_value_no_signal(db_to_linear(AudioServer.get_bus_volume_db(0)))
	_pause_music.set_pressed_no_signal(GameState.music_enabled)
	_pause_arcade.set_pressed_no_signal(GameState.arcade_drive)


func _on_pause_fullscreen_toggled(pressed: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _on_pause_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))


func _on_pause_music_toggled(pressed: bool) -> void:
	GameState.set_music_enabled(pressed)


func _on_pause_arcade_toggled(pressed: bool) -> void:
	GameState.set_arcade_drive(pressed)


func _on_pause_exit_pressed() -> void:
	_pause_main.visible = false
	_pause_settings.visible = false
	_pause_confirm.visible = true
	_sync_pause_nav()


func _on_pause_confirm_cancel_pressed() -> void:
	_hide_pause_confirm()


func _hide_pause_confirm() -> void:
	_pause_confirm.visible = false
	_pause_main.visible = true
	_sync_pause_nav()


func _on_pause_confirm_leave_pressed() -> void:
	_leave_race()


func _leave_race() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)
