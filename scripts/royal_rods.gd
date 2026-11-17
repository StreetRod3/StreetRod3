extends Node3D

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _PlaceDeparture := preload("res://scripts/place_departure.gd")
const _RoyalRodsSign := preload("res://scripts/royal_rods_sign.gd")
const _PartPreview := preload("res://scripts/part_preview.gd")
const _KING_POSTER := preload("res://assets/locations/city/theking-poster.jpg")
const _KING_SCENE_POSTER := preload("res://assets/locations/city/king-scene-poster.jpg")
const _WALL_POSTERS: Array[Texture2D] = [
	preload("res://assets/locations/city/poster1.png"),
	preload("res://assets/locations/city/poster2.jpg"),
	preload("res://assets/locations/city/poster3.webp"),
	preload("res://assets/locations/city/poster4.jpg"),
	preload("res://assets/locations/city/poster5.jpg"),
]

const _SORT_PRICE := "price"
const _SORT_NAME := "name"
## Shop left visible around the parts window. Wide enough for a finger.
const _CATALOG_EDGE := 72.0
const _BOTTOM_BAR := 52.0
const _CREAM := Color(0.78, 0.72, 0.59)
const _WOOD := Color(0.37, 0.22, 0.13)
const _BURGUNDY := Color(0.44, 0.07, 0.08)
const _METAL := Color(0.57, 0.57, 0.53)
## Lowest point of each stock model relative to its drawing origin.
const _STOCK_BOTTOM := {
	"engine": 0.095, "transmission": 0.09, "carb": 0.13, "heads": 0.12,
	"intake": 0.145, "manifold": 0.145, "distributor": 0.13, "air_cleaner": 0.23,
	"cam": 0.205, "exhaust": 0.205, "muffler": 0.15, "shocks": 0.205,
	"differential": 0.12, "springs": 0.1175,
}

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: CanvasLayer = $UI

var _nav := _MenuNav.new()
var _catalog: PanelContainer
var _catalog_margin: Control
var _catalog_list: VBoxContainer
var _catalog_title: Label
var _catalog_scroll: ScrollContainer
var _sort_by := _SORT_PRICE
var _sort_group: ButtonGroup
var _cash: Label
var _status: Label
var _hint: Label
var _back: Button
var _town: Button
var _folder: Area3D
var _poster_viewer: Control
var _poster_image: TextureRect
var _poster_close: Button
var _poster_shade: ColorRect
var _active_poster: Sprite3D
var _poster_tween: Tween
var _poster_closing := false
var _part_row_styles: Dictionary = {}
var _preview_mount: Node3D
var _preview_camera: Camera3D
var _preview_subject: Node3D
var _preview_caption: Label
var _preview_frame: SubViewportContainer
var _buy_button: Button
var _selected_kind := ""
var _selected_id := ""


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_ROYAL_RODS
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera.position = Vector3(0.0, 3.0, 9.0)
	_camera.look_at(Vector3(0.0, 1.65, -2.3), Vector3.UP)
	_build_store()
	_build_ui()


func _process(delta: float) -> void:
	_hint.text = _hint_at(GameState.pointer_position(get_viewport()), get_viewport().gui_get_hovered_control())
	if _preview_subject != null and _catalog.visible:
		_preview_mount.rotate_y(delta * 0.35)


func _hint_at(screen_pos: Vector2, hovered: Control) -> String:
	var node: Node = hovered
	while node != null:
		if node.has_meta(&"status_hint"):
			return str(node.get_meta(&"status_hint"))
		node = node.get_parent()
	if hovered != null or _catalog.visible or _poster_viewer.visible:
		return ""
	var display := _display_at(screen_pos)
	if display == null:
		return ""
	if display == _folder:
		return "Browse all new parts (P)"
	if display.get_parent() is Sprite3D:
		return "View poster"
	return "Browse %s" % _filter_name(str(display.get_meta(&"catalog_filter", ""))).to_lower()


func _input(event: InputEvent) -> void:
	if _poster_viewer.visible:
		if event.is_action_pressed(&"ui_cancel"):
			_close_poster()
			get_viewport().set_input_as_handled()
		elif _PlaceDeparture.home_pressed(event) or _PlaceDeparture.cruise_pressed(event):
			get_viewport().set_input_as_handled()
		return
	if _PlaceDeparture.home_pressed(event):
		get_viewport().set_input_as_handled()
		_leave(true)
	elif _PlaceDeparture.cruise_pressed(event):
		get_viewport().set_input_as_handled()
		_leave(false)


func _unhandled_input(event: InputEvent) -> void:
	if _poster_viewer.visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _catalog.visible:
			_close_catalog()
		else:
			_leave(true)
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and not key.ctrl_pressed and not key.meta_pressed and not key.alt_pressed and key.keycode == KEY_P:
			get_viewport().set_input_as_handled()
			_open_catalog()
			return
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not _catalog.visible:
			var display := _display_at(click.position)
			if display != null:
				get_viewport().set_input_as_handled()
				if display.get_parent() is Sprite3D:
					_open_poster(display.get_parent() as Sprite3D)
				else:
					_open_catalog(str(display.get_meta(&"catalog_filter", "")))
				return
	var viewport := get_viewport()
	if _nav.handle_event(self, event) and viewport != null:
		viewport.set_input_as_handled()


func _leave(home: bool) -> void:
	if home:
		GameState.drive_into_garage = true
		GameState.begin_cruise(GameState.POI_ROYAL_RODS, GameState.POI_GARAGE, GameState.SCENE_GARAGE)
	else:
		GameState.begin_roam(GameState.POI_ROYAL_RODS)


