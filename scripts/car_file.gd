class_name CarFile
extends RefCounted

## Loader for `.car` vehicle files (JSON). A car file names the body mesh,
## wheel mounts, driver seat, and chassis numbers. Engines, transmissions, and
## wheels are ids into the parts register named by `register`.
##
## `driver.position` is the driver's head in car space, same axes as wheel
## mounts: +X left, +Y up from the road, +Z forward.
##
## `cameras` names optional `far`, `close`, `cockpit`, and `bumper` views in
## the same car space (`position`, plus optional `pitch` and `fov` in degrees).
##
## `model.ground_clearance` is how far the body's lowest point sits above the
## floor when it is snapped there, for bodies without wheels of their own.
##
## `make` is who built the car ("GM", "Ford"): its engine must be that make unless the
## car has mounts for another one, and so must its rear end.
##
## `wheels.size` multiplies the size of whatever wheels are fitted, for a car
## whose tires are bigger or smaller than the wheel parts draw them (1 if left out).

const _PartsRegister := preload("res://scripts/parts_register.gd")

const CAMERA_MODES: Array[String] = ["far", "close", "cockpit", "bumper"]
const DEFAULT_CAMERAS: Dictionary = {
	"far": {"position": Vector3(0.0, 2.55, -10.4), "pitch": -14.0, "fov": 68.0},
	"close": {"position": Vector3(0.0, 1.8, -6.1), "pitch": -10.0, "fov": 70.0},
	"cockpit": {"position": Vector3(0.42, 1.23, -0.38), "pitch": -2.0, "fov": 72.0},
	"bumper": {"position": Vector3(0.0, 0.51, 2.95), "pitch": -1.0, "fov": 72.0},
}


static func load_path(path: String) -> Dictionary:
	var empty := _empty_result()
	if path.is_empty():
		empty.errors.append("Car path is empty.")
		return empty
	if not FileAccess.file_exists(path):
		empty.errors.append("Car file not found: %s" % path)
		return empty
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		empty.errors.append("Could not open car file: %s" % path)
		return empty
	var text := file.get_as_text()
	file.close()
	return parse_text(text, path)


static func parse_text(text: String, source: String = "") -> Dictionary:
	var result := _empty_result()
	result.source = source
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		result.errors.append("Invalid JSON in %s (line %d): %s" % [
			source if not source.is_empty() else "<memory>",
			json.get_error_line(),
			json.get_error_message(),
		])
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result.errors.append("Car root must be a JSON object.")
		return result
	var root: Dictionary = json.data
	result.id = str(root.get("id", ""))
	result.name = str(root.get("name", ""))
	result.make = str(root.get("make", ""))
	if result.id.is_empty():
		result.errors.append("Car is missing an id.")
	_parse_model(root, result)
	_parse_wheels(root, result)
	_parse_parts(root, result)
	_parse_chassis(root, result)
	_parse_driver(root, result)
	_parse_cameras(root, result)
	return result


static func _parse_model(root: Dictionary, result: Dictionary) -> void:
	var model: Variant = root.get("model", {})
	if typeof(model) != TYPE_DICTIONARY:
		result.errors.append("Car model must be an object.")
		return
	var body: Dictionary = model
	var path := str(body.get("path", ""))
	if path.is_empty():
		result.errors.append("Car model is missing a path.")
	result.model = {
		"path": path,
		"position": _vec3(body.get("position", [0.0, 0.55, 0.0])),
		"rotation": _vec3(body.get("rotation", [0.0, 0.0, 0.0])),
		"height": float(body.get("height", 5.0)),
		"ground_clearance": float(body.get("ground_clearance", 0.0)),
		# Size of the paint's EGA-style dither squares in meters (car_paint_mask.gdshader); 0 is none.
		"dither_cell": float(body.get("dither_cell", 0.0)),
	}


static func _parse_wheels(root: Dictionary, result: Dictionary) -> void:
	var wheels: Variant = root.get("wheels", {})
	if typeof(wheels) != TYPE_DICTIONARY:
		result.errors.append("Car wheels must be an object.")
		return
	var block: Dictionary = wheels
	var mounts: Variant = block.get("mounts", [])
	if typeof(mounts) != TYPE_ARRAY or (mounts as Array).is_empty():
		result.errors.append("Car wheels need at least one mount.")
		mounts = []
	var parsed: Array[Dictionary] = []
	for item: Variant in mounts:
		if typeof(item) != TYPE_DICTIONARY:
			result.errors.append("A wheel mount must be an object.")
			continue
		var mount: Dictionary = item
		var node := str(mount.get("node", ""))
		if node.is_empty():
			result.errors.append("A wheel mount is missing a node name.")
			continue
		parsed.append({
			"node": node,
			"position": _vec3(mount.get("position", [0.0, 0.0, 0.0])),
			"rotation": _vec3(mount.get("rotation", [0.0, 0.0, 0.0])),
		})
	result.wheels = {
		"path": "",
		"scale": 1.0,
		"height": 0.5,
		"overlay": bool(block.get("overlay", true)),
		"size": float(block.get("size", 1.0)),
		"mounts": parsed,
	}


