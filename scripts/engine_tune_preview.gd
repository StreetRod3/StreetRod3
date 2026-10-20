extends SubViewportContainer

const _EngineSound := preload("res://scripts/engine_sound.gd")

const _PULLEY_NAMES: Array[String] = ["crank_pulley", "upper_pulley", "alternator_pulley"]
const _TOOTH_PITCH := 0.09
const _TOOTH_DEPTH := 0.028
const _BELT_BODY := 0.016
const _SAMPLE_STEP := 0.022
## Crank turns per second on the sweet spot. Real idle is a blur, so this keeps the same ratios at a speed you can see.
const _PEAK_SPIN_RPS := 1.2

var _viewport: SubViewport
var _mount: Node3D
var _camera: Camera3D
var _engine: Node3D
var _belt: MeshInstance3D
var _model_path: String = ""
var _rpm: float = 600.0
var _phase: float = 0.0
var _length: float = 0.0
var _crank_radius: float = 0.22
var _belt_x0: float = 0.0
var _belt_x1: float = 0.0
var _focus_local: Vector3 = Vector3.ZERO
var _samples: PackedVector2Array = PackedVector2Array()
var _dists: PackedFloat32Array = PackedFloat32Array()
var _pulleys: Array[Dictionary] = []


func _ready() -> void:
	custom_minimum_size = Vector2(300, 340)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.transparent_bg = false
	_viewport.size = Vector2i(640, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	var world := Node3D.new()
	world.name = "World"
	_viewport.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.06, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.56, 0.5)
	env.ambient_light_energy = 0.85
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28.0, -48.0, 0.0)
	key.light_energy = 1.35
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 140.0, 0.0)
	fill.light_energy = 0.45
	world.add_child(fill)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 38.0
	_camera.near = 0.05
	world.add_child(_camera)
	_mount = Node3D.new()
	_mount.name = "Mount"
	world.add_child(_mount)


func set_engine(model_path: String) -> void:
	if model_path == _model_path and _engine != null:
		return
	_clear_engine()
	_model_path = model_path
	if model_path.is_empty() or _mount == null:
		return
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_warning("Engine model missing: %s" % model_path)
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		push_warning("Engine model could not be instanced: %s" % model_path)
		return
	_engine = inst
	_mount.add_child(_engine)
	_mount_pulleys()
	_engine.rotate_x(-PI * 0.5)
	_engine.force_update_transform()
	_frame_camera()


func set_tune(tune: int, sweet: int) -> void:
	_rpm = _EngineSound.tune_rpm(tune, sweet)


func _process(delta: float) -> void:
	if _belt == null or not is_visible_in_tree():
		return
	var peak := _EngineSound.tune_rpm(0, 0)
	var linear := 0.0
	if peak > 0.0:
		linear = _PEAK_SPIN_RPS * _rpm / peak * TAU * _crank_radius
	_phase = fposmod(_phase + linear * delta, _TOOTH_PITCH)
	for item in _pulleys:
		var pivot := item["pivot"] as Node3D
		var radius := float(item["radius"])
		if pivot == null or radius <= 0.001:
			continue
		pivot.rotate_x(linear / radius * delta)
	_rebuild_belt()


func _clear_engine() -> void:
	if _engine != null:
		_engine.free()
	_engine = null
	_belt = null
	_pulleys.clear()
	_samples = PackedVector2Array()
	_dists = PackedFloat32Array()
	_length = 0.0


