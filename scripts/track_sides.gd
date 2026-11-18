extends RefCounted

## The ground beside a Street Rod 2 course, where it is not flat: Mulholland's hillsides, drops,
## guard rails and truss bridges, and the Aqueduct's sloped concrete banks. These replace the grass
## grid the other tracks use. They take the place of what Street Rod 2 draws from its kind words and
## its strip's edges, in the same units as the road: 1800 across is 8 m.

const _GroundMaterial := preload("res://scripts/ground_material.gd")

## Where the road's edge ends and a hillside or a drop begins, past the edge. Street Rod 2's verge.
const MOUNTAIN_VERGE := 200.0 * 8.0 / 1800.0
## How far across a hillside or a drop reaches its full height. Street Rod 2's 600 across.
const MOUNTAIN_BANK_RUN := 600.0 * 8.0 / 1800.0
## A side this high is a wall to a car. Lower, it is only starting to rise.
const HILL_MIN := 0.9
## A side this far down is a fall to a car.
const DROP_MIN := 1.5
## Past the verge and this much of the slope, a car on a side with no rail has gone over.
const OVER_EDGE_PAST_VERGE := 1.2

## The Aqueduct, across: a flat floor between Street Rod 2's 1480 and 3320, banks out to 1080 and
## 3720, and their tops at its height 1660 against the floor's 2000.
const AQUEDUCT_FLOOR_HALF := 920.0 * 8.0 / 1800.0
const AQUEDUCT_BANK_RUN := 400.0 * 8.0 / 1800.0
const AQUEDUCT_BANK_HIGH := 340.0 * 8.0 / 1800.0
## Street Rod 2 pushes a car on a bank back toward the floor, 15 across a frame and 25 more once
## it is far up, at about twelve frames a second.
const AQUEDUCT_PUSH_MPS := 0.8
const AQUEDUCT_PUSH_HIGH_MPS := 2.1
const AQUEDUCT_HIGH_AT := AQUEDUCT_FLOOR_HALF + 180.0 * 8.0 / 1800.0
## A made track can stand an Aqueduct side higher than Street Rod 2's, up to this. A raised side
## curves up from the floor like a bowl and runs this much farther out for each meter higher, which
## keeps its top at about 58°.
const AQUEDUCT_SIDE_MAX := 8.0
const AQUEDUCT_BOWL_RUN_PER_M := 1.25

## How far the ground beside the road reaches, unless another part of the course is nearer.
const _FAR_M := 280.0
## Beside a banked Aqueduct's raised side, the concrete falls this much a meter out.
const _BANK_FALL := 0.5
const _HILL_TOP_M := 30.0
const _HILL_TOP_RISE := 1.25
const _SECTION_STEP := 2
## Two sections' far points closer than this across are one point.
const _MEET_M := 0.01
## On a track with a raised Aqueduct side, each side's columns from the floor to its top.
const _BOWL_COLUMNS := 8
## About 150 m each way, with the track's sample every 2 m.
const _SLOW_SAMPLES := 75
const _WALL_H := 2.5
## A wall or rail starts this far out from its line and eases in over this far along the road, so a
## car running wide scrapes along it instead of meeting its bare end head on.
const _FLARE_OUT_M := MOUNTAIN_BANK_RUN
const _FLARE_ALONG_M := 25.0
const _RAIL_LOW := 0.42
const _RAIL_HIGH := 0.78
const _RAIL_POST_EVERY_M := 5.0
const _TRUSS_H := 4.6
const _TRUSS_BAY_M := 5.0
const _TRUSS_BEAM := 0.16
## Ground under everything, for what the ribbons don't reach, and mountains past it.
const _UNDER_M := 26.0
const _UNDER_HALF_M := 5000.0
const _MOUNTAIN_RING_M := 2600.0
const _MOUNTAIN_COLUMNS := 240
const _MOUNTAIN_LOW_M := 110.0
const _MOUNTAIN_HIGH_M := 460.0

## Mulholland's ground: grass, dirt where it stands over the road, and the gravel verge (see
## shaders/vertex_ground.gdshader). These colors are no longer drawn; they are the flat look it had
## before the textures.
const _GREEN := Color(0.11, 0.42, 0.1, 1)
const _HILL_BROWN := Color(0.56, 0.3, 0.07, 0)
const _RAIL_GRAY := Color(0.62, 0.62, 0.6, 1)
const _TRUSS_RED := Color(0.5, 0.05, 0.04, 1)
## The Aqueduct's vertex colors shade its concrete texture, whose mean is 0.651 in linear light
## (see ground_material.gd). Vertex colors are sRGB, so each is the old flat color (0.58 channel,
## 0.5 top, 0.9/0.78/0.12 yellow) taken to linear, divided by that mean, and taken back. The yellow
## line's red would need more than 1, so the line keeps its hue at a little under the old brightness.
const _CONCRETE := Color(0.704, 0.704, 0.68, 1)
const _CONCRETE_TOP := Color(0.609, 0.609, 0.585, 1)
const _YELLOW_EDGE := Color(1.0, 0.87, 0.14, 1)
## The ground far under the Aqueduct, untextured.
const _UNDER_CONCRETE := Color(0.5, 0.5, 0.48, 1)
const _MOUNTAIN_GRAY := Color(0.34, 0.34, 0.36, 1)
const _MOUNTAIN_SNOW := Color(0.66, 0.66, 0.68, 1)


