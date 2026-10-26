extends Node3D

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _EngineSound := preload("res://scripts/engine_sound.gd")
const _TunePreview := preload("res://scripts/engine_tune_preview.gd")

@onready var _car_pivot: Node3D = $CarPivot
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera_pitch: Node3D = $CameraPivot/Pitch
@onready var _camera: Camera3D = $CameraPivot/Pitch/Camera3D

@onready var _clock_menu: Control = $GarageUI/ClockMenu
@onready var _clock_main: Control = $GarageUI/ClockMenu/Panel
@onready var _clock_settings: Control = $GarageUI/ClockMenu/SettingsPanel
@onready var _clock_fullscreen: CheckBox = $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/FullscreenCheck
@onready var _clock_master: HSlider = $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/MasterSlider
@onready var _clock_music: CheckBox = $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/MusicCheck
@onready var _clock_arcade: CheckBox = $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/ArcadeCheck
@onready var _stats_panel: Control = $GarageUI/StatsPanel
@onready var _spray_menu: Control = $GarageUI/ColorPickerMenu
@onready var _spray_color_picker: ColorPicker = $GarageUI/ColorPickerMenu/Panel/Margin/VBox/ColorPicker
@onready var _calendar: StaticBody3D = $InteractCalendar
@onready var _calendar_hint: Label = $GarageUI/CalendarHint
@onready var _hud_top: Control = $GarageUI/HudTop
@onready var _hud_car_name: Label = %CarNameLabel
@onready var _hud_cash: Label = %CashLabel
@onready var _lift: StaticBody3D = $InteractLift
@onready var _lift_arm: Node3D = $InteractLift/LiftArm
@onready var _door_left: Node3D = $InteractDoors/DoorLeft
@onready var _door_right: Node3D = $InteractDoors/DoorRight

var _orbiting: bool = false
var _yaw: float = -PI * 0.5
var _pitch: float = 0.35
var _cam_distance: float = 7.0
var _cam_distance_target: float = 7.0

# Camera zoom limits (mouse wheel + pinch).
const CAM_DISTANCE_DEFAULT := 7.0
const CAM_DISTANCE_MIN := 2.5
const CAM_DISTANCE_MAX := 20.0
const ZOOM_STEP := 0.75
const PINCH_SENSITIVITY := 1.5
# How quickly we interpolate camera distance (higher = snappier).
const ZOOM_SMOOTH_SPEED := 12.0

var _stats_label: Label
var _parts_board: Control
var _parts_title: Label
var _parts_list: VBoxContainer
var _parts_status: Label
var _parts_show_spares: bool = false
var _parts_show_wheels: bool = false
var _lift_home: Transform3D
var _lift_arm_home: Vector3
var _wheel_job: bool = false
var _departing: bool = false
var _calendar_home: Transform3D
var _calendar_blend: float = 0.0
var _calendar_inspecting: bool = false
var _calendar_tween: Tween
var _nav = _MenuNav.new()
var _car_list: Control
var _car_list_rows: VBoxContainer
var _car_list_count: Label
var _fuel_panel: Control
var _fuel_status: Label
var _fuel_note: Label
var _fuel_fill_btn: Button
var _fuel_close_btn: Button
var _tune_panel: Control
var _tune_title: Label
var _tune_engine: Label
var _tune_gauge: Control
var _tune_up: Button
var _tune_down: Button
var _tune_close: Button
var _tune_preview: Control
var _tune_sound: AudioStreamPlayer
var _hood: StaticBody3D
var _hood_shape: BoxShape3D
var _loss_root: Control
var _loss_panel: PanelContainer
var _loss_tail: Node2D

const _MONTHS := [
	"", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]
const _WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const _DAYS_IN_MONTH := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const _WHEEL_NODES: Array[String] = [
	"WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight",
]
const _LIFT_HEIGHT := 0.42
const _WHEEL_SIDE_M := 2.6
const _WHEEL_OUT_Z := -5.4
const _T_JACK := 1.8
const _T_LIFT := 1.5
const _T_DROP := 0.9
const _T_ROLL_SIDE := 1.6
const _T_ROLL_LONG := 2.2
const _T_RISE := 0.85
const _T_PAUSE := 0.28
const _T_DOOR_OPEN := 1.25
const _DOOR_SWING := 1.92
const _T_EXIT_DRIVE := 2.7
const _EXIT_DISTANCE := 10.4
const _EXIT_WHEEL_R := 0.27
const _T_EXIT_FADE := 0.5

func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	_stats_label = _stats_panel.get_node("Panel/Margin/VBox/StatsText") as Label
	_reset_clock_menu_page()
	_clock_menu.visible = false
	_stats_panel.visible = false
	_spray_menu.visible = false
	_build_parts_board()
	$InteractClock.set_meta(&"garage_interact", &"clock")
	$InteractDesk/InteractChart.set_meta(&"garage_interact", &"chart")
	$InteractDesk/ShelfOther/InteractFolder.set_meta(&"garage_interact", &"spares")
	$InteractDesk/InteractNewspaper.set_meta(&"garage_interact", &"newspaper")
	$InteractDesk/Shelf/Radio.set_meta(&"garage_interact", &"radio")
	$InteractDoors.set_meta(&"garage_interact", &"doors")
	$InteractSprayPistol.set_meta(&"garage_interact", &"spray")
	$InteractFuelCan.set_meta(&"garage_interact", &"fuel")
	_build_fuel_panel()
	_build_tune_panel()
	_build_hood_target()
	_lift.set_meta(&"garage_interact", &"lift")
	_lift_home = _lift.global_transform
	_lift_arm_home = _lift_arm.position
	GameState.update_music()
	_calendar.set_meta(&"garage_interact", &"calendar")
	_calendar_home = _calendar.global_transform
	_build_calendar_page()
	_calendar_hint.visible = false
	_hud_top.gui_input.connect(_on_hud_car_stripe_input)
	_build_car_list()
	_refresh_hud()
	if GameState.has_active_car():
		_car_pivot.visible = true
		if _car_pivot.has_method(&"set_car_body_color"):
			_car_pivot.set_car_body_color(GameState.car_color)
	else:
		_car_pivot.visible = false
	_build_loss_bubble()
	if GameState.is_ruined():
		_loss_root.visible = true
		_place_loss_bubble()
	_cam_distance_target = _cam_distance
	_update_camera_transform()

	# Defer so MeshInstance scripts (like the STL loader) have a chance
	# to populate `MeshInstance3D.mesh` before we inspect it.
	call_deferred(&"_debug_car_mesh")
	# Also align wheels to the floor after meshes are ready.
	call_deferred(&"_align_wheels_to_floor")
	call_deferred(&"_place_hood_target")

	# If the CarBody emits a signal when its STL finishes loading, connect to it
	var car_body := _car_pivot.get_node_or_null("CarBody") as MeshInstance3D
	if car_body != null and car_body.has_signal("stl_loaded"):
		car_body.connect("stl_loaded", Callable(self, "_on_carbody_stl_loaded"))


func _on_carbody_stl_loaded(_mesh: Variant) -> void:
	# When the CarBody's mesh is ready, re-align wheels to the floor.
	_align_wheels_to_floor()
	_place_hood_target()


func _align_wheels_to_floor() -> void:
	var floor_mesh_instance := $Floor/MeshInstance3D as MeshInstance3D
	if _car_pivot.has_method(&"align_wheels_to_floor"):
		_car_pivot.align_wheels_to_floor(floor_mesh_instance)


