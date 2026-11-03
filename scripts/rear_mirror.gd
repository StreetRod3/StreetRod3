extends SubViewportContainer

## Local pose on the player car. The car nose is +Z, and a camera looks along -Z, so this faces the road behind.
const _CAM_POS := Vector3(0.0, 1.62, 1.15)
const _CAM_PITCH := 0.08

@onready var _view: SubViewport = $RearView
@onready var _camera: Camera3D = $RearView/RearCamera

var _car: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_view.handle_input_locally = false
	_view.audio_listener_enable_3d = false
	_view.own_world_3d = false
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var race := owner
	if race != null:
		_car = race.get_node_or_null(^"PlayerCar") as Node3D
	_place_camera()


func _process(_delta: float) -> void:
	_place_camera()


func _place_camera() -> void:
	if _car == null or _camera == null:
		return
	var look := Basis.from_euler(Vector3(_CAM_PITCH, 0.0, 0.0))
	var pos := _car.global_transform * _CAM_POS
	_camera.global_transform = Transform3D(_car.global_transform.basis * look, pos)
