extends CanvasLayer

## The wheel and shifter page, opened from all three settings menus: click a row, then move
## that control. Sits over the whole screen, and takes the menu's keys while it is up.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _Controller := preload("res://scripts/controller.gd")

const HELP := "Click a row, then move that control. A car with fewer gears uses its top gear for the rest. Paddles or a sequential shifter go on Shift up and Shift down. Keyboard and gamepad are under Controls."
## An axis has to move this far, and come back to within this share of that, to be taken.
const AXIS_MIN_TRAVEL := 0.15
const AXIS_BACK_SHARE := 0.25
## It is taken once it has sat still this long, in ms, and this close to one spot.
const AXIS_SETTLE_MS := 250
const AXIS_STILL := 0.01
const SENSITIVITY_MIN := 1.0
const SENSITIVITY_MAX := 6.0
const SENSITIVITY_STEP := 0.5

var _nav := _MenuNav.new()
var _page: Control
var _return_focus: Control
var _rows: Dictionary = {}
var _status: Label
var _sensitivity_label: Label
var _sensitivity: HSlider
var _back_button: Button
var _clear_button: Button
## The action waiting for an input, or empty.
var _listening: String = ""
## The button that answered, still held. It stays quiet until it comes up, or binding Pause to
## it would count as pressing Pause and close this page.
var _answer_device: int = -1
var _answer_button: int = -1
## Where each axis started, the farthest it has gone, and where it has come back to, while listening.
var _travel: Dictionary = {}


## Hides the settings page behind it, and goes back to the button that opened it.
func open(host: Node, page: Control, return_focus: Control) -> void:
	_page = page
	_return_focus = return_focus
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build()
	_page.visible = false
	host.add_child(self)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_refresh()
	_nav.setup(_nav_items())


func _build() -> void:
	var back := ColorRect.new()
	back.color = Color(0.08, 0.09, 0.12, 1.0)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 28)
	title.text = "Wheel and shifter"
	box.add_child(title)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = HELP
	box.add_child(help)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	var wheel_column := _add_column(columns)
	_add_rows(wheel_column, _Controller.wheel_actions())
	_add_sensitivity(wheel_column)
	_add_rows(_add_column(columns), _Controller.shifter_actions())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_back_button = Button.new()
	_back_button.custom_minimum_size = Vector2(160.0, 36.0)
	_back_button.text = "Back"
	_back_button.pressed.connect(_close)
	buttons.add_child(_back_button)
	_clear_button = Button.new()
	_clear_button.custom_minimum_size = Vector2(160.0, 36.0)
	_clear_button.text = "Clear all"
	_clear_button.pressed.connect(_on_clear_pressed)
	buttons.add_child(_clear_button)
	box.add_child(buttons)


