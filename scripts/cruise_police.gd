extends RefCounted

## Heat and crash scenes for a free roam. The traffic cars do the driving.
## A cop sees SIGHT_M. Speeding counts only while one can see the car. A crash
## counts from anywhere, and a hit on a cop jumps the heat to 150%. The hard chase
## starts once the heat is past full, a couple of seconds after that hit.

const SIGHT_M := 150.0
const LIMIT_MPS := 11.0
## About 10 mph over the posted limit still counts as legal.
const TOLERANCE_MPH := 10.0
const _MPH := 2.2369362920544
const TOLERANCE_MPS := TOLERANCE_MPH / _MPH
const NOTICE_MPS := 1.5
const SPEED_HOLD_S := 1.0
## Time that used to clear the heat. It now takes that long to lose LOSE_DROP.
const LOSE_S := 4.0
const LOSE_DROP := 0.05
const PULL_RANGE_M := 8.0
## Cops pull alongside once the car is down to this. The ticket itself is TICKET_MPS.
const CRAWL_MPS := 3.0
## 3 mph. Under this, with a cop alongside, the car stops and the ticket is written.
const TICKET_MPS := 1.341
const GRACE_S := 20.0
## The ticket follows the heat: $10 with barely any, $100 just under a full meter.
## At 100% and above it is $100 times twice the heat, so 150% is $300.
const FINE_MIN := 10
const FINE_MAX := 100
## Watched speeding fills the meter slowly. A couple of seconds over the pace is a
## small mark, and a full meter takes a long run.
const HEAT_PER_S := 0.025
const HIT_HEAT := 0.35
## Cars out driving. Two with an empty meter, five when it is full.
const COPS_MIN := 2
const COPS_MAX := 5
const HARD_MPS := 6.0
const SCENE_JOIN_M := 18.0
const FAR_M := 80.0
const HOLD_MIN_S := 10.0
const HOLD_MAX_S := 20.0
const SCENE_LIFE_S := 20.0
const RETARGET_S := 0.5
const PATROL_MPS := 11.0
const PURSUE_MPS := 26.0
## On the road, trying to catch the car and make it pull over. Not the hard chase.
const STOP_MPS := 18.0
## The meter stops here until a stop has failed. Then it jumps to HEAT_RAMPAGE.
const HEAT_CAP := 1.0
const HEAT_RAMPAGE := 1.5
## How long the pull-over has to fail before the heat jumps past full.
const EVADE_S := 180.0
## A hit on a cop puts the heat past full at once. The hard chase waits this long.
const RAMPAGE_AFTER_HIT_S := 2.0

const PATROL := 0
const PURSUE := 1
const ATTEND := 2
const STOP := 3

var heat := 0.0
var grace := 0.0
var scenes: Array[Dictionary] = []

var _over_s := 0.0
var _crash := false
var _stop := false
## Fastest the car went while the heat was up, for the ticket.
var _top_mps := 0.0
## Seconds the car has stayed wanted without pulling over.
var _evade_s := 0.0
## The pull-over failed, or the heat is past full. Cops use the hard chase until the heat is gone.
var _rampage := false
## Seconds left before heat past full becomes the hard chase. A cop hit sets it.
var _rampage_in_s := 0.0


