extends RefCounted

## The driving model used before the tire simulation: speed is integrated
## directly, and a bicycle chassis with a yaw cap turns the car.

const ACCELERATION := 24.0
## Hard stops, but ones the tires could plausibly do, with steering left to use.
const BRAKING := 14.0
## Speed kept per 1/60 s, lifted off the throttle. Engine braking and drag, no more.
const COAST_FACTOR := 0.998
const REF_GEAR_RATIO := 2.80
const WHEELBASE_M := 2.59
const MAX_STEER_RAD := 0.52
const STEER_RESPONSE := 3.2
## Sideways acceleration full steering asks for at speed, in m/s². As in the simulation,
## the rack closes as speed rises, so a key press is not full lock at top speed.
const STEER_FULL_LATERAL_ACCEL := 14.0
## Extra angle at any speed, for the slip the front tires need to make that force.
const STEER_SLIP_ALLOWANCE_RAD := 0.055
## How fast the steering input moves on and back off, per second, so a tap is a small turn.
const STEER_INPUT_RATE := 4.0
const STEER_INPUT_RETURN := 7.0
## The most of a tire's grip that braking or power can take. What is left always steers.
const LONG_GRIP_SHARE_MAX := 0.72
## Acceleration past this shifts no more weight between the axles, in m/s².
const LOAD_TRANSFER_ACCEL_MAX := 11.0
## How far the nose may turn past what the tires can hold the path to. A little lets
## the car rotate into a corner; more and it slides on until steering cannot catch it.
const YAW_GRIP_MARGIN := 1.25
## Share of the sideways grip in use before cornering starts to take power away.
const CORNER_POWER_FADE_FROM := 0.5
## The power left when cornering takes all the grip the tires have.
const CORNER_POWER_MIN := 0.2
## How quickly the tires stop a car turning after a hit, in 1/seconds.
const SPIN_DECAY := 2.8
## How fast a barrier swings the nose round, in rad/s.
const SWING_RATE := 5.0
## How fast turning past what the wheel asks for dies away, in rad/s². The car carries
## its rotation for a moment as the wheel comes back, instead of stopping dead.
const YAW_SETTLE_RATE := 2.2
## Share of the front tires' sideways force that slows the car in a turn.
const CORNER_SCRUB := 0.6
## How quickly the turning dies away once the wheel is straight, in 1/seconds.
const STRAIGHTEN_RATE := 4.0
const MASS_KG := 1360.0
const CG_HEIGHT_M := 0.48
const GRAVITY := 9.81
const MU_DRY := 1.6
## Loose surface. Still well under dry grip, but the nose can come around.
const MU_OFFROAD := 0.78
const FRONT_AXLE_FRACTION := 0.46
const CORNERING_FRONT := 52000.0
const CORNERING_REAR := 64000.0
const GRIP_FADE_SPEED := 2.0
const TRACK_X_LIMIT := 18.0
const OFFROAD_ACCEL_SCALE := 0.42
const OFFROAD_DRAG := 0.993
const OFFROAD_MAX_SPEED_SCALE := 0.5
## How hard the loose surface slows a car that arrives above that speed, in m/s².
const OFFROAD_SLOWDOWN := 20.0

var forward_speed: float = 0.0
var heading_yaw: float = 0.0
var steer_angle: float = 0.0

var _lateral_speed: float = 0.0
var _yaw_rate: float = 0.0
var _off_road: bool = false
var _wheelbase: float = WHEELBASE_M
var _mass_kg: float = MASS_KG
var _cg_height: float = CG_HEIGHT_M
var _front_axle_fraction: float = FRONT_AXLE_FRACTION
var _max_steer_rad: float = MAX_STEER_RAD
var _wheel_grip: float = 3.0
var _steer_input: float = 0.0
## Turning from a hit, in rad/s. It is not the driver's, so the yaw cap does not hold it.
var _spin: float = 0.0
## Share of the tires' grip the suspension leaves. The car's springs and shocks set it.
var ride_grip: float = 1.0
## Swing from a barrier still to come, in radians.
var _swing: float = 0.0
## Sideways acceleration the tires can hold right now, in m/s².
var _lateral_grip: float = MU_DRY * GRAVITY


