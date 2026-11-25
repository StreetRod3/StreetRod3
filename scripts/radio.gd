@tool
extends Node3D

## The garage radio's face: a sliding dial, a power button, volume and tuning knobs, and five presets.
## The same face sits on the shelf and fills the view when the set is brought forward.
## The pointer stays put. The scale moves so the tuned frequency sits under it.
## From the viewer's left the controls are power, volume, the presets, then tuning. Marks sit under them.

const _Register := preload("res://scripts/radio_register.gd")

const _DIAL_VIEW := Vector2(896, 160)
const _DIAL_SPAN := 2100.0
## Tints on the aluminium texture. Off leaves the metal as it is.
const _BUTTON_OFF := Color(1.0, 1.0, 1.0)
const _BUTTON_ON := Color(1.0, 0.84, 0.62)
const _BUTTON_SIZE := Vector3(0.018, 0.016, 0.012)
const _VOLUME_W := 0.036
const _TUNE_W := 0.064
const _ROW_Y := -0.050
## One line under the row, low enough to clear the tuning knob.
const _CAPTION_Y := -0.110
const _INK := Color(0.11, 0.06, 0.04, 1.0)
const _HALO := Color(0.97, 0.93, 0.86, 1.0)
## The dial is unshaded, so this tint is its backlight. Off, the scale stays readable and only a little dimmer.
const _SCALE_LIT := Color(1.0, 0.98, 0.9)
const _SCALE_DARK := Color(0.78, 0.74, 0.66)
const _UNIT_LIT := Color(0.9, 0.82, 0.62)
const _UNIT_DARK := Color(0.68, 0.6, 0.44)
const _KNOB_TURN := 4.8
const _WOOD_TEXTURE := preload("res://assets/locations/garage/radio-wood-texture.png")
const _ALU_TEXTURE := preload("res://assets/locations/garage/radio-alu-texture.png")

var _dial: Node2D
var _dial_mat: StandardMaterial3D
var _unit: Label3D
var _knob_spin: Node3D
var _volume_spin: Node3D
var _power_mat: StandardMaterial3D
var _buttons: Array[StaticBody3D] = []
var _button_mats: Array[StandardMaterial3D] = []
var _even_alu: Texture2D


func _ready() -> void:
	# The editor is still wiring the shelf. Build on the next frame.
	call_deferred("_rebuild")


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_clear_built()
	_hide_shelf_face()
	_build()
	if Engine.is_editor_hint():
		_apply_frequency(620.0)
		_apply_power(true)
		_apply_volume(1.0)


func _clear_built() -> void:
	var doomed: Array[Node] = []
	for child in get_children():
		doomed.append(child)
	for child in doomed:
		remove_child(child)
		child.free()
	_buttons.clear()
	_button_mats.clear()
	_dial = null
	_dial_mat = null
	_unit = null
	_knob_spin = null
	_volume_spin = null
	_power_mat = null


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_apply_frequency(GameState.radio_frequency)
	_apply_power(GameState.music_enabled)
	_apply_volume(GameState.music_volume)


## How far the scale sits, in pixels, so `freq` is centered in a window `view_w` wide.
static func dial_shift(freq: float, freq_min: float, freq_max: float, span: float, view_w: float) -> float:
	var width := maxf(freq_max - freq_min, 1.0)
	var t := clampf((freq - freq_min) / width, 0.0, 1.0)
	return view_w * 0.5 - t * span


func _hide_shelf_face() -> void:
	var radio := get_parent()
	if radio == null:
		return
	for node_name: String in ["Speaker", "Dial", "KnobLeft", "KnobRight"]:
		var node := radio.get_node_or_null(node_name) as Node3D
		if node != null:
			node.visible = false


