extends Control

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _SaveSlots := preload("res://scripts/save_slots.gd")

var _nav = _MenuNav.new()


func _ready() -> void:
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_nav.setup([
		$Margin/Row/Menu/NewGameButton,
		$Margin/Row/Menu/LoadGameButton,
		$Margin/Row/Menu/SettingsButton,
		$Margin/Row/Menu/ExitButton,
	])


func _unhandled_input(event: InputEvent) -> void:
	if _nav.handle_event(self, event):
		accept_event()


func _on_new_game_pressed() -> void:
	GameState.new_game()
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


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
	_nav.setup([
		$Margin/Row/Menu/NewGameButton,
		$Margin/Row/Menu/LoadGameButton,
		$Margin/Row/Menu/SettingsButton,
		$Margin/Row/Menu/ExitButton,
	])
	_nav.select(1)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_SETTINGS)


func _on_exit_pressed() -> void:
	get_tree().quit()


func _set_status(text: String) -> void:
	var label := get_node_or_null("Margin/Row/Menu/StatusLabel") as Label
	if label:
		label.text = text
