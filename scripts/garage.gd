extends Node3D

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _ControlsSetup := preload("res://scripts/controls_setup.gd")
const _GraphicsSetup := preload("res://scripts/graphics_setup.gd")
const _EngineSound := preload("res://scripts/engine_sound.gd")
const _ShopSounds := preload("res://scripts/shop_sounds.gd")
const _SpeechBubble := preload("res://scenes/speech_bubble.tscn")
const _Console := preload("res://scripts/console.gd")
const _CarSale := preload("res://scripts/car_sale.gd")
const _SaveSlots := preload("res://scripts/save_slots.gd")

@onready var _car_pivot: Node3D = $CarPivot
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera_pitch: Node3D = $CameraPivot/Pitch
@onready var _camera: Camera3D = $CameraPivot/Pitch/Camera3D
## Stays on the pivot. The camera itself renders into the view above the status bar.
var _camera_mount: Node3D
var _view_holder: SubViewportContainer
var _view_port: SubViewport

@onready var _clock_menu: Control = $GarageUI/ClockMenu
@onready var _clock_main: Control = $GarageUI/ClockMenu/Panel
@onready var _clock_settings: Control = $GarageUI/ClockMenu/SettingsPanel
@onready var _clock_master: HSlider = $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/MasterSlider
@onready var _clock_music: CheckBox = $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/MusicCheck
@onready var _clock_arcade: CheckBox = $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/ArcadeCheck
@onready var _clock_imperial: CheckBox = $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/ImperialCheck
@onready var _clock_skip_cruise: CheckBox = $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/SkipCruiseCheck
@onready var _stats_panel: Control = $GarageUI/StatsPanel
@onready var _spray_menu: Control = $GarageUI/ColorPickerMenu
@onready var _spray_color_picker: ColorPicker = $GarageUI/ColorPickerMenu/Panel/Margin/VBox/ColorPicker
@onready var _calendar: StaticBody3D = $InteractCalendar
@onready var _calendar_hint: Label = $GarageUI/CalendarHint
@onready var _garage_ui: CanvasLayer = $GarageUI
@onready var _hud_top: Control = $GarageUI/HudTop
@onready var _hud_car_name: Label = %CarNameLabel
@onready var _hud_cash: Label = %CashLabel
@onready var _hud_bottom: Control = $GarageUI/HudBottom
@onready var _lift: StaticBody3D = $InteractLift
@onready var _vodka: StaticBody3D = $InteractDesk/InteractVodka
@onready var _lift_arm: Node3D = $InteractLift/LiftArm
@onready var _door_left: Node3D = $InteractDoors/DoorLeft
@onready var _door_right: Node3D = $InteractDoors/DoorRight
@onready var _clock_hour: Node3D = $InteractClock/Face/HourHand
@onready var _clock_minute: Node3D = $InteractClock/Face/MinuteHand
@onready var _clock_second: Node3D = $InteractClock/Face/SecondHand

var _orbiting: bool = false
var _yaw: float = -PI * 0.5
var _pitch: float = 0.24
var _cam_distance: float = CAM_DISTANCE_DEFAULT
var _cam_distance_target: float = CAM_DISTANCE_DEFAULT

# Camera zoom limits (mouse wheel + pinch).
const CAM_DISTANCE_DEFAULT := 4.0
## Height above the floor the camera aims at: about the car's beltline, so the whole
## car and the wall behind it, with its shelves and clock, are in the frame.
const CAM_LOOK_HEIGHT := 1.2
## Inside faces of the walls and ceiling, less a margin. The camera stays in the room.
const ROOM_MIN := Vector3(-4.15, 0.3, -3.5)
const ROOM_MAX := Vector3(2.85, 2.55, 3.5)
const CAM_DISTANCE_MIN := 2.5
const CAM_DISTANCE_MAX := 8.0
const ZOOM_STEP := 0.75
const PINCH_SENSITIVITY := 1.5
# How quickly we interpolate camera distance (higher = snappier).
const ZOOM_SMOOTH_SPEED := 12.0

var _stats_label: Label
var _parts_board: Control
var _parts_title: Label
var _parts_list: VBoxContainer
var _parts_status: Label
var _parts_close: Button
var _books_board: Control
var _books_title: Label
var _books_status: Label
var _books_scroll: ScrollContainer
var _books_list: VBoxContainer
var _books_back: Button
var _books_close: Button
var _open_book_id: String = ""
var _parts_show_spares: bool = false
var _parts_show_wheels: bool = false
var _parts_show_tires: bool = false
## The wheels the tire machine is working on, or "" before they are picked.
var _tire_target: String = ""
var _spares_actions: HBoxContainer
var _spares_sell: Button
var _spares_forget: Button
var _spares_group: ButtonGroup
## The spare the list is highlighting. A click only changes this; Sell it offers it.
var _spares_selected: int = -1
var _spares_kind: String = ""
var _spares_id: String = ""
## The buyer's offer for a spare, over the parts board, and what it is for.
var _offer_panel: Control
var _offer_label: Label
var _offer_accept: Button
var _offer_reject: Button
var _offer_kind: String = ""
var _offer_id: String = ""
var _offer_amount: int = 0
var _lift_home: Transform3D
var _lift_arm_home: Vector3
var _bay_busy: bool = false
var _departing: bool = false
var _departure_finished: bool = false
var _departure_destination: String = ""
var _swapping_car: bool = false
## Where the car sits in the bay. Kept while it rolls in from outside.
var _bay_home: Vector3 = Vector3.ZERO
var _calendar_home: Transform3D
var _calendar_blend: float = 0.0
var _calendar_inspecting: bool = false
var _calendar_tween: Tween
var _map: StaticBody3D
var _map_hint: Label
var _map_home: Transform3D
var _map_blend: float = 0.0
var _map_inspecting: bool = false
var _map_tween: Tween
## Each place on the sheet: id, marker, label center, and the label's half size.
var _map_spots: Array[Dictionary] = []
## The price box's up and down, and the most its five digits hold.
const SALE_PRICE_STEP := 50
const SALE_PRICE_MAX := 99999

var _nav := _MenuNav.new()
var _car_list: Control
var _car_list_rows: VBoxContainer
var _car_list_count: Label
var _car_list_status: Label
var _car_list_switch: Button
var _car_list_sell: Button
var _car_list_forget: Button
var _car_list_group: ButtonGroup
## The car the list is highlighting. A click only changes this; Switch it moves it into the bay.
var _car_list_selected: String = ""
var _car_sale: RefCounted = null
var _sale_car_id: String = ""
var _sale_panel: Control
var _sale_name: Label
var _sale_line: Label
var _sale_ask: HBoxContainer
var _sale_entry: LineEdit
var _sale_buttons: HBoxContainer
var _sale_answers: HBoxContainer
var _sale_offer: Button
var _sale_never: Button
var _sale_take: Button
var _sale_refuse: Button
var _say_bubble: Control
var _say_after: Callable = Callable()
## The ~ prompt, while it is up.
var _console: Control
## The map's "you're already here" line is up.
var _map_here: bool = false
## The engine heard rolling out of and into the bay.
var _engine_sound: AudioStreamPlayer
var _hood: StaticBody3D
var _hood_shape: BoxShape3D
var _under_car: StaticBody3D
var _under_car_shape: BoxShape3D
var _creeper: StaticBody3D
var _tire_machine: StaticBody3D
## Players for the jack, wheels, and tire machine, by sound name.
var _shop_players: Dictionary = {}
var _loss_bubble: Control
## Shown when the player tries to leave and the engine will not run.
var _stall_bubble: Control
## Shown when Switch it is used on the car already in the bay.
var _here_bubble: Control
## Shown once, on the garage visit straight after the last car is sold or lost.
var _gone_bubble: Control
## Shown when the vodka bottle on the desk is clicked.
var _vodka_bubble: Control
var _tooltip: Label

const _TOOLTIPS := {
	&"clock": "Menu (Q)",
	&"chart": "Parts list",
	&"spares": "Spare parts (L)",
	&"bookshelf": "Bookshelf (B)",
	&"newspaper": "Newspaper (N)",
	&"radio": "Radio (R)",
	&"doors": "Free roam (D)",
	&"spray": "Paint job (P)",
	&"fuel": "Gas station",
	&"hood": "Under the hood (H)",
	&"calendar": "Calendar (X)",
	&"map": "City map (M)",
	&"lift": "Wheels (W)",
	&"tire_machine": "Tire machine (T)",
	&"transmission": "Transmission (A)",
	&"creeper": "Under the car (U)",
	&"vodka": "Wanna drink?",
}
const _TOOLTIP_CARS := "Cars (C)"
const _TOOLTIP_NO_ENGINE := "Under the hood — no engine"
const _TOOLTIP_DOORS_NO_ENGINE := "Needs an engine to drive out"
const _TOOLTIP_DOORS_NO_RUN := "Won't start: %s"
const _TOOLTIP_DOORS_NO_GEARBOX := "Needs a transmission to drive out"
const _TOOLTIP_DOORS_LOOSE := "Tighten the transmission bolts to drive out"
const _TOOLTIP_DOORS_NO_TIRES := "Needs tires to drive out"
const _TOOLTIP_DOORS_NO_WHEELS := "Needs wheels to drive out"
const _SLOT_NAMES := {
	"manifold": "Exhaust manifolds",
	"exhaust": "Exhaust",
	"muffler": "Muffler",
	"muffler_left": "Left muffler",
	"differential": "Rear end",
	"springs": "Springs",
	"shocks": "Shocks",
	"tires": "Tires",
	"cam": "Camshaft",
	"heads": "Cylinder heads",
	"intake": "Intake manifold",
	"carb": "Carburetor",
	"carb_2": "Second carburetor",
	"carb_3": "Third carburetor",
	"distributor": "Distributor",
	"air_cleaner": "Air cleaner",
}
## Where the creeper lies on the floor, beside the car on the camera's side.
const _CREEPER_SPOT := Vector3(-1.85, 0.0, -1.75)

const _MONTHS := [
	"", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]
const _WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const _DAYS_IN_MONTH := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const _CITY_MAP := "res://assets/maps/city.trk"
## The sheet on the back wall, and how large it hangs in front of the camera.
const _MAP_SHEET := Vector2(0.94, 1.26)
const _MAP_DRAW := Vector2(0.86, 1.02)
const _MAP_INSPECT_SCALE := 1.85
const _MAP_INSPECT_DISTANCE := 1.55
const _MAP_POI_COLOR := {
	"garage": Color(0.78, 0.16, 0.13),
	"drive-in": Color(0.9, 0.1, 0.16),
	"gas-station": Color(0.12, 0.38, 0.78),
	"royal-rods": Color(0.82, 0.58, 0.1),
}
const _MAP_LABEL_NUDGE := {
	"garage": Vector2(0.07, 0.015),
	"drive-in": Vector2(-0.05, 0.042),
	"gas-station": Vector2(0.0, 0.04),
	"royal-rods": Vector2(0.07, -0.028),
}
const _MAP_NUMBER_ID: Array[String] = ["garage", "drive-in", "gas-station", "royal-rods"]
const _WHEEL_NODES: Array[String] = [
	"WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight",
]
const _LIFT_HEIGHT := 0.42
## The tire machine stands against the front wall, ahead of the car. With the car up on
## the jack, the wheels roll straight ahead under it along their own tracks and wait in
## front of the machine, the front pair nearer it.
const _TIRE_MACHINE_SPOT := Vector3(1.0, 0.0, 3.25)
const _TIRE_TABLE_Y := 0.66
const _TIRE_WAIT_Z := {
	"WheelFrontLeft": 5.0,
	"WheelFrontRight": 5.0,
	"WheelBackLeft": 4.2,
	"WheelBackRight": 4.2,
}
const _TIRE_ROLL_SPEED := 5.0
## Rolling radius of a wheel with the game's 225/60R15 tires on, and of a bare rim on its
## flange tips (16.62 in across), in meters.
const _TIRE_RADIUS := 0.3255
const _RIM_RADIUS := 0.211
## The new set waits beside the machine, and the old set piles up on the other side.
const _TIRE_STACK_NEW := Vector3(-0.15, 0.0, 3.3)
const _TIRE_STACK_OLD := Vector3(-1.05, 0.0, 3.3)
const _TIRE_THICK := 0.13
## Wheels start this far apart, so that the wrench is heard on each.
const _T_WRENCH_GAP := 0.3
const _T_WRENCH := 0.4
const _T_TIRE_MOVE := 0.55
const _T_JACK := 0.9
const _T_LIFT := 1.0
const _T_DROP := 0.4
const _T_RISE := 0.4
const _T_PAUSE := 0.28
const _T_DOOR_OPEN := 1.25
const _DOOR_SWING := 1.92
const _T_EXIT_DRIVE := 2.7
const _EXIT_DISTANCE := 10.4
const _EXIT_WHEEL_R := 0.27
const _T_EXIT_FADE := 0.5
## Engine note while a car rolls out of the bay or back in.
const _ROLL_RPM_IDLE := 700.0
const _ROLL_RPM_PULL := 2600.0
const _ROLL_VOL_NEAR := -4.0
const _ROLL_VOL_FAR := -16.0

func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	_stats_label = _stats_panel.get_node("Panel/Margin/VBox/StatsText") as Label
	_reset_clock_menu_page()
	var save_btn := $GarageUI/ClockMenu/Panel/Margin/VBox/SaveBtn as Button
	_mark_switch_button(save_btn)
	save_btn.tooltip_text = "Enter"
	_clock_menu.visible = false
	_stats_panel.visible = false
	_spray_menu.visible = false
	_build_parts_board()
	_build_books_board()
	$InteractClock.set_meta(&"garage_interact", &"clock")
	$InteractDesk/InteractChart.set_meta(&"garage_interact", &"chart")
	$InteractDesk/ShelfOther/InteractFolder.set_meta(&"garage_interact", &"spares")
	$InteractBookshelf.set_meta(&"garage_interact", &"bookshelf")
	_refresh_bookshelf_meshes()
	$InteractDesk/InteractNewspaper.set_meta(&"garage_interact", &"newspaper")
	$InteractDesk/Shelf/Radio.set_meta(&"garage_interact", &"radio")
	$InteractDoors.set_meta(&"garage_interact", &"doors")
	$InteractSprayPistol.set_meta(&"garage_interact", &"spray")
	$InteractFuelCan.set_meta(&"garage_interact", &"fuel")
	_vodka.set_meta(&"garage_interact", &"vodka")
	_build_engine_sound()
	_build_hood_target()
	_build_under_car_target()
	_build_creeper()
	_build_tire_machine()
	_lift.set_meta(&"garage_interact", &"lift")
	_lift_home = _lift.global_transform
	_lift_arm_home = _lift_arm.position
	GameState.update_music()
	_calendar.set_meta(&"garage_interact", &"calendar")
	_calendar_home = _calendar.global_transform
	_build_calendar_page()
	_calendar_hint.visible = false
	_build_city_map()
	_hud_top.gui_input.connect(_on_hud_car_stripe_input)
	_build_car_list()
	_build_sale_panel()
	_refresh_hud()
	if GameState.has_active_car():
		_car_pivot.visible = true
		if _car_pivot.has_method(&"set_car_body_color"):
			_car_pivot.set_car_body_color(GameState.car_color)
	else:
		_car_pivot.visible = false
	_build_loss_bubble()
	_build_stall_bubble()
	_build_here_bubble()
	_build_say_bubble()
	_build_gone_bubble()
	_build_vodka_bubble()
	_build_tooltip()
	if GameState.cars_just_gone:
		announce_cars_gone()
	elif GameState.is_ruined():
		_loss_bubble.visible = true
	_cam_distance_target = _cam_distance
	_build_view_above_status()
	_update_camera_transform()

	# Defer so MeshInstance scripts (like the STL loader) have a chance
	# to populate `MeshInstance3D.mesh` before we inspect it.
	call_deferred(&"_debug_car_mesh")
	# Also align wheels to the floor after meshes are ready.
	call_deferred(&"_align_wheels_to_floor")
	call_deferred(&"_place_bay_targets")
	if _wants_drive_in():
		call_deferred(&"_play_drive_in")

	# If the CarBody emits a signal when its STL finishes loading, connect to it
	var car_body := _car_pivot.get_node_or_null("CarBody") as MeshInstance3D
	if car_body != null and car_body.has_signal("stl_loaded"):
		car_body.connect("stl_loaded", Callable(self, "_on_carbody_stl_loaded"))


