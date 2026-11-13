extends Control

## Compact 3D top-down animated gear-shift lever window shown on the right side
## of the dashboard for ~2.5 seconds whenever the gear changes in cabin view.

const GEAR_NEUTRAL := -1
const GEAR_REVERSE := -2

const ANIM_DURATION := 0.34
const HOLD_DURATION := 2.15
const FADE_DURATION := 0.35

const _PIVOT_Y := -0.075
const _LEVER_LEN := 0.145

var _car: Node = null
var _from_gear: int = 0
var _to_gear: int = 0
var _gear_count: int = 4
var _automatic: bool = false
var _anim_t: float = 1.0
var _visible_timer: float = 0.0
var _active: bool = false

var _viewport: SubViewport = null
var _scene_root: Node3D = null
var _gate_root: Node3D = null
var _lever_pivot: Node3D = null
var _boot_rings: Array[MeshInstance3D] = []
var _slot_markers: Dictionary[int, Label3D] = {}
var _slot_leds: Dictionary[int, MeshInstance3D] = {}
var _header_label: Label = null
var _built_mode: int = -1
var _built_gears: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()


static func attach(layer: Node, car: Node) -> Control:
	var popup := new()
	popup.name = "GearShiftPopup"
	popup.anchor_left = 1.0
	popup.anchor_right = 1.0
	popup.anchor_top = 1.0
	popup.anchor_bottom = 1.0
	popup.offset_left = -352.0
	popup.offset_top = -188.0
	popup.offset_right = -192.0
	popup.offset_bottom = -28.0
	popup.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	popup.grow_vertical = Control.GROW_DIRECTION_BEGIN
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.pivot_offset = Vector2(160.0, 160.0)
	var hud_scale := clampf(GameState.hud_size, 0.6, 1.0)
	popup.scale = Vector2(hud_scale, hud_scale)
	layer.add_child(popup)
	if car != null:
		popup.call(&"bind_car", car)
	return popup


func bind_car(car: Node) -> void:
	_car = car
	if _car == null:
		return
	var cb := Callable(self, &"_on_gear_changed")
	if _car.has_signal(&"gear_changed") and not _car.is_connected(&"gear_changed", cb):
		_car.connect(&"gear_changed", cb)


func _build_ui() -> void:
	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.085, 0.10, 0.94)
	style.border_color = Color(0.62, 0.66, 0.72, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 5
	style.shadow_offset = Vector2(2.0, 3.0)
	frame.add_theme_stylebox_override(&"panel", style)
	add_child(frame)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 6)
	margin.add_theme_constant_override(&"margin_top", 22)
	margin.add_theme_constant_override(&"margin_right", 6)
	margin.add_theme_constant_override(&"margin_bottom", 6)
	frame.add_child(margin)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(svc)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.size = Vector2i(256, 220)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_viewport)

	_scene_root = Node3D.new()
	_scene_root.name = "Shifter3DRoot"
	_viewport.add_child(_scene_root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.055, 0.065, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.38, 1.0)
	env.ambient_light_energy = 0.85
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_scene_root.add_child(world_env)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-58.0, 32.0, 0.0)
	key_light.light_energy = 1.65
	key_light.light_color = Color(1.0, 0.97, 0.92)
	_scene_root.add_child(key_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-42.0, -145.0, 0.0)
	rim_light.light_energy = 0.7
	rim_light.light_color = Color(0.75, 0.85, 1.0)
	_scene_root.add_child(rim_light)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.25, 0.068)
	cam.rotation_degrees = Vector3(-74.0, 0.0, 0.0)
	cam.fov = 38.0
	cam.near = 0.02
	cam.far = 5.0
	cam.current = true
	_scene_root.add_child(cam)

	_header_label = Label.new()
	_header_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_header_label.offset_top = 3.0
	_header_label.offset_bottom = 21.0
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_label.add_theme_font_size_override(&"font_size", 12)
	_header_label.add_theme_color_override(&"font_color", Color(0.96, 0.84, 0.36, 0.98))
	frame.add_child(_header_label)


func _on_gear_changed(from_gear: int, to_gear: int) -> void:
	if _car == null or not is_instance_valid(_car):
		return
	if not _car.has_method(&"is_cockpit_camera") or not bool(_car.call(&"is_cockpit_camera")):
		return
	if _car.has_method(&"get_gear_count"):
		_gear_count = maxi(int(_car.call(&"get_gear_count")), 1)
	if _car.has_method(&"is_automatic_gearbox"):
		_automatic = bool(_car.call(&"is_automatic_gearbox"))
	if _automatic:
		var norm_from := 0 if from_gear >= 0 else from_gear
		var norm_to := 0 if to_gear >= 0 else to_gear
		if norm_from == norm_to:
			return
		_from_gear = norm_from
		_to_gear = norm_to
	else:
		_from_gear = from_gear
		_to_gear = to_gear
	_ensure_shifter_rig()
	_update_header_and_badges()
	_anim_t = 0.0
	_visible_timer = HOLD_DURATION + FADE_DURATION
	_active = true
	modulate.a = 1.0
	visible = true
	_pose_lever()


