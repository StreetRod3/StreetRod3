extends Node3D

## An engine built up from its parts as the active car has them: the long block with
## its front drive (balancer, timing tab, pulleys, belt), the camshaft, the intake, its carburetors, the
## distributor, the air cleaner, and the plug wires. Each part is a rig under `frame`,
## keyed by `GameState.HOOD_ENGINE`, a hood slot, or `WIRES`, so the hood screen can lift
## it out on its own. Parts are built in engine units: +X toward the back of the car, +Y
## to the car's right, +Z up, the crank at Z -0.36 and the block 3 long. `frame` turns
## them into meters, standing up in the Y-up world.

## Engine models are built about four and a half times real size.
const ENGINE_SCALE := 0.22
const CRANK_Z := -0.36
const WIRES := "wires"
## The belt and what it drives off the front of the engine, which pull off like the wires.
const FRONT := "front"

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
## The camshaft lies down the valley on top of the block, running back into the
## distributor's boss, where the heads close in over it. A retainer plate holds its front
## end, with a bolt each side.
const CAM_Z := 0.8
const CAM_FRONT_X := -1.42
const CAM_BACK_X := 1.0
const CAM_BOLTS: Array[Vector3] = [Vector3(-1.32, 0.12, 0.765), Vector3(-1.32, -0.12, 0.765)]
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

## The Ford flathead, laid out as tools/make_flathead.py builds its model: measurements
## in inches there, from the crank, +X back, +Y right, +Z up; `fh()` turns them into
## engine units. Its model carries the whole engine, and its own front drive (timing
## cover, water pumps, generator, fan, belt) stays with the long block; the balancer and
## the timing tab are built here on its crank, ahead of the belt.
const FH_FAMILY := "ford-flathead"
const FH_IN := 0.0254 / ENGINE_SCALE
const FH_DECK := 10.45
const FH_DECK_OUT := 2.6
const FH_HEAD_INNER := 8.6
const FH_BANK_SHIFT := 0.5
const FH_BORES_X: Array[float] = [-6.375, -2.125, 2.125, 6.375]
const FH_PLUG_X: Array[float] = [-8.3, -2.8, 2.8, 8.3]
const FH_PLUG_IN := 3.15
## Height off the deck of the top the head bolts go into, and of the plugs' seats, by
## the heads' finish.
const FH_HEAD_TOP := {"": 1.9, "finned": 2.0}
const FH_PLUG_SEAT := {"": 1.9, "finned": 1.4}
const FH_HEAD_BOLT_X := 9.0
const FH_HEAD_BOLT_IN := 4.25
const FH_COVER_X := -12.5
const FH_BELT_X := -13.6
const FH_PULLEY_R := 3.2
## Middle of the distributor cap's face, lying forward off the cam's nose.
const FH_CAP := Vector3(-14.6, 1.8, 5.2)
const FH_CAP_R := 1.8
const FH_DIST_BOLT := Vector3(-12.5, 3.5, 5.2)
const FH_MOUNTS: Array[Vector3] = [Vector3(-11.5, 6.9, 0.0), Vector3(-11.5, -6.9, 0.0)]
## The camshaft lies on the valley floor once the intake and heads are off.
const FH_CAM := Vector3(-9.5, 9.5, 11.0)
const FH_INTAKE_TOP := 12.0
const FH_INTAKE_BOLTS: Array[Vector3] = [Vector3(-8.5, 2.92, 12.0), Vector3(8.5, -2.92, 12.0)]
## Plug wires run along the heads' inner edges, this far in from the outer edge and up.
const FH_WIRE_A := 8.0
const FH_WIRE_H := 2.5
## Model nodes that are not the long block's: they are other parts' rigs, or the crank
## pulley the balancer stands in for.
const _FH_NODES_OFF_BLOCK: Array[String] = ["cylinder_head", "spark_plug", "water_outlet", "plug_conduit", "intake_manifold", "carburetor", "carb_throat", "distributor", "pulley_crank", "crank_snout", "belt", "generator", "pulley_generator", "pulley_pump", "fan_"]
## The flathead's front drive in its model: belt, generator, fan, and the pulleys the belt
## turns. The water pump housings stay on the block.
const _FH_NODES_FRONT: Array[String] = ["belt", "generator", "pulley_generator", "pulley_pump", "fan_"]
const _FH_NODES_HEADS: Array[String] = ["cylinder_head", "spark_plug", "water_outlet", "plug_conduit"]

## The Chevy small-block, laid out as tools/make_sbc.py builds its model (in inches from
## the crank as the flathead's are, `fh()` turning them into engine units). Its model
## carries the stock parts: the iron intake with its thermostat housing, coil and oil
## filler, the four-barrel, the 14 inch air cleaner, the distributor, the plugs and the
## cast-iron exhaust manifolds; headers are models of their own. The balancer and the
## timing tab are built here on its crank.
const SB_FAMILY := "chevy-sbc"
const SB_BORE_MID := -0.49
const SB_BANK_SHIFT := 0.425
const SB_BORES_X: Array[float] = [-6.6, -2.2, 2.2, 6.6]
## The block's back face, where the transmission's bell housing bolts on.
const SB_BLOCK_BACK := 10.6
## The carb pad's top, the carburetor's top where the air cleaner sits, and the stock
## cleaner's wing nut top and radius.
const SB_PAD := Vector3(-0.45, 0.0, 13.55)
const SB_CARB_TOP := 16.7
const SB_WINGNUT_TOP := 21.1
const SB_CLEANER_R := 7.3
## The distributor's axis at the cap's foot, its towers' ring and tops, and the clamp bolt.
const SB_DIST := Vector3(8.87, 1.55, 13.0)
const SB_TOWER_R := 1.2
const SB_TOWER_TOP := 17.3
const SB_CLAMP_BOLT := Vector3(7.32, 1.55, 11.75)
## Where the plugs leave the right head's exhaust face (y, z), their way out on the right
## (mirrored on the left), and how far out along it the boots start.
const SB_PLUG_EXIT := Vector2(9.061, 5.541)
const SB_PLUG_DIR := Vector3(0.231, 0.963, -0.14)
const SB_PLUG_BOOT := 0.9
## Plug wires leave the cap out sideways behind the air cleaner (`SB_WIRE_BACK`: along,
## out from the middle, height), run forward over the valve cover, out past the exhaust
## and down to the plugs, as (out from the middle, height).
const SB_WIRE_BACK := Vector3(7.6, 5.5, 15.6)
const SB_WIRE_OVER := Vector2(7.5, 14.4)
const SB_WIRE_BEND := Vector2(13.0, 11.8)
const SB_WIRE_DOWN := Vector2(13.3, 8.2)
## Intake bolts: the right flange's front one and the left's back one, on the flange's
## face (y, z) and square to it.
const SB_INTAKE_BOLT_X := 9.42
const SB_INTAKE_BOLT := Vector2(3.674, 11.178)
const SB_INTAKE_NORMAL := Vector2(-0.615, 0.788)
## Head bolts, front and back on the intake face above the intake's flange.
const SB_HEAD_BOLT_X := 8.8
const SB_HEAD_BOLT := Vector2(5.289, 11.627)
## The mount pads' bolt bosses on the block's sides, and their way out.
const SB_MOUNT_X := -6.2
const SB_MOUNT := Vector2(6.037, 1.054)
const SB_MOUNT_NORMAL := Vector2(0.636, -0.772)
## The camshaft lies in the valley once the intake is off: front, back, height.
const SB_CAM := Vector3(-9.3, 8.3, 9.45)
const SB_COVER_X := -11.4
const SB_BELT_X := -13.35
const SB_PULLEY_R := 3.2
## For the aftermarket intakes: where a runner meets its port on each head (out from the
## middle, height, and how steeply it climbs out of it), the floor over the valley
## (bottom, top, half wide), the thermostat housing's place, and the distributor's boss.
const SB_PORT := Vector3(4.15, 10.5, 53.0)
const SB_FLOOR := Vector3(9.81, 10.65, 3.0)
const SB_THERMOSTAT := Vector2(-8.9, 0.06)
const SB_DIST_BOSS_TOP := 10.95
const SB_HEADERS := {
	"shorty": "res://assets/parts/sbc-headers-shorty.glb",
	"long-tube": "res://assets/parts/sbc-headers-long.glb",
}
const _SB_NODES_HEADS: Array[String] = ["cylinder_head", "valve_cover", "valve_bolt", "spark_plug"]
const _SB_NODES_INTAKE: Array[String] = ["intake_manifold", "thermostat", "ignition_coil", "oil_filler"]
const _SB_NODES_CARB: Array[String] = ["carburetor", "carb_throat"]
const _SB_NODES_DISTRIBUTOR: Array[String] = ["distributor"]
const _SB_NODES_CLEANER: Array[String] = ["air_cleaner"]
const _SB_NODES_FRONT: Array[String] = ["belt", "alternator", "upper_pulley", "fan_", "accessory_bracket"]
## The crank's own balancer and pulley, which the built balancer stands in for, and the
## exhaust, which goes on with the heads.
const _SB_NODES_BALANCER: Array[String] = ["harmonic_balancer", "crank_pulley", "crank_bolt"]
const _SB_NODES_EXHAUST: Array[String] = ["exhaust"]

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
## A rival's engine, shown instead of the car in the garage. Empty slots mean the garage car.
var _spec_on: bool = false
var _spec_engine: Dictionary = {}
var _spec_slots: Dictionary = {}


