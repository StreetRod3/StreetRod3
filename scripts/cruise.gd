extends Node3D

## A short automatic drive between two places on the city map, or a free drive around it.
## The automatic drive follows the route and plans its speed for the corners. The car rides
## on its own springs and shocks: the body leans and dives over wheels that roll and steer,
## and the camera hangs back. Free roam uses the same city and the race car's own driving.
## Other cars drive the streets in a lane and turn off at random.

const CITY_MAP := "res://assets/maps/city.trk"
const _StreetScenery := preload("res://scripts/street_scenery.gd")
const _CAR_SCENE := preload("res://scenes/car_vehicle_visual.tscn")
const _EngineSound := preload("res://scripts/engine_sound.gd")
const _VehicleDynamics := preload("res://scripts/vehicle_dynamics.gd")
const _CarBodyMotion := preload("res://scripts/car_body_motion.gd")
const _ChaseCamera := preload("res://scripts/chase_camera.gd")
const _PlayerCar := preload("res://scripts/player_race_car.gd")
const _RpmMeter := preload("res://scripts/rpm_meter.gd")
const _TouchControls := preload("res://scripts/race_touch_controls.gd")
const _StreetLamp := preload("res://scripts/street_lamp.gd")
const _CruiseTraffic := preload("res://scripts/cruise_traffic.gd")
const _CruiseMinimap := preload("res://scripts/cruise_minimap.gd")
## Spawn at least this far from the place just left, toward the street, in meters.
const _ROAM_CLEAR := 8.5
## A stop in front of a place. Faster than this is still driving past.
const _ROAM_STOP := 1.0
## The roam car's body origin sits this far behind the middle of the car.
const _ROAM_NOSE := 1.9

const _BODY_Y := 0.35
const _LOOK_AHEAD := 6.0
## Corner radius through a junction. Kept inside the width of the street.
const _TURN_RADIUS := 14.0
const _FADE_IN_S := 0.28
const _FADE_OUT_S := 0.28
const _TOP_SPEED := 26.0
## How the driver pulls away and brakes, in m/s². Brisk, but the car's tires set the corners,
## so better tires make the drive quicker.
const _DRIVE_ACCEL := 6.0
const _DRIVE_BRAKE := 8.0
const _CORNER_GRIP_USE := 0.88
## The road is read this far either side of a point to judge how tight it is, in meters.
const _CURVE_SPAN := 3.0
## Slowest the plan moves at, so the car gets away from a standing start and reaches the end.
const _CREEP_SPEED := 2.0
## Turn rate that shows as a full steering input, in rad/s.
const _FULL_STEER_YAW_RATE := 0.8
const _LONGEST_RIDE_STEP_S := 1.0 / 30.0

const _ROAD_COLOR := Color(0.32, 0.33, 0.35, 1)
const _EDGE_COLOR := Color(0.86, 0.84, 0.78, 1)
const _LANE_COLOR := Color(0.95, 0.86, 0.45, 1)
## Streets at least this wide, from the center to the curb, get two lanes.
const _TWO_LANE_HALF := 6.0
const _LANE_DASH := 3.2
const _LANE_GAP := 2.6
## White line sits this far inside the pavement edge. Its half-width is `_CURB_HALF`.
const _CURB_FROM_EDGE := 0.28
const _CURB_HALF := 0.12
const _GROUND_COLOR := Color(0.2, 0.28, 0.18, 1)
const _BLOCK_COLOR := Color(0.45, 0.42, 0.38, 1)
const _BUSH_DARK := Color(0.14, 0.32, 0.13)
const _BUSH_MID := Color(0.24, 0.42, 0.17)
## Past the curb, in meters. The lamp head reaches back over the gutter.
const _LAMP_SETBACK := 0.95
## The pole's base must sit at least this far off every paved edge.
const _LAMP_CLEAR := 0.4
const _LAMP_EVERY := 18.0
const _BUSH_EVERY := 6.4
## The street drag's trees, on the grass this far past the curb, and about this far apart.
const _TREE_SETBACK := 5.5
const _TREE_EVERY := 36.0
const _FRAME_COLOR := Color(0.15, 0.14, 0.13)
const _STOOP_COLOR := Color(0.58, 0.56, 0.52)
const _DOOR_COLORS: Array[Color] = [
	Color(0.34, 0.16, 0.12),
	Color(0.15, 0.28, 0.42),
	Color(0.2, 0.28, 0.22),
	Color(0.42, 0.26, 0.14),
	Color(0.3, 0.14, 0.18),
]
const _SIGN_COLORS: Array[Color] = [
	Color(0.1, 0.24, 0.48),
	Color(0.55, 0.08, 0.1),
	Color(0.12, 0.34, 0.22),
	Color(0.45, 0.2, 0.08),
	Color(0.24, 0.14, 0.36),
]
## Each place is built with its front on local z = 0. Local -Z faces the street.
const _SHOP_WALL := Color(0.62, 0.58, 0.52)
const _SHOP_DOOR := Color(0.4, 0.43, 0.48)
const _DINER_WALL := Color(0.84, 0.78, 0.68)
const _DINER_RED := Color(0.62, 0.08, 0.09)
const _GAS_BLUE := Color(0.16, 0.32, 0.62)
const _GAS_YELLOW := Color(0.95, 0.78, 0.16)
const _DOOR_SWING := 1.75
const _DOOR_OPEN_S := 1.1

var _car: CharacterBody3D
var _pivot: Node3D
var _camera: Camera3D
var _cam_rest := Transform3D.IDENTITY
var _chase_cam: _ChaseCamera = _ChaseCamera.new()
var _dynamics: _VehicleDynamics
var _body_motion: _CarBodyMotion = _CarBodyMotion.new()
var _engine: AudioStreamPlayer
var _shade: ColorRect
var _pts: PackedVector3Array = PackedVector3Array()
var _dists: PackedFloat32Array = PackedFloat32Array()
var _length: float = 0.0
## Planned speed at each point of `_pts`, in m/s.
var _plan: PackedFloat32Array = PackedFloat32Array()
var _corner_accel: float = 8.0
var _along: float = 0.0
var _speed: float = 0.0
var _yaw_rate: float = 0.0
var _road_y: float = 0.0
var _fade: float = 1.0
var _phase: int = 0
var _destination: String = ""
var _streets: Array[Dictionary] = []
var _garage_left: Node3D
var _garage_right: Node3D
var _leaving_garage := false
var _finished := false
var _roaming := false
var _roam_car: CharacterBody3D
var _roam_home := ""
var _roam_home_clear := false
var _roam_done := false
var _wrecked := false
var _roam_doors_shut := false
## Each place's front apron: id, origin, facing, right, half_width, depth.
var _roam_places: Array[Dictionary] = []
var _hud_speed: Label
var _hud_gear: Label
var _hud_damage: Label
var _hud_hint: Label
var _rpm_meter: Control
var _minimap: Control
var _touch: Node


func _ready() -> void:
	GameState.update_music()
	var from_roam := GameState.roam_from_poi
	if not from_roam.is_empty():
		GameState.roam_from_poi = ""
		_start_roam(from_roam)
		return
	var destination := GameState.cruise_scene
	var from_poi := GameState.cruise_from_poi
	var to_poi := GameState.cruise_to_poi
	_leaving_garage = from_poi == GameState.POI_GARAGE
	GameState.cruise_from_poi = ""
	GameState.cruise_to_poi = ""
	GameState.cruise_scene = ""
	_destination = destination if not destination.is_empty() else GameState.SCENE_GARAGE
	_build_world()
	_build_fade()
	var track := TrackFile.load_path(CITY_MAP)
	var errors: Array = track.get("errors", [])
	var route: Array[Vector3] = []
	if errors.is_empty():
		route = TrackFile.cruise_route(track, from_poi, to_poi)
	if route.size() < 2:
		for err: String in errors:
			push_error(str(err))
		if errors.is_empty():
			push_error("No city route from %s to %s." % [from_poi, to_poi])
		set_process(false)
		call_deferred(&"_finish")
		return
	_build_city(track)
	_bake(route)
	_build_car()
	_plan_speeds()
	_place_car(0.0)
	_yaw_rate = 0.0
	_chase_cam.settle(_car.rotation.y)
	_chase_cam.place(_camera, _car, _pivot.position, _cam_rest, Vector3.ZERO, 0.0)
	if GameState.engine_runs():
		_engine = _EngineSound.new()
		_car.add_child(_engine)
		_engine.set_state(900.0, 0.2, false)
		GameState.set_music_dimmed(true)
	if _leaving_garage:
		_set_garage_doors_open()
	_start_traffic(track, _car.global_position)


func _unhandled_input(event: InputEvent) -> void:
	if _wrecked:
		if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			_leave_after_wreck()
		return
	if _roaming or _finished or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_SPACE:
		return
	get_viewport().set_input_as_handled()
	_finish()


func _process(delta: float) -> void:
	_update_hud()
	if _minimap != null and _roam_car != null:
		_minimap.call(&"set_view", _roam_car.global_position, _roam_car.rotation.y)
	if _roaming:
		_fade = maxf(_fade - delta / _FADE_IN_S, 0.0)
		_paint_fade()
		if _fade <= 0.0 and _leaving_garage and not _roam_doors_shut:
			_roam_doors_shut = true
			_close_garage_doors()
		if _check_roam_wreck():
			return
		_check_roam_arrival()
		return
	if _phase == 0:
		_fade = maxf(_fade - delta / _FADE_IN_S, 0.0)
		_paint_fade()
		_ride(delta)
		if _fade <= 0.0:
			_phase = 1
			if _leaving_garage:
				_close_garage_doors()
		return
	if _phase == 1:
		_speed = maxf(_planned_speed(_along), _CREEP_SPEED)
		_along = minf(_along + _speed * delta, _length)
		_place_car(_along)
		_update_engine()
		if _along >= _length:
			_phase = 2
			_speed = 0.0
		_ride(delta)
		return
	_ride(delta)
	_fade = minf(_fade + delta / _FADE_OUT_S, 1.0)
	_paint_fade()
	if _fade >= 1.0:
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	set_process_unhandled_input(false)
	GameState.set_music_dimmed(false)
	if _engine != null and is_instance_valid(_engine):
		_engine.stop()
	GameState.current_scene_path = _destination
	get_tree().change_scene_to_file(_destination)


## The road's height where the car is. The suspension reads this for each wheel.
func surface_height(_world: Vector3) -> float:
	return _road_y


## Runs the springs and shocks from how the car is moving, and poses it and the camera.
func _ride(delta: float) -> void:
	if _car == null or _dynamics == null or delta <= 0.0:
		return
	var step := minf(delta, _LONGEST_RIDE_STEP_S)
	var yaw := _car.rotation.y
	var velocity := Vector3(sin(yaw), 0.0, cos(yaw)) * _speed
	_dynamics.sample_surfaces(self, _car.global_transform)
	_body_motion.ride_from_motion(step, velocity, yaw)
	# Not before the first frame: the visuals are fitted to the floor once `_ready` is done.
	_body_motion.capture()
	var steer := atan(_yaw_rate * _dynamics.config.wheelbase_m / maxf(_speed, 1.0))
	_body_motion.pose(delta, _speed, steer, clampf(_yaw_rate / _FULL_STEER_YAW_RATE, -1.0, 1.0))
	_chase_cam.place(_camera, _car, _pivot.position, _cam_rest, velocity, delta)