func _process(delta: float) -> void:
	if not _active:
		return
	if _car == null or not is_instance_valid(_car) or not _car.has_method(&"is_cockpit_camera") or not bool(_car.call(&"is_cockpit_camera")):
		_hide_now()
		return
	if _anim_t < 1.0:
		_anim_t = minf(1.0, _anim_t + delta / ANIM_DURATION)
	_visible_timer -= delta
	if _visible_timer <= 0.0:
		_hide_now()
		return
	if _visible_timer < FADE_DURATION:
		modulate.a = clampf(_visible_timer / FADE_DURATION, 0.0, 1.0)
	else:
		modulate.a = 1.0
	_pose_lever()


func _hide_now() -> void:
	_active = false
	_visible_timer = 0.0
	visible = false


func _gear_text(gear: int) -> String:
	if gear == GEAR_REVERSE:
		return "R"
	if gear == GEAR_NEUTRAL:
		return "N"
	if _automatic:
		return "D"
	return str(gear + 1)


func _ensure_shifter_rig() -> void:
	var mode := 1 if _automatic else 0
	if _gate_root != null and _built_mode == mode and _built_gears == _gear_count:
		return
	_built_mode = mode
	_built_gears = _gear_count
	if _gate_root != null:
		_gate_root.queue_free()
	_boot_rings.clear()
	_slot_markers.clear()
	_slot_leds.clear()

	_gate_root = Node3D.new()
	_gate_root.name = "GateRig"
	_scene_root.add_child(_gate_root)

	var console_mat := _mat(Color(0.08, 0.085, 0.10), 0.72, 0.08)
	var bezel_mat := _mat(Color(0.68, 0.72, 0.78), 0.22, 0.88)
	var plate_mat := _mat(Color(0.24, 0.26, 0.30), 0.32, 0.72)
	var groove_mat := _mat(Color(0.018, 0.02, 0.024), 0.92, 0.05)

	# Console base pad.
	_add_box(_gate_root, Vector3(0.20, 0.025, 0.18), Vector3(0.0, -0.02, 0.0), console_mat)
	# Chrome outer bezel strips.
	_add_box(_gate_root, Vector3(0.165, 0.008, 0.010), Vector3(0.0, 0.001, -0.072), bezel_mat)
	_add_box(_gate_root, Vector3(0.165, 0.008, 0.010), Vector3(0.0, 0.001, 0.072), bezel_mat)
	_add_box(_gate_root, Vector3(0.010, 0.008, 0.154), Vector3(-0.078, 0.001, 0.0), bezel_mat)
	_add_box(_gate_root, Vector3(0.010, 0.008, 0.154), Vector3(0.078, 0.001, 0.0), bezel_mat)
	# Recessed gate plate.
	_add_box(_gate_root, Vector3(0.148, 0.005, 0.136), Vector3(0.0, -0.002, 0.0), plate_mat)

	if _automatic:
		_build_automatic_gate(groove_mat)
	else:
		_build_manual_gate(groove_mat)

	_build_lever_3d()


func _build_manual_gate(groove_mat: StandardMaterial3D) -> void:
	var slots := _manual_slots_3d()
	var min_x := 1.0
	var max_x := -1.0
	for gear_id: int in slots:
		if gear_id == GEAR_NEUTRAL:
			continue
		var p: Vector2 = slots[gear_id]
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)

	# Neutral horizontal slot.
	_add_box(_gate_root, Vector3((max_x - min_x) + 0.014, 0.004, 0.012), Vector3((min_x + max_x) * 0.5, 0.0012, 0.0), groove_mat)

	# Vertical gear slots + labels + indicator LEDs.
	for gear_id: int in slots:
		if gear_id == GEAR_NEUTRAL:
			continue
		var p: Vector2 = slots[gear_id]
		_add_box(_gate_root, Vector3(0.012, 0.004, absf(p.y) + 0.012), Vector3(p.x, 0.0012, p.y * 0.5), groove_mat)

		var led := _add_cyl(_gate_root, 0.007, 0.003, Vector3(p.x, 0.0015, p.y), _mat(Color(0.18, 0.20, 0.24), 0.4, 0.2))
		_slot_leds[gear_id] = led

		var lbl := Label3D.new()
		lbl.text = _gear_text(gear_id)
		lbl.font_size = 36
		lbl.pixel_size = 0.00055
		lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		var z_off := -0.016 if p.y < 0.0 else 0.016
		lbl.position = Vector3(p.x, 0.004, p.y + z_off)
		lbl.modulate = Color(0.82, 0.85, 0.90)
		_gate_root.add_child(lbl)
		_slot_markers[gear_id] = lbl


