extends Node3D

## On the creeper under the car, which sits on jack stands, looking up at the whole
## underside with the front of the car to the right. Click the exhaust manifolds, the
## exhaust pipes, a muffler, or the rear end to swap it for a spare. The exhaust can
## come off and leave the headers open, and a muffler can come off and leave its pipe
## ending open where the muffler bolted on. A dual exhaust has a muffler on each side.
## The springs and shocks are at all four corners, and they swap as a set.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _EngineAssembly := preload("res://scripts/engine_assembly.gd")

## Engine models are built about four and a half times real size.
const ENGINE_SCALE := 0.22
## Rear face of the block and the crank center, in engine model units once it is stood up.
const ENGINE_REAR_X := 1.5
const ENGINE_CRANK_Y := -0.36
## Heights off the floor, in meters, with the car up on stands and the wheels hanging.
const CRANK_Y := 1.01
const AXLE_Y := 0.71
const PIPE_Y := 0.85
const FRAME_Y := 0.94
const PAN_Y := 1.08
const WHEEL_R := 0.34
const TRACK_HALF := 0.74
const FRAME_HALF := 0.48
const BODY_HALF := 0.86
## The Ford flathead's exhaust, from tools/make_flathead.py in inches on the right bank:
## where each cast log's outlet flange takes the head pipe, below its front end, the
## log's ends and height, and the back of the bell housing cast on the block, which is
## where the transmission starts. Its logs are its model's own `exhaust_*` nodes.
const _FH_OUTLET := Vector3(-8.375, 9.042, 0.45)
const _FH_LOG_X := Vector2(-9.375, 9.8)
const _FH_LOG_Z := 3.951
const _FH_BELL_BACK := 15.3
## The Chevy small-block, from tools/make_sbc.py in inches on the right bank (x before the
## bank's offset): where each exhaust's outlet takes the head pipe, under the cast-iron
## manifold's center or at the end of a header's collector. Its exhaust is the manifold
## slot's, from its model or the headers' own.
const _SB_OUTLETS := {
	"log": Vector3(0.0, 10.55, 3.3),
	"shorty": Vector3(6.6, 11.4, -6.43),
	"long-tube": Vector3(13.6, 10.4, -11.21),
}
## The Chevy six, from tools/make_235.py in inches from its block's middle: where each
## exhaust outlet's flange takes a head pipe (the stock manifold's one under the
## carburetor, the split headers' two), the manifold's run along the head for its hot
## spot, and the back of the flywheel housing. Its exhaust is all on its left.
const _SIX_OUTLETS := {
	"log": [Vector3(-1.0, -5.85, 6.6)],
	"split": [Vector3(-1.75, -4.55, 7.2), Vector3(1.75, -4.55, 7.2)],
}
const _SIX_RUN := Vector3(10.5, -4.6, 9.4)
const _SIX_BACK := 13.6
## Engine model nodes that come off with the belt (`GameState.front_drive`): the
## flathead's belt, generator, fan and pulleys, and the small-block's pulleys and bracket.
const _FRONT_NODES: Array[String] = ["belt", "generator", "pulley_generator", "pulley_pump", "fan_", "upper_pulley", "alternator", "accessory_bracket"]
## Exhaust ports along each head, and how far out from the crank line the heads are.
const PORT_COUNT := 4
const PORT_STEP := 0.13
const HEAD_Z := 0.235
## The pipes run back at this spread, and the mufflers hang this far either side of the
## tunnel. A single exhaust's muffler is on the right.
const PIPE_Z := 0.3
const MUFFLER_Z := 0.3
## The car's right side is -Z: it faces -X with +Y up.
const RIGHT := -1.0
const MUFFLER_LEN := 0.62
## Camera distance below the parts it looks up at, and how far it can tilt off straight up.
const CAM_DISTANCE := 2.35
const CAM_DISTANCE_MIN := 0.6
const CAM_DISTANCE_MAX := 3.0
const ZOOM_STEP := 0.15
const TILT_MAX := 0.7
## Height the camera looks up at: about where the pipes and the axle hang.
const FOCUS_Y := 0.85
## Starting tilt across the car, so the parts show some depth.
const TILT_SIDE := 0.3
## A part lowers this far off its mounts, then slides out from under the car.
const LOWER := 0.17
const SLIDE_OUT := 1.9

const T_UNBOLT := 0.35
const T_LOWER := 0.5
const T_SLIDE := 0.7
const T_PAUSE := 0.15

const SLOT_NAMES := {
	"manifold": "Exhaust manifolds",
	"exhaust": "Exhaust",
	"muffler": "Muffler",
	"muffler_left": "Left muffler",
	"differential": "Rear end",
	"springs": "Springs",
	"shocks": "Shocks",
}
const SLOT_PLURALS := {
	"manifold": "exhaust manifolds",
	"exhaust": "exhausts",
	"muffler": "mufflers",
	"muffler_left": "mufflers",
	"differential": "rear ends",
	"springs": "springs",
	"shocks": "shocks",
}
const SLOT_KEYS := {
	"manifold": "1",
	"exhaust": "2",
	"muffler": "3",
	"muffler_left": "4",
	"differential": "5",
	"springs": "6",
	"shocks": "7",
}
const _SLOT_KEYCODES := {
	KEY_1: "manifold",
	KEY_2: "exhaust",
	KEY_3: "muffler",
	KEY_4: "muffler_left",
	KEY_5: "differential",
	KEY_6: "springs",
	KEY_7: "shocks",
}

const _IRON := Color(0.22, 0.2, 0.19)
const _RUST := Color(0.2, 0.13, 0.1)
const _CHROME := Color(0.82, 0.83, 0.85)
const _CERAMIC := Color(0.7, 0.7, 0.68)
const _ALUMINIZED := Color(0.6, 0.6, 0.58)
const _STEEL := Color(0.55, 0.56, 0.58)
const _UNDERBODY := Color(0.09, 0.085, 0.08)
const _SOOT := Color(0.05, 0.045, 0.04)
const _CREAM := Color(0.95, 0.9, 0.78, 1)
const _HOVER := Color(0.95, 0.62, 0.22)
const _SPRING_COLORS := {
	"stock": Color(0.14, 0.14, 0.14),
	"heavy": Color(0.62, 0.1, 0.08),
	"lowering": Color(0.1, 0.25, 0.6),
	"racing": Color(0.85, 0.72, 0.1),
}
const _SHOCK_COLORS := {
	"stock": Color(0.3, 0.3, 0.3),
	"gas": Color(0.8, 0.62, 0.08),
	"racing": Color(0.7, 0.1, 0.1),
}
## Leaves in a rear leaf spring, by the spring's style.
const _SPRING_LEAVES := {"stock": 2, "heavy": 3, "lowering": 3, "racing": 4}
const _COIL_RADIUS := 0.055
const _COIL_TURNS := 5
const _SHOCK_Z := 0.6
const _RATE := 22050

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $UI/Root

var _wheelbase := 2.6
var _front_x := -1.3
var _rear_x := 1.3
## Rear face of the engine block, where the bellhousing starts.
var _engine_rear := -0.35
var _muffler_x := 0.5
var _focus := Vector3.ZERO
var _distance := CAM_DISTANCE
## Tilt across the car and along it, in radians off straight up.
var _tilt_side := TILT_SIDE
var _tilt_length := 0.0
var _looking: bool = false
var _busy: bool = false
var _hover: String = ""
## Part rigs by slot. Built in world space under a node that only moves to animate.
var _rigs := {}
var _nav := _MenuNav.new()

var _part_labels := {}
var _stats_label: Label
var _hint: Label
var _tooltip: Label
var _slot_btns := {}
var _done_btn: Button
var _picker: Control
var _picker_slot: String = ""
var _picker_title: Label
var _picker_rows: VBoxContainer
var _picker_note: Label

