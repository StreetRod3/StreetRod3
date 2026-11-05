extends CanvasLayer

## Makes a gamepad of a known make work everywhere with no setup, by pressing what the game
## already answers to: the D-pad is the arrow keys, A is Enter, and B and Start are Escape.
## Outside of driving the left stick moves a pointer, and A clicks with it. The game's own code
## never has to know a gamepad is there. Sticks and triggers for driving are in controller.gd.

const _Controller := preload("res://scripts/controller.gd")

## Across the window per second at full stick, as a share of its height.
const POINTER_SPEED := 1.1
## Scroll steps per second at full right stick, which zooms like a mouse wheel.
const SCROLL_RATE := 8.0
const SCROLL_STICK := 0.5
const RING_RADIUS := 11.0
const RING_COLOR := Color(1.0, 0.86, 0.2, 1.0)

## What a button can do besides press a key.
const NOTHING := 0
const CLICK := -1
const RIGHT_CLICK := -2
const ARROWS: Array[int] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]

var _down: Dictionary = {}
## What each held control did when it went down, so its release undoes the same thing.
var _pressed_as: Dictionary = {}
var _pointer := Vector2.ZERO
var _pointing: bool = false
var _scroll_time: float = 0.0
var _ring: Control


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Where the game should take the mouse to be, since the pointer here is not the system's.
func pointer_position(viewport: Viewport) -> Vector2:
	return _pointer if _pointing else viewport.get_mouse_position()


func _process(delta: float) -> void:
	var driving := _is_driving()
	if driving and _pointing:
		_stop_pointing()
	# A new scene sets the mouse back to visible.
	if _pointing and Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_update_buttons(driving)
	if not driving and not _Controller.capturing:
		_update_pointer(delta)
		_update_scroll(delta)


func _input(event: InputEvent) -> void:
	# The real mouse takes over from the pointer. The pointer's own moves land where it is.
	if _pointing and event is InputEventMouseMotion and event.position.distance_to(_pointer) > 1.0:
		_stop_pointing()


func _is_driving() -> bool:
	if get_tree().paused or get_tree().current_scene == null:
		return false
	var path := get_tree().current_scene.scene_file_path
	return path == GameState.SCENE_RACE or path == GameState.SCENE_CRUISE


func _update_buttons(driving: bool) -> void:
	_update_button(JOY_BUTTON_A, CLICK if _pointing else KEY_ENTER)
	_update_button(JOY_BUTTON_B, KEY_ESCAPE)
	_update_button(JOY_BUTTON_START, KEY_ESCAPE)
	_update_button(JOY_BUTTON_DPAD_UP, KEY_UP)
	_update_button(JOY_BUTTON_DPAD_DOWN, KEY_DOWN)
	_update_button(JOY_BUTTON_DPAD_LEFT, KEY_LEFT)
	_update_button(JOY_BUTTON_DPAD_RIGHT, KEY_RIGHT)
	_update_button(JOY_BUTTON_X, KEY_SPACE if driving else RIGHT_CLICK)
	_update_button(JOY_BUTTON_Y, KEY_C if driving else NOTHING)
	_update_button(JOY_BUTTON_LEFT_SHOULDER, KEY_Q if driving else NOTHING)
	_update_button(JOY_BUTTON_RIGHT_SHOULDER, KEY_E if driving else NOTHING)
	_update_button(JOY_BUTTON_BACK, NOTHING if driving else KEY_Q)
	# Any device can have these bound, and the game only knows them as keys.
	_update_source(_Controller.CAMERA, _Controller.is_down(_Controller.CAMERA), KEY_C)
	_update_source(_Controller.PAUSE, _Controller.is_down(_Controller.PAUSE), KEY_ESCAPE)


func _update_button(button: JoyButton, does: int) -> void:
	_update_source(button, _Controller.pad_button_down(button), does)


## A control held while the setup page was listening was its answer, not a press of its own, so
## nothing happens until it comes up and goes down again.
func _update_source(source: Variant, down: bool, does: int) -> void:
	if down == bool(_down.get(source, false)):
		return
	_down[source] = down
	if not down:
		_release(source)
	elif not _Controller.capturing and does != NOTHING:
		# The D-pad means going through the menu by its focus, not by the pointer.
		if ARROWS.has(does):
			_stop_pointing()
		_pressed_as[source] = does
		_emit(does, true)


func _release(source: Variant) -> void:
	if _pressed_as.has(source):
		_emit(int(_pressed_as[source]), false)
		_pressed_as.erase(source)


func _emit(does: int, pressed: bool) -> void:
	if does == CLICK or does == RIGHT_CLICK:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT if does == CLICK else MOUSE_BUTTON_RIGHT
		click.button_mask = (MOUSE_BUTTON_MASK_LEFT if does == CLICK else MOUSE_BUTTON_MASK_RIGHT) if pressed else (0 as MouseButtonMask)
		click.pressed = pressed
		_place(click)
		Input.parse_input_event(click)
		return
	var key := InputEventKey.new()
	key.keycode = does as Key
	key.physical_keycode = does as Key
	key.pressed = pressed
	Input.parse_input_event(key)


func _update_pointer(delta: float) -> void:
	var stick := _Controller.pad_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	if stick == Vector2.ZERO:
		return
	var view := get_viewport()
	if not _pointing:
		_pointing = true
		_pointer = view.get_mouse_position()
		_ring.visible = true
	var size := view.get_visible_rect().size
	var before := _pointer
	# Squared, for fine aim near center and a quick trip across at full stick.
	var step := stick * stick.length() * POINTER_SPEED * size.y * delta
	_pointer = (_pointer + step).clamp(Vector2.ZERO, size)
	_ring.position = _pointer
	var motion := InputEventMouseMotion.new()
	_place(motion)
	motion.relative = _pointer - before
	motion.velocity = motion.relative / maxf(delta, 0.001)
	motion.button_mask = Input.get_mouse_button_mask()
	Input.parse_input_event(motion)


func _update_scroll(delta: float) -> void:
	var stick := _Controller.pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	if absf(stick.y) < SCROLL_STICK:
		_scroll_time = 0.0
		return
	_scroll_time -= delta
	if _scroll_time > 0.0:
		return
	_scroll_time = 1.0 / SCROLL_RATE
	for pressed: bool in [true, false]:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP if stick.y < 0.0 else MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = pressed
		_place(wheel)
		Input.parse_input_event(wheel)


func _place(event: InputEventMouse) -> void:
	var at := _pointer if _pointing else get_viewport().get_mouse_position()
	event.position = at
	event.global_position = at


func _stop_pointing() -> void:
	if not _pointing:
		return
	_pointing = false
	_ring.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _draw_ring() -> void:
	_ring.draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 32, Color.BLACK, 4.0, true)
	_ring.draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 32, RING_COLOR, 2.0, true)
	_ring.draw_circle(Vector2.ZERO, 2.0, RING_COLOR)


## A pad pulled out with a button down would leave its key held for good.
func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	for source: Variant in _pressed_as.keys():
		_release(source)
	_down.clear()
	if _Controller.pads().is_empty():
		_stop_pointing()
