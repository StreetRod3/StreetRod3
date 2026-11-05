extends RefCounted

## A wheel, pedals, and shifter as bound in the setup page (controller_setup.gd). An H-pattern
## holds down one button per gear, and none in neutral. A sequential, or a wheel's paddles, has
## one button for up and one for down. A binding keeps the device's GUID, since the number a
## device gets can change from one run to the next. A gamepad of a known make needs none of
## this: left stick and triggers work as they are here, and gamepad.gd does its buttons. Binding
## is still there to change them.

const STEER := "steer"
const THROTTLE := "throttle"
const BRAKE := "brake"
const HANDBRAKE := "handbrake"
const CAMERA := "camera"
const PAUSE := "pause"
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
## A gamepad's stick noise around center, as a share of the axis.
const STICK_DEAD_ZONE := 0.12
## What the buttons are called on the pad in hand. These go by where a button sits, so Godot's X
## is the square on a PlayStation pad.
const XBOX_NAMES: Dictionary[int, String] = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
const PLAYSTATION_NAMES: Dictionary[int, String] = {
	JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_BACK: "Share", JOY_BUTTON_START: "Options", JOY_BUTTON_GUIDE: "PS",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
## Sony's USB vendor number, as Godot reports it. Pads from others that act as one say so in
## their name instead.
const SONY_VENDOR := "1356"
const PLAYSTATION_WORDS: Array[String] = ["ps3", "ps4", "ps5", "playstation", "dualshock", "dualsense"]

## Set while the setup page waits for an input, so the controls do nothing else meanwhile.
static var capturing: bool = false


static func wheel_actions() -> Array[String]:
	return [STEER, THROTTLE, BRAKE, HANDBRAKE, CAMERA, PAUSE]


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
		CAMERA:
			return "Camera"
		PAUSE:
			return "Pause"
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
		return _pad_stick()
	var binding: Dictionary = GameState.controller_bindings[STEER]
	var value := Input.get_joy_axis(device, int(binding.get("axis", 0)) as JoyAxis)
	if absf(value) < STEER_DEAD_ZONE:
		return 0.0
	var right := signf(float(binding.get("full", 1.0)) - float(binding.get("rest", 0.0)))
	var gain := 1.0 if Input.is_joy_known(device) else GameState.steer_sensitivity
	return clampf(-value * right * gain, -1.0, 1.0)


## A steering wheel, as against a gamepad's stick, which wants easing the way a key does.
static func is_wheel_steering() -> bool:
	var device := _device_for(STEER)
	return device >= 0 and not Input.is_joy_known(device)


## How far a pedal is pressed, from 0 to 1.
static func pedal(action: String) -> float:
	var device := _device_for(action)
	if device < 0:
		return _pad_trigger(action)
	var binding: Dictionary = GameState.controller_bindings[action]
	var value := Input.get_joy_axis(device, int(binding.get("axis", 0)) as JoyAxis)
	# An axis reads 0 until it first moves, so one resting at the end of its travel would read
	# half pressed on the start line.
	if is_zero_approx(value):
		return 0.0
	var pressed := inverse_lerp(float(binding.get("rest", -1.0)), float(binding.get("full", 1.0)), value)
	return clampf(inverse_lerp(PEDAL_DEAD_LOW, PEDAL_DEAD_HIGH, pressed), 0.0, 1.0)


## The first gamepad's names for its buttons. Xbox ones are the default, with or without a pad.
static func playstation_names() -> bool:
	var found := pads()
	if found.is_empty():
		return false
	if str(Input.get_joy_info(found[0]).get("vendor_id", "")) == SONY_VENDOR:
		return true
	var pad_name := Input.get_joy_name(found[0]).to_lower()
	for word: String in PLAYSTATION_WORDS:
		if pad_name.contains(word):
			return true
	return false


## What an unbound control does on a gamepad, for the setup page, or empty if nothing.
static func pad_default_label(action: String) -> String:
	match action:
		STEER:
			return "Gamepad: left stick"
		THROTTLE:
			return "Gamepad: %s" % trigger_name(JOY_AXIS_TRIGGER_RIGHT)
		BRAKE:
			return "Gamepad: %s" % trigger_name(JOY_AXIS_TRIGGER_LEFT)
		HANDBRAKE:
			return "Gamepad: %s" % button_name(JOY_BUTTON_X)
		CAMERA:
			return "Gamepad: %s" % button_name(JOY_BUTTON_Y)
		PAUSE:
			return "Gamepad: %s" % button_name(JOY_BUTTON_START)
		UP:
			return "Gamepad: %s" % button_name(JOY_BUTTON_RIGHT_SHOULDER)
		DOWN:
			return "Gamepad: %s" % button_name(JOY_BUTTON_LEFT_SHOULDER)
	return ""


static func button_name(button: JoyButton) -> String:
	var names := PLAYSTATION_NAMES if playstation_names() else XBOX_NAMES
	return names.get(int(button), "Button %d" % int(button))


static func trigger_name(axis: JoyAxis) -> String:
	if playstation_names():
		return "R2" if axis == JOY_AXIS_TRIGGER_RIGHT else "L2"
	return "RT" if axis == JOY_AXIS_TRIGGER_RIGHT else "LT"


## The driving controls for the HUD, by the names on the pad in hand.
static func pad_hint() -> String:
	return "Stick: steer · %s: gas · %s: brake · %s: hand brake · %s/%s: shift, reverse · %s: camera · %s: pause · %s+%s: burnout" % [
		trigger_name(JOY_AXIS_TRIGGER_RIGHT),
		trigger_name(JOY_AXIS_TRIGGER_LEFT),
		button_name(JOY_BUTTON_X),
		button_name(JOY_BUTTON_LEFT_SHOULDER),
		button_name(JOY_BUTTON_RIGHT_SHOULDER),
		button_name(JOY_BUTTON_Y),
		button_name(JOY_BUTTON_START),
		trigger_name(JOY_AXIS_TRIGGER_RIGHT),
		trigger_name(JOY_AXIS_TRIGGER_LEFT),
	]


## Gamepads Godot knows the layout of, which an unknown wheel or shifter is not.
static func pads() -> Array[int]:
	var found: Array[int] = []
	for device: int in Input.get_connected_joypads():
		if Input.is_joy_known(device):
			found.append(device)
	return found


## A button on any gamepad, unless the setup page gave that button a job of its own.
static func pad_button_down(button: JoyButton) -> bool:
	for device: int in pads():
		if Input.is_joy_button_pressed(device, button) and not _is_bound(device, int(button)):
			return true
	return false


## The left stick across all gamepads, with its dead zone taken out: x for steering, and both
## for the pointer outside of driving.
static func pad_stick(x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	for device: int in pads():
		var stick := Vector2(Input.get_joy_axis(device, x_axis), Input.get_joy_axis(device, y_axis))
		if stick.length() > STICK_DEAD_ZONE:
			return stick.normalized() * inverse_lerp(STICK_DEAD_ZONE, 1.0, minf(stick.length(), 1.0))
	return Vector2.ZERO


static func _pad_stick() -> float:
	return -pad_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y).x


static func _pad_trigger(action: String) -> float:
	var axis := JOY_AXIS_TRIGGER_RIGHT if action == THROTTLE else JOY_AXIS_TRIGGER_LEFT
	if action != THROTTLE and action != BRAKE:
		return 0.0
	var most := 0.0
	for device: int in pads():
		most = maxf(most, Input.get_joy_axis(device, axis))
	return clampf(inverse_lerp(PEDAL_DEAD_LOW, PEDAL_DEAD_HIGH, most), 0.0, 1.0)


static func _is_bound(device: int, button: int) -> bool:
	var guid := Input.get_joy_guid(device)
	for binding: Variant in GameState.controller_bindings.values():
		if binding is Dictionary and str(binding.get("guid", "")) == guid and int(binding.get("button", -1)) == button:
			return true
	return false


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
	GameState.save_settings()


## An axis can do two jobs if they lie in opposite directions, for gas and brake on one axis.
static func bind_axis(action: String, device: int, axis: int, rest: float, full: float) -> void:
	var guid := Input.get_joy_guid(device)
	for other: String in actions():
		var held: Variant = GameState.controller_bindings.get(other)
		if held is Dictionary and str(held.get("guid", "")) == guid and int(held.get("axis", -1)) == axis:
			if signf(float(held.get("full", 0.0)) - float(held.get("rest", 0.0))) == signf(full - rest):
				GameState.controller_bindings.erase(other)
	GameState.controller_bindings[action] = {"guid": guid, "name": Input.get_joy_name(device), "axis": axis, "rest": rest, "full": full}
	GameState.save_settings()


static func unbind(action: String) -> void:
	GameState.controller_bindings.erase(action)
	GameState.save_settings()


static func clear() -> void:
	GameState.controller_bindings.clear()
	GameState.save_settings()


## Godot's default menu actions take some joypad buttons and the first two axes, whatever the
## device. Those would run the menu focus around whenever a wheel turned, a pedal moved, or a
## gear went in, and a gamepad's stick moves the pointer here. gamepad.gd presses keys instead.
static func free_menu_inputs() -> void:
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)


static func device_of(action: String) -> int:
	return _device_for(action)


static func _device_for(action: String) -> int:
	var binding: Variant = GameState.controller_bindings.get(action)
	if not binding is Dictionary:
		return -1
	var guid := str(binding.get("guid", ""))
	for device: int in Input.get_connected_joypads():
		if Input.get_joy_guid(device) == guid:
			return device
	return -1
