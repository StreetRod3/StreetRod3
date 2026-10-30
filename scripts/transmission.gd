extends Node3D

## Under the car on the lift. Two bellhousing bolts hold the gearbox to the engine.
## Click a bolt hole to thread a bolt in, click the bolt again to tighten it, and click a
## tight bolt to back it out. With both bolts out the jack takes the gearbox down to spare
## parts. Select raises a spare gearbox into an empty bellhousing, its bolts in but loose.

const _MenuNav := preload("res://scripts/menu_nav.gd")

## Engine models are built about four and a half times real size.
const ENGINE_SCALE := 0.22
## Rear face of the block and the crank center, in engine model units once it is stood up.
const ENGINE_REAR_X := 1.5
const ENGINE_CRANK_Y := -0.36
## Crank centerline in meters off the floor. The car is up on the lift.
const DRIVELINE_Y := 1.2
const FLANGE_R := 0.215
const FLANGE_T := 0.022
const BELL_LEN := 0.24
const BOLT_RING_R := 0.19
## Upper and lower bolt, both on the side the camera starts on.
const BOLT_ANGLES: Array[float] = [0.9, -0.9]
const BOLT_NAMES: Array[String] = ["Upper bolt", "Lower bolt"]
## How far a bolt stands proud of the flange for each turn it still needs.
const BOLT_PITCH := 0.014
## Spin of the bolt head for each turn, in radians.
const BOLT_SPIN := TAU * 0.6
## The gearbox slides this far back off the input shaft before it can drop.
const SLIDE_BACK := 0.2
const JACK_PARK := Vector3(1.6, 0.0, -0.9)
## Cradle height while the jack rolls about.
const JACK_LOW := 0.42
const JACK_POST_BASE := 0.1
const CROSSMEMBER_IN := Vector3(0.82, DRIVELINE_Y - 0.1025, 0.0)
## Unbolted and laid on the floor, out of the jack's way.
const CROSSMEMBER_OUT := Vector3(0.9, 0.0225, -1.0)
const T_CROSSMEMBER := 0.8
const FOCUS := Vector3(0.2, DRIVELINE_Y - 0.05, 0.0)

const T_TURN := 0.32
const T_BOLT_OUT := 0.5
const T_BOLT_IN := 0.55
const T_JACK_ROLL := 1.5
const T_JACK_LIFT := 1.4
const T_SLIDE := 0.8
const T_PAUSE := 0.2

const CAM_YAW_MIN := -0.35
const CAM_YAW_MAX := 1.75
const CAM_PITCH_MIN := -0.15
const CAM_PITCH_MAX := 0.8
const CAM_DISTANCE_MIN := 0.7
const CAM_DISTANCE_MAX := 2.2
const ZOOM_STEP := 0.1

const _IRON := Color(0.24, 0.24, 0.25)
const _ALLOY := Color(0.66, 0.66, 0.64)
const _RACE := Color(0.13, 0.14, 0.17)
const _RACE_TRIM := Color(0.72, 0.1, 0.08)
const _STEEL := Color(0.55, 0.56, 0.58)
const _UNDERBODY := Color(0.09, 0.085, 0.08)
const _JACK_RED := Color(0.62, 0.1, 0.07)
const _CREAM := Color(0.95, 0.9, 0.78, 1)
const _RATE := 22050

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $UI/Root

## The gearbox. Origin on the crank line at the face of the bellhousing flange.
var _rig: Node3D
## Rig-local point the jack cradle carries it by: under the middle of the case.
var _rig_seat := Vector3.ZERO
var _jack: Node3D
var _cradle: Node3D
var _post: MeshInstance3D
## Holds up the tail housing. It comes out so the gearbox can drop past it.
var _crossmember: Node3D
var _bolts: Array[Node3D] = []
var _bolt_mats: Array[StandardMaterial3D] = []
var _holes: Array[Vector3] = []
## A bolt that was tight comes all the way out before it can be tightened again.
var _loosening: Array[bool] = []
var _hover: int = -1
var _busy: bool = false
var _orbiting: bool = false
var _yaw: float = 0.5
var _pitch: float = 0.3
var _distance: float = 1.55
var _nav = _MenuNav.new()

