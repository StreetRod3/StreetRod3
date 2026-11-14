extends SceneTree

## The mouse wheel scrolls an open window without zooming the garage behind it (#118).


func _initialize() -> void:
	call_deferred("_run")


## One notch of the wheel with the pointer at `at`, sent as the platforms send it: a press,
## then a release.
func _notch(at: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)
	for pressed: bool in [true, false]:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = button
		wheel.pressed = pressed
		wheel.factor = 1.0
		wheel.position = at
		wheel.global_position = at
		root.push_input(wheel)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := root.get_node("GameState")
	var save_dir := "/tmp/garage-wheel-zoom-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.set("save_dir", save_dir)
	state.set("legacy_save_path", "")
	state.call("new_game")
	var garage := (load("res://scenes/garage.tscn") as PackedScene).instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	await physics_frame

	var middle := Vector2(root.size) * 0.5
	var start := float(garage.get("_cam_distance_target"))
	_notch(middle, MOUSE_BUTTON_WHEEL_DOWN)
	var one_notch := float(garage.get("_cam_distance_target")) - start
	assert(one_notch > 0.0)
	# The release does not zoom again: one notch is one step.
	assert(is_equal_approx(one_notch, float(garage.get("ZOOM_STEP"))))

	for opener: StringName in [&"_show_parts_board", &"_show_spares_board"]:
		garage.call(opener)
		await process_frame
		var before := float(garage.get("_cam_distance_target"))
		# Over the list, and beside the window, over the dimmed garage.
		for at: Vector2 in [middle, Vector2(40, 40)]:
			_notch(at, MOUSE_BUTTON_WHEEL_UP)
			_notch(at, MOUSE_BUTTON_WHEEL_DOWN)
			_notch(at, MOUSE_BUTTON_WHEEL_DOWN)
		assert(is_equal_approx(float(garage.get("_cam_distance_target")), before))
		garage.call("_hide_parts_board")
		await process_frame

	print("garage wheel zoom tests passed")
	quit()