func _build_store() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.12, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.91, 0.76)
	env.ambient_light_energy = 0.7
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_color = Color(1.0, 0.9, 0.75)
	light.light_energy = 0.8
	add_child(light)

	_box(Vector3(13.0, 0.2, 13.0), Vector3(0, -0.1, 0), Color(0.34, 0.31, 0.27))
	_box(Vector3(13.0, 5.2, 0.25), Vector3(0, 2.6, -5.2), _CREAM)
	_box(Vector3(0.25, 5.2, 10.0), Vector3(-6.5, 2.6, -0.2), _CREAM.darkened(0.1))
	_box(Vector3(0.25, 5.2, 10.0), Vector3(6.5, 2.6, -0.2), _CREAM.darkened(0.1))
	_box(Vector3(0.04, 1.0, 2.2), Vector3(-6.35, 4.05, -0.6), _BURGUNDY)
	_label_3d("MOTOR OIL", Vector3(-6.32, 4.22, -0.6), 40, 0.012, _CREAM, PI / 2.0)
	_label_3d("SERVICE  •  QUALITY", Vector3(-6.32, 3.85, -0.6), 25, 0.008, _CREAM, PI / 2.0)
	_box(Vector3(0.04, 1.0, 2.2), Vector3(6.35, 4.6, -0.6), Color(0.17, 0.29, 0.36))
	_label_3d("SPEED SHOP", Vector3(6.32, 4.77, -0.6), 40, 0.012, _CREAM, -PI / 2.0)
	_label_3d("TUNE UP TODAY", Vector3(6.32, 4.4, -0.6), 25, 0.008, _CREAM, -PI / 2.0)
	_box(Vector3(13.0, 0.3, 0.1), Vector3(0, 0.6, -5.02), _BURGUNDY)
	var sign := _RoyalRodsSign.new()
	sign.position = Vector3(0, 4.1, -4.98)
	add_child(sign)
	_build_poster("KingPoster", _KING_POSTER, Vector3(-1.95, 2.45, -5.02))
	_build_poster("KingScenePoster", _KING_SCENE_POSTER, Vector3(1.95, 2.45, -5.02))
	var poster_positions := [
		Vector3(6.34, 1.85, -3.2),
		Vector3(6.34, 1.85, -1.55),
		Vector3(6.34, 1.85, 0.1),
		Vector3(6.34, 3.35, -2.375),
		Vector3(6.34, 3.35, -0.725),
	]
	for i in _WALL_POSTERS.size():
		_build_poster("WallPoster%d" % (i + 1), _WALL_POSTERS[i], poster_positions[i], 1.15, -PI / 2.0)
	_build_shelf(-4.55, ["engine", "transmission", "carb", "heads", "intake", "distributor", "air_cleaner"])
	_build_shelf(4.55, ["cam", "manifold", "exhaust", "muffler", "differential", "springs", "shocks"])
	_build_wheel_stand(-5.65, -1.0, "wheels")
	_build_wheel_stand(-5.65, 1.4, "tires")
	_build_clerk()
	_box(Vector3(5.5, 1.2, 1.1), Vector3(0, 0.6, -0.8), _WOOD)
	_box(Vector3(5.7, 0.13, 1.3), Vector3(0, 1.27, -0.8), Color(0.68, 0.61, 0.48))
	_box(Vector3(5.15, 0.08, 0.04), Vector3(0, 0.3, -0.23), _CREAM)
	_box(Vector3(0.58, 0.42, 0.42), Vector3(1.75, 1.55, -0.8), Color(0.25, 0.27, 0.24))
	_box(Vector3(0.44, 0.1, 0.25), Vector3(1.75, 1.79, -0.77), _METAL)
	_build_catalog_folder()
	_label_3d("NEW PARTS", Vector3(0, 0.82, -0.19), 40, 0.012, Color(0.95, 0.82, 0.55))


func _build_poster(poster_name: String, texture: Texture2D, center: Vector3, width: float = 1.8, angle: float = 0.0) -> void:
	var height := width * float(texture.get_height()) / float(texture.get_width())
	_box(Vector3(width + 0.12, height + 0.12, 0.06), center, _WOOD, Vector3(0, angle, 0))
	var poster := Sprite3D.new()
	poster.name = poster_name
	poster.texture = texture
	poster.pixel_size = width / float(texture.get_width())
	poster.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	poster.shaded = false
	poster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	poster.position = center + Vector3(0, 0, 0.04).rotated(Vector3.UP, angle)
	poster.rotation.y = angle
	add_child(poster)
	var area := Area3D.new()
	area.name = "PosterHitbox"
	area.collision_layer = 1
	area.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width + 0.12, height + 0.12, 0.08)
	collision.shape = shape
	area.add_child(collision)
	poster.add_child(area)


func _build_catalog_folder() -> void:
	var center := Vector3(-0.9, 1.36, -0.72)
	_box(Vector3(0.92, 0.05, 0.68), center, _BURGUNDY)
	_box(Vector3(0.78, 0.015, 0.54), center + Vector3(0.0, 0.033, 0.0), _CREAM)
	_box(Vector3(0.26, 0.05, 0.09), center + Vector3(-0.28, 0.0, -0.38), _BURGUNDY)
	var label := Label3D.new()
	label.text = "PARTS"
	label.font_size = 40
	label.pixel_size = 0.005
	label.modulate = Color(0.25, 0.12, 0.09)
	label.shaded = false
	label.position = center + Vector3(0.0, 0.043, 0.0)
	label.rotation.x = -PI / 2.0
	add_child(label)
	_folder = Area3D.new()
	_folder.name = "PartsFolder"
	_folder.position = center
	_folder.collision_layer = 1
	_folder.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.92, 0.12, 0.76)
	collision.shape = shape
	_folder.add_child(collision)
	add_child(_folder)


