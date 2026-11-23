extends SceneTree

## A fine the player cannot pay opens the drive-in from a cell. The diner is there,
## the bars are in front of the camera, and the only exit is the main menu.


func _initialize() -> void:
	call_deferred("_run")


func _first_label(node: Node) -> Label:
	if node is Label:
		return node as Label
	for child: Node in node.get_children():
		var found := _first_label(child)
		if found != null:
			return found
	return null


func _run() -> void:
	var state := root.get_node("GameState")
	state.call("new_game")
	assert(not bool(state.get("jailed")), "A new game is not a jail sentence")
	state.set("jailed", true)
	state.set("money", 40)

	var packed := load(str(state.get("SCENE_DRIVE_IN"))) as PackedScene
	assert(change_scene_to_packed(packed) == OK)
	await process_frame
	await process_frame
	var drive_in := current_scene
	assert(bool(drive_in.get("_jailed")), "The cell is up")
	assert(not bool(state.get("jailed")), "The sentence is read once")
	assert(str(state.get("current_scene_path")) == str(state.get("SCENE_GARAGE")), "A save from here resumes at the garage")
	assert(int(state.get("money")) == 40, "Jail takes nothing")

	var bars := drive_in.get_node("Camera3D/Bars") as Node3D
	assert(bars != null and bars.get_child_count() > 0, "Bars stand in front of the lens")
	var menu := drive_in.get_node("UI/JailMenu/MainMenu") as Button
	assert(menu != null and menu.text == "Main menu", "The only choice is the main menu")
	assert(drive_in.get_node_or_null("UI/HudBottom") == null, "The diner's own menu stays down")
	var fine := drive_in.get_node("UI/Fine") as Control
	assert(fine != null and fine.visible, "The fine is a speech bubble")
	var fine_label := _first_label(fine)
	assert(fine_label != null and fine_label.text == "You can't pay the fine.", "The bubble says the fine cannot be paid")
	var man := drive_in.find_child("Organizer", true, false) as StaticBody3D
	assert(man != null and not man.input_ray_pickable, "The organizer cannot be talked to")
	var roster: int = (state.get("opponents") as Array).size()
	var rival := drive_in.find_child("RivalCar", true, false) as StaticBody3D
	assert(rival != null and not rival.input_ray_pickable, "A rival drives through and cannot be clicked")
	drive_in.call("_begin_rival_leave")
	drive_in.call("_advance_rival", 30.0)
	assert(drive_in.get("_rival") == null, "The rival drives off")
	assert(fine.visible, "The bubble stays up after the car leaves")
	drive_in.call("_summon_jail_car")
	var next := drive_in.get("_rival") as StaticBody3D
	assert(next != null and is_instance_valid(next) and not next.input_ray_pickable, "Another rival drives in")
	assert((state.get("opponents") as Array).size() == roster, "Watching them adds nobody to the roster")

	drive_in.call("_leave_jail")
	assert(not bool(drive_in.get("_jailed")), "Leaving clears the cell")
	await process_frame
	await process_frame
	assert(str(state.get("current_scene_path")) == str(state.get("SCENE_MAIN_MENU")))
	assert(current_scene != null and current_scene.name == "MainMenu", "The main menu replaces the cell")
	print("jail_test: OK")
	quit(0)
