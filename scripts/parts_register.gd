class_name PartsRegister
extends RefCounted

## Catalog of engines, transmissions, wheels, and bolt-on parts.
## `.car` files reference entries by id instead of copying them.
##
## Makes and engine families: an engine has a `make` ("GM", "Ford") and a `family`
## (a key of the register's `families`, each with a name and a make). Parts that bolt to
## an engine have the `family` they fit; transmissions and rear ends have a `make`.
## Anything with neither fits every car.
##
## One entry can stand for a part made for several families or makes: `families` or
## `makes` as a list expands it into a copy for each. The first copy keeps the entry's
## id, so saves that name it still find it; the others are "<id>-<family>", or
## "<id>-<make in lower case>", with the same everything else. Each copy keeps the
## entry's id as `base`.
##
## Bolt-on parts sit in the register under groups (`PART_GROUPS`) so the file reads by
## kind; the groups are only for the file. Loaded, they are one list, `parts`, and each
## entry's `slot` says what it bolts to (the `fuel` group has carburetors and air
## cleaners, `exhaust` has exhausts and mufflers, `suspension` springs and shocks). An id
## must be unique across all the groups.

const ENGINES := "engines"
const TRANSMISSIONS := "transmissions"
const WHEELS := "wheels"
const PARTS := "parts"
const PART_GROUPS: Array[String] = [
	"heads", "intake", "fuel", "ignition", "cam", "tires", "headers", "exhaust",
	"differential", "suspension", "mounts",
]
const FAMILIES := "families"

static var _cache: Dictionary = {}


static func load_path(path: String) -> Dictionary:
	if _cache.has(path):
		var cached: Variant = _cache[path]
		if typeof(cached) == TYPE_DICTIONARY:
			return cached
	var loaded := _read(path)
	_cache[path] = loaded
	return loaded


static func find(register: Dictionary, category: String, part_id: String) -> Dictionary:
	var rows: Variant = register.get(category, [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for item: Variant in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var part: Dictionary = item
		if str(part.get("id", "")) == part_id:
			return part
	return {}


static func _read(path: String) -> Dictionary:
	var result := _empty()
	result.source = path
	if path.is_empty():
		result.errors.append("Parts register path is empty.")
		return result
	if not FileAccess.file_exists(path):
		result.errors.append("Parts register not found: %s" % path)
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Could not open parts register: %s" % path)
		return result
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		result.errors.append("Invalid JSON in %s (line %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result.errors.append("Parts register root must be a JSON object.")
		return result
	var root: Dictionary = json.data
	var families: Variant = root.get(FAMILIES, {})
	if typeof(families) == TYPE_DICTIONARY:
		result.families = families
	else:
		result.errors.append("Parts register 'families' must be an object.")
	result.engines = _rows(root.get(ENGINES, []), ENGINES, result)
	result.transmissions = _rows(root.get(TRANSMISSIONS, []), TRANSMISSIONS, result)
	result.wheels = _rows(root.get(WHEELS, []), WHEELS, result)
	var parts: Array[Dictionary] = []
	var seen_parts: Dictionary = {}
	for group: String in PART_GROUPS:
		parts.append_array(_rows(root.get(group, []), group, result, seen_parts))
	result.parts = parts
	return result


## `seen` holds the ids already taken; groups that load into one list share it.
static func _rows(value: Variant, category: String, result: Dictionary, seen: Dictionary = {}) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Parts register '%s' must be a list." % category)
		return rows
	for item: Variant in value:
		if typeof(item) != TYPE_DICTIONARY:
			result.errors.append("A %s entry must be an object." % category)
			continue
		var part: Dictionary = item
		var part_id := str(part.get("id", ""))
		if part_id.is_empty():
			result.errors.append("A %s entry is missing an id." % category)
			continue
		for copy: Dictionary in _expand(part, part_id, result):
			var copy_id := str(copy["id"])
			if seen.has(copy_id):
				result.errors.append("Duplicate %s id '%s'." % [category, copy_id])
				continue
			seen[copy_id] = true
			rows.append(copy)
	return rows


## The copies an entry stands for: one per family in `families` or make in `makes`, or
## the entry alone.
static func _expand(part: Dictionary, part_id: String, result: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: String in ["families", "makes"]:
		if not part.has(key):
			continue
		var listed: Variant = part[key]
		if typeof(listed) != TYPE_ARRAY or (listed as Array).is_empty():
			result.errors.append("'%s' of '%s' must be a list that is not empty." % [key, part_id])
			return out
		var field := "family" if key == "families" else "make"
		for i: int in (listed as Array).size():
			var value := str((listed as Array)[i])
			var copy: Dictionary = part.duplicate()
			copy.erase(key)
			copy[field] = value
			copy["base"] = part_id
			copy["id"] = part_id if i == 0 else "%s-%s" % [part_id, value.to_lower()]
			out.append(copy)
		return out
	var copy: Dictionary = part.duplicate()
	copy["id"] = part_id
	copy["base"] = part_id
	out.append(copy)
	return out


static func _empty() -> Dictionary:
	return {
		"source": "",
		"engines": [],
		"transmissions": [],
		"wheels": [],
		"parts": [],
		"families": {},
		"errors": [],
	}
