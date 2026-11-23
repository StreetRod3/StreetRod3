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
		"res://scripts/speed_sign.gd",
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
	_test_beacons()
	_test_cop_solids()
	_test_unstick()
	_test_pass()
	_test_park_beside()
	_test_steer_limit()
	_test_join()
	_test_zones()
	_test_sign_damage()
	_test_bend_edges()
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
	var legal := _Police.new()
	legal.tick(2.0, 10.0, true, false, 30.0 / 2.2369362920544)
	assert(legal.heat == 0.0, "10 m/s is legal on a 30 mph street")
	var small := _Police.new()
	var small_limit := 20.0 / 2.2369362920544
	small.tick(_Police.SPEED_HOLD_S + 0.1, small_limit + _Police.TOLERANCE_MPS - 0.2, true, false, small_limit)
	assert(small.heat == 0.0, "About 10 mph over a 20 mph street is still tolerated")
	small.tick(_Police.SPEED_HOLD_S + 0.1, small_limit + _Police.TOLERANCE_MPS + 0.5, true, false, small_limit)
	assert(small.heat > 0.0, "More than about 10 mph over the posted limit starts heat")
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
	assert(is_equal_approx(police.heat, _Police.HEAT_RAMPAGE), "Hitting a cop jumps the heat to 150%")
	police.note_hit(4.0, false)
	assert(is_equal_approx(police.heat, _Police.HEAT_RAMPAGE), "A later crash leaves the 150% in place")
	police.tick(_Police.LOSE_S, 5.0, false, false)
	assert(is_equal_approx(police.heat, _Police.HEAT_RAMPAGE - _Police.LOSE_DROP), "That heat then drops by the usual rule")
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
	assert(_Police.fine_for(1.0) == _Police.FINE_MAX * 2, "A full meter doubles the fine")
	assert(_Police.fine_for(_Police.HEAT_RAMPAGE) == _Police.FINE_MAX * 2, "Past a full meter the fine stays doubled")
	assert(_Police.fine_for(0.5) == 55, "Half the heat is halfway between the fines")
	police.tick(_Police.SPEED_HOLD_S + 0.1, 20.0, true, false)
	assert(police.heat > 0.0, "Speeding in sight is wanted")
	police.tick(2.0, 2.0, true, true)
	assert(police.take_stop(500).is_empty(), "Above 3 mph with a cop alongside is not a ticket yet")
	police.tick(0.05, 1.2, true, true)
	var guilt := police.heat
	var speed_stop: Dictionary = police.take_stop(500)
	assert(not bool(speed_stop["broke"]), "Cash covers a speeding fine")
	assert(int(speed_stop["amount"]) == _Police.fine_for(guilt), "The fine follows the heat")
	assert(int(speed_stop["paid"]) == int(speed_stop["amount"]), "Cash pays the whole fine")
	assert(is_equal_approx(float(speed_stop["speed"]), 20.0), "The ticket keeps the speed from the chase")
	assert(police.heat == 0.0, "The stop clears the heat")
	assert(is_equal_approx(police.grace, _Police.GRACE_S), "The stop starts the grace")

	police.note_hit(0.0, true)
	police.tick(0.05, 0.5, true, true)
	var broke: Dictionary = police.take_stop(0)
	assert(bool(broke["broke"]), "No cash is a tow")
	assert(int(broke["paid"]) == 0, "A tow takes nothing")
	assert(int(broke["amount"]) == _Police.fine_for(_Police.HEAT_RAMPAGE), "A cop hit takes the doubled full fine")

	police.note_hit(3.0, false)
	police.tick(0.05, 0.5, true, true)
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
	var stop: Array[int] = police.duties(cops, Vector3.ZERO)
	assert(stop[0] == _Police.STOP and stop[1] == _Police.STOP, "Full heat sends both cops to pull the car over")
	police.tick(_Police.EVADE_S, 5.0, true, false)
	assert(is_equal_approx(police.heat, _Police.HEAT_RAMPAGE), "A stop that fails for a few minutes raises the heat to 150%")
	var chase: Array[int] = police.duties(cops, Vector3.ZERO)
	assert(chase[0] == _Police.PURSUE and chase[1] == _Police.PURSUE, "At 150% the cops use the hard chase")
	assert(police.hud_text(true) == "Heat: 150%  Police", "The meter shows 150%")

	police.heat = 0.5
	police.set(&"_rampage", false)
	police.open_scene(Vector3.ZERO, false, 7)
	var split: Array[int] = police.duties(cops, Vector3(200.0, 0.0, 0.0))
	assert(split[0] == _Police.ATTEND, "The cop nearest a scene the player left stays with it")
	assert(split[1] == _Police.STOP, "The other cop comes to stop the player who left")


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


