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
const _AirTime := preload("res://scripts/air_time.gd")

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
## How far ahead, in seconds of travel, the driver reads the road heading and how it bends.
const STEER_LOOKAHEAD_S := 0.4
## Steering against turning faster or slower than the road does, per rad/s.
const STEER_YAW_DAMPING := 0.55
## Body slip speed where the driver stops steering at the line and catches the slide.
const SLIDE_LATERAL_MPS := 4.0
## Pointing this far off the road at a crawl, after a spin, the driver turns round on full lock
## with this much throttle, and keeps turning the same way until it is pointing up the road.
const TURN_ROUND_ERROR_RAD := 1.2
const TURN_ROUND_THROTTLE := 0.5
const LANE_EDGE_MARGIN_M := 1.8
## How a rival moves around something on the road: how early it looks, and how fast it goes across.
const DODGE_LOOK_S := 2.2
const DODGE_LOOK_M := 25.0
const DODGE_MPS := 8.5
## On a tight road: what share of the gap to its lane it closes in a second, and how fast at most.
const TIGHT_CLOSE_RATE := 4.0
const TIGHT_MAX_MPS := 5.0
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
## Share of a landing's impact, in m/s, that comes off the speed. The same as the player's car.
const LANDING_SPEED_LOSS := 0.15
## On the arcade rails after a jump: what share of the way back to its lane the car closes in a
## second, and how fast at most it goes across.
const _RAIL_REJOIN_RATE := 1.2
const _RAIL_REJOIN_MAX_MPS := 5.0

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
var _traffic_brake: bool = false
var _traffic_speed_cap: float = INF
var _lane_ready: bool = false
## While turning round after a spin: which way, 1 or -1. 0 when not turning round.
var _turn_round: float = 0.0
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
## Off a jump. In the air the car leaves its line and flies on the way it took off, and once down
## it drives back to the line from wherever it landed.
var _air: _AirTime = _AirTime.new()
## Flat velocity in the air, in m/s: the way the car was going when it left the road.
var _flight_velocity: Vector3 = Vector3.ZERO
## On the arcade rails: how far, in meters, the car landed from its lane. Closes as it drives back.
var _rail_rejoin: float = 0.0


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
	if _air.airborne:
		_physics_flight()
	elif GameState.arcade_drive:
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


## In the air neither the rails nor the tires move the car, and the springs sit as they were.
## It flies on flat and straight until `_stick_to_road` brings it down.
func _physics_flight() -> void:
	velocity = _flight_velocity
	move_and_slide()
	_skids.end_strips()
	_body_motion.note_velocity(_flight_velocity)
	var track := _race_track(get_parent())
	if track != null and track.has_method(&"closest_sample"):
		_path_s = float(track.closest_sample(global_position).get("s", _path_s))


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
	var throttle := 1.0
	var brake := false
	if track != null:
		var command := _drive_command(track, delta)
		steer = command.x
		throttle = command.y
		brake = command.z > 0.5

	if _escape_obstacle(track):
		_dynamics.reset_motion()
		_dynamics.update_steering(delta, 0.0)
		_hold_still()
		return

	var drive := 0.0
	var brake_input := 0.0
	if throttle > 0.0 and _shift_timer <= 0.0:
		drive = _requested_drive_force() * throttle
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
	if not is_inf(_traffic_speed_cap):
		corner = minf(corner, _traffic_speed_cap)
	if _traffic_brake:
		corner = minf(corner, 6.0)
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
		var across := clampf(-_rail_rejoin * _RAIL_REJOIN_RATE, -_RAIL_REJOIN_MAX_MPS, _RAIL_REJOIN_MAX_MPS)
		_rail_rejoin += across * delta
		var dest := center + right * (lane + _rail_rejoin)
		velocity = Vector3.ZERO
		move_and_slide()
		global_position.x = dest.x
		global_position.z = dest.z
		rotation.y = float(sample.get("yaw", 0.0)) + _rail_wobble + atan2(across, maxf(forward_speed, 3.0))
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
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	if track.has_method(&"has_jumps") and track.has_jumps():
		var was_flying := _air.airborne
		var moving := _flight_velocity if was_flying else _ground_velocity(forward)
		var speed := moving.length()
		var travel := moving / speed if speed > 0.1 else forward
		var delta := get_physics_process_delta_time()
		_air.step(track, global_position, travel, speed, delta)
		here = _air.height
		if _air.airborne:
			if not was_flying:
				_flight_velocity = moving
			global_position.y = _road_base_y + here
			rotation.x = _air.flight_pitch(rotation.x, speed, delta)
			return
		if was_flying:
			_rejoin_line(track)
	global_position.y = _road_base_y + here
	var ahead: float = track.surface_height(global_position + forward * _ROAD_PITCH_SPAN)
	var behind: float = track.surface_height(global_position - forward * _ROAD_PITCH_SPAN)
	rotation.x = -atan2(ahead - behind, _ROAD_PITCH_SPAN * 2.0)
	if track.has_method(&"surface_roll"):
		rotation.z = track.surface_roll(global_position, rotation.y)