var _sfx_ratchet: AudioStreamPlayer
var _sfx_snug: AudioStreamPlayer
var _sfx_clunk: AudioStreamPlayer


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	GameState.update_music()
	if not GameState.has_active_car():
		get_tree().change_scene_to_file.call_deferred(GameState.SCENE_GARAGE)
		return
	_lay_out()
	_build_world()
	_build_chassis()
	_build_engine()
	_build_driveline()
	for slot in GameState.UNDER_CAR_SLOTS:
		_rebuild_rig(slot)
	_build_zones()
	_build_sounds()
	_build_ui()
	_update_camera()
	_refresh_ui()


func _process(_delta: float) -> void:
	if _picker == null:
		return
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
			_looking = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if _picker.visible:
			return
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_distance = clampf(_distance + dir * ZOOM_STEP, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
			_update_camera()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var slot := _slot_at(mb.position)
			if not slot.is_empty():
				get_viewport().set_input_as_handled()
				_open_picker(slot)
		return
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if mg.factor > 0.0001:
			_distance = clampf(_distance / mg.factor, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
			_update_camera()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _looking:
		var mm := event as InputEventMouseMotion
		_tilt_length = clampf(_tilt_length - mm.relative.x * 0.005, -TILT_MAX, TILT_MAX)
		_tilt_side = clampf(_tilt_side + mm.relative.y * 0.005, -TILT_MAX, TILT_MAX)
		_update_camera()
		get_viewport().set_input_as_handled()


func _handle_key(key: InputEventKey) -> void:
	if not key.pressed:
		return
	if _picker.visible:
		if key.echo:
			return
		if _nav.handle_event(self, key):
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_ESCAPE:
			_close_picker()
			get_viewport().set_input_as_handled()
		return
	if key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		# Mark the key first. Leaving drops this scene, and the viewport is gone after that.
		get_viewport().set_input_as_handled()
		_on_done_pressed()
		return
	elif _SLOT_KEYCODES.has(key.keycode):
		_open_picker(str(_SLOT_KEYCODES[key.keycode]))
	else:
		return
	get_viewport().set_input_as_handled()


# --- Camera ----------------------------------------------------------------------


func _update_camera() -> void:
	var dir := Basis(Vector3.RIGHT, _tilt_side) * Basis(Vector3.BACK, _tilt_length) * Vector3.DOWN
	_camera.global_position = _focus + dir * _distance
	# Looking straight up with the front of the car off to the right of the screen.
	_camera.look_at(_focus, Vector3.FORWARD)


# --- Picking parts -------------------------------------------------------------


func _slot_at(screen_pos: Vector2) -> String:
	if _busy:
		return ""
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 10.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var node := hit.get("collider") as Node
	if node == null or not node.has_meta(&"under_car_slot"):
		return ""
	var slot := str(node.get_meta(&"under_car_slot"))
	if _is_six() and not GameState.has_dual_exhaust():
		# A six's single muffler hangs on the left, where the dual's left one would.
		if slot == GameState.SLOT_MUFFLER_LEFT:
			slot = GameState.SLOT_MUFFLER
		elif slot == GameState.SLOT_MUFFLER:
			return ""
	return slot if GameState.active_slots().has(slot) else ""


func _update_hover() -> void:
	var slot := ""
	var vp := get_viewport()
	if not _picker.visible and not _looking and vp.gui_get_hovered_control() == null:
		slot = _slot_at(GameState.pointer_position(vp))
	if slot != _hover:
		_light_rig(_hover, false)
		_hover = slot
		_light_rig(_hover, true)
	if _hover.is_empty():
		_tooltip.visible = false
		return
	_tooltip.text = _slot_hint(_hover)
	_tooltip.visible = true
	_tooltip.reset_size()
	_tooltip.position = GameState.pointer_position(vp) + Vector2(18.0, 14.0)


func _light_rig(slot: String, lit: bool) -> void:
	if slot.is_empty() or not _rigs.has(slot):
		return
	for node in (_rigs[slot] as Node3D).find_children("*", "MeshInstance3D", true, false):
		var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = lit
		mat.emission = _HOVER
		mat.emission_energy_multiplier = 0.12


func _slot_hint(slot: String) -> String:
	var part := GameState.slot_part(slot)
	if part.is_empty():
		return "%s — none, click to fit one" % _slot_name(slot)
	return "%s — %s" % [_slot_name(slot), str(part.get("name", "Part"))]


## Which side a muffler slot hangs on: a dual exhaust's two either side, and a single
## exhaust's on the right, but on the six's left, under its manifold.
func _muffler_side(slot: String) -> float:
	if slot == GameState.SLOT_MUFFLER_LEFT:
		return -RIGHT
	return -RIGHT if _is_six() and not GameState.has_dual_exhaust() else RIGHT


## The muffler of a dual exhaust is the right-hand one.
func _slot_name(slot: String) -> String:
	if slot == GameState.SLOT_MUFFLER and GameState.has_dual_exhaust():
		return "Right muffler"
	return str(SLOT_NAMES[slot])


func _open_picker(slot: String) -> void:
	if _busy or slot.is_empty() or not GameState.active_slots().has(slot):
		return
	_picker_slot = slot
	_picker_title.text = "Spare %s" % SLOT_PLURALS[slot]
	for child in _picker_rows.get_children():
		_picker_rows.remove_child(child)
		child.free()
	var fitted := GameState.slot_part(slot)
	var spares := GameState.spare_slot_parts(slot)
	for part in spares:
		_picker_rows.add_child(_picker_row(str(part.get("name", "Part")), GameState.part_detail(part), "Fit", str(part.get("id", ""))))
	if GameState.REMOVABLE_SLOTS.has(slot) and not fitted.is_empty():
		if slot == GameState.SLOT_EXHAUST:
			_picker_rows.add_child(_picker_row("Take the exhaust off", "Open headers: loud, and the mufflers come off too", "Remove", ""))
		else:
			_picker_rows.add_child(_picker_row("Take the muffler off", "Open pipe: loud, and no faster", "Remove", ""))
	var lines: Array[String] = ["Nothing on the car now." if fitted.is_empty() else "On the car: %s" % str(fitted.get("name", "Part"))]
	if spares.is_empty():
		lines.append("No spare %s. The newspaper sells them." % SLOT_PLURALS[slot])
	if GameState.spot_kind(slot) == GameState.SLOT_MUFFLER:
		if GameState.slot_part(GameState.SLOT_EXHAUST).is_empty():
			lines.append("Put an exhaust on first: a muffler needs a pipe to hang on.")
		elif GameState.has_dual_exhaust():
			lines.append("Each muffler on a dual exhaust gives half its gain.")
	_picker_note.text = "\n".join(lines)
	_picker.visible = true
	_tooltip.visible = false
	_sync_nav()


func _picker_row(title: String, detail: String, action: String, part_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s\n%s" % [title, detail]
	label.add_theme_color_override(&"font_color", _CREAM)
	row.add_child(label)
	var btn := Button.new()
	btn.text = action
	btn.custom_minimum_size = Vector2(84, 0)
	btn.pressed.connect(_swap.bind(_picker_slot, part_id))
	row.add_child(btn)
	return row


func _close_picker() -> void:
	_picker.visible = false
	_sync_nav()


func _sync_nav() -> void:
	if _picker.visible:
		_nav.setup(_nav.collect_buttons(_picker))
	else:
		_nav.clear()


## Takes the part in `slot` down and puts `part_id` up in its place. An empty id takes
## the part off and leaves the slot empty. The mufflers hang on the exhaust, so they come
## down with it, and any that stay on go back up with the new one.
func _swap(slot: String, part_id: String) -> void:
	if _busy:
		return
	var err := GameState.remove_slot_part(slot) if part_id.is_empty() else GameState.fit_slot_part(part_id, slot)
	if not err.is_empty():
		_picker_note.text = err
		return
	_close_picker()
	_busy = true
	_light_rig(_hover, false)
	_hover = ""
	_refresh_ui()
	var affected: Array[String] = [slot]
	if slot == GameState.SLOT_EXHAUST:
		affected.append_array([GameState.SLOT_MUFFLER, GameState.SLOT_MUFFLER_LEFT])
	var old: Array[Node3D] = []
	for each in affected:
		if _rigs.has(each):
			old.append(_rigs[each])
			_rigs.erase(each)
	if not old.is_empty():
		_hint.text = "Unbolting the %s…" % _slot_name(slot).to_lower()
		_play(_sfx_ratchet)
		await _pause(T_UNBOLT)
		_play(_sfx_ratchet)
		await _pause(T_UNBOLT)
		await _move_rigs(old, Vector3(0.0, -LOWER, 0.0), T_LOWER)
		_play(_sfx_clunk)
		await _move_rigs(old, Vector3(0.0, -LOWER, SLIDE_OUT), T_SLIDE)
		if not is_instance_valid(self):
			return
		for rig in old:
			rig.queue_free()
	var fresh: Array[Node3D] = []
	for each in affected:
		var rig := _rebuild_rig(each)
		if rig != null:
			rig.position = Vector3(0.0, -LOWER, -SLIDE_OUT)
			fresh.append(rig)
	if not fresh.is_empty():
		_hint.text = "Putting the %s up…" % str(GameState.slot_part(slot).get("name", "part")).to_lower()
		await _pause(T_PAUSE)
		await _move_rigs(fresh, Vector3(0.0, -LOWER, 0.0), T_SLIDE)
		await _move_rigs(fresh, Vector3.ZERO, T_LOWER)
		_play(_sfx_clunk)
		await _pause(T_PAUSE)
		_play(_sfx_ratchet)
		await _pause(T_UNBOLT)
		_play(_sfx_snug)
		await _pause(T_UNBOLT)
	if not is_instance_valid(self):
		return
	_busy = false
	_refresh_ui()


## Moves the rigs together, each to `to` off its place on the car.
func _move_rigs(rigs: Array[Node3D], to: Vector3, duration: float) -> void:
	if not is_instance_valid(self):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for rig in rigs:
		if is_instance_valid(rig):
			tw.tween_property(rig, "position", to, duration)
	await tw.finished


func _pause(seconds: float) -> void:
	if not is_instance_valid(self):
		return
	await get_tree().create_timer(seconds).timeout


func _on_done_pressed() -> void:
	if _busy:
		return
	_nav.clear()
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


# --- UI ----------------------------------------------------------------------


func _refresh_ui() -> void:
	var active := GameState.active_slots()
	for slot in GameState.UNDER_CAR_SLOTS:
		var part := GameState.slot_part(slot)
		var label: Label = _part_labels[slot]
		label.visible = active.has(slot)
		label.text = "%s: %s" % [_slot_name(slot), "none" if part.is_empty() else str(part.get("name", "Part"))]
		var btn: Button = _slot_btns[slot]
		btn.visible = active.has(slot)
		btn.disabled = _busy
		btn.text = "%s (%s)" % [_slot_name(slot).replace("Exhaust manifolds", "Manifolds"), SLOT_KEYS[slot]]
	_stats_label.text = "%.0f hp · %s" % [GameState.engine_power_hp, GameState.speed_text(GameState.get_effective_vmax_kmh())]
	_done_btn.disabled = _busy
	if _busy:
		return
	var tip := "Click a part to change it. The wheel zooms; right-drag tilts the view."
	if GameState.has_engine() and GameState.slot_part(GameState.SLOT_MANIFOLD).is_empty():
		_hint.text = "The engine has no exhaust manifolds and won't run without them. " + tip
		return
	if GameState.slot_part(GameState.SLOT_EXHAUST).is_empty():
		_hint.text = "The headers are open with no exhaust on. " + tip
		return
	for slot in GameState.muffler_slots():
		if GameState.slot_part(slot).is_empty():
			_hint.text = "A pipe ends open where its muffler would bolt on. " + tip
			return
	_hint.text = tip


func _build_ui() -> void:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override(&"panel", _panel_style())
	header.position = Vector2(16, 16)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(header)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 4)
	header.add_child(info)
	info.add_child(_ui_label("Under the car — %s" % GameState.car_name, 22))
	for slot in GameState.UNDER_CAR_SLOTS:
		var line := _ui_label("", 16)
		_part_labels[slot] = line
		info.add_child(line)
	_stats_label = _ui_label("", 16)
	info.add_child(_stats_label)

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override(&"panel", _panel_style())
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16.0
	bottom.offset_right = -16.0
	bottom.offset_top = -100.0
	bottom.offset_bottom = -16.0
	_ui.add_child(bottom)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	bottom.add_child(rows)
	_hint = _ui_label("", 18)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_hint)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 12)
	rows.add_child(bar)
	for slot in GameState.UNDER_CAR_SLOTS:
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_open_picker.bind(slot))
		bar.add_child(btn)
		_slot_btns[slot] = btn
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	_done_btn = Button.new()
	_done_btn.text = "Done"
	_done_btn.focus_mode = Control.FOCUS_NONE
	_done_btn.custom_minimum_size = Vector2(96, 0)
	_done_btn.pressed.connect(_on_done_pressed)
	bar.add_child(_done_btn)

	_tooltip = _ui_label("", 18)
	_tooltip.visible = false
	_tooltip.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	_tooltip.add_theme_constant_override(&"shadow_offset_x", 2)
	_tooltip.add_theme_constant_override(&"shadow_offset_y", 2)
	_ui.add_child(_tooltip)

	_build_picker()


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
	panel.offset_left = -270.0
	panel.offset_right = 270.0
	panel.offset_top = -200.0
	panel.offset_bottom = 200.0
	_picker.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	_picker_title = _ui_label("", 22)
	_picker_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_picker_title)
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
	var close := Button.new()
	close.text = "Forget it"
	close.pressed.connect(_close_picker)
	box.add_child(close)
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