func _display_at(screen_pos: Vector2) -> Area3D:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") as Area3D


func _folder_at(screen_pos: Vector2) -> bool:
	return _display_at(screen_pos) == _folder


func _build_shelf(x: float, types: Array) -> void:
	_box(Vector3(2.6, 3.35, 0.14), Vector3(x, 2.85, -4.65), _WOOD)
	for y: float in [1.28, 2.0, 2.72, 3.44, 4.16]:
		_box(Vector3(2.75, 0.12, 0.8), Vector3(x, y, -4.3), _WOOD.lightened(0.1))
	for i in types.size():
		var kind := str(types[i])
		var center_x := x + (-0.68 if i % 2 == 0 else 0.68)
		var base := 3.5 - float(i / 2) * 0.72
		_shelf_stock(center_x, base, kind)
		_label_3d(_filter_name(kind).to_upper(), Vector3(center_x, base + 0.04, -3.87), 30, 0.0038, _CREAM)
		_add_display(kind, Vector3(center_x, base + 0.32, -4.12), Vector3(1.3, 0.68, 0.65))


func _add_display(kind: String, center: Vector3, size: Vector3) -> void:
	var area := Area3D.new()
	area.name = "Shelf_" + kind
	area.position = center
	area.collision_layer = 1
	area.collision_mask = 0
	area.set_meta(&"catalog_filter", kind)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	add_child(area)


func _build_wheel_stand(x: float, z: float, kind: String) -> void:
	var first := get_child_count()
	_box(Vector3(1.25, 0.1, 0.55), Vector3(x, 0.7, z), _METAL)
	_box(Vector3(1.25, 0.1, 0.55), Vector3(x, 2.65, z), _METAL)
	for dx: float in [-0.58, 0.58]:
		_box(Vector3(0.08, 2.0, 0.08), Vector3(x + dx, 1.7, z), _METAL)
	for y: float in [1.25, 2.05]:
		_box(Vector3(1.25, 0.08, 0.42), Vector3(x, y - 0.38, z + 0.08), _METAL)
		_cylinder(0.34, 0.24, Vector3(x, y, z + 0.08), Color(0.08, 0.08, 0.08), Vector3(PI / 2.0, 0, 0))
		if kind == "wheels":
			_cylinder(0.21, 0.25, Vector3(x, y, z + 0.09), _METAL, Vector3(PI / 2.0, 0, 0))
	_label_3d(_filter_name(kind).to_upper(), Vector3(x, 2.78, z + 0.3), 34, 0.008, _CREAM)
	_add_display(kind, Vector3(x, 1.72, z + 0.15), Vector3(1.3, 2.05, 0.5))
	var stand := Node3D.new()
	stand.name = "Stand_" + kind
	stand.position = Vector3(x, 0.0, z)
	add_child(stand)
	while get_child(first) != stand:
		get_child(first).reparent(stand)
	stand.rotation.y = PI / 2.0 if x < 0.0 else -PI / 2.0
	stand.position.y = -0.65


func _shelf_stock(x: float, y: float, kind: String) -> void:
	if not _STOCK_BOTTOM.has(kind):
		push_error("No shelf stock model for '%s'." % kind)
		return
	for dx: float in [-0.28, 0.28]:
		var at := Vector3(x + dx, y - float(_STOCK_BOTTOM[kind]), -4.25)
		match kind:
			"engine":
				_box(Vector3(0.38, 0.25, 0.3), at + Vector3(0, 0.22, 0), Color(0.65, 0.25, 0.09))
				_box(Vector3(0.42, 0.1, 0.3), at + Vector3(0, 0.4, 0), _METAL)
				_cylinder(0.1, 0.08, at + Vector3(0, 0.49, 0), _METAL)
			"transmission":
				_cylinder(0.12, 0.38, at + Vector3(0, 0.27, 0), _METAL, Vector3(0, 0, PI / 2.0))
				_cylinder(0.18, 0.08, at + Vector3(-0.18, 0.27, 0), _METAL, Vector3(0, 0, PI / 2.0))
			"carb":
				_box(Vector3(0.3, 0.2, 0.25), at + Vector3(0, 0.23, 0), Color(0.61, 0.53, 0.32))
				_cylinder(0.08, 0.08, at + Vector3(-0.08, 0.37, 0), _METAL)
				_cylinder(0.08, 0.08, at + Vector3(0.08, 0.37, 0), _METAL)
			"heads":
				_box(Vector3(0.42, 0.18, 0.24), at + Vector3(0, 0.21, 0), _METAL)
				_box(Vector3(0.36, 0.07, 0.25), at + Vector3(0, 0.34, 0), Color(0.35, 0.35, 0.33))
			"intake", "manifold":
				_box(Vector3(0.4, 0.15, 0.26), at + Vector3(0, 0.22, 0), _METAL)
				for offset: float in [-0.13, 0.0, 0.13]:
					_cylinder(0.045, 0.22, at + Vector3(offset, 0.34, 0), _METAL)
			"distributor", "air_cleaner":
				_cylinder(0.15 if kind == "air_cleaner" else 0.09, 0.1 if kind == "air_cleaner" else 0.3, at + Vector3(0, 0.28, 0), _BURGUNDY if kind == "distributor" else _METAL)
			"cam", "exhaust", "muffler", "shocks":
				_cylinder(0.1 if kind == "muffler" else 0.045, 0.4, at + Vector3(0, 0.25, 0), _METAL, Vector3(0, 0, PI / 2.0))
			"differential":
				_sphere(0.16, at + Vector3(0, 0.28, 0), _METAL)
				_cylinder(0.06, 0.4, at + Vector3(0, 0.28, 0), _METAL, Vector3(0, 0, PI / 2.0))
			"springs":
				for step in 4:
					_cylinder(0.12, 0.045, at + Vector3(0, 0.14 + float(step) * 0.09, 0), _METAL)


