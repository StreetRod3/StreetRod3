extends Node3D

## Builds a road course from a `.trk` graph and answers path queries.

const _StreetScenery := preload("res://scripts/street_scenery.gd")
const _CourseScenery := preload("res://scripts/course_scenery.gd")
const _TrackSides := preload("res://scripts/track_sides.gd")
const _GroundMaterial := preload("res://scripts/ground_material.gd")

@export_file("*.trk") var track_path: String = "res://assets/tracks/track1.trk"

const ROAD_HALF_W := 20.0
## Depth of the barrier strip past the driveable edge.
const OBSTACLE_BAND := 0.7
const BAKE_STEP := 2.0
## Grass grid around the road. It sits just under the pavement so the two don't flicker.
const _TERRAIN_PAD := 400.0
const _TERRAIN_STEP := 12.0
const _TERRAIN_SINK := 0.08
## How far under the grass beside the road (`_build_side_grass()`) the grid stays, at the least.
const _UNDER_SIDE_GRASS_M := 0.3
## A street track's rises are short, so its grass needs more points to stay under the road.
const _STREET_TERRAIN_PAD := 300.0
const _STREET_TERRAIN_STEP := 6.0
## Grass points under a street track's road go this much lower still. Between points the grass runs
## straight, so at the bottom of a dip it would otherwise come up through the pavement.
const _STREET_UNDER_ROAD_SINK := 1.0
const _STREET_SHOULDER_W := 0.75
## How far a street track's pavement runs back behind the start, so it doesn't begin under the cars.
const _STREET_RUN_IN_M := 60.0
## Cell size for the nearest-sample lookup used while shaping the grass.
const _BIN_CELL := 64.0
const FILLET_MIN_ANGLE := 0.06 ## ~3.5 degrees; smaller turns stay as a sharp join
const FILLET_LEN_FRACTION := 0.4
const FILLET_MAX_CUT := 80.0
## Straight pavement past the finish. The race still ends on the finish line.
const _RUNOFF_M := 400.0
## The ground beside a mountain or Aqueduct track reaches out this far at most (see `_FAR_M` in
## track_sides.gd), and less where another part of the course is nearer: it stops a little past
## halfway, so the two sides overlap rather than leave cracks where the sections meet at angles.
const _SIDE_REACH_MAX := 300.0
const _SIDE_OVERLAP_M := 8.0
## A plain track's grass stops at least this short of another road's pavement, past halfway.
const _SIDE_OFF_ROAD_M := 0.5
const CURB_W := 0.45
const CURB_H := 0.16
const CURB_L := 2.0
const CURB_RED := Color(0.82, 0.12, 0.12, 1)
const CURB_WHITE := Color(0.92, 0.92, 0.9, 1)
const CHECK_BLACK := Color(0.06, 0.06, 0.07, 1)
const CHECK_WHITE := Color(0.94, 0.94, 0.92, 1)
const POST_COLOR := Color(0.12, 0.12, 0.13, 1)
## The sides of a jump track's ramps, from the road's edge down to the grass.
const _RAMP_SIDE_COLOR := Color(0.42, 0.33, 0.22, 1)
## Road this high or less over the grass has no ramp side.
const _RAMP_SIDE_MIN_M := 0.02
## Which ground `_height_on()` reads: whatever is there, or a plain track's road or grass alone.
const _ANY_GROUND := 0
const _ROAD_ONLY := 1
const _GRASS_ONLY := 2
## The collision layer of a jump track's ramp sides. A car takes it into its mask only while
## `car_off_road()` says so.
const RAMP_SIDE_LAYER := 4
## How far a car's box may still reach over a ramp's edge and the car count as off the road. A car
## on the grass stops with its box against the side, so it has to be more than 0.
const _RAMP_STRADDLE_M := 0.15
## Yellow and black bands across the road up to each lip, so a jump shows from the car.
const _LIP_YELLOW := Color(0.95, 0.76, 0.08, 1)
const _LIP_BAND_LONG := 1.6
const _LIP_BAND_ACROSS := 1.0
## The grass beside a banked road's raised edge falls this much a meter out, back to the road's foot.
const _BANK_EMBANK_SLOPE := 0.5
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
## Pavement behind the start: `_STREET_RUN_IN_M`, or less where it would reach another part of
## the course, as on a course that comes back round to where it began.
var _run_in_m: float = _STREET_RUN_IN_M
var _pos := Vector3.ZERO
var _yaw: float = 0.0
var _seg_half_w: float = ROAD_HALF_W
var _seg_surface: String = "regular"
var _seg_road_type: String = "regular"
var _bins: Dictionary = {}
var _road_mi: MeshInstance3D
var _built: bool = false
## A plain track's grass beside the road, from `_side_reaches()`: how far it reaches out and the
## other road's height, per sample. Empty on other tracks.
var _grass_sides: Array[PackedFloat32Array] = []
var _sign_mesh: ArrayMesh
var _sign_textures: Dictionary = {}
var _street: bool = false
var _style: String = TrackFile.STYLE_CIRCUIT
## The track's sky, an id in skies.gd.
var _sky: String = "day"
## Cars leave the road where it drops away faster than they fall. See `air_time.gd`.
var _jumps: bool = false
## A course that comes back round to its start, raced `_laps` times. The samples go round once and
## end on the start again; there is no pavement behind the start or past the finish.
var _loop: bool = false
var _laps: int = 1
## Where along the path each lip is: a sharp node where the road drops away more steeply than it came up.
var _lips: PackedFloat32Array = PackedFloat32Array()
var _scenery: Array[Dictionary] = []
## Each sample's hillside (up) or drop (down) on the driver's left and right, and whether the right
## has a guard rail. Only Mulholland has these.
var _left_sides: PackedFloat32Array = PackedFloat32Array()
var _right_sides: PackedFloat32Array = PackedFloat32Array()
var _rails: PackedByteArray = PackedByteArray()
## The road's height with its rises and dips averaged out, which ground far from it follows.
var _far_ys: PackedFloat32Array = PackedFloat32Array()
## Each sample's bank: how much the road rises a meter across toward its `lateral` side (the
## driver's left), below 0 falling. The edge at the bottom stays at the road's height. All 0 but
## on a circuit track whose nodes bank it (`_banked`).
var _banks: PackedFloat32Array = PackedFloat32Array()
var _banked: bool = false
## Where each node falls along the path.
var _node_s: PackedFloat32Array = PackedFloat32Array()
## What a rival steers around, from the start: {s, to, low, high}, sorted by s.
var _blocks: Array[Dictionary] = []
var _dynamic_blocks: Array[Dictionary] = []
var _road_rocks: Array[Vector3] = []
## Squared distance from the last grass point to the road's middle, set by `_grass_height`.
var _grass_dist_sq: float = 0.0


func is_road_course() -> bool:
	return _built


func has_jumps() -> bool:
	return _jumps


## The sky the track asks for, an id in skies.gd.
func get_sky() -> String:
	return _sky


func get_length() -> float:
	return _race_length


func get_half_width() -> float:
	if _half_ws.is_empty():
		return ROAD_HALF_W
	return _half_ws[0]


func get_road_mesh_instance() -> MeshInstance3D:
	return _road_mi


