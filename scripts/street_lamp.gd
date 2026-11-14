extends Node3D

## A street light on the cruise. A slow hit bends it and stops the car. A fast hit
## knocks it apart. Either way the harm stays well short of wrecking the car.

const _Sounds := preload("res://scripts/shop_sounds.gd")
const _BoxBatch := preload("res://scripts/box_batch.gd")

const _POLE := Color(0.3, 0.31, 0.33)
const _HEAD := Color(0.16, 0.16, 0.18)
const _GLOW := Color(1.0, 0.86, 0.5)
const _REACH := 1.2
## Under this speed the pole bends and the car stops. At this speed or more it breaks.
const _BEND_BELOW := 8.0
## Too slow to count as a hit, so brushing one at a crawl does nothing.
const _IGNORE_BELOW := 1.2
## Change of speed charged as damage. The free allowance is 1.5, and 14 totals a car.
const _BEND_HARM := 2.4
const _BREAK_HARM := 3.6
const _BREAK_SPEED_LOST := 2.2
const _BEND_ANGLE := 0.72

var _bend: Node3D
var _light: OmniLight3D
var _area: Area3D
var _spent := false
var _bits: Array[Dictionary] = []
var _shared: MultiMesh
var _slot := -1

## Pole, base, arm, head and lens in one mesh, shared by every lamp.
static var _mesh: ArrayMesh


## The whole lamp, standing at the origin with its arm out along +X.
static func lamp_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var batch := _BoxBatch.new()
	batch.set_look(_POLE, 0.42, 0.55)
	batch.add_post(0.08, 0.065, 4.7, 8, Transform3D.IDENTITY)
	batch.set_look(Color(0.22, 0.22, 0.24), 0.55, 0.35)
	batch.add_box(Vector3(0.36, 0.08, 0.36), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.04, 0.0)))
	batch.set_look(_POLE, 0.4, 0.5)
	batch.add_box(Vector3(_REACH, 0.055, 0.055), Transform3D(Basis.IDENTITY, Vector3(_REACH * 0.45, 4.62, 0.0)))
	batch.set_look(_HEAD, 0.45, 0.4)
	batch.add_box(Vector3(0.4, 0.08, 0.22), Transform3D(Basis.IDENTITY, Vector3(_REACH, 4.5, 0.0)))
	batch.set_look(_GLOW, 0.28, 0.0, _GLOW, 1.6)
	batch.add_box(Vector3(0.26, 0.035, 0.14), Transform3D(Basis.IDENTITY, Vector3(_REACH, 4.43, 0.0)))
	_mesh = batch.commit()
	return _mesh


## With `shared`, the lamp is drawn as instance `slot` of that MultiMesh, which must sit in
## this lamp's parent, until a hit gives it its own mesh. Otherwise it draws itself.
func setup(at: Vector3, toward: Vector3, shared: MultiMesh = null, slot: int = -1) -> void:
	position = at
	var face := Vector3(toward.x, 0.0, toward.z)
	if face.length_squared() > 0.001:
		face = face.normalized()
		var side := face.cross(Vector3.UP).normalized()
		basis = Basis(face, Vector3.UP, side)
	_bend = Node3D.new()
	_bend.name = "Bend"
	add_child(_bend)
	_shared = shared
	_slot = slot
	if _shared != null:
		_shared.set_instance_transform(_slot, transform)
	else:
		_draw_own()
	_light = OmniLight3D.new()
	_light.position = Vector3(_REACH, 4.35, 0.0)
	_light.light_color = _GLOW
	_light.light_energy = 0.28
	_light.omni_range = 8.0
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 26.0
	_light.distance_fade_length = 16.0
	_bend.add_child(_light)
	var shape := CylinderShape3D.new()
	shape.radius = 0.42
	shape.height = 4.4
	var hit := CollisionShape3D.new()
	hit.shape = shape
	hit.position = Vector3(0.0, 2.2, 0.0)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	_area.body_entered.connect(_on_body_entered)
	_area.add_child(hit)
	add_child(_area)
	set_physics_process(false)


