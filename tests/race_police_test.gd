extends SceneTree

const _Police := preload("res://scripts/race_police.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Running Race Police Tests ---")
	for path: String in [
		"res://scripts/race_police.gd",
		"res://scripts/road_race_police.gd",
		"res://scripts/mulholland_traffic.gd",
		"res://scripts/race_traffic_car.gd",
		"res://scripts/race.gd",
	]:
		var loaded: Script = load(path)
		assert(loaded != null, "Could not parse %s" % path)
	_test_roll()
	_test_traffic_ticket()
	_test_pass()
	_test_chase()
	_test_pace()
	_test_road_car()
	_test_mulholland_cop()
	print("--- All Race Police Tests Passed! ---")
	quit()


func _test_roll() -> void:
	print("Testing the chance of a cop...")
	assert(_Police.rolled_in(0.0), "A roll of 0 brings a cop")
	assert(_Police.rolled_in(0.149), "Just under 15% brings a cop")
	assert(not _Police.rolled_in(0.15), "15% and up is a race with no cop")
	assert(not _Police.rolled_in(0.9), "A high roll is a race with no cop")


func _test_traffic_ticket() -> void:
	print("Testing a cop in traffic...")
	var police := _Police.new()
	police.arm_traffic()
	assert(not police.note_beside(3.0, 20.0, 0.0), "Passing a traffic cop at speed is not a ticket")
	assert(not police.ticketed, "The race is still on")
	assert(not police.note_beside(3.0, 20.0, 1.0), "A brush under the damage line is nothing")
	assert(police.note_beside(30.0, 40.0, 3.0), "A real hit on the cop is a ticket")
	assert(police.ticketed, "The hit closed the race")

	var stopped := _Police.new()
	stopped.arm_traffic()
	assert(not stopped.note_beside(12.0, 0.5, 0.0), "Stopped, but the cop is not alongside")
	assert(stopped.note_beside(4.0, 1.0, 0.0), "Stopped alongside the cop is a ticket")


func _test_pass() -> void:
	print("Testing the parked cop...")
	var police := _Police.new()
	police.arm_parked()
	assert(not police.note_pass(100.0, 400.0), "Still well behind, so the cop stays parked")
	assert(not police.pursuing, "The cop has not pulled out")
	assert(police.note_pass(410.0, 400.0), "Driving past the parked cop starts the chase")
	assert(police.pursuing, "The cop is chasing")

	var late := _Police.new()
	late.arm_parked()
	assert(not late.note_pass(500.0, 400.0), "Already past, with no approach, is not a pass")
	assert(not late.pursuing, "The cop stays parked when the car was never behind it")


func _test_chase() -> void:
	print("Testing the chase ticket...")
	var police := _Police.new()
	police.arm_parked()
	police.note_pass(10.0, 100.0)
	police.note_pass(120.0, 100.0)
	assert(not police.note_chase(40.0, 30.0, 80.0, 120.0, 2.0, 0.0), "Well behind is not a ticket yet")
	assert(not police.note_chase(5.0, 30.0, 90.0, 120.0, 1.0, 0.0), "Close, but still too far behind to be level")
	assert(police.note_chase(5.0, 30.0, 118.0, 120.0, _Police.CATCH_S, 0.0), "Level for a moment is a ticket")

	var hit := _Police.new()
	hit.arm_parked()
	hit.note_pass(10.0, 100.0)
	hit.note_pass(110.0, 100.0)
	assert(hit.note_chase(20.0, 30.0, 90.0, 110.0, 0.1, 4.0), "Hitting the chasing cop is a ticket")

	var crawl := _Police.new()
	crawl.arm_parked()
	crawl.note_pass(10.0, 100.0)
	crawl.note_pass(110.0, 100.0)
	assert(crawl.note_chase(4.0, 1.0, 90.0, 110.0, 0.05, 0.0), "Stopped with the cop alongside is a ticket")