var _box_label: Label
var _bolt_labels: Array[Label] = []
var _hint: Label
var _tooltip: Label
var _select_btn: Button
var _done_btn: Button
var _picker: Control
var _picker_rows: VBoxContainer
var _picker_note: Label
var _picker_close: Button

var _sfx_ratchet: AudioStreamPlayer
var _sfx_snug: AudioStreamPlayer
var _sfx_clunk: AudioStreamPlayer
var _sfx_tink: AudioStreamPlayer


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	GameState.update_music()
	if not GameState.has_active_car():
		get_tree().change_scene_to_file.call_deferred(GameState.SCENE_GARAGE)
		return
	_build_world()
	_build_bay()
	_build_engine()
	_build_jack()
	_build_bolts()
	if GameState.has_gearbox():
		_rig = _build_gearbox(GameState.get_equipped_gearbox())
		add_child(_rig)
		_rig.position = Vector3(0.0, DRIVELINE_Y, 0.0)
	_place_bolts()
	_build_sounds()
	_build_ui()
	_update_camera()
	_refresh_ui()


func _process(_delta: float) -> void:
	if _picker != null:
		_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if _picker == null:
		return
	if event is InputEventKey:
		_handle_key(event as InputEventKey)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_distance = clampf(_distance + dir * ZOOM_STEP, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
			_update_camera()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _picker.visible:
			var index := _bolt_at(mb.position)
			if index >= 0:
				get_viewport().set_input_as_handled()
				_on_bolt(index)
		return
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if mg.factor > 0.0001:
			_distance = clampf(_distance / mg.factor, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
			_update_camera()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_yaw = clampf(_yaw + mm.relative.x * 0.005, CAM_YAW_MIN, CAM_YAW_MAX)
		_pitch = clampf(_pitch + mm.relative.y * 0.005, CAM_PITCH_MIN, CAM_PITCH_MAX)
		_update_camera()
		get_viewport().set_input_as_handled()


func _handle_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	if _nav.handle_event(self, key):
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_ESCAPE:
		if _picker.visible:
			_close_picker()
		else:
			_on_done_pressed()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_G and not _picker.visible:
		_on_select_pressed()
		get_viewport().set_input_as_handled()
		return
	if (key.keycode == KEY_1 or key.keycode == KEY_2) and not _picker.visible:
		_on_bolt(0 if key.keycode == KEY_1 else 1)
		get_viewport().set_input_as_handled()


func _update_camera() -> void:
	var dir := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3.BACK
	_camera.global_position = FOCUS + dir * _distance
	_camera.look_at(FOCUS, Vector3.UP)


# --- Bolts -----------------------------------------------------------------


func _on_bolt(index: int) -> void:
	if _busy or index < 0 or index >= _bolts.size() or not GameState.has_gearbox():
		return
	var turns: int = GameState.gearbox_bolts[index]
	var next := turns - 1
	if turns == 0 or (not _loosening[index] and turns < GameState.GEARBOX_BOLT_TIGHT):
		next = turns + 1
	_loosening[index] = next < turns and next > 0
	GameState.set_gearbox_bolt(index, next)
	_busy = true
	_refresh_ui()
	if turns == 0:
		await _thread_in(index)
	elif next > 0:
		await _turn_bolt(index, turns, next)
	else:
		await _back_out(index)
		if is_instance_valid(self) and _all_bolts_out():
			await _drop_gearbox()
	if not is_instance_valid(self):
		return
	_busy = false
	_refresh_ui()


func _all_bolts_out() -> bool:
	for turns in GameState.gearbox_bolts:
		if turns > 0:
			return false
	return true


func _turn_bolt(index: int, from: int, to: int) -> void:
	if to == GameState.GEARBOX_BOLT_TIGHT:
		_play(_sfx_snug)
	else:
		_play(_sfx_ratchet)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_set_bolt_turns.bind(index), float(from), float(to), T_TURN)
	await tw.finished


## Backs the last turn out, then lets the bolt fall to the floor.
func _back_out(index: int) -> void:
	_play(_sfx_ratchet)
	var tw := create_tween()
	tw.tween_method(_set_bolt_turns.bind(index), 1.0, -1.2, T_TURN * 1.4)
	await tw.finished
	if not is_instance_valid(self):
		return
	var fall := create_tween()
	fall.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(_bolts[index], "global_transform", _bolt_floor(index), T_BOLT_OUT)
	await fall.finished
	_play(_sfx_tink)


## Picks the bolt up off the floor and starts it a turn into its hole.
func _thread_in(index: int) -> void:
	var lift := create_tween()
	lift.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	lift.tween_property(_bolts[index], "global_transform", _bolt_xform(index, -1.2), T_BOLT_IN)
	await lift.finished
	if not is_instance_valid(self):
		return
	_play(_sfx_ratchet)
	var tw := create_tween()
	tw.tween_method(_set_bolt_turns.bind(index), -1.2, 1.0, T_TURN * 1.4)
	await tw.finished


func _set_bolt_turns(turns: float, index: int) -> void:
	_bolts[index].global_transform = _bolt_xform(index, turns)


## Where a bolt sits with `turns` in. Below zero it is backing out of the hole.
func _bolt_xform(index: int, turns: float) -> Transform3D:
	var proud := (float(GameState.GEARBOX_BOLT_TIGHT) - turns) * BOLT_PITCH
	return Transform3D(Basis(Vector3.RIGHT, turns * BOLT_SPIN), _holes[index] + Vector3(proud, 0.0, 0.0))


## A bolt lying on the floor under the bellhousing.
func _bolt_floor(index: int) -> Transform3D:
	var spot := Vector3(0.1 + 0.08 * float(index), 0.021, _holes[index].z + 0.12)
	return Transform3D(Basis(Vector3.UP, 0.5 + 1.1 * float(index)), spot)


func _place_bolts() -> void:
	_loosening.clear()
	for i in _bolts.size():
		_loosening.append(false)
		var turns: int = GameState.gearbox_bolts[i] if i < GameState.gearbox_bolts.size() else 0
		if not GameState.has_gearbox() or turns <= 0:
			_bolts[i].global_transform = _bolt_floor(i)
		else:
			_bolts[i].global_transform = _bolt_xform(i, float(turns))


func _bolt_at(screen_pos: Vector2) -> int:
	if _busy or not GameState.has_gearbox():
		return -1
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 20.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	var node := hit.get("collider") as Node
	if node == null or not node.has_meta(&"transmission_bolt"):
		return -1
	return int(node.get_meta(&"transmission_bolt"))


func _update_hover() -> void:
	var index := -1
	var vp := get_viewport()
	if not _picker.visible and not _orbiting and vp.gui_get_hovered_control() == null:
		index = _bolt_at(vp.get_mouse_position())
	if index != _hover:
		_hover = index
		for i in _bolt_mats.size():
			_bolt_mats[i].emission_enabled = i == _hover
	if _hover < 0:
		_tooltip.visible = false
		return
	_tooltip.text = _bolt_hint(_hover)
	_tooltip.visible = true
	_tooltip.reset_size()
	_tooltip.position = vp.get_mouse_position() + Vector2(18.0, 14.0)


func _bolt_hint(index: int) -> String:
	var turns: int = GameState.gearbox_bolts[index]
	var label := BOLT_NAMES[index]
	if turns == 0:
		return "%s — thread it in" % label
	if _loosening[index] or turns >= GameState.GEARBOX_BOLT_TIGHT:
		return "%s — loosen" % label
	return "%s — tighten" % label


func _bolt_state_text(index: int) -> String:
	var turns: int = GameState.gearbox_bolts[index]
	if turns == 0:
		return "out"
	if turns >= GameState.GEARBOX_BOLT_TIGHT:
		return "tight"
	return "loose, %d of %d turns" % [turns, GameState.GEARBOX_BOLT_TIGHT]


# --- Gearbox in and out ------------------------------------------------------


## Both bolts are out: slide the gearbox back off the input shaft and lower it away.
func _drop_gearbox() -> void:
	var err := GameState.remove_gearbox()
	if not err.is_empty() or _rig == null:
		_hint.text = err
		return
	_hint.text = "Bringing the jack in…"
	await _pause(T_PAUSE)
	await _roll_jack(Vector3(_rig_seat.x, 0.0, 0.0), T_JACK_ROLL)
	await _lift_cradle(DRIVELINE_Y + _rig_seat.y, T_JACK_LIFT)
	if not is_instance_valid(self):
		return
	_rig.reparent(_cradle, true)
	await _slide_crossmember(CROSSMEMBER_OUT)
	await _roll_jack(Vector3(_rig_seat.x + SLIDE_BACK, 0.0, 0.0), T_SLIDE)
	_play(_sfx_clunk)
	await _lift_cradle(JACK_LOW, T_JACK_LIFT)
	await _roll_jack(JACK_PARK, T_JACK_ROLL)
	if not is_instance_valid(self):
		return
	_hint.text = ""


## Rolls a spare gearbox in on the jack, raises it, and slides it onto the input shaft.
func _raise_gearbox(gearbox_id: String) -> void:
	if _busy:
		return
	var err := GameState.fit_gearbox(gearbox_id)
	if not err.is_empty():
		_picker_note.text = err
		return
	_close_picker()
	_busy = true
	_refresh_ui()
	_hint.text = "Rolling the gearbox in…"
	if _rig != null:
		# The one on the jack goes up on the shelf.
		_rig.queue_free()
	_rig = _build_gearbox(GameState.get_equipped_gearbox())
	_cradle.add_child(_rig)
	_rig.position = -_rig_seat
	await _roll_jack(Vector3(_rig_seat.x + SLIDE_BACK, 0.0, 0.0), T_JACK_ROLL)
	await _lift_cradle(DRIVELINE_Y + _rig_seat.y, T_JACK_LIFT * 1.2)
	await _roll_jack(Vector3(_rig_seat.x, 0.0, 0.0), T_SLIDE)
	if not is_instance_valid(self):
		return
	_play(_sfx_clunk)
	await _slide_crossmember(CROSSMEMBER_IN)
	if not is_instance_valid(self):
		return
	_rig.reparent(self, true)
	await _pause(T_PAUSE)
	await _lift_cradle(JACK_LOW, T_JACK_LIFT * 0.8)
	await _roll_jack(JACK_PARK, T_JACK_ROLL)
	for i in _bolts.size():
		if not is_instance_valid(self):
			return
		_loosening[i] = false
		await _thread_in(i)
	if not is_instance_valid(self):
		return
	_busy = false
	_refresh_ui()


func _roll_jack(to: Vector3, duration: float) -> void:
	if not is_instance_valid(self):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_jack, "position", to, duration)
	await tw.finished