# --- The car -------------------------------------------------------------------


## Axles from the car's wheelbase. The engine sits just behind the front axle.
func _lay_out() -> void:
	var chassis: Variant = GameState.car_spec.get("chassis", {})
	if typeof(chassis) == TYPE_DICTIONARY:
		_wheelbase = clampf(float((chassis as Dictionary).get("wheelbase", _wheelbase)), 2.2, 3.4)
	_front_x = -_wheelbase * 0.5
	_rear_x = _wheelbase * 0.5
	_engine_rear = _front_x + 0.95
	_muffler_x = _rear_x - 0.35 - MUFFLER_LEN * 0.5
	# Halfway between the front of the manifolds and the back of the rear end cover.
	_focus = Vector3((_engine_rear - 0.6 + _rear_x + 0.25) * 0.5 - 0.1, FOCUS_Y, 0.0)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.045, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# Trouble lights down on the floor under each part, and the shop lights beyond.
	for spot: float in [_engine_rear - 0.3, _muffler_x, _rear_x]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(spot, 0.3, -0.45)
		lamp.light_color = Color(1.0, 0.86, 0.66)
		lamp.light_energy = 0.9
		lamp.omni_range = 1.7
		lamp.shadow_enabled = true
		add_child(lamp)
	for side: float in [-1.0, 1.0]:
		var fill := OmniLight3D.new()
		fill.position = Vector3(0.0, 0.5, 2.4 * side)
		fill.light_color = Color(0.7, 0.78, 0.95)
		fill.light_energy = 0.8
		fill.omni_range = 4.0
		add_child(fill)


