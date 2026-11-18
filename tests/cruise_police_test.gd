extends SceneTree

const _Police := preload("res://scripts/cruise_police.gd")
const _Ticket := preload("res://scripts/speeding_ticket.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Running Cruise Police Tests ---")
	for path: String in [
		"res://scripts/cruise_police.gd",
		"res://scripts/cruise_traffic.gd",
		"res://scripts/traffic_car.gd",
		"res://scripts/car_bump.gd",
		"res://scripts/cruise.gd",
		"res://scripts/player_race_car.gd",
		"res://scripts/speeding_ticket.gd",
	]:
		var loaded: Script = load(path)
		assert(loaded != null, "Could not parse %s" % path)
	_test_speeding()
	_test_hits()
	_test_pull_over()
	_test_scenes()
	_test_duties()
	_test_roster()
	_test_ticket()
	print("--- All Cruise Police Tests Passed! ---")
	quit()


func _test_speeding() -> void:
	print("Testing speeding heat...")
	var police := _Police.new()
	police.tick(0.9, 20.0, true, false)
	assert(police.heat == 0.0, "A second under the hold does not start heat")
	police.tick(0.2, 20.0, false, false)
	assert(police.heat == 0.0, "Speeding out of sight does not start heat")
	police.tick(0.2, 20.0, true, false)
	assert(police.heat > 0.0, "A cop in sight after the hold starts heat")
	var raised: float = police.heat
	police.tick(5.0, 5.0, true, false)
	assert(is_equal_approx(police.heat, raised), "Under the limit with a cop watching keeps the heat")
	police.heat = 0.4
	police.tick(_Police.LOSE_S, 5.0, false, false)
	assert(is_equal_approx(police.heat, 0.4 - _Police.LOSE_DROP), "Out of sight, the old clear time now drops 5%")


func _test_hits() -> void:
	print("Testing hits...")
	var police := _Police.new()
	police.note_hit(1.0, false)
	assert(police.heat == 0.0, "A brush under the damage line is nothing")
	police.note_hit(3.0, false)
	assert(is_equal_approx(police.heat, _Police.HIT_HEAT), "A real hit adds a chunk with no cop nearby")
	police.note_hit(0.0, true)
	assert(police.heat == 1.0, "Hitting a cop fills the heat")
	police.heat = 0.4
	police.grace = 10.0
	police.tick(2.0, 30.0, true, false)
	assert(is_equal_approx(police.heat, 0.4), "Grace blocks a fresh speeding heat")
	police.note_hit(4.0, false)
	assert(police.heat > 0.4, "A crash during the grace still counts")


func _test_pull_over() -> void:
	print("Testing the pull-over...")
	var police := _Police.new()
	assert(_Police.fine_for(0.0) == _Police.FINE_MIN, "No guilt is the small fine")
	assert(_Police.fine_for(1.0) == _Police.FINE_MAX, "Full guilt is the large fine")
	assert(_Police.fine_for(0.5) == 55, "Half the heat is halfway between the fines")
	police.tick(_Police.SPEED_HOLD_S + 0.1, 20.0, true, false)
	assert(police.heat > 0.0, "Speeding in sight is wanted")
	police.tick(_Police.PULL_HOLD_S, 1.0, true, true)
	var guilt := police.heat
	var speed_stop: Dictionary = police.take_stop(500)
	assert(not bool(speed_stop["broke"]), "Cash covers a speeding fine")
	assert(int(speed_stop["amount"]) == _Police.fine_for(guilt), "The fine follows the heat")
	assert(int(speed_stop["paid"]) == int(speed_stop["amount"]), "Cash pays the whole fine")
	assert(is_equal_approx(float(speed_stop["speed"]), 20.0), "The ticket keeps the speed from the chase")
	assert(police.heat == 0.0, "The stop clears the heat")
	assert(is_equal_approx(police.grace, _Police.GRACE_S), "The stop starts the grace")

	police.note_hit(0.0, true)
	police.tick(_Police.PULL_HOLD_S, 0.5, true, true)
	var broke: Dictionary = police.take_stop(0)
	assert(bool(broke["broke"]), "No cash is a tow")
	assert(int(broke["paid"]) == 0, "A tow takes nothing")
	assert(int(broke["amount"]) == _Police.FINE_MAX, "A cop hit is the full fine")

	police.note_hit(3.0, false)
	police.tick(_Police.PULL_HOLD_S, 0.5, true, true)
	var short: Dictionary = police.take_stop(20)
	assert(int(short["paid"]) == 20, "A short wallet pays what it has")
	assert(not bool(short["broke"]), "Some cash is not a tow")


