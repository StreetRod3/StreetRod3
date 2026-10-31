extends Control

## Comic speech bubble used at the end of a race. One instance per line of text.

signal pressed

const _INK := Color(0.08, 0.06, 0.05)
const _PAPER := Color(0.98, 0.97, 0.93)
const _CENTERED := 0
const _FOLLOW := 1

var _panel: PanelContainer
var _label: Label
var _tail: Node2D
var _camera: Camera3D
var _anchor_node: Node3D
var _anchor_offset := Vector3.ZERO
var _mode := _CENTERED
var _hold_when_behind := false
var _grabbing := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(place)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		place()


func set_line(text: String, min_size: Vector2 = Vector2(320, 56), font_size: int = 26) -> void:
	_label.text = text
	_label.custom_minimum_size = min_size
	_label.add_theme_font_size_override(&"font_size", font_size)


## Full-screen click catcher. A click anywhere emits [signal pressed].
func grab_screen() -> void:
	if _grabbing:
		return
	_grabbing = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


## Tail tracks a world point. If it sits behind the camera, the bubble stays up high.
func follow_node(camera: Camera3D, node: Node3D, offset: Vector3 = Vector3.ZERO) -> void:
	_camera = camera
	_anchor_node = node
	_anchor_offset = offset
	_mode = _FOLLOW


## Leave the bubble where it is when the anchor is behind the camera.
func hold_when_behind(hold: bool) -> void:
	_hold_when_behind = hold


## Screen-centered, the way the race result sits above the cars.
func show_centered() -> void:
	_mode = _CENTERED
	place()


func place() -> void:
	if not is_inside_tree() or _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var bubble_size := _panel.get_combined_minimum_size()
	if _mode == _CENTERED:
		var x := (vp.x - bubble_size.x) * 0.5
		var y := clampf(vp.y * 0.42 - bubble_size.y, 16.0, maxf(16.0, vp.y - bubble_size.y - 42.0))
		_panel.position = Vector2(x, y)
		_panel.size = bubble_size
		_tail.position = Vector2(bubble_size.x * 0.5, bubble_size.y - 4.0)
		return
	if _camera == null or _anchor_node == null or not is_instance_valid(_anchor_node):
		return
	var spot := _anchor_node.global_position + _anchor_offset
	var screen := Vector2(vp.x * 0.5, 180.0)
	if _camera.is_position_behind(spot):
		if _hold_when_behind:
			return
	else:
		screen = _camera.unproject_position(spot)
	var tail_h := 26.0
	var px := clampf(screen.x - bubble_size.x * 0.5, 16.0, maxf(16.0, vp.x - bubble_size.x - 16.0))
	var py := clampf(screen.y - bubble_size.y - tail_h - 8.0, 16.0, maxf(16.0, vp.y - bubble_size.y - tail_h - 16.0))
	_panel.position = Vector2(px, py)
	_panel.size = bubble_size
	var tail_x := clampf(screen.x - px, 28.0, maxf(28.0, bubble_size.x - 28.0))
	_tail.position = Vector2(tail_x, bubble_size.y - 4.0)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override(&"panel", _style())
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 20)
	margin.add_theme_constant_override(&"margin_right", 20)
	margin.add_theme_constant_override(&"margin_top", 14)
	margin.add_theme_constant_override(&"margin_bottom", 14)
	_panel.add_child(margin)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_color", _INK)
	_label.add_theme_font_size_override(&"font_size", 26)
	_label.custom_minimum_size = Vector2(320, 56)
	margin.add_child(_label)
	_tail = Node2D.new()
	_panel.add_child(_tail)
	var outline := Line2D.new()
	outline.width = 5.0
	outline.default_color = _INK
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	outline.points = PackedVector2Array([Vector2(-18, 0), Vector2(0, 24), Vector2(18, 0)])
	_tail.add_child(outline)
	var fill := Polygon2D.new()
	fill.color = _PAPER
	fill.polygon = PackedVector2Array([Vector2(-14, 2), Vector2(0, 18), Vector2(14, 2)])
	_tail.add_child(fill)


func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _PAPER
	style.border_color = _INK
	style.set_border_width_all(4)
	style.set_corner_radius_all(18)
	return style


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		pressed.emit()
		get_viewport().set_input_as_handled()
