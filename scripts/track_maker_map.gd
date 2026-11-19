extends Control

## The track maker's top-down map. It draws a course (`track_maker_doc.gd`) and edits it with
## the mouse: with the road tool, a click on empty ground adds a node at the finish end, a click on a
## road splits it there, and nodes drag about; with the scenery tool, a click places the
## chosen kind and placed things drag about; with the ground tool, holding the button paints the
## ground's height with the chosen brush (track_terrain.gd). The wheel zooms, and the right or middle button
## drags the view. The map is drawn as the driver sees it: +Y (ahead from the start) is up
## and the driver's right, -X, is on the right.

const _Doc := preload("res://scripts/track_maker_doc.gd")
const _TrackTerrain := preload("res://scripts/track_terrain.gd")

## Before the first change of an edit, so the maker can keep an undo step.
signal edit_begun
## The course changed. During a drag this comes every move.
signal doc_edited
## A drag or click edit is over.
signal edit_ended
signal selection_changed
## Ctrl+click with the ground tool: the ground's height there, for Flatten.
signal ground_picked(height: float)

enum Tool { ROAD, SCENERY, GROUND }

const SNAP_M := 5.0
const MIN_SCALE := 0.02
const MAX_SCALE := 40.0
const _NODE_PICK_PX := 10.0
const _SCENERY_PICK_PX := 8.0
const _ROAD_PICK_PX := 7.0
const _BACKGROUND := Color(0.11, 0.13, 0.11, 1)
const _GRID_MINOR := Color(1, 1, 1, 0.05)
const _GRID_MAJOR := Color(1, 1, 1, 0.12)
const _AXIS := Color(0.95, 0.9, 0.78, 0.25)
const _CREAM := Color(0.95, 0.9, 0.78, 1)
const _SELECTED := Color(1.0, 0.85, 0.1, 1)
const _START := Color(0.3, 0.9, 0.35, 1)
const _FINISH := Color(0.95, 0.25, 0.2, 1)
## Scenery painted on the road, drawn small so the road shows through.
const _ROAD_MARKS := ["dash", "finish", "dark_streak", "stain", "joint", "gutter"]

var doc: _Doc
var tool: Tool = Tool.ROAD
var scenery_kind: String = "tree"
var snap: bool = false
var selected_node: int = -1
var selected_scenery: int = -1
## The ground tool's brush, its radius in meters, its strength (0 to 1), and Flatten's height.
var brush: _TrackTerrain.Brush = _TrackTerrain.Brush.RAISE
var brush_radius: float = 30.0
var brush_strength: float = 0.5
var flatten_height: float = 0.0
## The track point at the middle of the map, and pixels per meter.
var view_center: Vector2 = Vector2(0.0, 100.0)
var view_scale: float = 1.5

enum _Drag { NONE, NODE, SCENERY, PAN }
var _drag: _Drag = _Drag.NONE
var _drag_index: int = -1
## A drag of something already there starts its undo step only once it moves.
var _drag_begun: bool = false
var _pan_mouse: Vector2 = Vector2.ZERO
var _pan_center: Vector2 = Vector2.ZERO
var _painting: bool = false
var _mouse: Vector2 = Vector2(-1000.0, -1000.0)
## Chunk -> [stamp, ImageTexture]: each painted chunk drawn shaded, remade when it changes.
var _paint_images: Dictionary = {}


func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _process(delta: float) -> void:
	if not _painting or doc == null:
		return
	if _dab(minf(delta, 0.1)):
		doc_edited.emit()
		queue_redraw()


func is_painting() -> bool:
	return _painting


## One dab of the brush under the pointer, for `seconds` of painting.
func _dab(seconds: float) -> bool:
	return doc.terrain.paint(brush, to_track(_mouse), brush_radius, brush_strength, seconds, flatten_height, doc.ground_base)


# --- View ----------------------------------------------------------------------------------


func to_screen(point: Vector2) -> Vector2:
	return size * 0.5 + Vector2(view_center.x - point.x, view_center.y - point.y) * view_scale


func to_track(screen: Vector2) -> Vector2:
	var d := (screen - size * 0.5) / view_scale
	return Vector2(view_center.x - d.x, view_center.y - d.y)


