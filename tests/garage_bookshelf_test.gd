extends SceneTree

const _ArcadeDrive := preload("res://scripts/arcade_drive.gd")
const _VehicleDynamics := preload("res://scripts/vehicle_dynamics.gd")


func _initialize() -> void:
	call_deferred("_run")


func _world_aabb(node: Node) -> AABB:
	var box := AABB()
	var started := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var local := mi.mesh.get_aabb()
		var xf := mi.global_transform
		box = AABB(xf * local.get_endpoint(0), Vector3.ZERO)
		for i: int in range(1, 8):
			box = box.expand(xf * local.get_endpoint(i))
		started = true
	for child: Node in node.get_children():
		var cb := _world_aabb(child)
		if cb.size == Vector3.ZERO:
			continue
		if not started:
			box = cb
			started = true
		else:
			box = box.merge(cb)
	return box


func _visible_book_meshes(bookshelf: Node) -> int:
	var count := 0
	for child: Node in bookshelf.get_children():
		if child is MeshInstance3D and child.name.begins_with("Book") and (child as MeshInstance3D).visible:
			count += 1
	return count


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := root.get_node("GameState")
	var save_dir := "/tmp/garage-bookshelf-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.set("save_dir", save_dir)
	state.set("legacy_save_path", "")
	state.call("new_game")

	# Registry loads books from assets/books/books.registry, and owned list starts empty.
	var catalog: Array = state.get("BOOKS")
	assert(catalog.size() >= 5)
	assert(not (state.call("book_by_id", "hellmark-flathead") as Dictionary).is_empty())
	assert(not (state.call("book_by_id", "hellmark-sbc") as Dictionary).is_empty())
	assert(not (state.call("book_by_id", "hellmark-yblock") as Dictionary).is_empty())
	assert(not (state.call("book_by_id", "hellmark-windsor") as Dictionary).is_empty())
	assert(not (state.call("book_by_id", "hellmark-racing-slicks") as Dictionary).is_empty())
	assert((state.call("book_by_id", "motors-auto-repair") as Dictionary).is_empty())
	assert((state.get("owned_book_ids") as Array).is_empty())
	assert((state.call("owned_books") as Array).is_empty())

	var garage := (load("res://scenes/garage.tscn") as PackedScene).instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	await physics_frame
	garage.call("_fit_view_above_status")
	await process_frame
	await physics_frame

	var bookshelf := garage.get_node_or_null("InteractBookshelf") as StaticBody3D
	assert(bookshelf != null)
	assert(bookshelf.get_meta(&"garage_interact") == &"bookshelf")
	assert(_visible_book_meshes(bookshelf) == 0)

	# Verify bookshelf sits above the desk and does not overlap neighboring props.
	var shelf_box := _world_aabb(bookshelf)
	var desk_box := _world_aabb(garage.get_node("InteractDesk/MeshInstance3D"))
	var vodka_box := _world_aabb(garage.get_node("InteractDesk/InteractVodka"))
	var radio_shelf_box := _world_aabb(garage.get_node("InteractDesk/Shelf"))
	assert(shelf_box.position.y > desk_box.end.y)
	assert(shelf_box.position.y > vodka_box.end.y)
	assert(not shelf_box.intersects(radio_shelf_box))

	# Verify camera sees the bookshelf and raycast hits it.
	var cam := garage.get("_camera") as Camera3D
	var vp := garage.get("_view_port") as SubViewport
	assert(not cam.is_position_behind(bookshelf.global_position))
	var screen_pos := cam.unproject_position(bookshelf.global_position)
	assert(screen_pos.x > 0.0 and screen_pos.x < float(vp.size.x))
	assert(screen_pos.y > 0.0 and screen_pos.y < float(vp.size.y))
	assert(garage.call("_interact_kind_at", screen_pos) == &"bookshelf")

	# Verify PartsBoard and BooksBoard share the same window panel sizing.
	var parts_board := garage.get("_parts_board") as Control
	var books_board := garage.get("_books_board") as Control
	assert(books_board != null and not books_board.visible)
	var parts_panel := parts_board.get_child(1) as PanelContainer
	var books_panel := books_board.get_child(1) as PanelContainer
	assert(books_panel.custom_minimum_size == parts_panel.custom_minimum_size)

	# Click on the bookshelf to open BooksBoard: initially empty.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_pos
	garage.call("_unhandled_input", click)
	assert(books_board.visible)
	var books_title := garage.get("_books_title") as Label
	var books_status := garage.get("_books_status") as Label
	var books_list := garage.get("_books_list") as VBoxContainer
	var books_back := garage.get("_books_back") as Button
	assert(books_title.text == "Bookshelf")
	assert(books_status.text == "The shelf is empty.")
	assert(books_list.get_child_count() == 0)
	assert(not books_back.visible)

	# Check baseline tire grip on bias-ply (3), radial (4), and racing slicks (5) before givebook.
	var slots: Dictionary = state.get("slot_part_ids")
	slots["tires"] = "tires-bias"
	assert(is_equal_approx(float(state.call("tire_grip")), 3.0))
	slots["tires"] = "tires-radial"
	assert(is_equal_approx(float(state.call("tire_grip")), 4.0))
	slots["tires"] = "tires"
	assert(is_equal_approx(float(state.call("tire_grip")), 5.0))
	var slicks_part: Dictionary = state.call("listing_by_id", state.get("PARTS"), "tires")
	assert(str(state.call("part_detail", slicks_part)).begins_with("Grip 5"))

	# Press ` in the garage to open the console and test givebook.
	var backtick := InputEventKey.new()
	backtick.pressed = true
	backtick.keycode = KEY_QUOTELEFT
	backtick.physical_keycode = KEY_QUOTELEFT
	backtick.unicode = 0x60
	garage.call("_unhandled_input", backtick)
	var console := garage.get("_console") as Control
	assert(console != null)
	var console_out := console.get("_output") as Label

	# Missing argument and unknown book id handling.
	console.call("_on_submitted", "givebook")
	assert(console_out.text == "Usage: givebook <ID>")
	console.call("_on_submitted", "givebook no-such-book")
	assert(console_out.text.begins_with("Unknown book:"))
	assert((state.call("owned_books") as Array).is_empty())

	# Existing zero-arg console commands still work, and reject stray args.
	var cash_before: int = int(state.get("money"))
	console.call("_on_submitted", "inherit")
	assert(int(state.get("money")) > cash_before)

	# Add hellmark-racing-slicks via console command.
	console.call("_on_submitted", "givebook hellmark-racing-slicks")
	assert(state.call("owns_book", "hellmark-racing-slicks"))
	assert(_visible_book_meshes(bookshelf) == 1)
	assert(books_list.get_child_count() == 1)

	# Duplicate copy on the bookshelf shows up as a second physical copy, without multiplying bonuses.
	console.call("_on_submitted", "givebook hellmark-racing-slicks")
	assert((state.call("owned_books") as Array).size() == 1)
	assert(int(state.call("book_count", "hellmark-racing-slicks")) == 2)
	assert(_visible_book_meshes(bookshelf) == 2)
	var row_label := (books_list.get_child(0) as HBoxContainer).get_child(0) as Label
	assert(row_label.text.contains("×2"))

	# Close console with ` so garage shortcuts work again.
	root.push_input(backtick)
	await process_frame
	assert(garage.get("_console") == null)

	# Verify racing slicks grip increased by 1 (to 6), while bias and radial stay 3 and 4.
	assert(is_equal_approx(float(state.call("tire_grip")), 6.0))
	assert(str(state.call("part_detail", slicks_part)).begins_with("Grip 6"))
	slots["tires"] = "tires-bias"
	assert(is_equal_approx(float(state.call("tire_grip")), 3.0))
	slots["tires"] = "tires-radial"
	assert(is_equal_approx(float(state.call("tire_grip")), 4.0))
	slots["tires"] = "tires"

	# Driving models apply grip 6 without clamping at 5; opponents do not get player's book bonus.
	var arcade := _ArcadeDrive.new()
	arcade.apply_spec(state.call("race_chassis"), float(state.call("tire_grip")))
	assert(is_equal_approx(float(arcade.get("_wheel_grip")), 6.0))
	var dyn := _VehicleDynamics.new()
	dyn.apply_setup(state.call("race_chassis"), 5.0)
	var mu_before := float(dyn.get("_tire_grip"))
	dyn.apply_setup(state.call("race_chassis"), float(state.call("tire_grip")))
	assert(float(dyn.get("_tire_grip")) > mu_before)
	dyn.free()
	assert(is_equal_approx(float(state.call("opponent_tire_grip", {"tires": "tires"})), 5.0))

	# Press 1 in BooksBoard to read the book, then Esc back to list and Esc to close.
	var key_1 := InputEventKey.new()
	key_1.pressed = true
	key_1.keycode = KEY_1
	garage.call("_unhandled_input", key_1)
	assert(books_board.visible and books_back.visible)
	assert(books_title.text == "Hellmark's guide to racing slicks")
	assert(books_list.get_child_count() >= 1)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	assert(books_board.visible and not books_back.visible)
	root.push_input(esc)
	assert(not books_board.visible)

	# Verify hellmark-flathead increases hp by 3 across every owned car with a Ford flathead,
	# and by 0 when a Chevy small-block is mounted.
	var corvette_id := str(state.get("current_car_id"))
	var corvette_hp_before := float(state.get("engine_power_hp"))
	assert(str(state.call("editor_add_car", "ford-coupe-1932")) == "")
	assert(str(state.call("editor_add_car", "ford-coupe-1932")) == "")
	var owned_cars: Array = state.get("owned_car_ids")
	assert(owned_cars.size() == 3)
	var flathead_car_a := str(owned_cars[1])
	var flathead_car_b := str(owned_cars[2])

	assert(str(state.call("select_owned_car", flathead_car_a)) == "")
	var flathead_a_hp_before := float(state.get("engine_power_hp"))
	assert(str(state.call("select_owned_car", flathead_car_b)) == "")
	var flathead_b_hp_before := float(state.get("engine_power_hp"))

	# Open console and run `givebook hellmark-flathead` twice to confirm duplicate flathead books don't multiply hp.
	garage.call("_unhandled_input", backtick)
	console = garage.get("_console") as Control
	assert(console != null)
	console.call("_on_submitted", "givebook hellmark-flathead")
	console.call("_on_submitted", "givebook hellmark-flathead")
	assert(state.call("owns_book", "hellmark-flathead"))
	assert(int(state.call("book_count", "hellmark-flathead")) == 2)
	assert(_visible_book_meshes(bookshelf) == 4)
	root.push_input(backtick)
	await process_frame

	# Active flathead car B immediately gained +3 hp; flathead car A also has +3 hp; Corvette (SBC) +0 hp.
	assert(is_equal_approx(float(state.get("engine_power_hp")), flathead_b_hp_before + 3.0))
	assert(str(state.call("select_owned_car", flathead_car_a)) == "")
	assert(is_equal_approx(float(state.get("engine_power_hp")), flathead_a_hp_before + 3.0))
	assert(str(state.call("select_owned_car", corvette_id)) == "")
	assert(is_equal_approx(float(state.get("engine_power_hp")), corvette_hp_before))

	# Verify books for the other defined engine families: chevy-sbc (+5), ford-yblock (+4), ford-windsor (+5).
	assert(str(state.call("editor_add_car", "chevy-styleline-1950")) == "")
	assert(str(state.call("editor_add_car", "fairlane-1957")) == "")
	assert(str(state.call("editor_add_car", "ford-f100-1970")) == "")
	owned_cars = state.get("owned_car_ids")
	var styleline_id := str(owned_cars[3])
	var fairlane_id := str(owned_cars[4])
	var f100_id := str(owned_cars[5])

	assert(str(state.call("select_owned_car", styleline_id)) == "")
	var styleline_hp_before := float(state.get("engine_power_hp"))
	assert(str(state.call("select_owned_car", fairlane_id)) == "")
	var fairlane_hp_before := float(state.get("engine_power_hp"))
	assert(str(state.call("select_owned_car", f100_id)) == "")
	var f100_hp_before := float(state.get("engine_power_hp"))

	garage.call("_unhandled_input", backtick)
	console = garage.get("_console") as Control
	assert(console != null)
	console.call("_on_submitted", "givebook hellmark-sbc")
	console.call("_on_submitted", "givebook hellmark-yblock")
	console.call("_on_submitted", "givebook hellmark-windsor")
	assert(_visible_book_meshes(bookshelf) == 7)
	root.push_input(backtick)
	await process_frame

	assert(is_equal_approx(float(state.get("engine_power_hp")), f100_hp_before + 5.0))
	assert(str(state.call("select_owned_car", fairlane_id)) == "")
	assert(is_equal_approx(float(state.get("engine_power_hp")), fairlane_hp_before + 4.0))
	assert(str(state.call("select_owned_car", styleline_id)) == "")
	assert(is_equal_approx(float(state.get("engine_power_hp")), styleline_hp_before + 5.0))
	assert(str(state.call("select_owned_car", corvette_id)) == "")
	assert(is_equal_approx(float(state.get("engine_power_hp")), corvette_hp_before + 5.0))

	# Save and load round-trip preserves duplicate copies without multiplying bonuses, plus legacy save fallback (empty).
	assert(str(state.call("select_owned_car", flathead_car_a)) == "")
	assert(state.call("save_game", 1))
	state.call("new_game")
	assert((state.call("owned_books") as Array).is_empty())
	assert(state.call("load_game", 1))
	assert(state.call("owns_book", "hellmark-racing-slicks"))
	assert(state.call("owns_book", "hellmark-flathead"))
	assert(int(state.call("book_count", "hellmark-racing-slicks")) == 2)
	assert(int(state.call("book_count", "hellmark-flathead")) == 2)
	assert(is_equal_approx(float(state.get("engine_power_hp")), flathead_a_hp_before + 3.0))

	var save_path := str(state.call("save_slot_path", 1))
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	parsed.erase("owned_book_ids")
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(parsed))
	f.close()
	assert(state.call("load_game", 1))
	assert((state.call("owned_books") as Array).is_empty())
	assert(is_equal_approx(float(state.get("engine_power_hp")), flathead_a_hp_before))

	garage.free()
	await process_frame

	# Verify post-race book offer odds (10% * bet-amount / 100) and eligible race types.
	assert(is_equal_approx(float(state.call("book_offer_chance", -10)), 0.0))
	assert(is_equal_approx(float(state.call("book_offer_chance", 0)), 0.0))
	assert(is_equal_approx(float(state.call("book_offer_chance", 25)), 0.025))
	assert(is_equal_approx(float(state.call("book_offer_chance", 50)), 0.05))
	assert(is_equal_approx(float(state.call("book_offer_chance", 100)), 0.10))
	assert(is_equal_approx(float(state.call("book_offer_chance", 500)), 0.50))
	assert(is_equal_approx(float(state.call("book_offer_chance", 1000)), 1.0))
	assert(is_equal_approx(float(state.call("book_offer_chance", 2500)), 1.0))

	assert(bool(state.call("race_can_offer_book", "road")))
	assert(bool(state.call("race_can_offer_book", "aqueduct")))
	assert(bool(state.call("race_can_offer_book", "mulholland")))
	assert(not bool(state.call("race_can_offer_book", "drag")))
	assert(not bool(state.call("race_can_offer_book", "street_drag")))
	assert(not bool(state.call("race_can_offer_book", "stunt")))

	# Eligible races offer at roll < chance and decline at roll >= chance; ineligible races / $0 bets never offer.
	for eligible_race: String in ["road", "aqueduct", "mulholland"]:
		var hit: Dictionary = state.call("roll_race_book_offer", 25, eligible_race, 0.024, 0)
		var miss: Dictionary = state.call("roll_race_book_offer", 25, eligible_race, 0.025, 0)
		var free_race: Dictionary = state.call("roll_race_book_offer", 0, eligible_race, 0.0, 0)
		assert(not hit.is_empty() and str(hit.get("id", "")) == str((catalog[0] as Dictionary).get("id", "")))
		assert(miss.is_empty())
		assert(free_race.is_empty())
	for ineligible_race: String in ["drag", "street_drag", "stunt"]:
		var never_offered: Dictionary = state.call("roll_race_book_offer", 1000, ineligible_race, 0.0, 0)
		assert(never_offered.is_empty())

	# Random selection samples across BOOKS.
	var picked_ids: Dictionary = {}
	for n: int in 120:
		var rolled_book: Dictionary = state.call("roll_race_book_offer", 1000, "road", 0.0)
		assert(not rolled_book.is_empty())
		picked_ids[str(rolled_book.get("id", ""))] = true
	assert(picked_ids.size() > 1)

	# End-to-end race UI test: winning a money bet on Road Race, Aqueduct, and Mulholland Drive.
	state.call("new_game")
	state.set("selected_race_type", "road")
	state.set("race_stake", 1000) # 10% * 1000 / 100 = 100% offer chance
	state.set("race_pink_slips", false)
	var cash_start: int = int(state.get("money"))

	var race := (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	current_scene = race
	await process_frame
	await physics_frame

	# Win Road Race -> opponent proposes a book instead of $1000. Accept the book: book added, money unchanged.
	race.call("_show_result", true)
	var offer_root := race.get("_book_offer_root") as Control
	var accept_btn := race.get("_book_offer_accept") as Button
	var decline_btn := race.get("_book_offer_decline") as Button
	var result_panel := race.get("_result") as Control
	assert(offer_root != null and offer_root.visible)
	assert(not result_panel.visible)
	assert(int(state.get("money")) == cash_start)
	assert(int(state.get("race_stake")) == 0)
	var offered_first: Dictionary = race.get("_offered_book")
	var first_id := str(offered_first.get("id", ""))
	assert(not first_id.is_empty())

	accept_btn.emit_signal("pressed")
	assert(not offer_root.visible)
	assert(result_panel.visible)
	assert(str(race.get("_result_scene")) == "res://scenes/drive-in.tscn")
	assert(state.call("owns_book", first_id))
	assert(int(state.call("book_count", first_id)) == 1)
	assert(int(state.get("money")) == cash_start)

	# Decline on Aqueduct: player gets the cash payout instead of the book.
	result_panel.visible = false
	state.set("selected_race_type", "aqueduct")
	state.set("race_stake", 1000)
	race.call("_show_result", true)
	assert(offer_root.visible)
	assert(int(state.get("money")) == cash_start)
	decline_btn.emit_signal("pressed")
	assert(not offer_root.visible)
	assert(result_panel.visible)
	assert(int(state.get("money")) == cash_start + 1000)
	assert((state.get("owned_book_ids") as Array).size() == 1)

	# Rival-wreck win on Mulholland Drive also proposes a book instead of cash; duplicate book does not multiply bonus.
	result_panel.visible = false
	state.set("selected_race_type", "mulholland")
	state.set("race_stake", 1000)
	race.call("_show_rival_wreck")
	assert(offer_root.visible)
	race.call("_show_book_offer", state.call("book_by_id", "hellmark-sbc"), 1000, "Rival's car is totaled!")
	var sbc_hp_before_book := float(state.get("engine_power_hp"))
	if state.call("owns_book", "hellmark-sbc"):
		sbc_hp_before_book -= 5.0
	accept_btn.emit_signal("pressed")
	assert(state.call("owns_book", "hellmark-sbc"))
	assert(is_equal_approx(float(state.get("engine_power_hp")), sbc_hp_before_book + 5.0))
	# Accepting a duplicate copy of hellmark-sbc increases book_count, NOT engine_power_hp.
	result_panel.visible = false
	race.call("_show_book_offer", state.call("book_by_id", "hellmark-sbc"), 100, "")
	accept_btn.emit_signal("pressed")
	assert(int(state.call("book_count", "hellmark-sbc")) >= 2)
	assert(is_equal_approx(float(state.get("engine_power_hp")), sbc_hp_before_book + 5.0))

	# Drag race win with $1000 stake never proposes a book; pays cash immediately.
	result_panel.visible = false
	var cash_before_drag := int(state.get("money"))
	state.set("selected_race_type", "drag")
	state.set("race_stake", 1000)
	race.call("_show_result", true)
	assert(not offer_root.visible)
	assert(result_panel.visible)
	assert(int(state.get("money")) == cash_before_drag + 1000)

	race.free()
	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(save_dir)
	print("garage_bookshelf_test passed!")
	quit(0)
