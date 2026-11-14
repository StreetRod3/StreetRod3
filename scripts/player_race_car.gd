extends CharacterBody3D

## Speed along the car's nose (m/s).
var forward_speed: float = 0.0
## Car heading in radians. 0 means pointing along world +Z.
var heading_yaw: float = 0.0

const _VehicleDynamics := preload("res://scripts/vehicle_dynamics.gd")
const _SkidMarks := preload("res://scripts/skid_marks.gd")
const _ArcadeDrive := preload("res://scripts/arcade_drive.gd")
const _RacePark := preload("res://scripts/race_park.gd")
const _Controller := preload("res://scripts/controller.gd")
const _Rumble := preload("res://scripts/rumble.gd")
const _CarBodyMotion := preload("res://scripts/car_body_motion.gd")
const _WallScrape := preload("res://scripts/wall_scrape.gd")
const _CarDamage := preload("res://scripts/car_damage.gd")
const _ChaseCamera := preload("res://scripts/chase_camera.gd")
const _AirTime := preload("res://scripts/air_time.gd")
const _MouseDrive := preload("res://scripts/mouse_drive.gd")
const _CarFile := preload("res://scripts/car_file.gd")

const RPM_IDLE_MIN := 500.0
const RPM_IDLE := 600.0 ## C1 idle sits between 500 and 700.
const RPM_SHIFT_START := 5500.0
const RPM_REDLINE := 6500.0
const RPM_CRITICAL := 6700.0
const RPM_METER_MAX := 7000.0
const OVERREV_HOLD_S := 0.55
## Slower than this, gas and brake together are a burnout, in m/s.
const BURNOUT_MAX_SPEED := 2.0
## How fast a burnout comes on and dies away, per second.
const BURNOUT_RISE := 3.0
const BURNOUT_FALL := 6.0
const BURNOUT_RPM := 5000.0
## How fast the rear tires turn in a burnout at full strength, in m/s.
const BURNOUT_WHEEL_SPEED := 30.0
## In a full burnout the back of the car swings round the braked front wheels this fast with
## the wheel turned all the way, and wanders up to this much on its own, in rad/s.
const BURNOUT_SWING_RATE := 0.75
const BURNOUT_WANDER := 0.12
## How fast that swing builds and changes, in rad/s².
const BURNOUT_SWING_ACCEL := 3.0
## A rear tire sliding sideways this fast lays its burnout marks along its path, in m/s.
const BURNOUT_MARK_SLIDE := 0.5
## The hand brake works with the clutch in. On the gas the engine holds its revs, and climbs to
## this if it was lower, by the first rate. Once the clutch is out the revs come down to the
## road's by the second, in rpm per second.
const CLUTCH_FREE_RPM := 5000.0
const CLUTCH_REV_RATE := 6000.0
const CLUTCH_CATCH_RATE := 5000.0
## The clutch kick: as the clutch bites, the revs over the road's, as a share of the rev range,
## times this is the extra share of the gear's pull. Only when the hand brake comes off faster
## than this, in m/s, so a launch gets none.
const CLUTCH_KICK := 1.0
const CLUTCH_KICK_SPEED := 5.0

const CAM_FAR := 0
const CAM_CLOSE := 1
const CAM_COCKPIT := 2
const CAM_BUMPER := 3
## Below first gear. The box starts in drive (gear 0) in a race and on the city.
const GEAR_NEUTRAL := -1
const GEAR_REVERSE := -2
## Road speed where rumble from the surface and from sliding is at its fullest, in m/s.
const RUMBLE_FULL_SPEED := 25.0
## A tire past this share of its grip has started to slide, and this far past it is sliding hard.
const RUMBLE_SLIDE_START := 0.95
const RUMBLE_SLIDE_FULL := 0.3
const RUMBLE_SCRAPE := 0.35
const RUMBLE_SHIFT := 0.3
## Both pedals need to be this far down to start a burnout.
const BURNOUT_PEDAL := 0.5
## Reverse only goes in below this forward speed, in m/s. Above it the box stays out of gear.
const REVERSE_ENGAGE_SPEED := 2.0
## Reverse tops out at this share of first gear, and never slower than a brisk walk.
const REVERSE_TOP_FRACTION := 0.38
const REVERSE_TOP_MIN := 7.0
## Share of how hard a landing is that comes off the car's speed.
const LANDING_SPEED_LOSS := 0.15
## A blown tire pulls the car towards its side, as in Street Rod 2. The pull is steering input,
## -1 to 1, added to the driver's, and it grows as the tire shreds until full opposite lock
## can't hold the car straight.
const FLAT_PULL_START := 0.6
const FLAT_PULL_FULL := 1.5
const FLAT_PULL_RAMP_S := 1.5
## A flat drags the car down, in m/s².
const FLAT_DRAG := 4.0
## The nose jerks towards the flat as the tire goes, in rad/s.
const FLAT_YAW_KICK := 0.4
## How far the blown corner of the body sinks onto the rim, in meters, and how fast.
const FLAT_DROP_M := 0.12
const FLAT_DROP_S := 0.15
## A car out of the race slides to a stop at this rate, in m/s².
const HALT_DECEL := 9.0
## A landing softer than this, in m/s into the road, isn't felt: a car skimming a crest at the speed
## it starts to lift touches down every step or two.
const LANDING_FELT_MPS := 0.5

signal gear_changed(from_gear: int, to_gear: int)

@export var debug_dynamics: bool = false