func _build_loss_bubble() -> void:
	_loss_root = Control.new()
	_loss_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loss_root.visible = false
	_loss_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_loss_root.gui_input.connect(_on_loss_input)
	$GarageUI.add_child(_loss_root)
	_loss_panel = PanelContainer.new()
	_loss_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_loss_panel.gui_input.connect(_on_loss_input)
	_loss_panel.add_theme_stylebox_override(&"panel", _loss_bubble_style())
	_loss_root.add_child(_loss_panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 16)
	margin.add_theme_constant_override(&"margin_right", 16)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_bottom", 12)
	_loss_panel.add_child(margin)
	var line := Label.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.text = "You don't have neither car nor money. You lose!"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.custom_minimum_size = Vector2(320, 56)
	line.add_theme_font_size_override(&"font_size", 22)
	line.add_theme_color_override(&"font_color", Color(0.08, 0.06, 0.05))
	margin.add_child(line)
	_loss_tail = Node2D.new()
	_loss_panel.add_child(_loss_tail)
	var outline := Line2D.new()
	outline.width = 5.0
	outline.default_color = Color(0.08, 0.06, 0.05)
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	outline.points = PackedVector2Array([Vector2(-18, 0), Vector2(0, 24), Vector2(18, 0)])
	_loss_tail.add_child(outline)
	var fill := Polygon2D.new()
	fill.color = Color(0.98, 0.97, 0.93)
	fill.polygon = PackedVector2Array([Vector2(-14, 2), Vector2(0, 18), Vector2(14, 2)])
	_loss_tail.add_child(fill)


func _loss_bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.97, 0.93)
	style.border_color = Color(0.08, 0.06, 0.05)
	style.set_border_width_all(4)
	style.set_corner_radius_all(18)
	return style


func _on_loss_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	_leave_after_loss()
	get_viewport().set_input_as_handled()


func _dismiss_loss_bubble() -> void:
	if _loss_root != null:
		_loss_root.visible = false


func _leave_after_loss() -> void:
	GameState.current_scene_path = GameState.SCENE_MAIN_MENU
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)


func _place_loss_bubble() -> void:
	if _loss_root == null or not _loss_root.visible:
		return
	var spot := _car_pivot.global_position + Vector3(0.0, 1.35, 0.0)
	var screen := Vector2(get_viewport().get_visible_rect().size.x * 0.5, 180.0)
	if not _camera.is_position_behind(spot):
		screen = _camera.unproject_position(spot)
	var bubble_size := _loss_panel.get_combined_minimum_size()
	var vp := get_viewport().get_visible_rect().size
	var tail_h := 26.0
	var x := clampf(screen.x - bubble_size.x * 0.5, 16.0, maxf(16.0, vp.x - bubble_size.x - 16.0))
	var y := clampf(screen.y - bubble_size.y - tail_h - 8.0, 16.0, maxf(16.0, vp.y - bubble_size.y - tail_h - 16.0))
	_loss_panel.position = Vector2(x, y)
	_loss_panel.size = bubble_size
	var tail_x := clampf(screen.x - x, 28.0, maxf(28.0, bubble_size.x - 28.0))
	_loss_tail.position = Vector2(tail_x, bubble_size.y - 4.0)

func _process(_delta: float) -> void:
	if not _departing:
		_camera_pivot.global_position = _car_pivot.global_position

	# Smooth zoom: interpolate distance toward the latest target.
	# (We don't call `_update_camera_transform()` from input handlers so
	# mouse wheel / pinch stays smooth.)
	var delta := _delta
	if absf(_cam_distance - _cam_distance_target) > 0.0001:
		# Exponential smoothing: t = 1 - exp(-k*dt)
		var t := 1.0 - exp(-ZOOM_SMOOTH_SPEED * delta)
		_cam_distance = lerpf(_cam_distance, _cam_distance_target, t)
		_update_camera_transform()
	_update_calendar_transform()
	_place_loss_bubble()


func _debug_car_mesh() -> void:
	# Deterministic debug to see whether the imported car mesh is loaded and
	# where its bounds end up (world vs camera framing issues).
	var car_body := _car_pivot.get_node_or_null("CarBody") as MeshInstance3D
	if car_body == null:
		print("[DEBUG CAR][garage] Missing node `CarPivot/CarBody`.")
		return

	var mesh := car_body.mesh
	var surfaces := 0
	var resource_path := "<null>"
	if mesh != null:
		resource_path = mesh.resource_path
		if mesh.has_method(&"get_surface_count"):
			surfaces = mesh.get_surface_count()

	var aabb := car_body.get_aabb() # local-space bounds
	var center_local := aabb.position + aabb.size * 0.5
	var center_world := car_body.global_transform * center_local

	# Also explicitly try loading the STL resource path.
	# This distinguishes "scene reference failed" vs "import/load failed".
	var stl_path := "res://assets/vette-c1.stl"
	var exists_any := ResourceLoader.exists(stl_path)
	var exists_array_mesh := ResourceLoader.exists(stl_path, &"ArrayMesh")
	var loaded_any := ResourceLoader.load(stl_path)
	var loaded_any_type := "<null>"
	if loaded_any != null:
		loaded_any_type = loaded_any.get_class()

	var exists_mesh := ResourceLoader.exists(stl_path, &"Mesh")
	var loaded_mesh := ResourceLoader.load(stl_path, &"Mesh")
	var loaded_mesh_type := "<null>"
	if loaded_mesh != null:
		loaded_mesh_type = loaded_mesh.get_class()

	var abs_path := ProjectSettings.globalize_path(stl_path)
	var abs_exists := FileAccess.file_exists(abs_path)

	print("[DEBUG CAR][garage] CarBody visible=", car_body.visible, " mesh_null=", mesh == null)
	print("[DEBUG CAR][garage] mesh_resource=", resource_path, " surface_count=", surfaces)
	print("[DEBUG CAR][garage] local_aabb_size=", aabb.size, " local_aabb_pos=", aabb.position)
	print("[DEBUG CAR][garage] global_position=", car_body.global_position, " scale=", car_body.scale)
	print("[DEBUG CAR][garage] center_world=", center_world)
	print("[DEBUG CAR][garage] stl_path_exists(any)=", exists_any, " stl_path_exists(ArrayMesh)=", exists_array_mesh, " loaded_any=", loaded_any != null, " loaded_any_type=", loaded_any_type)
	print("[DEBUG CAR][garage] stl_path_exists(Mesh)=", exists_mesh, " loaded_mesh=", loaded_mesh != null, " loaded_mesh_type=", loaded_mesh_type)
	print("[DEBUG CAR][garage] stl_abs_path=", abs_path, " abs_exists=", abs_exists)


func _unhandled_input(event: InputEvent) -> void:
	if _departing:
		get_viewport().set_input_as_handled()
		return
	if _loss_root != null and _loss_root.visible and event.is_action_pressed(&"ui_cancel"):
		_dismiss_loss_bubble()
		get_viewport().set_input_as_handled()
		return
	if _wheel_job:
		_handle_camera_only(event)
		return
	if _clock_menu.visible and event.is_action_pressed(&"ui_cancel"):
		if _clock_settings.visible:
			_close_clock_settings()
		else:
			_clock_menu.visible = false
			_sync_menu_nav()
		get_viewport().set_input_as_handled()
		return
	if _stats_panel.visible and event.is_action_pressed(&"ui_cancel"):
		_stats_panel.visible = false
		_sync_menu_nav()
		get_viewport().set_input_as_handled()
		return
	if _spray_menu.visible and event.is_action_pressed(&"ui_cancel"):
		_spray_menu.visible = false
		_sync_menu_nav()
		get_viewport().set_input_as_handled()
		return
	if _parts_board != null and _parts_board.visible and event.is_action_pressed(&"ui_cancel"):
		_hide_parts_board()
		get_viewport().set_input_as_handled()
		return
	if _car_list != null and _car_list.visible and event.is_action_pressed(&"ui_cancel"):
		_hide_car_list()
		get_viewport().set_input_as_handled()
		return
	if _fuel_panel != null and _fuel_panel.visible and event.is_action_pressed(&"ui_cancel"):
		_hide_fuel_panel()
		get_viewport().set_input_as_handled()
		return
	if _tune_panel != null and _tune_panel.visible and event.is_action_pressed(&"ui_cancel"):
		_hide_tune_panel()
		get_viewport().set_input_as_handled()
		return
	if _calendar_inspecting and event.is_action_pressed(&"ui_cancel"):
		_hang_calendar()
		get_viewport().set_input_as_handled()
		return

	if _nav.handle_event(self, event):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if _try_garage_shortcut(event):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if _is_reset_zoom_shortcut(event):
		_cam_distance_target = CAM_DISTANCE_DEFAULT
		get_viewport().set_input_as_handled()
		return

	# Pinch gesture zoom (touch / trackpad).
	if event is InputEventMagnifyGesture:
		if _clock_menu.visible or _stats_panel.visible or _spray_menu.visible:
			return
		var mg := event as InputEventMagnifyGesture
		# `factor` grows when fingers spread (zoom in).
		var denom := 1.0 + (mg.factor * PINCH_SENSITIVITY)
		if absf(denom) < 0.0001:
			return
		_cam_distance_target = clampf(_cam_distance_target / denom, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			get_viewport().set_input_as_handled()
			return
		# Mouse wheel: use `factor` when available so trackpads behave better.
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor_any: Variant = mb.get(&"factor") # May be missing depending on platform/version.
			var raw_factor: float = 1.0
			if typeof(factor_any) == TYPE_FLOAT or typeof(factor_any) == TYPE_INT:
				raw_factor = float(factor_any)
			var factor := absf(raw_factor)
			if factor < 0.0001:
				factor = 1.0

			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			# Some platforms encode scroll direction in `factor`; if the sign disagrees,
			# flip the direction so zoom in/out is consistent.
			if raw_factor < 0.0:
				dir *= -1.0
			_cam_distance_target = clampf(
				_cam_distance_target + dir * ZOOM_STEP * factor,
				CAM_DISTANCE_MIN,
				CAM_DISTANCE_MAX
			)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _clock_menu.visible or _stats_panel.visible or _spray_menu.visible:
				return
			if _tune_panel != null and _tune_panel.visible:
				return
			if _car_list != null and _car_list.visible:
				_hide_car_list()
				get_viewport().set_input_as_handled()
				return
			if _calendar_inspecting:
				_hang_calendar()
				get_viewport().set_input_as_handled()
				return
			_try_interact(mb.position)

	if event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch - mm.relative.y * 0.005, 0.1, 1.2)
		_update_camera_transform()
		get_viewport().set_input_as_handled()