## Floor, floor pan, frame, body sides in the car's paint, wheels, and jack stands.
func _build_chassis() -> void:
	var concrete := _mat(Color(0.32, 0.31, 0.3), 0.0, 0.9)
	var under := _mat(_UNDERBODY, 0.2, 0.8)
	var frame := _mat(Color(0.12, 0.12, 0.12), 0.4, 0.6)
	var paint := _mat(GameState.car_color, 0.3, 0.4)
	var chrome := _mat(_CHROME, 0.9, 0.15)
	var rubber := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.9)
	var rim := _mat(Color(0.45, 0.45, 0.47), 0.7, 0.35)
	var stand := _mat(Color(0.36, 0.1, 0.07), 0.3, 0.5)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 8.0)
	floor.mesh = plane
	floor.material_override = concrete
	add_child(floor)
	var front := _front_x - 0.85
	var back := _rear_x + 1.05
	var length := back - front
	var mid := (front + back) * 0.5
	_box(self, Vector3(length, 0.03, BODY_HALF * 2.0), Vector3(mid, PAN_Y, 0.0), under)
	# Transmission tunnel down the middle of the pan.
	_box(self, Vector3(_rear_x - _engine_rear, 0.06, 0.3), Vector3((_engine_rear + _rear_x) * 0.5, PAN_Y - 0.04, 0.0), under)
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(length - 0.5, 0.1, 0.08), Vector3(mid, FRAME_Y, FRAME_HALF * side), frame)
		# Rocker: undercoated inside, the paint only on its outer skin.
		_box(self, Vector3(length, 0.2, 0.04), Vector3(mid, PAN_Y - 0.06, BODY_HALF * side), under)
		_box(self, Vector3(length, 0.24, 0.01), Vector3(mid, PAN_Y - 0.06, (BODY_HALF + 0.025) * side), paint)
		for axle_x: float in [_front_x, _rear_x]:
			_cylinder_z(self, WHEEL_R, 0.2, Vector3(axle_x, AXLE_Y, TRACK_HALF * side), rubber)
			_cylinder_z(self, WHEEL_R * 0.62, 0.205, Vector3(axle_x, AXLE_Y, TRACK_HALF * side), rim)
		# Jack stands under the frame, behind each axle.
		for stand_x: float in [_front_x + 0.35, _rear_x + 0.5]:
			var post := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.025
			cone.bottom_radius = 0.09
			cone.height = FRAME_Y - 0.05
			cone.radial_segments = 4
			post.mesh = cone
			post.material_override = stand
			post.position = Vector3(stand_x, (FRAME_Y - 0.05) * 0.5, FRAME_HALF * side)
			add_child(post)
	# Bumpers at both ends, unless one is stripped.
	if not GameState.bumper_stripped("front"):
		_box(self, Vector3(0.1, 0.1, BODY_HALF * 2.0), Vector3(front, PAN_Y - 0.08, 0.0), chrome)
	if not GameState.bumper_stripped("rear"):
		_box(self, Vector3(0.1, 0.1, BODY_HALF * 2.0), Vector3(back, PAN_Y - 0.08, 0.0), chrome)
	# Front crossmember under the engine and the rear one ahead of the tank.
	_box(self, Vector3(0.12, 0.08, FRAME_HALF * 2.0), Vector3(_front_x + 0.1, FRAME_Y - 0.02, 0.0), frame)
	_box(self, Vector3(0.1, 0.08, FRAME_HALF * 2.0), Vector3(_rear_x + 0.45, FRAME_Y, 0.0), frame)
	# Gas tank behind the axle.
	_box(self, Vector3(0.42, 0.18, 0.9), Vector3(_rear_x + 0.72, PAN_Y - 0.12, 0.0), _mat(Color(0.18, 0.18, 0.17), 0.5, 0.5))
	# Front suspension: lower control arms out to the spindles.
	for side: float in [-1.0, 1.0]:
		_tube(self, Vector3(_front_x + 0.15, FRAME_Y - 0.06, FRAME_HALF * 0.7 * side), Vector3(_front_x, AXLE_Y - 0.08, (TRACK_HALF - 0.12) * side), 0.025, frame)
		_tube(self, Vector3(_front_x - 0.15, FRAME_Y - 0.06, FRAME_HALF * 0.7 * side), Vector3(_front_x, AXLE_Y - 0.08, (TRACK_HALF - 0.12) * side), 0.025, frame)


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
	# A flathead's and a small-block's exhaust is the manifold slot's, drawn with it; and
	# with the belt off, what it drives is off too.
	var off: Array[String] = []
	if _is_flathead() or _is_sbc() or _is_six():
		off.append("exhaust")
	if not GameState.front_drive:
		off.append_array(_FRONT_NODES)
	for node in engine.find_children("*", "MeshInstance3D", true, false):
		for prefix in off:
			if str(node.name).begins_with(prefix):
				node.get_parent().remove_child(node)
				node.free()
				break
	add_child(engine)
	engine.transform = _engine_xform()


## Whether `engine` (the fitted one when empty) is a Ford flathead.
func _is_flathead(engine: Dictionary = {}) -> bool:
	if engine.is_empty():
		if not GameState.has_engine():
			return false
		engine = GameState.get_equipped_engine()
	return GameState.engine_family(engine) == _EngineAssembly.FH_FAMILY


## Whether `engine` (the fitted one when empty) is the Chevy six.
func _is_six(engine: Dictionary = {}) -> bool:
	if engine.is_empty():
		if not GameState.has_engine():
			return false
		engine = GameState.get_equipped_engine()
	return GameState.engine_family(engine) == _EngineAssembly.SIX_FAMILY


## Whether `engine` (the fitted one when empty) is the Chevy small-block.
func _is_sbc(engine: Dictionary = {}) -> bool:
	if engine.is_empty():
		if not GameState.has_engine():
			return false
		engine = GameState.get_equipped_engine()
	return GameState.engine_family(engine) == _EngineAssembly.SB_FAMILY


## Engine model units to this scene, as the engine is placed: stood up, its block's back
## face (a flathead's bell housing) at `_engine_rear`.
func _engine_xform(flathead: bool = _is_flathead(), sbc: bool = _is_sbc(), six: bool = _is_six()) -> Transform3D:
	var rear_x := ENGINE_REAR_X
	if flathead:
		rear_x = _EngineAssembly.fh(Vector3(_FH_BELL_BACK, 0.0, 0.0)).x
	elif sbc:
		rear_x = _EngineAssembly.fh(Vector3(_EngineAssembly.SB_BLOCK_BACK, 0.0, 0.0)).x
	elif six:
		rear_x = _EngineAssembly.fh(Vector3(_SIX_BACK, 0.0, 0.0)).x
	var basis := Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * ENGINE_SCALE)
	return Transform3D(basis, Vector3(_engine_rear - rear_x * ENGINE_SCALE, CRANK_Y - ENGINE_CRANK_Y * ENGINE_SCALE, 0.0))


## A point of the flathead in inches on the scene's `side` (its right is -Z), placed.
func _fh_point(p: Vector3, side: float) -> Vector3:
	return _engine_xform(true) * _EngineAssembly.fh(Vector3(p.x, -side * p.y, p.z))


## A point of the six in inches from its block's middle, placed.
func _six_point(p: Vector3) -> Vector3:
	return _engine_xform(false, false, true) * _EngineAssembly.six(p)


## The six's exhaust outlets for its manifold part's style, front to back, placed.
func _six_outlets() -> Array[Vector3]:
	var style := str(GameState.slot_part(GameState.SLOT_MANIFOLD).get("style", "log"))
	var out: Array[Vector3] = []
	for p: Vector3 in _SIX_OUTLETS.get(style, _SIX_OUTLETS["log"]):
		out.append(_six_point(p))
	return out


