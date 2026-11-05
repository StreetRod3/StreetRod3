extends RefCounted

## A wheel, pedals, and shifter as bound in the setup page (controller_setup.gd). An H-pattern
## holds down one button per gear, and none in neutral. A sequential, or a wheel's paddles, has
## one button for up and one for down. A binding keeps the device's GUID, since the number a
## device gets can change from one run to the next.

const STEER := "steer"
const THROTTLE := "throttle"
const BRAKE := "brake"
const HANDBRAKE := "handbrake"
const UP := "up"
const DOWN := "down"
const REVERSE := "reverse"
const GEARS: Array[String] = ["1", "2", "3", "4", "5", "6", "7"]

## What position() returns besides a gear from 0. Neutral and reverse match the car's gears.
const POSITION_NEUTRAL := -1
const POSITION_REVERSE := -2
const POSITION_NONE := -3

## Wheel noise around center, as a share of the axis.
const STEER_DEAD_ZONE := 0.005
## Pedals read nothing at the very top of their travel, and full at the very bottom.
const PEDAL_DEAD_LOW := 0.04
const PEDAL_DEAD_HIGH := 0.96
## An axis on the hand brake is on past this much of its travel.
const HANDBRAKE_ON := 0.5


static func wheel_actions() -> Array[String]:
	return [STEER, THROTTLE, BRAKE, HANDBRAKE]


static func shifter_actions() -> Array[String]:
	var list: Array[String] = [UP, DOWN]
	list.append_array(GEARS)
	list.append(REVERSE)
	return list


static func actions() -> Array[String]:
	var list := wheel_actions()
	list.append_array(shifter_actions())
	return list


static func takes_button(action: String) -> bool:
	return action != STEER and action != THROTTLE and action != BRAKE


static func takes_axis(action: String) -> bool:
	return action == STEER or action == THROTTLE or action == BRAKE or action == HANDBRAKE


static func action_label(action: String) -> String:
	match action:
		STEER:
			return "Steering"
		THROTTLE:
			return "Throttle"
		BRAKE:
			return "Brake"
		HANDBRAKE:
			return "Hand brake"
		UP:
			return "Shift up"
		DOWN:
			return "Shift down"
		REVERSE:
			return "Reverse"
		"1":
			return "1st"
		"2":
			return "2nd"
		"3":
			return "3rd"
	return "%sth" % action


## From -1 for full right to 1 for full left, the same way as the keys.
static func steer() -> float:
	var device := _device_for(STEER)
	if device < 0:
		return 0.0
	var binding: Dictionary = GameState.controller_bindings[STEER]
	var value := Input.get_joy_axis(device, int(binding.get("axis", 0)) as JoyAxis)
	if absf(value) < STEER_DEAD_ZONE:
		return 0.0
	var right := signf(float(binding.get("full", 1.0)) - float(binding.get("rest", 0.0)))
	return clampf(-value * right * GameState.steer_sensitivity, -1.0, 1.0)


## How far a pedal is pressed, from 0 to 1.
static func pedal(action: String) -> float:
	var device := _device_for(action)
	if device < 0:
		return 0.0
	var binding: Dictionary = GameState.controller_bindings[action]
	var value := Input.get_joy_axis(device, int(binding.get("axis", 0)) as JoyAxis)
	# An axis reads 0 until it first moves, so one resting at the end of its travel would read
	# half pressed on the start line.
	if is_zero_approx(value):
		return 0.0
	var pressed := inverse_lerp(float(binding.get("rest", -1.0)), float(binding.get("full", 1.0)), value)
	return clampf(inverse_lerp(PEDAL_DEAD_LOW, PEDAL_DEAD_HIGH, pressed), 0.0, 1.0)


## Where the H-pattern is now, or POSITION_NONE with none bound and plugged in.
static func position() -> int:
	if GameState.controller_bindings.is_empty():
		return POSITION_NONE
	var fitted := is_plugged_in(REVERSE)
	if is_down(REVERSE):
		return POSITION_REVERSE
	for i: int in GEARS.size():
		fitted = fitted or is_plugged_in(GEARS[i])
		if is_down(GEARS[i]):
			return i
	return POSITION_NEUTRAL if fitted else POSITION_NONE


static func is_down(action: String) -> bool:
	var device := _device_for(action)
	if device < 0:
		return false
	var binding: Dictionary = GameState.controller_bindings[action]
	if binding.has("axis"):
		return pedal(action) >= HANDBRAKE_ON
	return Input.is_joy_button_pressed(device, int(binding.get("button", 0)) as JoyButton)


static func is_plugged_in(action: String) -> bool:
	return _device_for(action) >= 0


## A button does one job, so taking it for a gear takes it off anything it did before.
static func bind_button(action: String, device: int, button: int) -> void:
	var guid := Input.get_joy_guid(device)
	for other: String in actions():
		var held: Variant = GameState.controller_bindings.get(other)
		if held is Dictionary and str(held.get("guid", "")) == guid and int(held.get("button", -1)) == button:
			GameState.controller_bindings.erase(other)
	GameState.controller_bindings[action] = {"guid": guid, "name": Input.get_joy_name(device), "button": button}
	_bindings_changed()


## An axis can do two jobs if they lie in opposite directions, for gas and brake on one axis.
static func bind_axis(action: String, device: int, axis: int, rest: float, full: float) -> void:
	var guid := Input.get_joy_guid(device)
	for other: String in actions():
		var held: Variant = GameState.controller_bindings.get(other)
		if held is Dictionary and str(held.get("guid", "")) == guid and int(held.get("axis", -1)) == axis:
			if signf(float(held.get("full", 0.0)) - float(held.get("rest", 0.0))) == signf(full - rest):
				GameState.controller_bindings.erase(other)
	GameState.controller_bindings[action] = {"guid": guid, "name": Input.get_joy_name(device), "axis": axis, "rest": rest, "full": full}
	_bindings_changed()


static func unbind(action: String) -> void:
	GameState.controller_bindings.erase(action)
	_bindings_changed()


static func clear() -> void:
	GameState.controller_bindings.clear()
	_bindings_changed()


## Godot's default menu actions take some joypad buttons and the first two axes. Those would
## run the menu focus around whenever the wheel turned, a pedal moved, or a gear went in, so
## anything bound comes off them.
static func free_menu_inputs() -> void:
	InputMap.load_from_project_settings()
	var buttons: Array[int] = []
	var axes: Array[int] = []
	for binding: Variant in GameState.controller_bindings.values():
		if binding is Dictionary:
			if binding.has("axis"):
				axes.append(int(binding.get("axis", -1)))
			else:
				buttons.append(int(binding.get("button", -1)))
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton and buttons.has(int(event.button_index)):
				InputMap.action_erase_event(action, event)
			elif event is InputEventJoypadMotion and axes.has(int(event.axis)):
				InputMap.action_erase_event(action, event)


static func _bindings_changed() -> void:
	free_menu_inputs()
	GameState.save_settings()


static func _device_for(action: String) -> int:
	var binding: Variant = GameState.controller_bindings.get(action)
	if not binding is Dictionary:
		return -1
	var guid := str(binding.get("guid", ""))
	for device: int in Input.get_connected_joypads():
		if Input.get_joy_guid(device) == guid:
			return device
	return -1
