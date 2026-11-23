extends RefCounted

## Whether a road race or Mulholland Drive has a police car, and when that car
## writes a ticket. The cars themselves live in the race. About one race in seven
## has a cop. On Mulholland it is another car in the traffic. On the road race it
## sits parked until the player drives past, then chases. A ticket is the cruise
## one: a real hit, or stopped inside pull range. A chase that draws level also
## writes it, because a race does not wait for the driver to pull over.

const _Cruise := preload("res://scripts/cruise_police.gd")

const APPEAR_CHANCE := 0.15
## Closes this much faster than the car ahead, once it is well behind.
const PURSUE_BONUS_MPS := 8.0
const PURSUE_MIN_MPS := 26.0
const PURSUE_CAP_MPS := 62.0
## How hard the parked car can speed up, so a fast car can still get away.
const PURSUE_ACCEL := 9.0
## Alongside for this long counts as caught.
const CATCH_S := 0.6
## Cop is level when it is no farther behind than this.
const LEVEL_BEHIND_M := 6.0

var active := false
var ticketed := false
var pursuing := false

var _parked := false
var _was_behind := false
var _catch_s := 0.0


static func rolled_in(roll: float) -> bool:
	return roll < APPEAR_CHANCE


## Top speed while catching up. Levels off so a much faster car can hold a lead.
static func chase_mps(player_speed: float) -> float:
	return clampf(maxf(player_speed, 0.0) + PURSUE_BONUS_MPS, PURSUE_MIN_MPS, PURSUE_CAP_MPS)


## Pace along the track. Behind, catch up. Level, match. Ahead, ease off and wait.
static func pace_for(cop_s: float, player_s: float, player_speed: float) -> float:
	var ahead := cop_s - player_s
	var moving := maxf(player_speed, 0.0)
	if ahead > 6.0:
		return minf(moving, 11.0)
	if ahead > -16.0:
		return maxf(moving, 11.0)
	return chase_mps(moving)


func arm_traffic() -> void:
	active = true


func arm_parked() -> void:
	active = true
	_parked = true


## A cop that is not chasing. A real hit, or a stop inside pull range, is a ticket.
func note_beside(gap_m: float, player_speed: float, hit_mps: float) -> bool:
	if not active or ticketed or pursuing:
		return false
	return _cite(gap_m, player_speed, hit_mps)


## The player was behind the parked cop and has now gone past it.
func note_pass(player_s: float, cop_s: float) -> bool:
	if not _parked or pursuing or ticketed:
		return false
	if player_s + 2.0 < cop_s:
		_was_behind = true
		return false
	if _was_behind and player_s >= cop_s:
		_parked = false
		pursuing = true
		_was_behind = false
		return true
	return false


## The chase. Level for CATCH_S, stopped in range, or a real hit.
func note_chase(gap_m: float, player_speed: float, cop_s: float, player_s: float, delta: float, hit_mps: float) -> bool:
	if not pursuing or ticketed:
		return false
	if _cite(gap_m, player_speed, hit_mps):
		return true
	var level := gap_m <= _Cruise.PULL_RANGE_M and cop_s >= player_s - LEVEL_BEHIND_M
	if level:
		_catch_s += delta
		if _catch_s >= CATCH_S:
			ticketed = true
			return true
	else:
		_catch_s = 0.0
	return false


func _cite(gap_m: float, player_speed: float, hit_mps: float) -> bool:
	if hit_mps > _Cruise.NOTICE_MPS or (gap_m <= _Cruise.PULL_RANGE_M and player_speed <= _Cruise.TICKET_MPS):
		ticketed = true
		return true
	return false
