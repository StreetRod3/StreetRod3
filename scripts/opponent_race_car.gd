extends CharacterBody3D

## Same planar vehicle as the player. The racing line is only a driver:
## it picks steer, throttle, and brake. The tires still make the motion.

const _VehicleDynamics := preload("res://scripts/vehicle_dynamics.gd")
const _SkidMarks := preload("res://scripts/skid_marks.gd")
const _ArcadeDrive := preload("res://scripts/arcade_drive.gd")
const _RacePark := preload("res://scripts/race_park.gd")
const _CarBodyMotion := preload("res://scripts/car_body_motion.gd")
const _WallScrape := preload("res://scripts/wall_scrape.gd")
const _CarDamage := preload("res://scripts/car_damage.gd")

## The path-following opponent from before the tire simulation.
## What a preset `accel_scale` of 1 gets of the pull the arcade drive gives a car. Set so
## the ladder of rivals lines up with what the player's car can do there.
const ARCADE_DRIVER_PULL := 46.0 / 24.0
const ARCADE_RATIOS: Array[float] = [2.52, 1.52, 1.00]
## How far ahead the arcade rails read the road's curve for the tires' share of power, in meters.
const _ARCADE_CURVE_STEP_M := 6.0
## The rear tires' share of a car's grip while it is pulling away.
const _ARCADE_REAR_GRIP_SHARE := 0.6

## Opponent preset `accel_scale` that matches the player's drive force.
const PRESET_ACCEL_REF := 0.30
## Share of the tire grip the driver plans to use in corners.
const CORNER_GRIP_USE := 0.5
## The same on the arcade rails, where the driver cannot lose it.
const ARCADE_CORNER_GRIP_USE := 0.8
## Heading error that asks for full steering input.
const STEER_FULL_ERROR_RAD := 0.175
## Steering per meter of drift from the chosen lane.
const STEER_PER_LANE_M := 0.1
## How far ahead, in seconds of travel, the driver reads the road heading.
const STEER_LOOKAHEAD_S := 0.4
## Steering against the current yaw rate, per rad/s.
const STEER_YAW_DAMPING := 0.55
## Body slip speed where the driver stops steering at the line and catches the slide.
const SLIDE_LATERAL_MPS := 4.0
const LANE_EDGE_MARGIN_M := 1.8
## How a rival moves around something on the road: how early it looks, and how fast it goes across.
const DODGE_LOOK_S := 2.2
const DODGE_LOOK_M := 25.0
const DODGE_MPS := 7.0
## On a tight road: what share of the gap to its lane it closes in a second, and how fast at most.
const TIGHT_CLOSE_RATE := 4.0
const TIGHT_MAX_MPS := 4.5
const TIGHT_EDGE_MARGIN_M := 1.0
## Turn rate on the arcade rails that shows as a full steering input, in rad/s.
const _RAIL_FULL_YAW_RATE := 0.5
## How quickly a sideways shove on the arcade rails dies away, in 1/seconds.
const _RAIL_SHOVE_DECAY := 2.2
## How quickly a hit's turn on the arcade rails dies away, and how fast the nose comes back.
const _RAIL_SPIN_DECAY := 3.0
const _RAIL_WOBBLE_RETURN := 3.5
## How hard a totaled car comes to a stop, in m/s².
const _TOTALED_BRAKE := 11.0

var forward_speed: float = 0.0

