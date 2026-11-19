extends Control

## The track maker: draw a race course on a top-down map, set its heights on the strip below,
## and take it for a test drive. Opened with `trackmaker` at the main menu's ~ prompt. It reads
## and writes `.trk` files (see `docs/track-format.md`); its own tracks go in `user://tracks`,
## and a copy run from the project can open and save the game's tracks in `assets/tracks`.
## A test drive writes the course to `GameState.TEST_DRIVE_TRACK`, keeps the maker's work in
## `GameState.track_maker_session`, and comes back here when it ends.

const _Doc := preload("res://scripts/track_maker_doc.gd")
const _MapView := preload("res://scripts/track_maker_map.gd")
const _ProfileView := preload("res://scripts/track_maker_profile.gd")
const _Skies := preload("res://scripts/skies.gd")
const _TrackSides := preload("res://scripts/track_sides.gd")
const _TrackTerrain := preload("res://scripts/track_terrain.gd")

const USER_TRACKS_DIR := "user://tracks"
const GAME_TRACKS_DIR := "res://assets/tracks"
const UNDO_LIMIT := 200
## Changes to one field this close together are one undo step.
const _UNDO_MERGE_MS := 1500
const _CHECK_DELAY_S := 0.3
const _PANEL_WIDTH := 340.0
const _LABEL_WIDTH := 84.0
const _CREAM := Color(0.95, 0.9, 0.78, 1)
const _DIM := Color(0.75, 0.7, 0.6, 1)
const _ERROR := Color(1.0, 0.45, 0.4, 1)
const _WARNING := Color(1.0, 0.78, 0.35, 1)
const _STYLES := [TrackFile.STYLE_CIRCUIT, TrackFile.STYLE_STREET, TrackFile.STYLE_MOUNTAIN, TrackFile.STYLE_AQUEDUCT]
const _ROAD_TYPES := [
	TrackFile.ROAD_REGULAR,
	TrackFile.ROAD_NARROW_LEFT,
	TrackFile.ROAD_NARROW_RIGHT,
	TrackFile.ROAD_NARROW_BOTH,
	TrackFile.ROAD_NARROW_LEFT_OBSTACLE,
	TrackFile.ROAD_NARROW_RIGHT_OBSTACLE,
	TrackFile.ROAD_NARROW_BOTH_OBSTACLE,
	TrackFile.ROAD_BRIDGE,
	TrackFile.ROAD_GRAVEL,
]
const _SURFACES := [TrackFile.SURFACE_REGULAR, TrackFile.SURFACE_DRY, TrackFile.SURFACE_WET, TrackFile.SURFACE_ICY]
const HELP := "Left click: add a node, split a road, or drag; with Ground, hold to paint (Ctrl+click picks a height) · Right drag: move the map · Wheel: zoom · Del: delete · Ctrl+Z / Ctrl+Y: undo / redo · Ctrl+S: save · F: whole track · F5: test drive · Esc: menu"

var doc: _Doc = _Doc.blank()
## The file the course was read from or last saved to, or "" for a new one.
var _path: String = ""
var _dirty: bool = false
var _undo: Array[_Doc] = []
var _redo: Array[_Doc] = []
var _last_tag: String = ""
var _last_tag_ms: int = 0
## What to do once the player agrees to throw away unsaved changes.
var _pending: Callable = Callable()

var _map: _MapView
var _profile: _ProfileView
var _check_timer: Timer
var _dialog: FileDialog
var _confirm: ConfirmationDialog
var _file_label: Label
var _status_label: Label
var _name_edit: LineEdit
var _style_option: OptionButton
var _jumps_check: CheckBox
var _auto_bank_check: CheckBox
var _loop_check: CheckBox
var _laps_spin: SpinBox
var _laps_row: HBoxContainer
var _sky_option: OptionButton
## The sky ids in `_sky_option`'s order.
var _sky_ids: Array[String] = []
var _length_label: Label
var _road_tool: Button
var _scenery_tool: Button
var _ground_tool: Button
var _ground_box: VBoxContainer
var _brush_option: OptionButton
var _brush_size_spin: SpinBox
var _brush_strength_spin: SpinBox
var _flatten_spin: SpinBox
var _flatten_row: HBoxContainer
var _ground_label: Label
var _snap_check: CheckBox
var _node_box: VBoxContainer
var _node_heading: Label
var _x_spin: SpinBox
var _y_spin: SpinBox
var _z_spin: SpinBox
var _sharp_check: CheckBox
var _bank_spin: SpinBox
var _bank_label: Label
var _mountain_box: VBoxContainer
var _left_spin: SpinBox
var _right_spin: SpinBox
var _rail_check: CheckBox
var _aqueduct_box: VBoxContainer
var _side_left_spin: SpinBox
var _side_right_spin: SpinBox
var _road_box: VBoxContainer
var _width_spin: SpinBox
var _type_option: OptionButton
var _surface_option: OptionButton
var _scenery_box: VBoxContainer
var _kind_option: OptionButton
var _scenery_selected_label: Label
var _scenery_delete: Button
var _errors_label: Label
var _warnings_label: Label


