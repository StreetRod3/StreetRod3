extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Running Mulholland Traffic Tests ---")
	var track_script: Script = load("res://scripts/race_track.gd")
	var car_script: Script = load("res://scripts/race_traffic_car.gd")
	var traf_script: Script = load("res://scripts/mulholland_traffic.gd")

	_test_race_track_dynamic_blocks(track_script)
	_test_race_traffic_car(track_script, car_script)
	_test_mulholland_traffic_manager(track_script, car_script, traf_script)
	_test_traffic_collision_and_boulder_avoidance(track_script, car_script, traf_script)
	_test_opponent_traffic_avoidance(track_script, car_script)
	print("--- All Mulholland Traffic Tests Passed! ---")
	quit()


func _test_race_track_dynamic_blocks(track_script: Script) -> void:
	print("Testing RaceTrack dynamic blocks and lane_around...")
	var track: Node3D = track_script.new()
	track.set("track_path", "res://assets/tracks/mulholland_0.trk")
	root.add_child(track)
	track.call("build_road_course")

	assert(track.call("is_road_course"), "Track should be built")
	var track_len: float = track.call("get_length")
	assert(track_len > 2000.0, "Mulholland track length should be > 2000m")

	# Test dynamic blocks
	var d_blocks: Array[Dictionary] = [
		{"s": 500.0, "to": 510.0, "low": 1.0, "high": 3.0} # blocks lateral [1.0, 3.0]
	]
	track.call("set_dynamic_blocks", d_blocks)

	# Looking forward towards s=505 from s=490 with wanted lane 2.0
	var dodged_forward: float = track.call("lane_around", 490.0, 2.0, 30.0)
	assert(dodged_forward < 0.9 or dodged_forward > 3.1, "Should dodge the dynamic block at lane 2.0")

	# Looking backward towards s=505 from s=520 with wanted lane 2.0
	var dodged_backward: float = track.call("lane_around", 520.0, 2.0, -30.0)
	assert(dodged_backward < 0.9 or dodged_backward > 3.1, "Should dodge the dynamic block in reverse look")

	# Clear dynamic blocks and verify lane returns to normal
	track.call("clear_dynamic_blocks")
	var clear_lane: float = track.call("lane_around", 490.0, 2.0, 30.0)
	assert(is_equal_approx(clear_lane, 2.0), "Without blocks, lane_around should return wanted lane")

	track.free()


func _test_race_traffic_car(track_script: Script, car_script: Script) -> void:
	print("Testing RaceTrafficCar...")
	var track: Node3D = track_script.new()
	track.set("track_path", "res://assets/tracks/mulholland_0.trk")
	root.add_child(track)
	track.call("build_road_course")

	# Test Oncoming car
	var car: CharacterBody3D = car_script.new()
	root.add_child(car)
	car.call("setup", "res://assets/cars/chevy-styleline-1950.car", Color.RED, 300.0, 2.0, 14.0, true)

	assert(car.get("s") == 300.0, "Car track s should be 300.0")
	assert(car.get("is_oncoming"), "Car should be oncoming")
	assert(car.call("get_mass_kg") == 1360.0, "Car mass should be 1360kg")

	# Initial step to position on track
	car.call("step", track, 0.1)
	assert(car.get("s") < 300.0, "Oncoming car s should decrease after step")
	var center_pt: Vector3 = car.call("center")
	var ground_h: float = track.call("surface_height", center_pt)
	assert(absf(center_pt.y - (ground_h + 0.35)) < 0.3, "Car height should match track elevation within pitch tolerance")

	# Test bump reaction
	var old_pos := car.global_position
	car.call("apply_car_bump", Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 2.0), 0.5)
	assert(car.get("loose") > 0.0, "Car should be loose after bump")
	assert(car.global_position.x > old_pos.x, "Car position should have offset applied")

	# Step during loose state
	car.call("step", track, 0.1)
	assert(car.get("loose") < 0.65, "Loose timer should decrease")
	car.free()

	# Test Same-Direction car
	var fwd_car: CharacterBody3D = car_script.new()
	root.add_child(fwd_car)
	fwd_car.call("setup", "res://assets/cars/chevy-styleline-1950.car", Color.BLUE, 300.0, -2.0, 10.0, false)
	assert(not fwd_car.get("is_oncoming"), "Car should be same-direction")
	fwd_car.call("step", track, 0.1)
	assert(fwd_car.get("s") > 300.0, "Same-direction car s should increase after step")
	fwd_car.free()

	track.free()