func _on_body_entered(body: Node) -> void:
	if _spent or not body.has_method(&"hit_sawhorse"):
		return
	var speed := absf(float(body.get("forward_speed")))
	if speed < _IGNORE_BELOW:
		return
	_spent = true
	_area.set_deferred(&"monitoring", false)
	_take_over()
	var signed := float(body.get("forward_speed"))
	var car := body as Node3D
	var nose := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	var travel := nose * signf(signed if absf(signed) > 0.01 else 1.0)
	if speed < _BEND_BELOW:
		body.call(&"hit_sawhorse", _BEND_HARM, speed)
		_lean(travel)
	else:
		body.call(&"hit_sawhorse", _BREAK_HARM, _BREAK_SPEED_LOST)
		_shatter(travel * speed)
	_play()


func _lean(travel: Vector3) -> void:
	var flat := Vector3(travel.x, 0.0, travel.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(1.0, 0.0, 0.0)
	flat = flat.normalized()
	var axis := Vector3.UP.cross(flat)
	if axis.length_squared() < 0.0001:
		return
	var tw := create_tween()
	tw.tween_property(_bend, "basis", Basis(axis.normalized(), _BEND_ANGLE), 0.28)


func _shatter(push: Vector3) -> void:
	_light.visible = false
	_bend.visible = false
	_piece(Vector3(0.14, 2.3, 0.14), _POLE, Vector3(0.0, 1.15, 0.0), push)
	_piece(Vector3(0.12, 2.2, 0.12), _POLE, Vector3(0.0, 3.4, 0.0), push)
	_piece(Vector3(_REACH, 0.06, 0.06), _POLE, Vector3(_REACH * 0.5, 4.62, 0.0), push)
	_piece(Vector3(0.4, 0.1, 0.22), _HEAD, Vector3(_REACH, 4.5, 0.0), push)
	set_physics_process(true)


func _piece(size: Vector3, color: Color, local: Vector3, push: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.45
	mesh.material = mat
	var bit := MeshInstance3D.new()
	bit.mesh = mesh
	add_child(bit)
	bit.top_level = true
	bit.global_position = to_global(local)
	bit.global_rotation = global_rotation
	var flight := push * randf_range(0.15, 0.4)
	flight = flight.limit_length(12.0)
	flight += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 2.0
	flight.y = randf_range(1.5, 4.5)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	_bits.append({
		"node": bit,
		"velocity": flight,
		"spin": spin,
		"rate": randf_range(4.0, 11.0),
		"half": size.y * 0.5,
	})


func _physics_process(delta: float) -> void:
	var moving := false
	for bit: Dictionary in _bits:
		var node := bit["node"] as Node3D
		var velocity: Vector3 = bit["velocity"]
		if velocity == Vector3.ZERO:
			continue
		moving = true
		velocity.y -= 9.8 * delta
		node.global_position += velocity * delta
		node.rotate(bit["spin"] as Vector3, float(bit["rate"]) * delta)
		var floor_y := float(bit["half"])
		if node.global_position.y < floor_y:
			var parked := node.global_position
			parked.y = floor_y
			node.global_position = parked
			velocity.y = absf(velocity.y) * 0.3
			velocity.x *= 0.55
			velocity.z *= 0.55
			if velocity.length() < 0.8:
				velocity = Vector3.ZERO
		bit["velocity"] = velocity
	if not moving:
		set_physics_process(false)


func _play() -> void:
	var smash := AudioStreamPlayer3D.new()
	smash.stream = _Sounds.stream("thud")
	smash.finished.connect(smash.queue_free)
	add_child(smash)
	smash.play()


func _draw_own() -> void:
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	lamp.mesh = lamp_mesh()
	_bend.add_child(lamp)


## A hit lamp bends or breaks on its own, so it leaves the shared MultiMesh for a mesh of its own.
func _take_over() -> void:
	if _shared == null:
		return
	_shared.set_instance_transform(_slot, Transform3D(Basis.from_scale(Vector3.ZERO), transform.origin))
	_shared = null
	_draw_own()