func _ready() -> void:
	GameState.end_test_drive()
	GameState.current_scene_path = GameState.SCENE_TRACK_MAKER
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_TRACKS_DIR))
	_build_ui()
	var restored := _restore_session()
	_set_doc(doc)
	_refresh_file_label()
	if not restored:
		_frame_when_laid_out.call_deferred()


func _frame_when_laid_out() -> void:
	_map.frame_all()


# --- Layout --------------------------------------------------------------------------------


func _build_ui() -> void:
	var back := ColorRect.new()
	back.color = Color(0.07, 0.07, 0.08, 1)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 0)
	add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 2)
	row.add_child(left)
	_map = _MapView.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.edit_begun.connect(_begin_edit.bind(""))
	_map.doc_edited.connect(_after_edit)
	_map.edit_ended.connect(_end_edit)
	_map.selection_changed.connect(_on_selection_changed)
	_map.ground_picked.connect(_on_ground_picked)
	left.add_child(_map)
	_profile = _ProfileView.new()
	_profile.custom_minimum_size = Vector2(0, 150)
	_profile.node_picked.connect(_on_profile_picked)
	_profile.edit_begun.connect(_begin_edit.bind(""))
	_profile.doc_edited.connect(_after_edit)
	_profile.edit_ended.connect(_end_edit)
	left.add_child(_profile)
	var help := Label.new()
	help.text = HELP
	help.add_theme_font_size_override(&"font_size", 13)
	help.add_theme_color_override(&"font_color", _DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(help)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(_PANEL_WIDTH, 0)
	row.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	margin.add_child(box)
	_build_file_section(box)
	box.add_child(HSeparator.new())
	_build_track_section(box)
	box.add_child(HSeparator.new())
	_build_tool_section(box)
	box.add_child(HSeparator.new())
	_build_node_section(box)
	_build_road_section(box)
	_build_scenery_section(box)
	_build_ground_section(box)
	box.add_child(HSeparator.new())
	_errors_label = _label("", 14, _ERROR)
	box.add_child(_errors_label)
	_warnings_label = _label("", 14, _WARNING)
	box.add_child(_warnings_label)
	var drive := _button("Test drive", _test_drive)
	drive.custom_minimum_size = Vector2(0, 44)
	box.add_child(drive)
	box.add_child(_button("Back to menu", _back_to_menu))

	_check_timer = Timer.new()
	_check_timer.one_shot = true
	_check_timer.wait_time = _CHECK_DELAY_S
	_check_timer.timeout.connect(_run_check)
	add_child(_check_timer)
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.trk ; Street Rod 3 tracks"])
	_dialog.use_native_dialog = false
	_dialog.file_selected.connect(_on_file_selected)
	add_child(_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Unsaved changes"
	_confirm.dialog_text = "This track has changes that aren't saved. Throw them away?"
	_confirm.ok_button_text = "Throw away"
	_confirm.confirmed.connect(_on_discard_confirmed)
	add_child(_confirm)


func _build_file_section(box: VBoxContainer) -> void:
	box.add_child(_label("Track maker", 24))
	_file_label = _label("", 13, _DIM)
	box.add_child(_file_label)
	var buttons := HFlowContainer.new()
	buttons.add_child(_button("New", _new_track))
	buttons.add_child(_button("Open...", _open_track.bind(USER_TRACKS_DIR)))
	if _can_edit_game_tracks():
		buttons.add_child(_button("Open game track...", _open_track.bind(GAME_TRACKS_DIR)))
	buttons.add_child(_button("Save", _save))
	buttons.add_child(_button("Save as...", _save_as))
	box.add_child(buttons)
	_status_label = _label("", 13, _DIM)
	box.add_child(_status_label)


func _build_track_section(box: VBoxContainer) -> void:
	box.add_child(_label("Track", 18))
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_changed)
	box.add_child(_row("Name", _name_edit))
	_style_option = _option(_STYLES)
	_style_option.item_selected.connect(_on_style_selected)
	box.add_child(_row("Style", _style_option))
	_jumps_check = CheckBox.new()
	_jumps_check.text = "Jumps (circuit only)"
	_jumps_check.toggled.connect(_on_jumps_toggled)
	box.add_child(_jumps_check)
	_auto_bank_check = CheckBox.new()
	_auto_bank_check.text = "Auto bank (each corner by how tight it is)"
	_auto_bank_check.toggled.connect(_on_auto_bank_toggled)
	box.add_child(_auto_bank_check)
	_loop_check = CheckBox.new()
	_loop_check.text = "Loop (the finish is the start)"
	_loop_check.toggled.connect(_on_loop_toggled)
	box.add_child(_loop_check)
	_laps_spin = SpinBox.new()
	_laps_spin.min_value = 1
	_laps_spin.max_value = _Doc.MAX_LAPS
	_laps_spin.step = 1
	_laps_spin.rounded = true
	_laps_spin.select_all_on_focus = true
	_laps_spin.value_changed.connect(_on_laps_changed)
	_laps_row = _row("Laps", _laps_spin)
	box.add_child(_laps_row)
	_sky_ids = _Skies.ids()
	_sky_option = OptionButton.new()
	for id: String in _sky_ids:
		var label := str(_Skies.SKIES[id]["name"])
		if not _Skies.has_file(id):
			label += " (file missing: day sky)"
		_sky_option.add_item(label)
	_sky_option.item_selected.connect(_on_sky_selected)
	box.add_child(_row("Sky", _sky_option))
	_length_label = _label("", 13, _DIM)
	box.add_child(_length_label)


func _build_tool_section(box: VBoxContainer) -> void:
	var group := ButtonGroup.new()
	var tools := HBoxContainer.new()
	_road_tool = _button("Road", _set_tool.bind(_MapView.Tool.ROAD))
	_road_tool.toggle_mode = true
	_road_tool.button_group = group
	_road_tool.button_pressed = true
	_road_tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_road_tool)
	_scenery_tool = _button("Scenery", _set_tool.bind(_MapView.Tool.SCENERY))
	_scenery_tool.toggle_mode = true
	_scenery_tool.button_group = group
	_scenery_tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_scenery_tool)
	_ground_tool = _button("Ground", _set_tool.bind(_MapView.Tool.GROUND))
	_ground_tool.toggle_mode = true
	_ground_tool.button_group = group
	_ground_tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_ground_tool)
	box.add_child(tools)
	var snaps := HBoxContainer.new()
	_snap_check = CheckBox.new()
	_snap_check.text = "Snap to %d m" % int(_MapView.SNAP_M)
	_snap_check.toggled.connect(_on_snap_toggled)
	snaps.add_child(_snap_check)
	snaps.add_child(_button("Whole track", _frame_when_laid_out))
	box.add_child(snaps)