func _build_automatic_gate(groove_mat: StandardMaterial3D) -> void:
	var slots := _auto_slots_3d()
	var rail_x := -0.016
	_add_box(_gate_root, Vector3(0.014, 0.004, 0.114), Vector3(rail_x, 0.0012, 0.0), groove_mat)

	for gear_id: int in slots:
		var p: Vector2 = slots[gear_id]
		_add_box(_gate_root, Vector3(0.024, 0.004, 0.003), Vector3(rail_x, 0.0016, p.y), groove_mat)
		var led := _add_cyl(_gate_root, 0.006, 0.003, Vector3(rail_x + 0.017, 0.0018, p.y), _mat(Color(0.18, 0.20, 0.24), 0.4, 0.2))
		_slot_leds[gear_id] = led

		var lbl := Label3D.new()
		lbl.text = _gear_text(gear_id)
		lbl.font_size = 34
		lbl.pixel_size = 0.00052
		lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		lbl.position = Vector3(rail_x + 0.036, 0.004, p.y)
		lbl.modulate = Color(0.82, 0.85, 0.90)
		_gate_root.add_child(lbl)
		_slot_markers[gear_id] = lbl


func _build_lever_3d() -> void:
	var boot_mat := _mat(Color(0.06, 0.06, 0.07), 0.78, 0.05)
	var chrome_mat := _mat(Color(0.88, 0.90, 0.94), 0.12, 0.95)
	var knob_mat := _mat(Color(0.11, 0.12, 0.14), 0.16, 0.25)
	var cap_mat := _mat(Color(0.82, 0.70, 0.26), 0.22, 0.75)

	# Pleated rubber/leather boot rings above the base.
	var radii: Array[float] = [0.025, 0.019, 0.013]
	for i: int in radii.size():
		var ring := _add_cyl(_gate_root, radii[i], 0.007, Vector3(0.0, 0.005 + float(i) * 0.006, 0.0), boot_mat)
		_boot_rings.append(ring)

	_lever_pivot = Node3D.new()
	_lever_pivot.name = "LeverPivot"
	_lever_pivot.position = Vector3(0.0, _PIVOT_Y, 0.0)
	_gate_root.add_child(_lever_pivot)

	# Chrome shaft extending along +Y of LeverPivot.
	_add_cyl(_lever_pivot, 0.0045, _LEVER_LEN, Vector3(0.0, _LEVER_LEN * 0.5, 0.0), chrome_mat)

	# Classic glossy shift knob at the top of the lever.
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.019
	knob_mesh.height = 0.036
	knob_mesh.radial_segments = 24
	knob_mesh.rings = 14
	var knob := MeshInstance3D.new()
	knob.mesh = knob_mesh
	knob.material_override = knob_mat
	knob.position = Vector3(0.0, _LEVER_LEN + 0.008, 0.0)
	_lever_pivot.add_child(knob)

	# Brass/gold emblem medallion on top of the knob.
	_add_cyl(_lever_pivot, 0.0095, 0.0025, Vector3(0.0, _LEVER_LEN + 0.0255, 0.0), cap_mat)


func _update_header_and_badges() -> void:
	if _header_label != null:
		_header_label.text = "%s  ->  %s" % [_gear_text(_from_gear), _gear_text(_to_gear)]
	for gear_id: int in _slot_leds:
		var led: MeshInstance3D = _slot_leds[gear_id]
		var mat := led.material_override as StandardMaterial3D
		if mat == null:
			continue
		if gear_id == _to_gear:
			mat.albedo_color = Color(0.28, 0.92, 0.42)
			mat.emission_enabled = true
			mat.emission = Color(0.24, 0.90, 0.38)
			mat.emission_energy_multiplier = 1.4
		elif gear_id == _from_gear:
			mat.albedo_color = Color(0.62, 0.50, 0.22)
			mat.emission_enabled = true
			mat.emission = Color(0.55, 0.42, 0.15)
			mat.emission_energy_multiplier = 0.5
		else:
			mat.albedo_color = Color(0.18, 0.20, 0.24)
			mat.emission_enabled = false
	for gear_id: int in _slot_markers:
		var lbl: Label3D = _slot_markers[gear_id]
		if gear_id == _to_gear:
			lbl.modulate = Color(0.45, 1.0, 0.58)
		elif gear_id == _from_gear:
			lbl.modulate = Color(0.95, 0.80, 0.40)
		else:
			lbl.modulate = Color(0.75, 0.78, 0.84)


