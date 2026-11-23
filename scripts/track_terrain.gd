extends RefCounted

## Painted ground for a track (the `.trk` file's `terrain`, docs/track-format.md#painted-ground):
## heights on a square grid `CELL_M` apart, in track meters (`x` east, `y` ahead; the game's X and
## Z). A point on the grid is painted or not. Unpainted ground is the track style's own, built
## from the road as before, so a track with no painting is the same as one without the field.
##
## The grid is kept in square chunks of `CHUNK` by `CHUNK` points. A chunk holds the points from
## its corner up to, not including, the next chunk's, and the ground between its points, `CHUNK_M`
## on a side, is its area. Wherever a chunk is, the game draws all the ground beyond the road from
## the grid (race_track.gd's `_build_painted_ground()`), so a chunk is kept with every painted
## point and with any point next to one: the outside edge of the area is always unpainted, and the
## painted ground eases back to the style's there.

const _Self := preload("res://scripts/track_terrain.gd")

## Meters between grid points.
const CELL_M := 4.0
## Points along a chunk's side.
const CHUNK := 32
const CHUNK_M := CELL_M * CHUNK
## The file's height for an unpainted point, in centimeters.
const UNPAINTED_CM := -2147483648
## The highest and lowest a point may be painted, in meters.
const HEIGHT_LIMIT := 5000.0

enum Brush { RAISE, LOWER, SMOOTH, FLATTEN, ERASE }

## How fast Raise and Lower move the ground at the brush's middle at full strength, in meters a
## second, and how much of the way to their goal Smooth and Flatten go in a second.
const RAISE_MPS := 8.0
const BLEND_PER_S := 6.0

## Chunk (Vector2i) -> PackedFloat32Array of CHUNK * CHUNK heights, row by row along x; NAN where
## the point is unpainted.
var chunks: Dictionary = {}
## Chunk -> when it last changed, from `_next_stamp`, so the maker's map knows which to redraw.
var _stamps: Dictionary = {}
## Chunks whose arrays this terrain alone holds. Godot shares a packed array between everything
## that holds it, so a chunk another copy may hold is duplicated before it is written to.
var _owned: Dictionary = {}
static var _next_stamp: int = 0


func is_empty() -> bool:
	return chunks.is_empty()


## Another terrain with the same ground. The chunks' arrays are shared until one side writes to
## one, so the maker's undo steps cost only the chunks a stroke changes.
func copy() -> _Self:
	var out := _Self.new()
	out.chunks = chunks.duplicate()
	out._stamps = _stamps.duplicate()
	_owned.clear()
	return out


## A number that changes whenever chunk `key` does: no two changes, in any terrain, share one.
func stamp(key: Vector2i) -> int:
	return int(_stamps.get(key, 0))


func _touch(key: Vector2i) -> void:
	_next_stamp += 1
	_stamps[key] = _next_stamp


static func chunk_of(i: int, j: int) -> Vector2i:
	return Vector2i(floori(float(i) / CHUNK), floori(float(j) / CHUNK))


## The height painted at grid point `i`, `j` (at `i * CELL_M`, `j * CELL_M`), or NAN.
func height(i: int, j: int) -> float:
	var key := chunk_of(i, j)
	if not chunks.has(key):
		return NAN
	var cells: PackedFloat32Array = chunks[key]
	return cells[(i - key.x * CHUNK) + (j - key.y * CHUNK) * CHUNK]


func is_painted(i: int, j: int) -> bool:
	return not is_nan(height(i, j))


## Paints grid point `i`, `j` at `value`, or clears it with NAN.
func set_height(i: int, j: int, value: float) -> void:
	var key := chunk_of(i, j)
	if not chunks.has(key):
		if is_nan(value):
			return
		chunks[key] = _blank_chunk()
		_owned[key] = true
	if not _owned.has(key):
		chunks[key] = (chunks[key] as PackedFloat32Array).duplicate()
		_owned[key] = true
	var cells: PackedFloat32Array = chunks[key]
	cells[(i - key.x * CHUNK) + (j - key.y * CHUNK) * CHUNK] = clampf(value, -HEIGHT_LIMIT, HEIGHT_LIMIT) if not is_nan(value) else NAN
	chunks[key] = cells
	_touch(key)
	if not is_nan(value):
		_keep_neighbors(i, j, key)


