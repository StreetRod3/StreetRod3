extends Node3D

## Builds a road course from a `.trk` graph and answers path queries.

const _StreetScenery := preload("res://scripts/street_scenery.gd")
const _CourseScenery := preload("res://scripts/course_scenery.gd")
const _TrackSides := preload("res://scripts/track_sides.gd")

@export_file("*.trk") var track_path: String = "res://assets/tracks/track1.trk"

const ROAD_HALF_W := 20.0
## Depth of the barrier strip past the driveable edge.
const OBSTACLE_BAND := 0.7
const BAKE_STEP := 2.0
## Grass grid around the road. It sits just under the pavement so the two don't flicker.
const _TERRAIN_PAD := 400.0
const _TERRAIN_STEP := 12.0
const _TERRAIN_SINK := 0.08
## A street track's rises are short, so its grass needs more points to stay under the road.
const _STREET_TERRAIN_PAD := 300.0
const _STREET_TERRAIN_STEP := 6.0
## Grass points under a street track's road go this much lower still. Between points the grass runs
## straight, so at the bottom of a dip it would otherwise come up through the pavement.
const _STREET_UNDER_ROAD_SINK := 1.0
const _STREET_SHOULDER_W := 0.75
const STREET_SHOULDER_COLOR := Color(0.36, 0.35, 0.32, 1)
## How far a street track's pavement runs back behind the start, so it doesn't begin under the cars.
const _STREET_RUN_IN_M := 60.0
## Cell size for the nearest-sample lookup used while shaping the grass.
const _BIN_CELL := 64.0
const FILLET_MIN_ANGLE := 0.06 ## ~3.5 degrees; smaller turns stay as a sharp join
const FILLET_LEN_FRACTION := 0.4
const FILLET_MAX_CUT := 80.0
## Straight pavement past the finish. The race still ends on the finish line.
const _RUNOFF_M := 400.0
const CURB_W := 0.45
const CURB_H := 0.16
const CURB_L := 2.0
const CURB_RED := Color(0.82, 0.12, 0.12, 1)
const CURB_WHITE := Color(0.92, 0.92, 0.9, 1)
const CHECK_BLACK := Color(0.06, 0.06, 0.07, 1)
const CHECK_WHITE := Color(0.94, 0.94, 0.92, 1)
const POST_COLOR := Color(0.12, 0.12, 0.13, 1)
const ROAD_COLOR := Color(0.18, 0.19, 0.2, 1)
const TERRAIN_COLOR := Color(0.14, 0.16, 0.13, 1)
const STREET_TERRAIN_COLOR := Color(0.16, 0.27, 0.11, 1)
## Mulholland's road, black in Street Rod 2.
const MOUNTAIN_ROAD_COLOR := Color(0.045, 0.045, 0.05, 1)
const _GRAVEL_COLOR := Color(0.4, 0.4, 0.38, 1)
## A rival holds to this over gravel: Street Rod 2's 59 mph.
const GRAVEL_RIVAL_MPS := 59.0 * 0.44704
## A car this close to the middle of a flat rock on the road has hit it.
const ROAD_ROCK_REACH := 1.5
## How far a rival stays from something on the road, from its own middle.
const _RIVAL_CLEARANCE_M := 1.45
const _RIVAL_EDGE_ROOM_M := 1.0
## Things on the road this close together are gone around as one.
const _BLOCK_GROUP_M := 12.0
const _BRIDGE_LINE_UP_M := 30.0
const _RIVAL_BRIDGE_ROOM_M := 1.3
const SIGN_OBJ := "res://assets/signs/narrow.obj"
const SIGN_TEX_BOTH := "res://assets/signs/narrow-both.png"
const SIGN_TEX_LEFT := "res://assets/signs/narrow-left.png"
const SIGN_TEX_RIGHT := "res://assets/signs/narrow-right.png"
const SIGN_SCALE := 2.0

var _pts: PackedVector3Array = PackedVector3Array()
var _yaws: PackedFloat32Array = PackedFloat32Array()
var _dists: PackedFloat32Array = PackedFloat32Array()
var _half_ws: PackedFloat32Array = PackedFloat32Array()
var _surfaces: PackedStringArray = PackedStringArray()
var _road_types: PackedStringArray = PackedStringArray()
var _length: float = 0.0
## Distance along the path where the race ends. The mesh continues past this.
var _race_length: float = 0.0
var _pos := Vector3.ZERO
var _yaw: float = 0.0
var _seg_half_w: float = ROAD_HALF_W
var _seg_surface: String = "regular"
var _seg_road_type: String = "regular"
var _bins: Dictionary = {}
var _road_mi: MeshInstance3D
var _built: bool = false
var _sign_mesh: ArrayMesh
var _sign_textures: Dictionary = {}
var _street: bool = false
var _style: String = TrackFile.STYLE_CIRCUIT
var _scenery: Array[Dictionary] = []
## Each sample's hillside (up) or drop (down) on the driver's left and right, and whether the right
## has a guard rail. Only Mulholland has these.
var _left_sides: PackedFloat32Array = PackedFloat32Array()
var _right_sides: PackedFloat32Array = PackedFloat32Array()
var _rails: PackedByteArray = PackedByteArray()
## Where each node falls along the path.
var _node_s: PackedFloat32Array = PackedFloat32Array()
## What a rival steers around, from the start: {s, to, low, high}, sorted by s.
var _blocks: Array[Dictionary] = []
var _road_rocks: Array[Vector3] = []
## Squared distance from the last grass point to the road's middle, set by `_grass_height`.
var _grass_dist_sq: float = 0.0


func is_road_course() -> bool:
	return _built


func get_length() -> float:
	return _race_length


func get_half_width() -> float:
	if _half_ws.is_empty():
		return ROAD_HALF_W
	return _half_ws[0]


func get_road_mesh_instance() -> MeshInstance3D:
	return _road_mi


func remaining_distance(world: Vector3) -> float:
	return maxf(0.0, _race_length - closest_sample(world)["s"])


func sample_at(s: float) -> Dictionary:
	if _pts.is_empty():
		return _empty_sample()
	s = clampf(s, 0.0, _length)
	var i := _index_at_distance(s)
	var j := mini(i + 1, _pts.size() - 1)
	var t := 0.0
	var span: float = _dists[j] - _dists[i]
	if span > 0.0001:
		t = (s - _dists[i]) / span
	var pos := _pts[i].lerp(_pts[j], t)
	var yaw := lerp_angle(_yaws[i], _yaws[j], t)
	return _make_sample(pos, yaw, s, 0.0, i)


func closest_sample(world: Vector3) -> Dictionary:
	if _pts.is_empty():
		return _empty_sample()
	var best_i := _nearest_index(world)
	var yaw: float = _yaws[best_i]
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var lateral := (world - _pts[best_i]).dot(right)
	return _make_sample(_pts[best_i], yaw, _dists[best_i], lateral, best_i)


