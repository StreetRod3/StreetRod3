extends CharacterBody3D

## A dumpster on casters (assets/locations/city/dumpster.glb, built by tools/dumpster_to_glb.py),
## standing by buildings in the city and placed as scenery on tracks. It is solid, but a car
## shoves it (wall_scrape.gd works out the shove from the two masses): it slides and spins away,
## slows on its casters, and bangs off walls, cars and other dumpsters. A knock throws its two
## lids open by how hard it was, each a little differently. A light one lifts them a crack and
## they drop shut; a hard one can flip them over the back, where they hang until the next.
##
## City traffic drives its lanes through anything, so a traffic car that runs into it shoves it
## the same way, and drives on.
##
## Nothing here needs ground to collide with: the dumpster stands at the height `ground` gives
## (a race track's `surface_height()`), or stays at the height it was put at with no ground.

const _MODEL := preload("res://assets/locations/city/dumpster.glb")
const _ShopSounds := preload("res://scripts/shop_sounds.gd")
const _WallScrape := preload("res://scripts/wall_scrape.gd")

## An empty 4-yard steel dumpster.
const MASS_KG := 300.0
## The bin's box: long along X, the front facing +Z.
const SIZE := Vector3(2.32, 1.55, 1.27)
## The box starts this far up, so it never touches the ground under it.
const _GROUND_GAP := 0.06
## Square of the radius of gyration of the bin's footprint about its middle.
const _GYRATION_SQ := (SIZE.x * SIZE.x + SIZE.z * SIZE.z) / 12.0
## Slowing on its casters, in m/s², and of its spin, in rad/s².
const _SLIDE_DECEL := 4.0
const _SPIN_DECEL := 6.0
## Share of a knock off its middle that goes into turning it; the rest of the car's push slides
## off along its side.
const _SPIN_SHARE := 0.5
## Share of the speed into a wall or a car that comes back out.
const _WALL_BOUNCE := 0.25
## Below these it is at rest.
const _REST_MPS := 0.05
const _REST_SPIN := 0.05
## How far it must be free to move to count as not pinned.
const _BLOCK_TEST := 0.05
## A knock this hard bangs.
const _BANG_MPS := 2.0

## A lid is a plank on its hinge: 3g / 2L for its 1.22 m. Shut, it slopes down to the front by
## `_LID_SLOPE`; flipped over it hangs against the back at `_LID_OPEN_STOP`.
const _LID_GRAVITY := 12.0
const _LID_SLOPE := deg_to_rad(10.0)
const _LID_OPEN_STOP := deg_to_rad(250.0)
const _LID_BOUNCE := 0.25
## How fast a knock throws a lid open, in rad/s for each m/s of the knock past `_LID_JOLT`, and
## how far apart the two lids can come out. The nudges of a car pushing it along stay under
## `_LID_JOLT` and leave the lids be. A lid needs about 5.3 rad/s to go over the top, so a knock
## of about 10 m/s (a car at 20 mph or so) can flip one over and a slower one only lifts them.
const _LID_JOLT := 1.0
## Knocks close together, a car leaning on it, count only for how much harder each is than the
## last, which fades at this many m/s each second.
const _JOLT_FADE := 8.0
const _LID_KICK := 0.6
const _LID_KICK_MIN := 0.6
const _LID_KICK_MAX := 1.25
const _LID_REST := 0.05

## Something with `surface_height(Vector3) -> float` for the ground under the dumpster.
var ground: Object = null

var _velocity := Vector3.ZERO
var _spin := 0.0
var _lids: Array[Node3D] = []
var _lid_open: Array[float] = [0.0, 0.0]
var _lid_rate: Array[float] = [0.0, 0.0]
var _bang: AudioStreamPlayer3D
var _last_jolt := 0.0
var _feel: Area3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1 | 2
	motion_mode = MOTION_MODE_FLOATING
	set_meta(&"pushable", true)
	var model := _MODEL.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	for lid_name: String in ["lid_left", "lid_right"]:
		var lid := model.get_node_or_null(lid_name) as Node3D
		if lid != null:
			_lids.append(lid)
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, SIZE.y - _GROUND_GAP, SIZE.z)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, _GROUND_GAP + box.size.y * 0.5, 0.0)
	add_child(shape)
	# Cars touching it, for the traffic.
	var feel_shape := CollisionShape3D.new()
	var feel_box := BoxShape3D.new()
	feel_box.size = box.size + Vector3(0.1, 0.0, 0.1)
	feel_shape.shape = feel_box
	feel_shape.position = shape.position
	_feel = Area3D.new()
	_feel.collision_layer = 0
	_feel.collision_mask = 2
	_feel.monitorable = false
	_feel.add_child(feel_shape)
	_feel.body_entered.connect(func(_body: Node3D) -> void: set_physics_process(true))
	add_child(_feel)
	_bang = AudioStreamPlayer3D.new()
	_bang.stream = _ShopSounds.stream("thud")
	_bang.position = Vector3(0.0, 0.8, 0.0)
	add_child(_bang)
	_stand()
	set_physics_process(false)


func mass_kg() -> float:
	return MASS_KG