func apply_spec(chassis: Dictionary, grip_rating: float) -> void:
	if not chassis.is_empty():
		_mass_kg = float(chassis.get("mass", _mass_kg))
		_wheelbase = float(chassis.get("wheelbase", _wheelbase))
		_cg_height = float(chassis.get("cg_height", _cg_height))
		_front_axle_fraction = float(chassis.get("front_axle_fraction", _front_axle_fraction))
		_max_steer_rad = deg_to_rad(float(chassis.get("max_steer_deg", rad_to_deg(_max_steer_rad))))
	_wheel_grip = clampf(grip_rating, 1.0, 5.0)


func reset() -> void:
	forward_speed = 0.0
	steer_angle = 0.0
	_stop_slide()


## How far the steering has been asked to turn, -1 to 1.
func steer_input() -> float:
	return _steer_input


func planar_velocity() -> Vector3:
	var forward := Vector3(sin(heading_yaw), 0.0, cos(heading_yaw))
	var right := Vector3(cos(heading_yaw), 0.0, -sin(heading_yaw))
	return forward * forward_speed + right * _lateral_speed


## Replaces the planar velocity after a bumper hit. Forward speed stays at or above zero.
func apply_planar_velocity(body: CharacterBody3D, planar: Vector3, car_center: Vector3) -> void:
	var forward := Vector3(sin(heading_yaw), 0.0, cos(heading_yaw))
	var right := Vector3(cos(heading_yaw), 0.0, -sin(heading_yaw))
	forward_speed = maxf(planar.dot(forward), 0.0)
	_lateral_speed = planar.dot(right)
	body.velocity = forward * forward_speed + right * _lateral_speed
	_apply_heading(body, car_center)


## A hit sets the car turning.
func kick_yaw(rate: float) -> void:
	_spin += rate


## A barrier swings the nose this far, in radians, over the next moments.
func swing_by(angle: float) -> void:
	_swing = angle
	_yaw_rate = 0.0


func _stop_slide() -> void:
	_lateral_speed = 0.0
	_yaw_rate = 0.0
	_spin = 0.0
	_swing = 0.0


## Gear acceleration is already scaled by ratio, power, and headroom.
func step(
	body: CharacterBody3D,
	delta: float,
	steer: float,
	throttle: bool,
	brake: bool,
	shifting: bool,
	blown: bool,
	gear_accel: float,
	max_mps: float,
	car_center: Vector3
) -> void:
	_update_surface(body)
	var speed_before := forward_speed
	var accel_scale := OFFROAD_ACCEL_SCALE if _off_road else 1.0
	if throttle and not shifting:
		forward_speed += gear_accel * accel_scale * grip_accel_scale(_wheel_grip) * _corner_power() * delta
	elif brake:
		forward_speed -= BRAKING * delta
	elif not throttle:
		forward_speed *= pow(COAST_FACTOR, delta * 60.0)
	if blown:
		forward_speed *= pow(0.96, delta * 60.0)
	if _off_road:
		forward_speed *= pow(OFFROAD_DRAG, delta * 60.0)
		var offroad_max := max_mps * OFFROAD_MAX_SPEED_SCALE
		if forward_speed > offroad_max:
			forward_speed = move_toward(forward_speed, offroad_max, OFFROAD_SLOWDOWN * delta)
	forward_speed = clampf(forward_speed, 0.0, max_mps)

	var longitudinal_accel := (forward_speed - speed_before) / maxf(delta, 0.0001)
	var wanted := clampf(steer, -1.0, 1.0)
	var input_rate := STEER_INPUT_RATE if wanted * _steer_input > 0.0 and absf(wanted) > absf(_steer_input) else STEER_INPUT_RETURN
	_steer_input = move_toward(_steer_input, wanted, input_rate * delta)
	var steer_target := _steer_input * _steer_limit() * _grip_steer_scale()
	steer_angle = move_toward(steer_angle, steer_target, STEER_RESPONSE * delta)
	_step_chassis(delta, longitudinal_accel)
	if absf(_steer_input) < 0.02 and absf(steer_angle) < 0.02:
		var straighten := clampf(STRAIGHTEN_RATE * delta, 0.0, 1.0)
		_yaw_rate = lerpf(_yaw_rate, 0.0, straighten)
		_lateral_speed = lerpf(_lateral_speed, 0.0, straighten)
	var steered_yaw := absf(forward_speed * tan(steer_angle) / _wheelbase) * 1.2 * _grip_steer_scale() + 0.08
	if absf(_yaw_rate) > steered_yaw:
		_yaw_rate = move_toward(_yaw_rate, signf(_yaw_rate) * steered_yaw, YAW_SETTLE_RATE * delta)
	var grip_yaw := YAW_GRIP_MARGIN * _lateral_grip / maxf(forward_speed, GRIP_FADE_SPEED)
	_yaw_rate = clampf(_yaw_rate, -grip_yaw, grip_yaw)
	_lateral_speed = clampf(_lateral_speed, -forward_speed * 0.45, forward_speed * 0.45)
	forward_speed = clampf(forward_speed, 0.0, max_mps)
	var swung := clampf(_swing, -SWING_RATE * delta, SWING_RATE * delta)
	_swing -= swung
	heading_yaw += (_yaw_rate + _spin) * delta + swung
	_spin *= exp(-SPIN_DECAY * delta)

	var forward_dir := Vector3(sin(heading_yaw), 0.0, cos(heading_yaw))
	var right_dir := Vector3(cos(heading_yaw), 0.0, -sin(heading_yaw))
	body.velocity = forward_dir * forward_speed + right_dir * _lateral_speed
	_apply_heading(body, car_center)


