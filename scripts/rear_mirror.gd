extends SubViewportContainer

## Local pose on the player car. The car nose is +Z, and a camera looks along -Z, so this faces the road behind.
const _CAM_POS := Vector3(0.0, 1.62, 1.15)
const _CAM_PITCH := 0.08
const _SCRIPT_PATH := "res://scripts/rear_mirror.gd"
const _FLIP_SHADER_CODE := "shader_type canvas_item;\n\nvoid fragment() {\n\tCOLOR = texture(TEXTURE, vec2(1.0 - UV.x, UV.y));\n}\n"

@onready var _view: SubViewport = $RearView
@onready var _camera: Camera3D = $RearView/RearCamera

var _car: Node3D


static func build_housing(car: Node3D) -> Control:
	var mirror := Control.new()
	mirror.name = "RearMirror"
	mirror.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mirror.offset_left = -270.0
	mirror.offset_top = 10.0
	mirror.offset_right = 270.0
	mirror.offset_bottom = 156.0
	mirror.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var housing := StyleBoxFlat.new()
	housing.bg_color = Color(0.06, 0.06, 0.07, 1.0)
	housing.border_width_left = 8
	housing.border_width_top = 8
	housing.border_width_right = 8
	housing.border_width_bottom = 12
	housing.border_color = Color(0.62, 0.63, 0.66, 1.0)
	housing.corner_radius_top_left = 14
	housing.corner_radius_top_right = 14
	housing.corner_radius_bottom_right = 16
	housing.corner_radius_bottom_left = 16

	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override(&"panel", housing)
	mirror.add_child(frame)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	margin.grow_vertical = Control.GROW_DIRECTION_BOTH
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 12)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_right", 12)
	margin.add_theme_constant_override(&"margin_bottom", 16)
	frame.add_child(margin)

	var shader := Shader.new()
	shader.code = _FLIP_SHADER_CODE
	var flip_mat := ShaderMaterial.new()
	flip_mat.shader = shader

	var glass := SubViewportContainer.new()
	glass.name = "Glass"
	glass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	glass.size_flags_vertical = Control.SIZE_EXPAND_FILL
	glass.stretch = true
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.material = flip_mat

	var view := SubViewport.new()
	view.name = "RearView"
	view.handle_input_locally = false
	view.audio_listener_enable_3d = false
	view.own_world_3d = false
	view.size = Vector2i(640, 180)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var cam := Camera3D.new()
	cam.name = "RearCamera"
	cam.current = true
	cam.fov = 52.0
	cam.near = 0.15
	cam.far = 1600.0
	view.add_child(cam)
	glass.add_child(view)
	glass.set_script(load(_SCRIPT_PATH))
	glass.call(&"set_car", car)
	margin.add_child(glass)
	return mirror


func set_car(car: Node3D) -> void:
	_car = car
	_place_camera()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_view.handle_input_locally = false
	_view.audio_listener_enable_3d = false
	_view.own_world_3d = false
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _car == null and owner != null:
		_car = owner.get_node_or_null(^"PlayerCar") as Node3D
	_place_camera()


func _process(_delta: float) -> void:
	_place_camera()


func _place_camera() -> void:
	if _car == null or _camera == null:
		return
	var look := Basis.from_euler(Vector3(_CAM_PITCH, 0.0, 0.0))
	var pos := _car.global_transform * _CAM_POS
	_camera.global_transform = Transform3D(_car.global_transform.basis * look, pos)