func _build_node_section(box: VBoxContainer) -> void:
	_node_box = VBoxContainer.new()
	box.add_child(_node_box)
	_node_heading = _label("", 18)
	_node_box.add_child(_node_heading)
	_x_spin = _spin(-100000.0, 100000.0, 0.01, " m", _edit_node.bind("x"))
	_node_box.add_child(_row("X", _x_spin))
	_y_spin = _spin(-100000.0, 100000.0, 0.01, " m", _edit_node.bind("y"))
	_node_box.add_child(_row("Y", _y_spin))
	_z_spin = _spin(-500.0, 500.0, 0.1, " m", _edit_node.bind("z"))
	_node_box.add_child(_row("Height", _z_spin))
	_sharp_check = CheckBox.new()
	_sharp_check.text = "Sharp (the grade changes here at once)"
	_sharp_check.toggled.connect(_edit_node_flag.bind("sharp"))
	_node_box.add_child(_sharp_check)
	_bank_spin = _spin(-TrackFile.BANK_MAX_DEG, TrackFile.BANK_MAX_DEG, 1.0, "°", _edit_node.bind("bank"))
	_bank_spin.custom_arrow_step = 1.0
	_node_box.add_child(_row("Bank", _bank_spin))
	_bank_label = _label("", 13, _DIM)
	_node_box.add_child(_bank_label)
	_mountain_box = VBoxContainer.new()
	_node_box.add_child(_mountain_box)
	_left_spin = _spin(-100.0, 100.0, 0.1, " m", _edit_node.bind("left"))
	_mountain_box.add_child(_row("Left side", _left_spin))
	_right_spin = _spin(-100.0, 100.0, 0.1, " m", _edit_node.bind("right"))
	_mountain_box.add_child(_row("Right side", _right_spin))
	_rail_check = CheckBox.new()
	_rail_check.text = "Guard rail on the right to the next node"
	_rail_check.toggled.connect(_edit_node_flag.bind("rail"))
	_mountain_box.add_child(_rail_check)
	_aqueduct_box = VBoxContainer.new()
	_node_box.add_child(_aqueduct_box)
	var stock := snappedf(_TrackSides.AQUEDUCT_BANK_HIGH, 0.1)
	_side_left_spin = _spin(stock, _TrackSides.AQUEDUCT_SIDE_MAX, 0.1, " m", _edit_aqueduct_side.bind("left"))
	_aqueduct_box.add_child(_row("Left side", _side_left_spin))
	_side_right_spin = _spin(stock, _TrackSides.AQUEDUCT_SIDE_MAX, 0.1, " m", _edit_aqueduct_side.bind("right"))
	_aqueduct_box.add_child(_row("Right side", _side_right_spin))
	var side_note := _label("%.1f m is Street Rod 2's side. Higher, it curves up from the floor into a wider bowl that a car can ride round a corner." % stock, 13, _DIM)
	_aqueduct_box.add_child(side_note)
	_node_box.add_child(_button("Delete node", _delete_selected))


