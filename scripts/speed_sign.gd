extends Node3D

## A speed-limit sign on the cruise. Any real hit knocks it apart. A slow hit still
## stops the car, and a fast one only checks it, the same as a street light.

const _Sounds := preload("res://scripts/shop_sounds.gd")
const _MODEL := preload("res://assets/locations/common/us_speed_limit_1970_blank.glb")

## The blank is Z-up. Turned onto its post, this is the empty panel.
const _NUMBER_Y := 1.919
## The post, from the model's own color.
const _POST := Color(0.412, 0.439, 0.455)
## The white face of the board.
const _BOARD := Color(0.93, 0.93, 0.9)
## Under this speed the car stops. The sign breaks apart either way.
const _BEND_BELOW := 8.0
## Too slow to count as a hit, so brushing one at a crawl does nothing.
const _IGNORE_BELOW := 1.2
const _BEND_HARM := 2.4
const _BREAK_HARM := 3.6
const _BREAK_SPEED_LOST := 2.2
## The post is a thin channel. The volume is as forgiving as a lamp pole.
const _HIT_RADIUS := 0.42
const _HIT_HEIGHT := 2.45

var _bend: Node3D
var _area: Area3D
var _spent := false
var _bits: Array[Dictionary] = []


## `at` is the foot of the post. `yaw` faces the sign's back along the road, so
## drivers who just turned in read the number.
func setup(at: Vector3, yaw: float, mph: int) -> void:
	position = at
	rotation.y = yaw
	_bend = Node3D.new()
	_bend.name = "Bend"
	add_child(_bend)
	var model := _MODEL.instantiate() as Node3D
	# The model lies along Z. This stands it on the post, face toward the cars.
	model.rotation.x = -PI * 0.5
	_bend.add_child(model)
	_light_face(model)
	_words(mph)
	var shape := CylinderShape3D.new()
	shape.radius = _HIT_RADIUS
	shape.height = _HIT_HEIGHT
	var hit := CollisionShape3D.new()
	hit.shape = shape
	hit.position = Vector3(0.0, _HIT_HEIGHT * 0.5, 0.0)
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
	var signed := float(body.get("forward_speed"))
	var car := body as Node3D
	var nose := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	var travel := nose * signf(signed if absf(signed) > 0.01 else 1.0)
	if speed < _BEND_BELOW:
		body.call(&"hit_sawhorse", _BEND_HARM, speed)
	else:
		body.call(&"hit_sawhorse", _BREAK_HARM, _BREAK_SPEED_LOST)
	_shatter(travel * speed)
	_play()


func _shatter(push: Vector3) -> void:
	_bend.visible = false
	_piece(Vector3(0.055, 1.125, 0.045), _POST, Vector3(0.0, 0.5625, 0.055), push)
	_piece(Vector3(0.055, 1.125, 0.045), _POST, Vector3(0.0, 1.6875, 0.055), push)
	_piece(Vector3(0.66, 0.762, 0.04), _BOARD, Vector3(0.0, 2.05, 0.0), push)
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


func _light_face(model: Node3D) -> void:
	var face := model.find_child("part_1", true, false) as MeshInstance3D
	if face == null or face.mesh == null:
		return
	var current := face.mesh.surface_get_material(0)
	if current is StandardMaterial3D and (current as StandardMaterial3D).emission_enabled:
		return
	if not current is StandardMaterial3D:
		return
	var board := (current as StandardMaterial3D).duplicate() as StandardMaterial3D
	board.emission_enabled = true
	board.emission = Color(0.96, 0.96, 0.94)
	board.emission_energy_multiplier = 0.15
	face.mesh.surface_set_material(0, board)


func _words(mph: int) -> void:
	var label := Label3D.new()
	label.text = str(mph)
	label.font_size = 64
	label.pixel_size = 0.005
	label.outline_size = 0
	label.modulate = Color.BLACK
	label.outline_modulate = Color.BLACK
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.rotation.y = PI
	label.position = Vector3(0.0, _NUMBER_Y, -0.02)
	_bend.add_child(label)
