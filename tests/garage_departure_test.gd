extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _new_garage() -> Node:
	var packed := load("res://scenes/garage.tscn") as PackedScene
	assert(change_scene_to_packed(packed) == OK)
	await process_frame
	await process_frame
	return current_scene


func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _run() -> void:
	var state := root.get_node("GameState")
	state.call("new_game")
	assert(state.call("can_drive"))
	state.set("skip_cruise", false)

	var garage := await _new_garage()
	garage.call("_input", _key(KEY_SPACE))
	assert(not garage.get("_departing"))
	garage.call("_start_drive_out", "")
	assert(garage.get("_departing"))
	garage.call("_input", _key(KEY_SPACE, false))
	garage.call("_input", _key(KEY_SPACE, true, true))
	garage.call("_input", _key(KEY_A))
	assert(not garage.get("_departure_finished"))
	root.push_input(_key(KEY_SPACE))
	assert(garage.get("_departure_finished"))
	assert(state.get("roam_from_poi") == state.POI_GARAGE)
	garage.call("_finish_drive_out")
	assert(state.get("roam_from_poi") == state.POI_GARAGE)
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == state.SCENE_CRUISE)

	garage = await _new_garage()
	garage.call("_start_drive_out", state.SCENE_GAS_STATION)
	await create_timer(1.7).timeout
	assert(not garage.get("_departure_finished"))
	root.push_input(_key(KEY_SPACE))
	assert(garage.get("_departure_finished"))
	assert(state.get("cruise_from_poi") == state.POI_GARAGE)
	assert(state.get("cruise_to_poi") == state.POI_GAS_STATION)
	assert(state.get("cruise_scene") == state.SCENE_GAS_STATION)
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == state.SCENE_CRUISE)

	garage = await _new_garage()
	state.set("skip_cruise", true)
	garage.call("_start_drive_out", state.SCENE_GAS_STATION)
	garage.call("_input", _key(KEY_SPACE))
	assert(state.get("current_scene_path") == state.SCENE_GAS_STATION)
	assert(state.get("cruise_scene") == "")
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == state.SCENE_GAS_STATION)

	garage = await _new_garage()
	state.set("skip_cruise", false)
	garage.call("_start_drive_out", state.SCENE_GAS_STATION)
	await create_timer(4.5).timeout
	assert(state.get("current_scene_path") == state.SCENE_GAS_STATION)
	assert(current_scene.scene_file_path == state.SCENE_CRUISE)

	print("garage departure tests passed")
	quit()
