extends SceneTree

## Loaded once the autoloads exist. A preload here would compile controller.gd before GameState.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var HeadLook: GDScript = load("res://scripts/head_look.gd")
	var Controller: GDScript = load("res://scripts/controller.gd")
	load("res://scripts/player_race_car.gd")
	load("res://scripts/cruise.gd")
	assert(int(Controller.default_keys(Controller.DOWN)[0]) == KEY_COMMA, "Comma shifts down")
	assert(int(Controller.default_keys(Controller.UP)[0]) == KEY_PERIOD, "Period shifts up")
	assert(int(Controller.default_keys(Controller.LOOK_LEFT)[0]) == KEY_Q, "Q looks left")
	assert(int(Controller.default_keys(Controller.LOOK_RIGHT)[0]) == KEY_E, "E looks right")
	assert(int(Controller.default_keys(Controller.LOOK_LEFT_WIDE)[0]) == KEY_Z, "Z looks far left")
	assert(int(Controller.default_keys(Controller.LOOK_RIGHT_WIDE)[0]) == KEY_C, "C looks far right")
	assert(int(Controller.default_keys(Controller.CAMERA)[0]) == 0, "C is no longer the camera key")
	assert(int(Controller.default_keys(Controller.CAMERA_FAR)[0]) == KEY_F1, "F1 is far behind")
	assert(int(Controller.default_keys(Controller.CAMERA_CLOSE)[0]) == KEY_F2, "F2 is close behind")
	assert(int(Controller.default_keys(Controller.CAMERA_COCKPIT)[0]) == KEY_F3, "F3 is inside")
	assert(int(Controller.default_keys(Controller.CAMERA_BUMPER)[0]) == KEY_F4, "F4 is the front bumper")
	var pad_left: Array = Controller.default_pad(Controller.LOOK_LEFT)
	var pad_right: Array = Controller.default_pad(Controller.LOOK_RIGHT)
	var pad_far: Array = Controller.default_pad(Controller.LOOK_FAR)
	assert(int(pad_left[0]["axis"]) == JOY_AXIS_RIGHT_X and int(pad_left[0]["dir"]) == -1, "Right stick left looks left")
	assert(int(pad_right[0]["axis"]) == JOY_AXIS_RIGHT_X and int(pad_right[0]["dir"]) == 1, "Right stick right looks right")
	assert(int(pad_far[0]["button"]) == JOY_BUTTON_RIGHT_STICK, "Clicking the right stick looks further")
	assert(Controller.camera_view_for_key(KEY_F3) == 2, "F3 picks the inside view")

	var rest := Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3(0.4, 1.2, -0.4))
	var ahead := -rest.basis.z
	assert(ahead.dot(Vector3(0.0, 0.0, 1.0)) > 0.99, "The driving camera looks along the car")
	var look: RefCounted = HeadLook.new()
	look.set(&"yaw", Controller.QUARTER_YAW)
	var turned: Transform3D = look.call(&"apply", rest)
	var right := -turned.basis.z
	assert(right.x < -0.9 and right.z > 0.1, "Full right looks to the right")
	assert(absf(right.angle_to(Vector3(0.0, 0.0, 1.0)) - Controller.QUARTER_YAW) < 0.001, "That look is 80 degrees from straight ahead")
	assert(turned.origin.is_equal_approx(rest.origin), "The head stays where the camera sits")
	look.set(&"yaw", -Controller.QUARTER_YAW)
	var left_pose: Transform3D = look.call(&"apply", rest)
	var left := -left_pose.basis.z
	assert(left.x > 0.9 and left.z > 0.1, "Full left looks to the left")
	assert(absf(left.angle_to(Vector3(0.0, 0.0, 1.0)) - Controller.QUARTER_YAW) < 0.001, "The left look is 80 degrees from straight ahead")

	look.set(&"yaw", Controller.WIDE_YAW)
	look.call(&"update", 1.0)
	assert(absf(float(look.get(&"yaw"))) < 0.01, "Letting go brings the head back")
	assert(is_zero_approx(Controller.head_yaw()), "Nothing held looks ahead")

	_hold(KEY_Q)
	assert(is_equal_approx(Controller.head_yaw(), -Controller.QUARTER_YAW), "Q asks for 80 degrees left")
	_release(KEY_Q)
	_hold(KEY_E)
	assert(is_equal_approx(Controller.head_yaw(), Controller.QUARTER_YAW), "E asks for 80 degrees right")
	_hold(KEY_Q)
	assert(is_zero_approx(Controller.head_yaw()), "Both quarter looks hold the head ahead")
	_release(KEY_Q)
	_release(KEY_E)

	_hold(KEY_Z)
	assert(is_equal_approx(Controller.head_yaw(), -Controller.WIDE_YAW), "Z asks for 165 degrees left")
	look.set(&"yaw", 0.0)
	look.call(&"update", 1.0)
	assert(absf(float(look.get(&"yaw")) + Controller.WIDE_YAW) < 0.01, "The head reaches the far look")
	look.set(&"yaw", -Controller.WIDE_YAW)
	var far_left: Transform3D = look.call(&"apply", rest)
	var far_left_dir := -far_left.basis.z
	assert(far_left_dir.x > 0.2 and far_left_dir.z < -0.9, "Z looks back over the left shoulder")
	assert(absf(far_left_dir.angle_to(Vector3(0.0, 0.0, 1.0)) - Controller.WIDE_YAW) < 0.001, "That look is 165 degrees from straight ahead")
	_hold(KEY_Q)
	assert(is_equal_approx(Controller.head_yaw(), -Controller.WIDE_YAW), "The wider look wins on the same side")
	_release(KEY_Q)
	_release(KEY_Z)
	_hold(KEY_C)
	assert(is_equal_approx(Controller.head_yaw(), Controller.WIDE_YAW), "C asks for 165 degrees right")
	_hold(KEY_Z)
	assert(is_zero_approx(Controller.head_yaw()), "Both far looks hold the head ahead")
	_release(KEY_Z)
	_release(KEY_C)
	assert(is_zero_approx(Controller.head_yaw()))

	print("Head look checks passed.")
	quit()


func _hold(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
