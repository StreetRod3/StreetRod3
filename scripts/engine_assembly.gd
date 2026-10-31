extends Node3D

## An engine built up from its parts as the active car has them: the long block with
## its front drive (balancer, timing tab, pulleys, belt), the intake, its carburetors, the
## distributor, the air cleaner, and the plug wires. Each part is a rig under `frame`,
## keyed by `GameState.HOOD_ENGINE`, a hood slot, or `WIRES`, so the hood screen can lift
## it out on its own. Parts are built in engine units: +X toward the back of the car, +Y
## to the car's right, +Z up, the crank at Z -0.36 and the block 3 long. `frame` turns
## them into meters, standing up in the Y-up world.

## Engine models are built about four and a half times real size.
const ENGINE_SCALE := 0.22
const CRANK_Z := -0.36
const WIRES := "wires"

## Where the cast-iron intake's carburetor pad is, and the distributor's base on any intake.
## The engine models carry their stock intake, carburetor and distributor at these spots.
const IRON_PAD := Vector3(0.0, 0.0, 1.08)
const DISTRIBUTOR_BASE := Vector3(0.92, 0.0, 1.05)
## The cap's plug towers stand in a ring this wide, their tops this high off the base.
const CAP_TOWER_R := 0.12
const CAP_TOWER_TOP := 0.42
## Cylinder centers along the block, front to back.
const BORES_X: Array[float] = [-1.05, -0.355, 0.355, 1.05]
## Spark plugs stand out of the heads' outer faces, this far out and this high.
const PLUG_Y := 0.86
const PLUG_Z := 0.72
## Plug wires run up over the valve covers here and down the outside of the heads here,
## as (out from the middle, height).
const WIRE_OVER := Vector2(0.72, 1.42)
const WIRE_BEND := Vector2(1.08, 1.36)
const WIRE_DOWN := Vector2(1.04, 0.95)
## Ports on the heads' top faces that a runner intake bolts to, out from the middle.
const PORT_Y := 0.36
const PORT_Z := 1.18
## The bottom of an aftermarket intake's plenum, down in the valley.
const INTAKE_FLOOR := 0.9
const INTAKE_WIDTH := 0.5
## Ends of the intake where it bolts down, one each side.
const INTAKE_BOLTS: Array[Vector3] = [Vector3(-0.74, 0.2, 1.08), Vector3(0.74, -0.2, 1.08)]
## Engine mounts: an ear off each front corner of the block beside the timing cover, the
## bolt standing up through it.
const MOUNT_BOLTS: Array[Vector3] = [Vector3(-1.58, 0.53, 0.1), Vector3(-1.58, -0.53, 0.1)]
## Head bolts, front and back on each head's sloping inner top face, below the valve
## cover, square to that face. The face runs from `HEAD_DECK_IN` (out from the middle,
## height) up to `HEAD_DECK_OUT`. The right head (+Y) first.
const HEAD_BOLT_X := 1.26
const HEAD_BOLT_Y := 0.3
const HEAD_DECK_IN := Vector2(0.09, 0.79)
const HEAD_DECK_OUT := Vector2(0.59, 1.18)
## The distributor's hold-down clamp bolt, on the boss behind it.
const CLAMP_BOLT := Vector3(1.16, 0.0, 1.05)

## The front drive. The timing cover's face is at `COVER_X`; pulleys line up on `BELT_X`.
const COVER_X := -1.67
const BELT_X := -2.02
const BALANCER_R := 0.38
const PUMP_CENTER := Vector2(0.0, 0.32)
const ALTERNATOR_CENTER := Vector2(0.95, 0.45)
## The timing tab: its 0 mark this far clockwise from the top as seen from the front,
## and each degree of timing drawn this many degrees of arc so the marks can be read.
const TAB_ZERO_DEG := 165.0
const TAB_ARC_PER_DEG := 3.0
const TAB_BTDC_MAX := 20
const TAB_ATDC_MAX := 4

const _MODEL_DEFAULT := "res://assets/parts/engine-v8-283.glb"
## Nodes of an engine model by part. The long block is everything else, less the front
## drive the assembly builds itself.
const _NODES_HEADS: Array[String] = ["cylinder_head", "valve_cover", "valve_bolt"]
const _NODES_INTAKE: Array[String] = ["intake_manifold"]
const _NODES_CARB: Array[String] = ["carburetor", "carb_throat"]
const _NODES_DISTRIBUTOR: Array[String] = ["distributor"]
const _NODES_FRONT_DRIVE: Array[String] = ["crank_pulley", "upper_pulley", "alternator_pulley", "water_pump_housing", "accessory_bracket"]

