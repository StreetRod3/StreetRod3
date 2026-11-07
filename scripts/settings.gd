extends Control

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _ControlsSetup := preload("res://scripts/controls_setup.gd")
const _GraphicsSetup := preload("res://scripts/graphics_setup.gd")

var _nav := _MenuNav.new()


func _ready() -> void:
	%MasterSlider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	%MusicCheck.set_pressed_no_signal(GameState.music_enabled)
	%ArcadeCheck.set_pressed_no_signal(GameState.arcade_drive)
	%ImperialCheck.set_pressed_no_signal(GameState.imperial_units)
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_nav.setup([
		%GraphicsBtn,
		%MasterSlider,
		%MusicCheck,
		%ArcadeCheck,
		%ImperialCheck,
		%ControlsBtn,
		$Margin/VBox/BackButton,
	])


func _unhandled_input(event: InputEvent) -> void:
	if _nav.handle_event(self, event):
		accept_event()


func _on_back_pressed() -> void:
	GameState.save_settings()
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)


func _on_graphics_pressed() -> void:
	_GraphicsSetup.new().open(self, $Margin, %GraphicsBtn)


func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))


func _on_music_toggled(pressed: bool) -> void:
	GameState.set_music_enabled(pressed)


func _on_arcade_toggled(pressed: bool) -> void:
	GameState.set_arcade_drive(pressed)


func _on_imperial_toggled(pressed: bool) -> void:
	GameState.set_imperial_units(pressed)


func _on_controls_pressed() -> void:
	_ControlsSetup.new().open(self, $Margin, %ControlsBtn)