func _slide_crossmember(to: Vector3) -> void:
	if not is_instance_valid(self):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_crossmember, "position", to, T_CROSSMEMBER)
	await tw.finished


func _lift_cradle(height: float, duration: float) -> void:
	if not is_instance_valid(self):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_set_cradle, _cradle.position.y, height, duration)
	await tw.finished


func _set_cradle(height: float) -> void:
	_cradle.position.y = height
	var reach := maxf(height - JACK_POST_BASE, 0.02)
	_post.scale = Vector3(1.0, reach, 1.0)
	_post.position.y = JACK_POST_BASE + reach * 0.5


func _pause(seconds: float) -> void:
	if not is_instance_valid(self):
		return
	await get_tree().create_timer(seconds).timeout


# --- UI ----------------------------------------------------------------------


func _on_select_pressed() -> void:
	if _busy:
		return
	if GameState.has_gearbox():
		_hint.text = "Take both bolts out and drop the old gearbox first."
		return
	_open_picker()


func _on_done_pressed() -> void:
	if _busy:
		return
	_nav.clear()
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


func _open_picker() -> void:
	for child in _picker_rows.get_children():
		_picker_rows.remove_child(child)
		child.free()
	var spares := GameState.spare_gearboxes()
	for box in spares:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\n%s" % [str(box.get("name", "Gearbox")), _box_detail(box)]
		label.add_theme_color_override(&"font_color", _CREAM)
		row.add_child(label)
		var fit := Button.new()
		fit.text = "Fit"
		fit.custom_minimum_size = Vector2(72, 0)
		fit.pressed.connect(_raise_gearbox.bind(str(box.get("id", ""))))
		row.add_child(fit)
		_picker_rows.add_child(row)
	if spares.is_empty():
		_picker_note.text = "No spare transmissions. The newspaper sells them."
	else:
		_picker_note.text = "Pick a gearbox to raise into the bellhousing."
	_picker.visible = true
	_sync_nav()