## Whether something solid behind it stops it moving along `direction` at all, as when a car
## pins it to a wall: then it is as solid as the wall.
func blocked_toward(direction: Vector3) -> bool:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return false
	# Only the world counts: the car leaning on it is touching it already.
	var mask := collision_mask
	collision_mask = 1
	var stuck := test_move(global_transform, direction.normalized() * _BLOCK_TEST)
	collision_mask = mask
	return stuck


## How fast it is sliding over the ground.
func planar_velocity() -> Vector3:
	return _velocity


## A shove: `change` is the change of its velocity, given at `at` in the world, which also sets
## it spinning when off its middle.
func push(change: Vector3, at: Vector3) -> void:
	change.y = 0.0
	_velocity += change
	var arm := at - global_position
	arm.y = 0.0
	_spin += (arm.z * change.x - arm.x * change.z) / _GYRATION_SQ * _SPIN_SHARE
	_knock(change.length())
	set_physics_process(true)


## Each lid takes the knock its own way.
func _knock(speed: float) -> void:
	var jolt := maxf(speed - maxf(_LID_JOLT, _last_jolt), 0.0)
	_last_jolt = maxf(_last_jolt, speed)
	for i in _lids.size():
		_lid_rate[i] += jolt * _LID_KICK * randf_range(_LID_KICK_MIN, _LID_KICK_MAX)
	if jolt > 0.0 and speed >= _BANG_MPS and _bang.is_inside_tree():
		_bang.volume_db = linear_to_db(clampf(speed / 10.0, 0.25, 1.0))
		_bang.play()


func _physics_process(delta: float) -> void:
	_last_jolt = maxf(_last_jolt - _JOLT_FADE * delta, 0.0)
	for body in _feel.get_overlapping_bodies():
		_traffic_shove(body)
	var speed := _velocity.length()
	if speed > 0.0:
		_velocity *= maxf(speed - _SLIDE_DECEL * delta, 0.0) / speed
	_spin = move_toward(_spin, 0.0, _SPIN_DECEL * delta)
	if _velocity.length_squared() > 0.0:
		var hit := move_and_collide(_velocity * delta)
		if hit != null:
			_bounce(hit)
	rotation.y += _spin * delta
	_stand()
	var lids_still := true
	for i in _lids.size():
		if not _swing_lid(i, delta):
			lids_still = false
	if lids_still and _velocity.length() < _REST_MPS and absf(_spin) < _REST_SPIN:
		_velocity = Vector3.ZERO
		_spin = 0.0
		set_physics_process(false)


## A traffic car going into it: shoved by the two masses along the car's way, as wall_scrape.gd
## does for a race car, which this leaves to that (they have `hit_sawhorse()`).
func _traffic_shove(car: Node3D) -> void:
	if car.has_method(&"hit_sawhorse") or not car.has_method(&"planar_velocity") or not car.has_method(&"get_mass_kg"):
		return
	var car_velocity: Vector3 = car.call(&"planar_velocity")
	car_velocity.y = 0.0
	if car_velocity.length_squared() < 0.01:
		return
	var way := car_velocity.normalized()
	var closing := (car_velocity - _velocity).dot(way)
	if closing <= 0.0:
		return
	var car_kg := float(car.call(&"get_mass_kg"))
	var share := (1.0 + _WallScrape.SHOVE_BOUNCE) / (car_kg + MASS_KG)
	push(way * (closing * car_kg * share), global_position - way * (SIZE.z * 0.5))


## Off whatever it ran into: another dumpster takes the speed into it, as two equal weights do,
## and anything else, a wall or a car, sends it back.
func _bounce(hit: KinematicCollision3D) -> void:
	var normal := hit.get_normal()
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return
	normal = normal.normalized()
	var into := -_velocity.dot(normal)
	if into <= 0.0:
		return
	var other := hit.get_collider()
	if other is Node and (other as Node).has_method(&"push"):
		(other as Node).call(&"push", -normal * into, hit.get_position())
		_velocity += normal * into
	else:
		_velocity += normal * into * (1.0 + _WALL_BOUNCE)
		_spin *= 0.5
	_knock(into)


func _stand() -> void:
	if ground != null and ground.has_method(&"surface_height"):
		global_position.y = float(ground.call(&"surface_height", global_position))


## Gravity on lid `i` about its hinge, stopped by the rim shut and by the back flipped over.
## True when it is at rest.
func _swing_lid(i: int, delta: float) -> bool:
	var rise := _lid_open[i] - _LID_SLOPE
	_lid_rate[i] -= _LID_GRAVITY * cos(rise) * delta
	_lid_open[i] += _lid_rate[i] * delta
	var stopped := false
	if _lid_open[i] <= 0.0:
		_lid_open[i] = 0.0
		if _lid_rate[i] < 0.0:
			_lid_rate[i] = -_lid_rate[i] * _LID_BOUNCE
			stopped = true
	elif _lid_open[i] >= _LID_OPEN_STOP:
		_lid_open[i] = _LID_OPEN_STOP
		if _lid_rate[i] > 0.0:
			_lid_rate[i] = -_lid_rate[i] * _LID_BOUNCE
			stopped = true
	_lids[i].rotation.x = -_lid_open[i]
	if stopped and absf(_lid_rate[i]) < _LID_REST * 10.0:
		_lid_rate[i] = 0.0
	return absf(_lid_rate[i]) < _LID_REST and (_lid_open[i] <= 0.0 or _lid_open[i] >= _LID_OPEN_STOP)
