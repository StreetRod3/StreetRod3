extends CanvasLayer

## The keyboard and gamepad page, opened from all three settings menus: click a slot, then press
## what should do that job. Only driving controls change here. The menus stay as they are, so
## nobody can lock themselves out of this page.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _Controller := preload("res://scripts/controller.gd")
const _ControlsTabs := preload("res://scripts/controls_tabs.gd")

const HELP := "Click a slot, then press the key or gamepad control for it. Press the one already there to clear it. A control does one job, so using it again moves it."
const SLOTS := 2
## How far a stick or trigger has to go to answer, and how far back before it counts as let go.
const AXIS_ANSWER := 0.6
const AXIS_LET_GO := 0.3
const RUMBLE_STEP := 0.25
const RUMBLE_TEST_S := 0.25

var _nav := _MenuNav.new()
var _tabs: TabBar
var _host: Node
var _page: Control
var _return_focus: Control
## Each slot's button, by "action:kind:slot".
var _slots: Dictionary = {}
var _status: Label
var _rumble: HSlider
var _rumble_label: Label
var _back_button: Button
var _reset_button: Button
## The slot waiting for an input.
var _listen_action: String = ""
var _listen_keys: bool = true
var _listen_slot: int = 0
## The control that answered, still held, which does nothing until it is let go.
var _answer_device: int = -1
var _answer_button: int = -1
var _answer_axis: int = -1
var _answer_key: int = -1


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
	title.text = "Controls"
	box.add_child(title)
	_tabs = _ControlsTabs.build(_ControlsTabs.KEYS_AND_PAD, self)
	box.add_child(_tabs)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = HELP
	box.add_child(help)
	var grid := GridContainer.new()
	grid.columns = 1 + SLOTS * 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for heading: String in ["", "Keyboard", "", "Gamepad", ""]:
		var label := Label.new()
		label.text = heading
		grid.add_child(label)
	for action: String in _Controller.control_actions():
		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(110.0, 0.0)
		name_label.text = _Controller.control_label(action)
		grid.add_child(name_label)
		for keys: bool in [true, false]:
			for slot: int in SLOTS:
				var button := Button.new()
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.custom_minimum_size = Vector2(160.0, 0.0)
				button.clip_text = true
				button.pressed.connect(_listen.bind(action, keys, slot))
				grid.add_child(button)
				_slots[_slot_key(action, keys, slot)] = button
	_rumble_label = Label.new()
	box.add_child(_rumble_label)
	_rumble = HSlider.new()
	_rumble.custom_minimum_size = Vector2(320.0, 0.0)
	_rumble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_rumble.min_value = 0.0
	_rumble.max_value = 1.0
	_rumble.step = RUMBLE_STEP
	_rumble.set_value_no_signal(GameState.rumble_strength)
	_rumble.value_changed.connect(_on_rumble_changed)
	box.add_child(_rumble)
	_show_rumble()
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
	_reset_button = Button.new()
	_reset_button.custom_minimum_size = Vector2(160.0, 36.0)
	_reset_button.text = "Reset all"
	_reset_button.pressed.connect(_on_reset_pressed)
	buttons.add_child(_reset_button)
	box.add_child(buttons)


func _slot_key(action: String, keys: bool, slot: int) -> String:
	return "%s:%s:%d" % [action, "key" if keys else "pad", slot]


func _nav_items() -> Array:
	var items: Array = [_tabs]
	for action: String in _Controller.control_actions():
		for keys: bool in [true, false]:
			for slot: int in SLOTS:
				var button: Button = _slots[_slot_key(action, keys, slot)]
				if not button.disabled:
					items.append(button)
	items.append(_rumble)
	items.append(_back_button)
	items.append(_reset_button)
	return items


func _exit_tree() -> void:
	_Controller.capturing = false
	if _host != null and _host.has_method(&"refresh_control_hint"):
		_host.call(&"refresh_control_hint")


## For a tab change, which opens this page in place of the other.
func focus_tabs() -> void:
	_tabs.grab_focus()


