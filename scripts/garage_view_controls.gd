extends Control

## Phone controls for turning the garage view and zooming. A wide desktop window hides them.

const _NARROW_WIDTH := 900.0
const _YAW_SPEED := 1.15
const _ZOOM_SPEED := 3.4

var _expanded: bool = true
var _yaw_dir: float = 0.0
var _zoom_dir: float = 0.0
var _panel: PanelContainer
var _rows: VBoxContainer
var _toggle: Button
var _buttons: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_apply_expanded()
	_refresh_visible()
	_place()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(delta: float) -> void:
	if not visible or (_yaw_dir == 0.0 and _zoom_dir == 0.0):
		return
	var garage := _garage()
	if garage == null or not garage.has_method(&"nudge_view"):
		return
	garage.call(&"nudge_view", _yaw_dir * _YAW_SPEED * delta, _zoom_dir * _ZOOM_SPEED * delta)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(&"panel", _panel_style())
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	_panel.add_child(box)

	_toggle = _make_button("Hide")
	_toggle.name = "ToggleButton"
	_toggle.pressed.connect(_on_toggle_pressed)
	box.add_child(_toggle)

	_rows = VBoxContainer.new()
	_rows.name = "Controls"
	_rows.add_theme_constant_override(&"separation", 8)
	box.add_child(_rows)

	var turn_left := _make_button("Rotate left")
	turn_left.name = "RotateLeft"
	_hold(turn_left, 1.0, true)
	var turn_right := _make_button("Rotate right")
	turn_right.name = "RotateRight"
	_hold(turn_right, -1.0, true)
	_rows.add_child(_row(turn_left, turn_right))

	var zoom_in := _make_button("Zoom in")
	zoom_in.name = "ZoomIn"
	_hold(zoom_in, -1.0, false)
	var zoom_out := _make_button("Zoom out")
	zoom_out.name = "ZoomOut"
	_hold(zoom_out, 1.0, false)
	_rows.add_child(_row(zoom_in, zoom_out))


func _hold(btn: Button, dir: float, yaw: bool) -> void:
	btn.button_down.connect(_set_dir.bind(dir, yaw))
	btn.button_up.connect(_clear_dir.bind(dir, yaw))


func _set_dir(dir: float, yaw: bool) -> void:
	if yaw:
		_yaw_dir = dir
	else:
		_zoom_dir = dir


func _clear_dir(dir: float, yaw: bool) -> void:
	if yaw:
		if is_equal_approx(_yaw_dir, dir):
			_yaw_dir = 0.0
	elif is_equal_approx(_zoom_dir, dir):
		_zoom_dir = 0.0


func _on_toggle_pressed() -> void:
	_expanded = not _expanded
	_yaw_dir = 0.0
	_zoom_dir = 0.0
	_apply_expanded()
	_place()


func _apply_expanded() -> void:
	_rows.visible = _expanded
	_toggle.text = "Hide" if _expanded else "View"


func _on_viewport_size_changed() -> void:
	_refresh_visible()
	_place()


func _refresh_visible() -> void:
	visible = _is_mobile_view()
	if not visible:
		_yaw_dir = 0.0
		_zoom_dir = 0.0


func _is_mobile_view() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	var vs := get_viewport().get_visible_rect().size
	var narrow := vs.x <= _NARROW_WIDTH or vs.x < vs.y
	if DisplayServer.is_touchscreen_available() and narrow:
		return true
	return vs.x <= _NARROW_WIDTH


func _place() -> void:
	var vs := get_viewport().get_visible_rect().size
	var btn_w := clampf(vs.x * 0.2, 100.0, 136.0)
	var btn_size := Vector2(btn_w, 48.0)
	var span := btn_w * 2.0 + 8.0 if _expanded else btn_w
	for btn: Button in _buttons:
		if btn == _toggle:
			btn.custom_minimum_size = Vector2(span, 44.0)
		else:
			btn.custom_minimum_size = btn_size
	var size := _panel.get_combined_minimum_size()
	_panel.position = Vector2.ZERO
	_panel.size = size
	position = Vector2(vs.x - 12.0 - size.x, vs.y - 56.0 - size.y)
	self.size = size


func _row(left: Button, right: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.add_child(left)
	row.add_child(right)
	return row


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override(&"font_size", 16)
	var ink := Color(0.95, 0.9, 0.78, 1.0)
	btn.add_theme_color_override(&"font_color", ink)
	btn.add_theme_color_override(&"font_hover_color", ink)
	btn.add_theme_color_override(&"font_pressed_color", ink)
	btn.add_theme_stylebox_override(&"normal", _button_style(Color(0.22, 0.16, 0.12, 1.0)))
	btn.add_theme_stylebox_override(&"hover", _button_style(Color(0.32, 0.22, 0.16, 1.0)))
	btn.add_theme_stylebox_override(&"pressed", _button_style(Color(0.55, 0.12, 0.1, 1.0)))
	btn.add_theme_stylebox_override(&"focus", _button_style(Color(0.32, 0.22, 0.16, 1.0)))
	_buttons.append(btn)
	return btn


func _button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.96)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _garage() -> Node:
	var ui := get_parent()
	if ui == null:
		return null
	return ui.get_parent()