## A painted point on a chunk's low edge is a corner of the ground in the chunks below it.
func _keep_neighbors(i: int, j: int, key: Vector2i) -> void:
	var low_x := i == key.x * CHUNK
	var low_y := j == key.y * CHUNK
	if low_x:
		_ensure(key + Vector2i(-1, 0))
	if low_y:
		_ensure(key + Vector2i(0, -1))
	if low_x and low_y:
		_ensure(key + Vector2i(-1, -1))


func _ensure(key: Vector2i) -> void:
	if not chunks.has(key):
		chunks[key] = _blank_chunk()
		_owned[key] = true
		_touch(key)


static func _blank_chunk() -> PackedFloat32Array:
	var cells := PackedFloat32Array()
	cells.resize(CHUNK * CHUNK)
	cells.fill(NAN)
	return cells


## Whether `point` (track x, y) lies in a chunk's area, where the game draws the ground from the
## grid.
func covers(point: Vector2) -> bool:
	return chunks.has(Vector2i(floori(point.x / CHUNK_M), floori(point.y / CHUNK_M)))


## The painted height at `point` (track x, y) in x, and in y how much of it is painted, 0 to 1:
## the share of the four grid points round it that are, weighted by nearness. The height is the
## painted points' alone.
func sample(point: Vector2) -> Vector2:
	if chunks.is_empty():
		return Vector2.ZERO
	var fx := point.x / CELL_M
	var fy := point.y / CELL_M
	var i := floori(fx)
	var j := floori(fy)
	var tx := fx - i
	var ty := fy - j
	var total := 0.0
	var weight := 0.0
	for c in 4:
		var di := c & 1
		var dj := c >> 1
		var w := (tx if di == 1 else 1.0 - tx) * (ty if dj == 1 else 1.0 - ty)
		if w <= 0.0:
			continue
		var h := height(i + di, j + dj)
		if is_nan(h):
			continue
		total += h * w
		weight += w
	if weight <= 0.0:
		return Vector2.ZERO
	return Vector2(total / weight, weight)


## The lowest and highest painted heights, or (0, 0) with none.
func height_range() -> Vector2:
	var low := INF
	var high := -INF
	for key: Vector2i in chunks:
		var cells: PackedFloat32Array = chunks[key]
		for h: float in cells:
			if not is_nan(h):
				low = minf(low, h)
				high = maxf(high, h)
	return Vector2(low, high) if low <= high else Vector2.ZERO


## The chunks' area together, in track meters, or an empty rect with none.
func area() -> Rect2:
	var out := Rect2()
	var first := true
	for key: Vector2i in chunks:
		var rect := Rect2(Vector2(key) * CHUNK_M, Vector2(CHUNK_M, CHUNK_M))
		out = rect if first else out.merge(rect)
		first = false
	return out


# --- Brushes -------------------------------------------------------------------------------


## How much a brush `radius` across reaches a point `dist` from its middle: all of it at the
## middle, none at the rim, smoothly between.
static func falloff(dist: float, radius: float) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	var t := dist / radius
	return (1.0 - t * t) * (1.0 - t * t)


## One dab of `brush` at `center` (track x, y), `radius` meters out, for `seconds` of painting at
## `strength` (0 to 1). Flatten goes toward `target`. `base` gives the ground an unpainted point
## starts from, taking a track point (Vector2) and returning meters: the maker passes the road's
## height nearby. Smooth leaves unpainted points alone. Returns whether anything changed.
func paint(brush: Brush, center: Vector2, radius: float, strength: float, seconds: float, target: float, base: Callable) -> bool:
	var reach := ceili(radius / CELL_M)
	var ci := roundi(center.x / CELL_M)
	var cj := roundi(center.y / CELL_M)
	var changes: Array[Vector3] = []
	for j in range(cj - reach, cj + reach + 1):
		for i in range(ci - reach, ci + reach + 1):
			var at := Vector2(i * CELL_M, j * CELL_M)
			var f := falloff(at.distance_to(center), radius)
			if f <= 0.0:
				continue
			var now := height(i, j)
			var next := now
			match brush:
				Brush.ERASE:
					next = NAN
				Brush.RAISE, Brush.LOWER:
					var from := now if not is_nan(now) else float(base.call(at))
					var way := 1.0 if brush == Brush.RAISE else -1.0
					next = from + way * RAISE_MPS * strength * seconds * f
				Brush.FLATTEN:
					var from := now if not is_nan(now) else float(base.call(at))
					next = lerpf(from, target, minf(BLEND_PER_S * strength * seconds * f, 1.0))
				Brush.SMOOTH:
					if is_nan(now):
						continue
					next = lerpf(now, _neighbor_mean(i, j), minf(BLEND_PER_S * strength * seconds * f, 1.0))
			if is_nan(now) and is_nan(next):
				continue
			if not is_nan(now) and not is_nan(next) and is_equal_approx(now, next):
				continue
			changes.append(Vector3(i, j, next))
	# Written after reading, so Smooth sees the ground as it was before this dab.
	for change: Vector3 in changes:
		set_height(int(change.x), int(change.y), change.z)
	if brush == Brush.ERASE and not changes.is_empty():
		prune()
	return not changes.is_empty()