static func _parse_parts(root: Dictionary, result: Dictionary) -> void:
	var parts: Variant = root.get("parts", {})
	if typeof(parts) != TYPE_DICTIONARY:
		result.errors.append("Car parts must be an object.")
		return
	var block: Dictionary = parts
	var register_path := str(root.get("register", ""))
	result.register = register_path
	if register_path.is_empty():
		result.errors.append("Car is missing a parts register path.")
		return
	var register: Dictionary = _PartsRegister.load_path(register_path)
	var register_errors: Variant = register.get("errors", [])
	if typeof(register_errors) == TYPE_ARRAY:
		for err: String in register_errors:
			result.errors.append(str(err))
	if typeof(register_errors) == TYPE_ARRAY and not (register_errors as Array).is_empty():
		return
	result.engine = _resolve(register, _PartsRegister.ENGINES, block.get("engine", ""), "engine")
	result.transmission = _resolve(register, _PartsRegister.TRANSMISSIONS, block.get("transmission", ""), "transmission")
	var wheel_part := _resolve(register, _PartsRegister.WHEELS, block.get("wheels", ""), "wheels")
	if str(result.engine.get("id", "")).is_empty():
		result.errors.append("Car engine was not found in the parts register.")
	if str(result.transmission.get("id", "")).is_empty():
		result.errors.append("Car transmission was not found in the parts register.")
	if str(wheel_part.get("id", "")).is_empty():
		result.errors.append("Car wheels were not found in the parts register.")
		return
	var wheels: Dictionary = result.wheels
	wheels["path"] = str(wheel_part.get("path", ""))
	wheels["scale"] = float(wheel_part.get("scale", 1.0))
	wheels["height"] = float(wheel_part.get("height", 0.5))
	wheels["part"] = str(wheel_part.get("id", ""))
	if str(wheels.get("path", "")).is_empty():
		result.errors.append("Wheel part '%s' is missing a path." % str(wheel_part.get("id", "")))


static func _resolve(register: Dictionary, category: String, part_id: Variant, label: String) -> Dictionary:
	var id := str(part_id)
	if id.is_empty():
		return {}
	var found: Dictionary = _PartsRegister.find(register, category, id)
	if found.is_empty():
		return {}
	found["id"] = id
	found["slot"] = label
	return found


static func _parse_chassis(root: Dictionary, result: Dictionary) -> void:
	var chassis: Variant = root.get("chassis", {})
	if typeof(chassis) != TYPE_DICTIONARY:
		result.errors.append("Car chassis must be an object.")
		return
	var block: Dictionary = chassis
	result.chassis = {
		"mass": float(block.get("mass", 1360.0)),
		"wheelbase": float(block.get("wheelbase", 2.59)),
		"cg_height": float(block.get("cg_height", 0.48)),
		"front_axle_fraction": float(block.get("front_axle_fraction", 0.46)),
		"max_steer_deg": float(block.get("max_steer_deg", 30.0)),
	}


static func _parse_driver(root: Dictionary, result: Dictionary) -> void:
	var fallback := Vector3(-0.35, 1.05, 0.2)
	var driver: Variant = root.get("driver", null)
	if driver == null:
		result.driver = {"position": fallback}
		return
	if typeof(driver) != TYPE_DICTIONARY:
		result.errors.append("Car driver must be an object.")
		result.driver = {"position": fallback}
		return
	var block: Dictionary = driver
	var pos := fallback
	var raw: Variant = block.get("position", null)
	if raw == null:
		result.errors.append("Car driver is missing a position.")
	elif typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
		result.errors.append("Car driver position must be [x, y, z].")
	else:
		pos = _vec3(raw)
	result.driver = {"position": pos}


static func _default_cameras_copy() -> Dictionary:
	var out: Dictionary = {}
	for mode: String in CAMERA_MODES:
		var def_cam: Dictionary = DEFAULT_CAMERAS[mode]
		out[mode] = {
			"position": def_cam["position"],
			"pitch": float(def_cam["pitch"]),
			"fov": float(def_cam["fov"]),
		}
	return out


static func _parse_cameras(root: Dictionary, result: Dictionary) -> void:
	var parsed := _default_cameras_copy()
	var raw_cameras: Variant = root.get("cameras", null)
	if raw_cameras == null:
		result.cameras = parsed
		return
	if typeof(raw_cameras) != TYPE_DICTIONARY:
		result.errors.append("Car cameras must be an object.")
		result.cameras = parsed
		return
	var block: Dictionary = raw_cameras
	for mode: String in CAMERA_MODES:
		if not block.has(mode):
			continue
		var entry: Variant = block[mode]
		var cam_out: Dictionary = parsed[mode]
		if typeof(entry) == TYPE_ARRAY:
			if (entry as Array).size() < 3:
				result.errors.append("Car camera '%s' position must be [x, y, z]." % mode)
			else:
				cam_out["position"] = _vec3(entry)
		elif typeof(entry) == TYPE_DICTIONARY:
			var cam_dict: Dictionary = entry
			if cam_dict.has("position"):
				var raw_pos: Variant = cam_dict["position"]
				if typeof(raw_pos) != TYPE_ARRAY or (raw_pos as Array).size() < 3:
					result.errors.append("Car camera '%s' position must be [x, y, z]." % mode)
				else:
					cam_out["position"] = _vec3(raw_pos)
			if cam_dict.has("pitch"):
				cam_out["pitch"] = float(cam_dict["pitch"])
			if cam_dict.has("fov"):
				cam_out["fov"] = float(cam_dict["fov"])
		else:
			result.errors.append("Car camera '%s' must be an object or [x, y, z]." % mode)
	result.cameras = parsed


static func _vec3(value: Variant) -> Vector3:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() < 3:
		return Vector3.ZERO
	var nums: Array = value
	return Vector3(float(nums[0]), float(nums[1]), float(nums[2]))


static func _empty_result() -> Dictionary:
	return {
		"source": "",
		"id": "",
		"name": "",
		"make": "",
		"register": "",
		"model": {},
		"wheels": {},
		"engine": {},
		"transmission": {},
		"chassis": {},
		"driver": {},
		"cameras": _default_cameras_copy(),
		"errors": [],
	}