## Height of the road under `world`, in meters. The grass beside it uses the same height.
func surface_height(world: Vector3) -> float:
	if _pts.is_empty():
		return 0.0
	var i := _nearest_index(world)
	var height := _pts[i].y
	var best_d := INF
	for j: int in [i - 1, i]:
		if j < 0 or j + 1 >= _pts.size():
			continue
		var a := _pts[j]
		var b := _pts[j + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var len2 := ab.length_squared()
		if len2 < 0.0001:
			continue
		var ap := Vector2(world.x - a.x, world.z - a.z)
		var t := clampf(ap.dot(ab) / len2, 0.0, 1.0)
		var d := ap.distance_squared_to(ab * t)
		if d < best_d:
			best_d = d
			height = lerpf(a.y, b.y, t)
	return height + _side_height_at(i, world)


## Height of a hillside, drop or bank at `world` over the road beside it, at sample `i`.
func _side_height_at(i: int, world: Vector3) -> float:
	if _style == TrackFile.STYLE_AQUEDUCT:
		return _TrackSides.aqueduct_height(_lateral_at(i, world))
	if _style != TrackFile.STYLE_MOUNTAIN:
		return 0.0
	var lateral := _lateral_at(i, world)
	return _TrackSides.mountain_height(lateral, _half_ws[i], _left_sides[i] if lateral > 0.0 else _right_sides[i])


func _lateral_at(i: int, world: Vector3) -> float:
	return (world - _pts[i]).dot(Vector3(cos(_yaws[i]), 0.0, -sin(_yaws[i])))


## How far a car at `world` leans across the road, by the height either side of it, in radians.
func surface_roll(world: Vector3, yaw: float) -> float:
	if _style != TrackFile.STYLE_AQUEDUCT and _style != TrackFile.STYLE_MOUNTAIN:
		return 0.0
	var across := Vector3(cos(yaw), 0.0, -sin(yaw)) * 0.8
	return atan2(surface_height(world + across) - surface_height(world - across), 1.6)


## What the Aqueduct's banks do to a car at `world`: sideways, toward the floor, in m/s.
func bank_push(world: Vector3) -> Vector3:
	if _style != TrackFile.STYLE_AQUEDUCT or _pts.is_empty():
		return Vector3.ZERO
	var i := _nearest_index(world)
	var across := Vector3(cos(_yaws[i]), 0.0, -sin(_yaws[i]))
	return across * _TrackSides.aqueduct_push(_lateral_at(i, world))


## True when a car at `world` has gone off an edge with nothing to stop it.
func over_the_edge(world: Vector3) -> bool:
	if _style != TrackFile.STYLE_MOUNTAIN or _pts.is_empty():
		return false
	var i := _nearest_index(world)
	var lateral := _lateral_at(i, world)
	var side := _left_sides[i] if lateral > 0.0 else _right_sides[i]
	if side > -_TrackSides.DROP_MIN:
		return false
	return absf(lateral) > _half_ws[i] + _TrackSides.MOUNTAIN_VERGE + _TrackSides.OVER_EDGE_PAST_VERGE


## The lane a rival should hold at `s`, looking `look` meters ahead, given the one it wants: of the
## gaps left by the next group of things on the road, the spot nearest that lane.
func lane_around(s: float, lane: float, look: float) -> float:
	var lows := PackedFloat32Array()
	var highs := PackedFloat32Array()
	var soft_lows := PackedFloat32Array()
	var soft_highs := PackedFloat32Array()
	var group_end := INF
	var bridge: Dictionary = {}
	for block: Dictionary in _blocks:
		var from_s := float(block["s"])
		if from_s > s + look or from_s > group_end:
			break
		if float(block["to"]) < s - 2.0:
			continue
		# Lining up for a bridge comes after whatever is in the way before it.
		if block.has("bridge"):
			bridge = block
			continue
		if is_inf(group_end):
			group_end = float(block["to"]) + _BLOCK_GROUP_M
		var low := float(block["low"]) - _RIVAL_CLEARANCE_M
		var high := float(block["high"]) + _RIVAL_CLEARANCE_M
		if block.has("soft"):
			soft_lows.append(low)
			soft_highs.append(high)
		else:
			lows.append(low)
			highs.append(high)
	var room := INF
	var no_more := lows.is_empty() and soft_lows.is_empty()
	if not bridge.is_empty() and (no_more or s >= float(bridge["s"])):
		room = maxf(float(bridge["bridge"]) - _RIVAL_BRIDGE_ROOM_M, 0.0)
	if no_more:
		return clampf(lane, -room, room)
	return clampf(_lane_through(lane, lows, highs, soft_lows, soft_highs), -room, room)


## Around everything if it can, then through a sawhorse, then the best of what is left.
func _lane_through(lane: float, lows: PackedFloat32Array, highs: PackedFloat32Array, soft_lows: PackedFloat32Array, soft_highs: PackedFloat32Array) -> float:
	var all_lows := lows + soft_lows
	var all_highs := highs + soft_highs
	var spot := _clear_spot(lane, all_lows, all_highs)
	if is_inf(spot):
		spot = _clear_spot(lane, lows, highs)
	if is_inf(spot):
		spot = _middle_of_widest_gap(lows, highs, get_half_width() - _RIVAL_EDGE_ROOM_M)
	return spot


## Of the spots at the ends of the gaps, the one nearest `lane` that has room, or INF.
func _clear_spot(lane: float, lows: PackedFloat32Array, highs: PackedFloat32Array) -> float:
	var limit := get_half_width() - _RIVAL_EDGE_ROOM_M
	var best := lane
	var best_cost := INF
	var spots := PackedFloat32Array([lane])
	spots.append_array(lows)
	spots.append_array(highs)
	for spot: float in spots:
		if absf(spot) > limit or _inside_any(spot, lows, highs):
			continue
		var cost := absf(spot - lane)
		if cost < best_cost:
			best_cost = cost
			best = spot
	return best if not is_inf(best_cost) else INF


func _inside_any(spot: float, lows: PackedFloat32Array, highs: PackedFloat32Array) -> bool:
	for k in lows.size():
		if spot > lows[k] + 0.001 and spot < highs[k] - 0.001:
			return true
	return false


## Things too close together to go between with room to spare: the best of what is left.
func _middle_of_widest_gap(lows: PackedFloat32Array, highs: PackedFloat32Array, limit: float) -> float:
	var order: Array[int] = []
	for k in lows.size():
		order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool: return lows[a] < lows[b])
	var best := 0.0
	var widest := -INF
	var from_x := -limit - _RIVAL_CLEARANCE_M
	for k: int in order:
		var gap := lows[k] + _RIVAL_CLEARANCE_M - from_x
		if gap > widest:
			widest = gap
			best = from_x + gap * 0.5
		from_x = maxf(from_x, highs[k] - _RIVAL_CLEARANCE_M)
	var last_gap := limit + _RIVAL_CLEARANCE_M - from_x
	if last_gap > widest:
		best = from_x + last_gap * 0.5
	return clampf(best, -limit, limit)


## A bridge is narrower than the road up to it, so a rival lines up for it well before.
func _add_bridge_blocks() -> void:
	var i := 0
	while i < _pts.size():
		if _road_types[i] != TrackFile.ROAD_BRIDGE:
			i += 1
			continue
		var from_i := i
		while i < _pts.size() and _road_types[i] == TrackFile.ROAD_BRIDGE:
			i += 1
		var half := _half_ws[from_i]
		var from_s := _dists[from_i] - _BRIDGE_LINE_UP_M
		var to_s := _dists[i - 1]
		_blocks.append({"s": from_s, "to": to_s, "bridge": half})
	_blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))