@onready var _dynamics: _VehicleDynamics = get_node_or_null("VehicleDynamics") as _VehicleDynamics
var _skids: _SkidMarks
var _visual: Node3D
var _gearbox: Dictionary = {}
var _gear: int = 0
var _shift_timer: float = 0.0
var _shift_time: float = 0.35
var _drive_scale: float = 1.0
var _power_hp: float = 280.0
var _max_mps: float = 40.0
var _lane_x: float = 0.0
## The lane being held, which eases around what is on the road.
var _dodge_lane: float = 0.0
var _dodge_ready: bool = false
var _lane_ready: bool = false
var _path_s: float = 0.0
var _path_yaw: float = 0.0
var _lateral: float = 0.0
var _arcade_active: bool = false
var _body_motion: _CarBodyMotion = _CarBodyMotion.new()
var _last_yaw: float = 0.0
var _rail_yaw_rate: float = 0.0
var _rail_shove: float = 0.0
var _rail_spin: float = 0.0
var _rail_wobble: float = 0.0
var _damage: _CarDamage = _CarDamage.new()
var _arcade_gear: int = 0
var _arcade_shift: float = 0.0
var _arcade_driver: float = 0.3
var _arcade_grip: float = 3.0
var _parking := false
var _park_speed := 0.0
var _park_slot := 0.0
## Body height on flat ground. Track height is added on top of this.
var _road_base_y: float = 0.0
const _ROAD_PITCH_SPAN := 8.0


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
	_visual = get_node_or_null("CarPivot") as Node3D
	var opp := GameState.selected_opponent()
	_apply_opponent_look(opp)
	_drive_scale = float(opp.get("accel_scale", PRESET_ACCEL_REF)) / PRESET_ACCEL_REF
	_shift_time = float(opp.get("shift_time", 0.35))
	var top_mps: float = GameState.opponent_top_kmh(opp) / 3.6
	_max_mps = top_mps * float(opp.get("vmax_scale", 0.90))
	_power_hp = GameState.opponent_power_hp(opp)
	_arcade_grip = GameState.opponent_tire_grip(opp)
	_arcade_driver = ARCADE_DRIVER_PULL * float(opp.get("accel_scale", 0.30)) * _ArcadeDrive.grip_accel_scale(_arcade_grip)
	_lane_x = global_position.x
	_apply_car_spec()
	_layout_wheels()
	_body_motion.setup(_visual, _dynamics)
	_dynamics.yaw = rotation.y
	_last_yaw = rotation.y
	_skids = _SkidMarks.new()
	_skids.name = "SkidMarks"
	add_child(_skids)
	_gearbox = GameState.opponent_gearbox(opp)
	_gear = 0


func get_path_s() -> float:
	return _path_s


func planar_velocity() -> Vector3:
	if GameState.arcade_drive:
		return Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * forward_speed
	return _dynamics.cg_velocity


func get_mass_kg() -> float:
	return _dynamics.config.mass_kg


## A hit from the other car or a barrier, by how much it changed this car's speed.
func take_hit(speed_change: float) -> bool:
	if not _damage.take_hit(speed_change):
		return false
	_damage.update_smoke(_visual.get_node_or_null("CarBody") as Node3D if _visual != null else null)
	return true


## Through a sawhorse: some damage by `harm` as a change of speed, and a little speed gone.
func hit_sawhorse(harm: float, speed_lost: float) -> void:
	take_hit(harm)
	if GameState.arcade_drive:
		forward_speed = maxf(forward_speed - speed_lost, 0.0)
	else:
		var speed := _dynamics.cg_velocity.length()
		if speed > 0.01:
			_dynamics.cg_velocity *= maxf(speed - speed_lost, 0.0) / speed


func damage_amount() -> float:
	return _damage.amount


func is_wrecked() -> bool:
	return _damage.is_totaled()


## Moves this car out of another car, keeps the bumped speed, and sets it turning.
func apply_car_bump(offset: Vector3, new_velocity: Vector3, yaw_kick: float) -> void:
	var planar := Vector3(new_velocity.x, 0.0, new_velocity.z)
	if not GameState.arcade_drive:
		global_position += offset
		_dynamics.cg_velocity = planar
		_dynamics.yaw_rate += yaw_kick
		velocity = planar
		_sync_motion_state()
		return
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var track := _race_track(get_parent())
	if track != null and track.has_method(&"sample_at"):
		var sample: Dictionary = track.sample_at(_path_s)
		var yaw := float(sample.get("yaw", rotation.y))
		forward = Vector3(sin(yaw), 0.0, cos(yaw))
		var right: Vector3 = sample.get("right", Vector3(cos(yaw), 0.0, -sin(yaw)))
		_path_s += offset.dot(forward)
		_lane_x += offset.dot(right)
		_lane_ready = true
		_rail_shove = planar.dot(right)
		_rail_spin += yaw_kick
	global_position += offset
	forward_speed = clampf(planar.dot(forward), 0.0, _max_mps)


func begin_park(slot: float) -> void:
	if _parking:
		return
	_parking = true
	_park_slot = slot
	_park_speed = maxf(forward_speed, 0.0)
	_skids.end_strips()


func _physics_process(delta: float) -> void:
	_damage.tick(delta)
	if _damage.is_totaled():
		_coast_to_a_stop(delta)
		return
	if _parking:
		_park_speed = _RacePark.step(self, _dynamics, delta, _park_speed, _park_slot)
		forward_speed = _park_speed
		_stick_to_road()
		_body_motion.ride_from_motion(delta, _dynamics.cg_velocity, rotation.y)
		_pose_body(delta)
		return
	if GameState.arcade_drive:
		_physics_arcade(delta)
		_ride_rails(delta)
	else:
		_physics_simulation(delta)
		_body_motion.note_velocity(_dynamics.cg_velocity)
	_stick_to_road()
	_pose_body(delta)


