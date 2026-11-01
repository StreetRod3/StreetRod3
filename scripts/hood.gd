extends Node3D

## Under the hood, looking down into the engine bay from in front of the car. The engine
## is built up in layers as in Street Rod 2: the engine on its mounts, the cylinder heads
## on the engine, the intake on the heads, the carburetors and the distributor in the intake, the air cleaner over the
## carburetors, and the plug wires from the distributor cap to the plugs. Each part is
## held by bolts: click a bolt hole to thread a bolt in, click the bolt again to tighten
## it, and click a tight bolt to back it out. With all of a part's bolts out and nothing
## on top of it, it lifts off into spare parts. Parts puts a spare into an empty spot,
## its bolts in but loose. Wires pulls the plug wires or puts them back. Tune opens the
## timing light when the engine will run.

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _EngineAssembly := preload("res://scripts/engine_assembly.gd")

## Crank height in meters off the shop floor.
const CRANK_Y := 0.55
const FOCUS := Vector3(0.0, 0.82, 0.0)
## How far a bolt stands proud of its hole for each turn it still needs, in engine units.
const BOLT_PITCH := 0.06
const BOLT_SPIN := TAU * 0.6
## Hole hot spots, in meters.
const SPOT_RADIUS := 0.035
## A bolt under the pointer takes the click over its part's box this far behind the box's
## face, in meters, since the box takes in the bolt's own hole.
const BOLT_PICK_DEPTH := 0.1
const _LAYER_PARTS := 1
const _LAYER_BOLTS := 2
## A part lifts this far off, in engine units, before it is put on the shelf.
const LIFT_PART := 4.0
const LIFT_ENGINE := 10.0
## Magnetic tray on the left fender where bolts that are out wait.
const TRAY := Vector3(-0.42, 0.985, 0.66)
const TRAY_STEP := 0.055

const T_TURN := 0.3
const T_BOLT_OUT := 0.45
const T_BOLT_IN := 0.5
const T_LIFT := 0.9
const T_LIFT_ENGINE := 1.8
const T_PAUSE := 0.15

const CAM_YAW_MIN := -2.8
const CAM_YAW_MAX := 0.3
const CAM_PITCH_MIN := -1.35
const CAM_PITCH_MAX := -0.12
const CAM_DISTANCE_MIN := 0.5
const CAM_DISTANCE_MAX := 2.6
const ZOOM_STEP := 0.1

## Hood parts from the top down: the order they come off in.
const TOP_DOWN: Array[String] = ["air_cleaner", "carb_3", "carb_2", "carb", "distributor", "intake", "heads", "engine"]
const PART_NAMES := {
	"engine": "Engine",
	"heads": "Cylinder heads",
	"intake": "Intake manifold",
	"carb": "Carburetor",
	"carb_2": "Second carburetor",
	"carb_3": "Third carburetor",
	"distributor": "Distributor",
	"air_cleaner": "Air cleaner",
	"wires": "Plug wires",
}
const BOLT_NAMES := {
	"engine": ["Right engine mount bolt", "Left engine mount bolt"],
	"heads": ["Right head, front bolt", "Right head, rear bolt", "Left head, front bolt", "Left head, rear bolt"],
	"intake": ["Front intake bolt", "Rear intake bolt"],
	"carb": ["Front carburetor nut", "Rear carburetor nut"],
	"carb_2": ["Front carburetor nut", "Rear carburetor nut"],
	"carb_3": ["Front carburetor nut", "Rear carburetor nut"],
	"distributor": ["Distributor hold-down bolt"],
	"air_cleaner": ["Air cleaner wing nut"],
}

const _CREAM := Color(0.95, 0.9, 0.78, 1)
const _RATE := 22050

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $UI/Root

var _engine: Node3D
## Per part key: bolt nodes, their materials, where they go, and whether each is backing out.
var _bolts: Dictionary = {}
var _bolt_mats: Dictionary = {}
var _spots: Dictionary = {}
var _loosening: Dictionary = {}
## Click targets: the holes, and each part's bounds (a list of boxes per part).
var _hole_bodies: Dictionary = {}
var _part_bodies: Dictionary = {}
## What the mouse is over: [key, bolt index], [key, -1] for a part, or [].
var _hover: Array = []
var _busy: bool = false
var _orbiting: bool = false
var _yaw: float = -0.95
var _pitch: float = -0.75
var _distance: float = 1.55
var _nav = _MenuNav.new()

var _engine_label: Label
var _parts_label: Label
var _hint: Label
var _tooltip: Label
var _parts_btn: Button
var _wires_btn: Button
var _tune_btn: Button
var _done_btn: Button
var _picker: Control
var _picker_rows: VBoxContainer
var _picker_note: Label
var _picker_close: Button

