extends CanvasLayer

## The shifter page, opened from all three settings menus: click a gear, then move the
## shifter into it. Sits over the whole screen, and takes the menu's keys while it is up.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _Shifter := preload("res://scripts/shifter.gd")

const HELP := "Click a gear, then put the shifter in that gear. For paddles or a sequential shifter, set Shift up and Shift down instead. A car with fewer gears uses its top gear for the rest."

var _nav := _MenuNav.new()
var _page: Control
var _return_focus: Control
var _rows: Dictionary = {}
var _status: Label
var _back_button: Button
var _clear_button: Button
## The action waiting for a button, or empty.
var _listening: String = ""


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
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 28)
	title.text = "Shifter"
	box.add_child(title)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = HELP
	box.add_child(help)
	for action: String in _Shifter.actions():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size = Vector2(130.0, 0.0)
		label.text = _Shifter.action_label(action)
		row.add_child(label)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_listen.bind(action))
		row.add_child(button)
		box.add_child(row)
		_rows[action] = button
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


func _nav_items() -> Array:
	var items: Array = []
	for action: String in _Shifter.actions():
		items.append(_rows[action])
	items.append(_back_button)
	items.append(_clear_button)
	return items


func _input(event: InputEvent) -> void:
	if _listening.is_empty():
		return
	if event is InputEventJoypadButton and event.pressed:
		_Shifter.bind(_listening, event.device, int(event.button_index))
		_listen_done()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				_Shifter.unbind(_listening)
			_listen_done()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not _nav.handle_event(self, event) and event.is_action_pressed(&"ui_cancel"):
		_close()
	get_viewport().set_input_as_handled()


func _listen(action: String) -> void:
	_listening = action
	_refresh()


func _listen_done() -> void:
	var button: Button = _rows[_listening]
	_listening = ""
	button.grab_focus()
	_refresh()


func _refresh() -> void:
	for action: String in _rows:
		var button: Button = _rows[action]
		button.text = "Waiting..." if action == _listening else _binding_text(action)
	if not _listening.is_empty():
		_status.text = "Move the shifter into %s, or press the button for it. Delete clears it, and any other key cancels." % _Shifter.action_label(_listening)
		return
	var found: Array[String] = []
	for device: int in Input.get_connected_joypads():
		found.append(Input.get_joy_name(device))
	if found.is_empty():
		_status.text = "No wheel or shifter found. Plug one in and press one of its buttons."
	else:
		_status.text = "Found: %s" % ", ".join(found)


func _binding_text(action: String) -> String:
	var binding: Variant = GameState.shifter_bindings.get(action)
	if not binding is Dictionary:
		return "Not set"
	var text := "%s, button %d" % [str(binding.get("name", "")), int(binding.get("button", 0))]
	return text if _Shifter.is_plugged_in(action) else text + " (not plugged in)"


func _on_clear_pressed() -> void:
	_listening = ""
	_Shifter.clear()
	_refresh()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh()


func _close() -> void:
	GameState.save_settings()
	_page.visible = true
	_return_focus.grab_focus()
	queue_free()