func hold(body: CharacterBody3D, delta: float, car_center: Vector3) -> void:
	forward_speed = 0.0
	_stop_slide()
	_steer_input = 0.0
	steer_angle = move_toward(steer_angle, 0.0, STEER_RESPONSE * delta)
	body.velocity = Vector3.ZERO
	_apply_heading(body, car_center)


## The road-wheel angle full steering gives at this speed, never past the lock.
func _steer_limit() -> float:
	var speed := maxf(forward_speed, 1.0)
	return minf(_max_steer_rad, atan(STEER_FULL_LATERAL_ACCEL * ride_grip * _wheelbase / (speed * speed)) + STEER_SLIP_ALLOWANCE_RAD)


static func grip_accel_scale(grip_rating: float) -> float:
	return 1.0 + (grip_rating - 3.0) * 0.04


## How much of the engine's pull the tires can pass on while they are also cornering.
func _corner_power() -> float:
	return corner_power(absf(forward_speed * _yaw_rate) / maxf(_lateral_grip, 0.1))


## The share of its pull a car keeps with this share of its sideways grip in use.
static func corner_power(grip_used: float) -> float:
	return clampf((1.0 - grip_used) / (1.0 - CORNER_POWER_FADE_FROM), CORNER_POWER_MIN, 1.0)


## Sideways acceleration tires of this rating can hold on dry road, in m/s².
static func dry_grip_accel(grip_rating: float, ride: float) -> float:
	return MU_DRY * GRAVITY * ride * grip_steer_scale(grip_rating)


func _grip_steer_scale() -> float:
	return grip_steer_scale(_wheel_grip)


static func grip_steer_scale(grip_rating: float) -> float:
	return 1.0 + (grip_rating - 3.0) * 0.12


