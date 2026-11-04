extends Control

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _CarVisual := preload("res://scenes/car_vehicle_visual.tscn")
const _SpeechBubble := preload("res://scenes/speech_bubble.tscn")
const _PartPreview := preload("res://scripts/part_preview.gd")

const _CAR_CAM_FROM := Vector3(5.6, 2.1, 8.2)
const _CAR_CAM_AT := Vector3(0.0, 0.8, 0.0)

const SECTION_INDEX := "index"
const SECTION_CARS := "cars"
const SECTION_PARTS := "parts"
const _NO_ROOM_LINES: Array[String] = [
	"You've got no room for all these cars!",
	"Sell some cars first!",
]

@onready var _cash: Label = %CashLabel
@onready var _parts_list: VBoxContainer = %PartsList
@onready var _cars_list: VBoxContainer = %CarsList
@onready var _status: Label = %StatusLabel
@onready var _index_section: VBoxContainer = %IndexSection
@onready var _cars_section: VBoxContainer = %CarsSection
@onready var _parts_section: VBoxContainer = %PartsSection
@onready var _back_button: Button = $Margin/VBox/BackButton
@onready var _preview_overlay: Control = %PreviewOverlay
@onready var _preview_caption: Label = %PreviewCaption
@onready var _preview_frame: SubViewportContainer = %PreviewFrame
@onready var _preview_mount: Node3D = %PreviewMount
@onready var _preview_floor: MeshInstance3D = %Floor
@onready var _preview_camera: Camera3D = %PreviewCamera
@onready var _preview_back: Button = %PreviewBack

var _section: String = SECTION_INDEX
var _nav := _MenuNav.new()
var _preview_car_id: String = ""
var _preview_part_id: String = ""
var _preview_copy: int = -1
var _preview_pivot: Node3D
var _preview_subject: Node3D
var _no_room: Control


func _ready() -> void:
	if GameState.is_ruined():
		GameState.finish_run()
		return
	GameState.current_scene_path = GameState.SCENE_NEWSPAPER
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_frame_car_camera()
	GameState.roll_newspaper_colors()
	GameState.roll_newspaper_wear()
	_build_no_room_bubble()
	_show_section(SECTION_INDEX)
	_refresh()


func _process(delta: float) -> void:
	if not _preview_overlay.visible or not _preview_frame.visible:
		return
	_preview_mount.rotate_y(delta * 0.35)


func _unhandled_input(event: InputEvent) -> void:
	if _no_room != null and _no_room.visible:
		if event.is_action_pressed(&"ui_cancel"):
			_dismiss_no_room_line()
		_mark_input_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		_on_back_pressed()
		return
	if _nav.handle_event(self, event):
		accept_event()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return
	var code: Key = key.keycode
	if code == KEY_U or code == KEY_C:
		_show_section(SECTION_CARS)
		_mark_input_handled()
	elif code == KEY_P or code == KEY_A:
		_show_section(SECTION_PARTS)
		_mark_input_handled()


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _refresh() -> void:
	_cash.text = "Cash on hand: $%d" % GameState.money
	_rebuild_parts()
	_rebuild_cars()
	_wire_menu()


func _rebuild_parts() -> void:
	for child in _parts_list.get_children():
		# Out of the list now, or the keys pick up rows that are about to be freed.
		_parts_list.remove_child(child)
		child.queue_free()
	_parts_list.add_child(_heading("ENGINES"))
	for engine: Dictionary in GameState.ENGINES:
		_add_part_ads(engine, "engine")
	_parts_list.add_child(_heading("TRANSMISSIONS"))
	for box: Dictionary in GameState.GEARBOXES:
		_add_part_ads(box, "transmission")
	_parts_list.add_child(_heading("WHEELS"))
	for wheel: Dictionary in GameState.WHEELS:
		_add_part_ads(wheel, "wheels")
	_parts_list.add_child(_heading("TIRES"))
	for part: Dictionary in GameState.PARTS:
		if str(part.get("slot", "")) == GameState.SLOT_TIRES:
			_add_part_ads(part, "part")
	var bolt_ons: Array[Dictionary] = []
	for part: Dictionary in GameState.PARTS:
		if str(part.get("slot", "")).is_empty():
			bolt_ons.append(part)
	if not bolt_ons.is_empty():
		_parts_list.add_child(_heading("ENGINE & CHASSIS"))
	for part: Dictionary in bolt_ons:
		_add_part_ads(part, "part")
	_parts_list.add_child(_heading("UNDER THE HOOD"))
	for part: Dictionary in GameState.PARTS:
		if not GameState.is_hood_kind(str(part.get("slot", ""))):
			continue
		_add_part_ads(part, "part")
	_parts_list.add_child(_heading("UNDER THE CAR"))
	for part: Dictionary in GameState.PARTS:
		var slot := str(part.get("slot", ""))
		if slot.is_empty() or slot == GameState.SLOT_TIRES or GameState.is_hood_kind(slot):
			continue
		_add_part_ads(part, "part")