## The block's paint as the models carry it, in linear color.
const PAINT := Color(0.41, 0.44, 0.46)
const _ALUMINUM := Color(0.7, 0.7, 0.69)
const _CHROME := Color(0.9, 0.9, 0.92)
const _STEEL := Color(0.62, 0.62, 0.63)
const _BLACK := Color(0.03, 0.03, 0.03)
const _RUBBER := Color(0.05, 0.05, 0.05)
const _ZINC := Color(0.66, 0.55, 0.26)
const _CAP_COLORS := {
	"black": Color(0.04, 0.04, 0.04),
	"red": Color(0.55, 0.04, 0.03),
	"blue": Color(0.05, 0.16, 0.5),
}
const _CARB_FINISHES := {
	"bright": Color(0.8, 0.68, 0.32),
	"silver": Color(0.72, 0.72, 0.7),
}

var frame: Node3D
## Rigs by key. A part that is not on the car has no rig.
var rigs: Dictionary = {}
## Turns about the crank: the mark is on top at 0, clockwise from the front.
var balancer: Node3D
var _mats: Dictionary = {}


func _init() -> void:
	frame = Node3D.new()
	frame.name = "EngineFrame"
	frame.rotation.x = -PI * 0.5
	frame.scale = Vector3.ONE * ENGINE_SCALE
	add_child(frame)


## Builds every part the active car has.
func build() -> void:
	for key in rigs.keys():
		(rigs[key] as Node3D).queue_free()
	rigs.clear()
	balancer = null
	for key in all_keys():
		rebuild(key)


static func all_keys() -> Array[String]:
	var keys: Array[String] = [GameState.HOOD_ENGINE]
	keys.append_array(GameState.HOOD_SLOTS)
	keys.append(WIRES)
	return keys


## Builds (or takes away) the rig for one key as the car has it now.
func rebuild(key: String) -> Node3D:
	if rigs.has(key):
		(rigs[key] as Node3D).queue_free()
		rigs.erase(key)
	if not _present(key):
		return null
	var rig := Node3D.new()
	rig.name = "Rig_%s" % key
	frame.add_child(rig)
	rigs[key] = rig
	match key:
		GameState.HOOD_ENGINE:
			_build_engine(rig)
		GameState.SLOT_HEADS:
			_build_heads(rig, GameState.slot_part(key))
		GameState.SLOT_INTAKE:
			_build_intake(rig, GameState.slot_part(key))
		GameState.SLOT_DISTRIBUTOR:
			_build_distributor(rig, GameState.slot_part(key))
		GameState.SLOT_AIR_CLEANER:
			_build_air_cleaner(rig, GameState.slot_part(key))
		WIRES:
			_build_wires(rig)
		_:
			_build_carb(rig, GameState.slot_part(key), carb_pad(key))
	return rig


func _present(key: String) -> bool:
	if key == WIRES:
		return GameState.has_engine() and GameState.plug_wires and not GameState.slot_part(GameState.SLOT_DISTRIBUTOR).is_empty() and not GameState.slot_part(GameState.SLOT_HEADS).is_empty()
	return GameState.is_hood_part_fitted(key)