func _test_pace() -> void:
	print("Testing the chase pace...")
	assert(is_equal_approx(_Police.pace_for(100.0, 160.0, 40.0), _Police.chase_mps(40.0)), "Well behind, the cop speeds up")
	assert(is_equal_approx(_Police.pace_for(150.0, 160.0, 40.0), 40.0), "Drawing level, the cop matches the car")
	assert(is_equal_approx(_Police.pace_for(180.0, 160.0, 40.0), 11.0), "Ahead, the cop eases off and waits")
	assert(_Police.chase_mps(10.0) == _Police.PURSUE_MIN_MPS, "A slow car is still chased at the minimum")
	assert(_Police.chase_mps(80.0) == _Police.PURSUE_CAP_MPS, "The chase has a top speed")


func _test_road_car() -> void:
	print("Testing the parked car on the road course...")
	var track_script: Script = load("res://scripts/race_track.gd")
	var track: Node3D = track_script.new()
	track.set("track_path", "res://assets/tracks/track1.trk")
	root.add_child(track)
	track.call("build_road_course")
	var length: float = track.call("get_length")

	var quiet_script: Script = load("res://scripts/road_race_police.gd")
	var quiet: Node3D = quiet_script.new()
	root.add_child(quiet)
	var player := CharacterBody3D.new()
	root.add_child(player)
	assert(not bool(quiet.call("setup", track, player, null, 0.2)), "A roll past 15% leaves the shoulder empty")

	var cops: Node3D = quiet_script.new()
	root.add_child(cops)
	assert(bool(cops.call("setup", track, player, null, 0.0)), "A roll under 15% parks a cop")
	var at: float = cops.call("cop_s")
	assert(absf(at - length * 0.5) < 5.0, "The cop is parked about halfway")
	var lateral: float = cops.call("cop_lateral")
	assert(lateral < -6.0, "The cop sits off on the shoulder, not in the racing line")
	assert(not bool(cops.call("police_pursuing")), "The cop waits until the car goes past")

	var behind: Dictionary = track.call("sample_at", at - 40.0)
	player.global_position = behind.get("position", Vector3.ZERO)
	cops.call("tick", 0.1)
	assert(not bool(cops.call("police_pursuing")), "Behind the cop, it stays parked")
	var ahead: Dictionary = track.call("sample_at", at + 15.0)
	player.global_position = ahead.get("position", Vector3.ZERO)
	cops.call("tick", 0.1)
	assert(bool(cops.call("police_pursuing")), "Passing the cop sends it after the car")

	player.free()
	cops.free()
	quiet.free()
	track.free()


func _test_mulholland_cop() -> void:
	print("Testing a cop in Mulholland traffic...")
	var track_script: Script = load("res://scripts/race_track.gd")
	var track: Node3D = track_script.new()
	track.set("track_path", "res://assets/tracks/mulholland_0.trk")
	root.add_child(track)
	track.call("build_road_course")

	var traf_script: Script = load("res://scripts/mulholland_traffic.gd")
	var plain: Node3D = traf_script.new()
	root.add_child(plain)
	var player := CharacterBody3D.new()
	root.add_child(player)
	var files: Array[String] = ["res://assets/cars/chevy-styleline-1950.car"]
	plain.call("setup", track, player, null, null, files, 0.9)
	assert(not bool(plain.call("police_due")), "A high roll means ordinary traffic only")

	var traf: Node3D = traf_script.new()
	root.add_child(traf)
	traf.call("setup", track, player, null, null, files, 0.0)
	assert(bool(traf.call("police_due")), "A low roll puts one cop in the traffic")
	var sample: Dictionary = track.call("sample_at", 400.0)
	player.global_position = sample.get("position", Vector3.ZERO)
	var cop: Node = null
	for _i in 40:
		traf.call("tick", 0.3)
		cop = traf.call("police_cop")
		if cop != null:
			break
	assert(cop != null, "The cop spawns with the other traffic")
	assert(bool(cop.get("cop")), "The spawned car is the police car")
	assert(not bool(traf.call("police_ticketed")), "Driving in the stream has not written a ticket")

	player.free()
	traf.free()
	plain.free()
	track.free()
