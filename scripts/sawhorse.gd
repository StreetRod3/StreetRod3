extends Node3D

## Street Rod 2's sawhorse, a yellow and black bar on legs standing out from the road's edge. Street
## Rod 2 drives through it as if it were not there. Here a car smashes through it, which costs some
## damage and a little speed, and the broken bits stay on the road. Neither they nor the sawhorse
## stop a car.

const _StreetScenery := preload("res://scripts/street_scenery.gd")
const _ShopSounds := preload("res://scripts/shop_sounds.gd")

const REACH := 2.6
const _BAR_Y := 1.05
const _BAR_H := 0.26
const _BAR_THICK := 0.08
const _LEG_W := 0.1
const _LEG_INSET := 0.42
const _FOOT_L := 0.9
const _STRIPES := 5
const _HIT_DEPTH := 0.5
const _HIT_H := 1.6

const _YELLOW := Color(0.95, 0.8, 0.1, 1)
const _BLACK := Color(0.03, 0.03, 0.03, 1)
const _LEG := Color(0.45, 0.45, 0.45, 1)

## What it does to a car going `speed` m/s: the change of speed to charge as damage, on top of what
## does no harm at all, and the speed actually lost, which never comes to much.
const _HARM_PER_MPS := 0.03
const _SPEED_LOST_SHARE := 0.05
const _SPEED_LOST_MAX := 3.0

const _SPLINTERS := 7
## A bit leaves at this share of the car's speed, and no faster than the most here.
const _THROW_MIN := 0.2
const _THROW_MAX := 0.55
const _THROW_MOST_MPS := 16.0
const _THROW_SIDE_MPS := 3.5
const _THROW_UP_MIN := 2.0
const _THROW_UP_MAX := 6.0
const _SPIN_RAD := 12.0
const _GRAVITY := 9.8
const _BOUNCE := 0.35
const _BOUNCE_KEEP := 0.55
const _SLIDE_STOP_RATE := 3.0
const _REST_MPS := 1.2
const _LIE_ON_ROAD := 0.03

var _track: Node3D
var _standing: Node3D
var _area: Area3D
var _broken: bool = false
## Each flying bit: {node, velocity, spin, half}.
var _bits: Array[Dictionary] = []


## `at` is the middle of the bar on the ground, and the sawhorse lies across a road pointing `yaw`.
func setup(track: Node3D, at: Vector3, yaw: float) -> void:
	_track = track
	name = "Sawhorse"
	transform = Transform3D(Basis(Vector3.UP, yaw), at)
	_standing = Node3D.new()
	add_child(_standing)
	var dark := _StreetScenery._material(_BLACK)
	var leg := _StreetScenery._material(_LEG)
	_StreetScenery._add_box(_standing, Vector3(REACH, _BAR_H, _BAR_THICK), _StreetScenery._material(_YELLOW), Vector3(0.0, _BAR_Y, 0.0))
	for k in _STRIPES:
		var x := (float(k) + 0.5) / float(_STRIPES) * REACH - REACH * 0.5
		_StreetScenery._add_box(_standing, Vector3(0.24, _BAR_H + 0.01, _BAR_THICK + 0.01), dark, Vector3(x, _BAR_Y, 0.0))
	for end: float in [-1.0, 1.0]:
		_StreetScenery._add_box(_standing, Vector3(_LEG_W, _BAR_Y, _LEG_W), leg, Vector3(end * REACH * _LEG_INSET, _BAR_Y * 0.5, 0.0))
		_StreetScenery._add_box(_standing, Vector3(_LEG_W, _LEG_W, _FOOT_L), leg, Vector3(end * REACH * _LEG_INSET, _LEG_W * 0.5, 0.0))
	var shape := BoxShape3D.new()
	shape.size = Vector3(REACH, _HIT_H, _HIT_DEPTH)
	var hit := CollisionShape3D.new()
	hit.shape = shape
	hit.position = Vector3(0.0, _HIT_H * 0.5, 0.0)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	_area.add_child(hit)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)
	set_physics_process(false)


func _on_body_entered(body: Node3D) -> void:
	if _broken or not body.has_method(&"hit_sawhorse"):
		return
	_broken = true
	var speed := maxf(float(body.get("forward_speed")), 0.0)
	var yaw := body.rotation.y
	body.hit_sawhorse(_harm_for(speed), minf(speed * _SPEED_LOST_SHARE, _SPEED_LOST_MAX))
	_area.set_deferred(&"monitoring", false)
	_standing.queue_free()
	_play_smash()
	_scatter(Vector3(sin(yaw), 0.0, cos(yaw)) * speed)