func _start_roam(from_poi: String) -> void:
	_roaming = true
	_roam_home = from_poi
	_leaving_garage = from_poi == GameState.POI_GARAGE
	_build_world()
	_build_fade()
	var track := TrackFile.load_path(CITY_MAP)
	var errors: Array = track.get("errors", [])
	if not errors.is_empty():
		for err: String in errors:
			push_error(str(err))
		_enter_roam_place(GameState.POI_GARAGE)
		return
	_build_city(track)
	if _leaving_garage:
		_set_garage_doors_open()
	_build_hud(track)
	_build_roam_car(track, from_poi)
	if _touch != null and _roam_car != null:
		_roam_car.set(&"_touch", _touch)
	if _roam_car != null:
		_start_traffic(track, _roam_car.global_position)
	if GameState.engine_runs():
		GameState.set_music_dimmed(true)


func _start_traffic(track: Dictionary, avoid: Vector3) -> void:
	var files: Array[String] = []
	for car: Dictionary in GameState.USED_CARS:
		var path := str(car.get("car_file", ""))
		if not path.is_empty():
			files.append(path)
	if files.is_empty():
		files.append("res://assets/cars/chevy-styleline-1950.car")
	var traffic := _CruiseTraffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(track, avoid, _floor, files)


## The apron in front of a place. Local -Z of the building faces the street.
func _note_roam_front(place_id: String, root: Node3D) -> void:
	var facing := -root.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3(0.0, 0.0, 1.0)
	else:
		facing = facing.normalized()
	var right := root.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3(1.0, 0.0, 0.0)
	else:
		right = right.normalized()
	var origin := root.global_position
	origin.y = 0.0
	_roam_places.append({
		"id": place_id,
		"origin": origin,
		"facing": facing,
		"right": right,
		"half_width": _front_half_width(place_id),
		"depth": _front_depth(place_id),
	})


func _front_half_width(place_id: String) -> float:
	match place_id:
		GameState.POI_GARAGE:
			return 6.2
		GameState.POI_DRIVE_IN:
			return 8.8
		GameState.POI_GAS_STATION:
			return 5.4
		_:
			return 6.5


func _front_depth(place_id: String) -> float:
	match place_id:
		GameState.POI_GARAGE:
			return 8.0
		GameState.POI_DRIVE_IN:
			return 6.3
		GameState.POI_GAS_STATION:
			return 5.6
		_:
			return 6.5


func _build_roam_car(track: Dictionary, from_poi: String) -> void:
	var spawn := _roam_spawn(track, from_poi)
	var body := CharacterBody3D.new()
	body.name = "PlayerCar"
	body.set_script(_PlayerCar)
	body.collision_layer = 2
	body.collision_mask = 1
	var pos: Vector3 = spawn["pos"]
	body.position = pos
	body.rotation.y = float(spawn["yaw"])
	var pivot := _CAR_SCENE.instantiate() as Node3D
	pivot.name = "CarPivot"
	pivot.position = Vector3(0.0, 0.0, 1.9)
	body.add_child(pivot)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.5, 3.8)
	shape.shape = box
	shape.position = Vector3(0.0, 0.0, 1.9)
	body.add_child(shape)
	var sound := AudioStreamPlayer.new()
	sound.name = "EngineSound"
	sound.set_script(_EngineSound)
	body.add_child(sound)
	var cam := Camera3D.new()
	cam.name = "RaceCamera"
	cam.position = Vector3(0.0, 2.2, -8.5)
	cam.rotation_degrees = Vector3(-14.0, 180.0, 0.0)
	cam.current = true
	body.add_child(cam)
	var dyn := Node.new()
	dyn.name = "VehicleDynamics"
	dyn.set_script(_VehicleDynamics)
	body.add_child(dyn)
	add_child(body)
	_roam_car = body
	if _floor != null and pivot.has_method(&"align_wheels_to_floor"):
		pivot.call(&"align_wheels_to_floor", _floor)


## On the driveway, facing the street, and clear of the apron that opens the place just left.
func _roam_spawn(track: Dictionary, from_poi: String) -> Dictionary:
	var pois: Dictionary = track["pois"]
	var poi: Dictionary = pois.get(from_poi, {})
	if poi.is_empty():
		var order: Array = track["poi_order"]
		poi = pois[str(order[0])]
	var stop := TrackFile.world_position(poi)
	var join := TrackFile.world_position(track["nodes"][int(poi["at"])])
	var to_street := join - stop
	to_street.y = 0.0
	var gap := to_street.length()
	if gap < 0.5:
		to_street = Vector3(0.0, 0.0, 1.0)
		gap = 1.0
	else:
		to_street /= gap
	var along := clampf(gap * 0.35, _ROAM_CLEAR, maxf(gap - 4.0, _ROAM_CLEAR))
	var pos := stop + to_street * along
	pos.y = 0.35
	return {"pos": pos, "yaw": atan2(to_street.x, to_street.z)}


func _check_roam_arrival() -> void:
	if _roam_done or _roam_car == null:
		return
	var here := _roam_center()
	if not _roam_home_clear and not _parked_at(_roam_home, here):
		_roam_home_clear = true
	if absf(float(_roam_car.call(&"get_forward_speed"))) > _ROAM_STOP:
		return
	var place := _roam_place_at(here)
	if place.is_empty() or (place == _roam_home and not _roam_home_clear):
		return
	_enter_roam_place(place)


func _roam_center() -> Vector3:
	var center := _roam_car.global_position + _roam_car.global_transform.basis.z * _ROAM_NOSE
	center.y = 0.0
	return center


func _roam_place_at(here: Vector3) -> String:
	var best := ""
	var best_ahead := INF
	for spot: Dictionary in _roam_places:
		if not _point_in_front(spot, here):
			continue
		if _scene_for_roam(str(spot["id"])).is_empty():
			continue
		var origin: Vector3 = spot["origin"]
		var facing: Vector3 = spot["facing"]
		var ahead := Vector3(here.x - origin.x, 0.0, here.z - origin.z).dot(facing)
		if ahead >= best_ahead:
			continue
		best_ahead = ahead
		best = str(spot["id"])
	return best


func _parked_at(place_id: String, here: Vector3) -> bool:
	for spot: Dictionary in _roam_places:
		if str(spot["id"]) != place_id:
			continue
		return _point_in_front(spot, here)
	return false


## `ahead` runs from the front wall toward the street. The wall itself does not count.
func _point_in_front(spot: Dictionary, here: Vector3) -> bool:
	var origin: Vector3 = spot["origin"]
	var facing: Vector3 = spot["facing"]
	var right: Vector3 = spot["right"]
	var rel := Vector3(here.x - origin.x, 0.0, here.z - origin.z)
	var side := rel.dot(right)
	var ahead := rel.dot(facing)
	if absf(side) > float(spot["half_width"]):
		return false
	return ahead >= 0.4 and ahead <= float(spot["depth"])


func _enter_roam_place(place_id: String) -> void:
	var scene := _scene_for_roam(place_id)
	if scene.is_empty() or _roam_done:
		return
	_roam_done = true
	set_process(false)
	if _roam_car != null:
		_roam_car.set_physics_process(false)
	GameState.set_music_dimmed(false)
	GameState.roam_from_poi = ""
	if place_id == GameState.POI_GARAGE:
		GameState.drive_into_garage = true
	GameState.current_scene_path = scene
	get_tree().change_scene_to_file(scene)


func _scene_for_roam(place_id: String) -> String:
	if place_id == GameState.POI_GARAGE:
		return GameState.SCENE_GARAGE
	if place_id == GameState.POI_DRIVE_IN:
		return GameState.SCENE_DRIVE_IN
	if place_id == GameState.POI_GAS_STATION:
		return GameState.SCENE_GAS_STATION
	return ""


## The race cluster while the player is driving. A scripted cruise stays clear.
func _build_hud(track: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.name = "CruiseUI"
	layer.layer = 10
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -332.0
	panel.offset_top = 12.0
	panel.offset_right = -12.0
	panel.offset_bottom = 300.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override(&"margin_left", 12)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_right", 12)
	margin.add_theme_constant_override(&"margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "VBox"
	box.add_theme_constant_override(&"separation", 6)
	margin.add_child(box)
	_hud_speed = _hud_line("Speed: 0 km/h")
	_hud_speed.name = "SpeedLabel"
	_hud_gear = _hud_line("Gear: —")
	_hud_gear.name = "GearLabel"
	_hud_damage = _hud_line("Damage: 0%")
	_hud_damage.name = "DamageLabel"
	_hud_hint = _hud_line(_drive_hint())
	_hud_hint.name = "HintLabel"
	_hud_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_hint.custom_minimum_size = Vector2(280.0, 0.0)
	box.add_child(_hud_speed)
	box.add_child(_hud_gear)
	box.add_child(_hud_damage)
	box.add_child(_hud_hint)
	var meter := Control.new()
	meter.name = "RpmMeter"
	meter.set_script(_RpmMeter)
	meter.anchor_left = 0.5
	meter.anchor_right = 0.5
	meter.anchor_top = 1.0
	meter.anchor_bottom = 1.0
	meter.offset_left = -150.0
	meter.offset_top = -196.0
	meter.offset_right = 150.0
	meter.offset_bottom = -16.0
	meter.grow_horizontal = Control.GROW_DIRECTION_BOTH
	meter.grow_vertical = Control.GROW_DIRECTION_BEGIN
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(meter)
	_rpm_meter = meter
	var touch := Control.new()
	touch.name = "MobileControls"
	touch.set_script(_TouchControls)
	layer.add_child(touch)
	_touch = touch
	_minimap = Control.new()
	_minimap.name = "Minimap"
	_minimap.set_script(_CruiseMinimap)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.z_index = 1
	_minimap.call(&"set_track", track)
	layer.add_child(_minimap)
	_layout_minimap()
	get_viewport().size_changed.connect(_layout_minimap)


func _layout_minimap() -> void:
	if _minimap == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var mobile := OS.has_feature("mobile") or viewport_size.x <= 900.0 or viewport_size.x < viewport_size.y
	var map_size := 128.0 if mobile else 156.0
	var bottom_margin := 212.0 if mobile else 16.0
	_minimap.anchor_left = 1.0
	_minimap.anchor_right = 1.0
	_minimap.anchor_top = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left = -map_size - 16.0
	_minimap.offset_right = -16.0
	_minimap.offset_top = -bottom_margin - map_size
	_minimap.offset_bottom = -bottom_margin
	_minimap.size = Vector2(map_size, map_size)


func _hud_line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _drive_hint() -> String:
	var box := GameState.get_equipped_gearbox()
	if bool(box.get("automatic", false)):
		return "W / Up: throttle · S / Down: brake · Space: hand brake · A/D or arrows: steer · Q/E: drive, neutral, reverse · C: camera · W+S: burnout\nStop in front of a place to go in"
	return "W / Up: throttle · S / Down: brake · Space: hand brake · A/D or arrows: steer · Q/E: shift · C: camera · W+S: burnout\nStop in front of a place to go in"


func _update_hud() -> void:
	if _hud_speed == null:
		return
	if _roaming and _roam_car != null and _roam_car.has_method(&"get_forward_speed"):
		var speed := absf(float(_roam_car.call(&"get_forward_speed")))
		_hud_speed.text = "Speed: %s" % GameState.speed_text(speed * 3.6)
		_hud_gear.text = "Gear: %s" % str(_roam_car.call(&"get_gear_label"))
		_hud_damage.text = "Damage: %d%%" % roundi(float(_roam_car.call(&"damage_amount")) * 100.0)
		if _rpm_meter != null and _rpm_meter.has_method(&"set_reading"):
			_rpm_meter.call(
				&"set_reading",
				float(_roam_car.call(&"get_rpm")),
				float(_roam_car.call(&"get_rpm_shift_start")),
				float(_roam_car.call(&"get_rpm_redline")),
				float(_roam_car.call(&"get_rpm_critical")),
				bool(_roam_car.call(&"is_engine_blown"))
			)
		return


func _check_roam_wreck() -> bool:
	if _wrecked or _roam_done or _roam_car == null:
		return _wrecked
	if not _roam_car.has_method(&"is_wrecked") or not bool(_roam_car.call(&"is_wrecked")):
		return false
	_wrecked = true
	_roam_done = true
	_roam_car.set_physics_process(false)
	var engine := _roam_car.get_node_or_null("EngineSound") as AudioStreamPlayer
	if engine != null:
		engine.stop()
	GameState.set_music_dimmed(false)
	GameState.wreck_active_car()
	_fade = 1.0
	_paint_fade()
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var label := Label.new()
	label.name = "WreckLabel"
	label.text = "Lucky you weren't killed, 'cause the car is totaled."
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.78))
	label.add_theme_font_size_override(&"font_size", 28)
	layer.add_child(label)
	return true


