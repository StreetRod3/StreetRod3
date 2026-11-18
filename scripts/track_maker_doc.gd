extends RefCounted

## The track maker's course: one chain of nodes from the start to the finish, the road leaving
## each node, and the scenery. It reads and writes `.trk` files (see `docs/track-format.md`).
## A file is read along its race path; fields the maker does not edit, such as `pois`,
## `left_out`, or a node's own id, are kept and written back, so saving a game track changes
## only what was edited.
##
## Every race starts at 0, 0 heading +Y, where the race scene puts the cars, so the start node
## stays there and the second node stays on the +Y axis.

const _Self := preload("res://scripts/track_maker_doc.gd")

const DEFAULT_NAME := "New track"
## Root fields the maker edits itself. Anything else in a file rides along untouched.
const _OWN_ROOT_KEYS := ["name", "style", "jumps", "loop", "laps", "sky", "nodes", "roads", "scenery"]
const MAX_LAPS := 99
## Fields in meters, written with a decimal point even when whole.
const _METRIC_KEYS := ["x", "y", "z", "width", "left", "right", "to", "w", "d", "h"]
## What a new node takes from the one before it.
const _CARRIED_NODE_KEYS := ["left", "right", "rail"]

var name: String = DEFAULT_NAME
var style: String = TrackFile.STYLE_CIRCUIT
var jumps: bool = false
## In race order. Each holds its file fields: id, x, y, and z, sharp, bank, left, right, rail when set.
var nodes: Array[Dictionary] = []
## `roads[i]` runs from `nodes[i]` to `nodes[i + 1]`: width, type, surface when set.
var roads: Array[Dictionary] = []
## The road from the last node back to the start. On a loop it is the lap's last road. Off a
## loop it is kept only so a file that had one stays as it was; the race doesn't follow it.
## Empty when there is none.
var loop_road: Dictionary = {}
## The course comes back round to the start, which is also the finish, and is raced `laps` times.
var loop: bool = false
var laps: int = 1
## The sky over the course, an id in skies.gd.
var sky: String = "day"
var scenery: Array[Dictionary] = []
## Root fields the maker does not edit, kept in file order.
var extra: Dictionary = {}


## A short straight from the start, ready to draw on.
static func blank() -> _Self:
	var doc := _Self.new()
	doc.nodes = [{"id": 1, "x": 0.0, "y": 0.0}, {"id": 2, "x": 0.0, "y": 200.0}]
	doc.roads = [{}]
	return doc


func copy() -> _Self:
	var doc := _Self.new()
	doc.name = name
	doc.style = style
	doc.jumps = jumps
	doc.loop = loop
	doc.laps = laps
	doc.sky = sky
	doc.nodes = _copy_list(nodes)
	doc.roads = _copy_list(roads)
	doc.loop_road = loop_road.duplicate(true)
	doc.scenery = _copy_list(scenery)
	doc.extra = extra.duplicate(true)
	return doc


