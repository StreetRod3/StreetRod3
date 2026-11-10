extends RefCounted

const PIXELS_FOR_FULL := 400.0
const SENSITIVITY_MIN := 0.25
const SENSITIVITY_MAX := 3.0

var steering := 0.0
var pedals := 0.0


func reset() -> void:
	steering = 0.0
	pedals = 0.0


func move(relative: Vector2, steering_enabled: bool, pedals_enabled: bool, steering_sensitivity: float, pedal_sensitivity: float) -> void:
	steering = clampf(steering - relative.x * steering_sensitivity / PIXELS_FOR_FULL, -1.0, 1.0) if steering_enabled else 0.0
	pedals = clampf(pedals - relative.y * pedal_sensitivity / PIXELS_FOR_FULL, -1.0, 1.0) if pedals_enabled else 0.0