## `cop_seen` is a cop inside SIGHT_M. `cop_close` is one inside PULL_RANGE_M.
## `limit_mps` is the limit of the street the car is on.
func tick(delta: float, speed: float, cop_seen: bool, cop_close: bool, limit_mps: float = LIMIT_MPS) -> void:
	if delta <= 0.0:
		return
	if grace > 0.0:
		grace = maxf(grace - delta, 0.0)
		_over_s = 0.0
	elif speed > limit_mps + TOLERANCE_MPS:
		_over_s += delta
		if _over_s >= SPEED_HOLD_S and cop_seen and heat < _heat_cap():
			heat = minf(heat + HEAT_PER_S * delta, _heat_cap())
	else:
		_over_s = 0.0
		if heat > 0.0 and not cop_seen:
			heat = maxf(heat - LOSE_DROP / LOSE_S * delta, 0.0)
			if heat <= 0.0:
				_clear_want()
	if heat > 0.0:
		_top_mps = maxf(_top_mps, speed)
		if not _rampage:
			_evade_s += delta
			if _evade_s >= EVADE_S:
				_rampage = true
				heat = HEAT_RAMPAGE
	else:
		_evade_s = 0.0
	if heat > HEAT_CAP and not _rampage:
		if _rampage_in_s > 0.0:
			_rampage_in_s = maxf(_rampage_in_s - delta, 0.0)
		if _rampage_in_s <= 0.0:
			_rampage = true
	elif not _rampage:
		_rampage_in_s = 0.0
	if heat > 0.0 and speed <= TICKET_MPS and cop_close:
		_stop = true


## How many police cars should be out driving at this heat. The steps land on
## each third of the meter, and full heat is the maximum.
func cops_for(amount: float) -> int:
	var heat_now := clampf(amount, 0.0, 1.0)
	var extra := int(floor(heat_now * float(COPS_MAX - COPS_MIN)))
	if heat_now >= 1.0:
		extra = COPS_MAX - COPS_MIN
	return COPS_MIN + extra


## A real hit on the player. Contact with a cop jumps the heat to 150%.
func note_hit(amount: float, on_cop: bool) -> void:
	if on_cop:
		var crossed := heat <= HEAT_CAP
		heat = maxf(heat, HEAT_RAMPAGE)
		if crossed and not _rampage:
			_rampage_in_s = RAMPAGE_AFTER_HIT_S
		_crash = true
		return
	if amount <= NOTICE_MPS:
		return
	# A hit never pulls the meter down. Heat already past the cap, from a cop,
	# stays there until the usual cool-down.
	heat = minf(heat + HIT_HEAT, maxf(heat, _heat_cap()))
	_crash = true


## A place other cars (or the player) just crashed. A later hit nearby joins it.
## `holder` is a car sitting there, or -1 when the scene is only a spot.
func open_scene(pos: Vector3, hard: bool, holder: int = -1) -> void:
	var flat := Vector2(pos.x, pos.z)
	for scene: Dictionary in scenes:
		var at: Vector3 = scene["pos"]
		if Vector2(at.x, at.z).distance_to(flat) > SCENE_JOIN_M:
			continue
		if hard:
			scene["hard"] = true
		if holder < 0:
			return
		var holders: Array = scene["holders"]
		if holders.has(holder):
			return
		holders.append(holder)
		if holders.size() >= 3:
			scene["hard"] = true
		scene["left"] = maxf(float(scene["left"]), SCENE_LIFE_S)
		return
	var holders: Array[int] = []
	if holder >= 0:
		holders.append(holder)
	scenes.append({
		"pos": pos,
		"left": SCENE_LIFE_S,
		"hard": hard,
		"holders": holders,
		"dropped": false,
	})


## Drops a scene whose cars have driven off, or whose time is up.
## `sitting` is instance id to whether that car is still pulled over.
func tick_scenes(delta: float, sitting: Dictionary) -> void:
	var keep: Array[Dictionary] = []
	for scene: Dictionary in scenes:
		scene["left"] = float(scene["left"]) - delta
		if float(scene["left"]) <= 0.0:
			continue
		var holders: Array = scene["holders"]
		if not holders.is_empty():
			var any := false
			for id: Variant in holders:
				if bool(sitting.get(id, false)):
					any = true
					break
			if not any:
				continue
		keep.append(scene)
	scenes = keep


func main_scene() -> Dictionary:
	if scenes.is_empty():
		return {}
	return scenes[scenes.size() - 1]


