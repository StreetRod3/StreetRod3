extends SceneTree

## Gearbox, racing-cam, racing-spring, and racing-shock books boost only the part they name.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	var save_dir := "/tmp/books-parts-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.set("save_dir", save_dir)
	state.set("legacy_save_path", "")
	state.call("new_game")

	assert(str((state.get("BOOKS") as Array)[0].get("id", "")) == "hellmark-flathead")
	assert((state.call("book_by_id", "hellmark-transmissions") as Dictionary).is_empty())
	assert(str(state.call("book_effect_text", state.call("book_by_id", "hellmark-gb-race5"))) == "+4 hp · 5-speed racing")
	assert(str(state.call("book_effect_text", state.call("book_by_id", "hellmark-gb-man5"))) == "+4 hp · 5-speed manual")
	assert(str(state.call("book_effect_text", state.call("book_by_id", "hellmark-gb-man4"))) == "+4 hp · 4-speed manual")
	assert(str(state.call("book_effect_text", state.call("book_by_id", "hellmark-gb-man3"))) == "+4 hp · 3-speed manual")
	assert(str(state.call("book_effect_text", state.call("book_by_id", "hellmark-gb-auto3"))) == "+4 hp · Automatic 3-speed")
	assert(str(state.call("book_effect_text", state.call("book_by_id", "hellmark-racing-cam"))) == "+5 hp · Racing camshaft")
	assert(str(state.call("book_effect_text", state.call("book_by_id", "hellmark-racing-springs"))) == "+20% stiffer · Racing springs")
	assert(str(state.call("book_effect_text", state.call("book_by_id", "hellmark-racing-shocks"))) == "+20% more damping · Racing shocks")
	for book_id: String in ["hellmark-gb-race5", "hellmark-gb-man5", "hellmark-gb-man4", "hellmark-gb-man3", "hellmark-gb-auto3", "hellmark-racing-cam", "hellmark-racing-springs", "hellmark-racing-shocks"]:
		var offer: Dictionary = state.call("roll_race_book_offer", 1000, "road", 0.0, _prize_index(state, book_id))
		assert(str(offer.get("id", "")) == book_id)

	var hp_before := float(state.get("engine_power_hp"))
	assert(state.call("add_book", "hellmark-gb-auto3"))
	assert(state.call("add_book", "hellmark-gb-race5"))
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before + 4.0))
	state.set("equipped_gearbox_id", "gb_race5")
	state.call("refresh_car_stats")
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before + 4.0))
	state.set("equipped_gearbox_id", "gb_man4")
	state.call("refresh_car_stats")
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before))
	assert(state.call("add_book", "hellmark-gb-man4"))
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before + 4.0))
	state.set("equipped_gearbox_id", "gb_auto3-ford")
	state.call("refresh_car_stats")
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before + 4.0))
	state.set("equipped_gearbox_id", state.get("NO_GEARBOX_ID"))
	state.call("refresh_car_stats")
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before))
	state.set("equipped_gearbox_id", state.get("DEFAULT_GEARBOX_ID"))
	state.call("refresh_car_stats")
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before + 4.0))

	assert(state.call("add_book", "hellmark-racing-cam"))
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before + 4.0))
	var slots: Dictionary = state.get("slot_part_ids")
	var stock_cam := str(slots["cam"])
	slots["cam"] = "cam"
	state.call("refresh_car_stats")
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before + 4.0 + 30.0 + 5.0))
	slots["cam"] = stock_cam
	state.call("refresh_car_stats")
	assert(is_equal_approx(float(state.get("engine_power_hp")), hp_before + 4.0))

	var racing_springs: Dictionary = state.call("listing_by_id", state.get("PARTS"), "springs-racing")
	var racing_shocks: Dictionary = state.call("listing_by_id", state.get("PARTS"), "shocks-racing")
	assert(str(state.call("part_detail", racing_springs)).begins_with("90% stiffer"))
	assert(str(state.call("part_detail", racing_shocks)) == "70% more damping")
	var stock_springs := str(slots["springs"])
	var stock_shocks := str(slots["shocks"])
	var stock_chassis: Dictionary = state.call("race_chassis")
	assert(state.call("add_book", "hellmark-racing-springs"))
	assert(state.call("add_book", "hellmark-racing-shocks"))
	var still_stock: Dictionary = state.call("race_chassis")
	assert(is_equal_approx(float(still_stock["spring_rate"]), float(stock_chassis["spring_rate"])))
	assert(is_equal_approx(float(still_stock["shock_rate"]), float(stock_chassis["shock_rate"])))
	assert(str(state.call("part_detail", racing_springs)).begins_with("110% stiffer"))
	assert(str(state.call("part_detail", racing_shocks)) == "90% more damping")
	slots["springs"] = "springs-racing"
	slots["shocks"] = "shocks-racing"
	var fitted_springs: Dictionary = state.call("slot_part", "springs")
	var fitted_shocks: Dictionary = state.call("slot_part", "shocks")
	assert(str(fitted_springs.get("id", "")) == "springs-racing")
	assert(str(fitted_shocks.get("id", "")) == "shocks-racing")
	var spring_c := float(state.call("mount_condition", "slot:springs"))
	var shock_c := float(state.call("mount_condition", "slot:shocks"))
	var expected_spring := 2.1 * lerpf(float(state.get("SPRING_WORN_RATE")), 1.0, spring_c)
	var expected_shock := 1.9 * lerpf(float(state.get("SHOCK_WORN_RATE")), 1.0, shock_c)
	var raced: Dictionary = state.call("race_chassis")
	assert(is_equal_approx(float(raced["spring_rate"]), expected_spring))
	assert(is_equal_approx(float(raced["shock_rate"]), expected_shock))
	slots["springs"] = stock_springs
	slots["shocks"] = stock_shocks

	print("books_parts_test: OK")
	quit()


func _prize_index(state: Node, book_id: String) -> int:
	var index := 0
	for book: Dictionary in state.get("BOOKS"):
		var id := str(book.get("id", ""))
		if id == "credits" or id == "shortcuts":
			continue
		if id == book_id:
			return index
		index += 1
	return -1