@onready var _cam: Camera3D = $RaceCamera
@onready var _engine_sound: Node = $EngineSound
@onready var _visual: Node3D = $CarPivot
var _cam_mode: int = CAM_FAR
@onready var _dynamics: _VehicleDynamics = get_node_or_null("VehicleDynamics") as _VehicleDynamics
var _arcade: _ArcadeDrive = _ArcadeDrive.new()
var _skids: _SkidMarks
var _car_center := Vector3(0.0, 0.0, 1.9)
var _debug_view: MeshInstance3D
var _debug_labels: Array[Label3D] = []
var _touch: Node = null
var _gearbox: Dictionary = {}
var _gear: int = 0
var _shift_timer: float = 0.0
## The gear the H-pattern shifter last asked for. Q and E can move off it until the next move.
var _shifter_gear: int = _Controller.POSITION_NONE
var _rumble := _Rumble.new()
var _camera_held: bool = false
var _tapped_up: bool = false
var _tapped_down: bool = false
var _tapped_camera: bool = false
var _shifter_up_held: bool = false
var _shifter_down_held: bool = false
## How far into a burnout the car is, 0 to 1.
var _burnout: float = 0.0
## How fast the back of the car is swinging in a burnout, in rad/s, before its strength.
var _burnout_swing: float = 0.0
var _burnout_time: float = 0.0
var _burnout_wander := FastNoiseLite.new()
## The engine's own revs while the clutch is in or still biting, or 0 when they follow the road.
var _clutch_rpm: float = 0.0
var _clutch_kicks: bool = false
var _overrev_time: float = 0.0
var _engine_blown: bool = false
## Which way a blown tire pulls, as steering input: 1 or -1, or 0 with all four up.
var _flat_side: float = 0.0
var _flat_s: float = 0.0
## The blown corner, in the car's space.
var _flat_corner := Vector3.ZERO
var _damage: _CarDamage = _CarDamage.new()
var _arcade_active: bool = false
var _body_motion: _CarBodyMotion = _CarBodyMotion.new()
var _cam_rest := Transform3D.IDENTITY
var _chase_cam: _ChaseCamera = _ChaseCamera.new()
var _parking := false
## Out of the race where it is, with nobody driving: wrecked, engine blown, or on a flat.
var _halting := false
var _park_speed := 0.0
var _park_slot := 0.0
## Body height on flat ground. Track height is added on top of this.
var _road_base_y: float = 0.0
const _ROAD_PITCH_SPAN := 8.0
var _air: _AirTime = _AirTime.new()
var _mouse_drive := _MouseDrive.new()
var _mouse_driving := true
var _mouse_captured := false

func _ready() -> void:
	_road_base_y = global_position.y
	if _dynamics == null:
		_dynamics = _VehicleDynamics.new()
		_dynamics.name = "VehicleDynamics"
		add_child(_dynamics)
	motion_mode = MOTION_MODE_FLOATING
	# Layer 2 is cars. Only the road and its barriers stop this body. Contact with the other
	# car is all in `car_bump.gd`, or on a slope the bodies touch before it sees a hit.
	collision_mask = 1
	_apply_car_spec()
	_cache_axles()
	_layout_wheels()
	_body_motion.shows_fuel = true
	_body_motion.setup(_visual, _dynamics)
	_dynamics.yaw = rotation.y
	heading_yaw = rotation.y
	_chase_cam.settle(heading_yaw)
	_skids = _SkidMarks.new()
	_skids.name = "SkidMarks"
	add_child(_skids)
	_burnout_wander.seed = randi()
	_burnout_wander.frequency = 0.5
	_cam_mode = posmod(GameState.driving_camera, 4)
	_apply_camera_mode()
	_gearbox = GameState.get_equipped_gearbox()
	_gear = 0
	var race := get_parent()
	if race != null:
		_touch = race.get_node_or_null("RaceUI/MobileControls")
	_resume_mouse_drive()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_mouse_drive()
	elif what == NOTIFICATION_UNPAUSED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if is_inside_tree() and can_process():
			_resume_mouse_drive()


func _resume_mouse_drive() -> void:
	_mouse_drive.reset()
	if _mouse_driving and (GameState.mouse_steering_enabled or GameState.mouse_pedals_enabled):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_captured = true


func _release_mouse_drive() -> void:
	_mouse_drive.reset()
	if _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_captured = false


func stop_mouse_driving() -> void:
	_mouse_driving = false
	_release_mouse_drive()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_mouse_drive.move(event.screen_relative, GameState.mouse_steering_enabled, GameState.mouse_pedals_enabled, GameState.mouse_steering_sensitivity, GameState.mouse_pedals_sensitivity)
	elif event is InputEventMouseButton and event.pressed and _mouse_captured:
		if event.button_index == MOUSE_BUTTON_LEFT and GameState.mouse_steering_enabled:
			_mouse_drive.steering = 0.0
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and GameState.mouse_pedals_enabled:
			_mouse_drive.pedals = 0.0
			get_viewport().set_input_as_handled()


## The car reads held controls each step, and a quick tap on a slow machine can come and go
## between two steps. So a key going down is remembered until the next one looks.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var code := int(event.keycode)
	_tapped_up = _tapped_up or _Controller.keys_for(_Controller.UP).has(code)
	_tapped_down = _tapped_down or _Controller.keys_for(_Controller.DOWN).has(code)
	_tapped_camera = _tapped_camera or _Controller.keys_for(_Controller.CAMERA).has(code)


func _camera_slot_name() -> String:
	match _cam_mode:
		CAM_CLOSE:
			return "close"
		CAM_COCKPIT:
			return "cockpit"
		CAM_BUMPER:
			return "bumper"
		_:
			return "far"


func _apply_camera_mode() -> void:
	if _cam == null:
		return
	var slot := _camera_slot_name()
	var defaults: Dictionary = _CarFile.DEFAULT_CAMERAS[slot]
	var pos: Vector3 = defaults["position"]
	var pitch_deg := float(defaults["pitch"])
	var fov_deg := float(defaults["fov"])
	var cameras: Variant = GameState.car_spec.get("cameras", {})
	if typeof(cameras) == TYPE_DICTIONARY and (cameras as Dictionary).has(slot):
		var entry: Variant = (cameras as Dictionary)[slot]
		if typeof(entry) == TYPE_DICTIONARY:
			var cam_dict: Dictionary = entry
			var raw_pos: Variant = cam_dict.get("position", null)
			if raw_pos is Vector3:
				pos = raw_pos
			pitch_deg = float(cam_dict.get("pitch", pitch_deg))
			fov_deg = float(cam_dict.get("fov", fov_deg))
	var local_pos := Vector3(_car_center.x + pos.x, pos.y - _road_base_y, _car_center.z + pos.z)
	_cam_rest = _camera_pose(local_pos, pitch_deg)
	_cam.fov = fov_deg
	_cam.top_level = true
	_cam.current = true
	_chase_cam.settle(rotation.y)
	_place_camera(0.0)


func _camera_pose(pos: Vector3, pitch_deg: float) -> Transform3D:
	var look := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), PI, 0.0))
	return Transform3D(look, pos)


## The chase cameras hang back from the car. The cockpit and bumper cameras are part of the
## body, so they ride its springs and the horizon tilts with it.
func _place_camera(delta: float) -> void:
	if _cam == null:
		return
	if _cam_mode == CAM_COCKPIT or _cam_mode == CAM_BUMPER:
		_cam.global_transform = global_transform * _body_motion.lean_in_car_space() * _cam_rest
		return
	var planar := _dynamics.cg_velocity if _parking else planar_velocity()
	_chase_cam.place(_cam, self, _car_center, _cam_rest, planar, delta)


func get_forward_speed() -> float:
	return forward_speed


func planar_velocity() -> Vector3:
	if _halting:
		return Vector3(velocity.x, 0.0, velocity.z)
	if GameState.arcade_drive:
		return _arcade.planar_velocity()
	return _dynamics.cg_velocity


