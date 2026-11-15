extends Control

## The track maker's height strip: each node's height along the course, start on the left.
## Click a node to select it, drag it up or down to set its height. Square nodes are sharp.
## The game rounds the road's grade through nodes that aren't sharp, so the real road is
## smoother than these straight lines.

const _Doc := preload("res://scripts/track_maker_doc.gd")

signal node_picked(index: int)
signal edit_begun
signal doc_edited
signal edit_ended

const HEIGHT_STEP := 0.1
const _PAD_X := 44.0
const _PAD_Y := 14.0
const _PICK_PX := 9.0
const _BACKGROUND := Color(0.09, 0.1, 0.11, 1)
const _CREAM := Color(0.95, 0.9, 0.78, 1)
const _SELECTED := Color(1.0, 0.85, 0.1, 1)

var doc: _Doc
var selected_node: int = -1

var _drag_index: int = -1
var _drag_begun: bool = false
## The height range on show. It holds still while a node is dragged.
var _low: float = -3.0
var _high: float = 3.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _distances() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var total := 0.0
	for i in doc.nodes.size():
		if i > 0:
			total += doc.node_point(i - 1).distance_to(doc.node_point(i))
		out.append(total)
	return out


func _fit_heights() -> void:
	var lo := 0.0
	var hi := 0.0
	for i in doc.nodes.size():
		lo = minf(lo, doc.node_height(i))
		hi = maxf(hi, doc.node_height(i))
	var middle := (lo + hi) * 0.5
	var half := maxf((hi - lo) * 0.5 + 1.0, 3.0)
	_low = middle - half
	_high = middle + half


func _point(s: float, z: float, length: float) -> Vector2:
	var w := maxf(size.x - _PAD_X * 2.0, 1.0)
	var h := maxf(size.y - _PAD_Y * 2.0, 1.0)
	var x := _PAD_X + (s / maxf(length, 1.0)) * w
	var y := _PAD_Y + (1.0 - (z - _low) / (_high - _low)) * h
	return Vector2(x, y)


func _height_at(y: float) -> float:
	var h := maxf(size.y - _PAD_Y * 2.0, 1.0)
	return _low + (1.0 - (y - _PAD_Y) / h) * (_high - _low)


func _gui_input(event: InputEvent) -> void:
	if doc == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		accept_event()
		if button.pressed:
			var hit := _node_at(button.position)
			if hit >= 0:
				node_picked.emit(hit)
				_drag_index = hit
				_drag_begun = false
		else:
			if _drag_begun:
				edit_ended.emit()
			_drag_index = -1
			_drag_begun = false
			queue_redraw()
	elif event is InputEventMouseMotion and _drag_index >= 0:
		if not _drag_begun:
			_drag_begun = true
			edit_begun.emit()
		var z := snappedf(_height_at((event as InputEventMouseMotion).position.y), HEIGHT_STEP)
		doc.set_node_field(_drag_index, "z", z)
		doc_edited.emit()
		queue_redraw()


func _node_at(at: Vector2) -> int:
	var dists := _distances()
	var length := dists[dists.size() - 1] if not dists.is_empty() else 0.0
	var best := -1
	var best_d := _PICK_PX
	for i in doc.nodes.size():
		var d := _point(dists[i], doc.node_height(i), length).distance_to(at)
		if d <= best_d:
			best = i
			best_d = d
	return best


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _BACKGROUND)
	if doc == null or doc.nodes.size() < 2:
		return
	if _drag_index < 0:
		_fit_heights()
	var font := get_theme_default_font()
	var dists := _distances()
	var length := dists[dists.size() - 1]
	var zero_y := _point(0.0, 0.0, length).y
	draw_line(Vector2(_PAD_X, zero_y), Vector2(size.x - _PAD_X, zero_y), Color(_CREAM, 0.2))
	draw_string(font, Vector2(4, _PAD_Y + 10), "%+.1f m" % _high, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(_CREAM, 0.6))
	draw_string(font, Vector2(4, size.y - _PAD_Y), "%+.1f m" % _low, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(_CREAM, 0.6))
	draw_string(font, Vector2(size.x - _PAD_X + 4, size.y - _PAD_Y), "%d m" % int(length), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(_CREAM, 0.6))
	var line := PackedVector2Array()
	for i in doc.nodes.size():
		line.append(_point(dists[i], doc.node_height(i), length))
	draw_polyline(line, Color(_CREAM, 0.7), 2.0)
	var last := doc.nodes.size() - 1
	var crowded := (size.x - _PAD_X * 2.0) / float(last) < 10.0
	for i in doc.nodes.size():
		var at := line[i]
		var r := 1.5 if crowded and i != 0 and i != last and i != selected_node else 4.0
		var color := _CREAM
		if i == 0:
			color = Color(0.3, 0.9, 0.35, 1)
		elif i == doc.nodes.size() - 1:
			color = Color(0.95, 0.25, 0.2, 1)
		if bool(doc.nodes[i].get("sharp", false)):
			draw_rect(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), color)
		else:
			draw_circle(at, r, color)
		if i == selected_node:
			draw_arc(at, 8.0, 0.0, TAU, 20, _SELECTED, 2.0)
			draw_string(font, at + Vector2(8, -8), "%+.1f m" % doc.node_height(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _SELECTED)