func _on_carbody_stl_loaded(_mesh: Variant) -> void:
	# When the CarBody's mesh is ready, re-align wheels to the floor.
	_align_wheels_to_floor()
	_place_bay_targets()


func _align_wheels_to_floor() -> void:
	var floor_mesh_instance := $Floor/MeshInstance3D as MeshInstance3D
	if _car_pivot.has_method(&"align_wheels_to_floor"):
		_car_pivot.align_wheels_to_floor(floor_mesh_instance)


func _build_loss_bubble() -> void:
	var bubble := _SpeechBubble.instantiate()
	bubble.visible = false
	$GarageUI.add_child(bubble)
	bubble.call("set_line", "You don't have neither car nor money. You lose!", Vector2(320, 56), 26)
	bubble.call("grab_screen")
	bubble.call("follow_node", _camera, _car_pivot, Vector3(0.0, 1.35, 0.0))
	bubble.connect("pressed", _leave_after_loss)
	_loss_bubble = bubble


func _dismiss_loss_bubble() -> void:
	if _loss_bubble != null:
		_loss_bubble.visible = false


func _build_stall_bubble() -> void:
	var bubble := _SpeechBubble.instantiate()
	bubble.visible = false
	$GarageUI.add_child(bubble)
	bubble.call("set_line", "Your car's not running, speedy!", Vector2(520, 56), 26)
	bubble.call("grab_screen")
	bubble.call("follow_node", _camera, _car_pivot, Vector3(0.0, 1.35, 0.0))
	bubble.connect("pressed", _dismiss_stall_bubble)
	_stall_bubble = bubble


func _show_stall_bubble() -> void:
	if _stall_bubble != null:
		_stall_bubble.visible = true


func _dismiss_stall_bubble() -> void:
	if _stall_bubble != null:
		_stall_bubble.visible = false


func _build_here_bubble() -> void:
	var bubble := _SpeechBubble.instantiate()
	bubble.visible = false
	$GarageUI.add_child(bubble)
	bubble.call("set_line", "Here it is!", Vector2(260, 56), 26)
	bubble.call("grab_screen")
	bubble.call("follow_node", _camera, _car_pivot, Vector3(0.0, 1.35, 0.0))
	bubble.connect("pressed", _dismiss_here_bubble)
	_here_bubble = bubble


## A bubble over the bay for a line that changes. A click or a key takes it down and runs `after`.
func _build_say_bubble() -> void:
	var bubble := _SpeechBubble.instantiate()
	bubble.visible = false
	$GarageUI.add_child(bubble)
	bubble.call("grab_screen")
	bubble.call("follow_node", _camera, _car_pivot, Vector3(0.0, 1.35, 0.0))
	bubble.connect("pressed", _dismiss_say_bubble)
	_say_bubble = bubble


func _say(line: String, after: Callable = Callable()) -> void:
	_say_after = after
	_say_bubble.call("set_line", line, Vector2(260, 56), 26)
	_say_bubble.visible = true


func _dismiss_say_bubble() -> void:
	_map_here = false
	_say_bubble.visible = false
	var after := _say_after
	_say_after = Callable()
	if after.is_valid():
		after.call()


func _show_here_bubble() -> void:
	if _here_bubble != null:
		_here_bubble.visible = true


func _dismiss_here_bubble() -> void:
	if _here_bubble != null:
		_here_bubble.visible = false


func _build_gone_bubble() -> void:
	var bubble := _SpeechBubble.instantiate()
	bubble.visible = false
	$GarageUI.add_child(bubble)
	bubble.call("set_line", "All cars gone!", Vector2(280, 56), 26)
	bubble.call("grab_screen")
	bubble.call("follow_node", _camera, _car_pivot, Vector3(0.0, 1.35, 0.0))
	bubble.connect("pressed", _dismiss_gone_bubble)
	_gone_bubble = bubble


## The last car was just sold or lost, and this is the garage they came back to.
func announce_cars_gone() -> void:
	if not GameState.take_cars_just_gone():
		return
	if _gone_bubble != null:
		_gone_bubble.visible = true


func _dismiss_gone_bubble() -> void:
	if _gone_bubble != null:
		_gone_bubble.visible = false
	if GameState.is_ruined() and _loss_bubble != null:
		_loss_bubble.visible = true


func _build_vodka_bubble() -> void:
	var bubble := _SpeechBubble.instantiate()
	bubble.visible = false
	$GarageUI.add_child(bubble)
	bubble.call("set_line", "Don't drink and drive, bub!", Vector2(520, 56), 26)
	bubble.call("grab_screen")
	bubble.call("follow_node", _camera, _vodka, Vector3(0.0, 0.46, 0.0))
	bubble.connect("pressed", _dismiss_vodka_bubble)
	_vodka_bubble = bubble


func _show_vodka_bubble() -> void:
	if _vodka_bubble != null:
		_vodka_bubble.visible = true


func _dismiss_vodka_bubble() -> void:
	if _vodka_bubble != null:
		_vodka_bubble.visible = false


func _leave_after_loss() -> void:
	GameState.current_scene_path = GameState.SCENE_MAIN_MENU
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)


func _process(_delta: float) -> void:
	_update_clock_hands()
	if not _departing and not _swapping_car:
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
	_update_map_transform()
	_update_tooltip()


func _build_tooltip() -> void:
	_tooltip = Label.new()
	_tooltip.name = "TooltipLabel"
	_tooltip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tooltip.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78, 1))
	_tooltip.add_theme_font_size_override(&"font_size", 22)
	_hud_bottom.add_child(_tooltip)


func _update_tooltip() -> void:
	if _tooltip != null:
		_tooltip.text = _tooltip_text_at_mouse()


func _tooltip_text_at_mouse() -> String:
	if _departing or _bay_busy or _orbiting or _calendar_inspecting or _map_inspecting:
		return ""
	var vp := get_viewport()
	var hovered := vp.gui_get_hovered_control()
	if hovered != null:
		if hovered == _hud_top or _hud_top.is_ancestor_of(hovered):
			return _TOOLTIP_CARS
		return ""
	var kind: Variant = _interact_kind_at(GameState.pointer_position(vp))
	if kind == null:
		return ""
	if _bay_needs_car(kind) and not GameState.has_active_car():
		return ""
	if not GameState.has_engine():
		if kind == &"hood":
			return _TOOLTIP_NO_ENGINE
		if kind == &"doors" or kind == &"fuel":
			return _TOOLTIP_DOORS_NO_ENGINE
	if (kind == &"doors" or kind == &"fuel") and not GameState.engine_runs():
		return _TOOLTIP_DOORS_NO_RUN % GameState.engine_trouble().to_lower().trim_suffix(".")
	if kind == &"doors" and not GameState.has_gearbox():
		return _TOOLTIP_DOORS_NO_GEARBOX
	if kind == &"doors" and not GameState.is_gearbox_bolted():
		return _TOOLTIP_DOORS_LOOSE
	if (kind == &"doors" or kind == &"fuel") and not GameState.has_wheels():
		return _TOOLTIP_DOORS_NO_WHEELS
	if (kind == &"doors" or kind == &"fuel") and not GameState.has_tires():
		return _TOOLTIP_DOORS_NO_TIRES
	return str(_TOOLTIPS.get(kind, ""))


func _interact_kind_at(screen_pos: Vector2) -> Variant:
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return null
	var node := hit.get("collider") as Node
	# The hit can be a child of the tagged body, so walk up to find the meta.
	while node != null:
		if node.has_meta(&"garage_interact"):
			return node.get_meta(&"garage_interact")
		node = node.get_parent()
	return null


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
	if _loss_bubble != null and _loss_bubble.visible and event.is_action_pressed(&"ui_cancel"):
		_dismiss_loss_bubble()
		get_viewport().set_input_as_handled()
		return
	if _gone_bubble != null and _gone_bubble.visible:
		if event.is_action_pressed(&"ui_cancel"):
			_dismiss_gone_bubble()
		get_viewport().set_input_as_handled()
		return
	if _stall_bubble != null and _stall_bubble.visible:
		if event.is_action_pressed(&"ui_cancel"):
			_dismiss_stall_bubble()
		get_viewport().set_input_as_handled()
		return
	if _here_bubble != null and _here_bubble.visible:
		if event.is_action_pressed(&"ui_cancel"):
			_dismiss_here_bubble()
		get_viewport().set_input_as_handled()
		return
	if _vodka_bubble != null and _vodka_bubble.visible:
		if event.is_action_pressed(&"ui_cancel"):
			_dismiss_vodka_bubble()
		get_viewport().set_input_as_handled()
		return
	if _map_inspecting and event.is_action_pressed(&"ui_cancel"):
		_hang_map()
		get_viewport().set_input_as_handled()
		return
	if _map_inspecting and _map_number_key(event):
		get_viewport().set_input_as_handled()
		return
	if _say_bubble != null and _say_bubble.visible:
		get_viewport().set_input_as_handled()
		return
	if _bay_busy:
		_handle_camera_only(event)
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if _console != null:
			# The garage's own keys wait while the prompt is up.
			get_viewport().set_input_as_handled()
			return
		if key.pressed and not key.echo and _Console.is_toggle_key(key):
			_open_console()
			get_viewport().set_input_as_handled()
			return
	if _car_sale != null:
		_nav.handle_event(self, event)
		get_viewport().set_input_as_handled()
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
	if _offer_panel != null and _offer_panel.visible and event.is_action_pressed(&"ui_cancel"):
		_on_offer_rejected()
		get_viewport().set_input_as_handled()
		return
	if _parts_board != null and _parts_board.visible and event.is_action_pressed(&"ui_cancel"):
		_hide_parts_board()
		get_viewport().set_input_as_handled()
		return
	if _books_board != null and _books_board.visible and event.is_action_pressed(&"ui_cancel"):
		if not _open_book_id.is_empty():
			_show_books_list()
		else:
			_hide_books_board()
		get_viewport().set_input_as_handled()
		return
	if _car_list != null and _car_list.visible and event.is_action_pressed(&"ui_cancel"):
		_on_car_list_forget()
		get_viewport().set_input_as_handled()
		return
	if _calendar_inspecting and event.is_action_pressed(&"ui_cancel"):
		_hang_calendar()
		get_viewport().set_input_as_handled()
		return

	if _car_list != null and _car_list.visible and _try_car_list_shortcut(event):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if _spares_list_open() and _try_spares_shortcut(event):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if _books_list_open() and _try_books_shortcut(event):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
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
		if _clock_menu.visible or _stats_panel.visible or _spray_menu.visible or (_books_board != null and _books_board.visible):
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
			if _car_list != null and _car_list.visible:
				_hide_car_list()
				get_viewport().set_input_as_handled()
				return
			if _calendar_inspecting:
				_hang_calendar()
				get_viewport().set_input_as_handled()
				return
			if _map_inspecting:
				var place := _map_poi_at(mb.position)
				if place.is_empty():
					_hang_map()
				else:
					_choose_map_poi(place)
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
			if _map_inspecting:
				_hang_map()
			else:
				_bring_map_forward()
		KEY_R:
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
		KEY_G:
			_handle_interact(&"fuel")
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
		KEY_T:
			if _parts_board != null and _parts_board.visible and _parts_show_tires:
				_hide_parts_board()
			else:
				_handle_interact(&"tire_machine")
		KEY_W:
			if _parts_board != null and _parts_board.visible and _parts_show_wheels:
				_hide_parts_board()
			else:
				_show_wheel_board()
		KEY_L:
			if _parts_board != null and _parts_board.visible and _parts_show_spares:
				_hide_parts_board()
			else:
				_show_spares_board()
		KEY_B:
			if _books_board != null and _books_board.visible:
				_hide_books_board()
			else:
				_show_books_board()
		KEY_H:
			_handle_interact(&"hood")
		KEY_A:
			_handle_interact(&"transmission")
		KEY_U:
			_handle_interact(&"creeper")
		KEY_C:
			if not _car_management_available():
				return false
			_toggle_car_list()
		_:
			return false
	_sync_menu_nav()
	return true


## The bay itself, or the car list already open over it. Other panels keep their own keys.
func _car_management_available() -> bool:
	if _clock_menu.visible or _stats_panel.visible or _spray_menu.visible or _calendar_inspecting or _map_inspecting:
		return false
	if _parts_board != null and _parts_board.visible:
		return false
	if _books_board != null and _books_board.visible:
		return false
	if _offer_panel != null and _offer_panel.visible:
		return false
	return true


func _open_console() -> void:
	_nav.clear()
	var console: Control = _Console.new()
	# Above the bottom bar, so the bankroll stays in view.
	console.call("add_command", "givebook", "put a book on the bookshelf: givebook <id>", _on_givebook)
	console.call("add_command", "showme", "put every part on the car in the bay in 100% condition", _on_showme)
	console.call("add_command", "tiger", "fill the gas tank with premium gas", _on_tiger)
	console.set("bottom_margin", _hud_bottom.size.y if _hud_bottom.visible else 0.0)
	console.call("add_command", "inherit", "an uncle dies and leaves you money", _on_inherit)
	console.closed.connect(_on_console_closed, CONNECT_DEFERRED)
	_console = console
	_garage_ui.add_child(console)


func _on_console_closed() -> void:
	if _console != null:
		_console.queue_free()
		_console = null
	_sync_menu_nav()


## The console's `givebook <ID>`. Puts the book on the shelf and refreshes open views.
func _on_givebook(arg: String) -> String:
	var line := GameState.give_book(arg)
	_refresh_bookshelf_meshes()
	if _books_board != null and _books_board.visible:
		_rebuild_books_board()
	if _parts_board != null and _parts_board.visible:
		_rebuild_parts_board()
	if _stats_panel != null and _stats_panel.visible:
		_show_stats()
	_refresh_hud()
	return line


## The console's `inherit`. The news stays on the prompt.
func _on_inherit() -> String:
	var news := GameState.inherit_from_uncle()
	_refresh_hud()
	return news