func _handle_camera_only(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		var denom := 1.0 + (mg.factor * PINCH_SENSITIVITY)
		if absf(denom) < 0.0001:
			return
		_cam_distance_target = clampf(_cam_distance_target / denom, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor_any: Variant = mb.get(&"factor")
			var raw_factor: float = 1.0
			if typeof(factor_any) == TYPE_FLOAT or typeof(factor_any) == TYPE_INT:
				raw_factor = float(factor_any)
			var factor := absf(raw_factor)
			if factor < 0.0001:
				factor = 1.0
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if raw_factor < 0.0:
				dir *= -1.0
			_cam_distance_target = clampf(
				_cam_distance_target + dir * ZOOM_STEP * factor,
				CAM_DISTANCE_MIN,
				CAM_DISTANCE_MAX
			)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch - mm.relative.y * 0.005, 0.1, 1.2)
		_update_camera_transform()
		get_viewport().set_input_as_handled()


func _try_garage_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return false
	if _gui_has_text_focus():
		return false
	match key.keycode:
		KEY_N:
			_handle_interact(&"newspaper")
		KEY_M:
			GameState.toggle_music()
			if _clock_settings.visible:
				_clock_music.set_pressed_no_signal(GameState.music_enabled)
		KEY_P:
			if _spray_menu.visible:
				_spray_menu.visible = false
			else:
				_show_spray_picker()
		KEY_D:
			_handle_interact(&"doors")
		KEY_X:
			if _calendar_inspecting:
				_hang_calendar()
			else:
				_bring_calendar_forward()
		KEY_Q:
			if _clock_menu.visible:
				if _clock_settings.visible:
					_close_clock_settings()
				else:
					_clock_menu.visible = false
			else:
				_hide_garage_overlays()
				_clock_menu.visible = true
		KEY_I:
			if _stats_panel.visible:
				_stats_panel.visible = false
			else:
				_show_stats()
		KEY_L:
			if _parts_board != null and _parts_board.visible and _parts_show_wheels:
				_hide_parts_board()
			else:
				_show_wheel_board()
		_:
			return false
	_sync_menu_nav()
	return true


func _gui_has_text_focus() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _hide_garage_overlays() -> void:
	_reset_clock_menu_page()
	_clock_menu.visible = false
	_stats_panel.visible = false
	_spray_menu.visible = false
	if _parts_board != null:
		_parts_board.visible = false
	if _car_list != null:
		_car_list.visible = false
	if _fuel_panel != null:
		_fuel_panel.visible = false
	_hide_tune_panel()
	_sync_menu_nav()


func _reset_clock_menu_page() -> void:
	_clock_main.visible = true
	_clock_settings.visible = false


func _sync_menu_nav() -> void:
	if _clock_menu.visible and _clock_settings.visible:
		_nav.setup([
			_clock_fullscreen,
			_clock_master,
			_clock_music,
			_clock_arcade,
			$GarageUI/ClockMenu/SettingsPanel/Margin/VBox/BackBtn,
		])
	elif _clock_menu.visible:
		_nav.setup([
			$GarageUI/ClockMenu/Panel/Margin/VBox/SaveBtn,
			$GarageUI/ClockMenu/Panel/Margin/VBox/LoadBtn,
			$GarageUI/ClockMenu/Panel/Margin/VBox/SettingsBtn,
			$GarageUI/ClockMenu/Panel/Margin/VBox/QuitBtn,
			$GarageUI/ClockMenu/Panel/Margin/VBox/CloseBtn,
		])
	elif _stats_panel.visible:
		_nav.setup([$GarageUI/StatsPanel/Panel/Margin/VBox/StatsClose])
	elif _spray_menu.visible:
		_nav.setup([
			$GarageUI/ColorPickerMenu/Panel/Margin/VBox/HBox/ConfirmBtn,
			$GarageUI/ColorPickerMenu/Panel/Margin/VBox/HBox/CancelBtn,
		])
	elif _tune_panel != null and _tune_panel.visible:
		_nav.setup([_tune_up, _tune_down, _tune_close])
	elif _fuel_panel != null and _fuel_panel.visible:
		_nav.setup([_fuel_fill_btn, _fuel_close_btn])
	elif _parts_board != null and _parts_board.visible:
		_nav.setup(_nav.collect_buttons(_parts_board))
	elif _car_list != null and _car_list.visible:
		_nav.setup(_nav.collect_buttons(_car_list))
	else:
		_nav.clear()


func _is_reset_zoom_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.keycode != KEY_0 and key.keycode != KEY_KP_0:
		return false
	if OS.get_name() == "macOS":
		return key.meta_pressed and not key.ctrl_pressed
	return key.ctrl_pressed and not key.meta_pressed


func _update_camera_transform() -> void:
	_camera_pivot.rotation = Vector3.ZERO
	_camera_pivot.rotate_y(_yaw)
	_camera_pitch.rotation = Vector3.ZERO
	_camera_pitch.rotate_object_local(Vector3.RIGHT, -_pitch)
	_camera.position = Vector3(0.0, 0.6, _cam_distance)
	_camera.look_at(_camera_pivot.global_position + Vector3(0.0, 0.4, 0.0), Vector3.UP)


func _try_interact(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider == null:
		return
	var node := collider as Node
	if node == null:
		return
	# Godot may return the collider node itself (e.g. `CollisionShape3D`) instead of its parent
	# `StaticBody3D`. Walk up the tree until we find the interaction metadata.
	while node != null:
		if node.has_meta(&"garage_interact"):
			_handle_interact(node.get_meta(&"garage_interact"))
			return
		node = node.get_parent()


func _raycast(screen_pos: Vector2) -> Dictionary:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _handle_interact(kind: Variant) -> void:
	if _wheel_job or _departing:
		return
	if _bay_needs_car(kind) and not GameState.has_active_car():
		return
	match kind:
		&"clock":
			_reset_clock_menu_page()
			_clock_menu.visible = true
			_sync_menu_nav()
		&"chart":
			_show_parts_board()
		&"spares":
			_show_spares_board()
		&"newspaper":
			get_tree().change_scene_to_file(GameState.SCENE_NEWSPAPER)
		&"radio":
			GameState.toggle_music()
			if _clock_settings.visible:
				_clock_music.set_pressed_no_signal(GameState.music_enabled)
		&"doors":
			_start_drive_out()
		&"spray":
			_show_spray_picker()
		&"fuel":
			_show_fuel_panel()
		&"hood":
			_show_tune_panel()
		&"calendar":
			_bring_calendar_forward()
		&"lift":
			_show_wheel_board()


func _bay_needs_car(kind: Variant) -> bool:
	match kind:
		&"doors", &"chart", &"spares", &"spray", &"fuel", &"hood", &"lift":
			return true
	return false


func _start_drive_out() -> void:
	if _departing or _wheel_job or not GameState.has_active_car():
		return
	if _door_left == null or _door_right == null:
		get_tree().change_scene_to_file(GameState.SCENE_DRIVE_IN)
		return
	_departing = true
	_orbiting = false
	_snap_calendar_home()
	_hide_garage_overlays()
	$GarageUI.visible = false
	var door_hit := $InteractDoors/CollisionShape3D as CollisionShape3D
	if door_hit != null:
		door_hit.disabled = true
	await _play_drive_out()
	if not is_instance_valid(self):
		return
	get_tree().change_scene_to_file(GameState.SCENE_DRIVE_IN)


func _snap_calendar_home() -> void:
	_calendar_inspecting = false
	_calendar_hint.visible = false
	_calendar_blend = 0.0
	if _calendar_tween != null:
		_calendar_tween.kill()
	_calendar.global_transform = _calendar_home


func _play_drive_out() -> void:
	var doors := create_tween()
	doors.set_parallel(true)
	doors.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	doors.tween_property(_door_left, "rotation:y", _DOOR_SWING, _T_DOOR_OPEN)
	doors.tween_property(_door_right, "rotation:y", -_DOOR_SWING, _T_DOOR_OPEN)
	await doors.finished
	if not is_instance_valid(self):
		return
	await _pause(0.18)
	if not is_instance_valid(self):
		return
	await _reverse_car_out()


func _reverse_car_out() -> void:
	var start := _car_pivot.position
	var end := start + Vector3(0.0, 0.0, -_EXIT_DISTANCE)
	var wheels: Array[Node3D] = []
	var bases: Array[Basis] = []
	for wname in _WHEEL_NODES:
		var wheel := _car_pivot.get_node_or_null(wname) as Node3D
		if wheel == null or not wheel.visible:
			continue
		wheels.append(wheel)
		bases.append(wheel.basis)
	var travel := start.distance_to(end)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(_apply_drive_out.bind(start, end, wheels, bases, travel), 0.0, 1.0, _T_EXIT_DRIVE)
	var shade := _black_fade_rect()
	var fade := create_tween()
	fade.tween_interval(maxf(_T_EXIT_DRIVE - _T_EXIT_FADE, 0.0))
	fade.tween_property(shade, "color:a", 1.0, _T_EXIT_FADE)
	await tw.finished
	if is_instance_valid(shade):
		shade.color = Color(0.0, 0.0, 0.0, 1.0)


func _apply_drive_out(t: float, start: Vector3, end: Vector3, wheels: Array[Node3D], bases: Array[Basis], travel: float) -> void:
	_car_pivot.position = start.lerp(end, t)
	# Local +Y is the axle. Positive spin rolls the tire for travel toward -Z.
	var spin := (travel * t) / _EXIT_WHEEL_R
	for i in wheels.size():
		var wheel := wheels[i]
		if not is_instance_valid(wheel):
			continue
		wheel.basis = bases[i] * Basis(Vector3.UP, spin)


func _black_fade_rect() -> ColorRect:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	return shade


func _show_spray_picker() -> void:
	# Hide other garage overlays so clicks go to the picker.
	_clock_menu.visible = false
	_stats_panel.visible = false
	if _car_list != null:
		_car_list.visible = false
	if _fuel_panel != null:
		_fuel_panel.visible = false
	_spray_color_picker.color = GameState.car_color
	_spray_menu.visible = true
	_sync_menu_nav()


func _on_spray_confirm_pressed() -> void:
	GameState.set_car_color(_spray_color_picker.color)
	# Update the preview immediately.
	if _car_pivot.has_method(&"set_car_body_color"):
		_car_pivot.set_car_body_color(GameState.car_color)
	_spray_menu.visible = false
	_sync_menu_nav()


func _on_spray_cancel_pressed() -> void:
	_spray_menu.visible = false
	_sync_menu_nav()


func _build_parts_board() -> void:
	var root := Control.new()
	root.name = "PartsBoard"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 520)
	panel.offset_left = -210
	panel.offset_top = -260
	panel.offset_right = 210
	panel.offset_bottom = 260
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_parts_title = Label.new()
	_parts_title.text = "On the car"
	box.add_child(_parts_title)
	_parts_status = Label.new()
	_parts_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_parts_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	box.add_child(scroll)
	_parts_list = VBoxContainer.new()
	_parts_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_parts_list)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_hide_parts_board)
	box.add_child(close)
	$GarageUI.add_child(root)
	_parts_board = root