func _filter_name(kind: String) -> String:
	match kind:
		"engine":
			return "Engines"
		"transmission":
			return "Transmissions"
		"wheels":
			return "Wheels"
		"carb":
			return "Carburetors"
		"heads":
			return "Cylinder heads"
		"tires":
			return "Tires"
		"intake":
			return "Intakes"
		"distributor":
			return "Distributors"
		"air_cleaner":
			return "Air cleaners"
		"cam":
			return "Camshafts"
		"manifold":
			return "Headers"
		"exhaust":
			return "Exhaust"
		"muffler":
			return "Mufflers"
		"differential":
			return "Rear ends"
		"springs":
			return "Springs"
		"shocks":
			return "Shocks"
	return "New parts"


func _build_clerk() -> void:
	var jacket := Color(0.13, 0.18, 0.29)
	var skin := Color(0.77, 0.55, 0.39)
	var hair := Color(0.25, 0.16, 0.11)
	var frame := Color(0.34, 0.27, 0.2)
	_box(Vector3(0.82, 0.95, 0.38), Vector3(0, 1.55, -2.0), jacket)
	_box(Vector3(0.2, 0.68, 0.2), Vector3(-0.49, 1.48, -1.95), jacket, Vector3(0, 0, -0.2))
	_box(Vector3(0.2, 0.68, 0.2), Vector3(0.49, 1.48, -1.95), jacket, Vector3(0, 0, 0.2))
	_box(Vector3(0.25, 0.18, 0.2), Vector3(0, 2.03, -1.98), skin)
	_box(Vector3(0.22, 0.23, 0.02), Vector3(0, 1.91, -1.8), _CREAM)
	_box(Vector3(0.04, 0.23, 0.025), Vector3(0, 1.91, -1.78), _BURGUNDY)
	_box(Vector3(0.29, 0.16, 0.03), Vector3(-0.22, 1.7, -1.8), _CREAM)
	_label_3d("the King", Vector3(-0.22, 1.7, -1.77), 25, 0.0024, _BURGUNDY, 0.0, 0)
	_sphere(0.25, Vector3(0, 2.29, -1.98), skin)
	_sphere(0.025, Vector3(-0.09, 2.32, -1.747), Color(0.12, 0.09, 0.07))
	_sphere(0.025, Vector3(0.09, 2.32, -1.747), Color(0.12, 0.09, 0.07))
	_box(Vector3(0.18, 0.055, 0.035), Vector3(0, 2.21, -1.736), hair)
	_box(Vector3(0.12, 0.02, 0.02), Vector3(0, 2.16, -1.74), Color(0.35, 0.17, 0.12))
	_box(Vector3(0.45, 0.14, 0.36), Vector3(0, 2.49, -1.99), hair)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.075, 0.22, 0.28), Vector3(side * 0.215, 2.38, -1.98), hair)
		_box(Vector3(0.15, 0.018, 0.018), Vector3(side * 0.09, 2.39, -1.726), frame)
		_box(Vector3(0.15, 0.018, 0.018), Vector3(side * 0.09, 2.25, -1.726), frame)
		_box(Vector3(0.018, 0.14, 0.018), Vector3(side * 0.165, 2.32, -1.726), frame)
		_box(Vector3(0.018, 0.14, 0.018), Vector3(side * 0.015, 2.32, -1.726), frame)
	_box(Vector3(0.04, 0.018, 0.018), Vector3(0, 2.34, -1.726), frame)


