extends Control

## The save slot list, over whatever screen opened it: one row per slot with the car,
## cash, how many cars and when it was saved. Saving over a slot that has a save takes
## a second click. Emits `chosen` with the slot, or `closed` when backed out of; the
## opener does the saving or loading and frees the panel.

signal chosen(slot: int)
signal closed

const _MenuNav := preload("res://scripts/menu_nav.gd")

const _CREAM := Color(0.95, 0.9, 0.78, 1)
const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Saving (rows with a save ask before being saved over) or loading (empty rows are off).
var saving: bool = false

var _rows: Array[Button] = []
var _back: Button
var _hint: Label
var _confirm_slot: int = 0
var _nav = _MenuNav.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	panel.add_child(box)
	box.add_child(_label("Save game" if saving else "Load game", 24))
	_hint = _label("", 16)
	box.add_child(_hint)
	for slot in range(1, GameState.SAVE_SLOTS + 1):
		var row := Button.new()
		row.custom_minimum_size = Vector2(620, 40)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.pressed.connect(_on_row_pressed.bind(slot))
		box.add_child(row)
		_rows.append(row)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(0, 40)
	_back.pressed.connect(_close)
	box.add_child(_back)
	_refresh()
	var nav_items: Array = []
	for row in _rows:
		nav_items.append(row)
	nav_items.append(_back)
	_nav.setup(nav_items)
	_nav.select(_first_row())


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_close()
		else:
			_nav.handle_event(self, event)
		# Nothing behind the list gets keys while it is up.
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var any := false
	for i in _rows.size():
		var slot := i + 1
		var info := GameState.save_slot_info(slot)
		var row := _rows[i]
		any = any or not info.is_empty()
		if info.is_empty():
			row.text = "%d.   — empty —" % slot
			row.disabled = not saving
		elif saving and slot == _confirm_slot:
			row.text = "%d.   Click again to save over %s" % [slot, str(info["car_name"])]
			row.disabled = false
		else:
			row.text = "%d.   %s" % [slot, _describe(info)]
			if slot == GameState.save_slot:
				row.text += "   (this game)"
			row.disabled = false
	if saving:
		_hint.text = "Pick a slot to save to."
	else:
		_hint.text = "Pick a save to load." if any else "There are no saves yet."


func _describe(info: Dictionary) -> String:
	var cars := int(info.get("cars", 0))
	return "%s  ·  $%d  ·  %d car%s  ·  %s" % [
		str(info.get("car_name", "")),
		int(info.get("money", 0)),
		cars,
		"" if cars == 1 else "s",
		_when(int(info.get("saved_at", 0))),
	]


## A save time as local date and time, "Oct 31 2026, 14:22".
static func _when(unix: int) -> String:
	if unix <= 0:
		return "unknown time"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%s %d %d, %02d:%02d" % [_MONTHS[int(d["month"]) - 1], int(d["day"]), int(d["year"]), int(d["hour"]), int(d["minute"])]


## The row to start on: this game's slot, or else the first free one when saving and
## the first save when loading.
func _first_row() -> int:
	if GameState.save_slot > 0:
		return GameState.save_slot - 1
	for i in _rows.size():
		var empty := GameState.save_slot_info(i + 1).is_empty()
		if empty == saving:
			return i
	return _rows.size() if not saving else 0


func _on_row_pressed(slot: int) -> void:
	if saving and slot != _confirm_slot and not GameState.save_slot_info(slot).is_empty():
		_confirm_slot = slot
		_refresh()
		return
	_confirm_slot = 0
	_nav.clear()
	chosen.emit(slot)


func _close() -> void:
	_nav.clear()
	closed.emit()


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", _CREAM)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.96)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style