func _show_parts_board() -> void:
	_parts_show_spares = false
	_parts_show_wheels = false
	_clock_menu.visible = false
	_spray_menu.visible = false
	_stats_panel.visible = false
	if _car_list != null:
		_car_list.visible = false
	if _fuel_panel != null:
		_fuel_panel.visible = false
	_rebuild_parts_board()
	_parts_board.visible = true
	_sync_menu_nav()


func _show_spares_board() -> void:
	_parts_show_spares = true
	_parts_show_wheels = false
	_clock_menu.visible = false
	_spray_menu.visible = false
	_stats_panel.visible = false
	if _car_list != null:
		_car_list.visible = false
	if _fuel_panel != null:
		_fuel_panel.visible = false
	_rebuild_parts_board()
	_parts_board.visible = true
	_sync_menu_nav()


func _show_wheel_board() -> void:
	if _wheel_job:
		return
	_parts_show_spares = false
	_parts_show_wheels = true
	_clock_menu.visible = false
	_spray_menu.visible = false
	_stats_panel.visible = false
	if _car_list != null:
		_car_list.visible = false
	if _fuel_panel != null:
		_fuel_panel.visible = false
	_rebuild_parts_board()
	_parts_board.visible = true
	_sync_menu_nav()


func _hide_parts_board() -> void:
	_parts_board.visible = false
	_sync_menu_nav()


func _rebuild_parts_board() -> void:
	for child in _parts_list.get_children():
		child.queue_free()
	if _parts_show_wheels:
		_rebuild_wheels_list()
		return
	if _parts_show_spares:
		_rebuild_spares_list()
		return
	_parts_title.text = "On the car"
	var engine := GameState.get_equipped_engine()
	var box: Dictionary = GameState.get_equipped_gearbox()
	var wheel := GameState.get_equipped_wheel()
	_parts_status.text = "%s\n%.0f hp · %.0f km/h" % [
		GameState.car_name,
		GameState.engine_power_hp,
		GameState.get_effective_vmax_kmh(),
	]
	if not engine.is_empty():
		_parts_list.add_child(_mounted_line("Engine", _parts_row_text(engine, "engine")))
	if not box.is_empty():
		_parts_list.add_child(_mounted_line("Transmission", _parts_row_text(box, "transmission")))
	if not wheel.is_empty():
		_parts_list.add_child(_mounted_line("Wheels", _parts_row_text(wheel, "wheels")))
	for part_id in GameState.equipped_part_ids:
		var part: Dictionary = GameState.listing_by_id(GameState.PARTS, part_id)
		if part.is_empty():
			continue
		_parts_list.add_child(_mounted_line("Bolt-on", _parts_row_text(part, "part")))


func _rebuild_wheels_list() -> void:
	_parts_title.text = "Wheels"
	_parts_status.text = "Pick a set. The jack will change them one corner at a time."
	var count := 0
	for wheel in GameState.WHEELS:
		var wheel_id := str(wheel.get("id", ""))
		if not GameState.owns_wheel(wheel_id):
			continue
		_parts_list.add_child(_parts_row(wheel, "wheels", GameState.equipped_wheel_id))
		count += 1
	if count == 0:
		_parts_status.text = "No wheels on the shelf. Buy a set in the newspaper."
	elif count == 1 and GameState.owns_wheel(GameState.equipped_wheel_id):
		_parts_status.text = "Only the wheels on the car are here. Buy another set in the newspaper."