func _close_picker() -> void:
	_picker.visible = false
	_sync_nav()


func _sync_nav() -> void:
	if _picker.visible:
		_nav.setup(_nav.collect_buttons(_picker))
	else:
		_nav.setup([_select_btn, _done_btn])


func _box_detail(box: Dictionary) -> String:
	var ratios: Variant = box.get("ratios", [])
	var gears := 0
	if typeof(ratios) == TYPE_ARRAY:
		gears = (ratios as Array).size()
	var kind := "automatic" if bool(box.get("automatic", false)) else "manual"
	return "%s · %d gears · ratios %s" % [kind, gears, GameState.gearbox_ratio_text(box)]


func _refresh_ui() -> void:
	var has_box := GameState.has_gearbox()
	if has_box:
		var box := GameState.get_equipped_gearbox()
		_box_label.text = "%s\n%s" % [str(box.get("name", "Gearbox")), _box_detail(box)]
	else:
		_box_label.text = "No transmission"
	for i in _bolt_labels.size():
		_bolt_labels[i].visible = has_box
		if has_box:
			_bolt_labels[i].text = "%s: %s" % [BOLT_NAMES[i], _bolt_state_text(i)]
	_select_btn.disabled = _busy
	_done_btn.disabled = _busy
	if _busy:
		return
	if not has_box:
		_hint.text = "The bellhousing is empty. Select a spare gearbox to raise one in."
	elif GameState.is_gearbox_bolted():
		_hint.text = "Both bolts are tight. Click one to back it out."
	elif GameState.gearbox_bolts.has(0):
		_hint.text = "Click the empty hole to thread its bolt back in, or back the other bolt out to drop the gearbox."
	else:
		_hint.text = "Tighten both bolts before the car can drive."