func _leave_after_wreck() -> void:
	GameState.drive_into_garage = false
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


func _add_solid(parent: Node3D, size: Vector3, pos: Vector3, barrier := false) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	if barrier:
		body.set_meta(&"track_obstacle", true)
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


func _add_solid_world(pos: Vector3, size: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "GroundBody"
	add_child(holder)
	_add_solid(holder, size, pos)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.35, 0.55)
	sky_mat.sky_horizon_color = Color(0.55, 0.6, 0.65)
	sky_mat.ground_bottom_color = Color(0.15, 0.16, 0.18)
	sky_mat.ground_horizon_color = Color(0.4, 0.42, 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.5, 0.52, 0.55)
	env.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _build_city(track: Dictionary) -> void:
	var ground := _build_ground(track)
	add_child(ground)
	var ground_box := ground.mesh as BoxMesh
	if ground_box != null:
		_add_solid_world(ground.position, ground_box.size)
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = _ROAD_COLOR
	road_mat.roughness = 0.92
	road_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var roads := MeshInstance3D.new()
	var edges := MeshInstance3D.new()
	var lanes := MeshInstance3D.new()
	var built := _road_meshes(track)
	roads.mesh = built[0]
	edges.mesh = built[1]
	lanes.mesh = built[2]
	roads.material_override = road_mat
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = _EDGE_COLOR
	edge_mat.roughness = 0.8
	edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	edges.material_override = edge_mat
	var lane_mat := StandardMaterial3D.new()
	lane_mat.albedo_color = _LANE_COLOR
	lane_mat.roughness = 0.7
	lane_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lanes.material_override = lane_mat
	add_child(roads)
	add_child(edges)
	add_child(lanes)
	_build_places(track)
	_build_blocks(track)
	_build_streetscape(track)
	_floor = ground


var _floor: MeshInstance3D


func _build_ground(track: Dictionary) -> MeshInstance3D:
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0
	var first := true
	var points: Array[Vector3] = []
	for id: int in track["nodes"]:
		points.append(TrackFile.world_position(track["nodes"][id]))
	for pid: String in track["poi_order"]:
		points.append(TrackFile.world_position(track["pois"][pid]))
	for point in points:
		if first:
			min_x = point.x
			max_x = point.x
			min_z = point.z
			max_z = point.z
			first = false
		else:
			min_x = minf(min_x, point.x)
			max_x = maxf(max_x, point.x)
			min_z = minf(min_z, point.z)
			max_z = maxf(max_z, point.z)
	var pad := 40.0
	var box := BoxMesh.new()
	box.size = Vector3(max_x - min_x + pad * 2.0, 1.0, max_z - min_z + pad * 2.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = _GROUND_COLOR
	ground_mat.roughness = 0.95
	box.material = ground_mat
	var ground := MeshInstance3D.new()
	ground.mesh = box
	ground.position = Vector3((min_x + max_x) * 0.5, -0.5, (min_z + max_z) * 0.5)
	return ground


func _road_meshes(track: Dictionary) -> Array:
	var asphalt := SurfaceTool.new()
	var marks := SurfaceTool.new()
	var lanes := SurfaceTool.new()
	asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	marks.begin(Mesh.PRIMITIVE_TRIANGLES)
	lanes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: Array[Dictionary] = []
	var links: Dictionary = {}
	var seen := {}
	var nodes: Dictionary = track["nodes"]
	for road: Dictionary in track["roads"]:
		var a_id := int(road["from"])
		var b_id := int(road["to"])
		var key := "%d-%d" % [mini(a_id, b_id), maxi(a_id, b_id)]
		if seen.has(key):
			continue
		seen[key] = true
		var half := maxf(float(road["width"]) * 0.5, 1.0)
		_add_street(segments, links, a_id, b_id, TrackFile.world_position(nodes[a_id]), TrackFile.world_position(nodes[b_id]), half)
	for pid: String in track["poi_order"]:
		var poi: Dictionary = track["pois"][pid]
		var stop := TrackFile.world_position(poi)
		var at_id := int(poi["at"])
		var join := TrackFile.world_position(nodes[at_id])
		if stop.distance_squared_to(join) > 0.25:
			_add_street(segments, links, -1, at_id, stop, join, 4.5)
	for segment in segments:
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var half_w := float(segment["half"])
		_add_ribbon(asphalt, a, b, half_w, 0.03 if int(segment["a_node"]) >= 0 else 0.04)
		var span := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var length := span.length()
		if length < 0.2:
			continue
		var dir := span / length
		var side := dir.cross(Vector3.UP)
		var inset := maxf(half_w - _CURB_FROM_EDGE, _CURB_HALF * 2.0)
		var a_node := int(segment["a_node"])
		var b_node := int(segment["b_node"])
		for sign_i in 2:
			var sign := -1.0 if sign_i == 0 else 1.0
			var side_dir := side * sign
			var trim_a := _curb_trim(links, a_node, side_dir)
			var trim_b := _curb_trim(links, b_node, side_dir)
			if trim_a + trim_b + 0.3 >= length:
				continue
			var shift := side_dir * inset
			_add_ribbon(marks, a + dir * trim_a + shift, b - dir * trim_b + shift, _CURB_HALF, 0.05)
		if half_w >= _TWO_LANE_HALF:
			var stop_a := _junction_half(links, a_node, dir)
			var stop_b := _junction_half(links, b_node, -dir)
			_add_lane_dashes(lanes, a, b, stop_a, stop_b)
	_streets = segments
	asphalt.generate_normals()
	marks.generate_normals()
	lanes.generate_normals()
	return [asphalt.commit(), marks.commit(), lanes.commit()]


func _add_street(segments: Array[Dictionary], links: Dictionary, a_id: int, b_id: int, a: Vector3, b: Vector3, half: float) -> void:
	var span := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if span.length_squared() < 0.01:
		return
	var dir := span.normalized()
	segments.append({
		"a": a,
		"b": b,
		"half": half,
		"a_node": a_id,
		"b_node": b_id,
	})
	_note_link(links, a_id, dir, half)
	_note_link(links, b_id, -dir, half)


## Poles just outside the curb, shrubs on the grass, and the street drag's trees behind those.
func _build_streetscape(track: Dictionary) -> void:
	var blocks: Array = track.get("buildings", [])
	var keep_out: Array[Vector3] = []
	for pid: String in track["poi_order"]:
		keep_out.append(TrackFile.world_position(track["pois"][pid]))
	var lamps: Array[Dictionary] = []
	var dark_bush: Array[Transform3D] = []
	var mid_bush: Array[Transform3D] = []
	var trees: Array[Vector2] = []
	var big_trees: Array[Vector2] = []
	var bare_trees: Array[Vector2] = []
	var lamp_cells := {}
	var bush_cells := {}
	var tree_cells := {}
	for segment in _streets:
		if int(segment["a_node"]) < 0:
			continue
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var half := float(segment["half"])
		var span := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var length := span.length()
		if length < 14.0:
			continue
		var dir := span / length
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			continue
		side = side.normalized()
		var margin := half + 2.0
		var usable := length - margin * 2.0
		if usable < 4.0:
			continue
		var lamp_count := maxi(int(floor(usable / _LAMP_EVERY)) + 1, 1)
		var lamp_step := usable / float(lamp_count)
		for i in lamp_count:
			var center := a + dir * (margin + lamp_step * (float(i) + 0.5))
			for sign: float in [-1.0, 1.0]:
				var outward := side * sign
				var pos := center + outward * (half + _LAMP_SETBACK)
				pos.y = 0.0
				if not _claim_cell(lamp_cells, pos, 5.0):
					continue
				if _lot_blocked(Vector2(pos.x, pos.z), 0.5, blocks, keep_out):
					continue
				if _on_pavement(Vector2(pos.x, pos.z), _LAMP_CLEAR):
					continue
				lamps.append({"at": pos, "toward": -outward})
		var bush_count := maxi(int(floor(usable / _BUSH_EVERY)) + 1, 1)
		var bush_step := usable / float(bush_count)
		for i in bush_count:
			var center := a + dir * (margin + bush_step * (float(i) + 0.5))
			for sign_i in 2:
				var sign := -1.0 if sign_i == 0 else 1.0
				var outward := side * sign
				for ring_i in 2:
					if ring_i == 1 and (i + sign_i) % 2 == 1:
						continue
					var setback := 2.25 if ring_i == 0 else 4.15
					var n := _facade_hash(int(center.x * 3.0) + sign_i, int(center.z * 3.0), ring_i, i)
					var pos := center + outward * (half + setback) + dir * (float(n % 5) - 2.0) * 0.22
					pos.y = 0.0
					if not _claim_cell(bush_cells, pos, 2.2):
						continue
					var radius := 0.58 + float(n % 4) * 0.1
					if _lot_blocked(Vector2(pos.x, pos.z), radius + 0.2, blocks, keep_out):
						continue
					if _on_pavement(Vector2(pos.x, pos.z), radius):
						continue
					var pile: Array[Transform3D] = dark_bush if n % 2 == 0 else mid_bush
					_place_bush(pile, pos, radius, 0.0)
					_place_bush(pile, pos + outward * 0.22 + dir * 0.28, radius * 0.72, 0.05)
					_place_bush(pile, pos - dir * 0.16, radius * 0.55, radius * 0.35)
		if usable < 16.0:
			continue
		var tree_count := maxi(int(floor(usable / _TREE_EVERY)), 1)
		var tree_step := usable / float(tree_count)
		for i in tree_count:
			var center := a + dir * (margin + tree_step * (float(i) + 0.5))
			for sign_i in 2:
				var n := _facade_hash(int(center.x * 2.0) + sign_i, int(center.z * 2.0), i, sign_i)
				if n % 3 == 0:
					continue
				var sign := -1.0 if sign_i == 0 else 1.0
				var pos := center + side * sign * (half + _TREE_SETBACK)
				pos.y = 0.0
				if not _claim_cell(tree_cells, pos, 8.0):
					continue
				if _lot_blocked(Vector2(pos.x, pos.z), 3.6, blocks, keep_out, 20.0):
					continue
				var spot := Vector2(pos.x, pos.z)
				var kind := n % 5
				if kind == 0:
					bare_trees.append(spot)
				elif kind == 1:
					big_trees.append(spot)
				else:
					trees.append(spot)
	var root := Node3D.new()
	root.name = "Streetscape"
	add_child(root)
	for spec: Dictionary in lamps:
		var lamp := Node3D.new()
		lamp.set_script(_StreetLamp)
		root.add_child(lamp)
		lamp.call(&"setup", spec["at"], spec["toward"])
	var shrub := SphereMesh.new()
	shrub.radius = 1.0
	shrub.height = 2.0
	shrub.radial_segments = 8
	shrub.rings = 5
	_add_multimesh(root, shrub, _facade_material(_BUSH_DARK, 0.92, 0.0), dark_bush, false)
	_add_multimesh(root, shrub, _facade_material(_BUSH_MID, 0.9, 0.0), mid_bush, false)
	_StreetScenery.add_flat_trees(root, trees, big_trees, bare_trees)
	_add_tree_barriers(root, trees, 0.22, 5.5)
	_add_tree_barriers(root, big_trees, 0.34, 7.5)
	_add_tree_barriers(root, bare_trees, 0.18, 6.5)


## Trunks only. A tree does not get out of the way, and a hard hit wrecks the car.
func _add_tree_barriers(parent: Node3D, spots: Array[Vector2], radius: float, height: float) -> void:
	for spot: Vector2 in spots:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta(&"track_obstacle", true)
		body.position = Vector3(spot.x, height * 0.5 - 0.15, spot.y)
		var shape := CollisionShape3D.new()
		var trunk := CylinderShape3D.new()
		trunk.radius = radius
		trunk.height = height
		shape.shape = trunk
		body.add_child(shape)
		parent.add_child(body)


func _place_bush(pile: Array[Transform3D], pos: Vector3, radius: float, lift: float) -> void:
	if _on_pavement(Vector2(pos.x, pos.z), radius):
		return
	pile.append(_bush_transform(pos, radius, lift))


## A disc overlaps a paved street or a driveway.
func _on_pavement(point: Vector2, clearance: float) -> bool:
	for segment: Dictionary in _streets:
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var gap := _gap_to_segment(point, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if gap < float(segment["half"]) + clearance:
			return true
	return false


func _bush_transform(pos: Vector3, radius: float, lift: float) -> Transform3D:
	var basis := Basis.IDENTITY.scaled(Vector3(radius, radius * 0.78, radius))
	return Transform3D(basis, pos + Vector3(0.0, radius * 0.5 + lift, 0.0))


func _claim_cell(taken: Dictionary, pos: Vector3, cell: float) -> bool:
	var key := "%d:%d" % [int(round(pos.x / cell)), int(round(pos.z / cell))]
	if taken.has(key):
		return false
	taken[key] = true
	return true


func _lot_blocked(point: Vector2, pad: float, blocks: Array, keep_out: Array[Vector3], place_reach: float = 12.0) -> bool:
	for spot: Vector3 in keep_out:
		if Vector2(spot.x, spot.z).distance_to(point) < place_reach:
			return true
	for raw: Dictionary in blocks:
		var hx := float(raw["w"]) * 0.5 + pad
		var hz := float(raw["d"]) * 0.5 + pad
		if absf(point.x - float(raw["x"])) < hx and absf(point.y - float(raw["y"])) < hz:
			return true
	return false


func _add_multimesh(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array[Transform3D], shadow: bool) -> void:
	if xforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = xforms.size()
	for i in xforms.size():
		multi.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = mat
	if not shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


func _note_link(links: Dictionary, node_id: int, dir: Vector3, half: float) -> void:
	if node_id < 0:
		return
	if not links.has(node_id):
		links[node_id] = []
	(links[node_id] as Array).append({"dir": dir, "half": half})


## Distance along a road before its curb meets the curb of a street on `side_dir`.
func _curb_trim(links: Dictionary, node_id: int, side_dir: Vector3) -> float:
	if node_id < 0 or not links.has(node_id):
		return 0.0
	var widest := 0.0
	var found := false
	for raw: Dictionary in links[node_id]:
		var entry: Dictionary = raw
		var dir: Vector3 = entry["dir"]
		if dir.dot(side_dir) <= 0.5:
			continue
		widest = maxf(widest, float(entry["half"]))
		found = true
	if not found:
		return 0.0
	return maxf(widest - _CURB_FROM_EDGE - _CURB_HALF, 0.0)


## How far a center line must stop so it does not run across the side street.
func _junction_half(links: Dictionary, node_id: int, along: Vector3) -> float:
	if node_id < 0 or not links.has(node_id):
		return 0.0
	var along_flat := Vector3(along.x, 0.0, along.z)
	if along_flat.length_squared() < 0.0001:
		return 0.0
	along_flat = along_flat.normalized()
	var widest := 0.0
	for raw: Dictionary in links[node_id]:
		var entry: Dictionary = raw
		var dir: Vector3 = entry["dir"]
		if absf(dir.dot(along_flat)) > 0.85:
			continue
		widest = maxf(widest, float(entry["half"]))
	return widest


func _add_lane_dashes(st: SurfaceTool, a: Vector3, b: Vector3, trim_a: float, trim_b: float) -> void:
	var span := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := span.length()
	if length < trim_a + trim_b + _LANE_DASH:
		return
	var dir := span / length
	var cursor := trim_a
	var end := length - trim_b
	while cursor < end - 0.2:
		var dash_end := minf(cursor + _LANE_DASH, end)
		_add_ribbon(st, a + dir * cursor, a + dir * dash_end, 0.1, 0.06)
		cursor = dash_end + _LANE_GAP


func _add_ribbon(st: SurfaceTool, a: Vector3, b: Vector3, half_w: float, lift: float) -> void:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat.length_squared() < 0.01:
		return
	var side := flat.normalized().cross(Vector3.UP) * half_w
	var y := lift
	var a_l := Vector3(a.x, y, a.z) - side
	var a_r := Vector3(a.x, y, a.z) + side
	var b_l := Vector3(b.x, y, b.z) - side
	var b_r := Vector3(b.x, y, b.z) + side
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a_l)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(a_r)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(b_r)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a_l)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(b_r)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(b_l)