func _input(event: InputEvent) -> void:
	if _ControlsTabs.handle_key(_tabs, event):
		get_viewport().set_input_as_handled()
		return
	if _listen_action.is_empty():
		return
	if event is InputEventKey:
		_on_listen_key(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		if event.pressed and Input.is_joy_known(event.device):
			_on_listen_pad_button(event.device, int(event.button_index))
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		if not _listen_keys and Input.is_joy_known(event.device) and absf(event.axis_value) >= AXIS_ANSWER:
			_answer_device = event.device
			_answer_axis = int(event.axis)
			_Controller.set_pad(_listen_action, _listen_slot, {"axis": int(event.axis), "dir": 1 if event.axis_value > 0.0 else -1})
			_listen_done()
		get_viewport().set_input_as_handled()


func _on_listen_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	var code := int(event.keycode) if event.keycode != KEY_NONE else int(event.physical_keycode)
	if code == KEY_ESCAPE:
		_listen_done()
	elif code == KEY_DELETE or code == KEY_BACKSPACE:
		_clear_listening_slot()
		_listen_done()
	elif _listen_keys:
		_answer_key = code
		_Controller.set_key(_listen_action, _listen_slot, code)
		_listen_done()
	else:
		_listen_done()


## On a keyboard slot a gamepad button can only back out, or a pad on its own could not leave.
func _on_listen_pad_button(device: int, button: int) -> void:
	_answer_device = device
	_answer_button = button
	if not _listen_keys:
		_Controller.set_pad(_listen_action, _listen_slot, {"button": button})
	_listen_done()


func _clear_listening_slot() -> void:
	if _listen_keys:
		_Controller.clear_key(_listen_action, _listen_slot)
	else:
		_Controller.clear_pad(_listen_action, _listen_slot)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not _nav.handle_event(self, event) and event.is_action_pressed(&"ui_cancel"):
		_close()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _listen_action.is_empty():
		return
	var let_go := false
	if _answer_button >= 0:
		let_go = not Input.is_joy_button_pressed(_answer_device, _answer_button as JoyButton)
	elif _answer_axis >= 0:
		let_go = absf(Input.get_joy_axis(_answer_device, _answer_axis as JoyAxis)) < AXIS_LET_GO
	elif _answer_key >= 0:
		let_go = not Input.is_key_pressed(_answer_key as Key)
	if let_go:
		_clear_answer()
		_Controller.capturing = false


func _listen(action: String, keys: bool, slot: int) -> void:
	_listen_action = action
	_listen_keys = keys
	_listen_slot = slot
	_clear_answer()
	_Controller.capturing = true
	_refresh()


func _listen_done() -> void:
	var button: Button = _slots[_slot_key(_listen_action, _listen_keys, _listen_slot)]
	_listen_action = ""
	_Controller.capturing = _answer_button >= 0 or _answer_axis >= 0 or _answer_key >= 0
	button.grab_focus()
	_refresh()


func _clear_answer() -> void:
	_answer_button = -1
	_answer_axis = -1
	_answer_key = -1


func _refresh() -> void:
	for action: String in _Controller.control_actions():
		for keys: bool in [true, false]:
			for slot: int in SLOTS:
				_refresh_slot(action, keys, slot)
	if not _listen_action.is_empty():
		var what := "key" if _listen_keys else "gamepad control"
		_status.text = "Press the %s for %s. Delete clears the slot, and Esc cancels." % [what, _Controller.control_label(_listen_action).to_lower()]
		return
	var found: Array[String] = []
	for device: int in _Controller.pads():
		found.append(Input.get_joy_name(device))
	_status.text = "Gamepad: %s" % ", ".join(found) if not found.is_empty() else "No gamepad found. Plug one in and press one of its buttons."


func _refresh_slot(action: String, keys: bool, slot: int) -> void:
	var button: Button = _slots[_slot_key(action, keys, slot)]
	if action == _listen_action and keys == _listen_keys and slot == _listen_slot:
		button.text = "Waiting..."
		return
	# Esc always pauses, so a bad remap can never trap anyone in a race.
	if keys and action == _Controller.PAUSE and slot == 0:
		button.text = "Esc"
		button.disabled = true
		return
	button.text = _Controller.key_slot_name(action, slot) if keys else _Controller.pad_slot_name(action, slot)


func _show_rumble() -> void:
	if GameState.rumble_strength <= 0.0:
		_rumble_label.text = "Rumble: off"
	else:
		_rumble_label.text = "Rumble: %d%%" % roundi(GameState.rumble_strength * 100.0)


func _on_rumble_changed(value: float) -> void:
	GameState.rumble_strength = value
	_show_rumble()
	for device: int in _Controller.pads():
		Input.start_joy_vibration(device, value, value, RUMBLE_TEST_S)


func _on_reset_pressed() -> void:
	_listen_action = ""
	_clear_answer()
	_Controller.capturing = false
	_Controller.reset_controls()
	_refresh()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh()


func _close() -> void:
	GameState.save_settings()
	_page.visible = true
	_return_focus.grab_focus()
	queue_free()
