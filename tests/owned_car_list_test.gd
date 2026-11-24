extends SceneTree

## Owned-car horsepower and top speed match the parts board, and a second paint is its own color.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := root.get_node("GameState")
	state.set("save_dir", "/tmp/owned-car-list-test-%d" % OS.get_process_id())
	state.set("legacy_save_path", "")
	state.call("new_game")
	var current := str(state.get("current_car_id"))
	_assert_live(state, current)
	var stock_hp := float(state.get("engine_power_hp"))

	assert(str(state.call("editor_add_car", "chevy-c10-1963")) == "")
	assert(str(state.call("editor_add_car", "dodge-challenger-1970")) == "")
	assert(str(state.call("editor_add_car", "corvette-1960")) == "")
	var owned: Array = state.get("owned_car_ids")
	var c10 := str(owned[1])
	var challenger := str(owned[2])
	var cove_car := str(owned[3])
	assert(_paints(state, current).size() == 1)
	assert(_paints(state, c10).size() == 2)
	assert(_paints(state, challenger).size() == 2)
	assert(_paints(state, cove_car).size() == 1)
	var c10_perf: Vector2 = state.call("owned_car_performance", c10)
	assert(c10_perf.x > 0.0 and c10_perf.y > 0.0)

	assert(str(state.call("select_owned_car", cove_car)) == "")
	_assert_live(state, cove_car)
	state.call("set_car_cove_color", Color(0.95, 0.9, 0.2, 1))
	var split: Array = _paints(state, cove_car)
	assert(split.size() == 2)
	assert(not (split[0] as Color).is_equal_approx(split[1]))
	assert(str(state.call("select_owned_car", current)) == "")
	var parked: Array = _paints(state, cove_car)
	assert(parked.size() == 2)
	_assert_live(state, current)
	assert(is_equal_approx(float(state.get("engine_power_hp")), stock_hp))

	var garage := (load("res://scenes/garage.tscn") as PackedScene).instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	garage.call("_toggle_car_list")
	await process_frame
	var rows := garage.get("_car_list_rows") as VBoxContainer
	assert(rows.get_child_count() == 4)
	for i: int in rows.get_child_count():
		var btn := rows.get_child(i) as Button
		var box := btn.get_child(0) as HBoxContainer
		var name_label := box.get_child(0).get_child(0) as Label
		var stats := box.get_child(1) as Label
		var swatch := box.get_child(2)
		assert(name_label.text.begins_with("%d." % [i + 1]))
		assert(stats.text.contains("hp"))
		assert(stats.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT)
		assert(swatch.get_class() == "Control" or swatch.get_script() != null)
		assert(stats.global_position.x > name_label.global_position.x)
		assert(swatch.global_position.x > stats.global_position.x)
	var c10_swatch: Object = (rows.get_child(1) as Button).get_child(0).get_child(2)
	assert(float((c10_swatch.get("accent") as Color).a) > 0.0)
	var stock_swatch: Object = (rows.get_child(0) as Button).get_child(0).get_child(2)
	assert(is_zero_approx(float((stock_swatch.get("accent") as Color).a)))

	print("owned_car_list_test: OK")
	quit()


func _assert_live(state: Node, car_id: String) -> void:
	var perf: Vector2 = state.call("owned_car_performance", car_id)
	assert(is_equal_approx(perf.x, float(state.get("engine_power_hp"))))
	assert(is_equal_approx(perf.y, float(state.call("get_effective_vmax_kmh"))))


func _paints(state: Node, car_id: String) -> Array:
	return state.call("owned_car_paints", car_id)