func get_mass_kg() -> float:
	return _dynamics.config.mass_kg


## Moves this car out of another car, keeps the bumped speed, and sets it turning.
func apply_car_bump(offset: Vector3, new_velocity: Vector3, yaw_kick: float) -> void:
	global_position += offset
	var planar := Vector3(new_velocity.x, 0.0, new_velocity.z)
	if GameState.arcade_drive:
		_arcade.apply_planar_velocity(self, planar, _car_center)
		_arcade.kick_yaw(yaw_kick)
		forward_speed = _arcade.forward_speed
		heading_yaw = _arcade.heading_yaw
	else:
		_dynamics.cg_velocity = planar
		_dynamics.yaw_rate += yaw_kick
		velocity = planar
		_sync_motion_state()


## A hit from a barrier or the other car, by how much it changed this car's speed.
func take_hit(speed_change: float) -> bool:
	if not _damage.take_hit(speed_change):
		return false
	var jolt := clampf(speed_change / _CarDamage.TOTAL_MPS, 0.3, 1.0)
	_rumble.pulse(jolt * 0.6, jolt)
	_chase_cam.jolt(speed_change)
	_damage.update_smoke(_visual.get_node_or_null("CarBody") as Node3D)
	return true


## Through a sawhorse: a jolt, some damage by `harm` as a change of speed, and a little speed gone.
func hit_sawhorse(harm: float, speed_lost: float) -> void:
	take_hit(harm)
	scrape_road(speed_lost)


## A flat rock under the car: a jolt and some speed gone, with no damage, as in Street Rod 2.
func scrape_road(speed_lost: float) -> void:
	_chase_cam.jolt(speed_lost)
	if GameState.arcade_drive:
		_arcade.forward_speed = move_toward(_arcade.forward_speed, 0.0, speed_lost)
		forward_speed = _arcade.forward_speed
	else:
		var speed := _dynamics.cg_velocity.length()
		if speed > 0.01:
			_dynamics.cg_velocity *= maxf(speed - speed_lost, 0.0) / speed


func damage_amount() -> float:
	return _damage.amount


func get_gear_label() -> String:
	if _gear == GEAR_REVERSE:
		return "R"
	if _gear == GEAR_NEUTRAL:
		return "N"
	var count := _gear_count()
	if _is_automatic():
		return "D%d / %d" % [_gear + 1, count]
	return "%d / %d" % [_gear + 1, count]


func get_short_gear_label() -> String:
	if _gear == GEAR_REVERSE:
		return "R"
	if _gear == GEAR_NEUTRAL:
		return "N"
	if _is_automatic():
		return "D"
	return str(_gear + 1)


func is_automatic_gearbox() -> bool:
	return _is_automatic()


func is_cockpit_camera() -> bool:
	return _cam_mode == CAM_COCKPIT


func get_gear_index() -> int:
	return _gear


func get_gear_count() -> int:
	return _gear_count()


func is_engine_blown() -> bool:
	return _engine_blown


## A tire blows at `corner`, an index into the wheels (front left, front right, rear left,
## rear right).
func blow_tire(corner: int) -> void:
	if has_flat_tire():
		return
	var wheels := _dynamics.wheels()
	_flat_corner = wheels[corner].local_position if corner >= 0 and corner < wheels.size() else _car_center + Vector3(0.75, 0.0, 1.5)
	_flat_side = 1.0 if _flat_corner.x >= _car_center.x else -1.0
	_body_motion.flat_wheel = corner
	_flat_s = 0.0
	_rumble.pulse(0.8, 1.0)
	_chase_cam.jolt(6.0)
	if GameState.arcade_drive:
		_arcade.kick_yaw(_flat_side * FLAT_YAW_KICK)
	else:
		_dynamics.yaw_rate += _flat_side * FLAT_YAW_KICK


func has_flat_tire() -> bool:
	return _flat_side != 0.0


func _flat_pull() -> float:
	if not has_flat_tire():
		return 0.0
	return _flat_side * lerpf(FLAT_PULL_START, FLAT_PULL_FULL, clampf(_flat_s / FLAT_PULL_RAMP_S, 0.0, 1.0))


## The flat slows the car, and its corner of the body sits down onto the rim.
func _ride_on_flat(delta: float) -> void:
	if not has_flat_tire():
		return
	_flat_s += delta
	if not _air.airborne:
		var lost := FLAT_DRAG * delta
		if GameState.arcade_drive:
			_arcade.forward_speed = move_toward(_arcade.forward_speed, 0.0, lost)
		else:
			var speed := _dynamics.cg_velocity.length()
			if speed > 0.01:
				_dynamics.cg_velocity *= maxf(speed - lost, 0.0) / speed
	var drop := FLAT_DROP_M * clampf(_flat_s / FLAT_DROP_S, 0.0, 1.0)
	_body_motion.flat_drop = drop
	var from_center := _flat_corner - _car_center
	# Half the drop from rolling and half from pitching puts the whole of it on that corner.
	_body_motion.flat_roll = -signf(from_center.x) * 0.5 * drop / maxf(absf(from_center.x), 0.3)
	_body_motion.flat_pitch = -signf(from_center.z) * 0.5 * drop / maxf(absf(from_center.z), 0.5)


func is_wrecked() -> bool:
	return _damage.is_totaled()


func get_rpm() -> float:
	if _engine_blown:
		return 0.0
	var rpm := _road_rpm()
	rpm = lerpf(rpm, maxf(rpm, BURNOUT_RPM), _burnout)
	rpm = maxf(rpm, _clutch_rpm)
	return clampf(rpm, RPM_IDLE_MIN, RPM_METER_MAX)


## The revs the road speed turns the engine at in this gear.
func _road_rpm() -> float:
	if _gear == GEAR_NEUTRAL:
		return RPM_IDLE
	var top := _reverse_top() if _gear == GEAR_REVERSE else _gear_top_mps(_gear)
	if top <= 0.05:
		return RPM_IDLE
	return RPM_IDLE + (RPM_REDLINE - RPM_IDLE) * (absf(forward_speed) / top)


func get_rpm_shift_start() -> float:
	return RPM_SHIFT_START


func get_rpm_redline() -> float:
	return RPM_REDLINE


func get_rpm_critical() -> float:
	return RPM_CRITICAL


func _cache_axles() -> void:
	if _visual == null:
		return
	_car_center = _visual.position


func _apply_car_spec() -> void:
	var chassis := GameState.race_chassis()
	var grip_rating := GameState.tire_grip()
	_dynamics.apply_setup(chassis, grip_rating)
	_arcade.apply_spec(chassis, grip_rating)


