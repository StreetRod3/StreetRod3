class_name TrackFile
extends RefCounted

## Loader and validator for `.trk` race-track graphs.
## See `docs/track-format.md`.

const NODE_START := "start"
const NODE_FINISH := "finish"
const NODE_REGULAR := "regular"

const ROAD_REGULAR := "regular"
const ROAD_NARROW := "narrow"
const ROAD_NARROW_LEFT := "narrow-left"
const ROAD_NARROW_RIGHT := "narrow-right"
const ROAD_NARROW_BOTH := "narrow-both"
const ROAD_NARROW_OBSTACLE := "narrow-obstacle"
const ROAD_NARROW_LEFT_OBSTACLE := "narrow-left-obstacle"
const ROAD_NARROW_RIGHT_OBSTACLE := "narrow-right-obstacle"
const ROAD_NARROW_BOTH_OBSTACLE := "narrow-both-obstacle"

const SURFACE_REGULAR := "regular"
const SURFACE_DRY := "dry"
const SURFACE_WET := "wet"
const SURFACE_ICY := "icy"

const DEFAULT_WIDTH := 8.0

const STYLE_CIRCUIT := "circuit"
const STYLE_STREET := "street"
const SCENERY_KINDS := ["tree", "big_tree", "bare_tree", "pole", "gantry", "dash", "finish", "streak", "dark_streak"]

const _NODE_TYPES := [NODE_START, NODE_FINISH, NODE_REGULAR]
const _ROAD_TYPES := [
	ROAD_REGULAR,
	ROAD_NARROW,
	ROAD_NARROW_LEFT,
	ROAD_NARROW_RIGHT,
	ROAD_NARROW_BOTH,
	ROAD_NARROW_OBSTACLE,
	ROAD_NARROW_LEFT_OBSTACLE,
	ROAD_NARROW_RIGHT_OBSTACLE,
	ROAD_NARROW_BOTH_OBSTACLE,
]
const _SURFACES := [SURFACE_REGULAR, SURFACE_DRY, SURFACE_WET, SURFACE_ICY]


static func load_path(path: String) -> Dictionary:
	var empty := _empty_result()
	if path.is_empty():
		empty.errors.append("Track path is empty.")
		return empty
	if not FileAccess.file_exists(path):
		empty.errors.append("Track file not found: %s" % path)
		return empty
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		empty.errors.append("Could not open track file: %s" % path)
		return empty
	var text := file.get_as_text()
	file.close()
	return parse_text(text, path)


static func parse_text(text: String, source: String = "") -> Dictionary:
	var result := _empty_result()
	result.source = source
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		result.errors.append("Invalid JSON in %s (line %d): %s" % [
			source if not source.is_empty() else "<memory>",
			json.get_error_line(),
			json.get_error_message(),
		])
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result.errors.append("Track root must be a JSON object.")
		return result
	var root: Dictionary = json.data
	result.name = str(root.get("name", ""))
	result.style = str(root.get("style", STYLE_CIRCUIT))
	if result.style != STYLE_CIRCUIT and result.style != STYLE_STREET:
		result.errors.append("Unknown track style `%s`." % result.style)
	_parse_nodes(root, result)
	_parse_roads(root, result)
	_parse_pois(root, result)
	_parse_buildings(root, result)
	_parse_scenery(root, result)
	if result.errors.is_empty():
		_build_race_path(result)
	return result


## Track `x` is world X, track `y` is world Z, track `z` is height (world Y).
static func world_position(node: Dictionary) -> Vector3:
	return Vector3(float(node.get("x", 0.0)), float(node.get("z", 0.0)), float(node.get("y", 0.0)))


static func _empty_result() -> Dictionary:
	return {
		"source": "",
		"name": "",
		"nodes": {}, # id -> node dict
		"node_order": [], # ids in file order
		"roads": [],
		"start_id": 0,
		"finish_ids": [],
		"path_ids": [],
		"pois": {}, # poi id -> poi dict
		"poi_order": [],
		"buildings": [], # scenery boxes: x, y, w, d, h
		"style": STYLE_CIRCUIT,
		"scenery": [], # what stands beside a street track: kind, x, y
		"errors": [],
		"warnings": [],
	}