## Fits the whole course on the map.
func frame_all() -> void:
	if doc == null or doc.nodes.is_empty():
		return
	var box := Rect2(doc.node_point(0), Vector2.ZERO)
	for i in doc.nodes.size():
		box = box.expand(doc.node_point(i))
	box = box.grow(40.0)
	view_center = box.get_center()
	var room := size - Vector2(40, 40)
	if room.x <= 0.0 or room.y <= 0.0:
		room = Vector2(800, 600)
	view_scale = clampf(minf(room.x / box.size.x, room.y / box.size.y), MIN_SCALE, MAX_SCALE)
	queue_redraw()


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := to_track(screen)
	view_scale = clampf(view_scale * factor, MIN_SCALE, MAX_SCALE)
	view_center += before - to_track(screen)
	queue_redraw()


# --- Mouse ---------------------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if doc == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom_at(button.position, 1.15)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom_at(button.position, 1.0 / 1.15)
				accept_event()
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if button.pressed:
					_drag = _Drag.PAN
					_pan_mouse = button.position
					_pan_center = view_center
				elif _drag == _Drag.PAN:
					_drag = _Drag.NONE
				accept_event()
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					grab_focus()
					if tool == Tool.GROUND and button.ctrl_pressed:
						ground_picked.emit(doc.ground_at(to_track(button.position)))
					else:
						_press(button.position)
				else:
					_release()
				accept_event()
	elif event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		_motion(_mouse)
		if tool == Tool.GROUND:
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and tool == Tool.GROUND:
		_mouse = Vector2(-1000.0, -1000.0)
		queue_redraw()


func _press(at: Vector2) -> void:
	if tool == Tool.GROUND:
		_mouse = at
		edit_begun.emit()
		_painting = true
		if _dab(1.0 / 30.0):
			doc_edited.emit()
		queue_redraw()
		return
	if tool == Tool.SCENERY:
		var hit := _scenery_at(at)
		if hit < 0:
			edit_begun.emit()
			var spot := _snapped(to_track(at))
			doc.scenery.append({"kind": scenery_kind, "x": _Doc.cm(spot.x), "y": _Doc.cm(spot.y)})
			hit = doc.scenery.size() - 1
			_drag_begun = true
			doc_edited.emit()
		else:
			_drag_begun = false
		select(-1, hit)
		_drag = _Drag.SCENERY
		_drag_index = hit
		return
	var node := _node_at(at)
	if node >= 0:
		select(node, -1)
		if node > 0:
			_drag = _Drag.NODE
			_drag_index = node
			_drag_begun = false
		return
	var road := _road_at(at)
	edit_begun.emit()
	if road >= 0:
		node = doc.insert_node(road, _snapped(_on_road(road, to_track(at))))
	else:
		node = doc.append_node(_snapped(to_track(at)))
	_drag_begun = true
	doc_edited.emit()
	select(node, -1)
	_drag = _Drag.NODE
	_drag_index = node


func _motion(at: Vector2) -> void:
	match _drag:
		_Drag.PAN:
			view_center = _pan_center + (at - _pan_mouse) / view_scale
			queue_redraw()
		_Drag.NODE:
			_start_drag_edit()
			doc.move_node(_drag_index, _snapped(to_track(at)))
			doc_edited.emit()
			queue_redraw()
		_Drag.SCENERY:
			_start_drag_edit()
			var point := _snapped(to_track(at))
			doc.scenery[_drag_index]["x"] = _Doc.cm(point.x)
			doc.scenery[_drag_index]["y"] = _Doc.cm(point.y)
			doc_edited.emit()
			queue_redraw()


func _start_drag_edit() -> void:
	if not _drag_begun:
		_drag_begun = true
		edit_begun.emit()


func _release() -> void:
	if _painting:
		_painting = false
		edit_ended.emit()
		return
	var was := _drag
	_drag = _Drag.NONE
	if (was == _Drag.NODE or was == _Drag.SCENERY) and _drag_begun:
		_drag_begun = false
		edit_ended.emit()


func select(node: int, sight: int) -> void:
	selected_node = node
	selected_scenery = sight
	selection_changed.emit()
	queue_redraw()


func _snapped(point: Vector2) -> Vector2:
	if not snap:
		return point
	return point.snapped(Vector2(SNAP_M, SNAP_M))


func _node_at(at: Vector2) -> int:
	var best := -1
	var best_d := _NODE_PICK_PX
	for i in doc.nodes.size():
		var d := to_screen(doc.node_point(i)).distance_to(at)
		if d <= best_d:
			best = i
			best_d = d
	return best