func _layout_wheels() -> void:
	var points: Array[Vector3] = []
	if _visual != null:
		for wname: String in ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]:
			var wheel := _visual.get_node_or_null(wname) as Node3D
			if wheel == null:
				points.clear()
				break
			points.append(to_local(wheel.global_position))
	if points.size() == 4:
		_dynamics.set_wheel_positions(points)
	else:
		_dynamics.layout_about(Vector3(_car_center.x, 0.0, _car_center.z))


func _sync_motion_state() -> void:
	forward_speed = _dynamics.longitudinal_speed()
	heading_yaw = _dynamics.yaw


func _hold_still() -> void:
	_sync_motion_state()
	_dynamics.pose_body(self, false)
	move_and_slide()
	_skids.end_strips()


func _steer_input() -> float:
	var s := _Controller.amount(_Controller.STEER_LEFT) - _Controller.amount(_Controller.STEER_RIGHT)
	if _touch != null and _touch.has_method(&"get_steer"):
		var touch_steer: float = _touch.get_steer()
		if not is_zero_approx(touch_steer):
			s = touch_steer
	if is_zero_approx(s):
		s = _Controller.steer()
	return clampf(s + _mouse_drive.steering + _flat_pull(), -1.0, 1.0)


func _throttle_down() -> bool:
	return _throttle_amount() > 0.0


func _brake_down() -> bool:
	return _brake_amount() > 0.0


## How far down each pedal is, from 0 to 1. Keys and the touch pedals are all or nothing.
func _throttle_amount() -> float:
	if _touch != null and _touch.has_method(&"is_throttle_down") and _touch.is_throttle_down():
		return 1.0
	return maxf(maxf(_Controller.amount(_Controller.THROTTLE), _Controller.pedal(_Controller.THROTTLE)), maxf(_mouse_drive.pedals, 0.0))


func _brake_amount() -> float:
	if _touch != null and _touch.has_method(&"is_brake_down") and _touch.is_brake_down():
		return 1.0
	return maxf(maxf(_Controller.amount(_Controller.BRAKE), _Controller.pedal(_Controller.BRAKE)), maxf(-_mouse_drive.pedals, 0.0))


## Gas and brake together with the car all but stopped, which is how a burnout starts. In neutral
## nothing drives the wheels, so the gas only revs the engine.
func _burnout_held() -> bool:
	return _throttle_amount() >= BURNOUT_PEDAL and _brake_amount() >= BURNOUT_PEDAL and not _engine_blown and absf(forward_speed) < BURNOUT_MAX_SPEED and _gear != GEAR_NEUTRAL


## The wheels spin, the engine revs, the tires smoke and mark the road, and the back of the car
## can be swung round, but it does nothing for the launch or the tires yet. See docs/todo.md.
func _update_burnout(delta: float) -> void:
	if _burnout_held():
		_burnout = move_toward(_burnout, 1.0, BURNOUT_RISE * delta)
	else:
		_burnout = move_toward(_burnout, 0.0, BURNOUT_FALL * delta)
	if _burnout <= 0.0:
		_burnout_swing = 0.0
		return
	_swing_burnout(delta)
	var track := _race_track()
	var wheels := _dynamics.wheels()
	var forward := global_transform.basis.z.normalized()
	var pivot := global_transform * _front_axle()
	var swing := absf(_burnout_swing * _burnout)
	for i in wheels.size():
		var wheel: _VehicleDynamics.Wheel = wheels[i]
		if wheel.front:
			continue
		var world: Vector3 = global_transform * wheel.local_position
		var ground_y := wheel.road_y
		if track != null and track.has_method(&"surface_height"):
			ground_y = float(track.surface_height(world))
		# A tire swinging round leaves its rubber along the way it slides, so the marks join up into an arc.
		var arm := Vector3(world.x - pivot.x, 0.0, world.z - pivot.z)
		var along := Vector3.UP.cross(arm).normalized()
		if along.dot(forward) < 0.0:
			along = -along
		var mark_dir := forward.lerp(along, clampf(swing * arm.length() / BURNOUT_MARK_SLIDE, 0.0, 1.0)).normalized()
		_skids.burn(i, world, ground_y, mark_dir, _burnout)
	_skids.flush()


## Rear tires spinning in a burnout have no grip left to hold the back of the car sideways, so
## it swings round the braked front wheels: the way the wheel is turned, and a little on its own.
func _swing_burnout(delta: float) -> void:
	_burnout_time += delta
	var wander := _burnout_wander.get_noise_1d(_burnout_time) * BURNOUT_WANDER
	var wanted := _steer_input() * BURNOUT_SWING_RATE + wander
	_burnout_swing = move_toward(_burnout_swing, wanted, BURNOUT_SWING_ACCEL * delta)
	var turn := _burnout_swing * _burnout * delta
	if is_zero_approx(turn):
		return
	var pivot := global_transform * _front_axle()
	var moved := pivot + (global_position - pivot).rotated(Vector3.UP, turn)
	rotation.y += turn
	heading_yaw = rotation.y
	_arcade.heading_yaw = rotation.y
	_dynamics.yaw = wrapf(rotation.y, -PI, PI)
	# Through move_and_slide, so a barrier still stops the car.
	var kept := velocity
	velocity = (moved - global_position) / delta
	move_and_slide()
	velocity = kept


## The middle of the front axle, in the car's own space.
func _front_axle() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for wheel: _VehicleDynamics.Wheel in _dynamics.wheels():
		if wheel.front:
			sum += wheel.local_position
			count += 1
	if count == 0:
		return _car_center + Vector3(0.0, 0.0, _ArcadeDrive.WHEELBASE_M * 0.5)
	return sum / float(count)


## The hand brake works with the clutch in, so on the gas the engine keeps revving instead of
## falling with the road speed. When the clutch comes out the revs come down to the road's, and
## if the car is moving, what they had over it gives a short kick of extra pull.
func _update_clutch(delta: float) -> void:
	var road := _road_rpm()
	if _gear == GEAR_NEUTRAL and not _engine_blown:
		_rev_in_neutral(delta)
		return
	var handbrake := _handbrake_down()
	if handbrake and _throttle_down() and not _burnout_held() and not _engine_blown:
		var held := maxf(_clutch_rpm, road)
		var free := lerpf(RPM_IDLE, CLUTCH_FREE_RPM, _throttle_amount())
		_clutch_rpm = move_toward(held, maxf(held, free), CLUTCH_REV_RATE * delta)
		_clutch_kicks = forward_speed >= CLUTCH_KICK_SPEED
		return
	if handbrake or _clutch_rpm <= 0.0:
		_clutch_kicks = false
	_clutch_rpm = move_toward(_clutch_rpm, road, CLUTCH_CATCH_RATE * delta)
	if _clutch_rpm <= road:
		_clutch_rpm = 0.0
		_clutch_kicks = false


