extends MeshInstance3D

## Dark strips on the ground and smoke in the air while a tire is past its grip. Each
## wheel keeps its own strip, and a gap or a teleport starts a new one.

const _VehicleDynamics := preload("res://scripts/vehicle_dynamics.gd")

const MARK_Y := 0.035
const MIN_STEP := 0.15
const MAX_STEP := 2.4
const USE_MARK := 0.9
const MAX_VERTS := 9000
## How long a patch of rubber a tire spinning on the spot lays down, in meters, and how
## many physics ticks apart it adds to it.
const BURN_PATCH_M := 0.9
const BURN_TICKS := 18
const BURN_ALPHA := 0.3
const SMOKE_PER_WHEEL := 20
const SMOKE_LIFETIME_S := 1.3
const SMOKE_RISE_M := 0.2
const SMOKE_PUFF_MIN := 0.7
const SMOKE_PUFF_MAX := 1.6
## How big a puff starts as a share of its full size, before it spreads out.
const SMOKE_PUFF_START := 0.35
## How much bigger the smoke is from a tire spinning on the spot.
const BURN_SMOKE := 1.8

var _verts := PackedVector3Array()
var _colors := PackedColorArray()
var _points: Array[Vector3] = []
var _drawing: Array[bool] = []
var _dirty := false
## How much each wheel should smoke this tick, 0 to 1, and where.
var _smoke_wanted: Array[float] = []
var _smoke_at: Array[Vector3] = []
var _smokes: Array[CPUParticles3D] = []
var _smoke_mesh: QuadMesh = null
var _burn_ticks: Array[int] = []


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	material_override = mat


## Runs after the car has driven, so it sees what every wheel asked for this tick.
func _physics_process(_delta: float) -> void:
	for i in _smoke_wanted.size():
		var wanted := _smoke_wanted[i]
		if wanted > 0.0:
			var smoke := _smoke_for(i)
			smoke.global_position = _smoke_at[i]
			smoke.scale_amount_min = SMOKE_PUFF_MIN * wanted
			smoke.scale_amount_max = SMOKE_PUFF_MAX * wanted
			smoke.emitting = true
		elif i < _smokes.size() and _smokes[i] != null:
			_smokes[i].emitting = false
		_smoke_wanted[i] = 0.0


## One sample per wheel of a vehicle_dynamics car, in wheel order.
## `track` supplies the road height. Without one, the marks stay on flat ground.
func record(wheels: Array, body: Transform3D, track: Object = null) -> void:
	for i in wheels.size():
		var wheel: _VehicleDynamics.Wheel = wheels[i]
		var contact := Vector2(wheel.forward_velocity, wheel.lateral_velocity).length()
		var world: Vector3 = body * wheel.local_position
		var ground_y := wheel.road_y
		if track != null and track.has_method(&"surface_height"):
			ground_y = float(track.surface_height(world))
		stamp(
			i,
			world,
			ground_y,
			wheel.grip_utilization,
			wheel.slip_angle,
			wheel.long_slip,
			contact,
			wheel.surface_blend,
			wheel.peak_curve
		)
	flush()


## The same for a car with no tire simulation, from what it can say about each axle.
func record_axles(
	wheels: Array,
	body: Transform3D,
	track: Object,
	speed: float,
	front_use: float,
	front_slip: float,
	front_long: float,
	rear_use: float,
	rear_slip: float,
	rear_long: float
) -> void:
	for i in wheels.size():
		var wheel: _VehicleDynamics.Wheel = wheels[i]
		var world: Vector3 = body * wheel.local_position
		var ground_y := wheel.road_y
		if track != null and track.has_method(&"surface_height"):
			ground_y = float(track.surface_height(world))
		var long_slip := front_long if wheel.front else rear_long
		# A tire spinning or locked is moving over the road even if the car is barely moving.
		var contact := maxf(speed, 3.0) if absf(long_slip) > 1.0 else speed
		stamp(
			i,
			world,
			ground_y,
			front_use if wheel.front else rear_use,
			front_slip if wheel.front else rear_slip,
			long_slip,
			contact,
			wheel.surface_blend,
			true
		)
	flush()


## A driven tire spinning on the spot: smoke, and rubber building up under it. `strength` is 0 to 1.
func burn(index: int, world: Vector3, ground_y: float, forward: Vector3, strength: float) -> void:
	_ensure(index)
	var point := Vector3(world.x, ground_y + MARK_Y, world.z)
	_points[index] = point
	_drawing[index] = false
	_smoke_wanted[index] = strength * BURN_SMOKE
	_smoke_at[index] = point + Vector3.UP * SMOKE_RISE_M
	_burn_ticks[index] += 1
	if _burn_ticks[index] >= BURN_TICKS:
		_burn_ticks[index] = 0
		var half := forward * BURN_PATCH_M * 0.5
		_add_mark(point - half, point + half, forward, 0.17, BURN_ALPHA, 0.0)
		_dirty = true


func end_strips() -> void:
	for i in _drawing.size():
		_drawing[i] = false
		_smoke_wanted[i] = 0.0