func _scenery_at(at: Vector2) -> int:
	var best := -1
	var best_d := _SCENERY_PICK_PX
	for i in doc.scenery.size():
		var d := to_screen(_scenery_point(i)).distance_to(at)
		if d <= best_d:
			best = i
			best_d = d
	return best


func _road_at(at: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in doc.road_count():
		var a := to_screen(doc.node_point(i))
		var b := to_screen(doc.node_point(doc.road_end(i)))
		var d := at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b))
		var reach := maxf(_ROAD_PICK_PX, _road_width(i) * view_scale * 0.5)
		if d <= reach and d < best_d:
			best = i
			best_d = d
	return best


## The point on road `i`'s middle nearest `point`.
func _on_road(i: int, point: Vector2) -> Vector2:
	return Geometry2D.get_closest_point_to_segment(point, doc.node_point(i), doc.node_point(doc.road_end(i)))


func _scenery_point(i: int) -> Vector2:
	return Vector2(float(doc.scenery[i].get("x", 0.0)), float(doc.scenery[i].get("y", 0.0)))


func _road_width(i: int) -> float:
	return float(doc.road_from(i).get("width", TrackFile.DEFAULT_WIDTH))


# --- Drawing -------------------------------------------------------------------------------


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _BACKGROUND)
	if doc == null:
		return
	_draw_ground()
	_draw_grid()
	_draw_roads()
	_draw_scenery()
	_draw_nodes()
	_draw_brush()
	_draw_scale_bar()


## The painted ground, shaded as if lit from the top left and colored by height, with a contour
## line every `_CONTOUR_M` meters. Unpainted ground isn't drawn.
func _draw_ground() -> void:
	var terrain := doc.terrain
	var keep: Dictionary = {}
	var chunk_m := _TrackTerrain.CHUNK_M
	var cell := _TrackTerrain.CELL_M
	var view := Rect2(Vector2.ZERO, size)
	for key: Vector2i in terrain.chunks:
		var origin := Vector2(key) * chunk_m
		# The image's pixels sit on the grid's points; the map runs +X to the left and +Y up.
		var corner := to_screen(origin + Vector2(chunk_m - cell * 0.5, chunk_m - cell * 0.5))
		var rect := Rect2(corner, Vector2(chunk_m, chunk_m) * view_scale)
		keep[key] = true
		if not view.intersects(rect):
			continue
		var stamp := terrain.stamp(key)
		var cached: Array = _paint_images.get(key, [])
		if cached.is_empty() or int(cached[0]) != stamp:
			cached = [stamp, ImageTexture.create_from_image(_ground_image(key))]
			_paint_images[key] = cached
		draw_texture_rect(cached[1] as ImageTexture, rect, false)
	for key: Variant in _paint_images.keys():
		if not keep.has(key):
			_paint_images.erase(key)


const _CONTOUR_M := 5.0


func _ground_image(key: Vector2i) -> Image:
	var terrain := doc.terrain
	var n := _TrackTerrain.CHUNK
	var cell := _TrackTerrain.CELL_M
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	# In screen terms: x right, y up out of the map, z up the screen; lit from the top left.
	var light := Vector3(-1.0, 1.4, 1.0).normalized()
	var flat := light.y
	for lj in n:
		for li in n:
			var i := key.x * n + li
			var j := key.y * n + lj
			var h := terrain.height(i, j)
			if is_nan(h):
				continue
			# Screen right is track -X, and screen up +Y.
			var right := _near_height(terrain, i - 1, j, h)
			var left := _near_height(terrain, i + 1, j, h)
			var down := _near_height(terrain, i, j - 1, h)
			var up := _near_height(terrain, i, j + 1, h)
			var normal := Vector3(left - right, 2.0 * cell, down - up).normalized()
			var shade := clampf(0.85 + 0.9 * (normal.dot(light) - flat), 0.35, 1.2)
			var color := height_color(h) * shade
			var band := floori(h / _CONTOUR_M)
			if floori(right / _CONTOUR_M) != band or floori(up / _CONTOUR_M) != band:
				color = color.darkened(0.35)
			color.a = 0.85
			image.set_pixel(n - 1 - li, n - 1 - lj, color)
	return image


static func _near_height(terrain: _TrackTerrain, i: int, j: int, fallback: float) -> float:
	var h := terrain.height(i, j)
	return fallback if is_nan(h) else h


