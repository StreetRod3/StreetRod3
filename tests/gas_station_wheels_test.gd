extends SceneTree

## The car at the gas station wears the wheels fitted to it, not its car file's stock ones (#184).

const _MOUNTS: Array[String] = ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	state.call("new_game")
	assert(state.call("has_active_car"))
	var stock := str(state.get("equipped_wheel_id"))
	var fitted := {}
	for wheel: Dictionary in state.get("WHEELS"):
		if str(wheel.get("id", "")) != stock and not str(wheel.get("path", "")).is_empty():
			fitted = wheel
			break
	assert(not fitted.is_empty())
	state.set("equipped_wheel_id", str(fitted["id"]))

	assert(change_scene_to_file(state.SCENE_GAS_STATION) == OK)
	await process_frame
	await process_frame
	var car := current_scene.find_child("PlayerCar", true, false) as Node3D
	assert(car != null)
	for mount_name in _MOUNTS:
		var mount := car.get_node_or_null(mount_name) as Node3D
		assert(mount != null)
		assert(mount.visible)
		assert(str(mount.get("stl_path")) == str(fitted["path"]))

	print("gas station wheels tests passed")
	quit()