func _mount_pulleys() -> void:
	var circles: Array[Dictionary] = []
	var shared_front := -INF
	var shared_back := INF
	var focus := Vector3.ZERO
	var counted := 0
	for pulley_name in _PULLEY_NAMES:
		var pulley := _engine.find_child(pulley_name, true, false) as MeshInstance3D
		if pulley == null or pulley.mesh == null:
			continue
		var box := pulley.mesh.get_aabb()
		if box.size.x > box.size.y or box.size.x > box.size.z:
			continue
		var center := box.get_center()
		var radius := maxf(box.size.y, box.size.z) * 0.5 + 0.008
		var pivot := Node3D.new()
		pivot.name = pulley_name + "Pivot"
		pulley.get_parent().add_child(pivot)
		pivot.position = center
		pulley.reparent(pivot, false)
		pulley.position = -center
		_add_timing_mark(pivot, radius)
		_pulleys.append({"pivot": pivot, "radius": radius})
		circles.append({"center": Vector2(center.y, center.z), "radius": radius})
		shared_front = maxf(shared_front, center.x - box.size.x * 0.5)
		shared_back = minf(shared_back, center.x + box.size.x * 0.5)
		focus += center
		counted += 1
		if pulley_name == "crank_pulley":
			_crank_radius = radius
	if counted == 0:
		return
	_focus_local = focus / float(counted)
	if shared_front < shared_back:
		_belt_x0 = shared_front - 0.02
		_belt_x1 = shared_front + 0.012
	_build_path(circles)
	_belt = MeshInstance3D.new()
	_belt.name = "TimingBelt"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.015, 0.015, 0.018)
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_belt.material_override = mat
	_engine.add_child(_belt)
	_rebuild_belt()


func _add_timing_mark(pivot: Node3D, radius: float) -> void:
	var mark := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.045, 0.028, radius * 0.42)
	mark.mesh = box
	mark.position = Vector3(0.0, 0.0, radius * 0.72)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.84, 0.48)
	mark.material_override = mat
	pivot.add_child(mark)


func _build_path(circles: Array[Dictionary]) -> void:
	_samples = PackedVector2Array()
	_dists = PackedFloat32Array()
	_length = 0.0
	if circles.size() < 2:
		return
	var centroid := Vector2.ZERO
	for circle in circles:
		centroid += circle["center"] as Vector2
	centroid /= float(circles.size())
	circles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := a["center"] as Vector2
		var cb := b["center"] as Vector2
		return (ca - centroid).angle() < (cb - centroid).angle()
	)
	var tangents: Array[Dictionary] = []
	for i in circles.size():
		var a: Dictionary = circles[i]
		var b: Dictionary = circles[(i + 1) % circles.size()]
		var tangent := _outer_tangent(a["center"] as Vector2, float(a["radius"]), b["center"] as Vector2, float(b["radius"]), centroid)
		if tangent.is_empty():
			return
		tangents.append(tangent)
	for i in circles.size():
		var circle: Dictionary = circles[i]
		var center := circle["center"] as Vector2
		var radius := float(circle["radius"])
		var incoming: Dictionary = tangents[(i + circles.size() - 1) % circles.size()]
		var outgoing: Dictionary = tangents[i]
		var a0 := ((incoming["to"] as Vector2) - center).angle()
		var a1 := ((outgoing["from"] as Vector2) - center).angle()
		var sweep := fposmod(a1 - a0, TAU)
		var arc_steps := maxi(int(ceil(sweep * radius / _SAMPLE_STEP)), 1)
		for step in arc_steps:
			var ang := a0 + sweep * float(step) / float(arc_steps)
			_push_sample(center + Vector2.from_angle(ang) * radius)
		var start := outgoing["from"] as Vector2
		var finish := outgoing["to"] as Vector2
		var line_steps := maxi(int(ceil(start.distance_to(finish) / _SAMPLE_STEP)), 1)
		for step in line_steps:
			_push_sample(start.lerp(finish, float(step) / float(line_steps)))
	if _samples.size() < 8:
		_samples = PackedVector2Array()
		return
	_dists.resize(_samples.size())
	var total := 0.0
	_dists[0] = 0.0
	for i in range(1, _samples.size()):
		total += _samples[i].distance_to(_samples[i - 1])
		_dists[i] = total
	total += _samples[0].distance_to(_samples[_samples.size() - 1])
	_length = total