## The map's color for ground `h` meters high: green low, through tan and brown, to grey and
## white on the heights.
static func height_color(h: float) -> Color:
	var stops: Array[Vector2] = [Vector2(-50, 0), Vector2(0, 1), Vector2(40, 2), Vector2(150, 3), Vector2(400, 4), Vector2(1000, 5)]
	var colors: Array[Color] = [
		Color(0.12, 0.3, 0.25), Color(0.3, 0.5, 0.22), Color(0.62, 0.58, 0.32),
		Color(0.5, 0.36, 0.22), Color(0.55, 0.55, 0.55), Color(0.95, 0.95, 0.95),
	]
	if h <= stops[0].x:
		return colors[0]
	for k in range(1, stops.size()):
		if h <= stops[k].x:
			return colors[k - 1].lerp(colors[k], (h - stops[k - 1].x) / (stops[k].x - stops[k - 1].x))
	return colors[colors.size() - 1]


## The ground tool's brush round the pointer, and the ground's height under it.
func _draw_brush() -> void:
	if tool != Tool.GROUND or not Rect2(Vector2.ZERO, size).has_point(_mouse):
		return
	var r := brush_radius * view_scale
	draw_arc(_mouse, r, 0.0, TAU, 48, Color(_CREAM, 0.9), 1.5)
	draw_arc(_mouse, r * 0.5, 0.0, TAU, 32, Color(_CREAM, 0.35), 1.0)
	var at := to_track(_mouse)
	var paint := doc.terrain.sample(at)
	var text := "ground %.1f m" % doc.ground_at(at)
	if paint.y <= 0.0:
		text += " (not painted)"
	draw_string(get_theme_default_font(), _mouse + Vector2(r * 0.7 + 8.0, -8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _CREAM)


func _draw_grid() -> void:
	var step := 1.0
	for candidate: float in [1.0, 5.0, 10.0, 50.0, 100.0, 500.0, 1000.0, 5000.0]:
		step = candidate
		if candidate * view_scale >= 14.0:
			break
	var major := step * 10.0
	var a := to_track(Vector2.ZERO)
	var b := to_track(size)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var x := floorf(lo.x / step) * step
	while x <= hi.x:
		var sx := to_screen(Vector2(x, 0.0)).x
		var color := _AXIS if is_zero_approx(x) else (_GRID_MAJOR if is_zero_approx(fmod(absf(x), major)) else _GRID_MINOR)
		draw_line(Vector2(sx, 0.0), Vector2(sx, size.y), color)
		x += step
	var y := floorf(lo.y / step) * step
	while y <= hi.y:
		var sy := to_screen(Vector2(0.0, y)).y
		var color := _AXIS if is_zero_approx(y) else (_GRID_MAJOR if is_zero_approx(fmod(absf(y), major)) else _GRID_MINOR)
		draw_line(Vector2(0.0, sy), Vector2(size.x, sy), color)
		y += step


static func road_color(road_type: String) -> Color:
	match road_type:
		TrackFile.ROAD_GRAVEL:
			return Color(0.52, 0.5, 0.45, 1)
		TrackFile.ROAD_BRIDGE:
			return Color(0.55, 0.38, 0.22, 1)
	if TrackFile.obstacle_left(road_type) or TrackFile.obstacle_right(road_type):
		return Color(0.8, 0.45, 0.12, 1)
	if road_type != TrackFile.ROAD_REGULAR:
		return Color(0.42, 0.44, 0.5, 1)
	return Color(0.32, 0.33, 0.35, 1)


func _draw_roads() -> void:
	# A road back to the start that the race doesn't follow, kept from the file.
	if not doc.loop and not doc.loop_road.is_empty() and doc.nodes.size() > 2:
		draw_dashed_line(to_screen(doc.node_point(doc.nodes.size() - 1)), to_screen(doc.node_point(0)), Color(_CREAM, 0.3), 1.0, 8.0)
	for i in doc.road_count():
		var a := to_screen(doc.node_point(i))
		var b := to_screen(doc.node_point(doc.road_end(i)))
		var px := maxf(_road_width(i) * view_scale, 3.0)
		var color := road_color(str(doc.road_from(i).get("type", TrackFile.ROAD_REGULAR)))
		if i == selected_node:
			draw_line(a, b, _SELECTED, px + 4.0)
		draw_line(a, b, color, px)
		draw_circle(a, px * 0.5, color)
		draw_circle(b, px * 0.5, color)
	for i in doc.road_count():
		draw_line(to_screen(doc.node_point(i)), to_screen(doc.node_point(doc.road_end(i))), Color(_CREAM, 0.35), 1.0)


static func scenery_color(kind: String) -> Color:
	if kind.contains("tree") or kind == "shrub" or kind == "bush":
		return Color(0.35, 0.75, 0.3, 1)
	if kind.contains("rock") or kind.contains("boulder"):
		return Color(0.6, 0.48, 0.36, 1)
	if kind.contains("sign") or kind.begins_with("chevron"):
		return Color(0.95, 0.8, 0.2, 1)
	if kind == "barricade" or kind == "post":
		return Color(0.95, 0.55, 0.15, 1)
	if kind in ["dash", "finish", "dark_streak", "stain"]:
		return Color(0.9, 0.9, 0.85, 1)
	if kind in ["joint", "gutter", "drain", "slab", "fin"]:
		return Color(0.45, 0.75, 0.85, 1)
	return Color(0.75, 0.75, 0.78, 1)


func _draw_scenery() -> void:
	var dim := tool != Tool.SCENERY
	for i in doc.scenery.size():
		var kind := str(doc.scenery[i].get("kind", ""))
		var color := scenery_color(kind)
		if dim:
			color.a = 0.55
		var at := to_screen(_scenery_point(i))
		if not Rect2(Vector2.ZERO, size).grow(10.0).has_point(at):
			continue
		draw_circle(at, 1.5 if _ROAD_MARKS.has(kind) else 3.5, color)
		if i == selected_scenery:
			draw_arc(at, 7.0, 0.0, TAU, 20, _SELECTED, 2.0)
			draw_string(get_theme_default_font(), at + Vector2(10, 5), kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _SELECTED)


func _draw_nodes() -> void:
	var font := get_theme_default_font()
	var last := doc.nodes.size() - 1
	# Nodes closer together on screen than this are drawn as small dots, so the road shows.
	var crowded := last > 0 and doc.path_length() / float(doc.road_count()) * view_scale < 14.0
	for i in doc.nodes.size():
		var at := to_screen(doc.node_point(i))
		if not Rect2(Vector2.ZERO, size).grow(20.0).has_point(at):
			continue
		var color := _CREAM
		if i == 0:
			color = _START
		elif i == last and not doc.loop:
			color = _FINISH
		var r := 1.5 if crowded and i != 0 and i != last and i != selected_node else 5.0
		if bool(doc.nodes[i].get("sharp", false)):
			draw_rect(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), color)
		else:
			draw_circle(at, r, color)
		if i == 0 and doc.loop:
			# The start is the finish too.
			draw_arc(at, 7.0, 0.0, TAU, 20, _FINISH, 2.0)
		if i == selected_node:
			draw_arc(at, 9.0, 0.0, TAU, 24, _SELECTED, 2.0)
		var labeled := (view_scale >= 0.4 and not crowded) or i == selected_node
		var z := doc.node_height(i)
		if not is_zero_approx(z) and labeled:
			draw_string(font, at + Vector2(9, -7), "%+.1f m" % z, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(_CREAM, 0.8))
		var bank := doc.bank_at(i)
		if not is_zero_approx(bank) and labeled:
			var edge := "L" if bank > 0.0 else "R"
			draw_string(font, at + Vector2(9, 9), "%s up %d°" % [edge, roundi(absf(bank))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(_CREAM, 0.8))
		if doc.style == TrackFile.STYLE_AQUEDUCT and labeled and (doc.nodes[i].has("left") or doc.nodes[i].has("right")):
			var sides := "sides L %.1f R %.1f m" % [doc.aqueduct_side_at(i, "left"), doc.aqueduct_side_at(i, "right")]
			draw_string(font, at + Vector2(9, 25), sides, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(_CREAM, 0.8))
	# Which way the race starts.
	var start := to_screen(doc.node_point(0))
	draw_colored_polygon(PackedVector2Array([start + Vector2(0, -22), start + Vector2(-7, -10), start + Vector2(7, -10)]), _START)


func _draw_scale_bar() -> void:
	var meters := 1.0
	for candidate: float in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]:
		meters = candidate
		if candidate * view_scale >= 80.0:
			break
	var px := meters * view_scale
	var at := Vector2(16, size.y - 18)
	draw_line(at, at + Vector2(px, 0), _CREAM, 2.0)
	draw_line(at + Vector2(0, -5), at + Vector2(0, 5), _CREAM, 2.0)
	draw_line(at + Vector2(px, -5), at + Vector2(px, 5), _CREAM, 2.0)
	draw_string(get_theme_default_font(), at + Vector2(px + 8, 5), "%d m" % int(meters), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _CREAM)