## Where each bolt of a part goes, in engine units: origin at the hole, +Z out of it.
func bolt_spots(key: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	match key:
		GameState.HOOD_ENGINE:
			for p in MOUNT_BOLTS:
				out.append(Transform3D(Basis.IDENTITY, p))
		GameState.SLOT_HEADS:
			var slope := HEAD_DECK_OUT - HEAD_DECK_IN
			var z := HEAD_DECK_IN.y + slope.y * (HEAD_BOLT_Y - HEAD_DECK_IN.x) / slope.x
			for side in head_sides():
				var normal := Vector3(0.0, -slope.y * side, slope.x).normalized()
				for x in [-HEAD_BOLT_X, HEAD_BOLT_X]:
					out.append(Transform3D(_axis_basis(normal), Vector3(x, HEAD_BOLT_Y * side, z)))
		GameState.SLOT_INTAKE:
			for p in INTAKE_BOLTS:
				out.append(Transform3D(Basis.IDENTITY, p))
		GameState.SLOT_DISTRIBUTOR:
			out.append(Transform3D(Basis.IDENTITY, CLAMP_BOLT))
		GameState.SLOT_AIR_CLEANER:
			out.append(Transform3D(Basis.IDENTITY, carb_pad(GameState.SLOT_CARB) + Vector3(0.0, 0.0, _cleaner_top())))
		_:
			if GameState.CARB_SLOTS.has(key):
				var four := int(GameState.slot_part(GameState.SLOT_INTAKE).get("barrels", 4)) == 4
				var nut := Vector3(-0.25, -0.2, 0.1) if four else Vector3(-0.2, -0.17, 0.07)
				out.append(Transform3D(Basis.IDENTITY, carb_pad(key) + nut))
	return out


## The carburetor pads of an intake style, front to back.
static func pads_for(style: String) -> Array[Vector3]:
	match style:
		"highrise":
			return [Vector3(0.0, 0.0, 1.26)]
		"tripower":
			return [Vector3(-0.58, 0.0, 1.24), Vector3(0.0, 0.0, 1.24), Vector3(0.58, 0.0, 1.24)]
		"dualquad":
			return [Vector3(-0.42, 0.0, 1.3), Vector3(0.42, 0.0, 1.3)]
	return [IRON_PAD]


## The pad a carburetor slot sits on, on the fitted intake.
func carb_pad(slot: String) -> Vector3:
	var pads := pads_for(str(GameState.slot_part(GameState.SLOT_INTAKE).get("style", "iron4")))
	return pads[clampi(GameState.CARB_SLOTS.find(slot), 0, pads.size() - 1)]


## Height of a carburetor's air horn above its pad.
func _carb_height() -> float:
	return 0.48 if int(GameState.slot_part(GameState.SLOT_INTAKE).get("barrels", 4)) == 4 else 0.36


func _cleaner_top() -> float:
	return _carb_height() + 0.32


## The balancer's turn that puts its mark at `degrees` of timing on the tab.
static func mark_angle(degrees: float) -> float:
	return deg_to_rad(TAB_ZERO_DEG - degrees * TAB_ARC_PER_DEG)


# --- Engine and front drive ------------------------------------------------------


func _build_engine(rig: Node3D) -> void:
	var leave: Array[String] = []
	for nodes in [_NODES_HEADS, _NODES_INTAKE, _NODES_CARB, _NODES_DISTRIBUTOR, _NODES_FRONT_DRIVE]:
		leave.append_array(nodes)
	_add_model_nodes(rig, leave, false)
	var steel := _mat("steel", _STEEL, 0.6, 0.35)
	var dark := _mat("dark", Color(0.12, 0.12, 0.12), 0.6, 0.5)
	var rubber := _mat("rubber", _RUBBER, 0.0, 0.85)
	var white := _mat("mark", Color(0.95, 0.95, 0.9), 0.0, 0.5)
	var paint := _paint()
	# The boss in the valley behind the intake that the distributor stands in.
	_box(rig, Vector3(0.5, 0.2, DISTRIBUTOR_BASE.z - 0.7), Vector3((DISTRIBUTOR_BASE.x + CLAMP_BOLT.x) * 0.5, 0.0, (DISTRIBUTOR_BASE.z + 0.7) * 0.5), paint)
	# Mount ears off the block's front corners, on rubber mounts below.
	for p in MOUNT_BOLTS:
		_box(rig, Vector3(0.18, 0.2, 0.06), Vector3(p.x + 0.02, p.y, p.z - 0.03), steel)
		_box(rig, Vector3(0.14, 0.16, 0.12), Vector3(p.x, p.y, p.z - 0.12), rubber)
	# Balancer: steel hub, rubber ring, steel rim with the mark across its face.
	balancer = Node3D.new()
	balancer.name = "Balancer"
	balancer.position = Vector3(0.0, 0.0, CRANK_Z)
	rig.add_child(balancer)
	_cyl_x(balancer, BALANCER_R, 0.16, COVER_X - 0.01, steel, 40)
	_cyl_x(balancer, BALANCER_R - 0.06, 0.012, COVER_X - 0.17, rubber, 40)
	_cyl_x(balancer, BALANCER_R - 0.08, 0.02, COVER_X - 0.18, steel, 40)
	_cyl_x(balancer, 0.12, 0.14, COVER_X - 0.17, dark, 20)
	# The mark: a white line on the face out to the rim, and on across the rim.
	var mark_face := _box(balancer, Vector3(0.016, 0.045, 0.12), Vector3(COVER_X - 0.19, 0.0, BALANCER_R - 0.055), white)
	mark_face.name = "MarkFace"
	var mark_rim := _box(balancer, Vector3(0.16, 0.045, 0.012), Vector3(COVER_X - 0.09, 0.0, BALANCER_R + 0.003), white)
	mark_rim.name = "MarkRim"
	# Crank pulley out on the hub, in line with the belt.
	_cyl_x(balancer, 0.3, 0.035, BELT_X + 0.04, steel, 36)
	_cyl_x(balancer, 0.24, 0.02, BELT_X + 0.01, steel, 36)
	_cyl_x(balancer, 0.3, 0.035, BELT_X - 0.025, steel, 36)
	_build_timing_tab(rig)
	# Water pump above the crank, and its pulley.
	_cyl_x(rig, 0.17, 0.3, COVER_X, paint, 24, PUMP_CENTER.x, PUMP_CENTER.y)
	_cyl_x(rig, 0.06, 0.06, COVER_X - 0.3, steel, 12, PUMP_CENTER.x, PUMP_CENTER.y)
	_cyl_x(rig, 0.3, 0.08, BELT_X + 0.04, steel, 36, PUMP_CENTER.x, PUMP_CENTER.y)
	# Alternator on the right, on a bracket off the head.
	_cyl_x(rig, 0.26, 0.48, -1.28, _mat("alternator", Color(0.62, 0.62, 0.6), 0.6, 0.45), 24, ALTERNATOR_CENTER.x, ALTERNATOR_CENTER.y)
	_cyl_x(rig, 0.04, 0.2, -1.76, steel, 10, ALTERNATOR_CENTER.x, ALTERNATOR_CENTER.y)
	_cyl_x(rig, 0.14, 0.08, BELT_X + 0.04, steel, 24, ALTERNATOR_CENTER.x, ALTERNATOR_CENTER.y)
	_box(rig, Vector3(0.04, 0.3, 0.08), Vector3(-1.56, 0.82, 0.62), dark)
	# Fan belt around the three pulleys.
	var hull := PackedVector2Array()
	for c in [[Vector2(0.0, CRANK_Z), 0.3], [PUMP_CENTER, 0.3], [ALTERNATOR_CENTER, 0.14]]:
		for k in 24:
			var a := TAU * float(k) / 24.0
			hull.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * (float(c[1]) + 0.025))
	hull = Geometry2D.convex_hull(hull)
	var loop := PackedVector3Array()
	for i in hull.size() - 1:
		loop.append(Vector3(BELT_X, hull[i].x, hull[i].y))
	var belt := MeshInstance3D.new()
	belt.mesh = sweep_mesh(loop, 0.035, 6, true)
	belt.material_override = rubber
	rig.add_child(belt)