func _rebuild_spares_list() -> void:
	_parts_title.text = "Spare parts"
	_parts_status.text = "Bought, not on the car."
	var count := 0
	for engine in GameState.ENGINES:
		var engine_id := str(engine.get("id", ""))
		if GameState.owns_engine(engine_id) and engine_id != GameState.equipped_engine_id:
			_parts_list.add_child(_parts_row(engine, "engine", GameState.equipped_engine_id))
			count += 1
	for box in GameState.GEARBOXES:
		var box_id := str(box.get("id", ""))
		if GameState.owns_gearbox(box_id) and box_id != GameState.equipped_gearbox_id:
			_parts_list.add_child(_parts_row(box, "transmission", GameState.equipped_gearbox_id))
			count += 1
	for wheel in GameState.WHEELS:
		var wheel_id := str(wheel.get("id", ""))
		if GameState.owns_wheel(wheel_id) and wheel_id != GameState.equipped_wheel_id:
			_parts_list.add_child(_parts_row(wheel, "wheels", GameState.equipped_wheel_id))
			count += 1
	for part in GameState.PARTS:
		var part_id := str(part.get("id", ""))
		if GameState.owns_part(part_id) and not GameState.is_part_equipped(part_id):
			_parts_list.add_child(_parts_row(part, "part", ""))
			count += 1
	if count == 0:
		_parts_status.text = "The folder is empty. Parts you buy land here until you fit them."


func _mounted_line(slot: String, detail: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s — %s" % [slot, detail]
	return label


func _parts_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _parts_row(item: Dictionary, kind: String, equipped_id: String) -> HBoxContainer:
	var part_id := str(item.get("id", ""))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = _parts_row_text(item, kind)
	row.add_child(label)
	var btn := Button.new()
	var owned := _parts_owned(kind, part_id)
	var fitted := part_id == equipped_id or (kind == "part" and GameState.is_part_equipped(part_id))
	if fitted:
		btn.text = "On the car"
		btn.disabled = true
	elif owned:
		btn.text = "Fit"
		btn.pressed.connect(_on_fit_part.bind(kind, part_id))
	else:
		btn.text = "Buy $%d" % int(item.get("price", 0))
		btn.disabled = GameState.money < int(item.get("price", 0))
		btn.pressed.connect(_on_fit_part.bind(kind, part_id))
	row.add_child(btn)
	return row


func _parts_row_text(item: Dictionary, kind: String) -> String:
	var name := str(item.get("name", "Part"))
	if kind == "engine":
		return "%s  %.0f hp" % [name, float(item.get("hp", 0.0))]
	if kind == "transmission":
		var kind_name := "auto" if bool(item.get("automatic", false)) else "manual"
		return "%s  %s" % [name, kind_name]
	if kind == "part":
		return "%s  +%d hp" % [name, int(item.get("hp", 0))]
	return name


func _parts_owned(kind: String, part_id: String) -> bool:
	match kind:
		"engine":
			return GameState.owns_engine(part_id)
		"transmission":
			return GameState.owns_gearbox(part_id)
		"wheels":
			return GameState.owns_wheel(part_id)
		"part":
			return GameState.owns_part(part_id)
	return false


func _on_fit_part(kind: String, part_id: String) -> void:
	var err := ""
	match kind:
		"engine":
			err = GameState.buy_or_equip_engine(part_id)
		"transmission":
			err = GameState.buy_or_equip_gearbox(part_id)
		"wheels":
			if GameState.owns_wheel(part_id) and part_id != GameState.equipped_wheel_id:
				_hide_parts_board()
				_start_wheel_change(part_id)
				return
			err = GameState.buy_or_equip_wheel(part_id)
		"part":
			err = GameState.equip_part(part_id)
	if not err.is_empty():
		_parts_status.text = err
	_rebuild_parts_board()
	_refresh_hud()
	if _parts_board.visible:
		_sync_menu_nav()


func _refresh_hud() -> void:
	_hud_car_name.text = GameState.car_name
	_hud_cash.text = "Cash: $%d" % GameState.money


func _on_hud_car_stripe_input(event: InputEvent) -> void:
	if _wheel_job or not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_toggle_car_list()
	get_viewport().set_input_as_handled()


func _build_car_list() -> void:
	var root := PanelContainer.new()
	root.name = "CarList"
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.offset_left = -220.0
	root.offset_top = 48.0
	root.offset_right = 220.0
	root.offset_bottom = 48.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.96)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	root.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	root.add_child(box)
	var title := Label.new()
	title.text = "Cars in the garage"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78, 1))
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(400, 40)
	box.add_child(scroll)
	_car_list_rows = VBoxContainer.new()
	_car_list_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_car_list_rows.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_car_list_rows)
	_car_list_count = Label.new()
	_car_list_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_list_count.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78, 1))
	box.add_child(_car_list_count)
	$GarageUI.add_child(root)
	_car_list = root


func _toggle_car_list() -> void:
	if _wheel_job or _car_list == null:
		return
	if _car_list.visible:
		_hide_car_list()
		return
	_hide_garage_overlays()
	_rebuild_car_list()
	_car_list.visible = true
	_sync_menu_nav()


func _hide_car_list() -> void:
	if _car_list == null or not _car_list.visible:
		return
	_car_list.visible = false
	_sync_menu_nav()


func _build_fuel_panel() -> void:
	var root := Control.new()
	root.name = "FuelPanel"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200.0
	panel.offset_top = -90.0
	panel.offset_right = 200.0
	panel.offset_bottom = 90.0
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 16)
	margin.add_theme_constant_override(&"margin_right", 16)
	margin.add_theme_constant_override(&"margin_top", 14)
	margin.add_theme_constant_override(&"margin_bottom", 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Fuel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_fuel_status = Label.new()
	_fuel_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_fuel_status)
	_fuel_note = Label.new()
	_fuel_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fuel_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_fuel_note)
	_fuel_fill_btn = Button.new()
	_fuel_fill_btn.pressed.connect(_on_fuel_fill_pressed)
	box.add_child(_fuel_fill_btn)
	_fuel_close_btn = Button.new()
	_fuel_close_btn.text = "Close"
	_fuel_close_btn.pressed.connect(_hide_fuel_panel)
	box.add_child(_fuel_close_btn)
	$GarageUI.add_child(root)
	_fuel_panel = root


func _show_fuel_panel() -> void:
	if _wheel_job or _fuel_panel == null:
		return
	_hide_garage_overlays()
	_refresh_fuel_panel()
	_fuel_panel.visible = true
	_sync_menu_nav()


func _hide_fuel_panel() -> void:
	if _fuel_panel == null or not _fuel_panel.visible:
		return
	_fuel_panel.visible = false
	_sync_menu_nav()


func _refresh_fuel_panel() -> void:
	_fuel_status.text = "Tank: %.0f / %.0f L" % [GameState.fuel, GameState.DEFAULT_TANK_L]
	var price := GameState.refuel_price()
	if price <= 0:
		_fuel_fill_btn.text = "Tank is full"
		_fuel_fill_btn.disabled = true
		_fuel_note.text = ""
		return
	_fuel_fill_btn.text = "Fill up — $%d" % price
	_fuel_fill_btn.disabled = GameState.money < price
	if GameState.money < price:
		_fuel_note.text = "Not enough cash."
	else:
		_fuel_note.text = ""


func _on_fuel_fill_pressed() -> void:
	var err := GameState.refuel_tank()
	_refresh_fuel_panel()
	if not err.is_empty() and err != "The tank is already full.":
		_fuel_note.text = err
	_refresh_hud()
	if _fuel_panel != null and _fuel_panel.visible:
		_sync_menu_nav()