## A point of the small-block in inches on the right bank, moved to the scene's `side`'s
## bank and placed.
func _sb_point(p: Vector3, side: float) -> Vector3:
	var x := _EngineAssembly.sb_bank_x(-side, p.x)
	return _engine_xform(false, true) * _EngineAssembly.fh(Vector3(x, -side * p.y, p.z))


## Gearbox (seen from below, it is changed on the lift), driveshaft, and axle housing.
func _build_driveline() -> void:
	var steel := _mat(_STEEL, 0.7, 0.35)
	var iron := _mat(_IRON, 0.5, 0.6)
	var tail := _engine_rear + 0.2
	if GameState.has_gearbox():
		var box := GameState.get_equipped_gearbox()
		var case_color := _IRON if bool(box.get("automatic", false)) else Color(0.62, 0.62, 0.6)
		var case_mat := _mat(case_color, 0.55, 0.45)
		_cylinder_x(self, 0.17, 0.12, 0.24, _engine_rear, case_mat, CRANK_Y, 0.0, 24)
		_box(self, Vector3(0.36, 0.19, 0.18), Vector3(_engine_rear + 0.42, CRANK_Y - 0.01, 0.0), case_mat)
		_cylinder_x(self, 0.07, 0.05, 0.24, _engine_rear + 0.6, case_mat, CRANK_Y, 0.0, 20)
		tail = _engine_rear + 0.84
	var pinion := Vector3(_rear_x - 0.31, AXLE_Y + 0.02, 0.0)
	_tube(self, Vector3(tail, CRANK_Y, 0.0), pinion, 0.038, steel)
	# Axle tubes out to the brake drums. The center section is the rear end part.
	for side: float in [-1.0, 1.0]:
		_tube(self, Vector3(_rear_x, AXLE_Y, 0.1 * side), Vector3(_rear_x, AXLE_Y, (TRACK_HALF - 0.12) * side), 0.042, iron)
		_cylinder_z(self, 0.15, 0.08, Vector3(_rear_x, AXLE_Y, (TRACK_HALF - 0.12) * side), iron)


## Coil springs from the frame down to the front control arms, and a leaf spring under the
## axle at the back. Stiffer springs have a color of their own and more leaves.
func _build_springs(rig: Node3D, style: String) -> void:
	var mat := _mat(_SPRING_COLORS.get(style, _SPRING_COLORS["stock"]), 0.5, 0.45)
	var leaves := int(_SPRING_LEAVES.get(style, 2))
	for side: float in [-1.0, 1.0]:
		_build_coil(rig, Vector3(_front_x, FRAME_Y - 0.04, FRAME_HALF * 0.95 * side), AXLE_Y - 0.06, mat)
		for leaf in leaves:
			var length := 1.2 - 0.3 * float(leaf)
			_box(rig, Vector3(length, 0.022, 0.06), Vector3(_rear_x, AXLE_Y - 0.06 - 0.024 * float(leaf), FRAME_HALF * side), mat)


func _build_coil(rig: Node3D, center: Vector3, bottom_y: float, mat: Material) -> void:
	var points: Array[Vector3] = []
	var steps := _COIL_TURNS * 8
	for i in steps + 1:
		var t := float(i) / float(steps)
		var angle := t * TAU * float(_COIL_TURNS)
		points.append(Vector3(center.x + cos(angle) * _COIL_RADIUS, lerpf(center.y, bottom_y, t), center.z + sin(angle) * _COIL_RADIUS))
	_pipe(rig, points, 0.009, mat)


## A shock at each corner: its body, the chrome rod, and on racing shocks a reservoir.
func _build_shocks(rig: Node3D, style: String) -> void:
	var body := _mat(_SHOCK_COLORS.get(style, _SHOCK_COLORS["stock"]), 0.4, 0.45)
	var rod := _mat(_CHROME, 0.9, 0.2)
	for side: float in [-1.0, 1.0]:
		for axle_x: float in [_front_x, _rear_x]:
			var top := Vector3(axle_x + 0.16, FRAME_Y + 0.02, _SHOCK_Z * 0.86 * side)
			var bottom := Vector3(axle_x + 0.03, AXLE_Y - 0.05, _SHOCK_Z * side)
			var middle := top.lerp(bottom, 0.45)
			_tube(rig, top, middle, 0.012, rod)
			_tube(rig, middle, bottom, 0.03, body)
			if style == "racing":
				_cylinder_x(rig, 0.024, 0.024, 0.1, middle.x + 0.03, body, middle.y, middle.z + 0.05 * side, 14)


## Head pipes from the manifold flanges back to where the muffler bolts on. A single
## exhaust crosses the left pipe over to the right one ahead of its muffler; a dual
## exhaust runs a pipe straight back on each side. An open end shows with no muffler.
func _build_exhaust(rig: Node3D, dual: bool) -> void:
	var pipe := _exhaust_pipe_mat()
	var soot := _mat(_SOOT, 0.0, 1.0)
	var end_x := _muffler_x - MUFFLER_LEN * 0.5 - 0.08
	var ends: Array[float] = [RIGHT]
	if dual:
		ends.append(-RIGHT)
	if _is_six():
		_build_six_exhaust(rig, dual, end_x, pipe, soot)
		return
	var flathead := _is_flathead()
	for side in ends:
		var start := _pipe_start(side)
		var end := Vector3(end_x, PIPE_Y, MUFFLER_Z * side)
		if flathead or _is_sbc():
			# Down from the outlet, then back beside the pan.
			_pipe(rig, [start, Vector3(start.x + 0.08, PIPE_Y, start.z), end], 0.028, pipe)
		else:
			_tube(rig, start, end, 0.028, pipe)
		_cylinder_x(rig, 0.024, 0.024, 0.002, end_x, soot, PIPE_Y, MUFFLER_Z * side, 16)
	if dual:
		return
	if flathead:
		# The left pipe drops and crosses under the front of the pan, ahead of the sump,
		# into the right one.
		var from := _pipe_start(-RIGHT)
		var into := _pipe_start(RIGHT)
		var low := PIPE_Y - 0.035
		_pipe(rig, [from, Vector3(from.x + 0.06, low, from.z), Vector3(from.x + 0.1, low, into.z * 0.6), Vector3(into.x + 0.2, PIPE_Y, into.z + (MUFFLER_Z * RIGHT - into.z) * 0.1)], 0.026, pipe)
		return
	# Every run heads back from the flanges, never forward: the left pipe steps back,
	# then crosses under the driveshaft and joins the right one ahead of the muffler.
	var left := _pipe_start(-RIGHT)
	var span := end_x - _pipe_start(RIGHT).x
	var join := Vector3(end_x - span * 0.15, PIPE_Y, MUFFLER_Z * RIGHT)
	var cross: Array[Vector3] = [left, Vector3(left.x + span * 0.12, PIPE_Y, left.z), join]
	_pipe(rig, cross, 0.026, pipe)