## A totaled car rolls straight on until it stops, and sits there smoking.
func _coast_to_a_stop(delta: float) -> void:
	forward_speed = move_toward(forward_speed, 0.0, _TOTALED_BRAKE * delta)
	var nose := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	velocity = nose * forward_speed
	_dynamics.yaw = rotation.y
	_dynamics.yaw_rate = 0.0
	_dynamics.cg_velocity = velocity
	_dynamics.update_steering(delta, 0.0)
	move_and_slide()
	_skids.end_strips()
	_dynamics.sample_surfaces(_race_track(get_parent()), global_transform)
	_body_motion.ride_from_motion(delta, velocity, rotation.y)
	_stick_to_road()
	_pose_body(delta)


## On the arcade rails only the speed and the heading say how hard the body is being thrown.
func _ride_rails(delta: float) -> void:
	var track := _race_track(get_parent())
	_dynamics.sample_surfaces(track, global_transform)
	var turned := wrapf(rotation.y - _last_yaw, -PI, PI) / maxf(delta, 0.0001)
	_last_yaw = rotation.y
	_rail_yaw_rate = lerpf(_rail_yaw_rate, turned, 1.0 - exp(-8.0 * delta))
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	_body_motion.ride_from_motion(delta, forward * forward_speed, rotation.y)


func _pose_body(delta: float) -> void:
	var race := get_parent()
	if race != null and race.has_method(&"is_race_started") and not race.is_race_started():
		return
	_body_motion.capture()
	var steer := _dynamics.steer_angle()
	var steer_input := _dynamics.steer_input()
	if GameState.arcade_drive and not _parking and not _damage.is_totaled():
		steer = atan(_rail_yaw_rate * _dynamics.config.wheelbase_m / maxf(forward_speed, 1.0))
		steer_input = clampf(_rail_yaw_rate / _RAIL_FULL_YAW_RATE, -1.0, 1.0)
	_body_motion.pose(delta, forward_speed, steer, steer_input)


func _physics_simulation(delta: float) -> void:
	if _arcade_active:
		_dynamics.reset_all_motion()
		_dynamics.yaw = rotation.y
		_dynamics.cg_velocity = Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * maxf(forward_speed, 0.0)
		_arcade_active = false
	var race := get_parent()
	var track := _race_track(race)
	_capture_lane(track)
	_project_progress(track)
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		_dynamics.reset_all_motion()
		_hold_still()
		return

	if _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - delta)
	else:
		_auto_shift()

	var steer := 0.0
	var throttle := true
	var brake := false
	if track != null:
		var command := _drive_command(track)
		steer = command.x
		throttle = command.y > 0.5
		brake = command.z > 0.5

	if _escape_obstacle(track):
		_dynamics.reset_motion()
		_dynamics.update_steering(delta, 0.0)
		_hold_still()
		return

	var drive := 0.0
	var brake_input := 0.0
	if throttle and _shift_timer <= 0.0:
		drive = _requested_drive_force()
	elif brake:
		brake_input = 1.0
	_dynamics.sample_surfaces(track, global_transform)
	_dynamics.step(delta, steer, drive, brake_input)
	_hold_tight_lane(track, delta)
	_sync_motion_state()
	_dynamics.pose_body(self, true)
	var before := velocity
	move_and_slide()
	if _scrape_barrier(before, track, delta):
		_skids.end_strips()
	else:
		_skids.record(_dynamics.wheels(), global_transform, track)