func _box(size: Vector3, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(mesh, pos, color, rot)


func _cylinder(radius: float, height: float, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_mesh(mesh, pos, color, rot)


func _sphere(radius: float, pos: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	_mesh(mesh, pos, color)


func _mesh(mesh: Mesh, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation = rot
	add_child(instance)


func _label_3d(text: String, pos: Vector3, font_size: int, pixel_size: float, color: Color, yaw: float = 0.0, outline: int = 12) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.shaded = false
	label.outline_size = outline
	label.rotation.y = yaw
	add_child(label)


func _build_ui() -> void:
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -52.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bar)
	var background := ColorRect.new()
	background.color = Color(0.14, 0.09, 0.06, 0.95)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(background)
	_cash = Label.new()
	_cash.position = Vector2(18, 13)
	_cash.add_theme_font_size_override(&"font_size", 22)
	bar.add_child(_cash)
	_refresh_cash()
	var hint_layer := CanvasLayer.new()
	hint_layer.layer = 2
	_ui.add_child(hint_layer)
	_hint = Label.new()
	_hint.name = "StatusHint"
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 250.0
	_hint.offset_right = -_PlaceDeparture.label_inset()
	_hint.offset_top = -52.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78))
	_hint.add_theme_font_size_override(&"font_size", 20)
	hint_layer.add_child(_hint)
	var depart := _PlaceDeparture.add_to(bar)
	_back = depart["back"] as Button
	_town = depart["town"] as Button
	_back.set_meta(&"status_hint", "Return to the garage (G)")
	_town.set_meta(&"status_hint", "Cruise around town (D)")
	_back.pressed.connect(_leave.bind(true))
	_town.pressed.connect(_leave.bind(false))

	_catalog_margin = Control.new()
	_catalog_margin.name = "CatalogMargin"
	_catalog_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catalog_margin.offset_bottom = -_BOTTOM_BAR
	_catalog_margin.mouse_filter = Control.MOUSE_FILTER_STOP
	_catalog_margin.visible = false
	_catalog_margin.gui_input.connect(_on_catalog_margin_input)
	_ui.add_child(_catalog_margin)
	_catalog = PanelContainer.new()
	_catalog.name = "Catalog"
	_catalog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catalog.offset_left = _CATALOG_EDGE
	_catalog.offset_right = -_CATALOG_EDGE
	_catalog.offset_top = _CATALOG_EDGE
	_catalog.offset_bottom = -(_BOTTOM_BAR + _CATALOG_EDGE)
	var catalog_style := StyleBoxFlat.new()
	catalog_style.bg_color = Color(0.13, 0.1, 0.08, 0.98)
	catalog_style.border_color = Color(0.69, 0.53, 0.3)
	catalog_style.set_border_width_all(2)
	_catalog.add_theme_stylebox_override(&"panel", catalog_style)
	_ui.add_child(_catalog)
	var margin := MarginContainer.new()
	for edge: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(edge, 12)
	_catalog.add_child(margin)
	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", 14)
	margin.add_child(split)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size = Vector2(1040, 0)
	split.add_child(column)
	_catalog_title = Label.new()
	_catalog_title.add_theme_font_size_override(&"font_size", 22)
	column.add_child(_catalog_title)
	var note := Label.new()
	note.text = "New, 100% condition. Bought parts go to your spares."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var sorts := HBoxContainer.new()
	sorts.alignment = BoxContainer.ALIGNMENT_CENTER
	sorts.add_theme_constant_override(&"separation", 8)
	var sort_label := Label.new()
	sort_label.text = "Sort"
	sort_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sorts.add_child(sort_label)
	_sort_group = ButtonGroup.new()
	_sort_group.allow_unpress = false
	sorts.add_child(_sort_button("By price", _SORT_PRICE))
	sorts.add_child(_sort_button("By name", _SORT_NAME))
	column.add_child(sorts)
	_catalog_scroll = ScrollContainer.new()
	_catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog_scroll.follow_focus = true
	column.add_child(_catalog_scroll)
	_catalog_list = VBoxContainer.new()
	_catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_list.add_theme_constant_override(&"separation", 18)
	_catalog_scroll.add_child(_catalog_list)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var close := Button.new()
	close.text = "Close catalog (Esc)"
	close.set_meta(&"status_hint", "Close the catalog (Esc)")
	close.pressed.connect(_close_catalog)
	column.add_child(close)
	split.add_child(_build_part_preview())
	for group: Array in [
		["ENGINES", "engine", GameState.ENGINES],
		["TRANSMISSIONS", "transmission", GameState.GEARBOXES],
		["WHEELS", "wheels", GameState.WHEELS],
		["PARTS", "part", GameState.PARTS],
	]:
		var heading := Label.new()
		heading.text = str(group[0])
		heading.add_theme_font_size_override(&"font_size", 19)
		_catalog_list.add_child(heading)
		for part: Dictionary in group[2]:
			var kind := str(group[1])
			var filter := str(part.get("slot", "")) if kind == "part" else kind
			var row := PanelContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.set_meta(&"catalog_filter", filter)
			row.set_meta(&"part_kind", kind)
			row.set_meta(&"part_id", str(part["id"]))
			row.set_meta(&"sort_price", int(part.get("price", 0)))
			row.set_meta(&"sort_name", _item_label(part))
			row.set_meta(&"row_hovered", false)
			row.set_meta(&"row_pressed", false)
			var part_column := VBoxContainer.new()
			part_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			part_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
			part_column.add_theme_constant_override(&"separation", 2)
			row.add_child(part_column)
			var button := Button.new()
			button.text = "%s  —  $%d" % [_item_label(part), int(part.get("price", 0))]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.set_meta(&"catalog_filter", filter)
			button.set_meta(&"part_id", str(part["id"]))
			button.set_meta(&"status_hint", "Look at %s" % _item_label(part))
			button.pressed.connect(_select_part.bind(kind, str(part["id"])))
			part_column.add_child(button)
			var detail := Label.new()
			detail.text = GameState.listing_detail(kind, part)
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			detail.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			detail.add_theme_color_override(&"font_color", Color(0.86, 0.78, 0.62))
			detail.add_theme_font_size_override(&"font_size", 15)
			detail.set_meta(&"status_hint", button.get_meta(&"status_hint"))
			detail.gui_input.connect(_buy_from_detail.bind(button, detail))
			part_column.add_child(detail)
			_catalog_list.add_child(row)
			_ensure_part_row_styles(button)
			_flatten_part_button(button)
			_refresh_part_row(row, button)
			row.mouse_entered.connect(_part_row_hover.bind(row, button, true))
			row.mouse_exited.connect(_part_row_hover.bind(row, button, false))
			row.gui_input.connect(_buy_from_detail.bind(button, row))
			button.focus_entered.connect(_part_row_focus.bind(row, button))
			button.focus_exited.connect(_part_row_focus.bind(row, button))
			button.button_down.connect(_part_row_press.bind(row, button, true))
			button.button_up.connect(_part_row_press.bind(row, button, false))
	_sort_catalog()
	_catalog.visible = false
	_build_poster_viewer()
	_nav.setup([_back, _town])


func _build_part_preview() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.62, 0.56, 0.46)
	plate.set_content_margin_all(12)
	panel.add_theme_stylebox_override(&"panel", plate)
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override(&"separation", 10)
	panel.add_child(preview_column)
	_preview_caption = Label.new()
	_preview_caption.text = "Select a part"
	_preview_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_caption.add_theme_font_size_override(&"font_size", 20)
	_preview_caption.add_theme_color_override(&"font_color", Color(0.1, 0.08, 0.06))
	preview_column.add_child(_preview_caption)
	_preview_frame = SubViewportContainer.new()
	_preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_frame.stretch = true
	preview_column.add_child(_preview_frame)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.size = Vector2i(640, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_preview_frame.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.56, 0.46)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.86, 0.78)
	environment.ambient_light_energy = 0.65
	var env := WorldEnvironment.new()
	env.environment = environment
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_energy = 1.15
	key.shadow_enabled = true
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 150, 0)
	fill.light_energy = 0.35
	world.add_child(fill)
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(16, 0.08, 16)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.38, 0.34, 0.28)
	floor_mat.roughness = 0.92
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.material_override = floor_mat
	floor.position.y = -0.04
	world.add_child(floor)
	_preview_camera = Camera3D.new()
	_preview_camera.fov = 40.0
	_preview_camera.current = true
	world.add_child(_preview_camera)
	_preview_mount = Node3D.new()
	world.add_child(_preview_mount)
	_preview_camera.look_at_from_position(Vector3(0.9, 0.45, 1.3), Vector3(0.0, 0.3, 0.0))
	_buy_button = Button.new()
	_buy_button.text = "Buy"
	_buy_button.disabled = true
	_buy_button.custom_minimum_size = Vector2(0, 44)
	_buy_button.set_meta(&"status_hint", "Buy the part on show")
	_buy_button.pressed.connect(_buy_selected)
	preview_column.add_child(_buy_button)
	return panel


