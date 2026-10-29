extends Node

## Planar vehicle. Steering sets the front wheel angle. Tires make forces.
## Forces make yaw torque. Torque changes yaw rate, and yaw rate turns the car.
## Nothing steers the body toward a target heading.
##
## Each wheel is a raycast spring with a damper. That spring force is the tire
## normal load, so weight transfer arrives as the body squats instead of as an
## instant split of the static weight. Grip peaks at a small slip and then
## falls to a sliding value. The steering rack chases the input over time, and
## it slows its return while the car is sliding.
##
## Asphalt and grass, four wheels, rear-wheel drive. Grass is a strong
## deterrent: less grip, less drive, and a speed-dependent drag.
## The cars stay CharacterBody3D nodes. These rays read the ground under that
## body. Step runs from the car's `_physics_process`.

@export_group("Suspension")
## Off uses the instant, filtered load-transfer formula on a flat body.
@export var use_spring_suspension: bool = true
## Newtons per meter of spring compression at each wheel.
@export var spring_stiffness: float = 52000.0
## Newtons per meter per second. Resists bump and rebound.
@export var damper_coefficient: float = 7000.0
@export_group("Tires")
## Off uses the saturating slip curve, where force never falls past the limit.
@export var use_peak_slip_curve: bool = true
## Where grip peaks. 0.08 is 8% longitudinal slip and an 8 degree slip angle.
@export_range(0.06, 0.10, 0.005) var peak_slip_threshold: float = 0.08
## Grip left once the tire is well past the peak, as a fraction of peak grip.
@export_range(0.45, 0.95, 0.01) var sliding_grip_factor: float = 0.76
@export_group("Steering")
## Off uses a fixed rack speed with no speed or slide dependence.
@export var use_dynamic_steering: bool = true
## How fast the front wheels chase the steering input, in radians per second.
@export_range(0.4, 8.0, 0.1) var steering_damping_speed: float = 2.0
@export_group("Brakes")
## Off chases the brake with the same fast response as the throttle.
@export var use_brake_ramp: bool = true
## Seconds a held brake key takes to reach full brake. Release stays fast.
@export_range(0.1, 1.5, 0.05) var brake_build_time: float = 0.45

class SurfaceProfile:
	var grip_multiplier: float = 1.0
	var rolling_resistance: float = 0.015
	var drive_multiplier: float = 1.0
	## Extra scale on the steered wheel angle. Grip already cuts cornering force.
	var steer_multiplier: float = 1.0
	## Per wheel. Force magnitude is this times speed squared, opposing the contact velocity.
	var speed_resistance: float = 0.0


class Config:
	var mass_kg: float = 1360.0
	var gravity: float = 9.81
	var wheelbase_m: float = 2.59
	var track_width_m: float = 1.55
	## Height of the mass center above the tire contact plane. This is the lever
	## for longitudinal and lateral load transfer.
	var cg_height_m: float = 0.48
	## Fraction of the wheelbase from the mass center forward to the front axle.
	## Below 0.5 puts more static weight on the front axle.
	var front_axle_fraction: float = 0.46
	## 0 uses mass * cg_to_front * cg_to_rear once the wheels are placed.
	var yaw_inertia_override_kgm2: float = 0.0

	## Low-speed lock. At speed the rack stops at the angle for steer_full_lateral_accel.
	var max_steer_rad: float = 0.52
	## Steady lateral acceleration a full steering input asks for, in m/s².
	## The road-wheel angle is atan(this * wheelbase / speed²), never past max_steer_rad.
	var steer_full_lateral_accel: float = 9.0
	## How fast the steering input is chased, in 1/seconds.
	var steer_input_response: float = 8.0
	## 1 is linear. Higher values keep a short press near center; holding still reaches full lock.
	var steer_input_curve: float = 1.8
	## Rack speed when dynamic steering is off.
	var steer_rate_rad_s: float = 2.4
	## Saturating curve, used when the peak slip curve is off. Lateral slip
	## where a pure cornering tire is entering saturation. Force there is about
	## 80% of the grip limit, and further slip adds very little.
	var slip_angle_full_grip_rad: float = 0.11
	## Higher values stay linear longer, then flatten. 2 is a gentle circle.
	var slip_curve_order: float = 3.0
	## How quickly normal load follows acceleration when spring suspension is off.
	var load_transfer_response_s: float = 0.06
	## Friction coefficient at grip_reference_rating. Force limit is grip * normal load.
	var grip_mu: float = 1.05
	var grip_reference_rating: float = 3.0
	var grip_mu_per_rating: float = 0.12
	## Added to forward speed in the slip angle so a stopped wheel does not
	## treat a tiny lateral velocity as a right angle.
	var slip_speed_regularization_mps: float = 1.5
	## Smooths the sign of brake and rolling forces around zero speed.
	var longitudinal_smoothing_mps: float = 0.4

	## Propulsion force at reference_gear_ratio, before the tire limit.
	## The player scales this by the current gear and horsepower.
	var drive_force_n: float = 7800.0
	var reference_gear_ratio: float = 2.80
	var reference_power_hp: float = 280.0
	## Total brake request shared across all four wheels, before the tire limit.
	## Above the car's total grip, so a hard stop can use up the friction circle.
	var brake_force_n: float = 16000.0
	## Share of brake_force_n applied by the front axle.
	var brake_front_fraction: float = 0.62
	## How fast the throttle and brake requests are chased, in 1/seconds.
	var throttle_response: float = 10.0
	## Width of the asphalt-to-grass blend at the road edge.
	var edge_blend_m: float = 2.2
	var air_density: float = 1.225
	## Cd * frontal area. Drag force is 0.5 * air_density * drag_area_m2 * speed^2.
	var drag_area_m2: float = 0.20

	var debug_force_scale: float = 0.0003
	var debug_velocity_scale: float = 0.12

	var asphalt := SurfaceProfile.new()
	var grass := SurfaceProfile.new()


