extends Control

## The save editor, opened with `saveedit` at the main menu's ~ prompt. It does what the
## Street Rod and Street Rod 2 save editors do: pick a save, then add a car to its
## garage, add a spare part, or set the bank balance. Each change is written to the save
## straight away; when a write fails the save is read back and nothing changes. Emits
## `closed` when backed out of; the opener frees it.

signal closed

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _SaveSlots := preload("res://scripts/save_slots.gd")

const _CREAM := Color(0.95, 0.9, 0.78, 1)
const _DIM := Color(0.75, 0.7, 0.6, 1)
const _ROW_SIZE := Vector2(640, 36)
## The most the balance can be set to. JSON numbers stay exact well past this.
const MONEY_MAX := 999999999
const _SPARE_KINDS: Array[Array] = [
	["engine", "Engines"],
	["transmission", "Transmissions"],
	["wheels", "Wheels"],
	["part", "Parts"],
]

enum Page { SLOTS, MENU, CARS, SPARES, MONEY, ERROR }

var _page: Page = Page.SLOTS
var _slot: int = 0
var _slots: Control
var _panel: PanelContainer
var _box: VBoxContainer
var _hint: Label
var _status: Label
var _money_edit: LineEdit
## On the spares page, each part's button with its [kind, id].
var _spare_rows: Dictionary = {}
var _nav := _MenuNav.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(&"panel", _panel_style())
	center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 8)
	_panel.add_child(_box)
	_open_slots()


## Esc goes back a page, or out from the menu. It is caught here, before a focused line
## edit can take it. The slot list handles its own keys.
func _input(event: InputEvent) -> void:
	if _slots != null or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _page == Page.MENU:
			_close()
		elif _page == Page.ERROR:
			_open_slots()
		else:
			_show_menu("")


func _unhandled_input(event: InputEvent) -> void:
	if _slots != null or not event is InputEventKey:
		return
	_nav.handle_event(self, event)
	# Nothing behind the editor gets keys while it is up.
	get_viewport().set_input_as_handled()


# --- Pages --------------------------------------------------------------------


func _open_slots() -> void:
	_page = Page.SLOTS
	_nav.clear()
	_panel.visible = false
	var slots: Control = _SaveSlots.new()
	slots.set("heading", "Save editor")
	slots.set("hint", "Pick a save to edit.")
	slots.chosen.connect(_on_slot_chosen, CONNECT_DEFERRED)
	slots.closed.connect(_close, CONNECT_DEFERRED)
	_slots = slots
	add_child(slots)


func _on_slot_chosen(slot: int) -> void:
	_slots.queue_free()
	_slots = null
	_panel.visible = true
	if not GameState.load_game(slot):
		_page = Page.ERROR
		_clear_page()
		_box.add_child(_label("Save editor", 24))
		_box.add_child(_label("Could not read the save in slot %d." % slot, 16))
		_finish_page([_button("Back", _open_slots)], 0)
		return
	_slot = slot
	_show_menu("")


func _show_menu(status: String) -> void:
	_page = Page.MENU
	_clear_page()
	_box.add_child(_label("Save editor  ·  slot %d" % _slot, 24))
	_box.add_child(_label(_summary(), 16, _DIM))
	var rows: Array[Control] = [
		_button("Add a car to the garage   (%d of %d cars)" % [GameState.owned_car_ids.size(), GameState.MAX_OWNED_CARS], _show_cars),
		_button("Add a spare part", _show_spares),
		_button("Set the bank balance   ($%d)" % GameState.money, _show_money),
		_button("Edit another save", _open_slots),
		_button("Done", _close),
	]
	_status = _label(status, 16)
	_box.add_child(_status)
	_finish_page(rows, 0)


func _show_cars() -> void:
	_page = Page.CARS
	_clear_page()
	_box.add_child(_label("Add a car to the garage", 24))
	_hint = _label("", 16, _DIM)
	_box.add_child(_hint)
	var list := _scroll_list()
	var rows: Array[Control] = []
	for car: Dictionary in GameState.USED_CARS:
		var model_id := str(car.get("id", ""))
		var row := _button("%s   (paper price $%d)" % [str(car.get("name", model_id)), int(car.get("price", 0))], _on_car_pressed.bind(model_id), list)
		rows.append(row)
	_status = _label("", 16)
	_box.add_child(_status)
	rows.append(_button("Back", _show_menu.bind("")))
	_refresh_car_hint()
	_finish_page(rows, 0)


func _on_car_pressed(model_id: String) -> void:
	var had_car := GameState.has_active_car()
	var trouble := GameState.editor_add_car(model_id)
	if not trouble.is_empty():
		_status.text = trouble
		return
	var listed := GameState.listing_by_id(GameState.USED_CARS, model_id)
	var car_label := str(listed.get("name", model_id))
	_commit(("Parked in your garage: %s." if had_car else "Yours to drive: %s.") % car_label)
	_refresh_car_hint()


func _refresh_car_hint() -> void:
	_hint.text = "%d of %d cars. A car comes stock, in its paper paint." % [GameState.owned_car_ids.size(), GameState.MAX_OWNED_CARS]


