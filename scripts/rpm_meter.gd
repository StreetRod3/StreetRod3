extends Control

const IDLE_RPM := 600.0
const METER_MAX := 7000.0
const CRUISE_START := 2800.0
const CRUISE_END := 3200.0
const KM_TO_MILES := 0.62137119
const SPEED_MAX_MPH := 160.0
const SPEED_MAX_KMH := 240.0

var _rpm: float = IDLE_RPM
var _shift_start: float = 5500.0
var _redline: float = 6500.0
var _critical: float = 6700.0
var _blown: bool = false
var _speed_kmh: float = 0.0
var _gear_text: String = "1"
var _imperial: bool = true
var _pulse: float = 0.0


func set_reading(
	rpm: float,
	shift_start: float,
	redline: float,
	critical: float,
	blown: bool,
	speed_kmh: float = 0.0,
	gear_text: String = "1",
	imperial: bool = true
) -> void:
	_rpm = rpm
	_shift_start = shift_start
	_redline = redline
	_critical = critical
	_blown = blown
	_speed_kmh = maxf(0.0, speed_kmh)
	_gear_text = gear_text
	_imperial = imperial
	queue_redraw()


func _process(delta: float) -> void:
	if _blown or _rpm >= _shift_start:
		_pulse += delta * (8.0 if _rpm >= _critical or _blown else 5.0)
	else:
		_pulse = 0.0
	if _rpm >= _shift_start or _blown:
		queue_redraw()


func _draw() -> void:
	var radius := minf(size.x * 0.21, size.y * 0.42)
	var center_y := size.y * 0.76
	var tach_center := Vector2(size.x * 0.255, center_y)
	var speed_center := Vector2(size.x * 0.745, center_y)
	var start_ang := deg_to_rad(200.0)
	var sweep := deg_to_rad(220.0)
	var font := get_theme_default_font()

	_draw_tachometer(tach_center, radius, start_ang, sweep, font)
	_draw_speedometer(speed_center, radius, start_ang, sweep, font)
	_draw_gear_badge(Vector2(size.x * 0.5, center_y + 10.0), font)