class Wheel:
	var local_position: Vector3 = Vector3.ZERO
	var offset: Vector3 = Vector3.ZERO
	var steer_angle: float = 0.0
	var driven: bool = false
	var front: bool = false
	var grip: float = 1.05
	var static_load: float = 0.0
	var normal_load: float = 0.0
	var forward_velocity: float = 0.0
	var lateral_velocity: float = 0.0
	var slip_angle: float = 0.0
	## Signed longitudinal slip divided by the peak-slip threshold.
	## 1 is the grip peak. Past 1 the tire is sliding. There is no wheel spin model.
	var long_slip: float = 0.0
	var long_force: float = 0.0
	var lat_force: float = 0.0
	## Magnitude of the tire force divided by grip * normal load.
	var grip_utilization: float = 0.0
	var force_body: Vector3 = Vector3.ZERO
	## 0 is asphalt, 1 is fully on grass.
	var surface_blend: float = 0.0
	var surface_name: String = "asphalt"
	## True when `long_slip` is on the peak curve, where 1 is the grip peak.
	## False when it is demand over the grip limit.
	var peak_curve: bool = false
	## Spring travel. `ride_drop` is the ray length at the settled ride height.
	## 0 means it has never been captured for this wheel layout.
	var ride_drop: float = 0.0
	var ride_recapture: bool = true
	var rest_length: float = 0.0
	var compression: float = 0.0
	var compression_speed: float = 0.0
	var suspension_force: float = 0.0
	var grounded: bool = false
	var suspension_ready: bool = false


var config := Config.new()
var cg_local: Vector3 = Vector3.ZERO
var cg_velocity: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var yaw_rate: float = 0.0
var yaw_inertia: float = 2000.0

var _wheels: Array[Wheel] = []
var _steer_input: float = 0.0
var _steer_angle: float = 0.0
var _tire_grip: float = 1.05
var _long_accel: float = 0.0
var _lat_accel: float = 0.0
var _wheelbase: float = 2.59
var _front_track: float = 1.55
var _rear_track: float = 1.55
var _static_front_axle: float = 0.0
var _static_rear_axle: float = 0.0
var _drive_filtered: float = 0.0
var _brake_filtered: float = 0.0
var _heave: float = 0.0
var _heave_vel: float = 0.0
var _pitch: float = 0.0
var _pitch_vel: float = 0.0
var _roll: float = 0.0
var _roll_vel: float = 0.0
var _pitch_inertia: float = 2500.0
var _roll_inertia: float = 600.0

## Flat road used when a wheel ray misses. The road mesh has no collider.
const _GROUND_Y := 0.0
const _WORLD_MASK := 1
const _RAY_LENGTH_M := 2.5
## Hub height above the road for the race spawn, used when the first
## ride-height sample is implausible.
const _DEFAULT_RIDE_DROP_M := 0.71
const _MIN_RIDE_DROP_M := 0.1
const _MAX_RIDE_DROP_M := 1.2
## A recapture further than this from the last good ride height is ignored.
const _RIDE_RECAPTURE_TOLERANCE_M := 0.08
const _MAX_TRAVEL_M := 0.22
const _BUMP_STIFFNESS := 6.0
const _LOAD_CAP := 4.0
const _HEAVE_LIMIT_M := 0.18
const _LEAN_LIMIT_RAD := 0.12
## How fast normalized longitudinal slip chases the force the driver asked for.
const _SLIP_RESPONSE := 9.0
## Return rate while a slide still needs the current steering angle.
const _COUNTERSTEER_RETURN := 0.4
const _SLIDE_YAW_RATE := 0.4
const _SLIDE_LATERAL_MPS := 2.5