func _test_scenes() -> void:
	print("Testing scenes...")
	var police := _Police.new()
	police.open_scene(Vector3(0.0, 0.0, 0.0), false, 1)
	police.open_scene(Vector3(4.0, 0.0, 0.0), false, 2)
	assert(police.scenes.size() == 1, "A second hit nearby joins the scene")
	assert((police.scenes[0]["holders"] as Array).size() == 2, "Both cars sit in the one scene")
	police.open_scene(Vector3(2.0, 0.0, 0.0), false, 3)
	assert(bool(police.scenes[0]["hard"]), "A third car makes it a hard scene")
	police.tick_scenes(1.0, {1: true, 2: true, 3: false})
	assert(police.scenes.size() == 1, "One car still sitting keeps the scene")
	police.tick_scenes(1.0, {1: false, 2: false, 3: false})
	assert(police.scenes.is_empty(), "The scene ends once the cars drive off")

	police.open_scene(Vector3(30.0, 0.0, 0.0), false, -1)
	police.tick_scenes(_Police.SCENE_LIFE_S - 1.0, {})
	assert(police.scenes.size() == 1, "A bare scene waits out its timer")
	police.tick_scenes(2.0, {})
	assert(police.scenes.is_empty(), "A bare scene ends when its time is up")


func _test_duties() -> void:
	print("Testing cop duties...")
	var police := _Police.new()
	var cops: Array[Vector3] = [Vector3(10.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0)]
	var calm: Array[int] = police.duties(cops, Vector3(10.0, 0.0, 0.0))
	assert(calm[0] == _Police.PATROL and calm[1] == _Police.PATROL, "No heat and no scene is a patrol")

	police.open_scene(Vector3.ZERO, true, -1)
	var both: Array[int] = police.duties(cops, Vector3(3.0, 0.0, 0.0))
	assert(both[0] == _Police.ATTEND and both[1] == _Police.ATTEND, "A hard scene with no heat calls both cops")
	assert(police.wants_drop(90.0), "A far scene wants a cop moved in")
	police.mark_dropped()
	assert(not police.wants_drop(90.0), "A scene is only dropped into once")

	police.scenes.clear()
	police.heat = 1.0
	var chase: Array[int] = police.duties(cops, Vector3.ZERO)
	assert(chase[0] == _Police.PURSUE and chase[1] == _Police.PURSUE, "Full heat sends both cops")

	police.heat = 0.5
	police.open_scene(Vector3.ZERO, false, 7)
	var split: Array[int] = police.duties(cops, Vector3(200.0, 0.0, 0.0))
	assert(split[0] == _Police.ATTEND, "The cop nearest a scene the player left stays with it")
	assert(split[1] == _Police.PURSUE, "The other cop chases the player who left")


func _test_roster() -> void:
	print("Testing how many cops the heat calls...")
	var police := _Police.new()
	assert(police.cops_for(0.0) == 2, "An empty meter keeps two cars out")
	assert(police.cops_for(0.3) == 2, "Low heat does not call another car")
	assert(police.cops_for(0.5) == 3, "Half heat calls a third car")
	assert(police.cops_for(0.8) == 4, "High heat calls a fourth car")
	assert(police.cops_for(1.0) == _Police.COPS_MAX, "Full heat has five cars out")


func _test_ticket() -> void:
	print("Testing the ticket...")
	var ticket := _Ticket.new() as Control
	root.add_child(ticket)
	ticket.call(&"fill", "Chris Gorecki", 42, 20.0, 11.0, false)
	var name_label := ticket.find_child("DriverName", true, false) as Label
	var fine_label := ticket.find_child("FineAmount", true, false) as Label
	assert(name_label != null and name_label.text == "CHRIS GORECKI", "The ticket uses the license name")
	assert(fine_label != null and fine_label.text == "$42", "The ticket shows the fine")
	ticket.queue_free()
