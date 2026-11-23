extends SceneTree

## The police station stands across the drive-in's road, facing it, with its lot
## stopping at the curb.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var track: Dictionary = TrackFile.load_path("res://assets/maps/city.trk")
	assert(track["errors"].is_empty(), "The city map loads")
	var block := _police_block(track)
	assert(not block.is_empty(), "The city has one police station")
	var cruise := (load("res://scripts/cruise.gd") as Script).new() as Node3D
	cruise.call("_road_meshes", track)
	var diner := Node3D.new()
	var join := TrackFile.world_position(track["nodes"][int(track["pois"]["drive-in"]["at"])])
	var stop := TrackFile.world_position(track["pois"]["drive-in"])
	var away := stop - join
	away.y = 0.0
	away = away.normalized()
	cruise.call("_place_alongside", diner, stop, away)
	cruise.call("_build_blocks", track)
	var station := cruise.get_node("PoliceStation") as Node3D
	var half := _driveway_half(cruise, stop)
	assert(half > 0.0, "The drive-in has a road in front of it")
	var south_curb := stop.z - half
	var north_curb := stop.z + half
	var half_d := float(block["d"]) * 0.5
	var half_w := float(block["w"]) * 0.5
	var station_front := station.position.z + half_d
	assert(diner.position.z > north_curb, "The drive-in stands on the north side of its road")
	assert(station_front < south_curb, "The police station stands on the south side of that road")
	assert(absf(station.position.x - diner.position.x) < 2.0, "The station lines up with the drive-in")
	for side_x: float in [-1.0, 1.0]:
		for side_z: float in [-1.0, 1.0]:
			var corner := Vector2(station.position.x + side_x * half_w, station.position.z + side_z * half_d)
			assert(not cruise.call("_on_pavement", corner, 0.5), "The station sits off the street")
	var found := false
	for apron: Dictionary in cruise.get("_aprons"):
		if apron["root"] != station:
			continue
		found = true
		var middle: Vector3 = apron["middle"]
		var apron_half: Vector3 = apron["half"]
		var north := station.position.z + middle.z + apron_half.z
		assert(north <= south_curb + 0.05, "The station lot stops at the curb")
		assert(north > station_front - 0.05, "The lot is in front of the station")
	assert(found, "The station has a lot in front")
	var labels := station.find_children("*", "Label3D", true, false)
	assert(labels.size() == 1, "The station has its sign")
	var words := labels[0] as Label3D
	assert(words.text == "POLICE", "The sign reads POLICE")
	assert(words.position.z > 0.0, "The sign is on the side facing the drive-in")
	print("city police station: OK")
	diner.free()
	cruise.free()
	quit(0)


func _police_block(track: Dictionary) -> Dictionary:
	var found := {}
	for raw: Dictionary in track["buildings"]:
		if str(raw.get("sign", "")) != "POLICE":
			continue
		assert(found.is_empty(), "The city has one police station")
		found = raw
	return found


func _driveway_half(cruise: Node3D, stop: Vector3) -> float:
	for segment: Dictionary in cruise.get("_streets"):
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		if a.distance_to(stop) < 0.2 or b.distance_to(stop) < 0.2:
			return float(segment["half"])
	return -1.0
