extends Node3D

## Setting the timing with a timing light, as in Street Rod 2. The engine idles; the
## light, clipped to the number one plug wire, flashes each time that plug fires, and
## the flash freezes the balancer with its mark against the timing tab. Advance and
## Retard turn the distributor a step at a time. As in Street Rod 2, the mark has a
## pointer to line up with (red, on the tab at the sticker's timing), and the idle is
## smooth and fastest only there; away from it the idle drops, lopes and misses, and the
## mark wanders from flash to flash.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _EngineAssembly := preload("res://scripts/engine_assembly.gd")
const _EngineSound := preload("res://scripts/engine_sound.gd")
const _Hood := preload("res://scripts/hood.gd")

const CRANK_Y := 0.55
## How long each flash lasts, in seconds.
const FLASH_TIME := 0.03
## The mark wanders this many degrees of timing for each step off the sweet spot.
const WANDER_PER_STEP := 0.9
## The mark glows this long after each flash, in seconds, as it hangs in your eye.
const AFTERGLOW := 0.12

const _CREAM := Color(0.95, 0.9, 0.78, 1)

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $UI/Root

var _engine: Node3D
var _light_gun: Node3D
var _lens_mat: StandardMaterial3D
var _mark_mats: Array[StandardMaterial3D] = []
var _strobe: SpotLight3D
var _env: Environment
var _sound: AudioStreamPlayer
var _click: AudioStreamPlayer
var _nav = _MenuNav.new()
var _since_flash: float = 0.0
var _flashing: bool = false
var _rng := RandomNumberGenerator.new()

var _hint: Label
var _advance_btn: Button
var _retard_btn: Button
var _done_btn: Button


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	if not GameState.has_active_car() or not GameState.engine_runs():
		get_tree().change_scene_to_file.call_deferred(GameState.SCENE_HOOD)
		return
	_rng.randomize()
	_build_world()
	_engine = _EngineAssembly.new()
	_engine.name = "Engine"
	_engine.position = Vector3(0.0, CRANK_Y - _EngineAssembly.CRANK_Z * _EngineAssembly.ENGINE_SCALE, 0.0)
	add_child(_engine)
	_engine.build()
	_place_camera()
	_build_pointer()
	_find_mark()
	_build_light_gun()
	_build_ui()
	_build_sound()
	_refresh()


func _exit_tree() -> void:
	if _sound != null and _sound.playing:
		_sound.stop()
	GameState.set_music_dimmed(false)


func _process(delta: float) -> void:
	if _engine == null or _engine.balancer == null:
		return
	var rpm: float = _EngineSound.tune_rpm(GameState.engine_tune, GameState.engine_sweet_tune())
	# Number one fires every other turn of the crank. Each flash catches the mark at the
	# timing, so it stands still there; the strobe is the only light that shows it.
	var period := 120.0 / rpm
	_since_flash += delta
	if _since_flash >= period:
		_since_flash = fmod(_since_flash, period)
		_flashing = true
		var off := float(absi(GameState.engine_tune - GameState.engine_sweet_tune()))
		var wander := _rng.randf_range(-1.0, 1.0) * off * WANDER_PER_STEP
		_engine.balancer.rotation.x = _EngineAssembly.mark_angle(float(GameState.timing_degrees()) + wander)
	elif _flashing and _since_flash > FLASH_TIME:
		_flashing = false
	_strobe.light_energy = 5.0 if _flashing else 0.0
	_lens_mat.emission_energy_multiplier = 6.0 if _flashing else 0.0
	var glow := 3.0 * exp(-_since_flash / AFTERGLOW)
	for mat in _mark_mats:
		mat.emission_energy_multiplier = glow


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	if _nav.handle_event(self, key):
		get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_UP, KEY_PAGEUP, KEY_KP_ADD, KEY_EQUAL:
			_step(1)
		KEY_DOWN, KEY_PAGEDOWN, KEY_KP_SUBTRACT, KEY_MINUS:
			_step(-1)
		KEY_ESCAPE:
			if key.echo:
				return
			# Mark the key first. Leaving drops this scene, and the viewport is gone after that.
			get_viewport().set_input_as_handled()
			_on_done_pressed()
			return
		_:
			return
	get_viewport().set_input_as_handled()


func _step(delta: int) -> void:
	var before := GameState.engine_tune
	GameState.set_engine_tune(before + delta)
	if GameState.engine_tune != before:
		_click.play()
	_refresh()


func _refresh() -> void:
	var tune := GameState.engine_tune
	_advance_btn.disabled = tune >= GameState.ENGINE_TUNE_MAX
	_retard_btn.disabled = tune <= GameState.ENGINE_TUNE_MIN
	if _sound != null:
		_sound.call(&"set_tune", tune, GameState.engine_sweet_tune())
	_hint.text = "Line the mark up with the red pointer. It idles smooth when it's right."