func _init() -> void:
	frame = Node3D.new()
	frame.name = "EngineFrame"
	frame.rotation.x = -PI * 0.5
	frame.scale = Vector3.ONE * ENGINE_SCALE
	add_child(frame)


## Show `engine` with hood `slots` (part dictionaries keyed by slot) instead of the garage car.
func show_spec(engine: Dictionary, slots: Dictionary) -> void:
	_spec_on = true
	_spec_engine = engine
	_spec_slots = slots


## A point of the flathead in inches as engine units.
static func fh(p: Vector3) -> Vector3:
	return Vector3(p.x * FH_IN, p.y * FH_IN, p.z * FH_IN + CRANK_Z)


## A point on the flathead's bank `side` (+1 right): `x` along the head from its middle,
## `a` in across the deck from its outer edge, `h` up off the deck, as engine units.
static func fh_head(side: float, x: float, a: float, h: float) -> Vector3:
	var s45 := sqrt(0.5)
	var up := Vector2(side * s45, s45)
	var across := Vector2(-side * s45, s45)
	var p := up * FH_DECK - across * FH_DECK_OUT + across * a + up * h
	return fh(Vector3(x - side * FH_BANK_SHIFT, p.x, p.y))


## Straight up out of a flathead head's deck on bank `side`.
static func fh_head_up(side: float) -> Vector3:
	return Vector3(0.0, side, 1.0).normalized()


## Whether the engine on view is a Ford flathead.
func is_flathead() -> bool:
	return GameState.engine_family(_view_engine()) == FH_FAMILY


## Whether the engine on view is the Chevy small-block, drawn from its own model.
func is_sbc() -> bool:
	return GameState.engine_family(_view_engine()) == SB_FAMILY


## A small-block point on bank `side` (+1 right): `x` along the engine as the bores are
## numbered, moved to that bank's bores, in inches.
static func sb_bank_x(side: float, x: float) -> float:
	return x + SB_BORE_MID + side * SB_BANK_SHIFT


## Where the balancer's back face is along the crank, and the crank pulley's belt line.
func balancer_x() -> float:
	if is_flathead():
		return fh(Vector3(FH_BELT_X, 0.0, 0.0)).x - 0.05
	return fh(Vector3(SB_COVER_X, 0.0, 0.0)).x if is_sbc() else COVER_X


func belt_x() -> float:
	if is_flathead():
		return fh(Vector3(FH_BELT_X, 0.0, 0.0)).x
	return fh(Vector3(SB_BELT_X, 0.0, 0.0)).x if is_sbc() else BELT_X


func _view_engine() -> Dictionary:
	if _spec_on:
		return _spec_engine
	return GameState.get_equipped_engine()


func _view_part(key: String) -> Dictionary:
	if _spec_on:
		var part: Variant = _spec_slots.get(key, {})
		if part is Dictionary:
			return part
		return {}
	return GameState.slot_part(key)


func _view_fitted(key: String) -> bool:
	if _spec_on:
		if key == GameState.HOOD_ENGINE:
			return not _spec_engine.is_empty()
		return not _view_part(key).is_empty()
	return GameState.is_hood_part_fitted(key)


func _view_wires() -> bool:
	if _spec_on:
		return true
	return GameState.plug_wires


func _view_front() -> bool:
	if _spec_on:
		return true
	return GameState.front_drive


func _view_head_count() -> int:
	return GameState.heads_on(_view_engine())


func _view_carb_slots() -> Array[String]:
	if not _spec_on:
		return GameState.carb_slots()
	var out: Array[String] = []
	var intake := _view_part(GameState.SLOT_INTAKE)
	if intake.is_empty():
		return out
	for i in clampi(int(intake.get("carbs", 1)), 1, GameState.CARB_SLOTS.size()):
		out.append(GameState.CARB_SLOTS[i])
	return out


## Builds every part the active car has.
func build() -> void:
	for key: String in rigs.keys():
		(rigs[key] as Node3D).queue_free()
	rigs.clear()
	balancer = null
	for key in all_keys():
		rebuild(key)


static func all_keys() -> Array[String]:
	var keys: Array[String] = [GameState.HOOD_ENGINE, FRONT]
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
		FRONT:
			_build_front(rig)
		GameState.SLOT_CAM:
			_build_cam(rig, _view_part(key))
		GameState.SLOT_HEADS:
			_build_heads(rig, _view_part(key))
		GameState.SLOT_INTAKE:
			_build_intake(rig, _view_part(key))
		GameState.SLOT_DISTRIBUTOR:
			_build_distributor(rig, _view_part(key))
		GameState.SLOT_AIR_CLEANER:
			_build_air_cleaner(rig, _view_part(key))
		WIRES:
			_build_wires(rig)
		_:
			_build_carb(rig, _view_part(key), carb_pad(key))
	return rig