## The six's pipes, all from its left: each drops from its outlet and runs straight back
## beside the flywheel housing and the bellhousing, clear of them. A single exhaust's
## muffler is on the left too, so its pipe runs straight on to it, the split headers' back
## outlet dropping into its run. On a dual exhaust (the split headers only) the front
## outlet's pipe keeps to the outside on to the left muffler and the back one's runs inside
## it and crosses to the right one under the gearbox's case behind the bellhousing, where
## it sits high enough.
func _build_six_exhaust(rig: Node3D, dual: bool, end_x: float, pipe: Material, soot: Material) -> void:
	var left := -RIGHT
	var outlets := _six_outlets()
	# Out past the flywheel housing's flange (7.3 in round the crank) with a pipe's width
	# to spare; the outer pipe outside that again.
	var inside := 0.18 * left
	var outside := 0.25 * left
	var under := _engine_rear + 0.3
	var over := _engine_rear + 0.6
	var right_end := Vector3(end_x, PIPE_Y, MUFFLER_Z * RIGHT)
	var front := outlets[0]
	var back := outlets[outlets.size() - 1]
	var crossing := outlets.size() > 1 and dual
	if not crossing:
		var run := Vector3(_engine_rear + 0.1, PIPE_Y, inside)
		_pipe(rig, [front, Vector3(front.x + 0.06, PIPE_Y, inside), run, Vector3(end_x, PIPE_Y, MUFFLER_Z * left)], 0.028, pipe)
		_cylinder_x(rig, 0.024, 0.024, 0.002, end_x, soot, PIPE_Y, MUFFLER_Z * left, 16)
		if outlets.size() > 1:
			_pipe(rig, [back, Vector3(back.x + 0.05, PIPE_Y, inside)], 0.026, pipe)
		return
	var drop := Vector3(back.x + 0.06, PIPE_Y, inside)
	_pipe(rig, [back, drop, Vector3(under, PIPE_Y, inside), Vector3(over, PIPE_Y, MUFFLER_Z * RIGHT), right_end], 0.028, pipe)
	_cylinder_x(rig, 0.024, 0.024, 0.002, end_x, soot, PIPE_Y, MUFFLER_Z * RIGHT, 16)
	_pipe(rig, [front, Vector3(front.x + 0.06, PIPE_Y, outside), Vector3(end_x, PIPE_Y, MUFFLER_Z * left)], 0.028, pipe)
	_cylinder_x(rig, 0.024, 0.024, 0.002, end_x, soot, PIPE_Y, MUFFLER_Z * left, 16)


func _exhaust_pipe_mat() -> StandardMaterial3D:
	return _mat(_ALUMINIZED.darkened(0.25), 0.6, 0.55)


## Kicks up over the axle on `side` and out the back.
func _build_tailpipe(rig: Node3D, side: float) -> void:
	var outlet := _muffler_x + MUFFLER_LEN * 0.5
	var tail: Array[Vector3] = [
		Vector3(outlet + 0.08, PIPE_Y, MUFFLER_Z * side),
		Vector3(_rear_x - 0.2, PIPE_Y, MUFFLER_Z * side),
		Vector3(_rear_x - 0.06, AXLE_Y + 0.22, (MUFFLER_Z + 0.08) * side),
		Vector3(_rear_x + 0.2, AXLE_Y + 0.22, (MUFFLER_Z + 0.08) * side),
		Vector3(_rear_x + 0.4, PIPE_Y + 0.02, (MUFFLER_Z + 0.1) * side),
		Vector3(_rear_x + 1.1, PIPE_Y + 0.02, (MUFFLER_Z + 0.1) * side),
	]
	_pipe(rig, tail, 0.027, _exhaust_pipe_mat())


## Where a head pipe leaves the manifold on `side`: behind the bellhousing, or on a
## flathead under the front of its log.
func _pipe_start(side: float) -> Vector3:
	if _is_six():
		# Both pipes start on the six's left: the front outlet feeds the right-hand run.
		var outlets := _six_outlets()
		return outlets[0] if side == RIGHT else outlets[outlets.size() - 1]
	if _is_flathead():
		return _fh_point(_FH_OUTLET, side)
	if _is_sbc():
		var style := str(GameState.slot_part(GameState.SLOT_MANIFOLD).get("style", "log"))
		return _sb_point(_SB_OUTLETS.get(style, _SB_OUTLETS["log"]), side)
	return Vector3(_engine_rear + 0.28, PIPE_Y, PIPE_Z * side)


## Static hot spots for each slot, so an empty one can still be clicked.
func _build_zones() -> void:
	if _is_six():
		var front := _six_point(Vector3(-_SIX_RUN.x, _SIX_RUN.y, _SIX_RUN.z))
		var back := _six_point(_SIX_RUN)
		_zone(GameState.SLOT_MANIFOLD, Vector3(back.x - front.x + 0.06, 0.24, 0.16), (front + back) * 0.5)
	for side: float in [-1.0, 1.0]:
		if _is_six():
			break
		if _is_flathead():
			var front := _fh_point(Vector3(_FH_LOG_X.x, _FH_OUTLET.y, _FH_LOG_Z), side)
			var back := _fh_point(Vector3(_FH_LOG_X.y, _FH_OUTLET.y, _FH_LOG_Z), side)
			_zone(GameState.SLOT_MANIFOLD, Vector3(back.x - front.x + 0.06, 0.2, 0.14), (front + back) * 0.5 + Vector3(0.0, -0.03, 0.0))
		elif _is_sbc():
			# Along the exhaust face, down to the manifold's outlet.
			var front := _sb_point(Vector3(-9.0, 10.5, 6.0), side)
			var back := _sb_point(Vector3(9.0, 10.5, 6.0), side)
			_zone(GameState.SLOT_MANIFOLD, Vector3(back.x - front.x, 0.24, 0.16), (front + back) * 0.5)
		else:
			_zone(GameState.SLOT_MANIFOLD, Vector3(0.82, 0.3, 0.16), Vector3(_engine_rear - 0.18, CRANK_Y - 0.05, 0.3 * side))
	_zone(GameState.SLOT_MUFFLER, Vector3(MUFFLER_LEN + 0.16, 0.24, 0.32), Vector3(_muffler_x, PIPE_Y, MUFFLER_Z * RIGHT))
	_zone(GameState.SLOT_MUFFLER_LEFT, Vector3(MUFFLER_LEN + 0.16, 0.24, 0.32), Vector3(_muffler_x, PIPE_Y, -MUFFLER_Z * RIGHT))
	# The head pipes, between the manifold flanges and the mufflers.
	var pipes_from := _pipe_start(RIGHT).x
	var pipes_to := _muffler_x - MUFFLER_LEN * 0.5 - 0.08
	_zone(GameState.SLOT_EXHAUST, Vector3(pipes_to - pipes_from, 0.14, MUFFLER_Z * 2.0 + 0.12), Vector3((pipes_from + pipes_to) * 0.5, PIPE_Y, 0.0))
	_zone(GameState.SLOT_DIFFERENTIAL, Vector3(0.62, 0.34, 0.4), Vector3(_rear_x - 0.06, AXLE_Y, 0.0))
	for side: float in [-1.0, 1.0]:
		_zone(GameState.SLOT_SPRINGS, Vector3(0.24, 0.3, 0.2), Vector3(_front_x, (FRAME_Y + AXLE_Y) * 0.5 - 0.04, FRAME_HALF * 0.95 * side))
		_zone(GameState.SLOT_SPRINGS, Vector3(1.24, 0.12, 0.1), Vector3(_rear_x, AXLE_Y - 0.08, FRAME_HALF * side))
		for axle_x: float in [_front_x, _rear_x]:
			_zone(GameState.SLOT_SHOCKS, Vector3(0.26, 0.4, 0.12), Vector3(axle_x + 0.1, (FRAME_Y + AXLE_Y) * 0.5, _SHOCK_Z * 0.95 * side))


func _zone(slot: String, size: Vector3, pos: Vector3) -> void:
	if slot == GameState.SLOT_MANIFOLD and not GameState.has_engine():
		return
	var body := StaticBody3D.new()
	body.set_meta(&"under_car_slot", slot)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	add_child(body)


# --- Parts ---------------------------------------------------------------------