func _on_done_pressed() -> void:
	_nav.clear()
	get_tree().change_scene_to_file(GameState.SCENE_HOOD)


# --- Scene -------------------------------------------------------------------------------


func _build_world() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.018, 0.016)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.46, 0.42)
	_env.ambient_light_energy = 0.4
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_Hood._shop_reflections(_env)
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)
	# Dim shop light from above the fender.
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-0.4, 1.5, 0.6)
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = 0.8
	lamp.omni_range = 3.0
	add_child(lamp)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.065, 0.06)
	dark.roughness = 0.85
	var paint := StandardMaterial3D.new()
	paint.albedo_color = GameState.car_color
	paint.metallic = 0.3
	paint.roughness = 0.4
	# Frame rail and inner fender either side, the fender top on the near side.
	for side in [-1.0, 1.0]:
		_box(Vector3(2.0, 0.12, 0.08), Vector3(0.0, 0.32, 0.46 * side), dark)
		_box(Vector3(1.6, 0.5, 0.03), Vector3(-0.1, 0.62, 0.66 * side), dark)
	_box(Vector3(1.9, 0.05, 0.24), Vector3(-0.15, 0.95, 0.8), paint)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


## The point on the timing tab where the marks are, in meters.
func _tab_point() -> Vector3:
	var a := _EngineAssembly.mark_angle(10.0)
	var r := _EngineAssembly.BALANCER_R
	var local := Vector3(_EngineAssembly.COVER_X - 0.2, -r * sin(a), _EngineAssembly.CRANK_Z + r * cos(a))
	return _engine.frame.global_transform * local


## Close in on the balancer from the front, a little to the side of the tab, the way
## you would crouch at the grille with the light.
func _place_camera() -> void:
	var tab := _tab_point()
	var crank: Vector3 = _engine.frame.global_transform * Vector3(_EngineAssembly.COVER_X - 0.2, 0.0, _EngineAssembly.CRANK_Z)
	var look := crank.lerp(tab, 0.85)
	_camera.fov = 40.0
	_camera.global_position = look + Vector3(-0.3, 0.02, 0.09)
	_camera.look_at(look, Vector3.UP)


## The red pointer on the tab at the timing the sticker gives, past the ticks and the
## numbers, lit so it shows between flashes: the line the mark is set against.
func _build_pointer() -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.08, 0.05)
	red.emission_enabled = true
	red.emission = Color(1.0, 0.12, 0.06)
	red.emission_energy_multiplier = 1.6
	var a := _EngineAssembly.mark_angle(float(GameState.timing_degrees(GameState.engine_sweet_tune())))
	var x := _EngineAssembly.COVER_X - 0.215
	var pointer := Node3D.new()
	pointer.name = "Pointer"
	pointer.position = Vector3(x, 0.0, _EngineAssembly.CRANK_Z)
	pointer.rotation.x = a
	_engine.frame.add_child(pointer)
	var r := _EngineAssembly.BALANCER_R
	# A long bar from the rim out past the numbers, and a head on its end.
	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(0.012, 0.022, 0.3)
	bar.mesh = bar_mesh
	bar.material_override = red
	bar.position = Vector3(0.0, 0.0, r + 0.17)
	pointer.add_child(bar)
	var head := MeshInstance3D.new()
	var head_mesh := PrismMesh.new()
	head_mesh.size = Vector3(0.09, 0.08, 0.012)
	head.mesh = head_mesh
	head.material_override = red
	head.rotation.y = PI * 0.5
	head.rotation.z = PI
	head.position = Vector3(0.0, 0.0, r + 0.35)
	pointer.add_child(head)


