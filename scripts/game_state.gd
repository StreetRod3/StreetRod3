extends Node

## Saves go in numbered slots, one file each. The single save from before slots
## becomes slot 1 the first time the slots are looked at.
const SAVE_DIR := "user://saves"
const SAVE_SLOTS := 8
const LEGACY_SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
const SCENE_GARAGE := "res://scenes/garage.tscn"
const SCENE_GAS_STATION := "res://scenes/gas_station.tscn"
const SCENE_DRIVE_IN := "res://scenes/drive-in.tscn"
const SCENE_RACE := "res://scenes/race.tscn"
const SCENE_NEWSPAPER := "res://scenes/newspaper.tscn"
const SCENE_DRIVER_LICENSE := "res://scenes/driver_license.tscn"
const SCENE_SETTINGS := "res://scenes/settings.tscn"
const SCENE_TRANSMISSION := "res://scenes/transmission.tscn"
const SCENE_UNDER_CAR := "res://scenes/under_car.tscn"
const SCENE_HOOD := "res://scenes/hood.tscn"
const SCENE_TUNE := "res://scenes/tune.tscn"
const SCENE_CRUISE := "res://scenes/cruise.tscn"

const POI_GARAGE := "garage"
const POI_DRIVE_IN := "drive-in"
const POI_GAS_STATION := "gas-station"

const MUSIC_GARAGE := "res://assets/music/garage.mp3"
const MUSIC_RACE := "res://assets/music/race.mp3"
const DEFAULT_CAR_ID := "sr1-corvette-1956"
const MAX_OWNED_CARS := 16
const DEFAULT_TANK_L := 60.0
const FUEL_L_PER_KM := 5.0
const FUEL_PRICE_PER_L := 2
const ENGINE_TUNE_MIN := 0
const ENGINE_TUNE_MAX := 10
const ENGINE_TUNE_DEFAULT := 4
## After a race the timing holds, or walks one step either way.
const ENGINE_TUNE_DRIFT_DOWN := 0.2
const ENGINE_TUNE_DRIFT_UP := 0.2
const PLAYER_CAR_FILE := "res://assets/cars/sr1-corvette-1956.car"
const OPPONENTS_PATH := "res://assets/opponents/opponents.json"
const DEFAULT_OPPONENT_HEAD := "res://assets/opponents/head.glb"
const PARTS_REGISTER := "res://assets/parts/parts.register"
const CARS_REGISTER := "res://assets/cars/cars.register"
const _CarFile := preload("res://scripts/car_file.gd")
const _PartsRegister := preload("res://scripts/parts_register.gd")
const _CarsRegister := preload("res://scripts/cars_register.gd")

const MILES_PER_KM := 0.621371
const POUNDS_PER_KG := 2.20462
const GALLONS_PER_L := 0.264172
const INCHES_PER_CM := 0.393701
const FEET_PER_M := 3.28084
const RACE_DRAG := "drag"
const RACE_ROAD := "road"
## Street Rod 2's cruise drag race: 180 of its road lines, at about 5 m a line.
const RACE_STREET_DRAG := "street_drag"
const STREET_DRAG_TRACK := "res://assets/tracks/street_drag.trk"
const STREET_DRAG_LENGTH_M := 900.0
## Street Rod 2's other two cruise races, at the same 5 m a line. Mulholland drive is lines 370 to
## 960 of one of ten courses, picked when a game starts. The Aqueduct is lines 8 to 342 of its table.
const RACE_MULHOLLAND := "mulholland"
const MULHOLLAND_TRACK := "res://assets/tracks/mulholland_%d.trk"
const MULHOLLAND_COURSES := 10
const MULHOLLAND_LENGTH_M := 2950.0
const RACE_AQUEDUCT := "aqueduct"
const AQUEDUCT_TRACK := "res://assets/tracks/aqueduct.trk"
const AQUEDUCT_LENGTH_M := 1670.0
const QUARTER_MILE_M := 402.336
const ROAD_RACE_LENGTH_M := QUARTER_MILE_M * 6.0
const DRAG_STAKE_LOW := 10
const DRAG_STAKE_HIGH := 50
const ROAD_STAKE_LOW := 25
const ROAD_STAKE_HIGH := 100
## Engine id for a car whose engine was blown and pulled out.
const NO_ENGINE_ID := "none"
## Races the player runs before a rival has a new engine in a car that came with none.
const RIVAL_ENGINE_WAIT_RACES := 3
## Gearbox id for a car whose transmission was taken out. The gearbox goes to spare parts.
const NO_GEARBOX_ID := "none"
## A car with its wheels off. It stays in the bay until it gets some.
const NO_WHEEL_ID := "none"
const NO_WHEELS_IN_BAY := "The car in the garage has no wheels, so it can't roll out."
## Bellhousing bolts holding the gearbox to the engine.
const GEARBOX_BOLT_COUNT := 2
## Turns that seat a bellhousing bolt. Zero is out of its hole.
const GEARBOX_BOLT_TIGHT := 3
## A bolt started in its hole runs down this far by hand, a turn short of tight; a tight
## bolt loosens back to one turn. Each way is two clicks (`next_bolt_turns()`).
const BOLT_THREADED := 2
## Parts changed from the creeper. A car has one of each; parts name theirs in `slot`.
const SLOT_MANIFOLD := "manifold"
const SLOT_EXHAUST := "exhaust"
const SLOT_MUFFLER := "muffler"
## The second muffler, on the left pipe of a dual exhaust. It takes the same parts as
## `SLOT_MUFFLER`, which is the one muffler of a single exhaust.
const SLOT_MUFFLER_LEFT := "muffler_left"
const SLOT_DIFFERENTIAL := "differential"
## The tires on the car's wheels. They are changed at the tire machine with the wheels off
## the car. Wheels can be bare, but a car does not leave the garage on bare wheels.
const SLOT_TIRES := "tires"
## What the body rides on. A car always has both, so they swap but never just come off.
const SLOT_SPRINGS := "springs"
const SLOT_SHOCKS := "shocks"
const UNDER_CAR_SLOTS: Array[String] = [SLOT_MANIFOLD, SLOT_EXHAUST, SLOT_MUFFLER, SLOT_MUFFLER_LEFT, SLOT_DIFFERENTIAL, SLOT_SPRINGS, SLOT_SHOCKS]
## Parts changed under the hood, from the bottom up: the camshaft in the block, the
## cylinder heads over it, the intake on the heads, the carburetors and the distributor in the intake, the air
## cleaner over the carburetors. The heads are one part however many the engine has.
const SLOT_CAM := "cam"
const SLOT_HEADS := "heads"
const SLOT_INTAKE := "intake"
const SLOT_CARB := "carb"
## The second and third carburetors of a dual-quad or tri-power intake. They take the
## same parts as `SLOT_CARB`.
const SLOT_CARB_2 := "carb_2"
const SLOT_CARB_3 := "carb_3"
const SLOT_DISTRIBUTOR := "distributor"
const SLOT_AIR_CLEANER := "air_cleaner"
const CARB_SLOTS: Array[String] = [SLOT_CARB, SLOT_CARB_2, SLOT_CARB_3]
const HOOD_SLOTS: Array[String] = [SLOT_CAM, SLOT_HEADS, SLOT_INTAKE, SLOT_CARB, SLOT_CARB_2, SLOT_CARB_3, SLOT_DISTRIBUTOR, SLOT_AIR_CLEANER]
const ALL_SLOTS: Array[String] = [
	SLOT_MANIFOLD, SLOT_EXHAUST, SLOT_MUFFLER, SLOT_MUFFLER_LEFT, SLOT_DIFFERENTIAL, SLOT_SPRINGS, SLOT_SHOCKS, SLOT_TIRES,
	SLOT_CAM, SLOT_HEADS, SLOT_INTAKE, SLOT_CARB, SLOT_CARB_2, SLOT_CARB_3, SLOT_DISTRIBUTOR, SLOT_AIR_CLEANER,
]
## Slot id for an empty slot. The exhaust, the mufflers, and everything under the hood
## can come off for good.
const NO_PART_ID := "none"
const REMOVABLE_SLOTS: Array[String] = [
	SLOT_EXHAUST, SLOT_MUFFLER, SLOT_MUFFLER_LEFT, SLOT_TIRES,
	SLOT_CAM, SLOT_HEADS, SLOT_INTAKE, SLOT_CARB, SLOT_CARB_2, SLOT_CARB_3, SLOT_DISTRIBUTOR, SLOT_AIR_CLEANER,
]
## What every car rolls out of the factory with.
const STOCK_SLOT_PARTS := {
	SLOT_MANIFOLD: "manifold-iron",
	SLOT_EXHAUST: "exhaust-single",
	SLOT_MUFFLER: "muffler-stock",
	SLOT_MUFFLER_LEFT: NO_PART_ID,
	SLOT_DIFFERENTIAL: "diff-308",
	SLOT_SPRINGS: "springs-stock",
	SLOT_SHOCKS: "shocks-stock",
	SLOT_TIRES: "tires-bias",
	SLOT_CAM: "cam-stock",
	SLOT_HEADS: "heads-iron",
	SLOT_INTAKE: "intake-iron4",
	SLOT_CARB: "carb-4bbl-stock",
	SLOT_CARB_2: NO_PART_ID,
	SLOT_CARB_3: NO_PART_ID,
	SLOT_DISTRIBUTOR: "dist-points",
	SLOT_AIR_CLEANER: "air-cleaner-stock",
}
## Key in `engine_bolts` for the engine's own mounts. The other keys are hood slots.
const HOOD_ENGINE := "engine"
## Bolts holding each part under the hood. They turn like the bellhousing bolts, out
## (0) to `GEARBOX_BOLT_TIGHT`. The heads have `HEAD_BOLTS` each and the air cleaner one per carburetor (`hood_bolt_count()`).
const HOOD_BOLT_COUNTS := {
	HOOD_ENGINE: 2,
	SLOT_CAM: 2,
	SLOT_HEADS: 4,
	SLOT_INTAKE: 2,
	SLOT_CARB: 2,
	SLOT_CARB_2: 2,
	SLOT_CARB_3: 2,
	SLOT_DISTRIBUTOR: 1,
	SLOT_AIR_CLEANER: 1,
}
const HEAD_BOLTS := 2
## Condition of a part, 0 to 1. Parts from the paper are new; parts that come with a car
## start somewhere in the used range; everything on the car wears a little each race.
const CONDITION_USED_MIN := 0.5
const CONDITION_USED_MAX := 0.9
const CONDITION_WEAR_MIN := 0.01
const CONDITION_WEAR_MAX := 0.03
## The most of a part's condition crashes can take in one race, just short of a total.
const CRASH_WEAR_MAX := 0.5
## What a part worn right down still does. Tired springs sag, and worn shocks barely damp.
const SPRING_WORN_RATE := 0.75
const SHOCK_WORN_RATE := 0.45
const CONDITION_FLOOR := 0.05
## Tires worn down to this blow out in the next race, somewhere between these shares of
## the way along it.
const TIRE_BLOWOUT_CONDITION := 0.15
const TIRE_BLOWOUT_MIN := 0.2
const TIRE_BLOWOUT_MAX := 0.8
## A buyer offers between these fractions of the paper's price. Condition skews where in
## the range: a new part draws high offers more often, a worn one low.
const SELL_OFFER_MIN := 0.5
const SELL_OFFER_MAX := 0.9
## Spark advance for each tune step: step 0 fires at top dead center.
const TIMING_DEG_PER_STEP := 2
## Airflow an engine wants, in cfm per cubic inch. Carburetors well short of it starve
## the engine; far over it they bog.
const CFM_PER_CID := 1.5
const CARB_STARVED := 0.85
const CARB_BOGGED := 1.8
## How much a kilogram of wheel counts against a kilogram of car. A wheel's mass has to be
## spun up as well as carried along.
const WHEEL_ROTATING_FACTOR := 2.0
## Engine sound boost with the exhaust off and the headers open, in dB.
const OPEN_EXHAUST_DB := 6.0
## Outcomes of `apply_pink_slips`.
const PINK_NONE := 0
const PINK_WON := 1
const PINK_KEPT := 2
const PINK_LOST := 3

## Display name of the player's car.
## Where the slots are kept, and the old single save to bring in. Test scripts point these
## somewhere else so they never touch the player's saves.
var save_dir: String = SAVE_DIR
var legacy_save_path: String = LEGACY_SAVE_PATH
## The slot this game was last saved to or loaded from, or 0 for a new game.
var save_slot: int = 0
var car_name: String = "Corvette 1956"
## Current paint color for the active car.
var car_color: Color = Color(0.78, 0.14, 0.14, 1.0)
## Fuel in the active car's tank, in liters.
var fuel: float = DEFAULT_TANK_L
## Top speed and horsepower after parts and engine tune.
var vmax_kmh: float = 220.0
var engine_power_hp: float = 280.0
## Ignition timing for the active car. Power and top speed peak at `engine_sweet_tune()`.
var engine_tune: int = ENGINE_TUNE_DEFAULT

## Last scene to restore (garage, drive-in, race).
var current_scene_path: String = SCENE_GARAGE
## Index into `opponents` for the next race.
var selected_opponent_id: int = 0
## `RACE_DRAG` (straight quarter mile), `RACE_ROAD` (turning course), or Street Rod 2's three:
## `RACE_STREET_DRAG`, `RACE_MULHOLLAND` and `RACE_AQUEDUCT`.
var selected_race_type: String = RACE_DRAG
## Which of Mulholland's courses this game has. Street Rod 2 keeps one for a whole game too.
var mulholland_course: int = 0
## Cash side bet for the next race. Zero is a race for nothing.
var race_stake: int = 0
## Road race where the winner takes the loser's car.
var race_pink_slips: bool = false
## The next garage visit says the roster is empty. Not saved: only the trip straight back.
var cars_just_gone: bool = false
## The next garage visit rolls the car in from outside. Set by the drive-in, the gas
## station, and a car just bought from the paper. Not saved.
var drive_into_garage: bool = false
## Street cruise playing before `cruise_scene`. Not saved.
var cruise_from_poi: String = ""
var cruise_to_poi: String = ""
var cruise_scene: String = ""
## A rival's engine on the hood screen. Empty when the bay is the player's car.
## Not saved. Keys: engine_id, hp, parts (hood slot to part id), car_name, color.
var hood_peek: Dictionary = {}
## Rival left waiting at the drive-in while the player looks under the hood. -1 if none.
## Not saved.
var drive_in_rival_index: int = -1
## The player already closed one look under this rival's hood. Not saved.
var drive_in_hood_seen: bool = false
## The direct-speed driving model from before the tire simulation.
var arcade_drive: bool = true
## Show speeds, fuel, weights, and distances in US units. They are always kept in metric.
var imperial_units: bool = false

## Whether background music is on. Persisted in settings; also toggled by the garage radio.
var music_enabled: bool = true

## The name signed on the license at the start of a new game. Print it with to_upper()
## for the typed line, because McGee can be made from this and not from MCGEE.
var driver_name: String = ""
## What the license says about the driver, as printed on it and clicked through there.
const DRIVER_TRAITS_DEFAULT := {"sex": "M", "hair": "BRN", "eyes": "BRN", "height": "5-08", "weight": "165", "skin": "LGT", "glasses": false}
var driver_traits: Dictionary = DRIVER_TRAITS_DEFAULT.duplicate()
## Cash on hand for classifieds (parts and used cars).
var money: int = 2500
## Instance id of the car currently in the garage. Empty when the bay is empty.
var current_car_id: String = DEFAULT_CAR_ID
## Instance ids. The same model can appear more than once.
var owned_car_ids: Array[String] = [DEFAULT_CAR_ID]
var _next_car_serial: int = 1
var owned_part_ids: Array[String] = []
var equipped_part_ids: Array[String] = []
var owned_gearbox_ids: Array[String] = ["gb_auto3"]
var equipped_gearbox_id: String = "gb_auto3"
## Turns on each bellhousing bolt of the active car, 0 (out) to `GEARBOX_BOLT_TIGHT`.
var gearbox_bolts: Array[int] = [GEARBOX_BOLT_TIGHT, GEARBOX_BOLT_TIGHT]
## Manifolds, muffler, and rear end of the active car, by slot. Not in `equipped_part_ids`.
var slot_part_ids: Dictionary = STOCK_SLOT_PARTS.duplicate()
## Turns on each bolt under the hood of the active car, by `HOOD_BOLT_COUNTS` key. A
## fitted part missing here is bolted tight.
var engine_bolts: Dictionary = {}
## The spark plug wires run from the distributor cap to the plugs.
var plug_wires: bool = true
var owned_engine_ids: Array[String] = ["v8-283"]
var equipped_engine_id: String = "v8-283"
var owned_wheel_ids: Array[String] = ["wheel-c1"]
var equipped_wheel_id: String = "wheel-c1"
## Paint, fuel, and mounted parts for each owned car. The fields above mirror the active car.
var car_records: Dictionary = {}
## Conditions of spares that are on no car, by `"kind:id"` (kinds as the garage's parts
## list names them: engine, transmission, wheels, part). Each car record keeps its own
## fitted parts' conditions under "conditions".
var spare_conditions: Dictionary = {}
## Tires stay on their wheels until the tire machine takes them off. For each wheel id, the
## tires on its spare sets as {"id", "c"}, one entry for each set that has any. Those tires
## are owned but are not spare parts.
var spare_wheel_tires: Dictionary = {}
## The last offer made for each spare, so the next one differs.
var _last_offers: Dictionary = {}
## Parsed `PLAYER_CAR_FILE`. Empty sections mean the file failed to load.
var car_spec: Dictionary = {}
## Paint for each listing during the current newspaper visit.
var newspaper_colors: Dictionary = {}

