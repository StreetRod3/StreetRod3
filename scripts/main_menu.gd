extends Control

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _SaveSlots := preload("res://scripts/save_slots.gd")
const _Console := preload("res://scripts/console.gd")
const _SaveEditor := preload("res://scripts/save_editor.gd")

var _nav := _MenuNav.new()
## The ~ prompt and the save editor, while they are up.
var _console: Control
var _save_editor: Control


func _ready() -> void:
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_nav.setup(_menu_buttons())


func _menu_buttons() -> Array:
	return [
		$Margin/Row/Menu/NewGameButton,
		$Margin/Row/Menu/LoadGameButton,
		$Margin/Row/Menu/SettingsButton,
		$Margin/Row/Menu/ExitButton,
	]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and _console == null and _save_editor == null:
		var key := event as InputEventKey
		if key.pressed and not key.echo and _Console.is_toggle_key(key):
			accept_event()
			_open_console()
			return
	if _nav.handle_event(self, event):
		accept_event()


func _open_console() -> void:
	_nav.clear()
	var console: Control = _Console.new()
	console.call("add_command", "saveedit", "edit a saved game: cars, spare parts and money", _open_save_editor)
	console.closed.connect(_on_console_closed, CONNECT_DEFERRED)
	_console = console
	add_child(console)


func _on_console_closed() -> void:
	if _console != null:
		_console.queue_free()
		_console = null
	if _save_editor == null:
		_nav.setup(_menu_buttons())


## The console's `saveedit`. "" closes the prompt; a line stays on it.
func _open_save_editor() -> String:
	if not GameState.has_save_file():
		return "No saved games to edit."
	var editor: Control = _SaveEditor.new()
	editor.closed.connect(_on_save_editor_closed, CONNECT_DEFERRED)
	_save_editor = editor
	add_child(editor)
	return ""


func _on_save_editor_closed() -> void:
	if _save_editor != null:
		_save_editor.queue_free()
		_save_editor = null
	_set_status("")
	_nav.setup(_menu_buttons())


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_DRIVER_LICENSE)


func _on_load_game_pressed() -> void:
	if not GameState.has_save_file():
		_set_status("No saved games yet.")
		return
	_nav.clear()
	var slots: Control = _SaveSlots.new()
	slots.chosen.connect(_on_save_slot_chosen.bind(slots))
	slots.closed.connect(_on_save_slots_closed.bind(slots))
	add_child(slots)


func _on_save_slot_chosen(slot: int, slots: Control) -> void:
	slots.queue_free()
	if GameState.load_game(slot):
		GameState.go_to_saved_scene(get_tree())
	else:
		_set_status("Could not load that save.")
		_on_save_slots_closed(null)


func _on_save_slots_closed(slots: Control) -> void:
	if slots != null:
		slots.queue_free()
	_nav.setup(_menu_buttons())
	_nav.select(1)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_SETTINGS)


func _on_exit_pressed() -> void:
	get_tree().quit()


func _set_status(text: String) -> void:
	var label := get_node_or_null("Margin/Row/Menu/StatusLabel") as Label
	if label:
		label.text = text