## Plate over the balancer's rim with a mark each two degrees, 0 to 20 before top dead
## center and a few after, numbered every ten.
func _build_timing_tab(rig: Node3D) -> void:
	var steel := _mat("tab", Color(0.3, 0.3, 0.3), 0.7, 0.4)
	var white := _mat("mark", Color(0.95, 0.95, 0.9), 0.0, 0.5)
	var x := COVER_X - 0.2
	for deg in range(-TAB_ATDC_MAX, TAB_BTDC_MAX + 1, 2):
		var a := mark_angle(float(deg))
		var long := deg % 10 == 0
		var span := 0.1 if long else 0.06
		var r := BALANCER_R + 0.02 + span * 0.5
		var tick := _box(rig, Vector3(0.01, 0.014, span), Vector3(x - 0.005, -r * sin(a), CRANK_Z + r * cos(a)), white)
		tick.rotation.x = a
		if long:
			var label := Label3D.new()
			label.text = str(deg)
			label.font_size = 32
			label.pixel_size = 0.0035
			label.outline_size = 0
			label.modulate = Color(0.95, 0.95, 0.9)
			var lr := BALANCER_R + 0.17
			label.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)), Vector3(x - 0.01, -lr * sin(a), CRANK_Z + lr * cos(a)))
			rig.add_child(label)
	# The plate itself, a strip of arc behind the marks, on a foot to the cover.
	var steps := 10
	var a0 := mark_angle(float(TAB_BTDC_MAX + 1))
	var a1 := mark_angle(float(-TAB_ATDC_MAX - 1))
	for i in steps:
		var a := lerpf(a0, a1, (float(i) + 0.5) / float(steps))
		var r := BALANCER_R + 0.07
		var seg := _box(rig, Vector3(0.012, (a1 - a0) / float(steps) * r * 1.1, 0.12), Vector3(x + 0.006, -r * sin(a), CRANK_Z + r * cos(a)), steel)
		seg.rotation.x = a
	var foot := mark_angle(8.0)
	_box(rig, Vector3(0.18, 0.06, 0.06), Vector3(x + 0.09, -(BALANCER_R + 0.12) * sin(foot), CRANK_Z + (BALANCER_R + 0.12) * cos(foot)), steel)


