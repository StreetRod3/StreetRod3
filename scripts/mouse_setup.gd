extends CanvasLayer

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _ControlsTabs := preload("res://scripts/controls_tabs.gd")
const _MouseDrive := preload("res://scripts/mouse_drive.gd")

var _nav := _MenuNav.new()
var _tabs: TabBar
var _page: Control
var _return_focus: Control
var _steering_label: Label
var _pedals_label: Label
var _items: Array = []


func open(host: Node, page: Control, return_focus: Control) -> void:
	_page = page
	_return_focus = return_focus
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build()
	_page.visible = false
	host.add_child(self)
	_nav.setup(_items)


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.09, 0.12, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_tabs = _ControlsTabs.build(_ControlsTabs.MOUSE, self)
	box.add_child(_tabs)
	var help := Label.new()
	help.text = "Move left or right to steer; move up to accelerate and down to brake. Move back to neutral, or left-click to reset steering and right-click to reset acceleration / brake. Both axes reset when driving resumes."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	var steer_check := CheckBox.new()
	steer_check.name = "MouseSteering"
	steer_check.text = "Mouse steering"
	steer_check.button_pressed = GameState.mouse_steering_enabled
	steer_check.toggled.connect(_set_steering)
	box.add_child(steer_check)
	_steering_label = Label.new()
	box.add_child(_steering_label)
	var steer_slider := _slider(GameState.mouse_steering_sensitivity)
	steer_slider.name = "MouseSteeringSensitivity"
	steer_slider.value_changed.connect(_set_steering_sensitivity)
	box.add_child(steer_slider)
	var pedals_check := CheckBox.new()
	pedals_check.name = "MousePedals"
	pedals_check.text = "Mouse acceleration and brake"
	pedals_check.button_pressed = GameState.mouse_pedals_enabled
	pedals_check.toggled.connect(_set_pedals)
	box.add_child(pedals_check)
	_pedals_label = Label.new()
	box.add_child(_pedals_label)
	var pedals_slider := _slider(GameState.mouse_pedals_sensitivity)
	pedals_slider.name = "MousePedalsSensitivity"
	pedals_slider.value_changed.connect(_set_pedals_sensitivity)
	box.add_child(pedals_slider)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 36)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_close)
	box.add_child(back)
	_show_sensitivity()
	_items = [_tabs, steer_check, steer_slider, pedals_check, pedals_slider, back]


func _slider(value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = _MouseDrive.SENSITIVITY_MIN
	slider.max_value = _MouseDrive.SENSITIVITY_MAX
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(320, 0)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	slider.set_value_no_signal(value)
	return slider


func _show_sensitivity() -> void:
	_steering_label.text = "Steering sensitivity: %.2f" % GameState.mouse_steering_sensitivity
	_pedals_label.text = "Acceleration / brake sensitivity: %.2f" % GameState.mouse_pedals_sensitivity


func _set_steering(enabled: bool) -> void:
	GameState.mouse_steering_enabled = enabled


func _set_pedals(enabled: bool) -> void:
	GameState.mouse_pedals_enabled = enabled


func _set_steering_sensitivity(value: float) -> void:
	GameState.mouse_steering_sensitivity = value
	_show_sensitivity()


func _set_pedals_sensitivity(value: float) -> void:
	GameState.mouse_pedals_sensitivity = value
	_show_sensitivity()


func focus_tabs() -> void:
	_tabs.grab_focus()


func _input(event: InputEvent) -> void:
	if _ControlsTabs.handle_key(_tabs, event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _nav.handle_event(self, event) and event.is_action_pressed(&"ui_cancel"):
		_close()
	get_viewport().set_input_as_handled()


func _close() -> void:
	GameState.save_settings()
	_page.visible = true
	_return_focus.grab_focus()
	queue_free()