var _sfx_ratchet: AudioStreamPlayer
var _sfx_snug: AudioStreamPlayer
var _sfx_clunk: AudioStreamPlayer
var _sfx_tink: AudioStreamPlayer
var _sfx_snap: AudioStreamPlayer


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	GameState.update_music()
	if not GameState.has_active_car():
		get_tree().change_scene_to_file.call_deferred(GameState.SCENE_GARAGE)
		return
	_build_world()
	_build_bay()
	_engine = _EngineAssembly.new()
	_engine.name = "Engine"
	_engine.position = Vector3(0.0, CRANK_Y - _EngineAssembly.CRANK_Z * _EngineAssembly.ENGINE_SCALE, 0.0)
	add_child(_engine)
	_engine.build()
	for key in TOP_DOWN:
		_build_bolts(key)
	_build_sounds()
	_build_ui()
	_update_camera()
	_refresh_ui()
	# Bodies are placed once the meshes have their world transforms.
	_refresh_part_bodies.call_deferred()


func _process(_delta: float) -> void:
	if _picker != null:
		_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if _picker == null:
		return
	if event is InputEventKey:
		_handle_key(event as InputEventKey)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_distance = clampf(_distance + dir * ZOOM_STEP, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
			_update_camera()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _picker.visible:
			var target := _target_at(mb.position)
			if not target.is_empty():
				get_viewport().set_input_as_handled()
				_on_target(target)
		return
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if mg.factor > 0.0001:
			_distance = clampf(_distance / mg.factor, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
			_update_camera()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_yaw = clampf(_yaw - mm.relative.x * 0.005, CAM_YAW_MIN, CAM_YAW_MAX)
		_pitch = clampf(_pitch - mm.relative.y * 0.005, CAM_PITCH_MIN, CAM_PITCH_MAX)
		_update_camera()
		get_viewport().set_input_as_handled()


func _handle_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	if _nav.handle_event(self, key):
		get_viewport().set_input_as_handled()
		return
	var handled := true
	match key.keycode:
		KEY_ESCAPE:
			if _picker.visible:
				_close_picker()
			else:
				# Mark the key first. Leaving drops this scene, and the viewport is gone after that.
				get_viewport().set_input_as_handled()
				_on_done_pressed()
				return
		KEY_P:
			if not _picker.visible:
				_on_parts_pressed()
		KEY_W:
			if not _picker.visible:
				_on_wires_pressed()
		KEY_T:
			if not _picker.visible:
				get_viewport().set_input_as_handled()
				_on_tune_pressed()
				return
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _update_camera() -> void:
	var dir := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3.BACK
	_camera.global_position = FOCUS + dir * _distance
	_camera.look_at(FOCUS, Vector3.UP)


# --- Bolts -------------------------------------------------------------------------


func _on_bolt(key: String, index: int) -> void:
	if _busy or not GameState.is_hood_part_fitted(key):
		return
	var bolts := GameState.hood_bolts(key)
	if index < 0 or index >= bolts.size():
		return
	var turns: int = bolts[index]
	var loosening: Array = _loosening[key]
	var next := GameState.next_bolt_turns(turns, loosening[index])
	loosening[index] = next < turns and next > 0
	GameState.set_hood_bolt(key, index, next)
	_busy = true
	_refresh_ui()
	if turns == 0:
		await _thread_in(key, index)
	elif next > 0:
		await _turn_bolt(key, index, turns, next)
	else:
		await _back_out(key, index)
		if is_instance_valid(self):
			await _settle()
	if not is_instance_valid(self):
		return
	_busy = false
	_refresh_ui()


func _turn_bolt(key: String, index: int, from: int, to: int) -> void:
	_play(_sfx_snug if to == GameState.GEARBOX_BOLT_TIGHT else _sfx_ratchet)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_set_bolt_turns.bind(key, index), float(from), float(to), T_TURN)
	await tw.finished


## Backs the last turn out, then sets the bolt in the tray on the fender.
func _back_out(key: String, index: int) -> void:
	_play(_sfx_ratchet)
	var tw := create_tween()
	tw.tween_method(_set_bolt_turns.bind(key, index), 1.0, -1.5, T_TURN * 1.4)
	await tw.finished
	if not is_instance_valid(self):
		return
	var move := create_tween()
	move.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	move.tween_property(_bolts[key][index], "global_transform", _tray_xform(key, index), T_BOLT_OUT)
	await move.finished
	_play(_sfx_tink)


## Takes the bolt out of the tray and runs it into its hole by hand.
func _thread_in(key: String, index: int) -> void:
	var move := create_tween()
	move.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	move.tween_property(_bolts[key][index], "global_transform", _bolt_xform(key, index, -1.5), T_BOLT_IN)
	await move.finished
	if not is_instance_valid(self):
		return
	_play(_sfx_ratchet)
	var tw := create_tween()
	tw.tween_method(_set_bolt_turns.bind(key, index), -1.5, float(GameState.BOLT_THREADED), T_TURN * 1.8)
	await tw.finished


func _set_bolt_turns(turns: float, key: String, index: int) -> void:
	(_bolts[key][index] as Node3D).global_transform = _bolt_xform(key, index, turns)


## Where a bolt sits with `turns` in. Below zero it is backing out of the hole.
func _bolt_xform(key: String, index: int, turns: float) -> Transform3D:
	var spot: Transform3D = _spots[key][index]
	var proud := (float(GameState.GEARBOX_BOLT_TIGHT) - turns) * BOLT_PITCH
	var local := Transform3D(spot.basis * Basis(Vector3.BACK, turns * BOLT_SPIN), spot.origin + spot.basis.z * proud)
	return _engine.frame.global_transform * local


## A bolt lying in the tray, its own place for each bolt of each part.
func _tray_xform(key: String, index: int) -> Transform3D:
	var slot := 0
	for k in TOP_DOWN:
		if k == key:
			break
		slot += GameState.hood_bolt_count(k)
	slot += index
	var basis := Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)
	return Transform3D(basis.scaled(Vector3.ONE * _EngineAssembly.ENGINE_SCALE), TRAY + Vector3(TRAY_STEP * float(slot), 0.012, 0.0))