## The ground's height at `lateral`, as `_mountain_section` draws it, with `side` the full height of
## a hillside (up) or drop (down) on that side of the road. Near the road it goes with `road_y`, and
## farther out it goes over to `far_y`, the road's height with the rises and dips averaged out.
static func mountain_ground(lateral: float, half_width: float, side: float, road_y: float, far_y: float) -> float:
	var out := absf(lateral) - half_width - MOUNTAIN_VERGE
	if out <= 0.0:
		return road_y
	if out < MOUNTAIN_BANK_RUN:
		return road_y + side * out / MOUNTAIN_BANK_RUN
	var far := far_y + _far_rise(side)
	if out < MOUNTAIN_BANK_RUN + _HILL_TOP_M:
		return lerpf(road_y + side, far, (out - MOUNTAIN_BANK_RUN) / _HILL_TOP_M)
	return far


static func _far_rise(side: float) -> float:
	return side * _HILL_TOP_RISE if side > 0.0 else side


## How high an Aqueduct side stands for a node's `left` or `right`: Street Rod 2's side for 0, or
## anything lower, and no higher than `AQUEDUCT_SIDE_MAX`.
static func aqueduct_side(value: float) -> float:
	return clampf(value, AQUEDUCT_BANK_HIGH, AQUEDUCT_SIDE_MAX)


## How far out past the floor an Aqueduct side `high` tall reaches its top.
static func aqueduct_run(high: float) -> float:
	return AQUEDUCT_BANK_RUN + maxf(high - AQUEDUCT_BANK_HIGH, 0.0) * AQUEDUCT_BOWL_RUN_PER_M


## How much of a side `high` tall curves like a bowl, rather than sloping straight as Street Rod 2's
## does: none at its height, all of it at twice that, so a side eases from one to the other.
static func aqueduct_curve(high: float) -> float:
	return clampf((high - AQUEDUCT_BANK_HIGH) / AQUEDUCT_BANK_HIGH, 0.0, 1.0)


## The channel's height at `lateral` over its floor, with that side `high` tall.
static func aqueduct_height(lateral: float, high: float = AQUEDUCT_BANK_HIGH) -> float:
	var out := absf(lateral) - AQUEDUCT_FLOOR_HALF
	if out <= 0.0:
		return 0.0
	var t := minf(out / aqueduct_run(high), 1.0)
	return lerpf(t, t * t, aqueduct_curve(high)) * high


## How steeply a side `high` tall rises at `lateral`, a meter farther out. 0 on the floor and past
## the top.
static func aqueduct_rise(lateral: float, high: float) -> float:
	var out := absf(lateral) - AQUEDUCT_FLOOR_HALF
	var run := aqueduct_run(high)
	if out <= 0.0 or out >= run:
		return 0.0
	return lerpf(1.0, 2.0 * out / run, aqueduct_curve(high)) * high / run


## Across the road, what a bank does to a car at `lateral`, with that side `high` tall. Toward the
## floor, in m/s. A raised side pushes less the more it curves, and not at all once it is a bowl: a
## car rides up it as on a banked corner instead (race_track.gd's `bank_slope()`).
static func aqueduct_push(lateral: float, high: float = AQUEDUCT_BANK_HIGH) -> float:
	var over := absf(lateral)
	if over <= AQUEDUCT_FLOOR_HALF:
		return 0.0
	var push := AQUEDUCT_PUSH_HIGH_MPS if over >= AQUEDUCT_HIGH_AT else AQUEDUCT_PUSH_MPS
	return -signf(lateral) * push * (1.0 - aqueduct_curve(high))


static func build_mountain(
	track: Node3D,
	pts: PackedVector3Array,
	yaws: PackedFloat32Array,
	half_ws: PackedFloat32Array,
	types: PackedStringArray,
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	rails: PackedByteArray,
	far_y: PackedFloat32Array,
	run_in_m: float,
	reaches: Array[PackedFloat32Array],
	back_reach: Vector2,
	lifts: Array = []
) -> void:
	var sections := _section_indices(pts.size())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var back := _behind_start(pts, yaws, run_in_m)
	var up := _side_lifts(lifts, pts.size())
	for side: float in [1.0, -1.0]:
		var heights := left if side > 0.0 else right
		var reach: PackedFloat32Array = reaches[0] if side > 0.0 else reaches[1]
		var back_side := back_reach.x if side > 0.0 else back_reach.y
		var raise := up[0] if side > 0.0 else up[1]
		_add_side_span(st, _mountain_section(back, yaws[0], side, half_ws[0], heights[0], far_y[0], back_side, raise[0]), _mountain_section(pts[0], yaws[0], side, half_ws[0], heights[0], far_y[0], reach[0], raise[0]))
		for k in range(sections.size() - 1):
			var a := sections[k]
			var b := sections[k + 1]
			_add_side_span(
				st,
				_mountain_section(pts[a], yaws[a], side, half_ws[a], heights[a], far_y[a], reach[a], raise[a]),
				_mountain_section(pts[b], yaws[b], side, half_ws[b], heights[b], far_y[b], reach[b], raise[b])
			)
	var ground := _GroundMaterial.vertex_ground()
	ground.set_shader_parameter(&"verge_m", MOUNTAIN_VERGE)
	_add_mesh(track, "Sides", st, ground)
	var railed := rails.duplicate()
	var right_out := _rail_flares(pts, types, railed)
	var left_out := _hill_flares(pts, left)
	var hill_right := _hill_flares(pts, right)
	for i in right_out.size():
		right_out[i] = maxf(right_out[i], hill_right[i])
	_build_walls(track, pts, yaws, half_ws, types, left, right, railed, left_out, right_out, sections, up)
	_build_rails(track, pts, yaws, half_ws, railed, right_out, up[1])
	_build_trusses(track, pts, yaws, half_ws, types, up)
	_build_under(track, pts, _GREEN.darkened(0.25), _GroundMaterial.grass())
	_build_mountains(track, pts)


