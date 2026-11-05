extends RefCounted

## The two ways off a place's bottom bar: home, or a drive around town.
## A new place adds these and connects the presses itself.

const _BACK_WIDTH := 228.0
const _TOWN_WIDTH := 196.0
const _GAP := 8.0
const _EDGE := 16.0


static func add_to(bar: Control) -> Dictionary:
	var back := _button(bar, "Back to garage (G)", _EDGE, _BACK_WIDTH)
	back.name = "BackButton"
	var town := _button(bar, "Town cruise (D)", _EDGE + _BACK_WIDTH + _GAP, _TOWN_WIDTH)
	town.name = "TownButton"
	return {"back": back, "town": town}


## D is the ui_right key, so a place has to read these in `_input`.
static func home_pressed(event: InputEvent) -> bool:
	return _plain_key(event, KEY_G)


static func cruise_pressed(event: InputEvent) -> bool:
	return _plain_key(event, KEY_D)


static func _plain_key(event: InputEvent, code: Key) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed or key.shift_pressed:
		return false
	return key.keycode == code


## How far labels on the bar should stop, clear of both buttons.
static func label_inset() -> float:
	return _EDGE + _BACK_WIDTH + _GAP + _TOWN_WIDTH + 16.0


static func _button(bar: Control, text: String, from_right: float, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 36.0)
	button.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	button.offset_right = -from_right
	button.offset_left = -from_right - width
	button.offset_top = -18.0
	button.offset_bottom = 18.0
	bar.add_child(button)
	return button