# --- Heads -------------------------------------------------------------------------


## The banks the engine has heads on, by side: +1 on the right, -1 on the left. One head
## on an inline engine is the right-hand one.
static func head_sides() -> Array[float]:
	var sides: Array[float] = [1.0]
	if GameState.engine_head_count() >= 2:
		sides.append(-1.0)
	return sides


## Each head with its valve cover, in a node of its own (`Head_1`, `Head_-1`) so the
## hood screen can tell them apart. Aluminum heads are left bare.
func _build_heads(rig: Node3D, part: Dictionary) -> void:
	var aluminum := str(part.get("finish", "")) == "aluminum"
	for side in head_sides():
		var bank := "%d" % int(side)
		var head := Node3D.new()
		head.name = "Head_%s" % bank
		rig.add_child(head)
		var nodes: Array[String] = ["cylinder_head_" + bank, "valve_cover_" + bank, "valve_bolt_%s_" % bank]
		var model := _add_model_nodes(head, nodes, true)
		if model == null or not aluminum:
			continue
		var casting := model.find_child("cylinder_head_" + bank, true, false) as MeshInstance3D
		if casting != null:
			casting.material_override = _mat("aluminum", _ALUMINUM, 0.75, 0.35)


# --- Intake ------------------------------------------------------------------------


func _build_intake(rig: Node3D, part: Dictionary) -> void:
	var style := str(part.get("style", "iron4"))
	if style == "iron4":
		_add_model_nodes(rig, _NODES_INTAKE, true)
		return
	var metal := _paint() if style == "tripower" else _mat("aluminum", _ALUMINUM, 0.75, 0.35)
	var pads := pads_for(style)
	var front := pads[0].x - 0.36
	var back := pads[pads.size() - 1].x + 0.36
	var top := pads[0].z
	var floor_z := INTAKE_FLOOR
	# Runners from the plenum out to each port on the heads, four a side.
	for side in [-1.0, 1.0]:
		for bx in BORES_X:
			var port := Vector3(bx + 0.1 * side, PORT_Y * side, PORT_Z)
			var root := Vector3(clampf(bx * 0.55, front + 0.12, back - 0.12), INTAKE_WIDTH * 0.3 * side, top - 0.14)
			var mid := Vector3((port.x + root.x) * 0.5, (PORT_Y + 0.04) * side, top - 0.02)
			var runner := MeshInstance3D.new()
			runner.mesh = sweep_mesh(_bezier(root, mid, port, 10), 0.075, 10, false)
			runner.material_override = metal
			rig.add_child(runner)
			_box(rig, Vector3(0.22, 0.2, 0.04), port + Vector3(0.0, 0.0, 0.01), metal)
	# Plenum and the pads on top, and the flanges the bolts go through.
	_box(rig, Vector3(back - front, INTAKE_WIDTH, top - floor_z), Vector3((front + back) * 0.5, 0.0, (top + floor_z) * 0.5 - 0.02), metal)
	for pad in pads:
		var size := Vector3(0.5, INTAKE_WIDTH, 0.04) if style != "tripower" else Vector3(0.44, 0.4, 0.04)
		_box(rig, size, pad - Vector3(0.0, 0.0, 0.02), metal)
	if style == "dualquad":
		# Cast fins down the plenum between the carburetors.
		for i in 5:
			_box(rig, Vector3(0.025, INTAKE_WIDTH + 0.04, 0.06), Vector3(lerpf(-0.16, 0.16, float(i) / 4.0), 0.0, top - 0.08), metal)
	for p in INTAKE_BOLTS:
		_box(rig, Vector3(0.18, 0.18, p.z - floor_z), Vector3(p.x, p.y, (p.z + floor_z) * 0.5), metal)
	# Thermostat housing and water neck in front.
	_box(rig, Vector3(0.36, 0.36, top - floor_z), Vector3(front - 0.16, 0.0, (top + floor_z) * 0.5 - 0.02), metal)
	_cyl_z(rig, 0.11, 0.09, 0.14, Vector3(front - 0.2, 0.0, top - 0.02), _mat("steel", _STEEL, 0.6, 0.35), 16)