func _build_ui() -> void:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override(&"panel", _panel_style())
	header.position = Vector2(16, 16)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(header)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 4)
	header.add_child(info)
	var title := _ui_label("Transmission — %s" % GameState.car_name, 22)
	info.add_child(title)
	_box_label = _ui_label("", 16)
	info.add_child(_box_label)
	for i in BOLT_NAMES.size():
		var line := _ui_label("", 16)
		_bolt_labels.append(line)
		info.add_child(line)

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override(&"panel", _panel_style())
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16.0
	bottom.offset_right = -16.0
	bottom.offset_top = -72.0
	bottom.offset_bottom = -16.0
	_ui.add_child(bottom)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 12)
	bottom.add_child(bar)
	_hint = _ui_label("", 18)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_hint)
	_select_btn = Button.new()
	_select_btn.text = "Select gearbox (G)"
	_select_btn.pressed.connect(_on_select_pressed)
	bar.add_child(_select_btn)
	_done_btn = Button.new()
	_done_btn.text = "Done"
	_done_btn.custom_minimum_size = Vector2(96, 0)
	_done_btn.pressed.connect(_on_done_pressed)
	bar.add_child(_done_btn)

	_tooltip = _ui_label("", 18)
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	_tooltip.add_theme_constant_override(&"shadow_offset_x", 2)
	_tooltip.add_theme_constant_override(&"shadow_offset_y", 2)
	_ui.add_child(_tooltip)

	_build_picker()
	_sync_nav()


func _build_picker() -> void:
	_picker = Control.new()
	_picker.name = "Picker"
	_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260.0
	panel.offset_right = 260.0
	panel.offset_top = -200.0
	panel.offset_bottom = 200.0
	_picker.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	var title := _ui_label("Spare transmissions", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_picker_note = _ui_label("", 16)
	_picker_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_picker_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_picker_rows = VBoxContainer.new()
	_picker_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_rows.add_theme_constant_override(&"separation", 10)
	scroll.add_child(_picker_rows)
	_picker_close = Button.new()
	_picker_close.text = "Forget it"
	_picker_close.pressed.connect(_close_picker)
	box.add_child(_picker_close)
	_ui.add_child(_picker)


func _ui_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", _CREAM)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.92)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


# --- Scene building ----------------------------------------------------------


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.045, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# Work light on a stand beside the camera, and a cool fill from the shop beyond.
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.55, 0.8, 0.75)
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = 1.5
	lamp.omni_range = 3.5
	lamp.shadow_enabled = true
	add_child(lamp)
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.6, 0.6, 1.6)
	fill.light_color = Color(0.7, 0.78, 0.95)
	fill.light_energy = 0.9
	fill.omni_range = 5.0
	add_child(fill)