## True on a road narrow enough, with walls beside it, that a rival has to hold its lane closely.
func is_tight_road() -> bool:
	return _style == TrackFile.STYLE_MOUNTAIN or _style == TrackFile.STYLE_AQUEDUCT


## The most a rival should be going with gravel within `look` meters of `s`, or INF.
func gravel_limit(s: float, look: float) -> float:
	if _style != TrackFile.STYLE_MOUNTAIN:
		return INF
	var ahead := sample_at(s)
	if str(ahead["road_type"]) == TrackFile.ROAD_GRAVEL:
		return GRAVEL_RIVAL_MPS
	var step := 10.0
	var at := s + step
	while at <= s + look:
		if str(sample_at(at)["road_type"]) == TrackFile.ROAD_GRAVEL:
			return GRAVEL_RIVAL_MPS
		at += step
	return INF


## A road rock under a car at `world`: its place, removed from the list so it counts once, or
## Vector3.INF with none there.
func take_road_rock(world: Vector3) -> Vector3:
	for k in _road_rocks.size():
		var rock := _road_rocks[k]
		if Vector2(world.x - rock.x, world.z - rock.z).length_squared() < ROAD_ROCK_REACH * ROAD_ROCK_REACH:
			_road_rocks.remove_at(k)
			return rock
	return Vector3.INF


## Where a car at `world` must go when it sits in a barrier band just outside
## the road edge. Returns `world` unchanged when it is clear.
func obstacle_escape(world: Vector3) -> Vector3:
	var sample := closest_sample(world)
	var lat := float(sample.get("lateral", 0.0))
	var left_ext := float(sample.get("left_ext", 0.0))
	var right_ext := float(sample.get("right_ext", 0.0))
	var center: Vector3 = sample.get("position", world)
	var right_v: Vector3 = sample.get("right", Vector3.RIGHT)
	var safe := world
	if bool(sample.get("obstacle_left", false)) and lat < -left_ext and lat > -(left_ext + OBSTACLE_BAND):
		safe = center - right_v * maxf(left_ext - 0.5, 0.4)
	elif bool(sample.get("obstacle_right", false)) and lat > right_ext and lat < right_ext + OBSTACLE_BAND:
		safe = center + right_v * maxf(right_ext - 0.5, 0.4)
	else:
		return world
	return Vector3(safe.x, world.y, safe.z)


func finish_basis() -> Transform3D:
	if _pts.is_empty():
		return Transform3D.IDENTITY
	var sample := sample_at(_race_length)
	var pos: Vector3 = sample["position"]
	var yaw: float = sample["yaw"]
	return Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0.0, 2.0, 0.0))


func build_road_course() -> void:
	if _built:
		return
	_build_path()
	if _pts.size() < 2:
		return
	if _style == TrackFile.STYLE_AQUEDUCT:
		_TrackSides.build_aqueduct(self, _pts, _yaws, _STREET_RUN_IN_M)
	elif _style == TrackFile.STYLE_MOUNTAIN:
		_TrackSides.build_mountain(self, _pts, _yaws, _half_ws, _road_types, _left_sides, _right_sides, _rails, _STREET_RUN_IN_M)
		_build_road_mesh()
	else:
		_build_terrain()
		_build_road_mesh()
	if _style == TrackFile.STYLE_AQUEDUCT or _style == TrackFile.STYLE_MOUNTAIN:
		_StreetScenery.build(self, _scenery, _half_ws[0] * 2.0)
		var found: Dictionary = _CourseScenery.build(self, _scenery)
		_blocks.assign(found["blocks"])
		_road_rocks.assign(found["rocks"])
		_add_bridge_blocks()
	elif _street:
		_StreetScenery.build(self, _scenery, get_half_width() * 2.0)
	else:
		_build_curbs()
		_build_obstacles()
		_build_narrow_signs()
		_build_finish_line()
	_built = true


func _ready() -> void:
	var course := GameState.race_track_path()
	if not course.is_empty():
		track_path = course
	if GameState.race_on_track():
		build_road_course()


func _empty_sample() -> Dictionary:
	return _make_sample(Vector3.ZERO, 0.0, 0.0, 0.0)


func _make_sample(pos: Vector3, yaw: float, s: float, lateral: float, index: int = 0) -> Dictionary:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var hw := ROAD_HALF_W
	var surface := TrackFile.SURFACE_REGULAR
	var rtype := TrackFile.ROAD_REGULAR
	if index >= 0 and index < _half_ws.size():
		hw = _half_ws[index]
		surface = _surfaces[index]
		rtype = _road_types[index]
	var extents := TrackFile.driveable_extents(hw * 2.0, rtype)
	return {
		"position": pos,
		"forward": forward,
		"right": right,
		"yaw": yaw,
		"s": s,
		"lateral": lateral,
		"half_width": hw,
		"left_ext": extents.x,
		"right_ext": extents.y,
		"surface": surface,
		"road_type": rtype,
		"gravel": rtype == TrackFile.ROAD_GRAVEL,
		"obstacle_left": TrackFile.obstacle_left(rtype),
		"obstacle_right": TrackFile.obstacle_right(rtype),
	}


func _build_path() -> void:
	_pts.clear()
	_bins.clear()
	_yaws.clear()
	_dists.clear()
	_half_ws.clear()
	_surfaces.clear()
	_road_types.clear()
	_pos = Vector3.ZERO
	_yaw = 0.0
	_length = 0.0
	_race_length = 0.0
	var data := TrackFile.load_path(track_path)
	for warning: String in data.warnings:
		push_warning("[track] %s" % warning)
	if not data.errors.is_empty():
		for error_text: String in data.errors:
			push_error("[track] %s" % error_text)
		return
	_style = data.style
	_street = _style != TrackFile.STYLE_CIRCUIT
	_scenery.assign(data.scenery)
	var path_ids: Array = data.path_ids
	if path_ids.size() < 2:
		push_error("[track] Race path is too short.")
		return
	var n := path_ids.size()
	var pts: Array[Vector3] = []
	var roads: Array[Dictionary] = []
	for i in n:
		pts.append(TrackFile.world_position(data.nodes[int(path_ids[i])]))
	for i in range(n - 1):
		roads.append(TrackFile.find_road(data, int(path_ids[i]), int(path_ids[i + 1])))
	var cuts: PackedFloat32Array = PackedFloat32Array()
	cuts.resize(n)
	for i in range(1, n - 1):
		cuts[i] = _fillet_cut(pts[i - 1], pts[i], pts[i + 1])
	_apply_road(roads[0])
	_pos = pts[0]
	_yaw = atan2(pts[1].x - pts[0].x, pts[1].z - pts[0].z)
	_push_sample()
	for i in range(1, n - 1):
		var in_dir := (pts[i] - pts[i - 1])
		in_dir.y = 0.0
		if in_dir.length() > 0.0001:
			in_dir = in_dir.normalized()
		var out_dir := (pts[i + 1] - pts[i])
		out_dir.y = 0.0
		if out_dir.length() > 0.0001:
			out_dir = out_dir.normalized()
		var cut: float = cuts[i]
		_apply_road(roads[i - 1])
		if cut < 0.05:
			_append_to(pts[i])
			continue
		var p0 := pts[i] - in_dir * cut
		var p2 := pts[i] + out_dir * cut
		var in_span := Vector3(pts[i].x - pts[i - 1].x, 0.0, pts[i].z - pts[i - 1].z).length()
		var out_span := Vector3(pts[i + 1].x - pts[i].x, 0.0, pts[i + 1].z - pts[i].z).length()
		if in_span > 0.0001:
			p0.y = lerpf(pts[i - 1].y, pts[i].y, 1.0 - cut / in_span)
		if out_span > 0.0001:
			p2.y = lerpf(pts[i].y, pts[i + 1].y, cut / out_span)
		_append_to(p0)
		_append_bezier(p0, pts[i], p2, roads[i - 1], roads[i])
	_apply_road(roads[n - 2])
	_append_to(pts[n - 1])
	_smooth_path_heights(pts)
	_race_length = _length
	_append_runoff()
	_fill_sides(data, path_ids)
	_build_bins()