# --- Carburetors ---------------------------------------------------------------------


func _build_carb(rig: Node3D, part: Dictionary, pad: Vector3) -> void:
	if int(part.get("barrels", 4)) == 2:
		_build_two_barrel(rig, pad)
		return
	var model := _add_model_nodes(rig, _NODES_CARB, true)
	if model == null:
		return
	model.position = pad - IRON_PAD
	var finish: Variant = _CARB_FINISHES.get(str(part.get("finish", "")), null)
	var body := model.find_child("carburetor", true, false) as MeshInstance3D
	if finish is Color and body != null:
		body.material_override = _mat("carb_" + str(part.get("finish", "")), finish, 0.85, 0.3)


func _build_two_barrel(rig: Node3D, pad: Vector3) -> void:
	var zinc := _mat("carb", _ZINC, 0.85, 0.35)
	var dark := _mat("black", _BLACK, 0.0, 0.6)
	var steel := _mat("steel", _STEEL, 0.6, 0.35)
	_box(rig, Vector3(0.44, 0.4, 0.03), pad + Vector3(0.0, 0.0, 0.015), dark)
	_box(rig, Vector3(0.38, 0.34, 0.06), pad + Vector3(0.0, 0.0, 0.06), zinc)
	_box(rig, Vector3(0.3, 0.32, 0.2), pad + Vector3(0.0, 0.0, 0.19), zinc)
	# Float bowl on the front, air horn on top with its two throats.
	_box(rig, Vector3(0.12, 0.28, 0.2), pad + Vector3(-0.2, 0.0, 0.18), zinc)
	_cyl_z(rig, 0.17, 0.17, 0.07, pad + Vector3(0.0, 0.0, 0.29), zinc, 20)
	for y in [-0.075, 0.075]:
		_cyl_z(rig, 0.055, 0.055, 0.005, pad + Vector3(0.0, y, 0.36), dark, 14)
	# Throttle shaft and lever.
	_cyl_x(rig, 0.018, 0.4, pad.x - 0.2, steel, 8, pad.y + 0.18, pad.z + 0.08)


# --- Distributor -----------------------------------------------------------------------


func _build_distributor(rig: Node3D, part: Dictionary) -> void:
	var model := _add_model_nodes(rig, _NODES_DISTRIBUTOR, true)
	if model == null:
		return
	var color: Variant = _CAP_COLORS.get(str(part.get("cap", "black")), _CAP_COLORS["black"])
	var cap_mat := _mat("cap_" + str(part.get("cap", "black")), color, 0.0, 0.35)
	var cap := model.find_child("distributor_cap", true, false) as MeshInstance3D
	if cap != null:
		cap.material_override = cap_mat
	# The plug towers round the top of the cap.
	for tower in cap_towers():
		_cyl_z(rig, 0.03, 0.025, 0.08, DISTRIBUTOR_BASE + tower - Vector3(0.0, 0.0, 0.08), cap_mat, 10)
	# Hold-down clamp from the bolt over the distributor's flange.
	var steel := _mat("steel", _STEEL, 0.6, 0.35)
	var reach := Vector2(DISTRIBUTOR_BASE.x - CLAMP_BOLT.x, DISTRIBUTOR_BASE.y - CLAMP_BOLT.y)
	var clamp := _box(rig, Vector3(reach.length() + 0.08, 0.08, 0.025), Vector3((DISTRIBUTOR_BASE.x + CLAMP_BOLT.x) * 0.5, (DISTRIBUTOR_BASE.y + CLAMP_BOLT.y) * 0.5, CLAMP_BOLT.z), steel)
	clamp.rotation.z = reach.angle()


# --- Air cleaner ---------------------------------------------------------------------