func _present(key: String) -> bool:
	if key == FRONT:
		return _view_fitted(GameState.HOOD_ENGINE) and _view_front()
	if key == WIRES:
		return _view_fitted(GameState.HOOD_ENGINE) and _view_wires() and not _view_part(GameState.SLOT_DISTRIBUTOR).is_empty() and not _view_part(GameState.SLOT_HEADS).is_empty()
	return _view_fitted(key)


## Where each bolt of a part goes, in engine units: origin at the hole, +Z out of it.
func bolt_spots(key: String) -> Array[Transform3D]:
	if is_flathead():
		return _fh_bolt_spots(key)
	if is_sbc():
		return _sb_bolt_spots(key)
	var out: Array[Transform3D] = []
	match key:
		GameState.HOOD_ENGINE:
			for p in MOUNT_BOLTS:
				out.append(Transform3D(Basis.IDENTITY, p))
		GameState.SLOT_CAM:
			for p in CAM_BOLTS:
				out.append(Transform3D(Basis.IDENTITY, p))
		GameState.SLOT_HEADS:
			var slope := HEAD_DECK_OUT - HEAD_DECK_IN
			var z := HEAD_DECK_IN.y + slope.y * (HEAD_BOLT_Y - HEAD_DECK_IN.x) / slope.x
			for side in head_sides():
				var normal := Vector3(0.0, -slope.y * side, slope.x).normalized()
				for x: float in [-HEAD_BOLT_X, HEAD_BOLT_X]:
					out.append(Transform3D(_axis_basis(normal), Vector3(x, HEAD_BOLT_Y * side, z)))
		GameState.SLOT_INTAKE:
			for p in INTAKE_BOLTS:
				out.append(Transform3D(Basis.IDENTITY, p))
		GameState.SLOT_DISTRIBUTOR:
			out.append(Transform3D(Basis.IDENTITY, CLAMP_BOLT))
		GameState.SLOT_AIR_CLEANER:
			for slot in _view_carb_slots():
				out.append(Transform3D(Basis.IDENTITY, carb_pad(slot) + Vector3(0.0, 0.0, _cleaner_top())))
		_:
			if GameState.CARB_SLOTS.has(key):
				# Two nuts on opposite corners of the base, front one first.
				var four := int(_view_part(GameState.SLOT_INTAKE).get("barrels", 4)) == 4
				var nut := Vector3(0.25, 0.2, 0.25) if four else Vector3(0.15, 0.21, 0.09)
				for corner: Vector3 in [Vector3(-nut.x, -nut.y, nut.z), nut]:
					out.append(Transform3D(Basis.IDENTITY, carb_pad(key) + corner))
	return out