func _build_road_section(box: VBoxContainer) -> void:
	_road_box = VBoxContainer.new()
	box.add_child(_road_box)
	_road_box.add_child(_label("Road to the next node", 18))
	_width_spin = _spin(2.0, 60.0, 0.1, " m", _edit_road_width)
	_road_box.add_child(_row("Width", _width_spin))
	_type_option = _option(_ROAD_TYPES)
	_type_option.item_selected.connect(_edit_road_choice.bind("type", _ROAD_TYPES))
	_road_box.add_child(_row("Type", _type_option))
	_surface_option = _option(_SURFACES)
	_surface_option.item_selected.connect(_edit_road_choice.bind("surface", _SURFACES))
	_road_box.add_child(_row("Surface", _surface_option))


func _build_scenery_section(box: VBoxContainer) -> void:
	_scenery_box = VBoxContainer.new()
	box.add_child(_scenery_box)
	_scenery_box.add_child(_label("Scenery", 18))
	_kind_option = _option(TrackFile.SCENERY_KINDS)
	_kind_option.item_selected.connect(_on_kind_selected)
	_scenery_box.add_child(_row("Kind", _kind_option))
	_scenery_selected_label = _label("Click the map to place one.", 13, _DIM)
	_scenery_box.add_child(_scenery_selected_label)
	_scenery_delete = _button("Delete scenery", _delete_selected)
	_scenery_box.add_child(_scenery_delete)


func _build_ground_section(box: VBoxContainer) -> void:
	_ground_box = VBoxContainer.new()
	box.add_child(_ground_box)
	_ground_box.add_child(_label("Ground", 18))
	_brush_option = _option(["Raise", "Lower", "Smooth", "Flatten", "Erase"])
	_brush_option.item_selected.connect(_on_brush_selected)
	_ground_box.add_child(_row("Brush", _brush_option))
	_brush_size_spin = _spin(_TrackTerrain.CELL_M, 500.0, 1.0, " m", _on_brush_size_changed)
	_brush_size_spin.set_value_no_signal(_map.brush_radius)
	_ground_box.add_child(_row("Size", _brush_size_spin))
	_brush_strength_spin = _spin(1.0, 100.0, 1.0, " %", _on_brush_strength_changed)
	_brush_strength_spin.set_value_no_signal(_map.brush_strength * 100.0)
	_ground_box.add_child(_row("Strength", _brush_strength_spin))
	_flatten_spin = _spin(-_TrackTerrain.HEIGHT_LIMIT, _TrackTerrain.HEIGHT_LIMIT, 0.1, " m", _on_flatten_changed)
	_flatten_row = _row("Height", _flatten_spin)
	_ground_box.add_child(_flatten_row)
	_ground_label = _label("", 13, _DIM)
	_ground_box.add_child(_ground_label)
	_ground_box.add_child(_button("Road follows ground", _road_follows_ground))
	_ground_box.add_child(_label("Sets each node on painted ground to the ground's height there.", 13, _DIM))