## How far to the finish line from `world`. On a loop, to the end of the lap: the race keeps count
## of the laps itself (see `lap_s()`).
func remaining_distance(world: Vector3) -> float:
	return maxf(0.0, _race_length - closest_sample(world)["s"])


func is_loop() -> bool:
	return _loop


## Times round a loop. 1 on any other course.
func get_laps() -> int:
	return _laps if _loop else 1


## Where `world` is along one lap, from 0 at the start to the lap's length. It jumps back to 0 at
## the line, so the race unwraps it to count laps.
func lap_s(world: Vector3) -> float:
	return float(closest_sample(world)["s"])


func sample_at(s: float) -> Dictionary:
	if _pts.is_empty():
		return _empty_sample()
	if _loop and _race_length > 0.0 and (s < 0.0 or s > _race_length):
		s = fposmod(s, _race_length)
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


## Height of the road under `world`, in meters. Beside the road it is the ground's: on a plain
## track the grass's (`_side_grass_height()`), elsewhere the road's own or its style's sides.
func surface_height(world: Vector3) -> float:
	return _height_on(world, _ANY_GROUND)


## The ground at `world` for a car that `car_off_road()` found on the grass (`off_road`) or on the
## road: the car's height, its tilt and its wheels all read it. On a jump track that keeps a car on
## the grass beside a ramp on the grass, rather than on the ramp's top over its side, and one on a
## ramp on the ramp until it is clear of the edge. Elsewhere it is `surface_height()`.
func ground_for(world: Vector3, off_road: bool) -> float:
	if not _jumps or _street or _grass_sides.size() != 4:
		return surface_height(world)
	return _height_on(world, _GRASS_ONLY if off_road else _ROAD_ONLY)


## `surface_height()`, where `ground` can hold a plain track to its road or its grass alone.
func _height_on(world: Vector3, ground: int) -> float:
	if _pts.is_empty():
		return 0.0
	var i := _nearest_index(world)
	var height := _pts[i].y
	var bank := _banks[i] if _banked else 0.0
	var half_w := _half_ws[i]
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
			if _banked:
				bank = lerpf(_banks[j], _banks[j + 1], t)
				half_w = lerpf(_half_ws[j], _half_ws[j + 1], t)
	if not _street and _grass_sides.size() == 4 and _grass_sides[0].size() == _pts.size():
		var lateral := _lateral_at(i, world)
		var ext := _sample_extents(i)
		var off := lateral > ext.y or lateral < -ext.x
		if ground == _GRASS_ONLY or (ground == _ANY_GROUND and off):
			if lateral >= 0.0:
				return _side_grass_height(height, ext.y, _grass_sides[0][i], _grass_sides[2][i], maxf(lateral, ext.y), _lift_for(bank, half_w, ext.y))
			return _side_grass_height(height, ext.x, _grass_sides[1][i], _grass_sides[3][i], maxf(-lateral, ext.x), _lift_for(bank, half_w, -ext.x))
	if _banked:
		height += _lift_for(bank, half_w, _lateral_at(i, world))
	return _side_ground_at(i, world, height)


## The ground's height at `world`, at sample `i`, with `road_y` the road's beside it.
func _side_ground_at(i: int, world: Vector3, road_y: float) -> float:
	if _style == TrackFile.STYLE_AQUEDUCT:
		return road_y + _TrackSides.aqueduct_height(_lateral_at(i, world))
	if _style != TrackFile.STYLE_MOUNTAIN:
		return road_y
	var lateral := _lateral_at(i, world)
	return _TrackSides.mountain_ground(lateral, _half_ws[i], _left_sides[i] if lateral > 0.0 else _right_sides[i], road_y, _far_ys[i])


func _lateral_at(i: int, world: Vector3) -> float:
	return (world - _pts[i]).dot(Vector3(cos(_yaws[i]), 0.0, -sin(_yaws[i])))


## How far a car at `world` leans across the road, by the height either side of it, in radians.
func surface_roll(world: Vector3, yaw: float) -> float:
	if _style != TrackFile.STYLE_AQUEDUCT and _style != TrackFile.STYLE_MOUNTAIN and not _banked:
		return 0.0
	var across := Vector3(cos(yaw), 0.0, -sin(yaw)) * 0.8
	return atan2(surface_height(world + across) - surface_height(world - across), 1.6)


## How steeply the ground rises across a car at `world` heading `yaw`: the rise a meter toward the
## car's +X, on a banked circuit's road or the grass beside it. 0 on any other track, so the
## driving models leave their own flat and sloped ground (the Aqueduct pushes with `bank_push()`).
func bank_slope(world: Vector3, yaw: float) -> float:
	if not _banked:
		return 0.0
	var across := Vector3(cos(yaw), 0.0, -sin(yaw)) * 0.8
	return (surface_height(world + across) - surface_height(world - across)) / 1.6


## What the Aqueduct's banks do to a car at `world`: sideways, toward the floor, in m/s.
func bank_push(world: Vector3) -> Vector3:
	if _style != TrackFile.STYLE_AQUEDUCT or _pts.is_empty():
		return Vector3.ZERO
	var i := _nearest_index(world)
	var across := Vector3(cos(_yaws[i]), 0.0, -sin(_yaws[i]))
	return across * _TrackSides.aqueduct_push(_lateral_at(i, world))


## Whether a car is off a jump track's road, on the grass beside it: its collision box, `half` its
## width (x) and length (y) about its `middle` and turned to `yaw`, lies past the road's edge, all
## but `_RAMP_STRADDLE_M`. So a car going off a ramp's side stays on the ramp until it is clear of
## the side, and drops without landing inside it, and a car on the grass that has driven, or backed,
## up to the side is still on the grass. Only a car off the road runs into the ramp sides, so one
## on a ramp never catches on a side's top. False on every other track.
func car_off_road(middle: Vector3, yaw: float, half: Vector2) -> bool:
	if not _jumps or _street or _pts.is_empty():
		return false
	var i := _nearest_index(middle)
	var lateral := _lateral_at(i, middle)
	var ext := _sample_extents(i)
	var turn := yaw - _yaws[i]
	var across := half.x * absf(cos(turn)) + half.y * absf(sin(turn))
	return lateral - across > ext.y - _RAMP_STRADDLE_M or lateral + across < -ext.x + _RAMP_STRADDLE_M


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


## Something new on the road for rivals to steer round for the rest of the race, such as a fallen
## tree (tree_grove.gd): {"s", "to", "low", "high"}, as course_scenery.gd's blocks.
func add_block(block: Dictionary) -> void:
	_blocks.append(block)
	_blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))


func set_dynamic_blocks(blocks: Array[Dictionary]) -> void:
	_dynamic_blocks = blocks


func clear_dynamic_blocks() -> void:
	_dynamic_blocks.clear()