func _build() -> void:
	var wood := _wood_material()
	var cabinet := get_parent().get_node_or_null("Body") as MeshInstance3D
	if cabinet != null:
		cabinet.material_override = wood
	_plate_material(Vector3(0.50, 0.28, 0.012), Vector3(0.0, -0.02, -0.096), wood)
	_plate(Vector3(0.42, 0.09, 0.008), Vector3(0.0, 0.042, -0.106), Color(0.05, 0.04, 0.04))
	_build_dial(Vector3(0.0, 0.042, -0.114))
	_unit_label()
	# The set faces the camera, so local +X is the viewer's left.
	var centers := _control_centers()
	var power := _build_face_button("Power", "power", Vector3(centers[0], _ROW_Y, -0.12))
	_power_mat = (power.get_node("Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	_pictogram(power, "power")
	_volume_spin = _build_knob("Volume", "volume", Vector3(centers[1], _ROW_Y, -0.122), 0.016, 0.018, 0.016)
	var button_i := 2
	for button in range(1, _Register.MEMORY_BUTTONS + 1):
		_build_memory(button, Vector3(centers[button_i], _ROW_Y, -0.12))
		button_i += 1
	_knob_spin = _build_knob("Tune", "tune", Vector3(centers[button_i], _ROW_Y, -0.124), 0.028, 0.032, 0.022)


func _build_dial(pos: Vector3) -> void:
	var vp := SubViewport.new()
	vp.name = "DialViewport"
	vp.size = Vector2i(int(_DIAL_VIEW.x), int(_DIAL_VIEW.y))
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var strip := DialStrip.new()
	strip.name = "Strip"
	strip.freq_min = _Register.FREQ_MIN
	strip.freq_max = _Register.FREQ_MAX
	strip.span = _DIAL_SPAN
	strip.strip_h = _DIAL_VIEW.y
	vp.add_child(strip)
	_dial = strip
	var needle := DialNeedle.new()
	needle.view = _DIAL_VIEW
	vp.add_child(needle)
	var quad := MeshInstance3D.new()
	quad.name = "Dial"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.40, 0.072)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = vp.get_texture()
	mat.albedo_color = _SCALE_LIT
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dial_mat = mat
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.mesh = mesh
	quad.material_override = mat
	quad.position = pos
	quad.rotation.y = PI
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)


func _unit_label() -> void:
	var lab := Label3D.new()
	lab.text = "Hz"
	lab.position = Vector3(-0.21, 0.096, -0.108)
	lab.font_size = 32
	lab.pixel_size = 0.00055
	lab.modulate = _UNIT_LIT
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unit = lab
	lab.shaded = false
	# Faces +Z by default; the set's front is -Z, so turn the word around.
	lab.rotation.y = PI
	add_child(lab)


## Left to right for the viewer: power, volume, the five presets, tuning.
func _control_centers() -> Array[float]:
	var button_w := _BUTTON_SIZE.x
	var gap := 0.016
	var preset_gap := 0.002
	var widths: Array[float] = [button_w, _VOLUME_W]
	for _button in _Register.MEMORY_BUTTONS:
		widths.append(button_w)
	widths.append(_TUNE_W)
	var span := 0.0
	for w in widths:
		span += w
	span += gap * 3.0 + preset_gap * float(_Register.MEMORY_BUTTONS - 1)
	var x := span * 0.5
	var centers: Array[float] = []
	for i in widths.size():
		x -= widths[i] * 0.5
		centers.append(x)
		x -= widths[i] * 0.5
		if i == widths.size() - 1:
			break
		var between_presets := i >= 2 and i < 1 + _Register.MEMORY_BUTTONS
		x -= preset_gap if between_presets else gap
	return centers


func _build_face_button(node_name: String, kind: String, pos: Vector3) -> StaticBody3D:
	var body := _control(node_name, kind, pos, _BUTTON_SIZE, _BUTTON_OFF)
	var mesh := body.get_node("Mesh") as MeshInstance3D
	mesh.material_override = _button_material()
	return body


func _build_knob(node_name: String, kind: String, pos: Vector3, top: float, bottom: float, depth: float) -> Node3D:
	var span := bottom * 2.2
	var body := _control(node_name, kind, pos, Vector3(span, span, 0.02), Color(0.12, 0.12, 0.13))
	var plate := body.get_node("Mesh") as MeshInstance3D
	plate.visible = false
	var spin := Node3D.new()
	spin.name = "Spin"
	body.add_child(spin)
	var knob := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = depth
	mesh.radial_segments = 32
	var mat := _aluminium_material(false)
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	knob.mesh = mesh
	knob.material_override = mat
	knob.rotation.x = PI * 0.5
	knob.position = Vector3(0.0, 0.0, -depth * 0.35)
	knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(knob)
	var mark := MeshInstance3D.new()
	var tick := BoxMesh.new()
	tick.size = Vector3(0.004, top * 0.55, 0.003)
	var tick_mat := StandardMaterial3D.new()
	tick_mat.albedo_color = Color(0.12, 0.12, 0.13)
	mark.mesh = tick
	mark.material_override = tick_mat
	mark.position = Vector3(0.0, top * 0.55, -depth * 0.55)
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(mark)
	_pictogram(body, "volume" if kind == "volume" else "frequency")
	return spin