func _pose_lever() -> void:
	if _lever_pivot == null:
		return
	var target_xz := _auto_lever_xz() if _automatic else _manual_lever_xz()
	var dir := Vector3(target_xz.x, -_PIVOT_Y + 0.025, target_xz.y).normalized()
	var up := Vector3.UP
	var rot_axis := up.cross(dir)
	var basis := Basis.IDENTITY
	if rot_axis.length_squared() > 0.000001:
		var angle := acos(clampf(up.dot(dir), -1.0, 1.0))
		basis = Basis(rot_axis.normalized(), angle)
	_lever_pivot.transform = Transform3D(basis, Vector3(0.0, _PIVOT_Y, 0.0))

	for i: int in _boot_rings.size():
		var ring: MeshInstance3D = _boot_rings[i]
		var frac := float(i + 1) / float(_boot_rings.size() + 1)
		ring.position.x = target_xz.x * frac * 0.65
		ring.position.z = target_xz.y * frac * 0.65


func _manual_slots_3d() -> Dictionary[int, Vector2]:
	var top_z := -0.042
	var bot_z := 0.042
	var out: Dictionary[int, Vector2] = {}
	out[GEAR_NEUTRAL] = Vector2(0.0, 0.0)
	if _gear_count <= 3:
		var x0 := -0.028
		var x1 := 0.028
		out[GEAR_REVERSE] = Vector2(x0, top_z)
		out[0] = Vector2(x0, bot_z)
		if _gear_count >= 2:
			out[1] = Vector2(x1, top_z)
		if _gear_count >= 3:
			out[2] = Vector2(x1, bot_z)
		return out
	var xs: Array[float] = [-0.044, 0.0, 0.044]
	out[0] = Vector2(xs[0], top_z)
	out[1] = Vector2(xs[0], bot_z)
	out[2] = Vector2(xs[1], top_z)
	out[3] = Vector2(xs[1], bot_z)
	if _gear_count >= 5:
		out[4] = Vector2(xs[2], top_z)
	out[GEAR_REVERSE] = Vector2(xs[2], bot_z)
	return out


func _auto_slots_3d() -> Dictionary[int, Vector2]:
	var gears: Array[int] = [GEAR_REVERSE, GEAR_NEUTRAL, 0]
	var out: Dictionary[int, Vector2] = {}
	var count := maxi(gears.size() - 1, 1)
	for idx: int in gears.size():
		var g: int = gears[idx]
		var z := lerpf(-0.042, 0.042, float(idx) / float(count))
		out[g] = Vector2(-0.016, z)
	return out


func _manual_lever_xz() -> Vector2:
	var slots := _manual_slots_3d()
	var p0: Vector2 = slots.get(_from_gear, Vector2.ZERO)
	var p1: Vector2 = slots.get(_to_gear, Vector2.ZERO)
	var n0 := Vector2(p0.x, 0.0)
	var n1 := Vector2(p1.x, 0.0)
	var t := clampf(_anim_t, 0.0, 1.0)
	if _from_gear == GEAR_NEUTRAL and _to_gear == GEAR_NEUTRAL:
		return Vector2.ZERO
	if _from_gear == GEAR_NEUTRAL:
		if t < 0.45:
			return p0.lerp(n1, _ease_out_cubic(t / 0.45))
		return n1.lerp(p1, _ease_out_back((t - 0.45) / 0.55))
	if _to_gear == GEAR_NEUTRAL:
		if t < 0.55:
			return p0.lerp(n0, _ease_out_cubic(t / 0.55))
		return n0.lerp(p1, _ease_out_cubic((t - 0.55) / 0.45))
	if is_equal_approx(p0.x, p1.x):
		return p0.lerp(p1, _ease_out_back(t))
	if t < 0.34:
		return p0.lerp(n0, _ease_out_cubic(t / 0.34))
	if t < 0.66:
		return n0.lerp(n1, _ease_in_out_cubic((t - 0.34) / 0.32))
	return n1.lerp(p1, _ease_out_back((t - 0.66) / 0.34))


func _auto_lever_xz() -> Vector2:
	var slots := _auto_slots_3d()
	var p0: Vector2 = slots.get(_from_gear, Vector2(-0.016, -0.048))
	var p1: Vector2 = slots.get(_to_gear, Vector2(-0.016, -0.048))
	return p0.lerp(p1, _ease_out_back(clampf(_anim_t, 0.0, 1.0)))


func _mat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _add_box(parent: Node3D, box_size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _ease_out_cubic(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u


func _ease_in_out_cubic(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	if x < 0.5:
		return 4.0 * x * x * x
	return 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5


func _ease_out_back(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	var c1 := 1.15
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
