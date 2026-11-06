extends RefCounted

## A car's height on a track with jumps. Where the road drops away faster than the car can fall, at
## a ramp's lip or over a crest taken fast, the car leaves it and flies until it comes back down.
## Height only: the car keeps its speed and heading in the air, and the caller stops driving it.

const GRAVITY := 9.81
## How far behind and ahead of the car the road's grade is read, in meters. The road's own sample
## step, so over a crest the grade turns as smoothly as the road does, not in a jump at each sample.
const GRADE_SPAN_M := 2.0
## Steepest grade a car on the ground takes up into its climb, as rise over run.
const MAX_CLIMB := 1.0
## How fast the nose follows the way the car is flying, per second.
const PITCH_RATE := 3.0
## Coming down this hard or softer, in m/s into the road, the springs take it all.
const LANDING_SOAK_MPS := 4.0
## Share of the rest that counts as a hit to the car. Springs and tires take a hit straight down
## better than a barrier takes one from the side.
const LANDING_HARM_SHARE := 0.5

var airborne: bool = false
## Height of the car above the track's level, where it would sit on flat road at 0, in meters.
var height: float = 0.0
## How fast the car is rising, in m/s. Falling is below 0.
var rise: float = 0.0
## On the step a car comes down: how hard, in m/s straight into the road. 0 on every other step.
var impact: float = 0.0
var _started: bool = false


## Puts the car back on the road at the next step.
func reset() -> void:
	airborne = false
	rise = 0.0
	impact = 0.0
	_started = false


## One step. `travel` is the flat direction the car is moving, `speed` its flat speed in m/s.
func step(track: Node, world: Vector3, travel: Vector3, speed: float, delta: float) -> void:
	impact = 0.0
	var ground: float = track.surface_height(world)
	if not _started or delta <= 0.0:
		_started = true
		height = ground
		rise = 0.0
		return
	if airborne:
		rise -= GRAVITY * delta
		height += rise * delta
		if height > ground:
			return
		var ahead: float = track.surface_height(world + travel * GRADE_SPAN_M)
		var grade := (ahead - ground) / GRADE_SPAN_M
		impact = maxf(grade * speed - rise, 0.0) / sqrt(1.0 + grade * grade)
		airborne = false
		height = ground
		rise = _follow_rise(track, world, travel, speed, ground)
		return
	var follow := _follow_rise(track, world, travel, speed, ground)
	if (follow - rise) / delta < -GRAVITY:
		# The road falls away faster than the car can: it flies on with the rise it had.
		airborne = true
		height = maxf(height + rise * delta - 0.5 * GRAVITY * delta * delta, ground)
		rise -= GRAVITY * delta
		return
	height = ground
	rise = follow


## How fast a car on the road at `world` is rising, by the grade it has just come up.
func _follow_rise(track: Node, world: Vector3, travel: Vector3, speed: float, ground: float) -> float:
	var behind: float = track.surface_height(world - travel * GRADE_SPAN_M)
	return minf((ground - behind) / GRADE_SPAN_M, MAX_CLIMB) * speed


## The pitch to give a car in the air: its nose turning to the way it is flying.
func flight_pitch(pitch: float, speed: float, delta: float) -> float:
	var wanted := -atan2(rise, maxf(speed, 1.0))
	return lerp_angle(pitch, wanted, 1.0 - exp(-PITCH_RATE * delta))


## How hard a landing `impact` hits the car, as a change of speed for `car_damage.gd`.
static func landing_harm(impact: float) -> float:
	return maxf(impact - LANDING_SOAK_MPS, 0.0) * LANDING_HARM_SHARE
