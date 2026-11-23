extends SceneTree

## The track maker reads and writes every game track without changing it, keeps its editing
## rules, and switches the race to a test drive and back.

const _Doc := preload("res://scripts/track_maker_doc.gd")
const _TrackSides := preload("res://scripts/track_sides.gd")
const _RoadBank := preload("res://scripts/road_bank.gd")
const _TrackTerrain := preload("res://scripts/track_terrain.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_round_trips()
	_editing()
	_loops()
	_banking()
	_painted_ground()
	_test_drive_race_type()
	print("track_maker_test: ok")
	quit()


## Every game track reads and writes back to the same course. The baked Mulholland courses,
## already in the maker's layout, come back byte for byte.
func _round_trips() -> void:
	for file: String in DirAccess.get_files_at("res://assets/tracks"):
		if not file.ends_with(".trk"):
			continue
		var path := "res://assets/tracks/" + file
		var text := FileAccess.get_file_as_string(path)
		var read := _Doc.from_text(text, path)
		assert(read.doc != null, "%s: %s" % [file, str(read.errors)])
		var doc: _Doc = read.doc
		var out := doc.to_text()
		var before := TrackFile.parse_text(text, path)
		var after := TrackFile.parse_text(out, path)
		assert(after.errors.is_empty(), "%s: %s" % [file, str(after.errors)])
		assert(JSON.parse_string(text) == JSON.parse_string(out), "%s changed on a resave" % file)
		assert(before.path_ids == after.path_ids)
		assert(doc.check().errors.is_empty(), "%s: %s" % [file, str(doc.check().errors)])
		if file.begins_with("mulholland_"):
			assert(out == text, "%s is not byte for byte the same" % file)


func _editing() -> void:
	var doc := _Doc.blank()
	assert(doc.nodes.size() == 2 and doc.check().errors.is_empty())
	# The start doesn't move, and node 2 only slides along +Y.
	doc.move_node(0, Vector2(30, 30))
	assert(doc.node_point(0) == Vector2.ZERO)
	doc.move_node(1, Vector2(25, 150))
	assert(doc.node_point(1) == Vector2(0, 150))
	# A new node at the finish carries on the last road and height.
	doc.set_road_field(0, "type", TrackFile.ROAD_GRAVEL)
	doc.set_node_field(1, "z", 2.0)
	var added := doc.append_node(Vector2(-40, 260))
	assert(added == 2 and doc.roads.size() == 2)
	assert(str(doc.roads[1].get("type", "")) == TrackFile.ROAD_GRAVEL)
	assert(is_equal_approx(doc.node_height(2), 2.0))
	# Splitting a road puts the new node between its neighbors' heights.
	var split := doc.insert_node(1, Vector2(-20, 205))
	assert(split == 2 and doc.nodes.size() == 4 and doc.roads.size() == 3)
	assert(is_equal_approx(doc.node_height(2), 2.0))
	# Fields at their defaults are left out.
	doc.set_road_field(0, "type", TrackFile.ROAD_REGULAR)
	assert(not doc.roads[0].has("type"))
	doc.set_node_field(1, "z", 0.0)
	assert(not doc.nodes[1].has("z"))
	# Ids stay unique and the start and finish are typed on save.
	var parsed := TrackFile.parse_text(doc.to_text())
	assert(parsed.errors.is_empty(), str(parsed.errors))
	assert(parsed.path_ids.size() == 4)
	# The start can't go; a track keeps two nodes.
	assert(not doc.remove_node(0))
	assert(doc.remove_node(3) and doc.nodes.size() == 3 and doc.roads.size() == 2)
	assert(doc.remove_node(1) and doc.nodes.size() == 2)
	assert(not doc.remove_node(1))
	# Node 2 off the +Y axis is an error the maker shows.
	doc.nodes[1]["x"] = 5.0
	assert(not doc.check().errors.is_empty())
	# Undo copies don't share data.
	var copy := doc.copy()
	copy.nodes[1]["x"] = 0.0
	assert(is_equal_approx(float(doc.nodes[1]["x"]), 5.0))
	# Points from the map are 32-bit; the file gets them to the centimeter.
	doc.move_node(1, Vector2(0.0, 220.63))
	assert(doc.to_text().contains("\"y\": 220.63}") or doc.to_text().contains("\"y\": 220.63,"), doc.to_text())


## A loop goes round to the start, which is the finish, and comes back from its file the same.
func _loops() -> void:
	var doc := _Doc.blank()
	for point: Vector2 in [Vector2(-100, 260), Vector2(-160, 100), Vector2(-90, -70), Vector2(0, -60)]:
		doc.append_node(point)
	doc.set_loop(true)
	doc.laps = 3
	assert(doc.road_count() == doc.nodes.size())
	var parsed := TrackFile.parse_text(doc.to_text())
	assert(parsed.errors.is_empty(), str(parsed.errors))
	assert(parsed.loop and parsed.laps == 3)
	assert(parsed.path_ids.size() == doc.nodes.size() + 1 and parsed.path_ids[0] == parsed.path_ids[-1])
	assert(parsed.finish_ids.size() == 1 and parsed.finish_ids[0] == doc.node_id(doc.nodes.size() - 1), "no finish type on a loop")
	assert(doc.check().warnings.is_empty(), str(doc.check().warnings))
	var again: _Doc = _Doc.from_text(doc.to_text()).doc
	assert(again.loop and again.laps == 3 and again.nodes.size() == doc.nodes.size())
	assert(again.to_text() == doc.to_text())
	# The last node's road is the one back to the start.
	doc.set_road_field(doc.nodes.size() - 1, "type", TrackFile.ROAD_GRAVEL)
	assert(str(doc.loop_road.get("type", "")) == TrackFile.ROAD_GRAVEL)
	# Splitting it adds a last node between the old last and the start.
	var count := doc.nodes.size()
	assert(doc.insert_node(doc.road_count() - 1, Vector2(0, -30)) == count)
	assert(doc.node_point(count) == Vector2(0, -30) and doc.road_count() == count + 1)
	# Coming into the start at an angle is fine: the race turns it onto the start straight behind
	# the line, so the lap's two ends meet in one place heading the same way.
	doc.move_node(count, Vector2(40, -30))
	assert(doc.check().warnings.is_empty(), str(doc.check().warnings))
	var trk := OS.get_temp_dir().path_join("track_maker_test_loop.trk")
	var out := FileAccess.open(trk, FileAccess.WRITE)
	out.store_string(doc.to_text())
	out.close()
	var track: Node3D = load("res://scripts/race_track.gd").new()
	track.set(&"track_path", trk)
	track.call(&"_build_path")
	DirAccess.remove_absolute(trk)
	var pts: PackedVector3Array = track.get(&"_pts")
	var yaws: PackedFloat32Array = track.get(&"_yaws")
	assert(pts.size() > 10)
	assert(pts[0].is_zero_approx() and is_zero_approx(yaws[0]), "the cars still start at 0, 0 facing +Y")
	assert(pts[-1] == pts[0] and yaws[-1] == yaws[0], "the lap ends where it began")
	# Two samples back, the road already runs straight up the start straight.
	assert(absf(pts[-3].x) < 0.01 and absf(yaws[-3]) < 0.01, str(pts[-3], " ", yaws[-3]))
	for k in range(1, pts.size()):
		assert(absf(angle_difference(yaws[k - 1], yaws[k])) < deg_to_rad(20.0), "no kink at sample %d" % k)
	track.free()
	# A loop needs three nodes.
	var short := _Doc.blank()
	short.set_loop(true)
	assert(not short.check().errors.is_empty())
	# Far ground on a loop follows heights averaged round past the start, so it matches at the line.
	var ring := PackedVector3Array()
	for k in 401:
		ring.append(Vector3(0.0, 4.0 if k < 100 else 0.0, float(k)))
	ring[400] = ring[0]
	var far := _TrackSides.slow_heights(ring, true)
	assert(is_equal_approx(far[0], far[far.size() - 1]))
	assert(far[399] > 0.5, "the average before the line takes in the rise after it")
	# Unticking drops the road back.
	doc.set_loop(false)
	assert(doc.loop_road.is_empty() and TrackFile.parse_text(doc.to_text()).errors.is_empty())


## A node's bank is read, held to its limit, written back, explained in the panel, and built into
## the road a car drives on.
func _banking() -> void:
	var doc := _Doc.blank()
	for point: Vector2 in [Vector2(-200, 200), Vector2(-200, -150), Vector2(0, -150)]:
		doc.append_node(point)
	doc.set_loop(true)
	# Node 2 turns right, toward -X: its left edge up leans into the bend.
	doc.set_node_field(1, "bank", 25.0)
	doc.set_node_field(2, "bank", -10.0)
	assert(doc.bank_note(1).contains("into this right-hand bend"), doc.bank_note(1))
	assert(doc.bank_note(2).contains("off-camber"), doc.bank_note(2))
	assert(doc.bank_note(0) == "Flat across.")
	assert(doc.check().warnings.is_empty(), str(doc.check().warnings))
	var text := doc.to_text()
	var parsed := TrackFile.parse_text(text)
	assert(parsed.errors.is_empty(), str(parsed.errors))
	assert(is_equal_approx(float(parsed.nodes[doc.node_id(1)]["bank"]), 25.0))
	assert(is_equal_approx(float(parsed.nodes[doc.node_id(0)]["bank"]), 0.0))
	assert(_Doc.from_text(text).doc.to_text() == text)
	var steep := TrackFile.parse_text(text.replace("\"bank\": 25", "\"bank\": 60"))
	assert(is_equal_approx(float(steep.nodes[doc.node_id(1)]["bank"]), TrackFile.BANK_MAX_DEG))
	assert(not steep.warnings.is_empty())
	# Every style banks.
	doc.style = TrackFile.STYLE_STREET
	assert(doc.check().warnings.is_empty(), str(doc.check().warnings))
	doc.style = TrackFile.STYLE_CIRCUIT
	# The road: the low edge at the node's height, the other edge up, and the start flat.
	var trk := OS.get_temp_dir().path_join("track_maker_test_bank.trk")
	var out := FileAccess.open(trk, FileAccess.WRITE)
	out.store_string(text)
	out.close()
	var track: Node3D = load("res://scripts/race_track.gd").new()
	track.set(&"track_path", trk)
	track.call(&"_build_path")
	DirAccess.remove_absolute(trk)
	var corner: Dictionary = track.call(&"closest_sample", Vector3(0.0, 0.0, 200.0))
	var middle: Vector3 = corner["position"]
	var right: Vector3 = corner["right"]
	var rise := tan(deg_to_rad(25.0))
	assert(is_equal_approx(float(corner["bank"]), rise), str(corner["bank"]))
	var half := TrackFile.DEFAULT_WIDTH * 0.5
	var low: float = track.call(&"surface_height", middle - right * (half - 0.5))
	var high: float = track.call(&"surface_height", middle + right * (half - 0.5))
	assert(absf(low - 0.5 * rise) < 0.05, str(low))
	assert(absf(high - (2.0 * half - 0.5) * rise) < 0.05, str(high))
	var slope: float = track.call(&"bank_slope", middle, float(corner["yaw"]))
	assert(absf(slope - rise) < 0.01, str(slope))
	# The bank eases in from the start line, so a meter on it has hardly begun.
	assert(absf(float(track.call(&"surface_height", Vector3(2.0, 0.0, 1.0)))) < 0.01, "the start is flat")
	assert(absf(float(track.call(&"bank_slope", Vector3(0.0, 0.0, 1.0), 0.0))) < 0.001)
	track.free()
	# Every style banks the road the same, and the slope a car feels goes with it.
	for style: String in [TrackFile.STYLE_STREET, TrackFile.STYLE_MOUNTAIN, TrackFile.STYLE_AQUEDUCT]:
		doc.style = style
		var styled := OS.get_temp_dir().path_join("track_maker_test_bank_%s.trk" % style)
		var file := FileAccess.open(styled, FileAccess.WRITE)
		file.store_string(doc.to_text())
		file.close()
		var other: Node3D = load("res://scripts/race_track.gd").new()
		other.set(&"track_path", styled)
		other.call(&"_build_path")
		DirAccess.remove_absolute(styled)
		var at: Dictionary = other.call(&"closest_sample", Vector3(0.0, 0.0, 200.0))
		var mid: Vector3 = at["position"]
		var across: Vector3 = at["right"]
		assert(is_equal_approx(float(at["bank"]), rise), "%s: %s" % [style, at["bank"]])
		var tilt := float(other.call(&"surface_height", mid + across) - other.call(&"surface_height", mid - across)) * 0.5
		assert(absf(tilt - rise) < 0.01, "%s tilts %s" % [style, tilt])
		var felt: float = other.call(&"bank_slope", mid, float(at["yaw"]))
		assert(absf(felt - rise) < 0.01, "%s feels %s" % [style, felt])
		other.free()
	doc.style = TrackFile.STYLE_CIRCUIT
	# Auto bank leans every corner into its turn by how tight it is, over the nodes' own banks,
	# and the race builds the same.
	doc.auto_bank = true
	assert(is_equal_approx(doc.bank_at(1), TrackFile.AUTO_BANK_MAX_DEG), str(doc.bank_at(1)))
	assert(doc.bank_at(3) > 0.0, "node 4 turns right too, where node 3's own bank was against it")
	assert(is_zero_approx(doc.bank_at(0)), "the start is on a straight")
	assert(doc.bank_note(3).contains("into this"), doc.bank_note(3))
	var auto_text := doc.to_text()
	assert(auto_text.contains("\"auto_bank\": true"))
	assert(_Doc.from_text(auto_text).doc.auto_bank)
	var gentle := TrackFile.auto_bank_deg(Vector2(0, 0), Vector2(0, 200), Vector2(-70, 400))
	assert(gentle > 5.0 and gentle < 20.0, str(gentle))
	assert(TrackFile.auto_bank_deg(Vector2(0, 0), Vector2(0, 200), Vector2(70, 400)) < 0.0, "a left bend leans left")
	var auto_trk := OS.get_temp_dir().path_join("track_maker_test_auto_bank.trk")
	var auto_file := FileAccess.open(auto_trk, FileAccess.WRITE)
	auto_file.store_string(auto_text)
	auto_file.close()
	var auto_track: Node3D = load("res://scripts/race_track.gd").new()
	auto_track.set(&"track_path", auto_trk)
	auto_track.call(&"_build_path")
	DirAccess.remove_absolute(auto_trk)
	var auto_corner: Dictionary = auto_track.call(&"closest_sample", Vector3(0.0, 0.0, 200.0))
	assert(is_equal_approx(float(auto_corner["bank"]), tan(deg_to_rad(TrackFile.AUTO_BANK_MAX_DEG))), str(auto_corner["bank"]))
	auto_track.free()
	doc.auto_bank = false
	assert(is_equal_approx(doc.bank_at(2), -10.0), "unticking brings the node's own bank back")
	# On the bank the tires hold more turning toward its low side, and the pull fades out at a stop.
	assert(_RoadBank.load(rise, -10.0) > 1.0 and _RoadBank.load(rise, 10.0) < 1.0)
	assert(is_equal_approx(_RoadBank.load(0.0, 10.0), 1.0))
	assert(is_equal_approx(_RoadBank.pull(rise, 30.0), -_RoadBank.GRAVITY * rise))
	assert(is_zero_approx(_RoadBank.pull(rise, 0.0)))


## Painting the ground: the brushes, the file, and the road following it.
func _painted_ground() -> void:
	var doc := _Doc.blank()
	assert(doc.terrain.is_empty() and not doc.to_text().contains("terrain"))
	var base := doc.ground_base
	# A dab of Raise lifts the middle most, and starts from the road's height.
	doc.set_node_field(1, "z", 2.0)
	assert(doc.terrain.paint(_TrackTerrain.Brush.RAISE, Vector2(40, 100), 20.0, 1.0, 1.0, 0.0, base))
	var middle := doc.terrain.sample(Vector2(40, 100))
	var rim := doc.terrain.sample(Vector2(40, 116))
	assert(middle.y == 1.0 and middle.x > rim.x and rim.x > 1.0)
	assert(absf(middle.x - (doc.ground_base(Vector2(40, 100)) + _TrackTerrain.RAISE_MPS)) < 0.01)
	# Off the paint there is none, and the chunks round a painted point are kept.
	assert(doc.terrain.sample(Vector2(400, 400)).y == 0.0)
	# Flatten goes to its height; Smooth leaves unpainted ground alone.
	doc.terrain.paint(_TrackTerrain.Brush.FLATTEN, Vector2(40, 100), 8.0, 1.0, 10.0, -3.0, base)
	assert(absf(doc.terrain.sample(Vector2(40, 100)).x + 3.0) < 0.01)
	assert(not doc.terrain.paint(_TrackTerrain.Brush.SMOOTH, Vector2(300, 300), 20.0, 1.0, 1.0, 0.0, base))
	# Painting across a chunk's low edge keeps the chunk below too, so the area's rim is unpainted.
	doc.terrain.set_height(_TrackTerrain.CHUNK, _TrackTerrain.CHUNK, 5.0)
	assert(doc.terrain.chunks.has(Vector2i(0, 0)) and doc.terrain.chunks.has(Vector2i(1, 1)))
	# The file keeps it to the centimeter, and a resave is the same text.
	var text := doc.to_text()
	var back: _Doc = _Doc.from_text(text, "paint").doc
	assert(back != null and back.to_text() == text)
	for key: Vector2i in doc.terrain.chunks:
		var a: PackedFloat32Array = doc.terrain.chunks[key]
		var b: PackedFloat32Array = back.terrain.chunks[key]
		for k in a.size():
			assert(is_nan(a[k]) == is_nan(b[k]))
			assert(is_nan(a[k]) or absf(a[k] - b[k]) <= 0.005)
	# An undo copy doesn't change with the doc.
	var before := doc.copy()
	doc.terrain.paint(_TrackTerrain.Brush.LOWER, Vector2(40, 100), 20.0, 1.0, 1.0, 0.0, base)
	assert(before.terrain.sample(Vector2(40, 100)).x > doc.terrain.sample(Vector2(40, 100)).x + 1.0)
	# The road follows painted ground at its nodes.
	doc.terrain.paint(_TrackTerrain.Brush.FLATTEN, Vector2(0, 200), 30.0, 1.0, 10.0, 7.5, base)
	assert(doc.road_follows_ground() == 1 and doc.node_height(1) == 7.5)
	# Erase takes it all away, chunks too.
	doc.terrain.paint(_TrackTerrain.Brush.ERASE, Vector2(60, 140), 400.0, 1.0, 1.0, 0.0, base)
	assert(doc.terrain.is_empty())
	# A bad chunk is an error, not a crash.
	var bad := TrackFile.parse_text('{"name": "x", "nodes": [{"id": 1, "x": 0, "y": 0}, {"id": 2, "x": 0, "y": 100}], "roads": [{"from": 1, "to": 2}], "terrain": [{"x": 0, "y": 0, "h": "nonsense"}]}')
	assert(not bad.errors.is_empty())


func _test_drive_race_type() -> void:
	var state := root.get_node("GameState")
	state.set("selected_race_type", state.get("RACE_STUNT"))
	state.call("begin_test_drive", "user://somewhere.trk")
	assert(state.call("is_test_drive"))
	assert(state.call("race_on_track"))
	assert(state.call("race_track_path") == "user://somewhere.trk")
	state.call("end_test_drive")
	assert(not state.call("is_test_drive"))
	assert(state.get("selected_race_type") == state.get("RACE_STUNT"))
	assert(state.get("test_track_path") == "")