## Each sample's side heights, running straight from node to node. Past the last node they hold.
func _fill_sides(data: Dictionary, path_ids: Array) -> void:
	_left_sides.resize(_pts.size())
	_right_sides.resize(_pts.size())
	_rails.resize(_pts.size())
	_left_sides.fill(0.0)
	_right_sides.fill(0.0)
	_rails.fill(0)
	if _style != TrackFile.STYLE_MOUNTAIN:
		return
	var k := 0
	for i in _pts.size():
		var s := _dists[i]
		while k < _node_s.size() - 2 and s >= _node_s[k + 1]:
			k += 1
		var k1 := mini(k + 1, _node_s.size() - 1)
		var a: Dictionary = data.nodes[int(path_ids[k])]
		var b: Dictionary = data.nodes[int(path_ids[k1])]
		var span := _node_s[k1] - _node_s[k]
		var t := clampf((s - _node_s[k]) / span, 0.0, 1.0) if span > 0.0001 else 0.0
		_left_sides[i] = lerpf(float(a["left"]), float(b["left"]), t)
		_right_sides[i] = lerpf(float(a["right"]), float(b["right"]), t)
		_rails[i] = 1 if bool(a["rail"]) else 0


## Replace the straight ramps between nodes with a smooth curve that still passes through each height.
func _smooth_path_heights(nodes: Array[Vector3]) -> void:
	if _pts.size() < 2 or nodes.size() < 2:
		return
	var knot_s := PackedFloat32Array()
	var knot_y := PackedFloat32Array()
	var search_from := 0
	for node in nodes:
		var best_i := search_from
		var best_d := _planar_distance_sq(node, _pts[search_from])
		for i in range(search_from + 1, _pts.size()):
			var d := _planar_distance_sq(node, _pts[i])
			if d < best_d:
				best_d = d
				best_i = i
		knot_s.append(_dists[best_i])
		knot_y.append(node.y)
		search_from = best_i
	for i in range(1, knot_s.size()):
		if knot_s[i] <= knot_s[i - 1]:
			knot_s[i] = knot_s[i - 1] + 0.5
	_node_s = knot_s
	var slopes := _height_slopes(knot_s, knot_y)
	var k := 0
	for i in _pts.size():
		var s := _dists[i]
		while k < knot_s.size() - 2 and s >= knot_s[k + 1]:
			k += 1
		var k1 := mini(k + 1, knot_s.size() - 1)
		var span := knot_s[k1] - knot_s[k]
		var y := knot_y[k]
		if span > 0.0001:
			var t := clampf((s - knot_s[k]) / span, 0.0, 1.0)
			y = _hermite_height(knot_y[k], slopes[k], knot_y[k1], slopes[k1], span, t)
		var p := _pts[i]
		p.y = y
		_pts[i] = p


## Fritsch-Carlson slopes: the curve stays between the node heights and meets smoothly at each one.
func _height_slopes(s: PackedFloat32Array, y: PackedFloat32Array) -> PackedFloat32Array:
	var n := s.size()
	var delta := PackedFloat32Array()
	delta.resize(n - 1)
	for i in n - 1:
		var span := s[i + 1] - s[i]
		delta[i] = 0.0 if span <= 0.0001 else (y[i + 1] - y[i]) / span
	var m := PackedFloat32Array()
	m.resize(n)
	# Ease off the start line and onto the finish with a level grade.
	m[0] = 0.0
	m[n - 1] = 0.0
	for i in range(1, n - 1):
		if delta[i - 1] * delta[i] <= 0.0:
			m[i] = 0.0
		else:
			m[i] = (delta[i - 1] + delta[i]) * 0.5
	for i in n - 1:
		if absf(delta[i]) < 0.0000001:
			m[i] = 0.0
			m[i + 1] = 0.0
			continue
		var a := m[i] / delta[i]
		var b := m[i + 1] / delta[i]
		var mag := a * a + b * b
		if mag > 9.0:
			var scale := 3.0 / sqrt(mag)
			m[i] = scale * a * delta[i]
			m[i + 1] = scale * b * delta[i]
	return m