func _build_memory(button: int, pos: Vector3) -> void:
	var body := _build_face_button("Memory%d" % button, str(button), pos)
	var mat := (body.get_node("Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	_buttons.append(body)
	_button_mats.append(mat)
	_number(body, str(button))


func _number(body: Node3D, text: String) -> void:
	var lab := Label3D.new()
	lab.name = "Caption"
	lab.text = text
	lab.position = Vector3(0.0, _CAPTION_Y - _ROW_Y, -0.006)
	lab.font_size = 64
	lab.pixel_size = 0.00022
	lab.modulate = _INK
	lab.outline_modulate = _HALO
	lab.outline_size = 6
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.shaded = false
	lab.rotation.y = PI
	body.add_child(lab)


func _pictogram(body: Node3D, kind: String) -> void:
	var quad := MeshInstance3D.new()
	quad.name = "Mark"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.016, 0.016)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _icon(kind)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.mesh = mesh
	quad.material_override = mat
	quad.position = Vector3(0.0, _CAPTION_Y - _ROW_Y, -0.006)
	quad.rotation.y = PI
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(quad)


func _icon(kind: String) -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"power":
			_draw_power(img)
		"volume":
			_draw_volume(img)
		_:
			_draw_frequency(img)
	return ImageTexture.create_from_image(img)


func _draw_power(img: Image) -> void:
	var c := Vector2(32, 36)
	var radius := 15.0
	var gap := 0.62
	var pts := PackedVector2Array()
	var angle := -PI * 0.5 + gap
	var end := -PI * 0.5 - gap + TAU
	while angle <= end:
		pts.append(c + Vector2(cos(angle), sin(angle)) * radius)
		angle += 0.18
	_stroke(img, pts, 3.5)
	_stroke(img, PackedVector2Array([Vector2(32, 12), Vector2(32, 36)]), 3.5)


func _draw_volume(img: Image) -> void:
	_stroke(img, PackedVector2Array([
		Vector2(10, 24), Vector2(20, 24), Vector2(20, 40), Vector2(10, 40), Vector2(10, 24),
	]), 3.2)
	_stroke(img, PackedVector2Array([
		Vector2(20, 26), Vector2(32, 16), Vector2(32, 48), Vector2(20, 38),
	]), 3.2)
	_arc(img, Vector2(34, 32), 10.0, -0.9, 0.9)
	_arc(img, Vector2(34, 32), 16.0, -0.9, 0.9)


func _draw_frequency(img: Image) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var t := float(i) / 48.0
		pts.append(Vector2(8.0 + t * 48.0, 32.0 + sin(t * TAU * 2.0) * 12.0))
	_stroke(img, pts, 3.2)


func _arc(img: Image, center: Vector2, radius: float, start: float, end: float) -> void:
	var pts := PackedVector2Array()
	var angle := start
	while angle <= end:
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
		angle += 0.16
	_stroke(img, pts, 3.0)


func _stroke(img: Image, pts: PackedVector2Array, width: float) -> void:
	if pts.size() < 2:
		return
	for i in pts.size() - 1:
		_thick_line(img, pts[i], pts[i + 1], width + 4.0, _HALO)
	for i in pts.size() - 1:
		_thick_line(img, pts[i], pts[i + 1], width, _INK)


func _thick_line(img: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var steps := int(a.distance_to(b) * 2.0) + 1
	var radius := width * 0.5
	var reach := int(ceil(radius))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		for y in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				if Vector2(x, y).length() > radius:
					continue
				var px := int(round(p.x)) + x
				var py := int(round(p.y)) + y
				if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
					continue
				img.set_pixel(px, py, color)


func _apply_frequency(freq: float) -> void:
	if _dial != null:
		_dial.position.x = dial_shift(freq, _Register.FREQ_MIN, _Register.FREQ_MAX, _DIAL_SPAN, _DIAL_VIEW.x)
	if _knob_spin != null:
		var span := maxf(_Register.FREQ_MAX - _Register.FREQ_MIN, 1.0)
		var t := clampf((freq - _Register.FREQ_MIN) / span, 0.0, 1.0)
		# The face points at the camera, so positive Z is clockwise: a rightward drag turns the knob that way.
		_knob_spin.rotation.z = t * _KNOB_TURN
	for i in _button_mats.size():
		var tuned := i == 0
		if not Engine.is_editor_hint():
			var saved := GameState.radio_memory_frequency(i + 1)
			tuned = saved >= 0.0 and absf(saved - freq) <= _Register.TUNE_SLACK
		_button_mats[i].albedo_color = _BUTTON_ON if tuned else _BUTTON_OFF


func _apply_volume(volume: float) -> void:
	if _volume_spin == null:
		return
	_volume_spin.rotation.z = clampf(volume, 0.0, 1.0) * _KNOB_TURN


func _apply_power(on: bool) -> void:
	if _power_mat != null:
		_power_mat.albedo_color = _BUTTON_ON if on else _BUTTON_OFF
	if _dial_mat != null:
		_dial_mat.albedo_color = _SCALE_LIT if on else _SCALE_DARK
	if _unit != null:
		_unit.modulate = _UNIT_LIT if on else _UNIT_DARK


func _plate(size: Vector3, pos: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.62
	_plate_material(size, pos, mat)


func _plate_material(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _wood_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _WOOD_TEXTURE
	mat.roughness = 0.72
	mat.metallic = 0.0
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(3.0, 3.0, 3.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat


## The memory buttons are small, so the full brush photo turns into a blocky grid.
## A softened copy keeps the aluminium colour and reads as one solid piece.
func _button_material() -> StandardMaterial3D:
	var mat := _aluminium_material(false)
	mat.albedo_texture = _even_aluminium_texture()
	mat.uv1_triplanar = false
	mat.uv1_scale = Vector3.ONE
	return mat


func _even_aluminium_texture() -> Texture2D:
	if _even_alu != null:
		return _even_alu
	var src := Image.load_from_file(ProjectSettings.globalize_path("res://assets/locations/garage/radio-alu-texture.png"))
	src.resize(16, 16, Image.INTERPOLATE_LANCZOS)
	_even_alu = ImageTexture.create_from_image(src)
	return _even_alu


func _aluminium_material(triplanar: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _ALU_TEXTURE
	mat.albedo_color = _BUTTON_OFF
	mat.metallic = 0.18
	mat.roughness = 0.46
	mat.uv1_triplanar = triplanar
	mat.uv1_scale = Vector3.ONE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat


func _control(node_name: String, kind: String, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.set_meta(&"radio_control", kind)
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.48
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.name = "Hit"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


class DialStrip extends Node2D:
	var freq_min := 540.0
	var freq_max := 1600.0
	var span := 2100.0
	var strip_h := 160.0

	func _ready() -> void:
		var marks: Array[float] = [540, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600]
		for freq: float in marks:
			var lab := Label.new()
			lab.text = str(int(freq))
			lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lab.add_theme_font_size_override(&"font_size", 32)
			lab.add_theme_color_override(&"font_color", Color(0.16, 0.09, 0.05))
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lab.size = Vector2(110, 40)
			lab.position = Vector2(_x(freq) - 55.0, 14.0)
			add_child(lab)

	func _draw() -> void:
		draw_rect(Rect2(-800.0, 0.0, span + 1600.0, strip_h), Color(0.94, 0.87, 0.66))
		draw_line(Vector2(0.0, strip_h - 8.0), Vector2(span, strip_h - 8.0), Color(0.16, 0.09, 0.05), 2.0)
		var freq := freq_min
		while freq <= freq_max + 0.01:
			var x := _x(freq)
			var major := int(round(freq)) % 100 == 0 or is_equal_approx(freq, freq_min) or is_equal_approx(freq, freq_max)
			var h := 52.0 if major else 24.0
			draw_line(Vector2(x, strip_h - 8.0), Vector2(x, strip_h - 8.0 - h), Color(0.16, 0.09, 0.05), 3.0 if major else 1.5)
			freq += 20.0

	func _x(freq: float) -> float:
		return (freq - freq_min) / maxf(freq_max - freq_min, 1.0) * span


class DialNeedle extends Node2D:
	var view := Vector2(640, 160)

	func _draw() -> void:
		var cx := view.x * 0.5
		var red := Color(0.78, 0.12, 0.1)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 8.0, 2.0),
			Vector2(cx + 8.0, 2.0),
			Vector2(cx, 22.0),
		]), red)
		draw_line(Vector2(cx, 18.0), Vector2(cx, view.y - 2.0), red, 2.0)
