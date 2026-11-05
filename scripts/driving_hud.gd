extends RefCounted

## The driving HUD as set on the graphics page, for the race and the cruise alike: which lines
## it shows, and its size. The panel shrinks into its top right corner and the rev counter down
## toward the bottom middle, so both stay where they were, only smaller. Size scales everything
## in them, text and spacing alike.

const SMALLEST := 0.6
const STEP := 0.1
const HINTS := "hints"
const RPM := "rpm"
## What the HUD can show, in the order the graphics page lists it.
const ITEMS: Array[String] = ["opponent", "speed", "gear", "damage", "distance", "time", HINTS, RPM]
## The panel's line for each item. The hints line is the touch controls' to show or hide.
const LINES: Dictionary[String, String] = {
	"opponent": "OppLabel",
	"speed": "SpeedLabel",
	"gear": "GearLabel",
	"damage": "DamageLabel",
	"distance": "DistLabel",
	"time": "TimeLabel",
}


static func item_label(item: String) -> String:
	match item:
		"opponent":
			return "Opponent"
		"speed":
			return "Speed"
		"gear":
			return "Gear"
		"damage":
			return "Damage"
		"distance":
			return "Distance to finish"
		"time":
			return "Race time"
		HINTS:
			return "Control hints"
		RPM:
			return "Rev counter"
	return item


static func apply(panel: Control, meter: Control) -> void:
	var size := clampf(GameState.hud_size, SMALLEST, 1.0)
	var any_line := GameState.hud_shows(HINTS)
	var box := panel.get_node_or_null("Margin/VBox")
	for item: String in LINES:
		var line := box.get_node_or_null(LINES[item]) as Control if box != null else null
		if line != null:
			line.visible = GameState.hud_shows(item)
			any_line = any_line or line.visible
	# With every line off there is nothing left to put a box around.
	panel.visible = any_line
	panel.scale = Vector2(size, size)
	panel.pivot_offset = Vector2(panel.size.x, 0.0)
	if not panel.has_meta(&"hud_pinned"):
		panel.set_meta(&"hud_pinned", true)
		# Hiding lines narrows the panel, which moves its corner.
		panel.resized.connect(func() -> void: panel.pivot_offset = Vector2(panel.size.x, 0.0))
	if meter != null:
		meter.visible = GameState.hud_shows(RPM)
		meter.pivot_offset = Vector2(meter.size.x * 0.5, meter.size.y)
		meter.scale = Vector2(size, size)