## In neutral the engine turns free of the road: the revs follow the gas pedal, up to
## CLUTCH_FREE_RPM with it all the way down, and fall back to idle when it comes up. Going into
## gear, they come down to the road's as when the clutch comes out, with the same kick if moving.
func _rev_in_neutral(delta: float) -> void:
	var wanted := lerpf(RPM_IDLE, CLUTCH_FREE_RPM, _throttle_amount())
	var revs := maxf(_clutch_rpm, RPM_IDLE)
	var rate := CLUTCH_REV_RATE if wanted > revs else CLUTCH_CATCH_RATE
	_clutch_rpm = move_toward(revs, wanted, rate * delta)
	_clutch_kicks = forward_speed >= CLUTCH_KICK_SPEED


## On the gas with the engine free of the road, in neutral or with the hand brake's clutch in.
func _revving_free() -> bool:
	return _throttle_down() and _clutch_rpm > 0.0 and not _engine_blown


## How much the clutch kick adds to the gear's pull, as a factor.
func _clutch_kick() -> float:
	if not _clutch_kicks:
		return 1.0
	var over := maxf(_clutch_rpm - _road_rpm(), 0.0) / (RPM_REDLINE - RPM_IDLE)
	return 1.0 + CLUTCH_KICK * over


## Paving drawn over the ground where there is no track to say how high it is, as in free roam,
## for the skid marks to lie on.
func set_mark_paving(source: Object) -> void:
	_skids.paving = source


func _handbrake_down() -> bool:
	if _Controller.action_down(_Controller.HANDBRAKE):
		return true
	return _touch != null and _touch.has_method(&"is_handbrake_down") and _touch.is_handbrake_down()


func begin_park(slot: float) -> void:
	if _parking or _halting:
		return
	stop_mouse_driving()
	_parking = true
	_park_slot = slot
	_burnout = 0.0
	_park_speed = maxf(forward_speed, 0.0)
	_clutch_rpm = 0.0
	_clutch_kicks = false
	_skids.end_strips()


## Takes the controls away from a car whose race is over and lets it slide to a stop where it
## is, as a wreck or a car that lost its engine or a tire would. A car that finished parks instead.
func halt() -> void:
	if _parking or _halting:
		return
	stop_mouse_driving()
	_halting = true
	_burnout = 0.0
	_clutch_rpm = 0.0
	_clutch_kicks = false
	_skids.end_strips()


func _halt_step(delta: float) -> void:
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var speed := planar.length()
	if speed > 0.0:
		planar *= move_toward(speed, 0.0, HALT_DECEL * delta) / speed
	velocity = planar
	move_and_slide()
	planar = Vector3(velocity.x, 0.0, velocity.z)
	velocity = planar
	heading_yaw = rotation.y
	forward_speed = planar.dot(Vector3(sin(heading_yaw), 0.0, cos(heading_yaw)))
	_dynamics.cg_velocity = planar
	_stick_to_road()
	_update_engine_sound(false)
	_body_motion.ride_from_motion(delta, planar, heading_yaw)
	_pose_body(delta)


func _physics_process(delta: float) -> void:
	_damage.tick(delta)
	_poll_camera()
	if _halting:
		_halt_step(delta)
		return
	if _parking:
		_park_speed = _RacePark.step(self, _dynamics, delta, _park_speed, _park_slot)
		forward_speed = _park_speed
		heading_yaw = rotation.y
		_stick_to_road()
		_update_engine_sound(false)
		_body_motion.ride_from_motion(delta, _dynamics.cg_velocity, rotation.y)
		_pose_body(delta)
		return
	_poll_touch_shifts()
	_poll_shifter()
	var on_wheel := _Controller.is_wheel_steering()
	_dynamics.direct_steer = on_wheel
	_arcade.direct_steer = on_wheel
	# Runs during the countdown too, so a gear picked on the start line is in by the green light.
	if _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - delta)
	_update_clutch(delta)
	_ride_on_flat(delta)
	if _air.airborne:
		_physics_air(delta)
	elif GameState.arcade_drive:
		_physics_arcade(delta)
		_dynamics.sample_surfaces(_race_track(), global_transform)
		_body_motion.ride_from_motion(delta, _arcade.planar_velocity(), heading_yaw)
	else:
		_physics_simulation(delta)
		_body_motion.note_velocity(_dynamics.cg_velocity)
	_update_burnout(delta)
	_update_rumble(delta)
	_stick_to_road()
	_pose_body(delta)


func _pose_body(delta: float) -> void:
	var race := get_parent()
	if race != null and race.has_method(&"is_race_started") and not race.is_race_started():
		_chase_cam.settle(rotation.y)
		_place_camera(0.0)
		return
	_body_motion.capture()
	var on_arcade := GameState.arcade_drive and not _parking
	var steer: float = _arcade.steer_angle if on_arcade else _dynamics.steer_angle()
	var steer_input: float = _arcade.steer_input() if on_arcade else _dynamics.steer_input()
	_body_motion.pose(delta, forward_speed, steer, steer_input, _burnout * BURNOUT_WHEEL_SPEED, get_rpm())
	_place_camera(delta)


func _physics_simulation(delta: float) -> void:
	if _arcade_active:
		_dynamics.reset_all_motion()
		_dynamics.yaw = heading_yaw
		_dynamics.cg_velocity = Vector3(sin(heading_yaw), 0.0, cos(heading_yaw)) * forward_speed
		_arcade_active = false
	var race := get_parent()
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		_dynamics.reset_all_motion()
		_hold_still()
		_update_engine_sound(_revving_free())
		_update_debug_draw()
		return

	var throttle := _throttle_down() and not _burnout_held()
	var brake := _brake_down()
	var steer := _steer_input()
	if _engine_blown:
		throttle = false
	elif _is_automatic():
		_auto_shift(throttle, brake)

	var track := _race_track()
	if _escape_obstacle(track):
		_dynamics.reset_motion()
		_dynamics.update_steering(delta, 0.0)
		_hold_still()
		_update_overrev(delta)
		_update_engine_sound(throttle)
		_update_debug_draw()
		return

	var handbrake := _handbrake_down()
	_dynamics.handbrake_input = 1.0 if handbrake else 0.0
	var drive := 0.0
	var brake_input := 0.0
	if throttle and _shift_timer <= 0.0 and not handbrake:
		drive = _requested_drive_force() * _throttle_amount() * _clutch_kick()
	elif brake:
		brake_input = _brake_amount()
	_dynamics.sample_surfaces(track, global_transform)
	_dynamics.step(delta, steer, drive, brake_input)
	_sync_motion_state()
	_dynamics.pose_body(self, true)
	var before := velocity
	move_and_slide()
	if _scrape_barrier(before, delta):
		_skids.end_strips()
	else:
		_skids.record(_dynamics.wheels(), global_transform, _race_track())

	_update_overrev(delta)
	_update_engine_sound(throttle)
	_update_debug_draw()