## The console's `showme`. The line stays on the prompt; an open parts list shows the
## new conditions.
func _on_showme() -> String:
	var line := GameState.restore_car_parts()
	if _parts_board != null and _parts_board.visible:
		_rebuild_parts_board()
	return line


## The console's `tiger`. The line stays on the prompt.
func _on_tiger() -> String:
	return GameState.fill_tank_free()


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
	if _books_board != null:
		_books_board.visible = false
	if _car_list != null:
		_car_list.visible = false
	_dismiss_here_bubble()
	_sync_menu_nav()


func _reset_clock_menu_page() -> void:
	_clock_main.visible = true
	_clock_settings.visible = false


func _sync_menu_nav() -> void:
	if _clock_menu.visible and _clock_settings.visible:
		_nav.setup([
			$GarageUI/ClockMenu/SettingsPanel/Margin/VBox/GraphicsBtn,
			_clock_master,
			_clock_music,
			_clock_arcade,
			_clock_imperial,
			_clock_skip_cruise,
			$GarageUI/ClockMenu/SettingsPanel/Margin/VBox/ControlsBtn,
			$GarageUI/ClockMenu/SettingsPanel/Margin/VBox/BackBtn,
		])
	elif _clock_menu.visible:
		_nav.setup([
			$GarageUI/ClockMenu/Panel/Margin/VBox/SaveBtn,
			$GarageUI/ClockMenu/Panel/Margin/VBox/LoadBtn,
			$GarageUI/ClockMenu/Panel/Margin/VBox/NewBtn,
			$GarageUI/ClockMenu/Panel/Margin/VBox/SettingsBtn,
			$GarageUI/ClockMenu/Panel/Margin/VBox/QuitBtn,
			$GarageUI/ClockMenu/Panel/Margin/VBox/CloseBtn,
		])
		_nav.select(0)
	elif _stats_panel.visible:
		_nav.setup([$GarageUI/StatsPanel/Panel/Margin/VBox/StatsClose])
	elif _spray_menu.visible:
		_nav.setup([
			$GarageUI/ColorPickerMenu/Panel/Margin/VBox/HBox/ConfirmBtn,
			$GarageUI/ColorPickerMenu/Panel/Margin/VBox/HBox/CancelBtn,
		])
	elif _offer_panel != null and _offer_panel.visible:
		_nav.setup([_offer_accept, _offer_reject])
	elif _sale_panel != null and _sale_panel.visible:
		_nav.setup(_nav.collect_buttons(_sale_panel))
	elif _parts_board != null and _parts_board.visible:
		_nav.setup(_nav.collect_buttons(_parts_board))
	elif _books_board != null and _books_board.visible:
		_nav.setup(_nav.collect_buttons(_books_board))
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


## `yaw_delta` positive turns the view the way a leftward drag does. `zoom_delta` positive moves out.
func nudge_view(yaw_delta: float, zoom_delta: float) -> void:
	if _departing:
		return
	_yaw += yaw_delta
	_cam_distance_target = clampf(_cam_distance_target + zoom_delta, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
	_update_camera_transform()


## The 3D view fills the window down to the status bar, so that bar is not drawn on top of the map.
func _build_view_above_status() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ViewLayer"
	layer.layer = -1
	add_child(layer)
	_view_holder = SubViewportContainer.new()
	_view_holder.name = "View"
	_view_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_holder.stretch = true
	layer.add_child(_view_holder)
	_view_port = SubViewport.new()
	_view_port.name = "ViewPort"
	_view_port.handle_input_locally = false
	_view_port.gui_disable_input = true
	_view_port.physics_object_picking = false
	_view_port.audio_listener_enable_3d = true
	_view_port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var root := get_viewport()
	_view_port.msaa_3d = root.msaa_3d
	_view_port.screen_space_aa = root.screen_space_aa
	_view_holder.add_child(_view_port)
	_view_port.own_world_3d = false
	_view_port.world_3d = root.world_3d
	_camera_mount = Marker3D.new()
	_camera_mount.name = "CameraMount"
	_camera_pitch.add_child(_camera_mount)
	_camera_mount.position = _camera.position
	_camera.reparent(_view_port)
	_camera.make_current()
	_fit_view_above_status()
	root.size_changed.connect(_fit_view_above_status)
	_view_holder.resized.connect(_fit_view_above_status)


func _fit_view_above_status() -> void:
	if _view_holder == null or _view_port == null or _hud_bottom == null:
		return
	var bar_h := _hud_bottom.size.y
	if bar_h < 1.0:
		bar_h = -_hud_bottom.offset_top
	var vp := get_viewport().get_visible_rect().size
	var width := maxi(int(round(vp.x)), 2)
	var height := maxi(int(round(vp.y - bar_h)), 2)
	if not is_equal_approx(_view_holder.offset_bottom, -bar_h):
		_view_holder.offset_bottom = -bar_h
	var next := Vector2i(width, height)
	if _view_port.size != next:
		_view_port.size = next


func _update_camera_transform() -> void:
	_camera_pivot.rotation = Vector3.ZERO
	_camera_pivot.rotate_y(_yaw)
	_camera_pitch.rotation = Vector3.ZERO
	_camera_pitch.rotate_object_local(Vector3.RIGHT, -_pitch)
	_camera_mount.position = Vector3(0.0, 0.6, _cam_distance)
	var target := _camera_pivot.global_position + Vector3(0.0, CAM_LOOK_HEIGHT, 0.0)
	_camera.global_position = _inside_room(target, _camera_mount.global_position)
	_camera.look_at(target, Vector3.UP)


## `eye`, pulled in toward `target` until it is inside the walls.
func _inside_room(target: Vector3, eye: Vector3) -> Vector3:
	var t := 1.0
	for axis in 3:
		var reach := eye[axis] - target[axis]
		if absf(reach) < 0.0001:
			continue
		var limit := ROOM_MAX[axis] if reach > 0.0 else ROOM_MIN[axis]
		t = minf(t, clampf((limit - target[axis]) / reach, 0.0, 1.0))
	return target.lerp(eye, t)


func _try_interact(screen_pos: Vector2) -> void:
	var kind: Variant = _interact_kind_at(screen_pos)
	if kind != null:
		_handle_interact(kind)


func _raycast(screen_pos: Vector2) -> Dictionary:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _handle_interact(kind: Variant) -> void:
	if _bay_busy or _departing:
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
		&"bookshelf":
			_show_books_board()
		&"newspaper":
			get_tree().change_scene_to_file(GameState.SCENE_NEWSPAPER)
		&"radio":
			GameState.toggle_music()
			if _clock_settings.visible:
				_clock_music.set_pressed_no_signal(GameState.music_enabled)
		&"doors":
			_start_drive_out("")
		&"spray":
			_show_spray_picker()
		&"fuel":
			_start_drive_out(GameState.SCENE_GAS_STATION)
		&"hood":
			_open_hood()
		&"calendar":
			_bring_calendar_forward()
		&"map":
			_bring_map_forward()
		&"lift":
			_show_wheel_board()
		&"tire_machine":
			_show_tire_board()
		&"transmission":
			_open_transmission()
		&"creeper":
			_open_under_car()
		&"vodka":
			_show_vodka_bubble()


func _bay_needs_car(kind: Variant) -> bool:
	match kind:
		&"doors", &"chart", &"spares", &"spray", &"fuel", &"hood", &"lift", &"tire_machine", &"transmission", &"creeper":
			return true
	return false


func _open_transmission() -> void:
	if _bay_busy or _departing or not GameState.has_active_car():
		return
	get_tree().change_scene_to_file(GameState.SCENE_TRANSMISSION)


func _open_hood() -> void:
	if _bay_busy or _departing or not GameState.has_active_car():
		return
	GameState.hood_peek.clear()
	get_tree().change_scene_to_file(GameState.SCENE_HOOD)


func _open_under_car() -> void:
	if _bay_busy or _departing or not GameState.has_active_car():
		return
	get_tree().change_scene_to_file(GameState.SCENE_UNDER_CAR)


func _start_drive_out(destination: String) -> void:
	if _departing or _bay_busy:
		return
	if not GameState.engine_runs():
		_show_stall_bubble()
		return
	if not GameState.can_drive():
		return
	_dismiss_stall_bubble()
	var poi := _poi_for_scene(destination)
	if _door_left == null or _door_right == null:
		if destination.is_empty():
			GameState.begin_roam(GameState.POI_GARAGE)
		else:
			_go_to_drive_destination(destination, poi)
		return
	_departing = true
	_departure_destination = destination
	_orbiting = false
	_snap_calendar_home()
	_snap_map_home()
	_hide_garage_overlays()
	$GarageUI.visible = false
	var door_hit := $InteractDoors/CollisionShape3D as CollisionShape3D
	if door_hit != null:
		door_hit.disabled = true
	await _play_drive_out()
	if not is_instance_valid(self):
		return
	_finish_drive_out()


func _finish_drive_out() -> void:
	if _departure_finished:
		return
	_departure_finished = true
	_stop_roll_engine()
	if _departure_destination.is_empty():
		GameState.begin_roam(GameState.POI_GARAGE)
		return
	_go_to_drive_destination(_departure_destination, _poi_for_scene(_departure_destination))


func _poi_for_scene(destination: String) -> String:
	if destination == GameState.SCENE_DRIVE_IN:
		return GameState.POI_DRIVE_IN
	if destination == GameState.SCENE_GAS_STATION:
		return GameState.POI_GAS_STATION
	if destination == GameState.SCENE_ROYAL_RODS:
		return GameState.POI_ROYAL_RODS
	return ""


func _scene_for_poi(poi: String) -> String:
	if poi == GameState.POI_DRIVE_IN:
		return GameState.SCENE_DRIVE_IN
	if poi == GameState.POI_GAS_STATION:
		return GameState.SCENE_GAS_STATION
	if poi == GameState.POI_ROYAL_RODS:
		return GameState.SCENE_ROYAL_RODS
	return ""


func _go_to_drive_destination(destination: String, poi: String) -> void:
	if poi.is_empty():
		get_tree().change_scene_to_file(destination)
		return
	GameState.begin_cruise(GameState.POI_GARAGE, poi, destination)


func _snap_calendar_home() -> void:
	_calendar_inspecting = false
	_calendar_hint.visible = false
	_calendar_blend = 0.0
	if _calendar_tween != null:
		_calendar_tween.kill()
	_calendar.global_transform = _calendar_home


func _snap_map_home() -> void:
	if _map == null:
		return
	_map_inspecting = false
	_set_map_hint_visible(false)
	_map_blend = 0.0
	if _map_tween != null:
		_map_tween.kill()
	_map.global_transform = _map_home


func _wants_drive_in() -> bool:
	var arriving := GameState.drive_into_garage
	GameState.drive_into_garage = false
	if not arriving or not GameState.has_active_car() or _door_left == null or _door_right == null:
		return false
	_bay_home = _car_pivot.position
	_car_pivot.position = _bay_home + Vector3(0.0, 0.0, -_EXIT_DISTANCE)
	_door_left.rotation.y = _DOOR_SWING
	_door_right.rotation.y = -_DOOR_SWING
	_bay_busy = true
	_swapping_car = true
	_orbiting = false
	return true


## Doors are already open. The car rolls in from outside, then the doors close.
func _play_drive_in() -> void:
	await _pause(0.35)
	if not is_instance_valid(self):
		return
	await _roll_car(_car_pivot.position, _bay_home, Tween.EASE_OUT)
	if not is_instance_valid(self):
		return
	_car_pivot.position = _bay_home
	_place_bay_targets()
	await _swing_doors(0.0)
	if not is_instance_valid(self):
		return
	_swapping_car = false
	_bay_busy = false


func _play_drive_out() -> void:
	await _swing_doors(_DOOR_SWING)
	if not is_instance_valid(self):
		return
	await _pause(0.18)
	if not is_instance_valid(self):
		return
	var shade := _black_fade_rect()
	var fade := create_tween()
	fade.tween_interval(maxf(_T_EXIT_DRIVE - _T_EXIT_FADE, 0.0))
	fade.tween_property(shade, "color:a", 1.0, _T_EXIT_FADE)
	await _roll_car(_car_pivot.position, _car_pivot.position + Vector3(0.0, 0.0, -_EXIT_DISTANCE), Tween.EASE_IN)
	if is_instance_valid(shade):
		shade.color = Color(0.0, 0.0, 0.0, 1.0)


## Opens (`_DOOR_SWING`) or closes (0) both garage doors.
func _swing_doors(angle: float) -> void:
	var doors := create_tween()
	doors.set_parallel(true)
	doors.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	doors.tween_property(_door_left, "rotation:y", angle, _T_DOOR_OPEN)
	doors.tween_property(_door_right, "rotation:y", -angle, _T_DOOR_OPEN)
	await doors.finished


## Rolls the car along Z from `start` to `end`, spinning the wheels to match.
func _roll_car(start: Vector3, end: Vector3, ease_type: Tween.EaseType) -> void:
	var wheels: Array[Node3D] = []
	var bases: Array[Basis] = []
	for wname in _WHEEL_NODES:
		var wheel := _car_pivot.get_node_or_null(wname) as Node3D
		if wheel == null or not wheel.visible:
			continue
		wheels.append(wheel)
		bases.append(wheel.basis)
	var travel := (start.z - end.z)
	var pulling_away := travel > 0.0
	_start_roll_engine()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(ease_type)
	tw.tween_method(_apply_drive_out.bind(start, end, wheels, bases, travel, pulling_away), 0.0, 1.0, _T_EXIT_DRIVE)
	await tw.finished
	for i in wheels.size():
		if is_instance_valid(wheels[i]):
			wheels[i].basis = bases[i]
	_stop_roll_engine()


func _swap_car_in_bay(car_id: String) -> void:
	_bay_busy = true
	_swapping_car = true
	_orbiting = false
	_hide_garage_overlays()
	var bay := _car_pivot.position
	var outside := bay + Vector3(0.0, 0.0, -_EXIT_DISTANCE)
	await _swing_doors(_DOOR_SWING)
	if not is_instance_valid(self):
		return
	if GameState.has_active_car() and _car_pivot.visible:
		await _pause(0.18)
		if not is_instance_valid(self):
			return
		await _roll_car(bay, outside, Tween.EASE_IN)
		if not is_instance_valid(self):
			return
	var err := GameState.select_owned_car(car_id)
	_car_pivot.position = outside
	_apply_active_car_visual()
	_refresh_hud()
	if err.is_empty() and GameState.has_active_car():
		await _pause(0.3)
		if not is_instance_valid(self):
			return
		await _roll_car(outside, bay, Tween.EASE_OUT)
		if not is_instance_valid(self):
			return
	_car_pivot.position = bay
	_place_bay_targets()
	await _swing_doors(0.0)
	if not is_instance_valid(self):
		return
	_swapping_car = false
	_bay_busy = false


func _apply_drive_out(t: float, start: Vector3, end: Vector3, wheels: Array[Node3D], bases: Array[Basis], travel: float, pulling_away: bool) -> void:
	_car_pivot.position = start.lerp(end, t)
	# Local +Y is the axle. Positive spin rolls the tire for travel toward -Z.
	var spin := (travel * t) / _EXIT_WHEEL_R
	for i in wheels.size():
		var wheel := wheels[i]
		if not is_instance_valid(wheel):
			continue
		wheel.basis = bases[i] * Basis(Vector3.UP, spin)
	var span := maxf(absf(end.z - start.z), 0.001)
	var away := clampf(absf(_car_pivot.position.z - maxf(start.z, end.z)) / span, 0.0, 1.0)
	_update_roll_engine(t, pulling_away, away)


func _start_roll_engine() -> void:
	if _engine_sound == null or not _engine_sound.has_method(&"set_state") or not GameState.has_engine():
		return
	GameState.set_music_dimmed(true)
	_engine_sound.volume_db = _ROLL_VOL_NEAR
	_engine_sound.call(&"set_state", _ROLL_RPM_IDLE, 0.15, false)


func _update_roll_engine(t: float, pulling_away: bool, away: float) -> void:
	if _engine_sound == null or not _engine_sound.playing:
		return
	var rpm := lerpf(_ROLL_RPM_IDLE, _ROLL_RPM_PULL, t)
	var throttle := lerpf(0.3, 0.9, t)
	if not pulling_away:
		rpm = lerpf(_ROLL_RPM_PULL, _ROLL_RPM_IDLE, t)
		throttle = lerpf(0.55, 0.0, t)
	_engine_sound.volume_db = lerpf(_ROLL_VOL_NEAR, _ROLL_VOL_FAR, away)
	_engine_sound.call(&"set_state", rpm, throttle, false)


func _stop_roll_engine() -> void:
	if _engine_sound != null:
		_engine_sound.volume_db = -6.0
		if _engine_sound.playing:
			_engine_sound.stop()
	GameState.set_music_dimmed(false)


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
	if _parts_board != null:
		_parts_board.visible = false
	if _books_board != null:
		_books_board.visible = false
	if _car_list != null:
		_car_list.visible = false
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
	panel.custom_minimum_size = Vector2(580, 520)
	panel.offset_left = -290
	panel.offset_top = -260
	panel.offset_right = 290
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
	_spares_actions = HBoxContainer.new()
	_spares_actions.add_theme_constant_override(&"separation", 8)
	_spares_actions.visible = false
	_spares_sell = _car_list_action("Sell it", _on_spares_sell)
	_spares_forget = _car_list_action("Forget it", _on_spares_forget)
	_mark_switch_button(_spares_sell)
	_spares_sell.tooltip_text = "S or Enter"
	_spares_forget.tooltip_text = "Esc"
	_spares_actions.add_child(_spares_sell)
	_spares_actions.add_child(_spares_forget)
	box.add_child(_spares_actions)
	_parts_close = Button.new()
	_parts_close.text = "Close"
	_parts_close.pressed.connect(_hide_parts_board)
	box.add_child(_parts_close)
	_build_offer_panel(root)
	$GarageUI.add_child(root)
	_parts_board = root


## A buyer's offer over the parts board: what they would pay, and take it or leave it.
func _build_offer_panel(parent: Control) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.visible = false
	parent.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	_offer_label = Label.new()
	_offer_label.custom_minimum_size = Vector2(380, 0)
	_offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_offer_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_offer_accept = Button.new()
	_offer_accept.custom_minimum_size = Vector2(120, 0)
	_offer_accept.pressed.connect(_on_offer_accepted)
	row.add_child(_offer_accept)
	_offer_reject = Button.new()
	_offer_reject.text = "Reject"
	_offer_reject.custom_minimum_size = Vector2(120, 0)
	_offer_reject.pressed.connect(_on_offer_rejected)
	row.add_child(_offer_reject)
	_offer_panel = shade


func _on_sell_part(kind: String, part_id: String) -> void:
	var err := GameState.sell_trouble(kind, part_id)
	if not err.is_empty():
		_parts_status.text = err
		return
	var item := GameState.listing_for(kind, part_id)
	var list := GameState.spare_condition_list(kind, part_id)
	var condition := list[list.size() - 1] if not list.is_empty() else 1.0
	_offer_kind = kind
	_offer_id = part_id
	_offer_amount = GameState.sell_offer(kind, part_id)
	var new_price := int(item.get("price", 0))
	var what := str(item.get("name", "part"))
	if kind == "wheels":
		var tires := GameState.tires_sold_with_wheels(part_id)
		if not tires.is_empty():
			new_price += int(tires.get("price", 0))
			what += ", with %s on them," % str(tires.get("name", "tires"))
	_offer_label.text = "A buyer looks over your %s (%d%%) and offers $%d.\nThe paper sells them new for $%d." % [
		what, roundi(condition * 100.0), _offer_amount, new_price]
	_offer_accept.text = "Accept $%d" % _offer_amount
	_offer_panel.visible = true
	_sync_menu_nav()
	_offer_accept.grab_focus()


func _on_offer_accepted() -> void:
	var name := str(GameState.listing_for(_offer_kind, _offer_id).get("name", "part"))
	var err := GameState.sell_spare(_offer_kind, _offer_id, _offer_amount)
	_offer_panel.visible = false
	_rebuild_parts_board()
	_parts_status.text = err if not err.is_empty() else "Sold the %s for $%d." % [name, _offer_amount]
	_refresh_hud()
	_sync_menu_nav()
	_focus_spares_sell()


func _on_offer_rejected() -> void:
	_offer_panel.visible = false
	_parts_status.text = "You turned down $%d. Sell again for another offer." % _offer_amount
	_sync_menu_nav()
	_focus_spares_sell()


func _show_parts_board() -> void:
	_parts_show_spares = false
	_parts_show_wheels = false
	_parts_show_tires = false
	_clock_menu.visible = false
	_spray_menu.visible = false
	_stats_panel.visible = false
	if _books_board != null:
		_books_board.visible = false
	if _car_list != null:
		_car_list.visible = false
	_rebuild_parts_board()
	_parts_board.visible = true
	_sync_menu_nav()


func _show_spares_board() -> void:
	_parts_show_spares = true
	_parts_show_wheels = false
	_parts_show_tires = false
	_clock_menu.visible = false
	_spray_menu.visible = false
	_stats_panel.visible = false
	if _books_board != null:
		_books_board.visible = false
	if _car_list != null:
		_car_list.visible = false
	_rebuild_parts_board()
	_parts_board.visible = true
	_sync_menu_nav()
	_focus_spares_sell()


## The tire machine's list, on the wheels named or else asking which.
func _show_tire_board(wheel_id: String = "") -> void:
	if _bay_busy:
		return
	_show_wheel_board()
	_parts_show_wheels = false
	_parts_show_tires = true
	_tire_target = wheel_id
	_rebuild_parts_board()
	_sync_menu_nav()


func _show_wheel_board() -> void:
	if _bay_busy:
		return
	_parts_show_spares = false
	_parts_show_tires = false
	_parts_show_wheels = true
	_clock_menu.visible = false
	_spray_menu.visible = false
	_stats_panel.visible = false
	if _books_board != null:
		_books_board.visible = false
	if _car_list != null:
		_car_list.visible = false
	_rebuild_parts_board()
	_parts_board.visible = true
	_sync_menu_nav()


func _hide_parts_board() -> void:
	_offer_panel.visible = false
	_parts_board.visible = false
	_sync_menu_nav()


func _build_books_board() -> void:
	var root := Control.new()
	root.name = "BooksBoard"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(580, 520)
	panel.offset_left = -290
	panel.offset_top = -260
	panel.offset_right = 290
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
	_books_title = Label.new()
	_books_title.text = "Bookshelf"
	box.add_child(_books_title)
	_books_status = Label.new()
	_books_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_books_status)
	_books_scroll = ScrollContainer.new()
	_books_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_books_scroll.custom_minimum_size = Vector2(0, 380)
	box.add_child(_books_scroll)
	_books_list = VBoxContainer.new()
	_books_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_books_list.add_theme_constant_override("separation", 10)
	_books_scroll.add_child(_books_list)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	_books_back = Button.new()
	_books_back.text = "Back"
	_books_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_books_back.visible = false
	_books_back.pressed.connect(_show_books_list)
	actions.add_child(_books_back)
	_books_close = Button.new()
	_books_close.text = "Close"
	_books_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_books_close.pressed.connect(_hide_books_board)
	actions.add_child(_books_close)
	box.add_child(actions)
	$GarageUI.add_child(root)
	_books_board = root