func _physics_arcade(delta: float) -> void:
	if not _arcade_active:
		_arcade_gear = 0
		_arcade_shift = 0.0
		_arcade_active = true
	var race := get_parent()
	var track := _race_track(race)
	_capture_lane(track)
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		forward_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
		return
	var corner := _max_mps
	if track != null and track.has_method(&"sample_at"):
		corner = _corner_speed(track, forward_speed, _ArcadeDrive.dry_grip_accel(_arcade_grip, _dynamics.ride_grip()) * ARCADE_CORNER_GRIP_USE)
	var braking := forward_speed > corner
	var pull := 0.0
	if braking:
		forward_speed = move_toward(forward_speed, corner, _ArcadeDrive.BRAKING * delta)
	elif _arcade_shift > 0.0:
		_arcade_shift = maxf(0.0, _arcade_shift - delta)
	else:
		var top := _arcade_gear_top(_arcade_gear)
		if _arcade_gear < ARCADE_RATIOS.size() - 1 and forward_speed >= top * 0.90:
			_arcade_gear += 1
			_arcade_shift = _shift_time
		else:
			pull = _arcade_gear_accel(track)
			forward_speed = minf(forward_speed + pull * _damage.power_left() * delta, maxf(corner, forward_speed))
	forward_speed = minf(forward_speed, _max_mps)
	_mark_arcade_tires(track, braking, pull)
	if track != null and track.has_method(&"sample_at"):
		_path_s += forward_speed * delta
		_lane_x += _rail_shove * delta
		_rail_shove *= exp(-_RAIL_SHOVE_DECAY * delta)
		_rail_wobble += _rail_spin * delta
		_rail_spin *= exp(-_RAIL_SPIN_DECAY * delta)
		_rail_wobble *= exp(-_RAIL_WOBBLE_RETURN * delta)
		var sample: Dictionary = track.sample_at(_path_s)
		var right: Vector3 = sample.get("right", Vector3.RIGHT)
		var center: Vector3 = sample.get("position", global_position)
		var left_ext := float(sample.get("left_ext", 8.0))
		var right_ext := float(sample.get("right_ext", 8.0))
		var left_room := maxf(left_ext - 1.6, 0.0)
		var right_room := maxf(right_ext - 1.6, 0.0)
		var lane := clampf(_lane_x, -left_room, right_room)
		if track.has_method(&"is_tight_road") and track.is_tight_road():
			lane = clampf(_dodging_lane(track, lane, delta), -maxf(left_ext - TIGHT_EDGE_MARGIN_M, 0.0), maxf(right_ext - TIGHT_EDGE_MARGIN_M, 0.0))
		var dest := center + right * lane
		velocity = Vector3.ZERO
		move_and_slide()
		global_position.x = dest.x
		global_position.z = dest.z
		rotation.y = float(sample.get("yaw", 0.0)) + _rail_wobble
		return
	velocity = Vector3(0.0, velocity.y, forward_speed)
	move_and_slide()


## Marks and smoke off the line and under hard braking. On the rails a rival never slides.
func _mark_arcade_tires(track: Node, braking: bool, pull: float) -> void:
	var hard_braking := braking and forward_speed > _ArcadeDrive.BRAKE_MARK_SPEED
	var rear_grip := _ArcadeDrive.dry_grip_accel(_arcade_grip, _dynamics.ride_grip()) * _ARCADE_REAR_GRIP_SHARE
	var rear_long := pull / maxf(rear_grip, 0.1)
	_skids.record_axles(
		_dynamics.wheels(),
		global_transform,
		track,
		forward_speed,
		1.0 if hard_braking else 0.0,
		0.0,
		-1.0 if hard_braking else 0.0,
		rear_long,
		0.0,
		rear_long
	)


func _arcade_gear_top(gear_index: int) -> float:
	var i := clampi(gear_index, 0, ARCADE_RATIOS.size() - 1)
	var top_ratio: float = ARCADE_RATIOS[ARCADE_RATIOS.size() - 1]
	var ratio: float = maxf(ARCADE_RATIOS[i], 0.01)
	return _max_mps * (top_ratio / ratio)


func _arcade_gear_accel(track: Node) -> float:
	var ratio: float = ARCADE_RATIOS[clampi(_arcade_gear, 0, ARCADE_RATIOS.size() - 1)]
	var pull := _ArcadeDrive.gear_acceleration(ratio, _arcade_gear_top(_arcade_gear), forward_speed, _power_hp) * _arcade_driver
	if track == null or not track.has_method(&"sample_at"):
		return pull
	var yaw_now: float = float(track.sample_at(_path_s).get("yaw", 0.0))
	var yaw_on: float = float(track.sample_at(_path_s + _ARCADE_CURVE_STEP_M).get("yaw", yaw_now))
	var curve := absf(wrapf(yaw_on - yaw_now, -PI, PI)) / _ARCADE_CURVE_STEP_M
	var grip := _ArcadeDrive.dry_grip_accel(_arcade_grip, _dynamics.ride_grip())
	return pull * _ArcadeDrive.corner_power(forward_speed * forward_speed * curve / maxf(grip, 0.1))


func _hold_still() -> void:
	_sync_motion_state()
	_dynamics.pose_body(self, false)
	move_and_slide()
	_skids.end_strips()