func _label(text: String, font_size: int, color: Color = _CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(_PANEL_WIDTH - 40.0, 0)
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(_LABEL_WIDTH, 0)
	label.add_theme_color_override(&"font_color", _CREAM)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _spin(low: float, high: float, step: float, suffix: String, action: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.suffix = suffix
	spin.custom_arrow_step = step * 10.0
	spin.select_all_on_focus = true
	spin.value_changed.connect(action)
	return spin


func _option(items: Array) -> OptionButton:
	var option := OptionButton.new()
	for item: Variant in items:
		option.add_item(str(item))
	return option


# --- The course ----------------------------------------------------------------------------


func _set_doc(next: _Doc) -> void:
	doc = next
	_map.doc = doc
	_profile.doc = doc
	if _map.selected_node >= doc.nodes.size():
		_map.selected_node = doc.nodes.size() - 1
	if _map.selected_scenery >= doc.scenery.size():
		_map.selected_scenery = -1
	_profile.selected_node = _map.selected_node
	_refresh_track_fields()
	_refresh_selection_fields()
	_map.queue_redraw()
	_profile.queue_redraw()
	_run_check()


## Keeps an undo step before a change. Changes to the same field in quick succession, such
## as typing a number, share one step.
func _begin_edit(tag: String = "") -> void:
	var now := Time.get_ticks_msec()
	if not tag.is_empty() and tag == _last_tag and now - _last_tag_ms < _UNDO_MERGE_MS:
		_last_tag_ms = now
		return
	_undo.append(doc.copy())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()
	_last_tag = tag
	_last_tag_ms = now


func _after_edit() -> void:
	_dirty = true
	_refresh_file_label()
	_refresh_selection_fields()
	_map.queue_redraw()
	_profile.queue_redraw()
	_check_timer.start()


func _end_edit() -> void:
	_last_tag = ""
	_refresh_ground_fields()


func _undo_step() -> void:
	if _undo.is_empty():
		return
	_redo.append(doc.copy())
	_set_doc(_undo.pop_back())
	_last_tag = ""
	_dirty = true
	_refresh_file_label()


func _redo_step() -> void:
	if _redo.is_empty():
		return
	_undo.append(doc.copy())
	_set_doc(_redo.pop_back())
	_last_tag = ""
	_dirty = true
	_refresh_file_label()


func _run_check() -> void:
	var result := doc.check()
	var errors: Array[String] = []
	errors.assign(result.errors)
	var warnings: Array[String] = []
	warnings.assign(result.warnings)
	_errors_label.text = "\n".join(errors)
	_errors_label.visible = not errors.is_empty()
	_warnings_label.text = "\n".join(warnings)
	_warnings_label.visible = not warnings.is_empty()
	var what := "a lap" if doc.loop else "long"
	_length_label.text = "%d nodes, about %s %s (the game rounds the corners)." % [doc.nodes.size(), _meters(doc.path_length()), what]


static func _meters(value: float) -> String:
	if value >= 1000.0:
		return "%.2f km" % (value / 1000.0)
	return "%d m" % roundi(value)


# --- Panel fields --------------------------------------------------------------------------


func _refresh_track_fields() -> void:
	if _name_edit.text != doc.name:
		_name_edit.text = doc.name
	_style_option.select(maxi(_STYLES.find(doc.style), 0))
	_jumps_check.set_pressed_no_signal(doc.jumps)
	_jumps_check.disabled = doc.style != TrackFile.STYLE_CIRCUIT and not doc.jumps
	_auto_bank_check.set_pressed_no_signal(doc.auto_bank)
	_loop_check.set_pressed_no_signal(doc.loop)
	_laps_spin.set_value_no_signal(doc.laps)
	_laps_row.visible = doc.loop
	_sky_option.select(maxi(_sky_ids.find(doc.sky), 0))


func _refresh_selection_fields() -> void:
	var i := _map.selected_node
	var on_node := i >= 0 and i < doc.nodes.size()
	_node_box.visible = on_node
	_road_box.visible = on_node and i < doc.road_count()
	_scenery_box.visible = _map.tool == _MapView.Tool.SCENERY or _map.selected_scenery >= 0
	_ground_box.visible = _map.tool == _MapView.Tool.GROUND
	_refresh_ground_fields()
	if on_node:
		var where := ""
		if i == 0:
			where = " (start and finish)" if doc.loop else " (start)"
		elif i == doc.nodes.size() - 1 and not doc.loop:
			where = " (finish)"
		_node_heading.text = "Node %d of %d%s" % [i + 1, doc.nodes.size(), where]
		var point := doc.node_point(i)
		_x_spin.set_value_no_signal(point.x)
		_y_spin.set_value_no_signal(point.y)
		# The race puts the cars at 0, 0 heading +Y, so the start can't move and node 2 only slides ahead.
		_x_spin.editable = i > 1
		_y_spin.editable = i > 0
		_z_spin.set_value_no_signal(doc.node_height(i))
		_sharp_check.set_pressed_no_signal(bool(doc.nodes[i].get("sharp", false)))
		_bank_spin.set_value_no_signal(doc.bank_at(i))
		# Auto bank sets it from the corner.
		_bank_spin.editable = not doc.auto_bank
		_bank_label.text = doc.bank_note(i)
		_mountain_box.visible = doc.style == TrackFile.STYLE_MOUNTAIN
		_left_spin.set_value_no_signal(float(doc.nodes[i].get("left", 0.0)))
		_right_spin.set_value_no_signal(float(doc.nodes[i].get("right", 0.0)))
		_rail_check.set_pressed_no_signal(bool(doc.nodes[i].get("rail", false)))
		_aqueduct_box.visible = doc.style == TrackFile.STYLE_AQUEDUCT
		_side_left_spin.set_value_no_signal(doc.aqueduct_side_at(i, "left"))
		_side_right_spin.set_value_no_signal(doc.aqueduct_side_at(i, "right"))
	if on_node and i < doc.road_count():
		var road := doc.road_from(i)
		_width_spin.set_value_no_signal(float(road.get("width", TrackFile.DEFAULT_WIDTH)))
		_type_option.select(maxi(_ROAD_TYPES.find(TrackFile.normalize_road_type(str(road.get("type", TrackFile.ROAD_REGULAR)))), 0))
		_surface_option.select(maxi(_SURFACES.find(str(road.get("surface", TrackFile.SURFACE_REGULAR))), 0))
	var sight := _map.selected_scenery
	if sight >= 0 and sight < doc.scenery.size():
		var kind := str(doc.scenery[sight].get("kind", ""))
		_kind_option.select(maxi(TrackFile.SCENERY_KINDS.find(kind), 0))
		_scenery_selected_label.text = "Selected: %s at %.1f, %.1f" % [kind, float(doc.scenery[sight].get("x", 0.0)), float(doc.scenery[sight].get("y", 0.0))]
		_scenery_delete.visible = true
	else:
		_scenery_selected_label.text = "Click the map to place a %s." % _map.scenery_kind
		_scenery_delete.visible = false


func _on_selection_changed() -> void:
	_profile.selected_node = _map.selected_node
	_profile.queue_redraw()
	_refresh_selection_fields()


func _on_profile_picked(index: int) -> void:
	_map.select(index, -1)


func _set_tool(which: _MapView.Tool) -> void:
	_map.tool = which
	if which != _MapView.Tool.SCENERY:
		_map.selected_scenery = -1
	if which != _MapView.Tool.ROAD:
		_map.selected_node = -1
	_on_selection_changed()
	_map.queue_redraw()


func _refresh_ground_fields() -> void:
	var brush := _map.brush
	_brush_option.select(int(brush))
	_flatten_row.visible = brush == _TrackTerrain.Brush.FLATTEN
	var help := {
		_TrackTerrain.Brush.RAISE: "Hold the left button to raise the ground under the brush, most in its middle.",
		_TrackTerrain.Brush.LOWER: "Hold the left button to lower the ground under the brush.",
		_TrackTerrain.Brush.SMOOTH: "Hold the left button to even out painted ground.",
		_TrackTerrain.Brush.FLATTEN: "Hold the left button to bring the ground to Height. Ctrl+click picks the height there.",
		_TrackTerrain.Brush.ERASE: "Hold the left button to clear the paint, back to the style's own ground.",
	}
	var text := str(help[brush])
	if _map.is_painting():
		return
	var painted := doc.terrain.area()
	if doc.terrain.is_empty():
		text += " Nothing is painted yet."
	else:
		var heights := doc.terrain.height_range()
		text += " Painted from %.1f to %.1f m, over %s by %s." % [heights.x, heights.y, _meters(painted.size.x), _meters(painted.size.y)]
	_ground_label.text = text


func _on_brush_selected(index: int) -> void:
	_map.brush = index as _TrackTerrain.Brush
	_refresh_ground_fields()


func _on_brush_size_changed(value: float) -> void:
	_map.brush_radius = value
	_map.queue_redraw()


func _on_brush_strength_changed(value: float) -> void:
	_map.brush_strength = value / 100.0


func _on_flatten_changed(value: float) -> void:
	_map.flatten_height = value


func _on_ground_picked(height: float) -> void:
	_map.flatten_height = snappedf(height, 0.1)
	_flatten_spin.set_value_no_signal(_map.flatten_height)
	if _map.brush != _TrackTerrain.Brush.FLATTEN:
		_map.brush = _TrackTerrain.Brush.FLATTEN
		_refresh_ground_fields()
	_set_status("Flatten height %.1f m" % _map.flatten_height)


func _road_follows_ground() -> void:
	_begin_edit()
	var changed := doc.road_follows_ground()
	if changed == 0:
		_undo.pop_back()
		_set_status("No node is on painted ground at another height.")
		return
	_after_edit()
	_set_status("%d nodes moved to the ground's height." % changed)


func _on_snap_toggled(on: bool) -> void:
	_map.snap = on


func _on_name_changed(text: String) -> void:
	_begin_edit("name")
	doc.name = text
	_after_edit()


func _on_style_selected(index: int) -> void:
	_begin_edit()
	doc.style = str(_STYLES[index])
	if doc.style != TrackFile.STYLE_CIRCUIT and doc.jumps:
		doc.jumps = false
	_refresh_track_fields()
	_after_edit()


func _on_jumps_toggled(on: bool) -> void:
	_begin_edit()
	doc.jumps = on
	_after_edit()


func _on_auto_bank_toggled(on: bool) -> void:
	_begin_edit()
	doc.auto_bank = on
	_after_edit()


func _on_loop_toggled(on: bool) -> void:
	_begin_edit()
	doc.set_loop(on)
	_refresh_track_fields()
	_after_edit()


func _on_sky_selected(index: int) -> void:
	_begin_edit()
	doc.sky = _sky_ids[index]
	_after_edit()


func _on_laps_changed(value: float) -> void:
	_begin_edit("laps")
	doc.laps = clampi(roundi(value), 1, _Doc.MAX_LAPS)
	_after_edit()


func _edit_node(value: float, key: String) -> void:
	var i := _map.selected_node
	if i < 0 or i >= doc.nodes.size():
		return
	_begin_edit("node:%d:%s" % [i, key])
	match key:
		"x":
			doc.move_node(i, Vector2(value, doc.node_point(i).y))
		"y":
			doc.move_node(i, Vector2(doc.node_point(i).x, value))
		_:
			doc.set_node_field(i, key, _Doc.cm(value))
	_after_edit()


## An Aqueduct side's height. Street Rod 2's, or near it, is left out of the file.
func _edit_aqueduct_side(value: float, key: String) -> void:
	var i := _map.selected_node
	if i < 0 or i >= doc.nodes.size():
		return
	_begin_edit("node:%d:%s" % [i, key])
	doc.set_node_field(i, key, 0.0 if value < _TrackSides.AQUEDUCT_BANK_HIGH + 0.05 else _Doc.cm(value))
	_after_edit()


func _edit_node_flag(on: bool, key: String) -> void:
	var i := _map.selected_node
	if i < 0 or i >= doc.nodes.size():
		return
	_begin_edit()
	doc.set_node_field(i, key, on)
	_after_edit()


func _edit_road_width(value: float) -> void:
	var i := _map.selected_node
	if i < 0 or i >= doc.road_count():
		return
	_begin_edit("road:%d:width" % i)
	doc.set_road_field(i, "width", _Doc.cm(value))
	_after_edit()


func _edit_road_choice(index: int, key: String, choices: Array) -> void:
	var i := _map.selected_node
	if i < 0 or i >= doc.road_count():
		return
	_begin_edit()
	doc.set_road_field(i, key, str(choices[index]))
	_after_edit()


func _on_kind_selected(index: int) -> void:
	var kind := str(TrackFile.SCENERY_KINDS[index])
	_map.scenery_kind = kind
	var sight := _map.selected_scenery
	if sight >= 0 and sight < doc.scenery.size():
		_begin_edit()
		doc.scenery[sight]["kind"] = kind
		_after_edit()
	else:
		_refresh_selection_fields()


func _delete_selected() -> void:
	var sight := _map.selected_scenery
	if sight >= 0 and sight < doc.scenery.size():
		_begin_edit()
		doc.scenery.remove_at(sight)
		_map.selected_scenery = -1
		_after_edit()
		_on_selection_changed()
		return
	var i := _map.selected_node
	if i < 0:
		return
	if i == 0:
		_set_status("The start can't be deleted.", true)
		return
	if doc.nodes.size() <= 2:
		_set_status("A track needs at least two nodes.", true)
		return
	_begin_edit()
	doc.remove_node(i)
	_map.selected_node = mini(i, doc.nodes.size() - 1)
	_after_edit()
	_on_selection_changed()


# --- Files ---------------------------------------------------------------------------------


## True when running from the project, where the game's own tracks can be saved.
func _can_edit_game_tracks() -> bool:
	return not OS.has_feature("template") and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(GAME_TRACKS_DIR))


func _refresh_file_label() -> void:
	var where := "Not saved yet" if _path.is_empty() else _path
	_file_label.text = where + (" (changed)" if _dirty else "")


func _set_status(text: String, is_error: bool = false) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override(&"font_color", _ERROR if is_error else _DIM)


func _confirm_discard(then: Callable) -> void:
	if not _dirty:
		then.call()
		return
	_pending = then
	_confirm.popup_centered()


func _on_discard_confirmed() -> void:
	var then := _pending
	_pending = Callable()
	if then.is_valid():
		then.call()


func _new_track() -> void:
	_confirm_discard(_start_new_track)


func _start_new_track() -> void:
	_undo.clear()
	_redo.clear()
	_path = ""
	_dirty = false
	_map.selected_node = -1
	_map.selected_scenery = -1
	_set_doc(_Doc.blank())
	_refresh_file_label()
	_set_status("")
	_map.frame_all()


func _open_track(folder: String) -> void:
	_confirm_discard(_show_file_dialog.bind(FileDialog.FILE_MODE_OPEN_FILE, folder))


func _save() -> void:
	if _path.is_empty():
		_save_as()
	else:
		_write(_path)


func _save_as() -> void:
	var folder := USER_TRACKS_DIR if _path.is_empty() else _path.get_base_dir()
	_show_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, folder)