func _fh_bolt_spots(key: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	match key:
		GameState.HOOD_ENGINE:
			for p in FH_MOUNTS:
				out.append(Transform3D(Basis.IDENTITY, fh(p)))
		GameState.SLOT_CAM:
			for y: float in [-0.12, 0.12]:
				out.append(Transform3D(Basis.IDENTITY, fh(Vector3(FH_CAM.x + 1.0, 0.0, FH_CAM.z)) + Vector3(0.0, y, -0.035)))
		GameState.SLOT_HEADS:
			var top := float(FH_HEAD_TOP.get(str(_view_part(GameState.SLOT_HEADS).get("finish", "")), FH_HEAD_TOP[""]))
			for side in head_sides():
				for x: float in [-FH_HEAD_BOLT_X, FH_HEAD_BOLT_X]:
					var at := fh_head(side, x, FH_HEAD_INNER - FH_HEAD_BOLT_IN, top)
					out.append(Transform3D(_axis_basis(fh_head_up(side)), at))
		GameState.SLOT_INTAKE:
			var lift := 0.45 if str(_view_part(GameState.SLOT_INTAKE).get("style", "")) == "flathead-3x2" else 0.0
			for p in FH_INTAKE_BOLTS:
				out.append(Transform3D(Basis.IDENTITY, fh(p + Vector3(0.0, 0.0, lift))))
		GameState.SLOT_DISTRIBUTOR:
			out.append(Transform3D(_axis_basis(Vector3(-1.0, 0.0, 0.0)), fh(FH_DIST_BOLT)))
		GameState.SLOT_AIR_CLEANER:
			for slot in _view_carb_slots():
				out.append(Transform3D(Basis.IDENTITY, carb_pad(slot) + Vector3(0.0, 0.0, _cleaner_top())))
		_:
			if GameState.CARB_SLOTS.has(key):
				for corner: Vector3 in [Vector3(-0.15, -0.21, 0.09), Vector3(0.15, 0.21, 0.09)]:
					out.append(Transform3D(Basis.IDENTITY, carb_pad(key) + corner))
	return out


func _sb_bolt_spots(key: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	match key:
		GameState.HOOD_ENGINE:
			for side: float in [1.0, -1.0]:
				var normal := Vector3(0.0, SB_MOUNT_NORMAL.x * side, SB_MOUNT_NORMAL.y)
				out.append(Transform3D(_axis_basis(normal), fh(Vector3(SB_MOUNT_X, SB_MOUNT.x * side, SB_MOUNT.y))))
		GameState.SLOT_CAM:
			for y: float in [-1.0, 1.0]:
				out.append(Transform3D(Basis.IDENTITY, fh(Vector3(SB_CAM.x + 0.8, y, SB_CAM.z + 0.4))))
		GameState.SLOT_HEADS:
			for side in head_sides():
				var normal := Vector3(0.0, SB_INTAKE_NORMAL.x * side, SB_INTAKE_NORMAL.y)
				for x: float in [-SB_HEAD_BOLT_X, SB_HEAD_BOLT_X]:
					out.append(Transform3D(_axis_basis(normal), fh(Vector3(sb_bank_x(side, x), SB_HEAD_BOLT.x * side, SB_HEAD_BOLT.y))))
		GameState.SLOT_INTAKE:
			for side: float in [1.0, -1.0]:
				var normal := Vector3(0.0, SB_INTAKE_NORMAL.x * side, SB_INTAKE_NORMAL.y)
				var at := Vector3(sb_bank_x(side, -SB_INTAKE_BOLT_X * side), SB_INTAKE_BOLT.x * side, SB_INTAKE_BOLT.y)
				out.append(Transform3D(_axis_basis(normal), fh(at)))
		GameState.SLOT_DISTRIBUTOR:
			out.append(Transform3D(Basis.IDENTITY, fh(SB_CLAMP_BOLT)))
		GameState.SLOT_AIR_CLEANER:
			for slot in _view_carb_slots():
				out.append(Transform3D(Basis.IDENTITY, carb_pad(slot) + Vector3(0.0, 0.0, _cleaner_top())))
		_:
			if GameState.CARB_SLOTS.has(key):
				var four := int(_view_part(GameState.SLOT_INTAKE).get("barrels", 4)) == 4
				var nut := Vector3(2.58, 2.58, 0.75) * FH_IN if four else Vector3(0.15, 0.21, 0.09)
				for corner: Vector3 in [Vector3(-nut.x, -nut.y, nut.z), nut]:
					out.append(Transform3D(Basis.IDENTITY, carb_pad(key) + corner))
	return out


## The carburetor pads of an intake style on the engine on view, front to back.
func pads_for(style: String) -> Array[Vector3]:
	if is_sbc():
		match style:
			"highrise":
				return [fh(SB_PAD + Vector3(0.0, 0.0, 1.0))]
			"tripower":
				return [fh(Vector3(-5.6, 0.0, SB_PAD.z + 0.6)), fh(Vector3(SB_PAD.x, 0.0, SB_PAD.z + 0.6)), fh(Vector3(4.7, 0.0, SB_PAD.z + 0.6))]
			"dualquad":
				return [fh(Vector3(-5.6, 0.0, SB_PAD.z + 1.0)), fh(Vector3(2.6, 0.0, SB_PAD.z + 1.0))]
		return [fh(SB_PAD)]
	match style:
		"flathead":
			return [fh(Vector3(0.0, 0.0, FH_INTAKE_TOP + 1.8))]
		"flathead-3x2":
			return [fh(Vector3(-5.0, 0.0, FH_INTAKE_TOP + 2.7)), fh(Vector3(0.0, 0.0, FH_INTAKE_TOP + 2.7)), fh(Vector3(5.0, 0.0, FH_INTAKE_TOP + 2.7))]
		"highrise":
			return [Vector3(0.0, 0.0, 1.26)]
		"tripower":
			return [Vector3(-0.58, 0.0, 1.24), Vector3(0.0, 0.0, 1.24), Vector3(0.58, 0.0, 1.24)]
		"dualquad":
			return [Vector3(-0.42, 0.0, 1.3), Vector3(0.42, 0.0, 1.3)]
	return [IRON_PAD]


## The pad a carburetor slot sits on, on the fitted intake.
func carb_pad(slot: String) -> Vector3:
	var pads := pads_for(str(_view_part(GameState.SLOT_INTAKE).get("style", "iron4")))
	return pads[clampi(GameState.CARB_SLOTS.find(slot), 0, pads.size() - 1)]


## Height of a carburetor's air horn above its pad.
func _carb_height() -> float:
	var four := int(_view_part(GameState.SLOT_INTAKE).get("barrels", 4)) == 4
	if four and is_sbc():
		return (SB_CARB_TOP - SB_PAD.z) * FH_IN
	return 0.48 if four else 0.36


## Height of an air cleaner's top above the pad: the stock small-block cleaner's wing nut.
func _cleaner_top() -> float:
	if is_sbc() and _sb_stock_cleaner():
		return (SB_WINGNUT_TOP - SB_PAD.z) * FH_IN
	return _carb_height() + 0.32


## Whether the small-block's own air cleaner is the one on: the stock cleaner on its one
## four-barrel.
func _sb_stock_cleaner() -> bool:
	return str(_view_part(GameState.SLOT_AIR_CLEANER).get("style", "stock")) == "stock" and _view_carb_slots().size() <= 1 and int(_view_part(GameState.SLOT_INTAKE).get("barrels", 4)) == 4


## The balancer's turn that puts its mark at `degrees` of timing on the tab.
static func mark_angle(degrees: float) -> float:
	return deg_to_rad(TAB_ZERO_DEG - degrees * TAB_ARC_PER_DEG)


# --- Engine and front drive ------------------------------------------------------


func _build_engine(rig: Node3D) -> void:
	if is_flathead():
		_build_flathead_block(rig)
		return
	if is_sbc():
		_build_sbc_block(rig)
		return
	var leave: Array[String] = []
	for nodes: Array[String] in [_NODES_HEADS, _NODES_INTAKE, _NODES_CARB, _NODES_DISTRIBUTOR, _NODES_FRONT_DRIVE]:
		leave.append_array(nodes)
	_add_model_nodes(rig, leave, false)
	var steel := _mat("steel", _STEEL, 0.6, 0.35)
	var rubber := _mat("rubber", _RUBBER, 0.0, 0.85)
	var paint := _paint()
	# The boss in the valley behind the intake that the distributor stands in.
	_box(rig, Vector3(0.5, 0.2, DISTRIBUTOR_BASE.z - 0.7), Vector3((DISTRIBUTOR_BASE.x + CLAMP_BOLT.x) * 0.5, 0.0, (DISTRIBUTOR_BASE.z + 0.7) * 0.5), paint)
	# Mount ears off the block's front corners, on rubber mounts below.
	for p in MOUNT_BOLTS:
		_box(rig, Vector3(0.18, 0.2, 0.06), Vector3(p.x + 0.02, p.y, p.z - 0.03), steel)
		_box(rig, Vector3(0.14, 0.16, 0.12), Vector3(p.x, p.y, p.z - 0.12), rubber)
	_build_balancer(rig, 0.3)
	# Water pump above the crank. Its pulley is the front drive's.
	_cyl_x(rig, 0.17, 0.3, COVER_X, paint, 24, PUMP_CENTER.x, PUMP_CENTER.y)
	_cyl_x(rig, 0.06, 0.06, COVER_X - 0.3, steel, 12, PUMP_CENTER.x, PUMP_CENTER.y)


## The belt and what it drives: on a flathead its model's belt, generator, fan and
## pulleys; on the others the water pump pulley, the alternator on its bracket, and the belt.
func _build_front(rig: Node3D) -> void:
	if is_flathead():
		_add_model_filtered(rig, _model_path(), func(n: String) -> bool: return _begins_any(n, _FH_NODES_FRONT))
		return
	if is_sbc():
		_add_model_nodes(rig, _SB_NODES_FRONT, true)
		return
	var steel := _mat("steel", _STEEL, 0.6, 0.35)
	var dark := _mat("dark", Color(0.12, 0.12, 0.12), 0.6, 0.5)
	var rubber := _mat("rubber", _RUBBER, 0.0, 0.85)
	_cyl_x(rig, 0.3, 0.08, BELT_X + 0.04, steel, 36, PUMP_CENTER.x, PUMP_CENTER.y)
	# Alternator on the right, on a bracket off the head.
	_cyl_x(rig, 0.26, 0.48, -1.28, _mat("alternator", Color(0.62, 0.62, 0.6), 0.6, 0.45), 24, ALTERNATOR_CENTER.x, ALTERNATOR_CENTER.y)
	_cyl_x(rig, 0.04, 0.2, -1.76, steel, 10, ALTERNATOR_CENTER.x, ALTERNATOR_CENTER.y)
	_cyl_x(rig, 0.14, 0.08, BELT_X + 0.04, steel, 24, ALTERNATOR_CENTER.x, ALTERNATOR_CENTER.y)
	_box(rig, Vector3(0.04, 0.3, 0.08), Vector3(-1.56, 0.82, 0.62), dark)
	# Fan belt around the three pulleys.
	var hull := PackedVector2Array()
	for c: Array in [[Vector2(0.0, CRANK_Z), 0.3], [PUMP_CENTER, 0.3], [ALTERNATOR_CENTER, 0.14]]:
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


## The flathead's long block from its model, less the other parts' nodes and its crank
## pulley, with mount ears off the front corners and the balancer on the crank.
func _build_flathead_block(rig: Node3D) -> void:
	_add_model_filtered(rig, _model_path(), func(n: String) -> bool: return not _begins_any(n, _FH_NODES_OFF_BLOCK))
	var steel := _mat("steel", _STEEL, 0.6, 0.35)
	var rubber := _mat("rubber", _RUBBER, 0.0, 0.85)
	for p in FH_MOUNTS:
		var at := fh(p)
		_box(rig, Vector3(0.18, 0.2, 0.06), at + Vector3(0.02, 0.0, -0.03), steel)
		_box(rig, Vector3(0.14, 0.16, 0.12), at + Vector3(0.0, 0.0, -0.12), rubber)
	# The crank's snout from the timing cover out to the balancer.
	var cover := fh(Vector3(FH_COVER_X, 0.0, 0.0)).x
	_cyl_x(rig, 0.1, cover - balancer_x(), cover, steel, 16, 0.0, CRANK_Z)
	_build_balancer(rig, FH_PULLEY_R * FH_IN)


## The small-block's long block from its model, less the other parts' nodes and its own
## balancer and crank pulley, with the balancer built on the crank. Its mount pads are
## cast on the block's sides.
func _build_sbc_block(rig: Node3D) -> void:
	var leave: Array[String] = []
	for nodes: Array[String] in [_SB_NODES_HEADS, _SB_NODES_INTAKE, _SB_NODES_CARB, _SB_NODES_DISTRIBUTOR, _SB_NODES_CLEANER, _SB_NODES_FRONT, _SB_NODES_BALANCER, _SB_NODES_EXHAUST]:
		leave.append_array(nodes)
	_add_model_nodes(rig, leave, false)
	_build_balancer(rig, SB_PULLEY_R * FH_IN)


## Balancer: steel hub, rubber ring, steel rim with the mark across its face, its back at
## `balancer_x()`, and the crank pulley of `pulley_r` on the belt line; and the timing tab.
func _build_balancer(rig: Node3D, pulley_r: float) -> void:
	var steel := _mat("steel", _STEEL, 0.6, 0.35)
	var dark := _mat("dark", Color(0.12, 0.12, 0.12), 0.6, 0.5)
	var rubber := _mat("rubber", _RUBBER, 0.0, 0.85)
	var white := _mat("mark", Color(0.95, 0.95, 0.9), 0.0, 0.5)
	var bx := balancer_x()
	balancer = Node3D.new()
	balancer.name = "Balancer"
	balancer.position = Vector3(0.0, 0.0, CRANK_Z)
	rig.add_child(balancer)
	_cyl_x(balancer, BALANCER_R, 0.16, bx - 0.01, steel, 40)
	_cyl_x(balancer, BALANCER_R - 0.06, 0.012, bx - 0.17, rubber, 40)
	_cyl_x(balancer, BALANCER_R - 0.08, 0.02, bx - 0.18, steel, 40)
	_cyl_x(balancer, 0.12, 0.14, bx - 0.17, dark, 20)
	# The mark: a white line on the face out to the rim, and on across the rim.
	var mark_face := _box(balancer, Vector3(0.016, 0.045, 0.12), Vector3(bx - 0.19, 0.0, BALANCER_R - 0.055), white)
	mark_face.name = "MarkFace"
	var mark_rim := _box(balancer, Vector3(0.16, 0.045, 0.012), Vector3(bx - 0.09, 0.0, BALANCER_R + 0.003), white)
	mark_rim.name = "MarkRim"
	# Crank pulley on the hub, in line with the belt.
	var belt := belt_x()
	_cyl_x(balancer, pulley_r, 0.035, belt + 0.04, steel, 36)
	_cyl_x(balancer, pulley_r - 0.06, 0.02, belt + 0.01, steel, 36)
	_cyl_x(balancer, pulley_r, 0.035, belt - 0.025, steel, 36)
	_build_timing_tab(rig)


## Plate over the balancer's rim with a mark each two degrees, 0 to 20 before top dead
## center and a few after, numbered every ten.
func _build_timing_tab(rig: Node3D) -> void:
	var steel := _mat("tab", Color(0.3, 0.3, 0.3), 0.7, 0.4)
	var white := _mat("mark", Color(0.95, 0.95, 0.9), 0.0, 0.5)
	var x := balancer_x() - 0.2
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


# --- Camshaft ----------------------------------------------------------------------


## A shaft with an intake and an exhaust lobe for each cylinder of each bank, turned to
## different angles. A racing cam has taller lobes and is polished.
func _build_cam(rig: Node3D, part: Dictionary) -> void:
	var racing := str(part.get("style", "stock")) == "racing"
	var metal := _mat("cam_racing", _CHROME, 0.9, 0.2) if racing else _mat("steel", _STEEL, 0.6, 0.35)
	var lobe_r := 0.09 if racing else 0.075
	var flathead := is_flathead()
	var sbc := is_sbc()
	var cam_z := fh(FH_CAM).z if flathead else CAM_Z
	var front := fh(FH_CAM).x if flathead else CAM_FRONT_X
	var back := fh(Vector3(FH_CAM.y, 0.0, 0.0)).x if flathead else CAM_BACK_X
	if sbc:
		cam_z = fh(SB_CAM).z
		front = fh(SB_CAM).x
		back = SB_CAM.y * FH_IN
	_cyl_x(rig, 0.045, back - front, back, metal, 12, 0.0, cam_z)
	var bores: Array[float] = []
	for b in (FH_BORES_X if flathead else SB_BORES_X if sbc else BORES_X):
		bores.append(b * FH_IN if flathead or sbc else b)
	var phase := 0.0
	for bore in bores:
		for offset: float in [-0.21, -0.07, 0.07, 0.21]:
			var turned := Node3D.new()
			turned.position = Vector3(bore + offset, 0.0, cam_z)
			turned.rotation.x = phase
			rig.add_child(turned)
			var lobe := _cyl_x(turned, lobe_r, 0.07, 0.035, metal, 16)
			lobe.scale.x = 0.62
			phase += 2.4
	var plate := bolt_spots(GameState.SLOT_CAM)[0].origin if flathead or sbc else CAM_BOLTS[0]
	_box(rig, Vector3(0.14, 0.36, 0.03), Vector3(plate.x, 0.0, plate.z - 0.015), _mat("steel", _STEEL, 0.6, 0.35))


# --- Heads -------------------------------------------------------------------------


## The banks the engine has heads on, by side: +1 on the right, -1 on the left. One head
## on an inline engine is the right-hand one.
func head_sides() -> Array[float]:
	var sides: Array[float] = [1.0]
	if _view_head_count() >= 2:
		sides.append(-1.0)
	return sides


## Each head with its valve cover, in a node of its own (`Head_1`, `Head_-1`) so the
## hood screen can tell them apart. Aluminum heads are left bare.
func _build_heads(rig: Node3D, part: Dictionary) -> void:
	if is_flathead():
		_build_flathead_heads(rig, part)
		return
	var aluminum := str(part.get("finish", "")) == "aluminum"
	var sbc := is_sbc()
	for side in head_sides():
		var bank := "%d" % int(side)
		var head := Node3D.new()
		head.name = "Head_%s" % bank
		rig.add_child(head)
		var nodes: Array[String] = ["cylinder_head_" + bank, "valve_cover_" + bank, "valve_bolt_%s_" % bank]
		if sbc:
			# The small-block's covers, bolts and plugs are in pieces named by bank, and
			# the exhaust bolts to the head.
			nodes = []
			for prefix in _SB_NODES_HEADS:
				nodes.append("%s_%s" % [prefix, bank])
			for prefix: String in ["cylinder_head_holes", "valve_cover_body", "valve_cover_top", "valve_bolt_bar", "spark_plug_base", "spark_plug_tip"]:
				nodes.append("%s_%s" % [prefix, bank])
			_build_sbc_exhaust(head, side)
		var model := _add_model_nodes(head, nodes, true)
		if model == null or not aluminum:
			continue
		var casting := model.find_child("cylinder_head_" + bank, true, false) as MeshInstance3D
		if casting != null:
			casting.material_override = _mat("aluminum", _ALUMINUM, 0.75, 0.35)


## The small-block's exhaust on bank `side` as the car's manifold part has it: the cast-iron
## manifold from the engine's model, or the headers' own model; none with no part on.
func _build_sbc_exhaust(head: Node3D, side: float) -> void:
	var manifold := _view_part(GameState.SLOT_MANIFOLD)
	if manifold.is_empty():
		return
	var bank := "%d" % int(side)
	var style := str(manifold.get("style", "log"))
	var path := str(SB_HEADERS.get(style, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		_add_model_filtered(head, _model_path(), func(n: String) -> bool: return n.begins_with("exhaust_manifold") and first_number(n) == bank)
		return
	# A header node's bank is the first number in its name.
	_add_model_filtered(head, path, func(n: String) -> bool: return first_number(n) == bank)


## The first part of `node_name` between underscores that is a number, or "".
static func first_number(node_name: String) -> String:
	for bit in node_name.split("_"):
		if bit.is_valid_int():
			return bit
	return ""


## A flathead's heads from the part's own model, or the engine's for the stock ones: each
## bank's nodes (their names end in its side) in a node of its own.
func _build_flathead_heads(rig: Node3D, part: Dictionary) -> void:
	var path := _part_model(part)
	for side in head_sides():
		var bank := "%d" % int(side)
		var head := Node3D.new()
		head.name = "Head_%s" % bank
		rig.add_child(head)
		_add_model_filtered(head, path, func(n: String) -> bool: return _begins_any(n, _FH_NODES_HEADS) and n.get_slice("_", n.get_slice_count("_") - 1) == bank)


# --- Intake ------------------------------------------------------------------------


func _build_intake(rig: Node3D, part: Dictionary) -> void:
	var style := str(part.get("style", "iron4"))
	if is_sbc():
		if style == "iron4":
			_add_model_nodes(rig, _SB_NODES_INTAKE, true)
		else:
			_build_sbc_intake(rig, style)
		return
	if style == "iron4":
		_add_model_nodes(rig, _NODES_INTAKE, true)
		return
	if style.begins_with("flathead"):
		_add_model_filtered(rig, _part_model(part), func(n: String) -> bool: return n.begins_with("intake_manifold"))
		return
	var metal := _paint() if style == "tripower" else _mat("aluminum", _ALUMINUM, 0.75, 0.35)
	var pads := pads_for(style)
	var front := pads[0].x - 0.36
	var back := pads[pads.size() - 1].x + 0.36
	var top := pads[0].z
	var floor_z := INTAKE_FLOOR
	# Runners from the plenum out to each port on the heads, four a side.
	for side: float in [-1.0, 1.0]:
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


## An aftermarket intake on the small-block: the floor over the valley on the block's end
## walls, a runner out of each port on the heads' intake faces up into the plenum, the
## plenum and its pads, the distributor's boss behind, and the thermostat housing in front.
func _build_sbc_intake(rig: Node3D, style: String) -> void:
	var metal := _paint() if style == "tripower" else _mat("aluminum", _ALUMINUM, 0.75, 0.35)
	var pads := pads_for(style)
	var top := pads[0].z
	var half_y := SB_FLOOR.z * FH_IN
	var floor_top := fh(Vector3(0.0, 0.0, SB_FLOOR.y)).z
	var floor_bottom := fh(Vector3(0.0, 0.0, SB_FLOOR.x)).z
	var ends := Vector2(fh(Vector3(-10.5, 0.0, 0.0)).x, fh(Vector3(10.5, 0.0, 0.0)).x)
	_box(rig, Vector3(ends.y - ends.x, half_y * 2.0, floor_top - floor_bottom), Vector3((ends.x + ends.y) * 0.5, 0.0, (floor_top + floor_bottom) * 0.5), metal)
	var front := pads[0].x - 0.3
	var back := pads[pads.size() - 1].x + 0.3
	var width := half_y * 1.4
	var climb := deg_to_rad(SB_PORT.z)
	for side: float in [-1.0, 1.0]:
		for bx in SB_BORES_X:
			var port := fh(Vector3(sb_bank_x(side, bx), SB_PORT.x * side, SB_PORT.y))
			var out := Vector3(0.0, -side * cos(climb), sin(climb))
			var rise := port + out * 0.12
			var root := Vector3(clampf(port.x * 0.6, front + 0.1, back - 0.1), width * 0.35 * side, top - 0.12)
			var runner := MeshInstance3D.new()
			runner.mesh = sweep_mesh(_bezier(port, rise + Vector3(0.0, 0.0, 0.12), root, 10), 0.085, 12, false)
			runner.material_override = metal
			rig.add_child(runner)
			# The runner's flange square to it on the head's face.
			var flange := _box(rig, Vector3(0.22, 0.24, 0.04), port, metal)
			flange.basis = _axis_basis(out)
	# Plenum and the pads on top.
	_box(rig, Vector3(back - front, width, top - floor_top), Vector3((front + back) * 0.5, 0.0, (top + floor_top) * 0.5 - 0.02), metal)
	for pad in pads:
		var size := Vector3(0.62, 0.62, 0.04) if style != "tripower" else Vector3(0.46, 0.5, 0.04)
		_box(rig, size, pad - Vector3(0.0, 0.0, 0.02), metal)
	if style == "dualquad":
		# Cast fins across the plenum between the carburetors.
		var mid := (pads[0].x + pads[1].x) * 0.5
		for i in 5:
			_box(rig, Vector3(0.025, width + 0.04, 0.06), Vector3(mid + lerpf(-0.16, 0.16, float(i) / 4.0), 0.0, top - 0.1), metal)
	# The distributor's boss, the bolts' bosses, and the thermostat housing with its neck.
	var boss := fh(Vector3(SB_DIST.x, SB_DIST.y, 0.0))
	_cyl_z(rig, 0.15, 0.13, fh(Vector3(0.0, 0.0, SB_DIST_BOSS_TOP)).z - floor_top + 0.01, Vector3(boss.x, boss.y, floor_top - 0.01), metal, 24)
	for spot in _sb_bolt_spots(GameState.SLOT_INTAKE):
		var b := _box(rig, Vector3(0.12, 0.12, 0.04), spot.origin - spot.basis.z * 0.02, metal)
		b.basis = spot.basis
	var stat := fh(Vector3(SB_THERMOSTAT.x, SB_THERMOSTAT.y, 0.0))
	var stat_top := fh(Vector3(0.0, 0.0, SB_FLOOR.y + 1.6)).z
	_box(rig, Vector3(0.3, 0.32, stat_top - floor_top), Vector3(stat.x, stat.y, (stat_top + floor_top) * 0.5), metal)
	_cyl_z(rig, 0.1, 0.085, 0.16, Vector3(stat.x - 0.04, stat.y, stat_top), _mat("steel", _STEEL, 0.6, 0.35), 20)


# --- Carburetors ---------------------------------------------------------------------


func _build_carb(rig: Node3D, part: Dictionary, pad: Vector3) -> void:
	if int(part.get("barrels", 4)) == 2:
		_build_two_barrel(rig, pad)
		return
	if is_sbc():
		_build_sbc_carb(rig, part, pad)
		return
	var model := _add_model_nodes(rig, _NODES_CARB, true)
	if model == null:
		return
	model.position = pad - IRON_PAD
	var finish: Variant = _CARB_FINISHES.get(str(part.get("finish", "")), null)
	var body := model.find_child("carburetor", true, false) as MeshInstance3D
	if finish is Color and body != null:
		body.material_override = _mat("carb_" + str(part.get("finish", "")), finish, 0.85, 0.3)


## The small-block's four-barrel from its model, moved onto `pad`; a finish colors its
## body, bowls and air horn.
func _build_sbc_carb(rig: Node3D, part: Dictionary, pad: Vector3) -> void:
	var model := _add_model_nodes(rig, _SB_NODES_CARB, true)
	if model == null:
		return
	model.position = pad - fh(SB_PAD)
	var finish: Variant = _CARB_FINISHES.get(str(part.get("finish", "")), null)
	if not finish is Color:
		return
	var mat := _mat("carb_" + str(part.get("finish", "")), finish, 0.85, 0.3)
	for node in model.find_children("carburetor*", "MeshInstance3D", true, false):
		if not str(node.name).begins_with("carburetor_bowl_screw"):
			(node as MeshInstance3D).material_override = mat


func _build_two_barrel(rig: Node3D, pad: Vector3) -> void:
	var zinc := _mat("carb", _ZINC, 0.85, 0.35)
	var dark := _mat("black", _BLACK, 0.0, 0.6)
	var steel := _mat("steel", _STEEL, 0.6, 0.35)
	_box(rig, Vector3(0.44, 0.52, 0.03), pad + Vector3(0.0, 0.0, 0.015), dark)
	_box(rig, Vector3(0.38, 0.5, 0.06), pad + Vector3(0.0, 0.0, 0.06), zinc)
	_box(rig, Vector3(0.3, 0.32, 0.2), pad + Vector3(0.0, 0.0, 0.19), zinc)
	# Float bowl on the front, air horn on top with its two throats.
	_box(rig, Vector3(0.12, 0.28, 0.2), pad + Vector3(-0.2, 0.0, 0.18), zinc)
	_cyl_z(rig, 0.17, 0.17, 0.07, pad + Vector3(0.0, 0.0, 0.29), zinc, 20)
	for y: float in [-0.075, 0.075]:
		_cyl_z(rig, 0.055, 0.055, 0.005, pad + Vector3(0.0, y, 0.36), dark, 14)
	# Throttle shaft and lever.
	_cyl_x(rig, 0.018, 0.4, pad.x - 0.2, steel, 8, pad.y + 0.17, pad.z + 0.21)


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
	if is_sbc():
		# The small-block's cap has its towers in its model.
		for node in model.find_children("distributor_cap_*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = cap_mat
		return
	if is_flathead():
		# The flathead's lies forward with its towers round the cap's face.
		for tower in cap_towers():
			_cyl_x(rig, 0.03, 0.08, tower.x + 0.08, cap_mat, 10, tower.y, tower.z)
		return
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
	var slots := _view_carb_slots()
	var pads: Array[Vector3] = []
	for slot in slots:
		pads.append(carb_pad(slot))
	if pads.is_empty():
		pads.append(carb_pad(GameState.SLOT_CARB))
	if is_sbc() and _sb_stock_cleaner():
		_build_sbc_cleaner(rig, pads[0])
		return
	var r := 0.72
	if pads.size() == 2:
		r = 0.45
	elif pads.size() == 3:
		r = 0.3
	if is_flathead():
		r = 0.5 if pads.size() == 1 else 0.26
	if is_sbc():
		var radii: Array[float] = [SB_CLEANER_R, 4.0, 2.5]
		r = radii[clampi(pads.size() - 1, 0, 2)] * FH_IN
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
		var engine := _view_engine()
		label.text = str(engine.get("badge", "%d V8" % GameState.cid_of(engine)))
		label.font_size = 64
		label.pixel_size = 0.004
		label.modulate = Color(0.85, 0.12, 0.08) if not chrome else Color(0.15, 0.15, 0.15)
		label.outline_size = 0
		# Lying on the lid, read from the front of the car.
		label.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), pads[0] + Vector3(-0.46, 0.0, base + h + 0.025))
		rig.add_child(label)


## The small-block's stock 14 inch cleaner from its model, moved onto `pad`, with the
## engine's badge on the lid in front of the wing nut.
func _build_sbc_cleaner(rig: Node3D, pad: Vector3) -> void:
	var model := _add_model_nodes(rig, _SB_NODES_CLEANER, true)
	if model == null:
		return
	model.position = pad - fh(SB_PAD)
	var label := Label3D.new()
	var engine := _view_engine()
	label.text = str(engine.get("badge", "%d V8" % GameState.cid_of(engine)))
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(0.85, 0.12, 0.08)
	label.outline_size = 0
	# Lying on the lid, read from the front of the car: the lid is about 3.7 in over the
	# cleaner's base this far out.
	var at := pad + Vector3(-3.6, 0.0, SB_CARB_TOP - SB_PAD.z + 3.74) * FH_IN
	label.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), at)
	rig.add_child(label)


# --- Plug wires ----------------------------------------------------------------------


## Where each spark plug stands out of its head, as a boot end and the direction it points.
func plug_spots() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if is_flathead():
		var seat := float(FH_PLUG_SEAT.get(str(_view_part(GameState.SLOT_HEADS).get("finish", "")), FH_PLUG_SEAT[""]))
		for side: float in [1.0, -1.0]:
			for x in FH_PLUG_X:
				var at := fh_head(side, x, FH_HEAD_INNER - FH_PLUG_IN, seat + 0.35)
				out.append(Transform3D(_axis_basis(fh_head_up(side)), at))
		return out
	if is_sbc():
		for side: float in [1.0, -1.0]:
			var dir := Vector3(SB_PLUG_DIR.x, SB_PLUG_DIR.y * side, SB_PLUG_DIR.z)
			for bx in SB_BORES_X:
				var exit := Vector3(sb_bank_x(side, bx), SB_PLUG_EXIT.x * side, SB_PLUG_EXIT.y)
				out.append(Transform3D(_axis_basis(dir), fh(exit + dir * SB_PLUG_BOOT)))
		return out
	for side: float in [1.0, -1.0]:
		for i in BORES_X.size():
			var x: float = BORES_X[i] + (0.08 if side > 0.0 else -0.08)
			var dir := Vector3(0.0, side, -0.5).normalized()
			out.append(Transform3D(_axis_basis(dir), Vector3(x, PLUG_Y * side, PLUG_Z)))
	return out


## Wires from the cap's towers to the plugs, each tower to the nearest plug.
func _build_wires(rig: Node3D) -> void:
	var rubber := _mat("wire", Color(0.08, 0.07, 0.07), 0.0, 0.6)
	var boot := _mat("boot", Color(0.75, 0.3, 0.1), 0.0, 0.7)
	if is_flathead():
		_build_flathead_wires(rig, rubber, boot)
		return
	var plugs := plug_spots()
	var free := plugs.duplicate()
	var base := distributor_base()
	var over_at := SB_WIRE_OVER * FH_IN + Vector2(0.0, CRANK_Z) if is_sbc() else WIRE_OVER
	var bend_at := SB_WIRE_BEND * FH_IN + Vector2(0.0, CRANK_Z) if is_sbc() else WIRE_BEND
	var down_at := SB_WIRE_DOWN * FH_IN + Vector2(0.0, CRANK_Z) if is_sbc() else WIRE_DOWN
	var towers: Array[Vector3] = []
	for t in cap_towers():
		towers.append(base + t)
	# Towers on the right go to the right bank, front ones to the front cylinders.
	towers.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y if signf(a.y) != signf(b.y) else a.x < b.x)
	for tower in towers:
		var best := 0
		for i in free.size():
			if _wire_cost(tower, free[i].origin, base) < _wire_cost(tower, free[best].origin, base):
				best = i
		var plug: Transform3D = free[best]
		free.remove_at(best)
		var side := signf(plug.origin.y)
		var out := plug.origin + plug.basis.z * 0.25
		var over := Vector3(plug.origin.x * 0.85 + tower.x * 0.15, side * over_at.x, over_at.y)
		var down := Vector3(plug.origin.x, side * down_at.x, down_at.y)
		var points := _bezier(tower, tower + Vector3(0.0, 0.0, 0.2), over, 8)
		if is_sbc():
			# Out sideways first, clear of the carburetors and air cleaners over the front.
			var back := fh(Vector3(SB_WIRE_BACK.x, SB_WIRE_BACK.y * side, SB_WIRE_BACK.z))
			points = _bezier(tower, tower + Vector3(0.0, 0.0, 0.08), back, 8)
			points.append_array(_bezier(back, Vector3(back.x, over.y, over.z + 0.04), over, 8).slice(1))
		points.append_array(_bezier(over, Vector3(plug.origin.x, side * bend_at.x, bend_at.y), down, 8).slice(1))
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