func _test_beacons() -> void:
	print("Testing the pursuit beacons...")
	var car_script: Script = load("res://scripts/traffic_car.gd")
	var car := car_script.new() as CharacterBody3D
	root.add_child(car)
	car.call(&"setup", "res://assets/cars/police-fairlane-1957.car", Color.WHITE, 0, 0.0, 11.0, 0.0)
	car.call(&"make_cop")
	var roof := car.get_node_or_null("RoofLight") as Node3D
	assert(roof != null and roof.get_child_count() == 0, "No extra lamp sits over the car")
	assert(car.find_child("BeaconRed", true, false) == null, "The beacons do not add a spinning lamp")
	car.set(&"on_duty", true)
	car.call(&"show_call", false, false, 0.2)
	var bar := car.find_child("police_lightbar", true, false) as MeshInstance3D
	var red := bar.get_surface_override_material(2) as StandardMaterial3D
	var blue := bar.get_surface_override_material(3) as StandardMaterial3D
	assert(red != null and blue != null, "The roof domes are the beacons")
	assert(red.emission_energy_multiplier == 0.0 and blue.emission_energy_multiplier == 0.0, "Off a chase both beacons stay dark")
	car.call(&"show_call", true, false, 0.05)
	assert(red.emission_energy_multiplier > 1.0 and blue.emission_energy_multiplier == 0.0, "A chase lights the red beacon first")
	car.call(&"show_call", true, false, 0.2)
	assert(red.emission_energy_multiplier == 0.0 and blue.emission_energy_multiplier > 1.0, "The next blink lights the blue beacon instead")
	car.queue_free()


func _test_cop_solids() -> void:
	print("Testing police stop for cars and buildings...")
	var traffic_script: Script = load("res://scripts/cruise_traffic.gd")
	var traffic := traffic_script.new() as Node3D
	root.add_child(traffic)
	var blocks: Array[Dictionary] = [{"c": Vector2(0.0, 0.0), "h": Vector2(5.0, 5.0)}]
	traffic._blocks = blocks
	var cop := _traffic_car(Vector3(0.0, 0.35, 1.6))
	cop.set(&"shove", Vector3(0.0, 0.0, -10.0))
	traffic.call(&"_keep_solid", cop)
	var shape := cop.get_node("CollisionShape3D") as CollisionShape3D
	assert(shape.global_position.z > 6.9, "A building pushes the police car back out")
	var out: Vector3 = cop.get(&"shove")
	assert(absf(out.z) < 0.05, "The police car stops driving into the building")
	var clear: Array[Dictionary] = []
	traffic._blocks = clear
	var other := _traffic_car(Vector3(0.0, 0.35, 1.1))
	cop.global_position = Vector3(0.0, 0.35, -1.9)
	cop.set(&"shove", Vector3(0.0, 0.0, 12.0))
	var stayed := cop.global_position
	var cars: Array = traffic._cars
	cars.append(cop)
	cars.append(other)
	traffic.call(&"_keep_solid", cop)
	assert(cop.global_position.distance_to(stayed) < 0.05, "Another car is left for the bump to separate")
	var slowed: Vector3 = cop.get(&"shove")
	assert(absf(slowed.z) < 0.05, "The police car stops driving through the other car")
	cop.queue_free()
	other.queue_free()
	traffic.queue_free()