## `reaches` is how far out the ground may go on the left and right of each sample, and
## `back_reach` the same behind the start: as far as halfway to another part of the course.
static func build_aqueduct(
	track: Node3D,
	pts: PackedVector3Array,
	yaws: PackedFloat32Array,
	run_in_m: float,
	reaches: Array[PackedFloat32Array],
	back_reach: Vector2,
	lifts: Array = [],
	highs: Array = []
) -> void:
	var sections := _section_indices(pts.size())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := SurfaceTool.new()
	steps.begin(Mesh.PRIMITIVE_TRIANGLES)
	var back := _behind_start(pts, yaws, run_in_m)
	var banked := not lifts.is_empty()
	var raised := not highs.is_empty()
	var up := _side_lifts(lifts, pts.size())
	var tall := _side_highs(highs, pts.size())
	for side: float in [1.0, -1.0]:
		var reach: PackedFloat32Array = reaches[0] if side > 0.0 else reaches[1]
		var high: PackedFloat32Array = tall[0] if side > 0.0 else tall[1]
		var back_side := back_reach.x if side > 0.0 else back_reach.y
		var start_tilt := Vector2(up[0][0], up[1][0])
		_add_side_span(
			st,
			_aqueduct_section(back, yaws[0], side, back_side, start_tilt, banked, high[0], raised),
			_aqueduct_section(pts[0], yaws[0], side, reach[0], start_tilt, banked, high[0], raised)
		)
		for k in range(sections.size() - 1):
			var a := sections[k]
			var b := sections[k + 1]
			var meet := _inside_meet(pts, yaws, a, b, side)
			_add_side_span(
				st,
				_aqueduct_section(pts[a], yaws[a], side, minf(reach[a], meet), Vector2(up[0][a], up[1][a]), banked, high[a], raised),
				_aqueduct_section(pts[b], yaws[b], side, minf(reach[b], meet), Vector2(up[0][b], up[1][b]), banked, high[b], raised),
				steps
			)
	_add_mesh(track, "Channel", st, _GroundMaterial.vertex_colored_concrete())
	var step_mesh := steps.commit()
	if step_mesh != null and step_mesh.get_surface_count() > 0:
		step_mesh.surface_set_material(0, _GroundMaterial.vertex_colored_concrete())
		var step_mi := MeshInstance3D.new()
		step_mi.name = "ChannelSteps"
		step_mi.mesh = step_mesh
		step_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		track.add_child(step_mi)
	var faces := PackedVector3Array()
	for k in range(sections.size() - 1):
		var a := sections[k]
		var b := sections[k + 1]
		for side: float in [1.0, -1.0]:
			var s := 0 if side > 0.0 else 1
			var top_a := AQUEDUCT_FLOOR_HALF + aqueduct_run(tall[s][a])
			var top_b := AQUEDUCT_FLOOR_HALF + aqueduct_run(tall[s][b])
			var raise_a := _aqueduct_top_raise(Vector2(up[0][a], up[1][a]), side, tall[s][a])
			var raise_b := _aqueduct_top_raise(Vector2(up[0][b], up[1][b]), side, tall[s][b])
			_add_wall_quad(faces, pts[a], yaws[a], side * top_a, pts[b], yaws[b], side * top_b, raise_a, raise_b)
	_add_wall_body(track, faces)
	_build_under(track, pts, _UNDER_CONCRETE.darkened(0.2))


## How far out on `side` (1 left, -1 right) the sideways lines at samples `a` and `b` meet, on the
## inside of a bend, or INF where they don't. Ground reaching past there folds back over itself: its
## triangles turn face down and the backs show dark on the ground round them, as the concrete is
## drawn from both sides. So the span between two sections runs out to where their lines meet, a
## wedge, and on the inside of a bend the wedges meet at its middle like spokes at a hub; the
## ground of the road before and after the bend covers on past there. Each span stops at its own
## meeting point rather than its neighbors', so no gap opens between them where the bend tightens.
## A circuit's grass does much the same (race_track.gd's `_inside_reach_caps()`).
static func _inside_meet(pts: PackedVector3Array, yaws: PackedFloat32Array, a: int, b: int, side: float) -> float:
	var r0 := Vector3(cos(yaws[a]), 0.0, -sin(yaws[a])) * side
	var r1 := Vector3(cos(yaws[b]), 0.0, -sin(yaws[b])) * side
	var mid_yaw := yaws[a] + angle_difference(yaws[a], yaws[b]) * 0.5
	var fwd := Vector3(sin(mid_yaw), 0.0, cos(mid_yaw))
	var along := Vector3(pts[b].x - pts[a].x, 0.0, pts[b].z - pts[a].z).dot(fwd)
	# How fast the two sideways lines close on each other, per meter out.
	var closing := -(r1 - r0).dot(fwd)
	if closing <= 0.0001 or along <= 0.0:
		return INF
	return along / closing