func _build_places(track: Dictionary) -> void:
	var nodes: Dictionary = track["nodes"]
	for pid: String in track["poi_order"]:
		var poi: Dictionary = track["pois"][pid]
		var stop := TrackFile.world_position(poi)
		var join := TrackFile.world_position(nodes[int(poi["at"])])
		var away := stop - join
		away.y = 0.0
		if away.length_squared() < 0.25:
			away = Vector3(0.0, 0.0, 1.0)
		else:
			away = away.normalized()
		var root := Node3D.new()
		root.name = str(poi["name"])
		var place_id := str(poi["id"])
		if place_id == "drive-in" or place_id == "gas-station":
			_place_alongside(root, stop, away)
		else:
			root.position = stop + away * 4.0
			root.rotation.y = atan2(away.x, away.z)
		add_child(root)
		_note_roam_front(place_id, root)
		match place_id:
			"garage":
				_build_garage(root)
			"drive-in":
				_build_drive_in(root)
			"gas-station":
				_build_gas_station(root)
			GameState.POI_ROYAL_RODS:
				_build_royal_rods(root)
			_:
				_add_box(root, Vector3(9.0, 4.2, 7.0), Vector3(0.0, 2.1, 3.5), Color(0.35, 0.35, 0.38))


## The front faces the lane. Local +X runs with the car, left to right across that front.
## A custom shop on the west side of the street up to the drive-in. Local -Z faces that street.
func _build_royal_rods(root: Node3D) -> void:
	_add_solid(root, Vector3(11.6, 4.6, 8.2), Vector3(0.0, 2.3, 4.2), true)
	var wall := Color(0.76, 0.7, 0.6)
	var burgundy := Color(0.48, 0.07, 0.09)
	var gold := Color(1.0, 0.82, 0.28)
	var bay := Color(0.4, 0.42, 0.46)
	_add_box(root, Vector3(11.6, 0.06, 5.2), Vector3(0.0, 0.03, -2.3), Color(0.5, 0.49, 0.46), 0.92)
	_add_box(root, Vector3(11.6, 4.3, 8.0), Vector3(0.0, 2.15, 4.2), wall, 0.88)
	_add_box(root, Vector3(12.1, 0.2, 8.5), Vector3(0.0, 4.4, 4.2), Color(0.22, 0.2, 0.2), 0.86)
	_add_box(root, Vector3(11.6, 0.22, 0.06), Vector3(0.0, 3.9, 0.16), burgundy, 0.45)
	_add_box(root, Vector3(3.8, 3.05, 0.1), Vector3(-3.15, 1.58, 0.16), bay, 0.5, 0.22)
	for i in 5:
		var rib_y := 0.45 + float(i) * 0.52
		_add_box(root, Vector3(3.5, 0.06, 0.04), Vector3(-3.15, rib_y, 0.1), Color(0.62, 0.64, 0.68), 0.4, 0.45)
	_add_box(root, Vector3(1.1, 2.15, 0.1), Vector3(-0.15, 1.12, 0.16), Color(0.16, 0.1, 0.09), 0.5)
	_add_box(root, Vector3(0.08, 0.22, 0.04), Vector3(0.22, 1.08, 0.09), gold, 0.35, 0.65)
	_add_box(root, Vector3(4.2, 2.3, 0.08), Vector3(3.15, 1.85, 0.16), Color(0.72, 0.74, 0.76), 0.32, 0.55)
	_add_box(root, Vector3(3.9, 2.0, 0.04), Vector3(3.15, 1.85, 0.1), Color(0.45, 0.62, 0.78), 0.08, 0.1)
	var metal := Color(0.2, 0.2, 0.22)
	_add_box(root, Vector3(0.1, 1.2, 0.1), Vector3(-3.5, 5.05, 0.25), metal, 0.4, 0.65)
	_add_box(root, Vector3(0.1, 1.2, 0.1), Vector3(3.5, 5.05, 0.25), metal, 0.4, 0.65)
	_add_box(root, Vector3(7.8, 1.15, 0.12), Vector3(0.0, 5.1, 0.2), Color(0.06, 0.03, 0.04))
	_add_box(root, Vector3(7.3, 0.07, 0.04), Vector3(0.0, 5.6, 0.12), gold, 0.3, 0.0, gold, 1.8)
	_add_box(root, Vector3(7.3, 0.07, 0.04), Vector3(0.0, 4.6, 0.12), gold, 0.3, 0.0, gold, 1.8)
	_add_label(root, "ROYAL RODS", Vector3(0.0, 5.1, 0.1), 40, 0.014, Color(2.3, 1.75, 0.45), Color(0.4, 0.1, 0.04), 6)
	_add_light(root, Vector3(0.0, 4.5, -1.6), Color(1.0, 0.78, 0.4), 0.85, 12.0)