func _init() -> void:
	var grass := config.grass
	## Weaker than asphalt, still enough lateral force to steer back to the road.
	grass.grip_multiplier = 0.62
	grass.rolling_resistance = 0.04
	grass.drive_multiplier = 0.30
	grass.steer_multiplier = 0.90
	grass.speed_resistance = 1.0


func apply_setup(chassis: Dictionary, grip_rating: float) -> void:
	if not chassis.is_empty():
		config.mass_kg = float(chassis.get("mass", config.mass_kg))
		config.wheelbase_m = float(chassis.get("wheelbase", config.wheelbase_m))
		config.cg_height_m = float(chassis.get("cg_height", config.cg_height_m))
		config.front_axle_fraction = float(chassis.get("front_axle_fraction", config.front_axle_fraction))
		var steer_deg := float(chassis.get("max_steer_deg", rad_to_deg(config.max_steer_rad)))
		config.max_steer_rad = deg_to_rad(steer_deg)
	var rating := grip_rating - config.grip_reference_rating
	_tire_grip = maxf(config.grip_mu + rating * config.grip_mu_per_rating, 0.2)
	_apply_grip_to_wheels()
	if _wheels.size() == 4:
		_distribute_weight()


func set_wheel_positions(local_positions: Array) -> void:
	if local_positions.size() != 4:
		return
	var pts: Array[Vector3] = []
	for point in local_positions:
		pts.append(point as Vector3)
	var front_z := (pts[0].z + pts[1].z) * 0.5
	var rear_z := (pts[2].z + pts[3].z) * 0.5
	var span := front_z - rear_z
	if absf(span) < 0.2:
		span = config.wheelbase_m if span >= 0.0 else -config.wheelbase_m
	var cg_x := 0.0
	for point in pts:
		cg_x += point.x
	cg_x /= float(pts.size())
	var cg_z := front_z - config.front_axle_fraction * span
	cg_local = Vector3(cg_x, config.cg_height_m, cg_z)
	_wheels.clear()
	for i in pts.size():
		var wheel := Wheel.new()
		wheel.local_position = pts[i]
		wheel.offset = Vector3(pts[i].x - cg_local.x, 0.0, pts[i].z - cg_local.z)
		wheel.front = i < 2
		wheel.driven = i >= 2
		wheel.grip = _tire_grip
		_wheels.append(wheel)
	_distribute_weight()
	_update_inertia()


func layout_about(body_center: Vector3) -> void:
	var reach := config.wheelbase_m * config.front_axle_fraction
	var tail := config.wheelbase_m - reach
	var half := config.track_width_m * 0.5
	cg_local = Vector3(body_center.x, config.cg_height_m, body_center.z)
	var pts: Array[Vector3] = [
		cg_local + Vector3(-half, 0.0, reach),
		cg_local + Vector3(half, 0.0, reach),
		cg_local + Vector3(-half, 0.0, -tail),
		cg_local + Vector3(half, 0.0, -tail),
	]
	set_wheel_positions(pts)


func wheels() -> Array[Wheel]:
	return _wheels


func steer_angle() -> float:
	return _steer_angle


## Peak acceleration the asphalt tires allow on a flat road, in m/s².
func grip_accel() -> float:
	return _tire_grip * config.asphalt.grip_multiplier * config.gravity


func longitudinal_speed() -> float:
	return (_basis().inverse() * cg_velocity).z


func lateral_speed() -> float:
	return (_basis().inverse() * cg_velocity).x


func body_velocity() -> Vector3:
	return _basis().inverse() * cg_velocity


func longitudinal_accel() -> float:
	return _long_accel


func lateral_accel() -> float:
	return _lat_accel


func reset_motion() -> void:
	cg_velocity = Vector3.ZERO
	yaw_rate = 0.0
	_long_accel = 0.0
	_lat_accel = 0.0
	_drive_filtered = 0.0
	_brake_filtered = 0.0
	_heave = 0.0
	_heave_vel = 0.0
	_pitch = 0.0
	_pitch_vel = 0.0
	_roll = 0.0
	_roll_vel = 0.0
	for wheel in _wheels:
		wheel.long_slip = 0.0
		wheel.compression_speed = 0.0
		wheel.suspension_ready = false
		wheel.ride_recapture = true
		wheel.suspension_force = wheel.static_load
		wheel.normal_load = wheel.static_load


func reset_all_motion() -> void:
	reset_motion()
	_steer_input = 0.0
	_steer_angle = 0.0
	for wheel in _wheels:
		wheel.steer_angle = 0.0
		wheel.force_body = Vector3.ZERO
		wheel.slip_angle = 0.0
		wheel.long_force = 0.0
		wheel.lat_force = 0.0
		wheel.grip_utilization = 0.0
		wheel.forward_velocity = 0.0
		wheel.lateral_velocity = 0.0


