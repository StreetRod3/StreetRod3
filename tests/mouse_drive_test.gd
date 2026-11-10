extends SceneTree

const MouseDrive := preload("res://scripts/mouse_drive.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var mouse := MouseDrive.new()
	mouse.move(Vector2(100, -200), true, true, 1.0, 1.0)
	assert(is_equal_approx(mouse.steering, -0.25))
	assert(is_equal_approx(mouse.pedals, 0.5))
	mouse.move(Vector2(-100, 200), true, true, 1.0, 1.0)
	assert(is_zero_approx(mouse.steering) and is_zero_approx(mouse.pedals))
	mouse.move(Vector2(-800, 800), true, true, 2.0, 2.0)
	assert(mouse.steering == 1.0 and mouse.pedals == -1.0)
	mouse.move(Vector2(400, -400), false, false, 1.0, 1.0)
	assert(mouse.steering == 0.0 and mouse.pedals == 0.0)
	mouse.move(Vector2(100, -200), true, false, 2.0, 1.0)
	assert(is_equal_approx(mouse.steering, -0.5) and is_zero_approx(mouse.pedals))
	mouse.move(Vector2(100, -200), false, true, 1.0, 0.5)
	assert(is_zero_approx(mouse.steering) and is_equal_approx(mouse.pedals, 0.25))

	var state := root.get_node("GameState")
	state.mouse_steering_enabled = true
	state.mouse_pedals_enabled = true
	state.mouse_steering_sensitivity = 2.0
	state.mouse_pedals_sensitivity = 0.5
	var car: CharacterBody3D = (load("res://scripts/player_race_car.gd") as Script).new()
	car.set("_mouse_captured", true)
	var event := InputEventMouseMotion.new()
	event.screen_relative = Vector2(100, -200)
	car.call("_input", event)
	assert(is_equal_approx(car.call("_steer_input"), -0.5))
	assert(is_equal_approx(car.call("_throttle_amount"), 0.25))
	assert(is_zero_approx(car.call("_brake_amount")))
	event.screen_relative = Vector2(-100, 400)
	car.call("_input", event)
	assert(is_equal_approx(car.call("_brake_amount"), 0.25))
	assert(is_zero_approx(car.call("_throttle_amount")))
	car.call("_release_mouse_drive")
	assert(is_zero_approx(car.call("_steer_input")) and is_zero_approx(car.call("_brake_amount")))
	car.free()

	var host := Control.new()
	root.add_child(host)
	var page := Control.new()
	var back := Button.new()
	host.add_child(page)
	page.add_child(back)
	var setup: CanvasLayer = (load("res://scripts/mouse_setup.gd") as Script).new()
	setup.call("open", host, page, back)
	assert(not page.visible)
	var steering := setup.find_child("MouseSteering", true, false) as CheckBox
	var pedals := setup.find_child("MousePedals", true, false) as CheckBox
	var steer_slider := setup.find_child("MouseSteeringSensitivity", true, false) as HSlider
	var pedals_slider := setup.find_child("MousePedalsSensitivity", true, false) as HSlider
	assert(steering.button_pressed and pedals.button_pressed)
	assert(is_equal_approx(steer_slider.value, 2.0) and is_equal_approx(pedals_slider.value, 0.5))
	steering.button_pressed = false
	pedals.button_pressed = false
	steer_slider.value = 1.5
	pedals_slider.value = 2.5
	assert(not state.mouse_steering_enabled and not state.mouse_pedals_enabled)
	assert(is_equal_approx(state.mouse_steering_sensitivity, 1.5) and is_equal_approx(state.mouse_pedals_sensitivity, 2.5))
	if OS.get_environment("MOUSE_TEST_ISOLATED") == "1":
		assert(ProjectSettings.globalize_path("user://").begins_with(OS.get_environment("HOME") + "/"))
		state.mouse_steering_enabled = true
		state.mouse_pedals_enabled = true
		state.save_settings()
		state.mouse_steering_enabled = false
		state.mouse_pedals_enabled = false
		state.mouse_steering_sensitivity = 1.0
		state.mouse_pedals_sensitivity = 1.0
		state.load_settings()
		assert(state.mouse_steering_enabled and state.mouse_pedals_enabled)
		assert(is_equal_approx(state.mouse_steering_sensitivity, 1.5) and is_equal_approx(state.mouse_pedals_sensitivity, 2.5))
	host.free()

	state.mouse_steering_enabled = true
	state.mouse_pedals_enabled = true
	var race := (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	var player := race.get_node("PlayerCar") as CharacterBody3D
	assert(player.get("_mouse_captured"))
	var gamepad: CanvasLayer = state.get("_gamepad")
	gamepad.set("_pointing", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	gamepad.call("_stop_pointing")
	if DisplayServer.get_name() != "headless":
		assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	player.call("_input", event)
	assert(not is_zero_approx(player.call("_brake_amount")))
	assert(not is_zero_approx(player.call("_steer_input")))
	var mouse_button := InputEventMouseButton.new()
	mouse_button.button_index = MOUSE_BUTTON_LEFT
	mouse_button.pressed = true
	var brake_before: float = player.call("_brake_amount")
	player.call("_input", mouse_button)
	assert(is_zero_approx(player.call("_steer_input")))
	assert(is_equal_approx(player.call("_brake_amount"), brake_before))
	player.call("_input", event)
	var steer_before: float = player.call("_steer_input")
	mouse_button.button_index = MOUSE_BUTTON_RIGHT
	mouse_button.pressed = false
	player.call("_input", mouse_button)
	assert(not is_zero_approx(player.call("_brake_amount")))
	mouse_button.pressed = true
	player.call("_input", mouse_button)
	assert(is_zero_approx(player.call("_brake_amount")))
	assert(is_equal_approx(player.call("_steer_input"), steer_before))
	player.call("_input", event)
	race.call("_open_pause_menu")
	assert(not player.get("_mouse_captured"))
	assert(is_zero_approx(player.call("_brake_amount")))
	race.call("_resume_race")
	assert(player.get("_mouse_captured"))
	assert(is_zero_approx(player.call("_brake_amount")))
	player.call("_input", event)
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(not player.get("_mouse_captured") and is_zero_approx(player.call("_brake_amount")))
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(player.get("_mouse_captured"))
	player.call("begin_park", 0.0)
	assert(not player.get("_mouse_captured"))
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(not player.get("_mouse_captured"))
	race.free()
	state.roam_from_poi = state.POI_GARAGE
	var cruise := (load("res://scenes/cruise.tscn") as PackedScene).instantiate()
	root.add_child(cruise)
	var cruise_car := cruise.get("_roam_car") as CharacterBody3D
	assert(cruise_car != null and cruise_car.get("_mouse_captured"))
	cruise_car.call("_input", event)
	assert(not is_zero_approx(cruise_car.call("_brake_amount")))
	cruise_car.call("stop_mouse_driving")
	assert(not cruise_car.get("_mouse_captured") and is_zero_approx(cruise_car.call("_brake_amount")))
	cruise.free()
	print("Mouse driving checks passed.")
	quit()