func _physics_arcade(delta: float) -> void:
	if not _arcade_active:
		_arcade.forward_speed = forward_speed
		_arcade.heading_yaw = heading_yaw
		_arcade_active = true
	var race := get_parent()
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		_arcade.hold(self, delta, _car_center)
		move_and_slide()
		forward_speed = 0.0
		heading_yaw = _arcade.heading_yaw
		_skids.end_strips()
		_update_engine_sound(_revving_free())
		return

	var throttle := _throttle_down() and not _burnout_held()
	var brake := _brake_down()
	var steer := _steer_input()
	if _engine_blown:
		throttle = false
	elif _is_automatic():
		_auto_shift(throttle, brake)

	if _escape_obstacle(_race_track()):
		_arcade.hold(self, delta, _car_center)
		move_and_slide()
		forward_speed = 0.0
		heading_yaw = _arcade.heading_yaw
		_skids.end_strips()
		_update_overrev(delta)
		_update_engine_sound(throttle)
		return

	var limits := _speed_limits()
	_arcade.ride_grip = _dynamics.ride_grip()
	_arcade.step(
		self,
		delta,
		steer,
		throttle and _gear != GEAR_NEUTRAL,
		brake,
		_handbrake_down(),
		_shift_timer > 0.0,
		_engine_blown,
		_signed_gear_accel() * _clutch_kick(),
		limits.y,
		_car_center,
		limits.x,
		_throttle_amount(),
		_brake_amount()
	)
	var before := velocity
	move_and_slide()
	if _scrape_barrier(before, delta):
		_skids.end_strips()
	else:
		_skids.record_axles(
			_dynamics.wheels(),
			global_transform,
			_race_track(),
			_arcade.forward_speed,
			_arcade.front_grip_use,
			_arcade.front_slip_angle,
			_arcade.front_long_slip,
			_arcade.rear_grip_use,
			_arcade.rear_slip_angle,
			_arcade.rear_long_slip
		)
	forward_speed = _arcade.forward_speed
	heading_yaw = _arcade.heading_yaw
	_update_overrev(delta)
	_update_engine_sound(throttle)


## In the air the car keeps the speed and heading it took off with. The arcade and simulation models
## sit as they were until it lands, so it comes down going the way it left.
func _physics_air(delta: float) -> void:
	var throttle := _throttle_down() and not _engine_blown
	velocity.y = 0.0
	move_and_slide()
	_skids.end_strips()
	_update_overrev(delta)
	_update_engine_sound(throttle)


func _is_automatic() -> bool:
	return bool(_gearbox.get("automatic", false))


func _gear_count() -> int:
	return _ratios().size()


func _ratios() -> Array:
	var ratios: Variant = _gearbox.get("ratios", [1.0])
	if typeof(ratios) != TYPE_ARRAY or ratios.is_empty():
		return [1.0]
	return ratios


func _gear_top_mps(gear_index: int) -> float:
	var ratios := _ratios()
	var i := clampi(gear_index, 0, ratios.size() - 1)
	var top_ratio := float(ratios[ratios.size() - 1])
	var ratio := maxf(float(ratios[i]), 0.01)
	var vmax_mps: float = GameState.get_effective_vmax_kmh() / 3.6
	return vmax_mps * (top_ratio / ratio)


## Gear and horsepower scale the configured propulsion force. The tires still
## have to be able to push that hard. Reverse pushes the other way.
func _requested_drive_force() -> float:
	if _gear == GEAR_NEUTRAL:
		return 0.0
	if _gear == GEAR_REVERSE:
		var backing := absf(forward_speed) if forward_speed <= 0.0 else 0.0
		return -_forward_drive_force(0, _reverse_top(), backing)
	return _forward_drive_force(_gear, _gear_top_mps(_gear), maxf(forward_speed, 0.0))


func _forward_drive_force(gear_index: int, top: float, speed: float) -> float:
	var ratios := _ratios()
	var ratio := float(ratios[clampi(gear_index, 0, ratios.size() - 1)])
	return _dynamics.drive_force(ratio * GameState.final_drive_accel(), top, speed, GameState.engine_power_hp) * _damage.power_left()


func _signed_gear_accel() -> float:
	if _gear == GEAR_NEUTRAL:
		return 0.0
	if _gear == GEAR_REVERSE:
		var ratios := _ratios()
		var ratio := float(ratios[0]) * GameState.final_drive_accel()
		var backing := absf(forward_speed) if forward_speed <= 0.0 else 0.0
		var pull := _ArcadeDrive.gear_acceleration(ratio, _reverse_top(), backing, GameState.engine_power_hp)
		return -pull * GameState.weight_accel() * _damage.power_left()
	var ratios := _ratios()
	var ratio := float(ratios[clampi(_gear, 0, ratios.size() - 1)]) * GameState.final_drive_accel()
	var pull := _ArcadeDrive.gear_acceleration(ratio, _gear_top_mps(_gear), maxf(forward_speed, 0.0), GameState.engine_power_hp)
	return pull * GameState.weight_accel() * _damage.power_left()


## Lowest and highest speed this gear allows, in m/s. Neutral coasts either way.
func _speed_limits() -> Vector2:
	var vmax := GameState.get_effective_vmax_kmh() / 3.6
	var reverse_top := _reverse_top()
	if _gear == GEAR_REVERSE:
		return Vector2(-reverse_top, 0.0)
	if _gear == GEAR_NEUTRAL:
		return Vector2(-reverse_top, vmax)
	return Vector2(minf(forward_speed, 0.0), vmax)


func _reverse_top() -> float:
	return maxf(_gear_top_mps(0) * REVERSE_TOP_FRACTION, REVERSE_TOP_MIN)


## The keys and gamepad buttons for shifting, the on-screen paddles, and a sequential shifter.
## The steps run reverse, neutral, first (or drive on an automatic), and up. Reverse only goes in
## once the car has stopped; until then a step down from neutral stays in neutral.
func _select_shift(direction: int) -> void:
	if _engine_blown or _shift_timer > 0.0 or direction == 0:
		return
	_set_gear(_gear_below() if direction < 0 else _gear_above())


func _gear_below() -> int:
	if _gear > 0 and not _is_automatic():
		return _gear - 1
	if _gear >= 0:
		return GEAR_NEUTRAL
	if _gear == GEAR_NEUTRAL and _can_engage_reverse():
		return GEAR_REVERSE
	return _gear