## The lane a rival should hold at `s`, looking `look` meters ahead, given the one it wants: of the
## gaps left by the next group of things on the road, the spot nearest that lane.
func lane_around(s: float, lane: float, look: float) -> float:
	var lows := PackedFloat32Array()
	var highs := PackedFloat32Array()
	var soft_lows := PackedFloat32Array()
	var soft_highs := PackedFloat32Array()
	var group_end := INF
	var bridge: Dictionary = {}
	var min_s := s - 2.0 if look >= 0.0 else s + look
	var max_s := s + look if look >= 0.0 else s + 2.0
	for block: Dictionary in _blocks:
		var from_s := float(block["s"])
		if look >= 0.0:
			if from_s > max_s or from_s > group_end:
				break
			if float(block["to"]) < min_s:
				continue
		else:
			if from_s > max_s:
				break
			if float(block["to"]) < min_s:
				continue
		# Lining up for a bridge comes after whatever is in the way before it.
		if block.has("bridge"):
			bridge = block
			continue
		if is_inf(group_end) and look >= 0.0:
			group_end = float(block["to"]) + _BLOCK_GROUP_M
		var low := float(block["low"]) - _RIVAL_CLEARANCE_M
		var high := float(block["high"]) + _RIVAL_CLEARANCE_M
		if block.has("soft"):
			soft_lows.append(low)
			soft_highs.append(high)
		else:
			lows.append(low)
			highs.append(high)
	for block: Dictionary in _dynamic_blocks:
		if float(block.get("to", 0.0)) < min_s or float(block.get("s", 0.0)) > max_s:
			continue
		var low := float(block.get("low", 0.0)) - _RIVAL_CLEARANCE_M
		var high := float(block.get("high", 0.0)) + _RIVAL_CLEARANCE_M
		if block.has("soft"):
			soft_lows.append(low)
			soft_highs.append(high)
		else:
			lows.append(low)
			highs.append(high)
	var room := INF
	var no_more := lows.is_empty() and soft_lows.is_empty()
	if not bridge.is_empty():
		var bridge_active := (s >= float(bridge["s"])) if look >= 0.0 else (s <= float(bridge.get("to", bridge["s"])))
		if no_more or bridge_active:
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
	var back_dir := -Vector3(sin(_yaws[0]), 0.0, cos(_yaws[0]))
	_run_in_m = 0.0 if _loop else _clear_run(_pts[0], back_dir, _STREET_RUN_IN_M, 0.0, -1.0, _half_ws[0])
	if _style == TrackFile.STYLE_AQUEDUCT or _style == TrackFile.STYLE_MOUNTAIN:
		var reaches := _side_reaches()
		var back_reach := _reach_at(_pts[0] + back_dir * _run_in_m, _yaws[0], -_run_in_m)
		if _style == TrackFile.STYLE_AQUEDUCT:
			_TrackSides.build_aqueduct(self, _pts, _yaws, _run_in_m, reaches, back_reach)
		else:
			_TrackSides.build_mountain(self, _pts, _yaws, _half_ws, _road_types, _left_sides, _right_sides, _rails, _far_ys, _run_in_m, reaches, back_reach)
			_build_road_mesh()
	else:
		_build_terrain()
		if not _street:
			_build_side_grass()
		_build_road_mesh()
		if _jumps:
			_build_ramp_sides()
			_build_lip_bands()
	if _style == TrackFile.STYLE_AQUEDUCT or _style == TrackFile.STYLE_MOUNTAIN:
		_StreetScenery.build(self, _scenery, _half_ws[0] * 2.0)
		var found: Dictionary = _CourseScenery.build(self, _scenery)
		_blocks.assign(found["blocks"])
		_road_rocks.assign(found["rocks"])
		_add_bridge_blocks()
	elif _street:
		_StreetScenery.build(self, _scenery, get_half_width() * 2.0)
	else:
		# Curbs would stand up off the ramps' lips.
		if not _jumps:
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
	var bank := 0.0
	if index >= 0 and index < _half_ws.size():
		hw = _half_ws[index]
		surface = _surfaces[index]
		rtype = _road_types[index]
	if index >= 0 and index < _banks.size():
		bank = _banks[index]
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
		"bank": bank,
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
	_sky = data.sky
	_jumps = bool(data.jumps)
	_loop = bool(data.loop)
	_laps = int(data.laps)
	_street = _style != TrackFile.STYLE_CIRCUIT
	_scenery.assign(data.scenery)
	var path_ids: Array = data.path_ids
	if path_ids.size() < 2:
		push_error("[track] Race path is too short.")
		return
	var n := path_ids.size()
	var pts: Array[Vector3] = []
	var sharp := PackedByteArray()
	var bank_degs := PackedFloat32Array()
	var roads: Array[Dictionary] = []
	for i in n:
		var node: Dictionary = data.nodes[int(path_ids[i])]
		pts.append(TrackFile.world_position(node))
		sharp.append(1 if bool(node.get("sharp", false)) else 0)
		bank_degs.append(float(node.get("bank", 0.0)))
	for i in range(n - 1):
		roads.append(TrackFile.find_road(data, int(path_ids[i]), int(path_ids[i + 1])))
	# Heights follow the nodes themselves, not the corner a loop adds below.
	var nodes: Array[Vector3] = pts.duplicate()
	# A loop comes back into its start already on the start straight: when the start node is a
	# corner, the last road turns onto the straight round a corner set back behind the line, so
	# the lap ends where it began, heading the same way, and the car still starts on the straight.
	var set_back_cut := 0.0
	var set_back := false
	if _loop and n >= 4:
		set_back_cut = _fillet_cut(pts[n - 2], pts[0], pts[1])
		if set_back_cut >= 0.05:
			var out_dir := Vector3(pts[1].x - pts[0].x, 0.0, pts[1].z - pts[0].z).normalized()
			pts.insert(n - 1, pts[0] - out_dir * set_back_cut)
			# The corner is the start's, so it banks as the start does.
			bank_degs.insert(n - 1, bank_degs[n - 1])
			roads.append(roads[n - 2])
			n += 1
			set_back = true
	var cuts: PackedFloat32Array = PackedFloat32Array()
	cuts.resize(n)
	for i in range(1, n - 1):
		cuts[i] = _fillet_cut(pts[i - 1], pts[i], pts[i + 1])
	if set_back:
		# The set-back corner's curve runs all the way to the start.
		var in_span := Vector3(pts[n - 2].x - pts[n - 3].x, 0.0, pts[n - 2].z - pts[n - 3].z).length()
		cuts[n - 2] = minf(set_back_cut, in_span * FILLET_LEN_FRACTION)
	_apply_road(roads[0])
	_pos = pts[0]
	_yaw = atan2(pts[1].x - pts[0].x, pts[1].z - pts[0].z)
	_push_sample()
	# Where each point's corner begins and ends along the path; a point with no corner is both.
	var curve_from := PackedFloat32Array([0.0])
	var curve_to := PackedFloat32Array([0.0])
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
			curve_from.append(_length)
			curve_to.append(_length)
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
		curve_from.append(_length)
		_append_bezier(p0, pts[i], p2, roads[i - 1], roads[i])
		curve_to.append(_length)
	_apply_road(roads[n - 2])
	_append_to(pts[n - 1])
	curve_from.append(_length)
	curve_to.append(_length)
	if _loop:
		# Exactly where the lap began, heading the same way.
		_pts[_pts.size() - 1] = _pts[0]
		_yaws[_yaws.size() - 1] = _yaws[0]
	_smooth_path_heights(nodes, sharp)
	_race_length = _length
	if not _loop:
		_append_runoff()
	_fill_banks(curve_from, curve_to, bank_degs)
	_fill_sides(data, path_ids)
	_build_bins()


