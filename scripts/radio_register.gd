class_name RadioRegister
extends RefCounted

## Stations for the garage radio, from `assets/music/radio.registry`.
## Songs are a catalog of id and file. A station lists those ids.
## A station with an empty song list plays every song in that catalog.
## News is a separate catalog. A station plays only the bulletins it lists.
## newsInterval is the minutes from the end of one bulletin to the next. Absent means 15.
## firstNewsAfter is the minutes until the first bulletin. Absent means the same gap. 0 starts the station on news.

const SONGS := "songs"
const NEWS := "news"
const STATIONS := "stations"
const MEMORY := "memory"
const MUSIC_DIR := "res://assets/music"
const NEWS_DIR := "res://assets/music/news"
const FREQ_MIN := 540.0
const FREQ_MAX := 1600.0
## How close the dial must be, in Hz, before a station comes in.
const TUNE_SLACK := 28.0
const MEMORY_BUTTONS := 5
## Minutes from the end of a bulletin to the next one, when a station sets no newsInterval.
const NEWS_EVERY_MINUTES := 15.0
const NEWS_EVERY := NEWS_EVERY_MINUTES * 60.0

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
	var catalog := _catalog(root.get(SONGS, []), result, SONGS, MUSIC_DIR)
	var news := _catalog(root.get(NEWS, []), result, NEWS, NEWS_DIR)
	result.stations = _rows(root.get(STATIONS, []), result, catalog, news)
	result.memory = _memory(root.get(MEMORY, null), result)
	return result


static func _catalog(value: Variant, result: Dictionary, label: String, folder: String) -> Dictionary:
	var catalog: Dictionary = {}
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Radio registry '%s' must be a list." % label)
		return catalog
	for item: Variant in value as Array:
		if typeof(item) != TYPE_DICTIONARY:
			result.errors.append("A %s entry must be an object." % _singular(label))
			continue
		var song: Dictionary = item
		var song_id := str(song.get("id", "")).strip_edges()
		var file := str(song.get("file", "")).strip_edges()
		if song_id.is_empty():
			result.errors.append("A %s entry is missing an id." % _singular(label))
			continue
		if catalog.has(song_id):
			result.errors.append("Duplicate %s id '%s'." % [_singular(label), song_id])
			continue
		if file.is_empty():
			result.errors.append("%s '%s' is missing a file." % [_singular(label).capitalize(), song_id])
			continue
		catalog[song_id] = _media_path(folder, file)
	return catalog


static func _rows(value: Variant, result: Dictionary, catalog: Dictionary, news: Dictionary) -> Array[Dictionary]:
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
		var news_every := _news_interval(station.get("newsInterval", null), result, station_id)
		rows.append({
			"id": station_id,
			"frequency": freq,
			"songs": _songs(station.get("songs", []), result, station_id, catalog),
			"news": _news(station.get("news", null), result, station_id, news),
			"news_interval": news_every,
			"first_news": _first_news(station.get("firstNewsAfter", null), result, station_id, news_every),
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


## Minutes in the registry, seconds here. A missing first bulletin uses the station's news interval. 0 starts on news.
static func _first_news(value: Variant, result: Dictionary, station_id: String, every: float) -> float:
	if value == null:
		return every
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		result.errors.append("Station '%s' firstNewsAfter must be a number of minutes." % station_id)
		return every
	var minutes := float(value)
	if minutes < 0.0:
		result.errors.append("Station '%s' firstNewsAfter cannot be negative." % station_id)
		return every
	return minutes * 60.0


## Minutes in the registry, seconds here. A missing interval stays at `NEWS_EVERY`.
static func _news_interval(value: Variant, result: Dictionary, station_id: String) -> float:
	if value == null:
		return NEWS_EVERY
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		result.errors.append("Station '%s' newsInterval must be a number of minutes." % station_id)
		return NEWS_EVERY
	var minutes := float(value)
	if minutes < 0.0:
		result.errors.append("Station '%s' newsInterval cannot be negative." % station_id)
		return NEWS_EVERY
	return minutes * 60.0


## Ids from the news catalog. No list, or an empty one, means the station has no news.
static func _news(value: Variant, result: Dictionary, station_id: String, catalog: Dictionary) -> Array[String]:
	if value == null:
		return []
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Station '%s' news must be a list of news ids." % station_id)
		return []
	var bulletins: Array[String] = []
	for item: Variant in value as Array:
		var news_id := str(item).strip_edges()
		if news_id.is_empty():
			continue
		if not catalog.has(news_id):
			result.errors.append("Station '%s' lists unknown news '%s'." % [station_id, news_id])
			continue
		bulletins.append(str(catalog[news_id]))
	return bulletins


static func _media_path(folder: String, name: String) -> String:
	if name.begins_with("res://"):
		return name
	return "%s/%s" % [folder, name.get_file()]


static func _singular(label: String) -> String:
	if label == NEWS:
		return "news"
	if label.ends_with("s"):
		return label.substr(0, label.length() - 1)
	return label


static func _empty() -> Dictionary:
	return {
		"source": "",
		"stations": [],
		"memory": [],
		"errors": [],
	}