## Makes the bolts for a part as the car has it, in or out of their holes.
func _build_bolts(key: String) -> void:
	for bolt in _bolts.get(key, []):
		(bolt as Node3D).queue_free()
	for body in _hole_bodies.get(key, []):
		(body as Node3D).queue_free()
	_bolts.erase(key)
	_bolt_mats.erase(key)
	_spots.erase(key)
	_hole_bodies.erase(key)
	if not GameState.is_hood_part_fitted(key):
		return
	var spots: Array[Transform3D] = _engine.bolt_spots(key)
	var bolts: Array[Node3D] = []
	var mats: Array[StandardMaterial3D] = []
	var bodies: Array[Node3D] = []
	var loosening: Array[bool] = []
	var turns := GameState.hood_bolts(key)
	_spots[key] = spots
	for i in spots.size():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.78, 0.66, 0.3)
		mat.metallic = 0.8
		mat.roughness = 0.3
		mat.emission = Color(0.95, 0.62, 0.22)
		mat.emission_energy_multiplier = 0.9
		var bolt := _make_bolt(key, mat)
		add_child(bolt)
		bolts.append(bolt)
		mats.append(mat)
		loosening.append(false)
		var body := StaticBody3D.new()
		body.collision_layer = _LAYER_BOLTS
		body.set_meta(&"hood_bolt", [key, i])
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = SPOT_RADIUS
		shape.shape = sphere
		body.add_child(shape)
		add_child(body)
		body.global_position = _engine.frame.global_transform * (spots[i].origin + spots[i].basis.z * 0.1)
		bodies.append(body)
	_bolts[key] = bolts
	_bolt_mats[key] = mats
	_loosening[key] = loosening
	_hole_bodies[key] = bodies
	for i in bolts.size():
		var t: int = turns[i] if i < turns.size() else 0
		bolts[i].global_transform = _tray_xform(key, i) if t <= 0 else _bolt_xform(key, i, float(t))


## A bolt in engine units, its axis +Z out of the hole: a hex head on a washer, or a wing
## nut for the air cleaner.
func _make_bolt(key: String, mat: Material) -> Node3D:
	var bolt := Node3D.new()
	bolt.name = "Bolt_%s" % key
	_cyl(bolt, 0.03, 0.3, -0.3, mat, 8)
	_cyl(bolt, 0.1, 0.015, 0.0, mat, 16)
	if key == GameState.SLOT_AIR_CLEANER:
		_cyl(bolt, 0.055, 0.09, 0.015, mat, 12)
		for side in [-1.0, 1.0]:
			var ear := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.12, 0.025, 0.1)
			ear.mesh = box
			ear.material_override = mat
			ear.position = Vector3(0.1 * side, 0.0, 0.08)
			bolt.add_child(ear)
	else:
		_cyl(bolt, 0.075, 0.08, 0.015, mat, 6)
	return bolt


func _cyl(parent: Node3D, radius: float, height: float, z0: float, mat: Material, sides: int) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.rotation.x = PI * 0.5
	mi.position = Vector3(0.0, 0.0, z0 + height * 0.5)
	parent.add_child(mi)


# --- Parts on and off ------------------------------------------------------------------