## Shop floor, the lift, and the underside of the car.
func _build_bay() -> void:
	var concrete := _mat(Color(0.32, 0.31, 0.3), 0.0, 0.9)
	var under := _mat(_UNDERBODY, 0.2, 0.8)
	var frame := _mat(Color(0.12, 0.12, 0.12), 0.4, 0.6)
	var paint := _mat(GameState.car_color, 0.3, 0.4)
	var lift := _mat(Color(0.16, 0.3, 0.55), 0.3, 0.5)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(9.0, 9.0)
	floor.mesh = plane
	floor.material_override = concrete
	add_child(floor)
	# Floor pan, frame rails, and the rocker panels in the car's paint.
	_box(self, Vector3(4.2, 0.03, 1.6), Vector3(0.1, DRIVELINE_Y + 0.34, 0.0), under)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(4.0, 0.1, 0.07), Vector3(0.1, DRIVELINE_Y + 0.17, 0.42 * side), frame)
		_box(self, Vector3(4.2, 0.16, 0.04), Vector3(0.1, DRIVELINE_Y + 0.27, 0.8 * side), paint)
		# Posts of the two-post lift, well out to the sides.
		_box(self, Vector3(0.24, 2.6, 0.24), Vector3(-0.45, 1.3, 1.75 * side), lift)
	# Transmission crossmember under the tail housing, out while the bellhousing is empty.
	_crossmember = _box(self, Vector3(0.06, 0.045, 0.86), CROSSMEMBER_IN, _mat(Color(0.3, 0.3, 0.31), 0.6, 0.45))
	if not GameState.has_gearbox():
		_crossmember.position = CROSSMEMBER_OUT
	# Drip pan under the engine.
	var pan := MeshInstance3D.new()
	var pan_mesh := CylinderMesh.new()
	pan_mesh.top_radius = 0.32
	pan_mesh.bottom_radius = 0.3
	pan_mesh.height = 0.04
	pan.mesh = pan_mesh
	pan.material_override = _mat(Color(0.2, 0.19, 0.17), 0.5, 0.5)
	pan.position = Vector3(-0.4, 0.02, -0.05)
	add_child(pan)


func _build_engine() -> void:
	if not GameState.has_engine():
		return
	var path := str(GameState.get_equipped_engine().get("model", ""))
	if path.is_empty():
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Engine model missing: %s" % path)
		return
	var engine := packed.instantiate() as Node3D
	if engine == null:
		return
	add_child(engine)
	engine.scale = Vector3.ONE * ENGINE_SCALE
	engine.rotation.x = -PI * 0.5
	engine.position = Vector3(-ENGINE_REAR_X * ENGINE_SCALE, DRIVELINE_Y - ENGINE_CRANK_Y * ENGINE_SCALE, 0.0)


func _build_jack() -> void:
	var red := _mat(_JACK_RED, 0.3, 0.5)
	var steel := _mat(_STEEL, 0.7, 0.35)
	var rubber := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.9)
	_jack = Node3D.new()
	_jack.name = "TransmissionJack"
	add_child(_jack)
	_box(_jack, Vector3(0.5, 0.05, 0.36), Vector3(0.0, 0.075, 0.0), red)
	for cx in [-0.21, 0.21]:
		for cz in [-0.15, 0.15]:
			var wheel := _cylinder_x(_jack, 0.035, 0.035, 0.03, 0.0, rubber)
			wheel.position = Vector3(cx, 0.035, cz)
	_post = MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.035
	post_mesh.bottom_radius = 0.045
	post_mesh.height = 1.0
	_post.mesh = post_mesh
	_post.material_override = steel
	_jack.add_child(_post)
	_cradle = Node3D.new()
	_cradle.name = "Cradle"
	_jack.add_child(_cradle)
	_box(_cradle, Vector3(0.34, 0.025, 0.2), Vector3(0.0, -0.0125, 0.0), red)
	for fx in [-0.16, 0.16]:
		for fz in [-0.09, 0.09]:
			_box(_cradle, Vector3(0.02, 0.07, 0.02), Vector3(fx, 0.02, fz), red)
	_jack.position = JACK_PARK
	_set_cradle(JACK_LOW)