static func _parse_nodes(root: Dictionary, result: Dictionary) -> void:
	if not root.has("nodes") or typeof(root["nodes"]) != TYPE_ARRAY:
		result.errors.append("Track must contain a `nodes` array.")
		return
	for raw: Variant in root["nodes"]:
		if typeof(raw) != TYPE_DICTIONARY:
			result.errors.append("Each node must be a JSON object.")
			continue
		var node: Dictionary = raw
		if not node.has("id"):
			result.errors.append("Node is missing `id`.")
			continue
		var id := int(node["id"])
		if result.nodes.has(id):
			result.errors.append("Duplicate node id %d." % id)
			continue
		if not node.has("x") or not node.has("y"):
			result.errors.append("Node %d must have numeric `x` and `y`." % id)
			continue
		var ntype := str(node.get("type", NODE_REGULAR)).strip_edges().to_lower()
		if ntype.is_empty():
			ntype = NODE_REGULAR
		if not _NODE_TYPES.has(ntype):
			result.warnings.append("Node %d has unknown type `%s`; using regular." % [id, ntype])
			ntype = NODE_REGULAR
		var parsed := {
			"id": id,
			"x": float(node["x"]),
			"y": float(node["y"]),
			"z": _node_height(node, id, result),
			"type": ntype,
		}
		result.nodes[id] = parsed
		result.node_order.append(id)
		if ntype == NODE_START:
			if result.start_id != 0:
				result.warnings.append("Multiple start nodes; keeping id %d." % result.start_id)
			else:
				result.start_id = id
		elif ntype == NODE_FINISH:
			result.finish_ids.append(id)
	if result.nodes.is_empty():
		result.errors.append("Track has no valid nodes.")
	if result.start_id == 0 and not result.node_order.is_empty():
		result.start_id = int(result.node_order[0])
		result.warnings.append("No start node; using first node %d." % result.start_id)
	if result.finish_ids.is_empty() and not result.node_order.is_empty():
		var last_id := int(result.node_order[result.node_order.size() - 1])
		result.finish_ids.append(last_id)
		result.warnings.append("No finish node; using last node %d." % last_id)


## Missing `z`, or a value that is not a number, is ground level.
static func _node_height(node: Dictionary, id: int, result: Dictionary) -> float:
	if not node.has("z"):
		return 0.0
	var raw: Variant = node["z"]
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		result.warnings.append("Node %d has a non-numeric `z`; using 0." % id)
		return 0.0
	return float(raw)


static func _parse_roads(root: Dictionary, result: Dictionary) -> void:
	if not root.has("roads") or typeof(root["roads"]) != TYPE_ARRAY:
		result.errors.append("Track must contain a `roads` array.")
		return
	for raw: Variant in root["roads"]:
		if typeof(raw) != TYPE_DICTIONARY:
			result.errors.append("Each road must be a JSON object.")
			continue
		var road: Dictionary = raw
		if not road.has("from") or not road.has("to"):
			result.errors.append("Road is missing `from` or `to`.")
			continue
		var from_id := int(road["from"])
		var to_id := int(road["to"])
		if not result.nodes.has(from_id) or not result.nodes.has(to_id):
			result.errors.append("Road %d -> %d references an unknown node." % [from_id, to_id])
			continue
		if from_id == to_id:
			result.errors.append("Road %d -> %d starts and ends on the same node." % [from_id, to_id])
			continue
		var rtype := str(road.get("type", ROAD_REGULAR)).strip_edges().to_lower()
		if rtype.is_empty():
			rtype = ROAD_REGULAR
		if rtype == ROAD_NARROW:
			rtype = ROAD_NARROW_BOTH
		elif rtype == ROAD_NARROW_OBSTACLE:
			rtype = ROAD_NARROW_BOTH_OBSTACLE
		if not _ROAD_TYPES.has(rtype):
			result.warnings.append(
				"Road %d -> %d has unknown type `%s`; using regular." % [from_id, to_id, rtype]
			)
			rtype = ROAD_REGULAR
		var surface := str(road.get("surface", SURFACE_REGULAR)).strip_edges().to_lower()
		if surface.is_empty():
			surface = SURFACE_REGULAR
		if not _SURFACES.has(surface):
			result.warnings.append(
				"Road %d -> %d has unknown surface `%s`; using regular." % [from_id, to_id, surface]
			)
			surface = SURFACE_REGULAR
		var width := DEFAULT_WIDTH
		if road.has("width"):
			width = float(road["width"])
		if width <= 0.0:
			result.warnings.append(
				"Road %d -> %d has non-positive width; using %.1f." % [from_id, to_id, DEFAULT_WIDTH]
			)
			width = DEFAULT_WIDTH
		result.roads.append({
			"from": from_id,
			"to": to_id,
			"width": width,
			"type": rtype,
			"surface": surface,
		})