## Rivals met so far. A car is assigned the first time they are called and kept for the game.
var opponents: Array[Dictionary] = []
## A rival's pronouns by their `gender` in `OPPONENTS_PATH`. Anyone with none listed is
## they/them: a name does not say.
const _PRONOUNS := {
	"man": {"subject": "he", "possessive": "his"},
	"woman": {"subject": "she", "possessive": "her"},
}
const _PRONOUNS_DEFAULT := {"subject": "they", "possessive": "their"}
## What each new rival drives, in the order they are met.
var _rival_ladder: Array[Dictionary] = []
var _opponent_names: Array[String] = []
## Skin and head model from `OPPONENTS_PATH`, keyed by rival name.
var _opponent_skins: Dictionary = {}
var _opponent_heads: Dictionary = {}
var _opponent_genders: Dictionary = {}

const DEFAULT_GEARBOX_ID := "gb_auto3"

## Filled from the registers at startup. The newspaper sells these lists.
var PARTS: Array[Dictionary] = []
var GEARBOXES: Array[Dictionary] = []
var ENGINES: Array[Dictionary] = []
var WHEELS: Array[Dictionary] = []
var USED_CARS: Array[Dictionary] = []


var _music_player: AudioStreamPlayer
var _music_track: String = ""


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)
	load_settings()
	load_parts_register()
	load_cars_register()
	load_player_car()
	if not car_records.has(current_car_id):
		set_fuel(_starting_fuel())
		_sync_record_from_active()
	refresh_car_stats()


func load_parts_register() -> void:
	var register: Dictionary = _PartsRegister.load_path(PARTS_REGISTER)
	var errors: Variant = register.get("errors", [])
	if typeof(errors) == TYPE_ARRAY:
		for err: String in errors:
			push_error(str(err))
	PARTS = _dict_list(register.get("parts", []))
	GEARBOXES = _dict_list(register.get("transmissions", []))
	ENGINES = _dict_list(register.get("engines", []))
	WHEELS = _dict_list(register.get("wheels", []))


func load_cars_register() -> void:
	var register: Dictionary = _CarsRegister.load_path(CARS_REGISTER)
	var errors: Variant = register.get("errors", [])
	if typeof(errors) == TYPE_ARRAY:
		for err: String in errors:
			push_error(str(err))
	USED_CARS = _dict_list(register.get("cars", []))