static func _harm_for(speed: float) -> float:
	# take_hit() lets this much through for free, so the harm starts above it.
	return 1.5 + speed * _HARM_PER_MPS


func _play_smash() -> void:
	var smash := AudioStreamPlayer3D.new()
	smash.stream = _ShopSounds.stream("thud")
	smash.finished.connect(smash.queue_free)
	add_child(smash)
	smash.play()


## The bar in three lengths, the legs, the feet, and splinters. Every bit is long across its own X,
## so that it lies flat with only a turn about Y.
func _scatter(car_velocity: Vector3) -> void:
	var yellow := _StreetScenery._material(_YELLOW)
	var dark := _StreetScenery._material(_BLACK)
	var leg := _StreetScenery._material(_LEG)
	var third := REACH / 3.0
	for k in 3:
		var x := (float(k) - 1.0) * third
		var bit := _new_bit(Vector3(third * 0.92, _BAR_H, _BAR_THICK), yellow, Vector3(x, _BAR_Y, 0.0), car_velocity)
		var stripe := MeshInstance3D.new()
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(0.24, _BAR_H + 0.01, _BAR_THICK + 0.01)
		stripe_mesh.material = dark
		stripe.mesh = stripe_mesh
		bit.add_child(stripe)
	for end: float in [-1.0, 1.0]:
		var foot_x := end * REACH * _LEG_INSET
		_new_bit(Vector3(_BAR_Y, _LEG_W, _LEG_W), leg, Vector3(foot_x, _BAR_Y * 0.5, 0.0), car_velocity)
		_new_bit(Vector3(_FOOT_L, _LEG_W, _LEG_W), leg, Vector3(foot_x, _LEG_W * 0.5, 0.0), car_velocity)
	for k in _SPLINTERS:
		var length := randf_range(0.14, 0.4)
		var x := randf_range(-REACH * 0.5, REACH * 0.5)
		_new_bit(Vector3(length, 0.05, 0.05), yellow if k % 3 != 0 else dark, Vector3(x, _BAR_Y, 0.0), car_velocity)
	set_physics_process(true)


func _new_bit(size: Vector3, mat: Material, local: Vector3, car_velocity: Vector3) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var bit := MeshInstance3D.new()
	bit.mesh = mesh
	add_child(bit)
	bit.top_level = true
	bit.global_position = to_global(local)
	bit.global_rotation = Vector3(randf_range(-0.4, 0.4), global_rotation.y + randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))
	var flight := car_velocity * randf_range(_THROW_MIN, _THROW_MAX)
	flight = flight.limit_length(_THROW_MOST_MPS)
	flight += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * _THROW_SIDE_MPS
	flight.y = randf_range(_THROW_UP_MIN, _THROW_UP_MAX)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _SPIN_RAD
	_bits.append({"node": bit, "velocity": flight, "spin": spin, "half": size.y * 0.5})
	return bit


func _physics_process(delta: float) -> void:
	var flying: Array[Dictionary] = []
	for bit: Dictionary in _bits:
		if not _step_bit(bit, delta):
			flying.append(bit)
	_bits = flying
	if _bits.is_empty():
		set_physics_process(false)


## True when the bit has come to rest, where it stays.
func _step_bit(bit: Dictionary, delta: float) -> bool:
	var node: Node3D = bit["node"]
	var velocity: Vector3 = bit["velocity"]
	var spin: Vector3 = bit["spin"]
	velocity.y -= _GRAVITY * delta
	node.global_position += velocity * delta
	node.global_rotation += spin * delta
	var floor_y: float = float(_track.surface_height(node.global_position)) + float(bit["half"]) + _LIE_ON_ROAD
	if node.global_position.y <= floor_y:
		node.global_position.y = floor_y
		if absf(velocity.y) < _REST_MPS * 2.0:
			velocity.y = 0.0
			velocity = velocity.move_toward(Vector3.ZERO, _SLIDE_STOP_RATE * _GRAVITY * delta)
			spin = Vector3.ZERO
			node.global_rotation = Vector3(0.0, node.global_rotation.y, 0.0)
			if velocity.length() < _REST_MPS:
				return true
		else:
			velocity.y = -velocity.y * _BOUNCE
			velocity.x *= _BOUNCE_KEEP
			velocity.z *= _BOUNCE_KEEP
			spin *= _BOUNCE_KEEP
	bit["velocity"] = velocity
	bit["spin"] = spin
	return false