static func _build_race_path(result: Dictionary) -> void:
	var outgoing: Dictionary = {}
	for road: Dictionary in result.roads:
		var from_id: int = road["from"]
		if not outgoing.has(from_id):
			outgoing[from_id] = []
		outgoing[from_id].append(road)
	var finish_set: Dictionary = {}
	for fid: int in result.finish_ids:
		finish_set[int(fid)] = true
	var path: Array[int] = []
	var used: Dictionary = {}
	var current: int = int(result.start_id)
	path.append(current)
	var guard := 0
	while guard < result.roads.size() + 2:
		guard += 1
		if finish_set.has(current) and path.size() > 1:
			break
		var choices: Array = outgoing.get(current, [])
		var next_road: Dictionary = {}
		for road: Dictionary in choices:
			var key := "%d>%d" % [road["from"], road["to"]]
			if used.has(key):
				continue
			next_road = road
			break
		if next_road.is_empty():
			break
		var key := "%d>%d" % [next_road["from"], next_road["to"]]
		used[key] = true
		current = int(next_road["to"])
		path.append(current)
	if path.size() < 2:
		result.errors.append("Could not walk a race path from start to finish.")
		return
	if not finish_set.has(path[path.size() - 1]):
		result.warnings.append("Race path does not end on a finish node.")
	result.path_ids = path


static func normalize_road_type(rtype: String) -> String:
	var t := rtype.strip_edges().to_lower()
	if t == ROAD_NARROW:
		return ROAD_NARROW_BOTH
	if t == ROAD_NARROW_OBSTACLE:
		return ROAD_NARROW_BOTH_OBSTACLE
	return t


static func narrows_left(rtype: String) -> bool:
	var t := normalize_road_type(rtype)
	return (
		t == ROAD_NARROW_LEFT
		or t == ROAD_NARROW_BOTH
		or t == ROAD_NARROW_LEFT_OBSTACLE
		or t == ROAD_NARROW_BOTH_OBSTACLE
	)


static func narrows_right(rtype: String) -> bool:
	var t := normalize_road_type(rtype)
	return (
		t == ROAD_NARROW_RIGHT
		or t == ROAD_NARROW_BOTH
		or t == ROAD_NARROW_RIGHT_OBSTACLE
		or t == ROAD_NARROW_BOTH_OBSTACLE
	)


static func obstacle_left(rtype: String) -> bool:
	var t := normalize_road_type(rtype)
	return t == ROAD_NARROW_LEFT_OBSTACLE or t == ROAD_NARROW_BOTH_OBSTACLE


static func obstacle_right(rtype: String) -> bool:
	var t := normalize_road_type(rtype)
	return t == ROAD_NARROW_RIGHT_OBSTACLE or t == ROAD_NARROW_BOTH_OBSTACLE


## Driveable extents from the centerline: `x` = left, `y` = right, both positive.
static func driveable_extents(full_width: float, rtype: String) -> Vector2:
	var width := maxf(full_width, 1.0)
	var half := width * 0.5
	var inset := width / 3.0
	var left := half
	var right := half
	if narrows_left(rtype):
		left = maxf(half - inset, 0.4)
	if narrows_right(rtype):
		right = maxf(half - inset, 0.4)
	return Vector2(left, right)


## World points from one point of interest to another: the driveway, the street nodes, then the destination driveway.
## Empty when either id is missing or no directed roads connect their street nodes.
static func cruise_route(result: Dictionary, from_poi: String, to_poi: String) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var pois: Dictionary = result.get("pois", {})
	if not pois.has(from_poi) or not pois.has(to_poi):
		return points
	var origin: Dictionary = pois[from_poi]
	var dest: Dictionary = pois[to_poi]
	var street := _street_path(result, int(origin["at"]), int(dest["at"]))
	if street.is_empty():
		return points
	_append_route_point(points, world_position(origin))
	var nodes: Dictionary = result["nodes"]
	for nid in street:
		_append_route_point(points, world_position(nodes[nid]))
	_append_route_point(points, world_position(dest))
	return points


static func _append_route_point(points: Array[Vector3], point: Vector3) -> void:
	if points.is_empty() or points[points.size() - 1].distance_squared_to(point) > 0.04:
		points.append(point)


## Directed street nodes from `from_id` to `to_id`, including both ends. Empty when no road reaches.
static func _street_path(result: Dictionary, from_id: int, to_id: int) -> Array[int]:
	var path: Array[int] = []
	var nodes: Dictionary = result.get("nodes", {})
	if not nodes.has(from_id) or not nodes.has(to_id):
		return path
	if from_id == to_id:
		path.append(from_id)
		return path
	var outgoing: Dictionary = {}
	for road: Dictionary in result.get("roads", []):
		var fid: int = int(road["from"])
		if not outgoing.has(fid):
			outgoing[fid] = []
		(outgoing[fid] as Array).append(int(road["to"]))
	var prev: Dictionary = {}
	var queue: Array[int] = [from_id]
	var seen := {from_id: true}
	var head := 0
	var found := false
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for nxt: int in outgoing.get(current, []):
			var next_id := int(nxt)
			if seen.has(next_id):
				continue
			seen[next_id] = true
			prev[next_id] = current
			if next_id == to_id:
				found = true
				break
			queue.append(next_id)
		if found:
			break
	if not found:
		return path
	var walk := to_id
	while true:
		path.append(walk)
		if walk == from_id:
			break
		walk = int(prev[walk])
	path.reverse()
	return path