func _show_books_board() -> void:
	_hang_calendar()
	_hang_map()
	_hide_garage_overlays()
	_open_book_id = ""
	_rebuild_books_board()
	_books_board.visible = true
	_sync_menu_nav()


func _show_books_list() -> void:
	_open_book_id = ""
	_rebuild_books_board()
	_sync_menu_nav()


func _hide_books_board() -> void:
	_open_book_id = ""
	_books_board.visible = false
	_sync_menu_nav()


func _on_book_read(book_id: String) -> void:
	_open_book_id = book_id
	_rebuild_books_board()
	_sync_menu_nav()


func _refresh_bookshelf_meshes() -> void:
	var shelf := get_node_or_null("InteractBookshelf") as Node3D
	if shelf == null:
		return
	var owned_count := GameState.owned_book_ids.size()
	var index := 0
	for child: Node in shelf.get_children():
		if child is MeshInstance3D and child.name.begins_with("Book"):
			(child as MeshInstance3D).visible = index < owned_count
			index += 1


func _rebuild_books_board() -> void:
	for child: Node in _books_list.get_children():
		_books_list.remove_child(child)
		child.queue_free()
	if not _open_book_id.is_empty():
		var book := GameState.book_by_id(_open_book_id)
		if not book.is_empty():
			_rebuild_book_pages(book)
			_books_back.visible = true
			_books_scroll.scroll_vertical = 0
			return
		_open_book_id = ""
	_books_title.text = "Bookshelf"
	var books := GameState.owned_books()
	if books.is_empty():
		_books_status.text = "The shelf is empty."
	else:
		_books_status.text = "Books on the shelf improve every car you own."
		for i: int in books.size():
			var item: Dictionary = books[i]
			var book_id := str(item.get("id", ""))
			var title := str(item.get("title", "Book"))
			var copies := GameState.book_count(book_id)
			var heading := "%d.  %s" % [i + 1, title]
			if copies > 1:
				heading += "  ×%d" % copies
			var effect := GameState.book_effect_text(item)
			var description := str(item.get("description", ""))
			var details: Array[String] = [heading]
			if not effect.is_empty():
				details.append(effect)
			if not description.is_empty():
				details.append(description)
			_books_list.add_child(_action_row("\n".join(details), "Read", _on_book_read.bind(book_id)))
	_books_back.visible = false
	_books_scroll.scroll_vertical = 0


func _rebuild_book_pages(book: Dictionary) -> void:
	_books_title.text = str(book.get("title", "Book"))
	var effect := GameState.book_effect_text(book)
	var description := str(book.get("description", ""))
	if not effect.is_empty() and not description.is_empty():
		_books_status.text = "%s\n%s" % [effect, description]
	elif not effect.is_empty():
		_books_status.text = effect
	else:
		_books_status.text = description
	var content := str(book.get("content", ""))
	if not content.is_empty():
		var body_label := Label.new()
		body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.text = content
		_books_list.add_child(body_label)


func _books_list_open() -> bool:
	return _books_board != null and _books_board.visible and _open_book_id.is_empty()


func _try_books_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed or key.shift_pressed:
		return false
	if _gui_has_text_focus():
		return false
	var index := _car_list_number_index(key.keycode)
	if index < 0:
		return false
	var books := GameState.owned_books()
	if index >= books.size():
		return false
	_on_book_read(str(books[index].get("id", "")))
	return true


func _rebuild_parts_board() -> void:
	for child in _parts_list.get_children():
		_parts_list.remove_child(child)
		# Not free(): this can be the button whose click is being handled, which still uses
		# itself after its signal, and freeing it now crashes the game.
		child.queue_free()
	var spares := false
	if _parts_show_tires:
		_rebuild_tires_list()
	elif _parts_show_wheels:
		_rebuild_wheels_list()
	elif _parts_show_spares:
		_rebuild_spares_list()
		spares = true
	else:
		_rebuild_fitted_list()
	_parts_close.visible = not spares
	_spares_actions.visible = spares


func _rebuild_fitted_list() -> void:
	_parts_title.text = "On the car"
	var engine := GameState.get_equipped_engine()
	var box: Dictionary = GameState.get_equipped_gearbox()
	var wheel := GameState.get_equipped_wheel()
	_parts_status.text = "%s\n%.0f hp · %s" % [
		GameState.car_name,
		GameState.engine_power_hp,
		GameState.speed_text(GameState.get_effective_vmax_kmh()),
	]
	if not engine.is_empty():
		_parts_list.add_child(_mounted_line("Engine", _parts_row_text(engine, "engine") + _condition_text("engine")))
	if box.is_empty():
		_parts_list.add_child(_mounted_line("Transmission", "none"))
	elif not GameState.is_gearbox_bolted():
		_parts_list.add_child(_mounted_line("Transmission", "%s%s  (bolts loose)" % [_parts_row_text(box, "transmission"), _condition_text("transmission")]))
	else:
		_parts_list.add_child(_mounted_line("Transmission", _parts_row_text(box, "transmission") + _condition_text("transmission")))
	if not wheel.is_empty():
		_parts_list.add_child(_mounted_line("Wheels", _parts_row_text(wheel, "wheels") + _condition_text("wheels")))
	for slot in GameState.active_slots():
		var fitted := GameState.slot_part(slot)
		var detail := "none" if fitted.is_empty() else _parts_row_text(fitted, "part") + _condition_text("slot:" + slot)
		if not fitted.is_empty() and GameState.is_hood_kind(GameState.spot_kind(slot)) and not GameState.is_hood_part_bolted(slot):
			detail += "  (bolts loose)"
		var label := str(_SLOT_NAMES[slot])
		if slot == GameState.SLOT_MUFFLER and GameState.has_dual_exhaust():
			label = "Right muffler"
		_parts_list.add_child(_mounted_line(label, detail))
	for part_id in GameState.equipped_part_ids:
		var part: Dictionary = GameState.listing_by_id(GameState.PARTS, part_id)
		if part.is_empty():
			continue
		_parts_list.add_child(_mounted_line("Bolt-on", _parts_row_text(part, "part") + _condition_text("bolt:" + part_id)))


## The tire machine works on wheels that are off the car: first pick the wheels, then the
## tires. The wheels are spare parts the whole time.
func _rebuild_tires_list() -> void:
	_parts_title.text = "Tire machine"
	var shelved := GameState.shelved_wheels()
	var chosen := false
	for wheel in shelved:
		if str(wheel.get("id", "")) == _tire_target:
			chosen = true
	if chosen:
		_rebuild_tires_for_wheels()
		return
	_tire_target = ""
	for wheel in shelved:
		_parts_list.add_child(_action_row(_parts_row_text(wheel, "wheels"), "Select", _on_tire_wheels_chosen.bind(str(wheel.get("id", "")))))
	if not shelved.is_empty():
		_parts_status.text = "Which wheels?"
	elif GameState.has_wheels():
		_parts_status.text = "The machine needs wheels that are off the car. Take them off first: click the jack or press W."
	else:
		_parts_status.text = "There are no wheels here. Buy a set in the newspaper."
	if GameState.tires_worn_out():
		_parts_status.text = "The tires on the car are worn out and will blow in the next race. " + _parts_status.text