func _draw_tachometer(center: Vector2, radius: float, start_ang: float, sweep: float, font: Font) -> void:
	draw_circle(center + Vector2(2.0, 3.0), radius + 7.0, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(center, radius + 5.0, Color(0.08, 0.08, 0.09, 0.88))

	_draw_zone(center, radius, start_ang, sweep, 0.0, _shift_start, METER_MAX, Color(0.18, 0.55, 0.28, 0.85))
	_draw_zone(center, radius, start_ang, sweep, CRUISE_START, CRUISE_END, METER_MAX, Color(0.22, 0.62, 0.78, 0.95))
	_draw_zone(center, radius, start_ang, sweep, _shift_start, _redline, METER_MAX, Color(0.92, 0.72, 0.12, 0.95))
	_draw_zone(center, radius, start_ang, sweep, _redline, _critical, METER_MAX, Color(0.92, 0.28, 0.08, 0.95))
	_draw_zone(center, radius, start_ang, sweep, _critical, METER_MAX, METER_MAX, Color(0.55, 0.04, 0.06, 0.95))

	draw_arc(center, radius, start_ang, start_ang + sweep, 48, Color(0.75, 0.76, 0.78, 0.7), 2.2, true)

	for thousand: int in range(0, 8):
		var rpm := float(thousand) * 1000.0
		var t := clampf(rpm / METER_MAX, 0.0, 1.0)
		var ang := start_ang + sweep * t
		var dir := Vector2.from_angle(ang)
		var outer := center + dir * radius
		var inner := center + dir * (radius - (9.0 if thousand % 2 == 0 else 5.5))
		draw_line(inner, outer, Color(0.88, 0.88, 0.9, 0.9), 2.0, true)
		if thousand % 2 == 0:
			var label_pos := center + dir * (radius - 20.0) - Vector2(4.5, -4.0)
			draw_string(font, label_pos, str(thousand), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.9, 0.92, 0.9))

	var cruise_ang := start_ang + sweep * ((CRUISE_START + CRUISE_END) * 0.5 / METER_MAX)
	var cruise_dir := Vector2.from_angle(cruise_ang)
	draw_string(
		font,
		center + cruise_dir * (radius + 2.0) + Vector2(-20.0, 2.0),
		"CRUISE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		Color(0.65, 0.88, 1.0, 0.9)
	)

	var shift_ang := start_ang + sweep * clampf(_shift_start / METER_MAX, 0.0, 1.0)
	var shift_dir := Vector2.from_angle(shift_ang)
	var flash := 0.55 + 0.45 * absf(sin(_pulse))
	var shift_color := Color(1.0, 0.86, 0.2, flash)
	draw_string(
		font,
		center + shift_dir * (radius + 4.0) + Vector2(-16.0, -2.0),
		"SHIFT",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		shift_color
	)

	var crit_ang := start_ang + sweep * clampf(_critical / METER_MAX, 0.0, 1.0)
	var crit_dir := Vector2.from_angle(crit_ang)
	draw_string(
		font,
		center + crit_dir * (radius + 2.0) + Vector2(-9.0, 10.0),
		"X",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(1.0, 0.2, 0.15, 0.95)
	)

	var needle_rpm := IDLE_RPM if _blown else _rpm
	var needle_t := clampf(needle_rpm / METER_MAX, 0.0, 1.0)
	var needle_ang := start_ang + sweep * needle_t
	var needle_col := Color(0.95, 0.95, 0.97, 1.0)
	if _blown:
		needle_col = Color(0.35, 0.08, 0.08, 1.0)
	elif _rpm >= _critical:
		needle_col = Color(1.0, 0.18, 0.12, 1.0)
	elif _rpm >= _redline:
		needle_col = Color(1.0, 0.45, 0.12, 1.0)
	elif _rpm >= _shift_start:
		needle_col = Color(1.0, 0.85, 0.2, 1.0)
	draw_line(center, center + Vector2.from_angle(needle_ang) * (radius - 14.0), needle_col, 3.0, true)
	draw_circle(center, 6.5, Color(0.18, 0.18, 0.2, 1.0))
	draw_circle(center, 2.8, needle_col)

	var readout := "BLOWN" if _blown else "%d" % int(_rpm)
	var readout_size := font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(
		font,
		center + Vector2(-readout_size.x * 0.5, 21.0),
		readout,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color(1.0, 0.25, 0.2, 1.0) if _blown or _rpm >= _critical else Color(0.92, 0.92, 0.94, 0.95)
	)
	var unit_size := font.get_string_size("RPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	draw_string(font, center + Vector2(-unit_size.x * 0.5, 34.0), "RPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.72, 0.85))