## Each sample's bank from its nodes'. A node's bank holds all round its corner, from where the
## curve begins to where it ends, and eases to the next node's over the straight between, so a
## car turns in on a road already banked. Past the finish it holds. Only a circuit track banks.
func _fill_banks(curve_from: PackedFloat32Array, curve_to: PackedFloat32Array, degs: PackedFloat32Array) -> void:
	_banks.resize(_pts.size())
	_banks.fill(0.0)
	_banked = false
	if _style != TrackFile.STYLE_CIRCUIT:
		return
	for deg: float in degs:
		if not is_zero_approx(deg):
			_banked = true
	if not _banked:
		return
	var last := mini(degs.size(), curve_from.size()) - 1
	var k := 0
	for i in _pts.size():
		var s := _dists[i]
		while k < last and curve_from[k + 1] <= s:
			k += 1
		var deg := degs[k]
		if s > curve_to[k] and k < last:
			var t := smoothstep(curve_to[k], curve_from[k + 1], s)
			deg = lerpf(degs[k], degs[k + 1], t)
		_banks[i] = tan(deg_to_rad(deg))


## How far the road at sample `i` stands over its middle's height, `lateral` meters from the middle
## (above 0 toward the driver's left). The low edge of a banked road is at the road's height.
func _bank_lift(i: int, lateral: float) -> float:
	if not _banked or i < 0 or i >= _banks.size():
		return 0.0
	return _lift_for(_banks[i], _half_ws[i], lateral)


static func _lift_for(bank: float, half_w: float, lateral: float) -> float:
	return lateral * bank + half_w * absf(bank)


## The point on the road at sample `i`, `lateral` meters across from its middle.
func _road_point(i: int, lateral: float) -> Vector3:
	var right := Vector3(cos(_yaws[i]), 0.0, -sin(_yaws[i]))
	return _pts[i] + right * lateral + Vector3.UP * _bank_lift(i, lateral)


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
	_far_ys = _TrackSides.slow_heights(_pts, _loop)
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
## At a `sharp` node the grade changes at once: the road comes in and goes out at the straight grades
## to its neighbours, so two sharp nodes together make a straight ramp, and its top a lip.
func _smooth_path_heights(nodes: Array[Vector3], sharp: PackedByteArray) -> void:
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
	var slopes_in := _height_slopes(knot_s, knot_y)
	var slopes_out := slopes_in.duplicate()
	for i in mini(sharp.size(), knot_s.size()):
		if sharp[i] == 0:
			continue
		if i > 0:
			slopes_in[i] = (knot_y[i] - knot_y[i - 1]) / (knot_s[i] - knot_s[i - 1])
		if i + 1 < knot_s.size():
			slopes_out[i] = (knot_y[i + 1] - knot_y[i]) / (knot_s[i + 1] - knot_s[i])
		if slopes_out[i] < slopes_in[i] - 0.01:
			_lips.append(knot_s[i])
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
			y = _hermite_height(knot_y[k], slopes_out[k], knot_y[k1], slopes_in[k1], span, t)
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
	var runoff := _clear_run(_pos, ahead, _RUNOFF_M, _race_length, 1.0, _seg_half_w)
	if runoff < 1.0:
		return
	var dest := _pos + ahead * runoff
	dest.y = _pos.y
	_append_to(dest)


## How far straight road can run from `from` along `dir`, up to `length`, before it comes onto
## another part of the course. `origin_s` is where `from` is along the course and `direction` which way
## the run goes along it (+1 past the finish, -1 behind the start). Road counts as another part
## when it is much farther round the course than straight across, so the road just behind a
## run doesn't stop it.
func _clear_run(from: Vector3, dir: Vector3, length: float, origin_s: float, direction: float, half_w: float) -> float:
	var t := 0.0
	while t <= length:
		var p := from + dir * t
		var along := origin_s + direction * t
		for q in range(0, _pts.size(), 2):
			var dx := p.x - _pts[q].x
			var dz := p.z - _pts[q].z
			var touch := _half_ws[q] + half_w + 2.0
			var d2 := dx * dx + dz * dz
			if d2 > touch * touch:
				continue
			if _along_gap(_dists[q], along) > 1.2 * sqrt(d2) + 10.0:
				return maxf(t - 5.0, 0.0)
		t += BAKE_STEP
	return length


## How far apart two places are along the course; on a loop, the shorter way round.
func _along_gap(a: float, b: float) -> float:
	var gap := absf(a - b)
	if _loop and _race_length > 0.0:
		gap = minf(gap, absf(_race_length - gap))
	return gap


## How far the ground may reach out on the left (0) and right (1) of each sample, and the height of
## the road whose part of the course stops it there on the left (2) and right (3): the sample's own
## height where none does.
func _side_reaches(off_road: bool = false) -> Array[PackedFloat32Array]:
	var n := _pts.size()
	var out: Array[PackedFloat32Array] = []
	for k in 4:
		var list := PackedFloat32Array()
		list.resize(n)
		out.append(list)
	var i := 0
	while i < n:
		var both := _reach_and_far_y_at(_pts[i], _yaws[i], _dists[i], off_road)
		for j: int in [i, i + 1]:
			if j < n:
				out[0][j] = both.x
				out[1][j] = both.y
				out[2][j] = both.z
				out[3][j] = both.w
		i = i + 2 if i + 2 < n or i == n - 1 else n - 1
	return out


## How far the ground beside the road at `center`, `s` along the course, may reach out on the left
## (x) and right (y): to just past halfway to the nearest other part of the course straight out
## that side, or `_SIDE_REACH_MAX`. Every fourth sample is enough to find the other parts.
## Heights make the road a little longer than the ground it crosses, hence the 2% and 2 m.
func _reach_at(center: Vector3, yaw: float, s: float) -> Vector2:
	var both := _reach_and_far_y_at(center, yaw, s)
	return Vector2(both.x, both.y)