func _rebuild_tires_for_wheels() -> void:
	var fitted_id := GameState.shelved_wheel_tires_id(_tire_target)
	var spares := 0
	for part in GameState.PARTS:
		if str(part.get("slot", "")) != GameState.SLOT_TIRES:
			continue
		var part_id := str(part.get("id", ""))
		if part_id == fitted_id:
			_parts_list.add_child(_fixed_row("On these wheels", part))
		elif GameState.spare_count(part_id) > 0:
			spares += 1
			_parts_list.add_child(_action_row(_parts_row_text(part, "part"), "Fit", _on_tires_fit.bind(part_id)))
	if not fitted_id.is_empty():
		_parts_list.add_child(_action_row("Take the tires off", "Remove", _on_tires_fit.bind("")))
	_parts_list.add_child(_action_row("Pick other wheels", "Back", _on_tire_wheels_chosen.bind("")))
	var wheels_name := str(GameState.listing_by_id(GameState.WHEELS, _tire_target).get("name", "wheels"))
	_parts_status.text = "%s: which tires?" % wheels_name if spares > 0 else "%s. No spare tires here: buy a set in the newspaper." % wheels_name
	if fitted_id.is_empty():
		_parts_status.text = "No tires on these. " + _parts_status.text
	elif GameState.shelved_wheel_tires_worn(_tire_target):
		_parts_status.text = "These tires are worn out and will blow in the next race. " + _parts_status.text


func _on_tire_wheels_chosen(wheel_id: String) -> void:
	_tire_target = wheel_id
	_rebuild_parts_board()
	_sync_menu_nav()


## Fits a spare set of tires to the chosen wheels, or with no id takes off the set on them.
func _on_tires_fit(tire_id: String) -> void:
	_hide_parts_board()
	_start_shelf_tire_change(_tire_target, tire_id)


func _fixed_row(state: String, part: Dictionary) -> HBoxContainer:
	var row := _action_row(_parts_row_text(part, "part"), state, Callable())
	(row.get_child(1) as Button).disabled = true
	return row


func _action_row(text: String, action: String, handler: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	row.add_child(label)
	var btn := Button.new()
	btn.text = action
	if handler.is_valid():
		btn.pressed.connect(handler)
	row.add_child(btn)
	return row


func _rebuild_wheels_list() -> void:
	_parts_title.text = "Wheels"
	_parts_status.text = "Pick a set. The jack will change them one corner at a time. Each set keeps the tires on it."
	var count := 0
	for wheel in GameState.WHEELS:
		var wheel_id := str(wheel.get("id", ""))
		if wheel_id != GameState.equipped_wheel_id and GameState.free_spare_count("wheels", wheel_id) <= 0:
			continue
		_parts_list.add_child(_parts_row(wheel, "wheels", GameState.equipped_wheel_id))
		count += 1
	if GameState.has_wheels():
		_parts_list.add_child(_action_row("Take the wheels off", "Remove", _on_wheels_off_pressed))
	else:
		_parts_status.text = "This car has no wheels and can't move until it gets some. Pick a set."
	if count == 0:
		_parts_status.text = "No wheels on the shelf. Buy a set in the newspaper."
	elif count == 1 and GameState.has_wheels():
		_parts_status.text = "Only the wheels on the car are here. Buy another set in the newspaper."


func _rebuild_spares_list() -> void:
	_parts_title.text = "Spare parts"
	_parts_status.text = "Bought, not on any car."
	_spares_group = ButtonGroup.new()
	var index := 0
	var catalogs: Array = [
		[GameState.ENGINES, "engine"],
		[GameState.GEARBOXES, "transmission"],
		[GameState.WHEELS, "wheels"],
		[GameState.PARTS, "part"],
	]
	for catalog: Array in catalogs:
		var kind := str(catalog[1])
		for item: Dictionary in catalog[0]:
			var part: Dictionary = item
			if GameState.free_spare_count(kind, str(part.get("id", ""))) <= 0:
				continue
			_parts_list.add_child(_spare_row(part, kind, index))
			index += 1
	if index == 0:
		_parts_status.text = "The folder is empty. Parts you buy land here until you fit them."
		_spares_selected = -1
		_spares_kind = ""
		_spares_id = ""
		_spares_sell.disabled = true
		return
	var pick := 0
	for i in _parts_list.get_child_count():
		var row := _parts_list.get_child(i) as Button
		if row == null:
			continue
		if str(row.get_meta(&"spare_kind")) == _spares_kind and str(row.get_meta(&"spare_id")) == _spares_id:
			pick = i
			break
	var chosen := _parts_list.get_child(pick) as Button
	if chosen != null:
		chosen.set_pressed_no_signal(true)
	_remember_spare(pick)
	_spares_sell.disabled = false


func _spare_row(item: Dictionary, kind: String, index: int) -> Button:
	var part_id := str(item.get("id", ""))
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = _spares_group
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 36)
	var label := _parts_row_text(item, kind)
	var conditions: Array[String] = []
	for c in GameState.spare_condition_list(kind, part_id):
		conditions.append("%d%%" % roundi(c * 100.0))
	if not conditions.is_empty():
		label += "  · " + ", ".join(conditions)
	btn.text = "%d.  %s" % [index + 1, label]
	btn.set_meta(&"spare_kind", kind)
	btn.set_meta(&"spare_id", part_id)
	btn.toggled.connect(_on_spare_row_toggled.bind(index))
	return btn


func _on_spare_row_toggled(on: bool, index: int) -> void:
	if not on:
		return
	_remember_spare(index)
	_parts_status.text = "Bought, not on any car."


func _remember_spare(index: int) -> void:
	_spares_selected = index
	var btn := _parts_list.get_child(index) as Button
	if btn == null:
		_spares_kind = ""
		_spares_id = ""
		return
	_spares_kind = str(btn.get_meta(&"spare_kind"))
	_spares_id = str(btn.get_meta(&"spare_id"))


func _on_spares_sell() -> void:
	if _spares_selected < 0 or _spares_selected >= _parts_list.get_child_count():
		_parts_status.text = "Pick a part first."
		return
	var btn := _parts_list.get_child(_spares_selected) as Button
	if btn == null:
		return
	_on_sell_part(str(btn.get_meta(&"spare_kind")), str(btn.get_meta(&"spare_id")))


func _on_spares_forget() -> void:
	_hide_parts_board()


func _spares_list_open() -> bool:
	if _parts_board == null or not _parts_board.visible or not _parts_show_spares:
		return false
	if _offer_panel != null and _offer_panel.visible:
		return false
	return true


func _focus_spares_sell() -> void:
	if not _spares_list_open():
		return
	if _spares_sell != null and not _spares_sell.disabled:
		_spares_sell.grab_focus()
	elif _spares_forget != null:
		_spares_forget.grab_focus()


## S sells. 1–9 pick those parts, and 0 picks the 10th.
func _try_spares_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed or key.shift_pressed:
		return false
	if _gui_has_text_focus():
		return false
	var index := _car_list_number_index(key.keycode)
	if index >= 0:
		_select_spare_index(index)
		return true
	if key.keycode != KEY_S:
		return false
	_on_spares_sell()
	return true


func _select_spare_index(index: int) -> void:
	if index < 0 or index >= _parts_list.get_child_count():
		return
	var btn := _parts_list.get_child(index) as Button
	if btn == null:
		return
	btn.button_pressed = true
	btn.grab_focus()


## A fitted part's condition, as it reads after its name.
func _condition_text(mount: String) -> String:
	return "  · %d%%" % roundi(GameState.mount_condition(mount) * 100.0)


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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		var copies := GameState.newspaper_copies(kind, part_id)
		if copies.is_empty():
			btn.text = "Sold"
			btn.disabled = true
		else:
			var price := GameState.newspaper_price(kind, part_id, 0)
			btn.text = "Buy $%d" % price
			btn.disabled = GameState.money < price
			btn.pressed.connect(_on_fit_part.bind(kind, part_id))
	row.add_child(btn)
	return row


func _parts_row_text(item: Dictionary, kind: String) -> String:
	var name := str(item.get("name", "Part"))
	var fits := GameState.fits_text(item)
	if kind == "engine":
		var hp_text := "%s  %.0f hp" % [name, float(item.get("hp", 0.0))]
		return hp_text if fits.is_empty() else "%s   %s" % [hp_text, fits]
	if kind == "transmission":
		var kind_name := "auto" if bool(item.get("automatic", false)) else "manual"
		return "%s  %s" % [name, kind_name] if fits.is_empty() else "%s  %s   for %s" % [name, kind_name, fits]
	if kind == "part" and item.has("slot"):
		return "%s  %s" % [name, GameState.part_detail(item)]
	if kind == "part":
		return "%s  +%d hp" % [name, int(item.get("hp", 0))]
	if kind == "wheels":
		return "%s  %s, %s" % [name, GameState.wheel_detail(item), GameState.wheel_tires_text(str(item.get("id", "")))]
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
			if GameState.free_spare_count("engine", part_id) > 0:
				# Engines go in from under the hood, mounts and all.
				_hide_parts_board()
				_open_hood()
				return
			err = GameState.buy_or_equip_engine(part_id)
		"transmission":
			# Gearboxes go in from under the car, bolts and all.
			_hide_parts_board()
			_open_transmission()
			return
		"wheels":
			if GameState.free_spare_count("wheels", part_id) > 0 and part_id != GameState.equipped_wheel_id:
				_hide_parts_board()
				_start_wheel_change(part_id)
				return
			err = GameState.buy_or_equip_wheel(part_id)
		"part":
			if GameState.part_slot(part_id) == GameState.SLOT_TIRES:
				# Tires go on wheels at the machine, not on the car.
				_show_tire_board()
				return
			elif GameState.is_hood_kind(GameState.part_slot(part_id)):
				# Intakes, carburetors, distributors, and air cleaners go on under the hood.
				_hide_parts_board()
				_open_hood()
				return
			elif not GameState.part_slot(part_id).is_empty():
				# Manifolds, mufflers, and rear ends go on from the creeper.
				_hide_parts_board()
				_open_under_car()
				return
			else:
				err = GameState.equip_part(part_id)
	if not err.is_empty():
		_parts_status.text = err
	_rebuild_parts_board()
	_refresh_hud()
	if _parts_board.visible:
		_sync_menu_nav()


func _refresh_hud() -> void:
	_hud_car_name.text = GameState.car_name
	_hud_cash.text = "Bankroll: $%d" % GameState.money


func _on_hud_car_stripe_input(event: InputEvent) -> void:
	if _bay_busy or not event is InputEventMouseButton:
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
	root.add_theme_stylebox_override(&"panel", _car_list_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	root.add_child(box)
	var title := _car_list_label("Cars in the garage")
	title.custom_minimum_size = Vector2(400, 24)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(400, 36)
	box.add_child(scroll)
	_car_list_rows = VBoxContainer.new()
	_car_list_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_car_list_rows.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_car_list_rows)
	_car_list_count = _car_list_label("")
	_car_list_count.custom_minimum_size = Vector2(400, 22)
	box.add_child(_car_list_count)
	_car_list_status = _car_list_label("")
	_car_list_status.custom_minimum_size = Vector2(400, 22)
	box.add_child(_car_list_status)
	_car_list_group = ButtonGroup.new()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	_car_list_switch = _car_list_action("Switch it", _on_car_list_switch)
	_car_list_sell = _car_list_action("Sell it", _on_car_list_sell)
	_car_list_forget = _car_list_action("Forget it", _on_car_list_forget)
	_mark_switch_button(_car_list_switch)
	_car_list_switch.tooltip_text = "S or Enter"
	_car_list_sell.tooltip_text = "L"
	_car_list_forget.tooltip_text = "F or Esc"
	actions.add_child(_car_list_switch)
	actions.add_child(_car_list_sell)
	actions.add_child(_car_list_forget)
	box.add_child(actions)
	$GarageUI.add_child(root)
	_car_list = root


func _car_list_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.96)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _car_list_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78, 1))
	return label