## The left (0) and right (1) edge lifts of a banked road, or all 0 when `lifts` is empty.
static func _side_lifts(lifts: Array, count: int) -> Array[PackedFloat32Array]:
	if lifts.size() == 2:
		return [lifts[0] as PackedFloat32Array, lifts[1] as PackedFloat32Array]
	var none := PackedFloat32Array()
	none.resize(count)
	none.fill(0.0)
	return [none, none]


## The left (0) and right (1) side heights of a raised Aqueduct, or all Street Rod 2's when `highs`
## is empty.
static func _side_highs(highs: Array, count: int) -> Array[PackedFloat32Array]:
	if highs.size() == 2:
		return [highs[0] as PackedFloat32Array, highs[1] as PackedFloat32Array]
	var stock := PackedFloat32Array()
	stock.resize(count)
	stock.fill(AQUEDUCT_BANK_HIGH)
	return [stock, stock]


## How far the Aqueduct's tilt lifts it at `lateral` across, from its left side's top `tilt.x` and
## its right's `tilt.y`, which stand where Street Rod 2's tops do. Past there it runs on as straight,
## for a raised side's wider bowl.
static func _aqueduct_tilt(tilt: Vector2, lateral: float) -> float:
	var top := AQUEDUCT_FLOOR_HALF + AQUEDUCT_BANK_RUN
	var middle := (tilt.x + tilt.y) * 0.5
	var edge := tilt.x if lateral > 0.0 else tilt.y
	return middle + (edge - middle) * absf(lateral) / top


## How far the top of the side on `side` stands over Street Rod 2's top: the tilt there, and how
## much higher the side is.
static func _aqueduct_top_raise(tilt: Vector2, side: float, high: float) -> float:
	var stock_top := AQUEDUCT_FLOOR_HALF + AQUEDUCT_BANK_RUN
	var edge := tilt.x if side > 0.0 else tilt.y
	var middle := (tilt.x + tilt.y) * 0.5
	var run_on := aqueduct_run(high) - AQUEDUCT_BANK_RUN
	return edge + (edge - middle) * run_on / stock_top + (high - AQUEDUCT_BANK_HIGH)


## How much of a raised edge's height the ground keeps `out` meters past it, falling 1 m in 2 as
## beside a banked street (race_track.gd's `_embank_keep()`).
static func _bank_keep(lift: float, out: float) -> float:
	if lift <= 0.0:
		return 0.0
	return clampf(1.0 - out * _BANK_FALL / lift, 0.0, 1.0)