func _draw_speedometer(center: Vector2, radius: float, start_ang: float, sweep: float, font: Font) -> void:
	draw_circle(center + Vector2(2.0, 3.0), radius + 7.0, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(center, radius + 5.0, Color(0.08, 0.08, 0.09, 0.88))

	var max_speed := SPEED_MAX_MPH if _imperial else SPEED_MAX_KMH
	var display_speed := _speed_kmh * KM_TO_MILES if _imperial else _speed_kmh
	var high_speed := 100.0 if _imperial else 160.0
	var red_speed := 130.0 if _imperial else 200.0

	_draw_zone(center, radius, start_ang, sweep, 0.0, high_speed, max_speed, Color(0.20, 0.52, 0.74, 0.85))
	_draw_zone(center, radius, start_ang, sweep, high_speed, red_speed, max_speed, Color(0.92, 0.72, 0.12, 0.92))
	_draw_zone(center, radius, start_ang, sweep, red_speed, max_speed, max_speed, Color(0.92, 0.28, 0.08, 0.95))

	draw_arc(center, radius, start_ang, start_ang + sweep, 48, Color(0.75, 0.76, 0.78, 0.7), 2.2, true)

	var step := 20.0
	var major_step := 40 if _imperial else 60
	var steps := int(round(max_speed / step))
	for i: int in range(0, steps + 1):
		var spd := float(i) * step
		var spd_int := roundi(spd)
		var t := clampf(spd / max_speed, 0.0, 1.0)
		var ang := start_ang + sweep * t
		var dir := Vector2.from_angle(ang)
		var is_major := (spd_int % major_step == 0)
		var outer := center + dir * radius
		var inner := center + dir * (radius - (9.0 if is_major else 5.5))
		draw_line(inner, outer, Color(0.88, 0.88, 0.9, 0.9), 2.0, true)
		if is_major:
			var txt := str(spd_int)
			var txt_sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
			var label_pos := center + dir * (radius - 20.0) + Vector2(-txt_sz.x * 0.5, 4.0)
			draw_string(font, label_pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.9, 0.92, 0.9))

	var needle_t := clampf(display_speed / max_speed, 0.0, 1.0)
	var needle_ang := start_ang + sweep * needle_t
	var needle_col := Color(0.95, 0.95, 0.97, 1.0)
	if display_speed >= red_speed:
		needle_col = Color(1.0, 0.35, 0.14, 1.0)
	elif display_speed >= high_speed:
		needle_col = Color(1.0, 0.82, 0.22, 1.0)
	draw_line(center, center + Vector2.from_angle(needle_ang) * (radius - 14.0), needle_col, 3.0, true)
	draw_circle(center, 6.5, Color(0.18, 0.18, 0.2, 1.0))
	draw_circle(center, 2.8, needle_col)

	var readout := "%d" % roundi(display_speed)
	var readout_size := font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(
		font,
		center + Vector2(-readout_size.x * 0.5, 21.0),
		readout,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color(0.92, 0.92, 0.94, 0.95)
	)
	var unit := "MPH" if _imperial else "KM/H"
	var unit_size := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	draw_string(font, center + Vector2(-unit_size.x * 0.5, 34.0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.72, 0.85))


func _draw_gear_badge(pos: Vector2, font: Font) -> void:
	var box_size := Vector2(34.0, 32.0)
	var rect := Rect2(pos - box_size * 0.5, box_size)
	draw_rect(Rect2(rect.position + Vector2(1.5, 2.0), rect.size), Color(0.0, 0.0, 0.0, 0.35), true)
	draw_rect(rect, Color(0.08, 0.085, 0.10, 0.92), true)
	draw_rect(rect, Color(0.62, 0.65, 0.70, 0.75), false, 1.5)

	var cap := "GEAR"
	var cap_sz := font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
	draw_string(font, Vector2(pos.x - cap_sz.x * 0.5, rect.position.y + 9.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.72, 0.76, 0.85))

	var g_txt := _gear_text if not _gear_text.is_empty() else "-"
	var g_col := Color(0.96, 0.84, 0.36, 0.98)
	if g_txt == "R":
		g_col = Color(1.0, 0.36, 0.28, 0.98)
	elif g_txt == "N":
		g_col = Color(0.75, 0.78, 0.84, 0.95)
	var g_sz := font.get_string_size(g_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(font, Vector2(pos.x - g_sz.x * 0.5, rect.position.y + 26.0), g_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, g_col)


func _draw_zone(
	center: Vector2,
	radius: float,
	start_ang: float,
	sweep: float,
	from_val: float,
	to_val: float,
	max_val: float,
	color: Color
) -> void:
	var a0 := start_ang + sweep * clampf(from_val / max_val, 0.0, 1.0)
	var a1 := start_ang + sweep * clampf(to_val / max_val, 0.0, 1.0)
	if a1 <= a0:
		return
	draw_arc(center, radius - 7.5, a0, a1, 28, color, 10.5, true)