## One cleaner over each carburetor: big round ones over four-barrels, small ones over a
## tri-power's two-barrels. The stock cleaner is painted black over a paper element; the
## chrome one is open around its element.
func _build_air_cleaner(rig: Node3D, part: Dictionary) -> void:
	var chrome := str(part.get("style", "stock")) == "chrome"
	var shell := _mat("chrome", _CHROME, 1.0, 0.12) if chrome else _mat("cleaner", Color(0.05, 0.05, 0.06), 0.4, 0.35)
	var element := _mat("element", Color(0.85, 0.82, 0.7), 0.0, 0.9)
	var steel := _mat("steel", _STEEL, 0.6, 0.35)
	var slots := GameState.carb_slots()
	var pads: Array[Vector3] = []
	for slot in slots:
		pads.append(carb_pad(slot))
	if pads.is_empty():
		pads.append(carb_pad(GameState.SLOT_CARB))
	var r := 0.72
	if pads.size() == 2:
		r = 0.45
	elif pads.size() == 3:
		r = 0.3
	var base := _carb_height()
	var h := _cleaner_top() - base
	for pad in pads:
		var at := pad + Vector3(0.0, 0.0, base)
		_cyl_z(rig, r, r, 0.04, at, shell, 40)
		_cyl_z(rig, r * 0.92, r * 0.92, h - 0.07, at + Vector3(0.0, 0.0, 0.04), element, 40)
		if not chrome:
			_cyl_z(rig, r + 0.01, r + 0.01, h * 0.5, at + Vector3(0.0, 0.0, 0.04), shell, 40)
		_cyl_z(rig, r + 0.02, r * 0.9, 0.04, at + Vector3(0.0, 0.0, h - 0.04), shell, 40)
		_cyl_z(rig, r * 0.6, r * 0.5, 0.025, at + Vector3(0.0, 0.0, h - 0.005), shell, 40)
		_cyl_z(rig, 0.02, 0.02, h + 0.02, at, steel, 8)
	if pads.size() == 1:
		var label := Label3D.new()
		label.text = "%d V8" % GameState.engine_cid()
		label.font_size = 64
		label.pixel_size = 0.004
		label.modulate = Color(0.85, 0.12, 0.08) if not chrome else Color(0.15, 0.15, 0.15)
		label.outline_size = 0
		# Lying on the lid, read from the front of the car.
		label.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), pads[0] + Vector3(-0.46, 0.0, base + h + 0.025))
		rig.add_child(label)


# --- Plug wires ----------------------------------------------------------------------


## Where each spark plug stands out of its head, as a boot end and the direction it points.
static func plug_spots() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for side in [1.0, -1.0]:
		for i in BORES_X.size():
			var x: float = BORES_X[i] + (0.08 if side > 0.0 else -0.08)
			var dir := Vector3(0.0, side, -0.5).normalized()
			out.append(Transform3D(_axis_basis(dir), Vector3(x, PLUG_Y * side, PLUG_Z)))
	return out


## Wires from the cap's towers to the plugs, each tower to the nearest plug.
func _build_wires(rig: Node3D) -> void:
	var rubber := _mat("wire", Color(0.08, 0.07, 0.07), 0.0, 0.6)
	var boot := _mat("boot", Color(0.75, 0.3, 0.1), 0.0, 0.7)
	var plugs := plug_spots()
	var free := plugs.duplicate()
	var towers: Array[Vector3] = []
	for t in cap_towers():
		towers.append(DISTRIBUTOR_BASE + t)
	# Towers on the right go to the right bank, front ones to the front cylinders.
	towers.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y if signf(a.y) != signf(b.y) else a.x < b.x)
	for tower in towers:
		var best := 0
		for i in free.size():
			if _wire_cost(tower, free[i].origin) < _wire_cost(tower, free[best].origin):
				best = i
		var plug: Transform3D = free[best]
		free.remove_at(best)
		var side := signf(plug.origin.y)
		var out := plug.origin + plug.basis.z * 0.25
		var over := Vector3(plug.origin.x * 0.85 + tower.x * 0.15, side * WIRE_OVER.x, WIRE_OVER.y)
		var down := Vector3(plug.origin.x, side * WIRE_DOWN.x, WIRE_DOWN.y)
		var points := _bezier(tower, tower + Vector3(0.0, 0.0, 0.2), over, 8)
		points.append_array(_bezier(over, Vector3(plug.origin.x, side * WIRE_BEND.x, WIRE_BEND.y), down, 8).slice(1))
		points.append_array(_bezier(down, out + plug.basis.z * 0.25, out, 6).slice(1))
		var wire := MeshInstance3D.new()
		wire.mesh = sweep_mesh(points, 0.025, 8, false)
		wire.material_override = rubber
		rig.add_child(wire)
		var b := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.04
		bm.bottom_radius = 0.036
		bm.height = 0.25
		b.mesh = bm
		b.material_override = boot
		b.transform = Transform3D(plug.basis * Basis(Vector3.RIGHT, PI * 0.5), plug.origin + plug.basis.z * 0.125)
		rig.add_child(b)