func _rebuild_car_list() -> void:
	for child in _car_list_rows.get_children():
		_car_list_rows.remove_child(child)
		child.free()
	for car_id in GameState.owned_car_ids:
		var car_label := GameState.car_display_name(car_id)
		var btn := Button.new()
		var current := car_id == GameState.current_car_id
		btn.text = car_label if not current else "%s    ·    in the bay" % car_label
		btn.disabled = current
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not current:
			btn.pressed.connect(_on_car_list_pick.bind(car_id))
		_car_list_rows.add_child(btn)
	_car_list_count.text = "%d of %d" % [GameState.owned_car_ids.size(), GameState.MAX_OWNED_CARS]
	var rows := mini(maxi(GameState.owned_car_ids.size(), 1), 8)
	var scroll := _car_list_rows.get_parent() as Control
	if scroll != null:
		scroll.custom_minimum_size = Vector2(400, rows * 36)
	_car_list.offset_left = -220.0
	_car_list.offset_right = 220.0
	_car_list.offset_top = 48.0
	_car_list.offset_bottom = 48.0 + 88.0 + float(rows * 36)


func _on_car_list_pick(car_id: String) -> void:
	var err := GameState.select_owned_car(car_id)
	if not err.is_empty():
		_hide_car_list()
		return
	_apply_active_car_visual()
	_refresh_hud()
	_hide_car_list()


func _apply_active_car_visual() -> void:
	_car_pivot.visible = GameState.has_active_car()
	if _car_pivot.has_method(&"reload_player_car"):
		_car_pivot.call(&"reload_player_car")
	_align_wheels_to_floor()
	call_deferred(&"_place_hood_target")


func _build_hood_target() -> void:
	_hood = StaticBody3D.new()
	_hood.name = "InteractHood"
	var col := CollisionShape3D.new()
	_hood_shape = BoxShape3D.new()
	_hood_shape.size = Vector3(1.3, 0.28, 1.0)
	col.shape = _hood_shape
	_hood.add_child(col)
	_hood.position = Vector3(0.0, 0.9, 0.85)
	_car_pivot.add_child(_hood)
	_hood.set_meta(&"garage_interact", &"hood")


func _place_hood_target() -> void:
	if _hood == null or _hood_shape == null:
		return
	var body := _car_pivot.get_node_or_null("CarBody") as Node3D
	if body == null:
		return
	var box := _world_mesh_aabb(body)
	if box.size.y < 0.2 or box.size.z < 0.4:
		return
	var origin := box.position
	var size := box.size
	# Front deck, under the roof line: the hood, not the cabin.
	var hood_min := origin + Vector3(size.x * 0.18, size.y * 0.42, size.z * 0.55)
	var hood_size := Vector3(size.x * 0.64, size.y * 0.26, size.z * 0.38)
	_hood.global_position = hood_min + hood_size * 0.5
	_hood_shape.size = hood_size


func _world_mesh_aabb(node: Node) -> AABB:
	var box := AABB()
	var started := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		box = _transformed_aabb(mi.global_transform, mi.mesh.get_aabb())
		started = true
	for child in node.get_children():
		var child_box := _world_mesh_aabb(child)
		if child_box.size == Vector3.ZERO:
			continue
		if not started:
			box = child_box
			started = true
		else:
			box = box.merge(child_box)
	return box


func _transformed_aabb(xf: Transform3D, local: AABB) -> AABB:
	var out := AABB(xf * local.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		out = out.expand(xf * local.get_endpoint(i))
	return out


func _build_tune_panel() -> void:
	var root := Control.new()
	root.name = "TunePanel"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -250.0
	panel.offset_top = -270.0
	panel.offset_right = 250.0
	panel.offset_bottom = 270.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.98)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override(&"panel", style)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	panel.add_child(box)
	_tune_title = Label.new()
	_tune_title.text = "Engine tune"
	_tune_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tune_title.add_theme_font_size_override(&"font_size", 22)
	_tune_title.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78, 1))
	box.add_child(_tune_title)
	_tune_engine = Label.new()
	_tune_engine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tune_engine.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78, 1))
	box.add_child(_tune_engine)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 12)
	_tune_preview = _TunePreview.new()
	_tune_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tune_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_tune_preview)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 6)
	_tune_up = _TuneArrow.new()
	(_tune_up as _TuneArrow).points_up = true
	_tune_up.pressed.connect(_on_tune_step_pressed.bind(1))
	column.add_child(_tune_up)
	_tune_gauge = _TuneGauge.new()
	column.add_child(_tune_gauge)
	_tune_down = _TuneArrow.new()
	(_tune_down as _TuneArrow).points_up = false
	_tune_down.pressed.connect(_on_tune_step_pressed.bind(-1))
	column.add_child(_tune_down)
	var center := CenterContainer.new()
	center.add_child(column)
	row.add_child(center)
	box.add_child(row)
	_tune_close = Button.new()
	_tune_close.text = "Close"
	_tune_close.pressed.connect(_hide_tune_panel)
	box.add_child(_tune_close)
	$GarageUI.add_child(root)
	_tune_panel = root
	_tune_sound = AudioStreamPlayer.new()
	_tune_sound.name = "TuneEngineSound"
	_tune_sound.set_script(_EngineSound)
	_tune_sound.set(&"play_on_ready", false)
	add_child(_tune_sound)


func _show_tune_panel() -> void:
	if _wheel_job or _departing or _tune_panel == null:
		return
	_hide_garage_overlays()
	_tune_panel.visible = true
	_refresh_tune_panel()
	_sync_menu_nav()


func _hide_tune_panel() -> void:
	if _tune_panel == null or not _tune_panel.visible:
		return
	_tune_panel.visible = false
	_stop_tune_sound()
	_sync_menu_nav()


func _on_tune_step_pressed(delta: int) -> void:
	GameState.set_engine_tune(GameState.engine_tune + delta)
	_refresh_tune_panel()


func _refresh_tune_panel() -> void:
	GameState.refresh_car_stats()
	var engine := GameState.get_equipped_engine()
	var engine_name := str(engine.get("name", "Engine"))
	_tune_engine.text = engine_name
	var sweet := GameState.engine_sweet_tune()
	var tune := GameState.engine_tune
	if _tune_gauge is _TuneGauge:
		(_tune_gauge as _TuneGauge).set_tune(tune, sweet)
	_tune_up.disabled = tune >= GameState.ENGINE_TUNE_MAX
	_tune_down.disabled = tune <= GameState.ENGINE_TUNE_MIN
	_tune_up.queue_redraw()
	_tune_down.queue_redraw()
	if _tune_preview != null and _tune_preview.has_method(&"set_engine"):
		_tune_preview.call(&"set_engine", str(engine.get("model", "")))
		_tune_preview.call(&"set_tune", tune, sweet)
	if _tune_panel.visible:
		_sync_tune_sound(tune, sweet)


func _sync_tune_sound(tune: int, sweet: int) -> void:
	if _tune_sound == null or not _tune_sound.has_method(&"set_tune"):
		return
	_tune_sound.call(&"set_tune", tune, sweet)
	GameState.set_music_dimmed(true)


func _stop_tune_sound() -> void:
	if _tune_sound != null and _tune_sound.playing:
		_tune_sound.stop()
	GameState.set_music_dimmed(false)


func _show_stats() -> void:
	if not GameState.has_active_car():
		return
	_hide_garage_overlays()
	var box: Dictionary = GameState.get_equipped_gearbox()
	var gears: Variant = box.get("ratios", [])
	var gear_count := 0
	if typeof(gears) == TYPE_ARRAY:
		gear_count = gears.size()
	var kind := "automatic" if bool(box.get("automatic", false)) else "manual"
	var t := "Car: %s\n\nTop speed: %.0f km/h\nEngine power: %.0f hp\nGearbox: %s\n%s, %d gears\nFuel: %.0f L" % [
		GameState.car_name,
		GameState.get_effective_vmax_kmh(),
		GameState.engine_power_hp,
		str(box.get("name", "—")),
		kind,
		gear_count,
		GameState.fuel,
	]
	_stats_label.text = t
	_stats_panel.visible = true
	_sync_menu_nav()


func _on_clock_save_pressed() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	if GameState.save_game():
		pass
	_clock_menu.visible = false
	_sync_menu_nav()


func _on_clock_load_pressed() -> void:
	if GameState.load_game():
		GameState.go_to_saved_scene(get_tree())
	_clock_menu.visible = false
	_sync_menu_nav()