static func _section_indices(count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i := 0
	while i < count - 1:
		out.append(i)
		i += _SECTION_STEP
	out.append(count - 1)
	return out


static func _behind_start(pts: PackedVector3Array, yaws: PackedFloat32Array, run_in_m: float) -> Vector3:
	return pts[0] - Vector3(sin(yaws[0]), 0.0, cos(yaws[0])) * run_in_m


## The road's height with its rises and dips averaged out, for ground far from it to follow. On a
## `loop`, whose last sample is the start again, the average runs on round past the start.
static func slow_heights(pts: PackedVector3Array, loop: bool = false) -> PackedFloat32Array:
	if loop and pts.size() > 2 * _SLOW_SAMPLES + 2:
		return _slow_heights_round(pts)
	var sums := PackedFloat32Array()
	sums.resize(pts.size() + 1)
	sums[0] = 0.0
	for i in pts.size():
		sums[i + 1] = sums[i] + pts[i].y
	var out := PackedFloat32Array()
	out.resize(pts.size())
	for i in pts.size():
		var from_i := maxi(i - _SLOW_SAMPLES, 0)
		var to_i := mini(i + _SLOW_SAMPLES + 1, pts.size())
		out[i] = (sums[to_i] - sums[from_i]) / float(to_i - from_i)
	return out


static func _slow_heights_round(pts: PackedVector3Array) -> PackedFloat32Array:
	var lap := pts.size() - 1
	var out := PackedFloat32Array()
	out.resize(pts.size())
	var window := 2 * _SLOW_SAMPLES + 1
	var sum := 0.0
	for k in range(-_SLOW_SAMPLES, _SLOW_SAMPLES + 1):
		sum += pts[posmod(k, lap)].y
	for i in lap:
		out[i] = sum / float(window)
		sum += pts[posmod(i + _SLOW_SAMPLES + 1, lap)].y - pts[posmod(i - _SLOW_SAMPLES, lap)].y
	out[lap] = out[0]
	return out


## Columns across one side of the road, from the road's edge outward, each {point, color, dirt}.
## Nothing goes past `reach` from the middle of the road, except the verge. A banked road's edge
## stands `lift` over its middle's height; the verge and the hillside or drop start from there.
static func _mountain_section(center: Vector3, yaw: float, side: float, half: float, height: float, far_y: float, reach: float, lift: float = 0.0) -> Array[Dictionary]:
	var across := Vector3(cos(yaw), 0.0, -sin(yaw)) * side
	var near := center + Vector3.UP * lift
	var verge := half + MOUNTAIN_VERGE
	var limit := maxf(reach, verge)
	var slope_end := minf(verge + MOUNTAIN_BANK_RUN, limit)
	var bank := _GREEN
	if height > 0.0:
		bank = _GREEN.lerp(_HILL_BROWN, clampf(height / HILL_MIN, 0.0, 1.0))
	var top := _far_rise(height)
	var far_center := Vector3(center.x, far_y, center.z)
	var hill_top := minf(slope_end + _HILL_TOP_M, limit)
	var far := minf(slope_end + _FAR_M, limit)
	# Every column carries how high it stands over the road and how far out it is from the road's
	# edge. The shader makes ground a little above the road dirt, so a hill is dirt nearly from its
	# foot and the field beside it stays grass; and it draws gravel out to a wavy line near
	# `MOUNTAIN_VERGE` all along the road.
	return [
		_column(near + across * half, 0.0, _GREEN, 0.0),
		_column(near + across * verge, 0.0, _GREEN, MOUNTAIN_VERGE),
		_column(near + across * slope_end, height, bank, slope_end - half),
		_column(far_center + across * hill_top, top, bank, hill_top - half),
		_column(far_center + across * far, top, bank if height > 0.0 else _GREEN, far - half),
	]


## A banked channel tilts as one, its left side's top `tilt.x` over the middle's height and its
## right's `tilt.y`; past a raised top the concrete falls back as the ground beside a banked street
## does. The side is `high` tall. `banked` adds the column where the top comes down, and `raised`
## the columns up a bowl, on every section so they all match.
static func _aqueduct_section(
	center: Vector3, yaw: float, side: float, reach: float, tilt: Vector2 = Vector2.ZERO, banked: bool = false,
	high: float = AQUEDUCT_BANK_HIGH, raised: bool = false
) -> Array[Dictionary]:
	var across := Vector3(cos(yaw), 0.0, -sin(yaw)) * side
	var run := aqueduct_run(high)
	var top := AQUEDUCT_FLOOR_HALF + run
	const EDGE_LINE := 0.22
	var limit := maxf(reach, top + EDGE_LINE)
	# Across the channel the tilt runs straight from one top to the other.
	var middle := (tilt.x + tilt.y) * 0.5
	var edge := _aqueduct_top_raise(tilt, side, high)
	var floor_up := lerpf(middle, tilt.x if side > 0.0 else tilt.y, AQUEDUCT_FLOOR_HALF / (AQUEDUCT_FLOOR_HALF + AQUEDUCT_BANK_RUN))
	var line_up := edge * _bank_keep(edge, EDGE_LINE)
	var columns: Array[Dictionary] = [
		_column(center, middle, _CONCRETE),
		_column(center + across * AQUEDUCT_FLOOR_HALF, floor_up, _CONCRETE),
	]
	if raised:
		for c in range(1, _BOWL_COLUMNS):
			var out := AQUEDUCT_FLOOR_HALF + run * float(c) / float(_BOWL_COLUMNS)
			columns.append(_column(center + across * out, _aqueduct_tilt(tilt, side * out) + aqueduct_height(out, high), _CONCRETE))
	columns.append_array([
		_column(center + across * top, AQUEDUCT_BANK_HIGH + edge, _CONCRETE),
		_column(center + across * top, AQUEDUCT_BANK_HIGH + edge, _YELLOW_EDGE),
		_column(center + across * (top + EDGE_LINE), AQUEDUCT_BANK_HIGH + line_up, _YELLOW_EDGE),
		_column(center + across * (top + EDGE_LINE), AQUEDUCT_BANK_HIGH + line_up, _CONCRETE_TOP),
	])
	if banked or raised:
		var foot := minf(top + maxf(edge / _BANK_FALL, EDGE_LINE + 0.05), limit)
		columns.append(_column(center + across * foot, AQUEDUCT_BANK_HIGH, _CONCRETE_TOP))
	columns.append(_column(center + across * minf(top + _FAR_M, limit), AQUEDUCT_BANK_HIGH, _CONCRETE_TOP))
	return columns


## `out` is how far the column is from the road's edge, in meters, for Mulholland's gravel verge.
## Its height over the road, `rise` (none below it), decides Mulholland's dirt.
static func _column(point: Vector3, rise: float, color: Color, out: float = 0.0) -> Dictionary:
	return {"point": point + Vector3(0.0, rise, 0.0), "color": color, "above": maxf(rise, 0.0), "out": out}


## `steps`, when given, takes the steps in height where wedges meet on the inside of a bend
## (`_add_step()`).
static func _add_side_span(st: SurfaceTool, near: Array[Dictionary], far: Array[Dictionary], steps: SurfaceTool = null) -> void:
	for c in range(near.size() - 1):
		var a0: Vector3 = near[c]["point"]
		var a1: Vector3 = near[c + 1]["point"]
		var b0: Vector3 = far[c]["point"]
		var b1: Vector3 = far[c + 1]["point"]
		if a0.is_equal_approx(a1) and b0.is_equal_approx(b1):
			continue
		var na: Dictionary = near[c]
		var na1: Dictionary = near[c + 1]
		var fb: Dictionary = far[c]
		var fb1: Dictionary = far[c + 1]
		# Facing up on either side of the road.
		var up := (a1 - a0).cross(b0 - a0).y > 0.0
		if steps != null and Vector2(a1.x - b1.x, a1.z - b1.z).length() < _MEET_M:
			_add_step(steps, na, na1, fb1, b0)
		else:
			for col: Dictionary in [na, na1, fb1] if up else [na, fb1, na1]:
				_add_column_vertex(st, col)
		for col: Dictionary in [na, fb1, fb] if up else [na, fb, fb1]:
			_add_column_vertex(st, col)


## Where two sections' ground meets on the inside of a bend (`_inside_meet()`), the span is a
## wedge whose tip, `far`, stands at its far section's height, and the next wedge's at the next
## section's: on a climbing bend each stands a little over the one before, and between them
## the far ground showed through as dark lines. This upright sliver fills the step, under the edge
## of the higher wedge from `near` to `tip`, its own section's tip below `far`. It faces the lower
## side, the only side it can be seen from, and is lit as the ground there, facing up; drawn
## smoothed with the ground it bent the normals round it, and lit as a wall it showed as a line.
## On the flat it is nothing and is left out. `toward` is a point on the wedge's side of it.
static func _add_step(steps: SurfaceTool, near: Dictionary, tip: Dictionary, far: Dictionary, toward: Vector3) -> void:
	var p0: Vector3 = near["point"]
	var p1: Vector3 = tip["point"]
	var p2: Vector3 = far["point"]
	if absf(p2.y - p1.y) < _MEET_M:
		return
	# The wedge is on the lower side when its tip is the lower one.
	var lower := (toward - p0) * signf(p1.y - p2.y)
	lower.y = 0.0
	# Its front is the side the cross product of its winding points away from, as the normals
	# SurfaceTool.generate_normals() makes for the ground show.
	var order: Array[Dictionary] = [near, tip, far]
	if (p1 - p0).cross(p2 - p0).dot(lower) > 0.0:
		order = [near, far, tip]
	for col: Dictionary in order:
		steps.set_normal(Vector3.UP)
		_add_column_vertex(steps, col)


## A column's point, with its color, its height over the road in UV.x and its distance from the
## road's edge in UV.y, for shaders/vertex_ground.gdshader.
static func _add_column_vertex(st: SurfaceTool, col: Dictionary) -> void:
	st.set_uv(Vector2(float(col["above"]), float(col["out"])))
	_add_vertex(st, col["point"], col["color"])


static func _add_vertex(st: SurfaceTool, point: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(point)


static func _vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _add_mesh(parent: Node3D, node_name: String, st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## A guard rail comes in from the side before it reaches the road's verge, on the flat ground before
## the drop. Marks those samples in `rails` and answers how far out each one is.
static func _rail_flares(pts: PackedVector3Array, types: PackedStringArray, rails: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(pts.size())
	out.fill(0.0)
	var starts := PackedInt32Array()
	for i in range(1, pts.size()):
		if rails[i] != 0 and rails[i - 1] == 0:
			starts.append(i)
	for start: int in starts:
		var along := 0.0
		var j := start - 1
		while j >= 0 and rails[j] == 0 and types[j] != TrackFile.ROAD_BRIDGE:
			along += pts[j].distance_to(pts[j + 1])
			if along >= _FLARE_ALONG_M:
				break
			rails[j] = 1
			out[j] = _FLARE_OUT_M * along / _FLARE_ALONG_M
			j -= 1
	return out


## A hillside's wall starts out on its slope, where the bank is still low, and comes in to the verge
## as the bank rises. Answers how far out it is at each sample.
static func _hill_flares(pts: PackedVector3Array, heights: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(pts.size())
	out.fill(0.0)
	for i in range(1, pts.size()):
		if heights[i] < HILL_MIN or heights[i - 1] >= HILL_MIN:
			continue
		var along := 0.0
		var j := i
		while j < pts.size() and along < _FLARE_ALONG_M:
			out[j] = _FLARE_OUT_M * (1.0 - along / _FLARE_ALONG_M)
			if j + 1 < pts.size():
				along += pts[j].distance_to(pts[j + 1])
			j += 1
	return out


## Where a car stops on this side of this sample, across, or zero with nothing there.
static func _wall_at(
	i: int,
	side: float,
	half_ws: PackedFloat32Array,
	types: PackedStringArray,
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	rails: PackedByteArray,
	left_out: PackedFloat32Array,
	right_out: PackedFloat32Array
) -> float:
	if types[i] == TrackFile.ROAD_BRIDGE:
		return half_ws[i]
	var height := left[i] if side > 0.0 else right[i]
	if height >= HILL_MIN or (side < 0.0 and rails[i] != 0):
		return half_ws[i] + MOUNTAIN_VERGE + (left_out[i] if side > 0.0 else right_out[i])
	return 0.0


static func _build_walls(
	track: Node3D,
	pts: PackedVector3Array,
	yaws: PackedFloat32Array,
	half_ws: PackedFloat32Array,
	types: PackedStringArray,
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	rails: PackedByteArray,
	left_out: PackedFloat32Array,
	right_out: PackedFloat32Array,
	sections: PackedInt32Array,
	up: Array[PackedFloat32Array]
) -> void:
	var faces := PackedVector3Array()
	for k in range(sections.size() - 1):
		var a := sections[k]
		var b := sections[k + 1]
		for side: float in [1.0, -1.0]:
			var raise := up[0] if side > 0.0 else up[1]
			var wall_a := _wall_at(a, side, half_ws, types, left, right, rails, left_out, right_out)
			var wall_b := _wall_at(b, side, half_ws, types, left, right, rails, left_out, right_out)
			if wall_a > 0.0 and wall_b > 0.0:
				_add_wall_quad(faces, pts[a], yaws[a], side * wall_a, pts[b], yaws[b], side * wall_b, raise[a], raise[b])
			# Where a bridge starts or ends, a face across the road's old edge.
			if (types[a] == TrackFile.ROAD_BRIDGE) != (types[b] == TrackFile.ROAD_BRIDGE):
				var wide := maxf(half_ws[a], half_ws[b]) + MOUNTAIN_VERGE
				var narrow := minf(half_ws[a], half_ws[b])
				_add_wall_quad(faces, pts[b], yaws[b], side * narrow, pts[b], yaws[b], side * wide, raise[b], raise[b])
	_add_wall_body(track, faces)


## `lift0` and `lift1` raise each end, for a banked road's raised side.
static func _add_wall_quad(faces: PackedVector3Array, p0: Vector3, yaw0: float, lat0: float, p1: Vector3, yaw1: float, lat1: float, lift0: float = 0.0, lift1: float = 0.0) -> void:
	var a := p0 + Vector3(cos(yaw0), 0.0, -sin(yaw0)) * lat0 + Vector3.UP * lift0
	var b := p1 + Vector3(cos(yaw1), 0.0, -sin(yaw1)) * lat1 + Vector3.UP * lift1
	var up := Vector3(0.0, _WALL_H, 0.0)
	var down := Vector3(0.0, -1.0, 0.0)
	faces.append_array(PackedVector3Array([a + down, b + down, b + up, a + down, b + up, a + up]))


## A trimesh, since a few kilometers of walls would be thousands of boxes.
static func _add_wall_body(track: Node3D, faces: PackedVector3Array) -> void:
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var hit := CollisionShape3D.new()
	hit.shape = shape
	var body := StaticBody3D.new()
	body.name = "TrackWalls"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"track_obstacle", true)
	body.add_child(hit)
	track.add_child(body)


## Street Rod 2's guard rail: a low beam on posts at the verge, on the right only.
## `lift` raises the rail where a banked road's right edge stands up.
static func _build_rails(track: Node3D, pts: PackedVector3Array, yaws: PackedFloat32Array, half_ws: PackedFloat32Array, rails: PackedByteArray, right_out: PackedFloat32Array, lift: PackedFloat32Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var posts: Array[Transform3D] = []
	var since_post := _RAIL_POST_EVERY_M
	for i in range(pts.size() - 1):
		if rails[i] == 0 or rails[i + 1] == 0:
			continue
		var a := _rail_foot(pts[i], yaws[i], half_ws[i] + right_out[i]) + Vector3.UP * lift[i]
		var b := _rail_foot(pts[i + 1], yaws[i + 1], half_ws[i + 1] + right_out[i + 1]) + Vector3.UP * lift[i + 1]
		_add_vertex(st, a + Vector3.UP * _RAIL_LOW, _RAIL_GRAY)
		_add_vertex(st, b + Vector3.UP * _RAIL_LOW, _RAIL_GRAY)
		_add_vertex(st, b + Vector3.UP * _RAIL_HIGH, _RAIL_GRAY)
		_add_vertex(st, a + Vector3.UP * _RAIL_LOW, _RAIL_GRAY)
		_add_vertex(st, b + Vector3.UP * _RAIL_HIGH, _RAIL_GRAY)
		_add_vertex(st, a + Vector3.UP * _RAIL_HIGH, _RAIL_GRAY)
		since_post += a.distance_to(b)
		if since_post >= _RAIL_POST_EVERY_M:
			since_post = 0.0
			posts.append(Transform3D(Basis(Vector3.UP, yaws[i]).scaled(Vector3(0.14, _RAIL_HIGH + 0.3, 0.14)), a + Vector3.UP * (_RAIL_HIGH * 0.5 - 0.15)))
	_add_mesh(track, "GuardRail", st, _vertex_color_material())
	_add_unit_boxes(track, "GuardRailPosts", posts, _RAIL_GRAY.darkened(0.3))


static func _rail_foot(center: Vector3, yaw: float, half: float) -> Vector3:
	# Toward -X, which is the driver's right.
	return center - Vector3(cos(yaw), 0.0, -sin(yaw)) * (half + MOUNTAIN_VERGE)


## Street Rod 2's narrow road: dark red posts, bars over the road and diagonals on each side.
## `lifts` raise each side's feet where a banked road's edge stands up.
static func _build_trusses(track: Node3D, pts: PackedVector3Array, yaws: PackedFloat32Array, half_ws: PackedFloat32Array, types: PackedStringArray, lifts: Array[PackedFloat32Array]) -> void:
	var beams: Array[Transform3D] = []
	var i := 0
	var run := 0.0
	var last: Array[Vector3] = []
	while i < pts.size():
		if types[i] != TrackFile.ROAD_BRIDGE:
			last.clear()
			run = 0.0
			i += 1
			continue
		if not last.is_empty():
			run += pts[i].distance_to(pts[i - 1])
		if last.is_empty() or run >= _TRUSS_BAY_M:
			run = 0.0
			var across := Vector3(cos(yaws[i]), 0.0, -sin(yaws[i])) * (half_ws[i] + 0.1)
			var feet: Array[Vector3] = [pts[i] + across + Vector3.UP * lifts[0][i], pts[i] - across + Vector3.UP * lifts[1][i]]
			var up := Vector3.UP * _TRUSS_H
			for foot: Vector3 in feet:
				beams.append(_beam(foot, foot + up))
			beams.append(_beam(feet[0] + up, feet[1] + up))
			if not last.is_empty():
				for s in 2:
					beams.append(_beam(last[s], feet[s]))
					beams.append(_beam(last[s] + up, feet[s] + up))
					beams.append(_beam(last[s], feet[s] + up))
			last = feet
		i += 1
	_add_unit_boxes(track, "Truss", beams, _TRUSS_RED)


## A unit box stretched from `a` to `b`.
static func _beam(a: Vector3, b: Vector3) -> Transform3D:
	var along := b - a
	var length := along.length()
	var forward := along / maxf(length, 0.001)
	var up_hint := Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT
	var x := up_hint.cross(forward).normalized()
	var y := forward.cross(x).normalized()
	return Transform3D(Basis(x * _TRUSS_BEAM, y * _TRUSS_BEAM, forward * length), (a + b) * 0.5)


static func _add_unit_boxes(parent: Node3D, node_name: String, xforms: Array[Transform3D], color: Color) -> void:
	if xforms.is_empty():
		return
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	box.material = mat
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


## `ground` replaces the flat `color` when given.
static func _build_under(track: Node3D, pts: PackedVector3Array, color: Color, ground: Material = null) -> void:
	var low := INF
	var center := Vector3.ZERO
	for p: Vector3 in pts:
		low = minf(low, p.y)
		center += p
	center /= float(pts.size())
	var plane := PlaneMesh.new()
	plane.size = Vector2(_UNDER_HALF_M * 2.0, _UNDER_HALF_M * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	plane.material = mat if ground == null else ground
	var mi := MeshInstance3D.new()
	mi.name = "UnderGround"
	mi.mesh = plane
	mi.position = Vector3(center.x, low - _UNDER_M, center.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	track.add_child(mi)


## The gray peaks Street Rod 2 draws behind Mulholland, a jagged ridge far off in every direction.
static func _build_mountains(track: Node3D, pts: PackedVector3Array) -> void:
	var center := Vector3.ZERO
	var low := INF
	for p: Vector3 in pts:
		center += p
		low = minf(low, p.y)
	center /= float(pts.size())
	var noise := FastNoiseLite.new()
	noise.seed = 2
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_y := low - _UNDER_M
	var ridge: Array[Vector3] = []
	for i in _MOUNTAIN_COLUMNS:
		var angle := TAU * float(i) / float(_MOUNTAIN_COLUMNS)
		# Sampled on a circle so the ridge meets itself.
		var circle := Vector2(cos(angle), sin(angle)) * 90.0
		var shape := absf(noise.get_noise_2dv(circle)) * 2.0 + 0.5 * noise.get_noise_2dv(circle * 3.0)
		var high := lerpf(_MOUNTAIN_LOW_M, _MOUNTAIN_HIGH_M, clampf(shape, 0.0, 1.0))
		ridge.append(center + Vector3(cos(angle) * _MOUNTAIN_RING_M, 0.0, sin(angle) * _MOUNTAIN_RING_M) + Vector3.UP * (base_y - center.y + high))
	for i in _MOUNTAIN_COLUMNS:
		var top_a := ridge[i]
		var top_b := ridge[(i + 1) % _MOUNTAIN_COLUMNS]
		var foot_a := Vector3(top_a.x, base_y, top_a.z)
		var foot_b := Vector3(top_b.x, base_y, top_b.z)
		var color_a := _mountain_color(top_a.y - base_y)
		var color_b := _mountain_color(top_b.y - base_y)
		_add_vertex(st, foot_a, _MOUNTAIN_GRAY)
		_add_vertex(st, top_a, color_a)
		_add_vertex(st, top_b, color_b)
		_add_vertex(st, foot_a, _MOUNTAIN_GRAY)
		_add_vertex(st, top_b, color_b)
		_add_vertex(st, foot_b, _MOUNTAIN_GRAY)
	_add_mesh(track, "Mountains", st, _vertex_color_material())


static func _mountain_color(high: float) -> Color:
	return _MOUNTAIN_GRAY.lerp(_MOUNTAIN_SNOW, smoothstep(_MOUNTAIN_LOW_M, _MOUNTAIN_HIGH_M, high))