func _gear_above() -> int:
	if _gear == GEAR_REVERSE:
		return GEAR_NEUTRAL
	if _gear < 0:
		return 0
	if _is_automatic():
		return _gear
	return mini(_gear + 1, _gear_count() - 1)


func _can_engage_reverse() -> bool:
	return forward_speed <= REVERSE_ENGAGE_SPEED


func _set_gear(next: int) -> void:
	if next == _gear:
		return
	var prev := _gear
	_rumble.pulse(RUMBLE_SHIFT, 0.0)
	_gear = next
	# Nothing has to mesh going into neutral, so the next shift can follow at once.
	_shift_timer = 0.0 if next == GEAR_NEUTRAL else float(_gearbox.get("shift_time", 0.15))
	_overrev_time = 0.0
	gear_changed.emit(prev, next)


func _request_shift(direction: int) -> void:
	if _engine_blown or _shift_timer > 0.0 or _gear < 0:
		return
	var next := _gear + direction
	if next < 0 or next >= _gear_count():
		return
	var prev := _gear
	_gear = next
	_shift_timer = float(_gearbox.get("shift_time", 0.15))
	_overrev_time = 0.0
	gear_changed.emit(prev, next)


func _auto_shift(throttle: bool, brake: bool) -> void:
	if _shift_timer > 0.0:
		return
	var top := _gear_top_mps(_gear)
	if throttle and _gear < _gear_count() - 1 and forward_speed >= top * 0.90:
		_request_shift(1)
		return
	if _gear <= 0:
		return
	var prev_top := _gear_top_mps(_gear - 1)
	if forward_speed < prev_top * 0.38:
		_request_shift(-1)
	elif (brake or not throttle) and forward_speed < prev_top * 0.62:
		_request_shift(-1)


## What the car is doing, felt through a gamepad: the tires spinning up, rough ground under it,
## a slide, and the engine at its limit. Hits, scrapes, and shifts are jolts of their own.
func _update_rumble(delta: float) -> void:
	var moving := clampf(absf(forward_speed) / RUMBLE_FULL_SPEED, 0.0, 1.0)
	var wheels := _dynamics.wheels()
	var rough := 0.0
	var grip_used := 0.0
	for wheel: _VehicleDynamics.Wheel in wheels:
		rough = maxf(rough, wheel.surface_blend)
		grip_used = maxf(grip_used, wheel.grip_utilization)
	if GameState.arcade_drive:
		grip_used = maxf(_arcade.front_grip_use, _arcade.rear_grip_use)
	var slide := clampf((grip_used - RUMBLE_SLIDE_START) / RUMBLE_SLIDE_FULL, 0.0, 1.0) * moving
	var at_limit := 0.0
	if not _engine_blown and not _is_automatic() and get_rpm() >= RPM_REDLINE:
		at_limit = 0.4
	var ground := rough * clampf(moving * 4.0, 0.0, 1.0)
	var weak := maxf(maxf(_burnout * 0.5, ground * (0.2 + 0.35 * moving)), maxf(slide * 0.35, at_limit))
	var strong := maxf(_burnout * 0.6, ground * 0.3 * moving)
	_rumble.update(delta, weak, strong)


func _exit_tree() -> void:
	_release_mouse_drive()
	_rumble.stop()


func _update_overrev(delta: float) -> void:
	if _engine_blown or _is_automatic():
		_overrev_time = 0.0
		return
	if get_rpm() >= RPM_CRITICAL:
		_overrev_time += delta
		if _overrev_time >= OVERREV_HOLD_S:
			_engine_blown = true
	else:
		_overrev_time = maxf(0.0, _overrev_time - delta * 2.0)


func _update_engine_sound(throttle: bool) -> void:
	if _engine_sound == null or not _engine_sound.has_method(&"set_state"):
		return
	_engine_sound.set_state(get_rpm(), 1.0 if throttle else 0.0, _engine_blown, _shift_timer > 0.0)


func _poll_camera() -> void:
	var held := _Controller.action_down(_Controller.CAMERA)
	if (held and not _camera_held) or _tapped_camera:
		_cam_mode = (_cam_mode + 1) % 4
		GameState.driving_camera = _cam_mode
		_apply_camera_mode()
	_camera_held = held
	_tapped_camera = false


func _poll_shifter() -> void:
	var up := _Controller.action_down(_Controller.UP)
	if (up and not _shifter_up_held) or _tapped_up:
		_select_shift(1)
	_shifter_up_held = up
	_tapped_up = false
	var down := _Controller.action_down(_Controller.DOWN)
	if (down and not _shifter_down_held) or _tapped_down:
		_select_shift(-1)
	_shifter_down_held = down
	_tapped_down = false

	var wanted := _shifter_wanted_gear()
	if wanted == _shifter_gear or _engine_blown or _shift_timer > 0.0:
		return
	_shifter_gear = wanted
	if wanted != _Controller.POSITION_NONE:
		_set_gear(wanted)


## Any forward position is drive on an automatic. A car with fewer gears than the shifter has
## its top gear in the rest. Reverse waits in neutral until the car has slowed enough for it.
func _shifter_wanted_gear() -> int:
	var lever := _Controller.position()
	if lever == _Controller.POSITION_REVERSE:
		return GEAR_REVERSE if _can_engage_reverse() else GEAR_NEUTRAL
	if lever < 0:
		return lever
	return 0 if _is_automatic() else mini(lever, _gear_count() - 1)


func _poll_touch_shifts() -> void:
	if _touch == null:
		return
	if _touch.has_method(&"pop_shift_up") and _touch.pop_shift_up():
		_select_shift(1)
	if _touch.has_method(&"pop_shift_down") and _touch.pop_shift_down():
		_select_shift(-1)


func _stick_to_road() -> void:
	var track := _race_track()
	if track == null or not track.has_method(&"surface_height"):
		rotation.x = 0.0
		return
	var here: float = track.surface_height(global_position)
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	if track.has_method(&"has_jumps") and track.has_jumps():
		var planar := Vector3(velocity.x, 0.0, velocity.z)
		var speed := planar.length()
		var travel := planar / speed if speed > 0.1 else forward
		var delta := get_physics_process_delta_time()
		_air.step(track, global_position, travel, speed, delta)
		here = _air.height
		if _air.airborne:
			global_position.y = _road_base_y + here
			rotation.x = _air.flight_pitch(rotation.x, speed, delta)
			return
		if _air.impact > LANDING_FELT_MPS:
			_land(_air.impact)
	global_position.y = _road_base_y + here
	var ahead: float = track.surface_height(global_position + forward * _ROAD_PITCH_SPAN)
	var behind: float = track.surface_height(global_position - forward * _ROAD_PITCH_SPAN)
	rotation.x = -atan2(ahead - behind, _ROAD_PITCH_SPAN * 2.0)
	if track.has_method(&"surface_roll"):
		rotation.z = track.surface_roll(global_position, rotation.y)
	if track.has_method(&"bank_push") and not _parking:
		global_position += track.bank_push(global_position) * get_physics_process_delta_time()