func _on_clock_quit_menu_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)
	_clock_menu.visible = false
	_sync_menu_nav()


func _on_clock_close_pressed() -> void:
	_reset_clock_menu_page()
	_clock_menu.visible = false
	_sync_menu_nav()


func _on_clock_settings_pressed() -> void:
	_clock_main.visible = false
	_clock_settings.visible = true
	_refresh_clock_settings()
	_sync_menu_nav()


func _on_clock_settings_back_pressed() -> void:
	_close_clock_settings()


func _close_clock_settings() -> void:
	GameState.save_settings()
	_clock_settings.visible = false
	_clock_main.visible = true
	_sync_menu_nav()


func _refresh_clock_settings() -> void:
	_clock_fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	_clock_master.set_value_no_signal(db_to_linear(AudioServer.get_bus_volume_db(0)))
	_clock_music.set_pressed_no_signal(GameState.music_enabled)
	_clock_arcade.set_pressed_no_signal(GameState.arcade_drive)


func _on_clock_fullscreen_toggled(pressed: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _on_clock_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))


func _on_clock_music_toggled(pressed: bool) -> void:
	GameState.set_music_enabled(pressed)


func _on_clock_arcade_toggled(pressed: bool) -> void:
	GameState.set_arcade_drive(pressed)


func _start_wheel_change(wheel_id: String) -> void:
	if _wheel_job:
		return
	if not GameState.owns_wheel(wheel_id) or wheel_id == GameState.equipped_wheel_id:
		return
	var wheel: Dictionary = GameState.listing_by_id(GameState.WHEELS, wheel_id)
	if wheel.is_empty():
		return
	_wheel_job = true
	_hide_garage_overlays()
	await _run_wheel_change(wheel)
	if not is_instance_valid(self):
		return
	_wheel_job = false


func _run_wheel_change(wheel: Dictionary) -> void:
	var car_start := _car_pivot.position
	var work := Vector3(-2.15, _lift_home.origin.y, 0.12)
	await _tween_global_pos(_lift, work, _T_JACK)
	if not is_instance_valid(self):
		return
	var lift_to := car_start + Vector3(0.0, _LIFT_HEIGHT, 0.0)
	var arm_to := _lift_arm_home + Vector3(0.0, _LIFT_HEIGHT, 0.0)
	await _tween_together(_car_pivot, lift_to, _lift_arm, arm_to, _T_LIFT)
	if not is_instance_valid(self):
		return
	await _pause(_T_PAUSE)
	var radius := maxf(float(wheel.get("height", 0.5)) * 0.5, 0.18)
	for wname in _WHEEL_NODES:
		var mount := _car_pivot.get_node_or_null(wname) as Node3D
		if mount == null:
			continue
		await _swap_one_wheel(mount, wheel, radius)
		if not is_instance_valid(self):
			return
		await _pause(_T_PAUSE)
	await _tween_together(_car_pivot, car_start, _lift_arm, _lift_arm_home, _T_LIFT)
	if not is_instance_valid(self):
		return
	await _tween_global_xform(_lift, _lift_home, _T_JACK)
	if not is_instance_valid(self):
		return
	var err := GameState.buy_or_equip_wheel(str(wheel.get("id", "")))
	if err.is_empty() and _car_pivot.has_method(&"apply_equipped_wheels"):
		_car_pivot.call(&"apply_equipped_wheels")
	_align_wheels_to_floor()
	_refresh_hud()


func _swap_one_wheel(mount: Node3D, wheel: Dictionary, radius: float) -> void:
	var home_local := mount.transform
	var world_xf := mount.global_transform
	var axle := world_xf.origin
	var floor_pos := Vector3(axle.x, axle.y - _LIFT_HEIGHT, axle.z)
	var side := 1.0 if axle.x >= 0.0 else -1.0
	var side_pos := Vector3(axle.x + side * _WHEEL_SIDE_M, floor_pos.y, axle.z)
	var outside := Vector3(side_pos.x, floor_pos.y, _WHEEL_OUT_Z)
	var parent := mount.get_parent()
	parent.remove_child(mount)
	add_child(mount)
	mount.global_transform = world_xf
	await _tween_global_pos(mount, floor_pos, _T_DROP)
	if not is_instance_valid(mount):
		return
	await _pause(_T_PAUSE)
	var facing := world_xf.basis.orthonormalized()
	facing = await _roll_node(mount, side_pos, radius, _T_ROLL_SIDE, world_xf.basis, facing)
	if not is_instance_valid(mount):
		return
	facing = await _roll_node(mount, outside, radius, _T_ROLL_LONG, world_xf.basis, facing)
	if not is_instance_valid(mount):
		return
	await _pause(_T_PAUSE)
	var kept_scale := mount.scale
	if _car_pivot.has_method(&"apply_wheel_to_mount"):
		_car_pivot.call(&"apply_wheel_to_mount", mount, wheel)
	mount.global_transform = Transform3D(world_xf.basis.orthonormalized().scaled(kept_scale), outside)
	facing = world_xf.basis.orthonormalized()
	facing = await _roll_node(mount, side_pos, radius, _T_ROLL_LONG, world_xf.basis, facing)
	if not is_instance_valid(mount):
		return
	await _roll_node(mount, floor_pos, radius, _T_ROLL_SIDE, world_xf.basis, facing)
	if not is_instance_valid(mount):
		return
	await _lift_to_axle(mount, axle, world_xf.basis, _T_RISE)
	if not is_instance_valid(mount):
		return
	remove_child(mount)
	parent.add_child(mount)
	mount.transform = home_local


func _tween_global_pos(node: Node3D, to: Vector3, duration: float) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "global_position", to, duration)
	await tw.finished


func _tween_together(car: Node3D, car_to: Vector3, arm: Node3D, arm_to: Vector3, duration: float) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.set_parallel(true)
	tw.tween_property(car, "position", car_to, duration)
	tw.tween_property(arm, "position", arm_to, duration)
	await tw.finished


func _tween_global_xform(node: Node3D, to: Transform3D, duration: float) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "global_transform", to, duration)
	await tw.finished


## Roll `node` along the ground from its current spot to `to`. Local +Y is the axle,
## same as the drive-out spin. Returns the upright facing at the end of the roll.
func _roll_node(node: Node3D, to: Vector3, radius: float, duration: float, mounted: Basis, from_facing: Basis) -> Basis:
	var start_pos := node.global_position
	var travel := Vector3(to.x - start_pos.x, 0.0, to.z - start_pos.z)
	var dist := travel.length()
	var facing := _facing_for_travel(mounted, travel)
	if dist <= 0.001 or not is_instance_valid(node):
		if is_instance_valid(node):
			node.global_position = to
		return facing
	var wheel_scale := node.scale
	var safe_r := maxf(radius, 0.08)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.tween_method(
		_apply_roll.bind(node, start_pos, to, from_facing, facing, dist, safe_r, wheel_scale),
		0.0,
		1.0,
		duration
	)
	await tw.finished
	return facing


## Upright wheel whose axle (local +Y) is perpendicular to `travel`.
func _facing_for_travel(mounted: Basis, travel: Vector3) -> Basis:
	var upright := mounted.orthonormalized()
	var flat := Vector3(travel.x, 0.0, travel.z)
	if flat.length() < 0.001:
		return upright
	var dir := flat.normalized()
	var current := upright.y
	current.y = 0.0
	if current.length() < 0.001:
		current = Vector3.RIGHT
	else:
		current = current.normalized()
	var axle := Vector3.UP.cross(dir)
	if axle.length() < 0.001:
		return upright
	axle = axle.normalized()
	if current.dot(axle) < 0.0:
		axle = -axle
	var yaw := current.signed_angle_to(axle, Vector3.UP)
	return Basis(Vector3.UP, yaw) * upright


func _lift_to_axle(node: Node3D, axle: Vector3, mounted: Basis, duration: float) -> void:
	var start_pos := node.global_position
	var start_basis := node.global_basis.orthonormalized()
	var goal := mounted.orthonormalized()
	var wheel_scale := node.scale
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(
		_apply_lift.bind(node, start_pos, axle, start_basis, goal, wheel_scale),
		0.0,
		1.0,
		duration
	)
	await tw.finished