func _add_part_ads(item: Dictionary, kind: String) -> void:
	var id := str(item.get("id", ""))
	var count := GameState.newspaper_copies(kind, id).size()
	for index: int in count:
		match kind:
			"engine":
				_parts_list.add_child(_make_engine_card(item, index))
			"transmission":
				_parts_list.add_child(_make_gearbox_card(item, index))
			"wheels":
				_parts_list.add_child(_make_wheel_card(item, index))
			_:
				_parts_list.add_child(_make_part_card(item, index))


func _rebuild_cars() -> void:
	for child in _cars_list.get_children():
		_cars_list.remove_child(child)
		child.queue_free()
	for car in GameState.USED_CARS:
		_cars_list.add_child(_make_car_card(car))


func _make_part_card(part: Dictionary, index: int) -> Control:
	var part_id := str(part.get("id", ""))
	var owned := GameState.part_count(part_id)
	var equipped := GameState.is_part_equipped(part_id)
	var box := _card()
	box.add_child(_heading(str(part.get("name", "Part"))))
	box.add_child(_body(_with_wear(GameState.part_detail(part), "part", part_id, index)))
	if owned > 0:
		box.add_child(_body("You have %d%s" % [owned, " · on this car" if equipped else ""]))
	box.add_child(_buy_button("part", part_id, index))
	_watch_part(box, part_id, "part", index)
	return box


func _make_gearbox_card(box: Dictionary, index: int) -> Control:
	var gearbox_id := str(box.get("id", ""))
	var gears: Variant = box.get("ratios", [])
	var gear_count := 0
	if typeof(gears) == TYPE_ARRAY:
		gear_count = gears.size()
	var kind := "automatic" if bool(box.get("automatic", false)) else "manual"
	var top_pct := int(round(float(box.get("top_speed", 1.0)) * 100.0))
	var card := _card()
	card.add_child(_heading(str(box.get("name", "Gearbox"))))
	card.add_child(_body(_with_wear("%d gears · %s · top speed %d%%" % [gear_count, kind, top_pct], "transmission", gearbox_id, index)))
	card.add_child(_body("Ratios  %s" % GameState.gearbox_ratio_text(box)))
	card.add_child(_buy_button("transmission", gearbox_id, index))
	_watch_part(card, gearbox_id, "transmission", index)
	return card


func _make_car_card(car: Dictionary) -> Control:
	var car_id := str(car.get("id", ""))
	var price := int(car.get("price", 0))
	var box := _card()
	box.set_meta(&"car_id", car_id)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_car_card_input.bind(car_id))
	if car_id == _preview_car_id:
		box.modulate = Color(0.96, 0.84, 0.58, 1)
	box.add_child(_heading(str(car.get("name", "Car"))))
	box.add_child(_body("%s   %.0f hp" % [GameState.speed_text(float(car.get("vmax", 0.0))), float(car.get("hp", 0.0))]))
	var btn := _ink_button()
	btn.text = "Buy — $%d" % price
	if GameState.owned_car_ids.size() >= GameState.MAX_OWNED_CARS:
		btn.pressed.connect(_on_buy_car.bind(car_id))
	else:
		btn.disabled = GameState.money < price
		btn.pressed.connect(_show_car_preview.bind(car_id))
		btn.pressed.connect(_on_buy_car.bind(car_id))
	box.add_child(btn)
	return box


func _on_car_card_input(event: InputEvent, car_id: String) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		_show_car_preview(car_id)