## Lifts off every part whose bolts are all out with nothing on top of it, top down, so
## taking the last bolt out of a part can bring the ones under it off after it.
func _settle() -> void:
	var again := true
	while again and is_instance_valid(self):
		again = false
		for key in TOP_DOWN:
			if not GameState.is_hood_part_fitted(key) or not GameState.hood_part_blocker(key).is_empty():
				continue
			if GameState.hood_bolts(key).max() > 0:
				continue
			await _lift_out(key)
			again = true
			break


func _lift_out(key: String) -> void:
	var err := GameState.remove_hood_part(key)
	if not err.is_empty():
		_hint.text = err
		return
	var rig: Node3D = _engine.rigs.get(key, null)
	_engine.rigs.erase(key)
	if key == GameState.SLOT_DISTRIBUTOR:
		_engine.rebuild(_EngineAssembly.WIRES)
	_hint.text = "Lifting the %s off…" % str(PART_NAMES[key]).to_lower()
	_play(_sfx_clunk)
	if rig != null:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(rig, "position:z", LIFT_ENGINE if key == GameState.HOOD_ENGINE else LIFT_PART, T_LIFT_ENGINE if key == GameState.HOOD_ENGINE else T_LIFT)
		await tw.finished
		if not is_instance_valid(self):
			return
		rig.queue_free()
	_build_bolts(key)
	_refresh_part_bodies()
	_hint.text = ""


## Lowers a spare part into an empty spot and starts its bolts.
func _fit(key: String, part_id: String) -> void:
	if _busy:
		return
	var err := GameState.fit_engine(part_id) if key == GameState.HOOD_ENGINE else GameState.fit_hood_part(part_id, key)
	if not err.is_empty():
		_picker_note.text = err
		return
	_close_picker()
	_busy = true
	_refresh_ui()
	var lift := LIFT_ENGINE if key == GameState.HOOD_ENGINE else LIFT_PART
	var rig: Node3D = _engine.rebuild(key)
	_build_bolts(key)
	var count := (_bolts.get(key, []) as Array).size()
	for i in count:
		(_bolts[key][i] as Node3D).global_transform = _tray_xform(key, i)
	_hint.text = "Lowering the %s in…" % str(PART_NAMES[key]).to_lower()
	if rig != null:
		rig.position.z = lift
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(rig, "position:z", 0.0, T_LIFT_ENGINE if key == GameState.HOOD_ENGINE else T_LIFT)
		await tw.finished
		if not is_instance_valid(self):
			return
	_play(_sfx_clunk)
	await _pause(T_PAUSE)
	for i in count:
		if not is_instance_valid(self):
			return
		await _thread_in(key, i)
	if not is_instance_valid(self):
		return
	_refresh_part_bodies()
	_busy = false
	_hint.text = ""
	_refresh_ui()


func _pause(seconds: float) -> void:
	if not is_instance_valid(self):
		return
	await get_tree().create_timer(seconds).timeout


# --- Clicking --------------------------------------------------------------------------


func _target_at(screen_pos: Vector2) -> Array:
	if _busy:
		return []
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 20.0
	var space := get_world_3d().direct_space_state
	var bolt_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, _LAYER_BOLTS))
	var part_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, _LAYER_PARTS))
	if not bolt_hit.is_empty():
		var bolt_near := from.distance_to(bolt_hit["position"])
		if part_hit.is_empty() or bolt_near <= from.distance_to(part_hit["position"]) + BOLT_PICK_DEPTH:
			var bolt := bolt_hit.get("collider") as Node
			if bolt != null and bolt.has_meta(&"hood_bolt"):
				return bolt.get_meta(&"hood_bolt")
	var node: Node = part_hit.get("collider") as Node if not part_hit.is_empty() else null
	if node != null and node.has_meta(&"hood_part"):
		return [str(node.get_meta(&"hood_part")), -1]
	return []


func _on_target(target: Array) -> void:
	var key := str(target[0])
	var index := int(target[1])
	if index >= 0:
		_on_bolt(key, index)
		return
	if key == _EngineAssembly.WIRES:
		_on_wires_pressed()
		return
	# A part left free with its bolts out, as an older save can have it, lifts off when
	# clicked.
	if not _busy and GameState.hood_part_blocker(key).is_empty() and GameState.hood_bolts(key).max() <= 0:
		await _settle_now()
		return
	_hint.text = _part_hint(key)


func _part_hint(key: String) -> String:
	var blocker := GameState.hood_part_blocker(key)
	if blocker == "wires":
		return "Pull the plug wires off before the %s can come out." % str(PART_NAMES[key]).to_lower()
	if not blocker.is_empty():
		return "Take the %s off first." % str(PART_NAMES[blocker]).to_lower()
	return "Back its bolts out and it lifts off."


