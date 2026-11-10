extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	var save_dir := "user://royal-rods-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.set("save_dir", save_dir)
	state.set("legacy_save_path", "")
	var track: Dictionary = TrackFile.load_path("res://assets/maps/city.trk")
	assert(track["errors"].is_empty())
	assert(TrackFile.cruise_route(track, "garage", "royal-rods").size() >= 2)
	assert(TrackFile.cruise_route(track, "royal-rods", "garage").size() >= 2)

	var garage := (load("res://scenes/garage.tscn") as PackedScene).instantiate()
	assert(garage.call("_scene_for_poi", "royal-rods") == state.SCENE_ROYAL_RODS)
	assert(garage.call("_poi_for_scene", state.SCENE_ROYAL_RODS) == "royal-rods")
	garage.free()
	var cruise := (load("res://scenes/cruise.tscn") as PackedScene).instantiate()
	assert(cruise.call("_scene_for_roam", "royal-rods") == state.SCENE_ROYAL_RODS)
	var building := Node3D.new()
	cruise.call("_build_royal_rods", building)
	var exterior_sign := building.get_node("RoyalRodsSign") as Node3D
	assert(exterior_sign.basis.z.dot(Vector3.BACK) < -0.99)
	var exterior_signature := (exterior_sign.get_node("KingsSignature") as Sprite3D).texture
	cruise.free()

	var store := (load("res://scenes/royal_rods.tscn") as PackedScene).instantiate()
	root.add_child(store)
	current_scene = store
	await process_frame
	assert(state.current_scene_path == state.SCENE_ROYAL_RODS)
	var interior_sign := store.get_node("RoyalRodsSign") as Node3D
	assert(interior_sign.basis.z.dot(Vector3.BACK) > 0.99)
	assert((interior_sign.get_node("KingsSignature") as Sprite3D).texture == exterior_signature)
	assert((interior_sign.get_node("Title") as Label3D).text == "ROYAL RODS")
	assert((interior_sign.get_node("Tagline") as Label3D).text == "SPEED EQUIPMENT  •  AUTO PARTS")
	building.free()
	var king_poster := store.get_node("KingPoster") as Sprite3D
	var scene_poster := store.get_node("KingScenePoster") as Sprite3D
	assert(king_poster.texture.resource_path == "res://assets/locations/city/theking-poster.jpg")
	assert(scene_poster.texture.resource_path == "res://assets/locations/city/king-scene-poster.jpg")
	assert(king_poster.position.x < 0.0 and scene_poster.position.x > 0.0)
	assert(is_equal_approx(king_poster.position.z, scene_poster.position.z))
	var poster_paths := [
		"res://assets/locations/city/poster1.png",
		"res://assets/locations/city/poster2.jpg",
		"res://assets/locations/city/poster3.webp",
		"res://assets/locations/city/poster4.jpg",
		"res://assets/locations/city/poster5.jpg",
	]
	var wall_posters: Array[Sprite3D] = []
	for i in poster_paths.size():
		var poster := store.get_node("WallPoster%d" % (i + 1)) as Sprite3D
		assert(poster.texture.resource_path == poster_paths[i])
		assert(poster.position.x > 6.0)
		assert(poster.global_basis.z.dot(Vector3.LEFT) > 0.99)
		wall_posters.append(poster)
	for i in wall_posters.size():
		for j in range(i + 1, wall_posters.size()):
			var a := wall_posters[i]
			var b := wall_posters[j]
			var half_widths := (a.texture.get_width() * a.pixel_size + b.texture.get_width() * b.pixel_size) / 2.0 + 0.12
			var half_heights := (a.texture.get_height() * a.pixel_size + b.texture.get_height() * b.pixel_size) / 2.0 + 0.12
			var horizontal_gap := absf(a.position.z - b.position.z) - half_widths
			var vertical_gap := absf(a.position.y - b.position.y) - half_heights
			assert(horizontal_gap >= 0.3 or vertical_gap >= 0.3)
	var catalog := store.get("_catalog") as Control
	var camera := store.get_node("Camera3D") as Camera3D
	var counter_label: Label3D
	var counter_trim: MeshInstance3D
	for child in store.get_children():
		if child is Label3D and child.text == "NEW PARTS":
			counter_label = child
		elif child is MeshInstance3D and child.mesh is BoxMesh and child.mesh.size.is_equal_approx(Vector3(5.15, 0.08, 0.04)):
			counter_trim = child
	assert(counter_label != null and counter_trim != null)
	var label_bottom := counter_label.position.y + counter_label.get_aabb().position.y
	var trim_top := counter_trim.position.y + (counter_trim.mesh as BoxMesh).size.y / 2.0
	assert(label_bottom - trim_top > 0.1)
	var folder := store.get_node("PartsFolder") as Area3D
	await physics_frame
	var folder_screen := camera.unproject_position(folder.global_position)
	assert(store.call("_folder_at", folder_screen))
	assert(not store.call("_folder_at", Vector2(0, 0)))
	assert(store.call("_hint_at", folder_screen, null) == "Browse all new parts (P)")
	assert(store.call("_hint_at", Vector2.ZERO, null) == "")
	var back := store.get("_back") as Button
	var town := store.get("_town") as Button
	assert(store.call("_hint_at", Vector2.ZERO, back) == "Return to the garage (G)")
	assert(store.call("_hint_at", Vector2.ZERO, town) == "Cruise around town (D)")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var viewer := store.get("_poster_viewer") as Control
	var image := store.get("_poster_image") as TextureRect
	var posters: Array[Sprite3D] = [king_poster, scene_poster]
	posters.append_array(wall_posters)
	for poster: Sprite3D in posters:
		click.position = camera.unproject_position(poster.global_position)
		assert(store.call("_display_at", click.position) == poster.get_node("PosterHitbox"))
		assert(store.call("_hint_at", click.position, null) == "View poster")
		store.call("_unhandled_input", click)
		assert(viewer.visible and image.texture == poster.texture)
		assert(store.call("_hint_at", folder_screen, null) == "")
		assert(store.call("_hint_at", Vector2.ZERO, store.get("_poster_close")) == "Close the poster (Esc)")
		var poster_target: Rect2 = store.call("_poster_target_rect")
		var available := viewer.size * 0.9 - Vector2(0, (store.get("_poster_close") as Button).get_combined_minimum_size().y + 12.0)
		var texture_size := poster.texture.get_size()
		var previous_size := texture_size * minf(available.x / texture_size.x, available.y / texture_size.y)
		assert(poster_target.size.is_equal_approx(previous_size * 0.9))
		assert(is_equal_approx(poster_target.size.aspect(), poster.texture.get_size().aspect()))
		assert(not catalog.visible)
		var shortcut_during_view := InputEventKey.new()
		shortcut_during_view.keycode = KEY_P
		shortcut_during_view.pressed = true
		store.call("_unhandled_input", shortcut_during_view)
		assert(not catalog.visible and viewer.visible)
		var cancel := InputEventAction.new()
		cancel.action = &"ui_cancel"
		cancel.pressed = true
		store.call("_input", cancel)
		assert(viewer.visible and not poster.visible)
		store.call("_input", cancel)
		await create_timer(0.5).timeout
		assert(not viewer.visible and image.texture == null and poster.visible)
	click.position = camera.unproject_position(king_poster.global_position)
	store.call("_unhandled_input", click)
	var initial_size := image.size
	var target: Rect2 = store.call("_poster_target_rect")
	assert(initial_size.x < target.size.x and initial_size.y < target.size.y)
	assert(not king_poster.visible)
	await create_timer(0.2).timeout
	assert(image.size.x > initial_size.x and image.size.x < target.size.x)
	await create_timer(0.3).timeout
	assert(image.size.is_equal_approx(target.size))
	assert(image.position.is_equal_approx(target.position))
	assert(image.size.x <= viewer.size.x * 0.9 and image.size.y <= viewer.size.y * 0.9)
	assert(image.position.x >= viewer.size.x * 0.05 - 0.01)
	assert(image.position.y >= viewer.size.y * 0.05 - 0.01)
	assert((image.position.x + image.size.x) <= viewer.size.x * 0.95 + 0.01)
	assert((image.position.y + image.size.y) <= viewer.size.y * 0.95 + 0.01)
	(store.get("_poster_close") as Button).pressed.emit()
	assert(viewer.visible and not king_poster.visible)
	await create_timer(0.2).timeout
	assert(viewer.visible and image.size.x < target.size.x and image.size.x > initial_size.x)
	assert(not king_poster.visible)
	await create_timer(0.3).timeout
	assert(not viewer.visible and king_poster.visible)
	click.position = camera.unproject_position(scene_poster.global_position)
	store.call("_unhandled_input", click)
	store.call("_close_poster")
	store.call("_resize_poster_viewer")
	assert(not viewer.visible and scene_poster.visible and image.texture == null)
	click.position = folder_screen
	store.call("_unhandled_input", click)
	assert(catalog.visible)
	assert(store.get("_catalog_list").get_child_count() > 4)
	assert(store.call("_hint_at", folder_screen, null) == "")
	for row: Node in store.get("_catalog_list").get_children():
		if row is Button:
			assert(str(store.call("_hint_at", Vector2.ZERO, row)).begins_with("Buy "))
			break
	store.call("_close_catalog")
	assert(not catalog.visible)
	click.position = Vector2.ZERO
	store.call("_unhandled_input", click)
	assert(not catalog.visible)
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_P
	shortcut.pressed = true
	store.call("_unhandled_input", shortcut)
	assert(catalog.visible)
	store.call("_close_catalog")
	var displayed: Dictionary = {
		"engine": state.ENGINES,
		"transmission": state.GEARBOXES,
		"wheels": state.WHEELS,
	}
	var register_file := FileAccess.open(state.PARTS_REGISTER, FileAccess.READ)
	assert(register_file != null)
	var register: Variant = JSON.parse_string(register_file.get_as_text())
	assert(register is Dictionary)
	var group_filters := {
		"heads": ["heads"], "intake": ["intake"], "fuel": ["carb", "air_cleaner"],
		"ignition": ["distributor"], "cam": ["cam"], "tires": ["tires"],
		"headers": ["manifold"], "exhaust": ["exhaust", "muffler"],
		"differential": ["differential"], "suspension": ["springs", "shocks"],
		"mounts": [],
	}
	var expected_parts: Dictionary = {}
	for group: String in PartsRegister.PART_GROUPS:
		assert(group_filters.has(group))
		assert(register.has(group) and register[group] is Array and not register[group].is_empty())
		for filter: String in group_filters[group]:
			assert(not displayed.has(filter))
			displayed[filter] = []
		for source: Dictionary in register[group]:
			var base := str(source["id"])
			var filters: Array = group_filters[group]
			var filter := ""
			if filters.size() == 1:
				filter = filters[0]
			elif filters.size() > 1:
				filter = str(source.get("slot", ""))
				assert(filters.has(filter))
			else:
				assert(group == "mounts" and source.get("mounts", false))
			var variants: Array = source.get("families", source.get("makes", []))
			var variant_count := maxi(variants.size(), 1)
			for i in variant_count:
				var id := base if i == 0 else "%s-%s" % [base, str(variants[i]).to_lower()]
				assert(not expected_parts.has(id))
				expected_parts[id] = {"base": base, "filter": filter}
	assert(expected_parts.size() == state.PARTS.size())
	for part: Dictionary in state.PARTS:
		var id := str(part["id"])
		assert(expected_parts.has(id))
		var expected: Dictionary = expected_parts[id]
		assert(str(part.get("base", "")) == expected["base"])
		var filter := str(expected["filter"])
		assert(str(part.get("slot", "")) == filter)
		if not filter.is_empty():
			displayed[filter].append(part)
		expected_parts.erase(id)
	assert(expected_parts.is_empty())
	for kind: String in displayed:
		if kind == "wheels" or kind == "tires":
			continue
		var first_child := store.get_child_count()
		store.call("_shelf_stock", 100.0, 100.0, kind)
		var lowest := [INF, INF]
		for i in range(first_child, store.get_child_count()):
			var stock := store.get_child(i) as MeshInstance3D
			assert(stock != null)
			var bounds := stock.transform * stock.mesh.get_aabb()
			var copy := 0 if stock.position.x < 100.0 else 1
			lowest[copy] = minf(float(lowest[copy]), bounds.position.y)
		assert(absf(float(lowest[0]) - 100.0) < 0.001)
		assert(absf(float(lowest[1]) - 100.0) < 0.001)
		while store.get_child_count() > first_child:
			store.get_child(first_child).free()
	var wheel_stand := store.get_node("Stand_wheels") as Node3D
	var tire_stand := store.get_node("Stand_tires") as Node3D
	assert(wheel_stand.global_position.x < 0.0)
	assert(is_equal_approx(wheel_stand.global_position.x, tire_stand.global_position.x))
	assert(absf(wheel_stand.global_position.z - tire_stand.global_position.z) >= 1.3)
	assert(wheel_stand.global_basis.z.dot(Vector3.RIGHT) > 0.99)
	assert(tire_stand.global_basis.z.dot(Vector3.RIGHT) > 0.99)
	for stand: Node3D in [wheel_stand, tire_stand]:
		var bottom := INF
		for child: Node in stand.get_children():
			if child is MeshInstance3D:
				var mesh := child as MeshInstance3D
				var bounds := mesh.global_transform * mesh.mesh.get_aabb()
				bottom = minf(bottom, bounds.position.y)
		assert(absf(bottom) < 0.001)
	for kind: String in displayed:
		var path := "Stand_%s/Shelf_%s" % [kind, kind] if kind in ["wheels", "tires"] else "Shelf_" + kind
		var shelf := store.get_node(path) as Area3D
		click.position = camera.unproject_position(shelf.global_position)
		assert(store.call("_display_at", click.position) == shelf)
		assert(store.call("_hint_at", click.position, null) == "Browse %s" % str(store.call("_filter_name", kind)).to_lower())
		store.call("_unhandled_input", click)
		assert(catalog.visible)
		var visible_ids: Array[String] = []
		for row: Node in store.get("_catalog_list").get_children():
			if row is Button and (row as Button).visible:
				assert(row.get_meta("catalog_filter") == kind)
				visible_ids.append(str(row.get_meta("part_id")))
		assert(visible_ids.size() == displayed[kind].size())
		for item: Dictionary in displayed[kind]:
			assert(visible_ids.has(str(item["id"])))
		if kind == "carb":
			state.money = 100000
			var id := str(displayed[kind][0]["id"])
			var before: int = state.free_spare_count("part", id)
			for row: Node in store.get("_catalog_list").get_children():
				if row is Button and (row as Button).visible and str(row.get_meta("part_id")) == id:
					(row as Button).pressed.emit()
					break
			assert(state.free_spare_count("part", id) == before + 1)
			assert((store.get("_status") as Label).text.contains("Bought"))
		store.call("_close_catalog")
	store.call("_open_catalog")
	var full_catalog_ids: Dictionary = {}
	for row: Node in store.get("_catalog_list").get_children():
		assert((row as Control).visible)
		if row is Button:
			var id := str(row.get_meta("part_id"))
			full_catalog_ids[id] = int(full_catalog_ids.get(id, 0)) + 1
	for items: Array in [state.ENGINES, state.GEARBOXES, state.WHEELS, state.PARTS]:
		for item: Dictionary in items:
			var id := str(item["id"])
			assert(int(full_catalog_ids.get(id, 0)) > 0)
			full_catalog_ids[id] -= 1
			if full_catalog_ids[id] == 0:
				full_catalog_ids.erase(id)
	assert(full_catalog_ids.is_empty())
	assert(not store.has_node("Shelf_mounts"))
	store.call("_close_catalog")

	state.roll_newspaper_wear()
	state.money = 100000
	var categories: Array = [
		["engine", state.ENGINES],
		["transmission", state.GEARBOXES],
		["wheels", state.WHEELS],
		["part", state.PARTS],
	]
	for category: Array in categories:
		var kind := str(category[0])
		var item: Dictionary = category[1][0]
		var id := str(item["id"])
		var before_money: int = state.money
		var before_count: int = state.free_spare_count(kind, id)
		var newspaper: Array = state.newspaper_copies(kind, id)
		assert(state.buy_new_part(kind, id).is_empty())
		assert(state.money == before_money - int(item["price"]))
		assert(state.free_spare_count(kind, id) == before_count + 1)
		assert(state.spare_condition_list(kind, id).has(1.0))
		assert(state.newspaper_copies(kind, id) == newspaper)
	var cash: int = state.money
	assert(not state.buy_new_part("invalid", "heads-iron").is_empty())
	assert(not state.buy_new_part("part", "missing").is_empty())
	assert(state.money == cash)
	state.money = 0
	var count: int = state.free_spare_count("part", "heads-iron")
	assert(not state.buy_new_part("part", "heads-iron").is_empty())
	assert(state.money == 0 and state.free_spare_count("part", "heads-iron") == count)
	state.money = 100000
	store.call("_buy", "part", "heads-iron")
	assert(state.free_spare_count("part", "heads-iron") == count + 1)
	assert((store.get("_status") as Label).text.contains("Bought"))
	count += 1

	assert(state.save_game(1))
	state.owned_part_ids.clear()
	state.spare_conditions.clear()
	assert(state.load_game(1))
	assert(state.free_spare_count("part", "heads-iron") == count)
	assert(state.spare_condition_list("part", "heads-iron").has(1.0))
	assert(state.current_scene_path == state.SCENE_ROYAL_RODS)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(save_dir.path_join("slot_1.json"))) == OK)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(save_dir)) == OK)

	store.call("_leave", true)
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == state.SCENE_CRUISE)
	assert(current_scene.get("_destination") == state.SCENE_GARAGE)
	assert(current_scene.get("_pts").size() >= 2)
	assert(state.drive_into_garage)
	change_scene_to_file(state.SCENE_ROYAL_RODS)
	await process_frame
	await process_frame
	current_scene.call("_leave", false)
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == state.SCENE_CRUISE)
	assert(current_scene.get("_roaming"))
	assert(current_scene.get("_roam_home") == state.POI_ROYAL_RODS)
	current_scene.call("_enter_roam_place", state.POI_ROYAL_RODS)
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == state.SCENE_ROYAL_RODS)
	print("Royal Rods integration checks passed.")
	quit()
