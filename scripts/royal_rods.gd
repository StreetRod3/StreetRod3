extends Node3D

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _PlaceDeparture := preload("res://scripts/place_departure.gd")

const _CREAM := Color(0.78, 0.72, 0.59)
const _WOOD := Color(0.37, 0.22, 0.13)
const _BURGUNDY := Color(0.44, 0.07, 0.08)
const _METAL := Color(0.57, 0.57, 0.53)

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: CanvasLayer = $UI

var _nav := _MenuNav.new()
var _catalog: PanelContainer
var _catalog_list: VBoxContainer
var _cash: Label
var _status: Label
var _shop_button: Button
var _back: Button
var _town: Button


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_ROYAL_RODS
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera.position = Vector3(0.0, 3.0, 9.0)
	_camera.look_at(Vector3(0.0, 1.65, -2.3), Vector3.UP)
	_build_store()
	_build_ui()


func _input(event: InputEvent) -> void:
	if _PlaceDeparture.home_pressed(event):
		get_viewport().set_input_as_handled()
		_leave(true)
	elif _PlaceDeparture.cruise_pressed(event):
		get_viewport().set_input_as_handled()
		_leave(false)


func _unhandled_input(event: InputEvent) -> void:
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
	if _nav.handle_event(self, event):
		get_viewport().set_input_as_handled()


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
	_box(Vector3(0.04, 1.65, 2.2), Vector3(-6.35, 3.0, -0.6), _BURGUNDY)
	_label_3d("MOTOR OIL", Vector3(-6.32, 3.25, -0.6), 40, 0.012, _CREAM, PI / 2.0)
	_label_3d("SERVICE  •  QUALITY", Vector3(-6.32, 2.75, -0.6), 25, 0.008, _CREAM, PI / 2.0)
	_box(Vector3(0.04, 1.65, 2.2), Vector3(6.35, 3.0, -0.6), Color(0.17, 0.29, 0.36))
	_label_3d("SPEED SHOP", Vector3(6.32, 3.25, -0.6), 40, 0.012, _CREAM, -PI / 2.0)
	_label_3d("TUNE UP TODAY", Vector3(6.32, 2.75, -0.6), 25, 0.008, _CREAM, -PI / 2.0)
	_box(Vector3(13.0, 0.3, 0.1), Vector3(0, 0.6, -5.02), _BURGUNDY)
	_box(Vector3(4.5, 0.85, 0.12), Vector3(0, 4.25, -5.0), _BURGUNDY)
	_label_3d("ROYAL RODS", Vector3(0, 4.25, -4.92), 52, 0.012, Color(1.0, 0.84, 0.43))
	_label_3d("SPEED EQUIPMENT  •  AUTO PARTS", Vector3(0, 3.65, -4.95), 32, 0.009, Color(0.28, 0.18, 0.12))
	_build_shelf(-4.55)
	_build_shelf(4.55)
	_build_clerk()
	_box(Vector3(5.5, 1.2, 1.1), Vector3(0, 0.6, -0.8), _WOOD)
	_box(Vector3(5.7, 0.13, 1.3), Vector3(0, 1.27, -0.8), Color(0.68, 0.61, 0.48))
	_box(Vector3(5.15, 0.08, 0.04), Vector3(0, 0.72, -0.23), _CREAM)
	_box(Vector3(0.58, 0.42, 0.42), Vector3(1.75, 1.55, -0.8), Color(0.25, 0.27, 0.24))
	_box(Vector3(0.44, 0.1, 0.25), Vector3(1.75, 1.79, -0.77), _METAL)
	_label_3d("NEW PARTS", Vector3(0, 0.82, -0.21), 40, 0.012, Color(0.95, 0.82, 0.55))


func _build_shelf(x: float) -> void:
	_box(Vector3(2.6, 3.1, 0.14), Vector3(x, 1.65, -4.65), _WOOD)
	for y: float in [0.35, 1.2, 2.05, 2.9]:
		_box(Vector3(2.75, 0.12, 0.8), Vector3(x, y, -4.3), _WOOD.lightened(0.1))
	for dx: float in [-0.85, 0.0, 0.85]:
		_box(Vector3(0.55, 0.55, 0.42), Vector3(x + dx, 1.53, -4.25), _BURGUNDY if dx == 0.0 else Color(0.74, 0.62, 0.41))
		_box(Vector3(0.42, 0.2, 0.02), Vector3(x + dx, 1.56, -4.02), _CREAM)
		_cylinder(0.23, 0.18, Vector3(x + dx, 2.2, -4.25), _METAL)
		_cylinder(0.13, 0.25, Vector3(x + dx, 2.4, -4.25), Color(0.28, 0.28, 0.26))
	_cylinder(0.37, 0.18, Vector3(x - 0.65, 0.5, -4.25), Color(0.08, 0.08, 0.08), Vector3(PI / 2.0, 0, 0))
	_cylinder(0.2, 0.2, Vector3(x - 0.65, 0.5, -4.14), _METAL, Vector3(PI / 2.0, 0, 0))
	_box(Vector3(0.8, 0.25, 0.35), Vector3(x + 0.55, 0.55, -4.25), _METAL)
	for dx: float in [-0.65, 0.0, 0.65]:
		_cylinder(0.18, 0.42, Vector3(x + dx, 3.16, -4.25), _BURGUNDY if dx == 0.0 else Color(0.26, 0.35, 0.42))
		_cylinder(0.19, 0.12, Vector3(x + dx, 3.16, -4.25), _CREAM)