func _car_list_action(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	return btn


## The red one: Enter runs it, and it stays marked when focus is on a car.
func _mark_switch_button(btn: Button) -> void:
	var ink := Color(0.98, 0.96, 0.9, 1)
	btn.add_theme_stylebox_override(&"normal", _switch_button_style(Color(0.55, 0.12, 0.1, 1)))
	btn.add_theme_stylebox_override(&"hover", _switch_button_style(Color(0.68, 0.18, 0.14, 1)))
	btn.add_theme_stylebox_override(&"pressed", _switch_button_style(Color(0.4, 0.08, 0.07, 1)))
	btn.add_theme_stylebox_override(&"focus", _switch_button_style(Color(0.68, 0.18, 0.14, 1)))
	btn.add_theme_color_override(&"font_color", ink)
	btn.add_theme_color_override(&"font_hover_color", ink)
	btn.add_theme_color_override(&"font_pressed_color", ink)
	btn.add_theme_color_override(&"font_focus_color", ink)
	btn.add_theme_color_override(&"font_disabled_color", Color(0.98, 0.96, 0.9, 0.45))


func _switch_button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(0.95, 0.9, 0.78, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _toggle_car_list() -> void:
	if _bay_busy or _car_list == null:
		return
	if _car_list.visible:
		_hide_car_list()
		return
	if GameState.owned_car_ids.is_empty():
		_say("You've got no car, dummy!")
		return
	_hide_garage_overlays()
	_rebuild_car_list()
	_car_list.visible = true
	_sync_menu_nav()
	if not _car_list_switch.disabled:
		_car_list_switch.grab_focus()


func _hide_car_list() -> void:
	if _car_list == null or not _car_list.visible:
		return
	_car_list.visible = false
	_dismiss_here_bubble()
	_sync_menu_nav()


func _rebuild_car_list() -> void:
	for child in _car_list_rows.get_children():
		_car_list_rows.remove_child(child)
		child.free()
	_ensure_car_list_selection()
	for i in GameState.owned_car_ids.size():
		_car_list_rows.add_child(_car_list_row(GameState.owned_car_ids[i], i))
	_car_list_count.text = "%d of %d" % [GameState.owned_car_ids.size(), GameState.MAX_OWNED_CARS]
	_car_list_status.text = ""
	_refresh_car_list_actions()
	var rows := mini(maxi(GameState.owned_car_ids.size(), 1), 8)
	var rows_height := float(rows * 36 + (rows - 1) * 6)
	var scroll := _car_list_rows.get_parent() as Control
	if scroll != null:
		scroll.custom_minimum_size = Vector2(400, rows_height)
	# Margins, title, count, status line, one row of action buttons, and the gaps between them.
	var chrome := 20.0 + 24.0 + 22.0 + 22.0 + 36.0 + 4.0 * 8.0
	_car_list.offset_left = -220.0
	_car_list.offset_right = 220.0
	_car_list.offset_top = 48.0
	_car_list.offset_bottom = 48.0 + chrome + rows_height


func _ensure_car_list_selection() -> void:
	if GameState.owned_car_ids.has(_car_list_selected):
		return
	if GameState.owned_car_ids.has(GameState.current_car_id):
		_car_list_selected = GameState.current_car_id
		return
	_car_list_selected = GameState.owned_car_ids[0] if not GameState.owned_car_ids.is_empty() else ""


func _car_list_row(car_id: String, index: int) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = _car_list_group
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 36)
	var label := GameState.car_display_name(car_id)
	if car_id == GameState.current_car_id:
		label = "%s    ·    in the bay" % label
	btn.text = "%d.  %s" % [index + 1, label]
	btn.toggled.connect(_on_car_list_row_toggled.bind(car_id))
	btn.set_pressed_no_signal(car_id == _car_list_selected)
	return btn


## S switches, L sells, F closes. 1–9 pick those cars, and 0 picks the 10th.
func _try_car_list_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed or key.shift_pressed:
		return false
	if _gui_has_text_focus():
		return false
	var index := _car_list_number_index(key.keycode)
	if index >= 0:
		_select_car_list_index(index)
		return true
	match key.keycode:
		KEY_S:
			_on_car_list_switch()
		KEY_L:
			_on_car_list_sell()
		KEY_F:
			_on_car_list_forget()
		_:
			return false
	return true


func _car_list_number_index(code: Key) -> int:
	match code:
		KEY_1, KEY_KP_1:
			return 0
		KEY_2, KEY_KP_2:
			return 1
		KEY_3, KEY_KP_3:
			return 2
		KEY_4, KEY_KP_4:
			return 3
		KEY_5, KEY_KP_5:
			return 4
		KEY_6, KEY_KP_6:
			return 5
		KEY_7, KEY_KP_7:
			return 6
		KEY_8, KEY_KP_8:
			return 7
		KEY_9, KEY_KP_9:
			return 8
		KEY_0, KEY_KP_0:
			return 9
		_:
			return -1


func _select_car_list_index(index: int) -> void:
	if index < 0 or index >= _car_list_rows.get_child_count():
		return
	var btn := _car_list_rows.get_child(index) as Button
	if btn == null:
		return
	btn.button_pressed = true
	btn.grab_focus()


func _on_car_list_row_toggled(on: bool, car_id: String) -> void:
	if not on:
		return
	_car_list_selected = car_id
	_car_list_status.text = ""
	_refresh_car_list_actions()


func _refresh_car_list_actions() -> void:
	var picked := GameState.owned_car_ids.has(_car_list_selected)
	_car_list_switch.disabled = not picked
	_car_list_sell.disabled = not picked


func _on_car_list_switch() -> void:
	var car_id := _car_list_selected
	if _bay_busy or _departing or not GameState.owned_car_ids.has(car_id):
		return
	if car_id == GameState.current_car_id:
		_hide_car_list()
		_show_here_bubble()
		return
	if GameState.has_active_car() and not GameState.has_wheels():
		_car_list_status.text = GameState.NO_WHEELS_IN_BAY
		return
	_dismiss_here_bubble()
	_hide_car_list()
	_swap_car_in_bay(car_id)


func _input(event: InputEvent) -> void:
	if _departing and event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			_finish_drive_out()
			return
	if _try_say_bubble_key(event) or (_car_sale != null and _try_sale_key(event)):
		get_viewport().set_input_as_handled()
		return
	if _say_bubble != null and _say_bubble.visible or _car_sale != null:
		return
	if not _is_enter_key(event):
		return
	if _car_list != null and _car_list.visible:
		if _here_bubble != null and _here_bubble.visible:
			get_viewport().set_input_as_handled()
			return
		if _bay_busy or _departing:
			return
		_on_car_list_switch()
		get_viewport().set_input_as_handled()
		return
	if _spares_list_open():
		_on_spares_sell()
		get_viewport().set_input_as_handled()
		return
	if _clock_menu.visible and _clock_main.visible:
		_on_clock_save_pressed()
		get_viewport().set_input_as_handled()


func _is_enter_key(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed or key.shift_pressed:
		return false
	return key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER


## Selling the selected car is not wired yet.
func _on_car_list_sell() -> void:
	if _bay_busy or _departing:
		return
	if not GameState.owned_car_ids.has(_car_list_selected):
		_car_list_status.text = "Pick a car first."
		return
	_sale_car_id = _car_list_selected
	_car_sale = _CarSale.new(GameState.car_value(_sale_car_id))
	_sale_name.text = GameState.car_display_name(_sale_car_id)
	_sale_entry.text = ""
	_car_list_status.text = ""
	_show_sale_ask()


func _on_car_list_forget() -> void:
	_hide_car_list()


func _build_sale_panel() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.visible = false
	$GarageUI.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _car_list_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	_sale_name = _car_list_label("")
	_sale_name.custom_minimum_size = Vector2(400, 24)
	box.add_child(_sale_name)
	_sale_line = _car_list_label("")
	box.add_child(_sale_line)
	_sale_ask = HBoxContainer.new()
	_sale_ask.alignment = BoxContainer.ALIGNMENT_CENTER
	_sale_ask.add_theme_constant_override(&"separation", 4)
	_sale_ask.add_child(_car_list_label("I'll take $"))
	_sale_entry = LineEdit.new()
	_sale_entry.max_length = 5
	_sale_entry.custom_minimum_size = Vector2(90, 0)
	_sale_entry.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_sale_entry.text_changed.connect(_on_sale_entry_changed)
	_sale_ask.add_child(_sale_entry)
	box.add_child(_sale_ask)
	_sale_buttons = HBoxContainer.new()
	_sale_buttons.add_theme_constant_override(&"separation", 8)
	_sale_offer = _car_list_action("Offer", _on_sale_offer)
	_sale_never = _car_list_action("Never mind", _close_car_sale)
	_mark_switch_button(_sale_offer)
	_sale_offer.tooltip_text = "O or Enter"
	_sale_never.tooltip_text = "N or Esc"
	_sale_buttons.add_child(_sale_offer)
	_sale_buttons.add_child(_sale_never)
	box.add_child(_sale_buttons)
	_sale_answers = HBoxContainer.new()
	_sale_answers.add_theme_constant_override(&"separation", 8)
	_sale_take = _car_list_action("OK", _on_sale_answer.bind(true))
	_sale_refuse = _car_list_action("No", _on_sale_answer.bind(false))
	_mark_switch_button(_sale_take)
	_sale_take.tooltip_text = "O or Enter"
	_sale_refuse.tooltip_text = "N or Esc"
	_sale_answers.add_child(_sale_take)
	_sale_answers.add_child(_sale_refuse)
	box.add_child(_sale_answers)
	_sale_panel = shade


## Digits only, as the price is read.
func _on_sale_entry_changed(text: String) -> void:
	var digits := ""
	for ch in text:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != text:
		_sale_entry.text = digits
		_sale_entry.caret_column = digits.length()


func _show_sale_ask() -> void:
	_sale_line.visible = false
	_sale_ask.visible = true
	_sale_buttons.visible = true
	_sale_answers.visible = false
	_sale_panel.visible = true
	_sync_menu_nav()
	_sale_entry.grab_focus()
	_sale_entry.edit()
	_sale_entry.select_all()


func _show_sale_counter(offer: int) -> void:
	_sale_line.text = "How about $%d ?" % offer
	_sale_line.visible = true
	_sale_ask.visible = false
	_sale_buttons.visible = false
	_sale_answers.visible = true
	_sale_panel.visible = true
	_sync_menu_nav()
	_sale_take.grab_focus()


func _on_sale_offer() -> void:
	var asked := _sale_entry.text.to_int()
	if asked <= 0:
		_sale_entry.grab_focus()
		_sale_entry.edit()
		return
	_car_sale.give_price(asked)
	_follow_sale()


func _on_sale_answer(taken: bool) -> void:
	_car_sale.answer_offer(taken)
	_follow_sale()


## On to whatever the buyer's last word calls for.
func _follow_sale() -> void:
	var after := _show_sale_ask
	match _car_sale.step:
		_CarSale.Step.OFFER:
			_show_sale_counter(_car_sale.offer)
			return
		_CarSale.Step.SOLD:
			after = _finish_car_sale
		_CarSale.Step.NO_SALE:
			after = _close_car_sale
	if _car_sale.say.is_empty():
		after.call()
		return
	_sale_panel.visible = false
	_say(_car_sale.say, after)


## Back to the car list, with or without a sale.
func _close_car_sale() -> void:
	_car_sale = null
	_sale_panel.visible = false
	_sync_menu_nav()
	if _car_list.visible and not _car_list_switch.disabled:
		_car_list_switch.grab_focus()


func _finish_car_sale() -> void:
	var car_id := _sale_car_id
	var price: int = _car_sale.price
	var sold := "Sold the %s for $%d." % [GameState.car_display_name(car_id), price]
	_close_car_sale()
	if car_id == GameState.current_car_id:
		await _drive_sold_car_away(car_id, price)
		if not is_instance_valid(self):
			return
	else:
		GameState.sell_car(car_id, price)
		_refresh_hud()
	if GameState.owned_car_ids.is_empty():
		_hide_car_list()
		return
	_rebuild_car_list()
	_car_list_status.text = sold
	_car_list.visible = true
	_sync_menu_nav()
	_car_list_switch.grab_focus()


## The buyer drives the car off and the bay stays empty.
func _drive_sold_car_away(car_id: String, price: int) -> void:
	_bay_busy = true
	_swapping_car = true
	_orbiting = false
	_hide_garage_overlays()
	var bay := _car_pivot.position
	await _swing_doors(_DOOR_SWING)
	if not is_instance_valid(self):
		return
	await _pause(0.18)
	if not is_instance_valid(self):
		return
	await _roll_car(bay, bay + Vector3(0.0, 0.0, -_EXIT_DISTANCE), Tween.EASE_IN)
	if not is_instance_valid(self):
		return
	GameState.sell_car(car_id, price)
	_car_pivot.position = bay
	_apply_active_car_visual()
	_refresh_hud()
	_place_bay_targets()
	await _swing_doors(0.0)
	if not is_instance_valid(self):
		return
	_swapping_car = false
	_bay_busy = false


## A click's worth of keys for the bubble: Enter, Space, or Esc.
func _try_say_bubble_key(event: InputEvent) -> bool:
	if _say_bubble == null or not _say_bubble.visible or not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if _is_enter_key(event) or key.keycode == KEY_SPACE or event.is_action_pressed(&"ui_cancel"):
		_dismiss_say_bubble()
		return true
	return false


## Enter or O for the red button, Esc or N for the other. Digits go on to the price, and up
## and down move it, which is the only way to name a price on a gamepad.
func _try_sale_key(event: InputEvent) -> bool:
	if not _sale_panel.visible or not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	var countering := _sale_answers.visible
	if not countering and (key.keycode == KEY_UP or key.keycode == KEY_DOWN):
		_nudge_sale_price(SALE_PRICE_STEP if key.keycode == KEY_UP else -SALE_PRICE_STEP)
		return true
	if _is_enter_key(event) or key.keycode == KEY_O:
		if countering:
			_on_sale_answer(true)
		else:
			_on_sale_offer()
		return true
	if event.is_action_pressed(&"ui_cancel") or key.keycode == KEY_N:
		if countering:
			_on_sale_answer(false)
		else:
			_close_car_sale()
		return true
	return false


## From what is typed, or from what the car is worth with nothing typed yet.
func _nudge_sale_price(by: int) -> void:
	var asked := _sale_entry.text.to_int() if not _sale_entry.text.is_empty() else GameState.car_value(_sale_car_id)
	_sale_entry.text = str(clampi(asked + by, 0, SALE_PRICE_MAX))
	_sale_entry.caret_column = _sale_entry.text.length()


func _apply_active_car_visual() -> void:
	_car_pivot.visible = GameState.has_active_car()
	if _car_pivot.has_method(&"reload_player_car"):
		_car_pivot.call(&"reload_player_car")
	_align_wheels_to_floor()
	call_deferred(&"_place_bay_targets")


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


func _place_bay_targets() -> void:
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
	var hood := GameState.hood_click_box(box)
	_hood.global_position = hood.get_center()
	_hood_shape.size = hood.size
	if _under_car == null or _under_car_shape == null:
		return
	# Low band between the axles, just behind the engine: where the gearbox sits.
	var under_min := origin + Vector3(size.x * -0.02, 0.0, size.z * 0.38)
	var under_size := Vector3(size.x * 1.04, size.y * 0.3, size.z * 0.28)
	_under_car.global_position = under_min + under_size * 0.5
	_under_car_shape.size = under_size


func _build_under_car_target() -> void:
	_under_car = StaticBody3D.new()
	_under_car.name = "InteractTransmission"
	var col := CollisionShape3D.new()
	_under_car_shape = BoxShape3D.new()
	_under_car_shape.size = Vector3(1.8, 0.4, 1.2)
	col.shape = _under_car_shape
	_under_car.add_child(col)
	_under_car.position = Vector3(0.0, 0.2, 0.3)
	_car_pivot.add_child(_under_car)
	_under_car.set_meta(&"garage_interact", &"transmission")


## A mechanic's creeper on the floor beside the car: padded deck on six casters.
func _build_creeper() -> void:
	_creeper = StaticBody3D.new()
	_creeper.name = "InteractCreeper"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.05, 0.16, 0.48)
	col.shape = shape
	col.position = Vector3(0.0, 0.08, 0.0)
	_creeper.add_child(col)
	var frame := _prop_mat(Color(0.55, 0.12, 0.08), 0.4, 0.45)
	var pad := _prop_mat(Color(0.08, 0.075, 0.07), 0.0, 0.65)
	var steel := _prop_mat(Color(0.6, 0.6, 0.62), 0.8, 0.3)
	var rubber := _prop_mat(Color(0.04, 0.04, 0.04), 0.0, 0.9)
	_prop_box(_creeper, Vector3(1.0, 0.025, 0.42), Vector3(0.0, 0.1, 0.0), frame)
	_prop_box(_creeper, Vector3(0.78, 0.03, 0.36), Vector3(-0.08, 0.127, 0.0), pad)
	# Headrest at the head end, toward the front of the car.
	_prop_box(_creeper, Vector3(0.16, 0.05, 0.3), Vector3(0.4, 0.137, 0.0), pad)
	for cx: float in [-0.42, 0.0, 0.42]:
		for cz: float in [-0.17, 0.17]:
			_prop_box(_creeper, Vector3(0.04, 0.03, 0.04), Vector3(cx, 0.075, cz), steel)
			var wheel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.03
			mesh.bottom_radius = 0.03
			mesh.height = 0.022
			wheel.mesh = mesh
			wheel.material_override = rubber
			wheel.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			wheel.position = Vector3(cx, 0.03, cz)
			_creeper.add_child(wheel)
	_creeper.position = _CREEPER_SPOT
	_creeper.rotation.y = 0.12 - PI * 0.5
	add_child(_creeper)
	_creeper.set_meta(&"garage_interact", &"creeper")


## A tire machine against the front wall: a cabinet with a turntable on top, the column and its
## swing arm over the table, and the pedals at its foot.
func _build_tire_machine() -> void:
	_tire_machine = StaticBody3D.new()
	_tire_machine.name = "InteractTireMachine"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.5, 0.75)
	col.shape = shape
	col.position = Vector3(0.0, 0.75, 0.0)
	_tire_machine.add_child(col)
	var cabinet := _prop_mat(Color(0.12, 0.26, 0.42), 0.3, 0.5)
	var steel := _prop_mat(Color(0.6, 0.6, 0.62), 0.8, 0.3)
	var dark := _prop_mat(Color(0.08, 0.08, 0.08), 0.4, 0.6)
	_prop_box(_tire_machine, Vector3(0.72, 0.56, 0.62), Vector3(0.0, 0.28, 0.0), cabinet)
	_prop_box(_tire_machine, Vector3(0.76, 0.03, 0.66), Vector3(0.0, 0.575, 0.0), dark)
	_prop_cyl(_tire_machine, 0.26, 0.05, Vector3(0.0, 0.615, 0.0), steel)
	_prop_cyl(_tire_machine, 0.03, 0.14, Vector3(0.0, 0.66, 0.0), steel)
	_prop_box(_tire_machine, Vector3(0.1, 0.88, 0.12), Vector3(0.33, 1.02, 0.0), cabinet)
	_prop_box(_tire_machine, Vector3(0.42, 0.07, 0.07), Vector3(0.15, 1.3, 0.0), dark)
	_prop_box(_tire_machine, Vector3(0.05, 0.3, 0.05), Vector3(-0.03, 1.15, 0.0), steel)
	_prop_box(_tire_machine, Vector3(0.09, 0.04, 0.09), Vector3(-0.03, 0.99, 0.0), dark)
	for cz: float in [-0.14, 0.0, 0.14]:
		_prop_box(_tire_machine, Vector3(0.16, 0.025, 0.08), Vector3(-0.42, 0.04, cz), steel)
	_tire_machine.position = _TIRE_MACHINE_SPOT
	# The column to the wall, the pedals to the room.
	_tire_machine.rotation.y = -PI * 0.5
	add_child(_tire_machine)
	_tire_machine.set_meta(&"garage_interact", &"tire_machine")


