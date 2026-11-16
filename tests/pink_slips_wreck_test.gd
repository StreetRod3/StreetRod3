extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	var save_dir := "user://pink-slips-wreck-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.set("save_dir", save_dir)
	state.set("legacy_save_path", "")
	state.new_game()

	state.selected_opponent_id = state.call_random_opponent()
	var opp: Dictionary = state.selected_opponent()
	var before_cars: int = state.owned_car_ids.size()
	var engine_id := str(opp.get("engine", ""))
	var gearbox_id := str(opp.get("gearbox", ""))
	var tires_id := str(state.opponent_tires(opp).get("id", ""))
	var before_engine_spares: int = state.free_spare_count("engine", engine_id)
	var before_gearbox_spares: int = state.free_spare_count("transmission", gearbox_id)
	var before_tires_spares: int = state.free_spare_count("part", tires_id)

	# Non-pink-slips wreck: nothing salvaged.
	state.race_pink_slips = false
	assert(not state.salvage_wrecked_opponent_car())
	assert(state.owned_car_ids.size() == before_cars)
	assert(state.free_spare_count("engine", engine_id) == before_engine_spares)

	# Pink-slips wreck: player keeps the parts as spares, not the car itself.
	var expected_rec: Dictionary = state.call("_opponent_car_record", opp)
	assert(not expected_rec.is_empty())
	var expected_mounts: Array = state.call("_record_mounts", expected_rec)
	var before_counts := {}
	for mount: Array in expected_mounts:
		before_counts[mount] = state.free_spare_count(mount[0], mount[1])

	state.race_pink_slips = true
	assert(state.salvage_wrecked_opponent_car())
	assert(not state.race_pink_slips)
	assert(state.owned_car_ids.size() == before_cars)

	var expected_delta := {}
	for mount: Array in expected_mounts:
		expected_delta[mount] = int(expected_delta.get(mount, 0)) + 1
	for mount: Array in expected_delta.keys():
		assert(state.free_spare_count(mount[0], mount[1]) == int(before_counts[mount]) + int(expected_delta[mount]))
	assert(state.free_spare_count("engine", engine_id) == before_engine_spares + 1)
	assert(state.free_spare_count("transmission", gearbox_id) == before_gearbox_spares + 1)
	assert(state.free_spare_count("part", tires_id) == before_tires_spares + 1)

	# Taken car wreck: salvages parts from taken_car and clears taken_car.
	var opp_after: Dictionary = state.selected_opponent()
	var taken := expected_rec.duplicate(true)
	opp_after["taken_car"] = taken
	var taken_before := {}
	for mount: Array in expected_mounts:
		taken_before[mount] = state.free_spare_count(mount[0], mount[1])
	state.race_pink_slips = true
	assert(state.salvage_wrecked_opponent_car())
	assert(not state.selected_opponent().has("taken_car"))
	for mount: Array in expected_delta.keys():
		assert(state.free_spare_count(mount[0], mount[1]) == int(taken_before[mount]) + int(expected_delta[mount]))

	print("Pink slips wreck checks passed.")
	quit(0)