## `_reach_at()` in x and y, and in z and w the height of the road that stops the ground on the
## left and right, or `center`'s own where nothing does. With `off_road`, the overlap past halfway
## never reaches the other road's pavement, which on a tight bend it can.
func _reach_and_far_y_at(center: Vector3, yaw: float, s: float, off_road: bool = false) -> Vector4:
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var left := _SIDE_REACH_MAX
	var right := _SIDE_REACH_MAX
	var left_y := center.y
	var right_y := center.y
	var left_max := INF
	var right_max := INF
	var far_sq := 4.0 * _SIDE_REACH_MAX * _SIDE_REACH_MAX
	for q in range(0, _pts.size(), 4):
		var dx := _pts[q].x - center.x
		var dz := _pts[q].z - center.z
		var d2 := dx * dx + dz * dz
		if d2 > far_sq:
			continue
		var out := dx * across.x + dz * across.z
		# Only road that runs nearly straight from here is this stretch. Anything farther round,
		# even the far side of a bend, stops the ground: on the inside of a bend that is at the
		# bend's middle, where the ground would otherwise start to fold over itself. Past a sharp
		# corner, though, the road straight on from it runs off to the side, under the ground, so
		# with `off_road` only road straight ahead or behind is this stretch.
		if _along_gap(_dists[q], s) <= 1.02 * sqrt(d2) + 2.0:
			if not off_road or absf(out) <= _half_ws[q] + _SIDE_OFF_ROAD_M:
				continue
		# Where the line between the two is crossed, straight out this side, is halfway; the other
		# road's edge is twice that, less its half width.
		var keep_off := 2.0 * d2 / (2.0 * absf(out)) - _half_ws[q] - _SIDE_OFF_ROAD_M if absf(out) > 0.001 else INF
		if out > 0.001:
			left_max = minf(left_max, keep_off)
			if d2 / (2.0 * out) < left:
				left = d2 / (2.0 * out)
				left_y = _pts[q].y
		elif out < -0.001:
			right_max = minf(right_max, keep_off)
			if d2 / (-2.0 * out) < right:
				right = d2 / (-2.0 * out)
				right_y = _pts[q].y
	left += _SIDE_OVERLAP_M
	right += _SIDE_OVERLAP_M
	if off_road:
		left = maxf(minf(left, left_max), left - _SIDE_OVERLAP_M)
		right = maxf(minf(right, right_max), right - _SIDE_OVERLAP_M)
	return Vector4(left, right, left_y, right_y)


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
	var stride := cols + 1
	var heights := PackedFloat32Array()
	heights.resize(stride * (rows + 1))
	for row in rows + 1:
		var z := origin_z + span_z * float(row) / float(rows)
		for col in cols + 1:
			var x := origin_x + span_x * float(col) / float(cols)
			var y := _grass_height(x, z) - _TERRAIN_SINK
			# The grass stays flat under a jump track's ramps; between its points it would come up
			# through the road past a lip.
			if _jumps:
				y = minf(y, -_TERRAIN_SINK)
			if _street and _grass_dist_sq <= _half_ws[0] * _half_ws[0]:
				y -= _STREET_UNDER_ROAD_SINK
			heights[row * stride + col] = y
	if not _street:
		heights = _under_side_grass(heights, cols, rows)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rows + 1:
		var z := origin_z + span_z * float(row) / float(rows)
		for col in cols + 1:
			var x := origin_x + span_x * float(col) / float(cols)
			st.add_vertex(Vector3(x, heights[row * stride + col], z))
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
	mesh.surface_set_material(0, _GroundMaterial.grass())
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)


## The grid's heights lowered to the lowest of each point and its eight neighbors, and
## `_UNDER_SIDE_GRASS_M` more. Between its points the grid runs straight for 12 m, so where the
## road climbs, dips or passes another part of the course at another height, it came up through
## the road; now it stays under the grass beside the road (`_build_side_grass()`), which hides it,
## and shows only past that.
func _under_side_grass(heights: PackedFloat32Array, cols: int, rows: int) -> PackedFloat32Array:
	var stride := cols + 1
	var out := PackedFloat32Array()
	out.resize(heights.size())
	for row in rows + 1:
		for col in cols + 1:
			var low := heights[row * stride + col]
			for dr in range(maxi(row - 1, 0), mini(row + 1, rows) + 1):
				for dc in range(maxi(col - 1, 0), mini(col + 1, cols) + 1):
					low = minf(low, heights[dr * stride + dc])
			out[row * stride + col] = low - _UNDER_SIDE_GRASS_M
	return out


## Grass beside the road of a plain track, at the height `surface_height()` holds a car to there
## (`_side_grass_height()`). It reaches out as the mountain's ground does (`_side_reaches()`), so the
## grid under it shows only far off. Behind the start, where there is no pavement, it runs across
## the road's line too.
func _build_side_grass() -> void:
	_grass_sides = _side_reaches(true)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [1.0, -1.0]:
		var k := 0 if side > 0.0 else 1
		var reach := _grass_sides[k].duplicate()
		var caps := _inside_reach_caps(side)
		for i in reach.size():
			reach[i] = minf(reach[i], caps[i])
		var far_y := _grass_sides[k + 2]
		for i in range(_pts.size() - 1):
			var e0 := _sample_extents(i)
			var e1 := _sample_extents(i + 1)
			var edge0 := e0.y if side > 0.0 else e0.x
			var edge1 := e1.y if side > 0.0 else e1.x
			_add_side_grass_span(
				st, side,
				_pts[i], _yaws[i], edge0, reach[i], far_y[i],
				_pts[i + 1], _yaws[i + 1], edge1, reach[i + 1], far_y[i + 1],
				_bank_lift(i, side * edge0), _bank_lift(i + 1, side * edge1)
			)
		if _run_in_m > 0.0:
			var back := _pts[0] - Vector3(sin(_yaws[0]), 0.0, cos(_yaws[0])) * _run_in_m
			back.y = _pts[0].y
			var back_reach := _reach_and_far_y_at(back, _yaws[0], -_run_in_m, true)
			_add_side_grass_span(
				st, side,
				back, _yaws[0], 0.0, back_reach.x if side > 0.0 else back_reach.y, back_reach.z if side > 0.0 else back_reach.w,
				_pts[0], _yaws[0], 0.0, reach[0], far_y[0]
			)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _GroundMaterial.grass())
	var mi := MeshInstance3D.new()
	mi.name = "SideGrass"
	mi.mesh = mesh
	# It lies a little over the ground grid, and its shadow fell on the grid wherever the grid
	# shows between strips, as a dark patch with nothing standing there to cast it.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## How far out from the middle of the road the side grass on `side` (1 right, -1 left) may reach
## at each sample. On the inside of a corner, strips reaching past the corner's middle cross those of
## the next samples: the crossed triangles face down and darken the grass round them, and lying
## on the grass they flicker against it. So there each stays at 80% of where it would cross its
## neighbor's, and the ground grid under it shows on beyond. INF where nothing limits it.
func _inside_reach_caps(side: float) -> PackedFloat32Array:
	var n := _pts.size()
	var caps := PackedFloat32Array()
	caps.resize(n)
	caps.fill(INF)
	for i in n - 1:
		var r0 := Vector3(cos(_yaws[i]), 0.0, -sin(_yaws[i])) * side
		var r1 := Vector3(cos(_yaws[i + 1]), 0.0, -sin(_yaws[i + 1])) * side
		var mid_yaw := _yaws[i] + angle_difference(_yaws[i], _yaws[i + 1]) * 0.5
		var fwd := Vector3(sin(mid_yaw), 0.0, cos(mid_yaw))
		var along := Vector3(_pts[i + 1].x - _pts[i].x, 0.0, _pts[i + 1].z - _pts[i].z).dot(fwd)
		# How fast the two samples' sideways lines close on each other, per meter out.
		var closing := -(r1 - r0).dot(fwd)
		if closing <= 0.0001 or along <= 0.0:
			continue
		var cap := 0.8 * along / closing
		caps[i] = minf(caps[i], cap)
		caps[i + 1] = minf(caps[i + 1], cap)
	return caps