## One part on its own, for a photograph. It is not added to this scene.
func build_preview(part: Dictionary) -> Node3D:
	var rig := Node3D.new()
	var style := str(part.get("style", ""))
	var slot := str(part.get("slot", ""))
	match slot:
		GameState.SLOT_MANIFOLD:
			if GameState.engine_family(part) == _EngineAssembly.SIX_FAMILY:
				_build_six_manifold(rig, part)
				return rig
			var model := _family_model(part)
			for side: float in [-1.0, 1.0]:
				_build_manifold(rig, style, side, model)
		GameState.SLOT_EXHAUST:
			_build_exhaust(rig, bool(part.get("dual", false)))
		GameState.SLOT_MUFFLER:
			_build_muffler(rig, style, MUFFLER_Z * RIGHT)
			_build_tailpipe(rig, RIGHT)
		GameState.SLOT_DIFFERENTIAL:
			_build_rear_end(rig, style, float(part.get("ratio", 3.08)))
		GameState.SLOT_SPRINGS:
			_preview_springs(rig, style)
		GameState.SLOT_SHOCKS:
			_preview_shock(rig, style)
	return rig


## A coil and a leaf pack, drawn with the same pieces as the car and set side by side.
func _preview_springs(rig: Node3D, style: String) -> void:
	var mat := _mat(_SPRING_COLORS.get(style, _SPRING_COLORS["stock"]), 0.5, 0.45)
	var leaves := int(_SPRING_LEAVES.get(style, 2))
	_build_coil(rig, Vector3(-0.28, 0.32, 0.0), 0.0, mat)
	for leaf: int in leaves:
		var length := 0.72 - 0.12 * float(leaf)
		_box(rig, Vector3(length, 0.022, 0.07), Vector3(0.22, 0.03 + 0.024 * float(leaf), 0.0), mat)


## One shock, standing, drawn with the same pieces as the car.
func _preview_shock(rig: Node3D, style: String) -> void:
	var body := _mat(_SHOCK_COLORS.get(style, _SHOCK_COLORS["stock"]), 0.4, 0.45)
	var rod := _mat(_CHROME, 0.9, 0.2)
	var top := Vector3(0.0, 0.48, 0.0)
	var bottom := Vector3(0.06, 0.0, 0.0)
	var middle := top.lerp(bottom, 0.45)
	_tube(rig, top, middle, 0.012, rod)
	_tube(rig, middle, bottom, 0.03, body)
	if style == "racing":
		_cylinder_x(rig, 0.024, 0.024, 0.1, middle.x + 0.03, body, middle.y, middle.z + 0.05, 14)


## Builds the rig for what is in `slot` now, or nothing for an empty slot.
func _rebuild_rig(slot: String) -> Node3D:
	var part := GameState.slot_part(slot)
	if part.is_empty():
		return null
	var rig := Node3D.new()
	rig.name = "Rig_%s" % slot
	add_child(rig)
	var style := str(part.get("style", ""))
	match slot:
		GameState.SLOT_MANIFOLD:
			if GameState.engine_family(part) == _EngineAssembly.SIX_FAMILY:
				_build_six_manifold(rig, part)
				return rig
			var model := _family_model(part)
			for side: float in [-1.0, 1.0]:
				_build_manifold(rig, style, side, model)
		GameState.SLOT_EXHAUST:
			_build_exhaust(rig, bool(part.get("dual", false)))
		GameState.SLOT_MUFFLER, GameState.SLOT_MUFFLER_LEFT:
			var side := _muffler_side(slot)
			_build_muffler(rig, style, MUFFLER_Z * side)
			_build_tailpipe(rig, side)
		GameState.SLOT_DIFFERENTIAL:
			_build_rear_end(rig, style, float(part.get("ratio", 3.08)))
		GameState.SLOT_SPRINGS:
			_build_springs(rig, style)
		GameState.SLOT_SHOCKS:
			_build_shocks(rig, style)
	_rigs[slot] = rig
	return rig


func _port(i: int, side: float) -> Vector3:
	return Vector3(_engine_rear - 0.12 - PORT_STEP * float(i), CRANK_Y + 0.08, HEAD_Z * side)


## The model a manifold part is drawn from: the model of a flathead for a flathead's; on
## the small-block, its cast-iron manifolds' (its own model) or the headers'; or "" for
## the others', which are drawn here.
func _family_model(part: Dictionary) -> String:
	if GameState.engine_family(part) != _EngineAssembly.FH_FAMILY:
		if not _is_sbc():
			return ""
		var headers := str(_EngineAssembly.SB_HEADERS.get(str(part.get("style", "")), ""))
		return headers if not headers.is_empty() else str(GameState.get_equipped_engine().get("model", ""))
	if _is_flathead():
		return str(GameState.get_equipped_engine().get("model", ""))
	for engine: Dictionary in GameState.ENGINES:
		if _is_flathead(engine):
			return str(engine.get("model", ""))
	return ""


## Log manifolds are rusty iron with the outlet at the back; shorty headers are chrome
## tubes into a collector by the bellhousing; long tubes run ceramic-gray clear back. A
## flathead's are its model's cast logs on that side, a small-block's its model's iron or
## the headers' (`model`).
func _build_manifold(rig: Node3D, style: String, side: float, model: String = "") -> void:
	if not model.is_empty():
		_build_model_manifold(rig, side, model)
		return
	var start := _pipe_start(side)
	var flange := _mat(_STEEL.darkened(0.2), 0.7, 0.4)
	_cylinder_x(rig, 0.04, 0.04, 0.012, start.x - 0.012, flange, start.y, start.z, 16)
	# Sooty bore, seen when no exhaust is bolted on.
	_cylinder_x(rig, 0.024, 0.024, 0.002, start.x, _mat(_SOOT, 0.0, 1.0), start.y, start.z, 16)
	match style:
		"shorty", "long-tube":
			var long := style == "long-tube"
			var mat := _mat(_CERAMIC if long else _CHROME, 0.75 if long else 0.95, 0.4 if long else 0.12)
			var collector := Vector3(start.x - (0.06 if long else 0.32), PIPE_Y + (0.0 if long else 0.06), (PIPE_Z - 0.01) * side)
			var drop := 0.17 if long else 0.1
			for i in PORT_COUNT:
				var port := _port(i, side)
				var out := port + Vector3(0.0, -0.03, 0.07 * side)
				var down := Vector3(port.x + 0.06, CRANK_Y - drop, (HEAD_Z + 0.1) * side)
				_pipe(rig, [port, out, down, collector + Vector3(-0.08, 0.02, 0.0)], 0.019, mat)
			_cylinder_x(rig, 0.045, 0.028, 0.1, collector.x - 0.08, mat, collector.y, collector.z, 18)
			_pipe(rig, [collector + Vector3(0.02, 0.0, 0.0), start], 0.027, mat)
		_:
			var iron := _mat(_RUST if style == "log" else _IRON, 0.3, 0.85)
			var log_z := (HEAD_Z + 0.06) * side
			var y := CRANK_Y + 0.05
			var first := _port(PORT_COUNT - 1, side).x - 0.04
			var last := _port(0, side).x + 0.05
			_cylinder_x(rig, 0.038, 0.045, last - first, first, iron, y, log_z, 16)
			for i in PORT_COUNT:
				var port := _port(i, side)
				_box(rig, Vector3(0.06, 0.055, 0.07), Vector3(port.x, port.y - 0.01, (HEAD_Z + 0.025) * side), iron)
			var elbow := Vector3(last - 0.01, y - 0.02, log_z)
			_pipe(rig, [elbow, Vector3(last + 0.04, PIPE_Y + 0.06, (PIPE_Z + 0.02) * side), start], 0.03, iron)