func _show_car_preview(car_id: String) -> void:
	if car_id == _preview_car_id:
		return
	_preview_car_id = car_id
	_preview_part_id = ""
	_preview_copy = -1
	if _preview_subject != null:
		_preview_subject.visible = false
	_tint_preview_cards()
	var car: Dictionary = GameState.listing_by_id(GameState.USED_CARS, car_id)
	var car_name := str(car.get("name", "Car"))
	var path := str(car.get("car_file", ""))
	var paint := GameState.newspaper_color(car_id)
	_open_preview_overlay()
	if path.is_empty() or not FileAccess.file_exists(path):
		_preview_frame.visible = false
		_preview_caption.text = "%s — no photograph with this ad." % car_name
		return
	if _preview_pivot == null:
		var pivot := _CarVisual.instantiate() as Node3D
		if pivot == null or not pivot.has_method(&"prepare_preview"):
			_preview_frame.visible = false
			_preview_caption.text = "Couldn't open the photograph."
			return
		var prepared: Variant = pivot.call(&"prepare_preview", path, paint)
		if not bool(prepared):
			pivot.free()
			_preview_frame.visible = false
			_preview_caption.text = "%s — no photograph with this ad." % car_name
			return
		_preview_mount.add_child(pivot)
		_preview_pivot = pivot
	elif not bool(_preview_pivot.call(&"preview_listing", path, paint)):
		_preview_frame.visible = false
		_preview_caption.text = "%s — no photograph with this ad." % car_name
		return
	if _preview_subject != null:
		_preview_subject.visible = false
	if _preview_pivot != null:
		_preview_pivot.visible = true
	_preview_mount.rotation = Vector3.ZERO
	_frame_car_camera()
	_seat_preview_car()
	_preview_frame.visible = true
	_preview_caption.text = car_name


func _show_part_preview(part_id: String, kind: String, index: int) -> void:
	if part_id == _preview_part_id and index == _preview_copy and _preview_overlay.visible and _preview_frame.visible:
		return
	_preview_part_id = part_id
	_preview_copy = index
	_preview_car_id = ""
	if _preview_pivot != null:
		_preview_pivot.visible = false
	_tint_preview_cards()
	var part := _catalog_part(kind, part_id)
	var part_name := str(part.get("name", "Part"))
	_open_preview_overlay()
	var subject := _PartPreview.build(part, kind) if not part.is_empty() else null
	if subject == null:
		_clear_preview_subject()
		_preview_frame.visible = false
		_preview_caption.text = "%s — no photograph with this ad." % part_name
		return
	_set_preview_subject(subject)
	_PartPreview.apply_wear(subject, GameState.newspaper_wear_percent(kind, part_id, index))
	_preview_mount.rotation = Vector3.ZERO
	_frame_subject_camera()
	_preview_frame.visible = true
	_preview_caption.text = part_name


func _catalog_part(kind: String, part_id: String) -> Dictionary:
	match kind:
		"engine":
			return GameState.listing_by_id(GameState.ENGINES, part_id)
		"transmission":
			return GameState.listing_by_id(GameState.GEARBOXES, part_id)
		"wheels":
			return GameState.listing_by_id(GameState.WHEELS, part_id)
		_:
			return GameState.listing_by_id(GameState.PARTS, part_id)


func _set_preview_subject(node: Node3D) -> void:
	_clear_preview_subject()
	_preview_subject = node
	node.visible = true
	_preview_mount.add_child(node)


func _clear_preview_subject() -> void:
	if _preview_subject == null:
		return
	_preview_mount.remove_child(_preview_subject)
	_preview_subject.free()
	_preview_subject = null


func _frame_car_camera() -> void:
	_preview_camera.look_at_from_position(_CAR_CAM_FROM, _CAR_CAM_AT)


func _frame_subject_camera() -> void:
	if _preview_subject == null:
		return
	_preview_subject.force_update_transform()
	var bounds := _local_mesh_bounds(_preview_subject)
	if bounds.size == Vector3.ZERO:
		_preview_camera.look_at_from_position(Vector3(0.9, 0.45, 1.3), Vector3(0.0, 0.3, 0.0))
		return
	var scale := _preview_subject.scale
	var center := bounds.get_center()
	_preview_subject.position = Vector3(-center.x * scale.x, -bounds.position.y * scale.y, -center.z * scale.z)
	var height := bounds.size.y * absf(scale.y)
	var focus := Vector3(0.0, height * 0.5, 0.0)
	var extent := maxf(bounds.size.x * absf(scale.x), maxf(height, bounds.size.z * absf(scale.z)))
	var dist := extent * 0.72 / tan(deg_to_rad(_preview_camera.fov * 0.5))
	var eye := focus + Vector3(0.85, 0.62, 0.9).normalized() * dist
	_preview_camera.look_at_from_position(eye, focus)


