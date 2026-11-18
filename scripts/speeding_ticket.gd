extends Control

## The paper handed over after a pull-over. Laid out like a traffic citation:
## a ruled sheet, small captions, and the typed answers under them.
## The name is the one from the license.

const _FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const _SIGN := preload("res://assets/fonts/HomemadeApple-Regular.ttf")

const _PAPER := Color(0.95, 0.93, 0.86)
const _INK := Color(0.1, 0.08, 0.07)
const _CAPTION := Color(0.28, 0.24, 0.2)
const _MPH := 2.236936


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


## `speed_mps` is the fastest the car went while the heat was up.
func fill(driver: String, fine: int, speed_mps: float, limit_mps: float, crash: bool) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.anchor_left = 0.5
	sheet.anchor_top = 0.5
	sheet.anchor_right = 0.5
	sheet.anchor_bottom = 0.5
	sheet.offset_left = -460.0
	sheet.offset_top = -300.0
	sheet.offset_right = 460.0
	sheet.offset_bottom = 300.0
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_theme_stylebox_override(&"panel", _paper())
	add_child(sheet)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 10)
	margin.add_theme_constant_override(&"margin_right", 10)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(margin)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override(&"separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(grid)
	var when := _when()
	var name := driver.strip_edges().to_upper()
	if name.is_empty():
		name = "—"
	var mph := roundi(maxf(speed_mps, 0.0) * _MPH)
	var zone := roundi(maxf(limit_mps, 0.0) * _MPH)
	var desc := "RECKLESS DRIVING" if crash and speed_mps <= limit_mps else "SPEED IN ZONE"
	grid.add_child(_row([
		_cell("Name", name, 22, "DriverName"),
		_cell("Fine", "$%d" % fine, 22, "FineAmount"),
	]))
	grid.add_child(_row([
		_cell("Time", when["time"], 18),
		_cell("Date of Offense", when["date"], 18),
		_cell("IN VIOLATION OF", "CITY TRAFFIC LAW", 18),
	]))
	grid.add_child(_row([
		_cell("Section", "11-S", 18),
		_cell("Sub Section", "", 18),
		_cell("Tr Inf", "●", 18),
		_cell("Misd", "○", 18),
		_cell("Felony", "○", 18),
		_cell("MPH", str(mph), 20),
		_cell("MPH Zone", str(zone), 20),
	]))
	grid.add_child(_row([
		_cell("Description of Violation", desc, 20),
		_cell("US DOT#", "", 18),
	]))
	grid.add_child(_row([
		_cell("Place of Occurrence", "CITY STREETS", 18),
		_cell("CDL Veh", "○", 18),
		_cell("Bus", "○", 18),
		_cell("Haz Mat", "○", 18),
	]))
	grid.add_child(_row([
		_cell("C/T/V Name", "THE CITY", 16),
		_cell("County", "", 16),
		_cell("Hwy No", "", 16),
		_cell("Loc Code", "", 16),
	]))
	grid.add_child(_row([
		_cell("AFFIRMED UNDER PENALTY OF PERJURY", "", 12),
		_cell("Date Affirmed", when["date"], 16),
		_cell("Off Assign", "A 0 1", 16),
	]))
	var sign := _cell("Officer's Signature", "J. Hale", 22)
	var signed := sign.find_child("Value", true, false) as Label
	if signed != null:
		signed.add_theme_font_override(&"font", _SIGN)
		signed.add_theme_font_size_override(&"font_size", 26)
	grid.add_child(_row([
		sign,
		_cell("Arrest Type", "1 - PACE", 16),
		_cell("Badge/Shield", "214", 18),
	]))
	grid.add_child(_row([
		_cell("Officer's Last Name", "HALE", 16),
		_cell("First Name", "J", 16),
		_cell("MI", "", 16),
	]))
	var hint := Label.new()
	hint.text = "Press any key"
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -140.0
	hint.offset_right = 140.0
	hint.offset_top = -42.0
	hint.offset_bottom = -12.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_override(&"font", _FONT)
	hint.add_theme_font_size_override(&"font_size", 16)
	hint.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78))
	add_child(hint)


func _when() -> Dictionary:
	var now := Time.get_datetime_dict_from_system()
	var hour := int(now["hour"])
	var mark := "AM"
	var shown := hour
	if hour >= 12:
		mark = "PM"
	if shown > 12:
		shown -= 12
	if shown == 0:
		shown = 12
	return {
		"time": "%d:%02d %s" % [shown, int(now["minute"]), mark],
		"date": "%02d/%02d/%d" % [int(now["month"]), int(now["day"]), int(now["year"])],
	}


func _row(cells: Array[Control]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for cell: Control in cells:
		row.add_child(cell)
	return row


func _cell(caption: String, value: String, value_size: int, node_name: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", _rule())
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var cap := Label.new()
	cap.text = caption
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_font_override(&"font", _FONT)
	cap.add_theme_font_size_override(&"font_size", 11)
	cap.add_theme_color_override(&"font_color", _CAPTION)
	box.add_child(cap)
	var val := Label.new()
	val.name = "Value" if node_name.is_empty() else node_name
	val.text = value
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val.add_theme_font_override(&"font", _FONT)
	val.add_theme_font_size_override(&"font_size", value_size)
	val.add_theme_color_override(&"font_color", _INK)
	box.add_child(val)
	return panel


func _paper() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _PAPER
	style.border_color = _INK
	style.set_border_width_all(3)
	style.set_content_margin_all(0)
	return style


func _rule() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _PAPER
	style.border_color = _INK
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	return style