func stamp(
	index: int,
	world: Vector3,
	ground_y: float,
	utilization: float,
	slip_angle: float,
	long_slip: float,
	contact_speed: float,
	surface_blend: float,
	peak_curve: bool = false
) -> void:
	_ensure(index)
	var sliding := false
	if peak_curve:
		var past_peak := absf(slip_angle) > 0.14 or absf(long_slip) > 1.05
		sliding = (
			contact_speed > 2.5
			and (utilization >= USE_MARK or (past_peak and utilization >= 0.55))
			and (absf(slip_angle) > 0.08 or absf(long_slip) > 0.9)
		)
	else:
		sliding = (
			utilization >= USE_MARK
			and contact_speed > 2.5
			and (absf(slip_angle) > 0.1 or absf(long_slip) > 1.05)
		)
	var point := Vector3(world.x, ground_y + MARK_Y, world.z)
	if not sliding:
		_drawing[index] = false
		_points[index] = point
		return
	_smoke_wanted[index] = lerpf(0.5, 1.0, smoothstep(USE_MARK, 1.0, utilization)) * (1.0 - clampf(surface_blend, 0.0, 1.0) * 0.5)
	_smoke_at[index] = point + Vector3.UP * SMOKE_RISE_M
	if _drawing[index]:
		var prev := _points[index]
		var delta := Vector3(point.x - prev.x, 0.0, point.z - prev.z)
		var dist := delta.length()
		if dist >= MIN_STEP and dist <= MAX_STEP:
			_add_quad(prev, point, delta / dist, utilization, surface_blend)
			_points[index] = point
			_dirty = true
		elif dist > MAX_STEP:
			_points[index] = point
	else:
		_points[index] = point
	_drawing[index] = true


func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	_trim()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _colors
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = built


func _ensure(index: int) -> void:
	while _points.size() <= index:
		_points.append(Vector3.ZERO)
		_drawing.append(false)
		_smoke_wanted.append(0.0)
		_smoke_at.append(Vector3.ZERO)
		_burn_ticks.append(0)


func _add_quad(a: Vector3, b: Vector3, forward: Vector3, utilization: float, surface_blend: float) -> void:
	var half := lerpf(0.09, 0.18, smoothstep(USE_MARK, 1.0, utilization))
	var alpha := lerpf(0.45, 0.9, smoothstep(USE_MARK, 1.0, utilization))
	_add_mark(a, b, forward, half, alpha, surface_blend)


func _add_mark(a: Vector3, b: Vector3, forward: Vector3, half: float, alpha: float, surface_blend: float) -> void:
	var side := Vector3(-forward.z, 0.0, forward.x) * half
	var color := Color(0.015, 0.015, 0.015, alpha).lerp(Color(0.1, 0.11, 0.06, alpha), clampf(surface_blend, 0.0, 1.0))
	var a_left := a + side
	var a_right := a - side
	var b_left := b + side
	var b_right := b - side
	_push(a_left, color)
	_push(b_left, color)
	_push(b_right, color)
	_push(a_left, color)
	_push(b_right, color)
	_push(a_right, color)


func _smoke_for(index: int) -> CPUParticles3D:
	while _smokes.size() <= index:
		_smokes.append(null)
	if _smokes[index] == null:
		var smoke := CPUParticles3D.new()
		smoke.name = "TireSmoke%d" % index
		smoke.amount = SMOKE_PER_WHEEL
		smoke.lifetime = SMOKE_LIFETIME_S
		smoke.direction = Vector3.UP
		smoke.spread = 35.0
		smoke.gravity = Vector3(0.0, 0.7, 0.0)
		smoke.initial_velocity_min = 0.4
		smoke.initial_velocity_max = 1.3
		var fade := Gradient.new()
		fade.set_color(0, Color(0.9, 0.9, 0.9, 0.42))
		fade.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
		smoke.color_ramp = fade
		var growth := Curve.new()
		growth.add_point(Vector2(0.0, SMOKE_PUFF_START))
		growth.add_point(Vector2(1.0, 1.0))
		smoke.scale_amount_curve = growth
		smoke.mesh = _smoke_puff()
		add_child(smoke)
		_smokes[index] = smoke
	return _smokes[index]


func _smoke_puff() -> QuadMesh:
	if _smoke_mesh == null:
		_smoke_mesh = QuadMesh.new()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		# Without this a particle's size is ignored. One not in use has none, and it would be drawn
		# full size and black at the emitter.
		mat.billboard_keep_scale = true
		mat.albedo_texture = _soft_puff_texture()
		_smoke_mesh.material = mat
	return _smoke_mesh


## White in the middle, fading to nothing at the edge, so a puff has no corners.
func _soft_puff_texture() -> GradientTexture2D:
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	falloff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = falloff
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


func _push(point: Vector3, color: Color) -> void:
	_verts.push_back(point)
	_colors.push_back(color)


func _trim() -> void:
	var extra := _verts.size() - MAX_VERTS
	if extra <= 0:
		return
	extra -= extra % 6
	if extra <= 0:
		return
	_verts = _verts.slice(extra)
	_colors = _colors.slice(extra)