func _build_bolts() -> void:
	for i in BOLT_ANGLES.size():
		var angle := BOLT_ANGLES[i]
		var hole := Vector3(FLANGE_T, DRIVELINE_Y + BOLT_RING_R * sin(angle), BOLT_RING_R * cos(angle))
		_holes.append(hole)
		var head_mat := _mat(Color(0.78, 0.66, 0.3), 0.8, 0.3)
		head_mat.emission = Color(0.95, 0.62, 0.22)
		head_mat.emission_energy_multiplier = 0.9
		_bolt_mats.append(head_mat)
		# Bolt axis is local +X, pointing out of the hole toward the gearbox.
		var bolt := Node3D.new()
		bolt.name = "Bolt%d" % i
		add_child(bolt)
		_cylinder_x(bolt, 0.009, 0.009, 0.065, -0.065, head_mat)
		_cylinder_x(bolt, 0.026, 0.026, 0.003, -0.001, head_mat, 0.0, 0.0, 20)
		_cylinder_x(bolt, 0.021, 0.021, 0.017, 0.002, head_mat, 0.0, 0.0, 6)
		_bolts.append(bolt)
		# The hole is the hot spot, so a bolt on the floor is found where it goes.
		var spot := StaticBody3D.new()
		spot.set_meta(&"transmission_bolt", i)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.04
		shape.shape = sphere
		spot.add_child(shape)
		spot.position = hole + Vector3(0.02, 0.0, 0.0)
		add_child(spot)