## Coming down off a jump: a jolt, damage past what the springs take, and some speed gone.
func _land(impact: float) -> void:
	take_hit(_AirTime.landing_harm(impact))
	scrape_road(impact * LANDING_SPEED_LOSS)
	var jolt := clampf(impact / 8.0, 0.1, 1.0)
	_rumble.pulse(jolt * 0.6, jolt * 0.5)


func _race_track() -> Node:
	var race := get_parent()
	if race != null and race.has_method(&"get_race_track"):
		return race.get_race_track()
	return null


func _escape_obstacle(track: Node) -> bool:
	if track == null or not track.has_method(&"obstacle_escape"):
		return false
	var safe: Vector3 = track.obstacle_escape(global_position)
	if safe.is_equal_approx(global_position):
		return false
	global_position = safe
	return true


## Applies touching a barrier to the driving model. True when one was touched.
func _scrape_barrier(before: Vector3, delta: float) -> bool:
	var hit := _WallScrape.resolve(self, before, delta)
	if hit.is_empty():
		return false
	take_hit(_damage.barrier_hit(float(hit["into"]) * (1.0 + _WallScrape.BOUNCE)))
	_rumble.pulse(RUMBLE_SCRAPE, RUMBLE_SCRAPE)
	var after: Vector3 = hit["velocity"]
	if GameState.arcade_drive:
		_arcade.apply_planar_velocity(self, after, _car_center)
		_arcade.swing_by(_WallScrape.arcade_swing(_race_track(), self, _arcade.heading_yaw, after))
	else:
		_dynamics.cg_velocity = after
		velocity = after
		_dynamics.yaw_rate = _WallScrape.turn_rate(_race_track(), self, _dynamics.yaw)
		_sync_motion_state()
	return true


func _update_debug_draw() -> void:
	if not debug_dynamics:
		if _debug_view != null:
			_debug_view.visible = false
		for label in _debug_labels:
			label.visible = false
		return
	_ensure_debug_view()
	_debug_view.visible = true
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_view.material_override)
	var cg := _dynamics.cg_local
	_debug_cross(mesh, cg, 0.35, Color(1.0, 0.85, 0.2))
	var v_body := _dynamics.body_velocity()
	var v_scale: float = _dynamics.config.debug_velocity_scale
	_debug_line(mesh, cg, cg + Vector3(v_body.x, 0.0, v_body.z) * v_scale, Color(0.3, 0.85, 1.0))
	var accel_scale := 0.12
	var long_a := _dynamics.longitudinal_accel()
	var lat_a := _dynamics.lateral_accel()
	_debug_line(mesh, cg, cg + Vector3(0.0, 0.15, long_a * accel_scale), Color(1.0, 0.55, 0.15))
	_debug_line(mesh, cg, cg + Vector3(lat_a * accel_scale, 0.15, 0.0), Color(0.85, 0.35, 1.0))
	var f_scale: float = _dynamics.config.debug_force_scale
	var weight := maxf(_dynamics.config.mass_kg * _dynamics.config.gravity, 1.0)
	var wheels := _dynamics.wheels()
	for i in wheels.size():
		var wheel: _VehicleDynamics.Wheel = wheels[i]
		var contact := Vector3(wheel.local_position.x, 0.0, wheel.local_position.z)
		var contact_color := Color(0.9, 0.9, 0.9).lerp(Color(0.45, 0.75, 0.3), wheel.surface_blend)
		_debug_cross(mesh, contact, 0.18, contact_color)
		var load_height := wheel.normal_load / weight * 1.6
		_debug_line(mesh, contact, contact + Vector3(0.0, load_height, 0.0), Color(0.95, 0.9, 0.4))
		var ahead := Vector3(sin(wheel.steer_angle), 0.0, cos(wheel.steer_angle))
		var right := Vector3(cos(wheel.steer_angle), 0.0, -sin(wheel.steer_angle))
		_debug_line(mesh, contact, contact + ahead * 0.7, Color(0.3, 0.9, 0.4))
		_debug_line(mesh, contact, contact + ahead * clampf(wheel.long_slip, -2.5, 2.5) * 0.45, Color(0.95, 0.75, 0.2))
		_debug_line(mesh, contact, contact + right * wheel.slip_angle * 1.4, Color(0.4, 0.75, 1.0))
		var used := clampf(wheel.grip_utilization, 0.0, 1.0)
		_debug_line(mesh, contact, contact + wheel.force_body * f_scale, Color(used, 1.0 - used, 0.15))
		if i + 1 < _debug_labels.size():
			var label := _debug_labels[i + 1]
			label.visible = true
			label.position = contact + Vector3(0.0, load_height + 0.35, 0.0)
			var surface := wheel.surface_name
			if wheel.surface_blend > 0.02 and wheel.surface_blend < 0.98:
				surface = "%s %.0f%%" % [wheel.surface_name, wheel.surface_blend * 100.0]
			label.text = "%s\n%.0f N\nuse %.0f%%\nlat %.0f deg\nslip %.2f" % [
				surface,
				wheel.normal_load,
				wheel.grip_utilization * 100.0,
				rad_to_deg(wheel.slip_angle),
				wheel.long_slip,
			]
	mesh.surface_end()
	_debug_view.mesh = mesh
	var summary := _debug_labels[0]
	summary.visible = true
	summary.position = cg + Vector3(0.0, 0.85, 0.0)
	summary.text = "%.0f km/h\nlong a %.1f\nlat a %.1f" % [
		v_body.z * 3.6,
		long_a,
		lat_a,
	]


func _ensure_debug_view() -> void:
	if _debug_view == null:
		_debug_view = MeshInstance3D.new()
		_debug_view.name = "DynamicsDebug"
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		_debug_view.material_override = mat
		_debug_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_view)
	if _debug_labels.size() == 5:
		return
	for _i in 5:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 48
		label.pixel_size = 0.002
		label.outline_size = 6
		label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		add_child(label)
		_debug_labels.append(label)


func _debug_line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)


func _debug_cross(mesh: ImmediateMesh, center: Vector3, size: float, color: Color) -> void:
	_debug_line(mesh, center - Vector3(size, 0.0, 0.0), center + Vector3(size, 0.0, 0.0), color)
	_debug_line(mesh, center - Vector3(0.0, size, 0.0), center + Vector3(0.0, size, 0.0), color)
	_debug_line(mesh, center - Vector3(0.0, 0.0, size), center + Vector3(0.0, 0.0, size), color)