func update_steering(dt: float, steer_input: float) -> void:
	_apply_steering(dt, steer_input)


## 0 on the asphalt side of the road edge, 1 once `edge_blend_m` into the grass.
func grass_amount(lateral: float, left_extent: float, right_extent: float) -> float:
	var outside := 0.0
	if lateral < -left_extent:
		outside = -left_extent - lateral
	elif lateral > right_extent:
		outside = lateral - right_extent
	var edge := maxf(config.edge_blend_m, 0.05)
	return smoothstep(0.0, edge, outside)


## Samples the road under each wheel. With no track every wheel is on asphalt.
func sample_surfaces(track: Object, body: Transform3D) -> void:
	var blends: Array[float] = []
	for wheel in _wheels:
		var amount := 0.0
		if track != null and track.has_method(&"closest_sample"):
			var sample: Dictionary = track.closest_sample(body * wheel.local_position)
			amount = grass_amount(
				float(sample.get("lateral", 0.0)),
				float(sample.get("left_ext", 0.0)),
				float(sample.get("right_ext", 0.0))
			)
		blends.append(amount)
	set_surface_blends(blends)


## Propulsion request for one gear. Force falls toward the top of the gear and
## ends a little past it. The tires still decide how much of it reaches the road.
func drive_force(gear_ratio: float, gear_top_mps: float, speed: float, power_hp: float) -> float:
	var headroom := 1.0
	if gear_top_mps > 0.05:
		var progress := maxf(speed, 0.0) / gear_top_mps
		if progress >= 1.12:
			return 0.0
		if progress >= 1.0:
			headroom = 0.14
		else:
			headroom = 1.0 - progress * progress
	var power_scale := power_hp / maxf(config.reference_power_hp, 1.0)
	var ratio_scale := gear_ratio / maxf(config.reference_gear_ratio, 0.01)
	return config.drive_force_n * ratio_scale * power_scale * headroom


## Turns the body to the integrated heading about the mass center, then hands
## the mass-center velocity to the character body.
func pose_body(body: CharacterBody3D, moving: bool) -> void:
	var cg_world := body.global_transform * cg_local
	body.rotation.y = yaw
	var cg_now := body.global_transform * cg_local
	body.global_position += cg_world - cg_now
	body.velocity = cg_velocity if moving else Vector3.ZERO


func set_surface_blends(blends: Array) -> void:
	for i in _wheels.size():
		var blend := 0.0
		if i < blends.size():
			blend = clampf(float(blends[i]), 0.0, 1.0)
		var wheel := _wheels[i]
		wheel.surface_blend = blend
		wheel.surface_name = "grass" if blend > 0.5 else "asphalt"


## One fixed physics step. drive_force_n is the total rear propulsion request.
## brake_input is 0..1. Neither is applied by rewriting velocity.
func step(dt: float, steer_input: float, drive_force_n: float, brake_input: float) -> void:
	if dt <= 0.0 or _wheels.is_empty() or config.mass_kg <= 0.0 or yaw_inertia <= 0.0:
		return
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var slices := 1
	if dt > tick * 1.5:
		slices = clampi(int(ceil(dt / tick)), 1, 4)
	var slice := dt / float(slices)
	var drive_target := maxf(drive_force_n, 0.0)
	var brake_target := clampf(brake_input, 0.0, 1.0)
	for _i in slices:
		_chase_pedals(slice, drive_target, brake_target)
		_integrate(slice, steer_input, _drive_filtered, _brake_filtered)


func _integrate(dt: float, steer_input: float, drive_force_n: float, brake_input: float) -> void:
	if use_spring_suspension:
		_update_suspension(dt)
	_apply_steering(dt, steer_input)
	var basis := _basis()
	var drive_each := 0.0
	var driven := 0
	for wheel in _wheels:
		if wheel.driven:
			driven += 1
	if driven > 0:
		drive_each = maxf(drive_force_n, 0.0) / float(driven)

	var force_body := Vector3.ZERO
	var torque := 0.0
	for wheel in _wheels:
		var tire := _tire_force(wheel, basis, drive_each, brake_input, dt)
		force_body += tire
		# Yaw component of r × F. Positive yaw swings the nose toward body +X.
		torque += wheel.offset.z * tire.x - wheel.offset.x * tire.z
	force_body += _aero_force_body(basis)

	cg_velocity += basis * force_body * (dt / config.mass_kg)
	cg_velocity.y = 0.0
	yaw_rate += torque / yaw_inertia * dt
	yaw = wrapf(yaw + yaw_rate * dt, -PI, PI)
	_long_accel = force_body.z / config.mass_kg
	_lat_accel = force_body.x / config.mass_kg
	if use_spring_suspension:
		_integrate_suspension(dt)
	else:
		_update_load_transfer(dt)