func _place_alongside(root: Node3D, stop: Vector3, away: Vector3) -> void:
	root.rotation.y = atan2(-away.z, away.x)
	var side := Vector3(-away.z, 0.0, away.x)
	root.position = stop - away * 4.0 + side * 7.2


func _build_garage(root: Node3D) -> void:
	_add_solid(root, Vector3(11.5, 5.4, 9.0), Vector3(-0.4, 2.7, 4.5), true)
	_add_box(root, Vector3(8.4, 0.06, 4.6), Vector3(-0.3, 0.03, -2.2), Color(0.55, 0.54, 0.5), 0.92)
	_add_box(root, Vector3(3.5, 5.2, 0.32), Vector3(-4.25, 2.6, 0.0), _SHOP_WALL)
	_add_box(root, Vector3(2.0, 5.2, 0.32), Vector3(4.2, 2.6, 0.0), _SHOP_WALL)
	_add_box(root, Vector3(0.32, 5.2, 8.8), Vector3(-5.84, 2.6, 4.4), _SHOP_WALL)
	_add_box(root, Vector3(0.32, 5.2, 8.8), Vector3(5.04, 2.6, 4.4), _SHOP_WALL)
	_add_box(root, Vector3(11.2, 5.2, 0.32), Vector3(-0.4, 2.6, 8.8), _SHOP_WALL)
	_add_box(root, Vector3(5.9, 0.72, 0.32), Vector3(0.35, 4.84, 0.0), _SHOP_WALL)
	_add_box(root, Vector3(11.8, 0.24, 9.3), Vector3(-0.4, 5.44, 4.45), Color(0.34, 0.32, 0.28), 0.92)
	_garage_left = _garage_door(root, -1.05, -1.0)
	_garage_right = _garage_door(root, 1.75, 1.0)
	_add_light(root, Vector3(0.3, 3.4, -4.5), Color(1.0, 0.95, 0.86), 0.7, 14.0)


## `hinge_sign` is -1 for the left leaf and +1 for the right. The hinge is the outer edge.
func _garage_door(root: Node3D, center_x: float, hinge_sign: float) -> Node3D:
	var half := 1.35
	var hinge := Node3D.new()
	hinge.position = Vector3(center_x + hinge_sign * half, 0.0, -0.2)
	root.add_child(hinge)
	var leaf := -hinge_sign * half
	_add_box(hinge, Vector3(2.7, 4.5, 0.1), Vector3(leaf, 2.25, 0.0), _SHOP_DOOR, 0.42, 0.28)
	for i in 4:
		var rib_y := -1.5 + float(i) * 1.0
		_add_box(hinge, Vector3(2.35, 0.07, 0.04), Vector3(leaf, 2.25 + rib_y, -0.07), Color(0.62, 0.64, 0.68), 0.35, 0.5)
	var handle_x := leaf - hinge_sign * 1.15
	_add_box(hinge, Vector3(0.06, 0.42, 0.05), Vector3(handle_x, 2.05, -0.1), Color(0.18, 0.18, 0.2), 0.32, 0.75)
	return hinge


func _set_garage_doors_open() -> void:
	if _garage_left == null or _garage_right == null:
		return
	_garage_left.rotation.y = _DOOR_SWING
	_garage_right.rotation.y = -_DOOR_SWING


func _close_garage_doors() -> void:
	if _garage_left == null or _garage_right == null:
		return
	var doors := create_tween()
	doors.set_parallel(true)
	doors.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	doors.tween_property(_garage_left, "rotation:y", 0.0, _DOOR_OPEN_S)
	doors.tween_property(_garage_right, "rotation:y", 0.0, _DOOR_OPEN_S)


func _build_drive_in(root: Node3D) -> void:
	_add_solid(root, Vector3(16.4, 3.5, 6.4), Vector3(0.0, 1.75, 3.2), true)
	_add_box(root, Vector3(17.2, 0.06, 6.4), Vector3(0.0, 0.03, -3.0), Color(0.14, 0.14, 0.15), 0.94)
	for i in 5:
		var x := -6.0 + float(i) * 3.0
		_add_box(root, Vector3(0.08, 0.02, 4.4), Vector3(x, 0.07, -2.6), Color(0.72, 0.72, 0.68), 0.6)
	_add_box(root, Vector3(16.4, 3.3, 6.2), Vector3(0.0, 1.65, 3.1), _DINER_WALL)
	_add_box(root, Vector3(17.0, 0.16, 6.8), Vector3(0.0, 3.4, 3.15), Color(0.09, 0.08, 0.09), 0.7)
	_add_box(root, Vector3(16.4, 0.14, 0.06), Vector3(0.0, 3.12, -0.04), _DINER_RED, 0.45)
	_add_box(root, Vector3(16.4, 0.16, 0.06), Vector3(0.0, 0.12, -0.04), Color(0.38, 0.06, 0.07), 0.5)
	for i in 4:
		_diner_window(root, -6.0 + float(i) * 2.8, 2.2)
	_diner_window(root, 5.7, 2.5)
	_add_box(root, Vector3(2.2, 0.08, 0.5), Vector3(5.7, 1.02, -0.28), Color(0.5, 0.28, 0.14), 0.55)
	_add_box(root, Vector3(2.3, 0.5, 0.06), Vector3(5.7, 3.42, -0.12), Color(0.07, 0.04, 0.03))
	var amber := Color(1.0, 0.62, 0.12)
	_add_box(root, Vector3(2.1, 0.04, 0.03), Vector3(5.7, 3.6, -0.16), amber, 0.3, 0.0, amber, 2.4)
	_add_box(root, Vector3(2.1, 0.04, 0.03), Vector3(5.7, 3.24, -0.16), amber, 0.3, 0.0, amber, 2.4)
	_add_label(root, "ORDER", Vector3(5.7, 3.42, -0.18), 36, 0.01, Color(2.6, 1.7, 0.35), Color(0.85, 0.32, 0.05), 5)
	_diner_awning(root)
	_diner_sign(root)


func _diner_window(root: Node3D, x: float, width: float) -> void:
	_add_box(root, Vector3(width, 1.55, 0.06), Vector3(x, 1.8, -0.02), Color(0.74, 0.75, 0.78), 0.32, 0.65)
	_add_box(root, Vector3(width - 0.14, 1.38, 0.04), Vector3(x, 1.8, -0.06), Color(0.5, 0.66, 0.78), 0.08, 0.12)


func _diner_awning(root: Node3D) -> void:
	var count := 14
	var x0 := -7.3
	var x1 := 3.9
	var stripe_w := (x1 - x0) / float(count)
	for i in count:
		var color: Color = _DINER_RED if i % 2 == 0 else Color(0.92, 0.9, 0.86)
		var x := x0 + stripe_w * (float(i) + 0.5)
		_add_box(root, Vector3(stripe_w + 0.02, 0.05, 1.25), Vector3(x, 2.58, -0.58), color, 0.55, 0.0, Color.BLACK, 0.0, Vector3(-0.28, 0.0, 0.0))


func _diner_sign(root: Node3D) -> void:
	var metal := Color(0.2, 0.2, 0.22)
	var tube := Color(1.0, 0.15, 0.28)
	_add_box(root, Vector3(0.1, 1.35, 0.1), Vector3(-4.8, 4.25, 0.1), metal, 0.4, 0.65)
	_add_box(root, Vector3(0.1, 1.35, 0.1), Vector3(4.8, 4.25, 0.1), metal, 0.4, 0.65)
	_add_box(root, Vector3(11.4, 1.4, 0.14), Vector3(0.0, 4.25, 0.02), Color(0.04, 0.02, 0.03))
	_add_box(root, Vector3(10.2, 0.9, 0.04), Vector3(0.0, 4.25, -0.08), Color(0.45, 0.03, 0.07), 0.4, 0.0, Color(1.0, 0.12, 0.22), 0.9)
	_add_box(root, Vector3(10.8, 0.06, 0.04), Vector3(0.0, 4.88, -0.1), tube, 0.3, 0.0, tube, 2.8)
	_add_box(root, Vector3(10.8, 0.06, 0.04), Vector3(0.0, 3.62, -0.1), tube, 0.3, 0.0, tube, 2.8)
	_add_box(root, Vector3(0.06, 1.32, 0.04), Vector3(-5.4, 4.25, -0.1), tube, 0.3, 0.0, tube, 2.8)
	_add_box(root, Vector3(0.06, 1.32, 0.04), Vector3(5.4, 4.25, -0.1), tube, 0.3, 0.0, tube, 2.8)
	_add_label(root, "CHRIS'S DRIVE-IN", Vector3(0.0, 4.25, -0.14), 48, 0.012, Color(2.4, 1.45, 1.55), Color(0.85, 0.08, 0.16), 8)
	var bulbs: Array[Color] = [
		Color(1.0, 0.16, 0.18),
		Color(1.0, 0.84, 0.22),
		Color(0.25, 0.95, 1.0),
		Color(0.35, 1.0, 0.42),
		Color(1.0, 0.38, 0.86),
	]
	for i in 9:
		var color: Color = bulbs[i % bulbs.size()]
		var bx := -4.4 + float(i) * 1.1
		_add_sphere(root, 0.07, Vector3(bx, 5.05, -0.08), color, 0.3, 0.0, color, 2.2)
	_add_light(root, Vector3(0.0, 4.4, -1.2), Color(1.0, 0.35, 0.45), 1.3, 10.0)