## Flat velocity on the road, in m/s. On the rails the car only goes where its nose points.
func _ground_velocity(forward: Vector3) -> Vector3:
	if GameState.arcade_drive or _parking or _damage.is_totaled():
		return forward * maxf(forward_speed, 0.0)
	return Vector3(_dynamics.cg_velocity.x, 0.0, _dynamics.cg_velocity.z)


## Down off a jump: the landing's damage and lost speed, and the line picked up again from the
## closest point on it. The rails ease the car back over to its lane, and the tires steer it there.
func _rejoin_line(track: Node) -> void:
	take_hit(_AirTime.landing_harm(_air.impact))
	var speed := _flight_velocity.length()
	var kept := maxf(speed - _air.impact * LANDING_SPEED_LOSS, 0.0) / maxf(speed, 0.1)
	forward_speed *= kept
	_dynamics.cg_velocity = _flight_velocity * kept
	_dynamics.yaw = rotation.y
	if not track.has_method(&"closest_sample"):
		return
	var sample: Dictionary = track.closest_sample(global_position)
	_path_s = float(sample.get("s", _path_s))
	if GameState.arcade_drive and not _parking:
		var left_room := maxf(float(sample.get("left_ext", 8.0)) - 1.6, 0.0)
		var right_room := maxf(float(sample.get("right_ext", 8.0)) - 1.6, 0.0)
		_rail_rejoin = float(sample.get("lateral", 0.0)) - clampf(_lane_x, -left_room, right_room)
		_rail_wobble = wrapf(rotation.y - float(sample.get("yaw", rotation.y)), -PI, PI)


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