func _dict_list(value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return rows
	for item: Variant in value:
		if typeof(item) == TYPE_DICTIONARY:
			var row: Dictionary = item
			rows.append(row)
	return rows


func has_active_car() -> bool:
	return not current_car_id.is_empty() and owned_car_ids.has(current_car_id)


func has_engine() -> bool:
	return has_active_car() and equipped_engine_id != NO_ENGINE_ID


func has_gearbox() -> bool:
	return has_active_car() and equipped_gearbox_id != NO_GEARBOX_ID


## Both bellhousing bolts are in and tight.
func is_gearbox_bolted() -> bool:
	if not has_gearbox():
		return false
	for turns in gearbox_bolts:
		if turns < GEARBOX_BOLT_TIGHT:
			return false
	return true


## The car can leave the garage under its own power.
func can_drive() -> bool:
	return engine_runs() and is_gearbox_bolted() and has_wheels() and has_tires()


func has_wheels() -> bool:
	return has_active_car() and equipped_wheel_id != NO_WHEEL_ID


func has_tires() -> bool:
	return not slot_part(SLOT_TIRES).is_empty()


## Everything the engine needs is on and bolted down, and the wires are on.
func engine_runs() -> bool:
	return engine_trouble().is_empty()


## Why the engine will not run, or "" when it will.
func engine_trouble() -> String:
	if not has_engine():
		return "There is no engine."
	if not is_hood_part_bolted(HOOD_ENGINE):
		return "The engine mounts are loose."
	if slot_part(SLOT_CAM).is_empty():
		return "There is no camshaft."
	if not is_hood_part_bolted(SLOT_CAM):
		return "The camshaft is loose."
	if slot_part(SLOT_HEADS).is_empty():
		return "There are no cylinder heads."
	if not is_hood_part_bolted(SLOT_HEADS):
		return "The cylinder heads are loose."
	if slot_part(SLOT_INTAKE).is_empty():
		return "There is no intake manifold."
	if not is_hood_part_bolted(SLOT_INTAKE):
		return "The intake manifold is loose."
	for slot in carb_slots():
		if slot_part(slot).is_empty():
			return "A carburetor is missing."
		if not is_hood_part_bolted(slot):
			return "A carburetor is loose."
	if slot_part(SLOT_DISTRIBUTOR).is_empty():
		return "There is no distributor."
	if not is_hood_part_bolted(SLOT_DISTRIBUTOR):
		return "The distributor is loose."
	if not plug_wires:
		return "The plug wires are off."
	if slot_part(SLOT_MANIFOLD).is_empty():
		return "There are no exhaust manifolds."
	return ""


## How many cylinder heads the fitted engine has: two on a V engine, one on an inline.
func engine_head_count(engine: Dictionary = {}) -> int:
	return heads_on(get_equipped_engine() if engine.is_empty() else engine)


## Heads on this engine and no other: an empty one does not mean the active car's.
static func heads_on(engine: Dictionary) -> int:
	return clampi(int(engine.get("heads", 2)), 1, 2)


## How many bolts hold a part under the hood: `HEAD_BOLTS` on each head, a wing nut on
## each carburetor's air cleaner, and `HOOD_BOLT_COUNTS` for the rest.
func hood_bolt_count(key: String) -> int:
	if key == SLOT_HEADS:
		return HEAD_BOLTS * engine_head_count()
	if key == SLOT_AIR_CLEANER:
		return maxi(carb_slots().size(), 1)
	return int(HOOD_BOLT_COUNTS.get(key, 0))


## Turns on each bolt of a part under the hood (`HOOD_BOLT_COUNTS` key).
func hood_bolts(key: String) -> Array[int]:
	var out: Array[int] = []
	var saved: Variant = engine_bolts.get(key, null)
	for i in hood_bolt_count(key):
		var turns := GEARBOX_BOLT_TIGHT
		if typeof(saved) == TYPE_ARRAY and i < (saved as Array).size():
			turns = clampi(int((saved as Array)[i]), 0, GEARBOX_BOLT_TIGHT)
		out.append(turns)
	return out


func set_hood_bolt(key: String, index: int, turns: int) -> void:
	if not is_hood_part_fitted(key):
		return
	var bolts := hood_bolts(key)
	if index < 0 or index >= bolts.size():
		return
	bolts[index] = clampi(turns, 0, GEARBOX_BOLT_TIGHT)
	engine_bolts[key] = bolts
	_sync_record_from_active()


func is_hood_part_fitted(key: String) -> bool:
	if key == HOOD_ENGINE:
		return has_engine()
	return has_engine() and not slot_part(key).is_empty()


func is_hood_part_bolted(key: String) -> bool:
	if not is_hood_part_fitted(key):
		return false
	for turns in hood_bolts(key):
		if turns < GEARBOX_BOLT_TIGHT:
			return false
	return true


## The carburetor slots the intake has: one, two for dual quads, three for a tri-power.
func carb_slots() -> Array[String]:
	var out: Array[String] = []
	var intake := slot_part(SLOT_INTAKE)
	if intake.is_empty():
		return out
	for i in clampi(int(intake.get("carbs", 1)), 1, CARB_SLOTS.size()):
		out.append(CARB_SLOTS[i])
	return out


## What has to come off before the part under the hood at `key` can: a slot, "wires",
## or "" when nothing is in the way.
func hood_part_blocker(key: String) -> String:
	match key:
		HOOD_ENGINE:
			if not slot_part(SLOT_HEADS).is_empty():
				return SLOT_HEADS
		SLOT_CAM:
			if not slot_part(SLOT_HEADS).is_empty():
				return SLOT_HEADS
		SLOT_HEADS:
			if not slot_part(SLOT_INTAKE).is_empty():
				return SLOT_INTAKE
			# The plugs are in the heads.
			if plug_wires:
				return "wires"
		SLOT_INTAKE:
			for slot in CARB_SLOTS:
				if not slot_part(slot).is_empty():
					return slot
			if not slot_part(SLOT_DISTRIBUTOR).is_empty():
				return SLOT_DISTRIBUTOR
		SLOT_CARB, SLOT_CARB_2, SLOT_CARB_3:
			if not slot_part(SLOT_AIR_CLEANER).is_empty():
				return SLOT_AIR_CLEANER
		SLOT_DISTRIBUTOR:
			if plug_wires:
				return "wires"
	return ""


## Why a spare part cannot go into the empty spot at `key` under the hood, or "".
func hood_spot_trouble(key: String) -> String:
	if key == HOOD_ENGINE:
		return "Take the old engine out first." if has_engine() else ""
	if not has_engine():
		return "Put an engine in first."
	if not slot_part(key).is_empty():
		return "Take the old one off first."
	if key == SLOT_CAM:
		return "Take the cylinder heads off first." if not slot_part(SLOT_HEADS).is_empty() else ""
	if key == SLOT_HEADS:
		return "Put a camshaft in first." if slot_part(SLOT_CAM).is_empty() else ""
	if slot_part(SLOT_HEADS).is_empty():
		return "Put the cylinder heads on first."
	if key == SLOT_INTAKE:
		return ""
	if slot_part(SLOT_INTAKE).is_empty():
		return "Put an intake manifold on first."
	if CARB_SLOTS.has(key) and not carb_slots().has(key):
		return "This intake has no pad for another carburetor."
	if key == SLOT_AIR_CLEANER:
		for slot in carb_slots():
			if slot_part(slot).is_empty():
				return "Put the carburetors on first."
	return ""


## Whether a carburetor fits the intake's pads: four-barrels on four-barrel pads.
func carb_fits_intake(carb: Dictionary) -> bool:
	return int(carb.get("barrels", 4)) == int(slot_part(SLOT_INTAKE).get("barrels", 4))


## Puts a spare part into an empty spot under the hood. Its bolts start in, but loose.
func fit_hood_part(part_id: String, slot: String) -> String:
	if not has_active_car():
		return "There is no car in the garage."
	var part := listing_by_id(PARTS, part_id)
	if part.is_empty() or spot_kind(slot) != str(part.get("slot", "")):
		return "That part does not go there."
	var err := hood_spot_trouble(slot)
	if not err.is_empty():
		return err
	if CARB_SLOTS.has(slot) and not carb_fits_intake(part):
		return "That carburetor does not fit this intake."
	if not owns_part(part_id):
		return "That part is not in spare parts."
	if spare_count(part_id) <= 0:
		return "That part is on a car, not in spare parts."
	slot_part_ids[slot] = part_id
	engine_bolts[slot] = _loose_bolts(slot)
	_sync_record_from_active()
	refresh_car_stats()
	return ""


## Lowers a spare engine into the empty bay. Its mounts start in, but loose.
func fit_engine(engine_id: String) -> String:
	if not has_active_car():
		return "There is no car in the garage."
	if has_engine():
		return "Take the old engine out first."
	if free_spare_count("engine", engine_id) <= 0 or listing_by_id(ENGINES, engine_id).is_empty():
		return "That engine is not in spare parts."
	equipped_engine_id = engine_id
	engine_bolts = {HOOD_ENGINE: _loose_bolts(HOOD_ENGINE)}
	plug_wires = false
	_sync_record_from_active()
	refresh_car_stats()
	return ""


## Lifts a part out from under the hood into spare parts: an engine, or a hood slot's
## part. Its bolts must be out and nothing may be on top of it. The exhaust manifolds and
## the camshaft go to spare parts with the engine.
func remove_hood_part(key: String) -> String:
	if not is_hood_part_fitted(key):
		return "There is nothing there to take off."
	for turns in hood_bolts(key):
		if turns > 0:
			return "Take the bolts out first."
	if not hood_part_blocker(key).is_empty():
		return "Something is on top of it."
	engine_bolts.erase(key)
	if key == HOOD_ENGINE:
		equipped_engine_id = NO_ENGINE_ID
		_clear_engine_parts(slot_part_ids)
		engine_bolts.clear()
		plug_wires = false
	else:
		slot_part_ids[key] = NO_PART_ID
		if key == SLOT_DISTRIBUTOR or key == SLOT_HEADS:
			plug_wires = false
	_sync_record_from_active()
	refresh_car_stats()
	return ""


## Hooks the plug wires up to the distributor cap, or pulls them off.
func set_plug_wires(on: bool) -> String:
	if on and slot_part(SLOT_HEADS).is_empty():
		return "There are no heads for the plugs."
	if on and slot_part(SLOT_DISTRIBUTOR).is_empty():
		return "There is no distributor to run them to."
	plug_wires = on
	_sync_record_from_active()
	return ""


## Spare engines: owned and in no car.
func spare_engines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for engine in ENGINES:
		var engine_id := str(engine.get("id", ""))
		if free_spare_count("engine", engine_id) > 0:
			out.append(engine)
	return out


func _loose_bolts(key: String) -> Array[int]:
	var bolts: Array[int] = []
	for i in hood_bolt_count(key):
		bolts.append(1)
	return bolts


## Spark advance in degrees before top dead center for a tune step.
func timing_degrees(step: int = -1) -> int:
	return (engine_tune if step < 0 else step) * TIMING_DEG_PER_STEP


## Displacement in cubic inches, from the register or the engine's name.
func engine_cid(engine: Dictionary = {}) -> int:
	return cid_of(get_equipped_engine() if engine.is_empty() else engine)


## Displacement of this engine and no other: an empty one does not mean the active car's.
static func cid_of(engine: Dictionary) -> int:
	var cid := int(engine.get("cid", 0))
	if cid <= 0:
		cid = str(engine.get("name", "")).to_int()
	return cid if cid > 0 else 283


## Power the carburetors leave the engine: 1 when they flow about what it wants, less
## when they are too small to feed it or so big they bog it.
func carb_flow_factor() -> float:
	var cfm := 0.0
	for slot in carb_slots():
		cfm += float(slot_part(slot).get("cfm", 0.0))
	if cfm <= 0.0:
		return 1.0
	var ratio := cfm / (float(engine_cid()) * CFM_PER_CID)
	if ratio < CARB_STARVED:
		return maxf(1.0 - 0.8 * (CARB_STARVED - ratio), 0.5)
	if ratio > CARB_BOGGED:
		return maxf(1.0 - 0.08 * (ratio - CARB_BOGGED), 0.9)
	return 1.0


func current_car_file_path() -> String:
	return car_file_path(current_car_id)


## Catalog id for an owned instance. A catalog id is returned unchanged.
func car_model_id(instance_id: String) -> String:
	if instance_id.is_empty():
		return ""
	var stored: Variant = car_records.get(instance_id, null)
	if typeof(stored) == TYPE_DICTIONARY:
		var model := str((stored as Dictionary).get("model_id", ""))
		if not model.is_empty():
			return _migrate_car_id(model)
	var migrated := _migrate_car_id(instance_id)
	if not listing_by_id(USED_CARS, migrated).is_empty():
		return migrated
	return ""


func car_display_name(instance_id: String) -> String:
	var car: Dictionary = listing_by_id(USED_CARS, car_model_id(instance_id))
	var label := str(car.get("name", ""))
	if label.is_empty():
		return "Car"
	return label


func car_file_path(instance_or_model: String) -> String:
	var model := car_model_id(instance_or_model)
	if model.is_empty():
		model = instance_or_model
	var car: Dictionary = listing_by_id(USED_CARS, model)
	var path := str(car.get("car_file", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return PLAYER_CAR_FILE
	return path


func load_player_car() -> void:
	if not has_active_car():
		car_spec = {}
		return
	car_spec = _CarFile.load_path(current_car_file_path())
	var errors: Variant = car_spec.get("errors", [])
	if typeof(errors) == TYPE_ARRAY:
		for err: String in errors:
			push_error(str(err))
	_ensure_stock_fitment()


func _ensure_stock_fitment() -> void:
	var engine_id := str(get_stock_engine().get("id", equipped_engine_id))
	var wheel_id := equipped_wheel_id
	var wheels: Variant = car_spec.get("wheels", {})
	if typeof(wheels) == TYPE_DICTIONARY:
		wheel_id = str((wheels as Dictionary).get("part", wheel_id))
	if equipped_engine_id != NO_ENGINE_ID:
		if not engine_id.is_empty() and not owned_engine_ids.has(engine_id):
			owned_engine_ids.append(engine_id)
		if equipped_engine_id.is_empty() or listing_by_id(ENGINES, equipped_engine_id).is_empty():
			equipped_engine_id = engine_id
	# Wheels sold stay sold: whatever is fitted is owned already (`_own_fitted_parts()`).
	if equipped_wheel_id != NO_WHEEL_ID and (equipped_wheel_id.is_empty() or listing_by_id(WHEELS, equipped_wheel_id).is_empty()):
		equipped_wheel_id = wheel_id


func get_stock_engine() -> Dictionary:
	var engine: Variant = car_spec.get("engine", {})
	if typeof(engine) != TYPE_DICTIONARY:
		return {}
	return engine


func get_stock_transmission() -> Dictionary:
	var box: Variant = car_spec.get("transmission", {})
	if typeof(box) != TYPE_DICTIONARY:
		return {}
	return box


func new_game() -> void:
	save_slot = 0
	driver_name = ""
	driver_traits = DRIVER_TRAITS_DEFAULT.duplicate()
	car_name = "Corvette 1956"
	car_color = Color(0.78, 0.14, 0.14, 1.0)
	fuel = DEFAULT_TANK_L
	vmax_kmh = 220.0
	engine_power_hp = 280.0
	engine_tune = ENGINE_TUNE_DEFAULT
	current_scene_path = SCENE_GARAGE
	selected_opponent_id = 0
	opponents.clear()
	selected_race_type = RACE_DRAG
	mulholland_course = randi() % MULHOLLAND_COURSES
	race_stake = 0
	race_pink_slips = false
	cars_just_gone = false
	drive_into_garage = false
	cruise_from_poi = ""
	cruise_to_poi = ""
	cruise_scene = ""
	hood_peek.clear()
	drive_in_rival_index = -1
	drive_in_hood_seen = false
	money = 2500
	_next_car_serial = 1
	owned_car_ids.clear()
	current_car_id = ""
	owned_part_ids.clear()
	equipped_part_ids.clear()
	owned_gearbox_ids.clear()
	owned_engine_ids.clear()
	owned_wheel_ids.clear()
	equipped_gearbox_id = DEFAULT_GEARBOX_ID
	gearbox_bolts = _tight_bolts()
	slot_part_ids = STOCK_SLOT_PARTS.duplicate()
	engine_bolts = {}
	plug_wires = true
	equipped_engine_id = ""
	equipped_wheel_id = ""
	car_records.clear()
	spare_conditions.clear()
	spare_wheel_tires.clear()
	_last_offers.clear()
	current_car_id = _add_owned_car(DEFAULT_CAR_ID, car_color)
	_install_car(current_car_id)
	set_fuel(_starting_fuel())
	_sync_record_from_active()


func save_slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [save_dir, slot]


func has_save_file(slot: int = 0) -> bool:
	_bring_in_legacy_save()
	if slot > 0:
		return FileAccess.file_exists(save_slot_path(slot))
	for i in range(1, SAVE_SLOTS + 1):
		if FileAccess.file_exists(save_slot_path(i)):
			return true
	return false


## What a slot's save list line shows: `car_name`, `money`, `cars` (how many owned) and
## `saved_at` (a Unix time). Empty when the slot has no save.
func save_slot_info(slot: int) -> Dictionary:
	_bring_in_legacy_save()
	var path := save_slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"car_name": "Unreadable save", "money": 0, "cars": 0, "saved_at": FileAccess.get_modified_time(path)}
	var d: Dictionary = parsed
	var owned: Variant = d.get("owned_car_ids", [])
	return {
		"car_name": str(d.get("car_name", "")),
		"money": int(d.get("money", 0)),
		"cars": owned.size() if typeof(owned) == TYPE_ARRAY else 0,
		"saved_at": int(d.get("saved_at", FileAccess.get_modified_time(path))),
	}


## Moves the save from before slots into slot 1, if slot 1 is free.
func _bring_in_legacy_save() -> void:
	if legacy_save_path.is_empty() or not FileAccess.file_exists(legacy_save_path):
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	if FileAccess.file_exists(save_slot_path(1)):
		return
	var err := DirAccess.rename_absolute(legacy_save_path, save_slot_path(1))
	if err != OK:
		push_warning("Could not move the old save into slot 1: %s" % error_string(err))


func save_game(slot: int) -> bool:
	if slot < 1 or slot > SAVE_SLOTS:
		return false
	_bring_in_legacy_save()
	DirAccess.make_dir_recursive_absolute(save_dir)
	var data := {
		"version": 2,
		"saved_at": int(Time.get_unix_time_from_system()),
		"car_name": car_name,
		"car_color": [car_color.r, car_color.g, car_color.b, car_color.a],
		"fuel": fuel,
		"cars": _cars_for_save(),
		"vmax_kmh": vmax_kmh,
		"engine_power_hp": engine_power_hp,
		"current_scene_path": current_scene_path,
		"selected_opponent_id": selected_opponent_id,
		"opponents": _opponents_for_save(),
		"selected_race_type": selected_race_type,
		"mulholland_course": mulholland_course,
		"race_stake": race_stake,
		"race_pink_slips": race_pink_slips,
		"driver_name": driver_name,
		"driver_traits": driver_traits,
		"money": money,
		"current_car_id": current_car_id,
		"owned_car_ids": owned_car_ids,
		"next_car_serial": _next_car_serial,
		"owned_part_ids": owned_part_ids,
		"equipped_part_ids": equipped_part_ids,
		"owned_gearbox_ids": owned_gearbox_ids,
		"equipped_gearbox_id": equipped_gearbox_id,
		"owned_engine_ids": owned_engine_ids,
		"equipped_engine_id": equipped_engine_id,
		"owned_wheel_ids": owned_wheel_ids,
		"equipped_wheel_id": equipped_wheel_id,
		"spare_conditions": spare_conditions,
		"spare_wheel_tires": spare_wheel_tires,
	}
	var json := JSON.stringify(data)
	var path := save_slot_path(slot)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save: %s" % path)
		return false
	f.store_string(json)
	f.close()
	save_slot = slot
	return true


func load_game(slot: int) -> bool:
	if not has_save_file(slot):
		return false
	var f := FileAccess.open(save_slot_path(slot), FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	car_name = str(d.get("car_name", car_name))
	var loaded_color: Variant = d.get("car_color", null)
	if typeof(loaded_color) == TYPE_ARRAY and loaded_color.size() >= 3:
		var r := float(loaded_color[0])
		var g := float(loaded_color[1])
		var b := float(loaded_color[2])
		var a := float(loaded_color[3]) if loaded_color.size() >= 4 else 1.0
		car_color = Color(r, g, b, a)
	fuel = float(d.get("fuel", DEFAULT_TANK_L))
	vmax_kmh = float(d.get("vmax_kmh", vmax_kmh))
	engine_power_hp = float(d.get("engine_power_hp", engine_power_hp))
	current_scene_path = str(d.get("current_scene_path", SCENE_GARAGE))
	if current_scene_path == "res://scenes/opponent_select.tscn":
		current_scene_path = SCENE_DRIVE_IN
	selected_opponent_id = int(d.get("selected_opponent_id", 0))
	_load_saved_opponents(d)
	var race_type := str(d.get("selected_race_type", RACE_DRAG))
	if race_on_track(race_type):
		selected_race_type = race_type
	else:
		selected_race_type = RACE_DRAG
	mulholland_course = posmod(int(d.get("mulholland_course", randi())), MULHOLLAND_COURSES)
	race_stake = maxi(int(d.get("race_stake", 0)), 0)
	race_pink_slips = bool(d.get("race_pink_slips", false))
	cars_just_gone = false
	drive_into_garage = false
	cruise_from_poi = ""
	cruise_to_poi = ""
	cruise_scene = ""
	hood_peek.clear()
	drive_in_rival_index = -1
	drive_in_hood_seen = false
	driver_name = str(d.get("driver_name", ""))
	driver_traits = DRIVER_TRAITS_DEFAULT.merged(d.get("driver_traits", {}), true)
	money = int(d.get("money", money))
	_next_car_serial = maxi(int(d.get("next_car_serial", 1)), 1)
	current_car_id = _migrate_car_id(str(d.get("current_car_id", current_car_id)))
	owned_car_ids = _string_array(d.get("owned_car_ids", owned_car_ids))
	for i in owned_car_ids.size():
		owned_car_ids[i] = _migrate_car_id(owned_car_ids[i])
	owned_part_ids = _string_array(d.get("owned_part_ids", owned_part_ids))
	if d.has("equipped_part_ids"):
		equipped_part_ids = _string_array(d.get("equipped_part_ids", []))
	else:
		equipped_part_ids = owned_part_ids.duplicate()
	owned_gearbox_ids = _string_array(d.get("owned_gearbox_ids", owned_gearbox_ids))
	equipped_gearbox_id = str(d.get("equipped_gearbox_id", equipped_gearbox_id))
	owned_engine_ids = _string_array(d.get("owned_engine_ids", owned_engine_ids))
	equipped_engine_id = str(d.get("equipped_engine_id", equipped_engine_id))
	owned_wheel_ids = _string_array(d.get("owned_wheel_ids", owned_wheel_ids))
	equipped_wheel_id = str(d.get("equipped_wheel_id", equipped_wheel_id))
	spare_conditions = _conditions_pool_from(d.get("spare_conditions", null))
	spare_wheel_tires = _spare_wheel_tires_from(d.get("spare_wheel_tires", null))
	_last_offers.clear()
	if owned_gearbox_ids.is_empty():
		owned_gearbox_ids = [DEFAULT_GEARBOX_ID]
	if equipped_gearbox_id != NO_GEARBOX_ID:
		if listing_by_id(GEARBOXES, equipped_gearbox_id).is_empty():
			equipped_gearbox_id = DEFAULT_GEARBOX_ID
		if not owns_gearbox(equipped_gearbox_id):
			owned_gearbox_ids.append(equipped_gearbox_id)
	_load_saved_cars(d)
	_own_fitted_parts()
	if has_active_car():
		load_player_car()
		_sync_record_from_active()
		refresh_car_stats()
	else:
		current_car_id = ""
		car_spec = {}
		car_name = "No car"
	save_slot = slot
	return true


func roll_newspaper_colors() -> void:
	newspaper_colors.clear()
	for car in USED_CARS:
		var car_id := str(car.get("id", ""))
		if car_id.is_empty():
			continue
		newspaper_colors[car_id] = _random_paint()


func newspaper_color(car_id: String) -> Color:
	var rolled: Variant = newspaper_colors.get(car_id, null)
	if rolled is Color:
		return rolled
	var car: Dictionary = listing_by_id(USED_CARS, car_id)
	var listed: Variant = car.get("color", null)
	if listed is Color:
		return listed
	return car_color


func _random_paint() -> Color:
	return Color.from_hsv(randf(), randf_range(0.55, 0.95), randf_range(0.45, 0.92))


## Who turns up next. Once the newest rival has been beaten, the next call brings someone
## new, the next step up `_rival_ladder`. Until then it is anybody already met.
func call_random_opponent() -> int:
	var names := _opponent_name_pool()
	if names.is_empty():
		return -1
	if opponents.is_empty() or bool(opponents.back().get("beaten", false)):
		var unmet: Array[String] = []
		for opp_name in names:
			if _index_of_opponent(opp_name) < 0:
				unmet.append(opp_name)
		if not unmet.is_empty():
			return _meet_opponent(unmet[randi() % unmet.size()])
	var running: Array[int] = []
	var soonest := -1
	for i in opponents.size():
		if not opponent_needs_engine(opponents[i]):
			running.append(i)
		elif soonest < 0 or int(opponents[i].get("engine_wait", 0)) < int(opponents[soonest].get("engine_wait", 0)):
			soonest = i
	if not running.is_empty():
		return running[randi() % running.size()]
	# With nobody else to race there would be no races to wait for.
	if soonest >= 0:
		_fit_rival_engine(opponents[soonest])
	return soonest


## A rival with no engine in their car can't drive it, so they don't turn up.
func opponent_needs_engine(opp: Dictionary) -> bool:
	return str(opp.get("engine", "")) == NO_ENGINE_ID


## Every race the player runs brings the rivals waiting on an engine closer to having one.
func note_race_started() -> void:
	for opp in opponents:
		if not opponent_needs_engine(opp):
			continue
		opp["engine_wait"] = int(opp.get("engine_wait", 0)) - 1
		if int(opp["engine_wait"]) <= 0:
			_fit_rival_engine(opp)


## Puts the engine the car came with into a rival's car. Everything else on the car stays
## as it is, the parts that were on the blown engine going on this one.
func _fit_rival_engine(opp: Dictionary) -> void:
	var stock := _opponent_stock_build(str(opp.get("car_file", "")))
	var hood := opponent_hood_parts(opp)
	var slots := hood
	var taken: Variant = opp.get("taken_car", null)
	if typeof(taken) == TYPE_DICTIONARY:
		(taken as Dictionary)["engine_id"] = str(stock["engine"])
		slots = (taken as Dictionary)["slot_parts"]
	var build := {"hp": float(stock["hp"]), "vmax": float(stock["vmax"])}
	_add_rival_parts(build, slots)
	var diff := listing_by_id(PARTS, str(slots.get(SLOT_DIFFERENTIAL, NO_PART_ID)))
	opp["engine"] = str(stock["engine"])
	opp["engine_hp"] = build["hp"]
	opp["hp"] = float(build["hp"]) * float(diff.get("accel", 1.0))
	opp["vmax"] = float(build["vmax"]) * float(diff.get("top_speed", 1.0))
	opp.erase("engine_wait")


func selected_opponent() -> Dictionary:
	return opponent_at(selected_opponent_id)


func opponent_at(index: int) -> Dictionary:
	if index < 0 or index >= opponents.size():
		return {}
	return opponents[index]


func _opponent_name_pool() -> Array[String]:
	if not _opponent_names.is_empty():
		return _opponent_names
	_opponent_names = _load_opponent_names()
	return _opponent_names


func opponent_skin(opp_name: String) -> Color:
	_opponent_name_pool()
	var stored: Variant = _opponent_skins.get(opp_name, null)
	if stored is Color:
		return stored
	return Color(0.76, 0.58, 0.44)


func opponent_head(opp_name: String) -> String:
	_opponent_name_pool()
	var path := str(_opponent_heads.get(opp_name, "")).strip_edges()
	if path.is_empty():
		return DEFAULT_OPPONENT_HEAD
	return path


## A rival's pronoun, "subject" or "possessive", in lower case.
func opponent_pronoun(opp: Dictionary, form: String) -> String:
	_opponent_name_pool()
	var gender := str(_opponent_genders.get(str(opp.get("name", "")), ""))
	return str(_PRONOUNS.get(gender, _PRONOUNS_DEFAULT)[form])


func _index_of_opponent(opp_name: String) -> int:
	for i in opponents.size():
		if str(opponents[i].get("name", "")) == opp_name:
			return i
	return -1


func _meet_opponent(opp_name: String) -> int:
	var index := opponents.size()
	opponents.append({"id": index, "name": opp_name, "tier": index, "beaten": false, "color": _random_paint()})
	_apply_rival_build(opponents[index], _ladder_row(index))
	return index


func _ladder_row(tier: int) -> Dictionary:
	_opponent_name_pool()
	if _rival_ladder.is_empty():
		return {}
	return _rival_ladder[clampi(tier, 0, _rival_ladder.size() - 1)]


## The rival's car and everything about how it goes, from a row of the ladder. A rival's
## performance comes from here, never from the player's car.
func _apply_rival_build(opp: Dictionary, row: Dictionary) -> void:
	var car := listing_by_id(USED_CARS, str(row.get("car", "")))
	if car.is_empty() and not USED_CARS.is_empty():
		car = USED_CARS[0]
	opp["car_id"] = str(car.get("id", ""))
	opp["car_name"] = str(car.get("name", "Car"))
	opp["car_file"] = str(car.get("car_file", ""))
	opp["tires"] = str(row.get("tires", STOCK_SLOT_PARTS[SLOT_TIRES]))
	opp["accel_scale"] = float(row.get("accel_scale", 0.3))
	opp["vmax_scale"] = float(row.get("vmax_scale", 0.9))
	opp["shift_time"] = float(row.get("shift_time", 0.35))
	opp["springs"] = str(row.get("springs", STOCK_SLOT_PARTS[SLOT_SPRINGS]))
	opp["shocks"] = str(row.get("shocks", STOCK_SLOT_PARTS[SLOT_SHOCKS]))
	var build := _opponent_stock_build(opp["car_file"])
	var engine := listing_by_id(ENGINES, str(row.get("engine", build["engine"])))
	if not engine.is_empty():
		build["engine"] = str(engine.get("id", ""))
		build["hp"] = float(engine.get("hp", 280.0))
		build["vmax"] = float(engine.get("vmax", 220.0))
	var hood := _rival_hood_parts(row.get("parts", {}))
	_add_rival_parts(build, hood)
	build["engine_hp"] = build["hp"]
	build["hood_parts"] = hood
	opp.erase("taken_car")
	build["gearbox"] = str(row.get("gearbox", build["gearbox"]))
	opp.merge(build, true)


## Adds what the parts in `slots` give to a rival's `build`. Each muffler of a dual exhaust
## does half the work, and each carburetor of a multi-carb intake its share, as on the
## player's car. Tires are counted in the race.
func _add_rival_parts(build: Dictionary, slots: Dictionary) -> void:
	var intake := listing_by_id(PARTS, str(slots.get(SLOT_INTAKE, NO_PART_ID)))
	var carb_share := 1.0 / float(clampi(int(intake.get("carbs", 1)), 1, CARB_SLOTS.size()))
	var muffler_share := 0.5 if str(slots.get(SLOT_MUFFLER_LEFT, NO_PART_ID)) != NO_PART_ID else 1.0
	for slot: String in slots:
		if slot == SLOT_TIRES:
			continue
		var part := listing_by_id(PARTS, str(slots[slot]))
		var share := 1.0
		if spot_kind(slot) == SLOT_CARB:
			share = carb_share
		elif spot_kind(slot) == SLOT_MUFFLER:
			share = muffler_share
		build["hp"] += float(part.get("hp", 0.0)) * share
		build["vmax"] += float(part.get("vmax", 0.0)) * share


## A rival's own hood parts by slot: stock wherever `listed` names nothing.
func _rival_hood_parts(listed: Variant) -> Dictionary:
	var hood := {}
	for slot in HOOD_SLOTS:
		hood[slot] = str(STOCK_SLOT_PARTS[slot])
	if typeof(listed) != TYPE_DICTIONARY:
		return hood
	for slot: String in hood.keys():
		var part_id := str((listed as Dictionary).get(slot, hood[slot]))
		if part_id == NO_PART_ID or not listing_by_id(PARTS, part_id).is_empty():
			hood[slot] = part_id
	return hood


## What is under a rival's hood, slot to part id.
func opponent_hood_parts(opp: Dictionary) -> Dictionary:
	return _rival_hood_parts(opp.get("hood_parts", {}))


## Marks the selected rival as beaten, which brings the next one along.
func note_race_win() -> void:
	var opp := selected_opponent()
	if not opp.is_empty():
		opp["beaten"] = true


## What a car came with: its power, top speed before gearing and tires, engine, and gearbox.
func _opponent_stock_build(car_file: String) -> Dictionary:
	var spec := _CarFile.load_path(car_file)
	var engine: Dictionary = spec.get("engine", {})
	var gearbox: Dictionary = spec.get("transmission", {})
	return {
		"hp": float(engine.get("hp", 280.0)),
		"vmax": float(engine.get("vmax", 220.0)),
		"engine": str(engine.get("id", "")),
		"gearbox": str(gearbox.get("id", DEFAULT_GEARBOX_ID)),
	}


func _load_opponent_names() -> Array[String]:
	var names: Array[String] = []
	if not FileAccess.file_exists(OPPONENTS_PATH):
		push_error("Opponents file missing: %s" % OPPONENTS_PATH)
		return names
	var file := FileAccess.open(OPPONENTS_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open opponents file: %s" % OPPONENTS_PATH)
		return names
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Opponents file must be a JSON object: %s" % OPPONENTS_PATH)
		return names
	var root: Dictionary = parsed
	var listed: Variant = root.get("names", [])
	if typeof(listed) != TYPE_ARRAY:
		push_error("Opponents file must contain a names list: %s" % OPPONENTS_PATH)
		return names
	_opponent_skins.clear()
	_opponent_heads.clear()
	_opponent_genders.clear()
	_rival_ladder = _dict_list(root.get("ladder", []))
	for item: Variant in listed:
		var name := ""
		var skin := Color(0.76, 0.58, 0.44)
		var head := DEFAULT_OPPONENT_HEAD
		var gender := ""
		if typeof(item) == TYPE_DICTIONARY:
			var row: Dictionary = item
			name = str(row.get("name", "")).strip_edges()
			gender = str(row.get("gender", ""))
			skin = _color_from_save(row.get("skin", null), skin)
			var listed_head := str(row.get("head", "")).strip_edges()
			if not listed_head.is_empty():
				head = listed_head
		else:
			name = str(item).strip_edges()
		if name.is_empty() or names.has(name):
			continue
		names.append(name)
		_opponent_skins[name] = skin
		_opponent_heads[name] = head
		_opponent_genders[name] = gender
	return names


func _opponents_for_save() -> Array:
	var rows: Array = []
	for opp in opponents:
		var paint := Color(0.8, 0.1, 0.1)
		var stored: Variant = opp.get("color", null)
		if stored is Color:
			paint = stored
		rows.append({
			"name": str(opp.get("name", "")),
			"car_id": str(opp.get("car_id", "")),
			"car_name": str(opp.get("car_name", "")),
			"car_file": str(opp.get("car_file", "")),
			"color": [paint.r, paint.g, paint.b, paint.a],
			"accel_scale": float(opp.get("accel_scale", 0.3)),
			"vmax_scale": float(opp.get("vmax_scale", 0.9)),
			"shift_time": float(opp.get("shift_time", 0.35)),
			"tires": str(opp.get("tires", "")),
			"springs": str(opp.get("springs", STOCK_SLOT_PARTS[SLOT_SPRINGS])),
			"shocks": str(opp.get("shocks", STOCK_SLOT_PARTS[SLOT_SHOCKS])),
			"hp": float(opp.get("hp", 280.0)),
			"engine_hp": float(opp.get("engine_hp", opp.get("hp", 280.0))),
			"hood_parts": opponent_hood_parts(opp),
			"vmax": float(opp.get("vmax", 220.0)),
			"engine": str(opp.get("engine", "")),
			"gearbox": str(opp.get("gearbox", DEFAULT_GEARBOX_ID)),
			"tier": int(opp.get("tier", 0)),
			"beaten": bool(opp.get("beaten", false)),
		})
		var taken: Variant = opp.get("taken_car", null)
		if typeof(taken) == TYPE_DICTIONARY:
			rows.back()["taken_car"] = _record_to_save(taken, str(opp.get("car_id", "")))
		if opponent_needs_engine(opp):
			rows.back()["engine_wait"] = int(opp.get("engine_wait", RIVAL_ENGINE_WAIT_RACES))
	return rows


func _load_saved_opponents(d: Dictionary) -> void:
	opponents.clear()
	var saved: Variant = d.get("opponents", [])
	if typeof(saved) != TYPE_ARRAY:
		return
	var i := 0
	for item: Variant in saved:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var name := str(row.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		opponents.append({
			"id": i,
			"name": name,
			"car_id": str(row.get("car_id", "")),
			"car_name": str(row.get("car_name", "Car")),
			"car_file": str(row.get("car_file", "")),
			"color": _color_from_save(row.get("color", null), Color(0.8, 0.1, 0.1)),
			"accel_scale": float(row.get("accel_scale", 0.3)),
			"vmax_scale": float(row.get("vmax_scale", 0.9)),
			"shift_time": float(row.get("shift_time", 0.35)),
			"tires": str(row.get("tires", "")),
			"springs": str(row.get("springs", STOCK_SLOT_PARTS[SLOT_SPRINGS])),
			"shocks": str(row.get("shocks", STOCK_SLOT_PARTS[SLOT_SHOCKS])),
			"tier": int(row.get("tier", i)),
			"beaten": bool(row.get("beaten", false)),
		})
		# Rivals in older saves went by the player's car, so they start on what theirs came with.
		var saved_build := row if row.has("hp") else _opponent_stock_build(str(row.get("car_file", "")))
		opponents[i]["hp"] = float(saved_build.get("hp", 280.0))
		opponents[i]["engine_hp"] = float(saved_build.get("engine_hp", opponents[i]["hp"]))
		opponents[i]["hood_parts"] = _rival_hood_parts(row.get("hood_parts", {}))
		var taken: Variant = row.get("taken_car", null)
		if typeof(taken) == TYPE_DICTIONARY:
			# A player's car with no engine loads with its parts off. This one waits with them on.
			var taken_row: Dictionary = (taken as Dictionary).duplicate()
			taken_row.erase("engine_id")
			var taken_rec := _record_from_save(taken_row, str(row.get("car_id", "")))
			taken_rec["engine_id"] = str((taken as Dictionary).get("engine_id", NO_ENGINE_ID))
			opponents[i]["taken_car"] = taken_rec
		opponents[i]["vmax"] = float(saved_build.get("vmax", 220.0))
		opponents[i]["gearbox"] = str(saved_build.get("gearbox", DEFAULT_GEARBOX_ID))
		opponents[i]["engine"] = str(saved_build.get("engine", ""))
		if opponent_needs_engine(opponents[i]):
			opponents[i]["engine_wait"] = int(row.get("engine_wait", RIVAL_ENGINE_WAIT_RACES))
		i += 1


func listing_by_id(list: Array[Dictionary], item_id: String) -> Dictionary:
	for item in list:
		if str(item.get("id", "")) == item_id:
			return item
	return {}


func owns_part(part_id: String) -> bool:
	return owned_part_ids.has(part_id)


func is_part_equipped(part_id: String) -> bool:
	return equipped_part_ids.has(part_id) or slot_part_ids.values().has(part_id)


func owns_car(model_id: String) -> bool:
	for instance_id in owned_car_ids:
		if car_model_id(instance_id) == model_id:
			return true
	return false


func owns_gearbox(gearbox_id: String) -> bool:
	return owned_gearbox_ids.has(gearbox_id)


func owns_engine(engine_id: String) -> bool:
	return owned_engine_ids.has(engine_id)


func owns_wheel(wheel_id: String) -> bool:
	return owned_wheel_ids.has(wheel_id)


func get_equipped_engine() -> Dictionary:
	if equipped_engine_id == NO_ENGINE_ID:
		return {}
	var engine: Dictionary = listing_by_id(ENGINES, equipped_engine_id)
	if engine.is_empty():
		return get_stock_engine()
	return engine


## How well the active car's tires hold the road, from 1 to 5.
func tire_grip() -> float:
	return _grip_of(slot_part(SLOT_TIRES)) if has_tires() else 1.0


func tires_worn_out() -> bool:
	return has_tires() and mount_condition("slot:" + SLOT_TIRES) <= TIRE_BLOWOUT_CONDITION


## How far from the finish worn-out tires let go in a race of `length_m`, or -1 if the tires
## will last.
func tire_blowout_distance_m(length_m: float) -> float:
	if not tires_worn_out():
		return -1.0
	return length_m * randf_range(TIRE_BLOWOUT_MIN, TIRE_BLOWOUT_MAX)


## A blowout: the tires are gone, not spares, and the wheels stay on the car.
func blow_tires() -> void:
	var tires := _tires_off_active_car()
	if tires.is_empty():
		return
	owned_part_ids.erase(str(tires.get("id", "")))
	_sync_record_from_active()
	refresh_car_stats()


## The tires on a rival's car. A rival from an older save is on the stock set.
func opponent_tires(opp: Dictionary) -> Dictionary:
	var tires := listing_by_id(PARTS, str(opp.get("tires", "")))
	if str(tires.get("slot", "")) != SLOT_TIRES:
		return listing_by_id(PARTS, str(STOCK_SLOT_PARTS[SLOT_TIRES]))
	return tires


func opponent_tire_grip(opp: Dictionary) -> float:
	return _grip_of(opponent_tires(opp))


## A rival's car's top speed through its gearbox and on its tires, before the driver's
## `vmax_scale`.
func opponent_top_kmh(opp: Dictionary) -> float:
	var top := float(opp.get("vmax", 220.0)) + float(opponent_tires(opp).get("vmax", 0.0))
	return top * float(opponent_gearbox(opp).get("top_speed", 1.0))


func opponent_power_hp(opp: Dictionary) -> float:
	return float(opp.get("hp", 280.0))


func opponent_gearbox(opp: Dictionary) -> Dictionary:
	var box := listing_by_id(GEARBOXES, str(opp.get("gearbox", "")))
	return listing_by_id(GEARBOXES, DEFAULT_GEARBOX_ID) if box.is_empty() else box


## The chassis of a rival's car, from its car file, on the rival's own springs and shocks.
func opponent_chassis(opp: Dictionary) -> Dictionary:
	var spec := _CarFile.load_path(str(opp.get("car_file", "")))
	var stored: Variant = spec.get("chassis", {})
	if typeof(stored) != TYPE_DICTIONARY or (stored as Dictionary).is_empty():
		return {}
	var chassis: Dictionary = (stored as Dictionary).duplicate()
	_put_on_suspension(chassis, listing_by_id(PARTS, str(opp.get("springs", ""))), listing_by_id(PARTS, str(opp.get("shocks", ""))), 1.0, 1.0)
	return chassis


## Sets a chassis's spring and shock rates and its ride height from the parts on it and
## what condition they are in. Lowering a car lowers its mass center too.
func _put_on_suspension(chassis: Dictionary, springs: Dictionary, shocks: Dictionary, spring_condition: float, shock_condition: float) -> void:
	chassis["spring_rate"] = float(springs.get("spring_rate", 1.0)) * lerpf(SPRING_WORN_RATE, 1.0, spring_condition)
	chassis["shock_rate"] = float(shocks.get("shock_rate", 1.0)) * lerpf(SHOCK_WORN_RATE, 1.0, shock_condition)
	var lower := float(springs.get("lower_m", 0.0))
	chassis["ride_lower"] = lower
	chassis["cg_height"] = float(chassis.get("cg_height", 0.48)) - lower


func _grip_of(tires: Dictionary) -> float:
	return clampf(float(tires.get("grip", 3.0)), 1.0, 5.0)


## How much heavier the active car's wheels make it than the set it came on, in kg as they
## count on the road. Lighter wheels make this negative.
func wheel_mass_delta_kg() -> float:
	var stock := listing_by_id(WHEELS, _stock_part_id(current_car_id, "wheels"))
	var fitted: Dictionary = listing_by_id(WHEELS, equipped_wheel_id)
	if stock.is_empty() or fitted.is_empty():
		return 0.0
	return (float(fitted.get("mass", 0.0)) - float(stock.get("mass", 0.0))) * WHEEL_ROTATING_FACTOR


## The active car's chassis for a race, with its wheels' weight counted in.
func race_chassis() -> Dictionary:
	var spec: Variant = car_spec.get("chassis", {})
	if typeof(spec) != TYPE_DICTIONARY or (spec as Dictionary).is_empty():
		return {}
	var chassis: Dictionary = (spec as Dictionary).duplicate()
	chassis["mass"] = float(chassis.get("mass", 1360.0)) + wheel_mass_delta_kg()
	_put_on_suspension(chassis, slot_part(SLOT_SPRINGS), slot_part(SLOT_SHOCKS), mount_condition("slot:" + SLOT_SPRINGS), mount_condition("slot:" + SLOT_SHOCKS))
	return chassis


## What the wheels' weight does to the pull in every gear, for the arcade drive, whose
## acceleration does not come from the mass. 1 on the wheels the car came on.
func wheel_weight_accel() -> float:
	var chassis := race_chassis()
	if chassis.is_empty():
		return 1.0
	var mass := float(chassis["mass"])
	return (mass - wheel_mass_delta_kg()) / maxf(mass, 1.0)


func wheel_detail(wheel: Dictionary) -> String:
	return "%s the set" % mass_text(float(wheel.get("mass", 0)))


func get_equipped_wheel() -> Dictionary:
	var wheel: Dictionary = listing_by_id(WHEELS, equipped_wheel_id)
	if wheel.is_empty():
		return {}
	return wheel


func get_equipped_gearbox() -> Dictionary:
	if equipped_gearbox_id == NO_GEARBOX_ID:
		return {}
	var stock := get_stock_transmission()
	if equipped_gearbox_id == str(stock.get("id", "")) and not stock.is_empty():
		return stock
	var box: Dictionary = listing_by_id(GEARBOXES, equipped_gearbox_id)
	if box.is_empty():
		if not stock.is_empty():
			return stock
		box = listing_by_id(GEARBOXES, DEFAULT_GEARBOX_ID)
	return box


func get_effective_vmax_kmh() -> float:
	var top := float(get_equipped_gearbox().get("top_speed", 1.0))
	return vmax_kmh * top * float(slot_part(SLOT_DIFFERENTIAL).get("top_speed", 1.0))


## Pull of the rear end against the stock gears. A shorter rear end pulls harder.
func final_drive_accel() -> float:
	return float(slot_part(SLOT_DIFFERENTIAL).get("accel", 1.0))


## How much louder the exhaust is than stock, in dB. Open headers or an open pipe count
## `OPEN_EXHAUST_DB`; the two sides of a dual exhaust are averaged.
func exhaust_volume_db() -> float:
	if not has_active_car():
		return 0.0
	if slot_part(SLOT_EXHAUST).is_empty():
		return OPEN_EXHAUST_DB
	var spots := muffler_slots()
	var total := 0.0
	for spot in spots:
		var muffler := slot_part(spot)
		total += OPEN_EXHAUST_DB if muffler.is_empty() else float(muffler.get("loud_db", 0.0))
	return total / float(spots.size())


func gearbox_ratio_text(box: Dictionary) -> String:
	var ratios: Variant = box.get("ratios", [])
	if typeof(ratios) != TYPE_ARRAY:
		return ""
	var bits: Array[String] = []
	for ratio: Variant in ratios:
		bits.append("%.2f" % float(ratio))
	return " · ".join(bits)


func refresh_car_stats() -> void:
	if not has_active_car():
		car_name = "No car"
		return
	var model := car_model_id(current_car_id)
	var car: Dictionary = listing_by_id(USED_CARS, model)
	if car.is_empty():
		car = listing_by_id(USED_CARS, DEFAULT_CAR_ID)
	car_name = str(car.get("name", car_name))
	if not has_engine():
		vmax_kmh = 0.0
		engine_power_hp = 0.0
		return
	vmax_kmh = float(car.get("vmax", vmax_kmh))
	engine_power_hp = float(car.get("hp", engine_power_hp))
	var engine := get_equipped_engine()
	if not engine.is_empty():
		if model == DEFAULT_CAR_ID:
			car_name = str(car_spec.get("name", car_name))
		vmax_kmh = float(engine.get("vmax", vmax_kmh))
		engine_power_hp = float(engine.get("hp", engine_power_hp))
	var tune_scale := engine_tune_scale(engine_tune, engine_sweet_tune())
	vmax_kmh *= tune_scale
	engine_power_hp *= tune_scale
	for part_id in equipped_part_ids:
		_add_part_stats(listing_by_id(PARTS, part_id), 1.0)
	# Each muffler of a dual exhaust does half the work, and each carburetor of a
	# multi-carb intake its share.
	var muffler_share := 1.0 / float(muffler_slots().size())
	var carb_share := 1.0 / float(maxi(carb_slots().size(), 1))
	for slot in active_slots():
		var share := 1.0
		if spot_kind(slot) == SLOT_MUFFLER:
			share = muffler_share
		elif spot_kind(slot) == SLOT_CARB:
			share = carb_share
		_add_part_stats(slot_part(slot), share)
	var flow := carb_flow_factor()
	vmax_kmh *= flow
	engine_power_hp *= flow


func _add_part_stats(part: Dictionary, share: float) -> void:
	if part.is_empty():
		return
	vmax_kmh += float(part.get("vmax", 0.0)) * share
	engine_power_hp += float(part.get("hp", 0.0)) * share


func set_engine_tune(step: int) -> void:
	engine_tune = clampi(step, ENGINE_TUNE_MIN, ENGINE_TUNE_MAX)
	_sync_record_from_active()
	refresh_car_stats()


## Heat from a finished race. Returns how many steps the timing actually moved.
func drift_engine_tune_after_race() -> int:
	var before := engine_tune
	var roll := randf()
	var delta := 0
	# Better ignition holds its timing better.
	var steady := float(slot_part(SLOT_DISTRIBUTOR).get("drift", 1.0))
	if roll < ENGINE_TUNE_DRIFT_DOWN * steady:
		delta = -1
	elif roll < (ENGINE_TUNE_DRIFT_DOWN + ENGINE_TUNE_DRIFT_UP) * steady:
		delta = 1
	set_engine_tune(before + delta)
	return engine_tune - before


## Timing step where this engine makes its rated power. Stable for a given engine id.
func engine_sweet_tune(engine_id: String = "") -> int:
	var id := equipped_engine_id if engine_id.is_empty() else engine_id
	if id.is_empty():
		return 6
	return 2 + absi(id.hash()) % 7


## 1 at the sweet spot, down to 0.68 several steps away.
func engine_tune_scale(tune: int, sweet: int) -> float:
	var t := clampf(float(absi(tune - sweet)) / 5.0, 0.0, 1.0)
	return lerpf(1.0, 0.68, t * t)


func buy_part(part_id: String) -> String:
	var part: Dictionary = listing_by_id(PARTS, part_id)
	if part.is_empty():
		return "That part is not in the paper."
	# Any number of a part can be bought, one for each car or each side of a dual
	# exhaust, stock parts too: one sold has to be bought back.
	var price := int(part.get("price", 0))
	if money < price:
		return "Not enough cash."
	money -= price
	owned_part_ids.append(part_id)
	return ""


## Copies of a part that are owned, on a car or not.
func part_count(part_id: String) -> int:
	return owned_part_ids.count(part_id)


## Copies of a part that are owned and on no car.
func spare_count(part_id: String) -> int:
	return free_spare_count("part", part_id)


# --- Condition and selling --------------------------------------------------------


## What is fitted to the active car, by mount: "engine", "transmission", "wheels",
## "slot:<slot>" and "bolt:<part id>", each as [kind, id].
func _active_mounts() -> Dictionary:
	var out := {}
	if has_engine():
		out["engine"] = ["engine", equipped_engine_id]
	if not equipped_gearbox_id.is_empty() and equipped_gearbox_id != NO_GEARBOX_ID:
		out["transmission"] = ["transmission", equipped_gearbox_id]
	if not equipped_wheel_id.is_empty() and equipped_wheel_id != NO_WHEEL_ID:
		out["wheels"] = ["wheels", equipped_wheel_id]
	for slot in ALL_SLOTS:
		var part_id := str(slot_part_ids.get(slot, NO_PART_ID))
		if part_id != NO_PART_ID and not part_id.is_empty():
			out["slot:" + slot] = ["part", part_id]
	for part_id in equipped_part_ids:
		out["bolt:" + part_id] = ["part", part_id]
	return out


## Brings a car record's conditions up to what is fitted now. What came off goes to the
## spares pool with its wear; what went on comes out of the pool (its best copy), or is
## new. A car with no conditions yet came used, so all it has is used.
func _settle_conditions(rec: Dictionary) -> void:
	var used := not rec.has("conditions")
	var old: Dictionary = rec.get("conditions", {})
	var mounts := _active_mounts()
	var now := {}
	for mount: String in old.keys():
		var entry: Dictionary = old[mount]
		var fitted: Variant = mounts.get(mount, null)
		if fitted == null or str(fitted[1]) != str(entry.get("id", "")):
			_push_spare_condition(str(entry.get("kind", "")), str(entry.get("id", "")), float(entry.get("c", 1.0)))
	for mount: String in mounts.keys():
		var kind := str(mounts[mount][0])
		var id := str(mounts[mount][1])
		var entry: Variant = old.get(mount, null)
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == id:
			now[mount] = entry
			continue
		var c := randf_range(CONDITION_USED_MIN, CONDITION_USED_MAX) if used else _pop_spare_condition(kind, id)
		now[mount] = {"kind": kind, "id": id, "c": c}
	rec["conditions"] = now


func _condition_key(kind: String, id: String) -> String:
	return "%s:%s" % [kind, id]


func _push_spare_condition(kind: String, id: String, c: float) -> void:
	if kind.is_empty() or id.is_empty():
		return
	var key := _condition_key(kind, id)
	var pool: Array = spare_conditions.get(key, [])
	pool.append(clampf(c, CONDITION_FLOOR, 1.0))
	spare_conditions[key] = pool


## The best spare copy's condition, taken out of the pool; new when there is none.
func _pop_spare_condition(kind: String, id: String) -> float:
	var key := _condition_key(kind, id)
	var pool: Array = spare_conditions.get(key, [])
	if pool.is_empty():
		return 1.0
	pool.sort()
	var c := float(pool.pop_back())
	spare_conditions[key] = pool
	return c


## Everything fitted to a car is an owned copy: what a car comes with, and what saves
## from when stock parts did not run out, or two cars shared one engine, are missing.
func _own_fitted_parts() -> void:
	var fitted := {}
	for stored: Variant in car_records.values():
		if typeof(stored) != TYPE_DICTIONARY:
			continue
		for mount: Array in _record_mounts(stored):
			fitted[mount] = int(fitted.get(mount, 0)) + 1
	for mount: Array in fitted.keys():
		var owned := _owned_list(mount[0])
		while owned.count(mount[1]) < int(fitted[mount]):
			owned.append(mount[1])


## Owned copies that are on no car.
func free_spare_count(kind: String, id: String) -> int:
	var owned := 0
	var key := ""
	match kind:
		"part":
			owned = owned_part_ids.count(id)
		"engine":
			owned = owned_engine_ids.count(id)
			key = "engine_id"
		"transmission":
			owned = owned_gearbox_ids.count(id)
			key = "gearbox_id"
		"wheels":
			owned = owned_wheel_ids.count(id)
			key = "wheel_id"
	var mounted := 0
	for raw_id: String in car_records.keys():
		var stored: Variant = car_records[raw_id]
		if typeof(stored) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = stored
		if kind == "part":
			var slots: Variant = rec.get("slot_parts", {})
			if typeof(slots) == TYPE_DICTIONARY:
				mounted += (slots as Dictionary).values().count(id)
			mounted += _string_array(rec.get("part_ids", [])).count(id)
		elif str(rec.get(key, "")) == id:
			mounted += 1
	if kind == "part":
		for sets: Array in spare_wheel_tires.values():
			for tires: Dictionary in sets:
				if str(tires.get("id", "")) == id:
					mounted += 1
	return maxi(owned - mounted, 0)


## Keeps one condition in the pool for each spare that is on no car: dropping the most
## worn when there are too many (sold, blown), adding new ones for parts just bought.
func _trim_spare_conditions() -> void:
	var lists := {"part": PARTS, "engine": ENGINES, "transmission": GEARBOXES, "wheels": WHEELS}
	var kept := {}
	for kind: String in lists.keys():
		for item: Dictionary in lists[kind]:
			var id := str(item.get("id", ""))
			var key := _condition_key(kind, id)
			var pool: Array = spare_conditions.get(key, [])
			var target := free_spare_count(kind, id)
			pool.sort()
			while pool.size() > target:
				pool.pop_front()
			while pool.size() < target:
				pool.append(1.0)
			if not pool.is_empty():
				kept[key] = pool
	spare_conditions = kept


## Conditions of the spare copies on no car, best first.
func spare_condition_list(kind: String, id: String) -> Array[float]:
	var out: Array[float] = []
	for c: float in spare_conditions.get(_condition_key(kind, id), []):
		out.append(float(c))
	out.sort()
	out.reverse()
	return out


## Condition of what is fitted at `mount` on the active car (see `_active_mounts()`).
func mount_condition(mount: String) -> float:
	var rec: Variant = car_records.get(current_car_id, null)
	if typeof(rec) != TYPE_DICTIONARY:
		return 1.0
	var conditions: Variant = (rec as Dictionary).get("conditions", {})
	if typeof(conditions) != TYPE_DICTIONARY:
		return 1.0
	var entry: Variant = (conditions as Dictionary).get(mount, null)
	return float((entry as Dictionary).get("c", 1.0)) if entry is Dictionary else 1.0


## Everything on the active car wears a little in a race.
func wear_parts_after_race() -> void:
	_sync_record_from_active()
	var rec: Dictionary = car_records.get(current_car_id, {})
	var conditions: Dictionary = rec.get("conditions", {})
	for mount: String in conditions.keys():
		var entry: Dictionary = conditions[mount]
		entry["c"] = maxf(float(entry.get("c", 1.0)) - randf_range(CONDITION_WEAR_MIN, CONDITION_WEAR_MAX), CONDITION_FLOOR)


## A race's crashes wear everything on the active car, by how close they came to totaling
## it (0 to 1). Each part takes between half and all of the most it can lose.
func wear_parts_from_crashes(damage: float) -> void:
	if damage <= 0.0:
		return
	_sync_record_from_active()
	var rec: Dictionary = car_records.get(current_car_id, {})
	var conditions: Dictionary = rec.get("conditions", {})
	for mount: String in conditions.keys():
		var entry: Dictionary = conditions[mount]
		var wear := damage * CRASH_WEAR_MAX * randf_range(0.5, 1.0)
		entry["c"] = maxf(float(entry.get("c", 1.0)) - wear, CONDITION_FLOOR)


## The register entry for an id of a garage parts-list kind.
func listing_for(kind: String, id: String) -> Dictionary:
	match kind:
		"engine":
			return listing_by_id(ENGINES, id)
		"transmission":
			return listing_by_id(GEARBOXES, id)
		"wheels":
			return listing_by_id(WHEELS, id)
	return listing_by_id(PARTS, id)


## Why a spare cannot be sold, or "" when it can. Only copies on no car sell.
func sell_trouble(kind: String, id: String) -> String:
	var item := listing_for(kind, id)
	if item.is_empty():
		return "Nobody knows what that is."
	if int(item.get("price", 0)) <= 0:
		return "Nobody would pay for that."
	if free_spare_count(kind, id) <= 0:
		return "It is on one of your cars."
	return ""


## A buyer's offer for the most worn spare copy, in dollars: between `SELL_OFFER_MIN`
## and `SELL_OFFER_MAX` of the paper's price, likelier high the better its condition,
## and never the same as the last offer for it.
func sell_offer(kind: String, id: String) -> int:
	var price := int(listing_for(kind, id).get("price", 0))
	if kind == "wheels":
		price += int(tires_sold_with_wheels(id).get("price", 0))
	var list := spare_condition_list(kind, id)
	var c := list[list.size() - 1] if not list.is_empty() else 1.0
	var key := _condition_key(kind, id)
	var last := int(_last_offers.get(key, -1))
	var offer := last
	for _try in 20:
		var x := pow(randf(), lerpf(3.0, 0.4, c))
		offer = roundi(float(price) * lerpf(SELL_OFFER_MIN, SELL_OFFER_MAX, x))
		if offer != last:
			break
	_last_offers[key] = offer
	return offer


## Sells the most worn spare copy for `offer`.
func sell_spare(kind: String, id: String, offer: int) -> String:
	var err := sell_trouble(kind, id)
	if not err.is_empty():
		return err
	if kind == "wheels" and not tires_sold_with_wheels(id).is_empty():
		owned_part_ids.erase(str(_pop_spare_wheel_tires(id).get("id", "")))
	_owned_list(kind).erase(id)
	var key := _condition_key(kind, id)
	var pool: Array = spare_conditions.get(key, [])
	if not pool.is_empty():
		pool.sort()
		pool.pop_front()
		spare_conditions[key] = pool
	_last_offers.erase(key)
	money += maxi(offer, 0)
	_sync_record_from_active()
	return ""


## The list holding the owned copies of a kind, one entry for each copy.
func _owned_list(kind: String) -> Array[String]:
	match kind:
		"engine":
			return owned_engine_ids
		"transmission":
			return owned_gearbox_ids
		"wheels":
			return owned_wheel_ids
	return owned_part_ids


## Takes the condition of what another car had at `mount` into the spares pool, when a
## part comes off that car to go on the active one.
func _release_condition(rec: Dictionary, mount: String) -> void:
	var conditions: Variant = rec.get("conditions", null)
	if typeof(conditions) != TYPE_DICTIONARY or not (conditions as Dictionary).has(mount):
		return
	var entry: Dictionary = conditions[mount]
	_push_spare_condition(str(entry.get("kind", "")), str(entry.get("id", "")), float(entry.get("c", 1.0)))
	(conditions as Dictionary).erase(mount)


func _mount_conditions_from(value: Variant) -> Dictionary:
	var out := {}
	if typeof(value) != TYPE_DICTIONARY:
		return out
	for mount: String in (value as Dictionary).keys():
		var entry: Variant = value[mount]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		out[str(mount)] = {
			"kind": str(entry.get("kind", "")),
			"id": str(entry.get("id", "")),
			"c": clampf(float(entry.get("c", 1.0)), CONDITION_FLOOR, 1.0),
		}
	return out


func _conditions_pool_from(value: Variant) -> Dictionary:
	var out := {}
	if typeof(value) != TYPE_DICTIONARY:
		return out
	for key: String in (value as Dictionary).keys():
		var pool: Array = []
		if typeof(value[key]) == TYPE_ARRAY:
			for c: Variant in value[key]:
				pool.append(clampf(float(c), CONDITION_FLOOR, 1.0))
		out[str(key)] = pool
	return out


func equip_part(part_id: String) -> String:
	if not part_slot(part_id).is_empty():
		return fit_slot_part(part_id)
	if is_part_equipped(part_id):
		return "Already on the car."
	if spare_count(part_id) <= 0:
		return "That part is not in spare parts."
	equipped_part_ids.append(part_id)
	_sync_record_from_active()
	refresh_car_stats()
	return ""


## A bought gearbox goes to spare parts. It is fitted under the car (`fit_gearbox`).
func buy_gearbox(gearbox_id: String) -> String:
	var box: Dictionary = listing_by_id(GEARBOXES, gearbox_id)
	if box.is_empty():
		return "That gearbox is not in the paper."
	if equipped_gearbox_id == gearbox_id:
		return "Already on the car."
	if free_spare_count("transmission", gearbox_id) > 0:
		return "Already in spare parts."
	var price := int(box.get("price", 0))
	if money < price:
		return "Not enough cash."
	money -= price
	owned_gearbox_ids.append(gearbox_id)
	return ""


## Owned gearboxes that are in no car, in register order.
func spare_gearboxes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for box in GEARBOXES:
		var box_id := str(box.get("id", ""))
		if free_spare_count("transmission", box_id) > 0:
			out.append(box)
	return out


## Where a click takes a bolt at `turns`: one out of its hole threads in and runs down to
## `BOLT_THREADED`, a loose one tightens a turn, a tight one loosens back to a turn, and
## one that was being loosened comes out. `loosening` is whether the last click on it
## loosened it.
static func next_bolt_turns(turns: int, loosening: bool) -> int:
	if turns <= 0:
		return BOLT_THREADED
	if loosening or turns >= GEARBOX_BOLT_TIGHT:
		return 1 if turns > 1 else 0
	return turns + 1


## Turns one bellhousing bolt to `turns` (0 takes it out, `GEARBOX_BOLT_TIGHT` seats it).
func set_gearbox_bolt(index: int, turns: int) -> void:
	if index < 0 or index >= gearbox_bolts.size() or not has_gearbox():
		return
	gearbox_bolts[index] = clampi(turns, 0, GEARBOX_BOLT_TIGHT)
	_sync_record_from_active()


## Drops the gearbox out of the active car into spare parts. Both bolts must be out.
func remove_gearbox() -> String:
	if not has_gearbox():
		return "There is no transmission in the car."
	for turns in gearbox_bolts:
		if turns > 0:
			return "Take both bolts out first."
	equipped_gearbox_id = NO_GEARBOX_ID
	_sync_record_from_active()
	refresh_car_stats()
	return ""


## Raises a spare gearbox into the empty bellhousing. Its bolts start in, but loose.
func fit_gearbox(gearbox_id: String) -> String:
	if not has_active_car():
		return "There is no car in the garage."
	if has_gearbox():
		return "Take the old transmission out first."
	if free_spare_count("transmission", gearbox_id) <= 0 or listing_by_id(GEARBOXES, gearbox_id).is_empty():
		return "That gearbox is not in spare parts."
	equipped_gearbox_id = gearbox_id
	gearbox_bolts.clear()
	for i in GEARBOX_BOLT_COUNT:
		gearbox_bolts.append(1)
	_sync_record_from_active()
	refresh_car_stats()
	return ""


## Under-car slot a part fits, or "" for a plain bolt-on.
func part_slot(part_id: String) -> String:
	return str(listing_by_id(PARTS, part_id).get("slot", ""))


## The kind of part `slot` takes: the left muffler slot takes mufflers, and the second
## and third carburetor slots take carburetors.
func spot_kind(slot: String) -> String:
	if slot == SLOT_MUFFLER_LEFT:
		return SLOT_MUFFLER
	if slot == SLOT_CARB_2 or slot == SLOT_CARB_3:
		return SLOT_CARB
	return slot


## Whether a part kind goes on under the hood rather than under the car.
func is_hood_kind(kind: String) -> bool:
	return HOOD_SLOTS.has(kind)


func has_dual_exhaust() -> bool:
	return bool(slot_part(SLOT_EXHAUST).get("dual", false))


## The muffler slots the exhaust has: one, or two for a dual exhaust.
func muffler_slots() -> Array[String]:
	if has_dual_exhaust():
		return [SLOT_MUFFLER, SLOT_MUFFLER_LEFT]
	return [SLOT_MUFFLER]


## Slots in use on the active car. The left muffler is there only behind a dual exhaust,
## the manifolds and hood slots only with an engine in, and only as many carburetors as
## the intake takes.
func active_slots() -> Array[String]:
	var out: Array[String] = []
	for slot in UNDER_CAR_SLOTS:
		if slot == SLOT_MUFFLER_LEFT and not has_dual_exhaust():
			continue
		if slot == SLOT_MANIFOLD and not has_engine():
			continue
		out.append(slot)
	out.append(SLOT_TIRES)
	if not has_engine():
		return out
	var carbs := carb_slots()
	for slot in HOOD_SLOTS:
		if not CARB_SLOTS.has(slot) or carbs.has(slot) or (slot == SLOT_CARB and carbs.is_empty()):
			out.append(slot)
	return out


## The part in `slot` on the active car, or {} when the slot is empty.
func slot_part(slot: String) -> Dictionary:
	return listing_by_id(PARTS, str(slot_part_ids.get(slot, NO_PART_ID)))


## Owned parts that could go in `slot` now, in register order. Stock parts never run out.
func spare_slot_parts(slot: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kind := spot_kind(slot)
	var fitted := str(slot_part_ids.get(slot, NO_PART_ID))
	for part in PARTS:
		var part_id := str(part.get("id", ""))
		if str(part.get("slot", "")) != kind or part_id == fitted or not owns_part(part_id):
			continue
		if spare_count(part_id) > 0:
			out.append(part)
	return out


## One line on what a part does, for ads and lists.
func part_detail(part: Dictionary) -> String:
	if part.has("spring_rate"):
		var lower_cm := roundi(float(part.get("lower_m", 0.0)) * 100.0)
		var stiffer := "stock rate" if is_equal_approx(float(part["spring_rate"]), 1.0) else "%d%% stiffer" % roundi((float(part["spring_rate"]) - 1.0) * 100.0)
		return "%s   lowers %s" % [stiffer, short_length_text(lower_cm)] if lower_cm > 0 else stiffer
	if part.has("shock_rate"):
		return "stock damping" if is_equal_approx(float(part["shock_rate"]), 1.0) else "%d%% more damping" % roundi((float(part["shock_rate"]) - 1.0) * 100.0)
	if part.has("accel"):
		return "%d%% more pull · %d%% top speed" % [
			roundi((float(part.get("accel", 1.0)) - 1.0) * 100.0),
			roundi(float(part.get("top_speed", 1.0)) * 100.0),
		]
	var bits: Array[String] = ["Grip %d" % int(part.get("grip", 0)) if part.has("grip") else "+%d hp" % int(part.get("hp", 0))]
	var vmax := int(part.get("vmax", 0))
	if vmax != 0:
		bits.append(speed_change_text(vmax))
	if part.has("cfm"):
		bits.append("%d cfm" % int(part.get("cfm", 0)))
	var carbs := int(part.get("carbs", 0))
	if carbs > 1:
		bits.append("%d %s" % [carbs, "four-barrels" if int(part.get("barrels", 4)) == 4 else "two-barrels"])
	if float(part.get("drift", 1.0)) < 1.0:
		bits.append("holds its timing")
	var loud := float(part.get("loud_db", 0.0))
	if loud >= 3.0:
		bits.append("loud")
	elif loud > 0.0:
		bits.append("a little louder")
	return "   ".join(bits)


## Swaps a spare part into a slot under the active car (its own slot unless `slot` is
## given). What was there goes to spare parts. A single exhaust has no left muffler, so
## fitting one sends that muffler to spare parts too.
func fit_slot_part(part_id: String, slot: String = "") -> String:
	if not has_active_car():
		return "There is no car in the garage."
	var kind := part_slot(part_id)
	if kind.is_empty():
		return "That part does not go under the car."
	if is_hood_kind(kind):
		return "That part goes on under the hood."
	if slot.is_empty():
		slot = kind
	if spot_kind(slot) != kind:
		return "That part does not go there."
	if not owns_part(part_id):
		return "That part is not in spare parts."
	if str(slot_part_ids.get(slot, NO_PART_ID)) == part_id:
		return "Already on the car."
	if kind == SLOT_MANIFOLD and not has_engine():
		return "Put an engine in first."
	if kind == SLOT_TIRES:
		return "Tires go on wheels at the tire machine."
	if kind == SLOT_MUFFLER and slot_part(SLOT_EXHAUST).is_empty():
		return "Put an exhaust on first."
	if slot == SLOT_MUFFLER_LEFT and not has_dual_exhaust():
		return "Only a dual exhaust has a second muffler."
	var part := listing_by_id(PARTS, part_id)
	if spare_count(part_id) <= 0:
		return "That part is on a car, not in spare parts."
	slot_part_ids[slot] = part_id
	if slot == SLOT_EXHAUST and not bool(part.get("dual", false)):
		slot_part_ids[SLOT_MUFFLER_LEFT] = NO_PART_ID
	_sync_record_from_active()
	refresh_car_stats()
	return ""


## Takes the exhaust or a muffler off into spare parts. With the exhaust off the headers
## are open, and the mufflers come off with it; with a muffler off its pipe ends open.
func remove_slot_part(slot: String) -> String:
	if not has_active_car():
		return "There is no car in the garage."
	if slot == SLOT_TIRES:
		return "Tires come off wheels at the tire machine."
	if not REMOVABLE_SLOTS.has(slot) or HOOD_SLOTS.has(slot):
		return "That has to stay on the car."
	if slot_part(slot).is_empty():
		return "There is nothing there to take off."
	slot_part_ids[slot] = NO_PART_ID
	if slot == SLOT_EXHAUST:
		slot_part_ids[SLOT_MUFFLER] = NO_PART_ID
		slot_part_ids[SLOT_MUFFLER_LEFT] = NO_PART_ID
	_sync_record_from_active()
	refresh_car_stats()
	return ""


func buy_or_equip_engine(engine_id: String) -> String:
	return _buy_or_equip(ENGINES, owned_engine_ids, engine_id, "engine")


func buy_or_equip_wheel(wheel_id: String) -> String:
	return _buy_or_equip(WHEELS, owned_wheel_ids, wheel_id, "wheel")


## What the tires on a set of wheels are called, for the lists: the set on the car, or else
## the next spare set of them to come off the shelf.
func wheel_tires_text(wheel_id: String) -> String:
	var tires := slot_part(SLOT_TIRES) if wheel_id == equipped_wheel_id else listing_by_id(PARTS, _next_spare_wheel_tires(wheel_id))
	return "no tires" if tires.is_empty() else "on %s" % str(tires.get("name", "tires"))


## The tires that go too when a spare set of these wheels is sold, or {}. A bare set goes
## first if there is one.
func tires_sold_with_wheels(wheel_id: String) -> Dictionary:
	var sets: Array = spare_wheel_tires.get(wheel_id, [])
	if sets.is_empty() or free_spare_count("wheels", wheel_id) > sets.size():
		return {}
	return listing_by_id(PARTS, _next_spare_wheel_tires(wheel_id))


func _next_spare_wheel_tires(wheel_id: String) -> String:
	var sets: Array = spare_wheel_tires.get(wheel_id, [])
	return "" if sets.is_empty() else str(sets[sets.size() - 1].get("id", ""))


func _pop_spare_wheel_tires(wheel_id: String) -> Dictionary:
	var sets: Array = spare_wheel_tires.get(wheel_id, [])
	if sets.is_empty():
		return {}
	var tires: Dictionary = sets.pop_back()
	if sets.is_empty():
		spare_wheel_tires.erase(wheel_id)
	return tires


## Takes the tires off the active car with their condition: {"id", "c"}, or {} when the
## wheels are bare.
func _tires_off_active_car() -> Dictionary:
	if not has_tires():
		return {}
	var tires := {"id": str(slot_part_ids[SLOT_TIRES]), "c": mount_condition("slot:" + SLOT_TIRES)}
	slot_part_ids[SLOT_TIRES] = NO_PART_ID
	var rec: Variant = car_records.get(current_car_id, null)
	if typeof(rec) == TYPE_DICTIONARY and (rec as Dictionary).has("conditions"):
		(rec["conditions"] as Dictionary).erase("slot:" + SLOT_TIRES)
	return tires


## Puts tires that came on a set of wheels on the active car, keeping their condition.
func _tires_onto_active_car(tires: Dictionary) -> void:
	if tires.is_empty():
		return
	var id := str(tires.get("id", ""))
	slot_part_ids[SLOT_TIRES] = id
	var rec: Variant = car_records.get(current_car_id, null)
	if typeof(rec) == TYPE_DICTIONARY:
		var conditions: Dictionary = (rec as Dictionary).get("conditions", {})
		conditions["slot:" + SLOT_TIRES] = {"kind": "part", "id": id, "c": float(tires.get("c", 1.0))}
		rec["conditions"] = conditions


func _shelve_active_tires() -> void:
	var tires := _tires_off_active_car()
	if tires.is_empty():
		return
	var sets: Array = spare_wheel_tires.get(equipped_wheel_id, [])
	sets.append(tires)
	spare_wheel_tires[equipped_wheel_id] = sets


## Takes the wheels off the active car onto the shelf, with their tires still on them.
func remove_wheels() -> String:
	if not has_wheels():
		return "There are no wheels on the car."
	_shelve_active_tires()
	equipped_wheel_id = NO_WHEEL_ID
	_sync_record_from_active()
	refresh_car_stats()
	return ""


## Wheel sets on the shelf, in register order.
func shelved_wheels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for wheel in WHEELS:
		if free_spare_count("wheels", str(wheel.get("id", ""))) > 0:
			out.append(wheel)
	return out


## The id of the tires on a shelved set of wheels, or "" when it is bare: the next set of
## them to come off the shelf.
func shelved_wheel_tires_id(wheel_id: String) -> String:
	return _next_spare_wheel_tires(wheel_id)


## Whether the tires on a shelved set of wheels are worn enough to blow.
func shelved_wheel_tires_worn(wheel_id: String) -> bool:
	var sets: Array = spare_wheel_tires.get(wheel_id, [])
	return not sets.is_empty() and float(sets[sets.size() - 1].get("c", 1.0)) <= TIRE_BLOWOUT_CONDITION


## The tire machine on a shelved set of wheels: spare tires go on it, and any tires that
## were on it go to spare parts.
func fit_tires_on_shelved_wheels(wheel_id: String, tire_id: String) -> String:
	if free_spare_count("wheels", wheel_id) <= 0:
		return "Those wheels are not on the shelf."
	if part_slot(tire_id) != SLOT_TIRES or spare_count(tire_id) <= 0:
		return "Those tires are not in spare parts."
	var sets: Array = spare_wheel_tires.get(wheel_id, [])
	var bare_set := free_spare_count("wheels", wheel_id) > sets.size()
	if not bare_set and shelved_wheel_tires_id(wheel_id) == tire_id:
		return "Those tires are already on them."
	if not bare_set:
		remove_tires_from_shelved_wheels(wheel_id)
	sets = spare_wheel_tires.get(wheel_id, [])
	sets.append({"id": tire_id, "c": _pop_spare_condition("part", tire_id)})
	spare_wheel_tires[wheel_id] = sets
	_trim_spare_conditions()
	return ""


## The tire machine takes the tires off a shelved set of wheels into spare parts.
func remove_tires_from_shelved_wheels(wheel_id: String) -> String:
	var tires := _pop_spare_wheel_tires(wheel_id)
	if tires.is_empty():
		return "Those wheels have no tires on them."
	_push_spare_condition("part", str(tires.get("id", "")), float(tires.get("c", 1.0)))
	_trim_spare_conditions()
	return ""


func _spare_wheel_tires_from(value: Variant) -> Dictionary:
	var out := {}
	if typeof(value) != TYPE_DICTIONARY:
		return out
	for wheel_id: String in (value as Dictionary).keys():
		if typeof(value[wheel_id]) != TYPE_ARRAY:
			continue
		var sets: Array = []
		for tires: Variant in value[wheel_id]:
			if typeof(tires) == TYPE_DICTIONARY and part_slot(str(tires.get("id", ""))) == SLOT_TIRES:
				sets.append({"id": str(tires["id"]), "c": clampf(float(tires.get("c", 1.0)), CONDITION_FLOOR, 1.0)})
		if not sets.is_empty():
			out[str(wheel_id)] = sets
	return out


func _buy_or_equip(list: Array[Dictionary], owned: Array[String], part_id: String, label: String) -> String:
	var part: Dictionary = listing_by_id(list, part_id)
	if part.is_empty():
		return "That %s is not in the register." % label
	var equipped := equipped_engine_id if label == "engine" else equipped_wheel_id
	if equipped == part_id:
		return "Already on the car."
	# What is on another car stays there, so a copy here has to be a spare.
	if free_spare_count("engine" if label == "engine" else "wheels", part_id) <= 0:
		var price := int(part.get("price", 0))
		if money < price:
			return "Not enough cash."
		money -= price
		owned.append(part_id)
		return ""
	if label == "engine":
		equipped_engine_id = part_id
	else:
		# Tires stay on their wheels: the old tires go to the shelf on the old set, and the
		# new set comes off the shelf with whatever is on it.
		_shelve_active_tires()
		equipped_wheel_id = part_id
		_tires_onto_active_car(_pop_spare_wheel_tires(part_id))
	_sync_record_from_active()
	refresh_car_stats()
	return ""


func set_car_color(next: Color) -> void:
	car_color = next
	_sync_record_from_active()


func set_fuel(amount: float) -> void:
	fuel = clampf(amount, 0.0, DEFAULT_TANK_L)


func commit_fuel() -> void:
	_sync_record_from_active()


## A new car begins between 15 and 30 liters, not on a full tank.
func _starting_fuel() -> float:
	return randf_range(15.0, 30.0)


func race_length_m(race_type: String = "") -> float:
	var kind := selected_race_type if race_type.is_empty() else race_type
	if kind == RACE_ROAD:
		return ROAD_RACE_LENGTH_M
	if kind == RACE_STREET_DRAG:
		return STREET_DRAG_LENGTH_M
	if kind == RACE_MULHOLLAND:
		return MULHOLLAND_LENGTH_M
	if kind == RACE_AQUEDUCT:
		return AQUEDUCT_LENGTH_M
	return QUARTER_MILE_M


## True for a race on a `.trk` course, false for the hardcoded quarter mile.
func race_on_track(race_type: String = "") -> bool:
	var kind := selected_race_type if race_type.is_empty() else race_type
	return kind == RACE_ROAD or race_from_sr2(kind)


## True for Street Rod 2's cruise races, which start with no lights.
func race_from_sr2(race_type: String = "") -> bool:
	var kind := selected_race_type if race_type.is_empty() else race_type
	return kind == RACE_STREET_DRAG or kind == RACE_MULHOLLAND or kind == RACE_AQUEDUCT


## The course file for a race, or "" for the road course's default and the quarter mile.
func race_track_path(race_type: String = "") -> String:
	var kind := selected_race_type if race_type.is_empty() else race_type
	if kind == RACE_STREET_DRAG:
		return STREET_DRAG_TRACK
	if kind == RACE_MULHOLLAND:
		return MULHOLLAND_TRACK % mulholland_course
	if kind == RACE_AQUEDUCT:
		return AQUEDUCT_TRACK
	return ""


func race_fuel_liters(race_type: String = "") -> float:
	var liters := race_length_m(race_type) / 1000.0 * FUEL_L_PER_KM
	return maxf(round(liters), 1.0)


func has_fuel_for_race(race_type: String = "") -> bool:
	return fuel + 0.05 >= race_fuel_liters(race_type)


## Pays or collects `race_stake`, then clears it. Positive means the player won the bet.
func apply_race_stake(player_won: bool) -> int:
	var stake := maxi(race_stake, 0)
	race_stake = 0
	if stake == 0:
		return 0
	if player_won:
		money += stake
		return stake
	var paid := mini(stake, money)
	money -= paid
	return -paid


func cheapest_car_price() -> int:
	var cheapest := -1
	for car in USED_CARS:
		var price := int(car.get("price", 0))
		if price <= 0:
			continue
		if cheapest < 0 or price < cheapest:
			cheapest = price
	return cheapest


func can_buy_a_car() -> bool:
	if owned_car_ids.size() >= MAX_OWNED_CARS:
		return false
	var cheapest := cheapest_car_price()
	return cheapest >= 0 and money >= cheapest


func is_ruined() -> bool:
	return owned_car_ids.is_empty() and not can_buy_a_car()


func finish_run() -> void:
	current_scene_path = SCENE_GARAGE
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(SCENE_GARAGE)


## Moves the raced car when `race_pink_slips` is set, then clears the flag.
## Returns one of the `PINK_*` outcomes. A won car goes straight into the bay.
func apply_pink_slips(player_won: bool) -> int:
	if not race_pink_slips:
		return PINK_NONE
	race_pink_slips = false
	if player_won:
		return PINK_WON if _take_opponent_car() else PINK_KEPT
	_lose_raced_car()
	return PINK_LOST


func _take_opponent_car() -> bool:
	var opp := selected_opponent()
	var model_id := str(opp.get("car_id", ""))
	if listing_by_id(USED_CARS, model_id).is_empty() or owned_car_ids.size() >= MAX_OWNED_CARS:
		return false
	if has_active_car():
		_sync_record_from_active()
	var paint := Color(0.8, 0.1, 0.1)
	var stored: Variant = opp.get("color", null)
	if stored is Color:
		paint = stored
	# A car they took from the player comes back as it left, and any other as they built it.
	var taken: Variant = opp.get("taken_car", null)
	var won_id := ""
	if typeof(taken) == TYPE_DICTIONARY:
		won_id = _add_owned_record((taken as Dictionary).duplicate(true))
	else:
		var parts := opponent_hood_parts(opp)
		parts[SLOT_SPRINGS] = str(opp.get("springs", STOCK_SLOT_PARTS[SLOT_SPRINGS]))
		parts[SLOT_SHOCKS] = str(opp.get("shocks", STOCK_SLOT_PARTS[SLOT_SHOCKS]))
		won_id = _add_owned_car(model_id, paint, str(opponent_tires(opp).get("id", "")), str(opp.get("engine", "")), str(opp.get("gearbox", "")), parts)
	_replace_opponent_car(selected_opponent_id)
	_install_car(won_id)
	return true


func _lose_raced_car() -> void:
	if not has_active_car():
		return
	_sync_record_from_active()
	var lost_id := current_car_id
	var model_id := car_model_id(lost_id)
	# The rival keeps the car as it stands now, its rear end built into the numbers.
	var tires := slot_part(SLOT_TIRES)
	var hood := {}
	for slot in HOOD_SLOTS:
		hood[slot] = str(slot_part_ids.get(slot, NO_PART_ID))
	var taken: Dictionary = (car_records[lost_id] as Dictionary).duplicate(true)
	taken["fuel"] = DEFAULT_TANK_L
	# Tires that blew in this race are replaced, the same as `opponent_tires()` reads them.
	if str(taken["slot_parts"][SLOT_TIRES]) == NO_PART_ID:
		taken["slot_parts"][SLOT_TIRES] = str(STOCK_SLOT_PARTS[SLOT_TIRES])
	var build := {
		"hp": engine_power_hp * final_drive_accel(),
		"engine_hp": engine_power_hp,
		"hood_parts": hood,
		"taken_car": taken,
		"springs": str(slot_part_ids.get(SLOT_SPRINGS, STOCK_SLOT_PARTS[SLOT_SPRINGS])),
		"shocks": str(slot_part_ids.get(SLOT_SHOCKS, STOCK_SLOT_PARTS[SLOT_SHOCKS])),
		"vmax": (vmax_kmh - float(tires.get("vmax", 0.0))) * float(slot_part(SLOT_DIFFERENTIAL).get("top_speed", 1.0)),
		"engine": equipped_engine_id,
		"engine_wait": RIVAL_ENGINE_WAIT_RACES,
		"gearbox": equipped_gearbox_id,
	}
	_set_opponent_car(selected_opponent_id, model_id, car_color, str(tires.get("id", "")), build)
	# What is on the car goes with it. Spares of the same parts stay the player's.
	var spares := _spares_beside(lost_id)
	_drop_active_car()
	_drop_copies_beyond(spares)
	if not owned_car_ids.is_empty():
		_install_car(owned_car_ids[0])


## The active car is destroyed. The bay stays empty even if other cars are owned.
func wreck_active_car() -> void:
	if not has_active_car():
		return
	_drop_active_car()


func _drop_active_car() -> void:
	var before := owned_car_ids.size()
	owned_car_ids.erase(current_car_id)
	car_records.erase(current_car_id)
	current_car_id = ""
	car_spec = {}
	car_name = "No car"
	if before > 0 and owned_car_ids.is_empty():
		_note_cars_gone()


func _note_cars_gone() -> void:
	cars_just_gone = true
	var tree := get_tree()
	var scene := tree.current_scene if tree != null else null
	if scene != null and scene.has_method(&"announce_cars_gone"):
		scene.call(&"announce_cars_gone")


## The garage reads this once, on the visit straight after the last car left.
func take_cars_just_gone() -> bool:
	var show := cars_just_gone
	cars_just_gone = false
	return show


## Pulls the blown engine out of the active car. It is gone, not a spare; what was
## bolted to it or inside it goes to spare parts. On pink slips the car is about to be
## lost, and those parts stay on it and go along.
func remove_engine() -> void:
	if not has_engine():
		return
	var blown := equipped_engine_id
	equipped_engine_id = NO_ENGINE_ID
	if not race_pink_slips:
		_clear_engine_parts(slot_part_ids)
		engine_bolts.clear()
		plug_wires = false
	_sync_record_from_active()
	owned_engine_ids.erase(blown)
	refresh_car_stats()


## Takes off everything that needs an engine. Owned copies off a car are spare parts.
func _clear_engine_parts(slots: Dictionary) -> void:
	slots[SLOT_MANIFOLD] = NO_PART_ID
	for slot in HOOD_SLOTS:
		slots[slot] = NO_PART_ID


## `_clear_engine_parts()` for a car that is not in the bay, with the conditions of what
## came off passed on to the spares.
func _clear_record_engine_parts(rec: Dictionary) -> void:
	var slots := _slots_from(rec.get("slot_parts", null))
	_clear_engine_parts(slots)
	rec["slot_parts"] = slots
	rec["engine_bolts"] = {}
	rec["plug_wires"] = false
	for slot in ALL_SLOTS:
		if str(slots[slot]) == NO_PART_ID:
			_release_condition(rec, "slot:" + slot)


## Gives a rival the player's car, with its numbers in `build`.
func _set_opponent_car(index: int, model_id: String, paint: Color, tires: String, build: Dictionary) -> void:
	if index < 0 or index >= opponents.size():
		return
	var car := listing_by_id(USED_CARS, model_id)
	var opp: Dictionary = opponents[index]
	opp["car_id"] = model_id
	opp["car_name"] = str(car.get("name", "Car"))
	opp["car_file"] = str(car.get("car_file", ""))
	opp["color"] = paint
	opp["tires"] = tires
	opp.merge(build, true)


func _replace_opponent_car(index: int) -> void:
	var opp := opponent_at(index)
	if opp.is_empty():
		return
	_apply_rival_build(opp, _ladder_row(int(opp.get("tier", index))))
	opp["color"] = _random_paint()


func consume_race_fuel(race_type: String = "") -> void:
	set_fuel(fuel - race_fuel_liters(race_type))


func refuel_price() -> int:
	var missing := DEFAULT_TANK_L - fuel
	if missing <= 0.05:
		return 0
	return maxi(int(ceil(missing * float(FUEL_PRICE_PER_L))), 1)


func refuel_tank() -> String:
	var price := refuel_price()
	if price <= 0:
		return "The tank is already full."
	if money < price:
		return "Not enough cash."
	money -= price
	set_fuel(DEFAULT_TANK_L)
	return ""


func select_owned_car(instance_id: String) -> String:
	if not owned_car_ids.has(instance_id):
		return "That car isn't in the garage."
	if current_car_id == instance_id:
		return "Already in the garage."
	if has_active_car() and not has_wheels():
		return NO_WHEELS_IN_BAY
	if has_active_car():
		_sync_record_from_active()
	current_car_id = instance_id
	_install_car(instance_id)
	return ""


func buy_or_select_car(model_id: String) -> String:
	var car: Dictionary = listing_by_id(USED_CARS, model_id)
	if car.is_empty():
		return "That car is not listed."
	if owned_car_ids.size() >= MAX_OWNED_CARS:
		return "The garage holds %d cars." % MAX_OWNED_CARS
	var price := int(car.get("price", 0))
	if money < price:
		return "Not enough cash."
	if has_active_car() and not has_wheels():
		return NO_WHEELS_IN_BAY
	if has_active_car():
		_sync_record_from_active()
	money -= price
	current_car_id = _add_owned_car(model_id, newspaper_color(model_id))
	_install_car(current_car_id)
	return ""


## What a car is worth, as in Street Rod 2: what the paper asks for it, plus the price of
## each part put on it, less the price of each stock part no longer on it. Wear does not
## come into it. A stripped car still has its body, so it never falls below a tenth of
## the paper's price and there is always a price it sells at.
func car_value(instance_id: String) -> int:
	if instance_id == current_car_id:
		_sync_record_from_active()
	var stored: Variant = car_records.get(instance_id, null)
	if typeof(stored) != TYPE_DICTIONARY:
		return 0
	var rec: Dictionary = stored
	var model_id := str(rec.get("model_id", ""))
	var listed := int(listing_by_id(USED_CARS, model_id).get("price", 0))
	var value := listed + _mounts_price(_record_mounts(rec)) - _mounts_price(_stock_mounts(model_id))
	return maxi(value, roundi(listed * 0.1))


## Sells a car for `price`. What is on it goes with it. The bay stays empty if it was the
## car in the bay, even if other cars are owned.
func sell_car(instance_id: String, price: int) -> String:
	if not owned_car_ids.has(instance_id):
		return "That car isn't in the garage."
	var active := instance_id == current_car_id
	if active:
		_sync_record_from_active()
	var spares := _spares_beside(instance_id)
	money += maxi(price, 0)
	if active:
		_drop_active_car()
	else:
		owned_car_ids.erase(instance_id)
		car_records.erase(instance_id)
		if owned_car_ids.is_empty():
			_note_cars_gone()
	_drop_copies_beyond(spares)
	return ""


## How many spares there are now of each thing on a car about to go.
func _spares_beside(instance_id: String) -> Dictionary:
	var spares := {}
	for mount: Array in _record_mounts(car_records.get(instance_id, {})):
		spares[mount] = free_spare_count(mount[0], mount[1])
	return spares


## With the car gone, what was on it no longer counts as owned.
func _drop_copies_beyond(spares: Dictionary) -> void:
	for mount: Array in spares.keys():
		while free_spare_count(mount[0], mount[1]) > int(spares[mount]):
			_owned_list(mount[0]).erase(mount[1])
	_trim_spare_conditions()


## What is on a car record, as [kind, id] pairs, one for each copy.
func _record_mounts(rec: Dictionary) -> Array:
	var out: Array = []
	var engine_id := str(rec.get("engine_id", NO_ENGINE_ID))
	if not engine_id.is_empty() and engine_id != NO_ENGINE_ID:
		out.append(["engine", engine_id])
	var gearbox_id := str(rec.get("gearbox_id", NO_GEARBOX_ID))
	if not gearbox_id.is_empty() and gearbox_id != NO_GEARBOX_ID:
		out.append(["transmission", gearbox_id])
	var wheel_id := str(rec.get("wheel_id", ""))
	if not wheel_id.is_empty() and wheel_id != NO_WHEEL_ID:
		out.append(["wheels", wheel_id])
	var slots: Variant = rec.get("slot_parts", {})
	if typeof(slots) == TYPE_DICTIONARY:
		for part_id: Variant in (slots as Dictionary).values():
			if str(part_id) != NO_PART_ID and not str(part_id).is_empty():
				out.append(["part", str(part_id)])
	for part_id in _string_array(rec.get("part_ids", [])):
		out.append(["part", part_id])
	return out


## What a model comes with, as [kind, id] pairs.
func _stock_mounts(model_id: String) -> Array:
	var gearbox_id := _stock_part_id(model_id, "transmission")
	return _record_mounts({
		"engine_id": _stock_part_id(model_id, "engine"),
		"gearbox_id": gearbox_id if not gearbox_id.is_empty() else DEFAULT_GEARBOX_ID,
		"wheel_id": _stock_part_id(model_id, "wheels"),
		"slot_parts": STOCK_SLOT_PARTS,
	})


func _mounts_price(mounts: Array) -> int:
	var total := 0
	for mount: Array in mounts:
		total += int(listing_for(mount[0], mount[1]).get("price", 0))
	return total


## A new car brings its own copy of everything on it, so spares stay spares.
## A new car in the garage, as it came unless a tire set, engine, or gearbox is named.
func _add_owned_car(model_id: String, paint: Color, tires: String = "", engine: String = "", gearbox: String = "", hood: Dictionary = {}) -> String:
	var rec := _make_car_record(model_id, paint)
	if not tires.is_empty():
		rec["slot_parts"][SLOT_TIRES] = tires
	rec["slot_parts"].merge(hood, true)
	if not listing_by_id(ENGINES, engine).is_empty():
		rec["engine_id"] = engine
	if not listing_by_id(GEARBOXES, gearbox).is_empty():
		rec["gearbox_id"] = gearbox
	return _add_owned_record(rec)


## Adds a car as `rec` has it. Everything on it is owned from now on.
func _add_owned_record(rec: Dictionary) -> String:
	_own_fitted_parts()
	var instance_id := "car-%d" % _next_car_serial
	_next_car_serial += 1
	owned_car_ids.append(instance_id)
	car_records[instance_id] = rec
	for mount: Array in _record_mounts(rec):
		_owned_list(mount[0]).append(mount[1])
	return instance_id


func _install_car(instance_id: String) -> void:
	if instance_id.is_empty() or not car_records.has(instance_id):
		return
	current_car_id = instance_id
	_apply_fields_from_record(instance_id)
	load_player_car()
	_sync_record_from_active()
	refresh_car_stats()


func _make_car_record(model_id: String, paint: Color) -> Dictionary:
	var engine_id := _stock_part_id(model_id, "engine")
	var gearbox_id := _stock_part_id(model_id, "transmission")
	var wheel_id := _stock_part_id(model_id, "wheels")
	if gearbox_id.is_empty():
		gearbox_id = DEFAULT_GEARBOX_ID
	var parts: Array[String] = []
	return {
		"model_id": model_id,
		"color": paint,
		"fuel": DEFAULT_TANK_L,
		"engine_id": engine_id,
		"gearbox_id": gearbox_id,
		"gearbox_bolts": _tight_bolts(),
		"wheel_id": wheel_id,
		"part_ids": parts,
		"slot_parts": STOCK_SLOT_PARTS.duplicate(),
		"engine_bolts": {},
		"plug_wires": true,
		"engine_tune": ENGINE_TUNE_DEFAULT,
	}


func _tight_bolts() -> Array[int]:
	var bolts: Array[int] = []
	for i in GEARBOX_BOLT_COUNT:
		bolts.append(GEARBOX_BOLT_TIGHT)
	return bolts


## Saved bolt turns, or tight bolts for records from before the transmission screen.
func _bolts_from(value: Variant) -> Array[int]:
	var bolts := _tight_bolts()
	if typeof(value) != TYPE_ARRAY:
		return bolts
	var saved: Array = value
	for i in mini(saved.size(), bolts.size()):
		bolts[i] = clampi(int(saved[i]), 0, GEARBOX_BOLT_TIGHT)
	return bolts


## Saved slot parts, with stock parts in any slot the save does not name. Mufflers come
## off with the exhaust, and the left one goes without a dual exhaust.
func _slots_from(value: Variant) -> Dictionary:
	var slots := STOCK_SLOT_PARTS.duplicate()
	if typeof(value) == TYPE_DICTIONARY:
		var saved: Dictionary = value
		for slot in ALL_SLOTS:
			var part_id := str(saved.get(slot, ""))
			# The manifolds are off a car with no engine, or one just put in.
			if part_id == NO_PART_ID and (REMOVABLE_SLOTS.has(slot) or slot == SLOT_MANIFOLD):
				slots[slot] = part_id
			elif str(listing_by_id(PARTS, part_id).get("slot", "")) == spot_kind(slot):
				slots[slot] = part_id
	var exhaust := listing_by_id(PARTS, str(slots[SLOT_EXHAUST]))
	if exhaust.is_empty():
		slots[SLOT_MUFFLER] = NO_PART_ID
	if not bool(exhaust.get("dual", false)):
		slots[SLOT_MUFFLER_LEFT] = NO_PART_ID
	# The intake sits on the heads; carburetors, distributor, and air cleaner sit in the
	# intake, and only as many carburetors as it has pads.
	if str(slots[SLOT_HEADS]) == NO_PART_ID:
		slots[SLOT_INTAKE] = NO_PART_ID
	var intake := listing_by_id(PARTS, str(slots[SLOT_INTAKE]))
	var pads := 0 if intake.is_empty() else clampi(int(intake.get("carbs", 1)), 1, CARB_SLOTS.size())
	for i in CARB_SLOTS.size():
		if i >= pads:
			slots[CARB_SLOTS[i]] = NO_PART_ID
	if intake.is_empty():
		slots[SLOT_DISTRIBUTOR] = NO_PART_ID
		slots[SLOT_AIR_CLEANER] = NO_PART_ID
	# The air cleaner sits on the carburetors, so it needs all of them.
	for i in pads:
		if str(slots[CARB_SLOTS[i]]) == NO_PART_ID:
			slots[SLOT_AIR_CLEANER] = NO_PART_ID
	return slots


## Saved bolt turns under the hood, keyed as `HOOD_BOLT_COUNTS`.
func _hood_bolts_from(value: Variant) -> Dictionary:
	var out := {}
	if typeof(value) != TYPE_DICTIONARY:
		return out
	var saved: Dictionary = value
	for key: String in HOOD_BOLT_COUNTS.keys():
		if typeof(saved.get(key, null)) != TYPE_ARRAY:
			continue
		var bolts: Array[int] = []
		for turns: Variant in saved[key]:
			bolts.append(clampi(int(turns), 0, GEARBOX_BOLT_TIGHT))
		out[key] = bolts
	return out


## Moves slot parts that older saves kept with the bolt-ons into their slots, and
## makes sure whatever is in a slot is owned.
func _settle_slot_parts() -> void:
	var bolt_ons: Array[String] = []
	for part_id in equipped_part_ids:
		var slot := part_slot(part_id)
		if slot.is_empty():
			bolt_ons.append(part_id)
		else:
			slot_part_ids[slot] = part_id
	equipped_part_ids = bolt_ons
	for slot in ALL_SLOTS:
		var part_id := str(slot_part_ids.get(slot, NO_PART_ID))
		if part_id != NO_PART_ID and not owned_part_ids.has(part_id):
			owned_part_ids.append(part_id)


func _stock_part_id(car_id: String, slot: String) -> String:
	var spec := _CarFile.load_path(car_file_path(car_id))
	var errors: Variant = spec.get("errors", [])
	if typeof(errors) == TYPE_ARRAY and not (errors as Array).is_empty():
		return ""
	if slot == "engine":
		var engine: Variant = spec.get("engine", {})
		if typeof(engine) == TYPE_DICTIONARY:
			return str((engine as Dictionary).get("id", ""))
		return ""
	if slot == "transmission":
		var box: Variant = spec.get("transmission", {})
		if typeof(box) == TYPE_DICTIONARY:
			return str((box as Dictionary).get("id", ""))
		return ""
	if slot == "wheels":
		var wheels: Variant = spec.get("wheels", {})
		if typeof(wheels) == TYPE_DICTIONARY:
			return str((wheels as Dictionary).get("part", ""))
	return ""


func _listed_color(car_id: String) -> Color:
	var car: Dictionary = listing_by_id(USED_CARS, car_id)
	var listed: Variant = car.get("color", null)
	if listed is Color:
		return listed
	return Color(0.78, 0.14, 0.14, 1.0)


func _sync_record_from_active() -> void:
	if not has_active_car():
		return
	var rec: Dictionary = {}
	var existing: Variant = car_records.get(current_car_id, null)
	if typeof(existing) == TYPE_DICTIONARY:
		rec = existing
	else:
		var model := car_model_id(current_car_id)
		if model.is_empty():
			model = current_car_id
		rec = _make_car_record(model, car_color)
	var model_id := str(rec.get("model_id", ""))
	if model_id.is_empty():
		model_id = car_model_id(current_car_id)
	if model_id.is_empty():
		model_id = current_car_id
	rec["model_id"] = model_id
	rec["color"] = car_color
	rec["fuel"] = fuel
	rec["engine_id"] = equipped_engine_id
	rec["gearbox_id"] = equipped_gearbox_id
	rec["gearbox_bolts"] = gearbox_bolts.duplicate()
	rec["wheel_id"] = equipped_wheel_id
	rec["part_ids"] = equipped_part_ids.duplicate()
	rec["slot_parts"] = slot_part_ids.duplicate()
	rec["engine_bolts"] = engine_bolts.duplicate(true)
	rec["plug_wires"] = plug_wires
	rec["engine_tune"] = engine_tune
	_settle_conditions(rec)
	car_records[current_car_id] = rec
	_own_fitted_parts()
	_trim_spare_conditions()


func _apply_fields_from_record(instance_id: String) -> void:
	var existing: Variant = car_records.get(instance_id, null)
	if typeof(existing) != TYPE_DICTIONARY:
		var model := car_model_id(instance_id)
		if model.is_empty():
			model = instance_id
		car_records[instance_id] = _make_car_record(model, _listed_color(model))
	var rec: Dictionary = car_records[instance_id]
	var paint: Variant = rec.get("color", car_color)
	if paint is Color:
		car_color = paint
	fuel = float(rec.get("fuel", DEFAULT_TANK_L))
	equipped_engine_id = str(rec.get("engine_id", equipped_engine_id))
	equipped_gearbox_id = str(rec.get("gearbox_id", equipped_gearbox_id))
	gearbox_bolts = _bolts_from(rec.get("gearbox_bolts", null))
	equipped_wheel_id = str(rec.get("wheel_id", equipped_wheel_id))
	equipped_part_ids = _string_array(rec.get("part_ids", []))
	slot_part_ids = _slots_from(rec.get("slot_parts", null))
	_settle_slot_parts()
	slot_part_ids = _slots_from(slot_part_ids)
	if equipped_engine_id == NO_ENGINE_ID:
		_clear_engine_parts(slot_part_ids)
	engine_bolts = _hood_bolts_from(rec.get("engine_bolts", null))
	plug_wires = bool(rec.get("plug_wires", true))
	engine_tune = clampi(int(rec.get("engine_tune", ENGINE_TUNE_DEFAULT)), ENGINE_TUNE_MIN, ENGINE_TUNE_MAX)


func _cars_for_save() -> Dictionary:
	_sync_record_from_active()
	var out := {}
	for raw_id: String in car_records.keys():
		var stored: Variant = car_records[raw_id]
		if typeof(stored) != TYPE_DICTIONARY:
			continue
		out[str(raw_id)] = _record_to_save(stored, car_model_id(str(raw_id)))
	return out


func _record_to_save(rec: Dictionary, model_id: String) -> Dictionary:
	var paint: Color = car_color
	var stored_paint: Variant = rec.get("color", null)
	if stored_paint is Color:
		paint = stored_paint
	var row := {
		"model_id": str(rec.get("model_id", model_id)),
		"color": [paint.r, paint.g, paint.b, paint.a],
		"fuel": float(rec.get("fuel", fuel)),
		"engine_id": str(rec.get("engine_id", "")),
		"gearbox_id": str(rec.get("gearbox_id", "")),
		"gearbox_bolts": _bolts_from(rec.get("gearbox_bolts", null)),
		"wheel_id": str(rec.get("wheel_id", "")),
		"part_ids": _string_array(rec.get("part_ids", [])),
		"slot_parts": _slots_from(rec.get("slot_parts", null)),
		"engine_bolts": _hood_bolts_from(rec.get("engine_bolts", null)),
		"plug_wires": bool(rec.get("plug_wires", true)),
		"engine_tune": int(rec.get("engine_tune", ENGINE_TUNE_DEFAULT)),
	}
	if rec.has("conditions"):
		row["conditions"] = _mount_conditions_from(rec["conditions"])
	return row


func _load_saved_cars(d: Dictionary) -> void:
	car_records.clear()
	var saved: Variant = d.get("cars", null)
	if typeof(saved) == TYPE_DICTIONARY:
		var rows: Dictionary = saved
		for key: String in rows.keys():
			var row: Variant = rows[key]
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var instance_id := _migrate_car_id(str(key))
			var row_d: Dictionary = row
			var model := str(row_d.get("model_id", ""))
			if model.is_empty():
				model = instance_id
			else:
				model = _migrate_car_id(model)
			car_records[instance_id] = _record_from_save(row_d, model)
			_note_instance_serial(instance_id)
	var kept: Array[String] = []
	for car_id in owned_car_ids:
		if not car_records.has(car_id):
			var model := car_model_id(car_id)
			if model.is_empty():
				model = car_id
			if listing_by_id(USED_CARS, model).is_empty():
				continue
			car_records[car_id] = _make_car_record(model, _listed_color(model))
		kept.append(car_id)
		_note_instance_serial(car_id)
	owned_car_ids = kept
	if owned_car_ids.is_empty():
		current_car_id = ""
		return
	if not owned_car_ids.has(current_car_id):
		current_car_id = owned_car_ids[0]
	_apply_fields_from_record(current_car_id)


func _record_from_save(row: Dictionary, model_id: String) -> Dictionary:
	var rec := {
		"model_id": model_id,
		"color": _color_from_save(row.get("color", null), car_color),
		"fuel": float(row.get("fuel", DEFAULT_TANK_L)),
		"engine_id": str(row.get("engine_id", "")),
		"gearbox_id": str(row.get("gearbox_id", "")),
		"gearbox_bolts": _bolts_from(row.get("gearbox_bolts", null)),
		"wheel_id": str(row.get("wheel_id", "")),
		"part_ids": _string_array(row.get("part_ids", [])),
		"slot_parts": _slots_from(row.get("slot_parts", null)),
		"engine_bolts": _hood_bolts_from(row.get("engine_bolts", null)),
		"plug_wires": bool(row.get("plug_wires", true)),
		"engine_tune": clampi(int(row.get("engine_tune", ENGINE_TUNE_DEFAULT)), ENGINE_TUNE_MIN, ENGINE_TUNE_MAX),
	}
	if row.has("conditions"):
		rec["conditions"] = _mount_conditions_from(row["conditions"])
	_move_record_bolt_ons_to_slots(rec)
	if rec["engine_id"] == NO_ENGINE_ID:
		_clear_record_engine_parts(rec)
	return rec


## Older saves keep some parts that now have a slot with the bolt-ons (see
## `_settle_slot_parts()`, the same for the car in the bay). The stock part in that slot
## is only a stand-in and is not owned yet.
func _move_record_bolt_ons_to_slots(rec: Dictionary) -> void:
	var slots: Dictionary = rec["slot_parts"]
	var conditions: Dictionary = rec.get("conditions", {})
	var kept: Array[String] = []
	for part_id in _string_array(rec.get("part_ids", [])):
		var slot := part_slot(part_id)
		if slot.is_empty():
			kept.append(part_id)
			continue
		slots[slot] = part_id
		if conditions.has("bolt:" + part_id):
			conditions["slot:" + slot] = conditions["bolt:" + part_id]
			conditions.erase("bolt:" + part_id)
	rec["part_ids"] = kept


func _note_instance_serial(instance_id: String) -> void:
	if not instance_id.begins_with("car-"):
		return
	var serial := instance_id.substr(4).to_int()
	if serial >= _next_car_serial:
		_next_car_serial = serial + 1


func _color_from_save(value: Variant, fallback: Color) -> Color:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() < 3:
		return fallback
	var nums: Array = value
	var a := 1.0
	if nums.size() >= 4:
		a = float(nums[3])
	return Color(float(nums[0]), float(nums[1]), float(nums[2]), a)


func _migrate_car_id(car_id: String) -> String:
	if car_id == "basic":
		return "corvette-1962"
	if car_id == "vette-1956":
		return DEFAULT_CAR_ID
	return car_id


func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item: Variant in value:
		out.append(str(item))
	return out


## Play the short city drive from one place to another, then open `destination_scene`.
func begin_cruise(from_poi: String, to_poi: String, destination_scene: String) -> void:
	cruise_from_poi = from_poi
	cruise_to_poi = to_poi
	cruise_scene = destination_scene
	current_scene_path = destination_scene
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(SCENE_CRUISE)


func go_to_saved_scene(tree: SceneTree) -> void:
	if is_ruined():
		finish_run()
		return
	var path := current_scene_path
	if path.is_empty() or not ResourceLoader.exists(path):
		path = SCENE_GARAGE
	tree.change_scene_to_file(path)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", _get_fullscreen())
	cfg.set_value("audio", "master_db", AudioServer.get_bus_volume_db(0))
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.set_value("game", "arcade_drive", arcade_drive)
	cfg.set_value("game", "imperial_units", imperial_units)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	if cfg.has_section_key("display", "fullscreen"):
		var fs: bool = cfg.get_value("display", "fullscreen")
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
		)
	if cfg.has_section_key("audio", "master_db"):
		AudioServer.set_bus_volume_db(0, float(cfg.get_value("audio", "master_db")))
	if cfg.has_section_key("audio", "music_enabled"):
		music_enabled = bool(cfg.get_value("audio", "music_enabled"))
	if cfg.has_section_key("game", "arcade_drive"):
		arcade_drive = bool(cfg.get_value("game", "arcade_drive"))
	if cfg.has_section_key("game", "imperial_units"):
		imperial_units = bool(cfg.get_value("game", "imperial_units"))


func toggle_music() -> void:
	set_music_enabled(not music_enabled)


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	save_settings()
	update_music()


func set_arcade_drive(enabled: bool) -> void:
	arcade_drive = enabled
	save_settings()


func set_imperial_units(enabled: bool) -> void:
	imperial_units = enabled
	save_settings()


func speed_text(kmh: float) -> String:
	return "%.0f mph" % (kmh * MILES_PER_KM) if imperial_units else "%.0f km/h" % kmh


## A part's change to top speed. At least 1 either way, so a small gain does not read as none.
func speed_change_text(kmh: int) -> String:
	if not imperial_units:
		return "%+d km/h" % kmh
	var mph := roundi(kmh * MILES_PER_KM)
	if mph == 0 and kmh != 0:
		mph = signi(kmh)
	return "%+d mph" % mph


func mass_text(kg: float) -> String:
	return "%d lb" % roundi(kg * POUNDS_PER_KG) if imperial_units else "%d kg" % int(kg)


func short_length_text(cm: int) -> String:
	return "%.1f in" % (cm * INCHES_PER_CM) if imperial_units else "%d cm" % cm


## Whole liters, or gallons to a tenth, since a race can take less than one.
func fuel_text(liters: float) -> String:
	return "%.1f gal" % (liters * GALLONS_PER_L) if imperial_units else "%.0f L" % liters


## For fuel while it is being pumped, to a tenth in either unit.
func fuel_fine_text(liters: float) -> String:
	return "%.1f gal" % (liters * GALLONS_PER_L) if imperial_units else "%.1f L" % liters


## What is in the tank out of what it holds.
func tank_text(fine: bool = false) -> String:
	if imperial_units:
		return "%.1f / %.1f gal" % [fuel * GALLONS_PER_L, DEFAULT_TANK_L * GALLONS_PER_L]
	return ("%.1f / %.0f L" if fine else "%.0f / %.0f L") % [fuel, DEFAULT_TANK_L]


func race_distance_text(meters: float) -> String:
	return "%.0f ft" % (meters * FEET_PER_M) if imperial_units else "%.1f m" % meters


func long_distance_text(km: float) -> String:
	return "%.1f mi" % (km * MILES_PER_KM) if imperial_units else "%.1f km" % km


func set_music_dimmed(dimmed: bool, dimmed_db: float = -16.0) -> void:
	if _music_player == null:
		return
	_music_player.volume_db = dimmed_db if dimmed else 0.0


func update_music() -> void:
	var scene_path := current_scene_path
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var loaded := tree.current_scene.scene_file_path
		if not loaded.is_empty():
			scene_path = loaded
	var track := _track_for_scene(scene_path)
	if not music_enabled or track.is_empty():
		if _music_player != null:
			_music_player.stop()
		_music_track = ""
		return
	if _music_track == track and _music_player.playing:
		return
	var stream := load(track)
	if stream == null:
		push_warning("Music track missing: " + track)
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music_player.stream = stream
	_music_player.play()
	_music_track = track


func _track_for_scene(path: String) -> String:
	if path == SCENE_RACE:
		return MUSIC_RACE
	return MUSIC_GARAGE


func _get_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