func _select_part(kind: String, id: String) -> void:
	if kind == _selected_kind and id == _selected_id and _preview_subject != null:
		return
	_selected_kind = kind
	_selected_id = id
	_refresh_part_rows()
	var part := GameState.listing_for(kind, id)
	var label := _item_label(part)
	_preview_caption.text = label
	_buy_button.text = "Buy — $%d" % int(part.get("price", 0))
	_buy_button.disabled = part.is_empty()
	_buy_button.set_meta(&"status_hint", "Buy %s" % label)
	_clear_part_preview()
	var subject := _PartPreview.build(part, kind) if not part.is_empty() else null
	if subject == null:
		_preview_frame.visible = false
		return
	_preview_subject = subject
	_preview_mount.add_child(subject)
	_preview_mount.rotation = Vector3.ZERO
	_preview_frame.visible = true
	_frame_part_camera()


func _clear_part_preview() -> void:
	if _preview_subject == null:
		return
	_preview_mount.remove_child(_preview_subject)
	_preview_subject.free()
	_preview_subject = null


## Each opening of the list starts with nothing on show.
func _reset_part_preview() -> void:
	_clear_part_preview()
	_preview_mount.rotation = Vector3.ZERO
	_preview_frame.visible = true
	_preview_caption.text = "Select a part"
	_buy_button.text = "Buy"
	_buy_button.disabled = true
	_buy_button.set_meta(&"status_hint", "Buy the part on show")
	_selected_kind = ""
	_selected_id = ""
	_refresh_part_rows()


func _frame_part_camera() -> void:
	if _preview_subject == null:
		return
	_preview_subject.force_update_transform()
	var bounds := _local_mesh_bounds(_preview_subject)
	if bounds.size == Vector3.ZERO:
		_preview_camera.look_at_from_position(Vector3(0.9, 0.45, 1.3), Vector3(0.0, 0.3, 0.0))
		return
	var scale := _preview_subject.scale
	var center := bounds.get_center()
	_preview_subject.position = Vector3(-center.x * scale.x, -bounds.position.y * scale.y, -center.z * scale.z)
	var height := bounds.size.y * absf(scale.y)
	var focus := Vector3(0.0, height * 0.5, 0.0)
	var extent := maxf(bounds.size.x * absf(scale.x), maxf(height, bounds.size.z * absf(scale.z)))
	var dist := extent * 0.72 / tan(deg_to_rad(_preview_camera.fov * 0.5))
	var eye := focus + Vector3(0.85, 0.62, 0.9).normalized() * dist
	_preview_camera.look_at_from_position(eye, focus)


func _local_mesh_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var started := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		bounds = (node as MeshInstance3D).mesh.get_aabb()
		started = true
	for child: Node in node.get_children():
		if not child is Node3D:
			continue
		var child_node := child as Node3D
		var child_bounds := _local_mesh_bounds(child_node)
		if child_bounds.size == Vector3.ZERO:
			continue
		child_bounds = _transformed_aabb(child_node.transform, child_bounds)
		if not started:
			bounds = child_bounds
			started = true
		else:
			bounds = bounds.merge(child_bounds)
	return bounds


func _transformed_aabb(xf: Transform3D, box: AABB) -> AABB:
	var out := AABB(xf * box.get_endpoint(0), Vector3.ZERO)
	for i: int in range(1, 8):
		out = out.expand(xf * box.get_endpoint(i))
	return out


func _buy_selected() -> void:
	if _selected_id.is_empty():
		return
	_buy(_selected_kind, _selected_id)


func _build_poster_viewer() -> void:
	_poster_viewer = Control.new()
	_poster_viewer.name = "PosterViewer"
	_poster_viewer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_poster_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(_poster_viewer)
	_poster_shade = ColorRect.new()
	_poster_shade.color = Color(0.06, 0.04, 0.03, 0.94)
	_poster_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_poster_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poster_viewer.add_child(_poster_shade)
	_poster_image = TextureRect.new()
	_poster_image.name = "PosterImage"
	_poster_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_poster_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_poster_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_poster_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poster_viewer.add_child(_poster_image)
	_poster_close = Button.new()
	_poster_close.text = "Close poster (Esc)"
	_poster_close.set_meta(&"status_hint", "Close the poster (Esc)")
	_poster_close.pressed.connect(_close_poster)
	_poster_viewer.add_child(_poster_close)
	_poster_viewer.visible = false
	_poster_viewer.resized.connect(_resize_poster_viewer)