func _update_hover() -> void:
	var target: Array = []
	var vp := get_viewport()
	if not _picker.visible and not _orbiting and vp.gui_get_hovered_control() == null:
		target = _target_at(vp.get_mouse_position())
	if target != _hover:
		_hover = target
		for key in _bolt_mats.keys():
			var mats: Array = _bolt_mats[key]
			for i in mats.size():
				(mats[i] as StandardMaterial3D).emission_enabled = _hover.size() == 2 and str(_hover[0]) == key and int(_hover[1]) == i
	if _hover.is_empty():
		_tooltip.visible = false
		return
	_tooltip.text = _target_text(_hover)
	_tooltip.visible = true
	_tooltip.reset_size()
	_tooltip.position = vp.get_mouse_position() + Vector2(18.0, 14.0)


func _target_text(target: Array) -> String:
	var key := str(target[0])
	var index := int(target[1])
	if index < 0:
		if key == _EngineAssembly.WIRES:
			return "Plug wires — pull them off"
		return "%s — %s" % [PART_NAMES[key], _part_name(key)]
	var turns: int = GameState.hood_bolts(key)[index]
	var label := str(BOLT_NAMES[key][index])
	if key == GameState.SLOT_HEADS and GameState.engine_head_count() == 1:
		label = ["Head, front bolt", "Head, rear bolt"][index % 2]
	if turns == 0:
		return "%s — thread it in" % label
	if _loosening[key][index] or turns >= GameState.GEARBOX_BOLT_TIGHT:
		return "%s — loosen" % label
	return "%s — tighten" % label


func _part_name(key: String) -> String:
	if key == GameState.HOOD_ENGINE:
		return str(GameState.get_equipped_engine().get("name", "Engine"))
	return str(GameState.slot_part(key).get("name", "none"))


## Click boxes around each part, from its meshes' bounds.
func _refresh_part_bodies() -> void:
	for bodies in _part_bodies.values():
		for body in bodies:
			(body as Node3D).queue_free()
	_part_bodies.clear()
	for key in _engine.rigs.keys():
		var rig: Node3D = _engine.rigs[key]
		if not is_instance_valid(rig):
			continue
		# The heads are one part but a box each, so the one box does not take in the
		# whole top of the engine between them.
		var pieces: Array = rig.get_children() if key == GameState.SLOT_HEADS else [rig]
		var bodies: Array[Node3D] = []
		for piece in pieces:
			var box := _world_bounds(piece)
			if box.size == Vector3.ZERO:
				continue
			var body := StaticBody3D.new()
			body.set_meta(&"hood_part", key)
			var shape := CollisionShape3D.new()
			var bshape := BoxShape3D.new()
			bshape.size = box.size
			shape.shape = bshape
			body.add_child(shape)
			add_child(body)
			body.global_position = box.get_center()
			bodies.append(body)
		if not bodies.is_empty():
			_part_bodies[key] = bodies
	# Parts lower down are under the ones on top: keep only their hot spots' bodies on
	# top by shrinking the engine's to its lower half, where nothing sits over it.
	if _part_bodies.has(GameState.HOOD_ENGINE):
		var body: StaticBody3D = _part_bodies[GameState.HOOD_ENGINE][0]
		var shape := (body.get_child(0) as CollisionShape3D).shape as BoxShape3D
		shape.size.y *= 0.5
		body.global_position.y -= shape.size.y * 0.5


func _world_bounds(node: Node) -> AABB:
	var out := AABB()
	var started := false
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var local := m.get_aabb()
		var xf := m.global_transform
		var box := AABB(xf * local.position, Vector3.ZERO)
		for i in 8:
			box = box.expand(xf * local.get_endpoint(i))
		if started:
			out = out.merge(box)
		else:
			out = box
			started = true
	return out


# --- UI ----------------------------------------------------------------------------------


func _on_parts_pressed() -> void:
	if _busy:
		return
	_open_picker()


func _on_wires_pressed() -> void:
	if _busy:
		return
	var err := GameState.set_plug_wires(not GameState.plug_wires)
	if not err.is_empty():
		_hint.text = err
		return
	_play(_sfx_snap)
	_engine.rebuild(_EngineAssembly.WIRES)
	_refresh_part_bodies()
	_hint.text = "Plug wires on." if GameState.plug_wires else "Plug wires off."
	_refresh_ui()
	# The wires held the distributor and heads down; with their bolts already out they
	# come off now.
	if not GameState.plug_wires:
		await _settle_now()


## Lifts off whatever is free to come off, keeping the screen busy while it goes.
func _settle_now() -> void:
	_busy = true
	_refresh_ui()
	await _settle()
	if not is_instance_valid(self):
		return
	_busy = false
	_refresh_ui()