static func _wire_cost(tower: Vector3, plug: Vector3) -> float:
	var side_miss := 0.0 if signf(tower.y - DISTRIBUTOR_BASE.y) == signf(plug.y) else 2.0
	return absf(plug.x - (tower.x - DISTRIBUTOR_BASE.x) * 9.0) + side_miss


## Tops of the distributor cap's plug towers, from its base.
static func cap_towers() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in 8:
		var a := TAU * (float(k) + 0.5) / 8.0
		out.append(Vector3(CAP_TOWER_R * cos(a), CAP_TOWER_R * sin(a), CAP_TOWER_TOP))
	return out


# --- Mesh helpers --------------------------------------------------------------------


## The fitted engine's model with only the nodes named by `prefixes` in it (`keep`), or
## with those taken out.
func _add_model_nodes(rig: Node3D, prefixes: Array[String], keep: bool) -> Node3D:
	var path := str(GameState.get_equipped_engine().get("model", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		path = _MODEL_DEFAULT
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Engine model missing: %s" % path)
		return null
	var model := packed.instantiate() as Node3D
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var named := false
		for prefix in prefixes:
			if str(node.name).begins_with(prefix):
				named = true
				break
		if named != keep:
			node.get_parent().remove_child(node)
			node.free()
	rig.add_child(model)
	return model


func _paint() -> StandardMaterial3D:
	return _mat("paint", PAINT.linear_to_srgb(), 0.65, 0.5)


func _mat(key: String, color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = mat
	return mat


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A disc or drum along -X: its back face at `x_back`, `length` toward the front.
func _cyl_x(parent: Node3D, radius: float, length: float, x_back: float, mat: Material, sides: int = 24, y: float = 0.0, z: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = sides
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.rotation = Vector3(0.0, 0.0, -PI * 0.5)
	mi.position = Vector3(x_back - length * 0.5, y, z)
	parent.add_child(mi)
	return mi


## A cylinder standing up from `bottom`.
func _cyl_z(parent: Node3D, r_bottom: float, r_top: float, height: float, bottom: Vector3, mat: Material, sides: int = 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	mi.position = bottom + Vector3(0.0, 0.0, height * 0.5)
	parent.add_child(mi)
	return mi


## A basis whose +Z points along `dir`.
static func _axis_basis(dir: Vector3) -> Basis:
	var z := dir.normalized()
	var ref := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(z).normalized()
	return Basis(x, z.cross(x), z)


static func _bezier(a: Vector3, c: Vector3, b: Vector3, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


## A round tube of `radius` along `points`, closed into a loop when `closed`.
static func sweep_mesh(points: PackedVector3Array, radius: float, sides: int, closed: bool) -> ArrayMesh:
	var n := points.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var normal := Vector3.ZERO
	for i in n:
		var a := points[(i - 1 + n) % n] if closed or i > 0 else points[i]
		var b := points[(i + 1) % n] if closed or i < n - 1 else points[i]
		var t := (b - a).normalized()
		if i == 0:
			var ref := Vector3.UP if absf(t.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			normal = t.cross(ref).normalized()
		else:
			normal = (normal - t * normal.dot(t)).normalized()
		var binormal := t.cross(normal)
		var ring := PackedVector3Array()
		for k in sides:
			var ang := TAU * float(k) / float(sides)
			ring.append(normal * cos(ang) + binormal * sin(ang))
		rings.append(ring)
	var segments := n if closed else n - 1
	for i in segments:
		var j := (i + 1) % n
		for k in sides:
			var k2 := (k + 1) % sides
			for v in [[i, k], [j, k], [j, k2], [i, k], [j, k2], [i, k2]]:
				var dir: Vector3 = rings[v[0]][v[1]]
				st.set_normal(dir)
				st.add_vertex(points[v[0]] + dir * radius)
	return st.commit()