func _stick_to_road() -> void:
	var track := _race_track(get_parent())
	if track == null or not track.has_method(&"surface_height"):
		rotation.x = 0.0
		return
	var here: float = track.surface_height(global_position)
	global_position.y = _road_base_y + here
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var ahead: float = track.surface_height(global_position + forward * _ROAD_PITCH_SPAN)
	var behind: float = track.surface_height(global_position - forward * _ROAD_PITCH_SPAN)
	rotation.x = -atan2(ahead - behind, _ROAD_PITCH_SPAN * 2.0)
	if track.has_method(&"surface_roll"):
		rotation.z = track.surface_roll(global_position, rotation.y)


func _race_track(race: Node) -> Node:
	if race != null and race.has_method(&"get_race_track"):
		return race.get_race_track()
	return null


func _apply_opponent_look(opp: Dictionary) -> void:
	if _visual == null or not _visual.has_method(&"preview_listing"):
		return
	var path := str(opp.get("car_file", ""))
	if path.is_empty():
		return
	var paint := Color.WHITE
	var stored: Variant = opp.get("color", null)
	if stored is Color:
		paint = stored
	if not bool(_visual.call(&"preview_listing", path, paint)):
		push_warning("Opponent car failed to load: %s" % path)


func _apply_car_spec() -> void:
	var opp := GameState.selected_opponent()
	_dynamics.apply_setup(GameState.opponent_chassis(opp), GameState.opponent_tire_grip(opp))


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
		var center := Vector3(0.0, 0.0, 1.9)
		if _visual != null:
			center = Vector3(_visual.position.x, 0.0, _visual.position.z)
		_dynamics.layout_about(center)


func _sync_motion_state() -> void:
	forward_speed = _dynamics.longitudinal_speed()


func _capture_lane(track: Node) -> void:
	if _lane_ready or track == null or not track.has_method(&"closest_sample"):
		return
	var sample: Dictionary = track.closest_sample(global_transform * _dynamics.cg_local)
	_lane_x = float(sample.get("lateral", 0.0))
	_lane_ready = true


func _project_progress(track: Node) -> void:
	if track == null or not track.has_method(&"closest_sample"):
		return
	var sample: Dictionary = track.closest_sample(global_transform * _dynamics.cg_local)
	_path_s = float(sample.get("s", _path_s))
	_path_yaw = float(sample.get("yaw", _path_yaw))
	_lateral = float(sample.get("lateral", _lateral))


## x is steering input, y is throttle (0 or 1), z is brake (0 or 1).
func _drive_command(track: Node) -> Vector3:
	var planar := Vector2(_dynamics.cg_velocity.x, _dynamics.cg_velocity.z).length()
	var here: Dictionary = track.sample_at(_path_s)
	var left_ext := float(here.get("left_ext", 8.0))
	var right_ext := float(here.get("right_ext", 8.0))
	var lane := clampf(_lane_x, -(left_ext - LANE_EDGE_MARGIN_M), right_ext - LANE_EDGE_MARGIN_M)
	var ahead_yaw := float(track.sample_at(_path_s + planar * STEER_LOOKAHEAD_S).get("yaw", _path_yaw))
	var err := wrapf(ahead_yaw - _dynamics.yaw, -PI, PI)
	var lat_err := _lateral - lane
	var steer := err / STEER_FULL_ERROR_RAD - lat_err * STEER_PER_LANE_M - _dynamics.yaw_rate * STEER_YAW_DAMPING
	var sliding := absf(_dynamics.lateral_speed()) > SLIDE_LATERAL_MPS and forward_speed > 6.0
	if sliding:
		steer = -_dynamics.yaw_rate * STEER_YAW_DAMPING
	if planar < 4.0:
		steer = err / (STEER_FULL_ERROR_RAD * 4.0)
	steer = clampf(steer, -1.0, 1.0)
	var too_fast := planar - _corner_speed(track, planar, _dynamics.grip_accel() * CORNER_GRIP_USE)
	var braking := (too_fast > 1.8 and absf(steer) < 0.3) or too_fast > 8.0
	var throttle := not braking and too_fast < 0.6 and absf(err) < 0.7 and not sliding
	if planar < 4.0 and absf(err) < 1.2:
		throttle = true
		braking = false
	return Vector3(steer, 1.0 if throttle else 0.0, 1.0 if braking else 0.0)


