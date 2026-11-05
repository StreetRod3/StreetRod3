extends RefCounted

## A wheel, pedals, and shifter as bound in the setup page (controller_setup.gd). An H-pattern
## holds down one button per gear, and none in neutral. A sequential, or a wheel's paddles, has
## one button for up and one for down. A binding keeps the device's GUID, since the number a
## device gets can change from one run to the next. Keyboard and gamepad driving controls are
## here too, and have their own page in controls_setup.gd, since a key or a gamepad's layout
## is the same on any machine.

const STEER := "steer"
const THROTTLE := "throttle"
const BRAKE := "brake"
const HANDBRAKE := "handbrake"
const CAMERA := "camera"
const PAUSE := "pause"
const STEER_LEFT := "steer_left"
const STEER_RIGHT := "steer_right"
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
## A button-like job taken by a stick or a trigger is on past this much of its travel.
const ACTION_ON := 0.5
## A key or gamepad slot with nothing in it.
const NO_KEY := 0
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
## A Switch pad's letters sit the other way around from an Xbox pad's, so Godot's A, on the
## bottom, says B on the pad. ZL and ZR are plain buttons, which Godot reports as full triggers.
const NINTENDO_NAMES: Dictionary[int, String] = {
	JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
	JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R",
	JOY_BUTTON_BACK: "Minus", JOY_BUTTON_START: "Plus", JOY_BUTTON_GUIDE: "Home",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
## USB vendor numbers, as Godot reports them. Pads from others that act as one say so in their
## name instead.
const SONY_VENDOR := "1356"
const NINTENDO_VENDOR := "1406"
const PLAYSTATION_WORDS: Array[String] = ["ps3", "ps4", "ps5", "playstation", "dualshock", "dualsense"]
const NINTENDO_WORDS: Array[String] = ["nintendo", "switch", "joy-con", "joycon"]

enum PadMaker { XBOX, PLAYSTATION, NINTENDO }

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
		STEER_LEFT:
			return "Steer left"
		STEER_RIGHT:
			return "Steer right"
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


## A bound wheel, from -1 for full right to 1 for full left, or 0 with none.
static func steer() -> float:
	var device := _device_for(STEER)
	if device < 0:
		return 0.0
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


## How far a bound pedal is pressed, from 0 to 1.
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


## Who made a gamepad, going by its USB vendor and then its name. Xbox names are the default.
static func pad_maker(device: int) -> PadMaker:
	var vendor := str(Input.get_joy_info(device).get("vendor_id", ""))
	if vendor == SONY_VENDOR:
		return PadMaker.PLAYSTATION
	if vendor == NINTENDO_VENDOR:
		return PadMaker.NINTENDO
	var pad_name := Input.get_joy_name(device).to_lower()
	for word: String in PLAYSTATION_WORDS:
		if pad_name.contains(word):
			return PadMaker.PLAYSTATION
	for word: String in NINTENDO_WORDS:
		if pad_name.contains(word):
			return PadMaker.NINTENDO
	return PadMaker.XBOX


## Names go by the first gamepad, and by Xbox with none plugged in.
static func _names_maker() -> PadMaker:
	var found := pads()
	return pad_maker(found[0]) if not found.is_empty() else PadMaker.XBOX


## The button a menu takes as yes. On a Switch pad that is the one that says A, on the right.
static func confirm_button(device: int) -> JoyButton:
	return JOY_BUTTON_B if pad_maker(device) == PadMaker.NINTENDO else JOY_BUTTON_A


static func back_button(device: int) -> JoyButton:
	return JOY_BUTTON_A if pad_maker(device) == PadMaker.NINTENDO else JOY_BUTTON_B


## Each gamepad by its own layout, so two different makes can both work the menus.
static func confirm_down() -> bool:
	for device: int in pads():
		var button := confirm_button(device)
		if Input.is_joy_button_pressed(device, button) and not _is_bound(device, int(button)):
			return true
	return false


static func back_down() -> bool:
	for device: int in pads():
		var button := back_button(device)
		if Input.is_joy_button_pressed(device, button) and not _is_bound(device, int(button)):
			return true
	return false


## Whether the yes button has a driving job, so it does not also press Enter on the road.
static func confirm_has_job() -> bool:
	for device: int in pads():
		if pad_button_has_job(confirm_button(device)):
			return true
	return false


static func button_name(button: JoyButton) -> String:
	var names := XBOX_NAMES
	match _names_maker():
		PadMaker.PLAYSTATION:
			names = PLAYSTATION_NAMES
		PadMaker.NINTENDO:
			names = NINTENDO_NAMES
	return names.get(int(button), "Button %d" % int(button))


static func trigger_name(axis: JoyAxis) -> String:
	match _names_maker():
		PadMaker.PLAYSTATION:
			return "R2" if axis == JOY_AXIS_TRIGGER_RIGHT else "L2"
		PadMaker.NINTENDO:
			return "ZR" if axis == JOY_AXIS_TRIGGER_RIGHT else "ZL"
	return "RT" if axis == JOY_AXIS_TRIGGER_RIGHT else "LT"


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


## A stick across all gamepads, with its dead zone taken out, for the pointer and scrolling.
static func pad_stick(x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	for device: int in pads():
		var stick := Vector2(Input.get_joy_axis(device, x_axis), Input.get_joy_axis(device, y_axis))
		if stick.length() > STICK_DEAD_ZONE:
			return stick.normalized() * inverse_lerp(STICK_DEAD_ZONE, 1.0, minf(stick.length(), 1.0))
	return Vector2.ZERO


## The jobs on the controls page, in its order.
static func control_actions() -> Array[String]:
	return [THROTTLE, BRAKE, STEER_LEFT, STEER_RIGHT, HANDBRAKE, UP, DOWN, CAMERA, PAUSE]


static func control_label(action: String) -> String:
	return action_label(action)


## Nothing here for Pause, since Esc always does that too.
static func default_keys(action: String) -> Array:
	match action:
		THROTTLE:
			return [KEY_W, KEY_UP]
		BRAKE:
			return [KEY_S, KEY_DOWN]
		STEER_LEFT:
			return [KEY_A, KEY_LEFT]
		STEER_RIGHT:
			return [KEY_D, KEY_RIGHT]
		HANDBRAKE:
			return [KEY_SPACE, NO_KEY]
		UP:
			return [KEY_E, NO_KEY]
		DOWN:
			return [KEY_Q, NO_KEY]
		CAMERA:
			return [KEY_C, NO_KEY]
	return [NO_KEY, NO_KEY]


## Each slot is a button, or an axis and the way it has to go, or empty.
static func default_pad(action: String) -> Array:
	match action:
		THROTTLE:
			return [{"axis": int(JOY_AXIS_TRIGGER_RIGHT), "dir": 1}, {}]
		BRAKE:
			return [{"axis": int(JOY_AXIS_TRIGGER_LEFT), "dir": 1}, {}]
		STEER_LEFT:
			return [{"axis": int(JOY_AXIS_LEFT_X), "dir": -1}, {"button": int(JOY_BUTTON_DPAD_LEFT)}]
		STEER_RIGHT:
			return [{"axis": int(JOY_AXIS_LEFT_X), "dir": 1}, {"button": int(JOY_BUTTON_DPAD_RIGHT)}]
		HANDBRAKE:
			return [{"button": int(JOY_BUTTON_X)}, {}]
		UP:
			return [{"button": int(JOY_BUTTON_RIGHT_SHOULDER)}, {}]
		DOWN:
			return [{"button": int(JOY_BUTTON_LEFT_SHOULDER)}, {}]
		CAMERA:
			return [{"button": int(JOY_BUTTON_Y)}, {}]
		PAUSE:
			return [{"button": int(JOY_BUTTON_START)}, {}]
	return [{}, {}]


static func keys_for(action: String) -> Array:
	return GameState.control_keys.get(action, default_keys(action))


static func pad_for(action: String) -> Array:
	return GameState.control_pad.get(action, default_pad(action))


## How hard a job is being asked for by the keyboard and gamepad, from 0 to 1.
static func amount(action: String) -> float:
	for code: Variant in keys_for(action):
		if int(code) != NO_KEY and Input.is_key_pressed(int(code) as Key):
			return 1.0
	var most := 0.0
	for device: int in pads():
		for entry: Variant in pad_for(action):
			most = maxf(most, _pad_amount(device, entry))
	return most


## A job that is on or off, from the keys, the gamepad, or a bound wheel or shifter.
static func action_down(action: String) -> bool:
	return amount(action) >= ACTION_ON or is_down(action)


## Pause, for gamepad.gd. Out on the road the gamepad can do it, and in the pause menu its fixed
## buttons take over, or going back would count twice. Esc is left out, being Esc already.
static func pause_down(on_road: bool) -> bool:
	if is_down(PAUSE):
		return true
	for code: Variant in keys_for(PAUSE):
		if int(code) != NO_KEY and Input.is_key_pressed(int(code) as Key):
			return true
	if not on_road:
		return false
	for device: int in pads():
		for entry: Variant in pad_for(PAUSE):
			if _pad_amount(device, entry) >= ACTION_ON:
				return true
	return false


## Whether a gamepad button has a driving job, so it does not also do its menu job on the road.
static func pad_button_has_job(button: JoyButton) -> bool:
	for action: String in control_actions():
		for entry: Variant in pad_for(action):
			if entry is Dictionary and int(entry.get("button", -1)) == int(button):
				return true
	return false


static func _pad_amount(device: int, entry: Variant) -> float:
	if not entry is Dictionary or entry.is_empty():
		return 0.0
	if entry.has("button"):
		var button := int(entry["button"])
		if Input.is_joy_button_pressed(device, button as JoyButton) and not _is_bound(device, button):
			return 1.0
		return 0.0
	var axis := int(entry.get("axis", 0))
	var low := PEDAL_DEAD_LOW if axis == JOY_AXIS_TRIGGER_LEFT or axis == JOY_AXIS_TRIGGER_RIGHT else STICK_DEAD_ZONE
	var value := Input.get_joy_axis(device, axis as JoyAxis) * float(entry.get("dir", 1))
	return clampf(inverse_lerp(low, PEDAL_DEAD_HIGH, value), 0.0, 1.0)


static func set_key(action: String, slot: int, code: int) -> void:
	var was: int = int(keys_for(action)[slot])
	_take_key_off_all(code)
	if was != code:
		var keys := keys_for(action).duplicate()
		keys[slot] = code
		GameState.control_keys[action] = keys
	GameState.save_settings()


static func clear_key(action: String, slot: int) -> void:
	var keys := keys_for(action).duplicate()
	keys[slot] = NO_KEY
	GameState.control_keys[action] = keys
	GameState.save_settings()


static func set_pad(action: String, slot: int, entry: Dictionary) -> void:
	var same: bool = pad_for(action)[slot] == entry
	_take_pad_off_all(entry)
	if not same:
		var list := pad_for(action).duplicate(true)
		list[slot] = entry
		GameState.control_pad[action] = list
	GameState.save_settings()


static func clear_pad(action: String, slot: int) -> void:
	var list := pad_for(action).duplicate(true)
	list[slot] = {}
	GameState.control_pad[action] = list
	GameState.save_settings()


static func reset_controls() -> void:
	GameState.control_keys.clear()
	GameState.control_pad.clear()
	GameState.save_settings()


static func _take_key_off_all(code: int) -> void:
	for action: String in control_actions():
		var keys := keys_for(action).duplicate()
		if keys.has(code):
			keys[keys.find(code)] = NO_KEY
			GameState.control_keys[action] = keys


static func _take_pad_off_all(entry: Dictionary) -> void:
	for action: String in control_actions():
		var list := pad_for(action).duplicate(true)
		var at := list.find(entry)
		if at >= 0:
			list[at] = {}
			GameState.control_pad[action] = list


static func key_slot_name(action: String, slot: int) -> String:
	var code := int(keys_for(action)[slot])
	return OS.get_keycode_string(code as Key) if code != NO_KEY else "Not set"


static func pad_slot_name(action: String, slot: int) -> String:
	return pad_entry_name(pad_for(action)[slot])


static func pad_entry_name(entry: Variant) -> String:
	if not entry is Dictionary or entry.is_empty():
		return "Not set"
	if entry.has("button"):
		return button_name(int(entry["button"]) as JoyButton)
	var axis := int(entry.get("axis", 0)) as JoyAxis
	if axis == JOY_AXIS_TRIGGER_LEFT or axis == JOY_AXIS_TRIGGER_RIGHT:
		return trigger_name(axis)
	var negative := int(entry.get("dir", 1)) < 0
	match axis:
		JOY_AXIS_LEFT_X:
			return "Left stick left" if negative else "Left stick right"
		JOY_AXIS_LEFT_Y:
			return "Left stick up" if negative else "Left stick down"
		JOY_AXIS_RIGHT_X:
			return "Right stick left" if negative else "Right stick right"
		JOY_AXIS_RIGHT_Y:
			return "Right stick up" if negative else "Right stick down"
	return "Axis %d" % int(axis)


## The driving controls for the HUD, as they are set now.
static func driving_hint(automatic: bool) -> String:
	return _pad_hint() if not pads().is_empty() else _key_hint(automatic)


static func _key_hint(automatic: bool) -> String:
	var shifting := "drive, reverse" if automatic else "shift, reverse"
	return "%s: throttle · %s: brake · %s: hand brake · %s, %s: steer · %s, %s: %s · %s: camera · %s+%s: burnout" % [
		_keys_text(THROTTLE), _keys_text(BRAKE), _keys_text(HANDBRAKE), _keys_text(STEER_LEFT), _keys_text(STEER_RIGHT),
		_keys_text(DOWN), _keys_text(UP), shifting, _keys_text(CAMERA), _first_key_text(THROTTLE), _first_key_text(BRAKE),
	]


static func _keys_text(action: String) -> String:
	var names: Array[String] = []
	for slot: int in keys_for(action).size():
		if int(keys_for(action)[slot]) != NO_KEY:
			names.append(key_slot_name(action, slot))
	return " / ".join(names) if not names.is_empty() else "-"


static func _first_key_text(action: String) -> String:
	return _keys_text(action).split(" / ")[0]


static func _pad_hint() -> String:
	var left := _first_pad_entry(STEER_LEFT)
	var right := _first_pad_entry(STEER_RIGHT)
	var steering := "%s, %s" % [pad_entry_name(left), pad_entry_name(right)]
	if left.get("axis", -1) == right.get("axis", -2) and left.get("dir", 0) == -int(right.get("dir", 0)):
		steering = "Stick" if int(left.get("axis", -1)) == JOY_AXIS_LEFT_X else pad_entry_name(left).trim_suffix(" left")
	return "%s: steer · %s: gas · %s: brake · %s: hand brake · %s/%s: shift, reverse · %s: camera · %s: pause · %s+%s: burnout" % [
		steering,
		pad_entry_name(_first_pad_entry(THROTTLE)),
		pad_entry_name(_first_pad_entry(BRAKE)),
		pad_entry_name(_first_pad_entry(HANDBRAKE)),
		pad_entry_name(_first_pad_entry(DOWN)),
		pad_entry_name(_first_pad_entry(UP)),
		pad_entry_name(_first_pad_entry(CAMERA)),
		pad_entry_name(_first_pad_entry(PAUSE)),
		pad_entry_name(_first_pad_entry(THROTTLE)),
		pad_entry_name(_first_pad_entry(BRAKE)),
	]


static func _first_pad_entry(action: String) -> Dictionary:
	for entry: Variant in pad_for(action):
		if entry is Dictionary and not entry.is_empty():
			return entry
	return {}


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