## The flathead's wires: forward out of the cap's face, up over the front of each head,
## back along its inner edge, and down onto the plugs. The towers on the right of the cap
## go to the right bank, front to back from the top.
func _build_flathead_wires(rig: Node3D, rubber: Material, boot: Material) -> void:
	var plugs := plug_spots()
	var towers := cap_towers()
	var centre := fh(FH_CAP)
	towers.sort_custom(func(a: Vector3, b: Vector3) -> bool: return atan2(a.z - centre.z, a.y - centre.y) < atan2(b.z - centre.z, b.y - centre.y))
	var right: Array[Vector3] = []
	var left: Array[Vector3] = []
	for t in towers:
		(right if t.y >= centre.y else left).append(t)
	for side: float in [1.0, -1.0]:
		var own := right if side > 0.0 else left
		var bank: Array[Transform3D] = []
		for p in plugs:
			if signf(p.origin.y) == side:
				bank.append(p)
		for i in mini(own.size(), bank.size()):
			var tower := own[i]
			var plug := bank[i]
			var out := plug.origin + plug.basis.z * 0.25
			var edge_front := fh_head(side, -10.0, FH_WIRE_A, FH_WIRE_H) + Vector3(0.0, 0.0, 0.03 * float(i))
			var edge := fh_head(side, 0.0, FH_WIRE_A, FH_WIRE_H)
			edge.x = plug.origin.x
			var points := _bezier(tower, tower + Vector3(-0.25, 0.0, 0.1), edge_front, 8)
			points.append_array(_bezier(edge_front, (edge_front + edge) * 0.5 + Vector3(0.0, 0.0, 0.04), edge, 6).slice(1))
			points.append_array(_bezier(edge, out + plug.basis.z * 0.2, out, 6).slice(1))
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


