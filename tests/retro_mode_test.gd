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
	var high_was: bool = state.retro_high
	var mat := mask.material as ShaderMaterial
	state.call("set_retro_high", false)
	assert(mat.get_shader_parameter("cell_px") == Vector2(8, 16))
	state.call("set_retro_high", true)
	assert(mat.get_shader_parameter("cell_px") == Vector2(4, 8))
	state.call("set_retro_high", high_was)
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
	state.call("set_retro_high", true)
	state.call("set_retro_mode", true)
	var setup: CanvasLayer = (load("res://scripts/graphics_setup.gd") as Script).new()
	setup.call("open", host, page, back)
	var box := setup.find_child("RetroSwitch", true, false) as Button
	assert(box != null)
	assert(box.text == "Retro: high")
	var sky := setup.get("_retro_sky") as ColorRect
	assert(sky.visible)
	box.pressed.emit()
	assert(state.retro_mode and not state.retro_high)
	assert(box.text == "Retro: low")
	assert(sky.visible)
	box.pressed.emit()
	assert(not state.retro_mode)
	assert(box.text == "Retro: off")
	assert(not sky.visible)
	box.pressed.emit()
	assert(state.retro_mode and state.retro_high)
	assert(box.text == "Retro: high")
	await process_frame
	host.free()

	state.call("set_retro_mode", was)
	state.call("set_retro_high", high_was)
	var settings := (load("res://scenes/settings.tscn") as PackedScene).instantiate()
	root.add_child(settings)
	var settings_box := settings.get_node(^"Margin/VBox/RetroSwitch") as Button
	assert(settings_box != null)
	assert(settings_box.text == str(state.call("retro_switch_text")))
	var before := int(state.call("retro_position"))
	settings_box.pressed.emit()
	assert(int(state.call("retro_position")) == (before + 1) % 3)
	state.call("set_retro_mode", was)
	state.call("set_retro_high", high_was)
	settings.free()
	print("Retro mode checks passed.")
	quit()
