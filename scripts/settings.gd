extends Control

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _ControlsSetup := preload("res://scripts/controls_setup.gd")
const _GraphicsSetup := preload("res://scripts/graphics_setup.gd")

var _nav := _MenuNav.new()


func _ready() -> void:
	%MasterSlider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	%MusicCheck.set_pressed_no_signal(GameState.music_enabled)
	%MusicSlider.value = GameState.music_volume
	%ArcadeCheck.set_pressed_no_signal(GameState.arcade_drive)
	_show_retro_switch()
	%ImperialCheck.set_pressed_no_signal(GameState.imperial_units)
	%SkipCruiseCheck.set_pressed_no_signal(GameState.skip_cruise)
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_nav.setup([
		%GraphicsBtn,
		%RetroSwitch,
		%MasterSlider,
		%MusicCheck,
		%MusicSlider,
		%ArcadeCheck,
		%ImperialCheck,
		%SkipCruiseCheck,
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
	var page := _GraphicsSetup.new()
	page.tree_exited.connect(_show_retro_switch)
	page.open(self, $Margin, %GraphicsBtn)


func _on_retro_switch_pressed() -> void:
	GameState.cycle_retro()
	_show_retro_switch()


func _show_retro_switch() -> void:
	%RetroSwitch.text = GameState.retro_switch_text()


func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))


func _on_music_toggled(pressed: bool) -> void:
	GameState.set_music_enabled(pressed)


func _on_music_volume_changed(value: float) -> void:
	GameState.set_music_volume(value)


func _on_arcade_toggled(pressed: bool) -> void:
	GameState.set_arcade_drive(pressed)


func _on_imperial_toggled(pressed: bool) -> void:
	GameState.set_imperial_units(pressed)


func _on_skip_cruise_toggled(pressed: bool) -> void:
	GameState.set_skip_cruise(pressed)


func _on_controls_pressed() -> void:
	_ControlsSetup.new().open(self, $Margin, %ControlsBtn)
