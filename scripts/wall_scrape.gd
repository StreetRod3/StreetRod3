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
## A car shoving a dumpster: share of the speed between them that comes back out, and the car's
## weight, a typical one's (arcade_drive.gd).
const SHOVE_BOUNCE := 0.3
const CAR_KG := 1360.0


## What touching a barrier does this step: {"into", "velocity"}, or {} with no barrier touched.
## `before` is the velocity going into the move. When the hardest thing touched is a tree's trunk
## and the hit snaps it (tree_grove.gd), or the car touched only a dumpster and shoved it
## (dumpster.gd), the car goes on its way slower instead, and the answer also has "gave_way": the
## change of speed to charge as damage.
static func resolve(car: CharacterBody3D, before: Vector3, delta: float) -> Dictionary:
	var touched := false
	var into := 0.0
	var normal := Vector3.ZERO
	var tree: Node = null
	var pushed: Node = null
	var push_into := 0.0
	var push_normal := Vector3.ZERO
	var push_at := Vector3.ZERO
	for i in car.get_slide_collision_count():
		var col := car.get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Node and (collider as Node).has_meta(&"pushable"):
			var push_flat := Vector3(col.get_normal().x, 0.0, col.get_normal().z)
			if push_flat.length_squared() < 0.0001:
				continue
			push_flat = push_flat.normalized()
			if bool((collider as Node).call(&"blocked_toward", -push_flat)):
				# Pinned against something solid, it stops the car as a barrier would.
				touched = true
				var pinned := -before.dot(push_flat)
				if pinned > into or normal == Vector3.ZERO:
					into = maxf(pinned, 0.0)
					normal = push_flat
					tree = null
				continue
			var closing: Vector3 = before - ((collider as Node).call(&"planar_velocity") as Vector3)
			var push_here := -closing.dot(push_flat)
			if push_here > push_into:
				pushed = collider as Node
				push_into = push_here
				push_normal = push_flat
				push_at = col.get_position()
			continue
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
			tree = collider as Node if (collider as Node).has_meta(&"tree_index") else null
	var shove := 0.0
	if pushed != null:
		shove = _shove(pushed, push_normal, push_into, push_at)
		before += push_normal * shove
	if not touched:
		if pushed == null:
			return {}
		return {"into": 0.0, "velocity": Vector3(before.x, 0.0, before.z), "gave_way": shove}
	var planar := Vector3(before.x, 0.0, before.z)
	if tree != null and tree.get_parent() != null and tree.get_parent().has_method(&"try_break"):
		var cost := float(tree.get_parent().call(&"try_break", int(tree.get_meta(&"tree_index")), into, planar, car))
		if cost >= 0.0:
			var speed := planar.length()
			var on := planar * (maxf(speed - cost, 0.0) / speed) if speed > 0.01 else Vector3.ZERO
			return {"into": 0.0, "velocity": on, "gave_way": cost}
	var along := planar + normal * into
	var speed := maxf(along.length() - into * _FRICTION - _RUB_DRAG * delta, 0.0)
	var after := along.normalized() * speed + normal * into * BOUNCE
	return {"into": into, "velocity": after}


## A car going `into` m/s against `pushed`, a dumpster, along `normal` (pointing back at the car):
## the two share the knock by their masses, the dumpster taking it at `at`. Returns the speed the
## car loses, back along `normal`.
static func _shove(pushed: Node, normal: Vector3, into: float, at: Vector3) -> float:
	var mass := float(pushed.call(&"mass_kg"))
	var share := (1.0 + SHOVE_BOUNCE) / (CAR_KG + mass)
	pushed.call(&"push", -normal * (into * CAR_KG * share), at)
	return into * mass * share


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