func _apply_steering(dt: float, steer_input: float) -> void:
	var target_input := clampf(steer_input, -1.0, 1.0)
	var blend := 1.0 - exp(-config.steer_input_response * dt)
	_steer_input = lerpf(_steer_input, target_input, blend)
	var target_angle := _shaped_steer(_steer_input) * _steer_angle_limit()
	var rate := _steering_rate(target_angle)
	_steer_angle = move_toward(_steer_angle, target_angle, rate * dt)
	var front_blend := 0.0
	var front_count := 0
	for wheel in _wheels:
		if wheel.front:
			front_blend += wheel.surface_blend
			front_count += 1
	if front_count > 0:
		front_blend /= float(front_count)
	var steer_scale := _blended(front_blend, config.asphalt.steer_multiplier, config.grass.steer_multiplier)
	for wheel in _wheels:
		wheel.steer_angle = _steer_angle * steer_scale if wheel.front else 0.0


## Full lock at walking pace. The rack closes as forward speed rises, down to the
## angle that asks for `steer_full_lateral_accel`. Ground speed is used so a
## slide does not open the rack just because the nose is no longer along the velocity.
func _steer_angle_limit() -> float:
	var speed := Vector2(cg_velocity.x, cg_velocity.z).length()
	var cap := config.max_steer_rad
	if speed < 1.0:
		return cap
	var ay := maxf(config.steer_full_lateral_accel, 0.5)
	var wheelbase := maxf(_wheelbase, 0.5)
	return minf(cap, atan(ay * wheelbase / (speed * speed)))


## Rack speed. High speed shortens it. During a slide the wheel is allowed to
## move into counter-steer, and its return toward center is slowed.
func _steering_rate(target_angle: float) -> float:
	if not use_dynamic_steering:
		return config.steer_rate_rad_s
	var speed := maxf(longitudinal_speed(), 0.0)
	var rate := maxf(steering_damping_speed, 0.2) / (1.0 + speed * 0.015)
	if not _slide_needs_catch():
		return rate
	var adding_catch := target_angle * yaw_rate < 0.0 and absf(target_angle) > absf(_steer_angle)
	if adding_catch:
		return rate
	return rate * _COUNTERSTEER_RETURN


func _slide_needs_catch() -> bool:
	if absf(yaw_rate) < _SLIDE_YAW_RATE or absf(lateral_speed()) < _SLIDE_LATERAL_MPS:
		return false
	if longitudinal_speed() < 6.0:
		return false
	return _steer_input * yaw_rate <= 0.02


func _shaped_steer(amount: float) -> float:
	var curve := maxf(config.steer_input_curve, 1.0)
	return signf(amount) * pow(absf(amount), curve)


func _tire_force(wheel: Wheel, basis: Basis, drive_each: float, brake_input: float, dt: float) -> Vector3:
	var omega := Vector3(0.0, yaw_rate, 0.0)
	var contact_world: Vector3 = cg_velocity + omega.cross(basis * wheel.offset)
	var contact_body := basis.inverse() * contact_world
	var fwd := Vector3(sin(wheel.steer_angle), 0.0, cos(wheel.steer_angle))
	var right := Vector3(cos(wheel.steer_angle), 0.0, -sin(wheel.steer_angle))
	var v_long := contact_body.dot(fwd)
	var v_lat := contact_body.dot(right)
	wheel.forward_velocity = v_long
	wheel.lateral_velocity = v_lat

	var reg := maxf(config.slip_speed_regularization_mps, 0.05)
	var slip := atan2(v_lat, absf(v_long) + reg)
	wheel.slip_angle = slip

	var blend := wheel.surface_blend
	var mu := _tire_grip * _blended(blend, config.asphalt.grip_multiplier, config.grass.grip_multiplier)
	wheel.grip = mu
	var limit := mu * wheel.normal_load
	var axle_share := config.brake_front_fraction if wheel.front else (1.0 - config.brake_front_fraction)
	var brake_n := brake_input * config.brake_force_n * axle_share * 0.5
	var along := _smooth_sign(v_long)
	var rolling := _blended(blend, config.asphalt.rolling_resistance, config.grass.rolling_resistance)
	var long_request := -brake_n * along
	long_request -= rolling * wheel.normal_load * along
	if wheel.driven:
		var drive_scale := _blended(blend, config.asphalt.drive_multiplier, config.grass.drive_multiplier)
		long_request += drive_each * drive_scale
	if limit <= 1.0:
		wheel.long_slip = 0.0
		wheel.long_force = 0.0
		wheel.lat_force = 0.0
		wheel.grip_utilization = 0.0
		var unloaded := _surface_drag(blend, contact_body)
		wheel.force_body = unloaded
		return unloaded

	var requested := long_request / limit
	var combined := Vector2.ZERO
	wheel.peak_curve = use_peak_slip_curve
	if use_peak_slip_curve:
		var peak_ratio := clampf(peak_slip_threshold, 0.06, 0.10)
		var slip_target := _slip_target(requested)
		var chase := _SLIP_RESPONSE + absf(v_long) * 0.25
		wheel.long_slip = move_toward(wheel.long_slip, slip_target, chase * dt)
		var s_lat := slip / maxf(deg_to_rad(peak_ratio * 100.0), 0.05)
		combined = _combined_slip_force(wheel.long_slip, s_lat, limit)
	else:
		wheel.long_slip = requested
		var s_lat := slip / maxf(config.slip_angle_full_grip_rad, 0.01)
		combined = _saturating_slip_force(requested, s_lat, limit)
	wheel.long_force = combined.x
	wheel.lat_force = combined.y
	wheel.grip_utilization = combined.length() / limit
	var force := fwd * combined.x + right * combined.y
	force += _surface_drag(blend, contact_body)
	wheel.force_body = force
	return force