func _show_spares() -> void:
	_page = Page.SPARES
	_clear_page()
	_box.add_child(_label("Add a spare part", 24))
	_box.add_child(_label("Each one goes into spare parts, new.", 16, _DIM))
	var list := _scroll_list()
	var rows: Array[Control] = []
	_spare_rows.clear()
	for kind_row: Array in _SPARE_KINDS:
		var kind := str(kind_row[0])
		list.add_child(_label(str(kind_row[1]), 18))
		for item: Dictionary in _spare_listing(kind):
			var id := str(item.get("id", ""))
			var row := _button("", _on_spare_pressed.bind(kind, id), list)
			_spare_rows[row] = [kind, id]
			rows.append(row)
	_status = _label("", 16)
	_box.add_child(_status)
	rows.append(_button("Back", _show_menu.bind("")))
	_refresh_spare_rows()
	_finish_page(rows, 0)


func _spare_listing(kind: String) -> Array[Dictionary]:
	match kind:
		"engine":
			return GameState.ENGINES
		"transmission":
			return GameState.GEARBOXES
		"wheels":
			return GameState.WHEELS
	return GameState.PARTS


func _on_spare_pressed(kind: String, id: String) -> void:
	var trouble := GameState.editor_add_spare(kind, id)
	if not trouble.is_empty():
		_status.text = trouble
		return
	_commit("Added to your spare parts: %s." % _part_name(kind, id))
	_refresh_spare_rows()


func _refresh_spare_rows() -> void:
	for row: Button in _spare_rows.keys():
		var entry: Array = _spare_rows[row]
		var kind := str(entry[0])
		var id := str(entry[1])
		row.text = "   %s   (%d spare)" % [_part_name(kind, id), GameState.free_spare_count(kind, id)]


func _part_name(kind: String, id: String) -> String:
	return str(GameState.listing_for(kind, id).get("name", id))


func _show_money() -> void:
	_page = Page.MONEY
	_clear_page()
	_box.add_child(_label("Set the bank balance", 24))
	_hint = _label("", 16, _DIM)
	_box.add_child(_hint)
	_money_edit = LineEdit.new()
	_money_edit.placeholder_text = "New amount, e.g. 5000, +500, -200"
	_money_edit.custom_minimum_size = _ROW_SIZE
	_money_edit.keep_editing_on_text_submit = true
	_money_edit.text_submitted.connect(_on_money_submitted.unbind(1))
	_box.add_child(_money_edit)
	var rows: Array[Control] = [_money_edit, _button("Set", _on_money_submitted)]
	_status = _label("", 16)
	_box.add_child(_status)
	rows.append(_button("Back", _show_menu.bind("")))
	_refresh_money_hint()
	_finish_page(rows, 0)


func _on_money_submitted() -> void:
	var before := GameState.money
	var after := parse_money(_money_edit.text, before)
	if after < 0:
		_status.text = "Type a whole number of dollars, or + or - and one."
		return
	_money_edit.clear()
	GameState.money = after
	_commit("Balance set: $%d -> $%d." % [before, after])
	_refresh_money_hint()


## The balance `text` asks for, starting from `current`: "5000" sets it, "+500" and
## "-200" add and take away. Kept between 0 and MONEY_MAX. -1 when `text` is not a
## number like that.
static func parse_money(text: String, current: int) -> int:
	var t := text.strip_edges().replace(",", "").replace("$", "")
	var direction := 0
	if t.begins_with("+"):
		direction = 1
		t = t.substr(1)
	elif t.begins_with("-"):
		direction = -1
		t = t.substr(1)
	if t.is_empty() or not t.is_valid_int() or t.begins_with("+") or t.begins_with("-"):
		return -1
	if t.length() > 12:
		return MONEY_MAX if direction >= 0 else 0
	var amount := t.to_int()
	var result := amount if direction == 0 else current + direction * amount
	return clampi(result, 0, MONEY_MAX)


func _refresh_money_hint() -> void:
	_hint.text = "Current balance: $%d" % GameState.money


# --- Saving -------------------------------------------------------------------


## Writes the change to the save, or reads the save back when that fails.
func _commit(done: String) -> void:
	if GameState.save_game(_slot):
		_status.text = done
		return
	GameState.load_game(_slot)
	_status.text = "Could not write the save, so nothing was changed."


func _close() -> void:
	_nav.clear()
	# The edited game is not the one being played.
	GameState.save_slot = 0
	closed.emit()


func _summary() -> String:
	var driver := GameState.driver_name if not GameState.driver_name.is_empty() else "No name"
	return "%s  ·  %s  ·  $%d" % [driver, GameState.car_name, GameState.money]


# --- Building -----------------------------------------------------------------


func _clear_page() -> void:
	_nav.clear()
	_spare_rows.clear()
	_hint = null
	_money_edit = null
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()


func _finish_page(rows: Array[Control], first: int) -> void:
	var items: Array = []
	for row in rows:
		items.append(row)
	_nav.setup(items)
	_nav.select(first)


## A button that runs `run` after its own press has finished, since most buttons here
## rebuild the page they are on.
func _button(text: String, run: Callable, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = _ROW_SIZE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(run, CONNECT_DEFERRED)
	(parent if parent != null else _box).add_child(button)
	return button


func _scroll_list() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(_ROW_SIZE.x + 24.0, 400.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 6)
	scroll.add_child(list)
	return list


func _label(text: String, font_size: int, color: Color = _CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.96)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style