static func _wire_cost(tower: Vector3, plug: Vector3, base: Vector3) -> float:
	var side_miss := 0.0 if signf(tower.y - base.y) == signf(plug.y) else 2.0
	return absf(plug.x - (tower.x - base.x) * 9.0) + side_miss


## The distributor's base the cap's towers stand on, in engine units.
func distributor_base() -> Vector3:
	return fh(SB_DIST) if is_sbc() else DISTRIBUTOR_BASE


## Tops of the distributor cap's plug towers, from `distributor_base()`; on a flathead, where they
## stand out of the cap's face, in engine units.
func cap_towers() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if is_flathead():
		var face := fh(FH_CAP)
		for k in 8:
			var a := TAU * (float(k) + 0.5) / 8.0
			var r := FH_CAP_R * 0.65 * FH_IN
			out.append(face + Vector3(-0.08, r * cos(a), r * sin(a)))
		return out
	var ring := SB_TOWER_R * FH_IN if is_sbc() else CAP_TOWER_R
	var top := (SB_TOWER_TOP - SB_DIST.z) * FH_IN if is_sbc() else CAP_TOWER_TOP
	for k in 8:
		var a := TAU * (float(k) + 0.5) / 8.0
		out.append(Vector3(ring * cos(a), ring * sin(a), top))
	return out


