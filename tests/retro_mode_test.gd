extends SceneTree

## Retro mode: the switch shows on the graphics page, the full-screen pass follows it, and the
## garage's own viewport is restyled instead of being painted over.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	var retro := state.get_node("RetroMode") as CanvasLayer
	var mask := retro.get_node("Characters") as ColorRect
	var was: bool = state.retro_mode
	state.call("set_retro_mode", true)
	assert(mask.visible)
	state.call("set_retro_mode", false)
	assert(not mask.visible)

	var holder := SubViewportContainer.new()
	root.add_child(holder)
	state.call("set_retro_mode", true)
	retro.call("cover_view", holder)
	assert(not mask.visible)
	assert(holder.material != null)
	holder.free()
	assert(mask.visible)
	assert(state.retro_mode)

	var host := Control.new()
	root.add_child(host)
	var page := Control.new()
	var back := Button.new()
	host.add_child(page)
	page.add_child(back)
	var setup: CanvasLayer = (load("res://scripts/graphics_setup.gd") as Script).new()
	setup.call("open", host, page, back)
	var box := setup.find_child("RetroMode", true, false) as CheckBox
	assert(box != null)
	assert(box.text == "Retro mode")
	assert(box.button_pressed)
	var sky := setup.get("_retro_sky") as ColorRect
	assert(sky.visible)
	box.button_pressed = false
	assert(not state.retro_mode)
	assert(not mask.visible)
	assert(not sky.visible)
	box.button_pressed = true
	assert(state.retro_mode and mask.visible and sky.visible)
	await process_frame
	host.free()

	state.call("set_retro_mode", was)
	var settings := (load("res://scenes/settings.tscn") as PackedScene).instantiate()
	root.add_child(settings)
	var settings_box := settings.get_node(^"Margin/VBox/RetroCheck") as CheckBox
	assert(settings_box != null)
	assert(settings_box.text == "Retro mode")
	assert(settings_box.button_pressed == was)
	settings_box.button_pressed = not was
	assert(state.retro_mode == (not was))
	settings_box.button_pressed = was
	settings.free()
	print("Retro mode checks passed.")
	quit()