func _step_chassis(delta: float, longitudinal_accel: float) -> void:
	var axle_front := _wheelbase * _front_axle_fraction
	var axle_rear := _wheelbase - axle_front
	var steer_grip := _grip_steer_scale()
	var mu := (MU_OFFROAD if _off_road else MU_DRY) * ride_grip * steer_grip
	var weight := _mass_kg * GRAVITY
	var transfer_accel := clampf(longitudinal_accel, -LOAD_TRANSFER_ACCEL_MAX, LOAD_TRANSFER_ACCEL_MAX)
	var transfer := _mass_kg * transfer_accel * _cg_height / _wheelbase
	var fz_front := maxf(weight * axle_rear / _wheelbase - transfer, weight * 0.12)
	var fz_rear := maxf(weight * axle_front / _wheelbase + transfer, weight * 0.12)
	var long_front := 0.0
	var long_rear := _mass_kg * longitudinal_accel
	if longitudinal_accel < 0.0:
		long_front = _mass_kg * longitudinal_accel * 0.65
		long_rear = _mass_kg * longitudinal_accel * 0.35

	var speed := maxf(forward_speed, 0.35)
	var front_slip := atan2(_lateral_speed + _yaw_rate * axle_front, speed) - steer_angle
	var rear_slip := atan2(_lateral_speed - _yaw_rate * axle_rear, speed)
	var front_force := _tire_force(front_slip, CORNERING_FRONT * steer_grip, fz_front, long_front, mu)
	var rear_force := _tire_force(rear_slip, CORNERING_REAR * steer_grip, fz_rear, long_rear, mu)
	var rolling := clampf(forward_speed / GRIP_FADE_SPEED, 0.0, 1.0)
	front_force *= rolling
	rear_force *= rolling

	_lateral_grip = (_lateral_limit(fz_front, long_front, mu) + _lateral_limit(fz_rear, long_rear, mu)) / _mass_kg
	var steer_cos := cos(steer_angle)
	var steer_sin := sin(steer_angle)
	var lateral_force := front_force * steer_cos + rear_force
	var yaw_moment := front_force * steer_cos * axle_front - rear_force * axle_rear
	var inertia := _mass_kg * axle_front * axle_rear
	_lateral_speed += (lateral_force / _mass_kg - _yaw_rate * forward_speed) * delta
	_yaw_rate += (yaw_moment / inertia) * delta
	forward_speed += (-front_force * steer_sin * CORNER_SCRUB / _mass_kg) * delta
	if forward_speed < GRIP_FADE_SPEED:
		var settle := (1.0 - forward_speed / GRIP_FADE_SPEED) * 8.0 * delta
		_lateral_speed = lerpf(_lateral_speed, 0.0, clampf(settle, 0.0, 1.0))
		_yaw_rate = lerpf(_yaw_rate, 0.0, clampf(settle, 0.0, 1.0))


func _tire_force(slip: float, stiffness: float, normal: float, longitudinal: float, mu: float) -> float:
	var lat_limit := _lateral_limit(normal, longitudinal, mu)
	return clampf(-stiffness * slip, -lat_limit, lat_limit)


func _lateral_limit(normal: float, longitudinal: float, mu: float) -> float:
	var limit := mu * normal
	var long_used := clampf(absf(longitudinal) / maxf(limit, 1.0), 0.0, LONG_GRIP_SHARE_MAX)
	return limit * sqrt(maxf(0.0, 1.0 - long_used * long_used))


static func gear_acceleration(ratio: float, gear_top: float, speed: float, power_hp: float) -> float:
	var headroom := 1.0
	if gear_top > 0.05:
		var progress := maxf(speed, 0.0) / gear_top
		if progress >= 1.12:
			return 0.0
		if progress >= 1.0:
			headroom = 0.14
		else:
			headroom = 1.0 - progress * progress
	var hp_scale := power_hp / 280.0
	return ACCELERATION * (ratio / REF_GEAR_RATIO) * hp_scale * headroom


func _update_surface(body: Node3D) -> void:
	var race := body.get_parent()
	if race and race.has_method(&"get_race_track"):
		var track: Node = race.get_race_track()
		if track != null and track.has_method(&"closest_sample"):
			var sample: Dictionary = track.closest_sample(body.global_position)
			var lat := float(sample.get("lateral", 0.0))
			var half := TRACK_X_LIMIT
			if track.has_method(&"get_half_width"):
				half = float(track.get_half_width())
			var left_ext := float(sample.get("left_ext", sample.get("half_width", half)))
			var right_ext := float(sample.get("right_ext", sample.get("half_width", half)))
			_off_road = lat < -(left_ext - 1.0) or lat > (right_ext - 1.0)
			return
	_off_road = absf(body.global_position.x) > TRACK_X_LIMIT


func _apply_heading(body: CharacterBody3D, car_center: Vector3) -> void:
	var center_world := body.global_transform * car_center
	body.rotation.y = heading_yaw
	var center_now := body.global_transform * car_center
	body.global_position += center_world - center_now