func _test_mulholland_traffic_manager(track_script: Script, car_script: Script, traf_script: Script) -> void:
	print("Testing MulhollandTraffic manager...")
	var track: Node3D = track_script.new()
	track.set("track_path", "res://assets/tracks/mulholland_0.trk")
	root.add_child(track)
	track.call("build_road_course")

	var dummy_player := CharacterBody3D.new()
	dummy_player.position = Vector3(-2.0, 0.35, 10.0)
	root.add_child(dummy_player)

	var dummy_opponent := CharacterBody3D.new()
	dummy_opponent.position = Vector3(2.0, 0.35, 10.0)
	dummy_opponent.set_script(load("res://scripts/opponent_race_car.gd"))
	dummy_opponent.set("_path_s", 10.0)
	root.add_child(dummy_opponent)

	var traf: Node3D = traf_script.new()
	root.add_child(traf)
	var files: Array[String] = ["res://assets/cars/chevy-styleline-1950.car"]
	traf.call("setup", track, dummy_player, dummy_opponent, null, files)

	# 1. Ticking near start line (s = 10m): no cars should spawn in start safe zone
	traf.call("tick", 0.1)
	var active_cars: Array = traf.get("_active_cars")
	assert(active_cars.is_empty(), "No cars should spawn within start safe zone")

	# 2. Advance player to s = 400m
	var sample_400: Dictionary = track.call("sample_at", 400.0)
	dummy_player.position = sample_400["position"] + sample_400["right"] * -2.0
	dummy_opponent.set("_path_s", 390.0)

	# Tick spawner
	traf.set("_spawn_cooldown", 0.0)
	traf.call("tick", 0.1)
	active_cars = traf.get("_active_cars")
	assert(active_cars.size() >= 1, "Traffic car should spawn ahead of racers")

	var first_car: CharacterBody3D = active_cars[0] as CharacterBody3D
	assert(first_car != null, "Spawned car should exist")
	assert(first_car.get("s") > 400.0, "Spawned car should be ahead of player")

	# Check dynamic blocks on track
	var d_blocks: Array = track.get("_dynamic_blocks")
	assert(not d_blocks.is_empty(), "Track should have dynamic blocks registered")

	# 3. Test despawning
	# Move racers far ahead of the traffic car
	var sample_1200: Dictionary = track.call("sample_at", 1200.0)
	dummy_player.position = sample_1200["position"]
	dummy_opponent.set("_path_s", 1200.0)

	traf.call("tick", 0.1)
	# The first car at ~550m should be despawned now since trail_s is 1200m
	active_cars = traf.get("_active_cars")
	assert(not active_cars.has(first_car), "Car far behind racers should despawn")

	traf.free()
	dummy_player.free()
	dummy_opponent.free()
	track.free()


func _test_traffic_collision_and_boulder_avoidance(track_script: Script, car_script: Script, traf_script: Script) -> void:
	print("Testing traffic collision and avoidance...")
	var track: Node3D = track_script.new()
	track.set("track_path", "res://assets/tracks/mulholland_0.trk")
	root.add_child(track)
	track.call("build_road_course")

	# Test boulder avoidance on oncoming car
	# Put a block at s=250, low=1.0, high=3.0 (blocks oncoming lane at 2.0)
	var d_blocks: Array[Dictionary] = [
		{"s": 248.0, "to": 252.0, "low": 1.0, "high": 3.0}
	]
	track.call("set_dynamic_blocks", d_blocks)

	var car: CharacterBody3D = car_script.new()
	root.add_child(car)
	car.call("setup", "res://assets/cars/chevy-styleline-1950.car", Color.YELLOW, 260.0, 2.0, 12.0, true)
	car.set("lane_bias", 0.0)

	# Step car towards s=250
	for i in 10:
		car.call("step", track, 0.1)

	# Car's lateral should move away from 2.0 to avoid the obstacle
	var current_lateral: float = car.get("lateral")
	assert(current_lateral < 1.0 or current_lateral > 3.0, "Traffic car should steer away from obstacle")

	car.free()
	track.free()