## x is steering input, y is throttle (0 to 1), z is brake (0 or 1). The steering sets the wheel
## for how the road bends ahead, so the car turns in with it rather than falling behind and
## catching up, and corrects from there for heading, lane, and turning too fast or too slow.
func _drive_command(track: Node, delta: float = 0.016) -> Vector3:
	var planar := Vector2(_dynamics.cg_velocity.x, _dynamics.cg_velocity.z).length()
	var here: Dictionary = track.sample_at(_path_s)
	var left_ext := float(here.get("left_ext", 8.0))
	var right_ext := float(here.get("right_ext", 8.0))
	var left_room := maxf(left_ext - LANE_EDGE_MARGIN_M, 0.0)
	var right_room := maxf(right_ext - LANE_EDGE_MARGIN_M, 0.0)
	var target_lane := _dodging_lane(track, clampf(_lane_x, -left_room, right_room), delta)
	var lane := clampf(target_lane, -left_room, right_room)
	var ahead_yaw := float(track.sample_at(_path_s + planar * STEER_LOOKAHEAD_S).get("yaw", _path_yaw))
	var err := wrapf(ahead_yaw - _dynamics.yaw, -PI, PI)
	var lat_err := _lateral - lane
	var turn_s := _path_s + planar * STEER_LOOKAHEAD_S
	var curve := wrapf(float(track.sample_at(turn_s + 6.0).get("yaw", ahead_yaw)) - ahead_yaw, -PI, PI) / 6.0
	var feed := _dynamics.steer_input_for(atan(curve * _dynamics.config.wheelbase_m))
	var road_yaw_rate := curve * planar
	var steer := feed + err / STEER_FULL_ERROR_RAD - lat_err * STEER_PER_LANE_M - (_dynamics.yaw_rate - road_yaw_rate) * STEER_YAW_DAMPING
	var sliding := absf(_dynamics.lateral_speed()) > SLIDE_LATERAL_MPS and forward_speed > 6.0
	if sliding:
		steer = -_dynamics.yaw_rate * STEER_YAW_DAMPING
	if planar < 4.0:
		steer = err / (STEER_FULL_ERROR_RAD * 4.0)
	if planar < 4.0 and absf(err) >= TURN_ROUND_ERROR_RAD:
		if _turn_round == 0.0:
			_turn_round = signf(err) if err != 0.0 else 1.0
		return Vector3(_turn_round, TURN_ROUND_THROTTLE, 0.0)
	if absf(err) < TURN_ROUND_ERROR_RAD:
		_turn_round = 0.0
	steer = clampf(steer, -1.0, 1.0)
	var corner_lim := _corner_speed(track, planar, _dynamics.grip_accel() * CORNER_GRIP_USE)
	if not is_inf(_traffic_speed_cap):
		corner_lim = minf(corner_lim, _traffic_speed_cap)
	var too_fast := planar - corner_lim
	var braking := (too_fast > 1.8 and absf(steer) < 0.3) or too_fast > 8.0 or _traffic_brake
	var throttle := not braking and too_fast < 0.6 and absf(err) < 0.7 and not sliding
	if planar < 4.0 and absf(err) < 1.2 and not _traffic_brake:
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
	var target_lane := _dodge_lane if _dodge_ready else _dodging_lane(track, clampf(_lane_x, -left_room, right_room), delta)
	var lane := clampf(target_lane, -left_room, right_room)
	var speed := maxf(_dynamics.longitudinal_speed(), 0.0)
	var yaw := float(here.get("yaw", _dynamics.yaw))
	var across := clampf((lane - _lateral) * TIGHT_CLOSE_RATE, -TIGHT_MAX_MPS, TIGHT_MAX_MPS)
	_dynamics.yaw = yaw + atan2(across, maxf(speed, 3.0))
	_dynamics.cg_velocity = Vector3(sin(yaw), 0.0, cos(yaw)) * speed + Vector3(cos(yaw), 0.0, -sin(yaw)) * across


## The lane to hold this step: the wanted one, eased around whatever is on the road ahead.
func _dodging_lane(track: Node, wanted: float, delta: float) -> float:
	var traffic_wanted := _scan_traffic(track, wanted)
	var target: float = track.lane_around(_path_s, traffic_wanted, maxf(forward_speed, 0.0) * DODGE_LOOK_S + DODGE_LOOK_M)
	if not _dodge_ready:
		_dodge_lane = target
		_dodge_ready = true
	_dodge_lane = move_toward(_dodge_lane, target, DODGE_MPS * delta)
	return _dodge_lane


