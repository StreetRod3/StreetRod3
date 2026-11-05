extends Control

const _RANGE_METERS := 70.0
const _MIN_ROAD_PX := 3.0
## Matches the driveway width the city is built with, in meters.
const _DRIVEWAY_WIDTH := 9.0
const _BACKGROUND := Color(0.055, 0.065, 0.075, 0.55)
const _ROAD_EDGE := Color(0.72, 0.72, 0.68, 0.9)
const _ROAD_FILL := Color(0.24, 0.27, 0.29, 1.0)
const _PLAYER_COLOR := Color(1.0, 0.88, 0.32, 1.0)
const _POI_COLORS := {
	"garage": Color(0.32, 0.76, 1.0, 1.0),
	"drive-in": Color(1.0, 0.38, 0.31, 1.0),
	"gas-station": Color(1.0, 0.78, 0.25, 1.0),
	"royal-rods": Color(0.54, 0.9, 0.48, 1.0),
}

var _streets: Array[Dictionary] = []
var _buildings: Array = []
var _pois: Dictionary = {}
var _center := Vector2.ZERO
var _heading := 0.0
var _scale := 1.0
var _map_center := Vector2.ZERO
var _map_radius := 0.0
var _initialized := false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_track(track: Dictionary) -> void:
	_streets = _collect_streets(track)
	_buildings = track.get("buildings", [])
	_pois = track.get("pois", {})
	_initialized = true
	queue_redraw()


func _collect_streets(track: Dictionary) -> Array[Dictionary]:
	var streets: Array[Dictionary] = []
	var seen := {}
	var nodes: Dictionary = track.get("nodes", {})
	for road: Dictionary in track.get("roads", []):
		var from_id := int(road["from"])
		var to_id := int(road["to"])
		var key := "%d-%d" % [mini(from_id, to_id), maxi(from_id, to_id)]
		if seen.has(key) or not nodes.has(from_id) or not nodes.has(to_id):
			continue
		seen[key] = true
		streets.append({
			"a": Vector2(float(nodes[from_id]["x"]), float(nodes[from_id]["y"])),
			"b": Vector2(float(nodes[to_id]["x"]), float(nodes[to_id]["y"])),
			"width": float(road["width"]),
		})
	var pois: Dictionary = track.get("pois", {})
	for poi_id: String in pois:
		var poi: Dictionary = pois[poi_id]
		var join: Dictionary = nodes.get(int(poi["at"]), {})
		if join.is_empty():
			continue
		streets.append({
			"a": Vector2(float(poi["x"]), float(poi["y"])),
			"b": Vector2(float(join["x"]), float(join["y"])),
			"width": _DRIVEWAY_WIDTH,
		})
	return streets


func set_view(position: Vector3, yaw: float) -> void:
	var new_center := Vector2(position.x, position.z)
	if _center.distance_squared_to(new_center) < 0.64 and absf(wrapf(yaw - _heading, -PI, PI)) < 0.035:
		return
	_center = new_center
	_heading = yaw
	queue_redraw()


func _draw() -> void:
	var diameter := minf(size.x, size.y)
	if diameter <= 0.0:
		return
	_map_center = size * 0.5
	_map_radius = diameter * 0.5 - 4.0
	_scale = (_map_radius - 7.0) / _RANGE_METERS

	draw_circle(_map_center, _map_radius - 1.0, _BACKGROUND)

	draw_set_transform(_map_center, _heading)
	if _initialized:
		_draw_roads()
		_draw_buildings()
		_draw_pois()
	draw_set_transform(Vector2.ZERO)

	_draw_player()
	draw_arc(_map_center, _map_radius - 1.0, 0.0, TAU, 64, Color(0.78, 0.8, 0.78, 0.9), 2.0, true)


func _draw_roads() -> void:
	# Edges first, then fills, so junctions and driveways merge into one paved shape.
	for pass_index in 2:
		for street: Dictionary in _streets:
			var a: Vector2 = _local_position(street["a"].x, street["a"].y)
			var b: Vector2 = _local_position(street["b"].x, street["b"].y)
			var clipped := _clip_segment(a, b, _map_radius - 4.0)
			if clipped.size() != 2:
				continue
			var width := maxf(float(street["width"]) * _scale, _MIN_ROAD_PX)
			if pass_index == 0:
				draw_line(clipped[0], clipped[1], _ROAD_EDGE, width + 2.0, true)
			else:
				draw_line(clipped[0], clipped[1], _ROAD_FILL, width, true)


func _draw_buildings() -> void:
	for building: Dictionary in _buildings:
		var center := _local_position(float(building["x"]), float(building["y"]))
		var half_size := Vector2(float(building["w"]), float(building["d"])) * _scale * 0.5
		if center.length() + half_size.length() > _map_radius - 7.0:
			continue
		var color: Color = building.get("color", Color(0.42, 0.4, 0.36, 1.0))
		draw_rect(Rect2(center - half_size, half_size * 2.0), color.darkened(0.18), true)


func _draw_pois() -> void:
	for poi_id: String in _pois:
		var poi: Dictionary = _pois[poi_id]
		var relative := _local_position(float(poi["x"]), float(poi["y"]))
		var edge_distance := _map_radius - 9.0
		var marker_center := relative
		if relative.length() > edge_distance:
			marker_center = relative.normalized() * edge_distance
		var marker := Rect2(marker_center - Vector2(4.0, 4.0), Vector2(8.0, 8.0))
		draw_rect(marker.grow(1.5), Color(0.04, 0.05, 0.06, 1.0), true)
		draw_rect(marker, _POI_COLORS.get(poi_id, Color(0.9, 0.9, 0.9, 1.0)), true)


func _draw_player() -> void:
	var forward := Vector2.UP
	var side := Vector2.RIGHT
	var tip := _map_center + forward * 9.0
	var rear := _map_center - forward * 5.5
	draw_colored_polygon(
		PackedVector2Array([tip, rear + side * 5.0, rear - side * 5.0]),
		_PLAYER_COLOR
	)
	draw_polyline(
		PackedVector2Array([tip, rear + side * 5.0, rear - side * 5.0, tip]),
		Color(0.08, 0.09, 0.1, 1.0),
		1.2,
		true
	)


func _local_position(world_x: float, world_z: float) -> Vector2:
	return Vector2(-(world_x - _center.x) * _scale, -(world_z - _center.y) * _scale)


func _clip_segment(a: Vector2, b: Vector2, radius: float) -> PackedVector2Array:
	var clipped := PackedVector2Array()
	var delta := b - a
	var quadratic := delta.length_squared()
	if quadratic <= 0.0001:
		return clipped
	var linear := 2.0 * a.dot(delta)
	var constant := a.length_squared() - radius * radius
	var discriminant := linear * linear - 4.0 * quadratic * constant
	if discriminant < 0.0:
		if constant <= 0.0:
			clipped.append(a)
			clipped.append(b)
		return clipped
	var root := sqrt(discriminant)
	var start := maxf(0.0, (-linear - root) / (2.0 * quadratic))
	var end := minf(1.0, (-linear + root) / (2.0 * quadratic))
	if start > end:
		return clipped
	clipped.append(a + delta * start)
	clipped.append(a + delta * end)
	return clipped