func _hermite_height(y0: float, m0: float, y1: float, m1: float, span: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	var h00 := 2.0 * t3 - 3.0 * t2 + 1.0
	var h10 := t3 - 2.0 * t2 + t
	var h01 := -2.0 * t3 + 3.0 * t2
	var h11 := t3 - t2
	return h00 * y0 + h10 * span * m0 + h01 * y1 + h11 * span * m1


## Keep the last heading and height, so the pavement runs on in a straight line.
func _append_runoff() -> void:
	if _pts.is_empty():
		return
	_pos = _pts[_pts.size() - 1]
	_yaw = _yaws[_yaws.size() - 1]
	var ahead := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var dest := _pos + ahead * _RUNOFF_M
	dest.y = _pos.y
	_append_to(dest)


func _apply_road(road: Dictionary) -> void:
	if road.is_empty():
		_seg_half_w = ROAD_HALF_W
		_seg_surface = TrackFile.SURFACE_REGULAR
		_seg_road_type = TrackFile.ROAD_REGULAR
		return
	_seg_half_w = maxf(float(road.get("width", TrackFile.DEFAULT_WIDTH)) * 0.5, 0.5)
	_seg_surface = str(road.get("surface", TrackFile.SURFACE_REGULAR))
	_seg_road_type = str(road.get("type", TrackFile.ROAD_REGULAR))


func _push_sample() -> void:
	_pts.append(_pos)
	_yaws.append(_yaw)
	_dists.append(_length)
	_half_ws.append(_seg_half_w)
	_surfaces.append(_seg_surface)
	_road_types.append(_seg_road_type)


func _append_to(dest: Vector3) -> void:
	var delta := dest - _pos
	var dist := delta.length()
	if dist < 0.0001:
		return
	var planar := Vector3(delta.x, 0.0, delta.z)
	if planar.length() > 0.0001:
		_yaw = atan2(planar.x, planar.z)
	var dir := delta / dist
	var left := dist
	while left > 0.0001:
		var step := minf(BAKE_STEP, left)
		_pos += dir * step
		_length += step
		_push_sample()
		left -= step


func _fillet_cut(prev_pt: Vector3, corner: Vector3, next_pt: Vector3) -> float:
	var incoming := corner - prev_pt
	var outgoing := next_pt - corner
	incoming.y = 0.0
	outgoing.y = 0.0
	var in_len := incoming.length()
	var out_len := outgoing.length()
	if in_len < 0.05 or out_len < 0.05:
		return 0.0
	var turn := incoming.normalized().dot(outgoing.normalized())
	var angle := acos(clampf(turn, -1.0, 1.0))
	if angle < FILLET_MIN_ANGLE:
		return 0.0
	return minf(FILLET_MAX_CUT, minf(in_len * FILLET_LEN_FRACTION, out_len * FILLET_LEN_FRACTION))


func _append_bezier(
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	road_in: Dictionary,
	road_out: Dictionary
) -> void:
	var approx := p0.distance_to(p1) + p1.distance_to(p2)
	var steps := maxi(10, int(ceil(approx / BAKE_STEP)))
	for k in range(1, steps + 1):
		var t := float(k) / float(steps)
		if t < 0.5:
			_apply_road(road_in)
		else:
			_apply_road(road_out)
		var omt := 1.0 - t
		var pos := p0 * (omt * omt) + p1 * (2.0 * omt * t) + p2 * (t * t)
		var deriv := (p1 - p0) * (2.0 * omt) + (p2 - p1) * (2.0 * t)
		deriv.y = 0.0
		if deriv.length_squared() > 0.000001:
			_yaw = atan2(deriv.x, deriv.z)
		_length += _pos.distance_to(pos)
		_pos = pos
		_push_sample()


func _build_bins() -> void:
	_bins.clear()
	for i in _pts.size():
		var key := _bin_key(_pts[i])
		var packed: PackedInt32Array = _bins.get(key, PackedInt32Array())
		packed.append(i)
		_bins[key] = packed


func _bin_key(point: Vector3) -> Vector2i:
	return Vector2i(int(floor(point.x / _BIN_CELL)), int(floor(point.z / _BIN_CELL)))


func _nearest_index(world: Vector3) -> int:
	if _pts.is_empty():
		return 0
	if _bins.is_empty():
		return _nearest_index_scan(world)
	var cx := int(floor(world.x / _BIN_CELL))
	var cz := int(floor(world.z / _BIN_CELL))
	var best_i := 0
	var best_d := INF
	var r := 0
	while r < 40:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and absi(dx) != r and absi(dz) != r:
					continue
				var key := Vector2i(cx + dx, cz + dz)
				if not _bins.has(key):
					continue
				var packed: PackedInt32Array = _bins[key]
				for index in packed:
					var d := _planar_distance_sq(world, _pts[index])
					if d < best_d:
						best_d = d
						best_i = int(index)
		var left := world.x - float(cx - r) * _BIN_CELL
		var right := float(cx + r + 1) * _BIN_CELL - world.x
		var down := world.z - float(cz - r) * _BIN_CELL
		var up := float(cz + r + 1) * _BIN_CELL - world.z
		var edge := minf(minf(left, right), minf(down, up))
		if best_d <= edge * edge:
			break
		r += 1
	return best_i


func _nearest_index_scan(world: Vector3) -> int:
	var best_i := 0
	var best_d := INF
	for i in _pts.size():
		var d := _planar_distance_sq(world, _pts[i])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _planar_distance_sq(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


func _index_at_distance(s: float) -> int:
	var lo := 0
	var hi := _dists.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if _dists[mid] < s:
			lo = mid + 1
		else:
			hi = mid
	return maxi(lo - 1, 0)


func _make_mat(color: Color, roughness: float = 0.72) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _build_terrain() -> void:
	if _pts.is_empty():
		return
	var min_x := _pts[0].x
	var max_x := _pts[0].x
	var min_z := _pts[0].z
	var max_z := _pts[0].z
	for p in _pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var pad := _STREET_TERRAIN_PAD if _street else _TERRAIN_PAD
	var grid := _STREET_TERRAIN_STEP if _street else _TERRAIN_STEP
	var origin_x := min_x - pad
	var origin_z := min_z - pad
	var span_x := max_x - min_x + pad * 2.0
	var span_z := max_z - min_z + pad * 2.0
	var cols := maxi(int(ceil(span_x / grid)), 1)
	var rows := maxi(int(ceil(span_z / grid)), 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rows + 1:
		var z := origin_z + span_z * float(row) / float(rows)
		for col in cols + 1:
			var x := origin_x + span_x * float(col) / float(cols)
			var y := _grass_height(x, z) - _TERRAIN_SINK
			if _street and _grass_dist_sq <= _half_ws[0] * _half_ws[0]:
				y -= _STREET_UNDER_ROAD_SINK
			st.set_uv(Vector2(float(col), float(row)))
			st.add_vertex(Vector3(x, y, z))
	var stride := cols + 1
	for row in rows:
		for col in cols:
			var i00 := row * stride + col
			var i10 := i00 + 1
			var i01 := i00 + stride
			var i11 := i01 + 1
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i00)
			st.add_index(i11)
			st.add_index(i01)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _make_mat(STREET_TERRAIN_COLOR if _street else TERRAIN_COLOR, 0.95))
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)


## Road height at a grass vertex. Coarser than the driving query, and local to the mesh build.
func _grass_height(x: float, z: float) -> float:
	var best_i := 0
	var best_d := INF
	var step := 4
	var i := 0
	while i < _pts.size():
		var dx := x - _pts[i].x
		var dz := z - _pts[i].z
		var d := dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best_i = i
		i += step
	var start := maxi(best_i - step, 0)
	var finish := mini(best_i + step, _pts.size() - 1)
	for index in range(start, finish + 1):
		var dx := x - _pts[index].x
		var dz := z - _pts[index].z
		var d := dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best_i = index
	var height := _pts[best_i].y
	for j: int in [best_i - 1, best_i]:
		if j < 0 or j + 1 >= _pts.size():
			continue
		var a := _pts[j]
		var b := _pts[j + 1]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var len2 := abx * abx + abz * abz
		if len2 < 0.0001:
			continue
		var apx := x - a.x
		var apz := z - a.z
		var t := clampf((apx * abx + apz * abz) / len2, 0.0, 1.0)
		var px := abx * t
		var pz := abz * t
		var ex := apx - px
		var ez := apz - pz
		var dist := ex * ex + ez * ez
		if dist < best_d:
			best_d = dist
			height = lerpf(a.y, b.y, t)
	_grass_dist_sq = best_d
	return height


func _build_road_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if _street:
		_add_run_in(st)
	for i in range(_pts.size() - 1):
		var yaw0: float = _yaws[i]
		var yaw1: float = _yaws[i + 1]
		var t0: String = _road_types[i] if i < _road_types.size() else TrackFile.ROAD_REGULAR
		var t1: String = _road_types[i + 1] if i + 1 < _road_types.size() else t0
		var hw0 := _half_ws[i] if i < _half_ws.size() else ROAD_HALF_W
		var hw1 := _half_ws[i + 1] if i + 1 < _half_ws.size() else hw0
		var e0 := TrackFile.driveable_extents(hw0 * 2.0, t0)
		var e1 := TrackFile.driveable_extents(hw1 * 2.0, t1)
		var r0 := Vector3(cos(yaw0), 0.0, -sin(yaw0))
		var r1 := Vector3(cos(yaw1), 0.0, -sin(yaw1))
		var l0 := _pts[i] - r0 * e0.x
		var rr0 := _pts[i] + r0 * e0.y
		var l1 := _pts[i + 1] - r1 * e1.x
		var rr1 := _pts[i + 1] + r1 * e1.y
		var v := _dists[i] * 0.15
		var v1 := _dists[i + 1] * 0.15
		_add_tri(st, l0, rr0, rr1, Vector2(0, v), Vector2(1, v), Vector2(1, v1))
		_add_tri(st, l0, rr1, l1, Vector2(0, v), Vector2(1, v1), Vector2(0, v1))
	st.generate_normals()
	var mesh := st.commit()
	var mat := _make_mat(MOUNTAIN_ROAD_COLOR if _style == TrackFile.STYLE_MOUNTAIN else ROAD_COLOR, 0.85)
	mesh.surface_set_material(0, mat)
	_road_mi = MeshInstance3D.new()
	_road_mi.name = "RoadMesh"
	_road_mi.mesh = mesh
	add_child(_road_mi)
	if _style == TrackFile.STYLE_STREET:
		_build_street_shoulders()
	elif _style == TrackFile.STYLE_MOUNTAIN:
		_build_gravel()


