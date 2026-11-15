extends SceneTree

## The race's ~ prompt: it pauses the race, and each command does its job.


func _initialize() -> void:
	call_deferred("_run")


func _backtick() -> InputEventKey:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_QUOTELEFT
	key.physical_keycode = KEY_QUOTELEFT
	key.unicode = 0x60
	return key


func _new_race(state: Node) -> Node:
	var packed := load(str(state.get("SCENE_RACE"))) as PackedScene
	assert(change_scene_to_packed(packed) == OK)
	await process_frame
	await process_frame
	var race := current_scene
	race.call("_start_race")
	return race


func _open_console(race: Node) -> Control:
	race.call("_unhandled_input", _backtick())
	var console := race.get("_console") as Control
	assert(console != null)
	assert(paused)
	return console


func _close_console(race: Node) -> void:
	root.push_input(_backtick())
	await process_frame
	assert(race.get("_console") == null)
	assert(not paused)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := root.get_node("GameState")
	var save_dir := "/tmp/race-console-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.set("save_dir", save_dir)
	state.set("legacy_save_path", "")
	state.call("new_game")
	state.set("selected_opponent_id", int(state.call("_meet_opponent", "Test Rival")))
	state.set("selected_race_type", state.get("RACE_DRAG"))

	var race: Node = await _new_race(state)
	var player := race.get("_player") as Node
	var rival := race.get("_opponent") as Node

	var console := _open_console(race)
	var out := console.get("_output") as Label

	# showme: race damage, a flat, and worn parts all made good.
	player.call("take_hit", 8.0)
	assert(float(player.call("damage_amount")) > 0.0)
	player.call("blow_tire", 0)
	race.set("_flat_tire_s", 0.5)
	assert(player.call("has_flat_tire"))
	console.call("_on_submitted", "showme")
	assert(out.text.begins_with("Your car is fixed"))
	assert(is_zero_approx(float(player.call("damage_amount"))))
	assert(not player.call("has_flat_tire"))
	assert(float(race.get("_flat_tire_s")) < 0.0)

	# tiger: a full tank.
	state.call("set_fuel", 1.0)
	console.call("_on_submitted", "tiger")
	assert(is_equal_approx(float(state.get("fuel")), float(state.get("DEFAULT_TANK_L"))))

	# iddqd: no damage while it is on, and it toggles off again.
	console.call("_on_submitted", "iddqd")
	assert(player.get("invincible"))
	assert(not player.call("take_hit", 13.0))
	assert(is_zero_approx(float(player.call("damage_amount"))))
	console.call("_on_submitted", "iddqd")
	assert(not player.get("invincible"))
	assert(player.call("take_hit", 3.0))
	player.call("repair")

	# sleepytime: the rival coasts, and the race goes on.
	console.call("_on_submitted", "sleepytime")
	assert(rival.call("is_asleep"))
	assert(out.text.ends_with("falls asleep at the wheel."))
	console.call("_on_submitted", "sleepytime")
	assert(out.text == "The rival is already asleep.")
	await _close_console(race)
	for i: int in 30:
		await physics_frame
	assert(not race.get("_race_over"))
	assert(not rival.call("is_wrecked"))

	# wreckit: the rival is totaled and the race is won.
	console = _open_console(race)
	console.call("_on_submitted", "wreckit")
	assert(rival.call("is_wrecked"))
	await _close_console(race)
	await physics_frame
	await physics_frame
	assert(race.get("_race_over"))
	paused = false

	# On a test drive there is no rival to put to sleep or wreck.
	race = await _new_race(state)
	race.set("_test_drive", true)
	console = _open_console(race)
	out = console.get("_output") as Label
	console.call("_on_submitted", "wreckit")
	assert(out.text == "There is no rival on a test drive.")
	console.call("_on_submitted", "sleepytime")
	assert(out.text == "There is no rival on a test drive.")
	await _close_console(race)

	print("race console test passed")
	quit()