static func _parse_pois(root: Dictionary, result: Dictionary) -> void:
	if not root.has("pois"):
		return
	if typeof(root["pois"]) != TYPE_ARRAY:
		result.errors.append("Track `pois` must be an array.")
		return
	for raw: Variant in root["pois"]:
		if typeof(raw) != TYPE_DICTIONARY:
			result.errors.append("Each point of interest must be a JSON object.")
			continue
		var poi: Dictionary = raw
		var pid := str(poi.get("id", "")).strip_edges()
		if pid.is_empty():
			result.errors.append("Point of interest is missing `id`.")
			continue
		if result.pois.has(pid):
			result.errors.append("Duplicate point of interest `%s`." % pid)
			continue
		if not poi.has("at"):
			result.errors.append("Point of interest `%s` must name the street node it is attached to (`at`)." % pid)
			continue
		var at := int(poi["at"])
		if not result.nodes.has(at):
			result.errors.append("Point of interest `%s` is attached to unknown street node %d." % [pid, at])
			continue
		var street: Dictionary = result.nodes[at]
		var px := float(street["x"])
		var py := float(street["y"])
		if poi.has("x") or poi.has("y"):
			if not poi.has("x") or not poi.has("y"):
				result.errors.append("Point of interest `%s` needs both `x` and `y`, or neither." % pid)
				continue
			px = float(poi["x"])
			py = float(poi["y"])
		var named := str(poi.get("name", pid)).strip_edges()
		if named.is_empty():
			named = pid
		var parsed := {
			"id": pid,
			"name": named,
			"at": at,
			"x": px,
			"y": py,
			"z": _node_height(poi, at, result),
		}
		result.pois[pid] = parsed
		result.poi_order.append(pid)


static func _parse_buildings(root: Dictionary, result: Dictionary) -> void:
	if not root.has("buildings"):
		return
	if typeof(root["buildings"]) != TYPE_ARRAY:
		result.errors.append("Track `buildings` must be an array.")
		return
	var index := 0
	for raw: Variant in root["buildings"]:
		index += 1
		if typeof(raw) != TYPE_DICTIONARY:
			result.errors.append("Building %d must be a JSON object." % index)
			continue
		var building: Dictionary = raw
		if not building.has("x") or not building.has("y"):
			result.errors.append("Building %d must have numeric `x` and `y`." % index)
			continue
		var parsed := {
			"x": float(building["x"]),
			"y": float(building["y"]),
			"w": _building_size(building, "w", 10.0, index, result),
			"d": _building_size(building, "d", 8.0, index, result),
			"h": _building_size(building, "h", 6.0, index, result),
		}
		if building.has("color") and typeof(building["color"]) == TYPE_ARRAY:
			var rgb: Array = building["color"]
			if rgb.size() >= 3:
				parsed["color"] = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
		result.buildings.append(parsed)


static func _parse_scenery(root: Dictionary, result: Dictionary) -> void:
	if not root.has("scenery"):
		return
	if typeof(root["scenery"]) != TYPE_ARRAY:
		result.errors.append("Track `scenery` must be an array.")
		return
	var index := 0
	for raw: Variant in root["scenery"]:
		index += 1
		if typeof(raw) != TYPE_DICTIONARY:
			result.errors.append("Scenery %d must be a JSON object." % index)
			continue
		var item: Dictionary = raw
		if not item.has("x") or not item.has("y"):
			result.errors.append("Scenery %d must have numeric `x` and `y`." % index)
			continue
		var kind := str(item.get("kind", ""))
		if not SCENERY_KINDS.has(kind):
			result.warnings.append("Scenery %d has unknown kind `%s`; leaving it out." % [index, kind])
			continue
		result.scenery.append({ "kind": kind, "x": float(item["x"]), "y": float(item["y"]) })


static func _building_size(building: Dictionary, key: String, fallback: float, index: int, result: Dictionary) -> float:
	if not building.has(key):
		return fallback
	var value := float(building[key])
	if value <= 0.0:
		result.warnings.append("Building %d has non-positive `%s`; using %.1f." % [index, key, fallback])
		return fallback
	return value


static func find_road(result: Dictionary, from_id: int, to_id: int) -> Dictionary:
	for road: Dictionary in result.roads:
		if int(road["from"]) == from_id and int(road["to"]) == to_id:
			return road
	return {}
