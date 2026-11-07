extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	var save_dir := "user://royal-rods-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.set("save_dir", save_dir)
	state.set("legacy_save_path", "")
	var track: Dictionary = TrackFile.load_path("res://assets/maps/city.trk")
	assert(track["errors"].is_empty())
	assert(TrackFile.cruise_route(track, "garage", "royal-rods").size() >= 2)
	assert(TrackFile.cruise_route(track, "royal-rods", "garage").size() >= 2)

	var garage := (load("res://scenes/garage.tscn") as PackedScene).instantiate()
	assert(garage.call("_scene_for_poi", "royal-rods") == state.SCENE_ROYAL_RODS)
	assert(garage.call("_poi_for_scene", state.SCENE_ROYAL_RODS) == "royal-rods")
	garage.free()
	var cruise := (load("res://scenes/cruise.tscn") as PackedScene).instantiate()
	assert(cruise.call("_scene_for_roam", "royal-rods") == state.SCENE_ROYAL_RODS)
	cruise.free()

	var store := (load("res://scenes/royal_rods.tscn") as PackedScene).instantiate()
	root.add_child(store)
	current_scene = store
	await process_frame
	assert(state.current_scene_path == state.SCENE_ROYAL_RODS)
	store.call("_open_catalog")
	var catalog := store.get("_catalog") as Control
	assert(catalog.visible)
	assert(store.get("_catalog_list").get_child_count() > 4)
	store.call("_close_catalog")
	assert(not catalog.visible)

	state.roll_newspaper_wear()
	state.money = 100000
	var categories: Array = [
		["engine", state.ENGINES],
		["transmission", state.GEARBOXES],
		["wheels", state.WHEELS],
		["part", state.PARTS],
	]
	for category: Array in categories:
		var kind := str(category[0])
		var item: Dictionary = category[1][0]
		var id := str(item["id"])
		var before_money: int = state.money
		var before_count: int = state.free_spare_count(kind, id)
		var newspaper: Array = state.newspaper_copies(kind, id)
		assert(state.buy_new_part(kind, id).is_empty())
		assert(state.money == before_money - int(item["price"]))
		assert(state.free_spare_count(kind, id) == before_count + 1)
		assert(state.spare_condition_list(kind, id).has(1.0))
		assert(state.newspaper_copies(kind, id) == newspaper)
	var cash: int = state.money
	assert(not state.buy_new_part("invalid", "heads-iron").is_empty())
	assert(not state.buy_new_part("part", "missing").is_empty())
	assert(state.money == cash)
	state.money = 0
	var count: int = state.free_spare_count("part", "heads-iron")
	assert(not state.buy_new_part("part", "heads-iron").is_empty())
	assert(state.money == 0 and state.free_spare_count("part", "heads-iron") == count)
	state.money = 100000
	store.call("_buy", "part", "heads-iron")
	assert(state.free_spare_count("part", "heads-iron") == count + 1)
	assert((store.get("_status") as Label).text.contains("Bought"))
	count += 1

	assert(state.save_game(1))
	state.owned_part_ids.clear()
	state.spare_conditions.clear()
	assert(state.load_game(1))
	assert(state.free_spare_count("part", "heads-iron") == count)
	assert(state.spare_condition_list("part", "heads-iron").has(1.0))
	assert(state.current_scene_path == state.SCENE_ROYAL_RODS)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(save_dir.path_join("slot_1.json"))) == OK)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(save_dir)) == OK)

	store.call("_leave", true)
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == state.SCENE_CRUISE)
	assert(current_scene.get("_destination") == state.SCENE_GARAGE)
	assert(current_scene.get("_pts").size() >= 2)
	assert(state.drive_into_garage)
	change_scene_to_file(state.SCENE_ROYAL_RODS)
	await process_frame
	await process_frame
	current_scene.call("_leave", false)
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == state.SCENE_CRUISE)
	assert(current_scene.get("_roaming"))
	assert(current_scene.get("_roam_home") == state.POI_ROYAL_RODS)
	current_scene.call("_enter_roam_place", state.POI_ROYAL_RODS)
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == state.SCENE_ROYAL_RODS)
	print("Royal Rods integration checks passed.")
	quit()