func _prop_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _prop_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _prop_mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


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


func _build_engine_sound() -> void:
	_engine_sound = AudioStreamPlayer.new()
	_engine_sound.name = "EngineSound"
	_engine_sound.set_script(_EngineSound)
	_engine_sound.set(&"play_on_ready", false)
	add_child(_engine_sound)


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
	if box.is_empty():
		kind = "not fitted"
	var rear_end := GameState.slot_part(GameState.SLOT_DIFFERENTIAL)
	var grip_text := "%.0f" % GameState.tire_grip() if GameState.has_tires() else "—"
	var t := "Car: %s\n\nTop speed: %s\nEngine power: %.0f hp\nTire grip: %s\nGearbox: %s\n%s, %d gears\nRear end: %s\nFuel: %s" % [
		GameState.car_name,
		GameState.speed_text(GameState.get_effective_vmax_kmh()),
		GameState.engine_power_hp,
		grip_text,
		str(box.get("name", "—")),
		kind,
		gear_count,
		str(rear_end.get("name", "—")),
		GameState.fuel_text(GameState.fuel),
	]
	_stats_label.text = t
	_stats_panel.visible = true
	_sync_menu_nav()


## Clockwise on the dial is negative rotation about the face's Z axis.
func _update_clock_hands() -> void:
	var now := Time.get_time_dict_from_system()
	var second := fposmod(Time.get_unix_time_from_system(), 60.0)
	var minute := float(now.get("minute", 0)) + second / 60.0
	var hour := fposmod(float(now.get("hour", 0)), 12.0) + minute / 60.0
	_clock_hour.rotation.z = -hour * TAU / 12.0
	_clock_minute.rotation.z = -minute * TAU / 60.0
	_clock_second.rotation.z = -second * TAU / 60.0


func _on_clock_save_pressed() -> void:
	_open_save_slots(true)


func _on_clock_load_pressed() -> void:
	_open_save_slots(false)


func _on_clock_new_pressed() -> void:
	GameState.new_game()
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


## Puts the clock away and brings up the slot list for saving or loading.
func _open_save_slots(saving: bool) -> void:
	_clock_menu.visible = false
	_nav.clear()
	var slots: Control = _SaveSlots.new()
	slots.saving = saving
	slots.chosen.connect(_on_save_slot_chosen.bind(slots, saving))
	slots.closed.connect(_on_save_slots_closed.bind(slots))
	$GarageUI.add_child(slots)


func _on_save_slot_chosen(slot: int, slots: Control, saving: bool) -> void:
	slots.queue_free()
	if saving:
		GameState.current_scene_path = GameState.SCENE_GARAGE
		GameState.save_game(slot)
		_sync_menu_nav()
		return
	if GameState.load_game(slot):
		GameState.go_to_saved_scene(get_tree())
	else:
		_sync_menu_nav()


func _on_save_slots_closed(slots: Control) -> void:
	slots.queue_free()
	_clock_menu.visible = true
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


func _on_clock_controls_pressed() -> void:
	_ControlsSetup.new().open(self, _clock_settings, $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/ControlsBtn)




func _close_clock_settings() -> void:
	GameState.save_settings()
	_clock_settings.visible = false
	_clock_main.visible = true
	_sync_menu_nav()


func _refresh_clock_settings() -> void:
	_clock_master.set_value_no_signal(db_to_linear(AudioServer.get_bus_volume_db(0)))
	_clock_music.set_pressed_no_signal(GameState.music_enabled)
	_clock_arcade.set_pressed_no_signal(GameState.arcade_drive)
	_clock_imperial.set_pressed_no_signal(GameState.imperial_units)
	_clock_skip_cruise.set_pressed_no_signal(GameState.skip_cruise)


func _on_clock_graphics_pressed() -> void:
	_GraphicsSetup.new().open(self, _clock_settings, $GarageUI/ClockMenu/SettingsPanel/Margin/VBox/GraphicsBtn)


func _on_clock_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))


func _on_clock_music_toggled(pressed: bool) -> void:
	GameState.set_music_enabled(pressed)


func _on_clock_arcade_toggled(pressed: bool) -> void:
	GameState.set_arcade_drive(pressed)


func _on_clock_imperial_toggled(pressed: bool) -> void:
	GameState.set_imperial_units(pressed)


func _on_clock_skip_cruise_toggled(pressed: bool) -> void:
	GameState.set_skip_cruise(pressed)


func _start_wheel_change(wheel_id: String) -> void:
	if _bay_busy:
		return
	if GameState.free_spare_count("wheels", wheel_id) <= 0 or wheel_id == GameState.equipped_wheel_id:
		return
	var wheel: Dictionary = GameState.listing_by_id(GameState.WHEELS, wheel_id)
	if wheel.is_empty():
		return
	_bay_busy = true
	_hide_garage_overlays()
	await _run_wheel_change(wheel)
	if not is_instance_valid(self):
		return
	_bay_busy = false


func _shop_sound(sound_name: String) -> void:
	if not _shop_players.has(sound_name):
		var player := AudioStreamPlayer.new()
		player.stream = _ShopSounds.stream(sound_name)
		player.volume_db = -6.0
		player.max_polyphony = 4
		add_child(player)
		_shop_players[sound_name] = player
	(_shop_players[sound_name] as AudioStreamPlayer).play()


func _shop_sound_stop(sound_name: String) -> void:
	if _shop_players.has(sound_name):
		(_shop_players[sound_name] as AudioStreamPlayer).stop()


## The jack rolls in and raises the car.
func _jack_up(car_start: Vector3) -> void:
	var work := Vector3(-2.15, _lift_home.origin.y, 0.12)
	await _tween_global_pos(_lift, work, _T_JACK)
	if not is_instance_valid(self):
		return
	_shop_sound("jack_pump")
	var lift_to := car_start + Vector3(0.0, _LIFT_HEIGHT, 0.0)
	var arm_to := _lift_arm_home + Vector3(0.0, _LIFT_HEIGHT, 0.0)
	await _tween_together(_car_pivot, lift_to, _lift_arm, arm_to, _T_LIFT)
	if not is_instance_valid(self):
		return
	await _pause(_T_PAUSE)


## The jack lets the car down and rolls home.
func _jack_down(car_start: Vector3) -> void:
	_shop_sound("jack_release")
	await _tween_together(_car_pivot, car_start, _lift_arm, _lift_arm_home, _T_LIFT)
	if not is_instance_valid(self):
		return
	await _tween_global_xform(_lift, _lift_home, _T_JACK)


## The car goes up, the wheels on it roll away together, the new set rolls in together and
## goes on, and the car comes down.
func _run_wheel_change(wheel: Dictionary) -> void:
	var car_start := _car_pivot.position
	var had_wheels := GameState.has_wheels()
	await _jack_up(car_start)
	if not is_instance_valid(self):
		return
	var old_radius := _roll_radius(GameState.get_equipped_wheel(), GameState.has_tires())
	var radius := _roll_radius(wheel, not GameState.shelved_wheel_tires_id(str(wheel.get("id", ""))).is_empty())
	var wheels := _take_wheels_off(had_wheels)
	if had_wheels:
		var off: Array[Callable] = []
		for each in wheels:
			off.append(_roll_wheel_away.bind(each, old_radius))
		await _await_all(off)
		if not is_instance_valid(self):
			return
	var on: Array[Callable] = []
	for each in wheels:
		on.append(_roll_wheel_on.bind(each, wheel, radius))
	await _await_all(on)
	if not is_instance_valid(self):
		return
	await _jack_down(car_start)
	if not is_instance_valid(self):
		return
	var err := GameState.buy_or_equip_wheel(str(wheel.get("id", "")))
	if err.is_empty() and _car_pivot.has_method(&"apply_equipped_wheels"):
		_car_pivot.call(&"apply_equipped_wheels")
	_align_wheels_to_floor()
	_refresh_hud()


## Takes each wheel off its hub into the garage, drawn with the set on the car if `shown`.
func _take_wheels_off(shown: bool) -> Array[Dictionary]:
	var wheels: Array[Dictionary] = []
	for wname in _WHEEL_NODES:
		var mount := _car_pivot.get_node_or_null(wname) as Node3D
		if mount == null:
			continue
		if shown and _car_pivot.has_method(&"apply_wheel_to_mount"):
			_car_pivot.call(&"apply_wheel_to_mount", mount, GameState.get_equipped_wheel())
		wheels.append(_take_wheel_off(mount, str(wname)))
	return wheels


## A set rolls in from where the old one went, rises onto the hub, and is bolted up.
func _roll_wheel_on(wheel: Dictionary, part: Dictionary, radius: float) -> void:
	var mount: Node3D = wheel["mount"]
	var kept_scale: Vector3 = wheel["scale"]
	if _car_pivot.has_method(&"apply_wheel_to_mount"):
		_car_pivot.call(&"apply_wheel_to_mount", mount, part)
	var upright: Basis = (wheel["mounted"] as Basis).orthonormalized()
	mount.global_transform = Transform3D(upright.scaled(kept_scale), wheel["spot"])
	wheel["facing"] = upright
	await _roll_wheel(wheel, wheel["floor"], radius)
	if not is_instance_valid(mount):
		return
	await _lift_to_axle(mount, wheel["axle"], wheel["mounted"], _T_RISE)
	if not is_instance_valid(mount):
		return
	await _pause(float(wheel["turn"]) * _T_WRENCH_GAP)
	if not is_instance_valid(mount):
		return
	_shop_sound("wrench")
	remove_child(mount)
	(wheel["parent"] as Node).add_child(mount)
	mount.transform = wheel["home_local"]


func _on_wheels_off_pressed() -> void:
	_hide_parts_board()
	if _bay_busy or not GameState.has_wheels():
		return
	_bay_busy = true
	_hide_garage_overlays()
	await _run_wheels_off()
	if not is_instance_valid(self):
		return
	_bay_busy = false


## The car goes up and the wheels, tires and all, roll away to spare parts, and the car comes
## down with none.
func _run_wheels_off() -> void:
	var car_start := _car_pivot.position
	await _jack_up(car_start)
	if not is_instance_valid(self):
		return
	var radius := _roll_radius(GameState.get_equipped_wheel(), GameState.has_tires())
	var wheels := _take_wheels_off(true)
	var off: Array[Callable] = []
	for wheel in wheels:
		off.append(_roll_wheel_away.bind(wheel, radius))
	await _await_all(off)
	if not is_instance_valid(self):
		return
	GameState.remove_wheels()
	for wheel in wheels:
		var mount: Node3D = wheel["mount"]
		remove_child(mount)
		(wheel["parent"] as Node).add_child(mount)
		mount.transform = wheel["home_local"]
		mount.visible = false
	await _jack_down(car_start)
	if not is_instance_valid(self):
		return
	if _car_pivot.has_method(&"apply_equipped_wheels"):
		_car_pivot.call(&"apply_equipped_wheels")
	_refresh_hud()


## The tire machine on the chosen wheels: one wheel on the table stands for the set, its old
## tire coming off and the new one going on. It stays open on those wheels until the player
## leaves.
func _start_shelf_tire_change(wheel_id: String, tire_id: String) -> void:
	if _bay_busy:
		return
	var has_old := not GameState.shelved_wheel_tires_id(wheel_id).is_empty()
	if tire_id.is_empty() and not has_old:
		return
	if not tire_id.is_empty() and GameState.spare_count(tire_id) <= 0:
		return
	_bay_busy = true
	_hide_garage_overlays()
	await _run_shelf_tire_change(wheel_id, has_old, not tire_id.is_empty())
	if not is_instance_valid(self):
		return
	if tire_id.is_empty():
		GameState.remove_tires_from_shelved_wheels(wheel_id)
	else:
		GameState.fit_tires_on_shelved_wheels(wheel_id, tire_id)
	_refresh_hud()
	_bay_busy = false
	_show_tire_board(wheel_id)


func _run_shelf_tire_change(wheel_id: String, has_old: bool, has_new: bool) -> void:
	var radius := _roll_radius(GameState.listing_by_id(GameState.WHEELS, wheel_id), true)
	var on_table := _TIRE_MACHINE_SPOT + Vector3(0.0, _TIRE_TABLE_Y + _TIRE_THICK * 0.5, 0.0)
	var rim := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.62
	mesh.bottom_radius = radius * 0.62
	mesh.height = _TIRE_THICK * 1.2
	rim.mesh = mesh
	rim.material_override = _prop_mat(Color(0.6, 0.6, 0.62), 0.8, 0.3)
	add_child(rim)
	rim.global_position = on_table
	var rings: Array[MeshInstance3D] = []
	_shop_sound("motor")
	if has_old:
		var old := _tire_ring(radius, on_table)
		rings.append(old)
		_shop_sound("bead_pop")
		await _move_tire(old, on_table + Vector3(0.0, 0.3, 0.0), _TIRE_STACK_OLD + Vector3(0.0, _TIRE_THICK * 0.5, 0.0))
		if not is_instance_valid(self):
			return
	if has_new:
		var fresh := _tire_ring(radius, _TIRE_STACK_NEW + Vector3(0.0, _TIRE_THICK * 0.5, 0.0))
		rings.append(fresh)
		await _move_tire(fresh, on_table + Vector3(0.0, 0.3, 0.0), on_table)
		if not is_instance_valid(self):
			return
		fresh.visible = false
		_shop_sound("air")
	_shop_sound_stop("motor")
	for ring in rings:
		ring.queue_free()
	rim.queue_free()


