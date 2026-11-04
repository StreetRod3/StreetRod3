extends RefCounted

## Contact between the two race cars. Overlap is pushed apart and the hit is
## shared by weight, so a light car takes more of it than a heavy one. A hit
## away from a car's center also turns it. `resolve` reports how suddenly each
## car's speed changed, which is what damages it.

const CONTACT_MARGIN_M := 0.05
const SEPARATION_SLOP_M := 0.02
const MIN_OVERLAP_M := 0.01
const MIN_CLOSING_MPS := 0.25
const RESTITUTION := 0.2
## A car's resistance to turning is about its mass times this, in square meters.
const YAW_INERTIA_PER_KG := 1.67
## The fastest a hit can set a car turning, in rad/s.
const YAW_KICK_MAX := 1.6

## Returns how much each car's speed changed in m/s, (a, b). Zero when they are not touching.
func resolve(a: CharacterBody3D, b: CharacterBody3D) -> Vector2:
	if a == null or b == null:
		return Vector2.ZERO
	if not a.has_method(&"planar_velocity") or not a.has_method(&"apply_car_bump"):
		return Vector2.ZERO
	if not b.has_method(&"planar_velocity") or not b.has_method(&"apply_car_bump"):
		return Vector2.ZERO
	var box_a := _box(a)
	var box_b := _box(b)
	if box_a.is_empty() or box_b.is_empty():
		return Vector2.ZERO
	var hit := _overlap(box_a, box_b)
	if hit.is_empty():
		return Vector2.ZERO

	var normal := hit["normal"] as Vector2
	var depth := float(hit["depth"])
	var vel_a: Vector3 = a.planar_velocity()
	var vel_b: Vector3 = b.planar_velocity()
	var rel := Vector2(vel_b.x - vel_a.x, vel_b.z - vel_a.z).dot(normal)
	var offset_a := Vector3.ZERO
	var offset_b := Vector3.ZERO
	if depth > MIN_OVERLAP_M:
		var push := normal * (depth + SEPARATION_SLOP_M) * 0.5
		offset_a = Vector3(-push.x, 0.0, -push.y)
		offset_b = Vector3(push.x, 0.0, push.y)
	var new_a := vel_a
	var new_b := vel_b
	var change_a := 0.0
	var change_b := 0.0
	var kick_a := 0.0
	var kick_b := 0.0
	if rel < -MIN_CLOSING_MPS:
		var mass_a: float = a.get_mass_kg()
		var mass_b: float = b.get_mass_kg()
		var impulse := -(1.0 + RESTITUTION) * rel * mass_a * mass_b / (mass_a + mass_b)
		change_a = impulse / mass_a
		change_b = impulse / mass_b
		var push := Vector3(normal.x, 0.0, normal.y)
		new_a = vel_a - push * change_a
		new_b = vel_b + push * change_b
		var center_a: Vector2 = box_a["center"]
		var center_b: Vector2 = box_b["center"]
		var contact := (center_a + center_b) * 0.5
		kick_a = _yaw_kick(contact - center_a, -normal * impulse, mass_a)
		kick_b = _yaw_kick(contact - center_b, normal * impulse, mass_b)
	if offset_a.is_zero_approx() and offset_b.is_zero_approx() and new_a.is_equal_approx(vel_a):
		return Vector2.ZERO
	a.apply_car_bump(offset_a, new_a, kick_a)
	b.apply_car_bump(offset_b, new_b, kick_b)
	return Vector2(change_a, change_b)


## How fast a push at `arm` from the car's center sets it turning. x is world X and y is world Z.
func _yaw_kick(arm: Vector2, push: Vector2, mass: float) -> float:
	var torque := arm.y * push.x - arm.x * push.y
	return clampf(torque / (mass * YAW_INERTIA_PER_KG), -YAW_KICK_MAX, YAW_KICK_MAX)


func _box(body: CharacterBody3D) -> Dictionary:
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not shape_node.shape is BoxShape3D:
		return {}
	var box := shape_node.shape as BoxShape3D
	var xf := shape_node.global_transform
	var scale := xf.basis.get_scale()
	var axis_x := Vector2(xf.basis.x.x, xf.basis.x.z)
	var axis_z := Vector2(xf.basis.z.x, xf.basis.z.z)
	if axis_x.length_squared() < 0.0001 or axis_z.length_squared() < 0.0001:
		return {}
	return {
		"center": Vector2(xf.origin.x, xf.origin.z),
		"axis_x": axis_x.normalized(),
		"axis_z": axis_z.normalized(),
		"half_x": box.size.x * absf(scale.x) * 0.5,
		"half_z": box.size.z * absf(scale.z) * 0.5,
	}


func _overlap(a: Dictionary, b: Dictionary) -> Dictionary:
	var best_depth := INF
	var best_offset := -1.0
	var best_normal := Vector2.RIGHT
	var axes: Array[Vector2] = [
		a["axis_x"] as Vector2,
		a["axis_z"] as Vector2,
		b["axis_x"] as Vector2,
		b["axis_z"] as Vector2,
	]
	var delta: Vector2 = (b["center"] as Vector2) - (a["center"] as Vector2)
	for axis in axes:
		if axis.length_squared() < 0.0001:
			continue
		var n := axis.normalized()
		var dist := delta.dot(n)
		var depth := _radius(a, n) + _radius(b, n) - absf(dist)
		if depth < -CONTACT_MARGIN_M:
			return {}
		# Equal overlap prefers the axis the cars are actually offset along,
		# so a rear hit pushes forward instead of sideways.
		var offset := absf(dist)
		var closer := depth < best_depth - 0.0001
		var tied := absf(depth - best_depth) <= 0.0001 and offset > best_offset
		if closer or tied:
			best_depth = depth
			best_offset = offset
			best_normal = n if dist >= 0.0 else -n
	return {"normal": best_normal, "depth": best_depth}


func _radius(box: Dictionary, axis: Vector2) -> float:
	var along_x := float(box["half_x"]) * absf((box["axis_x"] as Vector2).dot(axis))
	var along_z := float(box["half_z"]) * absf((box["axis_z"] as Vector2).dot(axis))
	return along_x + along_z