## Scans ahead for active traffic cars and selects the safest lane, setting speed caps and braking when blocked.
func _scan_traffic(track: Node, wanted_lane: float) -> float:
	_traffic_brake = false
	_traffic_speed_cap = INF

	if not is_inside_tree() or track == null:
		return wanted_lane

	var traffic_cars := get_tree().get_nodes_in_group(&"traffic_cars")
	if traffic_cars.is_empty():
		return wanted_lane

	var speed := maxf(forward_speed, 10.0)
	var lookahead := maxf(speed * 3.2 + 35.0, 120.0)

	var relevant_cars: Array[Dictionary] = []
	for node: Node in traffic_cars:
		if node == null or not is_instance_valid(node):
			continue
		var car_s: float = float(node.get("s"))
		var gap := car_s - _path_s
		if gap > -3.0 and gap < lookahead:
			relevant_cars.append({
				"gap": gap,
				"lat": float(node.get("lateral")),
				"oncoming": bool(node.get("is_oncoming")),
				"speed": float(node.get("speed_mps")),
			})

	if relevant_cars.is_empty():
		return wanted_lane

	relevant_cars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["gap"]) < float(b["gap"]))

	# Check player position to avoid running into player while dodging
	var player_s := -INF
	var player_lat := 0.0
	var race := get_parent()
	if race != null:
		var p_car := race.get_node_or_null("PlayerCar") as Node3D
		if p_car != null and track.has_method(&"closest_sample"):
			var p_samp: Dictionary = track.closest_sample(p_car.global_position)
			player_s = float(p_samp.get("s", -INF))
			player_lat = float(p_samp.get("lateral", 0.0))

	# Candidate lanes: on 8m road, -2.0 is right lane, +2.0 is left/oncoming lane, 0.0 is center
	var candidates: Array[float] = [-2.0, 2.0, 0.0]
	if not candidates.has(wanted_lane):
		candidates.append(wanted_lane)

	var best_lane := wanted_lane
	var lowest_penalty := INF

	for c: float in candidates:
		var penalty := 0.0
		# Baseline preference: prefer right lane (-2.0), as oncoming traffic travels on +2.0
		if absf(c - (-2.0)) < 0.5:
			penalty += 0.0
		elif absf(c - 2.0) < 0.5:
			penalty += 20.0
		else:
			penalty += 45.0

		# Check static obstacles (boulders / walls / narrow bridges)
		if track.has_method(&"lane_around"):
			var static_clear: float = track.lane_around(_path_s, c, 35.0)
			if absf(static_clear - c) > 0.8:
				penalty += 4000.0

		# Check player car
		if absf(player_s - _path_s) < 12.0 and absf(c - player_lat) < 2.3:
			penalty += 1500.0

		# Check traffic cars
		for tcar: Dictionary in relevant_cars:
			var t_gap := float(tcar["gap"])
			var t_lat := float(tcar["lat"])
			var t_oncoming := bool(tcar["oncoming"])
			var lat_dist := absf(c - t_lat)
			if lat_dist < 2.4:
				if t_oncoming:
					penalty += 5000.0 / maxf(t_gap * 0.04, 0.4)
				else:
					penalty += 800.0 / maxf(t_gap * 0.08, 0.8)

		if penalty < lowest_penalty:
			lowest_penalty = penalty
			best_lane = c

	# Speed and braking evaluation
	for tcar: Dictionary in relevant_cars:
		var t_gap := float(tcar["gap"])
		var t_lat := float(tcar["lat"])
		var t_oncoming := bool(tcar["oncoming"])
		var t_speed := float(tcar["speed"])

		var our_lat := _lateral
		var lat_overlap := absf(our_lat - t_lat) < 2.2
		var target_overlap := absf(best_lane - t_lat) < 2.2

		if t_oncoming:
			if (lat_overlap or target_overlap) and t_gap < 75.0:
				var lat_dist := absf(our_lat - t_lat)
				if lat_dist < 2.1:
					_traffic_brake = true
					_traffic_speed_cap = minf(_traffic_speed_cap, maxf(t_gap * 0.6, 5.0))
		else:
			# Same direction car ahead
			if best_lane == t_lat or (lat_overlap and t_gap < 40.0):
				_traffic_speed_cap = minf(_traffic_speed_cap, t_speed)
				if forward_speed > t_speed:
					_traffic_brake = true
				if t_gap < 16.0:
					_traffic_brake = true
					_traffic_speed_cap = minf(_traffic_speed_cap, maxf(t_speed - 3.0, 3.0))

	return best_lane


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