## How far a set's axles sit off the floor as it rolls: on its tires, or on bare rims.
func _roll_radius(wheel: Dictionary, with_tires: bool) -> float:
	return (_TIRE_RADIUS if with_tires else _RIM_RADIUS) * float(wheel.get("scale", 1.0))


## Runs the coroutines side by side and waits for them all.
func _await_all(jobs: Array[Callable]) -> void:
	var left := [jobs.size()]
	for job in jobs:
		_finish_job(job, left)
	while left[0] > 0 and is_instance_valid(self):
		await get_tree().process_frame


func _finish_job(job: Callable, left: Array) -> void:
	await job.call()
	left[0] -= 1


## Takes a wheel off its hub into the garage and says where it came from and is going.
func _take_wheel_off(mount: Node3D, wname: String) -> Dictionary:
	var world_xf := mount.global_transform
	var axle := world_xf.origin
	var floor_pos := Vector3(axle.x, axle.y - _LIFT_HEIGHT, axle.z)
	var parent := mount.get_parent()
	var home_local := mount.transform
	parent.remove_child(mount)
	add_child(mount)
	mount.global_transform = world_xf
	return {
		"mount": mount,
		"parent": parent,
		"home_local": home_local,
		"mounted": world_xf.basis,
		"axle": axle,
		"floor": floor_pos,
		"spot": Vector3(axle.x, floor_pos.y, float(_TIRE_WAIT_Z[wname])),
		"scale": mount.scale,
		"facing": world_xf.basis.orthonormalized(),
		"turn": _WHEEL_NODES.find(wname),
	}


func _roll_wheel_away(wheel: Dictionary, radius: float) -> void:
	var mount: Node3D = wheel["mount"]
	await _pause(float(wheel["turn"]) * _T_WRENCH_GAP)
	if not is_instance_valid(mount):
		return
	_shop_sound("wrench")
	await _pause(_T_WRENCH)
	if not is_instance_valid(mount):
		return
	await _tween_global_pos(mount, wheel["floor"], _T_DROP)
	if not is_instance_valid(mount):
		return
	_shop_sound("thud")
	await _roll_wheel(wheel, wheel["spot"], radius)


func _roll_wheel(wheel: Dictionary, to: Vector3, radius: float) -> void:
	var mount: Node3D = wheel["mount"]
	var duration := mount.global_position.distance_to(to) / _TIRE_ROLL_SPEED
	wheel["facing"] = await _roll_node(mount, to, radius, duration, wheel["mounted"], wheel["facing"])


## A tire swings up to `over`, then across and down to `to`.
func _move_tire(tire: Node3D, over: Vector3, to: Vector3) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(tire, "global_position", over, _T_TIRE_MOVE)
	tw.tween_property(tire, "global_position", to, _T_TIRE_MOVE)
	await tw.finished


## A tire on its own, lying flat, drawn around a wheel of this radius.
func _tire_ring(radius: float, at: Vector3) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.62
	mesh.outer_radius = radius * 1.08
	ring.mesh = mesh
	ring.material_override = _prop_mat(Color(0.04, 0.04, 0.04), 0.0, 0.9)
	add_child(ring)
	ring.global_position = at
	return ring


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
	_hang_map()
	_hide_garage_overlays()
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


## A framed plan of the city, on the back wall. Clicking it brings the same sheet forward.
func _build_city_map() -> void:
	var track := TrackFile.load_path(_CITY_MAP)
	var errors: Array = track.get("errors", [])
	if not errors.is_empty():
		push_error("City map: %s" % str(errors[0]))
		return
	_map = StaticBody3D.new()
	_map.name = "InteractMap"
	# The wall the garage opens facing. Local -Z points into the room.
	_map.basis = Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0))
	_map.position = Vector3(2.95, 1.65, -2.0)
	add_child(_map)
	_map.set_meta(&"garage_interact", &"map")
	_map_board(_map, Vector3(_MAP_SHEET.x + 0.1, _MAP_SHEET.y + 0.1, 0.03), Vector3(0.0, 0.0, 0.006), Color(0.32, 0.2, 0.11), 0.62)
	_map_board(_map, Vector3(_MAP_SHEET.x, _MAP_SHEET.y, 0.008), Vector3(0.0, 0.0, -0.012), Color(0.9, 0.86, 0.76), 0.9)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_MAP_SHEET.x + 0.12, _MAP_SHEET.y + 0.12, 0.08)
	shape.shape = box
	_map.add_child(shape)
	_draw_city_map(_map, track)
	_map_home = _map.global_transform
	_map_hint = Label.new()
	_map_hint.name = "MapHint"
	_map_hint.visible = false
	_map_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_map_hint.offset_left = -460.0
	_map_hint.offset_top = -92.0
	_map_hint.offset_right = 460.0
	_map_hint.offset_bottom = -52.0
	_map_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_hint.text = "Click a place to drive there. M or Esc puts the map back"
	_map_hint.add_theme_font_size_override(&"font_size", 22)
	_map_hint.add_theme_color_override(&"font_color", Color(0.96, 0.93, 0.86))
	_garage_ui.add_child(_map_hint)


func _draw_city_map(host: Node3D, track: Dictionary) -> void:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	var nodes: Dictionary = track["nodes"]
	for id: int in nodes:
		var node: Dictionary = nodes[id]
		min_x = minf(min_x, float(node["x"]))
		max_x = maxf(max_x, float(node["x"]))
		min_y = minf(min_y, float(node["y"]))
		max_y = maxf(max_y, float(node["y"]))
	for pid: String in track["poi_order"]:
		var poi: Dictionary = track["pois"][pid]
		min_x = minf(min_x, float(poi["x"]))
		max_x = maxf(max_x, float(poi["x"]))
		min_y = minf(min_y, float(poi["y"]))
		max_y = maxf(max_y, float(poi["y"]))
	min_x -= 24.0
	max_x += 24.0
	min_y -= 24.0
	max_y += 24.0
	var span_x := maxf(max_x - min_x, 1.0)
	var span_y := maxf(max_y - min_y, 1.0)
	var scale := minf(_MAP_DRAW.x / span_x, _MAP_DRAW.y / span_y)
	var layout := {
		"cx": (min_x + max_x) * 0.5,
		"cy": (min_y + max_y) * 0.5,
		"scale": scale,
		"shift_y": -0.05,
	}
	var paper := SurfaceTool.new()
	paper.begin(Mesh.PRIMITIVE_TRIANGLES)
	_map_quad(paper, Vector2(0.0, float(layout["shift_y"])), Vector2(_MAP_DRAW.x * 0.5, 0.0), Vector2(0.0, _MAP_DRAW.y * 0.5), Color(0.55, 0.62, 0.46))
	_add_map_mesh(host, "Paper", paper, -0.022)
	var blocks := SurfaceTool.new()
	blocks.begin(Mesh.PRIMITIVE_TRIANGLES)
	for raw: Dictionary in track.get("buildings", []):
		var color := Color(0.45, 0.42, 0.38)
		if raw.has("color"):
			color = raw["color"]
		var center := _map_point(layout, float(raw["x"]), float(raw["y"]))
		var half := Vector2(float(raw["w"]), float(raw["d"])) * scale * 0.5
		_map_quad(blocks, center, Vector2(half.x, 0.0), Vector2(0.0, half.y), color.darkened(0.15))
	_add_map_mesh(host, "Blocks", blocks, -0.026)
	var streets := SurfaceTool.new()
	streets.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seen := {}
	for road: Dictionary in track["roads"]:
		var a_id := int(road["from"])
		var b_id := int(road["to"])
		var key := "%d-%d" % [mini(a_id, b_id), maxi(a_id, b_id)]
		if seen.has(key) or not nodes.has(a_id) or not nodes.has(b_id):
			continue
		seen[key] = true
		var a: Dictionary = nodes[a_id]
		var b: Dictionary = nodes[b_id]
		var from_pt := _map_point(layout, float(a["x"]), float(a["y"]))
		var to_pt := _map_point(layout, float(b["x"]), float(b["y"]))
		var span := to_pt - from_pt
		var length := span.length()
		if length < 0.0008:
			continue
		var dir := span / length
		var half_w := maxf(float(road.get("width", 16.0)) * scale * 0.5, 0.0045)
		_map_quad(streets, (from_pt + to_pt) * 0.5, dir * length * 0.5, Vector2(-dir.y, dir.x) * half_w, Color(0.32, 0.32, 0.34))
	_add_map_mesh(host, "Streets", streets, -0.03)
	_map_spots = []
	var marks := SurfaceTool.new()
	marks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var names := Node3D.new()
	names.name = "Names"
	names.position = Vector3(0.0, 0.0, -0.042)
	host.add_child(names)
	for pid: String in track["poi_order"]:
		var poi: Dictionary = track["pois"][pid]
		var at := _map_point(layout, float(poi["x"]), float(poi["y"]))
		var color: Color = _MAP_POI_COLOR.get(pid, Color(0.9, 0.82, 0.3))
		_map_quad(marks, at, Vector2(0.016, 0.0), Vector2(0.0, 0.016), color)
		var lab := Label3D.new()
		var place_name := str(poi["name"])
		lab.text = place_name
		var nudge: Vector2 = _MAP_LABEL_NUDGE.get(pid, Vector2(0.0, 0.04))
		var label_at := at + nudge
		var em := 40.0 * 0.00105
		_map_spots.append({
			"id": pid,
			"at": at,
			"label": label_at,
			"half": Vector2(maxf(place_name.length() * em * 0.34, 0.03), em * 0.9),
		})
		lab.position = Vector3(label_at.x, label_at.y, 0.0)
		lab.font_size = 40
		lab.pixel_size = 0.00105
		lab.modulate = Color(0.98, 0.95, 0.88)
		lab.outline_modulate = Color(0.1, 0.07, 0.05)
		lab.outline_size = 6
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.shaded = false
		lab.double_sided = false
		lab.rotation.y = PI
		names.add_child(lab)
	_add_map_mesh(host, "Places", marks, -0.034)
	var title := Label3D.new()
	title.text = "CITY"
	title.position = Vector3(0.0, _MAP_SHEET.y * 0.5 - 0.07, -0.02)
	title.font_size = 72
	title.pixel_size = 0.0014
	title.modulate = Color(0.22, 0.14, 0.08)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.shaded = false
	title.rotation.y = PI
	host.add_child(title)


## The place under the pointer while the sheet is held up. Empty when the click misses every name and marker.
func _map_poi_at(screen_pos: Vector2) -> String:
	if _map == null or _map_blend < 0.9:
		return ""
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return ""
	var body := hit.get("collider") as Node
	if body != _map:
		return ""
	var local := _map.to_local(hit["position"])
	var at := Vector2(local.x, local.y)
	var best := ""
	var best_d := 1000.0
	for spot: Dictionary in _map_spots:
		var marker: Vector2 = spot["at"]
		var label: Vector2 = spot["label"]
		var half: Vector2 = spot["half"]
		var outside := Vector2(maxf(absf(at.x - label.x) - half.x, 0.0), maxf(absf(at.y - label.y) - half.y, 0.0))
		var on_label := outside.length() <= 0.008
		var marker_d := at.distance_to(marker)
		var on_marker := marker_d <= 0.022
		if not on_label and not on_marker:
			continue
		var dist := marker_d if on_marker and not on_label else outside.length()
		if dist < best_d:
			best_d = dist
			best = str(spot["id"])
	return best


func _map_number_key(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return false
	var number := -1
	match key.keycode:
		KEY_0, KEY_KP_0:
			number = 0
		KEY_1, KEY_KP_1:
			number = 1
		KEY_2, KEY_KP_2:
			number = 2
		KEY_3, KEY_KP_3:
			number = 3
		_:
			return false
	if number < 0 or number >= _MAP_NUMBER_ID.size():
		return false
	_choose_map_poi(_MAP_NUMBER_ID[number])
	return true


func _choose_map_poi(poi: String) -> void:
	if not _map_inspecting:
		return
	if poi == GameState.POI_GARAGE:
		_show_map_here()
		return
	var scene := _scene_for_poi(poi)
	if scene.is_empty():
		return
	_hang_map()
	_start_drive_out(scene)


func _show_map_here() -> void:
	if _say_bubble == null:
		return
	_map_here = true
	_say_after = Callable()
	_say_bubble.call(&"set_line", "You're here bud!", Vector2(380, 56), 26)
	_say_bubble.visible = true


func _set_map_hint_visible(show: bool) -> void:
	if _map_hint != null:
		_map_hint.visible = show
	if not show and _map_here:
		_map_here = false
		if _say_bubble != null:
			_say_bubble.visible = false
		_say_after = Callable()


func _map_point(layout: Dictionary, x: float, y: float) -> Vector2:
	var drawn := float(layout["scale"])
	return Vector2((x - float(layout["cx"])) * drawn, (y - float(layout["cy"])) * drawn + float(layout["shift_y"]))


func _map_quad(st: SurfaceTool, center: Vector2, along: Vector2, across: Vector2, color: Color) -> void:
	var bl := Vector3(center.x - along.x - across.x, center.y - along.y - across.y, 0.0)
	var br := Vector3(center.x + along.x - across.x, center.y + along.y - across.y, 0.0)
	var tr := Vector3(center.x + along.x + across.x, center.y + along.y + across.y, 0.0)
	var tl := Vector3(center.x - along.x + across.x, center.y - along.y + across.y, 0.0)
	st.set_color(color)
	st.set_normal(Vector3(0.0, 0.0, -1.0))
	st.add_vertex(bl)
	st.add_vertex(br)
	st.add_vertex(tr)
	st.add_vertex(bl)
	st.add_vertex(tr)
	st.add_vertex(tl)


func _add_map_mesh(host: Node3D, node_name: String, st: SurfaceTool, z: float) -> void:
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.0, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)


func _map_board(host: Node3D, size: Vector3, pos: Vector3, color: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)


func _bring_map_forward() -> void:
	if _map == null or _map_inspecting:
		return
	_hang_calendar()
	_hide_garage_overlays()
	_map_inspecting = true
	_set_map_hint_visible(true)
	if _map_tween != null:
		_map_tween.kill()
	_map_tween = create_tween()
	_map_tween.tween_property(self, "_map_blend", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hang_map() -> void:
	if not _map_inspecting:
		return
	_map_inspecting = false
	_set_map_hint_visible(false)
	if _map_tween != null:
		_map_tween.kill()
	_map_tween = create_tween()
	_map_tween.tween_property(self, "_map_blend", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _update_map_transform() -> void:
	if _map == null:
		return
	if _map_blend <= 0.0001:
		if not _map_inspecting:
			_map.global_transform = _map_home
		return
	var face := _map_home.interpolate_with(_map_face_transform(), _map_blend)
	var grown := lerpf(1.0, _MAP_INSPECT_SCALE, _map_blend)
	face.basis = face.basis.orthonormalized().scaled(Vector3(grown, grown, grown))
	_map.global_transform = face


func _map_face_transform() -> Transform3D:
	var cam_xf := _camera.global_transform
	var pos := cam_xf.origin - cam_xf.basis.z * _MAP_INSPECT_DISTANCE
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