func _surface_drag(blend: float, contact_body: Vector3) -> Vector3:
	var resist := _blended(blend, config.asphalt.speed_resistance, config.grass.speed_resistance)
	if resist <= 0.0:
		return Vector3.ZERO
	var planar := Vector2(contact_body.x, contact_body.z)
	var speed := planar.length()
	return Vector3(-contact_body.x, 0.0, -contact_body.z) * resist * speed


func _chase_pedals(dt: float, drive_target: float, brake_target: float) -> void:
	var blend := 1.0 - exp(-config.throttle_response * dt)
	_drive_filtered = lerpf(_drive_filtered, drive_target, blend)
	if use_brake_ramp and brake_target > _brake_filtered:
		var rise := 1.0 / maxf(brake_build_time, 0.05)
		_brake_filtered = move_toward(_brake_filtered, brake_target, rise * dt)
	else:
		_brake_filtered = lerpf(_brake_filtered, brake_target, blend)


func _blended(blend: float, asphalt_value: float, grass_value: float) -> float:
	return lerpf(asphalt_value, grass_value, clampf(blend, 0.0, 1.0))


## Normalized slip of 1 sits on the grip peak. The input is signed demand
## divided by the friction limit. Demand the tire can hold stays at or below
## the peak. Demand past the limit runs out onto the sliding side.
func _slip_target(requested: float) -> float:
	var mag := absf(requested)
	if mag <= 0.001:
		return 0.0
	var signed := 0.0
	if mag <= 1.0:
		signed = asin(mag) / (PI * 0.5)
	else:
		signed = 1.0 + (mag - 1.0) * 1.6
	return clampf(signf(requested) * signed, -3.5, 3.5)


## Simplified peak-and-fall curve. `normalized_slip` is 1 at the grip peak.
## The rise is a quarter sine, so the slope is zero at the peak. Past the peak
## a smooth step falls to `sliding_grip_factor` and stays there.
func _grip_curve(normalized_slip: float) -> float:
	var x := absf(normalized_slip)
	if x <= 0.00001:
		return 0.0
	if x <= 1.0:
		return sin(x * PI * 0.5)
	var slide := clampf(sliding_grip_factor, 0.45, 0.95)
	var t := clampf((x - 1.0) / 1.35, 0.0, 1.0)
	var blend := t * t * (3.0 - 2.0 * t)
	return lerpf(1.0, slide, blend)


## Friction circle. The slip vector picks the direction. The curve picks how
## much of the limit that direction is allowed to use.
func _combined_slip_force(s_long: float, s_lat: float, limit: float) -> Vector2:
	var slip_mag := sqrt(s_long * s_long + s_lat * s_lat)
	if slip_mag <= 0.00001:
		return Vector2.ZERO
	var scale := limit * _grip_curve(slip_mag) / slip_mag
	return Vector2(s_long * scale, -s_lat * scale)


## Small slip is nearly linear. Large slip sits on the friction circle and
## extra slip barely increases the force. Force never falls past the limit.
func _saturating_slip_force(s_long: float, s_lat: float, limit: float) -> Vector2:
	var slip_mag := sqrt(s_long * s_long + s_lat * s_lat)
	if slip_mag <= 0.00001:
		return Vector2.ZERO
	var order := maxf(config.slip_curve_order, 2.0)
	var used := slip_mag / pow(1.0 + pow(slip_mag, order), 1.0 / order)
	var scale := limit * used / slip_mag
	return Vector2(s_long * scale, -s_lat * scale)