## The balancer's mark glows a moment after each flash.
func _find_mark() -> void:
	for mi in _engine.balancer.find_children("Mark*", "MeshInstance3D", true, false):
		var mat := ((mi as MeshInstance3D).material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = Color(1.0, 1.0, 0.92)
		(mi as MeshInstance3D).material_override = mat
		_mark_mats.append(mat)


## A timing light held up in the foreground, its lens on the tab: pistol grip, body,
## barrel, and the cord trailing away to the battery and the plug wire.
func _build_light_gun() -> void:
	var tab := _tab_point()
	_light_gun = Node3D.new()
	_light_gun.name = "TimingLight"
	add_child(_light_gun)
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.85, 0.62, 0.08)
	yellow.roughness = 0.45
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.04, 0.04, 0.04)
	black.roughness = 0.6
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.albedo_color = Color(0.75, 0.82, 0.9)
	_lens_mat.emission_enabled = true
	_lens_mat.emission = Color(0.85, 0.9, 1.0)
	_lens_mat.emission_energy_multiplier = 0.0
	_lens_mat.metallic = 0.2
	_lens_mat.roughness = 0.1
	# Built pointing down -Z, then aimed.
	_part(_light_gun, BoxMesh.new(), Vector3(0.06, 0.07, 0.16), Vector3(0.0, 0.0, 0.0), yellow)
	_part(_light_gun, CylinderMesh.new(), Vector3(0.032, 0.08, 0.032), Vector3(0.0, 0.0, -0.11), black, Vector3(PI * 0.5, 0.0, 0.0))
	_part(_light_gun, CylinderMesh.new(), Vector3(0.028, 0.006, 0.028), Vector3(0.0, 0.0, -0.152), _lens_mat, Vector3(PI * 0.5, 0.0, 0.0))
	var grip := _part(_light_gun, BoxMesh.new(), Vector3(0.04, 0.12, 0.05), Vector3(0.0, -0.08, 0.04), black)
	grip.rotation.x = -0.35
	var cord := MeshInstance3D.new()
	cord.mesh = _EngineAssembly.sweep_mesh(PackedVector3Array([
		Vector3(0.0, -0.13, 0.07), Vector3(0.0, -0.22, 0.12), Vector3(0.05, -0.32, 0.1), Vector3(0.12, -0.42, 0.02),
	]), 0.008, 6, false)
	cord.material_override = black
	_light_gun.add_child(cord)
	# Held off to the right of the tab and a little nearer, aimed in at it from the side
	# so it does not cover the marks.
	var cam := _camera.global_transform
	_light_gun.global_position = tab + cam.basis.x * 0.26 - cam.basis.y * 0.05 + cam.basis.z * 0.08
	_light_gun.look_at(tab, Vector3.UP)
	_strobe = SpotLight3D.new()
	_strobe.light_color = Color(0.85, 0.92, 1.0)
	_strobe.light_energy = 0.0
	_strobe.spot_range = 2.0
	_strobe.spot_angle = 14.0
	_strobe.position = Vector3(0.0, 0.0, -0.16)
	_light_gun.add_child(_strobe)


func _part(parent: Node3D, mesh: PrimitiveMesh, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is CylinderMesh:
		var c := mesh as CylinderMesh
		c.top_radius = size.x
		c.bottom_radius = size.x
		c.height = size.y
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_sound() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.name = "EngineSound"
	_sound.set_script(_EngineSound)
	add_child(_sound)
	_sound.volume_db += 4.0
	GameState.set_music_dimmed(true, -40.0)
	# A short click from the distributor turning in its clamp.
	_click = AudioStreamPlayer.new()
	var samples := PackedByteArray()
	var rate := 22050
	var n := int(0.06 * rate)
	samples.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := (sin(TAU * 1800.0 * t) * 0.5 + _rng.randf_range(-0.5, 0.5)) * exp(-t * 120.0) * 0.6
		samples.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = samples
	_click.stream = wav
	_click.volume_db = -8.0
	add_child(_click)


# --- UI ----------------------------------------------------------------------------------


func _build_ui() -> void:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override(&"panel", _panel_style())
	header.position = Vector2(16, 16)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(header)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 4)
	header.add_child(info)
	info.add_child(_ui_label("Timing — %s" % GameState.car_name, 22))
	info.add_child(_ui_label(str(GameState.get_equipped_engine().get("name", "Engine")), 17))

	# The tune-up sticker off the radiator support.
	var sticker := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.9, 0.8)
	style.border_color = Color(0.1, 0.1, 0.1)
	style.set_border_width_all(2)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	sticker.add_theme_stylebox_override(&"panel", style)
	sticker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sticker.offset_left = -230.0
	sticker.offset_top = 16.0
	sticker.offset_right = -16.0
	sticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(sticker)
	var lines := VBoxContainer.new()
	sticker.add_child(lines)
	for text in ["ENGINE TUNE-UP", "%d CU. IN. V8" % GameState.engine_cid(), "Timing  %d° BTDC" % GameState.timing_degrees(GameState.engine_sweet_tune()), "at idle"]:
		var label := Label.new()
		label.text = text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override(&"font_color", Color(0.1, 0.1, 0.1))
		label.add_theme_font_size_override(&"font_size", 16)
		lines.add_child(label)

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override(&"panel", _panel_style())
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16.0
	bottom.offset_right = -16.0
	bottom.offset_top = -72.0
	bottom.offset_bottom = -16.0
	_ui.add_child(bottom)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 12)
	bottom.add_child(bar)
	_hint = _ui_label("", 18)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_hint)
	_advance_btn = Button.new()
	_advance_btn.text = "▲ Advance"
	_advance_btn.pressed.connect(_step.bind(1))
	bar.add_child(_advance_btn)
	_retard_btn = Button.new()
	_retard_btn.text = "▼ Retard"
	_retard_btn.pressed.connect(_step.bind(-1))
	bar.add_child(_retard_btn)
	_done_btn = Button.new()
	_done_btn.text = "Done"
	_done_btn.custom_minimum_size = Vector2(96, 0)
	_done_btn.pressed.connect(_on_done_pressed)
	bar.add_child(_done_btn)
	_nav.setup([_advance_btn, _retard_btn, _done_btn])


func _ui_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", _CREAM)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.92)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style