func _test_opponent_traffic_avoidance(track_script: Script, car_script: Script) -> void:
	print("Testing opponent traffic avoidance...")
	var track: Node3D = track_script.new()
	track.set("track_path", "res://assets/tracks/mulholland_0.trk")
	root.add_child(track)
	track.call("build_road_course")

	var opp: CharacterBody3D = CharacterBody3D.new()
	opp.set_script(load("res://scripts/opponent_race_car.gd"))
	opp.position = Vector3(2.0, 0.35, 200.0)
	root.add_child(opp)
	opp.set("_path_s", 200.0)
	opp.set("_lateral", 2.0)
	opp.set("_lane_x", 2.0)
	opp.set("forward_speed", 25.0)

	# 1. No traffic in scene: wanted lane is preserved, no traffic brake
	var clear_lane: float = opp.call("_scan_traffic", track, 2.0)
	assert(is_equal_approx(clear_lane, 2.0), "With no traffic, wanted lane should be preserved")
	assert(not opp.get("_traffic_brake"), "No traffic brake when road is clear")
	assert(is_inf(opp.get("_traffic_speed_cap")), "No speed cap when road is clear")

	# 2. Oncoming traffic ahead in left lane (lateral = 2.0)
	var oncoming_car: CharacterBody3D = car_script.new()
	root.add_child(oncoming_car)
	oncoming_car.call("setup", "res://assets/cars/chevy-styleline-1950.car", Color.RED, 270.0, 2.0, 14.0, true)

	var dodged_lane: float = opp.call("_scan_traffic", track, 2.0)
	assert(is_equal_approx(dodged_lane, -2.0), "Opponent should dodge oncoming car in left lane by picking right lane (-2.0)")

	# If oncoming car is very close (e.g. at 230m vs opponent at 200m in same lane), opponent should brake
	oncoming_car.set("s", 230.0)
	opp.call("_scan_traffic", track, 2.0)
	assert(opp.get("_traffic_brake"), "Opponent should brake when oncoming car is close and in path")
	assert(opp.get("_traffic_speed_cap") < 25.0, "Speed cap should be applied when oncoming car is close")

	oncoming_car.free()

	# 3. Slower same-direction traffic ahead in right lane (lateral = -2.0) while left lane is clear
	opp.set("_lateral", -2.0)
	opp.set("_lane_x", -2.0)
	opp.set("_dodge_ready", false)
	opp.set("forward_speed", 26.0)

	var slow_car: CharacterBody3D = car_script.new()
	root.add_child(slow_car)
	slow_car.call("setup", "res://assets/cars/chevy-styleline-1950.car", Color.BLUE, 235.0, -2.0, 12.0, false)

	var overtake_lane: float = opp.call("_scan_traffic", track, -2.0)
	assert(is_equal_approx(overtake_lane, 2.0), "Opponent should choose left lane (2.0) to overtake slow car")

	# 4. Trapped scenario: slow car in right lane (-2.0) and oncoming traffic in left lane (+2.0)
	var block_oncoming: CharacterBody3D = car_script.new()
	root.add_child(block_oncoming)
	block_oncoming.call("setup", "res://assets/cars/chevy-styleline-1950.car", Color.YELLOW, 260.0, 2.0, 15.0, true)

	# Opponent is at s=200, slow car at s=220 (speed 12), oncoming car at s=260 (speed 15)
	slow_car.set("s", 220.0)
	var trapped_lane: float = opp.call("_scan_traffic", track, -2.0)
	# Because left lane has oncoming traffic, opponent must not overtake into head-on traffic
	assert(trapped_lane < 1.0, "Opponent should not attempt to overtake into oncoming traffic")
	assert(opp.get("_traffic_brake"), "Opponent should brake when trapped behind slower car with oncoming traffic")
	assert(opp.get("_traffic_speed_cap") <= 12.0, "Opponent speed should be capped to slower car's speed")

	# Verify _drive_command applies brake when traffic braking
	var dyn: Node = opp.get("_dynamics")
	dyn.set("cg_velocity", Vector3(0.0, 0.0, 26.0))
	var cmd: Vector3 = opp.call("_drive_command", track, 0.016)
	assert(cmd.z > 0.5, "Drive command should command braking (z > 0.5)")
	assert(cmd.y < 0.5, "Drive command should cut throttle when braking for traffic")

	slow_car.free()
	block_oncoming.free()
	opp.free()
	track.free()