func _show_file_dialog(mode: FileDialog.FileMode, folder: String) -> void:
	_dialog.file_mode = mode
	_dialog.title = "Open a track" if mode == FileDialog.FILE_MODE_OPEN_FILE else "Save the track"
	_dialog.current_dir = ProjectSettings.globalize_path(folder) if folder.contains("://") else folder
	if mode == FileDialog.FILE_MODE_SAVE_FILE:
		_dialog.current_file = _path.get_file() if not _path.is_empty() else _file_name_for(doc.name)
	_dialog.popup_centered_ratio(0.7)


static func _file_name_for(track_name: String) -> String:
	var base := track_name.strip_edges().to_lower().replace(" ", "_").validate_filename()
	return (base if not base.is_empty() else "track") + ".trk"


func _on_file_selected(path: String) -> void:
	if _dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		_read(path)
	else:
		_write(path)


func _read(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_set_status("Could not read %s." % path, true)
		return
	var result := _Doc.from_text(text, path)
	var errors: Array[String] = []
	errors.assign(result.errors)
	if result.doc == null:
		_set_status("Could not open %s:\n%s" % [path.get_file(), "\n".join(errors)], true)
		return
	var warnings: Array[String] = []
	warnings.assign(result.warnings)
	_undo.clear()
	_redo.clear()
	_path = path
	_dirty = false
	_map.selected_node = -1
	_map.selected_scenery = -1
	_set_doc(result.doc as _Doc)
	_refresh_file_label()
	_set_status("Opened %s.%s" % [path.get_file(), ("\n" + "\n".join(warnings)) if not warnings.is_empty() else ""], not warnings.is_empty())
	_map.frame_all()


func _write(path: String) -> void:
	if path.get_extension().to_lower() != "trk":
		path += ".trk"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Could not write %s: %s" % [path, error_string(FileAccess.get_open_error())], true)
		return
	file.store_string(doc.to_text())
	file.close()
	_path = path
	_dirty = false
	_refresh_file_label()
	var errors: Array[String] = []
	errors.assign(doc.check().errors)
	if errors.is_empty():
		_set_status("Saved %s." % path.get_file())
	else:
		_set_status("Saved %s, but the game can't race it until the problems below are fixed." % path.get_file(), true)


# --- Test drive and leaving ----------------------------------------------------------------


func _test_drive() -> void:
	var errors: Array[String] = []
	errors.assign(doc.check().errors)
	if not errors.is_empty():
		_set_status("Fix the problems below before a test drive.", true)
		return
	var file := FileAccess.open(GameState.TEST_DRIVE_TRACK, FileAccess.WRITE)
	if file == null:
		_set_status("Could not write the test drive course: %s" % error_string(FileAccess.get_open_error()), true)
		return
	file.store_string(doc.to_text())
	file.close()
	GameState.track_maker_session = {
		"doc": doc,
		"path": _path,
		"dirty": _dirty,
		"undo": _undo,
		"redo": _redo,
		"center": _map.view_center,
		"scale": _map.view_scale,
		"tool": _map.tool,
		"snap": _map.snap,
		"kind": _map.scenery_kind,
		"node": _map.selected_node,
	}
	GameState.begin_test_drive(GameState.TEST_DRIVE_TRACK)
	GameState.current_scene_path = GameState.SCENE_RACE
	get_tree().change_scene_to_file(GameState.SCENE_RACE)


## Picks up where the maker was before a test drive. False when there was nothing to pick up.
func _restore_session() -> bool:
	var session := GameState.track_maker_session
	GameState.track_maker_session = {}
	var saved: Variant = session.get("doc", null)
	if not saved is _Doc:
		return false
	doc = saved as _Doc
	_path = str(session.get("path", ""))
	_dirty = bool(session.get("dirty", false))
	var undo: Variant = session.get("undo", [])
	if undo is Array:
		_undo.assign(undo as Array)
	var redo: Variant = session.get("redo", [])
	if redo is Array:
		_redo.assign(redo as Array)
	_map.view_center = session.get("center", _map.view_center) as Vector2
	_map.view_scale = float(session.get("scale", _map.view_scale))
	_map.snap = bool(session.get("snap", false))
	_snap_check.set_pressed_no_signal(_map.snap)
	_map.scenery_kind = str(session.get("kind", _map.scenery_kind))
	_kind_option.select(maxi(TrackFile.SCENERY_KINDS.find(_map.scenery_kind), 0))
	_map.selected_node = int(session.get("node", -1))
	if int(session.get("tool", 0)) == _MapView.Tool.SCENERY:
		_map.tool = _MapView.Tool.SCENERY
		_scenery_tool.button_pressed = true
	return true


func _back_to_menu() -> void:
	_confirm_discard(_leave)


func _leave() -> void:
	GameState.track_maker_session = {}
	GameState.current_scene_path = GameState.SCENE_MAIN_MENU
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)


# --- Keys ----------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	var action := _key_action(key)
	if not action.is_valid():
		return
	# Before the action: a test drive or the menu takes this screen out of the tree.
	get_viewport().set_input_as_handled()
	action.call()


func _key_action(key: InputEventKey) -> Callable:
	var ctrl := key.is_command_or_control_pressed()
	match key.keycode:
		KEY_Z when ctrl:
			return _redo_step if key.shift_pressed else _undo_step
		KEY_Y when ctrl:
			return _redo_step
		KEY_S when ctrl and not key.echo:
			return _save_as if key.shift_pressed else _save
		KEY_DELETE, KEY_BACKSPACE:
			return _delete_selected
		KEY_F when not ctrl and not key.echo:
			return _map.frame_all
		KEY_F5 when not key.echo:
			return _test_drive
		KEY_ESCAPE when not key.echo:
			var focus := get_viewport().gui_get_focus_owner()
			if focus is LineEdit:
				return focus.release_focus
			return _back_to_menu
	return Callable()