## Street Rod 2's road work: the pavement gone for a stretch, a gray patch the width of the road.
func _build_gravel() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := Vector3.UP * 0.02
	for i in range(_pts.size() - 1):
		if _road_types[i] != TrackFile.ROAD_GRAVEL and _road_types[i + 1] != TrackFile.ROAD_GRAVEL:
			continue
		var r0 := Vector3(cos(_yaws[i]), 0.0, -sin(_yaws[i])) * _half_ws[i]
		var r1 := Vector3(cos(_yaws[i + 1]), 0.0, -sin(_yaws[i + 1])) * _half_ws[i + 1]
		var a := _pts[i] + lift
		var b := _pts[i + 1] + lift
		_add_tri(st, a - r0, a + r0, b + r1, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE)
		_add_tri(st, a - r0, b + r1, b - r1, Vector2.ZERO, Vector2.ONE, Vector2.UP)
	st.generate_normals()
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, _make_mat(_GRAVEL_COLOR, 0.98))
	var mi := MeshInstance3D.new()
	mi.name = "Gravel"
	mi.mesh = mesh
	add_child(mi)


## A gravel strip down each side of the road, over the run-in too.
func _build_street_shoulders() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yaw: float = _yaws[0]
	var run_in := _pts[0] - Vector3(sin(yaw), 0.0, cos(yaw)) * _STREET_RUN_IN_M
	_add_shoulder_span(st, run_in, yaw, _half_ws[0], _pts[0], yaw, _half_ws[0])
	for i in range(_pts.size() - 1):
		_add_shoulder_span(st, _pts[i], _yaws[i], _half_ws[i], _pts[i + 1], _yaws[i + 1], _half_ws[i + 1])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _make_mat(STREET_SHOULDER_COLOR, 0.95))
	var mi := MeshInstance3D.new()
	mi.name = "Shoulders"
	mi.mesh = mesh
	add_child(mi)


func _add_shoulder_span(st: SurfaceTool, p0: Vector3, yaw0: float, hw0: float, p1: Vector3, yaw1: float, hw1: float) -> void:
	var r0 := Vector3(cos(yaw0), 0.0, -sin(yaw0))
	var r1 := Vector3(cos(yaw1), 0.0, -sin(yaw1))
	for side: float in [-1.0, 1.0]:
		var inner0 := p0 + r0 * (side * hw0)
		var outer0 := p0 + r0 * (side * (hw0 + _STREET_SHOULDER_W))
		var inner1 := p1 + r1 * (side * hw1)
		var outer1 := p1 + r1 * (side * (hw1 + _STREET_SHOULDER_W))
		var a0 := inner0 if side > 0.0 else outer0
		var b0 := outer0 if side > 0.0 else inner0
		var a1 := inner1 if side > 0.0 else outer1
		var b1 := outer1 if side > 0.0 else inner1
		_add_tri(st, a0, b0, b1, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
		_add_tri(st, a0, b1, a1, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))


func _add_run_in(st: SurfaceTool) -> void:
	var yaw: float = _yaws[0]
	var side := Vector3(cos(yaw), 0.0, -sin(yaw)) * _half_ws[0]
	var back := _pts[0] - Vector3(sin(yaw), 0.0, cos(yaw)) * _STREET_RUN_IN_M
	var v := -_STREET_RUN_IN_M * 0.15
	_add_tri(st, back - side, back + side, _pts[0] + side, Vector2(0, v), Vector2(1, v), Vector2(1, 0))
	_add_tri(st, back - side, _pts[0] + side, _pts[0] - side, Vector2(0, v), Vector2(1, 0), Vector2(0, 0))


func _add_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	uva: Vector2,
	uvb: Vector2,
	uvc: Vector2
) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.set_uv(uvb)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.set_uv(uvc)
	st.add_vertex(c)


func _sample_type(i: int) -> String:
	if i < 0 or i >= _road_types.size():
		return TrackFile.ROAD_REGULAR
	return _road_types[i]


func _sample_extents(i: int) -> Vector2:
	var hw := _half_ws[i] if i >= 0 and i < _half_ws.size() else ROAD_HALF_W
	return TrackFile.driveable_extents(hw * 2.0, _sample_type(i))


func _build_curbs() -> void:
	var red_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	var stone_i := 0
	var stride := maxi(1, int(round(CURB_L / BAKE_STEP)))
	var i := 0
	while i < _pts.size():
		var yaw: float = _yaws[i]
		var basis := Basis(Vector3.UP, yaw)
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var ext := _sample_extents(i)
		var pos := _pts[i]
		_add_curb_stone(red_xforms, white_xforms, stone_i, basis, pos - right * ext.x)
		_add_curb_stone(red_xforms, white_xforms, stone_i + 1, basis, pos + right * ext.y)
		stone_i += 1
		i += stride
	for j in range(1, _pts.size()):
		var prev := _sample_extents(j - 1)
		var cur := _sample_extents(j)
		if absf(prev.x - cur.x) > 0.35:
			stone_i = _add_perp_curbs(red_xforms, white_xforms, stone_i, j, false, prev.x, cur.x)
		if absf(prev.y - cur.y) > 0.35:
			stone_i = _add_perp_curbs(red_xforms, white_xforms, stone_i, j, true, prev.y, cur.y)
	_add_box_multimesh(self, "CurbRed", Vector3(CURB_W, CURB_H, CURB_L), CURB_RED, red_xforms)
	_add_box_multimesh(self, "CurbWhite", Vector3(CURB_W, CURB_H, CURB_L), CURB_WHITE, white_xforms)


func _add_curb_stone(
	red_xforms: Array[Transform3D],
	white_xforms: Array[Transform3D],
	stone_i: int,
	basis: Basis,
	world: Vector3
) -> void:
	var xf := Transform3D(basis, world + Vector3(0.0, CURB_H * 0.5, 0.0))
	if stone_i % 2 == 0:
		red_xforms.append(xf)
	else:
		white_xforms.append(xf)