func _build_gas_station(root: Node3D) -> void:
	_add_solid(root, Vector3(10.4, 4.8, 5.6), Vector3(0.0, 2.4, 2.8), true)
	var brick := _brick_material()
	_add_box(root, Vector3(9.2, 0.06, 5.2), Vector3(0.2, 0.03, -2.4), Color(0.58, 0.56, 0.52), 0.9)
	_add_box_mat(root, Vector3(10.2, 3.2, 0.28), Vector3(0.0, 1.6, 0.0), brick)
	_add_box_mat(root, Vector3(0.28, 3.2, 5.5), Vector3(-5.0, 1.6, 2.75), brick)
	_add_box_mat(root, Vector3(0.28, 3.2, 5.5), Vector3(5.0, 1.6, 2.75), brick)
	_add_box_mat(root, Vector3(10.2, 3.2, 0.28), Vector3(0.0, 1.6, 5.5), brick)
	_add_box(root, Vector3(1.7, 1.35, 0.06), Vector3(-3.55, 1.75, -0.16), _GAS_YELLOW, 0.5)
	_add_box(root, Vector3(3.4, 1.7, 0.08), Vector3(-0.7, 1.9, -0.16), _GAS_BLUE, 0.4)
	_add_box(root, Vector3(3.1, 1.4, 0.04), Vector3(-0.7, 1.9, -0.21), Color(0.62, 0.8, 0.9), 0.1, 0.08)
	_add_box(root, Vector3(1.25, 2.25, 0.08), Vector3(2.75, 1.15, -0.16), Color(0.2, 0.4, 0.78), 0.42)
	_add_box(root, Vector3(0.7, 0.85, 0.03), Vector3(2.75, 1.55, -0.21), Color(0.7, 0.84, 0.95), 0.12, 0.08)
	_add_label(root, "OFFICE", Vector3(2.75, 1.55, -0.24), 20, 0.0065, Color(0.9, 0.95, 1.0), Color(0.08, 0.16, 0.35), 3)
	_add_box(root, Vector3(10.5, 0.12, 0.14), Vector3(0.0, 3.18, -0.1), _GAS_BLUE, 0.5)
	var tiles := Color(0.42, 0.32, 0.24)
	_add_box(root, Vector3(10.6, 0.14, 3.2), Vector3(0.0, 4.2, 1.45), tiles, 0.86, 0.0, Color.BLACK, 0.0, Vector3(-0.7, 0.0, 0.0))
	_add_box(root, Vector3(10.6, 0.14, 3.2), Vector3(0.0, 4.2, 3.95), tiles, 0.86, 0.0, Color.BLACK, 0.0, Vector3(0.7, 0.0, 0.0))
	_add_box(root, Vector3(10.7, 0.1, 0.2), Vector3(0.0, 5.15, 2.7), Color(0.28, 0.29, 0.31), 0.7)
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var sx := 5.28 * side
		_add_box(root, Vector3(0.1, 0.7, 3.0), Vector3(sx, 4.15, 1.45), _GAS_BLUE, 0.5, 0.0, Color.BLACK, 0.0, Vector3(-0.7, 0.0, 0.0))
		_add_box(root, Vector3(0.1, 0.7, 3.0), Vector3(sx, 4.15, 3.95), _GAS_BLUE, 0.5, 0.0, Color.BLACK, 0.0, Vector3(0.7, 0.0, 0.0))
	_gas_pump(root, Vector3(-1.5, 0.08, -2.3))
	_gas_pump(root, Vector3(0.7, 0.08, -2.3))
	_gas_sign(root)


func _gas_pump(root: Node3D, pos: Vector3) -> void:
	var red := Color(0.62, 0.1, 0.1)
	_add_box(root, Vector3(0.7, 0.1, 0.5), pos + Vector3(0.0, 0.05, 0.0), Color(0.78, 0.76, 0.72), 0.55)
	_add_box(root, Vector3(0.55, 1.2, 0.38), pos + Vector3(0.0, 0.7, 0.0), red, 0.42)
	_add_box(root, Vector3(0.48, 0.07, 0.04), pos + Vector3(0.0, 1.05, -0.2), _GAS_YELLOW, 0.35, 0.0, _GAS_YELLOW, 0.45)
	_add_sphere(root, 0.16, pos + Vector3(0.0, 1.48, 0.0), Color(0.75, 0.88, 0.95), 0.18, 0.08, Color(0.8, 0.92, 1.0), 0.3)


func _gas_sign(root: Node3D) -> void:
	var board := Color(0.04, 0.08, 0.06)
	var glow := Color(1.4, 1.05, 0.2)
	var green := Color(0.15, 0.72, 0.22)
	_add_cylinder(root, 0.09, 6.0, Vector3(6.5, 3.0, -0.35), Color(0.38, 0.26, 0.16), 0.75)
	_add_box(root, Vector3(2.4, 1.75, 0.1), Vector3(6.5, 5.55, -0.35), _GAS_YELLOW, 0.35, 0.0, glow, 0.3)
	_add_box(root, Vector3(2.05, 1.4, 0.06), Vector3(6.5, 5.55, -0.44), board)
	_add_label(root, "Chris'", Vector3(6.85, 5.9, -0.5), 40, 0.01, glow, board, 5)
	_add_label(root, "Gas", Vector3(6.85, 5.25, -0.5), 46, 0.011, glow, board, 5)
	_add_box(root, Vector3(0.62, 0.16, 0.05), Vector3(5.75, 5.78, -0.5), green, 0.4, 0.0, Color(0.25, 1.0, 0.4), 0.55, Vector3(0.0, 0.0, 0.62))
	_add_box(root, Vector3(0.62, 0.16, 0.05), Vector3(5.75, 5.32, -0.5), green, 0.4, 0.0, Color(0.25, 1.0, 0.4), 0.55, Vector3(0.0, 0.0, -0.62))
	_add_sphere(root, 0.08, Vector3(6.5, 6.55, -0.4), Color(1.0, 0.9, 0.6), 0.3, 0.0, Color(1.0, 0.85, 0.45), 1.8)
	_add_light(root, Vector3(6.5, 5.6, -1.3), Color(1.0, 0.82, 0.4), 0.9, 8.0)


func _brick_material() -> StandardMaterial3D:
	var image := Image.create(16, 8, false, Image.FORMAT_RGB8)
	var mortar := Color(0.76, 0.7, 0.62)
	var a := Color(0.62, 0.24, 0.16)
	var b := Color(0.48, 0.18, 0.13)
	for y in 8:
		for x in 16:
			var row := int(y / 4)
			var shifted := (x + (8 if row % 2 == 1 else 0)) % 16
			var in_brick := (y % 4) < 3 and shifted < 15
			var color := mortar
			if in_brick:
				color = a if (int(x / 4) + row) % 2 == 0 else b
			image.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(image)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.uv1_scale = Vector3(2.4, 1.5, 2.4)
	mat.roughness = 0.9
	return mat


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, albedo: Color, rough: float = 0.82, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 0.0, rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = rough
	mat.metallic = metal
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
	_add_box_mat(parent, size, pos, mat, rot, shadow)