## One stretch of `_build_side_grass()`, on the left (`side` 1) or right (-1): from the road's
## `edge` to the halfway line, where the slope ends, and on out to `reach`, all in meters from the
## middle of the road.
func _add_side_grass_span(
	st: SurfaceTool,
	side: float,
	p0: Vector3, yaw0: float, edge0: float, reach0: float, far_y0: float,
	p1: Vector3, yaw1: float, edge1: float, reach1: float, far_y1: float,
	lift0: float = 0.0, lift1: float = 0.0
) -> void:
	var r0 := Vector3(cos(yaw0), 0.0, -sin(yaw0)) * side
	var r1 := Vector3(cos(yaw1), 0.0, -sin(yaw1)) * side
	var outs0: Array[float] = [edge0, maxf(reach0 - _SIDE_OVERLAP_M, edge0), maxf(reach0, edge0)]
	var outs1: Array[float] = [edge1, maxf(reach1 - _SIDE_OVERLAP_M, edge1), maxf(reach1, edge1)]
	if _banked:
		# Where the bank's grass comes back down to the ground. Both ends need it, so a stretch
		# with no lift at one end has a narrow strip there.
		outs0.insert(1, minf(edge0 + maxf(_embank_run(lift0, edge0, outs0[1]), 0.05), outs0[1]))
		outs1.insert(1, minf(edge1 + maxf(_embank_run(lift1, edge1, outs1[1]), 0.05), outs1[1]))
	for k in outs0.size() - 1:
		var pts0: Array[Vector3] = []
		var pts1: Array[Vector3] = []
		for out: float in [outs0[k], outs0[k + 1]]:
			var y := _side_grass_height(p0.y, edge0, reach0, far_y0, out, lift0) - _TERRAIN_SINK
			pts0.append(Vector3(p0.x, y, p0.z) + r0 * out)
		for out: float in [outs1[k], outs1[k + 1]]:
			var y := _side_grass_height(p1.y, edge1, reach1, far_y1, out, lift1) - _TERRAIN_SINK
			pts1.append(Vector3(p1.x, y, p1.z) + r1 * out)
		# The road mesh's order, the point on the driver's right first, so the grass faces up.
		var a0 := pts0[0] if side > 0.0 else pts0[1]
		var b0 := pts0[1] if side > 0.0 else pts0[0]
		var a1 := pts1[0] if side > 0.0 else pts1[1]
		var b1 := pts1[1] if side > 0.0 else pts1[0]
		_add_tri(st, a0, b0, b1, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
		_add_tri(st, a0, b1, a1, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))


## Height of the ground beside a plain track's road at `road_y`, `out` meters from the middle, with
## the road's edge at `edge`, and on that side the ground reaching `reach` and the road that stops
## it there at `far_y`. Flat at the road's height where nothing is near; otherwise it slopes to
## halfway between the two roads' heights at the halfway line, where the grass from the other road
## meets it at the same height, and stays there over the overlap. A jump track's ramps don't lift it.
## Beside a banked road's raised edge, `lift` over `road_y`, the grass starts at the edge and falls
## at `_BANK_EMBANK_SLOPE`, and by the halfway line at the latest, to where it would lie. On a jump
## track it doesn't: there the ramp's side comes down to it.
func _side_grass_height(road_y: float, edge: float, reach: float, far_y: float, out: float, lift: float = 0.0) -> float:
	var base := minf(road_y, 0.0) if _jumps else road_y
	var meet := (base + (minf(far_y, 0.0) if _jumps else far_y)) * 0.5
	var half := maxf(reach - _SIDE_OVERLAP_M, edge)
	var bank_up := 0.0
	var run := _embank_run(lift, edge, half)
	if run > 0.0:
		bank_up = lift * clampf(1.0 - (out - edge) / run, 0.0, 1.0)
	if out >= half:
		return meet + bank_up
	if out <= edge:
		return base + bank_up
	return lerpf(base, meet, (out - edge) / (half - edge)) + bank_up


## How far out from a banked road's raised edge, `lift` up, its grass comes back down, with the
## halfway line at `half`. 0 where there is no slope: no lift, or a jump track.
func _embank_run(lift: float, edge: float, half: float) -> float:
	if lift <= 0.0 or _jumps:
		return 0.0
	return minf(lift / _BANK_EMBANK_SLOPE, maxf(half - edge, 0.5))


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
		var l0 := _pts[i] - r0 * e0.x + Vector3.UP * _bank_lift(i, -e0.x)
		var rr0 := _pts[i] + r0 * e0.y + Vector3.UP * _bank_lift(i, e0.y)
		var l1 := _pts[i + 1] - r1 * e1.x + Vector3.UP * _bank_lift(i + 1, -e1.x)
		var rr1 := _pts[i + 1] + r1 * e1.y + Vector3.UP * _bank_lift(i + 1, e1.y)
		var v := _dists[i] * 0.15
		var v1 := _dists[i + 1] * 0.15
		_add_tri(st, l0, rr0, rr1, Vector2(0, v), Vector2(1, v), Vector2(1, v1))
		_add_tri(st, l0, rr1, l1, Vector2(0, v), Vector2(1, v1), Vector2(0, v1))
	st.generate_normals()
	var mesh := st.commit()
	var mat := _GroundMaterial.dark_asphalt() if _style == TrackFile.STYLE_MOUNTAIN else _GroundMaterial.asphalt()
	mesh.surface_set_material(0, mat)
	_road_mi = MeshInstance3D.new()
	_road_mi.name = "RoadMesh"
	_road_mi.mesh = mesh
	add_child(_road_mi)
	if _style == TrackFile.STYLE_STREET:
		_build_street_shoulders()
	elif _style == TrackFile.STYLE_MOUNTAIN:
		_build_gravel()


## A jump track's ramps are solid blocks: a wall down each side from the road's edge to the grass.
func _build_ramp_sides() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foot := -_TERRAIN_SINK
	var walls := 0
	for i in range(_pts.size() - 1):
		var e0 := _sample_extents(i)
		var e1 := _sample_extents(i + 1)
		var r0 := Vector3(cos(_yaws[i]), 0.0, -sin(_yaws[i]))
		var r1 := Vector3(cos(_yaws[i + 1]), 0.0, -sin(_yaws[i + 1]))
		for side: float in [-1.0, 1.0]:
			# A banked road's raised edge has a side even where the road is at the grass.
			var top0 := _road_point(i, side * (e0.y if side > 0.0 else e0.x))
			var top1 := _road_point(i + 1, side * (e1.y if side > 0.0 else e1.x))
			if top0.y <= _RAMP_SIDE_MIN_M and top1.y <= _RAMP_SIDE_MIN_M:
				continue
			walls += 1
			var foot0 := Vector3(top0.x, foot, top0.z)
			var foot1 := Vector3(top1.x, foot, top1.z)
			var out := (r0 + r1).normalized() * side
			_add_wall_tri(st, top0, foot0, top1, out)
			_add_wall_tri(st, top1, foot0, foot1, out)
	if walls == 0:
		return
	var mesh := st.commit()
	mesh.surface_set_material(0, _make_mat(_RAMP_SIDE_COLOR, 0.9))
	var mi := MeshInstance3D.new()
	mi.name = "RampSides"
	mi.mesh = mesh
	add_child(mi)
	# A car on the grass beside a ramp is held to the grass, so the side stops it, as a barrier
	# does, rather than lifting it onto the ramp. Only a car off the road collides with it (see
	# `car_off_road()`): on a steep ramp a car's box comes down to the road and would catch on
	# the side's top. Cars ride 0.1 m up, so a side lower than that lets them up. The side faces
	# out only, so a car that drops off a ramp with its box a little inside it is pushed out onto
	# the grass rather than held.
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = false
	shape.set_faces(mesh.get_faces())
	var hit := CollisionShape3D.new()
	hit.shape = shape
	var body := StaticBody3D.new()
	body.name = "RampSideWalls"
	body.collision_layer = 1 << (RAMP_SIDE_LAYER - 1)
	body.collision_mask = 0
	body.set_meta(&"track_obstacle", true)
	body.add_child(hit)
	add_child(body)