## The mean of the painted points round `i`, `j`, itself included.
func _neighbor_mean(i: int, j: int) -> float:
	var total := 0.0
	var count := 0
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var h := height(i + di, j + dj)
			if not is_nan(h):
				total += h
				count += 1
	return total / count if count > 0 else height(i, j)


## Drops chunks that no painted point needs any more.
func prune() -> void:
	var needed: Dictionary = {}
	for key: Vector2i in chunks:
		var cells: PackedFloat32Array = chunks[key]
		for k in cells.size():
			if is_nan(cells[k]):
				continue
			needed[key] = true
			var li := k % CHUNK
			var lj := int(k / float(CHUNK))
			if li == 0:
				needed[key + Vector2i(-1, 0)] = true
			if lj == 0:
				needed[key + Vector2i(0, -1)] = true
			if li == 0 and lj == 0:
				needed[key + Vector2i(-1, -1)] = true
	for key: Vector2i in chunks.keys():
		if not needed.has(key):
			chunks.erase(key)
			_owned.erase(key)
	for key: Vector2i in needed:
		_ensure(key)


# --- The file ------------------------------------------------------------------------------


## The `terrain` list for the file: one entry for each chunk with a painted point, in order,
## `x` and `y` the chunk's place in chunks and `h` its heights in whole centimeters, 32-bit
## little-endian, row by row, deflated and in base64.
func to_file() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys: Array[Vector2i] = []
	for key: Vector2i in chunks:
		keys.append(key)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for key: Vector2i in keys:
		var cells: PackedFloat32Array = chunks[key]
		var any := false
		var cm := PackedInt32Array()
		cm.resize(cells.size())
		for k in cells.size():
			if is_nan(cells[k]):
				cm[k] = UNPAINTED_CM
			else:
				cm[k] = roundi(cells[k] * 100.0)
				any = true
		if not any:
			continue
		var packed := cm.to_byte_array().compress(FileAccess.COMPRESSION_DEFLATE)
		out.append({"x": key.x, "y": key.y, "h": Marshalls.raw_to_base64(packed)})
	return out


## Reads a file's `terrain` list. Problems go to `errors`; a bad chunk is left out.
static func from_file(raw: Variant, errors: Array) -> _Self:
	var out := _Self.new()
	if raw == null:
		return out
	if typeof(raw) != TYPE_ARRAY:
		errors.append("Track `terrain` must be an array.")
		return out
	var index := 0
	for item: Variant in raw as Array:
		index += 1
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("Terrain chunk %d must be a JSON object." % index)
			continue
		var chunk: Dictionary = item
		if not chunk.has("x") or not chunk.has("y") or typeof(chunk.get("h")) != TYPE_STRING:
			errors.append("Terrain chunk %d must have `x`, `y` and `h`." % index)
			continue
		var bytes := Marshalls.base64_to_raw(str(chunk["h"]))
		var size := CHUNK * CHUNK * 4
		var plain := bytes.decompress(size, FileAccess.COMPRESSION_DEFLATE) if not bytes.is_empty() else PackedByteArray()
		if plain.size() != size:
			errors.append("Terrain chunk %d's heights don't read." % index)
			continue
		var cm := plain.to_int32_array()
		var cells := PackedFloat32Array()
		cells.resize(cm.size())
		for k in cm.size():
			cells[k] = NAN if cm[k] == UNPAINTED_CM else float(cm[k]) / 100.0
		out.chunks[Vector2i(int(chunk["x"]), int(chunk["y"]))] = cells
		out._owned[Vector2i(int(chunk["x"]), int(chunk["y"]))] = true
	out.prune()
	return out
