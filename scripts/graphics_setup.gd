extends CanvasLayer

## The graphics page, opened from all three settings menus: fullscreen, and how much room the
## driving HUD takes. Sits over the whole screen, and takes the menu's keys while it is up.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _HudSize := preload("res://scripts/hud_size.gd")

var _nav := _MenuNav.new()
var _host: Node
var _page: Control
var _return_focus: Control
var _fullscreen: CheckBox
var _hints: CheckBox
var _size_label: Label
var _size: HSlider
var _back_button: Button


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
	_nav.setup([_fullscreen, _hints, _size, _back_button])


func _build() -> void:
	var back := ColorRect.new()
	back.color = Color(0.08, 0.09, 0.12, 1.0)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 28)
	title.text = "Graphics"
	box.add_child(title)
	_fullscreen = CheckBox.new()
	_fullscreen.text = "Fullscreen"
	_fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	box.add_child(_fullscreen)
	_hints = CheckBox.new()
	_hints.text = "Control hints on the driving HUD"
	_hints.set_pressed_no_signal(GameState.show_control_hints)
	_hints.toggled.connect(_on_hints_toggled)
	box.add_child(_hints)
	_size_label = Label.new()
	box.add_child(_size_label)
	_size = HSlider.new()
	_size.custom_minimum_size = Vector2(320.0, 0.0)
	_size.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_size.min_value = _HudSize.SMALLEST
	_size.max_value = 1.0
	_size.step = _HudSize.STEP
	_size.set_value_no_signal(GameState.hud_size)
	_size.value_changed.connect(_on_size_changed)
	box.add_child(_size)
	_show_size()
	_back_button = Button.new()
	_back_button.custom_minimum_size = Vector2(200.0, 40.0)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back_button.text = "Back"
	_back_button.pressed.connect(_close)
	box.add_child(_back_button)


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


func _on_hints_toggled(pressed: bool) -> void:
	GameState.show_control_hints = pressed


func _on_size_changed(value: float) -> void:
	GameState.hud_size = value
	_show_size()


func _close() -> void:
	GameState.save_settings()
	_page.visible = true
	_return_focus.grab_focus()
	queue_free()