func _add_column(columns: HBoxContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.0
	column.add_theme_constant_override("separation", 6)
	columns.add_child(column)
	return column


func _add_rows(column: VBoxContainer, actions: Array[String]) -> void:
	for action: String in actions:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size = Vector2(100.0, 0.0)
		label.text = _Controller.action_label(action)
		row.add_child(label)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.pressed.connect(_listen.bind(action))
		row.add_child(button)
		column.add_child(row)
		_rows[action] = button


func _add_sensitivity(column: VBoxContainer) -> void:
	_sensitivity_label = Label.new()
	column.add_child(_sensitivity_label)
	_sensitivity = HSlider.new()
	_sensitivity.min_value = SENSITIVITY_MIN
	_sensitivity.max_value = SENSITIVITY_MAX
	_sensitivity.step = SENSITIVITY_STEP
	_sensitivity.set_value_no_signal(GameState.steer_sensitivity)
	_sensitivity.value_changed.connect(_on_sensitivity_changed)
	column.add_child(_sensitivity)
	_show_sensitivity()


func _nav_items() -> Array:
	var items: Array = []
	for action: String in _Controller.wheel_actions():
		items.append(_rows[action])
	items.append(_sensitivity)
	for action: String in _Controller.shifter_actions():
		items.append(_rows[action])
	items.append(_back_button)
	items.append(_clear_button)
	return items


func _exit_tree() -> void:
	_Controller.capturing = false


func _input(event: InputEvent) -> void:
	if _listening.is_empty():
		return
	if event is InputEventJoypadButton:
		if event.pressed and _Controller.takes_button(_listening):
			_Controller.bind_button(_listening, event.device, int(event.button_index))
			_answer_device = event.device
			_answer_button = int(event.button_index)
			_listen_done()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		if _Controller.takes_axis(_listening):
			_note_axis(event.device, int(event.axis), event.axis_value)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				_Controller.unbind(_listening)
			_listen_done()
		get_viewport().set_input_as_handled()


## An axis is taken once it has moved a good way and come back to rest, which gives how far it
## goes and where it rests. Noise on the others never gets that far. Its first reading will not
## do for the rest, since a quick press has already left the top by then.
func _note_axis(device: int, axis: int, value: float) -> void:
	var seen: Dictionary = _travel.get_or_add(Vector2i(device, axis), {"first": value, "far": value})
	var first: float = seen["first"]
	if absf(value - first) > absf(float(seen["far"]) - first):
		seen["far"] = value
	var span := absf(float(seen["far"]) - first)
	# Coming back past the first reading still counts as back.
	var out := (value - first) * signf(float(seen["far"]) - first)
	if span < AXIS_MIN_TRAVEL or out > span * AXIS_BACK_SHARE:
		seen.erase("back_ms")
	elif not seen.has("back_ms") or absf(value - float(seen["rest"])) > AXIS_STILL:
		seen["rest"] = value
		seen["back_ms"] = Time.get_ticks_msec()


func _take_settled_axis() -> void:
	for key: Vector2i in _travel:
		var seen: Dictionary = _travel[key]
		if seen.has("back_ms") and Time.get_ticks_msec() - int(seen["back_ms"]) >= AXIS_SETTLE_MS:
			_Controller.bind_axis(_listening, key.x, key.y, seen["rest"], seen["far"])
			_listen_done()
			return


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not _nav.handle_event(self, event) and event.is_action_pressed(&"ui_cancel"):
		_close()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _listening.is_empty():
		_take_settled_axis()
	elif _answer_button >= 0 and not Input.is_joy_button_pressed(_answer_device, _answer_button as JoyButton):
		_answer_button = -1
		_Controller.capturing = false
	_refresh_rows()


func _listen(action: String) -> void:
	_listening = action
	_answer_button = -1
	_Controller.capturing = true
	_travel.clear()
	_refresh()


func _listen_done() -> void:
	var button: Button = _rows[_listening]
	_listening = ""
	_Controller.capturing = _answer_button >= 0
	button.grab_focus()
	_refresh()


func _refresh() -> void:
	_refresh_rows()
	if not _listening.is_empty():
		_status.text = "%s Delete clears it, and any other key cancels." % _listen_prompt()
		return
	var found: Array[String] = []
	for device: int in Input.get_connected_joypads():
		found.append(Input.get_joy_name(device))
	if found.is_empty():
		_status.text = "No wheel or shifter found. Plug one in and press one of its buttons."
	else:
		_status.text = "Found: %s" % ", ".join(found)


func _refresh_rows() -> void:
	for action: String in _rows:
		var button: Button = _rows[action]
		button.text = "Waiting..." if action == _listening else _binding_text(action)


func _listen_prompt() -> String:
	match _listening:
		_Controller.STEER:
			return "Turn the wheel to the right, then back to center."
		_Controller.THROTTLE, _Controller.BRAKE:
			return "Press the %s pedal all the way down, then let it go." % _Controller.action_label(_listening).to_lower()
		_Controller.HANDBRAKE:
			return "Pull the hand brake all the way, then let it go, or press its button."
		_Controller.CAMERA, _Controller.PAUSE:
			return "Press the button for %s." % _Controller.action_label(_listening).to_lower()
	return "Move the shifter into %s, or press the button for it." % _Controller.action_label(_listening)


func _binding_text(action: String) -> String:
	var binding: Variant = GameState.controller_bindings.get(action)
	if not binding is Dictionary:
		return "Not set"
	var name_text := str(binding.get("name", ""))
	if not _Controller.is_plugged_in(action):
		return "%s (not plugged in)" % name_text
	if not binding.has("axis"):
		if _Controller.pads().has(_Controller.device_of(action)):
			return "%s, %s" % [name_text, _Controller.button_name(int(binding.get("button", 0)) as JoyButton)]
		return "%s, button %d" % [name_text, int(binding.get("button", 0))]
	var reading := ""
	if action == _Controller.STEER:
		var steer := _Controller.steer()
		reading = "center" if roundi(absf(steer) * 100.0) == 0 else "%d%% %s" % [roundi(absf(steer) * 100.0), "left" if steer > 0.0 else "right"]
	else:
		reading = "%d%%" % roundi(_Controller.pedal(action) * 100.0)
	return "%s, axis %d: %s" % [name_text, int(binding.get("axis", 0)), reading]


func _show_sensitivity() -> void:
	_sensitivity_label.text = "Steering sensitivity: %.1f" % GameState.steer_sensitivity


func _on_sensitivity_changed(value: float) -> void:
	GameState.steer_sensitivity = value
	_show_sensitivity()


func _on_clear_pressed() -> void:
	_listening = ""
	_answer_button = -1
	_Controller.capturing = false
	_Controller.clear()
	_refresh()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh()


func _close() -> void:
	GameState.save_settings()
	_page.visible = true
	_return_focus.grab_focus()
	queue_free()