func _on_tune_pressed() -> void:
	if _busy:
		return
	var trouble := GameState.engine_trouble()
	if not trouble.is_empty():
		_hint.text = "It won't start. %s" % trouble
		return
	_nav.clear()
	get_tree().change_scene_to_file(GameState.SCENE_TUNE)


func _on_done_pressed() -> void:
	if _busy:
		return
	_nav.clear()
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


## Empty spots the spare parts could go into now.
func _open_spots() -> Array[String]:
	var out: Array[String] = []
	if not GameState.has_engine():
		return [GameState.HOOD_ENGINE]
	for key in GameState.HOOD_SLOTS:
		if GameState.is_hood_part_fitted(key):
			continue
		if GameState.CARB_SLOTS.has(key) and not GameState.carb_slots().has(key) and key != GameState.SLOT_CARB:
			continue
		out.append(key)
	return out


func _open_picker() -> void:
	for child in _picker_rows.get_children():
		_picker_rows.remove_child(child)
		child.free()
	var spots := _open_spots()
	for key in spots:
		var heading := _ui_label(str(PART_NAMES[key]), 18)
		heading.add_theme_color_override(&"font_color", Color(0.95, 0.75, 0.45))
		_picker_rows.add_child(heading)
		var trouble := GameState.hood_spot_trouble(key)
		if not trouble.is_empty():
			_picker_rows.add_child(_ui_label(trouble, 15))
			continue
		var spares: Array[Dictionary] = []
		if key == GameState.HOOD_ENGINE:
			spares = GameState.spare_engines()
		else:
			for part in GameState.spare_slot_parts(key):
				if not GameState.CARB_SLOTS.has(key) or GameState.carb_fits_intake(part):
					spares.append(part)
		if spares.is_empty():
			_picker_rows.add_child(_ui_label("None in spare parts. The newspaper sells them.", 15))
		for part in spares:
			_picker_rows.add_child(_picker_row(key, part))
	if spots.is_empty():
		_picker_note.text = "Everything is on. Take a part off to put a different one on."
	else:
		_picker_note.text = "Pick a part to put in."
	_picker.visible = true
	_sync_nav()


func _picker_row(key: String, part: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var label := _ui_label("", 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail := "%.0f hp" % float(part.get("hp", 0.0)) if key == GameState.HOOD_ENGINE else GameState.part_detail(part)
	label.text = "%s\n%s" % [str(part.get("name", "Part")), detail]
	row.add_child(label)
	var fit := Button.new()
	fit.text = "Fit"
	fit.custom_minimum_size = Vector2(72, 0)
	fit.pressed.connect(_fit.bind(key, str(part.get("id", ""))))
	row.add_child(fit)
	return row


func _close_picker() -> void:
	_picker.visible = false
	_sync_nav()


func _sync_nav() -> void:
	if _picker.visible:
		_nav.setup(_nav.collect_buttons(_picker))
	else:
		_nav.setup([_parts_btn, _wires_btn, _tune_btn, _done_btn])


func _refresh_ui() -> void:
	if GameState.has_engine():
		var engine := GameState.get_equipped_engine()
		_engine_label.text = "%s · %.0f hp" % [str(engine.get("name", "Engine")), GameState.engine_power_hp]
	else:
		_engine_label.text = "No engine"
	var lines: Array[String] = []
	for key in ["engine", "heads", "intake", "carb", "carb_2", "carb_3", "distributor", "air_cleaner"]:
		if not GameState.is_hood_part_fitted(key):
			if key == GameState.HOOD_ENGINE or (GameState.has_engine() and (not GameState.CARB_SLOTS.has(key) or GameState.carb_slots().has(key))):
				lines.append("%s: none" % PART_NAMES[key])
			continue
		var name := _part_name(key)
		if key == GameState.HOOD_ENGINE:
			name = "mounts"
		lines.append("%s: %s (%s)" % [PART_NAMES[key], name, _bolt_state(key)])
	if GameState.has_engine():
		lines.append("Plug wires: %s" % ("on" if GameState.plug_wires else "off"))
	_parts_label.text = "\n".join(lines)
	_wires_btn.text = "Wires off (W)" if GameState.plug_wires else "Wires on (W)"
	for b in [_parts_btn, _wires_btn, _tune_btn, _done_btn]:
		(b as Button).disabled = _busy
	if _busy:
		return
	if _hint.text.is_empty() or _hint.text.ends_with("…"):
		var trouble := GameState.engine_trouble()
		_hint.text = "Ready to run. Tune sets the timing." if trouble.is_empty() else trouble


func _bolt_state(key: String) -> String:
	var bolts := GameState.hood_bolts(key)
	if bolts.min() >= GameState.GEARBOX_BOLT_TIGHT:
		return "tight"
	if bolts.max() == 0:
		return "bolts out"
	return "loose"


func _build_ui() -> void:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override(&"panel", _panel_style())
	header.position = Vector2(16, 16)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(header)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 4)
	header.add_child(info)
	info.add_child(_ui_label("Under the hood — %s" % GameState.car_name, 22))
	_engine_label = _ui_label("", 17)
	info.add_child(_engine_label)
	_parts_label = _ui_label("", 15)
	info.add_child(_parts_label)

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override(&"panel", _panel_style())
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16.0
	bottom.offset_right = -16.0
	bottom.offset_top = -72.0
	bottom.offset_bottom = -16.0
	_ui.add_child(bottom)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 12)
	bottom.add_child(bar)
	_hint = _ui_label("", 18)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_hint)
	_parts_btn = _button("Parts (P)", _on_parts_pressed, bar)
	_wires_btn = _button("Wires (W)", _on_wires_pressed, bar)
	_tune_btn = _button("Tune (T)", _on_tune_pressed, bar)
	_done_btn = _button("Done", _on_done_pressed, bar)
	_done_btn.custom_minimum_size = Vector2(96, 0)

	_tooltip = _ui_label("", 18)
	_tooltip.visible = false
	_tooltip.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	_tooltip.add_theme_constant_override(&"shadow_offset_x", 2)
	_tooltip.add_theme_constant_override(&"shadow_offset_y", 2)
	_ui.add_child(_tooltip)

	_build_picker()
	_sync_nav()


