class_name RadioRegister
extends RefCounted

## Stations for the garage radio, from `assets/music/radio.registry`.
## Songs are a catalog of id and file. A station lists those ids.
## A station with an empty song list plays every song in that catalog.

const SONGS := "songs"
const STATIONS := "stations"
const MEMORY := "memory"
const MUSIC_DIR := "res://assets/music"
const FREQ_MIN := 540.0
const FREQ_MAX := 1600.0
## How close the dial must be, in Hz, before a station comes in.
const TUNE_SLACK := 28.0
const MEMORY_BUTTONS := 5

static var _cache: Dictionary = {}


static func load_path(path: String) -> Dictionary:
	if _cache.has(path):
		var cached: Variant = _cache[path]
		if typeof(cached) == TYPE_DICTIONARY:
			return cached
	var loaded := _read(path)
	_cache[path] = loaded
	return loaded


static func _read(path: String) -> Dictionary:
	var result := _empty()
	result.source = path
	if path.is_empty():
		result.errors.append("Radio registry path is empty.")
		return result
	if not FileAccess.file_exists(path):
		result.errors.append("Radio registry not found: %s" % path)
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Could not open radio registry: %s" % path)
		return result
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		result.errors.append("Invalid JSON in %s (line %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result.errors.append("Radio registry root must be a JSON object.")
		return result
	var root: Dictionary = json.data
	var catalog := _catalog(root.get(SONGS, []), result)
	result.stations = _rows(root.get(STATIONS, []), result, catalog)
	result.memory = _memory(root.get(MEMORY, null), result)
	return result


static func _catalog(value: Variant, result: Dictionary) -> Dictionary:
	var catalog: Dictionary = {}
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Radio registry '%s' must be a list." % SONGS)
		return catalog
	for item: Variant in value as Array:
		if typeof(item) != TYPE_DICTIONARY:
			result.errors.append("A song entry must be an object.")
			continue
		var song: Dictionary = item
		var song_id := str(song.get("id", "")).strip_edges()
		var file := str(song.get("file", "")).strip_edges()
		if song_id.is_empty():
			result.errors.append("A song entry is missing an id.")
			continue
		if catalog.has(song_id):
			result.errors.append("Duplicate song id '%s'." % song_id)
			continue
		if file.is_empty():
			result.errors.append("Song '%s' is missing a file." % song_id)
			continue
		catalog[song_id] = _song_path(file)
	return catalog


static func _rows(value: Variant, result: Dictionary, catalog: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Radio registry '%s' must be a list." % STATIONS)
		return rows
	var seen: Dictionary = {}
	for item: Variant in value as Array:
		if typeof(item) != TYPE_DICTIONARY:
			result.errors.append("A station entry must be an object.")
			continue
		var station: Dictionary = item
		var station_id := str(station.get("id", "")).strip_edges()
		if station_id.is_empty():
			result.errors.append("A station entry is missing an id.")
			continue
		if seen.has(station_id):
			result.errors.append("Duplicate station id '%s'." % station_id)
			continue
		var raw_freq: Variant = station.get("frequency", null)
		if typeof(raw_freq) != TYPE_FLOAT and typeof(raw_freq) != TYPE_INT:
			result.errors.append("Station '%s' needs a frequency." % station_id)
			continue
		var freq := float(raw_freq)
		if freq < FREQ_MIN or freq > FREQ_MAX:
			result.errors.append("Station '%s' frequency %s is outside %d-%d." % [station_id, str(raw_freq), int(FREQ_MIN), int(FREQ_MAX)])
			freq = clampf(freq, FREQ_MIN, FREQ_MAX)
		seen[station_id] = true
		rows.append({
			"id": station_id,
			"frequency": freq,
			"songs": _songs(station.get("songs", []), result, station_id, catalog),
		})
	return rows


## Five dial frequencies, one per memory button. A short or bad list is filled out so every button still has a place to go.
static func _memory(value: Variant, result: Dictionary) -> Array[float]:
	var rows: Array[float] = []
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Radio registry '%s' must be a list of %d frequencies." % [MEMORY, MEMORY_BUTTONS])
	else:
		for item: Variant in value as Array:
			if rows.size() >= MEMORY_BUTTONS:
				result.errors.append("Radio registry '%s' has more than %d frequencies." % [MEMORY, MEMORY_BUTTONS])
				break
			rows.append(_memory_freq(item, result))
		if rows.size() != MEMORY_BUTTONS and (value as Array).size() <= MEMORY_BUTTONS:
			result.errors.append("Radio registry '%s' needs %d frequencies." % [MEMORY, MEMORY_BUTTONS])
	while rows.size() < MEMORY_BUTTONS:
		rows.append(FREQ_MIN)
	return rows


static func _memory_freq(value: Variant, result: Dictionary) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		result.errors.append("A memory frequency must be a number.")
		return FREQ_MIN
	var freq := float(value)
	if freq < FREQ_MIN or freq > FREQ_MAX:
		result.errors.append("Memory frequency %s is outside %d-%d." % [str(value), int(FREQ_MIN), int(FREQ_MAX)])
		return clampf(freq, FREQ_MIN, FREQ_MAX)
	return freq


## Ids from the song catalog. An empty list plays every song in the catalog.
static func _songs(value: Variant, result: Dictionary, station_id: String, catalog: Dictionary) -> Array[String]:
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Station '%s' songs must be a list of song ids." % station_id)
		return _catalog_songs(catalog)
	if (value as Array).is_empty():
		return _catalog_songs(catalog)
	var songs: Array[String] = []
	for item: Variant in value as Array:
		var song_id := str(item).strip_edges()
		if song_id.is_empty():
			continue
		if not catalog.has(song_id):
			result.errors.append("Station '%s' lists unknown song '%s'." % [station_id, song_id])
			continue
		songs.append(str(catalog[song_id]))
	return songs


static func _catalog_songs(catalog: Dictionary) -> Array[String]:
	var songs: Array[String] = []
	for song_id: Variant in catalog.keys():
		songs.append(str(catalog[song_id]))
	return songs


static func _song_path(name: String) -> String:
	if name.begins_with("res://"):
		return name
	return "%s/%s" % [MUSIC_DIR, name.get_file()]


static func _empty() -> Dictionary:
	return {
		"source": "",
		"stations": [],
		"memory": [],
		"errors": [],
	}
