extends RefCounted

## Sizes a driving HUD by the setting: the panel shrinks into its top right corner and the rev
## counter down toward the bottom middle, so both stay where they were, only smaller.

const SMALLEST := 0.6
const STEP := 0.1


static func apply(panel: Control, meter: Control) -> void:
	var size := clampf(GameState.hud_size, SMALLEST, 1.0)
	panel.scale = Vector2(size, size)
	panel.pivot_offset = Vector2(panel.size.x, 0.0)
	if not panel.has_meta(&"hud_pinned"):
		panel.set_meta(&"hud_pinned", true)
		# Hiding the hints narrows the panel, which moves its corner.
		panel.resized.connect(func() -> void: panel.pivot_offset = Vector2(panel.size.x, 0.0))
	if meter != null:
		meter.pivot_offset = Vector2(meter.size.x * 0.5, meter.size.y)
		meter.scale = Vector2(size, size)