func _build_clerk() -> void:
	_box(Vector3(0.72, 0.95, 0.36), Vector3(0, 1.55, -2.0), Color(0.33, 0.42, 0.34))
	_box(Vector3(0.14, 0.65, 0.18), Vector3(-0.43, 1.48, -1.95), Color(0.33, 0.42, 0.34), Vector3(0, 0, -0.2))
	_box(Vector3(0.14, 0.65, 0.18), Vector3(0.43, 1.48, -1.95), Color(0.33, 0.42, 0.34), Vector3(0, 0, 0.2))
	_sphere(0.25, Vector3(0, 2.29, -1.98), Color(0.77, 0.55, 0.39))
	_sphere(0.025, Vector3(-0.09, 2.32, -1.747), Color(0.12, 0.09, 0.07))
	_sphere(0.025, Vector3(0.09, 2.32, -1.747), Color(0.12, 0.09, 0.07))
	_box(Vector3(0.12, 0.025, 0.02), Vector3(0, 2.2, -1.74), Color(0.35, 0.17, 0.12))
	_box(Vector3(0.42, 0.13, 0.35), Vector3(0, 2.49, -1.99), Color(0.18, 0.11, 0.07))
	_box(Vector3(0.2, 0.12, 0.02), Vector3(-0.14, 1.7, -1.81), _CREAM)


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


func _label_3d(text: String, pos: Vector3, font_size: int, pixel_size: float, color: Color, yaw: float = 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.shaded = false
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
	_shop_button = Button.new()
	_shop_button.text = "New parts (P)"
	_shop_button.set_anchors_preset(Control.PRESET_CENTER)
	_shop_button.offset_left = -85
	_shop_button.offset_right = 85
	_shop_button.offset_top = -18
	_shop_button.offset_bottom = 18
	_shop_button.pressed.connect(_open_catalog)
	bar.add_child(_shop_button)
	var depart := _PlaceDeparture.add_to(bar)
	_back = depart["back"] as Button
	_town = depart["town"] as Button
	_back.pressed.connect(_leave.bind(true))
	_town.pressed.connect(_leave.bind(false))

	_catalog = PanelContainer.new()
	_catalog.name = "Catalog"
	_catalog.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_catalog.offset_left = 18
	_catalog.offset_right = 468
	_catalog.offset_top = 18
	_catalog.offset_bottom = -68
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
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "ROYAL RODS  —  NEW PARTS"
	title.add_theme_font_size_override(&"font_size", 22)
	column.add_child(title)
	var note := Label.new()
	note.text = "New, 100% condition. Bought parts go to your spares."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	_catalog_list = VBoxContainer.new()
	_catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_catalog_list)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var close := Button.new()
	close.text = "Close catalog (Esc)"
	close.pressed.connect(_close_catalog)
	column.add_child(close)
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
			var button := Button.new()
			button.text = "%s  —  $%d" % [str(part.get("name", part["id"])), int(part.get("price", 0))]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(_buy.bind(str(group[1]), str(part["id"])))
			_catalog_list.add_child(button)
	_catalog.visible = false
	_nav.setup([_shop_button, _back, _town])


func _open_catalog() -> void:
	if _catalog.visible:
		return
	_catalog.visible = true
	_status.text = "Choose an item to buy."
	var buttons := _nav.collect_buttons(_catalog)
	_nav.setup(buttons)


func _close_catalog() -> void:
	_catalog.visible = false
	_nav.setup([_shop_button, _back, _town])


func _buy(kind: String, id: String) -> void:
	var error := GameState.buy_new_part(kind, id)
	if error.is_empty():
		_status.text = "Bought %s. It's in your spare parts." % str(GameState.listing_for(kind, id).get("name", id))
		_refresh_cash()
	else:
		_status.text = error


func _refresh_cash() -> void:
	_cash.text = "Bankroll: $%d" % GameState.money