func _pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _apply_roll(t: float, node: Node3D, start_pos: Vector3, to: Vector3, from_facing: Basis, facing: Basis, dist: float, safe_r: float, wheel_scale: Vector3) -> void:
	if not is_instance_valid(node):
		return
	var turn := clampf(t / 0.22, 0.0, 1.0)
	var turned := from_facing.slerp(facing, turn)
	var forward := -turned.x
	forward.y = 0.0
	var spin := 0.0
	var travel := Vector3(to.x - start_pos.x, 0.0, to.z - start_pos.z)
	if forward.length() > 0.001 and travel.length() > 0.001:
		spin = signf(travel.normalized().dot(forward.normalized())) * (dist * t) / safe_r
	var basis := (turned * Basis(Vector3.UP, spin)).scaled(wheel_scale)
	node.global_transform = Transform3D(basis, start_pos.lerp(to, t))


func _apply_lift(t: float, node: Node3D, start_pos: Vector3, to: Vector3, start_basis: Basis, goal: Basis, wheel_scale: Vector3) -> void:
	if not is_instance_valid(node):
		return
	var basis := start_basis.slerp(goal, t).scaled(wheel_scale)
	node.global_transform = Transform3D(basis, start_pos.lerp(to, t))


func _on_stats_close_pressed() -> void:
	_stats_panel.visible = false
	_sync_menu_nav()


func _bring_calendar_forward() -> void:
	if _calendar_inspecting:
		return
	_clock_menu.visible = false
	_stats_panel.visible = false
	_spray_menu.visible = false
	_calendar_home = _calendar.global_transform
	_calendar_inspecting = true
	_calendar_hint.visible = true
	if _calendar_tween != null:
		_calendar_tween.kill()
	_calendar_tween = create_tween()
	_calendar_tween.tween_property(self, "_calendar_blend", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hang_calendar() -> void:
	if not _calendar_inspecting:
		return
	_calendar_inspecting = false
	_calendar_hint.visible = false
	if _calendar_tween != null:
		_calendar_tween.kill()
	_calendar_tween = create_tween()
	_calendar_tween.tween_property(self, "_calendar_blend", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _update_calendar_transform() -> void:
	if _calendar_blend <= 0.0001:
		if not _calendar_inspecting:
			_calendar.global_transform = _calendar_home
		return
	_calendar.global_transform = _calendar_home.interpolate_with(_calendar_inspect_transform(), _calendar_blend)


func _calendar_inspect_transform() -> Transform3D:
	var cam_xf := _camera.global_transform
	var pos := cam_xf.origin - cam_xf.basis.z * 1.2
	return Transform3D.IDENTITY.translated(pos).looking_at(cam_xf.origin, Vector3.UP)


func _build_calendar_page() -> void:
	var host := _calendar.get_node("Labels") as Node3D
	for child in host.get_children():
		child.queue_free()
	var now := Time.get_datetime_dict_from_system()
	var year := int(now.get("year", 2026))
	var month := int(now.get("month", 1))
	var today := int(now.get("day", 1))
	var month_name: String = "Month"
	if month >= 1 and month < _MONTHS.size():
		month_name = _MONTHS[month]
	host.add_child(_cal_label("%s  %d" % [month_name, year], Vector3(0.0, 0.35, 0.0), 48, Color(0.98, 0.95, 0.9), 0.0032))
	var cell_w := 0.082
	var cell_h := 0.078
	var origin_x := -3.0 * cell_w
	var week_y := 0.22
	for i in 7:
		host.add_child(_cal_label(_WEEKDAYS[i], Vector3(origin_x + i * cell_w, week_y, 0.0), 22, Color(0.35, 0.18, 0.14), 0.0024))
	var first_wd := _weekday_sunday0(year, month, 1)
	var dim := _days_in_month(year, month)
	var col := first_wd
	var row := 0
	for day in range(1, dim + 1):
		var pos := Vector3(origin_x + col * cell_w, 0.12 - row * cell_h, 0.0)
		var is_today := day == today
		if is_today:
			var mark := MeshInstance3D.new()
			var quad := BoxMesh.new()
			quad.size = Vector3(0.07, 0.07, 0.002)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.75, 0.12, 0.12, 1)
			quad.material = mat
			mark.mesh = quad
			mark.position = pos + Vector3(0.0, 0.0, 0.002)
			host.add_child(mark)
		var color := Color(0.98, 0.94, 0.9) if is_today else Color(0.12, 0.1, 0.08)
		host.add_child(_cal_label(str(day), pos, 28, color, 0.0026))
		col += 1
		if col >= 7:
			col = 0
			row += 1


func _cal_label(text: String, pos: Vector3, font_size: int, color: Color, pixel_size: float) -> Label3D:
	var lab := Label3D.new()
	lab.text = text
	lab.position = pos
	lab.font_size = font_size
	lab.pixel_size = pixel_size
	lab.modulate = color
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lab.shaded = false
	lab.double_sided = false
	return lab


func _days_in_month(year: int, month: int) -> int:
	if month == 2 and _is_leap_year(year):
		return 29
	if month < 1 or month >= _DAYS_IN_MONTH.size():
		return 31
	return _DAYS_IN_MONTH[month]


func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


func _weekday_sunday0(year: int, month: int, day: int) -> int:
	# Sakamoto: 0 = Sunday.
	var t := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	var y := year
	if month < 3:
		y -= 1
	return (y + int(y / 4) - int(y / 100) + int(y / 400) + int(t[month - 1]) + day) % 7


class _TuneArrow extends Button:
	var points_up: bool = true

	func _ready() -> void:
		custom_minimum_size = Vector2(64, 40)
		text = ""
		focus_mode = Control.FOCUS_ALL

	func _draw() -> void:
		var color := Color(0.95, 0.9, 0.78, 1.0)
		if disabled:
			color.a = 0.35
		var mid := size * 0.5
		var pts := PackedVector2Array()
		if points_up:
			pts = PackedVector2Array([mid + Vector2(0, -9), mid + Vector2(12, 8), mid + Vector2(-12, 8)])
		else:
			pts = PackedVector2Array([mid + Vector2(0, 9), mid + Vector2(12, -8), mid + Vector2(-12, -8)])
		draw_colored_polygon(pts, color)


class _TuneGauge extends Control:
	var tune: int = 0
	var sweet: int = 6

	func _init() -> void:
		custom_minimum_size = Vector2(88, 210)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_tune(next: int, next_sweet: int) -> void:
		tune = next
		sweet = next_sweet
		queue_redraw()

	func _draw() -> void:
		var steps := GameState.ENGINE_TUNE_MAX
		var track := Rect2(18.0, 4.0, 52.0, size.y - 8.0)
		draw_rect(track, Color(0.08, 0.06, 0.05, 1.0))
		var row_h := track.size.y / float(steps + 1)
		for step in steps + 1:
			var scale := GameState.engine_tune_scale(step, sweet)
			var warmth := clampf((scale - 0.68) / 0.32, 0.0, 1.0)
			var bar_w := lerpf(8.0, track.size.x - 12.0, warmth)
			var y := track.position.y + track.size.y - (float(step) + 1.0) * row_h
			var bar := Rect2(track.position.x + 6.0, y + 2.0, bar_w, maxf(row_h - 4.0, 1.0))
			var color := Color(0.42, 0.14, 0.1).lerp(Color(0.95, 0.78, 0.32), warmth)
			draw_rect(bar, color)
			if step == sweet:
				draw_rect(Rect2(track.position.x + 2.0, y + 1.0, track.size.x - 4.0, row_h - 2.0), Color(0.95, 0.82, 0.4, 0.28), false, 2.0)
		var mark_y := track.position.y + track.size.y - (float(tune) + 0.5) * row_h
		var tip := Vector2(track.position.x - 1.0, mark_y)
		draw_colored_polygon(PackedVector2Array([
			tip + Vector2(-12, -6),
			tip,
			tip + Vector2(-12, 6),
		]), Color(0.95, 0.9, 0.78))