## A gearbox for `box`: bellhousing, case, tail housing. Automatics are iron with a
## pan, manuals aluminum with a rib per gear and a shifter, racing boxes black and red.
func _build_gearbox(box: Dictionary) -> Node3D:
	var rig := Node3D.new()
	rig.name = "Gearbox"
	var ratios: Variant = box.get("ratios", [])
	var gears := 3
	if typeof(ratios) == TYPE_ARRAY:
		gears = maxi((ratios as Array).size(), 1)
	var automatic := bool(box.get("automatic", false))
	var racing := not automatic and float(box.get("shift_time", 0.2)) < 0.1
	var color := _IRON if automatic else (_RACE if racing else _ALLOY)
	var metal := _mat(color, 0.55, 0.5 if automatic else 0.38)
	var dark := _mat(color.darkened(0.35), 0.5, 0.55)
	var trim := _mat(_RACE_TRIM if racing else color.darkened(0.15), 0.4, 0.45)
	var steel := _mat(_STEEL, 0.75, 0.3)
	var hole := _mat(Color(0.02, 0.02, 0.02), 0.0, 1.0)
	# Flange and bellhousing.
	_cylinder_x(rig, FLANGE_R, FLANGE_R, FLANGE_T, 0.0, metal, 0.0, 0.0, 32)
	_cylinder_x(rig, 0.17, 0.115, BELL_LEN, FLANGE_T, metal, 0.0, 0.0, 28)
	for angle in BOLT_ANGLES:
		_cylinder_x(rig, 0.011, 0.011, 0.002, FLANGE_T, hole, BOLT_RING_R * sin(angle), BOLT_RING_R * cos(angle), 12)
	var case_x := FLANGE_T + BELL_LEN - 0.01
	var case_len := 0.22 + 0.045 * float(gears)
	var bottom := -0.105
	if automatic:
		_cylinder_x(rig, 0.125, 0.105, case_len, case_x, metal, 0.0, 0.0, 28)
		_box(rig, Vector3(case_len * 0.8, 0.05, 0.2), Vector3(case_x + case_len * 0.45, -0.13, 0.0), dark)
		bottom = -0.155
	else:
		_box(rig, Vector3(case_len, 0.19, 0.18), Vector3(case_x + case_len * 0.5, -0.01, 0.0), metal)
		# A cast rib for each gear.
		for g in gears:
			var rx := case_x + case_len * (float(g) + 0.5) / float(gears)
			_box(rig, Vector3(0.012, 0.2, 0.19), Vector3(rx, -0.01, 0.0), dark)
		# Side cover, shifter tower, and the stick.
		_box(rig, Vector3(case_len * 0.7, 0.12, 0.012), Vector3(case_x + case_len * 0.5, -0.01, 0.096), trim)
		_box(rig, Vector3(0.08, 0.05, 0.08), Vector3(case_x + case_len * 0.7, 0.105, 0.0), dark)
		var stick := MeshInstance3D.new()
		var stick_mesh := CylinderMesh.new()
		stick_mesh.top_radius = 0.008
		stick_mesh.bottom_radius = 0.011
		stick_mesh.height = 0.22
		stick.mesh = stick_mesh
		stick.material_override = steel
		stick.position = Vector3(case_x + case_len * 0.7, 0.24, 0.0)
		rig.add_child(stick)
	# Tail housing, output yoke, and the rubber mount on the crossmember.
	var tail_x := case_x + case_len
	_cylinder_x(rig, 0.07, 0.05, 0.24, tail_x, metal, 0.0, 0.0, 20)
	_cylinder_x(rig, 0.035, 0.035, 0.07, tail_x + 0.24, steel, 0.0, 0.0, 16)
	_box(rig, Vector3(0.07, 0.03, 0.08), Vector3(0.82, -0.065, 0.0), _mat(Color(0.05, 0.05, 0.05), 0.0, 0.9))
	_rig_seat = Vector3(case_x + case_len * 0.5, bottom, 0.0)
	return rig


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A cylinder or cone along +X from `x0`, `r_front` at x0 and `r_back` at the far end.
func _cylinder_x(parent: Node3D, r_front: float, r_back: float, length: float, x0: float, mat: Material, y: float = 0.0, z: float = 0.0, sides: int = 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = r_front
	mesh.top_radius = r_back
	mesh.height = length
	mesh.radial_segments = sides
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.rotation = Vector3(0.0, 0.0, -PI * 0.5)
	mi.position = Vector3(x0 + length * 0.5, y, z)
	parent.add_child(mi)
	return mi


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


# --- Sounds --------------------------------------------------------------------


func _build_sounds() -> void:
	_sfx_ratchet = _sfx(_wav(_ratchet_samples(5, 0.3, 2600.0, 0.7)))
	_sfx_snug = _sfx(_wav(_snug_samples()))
	_sfx_clunk = _sfx(_wav(_clunk_samples()))
	_sfx_tink = _sfx(_wav(_tink_samples()))


func _sfx(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -6.0
	add_child(player)
	return player


func _play(player: AudioStreamPlayer) -> void:
	if player != null:
		player.play()


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _RATE
	wav.stereo = false
	wav.data = data
	return wav


## Pawl clicks of a ratchet wrench, `clicks` of them spread over `length` seconds.
func _ratchet_samples(clicks: int, length: float, pitch: float, level: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(length * _RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var span := int(0.014 * _RATE)
	for c in clicks:
		var start := int((float(c) + 0.1) / float(clicks) * out.size())
		for k in span:
			var i := start + k
			if i >= out.size():
				break
			var t := float(k) / _RATE
			var env := exp(-t * 480.0)
			out[i] += (rng.randf_range(-1.0, 1.0) * 0.55 + sin(TAU * pitch * t) * 0.45) * env * level
	return out


## The last click of a bolt pulling up tight: two clicks, then a heavier one.
func _snug_samples() -> PackedFloat32Array:
	var out := _ratchet_samples(2, 0.32, 2600.0, 0.7)
	var hit := _ratchet_samples(1, 0.16, 1500.0, 1.0)
	var at := int(0.2 * _RATE)
	for k in hit.size():
		if at + k < out.size():
			out[at + k] += hit[k]
	return out


## Iron on iron: the gearbox seating on its dowels, or dropping off them.
func _clunk_samples() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(0.45 * _RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in out.size():
		var t := float(i) / _RATE
		var body := (sin(TAU * 72.0 * t) * 0.7 + sin(TAU * 151.0 * t) * 0.35) * exp(-t * 14.0)
		var knock := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.6
		var ring := sin(TAU * 1240.0 * t) * exp(-t * 26.0) * 0.12
		out[i] = (body + knock + ring) * 0.8
	return out


## A bolt hitting the concrete, with one small bounce.
func _tink_samples() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(0.5 * _RATE))
	for bounce in 2:
		var at := int((0.0 if bounce == 0 else 0.13) * _RATE)
		var level := 0.6 if bounce == 0 else 0.25
		for k in out.size() - at:
			var t := float(k) / _RATE
			var env := exp(-t * 28.0) * level
			out[at + k] += (sin(TAU * 3150.0 * t) + sin(TAU * 4720.0 * t) * 0.6 + sin(TAU * 6900.0 * t) * 0.3) * env * 0.5
	return out