func _build_lip_bands() -> void:
	var yellow_xforms: Array[Transform3D] = []
	var black_xforms: Array[Transform3D] = []
	for lip_s: float in _lips:
		var top := sample_at(lip_s)
		var foot := sample_at(lip_s - _LIP_BAND_LONG)
		var top_p: Vector3 = top["position"]
		var foot_p: Vector3 = foot["position"]
		var yaw: float = top["yaw"]
		var grade := atan2(top_p.y - foot_p.y, Vector2(top_p.x - foot_p.x, top_p.z - foot_p.z).length())
		var lip_i := _index_at_distance(lip_s)
		var bank := _banks[lip_i] if _banked else 0.0
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, atan(bank)) * Basis(Vector3.RIGHT, -grade)
		var middle := (top_p + foot_p) * 0.5 + Vector3.UP * 0.02
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var ext := _sample_extents(lip_i)
		var count := int(floor((ext.x + ext.y) / _LIP_BAND_ACROSS))
		var from := -ext.x + ((ext.x + ext.y) - count * _LIP_BAND_ACROSS) * 0.5
		for k in count:
			var across := from + (float(k) + 0.5) * _LIP_BAND_ACROSS
			var xform := Transform3D(basis, middle + right * across + Vector3.UP * _bank_lift(lip_i, across))
			if k % 2 == 0:
				yellow_xforms.append(xform)
			else:
				black_xforms.append(xform)
	var size := Vector3(_LIP_BAND_ACROSS, 0.03, _LIP_BAND_LONG)
	_add_box_multimesh(self, "LipYellow", size, _LIP_YELLOW, yellow_xforms)
	_add_box_multimesh(self, "LipBlack", size, CHECK_BLACK, black_xforms)


## One triangle of a wall facing `out`, wound so that side is its front.
func _add_wall_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		var swap := b
		b = c
		c = swap
	for v: Vector3 in [a, b, c]:
		st.set_normal(out)
		st.add_vertex(v)


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
	mesh.surface_set_material(0, _GroundMaterial.gravel())
	var mi := MeshInstance3D.new()
	mi.name = "Gravel"
	mi.mesh = mesh
	add_child(mi)


## A gravel strip down each side of the road, over the run-in too.
func _build_street_shoulders() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yaw: float = _yaws[0]
	var run_in := _pts[0] - Vector3(sin(yaw), 0.0, cos(yaw)) * _run_in_m
	_add_shoulder_span(st, run_in, yaw, _half_ws[0], _pts[0], yaw, _half_ws[0])
	for i in range(_pts.size() - 1):
		_add_shoulder_span(st, _pts[i], _yaws[i], _half_ws[i], _pts[i + 1], _yaws[i + 1], _half_ws[i + 1])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _GroundMaterial.shoulder_concrete())
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
	var back := _pts[0] - Vector3(sin(yaw), 0.0, cos(yaw)) * _run_in_m
	var v := -_run_in_m * 0.15
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