## A model's exhaust on the scene's `side`, placed as the engine is: a flathead's log, or
## the small-block's manifold or headers. A node's bank is the first number in its name.
## The six's manifold or headers from their model (the stock manifold is the engine's),
## all of it on the engine's left.
func _build_six_manifold(rig: Node3D, part: Dictionary) -> void:
	var path := str(part.get("model", ""))
	if path.is_empty():
		if _is_six():
			path = str(GameState.get_equipped_engine().get("model", ""))
		else:
			for engine: Dictionary in GameState.ENGINES:
				if _is_six(engine):
					path = str(engine.get("model", ""))
					break
	var packed: PackedScene = null
	if not path.is_empty():
		packed = load(path) as PackedScene
	if packed == null:
		push_warning("Engine model missing: %s" % path)
		return
	var model := packed.instantiate() as Node3D
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if not str(node.name).begins_with("exhaust"):
			node.get_parent().remove_child(node)
			node.free()
	model.transform = _engine_xform(false, false, true)
	rig.add_child(model)


func _build_model_manifold(rig: Node3D, side: float, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Engine model missing: %s" % path)
		return
	var model := packed.instantiate() as Node3D
	var bank := "%d" % int(-side)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var node_name := str(node.name)
		if not node_name.begins_with("exhaust") or _EngineAssembly.first_number(node_name) != bank:
			node.get_parent().remove_child(node)
			node.free()
	var flathead := path.get_file().contains("flathead")
	model.transform = _engine_xform(flathead, not flathead)
	rig.add_child(model)


## One muffler between the head pipe and the tailpipe, hung at `z` across the car.
func _build_muffler(rig: Node3D, style: String, z: float) -> void:
	var inlet := _muffler_x - MUFFLER_LEN * 0.5
	var outlet := _muffler_x + MUFFLER_LEN * 0.5
	var nipple := _mat(_ALUMINIZED.darkened(0.2), 0.6, 0.5)
	match style:
		"glasspack":
			var shell := _mat(_CHROME, 0.95, 0.12)
			var band := _mat(Color(0.55, 0.08, 0.06), 0.3, 0.4)
			_cylinder_x(rig, 0.03, 0.058, 0.08, inlet - 0.08, shell, PIPE_Y, z, 20)
			_cylinder_x(rig, 0.058, 0.058, MUFFLER_LEN, inlet, shell, PIPE_Y, z, 24)
			_cylinder_x(rig, 0.058, 0.03, 0.08, outlet, shell, PIPE_Y, z, 20)
			for at: float in [0.12, MUFFLER_LEN - 0.14]:
				_cylinder_x(rig, 0.061, 0.061, 0.02, inlet + at, band, PIPE_Y, z, 24)
		"turbo":
			var shell := _mat(_ALUMINIZED, 0.7, 0.4)
			var can := _cylinder_x(rig, 0.11, 0.11, MUFFLER_LEN - 0.12, inlet + 0.06, shell, PIPE_Y, z, 28)
			can.scale = Vector3(0.55, 1.0, 1.45)
			_cylinder_x(rig, 0.03, 0.03, 0.14, inlet - 0.08, nipple, PIPE_Y, z, 16)
			_cylinder_x(rig, 0.03, 0.03, 0.14, outlet - 0.06, nipple, PIPE_Y, z, 16)
		_:
			var shell := _mat(Color(0.3, 0.29, 0.27), 0.5, 0.65)
			var can := _cylinder_x(rig, 0.12, 0.12, MUFFLER_LEN - 0.06, inlet + 0.03, shell, PIPE_Y + 0.02, z, 28)
			can.scale = Vector3(0.75, 1.0, 1.15)
			_cylinder_x(rig, 0.03, 0.03, 0.12, inlet - 0.08, nipple, PIPE_Y, z, 16)
			_cylinder_x(rig, 0.03, 0.03, 0.12, outlet - 0.04, nipple, PIPE_Y, z, 16)


## The center section: pinion snout, carrier, and cover, with the ratio on a tag.
func _build_rear_end(rig: Node3D, style: String, ratio: float) -> void:
	var iron := _mat(_IRON, 0.5, 0.6)
	var cover_color := _IRON.lightened(0.08)
	var cover_metal := 0.5
	var cover_rough := 0.55
	match style:
		"chrome":
			cover_color = _CHROME
			cover_metal = 0.95
			cover_rough = 0.12
		"finned":
			cover_color = Color(0.68, 0.68, 0.66)
			cover_metal = 0.75
			cover_rough = 0.35
		"girdle":
			cover_color = Color(0.1, 0.1, 0.11)
			cover_metal = 0.4
			cover_rough = 0.45
	var cover := _mat(cover_color, cover_metal, cover_rough)
	var center := Vector3(_rear_x, AXLE_Y, 0.0)
	var carrier := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.15
	ball.height = 0.3
	carrier.mesh = ball
	carrier.material_override = iron
	carrier.scale = Vector3(0.85, 0.95, 1.0)
	carrier.position = center
	rig.add_child(carrier)
	_cylinder_x(rig, 0.05, 0.085, 0.2, _rear_x - 0.3, iron, AXLE_Y + 0.02, 0.0, 20)
	_cylinder_x(rig, 0.035, 0.035, 0.04, _rear_x - 0.34, _mat(_STEEL, 0.7, 0.35), AXLE_Y + 0.02, 0.0, 16)
	_cylinder_x(rig, 0.145, 0.15, 0.035, _rear_x + 0.09, cover, AXLE_Y, 0.0, 28)
	_cylinder_x(rig, 0.1, 0.12, 0.035, _rear_x + 0.125, cover, AXLE_Y, 0.0, 28)
	if style == "finned":
		for i in 5:
			var fy := AXLE_Y - 0.1 + 0.05 * float(i)
			_box(rig, Vector3(0.03, 0.012, 0.2), Vector3(_rear_x + 0.17, fy, 0.0), cover)
	elif style == "girdle":
		var bolt := _mat(_STEEL, 0.8, 0.3)
		for side: float in [-1.0, 1.0]:
			_box(rig, Vector3(0.025, 0.04, 0.24), Vector3(_rear_x + 0.17, AXLE_Y + 0.045 * side, 0.0), cover)
		for i in 10:
			var a := TAU * float(i) / 10.0
			_cylinder_x(rig, 0.01, 0.01, 0.02, _rear_x + 0.12, bolt, AXLE_Y + 0.13 * sin(a), 0.13 * cos(a), 6)
	var tag := Label3D.new()
	tag.text = "%.2f" % ratio
	tag.font_size = 48
	tag.pixel_size = 0.0015
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.95, 0.85, 0.5)
	tag.outline_size = 8
	tag.position = Vector3(_rear_x + 0.19, AXLE_Y - 0.12, 0.09)
	rig.add_child(tag)


# --- Mesh helpers ----------------------------------------------------------------


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


## A disc or drum across the car, centered on `pos`.
func _cylinder_z(parent: Node3D, radius: float, width: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	mi.position = pos
	parent.add_child(mi)
	return mi


## A straight tube from `a` to `b`.
func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var span := b - a
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = span.length()
	mesh.radial_segments = 14
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	var axis := span.normalized()
	if axis.is_equal_approx(Vector3.DOWN):
		mi.basis = Basis(Vector3.RIGHT, PI)
	elif not axis.is_equal_approx(Vector3.UP):
		mi.basis = Basis(Quaternion(Vector3.UP, axis))
	mi.position = (a + b) * 0.5
	parent.add_child(mi)
	return mi


## A bent pipe through `points`, with a ball at each bend to close the joint.
func _pipe(parent: Node3D, points: Array[Vector3], radius: float, mat: Material) -> void:
	for i in points.size() - 1:
		_tube(parent, points[i], points[i + 1], radius, mat)
		if i > 0:
			var joint := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = radius
			ball.height = radius * 2.0
			ball.radial_segments = 14
			ball.rings = 7
			joint.mesh = ball
			joint.material_override = mat
			joint.position = points[i]
			parent.add_child(joint)


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


## A heavy part coming off its mounts, or seating on them.
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