func _test_unstick() -> void:
	print("Testing a chase car stuck across the road...")
	var traffic_script: Script = load("res://scripts/cruise_traffic.gd")
	var traffic := traffic_script.new() as Node3D
	root.add_child(traffic)
	var edges: Array[Dictionary] = [{
		"a": Vector3(0.0, 0.0, -30.0),
		"dir": Vector3(0.0, 0.0, 1.0),
		"length": 60.0,
	}]
	traffic._edges = edges
	var prey := Node3D.new()
	prey.name = "PlayerCar"
	prey.position = Vector3(40.0, 0.0, 0.0)
	root.add_child(prey)
	var cop := _traffic_car(Vector3(-1.9, 0.35, 0.0))
	cop.rotation.y = PI * 0.5
	cop.set(&"stuck_s", 0.9)
	cop.set(&"shove", Vector3.ZERO)
	cop.set(&"edge_i", 0)
	traffic.call(&"_drive_pursuit", cop, 0.2)
	var shove: Vector3 = cop.get(&"shove")
	assert(float(cop.get(&"unstick")) > 0.0, "A sideways stopped chase starts backing up")
	assert(shove.x < -0.4, "The backup is along the nose, off the cars in front")
	cop.set(&"unstick", 0.05)
	var off_before: float = traffic.call(&"_off_street", cop)
	traffic.call(&"_drive_pursuit", cop, 0.2)
	var off_after: float = traffic.call(&"_off_street", cop)
	assert(float(cop.get(&"unstick")) < 0.0, "After the backup the car creeps onto the street")
	assert(off_after < off_before - 0.02, "The creep turns the nose back toward the lane")
	cop.queue_free()
	prey.queue_free()
	traffic.queue_free()


func _test_pass() -> void:
	print("Testing cars pull out of a jam...")
	var traffic_script: Script = load("res://scripts/cruise_traffic.gd")
	var traffic := traffic_script.new() as Node3D
	root.add_child(traffic)
	var edges: Array[Dictionary] = [{
		"a": Vector3(0.0, 0.0, -10.0),
		"b": Vector3(0.0, 0.0, 50.0),
		"dir": Vector3(0.0, 0.0, 1.0),
		"right": Vector3(1.0, 0.0, 0.0),
		"length": 60.0,
		"half": 8.0,
		"lane": 3.5,
	}]
	traffic._edges = edges
	var car := _traffic_car(Vector3(0.0, 0.35, 0.0))
	car.set(&"edge_i", 0)
	car.set(&"along", 12.0)
	car.set(&"next_i", 0)
	car.set(&"speed", 0.0)
	car.set(&"shove", Vector3.ZERO)
	car.set(&"cruise_mps", 11.0)
	car.set(&"wait_s", 11.0)
	car.set(&"wait_for", 10.0)
	var blockers: Array[Dictionary] = [{
		"id": 1,
		"center": Vector3(0.0, 0.0, 8.0),
		"speed": 0.0,
		"ghost": false,
	}]
	traffic.call(&"_drive", car, 0.2, blockers)
	assert(float(car.get(&"pass_s")) > 0.0, "A car that has waited in a jam pulls out")
	var civilian: float = traffic.call(&"_wait_span", car)
	assert(civilian >= 10.0 and civilian <= 30.0, "A civilian waits between ten and thirty seconds")
	car.set(&"cop", true)
	var hurried: float = traffic.call(&"_wait_span", car)
	assert(hurried >= 2.0 and hurried <= 4.0, "Police leave a queue after a couple of seconds")
	var cop := _traffic_car(Vector3(0.0, 0.35, -20.0))
	cop.rotation.y = 0.0
	cop.set(&"cop", true)
	cop.set(&"on_duty", true)
	cop.set(&"duty", 1)
	cop.set(&"speed", 0.0)
	cop.set(&"shove", Vector3.ZERO)
	cop.set(&"edge_i", -1)
	cop.set(&"wait_s", 0.45)
	var stopped := _traffic_car(Vector3(0.0, 0.35, -14.0))
	stopped.set(&"speed", 0.0)
	var cars: Array = traffic._cars
	cars.append(cop)
	cars.append(stopped)
	traffic.call(&"_drive_pursuit", cop, 0.2)
	assert(float(cop.get(&"pass_s")) > 0.0, "A chase swings around a stopped car instead of queueing")
	car.queue_free()
	cop.queue_free()
	stopped.queue_free()
	traffic.queue_free()