func _add_box_mat(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if not shadow or size.y < 0.1:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _add_sphere(parent: Node3D, radius: float, pos: Vector3, albedo: Color, rough: float, metal: float, emission: Color = Color.BLACK, energy: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = rough
	mat.metallic = metal
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _add_cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, albedo: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = rough
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _add_label(parent: Node3D, text: String, pos: Vector3, font_size: int, pixel: float, color: Color, outline: Color, outline_px: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_modulate = outline
	label.outline_size = outline_px
	label.shaded = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	label.rotation.y = PI
	parent.add_child(label)


func _add_light(parent: Node3D, pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	parent.add_child(light)


func _build_blocks(track: Dictionary) -> void:
	var glass := _glass_material(false)
	var lit := _glass_material(true)
	var frame := _facade_material(_FRAME_COLOR, 0.55, 0.2)
	var doors: Array[Material] = []
	for color in _DOOR_COLORS:
		doors.append(_facade_material(color, 0.5, 0.04))
	var signs: Array[Material] = []
	for color in _SIGN_COLORS:
		signs.append(_facade_material(color, 0.45, 0.0))
	var index := 0
	for raw: Dictionary in track.get("buildings", []):
		var block: Dictionary = raw
		_build_city_building(block, index, glass, lit, frame, doors, signs)
		index += 1


## A scenery box dressed as a building. One entrance on the nearest street, two on some lots.
func _build_city_building(block: Dictionary, index: int, glass: Material, lit: Material, frame: Material, doors: Array[Material], signs: Array[Material]) -> void:
	var wide := float(block["w"])
	var deep := float(block["d"])
	var tall := float(block["h"])
	var wall := _BLOCK_COLOR
	if block.has("color"):
		wall = block["color"]
	var sign := ""
	if block.has("sign"):
		sign = str(block["sign"])
	var root := Node3D.new()
	root.position = Vector3(float(block["x"]), 0.0, float(block["y"]))
	add_child(root)
	_add_solid(root, Vector3(wide, tall, deep), Vector3(0.0, tall * 0.5, 0.0), true)
	_add_box(root, Vector3(wide, tall, deep), Vector3(0.0, tall * 0.5, 0.0), wall, 0.9)
	_add_box(root, Vector3(wide + 0.08, 0.72, deep + 0.08), Vector3(0.0, 0.36, 0.0), wall.darkened(0.24), 0.92)
	var board := wall.darkened(0.16)
	for side_x in 2:
		for side_z in 2:
			var sx := -1.0 if side_x == 0 else 1.0
			var sz := -1.0 if side_z == 0 else 1.0
			_add_facade_box(root, Vector3(0.22, tall, 0.22), Vector3(sx * wide * 0.5, tall * 0.5, sz * deep * 0.5), board, 0.88)
	_add_city_roof(root, wide, deep, tall, wall, index, glass, frame)
	var entrances := _entrance_faces(Vector2(root.position.x, root.position.z), wide * 0.5, deep * 0.5, index)
	for face in 4:
		_dress_facade(root, wide, deep, tall, face, entrances.has(face), index, sign, wall, glass, lit, frame, doors, signs)


func _add_city_roof(root: Node3D, wide: float, deep: float, tall: float, wall: Color, index: int, glass: Material, frame: Material) -> void:
	var parapet := wall.darkened(0.22)
	var cap := wall.darkened(0.45)
	_add_box(root, Vector3(wide + 0.5, 0.16, deep + 0.5), Vector3(0.0, tall + 0.04, 0.0), cap, 0.93)
	var lip_y := tall + 0.34
	_add_box(root, Vector3(wide + 0.1, 0.48, 0.14), Vector3(0.0, lip_y, deep * 0.5 - 0.05), parapet, 0.9)
	_add_box(root, Vector3(wide + 0.1, 0.48, 0.14), Vector3(0.0, lip_y, -deep * 0.5 + 0.05), parapet, 0.9)
	_add_box(root, Vector3(0.14, 0.48, deep - 0.1), Vector3(wide * 0.5 - 0.05, lip_y, 0.0), parapet, 0.9)
	_add_box(root, Vector3(0.14, 0.48, deep - 0.1), Vector3(-wide * 0.5 + 0.05, lip_y, 0.0), parapet, 0.9)
	if tall >= 10.0 and index % 2 == 0:
		var hut := wall.darkened(0.08)
		var hx := wide * 0.14
		var hz := deep * 0.06
		_add_box(root, Vector3(2.5, 1.65, 2.2), Vector3(hx, tall + 0.96, hz), hut, 0.88)
		_add_box_mat(root, Vector3(0.9, 0.72, 0.05), Vector3(hx, tall + 1.08, hz + 1.14), frame, Vector3.ZERO, false)
		_add_box_mat(root, Vector3(0.68, 0.5, 0.03), Vector3(hx, tall + 1.08, hz + 1.18), glass, Vector3.ZERO, false)
		_add_box_mat(root, Vector3(0.05, 0.72, 0.9), Vector3(hx + 1.29, tall + 1.08, hz), frame, Vector3.ZERO, false)
		_add_box_mat(root, Vector3(0.03, 0.5, 0.68), Vector3(hx + 1.33, tall + 1.08, hz), glass, Vector3.ZERO, false)
	if tall >= 12.0 and index % 3 == 0:
		var tank := Color(0.62, 0.64, 0.66)
		_add_cylinder(root, 0.48, 1.05, Vector3(-wide * 0.22, tall + 0.7, -deep * 0.12), tank, 0.32)
		_add_facade_box(root, Vector3(1.1, 0.07, 1.1), Vector3(-wide * 0.22, tall + 1.26, -deep * 0.12), tank.darkened(0.12), 0.4, 0.35)
	if index % 5 == 2 and (tall < 12.0 or index % 3 != 0):
		var metal := Color(0.32, 0.32, 0.34)
		var ax := -wide * 0.28
		var az := -deep * 0.18
		_add_facade_box(root, Vector3(0.05, 1.7, 0.05), Vector3(ax, tall + 0.95, az), metal, 0.35, 0.7)
		_add_facade_box(root, Vector3(1.25, 0.035, 0.035), Vector3(ax, tall + 1.65, az), metal, 0.35, 0.7)
		_add_facade_box(root, Vector3(0.85, 0.035, 0.035), Vector3(ax, tall + 1.4, az), metal, 0.35, 0.7)


## `face` is 0 +X, 1 -X, 2 +Z, 3 -Z. `entrance` is a side with the door, and the shop front when this building has a sign.
func _dress_facade(root: Node3D, wide: float, deep: float, tall: float, face: int, entrance: bool, index: int, sign: String, wall: Color, glass: Material, lit: Material, frame: Material, doors: Array[Material], signs: Array[Material]) -> void:
	var span := deep if face < 2 else wide
	var cols := 3 if span < 9.2 else 5
	var rows := _floor_count(tall)
	var margin := clampf(span * 0.11, 0.5, 1.05)
	var step := (span - margin * 2.0) / float(cols)
	var win_w := minf(step * 0.58, 1.45)
	var shop := entrance and not sign.is_empty()
	var awning := shop and index % 3 != 2
	for row in rows:
		var ground := row == 0
		var win_h := 1.5 if ground and shop else (1.12 if ground else 1.18)
		var y := 1.68 if ground and shop else (1.72 if ground else _upper_window_y(tall, rows, row))
		if y + win_h * 0.5 > tall - 0.4:
			win_h = (tall - 0.4 - y) * 2.0
		if win_h < 0.45:
			continue
		if not ground:
			var band := wall.lightened(0.1)
			_add_facade_box(root, _face_size(face, span + 0.04, 0.1, 0.06), _face_pos(wide, deep, face, 0.0, y - win_h * 0.5 - 0.16, 0.03), band, 0.8)
		for col in cols:
			var along := -span * 0.5 + margin + step * (float(col) + 0.5)
			var door_gap := 0.72 if shop else 0.52
			if entrance and ground and absf(along) < win_w * 0.5 + door_gap:
				continue
			var warm := _facade_hash(index, face, row, col) % 4 == 0
			_add_window(root, wide, deep, face, along, y, win_w, win_h, frame, lit if warm else glass)
			var shade_roll := 7 if shop else 3
			if _facade_hash(index, face, row, col) % shade_roll == 0:
				var shade := Color(0.72, 0.62, 0.46)
				_add_facade_box(root, _face_size(face, win_w - 0.1, win_h * 0.36, 0.02), _face_pos(wide, deep, face, along, y + win_h * 0.2, 0.12), shade, 0.7)
	if rows == 1 and tall >= 4.9:
		var high_y := tall - 0.95
		var high_h := 0.5
		if high_y - high_h * 0.5 > 3.55:
			for col in cols:
				var along := -span * 0.5 + margin + step * (float(col) + 0.5)
				var warm := _facade_hash(index, face, 9, col) % 4 == 0
				_add_window(root, wide, deep, face, along, high_y, win_w * 0.85, high_h, frame, lit if warm else glass)
	if entrance:
		_add_street_door(root, wide, deep, face, tall, index, sign, awning, glass, frame, doors, signs)


func _add_window(root: Node3D, wide: float, deep: float, face: int, along: float, y: float, win_w: float, win_h: float, frame: Material, glass: Material) -> void:
	_add_box_mat(root, _face_size(face, win_w + 0.14, win_h + 0.14, 0.05), _face_pos(wide, deep, face, along, y, 0.03), frame, Vector3.ZERO, false)
	_add_box_mat(root, _face_size(face, win_w, win_h, 0.03), _face_pos(wide, deep, face, along, y, 0.075), glass, Vector3.ZERO, false)
	_add_box_mat(root, _face_size(face, 0.05, win_h, 0.03), _face_pos(wide, deep, face, along, y, 0.1), frame, Vector3.ZERO, false)
	_add_box_mat(root, _face_size(face, win_w, 0.045, 0.03), _face_pos(wide, deep, face, along, y, 0.1), frame, Vector3.ZERO, false)


func _add_street_door(root: Node3D, wide: float, deep: float, face: int, tall: float, index: int, sign: String, awning: bool, glass: Material, frame: Material, doors: Array[Material], signs: Array[Material]) -> void:
	var home := sign.is_empty()
	var door_w := 0.92 if home else 1.12
	var door_h := 2.05 if home else 2.15
	var y := 0.1 + door_h * 0.5
	var leaf: Material = doors[index % doors.size()]
	var door_color: Color = _DOOR_COLORS[index % _DOOR_COLORS.size()]
	_add_box_mat(root, _face_size(face, door_w + 0.16, door_h + 0.1, 0.07), _face_pos(wide, deep, face, 0.0, y + 0.02, 0.03), frame, Vector3.ZERO, false)
	_add_box_mat(root, _face_size(face, door_w, door_h, 0.06), _face_pos(wide, deep, face, 0.0, y, 0.06), leaf, Vector3.ZERO, false)
	if home:
		_add_facade_box(root, _face_size(face, door_w - 0.22, 0.62, 0.025), _face_pos(wide, deep, face, 0.0, 1.55, 0.095), door_color.lightened(0.1), 0.48)
		_add_facade_box(root, _face_size(face, door_w - 0.22, 0.62, 0.025), _face_pos(wide, deep, face, 0.0, 0.72, 0.095), door_color.lightened(0.1), 0.48)
	else:
		_add_box_mat(root, _face_size(face, door_w - 0.26, 0.52, 0.025), _face_pos(wide, deep, face, 0.0, 1.68, 0.095), glass, Vector3.ZERO, false)
		_add_facade_box(root, _face_size(face, door_w - 0.26, 0.7, 0.025), _face_pos(wide, deep, face, 0.0, 0.72, 0.095), door_color.lightened(0.12), 0.48)
	var handle := 0.32 if home else 0.36
	if index % 2 == 1:
		handle = -handle
	_add_facade_box(root, _face_size(face, 0.05, 0.16, 0.04), _face_pos(wide, deep, face, handle, 1.05, 0.11), Color(0.78, 0.66, 0.32), 0.28, 0.85)
	var stoop_w := door_w + 0.35 if home else door_w + 0.55
	_add_facade_box(root, _face_size(face, stoop_w, 0.1, 0.7 if home else 0.85), _face_pos(wide, deep, face, 0.0, 0.05, 0.4 if home else 0.48), _STOOP_COLOR, 0.92)
	if home:
		return
	if not awning and tall >= 4.8:
		_add_box_mat(root, _face_size(face, door_w, 0.28, 0.03), _face_pos(wide, deep, face, 0.0, 2.52, 0.07), glass, Vector3.ZERO, false)
	var lamp := Color(1.0, 0.86, 0.55)
	for side: float in [-1.0, 1.0]:
		_add_box(root, _face_size(face, 0.1, 0.16, 0.07), _face_pos(wide, deep, face, side * 0.82, 2.02, 0.1), lamp, 0.3, 0.0, lamp, 0.7, Vector3.ZERO, false)
	if awning:
		_add_awning(root, wide, deep, face, deep if face < 2 else wide, 2.92, _SIGN_COLORS[index % _SIGN_COLORS.size()])
	if tall < 4.6:
		return
	var sign_y := 3.35
	if sign_y + 0.3 > tall - 0.35:
		return
	var board: Material = signs[index % signs.size()]
	var board_color: Color = _SIGN_COLORS[index % _SIGN_COLORS.size()]
	_add_box_mat(root, _face_size(face, 2.35, 0.5, 0.07), _face_pos(wide, deep, face, 0.0, sign_y, 0.1), board, Vector3.ZERO, false)
	_add_facade_label(root, sign, _face_pos(wide, deep, face, 0.0, sign_y, 0.18), face, 52, 0.011, Color(0.98, 0.94, 0.86), board_color.darkened(0.45))


func _add_awning(root: Node3D, wide: float, deep: float, face: int, span: float, y: float, color: Color) -> void:
	var stripes := 7
	var cloth := span - 0.9
	var width := cloth / float(stripes)
	var cream := Color(0.92, 0.88, 0.8)
	var start := -cloth * 0.5 + width * 0.5
	for i in stripes:
		var shade: Color = color if i % 2 == 0 else cream
		var along := start + width * float(i)
		_add_facade_box(root, _face_size(face, width + 0.02, 0.05, 0.9), _face_pos(wide, deep, face, along, y, 0.52), shade, 0.62)
	_add_facade_box(root, _face_size(face, cloth, 0.1, 0.05), _face_pos(wide, deep, face, 0.0, y - 0.1, 0.94), color.darkened(0.18), 0.55)


func _floor_count(tall: float) -> int:
	if tall < 5.6:
		return 1
	if tall < 8.6:
		return 2
	if tall < 11.6:
		return 3
	if tall < 14.6:
		return 4
	return 5


func _upper_window_y(tall: float, rows: int, row: int) -> float:
	var count := rows - 1
	var y0 := 3.45
	var y1 := tall - 0.8
	if count <= 1:
		return (y0 + y1) * 0.5
	var t := (float(row - 1) + 0.5) / float(count)
	return lerpf(y0, y1, t)


## The nearest street face, plus the next street face on every fourth building.
func _entrance_faces(center: Vector2, half_w: float, half_d: float, index: int) -> Array[int]:
	var points: Array[Vector2] = [
		Vector2(center.x + half_w, center.y),
		Vector2(center.x - half_w, center.y),
		Vector2(center.x, center.y + half_d),
		Vector2(center.x, center.y - half_d),
	]
	var best := 0
	var second := -1
	var best_gap := 1000.0
	var second_gap := 1000.0
	for i in 4:
		var gap := _nearest_curb(points[i])
		if gap < best_gap:
			second = best
			second_gap = best_gap
			best = i
			best_gap = gap
		elif gap < second_gap:
			second = i
			second_gap = gap
	var faces: Array[int] = [best]
	if second >= 0 and second_gap < 10.0 and index % 4 == 1:
		faces.append(second)
	return faces


func _nearest_curb(point: Vector2) -> float:
	var best := 80.0
	for segment in _streets:
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var gap := _gap_to_segment(point, Vector2(a.x, a.z), Vector2(b.x, b.z)) - float(segment["half"])
		if gap < best:
			best = gap
	return best


func _face_pos(wide: float, deep: float, face: int, along: float, up: float, out: float) -> Vector3:
	match face:
		0:
			return Vector3(wide * 0.5 + out, up, along)
		1:
			return Vector3(-wide * 0.5 - out, up, along)
		2:
			return Vector3(along, up, deep * 0.5 + out)
		_:
			return Vector3(along, up, -deep * 0.5 - out)


func _face_size(face: int, along: float, up: float, thick: float) -> Vector3:
	if face < 2:
		return Vector3(thick, up, along)
	return Vector3(along, up, thick)


func _facade_hash(index: int, face: int, row: int, col: int) -> int:
	var n := index * 73856093 ^ face * 19349663 ^ row * 83492791 ^ col * 15485863
	n = n ^ (n >> 13)
	return absi(n)


func _glass_material(lit: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.06
	if lit:
		mat.albedo_color = Color(1.0, 0.84, 0.5)
		mat.roughness = 0.38
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.68, 0.28)
		mat.emission_energy_multiplier = 0.38
	else:
		mat.albedo_color = Color(0.58, 0.74, 0.86)
		mat.roughness = 0.14
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.68, 0.82)
		mat.emission_energy_multiplier = 0.05
	return mat


func _facade_material(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	return mat


func _add_facade_box(parent: Node3D, size: Vector3, pos: Vector3, albedo: Color, rough: float, metal: float = 0.0) -> void:
	_add_box(parent, size, pos, albedo, rough, metal, Color.BLACK, 0.0, Vector3.ZERO, false)


func _add_facade_label(parent: Node3D, text: String, pos: Vector3, face: int, font_size: int, pixel: float, color: Color, outline: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_modulate = outline
	label.outline_size = 4
	label.shaded = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	match face:
		0:
			label.rotation.y = PI * 0.5
		1:
			label.rotation.y = -PI * 0.5
		2:
			label.rotation.y = 0.0
		_:
			label.rotation.y = PI
	parent.add_child(label)


func _build_car() -> void:
	# A body so the suspension has a car to read the road for. It touches nothing.
	_car = CharacterBody3D.new()
	_car.name = "Car"
	_car.collision_layer = 0
	_car.collision_mask = 0
	add_child(_car)
	_pivot = _CAR_SCENE.instantiate() as Node3D
	_pivot.position = Vector3(0.0, 0.0, 1.9)
	_car.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.top_level = true
	_camera.fov = 66.0
	_cam_rest = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-12.0), PI, 0.0)), Vector3(0.0, 3.1, -9.5))
	_car.add_child(_camera)
	_camera.current = true
	_dynamics = _VehicleDynamics.new()
	_dynamics.name = "VehicleDynamics"
	_car.add_child(_dynamics)
	_dynamics.apply_setup(GameState.race_chassis(), GameState.tire_grip())
	_lay_out_wheels()
	_body_motion.setup(_pivot, _dynamics)
	if _pivot.has_method(&"align_wheels_to_floor") and _floor != null:
		_pivot.call_deferred(&"align_wheels_to_floor", _floor)


func _lay_out_wheels() -> void:
	var points: Array[Vector3] = []
	for wname in _CarBodyMotion.WHEEL_NAMES:
		var wheel := _pivot.get_node_or_null(NodePath(wname)) as Node3D
		if wheel == null:
			_dynamics.layout_about(Vector3(_pivot.position.x, 0.0, _pivot.position.z))
			return
		points.append(_car.to_local(wheel.global_position))
	_dynamics.set_wheel_positions(points)


## The fastest the car can be at each point of the route: slow enough for the corners, and
## able to brake for them and to stop at the end.
func _plan_speeds() -> void:
	_corner_accel = _dynamics.grip_accel() * _CORNER_GRIP_USE
	var count := _pts.size()
	_plan.resize(count)
	for i in count:
		_plan[i] = _corner_limit(_dists[i])
	_plan[0] = 0.0
	_plan[count - 1] = 0.0
	for i in range(1, count):
		_plan[i] = minf(_plan[i], sqrt(_plan[i - 1] * _plan[i - 1] + 2.0 * _DRIVE_ACCEL * (_dists[i] - _dists[i - 1])))
	for i in range(count - 2, -1, -1):
		_plan[i] = minf(_plan[i], sqrt(_plan[i + 1] * _plan[i + 1] + 2.0 * _DRIVE_BRAKE * (_dists[i + 1] - _dists[i])))


func _corner_limit(distance: float) -> float:
	var a := _sample(maxf(distance - _CURVE_SPAN, 0.0))
	var mid := _sample(distance)
	var b := _sample(minf(distance + _CURVE_SPAN, _length))
	var into := Vector2(mid.x - a.x, mid.z - a.z)
	var out := Vector2(b.x - mid.x, b.z - mid.z)
	if into.length_squared() < 0.01 or out.length_squared() < 0.01:
		return _TOP_SPEED
	var curve := absf(into.angle_to(out)) / _CURVE_SPAN
	if curve < 0.001:
		return _TOP_SPEED
	return minf(_TOP_SPEED, sqrt(_corner_accel / curve))


func _planned_speed(distance: float) -> float:
	var s := clampf(distance, 0.0, _length)
	var i := 0
	while i + 1 < _dists.size() and _dists[i + 1] < s:
		i += 1
	var j := mini(i + 1, _plan.size() - 1)
	var span: float = _dists[j] - _dists[i]
	return lerpf(_plan[i], _plan[j], (s - _dists[i]) / span if span > 0.0001 else 0.0)


func _bake(points: Array[Vector3]) -> void:
	var rounded := _round_corners(points)
	_pts = PackedVector3Array()
	_dists = PackedFloat32Array()
	_pts.append(rounded[0])
	_dists.append(0.0)
	var total := 0.0
	for i in range(1, rounded.size()):
		var a: Vector3 = rounded[i - 1]
		var b: Vector3 = rounded[i]
		var span := Vector2(b.x - a.x, b.z - a.z).length()
		var steps := maxi(int(ceil(span / 2.0)), 1)
		for step in range(1, steps + 1):
			var p := a.lerp(b, float(step) / float(steps))
			var prev := _pts[_pts.size() - 1]
			total += Vector2(p.x - prev.x, p.z - prev.z).length()
			_pts.append(p)
			_dists.append(total)
	_length = total
	_shift_into_right_lane()


func _shift_into_right_lane() -> void:
	if _pts.size() < 2:
		return
	var offset := 0.0
	var shifted := PackedVector3Array()
	shifted.resize(_pts.size())
	for i in _pts.size():
		var half := _half_near(_pts[i])
		var target := half * 0.5 if half >= _TWO_LANE_HALF else 0.0
		if i > 0:
			var ds: float = _dists[i] - _dists[i - 1]
			var step := ds * 0.4
			if target > offset:
				offset = minf(offset + step, target)
			else:
				offset = maxf(offset - step, target)
		var tangent := _tangent_at(i)
		# This side of the tangent is the right lane in the chase view.
		var right := Vector3(-tangent.z, 0.0, tangent.x)
		shifted[i] = _pts[i] + right * offset
	_pts = shifted
	var total := 0.0
	_dists[0] = 0.0
	for i in range(1, _pts.size()):
		var prev := _pts[i - 1]
		var here := _pts[i]
		total += Vector2(here.x - prev.x, here.z - prev.z).length()
		_dists[i] = total
	_length = total


func _tangent_at(index: int) -> Vector3:
	var before := _pts[maxi(index - 1, 0)]
	var after := _pts[mini(index + 1, _pts.size() - 1)]
	var span := Vector3(after.x - before.x, 0.0, after.z - before.z)
	if span.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return span.normalized()


func _half_near(point: Vector3) -> float:
	var best := 0.0
	var best_d := 12.0
	var flat := Vector2(point.x, point.z)
	for segment in _streets:
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var gap := _gap_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if gap < best_d:
			best_d = gap
			best = float(segment["half"])
	return best


func _gap_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len2, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _sample(distance: float) -> Vector3:
	var s := clampf(distance, 0.0, _length)
	var i := 0
	while i + 1 < _dists.size() and _dists[i + 1] < s:
		i += 1
	var j := mini(i + 1, _pts.size() - 1)
	var span: float = _dists[j] - _dists[i]
	var t := 0.0
	if span > 0.0001:
		t = (s - _dists[i]) / span
	return _pts[i].lerp(_pts[j], t)


## Replace each kink with a circular arc so the car steers through the junction.
func _round_corners(points: Array[Vector3]) -> Array[Vector3]:
	var rounded: Array[Vector3] = []
	if points.is_empty():
		return rounded
	rounded.append(points[0])
	for i in range(1, points.size() - 1):
		var prev: Vector3 = points[i - 1]
		var corner: Vector3 = points[i]
		var nxt: Vector3 = points[i + 1]
		var in_v := Vector3(corner.x - prev.x, 0.0, corner.z - prev.z)
		var out_v := Vector3(nxt.x - corner.x, 0.0, nxt.z - corner.z)
		var in_len := in_v.length()
		var out_len := out_v.length()
		if in_len < 1.0 or out_len < 1.0:
			rounded.append(corner)
			continue
		var in_dir := in_v / in_len
		var out_dir := out_v / out_len
		var dot := clampf(in_dir.dot(out_dir), -1.0, 1.0)
		if dot > 0.985:
			rounded.append(corner)
			continue
		var deflection := acos(dot)
		if deflection > PI - 0.2:
			rounded.append(corner)
			continue
		var radius := _TURN_RADIUS
		var tangent := radius * tan(deflection * 0.5)
		var limit := minf(in_len, out_len) * 0.45
		if tangent > limit and deflection > 0.001:
			tangent = limit
			radius = tangent / tan(deflection * 0.5)
		var p0 := corner - in_dir * tangent
		var p2 := corner + out_dir * tangent
		var cross := in_dir.x * out_dir.z - in_dir.z * out_dir.x
		var left := Vector3(-in_dir.z, 0.0, in_dir.x)
		if cross < 0.0:
			left = -left
		var center := p0 + left * radius
		var start_angle := atan2(p0.x - center.x, p0.z - center.z)
		var end_angle := atan2(p2.x - center.x, p2.z - center.z)
		var sweep := angle_difference(start_angle, end_angle)
		rounded.append(p0)
		var steps := maxi(int(ceil(absf(sweep) * radius / 2.0)), 4)
		for s in range(1, steps):
			var ang := start_angle + sweep * float(s) / float(steps)
			rounded.append(Vector3(
				center.x + sin(ang) * radius,
				corner.y,
				center.z + cos(ang) * radius
			))
		rounded.append(p2)
	rounded.append(points[points.size() - 1])
	return rounded


func _place_car(distance: float) -> void:
	if _car == null:
		return
	var pos := _sample(distance)
	var behind := _sample(maxf(distance - 2.0, 0.0))
	var ahead := _sample(minf(distance + _LOOK_AHEAD, _length))
	var flat := Vector2(ahead.x - behind.x, ahead.z - behind.z)
	var delta := get_process_delta_time()
	if flat.length_squared() > 0.0001:
		var yaw := atan2(flat.x, flat.y)
		if delta > 0.0:
			var turning := wrapf(yaw - _car.rotation.y, -PI, PI) / delta
			_yaw_rate = lerpf(_yaw_rate, turning, 1.0 - exp(-8.0 * delta))
		_car.rotation.y = yaw
	_road_y = pos.y
	_car.position = Vector3(pos.x, pos.y + _BODY_Y, pos.z)


func _update_engine() -> void:
	if _engine == null:
		return
	var pace := clampf(_speed / _TOP_SPEED, 0.0, 1.0)
	_engine.set_state(lerpf(900.0, 2600.0, pace), lerpf(0.25, 0.7, pace), false)


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 1.0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_shade)


func _paint_fade() -> void:
	if _shade != null:
		_shade.color.a = _fade
