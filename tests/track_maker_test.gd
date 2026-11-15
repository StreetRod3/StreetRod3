extends SceneTree

## The track maker reads and writes every game track without changing it, keeps its editing
## rules, and switches the race to a test drive and back.

const _Doc := preload("res://scripts/track_maker_doc.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_round_trips()
	_editing()
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