func _test_park_beside() -> void:
	print("Testing a chase parks beside a stopped car...")
	var traffic_script: Script = load("res://scripts/cruise_traffic.gd")
	var traffic := traffic_script.new() as Node3D
	root.add_child(traffic)
	var edges: Array[Dictionary] = [{
		"a": Vector3(0.0, 0.0, -40.0),
		"b": Vector3(0.0, 0.0, 40.0),
		"dir": Vector3(0.0, 0.0, 1.0),
		"right": Vector3(1.0, 0.0, 0.0),
		"length": 80.0,
		"half": 8.0,
		"lane": 3.5,
	}]
	traffic._edges = edges
	var stale := root.get_node_or_null("PlayerCar")
	if stale != null:
		stale.free()
	var prey := Node3D.new()
	prey.name = "PlayerCar"
	root.add_child(prey)
	var cop := _traffic_car(Vector3(6.0, 0.35, 0.0))
	cop.rotation.y = 0.0
	cop.set(&"cop", true)
	cop.set(&"on_duty", true)
	cop.set(&"duty", 1)
	cop.set(&"edge_i", 0)
	cop.set(&"shove", Vector3(0.0, 0.0, 20.0))
	var blockers: Array[Dictionary] = []
	for _i in 40:
		traffic.call(&"_drive", cop, 0.2, blockers)
	var at: Vector3 = cop.call(&"center")
	var gap := Vector2(at.x, at.z).length()
	var left: Vector3 = cop.get(&"shove")
	assert(gap < 8.0, "A chase that finds the car stopped waits inside ticket range")
	assert(Vector2(left.x, left.z).length() < 1.5, "The police car stops beside it instead of circling")
	cop.queue_free()
	prey.queue_free()
	traffic.queue_free()


func _test_steer_limit() -> void:
	print("Testing police steering...")
	var traffic_script: Script = load("res://scripts/cruise_traffic.gd")
	var traffic := traffic_script.new() as Node3D
	root.add_child(traffic)
	var stopped: float = traffic.call(&"_yaw_limit", 0.0)
	assert(is_zero_approx(stopped), "A stopped police car does not spin in place")
	var crawling: float = traffic.call(&"_yaw_limit", 1.0)
	var full := tan(deg_to_rad(30.0)) / 3.0
	assert(crawling > 0.05 and crawling <= full + 0.001, "At a crawl the nose turns no harder than 30 degrees of steer")
	traffic.queue_free()


func _test_join() -> void:
	print("Testing a passed cop joins the chase...")
	var traffic_script: Script = load("res://scripts/cruise_traffic.gd")
	var traffic := traffic_script.new() as Node3D
	root.add_child(traffic)
	var police := _Police.new()
	police.heat = 0.4
	traffic._police = police
	var prey := Node3D.new()
	prey.position = Vector3(0.0, 0.0, -1.9)
	root.add_child(prey)
	var near := _traffic_car(Vector3(0.0, 0.35, -1.9))
	var beside := _traffic_car(Vector3(8.0, 0.35, -1.9))
	var far := _traffic_car(Vector3(40.0, 0.35, -1.9))
	var curb := _traffic_car(Vector3(-6.0, 0.35, -1.9))
	for car: CharacterBody3D in [near, beside, far, curb]:
		car.set(&"cop", true)
		car.set(&"on_duty", true)
		car.set(&"edge_i", -1)
	curb.set(&"on_duty", false)
	curb.set(&"parked", true)
	curb.set(&"post", 1)
	var cars: Array = traffic._cars
	cars.append(near)
	cars.append(beside)
	cars.append(far)
	cars.append(curb)
	traffic.call(&"_direct_cops", prey, 0.2)
	assert(int(near.get(&"duty")) == _Police.STOP, "The nearest cop is already chasing")
	assert(int(beside.get(&"duty")) == _Police.STOP, "A police car the player is passing joins the chase")
	assert(int(far.get(&"duty")) == _Police.PATROL, "A police car down the road stays on patrol")
	assert(bool(curb.get(&"on_duty")) and int(curb.get(&"duty")) == _Police.STOP, "A parked police car the player passes pulls out and joins")
	beside.global_position = Vector3(30.0, 0.35, -1.9)
	traffic.call(&"_direct_cops", prey, 0.2)
	assert(int(beside.get(&"duty")) == _Police.STOP, "A cop that joined keeps chasing after the player pulls ahead")
	police.heat = 0.0
	traffic.call(&"_match_roster", prey)
	assert(not bool(curb.get(&"on_duty")), "When the heat is gone the extra car is sent back")
	near.queue_free()
	beside.queue_free()
	far.queue_free()
	curb.queue_free()
	prey.queue_free()
	traffic.queue_free()