## One duty per cop, in the same order as `cop_at`. A scene the player has left
## keeps one cop. Full heat with the player still there sends every cop.
func duties(cop_at: Array[Vector3], player: Vector3) -> Array[int]:
	var out: Array[int] = []
	out.resize(cop_at.size())
	if cop_at.is_empty():
		return out
	var scene := main_scene()
	var live := not scene.is_empty()
	var scene_pos := Vector3.ZERO
	var hard := false
	if live:
		scene_pos = scene["pos"]
		hard = bool(scene["hard"])
	var away := Vector2(player.x - scene_pos.x, player.z - scene_pos.z).length()
	var fled := live and away > SIGHT_M
	var attend_n := 0
	var chase_n := 0
	if heat <= 0.0:
		if live:
			attend_n = 2 if hard else 1
	elif fled:
		attend_n = 1
		chase_n = 1
	elif heat >= HEAT_CAP:
		chase_n = cop_at.size()
	else:
		chase_n = 1
		if live and hard:
			attend_n = 1
	# Below the rampage line the chase is a pull-over. Past it, the hard chase.
	var chase := PURSUE if _rampage else STOP
	var used := {}
	_claim(out, used, _nearest_order(cop_at, scene_pos), ATTEND, attend_n)
	_claim(out, used, _nearest_order(cop_at, player), chase, chase_n)
	return out


## The nearest cop to a scene is still too far, and no cop has been moved in yet.
func wants_drop(distance: float) -> bool:
	var scene := main_scene()
	if scene.is_empty() or bool(scene.get("dropped", false)):
		return false
	return distance > FAR_M


func mark_dropped() -> void:
	var scene := main_scene()
	if scene.is_empty():
		return
	scene["dropped"] = true


## The fine for this much heat, in dollars. Up to a full meter it runs from FINE_MIN
## to FINE_MAX. At a full meter and past it, the fine is the full one times twice the heat.
static func fine_for(guilt: float) -> int:
	if guilt >= 1.0:
		return roundi(float(FINE_MAX) * guilt * 2.0)
	var t := clampf(guilt, 0.0, 1.0)
	return clampi(roundi(lerpf(float(FINE_MIN), float(FINE_MAX), t)), FINE_MIN, FINE_MAX)


## Empties the pull-over, clears the heat, and starts the grace.
func take_stop(money: int) -> Dictionary:
	if not _stop:
		return {}
	_stop = false
	var amount := fine_for(heat)
	var broke := money <= 0
	var paid := 0 if broke else mini(money, amount)
	var top := _top_mps
	var crashed := _crash
	heat = 0.0
	grace = GRACE_S
	_clear_want()
	_over_s = 0.0
	return {"paid": paid, "broke": broke, "amount": amount, "speed": top, "crash": crashed}


func hud_text(chasing: bool) -> String:
	if heat <= 0.0 and not chasing:
		return "Heat: 0%"
	var pct := roundi(clampf(heat, 0.0, HEAT_RAMPAGE) * 100.0)
	if chasing:
		return "Heat: %d%%  Police" % pct
	return "Heat: %d%%" % pct


func _heat_cap() -> float:
	return HEAT_RAMPAGE if _rampage else HEAT_CAP


func _clear_want() -> void:
	_crash = false
	_top_mps = 0.0
	_evade_s = 0.0
	_rampage = false
	_rampage_in_s = 0.0


func _claim(out: Array[int], used: Dictionary, order: Array[int], duty: int, count: int) -> void:
	var left := count
	for idx: int in order:
		if left <= 0:
			return
		if used.has(idx):
			continue
		out[idx] = duty
		used[idx] = true
		left -= 1


func _nearest_order(spots: Array[Vector3], target: Vector3) -> Array[int]:
	var left: Array[int] = []
	for i in spots.size():
		left.append(i)
	var order: Array[int] = []
	while not left.is_empty():
		var best := 0
		var best_d := spots[left[0]].distance_squared_to(target)
		for i in range(1, left.size()):
			var dist := spots[left[i]].distance_squared_to(target)
			if dist < best_d:
				best_d = dist
				best = i
		order.append(left[best])
		left.remove_at(best)
	return order