func _aero_force_body(basis: Basis) -> Vector3:
	var v_body := basis.inverse() * cg_velocity
	var planar := Vector2(v_body.x, v_body.z)
	var speed := planar.length()
	var coeff := 0.5 * config.air_density * config.drag_area_m2 * speed
	return Vector3(-coeff * v_body.x, 0.0, -coeff * v_body.z)


func _smooth_sign(speed: float) -> float:
	var eps := maxf(config.longitudinal_smoothing_mps, 0.05)
	return speed / sqrt(speed * speed + eps * eps)


func _distribute_weight() -> void:
	if _wheels.size() != 4:
		return
	var front_z := (_wheels[0].offset.z + _wheels[1].offset.z) * 0.5
	var rear_z := (_wheels[2].offset.z + _wheels[3].offset.z) * 0.5
	var span := maxf(absf(front_z - rear_z), 0.01)
	var to_front := absf(front_z)
	var to_rear := absf(rear_z)
	_wheelbase = span
	_front_track = maxf(absf(_wheels[0].offset.x - _wheels[1].offset.x), 0.4)
	_rear_track = maxf(absf(_wheels[2].offset.x - _wheels[3].offset.x), 0.4)
	var weight := config.mass_kg * config.gravity
	var front_each := weight * to_rear / span * 0.5
	var rear_each := weight * to_front / span * 0.5
	_static_front_axle = front_each * 2.0
	_static_rear_axle = rear_each * 2.0
	for wheel in _wheels:
		var static_load := front_each if wheel.front else rear_each
		wheel.static_load = static_load
		wheel.normal_load = static_load
		wheel.grip = _tire_grip


## Steady load shift from the mass center: forward accel loads the rear,
## braking loads the front, and lateral accel loads the outside wheels.
## The result is filtered so the normal force does not jump in one tick.
func _update_load_transfer(dt: float) -> void:
	if _wheels.size() != 4:
		return
	var height := maxf(config.cg_height_m, 0.0)
	var long_shift := config.mass_kg * _long_accel * height / _wheelbase
	var front_axle := maxf(_static_front_axle - long_shift, 0.0)
	var rear_axle := maxf(_static_rear_axle + long_shift, 0.0)
	var weight := maxf(config.mass_kg * config.gravity, 1.0)
	var front_share := _static_front_axle / weight
	var lat_moment := config.mass_kg * _lat_accel * height
	var front_transfer := front_share * lat_moment / _front_track
	var rear_transfer := (1.0 - front_share) * lat_moment / _rear_track
	var response := maxf(config.load_transfer_response_s, 0.01)
	var blend := 1.0 - exp(-dt / response)
	for wheel in _wheels:
		var axle := front_axle if wheel.front else rear_axle
		var transfer := front_transfer if wheel.front else rear_transfer
		# Positive lateral accel points to +X. The left wheel (negative X) takes that load.
		var side := 1.0 if wheel.offset.x <= 0.0 else -1.0
		var target := maxf(axle * 0.5 + side * transfer, 0.0)
		wheel.normal_load = lerpf(wheel.normal_load, target, blend)


## Ray length under each hub. A physics hit on the road wins. A miss uses the
## flat y=0 surface the track is built on, because the road mesh has no collider.
func _update_suspension(dt: float) -> void:
	if _wheels.is_empty():
		return
	var car := get_parent() as CollisionObject3D
	if car == null:
		return
	var space: PhysicsDirectSpaceState3D = null
	var world := car.get_world_3d()
	if world != null:
		space = world.direct_space_state
	var stiffness := maxf(spring_stiffness, 1000.0)
	var damper := maxf(damper_coefficient, 0.0)
	for wheel in _wheels:
		var origin := car.global_transform * wheel.local_position
		origin.y += _heave + _pitch * wheel.offset.z + _roll * wheel.offset.x
		var ground_y := _raycast_ground(space, car, origin)
		var drop := origin.y - ground_y
		if wheel.ride_recapture:
			wheel.ride_drop = _ride_drop_sample(wheel.ride_drop, drop)
			wheel.ride_recapture = false
		var sag := wheel.static_load / stiffness
		wheel.rest_length = wheel.ride_drop + sag
		var travel := wheel.rest_length - drop
		var compression := clampf(travel, 0.0, _MAX_TRAVEL_M)
		if not wheel.suspension_ready:
			wheel.compression = compression
			wheel.compression_speed = 0.0
			wheel.suspension_ready = true
		else:
			var raw_speed := (compression - wheel.compression) / maxf(dt, 0.0001)
			var blend := 1.0 - exp(-16.0 * dt)
			wheel.compression_speed = lerpf(wheel.compression_speed, raw_speed, blend)
			wheel.compression = compression
		var force := compression * stiffness + wheel.compression_speed * damper
		if travel > _MAX_TRAVEL_M:
			force += (travel - _MAX_TRAVEL_M) * stiffness * _BUMP_STIFFNESS
		var cap := maxf(wheel.static_load, 1.0) * _LOAD_CAP
		force = clampf(force, 0.0, cap)
		wheel.suspension_force = force
		wheel.normal_load = force
		wheel.grounded = travel > 0.0