func _test_zones() -> void:
	print("Testing speed limit zones...")
	var zones: Script = load("res://scripts/speed_zones.gd")
	assert(zones.mph_of({"speed": 50}) == 50, "The limit is the number on the road")
	assert(zones.mph_of({}) == 30, "A road with no limit marked is the ordinary 30")
	var track_script: Script = load("res://scripts/track_file.gd")
	var city: Dictionary = track_script.load_path("res://assets/maps/city.trk")
	var have := {}
	var paired := {}
	for road: Dictionary in city["roads"]:
		assert(road.has("speed"), "Every city street carries a speed limit")
		var mph := int(road["speed"])
		assert(mph == zones.mph_of(road), "The limit read is the one stored")
		have[mph] = true
		var a_id := int(road["from"])
		var b_id := int(road["to"])
		var key := "%d-%d" % [mini(a_id, b_id), maxi(a_id, b_id)]
		if paired.has(key):
			assert(int(paired[key]) == mph, "Both directions of a street share a limit")
		else:
			paired[key] = mph
	assert(have.has(30) and have.has(40) and have.has(50), "The city map has 30, 40, and 50")
	var traffic_script: Script = load("res://scripts/cruise_traffic.gd")
	var traffic := traffic_script.new() as Node3D
	root.add_child(traffic)
	traffic.call(&"_build_graph", {
		"nodes": {1: {"x": 0.0, "y": 0.0}, 2: {"x": 10.0, "y": 0.0}},
		"roads": [{"from": 1, "to": 2, "width": 8.0, "speed": 50}],
	})
	var posted := float(traffic.call(&"limit_at", Vector3(5.0, 0.0, 0.0)))
	assert(is_equal_approx(posted, 50.0 / 2.2369362920544), "A narrow street keeps the limit written on it")
	traffic.free()
	var cruise_script: Script = load("res://scripts/cruise.gd")
	var cruise := cruise_script.new() as Node3D
	cruise.call(&"_build_speed_signs", city)
	var signs := 0
	for child: Node in cruise.get_children():
		if str(child.name).begins_with("SpeedLimit"):
			signs += 1
	var degree := {}
	for key: Variant in paired:
		var ends := str(key).split("-")
		for end_id: String in ends:
			var id := int(end_id)
			degree[id] = int(degree.get(id, 0)) + 1
	var departures := 0
	for key: Variant in paired:
		var ends := str(key).split("-")
		for end_id: String in ends:
			if int(degree.get(int(end_id), 0)) >= 3:
				departures += 1
	assert(signs == departures, "A sign stands on each way out of a junction")
	var faced := 0
	for child: Node in cruise.get_children():
		if not str(child.name).begins_with("SpeedLimit"):
			continue
		var told := false
		for part: Node in child.find_children("*", "Label3D", true, false):
			var words := part as Label3D
			if not words.text.is_valid_int():
				continue
			assert(have.has(int(words.text)), "The sign shows the limit stored for that road")
			assert(words.position.z < 0.0, "The speed is on the face traffic sees")
			assert(is_equal_approx(words.rotation.y, PI), "The speed faces traffic entering that road")
			told = true
		assert(told, "Each sign tells the limit of its road")
		faced += 1
	assert(faced == signs, "Every speed sign was checked")
	var corner := cruise_script.new() as Node3D
	corner.call(&"_build_speed_signs", {
		"nodes": {1: {"x": 0.0, "y": 0.0}, 2: {"x": 40.0, "y": 0.0}},
		"roads": [
			{"from": 1, "to": 2, "width": 16.0, "speed": 30},
			{"from": 2, "to": 1, "width": 16.0, "speed": 30},
		],
	})
	var plain := 0
	for child: Node in corner.get_children():
		if str(child.name).begins_with("SpeedLimit"):
			plain += 1
	assert(plain == 0, "A bend or a dead end is not a junction")
	var junction := cruise_script.new() as Node3D
	junction.call(&"_build_speed_signs", {
		"nodes": {
			1: {"x": 0.0, "y": 0.0}, 2: {"x": 40.0, "y": 0.0},
			3: {"x": 0.0, "y": 40.0}, 4: {"x": -40.0, "y": 0.0},
		},
		"roads": [
			{"from": 1, "to": 2, "width": 16.0, "speed": 30},
			{"from": 2, "to": 1, "width": 16.0, "speed": 30},
			{"from": 1, "to": 3, "width": 16.0, "speed": 30},
			{"from": 3, "to": 1, "width": 16.0, "speed": 30},
			{"from": 1, "to": 4, "width": 16.0, "speed": 30},
			{"from": 4, "to": 1, "width": 16.0, "speed": 30},
		],
	})
	var on_sidewalk := false
	var at_dead_end := false
	var ways := 0
	for child: Node in junction.get_children():
		if not str(child.name).begins_with("SpeedLimit"):
			continue
		ways += 1
		var at := (child as Node3D).position
		if is_equal_approx(at.x, 11.0) and is_equal_approx(at.z, 9.4):
			on_sidewalk = true
		if at.x > 30.0:
			at_dead_end = true
	assert(ways == 3, "Each street leaving a junction gets a sign")
	assert(on_sidewalk, "Past a crossing, the sign stands on the sidewalk")
	assert(not at_dead_end, "The far end of a street is not a junction")
	var used_model := false
	for child: Node in junction.get_children():
		if child.find_child("part_1", true, false) != null:
			used_model = true
	assert(used_model, "The sign uses the 1970 blank")
	junction.free()
	corner.free()
	cruise.free()