func _local_mesh_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var started := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		bounds = (node as MeshInstance3D).mesh.get_aabb()
		started = true
	for child: Node in node.get_children():
		if not child is Node3D:
			continue
		var child_node := child as Node3D
		var child_bounds := _local_mesh_bounds(child_node)
		if child_bounds.size == Vector3.ZERO:
			continue
		child_bounds = _transformed_aabb(child_node.transform, child_bounds)
		if not started:
			bounds = child_bounds
			started = true
		else:
			bounds = bounds.merge(child_bounds)
	return bounds


func _transformed_aabb(xf: Transform3D, box: AABB) -> AABB:
	var out := AABB(xf * box.get_endpoint(0), Vector3.ZERO)
	for i: int in range(1, 8):
		out = out.expand(xf * box.get_endpoint(i))
	return out


func _seat_preview_car() -> void:
	if _preview_pivot == null or not _preview_pivot.has_method(&"align_wheels_to_floor"):
		return
	_preview_pivot.call(&"align_wheels_to_floor", _preview_floor)


func _open_preview_overlay() -> void:
	_preview_overlay.visible = true
	_wire_menu()


func _close_car_preview() -> void:
	if not _preview_overlay.visible:
		return
	_preview_overlay.visible = false
	_preview_car_id = ""
	_preview_part_id = ""
	_preview_copy = -1
	_tint_preview_cards()
	_wire_menu()


func _tint_preview_cards() -> void:
	_tint_list(_cars_list, &"car_id", _preview_car_id)
	for child: Node in _parts_list.get_children():
		if not child is Control:
			continue
		var card := child as Control
		var id := str(card.get_meta(&"part_id", ""))
		var copy := int(card.get_meta(&"copy_index", -1))
		if id == _preview_part_id and copy == _preview_copy and not _preview_part_id.is_empty():
			card.modulate = Color(0.96, 0.84, 0.58, 1)
		else:
			card.modulate = Color.WHITE


func _tint_list(list: Node, meta_name: StringName, selected: String) -> void:
	for child: Node in list.get_children():
		if not child is Control:
			continue
		var card := child as Control
		if str(card.get_meta(meta_name, "")) == selected and not selected.is_empty():
			card.modulate = Color(0.96, 0.84, 0.58, 1)
		else:
			card.modulate = Color.WHITE


func _ink_button() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 52)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.08, 0.07, 0.06, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.07, 0.06, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.07, 0.06, 1))
	btn.add_theme_color_override("font_focus_color", Color(0.08, 0.07, 0.06, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.28, 0.26, 0.24, 1))
	return btn


func _card() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	return box


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.08, 0.07, 0.06, 1))
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_constant_override("line_spacing", 4)
	label.add_theme_color_override("font_color", Color(0.16, 0.13, 0.1, 1))
	return label


func _make_engine_card(engine: Dictionary, index: int) -> Control:
	var engine_id := str(engine.get("id", ""))
	var card := _make_copy_card(engine, _with_wear("%.0f hp" % float(engine.get("hp", 0.0)), "engine", engine_id, index), "engine", index)
	_watch_part(card, engine_id, "engine", index)
	return card


func _make_wheel_card(wheel: Dictionary, index: int) -> Control:
	var wheel_id := str(wheel.get("id", ""))
	var card := _make_copy_card(wheel, _with_wear(GameState.wheel_detail(wheel) + ", no tires", "wheels", wheel_id, index), "wheels", index)
	_watch_part(card, wheel_id, "wheels", index)
	return card


func _with_wear(detail: String, kind: String, part_id: String, index: int) -> String:
	var wear := GameState.newspaper_wear_line(kind, part_id, index)
	if detail.is_empty():
		return wear
	return "%s   %s" % [detail, wear]


func _watch_part(card: Control, part_id: String, kind: String, index: int) -> void:
	card.set_meta(&"part_id", part_id)
	card.set_meta(&"copy_index", index)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_part_card_input.bind(part_id, kind, index))
	if part_id == _preview_part_id and index == _preview_copy:
		card.modulate = Color(0.96, 0.84, 0.58, 1)


