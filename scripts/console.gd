extends Control

## A one-line command prompt along the bottom of the screen, opened with ~ on the main
## menu. The opener registers its commands with `add_command()`. A command's callable
## returns "" when it has done its job, which closes the prompt, or a line to show
## above the prompt, which keeps it open. `help` lists the commands. ~ or Esc closes it
## and emits `closed`; the opener frees it.

signal closed

const _CREAM := Color(0.95, 0.9, 0.78, 1)

## How far above the bottom edge the prompt sits, to leave a bar there in view.
var bottom_margin: float = 0.0
var _commands: Dictionary = {}
var _line: LineEdit
var _output: Label


func add_command(command: String, about: String, run: Callable) -> void:
	_commands[command.to_lower()] = {"about": about, "run": run}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _panel_style())
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_top -= bottom_margin
	panel.offset_bottom -= bottom_margin
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	panel.add_child(box)
	_output = Label.new()
	_output.add_theme_font_size_override(&"font_size", 16)
	_output.add_theme_color_override(&"font_color", _CREAM)
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output.visible = false
	box.add_child(_output)
	var row := HBoxContainer.new()
	box.add_child(row)
	var prompt := Label.new()
	prompt.text = ">"
	prompt.add_theme_font_size_override(&"font_size", 18)
	prompt.add_theme_color_override(&"font_color", _CREAM)
	row.add_child(prompt)
	_line = LineEdit.new()
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.placeholder_text = "Type a command (help lists them)"
	_line.add_theme_font_size_override(&"font_size", 18)
	_line.add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
	_line.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	_line.caret_blink = true
	_line.keep_editing_on_text_submit = true
	_line.text_submitted.connect(_on_submitted)
	row.add_child(_line)
	_line.grab_focus.call_deferred()


## Before the line edit sees it, so ~ closes the prompt instead of being typed.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE or is_toggle_key(key):
		get_viewport().set_input_as_handled()
		closed.emit()


## ~ (the key left of 1, with or without shift) opens and closes the prompt.
static func is_toggle_key(key: InputEventKey) -> bool:
	return key.physical_keycode == KEY_QUOTELEFT or key.keycode == KEY_QUOTELEFT or key.unicode == 0x7e or key.unicode == 0x60


func _on_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	_line.clear()
	if trimmed.is_empty():
		return
	var split_at := trimmed.find(" ")
	var tab_at := trimmed.find("\t")
	if tab_at >= 0 and (split_at < 0 or tab_at < split_at):
		split_at = tab_at
	var command := (trimmed if split_at < 0 else trimmed.left(split_at)).to_lower()
	var arg := "" if split_at < 0 else trimmed.substr(split_at + 1).strip_edges()
	if command == "help":
		_show(_help())
		return
	if not _commands.has(command):
		_show("Unknown command: %s. Type help for the list." % command)
		return
	var entry: Dictionary = _commands[command]
	var run: Callable = entry["run"]
	var reply := ""
	if run.get_argument_count() > 0:
		reply = str(run.call(arg))
	elif not arg.is_empty():
		_show("Unknown command: %s. Type help for the list." % trimmed.to_lower())
		return
	else:
		reply = str(run.call())
	if reply.is_empty():
		closed.emit()
	else:
		_show(reply)


func _help() -> String:
	var lines: Array[String] = ["Commands:"]
	var names: Array = _commands.keys()
	names.sort()
	for command: String in names:
		var entry: Dictionary = _commands[command]
		lines.append("  %s - %s" % [command, str(entry["about"])])
	lines.append("  help - this list")
	return "\n".join(lines)


func _show(text: String) -> void:
	_output.text = text
	_output.visible = true


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.82)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.border_width_top = 2
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