func _test_sign_damage() -> void:
	print("Testing a speed sign taking a hit...")
	var lamp: Script = load("res://scripts/street_lamp.gd")
	var sign_script: Script = load("res://scripts/speed_sign.gd")
	var slow := sign_script.new() as Node3D
	root.add_child(slow)
	slow.call(&"setup", Vector3.ZERO, 0.0, 30)
	var crawl := _HitCar.new()
	crawl.forward_speed = 1.0
	slow.call(&"_on_body_entered", crawl)
	assert(crawl.harm < 0.0, "Brushing a sign at a crawl does nothing")
	var bend := slow.get_node("Bend") as Node3D
	assert(bend.visible, "An untouched sign stays up")
	var nudge := _HitCar.new()
	nudge.forward_speed = 3.0
	slow.call(&"_on_body_entered", nudge)
	assert(is_equal_approx(nudge.harm, float(lamp.get("_BEND_HARM"))), "A slow hit costs the same as a street light")
	assert(is_equal_approx(nudge.lost, 3.0), "A slow hit stops the car")
	assert(not bend.visible, "A slow hit breaks the sign apart")
	assert(_sign_pieces(slow) == 3, "A slow hit leaves the post and the board in pieces")
	var again := _HitCar.new()
	again.forward_speed = 12.0
	slow.call(&"_on_body_entered", again)
	assert(again.harm < 0.0, "A sign takes one hit")
	slow.free()

	var fast := sign_script.new() as Node3D
	root.add_child(fast)
	fast.call(&"setup", Vector3.ZERO, 0.0, 40)
	var hit := _HitCar.new()
	hit.forward_speed = 12.0
	hit.rotation.y = PI * 0.5
	fast.call(&"_on_body_entered", hit)
	assert(is_equal_approx(hit.harm, float(lamp.get("_BREAK_HARM"))), "A fast hit costs the same as breaking a street light")
	assert(is_equal_approx(hit.lost, float(lamp.get("_BREAK_SPEED_LOST"))), "A fast hit only checks the car")
	var down := fast.get_node("Bend") as Node3D
	assert(not down.visible, "A fast hit knocks the sign apart")
	assert(_sign_pieces(fast) == 3, "The post and the board come apart")
	fast.free()


func _sign_pieces(sign: Node) -> int:
	var bits := 0
	for child: Node in sign.get_children():
		if child is MeshInstance3D:
			bits += 1
	return bits