func _outer_tangent(c0: Vector2, r0: float, c1: Vector2, r1: float, centroid: Vector2) -> Dictionary:
	var delta := c1 - c0
	var dist := delta.length()
	if dist <= absf(r0 - r1) + 0.0001:
		return {}
	var base := delta.angle()
	var phi := acos(clampf((r0 - r1) / dist, -1.0, 1.0))
	var best := Vector2.RIGHT
	var best_d := -1.0
	for side in [-1.0, 1.0]:
		var normal := Vector2.from_angle(base + side * phi)
		var mid := (c0 + normal * r0 + c1 + normal * r1) * 0.5
		var score := mid.distance_squared_to(centroid)
		if score > best_d:
			best_d = score
			best = normal
	return {
		"from": c0 + best * r0,
		"to": c1 + best * r1,
	}


func _push_sample(point: Vector2) -> void:
	if not _samples.is_empty() and _samples[_samples.size() - 1].distance_squared_to(point) < 0.000001:
		return
	_samples.append(point)


func _rebuild_belt() -> void:
	if _belt == null or _samples.size() < 8:
		return
	var count := _samples.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := PackedVector3Array()
	verts.resize(count * 4)
	for i in count:
		var prev := _samples[(i + count - 1) % count]
		var next := _samples[(i + 1) % count]
		var tangent := next - prev
		var inward := Vector2(-tangent.y, tangent.x)
		if inward.length_squared() < 0.000001:
			inward = Vector2.UP
		else:
			inward = inward.normalized()
		var tooth := fposmod(_dists[i] - _phase, _TOOTH_PITCH) < _TOOTH_PITCH * 0.45
		var depth := _TOOTH_DEPTH if tooth else 0.0
		var point := _samples[i]
		var outer := point - inward * _BELT_BODY
		var inner := point + inward * (0.004 + depth)
		var base := i * 4
		verts[base] = Vector3(_belt_x0, outer.x, outer.y)
		verts[base + 1] = Vector3(_belt_x1, outer.x, outer.y)
		verts[base + 2] = Vector3(_belt_x1, inner.x, inner.y)
		verts[base + 3] = Vector3(_belt_x0, inner.x, inner.y)
	for i in count:
		var a := i * 4
		var b := ((i + 1) % count) * 4
		_add_quad(st, verts, a, a + 1, b + 1, b)
		_add_quad(st, verts, a + 1, a + 2, b + 2, b + 1)
		_add_quad(st, verts, a + 2, a + 3, b + 3, b + 2)
		_add_quad(st, verts, a + 3, a, b, b + 3)
	st.generate_normals()
	_belt.mesh = st.commit()


func _add_quad(st: SurfaceTool, verts: PackedVector3Array, a: int, b: int, c: int, d: int) -> void:
	st.add_vertex(verts[a])
	st.add_vertex(verts[b])
	st.add_vertex(verts[c])
	st.add_vertex(verts[a])
	st.add_vertex(verts[c])
	st.add_vertex(verts[d])


func _frame_camera() -> void:
	if _engine == null or _camera == null:
		return
	var focus := _engine.to_global(_focus_local + Vector3(0.55, 0.0, -0.05))
	if _pulleys.is_empty():
		var box := _mesh_aabb(_engine)
		focus = box.get_center()
	var offset := _engine.global_transform.basis * Vector3(-1.35, 0.38, 0.32).normalized() * 4.8
	_camera.global_position = focus + offset
	_camera.look_at(focus, Vector3.UP)


func _mesh_aabb(node: Node) -> AABB:
	var box := AABB()
	var started := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		box = _transformed_aabb(mi.global_transform, mi.mesh.get_aabb())
		started = true
	for child in node.get_children():
		var child_box := _mesh_aabb(child)
		if child_box.size == Vector3.ZERO:
			continue
		if not started:
			box = child_box
			started = true
		else:
			box = box.merge(child_box)
	return box


func _transformed_aabb(xf: Transform3D, local: AABB) -> AABB:
	var out := AABB(xf * local.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		out = out.expand(xf * local.get_endpoint(i))
	return out