func _poster_target_rect() -> Rect2:
	var viewport_size := _poster_viewer.size
	var available := viewport_size * 0.9 - Vector2(0, _poster_close.get_combined_minimum_size().y + 12.0)
	var texture_size := _poster_image.texture.get_size()
	var target_size := texture_size * minf(available.x / texture_size.x, available.y / texture_size.y) * 0.9
	return Rect2(Vector2((viewport_size.x - target_size.x) / 2.0, viewport_size.y * 0.05 + (available.y - target_size.y) / 2.0), target_size)


func _resize_poster_viewer() -> void:
	if not _poster_viewer.visible or _poster_image.texture == null:
		return
	if is_instance_valid(_poster_tween):
		_poster_tween.kill()
	if _poster_closing:
		_finish_close_poster()
		return
	var target := _poster_target_rect()
	_poster_image.position = target.position
	_poster_image.size = target.size
	var button_size := _poster_close.get_combined_minimum_size()
	_poster_close.size = button_size
	_poster_close.position = Vector2((_poster_viewer.size.x - button_size.x) / 2.0, _poster_viewer.size.y * 0.95 - button_size.y)
	_poster_shade.modulate.a = 1.0
	_poster_close.modulate.a = 1.0


func _open_poster(poster: Sprite3D) -> void:
	_active_poster = poster
	_poster_close.disabled = false
	_poster_image.texture = poster.texture
	_poster_viewer.visible = true
	_resize_poster_viewer()
	var target := Rect2(_poster_image.position, _poster_image.size)
	var start := _poster_wall_rect(poster)
	_poster_image.position = start.position
	_poster_image.size = start.size
	poster.visible = false
	_poster_shade.modulate.a = 0.0
	_poster_close.modulate.a = 0.0
	_poster_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_poster_tween.tween_property(_poster_image, "position", target.position, 0.4)
	_poster_tween.tween_property(_poster_image, "size", target.size, 0.4)
	_poster_tween.tween_property(_poster_shade, "modulate:a", 1.0, 0.4)
	_poster_tween.tween_property(_poster_close, "modulate:a", 1.0, 0.4)
	_nav.setup([_poster_close])


func _poster_wall_rect(poster: Sprite3D) -> Rect2:
	var half_size := poster.texture.get_size() * poster.pixel_size / 2.0
	var corners := [
		Vector3(-half_size.x, -half_size.y, 0), Vector3(half_size.x, -half_size.y, 0),
		Vector3(-half_size.x, half_size.y, 0), Vector3(half_size.x, half_size.y, 0),
	]
	var start := Rect2(_camera.unproject_position(poster.global_transform * corners[0]), Vector2.ZERO)
	for corner: Vector3 in corners:
		start = start.expand(_camera.unproject_position(poster.global_transform * corner))
	return start


func _close_poster() -> void:
	if _poster_closing or not _poster_viewer.visible:
		return
	_poster_closing = true
	if is_instance_valid(_poster_tween):
		_poster_tween.kill()
	_poster_close.disabled = true
	var target := _poster_wall_rect(_active_poster)
	_poster_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_poster_tween.tween_property(_poster_image, "position", target.position, 0.4)
	_poster_tween.tween_property(_poster_image, "size", target.size, 0.4)
	_poster_tween.tween_property(_poster_shade, "modulate:a", 0.0, 0.4)
	_poster_tween.tween_property(_poster_close, "modulate:a", 0.0, 0.4)
	_poster_tween.chain().tween_callback(_finish_close_poster)


func _finish_close_poster() -> void:
	_active_poster.visible = true
	_active_poster = null
	_poster_viewer.visible = false
	_poster_image.texture = null
	_poster_closing = false
	_nav.setup([_back, _town])