## On a road with walls beside it, the tires' model decides how fast this car goes, but not where.
## Steering by it runs a meter off its lane in a bend, and an 8 m road has no meter to spare.
func _hold_tight_lane(track: Node, delta: float) -> void:
	if track == null or not track.has_method(&"is_tight_road") or not track.is_tight_road():
		return
	var here: Dictionary = track.sample_at(_path_s)
	var left_ext := float(here.get("left_ext", 8.0))
	var right_ext := float(here.get("right_ext", 8.0))
	var left_room := maxf(left_ext - TIGHT_EDGE_MARGIN_M, 0.0)
	var right_room := maxf(right_ext - TIGHT_EDGE_MARGIN_M, 0.0)
	var lane := clampf(_dodging_lane(track, clampf(_lane_x, -left_room, right_room), delta), -left_room, right_room)
	var speed := maxf(_dynamics.longitudinal_speed(), 0.0)
	var yaw := float(here.get("yaw", _dynamics.yaw))
	var across := clampf((lane - _lateral) * TIGHT_CLOSE_RATE, -TIGHT_MAX_MPS, TIGHT_MAX_MPS)
	_dynamics.yaw = yaw + atan2(across, maxf(speed, 3.0))
	_dynamics.cg_velocity = Vector3(sin(yaw), 0.0, cos(yaw)) * speed + Vector3(cos(yaw), 0.0, -sin(yaw)) * across


## The lane to hold this step: the wanted one, eased around whatever is on the road ahead.
func _dodging_lane(track: Node, wanted: float, delta: float) -> float:
	var target: float = track.lane_around(_path_s, wanted, maxf(forward_speed, 0.0) * DODGE_LOOK_S + DODGE_LOOK_M)
	if not _dodge_ready:
		_dodge_lane = wanted
		_dodge_ready = true
	_dodge_lane = move_toward(_dodge_lane, target, DODGE_MPS * delta)
	return _dodge_lane


## Fastest speed the tightest bend in the braking horizon allows.
func _corner_speed(track: Node, planar: float, ay: float) -> float:
	var horizon := clampf(planar * 2.8, 36.0, 110.0)
	if track.has_method(&"gravel_limit"):
		var gravel: float = track.gravel_limit(_path_s, horizon)
		if gravel < _max_mps and not is_inf(gravel):
			return gravel
	var step := 6.0
	var count := maxi(int(horizon / step), 1)
	var prev: float = float(track.sample_at(_path_s).get("yaw", _dynamics.yaw))
	var worst := 0.0
	for i in count:
		var yaw: float = float(track.sample_at(_path_s + step * float(i + 1)).get("yaw", prev))
		worst = maxf(worst, absf(wrapf(yaw - prev, -PI, PI)) / step)
		prev = yaw
	if worst < 0.0015:
		return _max_mps
	return minf(_max_mps, sqrt(ay / worst))


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
	return _max_mps * (top_ratio / ratio)


func _requested_drive_force() -> float:
	var ratios := _ratios()
	var ratio := float(ratios[clampi(_gear, 0, ratios.size() - 1)])
	var force := _dynamics.drive_force(ratio, _gear_top_mps(_gear), forward_speed, _power_hp)
	return force * _drive_scale * _damage.power_left()


func _auto_shift() -> void:
	if _shift_timer > 0.0:
		return
	var top := _gear_top_mps(_gear)
	if _gear < _ratios().size() - 1 and forward_speed >= top * 0.90:
		_gear += 1
		_shift_timer = _shift_time
		return
	if _gear <= 0:
		return
	var prev_top := _gear_top_mps(_gear - 1)
	if forward_speed < prev_top * 0.45:
		_gear -= 1
		_shift_timer = _shift_time


func _escape_obstacle(track: Node) -> bool:
	if track == null or not track.has_method(&"obstacle_escape"):
		return false
	var safe: Vector3 = track.obstacle_escape(global_position)
	if safe.is_equal_approx(global_position):
		return false
	global_position = safe
	return true


## Applies touching a barrier to the tires' model. True when one was touched.
func _scrape_barrier(before: Vector3, track: Node, delta: float) -> bool:
	var hit := _WallScrape.resolve(self, before, delta)
	if hit.is_empty():
		return false
	take_hit(_damage.barrier_hit(float(hit["into"]) * (1.0 + _WallScrape.BOUNCE)))
	var after: Vector3 = hit["velocity"]
	_dynamics.cg_velocity = after
	velocity = after
	_dynamics.yaw_rate = _WallScrape.turn_rate(track, self, _dynamics.yaw)
	_sync_motion_state()
	return true
