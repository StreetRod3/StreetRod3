extends SceneTree

## Issue #153: back at the drive-in after looking under a rival's hood, the race menu
## must still show each race's length and fuel, and the tank.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	state.call("new_game")
	var index: int = state.call("call_random_opponent")
	assert(index >= 0)
	# The state the hood scene leaves behind when it sends the player back.
	state.set("drive_in_rival_index", index)
	state.set("drive_in_hood_seen", true)

	var packed := load(str(state.get("SCENE_DRIVE_IN"))) as PackedScene
	assert(change_scene_to_packed(packed) == OK)
	await process_frame
	await process_frame
	var drive_in := current_scene
	assert(drive_in.get("_chosen_index") == index)

	drive_in.call("_engage_rival")
	var hint := (drive_in.get("_race_hint") as Label).text
	var drag := (drive_in.get("_drag_btn") as Button).text
	var road := (drive_in.get("_road_btn") as Button).text
	print("hint: ", hint.replace("\n", " | "))
	print("drag: ", drag.replace("\n", " | "))
	print("road: ", road.replace("\n", " | "))
	assert(hint.contains("Tank"))
	assert(drag.contains("Quarter mile"))
	assert(road.contains("with turns"))
	print("drive_in_hood_return_test: OK")
	quit(0)