func _add_perp_curbs(
	red_xforms: Array[Transform3D],
	white_xforms: Array[Transform3D],
	stone_i: int,
	index: int,
	on_right: bool,
	ext_a: float,
	ext_b: float
) -> int:
	var yaw: float = _yaws[index]
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var side := 1.0 if on_right else -1.0
	var along := right * side
	var basis := Basis(Vector3.UP, yaw + PI * 0.5)
	var a := minf(ext_a, ext_b)
	var b := maxf(ext_a, ext_b)
	var span := b - a
	var count := maxi(1, int(ceil(span / CURB_L)))
	var step := span / float(count)
	for k in count:
		var lat := a + (k + 0.5) * step
		_add_curb_stone(red_xforms, white_xforms, stone_i, basis, _pts[index] + along * lat)
		stone_i += 1
	return stone_i


func _build_obstacles() -> void:
	var orange := Color(0.93, 0.38, 0.06, 1)
	var white := Color(0.96, 0.96, 0.93, 1)
	var body_xforms: Array[Transform3D] = []
	var stripe_xforms: Array[Transform3D] = []
	var body := StaticBody3D.new()
	body.name = "ConstructionBarriers"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"track_obstacle", true)
	add_child(body)
	const BARRIER_L := 1.25
	const BARRIER_H := 1.05
	const BARRIER_W := 0.48
	var stride := maxi(1, int(round(BARRIER_L / BAKE_STEP)))
	var i := 0
	while i < _pts.size():
		var rtype := _sample_type(i)
		var ext := _sample_extents(i)
		var yaw: float = _yaws[i]
		var basis := Basis(Vector3.UP, yaw)
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		if TrackFile.obstacle_left(rtype):
			_place_edge_barrier(
				body, body_xforms, stripe_xforms, _pts[i], basis, -right,
				ext.x, BARRIER_L, BARRIER_H, BARRIER_W
			)
		if TrackFile.obstacle_right(rtype):
			_place_edge_barrier(
				body, body_xforms, stripe_xforms, _pts[i], basis, right,
				ext.y, BARRIER_L, BARRIER_H, BARRIER_W
			)
		i += stride
	for j in range(1, _pts.size()):
		var prev_t := _sample_type(j - 1)
		var cur_t := _sample_type(j)
		var prev := _sample_extents(j - 1)
		var cur := _sample_extents(j)
		if TrackFile.obstacle_left(prev_t) != TrackFile.obstacle_left(cur_t) or absf(prev.x - cur.x) > 0.35:
			if TrackFile.obstacle_left(prev_t) or TrackFile.obstacle_left(cur_t):
				_place_perp_barriers(
					body, body_xforms, stripe_xforms, j, false, prev.x, cur.x,
					BARRIER_L, BARRIER_H, BARRIER_W
				)
		if TrackFile.obstacle_right(prev_t) != TrackFile.obstacle_right(cur_t) or absf(prev.y - cur.y) > 0.35:
			if TrackFile.obstacle_right(prev_t) or TrackFile.obstacle_right(cur_t):
				_place_perp_barriers(
					body, body_xforms, stripe_xforms, j, true, prev.y, cur.y,
					BARRIER_L, BARRIER_H, BARRIER_W
				)
	_add_box_multimesh(self, "BarrierOrange", Vector3(BARRIER_W, BARRIER_H, BARRIER_L), orange, body_xforms)
	_add_box_multimesh(self, "BarrierStripe", Vector3(BARRIER_W + 0.04, 0.16, BARRIER_L + 0.04), white, stripe_xforms)


func _build_narrow_signs() -> void:
	const LEAD_M := 12.0
	const OUTSET := 1.15
	const TOE := 0.22
	var root := Node3D.new()
	root.name = "NarrowSigns"
	add_child(root)
	var sign_i := 0
	for j in range(1, _pts.size()):
		var prev_t := _sample_type(j - 1)
		var cur_t := _sample_type(j)
		var now_narrow := TrackFile.narrows_left(cur_t) or TrackFile.narrows_right(cur_t)
		var was_narrow := TrackFile.narrows_left(prev_t) or TrackFile.narrows_right(prev_t)
		if not now_narrow or was_narrow:
			continue
		var s := maxf(0.0, _dists[j] - LEAD_M)
		var sample := sample_at(s)
		var pos: Vector3 = sample["position"]
		var yaw: float = sample["yaw"]
		var right_v: Vector3 = sample["right"]
		var left_ext := float(sample["left_ext"])
		var right_ext := float(sample["right_ext"])
		var left_n := TrackFile.narrows_left(cur_t)
		var right_n := TrackFile.narrows_right(cur_t)
		_add_narrow_sign(
			root, "NarrowSignL%d" % sign_i,
			pos - right_v * (left_ext + OUTSET),
			yaw + TOE, left_n, right_n
		)
		_add_narrow_sign(
			root, "NarrowSignR%d" % sign_i,
			pos + right_v * (right_ext + OUTSET),
			yaw - TOE, left_n, right_n
		)
		sign_i += 1


func _add_narrow_sign(
	parent: Node3D,
	node_name: String,
	world: Vector3,
	yaw: float,
	left_narrows: bool,
	right_narrows: bool
) -> void:
	var mesh := _get_sign_mesh()
	if mesh == null:
		return
	var sign := Node3D.new()
	sign.name = node_name
	sign.transform = Transform3D(Basis(Vector3.UP, yaw), world)
	sign.scale = Vector3(SIGN_SCALE, SIGN_SCALE, SIGN_SCALE)
	parent.add_child(sign)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	var plate := StandardMaterial3D.new()
	plate.albedo_texture = _get_sign_texture(left_narrows, right_narrows)
	plate.roughness = 0.42
	plate.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.set_surface_override_material(0, plate)
	if mesh.get_surface_count() > 1:
		mi.set_surface_override_material(1, _make_mat(POST_COLOR, 0.4))
	sign.add_child(mi)


func _sign_texture_path(left_narrows: bool, right_narrows: bool) -> String:
	if left_narrows and right_narrows:
		return SIGN_TEX_BOTH
	if left_narrows:
		return SIGN_TEX_LEFT
	return SIGN_TEX_RIGHT


