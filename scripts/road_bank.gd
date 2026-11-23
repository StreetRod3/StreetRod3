extends RefCounted

## What a banked road does to a car, for both driving models. Each works in the flat, so the bank
## comes in as two things: a pull toward the road's low side, and a change in how hard the tires
## are pressed onto it.
##
## On a road banked at `a`, a car turning with sideways acceleration `lat` (flat, toward its +X)
## is held by the road's push, square to the road, and by its tires, along it. Worked back to the
## flat, that is a pull of g·tan(a) toward the low side, which takes the car round on its own at
## the bank's own speed, and tires that hold (1 + lat·tan(a)/g) times what they would on the flat,
## more when turning toward the low side. Together they give a banked corner's real top speed.
## `slope` here is tan(a) across the car: the rise a meter toward the car's +X.

const GRAVITY := 9.81
## Past these the tires' load is held: up a steep bank with good tires the sum has no top.
const LOAD_MIN := 0.3
const LOAD_MAX := 2.0
## Below this speed the tires hold a car still on the bank, as a parked car's do, rather than
## let it creep down.
const HOLD_SPEED := 2.0


## The bank's pull across the car, toward its +X, in m/s², for a car going `speed`.
static func pull(slope: float, speed: float) -> float:
	return -GRAVITY * slope * clampf(absf(speed) / HOLD_SPEED, 0.0, 1.0)


## How many times its flat grip the tires have, turning at `lat` m/s² toward the car's +X.
static func load(slope: float, lat: float) -> float:
	if is_zero_approx(slope):
		return 1.0
	return clampf(1.0 - lat * slope / GRAVITY, LOAD_MIN, LOAD_MAX)
