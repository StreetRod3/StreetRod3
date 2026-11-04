extends RefCounted

## What a race has done to a car, from nothing to totaled. How bad a hit is goes by how
## suddenly the car's speed changed, so a heavy car takes less from a light one.

## A change of speed this small does no harm, in m/s.
const FREE_MPS := 1.5
## A single change of speed this large totals a car, in m/s.
const TOTAL_MPS := 14.0
## Share of the car's power gone just before it is totaled.
const POWER_LOSS := 0.55
## Damage where a car starts to smoke.
const SMOKE_AT := 0.5

## How fast one barrier contact is forgotten, in m/s per second. Pressing on through a
## contact is not a new hit.
const _BARRIER_FORGET_RATE := 30.0

var amount: float = 0.0
var _barrier_peak: float = 0.0
var _smoke: CPUParticles3D


## Adds a hit. True when it did any harm.
func take_hit(speed_change: float) -> bool:
	if speed_change <= FREE_MPS:
		return false
	amount = minf(amount + (speed_change - FREE_MPS) / (TOTAL_MPS - FREE_MPS), 1.0)
	return true


## The change of speed to charge for touching a barrier: only what is new in this contact.
func barrier_hit(speed_change: float) -> float:
	var fresh := maxf(speed_change, FREE_MPS) - maxf(_barrier_peak, FREE_MPS)
	_barrier_peak = maxf(_barrier_peak, speed_change)
	return FREE_MPS + fresh if fresh > 0.0 else 0.0


## Call every step.
func tick(delta: float) -> void:
	_barrier_peak = move_toward(_barrier_peak, 0.0, _BARRIER_FORGET_RATE * delta)


func is_totaled() -> bool:
	return amount >= 1.0


func power_left() -> float:
	return 1.0 - amount * POWER_LOSS


## Starts the smoke once the car is badly hurt. `body` is what it rises from.
func update_smoke(body: Node3D) -> void:
	if _smoke != null or amount < SMOKE_AT or body == null:
		return
	_smoke = CPUParticles3D.new()
	_smoke.name = "DamageSmoke"
	_smoke.amount = 24
	_smoke.lifetime = 1.4
	_smoke.direction = Vector3.UP
	_smoke.spread = 18.0
	_smoke.gravity = Vector3(0.0, 0.8, 0.0)
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.2
	_smoke.scale_amount_min = 0.5
	_smoke.scale_amount_max = 1.2
	var puff := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.14, 0.14, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff.material = mat
	_smoke.mesh = puff
	_smoke.position = Vector3(0.0, 0.8, 1.2)
	body.add_child(_smoke)