## Red and white curb stones along both road edges. Each edge is one strip of stones that meet end
## to end: boxes at every sample overlapped on curves, where samples come closer than a stone's
## length, and the overlapping red and white tops flickered. Where the road's width steps, a row of
## stones runs across the step and each edge strip breaks there.
func _build_curbs() -> void:
	var red_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	var stone_i := 0
	for j in range(1, _pts.size()):
		var prev := _sample_extents(j - 1)
		var cur := _sample_extents(j)
		if absf(prev.x - cur.x) > 0.35:
			stone_i = _add_perp_curbs(red_xforms, white_xforms, stone_i, j, false, prev.x, cur.x)
		if absf(prev.y - cur.y) > 0.35:
			stone_i = _add_perp_curbs(red_xforms, white_xforms, stone_i, j, true, prev.y, cur.y)
	_add_box_multimesh(self, "CurbRed", Vector3(CURB_W, CURB_H, CURB_L), CURB_RED, red_xforms)
	_add_box_multimesh(self, "CurbWhite", Vector3(CURB_W, CURB_H, CURB_L), CURB_WHITE, white_xforms)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stones := 0
	for side: float in [-1.0, 1.0]:
		var start := 0
		for j in range(1, _pts.size() + 1):
			if j < _pts.size() and absf(_edge_extent(j - 1, side) - _edge_extent(j, side)) <= 0.35:
				continue
			var closed := _loop and start == 0 and j == _pts.size()
			# Opposite colors face each other across the road, as the stones always have.
			stones += _add_curb_run(st, side, start, j - 1, closed, 0 if side < 0.0 else 1)
			start = j
	if stones == 0:
		return
	var mat := _make_mat(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Curbs"
	mi.mesh = mesh
	add_child(mi)


## How far out the road edge on `side` (-1 left, 1 right) is at sample `i`.
func _edge_extent(i: int, side: float) -> float:
	var ext := _sample_extents(i)
	return ext.y if side > 0.0 else ext.x


## One strip of curb stones along the edge on `side` from sample `a` to `b`, the stones as near
## CURB_L long as fit evenly; `closed` runs round a whole loop, with an even count so the colors
## alternate across the line too. On the inside of a corner tighter than the road is wide the edge
## doubles back on itself; those points are left out. Returns the stones added.
func _add_curb_run(st: SurfaceTool, side: float, a: int, b: int, closed: bool, color_from: int) -> int:
	var edge := PackedVector3Array()
	for i in range(a, b + 1):
		var yaw: float = _yaws[i]
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var p := _pts[i] + right * side * _edge_extent(i, side)
		p.y += _bank_lift(i, side * _edge_extent(i, side))
		if not edge.is_empty():
			var step := p - edge[edge.size() - 1]
			if step.dot(Vector3(sin(yaw), 0.0, cos(yaw))) < 0.01:
				continue
		edge.append(p)
	if closed and edge.size() > 2:
		edge[edge.size() - 1] = edge[0]
	if edge.size() < 2:
		return 0
	var cum := PackedFloat32Array([0.0])
	for i in range(1, edge.size()):
		cum.append(cum[i - 1] + edge[i].distance_to(edge[i - 1]))
	var total := cum[cum.size() - 1]
	if total < 0.3:
		return 0
	var count := maxi(1, roundi(total / CURB_L))
	if closed and count % 2 == 1:
		count += 1
	var ends := PackedVector3Array()
	var seg := 0
	for k in count + 1:
		var s := total * float(k) / float(count)
		while seg < cum.size() - 2 and cum[seg + 1] < s:
			seg += 1
		var span := cum[seg + 1] - cum[seg]
		var t := clampf((s - cum[seg]) / span, 0.0, 1.0) if span > 0.0001 else 0.0
		ends.append(edge[seg].lerp(edge[seg + 1], t))
	if closed:
		ends[count] = ends[0]
	# Across each stone end, square to the edge there, so neighbors share their end face.
	var across := PackedVector3Array()
	for k in count + 1:
		var before := ends[k - 1] if k > 0 else (ends[count - 1] if closed else ends[0])
		var after := ends[k + 1] if k < count else (ends[1] if closed else ends[count])
		var dir := after - before
		dir.y = 0.0
		across.append(Vector3(dir.z, 0.0, -dir.x).normalized() * (CURB_W * 0.5))
	var up := Vector3(0.0, CURB_H, 0.0)
	for k in count:
		var color := CURB_RED if (color_from + k) % 2 == 0 else CURB_WHITE
		var l0 := ends[k] - across[k]
		var r0 := ends[k] + across[k]
		var l1 := ends[k + 1] - across[k + 1]
		var r1 := ends[k + 1] + across[k + 1]
		var along := ends[k + 1] - ends[k]
		var right := Vector3(along.z, 0.0, -along.x).normalized()
		_curb_quad(st, l0 + up, r0 + up, r1 + up, l1 + up, Vector3.UP, color)
		_curb_quad(st, r0, r1, r1 + up, r0 + up, right, color)
		_curb_quad(st, l0, l1, l1 + up, l0 + up, -right, color)
		if not closed and k == 0:
			_curb_quad(st, l0, r0, r0 + up, l0 + up, -along.normalized(), color)
		if not closed and k == count - 1:
			_curb_quad(st, l1, r1, r1 + up, l1 + up, along.normalized(), color)
	return count


## A flat four-cornered face, turned to face `normal`.
func _curb_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var tris: Array[PackedVector3Array] = [PackedVector3Array([a, b, c]), PackedVector3Array([a, c, d])]
	for tri in tris:
		# Godot's front faces wind clockwise seen from the front.
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(normal) > 0.0:
			var swap := tri[1]
			tri[1] = tri[2]
			tri[2] = swap
		for v in tri:
			st.set_color(color)
			st.set_normal(normal)
			st.add_vertex(v)


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
		_add_curb_stone(red_xforms, white_xforms, stone_i, basis, _road_point(index, side * lat))
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
				body, body_xforms, stripe_xforms, _pts[i] + Vector3.UP * _bank_lift(i, -(ext.x + BARRIER_W * 0.5)), basis, -right,
				ext.x, BARRIER_L, BARRIER_H, BARRIER_W
			)
		if TrackFile.obstacle_right(rtype):
			_place_edge_barrier(
				body, body_xforms, stripe_xforms, _pts[i] + Vector3.UP * _bank_lift(i, ext.y + BARRIER_W * 0.5), basis, right,
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
		var at_l := pos - right_v * (left_ext + OUTSET)
		var at_r := pos + right_v * (right_ext + OUTSET)
		# Beside a banked road, on the grass where it stands.
		if _banked:
			at_l.y = surface_height(at_l)
			at_r.y = surface_height(at_r)
		_add_narrow_sign(root, "NarrowSignL%d" % sign_i, at_l, yaw + TOE, left_n, right_n)
		_add_narrow_sign(root, "NarrowSignR%d" % sign_i, at_r, yaw - TOE, left_n, right_n)
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
	var side := 1.0 if on_right else -1.0
	var basis := Basis(Vector3.UP, yaw + PI * 0.5)
	var a := minf(ext_a, ext_b)
	var b := maxf(ext_a, ext_b)
	var span := maxf(b - a, barrier_l)
	var count := maxi(1, int(ceil(span / barrier_l)))
	var step := span / float(count)
	for k in count:
		var lat := a + (k + 0.5) * step
		var pos := _road_point(index, side * lat) + Vector3(0.0, barrier_h * 0.5, 0.0)
		var xf := Transform3D(basis, pos)
		body_xforms.append(xf)
		stripe_xforms.append(Transform3D(basis, pos + Vector3(0.0, 0.18, 0.0)))
	var hit := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(barrier_w, barrier_h, span)
	hit.shape = box
	var mid := (a + b) * 0.5
	hit.transform = Transform3D(basis, _road_point(index, side * mid) + Vector3(0.0, barrier_h * 0.5, 0.0))
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
	var left_ext := float(sample["left_ext"])
	var right_ext := float(sample["right_ext"])
	var bank := float(sample["bank"])
	if is_zero_approx(bank):
		_add_checkered_strip(root, left_ext, right_ext)
		_add_finish_gantry(root)
		return
	# On a banked road the line leans with the road, and the gantry stands as much higher as the
	# road's raised edge, so the banner still clears a car there.
	var lean := atan(bank)
	var line := Node3D.new()
	line.name = "BankedLine"
	line.transform = Transform3D(Basis(Vector3.BACK, lean), Vector3.UP * _lift_for(bank, float(sample["half_width"]), 0.0))
	root.add_child(line)
	_add_checkered_strip(line, left_ext / cos(lean), right_ext / cos(lean))
	var high := maxf(_lift_for(bank, float(sample["half_width"]), -left_ext), _lift_for(bank, float(sample["half_width"]), right_ext))
	_add_finish_gantry(root, high)


## The checkered line across the road, 30 m at most and no wider than the road, so on a narrow
## road it stops at the edges rather than running out through the curbs onto the grass.
func _add_checkered_strip(parent: Node3D, left_ext: float, right_ext: float) -> void:
	const MAX_COLS := 24
	const ROWS := 2
	const SQUARE := 1.25
	var road_w := left_ext + right_ext
	var cols := MAX_COLS
	var width := MAX_COLS * SQUARE
	var origin_x := -width * 0.5
	if road_w < width:
		cols = maxi(2, roundi(road_w / SQUARE))
		width = road_w
		origin_x = -left_ext
	var square_w := width / float(cols)
	var origin_z := -ROWS * SQUARE * 0.5
	var black_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	for row in ROWS:
		for col in cols:
			var pos := Vector3(
				origin_x + (col + 0.5) * square_w,
				0.02,
				origin_z + (row + 0.5) * SQUARE
			)
			var xform := Transform3D(Basis.IDENTITY, pos)
			if (row + col) % 2 == 0:
				black_xforms.append(xform)
			else:
				white_xforms.append(xform)
	_add_box_multimesh(parent, "CheckBlack", Vector3(square_w, 0.03, SQUARE), CHECK_BLACK, black_xforms)
	_add_box_multimesh(parent, "CheckWhite", Vector3(square_w, 0.03, SQUARE), CHECK_WHITE, white_xforms)


## `rise` stands it that much taller, for a banked road's raised edge.
func _add_finish_gantry(parent: Node3D, rise: float = 0.0) -> void:
	const POST_W := 0.22
	const BANNER_W := 38.6
	const BANNER_H := 0.9
	var post_h := 4.4 + rise
	var post_x := BANNER_W * 0.5
	var post_mat := _make_mat(POST_COLOR, 0.45)
	_add_box(parent, "PostL", Vector3(POST_W, post_h, POST_W), post_mat, Vector3(-post_x, post_h * 0.5, 0.0))
	_add_box(parent, "PostR", Vector3(POST_W, post_h, POST_W), post_mat, Vector3(post_x, post_h * 0.5, 0.0))
	_add_box(parent, "Crossbar", Vector3(BANNER_W, POST_W, POST_W), post_mat, Vector3(0.0, post_h, 0.0))
	const BCOLS := 16
	const BROWS := 2
	var cell_w := BANNER_W / float(BCOLS)
	var cell_h := BANNER_H / float(BROWS)
	var banner_y := post_h - POST_W - BANNER_H * 0.5 - 0.04
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
