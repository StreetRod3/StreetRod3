extends RefCounted

## Rumble on any gamepad, from what the car is doing. Each request only lasts a moment and gets
## renewed, so it dies away by itself once the game stops asking: paused, parked, or gone.

const SEND_EVERY_S := 0.05
const LASTS_S := 0.2
## How fast a jolt dies away, per second, once it has hit.
const PULSE_FALL := 3.5
## A change too small to be felt is not worth sending.
const CHANGE_FELT := 0.02

const _Controller := preload("res://scripts/controller.gd")

var _pulse_weak: float = 0.0
var _pulse_strong: float = 0.0
var _since_sent: float = 0.0
var _sent_weak: float = 0.0
var _sent_strong: float = 0.0


## A jolt on top of whatever else is going on, such as a hit or a shift.
func pulse(weak: float, strong: float) -> void:
	_pulse_weak = maxf(_pulse_weak, weak)
	_pulse_strong = maxf(_pulse_strong, strong)


## `weak` is the fast buzz, and `strong` the heavy thump, each from 0 to 1. Call every step.
func update(delta: float, weak: float, strong: float) -> void:
	_pulse_weak = move_toward(_pulse_weak, 0.0, PULSE_FALL * delta)
	_pulse_strong = move_toward(_pulse_strong, 0.0, PULSE_FALL * delta)
	_since_sent += delta
	var scale := GameState.rumble_strength
	var now_weak := clampf(maxf(weak, _pulse_weak), 0.0, 1.0) * scale
	var now_strong := clampf(maxf(strong, _pulse_strong), 0.0, 1.0) * scale
	if now_weak <= 0.0 and now_strong <= 0.0:
		if _sent_weak > 0.0 or _sent_strong > 0.0:
			stop()
		return
	var changed := absf(now_weak - _sent_weak) >= CHANGE_FELT or absf(now_strong - _sent_strong) >= CHANGE_FELT
	if _since_sent < SEND_EVERY_S and not (changed and _sent_weak <= 0.0 and _sent_strong <= 0.0):
		return
	_since_sent = 0.0
	_sent_weak = now_weak
	_sent_strong = now_strong
	for device: int in _Controller.pads():
		Input.start_joy_vibration(device, now_weak, now_strong, LASTS_S)


func stop() -> void:
	_sent_weak = 0.0
	_sent_strong = 0.0
	for device: int in _Controller.pads():
		Input.stop_joy_vibration(device)
