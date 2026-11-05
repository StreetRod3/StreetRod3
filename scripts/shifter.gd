extends RefCounted

## A shifter as bound in the shifter setup (shifter_setup.gd). An H-pattern holds down one
## button per gear, and none in neutral. A sequential, or a wheel's paddles, has one button
## for up and one for down. A binding keeps the device's GUID, since the number a device gets
## can change from one run to the next.

const UP := "up"
const DOWN := "down"
const REVERSE := "reverse"
const GEARS: Array[String] = ["1", "2", "3", "4", "5", "6"]

## What position() returns besides a gear from 0. Neutral and reverse match the car's gears.
const POSITION_NEUTRAL := -1
const POSITION_REVERSE := -2
const POSITION_NONE := -3


static func actions() -> Array[String]:
	var list: Array[String] = [UP, DOWN]
	list.append_array(GEARS)
	list.append(REVERSE)
	return list


static func action_label(action: String) -> String:
	match action:
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


## Where the H-pattern is now, or POSITION_NONE with none bound and plugged in.
static func position() -> int:
	if GameState.shifter_bindings.is_empty():
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
	return device >= 0 and Input.is_joy_button_pressed(device, int(GameState.shifter_bindings[action].get("button", 0)) as JoyButton)


static func is_plugged_in(action: String) -> bool:
	return _device_for(action) >= 0


## A button does one job, so taking it for a gear takes it off anything it did before.
static func bind(action: String, device: int, button: int) -> void:
	var guid := Input.get_joy_guid(device)
	for other: String in actions():
		var held: Variant = GameState.shifter_bindings.get(other)
		if held is Dictionary and str(held.get("guid", "")) == guid and int(held.get("button", -1)) == button:
			GameState.shifter_bindings.erase(other)
	GameState.shifter_bindings[action] = {"guid": guid, "name": Input.get_joy_name(device), "button": button}
	GameState.save_settings()


static func unbind(action: String) -> void:
	GameState.shifter_bindings.erase(action)
	GameState.save_settings()


static func clear() -> void:
	GameState.shifter_bindings.clear()
	GameState.save_settings()


static func _device_for(action: String) -> int:
	var binding: Variant = GameState.shifter_bindings.get(action)
	if not binding is Dictionary:
		return -1
	var guid := str(binding.get("guid", ""))
	for device: int in Input.get_connected_joypads():
		if Input.get_joy_guid(device) == guid:
			return device
	return -1