static func _copy_list(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in list:
		out.append(item.duplicate(true))
	return out


# --- Reading -----------------------------------------------------------------------------


## Reads a `.trk` file's text. Returns `doc` (null when it can't be read), `errors`, and
## `warnings`.
static func from_text(text: String, source: String = "") -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var out := {"doc": null, "errors": errors, "warnings": warnings}
	var parsed := TrackFile.parse_text(text, source)
	for err: String in parsed.errors:
		errors.append(err)
	if not errors.is_empty():
		return out
	var raw: Variant = JSON.parse_string(text)
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("Track root must be a JSON object.")
		return out
	var root: Dictionary = raw
	var raw_nodes: Dictionary = {}
	for item: Variant in root.get("nodes", []):
		if typeof(item) == TYPE_DICTIONARY:
			raw_nodes[int((item as Dictionary).get("id", 0))] = item
	var raw_roads: Array[Dictionary] = []
	for item: Variant in root.get("roads", []):
		if typeof(item) == TYPE_DICTIONARY:
			raw_roads.append(item as Dictionary)

	var doc := _Self.new()
	doc.name = str(root.get("name", ""))
	doc.style = str(parsed.style)
	doc.jumps = bool(parsed.jumps)
	doc.loop = bool(parsed.loop)
	doc.laps = int(parsed.laps)
	doc.sky = str(parsed.sky)
	var path_ids: Array = parsed.path_ids.duplicate()
	if doc.loop:
		# A loop's path ends on the start again; the road there is the closing road.
		path_ids.pop_back()
	var chain: Array[Dictionary] = []
	for id: Variant in path_ids:
		var node: Dictionary = (raw_nodes[int(id)] as Dictionary).duplicate(true)
		# `type` stays only to keep its place in the line; saving writes it from the node's place.
		node["id"] = int(id)
		node["x"] = float(node.get("x", 0.0))
		node["y"] = float(node.get("y", 0.0))
		chain.append(node)
	doc.nodes = chain
	var links: Array[Dictionary] = []
	for i in range(path_ids.size() - 1):
		var road := _raw_road(raw_roads, int(path_ids[i]), int(path_ids[i + 1])).duplicate(true)
		road.erase("from")
		road.erase("to")
		links.append(road)
	doc.roads = links
	var first := int(path_ids[0])
	var last := int(path_ids[path_ids.size() - 1])
	var closing := _raw_road(raw_roads, last, first)
	var used_roads := links.size()
	if not closing.is_empty():
		doc.loop_road = closing.duplicate(true)
		doc.loop_road.erase("from")
		doc.loop_road.erase("to")
		used_roads += 1
	var sights: Array[Dictionary] = []
	for item: Variant in root.get("scenery", []):
		if typeof(item) == TYPE_DICTIONARY:
			sights.append((item as Dictionary).duplicate(true))
	doc.scenery = sights
	var kept: Dictionary = {}
	for key: Variant in root.keys():
		if not _OWN_ROOT_KEYS.has(str(key)):
			kept[key] = root[key]
	doc.extra = kept.duplicate(true)

	if raw_nodes.size() > chain.size():
		warnings.append("%d nodes off the race path were left out." % (raw_nodes.size() - chain.size()))
	if raw_roads.size() > used_roads:
		warnings.append("%d roads off the race path were left out." % (raw_roads.size() - used_roads))
	for warning: String in parsed.warnings:
		warnings.append(warning)
	out.doc = doc
	return out


static func _raw_road(roads_in: Array[Dictionary], from_id: int, to_id: int) -> Dictionary:
	for road: Dictionary in roads_in:
		if int(road.get("from", -1)) == from_id and int(road.get("to", -1)) == to_id:
			return road
	return {}


# --- Writing -----------------------------------------------------------------------------


## The file's text, laid out as the bake tools write it: one line for each node, road, and
## piece of scenery.
func to_text() -> String:
	var root := {"name": name}
	if style != TrackFile.STYLE_CIRCUIT:
		root["style"] = style
	if jumps:
		root["jumps"] = true
	if loop:
		root["loop"] = true
		root["laps"] = laps
	if sky != "day":
		root["sky"] = sky
	var out_nodes: Array[Dictionary] = []
	for i in nodes.size():
		out_nodes.append(_node_for_file(i))
	root["nodes"] = out_nodes
	var out_roads: Array[Dictionary] = []
	for i in roads.size():
		out_roads.append(_road_for_file(roads[i], node_id(i), node_id(i + 1)))
	if (loop or not loop_road.is_empty()) and nodes.size() > 2:
		out_roads.append(_road_for_file(loop_road, node_id(nodes.size() - 1), node_id(0)))
	root["roads"] = out_roads
	for key: Variant in extra.keys():
		root[key] = extra[key]
	if not scenery.is_empty():
		root["scenery"] = scenery
	var entries: PackedStringArray = []
	for key: Variant in root.keys():
		entries.append("  %s: %s" % [JSON.stringify(str(key)), _block_text(root[key])])
	return "{\n%s\n}\n" % ",\n".join(entries)


## A node as the file has it, its fields in their own order. `type` is written for the start
## and the finish only, where the node had it or else at the end.
func _node_for_file(i: int) -> Dictionary:
	var role := ""
	if i == 0:
		role = TrackFile.NODE_START
	elif i == nodes.size() - 1 and not loop:
		role = TrackFile.NODE_FINISH
	var row := {}
	for key: Variant in nodes[i].keys():
		if str(key) == "type":
			if not role.is_empty():
				row["type"] = role
		else:
			row[key] = nodes[i][key]
	row["id"] = node_id(i)
	if not role.is_empty() and not row.has("type"):
		row["type"] = role
	return row


func _road_for_file(road: Dictionary, from_id: int, to_id: int) -> Dictionary:
	var row := {"from": from_id, "to": to_id}
	for key: Variant in road.keys():
		row[key] = road[key]
	return row


## A root value: a list of objects goes one to a line, anything else on one line.
static func _block_text(value: Variant) -> String:
	if typeof(value) == TYPE_ARRAY and not (value as Array).is_empty():
		var lines: PackedStringArray = []
		for item: Variant in value as Array:
			if typeof(item) != TYPE_DICTIONARY:
				return value_text(value)
			lines.append("    " + value_text(item))
		return "[\n%s\n  ]" % ",\n".join(lines)
	return value_text(value)


## One value as JSON on one line, with a space after each colon and comma. Measurements in
## meters keep a decimal point (`8.0`), as the bake tools write them; ids and other whole
## numbers are written whole.
static func value_text(value: Variant, key: String = "") -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var parts: PackedStringArray = []
			var dict: Dictionary = value
			for k: Variant in dict.keys():
				parts.append("%s: %s" % [JSON.stringify(str(k)), value_text(dict[k], str(k))])
			return "{%s}" % ", ".join(parts)
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for item: Variant in value as Array:
				parts.append(value_text(item, key))
			return "[%s]" % ", ".join(parts)
		TYPE_FLOAT:
			var number := float(value)
			if number == roundf(number) and absf(number) < 1.0e15:
				return ("%d.0" if _METRIC_KEYS.has(key) else "%d") % int(number)
			return JSON.stringify(number, "", false, true)
	return JSON.stringify(value)


func node_id(i: int) -> int:
	return int(nodes[i].get("id", i + 1))


func _next_id() -> int:
	var top := 0
	for node: Dictionary in nodes:
		top = maxi(top, int(node.get("id", 0)))
	return top + 1


# --- Editing -----------------------------------------------------------------------------


## `value` to the centimeter, as a 64-bit number. Points come from the map as 32-bit floats, which
## would otherwise go into the file as -50.400001525878906.
static func cm(value: float) -> float:
	return roundf(value * 100.0) / 100.0


func node_point(i: int) -> Vector2:
	return Vector2(float(nodes[i].get("x", 0.0)), float(nodes[i].get("y", 0.0)))


func node_height(i: int) -> float:
	return float(nodes[i].get("z", 0.0))


## How the course turns at node `i`, as the sine of the angle: above 0 to the driver's right,
## below 0 to the left, 0 on a straight and at the ends of a course that isn't a loop.
func turn_at(i: int) -> float:
	var last := nodes.size() - 1
	var before := i - 1
	var after := i + 1
	if loop and last >= 2:
		before = posmod(i - 1, last + 1)
		after = posmod(i + 1, last + 1)
	if before < 0 or after > last:
		return 0.0
	var into := node_point(i) - node_point(before)
	var out := node_point(after) - node_point(i)
	if into.is_zero_approx() or out.is_zero_approx():
		return 0.0
	# The map's +Y is ahead and -X the driver's right, so a right turn crosses positive.
	return into.normalized().cross(out.normalized())


## What node `i`'s bank does, for the panel: which edge is up and whether that leans into the bend.
func bank_note(i: int) -> String:
	var bank := float(nodes[i].get("bank", 0.0))
	if is_zero_approx(bank):
		return "Flat across."
	var edge := "Left edge up" if bank > 0.0 else "Right edge up"
	var turn := turn_at(i)
	if absf(turn) < 0.02:
		return "%s, on a straight." % edge
	var bend := "right-hand" if turn > 0.0 else "left-hand"
	if (bank > 0.0) == (turn > 0.0):
		return "%s: leans into this %s bend." % [edge, bend]
	return "%s: leans out of this %s bend (off-camber)." % [edge, bend]


## Moves node `i`, held to where the race scene needs the start: the start stays at 0, 0
## and the second node on the +Y axis ahead of it.
func move_node(i: int, point: Vector2) -> void:
	if i == 0:
		return
	if i == 1:
		point = Vector2(0.0, maxf(point.y, 1.0))
	nodes[i]["x"] = cm(point.x)
	nodes[i]["y"] = cm(point.y)


## Sets a node field, leaving it out of the node when it is at its default.
func set_node_field(i: int, key: String, value: Variant) -> void:
	var is_default := false
	match typeof(value):
		TYPE_BOOL:
			is_default = not bool(value)
		TYPE_FLOAT, TYPE_INT:
			is_default = is_zero_approx(float(value))
	if is_default:
		nodes[i].erase(key)
	else:
		nodes[i][key] = value


## Roads on the course: one between each pair of nodes, and on a loop the one back to the start.
func road_count() -> int:
	return roads.size() + (1 if loop and nodes.size() > 2 else 0)


## The road leaving node `i`: on a loop the last node's is the road back to the start. Empty
## when there is none. Changing it changes the course.
func road_from(i: int) -> Dictionary:
	if i >= 0 and i < roads.size():
		return roads[i]
	if loop and i == nodes.size() - 1 and nodes.size() > 2:
		return loop_road
	return {}


## The node road `i` leads to.
func road_end(i: int) -> int:
	return (i + 1) % nodes.size()


## Makes the course a loop, or not. A new loop's road back to the start copies the last road;
## a course that stops being a loop loses that road.
func set_loop(on: bool) -> void:
	loop = on
	if on:
		if loop_road.is_empty() and not roads.is_empty():
			loop_road = roads[roads.size() - 1].duplicate(true)
	else:
		loop_road = {}


## Sets a field of the road leaving node `i`, leaving it out when it is at its default.
func set_road_field(i: int, key: String, value: Variant) -> void:
	if i < 0 or i >= road_count():
		return
	var road := road_from(i)
	var is_default := false
	match key:
		"width":
			is_default = is_equal_approx(float(value), TrackFile.DEFAULT_WIDTH)
		"type":
			is_default = str(value) == TrackFile.ROAD_REGULAR
		"surface":
			is_default = str(value) == TrackFile.SURFACE_REGULAR
	if is_default:
		road.erase(key)
	else:
		road[key] = value


## Adds a node at the finish end. The new road copies the last one, so a narrow or gravel
## stretch carries on. Returns the new node's index.
func append_node(point: Vector2) -> int:
	var last := nodes.size() - 1
	var node := _carried_from(last)
	node["x"] = cm(point.x)
	node["y"] = cm(point.y)
	if not is_zero_approx(node_height(last)):
		node["z"] = node_height(last)
	nodes.append(node)
	roads.append(roads[roads.size() - 1].duplicate(true) if not roads.is_empty() else {})
	if nodes.size() == 2:
		move_node(1, point)
	return nodes.size() - 1


## Splits road `road_index` at `point`. The two halves are the same kind of road, and the new
## node's height is between its neighbors'. Returns the new node's index.
func insert_node(road_index: int, point: Vector2) -> int:
	if road_index >= roads.size():
		return _split_loop_road(point)
	var a := road_index
	var b := road_index + 1
	var node := _carried_from(a)
	node["x"] = cm(point.x)
	node["y"] = cm(point.y)
	var span := node_point(a).distance_to(node_point(b))
	var t := 0.5 if span < 0.001 else clampf(node_point(a).distance_to(point) / span, 0.0, 1.0)
	var z := lerpf(node_height(a), node_height(b), t)
	if not is_zero_approx(z):
		node["z"] = cm(z)
	nodes.insert(b, node)
	roads.insert(b, roads[a].duplicate(true))
	if b == 1:
		move_node(1, point)
	return b


## A new last node on the road back to the start, between the old last node and the start.
func _split_loop_road(point: Vector2) -> int:
	var last := nodes.size() - 1
	var node := _carried_from(last)
	node["x"] = cm(point.x)
	node["y"] = cm(point.y)
	var span := node_point(last).distance_to(node_point(0))
	var t := 0.5 if span < 0.001 else clampf(node_point(last).distance_to(point) / span, 0.0, 1.0)
	var z := lerpf(node_height(last), node_height(0), t)
	if not is_zero_approx(z):
		node["z"] = cm(z)
	nodes.append(node)
	roads.append(loop_road.duplicate(true))
	return nodes.size() - 1


func _carried_from(i: int) -> Dictionary:
	var node := {"id": _next_id()}
	for key: String in _CARRIED_NODE_KEYS:
		if nodes[i].has(key):
			node[key] = nodes[i][key]
	return node


## Takes out node `i`. The road into it now runs on to the node after. The start can't go,
## and a track keeps at least two nodes. Returns false when nothing was removed.
func remove_node(i: int) -> bool:
	if i <= 0 or i >= nodes.size() or nodes.size() <= 2:
		return false
	nodes.remove_at(i)
	# The road into node `i` (roads[i - 1]) is kept; the one out of it goes.
	roads.remove_at(mini(i, roads.size() - 1))
	return true


## Straight-line length from the start to the finish, or once round a loop. The game rounds
## the corners, so the race is a little shorter.
func path_length() -> float:
	var total := 0.0
	for i in range(1, nodes.size()):
		total += node_point(i - 1).distance_to(node_point(i))
	if loop and nodes.size() > 2:
		total += node_point(nodes.size() - 1).distance_to(node_point(0))
	return total


## What the game's loader makes of the course, plus the maker's own rules. Returns `errors`
## and `warnings`; with errors the game can't race it.
func check() -> Dictionary:
	var parsed := TrackFile.parse_text(to_text(), name)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	for err: String in parsed.errors:
		errors.append(err)
	for warning: String in parsed.warnings:
		warnings.append(warning)
	if nodes.size() >= 2:
		if not node_point(0).is_zero_approx():
			errors.append("The start must be at 0, 0, where the race puts the cars.")
		var second := node_point(1)
		if not is_zero_approx(second.x) or second.y <= 0.0:
			errors.append("The first road must run straight ahead (+Y) from the start. Drag node 2 to fix it.")
	if not scenery.is_empty() and style == TrackFile.STYLE_CIRCUIT:
		warnings.append("A circuit track doesn't show scenery. Pick another style to see it.")
	return {"errors": errors, "warnings": warnings}