## Rest ride height for a wheel, sampled on the first step after a reset or a
## new wheel layout. A sample outside the plausible range, or one that jumps
## away from the last good height (a body lifted by a collision), is ignored.
func _ride_drop_sample(previous: float, drop: float) -> float:
	var plausible := drop >= _MIN_RIDE_DROP_M and drop <= _MAX_RIDE_DROP_M
	if previous <= 0.0:
		return drop if plausible else _DEFAULT_RIDE_DROP_M
	if plausible and absf(drop - previous) <= _RIDE_RECAPTURE_TOLERANCE_M:
		return drop
	return previous


func _raycast_ground(space: PhysicsDirectSpaceState3D, car: CollisionObject3D, origin: Vector3) -> float:
	var end := origin + Vector3(0.0, -_RAY_LENGTH_M, 0.0)
	if space != null:
		var exclude: Array[RID] = [car.get_rid()]
		var query := PhysicsRayQueryParameters3D.create(origin, end, _WORLD_MASK, exclude)
		query.collide_with_areas = false
		query.hit_from_inside = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.get("normal", Vector3.UP)
			var point: Vector3 = hit.get("position", end)
			var near_road := point.y <= _GROUND_Y + 0.4 and point.y >= _GROUND_Y - 1.0
			if normal.y > 0.45 and point.y <= origin.y and near_road:
				return point.y
	if origin.y >= _GROUND_Y - _RAY_LENGTH_M:
		return _GROUND_Y
	return origin.y + _RAY_LENGTH_M


## Heave, pitch, and roll from the spring forces plus the inertial couple at the
## mass center. Positive pitch lifts the nose. Positive roll lowers the left side.
func _integrate_suspension(dt: float) -> void:
	if _wheels.is_empty() or config.mass_kg <= 0.0:
		return
	var support := 0.0
	var pitch_moment := 0.0
	var roll_moment := 0.0
	for wheel in _wheels:
		var force := wheel.suspension_force
		support += force
		pitch_moment += force * wheel.offset.z
		roll_moment += force * wheel.offset.x
	var mass := config.mass_kg
	var height := maxf(config.cg_height_m, 0.0)
	_heave_vel += (support - mass * config.gravity) / mass * dt
	_pitch_vel += (pitch_moment + mass * _long_accel * height) / _pitch_inertia * dt
	_roll_vel += (roll_moment + mass * _lat_accel * height) / _roll_inertia * dt
	_heave += _heave_vel * dt
	_pitch += _pitch_vel * dt
	_roll += _roll_vel * dt
	if absf(_heave) > _HEAVE_LIMIT_M:
		_heave = clampf(_heave, -_HEAVE_LIMIT_M, _HEAVE_LIMIT_M)
		_heave_vel = 0.0
	if absf(_pitch) > _LEAN_LIMIT_RAD:
		_pitch = clampf(_pitch, -_LEAN_LIMIT_RAD, _LEAN_LIMIT_RAD)
		_pitch_vel = 0.0
	if absf(_roll) > _LEAN_LIMIT_RAD:
		_roll = clampf(_roll, -_LEAN_LIMIT_RAD, _LEAN_LIMIT_RAD)
		_roll_vel = 0.0


func _update_inertia() -> void:
	if config.yaw_inertia_override_kgm2 > 0.0:
		yaw_inertia = config.yaw_inertia_override_kgm2
	elif _wheels.size() != 4:
		yaw_inertia = config.mass_kg * config.wheelbase_m * config.wheelbase_m / 12.0
	else:
		var to_front := absf((_wheels[0].offset.z + _wheels[1].offset.z) * 0.5)
		var to_rear := absf((_wheels[2].offset.z + _wheels[3].offset.z) * 0.5)
		yaw_inertia = maxf(config.mass_kg * to_front * to_rear, 1.0)
	var height := config.cg_height_m
	_pitch_inertia = maxf(yaw_inertia + config.mass_kg * height * height, 1.0)
	var track := maxf((_front_track + _rear_track) * 0.5, 0.4)
	_roll_inertia = maxf(config.mass_kg * (height * height + track * track / 12.0), 1.0)


func _apply_grip_to_wheels() -> void:
	for wheel in _wheels:
		wheel.grip = _tire_grip


func _basis() -> Basis:
	return Basis(Vector3.UP, yaw)
