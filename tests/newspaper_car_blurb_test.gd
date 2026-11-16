extends SceneTree

## Used-car ads name the parts the car comes with, and not its power or top speed.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	var cars: Array = state.get("USED_CARS")
	assert(not cars.is_empty())
	for car: Dictionary in cars:
		var car_id := str(car.get("id", ""))
		var names: Array = state.call("stock_part_names", car_id)
		print("%s: %s" % [car_id, ", ".join(names)])
		assert(names.size() > 3)
		assert(not str(names[0]).contains("hp"))
	print("newspaper_car_blurb_test: OK")
	quit()
