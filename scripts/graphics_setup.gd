extends CanvasLayer

## The graphics page, opened from all three settings menus: fullscreen, and what the driving HUD
## shows and how big. A preview of the race screen beside it changes as the settings do. Sits over
## the whole screen, and takes the menu's keys while it is up.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _DrivingHud := preload("res://scripts/driving_hud.gd")
const _RpmMeter := preload("res://scripts/rpm_meter.gd")
const _Player := preload("res://scripts/player_race_car.gd")
const _Controller := preload("res://scripts/controller.gd")

const SIZE_HELP := "Shrinks the whole panel in the corner, text and spacing alike, and the rev counter with it."
## The preview is the race screen at half size.
const PREVIEW_SCALE := 0.5
const SCREEN := Vector2(1280.0, 720.0)
const PREVIEW_RPM := 3600.0

var _nav := _MenuNav.new()
var _host: Node
var _page: Control
var _return_focus: Control
var _fullscreen: CheckBox
var _size_label: Label
var _size: HSlider
var _shows: Dictionary[String, CheckBox] = {}
var _back_button: Button
var _preview_panel: PanelContainer
var _preview_meter: Control


## Hides the settings page behind it, and goes back to the button that opened it.
func open(host: Node, page: Control, return_focus: Control) -> void:
	_host = host
	_page = page
	_return_focus = return_focus
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build()
	_page.visible = false
	host.add_child(self)
	var items: Array = [_fullscreen, _size]
	for item: String in _DrivingHud.ITEMS:
		items.append(_shows[item])
	items.append(_back_button)
	_nav.setup(items)
	_update_preview.call_deferred()


func _build() -> void:
	var back := ColorRect.new()
	back.color = Color(0.08, 0.09, 0.12, 1.0)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	margin.add_child(columns)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	columns.add_child(box)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 28)
	title.text = "Graphics"
	box.add_child(title)
	_fullscreen = CheckBox.new()
	_fullscreen.text = "Fullscreen"
	_fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	box.add_child(_fullscreen)
	_size_label = Label.new()
	box.add_child(_size_label)
	_size = HSlider.new()
	_size.custom_minimum_size = Vector2(320.0, 0.0)
	_size.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_size.min_value = _DrivingHud.SMALLEST
	_size.max_value = 1.0
	_size.step = _DrivingHud.STEP
	_size.set_value_no_signal(GameState.hud_size)
	_size.value_changed.connect(_on_size_changed)
	box.add_child(_size)
	var size_help := Label.new()
	size_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size_help.custom_minimum_size = Vector2(320.0, 0.0)
	size_help.modulate = Color(1.0, 1.0, 1.0, 0.7)
	size_help.text = SIZE_HELP
	box.add_child(size_help)
	_show_size()
	var shows_title := Label.new()
	shows_title.text = "Show on the driving HUD"
	box.add_child(shows_title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	box.add_child(grid)
	for item: String in _DrivingHud.ITEMS:
		var check := CheckBox.new()
		check.text = _DrivingHud.item_label(item)
		check.set_pressed_no_signal(GameState.hud_shows(item))
		check.toggled.connect(_on_show_toggled.bind(item))
		grid.add_child(check)
		_shows[item] = check
	_back_button = Button.new()
	_back_button.custom_minimum_size = Vector2(200.0, 40.0)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back_button.text = "Back"
	_back_button.pressed.connect(_close)
	box.add_child(_back_button)
	columns.add_child(_build_preview())


## The race screen at half size: a sky, a road, the panel in its corner, and the rev counter.
func _build_preview() -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.text = "Preview"
	holder.add_child(caption)
	var frame := Control.new()
	frame.custom_minimum_size = SCREEN * PREVIEW_SCALE
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	var screen := Control.new()
	screen.size = SCREEN
	screen.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(screen)
	var sky := ColorRect.new()
	sky.color = Color(0.42, 0.52, 0.66, 1.0)
	sky.size = Vector2(SCREEN.x, SCREEN.y * 0.32)
	screen.add_child(sky)
	var road := ColorRect.new()
	road.color = Color(0.25, 0.26, 0.29, 1.0)
	road.position = Vector2(0.0, SCREEN.y * 0.32)
	road.size = Vector2(SCREEN.x, SCREEN.y * 0.68)
	screen.add_child(road)
	_preview_panel = PanelContainer.new()
	_preview_panel.anchor_left = 1.0
	_preview_panel.anchor_right = 1.0
	_preview_panel.offset_left = -320.0
	_preview_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	screen.add_child(_preview_panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_preview_panel.add_child(margin)
	var lines := VBoxContainer.new()
	lines.name = "VBox"
	lines.add_theme_constant_override("separation", 6)
	margin.add_child(lines)
	var sample: Dictionary[String, String] = {
		"OppLabel": "Opponent: Rival (Corvette 1956)",
		"SpeedLabel": "Speed: %s" % GameState.speed_text(96.0),
		"GearLabel": "Gear: 2 / 4",
		"DamageLabel": "Damage: 0% · Rival: 0%",
		"DistLabel": "To finish: %s" % GameState.race_distance_text(312.0),
		"TimeLabel": "Time: 14.20 s",
		"HintLabel": _Controller.driving_hint(false),
	}
	for line_name: String in sample:
		var line := Label.new()
		line.name = line_name
		line.text = sample[line_name]
		lines.add_child(line)
	_preview_meter = Control.new()
	_preview_meter.set_script(_RpmMeter)
	_preview_meter.anchor_left = 0.5
	_preview_meter.anchor_right = 0.5
	_preview_meter.anchor_top = 1.0
	_preview_meter.anchor_bottom = 1.0
	_preview_meter.offset_left = -180.0
	_preview_meter.offset_top = -196.0
	_preview_meter.offset_right = 180.0
	_preview_meter.offset_bottom = -16.0
	_preview_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_preview_meter)
	_preview_meter.call(&"set_reading", PREVIEW_RPM, _Player.RPM_SHIFT_START, _Player.RPM_REDLINE, _Player.RPM_CRITICAL, false, 96.0, "2", GameState.imperial_units)
	return holder


func _update_preview() -> void:
	(_preview_panel.get_node("Margin/VBox/HintLabel") as Control).visible = GameState.hud_shows(_DrivingHud.HINTS)
	_DrivingHud.apply(_preview_panel, _preview_meter)


func _exit_tree() -> void:
	if _host != null and _host.has_method(&"refresh_hud"):
		_host.call(&"refresh_hud")


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not _nav.handle_event(self, event) and event.is_action_pressed(&"ui_cancel"):
		_close()
	get_viewport().set_input_as_handled()


func _show_size() -> void:
	_size_label.text = "Driving HUD size: %d%%" % roundi(GameState.hud_size * 100.0)


func _on_fullscreen_toggled(pressed: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _on_show_toggled(pressed: bool, item: String) -> void:
	GameState.hud_items[item] = pressed
	_update_preview()


func _on_size_changed(value: float) -> void:
	GameState.hud_size = value
	_show_size()
	_update_preview()


func _close() -> void:
	GameState.save_settings()
	_page.visible = true
	_return_focus.grab_focus()
	queue_free()