func _on_part_card_input(event: InputEvent, part_id: String, kind: String, index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		_show_part_preview(part_id, kind, index)


func _make_copy_card(part: Dictionary, detail: String, kind: String, index: int) -> Control:
	var part_id := str(part.get("id", ""))
	var card := _card()
	card.add_child(_heading(str(part.get("name", "Part"))))
	card.add_child(_body(detail))
	card.add_child(_buy_button(kind, part_id, index))
	return card


func _buy_button(kind: String, part_id: String, index: int) -> Button:
	var price := GameState.newspaper_price(kind, part_id, index)
	var btn := _ink_button()
	btn.text = "Buy — $%d" % price
	btn.disabled = GameState.money < price
	btn.pressed.connect(_on_buy_copy.bind(kind, part_id, index))
	return btn


func _on_buy_copy(kind: String, part_id: String, index: int) -> void:
	var err := GameState.buy_newspaper_copy(kind, part_id, index)
	if _finish_if_ruined():
		return
	var bought := "Part is in the spare parts folder."
	match kind:
		"engine":
			bought = "Engine is in the spare parts folder."
		"transmission":
			bought = "Gearbox is in the spare parts folder."
		"wheels":
			bought = "Wheels are in the spare parts folder."
	_status.text = bought if err.is_empty() else err
	_refresh()


func _on_buy_car(car_id: String) -> void:
	if GameState.owned_car_ids.size() >= GameState.MAX_OWNED_CARS:
		_show_no_room_line()
		return
	var err := GameState.buy_or_select_car(car_id)
	if not err.is_empty():
		_status.text = err
		_refresh()
		return
	GameState.drive_into_garage = true
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


func _finish_if_ruined() -> bool:
	if not GameState.is_ruined():
		return false
	GameState.finish_run()
	return true


func _on_used_cars_tab_pressed() -> void:
	_show_section(SECTION_CARS)


func _on_auto_parts_tab_pressed() -> void:
	_show_section(SECTION_PARTS)


func _show_section(section: String) -> void:
	_section = section
	_index_section.visible = section == SECTION_INDEX
	_cars_section.visible = section == SECTION_CARS
	_parts_section.visible = section == SECTION_PARTS
	if section != SECTION_CARS:
		_preview_car_id = ""
		if _preview_pivot != null:
			_preview_pivot.visible = false
	if section != SECTION_PARTS:
		_preview_part_id = ""
		_preview_copy = -1
		if _preview_subject != null:
			_preview_subject.visible = false
	if _preview_car_id.is_empty() and _preview_part_id.is_empty():
		_preview_overlay.visible = false
	if section == SECTION_INDEX:
		_status.text = ""
		_back_button.text = "Fold it up — back to garage"
	else:
		_back_button.text = "Back to classifieds"
	_wire_menu()


func _wire_menu() -> void:
	var items: Array = []
	if _preview_overlay.visible:
		items = [_preview_back, _back_button]
	elif _section == SECTION_INDEX:
		items = [%UsedCarsCard, %AutoPartsCard, _back_button]
	elif _section == SECTION_CARS:
		items = _nav.collect_buttons(_cars_list)
		items.append(_back_button)
	else:
		items = _nav.collect_buttons(_parts_list)
		items.append(_back_button)
	_nav.setup(items)


func _build_no_room_bubble() -> void:
	var bubble := _SpeechBubble.instantiate()
	bubble.visible = false
	add_child(bubble)
	bubble.call("grab_screen")
	bubble.call("show_centered")
	bubble.connect("pressed", _dismiss_no_room_line)
	_no_room = bubble


func _show_no_room_line() -> void:
	if _no_room == null:
		return
	_no_room.call("set_line", _NO_ROOM_LINES[randi() % _NO_ROOM_LINES.size()], Vector2(560, 56), 26)
	_no_room.move_to_front()
	_no_room.visible = true
	_no_room.call("place")


func _dismiss_no_room_line() -> void:
	if _no_room != null:
		_no_room.visible = false


func _on_back_pressed() -> void:
	if _preview_overlay.visible:
		_close_car_preview()
		return
	if _section != SECTION_INDEX:
		_show_section(SECTION_INDEX)
		return
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)