func _get_sign_texture(left_narrows: bool, right_narrows: bool) -> Texture2D:
	var path := _sign_texture_path(left_narrows, right_narrows)
	if _sign_textures.has(path):
		return _sign_textures[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			tex = loaded
	if tex == null:
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
	_sign_textures[path] = tex
	return tex


func _get_sign_mesh() -> ArrayMesh:
	if _sign_mesh != null:
		return _sign_mesh
	_sign_mesh = _load_sign_obj(SIGN_OBJ)
	return _sign_mesh


func _load_sign_obj(path: String) -> ArrayMesh:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[track] Sign mesh not found: %s" % path)
		return null
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var plate_v := PackedVector3Array()
	var plate_n := PackedVector3Array()
	var plate_uv := PackedVector2Array()
	var post_v := PackedVector3Array()
	var post_n := PackedVector3Array()
	var post_uv := PackedVector2Array()
	var face_i := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("v "):
			var p := line.split(" ", false)
			if p.size() >= 4:
				verts.append(Vector3(float(p[1]), float(p[2]), float(p[3])))
		elif line.begins_with("vt "):
			var p := line.split(" ", false)
			if p.size() >= 3:
				uvs.append(Vector2(float(p[1]), 1.0 - float(p[2])))
		elif line.begins_with("f "):
			var p := line.split(" ", false)
			var fv: Array[Vector3] = []
			var ft: Array[Vector2] = []
			for k in range(1, p.size()):
				var idx := String(p[k]).split("/")
				var vi := int(idx[0]) - 1
				if vi < 0 or vi >= verts.size():
					continue
				fv.append(verts[vi])
				if idx.size() > 1 and not idx[1].is_empty():
					var ti := int(idx[1]) - 1
					ft.append(uvs[ti] if ti >= 0 and ti < uvs.size() else Vector2.ZERO)
				else:
					ft.append(Vector2.ZERO)
			if fv.size() >= 3:
				if face_i < 6:
					_append_obj_face(plate_v, plate_n, plate_uv, fv, ft)
				else:
					_append_obj_face(post_v, post_n, post_uv, fv, ft)
			face_i += 1
	file.close()
	var mesh := ArrayMesh.new()
	if not plate_v.is_empty():
		_add_obj_surface(mesh, plate_v, plate_n, plate_uv)
	if not post_v.is_empty():
		_add_obj_surface(mesh, post_v, post_n, post_uv)
	if mesh.get_surface_count() == 0:
		push_error("[track] Sign mesh has no faces: %s" % path)
		return null
	return mesh


func _append_obj_face(
	out_v: PackedVector3Array,
	out_n: PackedVector3Array,
	out_uv: PackedVector2Array,
	fv: Array[Vector3],
	ft: Array[Vector2]
) -> void:
	var n := (fv[1] - fv[0]).cross(fv[2] - fv[0])
	if n.length_squared() > 0.000001:
		n = n.normalized()
	else:
		n = Vector3.UP
	for t in range(1, fv.size() - 1):
		out_v.append(fv[0])
		out_v.append(fv[t])
		out_v.append(fv[t + 1])
		out_n.append(n)
		out_n.append(n)
		out_n.append(n)
		out_uv.append(ft[0])
		out_uv.append(ft[t])
		out_uv.append(ft[t + 1])


func _add_obj_surface(
	mesh: ArrayMesh,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array
) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _place_edge_barrier(
	body: StaticBody3D,
	body_xforms: Array[Transform3D],
	stripe_xforms: Array[Transform3D],
	center: Vector3,
	basis: Basis,
	outward: Vector3,
	driveable_ext: float,
	barrier_l: float,
	barrier_h: float,
	barrier_w: float
) -> void:
	var lat := driveable_ext + barrier_w * 0.5
	var pos := center + outward * lat + Vector3(0.0, barrier_h * 0.5, 0.0)
	var xf := Transform3D(basis, pos)
	body_xforms.append(xf)
	stripe_xforms.append(Transform3D(basis, pos + Vector3(0.0, 0.18, 0.0)))
	var hit := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(barrier_w, barrier_h, barrier_l)
	hit.shape = box
	hit.transform = xf
	body.add_child(hit)


func _place_perp_barriers(
	body: StaticBody3D,
	body_xforms: Array[Transform3D],
	stripe_xforms: Array[Transform3D],
	index: int,
	on_right: bool,
	ext_a: float,
	ext_b: float,
	barrier_l: float,
	barrier_h: float,
	barrier_w: float
) -> void:
	var yaw: float = _yaws[index]
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var along := right if on_right else -right
	var basis := Basis(Vector3.UP, yaw + PI * 0.5)
	var a := minf(ext_a, ext_b)
	var b := maxf(ext_a, ext_b)
	var span := maxf(b - a, barrier_l)
	var count := maxi(1, int(ceil(span / barrier_l)))
	var step := span / float(count)
	for k in count:
		var lat := a + (k + 0.5) * step
		var pos := _pts[index] + along * lat + Vector3(0.0, barrier_h * 0.5, 0.0)
		var xf := Transform3D(basis, pos)
		body_xforms.append(xf)
		stripe_xforms.append(Transform3D(basis, pos + Vector3(0.0, 0.18, 0.0)))
	var hit := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(barrier_w, barrier_h, span)
	hit.shape = box
	var mid := (a + b) * 0.5
	hit.transform = Transform3D(basis, _pts[index] + along * mid + Vector3(0.0, barrier_h * 0.5, 0.0))
	body.add_child(hit)


func _build_finish_line() -> void:
	if _pts.is_empty():
		return
	var sample := sample_at(_race_length)
	var pos: Vector3 = sample["position"]
	var yaw: float = sample["yaw"]
	var root := Node3D.new()
	root.name = "FinishLineVisual"
	root.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	add_child(root)
	_add_checkered_strip(root)
	_add_finish_gantry(root)


func _add_checkered_strip(parent: Node3D) -> void:
	const COLS := 24
	const ROWS := 2
	const SQUARE := 1.25
	var width := COLS * SQUARE
	var origin_x := -width * 0.5
	var origin_z := -ROWS * SQUARE * 0.5
	var black_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	for row in ROWS:
		for col in COLS:
			var pos := Vector3(
				origin_x + (col + 0.5) * SQUARE,
				0.02,
				origin_z + (row + 0.5) * SQUARE
			)
			var xform := Transform3D(Basis.IDENTITY, pos)
			if (row + col) % 2 == 0:
				black_xforms.append(xform)
			else:
				white_xforms.append(xform)
	_add_box_multimesh(parent, "CheckBlack", Vector3(SQUARE, 0.03, SQUARE), CHECK_BLACK, black_xforms)
	_add_box_multimesh(parent, "CheckWhite", Vector3(SQUARE, 0.03, SQUARE), CHECK_WHITE, white_xforms)


func _add_finish_gantry(parent: Node3D) -> void:
	const POST_H := 4.4
	const POST_W := 0.22
	const BANNER_W := 38.6
	const BANNER_H := 0.9
	var post_x := BANNER_W * 0.5
	var post_mat := _make_mat(POST_COLOR, 0.45)
	_add_box(parent, "PostL", Vector3(POST_W, POST_H, POST_W), post_mat, Vector3(-post_x, POST_H * 0.5, 0.0))
	_add_box(parent, "PostR", Vector3(POST_W, POST_H, POST_W), post_mat, Vector3(post_x, POST_H * 0.5, 0.0))
	_add_box(parent, "Crossbar", Vector3(BANNER_W, POST_W, POST_W), post_mat, Vector3(0.0, POST_H, 0.0))
	const BCOLS := 16
	const BROWS := 2
	var cell_w := BANNER_W / float(BCOLS)
	var cell_h := BANNER_H / float(BROWS)
	var banner_y := POST_H - POST_W - BANNER_H * 0.5 - 0.04
	var black_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	for row in BROWS:
		for col in BCOLS:
			var pos := Vector3(
				-BANNER_W * 0.5 + (col + 0.5) * cell_w,
				banner_y + (0.5 - row) * cell_h,
				0.0
			)
			var xform := Transform3D(Basis.IDENTITY, pos)
			if (row + col) % 2 == 0:
				black_xforms.append(xform)
			else:
				white_xforms.append(xform)
	_add_box_multimesh(parent, "BannerBlack", Vector3(cell_w, cell_h, 0.08), CHECK_BLACK, black_xforms)
	_add_box_multimesh(parent, "BannerWhite", Vector3(cell_w, cell_h, 0.08), CHECK_WHITE, white_xforms)


func _add_box(parent: Node3D, node_name: String, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_box_multimesh(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	color: Color,
	xforms: Array[Transform3D]
) -> void:
	if xforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = size
	box.material = _make_mat(color)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	parent.add_child(mmi)