func _button(text: String, handler: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _build_picker() -> void:
	_picker = Control.new()
	_picker.name = "Picker"
	_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280.0
	panel.offset_right = 280.0
	panel.offset_top = -230.0
	panel.offset_bottom = 230.0
	_picker.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	var title := _ui_label("Spare parts", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_picker_note = _ui_label("", 16)
	_picker_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_picker_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	# Room on the right for the scroll bar beside the Fit buttons.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override(&"margin_right", 12)
	scroll.add_child(margin)
	_picker_rows = VBoxContainer.new()
	_picker_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_rows.add_theme_constant_override(&"separation", 10)
	margin.add_child(_picker_rows)
	_picker_close = Button.new()
	_picker_close.text = "Forget it"
	_picker_close.pressed.connect(_close_picker)
	box.add_child(_picker_close)
	_ui.add_child(_picker)


func _ui_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", _CREAM)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.92)
	style.border_color = Color(0.55, 0.12, 0.1, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


# --- Scene building ----------------------------------------------------------------------


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.045, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_shop_reflections(env)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# Trouble light hung from the open hood, and a cool fill from the shop.
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-0.2, 1.75, 0.25)
	lamp.light_color = Color(1.0, 0.88, 0.7)
	lamp.light_energy = 1.6
	lamp.omni_range = 3.5
	lamp.shadow_enabled = true
	add_child(lamp)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.8, 1.4, 1.4)
	fill.light_color = Color(0.7, 0.78, 0.95)
	fill.light_energy = 0.8
	fill.omni_range = 5.0
	add_child(fill)


## Chrome and polished metal need something to reflect: a dim shop, lighter overhead.
static func _shop_reflections(env: Environment) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.52, 0.48)
	sky_mat.sky_horizon_color = Color(0.3, 0.28, 0.25)
	sky_mat.ground_horizon_color = Color(0.2, 0.19, 0.17)
	sky_mat.ground_bottom_color = Color(0.08, 0.075, 0.07)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY


## The bay around the engine: floor, frame rails, inner fenders, radiator and its support,
## the fenders and cowl in the car's paint, and the hood propped open.
func _build_bay() -> void:
	var concrete := _mat(Color(0.32, 0.31, 0.3), 0.0, 0.9)
	var under := _mat(Color(0.08, 0.075, 0.07), 0.2, 0.8)
	var paint := _mat(GameState.car_color, 0.3, 0.4)
	var frame := _mat(Color(0.1, 0.1, 0.1), 0.4, 0.6)
	var core := _mat(Color(0.12, 0.12, 0.11), 0.5, 0.7)
	var tray := _mat(Color(0.6, 0.6, 0.62), 0.8, 0.3)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(9.0, 9.0)
	floor.mesh = plane
	floor.material_override = concrete
	add_child(floor)
	for side in [-1.0, 1.0]:
		_box(Vector3(2.4, 0.12, 0.08), Vector3(0.1, 0.32, 0.46 * side), frame)
		# Inner fender, the fender top, and the wheel well below it.
		_box(Vector3(1.6, 0.5, 0.03), Vector3(-0.1, 0.62, 0.66 * side), under)
		_box(Vector3(1.9, 0.05, 0.24), Vector3(-0.15, 0.95, 0.8 * side), paint)
		_box(Vector3(1.9, 0.5, 0.03), Vector3(-0.15, 0.72, 0.92 * side), paint)
	# Radiator support and radiator ahead of the engine, firewall and cowl behind it.
	_box(Vector3(0.06, 0.62, 1.3), Vector3(-0.78, 0.62, 0.0), under)
	_box(Vector3(0.07, 0.48, 1.0), Vector3(-0.72, 0.63, 0.0), core)
	_box(Vector3(0.08, 0.06, 1.88), Vector3(-0.8, 0.95, 0.0), paint)
	_box(Vector3(0.04, 0.7, 1.3), Vector3(0.78, 0.6, 0.0), under)
	_box(Vector3(0.4, 0.05, 1.86), Vector3(0.98, 0.97, 0.0), paint)
	# The hood, hinged at the cowl and propped up.
	var hood := Node3D.new()
	hood.position = Vector3(0.78, 0.98, 0.0)
	hood.rotation.z = deg_to_rad(-68.0)
	add_child(hood)
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.55, 0.03, 1.8)
	panel.mesh = mesh
	panel.material_override = paint
	panel.position = Vector3(-0.78, 0.0, 0.0)
	hood.add_child(panel)
	var lining := MeshInstance3D.new()
	var lmesh := BoxMesh.new()
	lmesh.size = Vector3(1.4, 0.01, 1.6)
	lining.mesh = lmesh
	lining.material_override = under
	lining.position = Vector3(-0.78, -0.02, 0.0)
	hood.add_child(lining)
	# Parts tray on the left fender for the bolts that are out.
	_box(Vector3(TRAY_STEP * 9.5, 0.012, 0.09), TRAY + Vector3(TRAY_STEP * 4.0, 0.0, 0.0), tray)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


# --- Sounds --------------------------------------------------------------------------------


func _build_sounds() -> void:
	_sfx_ratchet = _sfx(_wav(_ratchet_samples(5, 0.3, 2600.0, 0.7)))
	_sfx_snug = _sfx(_wav(_snug_samples()))
	_sfx_clunk = _sfx(_wav(_clunk_samples()))
	_sfx_tink = _sfx(_wav(_tink_samples()))
	_sfx_snap = _sfx(_wav(_ratchet_samples(1, 0.12, 900.0, 0.8)))


func _sfx(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -6.0
	add_child(player)
	return player


func _play(player: AudioStreamPlayer) -> void:
	if player != null:
		player.play()


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _RATE
	wav.stereo = false
	wav.data = data
	return wav


## Pawl clicks of a ratchet wrench, `clicks` of them spread over `length` seconds.
func _ratchet_samples(clicks: int, length: float, pitch: float, level: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(length * _RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var span := int(0.014 * _RATE)
	for c in clicks:
		var start := int((float(c) + 0.1) / float(clicks) * out.size())
		for k in span:
			var i := start + k
			if i >= out.size():
				break
			var t := float(k) / _RATE
			var env := exp(-t * 480.0)
			out[i] += (rng.randf_range(-1.0, 1.0) * 0.55 + sin(TAU * pitch * t) * 0.45) * env * level
	return out


## The last click of a bolt pulling up tight: two clicks, then a heavier one.
func _snug_samples() -> PackedFloat32Array:
	var out := _ratchet_samples(2, 0.32, 2600.0, 0.7)
	var hit := _ratchet_samples(1, 0.16, 1500.0, 1.0)
	var at := int(0.2 * _RATE)
	for k in hit.size():
		if at + k < out.size():
			out[at + k] += hit[k]
	return out


## Iron on iron: a part seating on its studs, or coming off them.
func _clunk_samples() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(0.45 * _RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in out.size():
		var t := float(i) / _RATE
		var body := (sin(TAU * 72.0 * t) * 0.7 + sin(TAU * 151.0 * t) * 0.35) * exp(-t * 14.0)
		var knock := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.6
		var ring := sin(TAU * 1240.0 * t) * exp(-t * 26.0) * 0.12
		out[i] = (body + knock + ring) * 0.8
	return out


## A bolt dropped into the steel tray.
func _tink_samples() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(0.4 * _RATE))
	for bounce in 2:
		var at := int((0.0 if bounce == 0 else 0.09) * _RATE)
		var level := 0.5 if bounce == 0 else 0.2
		for k in out.size() - at:
			var t := float(k) / _RATE
			var env := exp(-t * 34.0) * level
			out[at + k] += (sin(TAU * 2650.0 * t) + sin(TAU * 4100.0 * t) * 0.6 + sin(TAU * 6200.0 * t) * 0.3) * env * 0.5
	return out