func _test_bend_edges() -> void:
	print("Testing a bend's outer edges...")
	var cruise_script: Script = load("res://scripts/cruise.gd")
	var bend := cruise_script.new() as Node3D
	var built: Array = bend.call(&"_road_meshes", _two_streets(0.0, 40.0, 16.0, 16.0))
	var roads := built[0] as ArrayMesh
	var edges := built[1] as ArrayMesh
	var road_verts := _mesh_verts(roads)
	var edge_verts := _mesh_verts(edges)
	assert(_has_vertex(road_verts, Vector3(-8.0, 0.03, -8.0)), "The outer pavement edges meet past a right-angle bend")
	assert(_has_tri(road_verts, Vector3(0.0, 0.03, 0.0), Vector3(0.0, 0.03, -8.0), Vector3(-8.0, 0.03, 0.0)), "Asphalt fills the wedge back to the node")
	assert(_has_vertex(edge_verts, Vector3(-7.84, 0.05, -7.84)), "The white line follows that corner")
	assert(not _has_vertex(road_verts, Vector3(8.0, 0.03, 8.0)), "The inside of the bend is left to the two streets")
	assert(is_equal_approx(float(bend.call(&"paved_height", Vector3(-7.5, 0.0, -7.5))), 0.03), "The joined corner is paved")
	assert(float(bend.call(&"_nearest_curb", Vector2(-7.5, -7.5))) <= 0.0, "The joined corner is inside the curb")
	bend.free()
	var uneven := cruise_script.new() as Node3D
	var wide: Array = uneven.call(&"_road_meshes", _two_streets(0.0, 40.0, 16.0, 8.0))
	var uneven_verts := _mesh_verts(wide[0] as ArrayMesh)
	assert(_has_vertex(uneven_verts, Vector3(-4.0, 0.03, -8.0)), "Edges of different widths meet on the narrower street")
	assert(_has_tri(uneven_verts, Vector3(0.0, 0.03, 0.0), Vector3(0.0, 0.03, -8.0), Vector3(-4.0, 0.03, 0.0)), "That corner is filled back to the node")
	uneven.free()
	var straight := cruise_script.new() as Node3D
	var flat: Array = straight.call(&"_road_meshes", {
		"nodes": {1: {"x": 0.0, "y": 0.0}, 2: {"x": 40.0, "y": 0.0}, 3: {"x": 80.0, "y": 0.0}},
		"roads": [
			{"from": 1, "to": 2, "width": 16.0},
			{"from": 2, "to": 3, "width": 16.0},
		],
		"poi_order": [],
		"pois": {},
	})
	for vert: Vector3 in _mesh_verts(flat[0] as ArrayMesh):
		assert(absf(vert.z) <= 8.01, "A straight pair of streets grows no corner")
	straight.free()
	var junction := cruise_script.new() as Node3D
	var tee: Array = junction.call(&"_road_meshes", {
		"nodes": {
			1: {"x": 0.0, "y": 0.0}, 2: {"x": 40.0, "y": 0.0},
			3: {"x": 0.0, "y": 40.0}, 4: {"x": -40.0, "y": 0.0},
		},
		"roads": [
			{"from": 1, "to": 2, "width": 16.0},
			{"from": 1, "to": 3, "width": 16.0},
			{"from": 1, "to": 4, "width": 16.0},
		],
		"poi_order": [],
		"pois": {},
	})
	assert(not _has_vertex(_mesh_verts(tee[0] as ArrayMesh), Vector3(-8.0, 0.03, -8.0)), "A junction of three streets is left as it was")
	junction.free()


func _two_streets(ax: float, bx: float, width_a: float, width_b: float) -> Dictionary:
	return {
		"nodes": {1: {"x": 0.0, "y": 0.0}, 2: {"x": bx, "y": ax}, 3: {"x": ax, "y": bx}},
		"roads": [
			{"from": 1, "to": 2, "width": width_a},
			{"from": 1, "to": 3, "width": width_b},
		],
		"poi_order": [],
		"pois": {},
	}


func _mesh_verts(mesh: ArrayMesh) -> PackedVector3Array:
	var arrays: Array = mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]


func _has_vertex(verts: PackedVector3Array, want: Vector3) -> bool:
	for vert: Vector3 in verts:
		if vert.distance_squared_to(want) < 0.0001:
			return true
	return false


func _has_tri(verts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var i := 0
	while i + 2 < verts.size():
		if _near_one(a, verts[i], verts[i + 1], verts[i + 2]) and _near_one(b, verts[i], verts[i + 1], verts[i + 2]) and _near_one(c, verts[i], verts[i + 1], verts[i + 2]):
			return true
		i += 3
	return false


func _near_one(want: Vector3, p: Vector3, q: Vector3, r: Vector3) -> bool:
	return want.distance_squared_to(p) < 0.0001 or want.distance_squared_to(q) < 0.0001 or want.distance_squared_to(r) < 0.0001


func _traffic_car(at: Vector3) -> CharacterBody3D:
	var car_script: Script = load("res://scripts/traffic_car.gd")
	var car := car_script.new() as CharacterBody3D
	root.add_child(car)
	car.call(&"setup", "res://assets/cars/police-fairlane-1957.car", Color.WHITE, 0, 0.0, 11.0, 0.0)
	car.global_position = at
	return car


## A car that only records the hit a sign reports. It has the same method a street light calls.
class _HitCar:
	extends Node3D
	var forward_speed: float = 0.0
	var harm: float = -1.0
	var lost: float = -1.0

	func hit_sawhorse(next_harm: float, speed_lost: float) -> void:
		harm = next_harm
		lost = speed_lost