# --- Mesh helpers --------------------------------------------------------------------


## The fitted engine's model with only the nodes named by `prefixes` in it (`keep`), or
## with those taken out.
func _add_model_nodes(rig: Node3D, prefixes: Array[String], keep: bool) -> Node3D:
	return _add_model_filtered(rig, _model_path(), func(n: String) -> bool: return _begins_any(n, prefixes) == keep)


## The fitted engine's model file.
func _model_path() -> String:
	var path := str(_view_engine().get("model", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		path = _MODEL_DEFAULT
	return path


## A part's own model file, or the engine's when it has none (the stock parts are in the
## engine's model).
func _part_model(part: Dictionary) -> String:
	var path := str(part.get("model", ""))
	return path if not path.is_empty() and ResourceLoader.exists(path) else _model_path()


## The model at `path` with only the mesh nodes whose names `keep` takes.
func _add_model_filtered(rig: Node3D, path: String, keep: Callable) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Engine model missing: %s" % path)
		return null
	var model := packed.instantiate() as Node3D
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if not bool(keep.call(str(node.name))):
			node.get_parent().remove_child(node)
			node.free()
	rig.add_child(model)
	return model


static func _begins_any(name: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if name.begins_with(prefix):
			return true
	return false


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
			for v: Array in [[i, k], [j, k], [j, k2], [i, k], [j, k2], [i, k2]]:
				var dir: Vector3 = rings[v[0]][v[1]]
				st.set_normal(dir)
				st.add_vertex(points[v[0]] + dir * radius)
	return st.commit()
