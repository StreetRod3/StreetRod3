extends RefCounted

## A car touching a track barrier. Only the speed going into the barrier is lost, plus some
## scraping along it, so a graze costs a little and a square hit costs nearly everything.

## Share of the speed into the barrier that comes back out.
const BOUNCE := 0.15
## Speed along the barrier lost per m/s going into it.
const _FRICTION := 0.3
## Slowing while rubbing along a barrier, in m/s².
const _RUB_DRAG := 5.0
## How hard a touching car is turned back along the road. Heading error to rad/s, and the most.
const _TURN_GAIN := 3.5
const _TURN_MAX := 1.4
const _ARCADE_MIN_MPS := 3.0


## What touching a barrier does this step: {"into", "velocity"}, or {} with no barrier touched.
## `before` is the velocity going into the move.
static func resolve(car: CharacterBody3D, before: Vector3, delta: float) -> Dictionary:
	var touched := false
	var into := 0.0
	var normal := Vector3.ZERO
	for i in car.get_slide_collision_count():
		var col := car.get_slide_collision(i)
		var collider := col.get_collider()
		if not (collider is Node and (collider as Node).has_meta(&"track_obstacle")):
			continue
		touched = true
		var flat := Vector3(col.get_normal().x, 0.0, col.get_normal().z)
		if flat.length_squared() < 0.0001:
			continue
		flat = flat.normalized()
		var here := -before.dot(flat)
		if here > into or normal == Vector3.ZERO:
			into = maxf(here, 0.0)
			normal = flat
	if not touched:
		return {}
	var planar := Vector3(before.x, 0.0, before.z)
	var along := planar + normal * into
	var speed := maxf(along.length() - into * _FRICTION - _RUB_DRAG * delta, 0.0)
	var after := along.normalized() * speed + normal * into * BOUNCE
	return {"into": into, "velocity": after}


## How far the arcade drive's nose has to swing to where the car is now going, since that
## drive goes where its nose points. Below walking pace it comes back along the road instead.
static func arcade_swing(track: Node, car: Node3D, yaw: float, after: Vector3) -> float:
	if after.length() >= _ARCADE_MIN_MPS:
		return wrapf(atan2(after.x, after.z) - yaw, -PI, PI)
	if track != null and track.has_method(&"closest_sample"):
		return wrapf(float(track.closest_sample(car.global_position).get("yaw", yaw)) - yaw, -PI, PI)
	return 0.0


## Turn rate that brings a touching car back along the road, so it cannot sit with its nose
## against a barrier. Zero with no track.
static func turn_rate(track: Node, car: Node3D, yaw: float) -> float:
	if track == null or not track.has_method(&"closest_sample"):
		return 0.0
	var road_yaw := float(track.closest_sample(car.global_position).get("yaw", yaw))
	return clampf(wrapf(road_yaw - yaw, -PI, PI) * _TURN_GAIN, -_TURN_MAX, _TURN_MAX)