func _sort_button(text: String, mode: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = _sort_group
	button.button_pressed = mode == _SORT_PRICE
	button.set_meta(&"status_hint", "Sort by %s" % mode)
	button.toggled.connect(_on_sort_toggled.bind(mode))
	return button


func _on_sort_toggled(on: bool, mode: String) -> void:
	if on:
		_set_catalog_sort(mode)


## Price or name, within each heading. Engines stay with engines.
func _set_catalog_sort(mode: String) -> void:
	if mode == _sort_by:
		return
	_sort_by = mode
	_sort_catalog()
	if not _catalog.visible:
		return
	var keep := get_viewport().gui_get_focus_owner()
	var buttons := _nav.collect_buttons(_catalog)
	_nav.setup(buttons)
	var keep_index := buttons.find(keep)
	if keep_index >= 0:
		_nav.select(keep_index)
	_catalog_scroll.scroll_vertical = 0


func _sort_catalog() -> void:
	var index := 0
	var count := _catalog_list.get_child_count()
	while index < count:
		if _catalog_list.get_child(index) is PanelContainer:
			index += 1
			continue
		var start := index + 1
		var end := start
		while end < count and _catalog_list.get_child(end) is PanelContainer:
			end += 1
		var rows: Array[Node] = []
		for i in range(start, end):
			rows.append(_catalog_list.get_child(i))
		rows.sort_custom(_catalog_row_before)
		for i in rows.size():
			_catalog_list.move_child(rows[i], start + i)
		index = end


func _catalog_row_before(a: Node, b: Node) -> bool:
	var name_a := str(a.get_meta(&"sort_name"))
	var name_b := str(b.get_meta(&"sort_name"))
	if _sort_by == _SORT_NAME:
		var by_name := name_a.nocasecmp_to(name_b)
		if by_name != 0:
			return by_name < 0
	var price_a := int(a.get_meta(&"sort_price"))
	var price_b := int(b.get_meta(&"sort_price"))
	if price_a != price_b:
		return price_a < price_b
	var then_name := name_a.nocasecmp_to(name_b)
	if then_name != 0:
		return then_name < 0
	return str(a.get_meta(&"part_id", "")) < str(b.get_meta(&"part_id", ""))


func _open_catalog(filter: String = "") -> void:
	if _catalog.visible:
		return
	_reset_part_preview()
	_catalog_title.text = "THE KING'S ROYAL RODS  —  " + _filter_name(filter).to_upper()
	for row: Node in _catalog_list.get_children():
		if row is Control:
			(row as Control).visible = filter.is_empty() or str(row.get_meta(&"catalog_filter", "")) == filter
	_catalog_scroll.scroll_vertical = 0
	_catalog_margin.visible = true
	_catalog.visible = true
	_status.text = "Choose an item to buy."
	var buttons := _nav.collect_buttons(_catalog)
	_nav.setup(buttons)


func _close_catalog() -> void:
	_catalog.visible = false
	_catalog_margin.visible = false
	_nav.setup([_back, _town])


## A tap on the shop around the parts window puts the list away.
func _on_catalog_margin_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		pressed = click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	_catalog_margin.accept_event()
	_close_catalog()


func _ensure_part_row_styles(sample: Button) -> void:
	if not _part_row_styles.is_empty():
		return
	var focus := sample.get_theme_stylebox(&"focus") as StyleBoxFlat
	for fill: StringName in [&"normal", &"hover", &"pressed"]:
		_part_row_styles["%s:false" % fill] = _part_row_box(sample, fill, focus, false)
		_part_row_styles["%s:true" % fill] = _part_row_box(sample, fill, focus, true)
	# A pick stays warm, with a gold edge, so it does not look like the grey hover.
	var selected := _selected_part_row_box(sample, focus, false)
	var selected_hover := _selected_part_row_box(sample, focus, true)
	_part_row_styles["selected:false"] = selected
	_part_row_styles["selected:true"] = selected
	_part_row_styles["selected_hover:false"] = selected_hover
	_part_row_styles["selected_hover:true"] = selected_hover


func _part_row_box(sample: Button, fill: StringName, focus: StyleBoxFlat, focused: bool) -> StyleBoxFlat:
	var box := (sample.get_theme_stylebox(fill) as StyleBoxFlat).duplicate() as StyleBoxFlat
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	box.expand_margin_left = focus.expand_margin_left
	box.expand_margin_top = focus.expand_margin_top
	box.expand_margin_right = focus.expand_margin_right
	box.expand_margin_bottom = focus.expand_margin_bottom
	if focused:
		box.border_color = focus.border_color
		box.set_border_width_all(focus.border_width_left)
	return box


## Warm paper with a gold edge. Hover stays the theme's grey, so a pick reads apart from it.
func _selected_part_row_box(sample: Button, focus: StyleBoxFlat, hovered: bool) -> StyleBoxFlat:
	var box := _part_row_box(sample, &"normal", focus, false)
	box.bg_color = Color(0.58, 0.40, 0.18) if hovered else Color(0.44, 0.30, 0.14)
	box.border_color = Color(0.95, 0.78, 0.38)
	box.set_border_width_all(maxi(focus.border_width_left, 2))
	return box


func _flatten_part_button(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state_name: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		button.add_theme_stylebox_override(state_name, empty)


func _part_row_button(row: PanelContainer) -> Button:
	var column := row.get_child(0)
	if column == null or column.get_child_count() == 0:
		return null
	return column.get_child(0) as Button


func _row_is_selected(row: PanelContainer) -> bool:
	return not _selected_id.is_empty() and str(row.get_meta(&"part_kind", "")) == _selected_kind and str(row.get_meta(&"part_id", "")) == _selected_id


func _refresh_part_rows() -> void:
	for child: Node in _catalog_list.get_children():
		if not child is PanelContainer:
			continue
		var row := child as PanelContainer
		var button := _part_row_button(row)
		if button == null:
			continue
		_refresh_part_row(row, button)


func _refresh_part_row(row: PanelContainer, button: Button) -> void:
	var selected := _row_is_selected(row)
	var fill := "normal"
	if bool(row.get_meta(&"row_pressed")):
		fill = "pressed"
	elif bool(row.get_meta(&"row_hovered")) and selected:
		fill = "selected_hover"
	elif bool(row.get_meta(&"row_hovered")):
		fill = "hover"
	elif selected:
		fill = "selected"
	row.add_theme_stylebox_override(&"panel", _part_row_styles["%s:%s" % [fill, button.has_focus()]])


func _part_row_hover(row: PanelContainer, button: Button, inside: bool) -> void:
	row.set_meta(&"row_hovered", inside)
	if inside:
		button.grab_focus()
	_refresh_part_row(row, button)


func _part_row_focus(row: PanelContainer, button: Button) -> void:
	_refresh_part_row(row, button)


func _part_row_press(row: PanelContainer, button: Button, down: bool) -> void:
	row.set_meta(&"row_pressed", down)
	_refresh_part_row(row, button)


func _buy_from_detail(event: InputEvent, button: Button, detail: Control) -> void:
	if not event is InputEventMouseButton:
		return
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	detail.accept_event()
	button.pressed.emit()


func _buy(kind: String, id: String) -> void:
	var error := GameState.buy_new_part(kind, id)
	if error.is_empty():
		_status.text = "Bought %s. It's in your spare parts." % _item_label(GameState.listing_for(kind, id))
		_refresh_cash()
	else:
		_status.text = error


func _refresh_cash() -> void:
	_cash.text = "Bankroll: $%d" % GameState.money


## A catalog item's name with whom it fits, so the GM and Ford copies of a part tell apart.
func _item_label(part: Dictionary) -> String:
	var name := str(part.get("name", part.get("id", "")))
	var fits := GameState.fits_text(part)
	return name if fits.is_empty() else "%s (%s)" % [name, fits]
